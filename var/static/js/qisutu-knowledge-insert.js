/*
 * Qisutu - Open Source Ticket System
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
        var insertButtons = root.querySelectorAll('[data-qisutu-knowledge-insert-mode]');
        var selectedArticle = null;
        var searchTimer = null;
        var searchSequence = 0;

        if (!openButton || !overlay || !search || !results) {
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

        function setInsertEnabled(enabled, hasLink) {
            insertButtons.forEach(function (button) {
                var linkMode = button.dataset.qisutuKnowledgeInsertMode === 'link';
                button.disabled = !enabled || (linkMode && !hasLink);
            });
        }

        function showArticle(article) {
            selectedArticle = article;
            preview.hidden = false;
            previewTitle.textContent = article.title || '';
            previewMeta.textContent = [article.article_number, article.visibility]
                .filter(Boolean).join(' · ');
            previewContent.innerHTML = article.content || '';
            setInsertEnabled(Boolean(article.can_insert), Boolean(article.portal_url));
            setStatus(article.can_insert ? '' : root.dataset.notAllowedText || '', !article.can_insert);
        }

        function loadArticle(id) {
            var params = parameters(root);
            params.ArticleID = id;
            setStatus(root.dataset.loadingText || '', false);
            setInsertEnabled(false, false);

            requestJSON(root.dataset.articleUrl, params).then(function (data) {
                if (!data.success || !data.article) {
                    throw new Error('Article unavailable');
                }
                showArticle(data.article);
            }).catch(function () {
                selectedArticle = null;
                preview.hidden = true;
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
            setInsertEnabled(false, false);
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

        insertButtons.forEach(function (button) {
            button.addEventListener('click', function () {
                var mode = button.dataset.qisutuKnowledgeInsertMode;
                var html = '';
                if (!selectedArticle || !selectedArticle.can_insert) {
                    return;
                }
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

                if ((root.dataset.context || '') === 'ticket_create') {
                    var form = root.closest('form');
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
