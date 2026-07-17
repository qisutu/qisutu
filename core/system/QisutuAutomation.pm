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

package QisutuAutomation;

use strict;
use warnings;
use utf8;

use JSON::PP;
use POSIX qw(strftime);
use Time::Local qw(timelocal);
use File::Spec;
use File::Basename qw(basename);
use File::Path qw(make_path remove_tree);

use QisutuTicket;
use QisutuChecklist;
use QisutuTicketSearch;
use QisutuDynamicField;

sub new {
    my ( $Class, %Param ) = @_;

    my $Self = {
        Config    => $Param{Config},
        DB        => $Param{DB},
        LastError => '',
        JSON      => JSON::PP->new->utf8(0)->canonical(1)->allow_nonref(1),
    };

    bless $Self, $Class;
    return $Self;
}

sub Error {
    my ($Self) = @_;
    return $Self->{LastError} || '';
}

sub RuleList {
    my ( $Self, %Param ) = @_;
    my $Type = $Param{Type} || '';
    my @Bind;
    my $Where = '';
    if ( $Type =~ m{\A(?:trigger|schedule)\z} ) {
        $Where = 'WHERE rule_type = ?';
        push @Bind, $Type;
    }

    my $Rows = $Self->{DB}->SelectAll(
        'SELECT * FROM automation_rule ' . $Where . '
         ORDER BY sort_order ASC, name ASC, id ASC',
        @Bind,
    );
    if ( !$Rows ) {
        $Self->{LastError} = $Self->{DB}->Error() || 'Automation rules could not be loaded';
        return [];
    }

    for my $Row ( @{$Rows} ) {
        $Row->{conditions} = $Self->_JSONDecode( $Row->{conditions_json}, {} );
        $Row->{actions}    = $Self->_JSONDecode( $Row->{actions_json}, {} );
        $Row->{schedule}   = $Self->_JSONDecode( $Row->{schedule_json}, {} );
        $Row->{condition_summary} = $Self->ConditionSummary( Conditions => $Row->{conditions} );
        $Row->{action_summary}    = $Self->ActionSummary( Actions => $Row->{actions} );
        $Row->{schedule_summary}  = $Self->ScheduleSummary( Schedule => $Row->{schedule} );
    }

    return $Rows;
}

sub RuleGet {
    my ( $Self, %Param ) = @_;
    my $RuleID = $Param{RuleID} || 0;
    return if $RuleID !~ m{\A\d+\z} || !$RuleID;

    my $Row = $Self->{DB}->SelectRow(
        'SELECT * FROM automation_rule WHERE id = ? LIMIT 1',
        $RuleID,
    );
    if ( !$Row ) {
        $Self->{LastError} = $Self->{DB}->Error() || 'Automation rule was not found';
        return;
    }

    $Row->{conditions} = $Self->_JSONDecode( $Row->{conditions_json}, {} );
    $Row->{actions}    = $Self->_JSONDecode( $Row->{actions_json}, {} );
    $Row->{schedule}   = $Self->_JSONDecode( $Row->{schedule_json}, {} );
    return $Row;
}

sub RuleCreate {
    my ( $Self, %Param ) = @_;
    my $Data = $Self->_RuleDataValidate(%Param);
    return if !$Data;

    my $Result = $Self->{DB}->Do(
        'INSERT INTO automation_rule (
            name, description, rule_type, event_name, conditions_json, actions_json,
            schedule_json, next_run_at, active, sort_order,
            created_by_user_id, changed_by_user_id, created_at, changed_at
         ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, NOW(), NOW())',
        $Data->{name},
        $Data->{description},
        $Data->{rule_type},
        $Data->{event_name},
        $Self->_JSONEncode( $Data->{conditions} ),
        $Self->_JSONEncode( $Data->{actions} ),
        $Self->_JSONEncode( $Data->{schedule} ),
        $Data->{next_run_at},
        $Data->{active},
        $Data->{sort_order},
        $Data->{changed_by_user_id},
        $Data->{changed_by_user_id},
    );
    if ( !$Result ) {
        $Self->{LastError} = $Self->{DB}->Error() || 'Automation rule could not be created';
        return;
    }

    return $Self->{DB}->LastInsertID('automation_rule') || 1;
}

sub RuleUpdate {
    my ( $Self, %Param ) = @_;
    my $RuleID = $Param{RuleID} || 0;
    if ( $RuleID !~ m{\A\d+\z} || !$RuleID ) {
        $Self->{LastError} = 'Valid RuleID is required';
        return;
    }

    my $Data = $Self->_RuleDataValidate(%Param);
    return if !$Data;

    my $Result = $Self->{DB}->Do(
        'UPDATE automation_rule
         SET name = ?, description = ?, rule_type = ?, event_name = ?,
             conditions_json = ?, actions_json = ?, schedule_json = ?,
             next_run_at = ?, active = ?, sort_order = ?,
             changed_by_user_id = ?, changed_at = NOW()
         WHERE id = ?',
        $Data->{name},
        $Data->{description},
        $Data->{rule_type},
        $Data->{event_name},
        $Self->_JSONEncode( $Data->{conditions} ),
        $Self->_JSONEncode( $Data->{actions} ),
        $Self->_JSONEncode( $Data->{schedule} ),
        $Data->{next_run_at},
        $Data->{active},
        $Data->{sort_order},
        $Data->{changed_by_user_id},
        $RuleID,
    );
    if ( !$Result ) {
        $Self->{LastError} = $Self->{DB}->Error() || 'Automation rule could not be saved';
        return;
    }

    return 1;
}

sub RuleDeactivate {
    my ( $Self, %Param ) = @_;
    my $RuleID = $Param{RuleID} || 0;
    my $UserID = $Param{ChangedByUserID} || 1;
    return if $RuleID !~ m{\A\d+\z} || !$RuleID;

    my $Result = $Self->{DB}->Do(
        'UPDATE automation_rule SET active = 0, changed_by_user_id = ?, changed_at = NOW() WHERE id = ?',
        $UserID,
        $RuleID,
    );
    if ( !$Result ) {
        $Self->{LastError} = $Self->{DB}->Error() || 'Automation rule could not be deactivated';
        return;
    }
    return 1;
}

sub ConditionsFromRequest {
    my ( $Self, %Param ) = @_;
    my $Request = $Param{Request} || {};

    my $Search = {
        Active          => 1,
        Text            => $Self->_Trim( $Request->{ConditionText} ),
        Mode            => $Request->{ConditionTextMode} || 'all',
        Scopes          => {
            title      => $Request->{ConditionScopeTitle} ? 1 : 0,
            article    => $Request->{ConditionScopeArticle} ? 1 : 0,
            people     => $Request->{ConditionScopePeople} ? 1 : 0,
            attachment => $Request->{ConditionScopeAttachment} ? 1 : 0,
        },
        TicketNumber    => $Self->_Trim( $Request->{ConditionTicketNumber} ),
        Title           => $Self->_Trim( $Request->{ConditionTitle} ),
        QueueIDs        => $Self->_IDList( $Request->{ConditionQueueID} ),
        StateIDs        => $Self->_IDList( $Request->{ConditionStateID} ),
        PriorityIDs     => $Self->_IDList( $Request->{ConditionPriorityID} ),
        CustomerIDs     => $Self->_IDList( $Request->{ConditionCustomerID} ),
        CustomerUserIDs => $Self->_IDList( $Request->{ConditionCustomerUserID} ),
        OwnerIDs        => $Self->_ValueList( $Request->{ConditionOwnerID} ),
        ResponsibleIDs  => $Self->_ValueList( $Request->{ConditionResponsibleID} ),
        ServiceIDs      => $Self->_IDList( $Request->{ConditionServiceID} ),
        SLAIDs          => $Self->_IDList( $Request->{ConditionSLAID} ),
        CreatedFrom     => $Self->_Trim( $Request->{ConditionCreatedFrom} ),
        CreatedTo       => $Self->_Trim( $Request->{ConditionCreatedTo} ),
        ChangedFrom     => $Self->_Trim( $Request->{ConditionChangedFrom} ),
        ChangedTo       => $Self->_Trim( $Request->{ConditionChangedTo} ),
        PendingFrom     => $Self->_Trim( $Request->{ConditionPendingFrom} ),
        PendingTo       => $Self->_Trim( $Request->{ConditionPendingTo} ),
        SolutionFrom    => $Self->_Trim( $Request->{ConditionSolutionFrom} ),
        SolutionTo      => $Self->_Trim( $Request->{ConditionSolutionTo} ),
        FirstResponseDueFrom => $Self->_Trim( $Request->{ConditionFirstResponseDueFrom} ),
        FirstResponseDueTo   => $Self->_Trim( $Request->{ConditionFirstResponseDueTo} ),
        UpdateDueFrom        => $Self->_Trim( $Request->{ConditionUpdateDueFrom} ),
        UpdateDueTo          => $Self->_Trim( $Request->{ConditionUpdateDueTo} ),
        SolutionDueFrom      => $Self->_Trim( $Request->{ConditionSolutionDueFrom} ),
        SolutionDueTo        => $Self->_Trim( $Request->{ConditionSolutionDueTo} ),
        Escalation      => $Self->_ValueList( $Request->{ConditionEscalation} ),
        Dynamic         => [],
    };

    my $Fields = $Param{DynamicFields} || [];
    for my $Field ( @{$Fields} ) {
        my $ID = $Field->{id} || 0;
        next if !$Request->{'ConditionDFEnable_' . $ID};
        push @{ $Search->{Dynamic} }, {
            id       => $ID,
            type     => $Field->{field_type} || 'text',
            operator => $Request->{'ConditionDFOperator_' . $ID} || 'contains',
            value    => $Self->_Trim( $Request->{'ConditionDFValue_' . $ID} ),
            value_to => $Self->_Trim( $Request->{'ConditionDFValueTo_' . $ID} ),
            values   => $Self->_ValueList( $Request->{'ConditionDFValues_' . $ID} ),
        };
    }

    return {
        Search                   => $Search,
        ChangedOlderMinutes      => $Self->_Unsigned( $Request->{ConditionChangedOlderMinutes} ),
        LastCustomerOlderMinutes => $Self->_Unsigned( $Request->{ConditionLastCustomerOlderMinutes} ),
        LastAgentOlderMinutes    => $Self->_Unsigned( $Request->{ConditionLastAgentOlderMinutes} ),
        NoOwner                  => $Request->{ConditionNoOwner} ? 1 : 0,
        NoResponsible            => $Request->{ConditionNoResponsible} ? 1 : 0,
        Checklist                => {
            TemplateIDs    => $Self->_IDList( $Request->{ConditionChecklistTemplateID} ),
            HasOpen        => $Request->{ConditionChecklistHasOpen} ? 1 : 0,
            HasCompleted   => $Request->{ConditionChecklistHasCompleted} ? 1 : 0,
            OpenRequired   => $Request->{ConditionChecklistOpenRequired} ? 1 : 0,
            AllRequiredDone => $Request->{ConditionChecklistAllRequiredDone} ? 1 : 0,
        },
    };
}

sub ActionsFromRequest {
    my ( $Self, %Param ) = @_;
    my $Request = $Param{Request} || {};
    my $Fields  = $Param{DynamicFields} || [];

    my @Dynamic;
    for my $Field ( @{$Fields} ) {
        my $ID = $Field->{id} || 0;
        next if !$Request->{'ActionDFEnable_' . $ID};
        my $Type = $Field->{field_type} || 'text';
        my $Value = $Type eq 'multiselect'
            ? join( "\n", @{ $Self->_ValueList( $Request->{'ActionDFValues_' . $ID} ) } )
            : $Self->_Trim( $Request->{'ActionDFValue_' . $ID} );
        push @Dynamic, {
            id    => $ID,
            type  => $Type,
            value => $Value,
            clear => $Request->{'ActionDFClear_' . $ID} ? 1 : 0,
        };
    }

    return {
        QueueID          => $Self->_Unsigned( $Request->{ActionQueueID} ),
        StateID          => $Self->_Unsigned( $Request->{ActionStateID} ),
        PendingMinutes   => $Self->_Unsigned( $Request->{ActionPendingMinutes} ),
        PriorityID       => $Self->_Unsigned( $Request->{ActionPriorityID} ),
        OwnerMode        => $Request->{ActionOwnerMode} || 'keep',
        OwnerID          => $Self->_Unsigned( $Request->{ActionOwnerID} ),
        ResponsibleMode  => $Request->{ActionResponsibleMode} || 'keep',
        ResponsibleID    => $Self->_Unsigned( $Request->{ActionResponsibleID} ),
        ServiceMode      => $Request->{ActionServiceMode} || 'keep',
        ServiceID        => $Self->_Unsigned( $Request->{ActionServiceID} ),
        Dynamic          => \@Dynamic,
        NoteEnabled      => $Request->{ActionNoteEnabled} ? 1 : 0,
        NoteSubject      => $Self->_Trim( $Request->{ActionNoteSubject} ),
        NoteBody         => $Self->_Trim( $Request->{ActionNoteBody} ),
        NoteCustomerVisible => $Request->{ActionNoteCustomerVisible} ? 1 : 0,
        EmailEnabled     => $Request->{ActionEmailEnabled} ? 1 : 0,
        EmailSubject     => $Self->_Trim( $Request->{ActionEmailSubject} ),
        EmailBody        => $Self->_Trim( $Request->{ActionEmailBody} ),
        AgentNotifyMode  => $Request->{ActionAgentNotifyMode} || 'none',
        AgentNotifyUserID => $Self->_Unsigned( $Request->{ActionAgentNotifyUserID} ),
        AgentNotifySubject => $Self->_Trim( $Request->{ActionAgentNotifySubject} ),
        AgentNotifyBody    => $Self->_Trim( $Request->{ActionAgentNotifyBody} ),
        ChecklistAddTemplateIDs    => $Self->_IDList( $Request->{ActionChecklistAddTemplateID} ),
        ChecklistRemoveTemplateIDs => $Self->_IDList( $Request->{ActionChecklistRemoveTemplateID} ),
        ChecklistSetTemplateID      => $Self->_Unsigned( $Request->{ActionChecklistSetTemplateID} ),
        ChecklistSetTemplateItemID  => $Self->_Unsigned( $Request->{ActionChecklistSetTemplateItemID} ),
        ChecklistSetDone            => $Request->{ActionChecklistSetDone} ? 1 : 0,
        ChecklistSetEnabled         => $Request->{ActionChecklistSetEnabled} ? 1 : 0,
        DeleteTickets    => $Request->{ActionDeleteTickets} ? 1 : 0,
        DeleteConfirmText => $Self->_Trim( $Request->{ActionDeleteConfirmText} ),
    };
}

sub ScheduleFromRequest {
    my ( $Self, %Param ) = @_;
    my $Request = $Param{Request} || {};
    return {
        type             => $Request->{ScheduleType} || 'every_minutes',
        interval_minutes => $Self->_Unsigned( $Request->{ScheduleIntervalMinutes} ) || 15,
        minute           => defined $Request->{ScheduleMinute} ? 0 + $Request->{ScheduleMinute} : 0,
        time             => $Self->_Trim( $Request->{ScheduleTime} ) || '02:00',
        weekday          => $Self->_Unsigned( $Request->{ScheduleWeekday} ) || 1,
        monthday         => $Self->_Unsigned( $Request->{ScheduleMonthday} ) || 1,
    };
}

sub Options {
    my ( $Self, %Param ) = @_;
    my $SearchObject = QisutuTicketSearch->new(
        Config => $Self->{Config},
        DB     => $Self->{DB},
    );
    my $Options = $SearchObject->Options(
        Language => $Param{Language} || 'en',
        User     => {},
    );
    if ( $SearchObject->Error() ) {
        $Self->{LastError} = $SearchObject->Error();
    }

    my $ChecklistObject = QisutuChecklist->new( Config => $Self->{Config}, DB => $Self->{DB} );
    my $Templates = $ChecklistObject->TemplateList( IncludeInactive => 0 ) || [];
    my @Items;
    for my $Template ( @{$Templates} ) {
        my $Full = $ChecklistObject->TemplateGet( TemplateID => $Template->{id} );
        for my $Item ( @{ $Full->{items} || [] } ) {
            push @Items, {
                id          => $Item->{id},
                template_id => $Template->{id},
                name        => $Item->{name},
                label       => ( $Template->{name} || '' ) . ' — ' . ( $Item->{name} || '' ),
            };
        }
        $Template->{label} = $Template->{name};
    }
    $Options->{ChecklistTemplates} = $Templates;
    $Options->{ChecklistItems} = \@Items;

    return $Options;
}

sub TicketPreview {
    my ( $Self, %Param ) = @_;
    $Self->{LastError} = '';
    my $Conditions = $Param{Conditions} || {};
    my $Limit = $Param{Limit} || 100;
    $Limit = 100 if $Limit > 100;

    my $Data = $Self->_TicketSelectionSQL( Conditions => $Conditions );
    return { Count => 0, Tickets => [] } if !$Data;

    my $Count = $Self->{DB}->SelectRow(
        'SELECT COUNT(*) AS ticket_count FROM ticket t WHERE ' . $Data->{Where},
        @{ $Data->{Bind} },
    );
    if ( !$Count ) {
        $Self->{LastError} = $Self->{DB}->Error() || 'Automation ticket count failed';
        return { Count => 0, Tickets => [] };
    }

    my $Rows = $Self->{DB}->SelectAll(
        'SELECT t.id, t.ticket_number, t.title, q.full_name AS queue_name,
                s.name AS state_name, p.name AS priority_name, t.changed_at
         FROM ticket t
         INNER JOIN ticket_queue q ON q.id = t.queue_id
         INNER JOIN ticket_state s ON s.id = t.state_id
         INNER JOIN ticket_priority p ON p.id = t.priority_id
         WHERE ' . $Data->{Where} . '
         ORDER BY t.changed_at DESC, t.id DESC
         LIMIT ' . int($Limit),
        @{ $Data->{Bind} },
    ) || [];

    return {
        Count   => 0 + ( $Count->{ticket_count} || 0 ),
        Tickets => $Rows,
    };
}

sub TicketIDs {
    my ( $Self, %Param ) = @_;
    $Self->{LastError} = '';
    my $Data = $Self->_TicketSelectionSQL( Conditions => $Param{Conditions} || {} );
    return [] if !$Data;
    my $Limit = $Param{Limit} || 5000;
    $Limit = 5000 if $Limit > 5000;

    my $Rows = $Self->{DB}->SelectAll(
        'SELECT t.id FROM ticket t WHERE ' . $Data->{Where} . '
         ORDER BY t.id ASC LIMIT ' . int($Limit),
        @{ $Data->{Bind} },
    );
    if ( !$Rows ) {
        $Self->{LastError} = $Self->{DB}->Error() || 'Automation tickets could not be selected';
        return [];
    }
    return [ map { 0 + $_->{id} } @{$Rows} ];
}

sub TicketMatches {
    my ( $Self, %Param ) = @_;
    my $TicketID = $Param{TicketID} || 0;
    return 0 if $TicketID !~ m{\A\d+\z} || !$TicketID;
    my $Data = $Self->_TicketSelectionSQL( Conditions => $Param{Conditions} || {} );
    return 0 if !$Data;
    my $Row = $Self->{DB}->SelectRow(
        'SELECT t.id FROM ticket t WHERE t.id = ? AND ' . $Data->{Where} . ' LIMIT 1',
        $TicketID,
        @{ $Data->{Bind} },
    );
    return $Row ? 1 : 0;
}

sub EnqueueDueTicketEvents {
    my ($Self) = @_;
    $Self->{LastError} = '';
    my $Result = $Self->{DB}->Do(
        'INSERT IGNORE INTO automation_event (
            event_key, event_name, ticket_id, depth, created_at
         )
         SELECT
            CONCAT(?, t.id, ?, DATE_FORMAT(t.pending_until, ?)),
            ?, t.id, 0, NOW()
         FROM ticket t
         INNER JOIN ticket_state s ON s.id = t.state_id
         WHERE s.state_type = ?
           AND t.pending_until IS NOT NULL
           AND t.pending_until <= NOW()',
        'pending_reached:', ':', '%Y%m%d%H%i%s',
        'pending_reached', 'pending',
    );
    if ( !defined $Result ) {
        $Self->{LastError} = $Self->{DB}->Error() || 'Due ticket events could not be created';
        return 0;
    }
    return 0 + $Result;
}

sub ProcessEvents {
    my ( $Self, %Param ) = @_;
    $Self->{LastError} = '';
    my $Limit = $Param{Limit} || 100;
    my $Events = $Self->{DB}->SelectAll(
        'SELECT * FROM automation_event
         WHERE processed_at IS NULL
         ORDER BY id ASC
         LIMIT ' . int($Limit)
    );
    if ( !defined $Events ) {
        $Self->{LastError} = $Self->{DB}->Error() || 'Automation events could not be loaded';
        return 0;
    }

    my $Created = 0;
    EVENT:
    for my $Event ( @{$Events} ) {
        my $EventName = $Event->{event_name} || '';
        my $Rules = $Self->{DB}->SelectAll(
            'SELECT id FROM automation_rule
             WHERE rule_type = ? AND active = 1
               AND (event_name = ? OR (? = ? AND event_name = ?))
             ORDER BY sort_order ASC, id ASC',
            'trigger',
            $EventName,
            $EventName,
            'ticket_changed',
            'any_ticket_change',
        );
        if ( !defined $Rules ) {
            $Self->{LastError} = $Self->{DB}->Error() || 'Trigger rules could not be loaded';
            last EVENT;
        }

        for my $Rule ( @{$Rules} ) {
            next if $Event->{source_rule_id} && $Rule->{id} == $Event->{source_rule_id};
            next if ( $Event->{depth} || 0 ) > 10;
            my $Key = join ':', 'event', $Event->{id}, $Rule->{id};
            my $Result = $Self->{DB}->Do(
                'INSERT IGNORE INTO automation_job (
                    job_key, rule_id, event_id, ticket_id, job_type, status,
                    scheduled_at, attempts, max_attempts, depth, suppress_notifications,
                    created_at, changed_at
                 ) VALUES (?, ?, ?, ?, ?, ?, NOW(), 0, 3, ?, ?, NOW(), NOW())',
                $Key,
                $Rule->{id},
                $Event->{id},
                $Event->{ticket_id},
                'trigger_action',
                'pending',
                $Event->{depth} || 0,
                $Event->{suppress_notifications} ? 1 : 0,
            );
            if ( !defined $Result ) {
                $Self->{LastError} = $Self->{DB}->Error() || 'Trigger job could not be created';
                next EVENT;
            }
            $Created++ if 0 + $Result > 0;
        }

        my $Marked = $Self->{DB}->Do(
            'UPDATE automation_event SET processed_at = NOW() WHERE id = ? AND processed_at IS NULL',
            $Event->{id},
        );
        if ( !defined $Marked ) {
            $Self->{LastError} = $Self->{DB}->Error() || 'Automation event could not be marked as processed';
            last EVENT;
        }
    }

    return $Created;
}

sub EnqueueDueSchedules {
    my ( $Self, %Param ) = @_;
    $Self->{LastError} = '';
    my $Rules = $Self->{DB}->SelectAll(
        'SELECT * FROM automation_rule
         WHERE rule_type = ? AND active = 1
           AND next_run_at IS NOT NULL AND next_run_at <= NOW()
         ORDER BY next_run_at ASC, id ASC
         LIMIT 50',
        'schedule',
    );
    if ( !defined $Rules ) {
        $Self->{LastError} = $Self->{DB}->Error() || 'Due scheduled rules could not be loaded';
        return 0;
    }

    my $Created = 0;
    for my $Rule ( @{$Rules} ) {
        my $RunKey = $Rule->{next_run_at} || strftime( '%Y-%m-%d %H:%M:%S', localtime );
        my $Key = join ':', 'schedule', $Rule->{id}, $RunKey;
        my $Result = $Self->{DB}->Do(
            'INSERT IGNORE INTO automation_job (
                job_key, rule_id, job_type, status, scheduled_at,
                attempts, max_attempts, created_at, changed_at
             ) VALUES (?, ?, ?, ?, NOW(), 0, 3, NOW(), NOW())',
            $Key,
            $Rule->{id},
            'schedule_scan',
            'pending',
        );
        if ( !defined $Result ) {
            $Self->{LastError} = $Self->{DB}->Error() || 'Scheduled automation job could not be created';
            last;
        }
        $Created++ if 0 + $Result > 0;

        my $Schedule = $Self->_JSONDecode( $Rule->{schedule_json}, {} );
        my $Next = $Self->NextRunCalculate(
            Schedule => $Schedule,
            From     => time + 1,
        );
        my $Updated = $Self->{DB}->Do(
            'UPDATE automation_rule SET next_run_at = ?, changed_at = NOW() WHERE id = ?',
            $Next,
            $Rule->{id},
        );
        if ( !defined $Updated ) {
            $Self->{LastError} = $Self->{DB}->Error() || 'Next scheduled run could not be saved';
            last;
        }
    }
    return $Created;
}

sub JobRecoverStale {
    my ($Self) = @_;
    $Self->{LastError} = '';
    my $Result = $Self->{DB}->Do(
        'UPDATE automation_job
         SET status = ?, locked_by = NULL, locked_until = NULL,
             next_attempt_at = NOW(), error_message = ?, changed_at = NOW()
         WHERE status = ? AND locked_until IS NOT NULL AND locked_until < NOW()',
        'pending', 'Previous worker lock expired; job returned to queue.', 'running',
    );
    if ( !defined $Result ) {
        $Self->{LastError} = $Self->{DB}->Error() || 'Stale automation jobs could not be recovered';
        return;
    }
    return 0 + $Result;
}

sub JobClaim {
    my ( $Self, %Param ) = @_;
    $Self->{LastError} = '';
    my $Worker = $Param{Worker} || 'qisutu-daemon';

    my $DBH = $Self->{DB}->Handle() || return;
    my $Job;

    my $OK = eval {
        $DBH->begin_work()
            or die( $DBH->errstr || 'Database transaction could not be started' );

        my $STH = $DBH->prepare(
            'SELECT * FROM automation_job
             WHERE status = ? AND scheduled_at <= NOW()
               AND (next_attempt_at IS NULL OR next_attempt_at <= NOW())
               AND (locked_until IS NULL OR locked_until < NOW())
             ORDER BY id ASC LIMIT 1 FOR UPDATE'
        ) or die( $DBH->errstr || 'Automation job query could not be prepared' );

        $STH->execute('pending')
            or die( $STH->errstr || 'Automation job query could not be executed' );

        $Job = $STH->fetchrow_hashref();

        if ($Job) {
            my $Update = $DBH->prepare(
                'UPDATE automation_job
                 SET status = ?, started_at = COALESCE(started_at, NOW()),
                     locked_by = ?, locked_until = DATE_ADD(NOW(), INTERVAL 10 MINUTE),
                     attempts = attempts + 1, changed_at = NOW()
                 WHERE id = ?'
            ) or die( $DBH->errstr || 'Automation job update could not be prepared' );

            $Update->execute( 'running', $Worker, $Job->{id} )
                or die( $Update->errstr || 'Automation job could not be claimed' );
        }

        $DBH->commit()
            or die( $DBH->errstr || 'Automation job transaction could not be committed' );

        1;
    };

    if ( !$OK ) {
        my $Error = $@ || $DBH->errstr || 'Automation job could not be claimed';
        if ( !$DBH->{AutoCommit} ) {
            eval { $DBH->rollback() };
        }
        $Error =~ s{\s+\z}{};
        $Self->{LastError} = $Error;
        return;
    }

    if ($Job) {
        $Job->{status} = 'running';
        $Job->{attempts} = ( $Job->{attempts} || 0 ) + 1;
    }

    return $Job;
}

sub JobProcess {
    my ( $Self, %Param ) = @_;
    $Self->{LastError} = '';
    my $Job = $Param{Job} || {};
    my $JobID = $Job->{id} || 0;
    return if !$JobID;

    my $Rule = $Self->RuleGet( RuleID => $Job->{rule_id} );
    if (!$Rule) {
        return $Self->_JobFail( Job => $Job, Error => $Self->Error() || 'Automation rule was not found' );
    }

    my $DBH = $Self->{DB}->Handle();
    if ($DBH) {
        eval {
            $DBH->do( 'SET @qisutu_automation_job_id = ' . int($JobID) );
            $DBH->do( 'SET @qisutu_automation_rule_id = ' . int( $Rule->{id} || 0 ) );
            $DBH->do( 'SET @qisutu_automation_depth = ' . int( $Job->{depth} || 0 ) );
            $DBH->do( 'SET @qisutu_suppress_notifications = ' . ( $Job->{suppress_notifications} ? 1 : 0 ) );
        };
    }

    if ( ( $Job->{job_type} || '' ) eq 'schedule_scan' ) {
        my $TicketIDs = $Self->TicketIDs( Conditions => $Rule->{conditions}, Limit => 5000 );
        if ( $Self->Error() ) {
            return $Self->_JobFail( Job => $Job, Error => $Self->Error() );
        }
        my $Count = 0;
        for my $TicketID ( @{$TicketIDs} ) {
            my $Key = join ':', 'schedule-ticket', $JobID, $TicketID;
            my $Result = $Self->{DB}->Do(
                'INSERT IGNORE INTO automation_job (
                    job_key, parent_job_id, rule_id, ticket_id, job_type, status,
                    scheduled_at, attempts, max_attempts, depth, created_at, changed_at
                 ) VALUES (?, ?, ?, ?, ?, ?, NOW(), 0, 3, ?, NOW(), NOW())',
                $Key,
                $JobID,
                $Rule->{id},
                $TicketID,
                'ticket_action',
                'pending',
                ( $Job->{depth} || 0 ) + 1,
            );
            $Count++ if $Result;
        }
        return $Self->_JobSuccess( Job => $Job, Result => { selected => scalar @{$TicketIDs}, queued => $Count } );
    }

    my $TicketID = $Job->{ticket_id} || 0;
    if (!$TicketID) {
        return $Self->_JobFail( Job => $Job, Error => 'Automation job has no TicketID' );
    }

    if ( ( $Job->{depth} || 0 ) > 10 ) {
        return $Self->_JobFail( Job => $Job, Error => 'Maximum automation depth exceeded' );
    }

    if ( !$Self->TicketMatches( TicketID => $TicketID, Conditions => $Rule->{conditions} ) ) {
        return $Self->_JobSuccess( Job => $Job, Result => { skipped => 1, reason => 'conditions_not_matched' } );
    }

    my $Applied = $Self->ActionsApply(
        TicketID => $TicketID,
        Actions  => $Rule->{actions},
        Rule     => $Rule,
        Job      => $Job,
    );
    if (!$Applied) {
        return $Self->_JobFail( Job => $Job, Error => $Self->Error() || 'Automation actions failed' );
    }

    return $Self->_JobSuccess( Job => $Job, Result => $Applied );
}

sub ActionsApply {
    my ( $Self, %Param ) = @_;
    my $TicketID = $Param{TicketID} || 0;
    my $Actions  = $Param{Actions} || {};
    my $Rule     = $Param{Rule} || {};
    my $Job      = $Param{Job} || {};
    my $SystemUserID = $Self->_SystemUserID();
    my $SuppressNotifications = $Job->{suppress_notifications} ? 1 : 0;

    if ( $Actions->{DeleteTickets} ) {
        return $Self->TicketDeleteComplete(
            TicketID => $TicketID,
            Rule     => $Rule,
            Job      => $Job,
        );
    }

    my $TicketObject = QisutuTicket->new(
        Config => $Self->{Config},
        DB     => $Self->{DB},
    );
    my @Done;

    if ( $Actions->{QueueID} ) {
        return $Self->_ActionError( $TicketObject ) if !$TicketObject->TicketQueueUpdate(
            TicketID => $TicketID, QueueID => $Actions->{QueueID}, ChangedByUserID => $SystemUserID,
        );
        push @Done, 'queue';
    }

    if ( $Actions->{PriorityID} ) {
        return $Self->_ActionError( $TicketObject ) if !$TicketObject->TicketPriorityUpdate(
            TicketID => $TicketID, PriorityID => $Actions->{PriorityID}, ChangedByUserID => $SystemUserID,
        );
        push @Done, 'priority';
    }

    if ( ( $Actions->{OwnerMode} || '' ) eq 'set' && $Actions->{OwnerID} ) {
        return $Self->_ActionError( $TicketObject ) if !$TicketObject->TicketOwnerUpdate(
            TicketID => $TicketID, OwnerUserID => $Actions->{OwnerID}, ChangedByUserID => $SystemUserID,
            SuppressNotification => $SuppressNotifications,
        );
        push @Done, 'owner';
    }
    elsif ( ( $Actions->{OwnerMode} || '' ) eq 'clear' ) {
        return if !$Self->_DirectTicketUpdate( TicketID => $TicketID, SQL => 'owner_user_id = NULL', UserID => $SystemUserID );
        push @Done, 'owner_clear';
    }

    if ( ( $Actions->{ResponsibleMode} || '' ) eq 'set' && $Actions->{ResponsibleID} ) {
        return $Self->_ActionError( $TicketObject ) if !$TicketObject->TicketResponsibleUpdate(
            TicketID => $TicketID, ResponsibleUserID => $Actions->{ResponsibleID}, ChangedByUserID => $SystemUserID,
        );
        push @Done, 'responsible';
    }
    elsif ( ( $Actions->{ResponsibleMode} || '' ) eq 'clear' ) {
        return if !$Self->_DirectTicketUpdate( TicketID => $TicketID, SQL => 'responsible_user_id = NULL', UserID => $SystemUserID );
        push @Done, 'responsible_clear';
    }

    if ( ( $Actions->{ServiceMode} || '' ) eq 'set' && $Actions->{ServiceID} ) {
        return $Self->_ActionError( $TicketObject ) if !$TicketObject->TicketServiceUpdate(
            TicketID => $TicketID, ServiceID => $Actions->{ServiceID}, ChangedByUserID => $SystemUserID,
        );
        push @Done, 'service';
    }
    elsif ( ( $Actions->{ServiceMode} || '' ) eq 'clear' ) {
        return $Self->_ActionError( $TicketObject ) if !$TicketObject->TicketServiceUpdate(
            TicketID => $TicketID, ServiceID => 0, ChangedByUserID => $SystemUserID,
        );
        push @Done, 'service_clear';
    }

    my $ChecklistObject = QisutuChecklist->new( Config => $Self->{Config}, DB => $Self->{DB} );
    for my $TemplateID ( @{ $Actions->{ChecklistAddTemplateIDs} || [] } ) {
        return $Self->_ActionError( $ChecklistObject ) if !$ChecklistObject->TicketChecklistAdd(
            TicketID        => $TicketID,
            TemplateID      => $TemplateID,
            ChangedByUserID => $SystemUserID,
            Source          => 'automation',
        );
        push @Done, 'checklist_add_' . $TemplateID;
    }

    for my $TemplateID ( @{ $Actions->{ChecklistRemoveTemplateIDs} || [] } ) {
        my $Rows = $Self->{DB}->SelectAll(
            'SELECT id FROM ticket_checklist WHERE ticket_id = ? AND template_id = ? AND removed_at IS NULL',
            $TicketID,
            $TemplateID,
        ) || [];
        for my $Row ( @{$Rows} ) {
            return $Self->_ActionError( $ChecklistObject ) if !$ChecklistObject->TicketChecklistRemove(
                TicketID          => $TicketID,
                TicketChecklistID => $Row->{id},
                ChangedByUserID   => $SystemUserID,
            );
        }
        push @Done, 'checklist_remove_' . $TemplateID;
    }

    if ( $Actions->{ChecklistSetEnabled} && $Actions->{ChecklistSetTemplateID} && $Actions->{ChecklistSetTemplateItemID} ) {
        return $Self->_ActionError( $ChecklistObject ) if !$ChecklistObject->TicketTemplateItemSet(
            TicketID       => $TicketID,
            TemplateID     => $Actions->{ChecklistSetTemplateID},
            TemplateItemID => $Actions->{ChecklistSetTemplateItemID},
            Done           => $Actions->{ChecklistSetDone},
            ChangedByUserID => $SystemUserID,
        );
        push @Done, 'checklist_item';
    }

    if ( $Actions->{StateID} ) {
        my $PendingUntil = '';
        if ( $Actions->{PendingMinutes} ) {
            $PendingUntil = strftime( '%Y-%m-%d %H:%M:%S', localtime( time + ( $Actions->{PendingMinutes} * 60 ) ) );
        }
        return $Self->_ActionError( $TicketObject ) if !$TicketObject->TicketStatusUpdate(
            TicketID => $TicketID, StatusID => $Actions->{StateID}, PendingUntil => $PendingUntil,
            ChangedByUserID => $SystemUserID, SuppressNotification => $SuppressNotifications,
        );
        push @Done, 'state';
    }

    for my $Dynamic ( @{ $Actions->{Dynamic} || [] } ) {
        my $FieldID = $Dynamic->{id} || 0;
        next if !$FieldID;
        my $Value = $Dynamic->{clear} ? '' : ( defined $Dynamic->{value} ? $Dynamic->{value} : '' );
        my $Result = $Self->{DB}->Do(
            'INSERT INTO ticket_dynamic_field_value (
                ticket_id, field_id, value_text, created_by_user_id, changed_by_user_id, created_at, changed_at
             ) VALUES (?, ?, ?, ?, ?, NOW(), NOW())
             ON DUPLICATE KEY UPDATE value_text = VALUES(value_text), changed_by_user_id = VALUES(changed_by_user_id), changed_at = NOW()',
            $TicketID, $FieldID, $Value, $SystemUserID, $SystemUserID,
        );
        if (!$Result) {
            $Self->{LastError} = $Self->{DB}->Error() || 'Dynamic field action failed';
            return;
        }
        push @Done, 'dynamic_field_' . $FieldID;
    }

    if ( $Actions->{NoteEnabled} && $Actions->{NoteBody} ) {
        my $ArticleID = $TicketObject->ArticleCreate(
            TicketID => $TicketID,
            Subject => $Actions->{NoteSubject} || ( 'Automation: ' . ( $Rule->{name} || '' ) ),
            Body => $Actions->{NoteBody},
            Channel => 'note', SenderType => 'agent', ContentType => 'text/html',
            Visibility => $Actions->{NoteCustomerVisible} ? 'both' : 'agent',
            CreatedByUserID => $SystemUserID, ChangedByUserID => $SystemUserID,
            SkipTicketAccessCheck => 1, SkipNotification => 1,
        );
        return $Self->_ActionError( $TicketObject ) if !$ArticleID;
        push @Done, 'note';
    }

    if ( $Actions->{EmailEnabled} && $Actions->{EmailBody} && !$SuppressNotifications ) {
        my $EmailResult = $Self->_CustomerEmailSend(
            TicketID => $TicketID,
            Subject  => $Actions->{EmailSubject},
            Body     => $Actions->{EmailBody},
            UserID   => $SystemUserID,
            RuleName => $Rule->{name} || '',
        );
        return if !$EmailResult;
        push @Done, 'email';
    }
    elsif ( $Actions->{EmailEnabled} && $Actions->{EmailBody} ) {
        push @Done, 'email_suppressed';
    }

    if ( ( $Actions->{AgentNotifyMode} || 'none' ) ne 'none' && !$SuppressNotifications ) {
        my $NotifyResult = $Self->_AgentNotificationSend(
            TicketID => $TicketID,
            Mode     => $Actions->{AgentNotifyMode},
            UserID   => $Actions->{AgentNotifyUserID},
            Subject  => $Actions->{AgentNotifySubject},
            Body     => $Actions->{AgentNotifyBody},
            RuleName => $Rule->{name} || '',
        );
        return if !$NotifyResult;
        push @Done, 'agent_notification';
    }
    elsif ( ( $Actions->{AgentNotifyMode} || 'none' ) ne 'none' ) {
        push @Done, 'agent_notification_suppressed';
    }

    return { applied => \@Done };
}

sub TicketDeleteComplete {
    my ( $Self, %Param ) = @_;
    $Self->{LastError} = '';
    my $TicketID = $Param{TicketID} || 0;
    my $Rule = $Param{Rule} || {};
    my $Job  = $Param{Job} || {};
    return if $TicketID !~ m{\A\d+\z} || !$TicketID;

    my $Ticket = $Self->{DB}->SelectRow(
        'SELECT id, ticket_number, title FROM ticket WHERE id = ? LIMIT 1',
        $TicketID,
    );
    return { deleted => 0, already_missing => 1 } if !$Ticket;

    my $ArticleRows = $Self->{DB}->SelectAll(
        'SELECT id FROM ticket_article WHERE ticket_id = ? ORDER BY id ASC',
        $TicketID,
    ) || [];
    my @ArticleIDs = map { 0 + $_->{id} } grep { $_->{id} } @{$ArticleRows};

    my $AttachmentRows = $Self->_TableExists('ticket_article_attachment')
        ? ( $Self->{DB}->SelectAll(
            'SELECT id FROM ticket_article_attachment WHERE ticket_id = ? ORDER BY id ASC',
            $TicketID,
        ) || [] )
        : [];
    my @AttachmentIDs = map { 0 + $_->{id} } grep { $_->{id} } @{$AttachmentRows};

    my $Paths = $Self->_AttachmentPaths( TicketID => $TicketID );
    my $Staged = $Self->_FilesStageForDeletion(
        TicketID => $TicketID,
        JobID    => $Job->{id} || 0,
        Paths    => $Paths,
    );
    return if !defined $Staged;

    my $DBH = $Self->{DB}->Handle() || do {
        $Self->_FilesRestore( Files => $Staged );
        $Self->{LastError} = 'Database connection failed';
        return;
    };

    my $DeletedRows = 0;
    my $DeleteOK = eval {
        $DBH->begin_work()
            or die( $DBH->errstr || 'Database transaction could not be started' );

        my %Done;

        # Remove rows from extension tables that reference attachments or
        # ticket articles but do not carry their own ticket_id. Child records
        # are deleted before their parent rows so foreign keys cannot leave
        # partially deleted tickets behind.
        for my $Reference (
            [ 'attachment_id',     \@AttachmentIDs, 'ticket_article_attachment' ],
            [ 'article_id',        \@ArticleIDs,    'ticket_article' ],
            [ 'ticket_article_id', \@ArticleIDs,    'ticket_article' ],
        ) {
            my ( $Column, $IDs, $ParentTable ) = @{$Reference};
            next if !@{$IDs};
            my $ReferenceTables = $Self->{DB}->SelectAll(
                'SELECT DISTINCT TABLE_NAME AS table_name
                 FROM information_schema.COLUMNS
                 WHERE TABLE_SCHEMA = DATABASE() AND COLUMN_NAME = ?',
                $Column,
            ) || [];
            my $Placeholder = join ', ', map {'?'} @{$IDs};
            for my $Row ( @{$ReferenceTables} ) {
                my $Table = $Row->{table_name} || '';
                next if !$Table || $Table eq $ParentTable || $Table !~ m{\A[A-Za-z0-9_]+\z};
                my $STH = $DBH->prepare(
                    'DELETE FROM `' . $Table . '` WHERE `' . $Column . '` IN (' . $Placeholder . ')'
                );
                $STH->execute( @{$IDs} );
                $DeletedRows += $STH->rows() > 0 ? $STH->rows() : 0;
                $Done{$Table} = 1;
            }
        }

        my @Known = qw(
            ticket_article_attachment
            ticket_dynamic_field_value
            agent_notification_event_log
            ticket_article
        );
        for my $Table (@Known) {
            next if !$Self->_TableExists($Table);
            my $STH = $DBH->prepare('DELETE FROM `' . $Table . '` WHERE ticket_id = ?');
            $STH->execute($TicketID);
            $DeletedRows += $STH->rows() > 0 ? $STH->rows() : 0;
            $Done{$Table} = 1;
        }

        my $Tables = $Self->{DB}->SelectAll(
            'SELECT DISTINCT TABLE_NAME AS table_name
             FROM information_schema.COLUMNS
             WHERE TABLE_SCHEMA = DATABASE() AND COLUMN_NAME = ?',
            'ticket_id',
        ) || [];
        for my $Row ( @{$Tables} ) {
            my $Table = $Row->{table_name} || '';
            next if !$Table || $Done{$Table};
            next if $Table =~ m{\A(?:ticket|automation_job|automation_event|automation_deleted_ticket)\z};
            next if $Table !~ m{\A[A-Za-z0-9_]+\z};
            my $STH = $DBH->prepare('DELETE FROM `' . $Table . '` WHERE ticket_id = ?');
            $STH->execute($TicketID);
            $DeletedRows += $STH->rows() > 0 ? $STH->rows() : 0;
        }

        my $Audit = $DBH->prepare(
            'INSERT INTO automation_deleted_ticket (
                ticket_id_original, ticket_number, title, rule_id, job_id,
                deleted_related_rows, deleted_file_count, deleted_at
             ) VALUES (?, ?, ?, ?, ?, ?, ?, NOW())'
        );
        $Audit->execute(
            $TicketID,
            $Ticket->{ticket_number} || '',
            $Ticket->{title} || '',
            $Rule->{id} || undef,
            $Job->{id} || undef,
            $DeletedRows,
            scalar @{$Staged},
        );

        my $EventUpdate = $DBH->prepare('UPDATE automation_event SET ticket_id = NULL WHERE ticket_id = ?');
        $EventUpdate->execute($TicketID);
        my $JobUpdate = $DBH->prepare('UPDATE automation_job SET ticket_id = NULL WHERE ticket_id = ?');
        $JobUpdate->execute($TicketID);

        my $Delete = $DBH->prepare('DELETE FROM ticket WHERE id = ?');
        $Delete->execute($TicketID);
        die 'Ticket delete did not affect a row' if $Delete->rows() < 1;

        $DBH->commit()
            or die( $DBH->errstr || 'Ticket deletion transaction could not be committed' );

        1;
    };

    if ( !$DeleteOK ) {
        my $Error = $@ || $DBH->errstr || 'Ticket deletion failed';
        if ( !$DBH->{AutoCommit} ) {
            eval { $DBH->rollback() };
        }
        $Self->_FilesRestore( Files => $Staged );
        $Error =~ s{\s+\z}{};
        $Self->{LastError} = $Error;
        return;
    }

    $Self->_FilesFinalize( Files => $Staged );
    return {
        deleted              => 1,
        ticket_number        => $Ticket->{ticket_number},
        deleted_related_rows => $DeletedRows,
        deleted_files        => scalar @{$Staged},
    };
}

sub JobList {
    my ( $Self, %Param ) = @_;
    $Self->{LastError} = '';
    my $Status = $Param{Status} || '';
    my $Limit = $Param{Limit} || 200;
    $Limit = 500 if $Limit > 500;
    my @Bind;
    my $Where = '';
    if ( $Status =~ m{\A(?:pending|running|successful|failed|cancelled)\z} ) {
        $Where = 'WHERE j.status = ?';
        push @Bind, $Status;
    }
    my $Rows = $Self->{DB}->SelectAll(
        'SELECT j.*, r.name AS rule_name, r.rule_type
         FROM automation_job j
         LEFT JOIN automation_rule r ON r.id = j.rule_id
         ' . $Where . '
         ORDER BY j.id DESC LIMIT ' . int($Limit),
        @Bind,
    );
    if (!$Rows) {
        $Self->{LastError} = $Self->{DB}->Error() || 'Automation jobs could not be loaded';
        return [];
    }
    return $Rows;
}

sub JobRetry {
    my ( $Self, %Param ) = @_;
    $Self->{LastError} = '';
    my $JobID = $Param{JobID} || 0;
    return if $JobID !~ m{\A\d+\z} || !$JobID;
    my $Result = $Self->{DB}->Do(
        'UPDATE automation_job
         SET status = ?, scheduled_at = NOW(), next_attempt_at = NULL,
             locked_by = NULL, locked_until = NULL, error_message = NULL,
             finished_at = NULL, changed_at = NOW()
         WHERE id = ? AND status IN (?, ?)',
        'pending', $JobID, 'failed', 'cancelled',
    );
    return $Result ? 1 : undef;
}

sub JobCancel {
    my ( $Self, %Param ) = @_;
    $Self->{LastError} = '';
    my $JobID = $Param{JobID} || 0;
    return if $JobID !~ m{\A\d+\z} || !$JobID;
    my $Result = $Self->{DB}->Do(
        'UPDATE automation_job
         SET status = ?, finished_at = NOW(), locked_by = NULL, locked_until = NULL, changed_at = NOW()
         WHERE id = ? AND status = ?',
        'cancelled', $JobID, 'pending',
    );
    return $Result ? 1 : undef;
}

sub NextRunCalculate {
    my ( $Self, %Param ) = @_;
    my $Schedule = $Param{Schedule} || {};
    my $From = $Param{From} || time;
    my $Type = $Schedule->{type} || 'every_minutes';

    if ( $Type eq 'every_minutes' ) {
        my $Minutes = $Self->_Unsigned( $Schedule->{interval_minutes} ) || 15;
        $Minutes = 1440 if $Minutes > 1440;
        return strftime( '%Y-%m-%d %H:%M:%S', localtime( $From + $Minutes * 60 ) );
    }

    my ( $Sec, $Min, $Hour, $MDay, $Mon, $Year, $WDay ) = localtime($From);
    my ( $TargetHour, $TargetMin ) = $Self->_TimeParts( $Schedule->{time} || '02:00' );

    if ( $Type eq 'hourly' ) {
        my $Minute = defined $Schedule->{minute} ? int( $Schedule->{minute} ) : 0;
        $Minute = 0 if $Minute < 0 || $Minute > 59;
        my $Epoch = timelocal( 0, $Minute, $Hour, $MDay, $Mon, $Year );
        $Epoch += 3600 if $Epoch <= $From;
        return strftime( '%Y-%m-%d %H:%M:%S', localtime($Epoch) );
    }

    if ( $Type eq 'daily' ) {
        my $Epoch = timelocal( 0, $TargetMin, $TargetHour, $MDay, $Mon, $Year );
        $Epoch += 86400 if $Epoch <= $From;
        return strftime( '%Y-%m-%d %H:%M:%S', localtime($Epoch) );
    }

    if ( $Type eq 'weekly' ) {
        my $Wanted = $Self->_Unsigned( $Schedule->{weekday} ) || 1;
        $Wanted = 1 if $Wanted > 7;
        my $Current = $WDay == 0 ? 7 : $WDay;
        my $AddDays = ( $Wanted - $Current + 7 ) % 7;
        my $Epoch = timelocal( 0, $TargetMin, $TargetHour, $MDay, $Mon, $Year ) + $AddDays * 86400;
        $Epoch += 7 * 86400 if $Epoch <= $From;
        return strftime( '%Y-%m-%d %H:%M:%S', localtime($Epoch) );
    }

    if ( $Type eq 'monthly' ) {
        my $WantedDay = $Self->_Unsigned( $Schedule->{monthday} ) || 1;
        $WantedDay = 28 if $WantedDay > 28;
        my $TryMon = $Mon;
        my $TryYear = $Year;
        my $Epoch = timelocal( 0, $TargetMin, $TargetHour, $WantedDay, $TryMon, $TryYear );
        if ( $Epoch <= $From ) {
            $TryMon++;
            if ( $TryMon > 11 ) { $TryMon = 0; $TryYear++; }
            $Epoch = timelocal( 0, $TargetMin, $TargetHour, $WantedDay, $TryMon, $TryYear );
        }
        return strftime( '%Y-%m-%d %H:%M:%S', localtime($Epoch) );
    }

    return strftime( '%Y-%m-%d %H:%M:%S', localtime( $From + 900 ) );
}

sub ConditionSummary {
    my ( $Self, %Param ) = @_;
    my $C = $Param{Conditions} || {};
    my $S = $C->{Search} || {};
    my @Part;
    push @Part, 'Freitext' if $S->{Text};
    push @Part, 'Ticketnummer' if $S->{TicketNumber};
    push @Part, 'Titel' if $S->{Title};
    for my $Item (
        [ QueueIDs => 'Queue' ], [ StateIDs => 'Status' ], [ PriorityIDs => 'Priorität' ],
        [ CustomerIDs => 'Kunde' ], [ CustomerUserIDs => 'Ansprechpartner' ],
        [ OwnerIDs => 'Besitzer' ], [ ResponsibleIDs => 'Verantwortlicher' ],
        [ ServiceIDs => 'Service' ], [ SLAIDs => 'SLA' ], [ Escalation => 'Eskalation' ],
    ) {
        push @Part, $Item->[1] if @{ $S->{ $Item->[0] } || [] };
    }
    push @Part, 'Zeiträume' if grep { $S->{$_} } qw(
        CreatedFrom CreatedTo ChangedFrom ChangedTo PendingFrom PendingTo
        SolutionFrom SolutionTo FirstResponseDueFrom FirstResponseDueTo
        UpdateDueFrom UpdateDueTo SolutionDueFrom SolutionDueTo
    );
    push @Part, 'Dynamische Felder' if @{ $S->{Dynamic} || [] };
    push @Part, 'Alter' if $C->{ChangedOlderMinutes} || $C->{LastCustomerOlderMinutes} || $C->{LastAgentOlderMinutes};
    push @Part, 'ohne Besitzer' if $C->{NoOwner};
    push @Part, 'ohne Verantwortlichen' if $C->{NoResponsible};
    my $CL = $C->{Checklist} || {};
    push @Part, 'Checklisten' if @{ $CL->{TemplateIDs} || [] } || $CL->{HasOpen} || $CL->{HasCompleted} || $CL->{OpenRequired} || $CL->{AllRequiredDone};
    return @Part ? join( ', ', @Part ) : 'Alle Tickets';
}

sub ActionSummary {
    my ( $Self, %Param ) = @_;
    my $A = $Param{Actions} || {};
    return 'Tickets vollständig löschen' if $A->{DeleteTickets};
    my @Part;
    push @Part, 'Queue' if $A->{QueueID};
    push @Part, 'Status' if $A->{StateID};
    push @Part, 'Priorität' if $A->{PriorityID};
    push @Part, 'Besitzer' if ( $A->{OwnerMode} || 'keep' ) ne 'keep';
    push @Part, 'Verantwortlicher' if ( $A->{ResponsibleMode} || 'keep' ) ne 'keep';
    push @Part, 'Service/SLA' if ( $A->{ServiceMode} || 'keep' ) ne 'keep';
    push @Part, 'Dynamische Felder' if @{ $A->{Dynamic} || [] };
    push @Part, 'Checkliste hinzufügen' if @{ $A->{ChecklistAddTemplateIDs} || [] };
    push @Part, 'Checkliste entfernen' if @{ $A->{ChecklistRemoveTemplateIDs} || [] };
    push @Part, 'Checklistenpunkt' if $A->{ChecklistSetEnabled};
    push @Part, 'Notiz' if $A->{NoteEnabled};
    push @Part, 'Kunden-E-Mail' if $A->{EmailEnabled};
    push @Part, 'Agentenbenachrichtigung' if ( $A->{AgentNotifyMode} || 'none' ) ne 'none';
    return @Part ? join( ', ', @Part ) : '-';
}

sub ScheduleSummary {
    my ( $Self, %Param ) = @_;
    my $S = $Param{Schedule} || {};
    my $Type = $S->{type} || 'every_minutes';
    return 'Alle ' . ( $S->{interval_minutes} || 15 ) . ' Minuten' if $Type eq 'every_minutes';
    return 'Stündlich, Minute ' . ( defined $S->{minute} ? $S->{minute} : 0 ) if $Type eq 'hourly';
    return 'Täglich ' . ( $S->{time} || '02:00' ) if $Type eq 'daily';
    return 'Wöchentlich, Tag ' . ( $S->{weekday} || 1 ) . ', ' . ( $S->{time} || '02:00' ) if $Type eq 'weekly';
    return 'Monatlich, Tag ' . ( $S->{monthday} || 1 ) . ', ' . ( $S->{time} || '02:00' ) if $Type eq 'monthly';
    return '-';
}

sub _RuleDataValidate {
    my ( $Self, %Param ) = @_;
    my $Name = $Self->_Trim( $Param{Name} );
    my $Type = $Param{RuleType} || '';
    my $Conditions = $Param{Conditions} || {};
    my $Actions = $Param{Actions} || {};
    my $Schedule = $Param{Schedule} || {};
    my $Event = $Param{EventName} || '';

    if (!$Name) {
        $Self->{LastError} = 'Translate:AutomationNameRequired';
        return;
    }
    if ( $Type !~ m{\A(?:trigger|schedule)\z} ) {
        $Self->{LastError} = 'Translate:AutomationTypeInvalid';
        return;
    }
    my %AllowedEvent = map { $_ => 1 } qw(
        ticket_created customer_article_created agent_article_created note_created
        status_changed queue_changed priority_changed owner_changed responsible_changed
        service_changed sla_changed dynamic_field_changed ticket_closed ticket_reopened
        pending_reached sla_warning sla_breached ticket_changed any_ticket_change
    );
    if ( $Type eq 'trigger' && ( $Event !~ m{\A[a-z0-9_]+\z} || !$AllowedEvent{$Event} ) ) {
        $Self->{LastError} = 'Translate:AutomationEventRequired';
        return;
    }
    if ( $Type eq 'schedule' && ( $Schedule->{type} || '' ) !~ m{\A(?:every_minutes|hourly|daily|weekly|monthly)\z} ) {
        $Self->{LastError} = 'Translate:AutomationScheduleInvalid';
        return;
    }
    if ( ( $Actions->{OwnerMode} || 'keep' ) eq 'set' && !$Actions->{OwnerID} ) {
        $Self->{LastError} = 'Translate:AutomationOwnerRequired';
        return;
    }
    if ( ( $Actions->{ResponsibleMode} || 'keep' ) eq 'set' && !$Actions->{ResponsibleID} ) {
        $Self->{LastError} = 'Translate:AutomationResponsibleRequired';
        return;
    }
    if ( ( $Actions->{ServiceMode} || 'keep' ) eq 'set' && !$Actions->{ServiceID} ) {
        $Self->{LastError} = 'Translate:AutomationServiceRequired';
        return;
    }
    if ( $Actions->{StateID} ) {
        my $State = $Self->{DB}->SelectRow(
            'SELECT id, state_type FROM ticket_state WHERE id = ? AND active = 1 LIMIT 1',
            $Actions->{StateID},
        );
        if (!$State) {
            $Self->{LastError} = 'Translate:AutomationStateInvalid';
            return;
        }
        if ( ( $State->{state_type} || '' ) eq 'pending' && !$Actions->{PendingMinutes} ) {
            $Self->{LastError} = 'Translate:AutomationPendingMinutesRequired';
            return;
        }
    }
    if ( $Actions->{NoteEnabled} && !$Actions->{NoteBody} ) {
        $Self->{LastError} = 'Translate:AutomationNoteBodyRequired';
        return;
    }
    if ( $Actions->{EmailEnabled} && !$Actions->{EmailBody} ) {
        $Self->{LastError} = 'Translate:AutomationEmailBodyRequired';
        return;
    }
    if ( ( $Actions->{AgentNotifyMode} || 'none' ) !~ m{\A(?:none|queue|agent)\z} ) {
        $Self->{LastError} = 'Translate:AutomationAgentNotifyModeInvalid';
        return;
    }
    if ( ( $Actions->{AgentNotifyMode} || 'none' ) eq 'agent' && !$Actions->{AgentNotifyUserID} ) {
        $Self->{LastError} = 'Translate:AutomationAgentNotifyUserRequired';
        return;
    }
    if ( ( $Actions->{AgentNotifyMode} || 'none' ) ne 'none' && !$Actions->{AgentNotifyBody} ) {
        $Self->{LastError} = 'Translate:AutomationAgentNotifyBodyRequired';
        return;
    }
    if ( $Actions->{ChecklistSetEnabled} ) {
        if ( !$Actions->{ChecklistSetTemplateID} || !$Actions->{ChecklistSetTemplateItemID} ) {
            $Self->{LastError} = 'Translate:AutomationChecklistItemRequired';
            return;
        }
        my $ValidItem = $Self->{DB}->SelectRow(
            'SELECT id FROM checklist_template_item WHERE id = ? AND template_id = ? AND active = 1 LIMIT 1',
            $Actions->{ChecklistSetTemplateItemID},
            $Actions->{ChecklistSetTemplateID},
        );
        if ( !$ValidItem ) {
            $Self->{LastError} = 'Translate:AutomationChecklistItemInvalid';
            return;
        }
    }

    if ( $Actions->{DeleteTickets} ) {
        if ( ( $Actions->{DeleteConfirmText} || '' ) ne 'DELETE' ) {
            $Self->{LastError} = 'Translate:AutomationDeleteConfirmationInvalid';
            return;
        }
        if ( !$Self->_ConditionsHaveRestriction($Conditions) ) {
            $Self->{LastError} = 'Translate:AutomationDeleteNeedsCondition';
            return;
        }
        my @Other = grep { $_ }
            $Actions->{QueueID}, $Actions->{StateID}, $Actions->{PriorityID},
            ( ( $Actions->{OwnerMode} || 'keep' ) ne 'keep' ),
            ( ( $Actions->{ResponsibleMode} || 'keep' ) ne 'keep' ),
            ( ( $Actions->{ServiceMode} || 'keep' ) ne 'keep' ),
            scalar @{ $Actions->{Dynamic} || [] },
            scalar @{ $Actions->{ChecklistAddTemplateIDs} || [] },
            scalar @{ $Actions->{ChecklistRemoveTemplateIDs} || [] },
            $Actions->{ChecklistSetEnabled},
            $Actions->{NoteEnabled}, $Actions->{EmailEnabled},
            ( ( $Actions->{AgentNotifyMode} || 'none' ) ne 'none' );
        if (@Other) {
            $Self->{LastError} = 'Translate:AutomationDeleteExclusive';
            return;
        }
    }
    elsif ( !$Self->_ActionsHaveAction($Actions) ) {
        $Self->{LastError} = 'Translate:AutomationActionRequired';
        return;
    }

    # The confirmation word is only required while saving a deletion rule and is
    # deliberately not persisted with the executable actions.
    delete $Actions->{DeleteConfirmText};

    my $NextRun;
    if ( $Type eq 'schedule' ) {
        $NextRun = $Self->NextRunCalculate( Schedule => $Schedule, From => time );
    }

    return {
        name               => $Name,
        description        => $Self->_Trim( $Param{Description} ),
        rule_type          => $Type,
        event_name         => $Type eq 'trigger' ? $Event : '',
        conditions         => $Conditions,
        actions            => $Actions,
        schedule           => $Type eq 'schedule' ? $Schedule : {},
        next_run_at        => $NextRun,
        active             => $Param{Active} ? 1 : 0,
        sort_order         => $Self->_Unsigned( $Param{SortOrder} ) || 1000,
        changed_by_user_id => $Param{ChangedByUserID} || 1,
    };
}

sub _TicketSelectionSQL {
    my ( $Self, %Param ) = @_;
    my $Conditions = $Param{Conditions} || {};
    my $SearchObject = QisutuTicketSearch->new(
        Config => $Self->{Config},
        DB     => $Self->{DB},
    );
    my $WhereData = $SearchObject->WhereData( Search => $Conditions->{Search} || { Active => 1 } );
    if ( $SearchObject->Error() ) {
        $Self->{LastError} = $SearchObject->Error();
        return;
    }

    my @Where = @{ $WhereData->{Where} || [] };
    my @Bind  = @{ $WhereData->{Bind} || [] };
    push @Where, 't.changed_at <= ?' if $Conditions->{ChangedOlderMinutes};
    push @Bind, $Self->_DateTimeBeforeMinutes( $Conditions->{ChangedOlderMinutes} ) if $Conditions->{ChangedOlderMinutes};
    push @Where, '(t.last_customer_article_at IS NOT NULL AND t.last_customer_article_at <= ?)' if $Conditions->{LastCustomerOlderMinutes};
    push @Bind, $Self->_DateTimeBeforeMinutes( $Conditions->{LastCustomerOlderMinutes} ) if $Conditions->{LastCustomerOlderMinutes};
    push @Where, '(t.last_agent_article_at IS NOT NULL AND t.last_agent_article_at <= ?)' if $Conditions->{LastAgentOlderMinutes};
    push @Bind, $Self->_DateTimeBeforeMinutes( $Conditions->{LastAgentOlderMinutes} ) if $Conditions->{LastAgentOlderMinutes};
    push @Where, 't.owner_user_id IS NULL' if $Conditions->{NoOwner};
    push @Where, 't.responsible_user_id IS NULL' if $Conditions->{NoResponsible};

    my $ChecklistObject = QisutuChecklist->new( Config => $Self->{Config}, DB => $Self->{DB} );
    my $ChecklistData = $ChecklistObject->TicketConditionSQL( Condition => $Conditions->{Checklist} || {} );
    push @Where, @{ $ChecklistData->{Where} || [] };
    push @Bind, @{ $ChecklistData->{Bind} || [] };

    return {
        Where => @Where ? join( ' AND ', map { '(' . $_ . ')' } @Where ) : '1=1',
        Bind  => \@Bind,
    };
}

sub _ActionsHaveAction {
    my ( $Self, $A ) = @_;
    return 1 if $A->{QueueID} || $A->{StateID} || $A->{PriorityID};
    return 1 if ( $A->{OwnerMode} || 'keep' ) ne 'keep';
    return 1 if ( $A->{ResponsibleMode} || 'keep' ) ne 'keep';
    return 1 if ( $A->{ServiceMode} || 'keep' ) ne 'keep';
    return 1 if @{ $A->{Dynamic} || [] };
    return 1 if @{ $A->{ChecklistAddTemplateIDs} || [] };
    return 1 if @{ $A->{ChecklistRemoveTemplateIDs} || [] };
    return 1 if $A->{ChecklistSetEnabled};
    return 1 if $A->{NoteEnabled} || $A->{EmailEnabled} || $A->{DeleteTickets};
    return 1 if ( $A->{AgentNotifyMode} || 'none' ) ne 'none';
    return 0;
}

sub _ConditionsHaveRestriction {
    my ( $Self, $C ) = @_;
    my $Data = $Self->_TicketSelectionSQL( Conditions => $C || {} );
    return 0 if !$Data;
    return ( $Data->{Where} || '1=1' ) ne '1=1' ? 1 : 0;
}

sub _DirectTicketUpdate {
    my ( $Self, %Param ) = @_;
    my $SQL = $Param{SQL} || '';
    return if $SQL !~ m{\A(?:owner_user_id|responsible_user_id) = NULL\z};
    my $Result = $Self->{DB}->Do(
        'UPDATE ticket SET ' . $SQL . ', changed_by_user_id = ?, changed_at = NOW() WHERE id = ?',
        $Param{UserID} || 1,
        $Param{TicketID},
    );
    if (!$Result) {
        $Self->{LastError} = $Self->{DB}->Error() || 'Ticket update failed';
        return;
    }
    return 1;
}

sub _CustomerEmailSend {
    my ( $Self, %Param ) = @_;
    my $Ticket = $Self->{DB}->SelectRow(
        'SELECT t.id, t.ticket_number, t.title,
                ua.firstname, ua.lastname, ua.email AS customer_email,
                se.name AS from_name, se.email AS from_email
         FROM ticket t
         INNER JOIN customer_user cu ON cu.id = t.customer_user_id
         INNER JOIN user_account ua ON ua.id = cu.user_account_id
         INNER JOIN ticket_queue q ON q.id = t.queue_id
         LEFT JOIN system_email se ON se.id = q.system_email_id AND se.active = 1
         WHERE t.id = ? LIMIT 1',
        $Param{TicketID},
    );
    if (!$Ticket || !$Ticket->{customer_email} || !$Ticket->{from_email}) {
        $Self->{LastError} = 'Automation customer e-mail sender or recipient is missing';
        return;
    }
    my $SMTP = $Self->{DB}->SelectRow(
        'SELECT * FROM smtp_account WHERE active = 1 ORDER BY sort_order ASC, id ASC LIMIT 1'
    );
    if (!$SMTP) {
        $Self->{LastError} = 'No active SMTP transport configured';
        return;
    }

    require QisutuMail;
    my $TicketObject = QisutuTicket->new( Config => $Self->{Config}, DB => $Self->{DB} );
    my $Subject = $Param{Subject} || ( 'Automation: ' . ( $Param{RuleName} || '' ) );
    $Subject = $TicketObject->TicketSubjectBuild( TicketID => $Ticket->{id}, Subject => $Subject );
    my $ToName = join ' ', grep { $_ } ( $Ticket->{firstname}, $Ticket->{lastname} );
    my $Send = QisutuMail->new( Config => $Self->{Config}, DB => $Self->{DB} )->SMTPSend(
        Account   => $SMTP,
        FromName  => $Ticket->{from_name} || 'Qisutu',
        FromEmail => $Ticket->{from_email},
        ToName    => $ToName,
        ToEmail   => $Ticket->{customer_email},
        Subject   => $Subject,
        Body      => $Param{Body},
    );
    if ( !$Send || !$Send->{Success} ) {
        $Self->{LastError} = $Send->{Message} || 'Automation e-mail could not be sent';
        return;
    }

    my $ArticleID = $TicketObject->ArticleCreate(
        TicketID => $Ticket->{id}, Subject => $Subject, Body => $Param{Body},
        Channel => 'email', SenderType => 'agent',
        FromName => $Ticket->{from_name} || 'Qisutu', FromEmail => $Ticket->{from_email},
        ToName => $ToName, ToEmail => $Ticket->{customer_email},
        ContentType => 'text/html', Visibility => 'both',
        CreatedByUserID => $Param{UserID} || 1, ChangedByUserID => $Param{UserID} || 1,
        SkipTicketAccessCheck => 1, SkipNotification => 1,
    );
    if (!$ArticleID) {
        $Self->{LastError} = $TicketObject->Error() || 'Automation e-mail article could not be created';
        return;
    }
    return 1;
}

sub _AgentNotificationSend {
    my ( $Self, %Param ) = @_;

    my $TicketID = $Param{TicketID} || 0;
    my $Mode = $Param{Mode} || 'none';
    my $TargetUserID = $Param{UserID} || 0;

    my $Ticket = $Self->{DB}->SelectRow(
        'SELECT t.id, t.ticket_number, t.title, t.queue_id,
                q.full_name AS queue_name,
                se.name AS from_name, se.email AS from_email
         FROM ticket t
         INNER JOIN ticket_queue q ON q.id = t.queue_id
         LEFT JOIN system_email se ON se.id = q.system_email_id AND se.active = 1
         WHERE t.id = ? LIMIT 1',
        $TicketID,
    );
    if ( !$Ticket || !$Ticket->{from_email} ) {
        $Self->{LastError} = 'Automation agent notification sender is missing';
        return;
    }

    my $Recipients;
    if ( $Mode eq 'agent' ) {
        $Recipients = $Self->{DB}->SelectAll(
            'SELECT id, login, email, firstname, lastname
             FROM user_account
             WHERE id = ? AND account_type = ? AND is_active = 1
               AND is_system_user = 0 AND email <> ""
             LIMIT 1',
            $TargetUserID,
            'agent',
        ) || [];
    }
    elsif ( $Mode eq 'queue' ) {
        $Recipients = $Self->{DB}->SelectAll(
            'SELECT DISTINCT ua.id, ua.login, ua.email, ua.firstname, ua.lastname
             FROM ticket_queue_group tqg
             INNER JOIN user_group ug
                ON ug.id = tqg.user_group_id AND ug.active = 1
             INNER JOIN user_group_member ugm
                ON ugm.user_group_id = ug.id AND ugm.active = 1
             INNER JOIN user_account ua
                ON ua.id = ugm.user_account_id
               AND ua.account_type = ?
               AND ua.is_active = 1
               AND ua.is_system_user = 0
               AND ua.email <> ""
             WHERE tqg.queue_id = ? AND tqg.active = 1
               AND (
                    ugm.permission_full = 1
                    OR ugm.permission_read = 1
                    OR ugm.permission_overview = 1
               )
             ORDER BY ua.login ASC, ua.id ASC',
            'agent',
            $Ticket->{queue_id},
        ) || [];
        if ( !@{$Recipients} ) {
            $Recipients = $Self->{DB}->SelectAll(
                'SELECT DISTINCT ua.id, ua.login, ua.email, ua.firstname, ua.lastname
                 FROM ticket_queue_group tqg
                 INNER JOIN user_group ug
                    ON ug.id = tqg.user_group_id AND ug.active = 1
                 INNER JOIN user_group_member ugm
                    ON ugm.user_group_id = ug.id AND ugm.active = 1
                 INNER JOIN user_account ua
                    ON ua.id = ugm.user_account_id
                   AND ua.account_type = ?
                   AND ua.is_active = 1
                   AND ua.is_system_user = 0
                   AND ua.email <> ""
                 WHERE tqg.queue_id = ? AND tqg.active = 1
                 ORDER BY ua.login ASC, ua.id ASC',
                'agent',
                $Ticket->{queue_id},
            ) || [];
        }
    }
    else {
        $Self->{LastError} = 'Invalid automation agent notification mode';
        return;
    }

    if ( !@{$Recipients} ) {
        $Self->{LastError} = 'No active agent recipients found for automation notification';
        return;
    }

    my $SMTP = $Self->{DB}->SelectRow(
        'SELECT * FROM smtp_account WHERE active = 1 ORDER BY sort_order ASC, id ASC LIMIT 1'
    );
    if (!$SMTP) {
        $Self->{LastError} = 'No active SMTP transport configured';
        return;
    }

    require QisutuMail;
    my $MailObject = QisutuMail->new( Config => $Self->{Config}, DB => $Self->{DB} );
    my $SubjectBase = $Param{Subject} || ( 'Automation: ' . ( $Param{RuleName} || '' ) );
    my $BodyBase = $Param{Body} || '';
    my $Sent = 0;

    for my $Agent ( @{$Recipients} ) {
        my $Name = $Self->_Trim( join ' ', grep { defined $_ && $_ ne '' } ( $Agent->{firstname}, $Agent->{lastname} ) );
        $Name ||= $Agent->{login} || $Agent->{email};

        my %Replace = (
            '{{Agent.FullName}}' => $Name,
            '{{Ticket.Number}}'  => $Ticket->{ticket_number} || '',
            '{{Ticket.Title}}'   => $Ticket->{title} || '',
            '{{Ticket.Queue}}'   => $Ticket->{queue_name} || '',
        );
        my $Subject = $SubjectBase;
        my $Body = $BodyBase;
        for my $Key ( keys %Replace ) {
            my $Value = $Replace{$Key};
            $Subject =~ s/\Q$Key\E/$Value/g;
            $Body =~ s/\Q$Key\E/$Value/g;
        }

        my $Result = $MailObject->SMTPSend(
            Account   => $SMTP,
            FromName  => $Ticket->{from_name} || 'Qisutu',
            FromEmail => $Ticket->{from_email},
            ToName    => $Name,
            ToEmail   => $Agent->{email},
            Subject   => $Subject,
            Body      => $Body,
        );
        if ( !$Result || !$Result->{Success} ) {
            $Self->{LastError} = $Result->{Message} || 'Automation agent notification could not be sent';
            return;
        }
        $Sent++;
    }

    return $Sent;
}

sub _ActionError {
    my ( $Self, $Object ) = @_;
    $Self->{LastError} = $Object->Error() || 'Automation ticket action failed';
    return;
}

sub _JobSuccess {
    my ( $Self, %Param ) = @_;
    my $Job = $Param{Job} || {};
    my $ResultJSON = $Self->_JSONEncode( $Param{Result} || {} );
    $Self->{DB}->Do(
        'UPDATE automation_job
         SET status = ?, result_json = ?, error_message = NULL,
             finished_at = NOW(), locked_by = NULL, locked_until = NULL, changed_at = NOW()
         WHERE id = ?',
        'successful', $ResultJSON, $Job->{id},
    );
    $Self->{DB}->Do(
        'UPDATE automation_rule
         SET last_run_at = NOW(), last_result = ?, run_count = run_count + 1, changed_at = changed_at
         WHERE id = ?',
        'successful', $Job->{rule_id},
    );
    return 1;
}

sub _JobFail {
    my ( $Self, %Param ) = @_;
    my $Job = $Param{Job} || {};
    my $Error = $Param{Error} || 'Automation job failed';
    my $Attempts = $Job->{attempts} || 1;
    my $Max = $Job->{max_attempts} || 3;
    my $Retry = $Attempts < $Max ? 1 : 0;
    my $Status = $Retry ? 'pending' : 'failed';
    my $Next = $Retry ? strftime( '%Y-%m-%d %H:%M:%S', localtime( time + ( 60 * $Attempts ) ) ) : undef;
    $Self->{DB}->Do(
        'UPDATE automation_job
         SET status = ?, next_attempt_at = ?, error_message = ?,
             finished_at = CASE WHEN ? = ? THEN NOW() ELSE NULL END,
             locked_by = NULL, locked_until = NULL, changed_at = NOW()
         WHERE id = ?',
        $Status, $Next, substr( $Error, 0, 4000 ), $Status, 'failed', $Job->{id},
    );
    if (!$Retry) {
        $Self->{DB}->Do(
            'UPDATE automation_rule
             SET last_run_at = NOW(), last_result = ?, error_count = error_count + 1, changed_at = changed_at
             WHERE id = ?',
            'failed', $Job->{rule_id},
        );
    }
    $Self->{LastError} = $Error;
    return;
}

sub _AttachmentPaths {
    my ( $Self, %Param ) = @_;
    return [] if !$Self->_TableExists('ticket_article_attachment');
    my $Columns = $Self->{DB}->SelectAll(
        'SELECT COLUMN_NAME AS column_name
         FROM information_schema.COLUMNS
         WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = ?',
        'ticket_article_attachment',
    ) || [];
    my %Column = map { ( $_->{column_name} || '' ) => 1 } @{$Columns};
    my ($PathColumn) = grep { $Column{$_} } qw(storage_path file_path path);
    return [] if !$PathColumn;
    my $Rows = $Self->{DB}->SelectAll(
        'SELECT id, `' . $PathColumn . '` AS storage_path
         FROM ticket_article_attachment WHERE ticket_id = ?',
        $Param{TicketID},
    ) || [];
    return [ grep { $_->{storage_path} } @{$Rows} ];
}

sub _FilesStageForDeletion {
    my ( $Self, %Param ) = @_;
    my $Paths = $Param{Paths} || [];
    return [] if !@{$Paths};
    my $Var = $Self->{Config}->{Paths}->{Var} || File::Spec->catdir( $Self->{Config}->{RootPath}, 'var' );
    my $Trash = File::Spec->catdir( $Var, 'automation-delete-trash', ( $Param{JobID} || 'job' ) . '-' . ( $Param{TicketID} || 'ticket' ) . '-' . time );
    eval { make_path($Trash) };
    if ($@) {
        $Self->{LastError} = 'Deletion staging directory could not be created: ' . $@;
        return;
    }
    my @Staged;
    for my $Row ( @{$Paths} ) {
        my $Path = $Self->_PathAbsolute( $Row->{storage_path} || '' );
        next if !$Path || !-e $Path;
        if ( !$Self->_PathAllowed($Path) ) {
            $Self->_FilesRestore( Files => \@Staged );
            $Self->{LastError} = 'Attachment path is outside the Qisutu installation: ' . $Path;
            return;
        }
        my $Target = File::Spec->catfile( $Trash, ( $Row->{id} || 0 ) . '-' . basename($Path) );
        if ( !rename $Path, $Target ) {
            $Self->_FilesRestore( Files => \@Staged );
            $Self->{LastError} = 'Attachment file could not be staged for deletion: ' . $Path;
            return;
        }
        push @Staged, { original => $Path, staged => $Target, trash => $Trash };
    }
    return \@Staged;
}

sub _FilesRestore {
    my ( $Self, %Param ) = @_;
    for my $File ( reverse @{ $Param{Files} || [] } ) {
        rename $File->{staged}, $File->{original} if -e $File->{staged};
    }
    return 1;
}

sub _FilesFinalize {
    my ( $Self, %Param ) = @_;
    my %Trash;
    for my $File ( @{ $Param{Files} || [] } ) {
        unlink $File->{staged} if -e $File->{staged};
        $Trash{ $File->{trash} } = 1 if $File->{trash};
    }
    for my $Dir ( keys %Trash ) {
        eval { remove_tree($Dir) if -d $Dir };
    }
    return 1;
}

sub _PathAbsolute {
    my ( $Self, $Path ) = @_;
    return '' if !$Path;
    return File::Spec->rel2abs($Path) if File::Spec->file_name_is_absolute($Path);
    my $Root = $Self->{Config}->{RootPath} || '/opt/qisutu';
    return File::Spec->rel2abs( File::Spec->catfile( $Root, $Path ) );
}

sub _PathAllowed {
    my ( $Self, $Path ) = @_;
    my $Root = File::Spec->canonpath( File::Spec->rel2abs( $Self->{Config}->{RootPath} || '/opt/qisutu' ) );
    my $Abs  = File::Spec->canonpath( File::Spec->rel2abs($Path) );
    my $Separator = File::Spec->catfile( '', '' );
    $Separator = '/' if !$Separator;
    return 1 if $Abs eq $Root;
    return index( $Abs, $Root . $Separator ) == 0 ? 1 : 0;
}

sub _TableExists {
    my ( $Self, $Table ) = @_;
    my $Row = $Self->{DB}->SelectRow(
        'SELECT COUNT(*) AS table_count FROM information_schema.TABLES
         WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = ?',
        $Table,
    );
    return $Row && $Row->{table_count} ? 1 : 0;
}

sub _SystemUserID {
    my ($Self) = @_;
    my $Row = $Self->{DB}->SelectRow(
        'SELECT id FROM user_account WHERE is_system_user = 1 ORDER BY id ASC LIMIT 1'
    );
    return $Row && $Row->{id} ? $Row->{id} : 1;
}

sub _DateTimeBeforeMinutes {
    my ( $Self, $Minutes ) = @_;
    return strftime( '%Y-%m-%d %H:%M:%S', localtime( time - ( $Minutes * 60 ) ) );
}

sub _TimeParts {
    my ( $Self, $Value ) = @_;
    return ( $1, $2 ) if ( $Value || '' ) =~ m{\A(\d{1,2}):(\d{2})\z} && $1 < 24 && $2 < 60;
    return ( 2, 0 );
}

sub _JSONEncode {
    my ( $Self, $Data ) = @_;
    return eval { $Self->{JSON}->encode($Data) } || '{}';
}

sub _JSONDecode {
    my ( $Self, $Text, $Fallback ) = @_;
    return $Fallback if !defined $Text || $Text eq '';
    my $Data = eval { $Self->{JSON}->decode($Text) };
    return $@ ? $Fallback : $Data;
}

sub _IDList {
    my ( $Self, $Value ) = @_;
    my %Seen;
    return [ grep { !$Seen{$_}++ } map { 0 + $_ } grep { defined $_ && $_ =~ m{\A\d+\z} && $_ > 0 } @{ $Self->_ValueList($Value) } ];
}

sub _ValueList {
    my ( $Self, $Value ) = @_;
    return [] if !defined $Value;
    return [ @{$Value} ] if ref $Value eq 'ARRAY';
    return [$Value];
}

sub _Unsigned {
    my ( $Self, $Value ) = @_;
    return 0 if !defined $Value || ref $Value || $Value !~ m{\A\d+\z};
    return 0 + $Value;
}

sub _Trim {
    my ( $Self, $Value ) = @_;
    return '' if !defined $Value || ref $Value;
    $Value =~ s{\x00}{}g;
    $Value =~ s{\A\s+|\s+\z}{}g;
    return $Value;
}

1;
