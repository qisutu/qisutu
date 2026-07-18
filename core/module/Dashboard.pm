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

package Dashboard;

use strict;
use warnings;
use utf8;

use JSON::PP qw(encode_json);
use POSIX qw(strftime);
use Time::Local qw(timelocal);

use QisutuDashboard;
use QisutuPermission;
use QisutuTicket;

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

    my $User = $Param{User} || {};

    if ( ( $User->{account_type} || '' ) eq 'customer' ) {
        return $Self->_CustomerRun(%Param);
    }

    return $Self->_AgentRun(%Param);
}

sub _AgentRun {
    my ( $Self, %Param ) = @_;

    my $Request  = $Param{Request} || {};
    my $User     = $Param{User} || {};
    my $Language = $Request->{Language} || 'en';
    my $Filter   = $Self->_FilterClean( Request => $Request );
    my $PermissionObject = QisutuPermission->new(
        Config => $Self->{Config},
        DB     => $Self->{DB},
    );
    my $DashboardObject = QisutuDashboard->new(
        Config     => $Self->{Config},
        DB         => $Self->{DB},
        Permission => $PermissionObject,
    );

    my $Queues = $DashboardObject->AgentQueueList( User => $User );
    my %AllowedQueue = map { ( $_->{id} || 0 ) => 1 } @{$Queues};
    if ( $Filter->{QueueID} && !$AllowedQueue{ $Filter->{QueueID} } ) {
        $Filter->{QueueID} = 0;
    }

    for my $Queue ( @{$Queues} ) {
        $Queue->{selected} = ( $Queue->{id} || 0 ) == ( $Filter->{QueueID} || 0 ) ? 'selected' : '';
    }

    my @AllowedQueueIDs = map { $_->{id} || 0 } @{$Queues};
    my $RawData = $DashboardObject->AgentData(
        User            => $User,
        AllowedQueueIDs => \@AllowedQueueIDs,
        QueueID         => $Filter->{QueueID},
        Scope           => $Filter->{Scope},
        DateFrom        => $Filter->{DateFrom},
        DateTo          => $Filter->{DateTo},
    );
    my $DisplayData = $Self->_AgentDataPrepare(
        Data     => $RawData,
        Filter   => $Filter,
        User     => $User,
        Language => $Language,
    );

    if ( ( $Request->{Step} || '' ) eq 'Data' ) {
        return $Self->_JSONResponse( Data => $DisplayData->{ClientData} );
    }

    my $DashboardError = $DashboardObject->Error() || '';
    my $PeriodOptions = $Self->_PeriodOptions(
        Selected => $Filter->{Period},
        Language => $Language,
    );
    my $ScopeOptions = $Self->_ScopeOptions(
        Selected => $Filter->{Scope},
        Language => $Language,
    );
    my $Endpoint = $Self->_DashboardURL(
        Step   => 'Data',
        Filter => $Filter,
    );

    return {
        Template => 'Dashboard.tt',
        Data     => {
            PageTitle          => 'Translate:PageStartTitle',
            IsAgentDashboard   => 1,
            IsCustomerDashboard => 0,
            ProgramTitle       => 'Translate:DashboardTitle',
            ProgramDescription => 'Translate:DashboardAgentIntro',
            Metrics            => $DisplayData->{Metrics},
            StatusRows         => $DisplayData->{StatusRows},
            HasStatusRows      => @{ $DisplayData->{StatusRows} } ? 1 : 0,
            AgeRows            => $DisplayData->{AgeRows},
            TrendRows          => $DisplayData->{TrendRows},
            AttentionTickets   => $DisplayData->{AttentionTickets},
            HasAttentionTickets => @{ $DisplayData->{AttentionTickets} } ? 1 : 0,
            DashboardDataJSON  => $Self->_JSONForHTML( $DisplayData->{ClientData} ),
            DashboardDataEndpoint => $Endpoint,
            GeneratedLabel     => $DisplayData->{ClientData}->{generated_label} || '',
            DashboardResetURL  => 'index.pl?Page=Dashboard',
            DashboardError     => $DashboardError,
            DashboardErrorClass => $DashboardError ? '' : 'qisutu-hidden',
            HasQueueAccess     => @{$Queues} ? 1 : 0,
            QueueOptions       => $Queues,
            PeriodOptions      => $PeriodOptions,
            ScopeOptions       => $ScopeOptions,
            DateFrom           => $Filter->{DateFrom},
            DateTo             => $Filter->{DateTo},
            CustomDateClass    => $Filter->{Period} eq 'custom' ? '' : 'qisutu-hidden',
            CustomDateDisabled => $Filter->{Period} eq 'custom' ? '' : 'disabled',
            AutoRefreshSeconds => 120,
        },
    };
}

sub _CustomerRun {
    my ( $Self, %Param ) = @_;

    my $Request  = $Param{Request} || {};
    my $User     = $Param{User} || {};
    my $Language = $Request->{Language} || 'en';
    my $TicketObject = $Self->_TicketObject();
    my $NewCount = 0;
    my $OpenCount = 0;
    my $PendingCount = 0;
    my $ClosedCount = 0;
    my $TotalCount = 0;
    my $Tickets = [];

    if ($TicketObject) {
        $NewCount     = $TicketObject->TicketListCount( User => $User, View => 'new' );
        $OpenCount    = $TicketObject->TicketListCount( User => $User, View => 'open' );
        $PendingCount = $TicketObject->TicketListCount( User => $User, View => 'pending' );
        $ClosedCount  = $TicketObject->TicketListCount( User => $User, View => 'closed' );
        $TotalCount   = $NewCount + $OpenCount + $PendingCount + $ClosedCount;
        $Tickets = $TicketObject->TicketList(
            User     => $User,
            Limit    => 5,
            ZoomPage => 'CustomerTicketZoom',
            Language => $Language,
            SortBy   => 'changed',
            SortDirection => 'desc',
        );
    }

    my $ListURL = 'index.pl?Page=CustomerTicketList';
    my $Metrics = [
        {
            key   => 'open',
            label => $Self->_Translate( Key => 'DashboardCustomerOpenTickets', Language => $Language ),
            value => $NewCount + $OpenCount + $PendingCount,
            url   => $ListURL,
            class => 'qisutu-dashboard-metric-primary',
        },
        {
            key   => 'pending',
            label => $Self->_Translate( Key => 'DashboardCustomerWaitingTickets', Language => $Language ),
            value => $PendingCount,
            url   => $ListURL,
            class => 'qisutu-dashboard-metric-warning',
        },
        {
            key   => 'total',
            label => $Self->_Translate( Key => 'DashboardCustomerTotalTickets', Language => $Language ),
            value => $TotalCount,
            url   => $ListURL,
            class => 'qisutu-dashboard-metric-neutral',
        },
    ];

    return {
        Template => 'Dashboard.tt',
        Data     => {
            PageTitle            => 'Translate:PageStartTitle',
            IsAgentDashboard     => 0,
            IsCustomerDashboard  => 1,
            ProgramTitle         => 'Translate:DashboardTitle',
            ProgramDescription   => 'Translate:DashboardCustomerIntro',
            Metrics              => $Metrics,
            CustomerTickets      => $Tickets,
            HasCustomerTickets   => @{$Tickets} ? 1 : 0,
            CustomerTicketListURL   => $ListURL,
            CustomerTicketCreateURL => 'index.pl?Page=CustomerTicketCreate',
        },
    };
}

sub _AgentDataPrepare {
    my ( $Self, %Param ) = @_;

    my $Data     = $Param{Data} || {};
    my $Filter   = $Param{Filter} || {};
    my $User     = $Param{User} || {};
    my $Language = $Param{Language} || 'en';
    my $MetricValue = $Data->{metrics} || {};
    my @MetricDefinition = (
        [ open             => 'DashboardKPIOpen',            'all_open',         'qisutu-dashboard-metric-primary' ],
        [ new              => 'DashboardKPINew',             'new',              'qisutu-dashboard-metric-info' ],
        [ unassigned       => 'DashboardKPIUnassigned',      'unassigned',       'qisutu-dashboard-metric-neutral' ],
        [ escalated        => 'DashboardKPIEscalated',       'escalated',        'qisutu-dashboard-metric-danger' ],
        [ warning          => 'DashboardKPIWarning',         'warning',          'qisutu-dashboard-metric-warning' ],
        [ customer_waiting => 'DashboardKPICustomerWaiting', 'customer_response','qisutu-dashboard-metric-customer' ],
    );
    my @Metrics;
    my %ClientMetrics;

    for my $Definition (@MetricDefinition) {
        my ( $Key, $LabelKey, $View, $Class ) = @{$Definition};
        my $URL = $Self->_AgentTicketListURL(
            View   => $View,
            Filter => $Filter,
            User   => $User,
        );
        my $Metric = {
            key   => $Key,
            label => $Self->_Translate( Key => $LabelKey, Language => $Language ),
            value => 0 + ( $MetricValue->{$Key} || 0 ),
            url   => $URL,
            class => $Class,
        };
        push @Metrics, $Metric;
        $ClientMetrics{$Key} = {
            value => $Metric->{value},
            url   => $URL,
        };
    }

    my @StatusRows;
    my @StatusColor = ( '#0ea5e9', '#14b8a6', '#8b5cf6', '#f59e0b', '#64748b', '#ec4899', '#22c55e', '#f97316' );
    my $StatusIndex = 0;
    for my $Status ( @{ $Data->{status} || [] } ) {
        my $View = ( $Status->{state_type} || '' ) eq 'new'
            ? 'new'
            : ( $Status->{state_type} || '' ) eq 'pending'
                ? 'pending'
                : 'open';
        push @StatusRows, {
            label => $Self->_StateLabel( State => $Status->{name}, Language => $Language ),
            value => 0 + ( $Status->{ticket_count} || 0 ),
            url   => $Self->_AgentTicketListURL(
                View    => $View,
                StateID => $Status->{id},
                Filter  => $Filter,
                User    => $User,
            ),
            color => $StatusColor[ $StatusIndex++ % @StatusColor ],
        };
    }

    my %AgeLabelKey = (
        under_8h  => 'DashboardAgeUnder8Hours',
        under_24h => 'DashboardAgeUnder24Hours',
        under_3d  => 'DashboardAgeUnder3Days',
        under_10d => 'DashboardAgeUnder10Days',
        over_10d  => 'DashboardAgeOver10Days',
    );
    my %AgeView = (
        under_8h  => 'age_under_8h',
        under_24h => 'age_under_24h',
        under_3d  => 'age_under_3d',
        under_10d => 'age_under_10d',
        over_10d  => 'age_over_10d',
    );
    my @AgeColor = ( '#38bdf8', '#2dd4bf', '#a3e635', '#fbbf24', '#fb7185' );
    my @AgeRows;
    my $AgeIndex = 0;
    for my $Age ( @{ $Data->{age} || [] } ) {
        push @AgeRows, {
            label => $Self->_Translate( Key => $AgeLabelKey{ $Age->{key} } || 'DashboardAge', Language => $Language ),
            value => 0 + ( $Age->{value} || 0 ),
            url   => $Self->_AgentTicketListURL(
                View          => $AgeView{ $Age->{key} } || 'all_open',
                Filter        => $Filter,
                User          => $User,
                SortBy        => 'age',
                SortDirection => 'desc',
            ),
            color => $AgeColor[ $AgeIndex++ % @AgeColor ],
        };
    }

    my @TrendRows;
    for my $Trend ( @{ $Data->{trend} || [] } ) {
        push @TrendRows, {
            date    => $Trend->{date} || '',
            label   => $Self->_DateLabel( Date => $Trend->{date}, Language => $Language ),
            created => 0 + ( $Trend->{created} || 0 ),
            closed  => 0 + ( $Trend->{closed} || 0 ),
        };
    }

    my @Attention;
    for my $Ticket ( @{ $Data->{attention} || [] } ) {
        my ( $ReasonKey, $ReasonClass ) = $Ticket->{is_escalated}
            ? ( 'DashboardAttentionReasonEscalated', 'qisutu-dashboard-reason-danger' )
            : $Ticket->{is_warning}
                ? ( 'DashboardAttentionReasonWarning', 'qisutu-dashboard-reason-warning' )
                : $Ticket->{is_customer_waiting}
                    ? ( 'DashboardAttentionReasonCustomerWaiting', 'qisutu-dashboard-reason-customer' )
                    : $Ticket->{is_unassigned}
                        ? ( 'DashboardAttentionReasonUnassigned', 'qisutu-dashboard-reason-neutral' )
                        : ( 'DashboardAttentionReasonOld', 'qisutu-dashboard-reason-old' );
        push @Attention, {
            id            => 0 + ( $Ticket->{id} || 0 ),
            ticket_number => $Ticket->{ticket_number} || '',
            title         => $Ticket->{title} || '',
            queue_name    => $Ticket->{queue_full_name} || $Ticket->{queue_name} || '',
            state_name    => $Self->_StateLabel( State => $Ticket->{state_name}, Language => $Language ),
            age           => $Self->_AgeLabel( Minutes => $Ticket->{age_minutes}, Language => $Language ),
            reason        => $Self->_Translate( Key => $ReasonKey, Language => $Language ),
            reason_class  => $ReasonClass,
            url           => 'index.pl?Page=AgentTicketZoom&TicketID=' . ( 0 + ( $Ticket->{id} || 0 ) ),
        };
    }

    my $Generated = $Self->_GeneratedLabel( Language => $Language );
    my $ClientData = {
        metrics => \%ClientMetrics,
        trend => {
            labels  => [ map { $_->{label} } @TrendRows ],
            created => [ map { $_->{created} } @TrendRows ],
            closed  => [ map { $_->{closed} } @TrendRows ],
        },
        status => {
            labels => [ map { $_->{label} } @StatusRows ],
            values => [ map { $_->{value} } @StatusRows ],
            urls   => [ map { $_->{url} } @StatusRows ],
            colors => [ map { $_->{color} } @StatusRows ],
        },
        age => {
            labels => [ map { $_->{label} } @AgeRows ],
            values => [ map { $_->{value} } @AgeRows ],
            urls   => [ map { $_->{url} } @AgeRows ],
            colors => [ map { $_->{color} } @AgeRows ],
        },
        attention => \@Attention,
        generated_label => $Generated,
        labels => {
            created => $Self->_Translate( Key => 'DashboardCreated', Language => $Language ),
            closed  => $Self->_Translate( Key => 'DashboardClosed', Language => $Language ),
            tickets => $Self->_Translate( Key => 'DashboardTickets', Language => $Language ),
            empty_attention => $Self->_Translate( Key => 'DashboardAttentionEmpty', Language => $Language ),
        },
    };

    return {
        Metrics          => \@Metrics,
        StatusRows       => \@StatusRows,
        AgeRows          => \@AgeRows,
        TrendRows        => \@TrendRows,
        AttentionTickets => \@Attention,
        ClientData       => $ClientData,
    };
}

sub _FilterClean {
    my ( $Self, %Param ) = @_;

    my $Request = $Param{Request} || {};
    my $Period = defined $Request->{Period} && $Request->{Period} =~ m{\A(?:1|7|30|90|custom)\z}
        ? $Request->{Period}
        : '30';
    my $Scope = ( $Request->{Scope} || '' ) eq 'personal' ? 'personal' : 'team';
    my $QueueID = defined $Request->{QueueID} && $Request->{QueueID} =~ m{\A\d+\z}
        ? int( $Request->{QueueID} )
        : 0;
    my $Today = strftime( '%Y-%m-%d', localtime(time) );
    my ( $DateFrom, $DateTo );

    if ( $Period eq 'custom' ) {
        $DateFrom = $Self->_DateClean( $Request->{DateFrom} );
        $DateTo   = $Self->_DateClean( $Request->{DateTo} );
        my $FromEpoch = $Self->_DateEpoch($DateFrom);
        my $ToEpoch   = $Self->_DateEpoch($DateTo);
        if ( !defined $FromEpoch || !defined $ToEpoch || $FromEpoch > $ToEpoch || ( $ToEpoch - $FromEpoch ) > 365 * 86_400 ) {
            $Period = '30';
        }
    }

    if ( $Period ne 'custom' ) {
        my $Days = int($Period);
        $DateTo = $Today;
        $DateFrom = strftime( '%Y-%m-%d', localtime( time - ( $Days - 1 ) * 86_400 ) );
    }

    return {
        Period   => $Period,
        Scope    => $Scope,
        QueueID  => $QueueID,
        DateFrom => $DateFrom,
        DateTo   => $DateTo,
    };
}

sub _PeriodOptions {
    my ( $Self, %Param ) = @_;

    my @Definition = (
        [ '1',      'DashboardPeriodToday' ],
        [ '7',      'DashboardPeriod7Days' ],
        [ '30',     'DashboardPeriod30Days' ],
        [ '90',     'DashboardPeriod90Days' ],
        [ 'custom', 'DashboardPeriodCustom' ],
    );

    return [
        map {
            {
                value    => $_->[0],
                label    => $Self->_Translate( Key => $_->[1], Language => $Param{Language} || 'en' ),
                selected => $_->[0] eq ( $Param{Selected} || '' ) ? 'selected' : '',
            }
        } @Definition
    ];
}

sub _ScopeOptions {
    my ( $Self, %Param ) = @_;

    my @Definition = (
        [ 'team',     'DashboardScopeTeam' ],
        [ 'personal', 'DashboardScopePersonal' ],
    );

    return [
        map {
            {
                value    => $_->[0],
                label    => $Self->_Translate( Key => $_->[1], Language => $Param{Language} || 'en' ),
                selected => $_->[0] eq ( $Param{Selected} || '' ) ? 'selected' : '',
            }
        } @Definition
    ];
}

sub _DashboardURL {
    my ( $Self, %Param ) = @_;

    my $Filter = $Param{Filter} || {};
    my @Part = ('Page=Dashboard');
    push @Part, 'Step=' . $Self->_URLEncode( $Param{Step} ) if $Param{Step};
    push @Part, 'Period=' . $Self->_URLEncode( $Filter->{Period} || '30' );
    push @Part, 'DateFrom=' . $Self->_URLEncode( $Filter->{DateFrom} || '' ) if ( $Filter->{Period} || '' ) eq 'custom';
    push @Part, 'DateTo=' . $Self->_URLEncode( $Filter->{DateTo} || '' ) if ( $Filter->{Period} || '' ) eq 'custom';
    push @Part, 'QueueID=' . $Self->_URLEncode( $Filter->{QueueID} ) if $Filter->{QueueID};
    push @Part, 'Scope=' . $Self->_URLEncode( $Filter->{Scope} || 'team' );

    return 'index.pl?' . join( ';', @Part );
}

sub _AgentTicketListURL {
    my ( $Self, %Param ) = @_;

    my $Filter = $Param{Filter} || {};
    my $User   = $Param{User} || {};
    my @Part = (
        'Page=AgentTicketList',
        'View=' . $Self->_URLEncode( $Param{View} || 'new' ),
    );
    if ( defined $Param{StateID} && $Param{StateID} =~ m{\A\d+\z} && $Param{StateID} > 0 ) {
        push @Part, 'SearchActive=1';
        push @Part, 'SearchStateID=' . $Self->_URLEncode( $Param{StateID} );
    }
    push @Part, 'FilterQueueID=' . $Self->_URLEncode( $Filter->{QueueID} ) if $Filter->{QueueID};
    if ( ( $Filter->{Scope} || '' ) eq 'personal' ) {
        push @Part, 'FilterOwnerID=' . $Self->_URLEncode( $User->{user_account_id} || 0 );
    }
    push @Part, 'SortBy=' . $Self->_URLEncode( $Param{SortBy} ) if $Param{SortBy};
    push @Part, 'SortDirection=' . $Self->_URLEncode( $Param{SortDirection} ) if $Param{SortDirection};

    return 'index.pl?' . join( ';', @Part );
}

sub _StateLabel {
    my ( $Self, %Param ) = @_;

    my $State = $Param{State} || '';
    my $Key   = lc $State;
    $Key =~ s{\A\s+|\s+\z}{}g;
    $Key =~ s{\+}{ plus }g;
    $Key =~ s{-}{ minus }g;
    $Key =~ s{[^a-z0-9]+}{_}g;
    $Key =~ s{\A_+|_+\z}{}g;
    return $State if !$Key;

    my $TranslationKey = 'TicketStateName_' . $Key;
    my $Label = $Self->_Translate( Key => $TranslationKey, Language => $Param{Language} || 'en' );

    return $Label eq $TranslationKey ? $State : $Label;
}

sub _DateLabel {
    my ( $Self, %Param ) = @_;

    my $Date = $Param{Date} || '';
    return $Date if $Date !~ m{\A(\d{4})-(\d{2})-(\d{2})\z};
    my ( $Year, $Month, $Day ) = ( $1, $2, $3 );

    return $Month . '/' . $Day if ( $Param{Language} || '' ) eq 'en';
    return $Day . '.' . $Month . '.';
}

sub _AgeLabel {
    my ( $Self, %Param ) = @_;

    my $Minutes = defined $Param{Minutes} && $Param{Minutes} =~ m{\A\d+\z} ? int( $Param{Minutes} ) : 0;
    my $Language = $Param{Language} || 'en';

    if ( $Minutes < 60 ) {
        return $Minutes . ' ' . $Self->_Translate( Key => 'DashboardMinutesShort', Language => $Language );
    }
    if ( $Minutes < 1440 ) {
        return int( $Minutes / 60 ) . ' ' . $Self->_Translate( Key => 'DashboardHoursShort', Language => $Language );
    }

    my $Days  = int( $Minutes / 1440 );
    my $Hours = int( ( $Minutes % 1440 ) / 60 );
    my $Label = $Days . ' ' . $Self->_Translate( Key => 'DashboardDaysShort', Language => $Language );
    $Label .= ' ' . $Hours . ' ' . $Self->_Translate( Key => 'DashboardHoursShort', Language => $Language ) if $Hours;

    return $Label;
}

sub _GeneratedLabel {
    my ( $Self, %Param ) = @_;

    my $Prefix = $Self->_Translate( Key => 'DashboardLastUpdated', Language => $Param{Language} || 'en' );
    return $Prefix . ': ' . strftime( '%d.%m.%Y %H:%M:%S', localtime(time) );
}

sub _DateClean {
    my ( $Self, $Value ) = @_;

    return '' if !defined $Value || $Value !~ m{\A\d{4}-\d{2}-\d{2}\z};
    return $Value;
}

sub _DateEpoch {
    my ( $Self, $Value ) = @_;

    return if !$Value || $Value !~ m{\A(\d{4})-(\d{2})-(\d{2})\z};
    my ( $Year, $Month, $Day ) = ( $1, $2, $3 );
    my $Epoch = eval { timelocal( 0, 0, 12, $Day, $Month - 1, $Year ) };
    return if !defined $Epoch;
    return if strftime( '%Y-%m-%d', localtime($Epoch) ) ne $Value;

    return $Epoch;
}

sub _JSONForHTML {
    my ( $Self, $Data ) = @_;

    my $JSON = encode_json( $Data || {} );
    $JSON =~ s{&}{\\u0026}g;
    $JSON =~ s{<}{\\u003c}g;
    $JSON =~ s{>}{\\u003e}g;
    $JSON =~ s{\x{2028}}{\\u2028}g;
    $JSON =~ s{\x{2029}}{\\u2029}g;

    return $JSON;
}

sub _JSONResponse {
    my ( $Self, %Param ) = @_;

    return {
        Response => $Self->{Output}->Response(
            ContentType => 'application/json; charset=UTF-8',
            Headers     => [ 'Cache-Control: no-store' ],
            Body        => encode_json( $Param{Data} || {} ),
        ),
    };
}

sub _TicketObject {
    my ($Self) = @_;

    return if !$Self->{DB};

    my $PermissionObject = QisutuPermission->new(
        Config => $Self->{Config},
        DB     => $Self->{DB},
    );

    return QisutuTicket->new(
        Config     => $Self->{Config},
        DB         => $Self->{DB},
        Permission => $PermissionObject,
    );
}

sub _Translate {
    my ( $Self, %Param ) = @_;

    return $Self->{Output}->Translate(
        Key      => $Param{Key},
        Language => $Param{Language} || 'en',
    );
}

sub _URLEncode {
    my ( $Self, $Value ) = @_;

    $Value = '' if !defined $Value;
    $Value = "$Value";
    utf8::encode($Value) if utf8::is_utf8($Value);
    $Value =~ s{([^A-Za-z0-9_.~-])}{sprintf '%%%02X', ord($1)}eg;

    return $Value;
}

1;
