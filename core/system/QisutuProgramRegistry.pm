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

package QisutuProgramRegistry;

use strict;
use warnings;
use utf8;

use File::Spec;
use JSON::PP;

sub new {
    my ( $Class, %Param ) = @_;

    my $Self = {
        Config    => $Param{Config},
        DB        => $Param{DB},
        Output    => $Param{Output},
        Programs  => undef,
        LastError => '',
    };

    bless $Self, $Class;

    return $Self;
}

sub Programs {
    my ($Self) = @_;

    if ( $Self->{Programs} ) {
        return $Self->{Programs};
    }

    my $Path = $Self->{Config}->{Paths}->{ProgramConfig};

    if ( !$Path ) {
        $Path = File::Spec->catdir( $Self->{Config}->{Paths}->{Config}, 'programs' );
    }

    if ( !-d $Path ) {
        $Self->{LastError} = "Program config path not found: $Path";
        $Self->{Programs} = [];
        return $Self->{Programs};
    }

    my @Programs;

    my $DirectoryHandle;

    if ( !opendir $DirectoryHandle, $Path ) {
        $Self->{LastError} = "Could not open program config path: $Path";
        $Self->{Programs} = [];
        return $Self->{Programs};
    }

    my @Files = sort grep { $_ =~ m{\.pm\z} } readdir $DirectoryHandle;

    closedir $DirectoryHandle;

    for my $File (@Files) {
        my $FullPath = File::Spec->catfile( $Path, $File );
        my $Program  = do $FullPath;

        next if !$Program;
        next if ref $Program ne 'HASH';
        next if !$Program->{Name};

        $Program->{Active} = 1 if !exists $Program->{Active};
        $Program->{Type} ||= 'ProgramOnly';
        $Program->{Order} ||= 0;
        $Program->{Icon}  ||= '';
        $Program->{URL}   ||= 'index.pl';

        push @Programs, $Program;
    }

    my %ProgramName = map { ( $_->{Name} || '' ) => 1 } @Programs;
    my $Runtime = $Self->{Config}->{AddonRuntime} || {};
    for my $AddonPath ( @{ $Runtime->{ProgramPaths} || [] } ) {
        next if !$AddonPath || !-d $AddonPath || -l $AddonPath;
        opendir my $AddonDirectoryHandle, $AddonPath or next;
        my @AddonFiles = sort grep { m{\.json\z} } readdir $AddonDirectoryHandle;
        closedir $AddonDirectoryHandle;

        for my $File (@AddonFiles) {
            my $FullPath = File::Spec->catfile( $AddonPath, $File );
            next if !-f $FullPath || -l $FullPath;
            open my $Handle, '<:raw', $FullPath or next;
            local $/;
            my $Content = <$Handle>;
            close $Handle;
            my $Program = eval { JSON::PP->new->utf8(1)->decode($Content) };
            next if !$Program || ref $Program ne 'HASH';
            next if ( $Program->{Name} || '' ) !~ m{\A[A-Za-z][A-Za-z0-9_]{1,99}\z};
            next if ( $Program->{Module} || '' ) !~ m{\AQisutu::Addon::[A-Za-z0-9_:]+\z};
            next if $ProgramName{ $Program->{Name} }++;
            next if ( $Program->{URL} || '' ) !~ m{\Aindex\.pl\?Page=[A-Za-z][A-Za-z0-9_]*(?:[;&][A-Za-z0-9_.%-]+=[A-Za-z0-9_.%-]*)*\z};
            $Program->{ManagedByAddon} = 1;
            $Program->{Active} = 1 if !exists $Program->{Active};
            $Program->{Type} ||= 'ProgramOnly';
            $Program->{Order} ||= 0;
            $Program->{Icon}  ||= '';
            push @Programs, $Program;
        }
    }

    @Programs = sort {
        ( $a->{Order} || 0 ) <=> ( $b->{Order} || 0 )
            || ( $a->{Name} || '' ) cmp ( $b->{Name} || '' )
    } @Programs;

    $Self->{Programs} = \@Programs;

    return $Self->{Programs};
}

sub MainNavigation {
    my ($Self) = @_;

    my $Programs = $Self->Programs();
    my @Navigation;

    for my $Program ( @{$Programs} ) {
        next if !$Program->{Active};
        next if ( $Program->{Type} || '' ) ne 'MainNavigation';

        push @Navigation, $Program;
    }

    return \@Navigation;
}

sub SubNavigation {
    my ( $Self, %Param ) = @_;

    my $Parent = $Param{Parent} || '';

    return [] if !$Parent;

    my $Programs = $Self->Programs();
    my @Navigation;

    for my $Program ( @{$Programs} ) {
        next if !$Program->{Active};
        next if ( $Program->{Type} || '' ) ne 'SubNavigation';
        next if ( $Program->{Parent} || '' ) ne $Parent;

        push @Navigation, $Program;
    }

    return \@Navigation;
}

sub ProgramGet {
    my ( $Self, %Param ) = @_;

    my $Name = $Param{Name} || '';

    return if !$Name;

    my $Programs = $Self->Programs();

    for my $Program ( @{$Programs} ) {
        next if ( $Program->{Name} || '' ) ne $Name;

        return $Program;
    }

    return;
}

sub NavigationHTML {
    my ( $Self, %Param ) = @_;

    my $Language   = $Param{Language}   || $Self->{Config}->{Language}->{Default} || 'en';
    my $ActiveName = $Param{ActiveName} || 'Dashboard';
    my $CurrentName = $Param{CurrentName} || $ActiveName;
    my $User       = $Param{User}       || {};
    my $Output     = $Self->{Output};

    my $Navigation = $Self->MainNavigation();
    my $HTML       = '';

    for my $Program ( @{$Navigation} ) {
        next if !$Self->_ProgramAllowed(
            Program => $Program,
            User    => $User,
        );

        my $Name  = $Program->{Name}  || '';
        my $Title = $Program->{Title} || $Name;
        my $Icon  = $Program->{Icon}  || '';
        my $URL   = $Program->{URL}   || 'index.pl';
        my $SubNavigation = $Self->SubNavigation( Parent => $Name );
        my @VisibleSubNavigation;

        for my $SubProgram ( @{$SubNavigation} ) {
            next if !$Self->_ProgramAllowed(
                Program => $SubProgram,
                User    => $User,
            );

            push @VisibleSubNavigation, $SubProgram;
        }

        $SubNavigation = \@VisibleSubNavigation;
        my $HasSubNavigation = @{$SubNavigation} ? 1 : 0;

        my $Class = 'qisutu-nav-item';

        if ( $Name eq $ActiveName ) {
            $Class .= ' qisutu-nav-item-active';
        }

        if ($HasSubNavigation) {
            $Class .= ' qisutu-nav-item-parent';
        }

        my $TitleText = $Output->Translate(
            Key      => $Title,
            Language => $Language,
        );

        if ($HasSubNavigation) {
            my $GroupClass = 'qisutu-nav-group';

            if ( $Name eq $ActiveName ) {
                $GroupClass .= ' qisutu-nav-group-active';
            }

            my $SubClass = 'qisutu-subnav';

            if ( $Name eq $ActiveName ) {
                $SubClass .= ' qisutu-subnav-open';
            }

            $HTML .= '<div class="' . $Output->HTMLEscape($GroupClass) . '">' . "\n";
            $HTML .= '<div class="' . $Output->HTMLEscape($Class) . '" role="button" tabindex="0" aria-haspopup="true" aria-expanded="false" title="' . $Output->HTMLEscape($TitleText) . '" aria-label="' . $Output->HTMLEscape($TitleText) . '">';
            $HTML .= '<span class="qisutu-nav-icon" aria-hidden="true">' . $Output->HTMLEscape($Icon) . '</span>';
            $HTML .= '<span class="qisutu-nav-label">' . $Output->HTMLEscape($TitleText) . '</span>';
            $HTML .= '</div>' . "\n";
            $HTML .= '<div class="' . $Output->HTMLEscape($SubClass) . '" data-nav-title="' . $Output->HTMLEscape($TitleText) . '">' . "\n";

            my $PreviousAdminOrderBlock;

            for my $SubProgram ( @{$SubNavigation} ) {
                if ( $Name eq 'Admin' ) {
                    my $AdminOrderBlock = int( ( 0 + ( $SubProgram->{Order} || 0 ) ) / 100 );

                    if (
                        defined $PreviousAdminOrderBlock
                        && $AdminOrderBlock != $PreviousAdminOrderBlock
                    ) {
                        $HTML .= '<div class="qisutu-subnav-separator" role="separator" aria-hidden="true"></div>' . "\n";
                    }

                    $PreviousAdminOrderBlock = $AdminOrderBlock;
                }

                my $SubName  = $SubProgram->{Name}  || '';
                my $SubTitle = $SubProgram->{Title} || $SubName;
                my $SubURL   = $SubProgram->{URL}   || 'index.pl';
                my $SubItemClass = 'qisutu-subnav-item';

                if ( $SubName eq $CurrentName ) {
                    $SubItemClass .= ' qisutu-subnav-item-active';
                }

                my $SubTitleText = $Output->Translate(
                    Key      => $SubTitle,
                    Language => $Language,
                );

                $HTML .= '<a class="' . $Output->HTMLEscape($SubItemClass) . '" href="' . $Output->HTMLEscape($SubURL) . '">';
                $HTML .= '<span class="qisutu-subnav-label">' . $Output->HTMLEscape($SubTitleText) . '</span>';
                $HTML .= '</a>' . "\n";
            }

            $HTML .= '</div>' . "\n";
            $HTML .= '</div>' . "\n";
        }
        else {
            $HTML .= '<a class="' . $Output->HTMLEscape($Class) . '" href="' . $Output->HTMLEscape($URL) . '" title="' . $Output->HTMLEscape($TitleText) . '" aria-label="' . $Output->HTMLEscape($TitleText) . '">';
            $HTML .= '<span class="qisutu-nav-icon" aria-hidden="true">' . $Output->HTMLEscape($Icon) . '</span>';
            $HTML .= '<span class="qisutu-nav-label">' . $Output->HTMLEscape($TitleText) . '</span>';
            $HTML .= '</a>' . "\n";
        }
    }

    return $HTML;
}

sub _ProgramAllowed {
    my ( $Self, %Param ) = @_;

    my $Program = $Param{Program} || {};
    my $User    = $Param{User}    || {};

    if ( exists $Program->{VisibleFor} ) {
        return $Self->_ProgramVisibleForAllowed(
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
    return 1 if !$Self->{DB};

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

sub _ProgramVisibleForAllowed {
    my ( $Self, %Param ) = @_;

    my $Program        = $Param{Program} || {};
    my $User           = $Param{User}    || {};
    my $UserAccessType = $Self->_UserAccessType( User => $User );
    my %VisibleFor     = map { $_ => 1 } @{ $Self->_ProgramVisibleFor( Program => $Program ) };

    return 1 if !$UserAccessType && $VisibleFor{anonymous};
    return 1 if $UserAccessType eq 'customer' && $VisibleFor{customer};
    return 1 if $UserAccessType eq 'agent' && $VisibleFor{agent};

    if ( $UserAccessType eq 'agent' && $VisibleFor{admin} ) {
        return 1 if !$Self->{DB};

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
