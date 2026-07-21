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

    var root = document.querySelector('[data-qisutu-dashboard]');
    if (!root) {
        return;
    }

    var dataElement = document.getElementById('qisutu-dashboard-data');
    var endpoint = root.getAttribute('data-qisutu-dashboard-endpoint') || '';
    var refreshSeconds = parseInt(root.getAttribute('data-qisutu-dashboard-refresh-seconds') || '120', 10);
    var refreshButton = root.querySelector('[data-qisutu-dashboard-refresh]');
    var updatedElement = root.querySelector('[data-qisutu-dashboard-updated]');
    var errorElement = root.querySelector('[data-qisutu-dashboard-error]');
    var filterForm = root.querySelector('[data-qisutu-dashboard-filter]');
    var periodSelect = root.querySelector('[data-qisutu-dashboard-period]');
    var customDates = root.querySelector('[data-qisutu-dashboard-custom-dates]');
    var customDateInputs = root.querySelectorAll('[data-qisutu-dashboard-date-from], [data-qisutu-dashboard-date-to]');
    var charts = {};
    var refreshTimer = 0;
    var refreshing = false;
    var lastRefresh = Date.now();
    var reduceMotion = window.matchMedia && window.matchMedia('(prefers-reduced-motion: reduce)').matches;
    var originalRefreshLabel = refreshButton ? refreshButton.textContent : '';

    function initialData() {
        if (!dataElement) {
            return {};
        }
        try {
            return JSON.parse(dataElement.textContent || '{}');
        }
        catch (error) {
            return {};
        }
    }

    function number(value) {
        var parsed = Number(value);
        return Number.isFinite(parsed) ? parsed : 0;
    }

    function chartAvailable() {
        return typeof window.Chart === 'function';
    }

    function destroyChart(name) {
        if (charts[name]) {
            charts[name].destroy();
            delete charts[name];
        }
    }

    function chartDefaults() {
        return {
            responsive: true,
            maintainAspectRatio: false,
            animation: reduceMotion ? false : { duration: 360 },
            plugins: {
                legend: {
                    labels: {
                        boxWidth: 12,
                        boxHeight: 12,
                        color: '#475569',
                        font: { family: 'inherit', size: 12, weight: '600' }
                    }
                },
                tooltip: {
                    backgroundColor: '#0f2934',
                    titleFont: { family: 'inherit' },
                    bodyFont: { family: 'inherit' },
                    padding: 10
                }
            }
        };
    }

    function renderTrend(data) {
        var canvas = root.querySelector('[data-qisutu-dashboard-chart="trend"]');
        if (!canvas || !chartAvailable()) {
            return;
        }

        destroyChart('trend');
        var defaults = chartDefaults();
        var labels = Array.isArray(data.labels) ? data.labels : [];
        var showPoints = labels.length <= 35;

        charts.trend = new window.Chart(canvas, {
            type: 'line',
            data: {
                labels: labels,
                datasets: [
                    {
                        label: data.createdLabel || '',
                        data: Array.isArray(data.created) ? data.created.map(number) : [],
                        borderColor: '#0284c7',
                        backgroundColor: 'rgba(2, 132, 199, .12)',
                        borderWidth: 2.5,
                        pointRadius: showPoints ? 3 : 0,
                        pointHoverRadius: 5,
                        tension: .28,
                        fill: true
                    },
                    {
                        label: data.closedLabel || '',
                        data: Array.isArray(data.closed) ? data.closed.map(number) : [],
                        borderColor: '#16a34a',
                        backgroundColor: 'rgba(22, 163, 74, .08)',
                        borderWidth: 2.5,
                        pointRadius: showPoints ? 3 : 0,
                        pointHoverRadius: 5,
                        tension: .28,
                        fill: true
                    }
                ]
            },
            options: {
                responsive: defaults.responsive,
                maintainAspectRatio: defaults.maintainAspectRatio,
                animation: defaults.animation,
                interaction: { mode: 'index', intersect: false },
                plugins: defaults.plugins,
                scales: {
                    x: {
                        grid: { display: false },
                        ticks: { color: '#64748b', maxRotation: 0, autoSkip: true, maxTicksLimit: 14 }
                    },
                    y: {
                        beginAtZero: true,
                        grid: { color: 'rgba(148, 163, 184, .22)' },
                        ticks: { color: '#64748b', precision: 0 }
                    }
                }
            }
        });
    }

    function clickableChartOptions(defaults, urls, horizontal) {
        return {
            responsive: defaults.responsive,
            maintainAspectRatio: defaults.maintainAspectRatio,
            animation: defaults.animation,
            indexAxis: horizontal ? 'y' : 'x',
            plugins: {
                legend: { display: false },
                tooltip: defaults.plugins.tooltip
            },
            onHover: function (event, elements) {
                event.native.target.style.cursor = elements.length && urls[elements[0].index] ? 'pointer' : 'default';
            },
            onClick: function (event, elements) {
                if (!elements.length) {
                    return;
                }
                var url = urls[elements[0].index] || '';
                if (url) {
                    window.location.href = url;
                }
            },
            scales: horizontal ? {
                x: {
                    beginAtZero: true,
                    grid: { color: 'rgba(148, 163, 184, .22)' },
                    ticks: { color: '#64748b', precision: 0 }
                },
                y: {
                    grid: { display: false },
                    ticks: { color: '#475569', autoSkip: false }
                }
            } : {
                x: {
                    grid: { display: false },
                    ticks: { color: '#475569', maxRotation: 0, autoSkip: false }
                },
                y: {
                    beginAtZero: true,
                    grid: { color: 'rgba(148, 163, 184, .22)' },
                    ticks: { color: '#64748b', precision: 0 }
                }
            }
        };
    }

    function renderBarChart(name, data, horizontal) {
        var canvas = root.querySelector('[data-qisutu-dashboard-chart="' + name + '"]');
        if (!canvas || !chartAvailable()) {
            return;
        }

        destroyChart(name);
        var labels = Array.isArray(data.labels) ? data.labels : [];
        var values = Array.isArray(data.values) ? data.values.map(number) : [];
        var colors = Array.isArray(data.colors) ? data.colors : [];
        var urls = Array.isArray(data.urls) ? data.urls : [];
        var defaults = chartDefaults();

        charts[name] = new window.Chart(canvas, {
            type: 'bar',
            data: {
                labels: labels,
                datasets: [
                    {
                        label: data.ticketsLabel || '',
                        data: values,
                        backgroundColor: colors,
                        borderColor: colors,
                        borderWidth: 1,
                        borderRadius: 5,
                        maxBarThickness: horizontal ? 34 : 52
                    }
                ]
            },
            options: clickableChartOptions(defaults, urls, horizontal)
        });
    }

    function renderCharts(data) {
        var labels = data.labels || {};
        var trend = data.trend || {};
        var status = data.status || {};
        var age = data.age || {};

        trend.createdLabel = labels.created || '';
        trend.closedLabel = labels.closed || '';
        status.ticketsLabel = labels.tickets || '';
        age.ticketsLabel = labels.tickets || '';

        renderTrend(trend);
        renderBarChart('status', status, true);
        renderBarChart('age', age, false);
    }

    function updateMetrics(data) {
        var metrics = data.metrics || {};
        Object.keys(metrics).forEach(function (key) {
            var card = root.querySelector('[data-qisutu-dashboard-metric="' + key + '"]');
            if (!card) {
                return;
            }
            var value = card.querySelector('[data-qisutu-dashboard-metric-value]');
            if (value) {
                value.textContent = String(number(metrics[key].value));
            }
            if (metrics[key].url) {
                card.setAttribute('href', metrics[key].url);
            }
        });
    }

    function replaceDataTable(selector, labels, values, secondValues, urls) {
        var body = root.querySelector(selector);
        if (!body) {
            return;
        }
        body.textContent = '';
        labels.forEach(function (label, index) {
            var row = document.createElement('tr');
            var labelCell = document.createElement('td');
            var valueCell = document.createElement('td');
            if (urls && urls[index]) {
                var link = document.createElement('a');
                link.href = urls[index];
                link.textContent = label;
                labelCell.appendChild(link);
            }
            else {
                labelCell.textContent = label;
            }
            valueCell.textContent = String(number(values[index]));
            row.appendChild(labelCell);
            row.appendChild(valueCell);
            if (secondValues) {
                var secondCell = document.createElement('td');
                secondCell.textContent = String(number(secondValues[index]));
                row.appendChild(secondCell);
            }
            body.appendChild(row);
        });
    }

    function updateTables(data) {
        var trend = data.trend || {};
        var status = data.status || {};
        var age = data.age || {};
        replaceDataTable(
            '[data-qisutu-dashboard-trend-table]',
            Array.isArray(trend.labels) ? trend.labels : [],
            Array.isArray(trend.created) ? trend.created : [],
            Array.isArray(trend.closed) ? trend.closed : []
        );
        replaceDataTable(
            '[data-qisutu-dashboard-status-table]',
            Array.isArray(status.labels) ? status.labels : [],
            Array.isArray(status.values) ? status.values : [],
            null,
            Array.isArray(status.urls) ? status.urls : []
        );
        replaceDataTable(
            '[data-qisutu-dashboard-age-table]',
            Array.isArray(age.labels) ? age.labels : [],
            Array.isArray(age.values) ? age.values : [],
            null,
            Array.isArray(age.urls) ? age.urls : []
        );
    }

    function tableCell(text, label) {
        var cell = document.createElement('td');
        cell.textContent = text || '';
        if (label) {
            cell.setAttribute('data-label', label);
        }
        return cell;
    }

    function updateAttention(data) {
        var body = root.querySelector('[data-qisutu-dashboard-attention-body]');
        var wrapper = root.querySelector('[data-qisutu-dashboard-attention-table-wrap]');
        var empty = root.querySelector('[data-qisutu-dashboard-attention-empty]');
        if (!body || !wrapper || !empty) {
            return;
        }

        var headers = Array.prototype.map.call(
            root.querySelectorAll('.qisutu-dashboard-attention-table thead th'),
            function (header) { return header.textContent || ''; }
        );
        var tickets = Array.isArray(data.attention) ? data.attention : [];
        body.textContent = '';

        tickets.forEach(function (ticket) {
            var row = document.createElement('tr');
            var numberCell = tableCell('', headers[0]);
            var numberLink = document.createElement('a');
            numberLink.href = ticket.url || '#';
            numberLink.textContent = ticket.ticket_number || '';
            numberCell.appendChild(numberLink);

            var titleCell = tableCell('', headers[1]);
            var titleLink = document.createElement('a');
            titleLink.className = 'qisutu-dashboard-ticket-title';
            titleLink.href = ticket.url || '#';
            titleLink.textContent = ticket.title || '';
            titleCell.appendChild(titleLink);

            var reasonCell = tableCell('', headers[5]);
            var reason = document.createElement('span');
            reason.className = 'qisutu-dashboard-reason';
            if (/^qisutu-dashboard-reason-[a-z]+$/.test(ticket.reason_class || '')) {
                reason.classList.add(ticket.reason_class);
            }
            reason.textContent = ticket.reason || '';
            reasonCell.appendChild(reason);

            row.appendChild(numberCell);
            row.appendChild(titleCell);
            row.appendChild(tableCell(ticket.queue_name || '', headers[2]));
            row.appendChild(tableCell(ticket.state_name || '', headers[3]));
            row.appendChild(tableCell(ticket.age || '', headers[4]));
            row.appendChild(reasonCell);
            body.appendChild(row);
        });

        wrapper.classList.toggle('qisutu-hidden', tickets.length === 0);
        empty.classList.toggle('qisutu-hidden', tickets.length !== 0);
    }

    function applyData(data, updateContent) {
        renderCharts(data || {});
        if (updateContent) {
            updateMetrics(data || {});
            updateTables(data || {});
            updateAttention(data || {});
        }
        if (updatedElement && data.generated_label) {
            updatedElement.textContent = data.generated_label;
        }
    }

    function showRuntimeError(message) {
        if (!errorElement) {
            return;
        }
        errorElement.textContent = message || root.getAttribute('data-qisutu-dashboard-refresh-error') || '';
        errorElement.classList.remove('qisutu-hidden');
    }

    function hideRuntimeError() {
        if (errorElement) {
            errorElement.classList.add('qisutu-hidden');
        }
    }

    function scheduleRefresh() {
        window.clearTimeout(refreshTimer);
        if (!endpoint || !Number.isFinite(refreshSeconds) || refreshSeconds < 30) {
            return;
        }
        refreshTimer = window.setTimeout(function () {
            if (document.visibilityState === 'visible') {
                refreshData();
            }
            else {
                scheduleRefresh();
            }
        }, refreshSeconds * 1000);
    }

    function refreshData() {
        if (refreshing || !endpoint) {
            return;
        }
        refreshing = true;
        if (refreshButton) {
            refreshButton.disabled = true;
            refreshButton.textContent = root.getAttribute('data-qisutu-dashboard-refreshing') || originalRefreshLabel;
        }

        fetch(endpoint, {
            method: 'GET',
            credentials: 'same-origin',
            headers: { Accept: 'application/json' },
            cache: 'no-store'
        })
            .then(function (response) {
                if (!response.ok) {
                    throw new Error('Dashboard request failed');
                }
                return response.json();
            })
            .then(function (data) {
                hideRuntimeError();
                applyData(data, true);
                lastRefresh = Date.now();
            })
            .catch(function () {
                showRuntimeError(root.getAttribute('data-qisutu-dashboard-refresh-error') || 'Dashboard refresh failed.');
            })
            .finally(function () {
                refreshing = false;
                if (refreshButton) {
                    refreshButton.disabled = false;
                    refreshButton.textContent = originalRefreshLabel;
                }
                scheduleRefresh();
            });
    }

    function toggleCustomDates() {
        if (!periodSelect || !customDates) {
            return;
        }
        var custom = periodSelect.value === 'custom';
        customDates.classList.toggle('qisutu-hidden', !custom);
        Array.prototype.forEach.call(customDateInputs, function (input) {
            input.disabled = !custom;
            input.required = custom;
        });
    }

    if (periodSelect) {
        periodSelect.addEventListener('change', toggleCustomDates);
        toggleCustomDates();
    }
    if (refreshButton) {
        refreshButton.addEventListener('click', refreshData);
    }
    document.addEventListener('visibilitychange', function () {
        if (document.visibilityState === 'visible' && Date.now() - lastRefresh >= refreshSeconds * 1000) {
            refreshData();
        }
    });
    if (filterForm) {
        filterForm.addEventListener('submit', function () {
            if (refreshButton) {
                refreshButton.disabled = true;
            }
        });
    }

    applyData(initialData(), false);
    scheduleRefresh();
}());
