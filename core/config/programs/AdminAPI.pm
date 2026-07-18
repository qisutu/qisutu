# Qisutu - Open Source Ticket System
# SPDX-License-Identifier: AGPL-3.0-or-later

{
    Name            => 'AdminAPI',
    Module          => 'AdminAPI',
    Title           => 'AdminAPITitle',
    Description     => 'AdminAPIDescription',
    Icon            => '',
    URL             => 'index.pl?Page=AdminAPI',
    Type            => 'SubNavigation',
    Parent          => 'Admin',
    Order           => 908,
    VisibleFor      => [ 'admin' ],
    AccessType      => 'agent',
    AccessTypes     => [ 'agent' ],
    PermissionGroup => 'admin',
    PermissionMode  => 'ro',
    Permission      => 'admin.view',
    Active          => 1,
}
