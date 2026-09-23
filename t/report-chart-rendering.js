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

const assert = require('node:assert/strict');
const fs = require('node:fs');
const vm = require('node:vm');
const path = require('node:path');
const root = path.resolve(__dirname, '..');
const source = fs.readFileSync(path.join(root, 'var/static/js/qisutu-reports.js'), 'utf8');
function functionSource(name, next) {
    const start = source.indexOf('    function ' + name + '(');
    const end = source.indexOf('    function ' + next + '(', start);
    assert.ok(start >= 0 && end > start, 'production renderer is present');
    return source.slice(start, end);
}
const classes = new Set();
const wrap = {classList: {
    add: name => classes.add(name),
    contains: name => classes.has(name),
    toggle: (name, value) => value ? classes.add(name) : classes.delete(name)
}};
let last;
const canvas = {parentElement: wrap};
const context = vm.createContext({
    form: {querySelector: () => canvas}, currentChart: null,
    window: {Chart: function(canvas, config) {
        last = {config, destroyed: false, destroy() {this.destroyed = true;}};
        return last;
    }}
});
vm.runInContext(functionSource('formatValue', 'cell') + functionSource('renderChart', 'preview'), context);
const result = {
    configuration: {chart_type: 'pie'},
    rows: [{label: '2026-08', values: [49, 12]}],
    metrics: [{label: 'Tickets'}, {label: 'Geschlossene Tickets'}],
    pie: {labels: ['Geschlossene Tickets', 'Übrige'], values: [12, 37], colors: ['#08789f', '#ef5b3a'], format: 'number'}
};
context.renderChart(result);
assert.equal(last.config.type, 'pie');
assert.equal(last.config.options.cutout, 0);
assert.equal(last.config.data.datasets.length, 1, 'parts belong to one pie, not concentric datasets');
assert.deepEqual(last.config.data.labels, result.pie.labels);
assert.deepEqual(last.config.data.datasets[0].data, [12, 37]);
assert.deepEqual(last.config.data.datasets[0].backgroundColor, ['#08789f', '#ef5b3a']);
assert.equal(last.config.data.datasets[0].borderColor, '#ffffff');
assert.equal(last.config.options.scales, undefined, 'pie has no cartesian axes');
const label = last.config.options.plugins.tooltip.callbacks.label({label: 'Geschlossene Tickets', raw: 12});
assert.ok(label.includes('12') && label.includes((12 * 100 / 49).toLocaleString(undefined, {maximumFractionDigits: 1}) + ' %'));
const previous = last;
result.configuration.chart_type = 'doughnut';
context.renderChart(result);
assert.equal(previous.destroyed, true, 'preview replaces its prior chart');
assert.equal(last.config.type, 'pie', 'legacy reports also use a pie');
for (const type of ['bar', 'stacked_bar', 'line', 'area']) {
    result.configuration.chart_type = type;
    context.renderChart(result);
    assert.equal(last.config.type, type === 'line' || type === 'area' ? 'line' : 'bar');
    assert.equal(last.config.data.datasets.length, 2, 'non-pie charts retain all selected metrics');
}
for (const type of ['table', 'kpi']) {
    result.configuration.chart_type = type;
    context.renderChart(result);
    assert.ok(classes.has('qisutu-hidden'));
}
result.configuration.chart_type = 'pie';
result.pie = {labels: [], values: [], colors: []};
context.renderChart(result);
assert.ok(classes.has('qisutu-hidden'), 'empty pie data does not invent slices');
const item = {key: 'tickets', groups: [{key: 'none'}], default_group: 'none', default_metric: 'ticket_count'};
Object.assign(context, {
    state: {source: 'tickets', chart_type: 'doughnut'},
    source: () => item,
    byKey: (entries, key) => entries.find(entry => entry.key === key),
    catalog: {sources: [item], chart_types: [{key: 'pie'}, {key: 'bar'}], sorts: []}
});
vm.runInContext(functionSource('normalizeState', 'renderSource'), context);
context.normalizeState();
assert.equal(context.state.chart_type, 'pie', 'legacy saved selection survives frontend normalization');
console.log('# Production chart renderer: pie, colors, values, tooltips and legacy selection verified');
