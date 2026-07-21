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

-- Qisutu 0.0.24: S/MIME message security and explicit mail-server certificate verification.

ALTER TABLE `postmaster_imap_account`
  ADD COLUMN IF NOT EXISTS `imap_verify_certificate` tinyint(1) NOT NULL DEFAULT 1 AFTER `imap_port`,
  ADD COLUMN IF NOT EXISTS `imap_ca_file` varchar(500) NOT NULL DEFAULT '' AFTER `imap_verify_certificate`;

ALTER TABLE `smtp_account`
  ADD COLUMN IF NOT EXISTS `smtp_verify_certificate` tinyint(1) NOT NULL DEFAULT 1 AFTER `smtp_port`,
  ADD COLUMN IF NOT EXISTS `smtp_ca_file` varchar(500) NOT NULL DEFAULT '' AFTER `smtp_verify_certificate`;

CREATE TABLE IF NOT EXISTS `mail_crypto_key` (
  `id` bigint(20) unsigned NOT NULL AUTO_INCREMENT,
  `crypto_type` varchar(20) NOT NULL DEFAULT 'smime',
  `key_role` varchar(20) NOT NULL,
  `system_email_id` bigint(20) unsigned DEFAULT NULL,
  `email_address` varchar(255) NOT NULL,
  `display_name` varchar(255) NOT NULL DEFAULT '',
  `certificate_pem` longtext NOT NULL,
  `certificate_chain_pem` longtext DEFAULT NULL,
  `private_key_encrypted` longtext DEFAULT NULL,
  `fingerprint_sha256` char(64) NOT NULL,
  `serial_number` varchar(190) NOT NULL DEFAULT '',
  `subject_name` text DEFAULT NULL,
  `issuer_name` text DEFAULT NULL,
  `valid_from` datetime DEFAULT NULL,
  `valid_until` datetime DEFAULT NULL,
  `active` tinyint(1) NOT NULL DEFAULT 1,
  `created_by_user_id` bigint(20) unsigned NOT NULL,
  `changed_by_user_id` bigint(20) unsigned NOT NULL,
  `created_at` datetime NOT NULL DEFAULT current_timestamp(),
  `changed_at` datetime NOT NULL DEFAULT current_timestamp() ON UPDATE current_timestamp(),
  PRIMARY KEY (`id`),
  UNIQUE KEY `mail_crypto_key_role_email_fingerprint` (`crypto_type`,`key_role`,`email_address`,`fingerprint_sha256`),
  KEY `mail_crypto_key_system_email` (`system_email_id`,`active`,`valid_until`,`id`),
  KEY `mail_crypto_key_recipient` (`key_role`,`email_address`,`active`,`valid_until`,`id`),
  CONSTRAINT `mail_crypto_key_system_email_fk` FOREIGN KEY (`system_email_id`) REFERENCES `system_email` (`id`) ON DELETE SET NULL,
  CONSTRAINT `mail_crypto_key_created_by_fk` FOREIGN KEY (`created_by_user_id`) REFERENCES `user_account` (`id`),
  CONSTRAINT `mail_crypto_key_changed_by_fk` FOREIGN KEY (`changed_by_user_id`) REFERENCES `user_account` (`id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE IF NOT EXISTS `mail_crypto_policy` (
  `id` bigint(20) unsigned NOT NULL AUTO_INCREMENT,
  `system_email_id` bigint(20) unsigned NOT NULL,
  `sign_outgoing` tinyint(1) NOT NULL DEFAULT 0,
  `encrypt_outgoing` varchar(20) NOT NULL DEFAULT 'disabled',
  `decrypt_incoming` tinyint(1) NOT NULL DEFAULT 1,
  `verify_incoming` tinyint(1) NOT NULL DEFAULT 1,
  `active` tinyint(1) NOT NULL DEFAULT 1,
  `created_by_user_id` bigint(20) unsigned NOT NULL,
  `changed_by_user_id` bigint(20) unsigned NOT NULL,
  `created_at` datetime NOT NULL DEFAULT current_timestamp(),
  `changed_at` datetime NOT NULL DEFAULT current_timestamp() ON UPDATE current_timestamp(),
  PRIMARY KEY (`id`),
  UNIQUE KEY `mail_crypto_policy_system_email_unique` (`system_email_id`),
  CONSTRAINT `mail_crypto_policy_system_email_fk` FOREIGN KEY (`system_email_id`) REFERENCES `system_email` (`id`) ON DELETE CASCADE,
  CONSTRAINT `mail_crypto_policy_created_by_fk` FOREIGN KEY (`created_by_user_id`) REFERENCES `user_account` (`id`),
  CONSTRAINT `mail_crypto_policy_changed_by_fk` FOREIGN KEY (`changed_by_user_id`) REFERENCES `user_account` (`id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE IF NOT EXISTS `ticket_article_crypto` (
  `id` bigint(20) unsigned NOT NULL AUTO_INCREMENT,
  `ticket_id` bigint(20) unsigned NOT NULL,
  `article_id` bigint(20) unsigned NOT NULL,
  `direction` varchar(20) NOT NULL,
  `crypto_type` varchar(20) NOT NULL DEFAULT 'smime',
  `encrypted` tinyint(1) NOT NULL DEFAULT 0,
  `decrypted` tinyint(1) NOT NULL DEFAULT 0,
  `signed` tinyint(1) NOT NULL DEFAULT 0,
  `signature_status` varchar(30) NOT NULL DEFAULT 'none',
  `signer_email` varchar(255) NOT NULL DEFAULT '',
  `signer_fingerprint` char(64) NOT NULL DEFAULT '',
  `recipient_fingerprints` text DEFAULT NULL,
  `error_message` text DEFAULT NULL,
  `created_at` datetime NOT NULL DEFAULT current_timestamp(),
  `changed_at` datetime NOT NULL DEFAULT current_timestamp() ON UPDATE current_timestamp(),
  PRIMARY KEY (`id`),
  UNIQUE KEY `ticket_article_crypto_article_unique` (`article_id`),
  KEY `ticket_article_crypto_ticket` (`ticket_id`,`article_id`),
  CONSTRAINT `ticket_article_crypto_ticket_fk` FOREIGN KEY (`ticket_id`) REFERENCES `ticket` (`id`) ON DELETE CASCADE,
  CONSTRAINT `ticket_article_crypto_article_fk` FOREIGN KEY (`article_id`) REFERENCES `ticket_article` (`id`) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;
