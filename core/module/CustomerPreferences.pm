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

package CustomerPreferences;

use strict;
use warnings;
use utf8;

sub new {
    my ( $Class, %Param ) = @_;

    my $Self = {
        Config  => $Param{Config},
        DB      => $Param{DB},
        Output  => $Param{Output},
        Program => $Param{Program},
    };

    bless $Self, $Class;

    return $Self;
}

sub Run {
    my ( $Self, %Param ) = @_;

    my $Request = $Param{Request} || {};
    my $User    = $Param{User}    || {};
    my $Prefs   = $Self->_PreferenceObject();
    my $Step    = $Request->{Step} || '';
    my $TwoFactor = $Self->_TwoFactorObject();
    my $RecoveryCodes = [];

    if ( $TwoFactor && $Step eq 'TwoFactorStart' ) {
        $TwoFactor->SetupStart( UserAccountID => $User->{user_account_id} );
        return { Redirect => 'index.pl?Page=CustomerPreferences;TwoFactorSetup=1' } if !$TwoFactor->Error();
    }
    elsif ( $TwoFactor && $Step eq 'TwoFactorEnable' ) {
        $RecoveryCodes = $TwoFactor->SetupConfirm( UserAccountID => $User->{user_account_id}, Code => $Request->{TwoFactorCode} );
    }
    elsif ( $TwoFactor && $Step eq 'TwoFactorDisable' ) {
        $TwoFactor->Disable( UserAccountID => $User->{user_account_id}, Code => $Request->{TwoFactorCode} );
        return { Redirect => 'index.pl?Page=CustomerPreferences;TwoFactorDisabled=1' } if !$TwoFactor->Error();
    }
    elsif ( $TwoFactor && $Step eq 'TwoFactorRecoveryRegenerate' ) {
        $RecoveryCodes = $TwoFactor->RecoveryCodesRegenerate( UserAccountID => $User->{user_account_id}, Code => $Request->{TwoFactorCode} );
    }

    if ( $Prefs && $Step eq 'PreferenceSave' ) {
        $Prefs->CustomerPreferenceSave(
            UserAccountID => $User->{user_account_id},
            Request       => $Request,
        );

        return { Redirect => 'index.pl?Page=CustomerPreferences;Saved=1' } if !$Prefs->Error();
    }

    my $Preference = $Prefs ? $Prefs->CustomerPreferenceGet( UserAccountID => $User->{user_account_id} ) : {};
    my $ErrorMessage = $TwoFactor && $TwoFactor->Error() ? $TwoFactor->Error() : ( $Prefs ? $Prefs->Error() : 'Preference system could not be loaded.' );
    my $SuccessMessage = $Request->{Saved} ? 'Translate:PreferencesSaved' : '';

    my $TwoFactorStatus = $TwoFactor ? $TwoFactor->StatusGet( UserAccountID => $User->{user_account_id} ) : {};
    my $TwoFactorProvisioningURI = $TwoFactor ? $TwoFactor->ProvisioningURI(
        Secret      => $TwoFactorStatus->{secret} || '',
        AccountName => $User->{email} || $User->{login} || 'user-' . ( $User->{user_account_id} || 0 ),
    ) : '';

    return {
        Template => 'CustomerPreferences.tt',
        Data     => {
            PageTitle          => 'Translate:CustomerPreferencesTitle',
            ProgramTitle       => 'Translate:CustomerPreferencesTitle',
            ProgramDescription => 'Translate:CustomerPreferencesDescription',
            ErrorMessage       => $ErrorMessage,
            ErrorClass         => $ErrorMessage ? '' : 'qisutu-hidden',
            SuccessMessage     => $SuccessMessage,
            SuccessClass       => $SuccessMessage ? '' : 'qisutu-hidden',
            FormAction         => 'index.pl',
            LanguageOptions    => $Self->_LanguageOptions(
                Preference => $Preference,
                Prefs      => $Prefs,
            ),
            TimezoneOptions    => $Self->_TimezoneOptions(
                Preference => $Preference,
                Prefs      => $Prefs,
            ),
            TwoFactorEnabled           => $TwoFactorStatus->{enabled} ? 1 : 0,
            TwoFactorSetup             => !$TwoFactorStatus->{enabled} && $TwoFactorStatus->{configured} ? 1 : 0,
            TwoFactorSecret            => $TwoFactorStatus->{secret} || '',
            TwoFactorProvisioningURI   => $TwoFactorProvisioningURI,
            TwoFactorRecoveryRemaining => $TwoFactorStatus->{recovery_codes_remaining} || 0,
            RecoveryCodesHTML          => join( '', map { '<li><code>' . $Self->{Output}->HTMLEscape($_) . '</code></li>' } @{ $RecoveryCodes || [] } ),
            ShowRecoveryCodes          => @{ $RecoveryCodes || [] } ? 1 : 0,
        },
    };
}

sub _TwoFactorObject {
    my ($Self) = @_;
    my $Loaded = eval { require QisutuTwoFactor; 1 };
    return if !$Loaded;
    return QisutuTwoFactor->new( Config => $Self->{Config}, DB => $Self->{DB} );
}

sub _PreferenceObject {
    my ($Self) = @_;

    my $Loaded = eval {
        require QisutuUserPreference;
        1;
    };

    return if !$Loaded;

    return QisutuUserPreference->new(
        Config => $Self->{Config},
        DB     => $Self->{DB},
    );
}

sub _LanguageOptions {
    my ( $Self, %Param ) = @_;

    my $Prefs      = $Param{Prefs};
    my $Preference = $Param{Preference} || {};
    my $Selected   = $Preference->{language} || $Self->{Config}->{Language}->{Default} || 'en';
    my $Languages  = $Prefs ? $Prefs->LanguageList() : [ $Selected ];
    my $HTML       = '';

    for my $Language ( @{$Languages} ) {
        my $IsSelected = $Language eq $Selected ? ' selected' : '';
        $HTML .= '<option value="' . $Self->{Output}->HTMLEscape($Language) . '"' . $IsSelected . '>';
        $HTML .= $Self->{Output}->HTMLEscape($Language);
        $HTML .= '</option>' . "
";
    }

    return $HTML;
}

sub _TimezoneOptions {
    my ( $Self, %Param ) = @_;

    my $Prefs      = $Param{Prefs};
    my $Preference = $Param{Preference} || {};
    my $Selected   = $Preference->{timezone} || 'Europe/Berlin';
    my $Timezones  = $Prefs ? $Prefs->TimezoneList() : [ $Selected ];
    my $HTML       = '';

    for my $Timezone ( @{$Timezones} ) {
        my $IsSelected = $Timezone eq $Selected ? ' selected' : '';
        $HTML .= '<option value="' . $Self->{Output}->HTMLEscape($Timezone) . '"' . $IsSelected . '>';
        $HTML .= $Self->{Output}->HTMLEscape($Timezone);
        $HTML .= '</option>' . "
";
    }

    return $HTML;
}

1;
