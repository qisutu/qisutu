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
use Test::More;
use Storable qw(dclone);
use lib "$FindBin::Bin/../core/system", "$FindBin::Bin/../core/module";
use QisutuTicket;
use QisutuMail;
use CustomerTicketZoom;

# Keep the production import, article, state, resolver and escalation methods.
# This transactional in-memory DB supplies their SQL boundary and lets tests
# inject failures without sending mail or requiring an installed database.
{
    package Local::FollowUpStateDB;

    sub new {
        my ( $Class, %Param ) = @_;
        my $StateID = $Param{StateID} || 3;
        return bless {
            State => {
                1 => { id => 1, state_type => 'new', sla_pause => 0 },
                2 => { id => 2, state_type => 'open', sla_pause => 0 },
                3 => { id => 3, state_type => 'pending', sla_pause => 1 },
                4 => { id => 4, state_type => 'closed', sla_pause => 0 },
                5 => { id => 5, state_type => 'pending', sla_pause => 0 },
                6 => { id => 6, state_type => 'open', sla_pause => 0 },
            },
            Row => {
                id => 42, ticket_number => '2026000042', title => 'Follow-up',
                queue_id => 7, priority_id => 3, state_id => $StateID,
                created_at => '2026-10-12 08:00:00', changed_at => '2026-10-12 10:00:00',
                pending_until => '2026-10-13 10:00:00',
                pending_started_at => '2026-10-12 10:00:00', pending_total_minutes => 5,
                sla_pause_started_at => $StateID == 3 ? '2026-10-12 10:00:00' : undef,
                sla_pause_total_minutes => 10, sla_source => 'queue',
                follow_up_option => $Param{Mode} || 'reopen', follow_up_allowed => 1,
                last_customer_article_at => '2026-10-12 08:00:00',
                last_agent_article_at => '2026-10-12 09:00:00',
            },
            Articles => [
                { sender_type => 'customer', visibility => 'both', internal => 0, created_at => '2026-10-12 08:00:00' },
                { sender_type => 'agent', visibility => 'both', internal => 0, created_at => '2026-10-12 09:00:00' },
            ],
            Attachments => [], Calls => [], Fail => $Param{Fail} || '',
        }, $Class;
    }

    sub Error { return $_[0]->{Error} || '' }
    sub BeginWork {
        my ($Self) = @_;
        die 'Nested transaction' if $Self->{Snapshot};
        $Self->{Snapshot} = Storable::dclone({ map { $_ => $Self->{$_} } qw(Row Articles Attachments) });
        push @{ $Self->{Calls} }, 'begin';
        return 1;
    }
    sub Commit {
        my ($Self) = @_;
        if ( $Self->{Fail} eq 'commit' ) { $Self->{Error} = 'Injected commit failure'; return }
        delete $Self->{Snapshot};
        push @{ $Self->{Calls} }, 'commit';
        return 1;
    }
    sub Rollback {
        my ($Self) = @_;
        my $Snapshot = delete $Self->{Snapshot};
        @{$Self}{keys %{$Snapshot}} = values %{$Snapshot} if $Snapshot;
        push @{ $Self->{Calls} }, 'rollback';
        return 1;
    }
    sub LastInsertID { return $_[1] eq 'ticket' ? 81 : scalar @{ $_[0]->{Articles} } }
    sub SelectRow {
        my ( $Self, $SQL, @Bind ) = @_;
        return { now_datetime => '2026-10-12 11:00:00' } if $SQL =~ m{SELECT DATE_FORMAT};
        return { next_article_number => scalar(@{ $Self->{Articles} }) + 1 } if $SQL =~ m{next_article_number};
        if ( $SQL =~ m{FROM ticket_state} ) {
            return $Self->{Fail} eq 'open_missing' ? undef : { id => 2 } if $SQL =~ m{state_type =};
            return $Self->{State}->{ $Bind[0] };
        }
        return { id => $Bind[0] } if $SQL =~ m{FROM ticket_(?:queue|priority)};
        return if $SQL =~ m{FROM system_setting};
        if ( $SQL =~ m{FROM ticket_article} ) {
            my @Agent = sort map { $_->{created_at} } grep {
                $_->{sender_type} eq $Bind[0] && !$_->{internal}
                    && ( $_->{visibility} eq $Bind[1] || $_->{visibility} eq $Bind[2] )
            } @{ $Self->{Articles} };
            my @Customer = sort map { $_->{created_at} } grep {
                $_->{sender_type} eq $Bind[6]
                    && ( $_->{visibility} eq $Bind[7] || $_->{visibility} eq $Bind[8] )
            } @{ $Self->{Articles} };
            return { first_agent_response_at => $Agent[0], last_agent_article_at => $Agent[-1], last_customer_article_at => $Customer[-1] };
        }
        if ( $SQL =~ m{FROM ticket t} ) {
            my $State = $Self->{State}->{ $Self->{Row}->{state_id} };
            return { %{ $Self->{Row} }, state_type => $State->{state_type}, current_state_type => $State->{state_type},
                sla_pause => $State->{sla_pause}, current_sla_pause => $State->{sla_pause}, queue_calendar_id => 7 };
        }
        die "Unexpected SelectRow: $SQL";
    }
    sub Do {
        my ( $Self, $SQL, @Bind ) = @_;
        if ( ( $Self->{Fail} eq 'article' && $SQL =~ m{INSERT INTO ticket_article} )
            || ( $Self->{Fail} eq 'state' && $SQL =~ m{SET state_id =} )
            || ( $Self->{Fail} eq 'escalation' && $SQL =~ m{SET first_response_due_at =} )
        ) { $Self->{Error} = 'Injected database failure'; return }
        if ( $SQL =~ m{INSERT INTO ticket_article} ) {
            push @{ $Self->{Articles} }, { sender_type => $Bind[3], visibility => $Bind[13], internal => $Bind[14], body => $Bind[10], created_at => '2026-10-12 11:00:00' };
        }
        elsif ( $SQL =~ m{INSERT INTO ticket \(} ) {
            $Self->{Row}->{id} = 81;
            $Self->{Row}->{state_id} = $Bind[3];
        }
        elsif ( $SQL =~ m{SET state_id =} ) {
            my $Row = $Self->{Row};
            $Row->{state_id} = $Bind[0];
            $Row->{pending_total_minutes} += $Bind[1];
            $Row->{pending_started_at} = undef if $Bind[2] ne 'pending';
            $Row->{pending_until} = $Bind[4];
            $Row->{sla_pause_total_minutes} += $Bind[5];
            $Row->{sla_pause_started_at} = undef if !$Bind[6];
        }
        elsif ( $SQL =~ m{SET first_response_due_at =} ) {
            my @Name = qw(first_response_due_at first_response_at update_due_at last_customer_article_at last_agent_article_at solution_due_at solution_at escalation_state sla_first_response_breached sla_update_breached sla_solution_breached changed_by_user_id);
            @{$Self->{Row}}{@Name} = @Bind[0..$#Name];
        }
        return 1;
    }
}

{
    package Local::FollowUpStateTicket;
    use parent 'QisutuTicket';
    sub _TicketHook { return 'Qisutu' }
    sub _TicketNumberCreate { return '202610120081' }
    sub _DefaultStateID { return 1 }
    sub _DefaultPriorityID { return 3 }
    sub _CustomerByEmail { return }
    sub _PostmasterDynamicFieldsApply { return 1 }
    sub _TicketArticleVisibilityColumnExists { return 1 }
    sub _WorkingMinutesBetween { return 60 }
    sub _PostmasterPendingUntil { return '2026-10-13 12:00:00' }
    sub _AddonEventEmit { return 1 }
    sub TicketGet { return $_[0]->{DB}->SelectRow('FROM ticket t') }
    sub ArticleList { return [] }
    sub _ArticleAttachmentsCreate {
        my ( $Self, %Param ) = @_;
        push @{ $Self->{DB}->{Attachments} }, @{ $Param{Attachments} };
        return 1;
    }
    sub _AgentNotificationSend {
        my ( $Self, %Param ) = @_;
        die 'Notification before commit' if $Self->{DB}->{Snapshot};
        push @{ $Self->{Notifications} }, $Param{NotificationType};
        return 1;
    }
    sub _CustomerAutoResponseSend {
        my ( $Self, %Param ) = @_;
        die 'Auto-response before commit' if $Self->{DB}->{Snapshot};
        push @{ $Self->{ResponseHeaders} }, $Param{Headers};
        return 0 if QisutuMail->AutoResponseSuppressed( Headers => $Param{Headers} );
        push @{ $Self->{Responses} }, $Param{ResponseType};
        return 1;
    }
}

sub _Ticket {
    return Local::FollowUpStateTicket->new( Config => {}, DB => Local::FollowUpStateDB->new(@_) );
}
my %Message = ( ExistingTicketID => 42, Subject => '[Qisutu#2026000042] Reply', Body => 'Customer answer',
    FromEmail => 'customer@example.test', CreatedByUserID => 1 );
my %Automatic = ( %Message, Headers => { 'auto-submitted' => 'auto-replied' } );

for my $StateID ( 2, 3, 4, 5 ) {
    for my $Mode ( qw(reopen new_ticket reject) ) {
        my $Ticket = _Ticket( StateID => $StateID, Mode => $Mode );
        is( $Ticket->TicketCreateFromEmail(%Automatic), 42, "$StateID/$Mode: automated reply stays on the original ticket" );
        is( $Ticket->{DB}->{Row}->{state_id}, $StateID, "$StateID/$Mode: state is unchanged" );
        my $Article = $Ticket->{DB}->{Articles}->[-1];
        is_deeply( [ @{$Article}{qw(sender_type visibility internal body)} ], ['system', 'agent', 1, 'Customer answer'], "$StateID/$Mode: complete internal system article" );
        is( $Ticket->{DB}->{Row}->{last_customer_article_at}, '2026-10-12 08:00:00', "$StateID/$Mode: last customer contact is unchanged" );
        is( $Ticket->{DB}->{Row}->{last_agent_article_at}, '2026-10-12 09:00:00', "$StateID/$Mode: last agent response is unchanged" );
        is_deeply( $Ticket->{Notifications} || [], [], "$StateID/$Mode: no reply notification" );
        is_deeply( $Ticket->{Responses} || [], [], "$StateID/$Mode: no automatic customer response" );
        is( $Ticket->LastEmailImportAction(), 'updated', "$StateID/$Mode: reported as updated" );
        is_deeply( $Ticket->LastEmailImportDetails(), { AutomatedMessage => 1, SenderType => 'system', Visibility => 'agent' }, "$StateID/$Mode: log reflects actual article classification" );
    }
}

for my $StateID ( 3, 5 ) {
    my $Ticket = _Ticket( StateID => $StateID );
    is( $Ticket->TicketCreateFromEmail(%Message), 42, "$StateID: genuine customer reply imports" );
    my $Row = $Ticket->{DB}->{Row};
    is( $Row->{state_id}, 2, "$StateID: pending state becomes open regardless of SLA pause flag" );
    ok( !defined $Row->{pending_started_at} && !defined $Row->{pending_until}, "$StateID: pending start and deadline cleared" );
    is( $Row->{pending_total_minutes}, 65, "$StateID: pending working minutes are preserved" );
    is( $Row->{sla_pause_total_minutes}, $StateID == 3 ? 70 : 10, "$StateID: only active SLA pauses are accounted" );
    ok( !defined $Row->{sla_pause_started_at}, "$StateID: SLA pause ended" );
    is( $Row->{last_customer_article_at}, '2026-10-12 11:00:00', "$StateID: genuine customer reply updates contact time" );
    is_deeply( $Ticket->{Notifications}, ['customer_reply_in_my_queues', 'ticket_state_changed'], "$StateID: both notifications occur once after commit" );
}

for my $Headers ( { 'precedence' => 'list' }, { 'precedence' => 'bulk' }, { 'x-auto-response-suppress' => 'All' } ) {
    my $Ticket = _Ticket();
    $Ticket->TicketCreateFromEmail( %Message, Headers => $Headers );
    is( $Ticket->{DB}->{Articles}->[-1]->{sender_type}, 'customer', 'response-suppression header retains customer classification' );
    is( $Ticket->{DB}->{Row}->{state_id}, 2, 'response-suppression header does not prevent pending state from ending' );
    is_deeply( $Ticket->{Responses} || [], [], 'receipt suppression is independent of article classification' );
    is_deeply( $Ticket->{ResponseHeaders}->[0], $Headers, 'incoming headers reach the response sender' );
}

for my $Post ( { StateID => 6 }, { StateID => 5, PendingMinutes => 120 }, { PendingMinutes => 120 } ) {
    my $Ticket = _Ticket();
    ok( $Ticket->TicketCreateFromEmail( %Message, PostmasterResult => $Post ), 'filtered customer reply imports' );
    is( $Ticket->{DB}->{Row}->{state_id}, $Post->{StateID} || 3, 'explicit filter state/pending action takes precedence' );
}
my $Closed = _Ticket( StateID => 4 );
$Closed->TicketCreateFromEmail( %Message, PostmasterResult => { StateID => 6 } );
is( $Closed->{DB}->{Row}->{state_id}, 6, 'closed-ticket reopen routing preserves an explicit filter state' );
my $Override = _Ticket();
$Override->TicketCreateFromEmail( %Automatic, PostmasterResult => { StateID => 6, SenderType => 'customer', ArticleVisibility => 'both' } );
is( $Override->{DB}->{Row}->{state_id}, 6, 'automated mail still applies explicit filter state' );
is( $Override->{DB}->{Articles}->[-1]->{sender_type}, 'customer', 'explicit sender override is honored' );
is_deeply( $Override->{Responses} || [], [], 'sender override cannot cause an automatic response loop' );
is_deeply( $Override->{Notifications}, ['ticket_state_changed'], 'explicit state action emits its status notification without a customer-reply notification' );

my $AttachmentTicket = _Ticket();
my $Attachment = { Filename => 'absence.txt', Content => 'Information', ContentType => 'text/plain' };
$AttachmentTicket->TicketCreateFromEmail( %Automatic, Attachments => [$Attachment] );
is_deeply( $AttachmentTicket->{DB}->{Attachments}, [$Attachment], 'automatic-message attachment content is retained' );

my $New = _Ticket();
{
    no warnings 'redefine';
    local *QisutuChecklist::TicketAutoCreate = sub { return 1 };
    is( $New->TicketCreateFromEmail( %Automatic, ExistingTicketID => 0, Subject => 'Automatic new mail', QueueID => 7 ), 81, 'automated mail without a ticket reference still creates a ticket' );
}
is_deeply( $New->{Responses} || [], [], 'new automated ticket does not produce a receipt' );
is( $New->LastEmailImportAction(), 'created', 'new automated ticket has the correct import action' );

for my $Fail ( qw(article state escalation commit open_missing) ) {
    my $Ticket = _Ticket( Fail => $Fail );
    my $Before = dclone( $Ticket->{DB}->{Row} );
    ok( !$Ticket->TicketCreateFromEmail(%Message), "$Fail: failed import reports failure" );
    is_deeply( $Ticket->{DB}->{Row}, $Before, "$Fail: ticket changes are rolled back" );
    is( scalar @{ $Ticket->{DB}->{Articles} }, 2, "$Fail: no partial article survives" );
    is_deeply( $Ticket->{Notifications} || [], [], "$Fail: no premature notification" );
    is_deeply( $Ticket->{Responses} || [], [], "$Fail: no premature receipt" );
}

{
    package Local::FollowUpPortal;
    use parent 'CustomerTicketZoom';
    sub _TicketObject { return $_[0]->{Ticket} }
    sub _TicketFormObject { return }
    sub _QueueAddress { return ('Support', 'support@example.test') }
}
for my $Fail ( '', 'state', 'commit' ) {
    my $Ticket = _Ticket( Fail => $Fail );
    my $Portal = Local::FollowUpPortal->new( Config => {}, DB => $Ticket->{DB} );
    $Portal->{Ticket} = $Ticket;
    my $Result;
    {
        no warnings 'redefine';
        local *QisutuCMDB::CustomerTicketSummaryHTML = sub { return '' };
        $Result = $Portal->Run( Request => { Step => 'CustomerArticleCreate', TicketID => 42, Subject => 'Reply', Body => '<p>Customer answer</p>' },
            User => { user_account_id => 9, email => 'customer@example.test' } );
    }
    if ($Fail) {
        ok( !$Result->{Redirect}, "portal $Fail: failure is shown instead of redirecting" );
        is( $Ticket->{DB}->{Row}->{state_id}, 3, "portal $Fail: original pending state retained" );
        is( scalar @{ $Ticket->{DB}->{Articles} }, 2, "portal $Fail: reply rolled back" );
        is_deeply( $Ticket->{Notifications} || [], [], "portal $Fail: no premature notifications" );
        is_deeply( $Ticket->{Responses} || [], [], "portal $Fail: no premature receipt" );
    }
    else {
        ok( $Result->{Redirect}, 'portal reply succeeds' );
        is( $Ticket->{DB}->{Row}->{state_id}, 2, 'portal reply ends pending state' );
        is_deeply( $Ticket->{Notifications}, ['customer_reply_in_my_queues', 'ticket_state_changed'], 'portal emits each notification once, after commit' );
        is_deeply( $Ticket->{Responses}, ['customer_ticket_reply'], 'portal emits one customer receipt' );
    }
}

# Execute the importer's actual routing preamble; this catches rejection and
# new-ticket decisions made before TicketCreateFromEmail is reached.
my $Fetch = do {
    open my $FH, '<', "$FindBin::Bin/../bin/qisutu-mail-fetch.pl" or die $!;
    local $/; <$FH>;
};
my ($Routing) = $Fetch =~ m{(            my \$ExistingTicketID = \$TicketObject->TicketIDFromSubject\(.*?)(?=            if \(\$CommunicationID\))}s;
ok( $Routing, 'mail-fetch routing preamble is available for execution' );
{
    package Local::RoutingProbe;
    sub TicketIDFromSubject { return 42 }
    sub ClosedTicketFollowUpGet { return { IsClosed => 1, Mode => $_[0]->{Mode} } }
}
for my $Mode ( qw(reopen new_ticket reject) ) {
    my $TicketObject = bless { Mode => $Mode }, 'Local::RoutingProbe';
    my $Message = { subject => 'Reply', headers => $Automatic{Headers} };
    my $Context = eval $Routing . '[ $ClosedFollowUpMode, $MessageScope, $FilterExistingTicketID ]';
    die $@ if $@;
    is_deeply( $Context, ['', 'follow_up', 42], "$Mode: automated replies reach follow-up filters on the existing ticket" );
    $Message->{headers} = {};
    $Context = eval $Routing . '[ $ClosedFollowUpMode, $MessageScope, $FilterExistingTicketID ]';
    die $@ if $@;
    is_deeply( $Context, [$Mode, $Mode eq 'new_ticket' ? 'new' : 'follow_up', $Mode eq 'new_ticket' ? 0 : 42], "$Mode: genuine closed-ticket follow-up policy is retained" );
}

done_testing();

