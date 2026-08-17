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

use Encode qw(decode);
use File::Spec;
use FindBin;
use Test::More;

use lib File::Spec->catdir( $FindBin::Bin, '..', 'core', 'config' );
use lib File::Spec->catdir( $FindBin::Bin, '..', 'core', 'system' );
use lib File::Spec->catdir( $FindBin::Bin, '..', 'core', 'output' );
use lib File::Spec->catdir( $FindBin::Bin, '..', 'core', 'module' );

use Login;
use QisutuOutput;

{
    package Local::LoginSecurity;
    sub new { return bless {}, shift }
    sub PublicCSRFTokenCreate { return 'public-csrf-token' }
}

{
    package Local::LoginExternalAuth;
    sub new { return bless { Error => '', BeginCalls => [] }, shift }
    sub ProviderList {
        return [
            {
                begin_url        => 'index.pl?Step=ExternalAuthBegin;Provider=entra-agent',
                label            => 'Translate:TestAgentEntraButton',
                auto_redirect    => 0,
                allow_local_login => 1,
            },
            {
                begin_url        => 'index.pl?Step=ExternalAuthBegin;Provider=entra-customer-login',
                label            => 'Translate:TestCustomerEntraButton',
                auto_redirect    => 0,
                allow_local_login => 1,
            },
        ];
    }
    sub AuthorizationBegin {
        my ( $Self, %Param ) = @_;
        push @{ $Self->{BeginCalls} }, { %Param };
        return 'https://login.microsoftonline.com/example/oauth2/v2.0/authorize';
    }
    sub AuthorizationComplete {
        my ($Self) = @_;
        $Self->{Error} = 'Translate:TestEntraError';
        return;
    }
    sub Error { return shift->{Error} || '' }
}

{
    package Local::LoginTwoFactor;
    sub new { return bless {}, shift }
    sub Required { return 0 }
}

{
    package Local::LoginPasswordReset;
    sub new { return bless {}, shift }
}

{
    package Local::LoginCustomerRegistration;
    sub new { return bless { Requests => [] }, shift }
    sub RequestCreate {
        my ( $Self, %Param ) = @_;
        push @{ $Self->{Requests} }, { %Param };
        return { Success => 1 };
    }
}

my $Root = File::Spec->rel2abs( File::Spec->catdir( $FindBin::Bin, '..' ) );
my $ExternalAuth = Local::LoginExternalAuth->new();
my $CustomerRegistration = Local::LoginCustomerRegistration->new();
my $Config = {
    RootPath => $Root,
    Paths    => {
        Output    => File::Spec->catdir( $Root, 'core', 'output' ),
        Language  => File::Spec->catdir( $Root, 'core', 'language' ),
        StaticURL => '/static',
    },
    Language => { Default => 'de' },
    System   => { Name => 'Qisutu' },
    Session  => {
        CookieName     => 'QisutuSession',
        LifetimeSeconds => 3600,
    },
    AddonRuntime => {
        LanguagePaths => [
            File::Spec->catdir( $Root, 't', 'data', 'login-addon-languages' ),
        ],
    },
};
my $Output = QisutuOutput->new( Config => $Config );
my $Login = Login->new(
    Config               => $Config,
    Output               => $Output,
    Security             => Local::LoginSecurity->new(),
    PasswordReset        => Local::LoginPasswordReset->new(),
    CustomerRegistration => $CustomerRegistration,
    TwoFactor            => Local::LoginTwoFactor->new(),
    ExternalAuth         => $ExternalAuth,
);

my $French = $Login->Run(
    BrowserLanguage => 'fr-FR,fr;q=0.9,en;q=0.8',
    FormAction      => 'index.pl',
);
$French = decode( 'UTF-8', $French );
like( $French, qr{<html lang="fr">}, 'the browser language selects French on the first login visit' );
like( $French, qr{Veuillez vous connecter[.]}, 'the login text follows the browser language' );
like( $French, qr{Se connecter comme agent avec Microsoft Entra ID}, 'the agent Entra ID button follows the selected language' );
like( $French, qr{Se connecter comme contact avec Microsoft Entra ID}, 'the contact Entra ID button follows the selected language' );
like( $French, qr{<option value="fr" selected>Français</option>}, 'the language dropdown marks French as selected' );
like( $French, qr{class="qisutu-login-language-icon"}, 'the language dropdown displays a globe icon' );
unlike( $French, qr{<label for="qisutu-login-language">}, 'the language dropdown has no visible language label' );
unlike( $French, qr{<button type="submit">OK</button>}, 'the automatically changing language dropdown has no OK button' );
like( $French, qr{name="Language" value="fr"}, 'the local login form preserves the selected language' );
like( $French, qr{Provider=entra-agent;Language=fr}, 'the agent Entra ID link preserves the selected language' );
like( $French, qr{Provider=entra-customer-login;Language=fr}, 'the contact Entra ID link preserves the selected language' );
like( $French, qr{Set-Cookie: QisutuPublicLanguage=fr;}, 'the selected language is stored for the Entra ID round trip' );

my $English = $Login->Run(
    Language            => 'en',
    LoginLanguageCookie => 'fr',
    BrowserLanguage     => 'de-DE,de;q=0.9',
    FormAction          => 'index.pl',
);
like( $English, qr{<html lang="en">}, 'an explicit dropdown selection takes precedence' );
like( $English, qr{Please sign in[.]}, 'the explicit English selection renders the English login' );
like( $English, qr{Sign in as an agent with Microsoft Entra ID}, 'the agent Entra ID button changes to English' );
like( $English, qr{Sign in as a contact with Microsoft Entra ID}, 'the contact Entra ID button changes to English' );

my $CookieLanguage = $Login->Run(
    LoginLanguageCookie => 'nl',
    BrowserLanguage     => 'fr-FR,fr;q=0.9',
    FormAction          => 'index.pl',
);
like( $CookieLanguage, qr{<html lang="nl">}, 'the remembered anonymous language takes precedence over the browser language' );
like( $CookieLanguage, qr{Meld u aan[.]}, 'the remembered Dutch language controls the login text' );

my $EnglishFallback = $Login->Run(
    BrowserLanguage => 'ja-JP,ja;q=0.9',
    FormAction      => 'index.pl',
);
like( $EnglishFallback, qr{<html lang="en">}, 'unsupported browser languages fall back to English' );
unlike( $EnglishFallback, qr{Bitte melden Sie sich an[.]}, 'the configured German system language does not control the anonymous login' );

my $EntraRedirect = $Login->Run(
    Step         => 'ExternalAuthBegin',
    Provider     => 'entra-agent',
    Language     => 'fr',
    SecureCookie => 1,
    FormAction   => 'index.pl',
);
like( $EntraRedirect, qr{Location: https://login[.]microsoftonline[.]com/}, 'the Entra ID button starts the external login' );
like( $EntraRedirect, qr{Set-Cookie: QisutuPublicLanguage=fr;.*Secure}, 'the Entra ID redirect stores the selected language securely' );

my $EntraError = $Login->Run(
    Step                => 'ExternalAuthCallback',
    LoginLanguageCookie => 'fr',
    FormAction          => 'index.pl',
);
$EntraError = decode( 'UTF-8', $EntraError );
like( $EntraError, qr{La connexion Microsoft Entra ID a échoué[.]}, 'an Entra ID callback error uses the language selected before the redirect' );

my $Registration = $Login->Run(
    Step        => 'CustomerRegistrationSubmit',
    Language    => 'it',
    Firstname   => 'Ada',
    Lastname    => 'Lovelace',
    Email       => 'ada@example.test',
    Company     => 'Example',
    FormAction  => 'index.pl',
);
is( $CustomerRegistration->{Requests}->[-1]->{Language}, 'it', 'customer registration stores the anonymously selected language' );
like( $Registration, qr{<html lang="it">}, 'the registration confirmation remains in the selected language' );

done_testing();
