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
use lib "$FindBin::Bin/../core/system", "$FindBin::Bin/../core/config", "$FindBin::Bin/../core/cpan-lib";
use Test::More;

use QisutuAPIAuth;
use QisutuRESTAPI;

{
    package Local::RESTDB;
    sub new { bless { Do => [], Error => '' }, shift }
    sub SelectRow {
        my ( $Self, $SQL, @Bind ) = @_;
        return { id=>5, account_type=>'agent', is_active=>1, is_system_user=>0 } if $SQL =~ m{FROM user_account\s+WHERE id}s;
        return $Self->{Token} && $Bind[0] == $Self->{Token}->{id} ? { %{$Self->{Token}} } : undef
            if $SQL =~ m{FROM api_token at.*WHERE at[.]id = \?}s;
        return { request_count=>0 } if $SQL =~ m{FROM api_request_log};
        return;
    }
    sub SelectAll { return [] }
    sub Do { my($Self,$SQL,@Bind)=@_;push @{$Self->{Do}},[$SQL,@Bind];return 1 }
    sub LastInsertID { return 42 }
    sub Error { return $_[0]->{Error} }
}

my $DB = Local::RESTDB->new();
my $Config = { System=>{Version=>'0.0.51',WebPath=>'/qisutu',BaseURL=>''},Language=>{Default=>'de'} };
my $Auth = QisutuAPIAuth->new( Config=>$Config, DB=>$DB );

my $Definitions = $Auth->ScopeDefinitions();
ok( scalar @{$Definitions} >= 10, 'documented API scopes are available' );
ok( grep( { $_->{Key} eq 'tickets.status' } @{$Definitions} ), 'ticket status has its own admin-controlled scope' );

my $Created = $Auth->TokenCreate(
    UserAccountID=>5,ChangedByUserID=>5,Label=>'Monitoring',Lifetime=>'90d',
    Scopes=>['tickets.read','tickets.status','does.not.exist'],RateLimitPerMinute=>120,
);
ok( $Created, 'API token can be created' );
like( $Created->{PlainToken}, qr{\Aqst_[0-9a-f]{96}\z}, 'plain token uses a strong random format' );
is_deeply( $Created->{Scopes}, ['tickets.read','tickets.status'], 'unknown scopes are discarded' );
unlike( join(' ',map { join(' ',@{$_}) } @{$DB->{Do}}), qr{\Q$Created->{PlainToken}\E}, 'plain token is never stored in the database call' );

my $Invalid = $Auth->TokenCreate(
    UserAccountID=>5,ChangedByUserID=>5,Label=>'Invalid IP',Scopes=>['tickets.read'],AllowedIPs=>'192.0.2.1;DROP TABLE',
);
ok( !$Invalid, 'invalid allowed IP input is rejected' );

my $API = QisutuRESTAPI->new( Config=>$Config, DB=>$DB );
my $Ping = $API->Handle(Method=>'GET',Path=>'/v1/ping',Query=>{},Body=>{},Headers=>{},RemoteIP=>'127.0.0.1',RequestID=>'test-request');
is( $Ping->{Status}, 200, 'public health endpoint works' );
is( $Ping->{Body}->{data}->{version}, '0.0.51', 'health endpoint reports program version' );

my $OpenAPI = $API->OpenAPIDocument();
is( $OpenAPI->{openapi}, '3.0.3', 'local OpenAPI document is available' );
ok( $OpenAPI->{paths}->{'/tickets/{ticket_id}'}->{patch}, 'ticket changes are documented' );

my $Denied = $API->Handle(Method=>'GET',Path=>'/v1/tickets',Query=>{},Body=>{},Headers=>{},RemoteIP=>'127.0.0.1',RequestID=>'unauthorized');
is( $Denied->{Status}, 401, 'missing API token is rejected' );
is( $Denied->{Body}->{error}->{code}, 'invalid_token', 'authentication error is machine readable' );

$DB->{Token} = {
    id=>42, user_account_id=>5, label=>'Existing API access', token_prefix=>'qst_existing',
    scopes_json=>'["tickets.read","example.retained"]', allowed_ips=>'192.0.2.10',
    rate_limit_per_minute=>275, active=>0, expires_at=>'2099-01-01 00:00:00',
    login=>'test', firstname=>'Test', lastname=>'User', account_type=>'agent', is_active=>1, is_system_user=>0,
};
my %Update = (
    TokenID=>42, UserAccountID=>5, ChangedByUserID=>5, Label=>'Renamed access',
    Scopes=>['tickets.status','example.retained','unknown.permission'],
    AllowedIPs=>"192.0.2.10\n2001:db8::10", RateLimitPerMinute=>275,
);
ok( $Auth->TokenUpdate(%Update), 'existing access can be edited' );
my ($UpdateSQL, @UpdateBind) = @{$DB->{Do}->[-1]};
unlike( $UpdateSQL, qr{token_hash\s*=|token_prefix\s*=|active\s*=}, 'editing preserves the secret and activation state' );
like( $UpdateSQL, qr{expires_at = expires_at}, 'editing preserves the expiry by default' );
is_deeply( JSON::PP->new->decode($UpdateBind[2]), ['tickets.status','example.retained'], 'editing retains existing add-on scopes and rejects new unknown permissions' );
is( $UpdateBind[3], '192.0.2.10,2001:db8::10', 'editing normalizes IP restrictions' );
is( $UpdateBind[4], 275, 'editing preserves a custom request limit' );

my $Writes = scalar @{$DB->{Do}};
ok( !$Auth->TokenUpdate(%Update,Scopes=>[]), 'editing rejects an empty permission selection' );
ok( !$Auth->TokenUpdate(%Update,TokenID=>999), 'editing rejects a missing token' );
ok( !$Auth->TokenUpdate(%Update,Lifetime=>'invalid'), 'editing rejects an invalid lifetime' );
is( scalar @{$DB->{Do}}, $Writes, 'invalid updates perform no database writes' );

ok( $Auth->TokenUpdate(%Update,Lifetime=>'30d'), 'editing can extend validity' );
like( $DB->{Do}->[-1]->[0], qr{DATE_ADD\(NOW\(\), INTERVAL 30 DAY\)}, 'new lifetime starts at save time' );
ok( $Auth->TokenUpdate(%Update,Lifetime=>'never'), 'editing can remove the expiry date' );
like( $DB->{Do}->[-1]->[0], qr{expires_at = NULL}, 'unlimited validity is stored without an expiry' );

ok( $Auth->TokenActivate(TokenID=>42,ChangedByUserID=>5), 'an inactive access can be activated again' );
unlike( $DB->{Do}->[-1]->[0], qr{token_hash\s*=|token_prefix\s*=|expires_at\s*=}, 'activation preserves the existing key and expiry' );
$Writes = scalar @{$DB->{Do}};
$DB->{Token}->{expires_at} = '2000-01-01 00:00:00';
ok( !$Auth->TokenActivate(TokenID=>42,ChangedByUserID=>5), 'an expired token must be extended before activation' );
$DB->{Token}->{expires_at} = undef;
$DB->{Token}->{is_active} = 0;
ok( !$Auth->TokenActivate(TokenID=>42,ChangedByUserID=>5), 'activation rejects an inactive user' );
$DB->{Token}->{is_active} = 1;
$DB->{Token}->{is_system_user} = 1;
ok( !$Auth->TokenActivate(TokenID=>42,ChangedByUserID=>5), 'activation rejects a system account' );
is( scalar @{$DB->{Do}}, $Writes, 'invalid activations perform no database writes' );

done_testing();
