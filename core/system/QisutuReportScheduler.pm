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

package QisutuReportScheduler;

use strict;
use warnings;
use utf8;

use File::Spec;
use JSON::PP ();
use POSIX qw(strftime);
use Time::Local qw(timelocal);

use QisutuMail;
use QisutuReportBuilder;
use QisutuReportPDF;

sub new {
    my ( $Class, %Param ) = @_;
    return bless {
        Config       => $Param{Config} || {},
        DB           => $Param{DB},
        LastError    => '',
        JSON         => JSON::PP->new->canonical(1),
        LanguageData => {},
    }, $Class;
}

sub Error { return $_[0]->{LastError} || ''; }

sub AgentList {
    my ($Self) = @_;
    return $Self->{DB}->SelectAll(
        'SELECT id, login, email,
                COALESCE(NULLIF(TRIM(CONCAT(firstname, " ", lastname)), ""), login) AS display_name
         FROM user_account
         WHERE account_type = "agent" AND is_active = 1 AND email <> ""
         ORDER BY display_name, login, id'
    ) || [];
}

sub ScheduleGet {
    my ( $Self, %Param ) = @_;
    my $ReportID = $Self->_ID( $Param{ReportID} );
    return $Self->_DefaultSchedule() if !$ReportID;

    my $Schedule = $Self->{DB}->SelectRow(
        'SELECT * FROM report_schedule WHERE report_definition_id = ? LIMIT 1',
        $ReportID,
    );
    return $Self->_DefaultSchedule() if !$Schedule;

    my $Recipients = $Self->{DB}->SelectAll(
        'SELECT recipient_type, user_account_id, email, display_name
         FROM report_schedule_recipient
         WHERE report_schedule_id = ?
         ORDER BY recipient_type, display_name, email, id',
        $Schedule->{id},
    ) || [];
    $Schedule->{agent_ids} = [ map { 0 + $_->{user_account_id} }
        grep { ( $_->{recipient_type} || '' ) eq 'agent' && $_->{user_account_id} } @{$Recipients} ];
    $Schedule->{additional_emails} = join "\n", map { $_->{email} }
        grep { ( $_->{recipient_type} || '' ) eq 'email' } @{$Recipients};
    $Schedule->{format_list} = [ grep { $_ } split /,/, ( $Schedule->{formats} || '' ) ];
    return $Schedule;
}

sub ScheduleSave {
    my ( $Self, %Param ) = @_;
    $Self->{LastError} = '';

    my $ReportID = $Self->_ID( $Param{ReportID} );
    my $UserID   = $Self->_ID( $Param{UserID} );
    if ( !$ReportID || !$UserID ) {
        return $Self->_Fail('Translate:ReportScheduleErrorSave');
    }

    my $Active = $Param{Active} ? 1 : 0;
    my $Frequency = $Param{Frequency} || 'daily';
    $Frequency = 'daily' if $Frequency !~ m{\A(?:daily|weekly|monthly)\z};
    my $SendTime = $Param{SendTime} || '08:00';
    if ( $SendTime !~ m{\A([01]\d|2[0-3]):([0-5]\d)(?::[0-5]\d)?\z} ) {
        return $Self->_Fail('Translate:ReportScheduleErrorTime');
    }
    $SendTime .= ':00' if length($SendTime) == 5;

    my $Weekday = $Param{Weekday};
    $Weekday = 1 if !defined $Weekday || $Weekday !~ m{\A[1-7]\z};
    my $Monthday = $Param{Monthday};
    $Monthday = 1 if !defined $Monthday || $Monthday !~ m{\A(?:[1-9]|1\d|2[0-8])\z};

    my $PeriodType = $Param{PeriodType} || 'previous_month';
    $PeriodType = 'previous_month'
        if $PeriodType !~ m{\A(?:fixed|previous_day|previous_week|previous_month|rolling_days)\z};
    my $RollingDays = $Param{RollingDays};
    $RollingDays = 30 if !defined $RollingDays || $RollingDays !~ m{\A\d+\z} || $RollingDays < 1;
    $RollingDays = 365 if $RollingDays > 365;

    my $Report = $Self->{DB}->SelectRow(
        'SELECT data_source FROM report_definition WHERE id = ? AND active = 1 LIMIT 1',
        $ReportID,
    );
    return $Self->_Fail('Translate:ReportErrorNotFound') if !$Report;
    my $PeriodField = $Self->_PeriodFieldValidate(
        Source => $Report->{data_source},
        Field  => $Param{PeriodField},
    );
    return $Self->_Fail('Translate:ReportScheduleErrorPeriodField') if !$PeriodField;

    my %AllowedFormat = map { $_ => 1 } qw(pdf csv_analysis csv_detail);
    my %SeenFormat;
    my @Formats = grep { $AllowedFormat{$_} && !$SeenFormat{$_}++ }
        @{ ref $Param{Formats} eq 'ARRAY' ? $Param{Formats} : [] };
    @Formats = ('pdf') if !@Formats && !$Active;
    return $Self->_Fail('Translate:ReportScheduleErrorFormat') if !@Formats;

    my @AgentIDs = @{ ref $Param{AgentIDs} eq 'ARRAY' ? $Param{AgentIDs} : [] };
    my %SeenID;
    @AgentIDs = grep { $_ && !$SeenID{$_}++ } map { $Self->_ID($_) } @AgentIDs;
    my @Agents;
    if (@AgentIDs) {
        my $Placeholder = join ',', map {'?'} @AgentIDs;
        my $Rows = $Self->{DB}->SelectAll(
            'SELECT id, email,
                    COALESCE(NULLIF(TRIM(CONCAT(firstname, " ", lastname)), ""), login) AS display_name
             FROM user_account
             WHERE account_type = "agent" AND is_active = 1 AND email <> "" AND id IN (' . $Placeholder . ')',
            @AgentIDs,
        ) || [];
        @Agents = @{$Rows};
    }

    my @Additional;
    my %SeenEmail = map { lc( $_->{email} || '' ) => 1 } @Agents;
    for my $Email ( split /[\s,;]+/, ( $Param{AdditionalEmails} || '' ) ) {
        $Email =~ s{\A\s+|\s+\z}{}g;
        next if $Email eq '';
        if ( $Email !~ m{\A[^\s\@]+\@[^\s\@]+\.[^\s\@]+\z} || length($Email) > 255 ) {
            return $Self->_Fail('Translate:ReportScheduleErrorEmail');
        }
        next if $SeenEmail{ lc $Email }++;
        push @Additional, $Email;
    }
    if ( $Active && !@Agents && !@Additional ) {
        return $Self->_Fail('Translate:ReportScheduleErrorRecipient');
    }

    my $ScheduleData = {
        frequency    => $Frequency,
        send_time    => $SendTime,
        weekday      => $Frequency eq 'weekly' ? $Weekday : undef,
        monthday     => $Frequency eq 'monthly' ? $Monthday : undef,
        period_type  => $PeriodType,
        period_field => $PeriodField,
        rolling_days => $PeriodType eq 'rolling_days' ? $RollingDays : undef,
    };
    my $NextRunAt = $Active ? $Self->_NextRunAt( Schedule => $ScheduleData, After => time ) : undef;

    $Self->{DB}->BeginWork() || return $Self->_Fail( $Self->{DB}->Error() || 'Translate:ReportScheduleErrorSave' );
    my $OK = $Self->{DB}->Do(
        'INSERT INTO report_schedule (
            report_definition_id, active, frequency, send_time, weekday, monthday,
            period_type, period_field, rolling_days, formats, next_run_at,
            created_by_user_id, changed_by_user_id
         ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
         ON DUPLICATE KEY UPDATE active = VALUES(active), frequency = VALUES(frequency),
            send_time = VALUES(send_time), weekday = VALUES(weekday), monthday = VALUES(monthday),
            period_type = VALUES(period_type), period_field = VALUES(period_field),
            rolling_days = VALUES(rolling_days), formats = VALUES(formats),
            next_run_at = VALUES(next_run_at), changed_by_user_id = VALUES(changed_by_user_id),
            changed_at = NOW()',
        $ReportID, $Active, $Frequency, $SendTime,
        $ScheduleData->{weekday}, $ScheduleData->{monthday}, $PeriodType, $PeriodField,
        $ScheduleData->{rolling_days}, join( ',', @Formats ), $NextRunAt, $UserID, $UserID,
    );
    my $Schedule = $OK ? $Self->{DB}->SelectRow(
        'SELECT id FROM report_schedule WHERE report_definition_id = ? LIMIT 1', $ReportID
    ) : undef;
    $OK = 0 if !$Schedule || !$Schedule->{id};
    $OK = $Self->{DB}->Do(
        'DELETE FROM report_schedule_recipient WHERE report_schedule_id = ?', $Schedule->{id}
    ) if $OK;
    if ($OK) {
        for my $Agent (@Agents) {
            $OK = $Self->{DB}->Do(
                'INSERT INTO report_schedule_recipient
                    (report_schedule_id, recipient_type, user_account_id, email, display_name)
                 VALUES (?, "agent", ?, ?, ?)',
                $Schedule->{id}, $Agent->{id}, $Agent->{email}, $Agent->{display_name} || '',
            );
            last if !$OK;
        }
    }
    if ($OK) {
        for my $Email (@Additional) {
            $OK = $Self->{DB}->Do(
                'INSERT INTO report_schedule_recipient
                    (report_schedule_id, recipient_type, user_account_id, email, display_name)
                 VALUES (?, "email", NULL, ?, "")',
                $Schedule->{id}, $Email,
            );
            last if !$OK;
        }
    }
    if ( !$OK || !$Self->{DB}->Commit() ) {
        $Self->{DB}->Rollback();
        return $Self->_Fail( $Self->{DB}->Error() || 'Translate:ReportScheduleErrorSave' );
    }
    return 1;
}

sub ProcessDue {
    my ( $Self, %Param ) = @_;
    $Self->{LastError} = '';
    my $Limit = $Param{Limit} || 20;
    $Limit = 20 if $Limit !~ m{\A\d+\z} || $Limit < 1;
    $Limit = 100 if $Limit > 100;

    my $Rows = $Self->{DB}->SelectAll(
        'SELECT rs.*, rd.owner_user_id, rd.name AS report_name, rd.description AS report_description,
                rd.configuration_json, rd.data_source, ua.is_active AS owner_active
         FROM report_schedule rs
         INNER JOIN report_definition rd ON rd.id = rs.report_definition_id AND rd.active = 1
         INNER JOIN user_account ua ON ua.id = rd.owner_user_id
         WHERE rs.active = 1 AND rs.next_run_at IS NOT NULL AND rs.next_run_at <= NOW()
         ORDER BY rs.next_run_at, rs.id
         LIMIT ' . int($Limit)
    );
    if ( !defined $Rows ) {
        return $Self->_Fail( $Self->{DB}->Error() || 'Report schedules could not be loaded' );
    }

    my $Processed = 0;
    for my $Schedule (@{$Rows}) {
        $Processed++ if $Self->_ProcessSchedule( Schedule => $Schedule );
    }
    return $Processed;
}

sub _ProcessSchedule {
    my ( $Self, %Param ) = @_;
    my $Schedule = $Param{Schedule} || {};
    my $ScheduledFor = $Schedule->{next_run_at};
    return if !$ScheduledFor;

    my $Existing = $Self->{DB}->SelectRow(
        'SELECT id FROM report_delivery_log WHERE report_schedule_id = ? AND scheduled_for = ? LIMIT 1',
        $Schedule->{id}, $ScheduledFor,
    );
    if ($Existing) {
        my $Next = $Self->_NextRunAt( Schedule => $Schedule, After => time );
        $Self->{DB}->Do('UPDATE report_schedule SET next_run_at = ? WHERE id = ?', $Next, $Schedule->{id});
        return;
    }

    my $Recipients = $Self->{DB}->SelectAll(
        'SELECT email, display_name FROM report_schedule_recipient
         WHERE report_schedule_id = ? ORDER BY id',
        $Schedule->{id},
    ) || [];
    my @Emails = map { $_->{email} } grep { $_->{email} } @{$Recipients};
    my ( $PeriodStart, $PeriodEnd ) = $Self->_DateRange(
        PeriodType => $Schedule->{period_type},
        RollingDays => $Schedule->{rolling_days},
        Now => time,
    );
    my $RecipientJSON = $Self->{JSON}->encode(\@Emails);
    my $Inserted = $Self->{DB}->Do(
        'INSERT INTO report_delivery_log (
            report_schedule_id, report_definition_id, scheduled_for, status,
            recipients_json, formats, period_start, period_end, started_at
         ) VALUES (?, ?, ?, "processing", ?, ?, ?, ?, NOW())',
        $Schedule->{id}, $Schedule->{report_definition_id}, $ScheduledFor,
        $RecipientJSON, $Schedule->{formats}, $PeriodStart, $PeriodEnd,
    );
    return if !$Inserted;
    my $LogID = $Self->{DB}->LastInsertID('report_delivery_log');
    my $Next = $Self->_NextRunAt( Schedule => $Schedule, After => time );
    $Self->{DB}->Do(
        'UPDATE report_schedule SET next_run_at = ?, last_run_at = NOW(), last_status = "processing", last_error = NULL WHERE id = ?',
        $Next, $Schedule->{id},
    );

    my $Error = '';
    if ( !$Schedule->{owner_active} ) {
        $Error = 'Report owner is inactive';
    }
    elsif ( !@Emails ) {
        $Error = 'No report recipients are configured';
    }
    my $Configuration = eval { $Self->{JSON}->decode( $Schedule->{configuration_json} || '{}' ) };
    if ( !$Error && ref $Configuration ne 'HASH' ) {
        $Error = 'Report configuration is invalid';
    }
    my $DisplayConfiguration = $Configuration;
    my $MandatoryFilters = [];
    if ( !$Error && ( $Schedule->{period_type} || '' ) ne 'fixed' ) {
        $DisplayConfiguration = $Self->_ConfigurationForPeriod(
            Configuration => $Configuration,
            Field         => $Schedule->{period_field},
            Start         => $PeriodStart,
            End           => $PeriodEnd,
        );
        $MandatoryFilters = [ {
            field => $Schedule->{period_field}, operator => 'between',
            values => [ $PeriodStart, $PeriodEnd ], value_labels => [ $PeriodStart, $PeriodEnd ],
        } ];
    }

    my @Formats = grep { $_ } split /,/, ( $Schedule->{formats} || '' );
    my $DetailLimit = grep { $_ eq 'csv_detail' } @Formats ? 50000 : 200;
    my $Result;
    if (!$Error) {
        my $Builder = QisutuReportBuilder->new( Config => $Self->{Config}, DB => $Self->{DB} );
        $Result = $Builder->Execute(
            Configuration => $Configuration,
            User          => { user_account_id => $Schedule->{owner_user_id} },
            ReportID      => $Schedule->{report_definition_id},
            ExecutionType => 'scheduled_mail',
            DetailLimit   => $DetailLimit,
            MandatoryFilters => $MandatoryFilters,
        );
        $Error = $Builder->Error() || 'Report execution failed' if !$Result;
        $Result->{configuration} = $DisplayConfiguration if $Result;
    }

    my $Language = $Self->{Config}->{Language}->{Default} || 'en';
    my @Attachments;
    if (!$Error) {
        $Self->_ResultTranslate( Result => $Result, Language => $Language );
        @Attachments = @{ $Self->_Attachments(
            Formats    => \@Formats,
            Name       => $Schedule->{report_name},
            Description => $Schedule->{report_description},
            Result     => $Result,
            Language   => $Language,
        ) };
        $Error = 'No report format is configured' if !@Attachments;
    }

    if (!$Error) {
        my $SMTP = $Self->{DB}->SelectRow(
            'SELECT * FROM smtp_account WHERE active = 1 ORDER BY sort_order, id LIMIT 1'
        );
        my $Sender = $Self->{DB}->SelectRow(
            'SELECT name, email FROM system_email WHERE active = 1 ORDER BY sort_order, id LIMIT 1'
        );
        if ( !$SMTP || !$Sender || !$Sender->{email} ) {
            $Error = 'No active SMTP account or system e-mail address is configured';
        }
        else {
            my $Subject = $Self->_T('ReportScheduleMailSubject', $Language, report => $Schedule->{report_name});
            my $Period = $PeriodStart && $PeriodEnd ? "$PeriodStart – $PeriodEnd" : $Self->_T('ReportScheduleFixedPeriod', $Language);
            my $PlainBody = $Self->_T('ReportScheduleMailBody', $Language, report => $Schedule->{report_name}, period => $Period);
            my @SendErrors;
            for my $Email (@Emails) {
                my $Send = QisutuMail->new( Config => $Self->{Config}, DB => $Self->{DB} )->SMTPSend(
                    Account     => $SMTP,
                    Operation   => 'report_schedule',
                    FromName    => $Sender->{name} || 'Qisutu',
                    FromEmail   => $Sender->{email},
                    ToName      => $Self->_T('ReportScheduleRecipients', $Language),
                    ToEmail     => $Email,
                    Subject     => $Subject,
                    Body        => '<p>' . $Self->_HTMLEscape($PlainBody) . '</p>',
                    PlainBody   => $PlainBody,
                    Attachments => \@Attachments,
                );
                if ( !$Send || !$Send->{Success} ) {
                    push @SendErrors, $Email . ': '
                        . ( $Send && $Send->{Message} ? $Send->{Message} : 'Report e-mail could not be sent' );
                }
            }
            $Error = join '; ', @SendErrors if @SendErrors;
        }
    }

    my $Status = $Error ? 'failed' : 'sent';
    $Self->{DB}->Do(
        'UPDATE report_delivery_log SET status = ?, error_message = ?, finished_at = NOW() WHERE id = ?',
        $Status, $Error || undef, $LogID,
    );
    $Self->{DB}->Do(
        'UPDATE report_schedule SET last_status = ?, last_error = ? WHERE id = ?',
        $Status, $Error || undef, $Schedule->{id},
    );
    return 1;
}

sub _Attachments {
    my ( $Self, %Param ) = @_;
    my @Attachment;
    my $Filename = $Self->_Filename( $Param{Name} );
    for my $Format ( @{ $Param{Formats} || [] } ) {
        if ( $Format eq 'pdf' ) {
            my $Generated = strftime('%Y-%m-%d %H:%M:%S', localtime);
            my $Content = QisutuReportPDF->new()->Create(
                Title          => $Param{Name},
                Description    => $Param{Description},
                GeneratedLabel => $Self->_T('ReportGeneratedAt', $Param{Language}) . ' ' . $Generated,
                FilterLabel    => $Self->_FilterSummary( $Param{Result}->{configuration}, $Param{Language} ),
                ResultLabel    => $Self->_T('ReportResults', $Param{Language}),
                DetailLabel    => $Self->_T('ReportDetails', $Param{Language}),
                FooterLabel    => $Self->_T('ReportPDFConfidential', $Param{Language}),
                Result         => $Param{Result},
            );
            push @Attachment, { Filename => "$Filename.pdf", ContentType => 'application/pdf', Content => $Content, ContentSize => length($Content) };
        }
        elsif ( $Format eq 'csv_analysis' || $Format eq 'csv_detail' ) {
            my $Analysis = $Format eq 'csv_analysis' ? 1 : 0;
            my $Content = $Self->_CSV( Result => $Param{Result}, Analysis => $Analysis );
            push @Attachment, {
                Filename => $Filename . ( $Analysis ? '-analysis.csv' : '-details.csv' ),
                ContentType => 'text/csv; charset=UTF-8', Content => $Content, ContentSize => length($Content),
            };
        }
    }
    return \@Attachment;
}

sub _CSV {
    my ( $Self, %Param ) = @_;
    my $Result = $Param{Result};
    my @Lines;
    if ( $Param{Analysis} ) {
        push @Lines, join ';', map { $Self->_CSVField($_) }
            ( $Result->{group}->{label}, map { $_->{label} } @{ $Result->{metrics} || [] } );
        for my $Row ( @{ $Result->{rows} || [] } ) {
            push @Lines, join ';', map { $Self->_CSVField($_) } ( $Row->{label}, @{ $Row->{values} || [] } );
        }
    }
    else {
        push @Lines, join ';', map { $Self->_CSVField( $_->{label} ) } @{ $Result->{details}->{columns} || [] };
        for my $Row ( @{ $Result->{details}->{rows} || [] } ) {
            push @Lines, join ';', map { $Self->_CSVField($_) } @{$Row};
        }
    }
    return chr(0xFEFF) . join("\r\n", @Lines) . "\r\n";
}

sub _ConfigurationForPeriod {
    my ( $Self, %Param ) = @_;
    my $Configuration = eval { $Self->{JSON}->decode( $Self->{JSON}->encode( $Param{Configuration} ) ) } || {};
    my @Filters = grep { ( $_->{field} || '' ) ne ( $Param{Field} || '' ) }
        @{ ref $Configuration->{filters} eq 'ARRAY' ? $Configuration->{filters} : [] };
    push @Filters, {
        field => $Param{Field}, operator => 'between',
        values => [ $Param{Start}, $Param{End} ], value_labels => [ $Param{Start}, $Param{End} ],
    };
    $Configuration->{filters} = \@Filters;
    return $Configuration;
}

sub _PeriodFieldValidate {
    my ( $Self, %Param ) = @_;
    my $Builder = QisutuReportBuilder->new( Config => $Self->{Config}, DB => $Self->{DB} );
    my ($Source) = grep { ( $_->{key} || '' ) eq ( $Param{Source} || '' ) } @{ $Builder->Catalog()->{sources} || [] };
    return if !$Source;
    my @DateFields = grep { ( $_->{type} || '' ) eq 'date' } @{ $Source->{fields} || [] };
    my $Requested = $Param{Field} || '';
    my ($Match) = grep { ( $_->{key} || '' ) eq $Requested } @DateFields;
    return $Match->{key} if $Match;
    return if $Requested ne '';
    return @DateFields ? $DateFields[0]->{key} : undef;
}

sub _DateRange {
    my ( $Self, %Param ) = @_;
    my $Type = $Param{PeriodType} || 'fixed';
    return if $Type eq 'fixed';
    my $Now = $Param{Now} || time;
    my @Now = localtime($Now);
    my $Today = timelocal( 0, 0, 0, $Now[3], $Now[4], $Now[5] );
    my ( $Start, $End );
    if ( $Type eq 'previous_day' ) {
        $Start = $End = $Today - 86400;
    }
    elsif ( $Type eq 'previous_week' ) {
        my $DaysSinceMonday = ( $Now[6] + 6 ) % 7;
        $End = $Today - ( $DaysSinceMonday + 1 ) * 86400;
        $Start = $End - 6 * 86400;
    }
    elsif ( $Type eq 'previous_month' ) {
        my ( $Year, $Month ) = ( $Now[5] + 1900, $Now[4] );
        if ( $Month == 0 ) { $Year--; $Month = 12; }
        $Start = timelocal( 0, 0, 0, 1, $Month - 1, $Year - 1900 );
        $End = timelocal( 0, 0, 0, 1, $Now[4], $Now[5] ) - 86400;
    }
    else {
        my $Days = $Param{RollingDays} || 30;
        $End = $Today - 86400;
        $Start = $End - ( $Days - 1 ) * 86400;
    }
    return strftime('%Y-%m-%d', localtime($Start)), strftime('%Y-%m-%d', localtime($End));
}

sub _NextRunAt {
    my ( $Self, %Param ) = @_;
    my $Schedule = $Param{Schedule} || {};
    my $After = $Param{After} || time;
    my ( $Hour, $Minute, $Second ) = split /:/, ( $Schedule->{send_time} || '08:00:00' );
    my @Now = localtime($After);
    my $Target;
    if ( ( $Schedule->{frequency} || '' ) eq 'weekly' ) {
        my $Today = $Now[6] == 0 ? 7 : $Now[6];
        my $Delta = ( ( $Schedule->{weekday} || 1 ) - $Today + 7 ) % 7;
        $Target = timelocal( $Second, $Minute, $Hour, $Now[3] + $Delta, $Now[4], $Now[5] );
        $Target = timelocal( $Second, $Minute, $Hour, $Now[3] + 7, $Now[4], $Now[5] ) if $Target <= $After;
    }
    elsif ( ( $Schedule->{frequency} || '' ) eq 'monthly' ) {
        my $Day = $Schedule->{monthday} || 1;
        $Target = timelocal( $Second, $Minute, $Hour, $Day, $Now[4], $Now[5] );
        $Target = timelocal( $Second, $Minute, $Hour, $Day, $Now[4] + 1, $Now[5] ) if $Target <= $After;
    }
    else {
        $Target = timelocal( $Second, $Minute, $Hour, $Now[3], $Now[4], $Now[5] );
        $Target = timelocal( $Second, $Minute, $Hour, $Now[3] + 1, $Now[4], $Now[5] ) if $Target <= $After;
    }
    return strftime('%Y-%m-%d %H:%M:%S', localtime($Target));
}

sub _DefaultSchedule {
    return {
        active => 0, frequency => 'daily', send_time => '08:00:00', weekday => 1, monthday => 1,
        period_type => 'previous_month', period_field => 'created_at', rolling_days => 30,
        formats => 'pdf', format_list => ['pdf'], agent_ids => [], additional_emails => '',
        next_run_at => undef, last_run_at => undef, last_status => '', last_error => '',
    };
}

sub _ResultTranslate {
    my ( $Self, %Param ) = @_;
    my $Result = $Param{Result};
    my $Language = $Param{Language};
    for my $Metric ( @{ $Result->{metrics} || [] } ) {
        $Metric->{label} = $Self->_T( $Metric->{label_key}, $Language );
    }
    my $Group = $Result->{group} || {};
    $Group->{label} ||= $Self->_T( $Group->{label_key}, $Language );
    my $Columns = $Result->{details}->{columns} || [];
    for my $Index ( 0 .. $#{$Columns} ) {
        my $Column = $Columns->[$Index];
        $Column->{label} ||= $Self->_T( $Column->{label_key}, $Language );
        if ( ( $Column->{type} || '' ) eq 'boolean' ) {
            for my $Row ( @{ $Result->{details}->{rows} || [] } ) {
                $Row->[$Index] = $Self->_T( $Row->[$Index] ? 'Yes' : 'No', $Language );
            }
        }
    }
}

sub _FilterSummary {
    my ( $Self, $Configuration, $Language ) = @_;
    my @Parts;
    for my $Filter ( @{ $Configuration->{filters} || [] } ) {
        my @Values = @{ $Filter->{value_labels} || [] };
        @Values = @{ $Filter->{values} || [] } if !@Values;
        push @Parts, ( $Filter->{field} || '' ) . ' ' . ( $Filter->{operator} || '' ) . ' ' . join( ', ', @Values );
    }
    return @Parts ? join( ' · ', @Parts ) : $Self->_T('ReportNoFilters', $Language);
}

sub _T {
    my ( $Self, $Key, $Language, %Replace ) = @_;
    return '' if !$Key;
    $Language ||= 'en';
    if ( !$Self->{LanguageData}->{$Language} ) {
        my $Path = File::Spec->catfile( $Self->{Config}->{Paths}->{Language} || '', "$Language.pm" );
        my $Data = $Path && -f $Path ? do $Path : undef;
        $Self->{LanguageData}->{$Language} = ref $Data eq 'HASH' ? $Data : {};
    }
    my $Value = $Self->{LanguageData}->{$Language}->{$Key};
    $Value = $Key if !defined $Value;
    for my $Name ( keys %Replace ) {
        my $Replacement = defined $Replace{$Name} ? $Replace{$Name} : '';
        $Value =~ s{\Q{$Name}\E}{$Replacement}g;
    }
    return $Value;
}

sub _CSVField {
    my ( $Self, $Value ) = @_;
    $Value = '' if !defined $Value;
    $Value = "'$Value" if $Value =~ m{\A[\t\r ]*[=+\-\@]};
    $Value =~ s{"}{""}g;
    return '"' . $Value . '"';
}

sub _Filename {
    my ( $Self, $Value ) = @_;
    $Value = lc( $Value || 'qisutu-report' );
    $Value =~ s{[^a-z0-9_-]+}{-}g;
    $Value =~ s{\A-+|-+\z}{}g;
    return substr( $Value || 'qisutu-report', 0, 80 );
}

sub _HTMLEscape {
    my ( $Self, $Value ) = @_;
    $Value = '' if !defined $Value;
    $Value =~ s{&}{&amp;}g;
    $Value =~ s{<}{&lt;}g;
    $Value =~ s{>}{&gt;}g;
    $Value =~ s{"}{&quot;}g;
    $Value =~ s{'}{&#39;}g;
    return $Value;
}

sub _ID {
    my ( $Self, $Value ) = @_;
    return defined $Value && $Value =~ m{\A\d+\z} && $Value > 0 ? int($Value) : 0;
}

sub _Fail {
    my ( $Self, $Error ) = @_;
    $Self->{LastError} = $Error || 'Report schedule failed';
    return;
}

1;
