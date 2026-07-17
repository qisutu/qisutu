# Qisutu - Open Source Ticket System
# Copyright (C) 2026 Franziska Steps
# SPDX-License-Identifier: AGPL-3.0-or-later

{
    Name            => 'AdminPostmasterIMAPAccount',
    Module          => 'AdminPostmasterIMAPAccounts',
    Title           => 'AdminStandardIMAPNavigation',
    Description     => 'AdminStandardIMAPDescription',
    Icon            => '',
    URL             => 'index.pl?Page=AdminPostmasterIMAPAccount',
    Type            => 'ProgramOnly',
    Parent          => 'Admin',
    Order           => 905.2,
    VisibleFor      => [ 'admin' ],
    AccessType      => 'agent',
    AccessTypes     => [ 'agent' ],
    PermissionGroup => 'admin',
    PermissionMode  => 'ro',
    Permission      => 'admin.view',
    Active          => 1,
}
