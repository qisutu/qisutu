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
use File::Spec;
use File::Temp qw(tempdir);
use Test::More;

my $Root = File::Spec->catdir( $FindBin::Bin, '..' );
use lib
    File::Spec->catdir( $FindBin::Bin, '..', 'core', 'system' ),
    File::Spec->catdir( $FindBin::Bin, '..', 'core', 'output' );

use QisutuMailCrypto;
use QisutuOutput;

my $Crypto = QisutuMailCrypto->new( Config => {} );
if ( !$Crypto->OpenSSLAvailable() ) {
    plan skip_all => 'OpenSSL is required for S/MIME tests';
}

my $Temp = tempdir( 'qisutu-mail-crypto-test-XXXXXX', TMPDIR => 1, CLEANUP => 1 );
my $CertificateFile = File::Spec->catfile( $Temp, 'certificate.pem' );
my $PrivateKeyFile = File::Spec->catfile( $Temp, 'private-key.pem' );

my ( $Generated, undef, $GenerateError ) = $Crypto->_Run(
    Command => [
        'openssl', 'req', '-x509', '-newkey', 'rsa:2048', '-nodes',
        '-keyout', $PrivateKeyFile,
        '-out', $CertificateFile,
        '-days', '2',
        '-subj', '/CN=Qisutu Mail Crypto Test/emailAddress=support@example.test',
        '-addext', 'subjectAltName=email:support@example.test',
    ],
);
ok( $Generated, 'a temporary S/MIME identity can be generated' ) or diag $GenerateError;

my $Certificate = _Read($CertificateFile);
my $PrivateKey = _Read($PrivateKeyFile);
like( $Certificate, qr{BEGIN CERTIFICATE}, 'test certificate is PEM encoded' );
like( $PrivateKey, qr{BEGIN PRIVATE KEY}, 'test private key is PEM encoded' );

ok( $Crypto->OpenSSLAvailable(), 'mail crypto detects OpenSSL' );
my $Info = $Crypto->_CertificateInfo($Certificate);
is_deeply( $Info->{Emails}, ['support@example.test'], 'certificate email address is extracted' );
like( $Info->{Fingerprint}, qr{\A[0-9A-F]{64}\z}, 'certificate SHA-256 fingerprint is normalized' );
ok(
    $Crypto->_KeyMatchesCertificate( Certificate => $Certificate, PrivateKey => $PrivateKey ),
    'certificate and private key are matched before import',
);

my $Message = join "\r\n",
    'Date: Mon, 20 Jul 2026 12:00:00 +0000',
    'From: support@example.test',
    'To: customer@example.test',
    'Subject: S/MIME test',
    'MIME-Version: 1.0',
    'Content-Type: text/plain; charset=UTF-8',
    '',
    'Hello from Qisutu',
    '';

my $Signed = $Crypto->_CMSSign(
    Message  => $Message,
    Identity => { certificate_pem => $Certificate, private_key_pem => $PrivateKey },
);
ok( defined $Signed, 'message is S/MIME signed' ) or diag $Crypto->Error();
like( $Signed || '', qr{multipart/signed}i, 'signed message has the standard S/MIME content type' );

my $Verified = $Crypto->_CMSVerify( Message => $Signed );
ok( $Verified->{Success}, 'S/MIME signature is cryptographically verified' ) or diag $Verified->{Error};
like( $Verified->{Message} || '', qr{Hello from Qisutu}, 'signature verification restores the original MIME entity' );
is( $Verified->{SignerEmail}, 'support@example.test', 'signer email is read from the certificate' );

my $Encrypted = $Crypto->_CMSEncrypt( Message => $Signed, Certificates => [$Certificate] );
ok( defined $Encrypted, 'signed message is S/MIME encrypted' ) or diag $Crypto->Error();
like( $Encrypted || '', qr{enveloped-data}i, 'encrypted message declares enveloped-data' );

my $Decrypted = $Crypto->_CMSDecrypt(
    Message  => $Encrypted,
    Identity => { certificate_pem => $Certificate, private_key_pem => $PrivateKey },
);
ok( defined $Decrypted, 'S/MIME message is decrypted' ) or diag $Crypto->Error();
my $VerifiedAfterDecrypt = $Crypto->_CMSVerify( Message => $Decrypted );
ok( $VerifiedAfterDecrypt->{Success}, 'sign-then-encrypt round trip preserves the signature' );
like( $VerifiedAfterDecrypt->{Message} || '', qr{Hello from Qisutu}, 'round trip preserves the message body' );

my $PolicyDB = bless {}, 'Local::MailCryptoDB';
my $PolicyCrypto = QisutuMailCrypto->new( Config => {}, DB => $PolicyDB );
my $Required = $PolicyCrypto->OutgoingProcess(
    Message    => $Message,
    FromEmail  => 'support@example.test',
    Recipients => ['missing@example.test'],
);
ok( !$Required->{Success}, 'required encryption blocks recipients without a certificate' );
like( $Required->{Error} || '', qr{missing\@example[.]test}, 'the missing recipient is named in the error' );

for my $File (
    'install/sql/schema.sql',
    'core/system/QisutuMail.pm',
    'core/system/QisutuAdmin.pm',
) {
    my $Content = _Read( File::Spec->catfile( $Root, split m{/}, $File ) );
    like( $Content, qr{(?:mail_crypto|verify_certificate)}, "$File contains mail encryption integration" );
}

my $Output = QisutuOutput->new( Config => {
    Paths => { Output => "$Root/core/output", Language => "$Root/core/language" },
    Language => { Default => 'de' },
} );
my $Rendered = $Output->RenderSingle(
    Template => 'AdminMailEncryption.tt',
    Data => {
        Language => 'de', ProgramTitle => 'E-Mail-Verschlüsselung', ProgramDescription => '',
        ErrorClass => 'qisutu-hidden', NoticeClass => 'qisutu-hidden', ErrorMessage => '', NoticeMessage => '',
        HasPolicies => 1, HasKeys => 1, FormAction => 'index.pl',
        Policies => [{
            system_email_id => 1, name => 'Support', email => 'support@example.test',
            sign_checked => 'checked', decrypt_checked => 'checked', verify_checked => 'checked',
            active_checked => 'checked', encrypt_disabled_selected => '',
            encrypt_available_selected => '', encrypt_required_selected => 'selected',
        }],
        Keys => [{
            id => 1, role_label => 'Translate:AdminMailEncryptionIdentity',
            email_address => 'support@example.test', display_name => 'Support',
            fingerprint_sha256 => $Info->{Fingerprint}, valid_from => $Info->{ValidFrom}, valid_until => $Info->{ValidUntil},
            status_class => 'qisutu-status-badge-active', status_label => 'Translate:AdminActive',
            toggle_step => 'KeyDeactivate', toggle_label => 'Translate:AdminDeactivate',
        }],
        SystemEmailOptionsHTML => '<option value="1">Support</option>',
    },
);
ok( defined $Rendered && length $Rendered, 'S/MIME administration template renders' );
unlike( $Rendered || '', qr{\[\%}, 'S/MIME administration rendering leaves no template directives behind' );

done_testing();

sub _Read {
    my ($Path) = @_;
    open my $Handle, '<', $Path or die "Cannot read $Path: $!";
    binmode $Handle;
    local $/;
    my $Content = <$Handle>;
    close $Handle;
    return defined $Content ? $Content : '';
}

package Local::MailCryptoDB;

sub SelectRow {
    my ( $Self, $SQL ) = @_;
    return {
        active            => 1,
        sign_outgoing     => 0,
        encrypt_outgoing  => 'required',
        decrypt_incoming  => 1,
        verify_incoming   => 1,
    } if $SQL =~ m{mail_crypto_policy};
    return;
}

sub SelectAll { return [] }
sub Do { return 1 }
sub Error { return '' }

1;
