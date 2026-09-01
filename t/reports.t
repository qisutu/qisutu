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
use lib "$FindBin::Bin/../core/system", "$FindBin::Bin/../core/config", "$FindBin::Bin/../core/cpan-lib";
use Test::More;

use QisutuReportBuilder;
use QisutuReportPDF;

{
    package Local::ReportPermission;
    sub new { bless {}, shift }
    sub QueueIDList { return [ 4, 8 ] }
    sub UserIsAdmin { return 0 }
}

{
    package Local::ReportDB;
    sub new { bless { Calls=>[], Do=>[], Error=>'' }, shift }
    sub SelectAll {
        my ( $Self, $SQL, @Bind ) = @_;
        push @{ $Self->{Calls} }, [ SelectAll=>$SQL,@Bind ];
        return [
            { id=>2, name=>'support', description=>'Support' },
            { id=>5, name=>'service-desk', description=>'Service Desk' },
        ] if $SQL =~ m{FROM user_group ug};
        return [] if $SQL =~ m{FROM ticket_dynamic_field f};
        return [ { group_key=>'2026-07',group_label=>'2026-07',metric_1=>2 } ] if $SQL =~ m{AS group_key};
        if ( $SQL =~ m{\bAS field_1\b} ) {
            my %Row;
            $Row{'field_'.$_} = $_ == 1 ? '202607180001' : 'Value '.$_ for 1..12;
            return [ \%Row ];
        }
        return [];
    }
    sub SelectRow {
        my ( $Self, $SQL, @Bind ) = @_;
        push @{ $Self->{Calls} }, [ SelectRow=>$SQL,@Bind ];
        return { metric_1=>2 };
    }
    sub Do { my($Self,$SQL,@Bind)=@_;push @{$Self->{Do}},[$SQL,@Bind];return 1 }
    sub Error { return $_[0]->{Error} }
}

my $DB = Local::ReportDB->new();
my $Builder = QisutuReportBuilder->new(
    Config=>{ Language=>{Default=>'de'} }, DB=>$DB, Permission=>Local::ReportPermission->new(),
);

my $Catalog = $Builder->Catalog();
is_deeply( [ map { $_->{key} } @{ $Catalog->{sources} } ], [qw(tickets articles time)], 'three report data sources are available' );
ok( grep( { $_->{key} eq 'sla_compliance' } @{ $Catalog->{sources}->[0]->{metrics} } ), 'ticket SLA metric is available' );
ok( grep( { $_->{key} eq 'total_minutes' } @{ $Catalog->{sources}->[2]->{metrics} } ), 'time accounting metric is available' );

my $Groups = $Builder->GroupList( UserID=>7 );
is_deeply(
    $Groups,
    [
        { id=>2, name=>'support', description=>'Support' },
        { id=>5, name=>'service-desk', description=>'Service Desk' },
    ],
    'sharing selection receives all active agent groups',
);
my ($GroupCall) = grep { $_->[1] =~ m{FROM user_group ug} } @{ $DB->{Calls} };
like( $GroupCall->[1], qr{ug\.active=1 AND ug\.group_type=\?}, 'group selection is limited to active agent groups' );
unlike( $GroupCall->[1], qr{user_group_member}, 'group selection is not restricted to current memberships' );
is( $GroupCall->[2], 'agent', 'agent group type is bound safely' );

my $Config = $Builder->DefaultConfiguration();
$Config->{filters} = [ { field=>'title',operator=>'contains',values=>['alpha%_" OR 1=1 --'] } ];
my $Clean = $Builder->ConfigurationValidate( Configuration=>$Config );
ok( $Clean, 'valid report configuration is accepted' );

my $Injected = { %{$Config}, source=>'tickets; DROP TABLE ticket' };
ok( !$Builder->ConfigurationValidate(Configuration=>$Injected), 'unknown data source is rejected' );
is( $Builder->Error(), 'Translate:ReportErrorInvalidSource', 'invalid source has a clear error' );

my $InvalidField = { %{$Config}, filters=>[ {field=>'t.id) OR 1=1 --',operator=>'eq',values=>[1]} ] };
ok( !$Builder->ConfigurationValidate(Configuration=>$InvalidField), 'unknown SQL-like field is rejected' );

my $Result = $Builder->Execute(
    Configuration=>$Config, User=>{user_account_id=>7}, ReportID=>0, ExecutionType=>'preview', DetailLimit=>20,
);
ok( $Result, 'report can be executed' );
is( $Result->{rows}->[0]->{values}->[0], 2, 'aggregation result is returned' );
is( $Result->{details}->{rows}->[0]->[0], '202607180001', 'detail result is returned' );

my ($AggregateCall) = grep { $_->[1] =~ m{AS group_key} } @{ $DB->{Calls} };
ok( $AggregateCall, 'aggregate query was issued' );
like( $AggregateCall->[1], qr{WHERE 1=1 AND}, 'report execution intentionally starts without a queue restriction' );
is( scalar(@{$AggregateCall})-2, 1, 'only the configured filter value is bound to the report query' );
unlike( $AggregateCall->[1], qr{OR 1=1}, 'filter input is not interpolated into SQL' );
ok( grep( { defined $_ && $_ eq '%alpha\%\_" OR 1=1 --%' } @{$AggregateCall}[2..$#{$AggregateCall}] ), 'filter input is escaped and bound separately' );
ok( grep( { $_->[0] =~ m{INSERT INTO report_execution_log} } @{ $DB->{Do} } ), 'report execution is audited' );

my $TimeConfig = {
    source=>'time',filter_logic=>'all',filters=>[],group_by=>'work_month',metrics=>['total_minutes'],
    chart_type=>'bar',sort=>'label_asc',limit=>25,columns=>['ticket_number','duration_minutes'],
};
$Builder->Execute(Configuration=>$TimeConfig,User=>{user_account_id=>7},DetailLimit=>20);
my ($TimeCall) = grep { $_->[1] =~ m{FROM ticket_time_accounting ta} && $_->[1] =~ m{AS group_key} } @{ $DB->{Calls} };
like( $TimeCall->[1], qr{tc\.id IS NULL}, 'cancelled time entries are excluded' );

my $PDF = QisutuReportPDF->new()->Create(
    Title=>'Monthly support',GeneratedLabel=>'2026-07-18',Result=>{
        configuration=>{chart_type=>'bar'}, group=>{label=>'Month'},
        metrics=>[{label=>'Tickets',format=>'number'}], summary=>[2],
        rows=>[{label=>'2026-07',values=>[2]}],
        details=>{columns=>[{label=>'Ticket'}],rows=>[['202607180001']]},
    },
);
like( $PDF, qr{\A%PDF-1\.4}, 'PDF export creates a PDF document' );
like( $PDF, qr{\nxref\n}, 'PDF export contains a cross-reference table' );
cmp_ok( length($PDF), '>', 1000, 'PDF contains chart and detail content' );

for my $Path (qw(
    core/output/Reports.tt var/static/js/qisutu-reports.js
    install/sql/schema.sql
)) {
    open my $FH, '<:raw', "$FindBin::Bin/../$Path" or die $!;
    local $/; my $Content = <$FH>; close $FH;
    ok( length($Content) > 100, "$Path is present" );
}

for my $Language (qw(de en fr it pt-BR pt-PT es nl pl cs tr)) {
    my $Translations = do "$FindBin::Bin/../core/language/$Language.pm";
    ok( ref $Translations eq 'HASH', "$Language translations load" );
    is( $Translations->{ReportCreate} ? 1 : 0, 1, "$Language contains report translations" );
}

done_testing();
