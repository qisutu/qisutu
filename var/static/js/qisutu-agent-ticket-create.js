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

    function initAutocomplete() {
        var inputs = document.querySelectorAll('[data-qisutu-autocomplete]');
        var controllers = [];

        if (!inputs.length) {
            return;
        }

        function closeAll(except) {
            document.querySelectorAll('[data-qisutu-autocomplete-results]').forEach(function (results) {
                if (except && results === except) {
                    return;
                }
                results.classList.add('qisutu-hidden');
                results.innerHTML = '';
            });
        }

        function urlWithTerm(url, term) {
            return url + (url.indexOf('?') === -1 ? '?' : '&') + 'Term=' + encodeURIComponent(term);
        }

        function renderMessage(results, className, text) {
            results.innerHTML = '';
            var item = document.createElement('div');
            item.className = className;
            item.textContent = text;
            results.appendChild(item);
            results.classList.remove('qisutu-hidden');
        }

        function renderItems(input, hidden, results, items) {
            results.innerHTML = '';

            if (!items.length) {
                renderMessage(results, 'qisutu-autocomplete-empty', input.getAttribute('data-qisutu-autocomplete-empty') || 'Keine Treffer gefunden.');
                return;
            }

            items.forEach(function (item) {
                var button = document.createElement('button');
                var label = document.createElement('strong');
                button.type = 'button';
                button.className = 'qisutu-autocomplete-item';
                label.textContent = item.label || '';
                button.appendChild(label);

                if (item.description) {
                    var description = document.createElement('span');
                    description.textContent = item.description;
                    button.appendChild(description);
                }

                button.addEventListener('mousedown', function (event) {
                    event.preventDefault();
                    input.value = item.label || '';
                    input.setAttribute('data-qisutu-autocomplete-selected-label', input.value);
                    input.setCustomValidity('');
                    if (hidden) {
                        hidden.value = item.id || '';
                    }
                    closeAll();
                });

                results.appendChild(button);
            });

            results.classList.remove('qisutu-hidden');
        }

        inputs.forEach(function (input) {
            var hiddenID = input.getAttribute('data-qisutu-autocomplete-hidden') || '';
            var hidden = hiddenID ? document.getElementById(hiddenID) : null;
            var field = input.closest('.qisutu-autocomplete') || input.parentNode;
            var results = field ? field.querySelector('[data-qisutu-autocomplete-results]') : null;
            var url = input.getAttribute('data-qisutu-autocomplete-url') || '';
            var minLength = parseInt(input.getAttribute('data-qisutu-autocomplete-min') || '2', 10);
            var requestIndex = 0;
            var timer = null;

            if (!results || !url) {
                return;
            }

            input.setAttribute('data-qisutu-autocomplete-selected-label', hidden && hidden.value ? input.value : '');

            input.addEventListener('input', function () {
                var term = input.value.trim();
                var selectedLabel = input.getAttribute('data-qisutu-autocomplete-selected-label') || '';

                input.setCustomValidity('');
                if (hidden && term !== selectedLabel) {
                    hidden.value = '';
                }

                window.clearTimeout(timer);
                requestIndex += 1;
                var currentIndex = requestIndex;

                if (term.length < minLength) {
                    closeAll();
                    return;
                }

                timer = window.setTimeout(function () {
                    controllers.forEach(function (controller) {
                        try { controller.abort(); } catch (error) {}
                    });
                    controllers = [];

                    var controller = typeof AbortController !== 'undefined' ? new AbortController() : null;
                    if (controller) {
                        controllers.push(controller);
                    }

                    renderMessage(results, 'qisutu-autocomplete-empty', input.getAttribute('data-qisutu-autocomplete-loading') || 'Suche läuft ...');

                    fetch(urlWithTerm(url, term), {
                        credentials: 'same-origin',
                        signal: controller ? controller.signal : undefined
                    }).then(function (response) {
                        if (!response.ok) {
                            throw new Error('lookup failed');
                        }
                        return response.json();
                    }).then(function (data) {
                        if (currentIndex !== requestIndex) {
                            return;
                        }
                        renderItems(input, hidden, results, Array.isArray(data.items) ? data.items : []);
                    }).catch(function (error) {
                        if (error && error.name === 'AbortError') {
                            return;
                        }
                        if (currentIndex === requestIndex) {
                            renderMessage(results, 'qisutu-autocomplete-empty', input.getAttribute('data-qisutu-autocomplete-error') || 'Die Suche konnte nicht geladen werden.');
                        }
                    });
                }, 220);
            });

            input.addEventListener('focus', function () {
                if (results.children.length) {
                    closeAll(results);
                    results.classList.remove('qisutu-hidden');
                }
            });

            input.addEventListener('keydown', function (event) {
                if (event.key === 'Escape') {
                    closeAll();
                }
            });
        });

        document.addEventListener('mousedown', function (event) {
            if (!event.target.closest || !event.target.closest('.qisutu-autocomplete')) {
                closeAll();
            }
        });
    }

    function initQueueTemplate() {
        var queue = document.querySelector('[data-qisutu-create-queue]');
        var body = document.querySelector('[data-qisutu-create-body]');

        if (!queue || !body) {
            return;
        }

        function editorSetData(value) {
            body.value = value || '';
            if (body.qisutuEditor && body.qisutuEditor.setData) {
                body.qisutuEditor.setData(value || '');
                return;
            }

            var attempts = 0;
            var timer = window.setInterval(function () {
                attempts += 1;
                if (body.qisutuEditor && body.qisutuEditor.setData) {
                    window.clearInterval(timer);
                    body.qisutuEditor.setData(value || '');
                }
                else if (attempts > 40) {
                    window.clearInterval(timer);
                }
            }, 100);
        }

        queue.addEventListener('change', function () {
            var url = queue.getAttribute('data-qisutu-template-url') || '';
            var queueID = queue.value || '';

            if (!url || !queueID) {
                editorSetData('');
                return;
            }

            fetch(url + (url.indexOf('?') === -1 ? '?' : '&') + 'QueueID=' + encodeURIComponent(queueID), {
                credentials: 'same-origin'
            }).then(function (response) {
                if (!response.ok) {
                    throw new Error('template failed');
                }
                return response.json();
            }).then(function (data) {
                if (data && data.success) {
                    editorSetData(data.body_template || '');
                }
            }).catch(function () {
                // Die bereits vorhandene Eingabe bleibt bei einem Ladefehler erhalten.
            });
        });
    }

    function initAttachments() {
        var form = document.querySelector('[data-qisutu-agent-ticket-create-form]');
        var input = document.querySelector('[data-qisutu-attachment-input]');
        var list = document.querySelector('[data-qisutu-attachment-list]');
        var empty = document.querySelector('[data-qisutu-attachment-empty]');
        var overlay = document.querySelector('[data-qisutu-attachment-limit-overlay]');
        var overlayMessage = document.querySelector('[data-qisutu-attachment-limit-message]');
        var overlayClose = document.querySelector('[data-qisutu-attachment-limit-close]');
        var selectedFiles = [];
        var canRewrite = false;

        if (!form || !input || !list) {
            return;
        }

        var maxBytes = Number(input.getAttribute('data-qisutu-attachment-max-bytes') || 0);
        var maxLabel = input.getAttribute('data-qisutu-attachment-max-label') || '';
        var removeLabel = list.getAttribute('data-qisutu-attachment-remove-label') || 'Entfernen';
        var messageTemplate = overlayMessage ? (overlayMessage.getAttribute('data-qisutu-message-template') || '') : '';

        function newTransfer() {
            try {
                return typeof DataTransfer === 'undefined' ? null : new DataTransfer();
            }
            catch (error) {
                return null;
            }
        }

        function detectRewrite() {
            var transfer = newTransfer();
            if (!transfer) {
                return false;
            }
            try {
                input.files = transfer.files;
                return true;
            }
            catch (error) {
                return false;
            }
        }

        function formatSize(size) {
            size = Number(size || 0);
            if (size >= 1024 * 1024 * 1024) {
                return (Math.round(size / 1024 / 1024 / 1024 * 10) / 10) + ' GB';
            }
            if (size >= 1024 * 1024) {
                return (Math.round(size / 1024 / 1024 * 10) / 10) + ' MB';
            }
            if (size >= 1024) {
                return (Math.round(size / 1024 * 10) / 10) + ' KB';
            }
            return size + ' B';
        }

        function tooLarge(file) {
            return !!(file && maxBytes > 0 && Number(file.size || 0) > maxBytes);
        }

        function syncInput() {
            if (!canRewrite) {
                return;
            }
            var transfer = newTransfer();
            if (!transfer) {
                return;
            }
            selectedFiles.forEach(function (file) {
                transfer.items.add(file);
            });
            input.files = transfer.files;
        }

        function render() {
            list.querySelectorAll('.qisutu-ticket-reply-attachment-items').forEach(function (node) {
                node.remove();
            });

            if (empty) {
                empty.classList.toggle('qisutu-hidden', selectedFiles.length > 0);
            }

            if (!selectedFiles.length) {
                return;
            }

            var ul = document.createElement('ul');
            ul.className = 'qisutu-ticket-reply-attachment-items';

            selectedFiles.forEach(function (file, index) {
                var li = document.createElement('li');
                var info = document.createElement('span');
                var remove = document.createElement('button');
                info.textContent = file.name + ' (' + formatSize(file.size) + ')';
                remove.type = 'button';
                remove.className = 'qisutu-ticket-reply-attachment-remove';
                remove.textContent = removeLabel;
                remove.addEventListener('click', function () {
                    selectedFiles.splice(index, 1);
                    if (canRewrite) {
                        syncInput();
                    }
                    else {
                        input.value = '';
                        selectedFiles = [];
                    }
                    render();
                });
                li.appendChild(info);
                li.appendChild(remove);
                ul.appendChild(li);
            });

            list.appendChild(ul);
        }

        function overlayOpen(file) {
            if (!overlay) {
                return;
            }
            var text = messageTemplate || 'Der Anhang „{{Filename}}“ ist mit {{FileSize}} größer als die erlaubten {{MaxSize}}.';
            text = text.replace(/\{\{Filename\}\}/g, file.name || 'attachment');
            text = text.replace(/\{\{FileSize\}\}/g, formatSize(file.size));
            text = text.replace(/\{\{MaxSize\}\}/g, maxLabel);
            if (overlayMessage) {
                overlayMessage.textContent = text;
            }
            overlay.hidden = false;
            if (overlayClose) {
                overlayClose.focus();
            }
        }

        function overlayHide() {
            if (overlay) {
                overlay.hidden = true;
            }
        }

        canRewrite = detectRewrite();

        input.addEventListener('change', function () {
            var files = Array.prototype.slice.call(input.files || []);
            var oversized = files.filter(tooLarge);
            var allowed = files.filter(function (file) { return !tooLarge(file); });

            if (canRewrite) {
                allowed.forEach(function (file) { selectedFiles.push(file); });
                syncInput();
            }
            else if (oversized.length) {
                input.value = '';
                selectedFiles = [];
            }
            else {
                selectedFiles = allowed;
            }

            render();
            if (oversized.length) {
                overlayOpen(oversized[0]);
            }
        });

        form.addEventListener('submit', function (event) {
            var files = canRewrite ? selectedFiles : Array.prototype.slice.call(input.files || []);
            var oversized = files.filter(tooLarge);
            if (oversized.length) {
                event.preventDefault();
                event.stopPropagation();
                overlayOpen(oversized[0]);
                return;
            }
            syncInput();
        });

        if (overlayClose) {
            overlayClose.addEventListener('click', overlayHide);
        }
        if (overlay) {
            overlay.addEventListener('click', function (event) {
                if (event.target === overlay) {
                    overlayHide();
                }
            });
        }
        document.addEventListener('keydown', function (event) {
            if (event.key === 'Escape' && overlay && !overlay.hidden) {
                overlayHide();
            }
        });

        render();
    }

    function initFormValidation() {
        var form = document.querySelector('[data-qisutu-agent-ticket-create-form]');
        if (!form) {
            return;
        }

        function bodyHasOwnText(html) {
            var container = document.createElement('div');
            container.innerHTML = html || '';
            container.querySelectorAll('.qisutu-mail-salutation, .qisutu-mail-signature').forEach(function (node) {
                node.remove();
            });
            return (container.textContent || '').replace(/\u00a0/g, ' ').trim() !== '';
        }

        form.addEventListener('submit', function (event) {
            var language = (document.documentElement.getAttribute('lang') || 'en').toLowerCase();
            var selectionMessage = language.indexOf('de') === 0
                ? 'Bitte wählen Sie einen Eintrag aus der Trefferliste aus.'
                : 'Please select an entry from the result list.';
            var invalid = null;
            var body = form.querySelector('[data-qisutu-create-body]');
            var errorBox = document.querySelector('[data-qisutu-create-error]');

            form.querySelectorAll('[data-qisutu-autocomplete]').forEach(function (input) {
                var hiddenID = input.getAttribute('data-qisutu-autocomplete-hidden') || '';
                var hidden = hiddenID ? document.getElementById(hiddenID) : null;
                var needsSelection = input.required || input.value.trim() !== '';

                input.setCustomValidity('');
                if (needsSelection && (!hidden || !hidden.value)) {
                    input.setCustomValidity(selectionMessage);
                    invalid = invalid || input;
                }
            });

            if (invalid) {
                event.preventDefault();
                invalid.reportValidity();
                invalid.focus();
                return;
            }

            if (body) {
                var html = body.qisutuEditor && body.qisutuEditor.getData
                    ? body.qisutuEditor.getData()
                    : body.value;

                if (!bodyHasOwnText(html)) {
                    event.preventDefault();
                    var bodyMessage = body.getAttribute('data-qisutu-body-required-message') || 'Please enter a message.';
                    if (errorBox) {
                        errorBox.textContent = bodyMessage;
                        errorBox.classList.remove('qisutu-hidden');
                        errorBox.scrollIntoView({ behavior: 'smooth', block: 'center' });
                    }
                    if (body.qisutuEditor && body.qisutuEditor.editing && body.qisutuEditor.editing.view) {
                        body.qisutuEditor.editing.view.focus();
                    }
                    else {
                        body.focus();
                    }
                }
            }
        }, true);
    }

    function init() {
        initAutocomplete();
        initQueueTemplate();
        initAttachments();
        initFormValidation();
    }

    if (document.readyState === 'loading') {
        document.addEventListener('DOMContentLoaded', init);
    }
    else {
        init();
    }
}());
