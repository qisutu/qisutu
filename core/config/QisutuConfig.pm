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

package QisutuConfig;

use strict;
use warnings;
use utf8;

sub Load {
    my $RootPath = $ENV{QISUTU_HOME} || '/opt/qisutu';

    return {
        RootPath => $RootPath,

        Database => {
            Type     => 'mysql',
            Host     => 'localhost',
            Port     => 3306,
            Name     => 'qisutu',
            User     => 'qisutu',
            Password => 'CHANGE-ME-DURING-INSTALLATION',
            Charset  => 'utf8mb4',
        },

        Session => {
            CookieName      => 'QISUTU_SESSION',
            LifetimeSeconds => 28800,
        },

        Language => {
            Default => 'de',
        },

        Paths => {
            Core      => "$RootPath/core",
            Config    => "$RootPath/core/config",
            ProgramConfig => "$RootPath/core/config/programs",
            SettingConfig => "$RootPath/core/config/settings",
            Module    => "$RootPath/core/module",
            Output    => "$RootPath/core/output",
            System    => "$RootPath/core/system",
            Language  => "$RootPath/core/language",
            Var       => "$RootPath/var",
            Log       => "$RootPath/var/log",
            Cache     => "$RootPath/var/cache",
            Static    => "$RootPath/var/static",
            StaticURL => '/qisutu/static',
        },

        System => {
            Name       => 'Qisutu',
            Version    => '0.0.30',
            InstanceID => 'qisutu',
            WebPath    => '/qisutu',
            BaseURL    => $ENV{QISUTU_BASE_URL} || '',
            TicketHook => 'Qisutu',
        },
    };
}

1;
