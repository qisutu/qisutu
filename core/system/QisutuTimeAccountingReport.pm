# Qisutu - Open Source Ticket System
# Copyright (C) 2026 Franziska Steps
# SPDX-License-Identifier: AGPL-3.0-or-later

package QisutuTimeAccountingReport;

use strict;
use warnings;
use utf8;

use POSIX qw(strftime);
use Time::Piece;

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

sub Error {
    my ($Self) = @_;
    return $Self->{LastError} || '';
}

sub FilterDefault {
    my ( $Self, %Param ) = @_;
    my $Today = $Param{Today} || strftime( '%Y-%m-%d', localtime );
    my $MonthStart = $Today;
    $MonthStart =~ s{-\d{2}\z}{-01};

    return {
        DateFrom       => $MonthStart,
        DateTo         => $Today,
        AgentID        => 0,
        CustomerID     => 0,
        QueueID        => 0,
        ActivityTypeID => 0,
        Billing        => 'all',
    };
}

sub FilterParse {
    my ( $Self, %Param ) = @_;
    my $Request = $Param{Request} || {};
    my $Filter = $Self->FilterDefault( Today => $Param{Today} );

    $Self->{LastError} = '';

    for my $Name (qw(DateFrom DateTo)) {
        $Filter->{$Name} = $Request->{$Name} if exists $Request->{$Name};
        if ( !$Self->_DateValid( $Filter->{$Name} ) ) {
            $Self->{LastError} = 'Translate:AdminTimeAccountingReportInvalidFilter';
            return;
        }
    }

    if ( $Filter->{DateFrom} gt $Filter->{DateTo} ) {
        $Self->{LastError} = 'Translate:AdminTimeAccountingReportInvalidFilter';
        return;
    }

    for my $Name (qw(AgentID CustomerID QueueID ActivityTypeID)) {
        my $Value = exists $Request->{$Name} ? $Request->{$Name} : 0;
        $Value = 0 if !defined $Value || $Value eq '';
        if ( $Value !~ m{\A\d+\z} ) {
            $Self->{LastError} = 'Translate:AdminTimeAccountingReportInvalidFilter';
            return;
        }
        $Filter->{$Name} = 0 + $Value;
    }

    my $Billing = exists $Request->{Billing} ? $Request->{Billing} : 'all';
    if ( $Billing !~ m{\A(?:all|billable|non_billable)\z} ) {
        $Self->{LastError} = 'Translate:AdminTimeAccountingReportInvalidFilter';
        return;
    }
    $Filter->{Billing} = $Billing;

    return $Filter;
}

sub OptionLists {
    my ($Self) = @_;

    my $Agents = $Self->{DB}->SelectAll(
        'SELECT id, login, firstname, lastname, is_active
         FROM user_account
         WHERE account_type = "agent"
         ORDER BY lastname ASC, firstname ASC, login ASC, id ASC'
    );
    my $Customers = $Self->{DB}->SelectAll(
        'SELECT id, customer_number, name, active
         FROM customer
         ORDER BY name ASC, customer_number ASC, id ASC'
    );
    my $Queues = $Self->{DB}->SelectAll(
        'SELECT id, full_name, active
         FROM ticket_queue
         ORDER BY sort_order ASC, full_name ASC, id ASC'
    );
    my $Activities = $Self->{DB}->SelectAll(
        'SELECT id, name, active
         FROM time_accounting_activity_type
         ORDER BY sort_order ASC, name ASC, id ASC'
    );

    if ( !defined $Agents || !defined $Customers || !defined $Queues || !defined $Activities ) {
        $Self->{LastError} = $Self->{DB}->Error() || 'Translate:AdminTimeAccountingReportLoadFailed';
        return;
    }

    return {
        Agents     => $Agents,
        Customers  => $Customers,
        Queues     => $Queues,
        Activities => $Activities,
    };
}

sub ReportGet {
    my ( $Self, %Param ) = @_;
    my $Filter = $Param{Filter} || return;
    my $Limit = defined $Param{Limit} ? $Param{Limit} : 500;

    $Self->{LastError} = '';

    my $Summary = $Self->_SummaryGet( Filter => $Filter );
    return if !$Summary;

    my $AgentGroups = $Self->_GroupList( Filter => $Filter, GroupBy => 'agent' );
    return if !defined $AgentGroups;
    my $CustomerGroups = $Self->_GroupList( Filter => $Filter, GroupBy => 'customer' );
    return if !defined $CustomerGroups;
    my $ActivityGroups = $Self->_GroupList( Filter => $Filter, GroupBy => 'activity' );
    return if !defined $ActivityGroups;
    my $Entries = $Self->EntryList( Filter => $Filter, Limit => $Limit );
    return if !defined $Entries;

    return {
        Summary        => $Summary,
        AgentGroups    => $AgentGroups,
        CustomerGroups => $CustomerGroups,
        ActivityGroups => $ActivityGroups,
        Entries        => $Entries,
        DetailLimited  => $Limit && ( $Summary->{entry_count} || 0 ) > $Limit ? 1 : 0,
    };
}

sub EntryList {
    my ( $Self, %Param ) = @_;
    my $Filter = $Param{Filter} || return;
    my $Limit = defined $Param{Limit} ? $Param{Limit} : 500;
    $Limit = 0 if $Limit !~ m{\A\d+\z};

    my ( $Where, @Bind ) = $Self->_WhereBuild( Filter => $Filter );
    my $SQL =
        'SELECT
            ta.id,
            ta.ticket_id,
            ta.ticket_article_id,
            ta.agent_user_id,
            ta.activity_type_id,
            ta.correction_of_time_accounting_id,
            ta.work_date,
            ta.duration_minutes,
            ta.is_billable,
            ta.source,
            ta.description,
            ta.created_at,
            t.ticket_number,
            t.title AS ticket_title,
            COALESCE(NULLIF(TRIM(CONCAT(COALESCE(ua.firstname, ""), " ", COALESCE(ua.lastname, ""))), ""), ua.login, "-") AS agent_name,
            ua.login AS agent_login,
            COALESCE(at.name, "") AS activity_type_name,
            COALESCE(tq.full_name, "") AS queue_name,
            COALESCE(c.name, "") AS customer_name,
            COALESCE(c.customer_number, "") AS customer_number,
            tc.id AS cancellation_id,
            tc.reason AS cancellation_reason,
            tc.cancelled_at,
            tc.replacement_time_accounting_id,
            COALESCE(NULLIF(TRIM(CONCAT(COALESCE(cua.firstname, ""), " ", COALESCE(cua.lastname, ""))), ""), cua.login, "") AS cancelled_by_name
         ' . $Self->_Joins() . '
         WHERE ' . $Where . '
         ORDER BY ta.work_date DESC, ta.created_at DESC, ta.id DESC';
    $SQL .= ' LIMIT ' . int($Limit) if $Limit;

    my $Rows = $Self->{DB}->SelectAll( $SQL, @Bind );
    if ( !defined $Rows ) {
        $Self->{LastError} = $Self->{DB}->Error() || 'Translate:AdminTimeAccountingReportLoadFailed';
        return;
    }

    return $Rows;
}

sub _SummaryGet {
    my ( $Self, %Param ) = @_;
    my ( $Where, @Bind ) = $Self->_WhereBuild( Filter => $Param{Filter} );

    my $Row = $Self->{DB}->SelectRow(
        'SELECT
            COUNT(*) AS entry_count,
            COALESCE(SUM(CASE WHEN tc.id IS NULL THEN 1 ELSE 0 END), 0) AS active_entry_count,
            COALESCE(SUM(CASE WHEN tc.id IS NOT NULL THEN 1 ELSE 0 END), 0) AS cancelled_entry_count,
            COALESCE(SUM(CASE WHEN tc.id IS NULL THEN ta.duration_minutes ELSE 0 END), 0) AS total_minutes,
            COALESCE(SUM(CASE WHEN tc.id IS NULL AND ta.is_billable = 1 THEN ta.duration_minutes ELSE 0 END), 0) AS billable_minutes,
            COALESCE(SUM(CASE WHEN tc.id IS NULL AND ta.is_billable = 0 THEN ta.duration_minutes ELSE 0 END), 0) AS non_billable_minutes
         ' . $Self->_Joins() . '
         WHERE ' . $Where,
        @Bind,
    );

    if ( !defined $Row ) {
        $Self->{LastError} = $Self->{DB}->Error() || 'Translate:AdminTimeAccountingReportLoadFailed';
        return;
    }

    return $Row;
}

sub _GroupList {
    my ( $Self, %Param ) = @_;
    my $GroupBy = $Param{GroupBy} || '';
    my %Definition = (
        agent => {
            Key   => 'ta.agent_user_id',
            Label => 'COALESCE(NULLIF(TRIM(CONCAT(COALESCE(ua.firstname, ""), " ", COALESCE(ua.lastname, ""))), ""), ua.login, "-")',
        },
        customer => {
            Key   => 'COALESCE(c.id, 0)',
            Label => 'COALESCE(NULLIF(c.name, ""), "-")',
        },
        activity => {
            Key   => 'COALESCE(at.id, 0)',
            Label => 'COALESCE(NULLIF(at.name, ""), "-")',
        },
    );
    return if !$Definition{$GroupBy};

    my ( $Where, @Bind ) = $Self->_WhereBuild( Filter => $Param{Filter} );
    my $Key = $Definition{$GroupBy}->{Key};
    my $Label = $Definition{$GroupBy}->{Label};
    my $Rows = $Self->{DB}->SelectAll(
        'SELECT
            ' . $Key . ' AS group_id,
            ' . $Label . ' AS group_label,
            COUNT(*) AS entry_count,
            COALESCE(SUM(ta.duration_minutes), 0) AS total_minutes,
            COALESCE(SUM(CASE WHEN ta.is_billable = 1 THEN ta.duration_minutes ELSE 0 END), 0) AS billable_minutes,
            COALESCE(SUM(CASE WHEN ta.is_billable = 0 THEN ta.duration_minutes ELSE 0 END), 0) AS non_billable_minutes
         ' . $Self->_Joins() . '
         WHERE ' . $Where . ' AND tc.id IS NULL
         GROUP BY ' . $Key . ', ' . $Label . '
         ORDER BY total_minutes DESC, group_label ASC',
        @Bind,
    );

    if ( !defined $Rows ) {
        $Self->{LastError} = $Self->{DB}->Error() || 'Translate:AdminTimeAccountingReportLoadFailed';
        return;
    }

    return $Rows;
}

sub _WhereBuild {
    my ( $Self, %Param ) = @_;
    my $Filter = $Param{Filter} || {};
    my @Where = ( 'ta.work_date >= ?', 'ta.work_date <= ?' );
    my @Bind = ( $Filter->{DateFrom}, $Filter->{DateTo} );

    if ( $Filter->{AgentID} ) {
        push @Where, 'ta.agent_user_id = ?';
        push @Bind, $Filter->{AgentID};
    }
    if ( $Filter->{CustomerID} ) {
        push @Where, 'COALESCE(ta.customer_id_snapshot, t.customer_id) = ?';
        push @Bind, $Filter->{CustomerID};
    }
    if ( $Filter->{QueueID} ) {
        push @Where, 'COALESCE(ta.queue_id_snapshot, t.queue_id) = ?';
        push @Bind, $Filter->{QueueID};
    }
    if ( $Filter->{ActivityTypeID} ) {
        push @Where, 'ta.activity_type_id = ?';
        push @Bind, $Filter->{ActivityTypeID};
    }
    if ( ( $Filter->{Billing} || '' ) eq 'billable' ) {
        push @Where, 'ta.is_billable = 1';
    }
    elsif ( ( $Filter->{Billing} || '' ) eq 'non_billable' ) {
        push @Where, 'ta.is_billable = 0';
    }

    return ( join( ' AND ', @Where ), @Bind );
}

sub _Joins {
    return
        'FROM ticket_time_accounting ta
         INNER JOIN ticket t ON t.id = ta.ticket_id
         INNER JOIN user_account ua ON ua.id = ta.agent_user_id
         LEFT JOIN time_accounting_activity_type at ON at.id = ta.activity_type_id
         LEFT JOIN ticket_queue tq ON tq.id = COALESCE(ta.queue_id_snapshot, t.queue_id)
         LEFT JOIN customer c ON c.id = COALESCE(ta.customer_id_snapshot, t.customer_id)
         LEFT JOIN ticket_time_accounting_cancellation tc ON tc.time_accounting_id = ta.id
         LEFT JOIN user_account cua ON cua.id = tc.cancelled_by_user_id';
}

sub _DateValid {
    my ( $Self, $Value ) = @_;
    return if !defined $Value || $Value !~ m{\A\d{4}-\d{2}-\d{2}\z};

    my $Parsed = eval { Time::Piece->strptime( $Value, '%Y-%m-%d' ) };
    return if !$Parsed;
    return $Parsed->strftime('%Y-%m-%d') eq $Value ? 1 : 0;
}

1;
