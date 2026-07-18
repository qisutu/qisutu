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

    var editors = [];

    function editorFor(target) {
        var textarea = typeof target === 'string' ? document.querySelector(target) : target;

        return textarea && textarea.qisutuEditor ? textarea.qisutuEditor : null;
    }

    function insertHTML(target, html) {
        var textarea = typeof target === 'string' ? document.querySelector(target) : target;
        var editor = editorFor(textarea);

        if (!textarea || !html) {
            return false;
        }

        if (!editor) {
            var start = Number.isInteger(textarea.selectionStart) ? textarea.selectionStart : textarea.value.length;
            var end = Number.isInteger(textarea.selectionEnd) ? textarea.selectionEnd : start;
            textarea.value = textarea.value.slice(0, start) + html + textarea.value.slice(end);
            textarea.focus();
            return true;
        }

        editor.model.change(function () {
            var viewFragment = editor.data.processor.toView(html);
            var modelFragment = editor.data.toModel(viewFragment);

            editor.model.insertContent(modelFragment, editor.model.document.selection);
        });
        editor.updateSourceElement();
        editor.editing.view.focus();
        return true;
    }

    window.QisutuRichText = window.QisutuRichText || {};
    window.QisutuRichText.editorFor = editorFor;
    window.QisutuRichText.insertHTML = insertHTML;

    function staticBase() {
        return window.QISUTU_STATIC_BASE || '/static';
    }

    function language() {
        var lang = document.documentElement.getAttribute('lang') || 'en';

        return lang.toLowerCase().replace(/[^a-z0-9_-]/g, '') || 'en';
    }

    function loadTranslation(lang, callback) {
        if (!lang || lang === 'en') {
            callback();
            return;
        }

        var script = document.createElement('script');
        script.src = staticBase() + '/js/ckeditor5/translations/' + lang + '.umd.js';
        script.onload = callback;
        script.onerror = callback;
        document.head.appendChild(script);
    }

    function pluginList(ckeditor) {
        var names = [
            'Essentials',
            'Paragraph',
            'Heading',
            'Bold',
            'Italic',
            'Underline',
            'Strikethrough',
            'Link',
            'List',
            'TodoList',
            'FontColor',
            'FontBackgroundColor',
            'BlockQuote',
            'Alignment',
            'Image',
            'ImageInsert',
            'ImageUpload',
            'ImageResize',
            'Base64UploadAdapter',
            'Table',
            'TableToolbar',
            'PasteFromOffice',
            'RemoveFormat',
            'SourceEditing',
            'GeneralHtmlSupport'
        ];

        return names
            .map(function (name) {
                return ckeditor[name];
            })
            .filter(Boolean);
    }

    function initEditor(textarea, lang) {
        var ckeditor = window.CKEDITOR;

        if (!ckeditor || !ckeditor.ClassicEditor || textarea.dataset.qisutuRichtextReady) {
            return;
        }

        textarea.dataset.qisutuRichtextReady = '1';

        ckeditor.ClassicEditor.create(textarea, {
            licenseKey: 'GPL',
            language: lang,
            plugins: pluginList(ckeditor),
            toolbar: {
                items: [
                    'heading',
                    '|',
                    'bold',
                    'italic',
                    'underline',
                    'strikethrough',
                    '|',
                    'fontColor',
                    'fontBackgroundColor',
                    '|',
                    'link',
                    'bulletedList',
                    'numberedList',
                    'todoList',
                    '|',
                    'blockQuote',
                    'insertTable',
                    'imageUpload',
                    'imageInsert',
                    '|',
                    'alignment',
                    'removeFormat',
                    'sourceEditing',
                    '|',
                    'undo',
                    'redo'
                ],
                shouldNotGroupWhenFull: false
            },
            image: {
                toolbar: [
                    'imageTextAlternative',
                    'toggleImageCaption',
                    'resizeImage'
                ]
            },
            table: {
                contentToolbar: [
                    'tableColumn',
                    'tableRow',
                    'mergeTableCells'
                ]
            },
            htmlSupport: {
                allow: [
                    {
                        name: /^(p|br|strong|b|em|i|u|s|ul|ol|li|blockquote|a|span|div|h2|h3|h4|pre|code|img|figure|figcaption|table|thead|tbody|tr|th|td)$/,
                        attributes: true,
                        classes: true,
                        styles: true
                    }
                ]
            }
        }).then(function (editor) {
            editors.push(editor);
            textarea.qisutuEditor = editor;
        }).catch(function (error) {
            window.console && window.console.error && window.console.error(error);
            textarea.dataset.qisutuRichtextReady = '';
        });
    }

    function init() {
        var lang = language();

        loadTranslation(lang, function () {
            document.querySelectorAll('textarea.qisutu-richtext').forEach(function (textarea) {
                initEditor(textarea, lang);
            });
        });

        document.addEventListener('submit', function (event) {
            var form = event.target;
            var invalidEditor = null;

            if (form && form.querySelectorAll) {
                form.querySelectorAll('textarea.qisutu-richtext').forEach(function (textarea) {
                    var editor = textarea.qisutuEditor;

                    if (!editor || invalidEditor) {
                        return;
                    }

                    editor.updateSourceElement();

                    if (!editor.getData().replace(/<[^>]*>/g, '').replace(/&nbsp;/g, ' ').trim()) {
                        invalidEditor = editor;
                    }
                });
            }

            if (invalidEditor) {
                event.preventDefault();
                invalidEditor.editing.view.focus();
                return;
            }

            editors.forEach(function (editor) {
                if (editor && editor.updateSourceElement) {
                    editor.updateSourceElement();
                }
            });
        }, true);
    }

    if (document.readyState === 'loading') {
        document.addEventListener('DOMContentLoaded', init);
    }
    else {
        init();
    }
}());
