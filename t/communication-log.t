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

BEGIN {
    package DBI;
    sub import { return }
    $INC{'DBI.pm'} = 1;
}

use FindBin;
use lib "$FindBin::Bin/../core/system", "$FindBin::Bin/../core/config", "$FindBin::Bin/../core/output", "$FindBin::Bin/../core/cpan-lib";
use Test::More;

use QisutuCommunicationLog;
use QisutuOutput;
use QisutuPostmasterFilter;

{
    package Local::CommunicationDB;
    sub new { bless { Do => [], LastID => 40, Error => '' }, shift }
    sub Do {
        my ( $Self, $SQL, @Bind ) = @_;
        my $PlaceholderCount = () = $SQL =~ m{[?]}g;
        if ( $PlaceholderCount != scalar @Bind ) {
            $Self->{Error} = "called with " . scalar(@Bind)
                . " bind variables when $PlaceholderCount are needed";
            return;
        }
        push @{ $Self->{Do} }, [ $SQL, @Bind ];
        return 1;
    }
    sub LastInsertID { return ++$_[0]->{LastID} }
    sub SelectRow {
        my ( $Self, $SQL, @Bind ) = @_;
        return { total_count=>2, success_count=>1, warning_count=>0, error_count=>1, running_count=>0, received_count=>3, sent_count=>1, average_duration_ms=>120 } if $SQL =~ m{COUNT[(][*][)] AS total_count};
        return { id => $Self->{LastID} + 1 } if $SQL =~ m{SELECT id FROM communication_log WHERE trace_id};
        return { id=>77, protocol=>'imap', operation=>'fetch', status=>'success' } if $SQL =~ m{SELECT l[.][*].*FROM communication_log l}s;
        return;
    }
    sub SelectAll {
        my ( $Self, $SQL, @Bind ) = @_;
        if ( $SQL =~ m{FROM postmaster_imap_account} ) {
            return [
                { account_type=>'imap', account_id=>7, account_display=>'Support-Eingang' },
                { account_type=>'smtp', account_id=>3, account_display=>'Support-Ausgang' },
            ];
        }
        if ( $SQL =~ m{FROM communication_log} && $SQL =~ m{GROUP BY account_type} ) {
            return [
                { account_type=>'imap', account_id=>7, account_display=>'Alter Name' },
                { account_type=>'smtp', account_id=>9, account_display=>'Gelöschtes Konto' },
            ];
        }
        if ( $SQL =~ m{FROM communication_log_step} ) {
            return [
                { id=>1, source_log_id=>77, source_protocol=>'imap', source_operation=>'fetch', stage=>'search' },
                { id=>2, source_log_id=>78, source_protocol=>'imap', source_operation=>'delete', source_parent_id=>77, stage=>'expunge' },
            ];
        }
        return [];
    }
    sub Error { return $_[0]->{Error} }
}

{
    package Local::FailingCommunicationDB;
    sub new { bless { Error => 'separate logging connection rejected the insert' }, shift }
    sub Do { return }
    sub Error { return $_[0]->{Error} }
}

my $DB = Local::CommunicationDB->new();
my $Object = QisutuCommunicationLog->new( Config=>{}, DB=>$DB );

my $Started = $Object->Start(
    Protocol=>'smtp', Direction=>'outgoing', Operation=>'send', AccountType=>'smtp', AccountID=>3,
    AccountName=>'Support', AccountEmail=>'support@example.org', ServerHost=>'smtp.example.org', ServerPort=>587,
    SenderEmail=>'support@example.org', RecipientEmail=>'customer@example.org', Subject=>'Test',
);
ok( $Started->{ID}, 'a communication operation can be started' );
like( $Started->{TraceID}, qr{\A[0-9a-f]{64}\z}, 'operation gets a non-secret trace ID' );
my $StartCall = $DB->{Do}->[0];
is(
    scalar( @{$StartCall} ) - 1,
    scalar( () = $StartCall->[0] =~ m{[?]}g ),
    'optional IDs remain explicit NULL bind values instead of disappearing from the bind list',
);

my $FallbackDB = Local::CommunicationDB->new();
my $FallbackObject = QisutuCommunicationLog->new( Config=>{}, DB=>$FallbackDB );
$FallbackObject->{DB} = Local::FailingCommunicationDB->new();
my $FallbackStarted = $FallbackObject->Start(
    Protocol=>'imap', Direction=>'incoming', Operation=>'fetch', AccountType=>'imap', AccountID=>7,
);
ok( $FallbackStarted->{ID}, 'communication logging retries on the established application connection' );
is( $FallbackObject->{DB}, $FallbackDB, 'all further steps use the successful fallback connection' );

ok( $Object->StepAdd(
    CommunicationID=>$Started->{ID}, Stage=>'authentication', Level=>'error', Message=>'Authentication failed',
    Details=>'Authorization: Bearer top-secret access_token="token-value" client_secret=hidden',
), 'processing step can be added' );

my $StepCall = $DB->{Do}->[-1];
my $StepBind = join ' ', @{$StepCall}[1 .. $#{$StepCall}];
unlike( $StepBind, qr{top-secret|token-value|hidden}, 'tokens and client secrets are removed from step details' );
like( $StepBind, qr{\[REDACTED\]}, 'redaction is visible in technical details' );

ok( $Object->Finish(
    CommunicationID=>$Started->{ID}, Status=>'error', Summary=>'access_token=top-secret', ErrorMessage=>'password=secret', MessagesFailed=>1,
), 'communication operation can be completed' );
my $FinishBind = join ' ', map { defined $_ ? $_ : '' } @{ $DB->{Do}->[-1] }[1 .. $#{ $DB->{Do}->[-1] }];
unlike( $FinishBind, qr{top-secret|password=secret}, 'secrets are also removed from summaries and errors' );

my ( $Where, $Bind ) = $Object->_FilterSQL(
    Period=>'custom', DateFrom=>'2026-07-01', DateTo=>'2026-07-19', Protocol=>'imap', Account=>'imap:7',
    Search=>q{%' OR 1=1 --},
);
unlike( $Where, qr{OR 1=1 --}, 'search input is not interpolated into SQL' );
ok( grep( { $_ eq q{%%' OR 1=1 --%} } @{$Bind} ), 'search input is passed as a bound value' );
like( $Where, qr{account_type = [^?]*[?] AND l[.]account_id = [^?]*[?]}, 'account type and ID are both filtered' );

my $Accounts = $Object->AccountList();
is_deeply(
    $Accounts,
    [
        { account_type=>'smtp', account_id=>9, account_display=>'Gelöschtes Konto' },
        { account_type=>'smtp', account_id=>3, account_display=>'Support-Ausgang' },
        { account_type=>'imap', account_id=>7, account_display=>'Support-Eingang' },
    ],
    'configured accounts are shown before their first log and historical accounts remain filterable',
);

my $DetailWithChildren = $Object->Get( CommunicationID=>77 );
is( scalar @{ $DetailWithChildren->{Steps} || [] }, 2, 'detail view loads steps of the selected connection and its child connections' );
is( $DetailWithChildren->{Steps}->[1]->{source_operation}, 'delete', 'child operation remains identifiable in the shared timeline' );

my $Postmaster = QisutuPostmasterFilter->new( Config=>{}, DB=>$DB );
my $FilterResult = $Postmaster->_EvaluateWithFilters(
    Filters => [ {
        id=>11, name=>'Support routing', active=>1, message_scope=>'both', match_mode=>'all',
        conditions=>[ { field_name=>'subject', operator=>'contains', match_value=>'help' } ],
        actions=>[ { action_type=>'dynamic_field', target_id=>7, action_value=>'urgent' } ],
    } ],
    Message => { subject=>'Please help' },
    Context => { MessageScope=>'new' },
);
is( $FilterResult->{Details}->[0]->{filter_name}, 'Support routing', 'evaluated filter name remains available for the communication trace' );
is( $FilterResult->{Details}->[0]->{conditions}->[0]->{matched}, 1, 'condition result remains available for the communication trace' );
is_deeply(
    $FilterResult->{Details}->[0]->{action_details}->[0],
    { action_type=>'dynamic_field', target_id=>7, action_value=>'urgent', result=>'dynamic_field_7=set' },
    'applied action type, target and value remain available for detailed logging',
);

for my $Path (qw(
    core/system/QisutuCommunicationLog.pm
    core/module/AdminCommunicationLog.pm
    core/output/AdminCommunicationLog.tt
    core/config/programs/AdminCommunicationLog.pm
    install/update/database/0.0.21/001-create-communication-log.sql
)) {
    open my $FH, '<:raw', "$FindBin::Bin/../$Path" or die $!;
    local $/;
    my $Content = <$FH>;
    close $FH;
    ok( length($Content) > 100, "$Path is present" );
}

for my $Language (qw(de en fr it)) {
    my $Translations = do "$FindBin::Bin/../core/language/$Language.pm";
    ok( ref $Translations eq 'HASH', "$Language translations load" );
    ok( $Translations->{CommunicationLogTitle}, "$Language contains communication-log translations" );
    ok( $Translations->{CommunicationLogStepsDescription}, "$Language describes the detailed processing steps" );
    ok( $Translations->{CommunicationLogNoStepsText}, "$Language explains missing processing steps" );
}

open my $FetchFH, '<:raw', "$FindBin::Bin/../bin/qisutu-mail-fetch.pl" or die $!;
local $/;
my $FetchSource = <$FetchFH>;
close $FetchFH;
like( $FetchSource, qr{sprintf\s+'%04d-%02d-%02d %02d:%02d:%02d'}, 'mail-fetch console output includes a timestamp' );
like( $FetchSource, qr{QisutuCommunicationLog}, 'mail fetch uses the central communication log' );
like( $FetchSource, qr{Stage\s*=>\s*'filter_check'}, 'mail fetch records each postmaster-filter check' );
like(
    $FetchSource,
    qr{Stage\s*=>\s*\(\s*\(.*?dynamic_field.*?\?\s*'dynamic_field'\s*:\s*'filter_action'}s,
    'mail fetch records dynamic-field filter actions explicitly',
);
like( $FetchSource, qr{LastEmailImportArticleID}, 'mail fetch links the created article to the communication trace' );

open my $TemplateFH, '<:raw', "$FindBin::Bin/../core/output/AdminCommunicationLog.tt" or die $!;
my $TemplateSource = do { local $/; <$TemplateFH> };
close $TemplateFH;
like( $TemplateSource, qr{qisutu-communication-list-row}, 'the compact connection list consists of fully clickable rows' );
unlike( $TemplateSource, qr{qisutu-communication-table}, 'the overflowing wide communication table is no longer used' );
unlike( $TemplateSource, qr{qisutu-communication-detail-overview}, 'the detail overlay does not repeat the connection list' );
like( $TemplateSource, qr{qisutu-communication-protocol-details}, 'the detail overlay is centered on the processing protocol' );
ok(
    index( $TemplateSource, 'qisutu-communication-protocol-details' )
        < index( $TemplateSource, 'qisutu-communication-message-meta' ),
    'processing steps precede supplementary message information',
);
like( $TemplateSource, qr{technical_details_html}, 'technical step details can be expanded in the detail view' );
unlike( $TemplateSource, qr{IF\s+Step[.]}, 'the template does not use unsupported nested conditions' );

my $Output = QisutuOutput->new( Config => {
    Paths    => { Output => "$FindBin::Bin/../core/output", Language => "$FindBin::Bin/../core/language" },
    Language => { Default => 'de' },
} );
my $RenderedTemplate = $Output->RenderSingle(
    Template => 'AdminCommunicationLog.tt',
    Data     => {
        Language => 'de', HasLogs => 1, HasDetail => 1, HasDetailSteps => 1,
        HasMessageMetadata => 1, HasProcessingData => 1, DetailStepCount => 1,
        DetailSender => 'kunde@example.test', DetailResult => 'Nachricht verarbeitet',
        Logs => [ { detail_url=>'index.pl?Page=AdminCommunicationLog;LogID=42', status_class=>'is-success', status_symbol=>'✓' } ],
        DetailSteps => [ {
            level_class=>'is-success', step_number=>1, message_display=>'Nachricht verarbeitet',
            created_at=>'2026-07-19 12:00:00', source_display=>'IMAP · E-Mails abrufen',
            stage_display=>'Nachricht verarbeiten', level_display=>'Erfolgreich',
            technical_details_html=>'<details><summary>Technische Details</summary><pre>Antwort: OK</pre></details>',
        } ],
    },
);
ok( defined $RenderedTemplate && length $RenderedTemplate, 'communication-log template renders with a list and detail data' );
unlike( $RenderedTemplate || '', qr{\[\%}, 'communication-log rendering leaves no template directives behind' );
like( $RenderedTemplate || '', qr{LogID=42}, 'rendered connection row opens its details' );
like( $RenderedTemplate || '', qr{Antwort: OK}, 'rendered detail contains expandable technical information' );
like( $RenderedTemplate || '', qr{Verarbeitungsschritte}, 'rendered detail focuses on the chronological processing steps' );
like( $RenderedTemplate || '', qr{kunde[\@]example[.]test}, 'rendered detail retains supplementary message metadata' );

open my $CSSFH, '<:raw', "$FindBin::Bin/../var/static/css/qisutu.css" or die $!;
my $CSSSource = do { local $/; <$CSSFH> };
close $CSSFH;
unlike( $CSSSource, qr{[.]qisutu-communication-table\s*[{][^}]*min-width:\s*1120px}s, 'the fixed oversized communication table width is gone' );
like( $CSSSource, qr{[.]qisutu-communication-detail\s*[{][^}]*width:\s*min[(]1040px,}s, 'the proven communication detail width is retained' );
unlike( $CSSSource, qr{[.]qisutu-communication-detail\s*[{][^}]*width:\s*min[(]1180px,}s, 'the detail dialog is not widened underneath the navigation sidebar' );
like( $CSSSource, qr{[.]qisutu-communication-detail-backdrop\s*[{][^}]*inset:\s*0\s+0\s+0\s+248px}s, 'the detail overlay begins to the right of the expanded navigation' );
like( $CSSSource, qr{html[.]qisutu-sidebar-collapsed\s+[.]qisutu-communication-detail-backdrop\s*[{][^}]*left:\s*68px}s, 'the detail overlay follows the collapsed navigation width' );
like( $CSSSource, qr{[.]qisutu-communication-detail-actions\s*[{][^}]*flex:\s*0\s+0\s+auto}s, 'the close action remains outside the scrolling detail content' );

open my $LogFH, '<:raw', "$FindBin::Bin/../core/system/QisutuCommunicationLog.pm" or die $!;
my $LogSource = do { local $/; <$LogFH> };
close $LogFH;
unlike(
    $LogSource,
    qr{(?:status\s*=|VALUES\s*[(][^)]*)\s*"(?:running|success|warning|error)"}s,
    'communication SQL does not rely on double-quoted string literals',
);
like(
    $LogSource,
    qr{SELECT id FROM communication_log WHERE trace_id = [^?]*[?]},
    'a newly written communication entry is verified by its trace ID',
);

done_testing();
