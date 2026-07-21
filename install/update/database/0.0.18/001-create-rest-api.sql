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

-- REST-API access tokens, audit log and idempotency cache.

CREATE TABLE IF NOT EXISTS `api_token` (
  `id` bigint(20) unsigned NOT NULL AUTO_INCREMENT,
  `user_account_id` bigint(20) unsigned NOT NULL,
  `label` varchar(190) NOT NULL,
  `token_prefix` varchar(24) NOT NULL,
  `token_hash` char(64) NOT NULL,
  `scopes_json` text NOT NULL,
  `allowed_ips` text DEFAULT NULL,
  `rate_limit_per_minute` int(10) unsigned NOT NULL DEFAULT 120,
  `active` tinyint(1) NOT NULL DEFAULT 1,
  `expires_at` datetime DEFAULT NULL,
  `last_used_at` datetime DEFAULT NULL,
  `last_used_ip` varchar(45) DEFAULT NULL,
  `created_by_user_id` bigint(20) unsigned NOT NULL,
  `changed_by_user_id` bigint(20) unsigned NOT NULL,
  `created_at` datetime NOT NULL DEFAULT current_timestamp(),
  `changed_at` datetime NOT NULL DEFAULT current_timestamp() ON UPDATE current_timestamp(),
  PRIMARY KEY (`id`),
  UNIQUE KEY `api_token_hash_unique` (`token_hash`),
  KEY `api_token_user_active` (`user_account_id`,`active`,`id`),
  KEY `api_token_prefix` (`token_prefix`),
  CONSTRAINT `api_token_user_fk` FOREIGN KEY (`user_account_id`) REFERENCES `user_account` (`id`),
  CONSTRAINT `api_token_created_by_fk` FOREIGN KEY (`created_by_user_id`) REFERENCES `user_account` (`id`),
  CONSTRAINT `api_token_changed_by_fk` FOREIGN KEY (`changed_by_user_id`) REFERENCES `user_account` (`id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE IF NOT EXISTS `api_request_log` (
  `id` bigint(20) unsigned NOT NULL AUTO_INCREMENT,
  `request_id` char(36) NOT NULL,
  `api_token_id` bigint(20) unsigned DEFAULT NULL,
  `user_account_id` bigint(20) unsigned DEFAULT NULL,
  `method` varchar(10) NOT NULL,
  `request_path` varchar(500) NOT NULL,
  `status_code` smallint(5) unsigned NOT NULL,
  `remote_ip` varchar(45) NOT NULL DEFAULT '',
  `duration_ms` int(10) unsigned NOT NULL DEFAULT 0,
  `result_code` varchar(100) NOT NULL DEFAULT '',
  `resource_type` varchar(50) NOT NULL DEFAULT '',
  `resource_id` bigint(20) unsigned DEFAULT NULL,
  `created_at` datetime NOT NULL DEFAULT current_timestamp(),
  PRIMARY KEY (`id`),
  UNIQUE KEY `api_request_log_request_unique` (`request_id`),
  KEY `api_request_log_token_created` (`api_token_id`,`created_at`,`id`),
  KEY `api_request_log_user_created` (`user_account_id`,`created_at`,`id`),
  KEY `api_request_log_created` (`created_at`,`id`),
  CONSTRAINT `api_request_log_token_fk` FOREIGN KEY (`api_token_id`) REFERENCES `api_token` (`id`) ON DELETE SET NULL,
  CONSTRAINT `api_request_log_user_fk` FOREIGN KEY (`user_account_id`) REFERENCES `user_account` (`id`) ON DELETE SET NULL
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE IF NOT EXISTS `api_idempotency` (
  `id` bigint(20) unsigned NOT NULL AUTO_INCREMENT,
  `api_token_id` bigint(20) unsigned NOT NULL,
  `idempotency_key` varchar(190) NOT NULL,
  `method` varchar(10) NOT NULL,
  `request_path` varchar(500) NOT NULL,
  `request_hash` char(64) NOT NULL,
  `status_code` smallint(5) unsigned NOT NULL,
  `response_json` mediumtext NOT NULL,
  `created_at` datetime NOT NULL DEFAULT current_timestamp(),
  `expires_at` datetime NOT NULL,
  PRIMARY KEY (`id`),
  UNIQUE KEY `api_idempotency_token_key_unique` (`api_token_id`,`idempotency_key`),
  KEY `api_idempotency_expiry` (`expires_at`,`id`),
  CONSTRAINT `api_idempotency_token_fk` FOREIGN KEY (`api_token_id`) REFERENCES `api_token` (`id`) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;
