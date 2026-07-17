-- Qisutu - Open Source Ticket System
-- Copyright (C) 2026 Franziska Steps
-- Qisutu - Kim-KI, https://qisutu.de
--
-- SPDX-FileCopyrightText: 2026 Franziska Steps
-- SPDX-License-Identifier: AGPL-3.0-or-later

CREATE TABLE IF NOT EXISTS `time_accounting_activity_type` (
  `id` bigint(20) unsigned NOT NULL AUTO_INCREMENT,
  `name` varchar(255) NOT NULL,
  `active` tinyint(1) NOT NULL DEFAULT 1,
  `is_default` tinyint(1) NOT NULL DEFAULT 0,
  `sort_order` int(10) unsigned NOT NULL DEFAULT 1000,
  `created_by_user_id` bigint(20) unsigned NOT NULL,
  `changed_by_user_id` bigint(20) unsigned NOT NULL,
  `created_at` datetime NOT NULL DEFAULT current_timestamp(),
  `changed_at` datetime NOT NULL DEFAULT current_timestamp(),
  PRIMARY KEY (`id`),
  UNIQUE KEY `time_accounting_activity_type_name_unique` (`name`),
  KEY `time_accounting_activity_type_active_sort` (`active`,`sort_order`,`name`),
  KEY `time_accounting_activity_type_created_by` (`created_by_user_id`),
  KEY `time_accounting_activity_type_changed_by` (`changed_by_user_id`),
  CONSTRAINT `time_accounting_activity_type_created_by_fk` FOREIGN KEY (`created_by_user_id`) REFERENCES `user_account` (`id`),
  CONSTRAINT `time_accounting_activity_type_changed_by_fk` FOREIGN KEY (`changed_by_user_id`) REFERENCES `user_account` (`id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE IF NOT EXISTS `ticket_time_accounting` (
  `id` bigint(20) unsigned NOT NULL AUTO_INCREMENT,
  `ticket_id` bigint(20) unsigned NOT NULL,
  `ticket_article_id` bigint(20) unsigned DEFAULT NULL,
  `agent_user_id` bigint(20) unsigned NOT NULL,
  `activity_type_id` bigint(20) unsigned DEFAULT NULL,
  `correction_of_time_accounting_id` bigint(20) unsigned DEFAULT NULL,
  `work_date` date NOT NULL,
  `duration_minutes` int(10) unsigned NOT NULL,
  `is_billable` tinyint(1) NOT NULL DEFAULT 0,
  `source` varchar(50) NOT NULL DEFAULT 'manual',
  `description` text DEFAULT NULL,
  `queue_id_snapshot` bigint(20) unsigned DEFAULT NULL,
  `customer_id_snapshot` bigint(20) unsigned DEFAULT NULL,
  `customer_user_id_snapshot` bigint(20) unsigned DEFAULT NULL,
  `created_by_user_id` bigint(20) unsigned NOT NULL,
  `created_at` datetime NOT NULL DEFAULT current_timestamp(),
  PRIMARY KEY (`id`),
  KEY `ticket_time_accounting_ticket_date` (`ticket_id`,`work_date`,`id`),
  KEY `ticket_time_accounting_agent_date` (`agent_user_id`,`work_date`),
  KEY `ticket_time_accounting_activity_date` (`activity_type_id`,`work_date`),
  KEY `ticket_time_accounting_billable_date` (`is_billable`,`work_date`),
  KEY `ticket_time_accounting_queue_snapshot` (`queue_id_snapshot`,`work_date`),
  KEY `ticket_time_accounting_customer_snapshot` (`customer_id_snapshot`,`work_date`),
  KEY `ticket_time_accounting_customer_user_snapshot` (`customer_user_id_snapshot`,`work_date`),
  KEY `ticket_time_accounting_article` (`ticket_article_id`),
  KEY `ticket_time_accounting_correction` (`correction_of_time_accounting_id`),
  KEY `ticket_time_accounting_created_by` (`created_by_user_id`),
  CONSTRAINT `ticket_time_accounting_ticket_fk` FOREIGN KEY (`ticket_id`) REFERENCES `ticket` (`id`) ON DELETE CASCADE,
  CONSTRAINT `ticket_time_accounting_article_fk` FOREIGN KEY (`ticket_article_id`) REFERENCES `ticket_article` (`id`) ON DELETE SET NULL,
  CONSTRAINT `ticket_time_accounting_agent_fk` FOREIGN KEY (`agent_user_id`) REFERENCES `user_account` (`id`),
  CONSTRAINT `ticket_time_accounting_activity_fk` FOREIGN KEY (`activity_type_id`) REFERENCES `time_accounting_activity_type` (`id`) ON DELETE SET NULL,
  CONSTRAINT `ticket_time_accounting_correction_fk` FOREIGN KEY (`correction_of_time_accounting_id`) REFERENCES `ticket_time_accounting` (`id`),
  CONSTRAINT `ticket_time_accounting_created_by_fk` FOREIGN KEY (`created_by_user_id`) REFERENCES `user_account` (`id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE IF NOT EXISTS `ticket_time_accounting_cancellation` (
  `id` bigint(20) unsigned NOT NULL AUTO_INCREMENT,
  `time_accounting_id` bigint(20) unsigned NOT NULL,
  `replacement_time_accounting_id` bigint(20) unsigned NOT NULL,
  `reason` text NOT NULL,
  `cancelled_by_user_id` bigint(20) unsigned NOT NULL,
  `cancelled_at` datetime NOT NULL DEFAULT current_timestamp(),
  PRIMARY KEY (`id`),
  UNIQUE KEY `ticket_time_accounting_cancellation_entry_unique` (`time_accounting_id`),
  KEY `ticket_time_accounting_cancellation_replacement` (`replacement_time_accounting_id`),
  CONSTRAINT `ticket_time_accounting_cancellation_entry_fk` FOREIGN KEY (`time_accounting_id`) REFERENCES `ticket_time_accounting` (`id`) ON DELETE CASCADE,
  CONSTRAINT `ticket_time_accounting_cancellation_replacement_fk` FOREIGN KEY (`replacement_time_accounting_id`) REFERENCES `ticket_time_accounting` (`id`),
  CONSTRAINT `ticket_time_accounting_cancellation_user_fk` FOREIGN KEY (`cancelled_by_user_id`) REFERENCES `user_account` (`id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

DROP TRIGGER IF EXISTS `qisutu_time_accounting_immutable_update`;
DROP TRIGGER IF EXISTS `qisutu_time_accounting_immutable_delete`;
DROP TRIGGER IF EXISTS `qisutu_time_accounting_cancellation_immutable_update`;
DROP TRIGGER IF EXISTS `qisutu_time_accounting_cancellation_immutable_delete`;

CREATE TRIGGER `qisutu_time_accounting_immutable_update`
BEFORE UPDATE ON `ticket_time_accounting`
FOR EACH ROW
SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Time accounting entries are immutable; create a correction instead';

CREATE TRIGGER `qisutu_time_accounting_immutable_delete`
BEFORE DELETE ON `ticket_time_accounting`
FOR EACH ROW
SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Time accounting entries are immutable';

CREATE TRIGGER `qisutu_time_accounting_cancellation_immutable_update`
BEFORE UPDATE ON `ticket_time_accounting_cancellation`
FOR EACH ROW
SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Time accounting cancellations are immutable';

CREATE TRIGGER `qisutu_time_accounting_cancellation_immutable_delete`
BEFORE DELETE ON `ticket_time_accounting_cancellation`
FOR EACH ROW
SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Time accounting cancellations are immutable';

INSERT INTO `user_group_permission` (
  `user_group_id`, `permission_key`, `active`, `created_by_user_id`, `changed_by_user_id`
)
SELECT `id`, 'time_accounting.correct', 1, 1, 1
FROM `user_group`
WHERE `name` = 'admin'
ON DUPLICATE KEY UPDATE
  `active` = VALUES(`active`),
  `changed_by_user_id` = VALUES(`changed_by_user_id`),
  `changed_at` = NOW();
