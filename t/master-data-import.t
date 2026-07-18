# Qisutu - Open Source Ticket System
# Copyright (C) 2026 Franziska Steps
# SPDX-License-Identifier: AGPL-3.0-or-later

use strict;
use warnings;
use utf8;

use Test::More;
use lib qw(core/system core/output core/module);
use QisutuMasterDataImport;

{
    package Local::MasterImportDB;
    sub new { bless {}, shift }
    sub SelectAll {
        my ( $Self, $SQL, @Bind ) = @_;
        if ( $SQL =~ /FROM user_dynamic_field f/ ) {
            return [] if ( $Bind[-1] || '' ) ne 'customer';
            return [{ id => 7, name => 'asset_tag', label => 'Inventarnummer', field_type => 'text', is_required => 1, sort_order => 100 }];
        }
        return [];
    }
    sub SelectRow { return }
    sub Error { return '' }
}

{
    package Local::MasterImportOutput;
    sub new { bless {}, shift }
    sub Translate { return $_[2] }
}

my $Object = QisutuMasterDataImport->new(
    Config => { Language => { Default => 'de' } },
    DB     => Local::MasterImportDB->new(),
    Output => Local::MasterImportOutput->new(),
);

my $CustomerDefinition = $Object->Definition( Type => 'customer', Language => 'de' );
is_deeply(
    $CustomerDefinition->{Header},
    [qw(customer_number name active dynamic.asset_tag)],
    'customer template contains fixed columns followed by the installation dynamic field',
);

my $Template = $Object->TemplateCSV( Type => 'customer', Language => 'de' );
is( substr( $Template, 0, 1 ), chr(0xFEFF), 'template contains an UTF-8 BOM character' );
like( $Template, qr/"customer_number";"name";"active";"dynamic\.asset_tag"/, 'template contains the exact header' );

my $Valid = $Object->_Analyze(
    Type     => 'customer',
    Language => 'de',
    Content  => "customer_number;name;active;dynamic.asset_tag\r\nK-1000;\"Beispiel; GmbH\";1;INV-1\r\n",
);
is( $Valid->{CreateCount}, 1, 'one valid new customer is recognized' );
is( $Valid->{ErrorCount}, 0, 'quoted semicolon is parsed without an error' );

my $RequiredError = $Object->_Analyze(
    Type     => 'customer',
    Language => 'de',
    Content  => "customer_number;name;active;dynamic.asset_tag\r\nK-1000;Beispiel GmbH;1;\r\n",
);
is( $RequiredError->{ErrorCount}, 1, 'required installation-specific dynamic field is validated' );

my $HeaderError = $Object->_Analyze(
    Type     => 'customer',
    Language => 'de',
    Content  => "customer_number;name;active\r\nK-1000;Beispiel GmbH;1\r\n",
);
is( $HeaderError->{ErrorCount}, 1, 'an outdated header is rejected' );

my $AgentDefinition = $Object->Definition( Type => 'agent', Language => 'de' );
is_deeply(
    $AgentDefinition->{Header},
    [qw(login email firstname lastname active)],
    'agent CSV has no password, group or permission column',
);
unlike( join( ';', @{$AgentDefinition->{Header}} ), qr/(?:password|group|permission)/i, 'agent rights and passwords cannot be imported' );

done_testing();
