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

package QisutuDB;

use strict;
use warnings;
use utf8;

use DBI;

sub new {
    my ( $Class, %Param ) = @_;

    my $Self = {
        Config    => $Param{Config},
        DBH       => undef,
        LastError => '',
    };

    bless $Self, $Class;

    return $Self;
}

sub Connect {
    my ($Self) = @_;

    $Self->{LastError} = '';

    my $DatabaseConfig = $Self->{Config}->{Database};

    my $DSN = sprintf(
        'DBI:mysql:database=%s;host=%s;port=%s;mysql_enable_utf8mb4=1',
        $DatabaseConfig->{Name},
        $DatabaseConfig->{Host},
        $DatabaseConfig->{Port},
    );

    my $DBH = DBI->connect(
        $DSN,
        $DatabaseConfig->{User},
        $DatabaseConfig->{Password},
        {
            RaiseError           => 0,
            PrintError           => 0,
            AutoCommit           => 1,
            mysql_enable_utf8mb4 => 1,
        }
    );

    if ( !$DBH ) {
        $Self->{LastError} = $DBI::errstr || 'Database connection failed';
        return;
    }

    $DBH->{mysql_enable_utf8mb4} = 1;
    $DBH->do('SET NAMES utf8mb4 COLLATE utf8mb4_unicode_ci');

    $Self->{DBH} = $DBH;

    return 1;
}

sub Handle {
    my ($Self) = @_;

    if ( !$Self->{DBH} ) {
        $Self->Connect() || return;
    }

    return $Self->{DBH};
}

sub Do {
    my ( $Self, $SQL, @Bind ) = @_;

    $Self->{LastError} = '';

    my $DBH = $Self->Handle() || return;

    my $STH = $DBH->prepare($SQL);
    if ( !$STH ) {
        $Self->{LastError} = $DBH->errstr || 'SQL prepare failed';
        return;
    }

    my $Result = $STH->execute(@Bind);
    if ( !$Result ) {
        $Self->{LastError} = $STH->errstr || 'SQL execute failed';
        return;
    }

    return $Result;
}

sub SelectRow {
    my ( $Self, $SQL, @Bind ) = @_;

    $Self->{LastError} = '';

    my $DBH = $Self->Handle() || return;

    my $STH = $DBH->prepare($SQL);
    if ( !$STH ) {
        $Self->{LastError} = $DBH->errstr || 'SQL prepare failed';
        return;
    }

    my $Result = $STH->execute(@Bind);
    if ( !$Result ) {
        $Self->{LastError} = $STH->errstr || 'SQL execute failed';
        return;
    }

    my $Row = $STH->fetchrow_hashref();

    return $Row;
}

sub SelectAll {
    my ( $Self, $SQL, @Bind ) = @_;

    $Self->{LastError} = '';

    my $DBH = $Self->Handle() || return;

    my $STH = $DBH->prepare($SQL);
    if ( !$STH ) {
        $Self->{LastError} = $DBH->errstr || 'SQL prepare failed';
        return;
    }

    my $Result = $STH->execute(@Bind);
    if ( !$Result ) {
        $Self->{LastError} = $STH->errstr || 'SQL execute failed';
        return;
    }

    my $Rows = $STH->fetchall_arrayref({});

    return $Rows;
}

sub LastInsertID {
    my ( $Self, $Table ) = @_;

    $Self->{LastError} = '';

    my $DBH = $Self->Handle() || return;

    my $ID = $DBH->last_insert_id( undef, undef, $Table, undef );

    if ( !defined $ID ) {
        $Self->{LastError} = $DBH->errstr || 'Last insert ID could not be loaded';
        return;
    }

    return $ID;
}

sub BeginWork {
    my ($Self) = @_;

    my $DBH = $Self->Handle() || return;

    return $DBH->begin_work();
}

sub Commit {
    my ($Self) = @_;

    my $DBH = $Self->Handle() || return;

    return $DBH->commit();
}

sub Rollback {
    my ($Self) = @_;

    my $DBH = $Self->Handle() || return;

    return $DBH->rollback();
}

sub Disconnect {
    my ($Self) = @_;

    if ( $Self->{DBH} ) {
        $Self->{DBH}->disconnect();
        $Self->{DBH} = undef;
    }

    return 1;
}

sub Error {
    my ($Self) = @_;

    return $Self->{LastError};
}

1;
