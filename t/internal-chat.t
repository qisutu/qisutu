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

use lib File::Spec->catdir( $FindBin::Bin, '..', 'core', 'system' );

use QisutuInternalChat;

my $Root = File::Spec->rel2abs( File::Spec->catdir( $FindBin::Bin, '..' ) );

{
    package Local::InternalChatDB;

    sub new {
        my ( $Class, @Result ) = @_;
        return bless { Result => \@Result, SQL => [] }, $Class;
    }

    sub SelectAll {
        my ( $Self, $SQL ) = @_;
        push @{ $Self->{SQL} }, $SQL;
        return shift @{ $Self->{Result} };
    }

    sub Error { return ''; }
}

{
    package Local::InternalChatDeleteDB;

    sub new {
        return bless {
            DoCalls    => [],
            Committed  => 0,
            RolledBack => 0,
        }, shift;
    }

    sub SelectRow {
        return {
            id        => 2,
            login     => 'bert',
            firstname => 'Bert',
            lastname  => 'Online',
        };
    }

    sub BeginWork { return 1; }

    sub Do {
        my ( $Self, $SQL, @Bind ) = @_;
        push @{ $Self->{DoCalls} }, { SQL => $SQL, Bind => \@Bind };
        return 1;
    }

    sub LastInsertID { return 77; }
    sub Commit       { $_[0]->{Committed} = 1; return 1; }
    sub Rollback     { $_[0]->{RolledBack} = 1; return 1; }
    sub Error        { return ''; }
}

sub content {
    my ($Relative) = @_;
    my $Path = File::Spec->catfile( $Root, split m{/}, $Relative );
    open my $FH, '<:encoding(UTF-8)', $Path or die "Cannot read $Relative: $!";
    local $/;
    my $Content = <$FH>;
    close $FH;
    return $Content;
}

my $Program = do File::Spec->catfile(
    $Root, 'core', 'config', 'programs', 'AgentInternalChat.pm',
);
is( $Program->{Name}, 'AgentInternalChat', 'internal chat endpoint is registered' );
is_deeply( $Program->{AccessTypes}, ['agent'], 'internal chat is restricted to agents' );

my $Schema = content('install/sql/schema.sql');
like( $Schema, qr{CREATE TABLE IF NOT EXISTS `internal_chat_message`}, 'chat messages are persisted' );
like( $Schema, qr{CREATE TABLE IF NOT EXISTS `ticket_presence`}, 'ticket presence is persisted' );
like( $Schema, qr{internal_chat_recipient_read_id}, 'unread chat messages have a dedicated index' );
like( $Schema, qr{ticket_presence_ticket_user_client_unique}, 'ticket presence supports multiple browser tabs safely' );

my $Service = content('core/system/QisutuInternalChat.pm');
like( $Service, qr{last_seen_at >= DATE_SUB\(NOW\(\), INTERVAL 10 MINUTE\)}, 'online state uses the requested ten-minute window' );
like( $Service, qr{Permission => 'ticket[.]edit'}, 'ticket handover verifies recipient queue edit permission' );
like( $Service, qr{TicketOwnerUpdate}, 'ticket handover changes the ticket owner through the ticket API' );
like( $Service, qr{MessageType\s+=> 'ticket_handover'}, 'ticket handover creates a chat event' );
like( $Service, qr{ArticleCreate}, 'ticket handover creates a ticket article' );
like( $Service, qr{Channel\s+=> 'note'}, 'ticket handover article is a note' );
like( $Service, qr{Visibility\s+=> 'agent'}, 'ticket handover note is visible only to agents' );
like( $Service, qr{\{sender\}.*\{recipient\}}s, 'ticket handover note names sender and recipient' );
like( $Service, qr{sub ConversationDelete}, 'chat service provides conversation deletion' );

my $AgentDB = Local::InternalChatDB->new(
    [
        { id => 2, login => 'anna', email => 'anna@example.invalid', firstname => 'Anna', lastname => 'Offline' },
        { id => 3, login => 'bert', email => 'bert@example.invalid', firstname => 'Bert', lastname => 'Online' },
    ],
    [ { id => 3, last_seen_at => '2026-09-03 14:00:00' } ],
    [ { id => 2, unread_count => 2 } ],
);
my $AgentService = QisutuInternalChat->new( Config => {}, DB => $AgentDB );
my $AgentRows = $AgentService->AgentList( UserID => 1 );
is_deeply( [ map { $_->{id} } @{$AgentRows} ], [ 3, 2 ], 'online agents are listed before offline agents' );
is( $AgentRows->[0]->{is_online}, 1, 'recent session marks an agent as online' );
is( $AgentRows->[1]->{unread_count}, 2, 'unread messages are assigned to their sender' );
is( scalar @{ $AgentDB->{SQL} }, 3, 'agent state uses three simple database queries' );
unlike( join( "\n", @{ $AgentDB->{SQL} } ), qr{COALESCE}, 'agent state avoids the failing combined query' );

my $DeleteDB = Local::InternalChatDeleteDB->new();
my $DeleteService = QisutuInternalChat->new( Config => {}, DB => $DeleteDB );
is(
    $DeleteService->ConversationDelete( UserID => 1, PartnerID => 2 ),
    77,
    'conversation deletion returns the synchronization marker ID',
);
is( scalar @{ $DeleteDB->{DoCalls} }, 2, 'conversation deletion performs delete and marker insert' );
like( $DeleteDB->{DoCalls}->[0]->{SQL}, qr{DELETE FROM internal_chat_message}, 'all messages in the selected conversation are deleted' );
is_deeply( $DeleteDB->{DoCalls}->[0]->{Bind}, [ 1, 2, 2, 1 ], 'deletion is restricted to both directions of one agent conversation' );
is( $DeleteDB->{DoCalls}->[1]->{Bind}->[2], 'conversation_deleted', 'an invisible synchronization marker is stored' );
like( $DeleteDB->{DoCalls}->[1]->{SQL}, qr{read_at\s*\)\s*VALUES}s, 'synchronization marker is created as already read' );
is( $DeleteDB->{Committed}, 1, 'conversation deletion is committed atomically' );
is( $DeleteDB->{RolledBack}, 0, 'successful conversation deletion is not rolled back' );

my $Header = content('core/output/Header.tt');
my $LauncherPosition = index( $Header, 'data-qisutu-internal-chat-open' );
my $UserPosition = index( $Header, 'class="qisutu-sidebar-user"' );
ok( $LauncherPosition >= 0 && $LauncherPosition < $UserPosition, 'internal chat button is placed before the sidebar user area' );
like( $Header, qr{data-qisutu-sidebar-actions}, 'sidebar exposes one stable action area for core and add-on launchers' );
like( $Header, qr{data-current-ticket-id="\[% TicketID %\]"}, 'chat receives the current ticket context' );
like( $Header, qr{data-text-invite-colleague}, 'chat receives the translated colleague invitation label' );
like( $Header, qr{data-text-ticket-invitation}, 'chat receives the translated ticket invitation message' );
like( $Header, qr{data-delete-url=.*Step=Delete}, 'chat receives the conversation deletion endpoint' );
like( $Header, qr{data-qisutu-internal-chat-delete hidden}, 'delete button is hidden until a conversation is selected' );

my $TicketZoom = content('core/output/AgentTicketZoom.tt');
like( $TicketZoom, qr{data-qisutu-ticket-presence}, 'ticket detail contains the live presence display' );

my $JavaScript = content('var/static/js/qisutu-internal-chat.js');
like( $JavaScript, qr{AgentRefreshMilliseconds = 10 \* 60 \* 1000}, 'online agent list refreshes every ten minutes' );
like( $JavaScript, qr{MessageRefreshMilliseconds = 4 \* 1000}, 'an open conversation refreshes promptly' );
like( $JavaScript, qr{data-qisutu-chat-agent}, 'ticket viewers can be addressed directly' );
like( $JavaScript, qr{function sidebarActionsSynchronize}, 'sidebar launchers are synchronized through the stable action area' );
like( $JavaScript, qr{KimActions[.]insertBefore\(Launcher, KimLauncher}, 'internal chat launcher is inserted immediately before Kim' );
like( $JavaScript, qr{document[.]querySelector\('\[data-ms365-launcher-open\]'\)}, 'Microsoft 365 Teams launcher is recognized by its dedicated marker' );
like( $JavaScript, qr{TeamsRoot[.]dataset[.]initialized === '1'}, 'Teams is moved only after its add-on initialization completed' );
like( $JavaScript, qr{Actions[.]appendChild\(TeamsLauncher\)}, 'Teams joins the sidebar action area when Kim is absent' );
like( $JavaScript, qr{Observer[.]observe\(document[.]body}, 'delayed add-on launchers are detected outside the sidebar navigation' );
unlike( $JavaScript, qr{Sidebar[.]querySelectorAll\('button, a'\)}, 'ordinary sidebar navigation links are never mistaken for launchers' );
like( $JavaScript, qr{function ticketInvitationStart}, 'an agent can start a ticket invitation from the presence row' );
like( $JavaScript, qr{InviteMode && !Agent[.]is_online}, 'ticket invitations offer only online agents' );
like( $JavaScript, qr{function ticketInvitationSend}, 'selecting an online agent sends the ticket invitation' );
like( $JavaScript, qr{TicketID: CurrentTicketID}, 'the invitation message includes the current ticket context' );
like( $JavaScript, qr{function conversationDelete}, 'selected conversations can be deleted from the chat' );
like( $JavaScript, qr{Message[.]message_type === 'conversation_deleted'}, 'open chats react to deletion on the other side' );
like( $JavaScript, qr{window[.]confirm\(Confirmation\)}, 'chat deletion requires explicit confirmation' );

my $Style = content('var/static/css/qisutu-internal-chat.css');
like( $Style, qr{[.]qisutu-sidebar-collaboration\s*\{[^\}]*position:\s*static}s, 'launchers use a stable row directly above the user area' );
like( $Style, qr{[.]qisutu-sidebar-collaboration\s*\{[^\}]*justify-content:\s*flex-end}s, 'sidebar actions remain aligned together on the right' );
like( $JavaScript, qr{Actions[.]hidden = !Actions[.]querySelector\('button, a'\)}, 'the empty fallback action row is hidden reliably' );
like( $Style, qr{[.]qisutu-sidebar-collaboration\[hidden\]}, 'the hidden fallback action row consumes no sidebar space' );
like( $Style, qr{[.]qisutu-ticket-presence-invite}, 'the ticket presence row styles the colleague invitation button' );
like( $Style, qr{[.]qisutu-internal-chat-delete}, 'the conversation header styles the chat deletion button' );

my @Languages = qw(de en fr it pt-BR pt-PT es nl pl cs tr);
for my $Language (@Languages) {
    my $Translation = do File::Spec->catfile( $Root, 'core', 'language', "$Language.pm" );
    ok( $Translation->{InternalChatTitle}, "$Language contains internal chat translations" );
    like( $Translation->{InternalChatTransferConfirm}, qr{\{agent\}}, "$Language preserves the transfer recipient placeholder" );
    like( $Translation->{InternalChatTransferNoteBody}, qr{\{sender\}}, "$Language preserves the transfer note sender placeholder" );
    like( $Translation->{InternalChatTransferNoteBody}, qr{\{recipient\}}, "$Language preserves the transfer note recipient placeholder" );
    ok( $Translation->{InternalChatInviteColleague}, "$Language contains the colleague invitation label" );
    ok( $Translation->{InternalChatNoOnlineAgents}, "$Language contains the no-online-agent message" );
    ok( $Translation->{InternalChatTicketInvitationMessage}, "$Language contains the automatic ticket invitation" );
    ok( $Translation->{InternalChatDelete}, "$Language contains the chat deletion label" );
    like( $Translation->{InternalChatDeleteConfirm}, qr{\{agent\}}, "$Language preserves the deletion agent placeholder" );
    ok( $Translation->{InternalChatDeleteSuccess}, "$Language contains the deletion success message" );
    ok( $Translation->{InternalChatDeleteFailed}, "$Language contains the deletion error message" );
}

done_testing();
