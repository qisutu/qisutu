# Qisutu - Open Source Ticket System
# Copyright (C) 2026 Franziska Steps
# SPDX-License-Identifier: AGPL-3.0-or-later

{
    Name            => 'AdminTimeAccountingActivityTypes',
    Module          => 'AdminTimeAccountingActivityTypes',
    Title           => 'AdminTimeAccountingActivityTypesTitle',
    Description     => 'AdminTimeAccountingActivityTypesDescription',
    Icon            => '',
    URL             => 'index.pl?Page=AdminTimeAccountingActivityTypes',
    Type            => 'SubNavigation',
    Parent          => 'Admin',
    Order           => 910,
    VisibleFor      => [ 'admin' ],
    AccessType      => 'agent',
    AccessTypes     => [ 'agent' ],
    PermissionGroup => 'admin',
    PermissionMode  => 'rw',
    Permission      => 'admin.view',
    Active          => 1,
}
