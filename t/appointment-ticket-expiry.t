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
use QisutuAppointment;

my @Cases = (
    ['Berlin before local midnight', '2026-10-17 12:05:00', 'Europe/Berlin', '2026-10-17 21:59:59', 0],
    ['Berlin local midnight before UTC midnight', '2026-10-17 12:05:00', 'Europe/Berlin', '2026-10-17 22:00:00', 1],
    ['Reported UTC midnight case', '2026-10-17 12:05:00', 'Europe/Berlin', '2026-10-18 00:00:29', 1],
    ['Seconds late on the same local day', '2026-10-17 12:05:00', 'Europe/Berlin', '2026-10-17 12:05:29', 0],
    ['Future deadline', '2026-10-18 12:05:00', 'Europe/Berlin', '2026-10-17 12:05:29', 0],
    ['UTC date differs but Los Angeles date is unchanged', '2026-10-17 22:05:00', 'America/Los_Angeles', '2026-10-18 01:00:00', 0],
    ['Los Angeles local midnight', '2026-10-17 22:05:00', 'America/Los_Angeles', '2026-10-18 07:00:00', 1],
    ['Tokyo local midnight', '2026-10-17 12:05:00', 'Asia/Tokyo', '2026-10-17 15:00:00', 1],
    ['Autumn DST repetition stays on one local day', '2026-10-25 00:30:00', 'Europe/Berlin', '2026-10-25 01:30:00', 0],
    ['Autumn DST local midnight', '2026-10-25 00:30:00', 'Europe/Berlin', '2026-10-25 23:00:00', 1],
    ['Spring DST local midnight', '2026-03-29 00:30:00', 'Europe/Berlin', '2026-03-29 22:00:00', 1],
    ['Year boundary', '2026-12-31 12:05:00', 'Europe/Berlin', '2026-12-31 23:00:00', 1],
);
for my $Case (@Cases) {
    my ($Name, $Due, $Zone, $Now, $Expected) = @$Case;
    is(QisutuAppointment::_TicketDueExpired($Due, $Zone, QisutuAppointmentTime::Epoch($Now)), $Expected, $Name);
}
for my $Bad (['invalid', 'Europe/Berlin'], ['2026-10-17 12:05:00', '../../etc/passwd']) {
    my $OK = eval { QisutuAppointment::_TicketDueExpired(@$Bad); 1 };
    ok(!$OK, 'Invalid deadline or timezone fails closed');
}

# Verify that optional deadlines retain an explicit NULL bind value.
my @Disabled = QisutuAppointment::_TicketDueAt({auto_ticket => 0}, '2026-10-17 12:05:00');
is_deeply(\@Disabled, [undef], 'Disabled ticket produces one undef value in SQL bind lists');
done_testing();
