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

package AdminGroups;

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
    my $Admin   = $Self->_AdminObject();

    if ( $Admin && ( $Request->{Step} || '' ) eq 'GroupCreate' ) {
        $Admin->GroupCreate(
            Name            => $Request->{Name},
            Title           => $Request->{Title},
            GroupType       => $Request->{GroupType},
            SortOrder       => $Request->{SortOrder},
            ChangedByUserID => $User->{user_account_id},
        );

        return { Redirect => 'index.pl?Page=AdminGroups' } if !$Admin->Error();
    }
    elsif ( $Admin && ( $Request->{Step} || '' ) eq 'GroupDeactivate' ) {
        $Admin->GroupDeactivate(
            GroupID         => $Request->{GroupID},
            ChangedByUserID => $User->{user_account_id},
        );

        return { Redirect => 'index.pl?Page=AdminGroups' } if !$Admin->Error();
    }
    elsif ( $Admin && ( $Request->{Step} || '' ) eq 'AgentGroupMatrixUpdate' ) {
        $Self->_UserGroupMatrixUpdate(
            Admin           => $Admin,
            Request         => $Request,
            GroupList       => $Admin->GroupList(),
            UserAccountID   => $Request->{UserAccountID},
            LevelPrefix     => 'PermissionLevel',
            UserType        => 'agent',
            ChangedByUserID => $User->{user_account_id},
        );

        return { Redirect => 'index.pl?Page=AdminGroups;Action=Agent;UserAccountID=' . ( $Request->{UserAccountID} || 0 ) } if !$Admin->Error();
    }
    elsif ( $Admin && ( $Request->{Step} || '' ) eq 'CustomerUserGroupMatrixUpdate' ) {
        $Self->_UserGroupMatrixUpdate(
            Admin           => $Admin,
            Request         => $Request,
            GroupList       => $Admin->GroupList(),
            UserAccountID   => $Request->{UserAccountID},
            LevelPrefix     => 'CustomerPermissionLevel',
            UserType        => 'customer',
            ChangedByUserID => $User->{user_account_id},
        );

        return { Redirect => 'index.pl?Page=AdminGroups;Action=CustomerUser;UserAccountID=' . ( $Request->{UserAccountID} || 0 ) } if !$Admin->Error();
    }
    elsif ( $Admin && ( $Request->{Step} || '' ) eq 'GroupAgentMatrixUpdate' ) {
        $Self->_GroupUserMatrixUpdate(
            Admin           => $Admin,
            Request         => $Request,
            UserList        => $Admin->AgentList(),
            GroupID         => $Request->{GroupID},
            LevelPrefix     => 'PermissionLevel',
            UserType        => 'agent',
            ChangedByUserID => $User->{user_account_id},
        );

        return { Redirect => 'index.pl?Page=AdminGroups;Action=Group;GroupID=' . ( $Request->{GroupID} || 0 ) } if !$Admin->Error();
    }
    elsif ( $Admin && ( $Request->{Step} || '' ) eq 'GroupCustomerUserMatrixUpdate' ) {
        $Self->_GroupUserMatrixUpdate(
            Admin           => $Admin,
            Request         => $Request,
            UserList        => $Admin->CustomerUserList(),
            GroupID         => $Request->{GroupID},
            LevelPrefix     => 'CustomerPermissionLevel',
            UserType        => 'customer',
            ChangedByUserID => $User->{user_account_id},
        );

        return { Redirect => 'index.pl?Page=AdminGroups;Action=Group;GroupID=' . ( $Request->{GroupID} || 0 ) } if !$Admin->Error();
    }

    my $Action           = $Request->{Action} || 'List';
    my $GroupList        = $Admin ? $Admin->GroupList() : [];
    my $AgentList        = $Admin ? $Admin->AgentList() : [];
    my $CustomerUserList = $Admin ? $Admin->CustomerUserList() : [];
    my $Group;
    my $Agent;
    my $CustomerUser;
    my $AgentGroupMatrix        = [];
    my $CustomerUserGroupMatrix = [];
    my $GroupAgentMatrix        = [];
    my $GroupCustomerUserMatrix = [];

    if ( $Admin && $Action eq 'Agent' ) {
        $Agent = $Admin->AgentGet( UserAccountID => $Request->{UserAccountID} );
        if ($Agent) {
            $AgentGroupMatrix = $Self->_UserGroupMatrixBuild(
                Admin       => $Admin,
                User        => $Agent,
                GroupList   => $GroupList,
                UserType    => 'agent',
                LevelPrefix => 'PermissionLevel',
            );
        }
        else {
            $Action = 'List';
        }
    }
    elsif ( $Admin && $Action eq 'CustomerUser' ) {
        $CustomerUser = $Self->_CustomerUserGetByUserAccountID(
            Admin         => $Admin,
            UserAccountID => $Request->{UserAccountID},
        );
        if ($CustomerUser) {
            $CustomerUserGroupMatrix = $Self->_UserGroupMatrixBuild(
                Admin       => $Admin,
                User        => $CustomerUser,
                GroupList   => $GroupList,
                UserType    => 'customer',
                LevelPrefix => 'CustomerPermissionLevel',
            );
        }
        else {
            $Action = 'List';
        }
    }
    elsif ( $Admin && $Action eq 'Group' ) {
        $Group = $Admin->GroupGet( GroupID => $Request->{GroupID} );
        if ($Group) {
            $GroupAgentMatrix = $Self->_GroupUserMatrixBuild(
                Admin       => $Admin,
                Group       => $Group,
                UserList    => $AgentList,
                UserType    => 'agent',
                LevelPrefix => 'PermissionLevel',
            );
            $GroupCustomerUserMatrix = $Self->_GroupUserMatrixBuild(
                Admin       => $Admin,
                Group       => $Group,
                UserList    => $CustomerUserList,
                UserType    => 'customer',
                LevelPrefix => 'CustomerPermissionLevel',
            );
        }
        else {
            $Action = 'List';
        }
    }

    my $ErrorMessage = $Admin ? $Admin->Error() : '';

    return {
        Template => 'AdminGroups.tt',
        Data     => {
            PageTitle          => 'Translate:AdminGroupsTitle',
            ProgramTitle       => 'Translate:AdminGroupsTitle',
            ProgramDescription => 'Translate:AdminGroupsDescription',
            GroupList          => $GroupList,
            AgentList          => $AgentList,
            CustomerUserList   => $CustomerUserList,
            GroupCount         => scalar @{$GroupList},
            AgentCount         => scalar @{$AgentList},
            CustomerUserCount  => scalar @{$CustomerUserList},
            ShowList           => $Action eq 'List' ? 1 : 0,
            ShowAgent          => $Action eq 'Agent' ? 1 : 0,
            ShowCustomerUser   => $Action eq 'CustomerUser' ? 1 : 0,
            ShowGroup          => $Action eq 'Group' ? 1 : 0,
            GroupID            => $Group ? $Group->{id} : '',
            GroupName          => $Group ? $Group->{name} : '',
            GroupTitle         => $Group ? $Group->{title} : '',
            GroupType          => $Group ? $Group->{group_type} : '',
            UserAccountID      => $Agent ? $Agent->{id} : $CustomerUser ? $CustomerUser->{user_account_id} : '',
            AgentLogin         => $Agent ? $Agent->{login} : '',
            AgentName          => $Agent ? $Self->_AgentLabel( Agent => $Agent ) : '',
            CustomerUserName   => $CustomerUser ? $Self->_CustomerUserLabel( CustomerUser => $CustomerUser ) : '',
            AgentGroupMatrix        => $AgentGroupMatrix,
            CustomerUserGroupMatrix => $CustomerUserGroupMatrix,
            GroupAgentMatrix        => $GroupAgentMatrix,
            GroupCustomerUserMatrix => $GroupCustomerUserMatrix,
            ErrorMessage       => $ErrorMessage,
            ErrorClass         => $ErrorMessage ? '' : 'qisutu-hidden',
            FormAction         => 'index.pl',
        },
    };
}

sub _AdminObject {
    my ($Self) = @_;

    return if !$Self->{DB};

    my $Loaded = eval {
        require QisutuAdmin;
        1;
    };

    return if !$Loaded;

    return QisutuAdmin->new(
        Config => $Self->{Config},
        DB     => $Self->{DB},
    );
}

sub _UserGroupMatrixBuild {
    my ( $Self, %Param ) = @_;

    my $Admin       = $Param{Admin};
    my $User        = $Param{User} || {};
    my $GroupList   = $Param{GroupList} || [];
    my $UserType    = $Param{UserType} || 'agent';
    my $LevelPrefix = $Param{LevelPrefix} || 'PermissionLevel';
    my $UserAccountID = $UserType eq 'customer' ? ( $User->{user_account_id} || 0 ) : ( $User->{id} || 0 );
    my $Current     = $Admin->UserGroupList( UserAccountID => $UserAccountID );
    my %CurrentByGroupID = map { $_->{user_group_id} => $_ } @{$Current};
    my @Matrix;

    for my $Group ( @{$GroupList} ) {
        my $CurrentGroup = $CurrentByGroupID{ $Group->{id} } || {};
        my $Level = $UserType eq 'customer'
            ? $Self->_CustomerPermissionLevelFromRow( Row => $CurrentGroup )
            : $Self->_AgentPermissionLevelFromRow( Row => $CurrentGroup );

        push @Matrix, {
            group_id                 => $Group->{id},
            group_name               => $Group->{name},
            group_title              => $Group->{title},
            permission_level_options => $Self->_PermissionLevelOptionsHTML(
                Name     => $LevelPrefix . '_' . $Group->{id},
                Selected => $Level,
                UserType => $UserType,
            ),
        };
    }

    return \@Matrix;
}

sub _GroupUserMatrixBuild {
    my ( $Self, %Param ) = @_;

    my $Admin       = $Param{Admin};
    my $Group       = $Param{Group} || {};
    my $UserList    = $Param{UserList} || [];
    my $UserType    = $Param{UserType} || 'agent';
    my $LevelPrefix = $Param{LevelPrefix} || 'PermissionLevel';
    my @Matrix;

    for my $User ( @{$UserList} ) {
        my $UserAccountID = $UserType eq 'customer' ? ( $User->{user_account_id} || 0 ) : ( $User->{id} || 0 );
        my $Current       = $Admin->UserGroupList( UserAccountID => $UserAccountID );
        my %CurrentByGroupID = map { $_->{user_group_id} => $_ } @{$Current};
        my $CurrentGroup = $CurrentByGroupID{ $Group->{id} } || {};
        my $Level = $UserType eq 'customer'
            ? $Self->_CustomerPermissionLevelFromRow( Row => $CurrentGroup )
            : $Self->_AgentPermissionLevelFromRow( Row => $CurrentGroup );

        push @Matrix, {
            user_account_id          => $UserAccountID,
            user_label               => $UserType eq 'customer'
                ? $Self->_CustomerUserLabel( CustomerUser => $User )
                : $Self->_AgentLabel( Agent => $User ),
            permission_level_options => $Self->_PermissionLevelOptionsHTML(
                Name     => $LevelPrefix . '_' . $UserAccountID,
                Selected => $Level,
                UserType => $UserType,
            ),
        };
    }

    return \@Matrix;
}

sub _UserGroupMatrixUpdate {
    my ( $Self, %Param ) = @_;

    my $Admin           = $Param{Admin};
    my $Request         = $Param{Request} || {};
    my $GroupList       = $Param{GroupList} || [];
    my $UserAccountID   = $Param{UserAccountID} || 0;
    my $LevelPrefix     = $Param{LevelPrefix} || 'PermissionLevel';
    my $UserType        = $Param{UserType} || 'agent';
    my $ChangedByUserID = $Param{ChangedByUserID} || 1;

    return if $UserAccountID !~ m{\A\d+\z} || !$UserAccountID;

    for my $Group ( @{$GroupList} ) {
        my $GroupID = $Group->{id};
        my %Permission = $Self->_PermissionFromLevel(
            Level    => $Request->{ $LevelPrefix . '_' . $GroupID },
            UserType => $UserType,
        );

        if ( $Permission{HasPermission} ) {
            $Admin->UserGroupAdd(
                UserAccountID      => $UserAccountID,
                GroupID            => $GroupID,
                PermissionRead     => $Permission{PermissionRead},
                PermissionCreate   => $Permission{PermissionCreate},
                PermissionChange   => $Permission{PermissionChange},
                PermissionOverview => $Permission{PermissionOverview},
                PermissionFull     => $Permission{PermissionFull},
                ChangedByUserID    => $ChangedByUserID,
            );
        }
        else {
            $Admin->UserGroupRemove(
                UserAccountID   => $UserAccountID,
                GroupID         => $GroupID,
                ChangedByUserID => $ChangedByUserID,
            );
        }

        last if $Admin->Error();
    }

    return 1;
}

sub _GroupUserMatrixUpdate {
    my ( $Self, %Param ) = @_;

    my $Admin           = $Param{Admin};
    my $Request         = $Param{Request} || {};
    my $UserList        = $Param{UserList} || [];
    my $GroupID         = $Param{GroupID} || 0;
    my $LevelPrefix     = $Param{LevelPrefix} || 'PermissionLevel';
    my $UserType        = $Param{UserType} || 'agent';
    my $ChangedByUserID = $Param{ChangedByUserID} || 1;

    return if $GroupID !~ m{\A\d+\z} || !$GroupID;

    for my $User ( @{$UserList} ) {
        my $UserAccountID = $UserType eq 'customer' ? ( $User->{user_account_id} || 0 ) : ( $User->{id} || 0 );
        my %Permission = $Self->_PermissionFromLevel(
            Level    => $Request->{ $LevelPrefix . '_' . $UserAccountID },
            UserType => $UserType,
        );

        if ( $Permission{HasPermission} ) {
            $Admin->UserGroupAdd(
                UserAccountID      => $UserAccountID,
                GroupID            => $GroupID,
                PermissionRead     => $Permission{PermissionRead},
                PermissionCreate   => $Permission{PermissionCreate},
                PermissionChange   => $Permission{PermissionChange},
                PermissionOverview => $Permission{PermissionOverview},
                PermissionFull     => $Permission{PermissionFull},
                ChangedByUserID    => $ChangedByUserID,
            );
        }
        else {
            $Admin->UserGroupRemove(
                UserAccountID   => $UserAccountID,
                GroupID         => $GroupID,
                ChangedByUserID => $ChangedByUserID,
            );
        }

        last if $Admin->Error();
    }

    return 1;
}

sub _PermissionFromLevel {
    my ( $Self, %Param ) = @_;

    my $Level    = $Param{Level} || 'none';
    my $UserType = $Param{UserType} || 'agent';

    if ( $UserType eq 'customer' ) {
        return (
            PermissionRead     => 1,
            PermissionCreate   => 1,
            PermissionChange   => 1,
            PermissionOverview => 0,
            PermissionFull     => 0,
            HasPermission      => 1,
        ) if $Level eq 'own';

        return (
            PermissionRead     => 1,
            PermissionCreate   => 1,
            PermissionChange   => 1,
            PermissionOverview => 1,
            PermissionFull     => 0,
            HasPermission      => 1,
        ) if $Level eq 'organization';
    }
    else {
        return (
            PermissionRead     => 1,
            PermissionCreate   => 0,
            PermissionChange   => 0,
            PermissionOverview => 1,
            PermissionFull     => 0,
            HasPermission      => 1,
        ) if $Level eq 'read';

        return (
            PermissionRead     => 1,
            PermissionCreate   => 1,
            PermissionChange   => 1,
            PermissionOverview => 1,
            PermissionFull     => 0,
            HasPermission      => 1,
        ) if $Level eq 'work';

        return (
            PermissionRead     => 1,
            PermissionCreate   => 1,
            PermissionChange   => 1,
            PermissionOverview => 1,
            PermissionFull     => 1,
            HasPermission      => 1,
        ) if $Level eq 'full';
    }

    return (
        PermissionRead     => 0,
        PermissionCreate   => 0,
        PermissionChange   => 0,
        PermissionOverview => 0,
        PermissionFull     => 0,
        HasPermission      => 0,
    );
}

sub _AgentPermissionLevelFromRow {
    my ( $Self, %Param ) = @_;

    my $Row = $Param{Row} || {};

    return 'full' if $Row->{permission_full};
    return 'work' if $Row->{permission_change} || $Row->{permission_create};
    return 'read' if $Row->{permission_read} || $Row->{permission_overview};

    return 'none';
}

sub _CustomerPermissionLevelFromRow {
    my ( $Self, %Param ) = @_;

    my $Row = $Param{Row} || {};

    return 'organization' if $Row->{permission_full} || $Row->{permission_overview};
    return 'own' if $Row->{permission_read} || $Row->{permission_create} || $Row->{permission_change};

    return 'none';
}

sub _PermissionLevelOptionsHTML {
    my ( $Self, %Param ) = @_;

    my $Name     = $Param{Name} || 'PermissionLevel';
    my $Selected = $Param{Selected} || 'none';
    my $UserType = $Param{UserType} || 'agent';
    my @Options;

    if ( $UserType eq 'customer' ) {
        @Options = (
            [ none         => 'No access' ],
            [ own          => 'Own tickets' ],
            [ organization => 'Organization tickets' ],
        );
    }
    else {
        @Options = (
            [ none => 'No access' ],
            [ read => 'Read' ],
            [ work => 'Work on tickets' ],
            [ full => 'Full access' ],
        );
    }

    my $HTML = '<select name="' . $Self->_Escape($Name) . '">';

    for my $Option (@Options) {
        my ( $Value, $Label ) = @{$Option};
        my $SelectedAttribute = $Value eq $Selected ? ' selected' : '';
        $HTML .= '<option value="' . $Self->_Escape($Value) . '"' . $SelectedAttribute . '>' . $Self->_Escape($Label) . '</option>';
    }

    $HTML .= '</select>';

    return $HTML;
}

sub _CustomerUserGetByUserAccountID {
    my ( $Self, %Param ) = @_;

    my $Admin         = $Param{Admin};
    my $UserAccountID = $Param{UserAccountID} || 0;

    return if $UserAccountID !~ m{\A\d+\z} || !$UserAccountID;

    my $CustomerUserList = $Admin->CustomerUserList();

    for my $CustomerUser ( @{$CustomerUserList} ) {
        return $CustomerUser if ( $CustomerUser->{user_account_id} || 0 ) == $UserAccountID;
    }

    return;
}

sub _AgentLabel {
    my ( $Self, %Param ) = @_;

    my $Agent = $Param{Agent} || {};
    my $Label = $Agent->{login} || '';
    my $Name  = join ' ', grep {$_} ( $Agent->{firstname}, $Agent->{lastname} );

    $Label .= ' (' . $Name . ')' if $Name;

    return $Label;
}

sub _CustomerUserLabel {
    my ( $Self, %Param ) = @_;

    my $CustomerUser = $Param{CustomerUser} || {};
    my $Label = $CustomerUser->{login} || '';
    my $Name  = join ' ', grep {$_} ( $CustomerUser->{firstname}, $CustomerUser->{lastname} );
    my $CustomerName = $CustomerUser->{customer_name} || '';

    $Label .= ' (' . $Name . ')' if $Name;
    $Label .= ' - ' . $CustomerName if $CustomerName;

    return $Label;
}

sub _Escape {
    my ( $Self, $Value ) = @_;

    $Value = '' if !defined $Value;

    if ( $Self->{Output} ) {
        return $Self->{Output}->HTMLEscape($Value);
    }

    $Value =~ s{&}{&amp;}g;
    $Value =~ s{<}{&lt;}g;
    $Value =~ s{>}{&gt;}g;
    $Value =~ s{"}{&quot;}g;

    return $Value;
}

1;
