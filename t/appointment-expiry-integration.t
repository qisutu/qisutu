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
use Test::More;
use File::Spec;
use File::Temp qw(tempdir);
use FindBin;
our $Clock;
BEGIN {
    *CORE::GLOBAL::time = sub () { defined $Clock ? $Clock : CORE::time() };
    if (!eval { require DBI; require DBD::SQLite; 1 }) {
        plan skip_all => 'Optional integration tests require DBI and DBD::SQLite';
    }
}
use lib File::Spec->catdir($FindBin::Bin, 'lib');
use QisutuAppointmentTestDB;
use QisutuAppointment;
use QisutuAutomation;
use QisutuConfig;

my $Root=File::Spec->rel2abs(File::Spec->catdir($FindBin::Bin,'..'));
my $Temp=tempdir(CLEANUP=>1);
my $User={user_account_id=>1,account_type=>'agent'};
my @Notifications;
{
    no warnings 'redefine';
    local *QisutuTicket::_AgentNotificationSend=sub {
        my ($Self,%Param)=@_;
        push @Notifications,$Param{TicketID};
        return 1;
    };

    subtest 'Deleting a ticket preserves the processed occurrence' => sub {
        my ($A,$DB,$Config,$CID)=fixture();
        my $Event=save_event($A,$CID);
        at('2026-10-17 14:05:14');
        is($A->ProcessDue(),1,'Seven minutes of planning lead is enough');
        my $Old=occurrence($DB,$Event,0);
        ok($Old->{ticket_id},'Occurrence is linked to its ticket');
        my $Automation=QisutuAutomation->new(Config=>$Config,DB=>$DB);
        my $Deleted=$Automation->TicketDeleteComplete(TicketID=>$Old->{ticket_id});
        ok($Deleted && $Deleted->{deleted},'Ticket is deleted by the production routine') or diag($Automation->Error);
        ok(!$DB->SelectRow('SELECT id FROM ticket WHERE id=?',$Old->{ticket_id}),'Ticket itself is gone');
        my $After=occurrence($DB,$Event,0);
        ok($After,'Calendar occurrence remains') or return;
        is($After->{id},$Old->{id},'Occurrence identity is preserved');
        is($After->{ticket_id},$Old->{ticket_id},'Historical ticket ID prevents another creation');
        my $Data=$A->EventGet($User,$Event->{id});
        $Data->{description}='Changed after ticket deletion';
        ok($A->Save($User,$Data,[]),'Editing the calendar still works');
        is($A->ProcessDue(),0,'No duplicate on the same local day');
        at('2026-10-18 02:00:29');
        is($A->ProcessDue(),0,'No duplicate at the UTC day change');
        is(occurrence($DB,$Event,0)->{ticket_due_at},$Old->{ticket_due_at},'Original deadline of a processed occurrence is retained');
        is(scalar @Notifications,1,'No duplicate assignment notification');
    };

    subtest 'Existing pending deadline expires at local midnight' => sub {
        my ($A,$DB,undef,$CID)=fixture();
        my $Event=save_event($A,$CID);
        at('2026-10-18 00:00:00');
        is($A->ProcessDue(),0,'Yesterday is rejected even before UTC midnight');
        ok(!defined occurrence($DB,$Event,0)->{ticket_due_at},'Expired pending deadline is retired');
        at('2026-10-18 02:00:29');
        is($A->ProcessDue(),0,'Daily expansion does not rearm it');
        is(scalar @Notifications,0,'Expired deadline never sends an assignment notification');
        my $Data=$A->EventGet($User,$Event->{id});
        $Data->{start_local}='2026-10-19T14:05';
        $Data->{end_local}='2026-10-19T14:35';
        ok($A->Save($User,$Data,[]),'An explicitly rescheduled event can receive a future deadline');
        at('2026-10-19 14:05:15');
        is($A->ProcessDue(),1,'The new future deadline is processed');
    };

    subtest 'Rebuilding a missing past occurrence creates no ticket' => sub {
        my ($A,$DB,undef,$CID)=fixture();
        my $Event=save_event($A,$CID);
        $DB->Do('DELETE FROM appointment_occurrence WHERE event_id=?',$Event->{id}) or die $DB->Error;
        at('2026-10-18 02:00:29');
        is($A->ProcessDue(),0,'Rebuilt past occurrence cannot create a late ticket');
        my $Occurrence=occurrence($DB,$Event,0);
        ok($Occurrence,'Calendar occurrence is restored for display');
        ok(!defined $Occurrence->{ticket_due_at},'Restored occurrence has no armed past deadline');
        is(scalar @Notifications,0,'Rebuilding sends no assignment notification');
    };

    subtest 'Recurring appointments retain future ticket generation' => sub {
        my ($A,$DB,undef,$CID)=fixture();
        my $Event=save_event($A,$CID,repeat=>{frequency=>'daily',count=>3});
        at('2026-10-18 02:00:29');
        is($A->ProcessDue(),0,'Yesterday is skipped and today is not processed early');
        at('2026-10-18 14:05:15');
        is($A->ProcessDue(),1,'Today recurring occurrence still creates its ticket');
        ok(!occurrence($DB,$Event,0)->{ticket_id},'Yesterday has no ticket');
        ok(occurrence($DB,$Event,1)->{ticket_id},'Today is linked');
        ok(!occurrence($DB,$Event,2)->{ticket_id},'Tomorrow is still pending');
        is($A->ProcessDue(),0,'Repeated run does not duplicate today');
        is(scalar @Notifications,1,'Only today receives a notification');
    };

    subtest 'Lead time uses the ticket deadline local day' => sub {
        my ($A,$DB,undef,$CID)=fixture();
        my $Event=save_event($A,$CID,start_local=>'2026-10-18T14:05',end_local=>'2026-10-18T14:35',ticket_lead=>1440);
        at('2026-10-18 00:05:00');
        is($A->ProcessDue(),0,'Yesterday ticket deadline is expired even if appointment start is today');
        ok(!occurrence($DB,$Event,0)->{ticket_id},'No late lead-time ticket is created');
        is(scalar @Notifications,0,'No late lead-time notification');
    };

    subtest 'Editing an individual exception retires a past deadline' => sub {
        my ($A,$DB,undef,$CID)=fixture();
        my $Event=save_event($A,$CID,repeat=>{frequency=>'daily',count=>3});
        my $Second=occurrence($DB,$Event,1);
        at('2026-10-18 02:00:29');
        my $Data=$A->EventGet($User,$Event->{id},$Second->{id});
        $Data->{scope}='one';
        $Data->{start_local}='2026-10-17T20:00';
        $Data->{end_local}='2026-10-17T20:30';
        ok($A->Save($User,$Data,[]),'Exception save accepts the explicit NULL deadline bind') or diag($A->Error);
        my $Saved=occurrence($DB,$Event,1);
        is($Saved->{is_exception},1,'Exception remains an exception');
        ok(!defined $Saved->{ticket_due_at},'Past exception deadline is not armed');
        is($A->ProcessDue(),0,'Neither past regular nor past exception occurrence creates a ticket');
        is(scalar @Notifications,0,'No notifications for expired occurrences');
    };
}
done_testing();

sub at {
    $Clock=QisutuAppointmentTime::LocalEpoch($_[0],'Europe/Berlin');
    die 'Invalid test clock' if !defined $Clock;
}
sub fixture {
    at('2026-10-17 13:58:00');
    @Notifications=();
    my $DB=QisutuAppointmentTestDB->new(Schema=>File::Spec->catfile($Root,'install','sql','schema.sql'));
    my $Config=QisutuConfig::Load();
    $Config->{RootPath}=$Root;
    $Config->{Paths}->{SecurityKey}=File::Spec->catfile($Temp,'security.key');
    my $A=QisutuAppointment->new(Config=>$Config,DB=>$DB);
    my $Cal=$A->CalendarSave($User,{name=>'Expiry test',color=>'#087e8b',kind=>'personal',shares=>[]}) or die $A->Error;
    return ($A,$DB,$Config,$Cal->{id});
}
sub save_event {
    my ($A,$CID,%Overrides)=@_;
    my $Saved=$A->Save($User,{
        calendar_id=>$CID,title=>'Zweiter Termintest',description=>'Calendar expiry regression',
        timezone=>'Europe/Berlin',start_local=>'2026-10-17T14:05',end_local=>'2026-10-17T14:35',
        type=>'maintenance',repeat=>{frequency=>'none'},auto_ticket=>1,ticket_lead=>0,
        queue_id=>1,priority_id=>3,participants=>[],reminders=>[],%Overrides,
    },[]) or die $A->Error;
    return $Saved;
}
sub occurrence {
    my ($DB,$Event,$Sequence)=@_;
    return $DB->SelectRow('SELECT * FROM appointment_occurrence WHERE event_id=? AND sequence_no=?',$Event->{id},$Sequence);
}
