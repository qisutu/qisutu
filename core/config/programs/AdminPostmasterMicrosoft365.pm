# Qisutu - Open Source Ticket System
# Copyright (C) 2026 Franziska Steps
# SPDX-License-Identifier: AGPL-3.0-or-later

{
    Name            => 'AdminPostmasterMicrosoft365',
    Module          => 'AdminPostmasterIMAPAccounts',
    Title           => 'AdminMicrosoft365Navigation',
    Description     => 'AdminMicrosoft365Description',
    Icon            => '',
    URL             => 'index.pl?Page=AdminPostmasterMicrosoft365',
    Type            => 'ProgramOnly',
    Parent          => 'Admin',
    Order           => 905.3,
    VisibleFor      => [ 'admin' ],
    AccessType      => 'agent',
    AccessTypes     => [ 'agent' ],
    PermissionGroup => 'admin',
    PermissionMode  => 'ro',
    Permission      => 'admin.view',
    Active          => 1,
}
