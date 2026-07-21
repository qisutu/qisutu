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

CREATE TABLE IF NOT EXISTS `ticket_bulk_action` (
  `id` bigint(20) unsigned NOT NULL AUTO_INCREMENT,
  `created_by_user_id` bigint(20) unsigned NOT NULL,
  `change_reason` text DEFAULT NULL,
  `requested_changes_json` longtext NOT NULL,
  `selected_count` int(10) unsigned NOT NULL DEFAULT 0,
  `success_count` int(10) unsigned NOT NULL DEFAULT 0,
  `skipped_count` int(10) unsigned NOT NULL DEFAULT 0,
  `failed_count` int(10) unsigned NOT NULL DEFAULT 0,
  `status` varchar(30) NOT NULL DEFAULT 'running',
  `created_at` datetime NOT NULL DEFAULT current_timestamp(),
  `completed_at` datetime DEFAULT NULL,
  PRIMARY KEY (`id`),
  KEY `ticket_bulk_action_user_created` (`created_by_user_id`,`created_at`,`id`),
  KEY `ticket_bulk_action_status_created` (`status`,`created_at`),
  CONSTRAINT `ticket_bulk_action_user_fk` FOREIGN KEY (`created_by_user_id`) REFERENCES `user_account` (`id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE IF NOT EXISTS `ticket_bulk_action_item` (
  `id` bigint(20) unsigned NOT NULL AUTO_INCREMENT,
  `bulk_action_id` bigint(20) unsigned NOT NULL,
  `ticket_id` bigint(20) unsigned DEFAULT NULL,
  `ticket_number_snapshot` varchar(50) NOT NULL DEFAULT '',
  `result` varchar(30) NOT NULL,
  `error_message` text DEFAULT NULL,
  `changes_json` longtext NOT NULL,
  `created_at` datetime NOT NULL DEFAULT current_timestamp(),
  PRIMARY KEY (`id`),
  KEY `ticket_bulk_action_item_action` (`bulk_action_id`,`id`),
  KEY `ticket_bulk_action_item_ticket` (`ticket_id`,`created_at`,`id`),
  KEY `ticket_bulk_action_item_result` (`result`,`created_at`),
  CONSTRAINT `ticket_bulk_action_item_action_fk` FOREIGN KEY (`bulk_action_id`) REFERENCES `ticket_bulk_action` (`id`) ON DELETE CASCADE,
  CONSTRAINT `ticket_bulk_action_item_ticket_fk` FOREIGN KEY (`ticket_id`) REFERENCES `ticket` (`id`) ON DELETE SET NULL
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

