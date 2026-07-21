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

CREATE TABLE IF NOT EXISTS `user_two_factor` (
  `user_account_id` bigint(20) unsigned NOT NULL,
  `secret_encrypted` text NOT NULL,
  `enabled` tinyint(1) NOT NULL DEFAULT 0,
  `recovery_code_hashes` text DEFAULT NULL,
  `last_used_counter` bigint(20) unsigned DEFAULT NULL,
  `created_at` datetime NOT NULL DEFAULT current_timestamp(),
  `changed_at` datetime NOT NULL DEFAULT current_timestamp() ON UPDATE current_timestamp(),
  PRIMARY KEY (`user_account_id`),
  KEY `user_two_factor_enabled` (`enabled`),
  CONSTRAINT `user_two_factor_user_fk` FOREIGN KEY (`user_account_id`) REFERENCES `user_account` (`id`) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE IF NOT EXISTS `user_two_factor_challenge` (
  `id` bigint(20) unsigned NOT NULL AUTO_INCREMENT,
  `token_hash` char(64) NOT NULL,
  `user_account_id` bigint(20) unsigned NOT NULL,
  `account_type` varchar(20) NOT NULL,
  `mode` varchar(20) NOT NULL DEFAULT 'login',
  `attempts` int(10) unsigned NOT NULL DEFAULT 0,
  `expires_at` datetime NOT NULL,
  `created_at` datetime NOT NULL DEFAULT current_timestamp(),
  PRIMARY KEY (`id`),
  UNIQUE KEY `user_two_factor_challenge_token` (`token_hash`),
  KEY `user_two_factor_challenge_expiry` (`expires_at`),
  CONSTRAINT `user_two_factor_challenge_user_fk` FOREIGN KEY (`user_account_id`) REFERENCES `user_account` (`id`) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

INSERT INTO system_setting (setting_key, setting_value, created_by_user_id, changed_by_user_id)
VALUES
  ('security.2fa.enforce_administrators', '0', 1, 1),
  ('security.2fa.enforce_agents', '0', 1, 1),
  ('security.2fa.enforce_customers', '0', 1, 1)
ON DUPLICATE KEY UPDATE setting_key = VALUES(setting_key);
