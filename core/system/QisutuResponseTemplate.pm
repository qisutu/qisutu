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

package QisutuResponseTemplate;

use strict;
use warnings;
use utf8;

use QisutuHTML;

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

    return $Self->{LastError} || '';
}

sub TemplateList {
    my ( $Self, %Param ) = @_;

    my @Bind;
    my $Where = '';

    if ( !$Param{IncludeInactive} ) {
        $Where = 'WHERE rt.active = 1';
    }

    my $Rows = $Self->{DB}->SelectAll(
        'SELECT
            rt.id,
            rt.name,
            rt.description,
            rt.content,
            rt.active,
            rt.sort_order,
            rt.created_at,
            rt.changed_at,
            COUNT(DISTINCT rtq.queue_id) AS queue_count,
            COUNT(DISTINCT rta.id) AS attachment_count,
            GROUP_CONCAT(DISTINCT tq.full_name ORDER BY tq.sort_order ASC, tq.full_name ASC SEPARATOR ", ") AS queue_names
         FROM response_template rt
         LEFT JOIN response_template_queue rtq
            ON rtq.template_id = rt.id
         LEFT JOIN ticket_queue tq
            ON tq.id = rtq.queue_id
         LEFT JOIN response_template_attachment rta
            ON rta.template_id = rt.id
         ' . $Where . '
         GROUP BY
            rt.id, rt.name, rt.description, rt.content, rt.active,
            rt.sort_order, rt.created_at, rt.changed_at
         ORDER BY rt.sort_order ASC, rt.name ASC',
        @Bind,
    );

    if ( !defined $Rows ) {
        $Self->{LastError} = $Self->{DB}->Error() || 'Response templates could not be loaded';
        return [];
    }

    return $Rows;
}

sub TemplateListForQueue {
    my ( $Self, %Param ) = @_;

    my $QueueID = $Param{QueueID} || 0;

    return [] if $QueueID !~ m{\A\d+\z} || !$QueueID;

    my $Rows = $Self->{DB}->SelectAll(
        'SELECT
            rt.id,
            rt.name,
            rt.description,
            rt.sort_order,
            COUNT(rta.id) AS attachment_count
         FROM response_template rt
         INNER JOIN response_template_queue rtq
            ON rtq.template_id = rt.id
           AND rtq.queue_id = ?
         LEFT JOIN response_template_attachment rta
            ON rta.template_id = rt.id
         WHERE rt.active = 1
         GROUP BY rt.id, rt.name, rt.description, rt.sort_order
         ORDER BY rt.sort_order ASC, rt.name ASC',
        $QueueID,
    );

    if ( !defined $Rows ) {
        $Self->{LastError} = $Self->{DB}->Error() || 'Response templates could not be loaded';
        return [];
    }

    return $Rows;
}

sub TemplateGet {
    my ( $Self, %Param ) = @_;

    my $TemplateID = $Param{TemplateID} || 0;

    return if $TemplateID !~ m{\A\d+\z} || !$TemplateID;

    my $Template = $Self->{DB}->SelectRow(
        'SELECT
            id,
            name,
            description,
            content,
            active,
            sort_order,
            created_at,
            changed_at
         FROM response_template
         WHERE id = ?
         LIMIT 1',
        $TemplateID,
    );

    if ( !$Template ) {
        $Self->{LastError} = 'Response template was not found';
        return;
    }

    return $Template;
}

sub TemplateForQueueGet {
    my ( $Self, %Param ) = @_;

    my $TemplateID = $Param{TemplateID} || 0;
    my $QueueID    = $Param{QueueID} || 0;

    return if $TemplateID !~ m{\A\d+\z} || !$TemplateID;
    return if $QueueID !~ m{\A\d+\z} || !$QueueID;

    my $Template = $Self->{DB}->SelectRow(
        'SELECT
            rt.id,
            rt.name,
            rt.description,
            rt.content,
            rt.active,
            rt.sort_order
         FROM response_template rt
         INNER JOIN response_template_queue rtq
            ON rtq.template_id = rt.id
           AND rtq.queue_id = ?
         WHERE rt.id = ?
           AND rt.active = 1
         LIMIT 1',
        $QueueID,
        $TemplateID,
    );

    if ( !$Template ) {
        $Self->{LastError} = 'Response template is not assigned to this queue';
        return;
    }

    my $Attachments = $Self->AttachmentList(
        TemplateID     => $TemplateID,
        IncludeContent => $Param{IncludeAttachmentContent} ? 1 : 0,
    );

    return if $Self->Error();

    $Template->{attachments} = $Attachments;

    return $Template;
}

sub TemplateCreate {
    my ( $Self, %Param ) = @_;

    my $Name        = $Self->_Trim( $Param{Name} );
    my $Description = $Self->_Trim( $Param{Description} );
    my $Content     = QisutuHTML->Sanitize( $Param{Content} || '' );
    my $SortOrder   = $Param{SortOrder} || 1000;
    my $UserID      = $Param{ChangedByUserID} || 1;

    if ( !$Name ) {
        $Self->{LastError} = 'Response template name is required';
        return;
    }

    if ( !QisutuHTML->PlainTextSearch($Content) ) {
        $Self->{LastError} = 'Response template content is required';
        return;
    }

    $SortOrder = 1000 if $SortOrder !~ m{\A\d+\z} || $SortOrder < 1;
    $UserID    = 1 if $UserID !~ m{\A\d+\z} || !$UserID;

    my $Result = $Self->{DB}->Do(
        'INSERT INTO response_template (
            name,
            description,
            content,
            active,
            sort_order,
            created_by_user_id,
            changed_by_user_id,
            created_at,
            changed_at
         ) VALUES (?, ?, ?, 1, ?, ?, ?, NOW(), NOW())',
        $Name,
        $Description,
        $Content,
        $SortOrder,
        $UserID,
        $UserID,
    );

    if ( !$Result ) {
        $Self->{LastError} = $Self->{DB}->Error() || 'Response template could not be created';
        return;
    }

    my $TemplateID = $Self->{DB}->LastInsertID('response_template');

    if ( !$TemplateID ) {
        my $Row = $Self->{DB}->SelectRow(
            'SELECT id FROM response_template WHERE name = ? ORDER BY id DESC LIMIT 1',
            $Name,
        );
        $TemplateID = $Row->{id} if $Row;
    }

    if ( !$TemplateID ) {
        $Self->{LastError} = 'Response template ID could not be determined';
        return;
    }

    return $TemplateID;
}

sub TemplateUpdate {
    my ( $Self, %Param ) = @_;

    my $TemplateID = $Param{TemplateID} || 0;
    my $Name        = $Self->_Trim( $Param{Name} );
    my $Description = $Self->_Trim( $Param{Description} );
    my $Content     = QisutuHTML->Sanitize( $Param{Content} || '' );
    my $Active      = $Param{Active} ? 1 : 0;
    my $SortOrder   = $Param{SortOrder} || 1000;
    my $UserID      = $Param{ChangedByUserID} || 1;

    if ( $TemplateID !~ m{\A\d+\z} || !$TemplateID ) {
        $Self->{LastError} = 'Valid response template ID is required';
        return;
    }

    if ( !$Name ) {
        $Self->{LastError} = 'Response template name is required';
        return;
    }

    if ( !QisutuHTML->PlainTextSearch($Content) ) {
        $Self->{LastError} = 'Response template content is required';
        return;
    }

    $SortOrder = 1000 if $SortOrder !~ m{\A\d+\z} || $SortOrder < 1;
    $UserID    = 1 if $UserID !~ m{\A\d+\z} || !$UserID;

    my $Result = $Self->{DB}->Do(
        'UPDATE response_template
         SET name = ?,
             description = ?,
             content = ?,
             active = ?,
             sort_order = ?,
             changed_by_user_id = ?,
             changed_at = NOW()
         WHERE id = ?',
        $Name,
        $Description,
        $Content,
        $Active,
        $SortOrder,
        $UserID,
        $TemplateID,
    );

    if ( !$Result ) {
        $Self->{LastError} = $Self->{DB}->Error() || 'Response template could not be updated';
        return;
    }

    return 1;
}

sub TemplateDeactivate {
    my ( $Self, %Param ) = @_;

    my $TemplateID = $Param{TemplateID} || 0;
    my $UserID      = $Param{ChangedByUserID} || 1;

    return if $TemplateID !~ m{\A\d+\z} || !$TemplateID;

    my $Result = $Self->{DB}->Do(
        'UPDATE response_template
         SET active = 0,
             changed_by_user_id = ?,
             changed_at = NOW()
         WHERE id = ?',
        $UserID,
        $TemplateID,
    );

    if ( !$Result ) {
        $Self->{LastError} = $Self->{DB}->Error() || 'Response template could not be deactivated';
        return;
    }

    return 1;
}

sub QueueList {
    my ( $Self, %Param ) = @_;

    my $Rows = $Self->{DB}->SelectAll(
        'SELECT
            tq.id,
            tq.full_name,
            tq.active,
            tq.sort_order,
            COUNT(rtq.template_id) AS template_count,
            GROUP_CONCAT(rt.name ORDER BY rt.sort_order ASC, rt.name ASC SEPARATOR ", ") AS template_names
         FROM ticket_queue tq
         LEFT JOIN response_template_queue rtq
            ON rtq.queue_id = tq.id
         LEFT JOIN response_template rt
            ON rt.id = rtq.template_id
         ' . ( $Param{IncludeInactive} ? '' : 'WHERE tq.active = 1' ) . '
         GROUP BY tq.id, tq.full_name, tq.active, tq.sort_order
         ORDER BY tq.sort_order ASC, tq.full_name ASC'
    );

    if ( !defined $Rows ) {
        $Self->{LastError} = $Self->{DB}->Error() || 'Queues could not be loaded';
        return [];
    }

    return $Rows;
}

sub TemplateQueueIDs {
    my ( $Self, %Param ) = @_;

    my $TemplateID = $Param{TemplateID} || 0;
    return [] if $TemplateID !~ m{\A\d+\z} || !$TemplateID;

    my $Rows = $Self->{DB}->SelectAll(
        'SELECT queue_id
         FROM response_template_queue
         WHERE template_id = ?
         ORDER BY queue_id ASC',
        $TemplateID,
    ) || [];

    return [ map { 0 + ( $_->{queue_id} || 0 ) } @{$Rows} ];
}

sub QueueTemplateIDs {
    my ( $Self, %Param ) = @_;

    my $QueueID = $Param{QueueID} || 0;
    return [] if $QueueID !~ m{\A\d+\z} || !$QueueID;

    my $Rows = $Self->{DB}->SelectAll(
        'SELECT template_id
         FROM response_template_queue
         WHERE queue_id = ?
         ORDER BY template_id ASC',
        $QueueID,
    ) || [];

    return [ map { 0 + ( $_->{template_id} || 0 ) } @{$Rows} ];
}

sub TemplateQueueSet {
    my ( $Self, %Param ) = @_;

    my $TemplateID = $Param{TemplateID} || 0;
    my $QueueIDs   = ref $Param{QueueIDs} eq 'ARRAY' ? $Param{QueueIDs} : [];
    my $UserID     = $Param{ChangedByUserID} || 1;

    if ( $TemplateID !~ m{\A\d+\z} || !$TemplateID ) {
        $Self->{LastError} = 'Valid response template ID is required';
        return;
    }

    my %Seen;
    my @IDs = grep { $_ =~ m{\A\d+\z} && $_ > 0 && !$Seen{$_}++ } @{$QueueIDs};

    if ( !$Self->{DB}->Do( 'DELETE FROM response_template_queue WHERE template_id = ?', $TemplateID ) ) {
        $Self->{LastError} = $Self->{DB}->Error() || 'Queue assignments could not be reset';
        return;
    }

    for my $QueueID (@IDs) {
        my $Result = $Self->{DB}->Do(
            'INSERT INTO response_template_queue (
                template_id,
                queue_id,
                created_by_user_id,
                changed_by_user_id,
                created_at,
                changed_at
             ) VALUES (?, ?, ?, ?, NOW(), NOW())',
            $TemplateID,
            $QueueID,
            $UserID,
            $UserID,
        );

        if ( !$Result ) {
            $Self->{LastError} = $Self->{DB}->Error() || 'Queue assignment could not be saved';
            return;
        }
    }

    return 1;
}

sub QueueTemplateSet {
    my ( $Self, %Param ) = @_;

    my $QueueID     = $Param{QueueID} || 0;
    my $TemplateIDs = ref $Param{TemplateIDs} eq 'ARRAY' ? $Param{TemplateIDs} : [];
    my $UserID      = $Param{ChangedByUserID} || 1;

    if ( $QueueID !~ m{\A\d+\z} || !$QueueID ) {
        $Self->{LastError} = 'Valid queue ID is required';
        return;
    }

    my %Seen;
    my @IDs = grep { $_ =~ m{\A\d+\z} && $_ > 0 && !$Seen{$_}++ } @{$TemplateIDs};

    if ( !$Self->{DB}->Do( 'DELETE FROM response_template_queue WHERE queue_id = ?', $QueueID ) ) {
        $Self->{LastError} = $Self->{DB}->Error() || 'Template assignments could not be reset';
        return;
    }

    for my $TemplateID (@IDs) {
        my $Result = $Self->{DB}->Do(
            'INSERT INTO response_template_queue (
                template_id,
                queue_id,
                created_by_user_id,
                changed_by_user_id,
                created_at,
                changed_at
             ) VALUES (?, ?, ?, ?, NOW(), NOW())',
            $TemplateID,
            $QueueID,
            $UserID,
            $UserID,
        );

        if ( !$Result ) {
            $Self->{LastError} = $Self->{DB}->Error() || 'Template assignment could not be saved';
            return;
        }
    }

    return 1;
}

sub AttachmentList {
    my ( $Self, %Param ) = @_;

    my $TemplateID = $Param{TemplateID} || 0;
    return [] if $TemplateID !~ m{\A\d+\z} || !$TemplateID;

    my $ContentColumn = $Param{IncludeContent} ? ', content' : '';

    my $Rows = $Self->{DB}->SelectAll(
        'SELECT
            id,
            template_id,
            filename,
            content_type,
            content_size,
            created_at
            ' . $ContentColumn . '
         FROM response_template_attachment
         WHERE template_id = ?
         ORDER BY id ASC',
        $TemplateID,
    );

    if ( !defined $Rows ) {
        $Self->{LastError} = $Self->{DB}->Error() || 'Template attachments could not be loaded';
        return [];
    }

    for my $Row (@{$Rows}) {
        $Row->{size_display} = $Self->_FileSizeFormat( $Row->{content_size} || 0 );
    }

    return $Rows;
}

sub AttachmentCreate {
    my ( $Self, %Param ) = @_;

    my $TemplateID = $Param{TemplateID} || 0;
    my $Attachment = $Param{Attachment} || {};
    my $UserID      = $Param{ChangedByUserID} || 1;

    if ( $TemplateID !~ m{\A\d+\z} || !$TemplateID ) {
        $Self->{LastError} = 'Valid response template ID is required';
        return;
    }

    my $Filename = $Self->_FilenameClean( $Attachment->{Filename} || '' );
    my $Content  = $Attachment->{Content};
    my $Type     = $Self->_ContentTypeClean( $Attachment->{ContentType} || 'application/octet-stream' );
    my $Size     = $Attachment->{ContentSize};

    if ( !$Filename || !defined $Content ) {
        $Self->{LastError} = 'Template attachment is incomplete';
        return;
    }

    $Size = length($Content) if !defined $Size || $Size !~ m{\A\d+\z};

    my $Result = $Self->{DB}->Do(
        'INSERT INTO response_template_attachment (
            template_id,
            filename,
            content_type,
            content,
            content_size,
            created_by_user_id,
            created_at
         ) VALUES (?, ?, ?, ?, ?, ?, NOW())',
        $TemplateID,
        $Filename,
        $Type,
        $Content,
        $Size,
        $UserID,
    );

    if ( !$Result ) {
        $Self->{LastError} = $Self->{DB}->Error() || 'Template attachment could not be stored';
        return;
    }

    return 1;
}

sub AttachmentDelete {
    my ( $Self, %Param ) = @_;

    my $AttachmentID = $Param{AttachmentID} || 0;
    my $TemplateID   = $Param{TemplateID} || 0;

    if ( $AttachmentID !~ m{\A\d+\z} || !$AttachmentID ) {
        $Self->{LastError} = 'Valid attachment ID is required';
        return;
    }

    if ( $TemplateID !~ m{\A\d+\z} || !$TemplateID ) {
        $Self->{LastError} = 'Valid response template ID is required';
        return;
    }

    my $Result = $Self->{DB}->Do(
        'DELETE FROM response_template_attachment
         WHERE id = ?
           AND template_id = ?',
        $AttachmentID,
        $TemplateID,
    );

    if ( !$Result ) {
        $Self->{LastError} = $Self->{DB}->Error() || 'Template attachment could not be deleted';
        return;
    }

    return 1;
}

sub AttachmentsForArticle {
    my ( $Self, %Param ) = @_;

    my $TemplateID   = $Param{TemplateID} || 0;
    my $QueueID      = $Param{QueueID} || 0;
    my $AttachmentIDs = ref $Param{AttachmentIDs} eq 'ARRAY' ? $Param{AttachmentIDs} : [];

    my $Template = $Self->TemplateForQueueGet(
        TemplateID              => $TemplateID,
        QueueID                 => $QueueID,
        IncludeAttachmentContent => 1,
    );

    return [] if !$Template;

    my %Wanted = map { 0 + $_ => 1 } grep { defined $_ && $_ =~ m{\A\d+\z} && $_ > 0 } @{$AttachmentIDs};
    my $UseSelection = $Param{UseSelection} ? 1 : ( @{$AttachmentIDs} ? 1 : 0 );
    my @Attachments;

    for my $Attachment ( @{ $Template->{attachments} || [] } ) {
        next if $UseSelection && !$Wanted{ 0 + ( $Attachment->{id} || 0 ) };

        push @Attachments, {
            Filename           => $Attachment->{filename} || 'attachment.bin',
            ContentType        => $Attachment->{content_type} || 'application/octet-stream',
            Content            => $Attachment->{content},
            ContentSize        => $Attachment->{content_size} || length( $Attachment->{content} || '' ),
            ContentDisposition => 'attachment',
        };
    }

    return \@Attachments;
}

sub _Trim {
    my ( $Self, $Value ) = @_;

    $Value = '' if !defined $Value;
    $Value =~ s{\A\s+|\s+\z}{}g;

    return $Value;
}

sub _FilenameClean {
    my ( $Self, $Filename ) = @_;

    $Filename = '' if !defined $Filename;
    $Filename =~ s{\\}{/}g;
    $Filename =~ s{\A.*/}{}g;
    $Filename =~ s{[\r\n\x00]}{}g;
    $Filename =~ s{\A\s+|\s+\z}{}g;
    $Filename = substr( $Filename, 0, 255 ) if length($Filename) > 255;

    return $Filename;
}

sub _ContentTypeClean {
    my ( $Self, $Type ) = @_;

    $Type = 'application/octet-stream' if !defined $Type;
    $Type =~ s{\r|\n}{ }g;
    $Type =~ s{\s+}{ }g;
    $Type =~ s{\A\s+|\s+\z}{}g;
    $Type = 'application/octet-stream' if !$Type;
    $Type = substr( $Type, 0, 255 ) if length($Type) > 255;

    return $Type;
}

sub _FileSizeFormat {
    my ( $Self, $Size ) = @_;

    $Size = 0 if !defined $Size || $Size !~ m{\A\d+(?:\.\d+)?\z};

    return sprintf( '%.1f GB', $Size / 1024 / 1024 / 1024 ) if $Size >= 1024 * 1024 * 1024;
    return sprintf( '%.1f MB', $Size / 1024 / 1024 ) if $Size >= 1024 * 1024;
    return sprintf( '%.1f KB', $Size / 1024 ) if $Size >= 1024;

    return int($Size) . ' B';
}

1;
