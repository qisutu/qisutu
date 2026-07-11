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

    document.addEventListener('DOMContentLoaded', function () {
        var forms = document.querySelectorAll('form');

        forms.forEach(translationSetup);
    });
}());
