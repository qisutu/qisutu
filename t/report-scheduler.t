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

use FindBin;
use lib "$FindBin::Bin/../core/config", "$FindBin::Bin/../core/system", "$FindBin::Bin/../core/cpan-lib";
use POSIX ();
use Test::More;
use Time::Local qw(timelocal);

use QisutuReportScheduler;

{
    package Local::ScheduleDB;
    sub new { return bless { Do => [], Error => '' }, shift }
    sub Error { return $_[0]->{Error} }
    sub BeginWork { return 1 }
    sub Commit { return 1 }
    sub Rollback { return 1 }
    sub LastInsertID { return 41 }
    sub SelectRow {
        my ( $Self, $SQL, @Bind ) = @_;
        return { data_source => 'tickets' } if $SQL =~ m{FROM report_definition};
        return { id => 12 } if $SQL =~ m{FROM report_schedule WHERE report_definition_id};
        return;
    }
    sub SelectAll {
        my ( $Self, $SQL, @Bind ) = @_;
        return [] if $SQL =~ m{FROM ticket_dynamic_field};
        if ( $SQL =~ m{FROM user_account} && $SQL =~ m{id IN} ) {
            return [ { id => 4, email => 'agent\@example.org', display_name => 'Agent Four' } ];
        }
        return [];
    }
    sub Do {
        my ( $Self, $SQL, @Bind ) = @_;
        push @{ $Self->{Do} }, [ $SQL, @Bind ];
        return 1;
    }
}

local $ENV{TZ} = 'UTC';
POSIX::tzset();

my $DB = Local::ScheduleDB->new();
my $Scheduler = QisutuReportScheduler->new(
    Config => {
        Language => { Default => 'de' },
        Paths => { Language => "$FindBin::Bin/../core/language" },
    },
    DB => $DB,
);

ok(
    $Scheduler->ScheduleSave(
        ReportID => 9, UserID => 2, Active => 1,
        Frequency => 'weekly', SendTime => '09:15', Weekday => 3,
        PeriodType => 'previous_week', PeriodField => 'created_at',
        Formats => [qw(pdf csv_analysis csv_detail)],
        AgentIDs => [4],
        AdditionalEmails => "outside1\@example.net\noutside2\@example.net",
    ),
    'an active schedule with agents and arbitrary addresses is saved',
);
my @RecipientInsert = grep { $_->[0] =~ m{INSERT INTO report_schedule_recipient} } @{ $DB->{Do} };
is( scalar @RecipientInsert, 3, 'the selected agent and both arbitrary addresses become recipients' );
ok( grep( { $_->[0] =~ m{INSERT INTO report_schedule} && $_->[0] =~ m{ON DUPLICATE KEY UPDATE} } @{ $DB->{Do} } ), 'the schedule is updated idempotently' );

ok(
    !$Scheduler->ScheduleSave(
        ReportID => 9, UserID => 2, Active => 1,
        Frequency => 'daily', SendTime => '09:15',
        PeriodType => 'previous_day', PeriodField => 'created_at',
        Formats => ['pdf'], AdditionalEmails => 'not-an-address',
    ),
    'invalid arbitrary email addresses are rejected',
);
is( $Scheduler->Error(), 'Translate:ReportScheduleErrorEmail', 'the invalid address has a specific error' );

my $January = timelocal( 0, 0, 12, 15, 0, 126 );
is_deeply(
    [ $Scheduler->_DateRange( PeriodType => 'previous_month', Now => $January ) ],
    [ '2025-12-01', '2025-12-31' ],
    'the previous-month period is calculated dynamically',
);
is_deeply(
    [ $Scheduler->_DateRange( PeriodType => 'rolling_days', RollingDays => 7, Now => $January ) ],
    [ '2026-01-08', '2026-01-14' ],
    'rolling periods contain completed calendar days only',
);

my $Configuration = $Scheduler->_ConfigurationForPeriod(
    Configuration => {
        source => 'tickets', filter_logic => 'all', group_by => 'created_month', metrics => ['ticket_count'],
        chart_type => 'bar', sort => 'label_asc', limit => 25, columns => ['ticket_number'],
        filters => [
            { field => 'created_at', operator => 'gte', values => ['2020-01-01'] },
            { field => 'queue_id', operator => 'eq', values => ['3'] },
        ],
    },
    Field => 'created_at', Start => '2026-01-08', End => '2026-01-14',
);
is( scalar @{ $Configuration->{filters} }, 2, 'the dynamic period replaces only the selected date filter' );
is_deeply( $Configuration->{filters}->[1]->{values}, [ '2026-01-08', '2026-01-14' ], 'the scheduled period is injected as a between filter' );

like(
    $Scheduler->_T('ReportScheduleMailBody', 'de', report => 'Monat', period => '2026-01'),
    qr{Monat.*2026-01},
    'mail translations replace report and period placeholders',
);

done_testing();
