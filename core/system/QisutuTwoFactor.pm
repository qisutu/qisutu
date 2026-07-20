# Qisutu - Open Source Ticket System
# Copyright (C) 2026 Franziska Steps
# Qisutu - Kim-KI, https://qisutu.de
# SPDX-License-Identifier: AGPL-3.0-or-later

package QisutuTwoFactor;

use strict;
use warnings;
use utf8;

use Digest::SHA qw(sha256_hex);
use Encode qw(encode);
use JSON::PP;
use QisutuSecurity;
use QisutuSystemSetting;

sub new {
    my ( $Class, %Param ) = @_;
    my $Self = {
        Config    => $Param{Config},
        DB        => $Param{DB},
        Security  => QisutuSecurity->new( Config => $Param{Config} ),
        LastError => '',
    };
    bless $Self, $Class;
    return $Self;
}

sub Error { return $_[0]->{LastError} || '' }

sub ProvisioningURI {
    my ( $Self, %Param ) = @_;

    my $Secret = uc( $Param{Secret} || '' );
    $Secret =~ s{\s+}{}g;
    return '' if $Secret !~ m{\A[A-Z2-7]+\z};

    my $Issuer = $Param{Issuer} || $Self->{Config}->{System}->{Name} || 'Qisutu';
    my $InstanceID = $Self->{Config}->{System}->{InstanceID} || '';
    if ( $InstanceID && lc($InstanceID) ne lc($Issuer) ) {
        $Issuer .= ' (' . $InstanceID . ')';
    }

    my $AccountName = $Param{AccountName} || '';
    $AccountName =~ s{\A\s+|\s+\z}{}g;
    return '' if !$AccountName;

    return 'otpauth://totp/'
        . $Self->_URIComponent($Issuer)
        . ':'
        . $Self->_URIComponent($AccountName)
        . '?secret=' . $Secret
        . '&issuer=' . $Self->_URIComponent($Issuer)
        . '&algorithm=SHA1&digits=6&period=30';
}

sub StatusGet {
    my ( $Self, %Param ) = @_;
    $Self->{LastError} = '';
    my $ID = $Param{UserAccountID} || 0;
    return {} if !$ID;
    my $Row = $Self->{DB}->SelectRow(
        'SELECT user_account_id, secret_encrypted, enabled, recovery_code_hashes, changed_at
         FROM user_two_factor WHERE user_account_id = ? LIMIT 1',
        $ID,
    );
    if ( !$Row ) {
        if ( $Self->{DB}->Error() ) {
            $Self->{LastError} = $Self->{DB}->Error();
            return {};
        }
        return { enabled => 0, configured => 0, recovery_codes_remaining => 0 };
    }
    my $Hashes = $Self->_HashesDecode( $Row->{recovery_code_hashes} );
    my $Secret = $Self->{Security}->Decrypt( Value => $Row->{secret_encrypted} || '' );
    if ( !defined $Secret ) {
        $Self->{LastError} = $Self->{Security}->Error() || 'Two-factor secret could not be decrypted';
        return {};
    }
    return {
        %{$Row},
        secret                   => $Secret,
        configured               => 1,
        recovery_codes_remaining => scalar @{$Hashes},
    };
}

sub Required {
    my ( $Self, %Param ) = @_;
    $Self->{LastError} = '';
    my $User = $Param{User} || {};
    my $Status = $Self->StatusGet( UserAccountID => $User->{id} || $User->{user_account_id} );
    return 1 if $Self->{LastError};
    return 1 if $Status->{enabled};

    my $AccountType = $User->{account_type} || '';
    my $IsAdministrator = $AccountType eq 'customer'
        ? 0
        : $Self->_IsAdministrator( UserAccountID => $User->{id} || $User->{user_account_id} );
    return 1 if $Self->{LastError};
    my $Key = $AccountType eq 'customer'
        ? 'security.2fa.enforce_customers'
        : $IsAdministrator
            ? 'security.2fa.enforce_administrators'
            : 'security.2fa.enforce_agents';

    return QisutuSystemSetting->new( Config => $Self->{Config}, DB => $Self->{DB} )->Get(
        Key     => $Key,
        Default => 0,
    ) ? 1 : 0;
}

sub SetupStart {
    my ( $Self, %Param ) = @_;
    $Self->{LastError} = '';
    my $ID = $Param{UserAccountID} || 0;
    return if !$ID;
    my $Secret = $Self->{Security}->TOTPSecretCreate();
    my $Encrypted = $Self->{Security}->Encrypt( Value => $Secret );
    if ( !$Secret || !defined $Encrypted ) {
        $Self->{LastError} = $Self->{Security}->Error() || 'Two-factor setup could not be started';
        return;
    }
    my $OK = $Self->{DB}->Do(
        'INSERT INTO user_two_factor (user_account_id, secret_encrypted, enabled, recovery_code_hashes)
         VALUES (?, ?, 0, NULL)
         ON DUPLICATE KEY UPDATE secret_encrypted = VALUES(secret_encrypted), enabled = 0, recovery_code_hashes = NULL',
        $ID, $Encrypted,
    );
    if ( !$OK ) {
        $Self->{LastError} = $Self->{DB}->Error() || 'Two-factor setup could not be saved';
        return;
    }
    return $Secret;
}

sub SetupConfirm {
    my ( $Self, %Param ) = @_;
    $Self->{LastError} = '';
    my $ID = $Param{UserAccountID} || 0;
    my $Status = $Self->StatusGet( UserAccountID => $ID );
    if ( !$Status->{configured} || !$Self->{Security}->TOTPVerify( Secret => $Status->{secret}, Code => $Param{Code} || '' ) ) {
        $Self->{LastError} = 'Translate:TwoFactorCodeInvalid';
        return;
    }
    my $Codes = $Self->{Security}->RecoveryCodesCreate();
    my @Hashes = map { $Self->{Security}->RecoveryCodeHash( Code => $_ ) } @{$Codes};
    my $OK = $Self->{DB}->Do(
        'UPDATE user_two_factor SET enabled = 1, recovery_code_hashes = ?, last_used_counter = ? WHERE user_account_id = ?',
        JSON::PP->new->canonical(1)->encode(\@Hashes), int( time() / 30 ), $ID,
    );
    if ( !$OK ) {
        $Self->{LastError} = $Self->{DB}->Error() || 'Two-factor setup could not be enabled';
        return;
    }
    return $Codes;
}

sub Verify {
    my ( $Self, %Param ) = @_;
    $Self->{LastError} = '';
    my $ID = $Param{UserAccountID} || 0;
    my $Code = $Param{Code} || '';
    my $Status = $Self->StatusGet( UserAccountID => $ID );
    return if !$Status->{enabled};

    if ( $Self->{Security}->TOTPVerify( Secret => $Status->{secret}, Code => $Code ) ) {
        $Self->{DB}->Do(
            'UPDATE user_two_factor SET last_used_counter = ? WHERE user_account_id = ?',
            int( time() / 30 ), $ID,
        );
        return 1;
    }

    my $Hash = $Self->{Security}->RecoveryCodeHash( Code => $Code );
    my $Hashes = $Self->_HashesDecode( $Status->{recovery_code_hashes} );
    for my $Index ( 0 .. $#{$Hashes} ) {
        next if !$Self->_ConstantTimeEqual( $Hashes->[$Index], $Hash );
        splice @{$Hashes}, $Index, 1;
        $Self->{DB}->Do(
            'UPDATE user_two_factor SET recovery_code_hashes = ? WHERE user_account_id = ?',
            JSON::PP->new->canonical(1)->encode($Hashes), $ID,
        );
        return 1;
    }

    $Self->{LastError} = 'Translate:TwoFactorCodeInvalid';
    return;
}

sub Disable {
    my ( $Self, %Param ) = @_;
    $Self->{LastError} = '';
    return if !$Self->Verify(%Param);
    return $Self->Reset( UserAccountID => $Param{UserAccountID} );
}

sub RecoveryCodesRegenerate {
    my ( $Self, %Param ) = @_;
    $Self->{LastError} = '';
    return if !$Self->Verify(%Param);
    my $Codes = $Self->{Security}->RecoveryCodesCreate();
    my @Hashes = map { $Self->{Security}->RecoveryCodeHash( Code => $_ ) } @{$Codes};
    my $OK = $Self->{DB}->Do(
        'UPDATE user_two_factor SET recovery_code_hashes = ? WHERE user_account_id = ?',
        JSON::PP->new->canonical(1)->encode(\@Hashes), $Param{UserAccountID},
    );
    return $Codes if $OK;
    $Self->{LastError} = $Self->{DB}->Error() || 'Recovery codes could not be regenerated';
    return;
}

sub Reset {
    my ( $Self, %Param ) = @_;
    $Self->{LastError} = '';
    my $ID = $Param{UserAccountID} || 0;
    return if !$ID;
    $Self->{DB}->Do( 'DELETE FROM user_two_factor_challenge WHERE user_account_id = ?', $ID );
    my $OK = $Self->{DB}->Do( 'DELETE FROM user_two_factor WHERE user_account_id = ?', $ID );
    if ( !$OK ) {
        $Self->{LastError} = $Self->{DB}->Error() || 'Two-factor authentication could not be reset';
        return;
    }
    return 1;
}

sub ChallengeCreate {
    my ( $Self, %Param ) = @_;
    $Self->{LastError} = '';
    my $User = $Param{User} || {};
    my $ID = $User->{id} || 0;
    return if !$ID;
    my $Status = $Self->StatusGet( UserAccountID => $ID );
    return if $Self->{LastError};
    my $Mode = $Status->{enabled} ? 'login' : 'setup';
    $Self->SetupStart( UserAccountID => $ID ) if $Mode eq 'setup';
    return if $Self->{LastError};

    my $Token = unpack( 'H*', $Self->{Security}->_RandomBytes(32) || '' );
    return if !$Token;
    $Self->{DB}->Do( 'DELETE FROM user_two_factor_challenge WHERE user_account_id = ? OR expires_at < NOW()', $ID );
    my $OK = $Self->{DB}->Do(
        'INSERT INTO user_two_factor_challenge (token_hash, user_account_id, account_type, mode, expires_at)
         VALUES (?, ?, ?, ?, DATE_ADD(NOW(), INTERVAL 10 MINUTE))',
        sha256_hex($Token), $ID, $User->{account_type} || 'agent', $Mode,
    );
    if ( !$OK ) {
        $Self->{LastError} = $Self->{DB}->Error() || 'Two-factor login challenge could not be created';
        return;
    }
    my $Current = $Self->StatusGet( UserAccountID => $ID );
    my $AccountName = $User->{email} || $User->{login} || 'user-' . $ID;
    return {
        Token           => $Token,
        Mode            => $Mode,
        Secret          => $Current->{secret} || '',
        AccountName     => $AccountName,
        ProvisioningURI => $Self->ProvisioningURI(
            Secret      => $Current->{secret} || '',
            AccountName => $AccountName,
        ),
    };
}

sub ChallengeVerify {
    my ( $Self, %Param ) = @_;
    $Self->{LastError} = '';
    my $Token = $Param{Token} || '';
    return if $Token !~ m{\A[0-9a-f]{64}\z};
    my $Row = $Self->{DB}->SelectRow(
        'SELECT c.*, ua.login, ua.email, ua.firstname, ua.lastname, ua.is_active
         FROM user_two_factor_challenge c
         INNER JOIN user_account ua ON ua.id = c.user_account_id
         WHERE c.token_hash = ? AND c.expires_at >= NOW() AND c.attempts < 5 LIMIT 1',
        sha256_hex($Token),
    );
    if ( !$Row || !$Row->{is_active} ) {
        $Self->{LastError} = 'Translate:TwoFactorChallengeInvalid';
        return;
    }
    my $Codes;
    my $OK = ( $Row->{mode} || '' ) eq 'setup'
        ? ( $Codes = $Self->SetupConfirm( UserAccountID => $Row->{user_account_id}, Code => $Param{Code} || '' ) )
        : $Self->Verify( UserAccountID => $Row->{user_account_id}, Code => $Param{Code} || '' );
    if ( !$OK ) {
        $Self->{DB}->Do( 'UPDATE user_two_factor_challenge SET attempts = attempts + 1 WHERE id = ?', $Row->{id} );
        return;
    }
    $Self->{DB}->Do( 'DELETE FROM user_two_factor_challenge WHERE id = ?', $Row->{id} );
    return { User => $Row, RecoveryCodes => $Codes || [] };
}

sub _IsAdministrator {
    my ( $Self, %Param ) = @_;
    my $Row = $Self->{DB}->SelectRow(
        'SELECT COUNT(*) AS permission_count
         FROM user_group_member ugm
         INNER JOIN user_group_permission ugp ON ugp.user_group_id = ugm.user_group_id
         INNER JOIN user_group ug ON ug.id = ugm.user_group_id
         WHERE ugm.user_account_id = ? AND ugm.active = 1 AND ug.active = 1
           AND ugp.permission_key = "admin.view" AND ugp.active = 1',
        $Param{UserAccountID} || 0,
    );
    if ( !$Row && $Self->{DB}->Error() ) {
        $Self->{LastError} = $Self->{DB}->Error();
        return;
    }
    return $Row && $Row->{permission_count} ? 1 : 0;
}

sub _HashesDecode {
    my ( $Self, $JSON ) = @_;
    my $Value = eval { JSON::PP->new->decode( $JSON || '[]' ) };
    return ref $Value eq 'ARRAY' ? $Value : [];
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

sub _URIComponent {
    my ( $Self, $Value ) = @_;

    my $Bytes = encode( 'UTF-8', defined $Value ? $Value : '' );
    $Bytes =~ s{([^A-Za-z0-9\-._~])}{sprintf '%%%02X', ord($1)}ge;

    return $Bytes;
}

1;
