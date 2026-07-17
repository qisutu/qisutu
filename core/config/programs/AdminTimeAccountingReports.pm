# Qisutu - Open Source Ticket System
# Copyright (C) 2026 Franziska Steps
# SPDX-License-Identifier: AGPL-3.0-or-later

{
    Name            => 'AdminTimeAccountingReports',
    Module          => 'AdminTimeAccountingReports',
    Title           => 'AdminTimeAccountingReportTitle',
    Description     => 'AdminTimeAccountingReportDescription',
    Icon            => '',
    URL             => 'index.pl?Page=AdminTimeAccountingReports',
    Type            => 'SubNavigation',
    Parent          => 'Admin',
    Order           => 911,
    VisibleFor      => [ 'admin' ],
    AccessType      => 'agent',
    AccessTypes     => [ 'agent' ],
    PermissionGroup => 'admin',
    PermissionMode  => 'ro',
    Permission      => 'admin.view',
    Active          => 1,
}
