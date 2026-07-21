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

-- Qisutu 0.0.23: central LDAP / Active Directory authentication for agents.

SET @qisutu_column_exists = (
  SELECT COUNT(*)
  FROM information_schema.COLUMNS
  WHERE TABLE_SCHEMA = DATABASE()
    AND TABLE_NAME = 'user_account'
    AND COLUMN_NAME = 'authentication_type'
);
SET @qisutu_sql = IF(
  @qisutu_column_exists = 0,
  'ALTER TABLE `user_account` ADD COLUMN `authentication_type` varchar(20) NOT NULL DEFAULT ''local'' AFTER `account_type`',
  'SELECT 1'
);
PREPARE qisutu_stmt FROM @qisutu_sql;
EXECUTE qisutu_stmt;
DEALLOCATE PREPARE qisutu_stmt;

CREATE TABLE IF NOT EXISTS `ldap_configuration` (
  `id` bigint(20) unsigned NOT NULL AUTO_INCREMENT,
  `name` varchar(100) NOT NULL DEFAULT 'LDAP / Active Directory',
  `directory_type` varchar(20) NOT NULL DEFAULT 'active_directory',
  `host` varchar(255) NOT NULL,
  `port` int(10) unsigned NOT NULL DEFAULT 636,
  `connection_security` varchar(20) NOT NULL DEFAULT 'ldaps',
  `verify_certificate` tinyint(1) NOT NULL DEFAULT 1,
  `ca_file` varchar(500) NOT NULL DEFAULT '',
  `bind_dn` varchar(1000) NOT NULL DEFAULT '',
  `bind_password_encrypted` text DEFAULT NULL,
  `base_dn` varchar(1000) NOT NULL,
  `user_filter` varchar(2000) NOT NULL DEFAULT '(objectClass=person)',
  `login_attribute` varchar(100) NOT NULL,
  `firstname_attribute` varchar(100) NOT NULL,
  `lastname_attribute` varchar(100) NOT NULL,
  `email_attribute` varchar(100) NOT NULL,
  `default_group_id` bigint(20) unsigned DEFAULT NULL,
  `update_on_login` tinyint(1) NOT NULL DEFAULT 1,
  `active` tinyint(1) NOT NULL DEFAULT 0,
  `last_test_at` datetime DEFAULT NULL,
  `last_test_status` varchar(20) NOT NULL DEFAULT '',
  `last_test_message` text DEFAULT NULL,
  `created_by_user_id` bigint(20) unsigned NOT NULL DEFAULT 1,
  `changed_by_user_id` bigint(20) unsigned NOT NULL DEFAULT 1,
  `created_at` datetime NOT NULL DEFAULT current_timestamp(),
  `changed_at` datetime NOT NULL DEFAULT current_timestamp() ON UPDATE current_timestamp(),
  PRIMARY KEY (`id`),
  KEY `ldap_configuration_active` (`active`),
  KEY `ldap_configuration_default_group` (`default_group_id`),
  CONSTRAINT `ldap_configuration_default_group_fk` FOREIGN KEY (`default_group_id`) REFERENCES `user_group` (`id`) ON DELETE SET NULL
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE IF NOT EXISTS `ldap_field_mapping` (
  `id` bigint(20) unsigned NOT NULL AUTO_INCREMENT,
  `ldap_configuration_id` bigint(20) unsigned NOT NULL,
  `object_type` varchar(50) NOT NULL,
  `field_id` bigint(20) unsigned NOT NULL,
  `ldap_attribute` varchar(100) NOT NULL,
  `is_required` tinyint(1) NOT NULL DEFAULT 0,
  `update_on_login` tinyint(1) NOT NULL DEFAULT 1,
  `clear_empty` tinyint(1) NOT NULL DEFAULT 0,
  `created_by_user_id` bigint(20) unsigned NOT NULL DEFAULT 1,
  `changed_by_user_id` bigint(20) unsigned NOT NULL DEFAULT 1,
  `created_at` datetime NOT NULL DEFAULT current_timestamp(),
  `changed_at` datetime NOT NULL DEFAULT current_timestamp() ON UPDATE current_timestamp(),
  PRIMARY KEY (`id`),
  UNIQUE KEY `ldap_field_mapping_unique` (`ldap_configuration_id`,`object_type`,`field_id`),
  KEY `ldap_field_mapping_field` (`field_id`),
  CONSTRAINT `ldap_field_mapping_configuration_fk` FOREIGN KEY (`ldap_configuration_id`) REFERENCES `ldap_configuration` (`id`) ON DELETE CASCADE,
  CONSTRAINT `ldap_field_mapping_field_fk` FOREIGN KEY (`field_id`) REFERENCES `user_dynamic_field` (`id`) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;
