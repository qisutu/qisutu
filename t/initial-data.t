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
use File::Spec;
use Test::More;

my $InsertPath = File::Spec->catfile( $FindBin::Bin, '..', 'install', 'sql', 'insert.sql' );
open my $InsertFH, '<:encoding(UTF-8)', $InsertPath or die "Cannot read $InsertPath: $!";
my $Insert = do { local $/; <$InsertFH> };
close $InsertFH;

sub InsertBlock {
    my ( $Table, $NextTable ) = @_;
    my ($Block) = $Insert =~ m{
        INSERT\s+INTO\s+`\Q$Table\E`\s*\(.*?\)\s*VALUES\s*(.*?)
        (?=INSERT\s+INTO\s+`\Q$NextTable\E`)
    }six;
    return $Block || '';
}

my $Groups = InsertBlock( 'user_group', 'user_group_member' );
my @GroupNames = $Groups =~ m{\(\s*\d+\s*,\s*'([^']+)'}g;
is_deeply( \@GroupNames, [qw(admin agent reports)], 'fresh installations contain exactly the three requested groups' );

my $Members = InsertBlock( 'user_group_member', 'user_group_permission' );
for my $GroupID ( 1 .. 3 ) {
    like(
        $Members,
        qr{\(\s*\Q$GroupID\E\s*,\s*1\s*,\s*'admin'\s*,\s*1\s*,\s*1\s*,\s*1\s*,\s*1\s*,\s*1\s*,\s*1\s*,\s*1\s*,\s*1\s*\)},
        "initial admin has full access to group $GroupID",
    );
}

my $Queues = InsertBlock( 'ticket_queue', 'ticket_queue_group' );
my @QueueNames = $Queues =~ m{\(\s*\d+\s*,\s*'([^']+)'}g;
is_deeply( \@QueueNames, [ 'Posteingang', 'Spam' ], 'fresh installations contain only Posteingang and Spam' );

my $QueueGroups = InsertBlock( 'ticket_queue_group', 'ticket_state' );
for my $QueueID ( 1 .. 2 ) {
    like(
        $QueueGroups,
        qr{\(\s*\Q$QueueID\E\s*,\s*2\s*,\s*'ticket[.]full'\s*,\s*1\s*,\s*1\s*,\s*1\s*\)},
        "queue $QueueID uses the agent group with full ticket access",
    );
}
unlike( $QueueGroups, qr{\(\s*\d+\s*,\s*(?:1|3)\s*,}, 'queues have no additional default group assignment' );

like( $Insert, qr{INSERT INTO `ticket_state`}, 'the remaining initial ticket states are retained' );
like( $Insert, qr{INSERT INTO `ticket_priority`}, 'the remaining initial priorities are retained' );
like( $Insert, qr{INSERT INTO `customer_auto_response_template`}, 'the remaining automatic-response templates are retained' );

done_testing();
