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

package AdminCalendars;

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

    my $Request  = $Param{Request} || {};
    my $User     = $Param{User}    || {};
    my $Language = $Request->{Language} || $Self->{Config}->{Language}->{Default} || 'en';
    my $Admin    = $Self->_AdminObject();
    my $Calendar = $Self->_CalendarObject();
    my $Step     = $Request->{Step} || '';
    my $Action   = $Request->{Action} || 'List';
    my $Message  = '';

    if ( $Admin && $Calendar && $Step eq 'CalendarCreate' ) {
        my $CalendarID = $Admin->CalendarCreate(
            Name            => $Request->{Name},
            Timezone        => $Request->{Timezone},
            SortOrder       => $Request->{SortOrder},
            ChangedByUserID => $User->{user_account_id},
        );

        if ($CalendarID) {
            $Calendar->WorkingTimeDefaultCreate(
                CalendarID      => $CalendarID,
                ChangedByUserID => $User->{user_account_id},
            );
            $Calendar->DefaultHolidayCreate(
                CalendarID      => $CalendarID,
                ChangedByUserID => $User->{user_account_id},
            );

            return { Redirect => 'index.pl?Page=AdminCalendars;Action=Edit;ItemID=' . $CalendarID } if !$Calendar->Error();
        }
    }
    elsif ( $Admin && $Calendar && $Step eq 'CalendarUpdate' ) {
        my $CalendarID = $Request->{ItemID} || 0;

        $Admin->CalendarUpdate(
            CalendarID      => $CalendarID,
            Name            => $Request->{Name},
            Timezone        => $Request->{Timezone},
            Active          => $Request->{Active},
            SortOrder       => $Request->{SortOrder},
            ChangedByUserID => $User->{user_account_id},
        );

        if ( !$Admin->Error() ) {
            $Calendar->WorkingTimeSave(
                CalendarID      => $CalendarID,
                Days            => $Self->_WorkingTimeRequest($Request),
                ChangedByUserID => $User->{user_account_id},
            );
        }

        return { Redirect => 'index.pl?Page=AdminCalendars;Action=Edit;ItemID=' . $CalendarID . ';Saved=1' } if !$Admin->Error() && !$Calendar->Error();
    }
    elsif ( $Admin && $Step eq 'CalendarDeactivate' ) {
        $Admin->CalendarDeactivate(
            CalendarID      => $Request->{ItemID},
            ChangedByUserID => $User->{user_account_id},
        );

        return { Redirect => 'index.pl?Page=AdminCalendars' } if !$Admin->Error();
    }
    elsif ( $Calendar && $Step eq 'HolidayCreate' ) {
        my $CalendarID = $Request->{ItemID} || 0;

        $Calendar->HolidayCreate(
            CalendarID       => $CalendarID,
            Name             => $Request->{HolidayName},
            HolidayDate      => $Request->{HolidayDate},
            RecurringAnnual  => $Request->{HolidayRecurringAnnual},
            SortOrder        => $Request->{HolidaySortOrder},
            ChangedByUserID  => $User->{user_account_id},
        );

        return { Redirect => 'index.pl?Page=AdminCalendars;Action=Edit;ItemID=' . $CalendarID . ';HolidaySaved=1' } if !$Calendar->Error();
    }
    elsif ( $Calendar && ( $Step eq 'HolidayActivate' || $Step eq 'HolidayDeactivate' ) ) {
        my $CalendarID = $Request->{ItemID} || 0;

        if ( $Step eq 'HolidayActivate' ) {
            $Calendar->HolidayActivate(
                HolidayID       => $Request->{HolidayID},
                ChangedByUserID => $User->{user_account_id},
            );
        }
        else {
            $Calendar->HolidayDeactivate(
                HolidayID       => $Request->{HolidayID},
                ChangedByUserID => $User->{user_account_id},
            );
        }

        return { Redirect => 'index.pl?Page=AdminCalendars;Action=Edit;ItemID=' . $CalendarID } if !$Calendar->Error();
    }

    if ( $Request->{Saved} ) {
        $Message = 'Translate:CalendarSaved';
    }
    elsif ( $Request->{HolidaySaved} ) {
        $Message = 'Translate:CalendarHolidaySaved';
    }

    my $ItemList = $Admin ? $Admin->CalendarList( IncludeInactive => 1 ) : [];
    my $Item;
    my $WorkingTimeList = [];
    my $HolidayList = [];

    if ( $Admin && $Action eq 'Edit' ) {
        $Item = $Admin->CalendarGet( CalendarID => $Request->{ItemID} );
        if ( !$Item ) {
            $Action = 'List';
        }
        else {
            $WorkingTimeList = $Calendar ? $Calendar->WorkingTimeList( CalendarID => $Item->{id} ) : [];
            $HolidayList     = $Calendar ? $Calendar->HolidayList( CalendarID => $Item->{id} )     : [];
        }
    }

    my $ErrorMessage = '';
    $ErrorMessage ||= $Admin    ? $Admin->Error()    : '';
    $ErrorMessage ||= $Calendar ? $Calendar->Error() : '';

    return {
        Template => 'AdminCalendars.tt',
        Data     => {
            PageTitle          => 'Translate:AdminCalendarsTitle',
            ProgramTitle       => 'Translate:AdminCalendarsTitle',
            ProgramDescription => 'Translate:AdminCalendarsDescription',
            PageName           => 'AdminCalendars',
            ItemList           => $ItemList,
            ItemCount          => scalar @{$ItemList},
            ItemID             => $Item ? $Item->{id} : '',
            ItemName           => $Item ? $Item->{name} : '',
            ItemTimezone       => $Item ? $Item->{timezone} : 'Europe/Berlin',
            ItemSortOrder      => $Item ? $Item->{sort_order} : 1000,
            ItemActiveChecked  => $Item && $Item->{active} ? 'checked' : '',
            WorkingTimeList    => $WorkingTimeList,
            HolidayList        => $HolidayList,
            TimezoneOptionsCreate => $Self->_TimezoneOptionsHTML( Selected => 'Europe/Berlin' ),
            TimezoneOptionsEdit   => $Self->_TimezoneOptionsHTML( Selected => $Item ? $Item->{timezone} : 'Europe/Berlin' ),
            Message            => $Message,
            MessageClass       => $Message ? '' : 'qisutu-hidden',
            ErrorMessage       => $ErrorMessage,
            ErrorClass         => $ErrorMessage ? '' : 'qisutu-hidden',
            FormAction         => 'index.pl',
            ShowList           => $Action eq 'List' ? 1 : 0,
            ShowCreate         => $Action eq 'Create' ? 1 : 0,
            ShowEdit           => $Action eq 'Edit' ? 1 : 0,
            Language           => $Language,
        },
    };
}

sub _WorkingTimeRequest {
    my ( $Self, $Request ) = @_;

    my @Days;

    for my $Weekday ( 1 .. 7 ) {
        push @Days, {
            weekday    => $Weekday,
            active     => $Request->{ 'WorkingActive' . $Weekday } ? 1 : 0,
            start_time => $Request->{ 'WorkingStart' . $Weekday } || '',
            end_time   => $Request->{ 'WorkingEnd' . $Weekday }   || '',
        };
    }

    return \@Days;
}

sub _TimezoneOptionsHTML {
    my ( $Self, %Param ) = @_;

    my $Selected = $Param{Selected} || 'Europe/Berlin';

    my @Timezone = (
        'Europe/Berlin',
        'Europe/Paris',
        'Europe/London',
        'Europe/Zurich',
        'Europe/Vienna',
        'UTC',
        'America/New_York',
        'America/Chicago',
        'America/Denver',
        'America/Los_Angeles',
        'Asia/Tokyo',
        'Asia/Singapore',
        'Australia/Sydney',
    );

    my $HTML = '';
    for my $Timezone (@Timezone) {
        my $Escaped  = $Self->_Escape($Timezone);
        my $SelectedAttribute = $Timezone eq $Selected ? ' selected' : '';
        $HTML .= '<option value="' . $Escaped . '"' . $SelectedAttribute . '>' . $Escaped . '</option>';
    }

    return $HTML;
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

sub _CalendarObject {
    my ($Self) = @_;

    return if !$Self->{DB};

    my $Loaded = eval {
        require QisutuCalendar;
        1;
    };

    return if !$Loaded;

    return QisutuCalendar->new(
        Config => $Self->{Config},
        DB     => $Self->{DB},
    );
}

sub _Escape {
    my ( $Self, $Value ) = @_;

    if ( $Self->{Output} ) {
        return $Self->{Output}->HTMLEscape($Value);
    }

    $Value = '' if !defined $Value;
    $Value =~ s/&/&amp;/g;
    $Value =~ s/</&lt;/g;
    $Value =~ s/>/&gt;/g;
    $Value =~ s/"/&quot;/g;
    $Value =~ s/'/&#39;/g;

    return $Value;
}

1;
