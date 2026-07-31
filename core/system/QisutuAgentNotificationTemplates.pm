# Qisutu - Open Source Ticket System
# Copyright (C) 2026 Franziska Steps
# Qisutu - Kim-KI, https://qisutu.de
#
# This file is part of Qisutu.
#
# Qisutu is free software: you can redistribute it and/or modify
# it under the terms of the GNU Affero General Public License as published by
# the Free Software Foundation, either version 3 of the License, or
# (at your option) any later version.
#
# Qisutu is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the
# GNU Affero General Public License for more details.
#
# You should have received a copy of the GNU Affero General Public License
# along with Qisutu. If not, see <https://www.gnu.org/licenses/>.
#
# SPDX-FileCopyrightText: 2026 Franziska Steps
# SPDX-License-Identifier: AGPL-3.0-or-later

package QisutuAgentNotificationTemplates;

use strict;
use warnings;
use utf8;

my @Languages = (
    { code => 'de',    label => 'Deutsch' },
    { code => 'en',    label => 'English' },
    { code => 'fr',    label => 'Français' },
    { code => 'it',    label => 'Italiano' },
    { code => 'es',    label => 'Español' },
    { code => 'pt-BR', label => 'Português (Brasil)' },
    { code => 'pt-PT', label => 'Português (Portugal)' },
    { code => 'nl',    label => 'Nederlands' },
    { code => 'pl',    label => 'Polski' },
    { code => 'cs',    label => 'Čeština' },
    { code => 'tr',    label => 'Türkçe' },
);

my @TypeOrder = (
    'ticket_new_in_my_queues',
    'customer_reply_in_my_queues',
    'ticket_assigned_to_me',
    'ticket_state_changed',
    'ticket_escalation_reached',
    'ticket_pending_reached',
);

my %Template = (
    de => [
        [ 'ticket_new_in_my_queues', q~Neues Ticket in meinen Queues~, q~Neues Ticket {{Ticket.Number}} in {{Ticket.Queue}}~, q~<p>Hallo {{Agent.FullName}},</p><p>in deiner Queue <strong>{{Ticket.Queue}}</strong> wurde ein neues Ticket erstellt.</p><p><strong>{{Ticket.Number}}</strong> - {{Ticket.Title}}</p><p>{{Ticket.LinkHTML}}</p>~ ],
        [ 'customer_reply_in_my_queues', q~Kundenantwort in Tickets von meinen Queues~, q~Kundenantwort in Ticket {{Ticket.Number}}~, q~<p>Hallo {{Agent.FullName}},</p><p>in deiner Queue <strong>{{Ticket.Queue}}</strong> gibt es eine neue Kundenantwort.</p><p><strong>{{Ticket.Number}}</strong> - {{Ticket.Title}}</p><p>Kunde: {{Customer.Name}}<br>Ansprechpartner: {{CustomerUser.FullName}}</p><p>{{Ticket.LinkHTML}}</p>~ ],
        [ 'ticket_assigned_to_me', q~Ticket wurde mir zugewiesen~, q~Ticket {{Ticket.Number}} wurde dir zugewiesen~, q~<p>Hallo {{Agent.FullName}},</p><p>das Ticket <strong>{{Ticket.Number}}</strong> wurde dir zugewiesen.</p><p>{{Ticket.Title}}</p><p>{{Ticket.LinkHTML}}</p>~ ],
        [ 'ticket_state_changed', q~Ticketstatus wurde geändert~, q~Status geändert: Ticket {{Ticket.Number}}~, q~<p>Hallo {{Agent.FullName}},</p><p>der Status des Tickets <strong>{{Ticket.Number}}</strong> in deiner Queue <strong>{{Ticket.Queue}}</strong> wurde geändert.</p><p>Neuer Status: <strong>{{Ticket.State}}</strong></p><p>{{Ticket.LinkHTML}}</p>~ ],
        [ 'ticket_escalation_reached', q~Bei Eskalation~, q~Eskalation erreicht: Ticket {{Ticket.Number}}~, q~<p>Hallo {{Agent.FullName}},</p><p>das Ticket <strong>{{Ticket.Number}}</strong> in deiner Queue <strong>{{Ticket.Queue}}</strong> ist eskaliert.</p><p>{{Ticket.Title}}</p><p>{{Ticket.LinkHTML}}</p>~ ],
        [ 'ticket_pending_reached', q~Bei erreichtem Warten-Status~, q~Warten erreicht: Ticket {{Ticket.Number}}~, q~<p>Hallo {{Agent.FullName}},</p><p>bei Ticket <strong>{{Ticket.Number}}</strong> in deiner Queue <strong>{{Ticket.Queue}}</strong> wurde der Warten-Zeitpunkt erreicht.</p><p>Warten bis: <strong>{{PendingUntil}}</strong><br>Erreicht seit: <strong>{{PendingReachedSince}}</strong></p><p>{{Ticket.LinkHTML}}</p>~ ],
    ],
    en => [
        [ 'ticket_new_in_my_queues', q~New ticket in my queues~, q~New ticket {{Ticket.Number}} in {{Ticket.Queue}}~, q~<p>Hello {{Agent.FullName}},</p><p>a new ticket was created in your queue <strong>{{Ticket.Queue}}</strong>.</p><p><strong>{{Ticket.Number}}</strong> - {{Ticket.Title}}</p><p>{{Ticket.LinkHTML}}</p>~ ],
        [ 'customer_reply_in_my_queues', q~Customer reply in tickets in my queues~, q~Customer reply in ticket {{Ticket.Number}}~, q~<p>Hello {{Agent.FullName}},</p><p>there is a new customer reply in your queue <strong>{{Ticket.Queue}}</strong>.</p><p><strong>{{Ticket.Number}}</strong> - {{Ticket.Title}}</p><p>Customer: {{Customer.Name}}<br>Contact: {{CustomerUser.FullName}}</p><p>{{Ticket.LinkHTML}}</p>~ ],
        [ 'ticket_assigned_to_me', q~Ticket assigned to me~, q~Ticket {{Ticket.Number}} was assigned to you~, q~<p>Hello {{Agent.FullName}},</p><p>ticket <strong>{{Ticket.Number}}</strong> was assigned to you.</p><p>{{Ticket.Title}}</p><p>{{Ticket.LinkHTML}}</p>~ ],
        [ 'ticket_state_changed', q~Ticket status changed~, q~Status changed: Ticket {{Ticket.Number}}~, q~<p>Hello {{Agent.FullName}},</p><p>the status of ticket <strong>{{Ticket.Number}}</strong> in your queue <strong>{{Ticket.Queue}}</strong> was changed.</p><p>New status: <strong>{{Ticket.State}}</strong></p><p>{{Ticket.LinkHTML}}</p>~ ],
        [ 'ticket_escalation_reached', q~On escalation~, q~Escalation reached: Ticket {{Ticket.Number}}~, q~<p>Hello {{Agent.FullName}},</p><p>ticket <strong>{{Ticket.Number}}</strong> in your queue <strong>{{Ticket.Queue}}</strong> has escalated.</p><p>{{Ticket.Title}}</p><p>{{Ticket.LinkHTML}}</p>~ ],
        [ 'ticket_pending_reached', q~When pending time is reached~, q~Pending time reached: Ticket {{Ticket.Number}}~, q~<p>Hello {{Agent.FullName}},</p><p>the pending time for ticket <strong>{{Ticket.Number}}</strong> in your queue <strong>{{Ticket.Queue}}</strong> has been reached.</p><p>Pending until: <strong>{{PendingUntil}}</strong><br>Reached: <strong>{{PendingReachedSince}}</strong> ago</p><p>{{Ticket.LinkHTML}}</p>~ ],
    ],
    fr => [
        [ 'ticket_new_in_my_queues', q~Nouveau ticket dans mes files~, q~Nouveau ticket {{Ticket.Number}} dans {{Ticket.Queue}}~, q~<p>Bonjour {{Agent.FullName}},</p><p>un nouveau ticket a été créé dans votre file <strong>{{Ticket.Queue}}</strong>.</p><p><strong>{{Ticket.Number}}</strong> - {{Ticket.Title}}</p><p>{{Ticket.LinkHTML}}</p>~ ],
        [ 'customer_reply_in_my_queues', q~Réponse client dans les tickets de mes files~, q~Réponse client dans le ticket {{Ticket.Number}}~, q~<p>Bonjour {{Agent.FullName}},</p><p>une nouvelle réponse client est disponible dans votre file <strong>{{Ticket.Queue}}</strong>.</p><p><strong>{{Ticket.Number}}</strong> - {{Ticket.Title}}</p><p>Client : {{Customer.Name}}<br>Contact : {{CustomerUser.FullName}}</p><p>{{Ticket.LinkHTML}}</p>~ ],
        [ 'ticket_assigned_to_me', q~Ticket qui m’a été attribué~, q~Le ticket {{Ticket.Number}} vous a été attribué~, q~<p>Bonjour {{Agent.FullName}},</p><p>le ticket <strong>{{Ticket.Number}}</strong> vous a été attribué.</p><p>{{Ticket.Title}}</p><p>{{Ticket.LinkHTML}}</p>~ ],
        [ 'ticket_state_changed', q~Statut du ticket modifié~, q~Statut modifié : ticket {{Ticket.Number}}~, q~<p>Bonjour {{Agent.FullName}},</p><p>le statut du ticket <strong>{{Ticket.Number}}</strong> dans votre file <strong>{{Ticket.Queue}}</strong> a été modifié.</p><p>Nouveau statut : <strong>{{Ticket.State}}</strong></p><p>{{Ticket.LinkHTML}}</p>~ ],
        [ 'ticket_escalation_reached', q~Lors d’une escalade~, q~Escalade atteinte : ticket {{Ticket.Number}}~, q~<p>Bonjour {{Agent.FullName}},</p><p>le ticket <strong>{{Ticket.Number}}</strong> dans votre file <strong>{{Ticket.Queue}}</strong> a été escaladé.</p><p>{{Ticket.Title}}</p><p>{{Ticket.LinkHTML}}</p>~ ],
        [ 'ticket_pending_reached', q~À l’échéance de l’attente~, q~Échéance de l’attente atteinte : ticket {{Ticket.Number}}~, q~<p>Bonjour {{Agent.FullName}},</p><p>l’échéance d’attente du ticket <strong>{{Ticket.Number}}</strong> dans votre file <strong>{{Ticket.Queue}}</strong> est atteinte.</p><p>En attente jusqu’au : <strong>{{PendingUntil}}</strong><br>Échéance atteinte depuis : <strong>{{PendingReachedSince}}</strong></p><p>{{Ticket.LinkHTML}}</p>~ ],
    ],
    it => [
        [ 'ticket_new_in_my_queues', q~Nuovo ticket nelle mie code~, q~Nuovo ticket {{Ticket.Number}} in {{Ticket.Queue}}~, q~<p>Ciao {{Agent.FullName}},</p><p>è stato creato un nuovo ticket nella tua coda <strong>{{Ticket.Queue}}</strong>.</p><p><strong>{{Ticket.Number}}</strong> - {{Ticket.Title}}</p><p>{{Ticket.LinkHTML}}</p>~ ],
        [ 'customer_reply_in_my_queues', q~Risposta del cliente nei ticket delle mie code~, q~Risposta del cliente nel ticket {{Ticket.Number}}~, q~<p>Ciao {{Agent.FullName}},</p><p>c’è una nuova risposta del cliente nella tua coda <strong>{{Ticket.Queue}}</strong>.</p><p><strong>{{Ticket.Number}}</strong> - {{Ticket.Title}}</p><p>Cliente: {{Customer.Name}}<br>Contatto: {{CustomerUser.FullName}}</p><p>{{Ticket.LinkHTML}}</p>~ ],
        [ 'ticket_assigned_to_me', q~Ticket assegnato a me~, q~Il ticket {{Ticket.Number}} ti è stato assegnato~, q~<p>Ciao {{Agent.FullName}},</p><p>il ticket <strong>{{Ticket.Number}}</strong> ti è stato assegnato.</p><p>{{Ticket.Title}}</p><p>{{Ticket.LinkHTML}}</p>~ ],
        [ 'ticket_state_changed', q~Stato del ticket modificato~, q~Stato modificato: ticket {{Ticket.Number}}~, q~<p>Ciao {{Agent.FullName}},</p><p>lo stato del ticket <strong>{{Ticket.Number}}</strong> nella tua coda <strong>{{Ticket.Queue}}</strong> è stato modificato.</p><p>Nuovo stato: <strong>{{Ticket.State}}</strong></p><p>{{Ticket.LinkHTML}}</p>~ ],
        [ 'ticket_escalation_reached', q~In caso di escalation~, q~Escalation raggiunta: ticket {{Ticket.Number}}~, q~<p>Ciao {{Agent.FullName}},</p><p>il ticket <strong>{{Ticket.Number}}</strong> nella tua coda <strong>{{Ticket.Queue}}</strong> è andato in escalation.</p><p>{{Ticket.Title}}</p><p>{{Ticket.LinkHTML}}</p>~ ],
        [ 'ticket_pending_reached', q~Al raggiungimento dell’attesa~, q~Termine di attesa raggiunto: ticket {{Ticket.Number}}~, q~<p>Ciao {{Agent.FullName}},</p><p>è stato raggiunto il termine di attesa del ticket <strong>{{Ticket.Number}}</strong> nella tua coda <strong>{{Ticket.Queue}}</strong>.</p><p>In attesa fino a: <strong>{{PendingUntil}}</strong><br>Raggiunto da: <strong>{{PendingReachedSince}}</strong></p><p>{{Ticket.LinkHTML}}</p>~ ],
    ],
    es => [
        [ 'ticket_new_in_my_queues', q~Nuevo ticket en mis colas~, q~Nuevo ticket {{Ticket.Number}} en {{Ticket.Queue}}~, q~<p>Hola {{Agent.FullName}},</p><p>se ha creado un nuevo ticket en tu cola <strong>{{Ticket.Queue}}</strong>.</p><p><strong>{{Ticket.Number}}</strong> - {{Ticket.Title}}</p><p>{{Ticket.LinkHTML}}</p>~ ],
        [ 'customer_reply_in_my_queues', q~Respuesta del cliente en tickets de mis colas~, q~Respuesta del cliente en el ticket {{Ticket.Number}}~, q~<p>Hola {{Agent.FullName}},</p><p>hay una nueva respuesta del cliente en tu cola <strong>{{Ticket.Queue}}</strong>.</p><p><strong>{{Ticket.Number}}</strong> - {{Ticket.Title}}</p><p>Cliente: {{Customer.Name}}<br>Contacto: {{CustomerUser.FullName}}</p><p>{{Ticket.LinkHTML}}</p>~ ],
        [ 'ticket_assigned_to_me', q~Ticket asignado a mí~, q~Se te ha asignado el ticket {{Ticket.Number}}~, q~<p>Hola {{Agent.FullName}},</p><p>se te ha asignado el ticket <strong>{{Ticket.Number}}</strong>.</p><p>{{Ticket.Title}}</p><p>{{Ticket.LinkHTML}}</p>~ ],
        [ 'ticket_state_changed', q~Estado del ticket modificado~, q~Estado modificado: ticket {{Ticket.Number}}~, q~<p>Hola {{Agent.FullName}},</p><p>se ha modificado el estado del ticket <strong>{{Ticket.Number}}</strong> en tu cola <strong>{{Ticket.Queue}}</strong>.</p><p>Nuevo estado: <strong>{{Ticket.State}}</strong></p><p>{{Ticket.LinkHTML}}</p>~ ],
        [ 'ticket_escalation_reached', q~En caso de escalado~, q~Escalado alcanzado: ticket {{Ticket.Number}}~, q~<p>Hola {{Agent.FullName}},</p><p>el ticket <strong>{{Ticket.Number}}</strong> en tu cola <strong>{{Ticket.Queue}}</strong> ha escalado.</p><p>{{Ticket.Title}}</p><p>{{Ticket.LinkHTML}}</p>~ ],
        [ 'ticket_pending_reached', q~Al alcanzar el tiempo de espera~, q~Tiempo de espera alcanzado: ticket {{Ticket.Number}}~, q~<p>Hola {{Agent.FullName}},</p><p>se ha alcanzado el tiempo de espera del ticket <strong>{{Ticket.Number}}</strong> en tu cola <strong>{{Ticket.Queue}}</strong>.</p><p>En espera hasta: <strong>{{PendingUntil}}</strong><br>Alcanzado desde hace: <strong>{{PendingReachedSince}}</strong></p><p>{{Ticket.LinkHTML}}</p>~ ],
    ],
    'pt-BR' => [
        [ 'ticket_new_in_my_queues', q~Novo ticket nas minhas filas~, q~Novo ticket {{Ticket.Number}} em {{Ticket.Queue}}~, q~<p>Olá {{Agent.FullName}},</p><p>um novo ticket foi criado na sua fila <strong>{{Ticket.Queue}}</strong>.</p><p><strong>{{Ticket.Number}}</strong> - {{Ticket.Title}}</p><p>{{Ticket.LinkHTML}}</p>~ ],
        [ 'customer_reply_in_my_queues', q~Resposta do cliente em tickets das minhas filas~, q~Resposta do cliente no ticket {{Ticket.Number}}~, q~<p>Olá {{Agent.FullName}},</p><p>há uma nova resposta do cliente na sua fila <strong>{{Ticket.Queue}}</strong>.</p><p><strong>{{Ticket.Number}}</strong> - {{Ticket.Title}}</p><p>Cliente: {{Customer.Name}}<br>Contato: {{CustomerUser.FullName}}</p><p>{{Ticket.LinkHTML}}</p>~ ],
        [ 'ticket_assigned_to_me', q~Ticket atribuído a mim~, q~O ticket {{Ticket.Number}} foi atribuído a você~, q~<p>Olá {{Agent.FullName}},</p><p>o ticket <strong>{{Ticket.Number}}</strong> foi atribuído a você.</p><p>{{Ticket.Title}}</p><p>{{Ticket.LinkHTML}}</p>~ ],
        [ 'ticket_state_changed', q~Status do ticket alterado~, q~Status alterado: ticket {{Ticket.Number}}~, q~<p>Olá {{Agent.FullName}},</p><p>o status do ticket <strong>{{Ticket.Number}}</strong> na sua fila <strong>{{Ticket.Queue}}</strong> foi alterado.</p><p>Novo status: <strong>{{Ticket.State}}</strong></p><p>{{Ticket.LinkHTML}}</p>~ ],
        [ 'ticket_escalation_reached', q~Em caso de escalonamento~, q~Escalonamento atingido: ticket {{Ticket.Number}}~, q~<p>Olá {{Agent.FullName}},</p><p>o ticket <strong>{{Ticket.Number}}</strong> na sua fila <strong>{{Ticket.Queue}}</strong> foi escalonado.</p><p>{{Ticket.Title}}</p><p>{{Ticket.LinkHTML}}</p>~ ],
        [ 'ticket_pending_reached', q~Ao atingir o prazo de pendência~, q~Prazo de pendência atingido: ticket {{Ticket.Number}}~, q~<p>Olá {{Agent.FullName}},</p><p>o prazo de pendência do ticket <strong>{{Ticket.Number}}</strong> na sua fila <strong>{{Ticket.Queue}}</strong> foi atingido.</p><p>Pendente até: <strong>{{PendingUntil}}</strong><br>Atingido há: <strong>{{PendingReachedSince}}</strong></p><p>{{Ticket.LinkHTML}}</p>~ ],
    ],
    'pt-PT' => [
        [ 'ticket_new_in_my_queues', q~Novo ticket nas minhas filas~, q~Novo ticket {{Ticket.Number}} em {{Ticket.Queue}}~, q~<p>Olá {{Agent.FullName}},</p><p>foi criado um novo ticket na sua fila <strong>{{Ticket.Queue}}</strong>.</p><p><strong>{{Ticket.Number}}</strong> - {{Ticket.Title}}</p><p>{{Ticket.LinkHTML}}</p>~ ],
        [ 'customer_reply_in_my_queues', q~Resposta do cliente em tickets das minhas filas~, q~Resposta do cliente no ticket {{Ticket.Number}}~, q~<p>Olá {{Agent.FullName}},</p><p>existe uma nova resposta do cliente na sua fila <strong>{{Ticket.Queue}}</strong>.</p><p><strong>{{Ticket.Number}}</strong> - {{Ticket.Title}}</p><p>Cliente: {{Customer.Name}}<br>Contacto: {{CustomerUser.FullName}}</p><p>{{Ticket.LinkHTML}}</p>~ ],
        [ 'ticket_assigned_to_me', q~Ticket atribuído a mim~, q~O ticket {{Ticket.Number}} foi-lhe atribuído~, q~<p>Olá {{Agent.FullName}},</p><p>o ticket <strong>{{Ticket.Number}}</strong> foi-lhe atribuído.</p><p>{{Ticket.Title}}</p><p>{{Ticket.LinkHTML}}</p>~ ],
        [ 'ticket_state_changed', q~Estado do ticket alterado~, q~Estado alterado: ticket {{Ticket.Number}}~, q~<p>Olá {{Agent.FullName}},</p><p>o estado do ticket <strong>{{Ticket.Number}}</strong> na sua fila <strong>{{Ticket.Queue}}</strong> foi alterado.</p><p>Novo estado: <strong>{{Ticket.State}}</strong></p><p>{{Ticket.LinkHTML}}</p>~ ],
        [ 'ticket_escalation_reached', q~Em caso de escalonamento~, q~Escalonamento atingido: ticket {{Ticket.Number}}~, q~<p>Olá {{Agent.FullName}},</p><p>o ticket <strong>{{Ticket.Number}}</strong> na sua fila <strong>{{Ticket.Queue}}</strong> foi escalonado.</p><p>{{Ticket.Title}}</p><p>{{Ticket.LinkHTML}}</p>~ ],
        [ 'ticket_pending_reached', q~Ao atingir o prazo de espera~, q~Prazo de espera atingido: ticket {{Ticket.Number}}~, q~<p>Olá {{Agent.FullName}},</p><p>foi atingido o prazo de espera do ticket <strong>{{Ticket.Number}}</strong> na sua fila <strong>{{Ticket.Queue}}</strong>.</p><p>Em espera até: <strong>{{PendingUntil}}</strong><br>Atingido há: <strong>{{PendingReachedSince}}</strong></p><p>{{Ticket.LinkHTML}}</p>~ ],
    ],
    nl => [
        [ 'ticket_new_in_my_queues', q~Nieuw ticket in mijn wachtrijen~, q~Nieuw ticket {{Ticket.Number}} in {{Ticket.Queue}}~, q~<p>Hallo {{Agent.FullName}},</p><p>er is een nieuw ticket aangemaakt in je wachtrij <strong>{{Ticket.Queue}}</strong>.</p><p><strong>{{Ticket.Number}}</strong> - {{Ticket.Title}}</p><p>{{Ticket.LinkHTML}}</p>~ ],
        [ 'customer_reply_in_my_queues', q~Klantantwoord in tickets van mijn wachtrijen~, q~Klantantwoord in ticket {{Ticket.Number}}~, q~<p>Hallo {{Agent.FullName}},</p><p>er is een nieuw klantantwoord in je wachtrij <strong>{{Ticket.Queue}}</strong>.</p><p><strong>{{Ticket.Number}}</strong> - {{Ticket.Title}}</p><p>Klant: {{Customer.Name}}<br>Contactpersoon: {{CustomerUser.FullName}}</p><p>{{Ticket.LinkHTML}}</p>~ ],
        [ 'ticket_assigned_to_me', q~Ticket aan mij toegewezen~, q~Ticket {{Ticket.Number}} is aan jou toegewezen~, q~<p>Hallo {{Agent.FullName}},</p><p>ticket <strong>{{Ticket.Number}}</strong> is aan jou toegewezen.</p><p>{{Ticket.Title}}</p><p>{{Ticket.LinkHTML}}</p>~ ],
        [ 'ticket_state_changed', q~Ticketstatus gewijzigd~, q~Status gewijzigd: ticket {{Ticket.Number}}~, q~<p>Hallo {{Agent.FullName}},</p><p>de status van ticket <strong>{{Ticket.Number}}</strong> in je wachtrij <strong>{{Ticket.Queue}}</strong> is gewijzigd.</p><p>Nieuwe status: <strong>{{Ticket.State}}</strong></p><p>{{Ticket.LinkHTML}}</p>~ ],
        [ 'ticket_escalation_reached', q~Bij escalatie~, q~Escalatie bereikt: ticket {{Ticket.Number}}~, q~<p>Hallo {{Agent.FullName}},</p><p>ticket <strong>{{Ticket.Number}}</strong> in je wachtrij <strong>{{Ticket.Queue}}</strong> is geëscaleerd.</p><p>{{Ticket.Title}}</p><p>{{Ticket.LinkHTML}}</p>~ ],
        [ 'ticket_pending_reached', q~Wanneer de wachttijd is bereikt~, q~Wachttijd bereikt: ticket {{Ticket.Number}}~, q~<p>Hallo {{Agent.FullName}},</p><p>de wachttijd van ticket <strong>{{Ticket.Number}}</strong> in je wachtrij <strong>{{Ticket.Queue}}</strong> is bereikt.</p><p>Wachten tot: <strong>{{PendingUntil}}</strong><br>Bereikt sinds: <strong>{{PendingReachedSince}}</strong></p><p>{{Ticket.LinkHTML}}</p>~ ],
    ],
    pl => [
        [ 'ticket_new_in_my_queues', q~Nowe zgłoszenie w moich kolejkach~, q~Nowe zgłoszenie {{Ticket.Number}} w {{Ticket.Queue}}~, q~<p>Witaj {{Agent.FullName}},</p><p>w Twojej kolejce <strong>{{Ticket.Queue}}</strong> utworzono nowe zgłoszenie.</p><p><strong>{{Ticket.Number}}</strong> - {{Ticket.Title}}</p><p>{{Ticket.LinkHTML}}</p>~ ],
        [ 'customer_reply_in_my_queues', q~Odpowiedź klienta w zgłoszeniach z moich kolejek~, q~Odpowiedź klienta w zgłoszeniu {{Ticket.Number}}~, q~<p>Witaj {{Agent.FullName}},</p><p>w Twojej kolejce <strong>{{Ticket.Queue}}</strong> pojawiła się nowa odpowiedź klienta.</p><p><strong>{{Ticket.Number}}</strong> - {{Ticket.Title}}</p><p>Klient: {{Customer.Name}}<br>Osoba kontaktowa: {{CustomerUser.FullName}}</p><p>{{Ticket.LinkHTML}}</p>~ ],
        [ 'ticket_assigned_to_me', q~Zgłoszenie przypisane do mnie~, q~Przypisano Ci zgłoszenie {{Ticket.Number}}~, q~<p>Witaj {{Agent.FullName}},</p><p>przypisano Ci zgłoszenie <strong>{{Ticket.Number}}</strong>.</p><p>{{Ticket.Title}}</p><p>{{Ticket.LinkHTML}}</p>~ ],
        [ 'ticket_state_changed', q~Zmieniono status zgłoszenia~, q~Zmieniono status: zgłoszenie {{Ticket.Number}}~, q~<p>Witaj {{Agent.FullName}},</p><p>zmieniono status zgłoszenia <strong>{{Ticket.Number}}</strong> w Twojej kolejce <strong>{{Ticket.Queue}}</strong>.</p><p>Nowy status: <strong>{{Ticket.State}}</strong></p><p>{{Ticket.LinkHTML}}</p>~ ],
        [ 'ticket_escalation_reached', q~Przy eskalacji~, q~Osiągnięto eskalację: zgłoszenie {{Ticket.Number}}~, q~<p>Witaj {{Agent.FullName}},</p><p>zgłoszenie <strong>{{Ticket.Number}}</strong> w Twojej kolejce <strong>{{Ticket.Queue}}</strong> zostało eskalowane.</p><p>{{Ticket.Title}}</p><p>{{Ticket.LinkHTML}}</p>~ ],
        [ 'ticket_pending_reached', q~Po osiągnięciu terminu oczekiwania~, q~Osiągnięto termin oczekiwania: zgłoszenie {{Ticket.Number}}~, q~<p>Witaj {{Agent.FullName}},</p><p>osiągnięto termin oczekiwania zgłoszenia <strong>{{Ticket.Number}}</strong> w Twojej kolejce <strong>{{Ticket.Queue}}</strong>.</p><p>Oczekiwanie do: <strong>{{PendingUntil}}</strong><br>Termin osiągnięto: <strong>{{PendingReachedSince}}</strong> temu</p><p>{{Ticket.LinkHTML}}</p>~ ],
    ],
    cs => [
        [ 'ticket_new_in_my_queues', q~Nový tiket v mých frontách~, q~Nový tiket {{Ticket.Number}} ve frontě {{Ticket.Queue}}~, q~<p>Dobrý den {{Agent.FullName}},</p><p>ve vaší frontě <strong>{{Ticket.Queue}}</strong> byl vytvořen nový tiket.</p><p><strong>{{Ticket.Number}}</strong> - {{Ticket.Title}}</p><p>{{Ticket.LinkHTML}}</p>~ ],
        [ 'customer_reply_in_my_queues', q~Odpověď zákazníka v tiketech mých front~, q~Odpověď zákazníka v tiketu {{Ticket.Number}}~, q~<p>Dobrý den {{Agent.FullName}},</p><p>ve vaší frontě <strong>{{Ticket.Queue}}</strong> je nová odpověď zákazníka.</p><p><strong>{{Ticket.Number}}</strong> - {{Ticket.Title}}</p><p>Zákazník: {{Customer.Name}}<br>Kontaktní osoba: {{CustomerUser.FullName}}</p><p>{{Ticket.LinkHTML}}</p>~ ],
        [ 'ticket_assigned_to_me', q~Tiket přiřazený mně~, q~Byl vám přiřazen tiket {{Ticket.Number}}~, q~<p>Dobrý den {{Agent.FullName}},</p><p>byl vám přiřazen tiket <strong>{{Ticket.Number}}</strong>.</p><p>{{Ticket.Title}}</p><p>{{Ticket.LinkHTML}}</p>~ ],
        [ 'ticket_state_changed', q~Stav tiketu byl změněn~, q~Stav změněn: tiket {{Ticket.Number}}~, q~<p>Dobrý den {{Agent.FullName}},</p><p>stav tiketu <strong>{{Ticket.Number}}</strong> ve vaší frontě <strong>{{Ticket.Queue}}</strong> byl změněn.</p><p>Nový stav: <strong>{{Ticket.State}}</strong></p><p>{{Ticket.LinkHTML}}</p>~ ],
        [ 'ticket_escalation_reached', q~Při eskalaci~, q~Dosažena eskalace: tiket {{Ticket.Number}}~, q~<p>Dobrý den {{Agent.FullName}},</p><p>tiket <strong>{{Ticket.Number}}</strong> ve vaší frontě <strong>{{Ticket.Queue}}</strong> byl eskalován.</p><p>{{Ticket.Title}}</p><p>{{Ticket.LinkHTML}}</p>~ ],
        [ 'ticket_pending_reached', q~Při dosažení doby čekání~, q~Dosažena doba čekání: tiket {{Ticket.Number}}~, q~<p>Dobrý den {{Agent.FullName}},</p><p>byla dosažena doba čekání tiketu <strong>{{Ticket.Number}}</strong> ve vaší frontě <strong>{{Ticket.Queue}}</strong>.</p><p>Čekání do: <strong>{{PendingUntil}}</strong><br>Dosaženo před: <strong>{{PendingReachedSince}}</strong></p><p>{{Ticket.LinkHTML}}</p>~ ],
    ],
    tr => [
        [ 'ticket_new_in_my_queues', q~Kuyruklarımda yeni bilet~, q~{{Ticket.Queue}} kuyruğunda yeni bilet {{Ticket.Number}}~, q~<p>Merhaba {{Agent.FullName}},</p><p><strong>{{Ticket.Queue}}</strong> kuyruğunuzda yeni bir bilet oluşturuldu.</p><p><strong>{{Ticket.Number}}</strong> - {{Ticket.Title}}</p><p>{{Ticket.LinkHTML}}</p>~ ],
        [ 'customer_reply_in_my_queues', q~Kuyruklarımdaki biletlere müşteri yanıtı~, q~{{Ticket.Number}} biletine müşteri yanıtı~, q~<p>Merhaba {{Agent.FullName}},</p><p><strong>{{Ticket.Queue}}</strong> kuyruğunuzda yeni bir müşteri yanıtı var.</p><p><strong>{{Ticket.Number}}</strong> - {{Ticket.Title}}</p><p>Müşteri: {{Customer.Name}}<br>İlgili kişi: {{CustomerUser.FullName}}</p><p>{{Ticket.LinkHTML}}</p>~ ],
        [ 'ticket_assigned_to_me', q~Bana atanan bilet~, q~{{Ticket.Number}} bileti size atandı~, q~<p>Merhaba {{Agent.FullName}},</p><p><strong>{{Ticket.Number}}</strong> bileti size atandı.</p><p>{{Ticket.Title}}</p><p>{{Ticket.LinkHTML}}</p>~ ],
        [ 'ticket_state_changed', q~Bilet durumu değiştirildi~, q~Durum değiştirildi: bilet {{Ticket.Number}}~, q~<p>Merhaba {{Agent.FullName}},</p><p><strong>{{Ticket.Queue}}</strong> kuyruğunuzdaki <strong>{{Ticket.Number}}</strong> biletinin durumu değiştirildi.</p><p>Yeni durum: <strong>{{Ticket.State}}</strong></p><p>{{Ticket.LinkHTML}}</p>~ ],
        [ 'ticket_escalation_reached', q~Eskalasyon durumunda~, q~Eskalasyona ulaşıldı: bilet {{Ticket.Number}}~, q~<p>Merhaba {{Agent.FullName}},</p><p><strong>{{Ticket.Queue}}</strong> kuyruğunuzdaki <strong>{{Ticket.Number}}</strong> bileti eskale edildi.</p><p>{{Ticket.Title}}</p><p>{{Ticket.LinkHTML}}</p>~ ],
        [ 'ticket_pending_reached', q~Bekleme süresine ulaşıldığında~, q~Bekleme süresine ulaşıldı: bilet {{Ticket.Number}}~, q~<p>Merhaba {{Agent.FullName}},</p><p><strong>{{Ticket.Queue}}</strong> kuyruğunuzdaki <strong>{{Ticket.Number}}</strong> biletinin bekleme süresine ulaşıldı.</p><p>Bekleme bitişi: <strong>{{PendingUntil}}</strong><br>Geçen süre: <strong>{{PendingReachedSince}}</strong></p><p>{{Ticket.LinkHTML}}</p>~ ],
    ],
);

sub Languages {
    return [ map { { %{$_} } } @Languages ];
}

sub LanguageClean {
    my ( $Class, $Language, $Fallback ) = @_;

    $Language = '' if !defined $Language;
    $Language =~ s{_}{-}g;
    $Language =~ s{\A\s+|\s+\z}{}g;

    my %Canonical = map { lc( $_->{code} ) => $_->{code} } @Languages;
    return $Canonical{ lc $Language } if $Canonical{ lc $Language };

    $Fallback = '' if !defined $Fallback;
    $Fallback =~ s{_}{-}g;
    return $Canonical{ lc $Fallback } if $Canonical{ lc $Fallback };

    return 'en';
}

sub Templates {
    my ( $Class, %Param ) = @_;

    my $Language = $Class->LanguageClean( $Param{Language}, 'en' );
    my %SortOrder = map { $TypeOrder[$_] => ( $_ + 1 ) * 100 } 0 .. $#TypeOrder;

    return [
        map {
            {
                type       => $_->[0],
                name       => $_->[1],
                subject    => $_->[2],
                body_html  => $_->[3],
                sort_order => $SortOrder{ $_->[0] },
            }
        } @{ $Template{$Language} || $Template{en} }
    ];
}

sub TicketLinkText {
    my ( $Class, %Param ) = @_;

    my $Language = $Class->LanguageClean( $Param{Language}, 'en' );
    my $Number   = defined $Param{Number} ? $Param{Number} : '';
    my %Text = (
        de      => 'Ticket %s öffnen',
        en      => 'Open ticket %s',
        fr      => 'Ouvrir le ticket %s',
        it      => 'Apri il ticket %s',
        es      => 'Abrir el ticket %s',
        'pt-BR' => 'Abrir o ticket %s',
        'pt-PT' => 'Abrir o ticket %s',
        nl      => 'Ticket %s openen',
        pl      => 'Otwórz zgłoszenie %s',
        cs      => 'Otevřít tiket %s',
        tr      => '%s biletini aç',
    );

    return sprintf( $Text{$Language} || $Text{en}, $Number );
}

sub DurationText {
    my ( $Class, %Param ) = @_;

    my $Language = $Class->LanguageClean( $Param{Language}, 'en' );
    my $Seconds  = $Param{Seconds} || 0;
    $Seconds = 0 if $Seconds < 0;

    my $Minutes = int( $Seconds / 60 );
    my $Hours   = int( $Minutes / 60 );
    my $Days    = int( $Hours / 24 );
    my ( $Value, $Unit ) = $Days > 0
        ? ( $Days, 'day' )
        : $Hours > 0
            ? ( $Hours, 'hour' )
            : ( $Minutes, 'minute' );

    my %Singular = (
        de => { day => 'Tag', hour => 'Stunde', minute => 'Minute' },
        en => { day => 'day', hour => 'hour', minute => 'minute' },
        fr => { day => 'jour', hour => 'heure', minute => 'minute' },
        it => { day => 'giorno', hour => 'ora', minute => 'minuto' },
        es => { day => 'día', hour => 'hora', minute => 'minuto' },
        'pt-BR' => { day => 'dia', hour => 'hora', minute => 'minuto' },
        'pt-PT' => { day => 'dia', hour => 'hora', minute => 'minuto' },
        nl => { day => 'dag', hour => 'uur', minute => 'minuut' },
        pl => { day => 'dzień', hour => 'godzina', minute => 'minuta' },
        cs => { day => 'den', hour => 'hodina', minute => 'minuta' },
        tr => { day => 'gün', hour => 'saat', minute => 'dakika' },
    );
    my %Plural = (
        de => { day => 'Tage', hour => 'Stunden', minute => 'Minuten' },
        en => { day => 'days', hour => 'hours', minute => 'minutes' },
        fr => { day => 'jours', hour => 'heures', minute => 'minutes' },
        it => { day => 'giorni', hour => 'ore', minute => 'minuti' },
        es => { day => 'días', hour => 'horas', minute => 'minutos' },
        'pt-BR' => { day => 'dias', hour => 'horas', minute => 'minutos' },
        'pt-PT' => { day => 'dias', hour => 'horas', minute => 'minutos' },
        nl => { day => 'dagen', hour => 'uur', minute => 'minuten' },
        pl => { day => 'dni', hour => 'godziny', minute => 'minuty' },
        cs => { day => 'dny', hour => 'hodiny', minute => 'minuty' },
        tr => { day => 'gün', hour => 'saat', minute => 'dakika' },
    );

    my $Word = $Value == 1
        ? $Singular{$Language}->{$Unit}
        : $Plural{$Language}->{$Unit};

    return $Value . ' ' . $Word;
}

1;
