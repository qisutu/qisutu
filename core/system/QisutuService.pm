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

package QisutuService;

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

sub ServiceList {
    my ( $Self, %Param ) = @_;

    my @Where;
    my @Bind;

    if ( $Param{ActiveOnly} ) {
        push @Where, 's.active = 1';
    }

    my $SQL = 'SELECT
            s.id,
            s.parent_id,
            parent.full_name AS parent_full_name,
            s.name,
            s.full_name,
            s.description,
            s.active,
            s.sort_order,
            COUNT(DISTINCT sl.id) AS sla_count
         FROM service s
         LEFT JOIN service parent ON parent.id = s.parent_id
         LEFT JOIN sla sl ON sl.service_id = s.id AND sl.active = 1';

    if (@Where) {
        $SQL .= ' WHERE ' . join( ' AND ', @Where );
    }

    $SQL .= ' GROUP BY
            s.id, s.parent_id, parent.full_name, s.name, s.full_name,
            s.description, s.active, s.sort_order
         ORDER BY s.sort_order ASC, s.full_name ASC';

    my $Rows = $Self->{DB}->SelectAll( $SQL, @Bind );

    if ( !$Rows ) {
        $Self->{LastError} = $Self->{DB}->Error() || 'Translate:AdminServiceLoadFailed';
        return [];
    }

    return $Rows;
}

sub ServiceGet {
    my ( $Self, %Param ) = @_;

    my $ServiceID = $Self->_ID( $Param{ServiceID} );
    return if !$ServiceID;

    my $Row = $Self->{DB}->SelectRow(
        'SELECT
            s.id,
            s.parent_id,
            parent.full_name AS parent_full_name,
            s.name,
            s.full_name,
            s.description,
            s.active,
            s.sort_order
         FROM service s
         LEFT JOIN service parent ON parent.id = s.parent_id
         WHERE s.id = ?
         LIMIT 1',
        $ServiceID,
    );

    if ( !$Row ) {
        $Self->{LastError} = 'Translate:AdminServiceNotFound';
        return;
    }

    return $Row;
}

sub ServiceCreate {
    my ( $Self, %Param ) = @_;

    my $Name        = $Self->_Trim( $Param{Name} );
    my $Description = $Self->_Trim( $Param{Description} );
    my $ParentID    = $Self->_OptionalID( $Param{ParentServiceID} );
    my $SortOrder   = $Self->_Unsigned( $Param{SortOrder}, 1000 );
    my $UserID         = $Self->_ID( $Param{ChangedByUserID} ) || 1;

    if ( !$Name ) {
        $Self->{LastError} = 'Translate:AdminServiceNameRequired';
        return;
    }
    if ( length($Name) > 255 ) {
        $Self->{LastError} = 'Translate:AdminServiceNameTooLong';
        return;
    }

    my $FullName = $Self->_ServiceFullName(
        Name     => $Name,
        ParentID => $ParentID,
    );
    return if !$FullName;

    my $Result = $Self->{DB}->Do(
        'INSERT INTO service (
            parent_id, name, full_name, description,
            active, sort_order, created_by_user_id, changed_by_user_id
         ) VALUES (?, ?, ?, ?, 1, ?, ?, ?)',
        $ParentID,
        $Name,
        $FullName,
        $Description || undef,
        $SortOrder,
        $UserID,
        $UserID,
    );

    if ( !$Result ) {
        $Self->{LastError} = $Self->{DB}->Error() || 'Translate:AdminServiceCreateFailed';
        return;
    }

    return $Self->{DB}->LastInsertID('service') || 1;
}

sub ServiceUpdate {
    my ( $Self, %Param ) = @_;

    my $ServiceID  = $Self->_ID( $Param{ServiceID} );
    my $Name       = $Self->_Trim( $Param{Name} );
    my $Description = $Self->_Trim( $Param{Description} );
    my $ParentID   = $Self->_OptionalID( $Param{ParentServiceID} );
    my $Active     = $Param{Active} ? 1 : 0;
    my $SortOrder       = $Self->_Unsigned( $Param{SortOrder}, 1000 );
    my $UserID          = $Self->_ID( $Param{ChangedByUserID} ) || 1;

    if ( !$ServiceID || !$Name ) {
        $Self->{LastError} = 'Translate:AdminServiceNameRequired';
        return;
    }
    if ( length($Name) > 255 ) {
        $Self->{LastError} = 'Translate:AdminServiceNameTooLong';
        return;
    }

    if ( $ParentID && $ParentID == $ServiceID ) {
        $Self->{LastError} = 'Translate:AdminServiceParentInvalid';
        return;
    }

    if ( $ParentID && $Self->_ServiceIsDescendant( ServiceID => $ServiceID, CandidateParentID => $ParentID ) ) {
        $Self->{LastError} = 'Translate:AdminServiceParentInvalid';
        return;
    }

    my $FullName = $Self->_ServiceFullName(
        Name     => $Name,
        ParentID => $ParentID,
    );
    return if !$FullName;

    if ( !$Self->{DB}->BeginWork() ) {
        $Self->{LastError} = $Self->{DB}->Error() || 'Translate:AdminServiceUpdateFailed';
        return;
    }

    my $Result = $Self->{DB}->Do(
        'UPDATE service
         SET parent_id = ?,
             name = ?,
             full_name = ?,
             description = ?,
             active = ?,
             sort_order = ?,
             changed_by_user_id = ?
         WHERE id = ?',
        $ParentID,
        $Name,
        $FullName,
        $Description || undef,
        $Active,
        $SortOrder,
        $UserID,
        $ServiceID,
    );

    if ( !$Result ) {
        $Self->{LastError} = $Self->{DB}->Error() || 'Translate:AdminServiceUpdateFailed';
        $Self->{DB}->Rollback();
        return;
    }

    if ( !$Self->_ServiceDescendantNamesRefresh(
        ServiceID       => $ServiceID,
        ChangedByUserID => $UserID,
    ) ) {
        $Self->{DB}->Rollback();
        return;
    }

    if ( !$Self->{DB}->Commit() ) {
        $Self->{LastError} = $Self->{DB}->Error() || 'Translate:AdminServiceUpdateFailed';
        $Self->{DB}->Rollback();
        return;
    }

    return 1;
}

sub ServiceDeactivate {
    my ( $Self, %Param ) = @_;

    my $ServiceID = $Self->_ID( $Param{ServiceID} );
    my $UserID    = $Self->_ID( $Param{ChangedByUserID} ) || 1;
    return if !$ServiceID;

    my $Result = $Self->{DB}->Do(
        'UPDATE service SET active = 0, changed_by_user_id = ? WHERE id = ?',
        $UserID,
        $ServiceID,
    );

    if ( !$Result ) {
        $Self->{LastError} = $Self->{DB}->Error() || 'Translate:AdminServiceUpdateFailed';
        return;
    }

    return 1;
}

sub SLAList {
    my ( $Self, %Param ) = @_;

    my @Where;
    my @Bind;

    if ( $Param{ActiveOnly} ) {
        push @Where, 'sl.active = 1';
    }
    if ( my $ServiceID = $Self->_ID( $Param{ServiceID} ) ) {
        push @Where, 'sl.service_id = ?';
        push @Bind, $ServiceID;
    }

    my $SQL = 'SELECT
            sl.id,
            sl.name,
            sl.service_id,
            s.full_name AS service_name,
            sl.calendar_id,
            c.name AS calendar_name,
            c.timezone AS calendar_timezone,
            sl.update_mode,
            sl.first_response_minutes,
            sl.update_minutes,
            sl.solution_minutes,
            sl.is_default,
            sl.active,
            sl.sort_order
         FROM sla sl
         INNER JOIN service s ON s.id = sl.service_id
         INNER JOIN calendar c ON c.id = sl.calendar_id';

    if (@Where) {
        $SQL .= ' WHERE ' . join( ' AND ', @Where );
    }

    $SQL .= ' ORDER BY s.sort_order ASC, s.full_name ASC, sl.sort_order ASC, sl.name ASC';

    my $Rows = $Self->{DB}->SelectAll( $SQL, @Bind );

    if ( !$Rows ) {
        $Self->{LastError} = $Self->{DB}->Error() || 'Translate:AdminSLALoadFailed';
        return [];
    }

    return $Rows;
}

sub SLAGet {
    my ( $Self, %Param ) = @_;

    my $SLAID = $Self->_ID( $Param{SLAID} );
    return if !$SLAID;

    my $Row = $Self->{DB}->SelectRow(
        'SELECT
            sl.id,
            sl.name,
            sl.service_id,
            s.full_name AS service_name,
            sl.calendar_id,
            c.name AS calendar_name,
            c.timezone AS calendar_timezone,
            sl.update_mode,
            sl.first_response_minutes,
            sl.update_minutes,
            sl.solution_minutes,
            sl.is_default,
            sl.active,
            sl.sort_order
         FROM sla sl
         INNER JOIN service s ON s.id = sl.service_id
         INNER JOIN calendar c ON c.id = sl.calendar_id
         WHERE sl.id = ?
         LIMIT 1',
        $SLAID,
    );

    if ( !$Row ) {
        $Self->{LastError} = 'Translate:AdminSLANotFound';
        return;
    }

    return $Row;
}

sub SLACreate {
    my ( $Self, %Param ) = @_;

    return $Self->_SLASave( %Param, Create => 1 );
}

sub SLAUpdate {
    my ( $Self, %Param ) = @_;

    return $Self->_SLASave( %Param, Create => 0 );
}

sub SLADeactivate {
    my ( $Self, %Param ) = @_;

    my $SLAID  = $Self->_ID( $Param{SLAID} );
    my $UserID = $Self->_ID( $Param{ChangedByUserID} ) || 1;
    return if !$SLAID;

    my $Result = $Self->{DB}->Do(
        'UPDATE sla SET active = 0, is_default = 0, changed_by_user_id = ? WHERE id = ?',
        $UserID,
        $SLAID,
    );

    if ( !$Result ) {
        $Self->{LastError} = $Self->{DB}->Error() || 'Translate:AdminSLAUpdateFailed';
        return;
    }

    return 1;
}

sub CustomerServiceList {
    my ( $Self, %Param ) = @_;

    my $CustomerID = $Self->_ID( $Param{CustomerID} );
    return [] if !$CustomerID;

    my $Rows = $Self->{DB}->SelectAll(
        'SELECT
            s.id AS service_id,
            s.full_name AS service_name,
            s.active AS service_active,
            cs.sla_id,
            cs.active AS assignment_active,
            sl.name AS sla_name
         FROM service s
         LEFT JOIN customer_service cs
            ON cs.service_id = s.id
            AND cs.customer_id = ?
         LEFT JOIN sla sl ON sl.id = cs.sla_id
         ORDER BY s.sort_order ASC, s.full_name ASC',
        $CustomerID,
    );

    if ( !$Rows ) {
        $Self->{LastError} = $Self->{DB}->Error() || 'Translate:AdminCustomerServiceLoadFailed';
        return [];
    }

    for my $Row ( @{$Rows} ) {
        $Row->{assigned} = $Row->{sla_id} && $Row->{assignment_active} ? 1 : 0;
        $Row->{sla_list} = $Self->SLAList( ServiceID => $Row->{service_id}, ActiveOnly => 1 );
    }

    return $Rows;
}

sub CustomerServiceSave {
    my ( $Self, %Param ) = @_;

    my $CustomerID = $Self->_ID( $Param{CustomerID} );
    my $Assignments = ref $Param{Assignments} eq 'ARRAY' ? $Param{Assignments} : [];
    my $UserID = $Self->_ID( $Param{ChangedByUserID} ) || 1;

    if ( !$CustomerID ) {
        $Self->{LastError} = 'Translate:AdminCustomerServiceCustomerRequired';
        return;
    }

    my $Customer = $Self->{DB}->SelectRow(
        'SELECT id FROM customer WHERE id = ? AND active = 1 LIMIT 1',
        $CustomerID,
    );
    if ( !$Customer ) {
        $Self->{LastError} = 'Translate:AdminCustomerServiceCustomerRequired';
        return;
    }

    if ( !$Self->{DB}->BeginWork() ) {
        $Self->{LastError} = $Self->{DB}->Error() || 'Translate:AdminCustomerServiceSaveFailed';
        return;
    }

    my $OK = $Self->{DB}->Do(
        'UPDATE customer_service SET active = 0, changed_by_user_id = ? WHERE customer_id = ?',
        $UserID,
        $CustomerID,
    );

    if ( !$OK ) {
        $Self->{LastError} = $Self->{DB}->Error() || 'Translate:AdminCustomerServiceSaveFailed';
        $Self->{DB}->Rollback();
        return;
    }

    for my $Assignment ( @{$Assignments} ) {
        next if ref $Assignment ne 'HASH';
        next if !$Assignment->{Active};

        my $ServiceID = $Self->_ID( $Assignment->{ServiceID} );
        my $SLAID     = $Self->_ID( $Assignment->{SLAID} );

        if ( !$ServiceID || !$SLAID ) {
            $Self->{LastError} = 'Translate:AdminCustomerServiceSLARequired';
            $Self->{DB}->Rollback();
            return;
        }

        my $Valid = $Self->{DB}->SelectRow(
            'SELECT sl.id
             FROM sla sl
             INNER JOIN service s ON s.id = sl.service_id
             WHERE sl.id = ?
               AND sl.service_id = ?
               AND sl.active = 1
               AND s.active = 1
             LIMIT 1',
            $SLAID,
            $ServiceID,
        );

        if ( !$Valid ) {
            $Self->{LastError} = 'Translate:AdminCustomerServiceSLAInvalid';
            $Self->{DB}->Rollback();
            return;
        }

        $OK = $Self->{DB}->Do(
            'INSERT INTO customer_service (
                customer_id, service_id, sla_id, active,
                created_by_user_id, changed_by_user_id
             ) VALUES (?, ?, ?, 1, ?, ?)
             ON DUPLICATE KEY UPDATE
                sla_id = VALUES(sla_id),
                active = 1,
                changed_by_user_id = VALUES(changed_by_user_id),
                changed_at = CURRENT_TIMESTAMP',
            $CustomerID,
            $ServiceID,
            $SLAID,
            $UserID,
            $UserID,
        );

        if ( !$OK ) {
            $Self->{LastError} = $Self->{DB}->Error() || 'Translate:AdminCustomerServiceSaveFailed';
            $Self->{DB}->Rollback();
            return;
        }
    }

    if ( !$Self->{DB}->Commit() ) {
        $Self->{LastError} = $Self->{DB}->Error() || 'Translate:AdminCustomerServiceSaveFailed';
        $Self->{DB}->Rollback();
        return;
    }

    return 1;
}

sub AvailableServiceList {
    my ( $Self, %Param ) = @_;

    my $CustomerID = $Self->_ID( $Param{CustomerID} );
    return [] if !$CustomerID;

    my $Rows = $Self->{DB}->SelectAll(
        'SELECT
            s.id,
            s.full_name,
            sl.id AS sla_id,
            sl.name AS sla_name,
            sl.calendar_id,
            c.name AS calendar_name,
            sl.update_mode,
            sl.first_response_minutes,
            sl.update_minutes,
            sl.solution_minutes,
            ? AS assignment_source
         FROM customer_service cs
         INNER JOIN service s ON s.id = cs.service_id AND s.active = 1
         INNER JOIN sla sl ON sl.id = cs.sla_id AND sl.active = 1 AND sl.service_id = s.id
         INNER JOIN calendar c ON c.id = sl.calendar_id AND c.active = 1
         WHERE cs.customer_id = ? AND cs.active = 1
         ORDER BY s.sort_order ASC, s.full_name ASC',
        'customer',
        $CustomerID,
    );

    if ( !$Rows ) {
        $Self->{LastError} = $Self->{DB}->Error() || 'Translate:TicketServiceLoadFailed';
        return [];
    }

    return $Rows;
}

sub AvailableServiceTreeList {
    my ( $Self, %Param ) = @_;

    my $CustomerID = $Self->_ID( $Param{CustomerID} );
    return [] if !$CustomerID;

    my $AvailableRows = $Self->AvailableServiceList( CustomerID => $CustomerID );
    return [] if $Self->Error();

    my $AllRows = $Self->ServiceList();
    return [] if $Self->Error();

    my %AllByID = map { ( $_->{id} || 0 ) => { %{$_} } } @{$AllRows};
    my %SelectableByID = map { ( $_->{id} || 0 ) => { %{$_} } } @{$AvailableRows};

    my $IncludeServiceID = $Self->_ID( $Param{IncludeServiceID} );
    if ( $IncludeServiceID && !$SelectableByID{$IncludeServiceID} && $AllByID{$IncludeServiceID} ) {
        $SelectableByID{$IncludeServiceID} = {
            %{ $AllByID{$IncludeServiceID} },
            assignment_source => 'existing_ticket',
        };
    }

    my %Include;
    for my $ServiceID ( keys %SelectableByID ) {
        my $CurrentID = $ServiceID;
        my %Visited;

        while ( $CurrentID && !$Visited{$CurrentID}++ ) {
            my $Row = $AllByID{$CurrentID};
            last if !$Row;
            $Include{$CurrentID} = 1;
            $CurrentID = $Row->{parent_id} || 0;
        }
    }

    my @Rows;
    for my $ServiceID ( keys %Include ) {
        my $Base = $AllByID{$ServiceID};
        next if !$Base;

        my $Selectable = $SelectableByID{$ServiceID};
        push @Rows, {
            %{$Base},
            %{ $Selectable || {} },
            selectable => $Selectable ? 1 : 0,
        };
    }

    return $Self->_ServiceTreeOrder( Rows => \@Rows );
}

sub ServiceTreeList {
    my ( $Self, %Param ) = @_;

    my $Rows = $Self->ServiceList( ActiveOnly => $Param{ActiveOnly} ? 1 : 0 );
    return [] if $Self->Error();

    my @TreeRows = map {
        {
            %{$_},
            selectable => 1,
        }
    } @{$Rows};

    return $Self->_ServiceTreeOrder( Rows => \@TreeRows );
}

sub SLAResolve {
    my ( $Self, %Param ) = @_;

    my $CustomerID = $Self->_ID( $Param{CustomerID} );
    my $ServiceID  = $Self->_ID( $Param{ServiceID} );
    return if !$CustomerID || !$ServiceID;

    my $Rows = $Self->AvailableServiceList( CustomerID => $CustomerID );
    for my $Row ( @{$Rows} ) {
        next if ( $Row->{id} || 0 ) != $ServiceID;
        return {
            service_id            => $Row->{id},
            service_name          => $Row->{full_name},
            sla_id                => $Row->{sla_id},
            sla_name              => $Row->{sla_name},
            calendar_id           => $Row->{calendar_id},
            calendar_name         => $Row->{calendar_name},
            update_mode           => $Row->{update_mode} || 'customer_response',
            first_response_minutes => $Row->{first_response_minutes} || 0,
            update_minutes         => $Row->{update_minutes} || 0,
            solution_minutes       => $Row->{solution_minutes} || 0,
            assignment_source      => $Row->{assignment_source} || 'customer',
        };
    }

    $Self->{LastError} = 'Translate:TicketServiceNotAvailable';
    return;
}

sub CustomerIDFromCustomerUser {
    my ( $Self, %Param ) = @_;

    my $CustomerUserID = $Self->_ID( $Param{CustomerUserID} );
    return if !$CustomerUserID;

    my $Row = $Self->{DB}->SelectRow(
        'SELECT customer_id FROM customer_user WHERE id = ? AND active = 1 LIMIT 1',
        $CustomerUserID,
    );

    return $Row ? $Row->{customer_id} : undef;
}

sub TicketStateList {
    my ($Self) = @_;

    my $Rows = $Self->{DB}->SelectAll(
        'SELECT id, name, state_type, sla_pause, active, sort_order
         FROM ticket_state
         ORDER BY sort_order ASC, name ASC'
    );

    if ( !$Rows ) {
        $Self->{LastError} = $Self->{DB}->Error() || 'Translate:AdminTicketStateLoadFailed';
        return [];
    }

    return $Rows;
}

sub TicketStateGet {
    my ( $Self, %Param ) = @_;

    my $StateID = $Self->_ID( $Param{StateID} );
    return if !$StateID;

    my $Row = $Self->{DB}->SelectRow(
        'SELECT id, name, state_type, sla_pause, active, sort_order
         FROM ticket_state WHERE id = ? LIMIT 1',
        $StateID,
    );

    if ( !$Row ) {
        $Self->{LastError} = 'Translate:AdminTicketStateNotFound';
        return;
    }

    return $Row;
}

sub TicketStateCreate {
    my ( $Self, %Param ) = @_;

    my $Name      = $Self->_Trim( $Param{Name} );
    my $StateType = $Self->_StateType( $Param{StateType} );
    my $SLAPause  = $Param{SLAPause} ? 1 : 0;
    my $SortOrder = $Self->_Unsigned( $Param{SortOrder}, 1000 );
    my $UserID    = $Self->_ID( $Param{ChangedByUserID} ) || 1;

    if ( !$Name || !$StateType ) {
        $Self->{LastError} = 'Translate:AdminTicketStateRequired';
        return;
    }

    my $Result = $Self->{DB}->Do(
        'INSERT INTO ticket_state (
            name, state_type, sla_pause, active, sort_order,
            created_by_user_id, changed_by_user_id
         ) VALUES (?, ?, ?, 1, ?, ?, ?)',
        $Name,
        $StateType,
        $SLAPause,
        $SortOrder,
        $UserID,
        $UserID,
    );

    if ( !$Result ) {
        $Self->{LastError} = $Self->{DB}->Error() || 'Translate:AdminTicketStateCreateFailed';
        return;
    }

    return 1;
}

sub TicketStateUpdate {
    my ( $Self, %Param ) = @_;

    my $StateID  = $Self->_ID( $Param{StateID} );
    my $Name      = $Self->_Trim( $Param{Name} );
    my $StateType = $Self->_StateType( $Param{StateType} );
    my $SLAPause  = $Param{SLAPause} ? 1 : 0;
    my $Active    = $Param{Active} ? 1 : 0;
    my $SortOrder = $Self->_Unsigned( $Param{SortOrder}, 1000 );
    my $UserID    = $Self->_ID( $Param{ChangedByUserID} ) || 1;

    if ( !$StateID || !$Name || !$StateType ) {
        $Self->{LastError} = 'Translate:AdminTicketStateRequired';
        return;
    }

    my $Result = $Self->{DB}->Do(
        'UPDATE ticket_state
         SET name = ?, state_type = ?, sla_pause = ?, active = ?,
             sort_order = ?, changed_by_user_id = ?
         WHERE id = ?',
        $Name,
        $StateType,
        $SLAPause,
        $Active,
        $SortOrder,
        $UserID,
        $StateID,
    );

    if ( !$Result ) {
        $Self->{LastError} = $Self->{DB}->Error() || 'Translate:AdminTicketStateUpdateFailed';
        return;
    }

    return 1;
}

sub Error {
    my ($Self) = @_;
    return $Self->{LastError};
}

sub _SLASave {
    my ( $Self, %Param ) = @_;

    my $Create      = $Param{Create} ? 1 : 0;
    my $SLAID       = $Self->_ID( $Param{SLAID} );
    my $Name        = $Self->_Trim( $Param{Name} );
    my $ServiceID   = $Self->_ID( $Param{ServiceID} );
    my $CalendarID  = $Self->_ID( $Param{CalendarID} );
    my $UpdateMode  = $Self->_UpdateMode( $Param{UpdateMode} );
    my $First       = $Self->_Unsigned( $Param{FirstResponseMinutes}, 0 );
    my $Update      = $Self->_Unsigned( $Param{UpdateMinutes}, 0 );
    my $Solution    = $Self->_Unsigned( $Param{SolutionMinutes}, 0 );
    my $IsDefault   = $Param{IsDefault} ? 1 : 0;
    my $Active      = $Create ? 1 : ( $Param{Active} ? 1 : 0 );
    my $SortOrder   = $Self->_Unsigned( $Param{SortOrder}, 1000 );
    my $UserID      = $Self->_ID( $Param{ChangedByUserID} ) || 1;

    if ( !$Create && !$SLAID ) {
        $Self->{LastError} = 'Translate:AdminSLANotFound';
        return;
    }

    if ( !$Name || !$ServiceID || !$CalendarID || !$UpdateMode ) {
        $Self->{LastError} = 'Translate:AdminSLARequired';
        return;
    }

    if ( length($Name) > 255 ) {
        $Self->{LastError} = 'Translate:AdminSLANameTooLong';
        return;
    }

    if ( !$Create ) {
        my $Existing = $Self->{DB}->SelectRow(
            'SELECT id, service_id FROM sla WHERE id = ? LIMIT 1',
            $SLAID,
        );
        if ( !$Existing ) {
            $Self->{LastError} = 'Translate:AdminSLANotFound';
            return;
        }

        if ( ( $Existing->{service_id} || 0 ) != $ServiceID ) {
            my $Assignment = $Self->{DB}->SelectRow(
                'SELECT COUNT(*) AS count FROM customer_service WHERE sla_id = ?',
                $SLAID,
            );
            if ( $Assignment && ( $Assignment->{count} || 0 ) > 0 ) {
                $Self->{LastError} = 'Translate:AdminSLAServiceChangeAssigned';
                return;
            }
        }
    }

    my $Service = $Self->{DB}->SelectRow(
        'SELECT id FROM service WHERE id = ? AND active = 1 LIMIT 1',
        $ServiceID,
    );
    my $Calendar = $Self->{DB}->SelectRow(
        'SELECT id FROM calendar WHERE id = ? AND active = 1 LIMIT 1',
        $CalendarID,
    );
    if ( !$Service || !$Calendar ) {
        $Self->{LastError} = 'Translate:AdminSLARequired';
        return;
    }

    if ( !$Self->{DB}->BeginWork() ) {
        $Self->{LastError} = $Self->{DB}->Error() || 'Translate:AdminSLASaveFailed';
        return;
    }

    my $Result;
    if ($Create) {
        $Result = $Self->{DB}->Do(
            'INSERT INTO sla (
                name, service_id, calendar_id, update_mode,
                first_response_minutes, update_minutes, solution_minutes,
                is_default, active, sort_order,
                created_by_user_id, changed_by_user_id
             ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, 1, ?, ?, ?)',
            $Name,
            $ServiceID,
            $CalendarID,
            $UpdateMode,
            $First,
            $Update,
            $Solution,
            $IsDefault,
            $SortOrder,
            $UserID,
            $UserID,
        );
        $SLAID = $Self->{DB}->LastInsertID('sla') if $Result;
    }
    else {
        $Result = $Self->{DB}->Do(
            'UPDATE sla
             SET name = ?, service_id = ?, calendar_id = ?, update_mode = ?,
                 first_response_minutes = ?, update_minutes = ?, solution_minutes = ?,
                 is_default = ?, active = ?, sort_order = ?, changed_by_user_id = ?
             WHERE id = ?',
            $Name,
            $ServiceID,
            $CalendarID,
            $UpdateMode,
            $First,
            $Update,
            $Solution,
            $IsDefault,
            $Active,
            $SortOrder,
            $UserID,
            $SLAID,
        );
    }

    if ( !$Result ) {
        $Self->{LastError} = $Self->{DB}->Error() || ( $Create ? 'Translate:AdminSLACreateFailed' : 'Translate:AdminSLAUpdateFailed' );
        $Self->{DB}->Rollback();
        return;
    }

    if ($IsDefault) {
        $Result = $Self->{DB}->Do(
            'UPDATE sla
             SET is_default = 0, changed_by_user_id = ?
             WHERE service_id = ? AND id <> ?',
            $UserID,
            $ServiceID,
            $SLAID,
        );
        if ( !$Result ) {
            $Self->{LastError} = $Self->{DB}->Error() || 'Translate:AdminSLASaveFailed';
            $Self->{DB}->Rollback();
            return;
        }
    }

    if ( !$Self->{DB}->Commit() ) {
        $Self->{LastError} = $Self->{DB}->Error() || 'Translate:AdminSLASaveFailed';
        $Self->{DB}->Rollback();
        return;
    }

    return $SLAID || 1;
}

sub _ServiceTreeOrder {
    my ( $Self, %Param ) = @_;

    my $Rows = $Param{Rows} || [];
    my %ByID = map { ( $_->{id} || 0 ) => { %{$_} } } @{$Rows};
    my %Children;

    for my $Row ( values %ByID ) {
        my $ParentID = $Row->{parent_id} || 0;
        $ParentID = 0 if !$ByID{$ParentID};
        $Row->{tree_parent_id} = $ParentID;
        push @{ $Children{$ParentID} }, $Row;
    }

    my $SortRows = sub {
        my ($List) = @_;
        return [
            sort {
                ( ( $a->{sort_order} || 0 ) <=> ( $b->{sort_order} || 0 ) )
                    || lc( $a->{name} || $a->{full_name} || '' ) cmp lc( $b->{name} || $b->{full_name} || '' )
                    || ( ( $a->{id} || 0 ) <=> ( $b->{id} || 0 ) )
            } @{$List || []}
        ];
    };

    my @Ordered;
    my %Visited;
    my $Walk;
    $Walk = sub {
        my ( $ParentID, $Depth ) = @_;
        for my $Row ( @{ $SortRows->( $Children{$ParentID} ) } ) {
            my $ID = $Row->{id} || 0;
            next if !$ID || $Visited{$ID}++;

            my $ChildRows = $Children{$ID} || [];
            push @Ordered, {
                %{$Row},
                parent_id   => $Row->{tree_parent_id} || 0,
                depth       => $Depth,
                has_children => @{$ChildRows} ? 1 : 0,
            };
            $Walk->( $ID, $Depth + 1 );
        }
    };

    $Walk->( 0, 0 );

    # Protect the UI from malformed cyclic service data. Any unvisited row is
    # still shown as a top-level entry instead of disappearing completely.
    for my $Row ( @{ $SortRows->( [ values %ByID ] ) } ) {
        my $ID = $Row->{id} || 0;
        next if !$ID || $Visited{$ID}++;
        push @Ordered, {
            %{$Row},
            parent_id    => 0,
            depth        => 0,
            has_children => 0,
        };
    }

    return \@Ordered;
}

sub _ServiceFullName {
    my ( $Self, %Param ) = @_;

    my $Name     = $Param{Name} || '';
    my $ParentID = $Param{ParentID} || 0;
    return $Name if !$ParentID;

    my $Parent = $Self->{DB}->SelectRow(
        'SELECT id, full_name FROM service WHERE id = ? AND active = 1 LIMIT 1',
        $ParentID,
    );

    if ( !$Parent ) {
        $Self->{LastError} = 'Translate:AdminServiceParentInvalid';
        return;
    }

    my $FullName = ( $Parent->{full_name} || '' ) . '::' . $Name;
    if ( length($FullName) > 750 ) {
        $Self->{LastError} = 'Translate:AdminServiceFullNameTooLong';
        return;
    }

    return $FullName;
}

sub _ServiceIsDescendant {
    my ( $Self, %Param ) = @_;

    my $ServiceID       = $Param{ServiceID} || 0;
    my $CandidateParent = $Param{CandidateParentID} || 0;
    my %Seen;

    while ($CandidateParent) {
        return 1 if $CandidateParent == $ServiceID;
        last if $Seen{$CandidateParent}++;

        my $Row = $Self->{DB}->SelectRow(
            'SELECT parent_id FROM service WHERE id = ? LIMIT 1',
            $CandidateParent,
        );
        last if !$Row;
        $CandidateParent = $Row->{parent_id} || 0;
    }

    return 0;
}

sub _ServiceDescendantNamesRefresh {
    my ( $Self, %Param ) = @_;

    my $ServiceID = $Param{ServiceID} || 0;
    my $UserID    = $Param{ChangedByUserID} || 1;
    my $Children = $Self->{DB}->SelectAll(
        'SELECT id, name FROM service WHERE parent_id = ? ORDER BY id ASC',
        $ServiceID,
    ) || [];

    my $Parent = $Self->{DB}->SelectRow(
        'SELECT full_name FROM service WHERE id = ? LIMIT 1',
        $ServiceID,
    );
    return 1 if !$Parent;

    for my $Child ( @{$Children} ) {
        my $FullName = ( $Parent->{full_name} || '' ) . '::' . ( $Child->{name} || '' );
        if ( length($FullName) > 750 ) {
            $Self->{LastError} = 'Translate:AdminServiceFullNameTooLong';
            return;
        }
        my $Result = $Self->{DB}->Do(
            'UPDATE service SET full_name = ?, changed_by_user_id = ? WHERE id = ?',
            $FullName,
            $UserID,
            $Child->{id},
        );
        if ( !$Result ) {
            $Self->{LastError} = $Self->{DB}->Error() || 'Translate:AdminServiceUpdateFailed';
            return;
        }
        return if !$Self->_ServiceDescendantNamesRefresh(
            ServiceID       => $Child->{id},
            ChangedByUserID => $UserID,
        );
    }

    return 1;
}

sub _UpdateMode {
    my ( $Self, $Value ) = @_;
    $Value = $Self->_Trim($Value);
    return $Value if $Value eq 'customer_response' || $Value eq 'regular';
    return;
}

sub _StateType {
    my ( $Self, $Value ) = @_;
    $Value = $Self->_Trim($Value);
    return $Value if $Value eq 'new' || $Value eq 'open' || $Value eq 'pending' || $Value eq 'closed';
    return;
}

sub _ID {
    my ( $Self, $Value ) = @_;
    return if !defined $Value || $Value !~ m{\A\d+\z} || !$Value;
    return 0 + $Value;
}

sub _OptionalID {
    my ( $Self, $Value ) = @_;
    return undef if !defined $Value || $Value eq '' || $Value eq '0';
    return $Self->_ID($Value);
}

sub _Unsigned {
    my ( $Self, $Value, $Default ) = @_;
    $Default = 0 if !defined $Default;
    return $Default if !defined $Value || $Value !~ m{\A\d+\z};
    return 0 + $Value;
}

sub _Trim {
    my ( $Self, $Value ) = @_;
    $Value = '' if !defined $Value;
    $Value =~ s{\A\s+|\s+\z}{}g;
    return $Value;
}

1;
