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

package QisutuCalendar;

use strict;
use warnings;
use utf8;

use POSIX qw(tzset);
use Time::Piece;
use Time::Seconds;

sub new {
    my ( $Class, %Param ) = @_;

    my $Self = {
        DB        => $Param{DB},
        Config    => $Param{Config},
        LastError => '',
    };

    bless $Self, $Class;

    return $Self;
}

sub WorkingTimeList {
    my ( $Self, %Param ) = @_;

    my $CalendarID = $Param{CalendarID} || 0;

    return [] if $CalendarID !~ m{\A\d+\z} || !$CalendarID;

    my $Rows = $Self->{DB}->SelectAll(
        'SELECT
            id,
            calendar_id,
            weekday,
            active,
            TIME_FORMAT(start_time, "%H:%i") AS start_time,
            TIME_FORMAT(end_time, "%H:%i") AS end_time
         FROM calendar_working_time
         WHERE calendar_id = ?
         ORDER BY weekday ASC',
        $CalendarID,
    );

    if ( !$Rows ) {
        $Self->{LastError} = $Self->{DB}->Error() || 'Calendar working times could not be loaded';
        return [];
    }

    my %ByWeekday;
    for my $Row ( @{$Rows} ) {
        $ByWeekday{ $Row->{weekday} } = $Row;
    }

    my @Prepared;
    for my $Weekday ( 1 .. 7 ) {
        my $Row = $ByWeekday{$Weekday} || {};

        push @Prepared, {
            weekday        => $Weekday,
            weekday_label  => $Self->_WeekdayLabel($Weekday),
            active         => $Row->{active} ? 1 : 0,
            active_checked => $Row->{active} ? 'checked' : '',
            start_time     => $Row->{start_time} || ( $Weekday <= 5 ? '08:00' : '' ),
            end_time       => $Row->{end_time}   || ( $Weekday <= 5 ? '17:00' : '' ),
        };
    }

    return \@Prepared;
}

sub WorkingTimeSave {
    my ( $Self, %Param ) = @_;

    my $CalendarID = $Param{CalendarID} || 0;
    my $Days       = $Param{Days}       || [];
    my $UserID     = $Param{ChangedByUserID} || 1;

    if ( $CalendarID !~ m{\A\d+\z} || !$CalendarID ) {
        $Self->{LastError} = 'Calendar is required';
        return;
    }

    for my $Day ( @{$Days} ) {
        next if ref $Day ne 'HASH';

        my $Weekday = $Day->{weekday} || 0;
        my $Active  = $Day->{active} ? 1 : 0;
        my $Start   = $Self->_TimeClean( $Day->{start_time} );
        my $End     = $Self->_TimeClean( $Day->{end_time} );

        if ( $Weekday !~ m{\A[1-7]\z} ) {
            $Self->{LastError} = 'Weekday is invalid';
            return;
        }

        if ($Active) {
            if ( !$Start || !$End ) {
                $Self->{LastError} = 'Start and end time are required for active working days';
                return;
            }

            if ( $Start ge $End ) {
                $Self->{LastError} = 'Working time end must be later than start';
                return;
            }
        }
        else {
            $Start ||= '00:00';
            $End   ||= '00:00';
        }

        my $Result = $Self->{DB}->Do(
            'INSERT INTO calendar_working_time (
                calendar_id,
                weekday,
                active,
                start_time,
                end_time,
                created_by_user_id,
                changed_by_user_id
             ) VALUES (
                ?, ?, ?, ?, ?, ?, ?
             )
             ON DUPLICATE KEY UPDATE
                active = VALUES(active),
                start_time = VALUES(start_time),
                end_time = VALUES(end_time),
                changed_by_user_id = VALUES(changed_by_user_id),
                changed_at = CURRENT_TIMESTAMP',
            $CalendarID,
            $Weekday,
            $Active,
            $Start,
            $End,
            $UserID,
            $UserID,
        );

        if ( !$Result ) {
            $Self->{LastError} = $Self->{DB}->Error() || 'Calendar working times could not be saved';
            return;
        }
    }

    return 1;
}

sub WorkingTimeDefaultCreate {
    my ( $Self, %Param ) = @_;

    my $CalendarID = $Param{CalendarID} || 0;
    my $UserID     = $Param{ChangedByUserID} || 1;

    my @Days;
    for my $Weekday ( 1 .. 7 ) {
        push @Days, {
            weekday    => $Weekday,
            active     => $Weekday <= 5 ? 1 : 0,
            start_time => $Weekday <= 5 ? '08:00' : '00:00',
            end_time   => $Weekday <= 5 ? '17:00' : '00:00',
        };
    }

    return $Self->WorkingTimeSave(
        CalendarID       => $CalendarID,
        Days             => \@Days,
        ChangedByUserID  => $UserID,
    );
}

sub HolidayList {
    my ( $Self, %Param ) = @_;

    my $CalendarID = $Param{CalendarID} || 0;

    return [] if $CalendarID !~ m{\A\d+\z} || !$CalendarID;

    my $Rows = $Self->{DB}->SelectAll(
        'SELECT
            id,
            calendar_id,
            name,
            holiday_date,
            month_day,
            recurring_annual,
            active,
            sort_order
         FROM calendar_holiday
         WHERE calendar_id = ?
         ORDER BY
            COALESCE(month_day, DATE_FORMAT(holiday_date, "%m-%d")) ASC,
            recurring_annual DESC,
            holiday_date ASC,
            sort_order ASC,
            name ASC',
        $CalendarID,
    );

    if ( !$Rows ) {
        $Self->{LastError} = $Self->{DB}->Error() || 'Calendar holidays could not be loaded';
        return [];
    }

    for my $Row ( @{$Rows} ) {
        $Row->{date_display} = $Row->{recurring_annual} ? ( $Row->{month_day} || '' ) : ( $Row->{holiday_date} || '' );
        $Row->{name_display} = $Self->_HolidayNameDisplay( $Row->{name} );
        $Row->{type_label}   = $Row->{recurring_annual} ? 'Translate:CalendarHolidayRecurring' : 'Translate:CalendarHolidaySingle';
        $Row->{active_label} = $Row->{active} ? 'Translate:AdminActiveYes' : 'Translate:AdminActiveNo';

        if ( $Row->{active} ) {
            $Row->{active_step}         = 'HolidayDeactivate';
            $Row->{active_button_label} = 'Translate:AdminDeactivate';
            $Row->{active_button_class} = 'qisutu-button-danger';
        }
        else {
            $Row->{active_step}         = 'HolidayActivate';
            $Row->{active_button_label} = 'Translate:AdminActivate';
            $Row->{active_button_class} = 'qisutu-button-secondary';
        }
    }

    return $Rows;
}

sub HolidayCreate {
    my ( $Self, %Param ) = @_;

    my $CalendarID = $Param{CalendarID} || 0;
    my $Name       = $Self->_Trim( $Param{Name} );
    my $Date       = $Self->_Trim( $Param{HolidayDate} );
    my $Recurring  = $Param{RecurringAnnual} ? 1 : 0;
    my $SortOrder  = $Param{SortOrder} || 1000;
    my $UserID     = $Param{ChangedByUserID} || 1;

    if ( $CalendarID !~ m{\A\d+\z} || !$CalendarID || !$Name || !$Date ) {
        $Self->{LastError} = 'Translate:CalendarHolidayNameAndDateRequired';
        return;
    }

    if ( $SortOrder !~ m{\A\d+\z} ) {
        $SortOrder = 1000;
    }

    my ( $HolidayDate, $MonthDay );

    if ($Recurring) {
        if ( $Date =~ m{\A(\d{2})-(\d{2})\z} ) {
            $MonthDay = "$1-$2";
        }
        elsif ( $Date =~ m{\A\d{4}-(\d{2})-(\d{2})\z} ) {
            $MonthDay = "$1-$2";
        }
        else {
            $Self->{LastError} = 'Translate:CalendarHolidayRecurringDateInvalid';
            return;
        }
    }
    else {
        if ( $Date !~ m{\A\d{4}-\d{2}-\d{2}\z} ) {
            $Self->{LastError} = 'Translate:CalendarHolidaySingleDateInvalid';
            return;
        }

        $HolidayDate = $Date;
    }

    my $Result = $Self->{DB}->Do(
        'INSERT INTO calendar_holiday (
            calendar_id,
            name,
            holiday_date,
            month_day,
            recurring_annual,
            active,
            sort_order,
            created_by_user_id,
            changed_by_user_id
         ) VALUES (
            ?, ?, ?, ?, ?, 1, ?, ?, ?
         )',
        $CalendarID,
        $Name,
        $HolidayDate,
        $MonthDay,
        $Recurring,
        $SortOrder,
        $UserID,
        $UserID,
    );

    if ( !$Result ) {
        $Self->{LastError} = $Self->{DB}->Error() || 'Translate:CalendarHolidayCreateFailed';
        return;
    }

    return 1;
}

sub HolidayActivate {
    my ( $Self, %Param ) = @_;

    return $Self->HolidaySetActive(
        HolidayID       => $Param{HolidayID},
        Active          => 1,
        ChangedByUserID => $Param{ChangedByUserID},
    );
}

sub HolidayDeactivate {
    my ( $Self, %Param ) = @_;

    return $Self->HolidaySetActive(
        HolidayID       => $Param{HolidayID},
        Active          => 0,
        ChangedByUserID => $Param{ChangedByUserID},
    );
}

sub HolidaySetActive {
    my ( $Self, %Param ) = @_;

    my $HolidayID = $Param{HolidayID} || 0;
    my $Active    = $Param{Active} ? 1 : 0;
    my $UserID    = $Param{ChangedByUserID} || 1;

    if ( $HolidayID !~ m{\A\d+\z} || !$HolidayID ) {
        $Self->{LastError} = 'Translate:CalendarHolidayRequired';
        return;
    }

    my $Result = $Self->{DB}->Do(
        'UPDATE calendar_holiday
         SET active = ?,
             changed_by_user_id = ?,
             changed_at = CURRENT_TIMESTAMP
         WHERE id = ?',
        $Active,
        $UserID,
        $HolidayID,
    );

    if ( !$Result ) {
        $Self->{LastError} = $Self->{DB}->Error() || 'Translate:CalendarHolidayActiveChangeFailed';
        return;
    }

    return 1;
}

sub DefaultHolidayCreate {
    my ( $Self, %Param ) = @_;

    my $CalendarID = $Param{CalendarID} || 0;
    my $UserID     = $Param{ChangedByUserID} || 1;

    if ( $CalendarID !~ m{\A\d+\z} || !$CalendarID ) {
        $Self->{LastError} = 'Calendar is required';
        return;
    }

    my @Holiday = (
        [ q{New Year's Day},  '01-01', 100 ],
        [ 'Labour Day',      '05-01', 200 ],
        [ 'Christmas Eve',   '12-24', 300 ],
        [ 'Christmas Day',   '12-25', 400 ],
        [ 'Boxing Day',      '12-26', 500 ],
        [ q{New Year's Eve},  '12-31', 600 ],
    );

    for my $Holiday (@Holiday) {
        my ( $Name, $MonthDay, $SortOrder ) = @{$Holiday};

        my $Existing = $Self->{DB}->SelectRow(
            'SELECT id
             FROM calendar_holiday
             WHERE calendar_id = ?
                AND recurring_annual = 1
                AND month_day = ?
             LIMIT 1',
            $CalendarID,
            $MonthDay,
        );

        if ($Existing) {
            next;
        }

        my $Result = $Self->{DB}->Do(
            'INSERT INTO calendar_holiday (
                calendar_id,
                name,
                holiday_date,
                month_day,
                recurring_annual,
                active,
                sort_order,
                created_by_user_id,
                changed_by_user_id
             ) VALUES (
                ?, ?, NULL, ?, 1, 1, ?, ?, ?
             )',
            $CalendarID,
            $Name,
            $MonthDay,
            $SortOrder,
            $UserID,
            $UserID,
        );

        if ( !$Result ) {
            $Self->{LastError} = $Self->{DB}->Error() || 'Default holidays could not be created';
            return;
        }
    }

    return 1;
}

sub IsHoliday {
    my ( $Self, %Param ) = @_;

    my $CalendarID = $Param{CalendarID} || 0;
    my $Date       = $Self->_DateFromDateTime( $Param{DateTime} || $Param{Date} || '' );

    return 0 if $CalendarID !~ m{\A\d+\z} || !$CalendarID || !$Date;

    return $Self->_IsHolidayDate(
        CalendarID => $CalendarID,
        Date       => $Date,
    );
}

sub IsWorkingTime {
    my ( $Self, %Param ) = @_;

    my $CalendarID = $Param{CalendarID} || 0;
    my $DateTime   = $Param{DateTime}   || '';
    my $Timezone   = $Param{Timezone}   || $Self->_CalendarTimezone( CalendarID => $CalendarID );

    return 0 if $CalendarID !~ m{\A\d+\z} || !$CalendarID || !$DateTime;

    my $Piece = $Self->_ParseDateTime( DateTime => $DateTime, Timezone => $Timezone );
    return 0 if !$Piece;

    my $Window = $Self->_WorkingWindowForPiece(
        CalendarID => $CalendarID,
        Piece      => $Piece,
        Timezone   => $Timezone,
    );

    return 0 if !$Window;
    return 1 if $Piece >= $Window->{start_piece} && $Piece < $Window->{end_piece};

    return 0;
}

sub NextWorkingTime {
    my ( $Self, %Param ) = @_;

    my $CalendarID = $Param{CalendarID} || 0;
    my $DateTime   = $Param{DateTime}   || '';
    my $Timezone   = $Param{Timezone}   || $Self->_CalendarTimezone( CalendarID => $CalendarID );

    return if $CalendarID !~ m{\A\d+\z} || !$CalendarID || !$DateTime;

    my $Current = $Self->_ParseDateTime( DateTime => $DateTime, Timezone => $Timezone );
    return if !$Current;

    for ( 1 .. 3660 ) {
        my $Window = $Self->_WorkingWindowForPiece(
            CalendarID => $CalendarID,
            Piece      => $Current,
            Timezone   => $Timezone,
        );

        if ($Window) {
            if ( $Current < $Window->{start_piece} ) {
                return $Self->_PieceFormat( $Window->{start_piece} );
            }
            if ( $Current >= $Window->{start_piece} && $Current < $Window->{end_piece} ) {
                return $Self->_PieceFormat($Current);
            }
        }

        $Current = $Self->_DayStart( Piece => $Current + ONE_DAY );
    }

    return;
}

sub WorkingMinutesBetween {
    my ( $Self, %Param ) = @_;

    my $CalendarID = $Param{CalendarID} || 0;
    my $Start      = $Param{StartDateTime} || '';
    my $End        = $Param{EndDateTime}   || '';
    my $Timezone   = $Param{Timezone} || $Self->_CalendarTimezone( CalendarID => $CalendarID );

    return 0 if $CalendarID !~ m{\A\d+\z} || !$CalendarID || !$Start || !$End;

    my $StartPiece = $Self->_ParseDateTime( DateTime => $Start, Timezone => $Timezone );
    my $EndPiece   = $Self->_ParseDateTime( DateTime => $End,   Timezone => $Timezone );

    return 0 if !$StartPiece || !$EndPiece || $EndPiece <= $StartPiece;

    my $Minutes = 0;
    my $Current = $StartPiece;

    while ( $Current < $EndPiece ) {
        my $Window = $Self->_WorkingWindowForPiece(
            CalendarID => $CalendarID,
            Piece      => $Current,
            Timezone   => $Timezone,
        );

        if (!$Window) {
            $Current = $Self->_DayStart( Piece => $Current + ONE_DAY );
            next;
        }

        my $From = $Current > $Window->{start_piece} ? $Current : $Window->{start_piece};
        my $To   = $EndPiece < $Window->{end_piece} ? $EndPiece : $Window->{end_piece};

        if ( $To > $From ) {
            $Minutes += int( ( $To - $From ) / 60 );
        }

        $Current = $Self->_DayStart( Piece => $Current + ONE_DAY );
    }

    return $Minutes;
}

sub AddWorkingMinutes {
    my ( $Self, %Param ) = @_;

    my $CalendarID = $Param{CalendarID} || 0;
    my $Start      = $Param{StartDateTime} || '';
    my $Minutes    = $Param{Minutes} || 0;
    my $Timezone   = $Param{Timezone} || $Self->_CalendarTimezone( CalendarID => $CalendarID );

    return if $CalendarID !~ m{\A\d+\z} || !$CalendarID || !$Start;
    return $Start if $Minutes !~ m{\A\d+\z} || !$Minutes;

    my $CurrentText = $Self->NextWorkingTime(
        CalendarID => $CalendarID,
        DateTime   => $Start,
        Timezone   => $Timezone,
    );

    return if !$CurrentText;

    my $Current = $Self->_ParseDateTime( DateTime => $CurrentText, Timezone => $Timezone );
    return if !$Current;

    my $Remaining = int($Minutes);

    for ( 1 .. 3660 ) {
        my $Window = $Self->_WorkingWindowForPiece(
            CalendarID => $CalendarID,
            Piece      => $Current,
            Timezone   => $Timezone,
        );

        if (!$Window) {
            $Current = $Self->_DayStart( Piece => $Current + ONE_DAY );
            next;
        }

        if ( $Current < $Window->{start_piece} ) {
            $Current = $Window->{start_piece};
        }

        if ( $Current >= $Window->{end_piece} ) {
            $Current = $Self->_DayStart( Piece => $Current + ONE_DAY );
            next;
        }

        my $Available = int( ( $Window->{end_piece} - $Current ) / 60 );

        if ( $Remaining <= $Available ) {
            return $Self->_PieceFormat( $Current + ( $Remaining * ONE_MINUTE ) );
        }

        $Remaining -= $Available;
        $Current = $Self->_DayStart( Piece => $Current + ONE_DAY );
    }

    return;
}

sub _CalendarData {
    my ( $Self, %Param ) = @_;

    my $CalendarID = $Param{CalendarID} || 0;
    return if $CalendarID !~ m{\A\d+\z} || !$CalendarID;

    $Self->{_CalendarDataCache} ||= {};
    return $Self->{_CalendarDataCache}->{$CalendarID} if $Self->{_CalendarDataCache}->{$CalendarID};

    my $Calendar = $Self->{DB}->SelectRow(
        'SELECT id, timezone
         FROM calendar
         WHERE id = ?
         LIMIT 1',
        $CalendarID,
    ) || {};

    my $WorkingRows = $Self->{DB}->SelectAll(
        'SELECT
            weekday,
            active,
            TIME_FORMAT(start_time, "%H:%i") AS start_time,
            TIME_FORMAT(end_time, "%H:%i") AS end_time
         FROM calendar_working_time
         WHERE calendar_id = ?',
        $CalendarID,
    ) || [];

    my %WorkingByWeekday;
    for my $Row ( @{$WorkingRows} ) {
        next if !$Row->{active};
        next if !$Row->{weekday};
        next if !$Row->{start_time} || !$Row->{end_time};
        next if $Row->{start_time} ge $Row->{end_time};

        $WorkingByWeekday{ $Row->{weekday} } = {
            start_time => $Row->{start_time},
            end_time   => $Row->{end_time},
        };
    }

    my $HolidayRows = $Self->{DB}->SelectAll(
        'SELECT holiday_date, month_day, recurring_annual
         FROM calendar_holiday
         WHERE calendar_id = ?
            AND active = 1',
        $CalendarID,
    ) || [];

    my %HolidayDate;
    my %HolidayMonthDay;
    for my $Row ( @{$HolidayRows} ) {
        if ( $Row->{holiday_date} ) {
            $HolidayDate{ $Row->{holiday_date} } = 1;
        }
        if ( $Row->{recurring_annual} && $Row->{month_day} ) {
            $HolidayMonthDay{ $Row->{month_day} } = 1;
        }
    }

    my $Data = {
        timezone          => $Calendar->{timezone} || 'Europe/Berlin',
        working_by_day    => \%WorkingByWeekday,
        holiday_date      => \%HolidayDate,
        holiday_month_day => \%HolidayMonthDay,
    };

    $Self->{_CalendarDataCache}->{$CalendarID} = $Data;

    return $Data;
}

sub _IsHolidayDate {
    my ( $Self, %Param ) = @_;

    my $CalendarID = $Param{CalendarID} || 0;
    my $Date       = $Param{Date} || '';

    return 0 if $CalendarID !~ m{\A\d+\z} || !$CalendarID || $Date !~ m{\A\d{4}-\d{2}-\d{2}\z};

    my $Data = $Self->_CalendarData( CalendarID => $CalendarID );
    return 0 if !$Data;

    my $MonthDay = substr( $Date, 5, 5 );

    return 1 if $Data->{holiday_date}->{$Date};
    return 1 if $Data->{holiday_month_day}->{$MonthDay};

    return 0;
}

sub _WorkingWindowForPiece {
    my ( $Self, %Param ) = @_;

    my $CalendarID = $Param{CalendarID} || 0;
    my $Piece      = $Param{Piece};
    my $Timezone   = $Param{Timezone} || $Self->_CalendarTimezone( CalendarID => $CalendarID );

    return if !$Piece;

    my $Date = $Piece->strftime('%Y-%m-%d');
    return if $Self->_IsHolidayDate( CalendarID => $CalendarID, Date => $Date );

    my $Weekday = $Piece->_wday();
    $Weekday = 7 if $Weekday == 0;

    my $Data = $Self->_CalendarData( CalendarID => $CalendarID );
    return if !$Data;

    my $Working = $Data->{working_by_day}->{$Weekday};
    return if !$Working;

    my $StartPiece = $Self->_ParseDateTime(
        DateTime => $Date . ' ' . $Working->{start_time} . ':00',
        Timezone => $Timezone,
    );
    my $EndPiece = $Self->_ParseDateTime(
        DateTime => $Date . ' ' . $Working->{end_time} . ':00',
        Timezone => $Timezone,
    );

    return if !$StartPiece || !$EndPiece || $EndPiece <= $StartPiece;

    return {
        start_piece => $StartPiece,
        end_piece   => $EndPiece,
    };
}

sub _CalendarTimezone {
    my ( $Self, %Param ) = @_;

    my $CalendarID = $Param{CalendarID} || 0;

    return 'Europe/Berlin' if $CalendarID !~ m{\A\d+\z} || !$CalendarID;

    my $Data = $Self->_CalendarData( CalendarID => $CalendarID );

    return $Data && $Data->{timezone} ? $Data->{timezone} : 'Europe/Berlin';
}

sub _ParseDateTime {
    my ( $Self, %Param ) = @_;

    my $DateTime = $Param{DateTime} || '';
    my $Timezone = $Param{Timezone} || 'Europe/Berlin';

    return if $DateTime !~ m{\A\d{4}-\d{2}-\d{2}\s+\d{2}:\d{2}(?::\d{2})?\z};

    if ( $DateTime =~ m{\A(\d{4}-\d{2}-\d{2}\s+\d{2}:\d{2})\z} ) {
        $DateTime = $1 . ':00';
    }

    return $Self->_WithTimezone(
        Timezone => $Timezone,
        Code     => sub {
            return Time::Piece->strptime( $DateTime, '%Y-%m-%d %H:%M:%S' );
        },
    );
}

sub _PieceFormat {
    my ( $Self, $Piece ) = @_;

    return $Piece->strftime('%Y-%m-%d %H:%M:%S');
}

sub _DayStart {
    my ( $Self, %Param ) = @_;

    my $Piece = $Param{Piece};

    return Time::Piece->strptime( $Piece->strftime('%Y-%m-%d') . ' 00:00:00', '%Y-%m-%d %H:%M:%S' );
}

sub _WithTimezone {
    my ( $Self, %Param ) = @_;

    my $Timezone = $Param{Timezone} || 'Europe/Berlin';
    my $Code     = $Param{Code};

    return if ref $Code ne 'CODE';

    my $OldTZ = $ENV{TZ};
    $ENV{TZ} = $Timezone;
    tzset();

    my $Result = eval { $Code->() };

    if ( defined $OldTZ ) {
        $ENV{TZ} = $OldTZ;
    }
    else {
        delete $ENV{TZ};
    }
    tzset();

    return $Result;
}

sub _DateFromDateTime {
    my ( $Self, $DateTime ) = @_;

    $DateTime ||= '';

    return $1 if $DateTime =~ m{\A(\d{4}-\d{2}-\d{2})};

    return;
}

sub _TimeClean {
    my ( $Self, $Value ) = @_;

    $Value = $Self->_Trim($Value);

    return if !$Value;
    return $1 if $Value =~ m{\A(\d{2}:\d{2})(?::\d{2})?\z};

    return;
}

sub _Trim {
    my ( $Self, $Value ) = @_;

    $Value = '' if !defined $Value;
    $Value =~ s{\A\s+}{};
    $Value =~ s{\s+\z}{};

    return $Value;
}


sub _HolidayNameDisplay {
    my ( $Self, $Name ) = @_;

    $Name = $Self->_Trim($Name);

    my %Map = (
        'New Year'       => 'Translate:CalendarHolidayDefaultNewYear',
        "New Year's Day" => 'Translate:CalendarHolidayDefaultNewYear',
        'Labour Day'     => 'Translate:CalendarHolidayDefaultLabourDay',
        'Labor Day'      => 'Translate:CalendarHolidayDefaultLabourDay',
        'Christmas Eve'  => 'Translate:CalendarHolidayDefaultChristmasEve',
        'Christmas Day'  => 'Translate:CalendarHolidayDefaultChristmasDay',
        'Boxing Day'     => 'Translate:CalendarHolidayDefaultBoxingDay',
        'New Year Eve'   => 'Translate:CalendarHolidayDefaultNewYearEve',
        "New Year's Eve" => 'Translate:CalendarHolidayDefaultNewYearEve',
    );

    return $Map{$Name} || $Name;
}

sub _WeekdayLabel {
    my ( $Self, $Weekday ) = @_;

    my %Label = (
        1 => 'Translate:CalendarMonday',
        2 => 'Translate:CalendarTuesday',
        3 => 'Translate:CalendarWednesday',
        4 => 'Translate:CalendarThursday',
        5 => 'Translate:CalendarFriday',
        6 => 'Translate:CalendarSaturday',
        7 => 'Translate:CalendarSunday',
    );

    return $Label{$Weekday} || '';
}

sub Error {
    my ($Self) = @_;

    return $Self->{LastError};
}

1;
