# Qisutu - Open Source Ticket System
# Copyright (C) 2026 Franziska Steps
# SPDX-License-Identifier: AGPL-3.0-or-later

package QisutuKnowledgeBase;

use strict;
use warnings;
use utf8;

use QisutuHTML;
use QisutuSystemSetting;

sub new {
    my ( $Class, %Param ) = @_;

    my $Self = {
        Config    => $Param{Config},
        DB        => $Param{DB},
        Output    => $Param{Output},
        LastError => '',
    };

    bless $Self, $Class;
    return $Self;
}

sub Error {
    my ($Self) = @_;
    return $Self->{LastError} || '';
}

sub PermissionLevel {
    my ( $Self, %Param ) = @_;

    my $User   = $Param{User} || {};
    my $UserID = $User->{user_account_id} || 0;
    return { View => 0, Edit => 0, Publish => 0, Admin => 0 }
        if ( $User->{account_type} || '' ) ne 'agent' || !$UserID;
    return { View => 1, Edit => 1, Publish => 1, Admin => 0 };
}

sub CategoryList {
    my ( $Self, %Param ) = @_;

    my $Language        = $Self->_LanguageClean( $Param{Language} );
    my $DefaultLanguage = $Self->_LanguageClean( $Self->{Config}->{Language}->{Default} || 'en' );
    my $Where           = $Param{IncludeInactive} ? '' : 'WHERE c.active = 1';

    my $Rows = $Self->{DB}->SelectAll(
        'SELECT c.id, c.parent_id, c.internal_name, c.active, c.sort_order,
                COALESCE(NULLIF(current_t.name, ""), NULLIF(default_t.name, ""), c.internal_name) AS name,
                COALESCE(current_t.description, default_t.description, "") AS description,
                parent.internal_name AS parent_internal_name,
                COALESCE(NULLIF(parent_current.name, ""), NULLIF(parent_default.name, ""), parent.internal_name, "") AS parent_name,
                COUNT(DISTINCT a.id) AS article_count
         FROM knowledge_category c
         LEFT JOIN knowledge_category_translation current_t ON current_t.category_id = c.id AND current_t.language = ?
         LEFT JOIN knowledge_category_translation default_t ON default_t.category_id = c.id AND default_t.language = ?
         LEFT JOIN knowledge_category parent ON parent.id = c.parent_id
         LEFT JOIN knowledge_category_translation parent_current ON parent_current.category_id = parent.id AND parent_current.language = ?
         LEFT JOIN knowledge_category_translation parent_default ON parent_default.category_id = parent.id AND parent_default.language = ?
         LEFT JOIN knowledge_article a ON a.category_id = c.id
         ' . $Where . '
         GROUP BY c.id, c.parent_id, c.internal_name, c.active, c.sort_order,
                  current_t.name, default_t.name, current_t.description, default_t.description,
                  parent.internal_name, parent_current.name, parent_default.name
         ORDER BY COALESCE(parent.sort_order, c.sort_order), parent.id, c.sort_order, name, c.id',
        $Language, $DefaultLanguage, $Language, $DefaultLanguage,
    );

    if ( !defined $Rows ) {
        $Self->{LastError} = $Self->{DB}->Error() || 'Knowledge categories could not be loaded';
        return [];
    }

    for my $Row ( @{$Rows} ) {
        $Row->{display_name} = $Row->{parent_name} ? $Row->{parent_name} . ' / ' . $Row->{name} : $Row->{name};
    }

    return $Rows;
}

sub CategoryGet {
    my ( $Self, %Param ) = @_;

    my $CategoryID = $Self->_ID( $Param{CategoryID} );
    return if !$CategoryID;

    my $Category = $Self->{DB}->SelectRow(
        'SELECT id, parent_id, internal_name, active, sort_order, created_at, changed_at
         FROM knowledge_category WHERE id = ? LIMIT 1',
        $CategoryID,
    );
    return if !$Category;

    $Category->{translations} = $Self->{DB}->SelectAll(
        'SELECT language, name, description
         FROM knowledge_category_translation
         WHERE category_id = ? ORDER BY language',
        $CategoryID,
    ) || [];

    return $Category;
}

sub CategorySave {
    my ( $Self, %Param ) = @_;

    my $CategoryID  = $Self->_ID( $Param{CategoryID} );
    my $ParentID    = $Self->_ID( $Param{ParentID} );
    my $Internal    = $Self->_Trim( $Param{InternalName} );
    my $SortOrder   = $Param{SortOrder} || 1000;
    my $Active      = exists $Param{Active} ? ( $Param{Active} ? 1 : 0 ) : 1;
    my $UserID      = $Self->_ID( $Param{ChangedByUserID} ) || 1;
    my $Translations = $Param{Translations} || {};

    if ( !$Internal || $Internal !~ m{\A[A-Za-z0-9][A-Za-z0-9_.-]{0,189}\z} ) {
        $Self->{LastError} = 'Translate:KnowledgeCategoryInternalNameInvalid';
        return;
    }
    $SortOrder = 1000 if $SortOrder !~ m{\A\d+\z};
    if ( $CategoryID && $ParentID == $CategoryID ) {
        $Self->{LastError} = 'Translate:KnowledgeCategoryParentInvalid';
        return;
    }
    if ( $ParentID && !$Self->{DB}->SelectRow( 'SELECT id FROM knowledge_category WHERE id = ? LIMIT 1', $ParentID ) ) {
        $Self->{LastError} = 'Translate:KnowledgeCategoryParentInvalid';
        return;
    }
    if ( $CategoryID && $ParentID ) {
        my %Seen;
        my $CursorID = $ParentID;
        while ($CursorID) {
            if ( $CursorID == $CategoryID || $Seen{$CursorID}++ ) {
                $Self->{LastError} = 'Translate:KnowledgeCategoryParentInvalid';
                return;
            }
            my $Parent = $Self->{DB}->SelectRow(
                'SELECT parent_id FROM knowledge_category WHERE id = ? LIMIT 1',
                $CursorID,
            );
            $CursorID = $Parent ? $Self->_ID( $Parent->{parent_id} ) : 0;
        }
    }

    my %CleanTranslation;
    for my $Language ( keys %{$Translations} ) {
        my $Code = $Self->_LanguageClean($Language);
        next if !$Code;
        my $Name = $Self->_Trim( $Translations->{$Language}->{name} );
        next if !$Name;
        $CleanTranslation{$Code} = {
            name        => substr( $Name, 0, 190 ),
            description => $Self->_Trim( $Translations->{$Language}->{description} ),
        };
    }
    if ( !keys %CleanTranslation ) {
        $Self->{LastError} = 'Translate:KnowledgeCategoryTranslationRequired';
        return;
    }

    if ( !$Self->{DB}->BeginWork() ) {
        $Self->{LastError} = $Self->{DB}->Error() || 'Knowledge category transaction failed';
        return;
    }

    my $OK;
    if ($CategoryID) {
        $OK = $Self->{DB}->Do(
            'UPDATE knowledge_category
             SET parent_id = NULLIF(?, 0), internal_name = ?, active = ?, sort_order = ?, changed_by_user_id = ?
             WHERE id = ?',
            $ParentID, $Internal, $Active, $SortOrder, $UserID, $CategoryID,
        );
    }
    else {
        $OK = $Self->{DB}->Do(
            'INSERT INTO knowledge_category
             (parent_id, internal_name, active, sort_order, created_by_user_id, changed_by_user_id, created_at, changed_at)
             VALUES (NULLIF(?, 0), ?, ?, ?, ?, ?, NOW(), NOW())',
            $ParentID, $Internal, $Active, $SortOrder, $UserID, $UserID,
        );
        $CategoryID = $Self->{DB}->LastInsertID('knowledge_category') if $OK;
    }

    if ($OK) {
        my $ExistingTranslations = $Self->{DB}->SelectAll(
            'SELECT language FROM knowledge_category_translation WHERE category_id = ?',
            $CategoryID,
        ) || [];
        for my $ExistingTranslation ( @{$ExistingTranslations} ) {
            my $ExistingLanguage = $Self->_LanguageClean( $ExistingTranslation->{language} );
            next if $CleanTranslation{$ExistingLanguage};
            $OK = $Self->{DB}->Do(
                'DELETE FROM knowledge_category_translation WHERE category_id = ? AND language = ?',
                $CategoryID, $ExistingLanguage,
            );
            last if !$OK;
        }
    }

    if ($OK) {
        for my $Language ( sort keys %CleanTranslation ) {
            my $Translation = $CleanTranslation{$Language};
            $OK = $Self->{DB}->Do(
                'INSERT INTO knowledge_category_translation
                 (category_id, language, name, description, created_by_user_id, changed_by_user_id, created_at, changed_at)
                 VALUES (?, ?, ?, ?, ?, ?, NOW(), NOW())
                 ON DUPLICATE KEY UPDATE name = VALUES(name), description = VALUES(description),
                    changed_by_user_id = VALUES(changed_by_user_id), changed_at = NOW()',
                $CategoryID, $Language, $Translation->{name}, $Translation->{description}, $UserID, $UserID,
            );
            last if !$OK;
        }
    }

    if ( $OK && $Self->{DB}->Commit() ) {
        return $CategoryID;
    }

    eval { $Self->{DB}->Rollback(); 1; };
    $Self->{LastError} = $Self->{DB}->Error() || 'Translate:KnowledgeCategorySaveFailed';
    return;
}

sub CategoryToggle {
    my ( $Self, %Param ) = @_;
    my $CategoryID = $Self->_ID( $Param{CategoryID} );
    return if !$CategoryID;
    my $Result = $Self->{DB}->Do(
        'UPDATE knowledge_category SET active = ?, changed_by_user_id = ?, changed_at = NOW() WHERE id = ?',
        $Param{Active} ? 1 : 0, $Self->_ID( $Param{ChangedByUserID} ) || 1, $CategoryID,
    );
    $Self->{LastError} = $Self->{DB}->Error() || 'Translate:KnowledgeCategorySaveFailed' if !$Result;
    return $Result ? 1 : undef;
}

sub ArticleList {
    my ( $Self, %Param ) = @_;

    my $Language   = $Self->_Trim( $Param{Language} ) ne '' ? $Self->_LanguageClean( $Param{Language} ) : '';
    my $CategoryID = $Self->_ID( $Param{CategoryID} );
    my $Query      = $Self->_Trim( $Param{Query} );
    my $Limit      = $Param{Limit} || 100;
    my $Offset     = $Param{Offset} || 0;
    $Limit  = 100 if $Limit !~ m{\A\d+\z} || $Limit < 1 || $Limit > 500;
    $Offset = 0 if $Offset !~ m{\A\d+\z};

    my @Where;
    my @Bind;
    if ($CategoryID) { push @Where, 'a.category_id = ?'; push @Bind, $CategoryID; }
    if ($Language)   { push @Where, 'a.language = ?'; push @Bind, $Language; }
    if ($Query) {
        my $Like = '%' . $Self->_LikeEscape($Query) . '%';
        push @Where, '(a.article_number LIKE ? ESCAPE "\\\\" OR a.title LIKE ? ESCAPE "\\\\" OR a.summary LIKE ? ESCAPE "\\\\" OR a.keywords LIKE ? ESCAPE "\\\\" OR a.search_text LIKE ? ESCAPE "\\\\")';
        push @Bind, ( $Like ) x 5;
    }
    my $Where = @Where ? 'WHERE ' . join( ' AND ', @Where ) : '';

    my $Rows = $Self->{DB}->SelectAll(
        'SELECT a.id, a.article_number, a.category_id, a.language, a.title, a.summary, a.keywords,
                a.visibility, a.customer_scope, a.status, a.revision_number, a.published_at,
                a.created_at, a.changed_at,
                COALESCE(NULLIF(ct.name, ""), c.internal_name) AS category_name,
                COUNT(DISTINCT u.id) AS usage_count
         FROM knowledge_article a
         INNER JOIN knowledge_category c ON c.id = a.category_id
         LEFT JOIN knowledge_category_translation ct ON ct.category_id = c.id AND ct.language = a.language
         LEFT JOIN knowledge_article_usage u ON u.article_id = a.id
         ' . $Where . '
         GROUP BY a.id, a.article_number, a.category_id, a.language, a.title, a.summary, a.keywords,
                  a.visibility, a.customer_scope, a.status, a.revision_number, a.published_at,
                  a.created_at, a.changed_at, ct.name, c.internal_name
         ORDER BY a.changed_at DESC, a.id DESC LIMIT ' . int($Limit) . ' OFFSET ' . int($Offset),
        @Bind,
    );

    if ( !defined $Rows ) {
        $Self->{LastError} = $Self->{DB}->Error() || 'Knowledge articles could not be loaded';
        return [];
    }
    return $Rows;
}

sub ArticleGet {
    my ( $Self, %Param ) = @_;
    my $ArticleID = $Self->_ID( $Param{ArticleID} );
    return if !$ArticleID;

    my $Article = $Self->{DB}->SelectRow(
        'SELECT a.*, COALESCE(NULLIF(ct.name, ""), c.internal_name) AS category_name
         FROM knowledge_article a
         INNER JOIN knowledge_category c ON c.id = a.category_id
         LEFT JOIN knowledge_category_translation ct ON ct.category_id = c.id AND ct.language = a.language
         WHERE a.id = ? LIMIT 1',
        $ArticleID,
    );
    return if !$Article;

    $Article->{revisions} = $Self->{DB}->SelectAll(
        'SELECT r.revision_number, r.status, r.visibility, r.changed_by_user_id, r.created_at,
                CONCAT_WS(" ", NULLIF(u.firstname, ""), NULLIF(u.lastname, "")) AS changed_by_name,
                u.login AS changed_by_login
         FROM knowledge_article_revision r
         LEFT JOIN user_account u ON u.id = r.changed_by_user_id
         WHERE r.article_id = ? ORDER BY r.revision_number DESC',
        $ArticleID,
    ) || [];
    return $Article;
}

sub ArticleSave {
    my ( $Self, %Param ) = @_;

    my $ArticleID     = $Self->_ID( $Param{ArticleID} );
    my $CategoryID    = $Self->_ID( $Param{CategoryID} );
    my $Language      = $Self->_LanguageClean( $Param{Language} );
    my $Title         = $Self->_Trim( $Param{Title} );
    my $Summary       = $Self->_Trim( $Param{Summary} );
    my $Keywords      = $Self->_Trim( $Param{Keywords} );
    my $Content       = QisutuHTML->Sanitize( $Param{Content} || '' );
    my $Visibility    = $Self->_Choice( $Param{Visibility}, { internal => 1, customer => 1 }, 'internal' );
    my $CustomerScope = 'all';
    my $Status        = 'published';
    my $UserID        = $Self->_ID( $Param{ChangedByUserID} ) || 1;

    if ( !$CategoryID || !$Self->{DB}->SelectRow( 'SELECT id FROM knowledge_category WHERE id = ? LIMIT 1', $CategoryID ) ) {
        $Self->{LastError} = 'Translate:KnowledgeArticleCategoryRequired';
        return;
    }
    if ( !$Title ) {
        $Self->{LastError} = 'Translate:KnowledgeArticleTitleRequired';
        return;
    }
    if ( !QisutuHTML->PlainTextSearch($Content) ) {
        $Self->{LastError} = 'Translate:KnowledgeArticleContentRequired';
        return;
    }
    my $SearchText = join ' ', grep {$_} $Title, $Summary, $Keywords, QisutuHTML->PlainTextSearch($Content);
    my $Existing = $ArticleID ? $Self->{DB}->SelectRow(
        'SELECT id, revision_number, status, article_number FROM knowledge_article WHERE id = ? LIMIT 1', $ArticleID,
    ) : undef;
    if ( $ArticleID && !$Existing ) {
        $Self->{LastError} = 'Translate:KnowledgeArticleNotFound';
        return;
    }
    my $Revision = $Existing ? ( $Existing->{revision_number} || 0 ) + 1 : 1;

    if ( !$Self->{DB}->BeginWork() ) {
        $Self->{LastError} = $Self->{DB}->Error() || 'Knowledge article transaction failed';
        return;
    }

    my $OK;
    if ($Existing) {
        $OK = $Self->{DB}->Do(
            'UPDATE knowledge_article SET category_id = ?, language = ?, title = ?, summary = ?, keywords = ?,
                 content = ?, search_text = ?, visibility = ?, customer_scope = ?, status = ?, revision_number = ?,
                 published_at = CASE WHEN ? = "published" THEN NOW() ELSE published_at END,
                 published_by_user_id = CASE WHEN ? = "published" THEN ? ELSE published_by_user_id END,
                 changed_by_user_id = ?, changed_at = NOW()
             WHERE id = ?',
            $CategoryID, $Language, $Title, $Summary, $Keywords, $Content, $SearchText,
            $Visibility, $CustomerScope, $Status, $Revision, $Status, $Status, $UserID, $UserID, $ArticleID,
        );
    }
    else {
        my $TemporaryNumber = 'TMP-' . time() . '-' . $UserID . '-' . int( rand(1_000_000) );
        $OK = $Self->{DB}->Do(
            'INSERT INTO knowledge_article
             (article_number, category_id, language, title, summary, keywords, content, search_text,
              visibility, customer_scope, status, revision_number, published_at, published_by_user_id,
              created_by_user_id, changed_by_user_id, created_at, changed_at)
             VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, 1,
                     CASE WHEN ? = "published" THEN NOW() ELSE NULL END,
                     CASE WHEN ? = "published" THEN ? ELSE NULL END,
                     ?, ?, NOW(), NOW())',
            $TemporaryNumber, $CategoryID, $Language, $Title, $Summary, $Keywords, $Content, $SearchText,
            $Visibility, $CustomerScope, $Status, $Status, $Status, $UserID, $UserID, $UserID,
        );
        $ArticleID = $Self->{DB}->LastInsertID('knowledge_article') if $OK;
        $OK = $Self->{DB}->Do(
            'UPDATE knowledge_article SET article_number = ? WHERE id = ?',
            sprintf( 'KB%08d', $ArticleID ), $ArticleID,
        ) if $OK && $ArticleID;
    }

    if ($OK) {
        $OK = $Self->{DB}->Do(
            'INSERT INTO knowledge_article_revision
             (article_id, revision_number, category_id, language, title, summary, keywords, content,
              visibility, customer_scope, status, changed_by_user_id, created_at)
             VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, NOW())',
            $ArticleID, $Revision, $CategoryID, $Language, $Title, $Summary, $Keywords, $Content,
            $Visibility, $CustomerScope, $Status, $UserID,
        );
    }
    if ($OK) {
        $OK = $Self->{DB}->Do( 'DELETE FROM knowledge_article_customer WHERE article_id = ?', $ArticleID );
    }
    if ($OK) {
        $OK = $Self->{DB}->Do( 'DELETE FROM knowledge_article_queue WHERE article_id = ?', $ArticleID );
    }

    if ( $OK && $Self->{DB}->Commit() ) {
        return $ArticleID;
    }

    eval { $Self->{DB}->Rollback(); 1; };
    $Self->{LastError} = $Self->{DB}->Error() || 'Translate:KnowledgeArticleSaveFailed';
    return;
}

sub CustomerArticleList {
    my ( $Self, %Param ) = @_;

    my $Language   = $Self->_LanguageClean( $Param{Language} );
    my $CategoryID = $Self->_ID( $Param{CategoryID} );
    my $Query      = $Self->_Trim( $Param{Query} );
    my @Where = ( 'a.visibility = "customer"', 'c.active = 1' );
    my @Bind;
    if ($Language)   { push @Where, 'a.language = ?'; push @Bind, $Language; }
    if ($CategoryID) { push @Where, 'a.category_id = ?'; push @Bind, $CategoryID; }
    if ($Query) {
        my $Like = '%' . $Self->_LikeEscape($Query) . '%';
        push @Where, '(a.article_number LIKE ? ESCAPE "\\\\" OR a.title LIKE ? ESCAPE "\\\\" OR a.summary LIKE ? ESCAPE "\\\\" OR a.keywords LIKE ? ESCAPE "\\\\" OR a.search_text LIKE ? ESCAPE "\\\\")';
        push @Bind, ( $Like ) x 5;
    }
    my $Rows = $Self->{DB}->SelectAll(
        'SELECT a.id, a.article_number, a.category_id, a.language, a.title, a.summary, a.changed_at,
                COALESCE(NULLIF(ct.name, ""), c.internal_name) AS category_name
         FROM knowledge_article a
         INNER JOIN knowledge_category c ON c.id = a.category_id
         LEFT JOIN knowledge_category_translation ct ON ct.category_id = c.id AND ct.language = a.language
         WHERE ' . join( ' AND ', @Where ) . '
         ORDER BY c.sort_order, a.title, a.id LIMIT 250',
        @Bind,
    );
    if ( !defined $Rows ) {
        $Self->{LastError} = $Self->{DB}->Error() || 'Knowledge articles could not be loaded';
        return [];
    }
    return $Rows;
}

sub CustomerCategoryList {
    my ( $Self, %Param ) = @_;

    my $Language        = $Self->_LanguageClean( $Param{Language} );
    my $DefaultLanguage = $Self->_LanguageClean( $Self->{Config}->{Language}->{Default} || 'en' );
    my $Rows = $Self->{DB}->SelectAll(
        'SELECT c.id, c.parent_id, c.internal_name, c.sort_order,
                COALESCE(NULLIF(current_t.name, ""), NULLIF(default_t.name, ""), c.internal_name) AS name,
                parent.internal_name AS parent_internal_name,
                COALESCE(NULLIF(parent_current.name, ""), NULLIF(parent_default.name, ""), parent.internal_name, "") AS parent_name,
                COUNT(DISTINCT a.id) AS article_count
         FROM knowledge_category c
         INNER JOIN knowledge_article a ON a.category_id = c.id
              AND a.language = ? AND a.visibility = "customer"
         LEFT JOIN knowledge_category_translation current_t ON current_t.category_id = c.id AND current_t.language = ?
         LEFT JOIN knowledge_category_translation default_t ON default_t.category_id = c.id AND default_t.language = ?
         LEFT JOIN knowledge_category parent ON parent.id = c.parent_id
         LEFT JOIN knowledge_category_translation parent_current ON parent_current.category_id = parent.id AND parent_current.language = ?
         LEFT JOIN knowledge_category_translation parent_default ON parent_default.category_id = parent.id AND parent_default.language = ?
         WHERE c.active = 1
         GROUP BY c.id, c.parent_id, c.internal_name, c.sort_order, current_t.name, default_t.name,
                  parent.internal_name, parent_current.name, parent_default.name, parent.sort_order
         ORDER BY COALESCE(parent.sort_order, c.sort_order), parent.id, c.sort_order, name, c.id',
        $Language, $Language, $DefaultLanguage, $Language, $DefaultLanguage,
    );
    if ( !defined $Rows ) {
        $Self->{LastError} = $Self->{DB}->Error() || 'Knowledge categories could not be loaded';
        return [];
    }
    for my $Row ( @{$Rows} ) {
        $Row->{display_name} = $Row->{parent_name} ? $Row->{parent_name} . ' / ' . $Row->{name} : $Row->{name};
    }
    return $Rows;
}

sub CustomerArticleGet {
    my ( $Self, %Param ) = @_;
    my $ArticleID  = $Self->_ID( $Param{ArticleID} );
    my $Language   = $Self->_LanguageClean( $Param{Language} );
    return if !$ArticleID;

    return $Self->{DB}->SelectRow(
        'SELECT a.id, a.article_number, a.category_id, a.language, a.title, a.summary, a.content,
                a.revision_number, a.published_at, a.changed_at,
                COALESCE(NULLIF(ct.name, ""), c.internal_name) AS category_name
         FROM knowledge_article a
         INNER JOIN knowledge_category c ON c.id = a.category_id AND c.active = 1
         LEFT JOIN knowledge_category_translation ct ON ct.category_id = c.id AND ct.language = a.language
         WHERE a.id = ? AND a.language = ? AND a.visibility = "customer"
         LIMIT 1',
        $ArticleID, $Language,
    );
}

sub AgentInsertSearch {
    my ( $Self, %Param ) = @_;

    my $Rows = $Self->ArticleList(
        Query    => $Param{Query},
        Language => $Param{Language},
        Limit    => 50,
    );
    my $CustomerSafe = $Param{CustomerSafe} ? 1 : 0;
    my @Result;

    for my $Article ( @{$Rows} ) {
        my $CanInsert = 1;
        if ($CustomerSafe) {
            $CanInsert = $Self->_ArticleCustomerAllowed( Article => $Article );
        }
        push @Result, {
            id             => 0 + ( $Article->{id} || 0 ),
            article_number => $Article->{article_number} || '',
            title          => $Article->{title} || '',
            summary        => $Article->{summary} || '',
            category_name  => $Article->{category_name} || '',
            visibility     => $Article->{visibility} || 'internal',
            status         => 'published',
            revision       => 0 + ( $Article->{revision_number} || 0 ),
            can_insert     => $CanInsert ? 1 : 0,
        };
    }
    return \@Result;
}

sub AgentInsertArticleGet {
    my ( $Self, %Param ) = @_;
    my $Article = $Self->ArticleGet( ArticleID => $Param{ArticleID} );
    return if !$Article;

    my $CanInsert = $Param{CustomerSafe}
        ? $Self->_ArticleCustomerAllowed( Article => $Article )
        : 1;

    my $BaseURL = QisutuSystemSetting->new( Config => $Self->{Config}, DB => $Self->{DB} )->BaseURL() || '';
    $BaseURL = $Self->_Trim($BaseURL);
    $BaseURL =~ s{/+\z}{};
    $BaseURL = '' if $BaseURL =~ m{[?#]} || $BaseURL !~ m{\Ahttps?://[^\s/]+(?:/[^\s]*)?\z}i;
    my $URL = 'index.pl?Page=CustomerKnowledgeBase&Action=View&ArticleID=' . ( $Article->{id} || 0 );
    $URL = $BaseURL . '/' . $URL if $BaseURL;

    return {
        id             => 0 + ( $Article->{id} || 0 ),
        article_number => $Article->{article_number} || '',
        title          => $Article->{title} || '',
        summary        => $Article->{summary} || '',
        content        => $Article->{content} || '',
        visibility     => $Article->{visibility} || 'internal',
        status         => 'published',
        revision       => 0 + ( $Article->{revision_number} || 0 ),
        can_insert     => $CanInsert ? 1 : 0,
        portal_url     => $CanInsert && ( $Article->{visibility} || '' ) eq 'customer' ? $URL : '',
    };
}

sub UsageRecord {
    my ( $Self, %Param ) = @_;
    my $ArticleID = $Self->_ID( $Param{ArticleID} );
    my $UserID    = $Self->_ID( $Param{UserID} );
    my $TicketID  = $Self->_ID( $Param{TicketID} );
    return if !$ArticleID || !$UserID;
    my $Article = $Self->{DB}->SelectRow( 'SELECT revision_number FROM knowledge_article WHERE id = ? LIMIT 1', $ArticleID );
    return if !$Article;
    my $Context = $Self->_Choice( $Param{Context}, { map { $_ => 1 } qw(ticket_create reply note forward) }, 'reply' );
    my $Mode    = $Self->_Choice( $Param{InsertMode}, { solution => 1, title_solution => 1, link => 1 }, 'solution' );
    my $Result = $Self->{DB}->Do(
        'INSERT INTO knowledge_article_usage
         (article_id, revision_number, ticket_id, used_by_user_id, usage_context, insert_mode, created_at)
         VALUES (?, ?, NULLIF(?, 0), ?, ?, ?, NOW())',
        $ArticleID, $Article->{revision_number} || 1, $TicketID, $UserID, $Context, $Mode,
    );
    $Self->{LastError} = $Self->{DB}->Error() || 'Knowledge usage could not be recorded' if !$Result;
    return $Result ? 1 : undef;
}

sub CustomerIDFromUser {
    my ( $Self, %Param ) = @_;
    my $UserID = $Self->_ID( $Param{UserID} );
    return 0 if !$UserID;
    my $Row = $Self->{DB}->SelectRow( 'SELECT customer_id FROM customer_user WHERE user_account_id = ? LIMIT 1', $UserID );
    return $Row ? 0 + ( $Row->{customer_id} || 0 ) : 0;
}

sub CustomerIDFromCustomerUser {
    my ( $Self, %Param ) = @_;
    my $ID = $Self->_ID( $Param{CustomerUserID} );
    return 0 if !$ID;
    my $Row = $Self->{DB}->SelectRow( 'SELECT customer_id FROM customer_user WHERE id = ? LIMIT 1', $ID );
    return $Row ? 0 + ( $Row->{customer_id} || 0 ) : 0;
}

sub _ArticleCustomerAllowed {
    my ( $Self, %Param ) = @_;
    my $Article = $Param{Article} || {};
    return ( $Article->{visibility} || '' ) eq 'customer' ? 1 : 0;
}

sub _IDList {
    my ( $Self, $Value ) = @_;
    my @Value = ref $Value eq 'ARRAY' ? @{$Value} : defined $Value ? ($Value) : ();
    my %Seen;
    return [ grep { $_ && !$Seen{$_}++ } map { $Self->_ID($_) } @Value ];
}

sub _ID {
    my ( $Self, $Value ) = @_;
    return 0 if !defined $Value || $Value !~ m{\A\d+\z};
    return 0 + $Value;
}

sub _Trim {
    my ( $Self, $Value ) = @_;
    $Value = '' if !defined $Value;
    $Value = "$Value";
    $Value =~ s{\x00}{}g;
    $Value =~ s{\A\s+|\s+\z}{}g;
    return $Value;
}

sub _LanguageClean {
    my ( $Self, $Value ) = @_;
    $Value = lc $Self->_Trim( $Value || $Self->{Config}->{Language}->{Default} || 'en' );
    $Value =~ s{[^a-z0-9_-]}{}g;
    return $Value || 'en';
}

sub _Choice {
    my ( $Self, $Value, $Allowed, $Default ) = @_;
    $Value = $Self->_Trim($Value);
    return $Allowed->{$Value} ? $Value : $Default;
}

sub _LikeEscape {
    my ( $Self, $Value ) = @_;
    $Value = '' if !defined $Value;
    $Value =~ s{([\\%_])}{\\$1}g;
    return $Value;
}

1;
