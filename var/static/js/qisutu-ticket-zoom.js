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

    function initArticles() {
        var articles = document.querySelectorAll('[data-qisutu-ticket-article]');
        var openAllButtons = document.querySelectorAll('[data-qisutu-articles-open-all]');
        var closeAllButtons = document.querySelectorAll('[data-qisutu-articles-close-all]');

        articles.forEach(function (article) {
            var toggle = article.querySelector('[data-qisutu-article-toggle]');

            if (!toggle) {
                return;
            }

            toggle.addEventListener('click', function () {
                article.classList.toggle('qisutu-ticket-article-open');
            });
        });

        openAllButtons.forEach(function (button) {
            button.addEventListener('click', function () {
                articles.forEach(function (article) {
                    article.classList.add('qisutu-ticket-article-open');
                });
            });
        });

        closeAllButtons.forEach(function (button) {
            button.addEventListener('click', function () {
                articles.forEach(function (article) {
                    article.classList.remove('qisutu-ticket-article-open');
                });
            });
        });
    }

    function initTicketInfoSections() {
        document.querySelectorAll('[data-qisutu-ticket-info-section]').forEach(function (section) {
            var toggle = section.querySelector('[data-qisutu-ticket-info-toggle]');
            var content = section.querySelector('[data-qisutu-ticket-info-content]');

            if (!toggle || !content) {
                return;
            }

            function stateSet(open) {
                section.classList.toggle('qisutu-ticket-info-block-open', open);
                toggle.setAttribute('aria-expanded', open ? 'true' : 'false');
                content.hidden = !open;
            }

            stateSet(toggle.getAttribute('aria-expanded') === 'true');

            toggle.addEventListener('click', function () {
                stateSet(toggle.getAttribute('aria-expanded') !== 'true');
            });
        });
    }

    function initReplyActions() {
        var form = document.querySelector('[data-qisutu-ticket-reply-form]');
        var modeInput = document.querySelector('[data-qisutu-article-mode]');
        var replyArticleIDInput = document.querySelector('[data-qisutu-reply-article-id]');
        var title = document.querySelector('[data-qisutu-reply-form-title]');
        var submit = document.querySelector('[data-qisutu-reply-submit]');
        var subject = document.getElementById('qisutu-article-subject');
        var body = document.getElementById('qisutu-article-body');
        var recipientFields = document.querySelector('[data-qisutu-email-recipient-fields]');
        var replyToInput = document.querySelector('[data-qisutu-reply-to-input]');
        var replyCcInput = document.querySelector('[data-qisutu-reply-cc-input]');
        var noteCustomerVisibleField = document.querySelector('[data-qisutu-note-customer-visible-field]');
        var noteCustomerVisibleCheckbox = document.querySelector('[data-qisutu-note-customer-visible]');
        var dynamicFields = document.querySelector('[data-qisutu-ticket-article-dynamic-fields]');
        var responseTemplateField = document.querySelector('[data-qisutu-response-template-field]');
        var responseTemplateSelect = document.querySelector('[data-qisutu-response-template-select]');
        var responseTemplateError = document.querySelector('[data-qisutu-response-template-error]');
        var responseTemplateHidden = document.querySelector('[data-qisutu-response-template-hidden-inputs]');
        var responseTemplateAttachmentWrap = document.querySelector('[data-qisutu-response-template-attachment-wrap]');
        var responseTemplateAttachmentList = document.querySelector('[data-qisutu-response-template-attachment-list]');
        var responseTemplateAttachments = [];
        var responseTemplateRequestSerial = 0;

        if (!form || !modeInput) {
            return;
        }

        function editorGetData() {
            if (body && body.qisutuEditor && body.qisutuEditor.getData) {
                return body.qisutuEditor.getData() || '';
            }

            return body ? (body.value || '') : '';
        }

        function editorSetData(value) {
            value = value || '';

            if (body && body.qisutuEditor && body.qisutuEditor.setData) {
                body.qisutuEditor.setData(value);
                body.value = value;
                return;
            }

            if (body) {
                body.value = value;
            }
        }

        function formShow(scroll) {
            form.classList.remove('qisutu-hidden');

            if (scroll) {
                form.scrollIntoView({
                    behavior: 'smooth',
                    block: 'start'
                });
            }
        }

        function emailFieldsToggle(show) {
            if (recipientFields) {
                recipientFields.classList.toggle('qisutu-hidden', !show);
            }

            if (replyToInput) {
                replyToInput.required = !!show;
            }
        }

        function dynamicFieldsToggle(show) {
            if (!dynamicFields) {
                return;
            }

            dynamicFields.classList.toggle('qisutu-hidden', !show);
            dynamicFields.querySelectorAll('input, textarea, select').forEach(function (field) {
                field.disabled = !show;
            });
        }

        function responseTemplateErrorToggle(show) {
            if (responseTemplateError) {
                responseTemplateError.classList.toggle('qisutu-hidden', !show);
            }
        }

        function responseTemplateFieldToggle(show) {
            if (!responseTemplateField || !responseTemplateSelect) {
                return;
            }

            var hasTemplates = responseTemplateSelect.options.length > 1;
            responseTemplateField.classList.toggle('qisutu-hidden', !(show && hasTemplates));
            responseTemplateSelect.disabled = !(show && hasTemplates);
        }

        function responseTemplateSlotSet(content) {
            var current = editorGetData();
            var parser = new DOMParser();
            var documentObject = parser.parseFromString('<div id="qisutu-response-template-root">' + current + '</div>', 'text/html');
            var root = documentObject.getElementById('qisutu-response-template-root');
            var slot;

            if (!root) {
                return;
            }

            slot = root.querySelector('.qisutu-response-template-slot');

            if (!slot) {
                slot = documentObject.createElement('div');
                slot.className = 'qisutu-response-template-slot';

                var signature = root.querySelector('.qisutu-mail-signature');
                if (signature && signature.parentNode) {
                    signature.parentNode.insertBefore(slot, signature);
                }
                else {
                    var quote = root.querySelector('blockquote');
                    if (quote && quote.parentNode) {
                        var quoteHeader = quote.previousElementSibling;
                        quote.parentNode.insertBefore(slot, quoteHeader || quote);
                    }
                    else {
                        root.appendChild(slot);
                    }
                }
            }

            slot.innerHTML = content || '<p><br></p><p><br></p>';
            editorSetData(root.innerHTML);
        }

        function responseTemplateHiddenRead() {
            var ids = [];
            var selectionIsExplicit = false;

            if (!responseTemplateHidden) {
                return { ids: ids, explicit: false };
            }

            responseTemplateHidden.querySelectorAll('input[name="ResponseTemplateAttachmentID"]').forEach(function (input) {
                var id = Number(input.value || 0);
                if (id > 0 && ids.indexOf(id) === -1) {
                    ids.push(id);
                }
            });

            selectionIsExplicit = !!responseTemplateHidden.querySelector('input[name="ResponseTemplateAttachmentSelection"]');

            return { ids: ids, explicit: selectionIsExplicit };
        }

        function responseTemplateAttachmentsRender() {
            if (responseTemplateHidden) {
                responseTemplateHidden.innerHTML = '';

                if (responseTemplateSelect && responseTemplateSelect.value) {
                    var marker = document.createElement('input');
                    marker.type = 'hidden';
                    marker.name = 'ResponseTemplateAttachmentSelection';
                    marker.value = '1';
                    responseTemplateHidden.appendChild(marker);
                }

                responseTemplateAttachments.forEach(function (attachment) {
                    var input = document.createElement('input');
                    input.type = 'hidden';
                    input.name = 'ResponseTemplateAttachmentID';
                    input.value = String(attachment.id || '');
                    responseTemplateHidden.appendChild(input);
                });
            }

            if (!responseTemplateAttachmentWrap || !responseTemplateAttachmentList) {
                return;
            }

            responseTemplateAttachmentList.innerHTML = '';
            responseTemplateAttachmentWrap.classList.toggle('qisutu-hidden', !responseTemplateAttachments.length);

            if (!responseTemplateAttachments.length) {
                return;
            }

            var removeLabel = responseTemplateAttachmentList.getAttribute('data-qisutu-response-template-remove-label') || 'Nicht mitsenden';
            var ul = document.createElement('ul');
            ul.className = 'qisutu-ticket-reply-attachment-items';

            responseTemplateAttachments.forEach(function (attachment, index) {
                var li = document.createElement('li');
                var info = document.createElement('span');
                var remove = document.createElement('button');
                var size = attachment.size_display || '';

                info.textContent = (attachment.filename || 'attachment.bin') + (size ? ' (' + size + ')' : '');
                remove.type = 'button';
                remove.className = 'qisutu-ticket-reply-attachment-remove';
                remove.textContent = removeLabel;
                remove.addEventListener('click', function () {
                    responseTemplateAttachments.splice(index, 1);
                    responseTemplateAttachmentsRender();
                });

                li.appendChild(info);
                li.appendChild(remove);
                ul.appendChild(li);
            });

            responseTemplateAttachmentList.appendChild(ul);
        }

        function responseTemplateReset(clearEditorSlot) {
            responseTemplateRequestSerial += 1;
            responseTemplateAttachments = [];
            responseTemplateErrorToggle(false);

            if (responseTemplateSelect) {
                responseTemplateSelect.value = '';
            }

            responseTemplateAttachmentsRender();

            if (clearEditorSlot) {
                responseTemplateSlotSet('');
            }
        }

        function responseTemplateLoad(templateID, insertContent, preserveSubmittedSelection) {
            var ticketID = responseTemplateSelect ? (responseTemplateSelect.getAttribute('data-qisutu-ticket-id') || '') : '';
            var serial = ++responseTemplateRequestSerial;
            var submitted = preserveSubmittedSelection ? responseTemplateHiddenRead() : { ids: [], explicit: false };

            responseTemplateErrorToggle(false);

            if (!templateID || !ticketID) {
                responseTemplateAttachments = [];
                responseTemplateAttachmentsRender();
                if (insertContent) {
                    responseTemplateSlotSet('');
                }
                return;
            }

            fetch('index.pl?Page=AgentTicketZoom&Step=ResponseTemplateGet&TicketID=' + encodeURIComponent(ticketID) + '&ResponseTemplateID=' + encodeURIComponent(templateID), {
                credentials: 'same-origin',
                headers: {
                    'Accept': 'application/json'
                }
            }).then(function (response) {
                if (!response.ok) {
                    throw new Error('Response template request failed');
                }
                return response.json();
            }).then(function (data) {
                if (serial !== responseTemplateRequestSerial) {
                    return;
                }

                if (!data || !data.success) {
                    throw new Error('Response template could not be loaded');
                }

                if (insertContent) {
                    responseTemplateSlotSet(data.content || '');
                }

                responseTemplateAttachments = Array.isArray(data.attachments) ? data.attachments.slice() : [];

                if (preserveSubmittedSelection && submitted.explicit) {
                    responseTemplateAttachments = responseTemplateAttachments.filter(function (attachment) {
                        return submitted.ids.indexOf(Number(attachment.id || 0)) !== -1;
                    });
                }

                responseTemplateAttachmentsRender();
            }).catch(function () {
                if (serial !== responseTemplateRequestSerial) {
                    return;
                }

                responseTemplateAttachments = [];
                responseTemplateAttachmentsRender();
                responseTemplateErrorToggle(true);
            });
        }

        function noteModeOpen(button) {
            modeInput.value = 'note';
            dynamicFieldsToggle(true);
            responseTemplateFieldToggle(false);
            responseTemplateReset(false);

            if (replyArticleIDInput) {
                replyArticleIDInput.value = '';
            }

            if (replyToInput) {
                replyToInput.value = '';
            }

            if (replyCcInput) {
                replyCcInput.value = '';
            }

            if (subject) {
                subject.value = '';
            }

            editorSetData('');
            emailFieldsToggle(false);

            if (noteCustomerVisibleField) {
                noteCustomerVisibleField.classList.remove('qisutu-hidden');
            }

            if (noteCustomerVisibleCheckbox) {
                noteCustomerVisibleCheckbox.checked = false;
            }

            if (title) {
                title.textContent = button.getAttribute('data-qisutu-reply-title') || button.textContent;
            }

            if (submit) {
                submit.textContent = button.getAttribute('data-qisutu-submit-label') || button.textContent;
            }

            formShow(button.getAttribute('data-qisutu-scroll-reply') === '1');

            if (body) {
                window.setTimeout(function () {
                    if (body.qisutuEditor && body.qisutuEditor.editing && body.qisutuEditor.editing.view) {
                        body.qisutuEditor.editing.view.focus();
                    }
                    else {
                        body.focus();
                    }
                }, 250);
            }
        }

        function articleReplyOpen(button) {
            var article = button.closest('[data-qisutu-ticket-article]');
            var template = article ? article.querySelector('[data-qisutu-article-reply-template]') : null;

            modeInput.value = 'email';
            dynamicFieldsToggle(true);

            if (replyArticleIDInput) {
                replyArticleIDInput.value = button.getAttribute('data-qisutu-reply-article-id') || '';
            }

            if (replyToInput) {
                replyToInput.value = button.getAttribute('data-qisutu-reply-to') || '';
            }

            if (replyCcInput) {
                replyCcInput.value = button.getAttribute('data-qisutu-reply-cc') || '';
            }

            if (subject) {
                subject.value = button.getAttribute('data-qisutu-reply-subject') || '';
            }

            editorSetData(template ? template.value : '');
            responseTemplateReset(false);
            responseTemplateFieldToggle(true);
            emailFieldsToggle(true);

            if (noteCustomerVisibleField) {
                noteCustomerVisibleField.classList.add('qisutu-hidden');
            }

            if (noteCustomerVisibleCheckbox) {
                noteCustomerVisibleCheckbox.checked = false;
            }

            if (title) {
                title.textContent = button.textContent || 'Antworten';
            }

            if (submit) {
                submit.textContent = submit.getAttribute('data-qisutu-email-submit-label') || 'Mailantwort senden';
            }

            formShow(true);

            if (replyToInput && !replyToInput.value) {
                window.setTimeout(function () {
                    replyToInput.focus();
                }, 250);
            }
            else if (body) {
                window.setTimeout(function () {
                    if (body.qisutuEditor && body.qisutuEditor.editing && body.qisutuEditor.editing.view) {
                        body.qisutuEditor.editing.view.focus();
                    }
                    else {
                        body.focus();
                    }
                }, 250);
            }
        }

        function articleForwardOpen(button) {
            var article = button.closest('[data-qisutu-ticket-article]');
            var template = article ? article.querySelector('[data-qisutu-article-forward-template]') : null;

            modeInput.value = 'forward';
            dynamicFieldsToggle(false);
            responseTemplateFieldToggle(false);
            responseTemplateReset(false);

            if (replyArticleIDInput) {
                replyArticleIDInput.value = button.getAttribute('data-qisutu-forward-article-id') || '';
            }

            if (replyToInput) {
                replyToInput.value = '';
            }

            if (replyCcInput) {
                replyCcInput.value = '';
            }

            if (subject) {
                subject.value = button.getAttribute('data-qisutu-forward-subject') || '';
            }

            editorSetData(template ? template.value : '');
            emailFieldsToggle(true);

            if (noteCustomerVisibleField) {
                noteCustomerVisibleField.classList.add('qisutu-hidden');
            }

            if (noteCustomerVisibleCheckbox) {
                noteCustomerVisibleCheckbox.checked = false;
            }

            if (title) {
                title.textContent = button.getAttribute('data-qisutu-forward-title') || button.textContent;
            }

            if (submit) {
                submit.textContent = button.getAttribute('data-qisutu-forward-submit-label') || button.textContent;
            }

            formShow(true);

            if (replyToInput) {
                window.setTimeout(function () {
                    replyToInput.focus();
                }, 250);
            }
        }

        if (responseTemplateSelect) {
            responseTemplateSelect.addEventListener('change', function () {
                var templateID = responseTemplateSelect.value || '';

                if (!templateID) {
                    responseTemplateAttachments = [];
                    responseTemplateAttachmentsRender();
                    responseTemplateErrorToggle(false);
                    responseTemplateSlotSet('');
                    return;
                }

                responseTemplateLoad(templateID, true, false);
            });
        }

        dynamicFieldsToggle(modeInput.value !== 'forward');
        emailFieldsToggle(modeInput.value === 'email' || modeInput.value === 'forward');
        responseTemplateFieldToggle(modeInput.value === 'email');

        if (modeInput.value === 'email' && responseTemplateSelect && responseTemplateSelect.value) {
            responseTemplateLoad(responseTemplateSelect.value, false, true);
        }
        else {
            responseTemplateAttachmentsRender();
        }

        if (modeInput.value === 'note' && noteCustomerVisibleField) {
            noteCustomerVisibleField.classList.remove('qisutu-hidden');
        }

        document.querySelectorAll('[data-qisutu-reply-mode="note"]').forEach(function (button) {
            button.addEventListener('click', function () {
                noteModeOpen(button);
            });
        });

        document.querySelectorAll('[data-qisutu-article-reply-button]').forEach(function (button) {
            button.addEventListener('click', function (event) {
                event.preventDefault();
                event.stopPropagation();
                articleReplyOpen(button);
            });
        });

        document.querySelectorAll('[data-qisutu-article-forward-button]').forEach(function (button) {
            button.addEventListener('click', function (event) {
                event.preventDefault();
                event.stopPropagation();
                articleForwardOpen(button);
            });
        });
    }

    function initPendingUntil() {
        var statusSelect = document.querySelector('[data-qisutu-ticket-status]');
        var pendingField = document.querySelector('[data-qisutu-pending-until-field]');
        var pendingInput = document.getElementById('qisutu-ticket-pending-until');

        if (!statusSelect || !pendingField) {
            return;
        }

        function updatePendingField() {
            var selected = statusSelect.options[statusSelect.selectedIndex];
            var stateType = selected ? (selected.getAttribute('data-state-type') || '') : '';
            var isPending = stateType === 'pending';

            pendingField.classList.toggle('qisutu-hidden', !isPending);

            if (pendingInput) {
                pendingInput.required = isPending;
            }
        }

        statusSelect.addEventListener('change', updatePendingField);
        updatePendingField();
    }


    function initAttachmentUpload() {
        var form = document.querySelector('[data-qisutu-ticket-reply-form]');
        var input = document.querySelector('[data-qisutu-attachment-input]');
        var list = document.querySelector('[data-qisutu-attachment-list]');
        var empty = document.querySelector('[data-qisutu-attachment-empty]');
        var overlay = document.querySelector('[data-qisutu-attachment-limit-overlay]');
        var overlayMessage = document.querySelector('[data-qisutu-attachment-limit-message]');
        var overlayClose = document.querySelector('[data-qisutu-attachment-limit-close]');
        var selectedFiles = [];
        var canRewriteFileInput = false;
        var removeLabel = 'Entfernen';
        var maxSizeBytes = Number(input ? (input.getAttribute('data-qisutu-attachment-max-bytes') || 0) : 0);
        var maxSizeLabel = input ? (input.getAttribute('data-qisutu-attachment-max-label') || '') : '';
        var messageTemplate = overlayMessage ? (overlayMessage.getAttribute('data-qisutu-message-template') || '') : '';

        if (!form || !input || !list) {
            return;
        }

        removeLabel = list.getAttribute('data-qisutu-attachment-remove-label') || removeLabel;

        function dataTransferCreate() {
            try {
                if (typeof DataTransfer === 'undefined') {
                    return null;
                }

                return new DataTransfer();
            }
            catch (error) {
                return null;
            }
        }

        function detectFileInputRewriteSupport() {
            var dataTransfer = dataTransferCreate();

            if (!dataTransfer) {
                return false;
            }

            try {
                input.files = dataTransfer.files;
                return true;
            }
            catch (error) {
                return false;
            }
        }

        canRewriteFileInput = detectFileInputRewriteSupport();

        function fileSizeFormat(size) {
            size = Number(size || 0);

            if (size >= 1024 * 1024 * 1024) {
                return (Math.round((size / 1024 / 1024 / 1024) * 10) / 10) + ' GB';
            }

            if (size >= 1024 * 1024) {
                return (Math.round((size / 1024 / 1024) * 10) / 10) + ' MB';
            }

            if (size >= 1024) {
                return (Math.round((size / 1024) * 10) / 10) + ' KB';
            }

            return size + ' B';
        }

        function isTooLarge(file) {
            return !!(file && maxSizeBytes > 0 && Number(file.size || 0) > maxSizeBytes);
        }

        function limitOverlayClose() {
            if (!overlay) {
                return;
            }

            overlay.hidden = true;
            overlay.setAttribute('aria-hidden', 'true');
        }

        function limitOverlayOpen(file) {
            if (!overlay || !overlayMessage) {
                return;
            }

            var text = messageTemplate || 'The selected attachment is too large.';
            text = text.replace(/\{\{Filename\}\}/g, file && file.name ? file.name : 'attachment');
            text = text.replace(/\{\{FileSize\}\}/g, fileSizeFormat(file ? file.size : 0));
            text = text.replace(/\{\{MaxSize\}\}/g, maxSizeLabel || fileSizeFormat(maxSizeBytes));
            overlayMessage.textContent = text;
            overlay.hidden = false;
            overlay.setAttribute('aria-hidden', 'false');

            if (overlayClose) {
                overlayClose.focus();
            }
        }

        function syncInputFiles() {
            var dataTransfer;

            if (!canRewriteFileInput) {
                return false;
            }

            dataTransfer = dataTransferCreate();
            if (!dataTransfer) {
                return false;
            }

            selectedFiles.forEach(function (file) {
                dataTransfer.items.add(file);
            });

            try {
                input.files = dataTransfer.files;
                return true;
            }
            catch (error) {
                canRewriteFileInput = false;
                return false;
            }
        }

        function render() {
            list.innerHTML = '';

            if (!selectedFiles.length) {
                if (empty) {
                    list.appendChild(empty.cloneNode(true));
                }
                return;
            }

            var ul = document.createElement('ul');
            ul.className = 'qisutu-ticket-reply-attachment-items';

            selectedFiles.forEach(function (file, index) {
                var li = document.createElement('li');
                var info = document.createElement('span');
                var remove = document.createElement('button');

                info.textContent = file.name + ' (' + fileSizeFormat(file.size) + ')';

                remove.type = 'button';
                remove.className = 'qisutu-ticket-reply-attachment-remove';
                remove.textContent = removeLabel;
                remove.addEventListener('click', function () {
                    if (canRewriteFileInput) {
                        selectedFiles.splice(index, 1);
                        syncInputFiles();
                    }
                    else {
                        selectedFiles = [];
                        try {
                            input.value = '';
                        }
                        catch (error) {
                        }
                    }

                    render();
                });

                li.appendChild(info);
                li.appendChild(remove);
                ul.appendChild(li);
            });

            list.appendChild(ul);
        }

        input.addEventListener('change', function () {
            var newFiles = Array.prototype.slice.call(input.files || []);
            var oversized = newFiles.filter(isTooLarge);
            var allowed = newFiles.filter(function (file) {
                return !isTooLarge(file);
            });

            if (canRewriteFileInput) {
                allowed.forEach(function (file) {
                    selectedFiles.push(file);
                });
                syncInputFiles();
            }
            else if (oversized.length) {
                selectedFiles = [];
                try {
                    input.value = '';
                }
                catch (error) {
                }
            }
            else {
                selectedFiles = allowed;
            }

            render();

            if (oversized.length) {
                limitOverlayOpen(oversized[0]);
            }
        });

        form.addEventListener('submit', function (event) {
            var files = canRewriteFileInput ? selectedFiles : Array.prototype.slice.call(input.files || []);
            var oversized = files.filter(isTooLarge);

            if (oversized.length) {
                event.preventDefault();
                event.stopPropagation();
                limitOverlayOpen(oversized[0]);
                return;
            }

            syncInputFiles();
        });

        if (overlayClose) {
            overlayClose.addEventListener('click', limitOverlayClose);
        }

        if (overlay) {
            overlay.addEventListener('click', function (event) {
                if (event.target === overlay) {
                    limitOverlayClose();
                }
            });
        }

        document.addEventListener('keydown', function (event) {
            if (event.key === 'Escape' && overlay && !overlay.hidden) {
                limitOverlayClose();
            }
        });

        render();
    }


    function initTicketToolsOverlay() {
        var openButtons = document.querySelectorAll('[data-qisutu-ticket-tools-open]');
        var overlay = document.querySelector('[data-qisutu-ticket-tools-overlay]');
        var closeButton = document.querySelector('[data-qisutu-ticket-tools-close]');
        var tiles = document.querySelectorAll('[data-qisutu-ticket-tool]');
        var panels = document.querySelectorAll('[data-qisutu-ticket-tool-panel]');
        var defaultTool = overlay ? (overlay.getAttribute('data-qisutu-ticket-tools-active') || 'priority') : 'priority';

        if (!openButtons.length || !overlay) {
            return;
        }

        function openButtonsExpandedSet(expanded) {
            openButtons.forEach(function (button) {
                button.setAttribute('aria-expanded', expanded ? 'true' : 'false');
            });
        }

        function eventTargetsOpenButton(event, path) {
            var matched = false;

            openButtons.forEach(function (button) {
                if (matched) {
                    return;
                }

                if ((path && path.indexOf(button) !== -1) || button.contains(event.target)) {
                    matched = true;
                }
            });

            return matched;
        }

        function overlayOpen() {
            overlay.classList.remove('qisutu-hidden');
            overlay.setAttribute('aria-hidden', 'false');
            openButtonsExpandedSet(true);
            autocompleteFieldsReset(overlay);
        }

        function overlayClose() {
            overlay.classList.add('qisutu-hidden');
            overlay.setAttribute('aria-hidden', 'true');
            openButtonsExpandedSet(false);
        }

        function autocompleteFieldsReset(root) {
            if (!root || !root.querySelectorAll) {
                return;
            }

            root.querySelectorAll('[data-qisutu-autocomplete-reset-on-panel="1"]').forEach(function (input) {
                var hiddenID = input.getAttribute('data-qisutu-autocomplete-hidden') || '';
                var hidden = hiddenID ? document.getElementById(hiddenID) : null;
                var field = input.closest ? (input.closest('.qisutu-autocomplete') || input.parentNode) : input.parentNode;
                var results = field ? field.querySelector('[data-qisutu-autocomplete-results]') : null;

                input.value = '';
                input.setAttribute('data-qisutu-autocomplete-selected-label', '');
                input.setAttribute('data-qisutu-autocomplete-request-index', '');

                if (hidden) {
                    hidden.value = '';
                }

                if (results) {
                    results.classList.add('qisutu-hidden');
                    results.innerHTML = '';
                }
            });
        }

        function overlayToggle() {
            if (overlay.classList.contains('qisutu-hidden')) {
                overlayOpen();
            }
            else {
                overlayClose();
            }
        }

        function panelActivate(toolName) {
            var activePanel = null;

            tiles.forEach(function (tile) {
                var isActive = tile.getAttribute('data-qisutu-ticket-tool') === toolName;

                tile.classList.toggle('qisutu-ticket-tools-tile-active', isActive);
                tile.setAttribute('aria-selected', isActive ? 'true' : 'false');
            });

            panels.forEach(function (panel) {
                var isActive = panel.getAttribute('data-qisutu-ticket-tool-panel') === toolName;

                panel.classList.toggle('qisutu-hidden', !isActive);

                if (isActive) {
                    activePanel = panel;
                }
            });

            autocompleteFieldsReset(activePanel);
        }

        panelActivate(defaultTool);

        openButtons.forEach(function (button) {
            button.addEventListener('click', overlayToggle);
        });

        if (closeButton) {
            closeButton.addEventListener('click', overlayClose);
        }

        tiles.forEach(function (tile) {
            tile.addEventListener('click', function () {
                panelActivate(tile.getAttribute('data-qisutu-ticket-tool') || 'priority');
            });
        });

        document.addEventListener('keydown', function (event) {
            if (event.key === 'Escape' && !overlay.classList.contains('qisutu-hidden')) {
                overlayClose();
            }
        });

        document.addEventListener('click', function (event) {
            if (overlay.classList.contains('qisutu-hidden')) {
                return;
            }

            var path = typeof event.composedPath === 'function' ? event.composedPath() : null;

            if (path && path.indexOf(overlay) !== -1) {
                return;
            }

            if (overlay.contains(event.target) || eventTargetsOpenButton(event, path)) {
                return;
            }

            overlayClose();
        });
    }


    function initTicketToolAutocomplete() {
        var controllers = [];

        function closeAll(except) {
            document.querySelectorAll('[data-qisutu-autocomplete-results]').forEach(function (results) {
                if (except && results === except) {
                    return;
                }

                results.classList.add('qisutu-hidden');
                results.innerHTML = '';
            });
        }

        function urlWithTerm(url, term) {
            var separator = url.indexOf('?') === -1 ? '?' : '&';
            return url + separator + 'Term=' + encodeURIComponent(term);
        }

        function messageRender(input, results, className, text) {
            results.innerHTML = '';

            var item = document.createElement('div');
            item.className = className;
            item.textContent = text;
            results.appendChild(item);
            results.classList.remove('qisutu-hidden');
        }

        function itemButtonCreate(item, input, hidden, results) {
            var button = document.createElement('button');
            var label = document.createElement('strong');
            var description = document.createElement('span');

            button.type = 'button';
            button.className = 'qisutu-autocomplete-item';

            label.textContent = item.label || '';
            button.appendChild(label);

            if (item.description) {
                description.textContent = item.description;
                button.appendChild(description);
            }

            button.addEventListener('mousedown', function (event) {
                event.preventDefault();
                event.stopPropagation();
            });

            button.addEventListener('click', function (event) {
                event.preventDefault();
                event.stopPropagation();

                input.value = item.label || '';
                input.setAttribute('data-qisutu-autocomplete-selected-label', item.label || '');

                if (hidden) {
                    hidden.value = item.id || '';
                }

                closeAll();
                input.focus();
            });

            return button;
        }

        function renderResults(input, hidden, results, items) {
            var emptyText = input.getAttribute('data-qisutu-autocomplete-empty') || 'Keine Treffer gefunden.';

            results.innerHTML = '';

            if (!items || !items.length) {
                messageRender(input, results, 'qisutu-autocomplete-empty', emptyText);
                return;
            }

            items.forEach(function (item) {
                results.appendChild(itemButtonCreate(item, input, hidden, results));
            });

            results.classList.remove('qisutu-hidden');
        }

        function lookupRun(input, hidden, results, url, requestIndex) {
            var term = input.value || '';
            var loadingText = input.getAttribute('data-qisutu-autocomplete-loading') || 'Suche läuft ...';
            var errorText = input.getAttribute('data-qisutu-autocomplete-error') || 'Suche konnte nicht geladen werden.';
            var xhr = new XMLHttpRequest();

            messageRender(input, results, 'qisutu-autocomplete-empty', loadingText);

            xhr.open('GET', urlWithTerm(url, term), true);
            xhr.setRequestHeader('Accept', 'application/json');
            xhr.onreadystatechange = function () {
                if (xhr.readyState !== 4) {
                    return;
                }

                if (String(input.getAttribute('data-qisutu-autocomplete-request-index') || '') !== String(requestIndex)) {
                    return;
                }

                if (xhr.status < 200 || xhr.status >= 300) {
                    messageRender(input, results, 'qisutu-autocomplete-empty', errorText);
                    return;
                }

                try {
                    var data = JSON.parse(xhr.responseText || '{}');
                    renderResults(input, hidden, results, data.items || []);
                }
                catch (e) {
                    messageRender(input, results, 'qisutu-autocomplete-empty', errorText);
                }
            };
            xhr.send();
        }

        function controllerCreate(input) {
            if (input.getAttribute('data-qisutu-autocomplete-ready') === '1') {
                return;
            }

            var url = input.getAttribute('data-qisutu-autocomplete-url') || '';
            var minLength = parseInt(input.getAttribute('data-qisutu-autocomplete-min') || '2', 10);
            var hiddenID = input.getAttribute('data-qisutu-autocomplete-hidden') || '';
            var hidden = hiddenID ? document.getElementById(hiddenID) : null;
            var field = input.closest ? (input.closest('.qisutu-autocomplete') || input.parentNode) : input.parentNode;
            var results = field ? field.querySelector('[data-qisutu-autocomplete-results]') : null;
            var timer = null;
            var requestIndex = 0;

            if (!url || !results) {
                return;
            }

            input.setAttribute('data-qisutu-autocomplete-ready', '1');
            input.setAttribute('data-qisutu-autocomplete-selected-label', input.value || '');

            function searchSchedule() {
                var term = input.value || '';
                requestIndex += 1;
                input.setAttribute('data-qisutu-autocomplete-request-index', String(requestIndex));

                if (hidden && term !== input.getAttribute('data-qisutu-autocomplete-selected-label')) {
                    hidden.value = '';
                }

                if (timer) {
                    window.clearTimeout(timer);
                }

                if (term.trim().length < minLength) {
                    closeAll();
                    return;
                }

                timer = window.setTimeout(function () {
                    lookupRun(input, hidden, results, url, requestIndex);
                }, 180);
            }

            results.addEventListener('mousedown', function (event) {
                event.stopPropagation();
            });

            results.addEventListener('click', function (event) {
                event.stopPropagation();
            });

            input.addEventListener('input', searchSchedule);
            input.addEventListener('keyup', searchSchedule);
            input.addEventListener('change', searchSchedule);
            input.addEventListener('paste', function () {
                window.setTimeout(searchSchedule, 0);
            });

            input.addEventListener('focus', function () {
                if ((input.value || '').trim().length >= minLength) {
                    searchSchedule();
                }
            });

            controllers.push({ input: input, results: results });
        }

        document.querySelectorAll('[data-qisutu-autocomplete]').forEach(function (input) {
            controllerCreate(input);
        });

        document.addEventListener('click', function (event) {
            var inside = controllers.some(function (controller) {
                return controller.input.contains(event.target) || controller.results.contains(event.target);
            });

            if (!inside) {
                closeAll();
            }
        });
    }

    function initTicketToolDynamicFields() {
        var queue = document.querySelector('[data-qisutu-ticket-tool-queue]');
        var target = document.querySelector('[data-qisutu-ticket-tool-queue-dynamic-fields]');

        if (!queue || !target) {
            return;
        }

        var requestIndex = 0;

        queue.addEventListener('change', function () {
            var url = queue.getAttribute('data-qisutu-dynamic-fields-url') || '';
            var queueID = queue.value || '';
            requestIndex += 1;
            var currentRequest = requestIndex;

            if (!url || !queueID) {
                target.innerHTML = '';
                return;
            }

            target.innerHTML = '';

            fetch(url + (url.indexOf('?') === -1 ? '?' : '&') + 'QueueID=' + encodeURIComponent(queueID), {
                credentials: 'same-origin'
            }).then(function (response) {
                if (!response.ok) {
                    throw new Error('dynamic fields failed');
                }
                return response.json();
            }).then(function (data) {
                if (currentRequest !== requestIndex) {
                    return;
                }
                target.innerHTML = data && data.success ? (data.html || '') : '';
            }).catch(function () {
                if (currentRequest === requestIndex) {
                    target.innerHTML = '';
                }
            });
        });
    }

    function initDynamicMultiSelects() {
        document.addEventListener('change', function (event) {
            var select = event.target && event.target.closest
                ? event.target.closest('select[data-qisutu-dynamic-multiselect]')
                : null;

            if (!select) {
                return;
            }

            var emptyOption = select.querySelector('option[value=""]');
            var hasSelectedValue = Array.prototype.slice.call(select.options).some(function (option) {
                return option.value !== '' && option.selected;
            });

            if (emptyOption && hasSelectedValue) {
                emptyOption.selected = false;
            }
        });
    }

    function initTimeAccountingCorrectionDialogs() {
        document.querySelectorAll('[data-qisutu-time-correction-open]').forEach(function (button) {
            var dialogID = button.getAttribute('data-qisutu-time-correction-open') || '';
            var dialog = dialogID ? document.getElementById(dialogID) : null;

            if (!dialog) {
                return;
            }

            function dialogClose() {
                if (typeof dialog.close === 'function') {
                    dialog.close();
                }
                else {
                    dialog.removeAttribute('open');
                }
                button.focus();
            }

            button.addEventListener('click', function () {
                if (dialog.hasAttribute('open')) {
                    return;
                }

                if (typeof dialog.showModal === 'function') {
                    dialog.showModal();
                }
                else {
                    dialog.setAttribute('open', '');
                }
            });

            dialog.querySelectorAll('[data-qisutu-time-correction-close]').forEach(function (closeButton) {
                closeButton.addEventListener('click', dialogClose);
            });

            dialog.addEventListener('click', function (event) {
                if (event.target === dialog) {
                    dialogClose();
                }
            });
        });
    }

    function initTicketSplitDialog() {
        var dialog = document.querySelector('[data-qisutu-ticket-split-dialog]');
        var articleIDInput = dialog ? dialog.querySelector('[data-qisutu-split-article-id]') : null;
        var titleInput = dialog ? dialog.querySelector('[data-qisutu-split-title]') : null;

        if (!dialog || !articleIDInput || !titleInput) {
            return;
        }

        function dialogOpen() {
            if (dialog.hasAttribute('open')) {
                return;
            }

            if (typeof dialog.showModal === 'function') {
                dialog.showModal();
            }
            else {
                dialog.setAttribute('open', '');
            }

            window.setTimeout(function () {
                titleInput.focus();
                titleInput.select();
            }, 50);
        }

        function dialogClose() {
            if (typeof dialog.close === 'function') {
                dialog.close();
            }
            else {
                dialog.removeAttribute('open');
            }
        }

        document.querySelectorAll('[data-qisutu-article-split-button]').forEach(function (button) {
            button.addEventListener('click', function (event) {
                event.preventDefault();
                event.stopPropagation();
                articleIDInput.value = button.getAttribute('data-qisutu-split-article-id') || '';
                titleInput.value = button.getAttribute('data-qisutu-split-title') || '';
                dialogOpen();
            });
        });

        dialog.querySelectorAll('[data-qisutu-ticket-split-close]').forEach(function (button) {
            button.addEventListener('click', dialogClose);
        });

        dialog.addEventListener('click', function (event) {
            if (event.target === dialog) {
                dialogClose();
            }
        });

        if (dialog.hasAttribute('open') && typeof dialog.showModal === 'function') {
            dialog.removeAttribute('open');
            dialog.showModal();
        }
    }

    function initTicketHistory() {
        document.querySelectorAll('[data-qisutu-ticket-history]').forEach(function (history) {
            var url = history.getAttribute('data-qisutu-ticket-history-url') || '';
            var list = history.querySelector('[data-qisutu-ticket-history-list]');
            var moreButton = history.querySelector('[data-qisutu-ticket-history-more]');
            var filterButtons = history.querySelectorAll('[data-qisutu-ticket-history-filter]');
            var category = 'all';
            var loading = false;

            if (!url || !list || !moreButton) {
                return;
            }

            function loadingSet(enabled) {
                loading = enabled;
                moreButton.disabled = enabled;
                filterButtons.forEach(function (button) {
                    button.disabled = enabled;
                });
            }

            function messageShow(message) {
                var box = document.createElement('div');
                box.className = 'qisutu-ticket-history-empty';
                box.textContent = message || '';
                list.replaceChildren(box);
            }

            function pageLoad(beforeID, append) {
                var requestURL;

                if (loading) {
                    return;
                }

                requestURL = new URL(url, window.location.href);
                requestURL.searchParams.set('Category', category);
                if (beforeID) {
                    requestURL.searchParams.set('BeforeID', String(beforeID));
                }

                loadingSet(true);
                if (!append) {
                    messageShow(history.getAttribute('data-qisutu-ticket-history-loading') || 'Loading…');
                }

                fetch(requestURL.toString(), {
                    headers: { 'Accept': 'application/json' },
                    credentials: 'same-origin'
                })
                    .then(function (response) {
                        if (!response.ok) {
                            throw new Error('History request failed');
                        }
                        return response.json();
                    })
                    .then(function (data) {
                        if (!data || !data.success) {
                            throw new Error('History response failed');
                        }

                        if (append) {
                            if (Number(data.count || 0) > 0) {
                                list.insertAdjacentHTML('beforeend', data.html || '');
                            }
                        }
                        else {
                            list.innerHTML = data.html || '';
                        }

                        moreButton.setAttribute('data-before-id', String(data.next_before_id || 0));
                        moreButton.hidden = !data.has_more;
                    })
                    .catch(function () {
                        if (!append) {
                            messageShow(history.getAttribute('data-qisutu-ticket-history-error') || 'History could not be loaded.');
                        }
                    })
                    .finally(function () {
                        loadingSet(false);
                    });
            }

            filterButtons.forEach(function (button) {
                button.addEventListener('click', function () {
                    var selected = button.getAttribute('data-qisutu-ticket-history-filter') || 'all';
                    if (selected === category && !loading) {
                        return;
                    }

                    category = selected;
                    filterButtons.forEach(function (item) {
                        var active = item === button;
                        item.classList.toggle('qisutu-ticket-history-filter-active', active);
                        item.setAttribute('aria-pressed', active ? 'true' : 'false');
                    });
                    pageLoad(0, false);
                });
            });

            moreButton.addEventListener('click', function () {
                pageLoad(Number(moreButton.getAttribute('data-before-id') || 0), true);
            });

            history.addEventListener('click', function (event) {
                var link = event.target.closest('.qisutu-ticket-history-link[href^="#qisutu-ticket-article-"]');
                var target;
                var close;
                if (!link) {
                    return;
                }
                target = document.querySelector(link.getAttribute('href'));
                if (target) {
                    target.classList.add('qisutu-ticket-article-open');
                }
                close = document.querySelector('[data-qisutu-ticket-tools-close]');
                if (close) {
                    close.click();
                }
            });
        });
    }

    function init() {
        initArticles();
        initTicketInfoSections();
        initReplyActions();
        initPendingUntil();
        initAttachmentUpload();
        initTicketToolsOverlay();
        initTicketToolAutocomplete();
        initTicketToolDynamicFields();
        initDynamicMultiSelects();
        initTimeAccountingCorrectionDialogs();
        initTicketSplitDialog();
        initTicketHistory();
    }

    if (document.readyState === 'loading') {
        document.addEventListener('DOMContentLoaded', init);
    }
    else {
        init();
    }
}());

/* Qisutu ticket checklist interaction. */
(function () {
    'use strict';

    document.addEventListener('change', function (event) {
        var toggle = event.target.closest('[data-qisutu-checklist-item-toggle]');
        if (!toggle) {
            return;
        }
        var form = toggle.closest('[data-qisutu-checklist-item-form]');
        if (form) {
            toggle.disabled = true;
            form.submit();
        }
    });

    document.addEventListener('submit', function (event) {
        var form = event.target.closest('[data-qisutu-checklist-remove-form]');
        if (!form) {
            return;
        }
        var message = form.getAttribute('data-confirm') || '';
        if (message && !window.confirm(message)) {
            event.preventDefault();
        }
    });

    if (window.location.hash === '#qisutu-ticket-checklists') {
        var block = document.getElementById('qisutu-ticket-checklists');
        if (block) {
            var button = block.querySelector('[data-qisutu-ticket-info-toggle]');
            var content = block.querySelector('[data-qisutu-ticket-info-content]');
            if (button && content) {
                button.setAttribute('aria-expanded', 'true');
                content.hidden = false;
                block.classList.add('qisutu-ticket-info-block-open');
            }
        }
    }
}());
