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

package QisutuMailCrypto;

use strict;
use warnings;
use utf8;

use File::Temp qw(tempdir tempfile);
use IPC::Open3;
use Symbol qw(gensym);
use Time::Piece;
use QisutuSecurity;

sub new {
    my ( $Class, %Param ) = @_;

    my $Self = {
        Config    => $Param{Config} || {},
        DB        => $Param{DB},
        LastError => '',
        TempDir   => tempdir( 'qisutu-smime-XXXXXX', TMPDIR => 1, CLEANUP => 1 ),
        Security  => QisutuSecurity->new( Config => $Param{Config} || {} ),
    };

    bless $Self, $Class;
    return $Self;
}

sub Error {
    my ($Self) = @_;
    return $Self->{LastError} || '';
}

sub OpenSSLAvailable {
    my ($Self) = @_;
    my ( $Success ) = $Self->_Run( Command => [ 'openssl', 'version' ] );
    return $Success ? 1 : 0;
}

sub SystemEmailList {
    my ($Self) = @_;
    return $Self->{DB}->SelectAll(
        'SELECT id, name, email, active FROM system_email ORDER BY sort_order, name, id'
    ) || [];
}

sub KeyList {
    my ($Self) = @_;
    return $Self->{DB}->SelectAll(
        'SELECT k.*, se.name AS system_email_name, se.email AS system_email
         FROM mail_crypto_key k
         LEFT JOIN system_email se ON se.id = k.system_email_id
         ORDER BY k.key_role, k.email_address, k.id DESC'
    ) || [];
}

sub KeyGet {
    my ( $Self, %Param ) = @_;
    my $KeyID = $Param{KeyID} || 0;
    return if $KeyID !~ m{\A\d+\z} || !$KeyID;
    return $Self->{DB}->SelectRow(
        'SELECT * FROM mail_crypto_key WHERE id = ? LIMIT 1',
        $KeyID,
    );
}

sub PolicyList {
    my ($Self) = @_;
    return $Self->{DB}->SelectAll(
        'SELECT se.id AS system_email_id, se.name, se.email, se.active AS system_email_active,
                COALESCE(p.sign_outgoing, 0) AS sign_outgoing,
                COALESCE(p.encrypt_outgoing, \'disabled\') AS encrypt_outgoing,
                COALESCE(p.decrypt_incoming, 1) AS decrypt_incoming,
                COALESCE(p.verify_incoming, 1) AS verify_incoming,
                COALESCE(p.active, 1) AS active
         FROM system_email se
         LEFT JOIN mail_crypto_policy p ON p.system_email_id = se.id
         ORDER BY se.sort_order, se.name, se.id'
    ) || [];
}

sub PolicySave {
    my ( $Self, %Param ) = @_;
    $Self->{LastError} = '';

    my $SystemEmailID = $Param{SystemEmailID} || 0;
    my $Encrypt = $Param{EncryptOutgoing} || 'disabled';
    my $UserID = $Param{ChangedByUserID} || 1;

    if ( $SystemEmailID !~ m{\A\d+\z} || !$SystemEmailID ) {
        $Self->{LastError} = 'A valid system email is required';
        return;
    }
    if ( $Encrypt !~ m{\A(?:disabled|available|required)\z} ) {
        $Self->{LastError} = 'Invalid outgoing encryption policy';
        return;
    }

    my $Existing = $Self->{DB}->SelectRow(
        'SELECT id FROM mail_crypto_policy WHERE system_email_id = ? LIMIT 1',
        $SystemEmailID,
    );

    if ($Existing) {
        return $Self->{DB}->Do(
            'UPDATE mail_crypto_policy
             SET sign_outgoing = ?, encrypt_outgoing = ?, decrypt_incoming = ?,
                 verify_incoming = ?, active = ?, changed_at = NOW(), changed_by_user_id = ?
             WHERE system_email_id = ?',
            $Param{SignOutgoing} ? 1 : 0,
            $Encrypt,
            $Param{DecryptIncoming} ? 1 : 0,
            $Param{VerifyIncoming} ? 1 : 0,
            $Param{Active} ? 1 : 0,
            $UserID,
            $SystemEmailID,
        );
    }

    return $Self->{DB}->Do(
        'INSERT INTO mail_crypto_policy
         (system_email_id, sign_outgoing, encrypt_outgoing, decrypt_incoming,
          verify_incoming, active, created_at, created_by_user_id, changed_at, changed_by_user_id)
         VALUES (?, ?, ?, ?, ?, ?, NOW(), ?, NOW(), ?)',
        $SystemEmailID,
        $Param{SignOutgoing} ? 1 : 0,
        $Encrypt,
        $Param{DecryptIncoming} ? 1 : 0,
        $Param{VerifyIncoming} ? 1 : 0,
        $Param{Active} ? 1 : 0,
        $UserID,
        $UserID,
    );
}

sub IdentityImportPKCS12 {
    my ( $Self, %Param ) = @_;
    $Self->{LastError} = '';

    my $Bundle = $Param{Content} || '';
    if ( !$Bundle ) {
        $Self->{LastError} = 'PKCS#12 file is empty';
        return;
    }

    my $BundleFile = $Self->_TempFile( Suffix => '.p12', Content => $Bundle );
    my $PassFile = $Self->_TempFile( Suffix => '.pass', Content => $Param{Passphrase} || '' );
    my ( $CertificateOK, $Certificate, $CertificateError ) = $Self->_Run(
        Command => [
            'openssl', 'pkcs12', '-in', $BundleFile, '-clcerts', '-nokeys',
            '-passin', 'file:' . $PassFile,
        ],
    );
    if ( !$CertificateOK ) {
        $Self->{LastError} = 'PKCS#12 certificate could not be read: ' . $CertificateError;
        return;
    }

    my ( $KeyOK, $PrivateKey, $KeyError ) = $Self->_Run(
        Command => [
            'openssl', 'pkcs12', '-in', $BundleFile, '-nocerts', '-nodes',
            '-passin', 'file:' . $PassFile,
        ],
    );
    if ( !$KeyOK ) {
        $Self->{LastError} = 'PKCS#12 private key could not be read: ' . $KeyError;
        return;
    }

    my ( $ChainOK, $CertificateChain ) = $Self->_Run(
        Command => [
            'openssl', 'pkcs12', '-in', $BundleFile, '-cacerts', '-nokeys',
            '-passin', 'file:' . $PassFile,
        ],
    );
    $CertificateChain = '' if !$ChainOK;

    return $Self->IdentityImportPEM(
        %Param,
        Certificate      => $Certificate,
        CertificateChain => $CertificateChain,
        PrivateKey       => $PrivateKey,
    );
}

sub IdentityImportPEM {
    my ( $Self, %Param ) = @_;
    $Self->{LastError} = '';

    my $SystemEmailID = $Param{SystemEmailID} || 0;
    my $SystemEmail = $Self->{DB}->SelectRow(
        'SELECT id, name, email FROM system_email WHERE id = ? LIMIT 1',
        $SystemEmailID,
    );
    if ( !$SystemEmail ) {
        $Self->{LastError} = 'The selected system email was not found';
        return;
    }

    my $Certificate = $Self->_CertificateNormalize( $Param{Certificate} || '' );
    return if !$Certificate;
    my $CertificateChain = $Self->_CertificateChainNormalize(
        $Param{CertificateChain} || $Param{Certificate} || '',
        $Certificate,
    );
    my $PrivateKey = $Self->_PrivateKeyNormalize( $Param{PrivateKey} || '', $Param{Passphrase} || '' );
    return if !$PrivateKey;
    return if !$Self->_KeyMatchesCertificate( Certificate => $Certificate, PrivateKey => $PrivateKey );

    my $Info = $Self->_CertificateInfo($Certificate) || return;
    if ( !$Self->_CertificateEmailMatches( Info => $Info, Email => $SystemEmail->{email} ) ) {
        $Self->{LastError} = 'The certificate email address does not match the selected system email';
        return;
    }

    my $EncryptedKey = $Self->{Security}->Encrypt( Value => $PrivateKey );
    if ( !$EncryptedKey ) {
        $Self->{LastError} = $Self->{Security}->Error() || 'Private key encryption failed';
        return;
    }

    return $Self->_KeyStore(
        KeyRole         => 'identity',
        SystemEmailID   => $SystemEmailID,
        Email           => lc $SystemEmail->{email},
        DisplayName     => $Param{DisplayName} || $SystemEmail->{name},
        Certificate     => $Certificate,
        CertificateChain => $CertificateChain,
        EncryptedKey    => $EncryptedKey,
        Info            => $Info,
        ChangedByUserID => $Param{ChangedByUserID},
    );
}

sub RecipientImport {
    my ( $Self, %Param ) = @_;
    $Self->{LastError} = '';

    my $Email = lc( $Param{Email} || '' );
    $Email =~ s{\A\s+|\s+\z}{}g;
    if ( $Email !~ m{\A[^\s\@]+\@[^\s\@]+\.[^\s\@]+\z} ) {
        $Self->{LastError} = 'A valid recipient email address is required';
        return;
    }

    my $Certificate = $Self->_CertificateNormalize( $Param{Certificate} || '' );
    return if !$Certificate;
    my $Info = $Self->_CertificateInfo($Certificate) || return;
    if ( !$Self->_CertificateEmailMatches( Info => $Info, Email => $Email ) ) {
        $Self->{LastError} = 'The certificate email address does not match the recipient';
        return;
    }

    return $Self->_KeyStore(
        KeyRole         => 'recipient',
        Email           => $Email,
        DisplayName     => $Param{DisplayName} || '',
        Certificate     => $Certificate,
        Info            => $Info,
        ChangedByUserID => $Param{ChangedByUserID},
    );
}

sub KeyActiveSet {
    my ( $Self, %Param ) = @_;
    my $KeyID = $Param{KeyID} || 0;
    return if $KeyID !~ m{\A\d+\z} || !$KeyID;
    return $Self->{DB}->Do(
        'UPDATE mail_crypto_key SET active = ?, changed_at = NOW(), changed_by_user_id = ? WHERE id = ?',
        $Param{Active} ? 1 : 0,
        $Param{ChangedByUserID} || 1,
        $KeyID,
    );
}

sub KeyDelete {
    my ( $Self, %Param ) = @_;
    my $KeyID = $Param{KeyID} || 0;
    return if $KeyID !~ m{\A\d+\z} || !$KeyID;
    return $Self->{DB}->Do( 'DELETE FROM mail_crypto_key WHERE id = ?', $KeyID );
}

sub OutgoingProcess {
    my ( $Self, %Param ) = @_;
    $Self->{LastError} = '';

    my $Message = $Param{Message} || '';
    my $From = lc( $Param{FromEmail} || '' );
    my @Recipients = map { lc $_ } @{ $Param{Recipients} || [] };
    my %RecipientSeen;
    @Recipients = grep { $_ && !$RecipientSeen{$_}++ } @Recipients;
    my $Policy = $Self->_PolicyForEmail($From);
    my $Crypto = {
        direction        => 'outgoing',
        crypto_type      => 'smime',
        was_encrypted    => 0,
        was_decrypted    => 0,
        was_signed       => 0,
        signature_status => 'none',
        signer_email     => $From,
    };

    return { Success => 1, Message => $Message, Crypto => $Crypto } if !$Policy || !$Policy->{active};

    my $Identity;
    if ( $Policy->{sign_outgoing} ) {
        $Identity = $Self->_IdentityForEmail($From);
        if ( !$Identity ) {
            $Self->{LastError} = 'Outgoing signing is enabled, but no active S/MIME identity exists for ' . $From;
            return { Success => 0, Error => $Self->{LastError}, Crypto => $Crypto };
        }
        my $Signed = $Self->_CMSSign( Message => $Message, Identity => $Identity );
        return { Success => 0, Error => $Self->{LastError}, Crypto => $Crypto } if !defined $Signed;
        $Message = $Signed;
        $Crypto->{was_signed} = 1;
        $Crypto->{signature_status} = 'created';
        $Crypto->{signer_fingerprint} = $Identity->{fingerprint_sha256} || '';
    }

    my $EncryptionPolicy = $Policy->{encrypt_outgoing} || 'disabled';
    if ( $EncryptionPolicy ne 'disabled' ) {
        my @Certificates;
        my @Missing;
        my @Fingerprints;
        for my $Email (@Recipients) {
            my $Recipient = $Self->_RecipientForEmail($Email);
            if ($Recipient) {
                push @Certificates, $Recipient->{certificate_pem};
                push @Fingerprints, $Recipient->{fingerprint_sha256} || '';
            }
            else {
                push @Missing, $Email;
            }
        }

        if ( @Missing && $EncryptionPolicy eq 'required' ) {
            $Self->{LastError} = 'S/MIME encryption is required, but certificates are missing for: ' . join( ', ', @Missing );
            return { Success => 0, Error => $Self->{LastError}, Crypto => $Crypto };
        }
        if ( @Missing && $EncryptionPolicy eq 'available' ) {
            $Crypto->{warning_message} = 'S/MIME encryption was skipped because certificates are missing for: '
                . join( ', ', @Missing );
        }
        if ( @Certificates && !@Missing ) {
            my $Encrypted = $Self->_CMSEncrypt( Message => $Message, Certificates => \@Certificates );
            return { Success => 0, Error => $Self->{LastError}, Crypto => $Crypto } if !defined $Encrypted;
            $Message = $Encrypted;
            $Crypto->{was_encrypted} = 1;
            $Crypto->{recipient_fingerprints} = join ',', grep {$_} @Fingerprints;
        }
    }

    return { Success => 1, Message => $Message, Crypto => $Crypto };
}

sub IncomingProcess {
    my ( $Self, %Param ) = @_;
    $Self->{LastError} = '';

    my $Message = $Param{Message} || '';
    my $RecipientEmail = lc( $Param{RecipientEmail} || '' );
    my $Policy = $Self->_PolicyForEmail($RecipientEmail);
    my $Crypto = {
        direction        => 'incoming',
        crypto_type      => 'smime',
        was_encrypted    => 0,
        was_decrypted    => 0,
        was_signed       => 0,
        signature_status => 'none',
    };

    if ( $Message =~ m{application/(?:x-)?pkcs7-mime}i && $Message =~ m{enveloped-data}i ) {
        if ( $Policy && ( !$Policy->{active} || !$Policy->{decrypt_incoming} ) ) {
            $Self->{LastError} = 'Encrypted S/MIME email received, but incoming decryption is disabled for ' . $RecipientEmail;
            $Crypto->{error_message} = $Self->{LastError};
            return { Success => 0, Error => $Self->{LastError}, Crypto => $Crypto };
        }
        else {
            my $Identity = $Self->_IdentityForEmail($RecipientEmail);
            if ( !$Identity ) {
                $Self->{LastError} = 'Encrypted S/MIME email received, but no active identity exists for ' . $RecipientEmail;
                $Crypto->{error_message} = $Self->{LastError};
                return { Success => 0, Error => $Self->{LastError}, Crypto => $Crypto };
            }
            my $Decrypted = $Self->_CMSDecrypt( Message => $Message, Identity => $Identity );
            if ( !defined $Decrypted ) {
                $Crypto->{error_message} = $Self->{LastError};
                return { Success => 0, Error => $Self->{LastError}, Crypto => $Crypto };
            }
            $Message = $Decrypted;
            $Crypto->{was_encrypted} = 1;
            $Crypto->{was_decrypted} = 1;
            $Crypto->{recipient_fingerprints} = $Identity->{fingerprint_sha256} || '';
        }
    }

    if ( $Message =~ m{multipart/signed}i || $Message =~ m{signed-data}i ) {
        $Crypto->{was_signed} = 1;
        if ( !$Policy || $Policy->{verify_incoming} ) {
            my $Verified = $Self->_CMSVerify( Message => $Message );
            if ( !$Verified->{Success} ) {
                $Crypto->{signature_status} = 'invalid';
                $Crypto->{error_message} = $Verified->{Error} || $Self->{LastError};
            }
            else {
                $Message = $Verified->{Message};
                $Crypto->{signature_status} = $Verified->{Trusted} ? 'valid_trusted' : 'valid_untrusted';
                $Crypto->{signer_email} = $Verified->{SignerEmail} || '';
                $Crypto->{signer_fingerprint} = $Verified->{SignerFingerprint} || '';
            }
        }
        else {
            $Crypto->{signature_status} = 'unchecked';
        }
    }

    return { Success => 1, Message => $Message, Crypto => $Crypto };
}

sub ArticleCryptoRecord {
    my ( $Self, %Param ) = @_;
    my $ArticleID = $Param{ArticleID} || 0;
    my $TicketID = $Param{TicketID} || 0;
    my $Crypto = $Param{Crypto} || {};
    return 1 if !$ArticleID || !$TicketID;
    return 1 if !$Crypto->{was_encrypted} && !$Crypto->{was_signed} && !$Crypto->{error_message};

    return $Self->{DB}->Do(
        'INSERT INTO ticket_article_crypto
         (ticket_id, article_id, direction, crypto_type, encrypted, decrypted,
          signed, signature_status, signer_email, signer_fingerprint,
          recipient_fingerprints, error_message, created_at)
         VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, NOW())
         ON DUPLICATE KEY UPDATE direction = VALUES(direction), crypto_type = VALUES(crypto_type),
          encrypted = VALUES(encrypted), decrypted = VALUES(decrypted),
          signed = VALUES(signed), signature_status = VALUES(signature_status),
          signer_email = VALUES(signer_email), signer_fingerprint = VALUES(signer_fingerprint),
          recipient_fingerprints = VALUES(recipient_fingerprints), error_message = VALUES(error_message)',
        $TicketID,
        $ArticleID,
        $Crypto->{direction} || 'incoming',
        $Crypto->{crypto_type} || 'smime',
        $Crypto->{was_encrypted} ? 1 : 0,
        $Crypto->{was_decrypted} ? 1 : 0,
        $Crypto->{was_signed} ? 1 : 0,
        $Crypto->{signature_status} || 'none',
        $Crypto->{signer_email} || '',
        $Crypto->{signer_fingerprint} || '',
        $Crypto->{recipient_fingerprints} || '',
        $Crypto->{error_message} || '',
    );
}

sub ArticleCryptoList {
    my ( $Self, %Param ) = @_;
    my $TicketID = $Param{TicketID} || 0;
    return [] if !$TicketID;
    return $Self->{DB}->SelectAll(
        'SELECT * FROM ticket_article_crypto WHERE ticket_id = ? ORDER BY article_id',
        $TicketID,
    ) || [];
}

sub _PolicyForEmail {
    my ( $Self, $Email ) = @_;
    return if !$Email;
    return $Self->{DB}->SelectRow(
        'SELECT p.* FROM mail_crypto_policy p
         INNER JOIN system_email se ON se.id = p.system_email_id
         WHERE LOWER(se.email) = LOWER(?) LIMIT 1',
        $Email,
    );
}

sub _IdentityForEmail {
    my ( $Self, $Email ) = @_;
    my $Identity = $Self->{DB}->SelectRow(
        'SELECT * FROM mail_crypto_key
         WHERE crypto_type = \'smime\' AND key_role = \'identity\' AND active = 1
           AND LOWER(email_address) = LOWER(?)
           AND (valid_from IS NULL OR valid_from <= NOW())
           AND (valid_until IS NULL OR valid_until >= NOW())
         ORDER BY valid_until DESC, id DESC LIMIT 1',
        $Email,
    );
    return if !$Identity;
    my $PrivateKey = $Self->{Security}->Decrypt( Value => $Identity->{private_key_encrypted} || '' );
    if ( !$PrivateKey ) {
        $Self->{LastError} = $Self->{Security}->Error() || 'S/MIME private key could not be decrypted';
        return;
    }
    $Identity->{private_key_pem} = $PrivateKey;
    return $Identity;
}

sub _RecipientForEmail {
    my ( $Self, $Email ) = @_;
    return $Self->{DB}->SelectRow(
        'SELECT * FROM mail_crypto_key
         WHERE crypto_type = \'smime\' AND key_role = \'recipient\' AND active = 1
           AND LOWER(email_address) = LOWER(?)
           AND (valid_from IS NULL OR valid_from <= NOW())
           AND (valid_until IS NULL OR valid_until >= NOW())
         ORDER BY valid_until DESC, id DESC LIMIT 1',
        $Email,
    );
}

sub _KeyStore {
    my ( $Self, %Param ) = @_;
    my $Info = $Param{Info} || {};
    my $UserID = $Param{ChangedByUserID} || 1;

    my $Result = $Self->{DB}->Do(
        'INSERT INTO mail_crypto_key
         (crypto_type, key_role, system_email_id, email_address, display_name,
          certificate_pem, certificate_chain_pem, private_key_encrypted, fingerprint_sha256, serial_number,
          subject_name, issuer_name, valid_from, valid_until, active,
          created_at, created_by_user_id, changed_at, changed_by_user_id)
         VALUES (\'smime\', ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, 1, NOW(), ?, NOW(), ?)',
        $Param{KeyRole},
        $Param{SystemEmailID},
        $Param{Email},
        $Param{DisplayName} || '',
        $Param{Certificate},
        $Param{CertificateChain},
        $Param{EncryptedKey},
        $Info->{Fingerprint},
        $Info->{Serial},
        $Info->{Subject},
        $Info->{Issuer},
        $Info->{ValidFrom},
        $Info->{ValidUntil},
        $UserID,
        $UserID,
    );
    if ( !$Result ) {
        $Self->{LastError} = $Self->{DB}->Error() || 'S/MIME certificate could not be saved';
        return;
    }
    return $Self->{DB}->LastInsertID('mail_crypto_key') || 1;
}

sub _CertificateNormalize {
    my ( $Self, $Content ) = @_;
    if ( !$Content ) {
        $Self->{LastError} = 'Certificate file is empty';
        return;
    }
    my $Input = $Self->_TempFile( Suffix => '.crt', Content => $Content );
    my ( $Success, $Output, $Error ) = $Self->_Run(
        Command => [ 'openssl', 'x509', '-in', $Input, '-outform', 'PEM' ],
    );
    if ( !$Success ) {
        ( $Success, $Output, $Error ) = $Self->_Run(
            Command => [ 'openssl', 'x509', '-inform', 'DER', '-in', $Input, '-outform', 'PEM' ],
        );
    }
    if ( !$Success ) {
        $Self->{LastError} = 'Invalid X.509 certificate: ' . $Error;
        return;
    }
    return $Output;
}

sub _CertificateChainNormalize {
    my ( $Self, $Content, $LeafCertificate ) = @_;
    return '' if !$Content;

    my $LeafInfo = $Self->_CertificateInfo($LeafCertificate) || {};
    my @Chain;
    while ( $Content =~ m{(-----BEGIN CERTIFICATE-----.*?-----END CERTIFICATE-----)}gs ) {
        my $Certificate = $Self->_CertificateNormalize($1);
        next if !$Certificate;
        my $Info = $Self->_CertificateInfo($Certificate) || next;
        next if $LeafInfo->{Fingerprint}
            && ( $Info->{Fingerprint} || '' ) eq $LeafInfo->{Fingerprint};
        push @Chain, $Certificate;
    }
    $Self->{LastError} = '';
    return join '', @Chain;
}

sub _PrivateKeyNormalize {
    my ( $Self, $Content, $Passphrase ) = @_;
    if ( !$Content ) {
        $Self->{LastError} = 'Private key file is empty';
        return;
    }
    my $Input = $Self->_TempFile( Suffix => '.key', Content => $Content );
    my $PassFile = $Self->_TempFile( Suffix => '.pass', Content => $Passphrase || '' );
    my ( $Success, $Output, $Error ) = $Self->_Run(
        Command => [
            'openssl', 'pkey', '-in', $Input, '-outform', 'PEM',
            '-passin', 'file:' . $PassFile,
        ],
    );
    if ( !$Success ) {
        ( $Success, $Output, $Error ) = $Self->_Run(
            Command => [
                'openssl', 'pkey', '-inform', 'DER', '-in', $Input, '-outform', 'PEM',
                '-passin', 'file:' . $PassFile,
            ],
        );
    }
    if ( !$Success ) {
        $Self->{LastError} = 'Invalid private key or passphrase: ' . $Error;
        return;
    }
    return $Output;
}

sub _KeyMatchesCertificate {
    my ( $Self, %Param ) = @_;
    my $CertificateFile = $Self->_TempFile( Suffix => '.crt', Content => $Param{Certificate} );
    my $PrivateKeyFile = $Self->_TempFile( Suffix => '.key', Content => $Param{PrivateKey} );
    my ( $CertOK, $CertKey ) = $Self->_Run(
        Command => [ 'openssl', 'x509', '-in', $CertificateFile, '-pubkey', '-noout' ],
    );
    my ( $KeyOK, $Key ) = $Self->_Run(
        Command => [ 'openssl', 'pkey', '-in', $PrivateKeyFile, '-pubout' ],
    );
    if ( !$CertOK || !$KeyOK || $CertKey ne $Key ) {
        $Self->{LastError} = 'Private key does not match the certificate';
        return;
    }
    return 1;
}

sub _CertificateInfo {
    my ( $Self, $Certificate ) = @_;
    my $File = $Self->_TempFile( Suffix => '.crt', Content => $Certificate );
    my ( $Success, $Output, $Error ) = $Self->_Run(
        Command => [
            'openssl', 'x509', '-in', $File, '-noout', '-fingerprint', '-sha256',
            '-serial', '-subject', '-issuer', '-dates', '-email', '-nameopt', 'RFC2253',
        ],
    );
    if ( !$Success ) {
        $Self->{LastError} = 'Certificate information could not be read: ' . $Error;
        return;
    }

    my %Info;
    for my $Line ( split m{\r?\n}, $Output ) {
        $Info{Fingerprint} = $1 if $Line =~ m{Fingerprint=(.+)\z}i;
        $Info{Serial} = $1 if $Line =~ m{\Aserial=(.+)\z}i;
        $Info{Subject} = $1 if $Line =~ m{\Asubject=(.+)\z}i;
        $Info{Issuer} = $1 if $Line =~ m{\Aissuer=(.+)\z}i;
        $Info{ValidFrom} = $Self->_CertificateDate($1) if $Line =~ m{\AnotBefore=(.+)\z}i;
        $Info{ValidUntil} = $Self->_CertificateDate($1) if $Line =~ m{\AnotAfter=(.+)\z}i;
        if ( $Line =~ m{\A[^=\s]+\@[^=\s]+\z} ) {
            push @{ $Info{Emails} }, lc $Line;
        }
    }
    $Info{Fingerprint} ||= '';
    $Info{Fingerprint} =~ s{:}{}g;
    return \%Info;
}

sub _CertificateEmailMatches {
    my ( $Self, %Param ) = @_;
    my $Email = lc( $Param{Email} || '' );
    for my $CertificateEmail ( @{ $Param{Info}->{Emails} || [] } ) {
        return 1 if lc($CertificateEmail) eq $Email;
    }
    return;
}

sub _CertificateDate {
    my ( $Self, $Value ) = @_;
    my $Time = eval { Time::Piece->strptime( $Value, '%b %e %H:%M:%S %Y %Z' ) };
    return $Time ? $Time->strftime('%Y-%m-%d %H:%M:%S') : undef;
}

sub _CMSSign {
    my ( $Self, %Param ) = @_;
    my ( $Outer, $Entity ) = $Self->_MessageSplit( $Param{Message} );
    my $Input = $Self->_TempFile( Suffix => '.eml', Content => $Entity );
    my $Certificate = $Self->_TempFile( Suffix => '.crt', Content => $Param{Identity}->{certificate_pem} );
    my $PrivateKey = $Self->_TempFile( Suffix => '.key', Content => $Param{Identity}->{private_key_pem} );
    my @ChainParameter;
    if ( $Param{Identity}->{certificate_chain_pem} ) {
        my $Chain = $Self->_TempFile(
            Suffix  => '.chain.pem',
            Content => $Param{Identity}->{certificate_chain_pem},
        );
        @ChainParameter = ( '-certfile', $Chain );
    }
    my ( $Success, $Output, $Error ) = $Self->_Run(
        Command => [
            'openssl', 'cms', '-sign', '-in', $Input, '-signer', $Certificate,
            '-inkey', $PrivateKey, @ChainParameter, '-outform', 'SMIME', '-md', 'sha256',
        ],
    );
    if ( !$Success ) {
        $Self->{LastError} = 'S/MIME signing failed: ' . $Error;
        return;
    }
    return $Self->_MessageJoin( $Outer, $Output );
}

sub _CMSEncrypt {
    my ( $Self, %Param ) = @_;
    my ( $Outer, $Entity ) = $Self->_MessageSplit( $Param{Message} );
    my $Input = $Self->_TempFile( Suffix => '.eml', Content => $Entity );
    my @Certificates;
    for my $Content ( @{ $Param{Certificates} || [] } ) {
        push @Certificates, $Self->_TempFile( Suffix => '.crt', Content => $Content );
    }
    if ( !@Certificates ) {
        $Self->{LastError} = 'No S/MIME recipient certificates are available';
        return;
    }
    my ( $Success, $Output, $Error ) = $Self->_Run(
        Command => [
            'openssl', 'cms', '-encrypt', '-binary', '-aes256', '-in', $Input,
            '-outform', 'SMIME', @Certificates,
        ],
    );
    if ( !$Success ) {
        $Self->{LastError} = 'S/MIME encryption failed: ' . $Error;
        return;
    }
    return $Self->_MessageJoin( $Outer, $Output );
}

sub _CMSDecrypt {
    my ( $Self, %Param ) = @_;
    my ( $Outer, $Entity ) = $Self->_MessageSplit( $Param{Message} );
    my $Input = $Self->_TempFile( Suffix => '.eml', Content => $Entity );
    my $Certificate = $Self->_TempFile( Suffix => '.crt', Content => $Param{Identity}->{certificate_pem} );
    my $PrivateKey = $Self->_TempFile( Suffix => '.key', Content => $Param{Identity}->{private_key_pem} );
    my ( $Success, $Output, $Error ) = $Self->_Run(
        Command => [
            'openssl', 'cms', '-decrypt', '-binary', '-inform', 'SMIME', '-in', $Input,
            '-recip', $Certificate, '-inkey', $PrivateKey,
        ],
    );
    if ( !$Success ) {
        $Self->{LastError} = 'S/MIME decryption failed: ' . $Error;
        return;
    }
    return $Self->_MessageJoin( $Outer, $Output );
}

sub _CMSVerify {
    my ( $Self, %Param ) = @_;
    my ( $Outer, $Entity ) = $Self->_MessageSplit( $Param{Message} );
    my $Input = $Self->_TempFile( Suffix => '.eml', Content => $Entity );
    my $Signer = $Self->_TempFile( Suffix => '.crt', Content => '' );
    my ( $Success, $Output, $Error ) = $Self->_Run(
        Command => [
            'openssl', 'cms', '-verify', '-inform', 'SMIME', '-in', $Input,
            '-noverify', '-signer', $Signer,
        ],
    );
    if ( !$Success ) {
        return { Success => 0, Error => 'S/MIME signature verification failed: ' . $Error };
    }

    my $Certificate = $Self->_FileRead($Signer);
    my $Info = $Certificate ? $Self->_CertificateInfo($Certificate) : {};
    my $SignerEmail = ( $Info->{Emails} && @{ $Info->{Emails} } ) ? $Info->{Emails}->[0] : '';
    my $Trusted = $Self->_CMSMessageTrusted($Input)
        || $Self->_CertificateKnown( $Info->{Fingerprint} || '' );

    return {
        Success           => 1,
        Message           => $Self->_MessageJoin( $Outer, $Output ),
        Trusted           => $Trusted,
        SignerEmail       => $SignerEmail,
        SignerFingerprint => $Info->{Fingerprint} || '',
    };
}

sub _CMSMessageTrusted {
    my ( $Self, $Input ) = @_;
    return 0 if !$Input;
    my @Command = (
        'openssl', 'cms', '-verify', '-inform', 'SMIME', '-in', $Input,
    );
    my $CAFile = $Self->{Config}->{Mail}->{SMIMECAFile} || '';
    push @Command, '-CAfile', $CAFile if $CAFile;
    my ( $Success ) = $Self->_Run( Command => \@Command );
    return $Success ? 1 : 0;
}

sub _CertificateKnown {
    my ( $Self, $Fingerprint ) = @_;
    return 0 if !$Fingerprint || !$Self->{DB};
    my $Known = $Self->{DB}->SelectRow(
        'SELECT id FROM mail_crypto_key
         WHERE crypto_type = \'smime\' AND fingerprint_sha256 = ? AND active = 1
         LIMIT 1',
        $Fingerprint,
    );
    return $Known ? 1 : 0;
}

sub _MessageSplit {
    my ( $Self, $Message ) = @_;
    $Message =~ s{\r?\n}{\r\n}g;
    my ( $Header, $Body ) = split m{\r\n\r\n}, $Message, 2;
    $Body = '' if !defined $Body;
    my @Fields = split m{\r\n(?=[^ \t])}, $Header || '';
    my ( @Outer, @Content );
    for my $Field (@Fields) {
        if ( $Field =~ m{\A(?:Content-|MIME-Version:)}i ) {
            push @Content, $Field;
        }
        else {
            push @Outer, $Field;
        }
    }
    my $Entity = join( "\r\n", @Content ) . "\r\n\r\n" . $Body;
    return ( join( "\r\n", @Outer ), $Entity );
}

sub _MessageJoin {
    my ( $Self, $Outer, $Entity ) = @_;
    $Entity =~ s{\r?\n}{\r\n}g;
    $Entity =~ s{\A\r\n+}{};
    return ( $Outer ? $Outer . "\r\n" : '' ) . $Entity;
}

sub _TempFile {
    my ( $Self, %Param ) = @_;
    my ( $Handle, $Path ) = tempfile( 'part-XXXXXX', DIR => $Self->{TempDir}, SUFFIX => $Param{Suffix} || '' );
    binmode $Handle;
    print {$Handle} defined $Param{Content} ? $Param{Content} : '';
    close $Handle;
    chmod 0600, $Path;
    return $Path;
}

sub _FileRead {
    my ( $Self, $Path ) = @_;
    open my $Handle, '<', $Path or return '';
    binmode $Handle;
    local $/;
    my $Content = <$Handle>;
    close $Handle;
    return defined $Content ? $Content : '';
}

sub _Run {
    my ( $Self, %Param ) = @_;
    my $Command = $Param{Command} || [];
    my $ErrorHandle = gensym;
    my ( $InputHandle, $OutputHandle );
    my $PID = eval { open3( $InputHandle, $OutputHandle, $ErrorHandle, @{$Command} ) };
    if ( !$PID ) {
        return ( 0, '', $@ || 'Command could not be started' );
    }
    close $InputHandle;
    binmode $OutputHandle;
    binmode $ErrorHandle;
    local $/;
    my $Output = <$OutputHandle>;
    my $Error = <$ErrorHandle>;
    close $OutputHandle;
    close $ErrorHandle;
    waitpid $PID, 0;
    my $ExitCode = $? >> 8;
    $Output = '' if !defined $Output;
    $Error = '' if !defined $Error;
    $Error =~ s{[\r\n]+}{ }g;
    return ( $ExitCode == 0 ? 1 : 0, $Output, $Error );
}

1;
