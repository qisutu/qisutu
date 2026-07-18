# Qisutu - Open Source Ticket System
# Copyright (C) 2026 Franziska Steps
# SPDX-License-Identifier: AGPL-3.0-or-later

{
    Name            => 'CMDB',
    Module          => 'CMDBItems',
    Title           => 'NavigationCMDB',
    Description     => 'CMDBDescription',
    Icon            => 'C',
    URL             => 'index.pl?Page=CMDBItems',
    Type            => 'MainNavigation',
    Parent          => '',
    Order           => 300,
    VisibleFor      => [ 'agent' ],
    AccessType      => 'agent',
    AccessTypes     => [ 'agent' ],
    PermissionGroup => '',
    PermissionMode  => '',
    Permission      => '',
    Active          => 1,
}
