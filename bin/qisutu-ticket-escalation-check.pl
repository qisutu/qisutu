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

use Cwd qw(abs_path);
use FindBin;
use File::Spec;

my $QisutuHome = $ENV{QISUTU_HOME} || abs_path( File::Spec->catdir( $FindBin::Bin, '..' ) );

$ENV{QISUTU_HOME} ||= $QisutuHome;

unshift @INC,
    File::Spec->catdir( $QisutuHome, 'core', 'config' ),
    File::Spec->catdir( $QisutuHome, 'core', 'system' ),
    File::Spec->catdir( $QisutuHome, 'core', 'cpan-lib' );

main();

sub main {
    require QisutuConfig;
    require QisutuDB;
    require QisutuTicket;

    my $Limit = 5000;

    for my $Arg (@ARGV) {
        if ( $Arg =~ m{\A\d+\z} && $Arg > 0 ) {
            $Limit = $Arg;
        }
    }

    my $Config = QisutuConfig::Load();

    my $DB = QisutuDB->new(
        Config => $Config,
    );

    if ( !$DB->Connect() ) {
        print "Database connection failed: " . ( $DB->Error() || '' ) . "\n";
        return;
    }

    my $TicketObject = QisutuTicket->new(
        Config => $Config,
        DB     => $DB,
    );

    my $Result = $TicketObject->CheckTicketEscalations(
        Limit           => $Limit,
        ChangedByUserID => 1,
    ) || {};

    print join(
        ' ',
        'Escalation check:',
        'pending_reached=' . ( $Result->{PendingDue} || 0 ),
        'escalated=' . ( $Result->{Escalated} || 0 ),
        'recalculated=' . ( $Result->{Recalculated} || 0 ),
        'checked=' . ( $Result->{Checked} || 0 ),
    ) . "\n";

    $DB->Disconnect();

    return;
}
