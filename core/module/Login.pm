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

package Login;

use strict;
use warnings;
use utf8;

use File::Spec;

use QisutuPasswordReset;
use QisutuCustomerRegistration;
use QisutuTwoFactor;
use QisutuAuthProvider;

sub new {
    my ( $Class, %Param ) = @_;

    my $Self = {
        Config        => $Param{Config},
        Output        => $Param{Output},
        DB            => $Param{DB},
        Auth          => $Param{Auth},
        Session       => $Param{Session},
        Security      => $Param{Security},
        PasswordReset        => $Param{PasswordReset},
        CustomerRegistration  => $Param{CustomerRegistration},
        TwoFactor             => $Param{TwoFactor},
        ExternalAuth          => $Param{ExternalAuth},
        LastError             => '',
    };

    if ( !$Self->{PasswordReset} ) {
        $Self->{PasswordReset} = QisutuPasswordReset->new(
            Config => $Self->{Config},
            DB     => $Self->{DB},
        );
    }

    if ( !$Self->{CustomerRegistration} ) {
        $Self->{CustomerRegistration} = QisutuCustomerRegistration->new(
            Config => $Self->{Config},
            DB     => $Self->{DB},
        );
    }

    if ( !$Self->{TwoFactor} ) {
        $Self->{TwoFactor} = QisutuTwoFactor->new(
            Config => $Self->{Config},
            DB     => $Self->{DB},
        );
    }


    if ( !$Self->{ExternalAuth} ) {
        $Self->{ExternalAuth} = QisutuAuthProvider->new(
            Config   => $Self->{Config},
            DB       => $Self->{DB},
            Security => $Self->{Security},
        );
    }

    bless $Self, $Class;

    return $Self;
}

sub Run {
    my ( $Self, %Param ) = @_;

    my $Step = $Param{Step} || '';

    $Self->{PublicLanguage} = $Self->_LanguageClean( $Param{Language} )
        || $Self->_LanguageClean( $Param{LoginLanguageCookie} )
        || $Self->_BrowserLanguage( $Param{BrowserLanguage} )
        || 'en';
    $Self->{PublicLanguageSecureCookie} = $Param{SecureCookie} ? 1 : 0;

    if ( $Step eq 'Login' ) {
        return $Self->_LoginSubmit(%Param);
    }

    if ( $Step eq 'PasswordForgot' ) {
        return $Self->_PasswordForgotShow(%Param);
    }

    if ( $Step eq 'PasswordForgotSubmit' ) {
        return $Self->_PasswordForgotSubmit(%Param);
    }

    if ( $Step eq 'PasswordReset' ) {
        return $Self->_PasswordResetShow(%Param);
    }

    if ( $Step eq 'PasswordResetSubmit' ) {
        return $Self->_PasswordResetSubmit(%Param);
    }

    if ( $Step eq 'CustomerRegistration' ) {
        return $Self->_CustomerRegistrationShow(%Param);
    }

    if ( $Step eq 'CustomerRegistrationSubmit' ) {
        return $Self->_CustomerRegistrationSubmit(%Param);
    }

    if ( $Step eq 'CustomerRegistrationPassword' ) {
        return $Self->_CustomerRegistrationPasswordShow(%Param);
    }

    if ( $Step eq 'CustomerRegistrationPasswordSubmit' ) {
        return $Self->_CustomerRegistrationPasswordSubmit(%Param);
    }

    if ( $Step eq 'TwoFactorVerify' ) {
        return $Self->_TwoFactorVerify(%Param);
    }

    if ( $Step eq 'ExternalAuthBegin' ) {
        return $Self->_ExternalAuthBegin(%Param);
    }

    if ( $Step eq 'ExternalAuthCallback' ) {
        return $Self->_ExternalAuthCallback(%Param);
    }

    return $Self->_LoginShow(%Param);
}

sub _LoginShow {
    my ( $Self, %Param ) = @_;

    my $AccountType = $Param{AccountType} || 'agent';
    my $ProviderSource = $Self->{ExternalAuth}
        ? $Self->{ExternalAuth}->ProviderList( AccountType => 'agent' )
        : [];
    my $Language = $Self->_PublicLanguage();
    my $Providers = [ map {
        my %Provider = %{$_};
        if ( $Provider{begin_url} ) {
            $Provider{begin_url} .= ';Language=' . $Language;
        }
        \%Provider;
    } @{$ProviderSource} ];
    my @AutoRedirect = grep { $_->{auto_redirect} } @{$Providers};
    if ( !$Param{ErrorMessage}
        && ( $Param{Step} || '' ) ne 'LocalLogin'
        && $AccountType eq 'agent'
        && @AutoRedirect == 1 ) {
        return $Self->{Output}->Redirect(
            Location => $AutoRedirect[0]->{begin_url},
            Cookie   => $Self->_PublicLanguageCookie(),
        );
    }
    my $ShowLocalAgentLogin = !grep { !$_->{allow_local_login} } @{$Providers};
    $AccountType = 'customer' if !$ShowLocalAgentLogin && $AccountType eq 'agent';
    return $Self->_RenderPublicPage(
        Template => 'Login.tt',
        Data     => $Self->_TemplateData(
            PageTitle    => 'Translate:PageLoginTitle',
            ErrorMessage => $Param{ErrorMessage} || '',
            LoginValue   => $Param{LoginValue}   || '',
            AccountType  => $AccountType,
            FormAction   => $Param{FormAction}   || 'index.pl',
            ExternalAuthProviders => $Providers,
            HasExternalAuth       => @{$Providers} ? 1 : 0,
            ShowLocalAgentLogin   => $ShowLocalAgentLogin,
        ),
    );
}

sub _ExternalAuthBegin {
    my ( $Self, %Param ) = @_;
    my $URL = $Self->{ExternalAuth}->AuthorizationBegin(
        Provider => $Param{Provider} || '',
    );
    if (!$URL) {
        return $Self->_LoginShow(
            ErrorMessage => $Self->{ExternalAuth}->Error() || 'Translate:ExternalAuthStartFailed',
            FormAction   => $Param{FormAction} || 'index.pl',
        );
    }
    return $Self->{Output}->Redirect(
        Location => $URL,
        Cookie   => $Self->_PublicLanguageCookie(),
    );
}

sub _ExternalAuthCallback {
    my ( $Self, %Param ) = @_;
    my $User = $Self->{ExternalAuth}->AuthorizationComplete( Request => \%Param );
    if (!$User) {
        return $Self->_LoginShow(
            ErrorMessage => $Self->{ExternalAuth}->Error() || 'Translate:ExternalAuthLoginFailed',
            FormAction   => $Param{FormAction} || 'index.pl',
        );
    }
    if ( $Self->{TwoFactor}->Required( User => $User ) ) {
        my $Challenge = $Self->{TwoFactor}->ChallengeCreate( User => $User );
        return $Self->_LoginShow(
            ErrorMessage => $Self->{TwoFactor}->Error() || 'Translate:LoginCouldNotBeFinished',
            FormAction   => $Param{FormAction} || 'index.pl',
        ) if !$Challenge;
        return $Self->_TwoFactorShow( %Param, Challenge => $Challenge );
    }
    return $Self->_LoginFinish( User => $User, %Param );
}

sub _LoginSubmit {
    my ( $Self, %Param ) = @_;

    my $Login       = $Param{Login}       || '';
    my $Password    = $Param{Password}    || '';
    my $AccountType = $Param{AccountType} || 'agent';

    if ( $AccountType ne 'agent' && $AccountType ne 'customer' ) {
        $AccountType = 'agent';
    }

    if ( $AccountType eq 'agent' && $Self->{ExternalAuth} ) {
        my $Providers = $Self->{ExternalAuth}->ProviderList( AccountType => 'agent' );
        if ( grep { !$_->{allow_local_login} } @{$Providers} ) {
            return $Self->_LoginShow(
                Step         => 'LocalLogin',
                ErrorMessage => 'Translate:ExternalAuthLocalLoginDisabled',
                AccountType  => 'customer',
                FormAction   => $Param{FormAction} || 'index.pl',
            );
        }
    }

    my $User = $Self->{Auth}->LoginCheck(
        Login       => $Login,
        Password    => $Password,
        AccountType => $AccountType,
    );

    if ( !$User ) {
        return $Self->_LoginShow(
            ErrorMessage => 'Translate:LoginInvalid',
            LoginValue   => $Login,
            AccountType  => $AccountType,
            FormAction   => $Param{FormAction} || 'index.pl',
        );
    }

    if ( $Self->{TwoFactor}->Required( User => $User ) ) {
        my $Challenge = $Self->{TwoFactor}->ChallengeCreate( User => $User );
        if ( !$Challenge ) {
            return $Self->_LoginShow(
                ErrorMessage => $Self->{TwoFactor}->Error() || 'Translate:LoginCouldNotBeFinished',
                LoginValue   => $Login,
                AccountType  => $AccountType,
                FormAction   => $Param{FormAction} || 'index.pl',
            );
        }
        return $Self->_TwoFactorShow(
            %Param,
            Challenge => $Challenge,
        );
    }

    return $Self->_LoginFinish( User => $User, %Param );
}

sub _LoginFinish {
    my ( $Self, %Param ) = @_;

    my $User = $Param{User} || {};

    my $Session = $Self->{Session}->Create(
        UserID    => $User->{id},
        IPAddress => $Param{IPAddress} || '',
        UserAgent => $Param{UserAgent} || '',
    );

    if ( !$Session ) {
        return $Self->_LoginShow(
            ErrorMessage => 'Translate:LoginCouldNotBeFinished',
            LoginValue   => $User->{login} || '',
            AccountType  => $User->{account_type} || 'agent',
            FormAction   => $Param{FormAction} || 'index.pl',
        );
    }

    my $Cookie = $Self->{Output}->CookieCreate(
        Name     => $Self->{Config}->{Session}->{CookieName},
        Value    => $Session->{Token},
        MaxAge   => $Self->{Config}->{Session}->{LifetimeSeconds},
        Path     => '/',
        SameSite => 'Lax',
        Secure   => $Param{SecureCookie} || 0,
        HttpOnly => 1,
    );

    my $Location = $Param{SuccessLocation} || 'index.pl';

    return $Self->{Output}->Redirect(
        Location => $Location,
        Cookie   => $Cookie,
    );
}

sub _TwoFactorShow {
    my ( $Self, %Param ) = @_;
    my $Challenge = $Param{Challenge} || {};
    my $Mode = $Challenge->{Mode} || $Param{TwoFactorMode} || 'login';
    my $Secret = $Challenge->{Secret} || $Param{TwoFactorSecret} || '';
    my $AccountName = $Challenge->{AccountName} || $Param{TwoFactorAccountName} || '';
    my $ProvisioningURI = $Challenge->{ProvisioningURI} || '';
    if ( !$ProvisioningURI && $Mode eq 'setup' && $Secret && $AccountName ) {
        $ProvisioningURI = $Self->{TwoFactor}->ProvisioningURI(
            Secret      => $Secret,
            AccountName => $AccountName,
        );
    }

    return $Self->_RenderPublicPage(
        Template => 'TwoFactorChallenge.tt',
        Data     => $Self->_TemplateData(
            PageTitle      => 'Translate:TwoFactorLoginTitle',
            ErrorMessage   => $Param{ErrorMessage} || '',
            FormAction     => $Param{FormAction} || 'index.pl',
            ChallengeToken => $Challenge->{Token} || $Param{ChallengeToken} || '',
            TwoFactorMode             => $Mode,
            TwoFactorSetup            => $Mode eq 'setup' ? 1 : 0,
            TwoFactorSecret           => $Secret,
            TwoFactorAccountName      => $AccountName,
            TwoFactorProvisioningURI  => $ProvisioningURI,
        ),
    );
}

sub _TwoFactorVerify {
    my ( $Self, %Param ) = @_;
    my $Result = $Self->{TwoFactor}->ChallengeVerify(
        Token => $Param{ChallengeToken} || '',
        Code  => $Param{TwoFactorCode} || '',
    );
    if ( !$Result ) {
        return $Self->_TwoFactorShow(
            %Param,
            ChallengeToken => $Param{ChallengeToken} || '',
            TwoFactorMode  => $Param{TwoFactorMode} || 'login',
            TwoFactorSecret => $Param{TwoFactorSecret} || '',
            TwoFactorAccountName => $Param{TwoFactorAccountName} || '',
            ErrorMessage   => $Self->{TwoFactor}->Error() || 'Translate:TwoFactorCodeInvalid',
        );
    }

    my $User = $Result->{User} || {};
    $User->{id} = $User->{user_account_id};
    my $Codes = $Result->{RecoveryCodes} || [];
    if ( @{$Codes} ) {
        my $Session = $Self->{Session}->Create(
            UserID    => $User->{id},
            IPAddress => $Param{IPAddress} || '',
            UserAgent => $Param{UserAgent} || '',
        );
        return $Self->_LoginShow( ErrorMessage => 'Translate:LoginCouldNotBeFinished' ) if !$Session;
        my $Cookie = $Self->{Output}->CookieCreate(
            Name => $Self->{Config}->{Session}->{CookieName}, Value => $Session->{Token},
            MaxAge => $Self->{Config}->{Session}->{LifetimeSeconds}, Path => '/', SameSite => 'Lax',
            Secure => $Param{SecureCookie} || 0, HttpOnly => 1,
        );
        return $Self->_RenderPublicPage(
            Template => 'TwoFactorRecoveryCodes.tt',
            Cookie   => $Cookie,
            Data     => $Self->_TemplateData(
                PageTitle         => 'Translate:TwoFactorRecoveryCodesTitle',
                FormAction        => $Param{SuccessLocation} || 'index.pl',
                RecoveryCodesHTML => join( '', map { '<li><code>' . $Self->{Output}->HTMLEscape($_) . '</code></li>' } @{$Codes} ),
            ),
        );
    }

    return $Self->_LoginFinish( User => $User, %Param );
}

sub _PasswordForgotShow {
    my ( $Self, %Param ) = @_;

    my $AccountType = $Param{AccountType} || 'agent';
    $AccountType = 'agent' if $AccountType ne 'customer';

    return $Self->_RenderPublicPage(
        Template => 'PasswordForgot.tt',
        Data     => $Self->_TemplateData(
            PageTitle    => 'Translate:PagePasswordForgotTitle',
            ErrorMessage => $Param{ErrorMessage} || '',
            UserInput    => $Param{UserInput} || '',
            AccountType  => $AccountType,
            FormAction   => $Param{FormAction} || 'index.pl',
        ),
    );
}

sub _PasswordForgotSubmit {
    my ( $Self, %Param ) = @_;

    my $AccountType = $Param{AccountType} || 'agent';
    my $UserInput   = $Param{UserInput} || '';

    my $Result = $Self->{PasswordReset}->RequestCreate(
        AccountType => $AccountType,
        UserInput   => $UserInput,
        IPAddress   => $Param{IPAddress} || '',
        UserAgent   => $Param{UserAgent} || '',
    );

    if ( !$Result || !$Result->{Success} ) {
        return $Self->_PasswordForgotShow(
            ErrorMessage => $Result && $Result->{Error} ? $Result->{Error} : 'Translate:PasswordForgotCouldNotBeProcessed',
            UserInput    => $UserInput,
            AccountType  => $AccountType,
            FormAction   => $Param{FormAction} || 'index.pl',
        );
    }

    return $Self->_RenderPublicPage(
        Template => 'PasswordForgotSent.tt',
        Data     => $Self->_TemplateData(
            PageTitle  => 'Translate:PagePasswordForgotSentTitle',
            FormAction => $Param{FormAction} || 'index.pl',
        ),
    );
}

sub _PasswordResetShow {
    my ( $Self, %Param ) = @_;

    my $Token = $Param{Token} || '';
    my $TokenData = $Self->{PasswordReset}->TokenGet( Token => $Token );

    if ( !$TokenData ) {
        return $Self->_PasswordResetInvalid(%Param);
    }

    return $Self->_RenderPublicPage(
        Template => 'PasswordReset.tt',
        Data     => $Self->_TemplateData(
            PageTitle       => 'Translate:PagePasswordResetTitle',
            ErrorMessage    => $Param{ErrorMessage} || '',
            Token           => $Token,
            FormAction      => $Param{FormAction} || 'index.pl',
            NewPassword     => '',
            RepeatPassword  => '',
        ),
    );
}

sub _PasswordResetSubmit {
    my ( $Self, %Param ) = @_;

    my $Token = $Param{Token} || '';

    my $Result = $Self->{PasswordReset}->PasswordSet(
        Token          => $Token,
        NewPassword    => defined $Param{NewPassword} ? $Param{NewPassword} : '',
        RepeatPassword => defined $Param{RepeatPassword} ? $Param{RepeatPassword} : '',
    );

    if ( !$Result || !$Result->{Success} ) {
        my $Error = $Result && $Result->{Error} ? $Result->{Error} : 'Translate:PasswordResetCouldNotBeSaved';

        if ( $Error eq 'Translate:PasswordResetInvalid' ) {
            return $Self->_PasswordResetInvalid(%Param);
        }

        my $TokenData = $Self->{PasswordReset}->TokenGet( Token => $Token );
        if ( !$TokenData ) {
            return $Self->_PasswordResetInvalid(%Param);
        }

        return $Self->_RenderPublicPage(
            Template => 'PasswordReset.tt',
            Data     => $Self->_TemplateData(
                PageTitle    => 'Translate:PagePasswordResetTitle',
                ErrorMessage => $Error,
                Token        => $Token,
                FormAction   => $Param{FormAction} || 'index.pl',
            ),
        );
    }

    my $Cookie = $Self->{Output}->CookieDelete(
        Name => $Self->{Config}->{Session}->{CookieName},
        Path => '/',
    );

    return $Self->_RenderPublicPage(
        Template => 'PasswordResetComplete.tt',
        Cookie   => $Cookie,
        Data     => $Self->_TemplateData(
            PageTitle  => 'Translate:PagePasswordResetCompleteTitle',
            FormAction => $Param{FormAction} || 'index.pl',
        ),
    );
}

sub _CustomerRegistrationShow {
    my ( $Self, %Param ) = @_;

    return $Self->_RenderPublicPage(
        Template => 'CustomerRegistration.tt',
        Data     => $Self->_TemplateData(
            PageTitle    => 'Translate:PageCustomerRegistrationTitle',
            ErrorMessage => $Param{ErrorMessage} || '',
            Firstname    => $Param{Firstname} || '',
            Lastname     => $Param{Lastname} || '',
            Email        => $Param{Email} || '',
            Company      => $Param{Company} || '',
            FormAction   => $Param{FormAction} || 'index.pl',
        ),
    );
}

sub _CustomerRegistrationSubmit {
    my ( $Self, %Param ) = @_;

    my $Language = $Self->_PublicLanguage();
    my $Result = $Self->{CustomerRegistration}->RequestCreate(
        Firstname => $Param{Firstname} || '',
        Lastname  => $Param{Lastname} || '',
        Email     => $Param{Email} || '',
        Company   => $Param{Company} || '',
        Language  => $Language,
        IPAddress => $Param{IPAddress} || '',
        UserAgent => $Param{UserAgent} || '',
    );

    if ( !$Result || !$Result->{Success} ) {
        return $Self->_CustomerRegistrationShow(
            ErrorMessage => $Result && $Result->{Error} ? $Result->{Error} : 'Translate:CustomerRegistrationCouldNotBeProcessed',
            Firstname    => $Param{Firstname} || '',
            Lastname     => $Param{Lastname} || '',
            Email        => $Param{Email} || '',
            Company      => $Param{Company} || '',
            FormAction   => $Param{FormAction} || 'index.pl',
        );
    }

    return $Self->_RenderPublicPage(
        Template => 'CustomerRegistrationSent.tt',
        Data     => $Self->_TemplateData(
            PageTitle  => 'Translate:PageCustomerRegistrationSentTitle',
            FormAction => $Param{FormAction} || 'index.pl',
        ),
    );
}

sub _CustomerRegistrationPasswordShow {
    my ( $Self, %Param ) = @_;

    my $Token = $Param{Token} || '';
    my $TokenData = $Self->{CustomerRegistration}->TokenGet( Token => $Token );

    if ( !$TokenData ) {
        return $Self->_CustomerRegistrationInvalid(%Param);
    }

    return $Self->_RenderPublicPage(
        Template => 'CustomerRegistrationPassword.tt',
        Data     => $Self->_TemplateData(
            PageTitle    => 'Translate:PageCustomerRegistrationPasswordTitle',
            ErrorMessage => $Param{ErrorMessage} || '',
            Token        => $Token,
            Email        => $TokenData->{email} || '',
            Company      => $TokenData->{company} || '',
            FormAction   => $Param{FormAction} || 'index.pl',
        ),
    );
}

sub _CustomerRegistrationPasswordSubmit {
    my ( $Self, %Param ) = @_;

    my $Token = $Param{Token} || '';
    my $Result = $Self->{CustomerRegistration}->RegistrationComplete(
        Token          => $Token,
        NewPassword    => defined $Param{NewPassword} ? $Param{NewPassword} : '',
        RepeatPassword => defined $Param{RepeatPassword} ? $Param{RepeatPassword} : '',
    );

    if ( !$Result || !$Result->{Success} ) {
        my $Error = $Result && $Result->{Error} ? $Result->{Error} : 'Translate:CustomerRegistrationCouldNotBeCompleted';

        if ( $Error eq 'Translate:CustomerRegistrationInvalid' ) {
            return $Self->_CustomerRegistrationInvalid(%Param);
        }

        my $TokenData = $Self->{CustomerRegistration}->TokenGet( Token => $Token );
        if ( !$TokenData ) {
            return $Self->_CustomerRegistrationInvalid(%Param);
        }

        return $Self->_RenderPublicPage(
            Template => 'CustomerRegistrationPassword.tt',
            Data     => $Self->_TemplateData(
                PageTitle    => 'Translate:PageCustomerRegistrationPasswordTitle',
                ErrorMessage => $Error,
                Token        => $Token,
                Email        => $TokenData->{email} || '',
                Company      => $TokenData->{company} || '',
                FormAction   => $Param{FormAction} || 'index.pl',
            ),
        );
    }

    my $Cookie = $Self->{Output}->CookieDelete(
        Name => $Self->{Config}->{Session}->{CookieName},
        Path => '/',
    );

    return $Self->_RenderPublicPage(
        Template => 'CustomerRegistrationComplete.tt',
        Cookie   => $Cookie,
        Data     => $Self->_TemplateData(
            PageTitle  => 'Translate:PageCustomerRegistrationCompleteTitle',
            LoginValue => $Result->{Login} || '',
            FormAction => $Param{FormAction} || 'index.pl',
        ),
    );
}

sub _CustomerRegistrationInvalid {
    my ( $Self, %Param ) = @_;

    return $Self->_RenderPublicPage(
        Template => 'CustomerRegistrationInvalid.tt',
        Data     => $Self->_TemplateData(
            PageTitle  => 'Translate:PageCustomerRegistrationInvalidTitle',
            FormAction => $Param{FormAction} || 'index.pl',
        ),
    );
}

sub _PasswordResetInvalid {
    my ( $Self, %Param ) = @_;

    return $Self->_RenderPublicPage(
        Template => 'PasswordResetInvalid.tt',
        Data     => $Self->_TemplateData(
            PageTitle  => 'Translate:PagePasswordResetInvalidTitle',
            FormAction => $Param{FormAction} || 'index.pl',
        ),
    );
}

sub _RenderPublicPage {
    my ( $Self, %Param ) = @_;

    my $Body = $Self->{Output}->Render(
        Template => $Param{Template},
        Header   => 'LoginHeader.tt',
        Footer   => 'LoginFooter.tt',
        Data     => $Param{Data} || {},
    );

    if ( !defined $Body ) {
        $Self->{LastError} = $Self->{Output}->Error() || 'Public login page could not be rendered';
        return;
    }

    return $Self->{Output}->Response(
        Body    => $Body,
        Cookie  => $Param{Cookie} || '',
        Headers => [
            'Set-Cookie: ' . $Self->_PublicLanguageCookie(),
            'Cache-Control: no-store, no-cache, must-revalidate, max-age=0',
            'Pragma: no-cache',
            'Expires: 0',
            'Referrer-Policy: no-referrer',
            'X-Robots-Tag: noindex, nofollow',
        ],
    );
}

sub _TemplateData {
    my ( $Self, %Param ) = @_;

    my $AccountType = $Param{AccountType} || 'agent';
    my $Language    = $Self->_LanguageClean( $Param{Language} ) || $Self->_PublicLanguage();

    return {
        Language        => $Language,
        LoginLanguages  => $Self->_LoginLanguageList( Selected => $Language ),
        LoginURL        => 'index.pl?Language=' . $Language,
        PasswordForgotURL => 'index.pl?Step=PasswordForgot;Language=' . $Language,
        CustomerRegistrationURL => 'index.pl?Step=CustomerRegistration;Language=' . $Language,
        Robots          => 'noindex, nofollow',
        PageTitle       => $Param{PageTitle} || 'Translate:PageLoginTitle',
        StaticBase      => $Self->{Config}->{Paths}->{StaticURL} || '/static',
        PageCSS         => 'qisutu-login.css?v=2026081602',
        BodyClass       => 'qisutu-login-page',
        SystemName      => $Self->{Config}->{System}->{Name} || 'Qisutu',
        ErrorMessage    => $Param{ErrorMessage} || '',
        FormAction      => $Param{FormAction} || 'index.pl',
        LoginValue      => $Param{LoginValue} || '',
        UserInput       => $Param{UserInput} || '',
        Token           => $Param{Token} || '',
        Firstname       => $Param{Firstname} || '',
        Lastname        => $Param{Lastname} || '',
        Email           => $Param{Email} || '',
        Company         => $Param{Company} || '',
        AccountType     => $AccountType,
        AgentChecked    => ( $AccountType eq 'agent' ? 'checked' : '' ),
        CustomerChecked => ( $AccountType eq 'customer' ? 'checked' : '' ),
        CSRFToken       => $Self->{Security}
            ? $Self->{Security}->PublicCSRFTokenCreate( Purpose => 'public-form' )
            : '',
        ChallengeToken  => $Param{ChallengeToken} || '',
        TwoFactorMode   => $Param{TwoFactorMode} || 'login',
        TwoFactorSetup  => $Param{TwoFactorSetup} ? 1 : 0,
        TwoFactorSecret => $Param{TwoFactorSecret} || '',
        TwoFactorAccountName     => $Param{TwoFactorAccountName} || '',
        TwoFactorProvisioningURI => $Param{TwoFactorProvisioningURI} || '',
        RecoveryCodesHTML => $Param{RecoveryCodesHTML} || '',
        ExternalAuthProviders => $Param{ExternalAuthProviders} || [],
        HasExternalAuth       => $Param{HasExternalAuth} ? 1 : 0,
        ShowLocalAgentLogin   => exists $Param{ShowLocalAgentLogin}
            ? ( $Param{ShowLocalAgentLogin} ? 1 : 0 )
            : 1,
    };
}

sub _PublicLanguage {
    my ($Self) = @_;

    return $Self->_LanguageClean( $Self->{PublicLanguage} ) || 'en';
}

sub _LanguageClean {
    my ( $Self, $Language ) = @_;

    return '' if !defined $Language || ref $Language;

    $Language =~ s{\A\s+|\s+\z}{}g;
    $Language =~ tr{_}{-};
    return '' if $Language !~ m{\A[A-Za-z]{2,3}(?:-[A-Za-z]{2})?\z};

    if ( $Language =~ m{\A([A-Za-z]{2,3})-([A-Za-z]{2})\z} ) {
        $Language = lc($1) . '-' . uc($2);
    }
    else {
        $Language = lc $Language;
    }

    my $LanguagePath = $Self->{Config}->{Paths}->{Language} || '';
    return '' if !$LanguagePath;

    my $File = File::Spec->catfile( $LanguagePath, "$Language.pm" );
    return '' if !-f $File || -l $File;

    return $Language;
}

sub _BrowserLanguage {
    my ( $Self, $Header ) = @_;

    return '' if !defined $Header || ref $Header;

    for my $Part ( split /,/, $Header ) {
        my ($Language) = split /;/, $Part, 2;
        $Language =~ s{\A\s+|\s+\z}{}g;
        next if !$Language || $Language eq '*';

        my $Clean = $Self->_LanguageClean($Language);
        return $Clean if $Clean;

        if ( $Language =~ m{\A([A-Za-z]{2,3})[-_]} ) {
            $Clean = $Self->_LanguageClean($1);
            return $Clean if $Clean;
        }
    }

    return '';
}

sub _LoginLanguageList {
    my ( $Self, %Param ) = @_;

    my $Selected = $Self->_LanguageClean( $Param{Selected} ) || $Self->_PublicLanguage();
    my @Known = (
        [ de      => 'Deutsch' ],
        [ en      => 'English' ],
        [ fr      => 'Français' ],
        [ it      => 'Italiano' ],
        [ 'pt-BR' => 'Português (Brasil)' ],
        [ 'pt-PT' => 'Português (Portugal)' ],
        [ es      => 'Español' ],
        [ nl      => 'Nederlands' ],
        [ pl      => 'Polski' ],
        [ cs      => 'Čeština' ],
        [ tr      => 'Türkçe' ],
    );

    my @Language;
    for my $Entry (@Known) {
        my ( $Code, $Label ) = @{$Entry};
        next if !$Self->_LanguageClean($Code);

        push @Language, {
            code     => $Code,
            label    => $Label,
            selected => $Code eq $Selected ? ' selected' : '',
        };
    }

    return \@Language;
}

sub _PublicLanguageCookie {
    my ($Self) = @_;

    return $Self->{Output}->CookieCreate(
        Name     => 'QisutuPublicLanguage',
        Value    => $Self->_PublicLanguage(),
        MaxAge   => 31536000,
        Path     => '/',
        SameSite => 'Lax',
        Secure   => $Self->{PublicLanguageSecureCookie} ? 1 : 0,
        HttpOnly => 1,
    );
}

sub Error {
    my ($Self) = @_;

    return $Self->{LastError};
}

1;
