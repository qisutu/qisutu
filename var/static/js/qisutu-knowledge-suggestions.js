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

    function initialize() {
        var section = document.getElementById('qisutu-knowledge-suggestions');
        var dialog = document.getElementById('qisutu-knowledge-dialog');
        if (!section || !dialog || section.dataset.initialized === '1'
            || typeof dialog.showModal !== 'function'
            || typeof window.fetch !== 'function'
            || typeof window.AbortController !== 'function') {
            return;
        }

        function localURL(value) {
            if (typeof value !== 'string' || !value.trim()) {
                return null;
            }
            try {
                var url = new URL(value, document.baseURI);
                if ((url.protocol !== 'http:' && url.protocol !== 'https:')
                    || url.origin !== window.location.origin || url.username || url.password) {
                    return null;
                }
                return url.href;
            } catch (error) {
                return null;
            }
        }

        var endpoint = localURL(section.dataset.endpoint);
        var fieldName = section.dataset.fieldName || '';
        var bodyFieldName = section.dataset.bodyFieldName || '';
        var form;
        var field;
        var bodyField;
        if (!endpoint || typeof section.dataset.csrfToken !== 'string' || !section.dataset.csrfToken) {
            return;
        }

        function usableField(candidate, owner) {
            return (candidate instanceof HTMLInputElement || candidate instanceof HTMLTextAreaElement)
                && candidate.form === owner && !candidate.disabled
                && (!(candidate instanceof HTMLInputElement) || candidate.type === 'text' || candidate.type === 'search');
        }

        Array.prototype.some.call(document.forms, function (candidate) {
            var page = candidate.elements.namedItem('Page');
            var title = fieldName ? candidate.elements.namedItem(fieldName) : null;
            var description = bodyFieldName ? candidate.elements.namedItem(bodyFieldName) : null;
            if (page && page.value === 'CustomerTicketCreate'
                && (usableField(title, candidate) || usableField(description, candidate))) {
                form = candidate;
                field = usableField(title, candidate) ? title : null;
                bodyField = usableField(description, candidate) ? description : null;
                return true;
            }
            return false;
        });
        if (!form) {
            return;
        }

        var anchor = field || bodyField;
        var row = field && fieldName === 'Title'
            ? field.closest('.qisutu-admin-form-columns') || field.closest('.qisutu-form-field')
            : anchor.closest('.qisutu-form-field');
        if (!row || !form.contains(row)) {
            return;
        }

        var status = section.querySelector('[data-knowledge-status]');
        var results = section.querySelector('[data-knowledge-results]');
        var automatic = section.querySelector('[data-knowledge-automatic]');
        var chooseButton = section.querySelector('[data-knowledge-choose]');
        var browser = section.querySelector('[data-knowledge-browser]');
        var browseQuery = section.querySelector('[data-knowledge-browse-query]');
        var browseSearch = section.querySelector('[data-knowledge-browse-search]');
        var browseStatus = section.querySelector('[data-knowledge-browse-status]');
        var browseResults = section.querySelector('[data-knowledge-browse-results]');
        var dialogTitle = dialog.querySelector('[data-knowledge-dialog-title]');
        var dialogStatus = dialog.querySelector('[data-knowledge-dialog-status]');
        var dialogCategory = dialog.querySelector('[data-knowledge-dialog-category]');
        var dialogSummary = dialog.querySelector('[data-knowledge-dialog-summary]');
        var dialogContent = dialog.querySelector('[data-knowledge-dialog-content]');
        var dialogAttachments = dialog.querySelector('[data-knowledge-dialog-attachments]');
        var attachmentList = dialog.querySelector('[data-knowledge-dialog-attachment-list]');
        var portalLink = dialog.querySelector('[data-knowledge-dialog-portal]');
        var closeButton = dialog.querySelector('[data-knowledge-dialog-close]');
        var continueButton = dialog.querySelector('[data-knowledge-dialog-continue]');
        if (!status || !results || !automatic || !chooseButton || !browser || !browseQuery
            || !browseSearch || !browseStatus || !browseResults || !dialogTitle || !dialogStatus || !dialogCategory
            || !dialogSummary || !dialogContent || !dialogAttachments || !attachmentList
            || !portalLink || !closeButton || !continueButton) {
            return;
        }

        var messages = {
            loading: section.dataset.messageLoading || '',
            empty: section.dataset.messageEmpty || '',
            browseEmpty: section.dataset.messageBrowseEmpty || section.dataset.messageEmpty || '',
            error: section.dataset.messageError || '',
            open: section.dataset.messageOpen || '',
            articleLoading: section.dataset.messageArticleLoading || '',
            articleError: section.dataset.messageArticleError || '',
            resultCount: section.dataset.messageResultCount || ''
        };
        var minimumLength = Number(section.dataset.minimumLength);
        var debounce = Number(section.dataset.debounce);
        if (!Number.isInteger(minimumLength) || minimumLength < 2 || minimumLength > 10) {
            minimumLength = 3;
        }
        if (!Number.isInteger(debounce) || debounce < 100 || debounce > 2000) {
            debounce = 350;
        }

        var searchVersion = 0;
        var viewVersion = 0;
        var browseVersion = 0;
        var searchController = null;
        var viewController = null;
        var browseController = null;
        var browseTimer = null;
        var editorPoll = null;
        var boundEditor = null;
        var timer = null;
        var composing = false;
        var browseComposing = false;
        var opener = null;

        function normalizeText(value, limit) {
            return Array.from(String(value || '').replace(/\s+/g, ' ').trim()).slice(0, limit).join('');
        }

        function editorForBody() {
            if (!bodyField) {
                return null;
            }
            if (bodyField.qisutuEditor) {
                return bodyField.qisutuEditor;
            }
            return window.QisutuRichText && typeof window.QisutuRichText.editorFor === 'function'
                ? window.QisutuRichText.editorFor(bodyField) : null;
        }

        function plainText(html) {
            // Template content is inert: ticket HTML is never inserted into the live page.
            var template = document.createElement('template');
            template.innerHTML = String(html || '');
            Array.prototype.forEach.call(template.content.querySelectorAll('script,style,noscript,template'), function (element) {
                element.remove();
            });
            Array.prototype.forEach.call(template.content.querySelectorAll('br'), function (element) {
                element.replaceWith(document.createTextNode(' '));
            });
            Array.prototype.forEach.call(template.content.querySelectorAll('p,div,li,h1,h2,h3,h4,h5,h6,blockquote,pre,tr,td,th,figcaption'), function (element) {
                element.appendChild(document.createTextNode(' '));
            });
            return template.content.textContent || '';
        }

        function queryValue() {
            var description = bodyField ? bodyField.value : '';
            var editor = editorForBody();
            if (editor && typeof editor.getData === 'function') {
                description = editor.getData();
            }
            if (editor || (bodyField && bodyField.matches('textarea.qisutu-richtext'))) {
                description = plainText(description);
            }
            return {
                subject: field ? normalizeText(field.value, 500) : '',
                description: normalizeText(description, 50000)
            };
        }

        function queryKey(query) {
            return query.subject + '\n' + query.description;
        }

        function queryLength(query) {
            return Array.from(query.subject).length + Array.from(query.description).length;
        }

        function bindEditor() {
            var editor = editorForBody();
            if (editor && editor !== boundEditor && editor.model && editor.model.document
                && typeof editor.model.document.on === 'function') {
                if (boundEditor && typeof boundEditor.model.document.off === 'function') {
                    boundEditor.model.document.off('change:data', updateSearch);
                }
                boundEditor = editor;
                editor.model.document.on('change:data', updateSearch);
                if (editorPoll !== null) {
                    window.clearInterval(editorPoll);
                    editorPoll = null;
                }
                updateSearch();
            }
        }

        function invalidateSearch() {
            searchVersion += 1;
            window.clearTimeout(timer);
            timer = null;
            if (searchController) {
                searchController.abort();
                searchController = null;
            }
        }

        function invalidateView() {
            viewVersion += 1;
            if (viewController) {
                viewController.abort();
                viewController = null;
            }
        }

        function isRecord(value) {
            return value !== null && typeof value === 'object' && !Array.isArray(value);
        }

        function positiveID(value) {
            if ((typeof value !== 'number' && typeof value !== 'string')
                || !/^[1-9][0-9]*$/.test(String(value))) {
                return null;
            }
            return String(value);
        }

        function optionalText(value) {
            return typeof value === 'string' ? value : '';
        }

        async function request(step, values, controller) {
            var body = new URLSearchParams();
            body.set('Step', step);
            body.set('CSRFToken', section.dataset.csrfToken);
            if (section.dataset.language) {
                body.set('Language', section.dataset.language);
            }
            Object.keys(values).forEach(function (key) {
                body.set(key, values[key]);
            });
            var response = await window.fetch(endpoint, {
                method: 'POST',
                credentials: 'same-origin',
                cache: 'no-store',
                headers: {
                    'Accept': 'application/json',
                    'Content-Type': 'application/x-www-form-urlencoded; charset=UTF-8'
                },
                body: body.toString(),
                signal: controller.signal
            });
            if (!response.ok
                || (response.headers.get('Content-Type') || '').split(';')[0].trim().toLowerCase() !== 'application/json') {
                throw new Error('Knowledge request failed');
            }
            var payload = await response.json();
            if (!isRecord(payload)) {
                throw new Error('Invalid knowledge response');
            }
            return payload;
        }

        function showSearchState(state, message) {
            section.dataset.state = state;
            section.setAttribute('aria-busy', state === 'loading' ? 'true' : 'false');
            status.textContent = message;
        }

        function textSpan(className, value) {
            var span = document.createElement('span');
            span.className = className;
            span.textContent = value;
            return span;
        }

        function renderResults(articles, list) {
            list = list || results;
            list.replaceChildren();
            articles.forEach(function (article) {
                var item = document.createElement('li');
                var button = document.createElement('button');
                button.type = 'button';
                button.className = 'qisutu-knowledge-suggestions-result';
                button.dataset.knowledgeArticleId = article.id;
                button.setAttribute('aria-controls', dialog.id);
                button.setAttribute('aria-haspopup', 'dialog');
                button.setAttribute('aria-label', messages.open + ': ' + article.title);
                button.appendChild(textSpan('qisutu-knowledge-suggestions-result-title', article.title));
                if (article.category_name) {
                    button.appendChild(textSpan('qisutu-knowledge-suggestions-result-category', article.category_name));
                }
                if (article.summary) {
                    button.appendChild(textSpan('qisutu-knowledge-suggestions-result-summary', article.summary));
                }
                button.appendChild(textSpan('qisutu-knowledge-suggestions-result-open', messages.open));
                button.addEventListener('click', function () {
                    openArticle(article, button);
                });
                item.appendChild(button);
                list.appendChild(item);
            });
        }

        function validArticles(payload, maximum) {
            if (!Array.isArray(payload.articles)) {
                throw new Error('Invalid knowledge search response');
            }
            return payload.articles.slice(0, maximum).filter(function (article) {
                return isRecord(article) && positiveID(article.id)
                    && typeof article.title === 'string' && article.title.trim();
            }).map(function (article) {
                return {
                    id: positiveID(article.id),
                    title: article.title,
                    summary: optionalText(article.summary),
                    category_name: optionalText(article.category_name)
                };
            });
        }

        function resultMessage(articles) {
            return articles.length ? messages.resultCount.replace(/\{count\}/g, String(articles.length)) : messages.empty;
        }

        async function search(query, version) {
            if (version !== searchVersion || queryKey(queryValue()) !== queryKey(query)) {
                return;
            }
            var controller = new AbortController();
            searchController = controller;
            try {
                var payload = await request('Search', { Subject: query.subject, Description: query.description }, controller);
                if (version !== searchVersion || controller.signal.aborted || queryKey(queryValue()) !== queryKey(query)) {
                    return;
                }
                if (Number.isInteger(payload.minimum_length)
                    && payload.minimum_length >= 2 && payload.minimum_length <= 10) {
                    minimumLength = payload.minimum_length;
                }
                if (queryLength(query) < minimumLength) {
                    automatic.hidden = true;
                    showSearchState('idle', '');
                    return;
                }
                var articles = validArticles(payload, 100);
                renderResults(articles);
                showSearchState(articles.length ? 'results' : 'empty', resultMessage(articles));
            } catch (error) {
                if (version === searchVersion && !controller.signal.aborted) {
                    results.replaceChildren();
                    showSearchState('error', messages.error);
                }
            } finally {
                if (searchController === controller) {
                    searchController = null;
                }
            }
        }

        function updateSearch() {
            // Invalidate before the debounce starts, including when a newer value is too short.
            invalidateSearch();
            results.replaceChildren();
            showSearchState('idle', '');
            var query = queryValue();
            automatic.hidden = composing || queryLength(query) < minimumLength;
            if (automatic.hidden) {
                return;
            }
            showSearchState('loading', messages.loading);
            var version = searchVersion;
            timer = window.setTimeout(function () {
                timer = null;
                search(query, version);
            }, debounce);
        }

        function invalidateBrowse() {
            browseVersion += 1;
            window.clearTimeout(browseTimer);
            browseTimer = null;
            if (browseController) {
                browseController.abort();
                browseController = null;
            }
        }

        function browseValue() {
            return normalizeText(browseQuery.value, 500);
        }

        async function loadBrowse(query, version) {
            if (version !== browseVersion || browser.hidden || browseValue() !== query) {
                return;
            }
            var controller = new AbortController();
            browseController = controller;
            try {
                var payload = await request('Browse', { Query: query }, controller);
                if (version !== browseVersion || controller.signal.aborted || browser.hidden || browseValue() !== query) {
                    return;
                }
                var articles = validArticles(payload, 250);
                renderResults(articles, browseResults);
                browseStatus.textContent = articles.length ? resultMessage(articles) : messages.browseEmpty;
                browser.dataset.state = articles.length ? 'results' : 'empty';
            } catch (error) {
                if (version === browseVersion && !controller.signal.aborted && !browser.hidden) {
                    browseResults.replaceChildren();
                    browseStatus.textContent = messages.error;
                    browser.dataset.state = 'error';
                }
            } finally {
                if (browseController === controller) {
                    browseController = null;
                    browser.setAttribute('aria-busy', 'false');
                }
            }
        }

        function updateBrowse(immediately) {
            invalidateBrowse();
            browseResults.replaceChildren();
            if (browser.hidden) {
                return;
            }
            browseStatus.textContent = messages.loading;
            browser.dataset.state = 'loading';
            browser.setAttribute('aria-busy', 'true');
            var version = browseVersion;
            var query = browseValue();
            if (immediately) {
                loadBrowse(query, version);
            } else {
                browseTimer = window.setTimeout(function () {
                    browseTimer = null;
                    loadBrowse(query, version);
                }, debounce);
            }
        }

        function showDialogText(element, value) {
            element.textContent = value;
            element.hidden = !value;
        }

        function prepareArticleContent(content) {
            // This HTML is sanitized by the authenticated add-on endpoint before transmission.
            dialogContent.innerHTML = content;
            // Open article references separately so the customer's unfinished ticket is preserved.
            Array.prototype.forEach.call(dialogContent.querySelectorAll('a[href]'), function (link) {
                try {
                    var href = link.getAttribute('href');
                    if (href.trim().charAt(0) === '#') {
                        link.removeAttribute('target');
                        return;
                    }
                    var url = new URL(href, document.baseURI);
                    if ((url.protocol !== 'http:' && url.protocol !== 'https:'
                        && url.protocol !== 'mailto:' && url.protocol !== 'tel:')
                        || url.username || url.password) {
                        link.removeAttribute('href');
                        return;
                    }
                    if (url.protocol === 'http:' || url.protocol === 'https:') {
                        link.target = '_blank';
                        link.rel = 'noopener noreferrer';
                    }
                } catch (error) {
                    link.removeAttribute('href');
                }
            });
        }

        function renderAttachments(attachments) {
            attachmentList.replaceChildren();
            if (Array.isArray(attachments)) {
                attachments.slice(0, 500).forEach(function (attachment) {
                    if (!isRecord(attachment) || typeof attachment.filename !== 'string') {
                        return;
                    }
                    var url = localURL(attachment.download_url);
                    if (!url) {
                        return;
                    }
                    var item = document.createElement('li');
                    var link = document.createElement('a');
                    link.href = url;
                    link.target = '_blank';
                    link.rel = 'noopener noreferrer';
                    link.textContent = attachment.filename;
                    item.appendChild(link);
                    if (typeof attachment.size_display === 'string' && attachment.size_display) {
                        item.appendChild(textSpan('qisutu-knowledge-dialog-attachment-size', attachment.size_display));
                    }
                    attachmentList.appendChild(item);
                });
            }
            dialogAttachments.hidden = !attachmentList.childElementCount;
        }

        async function openArticle(selection, button) {
            invalidateView();
            var version = viewVersion;
            var controller = new AbortController();
            viewController = controller;
            opener = button;
            dialog.dataset.state = 'loading';
            dialog.setAttribute('aria-busy', 'true');
            dialogTitle.textContent = selection.title;
            dialogStatus.textContent = messages.articleLoading;
            showDialogText(dialogCategory, '');
            showDialogText(dialogSummary, '');
            dialogContent.replaceChildren();
            attachmentList.replaceChildren();
            dialogAttachments.hidden = true;
            portalLink.hidden = true;
            portalLink.removeAttribute('href');
            if (!dialog.open) {
                dialog.showModal();
            }
            closeButton.focus({ preventScroll: true });
            try {
                var payload = await request('View', { ArticleID: selection.id }, controller);
                if (version !== viewVersion || controller.signal.aborted || !dialog.open) {
                    return;
                }
                var article = payload.article;
                if (!isRecord(article) || positiveID(article.id) !== selection.id
                    || typeof article.title !== 'string' || typeof article.content !== 'string') {
                    throw new Error('Invalid knowledge article response');
                }
                dialogTitle.textContent = article.title;
                showDialogText(dialogCategory, optionalText(article.category_name));
                showDialogText(dialogSummary, optionalText(article.summary));
                prepareArticleContent(article.content);
                renderAttachments(article.attachments);
                var articleURL = localURL(article.url);
                if (articleURL) {
                    portalLink.href = articleURL;
                    portalLink.hidden = false;
                }
                dialogStatus.textContent = '';
                dialog.dataset.state = 'article';
                dialog.setAttribute('aria-busy', 'false');
            } catch (error) {
                if (version === viewVersion && !controller.signal.aborted && dialog.open) {
                    dialogStatus.textContent = messages.articleError;
                    dialog.dataset.state = 'error';
                    dialog.setAttribute('aria-busy', 'false');
                }
            } finally {
                if (viewController === controller) {
                    viewController = null;
                }
            }
        }

        function closeArticle() {
            invalidateView();
            if (dialog.open) {
                dialog.close();
            }
        }

        closeButton.addEventListener('click', closeArticle);
        continueButton.addEventListener('click', closeArticle);
        dialog.addEventListener('cancel', invalidateView);
        dialog.addEventListener('close', function () {
            // Native close events are queued; an older event must not cancel a freshly reopened view.
            if (dialog.open) {
                return;
            }
            invalidateView();
            dialog.setAttribute('aria-busy', 'false');
            var target = opener && opener.isConnected ? opener : anchor;
            target.focus({ preventScroll: true });
            opener = null;
        });
        [field, bodyField].forEach(function (input) {
            if (!input) {
                return;
            }
            input.addEventListener('input', function (event) {
                if (event.isComposing) {
                    composing = true;
                }
                updateSearch();
            });
            input.addEventListener('compositionstart', function () {
                composing = true;
                updateSearch();
            });
            input.addEventListener('compositionend', function () {
                composing = false;
                updateSearch();
            });
        });
        chooseButton.addEventListener('click', function () {
            browser.hidden = !browser.hidden;
            chooseButton.setAttribute('aria-expanded', browser.hidden ? 'false' : 'true');
            if (browser.hidden) {
                invalidateBrowse();
            } else {
                updateBrowse(true);
                browseQuery.focus({ preventScroll: true });
            }
        });
        browseSearch.addEventListener('click', function () { updateBrowse(true); });
        browseQuery.addEventListener('input', function (event) {
            if (event.isComposing || browseComposing) {
                invalidateBrowse();
                return;
            }
            updateBrowse(false);
        });
        browseQuery.addEventListener('compositionstart', function () {
            browseComposing = true;
            invalidateBrowse();
        });
        browseQuery.addEventListener('compositionend', function () {
            browseComposing = false;
            updateBrowse(false);
        });
        browseQuery.addEventListener('keydown', function (event) {
            if (event.key === 'Enter' && !event.isComposing && !browseComposing) {
                event.preventDefault();
                updateBrowse(true);
            }
        });
        window.addEventListener('pagehide', function () {
            invalidateSearch();
            invalidateView();
            invalidateBrowse();
            if (editorPoll !== null) {
                window.clearInterval(editorPoll);
                editorPoll = null;
            }
            if (boundEditor && typeof boundEditor.model.document.off === 'function') {
                boundEditor.model.document.off('change:data', updateSearch);
            }
            boundEditor = null;
        });
        window.addEventListener('pageshow', function (event) {
            if (!event.persisted) {
                return;
            }
            startEditorBinding();
            updateSearch();
            if (!browser.hidden) {
                updateBrowse(true);
            }
        });

        function startEditorBinding() {
            if (bodyField && (bodyField.matches('textarea.qisutu-richtext') || editorForBody())) {
                if (editorPoll === null) {
                    editorPoll = window.setInterval(bindEditor, 250);
                }
                bindEditor();
            }
        }

        section.dataset.initialized = '1';
        row.insertAdjacentElement('afterend', section);
        section.hidden = false;
        updateSearch();
        startEditorBinding();
    }

    if (document.readyState === 'loading') {
        document.addEventListener('DOMContentLoaded', initialize, { once: true });
    } else {
        initialize();
    }
}());
