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

package TicketAttachmentDownload;

use strict;
use warnings;
use utf8;

use Encode qw(encode);

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

    my $Request      = $Param{Request} || {};
    my $User         = $Param{User} || {};
    my $AttachmentID = $Request->{AttachmentID} || 0;

    my $TicketObject = $Self->_TicketObject();
    if ( !$TicketObject ) {
        return $Self->_ErrorResponse(
            Status  => '500 Internal Server Error',
            Message => 'Ticket system could not be loaded.',
        );
    }

    my $Attachment = $TicketObject->ArticleAttachmentGet(
        AttachmentID => $AttachmentID,
        User         => $User,
    );

    if ( !$Attachment ) {
        return $Self->_ErrorResponse(
            Status  => '404 Not Found',
            Message => $TicketObject->Error() || 'Attachment was not found.',
        );
    }

    my $Filename    = $Self->_FilenameForHeader( $Attachment->{filename} || 'attachment.bin' );
    my $Disposition = $Self->_ContentDisposition( $Attachment->{filename} || 'attachment.bin' );
    my $ContentType = $Self->_ContentTypeForHeader( $Attachment->{content_type} || 'application/octet-stream' );
    my $Content     = $Attachment->{content};
    $Content = '' if !defined $Content;

    return {
        Response => $Self->{Output}->Response(
            Status      => '200 OK',
            ContentType => $ContentType,
            Body        => $Content,
            Headers     => [
                'Content-Disposition: ' . $Disposition,
                'Content-Length: ' . length($Content),
                'X-Content-Type-Options: nosniff',
            ],
        ),
    };
}

sub _TicketObject {
    my ($Self) = @_;

    return if !$Self->{DB};

    my $Loaded = eval {
        require QisutuPermission;
        require QisutuTicket;
        1;
    };

    if ( !$Loaded ) {
        return;
    }

    my $PermissionObject = QisutuPermission->new(
        Config => $Self->{Config},
        DB     => $Self->{DB},
    );

    return QisutuTicket->new(
        Config     => $Self->{Config},
        DB         => $Self->{DB},
        Permission => $PermissionObject,
    );
}

sub _ErrorResponse {
    my ( $Self, %Param ) = @_;

    my $Status  = $Param{Status} || '500 Internal Server Error';
    my $Message = $Param{Message} || 'Error';

    return {
        Response => $Self->{Output}->Response(
            Status      => $Status,
            ContentType => 'text/plain; charset=UTF-8',
            Body        => $Message,
        ),
    };
}

sub _FilenameForHeader {
    my ( $Self, $Filename ) = @_;

    $Filename ||= 'attachment.bin';
    $Filename =~ s{\\}{/}g;
    $Filename =~ s{\A.*/}{}g;
    $Filename =~ s{[\r\n\x00"]}{}g;
    $Filename =~ s{[^A-Za-z0-9_.\- ]}{_}g;
    $Filename =~ s{\A\s+|\s+\z}{}g;
    $Filename ||= 'attachment.bin';

    return $Filename;
}

sub _ContentDisposition {
    my ( $Self, $Filename ) = @_;

    $Filename ||= 'attachment.bin';
    $Filename =~ s{\\}{/}g;
    $Filename =~ s{\A.*/}{}g;
    $Filename =~ s{[\r\n\x00]}{}g;
    $Filename =~ s{\A\s+|\s+\z}{}g;
    $Filename ||= 'attachment.bin';

    my $Fallback = $Self->_FilenameForHeader($Filename);
    my $Bytes = encode( 'UTF-8', $Filename );
    my $Encoded = join '', map {
        my $Character = chr($_);
        $Character =~ m{[A-Za-z0-9!#\x24&+.^_`|~-]} ? $Character : sprintf( '%%%02X', $_ )
    } unpack( 'C*', $Bytes );

    return 'attachment; filename="' . $Fallback . '"; filename*=UTF-8\'\'' . $Encoded;
}

sub _ContentTypeForHeader {
    my ( $Self, $ContentType ) = @_;

    $ContentType ||= 'application/octet-stream';
    $ContentType =~ s{[\r\n\x00]}{}g;
    $ContentType =~ s{;.*\z}{};
    $ContentType =~ s{\A\s+|\s+\z}{}g;
    $ContentType = lc $ContentType;
    $ContentType = 'application/octet-stream' if $ContentType !~ m{\A[a-z0-9!#\x24&.+\-^_]+/[a-z0-9!#\x24&.+\-^_]+\z};

    return $ContentType;
}

1;
