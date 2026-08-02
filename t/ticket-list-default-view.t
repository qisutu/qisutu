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

use AgentTicketList;

{
    package Local::TicketListDB;
    sub SelectAll { return [] }
    sub Error { return '' }
}

{
    package Local::TicketListOutput;
    sub Translate { my ( $Self, %Param ) = @_; return $Param{Key} || '' }
    sub HTMLEscape {
        my ( $Self, $Value ) = @_;
        $Value = '' if !defined $Value;
        $Value =~ s/&/&amp;/g;
        $Value =~ s/</&lt;/g;
        $Value =~ s/>/&gt;/g;
        $Value =~ s/"/&quot;/g;
        return $Value;
    }
}

{
    package Local::TicketListPreference;
    sub new { return bless { DefaultView => 'my', SetCalls => [] }, shift }
    sub AgentPreferenceGet {
        my ($Self) = @_;
        return {
            ticket_list_default_view => $Self->{DefaultView},
            ticket_list_limit        => 20,
            ticket_list_columns      => 'ticket_number,title,queue,state,priority,customer,customer_user,owner,escalation_state,next_escalation,pending_until,changed',
        };
    }
    sub Set {
        my ( $Self, %Param ) = @_;
        push @{ $Self->{SetCalls} }, { %Param };
        $Self->{DefaultView} = $Param{Value} if ( $Param{Key} || '' ) eq 'ticket_list_default_view';
        return 1;
    }
    sub Error { return '' }
}

{
    package Local::TicketListTicket;
    sub new { return bless {}, shift }
    sub TicketSearchOptions { return AgentTicketList->_EmptySearchOptions() }
    sub TicketListDynamicFieldList { return [] }
    sub TicketListFilterOptions { return { Queues => [], Customers => [], CustomerUsers => [], Owners => [] } }
    sub TicketListCount {
        my ( $Self, %Param ) = @_;
        $Self->{LastView} = $Param{View};
        return 0;
    }
    sub Error { return '' }
}

{
    package Local::AgentTicketList;
    use parent 'AgentTicketList';
    sub _PreferenceObject { return shift->{PreferenceObject} }
    sub _TicketObject { return shift->{TicketObject} }
}

my $Preference = Local::TicketListPreference->new();
my $Ticket = Local::TicketListTicket->new();
my $Module = Local::AgentTicketList->new(
    Config => {},
    DB     => bless( {}, 'Local::TicketListDB' ),
    Output => bless( {}, 'Local::TicketListOutput' ),
);
$Module->{PreferenceObject} = $Preference;
$Module->{TicketObject} = $Ticket;

my $DefaultResult = $Module->Run(
    Request => { Language => 'de' },
    User    => { user_account_id => 7 },
);

is( $Ticket->{LastView}, 'my', 'the saved agent view is used when the URL does not specify a view' );
is( $DefaultResult->{Data}->{CurrentView}, 'my', 'the default-view button receives the active view' );
ok( $DefaultResult->{Data}->{CanSaveDefaultView}, 'the default-view button is available for regular views' );

my $SaveResult = $Module->Run(
    Request => {
        Language => 'de',
        Step     => 'TicketListDefaultViewSave',
        View     => 'pending',
    },
    User => { user_account_id => 7 },
);

is_deeply(
    $Preference->{SetCalls}->[-1],
    {
        UserAccountID => 7,
        Key           => 'ticket_list_default_view',
        Value         => 'pending',
    },
    'saving stores only the selected ticket view as an agent preference',
);
like( $SaveResult->{Redirect}, qr{(?:[?;])View=pending(?:;|\z)}, 'saving returns to the selected view' );

done_testing();
