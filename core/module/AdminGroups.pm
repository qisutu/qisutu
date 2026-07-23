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

use Encode qw(encode);

use constant CUSTOMER_USER_PAGE_SIZE => 25;

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
    elsif ( $Admin && ( $Request->{Step} || '' ) eq 'GroupUpdate' ) {
        $Admin->GroupUpdate(
            GroupID         => $Request->{GroupID},
            Title           => $Request->{Title},
            SortOrder       => $Request->{SortOrder},
            Active          => $Request->{Active},
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
        my $VisibleUserAccountIDs = $Self->_IDList( Value => $Request->{MatrixUserAccountIDs} );

        $Self->_GroupUserMatrixUpdate(
            Admin           => $Admin,
            Request         => $Request,
            UserList        => $Admin->CustomerUserListByUserAccountIDs(
                UserAccountIDs => $VisibleUserAccountIDs,
            ),
            GroupID         => $Request->{GroupID},
            LevelPrefix     => 'CustomerPermissionLevel',
            UserType        => 'customer',
            ChangedByUserID => $User->{user_account_id},
        );

        return {
            Redirect => $Self->_CustomerPageURL(
                Action         => 'Group',
                GroupID        => $Request->{GroupID},
                CustomerSearch => $Request->{CustomerSearch},
                CustomerPage   => $Request->{CustomerPage},
            ),
        } if !$Admin->Error();
    }

    my $Action         = $Request->{Action} || 'List';
    my $GroupList      = $Admin ? $Admin->GroupList() : [];
    for my $GroupItem ( @{$GroupList} ) {
        $GroupItem->{validity_label} = $GroupItem->{active} ? 'Translate:AdminValid' : 'Translate:AdminInvalid';
        $GroupItem->{validity_class} = $GroupItem->{active} ? 'qisutu-status-badge-active' : '';
    }
    my $AgentList      = [];
    my $CustomerUserList = [];
    my $Group;
    my $Agent;
    my $CustomerUser;
    my $AgentGroupMatrix        = [];
    my $CustomerUserGroupMatrix = [];
    my $GroupAgentMatrix        = [];
    my $GroupCustomerUserMatrix = [];

    my $CustomerSearch = $Self->_TrimValue( Value => $Request->{CustomerSearch} );
    $CustomerSearch = substr $CustomerSearch, 0, 200;
    my $CustomerPage = $Self->_PositiveInteger( Value => $Request->{CustomerPage}, Default => 1 );
    my $CustomerUserTotalCount = 0;
    my $CustomerPageCount      = 1;
    my $CustomerResultFrom     = 0;
    my $CustomerResultTo       = 0;

    if ( $Admin && $Action eq 'Agent' ) {
        $Agent = $Admin->AgentGet( UserAccountID => $Request->{UserAccountID} );
        $Action = 'List' if !$Agent;
    }
    elsif ( $Admin && $Action eq 'CustomerUser' ) {
        $CustomerUser = $Self->_CustomerUserGetByUserAccountID(
            Admin            => $Admin,
            CustomerUserList => $Admin->CustomerUserListByUserAccountIDs(
                UserAccountIDs => [ $Request->{UserAccountID} ],
            ),
            UserAccountID    => $Request->{UserAccountID},
        );
        $Action = 'List' if !$CustomerUser;
    }
    elsif ( $Admin && ( $Action eq 'Group' || $Action eq 'Edit' ) ) {
        $Group = $Admin->GroupGet( GroupID => $Request->{GroupID} );
        $Action = 'List' if !$Group;
    }

    if ( $Admin && ( $Action eq 'List' || $Action eq 'Group' ) ) {
        $AgentList = $Admin->AgentList();
        $CustomerUserTotalCount = $Admin->CustomerUserCount( Search => $CustomerSearch );
        $CustomerPageCount = int( ( $CustomerUserTotalCount + CUSTOMER_USER_PAGE_SIZE - 1 ) / CUSTOMER_USER_PAGE_SIZE );
        $CustomerPageCount = 1 if $CustomerPageCount < 1;
        $CustomerPage = $CustomerPageCount if $CustomerPage > $CustomerPageCount;

        my $Offset = ( $CustomerPage - 1 ) * CUSTOMER_USER_PAGE_SIZE;
        $CustomerUserList = $Admin->CustomerUserList(
            Search => $CustomerSearch,
            Limit  => CUSTOMER_USER_PAGE_SIZE,
            Offset => $Offset,
        );

        if ($CustomerUserTotalCount) {
            $CustomerResultFrom = $Offset + 1;
            $CustomerResultTo   = $Offset + scalar @{$CustomerUserList};
        }
    }

    if ( $Admin && $Action eq 'Agent' && $Agent ) {
        $AgentGroupMatrix = $Self->_UserGroupMatrixBuild(
            Admin       => $Admin,
            User        => $Agent,
            GroupList   => $GroupList,
            UserType    => 'agent',
            LevelPrefix => 'PermissionLevel',
        );
    }
    elsif ( $Admin && $Action eq 'CustomerUser' && $CustomerUser ) {
        $CustomerUserGroupMatrix = $Self->_UserGroupMatrixBuild(
            Admin       => $Admin,
            User        => $CustomerUser,
            GroupList   => $GroupList,
            UserType    => 'customer',
            LevelPrefix => 'CustomerPermissionLevel',
        );
    }
    elsif ( $Admin && $Action eq 'Group' && $Group ) {
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

    my $ErrorMessage = $Admin ? $Admin->Error() : '';
    my $PaginationItems = $Self->_PaginationItems(
        CurrentPage => $CustomerPage,
        PageCount   => $CustomerPageCount,
        Action      => $Action,
        GroupID     => $Group ? $Group->{id} : 0,
        Search      => $CustomerSearch,
    );

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
            CustomerUserCount  => $CustomerUserTotalCount,
            CustomerNoResults  => $CustomerUserTotalCount ? 0 : 1,
            ShowList           => $Action eq 'List' ? 1 : 0,
            ShowAgent          => $Action eq 'Agent' ? 1 : 0,
            ShowCustomerUser   => $Action eq 'CustomerUser' ? 1 : 0,
            ShowGroup          => $Action eq 'Group' ? 1 : 0,
            ShowGroupEdit      => $Action eq 'Edit' ? 1 : 0,
            GroupID            => $Group ? $Group->{id} : '',
            GroupName          => $Group ? $Group->{name} : '',
            GroupTitle         => $Group ? $Group->{title} : '',
            GroupType          => $Group ? $Group->{group_type} : '',
            GroupSortOrder     => $Group ? $Group->{sort_order} : 1000,
            GroupTypeAgentSelected => $Group && ( $Group->{group_type} || '' ) eq 'agent' ? 'selected' : '',
            GroupTypeCustomerSelected => $Group && ( $Group->{group_type} || '' ) eq 'customer' ? 'selected' : '',
            GroupTypeAdminSelected => $Group && ( $Group->{group_type} || '' ) eq 'admin' ? 'selected' : '',
            GroupValidSelected   => $Group && $Group->{active} ? 'selected' : '',
            GroupInvalidSelected => $Group && !$Group->{active} ? 'selected' : '',
            UserAccountID      => $Agent ? $Agent->{id} : $CustomerUser ? $CustomerUser->{user_account_id} : '',
            AgentLogin         => $Agent ? $Agent->{login} : '',
            AgentName          => $Agent ? $Self->_AgentLabel( Agent => $Agent ) : '',
            CustomerUserName   => $CustomerUser ? $Self->_CustomerUserLabel( CustomerUser => $CustomerUser ) : '',
            AgentGroupMatrix        => $AgentGroupMatrix,
            CustomerUserGroupMatrix => $CustomerUserGroupMatrix,
            GroupAgentMatrix        => $GroupAgentMatrix,
            GroupCustomerUserMatrix => $GroupCustomerUserMatrix,
            GroupCustomerUserIDs    => join( ',', grep {$_} map { $_->{user_account_id} || 0 } @{$CustomerUserList} ),
            CustomerSearch          => $CustomerSearch,
            CustomerPage            => $CustomerPage,
            CustomerPageCount       => $CustomerPageCount,
            CustomerHasPagination   => $CustomerPageCount > 1 ? 1 : 0,
            CustomerPaginationItems => $PaginationItems,
            CustomerPreviousURL     => $CustomerPage > 1
                ? $Self->_CustomerPageURL(
                    Action         => $Action,
                    GroupID        => $Group ? $Group->{id} : 0,
                    CustomerSearch => $CustomerSearch,
                    CustomerPage   => $CustomerPage - 1,
                )
                : '',
            CustomerNextURL         => $CustomerPage < $CustomerPageCount
                ? $Self->_CustomerPageURL(
                    Action         => $Action,
                    GroupID        => $Group ? $Group->{id} : 0,
                    CustomerSearch => $CustomerSearch,
                    CustomerPage   => $CustomerPage + 1,
                )
                : '',
            CustomerFilterResetURL => $Self->_CustomerPageURL(
                Action       => $Action,
                GroupID      => $Group ? $Group->{id} : 0,
                CustomerPage => 1,
            ),
            CustomerResultFrom     => $CustomerResultFrom,
            CustomerResultTo       => $CustomerResultTo,
            CustomerPageSize       => CUSTOMER_USER_PAGE_SIZE,
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

        my $PermissionFields = $Self->_PermissionRadioFields(
            Name     => $LevelPrefix . '_' . $Group->{id},
            Selected => $Level,
            UserType => $UserType,
        );

        push @Matrix, {
            group_id                 => $Group->{id},
            group_name               => $Group->{name},
            group_title              => $Group->{title},
            %{$PermissionFields},
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
    my @UserAccountIDs = map {
        $UserType eq 'customer' ? ( $_->{user_account_id} || 0 ) : ( $_->{id} || 0 )
    } @{$UserList};
    my $Current = $Admin->GroupMemberList(
        GroupID        => $Group->{id},
        UserAccountIDs => \@UserAccountIDs,
    );
    my %CurrentByUserID = map { $_->{user_account_id} => $_ } @{$Current};
    my @Matrix;

    for my $User ( @{$UserList} ) {
        my $UserAccountID = $UserType eq 'customer' ? ( $User->{user_account_id} || 0 ) : ( $User->{id} || 0 );
        my $CurrentGroup = $CurrentByUserID{$UserAccountID} || {};
        my $Level = $UserType eq 'customer'
            ? $Self->_CustomerPermissionLevelFromRow( Row => $CurrentGroup )
            : $Self->_AgentPermissionLevelFromRow( Row => $CurrentGroup );

        my $PermissionFields = $Self->_PermissionRadioFields(
            Name     => $LevelPrefix . '_' . $UserAccountID,
            Selected => $Level,
            UserType => $UserType,
        );

        push @Matrix, {
            user_account_id          => $UserAccountID,
            user_label               => $UserType eq 'customer'
                ? $Self->_CustomerUserLabel( CustomerUser => $User )
                : $Self->_AgentLabel( Agent => $User ),
            %{$PermissionFields},
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

    my $Current = $Admin->UserGroupList( UserAccountID => $UserAccountID );
    my %CurrentByGroupID = map { $_->{user_group_id} => $_ } @{$Current};

    for my $Group ( @{$GroupList} ) {
        my $GroupID = $Group->{id};
        my $RequestedLevel = $Request->{ $LevelPrefix . '_' . $GroupID } || 'none';
        my $CurrentGroup = $CurrentByGroupID{$GroupID} || {};
        my $CurrentLevel = $UserType eq 'customer'
            ? $Self->_CustomerPermissionLevelFromRow( Row => $CurrentGroup )
            : $Self->_AgentPermissionLevelFromRow( Row => $CurrentGroup );

        next if $RequestedLevel eq $CurrentLevel;

        my %Permission = $Self->_PermissionFromLevel(
            Level    => $RequestedLevel,
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

    my @UserAccountIDs = map {
        $UserType eq 'customer' ? ( $_->{user_account_id} || 0 ) : ( $_->{id} || 0 )
    } @{$UserList};
    my $Current = $Admin->GroupMemberList(
        GroupID        => $GroupID,
        UserAccountIDs => \@UserAccountIDs,
    );
    my %CurrentByUserID = map { $_->{user_account_id} => $_ } @{$Current};

    for my $User ( @{$UserList} ) {
        my $UserAccountID = $UserType eq 'customer' ? ( $User->{user_account_id} || 0 ) : ( $User->{id} || 0 );
        my $RequestedLevel = $Request->{ $LevelPrefix . '_' . $UserAccountID } || 'none';
        my $CurrentGroup = $CurrentByUserID{$UserAccountID} || {};
        my $CurrentLevel = $UserType eq 'customer'
            ? $Self->_CustomerPermissionLevelFromRow( Row => $CurrentGroup )
            : $Self->_AgentPermissionLevelFromRow( Row => $CurrentGroup );

        next if $RequestedLevel eq $CurrentLevel;

        my %Permission = $Self->_PermissionFromLevel(
            Level    => $RequestedLevel,
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

sub _PermissionRadioFields {
    my ( $Self, %Param ) = @_;

    my $Name     = $Param{Name} || 'PermissionLevel';
    my $Selected = $Param{Selected} || 'none';
    my $UserType = $Param{UserType} || 'agent';
    my @Levels = $UserType eq 'customer'
        ? qw(none own organization)
        : qw(none read work full);

    my %Fields = ( permission_name => $Name );
    for my $Level (@Levels) {
        $Fields{ 'permission_' . $Level . '_checked' } = $Level eq $Selected ? 'checked' : '';
    }

    return \%Fields;
}

sub _CustomerUserGetByUserAccountID {
    my ( $Self, %Param ) = @_;

    my $Admin         = $Param{Admin};
    my $UserAccountID = $Param{UserAccountID} || 0;

    return if $UserAccountID !~ m{\A\d+\z} || !$UserAccountID;

    my $CustomerUserList = $Param{CustomerUserList} || $Admin->CustomerUserList();

    for my $CustomerUser ( @{$CustomerUserList} ) {
        return $CustomerUser if ( $CustomerUser->{user_account_id} || 0 ) == $UserAccountID;
    }

    return;
}

sub _PaginationItems {
    my ( $Self, %Param ) = @_;

    my $CurrentPage = $Self->_PositiveInteger( Value => $Param{CurrentPage}, Default => 1 );
    my $PageCount   = $Self->_PositiveInteger( Value => $Param{PageCount}, Default => 1 );
    $CurrentPage = $PageCount if $CurrentPage > $PageCount;

    my %VisiblePage = ( 1 => 1, $PageCount => 1 );
    for my $Page ( $CurrentPage - 2 .. $CurrentPage + 2 ) {
        $VisiblePage{$Page} = 1 if $Page >= 1 && $Page <= $PageCount;
    }

    my @Items;
    my $PreviousPage = 0;
    for my $Page ( sort { $a <=> $b } keys %VisiblePage ) {
        if ( $PreviousPage && $Page > $PreviousPage + 1 ) {
            push @Items, {
                HTML => '<span class="qisutu-ticket-list-page-ellipsis">…</span>',
            };
        }

        my $URL = $Self->_CustomerPageURL(
            Action         => $Param{Action},
            GroupID        => $Param{GroupID},
            CustomerSearch => $Param{Search},
            CustomerPage   => $Page,
        );
        my $HTML = $Page == $CurrentPage
            ? '<span class="qisutu-ticket-list-page-link qisutu-ticket-list-page-active" aria-current="page">' . $Page . '</span>'
            : '<a class="qisutu-ticket-list-page-link" href="' . $Self->_Escape($URL) . '">' . $Page . '</a>';
        push @Items, {
            PageNumber => $Page,
            IsCurrent  => $Page == $CurrentPage ? 1 : 0,
            URL        => $URL,
            HTML       => $HTML,
        };
        $PreviousPage = $Page;
    }

    return \@Items;
}

sub _CustomerPageURL {
    my ( $Self, %Param ) = @_;

    my $URL = 'index.pl?Page=AdminGroups';
    my $GroupID = $Param{GroupID} || 0;
    if ( ( $Param{Action} || '' ) eq 'Group' && $GroupID =~ m{\A\d+\z} && $GroupID ) {
        $URL .= ';Action=Group;GroupID=' . $GroupID;
    }

    my $Search = $Self->_TrimValue( Value => $Param{CustomerSearch} );
    $URL .= ';CustomerSearch=' . $Self->_URLQueryEncode( Value => $Search ) if $Search ne '';

    my $Page = $Self->_PositiveInteger( Value => $Param{CustomerPage}, Default => 1 );
    $URL .= ';CustomerPage=' . $Page;

    return $URL;
}

sub _URLQueryEncode {
    my ( $Self, %Param ) = @_;

    my $Value = defined $Param{Value} ? $Param{Value} : '';
    my $Bytes = encode( 'UTF-8', $Value );
    $Bytes =~ s{([^A-Za-z0-9_.~-])}{sprintf '%%%02X', ord $1}ge;

    return $Bytes;
}

sub _IDList {
    my ( $Self, %Param ) = @_;

    my %Seen;
    my @IDs = grep { !$Seen{$_}++ }
        grep { m{\A\d+\z} && $_ > 0 }
        split m{\s*,\s*}, ( $Param{Value} || '' );
    splice @IDs, 200 if @IDs > 200;

    return \@IDs;
}

sub _PositiveInteger {
    my ( $Self, %Param ) = @_;

    my $Value   = defined $Param{Value} ? $Param{Value} : '';
    my $Default = $Param{Default} || 1;

    return $Default if $Value !~ m{\A\d+\z} || $Value < 1;

    return 0 + $Value;
}

sub _TrimValue {
    my ( $Self, %Param ) = @_;

    my $Value = defined $Param{Value} ? $Param{Value} : '';
    $Value =~ s{\A\s+}{};
    $Value =~ s{\s+\z}{};

    return $Value;
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
