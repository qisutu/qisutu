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

    function debounce(callback, delay) {
        var timer;
        return function () {
            var args = arguments;
            window.clearTimeout(timer);
            timer = window.setTimeout(function () { callback.apply(null, args); }, delay);
        };
    }

    function getJSON(url, query) {
        var separator = url.indexOf('?') === -1 ? '?' : '&';
        return window.fetch(url + separator + 'Query=' + encodeURIComponent(query || ''), {
            headers: { 'X-Requested-With': 'XMLHttpRequest' },
            credentials: 'same-origin'
        }).then(function (response) {
            if (!response.ok) { throw new Error('request failed'); }
            return response.json();
        });
    }

    function initFieldOptions() {
        document.querySelectorAll('[data-qisutu-cmdb-field-form]').forEach(function (form) {
            var type = form.querySelector('[data-qisutu-cmdb-field-type]');
            var box = form.querySelector('[data-qisutu-cmdb-field-options]');
            var textarea = box ? box.querySelector('textarea') : null;
            if (!type || !box || !textarea) { return; }
            function update() {
                var usesOptions = type.value === 'dropdown' || type.value === 'multiselect';
                box.classList.toggle('qisutu-hidden', !usesOptions);
                textarea.required = usesOptions;
            }
            type.addEventListener('change', update);
            update();
        });
    }

    function initCustomerSelector() {
        var overlay = document.querySelector('[data-qisutu-cmdb-customer-overlay]');
        var open = document.querySelector('[data-qisutu-cmdb-customer-open]');
        if (!overlay || !open) { return; }
        var close = overlay.querySelector('[data-qisutu-cmdb-customer-close]');
        var search = overlay.querySelector('[data-qisutu-cmdb-customer-search]');
        var results = overlay.querySelector('[data-qisutu-cmdb-customer-results]');
        var customerID = document.querySelector('[data-qisutu-cmdb-customer-id]');
        var current = document.querySelector('[data-qisutu-cmdb-customer-current]');
        var userSelect = document.querySelector('[data-qisutu-cmdb-customer-user]');

        function hide() {
            overlay.hidden = true;
            document.body.classList.remove('qisutu-overlay-open');
        }
        function show() {
            overlay.hidden = false;
            document.body.classList.add('qisutu-overlay-open');
            search.value = '';
            results.innerHTML = '<p class="qisutu-form-hint">Bitte geben Sie einen Namen oder eine Kundennummer ein.</p>';
            window.setTimeout(function () { search.focus(); }, 0);
        }
        function loadUsers(id) {
            if (!userSelect) { return; }
            userSelect.innerHTML = '<option value="">–</option>';
            if (!id) { return; }
            var url = userSelect.getAttribute('data-options-url') || '';
            window.fetch(url + '&CustomerID=' + encodeURIComponent(id), { credentials: 'same-origin' })
                .then(function (response) { return response.json(); })
                .then(function (data) {
                    (data.items || []).forEach(function (item) {
                        var option = document.createElement('option');
                        option.value = item.id;
                        option.textContent = item.label + (item.meta ? ' · ' + item.meta : '');
                        userSelect.appendChild(option);
                    });
                }).catch(function () {});
        }
        function choose(item) {
            customerID.value = item.id;
            current.innerHTML = '';
            var strong = document.createElement('strong');
            strong.textContent = item.label + (item.meta ? ' · ' + item.meta : '');
            current.appendChild(strong);
            loadUsers(item.id);
            hide();
        }
        var searchCustomers = debounce(function () {
            var query = search.value.trim();
            if (!query) {
                results.innerHTML = '<p class="qisutu-form-hint">Bitte geben Sie einen Namen oder eine Kundennummer ein.</p>';
                return;
            }
            results.innerHTML = '<p class="qisutu-form-hint">Suche läuft …</p>';
            getJSON(search.getAttribute('data-url') || '', query).then(function (data) {
                results.innerHTML = '';
                if (!(data.items || []).length) {
                    results.innerHTML = '<p class="qisutu-form-hint">Keine Kunden gefunden.</p>';
                    return;
                }
                data.items.forEach(function (item) {
                    var button = document.createElement('button');
                    button.type = 'button';
                    button.className = 'qisutu-cmdb-customer-result';
                    var name = document.createElement('strong');
                    name.textContent = item.label;
                    var meta = document.createElement('span');
                    meta.textContent = item.meta || '';
                    button.appendChild(name);
                    button.appendChild(meta);
                    button.addEventListener('click', function () { choose(item); });
                    results.appendChild(button);
                });
            }).catch(function () {
                results.innerHTML = '<p class="qisutu-form-error">Die Kundensuche konnte nicht geladen werden.</p>';
            });
        }, 220);

        open.addEventListener('click', show);
        if (close) { close.addEventListener('click', hide); }
        overlay.addEventListener('click', function (event) { if (event.target === overlay) { hide(); } });
        search.addEventListener('input', searchCustomers);
        document.addEventListener('keydown', function (event) { if (event.key === 'Escape' && !overlay.hidden) { hide(); } });
        document.querySelectorAll('[data-qisutu-cmdb-customer-clear]').forEach(function (button) {
            button.addEventListener('click', function () {
                customerID.value = '';
                current.innerHTML = '<span class="qisutu-form-hint">–</span>';
                loadUsers('');
            });
        });
    }

    function initAutocomplete() {
        document.querySelectorAll('[data-qisutu-cmdb-autocomplete]').forEach(function (input) {
            var field = input.closest('.qisutu-autocomplete');
            var results = field ? field.querySelector('[data-qisutu-autocomplete-results]') : null;
            var hidden = document.getElementById(input.getAttribute('data-qisutu-autocomplete-hidden') || '');
            if (!results || !hidden) { return; }
            var search = debounce(function () {
                var query = input.value.trim();
                hidden.value = '';
                if (!query) { results.classList.add('qisutu-hidden'); results.innerHTML = ''; return; }
                getJSON(input.getAttribute('data-qisutu-autocomplete-url') || '', query).then(function (data) {
                    results.innerHTML = '';
                    (data.items || []).forEach(function (item) {
                        var button = document.createElement('button');
                        button.type = 'button';
                        button.className = 'qisutu-autocomplete-item';
                        button.innerHTML = '<strong></strong><span></span>';
                        button.querySelector('strong').textContent = item.label || '';
                        button.querySelector('span').textContent = item.meta || '';
                        button.addEventListener('click', function () {
                            input.value = item.label || '';
                            hidden.value = item.id || '';
                            results.classList.add('qisutu-hidden');
                        });
                        results.appendChild(button);
                    });
                    results.classList.toggle('qisutu-hidden', !(data.items || []).length);
                }).catch(function () { results.classList.add('qisutu-hidden'); });
            }, 220);
            input.addEventListener('input', search);
        });
    }

    function initTicketLink() {
        var overlay = document.querySelector('[data-qisutu-cmdb-ticket-overlay]');
        if (!overlay) { return; }
        var input = overlay.querySelector('[data-qisutu-cmdb-ticket-search]');
        var results = overlay.querySelector('[data-qisutu-cmdb-ticket-results]');
        var form = overlay.querySelector('[data-qisutu-cmdb-ticket-form]');
        var ciID = form ? form.querySelector('[name="CIID"]') : null;
        function hide() { overlay.hidden = true; document.body.classList.remove('qisutu-overlay-open'); }
        document.querySelectorAll('[data-qisutu-cmdb-ticket-open]').forEach(function (button) {
            button.addEventListener('click', function () {
                overlay.hidden = false;
                document.body.classList.add('qisutu-overlay-open');
                input.value = '';
                results.innerHTML = '<p class="qisutu-form-hint">Nach CI-Nummer, Name oder einem als durchsuchbar markierten CI-Feld suchen.</p>';
                window.setTimeout(function () { input.focus(); }, 0);
            });
        });
        overlay.querySelectorAll('[data-qisutu-cmdb-ticket-close]').forEach(function (button) { button.addEventListener('click', hide); });
        overlay.addEventListener('click', function (event) { if (event.target === overlay) { hide(); } });
        input.addEventListener('input', debounce(function () {
            var query = input.value.trim();
            if (!query) { results.innerHTML = ''; return; }
            getJSON(input.getAttribute('data-url') || '', query).then(function (data) {
                results.innerHTML = '';
                if (!(data.items || []).length) { results.innerHTML = '<p class="qisutu-form-hint">Keine Configuration Items gefunden.</p>'; return; }
                data.items.forEach(function (item) {
                    var button = document.createElement('button');
                    button.type = 'button';
                    button.className = 'qisutu-cmdb-customer-result';
                    button.innerHTML = '<strong></strong><span></span>';
                    button.querySelector('strong').textContent = item.label || '';
                    button.querySelector('span').textContent = item.meta || '';
                    button.addEventListener('click', function () { ciID.value = item.id; form.submit(); });
                    results.appendChild(button);
                });
            }).catch(function () { results.innerHTML = '<p class="qisutu-form-error">Die Suche konnte nicht geladen werden.</p>'; });
        }, 220));
    }

    function init() {
        initFieldOptions();
        initCustomerSelector();
        initAutocomplete();
        initTicketLink();
    }
    if (document.readyState === 'loading') { document.addEventListener('DOMContentLoaded', init); }
    else { init(); }
}());
