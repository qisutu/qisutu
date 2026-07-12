/*
 * Qisutu - Open Source Ticket System
 * Copyright (C) 2026 Franziska Steps
 * SPDX-License-Identifier: AGPL-3.0-or-later
 */
(function () {
    'use strict';

    function scheduleFieldsUpdate() {
        var TypeSelect = document.querySelector('[data-qisutu-schedule-type]');
        if (!TypeSelect) {
            return;
        }
        var Type = TypeSelect.value;
        document.querySelectorAll('[data-qisutu-schedule-field]').forEach(function (Field) {
            var Types = (Field.getAttribute('data-qisutu-schedule-field') || '').split(/\s+/);
            Field.hidden = Types.indexOf(Type) === -1;
        });
    }

    function actionModeUpdate(Select) {
        if (!Select) {
            return;
        }
        var ValueSelect = Select.parentElement ? Select.parentElement.querySelectorAll('select')[1] : null;
        if (!ValueSelect) {
            return;
        }
        ValueSelect.hidden = Select.value !== 'set';
        ValueSelect.disabled = Select.value !== 'set';
    }

    function agentNotificationUpdate() {
        var Mode = document.querySelector('[data-qisutu-agent-notify-mode]');
        var User = document.querySelector('[data-qisutu-agent-notify-user]');
        if (!Mode || !User) {
            return;
        }
        User.hidden = Mode.value !== 'agent';
        User.disabled = Mode.value !== 'agent';
    }

    function previewSubmit(Button) {
        var Form = Button.closest('form');
        var Step = Form ? Form.querySelector('[data-qisutu-automation-step]') : null;
        var PreviewRequested = false;
        if (!Form || !Step) {
            return;
        }
        Button.addEventListener('click', function () {
            PreviewRequested = true;
            Step.value = Button.getAttribute('data-preview-step') || 'RulePreview';
        });
        Form.addEventListener('submit', function () {
            if (!PreviewRequested) {
                Step.value = Form.querySelector('input[name="RuleID"]').value ? 'RuleUpdate' : 'RuleCreate';
            }
            PreviewRequested = false;
        });
    }

    function multiSelectConfig(Form) {
        return {
            empty: Form.getAttribute('data-qisutu-multiselect-empty') || 'No selection',
            choose: Form.getAttribute('data-qisutu-multiselect-choose') || 'Select',
            selected: Form.getAttribute('data-qisutu-multiselect-selected') || 'selected',
            more: Form.getAttribute('data-qisutu-multiselect-more') || 'more',
            search: Form.getAttribute('data-qisutu-multiselect-search') || 'Search ...',
            selectAll: Form.getAttribute('data-qisutu-multiselect-select-all') || 'Select all visible',
            clear: Form.getAttribute('data-qisutu-multiselect-clear') || 'Clear selection',
            apply: Form.getAttribute('data-qisutu-multiselect-apply') || 'Apply',
            cancel: Form.getAttribute('data-qisutu-multiselect-cancel') || 'Cancel',
            close: Form.getAttribute('data-qisutu-multiselect-close') || 'Close',
            dialogTitle: Form.getAttribute('data-qisutu-multiselect-dialog-title') || 'Multiple selection'
        };
    }

    function multiSelectFieldLabel(Select, Config) {
        var Field = Select.closest('.qisutu-form-field');
        var Label = Field ? Field.querySelector(':scope > label') : null;
        if (!Label) {
            var DynamicRow = Select.closest('.qisutu-automation-dynamic-row');
            Label = DynamicRow ? DynamicRow.querySelector('.qisutu-form-checkbox span') : null;
        }
        var Text = Label ? (Label.textContent || '').trim() : '';
        return Text || Config.dialogTitle;
    }

    function multiSelectOptions(Select) {
        return Array.prototype.slice.call(Select.options).filter(function (Option) {
            return Option.value !== '' && !Option.disabled;
        });
    }

    function selectedOptions(Select) {
        return multiSelectOptions(Select).filter(function (Option) {
            return Option.selected;
        });
    }

    function createElement(Tag, ClassName, Text) {
        var Element = document.createElement(Tag);
        if (ClassName) {
            Element.className = ClassName;
        }
        if (Text !== undefined && Text !== null) {
            Element.textContent = Text;
        }
        return Element;
    }

    function smartMultiSelectInit(Form) {
        var Selects = Form.querySelectorAll('select[multiple]');
        if (!Selects.length) {
            return;
        }

        var Config = multiSelectConfig(Form);
        var Active = null;
        var LastFocus = null;

        var Overlay = createElement('div', 'qisutu-smart-multiselect-overlay');
        Overlay.hidden = true;
        Overlay.setAttribute('data-qisutu-smart-multiselect-overlay', '');

        var Dialog = createElement('section', 'qisutu-smart-multiselect-dialog');
        Dialog.setAttribute('role', 'dialog');
        Dialog.setAttribute('aria-modal', 'true');
        Dialog.setAttribute('aria-labelledby', 'qisutu-smart-multiselect-title');

        var Header = createElement('header', 'qisutu-smart-multiselect-header');
        var HeaderText = createElement('div', 'qisutu-smart-multiselect-header-text');
        var Eyebrow = createElement('span', 'qisutu-smart-multiselect-eyebrow', Config.dialogTitle);
        var Title = createElement('h2', '', '');
        Title.id = 'qisutu-smart-multiselect-title';
        HeaderText.appendChild(Eyebrow);
        HeaderText.appendChild(Title);
        var CloseButton = createElement('button', 'qisutu-smart-multiselect-close', '×');
        CloseButton.type = 'button';
        CloseButton.setAttribute('aria-label', Config.close);
        Header.appendChild(HeaderText);
        Header.appendChild(CloseButton);

        var SearchWrap = createElement('div', 'qisutu-smart-multiselect-search');
        var SearchIcon = createElement('span', 'qisutu-smart-multiselect-search-icon', '⌕');
        SearchIcon.setAttribute('aria-hidden', 'true');
        var SearchInput = createElement('input', '');
        SearchInput.type = 'search';
        SearchInput.placeholder = Config.search;
        SearchInput.autocomplete = 'off';
        SearchWrap.appendChild(SearchIcon);
        SearchWrap.appendChild(SearchInput);

        var Toolbar = createElement('div', 'qisutu-smart-multiselect-toolbar');
        var Count = createElement('strong', 'qisutu-smart-multiselect-dialog-count', '');
        var ToolbarButtons = createElement('div', 'qisutu-smart-multiselect-toolbar-buttons');
        var SelectAllButton = createElement('button', 'qisutu-button qisutu-button-secondary qisutu-button-small', Config.selectAll);
        SelectAllButton.type = 'button';
        var ClearButton = createElement('button', 'qisutu-button qisutu-button-secondary qisutu-button-small', Config.clear);
        ClearButton.type = 'button';
        ToolbarButtons.appendChild(SelectAllButton);
        ToolbarButtons.appendChild(ClearButton);
        Toolbar.appendChild(Count);
        Toolbar.appendChild(ToolbarButtons);

        var List = createElement('div', 'qisutu-smart-multiselect-list');
        List.setAttribute('role', 'listbox');
        List.setAttribute('aria-multiselectable', 'true');

        var Footer = createElement('footer', 'qisutu-smart-multiselect-footer');
        var CancelButton = createElement('button', 'qisutu-button qisutu-button-secondary', Config.cancel);
        CancelButton.type = 'button';
        var ApplyButton = createElement('button', 'qisutu-button qisutu-button-primary', Config.apply);
        ApplyButton.type = 'button';
        Footer.appendChild(CancelButton);
        Footer.appendChild(ApplyButton);

        Dialog.appendChild(Header);
        Dialog.appendChild(SearchWrap);
        Dialog.appendChild(Toolbar);
        Dialog.appendChild(List);
        Dialog.appendChild(Footer);
        Overlay.appendChild(Dialog);
        document.body.appendChild(Overlay);

        function updateDialogCount() {
            if (!Active) {
                Count.textContent = '';
                return;
            }
            Count.textContent = Active.draft.size + ' ' + Config.selected;
        }

        function updateTrigger(Select, Trigger) {
            var Selected = selectedOptions(Select);
            var Summary = Trigger.querySelector('[data-qisutu-multiselect-summary]');
            var CountText = Trigger.querySelector('[data-qisutu-multiselect-count]');
            Summary.textContent = '';

            if (!Selected.length) {
                Summary.appendChild(createElement('span', 'qisutu-smart-multiselect-placeholder', Config.empty));
                CountText.textContent = Config.choose;
                Trigger.classList.remove('qisutu-has-selection');
            }
            else {
                Selected.slice(0, 2).forEach(function (Option) {
                    Summary.appendChild(createElement('span', 'qisutu-smart-multiselect-chip', Option.textContent.trim()));
                });
                if (Selected.length > 2) {
                    Summary.appendChild(createElement('span', 'qisutu-smart-multiselect-chip qisutu-smart-multiselect-chip-more', '+' + (Selected.length - 2) + ' ' + Config.more));
                }
                CountText.textContent = Selected.length + ' ' + Config.selected;
                Trigger.classList.add('qisutu-has-selection');
            }
            Trigger.setAttribute('aria-label', multiSelectFieldLabel(Select, Config) + ': ' + CountText.textContent);
        }

        function filteredOptions() {
            if (!Active) {
                return [];
            }
            var Query = SearchInput.value.trim().toLocaleLowerCase();
            return Active.options.filter(function (Option) {
                return !Query || Option.textContent.toLocaleLowerCase().indexOf(Query) !== -1;
            });
        }

        function renderList() {
            List.textContent = '';
            if (!Active) {
                return;
            }
            var Options = filteredOptions();
            if (!Options.length) {
                List.appendChild(createElement('div', 'qisutu-smart-multiselect-no-results', Config.empty));
                updateDialogCount();
                return;
            }

            Options.forEach(function (Option) {
                var Row = createElement('label', 'qisutu-smart-multiselect-option');
                Row.setAttribute('role', 'option');
                var Checkbox = createElement('input', '');
                Checkbox.type = 'checkbox';
                Checkbox.value = Option.value;
                Checkbox.checked = Active.draft.has(Option.value);
                Row.setAttribute('aria-selected', Checkbox.checked ? 'true' : 'false');
                var Checkmark = createElement('span', 'qisutu-smart-multiselect-checkmark', '✓');
                Checkmark.setAttribute('aria-hidden', 'true');
                var Text = createElement('span', 'qisutu-smart-multiselect-option-text', Option.textContent.trim());
                Row.appendChild(Checkbox);
                Row.appendChild(Checkmark);
                Row.appendChild(Text);
                Checkbox.addEventListener('change', function () {
                    if (!Active) {
                        return;
                    }
                    if (Checkbox.checked) {
                        Active.draft.add(Option.value);
                    }
                    else {
                        Active.draft.delete(Option.value);
                    }
                    Row.setAttribute('aria-selected', Checkbox.checked ? 'true' : 'false');
                    updateDialogCount();
                });
                List.appendChild(Row);
            });
            updateDialogCount();
        }

        function closeDialog(RestoreFocus) {
            Overlay.hidden = true;
            document.body.classList.remove('qisutu-overlay-open');
            if (Active && Active.trigger) {
                Active.trigger.setAttribute('aria-expanded', 'false');
            }
            Active = null;
            SearchInput.value = '';
            List.textContent = '';
            if (RestoreFocus !== false && LastFocus) {
                LastFocus.focus();
            }
            LastFocus = null;
        }

        function openDialog(Select, Trigger) {
            LastFocus = Trigger;
            Active = {
                select: Select,
                trigger: Trigger,
                options: multiSelectOptions(Select),
                draft: new Set(selectedOptions(Select).map(function (Option) { return Option.value; }))
            };
            Title.textContent = multiSelectFieldLabel(Select, Config);
            SearchInput.value = '';
            renderList();
            Overlay.hidden = false;
            document.body.classList.add('qisutu-overlay-open');
            Trigger.setAttribute('aria-expanded', 'true');
            window.requestAnimationFrame(function () {
                SearchInput.focus();
            });
        }

        Selects.forEach(function (Select) {
            if (Select.getAttribute('data-qisutu-smart-multiselect-ready') === '1') {
                return;
            }
            Select.setAttribute('data-qisutu-smart-multiselect-ready', '1');
            Select.hidden = true;
            Select.setAttribute('aria-hidden', 'true');
            Select.tabIndex = -1;

            var Widget = createElement('div', 'qisutu-smart-multiselect');
            var Trigger = createElement('button', 'qisutu-smart-multiselect-trigger');
            Trigger.type = 'button';
            Trigger.setAttribute('aria-haspopup', 'dialog');
            Trigger.setAttribute('aria-expanded', 'false');
            var Summary = createElement('span', 'qisutu-smart-multiselect-summary');
            Summary.setAttribute('data-qisutu-multiselect-summary', '');
            var Meta = createElement('span', 'qisutu-smart-multiselect-meta');
            var CountText = createElement('span', 'qisutu-smart-multiselect-count');
            CountText.setAttribute('data-qisutu-multiselect-count', '');
            var Chevron = createElement('span', 'qisutu-smart-multiselect-chevron', '⌄');
            Chevron.setAttribute('aria-hidden', 'true');
            Meta.appendChild(CountText);
            Meta.appendChild(Chevron);
            Trigger.appendChild(Summary);
            Trigger.appendChild(Meta);
            Widget.appendChild(Trigger);
            Select.insertAdjacentElement('afterend', Widget);
            updateTrigger(Select, Trigger);

            Trigger.addEventListener('click', function () {
                openDialog(Select, Trigger);
            });
            Select.addEventListener('change', function () {
                updateTrigger(Select, Trigger);
            });
        });

        SearchInput.addEventListener('input', renderList);

        SelectAllButton.addEventListener('click', function () {
            if (!Active) {
                return;
            }
            filteredOptions().forEach(function (Option) {
                Active.draft.add(Option.value);
            });
            renderList();
        });

        ClearButton.addEventListener('click', function () {
            if (!Active) {
                return;
            }
            Active.draft.clear();
            renderList();
        });

        ApplyButton.addEventListener('click', function () {
            if (!Active) {
                return;
            }
            var Select = Active.select;
            var Trigger = Active.trigger;
            multiSelectOptions(Select).forEach(function (Option) {
                Option.selected = Active.draft.has(Option.value);
            });
            Select.dispatchEvent(new Event('change', { bubbles: true }));
            updateTrigger(Select, Trigger);
            closeDialog();
        });

        CloseButton.addEventListener('click', function () { closeDialog(); });
        CancelButton.addEventListener('click', function () { closeDialog(); });
        Overlay.addEventListener('click', function (Event) {
            if (Event.target === Overlay) {
                closeDialog();
            }
        });
        document.addEventListener('keydown', function (Event) {
            if (Event.key === 'Escape' && !Overlay.hidden) {
                Event.preventDefault();
                closeDialog();
            }
        });
    }

    document.addEventListener('DOMContentLoaded', function () {
        var Schedule = document.querySelector('[data-qisutu-schedule-type]');
        if (Schedule) {
            Schedule.addEventListener('change', scheduleFieldsUpdate);
            scheduleFieldsUpdate();
        }

        document.querySelectorAll('[data-qisutu-action-mode]').forEach(function (Select) {
            Select.addEventListener('change', function () { actionModeUpdate(Select); });
            actionModeUpdate(Select);
        });

        document.querySelectorAll('[data-qisutu-automation-preview]').forEach(previewSubmit);

        var AgentNotifyMode = document.querySelector('[data-qisutu-agent-notify-mode]');
        if (AgentNotifyMode) {
            AgentNotifyMode.addEventListener('change', agentNotificationUpdate);
            agentNotificationUpdate();
        }

        var DeleteCheckbox = document.querySelector('input[name="ActionDeleteTickets"]');
        var DeleteInput = document.querySelector('input[name="ActionDeleteConfirmText"]');
        if (DeleteCheckbox && DeleteInput) {
            var updateDelete = function () {
                DeleteInput.required = DeleteCheckbox.checked;
            };
            DeleteCheckbox.addEventListener('change', updateDelete);
            updateDelete();
        }

        var AutomationForm = document.querySelector('.qisutu-automation-form');
        if (AutomationForm) {
            smartMultiSelectInit(AutomationForm);
        }
    });
}());
