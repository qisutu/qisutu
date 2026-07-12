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

package QisutuChecklist;

use strict;
use warnings;
use utf8;

sub new {
    my ( $Class, %Param ) = @_;

    my $Self = {
        Config    => $Param{Config},
        DB        => $Param{DB},
        LastError => '',
    };

    bless $Self, $Class;
    return $Self;
}

sub Error {
    my ($Self) = @_;
    return $Self->{LastError};
}

sub TemplateList {
    my ( $Self, %Param ) = @_;

    my @Where;
    my @Bind;
    if ( !$Param{IncludeInactive} ) {
        push @Where, 'ct.active = 1';
    }

    my $Rows = $Self->{DB}->SelectAll(
        'SELECT
            ct.id,
            ct.name,
            ct.description,
            ct.usage_mode,
            ct.sort_order,
            ct.active,
            ct.created_at,
            ct.changed_at,
            COUNT(DISTINCT cti.id) AS item_count,
            COUNT(DISTINCT CASE WHEN cti.is_required = 1 AND cti.active = 1 THEN cti.id END) AS required_item_count,
            GROUP_CONCAT(DISTINCT tq.full_name ORDER BY tq.sort_order, tq.full_name SEPARATOR ", ") AS queue_names,
            GROUP_CONCAT(DISTINCT s.full_name ORDER BY s.sort_order, s.full_name SEPARATOR ", ") AS service_names,
            GROUP_CONCAT(DISTINCT c.name ORDER BY c.name SEPARATOR ", ") AS customer_names
         FROM checklist_template ct
         LEFT JOIN checklist_template_item cti
            ON cti.template_id = ct.id
           AND cti.active = 1
         LEFT JOIN checklist_template_queue ctq ON ctq.template_id = ct.id
         LEFT JOIN ticket_queue tq ON tq.id = ctq.queue_id
         LEFT JOIN checklist_template_service cts ON cts.template_id = ct.id
         LEFT JOIN service s ON s.id = cts.service_id
         LEFT JOIN checklist_template_customer ctc ON ctc.template_id = ct.id
         LEFT JOIN customer c ON c.id = ctc.customer_id
         ' . ( @Where ? 'WHERE ' . join( ' AND ', @Where ) : '' ) . '
         GROUP BY ct.id
         ORDER BY ct.sort_order ASC, ct.name ASC, ct.id ASC',
        @Bind,
    );

    if ( !$Rows ) {
        $Self->{LastError} = $Self->{DB}->Error() || 'Checklist templates could not be loaded';
        return [];
    }

    return $Rows;
}

sub TemplateGet {
    my ( $Self, %Param ) = @_;
    my $TemplateID = $Param{TemplateID} || 0;

    return if $TemplateID !~ m{\A\d+\z} || !$TemplateID;

    my $Template = $Self->{DB}->SelectRow(
        'SELECT * FROM checklist_template WHERE id = ? LIMIT 1',
        $TemplateID,
    );

    if ( !$Template ) {
        $Self->{LastError} = $Self->{DB}->Error() || 'Checklist template not found';
        return;
    }

    $Template->{items} = $Self->{DB}->SelectAll(
        'SELECT *
         FROM checklist_template_item
         WHERE template_id = ?
           AND active = 1
         ORDER BY sort_order ASC, id ASC',
        $TemplateID,
    ) || [];

    return $Template;
}

sub TemplateCreate {
    my ( $Self, %Param ) = @_;

    my $Name = $Self->_Trim( $Param{Name} );
    if ( !$Name ) {
        $Self->{LastError} = 'Translate:AdminChecklistNameRequired';
        return;
    }

    my $UsageMode = $Self->_UsageMode( $Param{UsageMode} );
    my $UserID    = $Param{ChangedByUserID} || 1;
    my $Result = $Self->{DB}->Do(
        'INSERT INTO checklist_template (
            name, description, usage_mode, sort_order, active,
            created_by_user_id, changed_by_user_id, created_at, changed_at
         ) VALUES (?, ?, ?, ?, 1, ?, ?, NOW(), NOW())',
        $Name,
        $Self->_Trim( $Param{Description} ),
        $UsageMode,
        $Self->_SortOrder( $Param{SortOrder} ),
        $UserID,
        $UserID,
    );

    if ( !$Result ) {
        $Self->{LastError} = $Self->{DB}->Error() || 'Checklist template could not be created';
        return;
    }

    my $TemplateID = $Self->{DB}->LastInsertID('checklist_template');
    return $TemplateID;
}

sub TemplateUpdate {
    my ( $Self, %Param ) = @_;

    my $TemplateID = $Param{TemplateID} || 0;
    my $Name       = $Self->_Trim( $Param{Name} );
    if ( $TemplateID !~ m{\A\d+\z} || !$TemplateID || !$Name ) {
        $Self->{LastError} = !$Name ? 'Translate:AdminChecklistNameRequired' : 'Checklist template is invalid';
        return;
    }

    my $Result = $Self->{DB}->Do(
        'UPDATE checklist_template
         SET name = ?, description = ?, usage_mode = ?, sort_order = ?, active = ?,
             changed_by_user_id = ?, changed_at = NOW()
         WHERE id = ?',
        $Name,
        $Self->_Trim( $Param{Description} ),
        $Self->_UsageMode( $Param{UsageMode} ),
        $Self->_SortOrder( $Param{SortOrder} ),
        $Param{Active} ? 1 : 0,
        $Param{ChangedByUserID} || 1,
        $TemplateID,
    );

    if ( !$Result ) {
        $Self->{LastError} = $Self->{DB}->Error() || 'Checklist template could not be updated';
        return;
    }

    return 1;
}

sub TemplateDeactivate {
    my ( $Self, %Param ) = @_;
    my $TemplateID = $Param{TemplateID} || 0;

    return if $TemplateID !~ m{\A\d+\z} || !$TemplateID;

    my $Result = $Self->{DB}->Do(
        'UPDATE checklist_template
         SET active = 0, changed_by_user_id = ?, changed_at = NOW()
         WHERE id = ?',
        $Param{ChangedByUserID} || 1,
        $TemplateID,
    );

    if ( !$Result ) {
        $Self->{LastError} = $Self->{DB}->Error() || 'Checklist template could not be deactivated';
        return;
    }

    return 1;
}

sub TemplateItemsSet {
    my ( $Self, %Param ) = @_;

    my $TemplateID = $Param{TemplateID} || 0;
    my $Items      = ref $Param{Items} eq 'ARRAY' ? $Param{Items} : [];
    my $UserID     = $Param{ChangedByUserID} || 1;

    if ( $TemplateID !~ m{\A\d+\z} || !$TemplateID ) {
        $Self->{LastError} = 'Checklist template is invalid';
        return;
    }

    my %Keep;
    my $ValidCount = 0;
    for my $Item ( @{$Items} ) {
        my $Name = $Self->_Trim( $Item->{Name} );
        my $Description = $Self->_Trim( $Item->{Description} );

        # A completely empty helper row is ignored. Once either field is used,
        # both the short title and the task description are mandatory.
        next if !$Name && !$Description;
        if ( !$Name ) {
            $Self->{LastError} = 'Translate:AdminChecklistItemNameRequired';
            return;
        }
        if ( !$Description ) {
            $Self->{LastError} = 'Translate:AdminChecklistItemDescriptionRequired';
            return;
        }
        $ValidCount++;

        my $ItemID = $Item->{ItemID} || 0;
        my $Result;
        if ( $ItemID =~ m{\A\d+\z} && $ItemID ) {
            $Result = $Self->{DB}->Do(
                'UPDATE checklist_template_item
                 SET name = ?, description = ?, is_required = ?, sort_order = ?, active = 1,
                     changed_by_user_id = ?, changed_at = NOW()
                 WHERE id = ? AND template_id = ?',
                $Name,
                $Description,
                $Item->{IsRequired} ? 1 : 0,
                $Self->_SortOrder( $Item->{SortOrder} ),
                $UserID,
                $ItemID,
                $TemplateID,
            );
            $Keep{$ItemID} = 1 if $Result;
        }
        else {
            $Result = $Self->{DB}->Do(
                'INSERT INTO checklist_template_item (
                    template_id, name, description, is_required, sort_order, active,
                    created_by_user_id, changed_by_user_id, created_at, changed_at
                 ) VALUES (?, ?, ?, ?, ?, 1, ?, ?, NOW(), NOW())',
                $TemplateID,
                $Name,
                $Description,
                $Item->{IsRequired} ? 1 : 0,
                $Self->_SortOrder( $Item->{SortOrder} ),
                $UserID,
                $UserID,
            );
            my $NewID = $Result ? $Self->{DB}->LastInsertID('checklist_template_item') : 0;
            $Keep{$NewID} = 1 if $NewID;
        }

        if ( !$Result ) {
            $Self->{LastError} = $Self->{DB}->Error() || 'Checklist item could not be saved';
            return;
        }
    }

    if ( !$ValidCount ) {
        $Self->{LastError} = 'Translate:AdminChecklistItemRequired';
        return;
    }

    my @KeepIDs = grep { $_ } keys %Keep;
    my $SQL = 'UPDATE checklist_template_item SET active = 0, changed_by_user_id = ?, changed_at = NOW() WHERE template_id = ?';
    my @Bind = ( $UserID, $TemplateID );
    if (@KeepIDs) {
        $SQL .= ' AND id NOT IN (' . join( ',', ('?') x @KeepIDs ) . ')';
        push @Bind, @KeepIDs;
    }

    if ( !$Self->{DB}->Do( $SQL, @Bind ) ) {
        $Self->{LastError} = $Self->{DB}->Error() || 'Old checklist items could not be deactivated';
        return;
    }

    return 1;
}

sub QueueList {
    my ( $Self, %Param ) = @_;
    my $Rows = $Self->{DB}->SelectAll(
        'SELECT id, name, full_name, sort_order, active
         FROM ticket_queue
         ' . ( $Param{IncludeInactive} ? '' : 'WHERE active = 1' ) . '
         ORDER BY sort_order ASC, full_name ASC, id ASC'
    );
    return $Rows || [];
}

sub ServiceList {
    my ( $Self, %Param ) = @_;
    my $Rows = $Self->{DB}->SelectAll(
        'SELECT id, name, full_name, parent_id, sort_order, active
         FROM service
         ' . ( $Param{IncludeInactive} ? '' : 'WHERE active = 1' ) . '
         ORDER BY full_name ASC, sort_order ASC, id ASC'
    );
    return $Rows || [];
}

sub CustomerList {
    my ( $Self, %Param ) = @_;
    my $Rows = $Self->{DB}->SelectAll(
        'SELECT id, customer_number, name, active
         FROM customer
         ' . ( $Param{IncludeInactive} ? '' : 'WHERE active = 1' ) . '
         ORDER BY name ASC, customer_number ASC, id ASC'
    );
    return $Rows || [];
}

sub TemplateQueueIDs {
    my ( $Self, %Param ) = @_;
    return $Self->_AssignmentIDs( Table => 'checklist_template_queue', Column => 'queue_id', TemplateID => $Param{TemplateID} );
}

sub TemplateServiceIDs {
    my ( $Self, %Param ) = @_;
    return $Self->_AssignmentIDs( Table => 'checklist_template_service', Column => 'service_id', TemplateID => $Param{TemplateID} );
}

sub TemplateCustomerIDs {
    my ( $Self, %Param ) = @_;
    return $Self->_AssignmentIDs( Table => 'checklist_template_customer', Column => 'customer_id', TemplateID => $Param{TemplateID} );
}

sub QueueTemplateIDs {
    my ( $Self, %Param ) = @_;
    return $Self->_ReverseAssignmentIDs( Table => 'checklist_template_queue', Column => 'queue_id', ID => $Param{QueueID} );
}

sub ServiceTemplateIDs {
    my ( $Self, %Param ) = @_;
    return $Self->_ReverseAssignmentIDs( Table => 'checklist_template_service', Column => 'service_id', ID => $Param{ServiceID} );
}

sub CustomerTemplateIDs {
    my ( $Self, %Param ) = @_;
    return $Self->_ReverseAssignmentIDs( Table => 'checklist_template_customer', Column => 'customer_id', ID => $Param{CustomerID} );
}

sub TemplateQueueSet {
    my ( $Self, %Param ) = @_;
    return $Self->_AssignmentSet(
        Table           => 'checklist_template_queue',
        Column          => 'queue_id',
        TemplateID      => $Param{TemplateID},
        IDs             => $Param{QueueIDs},
        ChangedByUserID => $Param{ChangedByUserID},
    );
}

sub TemplateServiceSet {
    my ( $Self, %Param ) = @_;
    return $Self->_AssignmentSet(
        Table           => 'checklist_template_service',
        Column          => 'service_id',
        TemplateID      => $Param{TemplateID},
        IDs             => $Param{ServiceIDs},
        ChangedByUserID => $Param{ChangedByUserID},
    );
}

sub TemplateCustomerSet {
    my ( $Self, %Param ) = @_;
    return $Self->_AssignmentSet(
        Table           => 'checklist_template_customer',
        Column          => 'customer_id',
        TemplateID      => $Param{TemplateID},
        IDs             => $Param{CustomerIDs},
        ChangedByUserID => $Param{ChangedByUserID},
    );
}

sub QueueTemplateSet {
    my ( $Self, %Param ) = @_;
    return $Self->_ReverseAssignmentSet(
        Table           => 'checklist_template_queue',
        Column          => 'queue_id',
        ID              => $Param{QueueID},
        TemplateIDs     => $Param{TemplateIDs},
        ChangedByUserID => $Param{ChangedByUserID},
    );
}

sub ServiceTemplateSet {
    my ( $Self, %Param ) = @_;
    return $Self->_ReverseAssignmentSet(
        Table           => 'checklist_template_service',
        Column          => 'service_id',
        ID              => $Param{ServiceID},
        TemplateIDs     => $Param{TemplateIDs},
        ChangedByUserID => $Param{ChangedByUserID},
    );
}

sub CustomerTemplateSet {
    my ( $Self, %Param ) = @_;
    return $Self->_ReverseAssignmentSet(
        Table           => 'checklist_template_customer',
        Column          => 'customer_id',
        ID              => $Param{CustomerID},
        TemplateIDs     => $Param{TemplateIDs},
        ChangedByUserID => $Param{ChangedByUserID},
    );
}

sub MatchingTemplates {
    my ( $Self, %Param ) = @_;

    my $QueueID    = $Param{QueueID} || 0;
    my $CustomerID = $Param{CustomerID} || 0;
    my $ServiceID  = $Param{ServiceID} || 0;
    my $Usage      = $Param{Usage} || 'manual';

    my @UsageModes = $Usage eq 'automatic' ? ( 'automatic', 'both' ) : ( 'manual', 'both' );
    my $ServiceCondition;
    my @ServiceBind;
    if ($ServiceID) {
        $ServiceCondition = '(
            NOT EXISTS (SELECT 1 FROM checklist_template_service x WHERE x.template_id = ct.id)
            OR EXISTS (SELECT 1 FROM checklist_template_service x WHERE x.template_id = ct.id AND x.service_id = ?)
        )';
        @ServiceBind = ($ServiceID);
    }
    elsif ( $Usage eq 'automatic' ) {
        # At ticket creation a service can still be empty. In that case queue
        # and customer assignments are sufficient for automatic templates.
        $ServiceCondition = '1 = 1';
    }
    else {
        # A manually selected service-specific checklist is only offered when
        # the ticket actually has a matching service.
        $ServiceCondition = 'NOT EXISTS (SELECT 1 FROM checklist_template_service x WHERE x.template_id = ct.id)';
    }

    my $Rows = $Self->{DB}->SelectAll(
        'SELECT ct.*
         FROM checklist_template ct
         WHERE ct.active = 1
           AND ct.usage_mode IN (?, ?)
           AND (
                NOT EXISTS (SELECT 1 FROM checklist_template_queue x WHERE x.template_id = ct.id)
                OR EXISTS (SELECT 1 FROM checklist_template_queue x WHERE x.template_id = ct.id AND x.queue_id = ?)
           )
           AND (
                NOT EXISTS (SELECT 1 FROM checklist_template_customer x WHERE x.template_id = ct.id)
                OR EXISTS (SELECT 1 FROM checklist_template_customer x WHERE x.template_id = ct.id AND x.customer_id = ?)
           )
           AND ' . $ServiceCondition . '
         ORDER BY ct.sort_order ASC, ct.name ASC, ct.id ASC',
        @UsageModes,
        $QueueID,
        $CustomerID,
        @ServiceBind,
    );

    if ( !defined $Rows ) {
        $Self->{LastError} = $Self->{DB}->Error() || 'Matching checklist templates could not be loaded';
        return;
    }

    return $Rows;
}

sub TicketAutoCreate {
    my ( $Self, %Param ) = @_;

    my $TicketID = $Param{TicketID} || 0;
    return if $TicketID !~ m{\A\d+\z} || !$TicketID;

    my $Ticket = $Self->{DB}->SelectRow(
        'SELECT id, queue_id, customer_id, service_id FROM ticket WHERE id = ? LIMIT 1',
        $TicketID,
    );
    if ( !$Ticket ) {
        $Self->{LastError} = $Self->{DB}->Error() || 'Ticket could not be loaded for automatic checklists';
        return;
    }

    my $Templates = $Self->MatchingTemplates(
        QueueID    => $Ticket->{queue_id},
        CustomerID => $Ticket->{customer_id},
        ServiceID  => $Ticket->{service_id},
        Usage      => 'automatic',
    );
    return if !defined $Templates;

    for my $Template ( @{$Templates} ) {
        if ( !$Self->TicketChecklistAdd(
            TicketID        => $TicketID,
            TemplateID      => $Template->{id},
            ChangedByUserID => $Param{ChangedByUserID} || 1,
            Source          => 'automatic',
        ) ) {
            return;
        }
    }

    return 1;
}

sub TicketChecklistAdd {
    my ( $Self, %Param ) = @_;

    my $TicketID   = $Param{TicketID} || 0;
    my $TemplateID = $Param{TemplateID} || 0;
    my $UserID     = $Param{ChangedByUserID} || 1;

    if ( $TicketID !~ m{\A\d+\z} || !$TicketID || $TemplateID !~ m{\A\d+\z} || !$TemplateID ) {
        $Self->{LastError} = 'Checklist ticket or template is invalid';
        return;
    }

    my $Existing = $Self->{DB}->SelectRow(
        'SELECT id FROM ticket_checklist WHERE ticket_id = ? AND template_id = ? AND removed_at IS NULL LIMIT 1',
        $TicketID,
        $TemplateID,
    );
    return $Existing->{id} if $Existing && $Existing->{id};

    my $Template = $Self->TemplateGet( TemplateID => $TemplateID );
    return if !$Template || !$Template->{active};

    my $OwnTransaction = $Self->_TransactionStart();
    return if !defined $OwnTransaction;

    my $Result = $Self->{DB}->Do(
        'INSERT INTO ticket_checklist (
            ticket_id, template_id, name, description, source, sort_order,
            created_by_user_id, changed_by_user_id, created_at, changed_at
         ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, NOW(), NOW())',
        $TicketID,
        $TemplateID,
        $Template->{name},
        $Template->{description},
        $Param{Source} || 'manual',
        $Template->{sort_order} || 1000,
        $UserID,
        $UserID,
    );
    if ( !$Result ) {
        $Self->{LastError} = $Self->{DB}->Error() || 'Ticket checklist could not be created';
        $Self->_TransactionRollback($OwnTransaction);
        return;
    }

    my $TicketChecklistID = $Self->{DB}->LastInsertID('ticket_checklist');
    for my $Item ( @{ $Template->{items} || [] } ) {
        if ( !$Self->{DB}->Do(
            'INSERT INTO ticket_checklist_item (
                ticket_checklist_id, template_item_id, name, description, is_required, sort_order, is_done,
                created_by_user_id, changed_by_user_id, created_at, changed_at
             ) VALUES (?, ?, ?, ?, ?, ?, 0, ?, ?, NOW(), NOW())',
            $TicketChecklistID,
            $Item->{id},
            $Item->{name},
            $Item->{description},
            $Item->{is_required} ? 1 : 0,
            $Item->{sort_order} || 1000,
            $UserID,
            $UserID,
        ) ) {
            $Self->{LastError} = $Self->{DB}->Error() || 'Ticket checklist item could not be created';
            $Self->_TransactionRollback($OwnTransaction);
            return;
        }
    }

    if ( !$Self->_Audit(
        TicketID          => $TicketID,
        TicketChecklistID => $TicketChecklistID,
        Action            => 'checklist_added',
        Details           => $Template->{name},
        UserID            => $UserID,
    ) ) {
        $Self->{LastError} = $Self->{DB}->Error() || 'Checklist audit entry could not be created';
        $Self->_TransactionRollback($OwnTransaction);
        return;
    }

    if ( !$Self->_TransactionCommit($OwnTransaction) ) {
        return;
    }

    return $TicketChecklistID;
}

sub TicketChecklistRemove {
    my ( $Self, %Param ) = @_;

    my $TicketID          = $Param{TicketID} || 0;
    my $TicketChecklistID = $Param{TicketChecklistID} || 0;
    my $UserID            = $Param{ChangedByUserID} || 1;

    my $Checklist = $Self->{DB}->SelectRow(
        'SELECT id, name FROM ticket_checklist WHERE id = ? AND ticket_id = ? AND removed_at IS NULL LIMIT 1',
        $TicketChecklistID,
        $TicketID,
    );
    if ( !$Checklist ) {
        $Self->{LastError} = 'Ticket checklist not found';
        return;
    }

    my $OwnTransaction = $Self->_TransactionStart();
    return if !defined $OwnTransaction;

    if ( !$Self->{DB}->Do(
        'UPDATE ticket_checklist
         SET removed_at = NOW(), removed_by_user_id = ?, changed_by_user_id = ?, changed_at = NOW()
         WHERE id = ? AND ticket_id = ?',
        $UserID,
        $UserID,
        $TicketChecklistID,
        $TicketID,
    ) ) {
        $Self->{LastError} = $Self->{DB}->Error() || 'Ticket checklist could not be removed';
        $Self->_TransactionRollback($OwnTransaction);
        return;
    }

    if ( !$Self->_Audit(
        TicketID          => $TicketID,
        TicketChecklistID => $TicketChecklistID,
        Action            => 'checklist_removed',
        Details           => $Checklist->{name},
        UserID            => $UserID,
    ) ) {
        $Self->{LastError} = $Self->{DB}->Error() || 'Checklist audit entry could not be created';
        $Self->_TransactionRollback($OwnTransaction);
        return;
    }

    return if !$Self->_TransactionCommit($OwnTransaction);
    return 1;
}

sub TicketItemToggle {
    my ( $Self, %Param ) = @_;

    my $TicketID = $Param{TicketID} || 0;
    my $ItemID   = $Param{ItemID} || 0;
    my $Done     = $Param{Done} ? 1 : 0;
    my $UserID   = $Param{ChangedByUserID} || 1;

    my $Item = $Self->{DB}->SelectRow(
        'SELECT tci.id, tci.name, tci.is_done, tc.id AS ticket_checklist_id
         FROM ticket_checklist_item tci
         INNER JOIN ticket_checklist tc ON tc.id = tci.ticket_checklist_id
         WHERE tci.id = ?
           AND tc.ticket_id = ?
           AND tc.removed_at IS NULL
         LIMIT 1',
        $ItemID,
        $TicketID,
    );
    if ( !$Item ) {
        $Self->{LastError} = 'Checklist item not found';
        return;
    }
    return 1 if ( $Item->{is_done} ? 1 : 0 ) == $Done;

    my $OwnTransaction = $Self->_TransactionStart();
    return if !defined $OwnTransaction;

    my $Result = $Self->{DB}->Do(
        'UPDATE ticket_checklist_item
         SET is_done = ?,
             completed_by_user_id = CASE WHEN ? = 1 THEN ? ELSE NULL END,
             completed_at = CASE WHEN ? = 1 THEN NOW() ELSE NULL END,
             changed_by_user_id = ?, changed_at = NOW()
         WHERE id = ?',
        $Done,
        $Done,
        $UserID,
        $Done,
        $UserID,
        $ItemID,
    );
    if ( !$Result ) {
        $Self->{LastError} = $Self->{DB}->Error() || 'Checklist item could not be updated';
        $Self->_TransactionRollback($OwnTransaction);
        return;
    }

    if ( !$Self->_Audit(
        TicketID          => $TicketID,
        TicketChecklistID => $Item->{ticket_checklist_id},
        TicketItemID      => $ItemID,
        Action            => $Done ? 'item_completed' : 'item_reopened',
        Details           => $Item->{name},
        UserID            => $UserID,
    ) ) {
        $Self->{LastError} = $Self->{DB}->Error() || 'Checklist audit entry could not be created';
        $Self->_TransactionRollback($OwnTransaction);
        return;
    }

    if ($Done) {
        my $Open = $Self->{DB}->SelectRow(
            'SELECT COUNT(*) AS open_count FROM ticket_checklist_item WHERE ticket_checklist_id = ? AND is_done = 0',
            $Item->{ticket_checklist_id},
        );
        if ( $Open && !( $Open->{open_count} || 0 ) ) {
            if ( !$Self->_Audit(
                TicketID          => $TicketID,
                TicketChecklistID => $Item->{ticket_checklist_id},
                Action            => 'checklist_completed',
                Details           => '',
                UserID            => $UserID,
            ) ) {
                $Self->{LastError} = $Self->{DB}->Error() || 'Checklist audit entry could not be created';
                $Self->_TransactionRollback($OwnTransaction);
                return;
            }
        }
    }

    return if !$Self->_TransactionCommit($OwnTransaction);
    return 1;
}

sub TicketChecklistList {
    my ( $Self, %Param ) = @_;
    my $TicketID = $Param{TicketID} || 0;

    my $Rows = $Self->{DB}->SelectAll(
        'SELECT
            tc.id,
            tc.ticket_id,
            tc.template_id,
            tc.name,
            tc.description,
            tc.source,
            tc.sort_order,
            tc.created_at,
            COUNT(tci.id) AS item_count,
            SUM(CASE WHEN tci.is_done = 1 THEN 1 ELSE 0 END) AS done_count,
            SUM(CASE WHEN tci.is_required = 1 AND tci.is_done = 0 THEN 1 ELSE 0 END) AS open_required_count
         FROM ticket_checklist tc
         LEFT JOIN ticket_checklist_item tci ON tci.ticket_checklist_id = tc.id
         WHERE tc.ticket_id = ?
           AND tc.removed_at IS NULL
         GROUP BY tc.id
         ORDER BY tc.sort_order ASC, tc.created_at ASC, tc.id ASC',
        $TicketID,
    );

    if ( !$Rows ) {
        $Self->{LastError} = $Self->{DB}->Error() || 'Ticket checklists could not be loaded';
        return [];
    }

    for my $Checklist ( @{$Rows} ) {
        $Checklist->{items} = $Self->{DB}->SelectAll(
            'SELECT
                tci.*,
                ua.firstname AS completed_by_firstname,
                ua.lastname AS completed_by_lastname,
                ua.login AS completed_by_login
             FROM ticket_checklist_item tci
             LEFT JOIN user_account ua ON ua.id = tci.completed_by_user_id
             WHERE tci.ticket_checklist_id = ?
             ORDER BY tci.sort_order ASC, tci.id ASC',
            $Checklist->{id},
        ) || [];

        $Checklist->{item_count}          = 0 + ( $Checklist->{item_count} || 0 );
        $Checklist->{done_count}          = 0 + ( $Checklist->{done_count} || 0 );
        $Checklist->{open_required_count} = 0 + ( $Checklist->{open_required_count} || 0 );
        $Checklist->{progress_percent}    = $Checklist->{item_count}
            ? int( ( $Checklist->{done_count} * 100 ) / $Checklist->{item_count} )
            : 100;
    }

    return $Rows;
}

sub TicketManualTemplateList {
    my ( $Self, %Param ) = @_;

    my $TicketID = $Param{TicketID} || 0;
    my $Ticket = $Self->{DB}->SelectRow(
        'SELECT id, queue_id, customer_id, service_id FROM ticket WHERE id = ? LIMIT 1',
        $TicketID,
    );
    return [] if !$Ticket;

    my $Rows = $Self->MatchingTemplates(
        QueueID    => $Ticket->{queue_id},
        CustomerID => $Ticket->{customer_id},
        ServiceID  => $Ticket->{service_id},
        Usage      => 'manual',
    );

    my $Existing = $Self->{DB}->SelectAll(
        'SELECT template_id FROM ticket_checklist WHERE ticket_id = ? AND removed_at IS NULL AND template_id IS NOT NULL',
        $TicketID,
    ) || [];
    my %Existing = map { ( $_->{template_id} || 0 ) => 1 } @{$Existing};

    return [ grep { !$Existing{ $_->{id} || 0 } } @{$Rows || []} ];
}

sub TicketCanClose {
    my ( $Self, %Param ) = @_;

    my $TicketID = $Param{TicketID} || 0;
    my $Rows = $Self->{DB}->SelectAll(
        'SELECT tc.name AS checklist_name, tci.name AS item_name
         FROM ticket_checklist_item tci
         INNER JOIN ticket_checklist tc ON tc.id = tci.ticket_checklist_id
         WHERE tc.ticket_id = ?
           AND tc.removed_at IS NULL
           AND tci.is_required = 1
           AND tci.is_done = 0
         ORDER BY tc.sort_order ASC, tc.id ASC, tci.sort_order ASC, tci.id ASC',
        $TicketID,
    );

    if ( !$Rows ) {
        if ( $Self->{DB}->Error() ) {
            $Self->{LastError} = $Self->{DB}->Error() || 'Open checklist items could not be checked';
            return;
        }
        return { Allowed => 1, OpenItems => [] };
    }

    if ( @{$Rows} ) {
        my $Details = join( '; ', map {
            ( $_->{checklist_name} || '' ) . ': ' . ( $_->{item_name} || '' )
        } @{$Rows} );
        $Self->_Audit(
            TicketID => $TicketID,
            Action   => 'close_blocked',
            Details  => $Details,
            UserID   => $Param{ChangedByUserID} || 1,
        );
        return {
            Allowed   => 0,
            OpenItems => $Rows,
        };
    }

    return { Allowed => 1, OpenItems => [] };
}

sub TicketConditionSQL {
    my ( $Self, %Param ) = @_;
    my $Condition = $Param{Condition} || {};
    my @Where;
    my @Bind;

    my $TemplateIDs = ref $Condition->{TemplateIDs} eq 'ARRAY' ? $Condition->{TemplateIDs} : [];
    if (@{$TemplateIDs}) {
        push @Where,
            'EXISTS (SELECT 1 FROM ticket_checklist ccl WHERE ccl.ticket_id = t.id AND ccl.removed_at IS NULL AND ccl.template_id IN ('
            . join( ',', ('?') x @{$TemplateIDs} ) . '))';
        push @Bind, @{$TemplateIDs};
    }

    if ( $Condition->{HasOpen} ) {
        push @Where,
            'EXISTS (SELECT 1 FROM ticket_checklist ccl INNER JOIN ticket_checklist_item cli ON cli.ticket_checklist_id = ccl.id WHERE ccl.ticket_id = t.id AND ccl.removed_at IS NULL AND cli.is_done = 0)';
    }
    if ( $Condition->{HasCompleted} ) {
        push @Where,
            'EXISTS (SELECT 1 FROM ticket_checklist ccl WHERE ccl.ticket_id = t.id AND ccl.removed_at IS NULL AND NOT EXISTS (SELECT 1 FROM ticket_checklist_item cli WHERE cli.ticket_checklist_id = ccl.id AND cli.is_done = 0))';
    }
    if ( $Condition->{OpenRequired} ) {
        push @Where,
            'EXISTS (SELECT 1 FROM ticket_checklist ccl INNER JOIN ticket_checklist_item cli ON cli.ticket_checklist_id = ccl.id WHERE ccl.ticket_id = t.id AND ccl.removed_at IS NULL AND cli.is_required = 1 AND cli.is_done = 0)';
    }
    if ( $Condition->{AllRequiredDone} ) {
        push @Where,
            'EXISTS (SELECT 1 FROM ticket_checklist ccl WHERE ccl.ticket_id = t.id AND ccl.removed_at IS NULL) AND NOT EXISTS (SELECT 1 FROM ticket_checklist ccl INNER JOIN ticket_checklist_item cli ON cli.ticket_checklist_id = ccl.id WHERE ccl.ticket_id = t.id AND ccl.removed_at IS NULL AND cli.is_required = 1 AND cli.is_done = 0)';
    }

    return { Where => \@Where, Bind => \@Bind };
}

sub TicketTemplateItemSet {
    my ( $Self, %Param ) = @_;
    my $TicketID      = $Param{TicketID} || 0;
    my $TemplateID    = $Param{TemplateID} || 0;
    my $TemplateItemID = $Param{TemplateItemID} || 0;
    my $Done          = $Param{Done} ? 1 : 0;
    my $UserID        = $Param{ChangedByUserID} || 1;

    my $Rows = $Self->{DB}->SelectAll(
        'SELECT tci.id
         FROM ticket_checklist_item tci
         INNER JOIN ticket_checklist tc ON tc.id = tci.ticket_checklist_id
         WHERE tc.ticket_id = ?
           AND tc.removed_at IS NULL
           AND tc.template_id = ?
           AND tci.template_item_id = ?',
        $TicketID,
        $TemplateID,
        $TemplateItemID,
    ) || [];

    for my $Row ( @{$Rows} ) {
        return if !$Self->TicketItemToggle(
            TicketID        => $TicketID,
            ItemID          => $Row->{id},
            Done            => $Done,
            ChangedByUserID => $UserID,
        );
    }

    return 1;
}

sub _AssignmentIDs {
    my ( $Self, %Param ) = @_;
    my $TemplateID = $Param{TemplateID} || 0;
    my $Rows = $Self->{DB}->SelectAll(
        'SELECT ' . $Param{Column} . ' AS id FROM ' . $Param{Table} . ' WHERE template_id = ? ORDER BY ' . $Param{Column},
        $TemplateID,
    ) || [];
    return [ map { 0 + ( $_->{id} || 0 ) } @{$Rows} ];
}

sub _ReverseAssignmentIDs {
    my ( $Self, %Param ) = @_;
    my $Rows = $Self->{DB}->SelectAll(
        'SELECT template_id AS id FROM ' . $Param{Table} . ' WHERE ' . $Param{Column} . ' = ? ORDER BY template_id',
        $Param{ID} || 0,
    ) || [];
    return [ map { 0 + ( $_->{id} || 0 ) } @{$Rows} ];
}

sub _AssignmentSet {
    my ( $Self, %Param ) = @_;
    my $TemplateID = $Param{TemplateID} || 0;
    my $IDs        = ref $Param{IDs} eq 'ARRAY' ? $Param{IDs} : [];
    my $UserID     = $Param{ChangedByUserID} || 1;

    return if !$Self->{DB}->Do( 'DELETE FROM ' . $Param{Table} . ' WHERE template_id = ?', $TemplateID );
    for my $ID ( @{$IDs} ) {
        next if $ID !~ m{\A\d+\z} || !$ID;
        if ( !$Self->{DB}->Do(
            'INSERT INTO ' . $Param{Table} . ' (template_id, ' . $Param{Column} . ', created_by_user_id, created_at) VALUES (?, ?, ?, NOW())',
            $TemplateID,
            $ID,
            $UserID,
        ) ) {
            $Self->{LastError} = $Self->{DB}->Error() || 'Checklist assignment could not be saved';
            return;
        }
    }
    return 1;
}

sub _ReverseAssignmentSet {
    my ( $Self, %Param ) = @_;
    my $ID          = $Param{ID} || 0;
    my $TemplateIDs = ref $Param{TemplateIDs} eq 'ARRAY' ? $Param{TemplateIDs} : [];
    my $UserID      = $Param{ChangedByUserID} || 1;

    return if !$Self->{DB}->Do( 'DELETE FROM ' . $Param{Table} . ' WHERE ' . $Param{Column} . ' = ?', $ID );
    for my $TemplateID ( @{$TemplateIDs} ) {
        next if $TemplateID !~ m{\A\d+\z} || !$TemplateID;
        if ( !$Self->{DB}->Do(
            'INSERT INTO ' . $Param{Table} . ' (template_id, ' . $Param{Column} . ', created_by_user_id, created_at) VALUES (?, ?, ?, NOW())',
            $TemplateID,
            $ID,
            $UserID,
        ) ) {
            $Self->{LastError} = $Self->{DB}->Error() || 'Checklist assignment could not be saved';
            return;
        }
    }
    return 1;
}

sub _TransactionStart {
    my ($Self) = @_;
    my $Handle = eval { $Self->{DB}->Handle() };
    if ( !$Handle ) {
        $Self->{LastError} = $Self->{DB}->Error() || 'Database connection failed';
        return;
    }
    return 0 if !$Handle->{AutoCommit};
    if ( !$Self->{DB}->BeginWork() ) {
        $Self->{LastError} = $Self->{DB}->Error() || 'Database transaction could not be started';
        return;
    }
    return 1;
}

sub _TransactionCommit {
    my ( $Self, $OwnTransaction ) = @_;
    return 1 if !$OwnTransaction;
    if ( !$Self->{DB}->Commit() ) {
        $Self->{LastError} = $Self->{DB}->Error() || 'Database transaction could not be committed';
        eval { $Self->{DB}->Rollback(); 1; };
        return;
    }
    return 1;
}

sub _TransactionRollback {
    my ( $Self, $OwnTransaction ) = @_;
    return 1 if !$OwnTransaction;
    eval { $Self->{DB}->Rollback(); 1; };
    return 1;
}

sub _Audit {
    my ( $Self, %Param ) = @_;
    my $Result = $Self->{DB}->Do(
        'INSERT INTO ticket_checklist_audit (
            ticket_id, ticket_checklist_id, ticket_checklist_item_id, action, details,
            created_by_user_id, created_at
         ) VALUES (?, ?, ?, ?, ?, ?, NOW())',
        $Param{TicketID},
        $Param{TicketChecklistID} || undef,
        $Param{TicketItemID} || undef,
        $Param{Action} || '',
        $Param{Details} || '',
        $Param{UserID} || 1,
    );
    return $Result ? 1 : 0;
}

sub _UsageMode {
    my ( $Self, $Value ) = @_;
    return $Value if $Value && $Value =~ m{\A(?:automatic|manual|both)\z};
    return 'manual';
}

sub _SortOrder {
    my ( $Self, $Value ) = @_;
    return 1000 if !defined $Value || $Value !~ m{\A\d+\z} || $Value < 1;
    return $Value;
}

sub _Trim {
    my ( $Self, $Value ) = @_;
    $Value = '' if !defined $Value;
    $Value =~ s{\A\s+|\s+\z}{}g;
    return $Value;
}

1;
