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

use File::Path qw(make_path);
use File::Spec;
use File::Temp qw(tempdir);
use FindBin;
use Test::More;

use lib File::Spec->catdir( $FindBin::Bin, '..', 'core', 'config' );
use lib File::Spec->catdir( $FindBin::Bin, '..', 'core', 'system' );
use lib File::Spec->catdir( $FindBin::Bin, '..', 'core', 'output' );

use QisutuAddonAPI;
use QisutuAddonEvent;
use QisutuAddonREST;
use QisutuAddonUI;
use QisutuAPIAuth;
use QisutuOutput;

BEGIN {
    package Qisutu::Addon::Test::Service;
    sub new { my ( $Class, %Param ) = @_; return bless \%Param, $Class }
    sub Ping { return 'service-ok' }
    $INC{'Qisutu/Addon/Test/Service.pm'} = __FILE__;

    package Qisutu::Addon::Test::Event;
    our @Handled;
    sub new { my ( $Class, %Param ) = @_; return bless \%Param, $Class }
    sub Handle {
        my ( $Self, %Param ) = @_;
        push @Handled, { %Param };
        return { success => 1, event => $Param{Event} };
    }
    $INC{'Qisutu/Addon/Test/Event.pm'} = __FILE__;

    package Qisutu::Addon::Test::REST;
    sub new { my ( $Class, %Param ) = @_; return bless \%Param, $Class }
    sub Handle {
        my ( $Self, %Param ) = @_;
        return { Status => 200, Data => { item_id => $Param{PathParameters}->{item_id} } };
    }
    $INC{'Qisutu/Addon/Test/REST.pm'} = __FILE__;

    package Qisutu::Addon::Test::UI;
    sub new { my ( $Class, %Param ) = @_; return bless \%Param, $Class }
    sub Render { return { Template => 'AddonAPITest.tt', Data => { AddonMessage => 'UI-Slot aktiv' } } }
    $INC{'Qisutu/Addon/Test/UI.pm'} = __FILE__;

    package Local::AddonEventDB;
    sub new { return bless { Rows => [], Error => '' }, shift }
    sub Error { return $_[0]->{Error} }
    sub Do {
        my ( $Self, $SQL, @Bind ) = @_;
        if ( $SQL =~ m{INSERT INTO addon_event_queue} ) {
            push @{ $Self->{Rows} }, {
                id => 1 + @{ $Self->{Rows} }, package_identifier => $Bind[0],
                event_name => $Bind[1], event_source => $Bind[2], handler_class => $Bind[3],
                handler_method => $Bind[4], payload_json => $Bind[5], status => 'pending', attempts => 0,
            };
        }
        elsif ( $SQL =~ m{SET status = "processing"} ) {
            my ($Row) = grep { $_->{id} == $Bind[1] } @{ $Self->{Rows} };
            $Row->{status} = 'processing';
        }
        elsif ( $SQL =~ m{SET status = "completed"} ) {
            my ($Row) = grep { $_->{id} == $Bind[1] } @{ $Self->{Rows} };
            $Row->{status} = 'completed';
            $Row->{result_json} = $Bind[0];
        }
        return 1;
    }
    sub SelectRow {
        my ( $Self, $SQL ) = @_;
        return ( grep { $_->{status} eq 'pending' } @{ $Self->{Rows} } )[0]
            if $SQL =~ m{FROM addon_event_queue};
        return;
    }

    package Local::ScopeAuth;
    sub new { return bless {}, shift }
    sub ScopeAllowed {
        my ( $Self, %Param ) = @_;
        return scalar grep { $_ eq $Param{Scope} } @{ $Param{Token}->{scopes} || [] };
    }
}

my $Root = File::Spec->catdir( $FindBin::Bin, '..' );
my $Temporary = tempdir( CLEANUP => 1 );
my $TemplatePath = File::Spec->catdir( $Temporary, 'templates' );
make_path($TemplatePath);
open my $TemplateHandle, '>:encoding(UTF-8)', File::Spec->catfile( $TemplatePath, 'AddonAPITest.tt' )
    or die "Cannot create test template: $!";
print {$TemplateHandle} '<aside class="addon-api-test">[% AddonMessage %]</aside>';
close $TemplateHandle;

my $DB = Local::AddonEventDB->new();
my $Config = {
    RootPath => $Root,
    System   => { Version => '0.0.79' },
    Language => { Default => 'de' },
    Paths    => {
        Output   => File::Spec->catdir( $Root, 'core', 'output' ),
        Language => File::Spec->catdir( $Root, 'core', 'language' ),
    },
    AddonRuntime => {
        APIVersion => '1.0',
        Capabilities => [qw(services.v1 events.v1 rest-routes.v1 ui-slots.v1)],
        TemplatePaths => [$TemplatePath],
        Services => [{
            package_identifier => 'example.api', key => 'test.service',
            class => 'Qisutu::Addon::Test::Service',
        }],
        EventSubscribers => [{
            package_identifier => 'example.api', key => 'test-event', event => 'ticket.*',
            class => 'Qisutu::Addon::Test::Event', method => 'Handle', mode => 'async',
        }],
        RESTRoutes => [{
            package_identifier => 'example.api', key => 'test-rest', method => 'GET',
            path => '/v1/addons/example.api/items/{item_id}', class => 'Qisutu::Addon::Test::REST',
            handler_method => 'Handle', scopes => ['example.read'], access_types => ['agent'],
        }],
        UISlots => [{
            package_identifier => 'example.api', key => 'test-ui', slot => 'admin.after',
            class => 'Qisutu::Addon::Test::UI', method => 'Render', access_types => ['agent'],
        }],
    },
};

my $API = QisutuAddonAPI->new( Config => $Config, DB => $DB, Identifier => 'example.api' );
is( $API->Version(), '1.0', 'the internal add-on API has a stable version' );
ok( $API->CapabilityAvailable( Capability => 'services.v1' ), 'add-ons can test individual API capabilities' );
ok( !$API->CapabilityAvailable( Capability => 'future.v9' ), 'unknown future capabilities are reported as unavailable' );
my $Service = $API->ServiceGet( Service => 'test.service' );
isa_ok( $Service, 'Qisutu::Addon::Test::Service' );
is( $Service->Ping(), 'service-ok', 'a registered add-on service is loaded through the stable API' );
is( $API->ServiceGet( Service => 'test.service' ), $Service, 'service objects are reused within one runtime' );

my $Event = QisutuAddonEvent->new( Config => $Config, DB => $DB );
ok( $Event->Emit( Event => 'ticket.created', Source => 'qisutu.core', Payload => { ticket_id => 42 } ), 'a matching core event is queued' );
is( scalar @{ $DB->{Rows} }, 1, 'the asynchronous event is persisted once per subscriber' );
ok( $Event->Emit( Event => 'mail.sent', Source => 'qisutu.core', Payload => {} ), 'an event without a subscriber is harmless' );
is( scalar @{ $DB->{Rows} }, 1, 'unmatched events do not create queue entries' );
ok( $Event->ProcessNext( Worker => 'test-worker' ), 'the daemon event processor invokes the isolated handler' );
is( $DB->{Rows}->[0]->{status}, 'completed', 'a successful event is marked completed' );
is( $Qisutu::Addon::Test::Event::Handled[0]->{Payload}->{ticket_id}, 42, 'the handler receives the structured payload' );

my $AddonREST = QisutuAddonREST->new( Config => $Config, DB => $DB, Auth => Local::ScopeAuth->new() );
my $Denied = $AddonREST->Dispatch(
    Method => 'GET', Path => '/v1/addons/example.api/items/17', Token => { account_type => 'agent', scopes => [] }, RequestID => 'test',
);
is( $Denied->{Status}, 403, 'an add-on REST route enforces its declared token scope' );
my $RESTResult = $AddonREST->Dispatch(
    Method => 'GET', Path => '/v1/addons/example.api/items/17', Token => { account_type => 'agent', scopes => ['example.read'] }, RequestID => 'test',
);
is( $RESTResult->{Status}, 200, 'an authorized add-on REST route is dispatched' );
is( $RESTResult->{Body}->{data}->{item_id}, 17, 'safe path parameters are passed to the route handler' );
ok( !$AddonREST->Dispatch( Method => 'GET', Path => '/v1/addons/example.api/unknown', Token => {} ), 'unregistered paths remain available to the core 404 response' );

my $Output = QisutuOutput->new( Config => $Config );
my $UI = QisutuAddonUI->new( Config => $Config, DB => $DB, Output => $Output );
my $HTML = $UI->Render(
    Slot => 'admin.after', Program => { Name => 'AdminAddons' },
    User => { account_type => 'agent' }, Data => { Language => 'de' },
);
like( $HTML, qr{UI-Slot aktiv}, 'a registered UI slot renders through an isolated add-on template' );
is( $UI->Render( Slot => 'unknown.position', Program => {}, User => {}, Data => {} ), '', 'unknown UI slots cannot inject output' );

my $Auth = QisutuAPIAuth->new( Config => $Config, DB => $DB );
my %Scope = map { $_->{Key} => $_ } @{ $Auth->ScopeDefinitions() };
ok( $Scope{'example.read'}, 'add-on REST scopes are offered by the normal API token administration' );
is( $Scope{'example.read'}->{Group}, 'addons', 'add-on scopes remain visibly separated from core scopes' );

my $TicketSource = _ReadRaw( File::Spec->catfile( $Root, 'core', 'system', 'QisutuTicket.pm' ) );
for my $EventName (qw(ticket.created article.created ticket.state_changed ticket.queue_changed ticket.priority_changed ticket.service_changed ticket.customer_changed ticket.owner_changed ticket.responsible_changed mail.received)) {
    like( $TicketSource, qr{\Q$EventName\E}, "the core publishes $EventName" );
}
my $MailSource = _ReadRaw( File::Spec->catfile( $Root, 'core', 'system', 'QisutuMail.pm' ) );
like( $MailSource, qr{mail[.]sent}, 'successful SMTP delivery publishes mail.sent without exposing message bodies' );

done_testing();

sub _ReadRaw {
    my ($Path) = @_;
    open my $Handle, '<:raw', $Path or die "Cannot read $Path: $!";
    local $/;
    my $Content = <$Handle>;
    close $Handle;
    return defined $Content ? $Content : '';
}
