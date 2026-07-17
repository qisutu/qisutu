# Qisutu - Open Source Ticket System
# Copyright (C) 2026 Franziska Steps
# Qisutu - Kim-KI, https://qisutu.de
#
# SPDX-FileCopyrightText: 2026 Franziska Steps
# SPDX-License-Identifier: AGPL-3.0-or-later

package QisutuBulkAction;

use strict;
use warnings;
use utf8;

use JSON::PP;

use QisutuPermission;
use QisutuTicket;

sub new {
    my ( $Class, %Param ) = @_;

    my $Permission = QisutuPermission->new(
        Config => $Param{Config},
        DB     => $Param{DB},
    );

    my $Self = {
        Config     => $Param{Config},
        DB         => $Param{DB},
        Permission => $Permission,
        Ticket     => QisutuTicket->new(
            Config     => $Param{Config},
            DB         => $Param{DB},
            Permission => $Permission,
        ),
        JSON      => JSON::PP->new->utf8(0)->canonical(1)->allow_nonref(1),
        LastError => '',
    };

    bless $Self, $Class;
    return $Self;
}

sub Options {
    my ( $Self, %Param ) = @_;

    $Self->{LastError} = '';

    my $UserID = ( $Param{User} || {} )->{user_account_id} || 0;
    return $Self->_EmptyOptions() if !$UserID;

    my $QueueIDs = $Self->{Permission}->QueueIDList(
        UserID     => $UserID,
        Permission => 'ticket.edit',
    );

    my $Queues = [];
    if ( @{$QueueIDs || []} ) {
        my $Placeholders = join ', ', map {'?'} @{$QueueIDs};
        $Queues = $Self->{DB}->SelectAll(
            'SELECT id, COALESCE(NULLIF(full_name, ""), name) AS label
             FROM ticket_queue
             WHERE active = 1
               AND id IN (' . $Placeholders . ')
             ORDER BY sort_order ASC, label ASC, id ASC',
            @{$QueueIDs},
        ) || [];
    }

    my $States = $Self->{DB}->SelectAll(
        'SELECT id, name AS label, state_type
         FROM ticket_state
         WHERE active = 1
         ORDER BY sort_order ASC, name ASC, id ASC'
    ) || [];

    my $Priorities = $Self->{DB}->SelectAll(
        'SELECT id, name AS label
         FROM ticket_priority
         WHERE active = 1
         ORDER BY sort_order ASC, priority_value ASC, name ASC, id ASC'
    ) || [];

    my $Agents = $Self->{DB}->SelectAll(
        'SELECT id,
            COALESCE(NULLIF(TRIM(CONCAT(firstname, " ", lastname)), ""), login, email) AS label
         FROM user_account
         WHERE account_type = ?
           AND is_active = 1
           AND is_system_user = 0
         ORDER BY label ASC, id ASC',
        'agent',
    ) || [];

    if ( $Self->{DB}->Error() ) {
        $Self->{LastError} = $Self->{DB}->Error();
    }

    return {
        Queues       => $Queues,
        States       => $States,
        Priorities   => $Priorities,
        Owners       => $Agents,
        Responsibles => $Agents,
    };
}

sub Execute {
    my ( $Self, %Param ) = @_;

    $Self->{LastError} = '';

    my $TicketIDs = ref $Param{TicketIDs} eq 'ARRAY' ? $Param{TicketIDs} : [];
    my $Changes   = ref $Param{Changes} eq 'HASH' ? $Param{Changes} : {};
    my $User      = $Param{User} || {};
    my $UserID    = $User->{user_account_id} || 0;
    my $Language  = $Param{Language} || 'en';
    my $Reason    = $Self->_Trim( $Param{Reason} );

    $Reason = substr( $Reason, 0, 1000 ) if length($Reason) > 1000;

    if ( !$UserID || !@{$TicketIDs} || @{$TicketIDs} > 50 || !$Self->_ChangesHaveAction($Changes) ) {
        $Self->{LastError} = 'Translate:TicketBulkActionInvalid';
        return;
    }

    my $RequestedJSON = $Self->_JSONEncode($Changes);
    my $OperationResult = $Self->{DB}->Do(
        'INSERT INTO ticket_bulk_action (
            created_by_user_id, change_reason, requested_changes_json, selected_count,
            success_count, skipped_count, failed_count, status, created_at, completed_at
         ) VALUES (?, ?, ?, ?, 0, 0, 0, ?, NOW(), NULL)',
        $UserID,
        $Reason,
        $RequestedJSON,
        scalar @{$TicketIDs},
        'running',
    );

    if ( !$OperationResult ) {
        $Self->{LastError} = $Self->{DB}->Error() || 'Translate:TicketBulkActionFailed';
        return;
    }

    my $OperationID = $Self->{DB}->LastInsertID('ticket_bulk_action') || 0;
    if (!$OperationID) {
        $Self->{LastError} = 'Translate:TicketBulkActionFailed';
        return;
    }

    my %Count = ( success => 0, skipped => 0, failed => 0 );

    for my $TicketID ( @{$TicketIDs} ) {
        my $Result = $Self->_TicketApply(
            OperationID => $OperationID,
            TicketID    => $TicketID,
            Changes     => $Changes,
            User        => $User,
            Language    => $Language,
        );

        my $Status = $Result->{Status} || 'failed';
        $Status = 'failed' if !exists $Count{$Status};
        $Count{$Status}++;
    }

    my $Completed = $Self->{DB}->Do(
        'UPDATE ticket_bulk_action
         SET success_count = ?, skipped_count = ?, failed_count = ?, status = ?, completed_at = NOW()
         WHERE id = ?',
        $Count{success},
        $Count{skipped},
        $Count{failed},
        'completed',
        $OperationID,
    );

    if (!$Completed) {
        $Self->{LastError} = $Self->{DB}->Error() || 'Translate:TicketBulkActionFailed';
        return;
    }

    return {
        OperationID => $OperationID,
        Selected    => scalar @{$TicketIDs},
        %Count,
    };
}

sub ResultGet {
    my ( $Self, %Param ) = @_;

    my $OperationID = $Param{OperationID} || 0;
    my $UserID      = $Param{UserID} || 0;
    return if $OperationID !~ m{\A\d+\z} || !$OperationID || !$UserID;

    my $Operation = $Self->{DB}->SelectRow(
        'SELECT *
         FROM ticket_bulk_action
         WHERE id = ? AND created_by_user_id = ?
         LIMIT 1',
        $OperationID,
        $UserID,
    );
    return if !$Operation;

    my $Items = $Self->{DB}->SelectAll(
        'SELECT id, ticket_id, ticket_number_snapshot, result, error_message, changes_json, created_at
         FROM ticket_bulk_action_item
         WHERE bulk_action_id = ?
         ORDER BY id ASC',
        $OperationID,
    ) || [];

    for my $Item ( @{$Items} ) {
        $Item->{changes} = $Self->_JSONDecode( $Item->{changes_json}, [] );
    }

    $Operation->{items} = $Items;
    return $Operation;
}

sub TicketHistoryList {
    my ( $Self, %Param ) = @_;

    my $TicketID = $Param{TicketID} || 0;
    my $Limit    = $Param{Limit} || 100;
    return [] if $TicketID !~ m{\A\d+\z} || !$TicketID;
    $Limit = 100 if $Limit !~ m{\A\d+\z} || $Limit < 1 || $Limit > 500;

    my $Rows = $Self->{DB}->SelectAll(
        'SELECT
            item.id,
            item.bulk_action_id,
            item.changes_json,
            item.created_at,
            action.change_reason,
            account.login,
            account.firstname,
            account.lastname
         FROM ticket_bulk_action_item item
         INNER JOIN ticket_bulk_action action ON action.id = item.bulk_action_id
         INNER JOIN user_account account ON account.id = action.created_by_user_id
         WHERE item.ticket_id = ?
           AND item.result = ?
         ORDER BY item.id DESC
         LIMIT ' . int($Limit),
        $TicketID,
        'success',
    ) || [];

    for my $Row ( @{$Rows} ) {
        $Row->{changes} = $Self->_JSONDecode( $Row->{changes_json}, [] );
        $Row->{agent_name} = $Self->_UserName($Row);
    }

    return $Rows;
}

sub Error {
    my ($Self) = @_;
    return $Self->{LastError} || '';
}

sub _TicketApply {
    my ( $Self, %Param ) = @_;

    my $OperationID = $Param{OperationID};
    my $TicketID    = $Param{TicketID};
    my $Changes     = $Param{Changes};
    my $User        = $Param{User};
    my $UserID      = $User->{user_account_id} || 0;
    my $Language    = $Param{Language};

    my $TicketBefore = $Self->{Ticket}->TicketGet(
        TicketID => $TicketID,
        User     => $User,
        Language => $Language,
    );

    if (!$TicketBefore) {
        return $Self->_FailureRecord(
            OperationID => $OperationID,
            TicketID    => $TicketID,
            Status      => 'skipped',
            Error       => $Self->{Ticket}->Error() || 'Ticket access denied',
        );
    }

    if ( !$Self->{Permission}->QueueAccessCheck(
        UserID     => $UserID,
        QueueID    => $TicketBefore->{queue_id},
        Permission => 'ticket.edit',
    ) ) {
        return $Self->_FailureRecord(
            OperationID => $OperationID,
            TicketID    => $TicketID,
            Number      => $TicketBefore->{ticket_number},
            Status      => 'skipped',
            Error       => 'Translate:TicketBulkActionPermissionDenied',
        );
    }

    # Bulk actions intentionally ignore required dynamic fields, including
    # fields assigned to a target queue. Existing values remain untouched.
    my $Expected = $Self->_ExpectedChangeCount(
        Ticket  => $TicketBefore,
        Changes => $Changes,
    );

    if (!$Expected) {
        return $Self->_FailureRecord(
            OperationID => $OperationID,
            TicketID    => $TicketID,
            Number      => $TicketBefore->{ticket_number},
            Status      => 'skipped',
            Error       => 'Translate:TicketBulkActionNoChange',
        );
    }

    if ( !$Self->{DB}->BeginWork() ) {
        return $Self->_FailureRecord(
            OperationID => $OperationID,
            TicketID    => $TicketID,
            Number      => $TicketBefore->{ticket_number},
            Status      => 'failed',
            Error       => $Self->{DB}->Error() || 'Translate:TicketBulkActionFailed',
        );
    }

    $Self->_NotificationSuppressionSet(1);

    my $OK = 1;

    if ( $OK && $Changes->{QueueID} && ( $TicketBefore->{queue_id} || 0 ) != $Changes->{QueueID} ) {
        $OK = $Self->{Ticket}->TicketQueueUpdate(
            TicketID        => $TicketID,
            QueueID         => $Changes->{QueueID},
            User            => $User,
            ChangedByUserID => $UserID,
        );
    }

    if ( $OK && $Changes->{OwnerChange} && ( $TicketBefore->{owner_user_id} || 0 ) != $Changes->{OwnerUserID} ) {
        $OK = $Self->{Ticket}->TicketOwnerUpdate(
            TicketID            => $TicketID,
            OwnerUserID         => $Changes->{OwnerUserID},
            AllowUnassigned     => 1,
            User                => $User,
            ChangedByUserID     => $UserID,
            SuppressNotification => 1,
        );
    }

    if ( $OK && $Changes->{ResponsibleChange} && ( $TicketBefore->{responsible_user_id} || 0 ) != $Changes->{ResponsibleUserID} ) {
        $OK = $Self->{Ticket}->TicketResponsibleUpdate(
            TicketID             => $TicketID,
            ResponsibleUserID    => $Changes->{ResponsibleUserID},
            AllowUnassigned      => 1,
            User                 => $User,
            ChangedByUserID      => $UserID,
        );
    }

    if ( $OK && $Changes->{StateID} && ( $TicketBefore->{state_id} || 0 ) != $Changes->{StateID} ) {
        $OK = $Self->{Ticket}->TicketStatusUpdate(
            TicketID            => $TicketID,
            StatusID            => $Changes->{StateID},
            PendingUntil        => $Changes->{PendingUntil} || '',
            ChangedByUserID     => $UserID,
            SuppressNotification => 1,
        );
    }

    if ( $OK && $Changes->{PriorityID} && ( $TicketBefore->{priority_id} || 0 ) != $Changes->{PriorityID} ) {
        $OK = $Self->{Ticket}->TicketPriorityUpdate(
            TicketID        => $TicketID,
            PriorityID      => $Changes->{PriorityID},
            User            => $User,
            ChangedByUserID => $UserID,
        );
    }

    if (!$OK) {
        my $Error = $Self->{Ticket}->Error() || 'Translate:TicketBulkActionFailed';
        $Self->{DB}->Rollback();
        $Self->_NotificationSuppressionSet(0);
        return $Self->_FailureRecord(
            OperationID => $OperationID,
            TicketID    => $TicketID,
            Number      => $TicketBefore->{ticket_number},
            Status      => 'failed',
            Error       => $Error,
        );
    }

    my $TicketAfter = $Self->{Ticket}->TicketGet(
        TicketID => $TicketID,
        User     => $User,
        Language => $Language,
    );

    if (!$TicketAfter) {
        my $Error = $Self->{Ticket}->Error() || 'Translate:TicketBulkActionFailed';
        $Self->{DB}->Rollback();
        $Self->_NotificationSuppressionSet(0);
        return $Self->_FailureRecord(
            OperationID => $OperationID,
            TicketID    => $TicketID,
            Number      => $TicketBefore->{ticket_number},
            Status      => 'failed',
            Error       => $Error,
        );
    }

    my $ChangeList = $Self->_ChangeList(
        Before  => $TicketBefore,
        After   => $TicketAfter,
        Changes => $Changes,
    );

    my $AuditOK = $Self->{DB}->Do(
        'INSERT INTO ticket_bulk_action_item (
            bulk_action_id, ticket_id, ticket_number_snapshot, result,
            error_message, changes_json, created_at
         ) VALUES (?, ?, ?, ?, NULL, ?, NOW())',
        $OperationID,
        $TicketID,
        $TicketBefore->{ticket_number} || '',
        'success',
        $Self->_JSONEncode($ChangeList),
    );

    if (!$AuditOK) {
        my $Error = $Self->{DB}->Error() || 'Translate:TicketBulkActionAuditFailed';
        $Self->{DB}->Rollback();
        $Self->_NotificationSuppressionSet(0);
        return $Self->_FailureRecord(
            OperationID => $OperationID,
            TicketID    => $TicketID,
            Number      => $TicketBefore->{ticket_number},
            Status      => 'failed',
            Error       => $Error,
        );
    }

    $Self->_NotificationSuppressionSet(0);

    if ( !$Self->{DB}->Commit() ) {
        my $Error = $Self->{DB}->Error() || 'Translate:TicketBulkActionFailed';
        $Self->{DB}->Rollback();
        return $Self->_FailureRecord(
            OperationID => $OperationID,
            TicketID    => $TicketID,
            Number      => $TicketBefore->{ticket_number},
            Status      => 'failed',
            Error       => $Error,
        );
    }

    return { Status => 'success' };
}

sub _ExpectedChangeCount {
    my ( $Self, %Param ) = @_;

    my $Ticket  = $Param{Ticket};
    my $Changes = $Param{Changes};
    my $Count   = 0;

    $Count++ if $Changes->{QueueID} && ( $Ticket->{queue_id} || 0 ) != $Changes->{QueueID};
    $Count++ if $Changes->{OwnerChange} && ( $Ticket->{owner_user_id} || 0 ) != $Changes->{OwnerUserID};
    $Count++ if $Changes->{ResponsibleChange} && ( $Ticket->{responsible_user_id} || 0 ) != $Changes->{ResponsibleUserID};
    $Count++ if $Changes->{StateID} && ( $Ticket->{state_id} || 0 ) != $Changes->{StateID};
    $Count++ if $Changes->{PriorityID} && ( $Ticket->{priority_id} || 0 ) != $Changes->{PriorityID};

    return $Count;
}

sub _ChangeList {
    my ( $Self, %Param ) = @_;

    my $Before  = $Param{Before};
    my $After   = $Param{After};
    my $Changes = $Param{Changes};
    my @Change;

    my @Definition = (
        [ queue       => 'TicketQueue',       'queue_id',            'queue_full_name' ],
        [ owner       => 'TicketOwner',       'owner_user_id',       'owner_name' ],
        [ responsible => 'TicketResponsible', 'responsible_user_id', 'responsible_name' ],
        [ state       => 'TicketState',       'state_id',            'state_name_display' ],
        [ priority    => 'TicketPriority',    'priority_id',         'priority_name_display' ],
    );

    for my $Definition (@Definition) {
        my ( $Field, $LabelKey, $IDKey, $ValueKey ) = @{$Definition};
        next if ( $Before->{$IDKey} || 0 ) == ( $After->{$IDKey} || 0 );

        my $OldValue = $Before->{$ValueKey};
        my $NewValue = $After->{$ValueKey};
        $OldValue = $Before->{queue_name} if $Field eq 'queue' && !$OldValue;
        $NewValue = $After->{queue_name}  if $Field eq 'queue' && !$NewValue;

        push @Change, {
            field     => $Field,
            label_key => $LabelKey,
            old_id    => 0 + ( $Before->{$IDKey} || 0 ),
            new_id    => 0 + ( $After->{$IDKey} || 0 ),
            old_value => $OldValue || '-',
            new_value => $NewValue || '-',
        };
    }

    return \@Change;
}

sub _FailureRecord {
    my ( $Self, %Param ) = @_;

    my $Status = $Param{Status} eq 'skipped' ? 'skipped' : 'failed';
    my $TicketID = $Param{TicketID};

    if ($TicketID) {
        my $Exists = $Self->{DB}->SelectRow(
            'SELECT id, ticket_number FROM ticket WHERE id = ? LIMIT 1',
            $TicketID,
        );
        if ($Exists) {
            $Param{Number} ||= $Exists->{ticket_number};
        }
        else {
            $TicketID = undef;
        }
    }

    $Self->{DB}->Do(
        'INSERT INTO ticket_bulk_action_item (
            bulk_action_id, ticket_id, ticket_number_snapshot, result,
            error_message, changes_json, created_at
         ) VALUES (?, ?, ?, ?, ?, ?, NOW())',
        $Param{OperationID},
        $TicketID,
        $Param{Number} || '',
        $Status,
        $Param{Error} || 'Translate:TicketBulkActionFailed',
        '[]',
    );

    return { Status => $Status };
}

sub _NotificationSuppressionSet {
    my ( $Self, $Enabled ) = @_;

    my $DBH = $Self->{DB}->Handle();
    return if !$DBH;
    eval { $DBH->do( 'SET @qisutu_suppress_notifications = ' . ( $Enabled ? '1' : '0' ) ); 1; };
    return 1;
}

sub _ChangesHaveAction {
    my ( $Self, $Changes ) = @_;
    return 1 if $Changes->{QueueID} || $Changes->{StateID} || $Changes->{PriorityID};
    return 1 if $Changes->{OwnerChange} || $Changes->{ResponsibleChange};
    return 0;
}

sub _EmptyOptions {
    return { Queues => [], States => [], Priorities => [], Owners => [], Responsibles => [] };
}

sub _JSONEncode {
    my ( $Self, $Value ) = @_;
    return eval { $Self->{JSON}->encode($Value) } || '{}';
}

sub _JSONDecode {
    my ( $Self, $Value, $Fallback ) = @_;
    return $Fallback if !defined $Value || $Value eq '';
    my $Decoded = eval { $Self->{JSON}->decode($Value) };
    return $@ ? $Fallback : $Decoded;
}

sub _UserName {
    my ( $Self, $User ) = @_;
    my $Name = join ' ', grep { defined $_ && $_ ne '' } ( $User->{firstname}, $User->{lastname} );
    return $Name || $User->{login} || '-';
}

sub _Trim {
    my ( $Self, $Value ) = @_;
    return '' if !defined $Value || ref $Value;
    $Value =~ s{\x00}{}g;
    $Value =~ s{\A\s+|\s+\z}{}g;
    return $Value;
}

1;
