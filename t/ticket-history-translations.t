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

use lib File::Spec->catdir( $FindBin::Bin, '..', 'core', 'system' );

use QisutuTicketHistory;

{
    package Local::TicketHistoryOutput;

    sub Translate {
        my ( $Self, %Param ) = @_;
        my %Translation = (
            TicketHistoryEventBulkAction      => 'Stapelverarbeitung wurde ausgeführt',
            TicketHistorySourceBulk           => 'Stapelverarbeitung',
            TicketHistorySystem               => 'System',
            TicketState                       => 'Status',
            TicketPriority                    => 'Priorität',
            TicketStateName_new               => 'Neu',
            TicketStateName_closed_successful => 'Erfolgreich geschlossen',
            TicketPriorityName_3_normal       => '3 normal',
            TicketPriorityName_4_high         => '4 hoch',
        );
        return exists $Translation{ $Param{Key} }
            ? $Translation{ $Param{Key} }
            : ( $Param{Key} || '' );
    }

    sub HTMLEscape {
        my ( $Self, $Value ) = @_;
        $Value = '' if !defined $Value;
        $Value =~ s{&}{&amp;}g;
        $Value =~ s{<}{&lt;}g;
        $Value =~ s{>}{&gt;}g;
        $Value =~ s{"}{&quot;}g;
        $Value =~ s{'}{&#39;}g;
        return $Value;
    }
}

my $History = QisutuTicketHistory->new(
    Output => bless( {}, 'Local::TicketHistoryOutput' ),
);

my $HTML = $History->TimelineHTML(
    Language => 'de',
    Items    => [
        {
            id             => 1,
            event_type     => 'bulk_action',
            event_category => 'system',
            actor_name     => 'Qisutu Administrator',
            source         => 'bulk',
            created_at     => '2026-08-09 19:19:23',
            details_text   => 'Prüfung' . "\n"
                . '[{"field":"state","label_key":"TicketState","old_value":"Translate:TicketStateName_new","new_value":"Translate:TicketStateName_closed_successful"},{"field":"priority","label_key":"TicketPriority","old_value":"Translate:TicketPriorityName_3_normal","new_value":"Translate:TicketPriorityName_4_high"}]',
        },
    ],
);

like(
    $HTML,
    qr{<strong>Neu → Erfolgreich geschlossen</strong>},
    'bulk history translates the old and new ticket states',
);
like(
    $HTML,
    qr{<strong>3 normal → 4 hoch</strong>},
    'bulk history translates the old and new priorities',
);
unlike(
    $HTML,
    qr{Translate:Ticket(?:State|Priority)Name_},
    'bulk history never exposes internal translation keys',
);

is(
    $History->_DisplayValue( Field => 'state_id', Value => 'new', Language => 'de' ),
    'Neu',
    'older raw state names remain translated',
);
is(
    $History->_DisplayValue( Field => 'priority_id', Value => '4 high', Language => 'de' ),
    '4 hoch',
    'older raw priority names remain translated',
);

done_testing();
