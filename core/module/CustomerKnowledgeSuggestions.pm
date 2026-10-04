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

package CustomerKnowledgeSuggestions;

use strict;
use warnings;
use utf8;

use JSON::PP;
use QisutuKnowledgeSuggestions;
use QisutuKnowledgeBase;
use QisutuHTML;


sub new {
    my ( $Class, %Param ) = @_;
    return bless {
        Config  => $Param{Config} || {},
        DB      => $Param{DB},
        Output  => $Param{Output},
        Program => $Param{Program},
    }, $Class;
}

sub Run {
    my ( $Self, %Param ) = @_;

    return $Self->_JSON( '400 Bad Request', { error => 'invalid_request' } )
        if defined $Param{Request} && ref $Param{Request} ne 'HASH';
    my $Request = $Param{Request} || {};
    my $User = ref $Param{User} eq 'HASH' ? $Param{User} : {};
    return $Self->_JSON( '403 Forbidden', { error => 'forbidden' } )
        if ref $User->{account_type} || ( $User->{account_type} || '' ) ne 'customer'
        || !$Self->_ID( $User->{user_account_id} );
    return $Self->_JSON( '400 Bad Request', { error => 'invalid_request' } )
        if ref $Request->{__RequestMethod};
    return $Self->_JSON( '405 Method Not Allowed', { error => 'method_not_allowed' }, 'Allow: POST' )
        if ( $Request->{__RequestMethod} || '' ) ne 'POST';

    my $Step = $Request->{Step};
    return $Self->_JSON( '400 Bad Request', { error => 'invalid_request' } )
        if !defined $Step || ref $Step || ( $Step ne 'Search' && $Step ne 'Browse' && $Step ne 'View' );

    my $Language = defined $Request->{Language} ? $Request->{Language}
        : $Self->{Config}->{Language}->{Default} || 'en';
    return $Self->_JSON( '400 Bad Request', { error => 'invalid_request' } )
        if ref $Language || $Language !~ m{\A[a-zA-Z0-9]+(?:[-_][a-zA-Z0-9]+)*\z} || length($Language) > 20;
    $Language = lc $Language;

    my $Query = defined $Request->{Query} ? $Request->{Query} : '';
    return $Self->_JSON( '400 Bad Request', { error => 'invalid_request' } )
        if ( $Step eq 'Search' || $Step eq 'Browse' ) && ( ref $Query || length($Query) > 500 );
    my %SearchInput = ( Query => $Query );
    if ( $Step eq 'Search' ) {
        for my $Field (qw(Subject Description)) {
            next if !exists $Request->{$Field};
            my $Value = defined $Request->{$Field} ? $Request->{$Field} : '';
            my $Maximum = $Field eq 'Subject' ? 500 : 50000;
            return $Self->_JSON( '400 Bad Request', { error => 'invalid_request' } )
                if ref $Value || length($Value) > $Maximum;
            $SearchInput{$Field} = $Value;
        }
    }
    my $ArticleID = $Self->_ID( $Request->{ArticleID} );
    return $Self->_JSON( '400 Bad Request', { error => 'invalid_request' } )
        if $Step eq 'View' && !$ArticleID;

    my $Result;
    my $OK = eval {
        my $Manager = QisutuKnowledgeSuggestions->new( Config => $Self->{Config}, DB => $Self->{DB} );
        my $Settings = $Manager->SettingsGet();
        die "Settings unavailable\n" if ref $Settings ne 'HASH' || $Self->{DB}->Error();
        my $MinimumLength = $Self->_Setting( $Settings->{minimum_length}, 3, 2, 10 );
        my $Limit = $Self->_Setting( $Settings->{max_results}, 3, 1, 10 );
        my $Enabled = !defined $Settings->{enabled} || ref $Settings->{enabled} || $Settings->{enabled} ne '0';

        if ( !$Enabled ) {
            $Result = $Step eq 'Search'
                ? $Self->_JSON( '200 OK', { articles => [], minimum_length => $MinimumLength } )
                : $Self->_JSON( '403 Forbidden', { error => 'disabled' } );
        }
        elsif ( $Step eq 'Search' ) {
            my $Search = QisutuKnowledgeSuggestions->new( Config => $Self->{Config}, DB => $Self->{DB} );
            my $Prepared = $Search->Prepare(%SearchInput);
            my $Articles = $Prepared->{length} >= $MinimumLength
                ? $Search->Articles( %SearchInput, Language => $Language, Limit => $Limit ) : [];
            $Result = $Self->_JSON( '200 OK', { articles => $Articles, minimum_length => $MinimumLength } );
        }
        elsif ( $Step eq 'Browse' ) {
            my $Search = QisutuKnowledgeSuggestions->new( Config => $Self->{Config}, DB => $Self->{DB} );
            $Result = $Self->_JSON( '200 OK', { articles => $Search->Browse( Query => $Query, Language => $Language ) } );
        }
        else {
            $Result = $Self->_View( ArticleID => $ArticleID, Language => $Language );
        }
        1;
    };
    return $Result if $OK;
    # Never expose raw SQL, exception text or database credentials to customers.
    return $Self->_JSON( '500 Internal Server Error', { error => 'unavailable' } );
}

sub _View {
    my ( $Self, %Param ) = @_;

    # Core CustomerArticleGet enforces customer visibility and active category,
    # but does not currently check publication status. Apply that guard here.
    my $Allowed = $Self->_Published( %Param );
    return $Self->_JSON( '404 Not Found', { error => 'article_not_found' } ) if !$Allowed;
    my $Knowledge = QisutuKnowledgeBase->new( Config => $Self->{Config}, DB => $Self->{DB}, Output => $Self->{Output} );
    my $Article = $Knowledge->CustomerArticleGet( %Param );
    die "Article unavailable\n" if $Self->{DB}->Error() || $Knowledge->Error();
    return $Self->_JSON( '404 Not Found', { error => 'article_not_found' } )
        if !$Article || !$Self->_ID( $Article->{id} ) || $Article->{id} != $Param{ArticleID};
    # Recheck immediately before delivery, after core loaded content/attachments.
    return $Self->_JSON( '404 Not Found', { error => 'article_not_found' } )
        if !$Self->_Published( %Param );

    my @Attachment;
    for my $Item ( @{ $Article->{attachments} || [] } ) {
        next if ref $Item ne 'HASH';
        my $ID = $Self->_ID( $Item->{id} );
        next if !$ID;
        push @Attachment, {
            id           => $ID,
            filename     => $Item->{filename} || 'attachment.bin',
            size_display => $Item->{size_display} || '',
            download_url => 'index.pl?Page=KnowledgeAttachmentDownload&AttachmentID=' . $ID,
        };
    }
    return $Self->_JSON( '200 OK', { article => {
        id            => $Param{ArticleID},
        title         => $Article->{title} || '',
        summary       => $Article->{summary} || '',
        category_name => $Article->{category_name} || '',
        content       => QisutuHTML->Sanitize( $Article->{content} || '' ),
        attachments   => \@Attachment,
        url           => 'index.pl?Page=CustomerKnowledgeBase&Action=View&ArticleID=' . $Param{ArticleID},
    } } );
}

sub _Published {
    my ( $Self, %Param ) = @_;
    my $Row = $Self->{DB}->SelectRow(
        'SELECT a.id FROM knowledge_article a
         INNER JOIN knowledge_category c ON c.id = a.category_id
         WHERE a.id = ? AND a.language = ? AND a.visibility = \'customer\'
             AND a.status = \'published\' AND c.active = 1 LIMIT 1',
        $Param{ArticleID}, $Param{Language},
    );
    die "Article access unavailable\n" if $Self->{DB}->Error();
    return $Row;
}

sub _ID {
    my ( $Self, $Value ) = @_;
    return 0 if !defined $Value || ref $Value || $Value !~ m{\A\d{1,18}\z} || $Value < 1;
    return 0 + $Value;
}

sub _Setting {
    my ( $Self, $Value, $Default, $Minimum, $Maximum ) = @_;
    return $Default if !defined $Value || ref $Value || $Value !~ m{\A\d{1,2}\z}
        || $Value < $Minimum || $Value > $Maximum;
    return 0 + $Value;
}

sub _JSON {
    my ( $Self, $Status, $Data, @ExtraHeaders ) = @_;
    return { Response => $Self->{Output}->Response(
        Status      => $Status,
        ContentType => 'application/json; charset=UTF-8',
        Body        => JSON::PP->new->utf8(1)->canonical(1)->encode($Data),
        Headers     => [ 'Cache-Control: private, no-store', 'Pragma: no-cache', @ExtraHeaders ],
    ) };
}

1;
