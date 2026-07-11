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

sub new {
    my ( $Class, %Param ) = @_;

    my $Self = {
        Config    => $Param{Config},
        Output    => $Param{Output},
        DB        => $Param{DB},
        Auth      => $Param{Auth},
        Session   => $Param{Session},
        LastError => '',
    };

    bless $Self, $Class;

    return $Self;
}

sub Run {
    my ( $Self, %Param ) = @_;

    my $Step = $Param{Step} || '';

    if ( $Step eq 'Login' ) {
        return $Self->_LoginSubmit(%Param);
    }

    return $Self->_LoginShow(%Param);
}

sub _LoginShow {
    my ( $Self, %Param ) = @_;

    my $Body = $Self->{Output}->Render(
        Template => 'Login.tt',
        Header   => 'LoginHeader.tt',
        Footer   => 'LoginFooter.tt',
            Data     => $Self->_TemplateData(
                ErrorMessage => $Param{ErrorMessage}  || '',
                LoginValue   => $Param{LoginValue}    || '',
                AccountType  => $Param{AccountType}   || 'agent',
                FormAction   => $Param{FormAction}    || 'index.pl',
            ),
    );

    if ( !defined $Body ) {
        $Self->{LastError} = $Self->{Output}->Error() || 'Login page could not be rendered';
        return;
    }

    return $Self->{Output}->Response(
        Body => $Body,
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

    my $Session = $Self->{Session}->Create(
        UserID    => $User->{id},
        IPAddress => $Param{IPAddress} || '',
        UserAgent => $Param{UserAgent} || '',
    );

    if ( !$Session ) {
        return $Self->_LoginShow(
            ErrorMessage => 'Translate:LoginCouldNotBeFinished',
            LoginValue   => $Login,
            AccountType  => $AccountType,
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

sub _TemplateData {
    my ( $Self, %Param ) = @_;

    return {
        Language     => $Self->_DefaultLanguage(),
        Robots       => 'noindex, nofollow',
        PageTitle    => 'Translate:PageLoginTitle',
        StaticBase   => $Self->{Config}->{Paths}->{StaticURL} || '/static',
        PageCSS      => 'qisutu-login.css',
        BodyClass    => 'qisutu-login-page',
        SystemName   => $Self->{Config}->{System}->{Name} || 'Qisutu',
        ErrorMessage => $Param{ErrorMessage} || '',
        FormAction   => $Param{FormAction}   || 'index.pl',
        LoginValue   => $Param{LoginValue}   || '',
        AccountType  => $Param{AccountType}  || 'agent',
        AgentChecked => ( ( $Param{AccountType} || 'agent' ) eq 'agent' ? 'checked' : '' ),
        CustomerChecked => ( ( $Param{AccountType} || '' ) eq 'customer' ? 'checked' : '' ),
    };
}


sub _DefaultLanguage {
    my ($Self) = @_;

    my $Language = $Self->{Config}->{Language}->{Default} || 'en';

    my $Loaded = eval {
        require QisutuSystemSetting;
        1;
    };

    if ($Loaded && $Self->{DB}) {
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
