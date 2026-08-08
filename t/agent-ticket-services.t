#!/usr/bin/env perl

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

use strict;
use warnings;
use utf8;

use File::Spec;
use FindBin;
use Test::More;

use lib File::Spec->catdir( $FindBin::Bin, '..', 'core', 'module' );
use lib File::Spec->catdir( $FindBin::Bin, '..', 'core', 'system' );

use AgentTicketCreate;

{
    package Local::AgentTicketServiceDB;

    sub SelectAll {
        my ( $Self, $SQL ) = @_;

        if ( $SQL =~ m{FROM\s+service\s+s}si ) {
            return [
                {
                    id          => 1,
                    parent_id   => undef,
                    name        => 'ERP',
                    full_name   => 'ERP',
                    active      => 1,
                    sort_order  => 100,
                    sla_count   => 0,
                },
                {
                    id          => 2,
                    parent_id   => 1,
                    name        => 'Finanzbuchhaltung',
                    full_name   => 'ERP::Finanzbuchhaltung',
                    active      => 1,
                    sort_order  => 100,
                    sla_count   => 0,
                },
                {
                    id          => 3,
                    parent_id   => undef,
                    name        => 'Email',
                    full_name   => 'Email',
                    active      => 1,
                    sort_order  => 200,
                    sla_count   => 0,
                },
            ];
        }

        die "Unexpected SelectAll SQL in agent-ticket-services test: $SQL";
    }

    sub Error { return '' }
}

{
    package Local::AgentTicketServiceOutput;

    sub Translate {
        my ( $Self, %Param ) = @_;
        return $Param{Key} || '';
    }
}

my $Module = AgentTicketCreate->new(
    Config => { Language => { Default => 'de' } },
    DB     => bless( {}, 'Local::AgentTicketServiceDB' ),
    Output => bless( {}, 'Local::AgentTicketServiceOutput' ),
);

my $Data = $Module->_ServiceOptionsData(
    CustomerUserID => 0,
    Language       => 'de',
);

ok( $Data->{success}, 'active services load without a selected customer contact' );
is( scalar @{ $Data->{items} || [] }, 3, 'all active services are available even without SLAs' );
ok( !grep( { !$_->{selectable} } @{ $Data->{items} || [] } ), 'every active service is selectable' );
is( $Data->{items}->[1]->{depth}, 1, 'the service hierarchy remains intact' );
is( $Data->{items}->[1]->{sla_id}, 0, 'a service without an SLA remains a valid service option' );

my $TicketPath = File::Spec->catfile( $FindBin::Bin, '..', 'core', 'system', 'QisutuTicket.pm' );
open my $TicketFH, '<:encoding(UTF-8)', $TicketPath or die "Cannot read $TicketPath: $!";
local $/;
my $TicketSource = <$TicketFH>;
close $TicketFH;

my ($AgentCreate) = $TicketSource =~ m{sub\s+TicketCreateFromAgent\b(.*?)^sub\s+}ms;
ok( $AgentCreate, 'agent ticket creation implementation was found' );
like(
    $AgentCreate,
    qr{\$SLASnapshot->\{service_id\}\s*=\s*\$ServiceID},
    'ticket creation stores an active service even when no customer SLA resolves',
);
unlike(
    $AgentCreate,
    qr{\$ServiceID\s*!~\s*m\{\\A\\d\+\\z\}\s*\|\|\s*!\$CustomerUserID},
    'service selection no longer requires a registered customer contact',
);

done_testing();
