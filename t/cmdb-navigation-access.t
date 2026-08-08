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

use lib File::Spec->catdir( $FindBin::Bin, '..', 'core', 'module' );
use lib File::Spec->catdir( $FindBin::Bin, '..', 'core', 'system' );

use CMDBItems;

{
    package Local::CMDBNavigationObject;

    sub PermissionLevel {
        return {
            View   => 1,
            Create => 1,
            Change => 1,
            Import => 1,
            Admin  => 1,
        };
    }

    sub TypeList   { return [] }
    sub CIList     { return { Items => [], Count => 0 } }
    sub StatusList { return [] }
    sub RelationTypeList { return [] }
    sub Error      { return '' }
}

{
    package Local::CMDBNavigationOutput;

    sub Translate {
        my ( $Self, %Param ) = @_;
        return $Param{Key} || '';
    }

    sub HTMLEscape {
        my ( $Self, $Value ) = @_;
        return defined $Value ? $Value : '';
    }
}

my $CMDBObject = bless {}, 'Local::CMDBNavigationObject';
my $Module = CMDBItems->new(
    Config  => { Language => { Default => 'de' } },
    DB      => bless( {}, 'Local::CMDBNavigationDB' ),
    Output  => bless( {}, 'Local::CMDBNavigationOutput' ),
    Program => { Name => 'CMDBItems' },
);

my $Result;
{
    no warnings 'redefine';
    local *QisutuCMDB::new = sub { return $CMDBObject };

    $Result = $Module->Run(
        Request => {
            Page     => 'CMDBItems',
            Action   => 'List',
            Language => 'de',
        },
        User => {
            user_account_id => 1,
            account_type    => 'agent',
        },
    );
}

is( $Result->{Template}, 'CMDBItems.tt', 'the CMDB main navigation renders the CMDB template' );
ok( !$Result->{Data}->{AccessDenied}, 'the CMDB main navigation is not treated as a restricted ticket link' );
ok( $Result->{Data}->{ShowList}, 'the CMDB main navigation shows the configuration item list' );
ok( $Result->{Data}->{AdminMode}, 'the central CMDB keeps its full management view' );
ok( $Result->{Data}->{CanCreate}, 'the evaluated CMDB create permission remains active' );
ok( $Result->{Data}->{CanChange}, 'the evaluated CMDB change permission remains active' );
ok( $Result->{Data}->{CanImport}, 'the evaluated CMDB import permission remains active' );

done_testing();
