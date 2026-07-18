# Qisutu - Open Source Ticket System
# Copyright (C) 2026 Franziska Steps
# SPDX-License-Identifier: AGPL-3.0-or-later

{
    Name            => 'AdminCMDBItems',
    Module          => 'CMDBItems',
    Title           => 'CMDBItemsTitle',
    Description     => 'CMDBDescription',
    Icon            => '',
    URL             => 'index.pl?Page=AdminCMDBItems',
    Type            => 'SubNavigation',
    Parent          => 'Admin',
    Order           => 917,
    VisibleFor      => [ 'admin' ],
    AccessType      => 'agent',
    AccessTypes     => [ 'agent' ],
    PermissionGroup => 'admin',
    PermissionMode  => 'ro',
    Permission      => 'admin.view',
    Active          => 1,
}
