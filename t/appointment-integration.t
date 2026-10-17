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
BEGIN {
    if (!eval {require DBI; require DBD::SQLite; 1}) {
        plan skip_all => 'Optional integration tests require DBI and DBD::SQLite';
    }
}
use lib File::Spec->catdir($FindBin::Bin,'lib');
use QisutuAppointmentTestDB;
use QisutuAppointment;
use QisutuConfig;
my $Root=File::Spec->rel2abs(File::Spec->catdir($FindBin::Bin,'..'));
my $Temp=tempdir(CLEANUP=>1);
{package TestCalendar;our @ISA=('QisutuAppointment');sub _SendDelivery { return 1; }}
my $DB=QisutuAppointmentTestDB->new(Schema=>File::Spec->catfile($Root,'install','sql','schema.sql'));
my $C=QisutuConfig::Load();$C->{RootPath}=$Root;$C->{Paths}->{SecurityKey}=File::Spec->catfile($Temp,'security.key');
my $A=TestCalendar->new(Config=>$C,DB=>$DB);my $U={user_account_id=>1,account_type=>'agent'};
for my $id(2..4){$DB->Do('INSERT INTO user_account (id,login,account_type,email,password_hash,firstname,lastname) VALUES (?,?,?,?,?,?,?)',$id,'test'.$id,'agent','test'.$id.'@example.invalid','INVALID','Test','Agent'.$id) or die $DB->Error;}
my $V={user_account_id=>2,account_type=>'agent'};my $W={user_account_id=>3,account_type=>'agent'};my $X={user_account_id=>4,account_type=>'agent'};
my $Cal=$A->CalendarSave($U,{name=>'Team Service',color=>'#087e8b',kind=>'team',shares=>[{subject_type=>'user',subject_id=>2,role=>1},{subject_type=>'user',subject_id=>3,role=>3}]});ok($Cal,'Create shared calendar') or die $A->Error;
is($A->Role($V,$Cal->{id}),1,'Busy-only share');is($A->Role($W,$Cal->{id}),3,'Writable share');is($A->Role($X,$Cal->{id}),0,'Unshared calendar inaccessible');
my $Start=QisutuAppointmentTime::Local(time+3600,'Europe/Berlin');my $End=QisutuAppointmentTime::Local(time+7200,'Europe/Berlin');
my $D={calendar_id=>$Cal->{id},title=>'Überprüfung für Kunde',description=>'Änderungen prüfen',timezone=>'Europe/Berlin',start_local=>$Start,end_local=>$End,type=>'maintenance',repeat=>{frequency=>'weekly',count=>3},auto_ticket=>1,ticket_lead=>120,queue_id=>1,priority_id=>3,participants=>[],reminders=>[120],reminder_app=>1};
my $E=$A->Save($U,$D,[{Filename=>'../test.txt',Content=>'Anhang',ContentType=>'text/plain'}]);ok($E,'Create recurring event with attachment') or die $A->Error;
my $Event=$A->EventGet($U,$E->{id});is($Event->{title},'Überprüfung für Kunde','Unicode preserved');is($Event->{attachments}->[0]->{filename},'test.txt','Attachment filename sanitized');
ok(!$A->EventGet($V,$E->{id}),'Busy-only reader cannot retrieve details');ok(!$A->Attachment($V,$Event->{attachments}->[0]->{id}),'Busy-only reader cannot download attachment');
my $From=substr(QisutuAppointmentTime::UTC(time-86400),0,10);my $To=substr(QisutuAppointmentTime::UTC(time+30*86400),0,10);
my $Rows=$A->List($V,{from=>$From,to=>$To});is(scalar(@$Rows),3,'Series has three occurrences');is($Rows->[0]->{title},'Belegt','Busy-only list redacts title');is($Rows->[0]->{description},'','Busy-only list redacts description');is(scalar(@{$A->List($X,{from=>$From,to=>$To})}),0,'Unshared events excluded');
ok(!$A->Save($V,{%$Event,title=>'Unauthorized'},[]),'Busy-only user cannot modify event');
my $First=$DB->SelectRow('SELECT * FROM appointment_occurrence WHERE event_id=? ORDER BY sequence_no',$E->{id});
my $Runs=$A->ProcessDue();ok(defined $Runs,'Scheduler runs') or diag($A->Error);
my $Ticket=$DB->SelectRow('SELECT * FROM ticket ORDER BY id DESC LIMIT 1');ok($Ticket,'Automatic ticket created without customer');is($Ticket->{state_id},2,'Automatic ticket is open');
my $Article=$DB->SelectRow('SELECT * FROM ticket_article WHERE ticket_id=? ORDER BY id DESC LIMIT 1',$Ticket->{id});is($Article->{internal},1,'Automatic ticket article is internal');is($Article->{visibility},'agent','Customer visibility excluded');
my $Linked=$DB->SelectRow('SELECT ticket_id FROM appointment_occurrence WHERE id=?',$First->{id});is($Linked->{ticket_id},$Ticket->{id},'Ticket and occurrence linked');
$A->ProcessDue();is($DB->SelectRow('SELECT COUNT(*) AS n FROM ticket')->{n},1,'Repeated scheduler run does not duplicate ticket');
my $BeforeDuplicate=$DB->SelectRow('SELECT COUNT(*) AS n FROM ticket')->{n};
my $Duplicate=$A->_Ticket->TicketCreateFromAgent(User=>$U,QueueID=>1,StateID=>2,PriorityID=>3,Title=>'Duplicate guard',Body=>'Test',ContentType=>'text/plain',InternalOnly=>1,AppointmentOccurrenceID=>$First->{id});
ok(!$Duplicate,'Already linked occurrence rejected by atomic ticket link');
is($DB->SelectRow('SELECT COUNT(*) AS n FROM ticket')->{n},$BeforeDuplicate,'Failed link rolls back new ticket');
is($DB->SelectRow('SELECT COUNT(*) AS n FROM ticket_article')->{n},1,'Failed link also rolls back article');
my $Notes=$A->Notifications($U);is(scalar(@$Notes),1,'Due in-app reminder appears');ok($A->NotificationRead($U,$Notes->[0]->{id},1),'Snooze reminder');is(scalar(@{$A->Notifications($U)}),0,'Snoozed reminder hidden until due');
my $Second=$DB->SelectRow('SELECT * FROM appointment_occurrence WHERE event_id=? AND sequence_no=1',$E->{id});my $Single=$A->EventGet($U,$E->{id},$Second->{id});
$Single->{scope}='one';$Single->{start_local}=QisutuAppointmentTime::Local(time+3*86400,'Europe/Berlin');$Single->{end_local}=QisutuAppointmentTime::Local(time+3*86400+3600,'Europe/Berlin');
ok($A->Save($U,$Single,[]),'Move one occurrence');is($DB->SelectRow('SELECT COUNT(*) AS n FROM appointment_occurrence WHERE event_id=?',$E->{id})->{n},3,'Moving occurrence preserves series cardinality');
ok(!$A->Save($U,$Single,[]),'Stale edit rejected');like($A->Error,qr/zwischenzeitlich/,'Concurrent modification explained');
my $Master=$A->EventGet($U,$E->{id});$Master->{private}=1;ok($A->Save($U,$Master,[]),'Make series private');
my $Privacy=$A->List($W,{from=>$From,to=>$To});is_deeply([map {$_->{title}} @$Privacy],['Belegt','Belegt','Belegt'],'Private details of exception and master both hidden from writer');ok(!$A->EventGet($W,$E->{id}),'Private event cannot be retrieved by shared writer');
$Master=$A->EventGet($U,$E->{id});ok($A->Cancel($U,{id=>$E->{id},version=>$Master->{version},scope=>'all'}),'Cancel entire series');$A->ProcessDue();is($DB->SelectRow('SELECT COUNT(*) AS n FROM ticket')->{n},1,'Cancel does not delete or duplicate existing ticket');is($DB->SelectRow('SELECT COUNT(*) AS n FROM appointment_occurrence WHERE event_id=? AND cancelled=0',$E->{id})->{n},0,'All remaining occurrences cancelled');
my $Invite={%$D,title=>'Kundengespräch',auto_ticket=>0,repeat=>{frequency=>'none'},send_invites=>1,participants=>[{user_id=>2},{email=>'guest@example.invalid',name=>'Gast'}]};
my $I=$A->Save($U,$Invite,[]);ok($I,'Invitation event created') or diag($A->Error);
my $IEvent=$A->EventGet($V,$I->{id});ok($IEvent,'Invited busy-only user can see their own invitation');ok($A->Respond($V,$I->{id},'accepted'),'Internal attendee can accept');is($DB->SelectRow('SELECT response FROM appointment_invitee WHERE event_id=? AND user_id=2',$I->{id})->{response},'accepted','RSVP saved');
my $Mail=$DB->SelectRow('SELECT payload_json FROM appointment_delivery WHERE event_id=? AND recipient_email=? AND channel="email"',$I->{id},'guest@example.invalid');my $Token=QisutuAppointment::_Data($Mail->{payload_json})->{reply_token};ok($Token&&length($Token)==64,'External invitation uses random token');ok(!$A->PublicReply('0'x64),'Unknown token rejected');ok($A->PublicReply($Token,'accepted'),'External guest can accept');
my $IPrivate=$A->EventGet($U,$I->{id});$IPrivate->{private}=1;$IPrivate->{participants}=[];ok($A->Save($U,$IPrivate,[]),'Remove invitees and make private');ok(!$A->PublicReply($Token),'Removed guest token revoked');
my $Bad={%$D,meeting_url=>'javascript:alert(1)'};ok(!$A->Save($U,$Bad,[]),'Dangerous meeting URL rejected');
my $Number=$DB->SelectRow('SELECT COUNT(*) AS n FROM appointment_event')->{n};ok(!$A->Save($U,{%$D,timezone=>'../../etc/passwd'},[]),'Invalid timezone rejected');is($DB->SelectRow('SELECT COUNT(*) AS n FROM appointment_event')->{n},$Number,'Invalid save leaves database unchanged');
# Reopen a valid event for frontend tests.
$A->Save($U,{%$D,title=>'Geplante Wartung',auto_ticket=>0,repeat=>{frequency=>'none'},private=>0},[]);
done_testing();
