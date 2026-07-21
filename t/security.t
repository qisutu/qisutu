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

use File::Path qw(make_path);
use File::Spec;
use File::Temp qw(tempdir);
use FindBin;
use Test::More;

use lib "$FindBin::Bin/../core/system", "$FindBin::Bin/../core/output", "$FindBin::Bin/../core/config";

use QisutuOutput;
use QisutuAdmin;
use QisutuMail;
use QisutuSecurity;

my $Root = tempdir( CLEANUP => 1 );
make_path( File::Spec->catdir( $Root, 'var', 'secure' ) );
my $KeyFile = File::Spec->catfile( $Root, 'var', 'secure', 'security.key' );
open my $KeyFH, '>', $KeyFile or die "Cannot create test key: $!";
print {$KeyFH} ( 'ab' x 32 ) . "\n";
close $KeyFH;

my $Config = {
    RootPath => $Root,
    Paths    => { SecurityKey => $KeyFile },
};
my $Security = QisutuSecurity->new( Config => $Config );

my $Encrypted = $Security->Encrypt( Value => 'mail-password-ÄÖÜ' );
like( $Encrypted, qr{\Aqse1:}, 'stored secrets use the authenticated encrypted envelope' );
unlike( $Encrypted, qr{mail-password}, 'encrypted envelope does not contain the clear text' );
is( $Security->Decrypt( Value => $Encrypted ), 'mail-password-ÄÖÜ', 'encrypted secrets can be decrypted with the installation key' );

for my $ShortSecret ( 'x', 'smtp-secret', '123456789012345' ) {
    my $ShortEncrypted = $Security->Encrypt( Value => $ShortSecret );
    like( $ShortEncrypted, qr{\Aqse1:}, 'a short mail password is encrypted' );
    is( $Security->Decrypt( Value => $ShortEncrypted ), $ShortSecret, 'a short mail password can be decrypted again' );
}

my $Damaged = $Encrypted;
substr( $Damaged, -2, 1, substr( $Damaged, -2, 1 ) eq 'A' ? 'B' : 'A' );
ok( !defined $Security->Decrypt( Value => $Damaged ), 'tampered encrypted secrets are rejected' );

my $Mail = QisutuMail->new( Config => $Config, DB => undef );
ok(
    !defined $Mail->_AccountValue(
        Account => { imap_password => $Damaged },
        Prefix  => 'imap',
        Key     => 'password',
    ),
    'mail integration rejects a damaged encrypted password',
);
like( $Mail->Error(), qr{Encrypted secret}, 'mail integration retains the concrete decryption error' );

my $Admin = QisutuAdmin->new( Config => $Config, DB => undef );
my $PreparedRows = $Admin->_RowsPrepare( Rows => [ { imap_password => $Damaged } ] );
is( $PreparedRows->[0]->{imap_password}, $Damaged, 'administration does not replace an unreadable encrypted password with an empty value' );
like( $PreparedRows->[0]->{_secret_error}, qr{Encrypted secret}, 'the account row carries the concrete secret error to the mail subsystem' );

my $CSRF = $Security->CSRFToken( SessionToken => 'session-token-for-test' );
like( $CSRF, qr{\A[0-9a-f]{64}\z}, 'session CSRF token is cryptographically signed' );
ok( $Security->CSRFTokenVerify( SessionToken => 'session-token-for-test', Token => $CSRF ), 'valid session CSRF token is accepted' );
ok( !$Security->CSRFTokenVerify( SessionToken => 'another-session', Token => $CSRF ), 'CSRF token cannot be reused for another session' );
ok( !$Security->CSRFTokenVerify( SessionToken => '', Token => '' ), 'missing CSRF material is always rejected' );

my $PublicCSRF = $Security->PublicCSRFTokenCreate( Purpose => 'public-ticket-form:test' );
ok( $Security->PublicCSRFTokenVerify( Token => $PublicCSRF, Purpose => 'public-ticket-form:test' ), 'signed public form token is accepted for its purpose' );
ok( !$Security->PublicCSRFTokenVerify( Token => $PublicCSRF, Purpose => 'public-ticket-form:other' ), 'public form token cannot be reused for another form' );

ok(
    $Security->TOTPVerify(
        Secret => 'GEZDGNBVGY3TQOJQGEZDGNBVGY3TQOJQ',
        Code   => '287082',
        Time   => 59,
    ),
    'TOTP implementation matches the RFC test secret'
);
my $RecoveryCodes = $Security->RecoveryCodesCreate();
is( scalar @{$RecoveryCodes}, 10, 'ten one-time recovery codes are generated' );
my %Unique = map { $_ => 1 } @{$RecoveryCodes};
is( scalar keys %Unique, 10, 'recovery codes are unique' );

my $Output = QisutuOutput->new( Config => $Config );
my $Rendered = $Output->_CSRFFieldsInject(
    Content => '<form method="post" action="index.pl"><button>Save</button></form><form method="get"></form>',
    Token   => $CSRF,
);
like( $Rendered, qr{name="CSRFToken" value="\Q$CSRF\E"}, 'CSRF token is injected into POST forms' );
is( () = $Rendered =~ m{name="CSRFToken"}g, 1, 'GET forms do not receive a CSRF field' );

local $ENV{HTTPS} = 'on';
my $Response = $Output->Response( Body => 'ok' );
like( $Response, qr{^X-Content-Type-Options: nosniff\r?$}m, 'nosniff header is sent' );
like( $Response, qr{^X-Frame-Options: DENY\r?$}m, 'internal pages reject framing' );
like( $Response, qr{^Strict-Transport-Security: max-age=31536000\r?$}m, 'HSTS is sent for HTTPS requests' );
my $Cookie = $Output->CookieCreate( Name => 'session', Value => 'token', Secure => 1 );
like( $Cookie, qr{\bHttpOnly\b}, 'session cookie is HttpOnly' );
like( $Cookie, qr{\bSecure\b}, 'HTTPS session cookie is Secure' );
like( $Cookie, qr{\bSameSite=Lax\b}, 'session cookie has SameSite protection' );

done_testing();
