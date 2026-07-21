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

use File::Spec;
use FindBin;
use Test::More;

use lib File::Spec->catdir( $FindBin::Bin, '..', 'core', 'output' );
use lib File::Spec->catdir( $FindBin::Bin, '..', 'core', 'system' );

use QisutuDispatcher;
use QisutuOutput;

{
    package Local::ProgramRegistry;

    sub NavigationHTML {
        return '';
    }
}

my $Root = File::Spec->catdir( $FindBin::Bin, '..' );
my $Config = {
    Paths => {
        Output   => File::Spec->catdir( $Root, 'core', 'output' ),
        Language => File::Spec->catdir( $Root, 'core', 'language' ),
        StaticURL => '/qisutu/static',
    },
    Language => { Default => 'de' },
    System   => {
        Name    => 'Qisutu',
        Version => '0.0.74',
    },
};

my $Output = QisutuOutput->new( Config => $Config );
my $Dispatcher = QisutuDispatcher->new(
    Config          => $Config,
    Output          => $Output,
    ProgramRegistry => bless( {}, 'Local::ProgramRegistry' ),
);

my $Data = $Dispatcher->_BaseData( User => {} );
is( $Data->{SystemVersion}, '0.0.74', 'dispatcher exposes the installed program version to authenticated templates' );

my $Header = $Output->RenderSingle(
    Template => 'Header.tt',
    Data     => $Data,
);

like(
    $Header || '',
    qr{<span class="qisutu-sidebar-version">0[.]0[.]74</span>},
    'sidebar displays the installed version directly beside the product name',
);

done_testing();
