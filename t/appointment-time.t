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
use QisutuAppointmentTime;
my $D={start_local=>'2026-10-20 09:00:00',end_local=>'2026-10-20 10:00:00',timezone=>'Europe/Berlin',repeat=>{frequency=>'weekly',interval=>2,weekdays=>[2],count=>4}};
my $O=QisutuAppointmentTime::Occurrences($D,'2027-01-31');
is_deeply([map {substr($_->{start_local},0,10)} @$O],[qw(2026-10-20 2026-11-03 2026-11-17 2026-12-01)],'Every second Tuesday and count limit');
is($O->[0]->{start_utc},'2026-10-20 07:00:00','Summer offset');
is($O->[1]->{start_utc},'2026-11-03 08:00:00','Same wall time after daylight saving ends');
$D->{start_local}='2026-01-31 09:00:00';$D->{end_local}='2026-01-31 10:00:00';$D->{repeat}={frequency=>'monthly',interval=>1,count=>3};
$O=QisutuAppointmentTime::Occurrences($D,'2026-08-01');
is_deeply([map {substr($_->{start_local},0,10)} @$O],[qw(2026-01-31 2026-03-31 2026-05-31)],'Missing month days are skipped');
$D->{start_local}='2026-10-13 09:00:00';$D->{end_local}='2026-10-13 10:00:00';$D->{repeat}={frequency=>'monthly',monthly_mode=>'weekday',interval=>1,count=>3};
$O=QisutuAppointmentTime::Occurrences($D,'2027-01-01');
is_deeply([map {substr($_->{start_local},0,10)} @$O],[qw(2026-10-13 2026-11-10 2026-12-08)],'Second Tuesday of each month');
$D->{start_local}='2026-10-27 09:00:00';$D->{end_local}='2026-10-27 10:00:00';$D->{repeat}->{monthly_mode}='last';
$O=QisutuAppointmentTime::Occurrences($D,'2027-01-01');
is_deeply([map {substr($_->{start_local},0,10)} @$O],[qw(2026-10-27 2026-11-24 2026-12-29)],'Last Tuesday of each month');
$D->{start_local}='2028-02-29 09:00:00';$D->{end_local}='2028-02-29 10:00:00';$D->{repeat}={frequency=>'yearly',count=>3};
$O=QisutuAppointmentTime::Occurrences($D,'2037-01-01');
is_deeply([map {substr($_->{start_local},0,10)} @$O],[qw(2028-02-29 2032-02-29 2036-02-29)],'Leap-day yearly recurrence');
$D->{start_local}='2026-10-24 00:00:00';$D->{end_local}='2026-10-26 00:00:00';$D->{repeat}={frequency=>'none'};
$O=QisutuAppointmentTime::Occurrences($D,'2027-01-01');
is(QisutuAppointmentTime::Epoch($O->[0]->{end_utc})-QisutuAppointmentTime::Epoch($O->[0]->{start_utc}),49*3600,'Multi-day all-day appointment spans autumn DST correctly');
ok(!defined QisutuAppointmentTime::LocalEpoch('2026-03-29 02:30:00','Europe/Berlin'),'Reject non-existing spring DST wall time');
ok(!defined QisutuAppointmentTime::Epoch('2026-02-30 09:00:00'),'Reject invalid calendar date');
ok(!QisutuAppointmentTime::ZoneValid('../../etc/passwd'),'Reject time-zone traversal');
$D->{start_local}='2026-10-20 09:00:00';$D->{end_local}='2026-10-20 10:00:00';$D->{repeat}={frequency=>'daily',until=>'2026-10-22'};
$O=QisutuAppointmentTime::Occurrences($D,'2027-01-01');is(scalar @$O,3,'Inclusive until date');
my $Before=$ENV{TZ};QisutuAppointmentTime::Local(time,'Europe/Paris');is($ENV{TZ},$Before,'Process timezone restored after conversion');
done_testing();
