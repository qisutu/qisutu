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

    function LegacyCopy(Value) {
        var Input = document.createElement('textarea');
        Input.value = Value;
        Input.setAttribute('readonly', '');
        Input.style.position = 'fixed';
        Input.style.left = '-9999px';
        Input.style.opacity = '0';
        document.body.appendChild(Input);
        Input.select();
        Input.setSelectionRange(0, Input.value.length);

        var Copied = false;
        try {
            Copied = document.execCommand('copy');
        }
        catch (Error) {
            Copied = false;
        }

        document.body.removeChild(Input);
        return Copied ? Promise.resolve() : Promise.reject(new Error('copy failed'));
    }

    function CopyText(Value) {
        if (window.isSecureContext && navigator.clipboard && navigator.clipboard.writeText) {
            return navigator.clipboard.writeText(Value);
        }
        return LegacyCopy(Value);
    }

    document.querySelectorAll('[data-copy-target]').forEach(function (Button) {
        Button.addEventListener('click', function () {
            var Target = document.getElementById(Button.getAttribute('data-copy-target'));
            if (!Target) {
                return;
            }

            CopyText(Target.textContent || '').then(function () {
                Button.textContent = Button.getAttribute('data-copied-label') || '';
                window.setTimeout(function () {
                    Button.textContent = Button.getAttribute('data-copy-label') || '';
                }, 1800);
            }).catch(function () {
                var Selection = window.getSelection();
                var Range = document.createRange();
                Range.selectNodeContents(Target);
                Selection.removeAllRanges();
                Selection.addRange(Range);
            });
        });
    });
}());
