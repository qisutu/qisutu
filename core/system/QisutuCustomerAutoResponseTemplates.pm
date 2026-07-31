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

package QisutuCustomerAutoResponseTemplates;

use strict;
use warnings;
use utf8;

use QisutuAgentNotificationTemplates;

my @TypeOrder = (
    'customer_ticket_created',
    'customer_ticket_reply',
    'incoming_email_rejected',
    'closed_ticket_follow_up',
);

my %Template = (
    de => [
        [ 'customer_ticket_created', q~Ticket durch Kunden erstellt~, q~Eingangsbestätigung: {{Ticket.Number}} – {{Ticket.Title}}~, q~<p>Hallo {{CustomerUser.FullName}},</p><p>vielen Dank für Ihre Nachricht. Ihr Ticket <strong>{{Ticket.Number}}</strong> wurde angelegt.</p><p><strong>{{Ticket.Title}}</strong></p><p>{{Ticket.LinkHTML}}</p>~ ],
        [ 'customer_ticket_reply', q~Kundenantwort eingegangen~, q~Eingangsbestätigung zu Ticket {{Ticket.Number}}~, q~<p>Hallo {{CustomerUser.FullName}},</p><p>Ihre Antwort zu Ticket <strong>{{Ticket.Number}}</strong> ist eingegangen.</p><p>{{Ticket.LinkHTML}}</p>~ ],
        [ 'incoming_email_rejected', q~Eingehende E-Mail abgelehnt~, q~Ihre E-Mail konnte nicht angenommen werden~, q~<p>Hallo {{Incoming.FromName}},</p><p>Ihre E-Mail mit dem Betreff <strong>{{Incoming.Subject}}</strong> konnte nicht angenommen werden.</p><p>Bitte wenden Sie sich auf einem anderen Weg an unseren Support.</p>~ ],
        [ 'closed_ticket_follow_up', q~Kundenantwort auf geschlossenes Ticket~, q~Antwort zu geschlossenem Ticket {{Ticket.Number}}~, q~<p>Hallo {{CustomerUser.FullName}},</p><p>Ihre Nachricht bezieht sich auf das bereits geschlossene Ticket <strong>{{Ticket.Number}}</strong>.</p><p>{{Ticket.LinkHTML}}</p>~ ],
    ],
    en => [
        [ 'customer_ticket_created', q~Ticket created by customer~, q~Confirmation: {{Ticket.Number}} – {{Ticket.Title}}~, q~<p>Hello {{CustomerUser.FullName}},</p><p>thank you for your message. Your ticket <strong>{{Ticket.Number}}</strong> has been created.</p><p><strong>{{Ticket.Title}}</strong></p><p>{{Ticket.LinkHTML}}</p>~ ],
        [ 'customer_ticket_reply', q~Customer reply received~, q~Confirmation for ticket {{Ticket.Number}}~, q~<p>Hello {{CustomerUser.FullName}},</p><p>your reply to ticket <strong>{{Ticket.Number}}</strong> has been received.</p><p>{{Ticket.LinkHTML}}</p>~ ],
        [ 'incoming_email_rejected', q~Incoming email rejected~, q~Your email could not be accepted~, q~<p>Hello {{Incoming.FromName}},</p><p>your email with the subject <strong>{{Incoming.Subject}}</strong> could not be accepted.</p><p>Please contact our support team in another way.</p>~ ],
        [ 'closed_ticket_follow_up', q~Customer reply to a closed ticket~, q~Reply to closed ticket {{Ticket.Number}}~, q~<p>Hello {{CustomerUser.FullName}},</p><p>your message refers to the already closed ticket <strong>{{Ticket.Number}}</strong>.</p><p>{{Ticket.LinkHTML}}</p>~ ],
    ],
    fr => [
        [ 'customer_ticket_created', q~Ticket créé par le client~, q~Confirmation de réception : {{Ticket.Number}} – {{Ticket.Title}}~, q~<p>Bonjour {{CustomerUser.FullName}},</p><p>merci pour votre message. Votre ticket <strong>{{Ticket.Number}}</strong> a été créé.</p><p><strong>{{Ticket.Title}}</strong></p><p>{{Ticket.LinkHTML}}</p>~ ],
        [ 'customer_ticket_reply', q~Réponse du client reçue~, q~Confirmation de réception pour le ticket {{Ticket.Number}}~, q~<p>Bonjour {{CustomerUser.FullName}},</p><p>votre réponse au ticket <strong>{{Ticket.Number}}</strong> a bien été reçue.</p><p>{{Ticket.LinkHTML}}</p>~ ],
        [ 'incoming_email_rejected', q~E-mail entrant refusé~, q~Votre e-mail n’a pas pu être accepté~, q~<p>Bonjour {{Incoming.FromName}},</p><p>votre e-mail ayant pour objet <strong>{{Incoming.Subject}}</strong> n’a pas pu être accepté.</p><p>Veuillez contacter notre assistance par un autre moyen.</p>~ ],
        [ 'closed_ticket_follow_up', q~Réponse du client à un ticket fermé~, q~Réponse au ticket fermé {{Ticket.Number}}~, q~<p>Bonjour {{CustomerUser.FullName}},</p><p>votre message concerne le ticket <strong>{{Ticket.Number}}</strong>, qui est déjà fermé.</p><p>{{Ticket.LinkHTML}}</p>~ ],
    ],
    it => [
        [ 'customer_ticket_created', q~Ticket creato dal cliente~, q~Conferma di ricezione: {{Ticket.Number}} – {{Ticket.Title}}~, q~<p>Ciao {{CustomerUser.FullName}},</p><p>grazie per il messaggio. Il ticket <strong>{{Ticket.Number}}</strong> è stato creato.</p><p><strong>{{Ticket.Title}}</strong></p><p>{{Ticket.LinkHTML}}</p>~ ],
        [ 'customer_ticket_reply', q~Risposta del cliente ricevuta~, q~Conferma di ricezione per il ticket {{Ticket.Number}}~, q~<p>Ciao {{CustomerUser.FullName}},</p><p>la risposta al ticket <strong>{{Ticket.Number}}</strong> è stata ricevuta.</p><p>{{Ticket.LinkHTML}}</p>~ ],
        [ 'incoming_email_rejected', q~E-mail in arrivo rifiutata~, q~Non è stato possibile accettare l’e-mail~, q~<p>Ciao {{Incoming.FromName}},</p><p>non è stato possibile accettare l’e-mail con oggetto <strong>{{Incoming.Subject}}</strong>.</p><p>Contatta il nostro supporto in un altro modo.</p>~ ],
        [ 'closed_ticket_follow_up', q~Risposta del cliente a un ticket chiuso~, q~Risposta al ticket chiuso {{Ticket.Number}}~, q~<p>Ciao {{CustomerUser.FullName}},</p><p>il messaggio si riferisce al ticket <strong>{{Ticket.Number}}</strong>, che è già stato chiuso.</p><p>{{Ticket.LinkHTML}}</p>~ ],
    ],
    es => [
        [ 'customer_ticket_created', q~Ticket creado por el cliente~, q~Confirmación de recepción: {{Ticket.Number}} – {{Ticket.Title}}~, q~<p>Hola {{CustomerUser.FullName}},</p><p>gracias por su mensaje. Se ha creado el ticket <strong>{{Ticket.Number}}</strong>.</p><p><strong>{{Ticket.Title}}</strong></p><p>{{Ticket.LinkHTML}}</p>~ ],
        [ 'customer_ticket_reply', q~Respuesta del cliente recibida~, q~Confirmación de recepción del ticket {{Ticket.Number}}~, q~<p>Hola {{CustomerUser.FullName}},</p><p>hemos recibido su respuesta al ticket <strong>{{Ticket.Number}}</strong>.</p><p>{{Ticket.LinkHTML}}</p>~ ],
        [ 'incoming_email_rejected', q~Correo entrante rechazado~, q~No se ha podido aceptar su correo electrónico~, q~<p>Hola {{Incoming.FromName}},</p><p>no se ha podido aceptar su correo con el asunto <strong>{{Incoming.Subject}}</strong>.</p><p>Póngase en contacto con nuestro equipo de soporte por otro medio.</p>~ ],
        [ 'closed_ticket_follow_up', q~Respuesta del cliente a un ticket cerrado~, q~Respuesta al ticket cerrado {{Ticket.Number}}~, q~<p>Hola {{CustomerUser.FullName}},</p><p>su mensaje se refiere al ticket <strong>{{Ticket.Number}}</strong>, que ya está cerrado.</p><p>{{Ticket.LinkHTML}}</p>~ ],
    ],
    'pt-BR' => [
        [ 'customer_ticket_created', q~Ticket criado pelo cliente~, q~Confirmação de recebimento: {{Ticket.Number}} – {{Ticket.Title}}~, q~<p>Olá {{CustomerUser.FullName}},</p><p>agradecemos sua mensagem. O ticket <strong>{{Ticket.Number}}</strong> foi criado.</p><p><strong>{{Ticket.Title}}</strong></p><p>{{Ticket.LinkHTML}}</p>~ ],
        [ 'customer_ticket_reply', q~Resposta do cliente recebida~, q~Confirmação de recebimento do ticket {{Ticket.Number}}~, q~<p>Olá {{CustomerUser.FullName}},</p><p>recebemos sua resposta ao ticket <strong>{{Ticket.Number}}</strong>.</p><p>{{Ticket.LinkHTML}}</p>~ ],
        [ 'incoming_email_rejected', q~E-mail recebido rejeitado~, q~Não foi possível aceitar seu e-mail~, q~<p>Olá {{Incoming.FromName}},</p><p>não foi possível aceitar seu e-mail com o assunto <strong>{{Incoming.Subject}}</strong>.</p><p>Entre em contato com nosso suporte de outra forma.</p>~ ],
        [ 'closed_ticket_follow_up', q~Resposta do cliente a um ticket fechado~, q~Resposta ao ticket fechado {{Ticket.Number}}~, q~<p>Olá {{CustomerUser.FullName}},</p><p>sua mensagem se refere ao ticket <strong>{{Ticket.Number}}</strong>, que já está fechado.</p><p>{{Ticket.LinkHTML}}</p>~ ],
    ],
    'pt-PT' => [
        [ 'customer_ticket_created', q~Ticket criado pelo cliente~, q~Confirmação de receção: {{Ticket.Number}} – {{Ticket.Title}}~, q~<p>Olá {{CustomerUser.FullName}},</p><p>agradecemos a sua mensagem. O ticket <strong>{{Ticket.Number}}</strong> foi criado.</p><p><strong>{{Ticket.Title}}</strong></p><p>{{Ticket.LinkHTML}}</p>~ ],
        [ 'customer_ticket_reply', q~Resposta do cliente recebida~, q~Confirmação de receção do ticket {{Ticket.Number}}~, q~<p>Olá {{CustomerUser.FullName}},</p><p>recebemos a sua resposta ao ticket <strong>{{Ticket.Number}}</strong>.</p><p>{{Ticket.LinkHTML}}</p>~ ],
        [ 'incoming_email_rejected', q~E-mail recebido rejeitado~, q~Não foi possível aceitar o seu e-mail~, q~<p>Olá {{Incoming.FromName}},</p><p>não foi possível aceitar o seu e-mail com o assunto <strong>{{Incoming.Subject}}</strong>.</p><p>Contacte o nosso suporte por outro meio.</p>~ ],
        [ 'closed_ticket_follow_up', q~Resposta do cliente a um ticket fechado~, q~Resposta ao ticket fechado {{Ticket.Number}}~, q~<p>Olá {{CustomerUser.FullName}},</p><p>a sua mensagem refere-se ao ticket <strong>{{Ticket.Number}}</strong>, que já está fechado.</p><p>{{Ticket.LinkHTML}}</p>~ ],
    ],
    nl => [
        [ 'customer_ticket_created', q~Ticket aangemaakt door klant~, q~Ontvangstbevestiging: {{Ticket.Number}} – {{Ticket.Title}}~, q~<p>Hallo {{CustomerUser.FullName}},</p><p>bedankt voor uw bericht. Uw ticket <strong>{{Ticket.Number}}</strong> is aangemaakt.</p><p><strong>{{Ticket.Title}}</strong></p><p>{{Ticket.LinkHTML}}</p>~ ],
        [ 'customer_ticket_reply', q~Antwoord van klant ontvangen~, q~Ontvangstbevestiging voor ticket {{Ticket.Number}}~, q~<p>Hallo {{CustomerUser.FullName}},</p><p>uw antwoord op ticket <strong>{{Ticket.Number}}</strong> is ontvangen.</p><p>{{Ticket.LinkHTML}}</p>~ ],
        [ 'incoming_email_rejected', q~Inkomende e-mail geweigerd~, q~Uw e-mail kon niet worden geaccepteerd~, q~<p>Hallo {{Incoming.FromName}},</p><p>uw e-mail met het onderwerp <strong>{{Incoming.Subject}}</strong> kon niet worden geaccepteerd.</p><p>Neem op een andere manier contact op met onze ondersteuning.</p>~ ],
        [ 'closed_ticket_follow_up', q~Klantantwoord op een gesloten ticket~, q~Antwoord op gesloten ticket {{Ticket.Number}}~, q~<p>Hallo {{CustomerUser.FullName}},</p><p>uw bericht heeft betrekking op ticket <strong>{{Ticket.Number}}</strong>, dat al is gesloten.</p><p>{{Ticket.LinkHTML}}</p>~ ],
    ],
    pl => [
        [ 'customer_ticket_created', q~Zgłoszenie utworzone przez klienta~, q~Potwierdzenie otrzymania: {{Ticket.Number}} – {{Ticket.Title}}~, q~<p>Dzień dobry {{CustomerUser.FullName}},</p><p>dziękujemy za wiadomość. Zgłoszenie <strong>{{Ticket.Number}}</strong> zostało utworzone.</p><p><strong>{{Ticket.Title}}</strong></p><p>{{Ticket.LinkHTML}}</p>~ ],
        [ 'customer_ticket_reply', q~Otrzymano odpowiedź klienta~, q~Potwierdzenie otrzymania odpowiedzi do zgłoszenia {{Ticket.Number}}~, q~<p>Dzień dobry {{CustomerUser.FullName}},</p><p>otrzymaliśmy odpowiedź do zgłoszenia <strong>{{Ticket.Number}}</strong>.</p><p>{{Ticket.LinkHTML}}</p>~ ],
        [ 'incoming_email_rejected', q~Odrzucono przychodzącą wiadomość e-mail~, q~Nie udało się przyjąć wiadomości e-mail~, q~<p>Dzień dobry {{Incoming.FromName}},</p><p>nie udało się przyjąć wiadomości e-mail o temacie <strong>{{Incoming.Subject}}</strong>.</p><p>Prosimy o kontakt z pomocą techniczną w inny sposób.</p>~ ],
        [ 'closed_ticket_follow_up', q~Odpowiedź klienta do zamkniętego zgłoszenia~, q~Odpowiedź do zamkniętego zgłoszenia {{Ticket.Number}}~, q~<p>Dzień dobry {{CustomerUser.FullName}},</p><p>wiadomość dotyczy zgłoszenia <strong>{{Ticket.Number}}</strong>, które jest już zamknięte.</p><p>{{Ticket.LinkHTML}}</p>~ ],
    ],
    cs => [
        [ 'customer_ticket_created', q~Tiket vytvořený zákazníkem~, q~Potvrzení přijetí: {{Ticket.Number}} – {{Ticket.Title}}~, q~<p>Dobrý den {{CustomerUser.FullName}},</p><p>děkujeme za zprávu. Tiket <strong>{{Ticket.Number}}</strong> byl vytvořen.</p><p><strong>{{Ticket.Title}}</strong></p><p>{{Ticket.LinkHTML}}</p>~ ],
        [ 'customer_ticket_reply', q~Odpověď zákazníka přijata~, q~Potvrzení přijetí odpovědi k tiketu {{Ticket.Number}}~, q~<p>Dobrý den {{CustomerUser.FullName}},</p><p>obdrželi jsme vaši odpověď k tiketu <strong>{{Ticket.Number}}</strong>.</p><p>{{Ticket.LinkHTML}}</p>~ ],
        [ 'incoming_email_rejected', q~Příchozí e-mail odmítnut~, q~Váš e-mail nebylo možné přijmout~, q~<p>Dobrý den {{Incoming.FromName}},</p><p>váš e-mail s předmětem <strong>{{Incoming.Subject}}</strong> nebylo možné přijmout.</p><p>Obraťte se na naši podporu jiným způsobem.</p>~ ],
        [ 'closed_ticket_follow_up', q~Odpověď zákazníka na uzavřený tiket~, q~Odpověď na uzavřený tiket {{Ticket.Number}}~, q~<p>Dobrý den {{CustomerUser.FullName}},</p><p>vaše zpráva se vztahuje k tiketu <strong>{{Ticket.Number}}</strong>, který je již uzavřen.</p><p>{{Ticket.LinkHTML}}</p>~ ],
    ],
    tr => [
        [ 'customer_ticket_created', q~Müşteri tarafından oluşturulan bilet~, q~Alındı onayı: {{Ticket.Number}} – {{Ticket.Title}}~, q~<p>Merhaba {{CustomerUser.FullName}},</p><p>mesajınız için teşekkür ederiz. <strong>{{Ticket.Number}}</strong> numaralı biletiniz oluşturuldu.</p><p><strong>{{Ticket.Title}}</strong></p><p>{{Ticket.LinkHTML}}</p>~ ],
        [ 'customer_ticket_reply', q~Müşteri yanıtı alındı~, q~{{Ticket.Number}} bileti için alındı onayı~, q~<p>Merhaba {{CustomerUser.FullName}},</p><p><strong>{{Ticket.Number}}</strong> numaralı bilete verdiğiniz yanıt alındı.</p><p>{{Ticket.LinkHTML}}</p>~ ],
        [ 'incoming_email_rejected', q~Gelen e-posta reddedildi~, q~E-postanız kabul edilemedi~, q~<p>Merhaba {{Incoming.FromName}},</p><p><strong>{{Incoming.Subject}}</strong> konulu e-postanız kabul edilemedi.</p><p>Lütfen destek ekibimizle başka bir yoldan iletişime geçin.</p>~ ],
        [ 'closed_ticket_follow_up', q~Kapalı bilete müşteri yanıtı~, q~Kapalı {{Ticket.Number}} biletine yanıt~, q~<p>Merhaba {{CustomerUser.FullName}},</p><p>mesajınız daha önce kapatılmış olan <strong>{{Ticket.Number}}</strong> numaralı biletle ilgilidir.</p><p>{{Ticket.LinkHTML}}</p>~ ],
    ],
);

sub Languages {
    return QisutuAgentNotificationTemplates->Languages();
}

sub LanguageClean {
    my ( $Class, $Language, $Fallback ) = @_;

    return QisutuAgentNotificationTemplates->LanguageClean( $Language, $Fallback );
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

1;
