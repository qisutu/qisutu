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
use FindBin;
use Test::More;
use lib "$FindBin::Bin/../core/system", "$FindBin::Bin/../core/cpan-lib";
use QisutuTicketForm;

# Exercise the real form validation, contact lookup and ticket insertion.
# External effects are captured so the tests need no installed database or SMTP.
{
    package Local::FormAssignmentDB;
    sub new { return bless { Writes => [], Lookups => [], FormType => 'public' }, shift }
    sub Error { return '' }
    sub BeginWork { return 1 }
    sub Commit { $_[0]->{Committed} = 1; return 1 }
    sub Rollback { $_[0]->{RolledBack} = 1; delete $_[0]->{Ticket}; return 1 }
    sub LastInsertID { return $_[1] eq 'ticket' ? 81 : 91 }
    sub SelectRow {
        my ( $Self, $SQL, @Bind ) = @_;
        return { id => 4 } if $SQL =~ m{FROM ticket_queue};
        if ( $SQL =~ m{FROM customer_user cu} ) {
            push @{ $Self->{Lookups} }, $Bind[0];
            return if $Bind[0] ne 'contact@example.test';
            return { customer_id => 2, customer_user_id => 17 };
        }
        die "Unexpected SelectRow: $SQL";
    }
    sub Do {
        my ( $Self, $SQL, @Bind ) = @_;
        die "Unexpected write: $SQL"
            if $SQL !~ m{\AINSERT INTO (?:ticket|ticket_form_submission|ticket_form_submission_value) \(};
        push @{ $Self->{Writes} }, [ $SQL, @Bind ];
        if ( $SQL =~ m{\AINSERT INTO ticket \(} ) {
            $Self->{Ticket} = {
                customer_id => $Bind[5], customer_user_id => $Bind[6],
                created_by_user_id => $Bind[7], changed_by_user_id => $Bind[8],
            };
        }
        return 1;
    }
}

{
    no warnings 'redefine';
    local *QisutuTicketForm::FormGet = sub {
        my ($Self) = @_;
        return {
            id => 7, active => 1, form_type => $Self->{DB}->{FormType},
            queue_id => 4, title => 'Request', internal_name => 'Request',
            require_consent => 1,
        };
    };
    local *QisutuTicketForm::FormListForCustomer = sub { return [ { id => 7 } ] };
    local *QisutuTicketForm::FieldList = sub {
        return [
            { id => 1, field_key => 'name', field_type => 'name', is_required => 1 },
            { id => 2, field_key => 'email', field_type => 'email', is_required => 1 },
            { id => 3, field_key => 'body', field_type => 'body', is_required => 1 },
        ];
    };
    local *QisutuTicket::_DefaultStateID = sub { return 1 };
    local *QisutuTicket::_DefaultPriorityID = sub { return 3 };
    local *QisutuTicket::_TicketNumberCreate = sub { return '202611060001' };
    local *QisutuTicket::_QueueAddress = sub { return ( 'Support', 'support@example.test' ) };
    local *QisutuTicket::ArticleCreate = sub {
        my ( $Self, %Param ) = @_;
        return if $Self->{DB}->{FailArticle};
        $Self->{DB}->{Article} = \%Param;
        return 82;
    };
    local *QisutuChecklist::TicketAutoCreate = sub {
        my ($Self) = @_;
        $Self->{DB}->{ChecklistAssignment} = { %{ $Self->{DB}->{Ticket} } };
        return 1;
    };
    local *QisutuTicket::_AgentNotificationSend = sub {
        my ($Self) = @_;
        die 'Notification before commit' if !$Self->{DB}->{Committed};
        $Self->{DB}->{NotificationAssignment} = { %{ $Self->{DB}->{Ticket} } };
        return 1;
    };
    local *QisutuTicket::_CustomerAutoResponseSend = sub { return 1 };

    my %Request = (
        FormField_1 => 'Submitted name', FormField_2 => 'contact@example.test',
        FormField_3 => 'Help please', FormConsent => '1',
    );
    for my $Email ( 'contact@example.test', '  CONTACT@Example.Test  ', 'unknown@example.test' ) {
        my $DB = Local::FormAssignmentDB->new();
        my $Form = QisutuTicketForm->new( DB => $DB );
        my $Result = $Form->SubmissionCreate(
            FormID => 7, Context => 'public',
            Request => { %Request, FormField_2 => $Email, CustomerID => 999, CustomerUserID => 999 },
        );
        ok( $Result && $Result->{TicketID} == 81, "public form creates a ticket for $Email" );
        my $Known = $Email ne 'unknown@example.test';
        my $Expected = {
            customer_id => $Known ? 2 : undef,
            customer_user_id => $Known ? 17 : undef,
            created_by_user_id => 1, changed_by_user_id => 1,
        };
        is_deeply( $DB->{Ticket}, $Expected, 'ticket persists both matching IDs and keeps the system author' );
        is_deeply( $DB->{ChecklistAssignment}, $Expected, 'customer is assigned before automatic checklists run' );
        is_deeply( $DB->{NotificationAssignment}, $Expected, 'notifications see the committed assignment' );
        my $Normalized = $Known ? 'contact@example.test' : 'unknown@example.test';
        is_deeply( $DB->{Lookups}, [ $Normalized ], 'lookup normalizes case and whitespace' );
        is( $DB->{Article}->{FromName}, 'Submitted name', 'article retains submitted sender name' );
        is( $DB->{Article}->{CreatedByUserID}, 1, 'public form does not impersonate the contact account' );
        my $Snapshot = $DB->{Writes}->[1];
        is( $Snapshot->[6], 'webform', 'submission remains a public webform' );
        is( $Snapshot->[7], 'Submitted name', 'submission snapshot retains sender name' );
        my $Trimmed = $Email;
        $Trimmed =~ s{\A\s+|\s+\z}{}g;
        is( $DB->{Article}->{FromEmail}, $Trimmed, 'article retains submitted sender email' );
        is( $Snapshot->[8], $Trimmed, 'submission snapshot retains sender email' );
    }

    for my $Invalid ( { FormField_2 => 'invalid' }, { FormConsent => '' }, { Website => 'spam' } ) {
        my $DB = Local::FormAssignmentDB->new();
        my $Form = QisutuTicketForm->new( DB => $DB );
        $Form->SubmissionCreate( FormID => 7, Context => 'public', Request => { %Request, %{$Invalid} } );
        is_deeply( $DB->{Lookups}, [], 'invalid or spam submission does not look up contacts' );
        is_deeply( $DB->{Writes}, [], 'invalid or spam submission creates no ticket' );
    }

    my $DB = Local::FormAssignmentDB->new();
    $DB->{FormType} = 'customer';
    my $Form = QisutuTicketForm->new( DB => $DB );
    ok( $Form->SubmissionCreate(
        FormID => 7, Context => 'customer', Request => \%Request,
        User => {
            customer_id => 5, customer_user_id => 44, user_account_id => 55,
            firstname => 'Portal', lastname => 'User', email => 'portal@example.test',
        },
    ), 'authenticated customer can still submit a customer form' );
    is_deeply( $DB->{Ticket}, {
        customer_id => 5, customer_user_id => 44, created_by_user_id => 55, changed_by_user_id => 55,
    }, 'customer portal keeps the authenticated identity despite a different email in the request' );
    is_deeply( $DB->{Lookups}, [], 'customer portal does not reassign by request email' );

    $DB = Local::FormAssignmentDB->new();
    $DB->{FailArticle} = 1;
    $Form = QisutuTicketForm->new( DB => $DB );
    ok( !$Form->SubmissionCreate( FormID => 7, Context => 'public', Request => \%Request ),
        'article failure rejects the submission' );
    ok( $DB->{RolledBack} && !$DB->{Ticket}, 'failed submission rolls back the assigned ticket' );
    ok( !$DB->{NotificationAssignment}, 'failed submission sends no notification' );
}

done_testing();
