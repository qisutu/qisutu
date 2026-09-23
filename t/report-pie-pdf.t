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
use lib "$FindBin::Bin/../core/system", "$FindBin::Bin/../core/config", "$FindBin::Bin/../core/cpan-lib";
use Test::More;
use QisutuReportPDF;

{
    package Local::PiePDF;
    our @ISA = ('QisutuReportPDF');
    sub _Sector {
        my ( $Self, @Param ) = @_;
        push @{ $Self->{Sectors} }, [@Param];
        return $Self->SUPER::_Sector(@Param);
    }
    sub _Circle {
        my ( $Self, @Param ) = @_;
        push @{ $Self->{Circles} }, [@Param];
        return $Self->SUPER::_Circle(@Param);
    }
}

my $Result = {
    configuration => { source=>'tickets', chart_type=>'pie', group_by=>'none', metrics=>['ticket_count','closed_count'] },
    group => { key=>'none', label=>'Gesamt' },
    metrics => [
        { key=>'ticket_count', label=>'Tickets', format=>'number' },
        { key=>'closed_count', label=>'Geschlossene Tickets', format=>'number' },
    ],
    summary => [49,12],
    rows => [{ label=>'Gesamt', values=>[49,12] }],
    details => { columns=>[], rows=>[] },
    pie => {
        labels=>['Geschlossene Tickets','Übrige Tickets'], values=>[12,37],
        colors=>['#0ea5e9','#f97316'], format=>'number',
    },
};
my $Renderer = Local::PiePDF->new();
my $PDF = $Renderer->Create( Title=>'Ticketverteilung', Result=>$Result );
like( $PDF, qr{\A%PDF-1\.4}, 'the selected pie exports a PDF document' );
is( scalar @{ $Renderer->{Sectors} || [] }, 2, 'twelve closed and thirty-seven other tickets make two slices' );
is( scalar @{ $Renderer->{Circles} || [] }, 0, 'the pie has no white inner circle or additional rings' );
my $First = $Renderer->{Sectors}->[0];
my $Second = $Renderer->{Sectors}->[1];
is( $First->[2], $Second->[2], 'both slices share a full pie radius' );
my $Tau = 2 * atan2(0,-1);
cmp_ok( abs( ( $First->[3]-$First->[4] ) / $Tau - 12/49 ), '<', 0.000001, 'first slice area matches 12 out of 49' );
cmp_ok( abs( ( $Second->[3]-$Second->[4] ) / $Tau - 37/49 ), '<', 0.000001, 'second slice fills the remaining 37 out of 49' );
is( $First->[4], $Second->[3], 'slice edges meet without a gap in the data' );
cmp_ok( $First->[4], '<', $First->[3], 'pie proceeds clockwise from its top to match the web chart' );
is_deeply( [map { sprintf('%.3f',$_) } @{$First}[5..7]], ['0.055','0.647','0.914'], 'first slice uses the prepared blue color' );
is_deeply( [map { sprintf('%.3f',$_) } @{$Second}[5..7]], ['0.976','0.451','0.086'], 'second slice uses the prepared orange color' );
like( $PDF, qr{1 1 1 RG 1 w}, 'white outlines separate the differently colored slices' );
like( $PDF, qr{\(Geschlossene Tickets: 12\) Tj}, 'legend includes the first slice name and count' );
like( $PDF, qr{\(\xDCbrige Tickets: 37\) Tj}, 'localized remaining-slice label and count survive PDF encoding' );

my $Legacy = Local::PiePDF->new();
$Legacy->Create( Result=>{ %{$Result}, configuration=>{ %{$Result->{configuration}}, chart_type=>'doughnut' } } );
is_deeply( $Legacy->{Sectors}, $Renderer->{Sectors}, 'legacy doughnut exports use the same full pie' );
is( scalar @{ $Legacy->{Circles} || [] }, 0, 'legacy chart type no longer creates a hole' );

my $Fallback = Local::PiePDF->new();
my %Unprepared = %{$Result};
delete $Unprepared{pie};
my $FallbackPDF = $Fallback->Create( Result=>\%Unprepared );
ok( $FallbackPDF, 'direct PDF callers get pie data from the shared backend helper' );
is( scalar @{ $Fallback->{Sectors} || [] }, 2, 'shared fallback builds closed and remaining slices' );
cmp_ok( abs( ( $Fallback->{Sectors}->[0]->[3]-$Fallback->{Sectors}->[0]->[4] ) / $Tau - 12/49 ), '<', 0.000001, 'direct caller retains the same slice proportions' );
ok( !exists $Unprepared{pie}, 'PDF preparation does not alter the caller result' );

my $Zero = Local::PiePDF->new();
my $ZeroPDF = $Zero->Create( Result=>{ %{$Result}, pie=>{ %{$Result->{pie}}, values=>[0,0] } } );
like( $ZeroPDF, qr{\A%PDF-1\.4}, 'an empty pie exports without division by zero' );
is( scalar @{ $Zero->{Sectors} || [] }, 0, 'zero values do not create invented slices' );

my $Single = Local::PiePDF->new();
my $SinglePDF = $Single->Create( Result=>{ %{$Result}, pie=>{ labels=>['Alle Tickets'],values=>[49],colors=>['#0ea5e9'],format=>'number' } } );
is( scalar @{ $Single->{Sectors} || [] }, 1, 'one nonzero value fills one complete disk' );
my $CenterMove = sprintf( '%.2f %.2f m', @{ $Single->{Sectors}->[0] }[0,1] );
unlike( $SinglePDF, qr{1 1 1 RG 1 w \Q$CenterMove\E}, 'a complete disk does not have a spurious radial white seam' );
like( $SinglePDF, qr{\(Alle Tickets: 49\) Tj}, 'single slice value remains visible in the legend' );

my $Many = Local::PiePDF->new();
my $ManyPDF = $Many->Create( Result=>{ %{$Result}, pie=>{
    labels=>[map { 'Gruppe ' . $_ } 1..12], values=>[(1)x12], colors=>[('#0ea5e9')x12], format=>'number',
} } );
is( scalar @{ $Many->{Sectors} || [] }, 12, 'all slices are rendered even when the compact legend is full' );
like( $ManyPDF, qr{\x85 \\\(\+1\\\)}, 'compact legend explicitly indicates one additional entry' );

my $Invalid = Local::PiePDF->new();
my $InvalidPDF = $Invalid->Create( Result=>{
    %Unprepared, metrics=>[{key=>'ticket_count'},{key=>'avg_solution'}],
} );
ok( !defined $InvalidPDF, 'incompatible metrics do not produce a misleading PDF pie' );
is( $Invalid->Error(), 'Translate:ReportErrorPieMetrics', 'invalid PDF data exposes the shared validation error' );

done_testing();
