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

package AdminTicketStates;

use strict;
use warnings;
use utf8;

use QisutuService;

sub new {
    my ( $Class, %Param ) = @_;
    my $Self = { Config => $Param{Config}, DB => $Param{DB}, Output => $Param{Output}, Program => $Param{Program} };
    bless $Self, $Class;
    return $Self;
}

sub Run {
    my ( $Self, %Param ) = @_;
    my $Request = $Param{Request} || {};
    my $User = $Param{User} || {};
    my $Object = QisutuService->new( Config => $Self->{Config}, DB => $Self->{DB} );
    my $Step = $Request->{Step} || '';

    if ( $Step eq 'StateCreate' ) {
        my $OK = $Object->TicketStateCreate(
            Name => $Request->{Name}, StateType => $Request->{StateType}, SLAPause => $Request->{SLAPause}, SortOrder => $Request->{SortOrder}, ChangedByUserID => $User->{user_account_id},
        );
        return { Redirect => 'index.pl?Page=AdminTicketStates' } if $OK && !$Object->Error();
    }
    elsif ( $Step eq 'StateUpdate' ) {
        my $OK = $Object->TicketStateUpdate(
            StateID => $Request->{StateID}, Name => $Request->{Name}, StateType => $Request->{StateType}, SLAPause => $Request->{SLAPause}, Active => $Request->{Active}, SortOrder => $Request->{SortOrder}, ChangedByUserID => $User->{user_account_id},
        );
        return { Redirect => 'index.pl?Page=AdminTicketStates;Action=Edit;StateID=' . ( $Request->{StateID} || 0 ) } if $OK && !$Object->Error();
    }

    my $Action = $Request->{Action} || 'List';
    my $StateList = $Object->TicketStateList();
    my $State;
    if ( $Action eq 'Edit' ) {
        $State = $Object->TicketStateGet( StateID => $Request->{StateID} );
        $Action = 'List' if !$State;
    }

    for my $Row ( @{$StateList} ) {
        $Row->{sla_pause_label} = $Row->{sla_pause} ? 'Translate:AdminActiveYes' : 'Translate:AdminActiveNo';
        $Row->{active_label} = $Row->{active} ? 'Translate:AdminActiveYes' : 'Translate:AdminActiveNo';
        my %TypeLabel = (
            new     => 'Translate:AdminTicketStateTypeNew',
            open    => 'Translate:AdminTicketStateTypeOpen',
            pending => 'Translate:AdminTicketStateTypePending',
            closed  => 'Translate:AdminTicketStateTypeClosed',
        );
        $Row->{state_type_label} = $TypeLabel{ $Row->{state_type} || '' } || ( $Row->{state_type} || '' );
    }

    my $ShowCreate = $Action eq 'Create' ? 1 : 0;
    my $ShowEdit   = $Action eq 'Edit' ? 1 : 0;
    my $Error = $Object->Error() || '';
    return {
        Template => 'AdminTicketStates.tt',
        Data => {
            PageTitle => 'Translate:AdminTicketStatesTitle', ProgramTitle => 'Translate:AdminTicketStatesTitle', ProgramDescription => 'Translate:AdminTicketStatesDescription',
            FormAction => 'index.pl',
            ShowList => $Action eq 'List' ? 1 : 0,
            ShowCreate => $ShowCreate,
            ShowEdit => $ShowEdit,
            ShowForm => $ShowCreate || $ShowEdit ? 1 : 0,
            ShowBackToList => $Action eq 'List' ? 0 : 1,
            StateList => $StateList,
            StateCount => scalar @{$StateList},
            ErrorMessage => $Error,
            ErrorClass => $Error ? '' : 'qisutu-hidden',
            FormTitle => $ShowCreate ? 'Translate:AdminTicketStateCreate' : 'Translate:AdminTicketStateEdit',
            FormSubmitLabel => $ShowCreate ? 'Translate:AdminCreate' : 'Translate:AdminSave',
            FormStep => $ShowCreate ? 'StateCreate' : 'StateUpdate',
            FormStateID => $State ? $State->{id} : '',
            FormStateName => $State ? $State->{name} : '',
            FormStateSortOrder => $State ? $State->{sort_order} : 1000,
            FormStateSLAPauseChecked => $State && $State->{sla_pause} ? 'checked' : '',
            FormStateActiveChecked => $State && $State->{active} ? 'checked' : '',
            FormTypeNewSelected => $State && $State->{state_type} eq 'new' ? 'selected' : '',
            FormTypeOpenSelected => !$State || $State->{state_type} eq 'open' ? 'selected' : '',
            FormTypePendingSelected => $State && $State->{state_type} eq 'pending' ? 'selected' : '',
            FormTypeClosedSelected => $State && $State->{state_type} eq 'closed' ? 'selected' : '',
        },
    };
}

1;
