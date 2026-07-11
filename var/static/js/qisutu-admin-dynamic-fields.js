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

    function translationSetup(form) {
        var rows = form.querySelector('[data-qisutu-translation-rows]');
        var count = form.querySelector('[data-qisutu-translation-count]');
        var addButton = form.querySelector('[data-qisutu-translation-add]');
        var template = document.getElementById('qisutu-translation-row-template');

        if (!rows || !count || !addButton || !template) {
            return;
        }

        addButton.addEventListener('click', function () {
            var index = parseInt(count.value || '0', 10) + 1;
            var fragment = template.content.cloneNode(true);
            var row = fragment.querySelector('[data-qisutu-translation-row]');
            var language = fragment.querySelector('[data-qisutu-translation-language]');
            var label = fragment.querySelector('[data-qisutu-translation-label]');

            language.name = 'TranslationLanguage_' + index;
            label.name = 'TranslationLabel_' + index;
            count.value = index;

            rows.appendChild(row);
        });

        rows.addEventListener('click', function (event) {
            var button = event.target.closest('[data-qisutu-translation-remove]');
            var row;

            if (!button) {
                return;
            }

            row = button.closest('[data-qisutu-translation-row]');

            if (!row) {
                return;
            }

            if (rows.querySelectorAll('[data-qisutu-translation-row]').length <= 1) {
                return;
            }

            row.remove();
        });
    }

    function optionSetup(form) {
        var fieldType = form.querySelector('[data-qisutu-field-type]');
        var config = form.querySelector('[data-qisutu-selection-config]');
        var rows = form.querySelector('[data-qisutu-option-rows]');
        var count = form.querySelector('[data-qisutu-option-count]');
        var addButton = form.querySelector('[data-qisutu-option-add]');
        var showEmpty = form.querySelector('[data-qisutu-show-empty-value]');
        var template = document.getElementById('qisutu-dynamic-option-row-template');

        if (!fieldType || !config || !rows || !count || !addButton || !showEmpty || !template) {
            return;
        }

        function isSelectionType() {
            return fieldType.value === 'dropdown' || fieldType.value === 'multiselect';
        }

        function syncDefaultValue(row) {
            var key = row.querySelector('[data-qisutu-option-key]');
            var defaultInput = row.querySelector('[data-qisutu-option-default]');

            if (key && defaultInput) {
                defaultInput.value = key.value || '';
            }
        }

        function refreshDefaults() {
            var defaults = Array.prototype.slice.call(rows.querySelectorAll('[data-qisutu-option-default]'));
            var inputType = fieldType.value === 'dropdown' ? 'radio' : 'checkbox';
            var firstChecked = null;

            defaults.forEach(function (input) {
                input.type = inputType;
                input.name = 'DefaultOption';
                input.disabled = !!showEmpty.checked || !isSelectionType();

                if (input.checked && !firstChecked) {
                    firstChecked = input;
                }
                else if (input.checked && inputType === 'radio') {
                    input.checked = false;
                }
            });
        }

        function refresh() {
            var visible = isSelectionType();

            config.classList.toggle('qisutu-hidden', !visible);

            Array.prototype.slice.call(rows.querySelectorAll('[data-qisutu-option-row]')).forEach(function (row) {
                var key = row.querySelector('[data-qisutu-option-key]');
                var value = row.querySelector('input[name^="OptionValue_"]');

                if (key) {
                    key.required = visible;
                    syncDefaultValue(row);
                }
                if (value) {
                    value.required = visible;
                }
            });

            refreshDefaults();
        }

        addButton.addEventListener('click', function () {
            var index = parseInt(count.value || '0', 10) + 1;
            var fragment = template.content.cloneNode(true);
            var row = fragment.querySelector('[data-qisutu-option-row]');
            var key = fragment.querySelector('[data-qisutu-option-key]');
            var value = fragment.querySelector('[data-qisutu-option-value]');
            var sortOrder = fragment.querySelector('[data-qisutu-option-sort-order]');
            var defaultInput = fragment.querySelector('[data-qisutu-option-default]');

            key.name = 'OptionKey_' + index;
            value.name = 'OptionValue_' + index;
            sortOrder.name = 'OptionSortOrder_' + index;
            sortOrder.value = String(index * 100);
            defaultInput.name = 'DefaultOption';
            defaultInput.value = '';
            count.value = index;

            rows.appendChild(row);
            refresh();
            key.focus();
        });

        rows.addEventListener('input', function (event) {
            var row = event.target.closest('[data-qisutu-option-row]');

            if (row && event.target.matches('[data-qisutu-option-key]')) {
                syncDefaultValue(row);
            }
        });

        rows.addEventListener('click', function (event) {
            var button = event.target.closest('[data-qisutu-option-remove]');
            var row;

            if (!button) {
                return;
            }

            row = button.closest('[data-qisutu-option-row]');
            if (row) {
                row.remove();
            }
        });

        showEmpty.addEventListener('change', function () {
            if (showEmpty.checked) {
                Array.prototype.slice.call(rows.querySelectorAll('[data-qisutu-option-default]')).forEach(function (input) {
                    input.checked = false;
                });
            }
            refreshDefaults();
        });

        fieldType.addEventListener('change', refresh);
        form.addEventListener('submit', function () {
            Array.prototype.slice.call(rows.querySelectorAll('[data-qisutu-option-row]')).forEach(syncDefaultValue);
        });

        refresh();
    }

    document.addEventListener('DOMContentLoaded', function () {
        var forms = document.querySelectorAll('form');

        forms.forEach(function (form) {
            translationSetup(form);
            optionSetup(form);
        });
    });
}());
