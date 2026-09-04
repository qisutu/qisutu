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

    document.querySelectorAll('[data-report-delete]').forEach(function (form) {
        form.addEventListener('submit', function (event) {
            var root = document.querySelector('[data-report-delete-confirm]');
            if (!window.confirm(root && root.dataset.reportDeleteConfirm ? root.dataset.reportDeleteConfirm : 'Delete report?')) {
                event.preventDefault();
            }
        });
    });

    var form = document.querySelector('[data-qisutu-report-designer]');
    if (!form) { return; }

    function parseJSON(selector, fallback) {
        try { return JSON.parse(document.querySelector(selector).textContent || ''); }
        catch (error) { return fallback; }
    }

    var catalog = parseJSON('[data-report-catalog]', { sources: [], operators: [], chart_types: [], sorts: [] });
    var state = parseJSON('[data-report-configuration]', {});
    var sourceSelect = form.querySelector('[data-report-source]');
    var sourceDescription = form.querySelector('[data-report-source-description]');
    var filterLogic = form.querySelector('[data-report-filter-logic]');
    var filterList = form.querySelector('[data-report-filter-list]');
    var filterEmpty = form.querySelector('[data-report-filter-empty]');
    var groupSelect = form.querySelector('[data-report-group]');
    var chartSelect = form.querySelector('[data-report-chart]');
    var sortSelect = form.querySelector('[data-report-sort]');
    var limitInput = form.querySelector('[data-report-limit]');
    var metricsWrap = form.querySelector('[data-report-metrics]');
    var columnsWrap = form.querySelector('[data-report-columns]');
    var configInput = form.querySelector('[data-report-configuration-input]');
    var visibilitySelect = form.querySelector('[data-report-visibility]');
    var sharingRoot = form.querySelector('[data-report-sharing]');
    var sharingToggle = form.querySelector('[data-report-sharing-toggle]');
    var sharingSummary = form.querySelector('[data-report-sharing-summary]');
    var sharingMenu = form.querySelector('[data-report-sharing-menu]');
    var sharingPrivate = form.querySelector('[data-report-sharing-private]');
    var groupValueSelect = form.querySelector('[data-report-group-values]');
    var sharingGroupOptions = form.querySelectorAll('[data-report-group-option]');
    var previewButton = form.querySelector('[data-report-preview]');
    var loading = form.querySelector('[data-report-loading]');
    var previewContent = form.querySelector('[data-report-preview-content]');
    var previewError = form.querySelector('[data-report-preview-error]');
    var scheduleRoot = form.querySelector('[data-report-schedule]');
    var scheduleActive = form.querySelector('[data-report-schedule-active]');
    var scheduleFrequency = form.querySelector('[data-report-schedule-frequency]');
    var scheduleWeekday = form.querySelector('[data-report-schedule-weekday]');
    var scheduleMonthday = form.querySelector('[data-report-schedule-monthday]');
    var schedulePeriod = form.querySelector('[data-report-schedule-period]');
    var schedulePeriodField = form.querySelector('[data-report-schedule-period-field]');
    var schedulePeriodFieldSelect = form.querySelector('[data-report-schedule-period-field-select]');
    var scheduleRolling = form.querySelector('[data-report-schedule-rolling]');
    var currentChart = null;
    var modal = document.querySelector('[data-report-option-modal]');
    var modalSearch = modal.querySelector('[data-report-option-search]');
    var modalResults = modal.querySelector('[data-report-option-results]');
    var modalTitle = modal.querySelector('[data-report-option-title]');
    var activeFilterIndex = -1;
    var searchTimer = null;

    function byKey(items, key) { return (items || []).find(function (item) { return item.key === key; }); }
    function source() { return byKey(catalog.sources, state.source) || catalog.sources[0] || { fields: [], groups: [], metrics: [], default_columns: [] }; }
    function field(key) { return byKey(source().fields, key); }
    function operator(key) { return byKey(catalog.operators, key); }
    function option(select, value, label) { var item = document.createElement('option'); item.value = value; item.textContent = label; select.appendChild(item); return item; }
    function escapeText(value) { return value === undefined || value === null ? '' : String(value); }

    function defaultsForSource(item) {
        return {
            source: item.key,
            filter_logic: 'all',
            filters: [],
            group_by: item.default_group,
            metrics: [item.default_metric],
            chart_type: 'bar',
            sort: 'label_asc',
            limit: 25,
            columns: (item.default_columns || []).slice()
        };
    }

    function normalizeState() {
        var item = source();
        if (!state.source || !byKey(catalog.sources, state.source)) { state = defaultsForSource(item); }
        state.filters = Array.isArray(state.filters) ? state.filters : [];
        state.metrics = Array.isArray(state.metrics) && state.metrics.length ? state.metrics.slice(0, 3) : [item.default_metric];
        state.columns = Array.isArray(state.columns) && state.columns.length ? state.columns.slice(0, 12) : (item.default_columns || []).slice();
        state.filter_logic = state.filter_logic === 'any' ? 'any' : 'all';
        state.group_by = byKey(item.groups, state.group_by) ? state.group_by : item.default_group;
        state.chart_type = byKey(catalog.chart_types, state.chart_type) ? state.chart_type : 'bar';
        state.sort = byKey(catalog.sorts, state.sort) ? state.sort : 'label_asc';
        state.limit = Math.max(5, Math.min(100, Number(state.limit) || 25));
    }

    function renderSource() {
        sourceSelect.textContent = '';
        catalog.sources.forEach(function (item) { option(sourceSelect, item.key, item.label).selected = item.key === state.source; });
        sourceDescription.textContent = source().description || '';
    }

    function renderSchedule() {
        if (!scheduleRoot) { return; }
        scheduleRoot.classList.toggle('is-inactive', !scheduleActive.checked);
        scheduleWeekday.classList.toggle('qisutu-hidden', scheduleFrequency.value !== 'weekly');
        scheduleMonthday.classList.toggle('qisutu-hidden', scheduleFrequency.value !== 'monthly');
        schedulePeriodField.classList.toggle('qisutu-hidden', schedulePeriod.value === 'fixed');
        scheduleRolling.classList.toggle('qisutu-hidden', schedulePeriod.value !== 'rolling_days');

        var selected = schedulePeriodFieldSelect.value || schedulePeriodFieldSelect.dataset.selected || '';
        var dateFields = source().fields.filter(function (item) { return item.type === 'date'; });
        schedulePeriodFieldSelect.textContent = '';
        dateFields.forEach(function (item) {
            option(schedulePeriodFieldSelect, item.key, item.label).selected = item.key === selected;
        });
        if (!schedulePeriodFieldSelect.value && dateFields.length) { schedulePeriodFieldSelect.value = dateFields[0].key; }
        schedulePeriodFieldSelect.dataset.selected = schedulePeriodFieldSelect.value;
    }

    function renderAnalysis() {
        var item = source();
        groupSelect.textContent = '';
        item.groups.forEach(function (entry) { option(groupSelect, entry.key, entry.label).selected = entry.key === state.group_by; });
        chartSelect.textContent = '';
        catalog.chart_types.forEach(function (entry) { option(chartSelect, entry.key, entry.label).selected = entry.key === state.chart_type; });
        sortSelect.textContent = '';
        catalog.sorts.forEach(function (entry) { option(sortSelect, entry.key, entry.label).selected = entry.key === state.sort; });
        limitInput.value = state.limit;

        metricsWrap.textContent = '';
        item.metrics.forEach(function (entry) {
            var label = document.createElement('label'); label.className = 'qisutu-form-checkbox';
            var input = document.createElement('input'); input.type = 'checkbox'; input.value = entry.key; input.checked = state.metrics.indexOf(entry.key) !== -1;
            input.addEventListener('change', function () {
                var selected = Array.prototype.filter.call(metricsWrap.querySelectorAll('input:checked'), function () { return true; });
                if (selected.length > 3) { input.checked = false; window.alert(form.dataset.metricLimit); }
                state.metrics = Array.prototype.map.call(metricsWrap.querySelectorAll('input:checked'), function (node) { return node.value; });
                if (!state.metrics.length) { input.checked = true; state.metrics = [input.value]; }
                sync();
            });
            var span = document.createElement('span'); span.textContent = entry.label;
            label.appendChild(input); label.appendChild(span); metricsWrap.appendChild(label);
        });

        columnsWrap.textContent = '';
        item.fields.forEach(function (entry) {
            var label = document.createElement('label'); label.className = 'qisutu-form-checkbox';
            var input = document.createElement('input'); input.type = 'checkbox'; input.value = entry.key; input.checked = state.columns.indexOf(entry.key) !== -1;
            input.addEventListener('change', function () {
                var checked = columnsWrap.querySelectorAll('input:checked');
                if (checked.length > 12) { input.checked = false; window.alert(form.dataset.columnLimit); }
                state.columns = Array.prototype.map.call(columnsWrap.querySelectorAll('input:checked'), function (node) { return node.value; });
                if (!state.columns.length) { input.checked = true; state.columns = [input.value]; }
                sync();
            });
            var span = document.createElement('span'); span.textContent = entry.label;
            label.appendChild(input); label.appendChild(span); columnsWrap.appendChild(label);
        });
    }

    function setFilterValues(index, values, labels) {
        state.filters[index].values = values.map(String);
        state.filters[index].value_labels = labels || values.map(String);
        sync();
    }

    function valueEditor(entry, index, filterItem) {
        var wrap = document.createElement('div'); wrap.className = 'qisutu-report-filter-value';
        if (filterItem.operator === 'empty' || filterItem.operator === 'not_empty') { wrap.textContent = '—'; return wrap; }
        var multiple = filterItem.operator === 'in' || filterItem.operator === 'not_in';
        if (entry.option_mode === 'search') {
            var button = document.createElement('button'); button.type = 'button'; button.className = 'qisutu-button qisutu-button-secondary qisutu-button-small';
            button.textContent = (filterItem.value_labels || []).length ? filterItem.value_labels.join(', ') : form.dataset.selectValues;
            button.addEventListener('click', function () { activeFilterIndex = index; openOptionModal(entry, multiple); });
            wrap.appendChild(button); return wrap;
        }
        if (entry.option_mode === 'local') {
            var select = document.createElement('select'); select.multiple = multiple; if (multiple) { select.size = Math.min(4, (entry.options || []).length); } else { option(select, '', '—'); }
            (entry.options || []).forEach(function (item) { var node = option(select, item.value, item.label); node.selected = (filterItem.values || []).map(String).indexOf(String(item.value)) !== -1; });
            select.addEventListener('change', function () { var selected = Array.prototype.filter.call(select.options, function (node) { return node.selected; }); if (!multiple && selected.length > 1) { selected = [selected[0]]; } setFilterValues(index, selected.map(function (node) { return node.value; }), selected.map(function (node) { return node.textContent; })); });
            wrap.appendChild(select); return wrap;
        }
        if (entry.type === 'date' && filterItem.operator === 'between') {
            [0, 1].forEach(function (position) { var input = document.createElement('input'); input.type = 'date'; input.value = (filterItem.values || [])[position] || ''; input.addEventListener('change', function () { var values = (state.filters[index].values || []).slice(); values[position] = input.value; setFilterValues(index, values, values); }); wrap.appendChild(input); });
            return wrap;
        }
        var input = document.createElement('input'); input.type = entry.type === 'date' ? 'date' : entry.type === 'number' ? 'number' : 'text'; input.value = (filterItem.values || []).join(multiple ? ', ' : ''); input.placeholder = multiple ? form.dataset.filterValues : form.dataset.filterValue;
        input.addEventListener('input', function () { var values = multiple ? input.value.split(',').map(function (value) { return value.trim(); }).filter(Boolean) : [input.value]; setFilterValues(index, values, values); });
        wrap.appendChild(input); return wrap;
    }

    function renderFilters() {
        filterLogic.value = state.filter_logic;
        filterList.textContent = '';
        filterEmpty.classList.toggle('qisutu-hidden', state.filters.length > 0);
        state.filters.forEach(function (filterItem, index) {
            var entry = field(filterItem.field) || source().fields[0];
            if (!entry) { return; }
            var row = document.createElement('div'); row.className = 'qisutu-report-filter-row';
            var fieldSelect = document.createElement('select'); fieldSelect.className = 'qisutu-report-filter-field';
            source().fields.forEach(function (item) { option(fieldSelect, item.key, item.label).selected = item.key === entry.key; });
            fieldSelect.addEventListener('change', function () { var changed = fieldSelect.value; var changedField = field(changed); state.filters[index] = { field: changed, operator: (changedField.operators || ['eq'])[0], values: [], value_labels: [] }; renderFilters(); sync(); });
            var operatorSelect = document.createElement('select'); operatorSelect.className = 'qisutu-report-filter-operator';
            (entry.operators || []).forEach(function (key) { var item = operator(key); option(operatorSelect, key, item ? item.label : key).selected = key === filterItem.operator; });
            operatorSelect.addEventListener('change', function () { state.filters[index].operator = operatorSelect.value; state.filters[index].values = []; state.filters[index].value_labels = []; renderFilters(); sync(); });
            var remove = document.createElement('button'); remove.type = 'button'; remove.className = 'qisutu-button qisutu-button-danger qisutu-button-small'; remove.textContent = '×'; remove.setAttribute('aria-label', form.dataset.remove); remove.addEventListener('click', function () { state.filters.splice(index, 1); renderFilters(); sync(); });
            row.appendChild(fieldSelect); row.appendChild(operatorSelect); row.appendChild(valueEditor(entry, index, filterItem)); row.appendChild(remove); filterList.appendChild(row);
        });
    }

    function sync() {
        state.filter_logic = filterLogic.value;
        state.group_by = groupSelect.value || state.group_by;
        state.chart_type = chartSelect.value || state.chart_type;
        state.sort = sortSelect.value || state.sort;
        state.limit = Math.max(5, Math.min(100, Number(limitInput.value) || 25));
        configInput.value = JSON.stringify(state);
    }

    function renderAll() { normalizeState(); renderSource(); renderFilters(); renderAnalysis(); renderSchedule(); sharingRender(); sync(); }

    sourceSelect.addEventListener('change', function () { var item = byKey(catalog.sources, sourceSelect.value); if (item) { state = defaultsForSource(item); renderAll(); } });
    filterLogic.addEventListener('change', sync); groupSelect.addEventListener('change', function () { state.group_by = groupSelect.value; sync(); });
    chartSelect.addEventListener('change', function () { state.chart_type = chartSelect.value; sync(); }); sortSelect.addEventListener('change', function () { state.sort = sortSelect.value; sync(); }); limitInput.addEventListener('input', sync);
    form.querySelector('[data-report-add-filter]').addEventListener('click', function () { var first = source().fields.find(function (item) { return item.type === 'date'; }) || source().fields[0]; if (!first) { return; } state.filters.push({ field: first.key, operator: first.type === 'date' ? 'between' : (first.operators || ['eq'])[0], values: [], value_labels: [] }); renderFilters(); sync(); });
    form.addEventListener('submit', sync);

    if (scheduleRoot) {
        scheduleActive.addEventListener('change', renderSchedule);
        scheduleFrequency.addEventListener('change', renderSchedule);
        schedulePeriod.addEventListener('change', renderSchedule);
        schedulePeriodFieldSelect.addEventListener('change', function () {
            schedulePeriodFieldSelect.dataset.selected = schedulePeriodFieldSelect.value;
        });
    }

    function sharingMenuSet(open) {
        sharingMenu.classList.toggle('qisutu-hidden', !open);
        sharingToggle.setAttribute('aria-expanded', open ? 'true' : 'false');
    }

    function sharingRender() {
        var selectedNames = [];
        var selectedByID = {};
        Array.prototype.forEach.call(groupValueSelect.options, function (option) {
            if (option.selected) { selectedByID[String(option.value)] = true; }
        });
        sharingGroupOptions.forEach(function (button) {
            var selected = !!selectedByID[String(button.dataset.groupId)];
            button.setAttribute('aria-selected', selected ? 'true' : 'false');
            if (selected) {
                var name = button.querySelector('.qisutu-report-sharing-group-name');
                if (name) { selectedNames.push(name.textContent.trim()); }
            }
        });
        var shared = visibilitySelect.value === 'shared';
        sharingPrivate.classList.toggle('is-selected', !shared);
        sharingPrivate.setAttribute('aria-selected', shared ? 'false' : 'true');
        var summary = shared
            ? (selectedNames.length ? selectedNames.join(', ') : sharingToggle.dataset.sharedLabel)
            : sharingToggle.dataset.privateLabel;
        sharingSummary.textContent = summary;
        sharingToggle.title = summary;
    }

    function sharingSetPrivate() {
        visibilitySelect.value = 'private';
        Array.prototype.forEach.call(groupValueSelect.options, function (option) { option.selected = false; });
        sharingRender();
        sharingMenuSet(false);
    }

    function sharingGroupToggle(button) {
        var groupID = String(button.dataset.groupId);
        Array.prototype.forEach.call(groupValueSelect.options, function (option) {
            if (String(option.value) === groupID) { option.selected = !option.selected; }
        });
        visibilitySelect.value = 'shared';
        sharingRender();
    }

    sharingToggle.addEventListener('click', function () {
        sharingMenuSet(sharingMenu.classList.contains('qisutu-hidden'));
    });
    sharingPrivate.addEventListener('click', sharingSetPrivate);
    sharingGroupOptions.forEach(function (button) {
        button.addEventListener('click', function () { sharingGroupToggle(button); });
    });
    document.addEventListener('click', function (event) {
        if (!sharingRoot.contains(event.target)) { sharingMenuSet(false); }
    });
    document.addEventListener('keydown', function (event) {
        if (event.key === 'Escape' && !sharingMenu.classList.contains('qisutu-hidden')) {
            sharingMenuSet(false);
            sharingToggle.focus();
        }
    });

    function openOptionModal(entry, multiple) {
        modal.dataset.multiple = multiple ? '1' : '0'; modal.dataset.field = entry.key; modalTitle.textContent = entry.label; modalSearch.value = '';
        modal.classList.remove('qisutu-hidden'); modal.setAttribute('aria-hidden', 'false'); document.body.classList.add('qisutu-modal-open'); loadOptions(); window.setTimeout(function () { modalSearch.focus(); }, 30);
    }
    function closeOptionModal() { modal.classList.add('qisutu-hidden'); modal.setAttribute('aria-hidden', 'true'); document.body.classList.remove('qisutu-modal-open'); activeFilterIndex = -1; }
    modal.querySelectorAll('[data-report-option-close]').forEach(function (node) { node.addEventListener('click', closeOptionModal); });
    modalSearch.addEventListener('input', function () { window.clearTimeout(searchTimer); searchTimer = window.setTimeout(loadOptions, 250); });

    function loadOptions() {
        if (activeFilterIndex < 0) { return; }
        var filterItem = state.filters[activeFilterIndex]; var params = new URLSearchParams(); params.set('Source', state.source); params.set('Field', filterItem.field); params.set('Search', modalSearch.value || '');
        modalResults.textContent = '…';
        window.fetch(form.dataset.optionSearchUrl + '&' + params.toString(), { credentials: 'same-origin', headers: { 'X-Requested-With': 'XMLHttpRequest' } }).then(function (response) { return response.json(); }).then(function (data) {
            modalResults.textContent = ''; var items = Array.isArray(data.items) ? data.items : []; if (!items.length) { modalResults.textContent = form.dataset.noMatches; return; }
            var selected = (filterItem.values || []).map(String);
            items.forEach(function (item) { var label = document.createElement('label'); label.className = 'qisutu-report-option-item'; var input = document.createElement('input'); input.type = modal.dataset.multiple === '1' ? 'checkbox' : 'radio'; input.name = 'report-option'; input.value = item.id; input.dataset.label = item.label; input.checked = selected.indexOf(String(item.id)) !== -1; label.appendChild(input); var span = document.createElement('span'); span.textContent = item.label; label.appendChild(span); modalResults.appendChild(label); });
        }).catch(function () { modalResults.textContent = form.dataset.previewError; });
    }
    modal.querySelector('[data-report-option-apply]').addEventListener('click', function () {
        if (activeFilterIndex < 0) { return; } var checked = modalResults.querySelectorAll('input:checked'); var values = Array.prototype.map.call(checked, function (node) { return node.value; }); var labels = Array.prototype.map.call(checked, function (node) { return node.dataset.label; }); setFilterValues(activeFilterIndex, values, labels); closeOptionModal(); renderFilters();
    });

    function formatValue(value, format) {
        var number = Number(value) || 0;
        if (format === 'percent') { return number.toLocaleString(undefined, { maximumFractionDigits: 2 }) + ' %'; }
        if (format === 'minutes') { var minutes = Math.round(number); return Math.floor(minutes / 60) + ' h ' + String(minutes % 60).padStart(2, '0') + ' min'; }
        return number.toLocaleString(undefined, { maximumFractionDigits: 2 });
    }

    function cell(text, tag) { var node = document.createElement(tag || 'td'); node.textContent = escapeText(text); return node; }
    function renderResult(result) {
        previewContent.classList.remove('qisutu-hidden'); previewError.classList.add('qisutu-hidden');
        var summary = form.querySelector('[data-report-summary]'); summary.textContent = '';
        (result.metrics || []).forEach(function (metric, index) { var card = document.createElement('div'); card.className = 'qisutu-dashboard-metric qisutu-dashboard-metric-primary'; var label = document.createElement('span'); label.className = 'qisutu-dashboard-metric-label'; label.textContent = metric.label; var value = document.createElement('strong'); value.className = 'qisutu-dashboard-metric-value'; value.textContent = formatValue((result.summary || [])[index], metric.format); card.appendChild(label); card.appendChild(value); summary.appendChild(card); });

        var analysisHead = form.querySelector('[data-report-analysis-head]'); var analysisBody = form.querySelector('[data-report-analysis-body]'); analysisHead.textContent = ''; analysisBody.textContent = ''; var headRow = document.createElement('tr'); headRow.appendChild(cell(result.group.label, 'th')); (result.metrics || []).forEach(function (metric) { headRow.appendChild(cell(metric.label, 'th')); }); analysisHead.appendChild(headRow);
        (result.rows || []).forEach(function (row) { var tr = document.createElement('tr'); tr.appendChild(cell(row.label)); (row.values || []).forEach(function (value, index) { tr.appendChild(cell(formatValue(value, result.metrics[index].format))); }); analysisBody.appendChild(tr); });

        var detailHead = form.querySelector('[data-report-detail-head]'); var detailBody = form.querySelector('[data-report-detail-body]'); detailHead.textContent = ''; detailBody.textContent = ''; var detailHeadRow = document.createElement('tr'); (result.details.columns || []).forEach(function (column) { detailHeadRow.appendChild(cell(column.label, 'th')); }); detailHead.appendChild(detailHeadRow); (result.details.rows || []).forEach(function (row) { var tr = document.createElement('tr'); row.forEach(function (value) { tr.appendChild(cell(value)); }); detailBody.appendChild(tr); });
        var limited = form.querySelector('[data-report-limited]'); limited.textContent = form.dataset.detailLimited; limited.classList.toggle('qisutu-hidden', !result.was_limited);
        form.querySelector('[data-report-duration]').textContent = (Number(result.duration_ms) || 0) + ' ms'; renderChart(result);
    }

    function renderChart(result) {
        var canvas = form.querySelector('[data-report-chart-canvas]'); var wrap = canvas.parentElement; var type = result.configuration.chart_type; if (currentChart) { currentChart.destroy(); currentChart = null; }
        wrap.classList.toggle('qisutu-hidden', type === 'table' || type === 'kpi' || !result.rows.length); if (wrap.classList.contains('qisutu-hidden') || typeof window.Chart !== 'function') { return; }
        var colors = ['#08789f', '#ef5b3a', '#4eae6c']; var chartType = type === 'doughnut' ? 'doughnut' : type === 'line' || type === 'area' ? 'line' : 'bar';
        var datasets = (result.metrics || []).map(function (metric, index) { return { label: metric.label, data: result.rows.map(function (row) { return Number(row.values[index]) || 0; }), backgroundColor: type === 'doughnut' ? result.rows.map(function (_, rowIndex) { return ['#08789f','#ef5b3a','#4eae6c','#f2b134','#8259a3','#28a8a8','#d35d8c','#6f7f91'][rowIndex % 8]; }) : colors[index % colors.length], borderColor: colors[index % colors.length], borderWidth: 2, fill: type === 'area', tension: 0.25 }; });
        currentChart = new window.Chart(canvas, { type: chartType, data: { labels: result.rows.map(function (row) { return row.label; }), datasets: datasets }, options: { responsive: true, maintainAspectRatio: false, animation: false, plugins: { legend: { position: 'bottom' } }, scales: chartType === 'doughnut' ? {} : { x: { stacked: type === 'stacked_bar' }, y: { beginAtZero: true, stacked: type === 'stacked_bar' } } } });
    }

    function preview() {
        sync(); loading.classList.remove('qisutu-hidden'); previewContent.classList.add('qisutu-hidden'); previewError.classList.add('qisutu-hidden'); previewButton.disabled = true;
        var data = new FormData(form); data.append('Step', 'Preview');
        window.fetch('index.pl', { method: 'POST', body: data, credentials: 'same-origin', headers: { 'X-Requested-With': 'XMLHttpRequest' } }).then(function (response) { return response.json(); }).then(function (payload) { if (!payload.success) { throw new Error(payload.error || form.dataset.previewError); } renderResult(payload.result); }).catch(function (error) { previewError.textContent = error.message || form.dataset.previewError; previewError.classList.remove('qisutu-hidden'); }).finally(function () { loading.classList.add('qisutu-hidden'); previewButton.disabled = false; });
    }
    previewButton.addEventListener('click', preview);

    renderAll();
    if (Number(form.querySelector('[name="ReportID"]').value) > 0) { window.setTimeout(preview, 50); }
}());
