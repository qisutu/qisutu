# Qisutu - Open Source Ticket System
# SPDX-License-Identifier: AGPL-3.0-or-later

{
    Name            => 'AdminCommunicationLog',
    Module          => 'AdminCommunicationLog',
    Title           => 'CommunicationLogTitle',
    Description     => 'CommunicationLogDescription',
    Icon            => '',
    URL             => 'index.pl?Page=AdminCommunicationLog',
    Type            => 'SubNavigation',
    Parent          => 'Admin',
    Order           => 675,
    VisibleFor      => [ 'admin' ],
    AccessType      => 'agent',
    AccessTypes     => [ 'agent' ],
    PermissionGroup => 'admin',
    PermissionMode  => 'ro',
    Permission      => 'admin.view',
    Active          => 1,
}
