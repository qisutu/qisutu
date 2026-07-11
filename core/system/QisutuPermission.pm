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

package QisutuPermission;

use strict;
use warnings;
use utf8;

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

sub UserPermissionCheck {
    my ( $Self, %Param ) = @_;

    my $UserID     = $Param{UserID}     || 0;
    my $Permission = $Param{Permission} || '';

    return 1 if !$Permission;
    return if $UserID !~ m{\A\d+\z} || !$UserID;

    my $Row = $Self->{DB}->SelectRow(
        'SELECT 1 AS allowed
         FROM user_group_member ugm
         INNER JOIN user_group_permission ugp
             ON ugp.user_group_id = ugm.user_group_id
         INNER JOIN user_group ug
             ON ug.id = ugm.user_group_id
         WHERE ugm.user_account_id = ?
             AND ugm.active = 1
             AND ug.active = 1
             AND ugp.permission_key = ?
             AND ugp.active = 1
         LIMIT 1',
        $UserID,
        $Permission,
    );

    return $Row ? 1 : 0;
}

sub UserIsAdmin {
    my ( $Self, %Param ) = @_;

    return $Self->UserPermissionCheck(
        UserID     => $Param{UserID},
        Permission => 'admin.view',
    );
}

sub _PermissionAction {
    my ( $Self, %Param ) = @_;

    my $Permission = $Param{Permission} || '';

    return 'create' if $Permission =~ m{\.create\z};
    return 'change' if $Permission =~ m{\.(?:edit|change|update|delete|manage)\z};
    return 'view';
}

sub QueueIDList {
    my ( $Self, %Param ) = @_;

    my $UserID     = $Param{UserID}     || 0;
    my $Permission = $Param{Permission} || 'ticket.view';
    my $Action     = $Self->_PermissionAction( Permission => $Permission );

    return [] if $UserID !~ m{\A\d+\z} || !$UserID;

    my $Rows = $Self->{DB}->SelectAll(
        'SELECT DISTINCT tqg.queue_id
         FROM user_group_member ugm
         INNER JOIN user_group ug
             ON ug.id = ugm.user_group_id
         INNER JOIN ticket_queue_group tqg
             ON tqg.user_group_id = ugm.user_group_id
         INNER JOIN ticket_queue tq
             ON tq.id = tqg.queue_id
         WHERE ugm.user_account_id = ?
             AND ugm.active = 1
             AND ug.active = 1
             AND tqg.active = 1
             AND tq.active = 1
             AND tqg.permission_key IN (?, "ticket.full")
             AND (
                ugm.permission_full = 1
                OR (? = "view" AND (ugm.permission_read = 1 OR ugm.permission_overview = 1))
                OR (? = "create" AND ugm.permission_create = 1)
                OR (? = "change" AND ugm.permission_change = 1)
             )
         ORDER BY tq.sort_order ASC, tq.full_name ASC, tq.id ASC',
        $UserID,
        $Permission,
        $Action,
        $Action,
        $Action,
    );

    if ( !$Rows ) {
        $Self->{LastError} = $Self->{DB}->Error() || 'Queue permission list could not be loaded';
        return [];
    }

    my @QueueIDs;

    for my $Row ( @{$Rows} ) {
        next if !$Row->{queue_id};
        push @QueueIDs, $Row->{queue_id};
    }

    return \@QueueIDs;
}

sub CustomerQueueRuleHash {
    my ( $Self, %Param ) = @_;

    my $UserID     = $Param{UserID}     || 0;
    my $Permission = $Param{Permission} || 'ticket.view';
    my $Action     = $Self->_PermissionAction( Permission => $Permission );

    return {} if $UserID !~ m{\A\d+\z} || !$UserID;

    my $Rows = $Self->{DB}->SelectAll(
        'SELECT
            tqg.queue_id,
            MAX(CASE WHEN ugm.permission_full = 1 OR ugm.permission_overview = 1 THEN 1 ELSE 0 END) AS organization_access
         FROM user_group_member ugm
         INNER JOIN user_group ug
             ON ug.id = ugm.user_group_id
         INNER JOIN ticket_queue_group tqg
             ON tqg.user_group_id = ugm.user_group_id
         INNER JOIN ticket_queue tq
             ON tq.id = tqg.queue_id
         WHERE ugm.user_account_id = ?
             AND ugm.active = 1
             AND ug.active = 1
             AND tqg.active = 1
             AND tq.active = 1
             AND tqg.permission_key IN (?, "ticket.full")
             AND (
                ugm.permission_full = 1
                OR (? = "view" AND (ugm.permission_read = 1 OR ugm.permission_overview = 1))
                OR (? = "create" AND ugm.permission_create = 1)
                OR (? = "change" AND ugm.permission_change = 1)
             )
         GROUP BY tqg.queue_id',
        $UserID,
        $Permission,
        $Action,
        $Action,
        $Action,
    );

    if ( !$Rows ) {
        $Self->{LastError} = $Self->{DB}->Error() || 'Customer queue permission list could not be loaded';
        return {};
    }

    my %Rule;

    for my $Row ( @{$Rows} ) {
        next if !$Row->{queue_id};
        $Rule{ $Row->{queue_id} } = $Row->{organization_access} ? 'organization' : 'own';
    }

    return \%Rule;
}

sub QueueAccessCheck {
    my ( $Self, %Param ) = @_;

    my $UserID     = $Param{UserID}     || 0;
    my $QueueID    = $Param{QueueID}    || 0;
    my $Permission = $Param{Permission} || 'ticket.view';
    my $Action     = $Self->_PermissionAction( Permission => $Permission );

    return if $UserID !~ m{\A\d+\z} || !$UserID;
    return if $QueueID !~ m{\A\d+\z} || !$QueueID;

    my $Row = $Self->{DB}->SelectRow(
        'SELECT 1 AS allowed
         FROM user_group_member ugm
         INNER JOIN user_group ug
             ON ug.id = ugm.user_group_id
         INNER JOIN ticket_queue_group tqg
             ON tqg.user_group_id = ugm.user_group_id
         WHERE ugm.user_account_id = ?
             AND tqg.queue_id = ?
             AND ugm.active = 1
             AND ug.active = 1
             AND tqg.active = 1
             AND tqg.permission_key IN (?, "ticket.full")
             AND (
                ugm.permission_full = 1
                OR (? = "view" AND (ugm.permission_read = 1 OR ugm.permission_overview = 1))
                OR (? = "create" AND ugm.permission_create = 1)
                OR (? = "change" AND ugm.permission_change = 1)
             )
         LIMIT 1',
        $UserID,
        $QueueID,
        $Permission,
        $Action,
        $Action,
        $Action,
    );

    return $Row ? 1 : 0;
}

sub Error {
    my ($Self) = @_;

    return $Self->{LastError};
}

1;
