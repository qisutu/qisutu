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

package QisutuDashboard;

use strict;
use warnings;
use utf8;

use POSIX qw(strftime);
use Time::Local qw(timelocal);

sub new {
    my ( $Class, %Param ) = @_;

    my $Self = {
        Config     => $Param{Config},
        DB         => $Param{DB},
        Permission => $Param{Permission},
        LastError  => '',
    };

    bless $Self, $Class;

    return $Self;
}

sub AgentQueueList {
    my ( $Self, %Param ) = @_;

    my $User   = $Param{User} || {};
    my $UserID = $User->{user_account_id} || 0;

    return [] if !$Self->{DB} || !$Self->{Permission};
    return [] if $UserID !~ m{\A\d+\z} || !$UserID;

    my $QueueIDs = $Self->{Permission}->QueueIDList(
        UserID     => $UserID,
        Permission => 'ticket.view',
    ) || [];

    return [] if !@{$QueueIDs};

    my $Placeholder = join ', ', map {'?'} @{$QueueIDs};
    my $Rows = $Self->{DB}->SelectAll(
        'SELECT id, COALESCE(NULLIF(full_name, ""), name) AS label
         FROM ticket_queue
         WHERE active = 1
           AND id IN (' . $Placeholder . ')
         ORDER BY sort_order ASC, label ASC, id ASC',
        @{$QueueIDs},
    );

    if ( !$Rows ) {
        $Self->{LastError} = $Self->{DB}->Error() || 'Dashboard queues could not be loaded';
        return [];
    }

    return $Rows;
}

sub AgentData {
    my ( $Self, %Param ) = @_;

    my $User          = $Param{User} || {};
    my $AllowedQueues = ref $Param{AllowedQueueIDs} eq 'ARRAY' ? $Param{AllowedQueueIDs} : [];
    my $QueueID       = $Param{QueueID} || 0;
    my $Scope         = ( $Param{Scope} || '' ) eq 'personal' ? 'personal' : 'team';
    my $DateFrom      = $Param{DateFrom} || '';
    my $DateTo        = $Param{DateTo} || '';

    my %AllowedQueue = map { int($_) => 1 } grep { defined $_ && $_ =~ m{\A\d+\z} && $_ > 0 } @{$AllowedQueues};
    my @QueueIDs = sort { $a <=> $b } keys %AllowedQueue;

    if ( $QueueID && $AllowedQueue{$QueueID} ) {
        @QueueIDs = ( int($QueueID) );
    }

    my $Empty = $Self->_EmptyData( DateFrom => $DateFrom, DateTo => $DateTo );
    return $Empty if !$Self->{DB} || !@QueueIDs;

    my $WhereData = $Self->_AgentWhereData(
        QueueIDs => \@QueueIDs,
        Scope    => $Scope,
        UserID   => $User->{user_account_id} || 0,
    );

    my $Metric = $Self->_Metrics( WhereData => $WhereData );
    my $Status = $Self->_StatusDistribution( WhereData => $WhereData );
    my $Age    = $Self->_AgeDistribution( WhereData => $WhereData );
    my $Trend  = $Self->_Trend(
        WhereData => $WhereData,
        DateFrom  => $DateFrom,
        DateTo    => $DateTo,
    );
    my $Attention = $Self->_Attention( WhereData => $WhereData );

    return {
        metrics   => $Metric,
        status    => $Status,
        age       => $Age,
        trend     => $Trend,
        attention => $Attention,
    };
}

sub _AgentWhereData {
    my ( $Self, %Param ) = @_;

    my $QueueIDs = $Param{QueueIDs} || [];
    my @Where;
    my @Bind;

    my $Placeholder = join ', ', map {'?'} @{$QueueIDs};
    push @Where, 't.queue_id IN (' . $Placeholder . ')';
    push @Bind, @{$QueueIDs};

    if ( ( $Param{Scope} || '' ) eq 'personal' ) {
        push @Where, 't.owner_user_id = ?';
        push @Bind, $Param{UserID} || 0;
    }

    return {
        SQL  => join( ' AND ', map { '(' . $_ . ')' } @Where ),
        Bind => \@Bind,
    };
}

sub _Metrics {
    my ( $Self, %Param ) = @_;

    my $WhereData = $Param{WhereData} || {};
    my $Escalated = $Self->_EscalatedSQL();
    my $Warning   = $Self->_WarningSQL();
    my $CustomerWaiting = $Self->_CustomerWaitingSQL();

    my $Row = $Self->{DB}->SelectRow(
        'SELECT
            COALESCE(SUM(CASE WHEN s.state_type <> "closed" THEN 1 ELSE 0 END), 0) AS open_count,
            COALESCE(SUM(CASE WHEN s.state_type = "new" THEN 1 ELSE 0 END), 0) AS new_count,
            COALESCE(SUM(CASE WHEN s.state_type <> "closed" AND t.owner_user_id IS NULL THEN 1 ELSE 0 END), 0) AS unassigned_count,
            COALESCE(SUM(CASE WHEN ' . $Escalated . ' THEN 1 ELSE 0 END), 0) AS escalated_count,
            COALESCE(SUM(CASE WHEN ' . $Warning . ' THEN 1 ELSE 0 END), 0) AS warning_count,
            COALESCE(SUM(CASE WHEN s.state_type <> "closed" AND ' . $CustomerWaiting . ' THEN 1 ELSE 0 END), 0) AS customer_waiting_count
         FROM ticket t
         INNER JOIN ticket_state s ON s.id = t.state_id
         WHERE ' . ( $WhereData->{SQL} || '1 = 0' ),
        @{ $WhereData->{Bind} || [] },
    );

    if ( !$Row ) {
        $Self->{LastError} ||= $Self->{DB}->Error() || 'Dashboard metrics could not be loaded';
        $Row = {};
    }

    return {
        open             => $Self->_Number( $Row->{open_count} ),
        new              => $Self->_Number( $Row->{new_count} ),
        unassigned       => $Self->_Number( $Row->{unassigned_count} ),
        escalated        => $Self->_Number( $Row->{escalated_count} ),
        warning          => $Self->_Number( $Row->{warning_count} ),
        customer_waiting => $Self->_Number( $Row->{customer_waiting_count} ),
    };
}

sub _StatusDistribution {
    my ( $Self, %Param ) = @_;

    my $WhereData = $Param{WhereData} || {};
    my $Rows = $Self->{DB}->SelectAll(
        'SELECT
            s.id,
            s.name,
            s.state_type,
            COUNT(*) AS ticket_count
         FROM ticket t
         INNER JOIN ticket_state s ON s.id = t.state_id
         WHERE ' . ( $WhereData->{SQL} || '1 = 0' ) . '
           AND s.state_type <> "closed"
         GROUP BY s.id, s.name, s.state_type, s.sort_order
         ORDER BY s.sort_order ASC, s.name ASC, s.id ASC',
        @{ $WhereData->{Bind} || [] },
    );

    if ( !$Rows ) {
        $Self->{LastError} ||= $Self->{DB}->Error() || 'Dashboard status distribution could not be loaded';
        return [];
    }

    for my $Row ( @{$Rows} ) {
        $Row->{ticket_count} = $Self->_Number( $Row->{ticket_count} );
    }

    return $Rows;
}

sub _AgeDistribution {
    my ( $Self, %Param ) = @_;

    my $WhereData = $Param{WhereData} || {};
    my $Row = $Self->{DB}->SelectRow(
        'SELECT
            COALESCE(SUM(CASE WHEN TIMESTAMPDIFF(MINUTE, t.created_at, NOW()) < 480 THEN 1 ELSE 0 END), 0) AS under_8h,
            COALESCE(SUM(CASE WHEN TIMESTAMPDIFF(MINUTE, t.created_at, NOW()) BETWEEN 480 AND 1439 THEN 1 ELSE 0 END), 0) AS under_24h,
            COALESCE(SUM(CASE WHEN TIMESTAMPDIFF(MINUTE, t.created_at, NOW()) BETWEEN 1440 AND 4319 THEN 1 ELSE 0 END), 0) AS under_3d,
            COALESCE(SUM(CASE WHEN TIMESTAMPDIFF(MINUTE, t.created_at, NOW()) BETWEEN 4320 AND 14399 THEN 1 ELSE 0 END), 0) AS under_10d,
            COALESCE(SUM(CASE WHEN TIMESTAMPDIFF(MINUTE, t.created_at, NOW()) >= 14400 THEN 1 ELSE 0 END), 0) AS over_10d
         FROM ticket t
         INNER JOIN ticket_state s ON s.id = t.state_id
         WHERE ' . ( $WhereData->{SQL} || '1 = 0' ) . '
           AND s.state_type <> "closed"',
        @{ $WhereData->{Bind} || [] },
    );

    if ( !$Row ) {
        $Self->{LastError} ||= $Self->{DB}->Error() || 'Dashboard age distribution could not be loaded';
        $Row = {};
    }

    return [
        { key => 'under_8h',  value => $Self->_Number( $Row->{under_8h} ) },
        { key => 'under_24h', value => $Self->_Number( $Row->{under_24h} ) },
        { key => 'under_3d',  value => $Self->_Number( $Row->{under_3d} ) },
        { key => 'under_10d', value => $Self->_Number( $Row->{under_10d} ) },
        { key => 'over_10d',  value => $Self->_Number( $Row->{over_10d} ) },
    ];
}

sub _Trend {
    my ( $Self, %Param ) = @_;

    my $WhereData = $Param{WhereData} || {};
    my $DateFrom  = $Param{DateFrom} || '';
    my $DateTo    = $Param{DateTo} || '';
    my $DateList  = $Self->_DateList( DateFrom => $DateFrom, DateTo => $DateTo );

    my $CreatedRows = $Self->{DB}->SelectAll(
        'SELECT DATE_FORMAT(t.created_at, "%Y-%m-%d") AS day_value, COUNT(*) AS ticket_count
         FROM ticket t
         WHERE ' . ( $WhereData->{SQL} || '1 = 0' ) . '
           AND t.created_at >= CONCAT(?, " 00:00:00")
           AND t.created_at <= CONCAT(?, " 23:59:59")
         GROUP BY DATE_FORMAT(t.created_at, "%Y-%m-%d")
         ORDER BY day_value ASC',
        @{ $WhereData->{Bind} || [] },
        $DateFrom,
        $DateTo,
    ) || [];

    my $ClosedRows = $Self->{DB}->SelectAll(
        'SELECT DATE_FORMAT(t.solution_at, "%Y-%m-%d") AS day_value, COUNT(*) AS ticket_count
         FROM ticket t
         WHERE ' . ( $WhereData->{SQL} || '1 = 0' ) . '
           AND t.solution_at IS NOT NULL
           AND t.solution_at >= CONCAT(?, " 00:00:00")
           AND t.solution_at <= CONCAT(?, " 23:59:59")
         GROUP BY DATE_FORMAT(t.solution_at, "%Y-%m-%d")
         ORDER BY day_value ASC',
        @{ $WhereData->{Bind} || [] },
        $DateFrom,
        $DateTo,
    ) || [];

    my %Created = map { ( $_->{day_value} || '' ) => $Self->_Number( $_->{ticket_count} ) } @{$CreatedRows};
    my %Closed  = map { ( $_->{day_value} || '' ) => $Self->_Number( $_->{ticket_count} ) } @{$ClosedRows};

    return [
        map {
            {
                date    => $_,
                created => $Created{$_} || 0,
                closed  => $Closed{$_} || 0,
            }
        } @{$DateList}
    ];
}

sub _Attention {
    my ( $Self, %Param ) = @_;

    my $WhereData = $Param{WhereData} || {};
    my $Escalated = $Self->_EscalatedSQL();
    my $Warning   = $Self->_WarningSQL();
    my $CustomerWaiting = $Self->_CustomerWaitingSQL();
    my $NextDue   = $Self->_NextDueSQL();

    my $Rows = $Self->{DB}->SelectAll(
        'SELECT
            t.id,
            t.ticket_number,
            t.title,
            t.created_at,
            t.changed_at,
            t.owner_user_id,
            q.name AS queue_name,
            COALESCE(NULLIF(q.full_name, ""), q.name) AS queue_full_name,
            s.name AS state_name,
            s.state_type,
            TIMESTAMPDIFF(MINUTE, t.created_at, NOW()) AS age_minutes,
            ' . $NextDue . ' AS next_due_at,
            CASE WHEN ' . $Escalated . ' THEN 1 ELSE 0 END AS is_escalated,
            CASE WHEN ' . $Warning . ' THEN 1 ELSE 0 END AS is_warning,
            CASE WHEN ' . $CustomerWaiting . ' THEN 1 ELSE 0 END AS is_customer_waiting,
            CASE WHEN t.owner_user_id IS NULL THEN 1 ELSE 0 END AS is_unassigned
         FROM ticket t
         INNER JOIN ticket_queue q ON q.id = t.queue_id
         INNER JOIN ticket_state s ON s.id = t.state_id
         WHERE ' . ( $WhereData->{SQL} || '1 = 0' ) . '
           AND s.state_type <> "closed"
           AND (
                ' . $Escalated . '
                OR ' . $Warning . '
                OR ' . $CustomerWaiting . '
                OR t.owner_user_id IS NULL
                OR t.created_at <= DATE_SUB(NOW(), INTERVAL 10 DAY)
           )
         ORDER BY
            is_escalated DESC,
            is_warning DESC,
            is_customer_waiting DESC,
            is_unassigned DESC,
            t.created_at ASC,
            t.id ASC
         LIMIT 10',
        @{ $WhereData->{Bind} || [] },
    );

    if ( !$Rows ) {
        $Self->{LastError} ||= $Self->{DB}->Error() || 'Dashboard attention list could not be loaded';
        return [];
    }

    for my $Row ( @{$Rows} ) {
        for my $Key (qw(age_minutes is_escalated is_warning is_customer_waiting is_unassigned)) {
            $Row->{$Key} = $Self->_Number( $Row->{$Key} );
        }
    }

    return $Rows;
}

sub _NextDueSQL {
    return 'NULLIF(LEAST(
        COALESCE(CASE WHEN t.first_response_at IS NULL THEN t.first_response_due_at END, "9999-12-31 23:59:59"),
        COALESCE(t.update_due_at, "9999-12-31 23:59:59"),
        COALESCE(CASE WHEN t.solution_at IS NULL THEN t.solution_due_at END, "9999-12-31 23:59:59")
    ), "9999-12-31 23:59:59")';
}

sub _EscalatedSQL {
    my ($Self) = @_;

    return 's.state_type <> "closed"
        AND s.sla_pause = 0
        AND (
            (t.first_response_due_at IS NOT NULL AND t.first_response_at IS NULL AND t.first_response_due_at <= NOW())
            OR (t.update_due_at IS NOT NULL AND t.update_due_at <= NOW())
            OR (t.solution_due_at IS NOT NULL AND t.solution_at IS NULL AND t.solution_due_at <= NOW())
        )';
}

sub _WarningSQL {
    my ($Self) = @_;

    my $NextDue = $Self->_NextDueSQL();

    return 's.state_type <> "closed"
        AND s.sla_pause = 0
        AND ' . $NextDue . ' IS NOT NULL
        AND ' . $NextDue . ' > NOW()
        AND ' . $NextDue . ' <= DATE_ADD(NOW(), INTERVAL 8 HOUR)';
}

sub _CustomerWaitingSQL {
    return 't.last_customer_article_at IS NOT NULL
        AND (
            t.last_agent_article_at IS NULL
            OR t.last_customer_article_at > t.last_agent_article_at
        )';
}

sub _DateList {
    my ( $Self, %Param ) = @_;

    my $From = $Self->_DateEpoch( $Param{DateFrom} );
    my $To   = $Self->_DateEpoch( $Param{DateTo} );

    return [] if !defined $From || !defined $To || $From > $To;

    my @Date;
    my $Current = $From;
    my $Guard   = 0;

    while ( $Current <= $To && $Guard < 366 ) {
        push @Date, strftime( '%Y-%m-%d', localtime($Current) );
        $Current += 86_400;
        $Guard++;
    }

    return \@Date;
}

sub _DateEpoch {
    my ( $Self, $Value ) = @_;

    return if !defined $Value || $Value !~ m{\A(\d{4})-(\d{2})-(\d{2})\z};
    my ( $Year, $Month, $Day ) = ( $1, $2, $3 );

    my $Epoch = eval { timelocal( 0, 0, 12, $Day, $Month - 1, $Year ) };
    return if !defined $Epoch;
    return if strftime( '%Y-%m-%d', localtime($Epoch) ) ne $Value;

    return $Epoch;
}

sub _EmptyData {
    my ( $Self, %Param ) = @_;

    my $DateList = $Self->_DateList(
        DateFrom => $Param{DateFrom},
        DateTo   => $Param{DateTo},
    );

    return {
        metrics => {
            open             => 0,
            new              => 0,
            unassigned       => 0,
            escalated        => 0,
            warning          => 0,
            customer_waiting => 0,
        },
        status => [],
        age => [
            { key => 'under_8h', value => 0 },
            { key => 'under_24h', value => 0 },
            { key => 'under_3d', value => 0 },
            { key => 'under_10d', value => 0 },
            { key => 'over_10d', value => 0 },
        ],
        trend => [ map { { date => $_, created => 0, closed => 0 } } @{$DateList} ],
        attention => [],
    };
}

sub _Number {
    my ( $Self, $Value ) = @_;

    return 0 if !defined $Value || $Value !~ m{\A-?\d+(?:\.\d+)?\z};
    return 0 + $Value;
}

sub Error {
    my ($Self) = @_;

    return $Self->{LastError};
}

1;
