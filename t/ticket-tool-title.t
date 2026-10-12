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
use Storable qw(dclone);
use Test::More;
use lib File::Spec->catdir( $FindBin::Bin, '..', 'core', 'module' );
use lib File::Spec->catdir( $FindBin::Bin, '..', 'core', 'output' );
use lib File::Spec->catdir( $FindBin::Bin, '..', 'core', 'system' );
use AgentTicketZoom;
use QisutuTicket;
use QisutuOutput;

# Execute the real title action and updater against a transactional database double.
{
    package Local::TitleDB;
    sub new {
        return bless {
            Ticket => {
                id => 42, queue_id => 7, title => 'Alter Titel', state_name => 'open',
                state_id => 2, priority_id => 3, owner_user_id => 8, changed_by_user_id => 2,
            },
            Articles => [],
        }, shift;
    }
    sub Error { return '' }
    sub BeginWork {
        my $s = shift;
        return if $s->{BeginFail};
        $s->{Ticket}->{title} = $s->{ConcurrentTitle} if exists $s->{ConcurrentTitle};
        $s->{Snapshot} = Storable::dclone([$s->{Ticket}, $s->{Articles}]);
        $s->{Begins}++;
        return 1;
    }
    sub Commit {
        my $s = shift;
        return if $s->{CommitFail};
        $s->{Commits}++;
        delete $s->{Snapshot};
        return 1;
    }
    sub Rollback {
        my $s = shift;
        $s->{Rollbacks}++;
        ($s->{Ticket}, $s->{Articles}) = @{delete $s->{Snapshot}};
        return 1;
    }
    sub SelectRow {
        my ($s, $sql, @bind) = @_;
        die "Unexpected SelectRow: $sql" unless $sql =~ /FROM ticket t/ && $sql =~ /FOR UPDATE/;
        return if $s->{Missing} || $bind[0] != $s->{Ticket}->{id};
        return { %{$s->{Ticket}} };
    }
    sub Do {
        my ($s, $sql, @bind) = @_;
        die "Unexpected Do: $sql" unless $sql =~ /UPDATE ticket\s+SET title = \?/;
        return if $s->{UpdateFail};
        die 'wrong ticket' unless $bind[2] == $s->{Ticket}->{id};
        $s->{Ticket}->{title} = $bind[0];
        $s->{Ticket}->{changed_by_user_id} = $bind[1];
        return 1;
    }
    package Local::TitlePermission;
    sub new { return bless {}, shift }
    sub QueueAccessCheck {
        my ($s, %p) = @_;
        return !$s->{Denied} && $p{UserID} == 8 && $p{QueueID} == 7 && $p{Permission} eq 'ticket.edit';
    }
    package Local::TitleTicket;
    use parent 'QisutuTicket';
    sub TicketGet {
        my $s = shift;
        return if $s->{DB}->{Missing};
        return { %{$s->{DB}->{Ticket}} };
    }
    sub ArticleCreate {
        my ($s, %p) = @_;
        return if $s->{ArticleFail};
        push @{$s->{DB}->{Articles}}, \%p;
        return 91;
    }
    sub _AgentNotificationSend { die 'Renaming must not send notifications' }
    package Local::TitleModule;
    use parent 'AgentTicketZoom';
    sub _QueueAccessCheck { return !shift->{Denied} }
}

my $Root = File::Spec->rel2abs( File::Spec->catdir($FindBin::Bin, '..') );
my $Config = { Paths => { Language => "$Root/core/language", Output => "$Root/core/output" }, Language => { Default => 'de' } };
my $Output = QisutuOutput->new(Config => $Config);
my $User = { user_account_id => 8, account_type => 'agent', email => 'agent@example.test' };
my ($DB, $Ticket, $Module, $Permission);
sub reset_fixture {
    $DB = Local::TitleDB->new();
    $Permission = Local::TitlePermission->new();
    $Ticket = Local::TitleTicket->new(DB => $DB, Config => $Config, Permission => $Permission);
    $Module = Local::TitleModule->new(DB => $DB, Config => $Config, Output => $Output);
}
sub update_title {
    my (%Request) = @_;
    return $Module->_TicketToolUpdate(
        TicketID => 42, TicketObject => $Ticket, Language => 'de', User => $User,
        Request => { ToolAction => 'title', Title => 'Neuer Titel', __RequestMethod => 'POST', %Request },
    );
}

reset_fixture();
ok(update_title(Title => '  Neuer Titel: Prüfung & Rückfrage  ')->{Success}, 'title can be changed without a manual note');
is($DB->{Ticket}->{title}, 'Neuer Titel: Prüfung & Rückfrage', 'Unicode title is stored and surrounding whitespace removed');
is($DB->{Ticket}->{changed_by_user_id}, 8, 'the acting agent is recorded for the history trigger');
is($DB->{Commits}, 1, 'title and internal article commit together');
is(scalar @{$DB->{Articles}}, 1, 'exactly one internal article is created');
my $Article = $DB->{Articles}->[0];
is($Article->{Subject}, 'Titel geändert', 'internal subject is translated');
like($Article->{Body}, qr{Alter Titel.*Neuer Titel: Prüfung &amp; Rückfrage}, 'internal article documents both titles and escapes markup');
is($Article->{Visibility}, 'agent', 'change note is internal');
is($Article->{Channel}, 'note', 'renaming does not send an e-mail');
is($Article->{SkipNotification}, 1, 'note notifications are suppressed');
is_deeply([@{$DB->{Ticket}}{qw(state_id priority_id queue_id owner_user_id)}], [2,3,7,8], 'other ticket attributes remain unchanged');
is(update_title(Title => ' Neuer Titel: Prüfung & Rückfrage ')->{Error}, 'Translate:TicketToolNoChange', 'unchanged title is rejected');
is(scalar @{$DB->{Articles}}, 1, 'unchanged title creates no duplicate note');

for my $Title ('0', 'Ä' x 500, q{O'Connor <script>alert("test")</script>}) {
    reset_fixture();
    ok(update_title(Title => $Title, ToolArticleBody => '<p>Betreff korrigiert.</p>')->{Success}, 'valid edge-case title is accepted');
    is($DB->{Ticket}->{title}, $Title, 'title is preserved exactly');
    like($DB->{Articles}->[0]->{Body}, qr{Betreff korrigiert}, 'optional comment is retained');
    unlike($DB->{Articles}->[0]->{Body}, qr{<script>}, 'title markup is escaped in the internal article');
}
for my $Title (undef, '', '   ', 'x' x 501, "Zwei\nZeilen", "Mit\tTab", "Mit\0NUL") {
    reset_fixture();
    is(update_title(Title => $Title)->{Error}, 'Translate:TicketToolTitleInvalid', 'invalid title is rejected on the server');
    is($DB->{Ticket}->{title}, 'Alter Titel', 'invalid input preserves the title');
    is_deeply($DB->{Articles}, [], 'invalid input creates no article');
}
for my $Method ('GET', '', 'PUT') {
    reset_fixture();
    ok(!update_title(__RequestMethod => $Method)->{Success}, 'only POST can change the title');
    ok(!$DB->{Begins}, 'non-POST request is rejected before mutation');
}

reset_fixture();
$Module->{Denied} = 1;
is(update_title()->{Error}, 'Translate:TicketChangeAccessDenied', 'the action requires queue edit permission');
ok(!$DB->{Begins}, 'permission denial prevents starting a mutation');
reset_fixture();
$Permission->{Denied} = 1;
is(update_title()->{Error}, 'Translate:TicketChangeAccessDenied', 'the system method independently checks queue edit permission');
is($DB->{Ticket}->{title}, 'Alter Titel', 'backend permission denial preserves the title');
for my $Type ('customer', '') {
    reset_fixture();
    ok(!$Ticket->TicketTitleUpdate(TicketID => 42, Title => 'New', User => {%{$User}, account_type => $Type}), 'non-agent cannot use the title updater');
    is($Ticket->Error(), 'Translate:TicketChangeAccessDenied', 'non-agent receives access error');
}
reset_fixture();
$DB->{Ticket}->{state_name} = 'merged';
is(update_title()->{Error}, 'Translate:TicketMergedReadOnly', 'merged ticket is read-only in the action');
ok(!$Ticket->TicketTitleUpdate(TicketID => 42, Title => 'New', User => $User), 'system updater also refuses merged tickets');
is($Ticket->Error(), 'Translate:TicketMergedReadOnly', 'system method reports merged restriction');
reset_fixture();
$DB->{Ticket}->{state_name} = 'closed successful';
ok(update_title()->{Success}, 'a regular closed ticket can be renamed');
is($DB->{Ticket}->{state_name}, 'closed successful', 'renaming does not reopen a closed ticket');

for my $Failure ('BeginFail', 'UpdateFail', 'CommitFail', 'ArticleFail', 'Missing') {
    reset_fixture();
    if ($Failure eq 'ArticleFail') { $Ticket->{$Failure} = 1 }
    else { $DB->{$Failure} = 1 }
    ok(!update_title()->{Success}, "$Failure prevents a successful rename");
    is($DB->{Ticket}->{title}, 'Alter Titel', "$Failure leaves the original title");
    is_deeply($DB->{Articles}, [], "$Failure leaves no orphaned note");
}
reset_fixture();
$DB->{ConcurrentTitle} = 'Zwischenzeitlich geändert';
is(update_title()->{Error}, 'Translate:TicketToolTitleConflict', 'a concurrent change between read and write is detected');
is($DB->{Ticket}->{title}, 'Zwischenzeitlich geändert', 'the concurrent title is not overwritten');
is_deeply($DB->{Articles}, [], 'a rejected concurrent change creates no misleading note');

reset_fixture();
for my $Language (qw(de en fr it pt-BR pt-PT es nl pl cs tr)) {
    my $Translations = do "$Root/core/language/$Language.pm";
    is($Module->_ToolArticleSubject(Language => $Language, Action => 'title'), $Translations->{TicketToolTitleChanged}, "$Language internal subject is translated");
    my $Summary = $Module->_ToolSummary(Language => $Language, Action => 'title', OldValue => '0', NewValue => 'NEW');
    like($Summary, qr{0.+NEW}, "$Language summary preserves both titles including zero");
    unlike($Summary, qr{\{(?:OldValue|NewValue)\}}, "$Language has no unresolved placeholders");
    my $HTML = $Output->RenderSingle(Template => 'AgentTicketZoom.tt', Data => {
        Language => $Language, TicketFound => 1, TicketID => 42, CanChangeTicket => 1, CSRFToken => 'test-token',
        TicketToolTitleValue => '" autofocus onfocus="alert(1)',
        TicketToolTitleArticleBody => '</textarea><script>alert(1)</script>',
    });
    like($HTML, qr{data-qisutu-ticket-tool="title">\Q$Translations->{TicketToolTitle}\E</button>}, "$Language title action is available");
    my ($Panel) = $HTML =~ m{(<div[^>]+data-qisutu-ticket-tool-panel="title".*?</form>)}s;
    like($Panel, qr{<form method="post"}, "$Language title form uses POST");
    like($Panel, qr{name="CSRFToken" value="test-token"}, "$Language title form has a CSRF token");
    like($Panel, qr{name="ToolAction" value="title"}, "$Language title form submits the new action");
    like($Panel, qr{id="qisutu-ticket-tool-title-body"[^>]+data-qisutu-richtext-optional="1"}, "$Language comment is optional in the browser");
    like($Panel, qr{name="Title" value="&quot; autofocus onfocus=&quot;alert\(1\)" maxlength="500" required}, "$Language title input is escaped and length-limited");
    unlike($Panel, qr{<script>alert\(1\)</script>}, "$Language comment is escaped on redisplay");
}
my $ReadOnly = $Output->RenderSingle(Template => 'AgentTicketZoom.tt', Data => {
    Language => 'de', TicketFound => 1, TicketID => 42, CanChangeTicket => 0,
});
unlike($ReadOnly, qr{data-qisutu-ticket-tool(?:-panel)?="title"}, 'read-only agents see neither the title action nor its form');

done_testing();
