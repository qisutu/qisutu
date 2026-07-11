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

package QisutuTicket;

use strict;
use warnings;
use utf8;

use POSIX qw(strftime);
use Time::Local qw(timelocal);

use QisutuCalendar;
use QisutuDynamicField;
use QisutuHTML;
use QisutuNotification;
use QisutuService;
use QisutuSystemSetting;

sub new {
    my ( $Class, %Param ) = @_;

    my $Self = {
        DB         => $Param{DB},
        Config     => $Param{Config},
        Permission                 => $Param{Permission},
        LastError                  => '',
        LastAgentNotificationSent  => 0,
        LastAgentNotificationError => '',
        LastEmailImportAction      => '',
        LastEmailImportTicketID    => 0,
    };

    bless $Self, $Class;

    return $Self;
}

sub TicketList {
    my ( $Self, %Param ) = @_;

    my $Limit            = $Param{Limit} || 100;
    my $User             = $Param{User}  || {};
    my $ZoomPage         = $Param{ZoomPage} || ( ( $User->{account_type} || '' ) eq 'customer' ? 'CustomerTicketZoom' : 'AgentTicketZoom' );
    my $Language         = $Param{Language} || 'en';
    my $View             = $Param{View} || '';
    my $FilterQueueID        = $Param{FilterQueueID} || '';
    my $FilterCustomerID     = $Param{FilterCustomerID} || '';
    my $FilterCustomerUserID = $Param{FilterCustomerUserID} || '';
    my $FilterOwnerID        = $Param{FilterOwnerID} || '';
    my $SortBy           = $Param{SortBy} || 'changed';
    my $SortDirection    = lc( $Param{SortDirection} || 'desc' );
    my $DynamicFields    = ref $Param{DynamicFields} eq 'ARRAY' ? $Param{DynamicFields} : [];

    if ( $ZoomPage =~ m{[^A-Za-z0-9_]} ) {
        $ZoomPage = ( ( $User->{account_type} || '' ) eq 'customer' ? 'CustomerTicketZoom' : 'AgentTicketZoom' );
    }

    if ( $Limit !~ m{\A\d+\z} ) {
        $Limit = 100;
    }
    $Limit = 1 if $Limit < 1;
    $Limit = 500 if $Limit > 500;

    $SortDirection = $SortDirection eq 'asc' ? 'ASC' : 'DESC';

    my @Where;
    my @Bind;

    my $CustomerAccess = $Self->_CustomerAccessData( User => $User );

    if ($CustomerAccess) {
        my $QueueRule = $Self->_CustomerQueueRuleHash(
            User       => $User,
            Permission => 'ticket.view',
        );

        my @OwnQueueIDs;
        my @OrganizationQueueIDs;

        for my $QueueID ( sort { $a <=> $b } keys %{$QueueRule} ) {
            if ( ( $QueueRule->{$QueueID} || '' ) eq 'organization' ) {
                push @OrganizationQueueIDs, $QueueID;
            }
            else {
                push @OwnQueueIDs, $QueueID;
            }
        }

        return [] if !@OwnQueueIDs && !@OrganizationQueueIDs;

        my @CustomerWhere;

        if ( @OwnQueueIDs && $CustomerAccess->{customer_user_id} ) {
            my $Placeholder = join ', ', map {'?'} @OwnQueueIDs;
            push @CustomerWhere, '(t.queue_id IN (' . $Placeholder . ') AND t.customer_user_id = ?)';
            push @Bind, @OwnQueueIDs, $CustomerAccess->{customer_user_id};
        }

        if ( @OrganizationQueueIDs && $CustomerAccess->{customer_id} ) {
            my $Placeholder = join ', ', map {'?'} @OrganizationQueueIDs;
            push @CustomerWhere, '(t.queue_id IN (' . $Placeholder . ') AND t.customer_id = ?)';
            push @Bind, @OrganizationQueueIDs, $CustomerAccess->{customer_id};
        }

        return [] if !@CustomerWhere;
        push @Where, '(' . join( ' OR ', @CustomerWhere ) . ')';
    }
    elsif ( $Self->{Permission} ) {
        my $QueueIDs = $Self->{Permission}->QueueIDList(
            UserID     => $User->{user_account_id},
            Permission => 'ticket.view',
        );

        return [] if !@{$QueueIDs};

        my $Placeholder = join ', ', map {'?'} @{$QueueIDs};
        push @Where, 't.queue_id IN (' . $Placeholder . ')';
        push @Bind, @{$QueueIDs};
    }

    if ($View) {
        if ( $View eq 'new' ) {
            push @Where, 'LOWER(TRIM(s.name)) = ?';
            push @Bind, 'new';
        }
        elsif ( $View eq 'open' ) {
            push @Where, 's.state_type = ? AND LOWER(TRIM(s.name)) <> ?';
            push @Bind, 'open', 'new';
        }
        elsif ( $View eq 'pending' ) {
            push @Where, 's.state_type = ?';
            push @Bind, 'pending';
        }
        elsif ( $View eq 'escalated' ) {
            push @Where,
                's.state_type <> ?
                 AND s.sla_pause = 0
                 AND (
                    (t.first_response_due_at IS NOT NULL AND t.first_response_at IS NULL AND t.first_response_due_at <= NOW())
                    OR (t.update_due_at IS NOT NULL AND t.update_due_at <= NOW())
                    OR (t.solution_due_at IS NOT NULL AND t.solution_at IS NULL AND t.solution_due_at <= NOW())
                 )';
            push @Bind, 'closed';
        }
        elsif ( $View eq 'my' ) {
            push @Where, 't.owner_user_id = ?';
            push @Bind, $User->{user_account_id} || 0;
        }
    }

    if ( $FilterQueueID =~ m{\A\d+\z} && $FilterQueueID > 0 ) {
        push @Where, 't.queue_id = ?';
        push @Bind, $FilterQueueID;
    }

    if ( $FilterCustomerID =~ m{\A\d+\z} && $FilterCustomerID > 0 ) {
        push @Where, 't.customer_id = ?';
        push @Bind, $FilterCustomerID;
    }

    if ( $FilterCustomerUserID =~ m{\A\d+\z} && $FilterCustomerUserID > 0 ) {
        push @Where, 't.customer_user_id = ?';
        push @Bind, $FilterCustomerUserID;
    }

    if ( $FilterOwnerID eq 'unassigned' ) {
        push @Where, 't.owner_user_id IS NULL';
    }
    elsif ( $FilterOwnerID =~ m{\A\d+\z} && $FilterOwnerID > 0 ) {
        push @Where, 't.owner_user_id = ?';
        push @Bind, $FilterOwnerID;
    }

    my $WhereSQL = @Where ? 'WHERE ' . join( ' AND ', map { '(' . $_ . ')' } @Where ) : '';
    my $OrderExpression = $Self->_TicketListOrderExpression(
        SortBy        => $SortBy,
        DynamicFields => $DynamicFields,
    );

    my $AgeDirection = '';
    if ( $SortBy eq 'age' ) {
        $AgeDirection = $SortDirection eq 'ASC' ? 'DESC' : 'ASC';
    }

    my $OrderDirection = $AgeDirection || $SortDirection;

    my $Tickets = $Self->{DB}->SelectAll(
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
            t.service_id,
            t.sla_id,
            t.sla_source,
            t.sla_name_snapshot,
            t.sla_calendar_id,
            t.sla_update_mode,
            t.sla_first_response_minutes,
            t.sla_update_minutes,
            t.sla_solution_minutes,
            t.sla_pause_started_at,
            t.sla_pause_total_minutes,
            t.sla_first_response_breached,
            t.sla_update_breached,
            t.sla_solution_breached,
            svc.full_name AS service_name,
            sl.name AS current_sla_name,
            sla_cal.name AS sla_calendar_name,
            sla_cal.timezone AS sla_calendar_timezone,
            t.created_at,
            t.changed_at,
            t.first_response_due_at,
            t.first_response_at,
            t.update_due_at,
            t.last_customer_article_at,
            t.last_agent_article_at,
            t.solution_due_at,
            t.solution_at,
            t.pending_until,
            t.pending_started_at,
            t.pending_total_minutes,
            t.escalation_state,
            q.name AS queue_name,
            q.full_name AS queue_full_name,
            queue_cal.name AS queue_calendar_name,
            queue_cal.timezone AS queue_calendar_timezone,
            s.name AS state_name,
            s.state_type,
            s.sla_pause,
            p.name AS priority_name,
            p.priority_value,
            c.name AS customer_name,
            cu_account.login AS customer_user_login,
            cu_account.firstname AS customer_user_firstname,
            cu_account.lastname AS customer_user_lastname,
            owner_account.login AS owner_login,
            owner_account.firstname AS owner_firstname,
            owner_account.lastname AS owner_lastname,
            responsible_account.login AS responsible_login,
            responsible_account.firstname AS responsible_firstname,
            responsible_account.lastname AS responsible_lastname,
            created_account.login AS created_by_login,
            created_account.firstname AS created_by_firstname,
            created_account.lastname AS created_by_lastname
         FROM ticket t
         INNER JOIN ticket_queue q ON q.id = t.queue_id
         INNER JOIN ticket_state s ON s.id = t.state_id
         INNER JOIN ticket_priority p ON p.id = t.priority_id
         LEFT JOIN calendar queue_cal ON queue_cal.id = q.calendar_id
         LEFT JOIN service svc ON svc.id = t.service_id
         LEFT JOIN sla sl ON sl.id = t.sla_id
         LEFT JOIN calendar sla_cal ON sla_cal.id = t.sla_calendar_id
         LEFT JOIN customer c ON c.id = t.customer_id
         LEFT JOIN customer_user cu ON cu.id = t.customer_user_id
         LEFT JOIN user_account cu_account ON cu_account.id = cu.user_account_id
         LEFT JOIN user_account owner_account ON owner_account.id = t.owner_user_id
         LEFT JOIN user_account responsible_account ON responsible_account.id = t.responsible_user_id
         LEFT JOIN user_account created_account ON created_account.id = t.created_by_user_id
         ' . $WhereSQL . '
         ORDER BY ' . $OrderExpression . ' ' . $OrderDirection . ', t.id ' . $OrderDirection . '
         LIMIT ' . $Limit,
        @Bind
    );

    if ( !$Tickets ) {
        $Self->{LastError} = $Self->{DB}->Error() || 'Ticket list could not be loaded';
        return [];
    }

    for my $Ticket ( @{$Tickets} ) {
        $Ticket->{ticket_zoom_url} = 'index.pl?Page=' . $ZoomPage . '&TicketID=' . ( $Ticket->{id} || 0 );
        $Ticket->{state_name_display} = $Self->_TicketStateDisplay(
            State => $Ticket->{state_name},
        );
        $Ticket->{priority_name_display} = $Self->_TicketPriorityDisplay(
            Priority => $Ticket->{priority_name},
        );

        $Ticket->{customer_user_name} = $Self->_UserName(
            Firstname => $Ticket->{customer_user_firstname},
            Lastname  => $Ticket->{customer_user_lastname},
            Login     => $Ticket->{customer_user_login},
        );

        $Ticket->{owner_name} = $Self->_UserName(
            Firstname => $Ticket->{owner_firstname},
            Lastname  => $Ticket->{owner_lastname},
            Login     => $Ticket->{owner_login},
        );

        $Ticket->{responsible_name} = $Self->_UserName(
            Firstname => $Ticket->{responsible_firstname},
            Lastname  => $Ticket->{responsible_lastname},
            Login     => $Ticket->{responsible_login},
        );

        $Ticket->{created_by_name} = $Self->_UserName(
            Firstname => $Ticket->{created_by_firstname},
            Lastname  => $Ticket->{created_by_lastname},
            Login     => $Ticket->{created_by_login},
        );

        $Ticket->{customer_name} ||= '';
        $Ticket->{customer_user_name} ||= '-';
        $Ticket->{owner_name} ||= '-';
        $Ticket->{responsible_name} ||= '-';
        $Ticket->{owner_line_text} = '';

        if ( $Ticket->{owner_name} && $Ticket->{owner_name} ne '-' ) {
            $Ticket->{owner_line_text} = $Self->_TicketOwnerLabel( Language => $Language ) . ': ' . $Ticket->{owner_name};
        }

        $Ticket->{created_at_display} = $Self->_DateTimeFormat(
            DateTime => $Ticket->{created_at},
            Language => $Language,
        ) || '-';
        $Ticket->{changed_at_display} = $Self->_DateTimeFormat(
            DateTime => $Ticket->{changed_at},
            Language => $Language,
        ) || '-';

        $Self->_EscalationDisplayPrepare( Ticket => $Ticket, Language => $Language );

        $Ticket->{age_display} = $Self->_EscalationDurationFormat(
            From     => $Ticket->{created_at},
            To       => $Self->{_DisplayNowDateTime} || '',
            Language => $Language,
        ) || '-';
    }

    $Self->_TicketListDynamicValuesLoad(
        Tickets       => $Tickets,
        DynamicFields => $DynamicFields,
    );

    return $Tickets;
}

sub TicketListDynamicFieldList {
    my ( $Self, %Param ) = @_;

    my $Language = $Param{Language} || $Self->{Config}->{Language}->{Default} || 'en';
    $Language =~ s{[^A-Za-z0-9_-]}{}g;
    $Language ||= 'en';

    my $DefaultLanguage = $Self->{Config}->{Language}->{Default} || 'en';
    $DefaultLanguage =~ s{[^A-Za-z0-9_-]}{}g;
    $DefaultLanguage ||= 'en';

    my $Rows = $Self->{DB}->SelectAll(
        'SELECT
            f.id,
            f.object_type,
            f.name,
            COALESCE(current_translation.label, default_translation.label, f.label, f.name) AS label,
            f.field_type,
            f.sort_order
         FROM user_dynamic_field f
         LEFT JOIN user_dynamic_field_translation current_translation
            ON current_translation.field_id = f.id
            AND current_translation.language = ?
         LEFT JOIN user_dynamic_field_translation default_translation
            ON default_translation.field_id = f.id
            AND default_translation.language = ?
         WHERE f.active = 1
            AND f.object_type IN (?, ?, ?)
         ORDER BY f.object_type ASC, f.sort_order ASC, label ASC, f.id ASC',
        $Language,
        $DefaultLanguage,
        'customer',
        'customer_user',
        'agent',
    ) || [];

    my @Field;

    for my $Row ( @{$Rows} ) {
        next if ref $Row ne 'HASH';
        next if !$Row->{id};

        if ( ( $Row->{object_type} || '' ) eq 'customer' ) {
            push @Field, {
                %{$Row},
                column_key       => 'dynamic_customer_' . $Row->{id},
                target_type      => 'customer',
                value_object_type => 'customer',
            };
        }
        elsif ( ( $Row->{object_type} || '' ) eq 'customer_user' ) {
            push @Field, {
                %{$Row},
                column_key       => 'dynamic_customer_user_' . $Row->{id},
                target_type      => 'customer_user',
                value_object_type => 'customer_user',
            };
        }
        elsif ( ( $Row->{object_type} || '' ) eq 'agent' ) {
            push @Field, {
                %{$Row},
                column_key       => 'dynamic_owner_' . $Row->{id},
                target_type      => 'owner',
                value_object_type => 'agent',
            };
            push @Field, {
                %{$Row},
                column_key       => 'dynamic_responsible_' . $Row->{id},
                target_type      => 'responsible',
                value_object_type => 'agent',
            };
        }
    }

    return \@Field;
}

sub TicketListFilterOptions {
    my ( $Self, %Param ) = @_;

    my $User = $Param{User} || {};
    my @QueueBind;
    my $QueueWhere       = '';
    my $TicketQueueWhere = '';

    if ( $Self->{Permission} ) {
        my $QueueIDs = $Self->{Permission}->QueueIDList(
            UserID     => $User->{user_account_id},
            Permission => 'ticket.view',
        );

        if ( @{$QueueIDs} ) {
            my $Placeholder = join ', ', map {'?'} @{$QueueIDs};
            $QueueWhere       = 'WHERE id IN (' . $Placeholder . ')';
            $TicketQueueWhere = 'WHERE t.queue_id IN (' . $Placeholder . ')';
            @QueueBind = @{$QueueIDs};
        }
        else {
            return {
                Queues        => [],
                Customers     => [],
                CustomerUsers => [],
                Owners        => [],
            };
        }
    }

    my $QueueRows = $Self->{DB}->SelectAll(
        'SELECT id, COALESCE(NULLIF(full_name, ""), name) AS label
         FROM ticket_queue
         ' . $QueueWhere . '
         ORDER BY sort_order ASC, label ASC, id ASC',
        @QueueBind,
    ) || [];

    my $CustomerRows = $Self->{DB}->SelectAll(
        'SELECT DISTINCT c.id, c.name AS label
         FROM ticket t
         INNER JOIN customer c ON c.id = t.customer_id
         ' . $TicketQueueWhere . '
         ORDER BY c.name ASC, c.id ASC',
        @QueueBind,
    ) || [];

    my $CustomerUserRows = $Self->{DB}->SelectAll(
        'SELECT DISTINCT
            cu.id,
            COALESCE(
                NULLIF(TRIM(CONCAT(cu_account.firstname, " ", cu_account.lastname)), ""),
                NULLIF(cu_account.login, ""),
                cu_account.email
            ) AS label
         FROM ticket t
         INNER JOIN customer_user cu ON cu.id = t.customer_user_id
         INNER JOIN user_account cu_account ON cu_account.id = cu.user_account_id
         ' . $TicketQueueWhere . '
         ORDER BY label ASC, cu.id ASC',
        @QueueBind,
    ) || [];

    my $OwnerRows = $Self->{DB}->SelectAll(
        'SELECT DISTINCT
            owner_account.id,
            COALESCE(NULLIF(TRIM(CONCAT(owner_account.firstname, " ", owner_account.lastname)), ""), owner_account.login) AS label
         FROM ticket t
         INNER JOIN user_account owner_account ON owner_account.id = t.owner_user_id
         ' . $TicketQueueWhere . '
         ORDER BY label ASC, owner_account.id ASC',
        @QueueBind,
    ) || [];

    return {
        Queues        => $QueueRows,
        Customers     => $CustomerRows,
        CustomerUsers => $CustomerUserRows,
        Owners        => $OwnerRows,
    };
}

sub _TicketListOrderExpression {
    my ( $Self, %Param ) = @_;

    my $SortBy        = $Param{SortBy} || 'changed';
    my $DynamicFields = $Param{DynamicFields} || [];

    my %Static = (
        ticket_number    => 't.ticket_number',
        title            => 't.title',
        queue            => 'q.full_name',
        state            => 's.name',
        priority         => 'p.priority_value',
        customer         => 'c.name',
        customer_user    => 'CONCAT(COALESCE(cu_account.firstname, ""), " ", COALESCE(cu_account.lastname, ""), " ", COALESCE(cu_account.login, ""))',
        owner            => 'CONCAT(COALESCE(owner_account.firstname, ""), " ", COALESCE(owner_account.lastname, ""), " ", COALESCE(owner_account.login, ""))',
        responsible      => 'CONCAT(COALESCE(responsible_account.firstname, ""), " ", COALESCE(responsible_account.lastname, ""), " ", COALESCE(responsible_account.login, ""))',
        created          => 't.created_at',
        changed          => 't.changed_at',
        age              => 't.created_at',
        escalation_state => 'CASE
            WHEN s.state_type <> "closed" AND s.sla_pause = 0 AND (
                (t.first_response_due_at IS NOT NULL AND t.first_response_at IS NULL AND t.first_response_due_at <= NOW())
                OR (t.update_due_at IS NOT NULL AND t.update_due_at <= NOW())
                OR (t.solution_due_at IS NOT NULL AND t.solution_at IS NULL AND t.solution_due_at <= NOW())
            ) THEN 2
            WHEN t.escalation_state = "warning" THEN 1
            ELSE 0
        END',
        next_escalation => 'NULLIF(LEAST(
            COALESCE(CASE WHEN t.first_response_at IS NULL THEN t.first_response_due_at END, "9999-12-31 23:59:59"),
            COALESCE(t.update_due_at, "9999-12-31 23:59:59"),
            COALESCE(CASE WHEN t.solution_at IS NULL THEN t.solution_due_at END, "9999-12-31 23:59:59")
        ), "9999-12-31 23:59:59")',
        pending_until => 't.pending_until',
    );

    return $Static{$SortBy} if $Static{$SortBy};

    for my $Field ( @{$DynamicFields} ) {
        next if ref $Field ne 'HASH';
        next if ( $Field->{column_key} || $Field->{key} || '' ) ne $SortBy;
        next if ( $Field->{id} || 0 ) !~ m{\A\d+\z};

        my $ObjectColumn = '';
        if ( ( $Field->{target_type} || '' ) eq 'customer' ) {
            $ObjectColumn = 't.customer_id';
        }
        elsif ( ( $Field->{target_type} || '' ) eq 'customer_user' ) {
            $ObjectColumn = 't.customer_user_id';
        }
        elsif ( ( $Field->{target_type} || '' ) eq 'owner' ) {
            $ObjectColumn = 't.owner_user_id';
        }
        elsif ( ( $Field->{target_type} || '' ) eq 'responsible' ) {
            $ObjectColumn = 't.responsible_user_id';
        }

        next if !$ObjectColumn;

        my $ObjectType = $Field->{value_object_type} || $Field->{object_type} || '';
        next if $ObjectType !~ m{\A(?:customer|customer_user|agent)\z};

        return '(SELECT dfv.value_text
                 FROM user_dynamic_field_value dfv
                 WHERE dfv.field_id = ' . int( $Field->{id} ) . '
                    AND dfv.object_type = "' . $ObjectType . '"
                    AND dfv.object_id = ' . $ObjectColumn . '
                 LIMIT 1)';
    }

    return 't.changed_at';
}

sub _TicketListDynamicValuesLoad {
    my ( $Self, %Param ) = @_;

    my $Tickets       = $Param{Tickets} || [];
    my $DynamicFields = $Param{DynamicFields} || [];

    return 1 if !@{$Tickets} || !@{$DynamicFields};

    for my $Ticket ( @{$Tickets} ) {
        $Ticket->{dynamic_values} ||= {};
    }

    for my $Field ( @{$DynamicFields} ) {
        next if ref $Field ne 'HASH';
        my $FieldID = $Field->{id} || 0;
        next if $FieldID !~ m{\A\d+\z} || !$FieldID;

        my $TargetType = $Field->{target_type} || '';
        my $ObjectType = $Field->{value_object_type} || $Field->{object_type} || '';
        my $ColumnKey  = $Field->{column_key} || $Field->{key} || '';
        next if !$ColumnKey;
        next if $ObjectType !~ m{\A(?:customer|customer_user|agent)\z};

        my $ObjectIDKey = '';
        if ( $TargetType eq 'customer' ) {
            $ObjectIDKey = 'customer_id';
        }
        elsif ( $TargetType eq 'customer_user' ) {
            $ObjectIDKey = 'customer_user_id';
        }
        elsif ( $TargetType eq 'owner' ) {
            $ObjectIDKey = 'owner_user_id';
        }
        elsif ( $TargetType eq 'responsible' ) {
            $ObjectIDKey = 'responsible_user_id';
        }
        next if !$ObjectIDKey;

        my %ObjectID;
        for my $Ticket ( @{$Tickets} ) {
            my $ObjectID = $Ticket->{$ObjectIDKey} || 0;
            $ObjectID{$ObjectID} = 1 if $ObjectID;
        }
        next if !%ObjectID;

        my @ObjectIDs = sort { $a <=> $b } keys %ObjectID;
        my $Placeholder = join ', ', map {'?'} @ObjectIDs;
        my $Rows = $Self->{DB}->SelectAll(
            'SELECT object_id, value_text
             FROM user_dynamic_field_value
             WHERE field_id = ?
                AND object_type = ?
                AND object_id IN (' . $Placeholder . ')',
            $FieldID,
            $ObjectType,
            @ObjectIDs,
        ) || [];

        my %ValueByObjectID = map {
            ( $_->{object_id} || 0 ) => ( defined $_->{value_text} ? $_->{value_text} : '' )
        } grep { ref $_ eq 'HASH' } @{$Rows};

        for my $Ticket ( @{$Tickets} ) {
            my $ObjectID = $Ticket->{$ObjectIDKey} || 0;
            $Ticket->{dynamic_values}->{$ColumnKey} = $ObjectID && exists $ValueByObjectID{$ObjectID}
                ? $ValueByObjectID{$ObjectID}
                : '';
        }
    }

    return 1;
}


sub TicketGet {
    my ( $Self, %Param ) = @_;

    my $TicketID     = $Param{TicketID}     || 0;
    my $TicketNumber = $Param{TicketNumber} || '';
    my $User         = $Param{User}         || {};
    my $Language     = $Param{Language}     || 'en';

    my $Where;
    my @Bind;

    if ($TicketID) {
        return if $TicketID !~ m{\A\d+\z};

        $Where = 't.id = ?';
        @Bind  = ($TicketID);
    }
    elsif ($TicketNumber) {
        $Where = 't.ticket_number = ?';
        @Bind  = ($TicketNumber);
    }
    else {
        $Self->{LastError} = 'TicketID or TicketNumber is required';
        return;
    }

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
            t.service_id,
            t.sla_id,
            t.sla_source,
            t.sla_assignment_source,
            t.sla_name_snapshot,
            t.sla_calendar_id,
            t.sla_update_mode,
            t.sla_first_response_minutes,
            t.sla_update_minutes,
            t.sla_solution_minutes,
            t.sla_pause_started_at,
            t.sla_pause_total_minutes,
            t.sla_first_response_breached,
            t.sla_update_breached,
            t.sla_solution_breached,
            t.created_at,
            t.changed_at,
            t.first_response_due_at,
            t.first_response_at,
            t.update_due_at,
            t.last_customer_article_at,
            t.last_agent_article_at,
            t.solution_due_at,
            t.solution_at,
            t.pending_until,
            t.pending_started_at,
            t.pending_total_minutes,
            t.escalation_state,
            q.calendar_id,
            q.escalation_first_response_minutes,
            q.escalation_update_minutes,
            q.escalation_solution_minutes,
            q.name AS queue_name,
            q.full_name AS queue_full_name,
            queue_cal.name AS queue_calendar_name,
            queue_cal.timezone AS queue_calendar_timezone,
            s.name AS state_name,
            s.state_type,
            s.sla_pause,
            p.name AS priority_name,
            p.priority_value,
            svc.full_name AS service_name,
            sl.name AS current_sla_name,
            sla_cal.name AS sla_calendar_name,
            sla_cal.timezone AS sla_calendar_timezone,
            c.customer_number,
            c.name AS customer_name,
            cu_account.login AS customer_user_login,
            cu_account.email AS customer_user_email,
            cu_account.firstname AS customer_user_firstname,
            cu_account.lastname AS customer_user_lastname,
            owner_account.login AS owner_login,
            owner_account.email AS owner_email,
            owner_account.firstname AS owner_firstname,
            owner_account.lastname AS owner_lastname,
            responsible_account.login AS responsible_login,
            responsible_account.email AS responsible_email,
            responsible_account.firstname AS responsible_firstname,
            responsible_account.lastname AS responsible_lastname,
            created_account.login AS created_by_login,
            created_account.email AS created_by_email,
            created_account.firstname AS created_by_firstname,
            created_account.lastname AS created_by_lastname,
            changed_account.login AS changed_by_login,
            changed_account.email AS changed_by_email,
            changed_account.firstname AS changed_by_firstname,
            changed_account.lastname AS changed_by_lastname
         FROM ticket t
         INNER JOIN ticket_queue q ON q.id = t.queue_id
         INNER JOIN ticket_state s ON s.id = t.state_id
         INNER JOIN ticket_priority p ON p.id = t.priority_id
         LEFT JOIN calendar queue_cal ON queue_cal.id = q.calendar_id
         LEFT JOIN service svc ON svc.id = t.service_id
         LEFT JOIN sla sl ON sl.id = t.sla_id
         LEFT JOIN calendar sla_cal ON sla_cal.id = t.sla_calendar_id
         LEFT JOIN customer c ON c.id = t.customer_id
         LEFT JOIN customer_user cu ON cu.id = t.customer_user_id
         LEFT JOIN user_account cu_account ON cu_account.id = cu.user_account_id
         LEFT JOIN user_account owner_account ON owner_account.id = t.owner_user_id
         LEFT JOIN user_account responsible_account ON responsible_account.id = t.responsible_user_id
         LEFT JOIN user_account created_account ON created_account.id = t.created_by_user_id
         LEFT JOIN user_account changed_account ON changed_account.id = t.changed_by_user_id
         WHERE ' . $Where . '
         LIMIT 1',
        @Bind
    );

    if ( !$Ticket ) {
        $Self->{LastError} = $Self->{DB}->Error() || 'Ticket not found';
        return;
    }

    $Ticket->{customer_user_name} = $Self->_UserName(
        Firstname => $Ticket->{customer_user_firstname},
        Lastname  => $Ticket->{customer_user_lastname},
        Login     => $Ticket->{customer_user_login},
    );

    $Ticket->{owner_name} = $Self->_UserName(
        Firstname => $Ticket->{owner_firstname},
        Lastname  => $Ticket->{owner_lastname},
        Login     => $Ticket->{owner_login},
    );

    $Ticket->{responsible_name} = $Self->_UserName(
        Firstname => $Ticket->{responsible_firstname},
        Lastname  => $Ticket->{responsible_lastname},
        Login     => $Ticket->{responsible_login},
    );

    $Ticket->{created_by_name} = $Self->_UserName(
        Firstname => $Ticket->{created_by_firstname},
        Lastname  => $Ticket->{created_by_lastname},
        Login     => $Ticket->{created_by_login},
    );

    $Ticket->{changed_by_name} = $Self->_UserName(
        Firstname => $Ticket->{changed_by_firstname},
        Lastname  => $Ticket->{changed_by_lastname},
        Login     => $Ticket->{changed_by_login},
    );

    if ( $Self->{Permission} ) {
        my $Allowed;
        my $CustomerAccess = $Self->_CustomerAccessData( User => $User );

        if ($CustomerAccess) {
            $Allowed = $Self->_CustomerTicketAccessCheck(
                Ticket         => $Ticket,
                CustomerAccess => $CustomerAccess,
                User           => $User,
            );
        }
        else {
            $Allowed = $Self->{Permission}->QueueAccessCheck(
                UserID     => $User->{user_account_id},
                QueueID    => $Ticket->{queue_id},
                Permission => 'ticket.view',
            );
        }

        if ( !$Allowed ) {
            $Self->{LastError} = 'Ticket access denied';
            return;
        }
    }

    $Ticket->{customer_name}      ||= '';
    $Ticket->{customer_number}    ||= '';
    $Ticket->{service_name}       ||= '-';
    $Ticket->{sla_name_display}     = $Ticket->{sla_name_snapshot} || $Ticket->{current_sla_name} || '-';
    if ( ( $Ticket->{sla_source} || '' ) eq 'sla' ) {
        $Ticket->{sla_calendar_display} = $Ticket->{sla_calendar_name}
            ? $Ticket->{sla_calendar_name} . ( $Ticket->{sla_calendar_timezone} ? ' ' . $Ticket->{sla_calendar_timezone} : '' )
            : '-';
    }
    else {
        $Ticket->{sla_calendar_display} = $Ticket->{queue_calendar_name}
            ? $Ticket->{queue_calendar_name} . ( $Ticket->{queue_calendar_timezone} ? ' ' . $Ticket->{queue_calendar_timezone} : '' )
            : '-';
    }
    if ( ( $Ticket->{sla_source} || '' ) eq 'sla' ) {
        $Ticket->{sla_source_label} = ( $Ticket->{sla_assignment_source} || '' ) eq 'customer'
            ? 'Translate:TicketSLASourceCustomer'
            : 'Translate:TicketSLASourceDefault';
    }
    else {
        $Ticket->{sla_source_label} = 'Translate:TicketSLASourceQueue';
    }
    $Ticket->{sla_update_mode_label} = ( $Ticket->{sla_update_mode} || '' ) eq 'regular'
        ? 'Translate:AdminSLAUpdateModeRegular'
        : 'Translate:AdminSLAUpdateModeCustomer';
    $Ticket->{state_name_display} = $Self->_TicketStateDisplay(
        State => $Ticket->{state_name},
    );
    $Ticket->{priority_name_display} = $Self->_TicketPriorityDisplay(
        Priority => $Ticket->{priority_name},
    );
    $Ticket->{customer_user_name} ||= '-';
    $Ticket->{owner_name}         ||= '-';
    $Ticket->{responsible_name}   ||= '-';
    $Ticket->{created_by_name}    ||= '-';
    $Ticket->{changed_by_name}    ||= '-';

    $Self->_EscalationDisplayPrepare( Ticket => $Ticket, Language => $Language );

    return $Ticket;
}

sub TicketCreateFromEmail {
    my ( $Self, %Param ) = @_;

    my $QueueID         = $Param{QueueID} || 0;
    my $Title           = $Param{Subject} || $Param{Title} || '(no subject)';
    my $Body            = $Param{Body} || '(empty message)';
    my $ContentType     = $Param{ContentType} || 'text/plain';
    my $FromName        = $Param{FromName} || '';
    my $FromEmail       = $Param{FromEmail} || '';
    my $ToName          = $Param{ToName} || '';
    my $ToEmail         = $Param{ToEmail} || '';
    my $CreatedByUserID = $Param{CreatedByUserID} || 1;
    my $ChangedByUserID = $Param{ChangedByUserID} || $CreatedByUserID;
    my $Attachments     = ref $Param{Attachments} eq 'ARRAY' ? $Param{Attachments} : [];

    $Self->{LastEmailImportAction}   = '';
    $Self->{LastEmailImportTicketID} = 0;

    if ( $QueueID !~ m{\A\d+\z} || !$QueueID ) {
        $Self->{LastError} = 'Valid QueueID is required';
        return;
    }

    my $Queue = $Self->{DB}->SelectRow(
        'SELECT id
         FROM ticket_queue
         WHERE id = ?
           AND active = 1
         LIMIT 1',
        $QueueID,
    );

    if ( !$Queue ) {
        $Self->{LastError} = 'Queue was not found';
        return;
    }

    my $ExistingTicketID = $Self->_TicketIDFromSubject( Subject => $Title );
    if ($ExistingTicketID) {
        return $Self->_TicketReplyCreateFromEmail(
            TicketID        => $ExistingTicketID,
            Subject         => $Title,
            Body            => $Body,
            ContentType     => $ContentType,
            FromName        => $FromName,
            FromEmail       => $FromEmail,
            ToName          => $ToName,
            ToEmail         => $ToEmail,
            CreatedByUserID => $CreatedByUserID,
            ChangedByUserID => $ChangedByUserID,
            Attachments     => $Attachments,
        );
    }

    my $StateID = $Self->_DefaultStateID();
    return if !$StateID;

    my $PriorityID = $Self->_DefaultPriorityID();
    return if !$PriorityID;

    my ( $CustomerID, $CustomerUserID ) = $Self->_CustomerByEmail( Email => $FromEmail );
    my $TicketNumber = $Self->_TicketNumberCreate();

    if ( !$TicketNumber ) {
        $Self->{LastError} ||= 'Ticket number could not be created';
        return;
    }

    $Title =~ s{\A\s+}{};
    $Title =~ s{\s+\z}{};
    $Title ||= '(no subject)';

    if ( length $Title > 500 ) {
        $Title = substr $Title, 0, 500;
    }

    $Self->{DB}->BeginWork() || do {
        $Self->{LastError} = $Self->{DB}->Error() || 'Transaction could not be started';
        return;
    };

    my $TicketResult = $Self->{DB}->Do(
        'INSERT INTO ticket (
            ticket_number,
            title,
            queue_id,
            state_id,
            priority_id,
            customer_id,
            customer_user_id,
            owner_user_id,
            responsible_user_id,
            created_by_user_id,
            changed_by_user_id,
            created_at,
            changed_at
        ) VALUES (
            ?, ?, ?, ?, ?, ?, ?, NULL, NULL, ?, ?, NOW(), NOW()
        )',
        $TicketNumber,
        $Title,
        $QueueID,
        $StateID,
        $PriorityID,
        $CustomerID,
        $CustomerUserID,
        $CreatedByUserID,
        $ChangedByUserID,
    );

    if ( !$TicketResult ) {
        $Self->{LastError} = $Self->{DB}->Error() || 'Ticket could not be created';
        $Self->{DB}->Rollback();
        return;
    }

    my $TicketID = $Self->{DB}->LastInsertID('ticket');

    if ( !$TicketID ) {
        $Self->{LastError} = 'Ticket ID could not be loaded';
        $Self->{DB}->Rollback();
        return;
    }

    my $ArticleID = $Self->ArticleCreate(
        TicketID        => $TicketID,
        Subject         => $Title,
        Body            => $Body,
        Channel         => 'email',
        SenderType      => 'customer',
        FromName        => $FromName,
        FromEmail       => $FromEmail,
        ToName          => $ToName,
        ToEmail         => $ToEmail,
        ContentType     => $ContentType,
        Visibility      => 'both',
        SkipTicketAccessCheck => 1,
        SkipNotification => 1,
        CreatedByUserID => $CreatedByUserID,
        ChangedByUserID => $ChangedByUserID,
        Attachments     => $Attachments,
    );

    if ( !$ArticleID ) {
        $Self->{LastError} ||= 'Initial e-mail article could not be created';
        $Self->{DB}->Rollback();
        return;
    }

    if ( !$Self->{DB}->Commit() ) {
        $Self->{LastError} = $Self->{DB}->Error() || 'Ticket transaction could not be committed';
        $Self->{DB}->Rollback();
        return;
    }

    $Self->_AgentNotificationSend(
        NotificationType => 'ticket_new_in_my_queues',
        TicketID         => $TicketID,
        ChangedByUserID  => $ChangedByUserID,
    );

    $Self->{LastEmailImportAction}   = 'created';
    $Self->{LastEmailImportTicketID} = $TicketID;

    return $TicketID;
}

sub _TicketReplyCreateFromEmail {
    my ( $Self, %Param ) = @_;

    my $TicketID        = $Param{TicketID} || 0;
    my $Subject         = $Param{Subject} || '(no subject)';
    my $Body            = $Param{Body} || '(empty message)';
    my $ContentType     = $Param{ContentType} || 'text/plain';
    my $FromName        = $Param{FromName} || '';
    my $FromEmail       = $Param{FromEmail} || '';
    my $ToName          = $Param{ToName} || '';
    my $ToEmail         = $Param{ToEmail} || '';
    my $CreatedByUserID = $Param{CreatedByUserID} || 1;
    my $ChangedByUserID = $Param{ChangedByUserID} || $CreatedByUserID;
    my $Attachments     = ref $Param{Attachments} eq 'ARRAY' ? $Param{Attachments} : [];

    my $Ticket = $Self->{DB}->SelectRow(
        'SELECT id, ticket_number
         FROM ticket
         WHERE id = ?
         LIMIT 1',
        $TicketID,
    );

    if (!$Ticket) {
        $Self->{LastError} = 'Referenced ticket was not found';
        return;
    }

    $Subject = $Self->_TicketSubjectReferenceRemove( Subject => $Subject );
    $Subject =~ s{\A\s+}{};
    $Subject =~ s{\s+\z}{};
    $Subject ||= 'Re: ' . ( $Ticket->{ticket_number} || $TicketID );

    if ( length $Subject > 500 ) {
        $Subject = substr $Subject, 0, 500;
    }

    $Self->{DB}->BeginWork() || do {
        $Self->{LastError} = $Self->{DB}->Error() || 'Transaction could not be started';
        return;
    };

    my $ArticleID = $Self->ArticleCreate(
        TicketID        => $TicketID,
        Subject         => $Subject,
        Body            => $Body,
        Channel         => 'email',
        SenderType      => 'customer',
        FromName        => $FromName,
        FromEmail       => $FromEmail,
        ToName          => $ToName,
        ToEmail         => $ToEmail,
        ContentType     => $ContentType,
        Visibility      => 'both',
        SkipTicketAccessCheck => 1,
        SkipNotification => 1,
        CreatedByUserID => $CreatedByUserID,
        ChangedByUserID => $ChangedByUserID,
        Attachments     => $Attachments,
    );

    if (!$ArticleID) {
        $Self->{LastError} ||= 'Reply article could not be created';
        $Self->{DB}->Rollback();
        return;
    }

    if ( !$Self->{DB}->Commit() ) {
        $Self->{LastError} = $Self->{DB}->Error() || 'Ticket reply transaction could not be committed';
        $Self->{DB}->Rollback();
        return;
    }

    $Self->_AgentNotificationSend(
        NotificationType => 'customer_reply_in_my_queues',
        TicketID         => $TicketID,
        ChangedByUserID  => $ChangedByUserID,
    );

    $Self->{LastEmailImportAction}   = 'updated';
    $Self->{LastEmailImportTicketID} = $TicketID;

    return $TicketID;
}

sub TicketCreateFromCustomer {
    my ( $Self, %Param ) = @_;

    my $User        = $Param{User} || {};
    my $QueueID     = $Param{QueueID} || 0;
    my $Title       = $Param{Title} || '';
    my $Body        = $Param{Body} || '';
    my $ContentType = $Param{ContentType} || 'text/plain';
    my $CustomerAccess = $Self->_CustomerAccessData( User => $User );

    if (!$CustomerAccess) {
        $Self->{LastError} = 'Customer user is required';
        return;
    }

    if ( $QueueID !~ m{\A\d+\z} || !$QueueID ) {
        $Self->{LastError} = 'Valid QueueID is required';
        return;
    }

    my $Queue = $Self->{DB}->SelectRow(
        'SELECT id, system_email_id
         FROM ticket_queue
         WHERE id = ?
            AND active = 1
         LIMIT 1',
        $QueueID,
    );

    if (!$Queue) {
        $Self->{LastError} = 'Queue was not found';
        return;
    }

    if ( $Self->{Permission} ) {
        my $Allowed = $Self->{Permission}->QueueAccessCheck(
            UserID     => $User->{user_account_id},
            QueueID    => $QueueID,
            Permission => 'ticket.create',
        );

        if (!$Allowed) {
            $Self->{LastError} = 'Queue access denied';
            return;
        }
    }

    $Title =~ s{\A\s+}{};
    $Title =~ s{\s+\z}{};
    $Body  =~ s{\A\s+}{};
    $Body  =~ s{\s+\z}{};

    if (!$Title || !$Body) {
        $Self->{LastError} = 'Subject and message are required';
        return;
    }

    if ( length $Title > 500 ) {
        $Title = substr $Title, 0, 500;
    }

    my $StateID = $Self->_DefaultStateID();
    return if !$StateID;

    my $PriorityID = $Self->_DefaultPriorityID();
    return if !$PriorityID;

    my $TicketNumber = $Self->_TicketNumberCreate();
    if (!$TicketNumber) {
        $Self->{LastError} ||= 'Ticket number could not be created';
        return;
    }

    my ( $ToName, $ToEmail ) = $Self->_QueueAddress( QueueID => $QueueID );
    my $FromName  = $Self->_UserName(
        Firstname => $User->{firstname},
        Lastname  => $User->{lastname},
        Login     => $User->{login},
    );
    my $FromEmail = $User->{email} || '';
    my $UserID    = $User->{user_account_id} || 1;

    $Self->{DB}->BeginWork() || do {
        $Self->{LastError} = $Self->{DB}->Error() || 'Transaction could not be started';
        return;
    };

    my $TicketResult = $Self->{DB}->Do(
        'INSERT INTO ticket (
            ticket_number,
            title,
            queue_id,
            state_id,
            priority_id,
            customer_id,
            customer_user_id,
            owner_user_id,
            responsible_user_id,
            created_by_user_id,
            changed_by_user_id,
            created_at,
            changed_at
        ) VALUES (
            ?, ?, ?, ?, ?, ?, ?, NULL, NULL, ?, ?, NOW(), NOW()
        )',
        $TicketNumber,
        $Title,
        $QueueID,
        $StateID,
        $PriorityID,
        $CustomerAccess->{customer_id},
        $CustomerAccess->{customer_user_id},
        $UserID,
        $UserID,
    );

    if (!$TicketResult) {
        $Self->{LastError} = $Self->{DB}->Error() || 'Ticket could not be created';
        $Self->{DB}->Rollback();
        return;
    }

    my $TicketID = $Self->{DB}->LastInsertID('ticket');
    if (!$TicketID) {
        $Self->{LastError} = 'Ticket ID could not be loaded';
        $Self->{DB}->Rollback();
        return;
    }

    my $ArticleID = $Self->ArticleCreate(
        TicketID        => $TicketID,
        User            => $User,
        Subject         => $Title,
        Body            => $Body,
        Channel         => 'web',
        SenderType      => 'customer',
        FromName        => $FromName,
        FromEmail       => $FromEmail,
        ToName          => $ToName,
        ToEmail         => $ToEmail,
        ContentType     => $ContentType,
        Visibility      => 'both',
        SkipTicketAccessCheck => 1,
        SkipNotification => 1,
        CreatedByUserID => $UserID,
        ChangedByUserID => $UserID,
    );

    if (!$ArticleID) {
        $Self->{LastError} ||= 'Initial article could not be created';
        $Self->{DB}->Rollback();
        return;
    }

    if ( !$Self->{DB}->Commit() ) {
        $Self->{LastError} = $Self->{DB}->Error() || 'Ticket transaction could not be committed';
        $Self->{DB}->Rollback();
        return;
    }

    $Self->_AgentNotificationSend(
        NotificationType => 'ticket_new_in_my_queues',
        TicketID         => $TicketID,
        ChangedByUserID  => $UserID,
    );

    return $TicketID;
}



sub TicketCreateFromAgent {
    my ( $Self, %Param ) = @_;

    my $User              = $Param{User} || {};
    my $QueueID           = $Param{QueueID} || 0;
    my $ServiceID         = $Param{ServiceID} || 0;
    my $CustomerUserID    = $Param{CustomerUserID} || 0;
    my $OwnerUserID       = $Param{OwnerUserID} || 0;
    my $ResponsibleUserID = $Param{ResponsibleUserID} || 0;
    my $Title             = $Param{Title} || '';
    my $Body              = $Param{Body} || '';
    my $ContentType       = $Param{ContentType} || 'text/html';
    my $Cc                = $Param{Cc} || '';
    my $StateID           = $Param{StateID} || 0;
    my $PriorityID        = $Param{PriorityID} || 0;
    my $PendingUntilRaw   = $Param{PendingUntil} || '';
    my $SendEmail         = $Param{SendEmail} ? 1 : 0;
    my $Attachments       = ref $Param{Attachments} eq 'ARRAY' ? $Param{Attachments} : [];
    my $DynamicFieldRequest = ref $Param{DynamicFieldRequest} eq 'HASH' ? $Param{DynamicFieldRequest} : {};
    my $Language            = $Param{Language} || $Self->{Config}->{Language}->{Default} || 'en';
    my $UserID              = $User->{user_account_id} || 0;

    if ( $UserID !~ m{\A\d+\z} || !$UserID || ( $User->{account_type} || '' ) ne 'agent' ) {
        $Self->{LastError} = 'Valid agent user is required';
        return;
    }

    if ( $QueueID !~ m{\A\d+\z} || !$QueueID ) {
        $Self->{LastError} = 'Translate:AgentTicketCreateQueueRequired';
        return;
    }

    if ( $CustomerUserID !~ m{\A\d+\z} || !$CustomerUserID ) {
        $Self->{LastError} = 'Translate:AgentTicketCreateCustomerUserRequired';
        return;
    }

    $Title =~ s{\A\s+|\s+\z}{}g;
    $Body  =~ s{\A\s+|\s+\z}{}g;

    if ( !$Title ) {
        $Self->{LastError} = 'Translate:AgentTicketCreateSubjectRequired';
        return;
    }

    if ( !$Self->_BodyHasVisibleContent( Body => $Body ) ) {
        $Self->{LastError} = 'Translate:AgentTicketCreateBodyRequired';
        return;
    }

    if ( $ContentType eq 'text/html' ) {
        $Body = QisutuHTML->Sanitize($Body);
    }
    else {
        $ContentType = 'text/plain';
    }

    if ( length $Title > 500 ) {
        $Title = substr $Title, 0, 500;
    }

    my $AttachmentValidation = $Self->_AttachmentsValidate( Attachments => $Attachments );
    if ( !$AttachmentValidation->{Valid} ) {
        $Self->{LastError} = $AttachmentValidation->{Error} || 'Attachment exceeds the permitted maximum size';
        return;
    }

    my $Queue = $Self->{DB}->SelectRow(
        'SELECT
            q.id,
            q.full_name,
            se.name AS system_email_name,
            se.email AS system_email_address
         FROM ticket_queue q
         LEFT JOIN system_email se
            ON se.id = q.system_email_id
           AND se.active = 1
         WHERE q.id = ?
           AND q.active = 1
         LIMIT 1',
        $QueueID,
    );

    if ( !$Queue ) {
        $Self->{LastError} = 'Translate:AgentTicketCreateQueueInvalid';
        return;
    }

    if ( $Self->{Permission} ) {
        my $Allowed = $Self->{Permission}->QueueAccessCheck(
            UserID     => $UserID,
            QueueID    => $QueueID,
            Permission => 'ticket.create',
        );

        if ( !$Allowed ) {
            $Self->{LastError} = 'Queue access denied';
            return;
        }
    }

    my $CustomerUser = $Self->{DB}->SelectRow(
        'SELECT
            cu.id,
            cu.customer_id,
            ua.login,
            ua.email,
            ua.firstname,
            ua.lastname
         FROM customer_user cu
         INNER JOIN customer c
            ON c.id = cu.customer_id
         INNER JOIN user_account ua
            ON ua.id = cu.user_account_id
         WHERE cu.id = ?
           AND cu.active = 1
           AND c.active = 1
           AND ua.is_active = 1
           AND ua.account_type = ?
         LIMIT 1',
        $CustomerUserID,
        'customer',
    );

    if ( !$CustomerUser ) {
        $Self->{LastError} = 'Translate:AgentTicketCreateCustomerUserInvalid';
        return;
    }

    if ( $SendEmail && !( $CustomerUser->{email} || '' ) ) {
        $Self->{LastError} = 'Translate:AgentTicketCreateCustomerUserEmailMissing';
        return;
    }

    my $SLASnapshot = {
        service_id            => undef,
        sla_id                => undef,
        sla_source            => 'queue',
        assignment_source     => 'queue',
        sla_name              => undef,
        calendar_id           => undef,
        update_mode           => 'customer_response',
        first_response_minutes => 0,
        update_minutes         => 0,
        solution_minutes       => 0,
    };

    if ($ServiceID) {
        if ( $ServiceID !~ m{\A\d+\z} ) {
            $Self->{LastError} = 'Translate:TicketServiceNotAvailable';
            return;
        }

        my $ServiceObject = QisutuService->new(
            Config => $Self->{Config},
            DB     => $Self->{DB},
        );
        my $Resolved = $ServiceObject->SLAResolve(
            CustomerID => $CustomerUser->{customer_id},
            ServiceID  => $ServiceID,
        );

        if ( !$Resolved ) {
            $Self->{LastError} = $ServiceObject->Error() || 'Translate:TicketServiceNotAvailable';
            return;
        }

        $SLASnapshot = {
            service_id             => $Resolved->{service_id},
            sla_id                 => $Resolved->{sla_id},
            sla_source             => 'sla',
            assignment_source      => $Resolved->{assignment_source} || 'default',
            sla_name               => $Resolved->{sla_name},
            calendar_id            => $Resolved->{calendar_id},
            update_mode            => $Resolved->{update_mode} || 'customer_response',
            first_response_minutes => $Resolved->{first_response_minutes} || 0,
            update_minutes         => $Resolved->{update_minutes} || 0,
            solution_minutes       => $Resolved->{solution_minutes} || 0,
        };
    }

    $OwnerUserID ||= $UserID;

    for my $AgentCheck (
        [ 'OwnerUserID',       $OwnerUserID,       'Translate:AgentTicketCreateOwnerInvalid' ],
        [ 'ResponsibleUserID', $ResponsibleUserID, 'Translate:AgentTicketCreateResponsibleInvalid' ],
    ) {
        my ( $Name, $AgentID, $Error ) = @{$AgentCheck};
        next if !$AgentID && $Name eq 'ResponsibleUserID';

        if ( $AgentID !~ m{\A\d+\z} || !$AgentID ) {
            $Self->{LastError} = $Error;
            return;
        }

        my $Agent = $Self->{DB}->SelectRow(
            'SELECT id
             FROM user_account
             WHERE id = ?
               AND account_type = ?
               AND is_active = 1
               AND is_system_user = 0
             LIMIT 1',
            $AgentID,
            'agent',
        );

        if ( !$Agent ) {
            $Self->{LastError} = $Error;
            return;
        }
    }

    my $State = $Self->{DB}->SelectRow(
        'SELECT id, state_type, sla_pause
         FROM ticket_state
         WHERE id = ?
           AND active = 1
         LIMIT 1',
        $StateID,
    );

    if ( !$State ) {
        $Self->{LastError} = 'Translate:AgentTicketCreateStateInvalid';
        return;
    }

    my $PendingUntil;
    if ( ( $State->{state_type} || '' ) eq 'pending' ) {
        $PendingUntil = $Self->_DateTimeInputNormalize($PendingUntilRaw);

        if ( !$PendingUntil ) {
            $Self->{LastError} = 'Translate:TicketPendingUntilRequired';
            return;
        }

        my $Now = $Self->_NowDateTime();
        if ( $Now && $PendingUntil le $Now ) {
            $Self->{LastError} = 'Translate:TicketPendingUntilFutureRequired';
            return;
        }
    }

    my $Priority = $Self->{DB}->SelectRow(
        'SELECT id
         FROM ticket_priority
         WHERE id = ?
           AND active = 1
         LIMIT 1',
        $PriorityID,
    );

    if ( !$Priority ) {
        $Self->{LastError} = 'Translate:AgentTicketCreatePriorityInvalid';
        return;
    }

    my $DynamicFieldObject = QisutuDynamicField->new(
        Config => $Self->{Config},
        DB     => $Self->{DB},
    );

    if ( !$DynamicFieldObject->TicketValueValidate(
        QueueID  => $QueueID,
        Request  => $DynamicFieldRequest,
        Language => $Language,
    ) ) {
        $Self->{LastError} = $DynamicFieldObject->Error() || 'Translate:TicketDynamicFieldInvalid';
        return;
    }

    my $FromName = $Queue->{system_email_name} || $Self->_UserName(
        Firstname => $User->{firstname},
        Lastname  => $User->{lastname},
        Login     => $User->{login},
    );
    my $FromEmail = $Queue->{system_email_address} || $User->{email} || '';
    my $ToName    = $Self->_UserName(
        Firstname => $CustomerUser->{firstname},
        Lastname  => $CustomerUser->{lastname},
        Login     => $CustomerUser->{login},
    );
    my $ToEmail = $CustomerUser->{email} || '';

    my $SMTPAccount;

    if ($SendEmail) {
        if ( !$FromEmail ) {
            $Self->{LastError} = 'Translate:TicketArticleSenderRequired';
            return;
        }

        $SMTPAccount = $Self->{DB}->SelectRow(
            'SELECT *
             FROM smtp_account
             WHERE active = 1
             ORDER BY sort_order ASC, id ASC
             LIMIT 1'
        );

        if ( !$SMTPAccount ) {
            $Self->{LastError} = 'Translate:TicketArticleSMTPRequired';
            return;
        }

        my $MailLoaded = eval {
            require QisutuMail;
            1;
        };

        if ( !$MailLoaded ) {
            $Self->{LastError} = 'Translate:AgentTicketCreateMailFailed';
            return;
        }
    }

    my $TicketNumber = $Self->_TicketNumberCreate();
    if ( !$TicketNumber ) {
        $Self->{LastError} ||= 'Ticket number could not be created';
        return;
    }

    $Self->{DB}->BeginWork() || do {
        $Self->{LastError} = $Self->{DB}->Error() || 'Transaction could not be started';
        return;
    };

    my $TicketResult = $Self->{DB}->Do(
        'INSERT INTO ticket (
            ticket_number,
            title,
            queue_id,
            state_id,
            priority_id,
            customer_id,
            customer_user_id,
            owner_user_id,
            responsible_user_id,
            service_id,
            sla_id,
            sla_source,
            sla_assignment_source,
            sla_name_snapshot,
            sla_calendar_id,
            sla_update_mode,
            sla_first_response_minutes,
            sla_update_minutes,
            sla_solution_minutes,
            pending_started_at,
            pending_until,
            sla_pause_started_at,
            solution_at,
            created_by_user_id,
            changed_by_user_id,
            created_at,
            changed_at
        ) VALUES (
            ?, ?, ?, ?, ?, ?, ?, ?, ?,
            ?, ?, ?, ?, ?, ?, ?, ?, ?, ?,
            CASE WHEN ? = "pending" THEN NOW() ELSE NULL END,
            ?,
            CASE WHEN ? = 1 THEN NOW() ELSE NULL END,
            CASE WHEN ? = "closed" THEN NOW() ELSE NULL END,
            ?, ?, NOW(), NOW()
        )',
        $TicketNumber,
        $Title,
        $QueueID,
        $StateID,
        $PriorityID,
        $CustomerUser->{customer_id},
        $CustomerUserID,
        $OwnerUserID,
        $ResponsibleUserID || undef,
        $SLASnapshot->{service_id},
        $SLASnapshot->{sla_id},
        $SLASnapshot->{sla_source},
        $SLASnapshot->{assignment_source},
        $SLASnapshot->{sla_name},
        $SLASnapshot->{calendar_id},
        $SLASnapshot->{update_mode},
        $SLASnapshot->{first_response_minutes},
        $SLASnapshot->{update_minutes},
        $SLASnapshot->{solution_minutes},
        $State->{state_type} || '',
        $PendingUntil,
        $State->{sla_pause} ? 1 : 0,
        $State->{state_type} || '',
        $UserID,
        $UserID,
    );

    if ( !$TicketResult ) {
        $Self->{LastError} = $Self->{DB}->Error() || 'Translate:TicketCreateFailed';
        $Self->{DB}->Rollback();
        return;
    }

    my $TicketID = $Self->{DB}->LastInsertID('ticket');
    if ( !$TicketID ) {
        $Self->{LastError} = 'Ticket ID could not be loaded';
        $Self->{DB}->Rollback();
        return;
    }

    if ( !$DynamicFieldObject->TicketValueSave(
        TicketID        => $TicketID,
        QueueID         => $QueueID,
        Request         => $DynamicFieldRequest,
        Language        => $Language,
        ChangedByUserID => $UserID,
    ) ) {
        $Self->{LastError} = $DynamicFieldObject->Error() || 'Translate:TicketDynamicFieldSaveFailed';
        $Self->{DB}->Rollback();
        return;
    }

    my $ArticleID = $Self->ArticleCreate(
        TicketID             => $TicketID,
        User                 => $User,
        Subject              => $Title,
        Body                 => $Body,
        Channel              => $SendEmail ? 'email' : 'web',
        SenderType           => 'agent',
        FromName             => $FromName,
        FromEmail            => $FromEmail,
        ToName               => $ToName,
        ToEmail              => $ToEmail,
        Cc                   => $Cc,
        ContentType          => $ContentType,
        Visibility           => 'both',
        SkipTicketAccessCheck => 1,
        SkipNotification      => 1,
        CreatedByUserID      => $UserID,
        ChangedByUserID      => $UserID,
        Attachments          => $Attachments,
    );

    if ( !$ArticleID ) {
        $Self->{LastError} ||= 'Translate:TicketArticleCreateFailed';
        $Self->{DB}->Rollback();
        return;
    }

    if ($SendEmail) {
        my $MailSubject = $Self->TicketSubjectBuild(
            TicketID => $TicketID,
            Subject  => $Title,
        );

        my $MailResult = QisutuMail->new(
            Config => $Self->{Config},
            DB     => $Self->{DB},
        )->SMTPSend(
            Account     => $SMTPAccount,
            FromName    => $FromName,
            FromEmail   => $FromEmail,
            ToName      => $ToName,
            ToEmail     => $ToEmail,
            Cc          => $Cc,
            Subject     => $MailSubject,
            Body        => $Body,
            Attachments => $Attachments,
        );

        if ( !$MailResult || !$MailResult->{Success} ) {
            $Self->{LastError} = $MailResult && $MailResult->{Message}
                ? $MailResult->{Message}
                : 'Translate:AgentTicketCreateMailFailed';
            $Self->{DB}->Rollback();
            return;
        }
    }

    if ( !$Self->{DB}->Commit() ) {
        $Self->{LastError} = $Self->{DB}->Error() || 'Ticket transaction could not be committed';
        $Self->{DB}->Rollback();
        return;
    }

    $Self->_AgentNotificationSend(
        NotificationType => 'ticket_new_in_my_queues',
        TicketID         => $TicketID,
        ChangedByUserID  => $UserID,
    );

    return $TicketID;
}

sub _BodyHasVisibleContent {
    my ( $Self, %Param ) = @_;

    my $Body = $Param{Body} || '';

    $Body =~ s{<div\b[^>]*class=["'][^"']*\bqisutu-mail-signature\b[^"']*["'][^>]*>.*\z}{}gis;
    $Body =~ s{\A\s*<div\b[^>]*class=["'][^"']*\bqisutu-mail-salutation\b[^"']*["'][^>]*>.*?</div>}{}gis;
    $Body =~ s{<style\b[^>]*>.*?</style>}{}gis;
    $Body =~ s{<script\b[^>]*>.*?</script>}{}gis;
    $Body =~ s{<[^>]+>}{}g;
    $Body =~ s{&nbsp;}{ }gi;
    $Body =~ s{&#160;}{ }g;
    $Body =~ s{\s+}{ }g;
    $Body =~ s{\A\s+|\s+\z}{}g;

    return $Body ? 1 : 0;
}

sub TicketSubjectBuild {
    my ( $Self, %Param ) = @_;

    my $Subject      = $Param{Subject} || '';
    my $TicketID     = $Param{TicketID} || 0;
    my $TicketNumber = $Param{TicketNumber} || '';

    if ( !$TicketNumber && $TicketID ) {
        my $Ticket = $Self->{DB}->SelectRow(
            'SELECT ticket_number
             FROM ticket
             WHERE id = ?
             LIMIT 1',
            $TicketID,
        );
        $TicketNumber = $Ticket->{ticket_number} if $Ticket;
    }

    return $Subject if !$TicketNumber;

    my $Hook = $Self->_TicketHook();
    $Subject = $Self->_TicketSubjectReferenceRemove( Subject => $Subject );
    $Subject =~ s{\r|\n}{ }g;
    $Subject =~ s{\s+}{ }g;
    $Subject =~ s{\A\s+|\s+\z}{}g;
    $Subject ||= $TicketNumber;

    my $Prefix = '[' . $Hook . '#' . $TicketNumber . ']';
    my $FullSubject = $Prefix . ' ' . $Subject;

    if ( length $FullSubject > 500 ) {
        $FullSubject = substr $FullSubject, 0, 500;
    }

    return $FullSubject;
}

sub LastEmailImportAction {
    my ($Self) = @_;

    return $Self->{LastEmailImportAction} || '';
}

sub LastEmailImportTicketID {
    my ($Self) = @_;

    return $Self->{LastEmailImportTicketID} || 0;
}

sub _TicketIDFromSubject {
    my ( $Self, %Param ) = @_;

    my $Subject = $Param{Subject} || '';
    return if !$Subject;

    my $TicketNumber = $Self->_TicketNumberFromSubject( Subject => $Subject );
    return if !$TicketNumber;

    my $Ticket = $Self->{DB}->SelectRow(
        'SELECT id
         FROM ticket
         WHERE ticket_number = ?
         LIMIT 1',
        $TicketNumber,
    );

    return if !$Ticket;

    return $Ticket->{id};
}

sub _TicketNumberFromSubject {
    my ( $Self, %Param ) = @_;

    my $Subject = $Param{Subject} || '';
    return '' if !$Subject;

    my $Hook = $Self->_TicketHook();
    my $HookQuoted = quotemeta($Hook);

    if ( $Hook && $Subject =~ m{\[\s*$HookQuoted\s*(?:\#|:|-|\s)+\s*(\d{6,30})\s*\]}i ) {
        return $1;
    }

    if ( $Hook && $Subject =~ m{\b$HookQuoted\s*(?:\#|:|-|\s)+\s*(\d{6,30})\b}i ) {
        return $1;
    }

    if ( $Subject =~ m{\[[^\]]*\#\s*(\d{6,30})\s*\]} ) {
        return $1;
    }

    if ( $Subject =~ m{\bTicket\s*(?:\#|:|-|\s)+\s*(\d{6,30})\b}i ) {
        return $1;
    }

    if ( $Subject =~ m{\b(\d{10,30})\b} ) {
        return $1;
    }

    return '';
}

sub _TicketSubjectReferenceRemove {
    my ( $Self, %Param ) = @_;

    my $Subject = $Param{Subject} || '';
    my $Hook = $Self->_TicketHook();
    my $HookQuoted = quotemeta($Hook);

    if ($Hook) {
        $Subject =~ s{\[\s*$HookQuoted\s*(?:\#|:|-|\s)+\s*\d{6,30}\s*\]\s*}{}gi;
        $Subject =~ s{\b$HookQuoted\s*(?:\#|:|-|\s)+\s*\d{6,30}\b\s*}{}gi;
    }

    $Subject =~ s{\[[^\]]*\#\s*\d{6,30}\s*\]\s*}{}g;
    $Subject =~ s{\bTicket\s*(?:\#|:|-|\s)+\s*\d{6,30}\b\s*}{}gi;
    $Subject =~ s{\s+}{ }g;
    $Subject =~ s{\A\s+|\s+\z}{}g;

    return $Subject;
}

sub _TicketHook {
    my ($Self) = @_;

    my $Hook = '';

    if ( $Self->{DB} ) {
        my $OK = eval {
            my $SettingObject = QisutuSystemSetting->new(
                Config => $Self->{Config},
                DB     => $Self->{DB},
            );
            $Hook = $SettingObject->Get( Key => 'system.ticket_hook', Default => 'Qisutu' ) || '';
            1;
        };

        if (!$OK) {
            $Hook = '';
        }
    }

    $Hook ||= $Self->{Config}->{System}->{TicketHook} || 'Qisutu';
    $Hook =~ s{\r|\n}{ }g;
    $Hook =~ s{[\[\]\#<>]}{}g;
    $Hook =~ s{\s+}{ }g;
    $Hook =~ s{\A\s+|\s+\z}{}g;
    $Hook ||= 'Qisutu';

    return $Hook;
}


sub CustomerQueueList {
    my ( $Self, %Param ) = @_;

    my $User      = $Param{User} || {};
    my $QueueRule = $Self->_CustomerQueueRuleHash(
        User       => $User,
        Permission => 'ticket.create',
    );
    my @QueueIDs = sort { $a <=> $b } keys %{$QueueRule};

    return [] if !@QueueIDs;

    my $Placeholder = join ', ', map {'?'} @QueueIDs;
    my $Rows = $Self->{DB}->SelectAll(
        'SELECT id, name, full_name
         FROM ticket_queue
         WHERE active = 1
            AND id IN (' . $Placeholder . ')
         ORDER BY sort_order ASC, full_name ASC, name ASC, id ASC',
        @QueueIDs,
    );

    if (!$Rows) {
        $Self->{LastError} = $Self->{DB}->Error() || 'Queue list could not be loaded';
        return [];
    }

    return $Rows;
}

sub ArticleList {
    my ( $Self, %Param ) = @_;

    my $TicketID = $Param{TicketID} || 0;
    my $Limit    = $Param{Limit}    || 100;
    my $User     = $Param{User}     || {};
    my $Language = $Param{Language} || 'en';

    if ( $TicketID !~ m{\A\d+\z} ) {
        $Self->{LastError} = 'Valid TicketID is required';
        return [];
    }

    my $Ticket = $Self->TicketGet(
        TicketID => $TicketID,
        User     => $User,
    );

    if ( !$Ticket ) {
        $Self->{LastError} ||= 'Ticket access denied';
        return [];
    }

    if ( $Limit !~ m{\A\d+\z} ) {
        $Limit = 100;
    }

    if ( $Limit < 1 ) {
        $Limit = 1;
    }

    if ( $Limit > 500 ) {
        $Limit = 500;
    }

    my $IsCustomerView = $Self->_CustomerAccessData( User => $User ) ? 1 : 0;
    my $VisibilitySQL  = $Self->_TicketArticleVisibilityColumnExists()
        ? 'a.visibility,'
        : "'' AS visibility,";

    my $Rows = $Self->{DB}->SelectAll(
        'SELECT
            a.id,
            a.ticket_id,
            a.article_number,
            a.channel,
            a.sender_type,
            a.from_name,
            a.from_email,
            a.to_name,
            a.to_email,
            a.cc,
            a.subject,
            a.body,
            a.content_type,
            ' . $VisibilitySQL . '
            a.internal,
            a.created_at,
            a.changed_at,
            created_account.login AS created_by_login,
            created_account.firstname AS created_by_firstname,
            created_account.lastname AS created_by_lastname,
            changed_account.login AS changed_by_login,
            changed_account.firstname AS changed_by_firstname,
            changed_account.lastname AS changed_by_lastname
         FROM ticket_article a
         LEFT JOIN user_account created_account ON created_account.id = a.created_by_user_id
         LEFT JOIN user_account changed_account ON changed_account.id = a.changed_by_user_id
         WHERE a.ticket_id = ?
         ORDER BY a.created_at ASC, a.id ASC
         LIMIT ' . $Limit,
        $TicketID
    );

    if ( !$Rows ) {
        $Self->{LastError} = $Self->{DB}->Error() || 'Article list could not be loaded';
        return [];
    }

    my @Articles;

    for my $Article ( @{$Rows} ) {
        $Article->{article_number} ||= '';
        $Article->{channel}        ||= '';
        $Article->{sender_type}    ||= '';
        $Article->{from_name}      ||= '';
        $Article->{from_email}     ||= '';
        $Article->{to_name}        ||= '';
        $Article->{to_email}       ||= '';
        $Article->{cc}             ||= '';
        $Article->{subject}        ||= '';
        $Article->{body}           ||= '';
        $Article->{content_type}   ||= 'text/plain';

        $Article->{visibility} = $Self->_ArticleVisibilityNormalize(
            Visibility => $Article->{visibility},
            Internal   => $Article->{internal},
            SenderType => $Article->{sender_type},
        );

        if ($IsCustomerView) {
            next if $Article->{visibility} eq 'agent';
        }
        else {
            next if $Article->{visibility} eq 'customer';
        }

        $Article->{created_by_name} = $Self->_UserName(
            Firstname => $Article->{created_by_firstname},
            Lastname  => $Article->{created_by_lastname},
            Login     => $Article->{created_by_login},
        );

        $Article->{changed_by_name} = $Self->_UserName(
            Firstname => $Article->{changed_by_firstname},
            Lastname  => $Article->{changed_by_lastname},
            Login     => $Article->{changed_by_login},
        );

        $Article->{created_by_name} ||= '-';
        $Article->{changed_by_name} ||= '-';
        $Article->{body_html}       = $Article->{content_type} eq 'text/html'
            ? QisutuHTML->Sanitize( $Article->{body} )
            : QisutuHTML->PlainTextToHTML( $Article->{body} );
        $Article->{attachments}       = [];
        $Article->{has_attachments}   = 0;
        $Article->{attachments_html}  = '';

        $Article->{sender_address_name} = $Article->{from_name} || $Article->{from_email} || '-';
        $Article->{sender_name} = $Self->_ArticleSenderDisplayName(
            SenderType    => $Article->{sender_type},
            Channel       => $Article->{channel},
            FromName      => $Article->{from_name},
            FromEmail     => $Article->{from_email},
            CreatedByName => $Article->{created_by_name},
        );
        $Article->{recipient} = $Article->{to_name} || $Article->{to_email} || '-';

        $Article->{visibility_label} = 'Translate:TicketArticleVisibilityBoth';
        if ( $Article->{visibility} eq 'agent' ) {
            $Article->{visibility_label} = 'Translate:TicketArticleVisibilityAgent';
        }
        elsif ( $Article->{visibility} eq 'customer' ) {
            $Article->{visibility_label} = 'Translate:TicketArticleVisibilityCustomer';
        }

        $Article->{sender_role_key} = $Self->_ArticleSenderRoleKey(
            SenderType => $Article->{sender_type},
            Channel    => $Article->{channel},
        );
        $Article->{sender_role_label} = 'Translate:' . $Article->{sender_role_key};
        $Article->{article_sender_class} = $Self->_ArticleSenderClass(
            SenderType => $Article->{sender_type},
            Visibility => $Article->{visibility},
        );
        $Article->{sender_initials} = $Self->_ArticleSenderInitials(
            SenderType => $Article->{sender_type},
            Channel    => $Article->{channel},
            Name       => $Article->{sender_name},
            Email      => $Article->{from_email},
        );

        push @Articles, $Article;
    }

    $Self->_ArticleAttachmentsAdd(
        Articles => \@Articles,
        Language => $Language,
    );

    return \@Articles;
}

sub _ArticleSenderDisplayName {
    my ( $Self, %Param ) = @_;

    my $SenderType    = lc( $Param{SenderType} || '' );
    my $Channel       = lc( $Param{Channel} || '' );
    my $FromName      = $Param{FromName} || '';
    my $FromEmail     = $Param{FromEmail} || '';
    my $CreatedByName = $Param{CreatedByName} || '';

    $FromName =~ s{\A\s+}{};
    $FromName =~ s{\s+\z}{};
    $CreatedByName =~ s{\A\s+}{};
    $CreatedByName =~ s{\s+\z}{};

    my $CreatedByIsUseful = $CreatedByName && $CreatedByName ne '-';
    my $FromNameIsUseful  = $FromName && $FromName ne '-' && lc($FromName) ne 'default';

    if ( $SenderType eq 'agent' ) {
        return $CreatedByName if $CreatedByIsUseful;
        return $FromName      if $FromNameIsUseful;
        return $FromEmail     if $FromEmail;
        return 'Agent';
    }

    if ( $SenderType eq 'customer' ) {
        return $FromName      if $FromNameIsUseful;
        return $FromEmail     if $FromEmail;
        return $CreatedByName if $CreatedByIsUseful;
        return 'Customer';
    }

    if ( $SenderType eq 'system' ) {
        return $FromName      if $FromNameIsUseful;
        return 'Qisutu';
    }

    if ( $Channel eq 'email' ) {
        return $FromName      if $FromNameIsUseful;
        return $FromEmail     if $FromEmail;
        return $CreatedByName if $CreatedByIsUseful;
        return 'E-mail';
    }

    return $CreatedByName if $CreatedByIsUseful;
    return $FromName      if $FromNameIsUseful;
    return $FromEmail     if $FromEmail;

    return '-';
}

sub _ArticleSenderInitials {
    my ( $Self, %Param ) = @_;

    my $SenderType = lc( $Param{SenderType} || '' );
    my $Channel    = lc( $Param{Channel} || '' );
    my $Name       = $Param{Name} || '';
    my $Email      = $Param{Email} || '';

    if ( !$Name || $Name eq '-' ) {
        return 'AG' if $SenderType eq 'agent';
        return 'CU' if $SenderType eq 'customer';
        return 'QS' if $SenderType eq 'system';
        return 'EM' if $Channel eq 'email';
    }

    return $Self->_Initials(
        Name  => $Name,
        Email => $Email,
    );
}

sub _ArticleSenderRoleKey {
    my ( $Self, %Param ) = @_;

    my $SenderType = lc( $Param{SenderType} || '' );
    my $Channel    = lc( $Param{Channel} || '' );

    return 'TicketArticleSenderCustomer' if $SenderType eq 'customer';
    return 'TicketArticleSenderAgent'    if $SenderType eq 'agent';
    return 'TicketArticleSenderSystem'   if $SenderType eq 'system';
    return 'TicketArticleSenderEmail'    if $Channel eq 'email';

    return 'TicketArticleSenderUnknown';
}

sub _ArticleSenderClass {
    my ( $Self, %Param ) = @_;

    my $SenderType = lc( $Param{SenderType} || '' );
    my $Visibility = lc( $Param{Visibility} || '' );

    return 'qisutu-ticket-article-from-customer' if $SenderType eq 'customer';
    return 'qisutu-ticket-article-from-agent qisutu-ticket-article-internal' if $SenderType eq 'agent' && $Visibility eq 'agent';
    return 'qisutu-ticket-article-from-agent' if $SenderType eq 'agent';
    return 'qisutu-ticket-article-from-system' if $SenderType eq 'system';

    return 'qisutu-ticket-article-from-mail';
}

sub _Initials {
    my ( $Self, %Param ) = @_;

    my $Name  = $Param{Name}  || '';
    my $Email = $Param{Email} || '';

    $Name =~ s{<[^>]+>}{}g;
    $Name =~ s{[^\p{L}\p{N}\s\-\.]}{ }g;
    $Name =~ s{\A\s+}{};
    $Name =~ s{\s+\z}{};

    my @Parts = grep {$_} split m{\s+}, $Name;
    my $Initials = '';

    if (@Parts >= 2) {
        $Initials = substr( $Parts[0], 0, 1 ) . substr( $Parts[-1], 0, 1 );
    }
    elsif (@Parts == 1) {
        $Initials = substr( $Parts[0], 0, 2 );
    }
    elsif ($Email) {
        my ($LocalPart) = split m{\@}, $Email;
        $Initials = substr( $LocalPart || '', 0, 2 );
    }

    $Initials = uc($Initials || '?');

    return $Initials;
}

sub _TicketChangeAllowed {
    my ( $Self, %Param ) = @_;

    my $Ticket = $Param{Ticket} || {};
    my $User   = $Param{User}   || {};

    return 1 if !$Self->{Permission};

    my $CustomerAccess = $Self->_CustomerAccessData( User => $User );

    if ($CustomerAccess) {
        return $Self->_CustomerTicketAccessCheck(
            Ticket         => $Ticket,
            CustomerAccess => $CustomerAccess,
            User           => $User,
            Permission     => 'ticket.view',
        );
    }

    return $Self->{Permission}->QueueAccessCheck(
        UserID     => $User->{user_account_id},
        QueueID    => $Ticket->{queue_id},
        Permission => 'ticket.edit',
    );
}

sub _CustomerTicketAccessCheck {
    my ( $Self, %Param ) = @_;

    my $Ticket         = $Param{Ticket} || {};
    my $CustomerAccess = $Param{CustomerAccess} || {};
    my $User           = $Param{User} || {};
    my $Permission     = $Param{Permission} || 'ticket.view';

    return if !$CustomerAccess->{customer_user_id};

    my $QueueRule = $Self->_CustomerQueueRuleHash(
        User       => $User,
        Permission => $Permission,
    );
    my $Rule = $QueueRule->{ $Ticket->{queue_id} || 0 } || '';

    return if !$Rule;

    return 1 if $Ticket->{customer_user_id}
        && $Ticket->{customer_user_id} == $CustomerAccess->{customer_user_id};

    return 1 if $Rule eq 'organization'
        && $Ticket->{customer_id}
        && $CustomerAccess->{customer_id}
        && $Ticket->{customer_id} == $CustomerAccess->{customer_id};

    return;
}

sub _CustomerQueueRuleHash {
    my ( $Self, %Param ) = @_;

    my $User       = $Param{User} || {};
    my $Permission = $Param{Permission} || 'ticket.view';
    my $UserID     = $User->{user_account_id} || 0;

    return {} if !$Self->{Permission};
    return {} if $UserID !~ m{\A\d+\z} || !$UserID;

    return $Self->{Permission}->CustomerQueueRuleHash(
        UserID     => $UserID,
        Permission => $Permission,
    );
}

sub _CustomerAccessData {
    my ( $Self, %Param ) = @_;

    my $User = $Param{User} || {};

    return if ( $User->{account_type} || '' ) eq 'agent';

    if ( $User->{customer_user_id} && $User->{customer_id} ) {
        return {
            customer_user_id => $User->{customer_user_id},
            customer_id      => $User->{customer_id},
        };
    }

    my $UserID = $User->{user_account_id} || 0;

    return if $UserID !~ m{\A\d+\z} || !$UserID;

    my $Row = $Self->{DB}->SelectRow(
        'SELECT
            cu.id AS customer_user_id,
            cu.customer_id
         FROM customer_user cu
         INNER JOIN customer c
            ON c.id = cu.customer_id
         WHERE cu.user_account_id = ?
            AND cu.active = 1
            AND c.active = 1
         LIMIT 1',
        $UserID,
    );

    return $Row || undef;
}

sub _ArticleVisibilityNormalize {
    my ( $Self, %Param ) = @_;

    my $Visibility = $Param{Visibility} || '';
    my $SenderType = $Param{SenderType} || '';

    $Visibility = lc $Visibility;
    $Visibility =~ s{\A\s+}{};
    $Visibility =~ s{\s+\z}{};

    $SenderType = lc $SenderType;
    $SenderType =~ s{\A\s+}{};
    $SenderType =~ s{\s+\z}{};

    if ( $SenderType eq 'customer' ) {
        return 'customer' if $Visibility eq 'customer';
        return 'both';
    }

    my $LegacyWithoutLoginWord = 'pub' . 'lic';

    if ( $Visibility eq $LegacyWithoutLoginWord || $Visibility eq 'external' ) {
        return 'both';
    }

    return $Visibility if $Visibility =~ m{\A(?:agent|customer|both)\z};

    return $Param{Internal} ? 'agent' : 'both';
}

sub _TicketArticleVisibilityColumnExists {
    my ($Self) = @_;

    return $Self->{TicketArticleVisibilityColumnExists}
        if defined $Self->{TicketArticleVisibilityColumnExists};

    my $Column = $Self->{DB}->SelectRow(
        'SELECT 1 AS column_exists
         FROM INFORMATION_SCHEMA.COLUMNS
         WHERE TABLE_SCHEMA = DATABASE()
           AND TABLE_NAME = ?
           AND COLUMN_NAME = ?
         LIMIT 1',
        'ticket_article',
        'visibility',
    );

    $Self->{TicketArticleVisibilityColumnExists} = $Column ? 1 : 0;

    return $Self->{TicketArticleVisibilityColumnExists};
}

sub _QueueAddress {
    my ( $Self, %Param ) = @_;

    my $QueueID = $Param{QueueID} || 0;

    return ( '', '' ) if $QueueID !~ m{\A\d+\z} || !$QueueID;

    my $Row = $Self->{DB}->SelectRow(
        'SELECT
            se.name,
            se.email
         FROM ticket_queue tq
         LEFT JOIN system_email se
            ON se.id = tq.system_email_id
            AND se.active = 1
         WHERE tq.id = ?
            AND tq.active = 1
         LIMIT 1',
        $QueueID,
    );

    return ( '', '' ) if !$Row;

    return ( $Row->{name} || '', $Row->{email} || '' );
}


sub ArticleAttachmentGet {
    my ( $Self, %Param ) = @_;

    my $AttachmentID = $Param{AttachmentID} || 0;
    my $User         = $Param{User} || {};

    if ( $AttachmentID !~ m{\A\d+\z} || !$AttachmentID ) {
        $Self->{LastError} = 'Valid AttachmentID is required';
        return;
    }

    if ( !$Self->_TicketArticleAttachmentTableExists() ) {
        $Self->{LastError} = 'Attachment table is missing';
        return;
    }

    my $Attachment = $Self->{DB}->SelectRow(
        'SELECT
            aa.id,
            aa.ticket_id,
            aa.article_id,
            aa.filename,
            aa.content_type,
            aa.content,
            aa.content_size,
            aa.content_id,
            aa.content_disposition,
            a.visibility,
            a.internal,
            a.sender_type
         FROM ticket_article_attachment aa
         INNER JOIN ticket_article a
            ON a.id = aa.article_id
         WHERE aa.id = ?
         LIMIT 1',
        $AttachmentID,
    );

    if ( !$Attachment ) {
        $Self->{LastError} = 'Attachment was not found';
        return;
    }

    my $Ticket = $Self->TicketGet(
        TicketID => $Attachment->{ticket_id},
        User     => $User,
    );

    if ( !$Ticket ) {
        $Self->{LastError} ||= 'Ticket access denied';
        return;
    }

    my $Visibility = $Self->_ArticleVisibilityNormalize(
        Visibility => $Attachment->{visibility},
        Internal   => $Attachment->{internal},
        SenderType => $Attachment->{sender_type},
    );

    my $IsCustomerView = $Self->_CustomerAccessData( User => $User ) ? 1 : 0;
    if ($IsCustomerView) {
        if ( $Visibility eq 'agent' ) {
            $Self->{LastError} = 'Attachment access denied';
            return;
        }
    }
    else {
        if ( $Visibility eq 'customer' ) {
            $Self->{LastError} = 'Attachment access denied';
            return;
        }
    }

    $Attachment->{filename}     ||= 'attachment.bin';
    $Attachment->{content_type} ||= 'application/octet-stream';
    $Attachment->{content_size} ||= length( $Attachment->{content} || '' );

    return $Attachment;
}

sub _ArticleAttachmentsCreate {
    my ( $Self, %Param ) = @_;

    my $TicketID        = $Param{TicketID} || 0;
    my $ArticleID       = $Param{ArticleID} || 0;
    my $Attachments     = ref $Param{Attachments} eq 'ARRAY' ? $Param{Attachments} : [];
    my $CreatedByUserID = $Param{CreatedByUserID} || 1;

    return 1 if !@{$Attachments};

    if ( !$Self->_TicketArticleAttachmentTableExists() ) {
        $Self->{LastError} = 'Attachment table ticket_article_attachment is missing';
        return;
    }

    for my $Attachment ( @{$Attachments} ) {
        next if ref $Attachment ne 'HASH';

        my $Content = $Attachment->{Content};
        next if !defined $Content || !length $Content;

        my $Filename = $Self->_AttachmentFilenameClean( $Attachment->{Filename} || 'attachment.bin' );
        my $MimeType = $Self->_AttachmentMimeTypeClean( $Attachment->{ContentType} || 'application/octet-stream' );
        my $Size     = $Attachment->{ContentSize} || length($Content);
        my $CID      = $Attachment->{ContentID} || '';
        my $Disposition = lc( $Attachment->{ContentDisposition} || 'attachment' );
        $Disposition = 'attachment' if $Disposition !~ m{\A(?:attachment|inline)\z};

        my $Inserted = $Self->{DB}->Do(
            'INSERT INTO ticket_article_attachment (
                ticket_id,
                article_id,
                filename,
                content_type,
                content,
                content_size,
                content_id,
                content_disposition,
                created_by_user_id,
                created_at
            ) VALUES (
                ?, ?, ?, ?, ?, ?, ?, ?, ?, NOW()
            )',
            $TicketID,
            $ArticleID,
            $Filename,
            $MimeType,
            $Content,
            $Size,
            $CID,
            $Disposition,
            $CreatedByUserID,
        );

        if ( !$Inserted ) {
            $Self->{LastError} = $Self->{DB}->Error() || 'Attachment could not be stored';
            return;
        }
    }

    return 1;
}

sub _ArticleAttachmentsAdd {
    my ( $Self, %Param ) = @_;

    my $Articles = ref $Param{Articles} eq 'ARRAY' ? $Param{Articles} : [];
    my $Language = $Param{Language} || 'en';

    return 1 if !@{$Articles};
    return 1 if !$Self->_TicketArticleAttachmentTableExists();

    my @ArticleIDs = map { $_->{id} } grep { $_->{id} && $_->{id} =~ m{\A\d+\z} } @{$Articles};
    return 1 if !@ArticleIDs;

    my $Placeholder = join ', ', map {'?'} @ArticleIDs;
    my $Rows = $Self->{DB}->SelectAll(
        'SELECT
            id,
            ticket_id,
            article_id,
            filename,
            content_type,
            content_size,
            content_disposition,
            created_at
         FROM ticket_article_attachment
         WHERE article_id IN (' . $Placeholder . ')
         ORDER BY id ASC',
        @ArticleIDs,
    );

    return 1 if !$Rows;

    my %ByArticleID;
    for my $Attachment ( @{$Rows} ) {
        $Attachment->{download_url} = 'index.pl?Page=TicketAttachmentDownload&AttachmentID=' . ( $Attachment->{id} || 0 );
        $Attachment->{size_display} = $Self->_FileSizeFormat( Size => $Attachment->{content_size} || 0, Language => $Language );
        push @{ $ByArticleID{ $Attachment->{article_id} || 0 } }, $Attachment;
    }

    for my $Article ( @{$Articles} ) {
        my $List = $ByArticleID{ $Article->{id} || 0 } || [];
        $Article->{attachments}      = $List;
        $Article->{has_attachments}  = @{$List} ? 1 : 0;
        $Article->{attachments_html} = $Self->_ArticleAttachmentsHTML(
            Attachments => $List,
            Language    => $Language,
        );
    }

    return 1;
}

sub _ArticleAttachmentsHTML {
    my ( $Self, %Param ) = @_;

    my $Attachments = ref $Param{Attachments} eq 'ARRAY' ? $Param{Attachments} : [];
    my $Language    = $Param{Language} || 'en';

    return '' if !@{$Attachments};

    my $Title = $Language eq 'de' ? 'Anhänge' : 'Attachments';
    my $Download = $Language eq 'de' ? 'Herunterladen' : 'Download';

    my $HTML = '<div class="qisutu-ticket-article-attachments">';
    $HTML .= '<strong>' . $Self->_HTMLEscape($Title) . '</strong>';
    $HTML .= '<ul>';

    for my $Attachment ( @{$Attachments} ) {
        my $Filename = $Attachment->{filename} || 'attachment.bin';
        my $Size     = $Attachment->{size_display} || '';
        my $URL      = $Attachment->{download_url} || '#';

        $HTML .= '<li>';
        $HTML .= '<a href="' . $Self->_HTMLEscape($URL) . '" download>' . $Self->_HTMLEscape($Filename) . '</a>';
        $HTML .= ' <span>(' . $Self->_HTMLEscape($Size) . ')</span>' if $Size;
        $HTML .= ' <em>' . $Self->_HTMLEscape($Download) . '</em>';
        $HTML .= '</li>';
    }

    $HTML .= '</ul></div>';

    return $HTML;
}

sub _TicketArticleAttachmentTableExists {
    my ($Self) = @_;

    return $Self->{TicketArticleAttachmentTableExists}
        if defined $Self->{TicketArticleAttachmentTableExists};

    my $Table = $Self->{DB}->SelectRow(
        'SELECT 1 AS table_exists
         FROM INFORMATION_SCHEMA.TABLES
         WHERE TABLE_SCHEMA = DATABASE()
           AND TABLE_NAME = ?
         LIMIT 1',
        'ticket_article_attachment',
    );

    $Self->{TicketArticleAttachmentTableExists} = $Table ? 1 : 0;

    return $Self->{TicketArticleAttachmentTableExists};
}

sub _AttachmentFilenameClean {
    my ( $Self, $Filename ) = @_;

    $Filename ||= 'attachment.bin';
    $Filename =~ s{\\}{/}g;
    $Filename =~ s{\A.*/}{}g;
    $Filename =~ s{[\r\n\x00"]}{}g;
    $Filename =~ s{\A\s+|\s+\z}{}g;
    $Filename ||= 'attachment.bin';

    if ( length $Filename > 180 ) {
        my $Extension = '';
        if ( $Filename =~ m{(\.[A-Za-z0-9]{1,12})\z} ) {
            $Extension = $1;
        }
        $Filename = substr( $Filename, 0, 180 - length($Extension) ) . $Extension;
    }

    return $Filename;
}

sub _AttachmentMimeTypeClean {
    my ( $Self, $MimeType ) = @_;

    $MimeType ||= 'application/octet-stream';
    $MimeType =~ s{[\r\n\x00]}{}g;
    $MimeType =~ s{;.*\z}{};
    $MimeType =~ s{\A\s+|\s+\z}{}g;
    $MimeType = lc $MimeType;
    $MimeType = 'application/octet-stream' if $MimeType !~ m{\A[a-z0-9!#$&.+\-^_]+/[a-z0-9!#$&.+\-^_]+\z};

    return $MimeType;
}

sub _FileSizeFormat {
    my ( $Self, %Param ) = @_;

    my $Size = $Param{Size} || 0;
    $Size = 0 if $Size !~ m{\A\d+\z};

    return $Size . ' B' if $Size < 1024;
    return sprintf '%.1f KB', $Size / 1024 if $Size < 1024 * 1024;
    return sprintf '%.1f MB', $Size / 1024 / 1024 if $Size < 1024 * 1024 * 1024;

    return sprintf '%.1f GB', $Size / 1024 / 1024 / 1024;
}

sub _HTMLEscape {
    my ( $Self, $Value ) = @_;

    $Value = '' if !defined $Value;
    $Value =~ s/&/&amp;/g;
    $Value =~ s/</&lt;/g;
    $Value =~ s/>/&gt;/g;
    $Value =~ s/"/&quot;/g;
    $Value =~ s/'/&#39;/g;

    return $Value;
}

sub ArticleCreate {
    my ( $Self, %Param ) = @_;

    my $TicketID        = $Param{TicketID}        || 0;
    my $User            = $Param{User}            || {};
    my $Subject         = $Param{Subject}         || '';
    my $Body            = $Param{Body}            || '';
    my $Channel         = $Param{Channel}         || 'note';
    my $SenderType      = $Param{SenderType}      || 'agent';
    my $FromName        = $Param{FromName}        || '';
    my $FromEmail       = $Param{FromEmail}       || '';
    my $ToName          = $Param{ToName}          || '';
    my $ToEmail         = $Param{ToEmail}         || '';
    my $Cc              = $Param{Cc}              || $Param{CC} || '';
    my $ContentType     = $Param{ContentType}     || 'text/plain';
    my $Visibility      = $Self->_ArticleVisibilityNormalize(
        Visibility => $Param{Visibility},
        Internal   => $Param{Internal},
        SenderType => $SenderType,
    );
    my $Internal        = $Visibility eq 'agent' ? 1 : 0;
    my $Language        = $Param{Language}        || 'en';
    my $CreatedByUserID = $Param{CreatedByUserID} || 0;
    my $ChangedByUserID = $Param{ChangedByUserID} || $CreatedByUserID;
    my $SkipTicketAccessCheck = $Param{SkipTicketAccessCheck} ? 1 : 0;
    my $SkipNotification      = $Param{SkipNotification} ? 1 : 0;
    my $Attachments           = ref $Param{Attachments} eq 'ARRAY' ? $Param{Attachments} : [];

    my $AttachmentValidation = $Self->_AttachmentsValidate( Attachments => $Attachments );
    if ( !$AttachmentValidation->{Valid} ) {
        $Self->{LastError} = $AttachmentValidation->{Error} || 'Attachment exceeds the permitted maximum size';
        return;
    }

    if ( $TicketID !~ m{\A\d+\z} || !$TicketID ) {
        $Self->{LastError} = 'Valid TicketID is required';
        return;
    }

    if ( $CreatedByUserID !~ m{\A\d+\z} || !$CreatedByUserID ) {
        $Self->{LastError} = 'Valid CreatedByUserID is required';
        return;
    }

    $Body =~ s{\A\s+}{};
    $Body =~ s{\s+\z}{};

    if ( $ContentType eq 'text/html' ) {
        $Body = QisutuHTML->Sanitize($Body);
    }
    else {
        $ContentType = 'text/plain';
    }

    if ( !$Body ) {
        $Self->{LastError} = 'Article body is required';
        return;
    }

    my $Ticket;

    if ( !$SkipTicketAccessCheck ) {
        $Ticket = $Self->TicketGet(
            TicketID => $TicketID,
            User     => $User,
        );
        if ( !$Ticket ) {
            $Self->{LastError} ||= 'Ticket not found';
            return;
        }

        if ( !$Self->_TicketChangeAllowed( Ticket => $Ticket, User => $User ) ) {
            $Self->{LastError} = 'Ticket change access denied';
            return;
        }
    }

    if ( !$Subject ) {
        if ( $Language eq 'de' ) {
            $Subject = 'Antwort zu ' . ( $Ticket ? ( $Ticket->{ticket_number} || $TicketID ) : $TicketID );
        }
        else {
            $Subject = 'Reply to ' . ( $Ticket ? ( $Ticket->{ticket_number} || $TicketID ) : $TicketID );
        }
    }

    if ( ( $Channel || '' ) eq 'email' && ( $SenderType || '' ) eq 'agent' ) {
        $Subject = $Self->TicketSubjectBuild(
            TicketID => $TicketID,
            Subject  => $Subject,
        );
    }

    my $NumberRow = $Self->{DB}->SelectRow(
        'SELECT COALESCE(MAX(article_number), 0) + 1 AS next_article_number
         FROM ticket_article
         WHERE ticket_id = ?',
        $TicketID,
    );

    if ( !$NumberRow ) {
        $Self->{LastError} = $Self->{DB}->Error() || 'Article number could not be created';
        return;
    }

    my $ArticleNumber = $NumberRow->{next_article_number} || 1;

    my $VisibilityColumn = $Self->_TicketArticleVisibilityColumnExists();
    my $VisibilitySQL    = $VisibilityColumn ? "\n            visibility," : '';
    my $VisibilityMark   = $VisibilityColumn ? '?, ' : '';
    my @VisibilityBind   = $VisibilityColumn ? ($Visibility) : ();

    my $Result = $Self->{DB}->Do(
        'INSERT INTO ticket_article (
            ticket_id,
            article_number,
            channel,
            sender_type,
            from_name,
            from_email,
            to_name,
            to_email,
            cc,
            subject,
            body,
            content_type,
            ' . $VisibilitySQL . '
            internal,
            created_by_user_id,
            changed_by_user_id,
            created_at,
            changed_at
        ) VALUES (
            ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ' . $VisibilityMark . '?, ?, ?, NOW(), NOW()
        )',
        $TicketID,
        $ArticleNumber,
        $Channel,
        $SenderType,
        $FromName,
        $FromEmail,
        $ToName,
        $ToEmail,
        $Cc,
        $Subject,
        $Body,
        $ContentType,
        @VisibilityBind,
        $Internal,
        $CreatedByUserID,
        $ChangedByUserID,
    );

    if ( !$Result ) {
        $Self->{LastError} = $Self->{DB}->Error() || 'Article could not be created';
        return;
    }

    my $ArticleID = $Self->{DB}->LastInsertID('ticket_article');

    if ( !$ArticleID ) {
        my $ArticleIDRow = $Self->{DB}->SelectRow(
            'SELECT id
             FROM ticket_article
             WHERE ticket_id = ?
                AND article_number = ?
             ORDER BY id DESC
             LIMIT 1',
            $TicketID,
            $ArticleNumber,
        );

        $ArticleID = $ArticleIDRow->{id} if $ArticleIDRow;
    }

    if ( !$ArticleID ) {
        $Self->{LastError} = $Self->{DB}->Error() || 'Article ID could not be loaded';
        return;
    }

    my $TicketUpdateResult = $Self->{DB}->Do(
        'UPDATE ticket
         SET changed_by_user_id = ?,
             changed_at = NOW()
         WHERE id = ?',
        $ChangedByUserID,
        $TicketID,
    );

    if ( !$TicketUpdateResult ) {
        $Self->{LastError} = $Self->{DB}->Error() || 'Ticket could not be updated after article creation';
        return;
    }

    if ( @{$Attachments} ) {
        if ( !$Self->_ArticleAttachmentsCreate(
            TicketID        => $TicketID,
            ArticleID       => $ArticleID,
            Attachments     => $Attachments,
            CreatedByUserID => $CreatedByUserID,
        ) ) {
            return;
        }
    }

    if ( !$Self->RecalculateTicketEscalationTimes(
        TicketID        => $TicketID,
        ChangedByUserID => $ChangedByUserID,
    ) ) {
        return;
    }

    if ( !$SkipNotification && ( $SenderType || '' ) eq 'customer' ) {
        $Self->_AgentNotificationSend(
            NotificationType => 'customer_reply_in_my_queues',
            TicketID         => $TicketID,
            ChangedByUserID  => $ChangedByUserID,
        );
    }

    return $ArticleID;
}


sub _AttachmentsValidate {
    my ( $Self, %Param ) = @_;

    my $Attachments = ref $Param{Attachments} eq 'ARRAY' ? $Param{Attachments} : [];

    return { Valid => 1, Error => '' } if !@{$Attachments};

    my $LimitMB = 25;

    if ( !defined $Self->{AttachmentMaxSizeMBCache} ) {
        my $Row = $Self->{DB}->SelectRow(
            'SELECT setting_value
             FROM system_setting
             WHERE setting_key = ?
             LIMIT 1',
            'system.attachment_max_size_mb',
        );

        if ( $Row && defined $Row->{setting_value} && $Row->{setting_value} =~ m{\A\d+\z} && $Row->{setting_value} >= 1 ) {
            $LimitMB = $Row->{setting_value};
            $LimitMB = 10240 if $LimitMB > 10240;
        }

        $Self->{AttachmentMaxSizeMBCache} = 0 + $LimitMB;
    }
    else {
        $LimitMB = $Self->{AttachmentMaxSizeMBCache};
    }

    my $LimitBytes = $LimitMB * 1024 * 1024;

    for my $Attachment ( @{$Attachments} ) {
        next if ref $Attachment ne 'HASH';

        my $Content = $Attachment->{Content};
        my $Size    = $Attachment->{ContentSize};
        $Size = length($Content) if !defined $Size || $Size !~ m{\A\d+\z};

        next if !$LimitBytes || $Size <= $LimitBytes;

        my $Filename = $Attachment->{Filename} || 'attachment';
        return {
            Valid => 0,
            Error => 'Attachment "' . $Filename . '" exceeds the permitted maximum size of ' . $LimitMB . ' MB',
        };
    }

    return { Valid => 1, Error => '' };
}

sub TicketStatusUpdate {
    my ( $Self, %Param ) = @_;

    my $TicketID        = $Param{TicketID} || 0;
    my $StatusID        = $Param{StatusID} || 0;
    my $ChangedByUserID = $Param{ChangedByUserID} || 1;
    my $PendingUntilRaw = $Param{PendingUntil} || '';

    if ( $TicketID !~ m{\A\d+\z} || !$TicketID ) {
        $Self->{LastError} = 'Valid TicketID is required';
        return;
    }

    if ( $StatusID !~ m{\A\d+\z} || !$StatusID ) {
        $Self->{LastError} = 'Valid StatusID is required';
        return;
    }

    my $Ticket = $Self->{DB}->SelectRow(
        'SELECT
            t.id,
            t.state_id,
            t.pending_started_at,
            t.pending_total_minutes,
            t.sla_pause_started_at,
            t.sla_pause_total_minutes,
            t.sla_source,
            t.sla_calendar_id,
            q.calendar_id AS queue_calendar_id,
            current_state.state_type AS current_state_type,
            current_state.sla_pause AS current_sla_pause
         FROM ticket t
         INNER JOIN ticket_queue q ON q.id = t.queue_id
         INNER JOIN ticket_state current_state ON current_state.id = t.state_id
         WHERE t.id = ?
         LIMIT 1',
        $TicketID,
    );

    if ( !$Ticket ) {
        $Self->{LastError} = $Self->{DB}->Error() || 'Ticket could not be loaded';
        return;
    }

    my $State = $Self->{DB}->SelectRow(
        'SELECT id, state_type, sla_pause
         FROM ticket_state
         WHERE id = ?
           AND active = 1
         LIMIT 1',
        $StatusID,
    );

    if ( !$State ) {
        $Self->{LastError} = $Self->{DB}->Error() || 'Ticket state could not be loaded';
        return;
    }

    my $Now = $Self->_NowDateTime();
    my $CalendarID = ( $Ticket->{sla_source} || '' ) eq 'sla'
        ? ( $Ticket->{sla_calendar_id} || 0 )
        : ( $Ticket->{queue_calendar_id} || 0 );

    my $PendingUntil;
    if ( ( $State->{state_type} || '' ) eq 'pending' ) {
        $PendingUntil = $Self->_DateTimeInputNormalize($PendingUntilRaw);

        if ( !$PendingUntil ) {
            $Self->{LastError} = 'Translate:TicketPendingUntilRequired';
            return;
        }

        if ( $Now && $PendingUntil le $Now ) {
            $Self->{LastError} = 'Translate:TicketPendingUntilFutureRequired';
            return;
        }
    }

    my $PendingMinutesToAdd = 0;
    if (
        ( $Ticket->{current_state_type} || '' ) eq 'pending'
        && ( $State->{state_type} || '' ) ne 'pending'
        && $Ticket->{pending_started_at}
        && $Now
    ) {
        $PendingMinutesToAdd = $Self->_WorkingMinutesBetween(
            CalendarID => $CalendarID,
            Start      => $Ticket->{pending_started_at},
            End        => $Now,
        );
    }

    my $SLAPauseMinutesToAdd = 0;
    if (
        $Ticket->{current_sla_pause}
        && !$State->{sla_pause}
        && $Ticket->{sla_pause_started_at}
        && $Now
    ) {
        $SLAPauseMinutesToAdd = $Self->_WorkingMinutesBetween(
            CalendarID => $CalendarID,
            Start      => $Ticket->{sla_pause_started_at},
            End        => $Now,
        );
    }

    my $Result = $Self->{DB}->Do(
        'UPDATE ticket
         SET state_id = ?,
             pending_total_minutes = pending_total_minutes + ?,
             pending_started_at = CASE
                 WHEN ? = "pending" THEN COALESCE(pending_started_at, NOW())
                 ELSE NULL
             END,
             pending_until = CASE WHEN ? = "pending" THEN ? ELSE NULL END,
             sla_pause_total_minutes = sla_pause_total_minutes + ?,
             sla_pause_started_at = CASE
                 WHEN ? = 1 THEN COALESCE(sla_pause_started_at, NOW())
                 ELSE NULL
             END,
             solution_at = CASE
                 WHEN ? = "closed" THEN COALESCE(solution_at, NOW())
                 ELSE solution_at
             END,
             changed_by_user_id = ?,
             changed_at = NOW()
         WHERE id = ?',
        $StatusID,
        $PendingMinutesToAdd,
        $State->{state_type} || '',
        $State->{state_type} || '',
        $PendingUntil,
        $SLAPauseMinutesToAdd,
        $State->{sla_pause} ? 1 : 0,
        $State->{state_type} || '',
        $ChangedByUserID,
        $TicketID,
    );

    if ( !$Result ) {
        $Self->{LastError} = $Self->{DB}->Error() || 'Ticket status could not be updated';
        return;
    }

    my $Recalculated = $Self->RecalculateTicketEscalationTimes(
        TicketID        => $TicketID,
        ChangedByUserID => $ChangedByUserID,
    );

    if ( $Recalculated && ( $Ticket->{state_id} || 0 ) != $StatusID ) {
        $Self->_AgentNotificationSend(
            NotificationType => 'ticket_state_changed',
            TicketID         => $TicketID,
            ChangedByUserID  => $ChangedByUserID,
        );
    }

    return $Recalculated;
}

sub TicketPriorityUpdate {
    my ( $Self, %Param ) = @_;

    my $TicketID        = $Param{TicketID} || 0;
    my $PriorityID      = $Param{PriorityID} || 0;
    my $User            = $Param{User} || {};
    my $ChangedByUserID = $Param{ChangedByUserID} || 1;

    if ( $TicketID !~ m{\A\d+\z} || !$TicketID ) {
        $Self->{LastError} = 'Valid TicketID is required';
        return;
    }

    if ( $PriorityID !~ m{\A\d+\z} || !$PriorityID ) {
        $Self->{LastError} = 'Valid PriorityID is required';
        return;
    }

    my $Ticket = $Self->{DB}->SelectRow(
        'SELECT id, queue_id, priority_id
         FROM ticket
         WHERE id = ?
         LIMIT 1',
        $TicketID,
    );

    if ( !$Ticket ) {
        $Self->{LastError} = $Self->{DB}->Error() || 'Ticket could not be loaded';
        return;
    }

    if ( $User->{user_account_id} && !$Self->_TicketChangeAllowed( Ticket => $Ticket, User => $User ) ) {
        $Self->{LastError} = 'Ticket change access denied';
        return;
    }

    my $Priority = $Self->{DB}->SelectRow(
        'SELECT id
         FROM ticket_priority
         WHERE id = ?
            AND active = 1
         LIMIT 1',
        $PriorityID,
    );

    if ( !$Priority ) {
        $Self->{LastError} = 'Ticket priority was not found';
        return;
    }

    my $Result = $Self->{DB}->Do(
        'UPDATE ticket
         SET priority_id = ?,
             changed_by_user_id = ?,
             changed_at = NOW()
         WHERE id = ?',
        $PriorityID,
        $ChangedByUserID,
        $TicketID,
    );

    if ( !$Result ) {
        $Self->{LastError} = $Self->{DB}->Error() || 'Ticket priority could not be updated';
        return;
    }

    return $Self->RecalculateTicketEscalationTimes(
        TicketID        => $TicketID,
        ChangedByUserID => $ChangedByUserID,
    );
}

sub TicketQueueUpdate {
    my ( $Self, %Param ) = @_;

    my $TicketID        = $Param{TicketID} || 0;
    my $QueueID         = $Param{QueueID} || 0;
    my $User            = $Param{User} || {};
    my $ChangedByUserID = $Param{ChangedByUserID} || 1;

    if ( $TicketID !~ m{\A\d+\z} || !$TicketID ) {
        $Self->{LastError} = 'Valid TicketID is required';
        return;
    }

    if ( $QueueID !~ m{\A\d+\z} || !$QueueID ) {
        $Self->{LastError} = 'Valid QueueID is required';
        return;
    }

    my $Ticket = $Self->{DB}->SelectRow(
        'SELECT
            t.id,
            t.queue_id,
            t.sla_source,
            t.sla_calendar_id,
            t.sla_pause_started_at,
            q.calendar_id AS queue_calendar_id,
            state.sla_pause
         FROM ticket t
         INNER JOIN ticket_queue q ON q.id = t.queue_id
         INNER JOIN ticket_state state ON state.id = t.state_id
         WHERE t.id = ?
         LIMIT 1',
        $TicketID,
    );

    if ( !$Ticket ) {
        $Self->{LastError} = $Self->{DB}->Error() || 'Ticket could not be loaded';
        return;
    }

    if ( $User->{user_account_id} && !$Self->_TicketChangeAllowed( Ticket => $Ticket, User => $User ) ) {
        $Self->{LastError} = 'Ticket change access denied';
        return;
    }

    my $Queue = $Self->{DB}->SelectRow(
        'SELECT id
         FROM ticket_queue
         WHERE id = ?
            AND active = 1
         LIMIT 1',
        $QueueID,
    );

    if ( !$Queue ) {
        $Self->{LastError} = 'Queue was not found';
        return;
    }

    if ( $User->{user_account_id} && $Self->{Permission} ) {
        my $TargetAllowed = $Self->{Permission}->QueueAccessCheck(
            UserID     => $User->{user_account_id},
            QueueID    => $QueueID,
            Permission => 'ticket.edit',
        );

        if (!$TargetAllowed) {
            $Self->{LastError} = 'Target queue access denied';
            return;
        }
    }

    my $PauseMinutesToAdd = 0;
    if ( $Ticket->{sla_pause} && $Ticket->{sla_pause_started_at} ) {
        my $OldCalendarID = ( $Ticket->{sla_source} || '' ) eq 'sla'
            ? ( $Ticket->{sla_calendar_id} || 0 )
            : ( $Ticket->{queue_calendar_id} || 0 );
        my $Now = $Self->_NowDateTime();
        if ($Now) {
            $PauseMinutesToAdd = $Self->_WorkingMinutesBetween(
                CalendarID => $OldCalendarID,
                Start      => $Ticket->{sla_pause_started_at},
                End        => $Now,
            );
        }
    }

    my $Result = $Self->{DB}->Do(
        'UPDATE ticket
         SET queue_id = ?,
             sla_pause_total_minutes = sla_pause_total_minutes + ?,
             sla_pause_started_at = CASE WHEN ? = 1 THEN NOW() ELSE NULL END,
             changed_by_user_id = ?,
             changed_at = NOW()
         WHERE id = ?',
        $QueueID,
        $PauseMinutesToAdd,
        $Ticket->{sla_pause} ? 1 : 0,
        $ChangedByUserID,
        $TicketID,
    );

    if ( !$Result ) {
        $Self->{LastError} = $Self->{DB}->Error() || 'Ticket queue could not be updated';
        return;
    }

    return $Self->RecalculateTicketEscalationTimes(
        TicketID        => $TicketID,
        ChangedByUserID => $ChangedByUserID,
    );
}


sub TicketServiceUpdate {
    my ( $Self, %Param ) = @_;

    my $TicketID        = $Param{TicketID} || 0;
    my $ServiceID       = defined $Param{ServiceID} ? $Param{ServiceID} : 0;
    my $User            = $Param{User} || {};
    my $ChangedByUserID = $Param{ChangedByUserID} || 1;

    if ( $TicketID !~ m{\A\d+\z} || !$TicketID ) {
        $Self->{LastError} = 'Valid TicketID is required';
        return;
    }

    if ( $ServiceID !~ m{\A\d+\z} ) {
        $Self->{LastError} = 'Translate:TicketServiceNotAvailable';
        return;
    }

    my $Ticket = $Self->{DB}->SelectRow(
        'SELECT
            t.id,
            t.queue_id,
            t.customer_id,
            t.service_id,
            t.sla_source,
            t.sla_calendar_id,
            t.sla_pause_started_at,
            t.sla_pause_total_minutes,
            q.calendar_id AS queue_calendar_id,
            state.sla_pause
         FROM ticket t
         INNER JOIN ticket_queue q ON q.id = t.queue_id
         INNER JOIN ticket_state state ON state.id = t.state_id
         WHERE t.id = ?
         LIMIT 1',
        $TicketID,
    );

    if ( !$Ticket ) {
        $Self->{LastError} = $Self->{DB}->Error() || 'Ticket could not be loaded';
        return;
    }

    if ( $User->{user_account_id} && !$Self->_TicketChangeAllowed( Ticket => $Ticket, User => $User ) ) {
        $Self->{LastError} = 'Ticket change access denied';
        return;
    }

    my $Snapshot = {
        service_id             => undef,
        sla_id                 => undef,
        sla_source             => 'queue',
        assignment_source      => 'queue',
        sla_name               => undef,
        calendar_id            => undef,
        update_mode            => 'customer_response',
        first_response_minutes => 0,
        update_minutes         => 0,
        solution_minutes       => 0,
    };

    if ($ServiceID) {
        my $ServiceObject = QisutuService->new(
            Config => $Self->{Config},
            DB     => $Self->{DB},
        );
        my $Resolved = $ServiceObject->SLAResolve(
            CustomerID => $Ticket->{customer_id},
            ServiceID  => $ServiceID,
        );

        if ( !$Resolved ) {
            $Self->{LastError} = $ServiceObject->Error() || 'Translate:TicketServiceNotAvailable';
            return;
        }

        $Snapshot = {
            service_id             => $Resolved->{service_id},
            sla_id                 => $Resolved->{sla_id},
            sla_source             => 'sla',
            assignment_source      => $Resolved->{assignment_source} || 'default',
            sla_name               => $Resolved->{sla_name},
            calendar_id            => $Resolved->{calendar_id},
            update_mode            => $Resolved->{update_mode} || 'customer_response',
            first_response_minutes => $Resolved->{first_response_minutes} || 0,
            update_minutes         => $Resolved->{update_minutes} || 0,
            solution_minutes       => $Resolved->{solution_minutes} || 0,
        };
    }

    my $PauseMinutesToAdd = 0;
    if ( $Ticket->{sla_pause} && $Ticket->{sla_pause_started_at} ) {
        my $OldCalendarID = ( $Ticket->{sla_source} || '' ) eq 'sla'
            ? ( $Ticket->{sla_calendar_id} || 0 )
            : ( $Ticket->{queue_calendar_id} || 0 );
        my $Now = $Self->_NowDateTime();
        if ($Now) {
            $PauseMinutesToAdd = $Self->_WorkingMinutesBetween(
                CalendarID => $OldCalendarID,
                Start      => $Ticket->{sla_pause_started_at},
                End        => $Now,
            );
        }
    }

    my $Result = $Self->{DB}->Do(
        'UPDATE ticket
         SET service_id = ?,
             sla_id = ?,
             sla_source = ?,
             sla_assignment_source = ?,
             sla_name_snapshot = ?,
             sla_calendar_id = ?,
             sla_update_mode = ?,
             sla_first_response_minutes = ?,
             sla_update_minutes = ?,
             sla_solution_minutes = ?,
             sla_pause_total_minutes = sla_pause_total_minutes + ?,
             sla_pause_started_at = CASE WHEN ? = 1 THEN NOW() ELSE NULL END,
             changed_by_user_id = ?,
             changed_at = NOW()
         WHERE id = ?',
        $Snapshot->{service_id},
        $Snapshot->{sla_id},
        $Snapshot->{sla_source},
        $Snapshot->{assignment_source},
        $Snapshot->{sla_name},
        $Snapshot->{calendar_id},
        $Snapshot->{update_mode},
        $Snapshot->{first_response_minutes},
        $Snapshot->{update_minutes},
        $Snapshot->{solution_minutes},
        $PauseMinutesToAdd,
        $Ticket->{sla_pause} ? 1 : 0,
        $ChangedByUserID,
        $TicketID,
    );

    if ( !$Result ) {
        $Self->{LastError} = $Self->{DB}->Error() || 'Translate:TicketServiceUpdateFailed';
        return;
    }

    return $Self->RecalculateTicketEscalationTimes(
        TicketID        => $TicketID,
        ChangedByUserID => $ChangedByUserID,
    );
}

sub TicketCustomerUserUpdate {
    my ( $Self, %Param ) = @_;

    my $TicketID        = $Param{TicketID} || 0;
    my $CustomerUserID  = $Param{CustomerUserID} || 0;
    my $User            = $Param{User} || {};
    my $ChangedByUserID = $Param{ChangedByUserID} || 1;

    if ( $TicketID !~ m{\A\d+\z} || !$TicketID ) {
        $Self->{LastError} = 'Valid TicketID is required';
        return;
    }

    if ( $CustomerUserID !~ m{\A\d+\z} || !$CustomerUserID ) {
        $Self->{LastError} = 'Valid CustomerUserID is required';
        return;
    }

    my $Ticket = $Self->{DB}->SelectRow(
        'SELECT
            t.id,
            t.queue_id,
            t.customer_id,
            t.customer_user_id,
            t.service_id,
            t.sla_source,
            t.sla_calendar_id,
            t.sla_pause_started_at,
            q.calendar_id AS queue_calendar_id,
            state.sla_pause
         FROM ticket t
         INNER JOIN ticket_queue q ON q.id = t.queue_id
         INNER JOIN ticket_state state ON state.id = t.state_id
         WHERE t.id = ?
         LIMIT 1',
        $TicketID,
    );

    if ( !$Ticket ) {
        $Self->{LastError} = $Self->{DB}->Error() || 'Ticket could not be loaded';
        return;
    }

    if ( $User->{user_account_id} && !$Self->_TicketChangeAllowed( Ticket => $Ticket, User => $User ) ) {
        $Self->{LastError} = 'Ticket change access denied';
        return;
    }

    my $CustomerUser = $Self->{DB}->SelectRow(
        'SELECT
            cu.id,
            cu.customer_id
         FROM customer_user cu
         INNER JOIN customer c
            ON c.id = cu.customer_id
         INNER JOIN user_account ua
            ON ua.id = cu.user_account_id
         WHERE cu.id = ?
            AND cu.active = 1
            AND c.active = 1
            AND ua.is_active = 1
            AND ua.account_type = ?
         LIMIT 1',
        $CustomerUserID,
        'customer',
    );

    if ( !$CustomerUser ) {
        $Self->{LastError} = 'Customer user was not found';
        return;
    }

    my $Snapshot;
    if ( $Ticket->{service_id} ) {
        my $ServiceObject = QisutuService->new(
            Config => $Self->{Config},
            DB     => $Self->{DB},
        );
        my $Resolved = $ServiceObject->SLAResolve(
            CustomerID => $CustomerUser->{customer_id},
            ServiceID  => $Ticket->{service_id},
        );

        if ($Resolved) {
            $Snapshot = {
                service_id             => $Resolved->{service_id},
                sla_id                 => $Resolved->{sla_id},
                sla_source             => 'sla',
                assignment_source      => $Resolved->{assignment_source} || 'default',
                sla_name               => $Resolved->{sla_name},
                calendar_id            => $Resolved->{calendar_id},
                update_mode            => $Resolved->{update_mode} || 'customer_response',
                first_response_minutes => $Resolved->{first_response_minutes} || 0,
                update_minutes         => $Resolved->{update_minutes} || 0,
                solution_minutes       => $Resolved->{solution_minutes} || 0,
            };
        }
        else {
            $Snapshot = {
                service_id             => undef,
                sla_id                 => undef,
                sla_source             => 'queue',
                assignment_source      => 'queue',
                sla_name               => undef,
                calendar_id            => undef,
                update_mode            => 'customer_response',
                first_response_minutes => 0,
                update_minutes         => 0,
                solution_minutes       => 0,
            };
        }
    }

    my $PauseMinutesToAdd = 0;
    if ( $Snapshot && $Ticket->{sla_pause} && $Ticket->{sla_pause_started_at} ) {
        my $OldCalendarID = ( $Ticket->{sla_source} || '' ) eq 'sla'
            ? ( $Ticket->{sla_calendar_id} || 0 )
            : ( $Ticket->{queue_calendar_id} || 0 );
        my $Now = $Self->_NowDateTime();
        if ($Now) {
            $PauseMinutesToAdd = $Self->_WorkingMinutesBetween(
                CalendarID => $OldCalendarID,
                Start      => $Ticket->{sla_pause_started_at},
                End        => $Now,
            );
        }
    }

    my $Result;
    if ($Snapshot) {
        $Result = $Self->{DB}->Do(
            'UPDATE ticket
             SET customer_id = ?,
                 customer_user_id = ?,
                 service_id = ?,
                 sla_id = ?,
                 sla_source = ?,
                 sla_assignment_source = ?,
                 sla_name_snapshot = ?,
                 sla_calendar_id = ?,
                 sla_update_mode = ?,
                 sla_first_response_minutes = ?,
                 sla_update_minutes = ?,
                 sla_solution_minutes = ?,
                 sla_pause_total_minutes = sla_pause_total_minutes + ?,
                 sla_pause_started_at = CASE WHEN ? = 1 THEN NOW() ELSE NULL END,
                 changed_by_user_id = ?,
                 changed_at = NOW()
             WHERE id = ?',
            $CustomerUser->{customer_id},
            $CustomerUser->{id},
            $Snapshot->{service_id},
            $Snapshot->{sla_id},
            $Snapshot->{sla_source},
            $Snapshot->{assignment_source},
            $Snapshot->{sla_name},
            $Snapshot->{calendar_id},
            $Snapshot->{update_mode},
            $Snapshot->{first_response_minutes},
            $Snapshot->{update_minutes},
            $Snapshot->{solution_minutes},
            $PauseMinutesToAdd,
            $Ticket->{sla_pause} ? 1 : 0,
            $ChangedByUserID,
            $TicketID,
        );
    }
    else {
        $Result = $Self->{DB}->Do(
            'UPDATE ticket
             SET customer_id = ?,
                 customer_user_id = ?,
                 changed_by_user_id = ?,
                 changed_at = NOW()
             WHERE id = ?',
            $CustomerUser->{customer_id},
            $CustomerUser->{id},
            $ChangedByUserID,
            $TicketID,
        );
    }

    if ( !$Result ) {
        $Self->{LastError} = $Self->{DB}->Error() || 'Ticket customer user could not be updated';
        return;
    }

    return $Self->RecalculateTicketEscalationTimes(
        TicketID        => $TicketID,
        ChangedByUserID => $ChangedByUserID,
    );
}

sub TicketOwnerUpdate {
    my ( $Self, %Param ) = @_;

    my $TicketID            = $Param{TicketID} || 0;
    my $OwnerUserID         = $Param{OwnerUserID} || 0;
    my $User                = $Param{User} || {};
    my $ChangedByUserID     = $Param{ChangedByUserID} || 1;
    my $SuppressNotification = $Param{SuppressNotification} ? 1 : 0;

    if ( $TicketID !~ m{\A\d+\z} || !$TicketID ) {
        $Self->{LastError} = 'Valid TicketID is required';
        return;
    }

    if ( $OwnerUserID !~ m{\A\d+\z} || !$OwnerUserID ) {
        $Self->{LastError} = 'Valid OwnerUserID is required';
        return;
    }

    my $Agent = $Self->{DB}->SelectRow(
        'SELECT id
         FROM user_account
         WHERE id = ?
            AND account_type = ?
            AND is_active = 1
            AND is_system_user = 0
         LIMIT 1',
        $OwnerUserID,
        'agent',
    );

    if ( !$Agent ) {
        $Self->{LastError} = 'Agent was not found';
        return;
    }

    my $Ticket = $Self->{DB}->SelectRow(
        'SELECT id, queue_id, owner_user_id
         FROM ticket
         WHERE id = ?
         LIMIT 1',
        $TicketID,
    );

    if ( !$Ticket ) {
        $Self->{LastError} = $Self->{DB}->Error() || 'Ticket could not be loaded';
        return;
    }

    if ( $User->{user_account_id} && !$Self->_TicketChangeAllowed( Ticket => $Ticket, User => $User ) ) {
        $Self->{LastError} = 'Ticket change access denied';
        return;
    }

    my $Result = $Self->{DB}->Do(
        'UPDATE ticket
         SET owner_user_id = ?,
             changed_by_user_id = ?,
             changed_at = NOW()
         WHERE id = ?',
        $OwnerUserID,
        $ChangedByUserID,
        $TicketID,
    );

    if ( !$Result ) {
        $Self->{LastError} = $Self->{DB}->Error() || 'Ticket owner could not be updated';
        return;
    }

    if ( !$SuppressNotification && ( $Ticket->{owner_user_id} || 0 ) != $OwnerUserID ) {
        $Self->_AgentNotificationSend(
            NotificationType => 'ticket_assigned_to_me',
            TicketID         => $TicketID,
            TargetUserID     => $OwnerUserID,
            ChangedByUserID  => $ChangedByUserID,
        );
    }

    return 1;
}

sub TicketResponsibleUpdate {
    my ( $Self, %Param ) = @_;

    my $TicketID             = $Param{TicketID} || 0;
    my $ResponsibleUserID    = $Param{ResponsibleUserID} || 0;
    my $User                 = $Param{User} || {};
    my $ChangedByUserID      = $Param{ChangedByUserID} || 1;

    if ( $TicketID !~ m{\A\d+\z} || !$TicketID ) {
        $Self->{LastError} = 'Valid TicketID is required';
        return;
    }

    if ( $ResponsibleUserID !~ m{\A\d+\z} || !$ResponsibleUserID ) {
        $Self->{LastError} = 'Valid ResponsibleUserID is required';
        return;
    }

    my $Agent = $Self->{DB}->SelectRow(
        'SELECT id
         FROM user_account
         WHERE id = ?
            AND account_type = ?
            AND is_active = 1
            AND is_system_user = 0
         LIMIT 1',
        $ResponsibleUserID,
        'agent',
    );

    if ( !$Agent ) {
        $Self->{LastError} = 'Agent was not found';
        return;
    }

    my $Ticket = $Self->{DB}->SelectRow(
        'SELECT id, queue_id, responsible_user_id
         FROM ticket
         WHERE id = ?
         LIMIT 1',
        $TicketID,
    );

    if ( !$Ticket ) {
        $Self->{LastError} = $Self->{DB}->Error() || 'Ticket could not be loaded';
        return;
    }

    if ( $User->{user_account_id} && !$Self->_TicketChangeAllowed( Ticket => $Ticket, User => $User ) ) {
        $Self->{LastError} = 'Ticket change access denied';
        return;
    }

    my $Result = $Self->{DB}->Do(
        'UPDATE ticket
         SET responsible_user_id = ?,
             changed_by_user_id = ?,
             changed_at = NOW()
         WHERE id = ?',
        $ResponsibleUserID,
        $ChangedByUserID,
        $TicketID,
    );

    if ( !$Result ) {
        $Self->{LastError} = $Self->{DB}->Error() || 'Ticket responsible could not be updated';
        return;
    }

    return 1;
}

sub TicketCloseUpdate {
    my ( $Self, %Param ) = @_;

    my $TicketID        = $Param{TicketID} || 0;
    my $StateID         = $Param{StateID} || 0;
    my $User            = $Param{User} || {};
    my $ChangedByUserID = $Param{ChangedByUserID} || 1;

    if ( $TicketID !~ m{\A\d+\z} || !$TicketID ) {
        $Self->{LastError} = 'Valid TicketID is required';
        return;
    }

    if ( $StateID !~ m{\A\d+\z} || !$StateID ) {
        $Self->{LastError} = 'Valid StateID is required';
        return;
    }

    my $Ticket = $Self->{DB}->SelectRow(
        'SELECT id, queue_id, state_id
         FROM ticket
         WHERE id = ?
         LIMIT 1',
        $TicketID,
    );

    if ( !$Ticket ) {
        $Self->{LastError} = $Self->{DB}->Error() || 'Ticket could not be loaded';
        return;
    }

    if ( $User->{user_account_id} && !$Self->_TicketChangeAllowed( Ticket => $Ticket, User => $User ) ) {
        $Self->{LastError} = 'Ticket change access denied';
        return;
    }

    my $State = $Self->{DB}->SelectRow(
        'SELECT id
         FROM ticket_state
         WHERE id = ?
            AND active = 1
            AND state_type = ?
         LIMIT 1',
        $StateID,
        'closed',
    );

    if ( !$State ) {
        $Self->{LastError} = 'Closed ticket state was not found';
        return;
    }

    return $Self->TicketStatusUpdate(
        TicketID        => $TicketID,
        StatusID        => $StateID,
        ChangedByUserID => $ChangedByUserID,
    );
}

sub RecalculateTicketEscalationTimes {
    my ( $Self, %Param ) = @_;

    my $TicketID        = $Param{TicketID} || 0;
    my $ChangedByUserID = $Param{ChangedByUserID} || 1;

    if ( $TicketID !~ m{\A\d+\z} || !$TicketID ) {
        $Self->{LastError} = 'Valid TicketID is required';
        return;
    }

    my $Ticket = $Self->{DB}->SelectRow(
        'SELECT
            t.id,
            t.queue_id,
            t.created_at,
            t.changed_at,
            t.first_response_due_at AS previous_first_response_due_at,
            t.update_due_at AS previous_update_due_at,
            t.solution_due_at AS previous_solution_due_at,
            t.solution_at,
            t.sla_source,
            t.sla_calendar_id,
            t.sla_update_mode,
            t.sla_first_response_minutes,
            t.sla_update_minutes,
            t.sla_solution_minutes,
            t.sla_pause_started_at,
            t.sla_pause_total_minutes,
            t.sla_first_response_breached,
            t.sla_update_breached,
            t.sla_solution_breached,
            state.state_type,
            state.sla_pause,
            q.calendar_id AS queue_calendar_id,
            q.escalation_first_response_minutes AS queue_first_response_minutes,
            q.escalation_update_minutes AS queue_update_minutes,
            q.escalation_solution_minutes AS queue_solution_minutes
         FROM ticket t
         INNER JOIN ticket_state state ON state.id = t.state_id
         INNER JOIN ticket_queue q ON q.id = t.queue_id
         WHERE t.id = ?
         LIMIT 1',
        $TicketID,
    );

    if ( !$Ticket ) {
        $Self->{LastError} = $Self->{DB}->Error() || 'Ticket could not be loaded for escalation calculation';
        return;
    }

    my $ArticleDates = $Self->{DB}->SelectRow(
        'SELECT
            MIN(CASE
                WHEN sender_type = ? AND internal = 0 AND visibility IN (?, ?)
                THEN created_at END
            ) AS first_agent_response_at,
            MAX(CASE
                WHEN sender_type = ? AND internal = 0 AND visibility IN (?, ?)
                THEN created_at END
            ) AS last_agent_article_at,
            MAX(CASE
                WHEN sender_type = ? AND visibility IN (?, ?)
                THEN created_at END
            ) AS last_customer_article_at
         FROM ticket_article
         WHERE ticket_id = ?',
        'agent', 'both', 'external',
        'agent', 'both', 'external',
        'customer', 'both', 'external',
        $TicketID,
    );

    if ( !$ArticleDates ) {
        $Self->{LastError} = $Self->{DB}->Error() || 'Ticket article dates could not be loaded';
        return;
    }

    my $UsesSLA = ( $Ticket->{sla_source} || '' ) eq 'sla' ? 1 : 0;
    my $CalendarID = $UsesSLA ? ( $Ticket->{sla_calendar_id} || 0 ) : ( $Ticket->{queue_calendar_id} || 0 );
    my $FirstMinutes = $UsesSLA ? ( $Ticket->{sla_first_response_minutes} || 0 ) : ( $Ticket->{queue_first_response_minutes} || 0 );
    my $UpdateMinutes = $UsesSLA ? ( $Ticket->{sla_update_minutes} || 0 ) : ( $Ticket->{queue_update_minutes} || 0 );
    my $SolutionMinutes = $UsesSLA ? ( $Ticket->{sla_solution_minutes} || 0 ) : ( $Ticket->{queue_solution_minutes} || 0 );
    my $UpdateMode = $UsesSLA ? ( $Ticket->{sla_update_mode} || 'customer_response' ) : 'customer_response';

    if ( !defined $Self->{_DisplayNowDateTime} ) {
        my $NowRow = $Self->{DB}->SelectRow(
            'SELECT DATE_FORMAT(NOW(), "%Y-%m-%d %H:%i:%s") AS now_datetime'
        );
        $Self->{_DisplayNowDateTime} = $NowRow ? ( $NowRow->{now_datetime} || '' ) : '';
    }
    my $Now = $Self->{_DisplayNowDateTime} || '';

    my $PauseMinutes = $Ticket->{sla_pause_total_minutes} || 0;
    if ( $Ticket->{sla_pause} && $Ticket->{sla_pause_started_at} && $Now ) {
        $PauseMinutes += $Self->_WorkingMinutesBetween(
            CalendarID => $CalendarID,
            Start      => $Ticket->{sla_pause_started_at},
            End        => $Now,
        );
    }

    my $FirstResponseDueAt;
    my $SolutionDueAt;
    my $UpdateDueAt;

    if ($FirstMinutes) {
        $FirstResponseDueAt = $Self->_AddEscalationMinutes(
            CalendarID => $CalendarID,
            Start      => $Ticket->{created_at},
            Minutes    => $FirstMinutes,
        );
        if ( $FirstResponseDueAt && $PauseMinutes ) {
            $FirstResponseDueAt = $Self->_AddEscalationMinutes(
                CalendarID => $CalendarID,
                Start      => $FirstResponseDueAt,
                Minutes    => $PauseMinutes,
            );
        }
    }

    if ($SolutionMinutes) {
        $SolutionDueAt = $Self->_AddEscalationMinutes(
            CalendarID => $CalendarID,
            Start      => $Ticket->{created_at},
            Minutes    => $SolutionMinutes,
        );
        if ( $SolutionDueAt && $PauseMinutes ) {
            $SolutionDueAt = $Self->_AddEscalationMinutes(
                CalendarID => $CalendarID,
                Start      => $SolutionDueAt,
                Minutes    => $PauseMinutes,
            );
        }
    }

    my $FirstResponseAt       = $ArticleDates->{first_agent_response_at};
    my $LastAgentArticleAt    = $ArticleDates->{last_agent_article_at};
    my $LastCustomerArticleAt = $ArticleDates->{last_customer_article_at};

    if ( $UpdateMinutes && $FirstResponseAt && ( $Ticket->{state_type} || '' ) ne 'closed' ) {
        my $UpdateStart;

        if ( $UpdateMode eq 'regular' ) {
            $UpdateStart = $LastAgentArticleAt || $FirstResponseAt;
        }
        elsif (
            $LastCustomerArticleAt
            && ( !$LastAgentArticleAt || $LastCustomerArticleAt gt $LastAgentArticleAt )
        ) {
            $UpdateStart = $LastCustomerArticleAt;
        }

        if ($UpdateStart) {
            $UpdateDueAt = $Self->_AddEscalationMinutes(
                CalendarID => $CalendarID,
                Start      => $UpdateStart,
                Minutes    => $UpdateMinutes,
            );
            if ( $UpdateDueAt && $PauseMinutes ) {
                $UpdateDueAt = $Self->_AddEscalationMinutes(
                    CalendarID => $CalendarID,
                    Start      => $UpdateDueAt,
                    Minutes    => $PauseMinutes,
                );
            }
        }
    }

    my $SolutionAt = $Ticket->{solution_at};
    if ( ( $Ticket->{state_type} || '' ) eq 'closed' && !$SolutionAt ) {
        $SolutionAt = $Ticket->{changed_at};
    }

    my $FirstBreached = $Ticket->{sla_first_response_breached} ? 1 : 0;
    my $UpdateBreached = $Ticket->{sla_update_breached} ? 1 : 0;
    my $SolutionBreached = $Ticket->{sla_solution_breached} ? 1 : 0;

    if ( $FirstResponseDueAt && $FirstResponseAt && $FirstResponseAt gt $FirstResponseDueAt ) {
        $FirstBreached = 1;
    }
    elsif (
        $FirstResponseDueAt
        && !$FirstResponseAt
        && !$Ticket->{sla_pause}
        && ( $Ticket->{state_type} || '' ) ne 'closed'
        && $Now
        && $FirstResponseDueAt le $Now
    ) {
        $FirstBreached = 1;
    }

    if (
        $Ticket->{previous_update_due_at}
        && $LastAgentArticleAt
        && $LastAgentArticleAt gt $Ticket->{previous_update_due_at}
    ) {
        $UpdateBreached = 1;
    }
    if (
        $UpdateDueAt
        && !$Ticket->{sla_pause}
        && ( $Ticket->{state_type} || '' ) ne 'closed'
        && $Now
        && $UpdateDueAt le $Now
    ) {
        $UpdateBreached = 1;
    }

    if ( $SolutionDueAt && $SolutionAt && $SolutionAt gt $SolutionDueAt ) {
        $SolutionBreached = 1;
    }
    elsif (
        $SolutionDueAt
        && !$SolutionAt
        && !$Ticket->{sla_pause}
        && ( $Ticket->{state_type} || '' ) ne 'closed'
        && $Now
        && $SolutionDueAt le $Now
    ) {
        $SolutionBreached = 1;
    }

    my $EscalationState = 'normal';
    if ( $FirstBreached || $UpdateBreached || $SolutionBreached ) {
        $EscalationState = 'escalated';
    }
    elsif ( !$Ticket->{sla_pause} && ( $Ticket->{state_type} || '' ) ne 'closed' && $Now ) {
        my @WarningChecks;
        push @WarningChecks, [ $FirstResponseDueAt, $FirstMinutes ] if $FirstResponseDueAt && !$FirstResponseAt;
        push @WarningChecks, [ $UpdateDueAt, $UpdateMinutes ] if $UpdateDueAt;
        push @WarningChecks, [ $SolutionDueAt, $SolutionMinutes ] if $SolutionDueAt && !$SolutionAt;

        for my $Check (@WarningChecks) {
            my ( $DueAt, $TargetMinutes ) = @{$Check};
            next if !$DueAt || $DueAt le $Now;

            my $Remaining = $Self->_WorkingMinutesBetween(
                CalendarID => $CalendarID,
                Start      => $Now,
                End        => $DueAt,
            );
            my $Threshold = int( ( $TargetMinutes || 0 ) * 0.20 );
            $Threshold = 1 if $Threshold < 1;

            if ( $Remaining <= $Threshold ) {
                $EscalationState = 'warning';
                last;
            }
        }
    }

    my $Result = $Self->{DB}->Do(
        'UPDATE ticket
         SET first_response_due_at = ?,
             first_response_at = ?,
             update_due_at = ?,
             last_customer_article_at = ?,
             last_agent_article_at = ?,
             solution_due_at = ?,
             solution_at = ?,
             escalation_state = ?,
             sla_first_response_breached = ?,
             sla_update_breached = ?,
             sla_solution_breached = ?,
             changed_by_user_id = ?,
             changed_at = changed_at
         WHERE id = ?',
        $FirstResponseDueAt,
        $FirstResponseAt,
        $UpdateDueAt,
        $LastCustomerArticleAt,
        $LastAgentArticleAt,
        $SolutionDueAt,
        $SolutionAt,
        $EscalationState,
        $FirstBreached,
        $UpdateBreached,
        $SolutionBreached,
        $ChangedByUserID,
        $TicketID,
    );

    if ( !$Result ) {
        $Self->{LastError} = $Self->{DB}->Error() || 'Ticket escalation times could not be saved';
        return;
    }

    return 1;
}

sub CheckTicketEscalations {
    my ( $Self, %Param ) = @_;

    my $Limit = $Param{Limit} || 5000;
    $Limit = 5000 if $Limit !~ m{\A\d+\z} || $Limit < 1 || $Limit > 50000;

    my $ChangedByUserID = $Param{ChangedByUserID} || 1;
    my $PendingReleased = 0;
    my $PendingDue      = 0;

    my $PendingRows = $Self->{DB}->SelectAll(
        'SELECT
            t.id
         FROM ticket t
         INNER JOIN ticket_state s
            ON s.id = t.state_id
         WHERE s.state_type = ?
           AND t.pending_until IS NOT NULL
           AND t.pending_until <= DATE_FORMAT(NOW(), "%Y-%m-%d %H:%i:%s")
         ORDER BY t.pending_until ASC, t.id ASC
         LIMIT ' . $Limit,
        'pending',
    ) || [];

    $PendingDue = scalar @{$PendingRows};

    for my $Row ( @{$PendingRows} ) {
        next if !$Row->{id};

        $Self->_AgentNotificationSend(
            NotificationType => 'ticket_pending_reached',
            TicketID         => $Row->{id},
            ChangedByUserID  => $ChangedByUserID,
        );
    }

    my $RemainingLimit = $Limit;
    $RemainingLimit = 1 if $RemainingLimit < 1;

    my $EscalationRows = $Self->{DB}->SelectAll(
        'SELECT t.id
         FROM ticket t
         INNER JOIN ticket_state s
            ON s.id = t.state_id
         WHERE s.state_type <> ?
           AND s.sla_pause = 0
           AND t.escalation_state <> ?
           AND (
                (t.first_response_due_at IS NOT NULL AND t.first_response_at IS NULL AND t.first_response_due_at <= DATE_FORMAT(NOW(), "%Y-%m-%d %H:%i:%s"))
                OR (t.update_due_at IS NOT NULL AND t.update_due_at <= DATE_FORMAT(NOW(), "%Y-%m-%d %H:%i:%s"))
                OR (t.solution_due_at IS NOT NULL AND t.solution_at IS NULL AND t.solution_due_at <= DATE_FORMAT(NOW(), "%Y-%m-%d %H:%i:%s"))
           )
         ORDER BY
            LEAST(
                COALESCE(t.first_response_due_at,  "9999-12-31 23:59:59"),
                COALESCE(t.update_due_at,          "9999-12-31 23:59:59"),
                COALESCE(t.solution_due_at,        "9999-12-31 23:59:59")
            ) ASC,
            t.id ASC
         LIMIT ' . $RemainingLimit,
        'closed',
        'escalated',
    ) || [];

    my $Escalated = 0;
    for my $Row ( @{$EscalationRows} ) {
        next if !$Row->{id};

        my $Result = $Self->{DB}->Do(
            'UPDATE ticket
             SET escalation_state = ?,
                 sla_first_response_breached = CASE
                     WHEN first_response_due_at IS NOT NULL
                       AND first_response_at IS NULL
                       AND first_response_due_at <= DATE_FORMAT(NOW(), "%Y-%m-%d %H:%i:%s")
                     THEN 1
                     ELSE sla_first_response_breached
                 END,
                 sla_update_breached = CASE
                     WHEN update_due_at IS NOT NULL
                       AND update_due_at <= DATE_FORMAT(NOW(), "%Y-%m-%d %H:%i:%s")
                     THEN 1
                     ELSE sla_update_breached
                 END,
                 sla_solution_breached = CASE
                     WHEN solution_due_at IS NOT NULL
                       AND solution_at IS NULL
                       AND solution_due_at <= DATE_FORMAT(NOW(), "%Y-%m-%d %H:%i:%s")
                     THEN 1
                     ELSE sla_solution_breached
                 END,
                 changed_by_user_id = ?,
                 changed_at = changed_at
             WHERE id = ?
               AND escalation_state <> ?',
            'escalated',
            $ChangedByUserID,
            $Row->{id},
            'escalated',
        );

        if ($Result) {
            $Escalated++;
            $Self->_AgentNotificationSend(
                NotificationType => 'ticket_escalation_reached',
                TicketID         => $Row->{id},
                ChangedByUserID  => $ChangedByUserID,
            );
        }
    }

    my $RecalculationLimit = $Limit > 5000 ? 5000 : $Limit;
    my $Recalculated = $Self->RecalculateOpenTicketEscalationStates(
        Force           => 1,
        Limit           => $RecalculationLimit,
        ChangedByUserID => $ChangedByUserID,
    );

    return {
        PendingDue      => $PendingDue,
        PendingReleased => $PendingReleased,
        Escalated       => $Escalated,
        Recalculated    => $Recalculated || 0,
        Checked         => $PendingDue + $Escalated,
    };
}

sub _PendingTicketRelease {
    my ( $Self, %Param ) = @_;

    my $Ticket          = $Param{Ticket} || {};
    my $TicketID        = $Ticket->{id} || 0;
    my $OpenStateID     = $Param{OpenStateID} || 0;
    my $ChangedByUserID = $Param{ChangedByUserID} || 1;

    return if $TicketID !~ m{\A\d+\z} || !$TicketID;
    return if $OpenStateID !~ m{\A\d+\z} || !$OpenStateID;

    my $Now = $Self->_NowDateTime();
    return if !$Now;

    my $PendingMinutesToAdd = 0;
    if ( $Ticket->{pending_started_at} ) {
        my $PendingEnd = $Ticket->{pending_until} || $Now;
        $PendingEnd = $Now if $PendingEnd gt $Now;

        $PendingMinutesToAdd = $Self->_WorkingMinutesBetween(
            CalendarID => $Ticket->{calendar_id},
            Start      => $Ticket->{pending_started_at},
            End        => $PendingEnd,
        );
    }

    my $Result = $Self->{DB}->Do(
        'UPDATE ticket
         SET state_id = ?,
             pending_total_minutes = pending_total_minutes + ?,
             pending_started_at = NULL,
             pending_until = NULL,
             escalation_state = ?,
             changed_by_user_id = ?,
             changed_at = NOW()
         WHERE id = ?',
        $OpenStateID,
        $PendingMinutesToAdd || 0,
        'normal',
        $ChangedByUserID,
        $TicketID,
    );

    return if !$Result;

    return $Self->RecalculateTicketEscalationTimes(
        TicketID        => $TicketID,
        ChangedByUserID => $ChangedByUserID,
    );
}

sub RecalculateOpenTicketEscalationStates {
    my ( $Self, %Param ) = @_;

    my $Limit = $Param{Limit} || 500;
    $Limit = 500 if $Limit !~ m{\A\d+\z} || $Limit < 1 || $Limit > 5000;

    my $Force = $Param{Force} ? 1 : 0;

    my $Where = 's.state_type <> ?';
    my @Bind  = ('closed');

    if ( !$Force ) {
        $Where .= '
            AND (
                (t.sla_source = "sla" AND (
                    (t.sla_first_response_minutes > 0 AND t.first_response_due_at IS NULL)
                    OR (t.sla_solution_minutes > 0 AND t.solution_due_at IS NULL)
                    OR (t.sla_update_minutes > 0 AND t.update_due_at IS NULL)
                ))
                OR (t.sla_source <> "sla" AND (
                    (q.escalation_first_response_minutes > 0 AND t.first_response_due_at IS NULL)
                    OR (q.escalation_solution_minutes > 0 AND t.solution_due_at IS NULL)
                    OR (q.escalation_update_minutes > 0 AND t.update_due_at IS NULL)
                ))
            )';
    }

    my $Rows = $Self->{DB}->SelectAll(
        'SELECT t.id
         FROM ticket t
         INNER JOIN ticket_state s
            ON s.id = t.state_id
         INNER JOIN ticket_queue q
            ON q.id = t.queue_id
         WHERE ' . $Where . '
         ORDER BY t.changed_at DESC, t.id DESC
         LIMIT ' . $Limit,
        @Bind,
    ) || [];

    my $Count = 0;
    for my $Row ( @{$Rows} ) {
        next if !$Row->{id};
        if ( $Self->RecalculateTicketEscalationTimes(
            TicketID        => $Row->{id},
            ChangedByUserID => $Param{ChangedByUserID} || 1,
        ) ) {
            $Count++;
        }
    }

    return $Count;
}


sub _OpenStateID {
    my ($Self) = @_;

    if ( defined $Self->{_OpenStateID} ) {
        return $Self->{_OpenStateID};
    }

    my $State = $Self->{DB}->SelectRow(
        'SELECT id
         FROM ticket_state
         WHERE active = 1
           AND state_type = ?
         ORDER BY
           CASE WHEN name = ? THEN 0 ELSE 1 END,
           sort_order ASC,
           id ASC
         LIMIT 1',
        'open',
        'open',
    );

    $Self->{_OpenStateID} = $State ? ( $State->{id} || 0 ) : 0;

    return $Self->{_OpenStateID};
}

sub _NowDateTime {
    my ($Self) = @_;

    if ( !defined $Self->{_DisplayNowDateTime} ) {
        my $NowRow = $Self->{DB}->SelectRow(
            'SELECT DATE_FORMAT(NOW(), "%Y-%m-%d %H:%i:%s") AS now_datetime'
        );
        $Self->{_DisplayNowDateTime} = $NowRow ? ( $NowRow->{now_datetime} || '' ) : '';
    }

    return $Self->{_DisplayNowDateTime} || '';
}

sub _DateTimeInputNormalize {
    my ( $Self, $Value ) = @_;

    $Value = '' if !defined $Value;
    $Value =~ s{\A\s+}{};
    $Value =~ s{\s+\z}{};
    $Value =~ s{T}{ };

    if ( $Value =~ m{\A(\d{4})-(\d{2})-(\d{2})\s+(\d{2}):(\d{2})(?::(\d{2}))?\z} ) {
        my ( $Year, $Month, $Day, $Hour, $Minute, $Second ) = ( $1, $2, $3, $4, $5, $6 || '00' );
        return sprintf '%04d-%02d-%02d %02d:%02d:%02d', $Year, $Month, $Day, $Hour, $Minute, $Second;
    }

    return;
}

sub _CalendarObject {
    my ($Self) = @_;

    if ( !$Self->{_CalendarObject} ) {
        $Self->{_CalendarObject} = QisutuCalendar->new(
            Config => $Self->{Config},
            DB     => $Self->{DB},
        );
    }

    return $Self->{_CalendarObject};
}

sub _AddEscalationMinutes {
    my ( $Self, %Param ) = @_;

    my $CalendarID = $Param{CalendarID} || 0;
    my $Start      = $Param{Start} || '';
    my $Minutes    = $Param{Minutes} || 0;

    return if !$Start || $Minutes !~ m{\A\d+\z} || !$Minutes;

    if ( $CalendarID && $CalendarID =~ m{\A\d+\z} ) {
        my $CalendarObject = $Self->_CalendarObject();

        my $DueAt = $CalendarObject->AddWorkingMinutes(
            CalendarID     => $CalendarID,
            StartDateTime  => $Start,
            Minutes        => $Minutes,
        );

        return $DueAt if $DueAt;
    }

    my $Row = $Self->{DB}->SelectRow(
        'SELECT DATE_FORMAT(DATE_ADD(?, INTERVAL ? MINUTE), "%Y-%m-%d %H:%i:%s") AS due_at',
        $Start,
        $Minutes,
    );

    return $Row ? $Row->{due_at} : undef;
}

sub _WorkingMinutesBetween {
    my ( $Self, %Param ) = @_;

    my $CalendarID = $Param{CalendarID} || 0;
    my $Start      = $Param{Start} || '';
    my $End        = $Param{End} || '';

    return 0 if !$Start || !$End;

    if ( $CalendarID && $CalendarID =~ m{\A\d+\z} ) {
        my $CalendarObject = $Self->_CalendarObject();

        my $Minutes = $CalendarObject->WorkingMinutesBetween(
            CalendarID    => $CalendarID,
            StartDateTime => $Start,
            EndDateTime   => $End,
        );

        return $Minutes || 0;
    }

    my $Row = $Self->{DB}->SelectRow(
        'SELECT GREATEST(TIMESTAMPDIFF(MINUTE, ?, ?), 0) AS minutes_between',
        $Start,
        $End,
    );

    return $Row ? ( $Row->{minutes_between} || 0 ) : 0;
}

sub _EscalationStateCalculate {
    my ( $Self, %Param ) = @_;

    return 'normal' if ( $Param{StateType} || '' ) eq 'closed';
    return 'normal' if $Param{SLAPause};

    my $Now = $Param{Now} || '';
    return 'normal' if !$Now;

    if ( $Param{FirstResponseDueAt} && !$Param{FirstResponseAt} && $Param{FirstResponseDueAt} le $Now ) {
        return 'escalated';
    }

    if ( $Param{UpdateDueAt} && $Param{UpdateDueAt} le $Now ) {
        return 'escalated';
    }

    if ( $Param{SolutionDueAt} && !$Param{SolutionAt} && $Param{SolutionDueAt} le $Now ) {
        return 'escalated';
    }

    return 'normal';
}

sub _EscalationDisplayPrepare {
    my ( $Self, %Param ) = @_;

    my $Ticket   = $Param{Ticket} || {};
    my $Language = $Param{Language} || 'en';

    $Ticket->{escalation_state} ||= 'normal';
    $Ticket->{escalation_state_label} = 'Translate:TicketEscalationStateNormal';
    $Ticket->{escalation_state_class} = 'qisutu-escalation-normal';

    $Ticket->{first_response_due_at_display} = $Self->_DateTimeFormat( DateTime => $Ticket->{first_response_due_at}, Language => $Language ) || '-';
    $Ticket->{first_response_at_display}     = $Self->_DateTimeFormat( DateTime => $Ticket->{first_response_at}, Language => $Language ) || '-';
    $Ticket->{update_due_at_display}         = $Self->_DateTimeFormat( DateTime => $Ticket->{update_due_at}, Language => $Language ) || '-';
    $Ticket->{last_customer_article_at_display} = $Self->_DateTimeFormat( DateTime => $Ticket->{last_customer_article_at}, Language => $Language ) || '-';
    $Ticket->{last_agent_article_at_display}    = $Self->_DateTimeFormat( DateTime => $Ticket->{last_agent_article_at}, Language => $Language ) || '-';
    $Ticket->{solution_due_at_display}       = $Self->_DateTimeFormat( DateTime => $Ticket->{solution_due_at}, Language => $Language ) || '-';
    $Ticket->{solution_at_display}           = $Self->_DateTimeFormat( DateTime => $Ticket->{solution_at}, Language => $Language ) || '-';
    $Ticket->{pending_until_display}         = $Self->_DateTimeFormat( DateTime => $Ticket->{pending_until}, Language => $Language ) || '-';
    $Ticket->{pending_until_class}           = '';
    $Ticket->{pending_until_reached}         = 0;
    $Ticket->{pending_until_reached_since}   = '';

    if ( !defined $Self->{_DisplayNowDateTime} ) {
        my $NowRow = $Self->{DB}->SelectRow(
            'SELECT DATE_FORMAT(NOW(), "%Y-%m-%d %H:%i:%s") AS now_datetime'
        );
        $Self->{_DisplayNowDateTime} = $NowRow ? ( $NowRow->{now_datetime} || '' ) : '';
    }
    my $Now = $Self->{_DisplayNowDateTime} || '';

    if (
        ( $Ticket->{state_type} || '' ) eq 'pending'
        && $Now
        && $Ticket->{pending_until}
        && $Ticket->{pending_until} le $Now
    ) {
        my $PendingSince = $Self->_EscalationDurationFormat(
            From     => $Ticket->{pending_until},
            To       => $Now,
            Language => $Language,
        );

        $Ticket->{pending_until_reached}       = 1;
        $Ticket->{pending_until_class}         = 'qisutu-escalation-value-escalated';
        $Ticket->{pending_until_reached_since} = $Self->_PendingReachedSinceText(
            Duration => $PendingSince,
            Language => $Language,
        );
    }

    my $EscalationCheckActive = 1;
    if ( ( $Ticket->{state_type} || '' ) eq 'closed' || $Ticket->{sla_pause} ) {
        $EscalationCheckActive = 0;
    }

    $Ticket->{first_response_escalated} = 0;
    $Ticket->{first_response_due_class} = '';
    $Ticket->{first_response_escalated_since} = '';

    if ( $Ticket->{sla_first_response_breached} ) {
        $Ticket->{first_response_escalated} = 1;
        $Ticket->{first_response_due_class} = 'qisutu-escalation-value-escalated';
    }
    elsif (
        $EscalationCheckActive
        && $Now
        && $Ticket->{first_response_due_at}
        && !$Ticket->{first_response_at}
        && $Ticket->{first_response_due_at} le $Now
    ) {
        $Ticket->{first_response_escalated} = 1;
        $Ticket->{first_response_due_class} = 'qisutu-escalation-value-escalated';
        $Ticket->{first_response_escalated_since} = $Self->_EscalationDurationFormat( From => $Ticket->{first_response_due_at}, To => $Now, Language => $Language );
    }

    $Ticket->{update_escalated} = 0;
    $Ticket->{update_due_class} = '';
    $Ticket->{update_escalated_since} = '';

    if ( $Ticket->{sla_update_breached} ) {
        $Ticket->{update_escalated} = 1;
        $Ticket->{update_due_class} = 'qisutu-escalation-value-escalated';
    }
    elsif (
        $EscalationCheckActive
        && $Now
        && $Ticket->{update_due_at}
        && $Ticket->{update_due_at} le $Now
    ) {
        $Ticket->{update_escalated} = 1;
        $Ticket->{update_due_class} = 'qisutu-escalation-value-escalated';
        $Ticket->{update_escalated_since} = $Self->_EscalationDurationFormat( From => $Ticket->{update_due_at}, To => $Now, Language => $Language );
    }

    $Ticket->{solution_escalated} = 0;
    $Ticket->{solution_due_class} = '';
    $Ticket->{solution_escalated_since} = '';

    if ( $Ticket->{sla_solution_breached} ) {
        $Ticket->{solution_escalated} = 1;
        $Ticket->{solution_due_class} = 'qisutu-escalation-value-escalated';
    }
    elsif (
        $EscalationCheckActive
        && $Now
        && $Ticket->{solution_due_at}
        && !$Ticket->{solution_at}
        && $Ticket->{solution_due_at} le $Now
    ) {
        $Ticket->{solution_escalated} = 1;
        $Ticket->{solution_due_class} = 'qisutu-escalation-value-escalated';
        $Ticket->{solution_escalated_since} = $Self->_EscalationDurationFormat( From => $Ticket->{solution_due_at}, To => $Now, Language => $Language );
    }

    if (
        $Ticket->{first_response_escalated}
        || $Ticket->{update_escalated}
        || $Ticket->{solution_escalated}
    ) {
        $Ticket->{escalation_state_display} = 'escalated';
        $Ticket->{escalation_state_label}   = 'Translate:TicketEscalationStateEscalated';
        $Ticket->{escalation_state_class}   = 'qisutu-escalation-escalated';
    }
    elsif ( ( $Ticket->{escalation_state} || '' ) eq 'warning' ) {
        $Ticket->{escalation_state_display} = 'warning';
        $Ticket->{escalation_state_label}   = 'Translate:TicketEscalationStateWarning';
        $Ticket->{escalation_state_class}   = 'qisutu-escalation-warning';
    }
    else {
        $Ticket->{escalation_state_display} = 'normal';
        $Ticket->{escalation_state_label}   = 'Translate:TicketEscalationStateNormal';
        $Ticket->{escalation_state_class}   = 'qisutu-escalation-normal';
    }

    my @DueDates;
    push @DueDates, $Ticket->{first_response_due_at} if $Ticket->{first_response_due_at} && !$Ticket->{first_response_at};
    push @DueDates, $Ticket->{update_due_at} if $Ticket->{update_due_at};
    push @DueDates, $Ticket->{solution_due_at} if $Ticket->{solution_due_at} && !$Ticket->{solution_at};

    @DueDates = sort @DueDates;
    $Ticket->{next_escalation_at} = $DueDates[0] || '';
    $Ticket->{next_escalation_at_display} = $Self->_DateTimeFormat( DateTime => $Ticket->{next_escalation_at}, Language => $Language ) || '-';

    $Ticket->{ticket_list_alert_label} = $Ticket->{escalation_state_label};
    $Ticket->{ticket_list_alert_class} = $Ticket->{escalation_state_class};
    $Ticket->{ticket_list_alert_text}  = $Ticket->{next_escalation_at_display};

    if ( $Ticket->{pending_until_reached} ) {
        $Ticket->{ticket_list_alert_label} = 'Translate:TicketPendingReached';
        $Ticket->{ticket_list_alert_class} = 'qisutu-escalation-escalated';
        $Ticket->{ticket_list_alert_text}  = $Self->_PendingReachedSinceShortText(
            Duration => $Self->_EscalationDurationFormat(
                From     => $Ticket->{pending_until},
                To       => $Now,
                Language => $Language,
            ),
            Language => $Language,
        );
    }

    return $Ticket;
}


sub _PendingReachedSinceText {
    my ( $Self, %Param ) = @_;

    my $Duration = $Param{Duration} || '';
    my $Language = $Param{Language} || 'en';

    if ( $Language eq 'de' ) {
        return 'Warten erreicht seit: ' . ( $Duration || 'weniger als 1 Minute' );
    }

    return 'Pending reached for: ' . ( $Duration || 'less than 1 minute' );
}

sub _PendingReachedSinceShortText {
    my ( $Self, %Param ) = @_;

    my $Duration = $Param{Duration} || '';
    my $Language = $Param{Language} || 'en';

    if ( $Language eq 'de' ) {
        return 'seit ' . ( $Duration || 'weniger als 1 Minute' );
    }

    return 'for ' . ( $Duration || 'less than 1 minute' );
}

sub _EscalationDurationFormat {
    my ( $Self, %Param ) = @_;

    my $From     = $Param{From} || '';
    my $To       = $Param{To} || '';
    my $Language = $Param{Language} || 'en';

    my $FromEpoch = $Self->_DateTimeToEpoch($From);
    my $ToEpoch   = $Self->_DateTimeToEpoch($To);

    return '' if !defined $FromEpoch || !defined $ToEpoch;

    my $Seconds = $ToEpoch - $FromEpoch;
    $Seconds = 0 if $Seconds < 0;

    my $Minutes = int( $Seconds / 60 );
    my $Hours   = int( $Minutes / 60 );
    my $Days    = int( $Hours / 24 );

    $Minutes = $Minutes % 60;
    $Hours   = $Hours % 24;

    if ( $Language eq 'de' ) {
        return 'weniger als 1 Minute' if !$Days && !$Hours && !$Minutes;

        my @Parts;
        push @Parts, $Days . ( $Days == 1 ? ' Tag' : ' Tage' ) if $Days;
        push @Parts, $Hours . ( $Hours == 1 ? ' Stunde' : ' Stunden' ) if $Hours;
        push @Parts, $Minutes . ( $Minutes == 1 ? ' Minute' : ' Minuten' ) if $Minutes && @Parts < 2;

        return join ' ', @Parts;
    }

    return 'less than 1 minute' if !$Days && !$Hours && !$Minutes;

    my @Parts;
    push @Parts, $Days . ( $Days == 1 ? ' day' : ' days' ) if $Days;
    push @Parts, $Hours . ( $Hours == 1 ? ' hour' : ' hours' ) if $Hours;
    push @Parts, $Minutes . ( $Minutes == 1 ? ' minute' : ' minutes' ) if $Minutes && @Parts < 2;

    return join ' ', @Parts;
}

sub _DateTimeToEpoch {
    my ( $Self, $DateTime ) = @_;

    return if !$DateTime;

    if ( $DateTime =~ m{\A(\d{4})-(\d{2})-(\d{2})[ T](\d{2}):(\d{2}):(\d{2})\z} ) {
        my ( $Year, $Month, $Day, $Hour, $Minute, $Second ) = ( $1, $2, $3, $4, $5, $6 );

        my $Epoch;
        eval {
            $Epoch = timelocal( $Second, $Minute, $Hour, $Day, $Month - 1, $Year - 1900 );
            1;
        } || return;

        return $Epoch;
    }

    return;
}


sub _DateTimeFormat {
    my ( $Self, %Param ) = @_;

    my $DateTime = $Param{DateTime} || '';
    my $Language = $Param{Language} || 'en';

    return '' if !$DateTime;

    if ( $DateTime =~ m{\A(\d{4})-(\d{2})-(\d{2})[ T](\d{2}):(\d{2}):(\d{2})\z} ) {
        my ( $Year, $Month, $Day, $Hour, $Minute, $Second ) = ( $1, $2, $3, $4, $5, $6 );

        if ( $Language eq 'de' ) {
            return "$Day.$Month.$Year $Hour:$Minute:$Second";
        }

        return "$Year-$Month-$Day $Hour:$Minute:$Second";
    }

    if ( $DateTime =~ m{\A(\d{4})-(\d{2})-(\d{2})[ T](\d{2}):(\d{2})\z} ) {
        my ( $Year, $Month, $Day, $Hour, $Minute ) = ( $1, $2, $3, $4, $5 );

        if ( $Language eq 'de' ) {
            return "$Day.$Month.$Year $Hour:$Minute";
        }

        return "$Year-$Month-$Day $Hour:$Minute";
    }

    if ( $DateTime =~ m{\A(\d{4})-(\d{2})-(\d{2})\z} ) {
        my ( $Year, $Month, $Day ) = ( $1, $2, $3 );

        if ( $Language eq 'de' ) {
            return "$Day.$Month.$Year";
        }

        return "$Year-$Month-$Day";
    }

    return $DateTime;
}

sub _UserName {
    my ( $Self, %Param ) = @_;

    my $Firstname = $Param{Firstname} || '';
    my $Lastname  = $Param{Lastname}  || '';
    my $Login     = $Param{Login}     || '';
    my $Name      = join ' ', grep {$_} ( $Firstname, $Lastname );

    if ( !$Name ) {
        $Name = $Login;
    }

    return $Name;
}

sub _TicketOwnerLabel {
    my ( $Self, %Param ) = @_;

    my $Language = $Param{Language} || 'en';

    if ( $Language eq 'de' ) {
        return 'Besitzer';
    }

    return 'Owner';
}

sub _TicketStateDisplay {
    my ( $Self, %Param ) = @_;

    my $State = $Param{State} || '';
    my $Key   = lc $State;

    $Key =~ s{\A\s+}{};
    $Key =~ s{\s+\z}{};
    $Key =~ s{\+}{ plus }g;
    $Key =~ s{-}{ minus }g;
    $Key =~ s{[^a-z0-9]+}{_}g;
    $Key =~ s{\A_+}{};
    $Key =~ s{_+\z}{};

    return $State if !$Key;

    return 'Translate:TicketStateName_' . $Key;
}

sub _TicketPriorityDisplay {
    my ( $Self, %Param ) = @_;

    my $Priority = $Param{Priority} || '';
    my $Key      = lc $Priority;

    $Key =~ s{\A\s+}{};
    $Key =~ s{\s+\z}{};
    $Key =~ s{[^a-z0-9]+}{_}g;
    $Key =~ s{\A_+}{};
    $Key =~ s{_+\z}{};

    my %Supported = map { $_ => 1 } qw(
        1_very_low
        2_low
        3_normal
        4_high
        5_very_high
    );

    return $Priority if !$Supported{$Key};

    return 'Translate:TicketPriorityName_' . $Key;
}

sub _DefaultStateID {
    my ($Self) = @_;

    my $State = $Self->{DB}->SelectRow(
        'SELECT id
         FROM ticket_state
         WHERE name = ?
           AND active = 1
         LIMIT 1',
        'new',
    );

    if ( !$State ) {
        $Self->{LastError} = $Self->{DB}->Error() || 'Ticket state new was not found';
        return;
    }

    return $State->{id};
}

sub _DefaultPriorityID {
    my ($Self) = @_;

    my $Priority = $Self->{DB}->SelectRow(
        'SELECT id
         FROM ticket_priority
         WHERE active = 1
           AND (name = ? OR priority_value = ?)
         ORDER BY
           CASE WHEN name = ? THEN 0 ELSE 1 END,
           sort_order ASC,
           id ASC
         LIMIT 1',
        '3 normal',
        3,
        '3 normal',
    );

    if ( !$Priority ) {
        $Self->{LastError} = $Self->{DB}->Error() || 'Ticket priority 3 normal was not found';
        return;
    }

    return $Priority->{id};
}

sub _TicketNumberCreate {
    my ($Self) = @_;

    my $Prefix = strftime '%Y%m%d', localtime;
    my $Row = $Self->{DB}->SelectRow(
        'SELECT MAX(ticket_number) AS max_ticket_number
         FROM ticket
         WHERE ticket_number LIKE ?',
        $Prefix . '%',
    );

    return if !$Row;

    my $Next = 1;
    if ( ( $Row->{max_ticket_number} || '' ) =~ m{\A\Q$Prefix\E(\d+)\z} ) {
        $Next = $1 + 1;
    }

    return $Prefix . sprintf '%04d', $Next;
}

sub _CustomerByEmail {
    my ( $Self, %Param ) = @_;

    my $Email = $Self->_NormalizeEmail( $Param{Email} );
    return ( undef, undef ) if !$Email;

    my $CustomerUser = $Self->{DB}->SelectRow(
        'SELECT
            cu.id AS customer_user_id,
            cu.customer_id
         FROM customer_user cu
         INNER JOIN user_account ua
            ON ua.id = cu.user_account_id
         INNER JOIN customer c
            ON c.id = cu.customer_id
         WHERE LOWER(ua.email) = ?
           AND cu.active = 1
           AND c.active = 1
           AND ua.is_active = 1
         LIMIT 1',
        $Email,
    );

    return ( undef, undef ) if !$CustomerUser;

    return ( $CustomerUser->{customer_id}, $CustomerUser->{customer_user_id} );
}

sub _NormalizeEmail {
    my ( $Self, $Email ) = @_;

    $Email ||= '';
    $Email =~ s{\A\s+}{};
    $Email =~ s{\s+\z}{};

    return lc $Email;
}


sub _AgentNotificationSend {
    my ( $Self, %Param ) = @_;

    $Self->{LastAgentNotificationSent}  = 0;
    $Self->{LastAgentNotificationError} = '';

    if ( !$Param{NotificationType} ) {
        $Self->{LastAgentNotificationError} = 'Missing agent notification type';
        return 0;
    }

    if ( !$Param{TicketID} ) {
        $Self->{LastAgentNotificationError} = 'Missing TicketID for agent notification';
        return 0;
    }

    my $Sent = 0;
    my $Error = '';

    my $OK = eval {
        my $Notification = QisutuNotification->new(
            Config => $Self->{Config},
            DB     => $Self->{DB},
        );

        $Sent  = $Notification->Send(%Param) || 0;
        $Error = $Notification->Error() || '';

        1;
    };

    if ( !$OK ) {
        $Error = $@ || 'Agent notification could not be sent';
        $Error =~ s{\s+\z}{};
    }

    $Self->{LastAgentNotificationSent}  = $Sent;
    $Self->{LastAgentNotificationError} = $Error;

    return $Sent;
}

sub LastAgentNotificationSent {
    my ($Self) = @_;

    return $Self->{LastAgentNotificationSent} || 0;
}

sub LastAgentNotificationError {
    my ($Self) = @_;

    return $Self->{LastAgentNotificationError} || '';
}

sub LastAgentNotificationSummary {
    my ($Self) = @_;

    my $Sent  = $Self->LastAgentNotificationSent();
    my $Error = $Self->LastAgentNotificationError();

    if ($Sent) {
        return $Sent . ' agent notification(s) sent';
    }

    return $Error ? '0 agent notification(s) sent: ' . $Error : '0 agent notification(s) sent';
}

sub Error {
    my ($Self) = @_;

    return $Self->{LastError};
}

1;
