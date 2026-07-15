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

package QisutuRuntimeLock;

use strict;
use warnings;
use utf8;

use Fcntl qw(:flock);
use File::Spec;

sub MaintenanceFile {
    my (%Param) = @_;

    my $RootPath = $Param{RootPath} || $ENV{QISUTU_HOME} || '';
    return if !$RootPath;

    return File::Spec->catfile( $RootPath, 'var', 'install', 'update.lock' );
}

sub MaintenanceActive {
    my (%Param) = @_;

    my $File = MaintenanceFile(%Param);
    return $File && -e $File ? 1 : 0;
}

sub InstanceID {
    my (%Param) = @_;

    my $RootPath = $Param{RootPath} || $ENV{QISUTU_HOME} || '';
    return 'qisutu' if !$RootPath;

    my $InstanceFile = File::Spec->catfile( $RootPath, 'var', 'install', 'instance.conf' );
    if ( open my $FH, '<:encoding(UTF-8)', $InstanceFile ) {
        while ( my $Line = <$FH> ) {
            $Line =~ s{\r?\n\z}{};
            next if $Line !~ m{\Ainstance_id=(.+)\z};
            my $InstanceID = $1;
            if ( $InstanceID =~ m{\A[a-z][a-z0-9-]{0,47}\z} ) {
                close $FH;
                return $InstanceID;
            }
            last;
        }
        close $FH;
    }

    my ( undef, undef, $Directory ) = File::Spec->splitpath($RootPath);
    $Directory ||= 'qisutu';
    $Directory =~ s{[^A-Za-z0-9-]+}{-}g;
    $Directory = lc $Directory;
    $Directory =~ s{\A-+|\-+\z}{}g;
    $Directory = 'qisutu' if $Directory !~ m{\A[a-z][a-z0-9-]{0,47}\z};

    return $Directory;
}

sub LockFile {
    my (%Param) = @_;

    my $InstanceID = InstanceID(%Param);
    my $LockDirectory = $ENV{QISUTU_RUNTIME_LOCK_DIR} || '/run/lock/qisutu';

    return File::Spec->catfile( $LockDirectory, $InstanceID . '.runtime.lock' );
}

sub SharedAcquire {
    my (%Param) = @_;

    my $LockFile = LockFile(%Param);
    my $Mode = LOCK_SH;
    $Mode |= LOCK_NB if $Param{NonBlocking};

    my $FH;
    if ( !open $FH, '>>', $LockFile ) {
        return {
            Success => 0,
            Busy    => 0,
            Error   => "Runtime lock file cannot be opened: $LockFile: $!",
        };
    }

    if ( !flock( $FH, $Mode ) ) {
        my $Error = "$!";
        close $FH;
        return {
            Success => 0,
            Busy    => $Param{NonBlocking} ? 1 : 0,
            Error   => "Runtime lock cannot be acquired: $LockFile: $Error",
        };
    }

    return {
        Success => 1,
        File    => $LockFile,
        Handle  => $FH,
    };
}

1;
