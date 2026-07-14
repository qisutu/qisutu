# Qisutu - Open Source Ticket System
# Copyright (C) 2026 Franziska Steps
# Qisutu - Kim-KI, https://qisutu.de
#
# This file is part of Qisutu.
#
# Qisutu is free software: you can redistribute it and/or modify
# it under the terms of the GNU Affero General Public License as published by
# the Free Software Foundation, either version 3 of the License, or
# (at your option) any later version.
#
# Qisutu is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the
# GNU Affero General Public License for more details.
#
# You should have received a copy of the GNU Affero General Public License
# along with Qisutu. If not, see <https://www.gnu.org/licenses/>.
#
# SPDX-FileCopyrightText: 2026 Franziska Steps
# SPDX-License-Identifier: AGPL-3.0-or-later

[
    {
        Key          => 'system.http_type',
        Module       => 'System',
        Group        => 'System',
        Name         => 'Translate:SystemSettingHTTPType',
        Description  => 'Translate:SystemSettingHTTPTypeDescription',
        Type         => 'select',
        Default      => 'https',
        PossibleValues => [
            { Value => 'https', Label => 'HTTPS' },
            { Value => 'http',  Label => 'HTTP' },
        ],
        SortOrder    => 100,
        Active       => 1,
    },
    {
        Key          => 'system.fqdn',
        Module       => 'System',
        Group        => 'System',
        Name         => 'Translate:SystemSettingFQDN',
        Description  => 'Translate:SystemSettingFQDNDescription',
        Type         => 'text',
        Default      => '',
        SortOrder    => 200,
        Active       => 1,
    },
    {
        Key          => 'system.web_path',
        Module       => 'System',
        Group        => 'System',
        Name         => 'Translate:SystemSettingWebPath',
        Description  => 'Translate:SystemSettingWebPathDescription',
        Type         => 'text',
        Default      => '',
        SortOrder    => 300,
        Active       => 1,
    },
    {
        Key          => 'system.default_language',
        Module       => 'System',
        Group        => 'System',
        Name         => 'Translate:SystemSettingDefaultLanguage',
        Description  => 'Translate:SystemSettingDefaultLanguageDescription',
        Type         => 'select',
        Default      => '',
        PossibleValues => [
            { Value => 'de', Label => 'Deutsch' },
            { Value => 'en', Label => 'English' },
            { Value => 'fr', Label => 'Français' },
            { Value => 'it', Label => 'Italiano' },
        ],
        SortOrder    => 400,
        Active       => 1,
    },
    {
        Key          => 'system.admin_email',
        Module       => 'System',
        Group        => 'System',
        Name         => 'Translate:SystemSettingAdminEmail',
        Description  => 'Translate:SystemSettingAdminEmailDescription',
        Type         => 'text',
        Default      => '',
        SortOrder    => 450,
        Active       => 1,
    },
    {
        Key          => 'system.timezone',
        Module       => 'System',
        Group        => 'System',
        Name         => 'Translate:SystemSettingTimezone',
        Description  => 'Translate:SystemSettingTimezoneDescription',
        Type         => 'text',
        Default      => 'Europe/Paris',
        SortOrder    => 475,
        Active       => 1,
    },
    {
        Key          => 'system.ticket_hook',
        Module       => 'System',
        Group        => 'System',
        Name         => 'Translate:SystemSettingTicketHook',
        Description  => 'Translate:SystemSettingTicketHookDescription',
        Type         => 'text',
        Default      => 'Qisutu',
        SortOrder    => 500,
        Active       => 1,
    },
    {
        Key          => 'system.attachment_max_size_mb',
        Module       => 'System',
        Group        => 'System',
        Name         => 'Translate:SystemSettingAttachmentMaxSize',
        Description  => 'Translate:SystemSettingAttachmentMaxSizeDescription',
        Type         => 'integer',
        Default      => 25,
        Minimum      => 1,
        Maximum      => 10240,
        Unit         => 'MB',
        SortOrder    => 600,
        Active       => 1,
    },
]
