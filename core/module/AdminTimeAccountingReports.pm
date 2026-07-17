# Qisutu - Open Source Ticket System
# Copyright (C) 2026 Franziska Steps
# SPDX-License-Identifier: AGPL-3.0-or-later

package AdminTimeAccountingReports;

use strict;
use warnings;
use utf8;

use QisutuTimeAccountingReport;

sub new {
    my ( $Class, %Param ) = @_;
    my $Self = {
        Config  => $Param{Config},
        DB      => $Param{DB},
        Output  => $Param{Output},
        Program => $Param{Program},
    };
    bless $Self, $Class;
    return $Self;
}

sub Run {
    my ( $Self, %Param ) = @_;
    my $Request  = $Param{Request} || {};
    my $Language = $Request->{Language} || $Self->{Config}->{Language}->{Default} || 'en';
    my $Object   = QisutuTimeAccountingReport->new( Config => $Self->{Config}, DB => $Self->{DB} );
    my $Filter   = $Object->FilterParse( Request => $Request );
    my $Error    = '';

    if (!$Filter) {
        $Error  = $Object->Error() || 'Translate:AdminTimeAccountingReportInvalidFilter';
        $Filter = $Object->FilterDefault();
    }

    if ( !$Error && ( $Request->{Action} || '' ) eq 'ExportCSV' ) {
        my $Entries = $Object->EntryList( Filter => $Filter, Limit => 0 );
        if ( defined $Entries ) {
            return {
                Response => $Self->_CSVResponse(
                    Entries  => $Entries,
                    Filter   => $Filter,
                    Language => $Language,
                ),
            };
        }
        $Error = $Object->Error() || 'Translate:AdminTimeAccountingReportLoadFailed';
    }

    my $Options = $Object->OptionLists();
    if (!$Options) {
        $Error ||= $Object->Error() || 'Translate:AdminTimeAccountingReportLoadFailed';
        $Options = { Agents => [], Customers => [], Queues => [], Activities => [] };
    }

    my $Report = $Object->ReportGet( Filter => $Filter, Limit => 500 );
    if (!$Report) {
        $Error ||= $Object->Error() || 'Translate:AdminTimeAccountingReportLoadFailed';
        $Report = {
            Summary => {}, AgentGroups => [], CustomerGroups => [], ActivityGroups => [], Entries => [], DetailLimited => 0,
        };
    }

    $Self->_OptionsPrepare( Options => $Options, Filter => $Filter );
    $Self->_ReportPrepare( Report => $Report );

    my $Summary = $Report->{Summary} || {};
    return {
        Template => 'AdminTimeAccountingReports.tt',
        Data => {
            PageTitle          => 'Translate:AdminTimeAccountingReportTitle',
            ProgramTitle       => 'Translate:AdminTimeAccountingReportTitle',
            ProgramDescription => 'Translate:AdminTimeAccountingReportDescription',
            ErrorMessage       => $Error,
            ErrorClass         => $Error ? '' : 'qisutu-hidden',
            FilterDateFrom     => $Filter->{DateFrom},
            FilterDateTo       => $Filter->{DateTo},
            FilterBillingAllSelected         => $Filter->{Billing} eq 'all' ? 'selected' : '',
            FilterBillingBillableSelected    => $Filter->{Billing} eq 'billable' ? 'selected' : '',
            FilterBillingNonBillableSelected => $Filter->{Billing} eq 'non_billable' ? 'selected' : '',
            AgentOptions       => $Options->{Agents},
            CustomerOptions    => $Options->{Customers},
            QueueOptions       => $Options->{Queues},
            ActivityOptions    => $Options->{Activities},
            ExportURL          => 'index.pl?Page=AdminTimeAccountingReports;Action=ExportCSV;' . $Self->_FilterQuery($Filter),
            TotalDuration      => $Self->_Duration( $Summary->{total_minutes} ),
            BillableDuration   => $Self->_Duration( $Summary->{billable_minutes} ),
            NonBillableDuration => $Self->_Duration( $Summary->{non_billable_minutes} ),
            ActiveEntryCount   => 0 + ( $Summary->{active_entry_count} || 0 ),
            CancelledEntryCount => 0 + ( $Summary->{cancelled_entry_count} || 0 ),
            EntryCount         => 0 + ( $Summary->{entry_count} || 0 ),
            AgentGroups        => $Report->{AgentGroups},
            CustomerGroups     => $Report->{CustomerGroups},
            ActivityGroups     => $Report->{ActivityGroups},
            EntryList          => $Report->{Entries},
            HasEntries         => @{ $Report->{Entries} || [] } ? 1 : 0,
            DetailLimitedClass => $Report->{DetailLimited} ? '' : 'qisutu-hidden',
        },
    };
}

sub _OptionsPrepare {
    my ( $Self, %Param ) = @_;
    my $Options = $Param{Options} || {};
    my $Filter  = $Param{Filter} || {};

    for my $Row ( @{ $Options->{Agents} || [] } ) {
        my $Name = join ' ', grep {$_} ( $Row->{firstname}, $Row->{lastname} );
        $Name ||= $Row->{login} || '-';
        $Name .= ' (' . $Row->{login} . ')' if $Row->{login} && $Name ne $Row->{login};
        $Row->{label} = $Name;
        $Row->{selected} = ( $Row->{id} || 0 ) == ( $Filter->{AgentID} || 0 ) ? 'selected' : '';
    }
    for my $Row ( @{ $Options->{Customers} || [] } ) {
        $Row->{label} = $Row->{name} || $Row->{customer_number} || '-';
        $Row->{selected} = ( $Row->{id} || 0 ) == ( $Filter->{CustomerID} || 0 ) ? 'selected' : '';
    }
    for my $Row ( @{ $Options->{Queues} || [] } ) {
        $Row->{label} = $Row->{full_name} || '-';
        $Row->{selected} = ( $Row->{id} || 0 ) == ( $Filter->{QueueID} || 0 ) ? 'selected' : '';
    }
    for my $Row ( @{ $Options->{Activities} || [] } ) {
        $Row->{label} = $Row->{name} || '-';
        $Row->{selected} = ( $Row->{id} || 0 ) == ( $Filter->{ActivityTypeID} || 0 ) ? 'selected' : '';
    }

    return;
}

sub _ReportPrepare {
    my ( $Self, %Param ) = @_;
    my $Report = $Param{Report} || {};

    for my $ListName (qw(AgentGroups CustomerGroups ActivityGroups)) {
        for my $Row ( @{ $Report->{$ListName} || [] } ) {
            $Row->{entry_count} = 0 + ( $Row->{entry_count} || 0 );
            $Row->{total_duration} = $Self->_Duration( $Row->{total_minutes} );
            $Row->{billable_duration} = $Self->_Duration( $Row->{billable_minutes} );
            $Row->{non_billable_duration} = $Self->_Duration( $Row->{non_billable_minutes} );
        }
    }

    for my $Row ( @{ $Report->{Entries} || [] } ) {
        $Row->{duration_label} = $Self->_Duration( $Row->{duration_minutes} );
        $Row->{billing_label} = $Row->{is_billable} ? 'Translate:TimeAccountingBillableYes' : 'Translate:TimeAccountingBillableNo';
        $Row->{status_label} = $Row->{cancellation_id} ? 'Translate:TimeAccountingCancelled' : 'Translate:AdminTimeAccountingReportActive';
        $Row->{row_class} = $Row->{cancellation_id} ? 'qisutu-time-report-entry-cancelled' : '';
        $Row->{ticket_url} = 'index.pl?Page=AgentTicketZoom;TicketID=' . ( $Row->{ticket_id} || 0 );
        $Row->{customer_name} ||= 'Translate:AdminTimeAccountingReportUnknownCustomer';
        $Row->{queue_name} ||= 'Translate:AdminTimeAccountingReportUnknownQueue';
        $Row->{activity_type_name} ||= 'Translate:AdminTimeAccountingReportUnknownActivity';
        $Row->{description} = '-' if !defined $Row->{description} || $Row->{description} eq '';
        $Row->{cancellation_reason} = '' if !defined $Row->{cancellation_reason};
        $Row->{cancellation_reason} = '-' if $Row->{cancellation_id} && $Row->{cancellation_reason} eq '';
        my @CancellationMeta;
        push @CancellationMeta, $Row->{cancelled_at} if $Row->{cancelled_at};
        push @CancellationMeta, $Row->{cancelled_by_name} if $Row->{cancelled_by_name};
        $Row->{cancellation_meta} = join ' · ', @CancellationMeta;
    }

    return;
}

sub _CSVResponse {
    my ( $Self, %Param ) = @_;
    my $Entries  = $Param{Entries} || [];
    my $Filter   = $Param{Filter} || {};
    my $Language = $Param{Language} || 'en';
    my @HeaderKeys = qw(
        TimeAccountingDate Ticket TimeAccountingAgent AdminTimeAccountingReportCustomer
        AdminTimeAccountingReportQueue TimeAccountingActivityType TimeAccountingDuration
        AdminTimeAccountingReportDurationMinutes TimeAccountingBilling TimeAccountingDescription
        AdminTimeAccountingReportStatus AdminTimeAccountingReportSource
        TimeAccountingCorrectionReason AdminTimeAccountingReportCancelledAt
        AdminTimeAccountingReportCancelledBy AdminTimeAccountingReportReplacementEntry
        AdminTimeAccountingReportCorrectionOf
    );
    my @Lines = ( join ';', map { $Self->_CSVField( $Self->_T( $_, $Language ) ) } @HeaderKeys );

    for my $Row ( @{$Entries} ) {
        my @Values = (
            $Row->{work_date},
            $Row->{ticket_number},
            $Row->{agent_name},
            $Row->{customer_name} || $Self->_T( 'AdminTimeAccountingReportUnknownCustomer', $Language ),
            $Row->{queue_name} || $Self->_T( 'AdminTimeAccountingReportUnknownQueue', $Language ),
            $Row->{activity_type_name} || $Self->_T( 'AdminTimeAccountingReportUnknownActivity', $Language ),
            $Self->_Duration( $Row->{duration_minutes} ),
            0 + ( $Row->{duration_minutes} || 0 ),
            $Self->_T( $Row->{is_billable} ? 'TimeAccountingBillableYes' : 'TimeAccountingBillableNo', $Language ),
            $Row->{description},
            $Self->_T( $Row->{cancellation_id} ? 'TimeAccountingCancelled' : 'AdminTimeAccountingReportActive', $Language ),
            $Row->{source},
            $Row->{cancellation_reason},
            $Row->{cancelled_at},
            $Row->{cancelled_by_name},
            $Row->{replacement_time_accounting_id},
            $Row->{correction_of_time_accounting_id},
        );
        push @Lines, join ';', map { $Self->_CSVField($_) } @Values;
    }

    my $Filename = 'qisutu-time-accounting-' . ( $Filter->{DateFrom} || 'from' ) . '-' . ( $Filter->{DateTo} || 'to' ) . '.csv';
    my $Body = chr(0xFEFF) . join( "\r\n", @Lines ) . "\r\n";
    return $Self->{Output}->Response(
        Body        => $Body,
        ContentType => 'text/csv; charset=UTF-8',
        Headers     => [ 'Content-Disposition: attachment; filename="' . $Filename . '"' ],
    );
}

sub _CSVField {
    my ( $Self, $Value ) = @_;
    $Value = '' if !defined $Value;
    $Value = "'" . $Value if $Value =~ m{\A[\t\r ]*[=+\-\@]};
    $Value =~ s{"}{""}g;
    return '"' . $Value . '"';
}

sub _FilterQuery {
    my ( $Self, $Filter ) = @_;
    return join ';', map { $_ . '=' . $Self->_URLEscape( $Filter->{$_} ) }
        qw(DateFrom DateTo AgentID CustomerID QueueID ActivityTypeID Billing);
}

sub _URLEscape {
    my ( $Self, $Value ) = @_;
    $Value = '' if !defined $Value;
    use bytes;
    $Value =~ s{([^A-Za-z0-9_.~-])}{sprintf '%%%02X', ord $1}eg;
    return $Value;
}

sub _Duration {
    my ( $Self, $Minutes ) = @_;
    $Minutes = 0 if !defined $Minutes || $Minutes !~ m{\A\d+\z};
    return int( $Minutes / 60 ) . ':' . sprintf( '%02d', $Minutes % 60 ) . ' h';
}

sub _T {
    my ( $Self, $Key, $Language ) = @_;
    return $Self->{Output}->Translate( Key => $Key, Language => $Language );
}

1;
