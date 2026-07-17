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

    function setupDeleteOverlay() {
        var overlay = document.querySelector('[data-qisutu-mail-delete-overlay]');
        var form = document.querySelector('[data-qisutu-mail-delete-form]');
        var idInput = document.querySelector('[data-qisutu-mail-delete-id-input]');
        var account = document.querySelector('[data-qisutu-mail-delete-account]');
        var closeButton = document.querySelector('[data-qisutu-mail-delete-close]');
        var lastTrigger = null;

        if (!overlay || !form || !idInput || !account || !closeButton) {
            return;
        }

        function closeOverlay() {
            overlay.hidden = true;
            overlay.setAttribute('aria-hidden', 'true');
            document.body.classList.remove('qisutu-overlay-open');
            idInput.value = '';
            account.textContent = '';

            if (lastTrigger) {
                lastTrigger.focus();
            }
        }

        function openOverlay(trigger) {
            var accountID = trigger.getAttribute('data-qisutu-mail-delete-id') || '';
            var accountName = trigger.getAttribute('data-qisutu-mail-delete-name') || '';

            if (!/^\d+$/.test(accountID)) {
                return;
            }

            lastTrigger = trigger;
            idInput.value = accountID;
            account.textContent = accountName;
            overlay.hidden = false;
            overlay.setAttribute('aria-hidden', 'false');
            document.body.classList.add('qisutu-overlay-open');
            closeButton.focus();
        }

        document.querySelectorAll('[data-qisutu-mail-delete-open]').forEach(function (trigger) {
            trigger.addEventListener('click', function () {
                openOverlay(trigger);
            });
        });

        closeButton.addEventListener('click', closeOverlay);

        overlay.addEventListener('click', function (event) {
            if (event.target === overlay) {
                closeOverlay();
            }
        });

        document.addEventListener('keydown', function (event) {
            if (event.key === 'Escape' && !overlay.hidden) {
                closeOverlay();
            }
        });

        form.addEventListener('submit', function (event) {
            if (!/^\d+$/.test(idInput.value)) {
                event.preventDefault();
                closeOverlay();
            }
        });
    }

    document.addEventListener('DOMContentLoaded', function () {
        document.querySelectorAll('[data-qisutu-port-target]').forEach(setupPort);
        setupDeleteOverlay();
    });
}());
