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

    function OptionDescriptors(Options) {
        var Rows = Options.querySelectorAll('[data-qisutu-ticket-form-option-row]');
        var Descriptors = [];

        Rows.forEach(function (Row) {
            var ValueInput = Row.querySelector('[data-qisutu-ticket-form-option-value]');
            var KeyInput = Row.querySelector('[data-qisutu-ticket-form-option-key]');
            var Value = ValueInput ? ValueInput.value.trim() : '';
            var Index = Row.dataset.optionIndex || '';

            if (Row.dataset.optionNew === '1' && KeyInput) {
                KeyInput.value = Value;
            }
            if (!Value || !Index) {
                return;
            }

            Descriptors.push({ Index: Index, Label: Value });
        });

        return Descriptors;
    }

    function OptionTranslationsSync(Options) {
        var Form = Options.closest('form');
        var FieldType = Form ? Form.querySelector('[data-qisutu-ticket-form-field-type]') : null;
        var IsSelection = FieldType && (FieldType.value === 'dropdown' || FieldType.value === 'multiselect');
        var Descriptors = OptionDescriptors(Options);

        if (!Form) {
            return;
        }

        Form.querySelectorAll('[data-qisutu-ticket-form-option-translation-fields]').forEach(function (Container) {
            var Language = Container.dataset.language || '';
            var Rows = Container.querySelector('[data-qisutu-ticket-form-option-translation-rows]');
            var Existing = {};

            if (!Language || !Rows) {
                return;
            }

            Rows.querySelectorAll('[data-qisutu-ticket-form-option-translation-row]').forEach(function (Row) {
                var Index = Row.dataset.optionIndex || '';
                var Input = Row.querySelector('[data-qisutu-ticket-form-option-translation-value]');
                if (Index && Input) {
                    Existing[Index] = Input.value || '';
                }
            });

            Rows.replaceChildren();
            Descriptors.forEach(function (Descriptor) {
                var Row = document.createElement('div');
                var Label = document.createElement('label');
                var Input = document.createElement('input');

                Row.className = 'qisutu-dynamic-option-translation-row';
                Row.dataset.qisutuTicketFormOptionTranslationRow = '1';
                Row.dataset.optionIndex = Descriptor.Index;
                Label.textContent = Descriptor.Label;
                Label.dataset.qisutuTicketFormOptionTranslationLabel = '1';
                Input.type = 'text';
                Input.name = 'OptionTranslation_' + Language + '_' + Descriptor.Index;
                Input.maxLength = 255;
                Input.value = Existing[Descriptor.Index] || '';
                Input.dataset.qisutuTicketFormOptionTranslationValue = '1';
                Row.appendChild(Label);
                Row.appendChild(Input);
                Rows.appendChild(Row);
            });

            Container.classList.toggle('qisutu-hidden', !IsSelection || !Descriptors.length);
        });
    }

    function OptionRowsSync(Options) {
        OptionDescriptors(Options);
        OptionTranslationsSync(Options);
    }

    function OptionRowAdd(Options, FocusInput) {
        var List = Options.querySelector('[data-qisutu-ticket-form-option-list]');
        var Count = Options.querySelector('[data-qisutu-ticket-form-option-count]');
        var Template = document.getElementById('qisutu-ticket-form-option-row-template');
        var Index;
        var Fragment;
        var Row;
        var KeyInput;
        var ValueInput;
        var RemoveButton;

        if (!List || !Count || !Template) {
            return;
        }

        Index = parseInt(Count.value || '0', 10) + 1;
        Fragment = Template.content.cloneNode(true);
        Row = Fragment.querySelector('[data-qisutu-ticket-form-option-row]');
        KeyInput = Fragment.querySelector('[data-qisutu-ticket-form-option-key]');
        ValueInput = Fragment.querySelector('[data-qisutu-ticket-form-option-value]');
        RemoveButton = Fragment.querySelector('[data-qisutu-ticket-form-option-remove]');
        Row.dataset.optionIndex = String(Index);
        Row.dataset.optionNew = '1';
        KeyInput.name = 'OptionKey_' + Index;
        ValueInput.name = 'OptionValue_' + Index;
        ValueInput.placeholder = List.dataset.optionPlaceholder || '';
        ValueInput.setAttribute('aria-label', List.dataset.optionPlaceholder || 'Option');
        RemoveButton.textContent = List.dataset.removeLabel || 'Remove';
        Count.value = String(Index);
        List.appendChild(Fragment);
        OptionRowsSync(Options);

        if (FocusInput) {
            ValueInput.focus();
        }
    }

    function SelectionOptionsUpdate(Select) {
        var Form = Select.closest('form');
        var Options = Form ? Form.querySelector('[data-qisutu-ticket-form-options]') : null;
        var IsSelection = Select.value === 'dropdown' || Select.value === 'multiselect';

        if (!Options) {
            return;
        }

        Options.classList.toggle('qisutu-hidden', !IsSelection);
        Options.querySelectorAll('[data-qisutu-ticket-form-option-value]').forEach(function (Input) {
            Input.required = IsSelection;
        });
        OptionRowsSync(Options);
    }

    function CustomerAssignmentInitialize(Root) {
        var Form = Root.closest('form');
        var Overlay = Root.querySelector('[data-qisutu-customer-assignment-overlay]');
        var OpenButton = Root.querySelector('[data-qisutu-customer-assignment-open]');
        var CancelButtons = Root.querySelectorAll('[data-qisutu-customer-assignment-cancel]');
        var ApplyButton = Root.querySelector('[data-qisutu-customer-assignment-apply]');
        var SearchInput = Root.querySelector('[data-qisutu-customer-assignment-search]');
        var Results = Root.querySelector('[data-qisutu-customer-assignment-results]');
        var Status = Root.querySelector('[data-qisutu-customer-assignment-status]');
        var MoreButton = Root.querySelector('[data-qisutu-customer-assignment-more]');
        var HiddenInputs = Root.querySelector('[data-qisutu-customer-selected-inputs]');
        var SelectedCount = Root.querySelector('[data-qisutu-customer-selected-count]');
        var WorkingCount = Root.querySelector('[data-qisutu-customer-working-count]');
        var AllCustomers = Form ? Form.querySelector('[data-qisutu-customer-all]') : null;
        var Selected = new Map();
        var Working = new Map();
        var Offset = 0;
        var CurrentQuery = '';
        var Loading = false;
        var SearchTimer;
        var SearchController;

        if (!Form || !Overlay || !OpenButton || !ApplyButton || !SearchInput || !Results || !HiddenInputs) {
            return;
        }

        HiddenInputs.querySelectorAll('[data-qisutu-customer-selected]').forEach(function (Input) {
            Selected.set(String(Input.dataset.customerId || ''), Input.dataset.customerLabel || '');
        });

        function CountUpdate() {
            if (SelectedCount) {
                SelectedCount.textContent = String(Selected.size);
            }
            if (WorkingCount) {
                WorkingCount.textContent = String(Working.size);
            }
        }

        function AllCustomersUpdate() {
            var IsAll = Boolean(AllCustomers && AllCustomers.checked);
            OpenButton.disabled = IsAll;
            Root.classList.toggle('qisutu-customer-assignment-all', IsAll);
        }

        function HiddenInputsRebuild() {
            HiddenInputs.replaceChildren();
            Array.from(Selected.entries()).sort(function (A, B) {
                return A[1].localeCompare(B[1]);
            }).forEach(function (Entry) {
                var Input = document.createElement('input');
                Input.type = 'hidden';
                Input.name = 'Customer_' + Entry[0];
                Input.value = '1';
                Input.dataset.qisutuCustomerSelected = '1';
                Input.dataset.customerId = Entry[0];
                Input.dataset.customerLabel = Entry[1];
                HiddenInputs.appendChild(Input);
            });
        }

        function ResultCheckboxCreate(Item) {
            var ID = String(Item.id || '');
            var Label = document.createElement('label');
            var Checkbox = document.createElement('input');
            var Text = document.createElement('span');
            var Name = document.createElement('strong');
            var Number = document.createElement('small');
            var DisplayLabel = (Item.name || '') + ' (' + (Item.customer_number || '') + ')';

            Label.className = 'qisutu-customer-assignment-item';
            Checkbox.type = 'checkbox';
            Checkbox.checked = Working.has(ID);
            Checkbox.dataset.customerId = ID;
            Checkbox.dataset.customerLabel = DisplayLabel;
            Name.textContent = Item.name || '-';
            Number.textContent = Item.customer_number || '-';
            Text.appendChild(Name);
            Text.appendChild(Number);
            Label.appendChild(Checkbox);
            Label.appendChild(Text);
            return Label;
        }

        function SearchLoad(Reset) {
            var URL = Root.dataset.searchUrl || '';
            var Controller;

            if (!URL) {
                return;
            }

            if (Reset) {
                if (SearchController) {
                    SearchController.abort();
                }
                Loading = false;
                Offset = 0;
                Results.replaceChildren();
            }

            if (Loading) {
                return;
            }

            Loading = true;
            Status.textContent = Root.dataset.loadingText || '';
            MoreButton.hidden = true;
            Controller = new AbortController();
            SearchController = Controller;

            fetch(URL + '&Query=' + encodeURIComponent(CurrentQuery) + '&Offset=' + Offset, {
                credentials: 'same-origin',
                headers: { 'Accept': 'application/json' },
                signal: Controller.signal
            }).then(function (Response) {
                if (!Response.ok) {
                    throw new Error('Customer search failed');
                }
                return Response.json();
            }).then(function (Data) {
                var Items = Array.isArray(Data.items) ? Data.items : [];
                Items.forEach(function (Item) {
                    Results.appendChild(ResultCheckboxCreate(Item));
                });
                Offset += Items.length;
                Status.textContent = !Results.children.length ? (Root.dataset.emptyText || '') : '';
                MoreButton.hidden = !Data.has_more;
            }).catch(function (Error) {
                if (Error.name !== 'AbortError') {
                    Status.textContent = Root.dataset.errorText || '';
                }
            }).finally(function () {
                if (SearchController === Controller) {
                    Loading = false;
                }
            });
        }

        function OverlayClose() {
            Overlay.hidden = true;
            Overlay.setAttribute('aria-hidden', 'true');
            document.body.classList.remove('qisutu-overlay-open');
            if (SearchController) {
                SearchController.abort();
            }
            OpenButton.focus();
        }

        function OverlayCancel() {
            Working = new Map(Selected);
            CountUpdate();
            OverlayClose();
        }

        OpenButton.addEventListener('click', function () {
            Working = new Map(Selected);
            CountUpdate();
            CurrentQuery = '';
            SearchInput.value = '';
            Overlay.hidden = false;
            Overlay.setAttribute('aria-hidden', 'false');
            document.body.classList.add('qisutu-overlay-open');
            SearchLoad(true);
            SearchInput.focus();
        });

        CancelButtons.forEach(function (Button) {
            Button.addEventListener('click', OverlayCancel);
        });

        ApplyButton.addEventListener('click', function () {
            Selected = new Map(Working);
            HiddenInputsRebuild();
            CountUpdate();
            OverlayClose();
        });

        SearchInput.addEventListener('input', function () {
            window.clearTimeout(SearchTimer);
            SearchTimer = window.setTimeout(function () {
                CurrentQuery = SearchInput.value.trim();
                SearchLoad(true);
            }, 250);
        });

        Results.addEventListener('change', function (Event) {
            var Checkbox = Event.target.closest('input[type="checkbox"][data-customer-id]');
            if (!Checkbox) {
                return;
            }
            if (Checkbox.checked) {
                Working.set(Checkbox.dataset.customerId, Checkbox.dataset.customerLabel || '');
            }
            else {
                Working.delete(Checkbox.dataset.customerId);
            }
            CountUpdate();
        });

        MoreButton.addEventListener('click', function () {
            SearchLoad(false);
        });

        Overlay.addEventListener('click', function (Event) {
            if (Event.target === Overlay) {
                OverlayCancel();
            }
        });

        document.addEventListener('keydown', function (Event) {
            if (Event.key === 'Escape' && !Overlay.hidden) {
                OverlayCancel();
            }
        });

        if (AllCustomers) {
            AllCustomers.addEventListener('change', AllCustomersUpdate);
        }
        CountUpdate();
        AllCustomersUpdate();
    }

    document.querySelectorAll('[data-qisutu-ticket-form-field-type]').forEach(function (Select) {
        SelectionOptionsUpdate(Select);
    });

    document.querySelectorAll('[data-qisutu-customer-assignment]').forEach(function (Root) {
        CustomerAssignmentInitialize(Root);
    });

    document.addEventListener('change', function (Event) {
        if (Event.target.matches('[data-qisutu-ticket-form-field-type]')) {
            SelectionOptionsUpdate(Event.target);
        }
    });

    document.addEventListener('click', function (Event) {
        var AddButton = Event.target.closest('[data-qisutu-ticket-form-option-add]');
        var RemoveButton = Event.target.closest('[data-qisutu-ticket-form-option-remove]');
        var Options;
        var List;

        if (AddButton) {
            Options = AddButton.closest('[data-qisutu-ticket-form-options]');
            OptionRowAdd(Options, true);
            SelectionOptionsUpdate(Options.closest('form').querySelector('[data-qisutu-ticket-form-field-type]'));
            return;
        }

        if (!RemoveButton) {
            return;
        }

        Options = RemoveButton.closest('[data-qisutu-ticket-form-options]');
        RemoveButton.closest('[data-qisutu-ticket-form-option-row]').remove();
        List = Options.querySelector('[data-qisutu-ticket-form-option-list]');
        if (!List.querySelector('[data-qisutu-ticket-form-option-row]')) {
            OptionRowAdd(Options, true);
        }
        SelectionOptionsUpdate(Options.closest('form').querySelector('[data-qisutu-ticket-form-field-type]'));
    });

    document.addEventListener('input', function (Event) {
        var Options;

        if (!Event.target.matches('[data-qisutu-ticket-form-option-value]')) {
            return;
        }

        Options = Event.target.closest('[data-qisutu-ticket-form-options]');
        OptionRowsSync(Options);
    });

    document.addEventListener('submit', function (Event) {
        var Options = Event.target.querySelector('[data-qisutu-ticket-form-options]');
        var Form = Event.target.closest('[data-qisutu-ticket-form-delete]');

        if (Options) {
            OptionRowsSync(Options);
        }

        if (!Form) {
            return;
        }
        var Message = document.documentElement.lang === 'de'
            ? 'Dieses inaktive Formular endgültig löschen?'
            : 'Permanently delete this inactive form?';
        if (!window.confirm(Message)) {
            Event.preventDefault();
        }
    });
}());
