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

use QisutuPasswordReset;
use QisutuCustomerRegistration;
use QisutuTwoFactor;

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

    bless $Self, $Class;

    return $Self;
}

sub Run {
    my ( $Self, %Param ) = @_;

    my $Step = $Param{Step} || '';

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

    return $Self->_LoginShow(%Param);
}

sub _LoginShow {
    my ( $Self, %Param ) = @_;

    return $Self->_RenderPublicPage(
        Template => 'Login.tt',
        Data     => $Self->_TemplateData(
            PageTitle    => 'Translate:PageLoginTitle',
            ErrorMessage => $Param{ErrorMessage} || '',
            LoginValue   => $Param{LoginValue}   || '',
            AccountType  => $Param{AccountType}  || 'agent',
            FormAction   => $Param{FormAction}   || 'index.pl',
        ),
    );
}

sub _LoginSubmit {
    my ( $Self, %Param ) = @_;

    my $Login       = $Param{Login}       || '';
    my $Password    = $Param{Password}    || '';
    my $AccountType = $Param{AccountType} || 'agent';

    if ( $AccountType ne 'agent' && $AccountType ne 'customer' ) {
        $AccountType = 'agent';
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

    my $Language = $Self->_DefaultLanguage();
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

    return {
        Language        => $Self->_DefaultLanguage(),
        Robots          => 'noindex, nofollow',
        PageTitle       => $Param{PageTitle} || 'Translate:PageLoginTitle',
        StaticBase      => $Self->{Config}->{Paths}->{StaticURL} || '/static',
        PageCSS         => 'qisutu-login.css?v=2026071602',
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
    };
}

sub _DefaultLanguage {
    my ($Self) = @_;

    my $Language = $Self->{Config}->{Language}->{Default} || 'en';

    my $Loaded = eval {
        require QisutuSystemSetting;
        1;
    };

    if ( $Loaded && $Self->{DB} ) {
        my $SettingObject = QisutuSystemSetting->new(
            Config => $Self->{Config},
            DB     => $Self->{DB},
        );

        my $ConfiguredLanguage = $SettingObject->Get(
            Key     => 'system.default_language',
            Default => $Language,
        );

        if ( $ConfiguredLanguage && $ConfiguredLanguage =~ m{\A[A-Za-z0-9_-]+\z} ) {
            $Language = $ConfiguredLanguage;
        }
    }

    return $Language || 'en';
}

sub Error {
    my ($Self) = @_;

    return $Self->{LastError};
}

1;
