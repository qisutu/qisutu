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

package QisutuReportChart;

use strict;
use warnings;
use utf8;

use POSIX qw(isfinite);
use Scalar::Util qw(looks_like_number);

sub new { return bless { LastError => '' }, shift; }
sub Error { return $_[0]->{LastError} || ''; }

sub MetricsCompatible {
    my ( $Self, %Param ) = @_;
    return $Self->_Plan( Configuration => $Param{Configuration} ) ? 1 : 0;
}

sub PieData {
    my ( $Self, %Param ) = @_;
    $Self->{LastError} = '';
    my $Result = $Param{Result} || {};
    my $Configuration = $Result->{configuration} || {};
    my $Metrics = $Result->{metrics} || [];
    my @Keys = map { $_->{key} || '' } @{$Metrics};
    my $Plan = $Self->_Plan( Configuration => { %{$Configuration}, metrics => \@Keys } ) || return;
    my $Rows = $Result->{rows} || [];
    my $Translate = $Param{Translate};
    my $Other = ref $Translate eq 'CODE' ? $Translate->('ReportPieOther') : 'Other';
    my $Pie = { labels => [], values => [], colors => [], format => $Metrics->[0]->{format} || 'number' };
    my $Grouped = ( $Configuration->{group_by} || '' ) ne 'none';
    for my $Row ( @{$Rows} ) {
        my @Values;
        for my $Index ( 0 .. $#{$Metrics} ) {
            my $Value = $Row->{values}->[$Index];
            return $Self->_Fail() if !defined $Value || !looks_like_number($Value) || !isfinite($Value) || $Value < 0;
            push @Values, 0 + $Value;
        }
        for my $Segment ( @{$Plan} ) {
            my $Value = $Values[ $Segment->{index} ];
            $Value -= $Values[$_] for @{ $Segment->{subtract} || [] };
            my $Tolerance = 0.000000001 * ( $Values[ $Segment->{index} ] || 1 );
            return $Self->_Fail() if $Value < -$Tolerance;
            $Value = 0 if $Value < 0;
            next if $Segment->{other} && !$Value;
            my $Metric = $Metrics->[ $Segment->{index} ];
            my $Label = $Segment->{other} ? $Other : $Metric->{label} || $Metric->{label_key} || $Metric->{key} || '';
            if ( @{$Metrics} == 1 ) {
                $Label = $Row->{label} if $Grouped && defined $Row->{label} && $Row->{label} ne '';
            }
            elsif ( $Grouped && @{$Rows} > 1 ) {
                $Label = ( $Row->{label} || '-' ) . ' · ' . $Label;
            }
            push @{ $Pie->{labels} }, $Label;
            push @{ $Pie->{values} }, $Value;
        }
    }
    my @Colors = ('#08789f', '#ef5b3a', '#4eae6c', '#f2b134', '#8259a3', '#28a8a8', '#d35d8c', '#6f7f91');
    $Pie->{colors} = [ map { $Colors[$_ % @Colors] } 0 .. $#{ $Pie->{values} } ];
    return $Pie;
}

sub _Plan {
    my ( $Self, %Param ) = @_;
    $Self->{LastError} = '';
    my $Configuration = $Param{Configuration} || {};
    my $Keys = $Configuration->{metrics};
    return $Self->_Fail() if ref $Keys ne 'ARRAY' || !@{$Keys} || @{$Keys} > 3;
    return [ { index => 0 } ] if @{$Keys} == 1;
    my %Index;
    for my $I ( 0 .. $#{$Keys} ) {
        return $Self->_Fail() if !$Keys->[$I] || exists $Index{ $Keys->[$I] };
        $Index{ $Keys->[$I] } = $I;
    }
    my %Families = (
        tickets => [
            { total => 'ticket_count', parts => [qw(open_count closed_count new_count escalated_count breached_count)],
              disjoint => [ [qw(open_count closed_count)], [qw(new_count closed_count)] ] },
            { total => 'open_count', parts => ['new_count'], disjoint => [] },
        ],
        articles => [
            { total => 'article_count', parts => [qw(internal_count customer_article_count)], disjoint => [] },
        ],
        time => [
            { total => 'total_minutes', parts => [qw(billable_minutes non_billable_minutes)],
              disjoint => [ [qw(billable_minutes non_billable_minutes)] ] },
        ],
    );
    for my $Family ( @{ $Families{ $Configuration->{source} || '' } || [] } ) {
        my %Allowed = map { $_ => 1 } @{ $Family->{parts} };
        my $HasTotal = exists $Index{ $Family->{total} };
        my @Parts = grep { $_ ne $Family->{total} } @{$Keys};
        next if grep { !$Allowed{$_} } @Parts;
        my $Disjoint = @Parts == 1 && $HasTotal;
        for my $Set ( @{ $Family->{disjoint} } ) {
            $Disjoint = 1 if join(',',sort @Parts) eq join(',',sort @{$Set});
        }
        next if !$Disjoint;
        my @Plan = map { { index => $Index{$_} } } @Parts;
        push @Plan, { index => $Index{ $Family->{total} }, subtract => [ map { $Index{$_} } @Parts ], other => 1 } if $HasTotal;
        return \@Plan;
    }
    return $Self->_Fail();
}

sub _Fail {
    my ($Self) = @_;
    $Self->{LastError} = 'Translate:ReportErrorPieMetrics';
    return;
}

1;
