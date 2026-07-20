# Qisutu - Open Source Ticket System
# SPDX-License-Identifier: AGPL-3.0-or-later

{
    Name            => 'AdminSMTPGoogleMail',
    Module          => 'AdminSMTPAccount',
    Title           => 'AdminSMTPGoogleTitle',
    Description     => 'AdminSMTPGoogleDescription',
    Icon            => '',
    URL             => 'index.pl?Page=AdminSMTPGoogleMail',
    Type            => 'ProgramOnly',
    Parent          => 'Admin',
    Order           => 907.3,
    VisibleFor      => [ 'admin' ],
    AccessType      => 'agent',
    AccessTypes     => [ 'agent' ],
    PermissionGroup => 'admin',
    PermissionMode  => 'ro',
    Permission      => 'admin.view',
    Active          => 1,
}
