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

use lib File::Spec->catdir( $FindBin::Bin, '..', 'core', 'system' );

use QisutuAuth;

{
    package Local::InstallerCredentialDB;

    sub new {
        my ( $Class, %Param ) = @_;
        return bless {
            user => {
                id                  => 1,
                login               => 'admin',
                account_type        => 'agent',
                authentication_type => 'local',
                email               => 'admin@example.invalid',
                password_hash       => $Param{PasswordHash},
                firstname           => 'Qisutu',
                lastname            => 'Administrator',
                is_active           => 1,
                failed_login_count  => 0,
                locked_until        => undef,
            },
            updates => 0,
        }, $Class;
    }

    sub SelectRow {
        my ( $Self, $SQL, @Bind ) = @_;
        return { %{ $Self->{user} } } if $SQL =~ m{FROM user_account};
        return;
    }

    sub Do {
        my ($Self) = @_;
        $Self->{updates}++;
        return 1;
    }
}

{
    package Local::InstallerCredentialLDAP;

    sub AuthenticateAgent {
        return { Handled => 0 };
    }

    sub AuthenticateCustomer {
        return { Handled => 0 };
    }
}

my $Root = File::Spec->rel2abs( File::Spec->catdir( $FindBin::Bin, '..' ) );
my $InstallerPath = File::Spec->catfile(
    $Root, 'bin', 'cgi-bin', 'install.pl',
);
open my $InstallerFH, '<:encoding(UTF-8)', $InstallerPath
    or die "Cannot open $InstallerPath: $!";
my $Installer = do { local $/; <$InstallerFH> };
close $InstallerFH;

my ($RandomIntSub) = $Installer =~ /(sub _RandomInt \{.*?^\})/ms;
my ($PasswordHashSub) = $Installer =~ /(sub _PasswordHash \{.*?^\})/ms;
my ($RandomPasswordSub) = $Installer =~ /(sub _RandomPassword \{.*?^\})/ms;
ok( $RandomIntSub, 'installer random-number helper can be isolated' );
ok( $PasswordHashSub, 'installer password-hash helper can be isolated' );
ok( $RandomPasswordSub, 'installer password generator can be isolated' );

my $Loaded = eval <<"PERL";
package Local::InstallerPassword;
$RandomIntSub
$PasswordHashSub
$RandomPasswordSub
1;
PERL
ok( $Loaded, 'installer password-hash implementation loads for an authentication test' )
    or diag $@;

my $Password = Local::InstallerPassword::_RandomPassword(24);
like(
    $Password,
    qr{\A[ABCDEFGHJKLMNPQRSTUVWXYZ23456789\@\#\%_\+]{24}\z},
    'generated administrator password uses only unambiguous characters',
);
unlike(
    $Password,
    qr{[01IOilo=\-]},
    'generated administrator password excludes visually confusable characters',
);
my $Hash = Local::InstallerPassword::_PasswordHash($Password);
like( $Hash, qr{\A\$6\$}, 'installer creates a SHA-512 crypt hash' );
is( length($Hash), 106, 'installer creates a complete SHA-512 crypt hash' );
is( crypt( $Password, $Hash ), $Hash, 'generated administrator password matches its installer hash' );

my $Database = Local::InstallerCredentialDB->new(
    PasswordHash => $Hash,
);
my $Authentication = QisutuAuth->new(
    DB   => $Database,
    LDAP => bless( {}, 'Local::InstallerCredentialLDAP' ),
);
my $User = $Authentication->LoginCheck(
    Login       => 'admin',
    Password    => $Password,
    AccountType => 'agent',
);
is( $User->{id}, 1, 'the real Qisutu authentication accepts the installer password and hash' );
is( $User->{login}, 'admin', 'the authenticated installer account is admin' );

my $WrongDatabase = Local::InstallerCredentialDB->new(
    PasswordHash => $Hash,
);
my $WrongAuthentication = QisutuAuth->new(
    DB   => $WrongDatabase,
    LDAP => bless( {}, 'Local::InstallerCredentialLDAP' ),
);
ok(
    !$WrongAuthentication->LoginCheck(
        Login       => 'admin',
        Password    => 'different-password',
        AccountType => 'agent',
    ),
    'the real Qisutu authentication rejects a mismatching password',
);

like(
    $Installer,
    qr{flock\(\s*\$LockHandle,\s*LOCK_EX\s*\)},
    'installer serializes database and finalization writes',
);
like(
    $Installer,
    qr{sub _AdminCredentialVerify \{.*?crypt\(\s*\$Password,\s*\$Account->\{password_hash\}\s*\).*?\$CheckHash ne \$Account->\{password_hash\}}s,
    'installer verifies the generated password against the stored database hash',
);
like(
    $Installer,
    qr{sub _AdminCredentialSynchronize \{.*?failed_login_count = 0,.*?locked_until = NULL,.*?_AdminCredentialVerify}s,
    'installer synchronizes and verifies the displayed password before completion',
);
like(
    $Installer,
    qr{data-copy-target="qisutu-install-admin-password"},
    'installer provides a copy button for the displayed administrator password',
);
like(
    $Installer,
    qr{qisutu-install[.]js},
    'installer loads the credential copy implementation',
);

my ($FinalizeSub) = $Installer =~ /(sub _InstallationFinalize \{.*?^\})/ms;
ok( $FinalizeSub, 'secure installation finalization can be isolated' );
cmp_ok(
    index( $FinalizeSub, '_AdminCredentialSynchronize' ),
    '<',
    index( $FinalizeSub, '$State->{show_final} = 1' ),
    'credential synchronization happens before the final page is enabled',
);
cmp_ok(
    index( $FinalizeSub, '_StateSave' ),
    '<',
    index( $FinalizeSub, '_InstallationLockCreate' ),
    'verified final state is saved before the installation is locked',
);

done_testing();
