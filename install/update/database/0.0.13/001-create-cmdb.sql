-- Qisutu - Open Source Ticket System
-- Copyright (C) 2026 Franziska Steps
-- SPDX-License-Identifier: AGPL-3.0-or-later

CREATE TABLE IF NOT EXISTS `cmdb_ci_type` (
  `id` bigint(20) unsigned NOT NULL AUTO_INCREMENT,
  `name` varchar(255) NOT NULL,
  `description` text DEFAULT NULL,
  `icon` varchar(20) NOT NULL DEFAULT 'CI',
  `active` tinyint(1) NOT NULL DEFAULT 1,
  `sort_order` int(10) unsigned NOT NULL DEFAULT 1000,
  `created_by_user_id` bigint(20) unsigned NOT NULL,
  `changed_by_user_id` bigint(20) unsigned NOT NULL,
  `created_at` datetime NOT NULL DEFAULT current_timestamp(),
  `changed_at` datetime NOT NULL DEFAULT current_timestamp() ON UPDATE current_timestamp(),
  PRIMARY KEY (`id`),
  UNIQUE KEY `cmdb_ci_type_name_unique` (`name`),
  KEY `cmdb_ci_type_active_sort` (`active`,`sort_order`,`name`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE IF NOT EXISTS `cmdb_ci_field` (
  `id` bigint(20) unsigned NOT NULL AUTO_INCREMENT,
  `type_id` bigint(20) unsigned NOT NULL,
  `field_key` varchar(100) NOT NULL,
  `label` varchar(255) NOT NULL,
  `field_type` varchar(30) NOT NULL DEFAULT 'text',
  `is_required` tinyint(1) NOT NULL DEFAULT 0,
  `customer_visible` tinyint(1) NOT NULL DEFAULT 0,
  `default_value` text DEFAULT NULL,
  `active` tinyint(1) NOT NULL DEFAULT 1,
  `sort_order` int(10) unsigned NOT NULL DEFAULT 1000,
  `created_by_user_id` bigint(20) unsigned NOT NULL,
  `changed_by_user_id` bigint(20) unsigned NOT NULL,
  `created_at` datetime NOT NULL DEFAULT current_timestamp(),
  `changed_at` datetime NOT NULL DEFAULT current_timestamp() ON UPDATE current_timestamp(),
  PRIMARY KEY (`id`),
  UNIQUE KEY `cmdb_ci_field_type_key_unique` (`type_id`,`field_key`),
  KEY `cmdb_ci_field_type_active_sort` (`type_id`,`active`,`sort_order`,`id`),
  CONSTRAINT `cmdb_ci_field_type_fk` FOREIGN KEY (`type_id`) REFERENCES `cmdb_ci_type` (`id`) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE IF NOT EXISTS `cmdb_ci_field_option` (
  `id` bigint(20) unsigned NOT NULL AUTO_INCREMENT,
  `field_id` bigint(20) unsigned NOT NULL,
  `option_key` varchar(255) NOT NULL,
  `option_label` varchar(500) NOT NULL,
  `active` tinyint(1) NOT NULL DEFAULT 1,
  `sort_order` int(10) unsigned NOT NULL DEFAULT 1000,
  PRIMARY KEY (`id`),
  UNIQUE KEY `cmdb_ci_field_option_key_unique` (`field_id`,`option_key`),
  KEY `cmdb_ci_field_option_sort` (`field_id`,`active`,`sort_order`,`id`),
  CONSTRAINT `cmdb_ci_field_option_field_fk` FOREIGN KEY (`field_id`) REFERENCES `cmdb_ci_field` (`id`) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE IF NOT EXISTS `cmdb_counter` (
  `counter_key` varchar(50) NOT NULL,
  `next_value` bigint(20) unsigned NOT NULL DEFAULT 1,
  PRIMARY KEY (`counter_key`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

INSERT IGNORE INTO `cmdb_counter` (`counter_key`,`next_value`) VALUES ('ci_number',1);

CREATE TABLE IF NOT EXISTS `cmdb_ci` (
  `id` bigint(20) unsigned NOT NULL AUTO_INCREMENT,
  `ci_number` varchar(50) NOT NULL,
  `type_id` bigint(20) unsigned NOT NULL,
  `name` varchar(500) NOT NULL,
  `description` text DEFAULT NULL,
  `status` varchar(50) NOT NULL DEFAULT 'active',
  `inventory_number` varchar(255) NOT NULL DEFAULT '',
  `serial_number` varchar(255) NOT NULL DEFAULT '',
  `location` varchar(500) NOT NULL DEFAULT '',
  `customer_id` bigint(20) unsigned DEFAULT NULL,
  `customer_user_id` bigint(20) unsigned DEFAULT NULL,
  `customer_visible` tinyint(1) NOT NULL DEFAULT 0,
  `source` varchar(50) NOT NULL DEFAULT 'manual',
  `external_id` varchar(255) NOT NULL DEFAULT '',
  `active` tinyint(1) NOT NULL DEFAULT 1,
  `created_by_user_id` bigint(20) unsigned NOT NULL,
  `changed_by_user_id` bigint(20) unsigned NOT NULL,
  `created_at` datetime NOT NULL DEFAULT current_timestamp(),
  `changed_at` datetime NOT NULL DEFAULT current_timestamp() ON UPDATE current_timestamp(),
  PRIMARY KEY (`id`),
  UNIQUE KEY `cmdb_ci_number_unique` (`ci_number`),
  KEY `cmdb_ci_type_active` (`type_id`,`active`,`name`),
  KEY `cmdb_ci_customer` (`customer_id`,`active`,`name`),
  KEY `cmdb_ci_customer_user` (`customer_user_id`,`active`,`name`),
  KEY `cmdb_ci_inventory` (`inventory_number`),
  KEY `cmdb_ci_serial` (`serial_number`),
  KEY `cmdb_ci_external` (`source`,`external_id`),
  CONSTRAINT `cmdb_ci_type_fk` FOREIGN KEY (`type_id`) REFERENCES `cmdb_ci_type` (`id`),
  CONSTRAINT `cmdb_ci_customer_fk` FOREIGN KEY (`customer_id`) REFERENCES `customer` (`id`) ON DELETE SET NULL,
  CONSTRAINT `cmdb_ci_customer_user_fk` FOREIGN KEY (`customer_user_id`) REFERENCES `customer_user` (`id`) ON DELETE SET NULL
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE IF NOT EXISTS `cmdb_ci_value` (
  `id` bigint(20) unsigned NOT NULL AUTO_INCREMENT,
  `ci_id` bigint(20) unsigned NOT NULL,
  `field_id` bigint(20) unsigned NOT NULL,
  `value_text` longtext DEFAULT NULL,
  `created_by_user_id` bigint(20) unsigned NOT NULL,
  `changed_by_user_id` bigint(20) unsigned NOT NULL,
  `created_at` datetime NOT NULL DEFAULT current_timestamp(),
  `changed_at` datetime NOT NULL DEFAULT current_timestamp() ON UPDATE current_timestamp(),
  PRIMARY KEY (`id`),
  UNIQUE KEY `cmdb_ci_value_ci_field_unique` (`ci_id`,`field_id`),
  KEY `cmdb_ci_value_field` (`field_id`),
  CONSTRAINT `cmdb_ci_value_ci_fk` FOREIGN KEY (`ci_id`) REFERENCES `cmdb_ci` (`id`) ON DELETE CASCADE,
  CONSTRAINT `cmdb_ci_value_field_fk` FOREIGN KEY (`field_id`) REFERENCES `cmdb_ci_field` (`id`) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE IF NOT EXISTS `cmdb_relation_type` (
  `id` bigint(20) unsigned NOT NULL AUTO_INCREMENT,
  `name` varchar(255) NOT NULL,
  `forward_label` varchar(255) NOT NULL,
  `reverse_label` varchar(255) NOT NULL,
  `active` tinyint(1) NOT NULL DEFAULT 1,
  `sort_order` int(10) unsigned NOT NULL DEFAULT 1000,
  `created_by_user_id` bigint(20) unsigned NOT NULL DEFAULT 1,
  `changed_by_user_id` bigint(20) unsigned NOT NULL DEFAULT 1,
  `created_at` datetime NOT NULL DEFAULT current_timestamp(),
  `changed_at` datetime NOT NULL DEFAULT current_timestamp() ON UPDATE current_timestamp(),
  PRIMARY KEY (`id`),
  UNIQUE KEY `cmdb_relation_type_name_unique` (`name`),
  KEY `cmdb_relation_type_active_sort` (`active`,`sort_order`,`name`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE IF NOT EXISTS `cmdb_ci_relation` (
  `id` bigint(20) unsigned NOT NULL AUTO_INCREMENT,
  `source_ci_id` bigint(20) unsigned NOT NULL,
  `target_ci_id` bigint(20) unsigned NOT NULL,
  `relation_type_id` bigint(20) unsigned NOT NULL,
  `note` varchar(1000) NOT NULL DEFAULT '',
  `active` tinyint(1) NOT NULL DEFAULT 1,
  `created_by_user_id` bigint(20) unsigned NOT NULL,
  `changed_by_user_id` bigint(20) unsigned NOT NULL,
  `created_at` datetime NOT NULL DEFAULT current_timestamp(),
  `changed_at` datetime NOT NULL DEFAULT current_timestamp() ON UPDATE current_timestamp(),
  PRIMARY KEY (`id`),
  UNIQUE KEY `cmdb_ci_relation_unique` (`source_ci_id`,`target_ci_id`,`relation_type_id`),
  KEY `cmdb_ci_relation_target` (`target_ci_id`,`active`,`id`),
  CONSTRAINT `cmdb_ci_relation_source_fk` FOREIGN KEY (`source_ci_id`) REFERENCES `cmdb_ci` (`id`) ON DELETE CASCADE,
  CONSTRAINT `cmdb_ci_relation_target_fk` FOREIGN KEY (`target_ci_id`) REFERENCES `cmdb_ci` (`id`) ON DELETE CASCADE,
  CONSTRAINT `cmdb_ci_relation_type_fk` FOREIGN KEY (`relation_type_id`) REFERENCES `cmdb_relation_type` (`id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE IF NOT EXISTS `ticket_cmdb_ci` (
  `id` bigint(20) unsigned NOT NULL AUTO_INCREMENT,
  `ticket_id` bigint(20) unsigned NOT NULL,
  `ci_id` bigint(20) unsigned NOT NULL,
  `created_by_user_id` bigint(20) unsigned NOT NULL,
  `created_at` datetime NOT NULL DEFAULT current_timestamp(),
  PRIMARY KEY (`id`),
  UNIQUE KEY `ticket_cmdb_ci_unique` (`ticket_id`,`ci_id`),
  KEY `ticket_cmdb_ci_ci` (`ci_id`,`ticket_id`),
  CONSTRAINT `ticket_cmdb_ci_ticket_fk` FOREIGN KEY (`ticket_id`) REFERENCES `ticket` (`id`) ON DELETE CASCADE,
  CONSTRAINT `ticket_cmdb_ci_ci_fk` FOREIGN KEY (`ci_id`) REFERENCES `cmdb_ci` (`id`) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE IF NOT EXISTS `cmdb_ci_history` (
  `id` bigint(20) unsigned NOT NULL AUTO_INCREMENT,
  `ci_id` bigint(20) unsigned NOT NULL,
  `event_type` varchar(100) NOT NULL,
  `field_key` varchar(100) NOT NULL DEFAULT '',
  `field_label` varchar(255) NOT NULL DEFAULT '',
  `old_value` longtext DEFAULT NULL,
  `new_value` longtext DEFAULT NULL,
  `details` text DEFAULT NULL,
  `related_ticket_id` bigint(20) unsigned DEFAULT NULL,
  `related_ci_id` bigint(20) unsigned DEFAULT NULL,
  `actor_user_id` bigint(20) unsigned DEFAULT NULL,
  `actor_name` varchar(255) NOT NULL DEFAULT '',
  `source` varchar(50) NOT NULL DEFAULT 'application',
  `created_at` datetime NOT NULL DEFAULT current_timestamp(),
  PRIMARY KEY (`id`),
  KEY `cmdb_ci_history_ci_created` (`ci_id`,`created_at`,`id`),
  KEY `cmdb_ci_history_ticket` (`related_ticket_id`,`created_at`),
  KEY `cmdb_ci_history_related_ci` (`related_ci_id`,`created_at`),
  CONSTRAINT `cmdb_ci_history_ci_fk` FOREIGN KEY (`ci_id`) REFERENCES `cmdb_ci` (`id`) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

DROP TRIGGER IF EXISTS `cmdb_ci_history_immutable_update`;
DROP TRIGGER IF EXISTS `cmdb_ci_history_immutable_delete`;

DELIMITER ;;
CREATE TRIGGER `cmdb_ci_history_immutable_update`
BEFORE UPDATE ON `cmdb_ci_history`
FOR EACH ROW
BEGIN
    SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'CMDB history entries are immutable';
END;;
CREATE TRIGGER `cmdb_ci_history_immutable_delete`
BEFORE DELETE ON `cmdb_ci_history`
FOR EACH ROW
BEGIN
    SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'CMDB history entries are immutable';
END;;
DELIMITER ;

INSERT IGNORE INTO `cmdb_ci_type`
(`id`,`name`,`description`,`icon`,`active`,`sort_order`,`created_by_user_id`,`changed_by_user_id`) VALUES
(1,'Arbeitsplatz','Kompletter IT-Arbeitsplatz','PC',1,100,1,1),
(2,'Notebook','Mobiler Arbeitsplatz','NB',1,200,1,1),
(3,'Server','Physischer oder virtueller Server','SV',1,300,1,1),
(4,'Drucker','Drucker oder Multifunktionsgerät','DR',1,400,1,1),
(5,'Netzwerkgerät','Switch, Router, Firewall oder Access Point','NW',1,500,1,1),
(6,'Mobilgerät','Smartphone oder Tablet','MO',1,600,1,1),
(7,'Software','Installierbares Softwareprodukt','SW',1,700,1,1),
(8,'Anwendung','Geschäftsanwendung oder Plattform','AP',1,800,1,1),
(9,'IT-Service','Technischer oder fachlicher IT-Service','SE',1,900,1,1),
(10,'Lizenz','Software- oder Nutzungslizenz','LI',1,1000,1,1),
(11,'Vertrag','Wartungs-, Liefer- oder Servicevertrag','VE',1,1100,1,1),
(12,'Standort','Gebäude, Raum oder technischer Standort','ST',1,1200,1,1);

INSERT IGNORE INTO `cmdb_relation_type`
(`id`,`name`,`forward_label`,`reverse_label`,`active`,`sort_order`,`created_by_user_id`,`changed_by_user_id`) VALUES
(1,'depends_on','ist abhängig von','wird benötigt von',1,100,1,1),
(2,'runs_on','läuft auf','betreibt',1,200,1,1),
(3,'connected_to','ist verbunden mit','ist verbunden mit',1,300,1,1),
(4,'part_of','ist Bestandteil von','enthält',1,400,1,1),
(5,'located_at','befindet sich an','beinhaltet',1,500,1,1),
(6,'licensed_by','wird lizenziert durch','lizenziert',1,600,1,1),
(7,'covered_by','wird abgedeckt durch','deckt ab',1,700,1,1);
