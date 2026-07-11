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

package Tickets;

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

    my $User    = $Param{User}    || {};
    my $Request = $Param{Request} || {};
    my $TicketID = $Request->{TicketID} || 0;

    if ( $TicketID && $TicketID =~ m{\A\d+\z} ) {
        return {
            Redirect => $Self->_UserIsCustomer( User => $User )
                ? 'index.pl?Page=CustomerTicketZoom&TicketID=' . $TicketID
                : 'index.pl?Page=AgentTicketZoom&TicketID=' . $TicketID,
        };
    }

    return {
        Redirect => $Self->_UserIsCustomer( User => $User )
            ? 'index.pl?Page=CustomerTicketList'
            : 'index.pl?Page=AgentTicketList',
    };
}

sub _UserIsCustomer {
    my ( $Self, %Param ) = @_;

    my $User = $Param{User} || {};

    return if ( $User->{account_type} || '' ) eq 'agent';
    return 1 if $User->{customer_user_id};

    my $UserID = $User->{user_account_id} || 0;

    return if !$Self->{DB};
    return if $UserID !~ m{\A\d+\z} || !$UserID;

    my $Row = $Self->{DB}->SelectRow(
        'SELECT 1 AS is_customer
         FROM customer_user cu
         INNER JOIN customer c
            ON c.id = cu.customer_id
         WHERE cu.user_account_id = ?
            AND cu.active = 1
            AND c.active = 1
         LIMIT 1',
        $UserID,
    );

    return $Row ? 1 : 0;
}

1;
