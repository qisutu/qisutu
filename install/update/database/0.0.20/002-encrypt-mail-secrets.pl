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

use QisutuConfig;
use QisutuDB;
use QisutuSecurity;

my $Config = QisutuConfig::Load();
my $DB = QisutuDB->new( Config => $Config );
my $Security = QisutuSecurity->new( Config => $Config );

my @Table = (
    [ postmaster_imap_account => qw(imap_password oauth_client_secret oauth_access_token oauth_refresh_token) ],
    [ smtp_account            => qw(smtp_password oauth_client_secret oauth_access_token oauth_refresh_token) ],
);

$DB->BeginWork() or die( $DB->Error() || "Secret migration transaction could not be started\n" );

eval {
    for my $Definition (@Table) {
        my ( $Table, @Column ) = @{$Definition};
        my $Rows = $DB->SelectAll( 'SELECT id, ' . join( ', ', @Column ) . ' FROM ' . $Table ) || [];
        for my $Row ( @{$Rows} ) {
            my @Set;
            my @Bind;
            for my $Column (@Column) {
                my $Value = $Row->{$Column};
                next if !defined $Value || $Value eq '' || $Value =~ m{\Aqse1:};
                my $Encrypted = $Security->Encrypt( Value => $Value );
                die( $Security->Error() || "Secret encryption failed\n" ) if !defined $Encrypted;
                push @Set, "$Column = ?";
                push @Bind, $Encrypted;
            }
            next if !@Set;
            push @Bind, $Row->{id};
            $DB->Do( 'UPDATE ' . $Table . ' SET ' . join( ', ', @Set ) . ' WHERE id = ?', @Bind )
                or die( $DB->Error() || "Secret migration update failed\n" );
        }
    }
    1;
} or do {
    my $Error = $@ || 'Unknown secret migration error';
    $DB->Rollback();
    die $Error;
};

$DB->Commit() or die( $DB->Error() || "Secret migration transaction could not be committed\n" );
$DB->Disconnect();

print "Mail and OAuth secrets are encrypted.\n";
