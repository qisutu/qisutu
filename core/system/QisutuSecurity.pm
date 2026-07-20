# Qisutu - Open Source Ticket System
# Copyright (C) 2026 Franziska Steps
# Qisutu - Kim-KI, https://qisutu.de
# SPDX-License-Identifier: AGPL-3.0-or-later

package QisutuSecurity;

use strict;
use warnings;
use utf8;

use Digest::SHA qw(hmac_sha1 hmac_sha256 hmac_sha256_hex sha256_hex);
use Encode qw(decode encode);
use IPC::Open3;
use MIME::Base64 qw(decode_base64 encode_base64);
use Symbol qw(gensym);

sub new {
    my ( $Class, %Param ) = @_;

    my $Self = {
        Config    => $Param{Config} || {},
        LastError => '',
    };

    bless $Self, $Class;

    return $Self;
}

sub Error {
    my ($Self) = @_;
    return $Self->{LastError} || '';
}

sub CSRFToken {
    my ( $Self, %Param ) = @_;

    my $SessionToken = $Param{SessionToken} || '';
    my $Key = $Self->_MasterKey();
    return '' if !$SessionToken || !$Key;

    return hmac_sha256_hex( "qisutu-csrf\0" . $SessionToken, $Key );
}

sub CSRFTokenVerify {
    my ( $Self, %Param ) = @_;

    my $Expected = $Self->CSRFToken( SessionToken => $Param{SessionToken} || '' );
    my $Provided = $Param{Token} || '';

    return if !$Expected || !$Provided;
    return $Self->_ConstantTimeEqual( $Expected, $Provided );
}

sub PublicCSRFTokenCreate {
    my ( $Self, %Param ) = @_;

    my $Key = $Self->_MasterKey();
    return '' if !$Key;

    my $Timestamp = time();
    my $Random = unpack( 'H*', $Self->_RandomBytes(16) || '' );
    return '' if !$Random;

    my $Purpose = $Param{Purpose} || 'public-form';
    my $Payload = join '.', $Timestamp, $Random;
    my $MAC = hmac_sha256_hex( "qisutu-public-csrf\0$Purpose\0$Payload", $Key );

    return join '.', $Payload, $MAC;
}

sub PublicCSRFTokenVerify {
    my ( $Self, %Param ) = @_;

    my $Token = $Param{Token} || '';
    my ( $Timestamp, $Random, $MAC ) = split /\./, $Token, 3;
    return if !$Timestamp || $Timestamp !~ m{\A\d{10}\z};
    return if !$Random || $Random !~ m{\A[0-9a-f]{32}\z};
    return if !$MAC || $MAC !~ m{\A[0-9a-f]{64}\z};
    return if $Timestamp > time() + 300 || $Timestamp < time() - 7200;

    my $Key = $Self->_MasterKey();
    return if !$Key;

    my $Purpose = $Param{Purpose} || 'public-form';
    my $Payload = join '.', $Timestamp, $Random;
    my $Expected = hmac_sha256_hex( "qisutu-public-csrf\0$Purpose\0$Payload", $Key );

    return $Self->_ConstantTimeEqual( $Expected, $MAC );
}

sub Encrypt {
    my ( $Self, %Param ) = @_;

    $Self->{LastError} = '';

    my $Value = defined $Param{Value} ? $Param{Value} : '';
    return '' if $Value eq '';
    return $Value if $Value =~ m{\Aqse1:};

    my $MasterKey = $Self->_MasterKey();
    return if !$MasterKey;

    my $Salt = $Self->_RandomBytes(16);
    my $IV   = $Self->_RandomBytes(16);
    return if !defined $Salt || !defined $IV;

    my $EncryptionKey = hmac_sha256( "qisutu-secret-encryption\0" . $Salt, $MasterKey );
    my $AuthenticationKey = hmac_sha256( "qisutu-secret-authentication\0" . $Salt, $MasterKey );
    my $Plain = encode( 'UTF-8', $Value );
    my $Cipher = $Self->_OpenSSLCrypt(
        Mode => 'encrypt',
        Key  => $EncryptionKey,
        IV   => $IV,
        Data => $Plain,
    );
    return if !defined $Cipher;

    my $Envelope = "\x01" . $Salt . $IV . $Cipher;
    my $MAC = hmac_sha256( $Envelope, $AuthenticationKey );
    my $Encoded = encode_base64( $Envelope . $MAC, '' );
    $Encoded =~ tr{+/}{-_};
    $Encoded =~ s{=+\z}{};

    return 'qse1:' . $Encoded;
}

sub Decrypt {
    my ( $Self, %Param ) = @_;

    $Self->{LastError} = '';

    my $Value = defined $Param{Value} ? $Param{Value} : '';
    return '' if $Value eq '';
    return $Value if $Value !~ m{\Aqse1:(.+)\z}s;

    my $Encoded = $1;
    $Encoded =~ tr{-_}{+/};
    $Encoded .= '=' x ( ( 4 - length($Encoded) % 4 ) % 4 );
    my $Raw = eval { decode_base64($Encoded) };
    # Envelope: version (1) + salt (16) + IV (16) + at least one AES
    # block (16) + MAC (32) = 81 bytes. The previous lower bound of 82
    # rejected every otherwise valid secret whose ciphertext used exactly
    # one block, which commonly affects shorter mail passwords.
    if (
        !defined $Raw
        || length($Raw) < 81
        || ( length($Raw) - 65 ) % 16
        || substr( $Raw, 0, 1 ) ne "\x01"
    ) {
        $Self->{LastError} = 'Encrypted secret is damaged or incomplete';
        return;
    }

    my $MasterKey = $Self->_MasterKey();
    return if !$MasterKey;

    my $Envelope = substr( $Raw, 0, -32 );
    my $MAC      = substr( $Raw, -32 );
    my $Salt     = substr( $Envelope, 1, 16 );
    my $IV       = substr( $Envelope, 17, 16 );
    my $Cipher   = substr( $Envelope, 33 );
    my $EncryptionKey = hmac_sha256( "qisutu-secret-encryption\0" . $Salt, $MasterKey );
    my $AuthenticationKey = hmac_sha256( "qisutu-secret-authentication\0" . $Salt, $MasterKey );
    my $Expected = hmac_sha256( $Envelope, $AuthenticationKey );

    if ( !$Self->_ConstantTimeEqual( $Expected, $MAC ) ) {
        $Self->{LastError} = 'Encrypted secret authentication failed';
        return;
    }

    my $Plain = $Self->_OpenSSLCrypt(
        Mode => 'decrypt',
        Key  => $EncryptionKey,
        IV   => $IV,
        Data => $Cipher,
    );
    return if !defined $Plain;

    my $Decoded = eval { decode( 'UTF-8', $Plain, 1 ) };
    if ( !defined $Decoded ) {
        $Self->{LastError} = 'Encrypted secret is not valid UTF-8';
        return;
    }

    return $Decoded;
}

sub TOTPSecretCreate {
    my ($Self) = @_;
    return $Self->_Base32Encode( $Self->_RandomBytes(20) || '' );
}

sub TOTPVerify {
    my ( $Self, %Param ) = @_;

    my $Secret = $Param{Secret} || '';
    my $Code   = $Param{Code} || '';
    $Code =~ s{\s+}{}g;
    return if $Code !~ m{\A\d{6}\z};

    my $Now = defined $Param{Time} ? $Param{Time} : time();
    for my $Offset ( -1, 0, 1 ) {
        my $Expected = $Self->_TOTPCode( Secret => $Secret, Counter => int( $Now / 30 ) + $Offset );
        return 1 if $Expected && $Self->_ConstantTimeEqual( $Expected, $Code );
    }

    return;
}

sub RecoveryCodesCreate {
    my ($Self) = @_;
    my @Codes;
    for ( 1 .. 10 ) {
        my $Raw = unpack( 'H*', $Self->_RandomBytes(8) || '' );
        return [] if !$Raw;
        push @Codes, uc( substr( $Raw, 0, 4 ) . '-' . substr( $Raw, 4, 4 ) . '-' . substr( $Raw, 8, 4 ) );
    }
    return \@Codes;
}

sub RecoveryCodeHash {
    my ( $Self, %Param ) = @_;
    my $Code = uc( $Param{Code} || '' );
    $Code =~ s{[^A-Z0-9]}{}g;
    return '' if !$Code;
    return sha256_hex( "qisutu-recovery-code\0" . $Code );
}

sub _TOTPCode {
    my ( $Self, %Param ) = @_;

    my $Key = $Self->_Base32Decode( $Param{Secret} || '' );
    return '' if !$Key;
    my $Counter = $Param{Counter} || 0;
    my $Message = pack( 'NN', int( $Counter / 4294967296 ), $Counter % 4294967296 );
    my $Digest = hmac_sha1( $Message, $Key );
    my $Offset = ord( substr( $Digest, -1 ) ) & 0x0f;
    my $Binary = unpack( 'N', substr( $Digest, $Offset, 4 ) ) & 0x7fffffff;
    return sprintf '%06d', $Binary % 1_000_000;
}

sub _Base32Encode {
    my ( $Self, $Raw ) = @_;
    return '' if !defined $Raw || $Raw eq '';
    my $Alphabet = 'ABCDEFGHIJKLMNOPQRSTUVWXYZ234567';
    my $Bits = join '', map { sprintf '%08b', ord($_) } split //, $Raw;
    $Bits .= '0' x ( ( 5 - length($Bits) % 5 ) % 5 );
    return join '', map { substr( $Alphabet, oct( '0b' . $_ ), 1 ) } ( $Bits =~ m{(.{5})}g );
}

sub _Base32Decode {
    my ( $Self, $Value ) = @_;
    $Value = uc( $Value || '' );
    $Value =~ s{[^A-Z2-7]}{}g;
    return '' if !$Value;
    my %Index;
    @Index{ split //, 'ABCDEFGHIJKLMNOPQRSTUVWXYZ234567' } = ( 0 .. 31 );
    my $Bits = join '', map { sprintf '%05b', $Index{$_} } split //, $Value;
    my $Raw = '';
    while ( length($Bits) >= 8 ) {
        $Raw .= chr( oct( '0b' . substr( $Bits, 0, 8, '' ) ) );
    }
    return $Raw;
}

sub _OpenSSLCrypt {
    my ( $Self, %Param ) = @_;

    my $Mode = $Param{Mode} || '';
    my @Command = (
        'openssl', 'enc', '-aes-256-cbc',
        ( $Mode eq 'decrypt' ? '-d' : '-e' ),
        '-K', unpack( 'H*', $Param{Key} || '' ),
        '-iv', unpack( 'H*', $Param{IV} || '' ),
    );

    my $Error = gensym;
    my ( $Input, $Output );
    my $PID = eval { open3( $Input, $Output, $Error, @Command ) };
    if ( !$PID ) {
        $Self->{LastError} = 'OpenSSL could not be started';
        return;
    }
    binmode $Input;
    binmode $Output;
    print {$Input} ( defined $Param{Data} ? $Param{Data} : '' );
    close $Input;
    local $/;
    my $Result = <$Output>;
    my $ErrorText = <$Error>;
    close $Output;
    close $Error;
    waitpid $PID, 0;

    if ( $? != 0 ) {
        $Self->{LastError} = 'OpenSSL encryption operation failed';
        return;
    }

    return defined $Result ? $Result : '';
}

sub _MasterKey {
    my ($Self) = @_;
    return $Self->{MasterKey} if $Self->{MasterKey};

    my $Root = $Self->{Config}->{RootPath} || $ENV{QISUTU_HOME} || '/opt/qisutu';
    my $File = $Self->{Config}->{Paths}->{SecurityKey} || "$Root/var/secure/security.key";
    my $FH;
    if ( !open $FH, '<', $File ) {
        $Self->{LastError} = "Security key cannot be read: $File";
        return;
    }
    local $/;
    my $Hex = <$FH>;
    close $FH;
    $Hex =~ s{\s+}{}g;
    if ( $Hex !~ m{\A[0-9a-fA-F]{64}\z} ) {
        $Self->{LastError} = 'Security key has an invalid format';
        return;
    }
    $Self->{MasterKey} = pack( 'H*', $Hex );
    return $Self->{MasterKey};
}

sub _RandomBytes {
    my ( $Self, $Length ) = @_;
    my $FH;
    if ( !open $FH, '<:raw', '/dev/urandom' ) {
        $Self->{LastError} = 'Secure random source is not available';
        return;
    }
    my $Data = '';
    my $Read = read $FH, $Data, $Length;
    close $FH;
    if ( !defined $Read || $Read != $Length ) {
        $Self->{LastError} = 'Secure random data could not be read';
        return;
    }
    return $Data;
}

sub _ConstantTimeEqual {
    my ( $Self, $Left, $Right ) = @_;
    return if !defined $Left || !defined $Right || $Left eq '' || length($Left) != length($Right);
    my $Difference = 0;
    for my $Index ( 0 .. length($Left) - 1 ) {
        $Difference |= ord( substr( $Left, $Index, 1 ) ) ^ ord( substr( $Right, $Index, 1 ) );
    }
    return $Difference == 0 ? 1 : 0;
}

1;
