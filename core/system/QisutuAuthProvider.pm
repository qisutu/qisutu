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

package QisutuAuthProvider;

use strict;
use warnings;
use utf8;

use Digest::SHA qw(sha256 sha256_hex);
use MIME::Base64 qw(encode_base64);

use QisutuAddonManager;
use QisutuSecurity;
use QisutuSystemSetting;

sub new {
    my ( $Class, %Param ) = @_;
    my $Self = {
        Config    => $Param{Config} || {},
        DB        => $Param{DB},
        Security  => $Param{Security} || QisutuSecurity->new( Config => $Param{Config} || {} ),
        LastError => '',
    };
    bless $Self, $Class;
    return $Self;
}

sub Error {
    my ($Self) = @_;
    return $Self->{LastError} || '';
}

sub ProviderList {
    my ( $Self, %Param ) = @_;
    my $AccountType = $Param{AccountType} || '';
    my $Runtime = $Self->{Config}->{AddonRuntime} || {};
    my $Manager = QisutuAddonManager->new( Config => $Self->{Config}, DB => $Self->{DB} );
    my @Provider;
    for my $Definition ( @{ $Runtime->{AuthProviders} || [] } ) {
        next if ref $Definition ne 'HASH';
        next if $AccountType && ( $Definition->{account_type} || '' ) ne $AccountType;
        my $Settings = $Manager->SettingsGet( Identifier => $Definition->{package_identifier} );
        my $EnabledKey = $Definition->{enabled_setting} || 'enabled';
        next if exists $Settings->{$EnabledKey} && !$Settings->{$EnabledKey};
        next if ( $Definition->{key} || '' ) !~ m{\A[a-z][a-z0-9_.-]{0,189}\z};
        my $AutoRedirectKey = $Definition->{auto_redirect_setting} || '';
        my $AllowLocalKey   = $Definition->{allow_local_login_setting} || '';
        push @Provider, {
            %{$Definition},
            Settings => $Settings,
            begin_url => 'index.pl?Step=ExternalAuthBegin;Provider=' . $Self->_URLEncode( $Definition->{key} ),
            label     => $Definition->{label} || $Definition->{key},
            auto_redirect => $AutoRedirectKey && $Settings->{$AutoRedirectKey} ? 1 : 0,
            allow_local_login => $AllowLocalKey
                ? ( $Settings->{$AllowLocalKey} ? 1 : 0 )
                : 1,
        };
    }
    return \@Provider;
}

sub AuthorizationBegin {
    my ( $Self, %Param ) = @_;
    $Self->{LastError} = '';
    my $Key = $Param{Provider} || '';
    my $Definition = $Self->_ProviderGet($Key) || return $Self->_Error('Translate:ExternalAuthProviderInvalid');
    my $RedirectURI = $Self->_RedirectURI() || return;
    my $State    = $Self->_RandomToken(32) || return;
    my $Nonce    = $Self->_RandomToken(32) || return;
    my $Verifier = $Self->_RandomToken(48) || return;
    my $Challenge = $Self->_Base64URL( sha256($Verifier) );
    my $EncryptedNonce = $Self->{Security}->Encrypt( Value => $Nonce );
    my $EncryptedVerifier = $Self->{Security}->Encrypt( Value => $Verifier );
    return $Self->_Error( $Self->{Security}->Error() || 'Translate:ExternalAuthStateFailed' )
        if !$EncryptedNonce || !$EncryptedVerifier;

    $Self->{DB}->Do('DELETE FROM addon_auth_state WHERE expires_at < NOW()');
    my $Stored = $Self->{DB}->Do(
        'INSERT INTO addon_auth_state (
            state_hash, provider_key, nonce_encrypted, verifier_encrypted,
            return_location, expires_at
         ) VALUES (?, ?, ?, ?, "index.pl", DATE_ADD(NOW(), INTERVAL 10 MINUTE))',
        sha256_hex($State), $Key, $EncryptedNonce, $EncryptedVerifier,
    );
    return $Self->_Error( $Self->{DB}->Error() || 'Translate:ExternalAuthStateFailed' ) if !$Stored;

    my $Provider = $Self->_ProviderObject($Definition) || return;
    my $URL = eval {
        $Provider->AuthorizationURL(
            State         => $State,
            Nonce         => $Nonce,
            CodeChallenge => $Challenge,
            RedirectURI   => $RedirectURI,
            Settings      => $Definition->{Settings},
        );
    };
    return $Self->_Error( $@ || $Provider->Error() || 'Translate:ExternalAuthStartFailed' ) if !$URL;
    return $URL;
}

sub AuthorizationComplete {
    my ( $Self, %Param ) = @_;
    $Self->{LastError} = '';
    my $Request = $Param{Request} || {};
    my $State = $Self->_Scalar( $Request->{state} );
    my $Code  = $Self->_Scalar( $Request->{code} );
    if ( $Request->{error} ) {
        return $Self->_Error('Translate:ExternalAuthProviderRejected');
    }
    return $Self->_Error('Translate:ExternalAuthCallbackInvalid')
        if $State !~ m{\A[A-Za-z0-9_-]{40,200}\z} || $Code eq '' || length($Code) > 4096;
    return $Self->_Error('Translate:ExternalAuthStateFailed') if !$Self->{DB}->BeginWork();
    my $Row = $Self->{DB}->SelectRow(
        'SELECT * FROM addon_auth_state
         WHERE state_hash = ? AND expires_at >= NOW() LIMIT 1 FOR UPDATE',
        sha256_hex($State),
    );
    if (!$Row) {
        $Self->{DB}->Rollback();
        return $Self->_Error('Translate:ExternalAuthStateInvalid');
    }
    my $Deleted = $Self->{DB}->Do('DELETE FROM addon_auth_state WHERE id = ?', $Row->{id});
    if ( !$Deleted || !$Self->{DB}->Commit() ) {
        $Self->{DB}->Rollback();
        return $Self->_Error('Translate:ExternalAuthStateFailed');
    }

    my $Definition = $Self->_ProviderGet( $Row->{provider_key} )
        || return $Self->_Error('Translate:ExternalAuthProviderInvalid');
    my $Nonce = $Self->{Security}->Decrypt( Value => $Row->{nonce_encrypted} );
    my $Verifier = $Self->{Security}->Decrypt( Value => $Row->{verifier_encrypted} );
    return $Self->_Error( $Self->{Security}->Error() || 'Translate:ExternalAuthStateInvalid' )
        if !$Nonce || !$Verifier;
    my $Provider = $Self->_ProviderObject($Definition) || return;
    my $User = eval {
        $Provider->Authenticate(
            Code        => $Code,
            Nonce       => $Nonce,
            CodeVerifier => $Verifier,
            RedirectURI => $Self->_RedirectURI(),
            Settings    => $Definition->{Settings},
        );
    };
    return $Self->_Error( $@ || $Provider->Error() || 'Translate:ExternalAuthLoginFailed' ) if !$User;
    return $User;
}

sub _ProviderGet {
    my ( $Self, $Key ) = @_;
    for my $Provider ( @{ $Self->ProviderList() } ) {
        return $Provider if ( $Provider->{key} || '' ) eq $Key;
    }
    return;
}

sub _ProviderObject {
    my ( $Self, $Definition ) = @_;
    my $Class = $Definition->{class} || '';
    return $Self->_Error('Translate:ExternalAuthProviderInvalid')
        if $Class !~ m{\AQisutu::Addon::[A-Za-z0-9_:]+\z};
    my $Loaded = eval "require $Class; 1;";
    return $Self->_Error( $@ || 'Translate:ExternalAuthProviderLoadFailed' ) if !$Loaded;
    my $Object = eval { $Class->new( Config => $Self->{Config}, DB => $Self->{DB} ) };
    return $Self->_Error( $@ || 'Translate:ExternalAuthProviderLoadFailed' ) if !$Object;
    return $Object;
}

sub _RedirectURI {
    my ($Self) = @_;
    my $BaseURL = QisutuSystemSetting->new( Config => $Self->{Config}, DB => $Self->{DB} )->BaseURL() || '';
    $BaseURL =~ s{\s+}{}g;
    $BaseURL =~ s{/+\z}{};
    return $Self->_Error('Translate:ExternalAuthBaseURLMissing')
        if $BaseURL !~ m{\Ahttps://[^\s/?#]+(?:/[^\s?#]*)?\z}i;
    return $BaseURL . '/index.pl?Step=ExternalAuthCallback';
}

sub _RandomToken {
    my ( $Self, $Length ) = @_;
    open my $Handle, '<:raw', '/dev/urandom'
        or return $Self->_Error('Translate:ExternalAuthRandomFailed');
    my $Data = '';
    my $Read = read $Handle, $Data, $Length;
    close $Handle;
    return $Self->_Error('Translate:ExternalAuthRandomFailed') if !$Read || $Read != $Length;
    return $Self->_Base64URL($Data);
}

sub _Base64URL {
    my ( $Self, $Value ) = @_;
    my $Encoded = encode_base64( $Value, '' );
    $Encoded =~ tr{+/}{-_};
    $Encoded =~ s{=+\z}{};
    return $Encoded;
}

sub _Scalar {
    my ( $Self, $Value ) = @_;
    $Value = $Value->[0] if ref $Value eq 'ARRAY';
    return ref $Value ? '' : ( defined $Value ? "$Value" : '' );
}

sub _URLEncode {
    my ( $Self, $Value ) = @_;
    $Value =~ s{([^A-Za-z0-9_\-\.])}{sprintf('%%%02X', ord($1))}eg;
    return $Value;
}

sub _Error {
    my ( $Self, $Message ) = @_;
    $Self->{LastError} = $Message || 'external authentication failed';
    return;
}

1;
