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
    require QisutuHTML;

    my $BatchSize = 500;
    for my $Arg (@ARGV) {
        if ( $Arg =~ m{\A\d+\z} && $Arg >= 10 && $Arg <= 5000 ) {
            $BatchSize = int($Arg);
        }
    }

    my $Config = QisutuConfig::Load();
    my $DB = QisutuDB->new( Config => $Config );

    if ( !$DB->Connect() ) {
        print STDERR "Database connection failed: " . ( $DB->Error() || '' ) . "\n";
        exit 1;
    }

    my $LastID  = 0;
    my $Updated = 0;

    while (1) {
        my $Rows = $DB->SelectAll(
            'SELECT id, body
             FROM ticket_article
             WHERE id > ?
             ORDER BY id ASC
             LIMIT ' . $BatchSize,
            $LastID,
        );

        if ( !$Rows ) {
            print STDERR "Search index rows could not be loaded: " . ( $DB->Error() || '' ) . "\n";
            $DB->Disconnect();
            exit 1;
        }

        last if !@{$Rows};

        for my $Row ( @{$Rows} ) {
            my $ID = $Row->{id} || 0;
            next if !$ID;

            my $SearchText = QisutuHTML->PlainTextSearch( $Row->{body} || '' );
            my $Result = $DB->Do(
                'UPDATE ticket_article SET search_text = ? WHERE id = ?',
                $SearchText,
                $ID,
            );

            if ( !$Result ) {
                print STDERR "Article $ID could not be indexed: " . ( $DB->Error() || '' ) . "\n";
                $DB->Disconnect();
                exit 1;
            }

            $LastID = $ID;
            $Updated++;
        }

        print "Indexed articles: $Updated\n";
    }

    print "Search index rebuild finished: $Updated articles\n";
    $DB->Disconnect();
    return;
}
