# Qisutu - Open Source Ticket System
# Copyright (C) 2026 Franziska Steps
# SPDX-License-Identifier: AGPL-3.0-or-later

{
    Name            => 'AdminCMDBImports',
    Module          => 'AdminCMDBImports',
    Title           => 'AdminCMDBImportsTitle',
    Description     => 'AdminCMDBImportsDescription',
    Icon            => '',
    URL             => 'index.pl?Page=AdminCMDBImports',
    Type            => 'SubNavigation',
    Parent          => 'Admin',
    Order           => 919,
    VisibleFor      => [ 'admin' ],
    AccessType      => 'agent',
    AccessTypes     => [ 'agent' ],
    PermissionGroup => 'admin',
    PermissionMode  => 'ro',
    Permission      => 'admin.view',
    Active          => 1,
}
