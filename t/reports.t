#!/usr/bin/env perl
# Qisutu - Open Source Ticket System
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
    install/update/database/0.0.19/001-create-reports.sql
)) {
    open my $FH, '<:raw', "$FindBin::Bin/../$Path" or die $!;
    local $/; my $Content = <$FH>; close $FH;
    ok( length($Content) > 100, "$Path is present" );
}

for my $Language (qw(de en fr it)) {
    my $Translations = do "$FindBin::Bin/../core/language/$Language.pm";
    ok( ref $Translations eq 'HASH', "$Language translations load" );
    is( $Translations->{ReportCreate} ? 1 : 0, 1, "$Language contains report translations" );
}

done_testing();
