# Qisutu - Open Source Ticket System
# Copyright (C) 2026 Franziska Steps
# SPDX-License-Identifier: AGPL-3.0-or-later

{
    Name            => 'AdminCSVImports',
    Module          => 'AdminCSVImports',
    Title           => 'AdminCSVImportsTitle',
    Description     => 'AdminCSVImportsDescription',
    Icon            => '',
    URL             => 'index.pl?Page=AdminCSVImports',
    Type            => 'SubNavigation',
    Parent          => 'Admin',
    Order           => 904,
    VisibleFor      => [ 'admin' ],
    AccessType      => 'agent',
    AccessTypes     => [ 'agent' ],
    PermissionGroup => 'admin',
    PermissionMode  => 'ro',
    Permission      => 'admin.view',
    Active          => 1,
}
