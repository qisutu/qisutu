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

use FindBin qw($Bin);
use Test::More;

my $ProjectRoot = "$Bin/..";

my $ToolPath    = "$ProjectRoot/tools/qisutu-static-analysis";
my $ProfilePath = "$ProjectRoot/.perlcriticrc";
my $PolicyPath  = "$ProjectRoot/DEVELOPMENT.md";

ok( -f $ToolPath,    'static-analysis command is included' );
ok( -x $ToolPath,    'static-analysis command is executable' );
ok( -f $ProfilePath, 'Perl::Critic profile is included' );

open my $ProfileHandle, '<', $ProfilePath
    or die "Cannot open $ProfilePath: $!";
my $Profile = do { local $/; <$ProfileHandle> };
close $ProfileHandle;

like( $Profile, qr/ProhibitStringyEval/, 'profile checks string evaluation' );
like( $Profile, qr/ProhibitTwoArgOpen/,  'profile checks unsafe file opening' );
like( $Profile, qr/RequireCheckedSyscalls/, 'profile checks system-call results' );
like( $Profile, qr/profile-strictness\s*=\s*fatal/, 'invalid profile entries fail analysis' );

open my $PolicyHandle, '<', $PolicyPath
    or die "Cannot open $PolicyPath: $!";
my $Policy = do { local $/; <$PolicyHandle> };
close $PolicyHandle;

like( $Policy, qr/mandatory release gate/, 'release policy makes analysis mandatory' );
like(
    $Policy,
    qr/medium or higher severity must be corrected before release/,
    'release policy requires relevant findings to be corrected'
);

done_testing();
