-- Qisutu - Open Source Ticket System
-- SPDX-License-Identifier: AGPL-3.0-or-later
-- Flexible, permission-aware report definitions and execution audit.

CREATE TABLE IF NOT EXISTS `report_definition` (
  `id` bigint(20) unsigned NOT NULL AUTO_INCREMENT,
  `owner_user_id` bigint(20) unsigned NOT NULL,
  `name` varchar(190) NOT NULL,
  `description` text DEFAULT NULL,
  `data_source` varchar(30) NOT NULL,
  `configuration_json` mediumtext NOT NULL,
  `visibility` varchar(20) NOT NULL DEFAULT 'private',
  `active` tinyint(1) NOT NULL DEFAULT 1,
  `created_by_user_id` bigint(20) unsigned NOT NULL,
  `changed_by_user_id` bigint(20) unsigned NOT NULL,
  `created_at` datetime NOT NULL DEFAULT current_timestamp(),
  `changed_at` datetime NOT NULL DEFAULT current_timestamp() ON UPDATE current_timestamp(),
  PRIMARY KEY (`id`),
  KEY `report_definition_owner_active` (`owner_user_id`,`active`,`changed_at`,`id`),
  KEY `report_definition_visibility_active` (`visibility`,`active`,`changed_at`,`id`),
  CONSTRAINT `report_definition_owner_fk` FOREIGN KEY (`owner_user_id`) REFERENCES `user_account` (`id`),
  CONSTRAINT `report_definition_created_by_fk` FOREIGN KEY (`created_by_user_id`) REFERENCES `user_account` (`id`),
  CONSTRAINT `report_definition_changed_by_fk` FOREIGN KEY (`changed_by_user_id`) REFERENCES `user_account` (`id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE IF NOT EXISTS `report_definition_group` (
  `report_definition_id` bigint(20) unsigned NOT NULL,
  `user_group_id` bigint(20) unsigned NOT NULL,
  `created_by_user_id` bigint(20) unsigned NOT NULL,
  `created_at` datetime NOT NULL DEFAULT current_timestamp(),
  PRIMARY KEY (`report_definition_id`,`user_group_id`),
  KEY `report_definition_group_group` (`user_group_id`,`report_definition_id`),
  CONSTRAINT `report_definition_group_report_fk` FOREIGN KEY (`report_definition_id`) REFERENCES `report_definition` (`id`) ON DELETE CASCADE,
  CONSTRAINT `report_definition_group_group_fk` FOREIGN KEY (`user_group_id`) REFERENCES `user_group` (`id`) ON DELETE CASCADE,
  CONSTRAINT `report_definition_group_created_by_fk` FOREIGN KEY (`created_by_user_id`) REFERENCES `user_account` (`id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE IF NOT EXISTS `report_execution_log` (
  `id` bigint(20) unsigned NOT NULL AUTO_INCREMENT,
  `report_definition_id` bigint(20) unsigned DEFAULT NULL,
  `user_account_id` bigint(20) unsigned NOT NULL,
  `execution_type` varchar(20) NOT NULL,
  `data_source` varchar(30) NOT NULL,
  `result_rows` int(10) unsigned NOT NULL DEFAULT 0,
  `duration_ms` int(10) unsigned NOT NULL DEFAULT 0,
  `was_limited` tinyint(1) NOT NULL DEFAULT 0,
  `created_at` datetime NOT NULL DEFAULT current_timestamp(),
  PRIMARY KEY (`id`),
  KEY `report_execution_log_report` (`report_definition_id`,`created_at`,`id`),
  KEY `report_execution_log_user` (`user_account_id`,`created_at`,`id`),
  CONSTRAINT `report_execution_log_report_fk` FOREIGN KEY (`report_definition_id`) REFERENCES `report_definition` (`id`) ON DELETE SET NULL,
  CONSTRAINT `report_execution_log_user_fk` FOREIGN KEY (`user_account_id`) REFERENCES `user_account` (`id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;
