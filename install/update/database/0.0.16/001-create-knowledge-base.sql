-- Qisutu knowledge base
-- SPDX-License-Identifier: AGPL-3.0-or-later

CREATE TABLE IF NOT EXISTS `knowledge_category` (
  `id` bigint(20) unsigned NOT NULL AUTO_INCREMENT,
  `parent_id` bigint(20) unsigned DEFAULT NULL,
  `internal_name` varchar(190) NOT NULL,
  `active` tinyint(1) NOT NULL DEFAULT 1,
  `sort_order` int(10) unsigned NOT NULL DEFAULT 1000,
  `created_by_user_id` bigint(20) unsigned NOT NULL,
  `changed_by_user_id` bigint(20) unsigned NOT NULL,
  `created_at` datetime NOT NULL DEFAULT current_timestamp(),
  `changed_at` datetime NOT NULL DEFAULT current_timestamp() ON UPDATE current_timestamp(),
  PRIMARY KEY (`id`),
  UNIQUE KEY `knowledge_category_internal_name_unique` (`internal_name`),
  KEY `knowledge_category_parent_sort` (`parent_id`,`active`,`sort_order`,`id`),
  CONSTRAINT `knowledge_category_parent_fk` FOREIGN KEY (`parent_id`) REFERENCES `knowledge_category` (`id`) ON DELETE SET NULL,
  CONSTRAINT `knowledge_category_created_by_fk` FOREIGN KEY (`created_by_user_id`) REFERENCES `user_account` (`id`),
  CONSTRAINT `knowledge_category_changed_by_fk` FOREIGN KEY (`changed_by_user_id`) REFERENCES `user_account` (`id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE IF NOT EXISTS `knowledge_category_translation` (
  `id` bigint(20) unsigned NOT NULL AUTO_INCREMENT,
  `category_id` bigint(20) unsigned NOT NULL,
  `language` varchar(20) NOT NULL,
  `name` varchar(190) NOT NULL,
  `description` text DEFAULT NULL,
  `created_by_user_id` bigint(20) unsigned NOT NULL,
  `changed_by_user_id` bigint(20) unsigned NOT NULL,
  `created_at` datetime NOT NULL DEFAULT current_timestamp(),
  `changed_at` datetime NOT NULL DEFAULT current_timestamp() ON UPDATE current_timestamp(),
  PRIMARY KEY (`id`),
  UNIQUE KEY `knowledge_category_translation_unique` (`category_id`,`language`),
  KEY `knowledge_category_translation_language` (`language`,`name`),
  CONSTRAINT `knowledge_category_translation_category_fk` FOREIGN KEY (`category_id`) REFERENCES `knowledge_category` (`id`) ON DELETE CASCADE,
  CONSTRAINT `knowledge_category_translation_created_by_fk` FOREIGN KEY (`created_by_user_id`) REFERENCES `user_account` (`id`),
  CONSTRAINT `knowledge_category_translation_changed_by_fk` FOREIGN KEY (`changed_by_user_id`) REFERENCES `user_account` (`id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE IF NOT EXISTS `knowledge_article` (
  `id` bigint(20) unsigned NOT NULL AUTO_INCREMENT,
  `article_number` varchar(40) NOT NULL DEFAULT '',
  `category_id` bigint(20) unsigned NOT NULL,
  `language` varchar(20) NOT NULL DEFAULT 'en',
  `title` varchar(255) NOT NULL,
  `summary` text DEFAULT NULL,
  `keywords` text DEFAULT NULL,
  `content` longtext NOT NULL,
  `search_text` longtext NOT NULL,
  `visibility` varchar(20) NOT NULL DEFAULT 'internal',
  `customer_scope` varchar(20) NOT NULL DEFAULT 'all',
  `status` varchar(20) NOT NULL DEFAULT 'draft',
  `revision_number` int(10) unsigned NOT NULL DEFAULT 1,
  `published_at` datetime DEFAULT NULL,
  `published_by_user_id` bigint(20) unsigned DEFAULT NULL,
  `created_by_user_id` bigint(20) unsigned NOT NULL,
  `changed_by_user_id` bigint(20) unsigned NOT NULL,
  `created_at` datetime NOT NULL DEFAULT current_timestamp(),
  `changed_at` datetime NOT NULL DEFAULT current_timestamp() ON UPDATE current_timestamp(),
  PRIMARY KEY (`id`),
  UNIQUE KEY `knowledge_article_number_unique` (`article_number`),
  KEY `knowledge_article_category_status` (`category_id`,`status`,`language`,`changed_at`),
  KEY `knowledge_article_visibility_status` (`visibility`,`customer_scope`,`status`,`language`),
  FULLTEXT KEY `knowledge_article_fulltext_search` (`title`,`summary`,`keywords`,`search_text`),
  CONSTRAINT `knowledge_article_category_fk` FOREIGN KEY (`category_id`) REFERENCES `knowledge_category` (`id`),
  CONSTRAINT `knowledge_article_published_by_fk` FOREIGN KEY (`published_by_user_id`) REFERENCES `user_account` (`id`),
  CONSTRAINT `knowledge_article_created_by_fk` FOREIGN KEY (`created_by_user_id`) REFERENCES `user_account` (`id`),
  CONSTRAINT `knowledge_article_changed_by_fk` FOREIGN KEY (`changed_by_user_id`) REFERENCES `user_account` (`id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE IF NOT EXISTS `knowledge_article_revision` (
  `id` bigint(20) unsigned NOT NULL AUTO_INCREMENT,
  `article_id` bigint(20) unsigned NOT NULL,
  `revision_number` int(10) unsigned NOT NULL,
  `category_id` bigint(20) unsigned NOT NULL,
  `language` varchar(20) NOT NULL,
  `title` varchar(255) NOT NULL,
  `summary` text DEFAULT NULL,
  `keywords` text DEFAULT NULL,
  `content` longtext NOT NULL,
  `visibility` varchar(20) NOT NULL,
  `customer_scope` varchar(20) NOT NULL,
  `status` varchar(20) NOT NULL,
  `changed_by_user_id` bigint(20) unsigned NOT NULL,
  `created_at` datetime NOT NULL DEFAULT current_timestamp(),
  PRIMARY KEY (`id`),
  UNIQUE KEY `knowledge_article_revision_unique` (`article_id`,`revision_number`),
  KEY `knowledge_article_revision_created` (`article_id`,`created_at`,`id`),
  CONSTRAINT `knowledge_article_revision_article_fk` FOREIGN KEY (`article_id`) REFERENCES `knowledge_article` (`id`) ON DELETE CASCADE,
  CONSTRAINT `knowledge_article_revision_category_fk` FOREIGN KEY (`category_id`) REFERENCES `knowledge_category` (`id`),
  CONSTRAINT `knowledge_article_revision_changed_by_fk` FOREIGN KEY (`changed_by_user_id`) REFERENCES `user_account` (`id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE IF NOT EXISTS `knowledge_article_customer` (
  `article_id` bigint(20) unsigned NOT NULL,
  `customer_id` bigint(20) unsigned NOT NULL,
  `created_by_user_id` bigint(20) unsigned NOT NULL,
  `created_at` datetime NOT NULL DEFAULT current_timestamp(),
  PRIMARY KEY (`article_id`,`customer_id`),
  KEY `knowledge_article_customer_customer` (`customer_id`,`article_id`),
  CONSTRAINT `knowledge_article_customer_article_fk` FOREIGN KEY (`article_id`) REFERENCES `knowledge_article` (`id`) ON DELETE CASCADE,
  CONSTRAINT `knowledge_article_customer_customer_fk` FOREIGN KEY (`customer_id`) REFERENCES `customer` (`id`) ON DELETE CASCADE,
  CONSTRAINT `knowledge_article_customer_created_by_fk` FOREIGN KEY (`created_by_user_id`) REFERENCES `user_account` (`id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE IF NOT EXISTS `knowledge_article_queue` (
  `article_id` bigint(20) unsigned NOT NULL,
  `queue_id` bigint(20) unsigned NOT NULL,
  `created_by_user_id` bigint(20) unsigned NOT NULL,
  `created_at` datetime NOT NULL DEFAULT current_timestamp(),
  PRIMARY KEY (`article_id`,`queue_id`),
  KEY `knowledge_article_queue_queue` (`queue_id`,`article_id`),
  CONSTRAINT `knowledge_article_queue_article_fk` FOREIGN KEY (`article_id`) REFERENCES `knowledge_article` (`id`) ON DELETE CASCADE,
  CONSTRAINT `knowledge_article_queue_queue_fk` FOREIGN KEY (`queue_id`) REFERENCES `ticket_queue` (`id`) ON DELETE CASCADE,
  CONSTRAINT `knowledge_article_queue_created_by_fk` FOREIGN KEY (`created_by_user_id`) REFERENCES `user_account` (`id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE IF NOT EXISTS `knowledge_article_usage` (
  `id` bigint(20) unsigned NOT NULL AUTO_INCREMENT,
  `article_id` bigint(20) unsigned NOT NULL,
  `revision_number` int(10) unsigned NOT NULL,
  `ticket_id` bigint(20) unsigned DEFAULT NULL,
  `used_by_user_id` bigint(20) unsigned NOT NULL,
  `usage_context` varchar(30) NOT NULL,
  `insert_mode` varchar(30) NOT NULL DEFAULT 'solution',
  `created_at` datetime NOT NULL DEFAULT current_timestamp(),
  PRIMARY KEY (`id`),
  KEY `knowledge_article_usage_article` (`article_id`,`created_at`,`id`),
  KEY `knowledge_article_usage_ticket` (`ticket_id`,`created_at`,`id`),
  KEY `knowledge_article_usage_user` (`used_by_user_id`,`created_at`,`id`),
  CONSTRAINT `knowledge_article_usage_article_fk` FOREIGN KEY (`article_id`) REFERENCES `knowledge_article` (`id`),
  CONSTRAINT `knowledge_article_usage_ticket_fk` FOREIGN KEY (`ticket_id`) REFERENCES `ticket` (`id`) ON DELETE SET NULL,
  CONSTRAINT `knowledge_article_usage_user_fk` FOREIGN KEY (`used_by_user_id`) REFERENCES `user_account` (`id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

INSERT INTO `user_group_permission` (`user_group_id`,`permission_key`,`active`,`created_by_user_id`,`changed_by_user_id`)
SELECT 1, permission_key, 1, 1, 1
FROM (
  SELECT 'knowledge.view' AS permission_key
  UNION ALL SELECT 'knowledge.edit'
  UNION ALL SELECT 'knowledge.publish'
) AS knowledge_permissions
ON DUPLICATE KEY UPDATE `active` = 1, `changed_by_user_id` = 1, `changed_at` = CURRENT_TIMESTAMP;
