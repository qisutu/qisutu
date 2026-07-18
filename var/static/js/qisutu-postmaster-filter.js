/*
 * Qisutu - Open Source Ticket System
 * SPDX-License-Identifier: AGPL-3.0-or-later
 */
(function () {
    'use strict';

    var form = document.querySelector('[data-postmaster-filter-form]');
    var configNode = document.getElementById('qisutu-postmaster-filter-config');
    if (!form || !configNode) {
        return;
    }

    var config;
    try {
        config = JSON.parse(configNode.textContent || '{}');
    }
    catch (error) {
        return;
    }

    var conditionContainer = form.querySelector('[data-condition-rows]');
    var actionContainer = form.querySelector('[data-action-rows]');
    var conditionCount = form.querySelector('[data-condition-count]');
    var actionCount = form.querySelector('[data-action-count]');
    var advancedToggle = form.querySelector('[data-postmaster-advanced-conditions]');
    var advancedHelp = form.querySelector('[data-postmaster-advanced-help]');
    var conditionRefreshers = [];
    var nextCondition = 0;
    var nextAction = 0;

    function element(tag, attributes, text) {
        var node = document.createElement(tag);
        Object.keys(attributes || {}).forEach(function (name) {
            if (name === 'class') {
                node.className = attributes[name];
            }
            else if (name === 'checked') {
                node.checked = Boolean(attributes[name]);
            }
            else {
                node.setAttribute(name, attributes[name]);
            }
        });
        if (text !== undefined) {
            node.textContent = text;
        }
        return node;
    }

    function selectOptions(select, list, selected, emptyLabel) {
        select.innerHTML = '';
        if (emptyLabel !== undefined) {
            select.appendChild(element('option', { value: '' }, emptyLabel));
        }
        (list || []).forEach(function (item) {
            var option = element('option', { value: String(item.id !== undefined ? item.id : item.key) }, item.label || item.key || '');
            if (String(option.value) === String(selected === undefined || selected === null ? '' : selected)) {
                option.selected = true;
            }
            select.appendChild(option);
        });
    }

    function definitionGroupLabel(group, kind) {
        if (kind === 'action') {
            if (group === 'article') { return config.labels.actionArticle; }
            if (group === 'processing') { return config.labels.actionProcessing; }
            return config.labels.actionTicket;
        }
        if (group === 'advanced') { return config.labels.conditionAdvanced; }
        if (group === 'legacy') { return config.labels.conditionLegacy; }
        return config.labels.conditionBasic;
    }

    function selectDefinitionOptions(select, list, selected, kind) {
        var groups = {};
        var order = kind === 'action' ? ['ticket', 'article', 'processing'] : ['basic', 'advanced', 'legacy'];
        select.innerHTML = '';
        (list || []).forEach(function (definition) {
            var group = definition.group || (kind === 'action' ? 'ticket' : 'basic');
            if (!groups[group]) {
                groups[group] = [];
            }
            groups[group].push(definition);
        });
        order.forEach(function (group) {
            if (!groups[group] || !groups[group].length) {
                return;
            }
            var optgroup = element('optgroup', { label: definitionGroupLabel(group, kind) });
            groups[group].forEach(function (definition) {
                var option = element('option', { value: definition.key }, definition.label || definition.key);
                option.selected = definition.key === selected;
                optgroup.appendChild(option);
            });
            select.appendChild(optgroup);
        });
    }

    function findDefinition(list, key) {
        return (list || []).find(function (item) { return item.key === key; }) || null;
    }

    function advancedEnabled() {
        return Boolean(advancedToggle && advancedToggle.checked);
    }

    function availableConditions(selected) {
        return (config.conditionDefinitions || []).filter(function (definition) {
            return definition.key === selected || (!definition.legacy && (!definition.advanced || advancedEnabled()));
        });
    }

    function compatibleOperators(fieldType, selected) {
        return (config.operatorDefinitions || []).filter(function (item) {
            var compatible = item.type === 'all' || item.type === fieldType;
            var visible = !item.advanced || advancedEnabled() || item.key === selected;
            return compatible && visible;
        });
    }

    function addCondition(data) {
        data = data || {};
        var index = nextCondition++;
        conditionCount.value = String(nextCondition);
        var row = element('div', { class: 'qisutu-postmaster-row qisutu-postmaster-condition-row' });

        var fieldWrap = element('div', { class: 'qisutu-form-field' });
        fieldWrap.appendChild(element('label', {}, config.labels.field));
        var field = element('select', { name: 'ConditionField_' + index, required: 'required' });
        fieldWrap.appendChild(field);
        row.appendChild(fieldWrap);

        var argumentWrap = element('div', { class: 'qisutu-form-field qisutu-postmaster-argument' });
        argumentWrap.appendChild(element('label', {}, config.labels.header));
        var argument = element('input', { type: 'text', name: 'ConditionArgument_' + index, value: data.field_argument || '', maxlength: '100', placeholder: 'X-Spam-Status' });
        argumentWrap.appendChild(argument);
        row.appendChild(argumentWrap);

        var operatorWrap = element('div', { class: 'qisutu-form-field' });
        operatorWrap.appendChild(element('label', {}, config.labels.operator));
        var operator = element('select', { name: 'ConditionOperator_' + index, required: 'required' });
        operatorWrap.appendChild(operator);
        row.appendChild(operatorWrap);

        var valueWrap = element('div', { class: 'qisutu-form-field qisutu-postmaster-value' });
        valueWrap.appendChild(element('label', {}, config.labels.value));
        var valueInput = element('input', { type: 'text', name: 'ConditionValue_' + index, value: data.match_value || '' });
        valueWrap.appendChild(valueInput);
        row.appendChild(valueWrap);

        var caseWrap = element('label', { class: 'qisutu-form-checkbox qisutu-postmaster-case' });
        var caseInput = element('input', { type: 'checkbox', name: 'ConditionCaseSensitive_' + index, value: '1', checked: data.case_sensitive });
        caseWrap.appendChild(caseInput);
        caseWrap.appendChild(element('span', {}, config.labels.caseSensitive));
        row.appendChild(caseWrap);

        var remove = element('button', { class: 'qisutu-button qisutu-button-danger qisutu-button-small', type: 'button' }, config.labels.remove);
        remove.addEventListener('click', function () { row.remove(); });
        row.appendChild(remove);

        function refreshFieldOptions() {
            var selected = field.value || data.field_name || 'subject';
            selectDefinitionOptions(field, availableConditions(selected), selected, 'condition');
            if (!field.value && field.options.length) {
                field.value = field.options[0].value;
            }
        }

        function refreshValue() {
            var definition = findDefinition(config.conditionDefinitions, field.value) || { type: 'text' };
            var oldValue = valueInput.value;
            var oldName = valueInput.name;
            var newInput;
            if (operator.value === 'empty' || operator.value === 'not_empty') {
                newInput = element('input', { type: 'text', name: oldName, value: '', disabled: 'disabled' });
            }
            else if (definition.type === 'boolean') {
                newInput = element('select', { name: oldName });
                selectOptions(newInput, [ { id: 'yes', label: config.labels.yes }, { id: 'no', label: config.labels.no } ], oldValue || 'yes');
            }
            else {
                newInput = element('input', { type: definition.type === 'number' ? 'number' : 'text', name: oldName, value: oldValue });
                if (definition.type === 'number') {
                    newInput.step = 'any';
                }
                if (operator.value === 'regex') {
                    newInput.placeholder = config.labels.regexAdvanced;
                }
            }
            valueWrap.replaceChild(newInput, valueInput);
            valueInput = newInput;
        }

        function refresh() {
            var definition = findDefinition(config.conditionDefinitions, field.value) || { type: 'text' };
            var hasArgument = Boolean(definition.argument);
            argumentWrap.hidden = !hasArgument;
            argument.disabled = !hasArgument;
            row.classList.toggle('qisutu-postmaster-condition-has-argument', hasArgument);
            var currentOperator = operator.value || data.operator || 'contains';
            selectOptions(operator, compatibleOperators(definition.type, currentOperator), currentOperator);
            if (!operator.value && operator.options.length) {
                operator.value = operator.options[0].value;
            }
            refreshValue();
        }

        field.addEventListener('change', function () {
            data.field_name = field.value;
            data.operator = '';
            argument.value = '';
            refresh();
        });
        operator.addEventListener('change', refreshValue);
        conditionContainer.appendChild(row);
        refreshFieldOptions();
        refresh();
        conditionRefreshers.push(function () {
            if (!row.isConnected) { return; }
            refreshFieldOptions();
            refresh();
        });
    }

    function addAction(data) {
        data = data || {};
        var index = nextAction++;
        actionCount.value = String(nextAction);
        var row = element('div', { class: 'qisutu-postmaster-row qisutu-postmaster-action-row' });

        var typeWrap = element('div', { class: 'qisutu-form-field' });
        typeWrap.appendChild(element('label', {}, config.labels.action));
        var type = element('select', { name: 'ActionType_' + index, required: 'required' });
        selectDefinitionOptions(type, config.actionDefinitions, data.action_type || 'queue', 'action');
        typeWrap.appendChild(type);
        row.appendChild(typeWrap);

        var targetWrap = element('div', { class: 'qisutu-form-field' });
        var targetLabel = element('label', {}, config.labels.target);
        targetWrap.appendChild(targetLabel);
        var target = element('select', { name: 'ActionTargetID_' + index });
        targetWrap.appendChild(target);
        row.appendChild(targetWrap);

        var valueWrap = element('div', { class: 'qisutu-form-field qisutu-postmaster-action-value' });
        var valueLabel = element('label', {}, config.labels.value);
        valueWrap.appendChild(valueLabel);
        var valueInput = element('input', { type: 'text', name: 'ActionValue_' + index, value: data.action_value || '' });
        valueWrap.appendChild(valueInput);
        row.appendChild(valueWrap);

        var remove = element('button', { class: 'qisutu-button qisutu-button-danger qisutu-button-small', type: 'button' }, config.labels.remove);
        remove.addEventListener('click', function () { row.remove(); });
        row.appendChild(remove);

        function refresh() {
            var definition = findDefinition(config.actionDefinitions, type.value) || { target: 'none' };
            var targetType = definition.target || 'none';
            var needsTarget = ['queue', 'state', 'priority', 'agent', 'service', 'sla', 'customer', 'customer_user', 'dynamic_field', 'dynamic_field_value'].indexOf(targetType) !== -1;
            var needsValue = ['text', 'number', 'visibility', 'sender_type', 'dynamic_field_value'].indexOf(targetType) !== -1;

            targetLabel.textContent = definition.targetLabel || config.labels.target;
            valueLabel.textContent = definition.valueLabel || config.labels.value;
            targetWrap.hidden = !needsTarget;
            target.disabled = !needsTarget;
            valueWrap.hidden = !needsValue;
            row.classList.toggle('qisutu-postmaster-action-no-target', !needsTarget);
            row.classList.toggle('qisutu-postmaster-action-no-value', !needsValue);

            if (needsTarget && config.options[targetType === 'dynamic_field_value' ? 'dynamic_field' : targetType]) {
                selectOptions(target, config.options[targetType === 'dynamic_field_value' ? 'dynamic_field' : targetType], data.target_id || target.value, config.labels.select);
            }
            else {
                target.innerHTML = '';
            }

            var oldValue = valueInput.value;
            var oldName = valueInput.name;
            var newInput;
            if (targetType === 'visibility') {
                newInput = element('select', { name: oldName });
                selectOptions(newInput, [ { id: 'both', label: config.labels.visibleBoth }, { id: 'agent', label: config.labels.visibleAgent } ], oldValue || data.action_value || 'both');
            }
            else if (targetType === 'sender_type') {
                newInput = element('select', { name: oldName });
                selectOptions(newInput, [ { id: 'customer', label: config.labels.senderCustomer }, { id: 'agent', label: config.labels.senderAgent }, { id: 'system', label: config.labels.senderSystem } ], oldValue || data.action_value || 'customer');
            }
            else {
                newInput = element('input', { type: targetType === 'number' ? 'number' : 'text', name: oldName, value: oldValue || data.action_value || '' });
                if (targetType === 'number') {
                    newInput.min = '1';
                }
            }
            newInput.disabled = !needsValue;
            valueWrap.replaceChild(newInput, valueInput);
            valueInput = newInput;
        }

        type.addEventListener('change', function () {
            data.target_id = '';
            data.action_value = '';
            target.innerHTML = '';
            valueInput.value = '';
            refresh();
        });
        actionContainer.appendChild(row);
        refresh();
    }

    if (advancedToggle) {
        advancedToggle.checked = Boolean(config.advancedInitiallyOpen);
        advancedHelp.hidden = !advancedToggle.checked;
        advancedToggle.addEventListener('change', function () {
            advancedHelp.hidden = !advancedToggle.checked;
            conditionRefreshers.forEach(function (refresh) { refresh(); });
        });
    }

    (config.conditions || []).forEach(addCondition);
    (config.actions || []).forEach(addAction);
    if (!conditionContainer.children.length) { addCondition(); }
    if (!actionContainer.children.length) { addAction(); }

    form.querySelector('[data-add-condition]').addEventListener('click', function () { addCondition(); });
    form.querySelector('[data-add-action]').addEventListener('click', function () { addAction(); });
    form.querySelector('[data-test-filter]').addEventListener('click', function () {
        form.querySelector('[data-postmaster-form-step]').value = 'PostmasterFilterTest';
    });
    form.querySelector('[data-save-filter]').addEventListener('click', function () {
        form.querySelector('[data-postmaster-form-step]').value = form.querySelector('input[name="FilterID"]').value ? 'PostmasterFilterUpdate' : 'PostmasterFilterCreate';
    });
}());
