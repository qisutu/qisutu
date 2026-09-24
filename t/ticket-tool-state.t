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
use File::Spec;
use FindBin;
use Test::More;
use Storable qw(dclone);
use lib File::Spec->catdir( $FindBin::Bin, '..', 'core', 'module' );
use lib File::Spec->catdir( $FindBin::Bin, '..', 'core', 'output' );
use lib File::Spec->catdir( $FindBin::Bin, '..', 'core', 'system' );
use AgentTicketZoom;
use QisutuTicket;
use QisutuOutput;

# Exercise the real status updater against an isolated transactional database double.
{
    package Local::StateDB;
    sub new {
        return bless {
            Ticket => { id => 42, queue_id => 7, state_id => 1, pending_until => undef },
            States => {
                1 => { id => 1, name => 'new', state_type => 'new', active => 1 },
                2 => { id => 2, name => 'open', state_type => 'open', active => 1 },
                3 => { id => 3, name => 'pending reminder', state_type => 'pending', active => 1 },
                4 => { id => 4, name => 'closed successful', state_type => 'closed', active => 1 },
                5 => { id => 5, name => 'merged', state_type => 'closed', active => 1 },
                6 => { id => 6, name => 'inactive', state_type => 'open', active => 0 },
            },
        }, shift;
    }
    sub Error { return '' }
    sub BeginWork { my $s = shift; $s->{Snapshot} = Storable::dclone($s->{Ticket}); $s->{Begins}++; return 1 }
    sub Commit { my $s = shift; $s->{Commits}++; delete $s->{Snapshot}; return 1 }
    sub Rollback { my $s = shift; $s->{Rollbacks}++; $s->{Ticket} = delete $s->{Snapshot}; return 1 }
    sub SelectRow {
        my ($s, $sql, @bind) = @_;
        if ($sql =~ /FROM ticket_state/) {
            my $row = $s->{States}->{$bind[0]} or return;
            return if !$row->{active} || ($sql =~ /name <>/ && $row->{name} eq $bind[1]);
            return { %{$row} };
        }
        if ($sql =~ /FROM ticket t/) {
            my $state = $s->{States}->{$s->{Ticket}->{state_id}};
            return { %{$s->{Ticket}}, current_state_type => $state->{state_type} };
        }
        die "Unexpected SelectRow: $sql";
    }
    sub SelectAll {
        my ($s, $sql) = @_;
        return $s->{OpenItems} || [] if $sql =~ /FROM ticket_checklist_item/;
        return [ map { $s->{States}->{$_} } grep { $s->{States}->{$_}->{active} } sort keys %{$s->{States}} ]
            if $sql =~ /FROM ticket_state/;
        die "Unexpected SelectAll: $sql";
    }
    sub Do {
        my ($s, $sql, @bind) = @_;
        return 1 if $sql =~ /INSERT INTO ticket_checklist_audit/;
        die "Unexpected Do: $sql" if $sql !~ /UPDATE ticket/;
        $s->{Ticket}->{state_id} = $bind[0];
        $s->{Ticket}->{pending_until} = $bind[3] eq 'pending' ? $bind[4] : undef;
        return 1;
    }
    package Local::StateTicket;
    use parent 'QisutuTicket';
    sub TicketGet {
        my $s = shift;
        return { %{$s->{DB}->{Ticket}}, state_name => $s->{DB}->{States}->{$s->{DB}->{Ticket}->{state_id}}->{name} };
    }
    sub _NowDateTime { return '2026-09-24 12:00:00' }
    sub RecalculateTicketEscalationTimes { shift->{Recalculations}++; return 1 }
    sub _AgentNotificationSend { shift->{Notifications}++; return 1 }
    sub _AddonEventEmit { shift->{Events}++; return 1 }
    sub ArticleCreate {
        my ($s, %param) = @_;
        return if $s->{ArticleFail};
        $s->{Article} = \%param;
        return 91;
    }
    package Local::StateFields;
    sub new { return bless {}, shift }
    sub TicketValueValidate { return !shift->{Invalid} }
    sub TicketValueSave { return 1 }
    sub Error { return 'Translate:TicketDynamicFieldInvalid' }
    package Local::StateModule;
    use parent 'AgentTicketZoom';
    sub _DynamicFieldObject { return shift->{Fields} }
    sub _QueueAccessCheck { return !shift->{Denied} }
}

my $Root = File::Spec->rel2abs( File::Spec->catdir($FindBin::Bin, '..') );
my $Config = { Paths => { Language => "$Root/core/language", Output => "$Root/core/output" }, Language => { Default => 'de' } };
my $Output = QisutuOutput->new(Config => $Config);
my ($DB, $Ticket, $Module);
sub reset_fixture {
    $DB = Local::StateDB->new();
    $Ticket = Local::StateTicket->new(DB => $DB, Config => $Config);
    $Module = Local::StateModule->new(DB => $DB, Config => $Config, Output => $Output);
    $Module->{Fields} = Local::StateFields->new();
}
sub update_state {
    my (%Request) = @_;
    return $Module->_TicketToolUpdate(
        TicketID => 42, TicketObject => $Ticket, Language => 'de',
        User => { user_account_id => 8, email => 'agent@example.test' },
        Request => { ToolAction => 'state', StatusID => 2, ToolArticleBody => '<p>Bearbeitung übernommen.</p>', %Request },
    );
}

reset_fixture();
ok(update_state()->{Success}, 'status action saves through the real ticket status updater');
is($DB->{Ticket}->{state_id}, 2, 'new status is persisted');
is($DB->{Commits}, 1, 'status and note commit together');
is($Ticket->{Article}->{Visibility}, 'agent', 'the action creates an internal article');
is($Ticket->{Article}->{Subject}, 'Status geändert', 'article subject is localized');
like($Ticket->{Article}->{Body}, qr{Bearbeitung übernommen}, 'entered note is preserved');
is($Ticket->{Article}->{SkipNotification}, 1, 'the note does not duplicate the status notification');
is($Ticket->{Notifications}, 1, 'the existing status notification is invoked once');
is($Ticket->{Recalculations}, 1, 'the existing SLA recalculation is invoked');
is(update_state()->{Error}, 'Translate:TicketToolNoChange', 'unchanged status is rejected');

reset_fixture();
ok(update_state(StatusID => 3, PendingUntil => '2026-10-01T14:30')->{Success}, 'pending status with a future date is accepted');
is($DB->{Ticket}->{pending_until}, '2026-10-01 14:30:00', 'pending date is normalized and persisted');
is(update_state(StatusID => 3, PendingUntil => '2026-10-01T14:30')->{Error}, 'Translate:TicketToolNoChange', 'equivalent pending date is not a change');
ok(update_state(StatusID => 3, PendingUntil => '2026-10-02T14:30')->{Success}, 'the pending date can be adjusted without changing the status');
ok(update_state(StatusID => 2)->{Success}, 'pending ticket can be opened');
ok(!defined $DB->{Ticket}->{pending_until}, 'leaving pending clears the pending date');
for my $Case (
    [ '', 'Translate:TicketPendingUntilRequired' ],
    [ '2026-09-20T14:30', 'Translate:TicketPendingUntilFutureRequired' ],
) {
    reset_fixture();
    is(update_state(StatusID => 3, PendingUntil => $Case->[0])->{Error}, $Case->[1], 'invalid pending date is rejected');
    is($DB->{Ticket}->{state_id}, 1, 'failed pending update preserves the original status');
    ok(!$Ticket->{Article}, 'failed pending update creates no article');
}

for my $ID (0, 5, 6, 999, 'invalid') {
    reset_fixture();
    is(update_state(StatusID => $ID)->{Error}, 'Translate:TicketToolSelectionRequired', "invalid, merged or inactive status $ID is rejected");
    ok(!$DB->{Begins}, 'invalid target causes no writes');
}
reset_fixture();
$DB->{Ticket}->{state_id} = 5;
is(update_state()->{Error}, 'Translate:TicketMergedReadOnly', 'merged ticket remains read-only');
reset_fixture();
$Module->{Denied} = 1;
is(update_state()->{Error}, 'Translate:TicketChangeAccessDenied', 'queue edit permission is required');
ok(!$DB->{Begins}, 'permission rejection happens before mutation');
reset_fixture();
is(update_state(ToolArticleBody => '<p><br></p>')->{Error}, 'Translate:TicketToolArticleBodyRequired', 'the internal note is required as for other ticket tools');
$Module->{Fields}->{Invalid} = 1;
is(update_state()->{Error}, 'Translate:TicketDynamicFieldInvalid', 'dynamic field requirements are enforced');
reset_fixture();
$Ticket->{ArticleFail} = 1;
ok(!update_state()->{Success}, 'article failure fails the action');
is($DB->{Ticket}->{state_id}, 1, 'article failure rolls the status back');
is($DB->{Rollbacks}, 1, 'article failure rolls back the transaction');
reset_fixture();
ok(update_state(StatusID => 4)->{Success}, 'a regular closed status is accepted');
ok(update_state(StatusID => 2)->{Success}, 'a closed ticket can be reopened');
reset_fixture();
$DB->{OpenItems} = [{ checklist_name => 'Prüfung', item_name => 'Freigabe' }];
my $Blocked = update_state(StatusID => 4);
ok(!$Blocked->{Success}, 'required open checklist items prevent closing');
is($DB->{Ticket}->{state_id}, 1, 'blocked close does not change the status');

reset_fixture();
my $Options = $Module->_StatusOptionsHTML(Language => 'de', CurrentStateID => 3, ExcludeMerged => 1);
like($Options, qr{value="3" selected data-state-type="pending"}, 'the action preselects the current status and exposes pending metadata');
unlike($Options, qr{value="(?:5|6)"}, 'merged and inactive states are absent from the action');

for my $Language (qw(de en fr it pt-BR pt-PT es nl pl cs tr)) {
    my $Translations = do "$Root/core/language/$Language.pm";
    is($Module->_ToolArticleSubject(Language => $Language, Action => 'state'), $Translations->{TicketToolStateChanged}, "$Language article subject is translated");
    my $Summary = $Module->_ToolSummary(Language => $Language, Action => 'state', OldValue => 'OLD', NewValue => 'NEW');
    like($Summary, qr{OLD.+NEW}, "$Language change summary substitutes both values");
    unlike($Summary, qr{\{(?:OldValue|NewValue)\}}, "$Language summary has no unresolved placeholders");
    my $HTML = $Output->RenderSingle(Template => 'AgentTicketZoom.tt', Data => {
        Language => $Language, TicketFound => 1, TicketID => 42, CSRFToken => 'test-token',
        TicketToolStateOptionsHTML => $Options, TicketToolStateArticleBody => '</textarea><script>alert(1)</script>',
    });
    like($HTML, qr{data-qisutu-ticket-tool="state">\Q$Translations->{TicketToolState}\E</button>}, "$Language renders the translated status button");
    like($HTML, qr{name="ToolAction" value="state"}, "$Language renders the submit action");
    like($HTML, qr{name="CSRFToken" value="test-token"}, "$Language status form is covered by CSRF injection");
    unlike($HTML, qr{<script>alert\(1\)</script>}, "$Language escapes the submitted note in the textarea");

}
done_testing();
