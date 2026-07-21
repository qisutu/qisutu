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

package QisutuPostmasterFilter;

use strict;
use warnings;
use utf8;

use JSON::PP ();

sub new {
    my ( $Class, %Param ) = @_;

    my $Self = {
        Config    => $Param{Config},
        DB        => $Param{DB},
        Output    => $Param{Output},
        LastError => '',
    };

    bless $Self, $Class;
    return $Self;
}

sub Error {
    my ($Self) = @_;
    return $Self->{LastError} || '';
}

sub ConditionDefinitions {
    return [
        { key => 'from_email',          label => 'Translate:PostmasterConditionFromEmail',           type => 'text',    group => 'basic' },
        { key => 'from_domain',         label => 'Translate:PostmasterConditionFromDomain',          type => 'text',    group => 'basic' },
        { key => 'from_name',           label => 'Translate:PostmasterConditionFromName',            type => 'text',    group => 'basic' },
        { key => 'to',                  label => 'Translate:PostmasterConditionTo',                  type => 'text',    group => 'basic' },
        { key => 'cc',                  label => 'Translate:PostmasterConditionCc',                  type => 'text',    group => 'basic' },
        { key => 'subject',             label => 'Translate:PostmasterConditionSubject',             type => 'text',    group => 'basic' },
        { key => 'body',                label => 'Translate:PostmasterConditionBody',                type => 'text',    group => 'basic' },
        { key => 'subject_body',        label => 'Translate:PostmasterConditionSubjectBody',         type => 'text',    group => 'basic' },
        { key => 'attachment_name',     label => 'Translate:PostmasterConditionAttachmentName',      type => 'text',    group => 'basic' },
        { key => 'attachment_extension',label => 'Translate:PostmasterConditionAttachmentExtension', type => 'text',    group => 'basic' },
        { key => 'has_attachment',      label => 'Translate:PostmasterConditionHasAttachment',       type => 'boolean', group => 'basic' },

        { key => 'attachment_mime',     label => 'Translate:PostmasterConditionAttachmentMime',      type => 'text',    group => 'advanced', advanced => 1 },
        { key => 'attachment_count',    label => 'Translate:PostmasterConditionAttachmentCount',     type => 'number',  group => 'advanced', advanced => 1 },
        { key => 'message_id',          label => 'Translate:PostmasterConditionMessageID',           type => 'text',    group => 'advanced', advanced => 1 },
        { key => 'in_reply_to',         label => 'Translate:PostmasterConditionInReplyTo',           type => 'text',    group => 'advanced', advanced => 1 },
        { key => 'references',          label => 'Translate:PostmasterConditionReferences',          type => 'text',    group => 'advanced', advanced => 1 },
        { key => 'custom_header',       label => 'Translate:PostmasterConditionCustomHeader',        type => 'text',    group => 'advanced', advanced => 1, argument => 1 },
        { key => 'mailbox_name',        label => 'Translate:PostmasterConditionMailboxName',         type => 'text',    group => 'advanced', advanced => 1 },
        { key => 'mailbox_email',       label => 'Translate:PostmasterConditionMailboxEmail',        type => 'text',    group => 'advanced', advanced => 1 },

        # Diese Kontextbedingungen bleiben ausschließlich zur kompatiblen
        # Verarbeitung bereits gespeicherter Filter erhalten. In neuen
        # Filtern werden sie nicht mehr angeboten.
        { key => 'customer_name',       label => 'Translate:PostmasterConditionCustomerName',        type => 'text',    group => 'legacy', legacy => 1 },
        { key => 'customer_company',    label => 'Translate:PostmasterConditionCustomerCompany',     type => 'text',    group => 'legacy', legacy => 1 },
        { key => 'existing_ticket',     label => 'Translate:PostmasterConditionExistingTicket',      type => 'boolean', group => 'legacy', legacy => 1 },
    ];
}

sub OperatorDefinitions {
    return [
        { key => 'contains',      label => 'Translate:PostmasterOperatorContains',      type => 'text' },
        { key => 'not_contains',  label => 'Translate:PostmasterOperatorNotContains',   type => 'text' },
        { key => 'equals',        label => 'Translate:PostmasterOperatorEquals',        type => 'all' },
        { key => 'not_equals',    label => 'Translate:PostmasterOperatorNotEquals',     type => 'all' },
        { key => 'starts_with',   label => 'Translate:PostmasterOperatorStartsWith',    type => 'text' },
        { key => 'ends_with',     label => 'Translate:PostmasterOperatorEndsWith',      type => 'text' },
        { key => 'empty',         label => 'Translate:PostmasterOperatorEmpty',         type => 'text' },
        { key => 'not_empty',     label => 'Translate:PostmasterOperatorNotEmpty',      type => 'text' },
        { key => 'wildcard',      label => 'Translate:PostmasterOperatorWildcard',      type => 'text' },
        { key => 'regex',         label => 'Translate:PostmasterOperatorRegex',         type => 'text', advanced => 1 },
        { key => 'greater_than',  label => 'Translate:PostmasterOperatorGreaterThan',   type => 'number' },
        { key => 'less_than',     label => 'Translate:PostmasterOperatorLessThan',      type => 'number' },
        { key => 'at_least',      label => 'Translate:PostmasterOperatorAtLeast',       type => 'number' },
        { key => 'at_most',       label => 'Translate:PostmasterOperatorAtMost',        type => 'number' },
    ];
}

sub ActionDefinitions {
    return [
        { key => 'queue',                label => 'Translate:PostmasterActionQueue',              target => 'queue',               group => 'ticket',     target_label => 'Translate:PostmasterActionFieldQueue' },
        { key => 'state',                label => 'Translate:PostmasterActionState',              target => 'state',               group => 'ticket',     target_label => 'Translate:PostmasterActionFieldState' },
        { key => 'priority',             label => 'Translate:PostmasterActionPriority',           target => 'priority',            group => 'ticket',     target_label => 'Translate:PostmasterActionFieldPriority' },
        { key => 'owner',                label => 'Translate:PostmasterActionOwner',              target => 'agent',               group => 'ticket',     target_label => 'Translate:PostmasterActionFieldOwner' },
        { key => 'owner_clear',          label => 'Translate:PostmasterActionOwnerClear',         target => 'none',                group => 'ticket' },
        { key => 'responsible',          label => 'Translate:PostmasterActionResponsible',        target => 'agent',               group => 'ticket',     target_label => 'Translate:PostmasterActionFieldResponsible' },
        { key => 'responsible_clear',    label => 'Translate:PostmasterActionResponsibleClear',   target => 'none',                group => 'ticket' },
        { key => 'service',              label => 'Translate:PostmasterActionService',            target => 'service',             group => 'ticket',     target_label => 'Translate:PostmasterActionFieldService' },
        { key => 'sla',                  label => 'Translate:PostmasterActionSLA',                target => 'sla',                 group => 'ticket',     target_label => 'Translate:PostmasterActionFieldSLA' },
        { key => 'service_clear',        label => 'Translate:PostmasterActionServiceClear',       target => 'none',                group => 'ticket' },
        { key => 'customer',             label => 'Translate:PostmasterActionCustomer',           target => 'customer',            group => 'ticket',     target_label => 'Translate:PostmasterActionFieldCustomer' },
        { key => 'customer_user',        label => 'Translate:PostmasterActionCustomerUser',       target => 'customer_user',       group => 'ticket',     target_label => 'Translate:PostmasterActionFieldCustomerUser' },
        { key => 'customer_clear',       label => 'Translate:PostmasterActionCustomerClear',      target => 'none',                group => 'ticket' },
        { key => 'title_set',            label => 'Translate:PostmasterActionTitleSet',           target => 'text',                group => 'ticket',     value_label  => 'Translate:PostmasterActionFieldText' },
        { key => 'title_prepend',        label => 'Translate:PostmasterActionTitlePrepend',       target => 'text',                group => 'ticket',     value_label  => 'Translate:PostmasterActionFieldText' },
        { key => 'title_append',         label => 'Translate:PostmasterActionTitleAppend',        target => 'text',                group => 'ticket',     value_label  => 'Translate:PostmasterActionFieldText' },
        { key => 'dynamic_field',        label => 'Translate:PostmasterActionDynamicField',      target => 'dynamic_field_value', group => 'ticket',     target_label => 'Translate:PostmasterActionFieldDynamicField', value_label => 'Translate:PostmasterActionFieldNewValue' },
        { key => 'dynamic_field_clear',  label => 'Translate:PostmasterActionDynamicFieldClear', target => 'dynamic_field',       group => 'ticket',     target_label => 'Translate:PostmasterActionFieldDynamicField' },
        { key => 'pending_minutes',      label => 'Translate:PostmasterActionPendingMinutes',    target => 'number',              group => 'ticket',     value_label  => 'Translate:PostmasterActionFieldMinutes' },
        { key => 'article_visibility',   label => 'Translate:PostmasterActionArticleVisibility', target => 'visibility',          group => 'article',    value_label  => 'Translate:PostmasterActionFieldVisibility' },
        { key => 'sender_type',          label => 'Translate:PostmasterActionSenderType',        target => 'sender_type',         group => 'article',    value_label  => 'Translate:PostmasterActionFieldSenderType' },
        { key => 'reject',               label => 'Translate:PostmasterActionReject',            target => 'none',                group => 'processing' },
        { key => 'ignore',               label => 'Translate:PostmasterActionIgnore',            target => 'none',                group => 'processing' },
    ];
}

sub FilterList {
    my ( $Self, %Param ) = @_;

    my $Where = $Param{IncludeInactive} ? '' : 'WHERE f.active = 1';
    my $Rows = $Self->{DB}->SelectAll(
        'SELECT
            f.id, f.name, f.description, f.match_mode, f.message_scope,
            f.stop_after_match, f.active, f.sort_order, f.created_at, f.changed_at,
            (SELECT COUNT(*) FROM postmaster_filter_condition c WHERE c.filter_id = f.id) AS condition_count,
            (SELECT COUNT(*) FROM postmaster_filter_action a WHERE a.filter_id = f.id) AS action_count
         FROM postmaster_filter f
         ' . $Where . '
         ORDER BY f.sort_order ASC, f.name ASC, f.id ASC'
    );

    if ( !$Rows ) {
        $Self->{LastError} = $Self->{DB}->Error() || 'Translate:PostmasterFilterLoadFailed';
        return [];
    }

    return $Rows;
}

sub FilterGet {
    my ( $Self, %Param ) = @_;

    my $FilterID = $Self->_ID( $Param{FilterID} );
    if ( !$FilterID ) {
        $Self->{LastError} = 'Translate:PostmasterFilterNotFound';
        return;
    }

    my $Filter = $Self->{DB}->SelectRow(
        'SELECT id, name, description, match_mode, message_scope, stop_after_match,
                active, sort_order, created_by_user_id, changed_by_user_id, created_at, changed_at
         FROM postmaster_filter
         WHERE id = ?
         LIMIT 1',
        $FilterID,
    );

    if ( !$Filter ) {
        $Self->{LastError} = 'Translate:PostmasterFilterNotFound';
        return;
    }

    $Filter->{conditions} = $Self->{DB}->SelectAll(
        'SELECT id, filter_id, field_name, field_argument, operator, match_value,
                case_sensitive, sort_order
         FROM postmaster_filter_condition
         WHERE filter_id = ?
         ORDER BY sort_order ASC, id ASC',
        $FilterID,
    ) || [];

    $Filter->{actions} = $Self->{DB}->SelectAll(
        'SELECT id, filter_id, action_type, target_id, action_value, sort_order
         FROM postmaster_filter_action
         WHERE filter_id = ?
         ORDER BY sort_order ASC, id ASC',
        $FilterID,
    ) || [];

    return $Filter;
}

sub FilterCreate {
    my ( $Self, %Param ) = @_;

    return $Self->_FilterSave( %Param, Create => 1 );
}

sub FilterUpdate {
    my ( $Self, %Param ) = @_;

    return $Self->_FilterSave( %Param, Create => 0 );
}

sub FilterDeactivate {
    my ( $Self, %Param ) = @_;

    my $FilterID = $Self->_ID( $Param{FilterID} );
    my $UserID   = $Self->_ID( $Param{ChangedByUserID} ) || 1;

    if ( !$FilterID ) {
        $Self->{LastError} = 'Translate:PostmasterFilterNotFound';
        return;
    }

    my $Result = $Self->{DB}->Do(
        'UPDATE postmaster_filter
         SET active = 0, changed_by_user_id = ?, changed_at = NOW()
         WHERE id = ?',
        $UserID,
        $FilterID,
    );

    if ( !$Result ) {
        $Self->{LastError} = $Self->{DB}->Error() || 'Translate:PostmasterFilterSaveFailed';
        return;
    }

    return 1;
}

sub ConditionsFromRequest {
    my ( $Self, %Param ) = @_;

    my $Request = $Param{Request} || {};
    my @Index = $Self->_RequestIndexes(
        Request => $Request,
        CountKey => 'ConditionRowCount',
        Prefix   => 'ConditionField_',
    );
    my @Conditions;

    for my $Index (@Index) {
        my $Field = $Self->_Trim( $Request->{ 'ConditionField_' . $Index } );
        next if !$Field;

        push @Conditions, {
            field_name     => $Field,
            field_argument => $Self->_Trim( $Request->{ 'ConditionArgument_' . $Index } ),
            operator       => $Self->_Trim( $Request->{ 'ConditionOperator_' . $Index } ) || 'contains',
            match_value    => $Self->_Trim( $Request->{ 'ConditionValue_' . $Index } ),
            case_sensitive => $Request->{ 'ConditionCaseSensitive_' . $Index } ? 1 : 0,
            sort_order     => 10 + scalar(@Conditions) * 10,
        };
    }

    return \@Conditions;
}

sub ActionsFromRequest {
    my ( $Self, %Param ) = @_;

    my $Request = $Param{Request} || {};
    my @Index = $Self->_RequestIndexes(
        Request => $Request,
        CountKey => 'ActionRowCount',
        Prefix   => 'ActionType_',
    );
    my @Actions;

    for my $Index (@Index) {
        my $Type = $Self->_Trim( $Request->{ 'ActionType_' . $Index } );
        next if !$Type;

        push @Actions, {
            action_type  => $Type,
            target_id    => $Self->_OptionalID( $Request->{ 'ActionTargetID_' . $Index } ),
            action_value => $Self->_Trim( $Request->{ 'ActionValue_' . $Index } ),
            sort_order   => 10 + scalar(@Actions) * 10,
        };
    }

    return \@Actions;
}

sub Options {
    my ( $Self, %Param ) = @_;

    my $Language = $Param{Language} || $Self->{Config}->{Language}->{Default} || 'en';

    my $Queues = $Self->{DB}->SelectAll(
        'SELECT id, full_name AS label FROM ticket_queue WHERE active = 1 ORDER BY sort_order, full_name, id'
    ) || [];
    my $States = $Self->{DB}->SelectAll(
        'SELECT id, name AS label, state_type FROM ticket_state WHERE active = 1 ORDER BY sort_order, name, id'
    ) || [];
    my $Priorities = $Self->{DB}->SelectAll(
        'SELECT id, name AS label FROM ticket_priority WHERE active = 1 ORDER BY sort_order, priority_value, name, id'
    ) || [];
    my $Agents = $Self->{DB}->SelectAll(
        'SELECT id, CONCAT_WS(" ", firstname, lastname) AS full_name, login, email
         FROM user_account
         WHERE account_type = ? AND is_active = 1 AND is_system_user = 0
         ORDER BY lastname, firstname, login, id',
        'agent',
    ) || [];
    for my $Agent ( @{$Agents} ) {
        $Agent->{label} = $Agent->{full_name} || $Agent->{login} || $Agent->{email} || $Agent->{id};
        $Agent->{label} .= ' (' . $Agent->{login} . ')' if $Agent->{login} && $Agent->{label} ne $Agent->{login};
    }

    my $Services = $Self->{DB}->SelectAll(
        'SELECT id, full_name AS label FROM service WHERE active = 1 ORDER BY sort_order, full_name, id'
    ) || [];
    my $SLAs = $Self->{DB}->SelectAll(
        'SELECT sl.id, CONCAT(s.full_name, " — ", sl.name) AS label, sl.service_id
         FROM sla sl
         INNER JOIN service s ON s.id = sl.service_id
         WHERE sl.active = 1 AND s.active = 1
         ORDER BY s.sort_order, s.full_name, sl.sort_order, sl.name, sl.id'
    ) || [];
    my $Customers = $Self->{DB}->SelectAll(
        'SELECT id, CONCAT(name, " (", customer_number, ")") AS label
         FROM customer WHERE active = 1 ORDER BY name, customer_number, id'
    ) || [];
    my $CustomerUsers = $Self->{DB}->SelectAll(
        'SELECT cu.id,
                CONCAT(c.name, " — ", CONCAT_WS(" ", ua.firstname, ua.lastname), " <", ua.email, ">") AS label,
                cu.customer_id
         FROM customer_user cu
         INNER JOIN customer c ON c.id = cu.customer_id AND c.active = 1
         INNER JOIN user_account ua ON ua.id = cu.user_account_id
         WHERE cu.active = 1 AND ua.is_active = 1 AND ua.account_type = ?
         ORDER BY c.name, ua.lastname, ua.firstname, ua.email, cu.id',
        'customer',
    ) || [];
    my $DynamicFields = $Self->{DB}->SelectAll(
        'SELECT f.id, f.name, f.field_type,
                COALESCE(current_translation.label, default_translation.label, f.label, f.name) AS label
         FROM ticket_dynamic_field f
         LEFT JOIN ticket_dynamic_field_translation current_translation
            ON current_translation.field_id = f.id AND current_translation.language = ?
         LEFT JOIN ticket_dynamic_field_translation default_translation
            ON default_translation.field_id = f.id AND default_translation.language = ?
         WHERE f.active = 1
         ORDER BY f.sort_order, label, f.id',
        $Language,
        $Self->{Config}->{Language}->{Default} || 'en',
    ) || [];
    for my $Field ( @{$DynamicFields} ) {
        if ( ( $Field->{field_type} || '' ) eq 'dropdown' || ( $Field->{field_type} || '' ) eq 'multiselect' ) {
            $Field->{options} = $Self->{DB}->SelectAll(
                'SELECT option_key, option_value
                 FROM ticket_dynamic_field_option
                 WHERE field_id = ? AND active = 1
                 ORDER BY sort_order, option_value, id',
                $Field->{id},
            ) || [];
        }
    }
    my $Mailboxes = $Self->{DB}->SelectAll(
        'SELECT id, CONCAT(name, " <", email, ">") AS label, name, email
         FROM postmaster_imap_account
         WHERE active = 1
         ORDER BY sort_order, name, id'
    ) || [];

    return {
        Queues        => $Queues,
        States        => $States,
        Priorities    => $Priorities,
        Agents        => $Agents,
        Services      => $Services,
        SLAs          => $SLAs,
        Customers     => $Customers,
        CustomerUsers => $CustomerUsers,
        DynamicFields => $DynamicFields,
        Mailboxes     => $Mailboxes,
    };
}

sub Evaluate {
    my ( $Self, %Param ) = @_;

    $Self->{LastError} = '';
    my $Filters = $Self->FilterList();
    return if $Self->Error();

    my @Full;
    for my $Filter ( @{$Filters} ) {
        my $Full = $Self->FilterGet( FilterID => $Filter->{id} );
        return if !$Full;
        push @Full, $Full;
    }

    return $Self->_EvaluateWithFilters(
        Filters => \@Full,
        Message => $Param{Message} || {},
        Context => $Param{Context} || {},
    );
}

sub EvaluateDraft {
    my ( $Self, %Param ) = @_;

    $Self->{LastError} = '';
    my $Filter = $Param{Filter} || {};

    my $Validation = $Self->_FilterValidate(
        Name         => $Filter->{name} || 'Draft',
        MatchMode    => $Filter->{match_mode} || 'all',
        MessageScope => $Filter->{message_scope} || 'both',
        Conditions   => $Filter->{conditions} || [],
        Actions      => $Filter->{actions} || [],
        SkipNameCheck => 1,
    );
    return if !$Validation;

    return $Self->_EvaluateWithFilters(
        Filters => [ {
            id               => 0,
            name             => $Filter->{name} || 'Draft',
            description      => $Filter->{description} || '',
            match_mode       => $Filter->{match_mode} || 'all',
            message_scope    => $Filter->{message_scope} || 'both',
            stop_after_match => $Filter->{stop_after_match} ? 1 : 0,
            active           => 1,
            sort_order       => 0,
            conditions       => $Filter->{conditions} || [],
            actions          => $Filter->{actions} || [],
        } ],
        Message => $Param{Message} || {},
        Context => $Param{Context} || {},
    );
}

sub RunLogSave {
    my ( $Self, %Param ) = @_;

    my $Details = $Param{Details};
    my $JSON = '';
    if ( defined $Details ) {
        my $OK = eval {
            $JSON = JSON::PP->new->canonical(1)->allow_nonref(1)->encode($Details);
            1;
        };
        $JSON = '' if !$OK;
    }

    my $Result = $Self->{DB}->Do(
        'INSERT INTO postmaster_filter_run (
            imap_account_id, message_uid, message_scope, message_subject, from_email,
            ticket_id, result, filter_count, matched_count, details_json, error_message, created_at
         ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, NOW())',
        $Self->_OptionalID( $Param{IMAPAccountID} ),
        $Self->_Trim( $Param{MessageUID} ) || undef,
        $Self->_Trim( $Param{MessageScope} ) || 'new',
        substr( $Self->_Trim( $Param{MessageSubject} ), 0, 500 ) || undef,
        substr( $Self->_Trim( $Param{FromEmail} ), 0, 255 ) || undef,
        $Self->_OptionalID( $Param{TicketID} ),
        $Self->_Trim( $Param{Result} ) || 'processed',
        $Self->_Unsigned( $Param{FilterCount} ),
        $Self->_Unsigned( $Param{MatchedCount} ),
        $JSON || undef,
        $Self->_Trim( $Param{ErrorMessage} ) || undef,
    );

    if ( !$Result ) {
        $Self->{LastError} = $Self->{DB}->Error() || 'Translate:PostmasterFilterLogSaveFailed';
        return;
    }

    return $Self->{DB}->LastInsertID('postmaster_filter_run') || 1;
}

sub RunLogList {
    my ( $Self, %Param ) = @_;

    my $Limit = $Self->_Unsigned( $Param{Limit} ) || 50;
    $Limit = 200 if $Limit > 200;

    my $Rows = $Self->{DB}->SelectAll(
        'SELECT r.id, r.imap_account_id, r.message_uid, r.message_scope, r.message_subject,
                r.from_email, r.ticket_id, r.result, r.filter_count, r.matched_count,
                r.error_message, r.created_at, a.name AS mailbox_name
         FROM postmaster_filter_run r
         LEFT JOIN postmaster_imap_account a ON a.id = r.imap_account_id
         ORDER BY r.id DESC
         LIMIT ' . int($Limit)
    );

    if ( !$Rows ) {
        $Self->{LastError} = $Self->{DB}->Error() || 'Translate:PostmasterFilterLogLoadFailed';
        return [];
    }

    return $Rows;
}

sub RunLogGet {
    my ( $Self, %Param ) = @_;

    my $RunID = $Self->_ID( $Param{RunID} );
    return if !$RunID;

    my $Row = $Self->{DB}->SelectRow(
        'SELECT r.*, a.name AS mailbox_name, a.email AS mailbox_email,
                t.ticket_number, t.title AS ticket_title
         FROM postmaster_filter_run r
         LEFT JOIN postmaster_imap_account a ON a.id = r.imap_account_id
         LEFT JOIN ticket t ON t.id = r.ticket_id
         WHERE r.id = ? LIMIT 1',
        $RunID,
    );
    if (!$Row) {
        $Self->{LastError} = 'Translate:PostmasterFilterLogNotFound';
        return;
    }

    my $Details = {};
    if ( $Row->{details_json} ) {
        eval { $Details = JSON::PP->new->decode( $Row->{details_json} ); 1; } || do { $Details = {}; };
    }
    $Row->{details} = $Details;
    return $Row;
}

sub _FilterSave {
    my ( $Self, %Param ) = @_;

    $Self->{LastError} = '';
    my $Create       = $Param{Create} ? 1 : 0;
    my $FilterID     = $Self->_ID( $Param{FilterID} );
    my $Name         = $Self->_Trim( $Param{Name} );
    my $Description  = $Self->_Trim( $Param{Description} );
    my $MatchMode    = $Self->_Trim( $Param{MatchMode} ) || 'all';
    my $MessageScope = $Self->_Trim( $Param{MessageScope} ) || 'both';
    my $Stop         = $Param{StopAfterMatch} ? 1 : 0;
    my $Active       = $Param{Active} ? 1 : 0;
    my $SortOrder    = $Self->_Unsigned( $Param{SortOrder} ) || 1000;
    my $UserID       = $Self->_ID( $Param{ChangedByUserID} ) || 1;
    my $Conditions   = ref $Param{Conditions} eq 'ARRAY' ? $Param{Conditions} : [];
    my $Actions      = ref $Param{Actions} eq 'ARRAY' ? $Param{Actions} : [];

    if ( !$Create && !$FilterID ) {
        $Self->{LastError} = 'Translate:PostmasterFilterNotFound';
        return;
    }

    return if !$Self->_FilterValidate(
        FilterID     => $FilterID,
        Name         => $Name,
        MatchMode    => $MatchMode,
        MessageScope => $MessageScope,
        Conditions   => $Conditions,
        Actions      => $Actions,
    );

    if ( !$Self->{DB}->BeginWork() ) {
        $Self->{LastError} = $Self->{DB}->Error() || 'Translate:PostmasterFilterSaveFailed';
        return;
    }

    if ($Create) {
        my $Result = $Self->{DB}->Do(
            'INSERT INTO postmaster_filter (
                name, description, match_mode, message_scope, stop_after_match,
                active, sort_order, created_by_user_id, changed_by_user_id,
                created_at, changed_at
             ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, NOW(), NOW())',
            $Name,
            $Description || undef,
            $MatchMode,
            $MessageScope,
            $Stop,
            $Active,
            $SortOrder,
            $UserID,
            $UserID,
        );
        if ( !$Result ) {
            $Self->{LastError} = $Self->{DB}->Error() || 'Translate:PostmasterFilterSaveFailed';
            $Self->{DB}->Rollback();
            return;
        }
        $FilterID = $Self->{DB}->LastInsertID('postmaster_filter');
    }
    else {
        my $Result = $Self->{DB}->Do(
            'UPDATE postmaster_filter
             SET name = ?, description = ?, match_mode = ?, message_scope = ?,
                 stop_after_match = ?, active = ?, sort_order = ?,
                 changed_by_user_id = ?, changed_at = NOW()
             WHERE id = ?',
            $Name,
            $Description || undef,
            $MatchMode,
            $MessageScope,
            $Stop,
            $Active,
            $SortOrder,
            $UserID,
            $FilterID,
        );
        if ( !$Result ) {
            $Self->{LastError} = $Self->{DB}->Error() || 'Translate:PostmasterFilterSaveFailed';
            $Self->{DB}->Rollback();
            return;
        }

        for my $Table ( qw(postmaster_filter_condition postmaster_filter_action) ) {
            my $Deleted = $Self->{DB}->Do( 'DELETE FROM ' . $Table . ' WHERE filter_id = ?', $FilterID );
            if ( !$Deleted ) {
                $Self->{LastError} = $Self->{DB}->Error() || 'Translate:PostmasterFilterSaveFailed';
                $Self->{DB}->Rollback();
                return;
            }
        }
    }

    my $Sort = 10;
    for my $Condition ( @{$Conditions} ) {
        my $Result = $Self->{DB}->Do(
            'INSERT INTO postmaster_filter_condition (
                filter_id, field_name, field_argument, operator, match_value,
                case_sensitive, sort_order, created_by_user_id, changed_by_user_id,
                created_at, changed_at
             ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, NOW(), NOW())',
            $FilterID,
            $Condition->{field_name},
            $Condition->{field_argument} || undef,
            $Condition->{operator},
            defined $Condition->{match_value} ? $Condition->{match_value} : '',
            $Condition->{case_sensitive} ? 1 : 0,
            $Sort,
            $UserID,
            $UserID,
        );
        if ( !$Result ) {
            $Self->{LastError} = $Self->{DB}->Error() || 'Translate:PostmasterFilterSaveFailed';
            $Self->{DB}->Rollback();
            return;
        }
        $Sort += 10;
    }

    $Sort = 10;
    for my $Action ( @{$Actions} ) {
        my $Result = $Self->{DB}->Do(
            'INSERT INTO postmaster_filter_action (
                filter_id, action_type, target_id, action_value, sort_order,
                created_by_user_id, changed_by_user_id, created_at, changed_at
             ) VALUES (?, ?, ?, ?, ?, ?, ?, NOW(), NOW())',
            $FilterID,
            $Action->{action_type},
            $Action->{target_id},
            defined $Action->{action_value} ? $Action->{action_value} : '',
            $Sort,
            $UserID,
            $UserID,
        );
        if ( !$Result ) {
            $Self->{LastError} = $Self->{DB}->Error() || 'Translate:PostmasterFilterSaveFailed';
            $Self->{DB}->Rollback();
            return;
        }
        $Sort += 10;
    }

    if ( !$Self->{DB}->Commit() ) {
        $Self->{LastError} = $Self->{DB}->Error() || 'Translate:PostmasterFilterSaveFailed';
        $Self->{DB}->Rollback();
        return;
    }

    return $FilterID;
}

sub _FilterValidate {
    my ( $Self, %Param ) = @_;

    my $FilterID     = $Self->_ID( $Param{FilterID} );
    my $Name         = $Self->_Trim( $Param{Name} );
    my $MatchMode    = $Param{MatchMode} || 'all';
    my $MessageScope = $Param{MessageScope} || 'both';
    my $Conditions   = $Param{Conditions} || [];
    my $Actions      = $Param{Actions} || [];

    if ( !$Param{SkipNameCheck} ) {
        if ( !$Name ) {
            $Self->{LastError} = 'Translate:PostmasterFilterNameRequired';
            return;
        }
        if ( length($Name) > 190 ) {
            $Self->{LastError} = 'Translate:PostmasterFilterNameTooLong';
            return;
        }

        my $Duplicate = $Self->{DB}->SelectRow(
            'SELECT id FROM postmaster_filter WHERE name = ? AND id <> ? LIMIT 1',
            $Name,
            $FilterID || 0,
        );
        if ($Duplicate) {
            $Self->{LastError} = 'Translate:PostmasterFilterNameExists';
            return;
        }
    }

    if ( $MatchMode ne 'all' && $MatchMode ne 'any' ) {
        $Self->{LastError} = 'Translate:PostmasterFilterMatchModeInvalid';
        return;
    }
    if ( $MessageScope ne 'new' && $MessageScope ne 'follow_up' && $MessageScope ne 'both' ) {
        $Self->{LastError} = 'Translate:PostmasterFilterScopeInvalid';
        return;
    }
    if ( ref $Conditions ne 'ARRAY' || !@{$Conditions} ) {
        $Self->{LastError} = 'Translate:PostmasterFilterConditionRequired';
        return;
    }
    if ( ref $Actions ne 'ARRAY' || !@{$Actions} ) {
        $Self->{LastError} = 'Translate:PostmasterFilterActionRequired';
        return;
    }

    my %Field = map { $_->{key} => $_ } @{ $Self->ConditionDefinitions() };
    my %Operator = map { $_->{key} => $_ } @{ $Self->OperatorDefinitions() };

    for my $Condition ( @{$Conditions} ) {
        my $FieldName = $Condition->{field_name} || '';
        my $OperatorName = $Condition->{operator} || '';
        if ( !$Field{$FieldName} || !$Operator{$OperatorName} ) {
            $Self->{LastError} = 'Translate:PostmasterFilterConditionInvalid';
            return;
        }

        my $Type = $Field{$FieldName}->{type} || 'text';
        my $OperatorType = $Operator{$OperatorName}->{type} || 'text';
        if ( $OperatorType ne 'all' && $OperatorType ne $Type ) {
            $Self->{LastError} = 'Translate:PostmasterFilterOperatorInvalid';
            return;
        }

        if ( $FieldName eq 'custom_header' ) {
            my $Header = $Condition->{field_argument} || '';
            if ( $Header !~ m{\A[A-Za-z0-9][A-Za-z0-9-]{0,99}\z} ) {
                $Self->{LastError} = 'Translate:PostmasterFilterHeaderInvalid';
                return;
            }
        }

        if ( $OperatorName ne 'empty' && $OperatorName ne 'not_empty' ) {
            my $Value = defined $Condition->{match_value} ? $Condition->{match_value} : '';
            if ( $Value eq '' ) {
                $Self->{LastError} = 'Translate:PostmasterFilterConditionValueRequired';
                return;
            }
            if ( $Type eq 'number' && $Value !~ m{\A-?(?:\d+(?:\.\d+)?|\.\d+)\z} ) {
                $Self->{LastError} = 'Translate:PostmasterFilterNumberInvalid';
                return;
            }
            if ( $Type eq 'boolean' && $Value ne 'yes' && $Value ne 'no' ) {
                $Self->{LastError} = 'Translate:PostmasterFilterBooleanInvalid';
                return;
            }
        }

        if ( $OperatorName eq 'regex' ) {
            my $RegexError = $Self->_RegexValidate( Pattern => $Condition->{match_value} );
            if ($RegexError) {
                $Self->{LastError} = 'Translate:PostmasterFilterRegexInvalid: ' . $RegexError;
                return;
            }
        }
    }

    my %Action = map { $_->{key} => $_ } @{ $Self->ActionDefinitions() };
    for my $Item ( @{$Actions} ) {
        my $Type = $Item->{action_type} || '';
        if ( !$Action{$Type} ) {
            $Self->{LastError} = 'Translate:PostmasterFilterActionInvalid';
            return;
        }
        return if !$Self->_ActionValidate( Action => $Item, Definition => $Action{$Type} );
    }

    return 1;
}

sub _ActionValidate {
    my ( $Self, %Param ) = @_;

    my $Action     = $Param{Action} || {};
    my $Definition = $Param{Definition} || {};
    my $Type       = $Action->{action_type} || '';
    my $TargetType = $Definition->{target} || 'none';
    my $TargetID   = $Self->_OptionalID( $Action->{target_id} );
    my $Value      = defined $Action->{action_value} ? $Action->{action_value} : '';

    my %Table = (
        queue         => [ 'ticket_queue', 'active = 1' ],
        state         => [ 'ticket_state', 'active = 1' ],
        priority      => [ 'ticket_priority', 'active = 1' ],
        agent         => [ 'user_account', 'account_type = "agent" AND is_active = 1 AND is_system_user = 0' ],
        service       => [ 'service', 'active = 1' ],
        sla           => [ 'sla', 'active = 1' ],
        customer      => [ 'customer', 'active = 1' ],
        customer_user => [ 'customer_user', 'active = 1' ],
        dynamic_field => [ 'ticket_dynamic_field', 'active = 1' ],
    );

    my $LookupType = $TargetType eq 'dynamic_field_value' ? 'dynamic_field' : $TargetType;
    if ( $Table{$LookupType} ) {
        if (!$TargetID) {
            $Self->{LastError} = 'Translate:PostmasterFilterActionTargetRequired';
            return;
        }
        my ( $TableName, $Where ) = @{ $Table{$LookupType} };
        my $Row = $Self->{DB}->SelectRow(
            'SELECT id FROM ' . $TableName . ' WHERE id = ? AND ' . $Where . ' LIMIT 1',
            $TargetID,
        );
        if (!$Row) {
            $Self->{LastError} = 'Translate:PostmasterFilterActionTargetInvalid';
            return;
        }
    }

    if ( $TargetType eq 'text' || $TargetType eq 'dynamic_field_value' ) {
        if ( $Value eq '' ) {
            $Self->{LastError} = 'Translate:PostmasterFilterActionValueRequired';
            return;
        }
    }
    elsif ( $TargetType eq 'number' ) {
        if ( $Value !~ m{\A\d+\z} || $Value < 1 ) {
            $Self->{LastError} = 'Translate:PostmasterFilterNumberInvalid';
            return;
        }
    }
    elsif ( $TargetType eq 'visibility' ) {
        if ( $Value ne 'both' && $Value ne 'agent' ) {
            $Self->{LastError} = 'Translate:PostmasterFilterActionValueInvalid';
            return;
        }
    }
    elsif ( $TargetType eq 'sender_type' ) {
        if ( $Value ne 'customer' && $Value ne 'agent' && $Value ne 'system' ) {
            $Self->{LastError} = 'Translate:PostmasterFilterActionValueInvalid';
            return;
        }
    }

    return 1;
}

sub _EvaluateWithFilters {
    my ( $Self, %Param ) = @_;

    my $Filters = $Param{Filters} || [];
    my $Message = $Param{Message} || {};
    my $Context = $Param{Context} || {};
    my $Scope   = $Context->{MessageScope} || ( $Context->{ExistingTicketID} ? 'follow_up' : 'new' );

    my $Customer = $Self->_CustomerContext( Email => $Message->{from_email} );
    my $Result = {
        Title             => defined $Message->{subject} ? $Message->{subject} : '',
        TitleChanged      => 0,
        QueueID           => undef,
        StateID           => undef,
        PriorityID        => undef,
        OwnerUserID       => undef,
        OwnerClear        => 0,
        ResponsibleUserID => undef,
        ResponsibleClear  => 0,
        ServiceID         => undef,
        SLAID             => undef,
        ServiceClear      => 0,
        CustomerID        => undef,
        CustomerUserID    => undef,
        CustomerClear     => 0,
        DynamicFields     => {},
        ArticleVisibility => 'both',
        SenderType        => 'customer',
        PendingMinutes    => undef,
        Reject            => 0,
        Ignore            => 0,
        Stop              => 0,
        FilterCount       => scalar @{$Filters},
        MatchedCount      => 0,
        MatchedFilterIDs  => [],
        MatchedFilters    => [],
        Details           => [],
    };

    FILTER:
    for my $Filter ( @{$Filters} ) {
        next FILTER if ref $Filter ne 'HASH';
        next FILTER if exists $Filter->{active} && !$Filter->{active};

        my $FilterScope = $Filter->{message_scope} || 'both';
        if ( $FilterScope ne 'both' && $FilterScope ne $Scope ) {
            push @{ $Result->{Details} }, {
                filter_id   => $Filter->{id} || 0,
                filter_name => $Filter->{name} || '',
                scope_match => 0,
                matched     => 0,
                conditions  => [],
                actions     => [],
            };
            next FILTER;
        }

        my @ConditionResult;
        for my $Condition ( @{ $Filter->{conditions} || [] } ) {
            my @Value = $Self->_ConditionValues(
                Condition => $Condition,
                Message   => $Message,
                Context   => $Context,
                Customer  => $Customer,
            );
            my $Matched = $Self->_ConditionMatch(
                Condition => $Condition,
                Values    => \@Value,
            );
            push @ConditionResult, {
                field_name     => $Condition->{field_name} || '',
                field_argument => $Condition->{field_argument} || '',
                operator       => $Condition->{operator} || '',
                match_value    => defined $Condition->{match_value} ? $Condition->{match_value} : '',
                values         => \@Value,
                matched        => $Matched ? 1 : 0,
            };
        }

        my $Matched = 0;
        if ( @ConditionResult ) {
            if ( ( $Filter->{match_mode} || 'all' ) eq 'any' ) {
                $Matched = ( grep { $_->{matched} } @ConditionResult ) ? 1 : 0;
            }
            else {
                $Matched = ( grep { !$_->{matched} } @ConditionResult ) ? 0 : 1;
            }
        }

        my @ActionResult;
        my @ActionDetails;
        if ($Matched) {
            $Result->{MatchedCount}++;
            push @{ $Result->{MatchedFilterIDs} }, $Filter->{id} || 0;
            push @{ $Result->{MatchedFilters} }, $Filter->{name} || '';

            for my $Action ( @{ $Filter->{actions} || [] } ) {
                my $Description = $Self->_ActionApply(
                    Action => $Action,
                    Result => $Result,
                );
                if ($Description) {
                    push @ActionResult, $Description;
                    push @ActionDetails, {
                        action_type  => $Action->{action_type} || '',
                        target_id    => $Self->_OptionalID( $Action->{target_id} ),
                        action_value => defined $Action->{action_value} ? $Action->{action_value} : '',
                        result       => $Description,
                    };
                }
            }

            if ( $Filter->{stop_after_match} ) {
                $Result->{Stop} = 1;
            }
        }

        push @{ $Result->{Details} }, {
            filter_id   => $Filter->{id} || 0,
            filter_name => $Filter->{name} || '',
            scope_match => 1,
            matched     => $Matched ? 1 : 0,
            conditions  => \@ConditionResult,
            actions     => \@ActionResult,
            action_details => \@ActionDetails,
            stopped     => $Matched && $Filter->{stop_after_match} ? 1 : 0,
        };

        last FILTER if $Result->{Stop};
    }

    return $Result;
}

sub _ConditionValues {
    my ( $Self, %Param ) = @_;

    my $Condition = $Param{Condition} || {};
    my $Message   = $Param{Message} || {};
    my $Context   = $Param{Context} || {};
    my $Customer  = $Param{Customer} || {};
    my $Field     = $Condition->{field_name} || '';
    my $Attachments = ref $Message->{attachments} eq 'ARRAY' ? $Message->{attachments} : [];

    return ( $Message->{from_email} || '' ) if $Field eq 'from_email';
    if ( $Field eq 'from_domain' ) {
        my $Email = $Message->{from_email} || '';
        return ( $Email =~ m{\@([^\s>]+)\z} ? $1 : '' );
    }
    return ( $Message->{from_name} || '' ) if $Field eq 'from_name';
    return ( $Message->{to_raw} || $Message->{to_email} || '' ) if $Field eq 'to';
    return ( $Message->{cc} || '' ) if $Field eq 'cc';
    return ( $Message->{subject} || '' ) if $Field eq 'subject';
    return ( $Message->{body} || '' ) if $Field eq 'body';
    return ( ( $Message->{subject} || '' ) . "\n" . ( $Message->{body} || '' ) ) if $Field eq 'subject_body';
    return map { $_->{Filename} || '' } @{$Attachments} if $Field eq 'attachment_name';
    if ( $Field eq 'attachment_extension' ) {
        return map {
            my $Name = $_->{Filename} || '';
            $Name =~ m{\.([^.]+)\z} ? $1 : '';
        } @{$Attachments};
    }
    return map { $_->{ContentType} || '' } @{$Attachments} if $Field eq 'attachment_mime';
    return ( scalar @{$Attachments} ) if $Field eq 'attachment_count';
    return ( @{$Attachments} ? 'yes' : 'no' ) if $Field eq 'has_attachment';
    return ( $Message->{message_id} || '' ) if $Field eq 'message_id';
    return ( $Message->{in_reply_to} || '' ) if $Field eq 'in_reply_to';
    return ( $Message->{references} || '' ) if $Field eq 'references';
    if ( $Field eq 'custom_header' ) {
        my $Name = lc( $Condition->{field_argument} || '' );
        my $Headers = ref $Message->{headers} eq 'HASH' ? $Message->{headers} : {};
        return ( $Headers->{$Name} || '' );
    }
    return ( $Context->{IMAPAccount}->{name} || '' ) if $Field eq 'mailbox_name';
    return ( $Context->{IMAPAccount}->{email} || '' ) if $Field eq 'mailbox_email';
    return ( $Customer->{customer_user_name} || '' ) if $Field eq 'customer_name';
    return ( $Customer->{customer_name} || '' ) if $Field eq 'customer_company';
    return ( $Context->{ExistingTicketID} ? 'yes' : 'no' ) if $Field eq 'existing_ticket';

    return ('');
}

sub _ConditionMatch {
    my ( $Self, %Param ) = @_;

    my $Condition = $Param{Condition} || {};
    my $Values    = $Param{Values} || [];
    my $Operator  = $Condition->{operator} || 'contains';
    my $Needle    = defined $Condition->{match_value} ? $Condition->{match_value} : '';
    my $Case      = $Condition->{case_sensitive} ? 1 : 0;
    my @Value     = @{$Values};

    if ( $Operator eq 'empty' ) {
        return !grep { defined $_ && $_ ne '' } @Value ? 1 : 0;
    }
    if ( $Operator eq 'not_empty' ) {
        return grep { defined $_ && $_ ne '' } @Value ? 1 : 0;
    }

    @Value = ('') if !@Value;

    my $Negative = $Operator eq 'not_contains' || $Operator eq 'not_equals' ? 1 : 0;
    my $PositiveOperator = $Operator eq 'not_contains' ? 'contains'
        : $Operator eq 'not_equals' ? 'equals'
        : $Operator;

    my @Matches;
    for my $Value (@Value) {
        $Value = '' if !defined $Value;
        push @Matches, $Self->_SingleMatch(
            Value     => $Value,
            Needle    => $Needle,
            Operator  => $PositiveOperator,
            Case      => $Case,
        ) ? 1 : 0;
    }

    if ($Negative) {
        return grep { $_ } @Matches ? 0 : 1;
    }

    return grep { $_ } @Matches ? 1 : 0;
}

sub _SingleMatch {
    my ( $Self, %Param ) = @_;

    my $Value    = defined $Param{Value} ? "$Param{Value}" : '';
    my $Needle   = defined $Param{Needle} ? "$Param{Needle}" : '';
    my $Operator = $Param{Operator} || 'contains';
    my $Case     = $Param{Case} ? 1 : 0;

    if ( $Operator eq 'greater_than' || $Operator eq 'less_than' || $Operator eq 'at_least' || $Operator eq 'at_most' ) {
        return 0 if $Value !~ m{\A-?(?:\d+(?:\.\d+)?|\.\d+)\z};
        return 0 if $Needle !~ m{\A-?(?:\d+(?:\.\d+)?|\.\d+)\z};
        return $Value >  $Needle ? 1 : 0 if $Operator eq 'greater_than';
        return $Value <  $Needle ? 1 : 0 if $Operator eq 'less_than';
        return $Value >= $Needle ? 1 : 0 if $Operator eq 'at_least';
        return $Value <= $Needle ? 1 : 0;
    }

    if ( $Operator eq 'regex' ) {
        return $Self->_RegexMatch( Value => $Value, Pattern => $Needle, Case => $Case );
    }

    if ( $Operator eq 'wildcard' ) {
        my $Pattern = quotemeta($Needle);
        $Pattern =~ s{\\\*}{.*}g;
        $Pattern =~ s{\\\?}{.}g;
        return $Self->_RegexMatch( Value => $Value, Pattern => '\\A' . $Pattern . '\\z', Case => $Case );
    }

    if (!$Case) {
        $Value  = lc $Value;
        $Needle = lc $Needle;
    }

    return $Value eq $Needle ? 1 : 0 if $Operator eq 'equals';
    return index( $Value, $Needle ) >= 0 ? 1 : 0 if $Operator eq 'contains';
    return index( $Value, $Needle ) == 0 ? 1 : 0 if $Operator eq 'starts_with';
    return length($Needle) <= length($Value) && substr( $Value, -length($Needle) ) eq $Needle ? 1 : 0 if $Operator eq 'ends_with';

    return 0;
}

sub _ActionApply {
    my ( $Self, %Param ) = @_;

    my $Action = $Param{Action} || {};
    my $Result = $Param{Result} || {};
    my $Type   = $Action->{action_type} || '';
    my $ID     = $Self->_OptionalID( $Action->{target_id} );
    my $Value  = defined $Action->{action_value} ? $Action->{action_value} : '';

    if ( $Type eq 'queue' )               { $Result->{QueueID} = $ID; return 'queue=' . $ID; }
    if ( $Type eq 'state' )               { $Result->{StateID} = $ID; return 'state=' . $ID; }
    if ( $Type eq 'priority' )            { $Result->{PriorityID} = $ID; return 'priority=' . $ID; }
    if ( $Type eq 'owner' )               { $Result->{OwnerUserID} = $ID; $Result->{OwnerClear} = 0; return 'owner=' . $ID; }
    if ( $Type eq 'owner_clear' )         { $Result->{OwnerUserID} = undef; $Result->{OwnerClear} = 1; return 'owner=clear'; }
    if ( $Type eq 'responsible' )         { $Result->{ResponsibleUserID} = $ID; $Result->{ResponsibleClear} = 0; return 'responsible=' . $ID; }
    if ( $Type eq 'responsible_clear' )   { $Result->{ResponsibleUserID} = undef; $Result->{ResponsibleClear} = 1; return 'responsible=clear'; }
    if ( $Type eq 'service' )             { $Result->{ServiceID} = $ID; $Result->{SLAID} = undef; $Result->{ServiceClear} = 0; return 'service=' . $ID; }
    if ( $Type eq 'sla' )                 { $Result->{SLAID} = $ID; $Result->{ServiceID} = undef; $Result->{ServiceClear} = 0; return 'sla=' . $ID; }
    if ( $Type eq 'service_clear' )       { $Result->{ServiceID} = undef; $Result->{SLAID} = undef; $Result->{ServiceClear} = 1; return 'service=clear'; }
    if ( $Type eq 'customer' )            { $Result->{CustomerID} = $ID; $Result->{CustomerUserID} = undef; $Result->{CustomerClear} = 0; return 'customer=' . $ID; }
    if ( $Type eq 'customer_user' )       { $Result->{CustomerUserID} = $ID; $Result->{CustomerID} = undef; $Result->{CustomerClear} = 0; return 'customer_user=' . $ID; }
    if ( $Type eq 'customer_clear' )      { $Result->{CustomerID} = undef; $Result->{CustomerUserID} = undef; $Result->{CustomerClear} = 1; return 'customer=clear'; }
    if ( $Type eq 'title_set' )           { $Result->{Title} = $Value; $Result->{TitleChanged} = 1; return 'title=set'; }
    if ( $Type eq 'title_prepend' )       { $Result->{Title} = $Value . ( $Result->{Title} || '' ); $Result->{TitleChanged} = 1; return 'title=prepend'; }
    if ( $Type eq 'title_append' )        { $Result->{Title} = ( $Result->{Title} || '' ) . $Value; $Result->{TitleChanged} = 1; return 'title=append'; }
    if ( $Type eq 'dynamic_field' )       { $Result->{DynamicFields}->{$ID} = $Value; return 'dynamic_field_' . $ID . '=set'; }
    if ( $Type eq 'dynamic_field_clear' ) { $Result->{DynamicFields}->{$ID} = undef; return 'dynamic_field_' . $ID . '=clear'; }
    if ( $Type eq 'article_visibility' )  { $Result->{ArticleVisibility} = $Value; return 'visibility=' . $Value; }
    if ( $Type eq 'sender_type' )         { $Result->{SenderType} = $Value; return 'sender_type=' . $Value; }
    if ( $Type eq 'pending_minutes' )     { $Result->{PendingMinutes} = 0 + $Value; return 'pending_minutes=' . $Value; }
    if ( $Type eq 'reject' )              { $Result->{Reject} = 1; return 'reject=1'; }
    if ( $Type eq 'ignore' )              { $Result->{Ignore} = 1; return 'ignore=1'; }

    return '';
}

sub _CustomerContext {
    my ( $Self, %Param ) = @_;

    my $Email = lc( $Self->_Trim( $Param{Email} ) );
    return {} if !$Email;

    my $Row = $Self->{DB}->SelectRow(
        'SELECT cu.id AS customer_user_id, c.id AS customer_id, c.name AS customer_name,
                CONCAT_WS(" ", ua.firstname, ua.lastname) AS customer_user_name,
                ua.login, ua.email
         FROM user_account ua
         INNER JOIN customer_user cu ON cu.user_account_id = ua.id AND cu.active = 1
         INNER JOIN customer c ON c.id = cu.customer_id AND c.active = 1
         WHERE LOWER(ua.email) = ? AND ua.account_type = ? AND ua.is_active = 1
         ORDER BY cu.id ASC LIMIT 1',
        $Email,
        'customer',
    );

    return $Row || {};
}

sub _RegexValidate {
    my ( $Self, %Param ) = @_;

    my $Pattern = defined $Param{Pattern} ? $Param{Pattern} : '';
    return 'empty expression' if $Pattern eq '';
    return 'expression is too long' if length($Pattern) > 500;
    return 'embedded Perl code is not allowed' if $Pattern =~ m{\(\?\??\{};

    my $Error = '';
    eval {
        local $SIG{__WARN__} = sub { die $_[0] };
        qr/$Pattern/;
        1;
    } || do {
        $Error = $@ || 'invalid expression';
        $Error =~ s{\s+at\s+.*\z}{}s;
        $Error =~ s{\A\s+|\s+\z}{}g;
    };

    return $Error;
}

sub _RegexMatch {
    my ( $Self, %Param ) = @_;

    my $Value   = defined $Param{Value} ? $Param{Value} : '';
    my $Pattern = defined $Param{Pattern} ? $Param{Pattern} : '';
    my $Case    = $Param{Case} ? 1 : 0;
    my $Matched = 0;

    local $SIG{ALRM} = sub { die "regex timeout\n" };
    eval {
        alarm 1;
        if ($Case) {
            my $Regex = qr/$Pattern/;
            $Matched = $Value =~ $Regex ? 1 : 0;
        }
        else {
            my $Regex = qr/$Pattern/i;
            $Matched = $Value =~ $Regex ? 1 : 0;
        }
        alarm 0;
        1;
    } || do {
        alarm 0;
        $Matched = 0;
    };

    return $Matched;
}

sub _RequestIndexes {
    my ( $Self, %Param ) = @_;

    my $Request  = $Param{Request} || {};
    my $CountKey = $Param{CountKey} || '';
    my $Prefix   = $Param{Prefix} || '';
    my %Index;

    my $Count = $Self->_Unsigned( $Request->{$CountKey} );
    if ($Count) {
        $Count = 500 if $Count > 500;
        $Index{$_} = 1 for 0 .. $Count - 1;
    }
    for my $Key ( keys %{$Request} ) {
        if ( $Key =~ m{\A\Q$Prefix\E(\d+)\z} ) {
            $Index{$1} = 1;
        }
    }

    return sort { $a <=> $b } keys %Index;
}

sub _ID {
    my ( $Self, $Value ) = @_;
    return if !defined $Value || ref $Value || $Value !~ m{\A\d+\z} || !$Value;
    return 0 + $Value;
}

sub _OptionalID {
    my ( $Self, $Value ) = @_;
    return undef if !defined $Value || $Value eq '' || ref $Value;
    return $Self->_ID($Value);
}

sub _Unsigned {
    my ( $Self, $Value ) = @_;
    return 0 if !defined $Value || ref $Value || $Value !~ m{\A\d+\z};
    return 0 + $Value;
}

sub _Trim {
    my ( $Self, $Value ) = @_;
    return '' if !defined $Value || ref $Value;
    $Value =~ s{\A\s+|\s+\z}{}g;
    return $Value;
}

1;
