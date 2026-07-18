# Qisutu - Open Source Ticket System
# Copyright (C) 2026 Franziska Steps
# Qisutu - Kim-KI, https://qisutu.de
#
# SPDX-FileCopyrightText: 2026 Franziska Steps
# SPDX-License-Identifier: AGPL-3.0-or-later

{
    Name            => 'AdminTicketForms',
    Module          => 'AdminTicketForms',
    Title           => 'AdminTicketFormsTitle',
    Description     => 'AdminTicketFormsDescription',
    Icon            => '',
    URL             => 'index.pl?Page=AdminTicketForms',
    Type            => 'SubNavigation',
    Parent          => 'Admin',
    Order           => 915,
    VisibleFor      => [ 'admin' ],
    AccessType      => 'agent',
    AccessTypes     => [ 'agent' ],
    PermissionGroup => 'admin',
    PermissionMode  => 'ro',
    Permission      => 'admin.view',
    Active          => 1,
}
