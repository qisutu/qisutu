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
use Digest::SHA qw(sha256_hex);
use JSON::PP qw(decode_json);
use lib File::Spec->catdir($FindBin::Bin, '..', 'core', 'system');
use lib File::Spec->catdir($FindBin::Bin, '..', 'core', 'module');
use QisutuSession;
use AgentInternalChat;

{
    package Local::ActivityDB;
    sub new { return bless { Writes => [] }, shift; }
    sub Do {
        my ($Self, @Args) = @_;
        push @{$Self->{Writes}}, \@Args;
        return 1;
    }
    sub Error { return ''; }
}
{
    package Local::ActivityOutput;
    sub new { return bless {}, shift; }
    sub Response { my ($Self, %Param) = @_; return \%Param; }
    sub Translate { my ($Self, %Param) = @_; return $Param{Key}; }
}

my $DB = Local::ActivityDB->new();
my $Session = QisutuSession->new(DB => $DB, Config => { Session => { LifetimeSeconds => 28800 } });
my $Token = 'test-session';
for my $Step (qw(State Unread Messages TicketPresence TicketPresenceLeave)) {
    for my $Method (qw(GET POST)) {
        ok($Session->Touch(Token => $Token, Request => {
            Page => 'AgentInternalChat', Step => $Step, __RequestMethod => $Method,
        }), "$Step/$Method: polling is accepted without recording activity");
    }
}
$Session->Touch(Token => $Token, Request => {Page => 'Dashboard', Step => 'Data', __RequestMethod => 'GET'});
$Session->Touch(Token => $Token, Request => {Page => 'AgentInternalChat', Step => 'Activity', __RequestMethod => 'GET'});
is(scalar @{$DB->{Writes}}, 0, 'background requests and GET activity do not update sessions');

# Reproduce an unattended tab polling for three hours.
for (1 .. 360) {
    for my $Step (qw(State Unread Messages TicketPresence)) {
        $Session->Touch(Token => $Token, Request => {
            Page => 'AgentInternalChat', Step => $Step, __RequestMethod => 'POST',
        });
    }
}
is(scalar @{$DB->{Writes}}, 0, 'three hours of automatic chat traffic leave last_seen_at unchanged');

for my $Step (qw(Activity Send Delete Transfer)) {
    my $Before = scalar @{$DB->{Writes}};
    ok($Session->Touch(Token => $Token, Request => {
        Page => 'AgentInternalChat', Step => $Step, __RequestMethod => 'POST',
    }), "$Step: explicit user activity succeeds");
    is(scalar @{$DB->{Writes}}, $Before + 1, "$Step: explicit action refreshes its session");
}
for my $Page (qw(AgentTicketZoom AgentTicketList Dashboard)) {
    my $Before = scalar @{$DB->{Writes}};
    $Session->Touch(Token => $Token, Request => {Page => $Page, __RequestMethod => 'GET'});
    is(scalar @{$DB->{Writes}}, $Before + 1, "$Page: navigation still records activity");
}
my $Write = $DB->{Writes}[-1];
like($Write->[0], qr/last_seen_at = NOW\(\)/, 'activity updates the online timestamp');
like($Write->[0], qr/is_active = 1.*expires_at > NOW\(\)/s, 'expired and logged-out sessions cannot be revived');
is_deeply([@{$Write}[1,2]], [28800, sha256_hex($Token)], 'only the current session is refreshed');
my $Before = scalar @{$DB->{Writes}};
$Session->Touch(Token => $Token);
is(scalar @{$DB->{Writes}}, $Before + 1, 'existing callers without request context retain their behavior');
ok(!$Session->Touch(Request => {Page => 'AgentInternalChat', Step => 'Unread'}), 'missing token is still rejected');

my $Module = AgentInternalChat->new(Config => {}, DB => $DB, Output => Local::ActivityOutput->new());
my $Agent = {account_type => 'agent', user_account_id => 17};
my $Response = $Module->Run(User => $Agent, Request => {Step => 'Activity', __RequestMethod => 'POST'})->{Response};
is($Response->{Status}, '200 OK', 'agent can report activity');
is(decode_json($Response->{Body})->{success}, 1, 'activity endpoint acknowledges success');
$Response = $Module->Run(User => $Agent, Request => {Step => 'Activity', __RequestMethod => 'GET'})->{Response};
is($Response->{Status}, '405 Method Not Allowed', 'activity requires POST');
$Response = $Module->Run(User => {account_type => 'customer', user_account_id => 18}, Request => {Step => 'Activity', __RequestMethod => 'POST'})->{Response};
is($Response->{Status}, '403 Forbidden', 'customer cannot report agent activity');

done_testing();
