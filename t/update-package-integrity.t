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
use File::Path qw(make_path);
use File::Spec;
use File::Temp qw(tempdir);
use FindBin;
use IPC::Open3;
use Symbol qw(gensym);
use Test::More;

sub read_file {
    my ($Path) = @_;
    open my $FH, '<:raw', $Path or die "Cannot read $Path: $!";
    my $Content = do { local $/; <$FH> };
    close $FH;
    return $Content;
}

sub write_file {
    my ( $Path, $Content ) = @_;
    open my $FH, '>:raw', $Path or die "Cannot write $Path: $!";
    print {$FH} $Content;
    close $FH or die "Cannot close $Path: $!";
    return;
}

my $Root = File::Spec->rel2abs("$FindBin::Bin/..");
my $Update = read_file("$Root/update.sh");
my $Temp = tempdir( CLEANUP => 1 );
my $Package = "$Temp/package";
make_path("$Package/core");
my $Harness = "$Temp/check-package.sh";
my $Script = "set -Eeuo pipefail\n";
for my $Name (qw(fail trim manifest_path_validate path_is_protected removed_path_validate package_manifest_source_validate)) {
    my ($Function) = $Update =~ /(^\Q$Name\E\(\) \{.*?^\})/ms;
    die "Cannot isolate $Name from update.sh" if !defined $Function;
    $Script .= "$Function\n";
}
$Script .= 'SOURCE_ROOT="$1"' . "\n";
$Script .= 'INSTANCE_ID=qisutu' . "\npackage_manifest_source_validate\n";
write_file( $Harness, $Script );

sub check_package {
    my ($Path) = @_;
    my $ErrorFH = gensym;
    my $PID = open3( undef, my $OutputFH, $ErrorFH, '/bin/bash', $Harness, $Path );
    my $Output = do { local $/; <$OutputFH> } // '';
    my $Error = do { local $/; <$ErrorFH> } // '';
    waitpid $PID, 0;
    return ( $? >> 8, $Output . $Error );
}

sub write_manifest {
    my (@Paths) = @_;
    write_file(
        "$Package/release.sha256",
        join '', map { sha256_hex( read_file("$Package/$_") ) . "  ./$_\n" } @Paths,
    );
    return;
}

my ( $Status, $Output ) = check_package($Root);
is( $Status, 0, 'the real updater accepts the complete release package' ) or diag $Output;

write_file( "$Package/release.remove", '' );
write_file( "$Package/core/program.pm", "original program\n" );
write_file( "$Package/.project", "<name>qisutu-2.0.2</name>\r\n" );
write_manifest(qw(release.remove core/program.pm .project));
write_file( "$Package/.project", "<name>qisutu-2.0.3</name>\n" );
( $Status, $Output ) = check_package($Package);
isnt( $Status, 0, 'including mutable Eclipse metadata in the manifest reproduces the update failure' );
like( $Output, qr{[.]project: FAILED}, 'the reproduced checksum failure identifies .project' );

write_manifest(qw(release.remove core/program.pm));
( $Status, $Output ) = check_package($Package);
is( $Status, 0, 'changed Eclipse project metadata does not block the corrected package' ) or diag $Output;

unlink "$Package/.project" or die "Cannot remove fixture: $!";
( $Status, $Output ) = check_package($Package);
is( $Status, 0, 'Eclipse metadata is optional' ) or diag $Output;

write_file( "$Package/core/program.pm", "changed program\n" );
( $Status, $Output ) = check_package($Package);
isnt( $Status, 0, 'a changed program file still blocks the update' );
like( $Output, qr{core/program[.]pm: FAILED}, 'the program checksum failure remains visible' );
write_file( "$Package/core/program.pm", "original program\n" );

unlink "$Package/core/program.pm" or die "Cannot remove fixture: $!";
( $Status, $Output ) = check_package($Package);
isnt( $Status, 0, 'a missing program file still blocks the update' );
like( $Output, qr{Datei aus release[.]sha256 fehlt}, 'the missing file is reported' );
write_file( "$Package/core/program.pm", "original program\n" );

for my $Unexpected ( 'core/extra.pm', 'core/.project' ) {
    write_file( "$Package/$Unexpected", "unexpected file\n" );
    ( $Status, $Output ) = check_package($Package);
    isnt( $Status, 0, "$Unexpected is not covered by the root metadata exception" );
    like( $Output, qr{nicht in release[.]sha256 eingetragen}, 'unlisted files remain rejected' );
    unlink "$Package/$Unexpected" or die "Cannot remove fixture: $!";
}

symlink 'core/program.pm', "$Package/.project" or die "Cannot create fixture symlink: $!";
( $Status, $Output ) = check_package($Package);
isnt( $Status, 0, 'a symbolic link named .project remains rejected' );
like( $Output, qr{Symbolische Links}, 'the symlink rejection remains active' );

done_testing();
