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
use lib File::Spec->catdir( $FindBin::Bin, '..', 'core', 'module' );

use AgentTicketCreate;
use AgentTicketZoom;
use QisutuNotification;

my $Config = {
    Paths    => { Config => File::Spec->catdir( $FindBin::Bin, '..', 'config' ) },
    Language => { Default => 'de' },
    System   => {
        Name       => 'Qisutu Test',
        BaseURL    => 'https://support.example.test/qisutu',
        TicketHook => 'Qisutu',
    },
};

my $PlaceholderList = QisutuNotification->ContentPlaceholderList();
my %Available = map { ( $_->{placeholder} || '' ) => 1 } @{$PlaceholderList};

ok( $Available{'{{CustomerUser.Firstname}}'}, 'salutations can use the customer user firstname' );
ok( $Available{'{{CustomerUser.Lastname}}'}, 'salutations can use the customer user lastname' );
ok( $Available{'{{Agent.FullName}}'}, 'signatures can use the current agent name' );
ok( $Available{'{{Ticket.LinkHTML}}'}, 'content templates can use the ready-made ticket link' );

my $Renderer = QisutuNotification->new( Config => $Config );
my $NewTicketHTML = $Renderer->ContentTemplateRenderHTML(
    HTML => '<p>Hallo {{CustomerUser.Firstname}} {{CustomerUser.Lastname}}</p>'
        . '<p>{{Agent.FullName}} – {{Ticket.Title}}</p>'
        . '<p>{{Ticket.Number}} {{Ticket.Link}} {{Ticket.LinkHTML}}</p>',
    Agent => {
        firstname => 'Ada',
        lastname  => '<Admin>',
        login     => 'ada',
        email     => 'ada@example.test',
    },
    Ticket => {
        title                   => 'Drucker & Scanner',
        customer_user_firstname => 'Klara',
        customer_user_lastname  => 'Kundin',
    },
    PreserveEmptyKeys => [ qw(Ticket.Number Ticket.Link Ticket.LinkHTML) ],
);

like( $NewTicketHTML, qr{Hallo Klara Kundin}, 'known customer placeholders are resolved before ticket creation' );
like( $NewTicketHTML, qr{Ada &lt;Admin&gt;}, 'placeholder values are safely HTML escaped' );
like( $NewTicketHTML, qr{Drucker &amp; Scanner}, 'ticket values are safely HTML escaped' );
like( $NewTicketHTML, qr{\{\{Ticket[.]Number\}\}}, 'ticket number stays available for final resolution after creation' );
like( $NewTicketHTML, qr{\{\{Ticket[.]LinkHTML\}\}}, 'ticket HTML link stays available for final resolution after creation' );

{
    package Local::ContentTemplateDB;

    sub new {
        return bless {}, shift;
    }

    sub Do {
        return 1;
    }

    sub Error {
        return '';
    }

    sub SelectAll {
        return [];
    }

    sub SelectRow {
        my ( $Self, $SQL, @Bind ) = @_;

        if ( $SQL =~ m{FROM\s+ticket_queue\s+q}s ) {
            if ( ( $Bind[0] || '' ) eq 'en' ) {
                return {
                    queue_name         => 'Inbox',
                    queue_full_name    => 'Support::Inbox',
                    salutation_content => '<p>Hello {{CustomerUser.Firstname}}, ticket {{Ticket.Number}}</p>',
                    signature_content  => '<p>Kind regards, {{Agent.FullName}}</p><p>{{Ticket.LinkHTML}}</p>',
                };
            }
            return {
                queue_name         => 'Posteingang',
                queue_full_name    => 'Support::Posteingang',
                salutation_content => '<p>Hallo {{CustomerUser.Firstname}} {{CustomerUser.Lastname}}, Ticket {{Ticket.Number}}</p>',
                signature_content  => '<p>{{Agent.FullName}} | {{Ticket.Queue}}</p><p>{{Ticket.LinkHTML}}</p>',
            };
        }

        if ( $SQL =~ m{FROM\s+customer_user\s+cu}s ) {
            return {
                customer_name              => 'Beispielkunde',
                customer_number            => 'K-100',
                customer_user_login         => 'klara',
                customer_user_email         => 'klara@example.test',
                customer_user_firstname     => 'Klara',
                customer_user_lastname      => 'Kundin',
            };
        }

        if ( $SQL =~ m{FROM\s+ticket_state}s ) {
            return { state_name => 'Offen' };
        }

        if ( $SQL =~ m{FROM\s+ticket_priority}s ) {
            return { priority_name => '3 normal' };
        }

        if ( $SQL =~ m{AS\s+salutation_content.*FROM\s+ticket\s+t}s ) {
            if ( ( $Bind[0] || '' ) eq 'en' ) {
                return {
                    salutation_content => '<p>Hello {{CustomerUser.Firstname}}, ticket {{Ticket.Number}}</p>',
                    signature_content  => '<p>Kind regards, {{Agent.FullName}}</p><p>{{Ticket.LinkHTML}}</p>',
                };
            }
            return {
                salutation_content => '<p>Hallo {{CustomerUser.Firstname}} {{CustomerUser.Lastname}}, Ticket {{Ticket.Number}}</p>',
                signature_content  => '<p>{{Agent.FullName}} | {{Ticket.Queue}}</p><p>{{Ticket.LinkHTML}}</p>',
            };
        }

        if ( $SQL =~ m{FROM\s+ticket\s+t\s+INNER\s+JOIN\s+ticket_queue}s ) {
            return {
                id                        => 42,
                ticket_number             => '2026000042',
                title                     => 'Druckerproblem',
                queue_id                  => 1,
                queue_name                => 'Posteingang',
                queue_full_name           => 'Support::Posteingang',
                state_name                => 'Offen',
                priority_name             => '3 normal',
                customer_name             => 'Beispielkunde',
                customer_number           => 'K-100',
                customer_user_login       => 'klara',
                customer_user_email       => 'klara@example.test',
                customer_user_firstname   => 'Klara',
                customer_user_lastname    => 'Kundin',
                owner_user_id             => 7,
            };
        }

        if ( $SQL =~ m{SELECT\s+id,\s+login,\s+email,\s+firstname,\s+lastname\s+FROM\s+user_account}s ) {
            return {
                id        => $Bind[0] || 7,
                login     => 'ada',
                email     => 'ada@example.test',
                firstname => 'Ada',
                lastname  => 'Agentin',
            };
        }

        if ( $SQL =~ m{FROM\s+system_setting}s ) {
            return;
        }

        die "Unexpected SelectRow SQL in content-template test: $SQL";
    }
}

my $DB = Local::ContentTemplateDB->new();
my $User = {
    user_account_id => 7,
    account_type    => 'agent',
    login           => 'ada',
    email           => 'ada@example.test',
    firstname       => 'Ada',
    lastname        => 'Agentin',
};

my $CreateModule = AgentTicketCreate->new( Config => $Config, DB => $DB );
my $CreateHTML = $CreateModule->_QueueTemplateHTML(
    QueueID        => 1,
    User           => $User,
    CustomerUserID => 9,
    OwnerUserID    => 7,
    Title          => 'Druckerproblem',
    StateID        => 1,
    PriorityID     => 3,
    Language       => 'de',
);

like( $CreateHTML, qr{Hallo Klara Kundin}, 'ticket creation inserts a resolved salutation into the editor template' );
like( $CreateHTML, qr{Ada Agentin [|] Support::Posteingang}, 'ticket creation inserts a resolved signature into the editor template' );
like( $CreateHTML, qr{\{\{Ticket[.]Number\}\}}, 'ticket creation preserves the not-yet-created ticket number' );
like( $CreateHTML, qr{\{\{Ticket[.]LinkHTML\}\}}, 'ticket creation preserves the not-yet-created ticket link' );

my $ZoomModule = AgentTicketZoom->new( Config => $Config, DB => $DB );
my $ZoomHTML = $ZoomModule->_QueueReplyTemplate(
    TicketID => 42,
    User     => $User,
    Language => 'de',
);

like( $ZoomHTML, qr{Hallo Klara Kundin, Ticket 2026000042}, 'ticket zoom resolves salutation and ticket number immediately' );
like( $ZoomHTML, qr{Ada Agentin [|] Support::Posteingang}, 'ticket zoom resolves the current agent in the signature' );
like( $ZoomHTML, qr{https://support[.]example[.]test/qisutu/index[.]pl[?]Page=AgentTicketZoom&amp;TicketID=42}, 'ticket zoom inserts the ticket link' );
unlike( $ZoomHTML, qr{\{\{[A-Za-z0-9_.]+\}\}}, 'ticket zoom leaves no supported placeholder unresolved' );

my $EnglishCreateHTML = $CreateModule->_QueueTemplateHTML(
    QueueID        => 1,
    User           => $User,
    CustomerUserID => 9,
    OwnerUserID    => 7,
    Title          => 'Printer problem',
    StateID        => 1,
    PriorityID     => 3,
    Language       => 'en',
);
like( $EnglishCreateHTML, qr{Hello Klara}, 'ticket creation selects the salutation in the agent language' );
like( $EnglishCreateHTML, qr{Kind regards, Ada Agentin}, 'ticket creation selects the signature in the agent language' );

my $EnglishZoomHTML = $ZoomModule->_QueueReplyTemplate(
    TicketID => 42,
    User     => $User,
    Language => 'en',
);
like( $EnglishZoomHTML, qr{Hello Klara, ticket 2026000042}, 'ticket replies select the salutation in the agent language' );
like( $EnglishZoomHTML, qr{Kind regards, Ada Agentin}, 'ticket replies select the signature in the agent language' );

done_testing();
