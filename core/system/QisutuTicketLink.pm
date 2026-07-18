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

package QisutuTicketLink;

use strict;
use warnings;
use utf8;
use POSIX qw(strftime);
use QisutuPermission;
use QisutuTicket;

sub new {
    my ( $Class, %Param ) = @_;

    my $Self = {
        Config     => $Param{Config},
        DB         => $Param{DB},
        LastError  => '',
        Permission => QisutuPermission->new(
            Config => $Param{Config},
            DB     => $Param{DB},
        ),
    };

    $Self->{TicketObject} = QisutuTicket->new(
        Config     => $Param{Config},
        DB         => $Param{DB},
        Permission => $Self->{Permission},
    );

    bless $Self, $Class;

    return $Self;
}

sub Error {
    my ($Self) = @_;

    return $Self->{LastError} || '';
}

sub TicketLookup {
    my ( $Self, %Param ) = @_;

    my $User            = $Param{User} || {};
    my $Query           = $Param{Query} || '';
    my $CurrentTicketID = $Param{CurrentTicketID} || 0;
    my $RequireEdit     = exists $Param{RequireEdit} ? ( $Param{RequireEdit} ? 1 : 0 ) : 1;

    $Query =~ s{\A\s+|\s+\z}{}g;
    return { items => [] } if length($Query) < 2;

    my $Like = '%' . $Query . '%';
    my $Rows = $Self->{DB}->SelectAll(
        'SELECT
            t.id,
            t.ticket_number,
            t.title,
            t.queue_id,
            t.customer_id,
            t.customer_user_id,
            q.full_name AS queue_name,
            s.name AS state_name
         FROM ticket t
         INNER JOIN ticket_queue q ON q.id = t.queue_id
         INNER JOIN ticket_state s ON s.id = t.state_id
         WHERE t.id <> ?
           AND (t.ticket_number LIKE ? OR t.title LIKE ?)
         ORDER BY
           CASE WHEN t.ticket_number = ? THEN 0 ELSE 1 END,
           t.changed_at DESC,
           t.id DESC
         LIMIT 100',
        $CurrentTicketID || 0,
        $Like,
        $Like,
        $Query,
    ) || [];

    my @Items;
    for my $Row ( @{$Rows} ) {
        next if $Param{ExcludeMerged} && ( $Row->{state_name} || '' ) eq 'merged';
        next if !$Self->_TicketPermissionCheck(
            Ticket     => $Row,
            User       => $User,
            Permission => $RequireEdit ? 'ticket.edit' : 'ticket.view',
        );

        push @Items, {
            id          => 0 + ( $Row->{id} || 0 ),
            label       => ( $Row->{ticket_number} || '' ) . ' — ' . ( $Row->{title} || '' ),
            description => join( ' · ', grep { defined $_ && $_ ne '' } ( $Row->{queue_name}, $Row->{state_name} ) ),
        };

        last if @Items >= 20;
    }

    return { items => \@Items };
}

sub LinkCreate {
    my ( $Self, %Param ) = @_;

    $Self->{LastError} = '';

    my $SourceTicketID = $Param{SourceTicketID} || 0;
    my $TargetTicketID = $Param{TargetTicketID} || 0;
    my $User           = $Param{User} || {};
    my $UserID         = $User->{user_account_id} || 0;

    return if !$Self->_NumericIDsValid( $SourceTicketID, $TargetTicketID, $UserID );
    if ( $SourceTicketID == $TargetTicketID ) {
        $Self->{LastError} = 'Translate:TicketLinkSelfDenied';
        return;
    }

    my $Source = $Self->_TicketForChange( TicketID => $SourceTicketID, User => $User );
    return if !$Source;
    my $Target = $Self->_TicketForChange( TicketID => $TargetTicketID, User => $User );
    return if !$Target;

    my ( $FirstID, $SecondID ) = $SourceTicketID < $TargetTicketID
        ? ( $SourceTicketID, $TargetTicketID )
        : ( $TargetTicketID, $SourceTicketID );

    return if !$Self->_TransactionStart( Source => 'related' );

    my $LockedTickets = $Self->{DB}->SelectAll(
        'SELECT id, queue_id
         FROM ticket
         WHERE id IN (?, ?)
         ORDER BY id ASC
         FOR UPDATE',
        $FirstID,
        $SecondID,
    );
    if ( !$LockedTickets || @{$LockedTickets} != 2 ) {
        $Self->{LastError} = $Self->{DB}->Error() || 'Translate:TicketLinkTicketNotFound';
        $Self->_TransactionRollback();
        return;
    }
    for my $LockedTicket ( @{$LockedTickets} ) {
        if ( !$Self->_TicketPermissionCheck( Ticket => $LockedTicket, User => $User, Permission => 'ticket.edit' ) ) {
            $Self->{LastError} = 'Translate:TicketLinkPermissionDenied';
            $Self->_TransactionRollback();
            return;
        }
    }

    my $LinkID = $Self->_LinkInsert(
        SourceTicketID => $FirstID,
        TargetTicketID => $SecondID,
        LinkType       => 'related',
        UserID         => $UserID,
    );

    if (!$LinkID) {
        $Self->_TransactionRollback();
        return;
    }

    return $Self->_TransactionCommit() ? $LinkID : undef;
}

sub ArticleSplit {
    my ( $Self, %Param ) = @_;

    $Self->{LastError} = '';

    my $SourceTicketID  = $Param{SourceTicketID} || 0;
    my $SourceArticleID = $Param{SourceArticleID} || 0;
    my $QueueID         = $Param{QueueID} || 0;
    my $StateID         = $Param{StateID} || 0;
    my $PriorityID      = $Param{PriorityID} || 0;
    my $User            = $Param{User} || {};
    my $UserID          = $User->{user_account_id} || 0;
    my $OwnerUserID     = $Param{OwnerUserID} || $UserID;
    my $ResponsibleID   = $Param{ResponsibleUserID} || 0;
    my $Title           = $Param{Title} || '';
    my $CopyAttachments = exists $Param{CopyAttachments} ? ( $Param{CopyAttachments} ? 1 : 0 ) : 1;

    return if !$Self->_NumericIDsValid( $SourceTicketID, $SourceArticleID, $QueueID, $StateID, $PriorityID, $UserID, $OwnerUserID );

    $Title =~ s{\A\s+|\s+\z}{}g;
    if (!$Title) {
        $Self->{LastError} = 'Translate:TicketSplitTitleRequired';
        return;
    }
    $Title = substr( $Title, 0, 500 ) if length($Title) > 500;

    my $Source = $Self->_TicketForChange( TicketID => $SourceTicketID, User => $User );
    return if !$Source;

    if ( !$Self->_QueuePermissionCheck( QueueID => $QueueID, UserID => $UserID, Permission => 'ticket.create' ) ) {
        $Self->{LastError} = 'Translate:TicketSplitQueueDenied';
        return;
    }

    my $Queue = $Self->{DB}->SelectRow(
        'SELECT id FROM ticket_queue WHERE id = ? AND active = 1 LIMIT 1',
        $QueueID,
    );
    my $State = $Self->{DB}->SelectRow(
        'SELECT id, name, state_type, sla_pause
         FROM ticket_state
         WHERE id = ? AND active = 1 AND state_type <> ? AND name <> ?
         LIMIT 1',
        $StateID,
        'pending',
        'merged',
    );
    my $Priority = $Self->{DB}->SelectRow(
        'SELECT id FROM ticket_priority WHERE id = ? AND active = 1 LIMIT 1',
        $PriorityID,
    );
    my $Owner = $Self->_AgentGet( UserID => $OwnerUserID );
    my $Responsible = $ResponsibleID ? $Self->_AgentGet( UserID => $ResponsibleID ) : undef;

    if ( !$Queue || !$State || !$Priority || !$Owner || ( $ResponsibleID && !$Responsible ) ) {
        $Self->{LastError} = 'Translate:TicketSplitSelectionInvalid';
        return;
    }

    my $TicketNumber = $Self->_TicketNumberCreate();
    if (!$TicketNumber) {
        $Self->{LastError} = 'Translate:TicketSplitCreateFailed';
        return;
    }

    return if !$Self->_TransactionStart( Source => 'split' );

    my $LockedSource = $Self->{DB}->SelectRow(
        'SELECT id, queue_id, customer_id, customer_user_id
         FROM ticket
         WHERE id = ?
         LIMIT 1
         FOR UPDATE',
        $SourceTicketID,
    );
    my $Article = $Self->{DB}->SelectRow(
        'SELECT *
         FROM ticket_article
         WHERE id = ? AND ticket_id = ?
         LIMIT 1
         FOR UPDATE',
        $SourceArticleID,
        $SourceTicketID,
    );
    if ( !$LockedSource || !$Article ) {
        $Self->{LastError} = $Article ? 'Translate:TicketSplitCreateFailed' : 'Translate:TicketSplitArticleNotFound';
        $Self->_TransactionRollback();
        return;
    }
    if ( !$Self->_TicketPermissionCheck( Ticket => $LockedSource, User => $User, Permission => 'ticket.edit' ) ) {
        $Self->{LastError} = 'Translate:TicketLinkPermissionDenied';
        $Self->_TransactionRollback();
        return;
    }

    my $TicketResult = $Self->{DB}->Do(
        'INSERT INTO ticket (
            ticket_number, title, queue_id, state_id, priority_id,
            customer_id, customer_user_id, owner_user_id, responsible_user_id,
            service_id, sla_id, sla_source, sla_assignment_source,
            sla_name_snapshot, sla_calendar_id, sla_update_mode,
            sla_first_response_minutes, sla_update_minutes, sla_solution_minutes,
            sla_pause_started_at, solution_at,
            created_by_user_id, changed_by_user_id, created_at, changed_at
         ) VALUES (
            ?, ?, ?, ?, ?, ?, ?, ?, ?,
            NULL, NULL, ?, ?, NULL, NULL, ?, 0, 0, 0,
            CASE WHEN ? = 1 THEN NOW() ELSE NULL END,
            CASE WHEN ? = ? THEN NOW() ELSE NULL END,
            ?, ?, NOW(), NOW()
         )',
        $TicketNumber,
        $Title,
        $QueueID,
        $StateID,
        $PriorityID,
        $LockedSource->{customer_id} || undef,
        $LockedSource->{customer_user_id} || undef,
        $OwnerUserID,
        $ResponsibleID || undef,
        'queue',
        'queue',
        'customer_response',
        $State->{sla_pause} ? 1 : 0,
        $State->{state_type} || '',
        'closed',
        $UserID,
        $UserID,
    );

    if (!$TicketResult) {
        $Self->{LastError} = $Self->{DB}->Error() || 'Translate:TicketSplitCreateFailed';
        $Self->_TransactionRollback();
        return;
    }

    my $TargetTicketID = $Self->{DB}->LastInsertID('ticket');
    if (!$TargetTicketID) {
        $Self->{LastError} = 'Translate:TicketSplitCreateFailed';
        $Self->_TransactionRollback();
        return;
    }

    my $TargetArticleID = $Self->_ArticleCopy(
        Article          => $Article,
        TargetTicketID   => $TargetTicketID,
        ArticleNumber    => 1,
        CopyAttachments  => $CopyAttachments,
        CreatedByUserID  => $UserID,
    );
    if (!$TargetArticleID) {
        $Self->_TransactionRollback();
        return;
    }

    my $LinkID = $Self->_LinkInsert(
        SourceTicketID => $SourceTicketID,
        TargetTicketID => $TargetTicketID,
        LinkType       => 'split',
        UserID         => $UserID,
    );
    if (!$LinkID) {
        $Self->_TransactionRollback();
        return;
    }

    if ( !$Self->_OriginInsert(
        LinkID          => $LinkID,
        SourceTicketID  => $SourceTicketID,
        SourceArticleID => $SourceArticleID,
        TargetTicketID  => $TargetTicketID,
        TargetArticleID => $TargetArticleID,
        OriginType      => 'split',
        UserID          => $UserID,
    ) ) {
        $Self->_TransactionRollback();
        return;
    }

    if ( !$Self->{TicketObject}->RecalculateTicketEscalationTimes(
        TicketID        => $TargetTicketID,
        ChangedByUserID => $UserID,
    ) ) {
        $Self->{LastError} = $Self->{TicketObject}->Error() || 'Translate:TicketSplitCreateFailed';
        $Self->_TransactionRollback();
        return;
    }

    return if !$Self->_TransactionCommit();

    return {
        TicketID     => $TargetTicketID,
        TicketNumber => $TicketNumber,
        ArticleID    => $TargetArticleID,
    };
}

sub TicketMerge {
    my ( $Self, %Param ) = @_;

    $Self->{LastError} = '';

    my $SourceTicketID = $Param{SourceTicketID} || 0;
    my $TargetTicketID = $Param{TargetTicketID} || 0;
    my $User           = $Param{User} || {};
    my $UserID         = $User->{user_account_id} || 0;

    return if !$Self->_NumericIDsValid( $SourceTicketID, $TargetTicketID, $UserID );
    if ( $SourceTicketID == $TargetTicketID ) {
        $Self->{LastError} = 'Translate:TicketMergeSelfDenied';
        return;
    }

    my $Source = $Self->_TicketForChange( TicketID => $SourceTicketID, User => $User );
    return if !$Source;
    my $Target = $Self->_TicketForChange( TicketID => $TargetTicketID, User => $User );
    return if !$Target;

    if (
        ( $Source->{customer_id} || 0 ) != ( $Target->{customer_id} || 0 )
        || ( $Source->{customer_user_id} || 0 ) != ( $Target->{customer_user_id} || 0 )
    ) {
        $Self->{LastError} = 'Translate:TicketMergeCustomerMismatch';
        return;
    }

    if ( ( $Source->{state_name} || '' ) eq 'merged' || ( $Target->{state_name} || '' ) eq 'merged' ) {
        $Self->{LastError} = 'Translate:TicketMergeAlreadyMerged';
        return;
    }

    my $MergedState = $Self->{DB}->SelectRow(
        'SELECT id FROM ticket_state WHERE name = ? AND active = 1 LIMIT 1',
        'merged',
    );
    if (!$MergedState) {
        $Self->{LastError} = 'Translate:TicketMergeStateMissing';
        return;
    }

    return if !$Self->_TransactionStart( Source => 'merge' );

    my $LockedTickets = $Self->{DB}->SelectAll(
        'SELECT
            t.id, t.queue_id, t.customer_id, t.customer_user_id,
            s.name AS state_name
         FROM ticket t
         INNER JOIN ticket_state s ON s.id = t.state_id
         WHERE t.id IN (?, ?)
         ORDER BY t.id ASC
         FOR UPDATE',
        $SourceTicketID,
        $TargetTicketID,
    );
    if ( !$LockedTickets || @{$LockedTickets} != 2 ) {
        $Self->{LastError} = $Self->{DB}->Error() || 'Translate:TicketMergeFailed';
        $Self->_TransactionRollback();
        return;
    }

    my %LockedByID = map { ( $_->{id} || 0 ) => $_ } @{$LockedTickets};
    my $LockedSource = $LockedByID{$SourceTicketID} || {};
    my $LockedTarget = $LockedByID{$TargetTicketID} || {};

    if (
        !$Self->_TicketPermissionCheck( Ticket => $LockedSource, User => $User, Permission => 'ticket.edit' )
        || !$Self->_TicketPermissionCheck( Ticket => $LockedTarget, User => $User, Permission => 'ticket.edit' )
    ) {
        $Self->{LastError} = 'Translate:TicketLinkPermissionDenied';
        $Self->_TransactionRollback();
        return;
    }

    if (
        ( $LockedSource->{customer_id} || 0 ) != ( $LockedTarget->{customer_id} || 0 )
        || ( $LockedSource->{customer_user_id} || 0 ) != ( $LockedTarget->{customer_user_id} || 0 )
    ) {
        $Self->{LastError} = 'Translate:TicketMergeCustomerMismatch';
        $Self->_TransactionRollback();
        return;
    }

    if ( ( $LockedSource->{state_name} || '' ) eq 'merged' || ( $LockedTarget->{state_name} || '' ) eq 'merged' ) {
        $Self->{LastError} = 'Translate:TicketMergeAlreadyMerged';
        $Self->_TransactionRollback();
        return;
    }

    my $Articles = $Self->{DB}->SelectAll(
        'SELECT * FROM ticket_article WHERE ticket_id = ? ORDER BY article_number ASC, id ASC FOR UPDATE',
        $SourceTicketID,
    );
    if ( !$Articles || !@{$Articles} ) {
        $Self->{LastError} = $Articles ? 'Translate:TicketMergeNoArticles' : ( $Self->{DB}->Error() || 'Translate:TicketMergeFailed' );
        $Self->_TransactionRollback();
        return;
    }

    my $TargetArticleNumbers = $Self->{DB}->SelectAll(
        'SELECT article_number
         FROM ticket_article
         WHERE ticket_id = ?
         ORDER BY article_number ASC, id ASC
         FOR UPDATE',
        $TargetTicketID,
    );
    if (!$TargetArticleNumbers) {
        $Self->{LastError} = $Self->{DB}->Error() || 'Translate:TicketMergeFailed';
        $Self->_TransactionRollback();
        return;
    }
    my $NextNumber = @{$TargetArticleNumbers}
        ? ( $TargetArticleNumbers->[-1]->{article_number} || 0 ) + 1
        : 1;

    my $LinkID = $Self->_LinkInsert(
        SourceTicketID => $SourceTicketID,
        TargetTicketID => $TargetTicketID,
        LinkType       => 'merge',
        UserID         => $UserID,
    );
    if (!$LinkID) {
        $Self->_TransactionRollback();
        return;
    }

    for my $Article ( @{$Articles} ) {
        my $ArticleID = $Article->{id} || 0;

        my $ExistingOrigin = $Self->{DB}->SelectRow(
            'SELECT COUNT(*) AS origin_count
             FROM ticket_article_origin
             WHERE target_article_id = ?',
            $ArticleID,
        );
        if (!$ExistingOrigin) {
            $Self->{LastError} = $Self->{DB}->Error() || 'Translate:TicketMergeFailed';
            $Self->_TransactionRollback();
            return;
        }

        if ( !( $ExistingOrigin->{origin_count} || 0 ) && !$Self->_OriginInsert(
            LinkID          => $LinkID,
            SourceTicketID  => $SourceTicketID,
            SourceArticleID => $ArticleID,
            TargetTicketID  => $TargetTicketID,
            TargetArticleID => $ArticleID,
            OriginType      => 'merge',
            UserID          => $UserID,
        ) ) {
            $Self->_TransactionRollback();
            return;
        }

        my $ArticleMove = $Self->{DB}->Do(
            'UPDATE ticket_article
             SET ticket_id = ?, article_number = ?
             WHERE id = ? AND ticket_id = ?',
            $TargetTicketID,
            $NextNumber++,
            $ArticleID,
            $SourceTicketID,
        );
        my $AttachmentMove = $Self->{DB}->Do(
            'UPDATE ticket_article_attachment
             SET ticket_id = ?
             WHERE article_id = ? AND ticket_id = ?',
            $TargetTicketID,
            $ArticleID,
            $SourceTicketID,
        );

        if ( !$ArticleMove || !defined $AttachmentMove ) {
            $Self->{LastError} = $Self->{DB}->Error() || 'Translate:TicketMergeFailed';
            $Self->_TransactionRollback();
            return;
        }
    }

    # A merged ticket is an empty shell. Move its CMDB assignments to the
    # target as well and retain an immutable audit entry on both objects.
    my $CMDBItems = $Self->{DB}->SelectAll(
        'SELECT ci.id, ci.ci_number, ci.name, ct.name AS type_name
         FROM ticket_cmdb_ci tc
         INNER JOIN cmdb_ci ci ON ci.id = tc.ci_id
         INNER JOIN cmdb_ci_type ct ON ct.id = ci.type_id
         WHERE tc.ticket_id = ?
         ORDER BY tc.id ASC
         FOR UPDATE',
        $SourceTicketID,
    );
    if ( !defined $CMDBItems ) {
        $Self->{LastError} = $Self->{DB}->Error() || 'Translate:TicketMergeFailed';
        $Self->_TransactionRollback();
        return;
    }
    my $ActorName = join ' ', grep {$_} ( $User->{firstname}, $User->{lastname} );
    $ActorName ||= $User->{login} || $User->{email} || 'System';
    for my $CI ( @{$CMDBItems} ) {
        my $Inserted = $Self->{DB}->Do(
            'INSERT IGNORE INTO ticket_cmdb_ci (ticket_id,ci_id,created_by_user_id,created_at) VALUES (?,?,?,NOW())',
            $TargetTicketID, $CI->{id}, $UserID,
        );
        my $Removed = $Self->{DB}->Do(
            'DELETE FROM ticket_cmdb_ci WHERE ticket_id=? AND ci_id=?',
            $SourceTicketID, $CI->{id},
        );
        my $CIHistory = $Self->{DB}->Do(
            'INSERT INTO cmdb_ci_history (ci_id,event_type,old_value,new_value,details,related_ticket_id,actor_user_id,actor_name,source,created_at)
             VALUES (?,\'ticket_linked\',?,?,\'Ticket merge\',?,?,?,\'merge\',NOW())',
            $CI->{id}, $SourceTicketID, $TargetTicketID, $TargetTicketID, $UserID, $ActorName,
        );
        my $Display = ( $CI->{ci_number} || '' ) . ' · ' . ( $CI->{name} || '' );
        my $SourceHistory = $Self->{DB}->Do(
            'INSERT INTO ticket_history (ticket_id,event_type,event_category,new_value,new_display,object_type,object_id,actor_user_id,actor_type,actor_name,source,details_text,created_at)
             VALUES (?,\'cmdb_ci_unlinked\',\'system\',?,?,\'cmdb_ci\',?,?,\'agent\',?,\'merge\',?,NOW())',
            $SourceTicketID, $CI->{id}, $Display, $CI->{id}, $UserID, $ActorName, $CI->{type_name} || '',
        );
        my $TargetHistory = $Self->{DB}->Do(
            'INSERT INTO ticket_history (ticket_id,event_type,event_category,new_value,new_display,object_type,object_id,actor_user_id,actor_type,actor_name,source,details_text,created_at)
             VALUES (?,\'cmdb_ci_linked\',\'system\',?,?,\'cmdb_ci\',?,?,\'agent\',?,\'merge\',?,NOW())',
            $TargetTicketID, $CI->{id}, $Display, $CI->{id}, $UserID, $ActorName, $CI->{type_name} || '',
        );
        if ( !defined $Inserted || !$Removed || !$CIHistory || !$SourceHistory || !$TargetHistory ) {
            $Self->{LastError} = $Self->{DB}->Error() || 'Translate:TicketMergeFailed';
            $Self->_TransactionRollback();
            return;
        }
    }

    my $TimeReferenceClear = $Self->{DB}->Do(
        'UPDATE ticket_time_accounting
         SET ticket_article_id = NULL
         WHERE ticket_id = ? AND ticket_article_id IS NOT NULL',
        $SourceTicketID,
    );
    if ( !defined $TimeReferenceClear ) {
        $Self->{LastError} = $Self->{DB}->Error() || 'Translate:TicketMergeFailed';
        $Self->_TransactionRollback();
        return;
    }

    my $TargetUpdate = $Self->{DB}->Do(
        'UPDATE ticket
         SET last_customer_article_at = (
                SELECT MAX(a.created_at) FROM ticket_article a
                WHERE a.ticket_id = ticket.id AND a.sender_type = \'customer\'
             ),
             last_agent_article_at = (
                SELECT MAX(a.created_at) FROM ticket_article a
                WHERE a.ticket_id = ticket.id AND a.sender_type = \'agent\'
             ),
             changed_by_user_id = ?, changed_at = NOW()
         WHERE id = ?',
        $UserID,
        $TargetTicketID,
    );
    my $SourceUpdate = $Self->{DB}->Do(
        'UPDATE ticket
         SET state_id = ?, solution_at = COALESCE(solution_at, NOW()), pending_until = NULL,
             pending_total_minutes = pending_total_minutes
                + CASE WHEN pending_started_at IS NOT NULL THEN TIMESTAMPDIFF(MINUTE, pending_started_at, NOW()) ELSE 0 END,
             sla_pause_total_minutes = sla_pause_total_minutes
                + CASE WHEN sla_pause_started_at IS NOT NULL THEN TIMESTAMPDIFF(MINUTE, sla_pause_started_at, NOW()) ELSE 0 END,
             pending_started_at = NULL, sla_pause_started_at = NULL,
             last_customer_article_at = NULL, last_agent_article_at = NULL,
             changed_by_user_id = ?, changed_at = NOW()
         WHERE id = ?',
        $MergedState->{id},
        $UserID,
        $SourceTicketID,
    );

    if ( !$TargetUpdate || !$SourceUpdate ) {
        $Self->{LastError} = $Self->{DB}->Error() || 'Translate:TicketMergeFailed';
        $Self->_TransactionRollback();
        return;
    }

    for my $RecalculateID ( $TargetTicketID, $SourceTicketID ) {
        if ( !$Self->{TicketObject}->RecalculateTicketEscalationTimes(
            TicketID        => $RecalculateID,
            ChangedByUserID => $UserID,
        ) ) {
            $Self->{LastError} = $Self->{TicketObject}->Error() || 'Translate:TicketMergeFailed';
            $Self->_TransactionRollback();
            return;
        }
    }

    return if !$Self->_TransactionCommit();

    return {
        TicketID     => $TargetTicketID,
        TicketNumber => $Target->{ticket_number} || '',
        MovedCount   => scalar @{$Articles},
    };
}

sub LinkList {
    my ( $Self, %Param ) = @_;

    my $TicketID = $Param{TicketID} || 0;
    my $User     = $Param{User} || {};
    return [] if $TicketID !~ m{\A\d+\z} || !$TicketID;

    my $Rows = $Self->{DB}->SelectAll(
        'SELECT
            l.id,
            l.source_ticket_id,
            l.target_ticket_id,
            l.link_type,
            l.created_at,
            st.ticket_number AS source_ticket_number,
            st.title AS source_title,
            st.queue_id AS source_queue_id,
            ss.name AS source_state,
            tt.ticket_number AS target_ticket_number,
            tt.title AS target_title,
            tt.queue_id AS target_queue_id,
            ts.name AS target_state,
            ua.login AS created_by_login,
            ua.firstname AS created_by_firstname,
            ua.lastname AS created_by_lastname
         FROM ticket_link l
         INNER JOIN ticket st ON st.id = l.source_ticket_id
         INNER JOIN ticket tt ON tt.id = l.target_ticket_id
         INNER JOIN ticket_state ss ON ss.id = st.state_id
         INNER JOIN ticket_state ts ON ts.id = tt.state_id
         LEFT JOIN user_account ua ON ua.id = l.created_by_user_id
         WHERE l.source_ticket_id = ? OR l.target_ticket_id = ?
         ORDER BY l.created_at DESC, l.id DESC',
        $TicketID,
        $TicketID,
    ) || [];

    my @Visible;
    for my $Row ( @{$Rows} ) {
        my $CurrentIsSource = ( $Row->{source_ticket_id} || 0 ) == $TicketID ? 1 : 0;
        my $Other = {
            id       => $CurrentIsSource ? $Row->{target_ticket_id} : $Row->{source_ticket_id},
            queue_id => $CurrentIsSource ? $Row->{target_queue_id} : $Row->{source_queue_id},
        };
        next if !$Self->_TicketPermissionCheck( Ticket => $Other, User => $User, Permission => 'ticket.view' );

        my $Type = $Row->{link_type} || 'related';
        my $LabelKey = 'TicketLinkTypeRelated';
        if ( $Type eq 'split' ) {
            $LabelKey = $CurrentIsSource ? 'TicketLinkTypeSplitChild' : 'TicketLinkTypeSplitOrigin';
        }
        elsif ( $Type eq 'merge' ) {
            $LabelKey = $CurrentIsSource ? 'TicketLinkTypeMergeTarget' : 'TicketLinkTypeMergedSource';
        }

        push @Visible, {
            id            => 0 + ( $Row->{id} || 0 ),
            ticket_id     => 0 + ( $Other->{id} || 0 ),
            ticket_number => $CurrentIsSource ? $Row->{target_ticket_number} : $Row->{source_ticket_number},
            title         => $CurrentIsSource ? $Row->{target_title} : $Row->{source_title},
            state         => $CurrentIsSource ? $Row->{target_state} : $Row->{source_state},
            link_type     => $Type,
            current_is_source => $CurrentIsSource ? 1 : 0,
            label_key     => 'Translate:' . $LabelKey,
            created_at    => $Row->{created_at} || '',
            created_by_name => join( ' ', grep { defined $_ && $_ ne '' } ( $Row->{created_by_firstname}, $Row->{created_by_lastname} ) )
                || $Row->{created_by_login}
                || '-',
        };
    }

    return \@Visible;
}

sub ArticleOriginMap {
    my ( $Self, %Param ) = @_;

    my $TicketID = $Param{TicketID} || 0;
    my $User     = $Param{User} || {};
    return {} if $TicketID !~ m{\A\d+\z} || !$TicketID;

    my $Rows = $Self->{DB}->SelectAll(
        'SELECT
            o.target_article_id,
            o.source_ticket_id,
            o.source_article_id,
            o.origin_type,
            t.ticket_number,
            t.title,
            t.queue_id
         FROM ticket_article_origin o
         INNER JOIN ticket t ON t.id = o.source_ticket_id
         WHERE o.target_ticket_id = ?',
        $TicketID,
    ) || [];

    my %Map;
    for my $Row ( @{$Rows} ) {
        next if !$Self->_TicketPermissionCheck( Ticket => $Row, User => $User, Permission => 'ticket.view' );
        $Map{ $Row->{target_article_id} } = {
            ticket_id       => 0 + ( $Row->{source_ticket_id} || 0 ),
            article_id      => 0 + ( $Row->{source_article_id} || 0 ),
            ticket_number   => $Row->{ticket_number} || '',
            title           => $Row->{title} || '',
            origin_type     => $Row->{origin_type} || '',
            label_key       => $Row->{origin_type} && $Row->{origin_type} eq 'split'
                ? 'Translate:TicketArticleSplitOrigin'
                : 'Translate:TicketArticleMergeOrigin',
        };
    }

    return \%Map;
}

sub _ArticleCopy {
    my ( $Self, %Param ) = @_;

    my $Article         = $Param{Article} || {};
    my $TargetTicketID  = $Param{TargetTicketID} || 0;
    my $ArticleNumber   = $Param{ArticleNumber} || 1;
    my $CreatedByUserID = $Param{CreatedByUserID} || 1;

    my $Result = $Self->{DB}->Do(
        'INSERT INTO ticket_article (
            ticket_id, article_number, channel, sender_type,
            from_name, from_email, to_name, to_email, cc,
            subject, body, search_text, content_type, visibility, internal,
            created_by_user_id, changed_by_user_id, created_at, changed_at
         ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)',
        $TargetTicketID,
        $ArticleNumber,
        $Article->{channel} || 'note',
        $Article->{sender_type} || 'agent',
        $Article->{from_name} || '',
        $Article->{from_email} || '',
        $Article->{to_name} || '',
        $Article->{to_email} || '',
        $Article->{cc},
        $Article->{subject} || '',
        $Article->{body} || '',
        $Article->{search_text},
        $Article->{content_type} || 'text/plain',
        $Article->{visibility} || ( $Article->{internal} ? 'agent' : 'both' ),
        $Article->{internal} ? 1 : 0,
        $Article->{created_by_user_id} || $CreatedByUserID,
        $Article->{changed_by_user_id} || $Article->{created_by_user_id} || $CreatedByUserID,
        $Article->{created_at},
        $Article->{changed_at} || $Article->{created_at},
    );
    if (!$Result) {
        $Self->{LastError} = $Self->{DB}->Error() || 'Translate:TicketArticleCopyFailed';
        return;
    }

    my $TargetArticleID = $Self->{DB}->LastInsertID('ticket_article');
    if (!$TargetArticleID) {
        $Self->{LastError} = 'Translate:TicketArticleCopyFailed';
        return;
    }

    if ( $Param{CopyAttachments} ) {
        my $AttachmentResult = $Self->{DB}->Do(
            'INSERT INTO ticket_article_attachment (
                ticket_id, article_id, filename, content_type, content,
                content_size, content_id, content_disposition,
                created_by_user_id, created_at
             ) SELECT
                ?, ?, filename, content_type, content,
                content_size, content_id, content_disposition,
                created_by_user_id, created_at
             FROM ticket_article_attachment
             WHERE ticket_id = ? AND article_id = ?',
            $TargetTicketID,
            $TargetArticleID,
            $Article->{ticket_id},
            $Article->{id},
        );
        if (!$AttachmentResult) {
            $Self->{LastError} = $Self->{DB}->Error() || 'Translate:TicketArticleAttachmentCopyFailed';
            return;
        }
    }

    return $TargetArticleID;
}

sub _LinkInsert {
    my ( $Self, %Param ) = @_;

    my $Result = $Self->{DB}->Do(
        'INSERT INTO ticket_link (
            source_ticket_id, target_ticket_id, link_type,
            source_article_id, target_article_id,
            created_by_user_id, created_at
         ) VALUES (?, ?, ?, 0, 0, ?, NOW())',
        $Param{SourceTicketID},
        $Param{TargetTicketID},
        $Param{LinkType},
        $Param{UserID},
    );
    if (!$Result) {
        my $DBError = $Self->{DB}->Error() || '';
        $Self->{LastError} = $DBError =~ m{duplicate}i
            ? 'Translate:TicketLinkAlreadyExists'
            : ( $DBError || 'Translate:TicketLinkCreateFailed' );
        return;
    }

    my $LinkID = $Self->{DB}->LastInsertID('ticket_link');
    if (!$LinkID) {
        $Self->{LastError} = 'Translate:TicketLinkCreateFailed';
        return;
    }

    return $LinkID;
}

sub _OriginInsert {
    my ( $Self, %Param ) = @_;

    my $Result = $Self->{DB}->Do(
        'INSERT INTO ticket_article_origin (
            ticket_link_id, source_ticket_id, source_article_id,
            target_ticket_id, target_article_id, origin_type,
            created_by_user_id, created_at
         ) VALUES (?, ?, ?, ?, ?, ?, ?, NOW())',
        $Param{LinkID},
        $Param{SourceTicketID},
        $Param{SourceArticleID},
        $Param{TargetTicketID},
        $Param{TargetArticleID},
        $Param{OriginType},
        $Param{UserID},
    );
    if (!$Result) {
        $Self->{LastError} = $Self->{DB}->Error() || 'Translate:TicketArticleOriginSaveFailed';
        return;
    }

    return 1;
}

sub _TicketForChange {
    my ( $Self, %Param ) = @_;

    my $Ticket = $Self->{TicketObject}->TicketGet(
        TicketID => $Param{TicketID},
        User     => $Param{User} || {},
    );
    if (!$Ticket) {
        $Self->{LastError} = $Self->{TicketObject}->Error() || 'Translate:TicketLinkTicketNotFound';
        return;
    }

    if ( ( $Ticket->{state_name} || '' ) eq 'merged' ) {
        $Self->{LastError} = 'Translate:TicketMergedReadOnly';
        return;
    }

    if ( !$Self->_TicketPermissionCheck(
        Ticket     => $Ticket,
        User       => $Param{User} || {},
        Permission => 'ticket.edit',
    ) ) {
        $Self->{LastError} = 'Translate:TicketLinkPermissionDenied';
        return;
    }

    return $Ticket;
}

sub _TicketPermissionCheck {
    my ( $Self, %Param ) = @_;

    my $Ticket = $Param{Ticket} || {};
    my $User   = $Param{User} || {};

    return $Self->_QueuePermissionCheck(
        QueueID   => $Ticket->{queue_id},
        UserID    => $User->{user_account_id},
        Permission => $Param{Permission} || 'ticket.view',
    );
}

sub _QueuePermissionCheck {
    my ( $Self, %Param ) = @_;

    my $QueueID = $Param{QueueID} || 0;
    my $UserID  = $Param{UserID} || 0;
    return if $QueueID !~ m{\A\d+\z} || !$QueueID || $UserID !~ m{\A\d+\z} || !$UserID;

    return $Self->{Permission}->QueueAccessCheck(
        UserID     => $UserID,
        QueueID    => $QueueID,
        Permission => $Param{Permission} || 'ticket.view',
    ) ? 1 : 0;
}

sub _AgentGet {
    my ( $Self, %Param ) = @_;

    my $UserID = $Param{UserID} || 0;
    return if $UserID !~ m{\A\d+\z} || !$UserID;

    return $Self->{DB}->SelectRow(
        'SELECT id FROM user_account
         WHERE id = ? AND account_type = ? AND is_active = 1 AND is_system_user = 0
         LIMIT 1',
        $UserID,
        'agent',
    );
}

sub _TicketNumberCreate {
    my ($Self) = @_;

    my $Prefix = strftime '%Y%m%d', localtime;
    my $Row = $Self->{DB}->SelectRow(
        'SELECT MAX(ticket_number) AS max_ticket_number
         FROM ticket
         WHERE ticket_number LIKE ?',
        $Prefix . '%',
    );
    return if !$Row;

    my $Next = 1;
    if ( ( $Row->{max_ticket_number} || '' ) =~ m{\A\Q$Prefix\E(\d+)\z} ) {
        $Next = $1 + 1;
    }

    return $Prefix . sprintf '%04d', $Next;
}

sub _NumericIDsValid {
    my ( $Self, @IDs ) = @_;

    for my $ID (@IDs) {
        if ( !defined $ID || $ID !~ m{\A\d+\z} || !$ID ) {
            $Self->{LastError} = 'Translate:TicketLinkInvalidRequest';
            return;
        }
    }

    return 1;
}

sub _TransactionStart {
    my ( $Self, %Param ) = @_;

    if ( !$Self->{DB}->BeginWork() ) {
        $Self->{LastError} = $Self->{DB}->Error() || 'Translate:TicketLinkTransactionFailed';
        return;
    }

    if ( !$Self->{DB}->Do('SET @qisutu_suppress_notifications = 1') ) {
        $Self->{LastError} = $Self->{DB}->Error() || 'Translate:TicketLinkTransactionFailed';
        eval { $Self->{DB}->Rollback(); 1; };
        return;
    }

    my $DBH = $Self->{DB}->Handle();
    if ( $DBH && $Param{Source} ) {
        my $Source = $DBH->quote( $Param{Source} );
        if ( !eval { $DBH->do( 'SET @qisutu_history_source = ' . $Source ); 1; } ) {
            $Self->{LastError} = 'Translate:TicketLinkTransactionFailed';
            eval { $Self->{DB}->Rollback(); 1; };
            eval { $Self->{DB}->Do('SET @qisutu_suppress_notifications = 0'); 1; };
            eval { $Self->{DB}->Do('SET @qisutu_history_source = NULL'); 1; };
            return;
        }
    }

    return 1;
}

sub _TransactionCommit {
    my ($Self) = @_;

    if ( !$Self->{DB}->Commit() ) {
        $Self->{LastError} = $Self->{DB}->Error() || 'Translate:TicketLinkTransactionFailed';
        eval { $Self->{DB}->Rollback(); 1; };
        eval { $Self->{DB}->Do('SET @qisutu_suppress_notifications = 0'); 1; };
        eval { $Self->{DB}->Do('SET @qisutu_history_source = NULL'); 1; };
        return;
    }

    eval { $Self->{DB}->Do('SET @qisutu_suppress_notifications = 0'); 1; };
    eval { $Self->{DB}->Do('SET @qisutu_history_source = NULL'); 1; };
    return 1;
}

sub _TransactionRollback {
    my ($Self) = @_;

    eval { $Self->{DB}->Rollback(); 1; };
    eval { $Self->{DB}->Do('SET @qisutu_suppress_notifications = 0'); 1; };
    eval { $Self->{DB}->Do('SET @qisutu_history_source = NULL'); 1; };
    return;
}

1;
