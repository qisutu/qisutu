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

package QisutuNotification;

use strict;
use warnings;
use utf8;

use QisutuHTML;
use QisutuMail;

sub new {
    my ( $Class, %Param ) = @_;

    my $Self = {
        DB        => $Param{DB},
        Config    => $Param{Config},
        LastError => '',
    };

    bless $Self, $Class;

    return $Self;
}

sub NotificationTypes {
    return [
        {
            type       => 'ticket_new_in_my_queues',
            name       => 'Neues Ticket in meinen Queues',
            sort_order => 100,
            subject    => 'Neues Ticket {{Ticket.Number}} in {{Ticket.Queue}}',
            body_html  => '<p>Hallo {{Agent.FullName}},</p><p>in deiner Queue <strong>{{Ticket.Queue}}</strong> wurde ein neues Ticket erstellt.</p><p><strong>{{Ticket.Number}}</strong> - {{Ticket.Title}}</p><p>{{Ticket.LinkHTML}}</p>',
        },
        {
            type       => 'customer_reply_in_my_queues',
            name       => 'Kundenantwort in Tickets von meinen Queues',
            sort_order => 200,
            subject    => 'Kundenantwort in Ticket {{Ticket.Number}}',
            body_html  => '<p>Hallo {{Agent.FullName}},</p><p>in deiner Queue <strong>{{Ticket.Queue}}</strong> gibt es eine neue Kundenantwort.</p><p><strong>{{Ticket.Number}}</strong> - {{Ticket.Title}}</p><p>Kunde: {{Customer.Name}}<br>Ansprechpartner: {{CustomerUser.FullName}}</p><p>{{Ticket.LinkHTML}}</p>',
        },
        {
            type       => 'ticket_assigned_to_me',
            name       => 'Ticket wurde mir zugewiesen',
            sort_order => 300,
            subject    => 'Ticket {{Ticket.Number}} wurde dir zugewiesen',
            body_html  => '<p>Hallo {{Agent.FullName}},</p><p>das Ticket <strong>{{Ticket.Number}}</strong> wurde dir zugewiesen.</p><p>{{Ticket.Title}}</p><p>{{Ticket.LinkHTML}}</p>',
        },
        {
            type       => 'ticket_state_changed',
            name       => 'Ticketstatus wurde geändert',
            sort_order => 400,
            subject    => 'Status geändert: Ticket {{Ticket.Number}}',
            body_html  => '<p>Hallo {{Agent.FullName}},</p><p>der Status des Tickets <strong>{{Ticket.Number}}</strong> in deiner Queue <strong>{{Ticket.Queue}}</strong> wurde geändert.</p><p>Neuer Status: <strong>{{Ticket.State}}</strong></p><p>{{Ticket.LinkHTML}}</p>',
        },
        {
            type       => 'ticket_escalation_reached',
            name       => 'bei Eskalation',
            sort_order => 500,
            subject    => 'Eskalation erreicht: Ticket {{Ticket.Number}}',
            body_html  => '<p>Hallo {{Agent.FullName}},</p><p>das Ticket <strong>{{Ticket.Number}}</strong> in deiner Queue <strong>{{Ticket.Queue}}</strong> ist eskaliert.</p><p>{{Ticket.Title}}</p><p>{{Ticket.LinkHTML}}</p>',
        },
        {
            type       => 'ticket_pending_reached',
            name       => 'bei Warten Status erreicht',
            sort_order => 600,
            subject    => 'Warten erreicht: Ticket {{Ticket.Number}}',
            body_html  => '<p>Hallo {{Agent.FullName}},</p><p>bei Ticket <strong>{{Ticket.Number}}</strong> in deiner Queue <strong>{{Ticket.Queue}}</strong> ist der Warten-Status erreicht.</p><p>Warten bis: <strong>{{PendingUntil}}</strong><br>Erreicht seit: <strong>{{PendingReachedSince}}</strong></p><p>{{Ticket.LinkHTML}}</p>',
        },
    ];
}

sub TemplateList {
    my ( $Self, %Param ) = @_;

    $Self->SchemaEnsure() || return [];
    $Self->_DefaultTemplatesEnsure();

    my $Rows = $Self->{DB}->SelectAll(
        'SELECT *
         FROM agent_notification_template
         ORDER BY sort_order ASC, name ASC'
    );

    if ( !$Rows ) {
        $Self->{LastError} = $Self->{DB}->Error() || 'Agent notification templates could not be loaded';
        return [];
    }

    my %Known = map { $_->{type} => $_ } @{ NotificationTypes() };

    for my $Row ( @{$Rows} ) {
        $Row->{active_label} = $Row->{active} ? 'Translate:AdminActiveYes' : 'Translate:AdminActiveNo';
        $Row->{display_name} = $Known{ $Row->{notification_type} }
            ? $Known{ $Row->{notification_type} }->{name}
            : ( $Row->{name} || $Row->{notification_type} );
        $Row->{body_preview} = QisutuHTML->PlainTextPreview( $Row->{body_html} || '', 160 );
    }

    return $Rows;
}

sub TemplateGet {
    my ( $Self, %Param ) = @_;

    my $Type = $Self->_NotificationTypeClean( $Param{NotificationType} );
    return if !$Type;

    $Self->SchemaEnsure() || return;
    $Self->_DefaultTemplatesEnsure();

    my $Template = $Self->{DB}->SelectRow(
        'SELECT *
         FROM agent_notification_template
         WHERE notification_type = ?
         LIMIT 1',
        $Type,
    );

    if ( !$Template ) {
        $Self->{LastError} = 'Agent notification template was not found';
        return;
    }

    return $Template;
}

sub TemplateUpdate {
    my ( $Self, %Param ) = @_;

    my $Type = $Self->_NotificationTypeClean( $Param{NotificationType} );
    return if !$Type;

    $Self->SchemaEnsure() || return;
    $Self->_DefaultTemplatesEnsure();

    my $Subject = $Self->_Trim( $Param{Subject} );
    my $Body    = QisutuHTML->Sanitize( $Param{BodyHTML} || '' );
    my $Active  = $Param{Active} ? 1 : 0;
    my $UserID  = $Param{ChangedByUserID} || 1;

    if ( !$Subject || !$Body ) {
        $Self->{LastError} = 'Subject and text are required';
        return;
    }

    my $Result = $Self->{DB}->Do(
        'UPDATE agent_notification_template
         SET subject = ?,
             body_html = ?,
             active = ?,
             changed_by_user_id = ?
         WHERE notification_type = ?',
        $Subject,
        $Body,
        $Active,
        $UserID,
        $Type,
    );

    if ( !$Result ) {
        $Self->{LastError} = $Self->{DB}->Error() || 'Agent notification template could not be saved';
        return;
    }

    return 1;
}

sub Send {
    my ( $Self, %Param ) = @_;

    $Self->{LastError} = '';

    my $Type = $Self->_NotificationTypeClean( $Param{NotificationType} || $Param{Type} );
    if ( !$Type ) {
        $Self->{LastError} ||= 'Invalid agent notification type';
        return 0;
    }

    my $TicketID = $Param{TicketID} || 0;
    if ( $TicketID !~ m{\A\d+\z} || !$TicketID ) {
        $Self->{LastError} = 'Valid TicketID is required for agent notification';
        return 0;
    }

    if ( !$Self->SchemaEnsure() ) {
        $Self->{LastError} ||= 'Agent notification schema could not be prepared';
        return 0;
    }

    $Self->_DefaultTemplatesEnsure();
    if ( $Self->{LastError} ) {
        return 0;
    }

    my $Template = $Self->TemplateGet( NotificationType => $Type );
    if ( !$Template ) {
        $Self->{LastError} ||= 'Agent notification template was not found';
        return 0;
    }

    if ( !$Template->{active} ) {
        $Self->{LastError} = 'Agent notification template is inactive';
        return 0;
    }

    my $Ticket = $Self->_TicketDataGet( TicketID => $TicketID );
    if ( !$Ticket ) {
        $Self->{LastError} ||= 'Ticket data could not be loaded for agent notification';
        return 0;
    }

    my $RecipientList = $Self->_RecipientList(
        NotificationType => $Type,
        Ticket           => $Ticket,
        TargetUserID     => $Param{TargetUserID},
    );

    if ( !@{$RecipientList} ) {
        $Self->{LastError} = 'No active agent recipients found for ticket queue';
        return 0;
    }

    $RecipientList = $Self->_RecipientPreferenceFilter(
        NotificationType => $Type,
        RecipientList    => $RecipientList,
    );

    if ( !@{$RecipientList} ) {
        $Self->{LastError} = 'No agent recipients found after personal notification preferences';
        return 0;
    }

    my $SMTPAccount = $Self->_ActiveSMTPAccount();
    if ( !$SMTPAccount ) {
        $Self->{LastError} = 'No active SMTP account found for agent notification';
        return 0;
    }

    my ( $FromName, $FromEmail ) = $Self->_SenderAddress( Ticket => $Ticket, SMTPAccount => $SMTPAccount );
    if ( !$FromEmail ) {
        $Self->{LastError} = 'No sender address found for agent notification';
        return 0;
    }

    my $EventKey = $Self->_EventKey(
        NotificationType => $Type,
        Ticket           => $Ticket,
        EventKey         => $Param{EventKey},
    );

    my $Sent = 0;
    my @ErrorMessages;

    for my $Agent ( @{$RecipientList} ) {
        next if !$Agent->{email};

        if ( $Self->_RequiresEventLog( NotificationType => $Type ) ) {
            next if $Self->_EventAlreadySent(
                NotificationType => $Type,
                TicketID         => $TicketID,
                RecipientUserID  => $Agent->{id},
                EventKey         => $EventKey,
            );
        }

        my $Placeholder = $Self->_PlaceholderBuild(
            Ticket       => $Ticket,
            Agent        => $Agent,
            ChangedByID  => $Param{ChangedByUserID},
            AssignedID   => $Param{TargetUserID},
        );

        my $Subject = $Self->_PlaceholderReplacePlain(
            Text        => $Template->{subject} || '',
            Placeholder => $Placeholder,
        );

        my $Body = $Self->_PlaceholderReplaceHTML(
            HTML        => $Template->{body_html} || '',
            Placeholder => $Placeholder,
        );

        my $InlineImages = $Self->_MailInlineImages();

        $Body = $Self->_MailHTMLBuild(
            BodyHTML   => $Body,
            InlineLogo => @{$InlineImages} ? 1 : 0,
        );

        my $Result = QisutuMail->new( Config => $Self->{Config}, DB => $Self->{DB} )->SMTPSend(
            Account      => $SMTPAccount,
            TicketID     => $TicketID,
            Operation    => 'notification',
            FromName     => $FromName,
            FromEmail    => $FromEmail,
            ReplyToName  => $Ticket->{system_email_name} || $FromName,
            ReplyToEmail => $Ticket->{system_email} || '',
            EnvelopeFrom => $SMTPAccount->{smtp_username} || $FromEmail,
            ToName       => $Agent->{full_name},
            ToEmail      => $Agent->{email},
            Subject      => $Subject,
            Body         => $Body,
            InlineImages => $InlineImages,
        );

        if ( $Result && $Result->{Success} ) {
            $Sent++;

            if ( $Self->_RequiresEventLog( NotificationType => $Type ) ) {
                $Self->_EventLogCreate(
                    NotificationType => $Type,
                    TicketID         => $TicketID,
                    RecipientUserID  => $Agent->{id},
                    EventKey         => $EventKey,
                );
            }

            next;
        }

        push @ErrorMessages,
            ( $Agent->{email} || 'unknown recipient' ) . ': '
            . ( $Result && $Result->{Message} ? $Result->{Message} : 'SMTP message could not be sent' );
    }

    if ( !$Sent && @ErrorMessages ) {
        $Self->{LastError} = join '; ', @ErrorMessages;
    }
    elsif ( !$Sent ) {
        $Self->{LastError} = 'No agent notification was sent';
    }

    return $Sent;
}

sub SendTicketNew {
    my ( $Self, %Param ) = @_;

    return $Self->Send(
        %Param,
        NotificationType => 'ticket_new_in_my_queues',
    );
}

sub SendCustomerReply {
    my ( $Self, %Param ) = @_;

    return $Self->Send(
        %Param,
        NotificationType => 'customer_reply_in_my_queues',
    );
}

sub SendTicketAssigned {
    my ( $Self, %Param ) = @_;

    return $Self->Send(
        %Param,
        NotificationType => 'ticket_assigned_to_me',
    );
}

sub SendTicketStateChanged {
    my ( $Self, %Param ) = @_;

    return $Self->Send(
        %Param,
        NotificationType => 'ticket_state_changed',
    );
}

sub SendTicketEscalationReached {
    my ( $Self, %Param ) = @_;

    return $Self->Send(
        %Param,
        NotificationType => 'ticket_escalation_reached',
    );
}

sub SendTicketPendingReached {
    my ( $Self, %Param ) = @_;

    return $Self->Send(
        %Param,
        NotificationType => 'ticket_pending_reached',
    );
}

sub SchemaEnsure {
    my ($Self) = @_;

    return 1 if $Self->{SchemaChecked};
    return if !$Self->{DB};

    my @SQL = (
        'CREATE TABLE IF NOT EXISTS agent_notification_template (
            id BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
            notification_type VARCHAR(100) NOT NULL,
            name VARCHAR(255) NOT NULL,
            subject VARCHAR(500) NOT NULL DEFAULT "",
            body_html LONGTEXT NOT NULL,
            active TINYINT(1) NOT NULL DEFAULT 1,
            sort_order INT UNSIGNED NOT NULL DEFAULT 1000,
            created_by_user_id BIGINT UNSIGNED NOT NULL DEFAULT 1,
            changed_by_user_id BIGINT UNSIGNED NOT NULL DEFAULT 1,
            created_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
            changed_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
            PRIMARY KEY (id),
            UNIQUE KEY agent_notification_template_type_unique (notification_type),
            KEY agent_notification_template_active_sort (active, sort_order)
        ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci',

        'CREATE TABLE IF NOT EXISTS agent_notification_event_log (
            id BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
            notification_type VARCHAR(100) NOT NULL,
            ticket_id BIGINT UNSIGNED NOT NULL,
            recipient_user_id BIGINT UNSIGNED NOT NULL,
            event_key VARCHAR(255) NOT NULL,
            sent_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
            PRIMARY KEY (id),
            UNIQUE KEY agent_notification_event_unique (notification_type, ticket_id, recipient_user_id, event_key),
            KEY agent_notification_event_ticket (ticket_id),
            KEY agent_notification_event_recipient (recipient_user_id)
        ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci'
    );

    for my $SQL (@SQL) {
        my $OK = $Self->{DB}->Do($SQL);

        if ( !$OK ) {
            $Self->{LastError} = $Self->{DB}->Error() || 'Agent notification schema could not be prepared';
            return;
        }
    }

    $Self->{SchemaChecked} = 1;

    return 1;
}

sub PlaceholderList {
    return [
        { placeholder => '{{Agent.FullName}}',        description => 'Name des Empfänger-Agenten' },
        { placeholder => '{{Agent.Firstname}}',       description => 'Vorname des Empfänger-Agenten' },
        { placeholder => '{{Agent.Lastname}}',        description => 'Nachname des Empfänger-Agenten' },
        { placeholder => '{{Agent.Login}}',           description => 'Login des Empfänger-Agenten' },
        { placeholder => '{{Agent.Email}}',           description => 'E-Mail-Adresse des Empfänger-Agenten' },
        { placeholder => '{{Ticket.Number}}',         description => 'Ticketnummer' },
        { placeholder => '{{Ticket.Title}}',          description => 'Tickettitel' },
        { placeholder => '{{Ticket.Queue}}',          description => 'Queue des Tickets' },
        { placeholder => '{{Ticket.State}}',          description => 'Aktueller Ticketstatus' },
        { placeholder => '{{Ticket.Priority}}',       description => 'Priorität des Tickets' },
        { placeholder => '{{Ticket.Link}}',           description => 'URL zum Ticket' },
        { placeholder => '{{Ticket.LinkHTML}}',       description => 'fertiger HTML-Link zum Ticket' },
        { placeholder => '{{System.Name}}',           description => 'Systemname' },
        { placeholder => '{{System.HTTPType}}',       description => 'HTTP-Typ des Systems' },
        { placeholder => '{{System.FQDN}}',           description => 'FQDN des Systems' },
        { placeholder => '{{System.WebPath}}',        description => 'Web-Pfad des Systems' },
        { placeholder => '{{System.BaseURL}}',        description => 'Basis-URL des Systems' },
        { placeholder => '{{System.TicketHook}}',    description => 'Ticket-Hook für E-Mail-Betreff' },
        { placeholder => '{{System.DefaultLanguage}}', description => 'Standard-Systemsprache' },
        { placeholder => '{{Customer.Name}}',         description => 'Kundenname' },
        { placeholder => '{{Customer.Number}}',       description => 'Kundennummer' },
        { placeholder => '{{CustomerUser.FullName}}', description => 'Name des Kundenbenutzers' },
        { placeholder => '{{CustomerUser.Firstname}}', description => 'Vorname des Kundenbenutzers' },
        { placeholder => '{{CustomerUser.Lastname}}', description => 'Nachname des Kundenbenutzers' },
        { placeholder => '{{CustomerUser.Login}}',    description => 'Login des Kundenbenutzers' },
        { placeholder => '{{CustomerUser.Email}}',    description => 'E-Mail-Adresse des Kundenbenutzers' },
        { placeholder => '{{ChangedBy.FullName}}',    description => 'Name des ändernden Benutzers' },
        { placeholder => '{{ChangedBy.Firstname}}',   description => 'Vorname des ändernden Benutzers' },
        { placeholder => '{{ChangedBy.Lastname}}',    description => 'Nachname des ändernden Benutzers' },
        { placeholder => '{{ChangedBy.Login}}',       description => 'Login des ändernden Benutzers' },
        { placeholder => '{{ChangedBy.Email}}',       description => 'E-Mail-Adresse des ändernden Benutzers' },
        { placeholder => '{{AssignedAgent.FullName}}', description => 'Name des zugewiesenen Agenten' },
        { placeholder => '{{AssignedAgent.Firstname}}', description => 'Vorname des zugewiesenen Agenten' },
        { placeholder => '{{AssignedAgent.Lastname}}', description => 'Nachname des zugewiesenen Agenten' },
        { placeholder => '{{AssignedAgent.Login}}',    description => 'Login des zugewiesenen Agenten' },
        { placeholder => '{{AssignedAgent.Email}}',    description => 'E-Mail-Adresse des zugewiesenen Agenten' },
        { placeholder => '{{PendingUntil}}',          description => 'Warten-bis-Zeitpunkt' },
        { placeholder => '{{PendingReachedSince}}',   description => 'Dauer seit erreichtem Warten-Status' },
        { placeholder => '{{Escalation.Type}}',       description => 'Eskalationsart' },
        { placeholder => '{{Escalation.DueTime}}',    description => 'nächster oder erreichter Eskalationszeitpunkt' },
    ];
}

sub ContentPlaceholderList {
    my @Placeholder = map { { %{$_} } } @{ PlaceholderList() };

    my %Description = (
        '{{Agent.FullName}}'  => 'Name des angemeldeten Agenten',
        '{{Agent.Firstname}}' => 'Vorname des angemeldeten Agenten',
        '{{Agent.Lastname}}'  => 'Nachname des angemeldeten Agenten',
        '{{Agent.Login}}'     => 'Login des angemeldeten Agenten',
        '{{Agent.Email}}'     => 'E-Mail-Adresse des angemeldeten Agenten',
    );

    for my $Item (@Placeholder) {
        next if !$Description{ $Item->{placeholder} || '' };
        $Item->{description} = $Description{ $Item->{placeholder} };
    }

    return \@Placeholder;
}

sub SystemPlaceholderHash {
    my ($Self) = @_;

    return { %{ $Self->_SystemPlaceholderHash() || {} } };
}

sub ContentTemplateRenderHTML {
    my ( $Self, %Param ) = @_;

    my $HTML = $Param{HTML} || '';
    return '' if !$HTML;

    my $Ticket = ref $Param{Ticket} eq 'HASH' ? { %{ $Param{Ticket} } } : undef;
    if ( !$Ticket && ( $Param{TicketID} || 0 ) ) {
        $Ticket = $Self->_TicketDataGet( TicketID => $Param{TicketID} );
    }
    $Ticket ||= {};

    if ( !$Ticket->{customer_user_name} ) {
        $Ticket->{customer_user_name} = $Self->_UserName(
            Firstname => $Ticket->{customer_user_firstname},
            Lastname  => $Ticket->{customer_user_lastname},
            Login     => $Ticket->{customer_user_login},
        );
    }

    my $Agent = ref $Param{Agent} eq 'HASH' ? { %{ $Param{Agent} } } : undef;
    if ( !$Agent && ( $Param{AgentUserID} || 0 ) ) {
        $Agent = $Self->_UserDataGet( UserID => $Param{AgentUserID} );
    }
    $Agent ||= {};
    if ( !$Agent->{full_name} ) {
        $Agent->{full_name} = $Self->_UserName(
            Firstname => $Agent->{firstname},
            Lastname  => $Agent->{lastname},
            Login     => $Agent->{login},
        );
    }

    my $ChangedBy = ref $Param{ChangedBy} eq 'HASH' ? { %{ $Param{ChangedBy} } } : undef;
    if ( $ChangedBy && !$ChangedBy->{full_name} ) {
        $ChangedBy->{full_name} = $Self->_UserName(
            Firstname => $ChangedBy->{firstname},
            Lastname  => $ChangedBy->{lastname},
            Login     => $ChangedBy->{login},
        );
    }

    my $Assigned = ref $Param{Assigned} eq 'HASH' ? { %{ $Param{Assigned} } } : undef;
    if ( $Assigned && !$Assigned->{full_name} ) {
        $Assigned->{full_name} = $Self->_UserName(
            Firstname => $Assigned->{firstname},
            Lastname  => $Assigned->{lastname},
            Login     => $Assigned->{login},
        );
    }

    my $Placeholder = $Self->_PlaceholderBuild(
        Ticket      => $Ticket,
        Agent       => $Agent,
        ChangedBy   => $ChangedBy,
        ChangedByID => $Param{ChangedByID},
        Assigned    => $Assigned,
        AssignedID  => $Param{AssignedID},
        TicketLinkPage => $Param{TicketLinkPage},
        SystemPlaceholder => $Param{SystemPlaceholder},
    );

    return $Self->_PlaceholderReplaceHTML(
        HTML              => $HTML,
        Placeholder       => $Placeholder,
        PreserveEmptyKeys => $Param{PreserveEmptyKeys},
    );
}

sub _DefaultTemplatesEnsure {
    my ($Self) = @_;

    return if $Self->{DefaultsEnsured};

    for my $Template ( @{ NotificationTypes() } ) {
        my $Result = $Self->{DB}->Do(
            'INSERT INTO agent_notification_template (
                notification_type,
                name,
                subject,
                body_html,
                active,
                sort_order,
                created_by_user_id,
                changed_by_user_id
             ) VALUES (
                ?, ?, ?, ?, 1, ?, 1, 1
             )
             ON DUPLICATE KEY UPDATE
                name = VALUES(name),
                sort_order = VALUES(sort_order)',
            $Template->{type},
            $Template->{name},
            $Template->{subject},
            $Template->{body_html},
            $Template->{sort_order},
        );

        if ( !$Result ) {
            $Self->{LastError} = $Self->{DB}->Error() || 'Default agent notification templates could not be prepared';
            return;
        }
    }

    $Self->{DefaultsEnsured} = 1;

    return 1;
}

sub _RecipientList {
    my ( $Self, %Param ) = @_;

    my $Type   = $Param{NotificationType} || '';
    my $Ticket = $Param{Ticket} || {};

    if ( $Type eq 'ticket_assigned_to_me' ) {
        my $TargetUserID = $Param{TargetUserID} || $Ticket->{owner_user_id} || 0;
        return $Self->_AgentByUserID( UserID => $TargetUserID );
    }

    return $Self->_QueueAgentList( QueueID => $Ticket->{queue_id} );
}

sub _RecipientPreferenceFilter {
    my ( $Self, %Param ) = @_;

    my $Type          = $Param{NotificationType} || '';
    my $RecipientList = $Param{RecipientList} || [];

    return $RecipientList if !$Self->_NotificationCanBeDisabled( NotificationType => $Type );

    my @Filtered;

    for my $Agent ( @{$RecipientList} ) {
        next if ref $Agent ne 'HASH';

        push @Filtered, $Agent if $Self->_AgentNotificationEnabled(
            NotificationType => $Type,
            UserAccountID    => $Agent->{id},
        );
    }

    return \@Filtered;
}

sub _AgentNotificationEnabled {
    my ( $Self, %Param ) = @_;

    my $Type          = $Param{NotificationType} || '';
    my $UserAccountID = $Param{UserAccountID} || 0;

    return 1 if !$Self->_NotificationCanBeDisabled( NotificationType => $Type );
    return 0 if $UserAccountID !~ m{\A\d+\z} || !$UserAccountID;

    my $PreferenceKey = $Self->_NotificationPreferenceKey( NotificationType => $Type );
    return 1 if !$PreferenceKey;

    my $Row = $Self->{DB}->SelectRow(
        'SELECT preference_value
         FROM user_preference
         WHERE user_account_id = ?
            AND preference_key = ?
         LIMIT 1',
        $UserAccountID,
        $PreferenceKey,
    );

    if ( !$Row ) {
        return $Self->_NotificationPreferenceDefault( NotificationType => $Type );
    }

    return ( $Row->{preference_value} || 0 ) ? 1 : 0;
}

sub _NotificationCanBeDisabled {
    my ( $Self, %Param ) = @_;

    my $Type = $Param{NotificationType} || '';

    return 0 if $Type eq 'ticket_escalation_reached';
    return 0 if $Type eq 'ticket_pending_reached';

    return $Self->_NotificationPreferenceKey( NotificationType => $Type ) ? 1 : 0;
}

sub _NotificationPreferenceKey {
    my ( $Self, %Param ) = @_;

    my $Type = $Param{NotificationType} || '';

    my %KeyForType = (
        ticket_new_in_my_queues       => 'notification_new_ticket',
        customer_reply_in_my_queues   => 'notification_customer_reply',
        ticket_assigned_to_me         => 'notification_assigned_ticket',
        ticket_state_changed          => 'notification_status_change',
    );

    return $KeyForType{$Type} || '';
}

sub _NotificationPreferenceDefault {
    my ( $Self, %Param ) = @_;

    my $Type = $Param{NotificationType} || '';

    return 0 if $Type eq 'ticket_state_changed';

    return 1;
}

sub _QueueAgentList {
    my ( $Self, %Param ) = @_;

    my $QueueID = $Param{QueueID} || 0;
    return [] if $QueueID !~ m{\A\d+\z} || !$QueueID;

    my $Rows = $Self->{DB}->SelectAll(
        'SELECT DISTINCT
            ua.id,
            ua.login,
            ua.email,
            ua.firstname,
            ua.lastname
         FROM ticket_queue_group tqg
         INNER JOIN user_group ug
            ON ug.id = tqg.user_group_id
            AND ug.active = 1
         INNER JOIN user_group_member ugm
            ON ugm.user_group_id = ug.id
            AND ugm.active = 1
         INNER JOIN user_account ua
            ON ua.id = ugm.user_account_id
            AND ua.account_type = ?
            AND ua.is_active = 1
            AND ua.is_system_user = 0
         WHERE tqg.queue_id = ?
            AND tqg.active = 1
            AND tqg.permission_key IN (?, ?)
            AND ua.email <> ""
            AND (
                ugm.permission_full = 1
                OR ugm.permission_read = 1
                OR ugm.permission_overview = 1
            )
         ORDER BY ua.login ASC, ua.id ASC',
        'agent',
        $QueueID,
        'ticket.view',
        'ticket.full',
    ) || [];

    if ( !@{$Rows} ) {
        $Rows = $Self->{DB}->SelectAll(
            'SELECT DISTINCT
                ua.id,
                ua.login,
                ua.email,
                ua.firstname,
                ua.lastname
             FROM ticket_queue_group tqg
             INNER JOIN user_group ug
                ON ug.id = tqg.user_group_id
                AND ug.active = 1
             INNER JOIN user_group_member ugm
                ON ugm.user_group_id = ug.id
                AND ugm.active = 1
             INNER JOIN user_account ua
                ON ua.id = ugm.user_account_id
                AND ua.account_type = ?
                AND ua.is_active = 1
                AND ua.is_system_user = 0
             WHERE tqg.queue_id = ?
                AND tqg.active = 1
                AND ua.email <> ""
             ORDER BY ua.login ASC, ua.id ASC',
            'agent',
            $QueueID,
        ) || [];
    }

    for my $Agent ( @{$Rows} ) {
        $Agent->{full_name} = $Self->_UserName(
            Firstname => $Agent->{firstname},
            Lastname  => $Agent->{lastname},
            Login     => $Agent->{login},
        );
    }

    return $Rows;
}

sub _AgentByUserID {
    my ( $Self, %Param ) = @_;

    my $UserID = $Param{UserID} || 0;
    return [] if $UserID !~ m{\A\d+\z} || !$UserID;

    my $Agent = $Self->{DB}->SelectRow(
        'SELECT id, login, email, firstname, lastname
         FROM user_account
         WHERE id = ?
            AND account_type = ?
            AND is_active = 1
            AND is_system_user = 0
            AND email <> ""
         LIMIT 1',
        $UserID,
        'agent',
    );

    return [] if !$Agent;

    $Agent->{full_name} = $Self->_UserName(
        Firstname => $Agent->{firstname},
        Lastname  => $Agent->{lastname},
        Login     => $Agent->{login},
    );

    return [$Agent];
}

sub _TicketDataGet {
    my ( $Self, %Param ) = @_;

    my $TicketID = $Param{TicketID} || 0;
    return if $TicketID !~ m{\A\d+\z} || !$TicketID;

    my $Ticket = $Self->{DB}->SelectRow(
        'SELECT
            t.id,
            t.ticket_number,
            t.title,
            t.queue_id,
            t.state_id,
            t.priority_id,
            t.customer_id,
            t.customer_user_id,
            t.owner_user_id,
            t.responsible_user_id,
            t.first_response_due_at,
            t.update_due_at,
            t.solution_due_at,
            t.pending_until,
            t.escalation_state,
            t.created_at,
            t.changed_at,
            q.name AS queue_name,
            q.full_name AS queue_full_name,
            se.name AS system_email_name,
            se.email AS system_email,
            s.name AS state_name,
            s.state_type,
            p.name AS priority_name,
            c.customer_number,
            c.name AS customer_name,
            cu_account.login AS customer_user_login,
            cu_account.email AS customer_user_email,
            cu_account.firstname AS customer_user_firstname,
            cu_account.lastname AS customer_user_lastname
         FROM ticket t
         INNER JOIN ticket_queue q ON q.id = t.queue_id
         INNER JOIN ticket_state s ON s.id = t.state_id
         INNER JOIN ticket_priority p ON p.id = t.priority_id
         LEFT JOIN system_email se ON se.id = q.system_email_id AND se.active = 1
         LEFT JOIN customer c ON c.id = t.customer_id
         LEFT JOIN customer_user cu ON cu.id = t.customer_user_id
         LEFT JOIN user_account cu_account ON cu_account.id = cu.user_account_id
         WHERE t.id = ?
         LIMIT 1',
        $TicketID,
    );

    return if !$Ticket;

    $Ticket->{customer_user_name} = $Self->_UserName(
        Firstname => $Ticket->{customer_user_firstname},
        Lastname  => $Ticket->{customer_user_lastname},
        Login     => $Ticket->{customer_user_login},
    );

    $Ticket->{pending_reached_since} = '';
    if ( $Ticket->{pending_until} ) {
        my $Duration = $Self->{DB}->SelectRow(
            'SELECT TIMESTAMPDIFF(SECOND, ?, NOW()) AS seconds_since',
            $Ticket->{pending_until},
        );
        if ( $Duration && ( $Duration->{seconds_since} || 0 ) > 0 ) {
            $Ticket->{pending_reached_since} = $Self->_DurationText( Seconds => $Duration->{seconds_since} );
        }
    }

    $Ticket->{escalation_due_time} = $Ticket->{first_response_due_at} || $Ticket->{update_due_at} || $Ticket->{solution_due_at} || '';

    return $Ticket;
}

sub _PlaceholderBuild {
    my ( $Self, %Param ) = @_;

    my $Ticket = $Param{Ticket} || {};
    my $Agent  = $Param{Agent}  || {};
    my $ChangedBy = ref $Param{ChangedBy} eq 'HASH'
        ? $Param{ChangedBy}
        : $Self->_UserDataGet( UserID => $Param{ChangedByID} );
    my $Assigned  = ref $Param{Assigned} eq 'HASH'
        ? $Param{Assigned}
        : $Self->_UserDataGet( UserID => $Param{AssignedID} || $Ticket->{owner_user_id} );
    my $SystemPlaceholder = ref $Param{SystemPlaceholder} eq 'HASH'
        ? $Param{SystemPlaceholder}
        : $Self->_SystemPlaceholderHash();
    my $TicketLink = $Ticket->{id} ? $Self->_TicketLink(
        TicketID => $Ticket->{id},
        Page     => $Param{TicketLinkPage},
    ) : '';
    my $TicketLinkHTML = $TicketLink
        ? '<a href="' . $TicketLink . '">Ticket ' . $Self->_Escape( $Ticket->{ticket_number} || $Ticket->{id} ) . ' öffnen</a>'
        : '';

    return {
        'Agent.FullName'         => $Agent->{full_name} || '',
        'Agent.Firstname'        => $Agent->{firstname} || '',
        'Agent.Lastname'         => $Agent->{lastname} || '',
        'Agent.Login'            => $Agent->{login} || '',
        'Agent.Email'            => $Agent->{email} || '',
        'Ticket.Number'          => $Ticket->{ticket_number} || '',
        'Ticket.Title'           => $Ticket->{title} || '',
        'Ticket.Queue'           => $Ticket->{queue_full_name} || $Ticket->{queue_name} || '',
        'Ticket.State'           => $Ticket->{state_name} || '',
        'Ticket.Priority'        => $Ticket->{priority_name} || '',
        'Ticket.Link'            => $TicketLink,
        'Ticket.LinkHTML'        => $TicketLinkHTML,
        'System.Name'            => $SystemPlaceholder->{'System.Name'} || '',
        'System.HTTPType'        => $SystemPlaceholder->{'System.HTTPType'} || '',
        'System.FQDN'            => $SystemPlaceholder->{'System.FQDN'} || '',
        'System.WebPath'         => $SystemPlaceholder->{'System.WebPath'} || '',
        'System.BaseURL'         => $SystemPlaceholder->{'System.BaseURL'} || '',
        'System.DefaultLanguage' => $SystemPlaceholder->{'System.DefaultLanguage'} || '',
        'System.TicketHook'      => $SystemPlaceholder->{'System.TicketHook'} || '',
        'Customer.Name'          => $Ticket->{customer_name} || '',
        'Customer.Number'        => $Ticket->{customer_number} || '',
        'CustomerUser.FullName'  => $Ticket->{customer_user_name} || '',
        'CustomerUser.Firstname' => $Ticket->{customer_user_firstname} || '',
        'CustomerUser.Lastname'  => $Ticket->{customer_user_lastname} || '',
        'CustomerUser.Login'     => $Ticket->{customer_user_login} || '',
        'CustomerUser.Email'     => $Ticket->{customer_user_email} || '',
        'ChangedBy.FullName'     => $ChangedBy->{full_name} || '',
        'ChangedBy.Firstname'    => $ChangedBy->{firstname} || '',
        'ChangedBy.Lastname'     => $ChangedBy->{lastname} || '',
        'ChangedBy.Login'        => $ChangedBy->{login} || '',
        'ChangedBy.Email'        => $ChangedBy->{email} || '',
        'AssignedAgent.FullName' => $Assigned->{full_name} || '',
        'AssignedAgent.Firstname' => $Assigned->{firstname} || '',
        'AssignedAgent.Lastname'  => $Assigned->{lastname} || '',
        'AssignedAgent.Login'     => $Assigned->{login} || '',
        'AssignedAgent.Email'    => $Assigned->{email} || '',
        'PendingUntil'           => $Self->_DateTimeDisplay( $Ticket->{pending_until} || '' ),
        'PendingReachedSince'    => $Ticket->{pending_reached_since} || '',
        'Escalation.Type'        => $Ticket->{escalation_state} || '',
        'Escalation.DueTime'     => $Self->_DateTimeDisplay( $Ticket->{escalation_due_time} || '' ),
    };
}

sub _PlaceholderReplaceHTML {
    my ( $Self, %Param ) = @_;

    my $HTML        = $Param{HTML} || '';
    my $Placeholder = $Param{Placeholder} || {};
    my %PreserveEmpty = map { $_ => 1 } @{ ref $Param{PreserveEmptyKeys} eq 'ARRAY' ? $Param{PreserveEmptyKeys} : [] };

    $HTML =~ s{\{\{\s*([A-Za-z0-9_.]+)\s*\}\}}{
        my $Key = $1;
        if ( $PreserveEmpty{$Key} && ( !exists $Placeholder->{$Key} || !defined $Placeholder->{$Key} || $Placeholder->{$Key} eq '' ) ) {
            '{{' . $Key . '}}';
        }
        elsif ( $Key eq 'Ticket.LinkHTML' ) {
            exists $Placeholder->{$Key} ? $Placeholder->{$Key} : '';
        }
        else {
            $Self->_Escape( exists $Placeholder->{$Key} ? $Placeholder->{$Key} : '' );
        }
    }gex;

    return QisutuHTML->Sanitize($HTML);
}

sub _PlaceholderReplacePlain {
    my ( $Self, %Param ) = @_;

    my $Text        = $Param{Text} || '';
    my $Placeholder = $Param{Placeholder} || {};

    $Text =~ s{\{\{\s*([A-Za-z0-9_.]+)\s*\}\}}{
        my $Value = exists $Placeholder->{$1} ? $Placeholder->{$1} : '';
        $Value =~ s{<[^>]+>}{}g;
        $Value;
    }gex;

    $Text =~ s{\s+}{ }g;
    $Text =~ s{\A\s+|\s+\z}{}g;

    return $Text;
}

sub _MailHTMLBuild {
    my ( $Self, %Param ) = @_;

    my $BodyHTML = $Param{BodyHTML} || '';
    my $LogoSRC  = '';

    if ( $Param{InlineLogo} ) {
        $LogoSRC = 'cid:qisutu-logo';
    }
    else {
        $LogoSRC = $Self->_LogoURL();
    }

    my $LogoHTML = '';
    if ($LogoSRC) {
        $LogoHTML = '<td style="width:34px;padding:0 10px 0 0;vertical-align:middle;">'
            . '<img src="' . $Self->_Escape($LogoSRC) . '" alt="Qisutu" style="height:28px;max-height:28px;width:auto;display:block;border:0;outline:none;text-decoration:none;">'
            . '</td>';
    }

    return '<!doctype html><html><head><meta charset="utf-8"></head><body style="margin:0;padding:0;background:#f4f7f9;font-family:Arial,Helvetica,sans-serif;color:#1f2933;">'
        . '<table role="presentation" width="100%" cellpadding="0" cellspacing="0" style="background:#f4f7f9;margin:0;padding:0;"><tr><td align="center" style="padding:0 12px 24px 12px;">'
        . '<table role="presentation" width="100%" cellpadding="0" cellspacing="0" style="max-width:760px;background:#ffffff;border:1px solid #d8e0e7;border-radius:8px;overflow:hidden;">'
        . '<tr><td style="background:#015068;padding:12px 18px;">'
        . '<table role="presentation" cellpadding="0" cellspacing="0" style="border-collapse:collapse;"><tr>'
        . $LogoHTML
        . '<td style="vertical-align:middle;color:#ffffff;font-size:20px;font-weight:bold;line-height:28px;">Qisutu</td>'
        . '</tr></table>'
        . '</td></tr>'
        . '<tr><td style="padding:24px 28px;font-size:15px;line-height:1.55;">'
        . $BodyHTML
        . '</td></tr></table></td></tr></table></body></html>';
}

sub _MailInlineImages {
    my ($Self) = @_;

    my $LogoPath = $Self->_LogoFilePath();
    return [] if !$LogoPath;

    return [
        {
            ContentID => 'qisutu-logo',
            Path      => $LogoPath,
            Filename  => 'logo.png',
            MimeType  => 'image/png',
        },
    ];
}

sub _LogoFilePath {
    my ($Self) = @_;

    my @Path;

    if ( $Self->{Config}->{Paths}->{Static} ) {
        push @Path, $Self->{Config}->{Paths}->{Static} . '/img/logo.png';
    }

    if ( $Self->{Config}->{RootPath} ) {
        push @Path, $Self->{Config}->{RootPath} . '/var/static/img/logo.png';
    }

    push @Path, '/opt/qisutu/var/static/img/logo.png';

    my %Seen;
    for my $Path (@Path) {
        next if !$Path || $Seen{$Path}++;
        return $Path if -f $Path && -r $Path;
    }

    return '';
}

sub _LogoURL {
    my ($Self) = @_;

    my $StaticURL = $Self->{Config}->{Paths}->{StaticURL} || '/static';

    if ( $StaticURL =~ m{
        \Ahttps?://
    }x ) {
        $StaticURL =~ s{/+\z}{};
        return $StaticURL . '/img/logo.png';
    }

    my $BaseURL = $Self->_SystemBaseURL();
    return '' if !$BaseURL;

    $BaseURL   =~ s{/+\z}{};
    $StaticURL =~ s{\A/+}{};
    $StaticURL =~ s{/+\z}{};

    return $BaseURL . '/' . $StaticURL . '/img/logo.png';
}

sub _SenderAddress {
    my ( $Self, %Param ) = @_;

    my $Ticket      = $Param{Ticket} || {};
    my $SMTPAccount = $Param{SMTPAccount} || {};

    return (
        $Ticket->{system_email_name} || $Self->{Config}->{System}->{Name} || 'Qisutu',
        $SMTPAccount->{smtp_username} || $Ticket->{system_email} || '',
    );
}

sub _ActiveSMTPAccount {
    my ($Self) = @_;

    return $Self->{DB}->SelectRow(
        'SELECT *
         FROM smtp_account
         WHERE active = 1
         ORDER BY sort_order ASC, id ASC
         LIMIT 1'
    );
}

sub _EventKey {
    my ( $Self, %Param ) = @_;

    return $Param{EventKey} if $Param{EventKey};

    my $Type   = $Param{NotificationType} || '';
    my $Ticket = $Param{Ticket} || {};

    if ( $Type eq 'ticket_pending_reached' ) {
        return join ':', $Type, $Ticket->{id} || 0, $Ticket->{pending_until} || '';
    }

    if ( $Type eq 'ticket_escalation_reached' ) {
        return join ':',
            $Type,
            $Ticket->{id} || 0,
            $Ticket->{first_response_due_at} || '',
            $Ticket->{update_due_at} || '',
            $Ticket->{solution_due_at} || '';
    }

    return join ':', $Type, $Ticket->{id} || 0, time();
}

sub _RequiresEventLog {
    my ( $Self, %Param ) = @_;

    my $Type = $Param{NotificationType} || '';

    return 1 if $Type eq 'ticket_escalation_reached';
    return 1 if $Type eq 'ticket_pending_reached';

    return 0;
}

sub _EventAlreadySent {
    my ( $Self, %Param ) = @_;

    my $Row = $Self->{DB}->SelectRow(
        'SELECT id
         FROM agent_notification_event_log
         WHERE notification_type = ?
            AND ticket_id = ?
            AND recipient_user_id = ?
            AND event_key = ?
         LIMIT 1',
        $Param{NotificationType} || '',
        $Param{TicketID} || 0,
        $Param{RecipientUserID} || 0,
        $Param{EventKey} || '',
    );

    return $Row ? 1 : 0;
}

sub _EventLogCreate {
    my ( $Self, %Param ) = @_;

    return $Self->{DB}->Do(
        'INSERT IGNORE INTO agent_notification_event_log (
            notification_type,
            ticket_id,
            recipient_user_id,
            event_key,
            sent_at
         ) VALUES (
            ?, ?, ?, ?, NOW()
         )',
        $Param{NotificationType} || '',
        $Param{TicketID} || 0,
        $Param{RecipientUserID} || 0,
        $Param{EventKey} || '',
    );
}

sub _UserDataGet {
    my ( $Self, %Param ) = @_;

    my $UserID = $Param{UserID} || 0;
    return {} if $UserID !~ m{\A\d+\z} || !$UserID;

    my $User = $Self->{DB}->SelectRow(
        'SELECT id, login, email, firstname, lastname
         FROM user_account
         WHERE id = ?
         LIMIT 1',
        $UserID,
    );

    return {} if !$User;

    $User->{full_name} = $Self->_UserName(
        Firstname => $User->{firstname},
        Lastname  => $User->{lastname},
        Login     => $User->{login},
    );

    return $User;
}

sub _TicketLink {
    my ( $Self, %Param ) = @_;

    my $TicketID = $Param{TicketID} || 0;
    my $BaseURL  = $Self->_SystemBaseURL();
    my $Page     = ( $Param{Page} || '' ) eq 'CustomerTicketZoom'
        ? 'CustomerTicketZoom'
        : 'AgentTicketZoom';

    $BaseURL =~ s{/+\z}{};

    my $Path = 'index.pl?Page=' . $Page . '&TicketID=' . $TicketID;

    return $BaseURL ? $BaseURL . '/' . $Path : $Path;
}

sub _SystemBaseURL {
    my ($Self) = @_;

    my $SettingObject = $Self->_SystemSettingObject();

    if ($SettingObject) {
        my $BaseURL = $SettingObject->BaseURL();
        return $BaseURL if $BaseURL;
    }

    my $BaseURL = $Self->{Config}->{System}->{BaseURL} || $ENV{QISUTU_BASE_URL} || '';
    $BaseURL =~ s{/+\z}{};

    return $BaseURL;
}

sub _SystemPlaceholderHash {
    my ($Self) = @_;

    my $SettingObject = $Self->_SystemSettingObject();

    if ($SettingObject) {
        return $SettingObject->PlaceholderHash() || {};
    }

    my $BaseURL = $Self->{Config}->{System}->{BaseURL} || $ENV{QISUTU_BASE_URL} || '';

    return {
        'System.Name'            => $Self->{Config}->{System}->{Name} || 'Qisutu',
        'System.HTTPType'        => '',
        'System.FQDN'            => '',
        'System.WebPath'         => '',
        'System.BaseURL'         => $BaseURL,
        'System.DefaultLanguage' => $Self->{Config}->{Language}->{Default} || 'en',
        'System.TicketHook'      => $Self->{Config}->{System}->{TicketHook} || 'Qisutu',
    };
}

sub _SystemSettingObject {
    my ($Self) = @_;

    return if !$Self->{DB};

    my $Loaded = eval {
        require QisutuSystemSetting;
        1;
    };

    return if !$Loaded;

    return QisutuSystemSetting->new(
        Config => $Self->{Config},
        DB     => $Self->{DB},
    );
}

sub _NotificationTypeClean {
    my ( $Self, $Type ) = @_;

    $Type = $Self->_Trim($Type);
    return '' if !$Type;

    my %Allowed = map { $_->{type} => 1 } @{ NotificationTypes() };

    if ( !$Allowed{$Type} ) {
        $Self->{LastError} = 'Invalid agent notification type';
        return '';
    }

    return $Type;
}

sub _DateTimeDisplay {
    my ( $Self, $DateTime ) = @_;

    $DateTime ||= '';

    if ( $DateTime =~ m{\A(\d{4})-(\d{2})-(\d{2})[ T](\d{2}):(\d{2})(?::(\d{2}))?\z} ) {
        return "$3.$2.$1 $4:$5";
    }

    return $DateTime;
}

sub _DurationText {
    my ( $Self, %Param ) = @_;

    my $Seconds = $Param{Seconds} || 0;
    $Seconds = 0 if $Seconds < 0;

    my $Minutes = int( $Seconds / 60 );
    my $Hours   = int( $Minutes / 60 );
    my $Days    = int( $Hours / 24 );

    if ( $Days > 0 ) {
        return $Days == 1 ? '1 Tag' : $Days . ' Tage';
    }

    if ( $Hours > 0 ) {
        return $Hours == 1 ? '1 Stunde' : $Hours . ' Stunden';
    }

    return $Minutes == 1 ? '1 Minute' : $Minutes . ' Minuten';
}

sub _UserName {
    my ( $Self, %Param ) = @_;

    my $Name = join ' ', grep {$_} ( $Param{Firstname} || '', $Param{Lastname} || '' );
    $Name ||= $Param{Login} || '';

    return $Name;
}

sub _Trim {
    my ( $Self, $Value ) = @_;

    $Value = '' if !defined $Value;
    $Value =~ s{\A\s+}{};
    $Value =~ s{\s+\z}{};

    return $Value;
}

sub _Escape {
    my ( $Self, $Value ) = @_;

    $Value = '' if !defined $Value;
    $Value =~ s/&/&amp;/g;
    $Value =~ s/</&lt;/g;
    $Value =~ s/>/&gt;/g;
    $Value =~ s/"/&quot;/g;
    $Value =~ s/'/&#39;/g;

    return $Value;
}

sub Error {
    my ($Self) = @_;

    return $Self->{LastError};
}

1;
