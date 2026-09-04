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

    function valueFromSelector(selector) {
        var field = selector ? document.querySelector(selector) : null;

        return field ? field.value || '' : '';
    }

    function context(root) {
        if ((root.dataset.context || '') === 'ticket_create') {
            return 'ticket_create';
        }

        var mode = valueFromSelector(root.dataset.modeSelector) || 'note';

        return mode === 'forward' ? 'forward' : mode === 'email' ? 'reply' : 'note';
    }

    function customerSafe(root) {
        if ((root.dataset.context || '') === 'ticket_create') {
            return true;
        }

        var mode = valueFromSelector(root.dataset.modeSelector) || 'note';
        if (mode === 'email' || mode === 'forward') {
            return true;
        }

        var visible = root.dataset.customerVisibleSelector
            ? document.querySelector(root.dataset.customerVisibleSelector)
            : null;

        return Boolean(visible && visible.checked);
    }

    function parameters(root) {
        return {
            QueueID: root.dataset.queueId || valueFromSelector(root.dataset.queueSelector),
            CustomerID: root.dataset.customerId || '',
            CustomerUserID: valueFromSelector(root.dataset.customerUserSelector),
            CustomerSafe: customerSafe(root) ? '1' : '0'
        };
    }

    function requestJSON(url, params, options) {
        var target = new URL(url, window.location.href);

        Object.keys(params || {}).forEach(function (key) {
            if (params[key] !== '' && params[key] !== null && typeof params[key] !== 'undefined') {
                target.searchParams.set(key, params[key]);
            }
        });

        return window.fetch(target.toString(), Object.assign({
            credentials: 'same-origin',
            headers: { 'Accept': 'application/json' }
        }, options || {})).then(function (response) {
            if (!response.ok) {
                throw new Error('HTTP ' + response.status);
            }
            return response.json();
        });
    }

    function safeHTMLText(value) {
        var node = document.createElement('span');
        node.textContent = value || '';
        return node.innerHTML;
    }

    function linkHTML(url, title) {
        var paragraph = document.createElement('p');
        var link = document.createElement('a');
        link.href = url;
        link.textContent = title || url;
        paragraph.appendChild(link);
        return paragraph.outerHTML;
    }

    function init(root) {
        var openButton = root.querySelector('[data-qisutu-knowledge-open]');
        var overlay = root.querySelector('[data-qisutu-knowledge-overlay]');
        var search = root.querySelector('[data-qisutu-knowledge-search]');
        var results = root.querySelector('[data-qisutu-knowledge-results]');
        var status = root.querySelector('[data-qisutu-knowledge-status]');
        var preview = root.querySelector('[data-qisutu-knowledge-preview]');
        var previewTitle = root.querySelector('[data-qisutu-knowledge-preview-title]');
        var previewMeta = root.querySelector('[data-qisutu-knowledge-preview-meta]');
        var previewContent = root.querySelector('[data-qisutu-knowledge-preview-content]');
        var previewAttachments = root.querySelector('[data-qisutu-knowledge-preview-attachments]');
        var includeText = root.querySelector('[data-qisutu-knowledge-include-text]');
        var textMode = root.querySelector('[data-qisutu-knowledge-text-mode]');
        var includeAttachments = root.querySelector('[data-qisutu-knowledge-include-attachments]');
        var applyButton = root.querySelector('[data-qisutu-knowledge-apply]');
        var form = root.closest('form');
        var hiddenInputs = form ? form.querySelector('[data-qisutu-knowledge-hidden-inputs]') : null;
        var selectedAttachmentWrap = form ? form.querySelector('[data-qisutu-knowledge-selected-attachment-wrap]') : null;
        var selectedAttachmentList = form ? form.querySelector('[data-qisutu-knowledge-selected-attachment-list]') : null;
        var selectedArticle = null;
        var searchTimer = null;
        var searchSequence = 0;

        if (!openButton || !overlay || !search || !results || !includeText || !textMode || !includeAttachments || !applyButton) {
            return;
        }

        function setStatus(text, error) {
            status.textContent = text || '';
            status.classList.toggle('qisutu-form-error', Boolean(error));
        }

        function close() {
            overlay.hidden = true;
            overlay.setAttribute('aria-hidden', 'true');
            document.body.classList.remove('qisutu-overlay-open');
            openButton.focus();
        }

        function updateApplyState() {
            var hasAttachments = Boolean(selectedArticle && Array.isArray(selectedArticle.attachments) && selectedArticle.attachments.length);
            var selectionMade = includeText.checked || (includeAttachments.checked && hasAttachments);
            applyButton.disabled = !selectedArticle || !selectedArticle.can_insert || !selectionMade;
            textMode.disabled = !selectedArticle || !selectedArticle.can_insert || !includeText.checked;
        }

        function setInsertEnabled(enabled, hasLink, hasAttachments) {
            includeText.disabled = !enabled;
            includeAttachments.disabled = !enabled || !hasAttachments;
            if (!hasAttachments) {
                includeAttachments.checked = false;
            }
            var linkOption = textMode.querySelector('option[value="link"]');
            if (linkOption) {
                linkOption.disabled = !hasLink;
            }
            if (!hasLink && textMode.value === 'link') {
                textMode.value = 'solution';
            }
            updateApplyState();
        }

        function renderPreviewAttachments(attachments) {
            if (!previewAttachments) {
                return;
            }
            previewAttachments.innerHTML = '';
            if (!Array.isArray(attachments) || !attachments.length) {
                previewAttachments.hidden = true;
                return;
            }

            var list = document.createElement('ul');
            attachments.forEach(function (attachment) {
                var item = document.createElement('li');
                item.textContent = (attachment.filename || '') + (attachment.size_display ? ' · ' + attachment.size_display : '');
                list.appendChild(item);
            });
            previewAttachments.appendChild(list);
            previewAttachments.hidden = false;
        }

        function selectedAttachmentUpdate() {
            if (!selectedAttachmentWrap || !selectedAttachmentList) {
                return;
            }
            selectedAttachmentWrap.classList.toggle(
                'qisutu-hidden',
                !selectedAttachmentList.querySelector('[data-qisutu-knowledge-selected-attachment]')
            );
        }

        function removeSelectedAttachment(id) {
            if (hiddenInputs) {
                hiddenInputs.querySelectorAll('input[name="KnowledgeAttachmentID"]').forEach(function (input) {
                    if (String(input.value) === String(id)) {
                        input.remove();
                    }
                });
            }
            if (selectedAttachmentList) {
                selectedAttachmentList.querySelectorAll('[data-qisutu-knowledge-selected-attachment]').forEach(function (item) {
                    if (String(item.dataset.qisutuKnowledgeSelectedAttachment) === String(id)) {
                        item.remove();
                    }
                });
            }
            selectedAttachmentUpdate();
        }

        function bindSelectedAttachmentRemove(button) {
            if (button.dataset.qisutuKnowledgeRemoveBound === '1') {
                return;
            }
            button.dataset.qisutuKnowledgeRemoveBound = '1';
            button.addEventListener('click', function () {
                removeSelectedAttachment(button.dataset.qisutuKnowledgeAttachmentRemove || '');
            });
        }

        function addSelectedAttachment(attachment) {
            if (!hiddenInputs || !selectedAttachmentList || !attachment || !attachment.id) {
                return;
            }
            var exists = Array.prototype.some.call(
                hiddenInputs.querySelectorAll('input[name="KnowledgeAttachmentID"]'),
                function (input) { return String(input.value) === String(attachment.id); }
            );
            if (exists) {
                return;
            }

            var input = document.createElement('input');
            input.type = 'hidden';
            input.name = 'KnowledgeAttachmentID';
            input.value = attachment.id;
            hiddenInputs.appendChild(input);

            var item = document.createElement('div');
            var description = document.createElement('span');
            var remove = document.createElement('button');
            item.className = 'qisutu-knowledge-selected-attachment';
            item.dataset.qisutuKnowledgeSelectedAttachment = attachment.id;
            description.textContent = (attachment.filename || '') + (attachment.size_display ? ' · ' + attachment.size_display : '');
            remove.type = 'button';
            remove.className = 'qisutu-button qisutu-button-secondary qisutu-button-small';
            remove.dataset.qisutuKnowledgeAttachmentRemove = attachment.id;
            remove.textContent = selectedAttachmentList.dataset.qisutuKnowledgeAttachmentRemoveLabel || 'Remove';
            item.appendChild(description);
            item.appendChild(remove);
            selectedAttachmentList.appendChild(item);
            bindSelectedAttachmentRemove(remove);
            selectedAttachmentUpdate();
        }

        function showArticle(article) {
            selectedArticle = article;
            preview.hidden = false;
            previewTitle.textContent = article.title || '';
            previewMeta.textContent = [article.article_number, article.visibility]
                .filter(Boolean).join(' · ');
            previewContent.innerHTML = article.content || '';
            renderPreviewAttachments(article.attachments || []);
            includeText.checked = true;
            includeAttachments.checked = false;
            textMode.value = 'solution';
            setInsertEnabled(
                Boolean(article.can_insert),
                Boolean(article.portal_url),
                Boolean(Array.isArray(article.attachments) && article.attachments.length)
            );
            setStatus(article.can_insert ? '' : root.dataset.notAllowedText || '', !article.can_insert);
        }

        function loadArticle(id) {
            var params = parameters(root);
            params.ArticleID = id;
            setStatus(root.dataset.loadingText || '', false);
            setInsertEnabled(false, false, false);

            requestJSON(root.dataset.articleUrl, params).then(function (data) {
                if (!data.success || !data.article) {
                    throw new Error('Article unavailable');
                }
                showArticle(data.article);
            }).catch(function () {
                selectedArticle = null;
                preview.hidden = true;
                renderPreviewAttachments([]);
                setStatus(root.dataset.errorText || '', true);
            });
        }

        function renderResults(items) {
            results.innerHTML = '';
            if (!items.length) {
                setStatus(root.dataset.emptyText || '', false);
                return;
            }

            setStatus('', false);
            items.forEach(function (article) {
                var button = document.createElement('button');
                var headline = document.createElement('strong');
                var summary = document.createElement('span');
                var meta = document.createElement('small');

                button.type = 'button';
                button.className = 'qisutu-knowledge-result';
                if (!article.can_insert) {
                    button.classList.add('qisutu-knowledge-result-restricted');
                }
                headline.textContent = article.title || '';
                summary.textContent = article.summary || '';
                meta.textContent = [article.article_number, article.category_name, article.visibility]
                    .filter(Boolean).join(' · ');
                button.appendChild(headline);
                button.appendChild(summary);
                button.appendChild(meta);
                button.addEventListener('click', function () {
                    results.querySelectorAll('.qisutu-knowledge-result-active').forEach(function (item) {
                        item.classList.remove('qisutu-knowledge-result-active');
                    });
                    button.classList.add('qisutu-knowledge-result-active');
                    loadArticle(article.id);
                });
                results.appendChild(button);
            });
        }

        function runSearch() {
            var sequence = ++searchSequence;
            var params = parameters(root);
            params.Query = search.value || '';
            setStatus(root.dataset.loadingText || '', false);

            requestJSON(root.dataset.searchUrl, params).then(function (data) {
                if (sequence !== searchSequence) {
                    return;
                }
                renderResults(data.success && Array.isArray(data.items) ? data.items : []);
            }).catch(function () {
                if (sequence === searchSequence) {
                    results.innerHTML = '';
                    setStatus(root.dataset.errorText || '', true);
                }
            });
        }

        function open() {
            var title = valueFromSelector(root.dataset.titleSelector);
            if (!search.value && title) {
                search.value = title;
            }
            selectedArticle = null;
            preview.hidden = true;
            renderPreviewAttachments([]);
            setInsertEnabled(false, false, false);
            overlay.hidden = false;
            overlay.setAttribute('aria-hidden', 'false');
            document.body.classList.add('qisutu-overlay-open');
            search.focus();
            runSearch();
        }

        openButton.addEventListener('click', open);
        overlay.querySelectorAll('[data-qisutu-knowledge-close]').forEach(function (button) {
            button.addEventListener('click', close);
        });
        overlay.addEventListener('click', function (event) {
            if (event.target === overlay) {
                close();
            }
        });
        search.addEventListener('input', function () {
            window.clearTimeout(searchTimer);
            searchTimer = window.setTimeout(runSearch, 250);
        });
        search.addEventListener('keydown', function (event) {
            if (event.key === 'Enter') {
                event.preventDefault();
                window.clearTimeout(searchTimer);
                runSearch();
            }
        });

        includeText.addEventListener('change', updateApplyState);
        includeAttachments.addEventListener('change', updateApplyState);
        textMode.addEventListener('change', updateApplyState);

        if (selectedAttachmentList) {
            selectedAttachmentList.querySelectorAll('[data-qisutu-knowledge-attachment-remove]').forEach(bindSelectedAttachmentRemove);
            selectedAttachmentUpdate();
        }

        applyButton.addEventListener('click', function () {
            var mode = includeText.checked ? textMode.value : 'attachments';
            var html = '';
            var attachSelected = includeAttachments.checked
                && selectedArticle
                && Array.isArray(selectedArticle.attachments)
                && selectedArticle.attachments.length;
            if (!selectedArticle || !selectedArticle.can_insert || (!includeText.checked && !attachSelected)) {
                setStatus(root.dataset.selectContentText || root.dataset.errorText || '', true);
                return;
            }

            if (includeText.checked) {
                if (mode === 'title_solution') {
                    html = '<h3>' + safeHTMLText(selectedArticle.title) + '</h3>' + (selectedArticle.content || '');
                }
                else if (mode === 'link') {
                    html = selectedArticle.portal_url ? linkHTML(selectedArticle.portal_url, selectedArticle.title) : '';
                }
                else {
                    html = selectedArticle.content || '';
                }
                if (!window.QisutuRichText || !window.QisutuRichText.insertHTML(root.dataset.editor, html)) {
                    setStatus(root.dataset.errorText || '', true);
                    return;
                }
            }

            if (attachSelected) {
                selectedArticle.attachments.forEach(addSelectedAttachment);
            }

            if ((root.dataset.context || '') === 'ticket_create') {
                if (form) {
                    var usageInput = document.createElement('input');
                    usageInput.type = 'hidden';
                    usageInput.name = 'KnowledgeUsage';
                    usageInput.value = selectedArticle.id + '|' + mode;
                    form.appendChild(usageInput);
                }
            }
            else {
                requestJSON(root.dataset.usageUrl, {}, {
                    method: 'POST',
                    headers: {
                        'Accept': 'application/json',
                        'Content-Type': 'application/x-www-form-urlencoded; charset=UTF-8'
                    },
                    body: new URLSearchParams({
                        Page: 'AgentKnowledgeBase',
                        Step: 'UsageRecord',
                        CSRFToken: (document.querySelector('input[name="CSRFToken"]') || {}).value || '',
                        ArticleID: selectedArticle.id,
                        TicketID: root.dataset.ticketId || '0',
                        Context: context(root),
                        InsertMode: mode
                    }).toString()
                }).catch(function () {});
            }
            close();
        });

        document.addEventListener('keydown', function (event) {
            if (event.key === 'Escape' && !overlay.hidden) {
                close();
            }
        });
    }

    function start() {
        document.querySelectorAll('[data-qisutu-knowledge-insert]').forEach(init);
    }

    if (document.readyState === 'loading') {
        document.addEventListener('DOMContentLoaded', start);
    }
    else {
        start();
    }
}());
