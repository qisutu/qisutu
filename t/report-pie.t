#!/usr/bin/env perl

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

use strict;
use warnings;
use utf8;

use FindBin;
use lib "$FindBin::Bin/../core/system", "$FindBin::Bin/../core/module", "$FindBin::Bin/../core/config", "$FindBin::Bin/../core/cpan-lib";
use Test::More;
use JSON::PP;

use QisutuReportChart;
use QisutuReportBuilder;
use QisutuReportScheduler;
use Reports;

my $Chart = QisutuReportChart->new();
sub Result {
    my ( $Keys, $Values, %Options ) = @_;
    return {
        configuration => { source => $Options{source} || 'tickets', chart_type => 'pie', group_by => $Options{group_by} || 'created_month', metrics => $Keys },
        metrics => [ map { { key => $_, label => $_, format => $Options{format} || 'number' } } @{$Keys} ],
        rows => [ { label => '2026-08', values => $Values } ],
        group => { label_key => 'ReportGroupCreatedMonth' }, details => { columns => [], rows => [] },
    };
}
sub Pie {
    my ($Result) = @_;
    return $Chart->PieData( Result => $Result, Translate => sub { return $_[0] eq 'ReportPieOther' ? 'Übrige' : $_[0]; } );
}

my $Screenshot = Result( [qw(ticket_count closed_count)], [49,12] );
$Screenshot->{metrics}->[0]->{label} = 'Tickets';
$Screenshot->{metrics}->[1]->{label} = 'Geschlossene Tickets';
my $Pie = Pie($Screenshot);
is_deeply( $Pie->{values}, [12,37], '49 total and 12 closed become 12 closed plus 37 remaining' );
is_deeply( $Pie->{labels}, ['Geschlossene Tickets','Übrige'], 'pie distinguishes the selected part from the localized remainder' );
is( $Pie->{values}->[0]+$Pie->{values}->[1], 49, 'pie denominator is 49, never 61' );
isnt( $Pie->{colors}->[0], $Pie->{colors}->[1], 'different portions receive different colors' );
is( $Pie->{format}, 'number', 'ticket slices retain count formatting' );

$Pie = Pie( Result([qw(closed_count ticket_count)],[12,49]) );
is_deeply( $Pie->{values}, [12,37], 'reversing metric selection does not duplicate the total' );
$Pie = Pie( Result([qw(ticket_count closed_count)],[49,12],group_by=>'none') );
is_deeply( $Pie->{values}, [12,37], 'ungrouped results produce the same part-whole split' );

my $Grouped = Result([qw(ticket_count closed_count)],[49,12]);
push @{ $Grouped->{rows} }, {label=>'2026-09',values=>[10,3]};
$Pie = Pie($Grouped);
is_deeply( $Pie->{values}, [12,37,3,7], 'multiple groups become disjoint slices of a single pie' );
is_deeply( $Pie->{labels}, ['2026-08 · closed_count','2026-08 · Übrige','2026-09 · closed_count','2026-09 · Übrige'], 'multiple groups remain identifiable in the pie legend' );
is( scalar @{ $Pie->{colors} }, 4, 'every group and category combination has a slice color' );

my $OneMetric = Result(['ticket_count'],[49]);
push @{ $OneMetric->{rows} }, {label=>'2026-09',values=>[12]};
$Pie = Pie($OneMetric);
is_deeply( $Pie->{values}, [49,12], 'one metric uses groups as pie slices' );
is_deeply( $Pie->{labels}, ['2026-08','2026-09'], 'one metric labels slices with the group values' );
$Pie = Pie( Result(['ticket_count'],[49],group_by=>'none') );
is_deeply( $Pie->{values}, [49], 'one ungrouped metric has one real slice' );
is_deeply( $Pie->{labels}, ['ticket_count'], 'one ungrouped metric uses its own label' );

$Pie = Pie( Result([qw(open_count closed_count)],[37,12]) );
is_deeply( $Pie->{values}, [37,12], 'known disjoint states can be compared without a separately selected total' );
$Pie = Pie( Result([qw(ticket_count open_count closed_count)],[49,37,12]) );
is_deeply( $Pie->{values}, [37,12], 'a selected total is not added to its complete state partition' );
$Pie = Pie( Result([qw(ticket_count new_count closed_count)],[49,5,12]) );
is_deeply( $Pie->{values}, [5,12,32], 'new and closed are disjoint parts and leave the correct remainder' );
$Pie = Pie( Result([qw(open_count new_count)],[37,5]) );
is_deeply( $Pie->{values}, [5,32], 'new tickets are treated as a subset of open tickets' );
$Pie = Pie( Result([qw(ticket_count escalated_count)],[49,3]) );
is_deeply( $Pie->{values}, [3,46], 'one escalation subset and total form a valid partition' );
$Pie = Pie( Result([qw(total_minutes billable_minutes)],[120,90],source=>'time',format=>'minutes') );
is_deeply( $Pie->{values}, [90,30], 'time accounting totals are split into billable and remaining minutes' );
is( $Pie->{format}, 'minutes', 'time accounting slice values retain minute formatting' );
$Pie = Pie( Result([qw(total_minutes billable_minutes non_billable_minutes)],[120,90,30],source=>'time',format=>'minutes') );
is_deeply( $Pie->{values}, [90,30], 'the total is omitted from a complete time accounting partition' );
$Pie = Pie( Result([qw(article_count internal_count)],[20,8],source=>'articles') );
is_deeply( $Pie->{values}, [8,12], 'article totals can be partitioned by internal articles' );

for my $Case (
    [ [qw(escalated_count breached_count)], [10,8], 'tickets' ],
    [ [qw(ticket_count escalated_count breached_count)], [49,10,8], 'tickets' ],
    [ [qw(ticket_count avg_solution)], [49,12], 'tickets' ],
    [ [qw(article_count distinct_tickets)], [20,8], 'articles' ],
    [ [qw(internal_count customer_article_count)], [5,8], 'articles' ],
    [ [qw(entry_count total_minutes)], [5,120], 'time' ],
) {
    ok( !Pie( Result($Case->[0],$Case->[1],source=>$Case->[2]) ), 'overlapping or incompatible measures are rejected: '.join(',',@{$Case->[0]}) );
    is( $Chart->Error(), 'Translate:ReportErrorPieMetrics', 'incompatible measures return the translated validation error' );
}
for my $Values ( [49,50], [49,-1], [49,undef], [49,'NaN'], [49,'Inf'] ) {
    ok( !Pie( Result([qw(ticket_count closed_count)],$Values) ), 'invalid part/whole values do not create a misleading pie' );
}
$Pie = Pie( Result([qw(ticket_count closed_count)],[0,0]) );
is_deeply( $Pie->{values}, [0], 'all-zero data keeps the real zero value without an invented remainder' );
my $Empty = Result(['ticket_count'],[0]);
$Empty->{rows} = [];
is_deeply( Pie($Empty), {labels=>[],values=>[],colors=>[],format=>'number'}, 'empty report data returns an empty pie safely' );

{
    package Local::PieDB;
    sub SelectAll { return [] }
}
my $Builder = QisutuReportBuilder->new(DB=>bless({},'Local::PieDB'),Permission=>bless({},'Local::PiePermission'));
my $Default = $Builder->DefaultConfiguration();
for my $Type (qw(pie doughnut)) {
    my $Valid = $Builder->ConfigurationValidate(Configuration=>{%{$Default},chart_type=>$Type,metrics=>[qw(ticket_count closed_count)]});
    is( $Valid->{chart_type}, 'pie', "$Type validates to canonical pie without changing the selected measures" );
}
ok( !$Builder->ReportSave(UserID=>7,Name=>'Invalid pie',Configuration=>{%{$Default},chart_type=>'pie',metrics=>[qw(escalated_count breached_count)]}), 'saving incompatible pie metrics fails before persistence' );
is( $Builder->Error(), 'Translate:ReportErrorPieMetrics', 'save failure explains incompatible pie metrics' );
my $Bar = $Builder->ConfigurationValidate(Configuration=>{%{$Default},chart_type=>'bar',metrics=>[qw(escalated_count breached_count)]});
is( $Bar->{chart_type}, 'bar', 'other diagram types still support overlapping metrics' );
ok( grep( {$_->{key} eq 'pie' && $_->{label_key} eq 'ReportChartPie'} @{$Builder->Catalog()->{chart_types}} ), 'catalog exposes the pie chart selection' );
ok( !grep( {$_->{key} eq 'doughnut'} @{$Builder->Catalog()->{chart_types}} ), 'catalog no longer offers ring charts' );

{
    package Local::PieOutput;
    sub Translate { my($Self,%Param)=@_;return $Self->{Translations}->{$Param{Key}} || $Param{Key}; }
}
my $Translations = do "$FindBin::Bin/../core/language/de.pm";
my $Reports = Reports->new(Config=>{},Output=>bless({Translations=>$Translations},'Local::PieOutput'));
my $Scheduler = QisutuReportScheduler->new(Config=>{Paths=>{Language=>"$FindBin::Bin/../core/language"}});
my $Localized = Result([qw(ticket_count closed_count)],[49,12]);
$Localized->{metrics}->[0]->{label_key} = 'ReportMetricTicketCount';
$Localized->{metrics}->[1]->{label_key} = 'ReportMetricClosedCount';
my $Scheduled = JSON::PP->new->decode(JSON::PP->new->encode($Localized));
$Scheduled->{configuration}->{chart_type} = 'doughnut';
$Reports->_ResultTranslate(Result=>$Localized,Language=>'de');
$Scheduler->_ResultTranslate(Result=>$Scheduled,Language=>'de');
is_deeply( $Localized->{pie}->{labels}, ['Geschlossene Tickets','Übrige'], 'interactive reports prepare fully translated pie labels' );
is_deeply( $Scheduled->{pie}, $Localized->{pie}, 'scheduled exports use the exact same translated pie data' );
is( $Scheduled->{configuration}->{chart_type}, 'pie', 'scheduled legacy ring reports become full pie charts' );

done_testing();
