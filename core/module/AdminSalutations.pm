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

package AdminSalutations;

use strict;
use warnings;
use utf8;
use parent 'AdminMasterData';

sub _Definition {
    return {
        Page           => 'AdminSalutations',
        Template       => 'AdminSalutations.tt',
        Title          => 'AdminSalutationsTitle',
        Description    => 'AdminSalutationsDescription',
        ListTitle      => 'AdminSalutationsList',
        CreateTitle    => 'AdminSalutationCreate',
        EditTitle      => 'AdminSalutationEdit',
        ValueLabel     => 'AdminContent',
        ValueColumn    => 'content',
        ValueParam     => 'Content',
        ValueIsTextarea => 1,
        RichText       => 1,
        IDParam        => 'SalutationID',
        ListMethod     => 'SalutationList',
        GetMethod      => 'SalutationGet',
        CreateMethod   => 'SalutationCreate',
        UpdateMethod   => 'SalutationUpdate',
        DeactivateMethod => 'SalutationDeactivate',
        CreateStep     => 'SalutationCreate',
        UpdateStep     => 'SalutationUpdate',
        DeactivateStep => 'SalutationDeactivate',
    };
}

1;
