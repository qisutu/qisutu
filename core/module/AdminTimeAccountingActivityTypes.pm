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

package AdminTimeAccountingActivityTypes;

use strict;
use warnings;
use utf8;

use QisutuTimeAccounting;

sub new {
    my ( $Class, %Param ) = @_;
    my $Self = { Config => $Param{Config}, DB => $Param{DB}, Output => $Param{Output}, Program => $Param{Program} };
    bless $Self, $Class;
    return $Self;
}

sub Run {
    my ( $Self, %Param ) = @_;
    my $Request  = $Param{Request} || {};
    my $User     = $Param{User} || {};
    my $Object   = QisutuTimeAccounting->new( Config => $Self->{Config}, DB => $Self->{DB}, Output => $Self->{Output} );
    my $Step     = $Request->{Step} || '';

    if ( $Step eq 'ActivityTypeCreate' ) {
        my $ID = $Object->ActivityTypeCreate(
            Name => $Request->{Name}, Default => $Request->{Default}, SortOrder => $Request->{SortOrder},
            ChangedByUserID => $User->{user_account_id},
        );
        return { Redirect => 'index.pl?Page=AdminTimeAccountingActivityTypes' } if $ID;
        $Request->{Action} = 'Create';
    }
    elsif ( $Step eq 'ActivityTypeUpdate' ) {
        my $OK = $Object->ActivityTypeUpdate(
            ActivityTypeID => $Request->{ActivityTypeID}, Name => $Request->{Name},
            Active => $Request->{Active}, Default => $Request->{Default}, SortOrder => $Request->{SortOrder},
            ChangedByUserID => $User->{user_account_id},
        );
        return { Redirect => 'index.pl?Page=AdminTimeAccountingActivityTypes;Action=Edit;ActivityTypeID=' . ( $Request->{ActivityTypeID} || 0 ) } if $OK;
        $Request->{Action} = 'Edit';
    }

    my $Action = $Request->{Action} || 'List';
    my $List = $Object->ActivityTypeList();
    my $Item;
    if ( $Action eq 'Edit' ) {
        $Item = $Object->ActivityTypeGet( ActivityTypeID => $Request->{ActivityTypeID} );
        $Action = 'List' if !$Item;
    }
    for my $Row ( @{$List} ) {
        $Row->{active_label}  = $Row->{active} ? 'Translate:AdminActiveYes' : 'Translate:AdminActiveNo';
        $Row->{default_label} = $Row->{is_default} ? 'Translate:AdminActiveYes' : 'Translate:AdminActiveNo';
    }

    my $ShowCreate = $Action eq 'Create' ? 1 : 0;
    my $ShowEdit   = $Action eq 'Edit' ? 1 : 0;
    my $Error      = $Object->Error() || '';
    return {
        Template => 'AdminTimeAccountingActivityTypes.tt',
        Data => {
            PageTitle => 'Translate:AdminTimeAccountingActivityTypesTitle',
            ProgramTitle => 'Translate:AdminTimeAccountingActivityTypesTitle',
            ProgramDescription => 'Translate:AdminTimeAccountingActivityTypesDescription',
            FormAction => 'index.pl', ShowList => $Action eq 'List' ? 1 : 0,
            ShowCreate => $ShowCreate, ShowEdit => $ShowEdit, ShowForm => $ShowCreate || $ShowEdit ? 1 : 0,
            ShowBackToList => $Action eq 'List' ? 0 : 1,
            ActivityTypeList => $List, ActivityTypeCount => scalar @{$List},
            ErrorMessage => $Error, ErrorClass => $Error ? '' : 'qisutu-hidden',
            FormTitle => $ShowCreate ? 'Translate:AdminTimeAccountingActivityTypeCreate' : 'Translate:AdminTimeAccountingActivityTypeEdit',
            FormSubmitLabel => $ShowCreate ? 'Translate:AdminCreate' : 'Translate:AdminSave',
            FormStep => $ShowCreate ? 'ActivityTypeCreate' : 'ActivityTypeUpdate',
            FormActivityTypeID => $Item ? $Item->{id} : '',
            FormName => $Step ? ( $Request->{Name} || '' ) : ( $Item ? $Item->{name} : '' ),
            FormSortOrder => $Step ? ( $Request->{SortOrder} || 1000 ) : ( $Item ? $Item->{sort_order} : 1000 ),
            FormActiveChecked => $Step eq 'ActivityTypeUpdate' ? ( $Request->{Active} ? 'checked' : '' ) : ( $Item && $Item->{active} ? 'checked' : '' ),
            FormDefaultChecked => $Step ? ( $Request->{Default} ? 'checked' : '' ) : ( $Item && $Item->{is_default} ? 'checked' : '' ),
        },
    };
}

1;
