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

    function formatBytes(bytes) {
        if (bytes >= 1024 * 1024) {
            return (bytes / (1024 * 1024)).toFixed(1) + ' MB';
        }
        if (bytes >= 1024) {
            return Math.round(bytes / 1024) + ' KB';
        }
        return bytes + ' B';
    }

    function initAttachments() {
        var input = document.querySelector('[data-qisutu-attachment-input]');
        var list = document.querySelector('[data-qisutu-attachment-list]');
        if (!input || !list) {
            return;
        }

        var empty = list.querySelector('[data-qisutu-attachment-empty]');
        var removeLabel = list.getAttribute('data-qisutu-attachment-remove-label') || 'Remove';
        var maxBytes = Number(input.getAttribute('data-qisutu-attachment-max-bytes') || 0);
        var maxLabel = input.getAttribute('data-qisutu-attachment-max-label') || '';
        var overlay = document.querySelector('[data-qisutu-attachment-limit-overlay]');
        var overlayMessage = document.querySelector('[data-qisutu-attachment-limit-message]');
        var overlayClose = document.querySelector('[data-qisutu-attachment-limit-close]');
        var selectedFiles = [];

        function syncInput() {
            if (typeof DataTransfer === 'undefined') {
                return;
            }
            var transfer = new DataTransfer();
            selectedFiles.forEach(function (file) {
                transfer.items.add(file);
            });
            input.files = transfer.files;
        }

        function render() {
            Array.prototype.slice.call(list.querySelectorAll('[data-qisutu-attachment-row]')).forEach(function (row) {
                row.remove();
            });
            selectedFiles.forEach(function (file, index) {
                var row = document.createElement('div');
                row.className = 'qisutu-ticket-reply-attachment';
                row.setAttribute('data-qisutu-attachment-row', '1');

                var name = document.createElement('span');
                name.textContent = file.name + ' (' + formatBytes(file.size) + ')';
                row.appendChild(name);

                var remove = document.createElement('button');
                remove.type = 'button';
                remove.className = 'qisutu-button qisutu-button-secondary';
                remove.textContent = removeLabel;
                remove.addEventListener('click', function () {
                    selectedFiles.splice(index, 1);
                    syncInput();
                    render();
                });
                row.appendChild(remove);
                list.appendChild(row);
            });
            if (empty) {
                empty.classList.toggle('qisutu-hidden', selectedFiles.length > 0);
            }
        }

        function showLimit(file) {
            if (!overlay) {
                return;
            }
            if (overlayMessage) {
                var message = overlayMessage.getAttribute('data-qisutu-message-template') || '';
                message = message.replace(/\{\{Filename\}\}/g, file.name);
                message = message.replace(/\{\{FileSize\}\}/g, formatBytes(file.size));
                message = message.replace(/\{\{MaxSize\}\}/g, maxLabel);
                overlayMessage.textContent = message;
            }
            overlay.hidden = false;
        }

        input.addEventListener('change', function () {
            Array.prototype.slice.call(input.files || []).forEach(function (file) {
                if (maxBytes && file.size > maxBytes) {
                    showLimit(file);
                    return;
                }
                selectedFiles.push(file);
            });
            syncInput();
            render();
        });

        if (overlayClose && overlay) {
            overlayClose.addEventListener('click', function () {
                overlay.hidden = true;
            });
        }
    }

    if (document.readyState === 'loading') {
        document.addEventListener('DOMContentLoaded', initAttachments);
    }
    else {
        initAttachments();
    }
}());
