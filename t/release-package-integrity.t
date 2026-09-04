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

use Digest::SHA qw(sha256_hex);
use File::Find;
use File::Spec;
use FindBin;
use Test::More;

my $Root = File::Spec->rel2abs( File::Spec->catdir( $FindBin::Bin, '..' ) );

sub read_lines {
    my ($Relative) = @_;
    my $Path = File::Spec->catfile( $Root, split m{/}, $Relative );

    open my $FH, '<:raw', $Path or die "Cannot read $Relative: $!";
    my @Lines = <$FH>;
    close $FH;

    s/\r?\n\z// for @Lines;
    return @Lines;
}

my %Manifest;
my @ManifestProblems;

for my $Line ( read_lines('release.sha256') ) {
    next if $Line eq '';

    if ( $Line !~ /\A([0-9a-f]{64})  \.\/(.+)\z/ ) {
        push @ManifestProblems, "ungültiger Manifesteintrag: $Line";
        next;
    }

    my ( $Expected, $Relative ) = ( $1, $2 );
    if ( exists $Manifest{$Relative} ) {
        push @ManifestProblems, "doppelter Manifestpfad: $Relative";
        next;
    }
    if ( $Relative eq '' || $Relative =~ m{(?:\A|/)\.{1,2}(?:/|\z)} || $Relative =~ m{//|\s} ) {
        push @ManifestProblems, "unsicherer Manifestpfad: $Relative";
        next;
    }

    $Manifest{$Relative} = $Expected;
}

my %Removed;
my @RemovalProblems;

for my $Line ( read_lines('release.remove') ) {
    $Line =~ s/\A\s+|\s+\z//g;
    next if $Line eq '' || $Line =~ /\A#/;

    if ( $Line !~ /\A\.\/(.+)\z/ ) {
        push @RemovalProblems, "ungültiger Entfernungseintrag: $Line";
        next;
    }

    my $Relative = $1;
    if ( exists $Removed{$Relative} ) {
        push @RemovalProblems, "doppelter Entfernungspfad: $Relative";
        next;
    }
    if ( $Relative eq '' || $Relative =~ m{(?:\A|/)\.{1,2}(?:/|\z)} || $Relative =~ m{//|\s} ) {
        push @RemovalProblems, "unsicherer Entfernungspfad: $Relative";
        next;
    }

    $Removed{$Relative} = 1;
}

is_deeply( \@ManifestProblems, [], 'release.sha256 enthält nur eindeutige und sichere Einträge' );
is_deeply( \@RemovalProblems, [], 'release.remove enthält nur eindeutige und sichere Einträge' );

my @Overlap = sort grep { exists $Manifest{$_} } keys %Removed;
is_deeply( \@Overlap, [], 'kein Pfad steht gleichzeitig in release.sha256 und release.remove' );

my @PresentObsolete;
for my $Relative ( sort keys %Removed ) {
    my $Path = File::Spec->catfile( $Root, split m{/}, $Relative );
    push @PresentObsolete, $Relative if -e $Path || -l $Path;
}
is_deeply( \@PresentObsolete, [], 'veraltete Dateien sind nicht mehr im Updatepaket enthalten' );

my @FileProblems;
for my $Relative ( sort keys %Manifest ) {
    my $Path = File::Spec->catfile( $Root, split m{/}, $Relative );
    if ( !-f $Path || -l $Path ) {
        push @FileProblems, "$Relative: fehlt oder ist kein reguläre Datei";
        next;
    }

    open my $FH, '<:raw', $Path or do {
        push @FileProblems, "$Relative: nicht lesbar: $!";
        next;
    };
    local $/;
    my $Content = <$FH>;
    close $FH;

    my $Actual = sha256_hex($Content);
    push @FileProblems, "$Relative: falsche SHA-256-Prüfsumme"
        if $Actual ne $Manifest{$Relative};
}
is_deeply( \@FileProblems, [], 'alle Dateien aus release.sha256 sind vorhanden und unverändert' );

my @Unlisted;
my @Symlinks;
find(
    {
        no_chdir => 1,
        wanted   => sub {
            my $Path = $File::Find::name;
            my $Relative = File::Spec->abs2rel( $Path, $Root );
            $Relative =~ s{\\}{/}g;

            if ( -l $Path ) {
                push @Symlinks, $Relative if !exists $Removed{$Relative};
                return;
            }
            return if !-f $Path || $Relative eq 'release.sha256';
            push @Unlisted, $Relative if !exists $Manifest{$Relative};
        },
    },
    $Root,
);

is_deeply( [ sort @Unlisted ], [], 'jede Paketdatei ist in release.sha256 eingetragen' );
is_deeply( [ sort @Symlinks ], [], 'das Updatepaket enthält keine symbolischen Links' );

ok( exists $Manifest{'core/config/programs/CMDB.pm'}, 'aktive CMDB-Navigation bleibt im Updatepaket' );
ok( !exists $Removed{'core/config/programs/CMDB.pm'}, 'aktive CMDB-Navigation wird beim Update nicht entfernt' );

my $ReleaseContent = join "\n", read_lines('release.conf');
my ($ReleaseVersion) = $ReleaseContent =~ /^version=([^\s]+)$/m;
is( $ReleaseVersion, '1.0.3', 'das Paket verwendet Programmversion 1.0.3' );
like( $ReleaseContent, qr{^minimum_program_version=1[.]0[.]1$}m, 'offizielle Updates beginnen bei Version 1.0.1' );
like( $ReleaseContent, qr{^database_version=1[.]0[.]2$}m, 'das Paket verwendet Datenbankversion 1.0.2' );
is_deeply( [ sort keys %Removed ], [], 'Version 1.0.3 enthält keine Update-Entfernungseinträge' );

my $MigrationRoot = File::Spec->catdir( $Root, 'install', 'update', 'database' );
opendir my $MigrationDH, $MigrationRoot or die "Cannot inspect $MigrationRoot: $!";
my @PrereleaseMigrations = sort grep { /^0[.]0[.]/ && -d File::Spec->catdir( $MigrationRoot, $_ ) } readdir $MigrationDH;
closedir $MigrationDH;
is_deeply( \@PrereleaseMigrations, [], 'das offizielle Paket enthält keine 0.0.x-Entwicklungsmigrationen' );

my $ConfigPath = File::Spec->catfile( $Root, 'core', 'config', 'QisutuConfig.pm' );
open my $ConfigFH, '<:raw', $ConfigPath or die "Cannot read core/config/QisutuConfig.pm: $!";
local $/;
my $ConfigContent = <$ConfigFH>;
close $ConfigFH;
my ($ConfigVersion) = $ConfigContent =~ /Version\s*=>\s*'([^']+)'/;
is( $ConfigVersion, $ReleaseVersion, 'Release- und Standardkonfiguration verwenden dieselbe Programmversion' );

my $SchemaContent = join "\n", read_lines('install/sql/schema.sql');
like( $SchemaContent, qr{INSERT INTO `database_version` \(`version`\) VALUES \('1[.]0[.]2'\)}, 'das Neuinstallationsschema verwendet Datenbankversion 1.0.2' );

done_testing();
