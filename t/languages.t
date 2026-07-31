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

use lib File::Spec->catdir( $FindBin::Bin, '..', 'core', 'output' );

use QisutuOutput;

my $Root = File::Spec->rel2abs( File::Spec->catdir( $FindBin::Bin, '..' ) );
my @Languages = qw(de en fr it pt-BR pt-PT es nl pl cs tr);
my $English = do File::Spec->catfile( $Root, 'core', 'language', 'en.pm' );

ok( ref $English eq 'HASH', 'English reference language loads' );

my $SystemSettings = do File::Spec->catfile(
    $Root, 'core', 'config', 'settings', 'System.pm',
);
my ($DefaultLanguageSetting) = grep {
    ( $_->{Key} || '' ) eq 'system.default_language'
} @{ $SystemSettings || [] };
is_deeply(
    [ map { $_->{Value} } @{ $DefaultLanguageSetting->{PossibleValues} || [] } ],
    \@Languages,
    'system settings expose exactly the eleven supported languages',
);

for my $Language (@Languages) {
    my $Path = File::Spec->catfile( $Root, 'core', 'language', "$Language.pm" );
    ok( -f $Path && !-l $Path, "$Language language file is present" );

    my $Translation = do $Path;
    ok( ref $Translation eq 'HASH', "$Language language file loads" );
    next if ref $Translation ne 'HASH';

    my @Missing = sort grep { !exists $Translation->{$_} } keys %{$English};
    my @Extra   = sort grep { !exists $English->{$_} } keys %{$Translation};
    is_deeply( \@Missing, [], "$Language contains every core translation key" );
    is_deeply( \@Extra, [], "$Language contains no unknown core translation key" );

    my @Empty = sort grep {
        defined $English->{$_}
            && $English->{$_} ne ''
            && ( !defined $Translation->{$_} || $Translation->{$_} eq '' )
    } keys %{$English};
    is_deeply( \@Empty, [], "$Language contains no empty translations" );

    my @PlaceholderMismatch;
    for my $Key ( keys %{$English} ) {
        next if !exists $Translation->{$Key};
        my @Source = sort( ( $English->{$Key} || '' ) =~ m{(\{[^{}]+\})}g );
        my @Target = sort( ( $Translation->{$Key} || '' ) =~ m{(\{[^{}]+\})}g );
        push @PlaceholderMismatch, $Key if join( "\0", @Source ) ne join( "\0", @Target );
    }
    is_deeply( \@PlaceholderMismatch, [], "$Language preserves every placeholder" );
}

my $PortugueseBrazil = do File::Spec->catfile(
    $Root, 'core', 'language', 'pt-BR.pm',
);
my $PortuguesePortugal = do File::Spec->catfile(
    $Root, 'core', 'language', 'pt-PT.pm',
);
my @PortugueseDifferences = grep {
    $PortugueseBrazil->{$_} ne $PortuguesePortugal->{$_}
} keys %{$English};
cmp_ok(
    scalar @PortugueseDifferences,
    '>',
    100,
    'Brazilian and European Portuguese are independent translations',
);

my $Output = QisutuOutput->new(
    Config => {
        Paths => {
            Language => File::Spec->catdir( $Root, 'core', 'language' ),
        },
    },
);

isnt(
    $Output->Translate( Key => 'LoginIntro', Language => 'pt-br' ),
    $English->{LoginIntro},
    'lower-case pt-br resolves to the canonical pt-BR language file',
);
isnt(
    $Output->Translate( Key => 'LoginIntro', Language => 'pt_PT' ),
    $English->{LoginIntro},
    'underscore pt_PT resolves to the canonical pt-PT language file',
);

done_testing();
