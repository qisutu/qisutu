#!/usr/bin/env perl
# Qisutu - Open Source Ticket System
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
        return { request_count=>0 } if $SQL =~ m{FROM api_request_log};
        return;
    }
    sub SelectAll { return [] }
    sub Do { my($Self,$SQL,@Bind)=@_;push @{$Self->{Do}},[$SQL,@Bind];return 1 }
    sub LastInsertID { return 42 }
    sub Error { return $_[0]->{Error} }
}

my $DB = Local::RESTDB->new();
my $Config = { System=>{Version=>'0.0.46',WebPath=>'/qisutu',BaseURL=>''},Language=>{Default=>'de'} };
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
is( $Ping->{Body}->{data}->{version}, '0.0.46', 'health endpoint reports program version' );

my $OpenAPI = $API->OpenAPIDocument();
is( $OpenAPI->{openapi}, '3.0.3', 'local OpenAPI document is available' );
ok( $OpenAPI->{paths}->{'/tickets/{ticket_id}'}->{patch}, 'ticket changes are documented' );

my $Denied = $API->Handle(Method=>'GET',Path=>'/v1/tickets',Query=>{},Body=>{},Headers=>{},RemoteIP=>'127.0.0.1',RequestID=>'unauthorized');
is( $Denied->{Status}, 401, 'missing API token is rejected' );
is( $Denied->{Body}->{error}->{code}, 'invalid_token', 'authentication error is machine readable' );

done_testing();
