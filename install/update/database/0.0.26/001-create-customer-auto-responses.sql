-- Qisutu - Open Source Ticket System
-- Copyright (C) 2026 Franziska Steps
-- Qisutu - Kim-KI, https://qisutu.de
--
-- This file is part of Qisutu.
--
-- Qisutu is free software: you can redistribute it and/or modify
-- it under the terms of the GNU Affero General Public License as published by
-- the Free Software Foundation, either version 3 of the License, or
-- (at your option) any later version.
--
-- Qisutu is distributed in the hope that it will be useful,
-- but WITHOUT ANY WARRANTY; without even the implied warranty of
-- MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the
-- GNU Affero General Public License for more details.
--
-- You should have received a copy of the GNU Affero General Public License
-- along with Qisutu. If not, see <https://www.gnu.org/licenses/>.
--
-- SPDX-FileCopyrightText: 2026 Franziska Steps
-- SPDX-License-Identifier: AGPL-3.0-or-later

-- Qisutu database update 0.0.26
-- Customer automatic response templates and duplicate-prevention log.

CREATE TABLE IF NOT EXISTS `customer_auto_response_template` (
  `id` bigint(20) unsigned NOT NULL AUTO_INCREMENT,
  `response_type` varchar(100) NOT NULL,
  `name` varchar(255) NOT NULL,
  `subject` varchar(500) NOT NULL DEFAULT '',
  `body_html` longtext NOT NULL,
  `active` tinyint(1) NOT NULL DEFAULT 0,
  `sort_order` int(10) unsigned NOT NULL DEFAULT 1000,
  `created_by_user_id` bigint(20) unsigned NOT NULL DEFAULT 1,
  `changed_by_user_id` bigint(20) unsigned NOT NULL DEFAULT 1,
  `created_at` datetime NOT NULL DEFAULT current_timestamp(),
  `changed_at` datetime NOT NULL DEFAULT current_timestamp() ON UPDATE current_timestamp(),
  PRIMARY KEY (`id`),
  UNIQUE KEY `customer_auto_response_template_type_unique` (`response_type`),
  KEY `customer_auto_response_template_active_sort` (`active`,`sort_order`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE IF NOT EXISTS `customer_auto_response_event_log` (
  `id` bigint(20) unsigned NOT NULL AUTO_INCREMENT,
  `response_type` varchar(100) NOT NULL,
  `ticket_id` bigint(20) unsigned NOT NULL DEFAULT 0,
  `article_id` bigint(20) unsigned NOT NULL DEFAULT 0,
  `recipient_email` varchar(255) NOT NULL,
  `event_key` varchar(255) NOT NULL,
  `sent_at` datetime NOT NULL DEFAULT current_timestamp(),
  PRIMARY KEY (`id`),
  UNIQUE KEY `customer_auto_response_event_unique` (`response_type`,`event_key`),
  KEY `customer_auto_response_event_ticket` (`ticket_id`),
  KEY `customer_auto_response_event_article` (`article_id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

INSERT INTO `customer_auto_response_template` (
  `response_type`, `name`, `subject`, `body_html`, `active`, `sort_order`,
  `created_by_user_id`, `changed_by_user_id`
) VALUES
  ('customer_ticket_created', 'Ticket durch Kunden erstellt', 'Eingangsbestätigung: {{Ticket.Number}} – {{Ticket.Title}}', '<p>Hallo {{CustomerUser.FullName}},</p><p>vielen Dank für Ihre Nachricht. Ihr Ticket <strong>{{Ticket.Number}}</strong> wurde angelegt.</p><p><strong>{{Ticket.Title}}</strong></p><p>{{Ticket.LinkHTML}}</p>', 0, 100, 1, 1),
  ('customer_ticket_reply', 'Kundenantwort eingegangen', 'Eingangsbestätigung zu Ticket {{Ticket.Number}}', '<p>Hallo {{CustomerUser.FullName}},</p><p>Ihre Antwort zu Ticket <strong>{{Ticket.Number}}</strong> ist eingegangen.</p><p>{{Ticket.LinkHTML}}</p>', 0, 200, 1, 1),
  ('incoming_email_rejected', 'Eingehende E-Mail abgelehnt', 'Ihre E-Mail konnte nicht angenommen werden', '<p>Hallo {{Incoming.FromName}},</p><p>Ihre E-Mail mit dem Betreff <strong>{{Incoming.Subject}}</strong> konnte nicht angenommen werden.</p><p>Bitte wenden Sie sich auf einem anderen Weg an unseren Support.</p>', 0, 300, 1, 1),
  ('closed_ticket_follow_up', 'Kundenantwort auf geschlossenes Ticket', 'Antwort zu geschlossenem Ticket {{Ticket.Number}}', '<p>Hallo {{CustomerUser.FullName}},</p><p>Ihre Nachricht bezieht sich auf das bereits geschlossene Ticket <strong>{{Ticket.Number}}</strong>.</p><p>{{Ticket.LinkHTML}}</p>', 0, 400, 1, 1)
ON DUPLICATE KEY UPDATE
  `name` = VALUES(`name`),
  `sort_order` = VALUES(`sort_order`);
