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
use lib "$FindBin::Bin/../core/system", "$FindBin::Bin/../core/module", "$FindBin::Bin/../core/output";
use Encode qw(decode FB_CROAK);
use JSON::PP qw(decode_json);
use Test::More;
use Dashboard;
use QisutuOutput;

my $Output = QisutuOutput->new( Config => {
    Paths => {
        Output   => "$FindBin::Bin/../core/output",
        Language => "$FindBin::Bin/../core/language",
    },
    Language => { Default => 'de' },
} );
my $Dashboard = Dashboard->new( Output => $Output );
my $Special = 'ÄÖÜ äöü ß – 東京 😀 </script><script>alert("test")</script> & '
    . chr(8232) . chr(8233);

for my $Language (qw(de en fr it es pt-BR pt-PT nl pl cs tr)) {
    my $Display = $Dashboard->_AgentDataPrepare(
        Language => $Language,
        Data => {
            age => [ { key => 'over_10d', value => 3 } ],
            status => [ { id => 1, name => $Special, state_type => 'open', ticket_count => 3 } ],
        },
    );
    my $Data = $Display->{ClientData};
    is( $Data->{age}->{labels}->[0], 'Über 10 Tage', 'German age label is correct before serialization' )
        if $Language eq 'de';
    my $JSON = $Dashboard->_JSONForHTML($Data);
    unlike( $JSON, qr{[<>&]}, "$Language: embedded JSON cannot close its script element" );
    ok( index($JSON, chr(8232)) == -1 && index($JSON, chr(8233)) == -1,
        "$Language: Unicode line separators are escaped" );

    my $HTML = $Output->RenderSingle(
        Template => 'Dashboard.tt',
        Data => {
            %{$Display}, Language => $Language, IsAgentDashboard => 1,
            DashboardDataJSON => $JSON,
        },
    );
    ok( defined $HTML, "$Language: actual dashboard template renders" );
    my $Response = $Output->Response( Body => $HTML );
    my (undef, $Body) = split /\r\n\r\n/, $Response, 2;
    my $Decoded = decode('UTF-8', $Body, FB_CROAK);
    my ($Embedded) = $Decoded =~ m{<script id="qisutu-dashboard-data" type="application/json">(.*?)</script>}s;
    ok( defined $Embedded, "$Language: response contains initial chart data" );
    is_deeply( JSON::PP->new->utf8(0)->decode($Embedded), $Data,
        "$Language: initial chart data preserves all Unicode text through HTML response" );

    my $Refresh = $Dashboard->_JSONResponse( Data => $Data )->{Response};
    my (undef, $RefreshBody) = split /\r\n\r\n/, $Refresh, 2;
    is_deeply( decode_json($RefreshBody), $Data,
        "$Language: automatic refresh preserves the same Unicode text" );
}

done_testing();
