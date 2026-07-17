# Qisutu - Open Source Ticket System
# Copyright (C) 2026 Franziska Steps
# Qisutu - Kim-KI, https://qisutu.de
#
# This file is part of Qisutu.
#
# SPDX-FileCopyrightText: 2026 Franziska Steps
# SPDX-License-Identifier: AGPL-3.0-or-later

{
    Name            => 'AdminPostmasterFilters',
    Module          => 'AdminPostmasterFilters',
    Title           => 'AdminPostmasterFiltersTitle',
    Description     => 'AdminPostmasterFiltersDescription',
    Icon            => '',
    URL             => 'index.pl?Page=AdminPostmasterFilters',
    Type            => 'SubNavigation',
    Parent          => 'Admin',
    Order           => 907,
    VisibleFor      => [ 'admin' ],
    AccessType      => 'agent',
    AccessTypes     => [ 'agent' ],
    PermissionGroup => 'admin',
    PermissionMode  => 'ro',
    Permission      => 'admin.view',
    Active          => 1,
}
