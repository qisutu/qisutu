/*
 * Qisutu - Open Source Ticket System
 * Copyright (C) 2026 Franziska Steps
 * Qisutu - Kim-KI, https://qisutu.de
 *
 * This file is part of Qisutu.
 *
 * Qisutu is free software: you can redistribute it and/or modify
 * it under the terms of the GNU Affero General Public License as published by
 * the Free Software Foundation, either version 3 of the License, or
 * (at your option) any later version.
 *
 * Qisutu is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the
 * GNU Affero General Public License for more details.
 *
 * You should have received a copy of the GNU Affero General Public License
 * along with Qisutu. If not, see <https://www.gnu.org/licenses/>.
 *
 * SPDX-FileCopyrightText: 2026 Franziska Steps
 * SPDX-License-Identifier: AGPL-3.0-or-later
 */

(function () {
    'use strict';

    var ports = {
        smtp: '25',
        smtp_starttls: '587',
        smtps: '465',
        imap: '143',
        imap_starttls: '143',
        imaps: '993'
    };

    function setupPort(select) {
        var targetName = select.getAttribute('data-qisutu-port-target');
        var form = select.closest('form');
        var target;

        if (!form || !targetName) {
            return;
        }

        target = form.querySelector('[name="' + targetName + '"]');

        if (!target) {
            return;
        }

        select.addEventListener('change', function () {
            var value = select.value;

            if (ports[value]) {
                target.value = ports[value];
            }
        });
    }

    document.addEventListener('DOMContentLoaded', function () {
        document.querySelectorAll('[data-qisutu-port-target]').forEach(setupPort);
    });
}());

