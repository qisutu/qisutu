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

'use strict';

const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const vm = require('node:vm');

function element(attributes = {}) {
    const listeners = {};
    return {
        getAttribute: name => attributes[name] || null,
        addEventListener(name, handler) {
            (listeners[name] ||= []).push(handler);
        },
        emit(name, event = {}) {
            for (const handler of listeners[name] || []) handler(event);
        }
    };
}

function fixture(ruleID = '7') {
    const step = { value: ruleID ? 'RuleUpdate' : 'RuleCreate' };
    const form = element();
    form.querySelector = selector => selector === '[data-qisutu-automation-step]' ? step : { value: ruleID };
    const preview = element({ 'data-preview-step': 'RulePreview' });
    preview.closest = () => form;
    const save = element();
    const deleteForm = element({ 'data-qisutu-automation-delete': 'Delete this rule?' });
    const confirmation = { allow: false, messages: [] };
    const document = element();
    document.querySelector = () => null;
    document.querySelectorAll = selector => selector === '[data-qisutu-automation-preview]' ? [preview]
        : selector === '[data-qisutu-automation-delete]' ? [deleteForm] : [];
    vm.runInNewContext(
        fs.readFileSync(path.join(__dirname, '../var/static/js/qisutu-automation.js'), 'utf8'),
        { document, window: { confirm(message) { confirmation.messages.push(message); return confirmation.allow; } } }
    );
    document.emit('DOMContentLoaded');
    return { form, preview, save, step, deleteForm, confirmation };
}

for (const ruleID of ['7', '']) {
    const { form, preview, save, step } = fixture(ruleID);
    const expected = ruleID ? 'RuleUpdate' : 'RuleCreate';
    form.emit('submit', { submitter: save });
    assert.equal(step.value, expected, 'Save must persist the current form');
    preview.emit('click');
    form.emit('submit', { submitter: preview });
    assert.equal(step.value, 'RulePreview', 'Preview must only preview');
    form.emit('submit', { submitter: save });
    assert.equal(step.value, expected, 'Save after Preview must persist');

    // Native validation may cancel submission after the preview button click.
    preview.emit('click');
    // The user fixes the form, changes the queue and clicks Save.
    form.emit('submit', { submitter: save });
    assert.equal(step.value, expected, 'An aborted preview must not turn the next Save into a preview');
    preview.emit('click');
    form.emit('submit', {});
    assert.equal(step.value, expected, 'Submission without a preview submitter must persist');
}

{
    const { deleteForm, confirmation } = fixture();
    let cancelled = false;
    deleteForm.emit('submit', { preventDefault() { cancelled = true; } });
    assert.equal(cancelled, true, 'Cancel must prevent deletion');
    assert.deepEqual(confirmation.messages, ['Delete this rule?']);
    confirmation.allow = true;
    cancelled = false;
    deleteForm.emit('submit', { preventDefault() { cancelled = true; } });
    assert.equal(cancelled, false, 'Confirm must allow deletion');
}

console.log('Automation form submit regression tests passed.');
