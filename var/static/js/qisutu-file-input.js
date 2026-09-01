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

    function labels() {
        var body = document.body;
        return {
            choose: body ? (body.getAttribute('data-qisutu-file-choose-label') || 'Choose file') : 'Choose file',
            empty: body ? (body.getAttribute('data-qisutu-file-empty-label') || 'No file selected') : 'No file selected'
        };
    }

    function refresh(input) {
        var wrapper = input.closest('.qisutu-file-input');
        var summary = wrapper ? wrapper.querySelector('.qisutu-file-input-summary') : null;
        var files = Array.prototype.slice.call(input.files || []);
        var text = files.length ? files.map(function (file) { return file.name; }).join(', ') : labels().empty;

        if (summary && summary.textContent !== text) {
            summary.textContent = text;
        }
        if (wrapper) {
            wrapper.classList.toggle('qisutu-file-input-has-files', files.length > 0);
        }
    }

    function enhance(input) {
        var wrapper;
        var choose;
        var summary;

        if (!input || input.getAttribute('data-qisutu-file-input-enhanced') === '1' || !input.parentNode) {
            return;
        }

        wrapper = document.createElement('span');
        wrapper.className = 'qisutu-file-input';
        input.parentNode.insertBefore(wrapper, input);
        wrapper.appendChild(input);

        choose = document.createElement('span');
        choose.className = 'qisutu-file-input-choose';
        choose.setAttribute('aria-hidden', 'true');
        choose.textContent = labels().choose;

        summary = document.createElement('span');
        summary.className = 'qisutu-file-input-summary';
        summary.setAttribute('aria-hidden', 'true');

        wrapper.appendChild(choose);
        wrapper.appendChild(summary);
        input.setAttribute('data-qisutu-file-input-enhanced', '1');
        input.addEventListener('change', function () { refresh(input); });
        input.qisutuFileInputRefresh = function () { refresh(input); };
        refresh(input);
    }

    function enhanceWithin(root) {
        if (!root || root.nodeType !== 1 && root.nodeType !== 9) {
            return;
        }
        if (root.matches && root.matches('input[type="file"]')) {
            enhance(root);
        }
        if (root.querySelectorAll) {
            root.querySelectorAll('input[type="file"]').forEach(enhance);
        }
    }

    function refreshAll() {
        document.querySelectorAll('input[type="file"][data-qisutu-file-input-enhanced="1"]').forEach(refresh);
    }

    function init() {
        var refreshQueued = false;
        var observer;

        enhanceWithin(document);

        observer = new MutationObserver(function (records) {
            records.forEach(function (record) {
                Array.prototype.forEach.call(record.addedNodes || [], enhanceWithin);
            });

            if (!refreshQueued) {
                refreshQueued = true;
                window.requestAnimationFrame(function () {
                    refreshQueued = false;
                    refreshAll();
                });
            }
        });
        observer.observe(document.body, { childList: true, subtree: true });

        document.addEventListener('reset', function () {
            window.setTimeout(refreshAll, 0);
        }, true);
    }

    if (document.readyState === 'loading') {
        document.addEventListener('DOMContentLoaded', init);
    }
    else {
        init();
    }
}());
