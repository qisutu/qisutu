/*
 * Qisutu - Open Source Ticket System
 * Copyright (C) 2026 Franziska Steps
 * SPDX-License-Identifier: AGPL-3.0-or-later
 */
(function () {
    'use strict';

    function initChecklistAdmin() {
        var list = document.querySelector('[data-qisutu-checklist-item-list]');
        var addButtons = document.querySelectorAll('[data-qisutu-checklist-item-add]');
        if (!list || !addButtons.length) {
            return;
        }

        function nextIndex() {
            var value = parseInt(list.getAttribute('data-next-index') || '0', 10);
            if (isNaN(value) || value < 0) {
                value = 0;
            }
            list.setAttribute('data-next-index', String(value + 1));
            return value;
        }

        function rows() {
            return list.querySelectorAll('[data-qisutu-checklist-item-row]');
        }

        function renumberSortOrders(force) {
            Array.prototype.forEach.call(rows(), function (row, position) {
                var input = row.querySelector('input[name^="ItemSortOrder_"]');
                if (input && (force || !input.value || parseInt(input.value, 10) <= 0)) {
                    input.value = String((position + 1) * 1000);
                }
            });
        }

        function escapeHTML(value) {
            return String(value || '').replace(/[&<>"']/g, function (character) {
                return { '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' }[character];
            });
        }

        function addRow(event) {
            if (event) {
                event.preventDefault();
                event.stopPropagation();
            }

            // Do not create several unused empty rows. If an empty row already
            // exists, move the focus there instead of appending another one.
            var existingRows = rows();
            for (var existingIndex = 0; existingIndex < existingRows.length; existingIndex++) {
                var existingInput = existingRows[existingIndex].querySelector('input[name^="ItemName_"]');
                var existingDescription = existingRows[existingIndex].querySelector('textarea[name^="ItemDescription_"]');
                if (existingInput && existingDescription && !existingInput.value.trim() && !existingDescription.value.trim()) {
                    existingInput.focus();
                    existingInput.scrollIntoView({ block: 'nearest', behavior: 'smooth' });
                    return;
                }
            }

            var index = nextIndex();
            var itemLabel = escapeHTML(list.getAttribute('data-label-item'));
            var descriptionLabel = escapeHTML(list.getAttribute('data-label-description'));
            var sortLabel = escapeHTML(list.getAttribute('data-label-sort'));
            var requiredLabel = escapeHTML(list.getAttribute('data-label-required'));
            var removeLabel = escapeHTML(list.getAttribute('data-label-remove'));
            var row = document.createElement('div');
            var position = rows().length + 1;

            row.className = 'qisutu-checklist-admin-item';
            row.setAttribute('data-qisutu-checklist-item-row', '1');
            row.setAttribute('draggable', 'true');
            row.innerHTML = ''
                + '<input type="hidden" name="ItemRowIndex" value="' + index + '">'
                + '<input type="hidden" name="ItemID_' + index + '" value="">'
                + '<span class="qisutu-checklist-drag-handle" aria-hidden="true">↕</span>'
                + '<div class="qisutu-form-field qisutu-checklist-admin-item-name">'
                + '<label>' + itemLabel + '</label>'
                + '<input type="text" name="ItemName_' + index + '" value="">'
                + '</div>'
                + '<div class="qisutu-form-field qisutu-checklist-admin-item-description">'
                + '<label>' + descriptionLabel + '</label>'
                + '<textarea name="ItemDescription_' + index + '" rows="3"></textarea>'
                + '</div>'
                + '<div class="qisutu-form-field qisutu-checklist-admin-item-sort">'
                + '<label>' + sortLabel + '</label>'
                + '<input type="number" name="ItemSortOrder_' + index + '" value="' + (position * 1000) + '" min="1">'
                + '</div>'
                + '<label class="qisutu-form-checkbox qisutu-checklist-required-checkbox">'
                + '<input type="checkbox" name="ItemRequired_' + index + '" value="1">'
                + '<span>' + requiredLabel + '</span>'
                + '</label>'
                + '<button class="qisutu-button qisutu-button-small qisutu-button-danger qisutu-checklist-admin-item-remove" type="button" data-qisutu-checklist-item-remove>' + removeLabel + '</button>';

            list.appendChild(row);
            var input = row.querySelector('input[type="text"]');
            if (input) {
                input.focus();
                input.scrollIntoView({ block: 'nearest', behavior: 'smooth' });
            }
        }

        Array.prototype.forEach.call(addButtons, function (button) {
            button.addEventListener('click', addRow);
        });

        var draggedRow = null;

        list.addEventListener('dragstart', function (event) {
            var row = event.target.closest('[data-qisutu-checklist-item-row]');
            if (!row) {
                return;
            }
            draggedRow = row;
            row.classList.add('qisutu-checklist-admin-item-dragging');
            if (event.dataTransfer) {
                event.dataTransfer.effectAllowed = 'move';
                event.dataTransfer.setData('text/plain', 'qisutu-checklist-item');
            }
        });

        list.addEventListener('dragover', function (event) {
            if (!draggedRow) {
                return;
            }
            event.preventDefault();
            var target = event.target.closest('[data-qisutu-checklist-item-row]');
            if (!target || target === draggedRow) {
                return;
            }
            var box = target.getBoundingClientRect();
            var after = event.clientY > box.top + (box.height / 2);
            list.insertBefore(draggedRow, after ? target.nextSibling : target);
        });

        list.addEventListener('dragend', function () {
            if (draggedRow) {
                draggedRow.classList.remove('qisutu-checklist-admin-item-dragging');
            }
            draggedRow = null;
            renumberSortOrders(true);
        });

        list.addEventListener('click', function (event) {
            var button = event.target.closest('[data-qisutu-checklist-item-remove]');
            if (!button) {
                return;
            }
            event.preventDefault();
            var currentRows = rows();
            if (currentRows.length <= 1) {
                var onlyRow = currentRows[0] || null;
                var text = onlyRow ? onlyRow.querySelector('input[name^="ItemName_"]') : null;
                var description = onlyRow ? onlyRow.querySelector('textarea[name^="ItemDescription_"]') : null;
                var required = onlyRow ? onlyRow.querySelector('input[name^="ItemRequired_"]') : null;
                if (text) {
                    text.value = '';
                    text.focus();
                }
                if (description) {
                    description.value = '';
                }
                if (required) {
                    required.checked = false;
                }
                return;
            }
            var row = button.closest('[data-qisutu-checklist-item-row]');
            if (row) {
                row.remove();
                renumberSortOrders(true);
            }
        });
    }

    if (document.readyState === 'loading') {
        document.addEventListener('DOMContentLoaded', initChecklistAdmin);
    }
    else {
        initChecklistAdmin();
    }
}());
