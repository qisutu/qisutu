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

package AdminAutomationJobs;

use strict;
use warnings;
use utf8;

use QisutuAutomation;

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
    my $Object = QisutuAutomation->new( Config => $Self->{Config}, DB => $Self->{DB} );
    my $Step = $Request->{Step} || '';

    if ( $Step eq 'JobRetry' ) {
        $Object->JobRetry( JobID => $Request->{JobID} );
        return { Redirect => 'index.pl?Page=AdminAutomationJobs;Status=' . ( $Request->{Status} || '' ) } if !$Object->Error();
    }
    elsif ( $Step eq 'JobCancel' ) {
        $Object->JobCancel( JobID => $Request->{JobID} );
        return { Redirect => 'index.pl?Page=AdminAutomationJobs;Status=' . ( $Request->{Status} || '' ) } if !$Object->Error();
    }

    my $Status = $Request->{Status} || '';
    my $Jobs = $Object->JobList( Status => $Status, Limit => 300 );
    for my $Job ( @{$Jobs} ) {
        $Job->{status_class} = 'qisutu-automation-status-' . ( $Job->{status} || 'pending' );
        $Job->{can_retry} = ( $Job->{status} || '' ) =~ m{\A(?:failed|cancelled)\z} ? 1 : 0;
        $Job->{can_cancel} = ( $Job->{status} || '' ) eq 'pending' ? 1 : 0;
        $Job->{ticket_display} = $Job->{ticket_id} || '-';
        $Job->{rule_display} = $Job->{rule_name} || '-';
        $Job->{error_display} = $Job->{error_message} || '-';
    }

    return {
        Template => 'AdminAutomationJobs.tt',
        Data => {
            PageTitle => 'Translate:AdminAutomationJobsTitle',
            ProgramTitle => 'Translate:AdminAutomationJobsTitle',
            ProgramDescription => 'Translate:AdminAutomationJobsDescription',
            Jobs => $Jobs,
            JobCount => scalar @{$Jobs},
            JobsRowsHTML => $Self->_JobsRowsHTML( Jobs => $Jobs, Language => ( $Request->{Language} || 'en' ), Status => $Status ),
            SelectedStatus => $Status,
            StatusAllSelected => !$Status ? 'selected' : '',
            StatusPendingSelected => $Status eq 'pending' ? 'selected' : '',
            StatusRunningSelected => $Status eq 'running' ? 'selected' : '',
            StatusSuccessfulSelected => $Status eq 'successful' ? 'selected' : '',
            StatusFailedSelected => $Status eq 'failed' ? 'selected' : '',
            StatusCancelledSelected => $Status eq 'cancelled' ? 'selected' : '',
            ErrorMessage => $Object->Error(),
            ErrorClass => $Object->Error() ? '' : 'qisutu-hidden',
        },
    };
}


sub _JobsRowsHTML {
    my ( $Self, %Param ) = @_;
    my $Language = $Param{Language} || 'en';
    my $SelectedStatus = $Param{Status} || '';
    my $HTML = '';
    my %StatusKey = (
        pending => 'AutomationStatusPending', running => 'AutomationStatusRunning',
        successful => 'AutomationStatusSuccessful', failed => 'AutomationStatusFailed',
        cancelled => 'AutomationStatusCancelled',
    );
    my $Retry = $Self->{Output}->Translate( Key => 'AutomationRetry', Language => $Language );
    my $Cancel = $Self->{Output}->Translate( Key => 'AutomationCancel', Language => $Language );

    for my $Job ( @{ $Param{Jobs} || [] } ) {
        my $Status = $Job->{status} || 'pending';
        my $StatusText = $Self->{Output}->Translate( Key => $StatusKey{$Status} || 'AutomationStatusPending', Language => $Language );
        $HTML .= '<tr>';
        $HTML .= '<td>' . int( $Job->{id} || 0 ) . '</td>';
        $HTML .= '<td>' . $Self->{Output}->HTMLEscape( $Job->{rule_display} || '-' ) . '</td>';
        $HTML .= '<td>' . $Self->{Output}->HTMLEscape( $Job->{job_type} || '-' ) . '</td>';
        $HTML .= '<td>' . $Self->{Output}->HTMLEscape( $Job->{ticket_display} || '-' ) . '</td>';
        $HTML .= '<td><span class="qisutu-automation-status ' . $Self->{Output}->HTMLEscape( $Job->{status_class} || '' ) . '">' . $Self->{Output}->HTMLEscape($StatusText) . '</span></td>';
        $HTML .= '<td>' . int( $Job->{attempts} || 0 ) . ' / ' . int( $Job->{max_attempts} || 0 ) . '</td>';
        $HTML .= '<td>' . $Self->{Output}->HTMLEscape( $Job->{scheduled_at} || '-' ) . '</td>';
        $HTML .= '<td>' . $Self->{Output}->HTMLEscape( $Job->{finished_at} || '-' ) . '</td>';
        $HTML .= '<td class="qisutu-automation-job-error">' . $Self->{Output}->HTMLEscape( $Job->{error_display} || '-' ) . '</td>';
        $HTML .= '<td>';
        if ( $Job->{can_retry} ) {
            $HTML .= $Self->_JobActionForm( Step => 'JobRetry', JobID => $Job->{id}, Status => $SelectedStatus, Label => $Retry );
        }
        if ( $Job->{can_cancel} ) {
            $HTML .= $Self->_JobActionForm( Step => 'JobCancel', JobID => $Job->{id}, Status => $SelectedStatus, Label => $Cancel );
        }
        $HTML .= '</td></tr>';
    }
    return $HTML;
}

sub _JobActionForm {
    my ( $Self, %Param ) = @_;
    return '<form method="post" action="index.pl" class="qisutu-inline-form">' .
        '<input type="hidden" name="Page" value="AdminAutomationJobs">' .
        '<input type="hidden" name="Step" value="' . $Self->{Output}->HTMLEscape( $Param{Step} || '' ) . '">' .
        '<input type="hidden" name="JobID" value="' . int( $Param{JobID} || 0 ) . '">' .
        '<input type="hidden" name="Status" value="' . $Self->{Output}->HTMLEscape( $Param{Status} || '' ) . '">' .
        '<button class="qisutu-button qisutu-button-secondary qisutu-button-small" type="submit">' . $Self->{Output}->HTMLEscape( $Param{Label} || '' ) . '</button>' .
        '</form>';
}

1;
