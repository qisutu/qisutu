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
const handlers = {};

// Run the production submit listener with editor and DOM doubles.
vm.runInNewContext(fs.readFileSync(path.join(__dirname, '../var/static/js/qisutu-richtext.js'), 'utf8'), {
    window: {},
    document: {
        readyState: 'complete',
        documentElement: { getAttribute: () => 'en' },
        querySelectorAll: () => [],
        addEventListener: (name, handler) => { handlers[name] = handler; }
    }
});

function submit(optional, body) {
    const result = { prevented: false, focused: false, updated: false };
    const textarea = {
        getAttribute: name => name === 'data-qisutu-richtext-optional' ? optional : null,
        qisutuEditor: {
            updateSourceElement: () => { result.updated = true; },
            getData: () => body,
            editing: { view: { focus: () => { result.focused = true; } } }
        }
    };
    handlers.submit({
        target: { querySelectorAll: () => [textarea] },
        preventDefault: () => { result.prevented = true; }
    });
    return result;
}

for (const body of ['', '<p><br></p>', '<p>&nbsp;</p>']) {
    assert.deepEqual(submit('1', body), { prevented: false, focused: false, updated: true },
        'a title change can be submitted with an empty optional comment');
    assert.deepEqual(submit(null, body), { prevented: true, focused: true, updated: true },
        'existing mandatory editors still reject empty content');
}
assert.deepEqual(submit('1', '<p>Grund für die Änderung.</p>'), { prevented: false, focused: false, updated: true },
    'an optional comment is synchronized before submission');
assert.deepEqual(submit(null, '<p>Pflichttext.</p>'), { prevented: false, focused: false, updated: true },
    'existing non-empty mandatory editors still submit');
console.log('PASS: 8 rich-text submission checks');
