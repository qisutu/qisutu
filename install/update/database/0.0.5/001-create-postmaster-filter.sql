-- Qisutu - Open Source Ticket System
-- Copyright (C) 2026 Franziska Steps
-- Qisutu - Kim-KI, https://qisutu.de
--
-- SPDX-FileCopyrightText: 2026 Franziska Steps
-- SPDX-License-Identifier: AGPL-3.0-or-later

CREATE TABLE IF NOT EXISTS `postmaster_filter` (
  `id` bigint(20) unsigned NOT NULL AUTO_INCREMENT,
  `name` varchar(190) NOT NULL,
  `description` text DEFAULT NULL,
  `match_mode` varchar(20) NOT NULL DEFAULT 'all',
  `message_scope` varchar(20) NOT NULL DEFAULT 'both',
  `stop_after_match` tinyint(1) NOT NULL DEFAULT 0,
  `active` tinyint(1) NOT NULL DEFAULT 1,
  `sort_order` int(10) unsigned NOT NULL DEFAULT 1000,
  `created_by_user_id` bigint(20) unsigned NOT NULL DEFAULT 1,
  `changed_by_user_id` bigint(20) unsigned NOT NULL DEFAULT 1,
  `created_at` datetime NOT NULL DEFAULT current_timestamp(),
  `changed_at` datetime NOT NULL DEFAULT current_timestamp() ON UPDATE current_timestamp(),
  PRIMARY KEY (`id`),
  UNIQUE KEY `postmaster_filter_name_unique` (`name`),
  KEY `postmaster_filter_active_sort` (`active`,`sort_order`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE IF NOT EXISTS `postmaster_filter_condition` (
  `id` bigint(20) unsigned NOT NULL AUTO_INCREMENT,
  `filter_id` bigint(20) unsigned NOT NULL,
  `field_name` varchar(100) NOT NULL,
  `field_argument` varchar(255) DEFAULT NULL,
  `operator` varchar(40) NOT NULL,
  `match_value` text NOT NULL,
  `case_sensitive` tinyint(1) NOT NULL DEFAULT 0,
  `sort_order` int(10) unsigned NOT NULL DEFAULT 1000,
  `created_by_user_id` bigint(20) unsigned NOT NULL DEFAULT 1,
  `changed_by_user_id` bigint(20) unsigned NOT NULL DEFAULT 1,
  `created_at` datetime NOT NULL DEFAULT current_timestamp(),
  `changed_at` datetime NOT NULL DEFAULT current_timestamp() ON UPDATE current_timestamp(),
  PRIMARY KEY (`id`),
  KEY `postmaster_filter_condition_filter_sort` (`filter_id`,`sort_order`),
  CONSTRAINT `postmaster_filter_condition_filter_fk` FOREIGN KEY (`filter_id`) REFERENCES `postmaster_filter` (`id`) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE IF NOT EXISTS `postmaster_filter_action` (
  `id` bigint(20) unsigned NOT NULL AUTO_INCREMENT,
  `filter_id` bigint(20) unsigned NOT NULL,
  `action_type` varchar(100) NOT NULL,
  `target_id` bigint(20) unsigned DEFAULT NULL,
  `action_value` text NOT NULL,
  `sort_order` int(10) unsigned NOT NULL DEFAULT 1000,
  `created_by_user_id` bigint(20) unsigned NOT NULL DEFAULT 1,
  `changed_by_user_id` bigint(20) unsigned NOT NULL DEFAULT 1,
  `created_at` datetime NOT NULL DEFAULT current_timestamp(),
  `changed_at` datetime NOT NULL DEFAULT current_timestamp() ON UPDATE current_timestamp(),
  PRIMARY KEY (`id`),
  KEY `postmaster_filter_action_filter_sort` (`filter_id`,`sort_order`),
  CONSTRAINT `postmaster_filter_action_filter_fk` FOREIGN KEY (`filter_id`) REFERENCES `postmaster_filter` (`id`) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE IF NOT EXISTS `postmaster_filter_run` (
  `id` bigint(20) unsigned NOT NULL AUTO_INCREMENT,
  `imap_account_id` bigint(20) unsigned DEFAULT NULL,
  `message_uid` varchar(255) DEFAULT NULL,
  `message_scope` varchar(20) NOT NULL DEFAULT 'new',
  `message_subject` varchar(500) DEFAULT NULL,
  `from_email` varchar(255) DEFAULT NULL,
  `ticket_id` bigint(20) unsigned DEFAULT NULL,
  `result` varchar(30) NOT NULL DEFAULT 'processed',
  `filter_count` int(10) unsigned NOT NULL DEFAULT 0,
  `matched_count` int(10) unsigned NOT NULL DEFAULT 0,
  `details_json` longtext DEFAULT NULL,
  `error_message` text DEFAULT NULL,
  `created_at` datetime NOT NULL DEFAULT current_timestamp(),
  PRIMARY KEY (`id`),
  KEY `postmaster_filter_run_created` (`created_at`),
  KEY `postmaster_filter_run_ticket` (`ticket_id`),
  KEY `postmaster_filter_run_account` (`imap_account_id`),
  KEY `postmaster_filter_run_result` (`result`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;
