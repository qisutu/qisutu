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

package AdminSLAs;

use strict;
use warnings;
use utf8;

use QisutuAdmin;
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
    my $User    = $Param{User} || {};
    my $ServiceObject = QisutuService->new( Config => $Self->{Config}, DB => $Self->{DB} );
    my $AdminObject = QisutuAdmin->new( Config => $Self->{Config}, DB => $Self->{DB} );
    my $Step = $Request->{Step} || '';

    if ( $Step eq 'SLACreate' ) {
        my $ID = $ServiceObject->SLACreate(
            Name                 => $Request->{Name},
            ServiceID            => $Request->{ServiceID},
            CalendarID           => $Request->{CalendarID},
            UpdateMode           => $Request->{UpdateMode},
            FirstResponseMinutes => $Request->{FirstResponseMinutes},
            UpdateMinutes        => $Request->{UpdateMinutes},
            SolutionMinutes      => $Request->{SolutionMinutes},
            IsDefault            => $Request->{IsDefault},
            SortOrder            => $Request->{SortOrder},
            ChangedByUserID      => $User->{user_account_id},
        );
        return { Redirect => 'index.pl?Page=AdminSLAs' } if $ID && !$ServiceObject->Error();
    }
    elsif ( $Step eq 'SLAUpdate' ) {
        my $OK = $ServiceObject->SLAUpdate(
            SLAID                => $Request->{SLAID},
            Name                 => $Request->{Name},
            ServiceID            => $Request->{ServiceID},
            CalendarID           => $Request->{CalendarID},
            UpdateMode           => $Request->{UpdateMode},
            FirstResponseMinutes => $Request->{FirstResponseMinutes},
            UpdateMinutes        => $Request->{UpdateMinutes},
            SolutionMinutes      => $Request->{SolutionMinutes},
            IsDefault            => $Request->{IsDefault},
            Active               => $Request->{Active},
            SortOrder            => $Request->{SortOrder},
            ChangedByUserID      => $User->{user_account_id},
        );
        return { Redirect => 'index.pl?Page=AdminSLAs;Action=Edit;SLAID=' . ( $Request->{SLAID} || 0 ) } if $OK && !$ServiceObject->Error();
    }
    elsif ( $Step eq 'SLADeactivate' ) {
        my $OK = $ServiceObject->SLADeactivate( SLAID => $Request->{SLAID}, ChangedByUserID => $User->{user_account_id} );
        return { Redirect => 'index.pl?Page=AdminSLAs' } if $OK && !$ServiceObject->Error();
    }

    my $Action = $Request->{Action} || 'List';
    my $SLAList = $ServiceObject->SLAList();
    my $ServiceList = $ServiceObject->ServiceList( ActiveOnly => 1 );
    my $CalendarList = $AdminObject->CalendarList();
    my $SLA;
    if ( $Action eq 'Edit' ) {
        $SLA = $ServiceObject->SLAGet( SLAID => $Request->{SLAID} );
        $Action = 'List' if !$SLA;
    }

    for my $Row ( @{$SLAList} ) {
        $Row->{calendar_display} = join ' ', grep { defined $_ && $_ ne '' } ( $Row->{calendar_name}, $Row->{calendar_timezone} );
        $Row->{is_default_label} = $Row->{is_default} ? 'Translate:AdminActiveYes' : 'Translate:AdminActiveNo';
        $Row->{active_label} = $Row->{active} ? 'Translate:AdminActiveYes' : 'Translate:AdminActiveNo';
    }

    my $ShowCreate = $Action eq 'Create' ? 1 : 0;
    my $ShowEdit   = $Action eq 'Edit' ? 1 : 0;
    my $Error = $ServiceObject->Error() || $AdminObject->Error() || '';

    return {
        Template => 'AdminSLAs.tt',
        Data => {
            PageTitle => 'Translate:AdminSLAsTitle', ProgramTitle => 'Translate:AdminSLAsTitle', ProgramDescription => 'Translate:AdminSLAsDescription',
            FormAction => 'index.pl',
            ShowList => $Action eq 'List' ? 1 : 0,
            ShowCreate => $ShowCreate,
            ShowEdit => $ShowEdit,
            ShowForm => $ShowCreate || $ShowEdit ? 1 : 0,
            ShowBackToList => $Action eq 'List' ? 0 : 1,
            SLAList => $SLAList,
            SLACount => scalar @{$SLAList},
            ErrorMessage => $Error,
            ErrorClass => $Error ? '' : 'qisutu-hidden',
            FormTitle => $ShowCreate ? 'Translate:AdminSLACreate' : 'Translate:AdminSLAEdit',
            FormSubmitLabel => $ShowCreate ? 'Translate:AdminCreate' : 'Translate:AdminSave',
            FormStep => $ShowCreate ? 'SLACreate' : 'SLAUpdate',
            FormSLAID => $SLA ? $SLA->{id} : '',
            FormSLAName => $SLA ? $SLA->{name} : '',
            FormSLASortOrder => $SLA ? $SLA->{sort_order} : 1000,
            FormSLAFirstResponseMinutes => $SLA ? $SLA->{first_response_minutes} : 0,
            FormSLAUpdateMinutes => $SLA ? $SLA->{update_minutes} : 0,
            FormSLASolutionMinutes => $SLA ? $SLA->{solution_minutes} : 0,
            FormSLAIsDefaultChecked => $SLA && $SLA->{is_default} ? 'checked' : '',
            FormSLAActiveChecked => $SLA && $SLA->{active} ? 'checked' : '',
            FormServiceOptionsHTML => $Self->_Options( List => $ServiceList, LabelKey => 'full_name', SelectedID => $SLA ? $SLA->{service_id} : '' ),
            FormCalendarOptionsHTML => $Self->_CalendarOptions( List => $CalendarList, SelectedID => $SLA ? $SLA->{calendar_id} : '' ),
            FormUpdateModeCustomerSelected => !$SLA || ( $SLA->{update_mode} || '' ) eq 'customer_response' ? 'selected' : '',
            FormUpdateModeRegularSelected => $SLA && ( $SLA->{update_mode} || '' ) eq 'regular' ? 'selected' : '',
        },
    };
}

sub _Options {
    my ( $Self, %Param ) = @_;
    my $HTML = '';
    for my $Row ( @{ $Param{List} || [] } ) {
        my $Selected = defined $Param{SelectedID} && $Param{SelectedID} ne '' && ( $Row->{id} || 0 ) == $Param{SelectedID} ? ' selected' : '';
        $HTML .= '<option value="' . $Self->{Output}->HTMLEscape( $Row->{id} || '' ) . '"' . $Selected . '>' . $Self->{Output}->HTMLEscape( $Row->{ $Param{LabelKey} } || '' ) . '</option>';
    }
    return $HTML;
}

sub _CalendarOptions {
    my ( $Self, %Param ) = @_;
    my $HTML = '';
    for my $Row ( @{ $Param{List} || [] } ) {
        my $Selected = defined $Param{SelectedID} && $Param{SelectedID} ne '' && ( $Row->{id} || 0 ) == $Param{SelectedID} ? ' selected' : '';
        my $Label = join ' ', grep { defined $_ && $_ ne '' } ( $Row->{name}, $Row->{timezone} );
        $HTML .= '<option value="' . $Self->{Output}->HTMLEscape( $Row->{id} || '' ) . '"' . $Selected . '>' . $Self->{Output}->HTMLEscape($Label) . '</option>';
    }
    return $HTML;
}

1;
