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

use AdminAgents;
use QisutuAdmin;

{
    package Local::AgentAdmin;

    sub new { return bless {}, shift }
    sub Error { return shift->{Error} || '' }
    sub AgentActivate {
        my ( $Self, %Param ) = @_;
        $Self->{ActivateParam} = { %Param };
        return 1;
    }
}

{
    package Local::AdminAgents;
    use parent 'AdminAgents';
    sub _AdminObject { return shift->{Admin} }
}

my $MockAdmin = Local::AgentAdmin->new();
my $Module = Local::AdminAgents->new( Config => {}, DB => undef, Output => undef, Program => undef );
$Module->{Admin} = $MockAdmin;

my $Result = $Module->Run(
    Request => {
        Step          => 'AgentActivate',
        UserAccountID => 23,
    },
    User => { user_account_id => 7 },
);

is( $Result->{Redirect}, 'index.pl?Page=AdminAgents', 'activating an agent returns to the overview' );
is_deeply(
    $MockAdmin->{ActivateParam},
    {
        UserAccountID   => 23,
        ChangedByUserID => 7,
    },
    'the overview activation action reaches the administration backend',
);

{
    package Local::AgentDB;

    sub new { return bless { Error => '' }, shift }
    sub Error { return shift->{Error} }
    sub Do {
        my ( $Self, $SQL, @Bind ) = @_;
        $Self->{LastDo} = { SQL => $SQL, Bind => \@Bind };
        return 1;
    }
}

my $DB = Local::AgentDB->new();
my $Admin = QisutuAdmin->new( Config => {}, DB => $DB );

ok( $Admin->AgentActivate( UserAccountID => 23, ChangedByUserID => 7 ), 'an inactive agent can be activated' );
like( $DB->{LastDo}->{SQL}, qr{SET is_active = 1}, 'activation stores the active state' );
like( $DB->{LastDo}->{SQL}, qr{account_type = "agent"}, 'activation is restricted to agent accounts' );
like( $DB->{LastDo}->{SQL}, qr{is_system_user = 0}, 'activation cannot target system users' );
is_deeply( $DB->{LastDo}->{Bind}, [23], 'activation binds the selected agent ID' );

done_testing();
