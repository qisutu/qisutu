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

    document.addEventListener('change', function (event) {
        var field = event.target;
        if (field && field.hasAttribute('data-qisutu-auto-submit') && field.form) {
            HTMLFormElement.prototype.submit.call(field.form);
        }
    });

    document.addEventListener('click', function (event) {
        var button = event.target.closest('[data-qisutu-history-back]');
        if (button) {
            event.preventDefault();
            window.history.back();
        }
    });

    document.addEventListener('submit', function (event) {
        var form = event.target;
        if (form && form.hasAttribute('data-qisutu-submit-confirm') &&
                !window.confirm(form.getAttribute('data-qisutu-submit-confirm'))) {
            event.preventDefault();
        }
    });
}());
