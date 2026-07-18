# Qisutu - Open Source Ticket System
# Copyright (C) 2026 Franziska Steps
# SPDX-License-Identifier: AGPL-3.0-or-later

{
    Name            => 'AdminCMDBTypes',
    Module          => 'AdminCMDBTypes',
    Title           => 'AdminCMDBTypesTitle',
    Description     => 'AdminCMDBTypesDescription',
    Icon            => '',
    URL             => 'index.pl?Page=AdminCMDBTypes',
    Type            => 'SubNavigation',
    Parent          => 'Admin',
    Order           => 918,
    VisibleFor      => [ 'admin' ],
    AccessType      => 'agent',
    AccessTypes     => [ 'agent' ],
    PermissionGroup => 'admin',
    PermissionMode  => 'ro',
    Permission      => 'admin.view',
    Active          => 1,
}
