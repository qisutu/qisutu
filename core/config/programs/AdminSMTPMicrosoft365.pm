# Qisutu - Open Source Ticket System
# SPDX-License-Identifier: AGPL-3.0-or-later

{
    Name            => 'AdminSMTPMicrosoft365',
    Module          => 'AdminSMTPAccount',
    Title           => 'AdminSMTPMicrosoft365Title',
    Description     => 'AdminSMTPMicrosoft365Description',
    Icon            => '',
    URL             => 'index.pl?Page=AdminSMTPMicrosoft365',
    Type            => 'ProgramOnly',
    Parent          => 'Admin',
    Order           => 907.2,
    VisibleFor      => [ 'admin' ],
    AccessType      => 'agent',
    AccessTypes     => [ 'agent' ],
    PermissionGroup => 'admin',
    PermissionMode  => 'ro',
    Permission      => 'admin.view',
    Active          => 1,
}
