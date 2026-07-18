-- Qisutu - Open Source Ticket System
-- Copyright (C) 2026 Franziska Steps
-- Qisutu - Kim-KI, https://qisutu.de
--
-- SPDX-FileCopyrightText: 2026 Franziska Steps
-- SPDX-License-Identifier: AGPL-3.0-or-later

CREATE TABLE IF NOT EXISTS `ticket_link` (
  `id` bigint(20) unsigned NOT NULL AUTO_INCREMENT,
  `source_ticket_id` bigint(20) unsigned NOT NULL,
  `target_ticket_id` bigint(20) unsigned NOT NULL,
  `link_type` varchar(30) NOT NULL DEFAULT 'related',
  `source_article_id` bigint(20) unsigned NOT NULL DEFAULT 0,
  `target_article_id` bigint(20) unsigned NOT NULL DEFAULT 0,
  `created_by_user_id` bigint(20) unsigned NOT NULL,
  `created_at` datetime NOT NULL DEFAULT current_timestamp(),
  PRIMARY KEY (`id`),
  UNIQUE KEY `ticket_link_relation_unique` (`source_ticket_id`,`target_ticket_id`,`link_type`,`source_article_id`,`target_article_id`),
  KEY `ticket_link_source` (`source_ticket_id`,`created_at`),
  KEY `ticket_link_target` (`target_ticket_id`,`created_at`),
  KEY `ticket_link_created_by` (`created_by_user_id`),
  CONSTRAINT `ticket_link_source_fk` FOREIGN KEY (`source_ticket_id`) REFERENCES `ticket` (`id`) ON DELETE CASCADE,
  CONSTRAINT `ticket_link_target_fk` FOREIGN KEY (`target_ticket_id`) REFERENCES `ticket` (`id`) ON DELETE CASCADE,
  CONSTRAINT `ticket_link_created_by_fk` FOREIGN KEY (`created_by_user_id`) REFERENCES `user_account` (`id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE IF NOT EXISTS `ticket_article_origin` (
  `id` bigint(20) unsigned NOT NULL AUTO_INCREMENT,
  `ticket_link_id` bigint(20) unsigned NOT NULL,
  `source_ticket_id` bigint(20) unsigned NOT NULL,
  `source_article_id` bigint(20) unsigned NOT NULL,
  `target_ticket_id` bigint(20) unsigned NOT NULL,
  `target_article_id` bigint(20) unsigned NOT NULL,
  `origin_type` varchar(30) NOT NULL,
  `created_by_user_id` bigint(20) unsigned NOT NULL,
  `created_at` datetime NOT NULL DEFAULT current_timestamp(),
  PRIMARY KEY (`id`),
  UNIQUE KEY `ticket_article_origin_target_unique` (`target_article_id`),
  KEY `ticket_article_origin_source` (`source_ticket_id`,`source_article_id`),
  KEY `ticket_article_origin_target` (`target_ticket_id`,`target_article_id`),
  KEY `ticket_article_origin_link` (`ticket_link_id`),
  KEY `ticket_article_origin_created_by` (`created_by_user_id`),
  CONSTRAINT `ticket_article_origin_link_fk` FOREIGN KEY (`ticket_link_id`) REFERENCES `ticket_link` (`id`) ON DELETE CASCADE,
  CONSTRAINT `ticket_article_origin_source_ticket_fk` FOREIGN KEY (`source_ticket_id`) REFERENCES `ticket` (`id`) ON DELETE CASCADE,
  CONSTRAINT `ticket_article_origin_source_article_fk` FOREIGN KEY (`source_article_id`) REFERENCES `ticket_article` (`id`) ON DELETE CASCADE,
  CONSTRAINT `ticket_article_origin_target_ticket_fk` FOREIGN KEY (`target_ticket_id`) REFERENCES `ticket` (`id`) ON DELETE CASCADE,
  CONSTRAINT `ticket_article_origin_target_article_fk` FOREIGN KEY (`target_article_id`) REFERENCES `ticket_article` (`id`) ON DELETE CASCADE,
  CONSTRAINT `ticket_article_origin_created_by_fk` FOREIGN KEY (`created_by_user_id`) REFERENCES `user_account` (`id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;
