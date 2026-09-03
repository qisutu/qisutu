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

use QisutuAdmin;
use QisutuTicket;

{
    package Local::FollowUpDB;

    sub new {
        my ( $Class, %Param ) = @_;
        return bless { Row => $Param{Row} || {}, InsertID => 81 }, $Class;
    }

    sub Error { return '' }
    sub BeginWork { return 1 }
    sub Commit { return 1 }
    sub Rollback { return 1 }
    sub Do { return 1 }
    sub LastInsertID { return shift->{InsertID} }

    sub SelectRow {
        my ( $Self, $SQL ) = @_;
        return { %{ $Self->{Row} } } if $SQL =~ m{q[.]follow_up_option}i;
        return;
    }
}

my $DB = Local::FollowUpDB->new(
    Row => {
        id                => 42,
        queue_id          => 7,
        state_type        => 'closed',
        follow_up_allowed => 1,
        follow_up_option  => 'new_ticket',
    },
);
my $Ticket = QisutuTicket->new( Config => {}, DB => $DB );
my $Admin  = QisutuAdmin->new( Config => {}, DB => $DB );

is( $Admin->_QueueFollowUpOption( Value => 'reopen' ), 'reopen', 'the queue stores the reopen radio option' );
is( $Admin->_QueueFollowUpOption( Value => 'new_ticket' ), 'new_ticket', 'the queue stores the new-ticket radio option' );
is( $Admin->_QueueFollowUpOption( Value => 'reject' ), 'reject', 'the queue stores the reject radio option' );
ok( !$Admin->_QueueFollowUpOption( Value => 'invalid' ), 'invalid queue follow-up values are rejected' );

is_deeply(
    $Ticket->ClosedTicketFollowUpGet( TicketID => 42 ),
    { TicketID => 42, QueueID => 7, IsClosed => 1, Mode => 'new_ticket' },
    'the closed-ticket follow-up setting is loaded from the ticket queue',
);

$DB->{Row}->{follow_up_option}  = '';
$DB->{Row}->{follow_up_allowed} = 0;
is(
    $Ticket->ClosedTicketFollowUpGet( TicketID => 42 )->{Mode},
    'reject',
    'legacy disabled follow-ups are migrated safely to rejection behavior',
);

{
    package Local::RoutingTicket;
    use parent 'QisutuTicket';

    sub ClosedTicketFollowUpGet { return shift->{Decision} }
    sub _OpenStateID { return 2 }
    sub _TicketHook { return 'Qisutu' }
    sub _TicketNumberCreate { return '202607220001' }
    sub _PostmasterDynamicFieldsApply { return 1 }
    sub _AgentNotificationSend { return 1 }
    sub _CustomerAutoResponseSend { return 1 }
    sub _AddonEventEmit { return 1 }

    sub _TicketReplyCreateFromEmail {
        my ( $Self, %Param ) = @_;
        $Self->{ReplyParam} = \%Param;
        return $Param{TicketID};
    }

    sub _PostmasterTicketDataResolve {
        my ( $Self, %Param ) = @_;
        $Self->{NewTicketResolveParam} = \%Param;
        return {
            queue_id                    => $Param{QueueID},
            state_id                    => 1,
            priority_id                 => 3,
            customer_id                 => undef,
            customer_user_id            => undef,
            owner_user_id               => undef,
            responsible_user_id         => undef,
            service_id                  => undef,
            sla_id                      => undef,
            sla_source                  => 'queue',
            sla_assignment_source       => 'queue',
            sla_name_snapshot           => '',
            sla_calendar_id             => undef,
            sla_update_mode             => 'customer',
            sla_first_response_minutes  => 0,
            sla_update_minutes          => 0,
            sla_solution_minutes        => 0,
            state_type                  => 'new',
            pending_until               => undef,
            state_sla_pause             => 0,
        };
    }

    sub ArticleCreate {
        my ( $Self, %Param ) = @_;
        $Self->{ArticleParam} = \%Param;
        return 91;
    }
}

my $Routing = Local::RoutingTicket->new(
    Config => { System => { TicketHook => 'Qisutu' } },
    DB     => Local::FollowUpDB->new(),
);

$Routing->{Decision} = { TicketID => 42, QueueID => 7, IsClosed => 1, Mode => 'reopen' };
is(
    $Routing->TicketCreateFromEmail(
        ExistingTicketID => 42,
        Subject          => '[Qisutu#2026000042] Re: Drucker',
        Body             => 'Antwort',
    ),
    42,
    'the reopen option keeps the reply on the existing ticket',
);
is( $Routing->{ReplyParam}->{PostmasterResult}->{StateID}, 2, 'the existing closed ticket is explicitly changed to the open state' );

$Routing->{Decision} = { TicketID => 42, QueueID => 7, IsClosed => 1, Mode => 'reject' };
ok(
    !$Routing->TicketCreateFromEmail(
        ExistingTicketID => 42,
        Subject          => '[Qisutu#2026000042] Re: Drucker',
        Body             => 'Antwort',
    ),
    'the reject option creates neither a reply nor a ticket',
);
is( $Routing->LastEmailImportAction(), 'rejected', 'the mail importer can send the configured rejection response' );

$Routing->{Decision} = { TicketID => 42, QueueID => 7, IsClosed => 1, Mode => 'new_ticket' };
{
    no warnings 'redefine';
    local *QisutuChecklist::TicketAutoCreate = sub { return 1 };
    is(
        $Routing->TicketCreateFromEmail(
            ExistingTicketID => 42,
            QueueID          => 3,
            Subject          => '[Qisutu#2026000042] Re: Drucker',
            Body             => 'Antwort',
        ),
        81,
        'the new-ticket option creates a separate ticket',
    );
}
is( $Routing->{NewTicketResolveParam}->{QueueID}, 7, 'the new ticket stays in the queue of the closed ticket' );
unlike( $Routing->{ArticleParam}->{Subject}, qr{2026000042}, 'the new ticket article contains no reference to the old closed ticket' );
is( $Routing->LastEmailImportAction(), 'created', 'the new-ticket follow-up is reported as a new ticket' );

my $Root = File::Spec->catdir( $FindBin::Bin, '..' );
my $Template = _Read( File::Spec->catfile( $Root, 'core', 'output', 'AdminQueues.tt' ) );
for my $Value ( qw(reopen new_ticket reject) ) {
    my $Count = () = $Template =~ m{type="radio"\s+name="FollowUpOption"\s+value="\Q$Value\E"}g;
    is( $Count, 2, "the $Value option is available when creating and editing queues" );
}
unlike( $Template, qr{name="FollowUpAllowed"}, 'the old follow-up checkbox is no longer rendered' );

my $Schema = _Read( File::Spec->catfile( $Root, 'install', 'sql', 'schema.sql' ) );
like( $Schema, qr{`follow_up_option`\s+varchar\(20\)}, 'fresh installations include the three-way queue setting' );
like( $Schema, qr{VALUES \('2[.]0[.]1'\)}, 'fresh installations use database version 2.0.1' );
like( $Schema, qr{`follow_up_option` varchar\(20\) NOT NULL DEFAULT 'reopen'}, 'the fresh-install default reopens a closed ticket' );

my $MailFetch = _Read( File::Spec->catfile( $Root, 'bin', 'qisutu-mail-fetch.pl' ) );
like( $MailFetch, qr{QueueClosedTicketFollowUpRejected}, 'queue-level rejection uses the existing automatic rejection path' );
like( $MailFetch, qr{ClosedFollowUpMode\s+ne\s+'new_ticket'}, 'new-ticket follow-ups are evaluated as new incoming mail' );

done_testing();

sub _Read {
    my ($File) = @_;
    open my $Handle, '<:encoding(UTF-8)', $File or die "Could not read $File: $!";
    local $/;
    my $Content = <$Handle>;
    close $Handle;
    return $Content;
}
