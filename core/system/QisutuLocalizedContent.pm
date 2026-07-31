# Qisutu - Open Source Ticket System
# Copyright (C) 2026 Franziska Steps
# Qisutu - Kim-KI, https://qisutu.de
#
# This file is part of Qisutu.
#
# Qisutu is free software: you can redistribute it and/or modify
# it under the terms of the GNU Affero General Public License as published by
# the Free Software Foundation, either version 3 of the License, or
# (at your option) any later version.
#
# Qisutu is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the
# GNU Affero General Public License for more details.
#
# You should have received a copy of the GNU Affero General Public License
# along with Qisutu. If not, see <https://www.gnu.org/licenses/>.
#
# SPDX-FileCopyrightText: 2026 Franziska Steps
# SPDX-License-Identifier: AGPL-3.0-or-later

package QisutuLocalizedContent;

use strict;
use warnings;
use utf8;

use QisutuAgentNotificationTemplates;
use QisutuHTML;

sub new {
    my ( $Class, %Param ) = @_;

    my $Self = {
        Config    => $Param{Config},
        DB        => $Param{DB},
        LastError => '',
    };

    bless $Self, $Class;

    return $Self;
}

sub LanguageList {
    return QisutuAgentNotificationTemplates->Languages();
}

sub LanguageClean {
    my ( $Self, $Language ) = @_;

    return QisutuAgentNotificationTemplates->LanguageClean(
        $Language,
        $Self->{Config}->{Language}->{Default} || 'en',
    );
}

sub SchemaEnsure {
    my ($Self) = @_;

    return 1 if $Self->{SchemaChecked};
    return if !$Self->{DB};

    my @SQL = (
        'CREATE TABLE IF NOT EXISTS salutation_translation (
            salutation_id BIGINT UNSIGNED NOT NULL,
            language VARCHAR(10) NOT NULL,
            name VARCHAR(100) NOT NULL,
            content LONGTEXT NOT NULL,
            created_by_user_id BIGINT UNSIGNED NOT NULL DEFAULT 1,
            changed_by_user_id BIGINT UNSIGNED NOT NULL DEFAULT 1,
            created_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
            changed_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
            PRIMARY KEY (salutation_id, language),
            KEY salutation_translation_language_name (language, name),
            CONSTRAINT salutation_translation_salutation_fk
                FOREIGN KEY (salutation_id) REFERENCES salutation (id) ON DELETE CASCADE
        ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci',

        'CREATE TABLE IF NOT EXISTS signature_translation (
            signature_id BIGINT UNSIGNED NOT NULL,
            language VARCHAR(10) NOT NULL,
            name VARCHAR(100) NOT NULL,
            content LONGTEXT NOT NULL,
            created_by_user_id BIGINT UNSIGNED NOT NULL DEFAULT 1,
            changed_by_user_id BIGINT UNSIGNED NOT NULL DEFAULT 1,
            created_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
            changed_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
            PRIMARY KEY (signature_id, language),
            KEY signature_translation_language_name (language, name),
            CONSTRAINT signature_translation_signature_fk
                FOREIGN KEY (signature_id) REFERENCES signature (id) ON DELETE CASCADE
        ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci',

        'INSERT IGNORE INTO salutation_translation (
            salutation_id,
            language,
            name,
            content,
            created_by_user_id,
            changed_by_user_id,
            created_at,
            changed_at
         )
         SELECT
            id,
            "de",
            name,
            content,
            created_by_user_id,
            changed_by_user_id,
            created_at,
            changed_at
         FROM salutation',

        'INSERT IGNORE INTO signature_translation (
            signature_id,
            language,
            name,
            content,
            created_by_user_id,
            changed_by_user_id,
            created_at,
            changed_at
         )
         SELECT
            id,
            "de",
            name,
            content,
            created_by_user_id,
            changed_by_user_id,
            created_at,
            changed_at
         FROM signature',
    );

    for my $SQL (@SQL) {
        my $Result = $Self->{DB}->Do($SQL);

        if ( !$Result ) {
            $Self->{LastError} = $Self->{DB}->Error() || 'Localized content schema could not be prepared';
            return;
        }
    }

    $Self->{SchemaChecked} = 1;

    return 1;
}

sub ItemList {
    my ( $Self, %Param ) = @_;

    my $Definition = $Self->_Definition( $Param{Type} );
    return [] if !$Definition;

    $Self->SchemaEnsure() || return [];

    my $Language        = $Self->LanguageClean( $Param{Language} );
    my $DefaultLanguage = $Self->LanguageClean( $Self->{Config}->{Language}->{Default} );
    my $WhereActive     = $Param{IncludeInactive} ? '' : 'WHERE base.active = 1';

    my $Rows = $Self->{DB}->SelectAll(
        'SELECT
            base.id,
            COALESCE(
                NULLIF(current_translation.name, ""),
                NULLIF(default_translation.name, ""),
                base.name
            ) AS name,
            COALESCE(current_translation.content, "") AS content,
            CASE WHEN current_translation.language IS NULL THEN 0 ELSE 1 END AS translation_exists,
            base.active,
            base.sort_order
         FROM ' . $Definition->{Table} . ' base
         LEFT JOIN ' . $Definition->{TranslationTable} . ' current_translation
            ON current_translation.' . $Definition->{IDColumn} . ' = base.id
           AND current_translation.language = ?
         LEFT JOIN ' . $Definition->{TranslationTable} . ' default_translation
            ON default_translation.' . $Definition->{IDColumn} . ' = base.id
           AND default_translation.language = ?
         ' . $WhereActive . '
         ORDER BY base.sort_order ASC, name ASC, base.id ASC',
        $Language,
        $DefaultLanguage,
    );

    if ( !$Rows ) {
        $Self->{LastError} = $Self->{DB}->Error() || 'Localized content could not be loaded';
        return [];
    }

    for my $Row ( @{$Rows} ) {
        $Row->{active_label} = $Row->{active} ? 'Translate:AdminActiveYes' : 'Translate:AdminActiveNo';
    }

    return $Rows;
}

sub ItemGet {
    my ( $Self, %Param ) = @_;

    my $Definition = $Self->_Definition( $Param{Type} );
    my $ID         = $Param{ID} || 0;
    return if !$Definition;
    return if $ID !~ m{\A\d+\z} || !$ID;

    $Self->SchemaEnsure() || return;

    my $Language        = $Self->LanguageClean( $Param{Language} );
    my $DefaultLanguage = $Self->LanguageClean( $Self->{Config}->{Language}->{Default} );

    my $Row = $Self->{DB}->SelectRow(
        'SELECT
            base.id,
            COALESCE(
                NULLIF(current_translation.name, ""),
                NULLIF(default_translation.name, ""),
                base.name
            ) AS name,
            COALESCE(current_translation.content, "") AS content,
            CASE WHEN current_translation.language IS NULL THEN 0 ELSE 1 END AS translation_exists,
            base.active,
            base.sort_order
         FROM ' . $Definition->{Table} . ' base
         LEFT JOIN ' . $Definition->{TranslationTable} . ' current_translation
            ON current_translation.' . $Definition->{IDColumn} . ' = base.id
           AND current_translation.language = ?
         LEFT JOIN ' . $Definition->{TranslationTable} . ' default_translation
            ON default_translation.' . $Definition->{IDColumn} . ' = base.id
           AND default_translation.language = ?
         WHERE base.id = ?
         LIMIT 1',
        $Language,
        $DefaultLanguage,
        $ID,
    );

    if ( !$Row ) {
        $Self->{LastError} = 'Localized content entry was not found';
        return;
    }

    $Row->{active_label} = $Row->{active} ? 'Translate:AdminActiveYes' : 'Translate:AdminActiveNo';

    return $Row;
}

sub ItemCreate {
    my ( $Self, %Param ) = @_;

    my $Definition = $Self->_Definition( $Param{Type} );
    return if !$Definition;

    $Self->SchemaEnsure() || return;

    my $Language  = $Self->LanguageClean( $Param{Language} );
    my $Name      = $Self->_Trim( $Param{Name} );
    my $Content   = QisutuHTML->Sanitize( $Self->_Trim( $Param{Content} ) );
    my $SortOrder = $Param{SortOrder} || 1000;
    my $UserID    = $Param{ChangedByUserID} || 1;

    if ( !$Name || !$Content ) {
        $Self->{LastError} = 'Name and content are required';
        return;
    }
    $SortOrder = 1000 if $SortOrder !~ m{\A\d+\z};

    if ( !$Self->{DB}->BeginWork() ) {
        $Self->{LastError} = $Self->{DB}->Error() || 'Localized content transaction could not be started';
        return;
    }

    my $Created = $Self->{DB}->Do(
        'INSERT INTO ' . $Definition->{Table} . ' (
            name,
            content,
            active,
            sort_order,
            created_by_user_id,
            changed_by_user_id
         ) VALUES (
            ?, ?, 1, ?, ?, ?
         )',
        $Name,
        $Content,
        $SortOrder,
        $UserID,
        $UserID,
    );

    if ( !$Created ) {
        return $Self->_RollbackWithError('Localized content entry could not be created');
    }

    my $ID = $Self->{DB}->LastInsertID( $Definition->{Table} );
    if ( !$ID ) {
        return $Self->_RollbackWithError('Localized content ID could not be loaded');
    }

    my $Translated = $Self->{DB}->Do(
        'INSERT INTO ' . $Definition->{TranslationTable} . ' (
            ' . $Definition->{IDColumn} . ',
            language,
            name,
            content,
            created_by_user_id,
            changed_by_user_id
         ) VALUES (
            ?, ?, ?, ?, ?, ?
         )',
        $ID,
        $Language,
        $Name,
        $Content,
        $UserID,
        $UserID,
    );

    if ( !$Translated ) {
        return $Self->_RollbackWithError('Localized content translation could not be created');
    }

    if ( $Language ne 'de' ) {
        my $GermanMarker = $Self->{DB}->Do(
            'INSERT IGNORE INTO ' . $Definition->{TranslationTable} . ' (
                ' . $Definition->{IDColumn} . ',
                language,
                name,
                content,
                created_by_user_id,
                changed_by_user_id
             ) VALUES (
                ?, "de", ?, "", ?, ?
             )',
            $ID,
            $Name,
            $UserID,
            $UserID,
        );

        if ( !$GermanMarker ) {
            return $Self->_RollbackWithError('Localized content language marker could not be created');
        }
    }

    if ( !$Self->{DB}->Commit() ) {
        return $Self->_RollbackWithError('Localized content transaction could not be committed');
    }

    return $ID;
}

sub ItemUpdate {
    my ( $Self, %Param ) = @_;

    my $Definition = $Self->_Definition( $Param{Type} );
    my $ID         = $Param{ID} || 0;
    return if !$Definition;

    $Self->SchemaEnsure() || return;

    my $Language  = $Self->LanguageClean( $Param{Language} );
    my $Name      = $Self->_Trim( $Param{Name} );
    my $Content   = QisutuHTML->Sanitize( $Self->_Trim( $Param{Content} ) );
    my $Active    = $Param{Active} ? 1 : 0;
    my $SortOrder = $Param{SortOrder} || 1000;
    my $UserID    = $Param{ChangedByUserID} || 1;

    if ( $ID !~ m{\A\d+\z} || !$ID || !$Name || !$Content ) {
        $Self->{LastError} = 'Entry, name and content are required';
        return;
    }
    $SortOrder = 1000 if $SortOrder !~ m{\A\d+\z};

    if ( !$Self->{DB}->BeginWork() ) {
        $Self->{LastError} = $Self->{DB}->Error() || 'Localized content transaction could not be started';
        return;
    }

    my $Updated = $Language eq 'de'
        ? $Self->{DB}->Do(
            'UPDATE ' . $Definition->{Table} . '
             SET name = ?,
                 content = ?,
                 active = ?,
                 sort_order = ?,
                 changed_by_user_id = ?
             WHERE id = ?',
            $Name,
            $Content,
            $Active,
            $SortOrder,
            $UserID,
            $ID,
        )
        : $Self->{DB}->Do(
            'UPDATE ' . $Definition->{Table} . '
             SET active = ?,
                 sort_order = ?,
                 changed_by_user_id = ?
             WHERE id = ?',
            $Active,
            $SortOrder,
            $UserID,
            $ID,
        );

    if ( !$Updated ) {
        return $Self->_RollbackWithError('Localized content entry could not be updated');
    }

    my $Translated = $Self->{DB}->Do(
        'INSERT INTO ' . $Definition->{TranslationTable} . ' (
            ' . $Definition->{IDColumn} . ',
            language,
            name,
            content,
            created_by_user_id,
            changed_by_user_id
         ) VALUES (
            ?, ?, ?, ?, ?, ?
         )
         ON DUPLICATE KEY UPDATE
            name = VALUES(name),
            content = VALUES(content),
            changed_by_user_id = VALUES(changed_by_user_id)',
        $ID,
        $Language,
        $Name,
        $Content,
        $UserID,
        $UserID,
    );

    if ( !$Translated ) {
        return $Self->_RollbackWithError('Localized content translation could not be saved');
    }

    if ( !$Self->{DB}->Commit() ) {
        return $Self->_RollbackWithError('Localized content transaction could not be committed');
    }

    return 1;
}

sub ItemDeactivate {
    my ( $Self, %Param ) = @_;

    my $Definition = $Self->_Definition( $Param{Type} );
    my $ID         = $Param{ID} || 0;
    my $UserID     = $Param{ChangedByUserID} || 1;
    return if !$Definition;
    return if $ID !~ m{\A\d+\z} || !$ID;

    $Self->SchemaEnsure() || return;

    my $Result = $Self->{DB}->Do(
        'UPDATE ' . $Definition->{Table} . '
         SET active = 0,
             changed_by_user_id = ?
         WHERE id = ?',
        $UserID,
        $ID,
    );

    if ( !$Result ) {
        $Self->{LastError} = $Self->{DB}->Error() || 'Localized content entry could not be deactivated';
        return;
    }

    return 1;
}

sub _Definition {
    my ( $Self, $Type ) = @_;

    my %Definition = (
        salutation => {
            Table            => 'salutation',
            TranslationTable => 'salutation_translation',
            IDColumn         => 'salutation_id',
        },
        signature => {
            Table            => 'signature',
            TranslationTable => 'signature_translation',
            IDColumn         => 'signature_id',
        },
    );

    if ( !$Type || !$Definition{$Type} ) {
        $Self->{LastError} = 'Invalid localized content type';
        return;
    }

    return $Definition{$Type};
}

sub _RollbackWithError {
    my ( $Self, $Fallback ) = @_;

    my $Error = $Self->{DB}->Error() || $Fallback;
    $Self->{DB}->Rollback();
    $Self->{LastError} = $Error;

    return;
}

sub _Trim {
    my ( $Self, $Value ) = @_;

    $Value = '' if !defined $Value;
    $Value =~ s{\A\s+}{};
    $Value =~ s{\s+\z}{};

    return $Value;
}

sub Error {
    my ($Self) = @_;

    return $Self->{LastError};
}

1;
