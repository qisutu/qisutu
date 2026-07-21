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

use File::Temp qw(tempdir);
use FindBin;
use Test::More;

use lib "$FindBin::Bin/../core/system";
use QisutuRuntimeLock;

my $Directory = tempdir( CLEANUP => 1 );
local $ENV{QISUTU_RUNTIME_LOCK_DIR} = $Directory;

my $Lock = QisutuRuntimeLock::SharedAcquire(
    RootPath   => '/opt/qisututest',
    NonBlocking => 1,
);

ok( $Lock->{Success}, 'runtime lock can be created' );
ok( -f $Lock->{File}, 'runtime lock file exists' );
is( ( stat $Lock->{File} )[2] & 0777, 0660, 'new runtime lock is group-writable' );

my $MailFetchLock = QisutuRuntimeLock::ProcessAcquire(
    RootPath    => '/opt/qisututest',
    Name        => 'mail-fetch',
    NonBlocking => 1,
);

ok( $MailFetchLock->{Success}, 'mail-fetch process lock can be acquired' );
like( $MailFetchLock->{File}, qr{qisututest[.]mail-fetch[.]lock\z}, 'mail-fetch lock is instance-specific' );
is( ( stat $MailFetchLock->{File} )[2] & 0777, 0660, 'mail-fetch lock is group-writable' );

my $SecondMailFetchLock = QisutuRuntimeLock::ProcessAcquire(
    RootPath    => '/opt/qisututest',
    Name        => 'mail-fetch',
    NonBlocking => 1,
);

ok( !$SecondMailFetchLock->{Success}, 'a second mail-fetch process cannot run concurrently' );
ok( $SecondMailFetchLock->{Busy}, 'a concurrent mail-fetch process is reported as busy' );

done_testing();
