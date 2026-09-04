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

package QisutuInternalChat;

use strict;
use warnings;
use utf8;

use QisutuPermission;
use QisutuTicket;

sub new {
    my ( $Class, %Param ) = @_;

    my $Self = {
        Config    => $Param{Config} || {},
        DB        => $Param{DB},
        LastError => '',
    };

    bless $Self, $Class;

    return $Self;
}

sub AgentList {
    my ( $Self, %Param ) = @_;

    my $UserID = $Self->_ID( $Param{UserID} );
    return [] if !$UserID;

    my $Rows = $Self->{DB}->SelectAll(
        'SELECT
            u.id,
            u.login,
            u.email,
            u.firstname,
            u.lastname
         FROM user_account u
         WHERE u.account_type = ?
            AND u.is_active = 1
            AND u.is_system_user = 0
            AND u.id <> ?',
        'agent',
        $UserID,
    );

    if ( !defined $Rows ) {
        $Self->{LastError} = $Self->{DB}->Error() || 'Translate:InternalChatLoadFailed';
        return [];
    }

    my $OnlineRows = $Self->{DB}->SelectAll(
        'SELECT
            user_account_id AS id,
            MAX(last_seen_at) AS last_seen_at
         FROM user_session
         WHERE is_active = 1
            AND expires_at > NOW()
            AND last_seen_at >= DATE_SUB(NOW(), INTERVAL 10 MINUTE)
         GROUP BY user_account_id',
    );

    if ( !defined $OnlineRows ) {
        $Self->{LastError} = $Self->{DB}->Error() || 'Translate:InternalChatLoadFailed';
        return [];
    }

    my $UnreadRows = $Self->{DB}->SelectAll(
        'SELECT
            sender_user_id AS id,
            COUNT(*) AS unread_count
         FROM internal_chat_message
         WHERE recipient_user_id = ?
            AND read_at IS NULL
         GROUP BY sender_user_id',
        $UserID,
    );

    if ( !defined $UnreadRows ) {
        $Self->{LastError} = $Self->{DB}->Error() || 'Translate:InternalChatLoadFailed';
        return [];
    }

    my %Online = map { ( 0 + ( $_->{id} || 0 ) ) => $_->{last_seen_at} } @{$OnlineRows};
    my %Unread = map { ( 0 + ( $_->{id} || 0 ) ) => 0 + ( $_->{unread_count} || 0 ) } @{$UnreadRows};

    for my $Agent ( @{$Rows} ) {
        $Agent->{id}           = 0 + ( $Agent->{id} || 0 );
        $Agent->{name}         = $Self->_UserName($Agent);
        $Agent->{initials}     = $Self->_Initials( $Agent->{name} );
        $Agent->{is_online}    = $Online{ $Agent->{id} } ? 1 : 0;
        $Agent->{last_seen_at} = $Online{ $Agent->{id} } || '';
        $Agent->{unread_count} = $Unread{ $Agent->{id} } || 0;
        delete $Agent->{firstname};
        delete $Agent->{lastname};
        delete $Agent->{email};
    }

    @{$Rows} = sort {
        $b->{is_online} <=> $a->{is_online}
            || $b->{unread_count} <=> $a->{unread_count}
            || lc( $a->{name} || $a->{login} || '' ) cmp lc( $b->{name} || $b->{login} || '' )
    } @{$Rows};

    return $Rows;
}

sub UnreadCount {
    my ( $Self, %Param ) = @_;

    my $UserID = $Self->_ID( $Param{UserID} );
    return 0 if !$UserID;

    my $Row = $Self->{DB}->SelectRow(
        'SELECT COUNT(*) AS unread_count
         FROM internal_chat_message
         WHERE recipient_user_id = ?
            AND read_at IS NULL',
        $UserID,
    );

    if ( !$Row ) {
        $Self->{LastError} = $Self->{DB}->Error() || 'Translate:InternalChatLoadFailed';
        return 0;
    }

    return 0 + ( $Row->{unread_count} || 0 );
}

sub MessageList {
    my ( $Self, %Param ) = @_;

    my $UserID    = $Self->_ID( $Param{UserID} );
    my $PartnerID = $Self->_ID( $Param{PartnerID} );
    my $SinceID   = $Self->_ID( $Param{SinceID} );

    if ( !$UserID || !$PartnerID || $UserID == $PartnerID || !$Self->_AgentGet( UserID => $PartnerID ) ) {
        $Self->{LastError} = 'Translate:InternalChatRecipientInvalid';
        return;
    }

    my $Read = $Self->{DB}->Do(
        'UPDATE internal_chat_message
         SET read_at = NOW()
         WHERE sender_user_id = ?
            AND recipient_user_id = ?
            AND read_at IS NULL',
        $PartnerID,
        $UserID,
    );

    if ( !$Read ) {
        $Self->{LastError} = $Self->{DB}->Error() || 'Translate:InternalChatLoadFailed';
        return;
    }

    my $Order = $SinceID ? 'ASC' : 'DESC';
    my $Since = $SinceID ? 'AND message.id > ?' : '';
    my @Bind  = ( $UserID, $PartnerID, $PartnerID, $UserID );
    push @Bind, $SinceID if $SinceID;

    my $Rows = $Self->{DB}->SelectAll(
        'SELECT
            message.id,
            message.sender_user_id,
            message.recipient_user_id,
            message.message_type,
            message.message_text,
            message.ticket_id,
            message.ticket_number,
            message.ticket_title,
            message.created_at,
            message.read_at,
            sender.login AS sender_login,
            sender.firstname AS sender_firstname,
            sender.lastname AS sender_lastname
         FROM internal_chat_message message
         INNER JOIN user_account sender
            ON sender.id = message.sender_user_id
         WHERE (
            (
                message.sender_user_id = ?
                AND message.recipient_user_id = ?
            ) OR (
                message.sender_user_id = ?
                AND message.recipient_user_id = ?
            )
         )
            ' . $Since . '
         ORDER BY message.id ' . $Order . '
         LIMIT 100',
        @Bind,
    );

    if ( !$Rows ) {
        $Self->{LastError} = $Self->{DB}->Error() || 'Translate:InternalChatLoadFailed';
        return;
    }

    @{$Rows} = reverse @{$Rows} if !$SinceID;

    for my $Message ( @{$Rows} ) {
        $Message->{id}                = 0 + ( $Message->{id} || 0 );
        $Message->{sender_user_id}    = 0 + ( $Message->{sender_user_id} || 0 );
        $Message->{recipient_user_id} = 0 + ( $Message->{recipient_user_id} || 0 );
        $Message->{ticket_id}         = 0 + ( $Message->{ticket_id} || 0 );
        $Message->{outgoing}          = $Message->{sender_user_id} == $UserID ? 1 : 0;
        $Message->{sender_name}       = $Self->_UserName({
            login     => $Message->{sender_login},
            firstname => $Message->{sender_firstname},
            lastname  => $Message->{sender_lastname},
        });
        delete $Message->{sender_login};
        delete $Message->{sender_firstname};
        delete $Message->{sender_lastname};
    }

    return $Rows;
}

sub MessageCreate {
    my ( $Self, %Param ) = @_;

    my $User      = $Param{User} || {};
    my $UserID    = $Self->_ID( $User->{user_account_id} );
    my $PartnerID = $Self->_ID( $Param{PartnerID} );
    my $TicketID  = $Self->_ID( $Param{TicketID} );
    my $Text      = $Self->_Trim( $Param{Text} );

    if ( !$UserID || !$PartnerID || $UserID == $PartnerID || !$Self->_AgentGet( UserID => $PartnerID ) ) {
        $Self->{LastError} = 'Translate:InternalChatRecipientInvalid';
        return;
    }
    if ( $Text eq '' ) {
        $Self->{LastError} = 'Translate:InternalChatMessageRequired';
        return;
    }
    if ( length($Text) > 4000 ) {
        $Self->{LastError} = 'Translate:InternalChatMessageTooLong';
        return;
    }

    my $Ticket = $TicketID ? $Self->_TicketGet( TicketID => $TicketID, User => $User ) : undef;
    if ( $TicketID && !$Ticket ) {
        $Self->{LastError} ||= 'Translate:InternalChatTicketAccessDenied';
        return;
    }

    return $Self->_MessageInsert(
        SenderUserID    => $UserID,
        RecipientUserID => $PartnerID,
        MessageType     => 'message',
        MessageText     => $Text,
        Ticket          => $Ticket,
    );
}

sub ConversationDelete {
    my ( $Self, %Param ) = @_;

    my $UserID    = $Self->_ID( $Param{UserID} );
    my $PartnerID = $Self->_ID( $Param{PartnerID} );

    if ( !$UserID || !$PartnerID || $UserID == $PartnerID || !$Self->_AgentGet( UserID => $PartnerID ) ) {
        $Self->{LastError} = 'Translate:InternalChatRecipientInvalid';
        return;
    }

    if ( !$Self->{DB}->BeginWork() ) {
        $Self->{LastError} = $Self->{DB}->Error() || 'Translate:InternalChatDeleteFailed';
        return;
    }

    my $Deleted = $Self->{DB}->Do(
        'DELETE FROM internal_chat_message
         WHERE (
            sender_user_id = ?
            AND recipient_user_id = ?
         ) OR (
            sender_user_id = ?
            AND recipient_user_id = ?
         )',
        $UserID,
        $PartnerID,
        $PartnerID,
        $UserID,
    );

    if ( !$Deleted ) {
        $Self->{DB}->Rollback();
        $Self->{LastError} = $Self->{DB}->Error() || 'Translate:InternalChatDeleteFailed';
        return;
    }

    my $MarkerStored = $Self->{DB}->Do(
        'INSERT INTO internal_chat_message (
            sender_user_id, recipient_user_id, message_type, message_text,
            ticket_id, ticket_number, ticket_title, created_at, read_at
         ) VALUES (?, ?, ?, ?, NULL, ?, ?, NOW(), NOW())',
        $UserID,
        $PartnerID,
        'conversation_deleted',
        '',
        '',
        '',
    );

    my $MessageID = $MarkerStored ? $Self->{DB}->LastInsertID('internal_chat_message') : 0;
    if ( !$MarkerStored || !$MessageID || !$Self->{DB}->Commit() ) {
        $Self->{DB}->Rollback();
        $Self->{LastError} = $Self->{DB}->Error() || 'Translate:InternalChatDeleteFailed';
        return;
    }

    return $MessageID;
}

sub TicketTransfer {
    my ( $Self, %Param ) = @_;

    my $User      = $Param{User} || {};
    my $UserID    = $Self->_ID( $User->{user_account_id} );
    my $PartnerID = $Self->_ID( $Param{PartnerID} );
    my $TicketID  = $Self->_ID( $Param{TicketID} );
    my $Recipient = $Self->_AgentGet( UserID => $PartnerID );

    if ( !$UserID || !$PartnerID || $UserID == $PartnerID || !$Recipient ) {
        $Self->{LastError} = 'Translate:InternalChatRecipientInvalid';
        return;
    }
    if ( !$TicketID ) {
        $Self->{LastError} = 'Translate:InternalChatTicketRequired';
        return;
    }

    my $Ticket = $Self->_TicketGet( TicketID => $TicketID, User => $User );
    if ( !$Ticket ) {
        $Self->{LastError} ||= 'Translate:InternalChatTicketAccessDenied';
        return;
    }

    my $Permission = QisutuPermission->new( Config => $Self->{Config}, DB => $Self->{DB} );
    if ( !$Permission->QueueAccessCheck(
        UserID     => $PartnerID,
        QueueID    => $Ticket->{queue_id},
        Permission => 'ticket.edit',
    ) ) {
        $Self->{LastError} = 'Translate:InternalChatTicketRecipientAccessDenied';
        return;
    }

    if ( !$Self->{DB}->BeginWork() ) {
        $Self->{LastError} = $Self->{DB}->Error() || 'Translate:InternalChatTransferFailed';
        return;
    }

    my $TicketObject = $Self->_TicketObject();
    my $Updated = $TicketObject->TicketOwnerUpdate(
        TicketID        => $TicketID,
        OwnerUserID     => $PartnerID,
        User            => $User,
        ChangedByUserID => $UserID,
    );

    if ( !$Updated ) {
        $Self->{DB}->Rollback();
        $Self->{LastError} = $TicketObject->Error() || 'Translate:InternalChatTransferFailed';
        return;
    }

    my $SenderName    = $Self->_UserName($User);
    my $RecipientName = $Self->_UserName($Recipient);
    my $NoteSubject   = $Self->_Trim( $Param{NoteSubject} ) || 'Ticket handover in internal chat';
    my $NoteBody      = $Self->_Trim( $Param{NoteBody} )
        || '{sender} handed the ticket over to {recipient} in the internal chat.';

    $NoteBody =~ s{\{sender\}}{$SenderName}g;
    $NoteBody =~ s{\{recipient\}}{$RecipientName}g;

    my $ArticleID = $TicketObject->ArticleCreate(
        TicketID        => $TicketID,
        User            => $User,
        Subject         => $NoteSubject,
        Body            => $NoteBody,
        Channel         => 'note',
        SenderType      => 'agent',
        FromName        => $SenderName,
        FromEmail       => $User->{email} || '',
        ContentType     => 'text/plain',
        Visibility      => 'agent',
        Internal        => 1,
        Language        => $Param{Language} || 'en',
        CreatedByUserID => $UserID,
        ChangedByUserID => $UserID,
        SkipNotification => 1,
    );

    if ( !$ArticleID ) {
        $Self->{DB}->Rollback();
        $Self->{LastError} = $TicketObject->Error() || 'Translate:InternalChatTransferFailed';
        return;
    }

    my $MessageID = $Self->_MessageInsert(
        SenderUserID    => $UserID,
        RecipientUserID => $PartnerID,
        MessageType     => 'ticket_handover',
        MessageText     => '',
        Ticket          => $Ticket,
    );

    if ( !$MessageID || !$Self->{DB}->Commit() ) {
        $Self->{DB}->Rollback();
        $Self->{LastError} ||= $Self->{DB}->Error() || 'Translate:InternalChatTransferFailed';
        return;
    }

    return {
        MessageID   => $MessageID,
        TicketID    => 0 + $TicketID,
        TicketNumber => $Ticket->{ticket_number} || '',
        TicketTitle  => $Ticket->{title} || '',
    };
}

sub TicketPresenceUpdate {
    my ( $Self, %Param ) = @_;

    my $User     = $Param{User} || {};
    my $UserID   = $Self->_ID( $User->{user_account_id} );
    my $TicketID = $Self->_ID( $Param{TicketID} );
    my $ClientID = $Param{ClientID} || '';

    if ( !$UserID || !$TicketID || $ClientID !~ m{\A[A-Za-z0-9_-]{16,64}\z} ) {
        $Self->{LastError} = 'Translate:InternalChatPresenceFailed';
        return;
    }

    my $Ticket = $Self->_TicketGet( TicketID => $TicketID, User => $User );
    if ( !$Ticket ) {
        $Self->{LastError} ||= 'Translate:InternalChatTicketAccessDenied';
        return;
    }

    my $Stored = $Self->{DB}->Do(
        'INSERT INTO ticket_presence (
            ticket_id, user_account_id, client_id, created_at, last_seen_at
         ) VALUES (?, ?, ?, NOW(), NOW())
         ON DUPLICATE KEY UPDATE last_seen_at = NOW()',
        $TicketID,
        $UserID,
        $ClientID,
    );

    if ( !$Stored ) {
        $Self->{LastError} = $Self->{DB}->Error() || 'Translate:InternalChatPresenceFailed';
        return;
    }

    $Self->{DB}->Do(
        'DELETE FROM ticket_presence
         WHERE last_seen_at < DATE_SUB(NOW(), INTERVAL 1 DAY)',
    );

    my $Rows = $Self->{DB}->SelectAll(
        'SELECT
            presence.user_account_id AS id,
            agent.login,
            agent.firstname,
            agent.lastname,
            MAX(presence.last_seen_at) AS last_seen_at
         FROM ticket_presence presence
         INNER JOIN user_account agent
            ON agent.id = presence.user_account_id
         WHERE presence.ticket_id = ?
            AND presence.user_account_id <> ?
            AND presence.last_seen_at >= DATE_SUB(NOW(), INTERVAL 90 SECOND)
            AND agent.account_type = ?
            AND agent.is_active = 1
            AND agent.is_system_user = 0
         GROUP BY presence.user_account_id, agent.login, agent.firstname, agent.lastname
         ORDER BY agent.firstname ASC, agent.lastname ASC, agent.login ASC',
        $TicketID,
        $UserID,
        'agent',
    );

    if ( !$Rows ) {
        $Self->{LastError} = $Self->{DB}->Error() || 'Translate:InternalChatPresenceFailed';
        return;
    }

    for my $Agent ( @{$Rows} ) {
        $Agent->{id}       = 0 + ( $Agent->{id} || 0 );
        $Agent->{name}     = $Self->_UserName($Agent);
        $Agent->{initials} = $Self->_Initials( $Agent->{name} );
        delete $Agent->{firstname};
        delete $Agent->{lastname};
        delete $Agent->{login};
    }

    return $Rows;
}

sub TicketPresenceLeave {
    my ( $Self, %Param ) = @_;

    my $UserID   = $Self->_ID( ( $Param{User} || {} )->{user_account_id} );
    my $TicketID = $Self->_ID( $Param{TicketID} );
    my $ClientID = $Param{ClientID} || '';

    return 1 if !$UserID || !$TicketID || $ClientID !~ m{\A[A-Za-z0-9_-]{16,64}\z};

    my $Deleted = $Self->{DB}->Do(
        'DELETE FROM ticket_presence
         WHERE ticket_id = ?
            AND user_account_id = ?
            AND client_id = ?',
        $TicketID,
        $UserID,
        $ClientID,
    );

    return $Deleted ? 1 : undef;
}

sub _MessageInsert {
    my ( $Self, %Param ) = @_;

    my $Ticket = $Param{Ticket} || {};
    my $Stored = $Self->{DB}->Do(
        'INSERT INTO internal_chat_message (
            sender_user_id, recipient_user_id, message_type, message_text,
            ticket_id, ticket_number, ticket_title, created_at
         ) VALUES (?, ?, ?, ?, ?, ?, ?, NOW())',
        $Param{SenderUserID},
        $Param{RecipientUserID},
        $Param{MessageType} || 'message',
        defined $Param{MessageText} ? $Param{MessageText} : '',
        $Ticket->{id} || undef,
        $Ticket->{ticket_number} || '',
        $Ticket->{title} || '',
    );

    if ( !$Stored ) {
        $Self->{LastError} = $Self->{DB}->Error() || 'Translate:InternalChatSendFailed';
        return;
    }

    my $MessageID = $Self->{DB}->LastInsertID('internal_chat_message');
    if ( !$MessageID ) {
        $Self->{LastError} = $Self->{DB}->Error() || 'Translate:InternalChatSendFailed';
        return;
    }

    return $MessageID;
}

sub _TicketGet {
    my ( $Self, %Param ) = @_;

    my $TicketObject = $Self->_TicketObject();
    my $Ticket = $TicketObject->TicketGet(
        TicketID => $Param{TicketID},
        User     => $Param{User} || {},
        Language => 'en',
    );

    if ( !$Ticket ) {
        $Self->{LastError} = 'Translate:InternalChatTicketAccessDenied';
        return;
    }

    return $Ticket;
}

sub _TicketObject {
    my ($Self) = @_;

    my $Permission = QisutuPermission->new(
        Config => $Self->{Config},
        DB     => $Self->{DB},
    );

    return QisutuTicket->new(
        Config     => $Self->{Config},
        DB         => $Self->{DB},
        Permission => $Permission,
    );
}

sub _AgentGet {
    my ( $Self, %Param ) = @_;

    my $UserID = $Self->_ID( $Param{UserID} );
    return if !$UserID;

    return $Self->{DB}->SelectRow(
        'SELECT id, login, firstname, lastname
         FROM user_account
         WHERE id = ?
            AND account_type = ?
            AND is_active = 1
            AND is_system_user = 0
         LIMIT 1',
        $UserID,
        'agent',
    );
}

sub _UserName {
    my ( $Self, $User ) = @_;

    $User ||= {};
    my $Name = join ' ', grep { defined $_ && $_ ne '' } $User->{firstname}, $User->{lastname};
    $Name =~ s{\s+}{ }g;
    $Name =~ s{\A\s+|\s+\z}{}g;

    return $Name || $User->{login} || $User->{email} || '-';
}

sub _Initials {
    my ( $Self, $Name ) = @_;

    my @Part = grep {$_} split /\s+/, $Name || '';
    my $Initials = @Part > 1
        ? substr( $Part[0], 0, 1 ) . substr( $Part[-1], 0, 1 )
        : substr( $Part[0] || '?', 0, 2 );

    return uc($Initials || '?');
}

sub _Trim {
    my ( $Self, $Value ) = @_;

    $Value = '' if !defined $Value;
    $Value =~ s{\x00}{}g;
    $Value =~ s{\r\n?}{\n}g;
    $Value =~ s{\A\s+|\s+\z}{}g;

    return $Value;
}

sub _ID {
    my ( $Self, $Value ) = @_;

    return 0 if !defined $Value || $Value !~ m{\A\d+\z};
    return 0 + $Value;
}

sub Error {
    my ($Self) = @_;

    return $Self->{LastError};
}

1;
