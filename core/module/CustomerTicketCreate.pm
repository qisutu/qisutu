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

package CustomerTicketCreate;

use strict;
use warnings;
use utf8;

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

    my $TicketObject = $Self->_TicketObject();
    my $Request      = $Param{Request} || {};
    my $User         = $Param{User} || {};
    my $CreateError  = '';
    my $QueueList    = [];

    if ( $TicketObject && ( $Request->{Step} || '' ) eq 'CustomerTicketCreate' ) {
        my $TicketID = $TicketObject->TicketCreateFromCustomer(
            User        => $User,
            QueueID     => $Request->{QueueID},
            Title       => $Request->{Title},
            Body        => $Request->{Body},
            ContentType => 'text/html',
        );

        if ($TicketID) {
            return {
                Redirect => 'index.pl?Page=CustomerTicketZoom&TicketID=' . $TicketID,
            };
        }

        $CreateError = $TicketObject->Error() || 'Translate:TicketCreateFailed';
    }

    if ($TicketObject) {
        $QueueList = $TicketObject->CustomerQueueList( User => $User );
    }

    return {
        Template => 'CustomerTicketCreate.tt',
        Data     => {
            PageTitle          => 'Translate:TicketCreateNew',
            ProgramTitle       => 'Translate:TicketCreateNew',
            ProgramDescription => 'Translate:ProgramTicketsDescription',
            TicketListURL      => 'index.pl?Page=CustomerTicketList',
            QueueOptionsHTML   => $Self->_QueueOptionsHTML( QueueList => $QueueList ),
            HasQueueOptions    => scalar @{$QueueList} ? 1 : 0,
            CreateError        => $CreateError,
            CreateErrorClass   => $CreateError ? '' : 'qisutu-hidden',
            FormAction         => 'index.pl',
        },
    };
}

sub _QueueOptionsHTML {
    my ( $Self, %Param ) = @_;

    my $QueueList = $Param{QueueList} || [];
    my $HTML      = '';

    for my $Queue ( @{$QueueList} ) {
        my $Name = $Queue->{full_name} || $Queue->{name} || '';
        $HTML .= '<option value="' . $Self->_Escape( $Queue->{id} ) . '">' . $Self->_Escape($Name) . '</option>';
    }

    return $HTML;
}

sub _Escape {
    my ( $Self, $Value ) = @_;

    $Value = '' if !defined $Value;

    if ( $Self->{Output} ) {
        return $Self->{Output}->HTMLEscape($Value);
    }

    $Value =~ s{&}{&amp;}g;
    $Value =~ s{<}{&lt;}g;
    $Value =~ s{>}{&gt;}g;
    $Value =~ s{"}{&quot;}g;

    return $Value;
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

1;
