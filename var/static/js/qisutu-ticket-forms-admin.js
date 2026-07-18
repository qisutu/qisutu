/* Qisutu - Open Source Ticket System; SPDX-License-Identifier: AGPL-3.0-or-later */
(function () {
    'use strict';

    function OptionTextParse(Line) {
        var Separator = Line.indexOf('|');

        if (Separator < 0) {
            return {
                Key: '',
                Value: Line.trim(),
                ExplicitKey: false
            };
        }

        return {
            Key: Line.substring(0, Separator).trim(),
            Value: Line.substring(Separator + 1).trim(),
            ExplicitKey: true
        };
    }

    function OptionRowsSync(Options) {
        var Input = Options.querySelector('[data-qisutu-ticket-form-options-input]');
        var Rows = Options.querySelectorAll('[data-qisutu-ticket-form-option-row]');
        var Lines = [];

        if (!Input) {
            return;
        }

        Rows.forEach(function (Row) {
            var ValueInput = Row.querySelector('[data-qisutu-ticket-form-option-value]');
            var Value = ValueInput ? ValueInput.value.trim() : '';
            var Key = Row.dataset.optionKey || '';

            if (!Value) {
                return;
            }

            if (Row.dataset.optionExplicitKey === '1' && Key) {
                Lines.push(Key + '|' + Value);
            }
            else {
                Lines.push(Value);
            }
        });

        Input.value = Lines.join('\n');
    }

    function OptionRowAdd(Options, Line, FocusInput) {
        var List = Options.querySelector('[data-qisutu-ticket-form-option-list]');
        var Parsed = OptionTextParse(Line || '');
        var Row;
        var ValueInput;
        var RemoveButton;

        if (!List) {
            return;
        }

        Row = document.createElement('div');
        Row.className = 'qisutu-ticket-form-option-row';
        Row.dataset.qisutuTicketFormOptionRow = '1';
        Row.dataset.optionKey = Parsed.Key;
        Row.dataset.optionExplicitKey = Parsed.ExplicitKey ? '1' : '0';

        ValueInput = document.createElement('input');
        ValueInput.type = 'text';
        ValueInput.className = 'qisutu-ticket-form-option-value';
        ValueInput.value = Parsed.Value;
        ValueInput.placeholder = List.dataset.optionPlaceholder || '';
        ValueInput.setAttribute('aria-label', List.dataset.optionPlaceholder || 'Option');
        ValueInput.dataset.qisutuTicketFormOptionValue = '1';

        RemoveButton = document.createElement('button');
        RemoveButton.type = 'button';
        RemoveButton.className = 'qisutu-button qisutu-button-danger qisutu-ticket-form-option-remove';
        RemoveButton.textContent = List.dataset.removeLabel || 'Remove';
        RemoveButton.dataset.qisutuTicketFormOptionRemove = '1';

        Row.appendChild(ValueInput);
        Row.appendChild(RemoveButton);
        List.appendChild(Row);

        if (FocusInput) {
            ValueInput.focus();
        }
    }

    function OptionRowsInitialize(Options) {
        var Input = Options.querySelector('[data-qisutu-ticket-form-options-input]');
        var Lines;

        if (!Input || Options.dataset.optionRowsInitialized === '1') {
            return;
        }

        Options.dataset.optionRowsInitialized = '1';
        Lines = Input.value.split(/\r?\n/).filter(function (Line) {
            return Line.trim() !== '';
        });

        Lines.forEach(function (Line) {
            OptionRowAdd(Options, Line, false);
        });

        if (!Lines.length) {
            OptionRowAdd(Options, '', false);
        }
    }

    function SelectionOptionsUpdate(Select) {
        var Form = Select.closest('form');
        var Options = Form ? Form.querySelector('[data-qisutu-ticket-form-options]') : null;
        var IsSelection = Select.value === 'dropdown' || Select.value === 'multiselect';

        if (!Options) {
            return;
        }

        OptionRowsInitialize(Options);
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
            OptionRowAdd(Options, '', true);
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
            OptionRowAdd(Options, '', true);
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
