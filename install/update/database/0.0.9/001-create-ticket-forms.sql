-- Qisutu - Open Source Ticket System
-- Copyright (C) 2026 Franziska Steps
-- Qisutu - Kim-KI, https://qisutu.de
--
-- SPDX-FileCopyrightText: 2026 Franziska Steps
-- SPDX-License-Identifier: AGPL-3.0-or-later

CREATE TABLE IF NOT EXISTS `ticket_form` (
  `id` bigint(20) unsigned NOT NULL AUTO_INCREMENT,
  `internal_name` varchar(190) NOT NULL,
  `form_type` varchar(20) NOT NULL DEFAULT 'customer',
  `slug` varchar(100) NOT NULL,
  `queue_id` bigint(20) unsigned NOT NULL,
  `all_customers` tinyint(1) NOT NULL DEFAULT 1,
  `require_consent` tinyint(1) NOT NULL DEFAULT 0,
  `allowed_origins` text DEFAULT NULL,
  `rate_limit_hour` int(10) unsigned NOT NULL DEFAULT 20,
  `rate_limit_day` int(10) unsigned NOT NULL DEFAULT 240,
  `rate_limit_total_day` int(10) unsigned NOT NULL DEFAULT 5000,
  `active` tinyint(1) NOT NULL DEFAULT 1,
  `sort_order` int(10) unsigned NOT NULL DEFAULT 1000,
  `form_version` int(10) unsigned NOT NULL DEFAULT 1,
  `created_by_user_id` bigint(20) unsigned NOT NULL,
  `changed_by_user_id` bigint(20) unsigned NOT NULL,
  `created_at` datetime NOT NULL DEFAULT current_timestamp(),
  `changed_at` datetime NOT NULL DEFAULT current_timestamp() ON UPDATE current_timestamp(),
  PRIMARY KEY (`id`),
  UNIQUE KEY `ticket_form_slug_unique` (`slug`),
  KEY `ticket_form_type_active_sort` (`form_type`,`active`,`sort_order`,`id`),
  KEY `ticket_form_queue` (`queue_id`),
  KEY `ticket_form_created_by` (`created_by_user_id`),
  KEY `ticket_form_changed_by` (`changed_by_user_id`),
  CONSTRAINT `ticket_form_queue_fk` FOREIGN KEY (`queue_id`) REFERENCES `ticket_queue` (`id`),
  CONSTRAINT `ticket_form_created_by_fk` FOREIGN KEY (`created_by_user_id`) REFERENCES `user_account` (`id`),
  CONSTRAINT `ticket_form_changed_by_fk` FOREIGN KEY (`changed_by_user_id`) REFERENCES `user_account` (`id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE IF NOT EXISTS `ticket_form_translation` (
  `id` bigint(20) unsigned NOT NULL AUTO_INCREMENT,
  `form_id` bigint(20) unsigned NOT NULL,
  `language` varchar(20) NOT NULL,
  `title` varchar(255) NOT NULL,
  `description` text DEFAULT NULL,
  `submit_label` varchar(100) NOT NULL,
  `confirmation_text` text NOT NULL,
  `consent_text` text DEFAULT NULL,
  `created_by_user_id` bigint(20) unsigned NOT NULL,
  `changed_by_user_id` bigint(20) unsigned NOT NULL,
  `created_at` datetime NOT NULL DEFAULT current_timestamp(),
  `changed_at` datetime NOT NULL DEFAULT current_timestamp() ON UPDATE current_timestamp(),
  PRIMARY KEY (`id`),
  UNIQUE KEY `ticket_form_translation_form_language` (`form_id`,`language`),
  KEY `ticket_form_translation_language` (`language`),
  CONSTRAINT `ticket_form_translation_form_fk` FOREIGN KEY (`form_id`) REFERENCES `ticket_form` (`id`) ON DELETE CASCADE,
  CONSTRAINT `ticket_form_translation_created_by_fk` FOREIGN KEY (`created_by_user_id`) REFERENCES `user_account` (`id`),
  CONSTRAINT `ticket_form_translation_changed_by_fk` FOREIGN KEY (`changed_by_user_id`) REFERENCES `user_account` (`id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE IF NOT EXISTS `ticket_form_customer` (
  `form_id` bigint(20) unsigned NOT NULL,
  `customer_id` bigint(20) unsigned NOT NULL,
  `created_by_user_id` bigint(20) unsigned NOT NULL,
  `created_at` datetime NOT NULL DEFAULT current_timestamp(),
  PRIMARY KEY (`form_id`,`customer_id`),
  KEY `ticket_form_customer_customer` (`customer_id`,`form_id`),
  CONSTRAINT `ticket_form_customer_form_fk` FOREIGN KEY (`form_id`) REFERENCES `ticket_form` (`id`) ON DELETE CASCADE,
  CONSTRAINT `ticket_form_customer_customer_fk` FOREIGN KEY (`customer_id`) REFERENCES `customer` (`id`) ON DELETE CASCADE,
  CONSTRAINT `ticket_form_customer_created_by_fk` FOREIGN KEY (`created_by_user_id`) REFERENCES `user_account` (`id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE IF NOT EXISTS `ticket_form_field` (
  `id` bigint(20) unsigned NOT NULL AUTO_INCREMENT,
  `form_id` bigint(20) unsigned NOT NULL,
  `field_key` varchar(100) NOT NULL,
  `field_type` varchar(30) NOT NULL DEFAULT 'text',
  `dynamic_field_id` bigint(20) unsigned DEFAULT NULL,
  `is_required` tinyint(1) NOT NULL DEFAULT 0,
  `default_value` text DEFAULT NULL,
  `active` tinyint(1) NOT NULL DEFAULT 1,
  `sort_order` int(10) unsigned NOT NULL DEFAULT 1000,
  `created_by_user_id` bigint(20) unsigned NOT NULL,
  `changed_by_user_id` bigint(20) unsigned NOT NULL,
  `created_at` datetime NOT NULL DEFAULT current_timestamp(),
  `changed_at` datetime NOT NULL DEFAULT current_timestamp() ON UPDATE current_timestamp(),
  PRIMARY KEY (`id`),
  UNIQUE KEY `ticket_form_field_form_key` (`form_id`,`field_key`),
  KEY `ticket_form_field_form_active_sort` (`form_id`,`active`,`sort_order`,`id`),
  KEY `ticket_form_field_dynamic` (`dynamic_field_id`),
  CONSTRAINT `ticket_form_field_form_fk` FOREIGN KEY (`form_id`) REFERENCES `ticket_form` (`id`) ON DELETE CASCADE,
  CONSTRAINT `ticket_form_field_dynamic_fk` FOREIGN KEY (`dynamic_field_id`) REFERENCES `ticket_dynamic_field` (`id`) ON DELETE SET NULL,
  CONSTRAINT `ticket_form_field_created_by_fk` FOREIGN KEY (`created_by_user_id`) REFERENCES `user_account` (`id`),
  CONSTRAINT `ticket_form_field_changed_by_fk` FOREIGN KEY (`changed_by_user_id`) REFERENCES `user_account` (`id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE IF NOT EXISTS `ticket_form_field_translation` (
  `id` bigint(20) unsigned NOT NULL AUTO_INCREMENT,
  `form_field_id` bigint(20) unsigned NOT NULL,
  `language` varchar(20) NOT NULL,
  `label` varchar(255) NOT NULL,
  `help_text` text DEFAULT NULL,
  `placeholder` varchar(255) DEFAULT NULL,
  `created_by_user_id` bigint(20) unsigned NOT NULL,
  `changed_by_user_id` bigint(20) unsigned NOT NULL,
  `created_at` datetime NOT NULL DEFAULT current_timestamp(),
  `changed_at` datetime NOT NULL DEFAULT current_timestamp() ON UPDATE current_timestamp(),
  PRIMARY KEY (`id`),
  UNIQUE KEY `ticket_form_field_translation_field_language` (`form_field_id`,`language`),
  KEY `ticket_form_field_translation_language` (`language`),
  CONSTRAINT `ticket_form_field_translation_field_fk` FOREIGN KEY (`form_field_id`) REFERENCES `ticket_form_field` (`id`) ON DELETE CASCADE,
  CONSTRAINT `ticket_form_field_translation_created_by_fk` FOREIGN KEY (`created_by_user_id`) REFERENCES `user_account` (`id`),
  CONSTRAINT `ticket_form_field_translation_changed_by_fk` FOREIGN KEY (`changed_by_user_id`) REFERENCES `user_account` (`id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE IF NOT EXISTS `ticket_form_submission` (
  `id` bigint(20) unsigned NOT NULL AUTO_INCREMENT,
  `ticket_id` bigint(20) unsigned NOT NULL,
  `form_id` bigint(20) unsigned DEFAULT NULL,
  `form_name_snapshot` varchar(190) NOT NULL,
  `form_title_snapshot` varchar(255) NOT NULL,
  `form_version` int(10) unsigned NOT NULL DEFAULT 1,
  `source` varchar(30) NOT NULL,
  `submitter_name` varchar(255) DEFAULT NULL,
  `submitter_email` varchar(255) DEFAULT NULL,
  `remote_ip_hash` char(64) DEFAULT NULL,
  `user_agent` varchar(255) DEFAULT NULL,
  `created_at` datetime NOT NULL DEFAULT current_timestamp(),
  PRIMARY KEY (`id`),
  UNIQUE KEY `ticket_form_submission_ticket_unique` (`ticket_id`),
  KEY `ticket_form_submission_form_created` (`form_id`,`created_at`,`id`),
  KEY `ticket_form_submission_source_created` (`source`,`created_at`,`id`),
  KEY `ticket_form_submission_ip_created` (`remote_ip_hash`,`created_at`),
  CONSTRAINT `ticket_form_submission_ticket_fk` FOREIGN KEY (`ticket_id`) REFERENCES `ticket` (`id`) ON DELETE CASCADE,
  CONSTRAINT `ticket_form_submission_form_fk` FOREIGN KEY (`form_id`) REFERENCES `ticket_form` (`id`) ON DELETE SET NULL
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE IF NOT EXISTS `ticket_form_submission_value` (
  `id` bigint(20) unsigned NOT NULL AUTO_INCREMENT,
  `submission_id` bigint(20) unsigned NOT NULL,
  `form_field_id` bigint(20) unsigned DEFAULT NULL,
  `dynamic_field_id` bigint(20) unsigned DEFAULT NULL,
  `field_key` varchar(100) NOT NULL,
  `label_snapshot` varchar(255) NOT NULL,
  `field_type_snapshot` varchar(30) NOT NULL,
  `value_text` text DEFAULT NULL,
  `display_value_text` text DEFAULT NULL,
  `sort_order` int(10) unsigned NOT NULL DEFAULT 1000,
  `created_at` datetime NOT NULL DEFAULT current_timestamp(),
  PRIMARY KEY (`id`),
  KEY `ticket_form_submission_value_submission_sort` (`submission_id`,`sort_order`,`id`),
  KEY `ticket_form_submission_value_form_field` (`form_field_id`),
  KEY `ticket_form_submission_value_dynamic` (`dynamic_field_id`),
  CONSTRAINT `ticket_form_submission_value_submission_fk` FOREIGN KEY (`submission_id`) REFERENCES `ticket_form_submission` (`id`) ON DELETE CASCADE,
  CONSTRAINT `ticket_form_submission_value_form_field_fk` FOREIGN KEY (`form_field_id`) REFERENCES `ticket_form_field` (`id`) ON DELETE SET NULL,
  CONSTRAINT `ticket_form_submission_value_dynamic_fk` FOREIGN KEY (`dynamic_field_id`) REFERENCES `ticket_dynamic_field` (`id`) ON DELETE SET NULL
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;
