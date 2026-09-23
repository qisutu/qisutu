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
use File::Spec;
use FindBin;
use Test::More;

my ($Node) = grep { -f $_ && -x $_ }
    map { File::Spec->catfile($_, 'node') } File::Spec->path();
plan skip_all => 'Node.js is required to exercise the browser chart renderer' if !$Node;
my $Status = system($Node, File::Spec->catfile($FindBin::Bin, 'report-chart-rendering.js'));
is($Status, 0, 'production chart rendering preserves filled pies, distinct slices and existing charts');
done_testing();
