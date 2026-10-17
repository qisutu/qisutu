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
use FindBin;
use JSON::PP qw(decode_json);
use lib File::Spec->catdir($FindBin::Bin,'..','core','module');
use AgentCalendar;
{
    package AppointmentTestOutput;
    sub new {bless {},shift}
    sub Response {my ($S,%P)=@_;return \%P;}
}
my $M=AgentCalendar->new(Config=>{},Output=>AppointmentTestOutput->new);
my $U={account_type=>'agent',user_account_id=>1};
for my $Step(qw(Save Cancel CalendarSave Respond NotificationRead)) {
    my $R=$M->Run(User=>$U,Request=>{Step=>$Step,__RequestMethod=>'GET'})->{Response};
    is($R->{Status},'405 Method Not Allowed',"$Step cannot mutate with GET");
}
my $R=$M->Run(User=>{account_type=>'customer',user_account_id=>2},Request=>{Step=>'Bootstrap'})->{Response};
is($R->{Status},'403 Forbidden','Customer portal cannot access agent calendars');
$R=$M->Run(User=>{},Request=>{Step=>'Bootstrap'})->{Response};is($R->{Status},'403 Forbidden','Anonymous user rejected');
for my $JSON ('[]','{invalid','null','"text"') {
    $R=$M->Run(User=>$U,Request=>{Step=>'Save',__RequestMethod=>'POST',Data=>$JSON})->{Response};
    is($R->{Status},'400 Bad Request','Malformed JSON payload rejected');
}
$R=$M->Run(User=>$U,Request=>{Step=>'Unknown',__RequestMethod=>'POST'})->{Response};
is($R->{Status},'400 Bad Request','Unknown action rejected');
done_testing();
