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

use File::Spec;
use FindBin;
use Test::More;

use lib File::Spec->catdir( $FindBin::Bin, '..', 'core', 'module' );
use lib File::Spec->catdir( $FindBin::Bin, '..', 'core', 'system' );

use AdminGroups;
use QisutuAdmin;

{
    package Local::GroupAdmin;

    sub new { return bless { Calls => [] }, shift }
    sub Error { return shift->{Error} || '' }
    sub GroupList { return [ { id => 9, name => 'support', title => 'Support' } ] }
    sub GroupGet { return { id => 9, name => 'support', title => 'Support', group_type => 'agent', active => 1, sort_order => 200 } }
    sub GroupUpdate { my ( $Self, %Param ) = @_; $Self->{GroupUpdateParam} = { %Param }; return 1 }
    sub AgentList { return [] }
    sub CustomerUserCount { my ( $Self, %Param ) = @_; $Self->{CountSearch} = $Param{Search}; return 1_000 }

    sub CustomerUserList {
        my ( $Self, %Param ) = @_;
        $Self->{ListParam} = { %Param };
        return [
            map {
                {
                    user_account_id => $_,
                    login           => 'user' . $_,
                    firstname       => 'Test',
                    lastname        => $_,
                    customer_name   => 'Beispielkunde',
                }
            } 51 .. 75
        ];
    }

    sub CustomerUserListByUserAccountIDs {
        my ( $Self, %Param ) = @_;
        $Self->{LoadedIDs} = [ @{ $Param{UserAccountIDs} || [] } ];
        return [
            map {
                {
                    user_account_id => $_,
                    login           => 'user' . $_,
                    customer_name   => 'Beispielkunde',
                }
            } @{ $Param{UserAccountIDs} || [] }
        ];
    }

    sub GroupMemberList {
        my ( $Self, %Param ) = @_;
        $Self->{GroupMemberParam} = { %Param };
        return [
            {
                user_group_id       => 9,
                user_account_id     => 51,
                permission_read     => 1,
                permission_create   => 1,
                permission_change   => 1,
                permission_overview => 0,
                permission_full     => 0,
            },
        ];
    }

    sub UserGroupAdd {
        my ( $Self, %Param ) = @_;
        push @{ $Self->{Calls} }, { Method => 'add', %Param };
        return 1;
    }

    sub UserGroupRemove {
        my ( $Self, %Param ) = @_;
        push @{ $Self->{Calls} }, { Method => 'remove', %Param };
        return 1;
    }
}

{
    package Local::AdminGroups;
    use parent 'AdminGroups';
    sub _AdminObject { return shift->{Admin} }
}

my $MockAdmin = Local::GroupAdmin->new();
my $Module = Local::AdminGroups->new( Config => {}, DB => bless( {}, 'Local::UnusedDB' ) );
$Module->{Admin} = $MockAdmin;

my $Result = $Module->Run(
    Request => {
        Action         => 'Group',
        GroupID        => 9,
        CustomerSearch => ' Beispiel ',
        CustomerPage   => 3,
    },
    User => { user_account_id => 1 },
);

is( $Result->{Data}->{CustomerPage}, 3, 'the requested customer-user page is retained' );
is( $Result->{Data}->{CustomerPageCount}, 40, 'one thousand customer users produce forty pages' );
is( $MockAdmin->{ListParam}->{Limit}, 25, 'only 25 customer users are loaded per page' );
is( $MockAdmin->{ListParam}->{Offset}, 50, 'page three starts at database offset 50' );
is( $MockAdmin->{ListParam}->{Search}, 'Beispiel', 'the trimmed filter reaches the database' );
is( scalar @{ $Result->{Data}->{GroupCustomerUserMatrix} }, 25, 'the rendered assignment matrix has only 25 rows' );
is( $Result->{Data}->{CustomerResultFrom}, 51, 'the result range starts at row 51' );
is( $Result->{Data}->{CustomerResultTo}, 75, 'the result range ends at row 75' );
is( $Result->{Data}->{GroupCustomerUserIDs}, join( ',', 51 .. 75 ), 'the form contains exactly the visible user IDs' );
is_deeply(
    $MockAdmin->{GroupMemberParam}->{UserAccountIDs},
    [ 51 .. 75 ],
    'permissions are loaded only for users on the visible page',
);

my $Edit = $Module->Run(
    Request => {
        Action  => 'Edit',
        GroupID => 9,
    },
    User => { user_account_id => 1 },
);
ok( $Edit->{Data}->{ShowGroupEdit}, 'a group has a dedicated edit view' );
is( $Edit->{Data}->{GroupTitle}, 'Support', 'the edit view loads the display name' );
is( $Edit->{Data}->{GroupSortOrder}, 200, 'the edit view loads the sort order' );
is( $Edit->{Data}->{GroupValidSelected}, 'selected', 'the edit view loads the validity' );

my $GroupUpdate = $Module->Run(
    Request => {
        Action    => 'Edit',
        Step      => 'GroupUpdate',
        GroupID   => 9,
        Title     => 'First-Level-Support',
        SortOrder => 250,
        Active    => 0,
    },
    User => { user_account_id => 7 },
);
is( $GroupUpdate->{Redirect}, 'index.pl?Page=AdminGroups', 'saving a group returns to the overview' );
is_deeply(
    $MockAdmin->{GroupUpdateParam},
    {
        GroupID         => 9,
        Title           => 'First-Level-Support',
        SortOrder       => 250,
        Active          => 0,
        ChangedByUserID => 7,
    },
    'display name, sort order and validity are passed to the group model',
);

$MockAdmin->{Calls} = [];
my $Update = $Module->Run(
    Request => {
        Step                       => 'GroupCustomerUserMatrixUpdate',
        GroupID                    => 9,
        MatrixUserAccountIDs       => '51,52',
        CustomerPermissionLevel_51 => 'none',
        CustomerPermissionLevel_52 => 'organization',
        CustomerSearch             => 'Beispiel GmbH',
        CustomerPage               => 3,
    },
    User => { user_account_id => 7 },
);

is_deeply( $MockAdmin->{LoadedIDs}, [ 51, 52 ], 'saving reloads only the IDs submitted by the visible page' );
is_deeply(
    [ map { $_->{UserAccountID} } @{ $MockAdmin->{Calls} } ],
    [ 51, 52 ],
    'saving never modifies an off-page customer user',
);
is( $MockAdmin->{Calls}->[0]->{Method}, 'remove', 'the visible existing assignment can be removed' );
is( $MockAdmin->{Calls}->[1]->{Method}, 'add', 'the visible organization assignment can be added' );
like( $Update->{Redirect}, qr{CustomerSearch=Beispiel%20GmbH;CustomerPage=3\z}, 'the filter and page survive saving' );

my $TemplatePath = File::Spec->catfile( $FindBin::Bin, '..', 'core', 'output', 'AdminGroups.tt' );
open my $TemplateHandle, '<:encoding(UTF-8)', $TemplatePath or die $!;
my $Template = do { local $/; <$TemplateHandle> };
close $TemplateHandle;

like( $Template, qr{type="radio"[^>]+value="organization"}, 'customer access is rendered with radio buttons' );
like( $Template, qr{name="MatrixUserAccountIDs"}, 'the customer assignment form marks its visible page IDs' );
like( $Template, qr{name="CustomerSearch"}, 'the customer-user list contains a filter' );
like( $Template, qr{CustomerPaginationItems}, 'the customer-user list contains numbered pagination' );
unlike( $Template, qr{permission_level_options}, 'the old per-row dropdown output is gone' );
like( $Template, qr{Action=Edit;GroupID=\[% Group[.]id %\]}, 'clicking a group opens its edit view' );
like( $Template, qr{Action=Group;GroupID=\[% Group[.]id %\]}, 'group assignments remain separately accessible' );
like( $Template, qr{name="Step" value="GroupUpdate"}, 'the group edit form saves group properties' );
like( $Template, qr{name="Active"}, 'the group edit form exposes validity' );

{
    package Local::AdminDB;

    sub new { return bless {}, shift }
    sub Error { return '' }

    sub Do {
        my ( $Self, $SQL, @Bind ) = @_;
        $Self->{LastDo} = { SQL => $SQL, Bind => \@Bind };
        return 1;
    }

    sub SelectAll {
        my ( $Self, $SQL, @Bind ) = @_;
        $Self->{LastSelectAll} = { SQL => $SQL, Bind => \@Bind };
        return [];
    }

    sub SelectRow {
        my ( $Self, $SQL, @Bind ) = @_;
        $Self->{LastSelectRow} = { SQL => $SQL, Bind => \@Bind };
        return { customer_user_count => 123 };
    }
}

my $DB = Local::AdminDB->new();
my $Admin = QisutuAdmin->new( Config => {}, DB => $DB );
$Admin->CustomerUserList( Search => 'Muster', Limit => 25, Offset => 50 );
like( $DB->{LastSelectAll}->{SQL}, qr{LIMIT 25 OFFSET 50}, 'customer users are paged in SQL rather than after loading all rows' );
is( scalar @{ $DB->{LastSelectAll}->{Bind} }, 6, 'the customer-user filter searches all six supported fields' );

is( $Admin->CustomerUserCount( Search => 'Muster' ), 123, 'the filtered customer-user count is loaded separately' );
is( scalar @{ $DB->{LastSelectRow}->{Bind} }, 6, 'the count uses the same six-field filter' );

$Admin->GroupMemberList( GroupID => 9, UserAccountIDs => [ 51, 52 ] );
like( $DB->{LastSelectAll}->{SQL}, qr{user_account_id IN \([?], [?]\)}, 'group permissions are restricted to visible user IDs in SQL' );
is_deeply( $DB->{LastSelectAll}->{Bind}, [ 9, 51, 52 ], 'the group-permission query binds the group and visible users only' );

ok(
    $Admin->GroupUpdate(
        GroupID         => 9,
        Title           => 'Service Desk',
        SortOrder       => 300,
        Active          => 0,
        ChangedByUserID => 7,
    ),
    'group properties can be updated',
);
like( $DB->{LastDo}->{SQL}, qr{UPDATE user_group\s+SET title = [?],\s+active = [?],\s+sort_order = [?]}s, 'group update writes display name, validity and sorting' );
is_deeply( $DB->{LastDo}->{Bind}, [ 'Service Desk', 0, 300, 7, 9 ], 'group update binds all editable values' );

done_testing();
