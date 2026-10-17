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
    if (!eval { require DBI; require DBD::SQLite; 1 }) {
        plan skip_all => 'Optional integration tests require DBI and DBD::SQLite';
    }
}
use lib File::Spec->catdir($FindBin::Bin, 'lib');
use QisutuAppointmentTestDB;
use QisutuAppointment;
use QisutuConfig;
use QisutuNotification;
use QisutuMail;

my $Root = File::Spec->rel2abs(File::Spec->catdir($FindBin::Bin, '..'));
my $Temp = tempdir(CLEANUP => 1);
my $DB = QisutuAppointmentTestDB->new(Schema => File::Spec->catfile($Root, 'install', 'sql', 'schema.sql'));
# Apply the column normally ensured by QisutuNotification::SchemaEnsure.
$DB->Do('ALTER TABLE agent_notification_template ADD COLUMN article_body_default_migrated INTEGER NOT NULL DEFAULT 0') or die $DB->Error;
my $Config = QisutuConfig::Load();
$Config->{RootPath} = $Root;
$Config->{Paths}->{SecurityKey} = File::Spec->catfile($Temp, 'security.key');
$Config->{System}->{BaseURL} = 'https://support.example.invalid/qisutu';
my $User = { user_account_id => 1, account_type => 'agent' };
my $Calendar = QisutuAppointment->new(Config => $Config, DB => $DB);
my $TicketObject = $Calendar->_Ticket();
for my $ID (2, 3) {
    $DB->Do('INSERT INTO user_account (id,login,account_type,email,password_hash,firstname,lastname) VALUES (?,?,?,?,?,?,?)',
        $ID, 'agent'.$ID, 'agent', 'agent'.$ID.'@example.invalid', 'INVALID', 'Agent', $ID) or die $DB->Error;
    $DB->Do('INSERT INTO user_group_member (user_group_id,user_account_id,role_name,active,permission_full,created_by_user_id,changed_by_user_id) VALUES (2,?,"agent",1,1,1,1)', $ID) or die $DB->Error;
}
$DB->Do('INSERT INTO smtp_account (name,smtp_username) VALUES (?,?)', 'Test SMTP', 'support@example.invalid') or die $DB->Error;
my $Cal = $Calendar->CalendarSave($User, { name => 'Notification test', color => '#087e8b', kind => 'personal', shares => [] }) or die $Calendar->Error;

my @Mail;
my @NotificationErrors;
my $SMTPFailure = 0;
{
    no warnings 'redefine';
    # The installation schema already exists in the test database. Only the
    # MariaDB schema checks and real SMTP transport are replaced here.
    local *QisutuNotification::SchemaEnsure = sub { return 1; };
    local *QisutuNotification::_SystemSettingObject = sub { return; };
    my $Send = QisutuNotification->can('Send');
    local *QisutuNotification::Send = sub {
        my $Sent = $Send->(@_);
        push @NotificationErrors, $_[0]->Error() if $_[0]->Error();
        return $Sent;
    };
    local *QisutuMail::SMTPSend = sub {
        my ($Self, %Param) = @_;
        my $Linked = $DB->SelectRow('SELECT id FROM appointment_occurrence WHERE ticket_id=?', $Param{TicketID});
        push @Mail, { %Param, committed => $DB->{DBH}->{AutoCommit} ? 1 : 0, linked => $Linked ? 1 : 0 };
        return $SMTPFailure ? { Success => 0, Message => 'Simulated SMTP failure' } : { Success => 1 };
    };

    my $First = due_event(repeat => { frequency => 'daily', count => 2 });
    ok(defined $Calendar->ProcessDue(), 'Scheduler creates first calendar ticket');
    is(scalar @Mail, 1, 'Calendar ticket sends one agent notification') or diag(join('; ', @NotificationErrors));
    my $Sent = $Mail[0] || {};
    is($Sent->{ToEmail}, 'admin@example.invalid', 'Default owner receives the notification even when also the planner');
    is($Sent->{Operation}, 'notification', 'Calendar ticket uses the standard agent notification mail path');
    is($Sent->{committed}, 1, 'Notification is sent only after ticket commit');
    is($Sent->{linked}, 1, 'Calendar occurrence is linked before notification is sent');
    like($Sent->{Body} || '', qr/Kalender-Benachrichtigung/, 'Notification contains the calendar ticket title');
    like($Sent->{Body} || '', qr/AgentTicketZoom/, 'Notification contains a link to the created ticket');
    $Calendar->ProcessDue();
    is(scalar @Mail, 1, 'Repeated scheduler run does not notify again');

    my $Occurrence = $DB->SelectRow('SELECT * FROM appointment_occurrence WHERE event_id=? AND sequence_no=0', $First->{id});
    my $Duplicate = $TicketObject->TicketCreateFromAgent(
        User => $User, QueueID => 1, StateID => 2, PriorityID => 3,
        Title => 'Duplicate test', Body => 'Test', InternalOnly => 1,
        AppointmentOccurrenceID => $Occurrence->{id},
    );
    ok(!$Duplicate, 'Duplicate calendar ticket is rejected');
    is(scalar @Mail, 1, 'Rolled back duplicate does not send an agent notification');
    $DB->Do('UPDATE appointment_occurrence SET ticket_due_at=? WHERE event_id=? AND sequence_no=1',
        QisutuAppointmentTime::UTC(time - 60), $First->{id}) or die $DB->Error;
    $Calendar->ProcessDue();
    is(scalar @Mail, 2, 'Next recurring occurrence sends its own ticket notification');

    my $Assigned = due_event(ticket_owner_id => 2);
    $Calendar->ProcessDue();
    is(scalar @Mail, 3, 'Explicit owner gets exactly one notification');
    is(($Mail[-1] || {})->{ToEmail}, 'agent2@example.invalid', 'Selected ticket owner receives the message');
    is(($Mail[-1] || {})->{FromEmail}, 'support@example.invalid', 'Agent notification uses the configured SMTP sender');
    is_deeply([map { $_->{ToEmail} } @Mail], ['admin@example.invalid', 'admin@example.invalid', 'agent2@example.invalid'],
        'No notification goes to other queue agents or the customer');

    my $Manual = $TicketObject->TicketCreateFromAgent(
        User => $User, QueueID => 1, StateID => 2, PriorityID => 3,
        OwnerUserID => 2, RecipientEmail => 'customer@example.invalid',
        Title => 'Manual agent ticket', Body => 'Manual body', SendEmail => 0,
    );
    ok($Manual, 'Manual agent ticket still succeeds');
    is(scalar @Mail, 3, 'Manual agent creation still sends no agent notification');

    $DB->Do('INSERT INTO user_preference (user_account_id,preference_key,preference_value) VALUES (2,?,?)',
        'notification_assigned_ticket', '0') or die $DB->Error;
    my $Muted = due_event(ticket_owner_id => 2);
    $Calendar->ProcessDue();
    ok($DB->SelectRow('SELECT ticket_id FROM appointment_occurrence WHERE event_id=?', $Muted->{id})->{ticket_id},
        'Ticket is created when owner has disabled assignment notifications');
    is(scalar @Mail, 3, 'Personal assignment notification preference is respected');

    my $Cancelled = due_event();
    my $Data = $Calendar->EventGet($User, $Cancelled->{id});
    ok($Calendar->Cancel($User, { id => $Cancelled->{id}, version => $Data->{version}, scope => 'all' }), 'Cancel pending appointment');
    $Calendar->ProcessDue();
    is(scalar @Mail, 3, 'Cancelled appointment sends no ticket notification');

    $SMTPFailure = 1;
    my $Failed = due_event();
    ok(defined $Calendar->ProcessDue(), 'SMTP failure does not roll back the generated ticket');
    is(scalar @Mail, 4, 'Agent notification delivery was attempted');
    ok($DB->SelectRow('SELECT ticket_id FROM appointment_occurrence WHERE event_id=?', $Failed->{id})->{ticket_id},
        'Ticket remains linked after SMTP failure');
    my $Count = $DB->SelectRow('SELECT COUNT(*) AS n FROM ticket')->{n};
    $Calendar->ProcessDue();
    is($DB->SelectRow('SELECT COUNT(*) AS n FROM ticket')->{n}, $Count, 'SMTP failure does not cause duplicate ticket creation');
}
done_testing();

sub due_event {
    my (%Overrides) = @_;
    return $Calendar->Save($User, {
        calendar_id => $Cal->{id}, title => 'Kalender-Benachrichtigung',
        description => 'Terminbeschreibung für den Agenten', timezone => 'Europe/Berlin',
        start_local => QisutuAppointmentTime::Local(time + 3600, 'Europe/Berlin'),
        end_local => QisutuAppointmentTime::Local(time + 7200, 'Europe/Berlin'),
        type => 'maintenance', repeat => { frequency => 'none' }, auto_ticket => 1,
        ticket_lead => 120, queue_id => 1, priority_id => 3,
        recipient_email => 'customer@example.invalid',
        participants => [], reminders => [], %Overrides,
    }, []) || die $Calendar->Error;
}
