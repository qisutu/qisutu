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
                    input.dispatchEvent(new CustomEvent('qisutu:autocomplete-selected', {
                        bubbles: true,
                        detail: { item: item }
                    }));
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
                    var hadSelection = hidden.value !== '';
                    hidden.value = '';
                    if (hadSelection) {
                        input.dispatchEvent(new CustomEvent('qisutu:autocomplete-cleared', {
                            bubbles: true
                        }));
                    }
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

    function initCustomerInfo() {
        var input = document.querySelector('[data-qisutu-customer-user-autocomplete]');
        var hidden = document.getElementById('qisutu-agent-ticket-create-customer-user-id');
        var panel = document.querySelector('[data-qisutu-customer-info]');

        if (!input || !hidden || !panel) {
            return;
        }

        var url = panel.getAttribute('data-qisutu-customer-info-url') || '';
        var empty = panel.querySelector('[data-qisutu-customer-info-empty]');
        var loading = panel.querySelector('[data-qisutu-customer-info-loading]');
        var error = panel.querySelector('[data-qisutu-customer-info-error]');
        var content = panel.querySelector('[data-qisutu-customer-info-content]');
        var customerList = panel.querySelector('[data-qisutu-customer-info-customer]');
        var customerUserList = panel.querySelector('[data-qisutu-customer-info-customer-user]');
        var requestIndex = 0;
        var controller = null;

        function setVisible(node, visible) {
            if (node) {
                node.classList.toggle('qisutu-hidden', !visible);
            }
        }

        function reset() {
            requestIndex += 1;
            if (controller) {
                try { controller.abort(); } catch (abortError) {}
                controller = null;
            }
            if (customerList) {
                customerList.innerHTML = '';
            }
            if (customerUserList) {
                customerUserList.innerHTML = '';
            }
            setVisible(empty, true);
            setVisible(loading, false);
            setVisible(error, false);
            setVisible(content, false);
        }

        function renderFields(target, fields) {
            target.innerHTML = '';

            (Array.isArray(fields) ? fields : []).forEach(function (field) {
                var row = document.createElement('div');
                var label = document.createElement('dt');
                var value = document.createElement('dd');

                row.className = 'qisutu-agent-ticket-create-customer-info-row';
                label.textContent = field.label || '';
                value.textContent = field.value === null || typeof field.value === 'undefined' || field.value === ''
                    ? '–'
                    : String(field.value);

                row.appendChild(label);
                row.appendChild(value);
                target.appendChild(row);
            });
        }

        function load(customerUserID) {
            customerUserID = String(customerUserID || '').trim();
            if (!url || !customerUserID) {
                reset();
                return;
            }

            requestIndex += 1;
            var currentIndex = requestIndex;

            if (controller) {
                try { controller.abort(); } catch (abortError) {}
            }
            controller = typeof AbortController !== 'undefined' ? new AbortController() : null;

            setVisible(empty, false);
            setVisible(loading, true);
            setVisible(error, false);
            setVisible(content, false);

            fetch(url + (url.indexOf('?') === -1 ? '?' : '&') + 'CustomerUserID=' + encodeURIComponent(customerUserID), {
                credentials: 'same-origin',
                signal: controller ? controller.signal : undefined
            }).then(function (response) {
                if (!response.ok) {
                    throw new Error('customer info failed');
                }
                return response.json();
            }).then(function (data) {
                if (currentIndex !== requestIndex) {
                    return;
                }
                if (!data || !data.success) {
                    throw new Error('customer info unavailable');
                }

                renderFields(customerList, data.customer && data.customer.fields);
                renderFields(customerUserList, data.customer_user && data.customer_user.fields);
                setVisible(loading, false);
                setVisible(error, false);
                setVisible(content, true);
            }).catch(function (loadError) {
                if (loadError && loadError.name === 'AbortError') {
                    return;
                }
                if (currentIndex !== requestIndex) {
                    return;
                }
                setVisible(loading, false);
                setVisible(error, true);
                setVisible(content, false);
            });
        }

        input.addEventListener('qisutu:autocomplete-selected', function () {
            load(hidden.value);
        });

        input.addEventListener('qisutu:autocomplete-cleared', reset);

        if (hidden.value) {
            load(hidden.value);
        }
        else {
            reset();
        }
    }

    function initServices() {
        var customerInput = document.querySelector('[data-qisutu-customer-user-autocomplete]');
        var customerHidden = document.getElementById('qisutu-agent-ticket-create-customer-user-id');
        var service = document.querySelector('[data-qisutu-create-service]');
        var info = document.querySelector('[data-qisutu-create-sla-info]');

        if (!customerInput || !customerHidden || !service) {
            return;
        }

        var url = service.getAttribute('data-qisutu-service-options-url') || '';
        var placeholderText = service.options.length ? service.options[0].textContent : '';
        var initialServiceID = service.value || '';
        var itemsByID = {};
        var requestIndex = 0;
        var controller = null;

        function text(selector, value) {
            var node = info ? info.querySelector(selector) : null;
            if (node) {
                node.textContent = value === null || typeof value === 'undefined' || value === '' ? '–' : String(value);
            }
        }

        function renderInfo(item) {
            if (!info) {
                return;
            }

            var visible = !!(item && item.sla_id);
            info.classList.toggle('qisutu-hidden', !visible);
            if (!visible) {
                return;
            }

            text('[data-qisutu-sla-name]', item.sla_name);
            text('[data-qisutu-sla-calendar]', item.calendar_name);
            text('[data-qisutu-sla-source]', item.assignment_source_label);
            text('[data-qisutu-sla-update-mode]', item.update_mode_label);
            text('[data-qisutu-sla-first]', item.first_response_minutes);
            text('[data-qisutu-sla-update]', item.update_minutes);
            text('[data-qisutu-sla-solution]', item.solution_minutes);
        }

        function refreshServiceTree() {
            if (window.QisutuServiceTree && typeof window.QisutuServiceTree.refresh === 'function') {
                window.QisutuServiceTree.refresh(service);
            }
        }

        function clearOptions() {
            service.innerHTML = '';
            var option = document.createElement('option');
            option.value = '';
            option.textContent = placeholderText;
            service.appendChild(option);
            itemsByID = {};
            renderInfo(null);
            refreshServiceTree();
        }

        function renderOptions(items, selectedID) {
            service.innerHTML = '';
            var placeholder = document.createElement('option');
            placeholder.value = '';
            placeholder.textContent = placeholderText;
            service.appendChild(placeholder);
            itemsByID = {};

            (Array.isArray(items) ? items : []).forEach(function (item) {
                var id = String(item.id || '');
                if (!id) {
                    return;
                }
                itemsByID[id] = item;
                var option = document.createElement('option');
                option.value = id;
                option.textContent = item.full_label || item.label || '';
                option.disabled = !item.selectable;
                option.setAttribute('data-qisutu-service-node', '1');
                option.setAttribute('data-parent-id', String(item.parent_id || 0));
                option.setAttribute('data-service-name', item.name || item.label || '');
                option.setAttribute('data-service-full-name', item.full_label || item.label || '');
                option.setAttribute('data-service-selectable', item.selectable ? '1' : '0');
                option.setAttribute('data-service-has-children', item.has_children ? '1' : '0');
                option.setAttribute('data-service-depth', String(item.depth || 0));
                service.appendChild(option);
            });

            selectedID = String(selectedID || '');
            if (selectedID && itemsByID[selectedID] && itemsByID[selectedID].selectable) {
                service.value = selectedID;
                renderInfo(itemsByID[selectedID]);
            }
            else {
                service.value = '';
                renderInfo(null);
            }
            refreshServiceTree();
        }

        function load(customerUserID, selectedID) {
            customerUserID = String(customerUserID || '').trim();
            requestIndex += 1;
            var currentIndex = requestIndex;

            if (controller) {
                try { controller.abort(); } catch (abortError) {}
            }
            controller = typeof AbortController !== 'undefined' ? new AbortController() : null;

            if (!url) {
                clearOptions();
                return;
            }

            fetch(url + (url.indexOf('?') === -1 ? '?' : '&') + 'CustomerUserID=' + encodeURIComponent(customerUserID), {
                credentials: 'same-origin',
                signal: controller ? controller.signal : undefined
            }).then(function (response) {
                if (!response.ok) {
                    throw new Error('service options failed');
                }
                return response.json();
            }).then(function (data) {
                if (currentIndex !== requestIndex) {
                    return;
                }
                renderOptions(data && data.success ? data.items : [], selectedID);
            }).catch(function (error) {
                if (error && error.name === 'AbortError') {
                    return;
                }
                if (currentIndex === requestIndex) {
                    clearOptions();
                }
            });
        }

        service.addEventListener('change', function () {
            var item = itemsByID[String(service.value || '')];
            renderInfo(item);
        });

        customerInput.addEventListener('qisutu:autocomplete-selected', function () {
            load(customerHidden.value, '');
        });
        customerInput.addEventListener('qisutu:autocomplete-cleared', function () {
            load('', service.value || '');
        });

        load(customerHidden.value, initialServiceID);
    }

    function initPendingUntil() {
        var status = document.querySelector('[data-qisutu-create-status]');
        var field = document.querySelector('[data-qisutu-create-pending-until-field]');
        var input = document.getElementById('qisutu-agent-ticket-create-pending-until');

        if (!status || !field || !input) {
            return;
        }

        function update() {
            var selected = status.options[status.selectedIndex];
            var stateType = selected ? (selected.getAttribute('data-state-type') || '') : '';
            var isPending = stateType === 'pending';

            field.classList.toggle('qisutu-hidden', !isPending);
            input.required = isPending;
        }

        status.addEventListener('change', update);
        update();
    }

    function initQueueTemplate() {
        var queue = document.querySelector('[data-qisutu-create-queue]');
        var body = document.querySelector('[data-qisutu-create-body]');
        var dynamicFields = document.querySelector('[data-qisutu-create-dynamic-fields]');
        var customerInput = document.querySelector('[data-qisutu-customer-user-autocomplete]');
        var ownerInput = document.getElementById('qisutu-agent-ticket-create-owner');
        var contextFields = [
            document.getElementById('qisutu-agent-ticket-create-title-field'),
            document.getElementById('qisutu-agent-ticket-create-state'),
            document.getElementById('qisutu-agent-ticket-create-priority'),
            document.getElementById('qisutu-agent-ticket-create-pending-until')
        ].filter(function (field) { return !!field; });

        if (!queue || !body) {
            return;
        }

        var lastTemplate = body.value || '';
        var templateRequestIndex = 0;

        function editorGetData() {
            if (body.qisutuEditor && body.qisutuEditor.getData) {
                return body.qisutuEditor.getData() || '';
            }
            return body.value || '';
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

        var dynamicFieldsRequestIndex = 0;

        function fieldValue(id) {
            var field = document.getElementById(id);
            return field ? (field.value || '') : '';
        }

        function templateURL(baseURL, queueID) {
            var parameters = {
                QueueID: queueID,
                CustomerUserID: fieldValue('qisutu-agent-ticket-create-customer-user-id'),
                OwnerUserID: fieldValue('qisutu-agent-ticket-create-owner-id'),
                Title: fieldValue('qisutu-agent-ticket-create-title-field'),
                StateID: fieldValue('qisutu-agent-ticket-create-state'),
                PriorityID: fieldValue('qisutu-agent-ticket-create-priority'),
                PendingUntil: fieldValue('qisutu-agent-ticket-create-pending-until')
            };
            var parts = [];

            Object.keys(parameters).forEach(function (key) {
                parts.push(encodeURIComponent(key) + '=' + encodeURIComponent(parameters[key] || ''));
            });

            return baseURL + (baseURL.indexOf('?') === -1 ? '?' : '&') + parts.join('&');
        }

        function templateLoad(force) {
            var url = queue.getAttribute('data-qisutu-template-url') || '';
            var queueID = queue.value || '';
            var previousTemplate = lastTemplate;

            templateRequestIndex += 1;
            var currentRequest = templateRequestIndex;

            if (!url || !queueID) {
                if (force) {
                    lastTemplate = '';
                    editorSetData('');
                }
                return;
            }

            fetch(templateURL(url, queueID), {
                credentials: 'same-origin'
            }).then(function (response) {
                if (!response.ok) {
                    throw new Error('template failed');
                }
                return response.json();
            }).then(function (data) {
                if (currentRequest !== templateRequestIndex || !data || !data.success) {
                    return;
                }

                var newTemplate = data.body_template || '';
                var currentBody = editorGetData();
                if (force || !currentBody.trim() || currentBody === previousTemplate) {
                    editorSetData(newTemplate);
                    lastTemplate = newTemplate;
                }
            }).catch(function () {
                // Die bereits vorhandene Eingabe bleibt bei einem Ladefehler erhalten.
            });
        }

        function dynamicFieldsLoad(queueID) {
            var url = queue.getAttribute('data-qisutu-dynamic-fields-url') || '';
            dynamicFieldsRequestIndex += 1;
            var currentRequest = dynamicFieldsRequestIndex;

            if (!dynamicFields) {
                return;
            }

            if (!url || !queueID) {
                dynamicFields.innerHTML = '';
                return;
            }

            dynamicFields.innerHTML = '';

            fetch(url + (url.indexOf('?') === -1 ? '?' : '&') + 'QueueID=' + encodeURIComponent(queueID), {
                credentials: 'same-origin'
            }).then(function (response) {
                if (!response.ok) {
                    throw new Error('dynamic fields failed');
                }
                return response.json();
            }).then(function (data) {
                if (currentRequest !== dynamicFieldsRequestIndex) {
                    return;
                }
                dynamicFields.innerHTML = data && data.success ? (data.html || '') : '';
            }).catch(function () {
                if (currentRequest === dynamicFieldsRequestIndex) {
                    dynamicFields.innerHTML = '';
                }
            });
        }

        queue.addEventListener('change', function () {
            var queueID = queue.value || '';

            dynamicFieldsLoad(queueID);
            templateLoad(true);
        });

        contextFields.forEach(function (field) {
            field.addEventListener('change', function () {
                templateLoad(false);
            });
        });

        [customerInput, ownerInput].forEach(function (input) {
            if (!input) {
                return;
            }
            input.addEventListener('qisutu:autocomplete-selected', function () {
                templateLoad(false);
            });
            input.addEventListener('qisutu:autocomplete-cleared', function () {
                templateLoad(false);
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

        function freeEmailValid(value) {
            var candidate = String(value || '').trim();
            var addressMatch;

            if (!candidate || /[;,]/.test(candidate)) {
                return false;
            }

            addressMatch = candidate.match(/^.*?<([^<>]+)>\s*$/);
            if (addressMatch) {
                candidate = String(addressMatch[1] || '').trim();
            }

            return /^[A-Z0-9._%+\-]+@[A-Z0-9.\-]+\.[A-Z]{2,}$/i.test(candidate);
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
                var allowsFreeEmail = input.hasAttribute('data-qisutu-autocomplete-free-email');

                input.setCustomValidity('');
                if (needsSelection && (!hidden || !hidden.value)) {
                    if (allowsFreeEmail && freeEmailValid(input.value)) {
                        return;
                    }
                    input.setCustomValidity(
                        allowsFreeEmail
                            ? (input.getAttribute('data-qisutu-free-email-invalid') || selectionMessage)
                            : selectionMessage
                    );
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

    function initDynamicMultiSelects() {
        document.addEventListener('change', function (event) {
            var select = event.target && event.target.closest
                ? event.target.closest('select[data-qisutu-dynamic-multiselect]')
                : null;

            if (!select) {
                return;
            }

            var emptyOption = select.querySelector('option[value=""]');
            var hasSelectedValue = Array.prototype.slice.call(select.options).some(function (option) {
                return option.value !== '' && option.selected;
            });

            if (emptyOption && hasSelectedValue) {
                emptyOption.selected = false;
            }
        });
    }

    function init() {
        initAutocomplete();
        initCustomerInfo();
        initServices();
        initPendingUntil();
        initQueueTemplate();
        initAttachments();
        initFormValidation();
        initDynamicMultiSelects();
    }

    if (document.readyState === 'loading') {
        document.addEventListener('DOMContentLoaded', init);
    }
    else {
        init();
    }
}());
