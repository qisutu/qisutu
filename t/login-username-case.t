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
use lib "$FindBin::Bin/../core/system";
use Test::More;
use QisutuAuth;

{
    package Local::CaseLoginDB;
    sub new { my ($Class, $User) = @_; return bless { User => $User, Writes => [], Lookups => 0 }, $Class; }
    sub SelectRow {
        my ($Self, $SQL, @Bind) = @_;
        $Self->{Lookups}++;
        return { is_locked => $Self->{User}->{locked_until} ? 1 : 0 } if $SQL =~ /AS is_locked/;
        # Reproduce the case-insensitive SQL lookup, even for the wrong spelling.
        return if lc($Bind[0]) ne lc($Self->{User}->{login}) || $Bind[1] ne $Self->{User}->{account_type};
        return { %{ $Self->{User} } };
    }
    sub Do { my ($Self, @Call) = @_; push @{ $Self->{Writes} }, \@Call; return 1; }
}
{
    package Local::CaseLoginLDAP;
    sub new { return bless { Result => $_[1] || { Handled => 0 } }, $_[0]; }
    sub AuthenticateAgent { return $_[0]->{Result}; }
    sub AuthenticateCustomer { return $_[0]->{Result}; }
    sub Error { return 'Directory authentication failed'; }
}
{
    package Local::CaseLoginAuth;
    our @ISA = ('QisutuAuth');
    sub _PasswordVerify {
        my ($Self, %Param) = @_;
        $Self->{PasswordChecks}++;
        return $Self->SUPER::_PasswordVerify(%Param);
    }
}

my $Password = 'Correct-Secret-2026';
my $Hash = crypt($Password, '$6$qisutuCaseTest$');
ok($Hash && substr($Hash, 0, 3) eq '$6$', 'platform can verify a real password hash');

sub Fixture {
    my (%Change) = @_;
    my $User = {
        id => 9, login => 'admin', account_type => 'agent', authentication_type => 'local',
        password_hash => $Hash, is_active => 1, failed_login_count => 2, locked_until => undef,
        %Change,
    };
    my $DB = Local::CaseLoginDB->new($User);
    my $Auth = Local::CaseLoginAuth->new(DB => $DB, LDAP => Local::CaseLoginLDAP->new());
    return ($Auth, $DB);
}

for my $Type (qw(agent customer)) {
    for my $Pair (['admin', 'Admin'], ['Admin', 'admin'], ['ADMIN', 'admin'], ['Änne', 'änne']) {
        my ($Stored, $Variant) = @{$Pair};
        my ($Auth, $DB) = Fixture(login => $Stored, account_type => $Type);
        ok(!$Auth->LoginCheck(Login => $Variant, Password => $Password, AccountType => $Type), "$Type: case variant is rejected despite correct password");
        is($DB->{Lookups}, 1, "$Type: the database candidate was actually looked up");
        is($Auth->Error(), 'Invalid login or password', "$Type: wrong spelling gets the normal credential error");
        is($Auth->{PasswordChecks} || 0, 0, "$Type: wrong spelling does not verify the candidate password");
        is(scalar @{ $DB->{Writes} }, 0, "$Type: wrong spelling cannot change lockouts or last login");
        my $User = $Auth->LoginCheck(Login => $Stored, Password => $Password, AccountType => $Type);
        ok($User, "$Type: the exact stored spelling succeeds");
        is($User->{login}, $Stored, "$Type: the stored login remains unchanged");
        ok(!exists $User->{password_hash}, "$Type: authentication never returns the password hash");
        is(scalar @{ $DB->{Writes} }, 1, "$Type: successful login updates the account once");
        like($DB->{Writes}->[0]->[0], qr/failed_login_count = 0/, "$Type: exact login keeps the failure reset");
    }
}

my ($Auth, $DB) = Fixture();
ok($Auth->LoginCheck(Login => "  admin\t", Password => $Password, AccountType => 'agent'), 'existing trimming around usernames remains supported');
($Auth, $DB) = Fixture();
ok(!$Auth->LoginCheck(Login => 'admin', Password => lc($Password), AccountType => 'agent'), 'passwords remain case-sensitive');
is($Auth->Error(), 'Invalid login or password', 'wrong password keeps the normal error');
like($DB->{Writes}->[0]->[0], qr/failed_login_count = failed_login_count \+ 1/, 'wrong password still counts toward the lockout');
($Auth, $DB) = Fixture(is_active => 0);
ok(!$Auth->LoginCheck(Login => 'admin', Password => $Password, AccountType => 'agent'), 'inactive exact account stays rejected');
is($Auth->{PasswordChecks} || 0, 0, 'inactive account does not reach password verification');
($Auth, $DB) = Fixture(locked_until => '2099-01-01 00:00:00');
ok(!$Auth->LoginCheck(Login => 'admin', Password => $Password, AccountType => 'agent'), 'locked exact account stays rejected');
is($Auth->Error(), 'User account is temporarily locked', 'lockout check is preserved');
($Auth, $DB) = Fixture(authentication_type => 'ldap');
ok(!$Auth->LoginCheck(Login => 'admin', Password => $Password, AccountType => 'agent'), 'directory account cannot use a local password fallback');
($Auth, $DB) = Fixture();
ok(!$Auth->LoginCheck(Login => 'admin', Password => $Password, AccountType => 'customer'), 'the selected account type remains enforced');
($Auth, $DB) = Fixture();
ok(!$Auth->LoginCheck(Login => 'unknown', Password => $Password, AccountType => 'agent'), 'unknown login remains rejected');

my $DirectoryUser = { id => 42, login => 'canonical@example.test', authentication_type => 'ldap' };
for my $Type (qw(agent customer)) {
    ($Auth, $DB) = Fixture(account_type => $Type);
    $Auth->{LDAP} = Local::CaseLoginLDAP->new({ Handled => 1, User => $DirectoryUser });
    is_deeply($Auth->LoginCheck(Login => 'DIRECTORY-ALIAS', Password => $Password, AccountType => $Type), $DirectoryUser, "$Type: directory identity mapping still uses its authoritative result");
    is($DB->{Lookups}, 0, "$Type: handled directory login does not enter the local path");
    $Auth->{LDAP} = Local::CaseLoginLDAP->new({ Handled => 1 });
    ok(!$Auth->LoginCheck(Login => 'admin', Password => $Password, AccountType => $Type), "$Type: failed directory authentication cannot fall back to local login");
    is($DB->{Lookups}, 0, "$Type: failed directory authentication also skips the local path");
}

done_testing();
