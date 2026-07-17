-- Qisutu - Open Source Ticket System
-- Copyright (C) 2026 Franziska Steps
-- Qisutu - Kim-KI, https://qisutu.de
--
-- SPDX-FileCopyrightText: 2026 Franziska Steps
-- SPDX-License-Identifier: AGPL-3.0-or-later

CREATE TABLE IF NOT EXISTS `oauth2_authorization_state` (
  `id` bigint(20) unsigned NOT NULL AUTO_INCREMENT,
  `state_hash` char(64) NOT NULL,
  `account_id` bigint(20) unsigned NOT NULL,
  `user_account_id` bigint(20) unsigned NOT NULL,
  `provider` varchar(30) NOT NULL,
  `requested_active` tinyint(1) NOT NULL DEFAULT 1,
  `return_page` varchar(100) NOT NULL,
  `expires_at` datetime NOT NULL,
  `created_at` datetime NOT NULL DEFAULT current_timestamp(),
  PRIMARY KEY (`id`),
  UNIQUE KEY `oauth2_authorization_state_hash_unique` (`state_hash`),
  KEY `oauth2_authorization_state_account_user` (`account_id`,`user_account_id`),
  KEY `oauth2_authorization_state_expires` (`expires_at`),
  CONSTRAINT `oauth2_authorization_state_account_fk` FOREIGN KEY (`account_id`) REFERENCES `postmaster_imap_account` (`id`) ON DELETE CASCADE,
  CONSTRAINT `oauth2_authorization_state_user_fk` FOREIGN KEY (`user_account_id`) REFERENCES `user_account` (`id`) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;
