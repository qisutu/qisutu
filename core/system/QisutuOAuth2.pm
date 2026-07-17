# Qisutu - Open Source Ticket System
# Copyright (C) 2010-2022 OFORK, https://o-fork.de/
# Copyright (C) 2026 Franziska Steps
# Qisutu - Kim-KI, https://qisutu.de
#
# OAuth2 mail-account handling in this file is based on the AGPLv3 OFORK
# OAuth2 module supplied for the Qisutu integration.
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
# SPDX-FileCopyrightText: 2010-2022 OFORK
# SPDX-FileCopyrightText: 2026 Franziska Steps
# SPDX-License-Identifier: AGPL-3.0-or-later

package QisutuOAuth2;

use strict;
use warnings;
use utf8;

use Digest::SHA qw(sha256_hex);
use HTTP::Tiny;
use JSON::PP;
use QisutuSystemSetting;

sub new {
    my ( $Class, %Param ) = @_;

    my $Self = {
        Config     => $Param{Config},
        DB         => $Param{DB},
        HTTPClient => $Param{HTTPClient},
        LastError  => '',
    };

    bless $Self, $Class;

    return $Self;
}

sub ProviderNormalize {
    my ( $Self, $Value ) = @_;

    $Value = lc( $Value || '' );
    $Value =~ s{[^a-z0-9]}{}g;

    return 'microsoft' if $Value =~ m{\A(?:microsoft|microsoft365|azure|office365)\z};
    return 'google'    if $Value =~ m{\A(?:google|googleworkspace|googleworkspacegmail|gmail)\z};

    return '';
}

sub ProviderDefinition {
    my ( $Self, %Param ) = @_;

    my $Account  = $Param{Account} || {};
    my $Provider = $Self->ProviderNormalize( $Param{Provider} || $Account->{oauth_provider} );

    if ( $Provider eq 'microsoft' ) {
        my $Tenant = $Account->{oauth_tenant_id} || 'common';
        $Tenant =~ s{\A\s+|\s+\z}{}g;
        $Tenant = 'common' if $Tenant !~ m{\A[A-Za-z0-9.-]+\z};

        return {
            Key          => 'microsoft',
            Name         => 'Microsoft 365',
            AuthURL      => 'https://login.microsoftonline.com/' . $Tenant . '/oauth2/v2.0/authorize',
            TokenURL     => 'https://login.microsoftonline.com/' . $Tenant . '/oauth2/v2.0/token',
            IMAPHost     => 'outlook.office365.com',
            IMAPSecurity => 'imaps',
            IMAPPort     => 993,
            Scope        => 'offline_access https://outlook.office.com/IMAP.AccessAsUser.All',
        };
    }

    if ( $Provider eq 'google' ) {
        return {
            Key          => 'google',
            Name         => 'Google Workspace / Gmail',
            AuthURL      => 'https://accounts.google.com/o/oauth2/v2/auth',
            TokenURL     => 'https://oauth2.googleapis.com/token',
            IMAPHost     => 'imap.gmail.com',
            IMAPSecurity => 'imaps',
            IMAPPort     => 993,
            Scope        => 'https://mail.google.com/',
        };
    }

    return;
}

sub RedirectURI {
    my ($Self) = @_;

    my $BaseURL = QisutuSystemSetting->new(
        Config => $Self->{Config},
        DB     => $Self->{DB},
    )->BaseURL() || '';

    $BaseURL =~ s{\A\s+|\s+\z}{}g;
    $BaseURL =~ s{/+\z}{};

    if ( !$BaseURL || $BaseURL !~ m{\Ahttps?://[^\s/?#]+(?:/[^\s?#]*)?\z}i ) {
        $Self->{LastError} = 'Translate:AdminOAuthBaseURLMissing';
        return '';
    }

    return $BaseURL . '/index.pl?Page=AdminPostmasterIMAPAccounts&Action=OAuthCallback';
}

sub AuthorizationBegin {
    my ( $Self, %Param ) = @_;

    my $Account         = $Param{Account} || {};
    my $AccountID       = $Account->{id} || 0;
    my $UserID          = $Param{UserID} || 0;
    my $RequestedActive = $Param{RequestedActive} ? 1 : 0;
    my $ReturnPage      = $Self->_ReturnPageClean( $Param{ReturnPage}, $Account->{oauth_provider} );
    my $Provider        = $Self->ProviderDefinition( Account => $Account );
    my $RedirectURI     = $Self->RedirectURI();

    if ( !$AccountID || $AccountID !~ m{\A\d+\z} || !$UserID || $UserID !~ m{\A\d+\z} ) {
        $Self->{LastError} = 'Translate:AdminOAuthAccountMissing';
        return;
    }
    if ( !$Provider ) {
        $Self->{LastError} = 'Translate:AdminOAuthProviderInvalid';
        return;
    }
    if ( !$RedirectURI ) {
        return;
    }

    my $ClientID     = $Account->{oauth_client_id} || '';
    my $ClientSecret = $Account->{oauth_client_secret} || '';
    my $Login        = $Account->{imap_username} || $Account->{email} || '';
    my $Scope        = $Account->{oauth_scope} || $Provider->{Scope};

    if ( !$ClientID || !$ClientSecret || !$Login || !$Scope ) {
        $Self->{LastError} = 'Translate:AdminOAuthConfigurationIncomplete';
        return;
    }

    my $State = $Self->_RandomToken();
    return if !$State;

    my $StateHash = sha256_hex($State);

    $Self->{DB}->Do('DELETE FROM oauth2_authorization_state WHERE expires_at < NOW()');
    $Self->{DB}->Do(
        'DELETE FROM oauth2_authorization_state WHERE account_id = ? AND user_account_id = ?',
        $AccountID,
        $UserID,
    );

    my $Stored = $Self->{DB}->Do(
        'INSERT INTO oauth2_authorization_state (
            state_hash,
            account_id,
            user_account_id,
            provider,
            requested_active,
            return_page,
            expires_at
         ) VALUES (?, ?, ?, ?, ?, ?, DATE_ADD(NOW(), INTERVAL 15 MINUTE))',
        $StateHash,
        $AccountID,
        $UserID,
        $Provider->{Key},
        $RequestedActive,
        $ReturnPage,
    );

    if ( !$Stored ) {
        $Self->{LastError} = $Self->{DB}->Error() || 'Translate:AdminOAuthStateStoreFailed';
        return;
    }

    my @Query = (
        [ client_id     => $ClientID ],
        [ response_type => 'code' ],
        [ redirect_uri  => $RedirectURI ],
        [ scope         => $Scope ],
        [ state         => $State ],
        [ login_hint    => $Login ],
    );

    if ( $Provider->{Key} eq 'microsoft' ) {
        push @Query,
            [ response_mode => 'query' ],
            [ prompt        => 'select_account' ];
    }
    elsif ( $Provider->{Key} eq 'google' ) {
        push @Query,
            [ access_type            => 'offline' ],
            [ prompt                 => 'consent' ],
            [ include_granted_scopes => 'true' ];
    }

    return $Provider->{AuthURL} . '?' . $Self->_FormEncode(\@Query);
}

sub AuthorizationComplete {
    my ( $Self, %Param ) = @_;

    my $Request = $Param{Request} || {};
    my $UserID  = $Param{UserID} || 0;
    my $State   = $Self->_Scalar( $Request->{state} );

    if ( !$UserID || $UserID !~ m{\A\d+\z} || $State !~ m{\A[0-9a-f]{64}\z} ) {
        $Self->{LastError} = 'Translate:AdminOAuthStateInvalid';
        return;
    }

    my $StateHash = sha256_hex($State);
    my $StateRow;

    if ( !$Self->{DB}->BeginWork() ) {
        $Self->{LastError} = $Self->{DB}->Error() || 'Translate:AdminOAuthStateInvalid';
        return;
    }

    $StateRow = $Self->{DB}->SelectRow(
        'SELECT *
         FROM oauth2_authorization_state
         WHERE state_hash = ?
           AND user_account_id = ?
           AND expires_at >= NOW()
         LIMIT 1
         FOR UPDATE',
        $StateHash,
        $UserID,
    );

    if ( !$StateRow ) {
        $Self->{DB}->Rollback();
        $Self->{LastError} = 'Translate:AdminOAuthStateInvalid';
        return;
    }

    if ( !$Self->{DB}->Do( 'DELETE FROM oauth2_authorization_state WHERE id = ?', $StateRow->{id} ) ) {
        $Self->{DB}->Rollback();
        $Self->{LastError} = $Self->{DB}->Error() || 'Translate:AdminOAuthStateInvalid';
        return;
    }

    if ( !$Self->{DB}->Commit() ) {
        $Self->{LastError} = $Self->{DB}->Error() || 'Translate:AdminOAuthStateInvalid';
        return;
    }

    my $ResultBase = {
        AccountID      => $StateRow->{account_id},
        Provider       => $StateRow->{provider},
        RequestedActive => $StateRow->{requested_active} ? 1 : 0,
        ReturnPage     => $Self->_ReturnPageClean( $StateRow->{return_page}, $StateRow->{provider} ),
    };

    my $ProviderError = $Self->_Scalar( $Request->{error} );
    if ($ProviderError) {
        my $Description = $Self->_Scalar( $Request->{error_description} );
        my $Message = $Description || $ProviderError;
        $Message =~ s{[\r\n]+}{ }g;
        $Message = substr( $Message, 0, 1000 );
        $Self->_AccountStatusSet(
            AccountID => $StateRow->{account_id},
            Status    => 'error',
            Message   => $Message,
            UserID    => $UserID,
        );
        $Self->{LastError} = $Message || 'Translate:AdminOAuthAuthorizationDenied';
        return { %{$ResultBase}, Success => 0, Message => $Self->{LastError} };
    }

    my $Code = $Self->_Scalar( $Request->{code} );
    if ( !$Code ) {
        $Self->{LastError} = 'Translate:AdminOAuthAuthorizationCodeMissing';
        $Self->_AccountStatusSet(
            AccountID => $StateRow->{account_id},
            Status    => 'error',
            Message   => $Self->{LastError},
            UserID    => $UserID,
        );
        return { %{$ResultBase}, Success => 0, Message => $Self->{LastError} };
    }

    my $Account = $Self->_AccountGet( AccountID => $StateRow->{account_id} );
    if ( !$Account ) {
        $Self->{LastError} = 'Translate:AdminOAuthAccountMissing';
        return { %{$ResultBase}, Success => 0, Message => $Self->{LastError} };
    }

    my $Provider = $Self->ProviderDefinition( Account => $Account );
    if ( !$Provider || $Provider->{Key} ne $StateRow->{provider} ) {
        $Self->{LastError} = 'Translate:AdminOAuthProviderInvalid';
        return { %{$ResultBase}, Success => 0, Message => $Self->{LastError} };
    }

    my $Token = $Self->_TokenRequest(
        Account     => $Account,
        Provider    => $Provider,
        GrantType   => 'authorization_code',
        Code        => $Code,
        RedirectURI => $Self->RedirectURI(),
    );

    if ( !$Token ) {
        $Self->_AccountStatusSet(
            AccountID => $StateRow->{account_id},
            Status    => 'error',
            Message   => $Self->{LastError},
            UserID    => $UserID,
        );
        return { %{$ResultBase}, Success => 0, Message => $Self->{LastError} };
    }

    my $RefreshToken = $Token->{refresh_token} || $Account->{oauth_refresh_token} || '';
    if ( !$RefreshToken ) {
        $Self->{LastError} = 'Translate:AdminOAuthRefreshTokenMissing';
        $Self->_AccountStatusSet(
            AccountID => $StateRow->{account_id},
            Status    => 'error',
            Message   => $Self->{LastError},
            UserID    => $UserID,
        );
        return { %{$ResultBase}, Success => 0, Message => $Self->{LastError} };
    }

    if ( !$Self->_TokenStore(
            AccountID   => $StateRow->{account_id},
            AccessToken => $Token->{access_token},
            RefreshToken => $RefreshToken,
            ExpiresIn   => $Token->{expires_in},
            UserID      => $UserID,
        )
        )
    {
        return { %{$ResultBase}, Success => 0, Message => $Self->{LastError} };
    }

    return {
        %{$ResultBase},
        Success => 1,
        Message => 'Translate:AdminOAuthAuthorizationSuccessful',
    };
}

sub AccessTokenGet {
    my ( $Self, %Param ) = @_;

    my $Account   = $Param{Account} || {};
    my $AccountID = $Account->{id} || 0;

    if ( !$AccountID || $AccountID !~ m{\A\d+\z} ) {
        $Self->{LastError} = 'Translate:AdminOAuthAccountMissing';
        return;
    }

    my $Stored = $Self->_AccountGet( AccountID => $AccountID );
    return if !$Stored;

    if (
        ( $Stored->{oauth_access_token} || '' ) ne ''
        && ( $Stored->{oauth_token_expires_epoch} || 0 ) > time() + 120
        )
    {
        return $Stored->{oauth_access_token};
    }

    my $RefreshToken = $Stored->{oauth_refresh_token} || '';
    if ( !$RefreshToken ) {
        $Self->{LastError} = 'Translate:AdminOAuthRefreshTokenMissing';
        return;
    }

    my $Provider = $Self->ProviderDefinition( Account => $Stored );
    if ( !$Provider ) {
        $Self->{LastError} = 'Translate:AdminOAuthProviderInvalid';
        return;
    }

    my $Token = $Self->_TokenRequest(
        Account      => $Stored,
        Provider     => $Provider,
        GrantType    => 'refresh_token',
        RefreshToken => $RefreshToken,
    );
    return if !$Token;

    my $NewRefreshToken = $Token->{refresh_token} || $RefreshToken;

    return if !$Self->_TokenStore(
        AccountID    => $AccountID,
        AccessToken  => $Token->{access_token},
        RefreshToken => $NewRefreshToken,
        ExpiresIn    => $Token->{expires_in},
        UserID       => $Stored->{changed_by_user_id} || 1,
    );

    return $Token->{access_token};
}

sub _TokenRequest {
    my ( $Self, %Param ) = @_;

    my $Account      = $Param{Account} || {};
    my $Provider     = $Param{Provider} || {};
    my $GrantType    = $Param{GrantType} || '';
    my $ClientID     = $Account->{oauth_client_id} || '';
    my $ClientSecret = $Account->{oauth_client_secret} || '';
    my $Scope        = $Account->{oauth_scope} || $Provider->{Scope} || '';

    if ( !$Provider->{TokenURL} || !$ClientID || !$ClientSecret || !$GrantType ) {
        $Self->{LastError} = 'Translate:AdminOAuthConfigurationIncomplete';
        return;
    }

    my @Form = (
        [ client_id     => $ClientID ],
        [ client_secret => $ClientSecret ],
        [ grant_type    => $GrantType ],
    );

    if ( $GrantType eq 'authorization_code' ) {
        my $Code        = $Param{Code} || '';
        my $RedirectURI = $Param{RedirectURI} || '';
        if ( !$Code || !$RedirectURI ) {
            $Self->{LastError} = 'Translate:AdminOAuthAuthorizationCodeMissing';
            return;
        }
        push @Form,
            [ code         => $Code ],
            [ redirect_uri => $RedirectURI ];
        push @Form, [ scope => $Scope ] if $Scope;
    }
    elsif ( $GrantType eq 'refresh_token' ) {
        my $RefreshToken = $Param{RefreshToken} || '';
        if ( !$RefreshToken ) {
            $Self->{LastError} = 'Translate:AdminOAuthRefreshTokenMissing';
            return;
        }
        push @Form, [ refresh_token => $RefreshToken ];
        push @Form, [ scope => $Scope ] if $Scope && ( $Provider->{Key} || '' ) eq 'microsoft';
    }
    else {
        $Self->{LastError} = 'Translate:AdminOAuthGrantInvalid';
        return;
    }

    my $HTTP = $Self->{HTTPClient} || HTTP::Tiny->new(
        agent      => 'Qisutu-OAuth2/1.0',
        timeout    => 25,
        verify_SSL => 1,
    );

    my $Response = eval {
        $HTTP->request(
            'POST',
            $Provider->{TokenURL},
            {
                headers => {
                    'content-type' => 'application/x-www-form-urlencoded',
                    accept         => 'application/json',
                },
                content => $Self->_FormEncode(\@Form),
            },
        );
    };

    if ( !$Response || ref $Response ne 'HASH' ) {
        $Self->{LastError} = 'Translate:AdminOAuthTokenConnectionFailed';
        return;
    }

    my $Data = eval { JSON::PP->new->utf8(1)->decode( $Response->{content} || '{}' ) };
    $Data = {} if !$Data || ref $Data ne 'HASH';

    if ( !$Response->{success} ) {
        my $Message = $Data->{error_description} || $Data->{error} || $Response->{reason} || 'OAuth2 token request failed';
        $Message =~ s{[\r\n]+}{ }g;
        $Self->{LastError} = substr( $Message, 0, 1000 );
        return;
    }

    if ( !$Data->{access_token} ) {
        $Self->{LastError} = 'Translate:AdminOAuthAccessTokenMissing';
        return;
    }

    my $ExpiresIn = $Data->{expires_in};
    $ExpiresIn = 3600 if !defined $ExpiresIn || $ExpiresIn !~ m{\A\d+\z};
    $ExpiresIn = 60 if $ExpiresIn < 60;
    $ExpiresIn = 86400 if $ExpiresIn > 86400;
    $Data->{expires_in} = $ExpiresIn;

    return $Data;
}

sub _TokenStore {
    my ( $Self, %Param ) = @_;

    my $ExpiresAt = time() + ( $Param{ExpiresIn} || 3600 );
    my $Stored = $Self->{DB}->Do(
        'UPDATE postmaster_imap_account
         SET oauth_access_token = ?,
             oauth_refresh_token = ?,
             oauth_token_expires_at = FROM_UNIXTIME(?),
             last_check_at = NOW(),
             last_check_status = ?,
             last_check_message = ?,
             changed_by_user_id = ?
         WHERE id = ?',
        $Param{AccessToken} || '',
        $Param{RefreshToken} || '',
        $ExpiresAt,
        'authorized',
        'Translate:AdminOAuthAuthorizationSuccessful',
        $Param{UserID} || 1,
        $Param{AccountID},
    );

    if ( !$Stored ) {
        $Self->{LastError} = $Self->{DB}->Error() || 'Translate:AdminOAuthTokenStoreFailed';
        return;
    }

    return 1;
}

sub _AccountGet {
    my ( $Self, %Param ) = @_;

    my $Account = $Self->{DB}->SelectRow(
        'SELECT *, UNIX_TIMESTAMP(oauth_token_expires_at) AS oauth_token_expires_epoch
         FROM postmaster_imap_account
         WHERE id = ?
         LIMIT 1',
        $Param{AccountID},
    );

    if ( !$Account ) {
        $Self->{LastError} = 'Translate:AdminOAuthAccountMissing';
        return;
    }

    return $Account;
}

sub _AccountStatusSet {
    my ( $Self, %Param ) = @_;

    return $Self->{DB}->Do(
        'UPDATE postmaster_imap_account
         SET active = 0,
             last_check_at = NOW(),
             last_check_status = ?,
             last_check_message = ?,
             changed_by_user_id = ?
         WHERE id = ?',
        $Param{Status} || 'error',
        $Param{Message} || '',
        $Param{UserID} || 1,
        $Param{AccountID},
    );
}

sub _RandomToken {
    my ($Self) = @_;

    my $Bytes = '';
    my $FH;

    if ( open $FH, '<', '/dev/urandom' ) {
        binmode $FH;
        my $Read = read $FH, $Bytes, 32;
        close $FH;
        if ( !$Read || $Read != 32 ) {
            $Bytes = '';
        }
    }

    if ( !$Bytes ) {
        $Self->{LastError} = 'Translate:AdminOAuthRandomSourceFailed';
        return '';
    }

    return unpack 'H*', $Bytes;
}

sub _FormEncode {
    my ( $Self, $Pairs ) = @_;

    return join '&', map {
        $Self->_URLEncode( $_->[0] ) . '=' . $Self->_URLEncode( $_->[1] )
    } @{ $Pairs || [] };
}

sub _URLEncode {
    my ( $Self, $Value ) = @_;

    $Value = '' if !defined $Value;
    utf8::encode($Value) if utf8::is_utf8($Value);
    $Value =~ s{([^A-Za-z0-9_.~-])}{sprintf '%%%02X', ord($1)}eg;

    return $Value;
}

sub _ReturnPageClean {
    my ( $Self, $Page, $Provider ) = @_;

    my %Allowed = map { $_ => 1 } qw(
        AdminPostmasterIMAPAccount
        AdminPostmasterMicrosoft365
        AdminPostmasterGoogleMail
    );

    return $Page if $Allowed{$Page || ''};

    my $Key = $Self->ProviderNormalize($Provider);
    return 'AdminPostmasterMicrosoft365' if $Key eq 'microsoft';
    return 'AdminPostmasterGoogleMail'    if $Key eq 'google';
    return 'AdminPostmasterIMAPAccount';
}

sub _Scalar {
    my ( $Self, $Value ) = @_;

    return '' if !defined $Value;
    return defined $Value->[0] ? $Value->[0] : '' if ref $Value eq 'ARRAY';
    return '' if ref $Value;
    return $Value;
}

sub Error {
    my ($Self) = @_;

    return $Self->{LastError};
}

1;
