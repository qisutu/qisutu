# Qisutu - Open Source Ticket System
# SPDX-License-Identifier: AGPL-3.0-or-later

{
    Name            => 'AdminSMTPStandard',
    Module          => 'AdminSMTPAccount',
    Title           => 'AdminSMTPStandardTitle',
    Description     => 'AdminSMTPStandardDescription',
    Icon            => '',
    URL             => 'index.pl?Page=AdminSMTPStandard',
    Type            => 'ProgramOnly',
    Parent          => 'Admin',
    Order           => 907.1,
    VisibleFor      => [ 'admin' ],
    AccessType      => 'agent',
    AccessTypes     => [ 'agent' ],
    PermissionGroup => 'admin',
    PermissionMode  => 'ro',
    Permission      => 'admin.view',
    Active          => 1,
}
