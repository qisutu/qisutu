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

CREATE TABLE IF NOT EXISTS `communication_log` (
  `id` bigint(20) unsigned NOT NULL AUTO_INCREMENT,
  `trace_id` char(64) NOT NULL,
  `parent_id` bigint(20) unsigned DEFAULT NULL,
  `protocol` varchar(20) NOT NULL,
  `direction` varchar(20) NOT NULL,
  `operation` varchar(50) NOT NULL,
  `status` varchar(20) NOT NULL DEFAULT 'running',
  `account_type` varchar(20) DEFAULT NULL,
  `account_id` bigint(20) unsigned DEFAULT NULL,
  `account_name` varchar(190) DEFAULT NULL,
  `account_email` varchar(255) DEFAULT NULL,
  `server_host` varchar(255) DEFAULT NULL,
  `server_port` int(10) unsigned DEFAULT NULL,
  `connection_security` varchar(50) DEFAULT NULL,
  `ticket_id` bigint(20) unsigned DEFAULT NULL,
  `article_id` bigint(20) unsigned DEFAULT NULL,
  `message_id` varchar(500) DEFAULT NULL,
  `sender_email` varchar(500) DEFAULT NULL,
  `recipient_email` varchar(1000) DEFAULT NULL,
  `subject` varchar(500) DEFAULT NULL,
  `result_summary` text DEFAULT NULL,
  `error_message` text DEFAULT NULL,
  `messages_found` int(10) unsigned NOT NULL DEFAULT 0,
  `messages_processed` int(10) unsigned NOT NULL DEFAULT 0,
  `messages_created` int(10) unsigned NOT NULL DEFAULT 0,
  `messages_updated` int(10) unsigned NOT NULL DEFAULT 0,
  `messages_ignored` int(10) unsigned NOT NULL DEFAULT 0,
  `messages_failed` int(10) unsigned NOT NULL DEFAULT 0,
  `messages_sent` int(10) unsigned NOT NULL DEFAULT 0,
  `bytes_transferred` bigint(20) unsigned NOT NULL DEFAULT 0,
  `duration_ms` bigint(20) unsigned DEFAULT NULL,
  `started_at` datetime(6) NOT NULL DEFAULT current_timestamp(6),
  `finished_at` datetime(6) DEFAULT NULL,
  `created_at` datetime(6) NOT NULL DEFAULT current_timestamp(6),
  PRIMARY KEY (`id`),
  UNIQUE KEY `communication_log_trace_unique` (`trace_id`),
  KEY `communication_log_started_status` (`started_at`,`status`,`id`),
  KEY `communication_log_protocol_started` (`protocol`,`started_at`,`id`),
  KEY `communication_log_account_started` (`account_type`,`account_id`,`started_at`,`id`),
  KEY `communication_log_ticket` (`ticket_id`,`started_at`,`id`),
  KEY `communication_log_parent` (`parent_id`,`id`),
  CONSTRAINT `communication_log_parent_fk` FOREIGN KEY (`parent_id`) REFERENCES `communication_log` (`id`) ON DELETE SET NULL
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE IF NOT EXISTS `communication_log_step` (
  `id` bigint(20) unsigned NOT NULL AUTO_INCREMENT,
  `communication_log_id` bigint(20) unsigned NOT NULL,
  `level` varchar(20) NOT NULL DEFAULT 'info',
  `stage` varchar(50) NOT NULL DEFAULT 'processing',
  `message` varchar(2000) NOT NULL,
  `technical_details` longtext DEFAULT NULL,
  `created_at` datetime(6) NOT NULL DEFAULT current_timestamp(6),
  PRIMARY KEY (`id`),
  KEY `communication_log_step_log_created` (`communication_log_id`,`created_at`,`id`),
  CONSTRAINT `communication_log_step_log_fk` FOREIGN KEY (`communication_log_id`) REFERENCES `communication_log` (`id`) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

INSERT INTO system_setting (setting_key, setting_value, created_by_user_id, changed_by_user_id)
VALUES ('mail.communication_log_retention_days', '90', 1, 1)
ON DUPLICATE KEY UPDATE setting_key = VALUES(setting_key);
