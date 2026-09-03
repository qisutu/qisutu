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

use Cwd qw(abs_path);
use FindBin;
use File::Spec;
use Sys::Hostname qw(hostname);
use Time::HiRes qw(sleep);

my $QisutuHome = $ENV{QISUTU_HOME} || abs_path( File::Spec->catdir( $FindBin::Bin, '..' ) );
$ENV{QISUTU_HOME} ||= $QisutuHome;

unshift @INC,
    File::Spec->catdir( $QisutuHome, 'core', 'config' ),
    File::Spec->catdir( $QisutuHome, 'core', 'system' ),
    File::Spec->catdir( $QisutuHome, 'core', 'cpan-lib' );

main();

sub main {
    require QisutuConfig;
    require QisutuDB;
    require QisutuAutomation;
    require QisutuRuntimeLock;
    require QisutuTicket;
    require QisutuAddonRuntime;
    require QisutuAddonManager;
    require QisutuAddonEvent;
    require QisutuReportScheduler;
    require QisutuSystemSetting;

    my $Once = 0;
    my $SleepSeconds = 3;
    my $MaxJobs = 100;
    my $MailFetchInterval = 300;

    for ( my $Index = 0; $Index < @ARGV; $Index++ ) {
        my $Arg = $ARGV[$Index] || '';
        if ( $Arg eq '--once' ) {
            $Once = 1;
        }
        elsif ( $Arg eq '--sleep' && defined $ARGV[ $Index + 1 ] && $ARGV[ $Index + 1 ] =~ m{\A\d+(?:\.\d+)?\z} ) {
            $SleepSeconds = 0 + $ARGV[++$Index];
            $SleepSeconds = 1 if $SleepSeconds < 1;
        }
        elsif ( $Arg eq '--max-jobs' && defined $ARGV[ $Index + 1 ] && $ARGV[ $Index + 1 ] =~ m{\A\d+\z} ) {
            $MaxJobs = 0 + $ARGV[++$Index];
            $MaxJobs = 1 if $MaxJobs < 1;
            $MaxJobs = 1000 if $MaxJobs > 1000;
        }
    }

    my $Stop = 0;
    local $SIG{TERM} = sub { $Stop = 1 };
    local $SIG{INT}  = sub { $Stop = 1 };
    local $SIG{HUP}  = sub { };

    if ( QisutuRuntimeLock::MaintenanceActive( RootPath => $QisutuHome ) ) {
        _Log('Update lock is active. Automation daemon will not start.');
        return;
    }

    my $RuntimeLock = QisutuRuntimeLock::SharedAcquire(
        RootPath => $QisutuHome,
    );
    if ( !$RuntimeLock->{Success} ) {
        die( ( $RuntimeLock->{Error} || 'Runtime lock could not be acquired.' ) . "\n" );
    }

    if ( QisutuRuntimeLock::MaintenanceActive( RootPath => $QisutuHome ) ) {
        _Log('Update lock became active. Automation daemon will not start.');
        return;
    }

    my $Config = QisutuConfig::Load();
    my $DB = QisutuDB->new( Config => $Config );
    if ( !$DB->Connect() ) {
        die 'Database connection failed: ' . ( $DB->Error() || 'unknown error' ) . "\n";
    }

    my $Worker = join '-', 'qisutu', hostname(), $$;
    my $Automation = QisutuAutomation->new( Config => $Config, DB => $DB );
    my $TicketObject = QisutuTicket->new( Config => $Config, DB => $DB );
    QisutuAddonRuntime->Apply( Config => $Config, DB => $DB );
    my $AddonManager = QisutuAddonManager->new( Config => $Config, DB => $DB );
    if ( !$AddonManager->InstalledPathPermissionsRepair() ) {
        die 'Installed add-on directory permissions could not be repaired: '
            . ( $AddonManager->Error() || 'unknown error' ) . "\n";
    }
    my $AddonEvent = QisutuAddonEvent->new( Config => $Config, DB => $DB );
    my $ReportScheduler = QisutuReportScheduler->new( Config => $Config, DB => $DB );
    my $LastEscalationCheck = 0;
    my $LastMailFetch = 0;
    my $LastMailFetchIntervalCheck = 0;
    my $LastReportScheduleCheck = 0;
    my $LastAddonEventCleanup = 0;

    _Log("Automation and mail daemon started as $Worker");

    while ( !$Stop ) {
        if ( QisutuRuntimeLock::MaintenanceActive( RootPath => $QisutuHome ) ) {
            _Log('Update lock detected. Automation daemon is stopping.');
            last;
        }

        if ( time - $LastMailFetchIntervalCheck >= 15 ) {
            $MailFetchInterval = _MailFetchIntervalGet( Config => $Config, DB => $DB );
            $LastMailFetchIntervalCheck = time;
        }

        if ( time - $LastMailFetch >= $MailFetchInterval ) {
            $LastMailFetch = time;
            _MailFetchRun( QisutuHome => $QisutuHome );
        }

        if ( time - $LastReportScheduleCheck >= 30 ) {
            my $ReportRuns = $ReportScheduler->ProcessDue( Limit => 20 );
            _Log( 'ERROR: report delivery: ' . $ReportScheduler->Error() )
                if !defined $ReportRuns || $ReportScheduler->Error();
            $LastReportScheduleCheck = time;
        }

        my $AddonOperation = $AddonManager->OperationProcessNext( Worker => $Worker );
        if ( !$AddonOperation && $AddonManager->Error() ) {
            _Log( 'ERROR: add-on operation: ' . $AddonManager->Error() );
        }
        if ($AddonOperation) {
            _Log('Add-on operation completed. The daemon is restarting to activate the changed add-on runtime.');
            last;
        }
        QisutuAddonRuntime->Apply( Config => $Config, DB => $DB );
        my $AddonTask = $AddonManager->TaskRunDue( Worker => $Worker );
        my $AddonEventCount = 0;
        while ( $AddonEventCount < $MaxJobs && !$Stop ) {
            my $AddonEventProcessed = $AddonEvent->ProcessNext( Worker => $Worker );
            if ( !$AddonEventProcessed ) {
                _Log( 'ERROR: add-on event: ' . $AddonEvent->Error() ) if $AddonEvent->Error();
                last;
            }
            $AddonEventCount++;
        }
        if ( time - $LastAddonEventCleanup >= 3600 ) {
            $AddonEvent->Cleanup();
            $LastAddonEventCleanup = time;
        }

        my $Recovered = $Automation->JobRecoverStale();
        if ( !defined $Recovered ) {
            _Log( 'ERROR: ' . ( $Automation->Error() || 'stale job recovery failed' ) );
        }

        my $Schedules = $Automation->EnqueueDueSchedules();
        _Log( 'ERROR: ' . $Automation->Error() ) if $Automation->Error();

        my $DueEvents = $Automation->EnqueueDueTicketEvents();
        _Log( 'ERROR: ' . $Automation->Error() ) if $Automation->Error();

        if ( time - $LastEscalationCheck >= 60 ) {
            my $Escalation = $TicketObject->CheckTicketEscalations(
                Limit           => 5000,
                ChangedByUserID => 1,
            );
            if (!$Escalation) {
                _Log( 'ERROR: ' . ( $TicketObject->Error() || 'ticket escalation check failed' ) );
            }
            $LastEscalationCheck = time;
        }

        my $Events = $Automation->ProcessEvents( Limit => 250 );
        _Log( 'ERROR: ' . $Automation->Error() ) if $Automation->Error();

        my $Processed = 0;
        while ( $Processed < $MaxJobs && !$Stop ) {
            my $Job = $Automation->JobClaim( Worker => $Worker );
            if ( !$Job ) {
                _Log( 'ERROR: ' . $Automation->Error() ) if $Automation->Error();
                last;
            }

            my $OK = eval { $Automation->JobProcess( Job => $Job ) };
            if ( !$OK && $@ ) {
                $Automation->_JobFail( Job => $Job, Error => $@ );
            }

            my $DBH = $DB->Handle();
            if ($DBH) {
                eval {
                    $DBH->do('SET @qisutu_automation_job_id = NULL');
                    $DBH->do('SET @qisutu_automation_rule_id = NULL');
                    $DBH->do('SET @qisutu_automation_depth = 0');
                };
            }
            $Processed++;
        }

        if ( $Once ) {
            _Log("Automation pass complete: schedules=$Schedules due_events=$DueEvents events=$Events jobs=$Processed");
            last;
        }

        sleep($SleepSeconds) if !$Stop;
    }

    $DB->Disconnect();
    _Log('Automation and mail daemon stopped');
    return;
}

sub _MailFetchIntervalGet {
    my (%Param) = @_;

    my $Minutes = QisutuSystemSetting->new(
        Config => $Param{Config},
        DB     => $Param{DB},
    )->Get(
        Key     => 'mail.fetch_interval_minutes',
        Default => 5,
    );
    my %Allowed = map { $_ => 1 } qw(1 2 5 10 15 30);
    $Minutes = 5 if !defined $Minutes || !$Allowed{$Minutes};

    return 60 * $Minutes;
}

sub _MailFetchRun {
    my (%Param) = @_;

    my $QisutuHome = $Param{QisutuHome} || '';
    my $MailFetchScript = File::Spec->catfile( $QisutuHome, 'bin', 'qisutu-mail-fetch.pl' );

    if ( !$QisutuHome || !-f $MailFetchScript || !-r $MailFetchScript ) {
        _Log("ERROR: Mail-fetch program is missing or unreadable: $MailFetchScript");
        return;
    }

    local $ENV{QISUTU_HOME} = $QisutuHome;
    _Log("Mail fetch started for $QisutuHome");

    my $Status = system { $^X } $^X, $MailFetchScript;
    if ( $Status == -1 ) {
        _Log("ERROR: Mail fetch could not be started: $!");
        return;
    }
    if ( $Status & 127 ) {
        _Log( 'ERROR: Mail fetch was terminated by signal ' . ( $Status & 127 ) );
        return;
    }

    my $ExitCode = $Status >> 8;
    if ($ExitCode) {
        _Log("ERROR: Mail fetch exited with status $ExitCode");
        return;
    }

    _Log("Mail fetch finished for $QisutuHome");
    return 1;
}

sub _Log {
    my ($Message) = @_;
    my @Now = localtime();
    my $Stamp = sprintf '%04d-%02d-%02d %02d:%02d:%02d',
        $Now[5] + 1900, $Now[4] + 1, $Now[3], $Now[2], $Now[1], $Now[0];
    print "$Stamp $Message\n";
    return;
}
