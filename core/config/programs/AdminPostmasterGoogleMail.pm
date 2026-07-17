# Qisutu - Open Source Ticket System
# Copyright (C) 2026 Franziska Steps
# SPDX-License-Identifier: AGPL-3.0-or-later

{
    Name            => 'AdminPostmasterGoogleMail',
    Module          => 'AdminPostmasterIMAPAccounts',
    Title           => 'AdminGoogleMailNavigation',
    Description     => 'AdminGoogleMailDescription',
    Icon            => '',
    URL             => 'index.pl?Page=AdminPostmasterGoogleMail',
    Type            => 'ProgramOnly',
    Parent          => 'Admin',
    Order           => 905.4,
    VisibleFor      => [ 'admin' ],
    AccessType      => 'agent',
    AccessTypes     => [ 'agent' ],
    PermissionGroup => 'admin',
    PermissionMode  => 'ro',
    Permission      => 'admin.view',
    Active          => 1,
}
