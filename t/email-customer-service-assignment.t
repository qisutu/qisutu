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
use QisutuTicket;

{
    package Local::EmailServiceDB;

    sub Error { return shift->{Fail} ? 'Customer service lookup failed' : '' }

    sub SelectRow {
        my ( $Self, $SQL, @Bind ) = @_;
        return { id => 2 } if $SQL =~ m{FROM ticket_queue};
        return { id => 1, state_type => 'new', sla_pause => 0 } if $SQL =~ m{FROM ticket_state};
        return { id => 3 } if $SQL =~ m{FROM ticket_priority};
        if ( $SQL =~ m{FROM customer_user cu} ) {
            if ( $SQL =~ m{LOWER\(ua.email\)} ) {
                return if $Bind[0] ne 'customer@example.test';
            }
            return { id => 8, customer_user_id => 8, customer_id => 1 };
        }
        return { id => $Bind[0] } if $SQL =~ m{FROM customer WHERE};
        if ( $SQL =~ m{FROM sla sl} ) {
            return {
                id => 99, service_id => 9, name => 'Filter SLA', calendar_id => 4,
                update_mode => 'regular', first_response_minutes => 30,
                update_minutes => 40, solution_minutes => 50,
            };
        }
        die "Unexpected SelectRow: $SQL";
    }

    sub SelectAll {
        my ( $Self, $SQL, @Bind ) = @_;
        die "Unexpected SelectAll: $SQL" if $SQL !~ m{FROM customer_service cs};
        $Self->{Lookups}++;
        return if $Self->{Fail};
        return [] if $Bind[1] != 1;
        return [ map { { %{$_} } } @{ $Self->{Services} || [] } ];
    }
}

my $Service = {
    id => 7, full_name => 'ERP-System', sla_id => 21, sla_name => 'ERP-SLA-M',
    calendar_id => 4, calendar_name => 'ERP calendar', update_mode => 'regular',
    first_response_minutes => 120, update_minutes => 60, solution_minutes => 1440,
    assignment_source => 'customer',
};
my $DB = bless { Services => [$Service] }, 'Local::EmailServiceDB';
my $Ticket = QisutuTicket->new( Config => {}, DB => $DB );
my %New = ( IsNew => 1, QueueID => 2, FromEmail => ' Customer@Example.Test ' );
my $Data = $Ticket->_PostmasterTicketDataResolve(%New);
ok( $Data, 'new incoming email resolves successfully' );
is( $Data->{customer_id}, 1, 'sender email identifies the customer' );
is( $Data->{customer_user_id}, 8, 'sender email identifies the customer contact' );
my %Expected = (
    service_id => 7, sla_id => 21, sla_source => 'sla', sla_assignment_source => 'customer',
    sla_name_snapshot => 'ERP-SLA-M', sla_calendar_id => 4, sla_update_mode => 'regular',
    sla_first_response_minutes => 120, sla_update_minutes => 60, sla_solution_minutes => 1440,
);
for my $Key ( sort keys %Expected ) {
    is( $Data->{$Key}, $Expected{$Key}, "single customer assignment stores $Key" );
}

$DB->{Services} = [];
$Data = $Ticket->_PostmasterTicketDataResolve(%New);
is( $Data->{sla_source}, 'queue', 'no valid assignment uses queue escalation settings' );
ok( !$Data->{service_id} && !$Data->{sla_id}, 'no unrelated service or SLA is assigned' );

$DB->{Services} = [ $Service, { %{$Service}, id => 8, sla_id => 22 } ];
$Data = $Ticket->_PostmasterTicketDataResolve(%New);
is( $Data->{sla_source}, 'queue', 'multiple valid assignments do not select an arbitrary service' );
ok( !$Data->{service_id}, 'ambiguous service remains unassigned' );

$DB->{Services} = [$Service];
$DB->{Lookups} = 0;
$Data = $Ticket->_PostmasterTicketDataResolve( %New, FromEmail => 'unknown@example.test' );
ok( !$Data->{customer_id} && !$Data->{service_id}, 'unknown senders do not inherit customer services' );
is( $DB->{Lookups}, 0, 'unknown senders do not query customer assignments' );

for my $Override ( { CustomerID => 1 }, { CustomerUserID => 8 } ) {
    $Data = $Ticket->_PostmasterTicketDataResolve(
        %New, FromEmail => 'unknown@example.test', PostmasterResult => $Override,
    );
    is( $Data->{service_id}, 7, 'postmaster customer identification also resolves its single assignment' );
}
$Data = $Ticket->_PostmasterTicketDataResolve( %New, PostmasterResult => { CustomerID => 2 } );
ok( !$Data->{service_id}, 'customer assignments are scoped to the selected customer' );

$DB->{Lookups} = 0;
$Data = $Ticket->_PostmasterTicketDataResolve( %New, PostmasterResult => { ServiceClear => 1 } );
is( $Data->{sla_source}, 'queue', 'explicit postmaster service clearing takes precedence' );
is( $DB->{Lookups}, 0, 'explicit clearing bypasses automatic assignment' );
$Data = $Ticket->_PostmasterTicketDataResolve( %New, PostmasterResult => { SLAID => 99 } );
is( $Data->{sla_id}, 99, 'explicit postmaster SLA takes precedence over customer auto-assignment' );
is( $Data->{sla_assignment_source}, 'filter', 'explicit SLA retains its filter source' );
$Data = $Ticket->_PostmasterTicketDataResolve( %New, PostmasterResult => { ServiceID => 9 } );
is( $Data->{service_id}, 9, 'explicit postmaster service takes precedence' );
$Data = $Ticket->_PostmasterTicketDataResolve( %New, PostmasterResult => { CustomerClear => 1 } );
ok( !$Data->{customer_id} && !$Data->{service_id}, 'clearing the customer does not reuse the sender assignment' );

my %Existing = (
    queue_id => 2, state_id => 1, priority_id => 3, customer_id => 1, customer_user_id => 8,
    %Expected, sla_name_snapshot => 'Agreed snapshot', sla_first_response_minutes => 90,
);
$DB->{Services} = [ { %{$Service}, first_response_minutes => 15 } ];
$DB->{Lookups} = 0;
$Data = $Ticket->_PostmasterTicketDataResolve( IsNew => 0, Ticket => \%Existing );
is( $Data->{sla_first_response_minutes}, 90, 'ordinary replies retain the agreed SLA snapshot' );
is( $Data->{sla_name_snapshot}, 'Agreed snapshot', 'ordinary replies retain the stored SLA name' );
is( $DB->{Lookups}, 0, 'existing tickets are not silently reclassified on reply' );

my $Unassigned = { %Existing, %{ $Ticket->_PostmasterQueueSLASnapshot() } };
$Data = $Ticket->_PostmasterTicketDataResolve( IsNew => 0, Ticket => $Unassigned );
ok( !$Data->{service_id}, 'ordinary replies preserve an existing unassigned service' );

$DB->{Fail} = 1;
$Data = $Ticket->_PostmasterTicketDataResolve(%New);
ok( !$Data, 'database lookup failures stop creation instead of silently dropping the SLA' );
is( $Ticket->Error(), 'Customer service lookup failed', 'lookup failure is reported to the mail importer' );

done_testing();
