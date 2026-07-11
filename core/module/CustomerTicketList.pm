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

package CustomerTicketList;

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
    my $Tickets      = [];
    my $User         = $Param{User} || {};

    if ($TicketObject) {
        $Tickets = $TicketObject->TicketList(
            Limit    => 100,
            User     => $User,
            ZoomPage => 'CustomerTicketZoom',
            Language => ( $Param{Request} || {} )->{Language} || 'en',
        );
    }

    return {
        Template => 'CustomerTicketList.tt',
        Data     => {
            PageTitle          => 'Translate:CustomerTicketListTitle',
            ProgramTitle       => 'Translate:CustomerTicketListTitle',
            ProgramDescription => 'Translate:ProgramTicketsDescription',
            Tickets            => $Tickets,
            HasTickets         => scalar @{$Tickets} ? 1 : 0,
            TicketCount        => scalar @{$Tickets},
            CustomerTicketCreateURL => 'index.pl?Page=CustomerTicketCreate',
        },
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

1;
