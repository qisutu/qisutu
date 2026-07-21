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

CREATE TABLE IF NOT EXISTS `master_data_import_run` (
  `id` bigint(20) unsigned NOT NULL AUTO_INCREMENT,
  `import_type` varchar(30) NOT NULL,
  `file_name` varchar(255) NOT NULL,
  `file_sha256` char(64) NOT NULL,
  `analysis_sha256` char(64) NOT NULL,
  `status` varchar(30) NOT NULL DEFAULT 'pending',
  `staged_content` longtext DEFAULT NULL,
  `total_count` int(10) unsigned NOT NULL DEFAULT 0,
  `created_count` int(10) unsigned NOT NULL DEFAULT 0,
  `updated_count` int(10) unsigned NOT NULL DEFAULT 0,
  `unchanged_count` int(10) unsigned NOT NULL DEFAULT 0,
  `error_count` int(10) unsigned NOT NULL DEFAULT 0,
  `invitation_count` int(10) unsigned NOT NULL DEFAULT 0,
  `error_summary` longtext DEFAULT NULL,
  `created_by_user_id` bigint(20) unsigned NOT NULL,
  `created_at` datetime NOT NULL DEFAULT current_timestamp(),
  `expires_at` datetime NOT NULL,
  `imported_at` datetime DEFAULT NULL,
  PRIMARY KEY (`id`),
  KEY `master_data_import_type_created` (`import_type`,`created_at`,`id`),
  KEY `master_data_import_status_expires` (`status`,`expires_at`,`id`),
  KEY `master_data_import_created_by` (`created_by_user_id`),
  CONSTRAINT `master_data_import_created_by_fk` FOREIGN KEY (`created_by_user_id`) REFERENCES `user_account` (`id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE IF NOT EXISTS `master_data_import_item` (
  `id` bigint(20) unsigned NOT NULL AUTO_INCREMENT,
  `run_id` bigint(20) unsigned NOT NULL,
  `row_number` int(10) unsigned NOT NULL,
  `record_key` varchar(255) NOT NULL DEFAULT '',
  `action` varchar(20) NOT NULL,
  `message` text DEFAULT NULL,
  `created_at` datetime NOT NULL DEFAULT current_timestamp(),
  PRIMARY KEY (`id`),
  KEY `master_data_import_item_run_action` (`run_id`,`action`,`row_number`,`id`),
  CONSTRAINT `master_data_import_item_run_fk` FOREIGN KEY (`run_id`) REFERENCES `master_data_import_run` (`id`) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;
