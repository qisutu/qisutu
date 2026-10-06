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
    const childrenBySelector = {};
    return {
        hidden: false, value: '', textContent: '', children: [],
        classList: { add() {}, remove() {}, toggle() {} },
        getAttribute: name => attributes[name] || '',
        setAttribute(name, value) { attributes[name] = value; },
        querySelector(selector) { return childrenBySelector[selector] ||= element(); },
        appendChild(child) { this.children.push(child); },
        addEventListener(name, handler) { (listeners[name] ||= []).push(handler); },
        emit(name, event = {isTrusted: true}) { for (const handler of listeners[name] || []) handler(event); }
    };
}

function fixture() {
    let now = 1000000;
    let online = true;
    let failActivity = false;
    const requests = [];
    const timers = [];
    const root = element({
        'data-csrf-token': 'test-csrf',
        'data-activity-url': 'activity', 'data-state-url': 'state', 'data-unread-url': 'unread'
    });
    const drawer = root.querySelector('[data-qisutu-internal-chat-drawer]');
    drawer.hidden = true;
    const launcher = element();
    const document = element();
    document.visibilityState = 'visible';
    document.body = element();
    document.getElementById = id => id === 'QisutuInternalChat' ? root : null;
    document.querySelector = selector => selector === '[data-qisutu-internal-chat-open]' ? launcher : null;
    document.createElement = () => element();
    const window = element();
    window.setInterval = (callback, delay) => { const timer = {callback, delay}; timers.push(timer); return timer; };
    window.clearInterval = () => {};
    window.fetch = async (url, options) => {
        requests.push({url, options});
        if (url === 'activity' && failActivity) throw new Error('network offline');
        return {ok: true, json: async () => ({success: 1, unread_count: 0, agents: [
            {id: 2, name: 'Test Agent', initials: 'TA', is_online: online ? 1 : 0}
        ]})};
    };
    vm.runInNewContext(fs.readFileSync(path.join(__dirname, '../var/static/js/qisutu-internal-chat.js'), 'utf8'), {
        document, window, URLSearchParams, Date: {now: () => now}
    });
    document.emit('DOMContentLoaded');
    return {
        root, drawer, document, window, requests, timers,
        advance(ms) { now += ms; },
        tick() { for (const timer of [...timers]) timer.callback(); },
        setOnline(value) { online = value; },
        setFailActivity(value) { failActivity = value; },
        count(url) { return requests.filter(item => item.url === url).length; }
    };
}
const settle = () => new Promise(resolve => setImmediate(resolve));

(async () => {
    const f = fixture();
    await settle();
    assert.equal(f.count('activity'), 1, 'visible initial page reports activity');
    const request = f.requests.find(item => item.url === 'activity');
    assert.equal(request.options.method, 'POST');
    assert.equal(new URLSearchParams(request.options.body).get('CSRFToken'), 'test-csrf');
    assert.equal(f.count('state'), 1);

    f.document.visibilityState = 'hidden';
    for (let i = 0; i < 360; i++) { f.advance(30000); f.tick(); await settle(); }
    assert.equal(f.count('activity'), 1, 'three hours of hidden-tab polling never report activity');
    assert.equal(f.count('unread'), 360, 'unread messages remain available');
    f.document.emit('pointermove');
    f.window.emit('focus');
    await settle();
    assert.equal(f.count('activity'), 1, 'hidden-tab events cannot refresh online status');

    f.document.visibilityState = 'visible';
    f.document.emit('visibilitychange');
    await settle();
    assert.equal(f.count('activity'), 2, 'returning to the tab reports activity');
    for (let i = 0; i < 100; i++) f.document.emit('pointermove');
    await settle();
    assert.equal(f.count('activity'), 2, 'mouse events are throttled');
    f.advance(30001);
    f.document.emit('input');
    await settle();
    assert.equal(f.count('activity'), 3, 'typing in the ticket editor reports activity');
    f.advance(30001);
    f.document.emit('input', {isTrusted: false});
    await settle();
    assert.equal(f.count('activity'), 3, 'synthetic events do not report user activity');

    f.drawer.hidden = false;
    const unreadBefore = f.count('unread');
    f.setOnline(false);
    f.tick();
    await settle();
    assert.equal(f.count('state'), 2, 'open chat refreshes its agent list on the next poll');
    assert.equal(f.count('unread'), unreadBefore, 'state response supplies the unread count without a duplicate request');
    assert.equal(f.root.querySelector('[data-qisutu-internal-chat-agent-list]').children.at(-1).children[1].children[2].textContent, 'Offline');
    assert.ok(f.timers.every(timer => timer.delay <= 30000), 'online list refreshes within 30 seconds');
    for (let i = 0; i < 30; i++) { f.advance(30000); f.tick(); await settle(); }
    assert.equal(f.count('activity'), 3, 'visible but unattended open chat also reports no activity');

    f.setFailActivity(true);
    f.document.emit('keydown');
    await settle();
    f.advance(30001);
    f.setFailActivity(false);
    f.document.emit('keydown');
    await settle();
    assert.equal(f.count('activity'), 5, 'activity resumes after a failed request');
    console.log('Internal chat activity and online refresh regression tests passed.');
})().catch(error => { console.error(error); process.exitCode = 1; });
