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
use JSON::PP;
use Test::More;
use lib "$FindBin::Bin/../core/config", "$FindBin::Bin/../core/system", "$FindBin::Bin/../core/output";
use QisutuConfig;
use QisutuOutput;
use QisutuSystemSetting;
use QisutuTicketForm;

# Run the actual public CGI and add-on loader. Only database, rendering and
# ticket persistence are replaced; the process module must be found on disk.
BEGIN { $INC{'QisutuDB.pm'} = __FILE__ }
{
    package QisutuDB;
    our $Instance;
    sub new { return $Instance }
}
{
    package Local::PublicFormDB;
    sub Error { return '' }
    sub SelectAll {
        my ( $Self, $SQL ) = @_;
        die "Unexpected query: $SQL" if $SQL !~ m{FROM addon_package};
        $Self->{RuntimeLookups}++;
        return $Self->{Package}->{active} ? [ $Self->{Package} ] : [];
    }
}
{
    package Local::PublicFormTicket;
    sub ArticleCreate {
        my ( $Self, %Param ) = @_;
        push @{ $Self->{Articles} }, \%Param;
        return 99;
    }
}

my $Root = tempdir( CLEANUP => 1 );
my $AddonRoot = File::Spec->catdir( $Root, 'addons' );
my $Installed = File::Spec->catdir( $AddonRoot, 'de.qisutu.kim-processes', '1.0.1' );
my $Library = File::Spec->catdir( $Installed, 'lib' );
my $ModuleDirectory = File::Spec->catdir( $Library, 'Qisutu', 'Addon', 'KimProcesses' );
make_path($ModuleDirectory);
my $ModuleFile = File::Spec->catfile( $ModuleDirectory, 'Runtime.pm' );
open my $ModuleFH, '>:raw', $ModuleFile or die $!;
print {$ModuleFH} <<'MODULE';
package Qisutu::Addon::KimProcesses::Runtime;
use strict;
use warnings;
sub new { my ( $Class, %Param ) = @_; return bless \%Param, $Class }
sub Start {
    my ( $Self, %Param ) = @_;
    push @{ $Self->{DB}->{Starts} }, \%Param;
    return 77;
}
sub InstanceGet { return { id => 77, status => 'active' } }
sub Error { return '' }
1;
MODULE
close $ModuleFH;

my $Config = { RootPath => $Root, Paths => { Addons => $AddonRoot }, Language => { Default => 'en' } };
my $Package = {
    package_identifier => 'de.qisutu.kim-processes', version => '1.0.1',
    installed_path => $Installed, active => 1, status => 'installed',
    manifest_json => JSON::PP->new->encode({ id => 'de.qisutu.kim-processes' }),
};
my $DB = bless { Package => $Package, Starts => [] }, 'Local::PublicFormDB';
my $Ticket = bless { Articles => [] }, 'Local::PublicFormTicket';
my $Program = File::Spec->rel2abs( "$FindBin::Bin/../bin/cgi-bin/form.pl" );
my @Rendered;

ok( !exists $INC{'Qisutu/Addon/KimProcesses/Runtime.pm'}, 'process module is not preloaded by the test' );
ok( !grep( { $_ eq $Library } @INC ), 'fresh public request has no add-on library path' );
{
    no warnings 'redefine';
    local @INC = @INC;
    local %ENV = %ENV;
    $ENV{QISUTU_HOME} = $Root;
    $ENV{GATEWAY_INTERFACE} = '';
    $ENV{REQUEST_METHOD} = 'POST';
    $ENV{QUERY_STRING} = 'Form=demo&Step=PublicTicketFormSubmit';
    $ENV{CONTENT_LENGTH} = 0;
    local $QisutuDB::Instance = $DB;
    local *QisutuConfig::Load = sub { return $Config };
    local *QisutuSystemSetting::AttachmentMaxSizeMB = sub { return 50 };
    local *QisutuTicketForm::FormGet = sub {
        return { id => 1, active => 1, form_type => 'public', title => 'Demo', process_template_id => 5 };
    };
    local *QisutuTicketForm::FormTranslationList = sub { return { en => { title => 'Demo' } } };
    local *QisutuTicketForm::SubmissionCreate = sub {
        my ($Self) = @_;
        $Self->_ProcessAutoStart(
            Form => $Self->FormGet(), TicketID => 44,
            TicketObject => $Ticket, Language => 'en',
        );
        return { TicketID => 44, TicketNumber => '202611060044', ConfirmationText => 'Created' };
    };
    local *QisutuAddonManager::PackageGet = sub { return $Package };
    local *QisutuAddonManager::SettingsGet = sub { return { enabled => 1, kim_api_token => 'test-token' } };
    local *QisutuOutput::RenderSingle = sub {
        my ( $Self, %Param ) = @_;
        push @Rendered, $Param{Data};
        return $Param{Data}->{Success} ? 'Created' : 'Form';
    };

    my $Response = '';
    {
        open my $ResponseFH, '>', \$Response or die $!;
        local *STDOUT = $ResponseFH;
        do $Program;
        die $@ if $@;
    }
    like( $Response, qr{200 OK}, 'public form returns a successful HTTP response' );
    ok( $Rendered[0]->{Success}, 'submission confirmation is rendered' );
    is( $DB->{RuntimeLookups}, 1, 'CGI initializes installed add-ons before submitting the form' );
    is_deeply( $DB->{Starts}, [ { TicketID => 44, TemplateID => 5, Token => 'test-token', UserID => 1 } ],
        'assigned process starts once for the submitted ticket' );
    is_deeply( $Ticket->{Articles}, [], 'successful dynamic module loading produces no failure note' );
    is( $INC{'Qisutu/Addon/KimProcesses/Runtime.pm'}, $ModuleFile, 'runtime was loaded from the installed add-on' );
    is_deeply( $Config->{AddonRuntime}->{LibraryPaths}, [$Library], 'configured installation path is registered' );

    # The same entry point remains usable when the package is disabled.
    $Package->{active} = 0;
    $Response = '';
    {
        open my $ResponseFH, '>', \$Response or die $!;
        local *STDOUT = $ResponseFH;
        main();
    }
    like( $Response, qr{200 OK}, 'disabled add-on does not prevent ticket submission' );
    is( scalar @{ $DB->{Starts} }, 1, 'disabled add-on is not started again' );
    is_deeply( $Config->{AddonRuntime}->{Packages}, [], 'disabled package is not registered' );
}

done_testing();
