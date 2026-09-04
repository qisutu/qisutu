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

    var AgentRefreshMilliseconds = 10 * 60 * 1000;
    var UnreadRefreshMilliseconds = 30 * 1000;
    var MessageRefreshMilliseconds = 4 * 1000;
    var TicketPresenceRefreshMilliseconds = 30 * 1000;

    function postForm(URL, Values) {
        var Body = new URLSearchParams();

        Object.keys(Values || {}).forEach(function (Key) {
            if (Values[Key] !== undefined && Values[Key] !== null) {
                Body.append(Key, String(Values[Key]));
            }
        });

        return window.fetch(URL, {
            method: 'POST',
            credentials: 'same-origin',
            headers: {
                'Content-Type': 'application/x-www-form-urlencoded; charset=UTF-8',
                'X-Requested-With': 'XMLHttpRequest'
            },
            body: Body.toString()
        }).then(function (Response) {
            if (!Response.ok) {
                throw new Error('Request failed');
            }
            return Response.json();
        });
    }

    function getJSON(URL) {
        return window.fetch(URL, {
            credentials: 'same-origin',
            headers: { 'X-Requested-With': 'XMLHttpRequest' }
        }).then(function (Response) {
            if (!Response.ok) {
                throw new Error('Request failed');
            }
            return Response.json();
        });
    }

    function clientIDCreate() {
        var Bytes = new Uint8Array(18);
        var Value = '';
        var Index;

        if (window.crypto && window.crypto.getRandomValues) {
            window.crypto.getRandomValues(Bytes);
            for (Index = 0; Index < Bytes.length; Index += 1) {
                Value += Bytes[Index].toString(16).padStart(2, '0');
            }
            return Value;
        }

        return 'qisutu' + Date.now().toString(36) + Math.random().toString(36).slice(2, 18);
    }

    function timeLabel(Value) {
        if (!Value) {
            return '';
        }
        if (/^\d{4}-\d{2}-\d{2} \d{2}:\d{2}/.test(Value)) {
            return Value.slice(11, 16);
        }
        return Value;
    }

    document.addEventListener('DOMContentLoaded', function () {
        var Root = document.getElementById('QisutuInternalChat');
        var Launcher = document.querySelector('[data-qisutu-internal-chat-open]');

        if (!Root || !Launcher) {
            return;
        }

        var Drawer = Root.querySelector('[data-qisutu-internal-chat-drawer]');
        var Backdrop = Root.querySelector('[data-qisutu-internal-chat-backdrop]');
        var Close = Root.querySelector('[data-qisutu-internal-chat-close]');
        var Badge = Launcher.querySelector('[data-qisutu-internal-chat-badge]');
        var AgentList = Root.querySelector('[data-qisutu-internal-chat-agent-list]');
        var AgentFilter = Root.querySelector('[data-qisutu-internal-chat-agent-filter]');
        var ConversationName = Root.querySelector('[data-qisutu-internal-chat-conversation-name]');
        var ConversationState = Root.querySelector('[data-qisutu-internal-chat-conversation-state]');
        var DeleteConversation = Root.querySelector('[data-qisutu-internal-chat-delete]');
        var Empty = Root.querySelector('[data-qisutu-internal-chat-empty]');
        var Messages = Root.querySelector('[data-qisutu-internal-chat-messages]');
        var Form = Root.querySelector('[data-qisutu-internal-chat-form]');
        var MessageInput = Root.querySelector('[data-qisutu-internal-chat-message]');
        var TicketContext = Root.querySelector('[data-qisutu-internal-chat-ticket-context]');
        var TicketContextText = Root.querySelector('[data-qisutu-internal-chat-ticket-context-text]');
        var Transfer = Root.querySelector('[data-qisutu-internal-chat-transfer]');
        var TransferStatus = Root.querySelector('[data-qisutu-internal-chat-transfer-status]');
        var CSRFToken = Root.getAttribute('data-csrf-token') || '';
        var CurrentTicketID = Number(Root.getAttribute('data-current-ticket-id') || 0);
        var CurrentTicketNumber = Root.getAttribute('data-current-ticket-number') || '';
        var CurrentTicketTitle = Root.getAttribute('data-current-ticket-title') || '';
        var Agents = [];
        var AgentByID = {};
        var SelectedAgentID = 0;
        var PendingAgentID = 0;
        var LastMessageID = 0;
        var LoadingMessages = false;
        var MessageTimer = null;
        var InviteMode = false;

        function sidebarActionsSynchronize() {
            var Sidebar = document.getElementById('QisutuSidebar');
            var Actions = Sidebar
                ? Sidebar.querySelector('[data-qisutu-sidebar-actions]')
                : null;
            var KimActions = document.querySelector('[data-kim-quick-actions]')
                || document.querySelector('.qisutu-kim-quick-actions');
            var TeamsLauncher = document.querySelector('[data-ms365-launcher-open]');
            var TeamsRoot = TeamsLauncher
                ? TeamsLauncher.closest('.qisutu-ms365-launcher-root')
                : null;
            var TeamsReady = !TeamsRoot || TeamsRoot.dataset.initialized === '1';
            var KimLauncher;

            if (!Sidebar || !Actions) {
                return;
            }

            if (KimActions && !KimActions.closest('.qisutu-nav')) {
                KimLauncher = Array.prototype.slice.call(
                    KimActions.querySelectorAll('button, a')
                ).find(function (Control) {
                    return (Control.textContent || '').trim().toLocaleLowerCase() === 'kim';
                });

                if (!KimActions.contains(Launcher)) {
                    KimActions.insertBefore(Launcher, KimLauncher || KimActions.firstChild);
                }
                if (TeamsLauncher && TeamsReady && !KimActions.contains(TeamsLauncher)) {
                    KimActions.appendChild(TeamsLauncher);
                }
            }
            else {
                if (!Actions.contains(Launcher)) {
                    Actions.insertBefore(Launcher, Actions.firstChild);
                }
                if (TeamsLauncher && TeamsReady && !Actions.contains(TeamsLauncher)) {
                    Actions.appendChild(TeamsLauncher);
                }
            }

            if (TeamsRoot && TeamsReady && (Actions.contains(TeamsLauncher)
                || (KimActions && KimActions.contains(TeamsLauncher)))) {
                TeamsRoot.classList.remove('is-standalone');
                TeamsRoot.classList.add('is-integrated');
            }
            Actions.hidden = !Actions.querySelector('button, a');
        }

        (function launcherPositionInitialize() {
            var Observer;

            sidebarActionsSynchronize();
            if (!document.body || !window.MutationObserver) {
                return;
            }

            Observer = new MutationObserver(sidebarActionsSynchronize);
            Observer.observe(document.body, { childList: true, subtree: true });
            window.setTimeout(function () {
                Observer.disconnect();
            }, 10000);
        }());

        function text(Key, Fallback) {
            return Root.getAttribute('data-text-' + Key) || Fallback || '';
        }

        function badgeUpdate(Count) {
            Count = Number(Count || 0);
            Badge.hidden = Count < 1;
            Badge.textContent = Count > 99 ? '99+' : String(Count);
        }

        function isOpen() {
            return Drawer && !Drawer.hidden;
        }

        function drawerClose() {
            Drawer.hidden = true;
            Backdrop.hidden = true;
            Launcher.setAttribute('aria-expanded', 'false');
            document.body.classList.remove('qisutu-internal-chat-open');
            if (MessageTimer) {
                window.clearInterval(MessageTimer);
                MessageTimer = null;
            }
        }

        function drawerOpen() {
            Drawer.hidden = false;
            Backdrop.hidden = false;
            Launcher.setAttribute('aria-expanded', 'true');
            document.body.classList.add('qisutu-internal-chat-open');
            loadAgents();
            if (SelectedAgentID) {
                loadMessages(false);
            }
            if (!MessageTimer) {
                MessageTimer = window.setInterval(function () {
                    if (isOpen() && SelectedAgentID) {
                        loadMessages(true);
                    }
                }, MessageRefreshMilliseconds);
            }
        }

        function agentButtonCreate(Agent) {
            var Button = document.createElement('button');
            var Avatar = document.createElement('span');
            var Dot = document.createElement('span');
            var TextWrap = document.createElement('span');
            var Name = document.createElement('span');
            var State = document.createElement('span');
            var Unread = document.createElement('span');

            Button.type = 'button';
            Button.className = 'qisutu-internal-chat-agent';
            Button.setAttribute('data-agent-id', String(Agent.id));
            Button.classList.toggle('qisutu-internal-chat-agent-active', Number(Agent.id) === SelectedAgentID);

            Avatar.className = 'qisutu-internal-chat-agent-avatar';
            Avatar.textContent = Agent.initials || '?';
            Dot.className = 'qisutu-internal-chat-online-dot' + (Agent.is_online ? ' qisutu-internal-chat-online-dot-online' : '');
            Avatar.appendChild(Dot);

            Name.className = 'qisutu-internal-chat-agent-name';
            Name.textContent = Agent.name || Agent.login || '-';
            State.className = 'qisutu-internal-chat-agent-state';
            State.textContent = Agent.is_online ? text('online', 'Online') : text('offline', 'Offline');
            TextWrap.appendChild(Name);
            TextWrap.appendChild(document.createElement('br'));
            TextWrap.appendChild(State);

            Unread.className = 'qisutu-internal-chat-agent-unread';
            Unread.hidden = !Number(Agent.unread_count || 0);
            Unread.textContent = Number(Agent.unread_count || 0) > 99 ? '99+' : String(Agent.unread_count || '');

            Button.appendChild(Avatar);
            Button.appendChild(TextWrap);
            Button.appendChild(Unread);
            Button.addEventListener('click', function () {
                agentSelect(Number(Agent.id));
            });

            return Button;
        }

        function agentsRender() {
            var Query = (AgentFilter.value || '').toLocaleLowerCase();
            var VisibleCount = 0;
            AgentList.innerHTML = '';

            Agents.forEach(function (Agent) {
                var Haystack = ((Agent.name || '') + ' ' + (Agent.login || '')).toLocaleLowerCase();
                if (InviteMode && !Agent.is_online) {
                    return;
                }
                if (Query && Haystack.indexOf(Query) === -1) {
                    return;
                }
                VisibleCount += 1;
                AgentList.appendChild(agentButtonCreate(Agent));
            });

            if (InviteMode && !VisibleCount) {
                AgentList.textContent = text('no-online-agents', 'No other agent is currently online.');
            }
        }

        function selectedAgentHeaderUpdate() {
            var Agent = AgentByID[SelectedAgentID];
            DeleteConversation.hidden = !Agent;
            if (!Agent) {
                ConversationName.textContent = text('select-agent', 'Select an agent');
                ConversationState.textContent = '';
                return;
            }
            ConversationName.textContent = Agent.name || Agent.login || '-';
            ConversationState.textContent = Agent.is_online ? text('online', 'Online') : text('offline', 'Offline');
        }

        function loadAgents() {
            getJSON(Root.getAttribute('data-state-url')).then(function (Data) {
                if (!Data.success) {
                    throw new Error(Data.message || 'Request failed');
                }
                Agents = Array.isArray(Data.agents) ? Data.agents : [];
                AgentByID = {};
                Agents.forEach(function (Agent) {
                    AgentByID[Number(Agent.id)] = Agent;
                });
                badgeUpdate(Data.unread_count);
                agentsRender();
                selectedAgentHeaderUpdate();
                if (PendingAgentID && AgentByID[PendingAgentID]) {
                    var AgentID = PendingAgentID;
                    PendingAgentID = 0;
                    agentSelect(AgentID);
                }
            }).catch(function () {
                AgentList.textContent = text('load-error', 'Could not load the internal chat.');
            });
        }

        function loadUnread() {
            getJSON(Root.getAttribute('data-unread-url')).then(function (Data) {
                if (Data.success) {
                    badgeUpdate(Data.unread_count);
                }
            }).catch(function () {
                // The next regular check will retry silently.
            });
        }

        function agentSelect(AgentID) {
            var SendTicketInvitation = InviteMode;

            if (!AgentByID[AgentID]) {
                PendingAgentID = AgentID;
                loadAgents();
                return;
            }

            PendingAgentID = 0;
            InviteMode = false;
            SelectedAgentID = AgentID;
            LastMessageID = 0;
            Messages.innerHTML = '';
            Empty.hidden = true;
            Messages.hidden = false;
            Form.hidden = false;
            DeleteConversation.hidden = false;
            MessageInput.disabled = false;
            TransferStatus.textContent = '';
            agentsRender();
            selectedAgentHeaderUpdate();

            if (CurrentTicketID) {
                TicketContext.hidden = false;
                TicketContextText.textContent = (CurrentTicketNumber ? CurrentTicketNumber + ' – ' : '') + CurrentTicketTitle;
                Transfer.disabled = false;
            }
            else {
                TicketContext.hidden = true;
            }

            if (SendTicketInvitation && CurrentTicketID) {
                ticketInvitationSend();
            }
            else {
                loadMessages(false);
            }
            MessageInput.focus();
        }

        function ticketCardCreate(Message) {
            var Card = document.createElement(Message.ticket_id ? 'a' : 'span');
            var Label = document.createElement('small');
            var Title = document.createElement('span');

            Card.className = 'qisutu-internal-chat-ticket-card';
            if (Message.ticket_id) {
                Card.href = 'index.pl?Page=AgentTicketZoom&TicketID=' + encodeURIComponent(Message.ticket_id);
            }
            Label.textContent = Message.message_type === 'ticket_handover'
                ? text('ticket-transferred', 'Ticket transferred')
                : text('ticket-reference', 'Ticket reference');
            Title.textContent = (Message.ticket_number ? Message.ticket_number + ' – ' : '') + (Message.ticket_title || '');
            Card.appendChild(Label);
            Card.appendChild(Title);
            return Card;
        }

        function messageAppend(Message) {
            var Wrap = document.createElement('div');
            var Bubble = document.createElement('div');
            var Meta = document.createElement('div');

            if (Message.message_type === 'conversation_deleted') {
                Messages.innerHTML = '';
                LastMessageID = Number(Message.id || 0);
                return;
            }

            Wrap.className = 'qisutu-internal-chat-message' + (Message.outgoing ? ' qisutu-internal-chat-message-outgoing' : '');
            Bubble.className = 'qisutu-internal-chat-message-bubble';

            if (Message.message_text) {
                Bubble.appendChild(document.createTextNode(Message.message_text));
            }
            if (Message.ticket_number || Message.ticket_title) {
                Bubble.appendChild(ticketCardCreate(Message));
            }
            Meta.className = 'qisutu-internal-chat-message-meta';
            Meta.textContent = (Message.outgoing ? text('you', 'You') : (Message.sender_name || '')) + ' · ' + timeLabel(Message.created_at);

            Wrap.appendChild(Bubble);
            Wrap.appendChild(Meta);
            Messages.appendChild(Wrap);
            LastMessageID = Math.max(LastMessageID, Number(Message.id || 0));
        }

        function loadMessages(Incremental) {
            if (!SelectedAgentID || LoadingMessages) {
                return;
            }
            LoadingMessages = true;

            postForm(Root.getAttribute('data-messages-url'), {
                CSRFToken: CSRFToken,
                PartnerID: SelectedAgentID,
                SinceID: Incremental ? LastMessageID : 0
            }).then(function (Data) {
                if (!Data.success) {
                    throw new Error(Data.message || 'Request failed');
                }
                if (!Incremental) {
                    Messages.innerHTML = '';
                    LastMessageID = 0;
                }
                (Data.messages || []).forEach(messageAppend);
                if (!Incremental || (Data.messages || []).length) {
                    Messages.scrollTop = Messages.scrollHeight;
                }
                badgeUpdate(Data.unread_count);
                if (AgentByID[SelectedAgentID]) {
                    AgentByID[SelectedAgentID].unread_count = 0;
                    agentsRender();
                }
            }).catch(function () {
                TransferStatus.textContent = text('load-error', 'Could not load the internal chat.');
            }).finally(function () {
                LoadingMessages = false;
            });
        }

        function messageSend(Event) {
            Event.preventDefault();
            var Value = (MessageInput.value || '').trim();
            if (!SelectedAgentID || !Value) {
                return;
            }

            MessageInput.disabled = true;
            postForm(Root.getAttribute('data-send-url'), {
                CSRFToken: CSRFToken,
                PartnerID: SelectedAgentID,
                TicketID: CurrentTicketID || '',
                Message: Value
            }).then(function (Data) {
                if (!Data.success) {
                    throw new Error(Data.message || text('send-error', 'The message could not be sent.'));
                }
                MessageInput.value = '';
                loadMessages(true);
            }).catch(function (Error) {
                TransferStatus.textContent = Error.message || text('send-error', 'The message could not be sent.');
            }).finally(function () {
                MessageInput.disabled = false;
                MessageInput.focus();
            });
        }

        function ticketInvitationSend() {
            if (!SelectedAgentID || !CurrentTicketID) {
                return;
            }

            MessageInput.disabled = true;
            TransferStatus.textContent = '';
            postForm(Root.getAttribute('data-send-url'), {
                CSRFToken: CSRFToken,
                PartnerID: SelectedAgentID,
                TicketID: CurrentTicketID,
                Message: text('ticket-invitation', 'Please take a look at this ticket. I have a question about it.')
            }).then(function (Data) {
                if (!Data.success) {
                    throw new Error(Data.message || text('send-error', 'The message could not be sent.'));
                }
                loadMessages(false);
            }).catch(function (Error) {
                TransferStatus.textContent = Error.message || text('send-error', 'The message could not be sent.');
            }).finally(function () {
                MessageInput.disabled = false;
                MessageInput.focus();
            });
        }

        function ticketInvitationStart() {
            InviteMode = true;
            PendingAgentID = 0;
            SelectedAgentID = 0;
            LastMessageID = 0;
            AgentFilter.value = '';
            Messages.innerHTML = '';
            Messages.hidden = true;
            Empty.hidden = false;
            Form.hidden = true;
            DeleteConversation.hidden = true;
            TicketContext.hidden = true;
            TransferStatus.textContent = '';
            selectedAgentHeaderUpdate();
            agentsRender();
            drawerOpen();
        }

        function conversationDelete() {
            var Agent = AgentByID[SelectedAgentID];
            var Confirmation;

            if (!Agent || !SelectedAgentID) {
                return;
            }

            Confirmation = text('delete-confirm', 'Delete the complete chat with {agent}?').replace('{agent}', Agent.name || Agent.login || '-');
            if (!window.confirm(Confirmation)) {
                return;
            }

            DeleteConversation.disabled = true;
            TransferStatus.textContent = '';
            postForm(Root.getAttribute('data-delete-url'), {
                CSRFToken: CSRFToken,
                PartnerID: SelectedAgentID
            }).then(function (Data) {
                if (!Data.success) {
                    throw new Error(Data.message || text('delete-error', 'The chat could not be deleted.'));
                }
                Messages.innerHTML = '';
                LastMessageID = Number(Data.message_id || 0);
                TransferStatus.textContent = Data.message || '';
                loadAgents();
            }).catch(function (Error) {
                TransferStatus.textContent = Error.message || text('delete-error', 'The chat could not be deleted.');
            }).finally(function () {
                DeleteConversation.disabled = false;
            });
        }

        function ticketTransfer() {
            var Agent = AgentByID[SelectedAgentID];
            var Confirmation;
            if (!Agent || !CurrentTicketID) {
                return;
            }

            Confirmation = text('transfer-confirm', 'Transfer this ticket to {agent}?').replace('{agent}', Agent.name || Agent.login || '-');
            if (!window.confirm(Confirmation)) {
                return;
            }

            Transfer.disabled = true;
            TransferStatus.textContent = '';
            postForm(Root.getAttribute('data-transfer-url'), {
                CSRFToken: CSRFToken,
                PartnerID: SelectedAgentID,
                TicketID: CurrentTicketID
            }).then(function (Data) {
                if (!Data.success) {
                    throw new Error(Data.message || text('transfer-error', 'The ticket could not be transferred.'));
                }
                TransferStatus.textContent = Data.message || text('transfer-success', 'The ticket was transferred.');
                loadMessages(true);
            }).catch(function (Error) {
                TransferStatus.textContent = Error.message || text('transfer-error', 'The ticket could not be transferred.');
            }).finally(function () {
                Transfer.disabled = false;
            });
        }

        Launcher.addEventListener('click', function () {
            if (isOpen()) {
                drawerClose();
            }
            else {
                InviteMode = false;
                agentsRender();
                drawerOpen();
            }
        });
        Close.addEventListener('click', drawerClose);
        Backdrop.addEventListener('click', drawerClose);
        AgentFilter.addEventListener('input', agentsRender);
        Form.addEventListener('submit', messageSend);
        DeleteConversation.addEventListener('click', conversationDelete);
        Transfer.addEventListener('click', ticketTransfer);
        MessageInput.addEventListener('keydown', function (Event) {
            if (Event.key === 'Enter' && !Event.shiftKey) {
                Event.preventDefault();
                Form.requestSubmit();
            }
        });

        document.addEventListener('click', function (Event) {
            var Button = Event.target.closest('[data-qisutu-chat-agent]');
            var AgentID;
            if (!Button) {
                return;
            }
            AgentID = Number(Button.getAttribute('data-qisutu-chat-agent') || 0);
            if (!AgentID) {
                return;
            }
            PendingAgentID = AgentID;
            drawerOpen();
            if (AgentByID[AgentID]) {
                agentSelect(AgentID);
            }
        });

        document.addEventListener('keydown', function (Event) {
            if (Event.key === 'Escape' && isOpen()) {
                drawerClose();
            }
        });

        loadAgents();
        window.setInterval(loadAgents, AgentRefreshMilliseconds);
        window.setInterval(loadUnread, UnreadRefreshMilliseconds);

        (function initTicketPresence() {
            var Presence = document.querySelector('[data-qisutu-ticket-presence]');
            if (!Presence) {
                return;
            }

            var PresenceList = Presence.querySelector('[data-qisutu-ticket-presence-list]');
            var TicketID = Number(Presence.getAttribute('data-ticket-id') || 0);
            var ClientID = clientIDCreate();
            var PresenceURL = Presence.getAttribute('data-presence-url') || '';
            var LeaveURL = Presence.getAttribute('data-leave-url') || '';

            function presenceRender(AgentRows) {
                PresenceList.innerHTML = '';
                if (!AgentRows.length) {
                    var EmptyState = document.createElement('span');
                    var Invite = document.createElement('button');
                    EmptyState.className = 'qisutu-ticket-presence-empty';
                    EmptyState.textContent = text('ticket-alone', 'No other agent currently has this ticket open.');
                    Invite.type = 'button';
                    Invite.className = 'qisutu-ticket-presence-invite';
                    Invite.textContent = text('invite-colleague', 'Invite a colleague');
                    Invite.addEventListener('click', ticketInvitationStart);
                    PresenceList.appendChild(EmptyState);
                    PresenceList.appendChild(Invite);
                    return;
                }

                AgentRows.forEach(function (Agent) {
                    var Item = document.createElement('span');
                    var Avatar = document.createElement('span');
                    var Name = document.createElement('span');
                    var Chat = document.createElement('button');

                    Item.className = 'qisutu-ticket-presence-agent';
                    Avatar.className = 'qisutu-ticket-presence-avatar';
                    Avatar.textContent = Agent.initials || '?';
                    Name.className = 'qisutu-ticket-presence-agent-name';
                    Name.textContent = Agent.name || '-';
                    Chat.type = 'button';
                    Chat.className = 'qisutu-ticket-presence-chat';
                    Chat.textContent = text('address', 'Address');
                    Chat.setAttribute('data-qisutu-chat-agent', String(Agent.id));
                    Chat.setAttribute('aria-label', text('address-agent', 'Address {agent} in chat').replace('{agent}', Agent.name || '-'));

                    Item.appendChild(Avatar);
                    Item.appendChild(Name);
                    Item.appendChild(Chat);
                    PresenceList.appendChild(Item);
                });
            }

            function presenceUpdate() {
                postForm(PresenceURL, {
                    CSRFToken: CSRFToken,
                    TicketID: TicketID,
                    ClientID: ClientID
                }).then(function (Data) {
                    if (Data.success) {
                        presenceRender(Array.isArray(Data.agents) ? Data.agents : []);
                    }
                }).catch(function () {
                    PresenceList.textContent = text('presence-error', 'Ticket presence could not be updated.');
                });
            }

            function presenceLeave() {
                var Body = new URLSearchParams();
                Body.append('CSRFToken', CSRFToken);
                Body.append('TicketID', String(TicketID));
                Body.append('ClientID', ClientID);
                if (navigator.sendBeacon) {
                    navigator.sendBeacon(LeaveURL, Body);
                }
            }

            presenceUpdate();
            window.setInterval(presenceUpdate, TicketPresenceRefreshMilliseconds);
            window.addEventListener('pagehide', presenceLeave);
        }());
    });
}());
