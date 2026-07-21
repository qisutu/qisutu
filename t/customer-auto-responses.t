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

use QisutuCustomerAutoResponse;
use QisutuMail;

my @Type = map { $_->{type} } @{ QisutuCustomerAutoResponse->ResponseTypes() };
is_deeply(
    \@Type,
    [ qw(customer_ticket_created customer_ticket_reply incoming_email_rejected closed_ticket_follow_up) ],
    'only the four agreed customer-originated events are available',
);

my %Placeholder = map { ( $_->{placeholder} || '' ) => 1 } @{ QisutuCustomerAutoResponse->PlaceholderList() };
ok( $Placeholder{'{{CustomerUser.Firstname}}'}, 'customer-user placeholders are offered' );
ok( $Placeholder{'{{Ticket.LinkHTML}}'}, 'customer ticket link placeholder is offered' );
ok( $Placeholder{'{{Incoming.Subject}}'}, 'incoming-mail placeholders are offered for rejection responses' );
ok( !$Placeholder{'{{Agent.FullName}}'}, 'irrelevant agent-recipient placeholders are not offered' );

{
    package Local::CustomerAutoResponseDB;

    sub new {
        return bless { Event => {}, Updated => [] }, shift;
    }

    sub Error {
        return '';
    }

    sub Do {
        my ( $Self, $SQL, @Bind ) = @_;

        if ( $SQL =~ m{INSERT\s+IGNORE\s+INTO\s+customer_auto_response_event_log}si ) {
            $Self->{Event}->{ $Bind[0] . '|' . $Bind[4] } = 1;
        }
        if ( $SQL =~ m{UPDATE\s+customer_auto_response_template}si ) {
            push @{ $Self->{Updated} }, \@Bind;
        }
        return 1;
    }

    sub SelectAll {
        return [];
    }

    sub SelectRow {
        my ( $Self, $SQL, @Bind ) = @_;

        if ( $SQL =~ m{FROM\s+customer_auto_response_template}si ) {
            my $Type = $Bind[0] || '';
            return {
                response_type => $Type,
                name          => 'Test response',
                subject       => $Type eq 'incoming_email_rejected'
                    ? 'Nicht angenommen: {{Incoming.Subject}}'
                    : 'Empfangen: {{Ticket.Number}} – {{Ticket.Title}}',
                body_html     => $Type eq 'incoming_email_rejected'
                    ? '<p>{{Incoming.FromName}}: {{Incoming.Subject}}</p>'
                    : '<p>Hallo {{CustomerUser.Firstname}}</p><p>{{Ticket.LinkHTML}}</p>',
                active        => 1,
            };
        }

        if ( $SQL =~ m{FROM\s+customer_auto_response_event_log}si ) {
            return $Self->{Event}->{ $Bind[0] . '|' . $Bind[1] } ? { id => 1 } : undef;
        }

        if ( $SQL =~ m{FROM\s+ticket\s+t}si ) {
            return {
                id                        => 42,
                ticket_number             => '2026000042',
                title                     => 'Drucker & Scanner',
                queue_id                  => 1,
                queue_name                => 'Posteingang',
                queue_full_name           => 'Support::Posteingang',
                state_name                => 'Offen',
                priority_name             => '3 normal',
                customer_name             => 'Beispiel GmbH',
                customer_number           => 'K-100',
                customer_user_login       => 'klara',
                customer_user_email       => 'klara@example.test',
                customer_user_firstname   => 'Klara',
                customer_user_lastname    => 'Kundin',
                system_email_name         => 'Qisutu Support',
                system_email              => 'support@example.test',
            };
        }

        if ( $SQL =~ m{FROM\s+smtp_account}si ) {
            return {
                id            => 1,
                active        => 1,
                smtp_host     => 'smtp.example.test',
                smtp_username => 'mailer@example.test',
            };
        }

        if ( $SQL =~ m{FROM\s+system_setting}si ) {
            return;
        }

        die "Unexpected SelectRow SQL in customer-auto-response test: $SQL";
    }
}

my $Config = {
    Paths => {
        Config        => File::Spec->catdir( $FindBin::Bin, '..', 'core', 'config' ),
        SettingConfig => File::Spec->catdir( $FindBin::Bin, '..', 'core', 'config', 'settings' ),
    },
    System => {
        Name       => 'Qisutu Test',
        BaseURL    => 'https://support.example.test/qisutu',
        TicketHook => 'Qisutu',
    },
    Language => { Default => 'de' },
};
my $DB = Local::CustomerAutoResponseDB->new();
my @Sent;

{
    no warnings 'redefine';
    local *QisutuMail::SMTPSend = sub {
        my ( $Self, %Param ) = @_;
        push @Sent, \%Param;
        return { Success => 1, Message => 'sent' };
    };

    my $Response = QisutuCustomerAutoResponse->new( Config => $Config, DB => $DB );
    ok(
        $Response->TemplateUpdate(
            ResponseType   => 'customer_ticket_reply',
            Subject        => 'Antwort {{Ticket.Number}}',
            BodyHTML       => '<p>Empfangen</p><script>alert(1)</script>',
            Active         => 1,
            ChangedByUserID => 9,
        ),
        'administrator can activate and edit an individual event template',
    );
    is( $DB->{Updated}->[-1]->[2], 1, 'active flag is persisted for the selected event' );
    unlike( $DB->{Updated}->[-1]->[1], qr{script}, 'CKEditor HTML is sanitized before storage' );

    ok(
        $Response->Send(
            ResponseType => 'customer_ticket_created',
            TicketID     => 42,
            ArticleID    => 7,
        ),
        'active ticket-created response is sent',
    );

    is( scalar @Sent, 1, 'exactly one email is sent for the event' );
    like( $Sent[0]->{Subject}, qr{\A\[Qisutu\#2026000042\]}, 'customer response subject contains a reply-safe ticket reference' );
    like( $Sent[0]->{Body}, qr{Hallo Klara}, 'customer placeholder is rendered in the email body' );
    like( $Sent[0]->{Body}, qr{Page=CustomerTicketZoom&amp;TicketID=42}, 'ticket link points to the customer portal' );
    unlike( $Sent[0]->{Body}, qr{Page=AgentTicketZoom}, 'customer email never exposes an agent ticket link' );

    ok(
        !$Response->Send(
            ResponseType => 'customer_ticket_created',
            TicketID     => 42,
            ArticleID    => 7,
        ),
        'the same article event is not sent twice',
    );
    like( $Response->Error(), qr{already sent}, 'duplicate suppression is reported clearly' );
    is( scalar @Sent, 1, 'duplicate attempt does not call SMTP again' );

    ok(
        $Response->Send(
            ResponseType      => 'incoming_email_rejected',
            RecipientName     => 'Max Mustermann',
            RecipientEmail    => 'max@example.test',
            IncomingSubject   => 'Unerlaubte Anfrage',
            IncomingFromName  => 'Max Mustermann',
            IncomingFromEmail => 'max@example.test',
            IncomingToEmail   => 'support@example.test',
            ReplyToEmail      => 'support@example.test',
            EventKey          => 'reject:mailbox-1:uid-99',
            Headers           => { 'auto-submitted' => 'no' },
        ),
        'explicit postmaster rejection response is sent',
    );
    like( $Sent[1]->{Subject}, qr{Nicht angenommen: Unerlaubte Anfrage}, 'incoming subject placeholder is rendered' );

    ok(
        !$Response->Send(
            ResponseType      => 'incoming_email_rejected',
            RecipientEmail    => 'robot@example.test',
            IncomingFromEmail => 'robot@example.test',
            Headers           => { 'auto-submitted' => 'auto-generated' },
            EventKey          => 'reject:mailbox-1:uid-100',
        ),
        'automatic senders do not receive rejection responses',
    );
    like( $Response->Error(), qr{suppressed}, 'automatic-sender suppression is reported' );
    is( scalar @Sent, 2, 'suppressed automatic message does not call SMTP' );
}

my $Root = File::Spec->catdir( $FindBin::Bin, '..' );
my $TicketSource = _Read( File::Spec->catfile( $Root, 'core', 'system', 'QisutuTicket.pm' ) );
my ($AgentCreate) = $TicketSource =~ m{sub\s+TicketCreateFromAgent\b(.*?)^sub\s+}ms;
unlike( $AgentCreate || '', qr{_CustomerAutoResponseSend}, 'agent-created tickets do not trigger an extra customer auto-response' );

my ($CustomerCreate) = $TicketSource =~ m{sub\s+TicketCreateFromCustomer\b(.*?)^sub\s+TicketCreateFromAgent\b}ms;
like( $CustomerCreate || '', qr{customer_ticket_created}, 'customer-created tickets trigger the receipt event' );

my ($EmailReply) = $TicketSource =~ m{sub\s+_TicketReplyCreateFromEmail\b(.*?)^sub\s+_PostmasterTicketDataResolve\b}ms;
like( $EmailReply || '', qr{closed_ticket_follow_up}, 'email replies to closed tickets use the dedicated event' );
like( $EmailReply || '', qr{customer_ticket_reply}, 'ordinary customer email replies use the receipt event' );

my $AdminTemplate = _Read( File::Spec->catfile( $Root, 'core', 'output', 'AdminCustomerAutoResponses.tt' ) );
like( $AdminTemplate, qr{qisutu-richtext}, 'each automatic-response edit view uses CKEditor' );
like( $AdminTemplate, qr{PlaceholderList}, 'the edit view presents its placeholder list' );

my $Release = _Read( File::Spec->catfile( $Root, 'release.conf' ) );
like( $Release, qr{^version=0[.]0[.]74$}m, 'automatic responses are included in the current program release' );
like( $Release, qr{^database_version=0[.]0[.]26$}m, 'automatic responses have their own database migration' );

my $Migration = _Read( File::Spec->catfile( $Root, 'install', 'update', 'database', '0.0.26', '001-create-customer-auto-responses.sql' ) );
like( $Migration, qr{customer_auto_response_template}, 'upgrade migration creates automatic-response templates' );
like( $Migration, qr{customer_auto_response_event_log}, 'upgrade migration creates duplicate-prevention log' );

sub _Read {
    my ($File) = @_;
    open my $Handle, '<:encoding(UTF-8)', $File or die "Could not read $File: $!";
    local $/;
    my $Content = <$Handle>;
    close $Handle;
    return $Content;
}

done_testing();
