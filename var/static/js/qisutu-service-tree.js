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

    var instances = typeof WeakMap !== 'undefined' ? new WeakMap() : null;
    var instanceList = [];

    function languageText() {
        var language = String(document.documentElement.lang || 'en').toLowerCase();
        var german = language.indexOf('de') === 0;

        return {
            search: german ? 'Services durchsuchen …' : 'Search services …',
            noResults: german ? 'Keine Services gefunden.' : 'No services found.',
            noSelection: german ? 'Keine Auswahl' : 'No selection',
            expand: german ? 'Unterservices öffnen' : 'Expand subservices',
            collapse: german ? 'Unterservices schließen' : 'Collapse subservices'
        };
    }

    function normalize(value) {
        return String(value || '').toLocaleLowerCase();
    }

    function getInstance(select) {
        if (instances) {
            return instances.get(select);
        }
        return select._qisutuServiceTree || null;
    }

    function setInstance(select, instance) {
        if (instances) {
            instances.set(select, instance);
        }
        else {
            select._qisutuServiceTree = instance;
        }
        instanceList.push(instance);
    }

    function closeOtherInstances(except) {
        instanceList.forEach(function (instance) {
            if (instance && instance !== except) {
                instance.close();
            }
        });
    }

    function ServiceTree(select) {
        this.select = select;
        this.text = languageText();
        this.nodes = [];
        this.nodesByID = {};
        this.childrenByParent = {};
        this.expanded = {};
        this.emptyOption = null;
        this.opened = false;

        this.wrapper = document.createElement('div');
        this.wrapper.className = 'qisutu-service-tree';
        this.wrapper.setAttribute('data-qisutu-service-tree-widget', '1');

        this.button = document.createElement('button');
        this.button.type = 'button';
        this.button.className = 'qisutu-service-tree-button';
        this.button.setAttribute('aria-haspopup', 'tree');
        this.button.setAttribute('aria-expanded', 'false');

        this.buttonLabel = document.createElement('span');
        this.buttonLabel.className = 'qisutu-service-tree-button-label';
        this.button.appendChild(this.buttonLabel);

        this.buttonArrow = document.createElement('span');
        this.buttonArrow.className = 'qisutu-service-tree-button-arrow';
        this.buttonArrow.setAttribute('aria-hidden', 'true');
        this.buttonArrow.textContent = '▾';
        this.button.appendChild(this.buttonArrow);

        this.panel = document.createElement('div');
        this.panel.className = 'qisutu-service-tree-panel';
        this.panel.hidden = true;

        var searchWrap = document.createElement('div');
        searchWrap.className = 'qisutu-service-tree-search-wrap';
        this.search = document.createElement('input');
        this.search.type = 'search';
        this.search.className = 'qisutu-service-tree-search';
        this.search.placeholder = this.text.search;
        this.search.setAttribute('autocomplete', 'off');
        searchWrap.appendChild(this.search);
        this.panel.appendChild(searchWrap);

        this.list = document.createElement('div');
        this.list.className = 'qisutu-service-tree-list';
        this.list.setAttribute('role', 'tree');
        this.panel.appendChild(this.list);

        this.wrapper.appendChild(this.button);
        this.wrapper.appendChild(this.panel);

        select.classList.add('qisutu-service-tree-native');
        select.setAttribute('aria-hidden', 'true');
        select.insertAdjacentElement('afterend', this.wrapper);

        this.bind();
        this.refresh();
    }

    ServiceTree.prototype.bind = function () {
        var self = this;

        this.button.addEventListener('click', function () {
            if (self.opened) {
                self.close();
            }
            else {
                self.open();
            }
        });

        this.search.addEventListener('input', function () {
            self.render();
        });

        this.select.addEventListener('change', function () {
            self.updateButton();
            self.ensureSelectedPath();
            self.render();
        });

        this.panel.addEventListener('click', function (event) {
            event.stopPropagation();
        });
    };

    ServiceTree.prototype.readOptions = function () {
        var self = this;
        var oldExpanded = this.expanded || {};

        this.nodes = [];
        this.nodesByID = {};
        this.childrenByParent = {};
        this.emptyOption = null;

        Array.prototype.slice.call(this.select.options).forEach(function (option) {
            if (option.getAttribute('data-qisutu-service-node') !== '1') {
                if (!self.emptyOption) {
                    self.emptyOption = option;
                }
                return;
            }

            var id = String(option.value || '');
            if (!id) {
                return;
            }

            var node = {
                id: id,
                parentId: String(option.getAttribute('data-parent-id') || '0'),
                name: option.getAttribute('data-service-name') || option.textContent || '',
                fullName: option.getAttribute('data-service-full-name') || option.textContent || '',
                meta: option.getAttribute('data-service-meta') || '',
                selectable: option.getAttribute('data-service-selectable') !== '0' && !option.disabled,
                option: option
            };

            self.nodes.push(node);
            self.nodesByID[id] = node;
        });

        this.nodes.forEach(function (node) {
            var parentId = self.nodesByID[node.parentId] ? node.parentId : '0';
            node.parentId = parentId;
            if (!self.childrenByParent[parentId]) {
                self.childrenByParent[parentId] = [];
            }
            self.childrenByParent[parentId].push(node);
        });

        this.expanded = {};
        Object.keys(oldExpanded).forEach(function (id) {
            if (self.nodesByID[id]) {
                self.expanded[id] = oldExpanded[id];
            }
        });
    };

    ServiceTree.prototype.ensureSelectedPath = function () {
        var selectedId = String(this.select.value || '');
        var visited = {};
        var node = this.nodesByID[selectedId];

        while (node && node.parentId !== '0' && !visited[node.id]) {
            visited[node.id] = true;
            this.expanded[node.parentId] = true;
            node = this.nodesByID[node.parentId];
        }
    };

    ServiceTree.prototype.selectedOption = function () {
        if (this.select.selectedIndex < 0) {
            return null;
        }
        return this.select.options[this.select.selectedIndex] || null;
    };

    ServiceTree.prototype.updateButton = function () {
        var option = this.selectedOption();
        var isNode = option && option.getAttribute('data-qisutu-service-node') === '1';
        var label = '';

        if (isNode) {
            label = option.getAttribute('data-service-full-name') || option.textContent || '';
            var meta = option.getAttribute('data-service-meta') || '';
            if (meta) {
                label += ' — ' + meta;
            }
        }
        else if (option) {
            label = option.textContent || '';
        }
        else if (this.emptyOption) {
            label = this.emptyOption.textContent || '';
        }

        this.buttonLabel.textContent = label;
        this.button.title = label;
        this.button.disabled = this.select.disabled;
    };

    ServiceTree.prototype.setValue = function (value) {
        value = String(value === null || typeof value === 'undefined' ? '' : value);
        this.select.value = value;

        var inputEvent;
        var changeEvent;
        try {
            inputEvent = new Event('input', { bubbles: true });
            changeEvent = new Event('change', { bubbles: true });
        }
        catch (error) {
            inputEvent = document.createEvent('Event');
            inputEvent.initEvent('input', true, false);
            changeEvent = document.createEvent('Event');
            changeEvent.initEvent('change', true, false);
        }

        this.select.dispatchEvent(inputEvent);
        this.select.dispatchEvent(changeEvent);
        this.close();
    };

    ServiceTree.prototype.toggleNode = function (id) {
        this.expanded[id] = !this.expanded[id];
        this.render();
    };

    ServiceTree.prototype.nodeMatches = function (node, query, cache) {
        var self = this;
        if (!query) {
            return true;
        }
        if (Object.prototype.hasOwnProperty.call(cache, node.id)) {
            return cache[node.id];
        }

        var ownMatch = normalize(node.name + ' ' + node.fullName + ' ' + node.meta).indexOf(query) !== -1;
        var childMatch = (this.childrenByParent[node.id] || []).some(function (child) {
            return self.nodeMatches(child, query, cache);
        });
        cache[node.id] = ownMatch || childMatch;
        return cache[node.id];
    };

    ServiceTree.prototype.renderNode = function (node, query, matchCache, level) {
        var self = this;
        if (!this.nodeMatches(node, query, matchCache)) {
            return null;
        }

        var children = this.childrenByParent[node.id] || [];
        var hasChildren = children.length > 0;
        var open = query ? true : !!this.expanded[node.id];

        var item = document.createElement('div');
        item.className = 'qisutu-service-tree-item';
        item.setAttribute('role', 'treeitem');
        item.setAttribute('aria-level', String(level + 1));
        if (hasChildren) {
            item.setAttribute('aria-expanded', open ? 'true' : 'false');
        }

        var row = document.createElement('div');
        row.className = 'qisutu-service-tree-row';
        if (String(this.select.value || '') === node.id) {
            row.classList.add('qisutu-service-tree-row-selected');
        }
        if (!node.selectable) {
            row.classList.add('qisutu-service-tree-row-structural');
        }

        if (hasChildren) {
            var toggle = document.createElement('button');
            toggle.type = 'button';
            toggle.className = 'qisutu-service-tree-node-toggle';
            toggle.setAttribute('aria-label', open ? this.text.collapse : this.text.expand);
            toggle.textContent = open ? '▼' : '▶';
            toggle.addEventListener('click', function (event) {
                event.preventDefault();
                event.stopPropagation();
                self.toggleNode(node.id);
            });
            row.appendChild(toggle);
        }
        else {
            var spacer = document.createElement('span');
            spacer.className = 'qisutu-service-tree-node-spacer';
            spacer.setAttribute('aria-hidden', 'true');
            row.appendChild(spacer);
        }

        var label = document.createElement('button');
        label.type = 'button';
        label.className = 'qisutu-service-tree-node-label';
        label.disabled = !node.selectable;
        label.title = node.fullName;

        var name = document.createElement('span');
        name.className = 'qisutu-service-tree-node-name';
        name.textContent = node.name;
        label.appendChild(name);

        if (node.meta) {
            var meta = document.createElement('span');
            meta.className = 'qisutu-service-tree-node-meta';
            meta.textContent = node.meta;
            label.appendChild(meta);
        }

        if (node.selectable) {
            label.addEventListener('click', function () {
                self.setValue(node.id);
            });
        }
        row.appendChild(label);
        item.appendChild(row);

        if (hasChildren && open) {
            var childContainer = document.createElement('div');
            childContainer.className = 'qisutu-service-tree-children';
            childContainer.setAttribute('role', 'group');
            children.forEach(function (child) {
                var childItem = self.renderNode(child, query, matchCache, level + 1);
                if (childItem) {
                    childContainer.appendChild(childItem);
                }
            });
            item.appendChild(childContainer);
        }

        return item;
    };

    ServiceTree.prototype.render = function () {
        var self = this;
        var query = normalize(this.search.value).trim();
        var matchCache = {};
        this.list.innerHTML = '';

        if (this.emptyOption) {
            var emptyRow = document.createElement('button');
            emptyRow.type = 'button';
            emptyRow.className = 'qisutu-service-tree-empty-option';
            var emptyValue = String(this.emptyOption.value || '');
            emptyRow.textContent = emptyValue === '' ? this.text.noSelection : (this.emptyOption.textContent || this.text.noSelection);
            if (String(this.select.value || '') === emptyValue) {
                emptyRow.classList.add('qisutu-service-tree-row-selected');
            }
            emptyRow.addEventListener('click', function () {
                self.setValue(emptyValue);
            });
            this.list.appendChild(emptyRow);
        }

        var added = 0;
        (this.childrenByParent['0'] || []).forEach(function (node) {
            var item = self.renderNode(node, query, matchCache, 0);
            if (item) {
                self.list.appendChild(item);
                added += 1;
            }
        });

        if (!added) {
            var noResults = document.createElement('div');
            noResults.className = 'qisutu-service-tree-no-results';
            noResults.textContent = this.text.noResults;
            this.list.appendChild(noResults);
        }
    };

    ServiceTree.prototype.open = function () {
        if (this.select.disabled) {
            return;
        }
        closeOtherInstances(this);
        this.opened = true;
        this.panel.hidden = false;
        this.button.setAttribute('aria-expanded', 'true');
        this.search.value = '';
        this.ensureSelectedPath();
        this.render();
        this.search.focus();
    };

    ServiceTree.prototype.close = function () {
        if (!this.opened) {
            return;
        }
        this.opened = false;
        this.panel.hidden = true;
        this.button.setAttribute('aria-expanded', 'false');
        this.search.value = '';
    };

    ServiceTree.prototype.refresh = function () {
        this.readOptions();
        this.ensureSelectedPath();
        this.updateButton();
        this.render();
    };

    function initSelect(select) {
        var instance = getInstance(select);
        if (instance) {
            instance.refresh();
            return instance;
        }

        instance = new ServiceTree(select);
        setInstance(select, instance);
        return instance;
    }

    function initAll(root) {
        var scope = root && root.querySelectorAll ? root : document;
        scope.querySelectorAll('select[data-qisutu-service-tree]').forEach(function (select) {
            initSelect(select);
        });
    }

    function refresh(select) {
        if (!select) {
            return;
        }
        initSelect(select).refresh();
    }

    window.QisutuServiceTree = {
        initAll: initAll,
        refresh: refresh
    };

    document.addEventListener('click', function (event) {
        instanceList.forEach(function (instance) {
            if (instance && instance.opened && !instance.wrapper.contains(event.target)) {
                instance.close();
            }
        });
    });

    document.addEventListener('keydown', function (event) {
        if (event.key === 'Escape') {
            instanceList.forEach(function (instance) {
                if (instance && instance.opened) {
                    instance.close();
                    instance.button.focus();
                }
            });
        }
    });

    if (document.readyState === 'loading') {
        document.addEventListener('DOMContentLoaded', function () {
            initAll(document);
        });
    }
    else {
        initAll(document);
    }
}());
