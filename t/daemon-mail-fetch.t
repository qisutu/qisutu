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
use Test::More;

my $DaemonPath = "$FindBin::Bin/../bin/qisutu-daemon.pl";
open my $DaemonFH, '<:encoding(UTF-8)', $DaemonPath
    or die "Cannot open $DaemonPath: $!";
my $Daemon = do { local $/; <$DaemonFH> };
close $DaemonFH;

like(
    $Daemon,
    qr{my \$MailFetchInterval = 300;},
    'the daemon starts with the five-minute default',
);
like(
    $Daemon,
    qr{mail[.]fetch_interval_minutes},
    'the daemon reads the configurable mail-retrieval interval',
);
like(
    $Daemon,
    qr{time - \$LastMailFetchIntervalCheck >= 15},
    'interval changes are reloaded without restarting the daemon',
);
like(
    $Daemon,
    qr{my \$LastMailFetch = 0;},
    'the first daemon pass starts mail retrieval immediately',
);
like(
    $Daemon,
    qr{time - \$LastMailFetch >= \$MailFetchInterval},
    'later daemon passes obey the mail-retrieval interval',
);
like(
    $Daemon,
    qr{File::Spec->catfile\( \$QisutuHome, 'bin', 'qisutu-mail-fetch[.]pl' \)},
    'the daemon resolves the mail-retrieval program inside its own instance',
);
like(
    $Daemon,
    qr{local \$ENV\{QISUTU_HOME\} = \$QisutuHome;},
    'the daemon passes its own instance path to mail retrieval',
);
like(
    $Daemon,
    qr{system \{ \$\^X \} \$\^X, \$MailFetchScript},
    'the daemon starts mail retrieval without invoking a command shell',
);

my $ServicePath = "$FindBin::Bin/../scriptfiles/qisutu-daemon.service";
open my $ServiceFH, '<:encoding(UTF-8)', $ServicePath
    or die "Cannot open $ServicePath: $!";
my $Service = do { local $/; <$ServiceFH> };
close $ServiceFH;

like(
    $Service,
    qr{^Environment=QISUTU_HOME=__QISUTU_ROOT__$}m,
    'each generated daemon service provides its own Qisutu instance path',
);

my $MailFetchPath = "$FindBin::Bin/../bin/qisutu-mail-fetch.pl";
open my $MailFetchFH, '<:encoding(UTF-8)', $MailFetchPath
    or die "Cannot open $MailFetchPath: $!";
my $MailFetch = do { local $/; <$MailFetchFH> };
close $MailFetchFH;

like(
    $MailFetch,
    qr{QisutuRuntimeLock::ProcessAcquire\(\s*RootPath\s*=>\s*\$QisutuHome,\s*Name\s*=>\s*'mail-fetch',\s*NonBlocking\s*=>\s*1,\s*\)}s,
    'mail retrieval prevents a second concurrent run for the same instance',
);

done_testing();
