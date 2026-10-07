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

package KnowledgeBase;

use strict;
use warnings;
use utf8;

sub new { my ( $Class, %Param ) = @_; return bless { %Param }, $Class; }

sub Run {
    my ( $Self, %Param ) = @_;
    my $User = $Param{User} || {};
    my $Type = $User->{account_type} || '';

    # The shared navigation parent is visible to both account types. It must
    # never execute agent actions or forward untrusted Step/Action parameters.
    if ( $User->{user_account_id} && ( $Type eq 'agent' || $Type eq 'customer' ) ) {
        return { Redirect => 'index.pl?Page='
            . ( $Type eq 'agent' ? 'AgentKnowledgeBase' : 'CustomerKnowledgeBase' ) };
    }
    return { Response => $Self->{Output}->Response(
        Status => '403 Forbidden', Headers => [ 'Cache-Control: no-store' ], Body => 'Forbidden',
    ) };
}

1;
