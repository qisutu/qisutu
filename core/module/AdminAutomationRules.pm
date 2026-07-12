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

package AdminAutomationRules;

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
    my $Request  = $Param{Request} || {};
    my $User     = $Param{User} || {};
    my $Language = $Request->{Language} || 'en';
    my $RuleType = $Self->{Program}->{RuleType} || 'trigger';
    my $Page     = $RuleType eq 'schedule' ? 'AdminAutomationSchedules' : 'AdminAutomationTriggers';
    my $Object   = QisutuAutomation->new( Config => $Self->{Config}, DB => $Self->{DB} );
    my $Options  = $Object->Options( Language => $Language ) || {};
    my $DynamicFields = $Options->{DynamicFields} || [];
    my $Step = $Request->{Step} || '';
    my $Action = $Request->{Action} || 'List';
    my $Error = '';
    my $Preview;
    my $Rule;
    my $FormRequest = {};

    if ( $Step eq 'RuleCreate' || $Step eq 'RuleUpdate' || $Step eq 'RulePreview' ) {
        my $Conditions = $Object->ConditionsFromRequest(
            Request       => $Request,
            DynamicFields => $DynamicFields,
        );
        my $Actions = $Object->ActionsFromRequest(
            Request       => $Request,
            DynamicFields => $DynamicFields,
        );
        my $Schedule = $Object->ScheduleFromRequest( Request => $Request );
        $FormRequest = $Request;
        $Action = $Step eq 'RuleCreate' ? 'Create' : $Step eq 'RuleUpdate' ? 'Edit' : ( $Request->{RuleID} ? 'Edit' : 'Create' );

        if ( $Step eq 'RulePreview' ) {
            $Preview = $Object->TicketPreview( Conditions => $Conditions, Limit => 100 );
            $Error = $Object->Error();
        }
        elsif ( $Step eq 'RuleCreate' ) {
            my $ID = $Object->RuleCreate(
                Name            => $Request->{Name},
                Description     => $Request->{Description},
                RuleType        => $RuleType,
                EventName       => $Request->{EventName},
                Conditions      => $Conditions,
                Actions         => $Actions,
                Schedule        => $Schedule,
                Active          => $Request->{Active},
                SortOrder       => $Request->{SortOrder},
                ChangedByUserID => $User->{user_account_id},
            );
            return { Redirect => 'index.pl?Page=' . $Page } if $ID;
            $Error = $Object->Error();
        }
        else {
            my $OK = $Object->RuleUpdate(
                RuleID          => $Request->{RuleID},
                Name            => $Request->{Name},
                Description     => $Request->{Description},
                RuleType        => $RuleType,
                EventName       => $Request->{EventName},
                Conditions      => $Conditions,
                Actions         => $Actions,
                Schedule        => $Schedule,
                Active          => $Request->{Active},
                SortOrder       => $Request->{SortOrder},
                ChangedByUserID => $User->{user_account_id},
            );
            return { Redirect => 'index.pl?Page=' . $Page . ';Action=Edit;RuleID=' . ( $Request->{RuleID} || 0 ) } if $OK;
            $Error = $Object->Error();
        }
    }
    elsif ( $Step eq 'RuleDeactivate' ) {
        my $OK = $Object->RuleDeactivate(
            RuleID          => $Request->{RuleID},
            ChangedByUserID => $User->{user_account_id},
        );
        return { Redirect => 'index.pl?Page=' . $Page } if $OK;
        $Error = $Object->Error();
    }

    if ( $Action eq 'Edit' && !%{$FormRequest} ) {
        $Rule = $Object->RuleGet( RuleID => $Request->{RuleID} );
        if ($Rule) {
            $FormRequest = $Self->_RequestFromRule( Rule => $Rule );
        }
        else {
            $Error ||= $Object->Error();
            $Action = 'List';
        }
    }
    elsif ( $Action eq 'Create' && !%{$FormRequest} ) {
        $FormRequest = {
            Active => 1,
            SortOrder => 1000,
            ConditionTextMode => 'all',
            ScheduleType => 'every_minutes',
            ScheduleIntervalMinutes => 15,
            ScheduleMinute => 0,
            ScheduleTime => '02:00',
            ScheduleWeekday => 1,
            ScheduleMonthday => 1,
            ActionOwnerMode => 'keep',
            ActionResponsibleMode => 'keep',
            ActionServiceMode => 'keep',
            ActionAgentNotifyMode => 'none',
        };
    }

    my $Rules = $Object->RuleList( Type => $RuleType );
    $Error ||= $Object->Error();

    my $TitleKey = $RuleType eq 'schedule' ? 'AdminAutomationSchedulesTitle' : 'AdminAutomationTriggersTitle';
    my $DescriptionKey = $RuleType eq 'schedule' ? 'AdminAutomationSchedulesDescription' : 'AdminAutomationTriggersDescription';
    my $ListKey = $RuleType eq 'schedule' ? 'AdminAutomationSchedulesList' : 'AdminAutomationTriggersList';
    my $CreateKey = $RuleType eq 'schedule' ? 'AdminAutomationScheduleCreate' : 'AdminAutomationTriggerCreate';
    my $EditKey = $RuleType eq 'schedule' ? 'AdminAutomationScheduleEdit' : 'AdminAutomationTriggerEdit';

    return {
        Template => 'AdminAutomationRules.tt',
        Data => {
            PageTitle          => 'Translate:' . $TitleKey,
            ProgramTitle       => 'Translate:' . $TitleKey,
            ProgramDescription => 'Translate:' . $DescriptionKey,
            PageName           => $Page,
            RuleType           => $RuleType,
            RuleTypeIsTrigger  => $RuleType eq 'trigger' ? 1 : 0,
            RuleTypeIsSchedule => $RuleType eq 'schedule' ? 1 : 0,
            ListTitle          => 'Translate:' . $ListKey,
            CreateTitle        => 'Translate:' . $CreateKey,
            EditTitle          => 'Translate:' . $EditKey,
            Rules              => $Rules,
            RuleCount          => scalar @{$Rules},
            RulesRowsHTML      => $Self->_RulesRowsHTML( Rules => $Rules, RuleType => $RuleType, Page => $Page, Language => $Language ),
            ShowList           => $Action eq 'List' ? 1 : 0,
            ShowForm           => $Action eq 'Create' || $Action eq 'Edit' ? 1 : 0,
            ShowEdit           => $Action eq 'Edit' ? 1 : 0,
            FormTitle          => $Action eq 'Create' ? 'Translate:' . $CreateKey : 'Translate:' . $EditKey,
            FormStep           => $Action eq 'Create' ? 'RuleCreate' : 'RuleUpdate',
            FormRuleID         => $FormRequest->{RuleID} || '',
            FormName           => $FormRequest->{Name} || '',
            FormDescription    => $FormRequest->{Description} || '',
            FormSortOrder      => defined $FormRequest->{SortOrder} ? $FormRequest->{SortOrder} : 1000,
            FormActiveChecked  => $FormRequest->{Active} ? 'checked' : '',
            EventOptionsHTML   => $Self->_EventOptions( Selected => $FormRequest->{EventName}, Language => $Language ),
            ConditionText      => $FormRequest->{ConditionText} || '',
            ConditionTicketNumber => $FormRequest->{ConditionTicketNumber} || '',
            ConditionTitle     => $FormRequest->{ConditionTitle} || '',
            ConditionTextModeAllSelected => ( $FormRequest->{ConditionTextMode} || 'all' ) eq 'all' ? 'selected' : '',
            ConditionTextModeAnySelected => ( $FormRequest->{ConditionTextMode} || '' ) eq 'any' ? 'selected' : '',
            ConditionTextModePhraseSelected => ( $FormRequest->{ConditionTextMode} || '' ) eq 'phrase' ? 'selected' : '',
            ConditionScopeTitleChecked => $FormRequest->{ConditionScopeTitle} ? 'checked' : '',
            ConditionScopeArticleChecked => $FormRequest->{ConditionScopeArticle} ? 'checked' : '',
            ConditionScopePeopleChecked => $FormRequest->{ConditionScopePeople} ? 'checked' : '',
            ConditionScopeAttachmentChecked => $FormRequest->{ConditionScopeAttachment} ? 'checked' : '',
            QueueOptionsHTML   => $Self->_MultiOptions( List => $Options->{Queues}, Selected => $FormRequest->{ConditionQueueID} ),
            StateOptionsHTML   => $Self->_MultiOptions( List => $Options->{States}, Selected => $FormRequest->{ConditionStateID} ),
            PriorityOptionsHTML => $Self->_MultiOptions( List => $Options->{Priorities}, Selected => $FormRequest->{ConditionPriorityID} ),
            CustomerOptionsHTML => $Self->_MultiOptions( List => $Options->{Customers}, Selected => $FormRequest->{ConditionCustomerID} ),
            CustomerUserOptionsHTML => $Self->_MultiOptions( List => $Options->{CustomerUsers}, Selected => $FormRequest->{ConditionCustomerUserID} ),
            OwnerConditionOptionsHTML => $Self->_MultiOptions( List => $Options->{Owners}, Selected => $FormRequest->{ConditionOwnerID}, Unassigned => 1 ),
            ResponsibleConditionOptionsHTML => $Self->_MultiOptions( List => $Options->{Responsibles}, Selected => $FormRequest->{ConditionResponsibleID}, Unassigned => 1 ),
            ServiceOptionsHTML => $Self->_MultiOptions( List => $Options->{Services}, Selected => $FormRequest->{ConditionServiceID} ),
            SLAOptionsHTML => $Self->_MultiOptions( List => $Options->{SLAs}, Selected => $FormRequest->{ConditionSLAID} ),
            ConditionCreatedFrom => $FormRequest->{ConditionCreatedFrom} || '',
            ConditionCreatedTo => $FormRequest->{ConditionCreatedTo} || '',
            ConditionChangedFrom => $FormRequest->{ConditionChangedFrom} || '',
            ConditionChangedTo => $FormRequest->{ConditionChangedTo} || '',
            ConditionPendingFrom => $FormRequest->{ConditionPendingFrom} || '',
            ConditionPendingTo => $FormRequest->{ConditionPendingTo} || '',
            ConditionSolutionFrom => $FormRequest->{ConditionSolutionFrom} || '',
            ConditionSolutionTo => $FormRequest->{ConditionSolutionTo} || '',
            ConditionFirstResponseDueFrom => $FormRequest->{ConditionFirstResponseDueFrom} || '',
            ConditionFirstResponseDueTo => $FormRequest->{ConditionFirstResponseDueTo} || '',
            ConditionUpdateDueFrom => $FormRequest->{ConditionUpdateDueFrom} || '',
            ConditionUpdateDueTo => $FormRequest->{ConditionUpdateDueTo} || '',
            ConditionSolutionDueFrom => $FormRequest->{ConditionSolutionDueFrom} || '',
            ConditionSolutionDueTo => $FormRequest->{ConditionSolutionDueTo} || '',
            ConditionChangedOlderMinutes => $FormRequest->{ConditionChangedOlderMinutes} || '',
            ConditionLastCustomerOlderMinutes => $FormRequest->{ConditionLastCustomerOlderMinutes} || '',
            ConditionLastAgentOlderMinutes => $FormRequest->{ConditionLastAgentOlderMinutes} || '',
            ConditionNoOwnerChecked => $FormRequest->{ConditionNoOwner} ? 'checked' : '',
            ConditionNoResponsibleChecked => $FormRequest->{ConditionNoResponsible} ? 'checked' : '',
            EscalationOptionsHTML => $Self->_EscalationOptions( Selected => $FormRequest->{ConditionEscalation} ),
            ConditionChecklistTemplateOptionsHTML => $Self->_MultiOptions( List => $Options->{ChecklistTemplates}, Selected => $FormRequest->{ConditionChecklistTemplateID} ),
            ConditionChecklistHasOpenChecked => $FormRequest->{ConditionChecklistHasOpen} ? 'checked' : '',
            ConditionChecklistHasCompletedChecked => $FormRequest->{ConditionChecklistHasCompleted} ? 'checked' : '',
            ConditionChecklistOpenRequiredChecked => $FormRequest->{ConditionChecklistOpenRequired} ? 'checked' : '',
            ConditionChecklistAllRequiredDoneChecked => $FormRequest->{ConditionChecklistAllRequiredDone} ? 'checked' : '',
            DynamicConditionHTML => $Self->_DynamicConditionHTML( Fields => $DynamicFields, Request => $FormRequest ),
            ActionQueueOptionsHTML => $Self->_SingleOptions( List => $Options->{Queues}, Selected => $FormRequest->{ActionQueueID} ),
            ActionStateOptionsHTML => $Self->_SingleOptions( List => $Options->{States}, Selected => $FormRequest->{ActionStateID} ),
            ActionPriorityOptionsHTML => $Self->_SingleOptions( List => $Options->{Priorities}, Selected => $FormRequest->{ActionPriorityID} ),
            ActionOwnerOptionsHTML => $Self->_SingleOptions( List => $Options->{Owners}, Selected => $FormRequest->{ActionOwnerID} ),
            ActionResponsibleOptionsHTML => $Self->_SingleOptions( List => $Options->{Responsibles}, Selected => $FormRequest->{ActionResponsibleID} ),
            ActionServiceOptionsHTML => $Self->_SingleOptions( List => $Options->{Services}, Selected => $FormRequest->{ActionServiceID} ),
            ActionOwnerKeepSelected => ( $FormRequest->{ActionOwnerMode} || 'keep' ) eq 'keep' ? 'selected' : '',
            ActionOwnerSetSelected => ( $FormRequest->{ActionOwnerMode} || '' ) eq 'set' ? 'selected' : '',
            ActionOwnerClearSelected => ( $FormRequest->{ActionOwnerMode} || '' ) eq 'clear' ? 'selected' : '',
            ActionResponsibleKeepSelected => ( $FormRequest->{ActionResponsibleMode} || 'keep' ) eq 'keep' ? 'selected' : '',
            ActionResponsibleSetSelected => ( $FormRequest->{ActionResponsibleMode} || '' ) eq 'set' ? 'selected' : '',
            ActionResponsibleClearSelected => ( $FormRequest->{ActionResponsibleMode} || '' ) eq 'clear' ? 'selected' : '',
            ActionServiceKeepSelected => ( $FormRequest->{ActionServiceMode} || 'keep' ) eq 'keep' ? 'selected' : '',
            ActionServiceSetSelected => ( $FormRequest->{ActionServiceMode} || '' ) eq 'set' ? 'selected' : '',
            ActionServiceClearSelected => ( $FormRequest->{ActionServiceMode} || '' ) eq 'clear' ? 'selected' : '',
            ActionPendingMinutes => $FormRequest->{ActionPendingMinutes} || '',
            DynamicActionHTML => $Self->_DynamicActionHTML( Fields => $DynamicFields, Request => $FormRequest ),
            ActionChecklistAddTemplateOptionsHTML => $Self->_MultiOptions( List => $Options->{ChecklistTemplates}, Selected => $FormRequest->{ActionChecklistAddTemplateID} ),
            ActionChecklistRemoveTemplateOptionsHTML => $Self->_MultiOptions( List => $Options->{ChecklistTemplates}, Selected => $FormRequest->{ActionChecklistRemoveTemplateID} ),
            ActionChecklistSetTemplateOptionsHTML => $Self->_SingleOptions( List => $Options->{ChecklistTemplates}, Selected => $FormRequest->{ActionChecklistSetTemplateID} ),
            ActionChecklistSetItemOptionsHTML => $Self->_SingleOptions( List => $Options->{ChecklistItems}, Selected => $FormRequest->{ActionChecklistSetTemplateItemID} ),
            ActionChecklistSetEnabledChecked => $FormRequest->{ActionChecklistSetEnabled} ? 'checked' : '',
            ActionChecklistSetDoneChecked => $FormRequest->{ActionChecklistSetDone} ? 'checked' : '',
            ActionNoteEnabledChecked => $FormRequest->{ActionNoteEnabled} ? 'checked' : '',
            ActionNoteSubject => $FormRequest->{ActionNoteSubject} || '',
            ActionNoteBody => $FormRequest->{ActionNoteBody} || '',
            ActionNoteCustomerVisibleChecked => $FormRequest->{ActionNoteCustomerVisible} ? 'checked' : '',
            ActionEmailEnabledChecked => $FormRequest->{ActionEmailEnabled} ? 'checked' : '',
            ActionEmailSubject => $FormRequest->{ActionEmailSubject} || '',
            ActionEmailBody => $FormRequest->{ActionEmailBody} || '',
            ActionAgentNotifyModeNoneSelected => ( $FormRequest->{ActionAgentNotifyMode} || 'none' ) eq 'none' ? 'selected' : '',
            ActionAgentNotifyModeQueueSelected => ( $FormRequest->{ActionAgentNotifyMode} || '' ) eq 'queue' ? 'selected' : '',
            ActionAgentNotifyModeAgentSelected => ( $FormRequest->{ActionAgentNotifyMode} || '' ) eq 'agent' ? 'selected' : '',
            ActionAgentNotifyUserOptionsHTML => $Self->_SingleOptions( List => $Options->{Owners}, Selected => $FormRequest->{ActionAgentNotifyUserID} ),
            ActionAgentNotifySubject => $FormRequest->{ActionAgentNotifySubject} || '',
            ActionAgentNotifyBody => $FormRequest->{ActionAgentNotifyBody} || '',
            ActionDeleteTicketsChecked => $FormRequest->{ActionDeleteTickets} ? 'checked' : '',
            ActionDeleteConfirmText => $FormRequest->{ActionDeleteConfirmText} || '',
            ScheduleTypeEveryMinutesSelected => ( $FormRequest->{ScheduleType} || 'every_minutes' ) eq 'every_minutes' ? 'selected' : '',
            ScheduleTypeHourlySelected => ( $FormRequest->{ScheduleType} || '' ) eq 'hourly' ? 'selected' : '',
            ScheduleTypeDailySelected => ( $FormRequest->{ScheduleType} || '' ) eq 'daily' ? 'selected' : '',
            ScheduleTypeWeeklySelected => ( $FormRequest->{ScheduleType} || '' ) eq 'weekly' ? 'selected' : '',
            ScheduleTypeMonthlySelected => ( $FormRequest->{ScheduleType} || '' ) eq 'monthly' ? 'selected' : '',
            ScheduleIntervalMinutes => $FormRequest->{ScheduleIntervalMinutes} || 15,
            ScheduleMinute => defined $FormRequest->{ScheduleMinute} ? $FormRequest->{ScheduleMinute} : 0,
            ScheduleTime => $FormRequest->{ScheduleTime} || '02:00',
            ScheduleWeekday => $FormRequest->{ScheduleWeekday} || 1,
            ScheduleWeekday1Selected => ( $FormRequest->{ScheduleWeekday} || 1 ) == 1 ? 'selected' : '',
            ScheduleWeekday2Selected => ( $FormRequest->{ScheduleWeekday} || 1 ) == 2 ? 'selected' : '',
            ScheduleWeekday3Selected => ( $FormRequest->{ScheduleWeekday} || 1 ) == 3 ? 'selected' : '',
            ScheduleWeekday4Selected => ( $FormRequest->{ScheduleWeekday} || 1 ) == 4 ? 'selected' : '',
            ScheduleWeekday5Selected => ( $FormRequest->{ScheduleWeekday} || 1 ) == 5 ? 'selected' : '',
            ScheduleWeekday6Selected => ( $FormRequest->{ScheduleWeekday} || 1 ) == 6 ? 'selected' : '',
            ScheduleWeekday7Selected => ( $FormRequest->{ScheduleWeekday} || 1 ) == 7 ? 'selected' : '',
            ScheduleMonthday => $FormRequest->{ScheduleMonthday} || 1,
            PreviewVisible => $Preview ? 1 : 0,
            PreviewCount => $Preview ? $Preview->{Count} : 0,
            PreviewTickets => $Preview ? $Preview->{Tickets} : [],
            PreviewHasTickets => $Preview && @{ $Preview->{Tickets} || [] } ? 1 : 0,
            PreviewRowsHTML => $Self->_PreviewRowsHTML( Tickets => $Preview ? $Preview->{Tickets} : [] ),
            ErrorMessage => $Error,
            ErrorClass => $Error ? '' : 'qisutu-hidden',
        },
    };
}

sub _RulesRowsHTML {
    my ( $Self, %Param ) = @_;
    my $HTML = '';
    my $RuleType = $Param{RuleType} || 'trigger';
    my $Page = $Param{Page} || '';
    my $Language = $Param{Language} || 'en';
    my $Edit = $Self->{Output}->Translate( Key => 'AdminEdit', Language => $Language );
    my $Yes  = $Self->{Output}->Translate( Key => 'AdminActiveYes', Language => $Language );
    my $No   = $Self->{Output}->Translate( Key => 'AdminActiveNo', Language => $Language );

    for my $Rule ( @{ $Param{Rules} || [] } ) {
        my $Description = $Rule->{description}
            ? '<br><small>' . $Self->{Output}->HTMLEscape( $Rule->{description} ) . '</small>'
            : '';
        $HTML .= '<tr>';
        $HTML .= '<td><strong>' . $Self->{Output}->HTMLEscape( $Rule->{name} || '' ) . '</strong>' . $Description . '</td>';
        if ( $RuleType eq 'trigger' ) {
            $HTML .= '<td>' . $Self->{Output}->HTMLEscape( $Self->_EventLabel( Event => $Rule->{event_name}, Language => $Language ) ) . '</td>';
        }
        else {
            $HTML .= '<td>' . $Self->{Output}->HTMLEscape( $Rule->{schedule_summary} || '-' ) . '</td>';
            $HTML .= '<td>' . $Self->{Output}->HTMLEscape( $Rule->{next_run_at} || '-' ) . '</td>';
        }
        $HTML .= '<td>' . $Self->{Output}->HTMLEscape( $Rule->{condition_summary} || '-' ) . '</td>';
        $HTML .= '<td>' . $Self->{Output}->HTMLEscape( $Rule->{action_summary} || '-' ) . '</td>';
        $HTML .= '<td>' . $Self->{Output}->HTMLEscape( $Rule->{active} ? $Yes : $No ) . '</td>';
        $HTML .= '<td><a class="qisutu-button qisutu-button-secondary qisutu-button-small" href="index.pl?Page=' .
            $Self->{Output}->HTMLEscape($Page) . ';Action=Edit;RuleID=' . int( $Rule->{id} || 0 ) . '">' .
            $Self->{Output}->HTMLEscape($Edit) . '</a></td>';
        $HTML .= '</tr>';
    }
    return $HTML;
}

sub _PreviewRowsHTML {
    my ( $Self, %Param ) = @_;
    my $HTML = '';
    for my $Ticket ( @{ $Param{Tickets} || [] } ) {
        $HTML .= '<tr>';
        for my $Key (qw(ticket_number title queue_name state_name priority_name)) {
            $HTML .= '<td>' . $Self->{Output}->HTMLEscape( $Ticket->{$Key} || '' ) . '</td>';
        }
        $HTML .= '</tr>';
    }
    return $HTML;
}

sub _EventLabel {
    my ( $Self, %Param ) = @_;
    my $Language = $Param{Language} || 'en';
    my %DE = (
        ticket_created => 'Ticket erstellt', customer_article_created => 'Kundenantwort eingegangen',
        agent_article_created => 'Agentenantwort erstellt', note_created => 'Notiz erstellt',
        status_changed => 'Status geändert', queue_changed => 'Queue geändert',
        priority_changed => 'Priorität geändert', owner_changed => 'Besitzer geändert',
        responsible_changed => 'Verantwortlicher geändert', service_changed => 'Service geändert',
        sla_changed => 'SLA geändert', dynamic_field_changed => 'Dynamisches Feld geändert',
        ticket_closed => 'Ticket geschlossen', ticket_reopened => 'Ticket wieder geöffnet',
        pending_reached => 'Warten-Zeitpunkt erreicht', sla_warning => 'SLA gefährdet',
        sla_breached => 'SLA verletzt', ticket_changed => 'Ticket geändert',
        any_ticket_change => 'Beliebige Ticketänderung',
    );
    my %EN = (
        ticket_created => 'Ticket created', customer_article_created => 'Customer reply received',
        agent_article_created => 'Agent reply created', note_created => 'Note created',
        status_changed => 'Status changed', queue_changed => 'Queue changed',
        priority_changed => 'Priority changed', owner_changed => 'Owner changed',
        responsible_changed => 'Responsible agent changed', service_changed => 'Service changed',
        sla_changed => 'SLA changed', dynamic_field_changed => 'Dynamic field changed',
        ticket_closed => 'Ticket closed', ticket_reopened => 'Ticket reopened',
        pending_reached => 'Pending time reached', sla_warning => 'SLA at risk',
        sla_breached => 'SLA breached', ticket_changed => 'Ticket changed',
        any_ticket_change => 'Any ticket change',
    );
    return ( $Language eq 'de' ? $DE{ $Param{Event} || '' } : $EN{ $Param{Event} || '' } ) || $Param{Event} || '';
}

sub _RequestFromRule {
    my ( $Self, %Param ) = @_;
    my $Rule = $Param{Rule} || {};
    my $C = $Rule->{conditions} || {};
    my $S = $C->{Search} || {};
    my $A = $Rule->{actions} || {};
    my $Schedule = $Rule->{schedule} || {};
    my %R = (
        RuleID => $Rule->{id}, Name => $Rule->{name}, Description => $Rule->{description},
        Active => $Rule->{active}, SortOrder => $Rule->{sort_order}, EventName => $Rule->{event_name},
        ConditionText => $S->{Text}, ConditionTextMode => $S->{Mode},
        ConditionScopeTitle => $S->{Scopes}->{title}, ConditionScopeArticle => $S->{Scopes}->{article},
        ConditionScopePeople => $S->{Scopes}->{people}, ConditionScopeAttachment => $S->{Scopes}->{attachment},
        ConditionTicketNumber => $S->{TicketNumber}, ConditionTitle => $S->{Title},
        ConditionQueueID => $S->{QueueIDs}, ConditionStateID => $S->{StateIDs},
        ConditionPriorityID => $S->{PriorityIDs}, ConditionCustomerID => $S->{CustomerIDs},
        ConditionCustomerUserID => $S->{CustomerUserIDs}, ConditionOwnerID => $S->{OwnerIDs},
        ConditionResponsibleID => $S->{ResponsibleIDs}, ConditionServiceID => $S->{ServiceIDs},
        ConditionSLAID => $S->{SLAIDs}, ConditionCreatedFrom => $S->{CreatedFrom},
        ConditionCreatedTo => $S->{CreatedTo}, ConditionChangedFrom => $S->{ChangedFrom},
        ConditionChangedTo => $S->{ChangedTo}, ConditionPendingFrom => $S->{PendingFrom},
        ConditionPendingTo => $S->{PendingTo}, ConditionSolutionFrom => $S->{SolutionFrom},
        ConditionSolutionTo => $S->{SolutionTo},
        ConditionFirstResponseDueFrom => $S->{FirstResponseDueFrom},
        ConditionFirstResponseDueTo => $S->{FirstResponseDueTo},
        ConditionUpdateDueFrom => $S->{UpdateDueFrom}, ConditionUpdateDueTo => $S->{UpdateDueTo},
        ConditionSolutionDueFrom => $S->{SolutionDueFrom}, ConditionSolutionDueTo => $S->{SolutionDueTo},
        ConditionEscalation => $S->{Escalation},
        ConditionChangedOlderMinutes => $C->{ChangedOlderMinutes},
        ConditionLastCustomerOlderMinutes => $C->{LastCustomerOlderMinutes},
        ConditionLastAgentOlderMinutes => $C->{LastAgentOlderMinutes},
        ConditionNoOwner => $C->{NoOwner}, ConditionNoResponsible => $C->{NoResponsible},
        ConditionChecklistTemplateID => $C->{Checklist}->{TemplateIDs},
        ConditionChecklistHasOpen => $C->{Checklist}->{HasOpen},
        ConditionChecklistHasCompleted => $C->{Checklist}->{HasCompleted},
        ConditionChecklistOpenRequired => $C->{Checklist}->{OpenRequired},
        ConditionChecklistAllRequiredDone => $C->{Checklist}->{AllRequiredDone},
        ActionQueueID => $A->{QueueID}, ActionStateID => $A->{StateID},
        ActionPendingMinutes => $A->{PendingMinutes}, ActionPriorityID => $A->{PriorityID},
        ActionOwnerMode => $A->{OwnerMode}, ActionOwnerID => $A->{OwnerID},
        ActionResponsibleMode => $A->{ResponsibleMode}, ActionResponsibleID => $A->{ResponsibleID},
        ActionServiceMode => $A->{ServiceMode}, ActionServiceID => $A->{ServiceID},
        ActionNoteEnabled => $A->{NoteEnabled}, ActionNoteSubject => $A->{NoteSubject},
        ActionNoteBody => $A->{NoteBody}, ActionNoteCustomerVisible => $A->{NoteCustomerVisible},
        ActionEmailEnabled => $A->{EmailEnabled}, ActionEmailSubject => $A->{EmailSubject},
        ActionEmailBody => $A->{EmailBody}, ActionAgentNotifyMode => $A->{AgentNotifyMode},
        ActionAgentNotifyUserID => $A->{AgentNotifyUserID},
        ActionAgentNotifySubject => $A->{AgentNotifySubject}, ActionAgentNotifyBody => $A->{AgentNotifyBody},
        ActionChecklistAddTemplateID => $A->{ChecklistAddTemplateIDs},
        ActionChecklistRemoveTemplateID => $A->{ChecklistRemoveTemplateIDs},
        ActionChecklistSetTemplateID => $A->{ChecklistSetTemplateID},
        ActionChecklistSetTemplateItemID => $A->{ChecklistSetTemplateItemID},
        ActionChecklistSetEnabled => $A->{ChecklistSetEnabled},
        ActionChecklistSetDone => $A->{ChecklistSetDone},
        ActionDeleteTickets => $A->{DeleteTickets},
        ScheduleType => $Schedule->{type}, ScheduleIntervalMinutes => $Schedule->{interval_minutes},
        ScheduleMinute => $Schedule->{minute}, ScheduleTime => $Schedule->{time},
        ScheduleWeekday => $Schedule->{weekday}, ScheduleMonthday => $Schedule->{monthday},
    );
    for my $D ( @{ $S->{Dynamic} || [] } ) {
        my $ID = $D->{id};
        $R{'ConditionDFEnable_' . $ID} = 1;
        $R{'ConditionDFOperator_' . $ID} = $D->{operator};
        $R{'ConditionDFValue_' . $ID} = $D->{value};
        $R{'ConditionDFValueTo_' . $ID} = $D->{value_to};
        $R{'ConditionDFValues_' . $ID} = $D->{values};
    }
    for my $D ( @{ $A->{Dynamic} || [] } ) {
        my $ID = $D->{id};
        $R{'ActionDFEnable_' . $ID} = 1;
        $R{'ActionDFClear_' . $ID} = $D->{clear};
        if ( ( $D->{type} || '' ) eq 'multiselect' ) {
            $R{'ActionDFValues_' . $ID} = [ split /\n/, $D->{value} || '' ];
        }
        else {
            $R{'ActionDFValue_' . $ID} = $D->{value};
        }
    }
    return \%R;
}

sub _EventOptions {
    my ( $Self, %Param ) = @_;
    my @Event = qw(
        ticket_created customer_article_created agent_article_created note_created
        status_changed queue_changed priority_changed owner_changed responsible_changed
        service_changed sla_changed dynamic_field_changed ticket_closed ticket_reopened
        pending_reached sla_warning sla_breached ticket_changed any_ticket_change
    );
    my $HTML = '';
    for my $Event (@Event) {
        my $Selected = ( $Param{Selected} || '' ) eq $Event ? ' selected' : '';
        my $Label = $Self->_EventLabel( Event => $Event, Language => $Param{Language} || 'en' );
        $HTML .= '<option value="' . $Self->{Output}->HTMLEscape($Event) . '"' . $Selected . '>'
            . $Self->{Output}->HTMLEscape($Label) . '</option>';
    }
    return $HTML;
}

sub _MultiOptions {
    my ( $Self, %Param ) = @_;
    my %Selected = map { defined $_ ? ( $_ => 1 ) : () } @{ $Self->_ValueList( $Param{Selected} ) };
    my $HTML = '';
    if ( $Param{Unassigned} ) {
        $HTML .= '<option value="unassigned"' . ( $Selected{unassigned} ? ' selected' : '' ) . '>Nicht zugewiesen</option>';
    }
    for my $Row ( @{ $Param{List} || [] } ) {
        my $ID = $Row->{id};
        $HTML .= '<option value="' . $Self->{Output}->HTMLEscape($ID) . '"' . ( $Selected{$ID} ? ' selected' : '' ) . '>' . $Self->{Output}->HTMLEscape( $Row->{label} || $Row->{name} || '' ) . '</option>';
    }
    return $HTML;
}

sub _SingleOptions {
    my ( $Self, %Param ) = @_;
    my $Selected = defined $Param{Selected} ? $Param{Selected} : '';
    my $HTML = '';
    for my $Row ( @{ $Param{List} || [] } ) {
        my $ID = $Row->{id};
        $HTML .= '<option value="' . $Self->{Output}->HTMLEscape($ID) . '"' . ( "$Selected" eq "$ID" ? ' selected' : '' ) . '>' . $Self->{Output}->HTMLEscape( $Row->{label} || $Row->{name} || '' ) . '</option>';
    }
    return $HTML;
}

sub _EscalationOptions {
    my ( $Self, %Param ) = @_;
    my %Selected = map { $_ => 1 } @{ $Self->_ValueList( $Param{Selected} ) };
    my @Option = (
        [ normal => 'Im Plan' ], [ warning => 'Gefährdet' ], [ escalated => 'Verletzt' ],
        [ no_sla => 'Ohne SLA' ], [ first_open => 'Erstantwort offen' ],
        [ update_open => 'Aktualisierung offen' ], [ solution_open => 'Lösung offen' ],
    );
    return join '', map {
        '<option value="' . $_->[0] . '"' . ( $Selected{ $_->[0] } ? ' selected' : '' ) . '>' . $_->[1] . '</option>'
    } @Option;
}

sub _DynamicConditionHTML {
    my ( $Self, %Param ) = @_;
    my $Request = $Param{Request} || {};
    my $HTML = '';
    for my $Field ( @{ $Param{Fields} || [] } ) {
        my $ID = $Field->{id};
        my $Enabled = $Request->{'ConditionDFEnable_' . $ID} ? ' checked' : '';
        my $Operator = $Request->{'ConditionDFOperator_' . $ID} || 'contains';
        my $Type = $Field->{field_type} || 'text';
        $HTML .= '<div class="qisutu-automation-dynamic-row"><label class="qisutu-form-checkbox"><input type="checkbox" name="ConditionDFEnable_' . $ID . '" value="1"' . $Enabled . '><span>' . $Self->{Output}->HTMLEscape( $Field->{display_label} || $Field->{label} || $Field->{name} ) . '</span></label>';
        $HTML .= '<select name="ConditionDFOperator_' . $ID . '">';
        my @Ops = $Type eq 'date' ? ( [from=>'ab'], [to=>'bis'], [between=>'zwischen'], [empty=>'leer'], [not_empty=>'nicht leer'] )
            : $Type eq 'number' ? ( [exact=>'gleich'], [from=>'>='], [to=>'<='], [between=>'zwischen'], [empty=>'leer'], [not_empty=>'nicht leer'] )
            : $Type eq 'multiselect' ? ( [any=>'enthält einen Wert'], [all=>'enthält alle Werte'], [empty=>'leer'], [not_empty=>'nicht leer'] )
            : $Type eq 'dropdown' ? ( [exact=>'ist einer von'], [empty=>'leer'], [not_empty=>'nicht leer'] )
            : ( [contains=>'enthält'], [starts=>'beginnt mit'], [exact=>'ist genau'], [empty=>'leer'], [not_empty=>'nicht leer'] );
        for my $Op (@Ops) {
            $HTML .= '<option value="' . $Op->[0] . '"' . ( $Operator eq $Op->[0] ? ' selected' : '' ) . '>' . $Op->[1] . '</option>';
        }
        $HTML .= '</select>';
        if ( $Type eq 'dropdown' || $Type eq 'multiselect' ) {
            my %Selected = map { $_ => 1 } @{ $Self->_ValueList( $Request->{'ConditionDFValues_' . $ID} ) };
            $HTML .= '<select name="ConditionDFValues_' . $ID . '"' . ( $Type eq 'multiselect' ? ' multiple size="4"' : '' ) . '><option value=""></option>';
            for my $Option ( @{ $Field->{options} || [] } ) {
                my $Key = $Option->{option_key} || '';
                $HTML .= '<option value="' . $Self->{Output}->HTMLEscape($Key) . '"' . ( $Selected{$Key} ? ' selected' : '' ) . '>' . $Self->{Output}->HTMLEscape( $Option->{option_value} || $Key ) . '</option>';
            }
            $HTML .= '</select>';
        }
        else {
            my $InputType = $Type eq 'date' ? 'datetime-local' : $Type eq 'number' ? 'number' : 'text';
            $HTML .= '<input type="' . $InputType . '" name="ConditionDFValue_' . $ID . '" value="' . $Self->{Output}->HTMLEscape( $Request->{'ConditionDFValue_' . $ID} || '' ) . '">';
            if ( $Type eq 'date' || $Type eq 'number' ) {
                $HTML .= '<input type="' . $InputType . '" name="ConditionDFValueTo_' . $ID . '" value="' . $Self->{Output}->HTMLEscape( $Request->{'ConditionDFValueTo_' . $ID} || '' ) . '" placeholder="bis">';
            }
        }
        $HTML .= '</div>';
    }
    return $HTML || '<p class="qisutu-form-hint">Keine dynamischen Ticketfelder vorhanden.</p>';
}

sub _DynamicActionHTML {
    my ( $Self, %Param ) = @_;
    my $Request = $Param{Request} || {};
    my $HTML = '';
    for my $Field ( @{ $Param{Fields} || [] } ) {
        my $ID = $Field->{id};
        my $Type = $Field->{field_type} || 'text';
        $HTML .= '<div class="qisutu-automation-dynamic-row"><label class="qisutu-form-checkbox"><input type="checkbox" name="ActionDFEnable_' . $ID . '" value="1"' . ( $Request->{'ActionDFEnable_' . $ID} ? ' checked' : '' ) . '><span>' . $Self->{Output}->HTMLEscape( $Field->{display_label} || $Field->{label} || $Field->{name} ) . '</span></label>';
        $HTML .= '<label class="qisutu-form-checkbox"><input type="checkbox" name="ActionDFClear_' . $ID . '" value="1"' . ( $Request->{'ActionDFClear_' . $ID} ? ' checked' : '' ) . '><span>leeren</span></label>';
        if ( $Type eq 'dropdown' || $Type eq 'multiselect' ) {
            my %Selected = map { $_ => 1 } @{ $Self->_ValueList( $Type eq 'multiselect' ? $Request->{'ActionDFValues_' . $ID} : $Request->{'ActionDFValue_' . $ID} ) };
            $HTML .= '<select name="' . ( $Type eq 'multiselect' ? 'ActionDFValues_' : 'ActionDFValue_' ) . $ID . '"' . ( $Type eq 'multiselect' ? ' multiple size="4"' : '' ) . '><option value=""></option>';
            for my $Option ( @{ $Field->{options} || [] } ) {
                my $Key = $Option->{option_key} || '';
                $HTML .= '<option value="' . $Self->{Output}->HTMLEscape($Key) . '"' . ( $Selected{$Key} ? ' selected' : '' ) . '>' . $Self->{Output}->HTMLEscape( $Option->{option_value} || $Key ) . '</option>';
            }
            $HTML .= '</select>';
        }
        else {
            my $InputType = $Type eq 'date' ? 'datetime-local' : $Type eq 'number' ? 'number' : 'text';
            $HTML .= '<input type="' . $InputType . '" name="ActionDFValue_' . $ID . '" value="' . $Self->{Output}->HTMLEscape( $Request->{'ActionDFValue_' . $ID} || '' ) . '">';
        }
        $HTML .= '</div>';
    }
    return $HTML || '<p class="qisutu-form-hint">Keine dynamischen Ticketfelder vorhanden.</p>';
}

sub _ValueList {
    my ( $Self, $Value ) = @_;
    return [] if !defined $Value;
    return [ @{$Value} ] if ref $Value eq 'ARRAY';
    return [$Value];
}

1;
