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

package QisutuCustomerAutoResponse;

use strict;
use warnings;
use utf8;

use parent 'QisutuNotification';

use QisutuCustomerAutoResponseTemplates;
use QisutuHTML;
use QisutuMail;

sub ResponseTypes {
    my ( $Self, %Param ) = @_;

    return QisutuCustomerAutoResponseTemplates->Templates(
        Language => $Param{Language} || 'de',
    );
}

sub LanguageList {
    return QisutuCustomerAutoResponseTemplates->Languages();
}

sub LanguageClean {
    my ( $Self, $Language ) = @_;

    return QisutuCustomerAutoResponseTemplates->LanguageClean(
        $Language,
        $Self->{Config}->{Language}->{Default} || 'en',
    );
}

sub TemplateList {
    my ( $Self, %Param ) = @_;

    my $Language = $Self->LanguageClean( $Param{Language} );

    $Self->SchemaEnsure() || return [];
    $Self->_DefaultTemplatesEnsure();
    return [] if $Self->{LastError};

    my $Rows = $Self->{DB}->SelectAll(
        'SELECT *
         FROM customer_auto_response_template
         WHERE language = ?
         ORDER BY sort_order ASC, name ASC'
        ,
        $Language,
    );

    if ( !$Rows ) {
        $Self->{LastError} = $Self->{DB}->Error() || 'Customer auto-response templates could not be loaded';
        return [];
    }

    for my $Row ( @{$Rows} ) {
        $Row->{active_label} = $Row->{active} ? 'Translate:AdminActiveYes' : 'Translate:AdminActiveNo';
        $Row->{display_name} = $Row->{name} || $Row->{response_type};
        $Row->{body_preview} = QisutuHTML->PlainTextPreview( $Row->{body_html} || '', 160 );
    }

    return $Rows;
}

sub TemplateGet {
    my ( $Self, %Param ) = @_;

    my $Type     = $Self->_ResponseTypeClean( $Param{ResponseType} || $Param{Type} );
    my $Language = $Self->LanguageClean( $Param{Language} );
    return if !$Type;

    $Self->SchemaEnsure() || return;
    $Self->_DefaultTemplatesEnsure();
    return if $Self->{LastError};

    my $Template = $Self->{DB}->SelectRow(
        'SELECT *
         FROM customer_auto_response_template
         WHERE response_type = ?
            AND language = ?
         LIMIT 1',
        $Type,
        $Language,
    );

    if ( !$Template ) {
        $Self->{LastError} = 'Customer auto-response template was not found';
        return;
    }

    return $Template;
}

sub TemplateUpdate {
    my ( $Self, %Param ) = @_;

    my $Type     = $Self->_ResponseTypeClean( $Param{ResponseType} || $Param{Type} );
    my $Language = $Self->LanguageClean( $Param{Language} );
    return if !$Type;

    $Self->SchemaEnsure() || return;
    $Self->_DefaultTemplatesEnsure();
    return if $Self->{LastError};

    my $Subject = $Self->_Trim( $Param{Subject} );
    my $Body    = QisutuHTML->Sanitize( $Param{BodyHTML} || '' );
    my $Active  = $Param{Active} ? 1 : 0;
    my $UserID  = $Param{ChangedByUserID} || 1;

    if ( !$Subject || !$Body ) {
        $Self->{LastError} = 'Subject and text are required';
        return;
    }

    my $Result = $Self->{DB}->Do(
        'UPDATE customer_auto_response_template
         SET subject = ?, body_html = ?, active = ?, changed_by_user_id = ?
         WHERE response_type = ?
            AND language = ?',
        $Subject,
        $Body,
        $Active,
        $UserID,
        $Type,
        $Language,
    );

    if ( !$Result ) {
        $Self->{LastError} = $Self->{DB}->Error() || 'Customer auto-response template could not be saved';
        return;
    }

    return 1;
}

sub Send {
    my ( $Self, %Param ) = @_;

    $Self->{LastError} = '';

    my $Type = $Self->_ResponseTypeClean( $Param{ResponseType} || $Param{Type} );
    return 0 if !$Type;

    my $TicketID = $Param{TicketID} || 0;
    if ( $Type ne 'incoming_email_rejected' && ( $TicketID !~ m{\A\d+\z} || !$TicketID ) ) {
        $Self->{LastError} = 'Valid TicketID is required for customer auto-response';
        return 0;
    }

    if ( $Type eq 'incoming_email_rejected' && $Self->_AutomatedMessage( Headers => $Param{Headers} ) ) {
        $Self->{LastError} = 'Automatic rejection response suppressed for an automated sender';
        return 0;
    }

    $Self->SchemaEnsure() || return 0;
    $Self->_DefaultTemplatesEnsure();
    return 0 if $Self->{LastError};

    my $Ticket = $TicketID ? $Self->_TicketDataGet( TicketID => $TicketID ) : {};
    if ( $TicketID && !$Ticket ) {
        $Self->{LastError} ||= 'Ticket data could not be loaded for customer auto-response';
        return 0;
    }

    my $RecipientEmail = $Self->_EmailClean(
        $Param{RecipientEmail} || $Ticket->{customer_user_email} || $Param{IncomingFromEmail}
    );
    my $RecipientName = $Self->_Trim(
        $Param{RecipientName} || $Ticket->{customer_user_name} || $Param{IncomingFromName}
    );
    if ( !$RecipientEmail ) {
        $Self->{LastError} = 'No valid customer recipient found for auto-response';
        return 0;
    }

    my $Language = $Self->_RecipientLanguage(
        Language       => $Param{Language},
        Ticket         => $Ticket,
        RecipientEmail => $RecipientEmail,
    );
    my $Template = $Self->TemplateGet(
        ResponseType => $Type,
        Language     => $Language,
    );
    return 0 if !$Template;
    if ( !$Template->{active} ) {
        $Self->{LastError} = 'Customer auto-response template is inactive';
        return 0;
    }

    if ($TicketID) {
        $Ticket->{customer_user_name}  ||= $RecipientName;
        $Ticket->{customer_user_email} ||= $RecipientEmail;
        if ( !$Ticket->{customer_user_firstname} && !$Ticket->{customer_user_lastname} && $RecipientName ) {
            my ( $Firstname, $Lastname ) = split /\s+/, $RecipientName, 2;
            $Ticket->{customer_user_firstname} = $Firstname || '';
            $Ticket->{customer_user_lastname}  = $Lastname || '';
        }
    }

    my $SMTPAccount = $Self->_ActiveSMTPAccount();
    if ( !$SMTPAccount ) {
        $Self->{LastError} = 'No active SMTP account found for customer auto-response';
        return 0;
    }

    my ( $FromName, $FromEmail ) = $Self->_SenderAddress(
        Ticket      => $Ticket,
        SMTPAccount => $SMTPAccount,
    );
    if ( !$FromEmail ) {
        $Self->{LastError} = 'No sender address found for customer auto-response';
        return 0;
    }

    my $Placeholder = $Self->_PlaceholderBuild(
        Ticket          => $Ticket,
        TicketLinkPage  => 'CustomerTicketZoom',
        Language        => $Language,
    );
    $Placeholder->{'Incoming.Subject'}   = $Param{IncomingSubject} || '';
    $Placeholder->{'Incoming.FromName'}  = $Param{IncomingFromName} || $RecipientName;
    $Placeholder->{'Incoming.FromEmail'} = $Param{IncomingFromEmail} || $RecipientEmail;
    $Placeholder->{'Incoming.ToEmail'}   = $Param{IncomingToEmail} || '';

    my $Subject = $Self->_PlaceholderReplacePlain(
        Text        => $Template->{subject} || '',
        Placeholder => $Placeholder,
    );
    $Subject = $Self->_TicketSubjectBuild(
        Subject      => $Subject,
        TicketNumber => $Ticket->{ticket_number},
    ) if $TicketID;

    my $Body = $Self->_PlaceholderReplaceHTML(
        HTML        => $Template->{body_html} || '',
        Placeholder => $Placeholder,
    );
    my $InlineImages = $Self->_MailInlineImages();
    $Body = $Self->_MailHTMLBuild(
        BodyHTML   => $Body,
        InlineLogo => @{$InlineImages} ? 1 : 0,
    );

    my $EventKey = $Self->_EventKeyBuild(
        ResponseType => $Type,
        TicketID     => $TicketID,
        ArticleID    => $Param{ArticleID},
        EventKey     => $Param{EventKey},
        Recipient    => $RecipientEmail,
    );
    if ( $Self->_EventAlreadySent( ResponseType => $Type, EventKey => $EventKey ) ) {
        $Self->{LastError} = 'Customer auto-response was already sent for this event';
        return 0;
    }

    my $ReplyToEmail = $Self->_EmailClean(
        $Param{ReplyToEmail} || $Ticket->{system_email} || ''
    );
    my $ReplyToName = $Self->_Trim(
        $Param{ReplyToName} || $Ticket->{system_email_name} || $FromName
    );

    my $Result = QisutuMail->new( Config => $Self->{Config}, DB => $Self->{DB} )->SMTPSend(
        Account      => $SMTPAccount,
        TicketID     => $TicketID || undef,
        ArticleID    => $Param{ArticleID} || undef,
        Operation    => 'customer_auto_response',
        FromName     => $FromName,
        FromEmail    => $FromEmail,
        ReplyToName  => $ReplyToName,
        ReplyToEmail => $ReplyToEmail,
        EnvelopeFrom => $SMTPAccount->{smtp_username} || $FromEmail,
        ToName       => $RecipientName,
        ToEmail      => $RecipientEmail,
        Subject      => $Subject,
        Body         => $Body,
        InlineImages => $InlineImages,
    );

    if ( !$Result || !$Result->{Success} ) {
        $Self->{LastError} = $Result && $Result->{Message}
            ? $Result->{Message}
            : 'Customer auto-response could not be sent';
        return 0;
    }

    if ( !$Self->_EventLogCreate(
        ResponseType  => $Type,
        TicketID      => $TicketID,
        ArticleID     => $Param{ArticleID},
        RecipientEmail => $RecipientEmail,
        EventKey      => $EventKey,
    ) ) {
        $Self->{LastError} = $Self->{DB}->Error() || 'Customer auto-response event could not be recorded';
        return 0;
    }

    return 1;
}

sub SchemaEnsure {
    my ($Self) = @_;

    return 1 if $Self->{CustomerAutoResponseSchemaChecked};
    return if !$Self->{DB};

    my @SQL = (
        'CREATE TABLE IF NOT EXISTS customer_auto_response_template (
            id BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
            response_type VARCHAR(100) NOT NULL,
            language VARCHAR(10) NOT NULL DEFAULT "de",
            name VARCHAR(255) NOT NULL,
            subject VARCHAR(500) NOT NULL DEFAULT "",
            body_html LONGTEXT NOT NULL,
            active TINYINT(1) NOT NULL DEFAULT 0,
            sort_order INT UNSIGNED NOT NULL DEFAULT 1000,
            created_by_user_id BIGINT UNSIGNED NOT NULL DEFAULT 1,
            changed_by_user_id BIGINT UNSIGNED NOT NULL DEFAULT 1,
            created_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
            changed_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
            PRIMARY KEY (id),
            UNIQUE KEY customer_auto_response_template_type_language_unique (response_type, language),
            KEY customer_auto_response_template_language_active_sort (language, active, sort_order)
        ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci',
        'CREATE TABLE IF NOT EXISTS customer_auto_response_event_log (
            id BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
            response_type VARCHAR(100) NOT NULL,
            ticket_id BIGINT UNSIGNED NOT NULL DEFAULT 0,
            article_id BIGINT UNSIGNED NOT NULL DEFAULT 0,
            recipient_email VARCHAR(255) NOT NULL,
            event_key VARCHAR(255) NOT NULL,
            sent_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
            PRIMARY KEY (id),
            UNIQUE KEY customer_auto_response_event_unique (response_type, event_key),
            KEY customer_auto_response_event_ticket (ticket_id),
            KEY customer_auto_response_event_article (article_id)
        ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci',
    );

    for my $SQL (@SQL) {
        if ( !$Self->{DB}->Do($SQL) ) {
            $Self->{LastError} = $Self->{DB}->Error() || 'Customer auto-response schema could not be prepared';
            return;
        }
    }

    my $LanguageColumn = $Self->_SchemaObjectCount(
        SQL => 'SELECT COUNT(*) AS object_count
                FROM information_schema.COLUMNS
                WHERE TABLE_SCHEMA = DATABASE()
                  AND TABLE_NAME = ?
                  AND COLUMN_NAME = ?',
        Bind => [ 'customer_auto_response_template', 'language' ],
    );
    return if !defined $LanguageColumn;

    if ( !$LanguageColumn ) {
        my $OK = $Self->{DB}->Do(
            'ALTER TABLE customer_auto_response_template
             ADD COLUMN language VARCHAR(10) NOT NULL DEFAULT "de" AFTER response_type'
        );
        if ( !$OK ) {
            $Self->{LastError} = $Self->{DB}->Error() || 'Customer auto-response language column could not be prepared';
            return;
        }
    }

    my $OldUnique = $Self->_SchemaObjectCount(
        SQL => 'SELECT COUNT(*) AS object_count
                FROM information_schema.STATISTICS
                WHERE TABLE_SCHEMA = DATABASE()
                  AND TABLE_NAME = ?
                  AND INDEX_NAME = ?',
        Bind => [ 'customer_auto_response_template', 'customer_auto_response_template_type_unique' ],
    );
    return if !defined $OldUnique;

    if ($OldUnique) {
        my $OK = $Self->{DB}->Do(
            'ALTER TABLE customer_auto_response_template
             DROP INDEX customer_auto_response_template_type_unique'
        );
        if ( !$OK ) {
            $Self->{LastError} = $Self->{DB}->Error() || 'Old customer auto-response template index could not be removed';
            return;
        }
    }

    my $LanguageUnique = $Self->_SchemaObjectCount(
        SQL => 'SELECT COUNT(*) AS object_count
                FROM information_schema.STATISTICS
                WHERE TABLE_SCHEMA = DATABASE()
                  AND TABLE_NAME = ?
                  AND INDEX_NAME = ?',
        Bind => [ 'customer_auto_response_template', 'customer_auto_response_template_type_language_unique' ],
    );
    return if !defined $LanguageUnique;

    if ( !$LanguageUnique ) {
        my $OK = $Self->{DB}->Do(
            'ALTER TABLE customer_auto_response_template
             ADD UNIQUE KEY customer_auto_response_template_type_language_unique (response_type, language)'
        );
        if ( !$OK ) {
            $Self->{LastError} = $Self->{DB}->Error() || 'Customer auto-response language index could not be prepared';
            return;
        }
    }

    my $LanguageSort = $Self->_SchemaObjectCount(
        SQL => 'SELECT COUNT(*) AS object_count
                FROM information_schema.STATISTICS
                WHERE TABLE_SCHEMA = DATABASE()
                  AND TABLE_NAME = ?
                  AND INDEX_NAME = ?',
        Bind => [ 'customer_auto_response_template', 'customer_auto_response_template_language_active_sort' ],
    );
    return if !defined $LanguageSort;

    if ( !$LanguageSort ) {
        my $OK = $Self->{DB}->Do(
            'ALTER TABLE customer_auto_response_template
             ADD KEY customer_auto_response_template_language_active_sort (language, active, sort_order)'
        );
        if ( !$OK ) {
            $Self->{LastError} = $Self->{DB}->Error() || 'Customer auto-response language sort index could not be prepared';
            return;
        }
    }

    $Self->{CustomerAutoResponseSchemaChecked} = 1;
    return 1;
}

sub PlaceholderList {
    return [
        { placeholder => '{{Ticket.Number}}',          description => 'Ticketnummer' },
        { placeholder => '{{Ticket.Title}}',           description => 'Tickettitel' },
        { placeholder => '{{Ticket.Queue}}',           description => 'Queue des Tickets' },
        { placeholder => '{{Ticket.State}}',           description => 'Aktueller Ticketstatus' },
        { placeholder => '{{Ticket.Priority}}',        description => 'Priorität des Tickets' },
        { placeholder => '{{Ticket.Link}}',            description => 'URL zum Ticket im Kundenportal' },
        { placeholder => '{{Ticket.LinkHTML}}',        description => 'Klickbarer Ticket-Link zum Kundenportal' },
        { placeholder => '{{Customer.Name}}',          description => 'Kundenname' },
        { placeholder => '{{Customer.Number}}',        description => 'Kundennummer' },
        { placeholder => '{{CustomerUser.FullName}}',  description => 'Name des Ansprechpartners' },
        { placeholder => '{{CustomerUser.Firstname}}', description => 'Vorname des Ansprechpartners' },
        { placeholder => '{{CustomerUser.Lastname}}',  description => 'Nachname des Ansprechpartners' },
        { placeholder => '{{CustomerUser.Login}}',     description => 'Login des Ansprechpartners' },
        { placeholder => '{{CustomerUser.Email}}',     description => 'E-Mail-Adresse des Ansprechpartners' },
        { placeholder => '{{Incoming.Subject}}',       description => 'Betreff der eingegangenen E-Mail' },
        { placeholder => '{{Incoming.FromName}}',      description => 'Name des E-Mail-Absenders' },
        { placeholder => '{{Incoming.FromEmail}}',     description => 'E-Mail-Adresse des Absenders' },
        { placeholder => '{{Incoming.ToEmail}}',       description => 'Empfängeradresse der eingegangenen E-Mail' },
        { placeholder => '{{System.Name}}',            description => 'Systemname' },
        { placeholder => '{{System.BaseURL}}',         description => 'Basis-URL des Systems' },
        { placeholder => '{{System.TicketHook}}',      description => 'Ticket-Hook für E-Mail-Betreff' },
        { placeholder => '{{System.DefaultLanguage}}', description => 'Standard-Systemsprache' },
    ];
}

sub _DefaultTemplatesEnsure {
    my ($Self) = @_;

    return 1 if $Self->{CustomerAutoResponseDefaultsEnsured};

    for my $Language ( @{ $Self->LanguageList() } ) {
        for my $Template ( @{ $Self->ResponseTypes( Language => $Language->{code} ) } ) {
            my $Result = $Self->{DB}->Do(
                'INSERT INTO customer_auto_response_template (
                    response_type, language, name, subject, body_html, active, sort_order,
                    created_by_user_id, changed_by_user_id
                 ) VALUES (?, ?, ?, ?, ?, 0, ?, 1, 1)
                 ON DUPLICATE KEY UPDATE name = VALUES(name), sort_order = VALUES(sort_order)',
                $Template->{type},
                $Language->{code},
                $Template->{name},
                $Template->{subject},
                $Template->{body_html},
                $Template->{sort_order},
            );
            if ( !$Result ) {
                $Self->{LastError} = $Self->{DB}->Error() || 'Default customer auto-response templates could not be prepared';
                return;
            }
        }
    }

    $Self->{CustomerAutoResponseDefaultsEnsured} = 1;
    return 1;
}

sub _ResponseTypeClean {
    my ( $Self, $Type ) = @_;

    $Type = $Self->_Trim($Type);
    my %Allowed = map { $_->{type} => 1 } @{ $Self->ResponseTypes( Language => 'en' ) };
    if ( !$Type || !$Allowed{$Type} ) {
        $Self->{LastError} = 'Invalid customer auto-response type';
        return '';
    }
    return $Type;
}

sub _RecipientLanguage {
    my ( $Self, %Param ) = @_;

    if ( defined $Param{Language} && $Param{Language} ne '' ) {
        return $Self->LanguageClean( $Param{Language} );
    }

    my $Ticket = ref $Param{Ticket} eq 'HASH' ? $Param{Ticket} : {};
    my $Row;

    if ( ( $Ticket->{customer_user_id} || 0 ) =~ m{\A\d+\z} && $Ticket->{customer_user_id} ) {
        $Row = $Self->{DB}->SelectRow(
            'SELECT language_preference.preference_value AS language
             FROM customer_user cu
             LEFT JOIN user_preference language_preference
                ON language_preference.user_account_id = cu.user_account_id
               AND language_preference.preference_key = "language"
             WHERE cu.id = ?
             LIMIT 1',
            $Ticket->{customer_user_id},
        );
    }

    if ( !$Row && ( $Param{RecipientEmail} || '' ) ) {
        $Row = $Self->{DB}->SelectRow(
            'SELECT language_preference.preference_value AS language
             FROM user_account ua
             LEFT JOIN user_preference language_preference
                ON language_preference.user_account_id = ua.id
               AND language_preference.preference_key = "language"
             WHERE LOWER(ua.email) = LOWER(?)
               AND ua.account_type = "customer"
               AND ua.is_active = 1
             ORDER BY ua.id ASC
             LIMIT 1',
            $Param{RecipientEmail},
        );
    }

    return $Self->LanguageClean( $Row ? $Row->{language} : '' );
}

sub _TicketSubjectBuild {
    my ( $Self, %Param ) = @_;

    my $Subject      = $Param{Subject} || '';
    my $TicketNumber = $Param{TicketNumber} || '';
    return $Subject if !$TicketNumber;

    my $System = $Self->_SystemPlaceholderHash();
    my $Hook = $System->{'System.TicketHook'} || 'Qisutu';
    my $QuotedHook = quotemeta($Hook);
    $Subject =~ s{\[$QuotedHook\#[^\]]+\]\s*}{}ig;
    $Subject =~ s{[\r\n]+}{ }g;
    $Subject =~ s{\s+}{ }g;
    $Subject =~ s{\A\s+|\s+\z}{}g;
    $Subject ||= $TicketNumber;

    my $FullSubject = '[' . $Hook . '#' . $TicketNumber . '] ' . $Subject;
    return length($FullSubject) > 500 ? substr( $FullSubject, 0, 500 ) : $FullSubject;
}

sub _EmailClean {
    my ( $Self, $Email ) = @_;

    $Email = $Self->_Trim($Email);
    $Email =~ s{[\r\n\x00]}{}g;
    return '' if $Email !~ m{\A[^\s\@]+\@[^\s\@]+\.[^\s\@]+\z};
    return lc $Email;
}

sub _AutomatedMessage {
    my ( $Self, %Param ) = @_;

    my $Headers = ref $Param{Headers} eq 'HASH' ? $Param{Headers} : {};
    my $AutoSubmitted = lc( $Headers->{'auto-submitted'} || '' );
    return 1 if $AutoSubmitted && $AutoSubmitted ne 'no';
    return 1 if lc( $Headers->{precedence} || '' ) =~ m{\A(?:bulk|junk|list)\z};
    return 1 if $Headers->{'x-auto-response-suppress'};
    return 0;
}

sub _EventKeyBuild {
    my ( $Self, %Param ) = @_;

    my $EventKey = $Self->_Trim( $Param{EventKey} );
    return substr( $EventKey, 0, 255 ) if $EventKey;

    $EventKey = join ':',
        $Param{ResponseType} || '',
        $Param{TicketID} || 0,
        $Param{ArticleID} || 0,
        lc( $Param{Recipient} || '' );
    return substr( $EventKey, 0, 255 );
}

sub _EventAlreadySent {
    my ( $Self, %Param ) = @_;

    my $Row = $Self->{DB}->SelectRow(
        'SELECT id
         FROM customer_auto_response_event_log
         WHERE response_type = ? AND event_key = ?
         LIMIT 1',
        $Param{ResponseType} || '',
        $Param{EventKey} || '',
    );
    return $Row ? 1 : 0;
}

sub _EventLogCreate {
    my ( $Self, %Param ) = @_;

    return $Self->{DB}->Do(
        'INSERT IGNORE INTO customer_auto_response_event_log (
            response_type, ticket_id, article_id, recipient_email, event_key, sent_at
         ) VALUES (?, ?, ?, ?, ?, NOW())',
        $Param{ResponseType} || '',
        $Param{TicketID} || 0,
        $Param{ArticleID} || 0,
        $Param{RecipientEmail} || '',
        $Param{EventKey} || '',
    );
}

1;
