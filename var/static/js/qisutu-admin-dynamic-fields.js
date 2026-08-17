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

    function optionDescriptors(form) {
        var rows = form.querySelector('[data-qisutu-option-rows]');
        var descriptors = [];

        if (!rows) {
            return descriptors;
        }

        Array.prototype.slice.call(rows.querySelectorAll('[data-qisutu-option-row]')).forEach(function (row) {
            var keyInput = row.querySelector('[data-qisutu-option-key]');
            var valueInput = row.querySelector('[data-qisutu-option-value]');
            var keyName = keyInput ? keyInput.name || '' : '';
            var match = keyName.match(/^OptionKey_(\d+)$/);
            var key = keyInput ? keyInput.value || '' : '';
            var value = valueInput ? valueInput.value || '' : '';

            if (!match || (!key && !value)) {
                return;
            }

            descriptors.push({
                index: match[1],
                label: value || key
            });
        });

        return descriptors;
    }

    function syncOptionTranslations(form) {
        var fieldType = form.querySelector('[data-qisutu-field-type]');
        var descriptors = optionDescriptors(form);
        var selectionType = fieldType && (fieldType.value === 'dropdown' || fieldType.value === 'multiselect');

        Array.prototype.slice.call(form.querySelectorAll('[data-qisutu-translation-row]')).forEach(function (translationRow) {
            var translationIndex = translationRow.getAttribute('data-qisutu-translation-index') || '';
            var container = translationRow.querySelector('[data-qisutu-option-translation-fields]');
            var rows = container ? container.querySelector('[data-qisutu-option-translation-rows]') : null;
            var existing = {};

            if (!translationIndex || !container || !rows) {
                return;
            }

            Array.prototype.slice.call(rows.querySelectorAll('[data-qisutu-option-translation-row]')).forEach(function (row) {
                var optionIndex = row.getAttribute('data-qisutu-option-index') || '';
                var input = row.querySelector('[data-qisutu-option-translation-value]');

                if (optionIndex && input) {
                    existing[optionIndex] = input.value || '';
                }
            });

            rows.textContent = '';

            descriptors.forEach(function (descriptor) {
                var row = document.createElement('div');
                var label = document.createElement('label');
                var input = document.createElement('input');

                row.className = 'qisutu-dynamic-option-translation-row';
                row.setAttribute('data-qisutu-option-translation-row', '');
                row.setAttribute('data-qisutu-option-index', descriptor.index);

                label.textContent = descriptor.label;
                label.setAttribute('data-qisutu-option-translation-label', '');

                input.type = 'text';
                input.name = 'OptionTranslation_' + translationIndex + '_' + descriptor.index;
                input.maxLength = 255;
                input.value = existing[descriptor.index] || '';
                input.setAttribute('data-qisutu-option-translation-value', '');

                row.appendChild(label);
                row.appendChild(input);
                rows.appendChild(row);
            });

            container.classList.toggle('qisutu-hidden', !selectionType || !descriptors.length);
        });
    }

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

            row.setAttribute('data-qisutu-translation-index', String(index));
            language.name = 'TranslationLanguage_' + index;
            label.name = 'TranslationLabel_' + index;
            count.value = index;

            rows.appendChild(row);
            syncOptionTranslations(form);
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

        syncOptionTranslations(form);
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
            syncOptionTranslations(form);
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
            if (row && (event.target.matches('[data-qisutu-option-key]') || event.target.matches('[data-qisutu-option-value]'))) {
                syncOptionTranslations(form);
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
                syncOptionTranslations(form);
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
            syncOptionTranslations(form);
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
