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

    function closeViewMenu(container) {
        if (!container) {
            return;
        }

        var button = container.querySelector('[data-qisutu-ticket-list-view-button]');
        var menu = container.querySelector('[data-qisutu-ticket-list-view-menu]');

        if (button) {
            button.setAttribute('aria-expanded', 'false');
        }
        if (menu) {
            menu.hidden = true;
        }
    }

    function initViewMenu() {
        var container = document.querySelector('[data-qisutu-ticket-list-view-select]');
        if (!container) {
            return;
        }

        var button = container.querySelector('[data-qisutu-ticket-list-view-button]');
        var menu = container.querySelector('[data-qisutu-ticket-list-view-menu]');
        if (!button || !menu) {
            return;
        }

        button.addEventListener('click', function (event) {
            event.preventDefault();
            var open = button.getAttribute('aria-expanded') === 'true';
            button.setAttribute('aria-expanded', open ? 'false' : 'true');
            menu.hidden = open;
        });

        document.addEventListener('click', function (event) {
            if (!container.contains(event.target)) {
                closeViewMenu(container);
            }
        });

        document.addEventListener('keydown', function (event) {
            if (event.key === 'Escape') {
                closeViewMenu(container);
            }
        });
    }

    function initFilters() {
        var form = document.querySelector('[data-qisutu-ticket-list-filter-form]');
        if (!form) {
            return;
        }

        var filters = form.querySelectorAll('[data-qisutu-ticket-list-filter]');
        filters.forEach(function (filter) {
            filter.addEventListener('change', function () {
                form.submit();
            });
        });
    }

    function initPerPageControls() {
        var forms = document.querySelectorAll('[data-qisutu-ticket-list-per-page-form]');
        var allowed = {10: true, 20: true, 30: true, 40: true, 50: true};

        forms.forEach(function (form) {
            var select = form.querySelector('[data-qisutu-ticket-list-per-page]');
            if (!select) {
                return;
            }

            var storageKey = form.getAttribute('data-qisutu-ticket-list-per-page-storage') || '';
            var explicit = form.getAttribute('data-qisutu-ticket-list-per-page-explicit') === '1';
            var saved = '';

            if (storageKey) {
                try {
                    saved = window.localStorage.getItem(storageKey) || '';
                }
                catch (error) {
                    saved = '';
                }
            }

            if (!explicit && allowed[saved] && select.value !== saved) {
                select.value = saved;
                form.submit();
                return;
            }

            if (storageKey && allowed[select.value]) {
                try {
                    window.localStorage.setItem(storageKey, select.value);
                }
                catch (error) {
                    // The list remains usable when browser storage is unavailable.
                }
            }

            select.addEventListener('change', function () {
                if (!allowed[select.value]) {
                    return;
                }

                if (storageKey) {
                    try {
                        window.localStorage.setItem(storageKey, select.value);
                    }
                    catch (error) {
                        // Submit even when browser storage is unavailable.
                    }
                }

                form.submit();
            });
        });
    }

    function initColumnOverlay() {
        var overlay = document.querySelector('[data-qisutu-ticket-list-columns-overlay]');
        var openButton = document.querySelector('[data-qisutu-ticket-list-columns-open]');
        if (!overlay || !openButton) {
            return;
        }

        var closeButtons = overlay.querySelectorAll('[data-qisutu-ticket-list-columns-close]');
        var dialog = overlay.querySelector('.qisutu-ticket-list-column-dialog');

        function openOverlay() {
            overlay.hidden = false;
            document.body.classList.add('qisutu-overlay-open');
            var firstCheckbox = overlay.querySelector('input[type="checkbox"]');
            if (firstCheckbox) {
                firstCheckbox.focus();
            }
        }

        function closeOverlay() {
            overlay.hidden = true;
            document.body.classList.remove('qisutu-overlay-open');
            openButton.focus();
        }

        openButton.addEventListener('click', openOverlay);

        closeButtons.forEach(function (button) {
            button.addEventListener('click', closeOverlay);
        });

        overlay.addEventListener('click', function (event) {
            if (event.target === overlay) {
                closeOverlay();
            }
        });

        if (dialog) {
            dialog.addEventListener('click', function (event) {
                event.stopPropagation();
            });
        }

        document.addEventListener('keydown', function (event) {
            if (event.key === 'Escape' && !overlay.hidden) {
                closeOverlay();
            }
        });
    }

    function columnMinimumWidth(key) {
        var widths = {
            ticket_number: 118,
            title: 180,
            queue: 74,
            state: 78,
            priority: 92,
            customer: 105,
            customer_user: 132,
            owner: 108,
            responsible: 132,
            created: 138,
            changed: 138,
            age: 76,
            escalation_state: 142,
            next_escalation: 142,
            pending_until: 138
        };

        return widths[key] || 105;
    }

    function columnMaximumWidth(key) {
        var widths = {
            ticket_number: 160,
            title: 430,
            created: 190,
            changed: 190,
            next_escalation: 210,
            pending_until: 190
        };

        return widths[key] || 280;
    }

    function clampColumnWidth(key, width) {
        return Math.max(columnMinimumWidth(key), Math.min(columnMaximumWidth(key), Math.round(width)));
    }

    function readColumnWidths(storageKey) {
        try {
            var value = window.localStorage.getItem(storageKey);
            var parsed = value ? JSON.parse(value) : {};
            return parsed && typeof parsed === 'object' ? parsed : {};
        }
        catch (error) {
            return {};
        }
    }

    function writeColumnWidths(storageKey, widths) {
        try {
            window.localStorage.setItem(storageKey, JSON.stringify(widths));
        }
        catch (error) {
            return;
        }
    }

    function compactColumnWidth(table, key, heading) {
        var width = columnMinimumWidth(key);
        var headingLink = heading ? heading.querySelector('a') : null;

        if (headingLink) {
            width = Math.max(width, headingLink.scrollWidth + 10);
        }

        var cells = table.querySelectorAll('[data-qisutu-ticket-list-cell="' + cssEscape(key) + '"]');
        cells.forEach(function (cell) {
            width = Math.max(width, cell.scrollWidth + 2);
        });

        return clampColumnWidth(key, width);
    }

    function cssEscape(value) {
        if (window.CSS && typeof window.CSS.escape === 'function') {
            return window.CSS.escape(value);
        }

        return String(value).replace(/[^A-Za-z0-9_-]/g, '\\$&');
    }

    function initResizableTicketList(table) {
        var columns = Array.prototype.slice.call(table.querySelectorAll('col[data-qisutu-ticket-list-col]'));
        var headings = Array.prototype.slice.call(table.querySelectorAll('th[data-qisutu-ticket-list-heading]'));

        if (!columns.length || columns.length !== headings.length) {
            return;
        }

        var userID = table.getAttribute('data-qisutu-ticket-list-user-id') || '0';
        var storageKey = 'qisutu.ticketList.columnWidths.' + userID;
        var savedWidths = readColumnWidths(storageKey);
        var widths = {};

        function applyTableWidth() {
            var total = columns.reduce(function (sum, column) {
                var key = column.getAttribute('data-qisutu-ticket-list-col') || '';
                return sum + (widths[key] || columnMinimumWidth(key));
            }, 0);

            if (table.querySelector('[data-qisutu-ticket-list-select-col]')) {
                total += 48;
            }

            table.style.width = total + 'px';
            table.style.minWidth = total + 'px';
        }

        function setColumnWidth(key, width) {
            var column = table.querySelector('col[data-qisutu-ticket-list-col="' + cssEscape(key) + '"]');
            var heading = table.querySelector('th[data-qisutu-ticket-list-heading="' + cssEscape(key) + '"]');
            var cleanWidth = clampColumnWidth(key, width);

            if (!column) {
                return;
            }

            widths[key] = cleanWidth;
            column.style.width = cleanWidth + 'px';

            if (heading) {
                var handle = heading.querySelector('[data-qisutu-ticket-list-resize]');
                if (handle) {
                    handle.setAttribute('aria-valuenow', String(cleanWidth));
                    handle.setAttribute('aria-valuemin', String(columnMinimumWidth(key)));
                    handle.setAttribute('aria-valuemax', String(columnMaximumWidth(key)));
                }
            }
        }

        headings.forEach(function (heading) {
            var key = heading.getAttribute('data-qisutu-ticket-list-heading') || '';
            var savedWidth = Number(savedWidths[key]);
            var width = Number.isFinite(savedWidth) && savedWidth > 0
                ? savedWidth
                : compactColumnWidth(table, key, heading);

            setColumnWidth(key, width);
        });

        table.classList.add('qisutu-ticket-list-table-resized');
        applyTableWidth();

        headings.forEach(function (heading) {
            var key = heading.getAttribute('data-qisutu-ticket-list-heading') || '';
            var handle = heading.querySelector('[data-qisutu-ticket-list-resize]');
            if (!handle) {
                return;
            }

            handle.addEventListener('pointerdown', function (event) {
                if (event.button !== 0) {
                    return;
                }

                event.preventDefault();
                event.stopPropagation();

                var startX = event.clientX;
                var startWidth = widths[key];
                document.body.classList.add('qisutu-ticket-list-column-resizing');
                heading.classList.add('qisutu-ticket-list-column-active');

                function move(moveEvent) {
                    var nextWidth = clampColumnWidth(key, startWidth + moveEvent.clientX - startX);
                    setColumnWidth(key, nextWidth);
                    applyTableWidth();
                }

                function stop() {
                    document.removeEventListener('pointermove', move);
                    document.removeEventListener('pointerup', stop);
                    document.removeEventListener('pointercancel', stop);
                    document.body.classList.remove('qisutu-ticket-list-column-resizing');
                    heading.classList.remove('qisutu-ticket-list-column-active');
                    savedWidths[key] = widths[key];
                    writeColumnWidths(storageKey, savedWidths);
                }

                document.addEventListener('pointermove', move);
                document.addEventListener('pointerup', stop);
                document.addEventListener('pointercancel', stop);
            });

            handle.addEventListener('dblclick', function (event) {
                event.preventDefault();
                event.stopPropagation();
                delete savedWidths[key];
                setColumnWidth(key, compactColumnWidth(table, key, heading));
                applyTableWidth();
                writeColumnWidths(storageKey, savedWidths);
            });

            handle.addEventListener('keydown', function (event) {
                if (event.key !== 'ArrowLeft' && event.key !== 'ArrowRight') {
                    return;
                }

                event.preventDefault();
                event.stopPropagation();

                var step = event.shiftKey ? 25 : 10;
                var direction = event.key === 'ArrowRight' ? 1 : -1;
                setColumnWidth(key, widths[key] + direction * step);
                applyTableWidth();
                savedWidths[key] = widths[key];
                writeColumnWidths(storageKey, savedWidths);
            });
        });
    }

    function initResizableTicketLists() {
        var tables = document.querySelectorAll('[data-qisutu-ticket-list-resizable]');
        tables.forEach(initResizableTicketList);
    }


    function localDateTimeValue(date, endOfDay) {
        var value = new Date(date.getTime());
        if (endOfDay) {
            value.setHours(23, 59, 0, 0);
        }
        else {
            value.setHours(0, 0, 0, 0);
        }

        function two(number) {
            return String(number).padStart(2, '0');
        }

        return value.getFullYear() + '-' + two(value.getMonth() + 1) + '-' + two(value.getDate())
            + 'T' + two(value.getHours()) + ':' + two(value.getMinutes());
    }

    function updateDynamicSearchField(container) {
        var operator = container.querySelector('[data-qisutu-search-dynamic-operator]');
        if (!operator) {
            return;
        }

        var values = container.querySelectorAll('[data-qisutu-search-dynamic-value]');
        var valueTo = container.querySelector('[data-qisutu-search-dynamic-value-to]');
        var noValue = operator.value === '' || operator.value === 'empty' || operator.value === 'not_empty';
        var between = operator.value === 'between';

        values.forEach(function (field) {
            field.disabled = noValue;
            field.closest('label');
        });

        if (valueTo) {
            valueTo.disabled = noValue || !between;
            valueTo.hidden = !between;
        }

        container.classList.toggle('qisutu-ticket-search-dynamic-no-value', noValue);
    }

    function initSearchOverlay() {
        var overlay = document.querySelector('[data-qisutu-ticket-search-overlay]');
        var openButtons = document.querySelectorAll('[data-qisutu-ticket-search-open]');
        if (!overlay || !openButtons.length) {
            return;
        }

        var dialog = overlay.querySelector('.qisutu-ticket-search-dialog');
        var form = overlay.querySelector('[data-qisutu-ticket-search-form]');
        var closeButtons = overlay.querySelectorAll('[data-qisutu-ticket-search-close]');
        var clearButton = overlay.querySelector('[data-qisutu-ticket-search-clear]');
        var lastOpenButton = null;

        function openOverlay(event) {
            if (event) {
                event.preventDefault();
                lastOpenButton = event.currentTarget;
            }
            overlay.hidden = false;
            document.body.classList.add('qisutu-overlay-open');
            var firstInput = overlay.querySelector('input[name="SearchText"]');
            if (firstInput) {
                window.setTimeout(function () {
                    firstInput.focus();
                    firstInput.select();
                }, 0);
            }
        }

        function closeOverlay() {
            overlay.hidden = true;
            document.body.classList.remove('qisutu-overlay-open');
            if (lastOpenButton && document.contains(lastOpenButton)) {
                lastOpenButton.focus();
            }
        }

        openButtons.forEach(function (button) {
            button.addEventListener('click', openOverlay);
        });

        closeButtons.forEach(function (button) {
            button.addEventListener('click', closeOverlay);
        });

        overlay.addEventListener('click', function (event) {
            if (event.target === overlay) {
                closeOverlay();
            }
        });

        if (dialog) {
            dialog.addEventListener('click', function (event) {
                event.stopPropagation();
            });
        }

        document.addEventListener('keydown', function (event) {
            if (event.key === 'Escape' && !overlay.hidden) {
                closeOverlay();
            }
        });

        var dynamicFields = overlay.querySelectorAll('[data-qisutu-search-dynamic]');
        dynamicFields.forEach(function (container) {
            var operator = container.querySelector('[data-qisutu-search-dynamic-operator]');
            if (operator) {
                operator.addEventListener('change', function () {
                    updateDynamicSearchField(container);
                });
            }
            updateDynamicSearchField(container);
        });

        var quickPeriods = overlay.querySelectorAll('[data-qisutu-search-period]');
        quickPeriods.forEach(function (button) {
            button.addEventListener('click', function () {
                if (!form) {
                    return;
                }

                var from = form.querySelector('[name="SearchCreatedFrom"]');
                var to = form.querySelector('[name="SearchCreatedTo"]');
                if (!from || !to) {
                    return;
                }

                var now = new Date();
                var start = new Date(now.getTime());
                var end = new Date(now.getTime());
                var period = button.getAttribute('data-qisutu-search-period') || '';

                if (period === 'yesterday') {
                    start.setDate(start.getDate() - 1);
                    end.setDate(end.getDate() - 1);
                }
                else if (period === '7' || period === '30') {
                    start.setDate(start.getDate() - (Number(period) - 1));
                }
                else if (period === 'year') {
                    start = new Date(now.getFullYear(), 0, 1);
                }

                from.value = localDateTimeValue(start, false);
                to.value = localDateTimeValue(end, true);
            });
        });

        if (clearButton && form) {
            clearButton.addEventListener('click', function (event) {
                event.preventDefault();

                form.querySelectorAll('input:not([type="hidden"])').forEach(function (input) {
                    if (input.type === 'checkbox' || input.type === 'radio') {
                        input.checked = input.name.indexOf('SearchScope') === 0;
                    }
                    else {
                        input.value = '';
                    }
                });

                form.querySelectorAll('select').forEach(function (select) {
                    Array.prototype.forEach.call(select.options, function (option) {
                        option.selected = false;
                    });
                    if (select.name === 'SearchMode') {
                        select.value = 'all';
                    }
                    else if (!select.multiple) {
                        select.selectedIndex = 0;
                    }
                });

                dynamicFields.forEach(updateDynamicSearchField);
                var firstInput = form.querySelector('input[name="SearchText"]');
                if (firstInput) {
                    firstInput.focus();
                }
            });
        }
    }

    function initBulkAction() {
        var overlay = document.querySelector('[data-qisutu-ticket-bulk-overlay]');
        var openButton = document.querySelector('[data-qisutu-ticket-bulk-open]');
        var clearButton = document.querySelector('[data-qisutu-ticket-bulk-clear]');
        var selectAll = document.querySelector('[data-qisutu-ticket-bulk-select-all]');
        var ticketCheckboxes = Array.prototype.slice.call(document.querySelectorAll('[data-qisutu-ticket-bulk-ticket]'));

        if (!overlay || !openButton || !ticketCheckboxes.length) {
            return;
        }

        var dialog = overlay.querySelector('.qisutu-ticket-bulk-dialog');
        var form = overlay.querySelector('[data-qisutu-ticket-bulk-form]');
        var closeButtons = overlay.querySelectorAll('[data-qisutu-ticket-bulk-close]');
        var stateSelect = overlay.querySelector('[data-qisutu-ticket-bulk-state]');
        var pendingField = overlay.querySelector('[data-qisutu-ticket-bulk-pending]');
        var pendingInput = pendingField ? pendingField.querySelector('input') : null;
        var buttonCount = document.querySelector('[data-qisutu-ticket-bulk-button-count]');
        var overlayCounts = overlay.querySelectorAll('[data-qisutu-ticket-bulk-count], [data-qisutu-ticket-bulk-submit-count]');

        function selectedCount() {
            return ticketCheckboxes.filter(function (checkbox) {
                return checkbox.checked;
            }).length;
        }

        function updateSelection() {
            var count = selectedCount();

            ticketCheckboxes.forEach(function (checkbox) {
                var row = checkbox.closest('[data-qisutu-ticket-bulk-row]');
                if (row) {
                    row.classList.toggle('qisutu-ticket-list-row-selected', checkbox.checked);
                }
            });

            if (buttonCount) {
                buttonCount.textContent = String(count);
            }
            overlayCounts.forEach(function (element) {
                element.textContent = String(count);
            });

            openButton.disabled = count === 0;
            openButton.setAttribute('aria-disabled', count === 0 ? 'true' : 'false');
            if (clearButton) {
                clearButton.hidden = count === 0;
            }

            if (selectAll) {
                selectAll.checked = count > 0 && count === ticketCheckboxes.length;
                selectAll.indeterminate = count > 0 && count < ticketCheckboxes.length;
            }
        }

        function updatePendingField() {
            if (!stateSelect || !pendingField || !pendingInput) {
                return;
            }

            var option = stateSelect.options[stateSelect.selectedIndex];
            var pending = option && option.getAttribute('data-state-type') === 'pending';
            pendingField.hidden = !pending;
            pendingInput.disabled = !pending;
            pendingInput.required = pending;
            if (!pending) {
                pendingInput.value = '';
            }
        }

        function openOverlay(event) {
            if (event) {
                event.preventDefault();
            }
            if (!selectedCount()) {
                return;
            }
            overlay.hidden = false;
            document.body.classList.add('qisutu-overlay-open');
            updateSelection();
            updatePendingField();
            var firstSelect = overlay.querySelector('select');
            if (firstSelect) {
                window.setTimeout(function () {
                    firstSelect.focus();
                }, 0);
            }
        }

        function closeOverlay() {
            overlay.hidden = true;
            document.body.classList.remove('qisutu-overlay-open');
            openButton.focus();
        }

        ticketCheckboxes.forEach(function (checkbox) {
            checkbox.addEventListener('change', updateSelection);
        });

        if (selectAll) {
            selectAll.addEventListener('change', function () {
                ticketCheckboxes.forEach(function (checkbox) {
                    checkbox.checked = selectAll.checked;
                });
                updateSelection();
            });
        }

        if (clearButton) {
            clearButton.addEventListener('click', function () {
                ticketCheckboxes.forEach(function (checkbox) {
                    checkbox.checked = false;
                });
                updateSelection();
            });
        }

        openButton.addEventListener('click', openOverlay);
        closeButtons.forEach(function (button) {
            button.addEventListener('click', closeOverlay);
        });

        overlay.addEventListener('click', function (event) {
            if (event.target === overlay) {
                closeOverlay();
            }
        });

        if (dialog) {
            dialog.addEventListener('click', function (event) {
                event.stopPropagation();
            });
        }

        if (stateSelect) {
            stateSelect.addEventListener('change', updatePendingField);
        }

        if (form) {
            form.addEventListener('submit', function (event) {
                var count = selectedCount();
                if (!count) {
                    event.preventDefault();
                    closeOverlay();
                    return;
                }

                var message = form.getAttribute('data-qisutu-ticket-bulk-confirm') || '';
                message = message.replace('{count}', String(count));
                if (message && !window.confirm(message)) {
                    event.preventDefault();
                }
            });
        }

        document.addEventListener('keydown', function (event) {
            if (event.key === 'Escape' && !overlay.hidden) {
                closeOverlay();
            }
        });

        updateSelection();
        updatePendingField();

        if (overlay.getAttribute('data-qisutu-ticket-bulk-open-on-load') === '1') {
            openOverlay();
        }
    }

    function init() {
        initViewMenu();
        initFilters();
        initPerPageControls();
        initColumnOverlay();
        initSearchOverlay();
        initBulkAction();
        initResizableTicketLists();
    }

    if (document.readyState === 'loading') {
        document.addEventListener('DOMContentLoaded', init);
    }
    else {
        init();
    }
}());
