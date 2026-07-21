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

package QisutuDispatcher;

use strict;
use warnings;
use utf8;

sub new {
    my ( $Class, %Param ) = @_;

    my $Self = {
        Config          => $Param{Config},
        DB              => $Param{DB},
        Output          => $Param{Output},
        ProgramRegistry => $Param{ProgramRegistry},
        LastError       => '',
    };

    bless $Self, $Class;

    return $Self;
}

sub Run {
    my ( $Self, %Param ) = @_;

    my $Request    = $Param{Request} || {};
    my $User       = $Param{User}    || {};
    my $Preference = $Self->_UserPreferenceGet( User => $User );
    my $Language   = $Preference->{language} || $Self->_DefaultLanguage();
    my $Page       = $Request->{Page} || $Self->_DefaultPage(
        User       => $User,
        Preference => $Preference,
    );

    $Request->{Language}       = $Language;
    $Request->{UserPreference} = $Preference;

    my $Program = $Self->{ProgramRegistry}->ProgramGet( Name => $Page );

    if ( !$Program || !$Program->{Active} ) {
        return $Self->_RenderError(
            User       => $User,
            Status     => '404 Not Found',
            Title      => 'Translate:ErrorPageNotFoundTitle',
            Message    => 'Translate:ErrorPageNotFoundText',
            ActiveName => 'Dashboard',
        );
    }

    if ( !$Self->_PermissionCheck( Program => $Program, User => $User ) ) {
        return $Self->_RenderError(
            User       => $User,
            Status     => '403 Forbidden',
            Title      => 'Translate:ErrorPermissionTitle',
            Message    => 'Translate:ErrorPermissionText',
            ActiveName => $Program->{Name},
        );
    }

    my $ModuleName = $Program->{Module} || $Program->{Name};
    my $Module     = $Self->_ModuleCreate(
        Module  => $ModuleName,
        Program => $Program,
    );

    if ( !$Module ) {
        return $Self->_RenderError(
            User       => $User,
            Status     => '500 Internal Server Error',
            Title      => 'Translate:ErrorProgramLoadTitle',
            Message    => 'Translate:ErrorProgramLoadText',
            ActiveName => $Program->{Name},
        );
    }

    my $Result = $Module->Run(
        Request => $Request,
        User    => $User,
        Program => $Program,
    );

    if ( !$Result || ref $Result ne 'HASH' ) {
        return $Self->_RenderError(
            User       => $User,
            Status     => '500 Internal Server Error',
            Title      => 'Translate:ErrorProgramRunTitle',
            Message    => 'Translate:ErrorProgramRunText',
            ActiveName => $Program->{Name},
        );
    }

    if ( $Result->{Response} ) {
        return $Result->{Response};
    }

    if ( $Result->{Redirect} ) {
        return $Self->{Output}->Redirect(
            Location => $Result->{Redirect},
        );
    }

    if ( !$Result->{Template} ) {
        return $Self->_RenderError(
            User       => $User,
            Status     => '500 Internal Server Error',
            Title      => 'Translate:ErrorTemplateMissingTitle',
            Message    => 'Translate:ErrorTemplateMissingText',
            ActiveName => $Program->{Name},
        );
    }

    return $Self->_RenderProgram(
        User       => $User,
        Program    => $Program,
        Template   => $Result->{Template},
        Data       => $Result->{Data} || {},
        ActiveName => $Self->_ActiveName( Program => $Program ),
    );
}


sub _DefaultPage {
    my ( $Self, %Param ) = @_;

    my $User       = $Param{User} || {};
    my $Preference = $Param{Preference} || $Self->_UserPreferenceGet( User => $User );
    my $StartPage  = $Preference->{start_page} || '';

    return $StartPage if $StartPage =~ m{\A(?:Dashboard|AgentTicketList)\z};
    return 'Dashboard';
}

sub _ModuleCreate {
    my ( $Self, %Param ) = @_;

    my $ModuleName = $Param{Module} || '';

    return if !$ModuleName;
    return if $ModuleName =~ m{[^A-Za-z0-9_:]};

    my $Loaded = eval "require $ModuleName; 1;";

    if ( !$Loaded ) {
        $Self->{LastError} = $@ || "Module could not be loaded: $ModuleName";
        return;
    }

    my $Object = $ModuleName->new(
        Config  => $Self->{Config},
        DB      => $Self->{DB},
        Output  => $Self->{Output},
        Program => $Param{Program},
    );

    return $Object;
}

sub _RenderProgram {
    my ( $Self, %Param ) = @_;

    my $User       = $Param{User}       || {};
    my $Program    = $Param{Program}    || {};
    my $Template   = $Param{Template}   || '';
    my $Data       = $Param{Data}       || {};
    my $ActiveName = $Param{ActiveName} || 'Dashboard';

    my $BaseData = $Self->_BaseData(
        User        => $User,
        ActiveName  => $ActiveName,
        CurrentName => $Program->{Name} || $ActiveName,
    );

    my %RenderData = ( %{$BaseData}, %{$Data} );

    if ( !$RenderData{PageTitle} ) {
        $RenderData{PageTitle} = $Program->{Title} ? 'Translate:' . $Program->{Title} : $Program->{Name};
    }

    my $Body = $Self->{Output}->Render(
        Template => $Template,
        Data     => \%RenderData,
    );

    if ( !defined $Body ) {
        return $Self->{Output}->Response(
            Status => '500 Internal Server Error',
            Body   => 'Qisutu page could not be rendered.',
        );
    }

    return $Self->{Output}->Response(
        Body => $Body,
    );
}

sub _RenderError {
    my ( $Self, %Param ) = @_;

    my $User       = $Param{User}       || {};
    my $Status     = $Param{Status}     || '500 Internal Server Error';
    my $Title      = $Param{Title}      || 'Translate:ErrorTitle';
    my $Message    = $Param{Message}    || 'Translate:ErrorText';
    my $ActiveName = $Param{ActiveName} || 'Dashboard';

    return $Self->_RenderProgram(
        User       => $User,
        Program    => {
            Name  => $ActiveName,
            Title => 'ErrorTitle',
        },
        Template   => 'Error.tt',
        ActiveName => $ActiveName,
        Data       => {
            PageTitle    => $Title,
            ErrorTitle   => $Title,
            ErrorMessage => $Message,
            Status       => $Status,
        },
    );
}

sub _BaseData {
    my ( $Self, %Param ) = @_;

    my $User       = $Param{User}       || {};
    my $ActiveName = $Param{ActiveName} || 'Dashboard';
    my $CurrentName = $Param{CurrentName} || $ActiveName;
    my $Language   = $Self->_DefaultLanguage();
    my $Timezone   = 'Europe/Berlin';
    my $Preference = $Self->_UserPreferenceGet( User => $User );

    if ( $Preference->{language} ) {
        $Language = $Preference->{language};
    }

    if ( $Preference->{timezone} ) {
        $Timezone = $Preference->{timezone};
    }

    my $Name       = $Self->_UserDisplayName( User => $User );

    return {
        Language           => $Language,
        UserTimezone       => $Timezone,
        Robots             => 'noindex, nofollow',
        StaticBase         => $Self->{Config}->{Paths}->{StaticURL} || '/static',
        PageCSS            => 'qisutu.css',
        BodyClass          => 'qisutu-app-page',
        SystemName         => $Self->{Config}->{System}->{Name} || 'Qisutu',
        SystemVersion      => $Self->{Config}->{System}->{Version} || '',
        UserDisplayName    => $Name,
        UserInitials       => $Self->_Initials( Name => $Name ),
        UserHasPreferences => ( ( $User->{account_type} || '' ) =~ m{\A(?:agent|customer)\z} ? 1 : 0 ),
        UserPreferencesURL  => ( ( $User->{account_type} || '' ) eq 'customer' ? 'index.pl?Page=CustomerPreferences' : 'index.pl?Page=AgentPreferences' ),
        UserPreferencesTitle => ( ( $User->{account_type} || '' ) eq 'customer' ? 'Translate:CustomerPreferencesTitle' : 'Translate:AgentPreferencesTitle' ),
        CSRFToken          => $User->{csrf_token} || '',
        NavigationHTML     => $Self->{ProgramRegistry}->NavigationHTML(
            Language    => $Language,
            ActiveName  => $ActiveName,
            CurrentName => $CurrentName,
            User        => $User,
        ),
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

sub _UserPreferenceGet {
    my ( $Self, %Param ) = @_;

    my $User = $Param{User} || {};

    return {} if !$User->{user_account_id};
    return {} if ( $User->{account_type} || '' ) !~ m{\A(?:agent|customer)\z};

    my $Loaded = eval {
        require QisutuUserPreference;
        1;
    };

    return {} if !$Loaded;

    my $PreferenceObject = QisutuUserPreference->new(
        Config => $Self->{Config},
        DB     => $Self->{DB},
    );

    if ( ( $User->{account_type} || '' ) eq 'customer' ) {
        return $PreferenceObject->CustomerPreferenceGet(
            UserAccountID => $User->{user_account_id},
        ) || {};
    }

    return $PreferenceObject->AgentPreferenceGet(
        UserAccountID => $User->{user_account_id},
    ) || {};
}

sub _ActiveName {
    my ( $Self, %Param ) = @_;

    my $Program = $Param{Program} || {};

    if ( ( $Program->{Type} || '' ) ne 'MainNavigation' && $Program->{Parent} ) {
        return $Program->{Parent};
    }

    return $Program->{Name} || 'Dashboard';
}

sub _UserDisplayName {
    my ( $Self, %Param ) = @_;

    my $User      = $Param{User} || {};
    my $Firstname = $User->{firstname} || '';
    my $Lastname  = $User->{lastname}  || '';
    my $Login     = $User->{login}     || '';
    my $Name      = join ' ', grep {$_} ( $Firstname, $Lastname );

    if ( !$Name ) {
        $Name = $Login;
    }

    return $Name;
}

sub _Initials {
    my ( $Self, %Param ) = @_;

    my $Name     = $Param{Name} || '';
    my @Parts    = grep {$_} split /\s+/, $Name;
    my $Initials = '';

    for my $Part (@Parts) {
        $Initials .= substr( $Part, 0, 1 );
        last if length $Initials >= 2;
    }

    if ( !$Initials ) {
        $Initials = 'Q';
    }

    return uc $Initials;
}

sub _PermissionCheck {
    my ( $Self, %Param ) = @_;

    my $Program = $Param{Program} || {};
    my $User    = $Param{User}    || {};

    if ( exists $Program->{VisibleFor} ) {
        return $Self->_VisibleForCheck(
            Program => $Program,
            User    => $User,
        );
    }

    my $Permission = $Self->_ProgramPermission( Program => $Program );
    my $UserAccessType = $Self->_UserAccessType( User => $User );

    return if !$Self->_ProgramAccessTypeAllowed(
        Program        => $Program,
        UserAccessType => $UserAccessType,
    );

    return 1 if !$Permission || $UserAccessType ne 'agent';

    my $Loaded = eval {
        require QisutuPermission;
        1;
    };

    return if !$Loaded;

    my $PermissionObject = QisutuPermission->new(
        Config => $Self->{Config},
        DB     => $Self->{DB},
    );

    return $PermissionObject->UserPermissionCheck(
        UserID     => $User->{user_account_id},
        Permission => $Permission,
    );
}

sub _VisibleForCheck {
    my ( $Self, %Param ) = @_;

    my $Program        = $Param{Program} || {};
    my $User           = $Param{User}    || {};
    my $UserAccessType = $Self->_UserAccessType( User => $User );
    my %VisibleFor     = map { $_ => 1 } @{ $Self->_ProgramVisibleFor( Program => $Program ) };

    return 1 if !$UserAccessType && $VisibleFor{anonymous};
    return 1 if $UserAccessType eq 'customer' && $VisibleFor{customer};
    return 1 if $UserAccessType eq 'agent' && $VisibleFor{agent};

    if ( $UserAccessType eq 'agent' && $VisibleFor{admin} ) {
        my $Loaded = eval {
            require QisutuPermission;
            1;
        };

        return if !$Loaded;

        my $PermissionObject = QisutuPermission->new(
            Config => $Self->{Config},
            DB     => $Self->{DB},
        );

        return $PermissionObject->UserIsAdmin(
            UserID => $User->{user_account_id},
        );
    }

    return;
}

sub _ProgramVisibleFor {
    my ( $Self, %Param ) = @_;

    my $Program = $Param{Program} || {};
    my @VisibleFor;

    if ( ref $Program->{VisibleFor} eq 'ARRAY' ) {
        @VisibleFor = @{ $Program->{VisibleFor} };
    }
    elsif ( defined $Program->{VisibleFor} && $Program->{VisibleFor} ne '' ) {
        @VisibleFor = split m{\s*,\s*|\s+}, $Program->{VisibleFor};
    }

    @VisibleFor = grep { $_ && m{\A(?:anonymous|customer|agent|admin)\z} } @VisibleFor;

    if ( !@VisibleFor ) {
        my @AccessTypes = @{ $Self->_ProgramAccessTypes( Program => $Program ) };
        @VisibleFor = map { $_ eq 'agent' && ( $Program->{Permission} || '' ) eq 'admin.view' ? 'admin' : $_ } @AccessTypes;
    }

    @VisibleFor = ('anonymous') if grep { $_ eq 'anonymous' } @VisibleFor;

    my %Seen;
    return [ grep { !$Seen{$_}++ } @VisibleFor ];
}

sub _ProgramAccessTypeAllowed {

    my ( $Self, %Param ) = @_;

    my $Program        = $Param{Program} || {};
    my $UserAccessType = $Param{UserAccessType} || '';
    my %Allowed        = map { $_ => 1 } @{ $Self->_ProgramAccessTypes( Program => $Program ) };

    return 1 if !$UserAccessType && $Allowed{anonymous};
    return 1 if $Allowed{anonymous};
    return 1 if $Allowed{$UserAccessType};

    return;
}

sub _ProgramAccessTypes {
    my ( $Self, %Param ) = @_;

    my $Program = $Param{Program} || {};
    my @AccessTypes;

    if ( ref $Program->{AccessTypes} eq 'ARRAY' ) {
        @AccessTypes = @{ $Program->{AccessTypes} };
    }
    elsif ( defined $Program->{AccessType} && $Program->{AccessType} ne '' ) {
        @AccessTypes = split m{\s*,\s*|\s+}, $Program->{AccessType};
    }

    @AccessTypes = grep { $_ && m{\A(?:anonymous|agent|customer|system)\z} } @AccessTypes;

    if ( !@AccessTypes ) {
        @AccessTypes = $Program->{Permission} || $Program->{PermissionGroup} ? ('agent') : ('anonymous');
    }

    my %Seen;
    return [ grep { !$Seen{$_}++ } @AccessTypes ];
}

sub _UserAccessType {
    my ( $Self, %Param ) = @_;

    my $User = $Param{User} || {};

    return $User->{account_type} if ( $User->{account_type} || '' ) =~ m{\A(?:agent|customer)\z};
    return 'system' if $User->{is_system_user};
    return 'customer' if $User->{customer_user_id};
    return 'customer' if $Self->_UserIsCustomer( User => $User );
    return 'agent' if $User->{user_account_id};

    return '';
}

sub _UserIsCustomer {
    my ( $Self, %Param ) = @_;

    my $UserID = ( $Param{User} || {} )->{user_account_id} || 0;

    return if !$Self->{DB};
    return if $UserID !~ m{\A\d+\z} || !$UserID;

    my $Row = $Self->{DB}->SelectRow(
        'SELECT 1 AS is_customer
         FROM customer_user cu
         INNER JOIN customer c
            ON c.id = cu.customer_id
         WHERE cu.user_account_id = ?
            AND cu.active = 1
            AND c.active = 1
         LIMIT 1',
        $UserID,
    );

    return $Row ? 1 : 0;
}

sub _ProgramPermission {
    my ( $Self, %Param ) = @_;

    my $Program = $Param{Program} || {};

    return $Program->{Permission} if $Program->{Permission};

    return if !$Program->{PermissionGroup} || !$Program->{PermissionMode};

    my $Mode = $Program->{PermissionMode};

    $Mode = 'view' if $Mode eq 'ro';
    $Mode = 'edit' if $Mode eq 'rw';

    return $Program->{PermissionGroup} . '.' . $Mode;
}

sub Error {
    my ($Self) = @_;

    return $Self->{LastError};
}

1;
