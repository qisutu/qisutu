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

-- MariaDB dump 10.19  Distrib 10.11.14-MariaDB, for debian-linux-gnu (x86_64)
--
-- Host: localhost    Database: qisutu
-- ------------------------------------------------------
-- Server version	10.11.14-MariaDB-0ubuntu0.24.04.1

/*!40101 SET @OLD_CHARACTER_SET_CLIENT=@@CHARACTER_SET_CLIENT */;
/*!40101 SET @OLD_CHARACTER_SET_RESULTS=@@CHARACTER_SET_RESULTS */;
/*!40101 SET @OLD_COLLATION_CONNECTION=@@COLLATION_CONNECTION */;
/*!40101 SET NAMES utf8mb4 */;
/*!40103 SET @OLD_TIME_ZONE=@@TIME_ZONE */;
/*!40103 SET TIME_ZONE='+00:00' */;
/*!40014 SET @OLD_UNIQUE_CHECKS=@@UNIQUE_CHECKS, UNIQUE_CHECKS=0 */;
/*!40014 SET @OLD_FOREIGN_KEY_CHECKS=@@FOREIGN_KEY_CHECKS, FOREIGN_KEY_CHECKS=0 */;
/*!40101 SET @OLD_SQL_MODE=@@SQL_MODE, SQL_MODE='NO_AUTO_VALUE_ON_ZERO' */;
/*!40111 SET @OLD_SQL_NOTES=@@SQL_NOTES, SQL_NOTES=0 */;

--
-- Table structure for table `agent_notification_event_log`
--

DROP TABLE IF EXISTS `agent_notification_event_log`;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!40101 SET character_set_client = utf8mb4 */;
CREATE TABLE `agent_notification_event_log` (
  `id` bigint(20) unsigned NOT NULL AUTO_INCREMENT,
  `notification_type` varchar(100) NOT NULL,
  `ticket_id` bigint(20) unsigned NOT NULL,
  `recipient_user_id` bigint(20) unsigned NOT NULL,
  `event_key` varchar(255) NOT NULL,
  `sent_at` datetime NOT NULL DEFAULT current_timestamp(),
  PRIMARY KEY (`id`),
  UNIQUE KEY `agent_notification_event_unique` (`notification_type`,`ticket_id`,`recipient_user_id`,`event_key`),
  KEY `agent_notification_event_ticket` (`ticket_id`),
  KEY `agent_notification_event_recipient` (`recipient_user_id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;
/*!40101 SET character_set_client = @saved_cs_client */;

--
-- Table structure for table `agent_notification_template`
--

DROP TABLE IF EXISTS `agent_notification_template`;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!40101 SET character_set_client = utf8mb4 */;
CREATE TABLE `agent_notification_template` (
  `id` bigint(20) unsigned NOT NULL AUTO_INCREMENT,
  `notification_type` varchar(100) NOT NULL,
  `language` varchar(10) NOT NULL DEFAULT 'de',
  `name` varchar(255) NOT NULL,
  `subject` varchar(500) NOT NULL DEFAULT '',
  `body_html` longtext NOT NULL,
  `active` tinyint(1) NOT NULL DEFAULT 1,
  `sort_order` int(10) unsigned NOT NULL DEFAULT 1000,
  `created_by_user_id` bigint(20) unsigned NOT NULL DEFAULT 1,
  `changed_by_user_id` bigint(20) unsigned NOT NULL DEFAULT 1,
  `created_at` datetime NOT NULL DEFAULT current_timestamp(),
  `changed_at` datetime NOT NULL DEFAULT current_timestamp() ON UPDATE current_timestamp(),
  PRIMARY KEY (`id`),
  UNIQUE KEY `agent_notification_template_type_language_unique` (`notification_type`,`language`),
  KEY `agent_notification_template_language_active_sort` (`language`,`active`,`sort_order`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;
/*!40101 SET character_set_client = @saved_cs_client */;

--
-- Table structure for table `customer_auto_response_event_log`
--

DROP TABLE IF EXISTS `customer_auto_response_event_log`;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!40101 SET character_set_client = utf8mb4 */;
CREATE TABLE `customer_auto_response_event_log` (
  `id` bigint(20) unsigned NOT NULL AUTO_INCREMENT,
  `response_type` varchar(100) NOT NULL,
  `ticket_id` bigint(20) unsigned NOT NULL DEFAULT 0,
  `article_id` bigint(20) unsigned NOT NULL DEFAULT 0,
  `recipient_email` varchar(255) NOT NULL,
  `event_key` varchar(255) NOT NULL,
  `sent_at` datetime NOT NULL DEFAULT current_timestamp(),
  PRIMARY KEY (`id`),
  UNIQUE KEY `customer_auto_response_event_unique` (`response_type`,`event_key`),
  KEY `customer_auto_response_event_ticket` (`ticket_id`),
  KEY `customer_auto_response_event_article` (`article_id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;
/*!40101 SET character_set_client = @saved_cs_client */;

--
-- Table structure for table `customer_auto_response_template`
--

DROP TABLE IF EXISTS `customer_auto_response_template`;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!40101 SET character_set_client = utf8mb4 */;
CREATE TABLE `customer_auto_response_template` (
  `id` bigint(20) unsigned NOT NULL AUTO_INCREMENT,
  `response_type` varchar(100) NOT NULL,
  `language` varchar(10) NOT NULL DEFAULT 'de',
  `name` varchar(255) NOT NULL,
  `subject` varchar(500) NOT NULL DEFAULT '',
  `body_html` longtext NOT NULL,
  `active` tinyint(1) NOT NULL DEFAULT 0,
  `sort_order` int(10) unsigned NOT NULL DEFAULT 1000,
  `created_by_user_id` bigint(20) unsigned NOT NULL DEFAULT 1,
  `changed_by_user_id` bigint(20) unsigned NOT NULL DEFAULT 1,
  `created_at` datetime NOT NULL DEFAULT current_timestamp(),
  `changed_at` datetime NOT NULL DEFAULT current_timestamp() ON UPDATE current_timestamp(),
  PRIMARY KEY (`id`),
  UNIQUE KEY `customer_auto_response_template_type_language_unique` (`response_type`,`language`),
  KEY `customer_auto_response_template_language_active_sort` (`language`,`active`,`sort_order`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;
/*!40101 SET character_set_client = @saved_cs_client */;

--
-- Table structure for table `automation_deleted_ticket`
--

DROP TABLE IF EXISTS `automation_deleted_ticket`;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!40101 SET character_set_client = utf8mb4 */;
CREATE TABLE `automation_deleted_ticket` (
  `id` bigint(20) unsigned NOT NULL AUTO_INCREMENT,
  `ticket_id_original` bigint(20) unsigned NOT NULL,
  `ticket_number` varchar(50) NOT NULL,
  `title` varchar(500) NOT NULL DEFAULT '',
  `rule_id` bigint(20) unsigned DEFAULT NULL,
  `job_id` bigint(20) unsigned DEFAULT NULL,
  `deleted_related_rows` bigint(20) unsigned NOT NULL DEFAULT 0,
  `deleted_file_count` bigint(20) unsigned NOT NULL DEFAULT 0,
  `deleted_at` datetime NOT NULL DEFAULT current_timestamp(),
  PRIMARY KEY (`id`),
  KEY `automation_deleted_ticket_number` (`ticket_number`),
  KEY `automation_deleted_ticket_deleted_at` (`deleted_at`),
  KEY `automation_deleted_ticket_rule` (`rule_id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;
/*!40101 SET character_set_client = @saved_cs_client */;

--
-- Table structure for table `automation_event`
--

DROP TABLE IF EXISTS `automation_event`;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!40101 SET character_set_client = utf8mb4 */;
CREATE TABLE `automation_event` (
  `id` bigint(20) unsigned NOT NULL AUTO_INCREMENT,
  `event_name` varchar(100) NOT NULL,
  `event_key` varchar(255) DEFAULT NULL,
  `ticket_id` bigint(20) unsigned DEFAULT NULL,
  `source_rule_id` bigint(20) unsigned DEFAULT NULL,
  `source_job_id` bigint(20) unsigned DEFAULT NULL,
  `depth` int(10) unsigned NOT NULL DEFAULT 0,
  `payload_json` longtext DEFAULT NULL,
  `suppress_notifications` tinyint(1) NOT NULL DEFAULT 0,
  `created_at` datetime NOT NULL DEFAULT current_timestamp(),
  `processed_at` datetime DEFAULT NULL,
  PRIMARY KEY (`id`),
  UNIQUE KEY `automation_event_key` (`event_key`),
  KEY `automation_event_unprocessed` (`processed_at`,`id`),
  KEY `automation_event_ticket` (`ticket_id`,`created_at`),
  KEY `automation_event_name` (`event_name`,`created_at`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;
/*!40101 SET character_set_client = @saved_cs_client */;

--
-- Table structure for table `automation_job`
--

DROP TABLE IF EXISTS `automation_job`;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!40101 SET character_set_client = utf8mb4 */;
CREATE TABLE `automation_job` (
  `id` bigint(20) unsigned NOT NULL AUTO_INCREMENT,
  `job_key` varchar(255) NOT NULL,
  `parent_job_id` bigint(20) unsigned DEFAULT NULL,
  `rule_id` bigint(20) unsigned NOT NULL,
  `event_id` bigint(20) unsigned DEFAULT NULL,
  `ticket_id` bigint(20) unsigned DEFAULT NULL,
  `job_type` varchar(50) NOT NULL,
  `status` varchar(30) NOT NULL DEFAULT 'pending',
  `scheduled_at` datetime NOT NULL DEFAULT current_timestamp(),
  `next_attempt_at` datetime DEFAULT NULL,
  `started_at` datetime DEFAULT NULL,
  `finished_at` datetime DEFAULT NULL,
  `attempts` int(10) unsigned NOT NULL DEFAULT 0,
  `max_attempts` int(10) unsigned NOT NULL DEFAULT 3,
  `depth` int(10) unsigned NOT NULL DEFAULT 0,
  `suppress_notifications` tinyint(1) NOT NULL DEFAULT 0,
  `locked_by` varchar(255) DEFAULT NULL,
  `locked_until` datetime DEFAULT NULL,
  `error_message` text DEFAULT NULL,
  `result_json` longtext DEFAULT NULL,
  `created_at` datetime NOT NULL DEFAULT current_timestamp(),
  `changed_at` datetime NOT NULL DEFAULT current_timestamp() ON UPDATE current_timestamp(),
  PRIMARY KEY (`id`),
  UNIQUE KEY `automation_job_key` (`job_key`),
  KEY `automation_job_claim` (`status`,`scheduled_at`,`next_attempt_at`,`locked_until`,`id`),
  KEY `automation_job_rule` (`rule_id`,`id`),
  KEY `automation_job_event` (`event_id`),
  KEY `automation_job_ticket` (`ticket_id`,`id`),
  KEY `automation_job_parent` (`parent_job_id`),
  CONSTRAINT `automation_job_event_fk` FOREIGN KEY (`event_id`) REFERENCES `automation_event` (`id`) ON DELETE SET NULL,
  CONSTRAINT `automation_job_parent_fk` FOREIGN KEY (`parent_job_id`) REFERENCES `automation_job` (`id`) ON DELETE SET NULL,
  CONSTRAINT `automation_job_rule_fk` FOREIGN KEY (`rule_id`) REFERENCES `automation_rule` (`id`) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;
/*!40101 SET character_set_client = @saved_cs_client */;

--
-- Table structure for table `automation_rule`
--

DROP TABLE IF EXISTS `automation_rule`;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!40101 SET character_set_client = utf8mb4 */;
CREATE TABLE `automation_rule` (
  `id` bigint(20) unsigned NOT NULL AUTO_INCREMENT,
  `name` varchar(255) NOT NULL,
  `description` text DEFAULT NULL,
  `rule_type` varchar(20) NOT NULL,
  `event_name` varchar(100) NOT NULL DEFAULT '',
  `conditions_json` longtext NOT NULL,
  `actions_json` longtext NOT NULL,
  `schedule_json` longtext NOT NULL,
  `next_run_at` datetime DEFAULT NULL,
  `active` tinyint(1) NOT NULL DEFAULT 1,
  `sort_order` int(10) unsigned NOT NULL DEFAULT 1000,
  `last_run_at` datetime DEFAULT NULL,
  `last_result` varchar(30) DEFAULT NULL,
  `run_count` bigint(20) unsigned NOT NULL DEFAULT 0,
  `error_count` bigint(20) unsigned NOT NULL DEFAULT 0,
  `created_by_user_id` bigint(20) unsigned NOT NULL,
  `changed_by_user_id` bigint(20) unsigned NOT NULL,
  `created_at` datetime NOT NULL DEFAULT current_timestamp(),
  `changed_at` datetime NOT NULL DEFAULT current_timestamp() ON UPDATE current_timestamp(),
  PRIMARY KEY (`id`),
  KEY `automation_rule_type_active_sort` (`rule_type`,`active`,`sort_order`),
  KEY `automation_rule_event_active` (`event_name`,`active`),
  KEY `automation_rule_next_run` (`rule_type`,`active`,`next_run_at`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;
/*!40101 SET character_set_client = @saved_cs_client */;

--
-- Table structure for table `calendar`
--

DROP TABLE IF EXISTS `calendar`;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!40101 SET character_set_client = utf8mb4 */;
CREATE TABLE `calendar` (
  `id` bigint(20) unsigned NOT NULL AUTO_INCREMENT,
  `name` varchar(100) NOT NULL,
  `timezone` varchar(100) NOT NULL DEFAULT 'Europe/Berlin',
  `active` tinyint(1) NOT NULL DEFAULT 1,
  `sort_order` int(10) unsigned NOT NULL DEFAULT 1000,
  `created_by_user_id` bigint(20) unsigned NOT NULL,
  `changed_by_user_id` bigint(20) unsigned NOT NULL,
  `created_at` timestamp NOT NULL DEFAULT current_timestamp(),
  `changed_at` timestamp NOT NULL DEFAULT current_timestamp() ON UPDATE current_timestamp(),
  PRIMARY KEY (`id`),
  UNIQUE KEY `calendar_name` (`name`),
  KEY `calendar_active_sort` (`active`,`sort_order`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;
/*!40101 SET character_set_client = @saved_cs_client */;

--
-- Table structure for table `calendar_holiday`
--

DROP TABLE IF EXISTS `calendar_holiday`;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!40101 SET character_set_client = utf8mb4 */;
CREATE TABLE `calendar_holiday` (
  `id` bigint(20) unsigned NOT NULL AUTO_INCREMENT,
  `calendar_id` bigint(20) unsigned NOT NULL,
  `name` varchar(200) NOT NULL,
  `holiday_date` date DEFAULT NULL,
  `month_day` char(5) DEFAULT NULL,
  `recurring_annual` tinyint(1) NOT NULL DEFAULT 0,
  `active` tinyint(1) NOT NULL DEFAULT 1,
  `sort_order` int(10) unsigned NOT NULL DEFAULT 1000,
  `created_by_user_id` bigint(20) unsigned NOT NULL DEFAULT 1,
  `changed_by_user_id` bigint(20) unsigned NOT NULL DEFAULT 1,
  `created_at` datetime NOT NULL DEFAULT current_timestamp(),
  `changed_at` datetime NOT NULL DEFAULT current_timestamp() ON UPDATE current_timestamp(),
  PRIMARY KEY (`id`),
  KEY `calendar_holiday_calendar_id` (`calendar_id`),
  KEY `calendar_holiday_date` (`holiday_date`),
  KEY `calendar_holiday_month_day` (`month_day`),
  KEY `calendar_holiday_active` (`active`),
  CONSTRAINT `fk_calendar_holiday_calendar_id` FOREIGN KEY (`calendar_id`) REFERENCES `calendar` (`id`) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;
/*!40101 SET character_set_client = @saved_cs_client */;

--
-- Table structure for table `calendar_working_time`
--

DROP TABLE IF EXISTS `calendar_working_time`;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!40101 SET character_set_client = utf8mb4 */;
CREATE TABLE `calendar_working_time` (
  `id` bigint(20) unsigned NOT NULL AUTO_INCREMENT,
  `calendar_id` bigint(20) unsigned NOT NULL,
  `weekday` tinyint(3) unsigned NOT NULL,
  `active` tinyint(1) NOT NULL DEFAULT 1,
  `start_time` time NOT NULL DEFAULT '08:00:00',
  `end_time` time NOT NULL DEFAULT '17:00:00',
  `created_by_user_id` bigint(20) unsigned NOT NULL DEFAULT 1,
  `changed_by_user_id` bigint(20) unsigned NOT NULL DEFAULT 1,
  `created_at` datetime NOT NULL DEFAULT current_timestamp(),
  `changed_at` datetime NOT NULL DEFAULT current_timestamp() ON UPDATE current_timestamp(),
  PRIMARY KEY (`id`),
  UNIQUE KEY `calendar_working_time_calendar_weekday_unique` (`calendar_id`,`weekday`),
  KEY `calendar_working_time_calendar_id` (`calendar_id`),
  CONSTRAINT `fk_calendar_working_time_calendar_id` FOREIGN KEY (`calendar_id`) REFERENCES `calendar` (`id`) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;
/*!40101 SET character_set_client = @saved_cs_client */;

--
-- Table structure for table `checklist_template`
--

DROP TABLE IF EXISTS `checklist_template`;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!40101 SET character_set_client = utf8mb4 */;
CREATE TABLE `checklist_template` (
  `id` bigint(20) unsigned NOT NULL AUTO_INCREMENT,
  `name` varchar(255) NOT NULL,
  `description` text DEFAULT NULL,
  `usage_mode` enum('automatic','manual','both') NOT NULL DEFAULT 'manual',
  `sort_order` int(10) unsigned NOT NULL DEFAULT 1000,
  `active` tinyint(1) NOT NULL DEFAULT 1,
  `created_by_user_id` bigint(20) unsigned NOT NULL,
  `changed_by_user_id` bigint(20) unsigned NOT NULL,
  `created_at` datetime NOT NULL,
  `changed_at` datetime NOT NULL,
  PRIMARY KEY (`id`),
  KEY `idx_checklist_template_active_sort` (`active`,`sort_order`,`name`),
  KEY `fk_checklist_template_created_by` (`created_by_user_id`),
  KEY `fk_checklist_template_changed_by` (`changed_by_user_id`),
  CONSTRAINT `fk_checklist_template_changed_by` FOREIGN KEY (`changed_by_user_id`) REFERENCES `user_account` (`id`),
  CONSTRAINT `fk_checklist_template_created_by` FOREIGN KEY (`created_by_user_id`) REFERENCES `user_account` (`id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;
/*!40101 SET character_set_client = @saved_cs_client */;

--
-- Table structure for table `checklist_template_customer`
--

DROP TABLE IF EXISTS `checklist_template_customer`;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!40101 SET character_set_client = utf8mb4 */;
CREATE TABLE `checklist_template_customer` (
  `template_id` bigint(20) unsigned NOT NULL,
  `customer_id` bigint(20) unsigned NOT NULL,
  `created_by_user_id` bigint(20) unsigned NOT NULL,
  `created_at` datetime NOT NULL,
  PRIMARY KEY (`template_id`,`customer_id`),
  KEY `idx_checklist_template_customer_customer` (`customer_id`,`template_id`),
  KEY `fk_checklist_template_customer_created_by` (`created_by_user_id`),
  CONSTRAINT `fk_checklist_template_customer_created_by` FOREIGN KEY (`created_by_user_id`) REFERENCES `user_account` (`id`),
  CONSTRAINT `fk_checklist_template_customer_customer` FOREIGN KEY (`customer_id`) REFERENCES `customer` (`id`) ON DELETE CASCADE,
  CONSTRAINT `fk_checklist_template_customer_template` FOREIGN KEY (`template_id`) REFERENCES `checklist_template` (`id`) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;
/*!40101 SET character_set_client = @saved_cs_client */;

--
-- Table structure for table `checklist_template_item`
--

DROP TABLE IF EXISTS `checklist_template_item`;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!40101 SET character_set_client = utf8mb4 */;
CREATE TABLE `checklist_template_item` (
  `id` bigint(20) unsigned NOT NULL AUTO_INCREMENT,
  `template_id` bigint(20) unsigned NOT NULL,
  `name` varchar(500) NOT NULL,
  `description` text DEFAULT NULL,
  `is_required` tinyint(1) NOT NULL DEFAULT 0,
  `sort_order` int(10) unsigned NOT NULL DEFAULT 1000,
  `active` tinyint(1) NOT NULL DEFAULT 1,
  `created_by_user_id` bigint(20) unsigned NOT NULL,
  `changed_by_user_id` bigint(20) unsigned NOT NULL,
  `created_at` datetime NOT NULL,
  `changed_at` datetime NOT NULL,
  PRIMARY KEY (`id`),
  KEY `idx_checklist_template_item_template_sort` (`template_id`,`active`,`sort_order`,`id`),
  KEY `fk_checklist_template_item_created_by` (`created_by_user_id`),
  KEY `fk_checklist_template_item_changed_by` (`changed_by_user_id`),
  CONSTRAINT `fk_checklist_template_item_changed_by` FOREIGN KEY (`changed_by_user_id`) REFERENCES `user_account` (`id`),
  CONSTRAINT `fk_checklist_template_item_created_by` FOREIGN KEY (`created_by_user_id`) REFERENCES `user_account` (`id`),
  CONSTRAINT `fk_checklist_template_item_template` FOREIGN KEY (`template_id`) REFERENCES `checklist_template` (`id`) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;
/*!40101 SET character_set_client = @saved_cs_client */;

--
-- Table structure for table `checklist_template_queue`
--

DROP TABLE IF EXISTS `checklist_template_queue`;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!40101 SET character_set_client = utf8mb4 */;
CREATE TABLE `checklist_template_queue` (
  `template_id` bigint(20) unsigned NOT NULL,
  `queue_id` bigint(20) unsigned NOT NULL,
  `created_by_user_id` bigint(20) unsigned NOT NULL,
  `created_at` datetime NOT NULL,
  PRIMARY KEY (`template_id`,`queue_id`),
  KEY `idx_checklist_template_queue_queue` (`queue_id`,`template_id`),
  KEY `fk_checklist_template_queue_created_by` (`created_by_user_id`),
  CONSTRAINT `fk_checklist_template_queue_created_by` FOREIGN KEY (`created_by_user_id`) REFERENCES `user_account` (`id`),
  CONSTRAINT `fk_checklist_template_queue_queue` FOREIGN KEY (`queue_id`) REFERENCES `ticket_queue` (`id`) ON DELETE CASCADE,
  CONSTRAINT `fk_checklist_template_queue_template` FOREIGN KEY (`template_id`) REFERENCES `checklist_template` (`id`) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;
/*!40101 SET character_set_client = @saved_cs_client */;

--
-- Table structure for table `checklist_template_service`
--

DROP TABLE IF EXISTS `checklist_template_service`;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!40101 SET character_set_client = utf8mb4 */;
CREATE TABLE `checklist_template_service` (
  `template_id` bigint(20) unsigned NOT NULL,
  `service_id` bigint(20) unsigned NOT NULL,
  `created_by_user_id` bigint(20) unsigned NOT NULL,
  `created_at` datetime NOT NULL,
  PRIMARY KEY (`template_id`,`service_id`),
  KEY `idx_checklist_template_service_service` (`service_id`,`template_id`),
  KEY `fk_checklist_template_service_created_by` (`created_by_user_id`),
  CONSTRAINT `fk_checklist_template_service_created_by` FOREIGN KEY (`created_by_user_id`) REFERENCES `user_account` (`id`),
  CONSTRAINT `fk_checklist_template_service_service` FOREIGN KEY (`service_id`) REFERENCES `service` (`id`) ON DELETE CASCADE,
  CONSTRAINT `fk_checklist_template_service_template` FOREIGN KEY (`template_id`) REFERENCES `checklist_template` (`id`) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;
/*!40101 SET character_set_client = @saved_cs_client */;

--
-- Table structure for table `customer`
--

DROP TABLE IF EXISTS `customer`;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!40101 SET character_set_client = utf8mb4 */;
CREATE TABLE `customer` (
  `id` bigint(20) unsigned NOT NULL AUTO_INCREMENT,
  `customer_number` varchar(100) NOT NULL,
  `name` varchar(255) NOT NULL,
  `active` tinyint(1) NOT NULL DEFAULT 1,
  `created_by_user_id` bigint(20) unsigned NOT NULL,
  `changed_by_user_id` bigint(20) unsigned NOT NULL,
  `created_at` datetime NOT NULL DEFAULT current_timestamp(),
  `changed_at` datetime NOT NULL DEFAULT current_timestamp() ON UPDATE current_timestamp(),
  PRIMARY KEY (`id`),
  UNIQUE KEY `customer_number` (`customer_number`),
  KEY `customer_name` (`name`),
  KEY `customer_active` (`active`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;
/*!40101 SET character_set_client = @saved_cs_client */;

--
-- Table structure for table `customer_service`
--

DROP TABLE IF EXISTS `customer_service`;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!40101 SET character_set_client = utf8mb4 */;
CREATE TABLE `customer_service` (
  `customer_id` bigint(20) unsigned NOT NULL,
  `service_id` bigint(20) unsigned NOT NULL,
  `sla_id` bigint(20) unsigned NOT NULL,
  `active` tinyint(1) NOT NULL DEFAULT 1,
  `created_by_user_id` bigint(20) unsigned NOT NULL,
  `changed_by_user_id` bigint(20) unsigned NOT NULL,
  `created_at` timestamp NOT NULL DEFAULT current_timestamp(),
  `changed_at` timestamp NOT NULL DEFAULT current_timestamp() ON UPDATE current_timestamp(),
  PRIMARY KEY (`customer_id`,`service_id`),
  KEY `customer_service_sla` (`sla_id`),
  KEY `customer_service_active` (`active`),
  KEY `customer_service_service_fk` (`service_id`),
  CONSTRAINT `customer_service_customer_fk` FOREIGN KEY (`customer_id`) REFERENCES `customer` (`id`) ON DELETE CASCADE,
  CONSTRAINT `customer_service_service_fk` FOREIGN KEY (`service_id`) REFERENCES `service` (`id`) ON DELETE CASCADE,
  CONSTRAINT `customer_service_sla_fk` FOREIGN KEY (`sla_id`) REFERENCES `sla` (`id`) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;
/*!40101 SET character_set_client = @saved_cs_client */;

--
-- Table structure for table `customer_user`
--

DROP TABLE IF EXISTS `customer_user`;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!40101 SET character_set_client = utf8mb4 */;
CREATE TABLE `customer_user` (
  `id` bigint(20) unsigned NOT NULL AUTO_INCREMENT,
  `customer_id` bigint(20) unsigned NOT NULL,
  `user_account_id` bigint(20) unsigned NOT NULL,
  `active` tinyint(1) NOT NULL DEFAULT 1,
  `created_by_user_id` bigint(20) unsigned NOT NULL,
  `changed_by_user_id` bigint(20) unsigned NOT NULL,
  `created_at` datetime NOT NULL DEFAULT current_timestamp(),
  `changed_at` datetime NOT NULL DEFAULT current_timestamp() ON UPDATE current_timestamp(),
  PRIMARY KEY (`id`),
  UNIQUE KEY `customer_user_unique` (`customer_id`,`user_account_id`),
  KEY `customer_user_customer_id` (`customer_id`),
  KEY `customer_user_user_account_id` (`user_account_id`),
  KEY `customer_user_active` (`active`),
  CONSTRAINT `fk_customer_user_customer_id` FOREIGN KEY (`customer_id`) REFERENCES `customer` (`id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;
/*!40101 SET character_set_client = @saved_cs_client */;

--
-- Table structure for table `postmaster_imap_account`
--

DROP TABLE IF EXISTS `oauth2_authorization_state`;
DROP TABLE IF EXISTS `postmaster_imap_account`;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!40101 SET character_set_client = utf8mb4 */;
CREATE TABLE `postmaster_imap_account` (
  `id` bigint(20) unsigned NOT NULL AUTO_INCREMENT,
  `name` varchar(100) NOT NULL,
  `email` varchar(255) NOT NULL,
  `queue_id` bigint(20) unsigned DEFAULT NULL,
  `imap_host` varchar(255) NOT NULL DEFAULT '',
  `imap_security` varchar(30) NOT NULL DEFAULT 'imap_starttls',
  `imap_port` int(10) unsigned NOT NULL DEFAULT 143,
  `imap_verify_certificate` tinyint(1) NOT NULL DEFAULT 1,
  `imap_ca_file` varchar(500) NOT NULL DEFAULT '',
  `imap_auth_type` varchar(30) NOT NULL DEFAULT 'password',
  `imap_username` varchar(255) NOT NULL DEFAULT '',
  `imap_password` text DEFAULT NULL,
  `oauth_provider` varchar(100) NOT NULL DEFAULT '',
  `oauth_client_id` text DEFAULT NULL,
  `oauth_client_secret` text DEFAULT NULL,
  `oauth_tenant_id` varchar(255) NOT NULL DEFAULT '',
  `oauth_scope` text DEFAULT NULL,
  `oauth_access_token` mediumtext DEFAULT NULL,
  `oauth_refresh_token` mediumtext DEFAULT NULL,
  `oauth_token_expires_at` datetime DEFAULT NULL,
  `active` tinyint(1) NOT NULL DEFAULT 1,
  `sort_order` int(10) unsigned NOT NULL DEFAULT 1000,
  `last_check_at` datetime DEFAULT NULL,
  `last_check_status` varchar(30) NOT NULL DEFAULT '',
  `last_check_message` text DEFAULT NULL,
  `created_by_user_id` bigint(20) unsigned NOT NULL DEFAULT 1,
  `changed_by_user_id` bigint(20) unsigned NOT NULL DEFAULT 1,
  `created_at` datetime NOT NULL DEFAULT current_timestamp(),
  `changed_at` datetime NOT NULL DEFAULT current_timestamp() ON UPDATE current_timestamp(),
  PRIMARY KEY (`id`),
  UNIQUE KEY `postmaster_imap_account_name` (`name`),
  KEY `postmaster_imap_account_active_sort` (`active`,`sort_order`),
  KEY `postmaster_imap_account_queue_id` (`queue_id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;
/*!40101 SET character_set_client = @saved_cs_client */;

--
-- Table structure for table `postmaster_filter`
--

DROP TABLE IF EXISTS `postmaster_filter`;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!40101 SET character_set_client = utf8mb4 */;
CREATE TABLE `postmaster_filter` (
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
/*!40101 SET character_set_client = @saved_cs_client */;

--
-- Table structure for table `postmaster_filter_condition`
--

DROP TABLE IF EXISTS `postmaster_filter_condition`;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!40101 SET character_set_client = utf8mb4 */;
CREATE TABLE `postmaster_filter_condition` (
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
/*!40101 SET character_set_client = @saved_cs_client */;

--
-- Table structure for table `postmaster_filter_action`
--

DROP TABLE IF EXISTS `postmaster_filter_action`;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!40101 SET character_set_client = utf8mb4 */;
CREATE TABLE `postmaster_filter_action` (
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
/*!40101 SET character_set_client = @saved_cs_client */;

--
-- Table structure for table `postmaster_filter_run`
--

DROP TABLE IF EXISTS `postmaster_filter_run`;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!40101 SET character_set_client = utf8mb4 */;
CREATE TABLE `postmaster_filter_run` (
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
/*!40101 SET character_set_client = @saved_cs_client */;

--
-- Table structure for table `response_template`
--

DROP TABLE IF EXISTS `response_template`;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!40101 SET character_set_client = utf8mb4 */;
CREATE TABLE `response_template` (
  `id` bigint(20) unsigned NOT NULL AUTO_INCREMENT,
  `name` varchar(190) NOT NULL,
  `description` text DEFAULT NULL,
  `content` longtext NOT NULL,
  `active` tinyint(1) NOT NULL DEFAULT 1,
  `sort_order` int(10) unsigned NOT NULL DEFAULT 1000,
  `created_by_user_id` bigint(20) unsigned NOT NULL DEFAULT 1,
  `changed_by_user_id` bigint(20) unsigned NOT NULL DEFAULT 1,
  `created_at` datetime NOT NULL DEFAULT current_timestamp(),
  `changed_at` datetime NOT NULL DEFAULT current_timestamp() ON UPDATE current_timestamp(),
  PRIMARY KEY (`id`),
  UNIQUE KEY `response_template_name_unique` (`name`),
  KEY `response_template_active_sort` (`active`,`sort_order`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;
/*!40101 SET character_set_client = @saved_cs_client */;

--
-- Table structure for table `response_template_translation`
--

DROP TABLE IF EXISTS `response_template_translation`;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!40101 SET character_set_client = utf8mb4 */;
CREATE TABLE `response_template_translation` (
  `template_id` bigint(20) unsigned NOT NULL,
  `language` varchar(10) NOT NULL,
  `name` varchar(190) NOT NULL,
  `description` text DEFAULT NULL,
  `content` longtext NOT NULL,
  `created_by_user_id` bigint(20) unsigned NOT NULL DEFAULT 1,
  `changed_by_user_id` bigint(20) unsigned NOT NULL DEFAULT 1,
  `created_at` datetime NOT NULL DEFAULT current_timestamp(),
  `changed_at` datetime NOT NULL DEFAULT current_timestamp() ON UPDATE current_timestamp(),
  PRIMARY KEY (`template_id`,`language`),
  KEY `response_template_translation_language_name` (`language`,`name`),
  CONSTRAINT `response_template_translation_template_fk` FOREIGN KEY (`template_id`) REFERENCES `response_template` (`id`) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;
/*!40101 SET character_set_client = @saved_cs_client */;

--
-- Table structure for table `response_template_attachment`
--

DROP TABLE IF EXISTS `response_template_attachment`;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!40101 SET character_set_client = utf8mb4 */;
CREATE TABLE `response_template_attachment` (
  `id` bigint(20) unsigned NOT NULL AUTO_INCREMENT,
  `template_id` bigint(20) unsigned NOT NULL,
  `filename` varchar(255) NOT NULL,
  `content_type` varchar(255) NOT NULL DEFAULT 'application/octet-stream',
  `content` longblob NOT NULL,
  `content_size` bigint(20) unsigned NOT NULL DEFAULT 0,
  `created_by_user_id` bigint(20) unsigned NOT NULL DEFAULT 1,
  `created_at` datetime NOT NULL DEFAULT current_timestamp(),
  PRIMARY KEY (`id`),
  KEY `response_template_attachment_template_id` (`template_id`),
  KEY `response_template_attachment_created_at` (`created_at`),
  CONSTRAINT `response_template_attachment_template_fk` FOREIGN KEY (`template_id`) REFERENCES `response_template` (`id`) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;
/*!40101 SET character_set_client = @saved_cs_client */;

--
-- Table structure for table `response_template_queue`
--

DROP TABLE IF EXISTS `response_template_queue`;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!40101 SET character_set_client = utf8mb4 */;
CREATE TABLE `response_template_queue` (
  `id` bigint(20) unsigned NOT NULL AUTO_INCREMENT,
  `template_id` bigint(20) unsigned NOT NULL,
  `queue_id` bigint(20) unsigned NOT NULL,
  `created_by_user_id` bigint(20) unsigned NOT NULL DEFAULT 1,
  `changed_by_user_id` bigint(20) unsigned NOT NULL DEFAULT 1,
  `created_at` datetime NOT NULL DEFAULT current_timestamp(),
  `changed_at` datetime NOT NULL DEFAULT current_timestamp() ON UPDATE current_timestamp(),
  PRIMARY KEY (`id`),
  UNIQUE KEY `response_template_queue_unique` (`template_id`,`queue_id`),
  KEY `response_template_queue_queue_id` (`queue_id`),
  CONSTRAINT `response_template_queue_queue_fk` FOREIGN KEY (`queue_id`) REFERENCES `ticket_queue` (`id`) ON DELETE CASCADE,
  CONSTRAINT `response_template_queue_template_fk` FOREIGN KEY (`template_id`) REFERENCES `response_template` (`id`) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;
/*!40101 SET character_set_client = @saved_cs_client */;

--
-- Table structure for table `salutation`
--

DROP TABLE IF EXISTS `salutation_translation`;
DROP TABLE IF EXISTS `salutation`;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!40101 SET character_set_client = utf8mb4 */;
CREATE TABLE `salutation` (
  `id` bigint(20) unsigned NOT NULL AUTO_INCREMENT,
  `name` varchar(100) NOT NULL,
  `content` longtext NOT NULL,
  `active` tinyint(1) NOT NULL DEFAULT 1,
  `sort_order` int(10) unsigned NOT NULL DEFAULT 1000,
  `created_by_user_id` bigint(20) unsigned NOT NULL,
  `changed_by_user_id` bigint(20) unsigned NOT NULL,
  `created_at` timestamp NOT NULL DEFAULT current_timestamp(),
  `changed_at` timestamp NOT NULL DEFAULT current_timestamp() ON UPDATE current_timestamp(),
  PRIMARY KEY (`id`),
  UNIQUE KEY `salutation_name` (`name`),
  KEY `salutation_active_sort` (`active`,`sort_order`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;
/*!40101 SET character_set_client = @saved_cs_client */;

--
-- Table structure for table `salutation_translation`
--

/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!40101 SET character_set_client = utf8mb4 */;
CREATE TABLE `salutation_translation` (
  `salutation_id` bigint(20) unsigned NOT NULL,
  `language` varchar(10) NOT NULL,
  `name` varchar(100) NOT NULL,
  `content` longtext NOT NULL,
  `created_by_user_id` bigint(20) unsigned NOT NULL DEFAULT 1,
  `changed_by_user_id` bigint(20) unsigned NOT NULL DEFAULT 1,
  `created_at` datetime NOT NULL DEFAULT current_timestamp(),
  `changed_at` datetime NOT NULL DEFAULT current_timestamp() ON UPDATE current_timestamp(),
  PRIMARY KEY (`salutation_id`,`language`),
  KEY `salutation_translation_language_name` (`language`,`name`),
  CONSTRAINT `salutation_translation_salutation_fk` FOREIGN KEY (`salutation_id`) REFERENCES `salutation` (`id`) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;
/*!40101 SET character_set_client = @saved_cs_client */;

--
-- Table structure for table `service`
--

DROP TABLE IF EXISTS `service`;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!40101 SET character_set_client = utf8mb4 */;
CREATE TABLE `service` (
  `id` bigint(20) unsigned NOT NULL AUTO_INCREMENT,
  `parent_id` bigint(20) unsigned DEFAULT NULL,
  `name` varchar(255) NOT NULL,
  `full_name` varchar(750) NOT NULL,
  `description` text DEFAULT NULL,
  `active` tinyint(1) NOT NULL DEFAULT 1,
  `sort_order` int(10) unsigned NOT NULL DEFAULT 1000,
  `created_by_user_id` bigint(20) unsigned NOT NULL,
  `changed_by_user_id` bigint(20) unsigned NOT NULL,
  `created_at` timestamp NOT NULL DEFAULT current_timestamp(),
  `changed_at` timestamp NOT NULL DEFAULT current_timestamp() ON UPDATE current_timestamp(),
  PRIMARY KEY (`id`),
  UNIQUE KEY `service_full_name` (`full_name`),
  KEY `service_parent` (`parent_id`),
  KEY `service_active_sort` (`active`,`sort_order`),
  CONSTRAINT `service_parent_fk` FOREIGN KEY (`parent_id`) REFERENCES `service` (`id`) ON DELETE SET NULL
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;
/*!40101 SET character_set_client = @saved_cs_client */;

--
-- Table structure for table `signature`
--

DROP TABLE IF EXISTS `signature_translation`;
DROP TABLE IF EXISTS `signature`;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!40101 SET character_set_client = utf8mb4 */;
CREATE TABLE `signature` (
  `id` bigint(20) unsigned NOT NULL AUTO_INCREMENT,
  `name` varchar(100) NOT NULL,
  `content` longtext NOT NULL,
  `active` tinyint(1) NOT NULL DEFAULT 1,
  `sort_order` int(10) unsigned NOT NULL DEFAULT 1000,
  `created_by_user_id` bigint(20) unsigned NOT NULL,
  `changed_by_user_id` bigint(20) unsigned NOT NULL,
  `created_at` timestamp NOT NULL DEFAULT current_timestamp(),
  `changed_at` timestamp NOT NULL DEFAULT current_timestamp() ON UPDATE current_timestamp(),
  PRIMARY KEY (`id`),
  UNIQUE KEY `signature_name` (`name`),
  KEY `signature_active_sort` (`active`,`sort_order`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;
/*!40101 SET character_set_client = @saved_cs_client */;

--
-- Table structure for table `signature_translation`
--

/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!40101 SET character_set_client = utf8mb4 */;
CREATE TABLE `signature_translation` (
  `signature_id` bigint(20) unsigned NOT NULL,
  `language` varchar(10) NOT NULL,
  `name` varchar(100) NOT NULL,
  `content` longtext NOT NULL,
  `created_by_user_id` bigint(20) unsigned NOT NULL DEFAULT 1,
  `changed_by_user_id` bigint(20) unsigned NOT NULL DEFAULT 1,
  `created_at` datetime NOT NULL DEFAULT current_timestamp(),
  `changed_at` datetime NOT NULL DEFAULT current_timestamp() ON UPDATE current_timestamp(),
  PRIMARY KEY (`signature_id`,`language`),
  KEY `signature_translation_language_name` (`language`,`name`),
  CONSTRAINT `signature_translation_signature_fk` FOREIGN KEY (`signature_id`) REFERENCES `signature` (`id`) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;
/*!40101 SET character_set_client = @saved_cs_client */;

--
-- Table structure for table `sla`
--

DROP TABLE IF EXISTS `sla`;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!40101 SET character_set_client = utf8mb4 */;
CREATE TABLE `sla` (
  `id` bigint(20) unsigned NOT NULL AUTO_INCREMENT,
  `name` varchar(255) NOT NULL,
  `service_id` bigint(20) unsigned NOT NULL,
  `calendar_id` bigint(20) unsigned NOT NULL,
  `update_mode` varchar(30) NOT NULL DEFAULT 'customer_response',
  `first_response_minutes` int(10) unsigned NOT NULL DEFAULT 0,
  `update_minutes` int(10) unsigned NOT NULL DEFAULT 0,
  `solution_minutes` int(10) unsigned NOT NULL DEFAULT 0,
  `is_default` tinyint(1) NOT NULL DEFAULT 0,
  `active` tinyint(1) NOT NULL DEFAULT 1,
  `sort_order` int(10) unsigned NOT NULL DEFAULT 1000,
  `created_by_user_id` bigint(20) unsigned NOT NULL,
  `changed_by_user_id` bigint(20) unsigned NOT NULL,
  `created_at` timestamp NOT NULL DEFAULT current_timestamp(),
  `changed_at` timestamp NOT NULL DEFAULT current_timestamp() ON UPDATE current_timestamp(),
  PRIMARY KEY (`id`),
  UNIQUE KEY `sla_service_name` (`service_id`,`name`),
  KEY `sla_service_active_sort` (`service_id`,`active`,`sort_order`),
  KEY `sla_calendar` (`calendar_id`),
  CONSTRAINT `sla_calendar_fk` FOREIGN KEY (`calendar_id`) REFERENCES `calendar` (`id`),
  CONSTRAINT `sla_service_fk` FOREIGN KEY (`service_id`) REFERENCES `service` (`id`) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;
/*!40101 SET character_set_client = @saved_cs_client */;

--
-- Table structure for table `smtp_account`
--

DROP TABLE IF EXISTS `smtp_account`;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!40101 SET character_set_client = utf8mb4 */;
CREATE TABLE `smtp_account` (
  `id` bigint(20) unsigned NOT NULL AUTO_INCREMENT,
  `name` varchar(100) NOT NULL,
  `smtp_host` varchar(255) NOT NULL DEFAULT '',
  `smtp_security` varchar(30) NOT NULL DEFAULT 'smtp_starttls',
  `smtp_port` int(10) unsigned NOT NULL DEFAULT 587,
  `smtp_verify_certificate` tinyint(1) NOT NULL DEFAULT 1,
  `smtp_ca_file` varchar(500) NOT NULL DEFAULT '',
  `smtp_auth_type` varchar(30) NOT NULL DEFAULT 'password',
  `smtp_username` varchar(255) NOT NULL DEFAULT '',
  `smtp_password` text DEFAULT NULL,
  `oauth_provider` varchar(100) NOT NULL DEFAULT '',
  `oauth_client_id` text DEFAULT NULL,
  `oauth_client_secret` text DEFAULT NULL,
  `oauth_tenant_id` varchar(255) NOT NULL DEFAULT '',
  `oauth_scope` text DEFAULT NULL,
  `oauth_access_token` mediumtext DEFAULT NULL,
  `oauth_refresh_token` mediumtext DEFAULT NULL,
  `oauth_token_expires_at` datetime DEFAULT NULL,
  `active` tinyint(1) NOT NULL DEFAULT 1,
  `sort_order` int(10) unsigned NOT NULL DEFAULT 1000,
  `last_check_at` datetime DEFAULT NULL,
  `last_check_status` varchar(30) NOT NULL DEFAULT '',
  `last_check_message` text DEFAULT NULL,
  `created_by_user_id` bigint(20) unsigned NOT NULL DEFAULT 1,
  `changed_by_user_id` bigint(20) unsigned NOT NULL DEFAULT 1,
  `created_at` datetime NOT NULL DEFAULT current_timestamp(),
  `changed_at` datetime NOT NULL DEFAULT current_timestamp() ON UPDATE current_timestamp(),
  PRIMARY KEY (`id`),
  UNIQUE KEY `smtp_account_name` (`name`),
  KEY `smtp_account_active_sort` (`active`,`sort_order`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;
/*!40101 SET character_set_client = @saved_cs_client */;

--
-- Table structure for table `system_email`
--

DROP TABLE IF EXISTS `system_email`;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!40101 SET character_set_client = utf8mb4 */;
CREATE TABLE `system_email` (
  `id` bigint(20) unsigned NOT NULL AUTO_INCREMENT,
  `name` varchar(100) NOT NULL,
  `email` varchar(255) NOT NULL,
  `active` tinyint(1) NOT NULL DEFAULT 1,
  `sort_order` int(10) unsigned NOT NULL DEFAULT 1000,
  `created_by_user_id` bigint(20) unsigned NOT NULL,
  `changed_by_user_id` bigint(20) unsigned NOT NULL,
  `created_at` timestamp NOT NULL DEFAULT current_timestamp(),
  `changed_at` timestamp NOT NULL DEFAULT current_timestamp() ON UPDATE current_timestamp(),
  PRIMARY KEY (`id`),
  UNIQUE KEY `system_email_name` (`name`),
  KEY `system_email_active_sort` (`active`,`sort_order`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;
/*!40101 SET character_set_client = @saved_cs_client */;

--
-- Table structure for table `system_setting`
--

DROP TABLE IF EXISTS `system_setting`;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!40101 SET character_set_client = utf8mb4 */;
CREATE TABLE `system_setting` (
  `id` bigint(20) unsigned NOT NULL AUTO_INCREMENT,
  `setting_key` varchar(190) NOT NULL,
  `setting_value` longtext DEFAULT NULL,
  `created_by_user_id` bigint(20) unsigned NOT NULL DEFAULT 1,
  `changed_by_user_id` bigint(20) unsigned NOT NULL DEFAULT 1,
  `created_at` datetime NOT NULL DEFAULT current_timestamp(),
  `changed_at` datetime NOT NULL DEFAULT current_timestamp() ON UPDATE current_timestamp(),
  PRIMARY KEY (`id`),
  UNIQUE KEY `system_setting_key_unique` (`setting_key`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;
/*!40101 SET character_set_client = @saved_cs_client */;

--
-- Table structure for table `ticket`
--

DROP TABLE IF EXISTS `ticket`;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!40101 SET character_set_client = utf8mb4 */;
CREATE TABLE `ticket` (
  `id` bigint(20) unsigned NOT NULL AUTO_INCREMENT,
  `ticket_number` varchar(50) NOT NULL,
  `title` varchar(500) NOT NULL,
  `queue_id` bigint(20) unsigned NOT NULL,
  `state_id` bigint(20) unsigned NOT NULL,
  `priority_id` bigint(20) unsigned NOT NULL,
  `customer_id` bigint(20) unsigned DEFAULT NULL,
  `customer_user_id` bigint(20) unsigned DEFAULT NULL,
  `owner_user_id` bigint(20) unsigned DEFAULT NULL,
  `responsible_user_id` bigint(20) unsigned DEFAULT NULL,
  `service_id` bigint(20) unsigned DEFAULT NULL,
  `sla_id` bigint(20) unsigned DEFAULT NULL,
  `sla_source` varchar(20) NOT NULL DEFAULT 'queue',
  `sla_assignment_source` varchar(20) NOT NULL DEFAULT 'queue',
  `sla_name_snapshot` varchar(255) DEFAULT NULL,
  `sla_calendar_id` bigint(20) unsigned DEFAULT NULL,
  `sla_update_mode` varchar(30) NOT NULL DEFAULT 'customer_response',
  `sla_first_response_minutes` int(10) unsigned NOT NULL DEFAULT 0,
  `sla_update_minutes` int(10) unsigned NOT NULL DEFAULT 0,
  `sla_solution_minutes` int(10) unsigned NOT NULL DEFAULT 0,
  `created_by_user_id` bigint(20) unsigned NOT NULL,
  `changed_by_user_id` bigint(20) unsigned NOT NULL,
  `first_response_due_at` datetime DEFAULT NULL,
  `first_response_at` datetime DEFAULT NULL,
  `update_due_at` datetime DEFAULT NULL,
  `last_customer_article_at` datetime DEFAULT NULL,
  `last_agent_article_at` datetime DEFAULT NULL,
  `solution_due_at` datetime DEFAULT NULL,
  `solution_at` datetime DEFAULT NULL,
  `pending_until` datetime DEFAULT NULL,
  `pending_started_at` datetime DEFAULT NULL,
  `pending_total_minutes` int(10) unsigned NOT NULL DEFAULT 0,
  `sla_pause_started_at` datetime DEFAULT NULL,
  `sla_pause_total_minutes` int(10) unsigned NOT NULL DEFAULT 0,
  `escalation_state` varchar(30) NOT NULL DEFAULT 'normal',
  `sla_first_response_breached` tinyint(1) NOT NULL DEFAULT 0,
  `sla_update_breached` tinyint(1) NOT NULL DEFAULT 0,
  `sla_solution_breached` tinyint(1) NOT NULL DEFAULT 0,
  `created_at` datetime NOT NULL DEFAULT current_timestamp(),
  `changed_at` datetime NOT NULL DEFAULT current_timestamp() ON UPDATE current_timestamp(),
  PRIMARY KEY (`id`),
  UNIQUE KEY `ticket_number` (`ticket_number`),
  KEY `ticket_queue_id` (`queue_id`),
  KEY `ticket_state_id` (`state_id`),
  KEY `ticket_priority_id` (`priority_id`),
  KEY `ticket_customer_id` (`customer_id`),
  KEY `ticket_customer_user_id` (`customer_user_id`),
  KEY `ticket_owner_user_id` (`owner_user_id`),
  KEY `ticket_responsible_user_id` (`responsible_user_id`),
  KEY `ticket_created_at` (`created_at`),
  KEY `ticket_changed_at` (`changed_at`),
  KEY `ticket_service_id` (`service_id`),
  KEY `ticket_sla_id` (`sla_id`),
  KEY `ticket_sla_calendar_id` (`sla_calendar_id`),
  KEY `ticket_solution_at` (`solution_at`),
  KEY `ticket_pending_until` (`pending_until`),
  KEY `ticket_first_response_due_at` (`first_response_due_at`),
  KEY `ticket_update_due_at` (`update_due_at`),
  KEY `ticket_solution_due_at` (`solution_due_at`),
  FULLTEXT KEY `ticket_fulltext_title` (`title`),
  CONSTRAINT `fk_ticket_customer_id` FOREIGN KEY (`customer_id`) REFERENCES `customer` (`id`),
  CONSTRAINT `fk_ticket_customer_user_id` FOREIGN KEY (`customer_user_id`) REFERENCES `customer_user` (`id`),
  CONSTRAINT `fk_ticket_priority_id` FOREIGN KEY (`priority_id`) REFERENCES `ticket_priority` (`id`),
  CONSTRAINT `fk_ticket_queue_id` FOREIGN KEY (`queue_id`) REFERENCES `ticket_queue` (`id`),
  CONSTRAINT `fk_ticket_state_id` FOREIGN KEY (`state_id`) REFERENCES `ticket_state` (`id`),
  CONSTRAINT `ticket_service_fk` FOREIGN KEY (`service_id`) REFERENCES `service` (`id`) ON DELETE SET NULL,
  CONSTRAINT `ticket_sla_calendar_fk` FOREIGN KEY (`sla_calendar_id`) REFERENCES `calendar` (`id`) ON DELETE SET NULL,
  CONSTRAINT `ticket_sla_fk` FOREIGN KEY (`sla_id`) REFERENCES `sla` (`id`) ON DELETE SET NULL
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;
/*!40101 SET character_set_client = @saved_cs_client */;
/*!50003 SET @saved_cs_client      = @@character_set_client */ ;
/*!50003 SET @saved_cs_results     = @@character_set_results */ ;
/*!50003 SET @saved_col_connection = @@collation_connection */ ;
/*!50003 SET character_set_client  = utf8mb3 */ ;
/*!50003 SET character_set_results = utf8mb3 */ ;
/*!50003 SET collation_connection  = utf8mb3_general_ci */ ;
/*!50003 SET @saved_sql_mode       = @@sql_mode */ ;
/*!50003 SET sql_mode              = 'STRICT_TRANS_TABLES,ERROR_FOR_DIVISION_BY_ZERO,NO_ENGINE_SUBSTITUTION' */ ;
DELIMITER ;;
/*!50003 CREATE*/ /*!50003 TRIGGER `qisutu_automation_ticket_insert`
AFTER INSERT ON `ticket`
FOR EACH ROW
BEGIN
    INSERT INTO `automation_event` (
        `event_name`, `ticket_id`, `source_rule_id`, `source_job_id`, `depth`, `suppress_notifications`, `created_at`
    ) VALUES (
        'ticket_created', NEW.`id`, NULLIF(@qisutu_automation_rule_id, 0),
        NULLIF(@qisutu_automation_job_id, 0), COALESCE(@qisutu_automation_depth, 0) + 1,
        COALESCE(@qisutu_suppress_notifications, 0), NOW()
    );
END */;;
DELIMITER ;
/*!50003 SET sql_mode              = @saved_sql_mode */ ;
/*!50003 SET character_set_client  = @saved_cs_client */ ;
/*!50003 SET character_set_results = @saved_cs_results */ ;
/*!50003 SET collation_connection  = @saved_col_connection */ ;
/*!50003 SET @saved_cs_client      = @@character_set_client */ ;
/*!50003 SET @saved_cs_results     = @@character_set_results */ ;
/*!50003 SET @saved_col_connection = @@collation_connection */ ;
/*!50003 SET character_set_client  = utf8mb3 */ ;
/*!50003 SET character_set_results = utf8mb3 */ ;
/*!50003 SET collation_connection  = utf8mb3_general_ci */ ;
/*!50003 SET @saved_sql_mode       = @@sql_mode */ ;
/*!50003 SET sql_mode              = 'STRICT_TRANS_TABLES,ERROR_FOR_DIVISION_BY_ZERO,NO_ENGINE_SUBSTITUTION' */ ;
DELIMITER ;;
/*!50003 CREATE*/ /*!50003 TRIGGER `qisutu_automation_ticket_update`
AFTER UPDATE ON `ticket`
FOR EACH ROW
BEGIN
    DECLARE old_state_type varchar(30) DEFAULT '';
    DECLARE new_state_type varchar(30) DEFAULT '';

    SELECT `state_type` INTO old_state_type FROM `ticket_state` WHERE `id` = OLD.`state_id` LIMIT 1;
    SELECT `state_type` INTO new_state_type FROM `ticket_state` WHERE `id` = NEW.`state_id` LIMIT 1;

    INSERT INTO `automation_event` (
        `event_name`, `ticket_id`, `source_rule_id`, `source_job_id`, `depth`, `suppress_notifications`, `created_at`
    ) VALUES (
        'ticket_changed', NEW.`id`, NULLIF(@qisutu_automation_rule_id, 0),
        NULLIF(@qisutu_automation_job_id, 0), COALESCE(@qisutu_automation_depth, 0) + 1,
        COALESCE(@qisutu_suppress_notifications, 0), NOW()
    );

    IF NOT (OLD.`state_id` <=> NEW.`state_id`) THEN
        INSERT INTO `automation_event` (`event_name`,`ticket_id`,`source_rule_id`,`source_job_id`,`depth`,`suppress_notifications`,`created_at`)
        VALUES ('status_changed',NEW.`id`,NULLIF(@qisutu_automation_rule_id,0),NULLIF(@qisutu_automation_job_id,0),COALESCE(@qisutu_automation_depth,0)+1,COALESCE(@qisutu_suppress_notifications,0),NOW());
    END IF;
    IF NOT (OLD.`queue_id` <=> NEW.`queue_id`) THEN
        INSERT INTO `automation_event` (`event_name`,`ticket_id`,`source_rule_id`,`source_job_id`,`depth`,`suppress_notifications`,`created_at`)
        VALUES ('queue_changed',NEW.`id`,NULLIF(@qisutu_automation_rule_id,0),NULLIF(@qisutu_automation_job_id,0),COALESCE(@qisutu_automation_depth,0)+1,COALESCE(@qisutu_suppress_notifications,0),NOW());
    END IF;
    IF NOT (OLD.`priority_id` <=> NEW.`priority_id`) THEN
        INSERT INTO `automation_event` (`event_name`,`ticket_id`,`source_rule_id`,`source_job_id`,`depth`,`suppress_notifications`,`created_at`)
        VALUES ('priority_changed',NEW.`id`,NULLIF(@qisutu_automation_rule_id,0),NULLIF(@qisutu_automation_job_id,0),COALESCE(@qisutu_automation_depth,0)+1,COALESCE(@qisutu_suppress_notifications,0),NOW());
    END IF;
    IF NOT (OLD.`owner_user_id` <=> NEW.`owner_user_id`) THEN
        INSERT INTO `automation_event` (`event_name`,`ticket_id`,`source_rule_id`,`source_job_id`,`depth`,`suppress_notifications`,`created_at`)
        VALUES ('owner_changed',NEW.`id`,NULLIF(@qisutu_automation_rule_id,0),NULLIF(@qisutu_automation_job_id,0),COALESCE(@qisutu_automation_depth,0)+1,COALESCE(@qisutu_suppress_notifications,0),NOW());
    END IF;
    IF NOT (OLD.`responsible_user_id` <=> NEW.`responsible_user_id`) THEN
        INSERT INTO `automation_event` (`event_name`,`ticket_id`,`source_rule_id`,`source_job_id`,`depth`,`suppress_notifications`,`created_at`)
        VALUES ('responsible_changed',NEW.`id`,NULLIF(@qisutu_automation_rule_id,0),NULLIF(@qisutu_automation_job_id,0),COALESCE(@qisutu_automation_depth,0)+1,COALESCE(@qisutu_suppress_notifications,0),NOW());
    END IF;
    IF NOT (OLD.`service_id` <=> NEW.`service_id`) THEN
        INSERT INTO `automation_event` (`event_name`,`ticket_id`,`source_rule_id`,`source_job_id`,`depth`,`suppress_notifications`,`created_at`)
        VALUES ('service_changed',NEW.`id`,NULLIF(@qisutu_automation_rule_id,0),NULLIF(@qisutu_automation_job_id,0),COALESCE(@qisutu_automation_depth,0)+1,COALESCE(@qisutu_suppress_notifications,0),NOW());
    END IF;
    IF NOT (OLD.`sla_id` <=> NEW.`sla_id`) THEN
        INSERT INTO `automation_event` (`event_name`,`ticket_id`,`source_rule_id`,`source_job_id`,`depth`,`suppress_notifications`,`created_at`)
        VALUES ('sla_changed',NEW.`id`,NULLIF(@qisutu_automation_rule_id,0),NULLIF(@qisutu_automation_job_id,0),COALESCE(@qisutu_automation_depth,0)+1,COALESCE(@qisutu_suppress_notifications,0),NOW());
    END IF;
    IF old_state_type <> 'closed' AND new_state_type = 'closed' THEN
        INSERT INTO `automation_event` (`event_name`,`ticket_id`,`source_rule_id`,`source_job_id`,`depth`,`suppress_notifications`,`created_at`)
        VALUES ('ticket_closed',NEW.`id`,NULLIF(@qisutu_automation_rule_id,0),NULLIF(@qisutu_automation_job_id,0),COALESCE(@qisutu_automation_depth,0)+1,COALESCE(@qisutu_suppress_notifications,0),NOW());
    END IF;
    IF old_state_type = 'closed' AND new_state_type <> 'closed' THEN
        INSERT INTO `automation_event` (`event_name`,`ticket_id`,`source_rule_id`,`source_job_id`,`depth`,`suppress_notifications`,`created_at`)
        VALUES ('ticket_reopened',NEW.`id`,NULLIF(@qisutu_automation_rule_id,0),NULLIF(@qisutu_automation_job_id,0),COALESCE(@qisutu_automation_depth,0)+1,COALESCE(@qisutu_suppress_notifications,0),NOW());
    END IF;
    IF NOT (OLD.`escalation_state` <=> NEW.`escalation_state`) AND NEW.`escalation_state` = 'warning' THEN
        INSERT INTO `automation_event` (`event_name`,`ticket_id`,`source_rule_id`,`source_job_id`,`depth`,`suppress_notifications`,`created_at`)
        VALUES ('sla_warning',NEW.`id`,NULLIF(@qisutu_automation_rule_id,0),NULLIF(@qisutu_automation_job_id,0),COALESCE(@qisutu_automation_depth,0)+1,COALESCE(@qisutu_suppress_notifications,0),NOW());
    END IF;
    IF NOT (OLD.`escalation_state` <=> NEW.`escalation_state`) AND NEW.`escalation_state` = 'escalated' THEN
        INSERT INTO `automation_event` (`event_name`,`ticket_id`,`source_rule_id`,`source_job_id`,`depth`,`suppress_notifications`,`created_at`)
        VALUES ('sla_breached',NEW.`id`,NULLIF(@qisutu_automation_rule_id,0),NULLIF(@qisutu_automation_job_id,0),COALESCE(@qisutu_automation_depth,0)+1,COALESCE(@qisutu_suppress_notifications,0),NOW());
    END IF;
END */;;
DELIMITER ;
/*!50003 SET sql_mode              = @saved_sql_mode */ ;
/*!50003 SET character_set_client  = @saved_cs_client */ ;
/*!50003 SET character_set_results = @saved_cs_results */ ;
/*!50003 SET collation_connection  = @saved_col_connection */ ;

--
-- Table structure for table `ticket_article`
--

DROP TABLE IF EXISTS `ticket_article`;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!40101 SET character_set_client = utf8mb4 */;
CREATE TABLE `ticket_article` (
  `id` bigint(20) unsigned NOT NULL AUTO_INCREMENT,
  `ticket_id` bigint(20) unsigned NOT NULL,
  `article_number` int(10) unsigned NOT NULL DEFAULT 1,
  `channel` varchar(50) NOT NULL DEFAULT 'note',
  `sender_type` varchar(50) NOT NULL DEFAULT 'agent',
  `from_name` varchar(255) NOT NULL DEFAULT '',
  `from_email` varchar(255) NOT NULL DEFAULT '',
  `to_name` varchar(255) NOT NULL DEFAULT '',
  `to_email` varchar(255) NOT NULL DEFAULT '',
  `cc` text DEFAULT NULL,
  `subject` varchar(255) NOT NULL DEFAULT '',
  `body` longtext NOT NULL,
  `search_text` longtext DEFAULT NULL,
  `content_type` varchar(100) NOT NULL DEFAULT 'text/plain',
  `visibility` varchar(20) NOT NULL DEFAULT 'both',
  `internal` tinyint(1) NOT NULL DEFAULT 0,
  `created_by_user_id` bigint(20) unsigned NOT NULL,
  `changed_by_user_id` bigint(20) unsigned NOT NULL,
  `created_at` datetime NOT NULL,
  `changed_at` datetime NOT NULL,
  PRIMARY KEY (`id`),
  KEY `ticket_article_ticket_id` (`ticket_id`),
  KEY `ticket_article_created_at` (`created_at`),
  KEY `ticket_article_created_by_user_id` (`created_by_user_id`),
  KEY `ticket_article_changed_by_user_id` (`changed_by_user_id`),
  KEY `ticket_article_visibility_idx` (`visibility`),
  FULLTEXT KEY `ticket_article_fulltext_search` (`subject`,`search_text`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;
/*!40101 SET character_set_client = @saved_cs_client */;
/*!50003 SET @saved_cs_client      = @@character_set_client */ ;
/*!50003 SET @saved_cs_results     = @@character_set_results */ ;
/*!50003 SET @saved_col_connection = @@collation_connection */ ;
/*!50003 SET character_set_client  = utf8mb3 */ ;
/*!50003 SET character_set_results = utf8mb3 */ ;
/*!50003 SET collation_connection  = utf8mb3_general_ci */ ;
/*!50003 SET @saved_sql_mode       = @@sql_mode */ ;
/*!50003 SET sql_mode              = 'STRICT_TRANS_TABLES,ERROR_FOR_DIVISION_BY_ZERO,NO_ENGINE_SUBSTITUTION' */ ;
DELIMITER ;;
/*!50003 CREATE*/ /*!50003 TRIGGER `qisutu_automation_article_insert`
AFTER INSERT ON `ticket_article`
FOR EACH ROW
BEGIN
    INSERT INTO `automation_event` (
        `event_name`, `ticket_id`, `source_rule_id`, `source_job_id`, `depth`, `suppress_notifications`, `created_at`
    ) VALUES (
        'article_created', NEW.`ticket_id`, NULLIF(@qisutu_automation_rule_id, 0),
        NULLIF(@qisutu_automation_job_id, 0), COALESCE(@qisutu_automation_depth, 0) + 1,
        COALESCE(@qisutu_suppress_notifications, 0), NOW()
    );

    IF NEW.`sender_type` = 'customer' THEN
        INSERT INTO `automation_event` (`event_name`,`ticket_id`,`source_rule_id`,`source_job_id`,`depth`,`suppress_notifications`,`created_at`)
        VALUES ('customer_article_created',NEW.`ticket_id`,NULLIF(@qisutu_automation_rule_id,0),NULLIF(@qisutu_automation_job_id,0),COALESCE(@qisutu_automation_depth,0)+1,COALESCE(@qisutu_suppress_notifications,0),NOW());
    END IF;
    IF NEW.`sender_type` = 'agent' AND NEW.`channel` = 'email' THEN
        INSERT INTO `automation_event` (`event_name`,`ticket_id`,`source_rule_id`,`source_job_id`,`depth`,`suppress_notifications`,`created_at`)
        VALUES ('agent_article_created',NEW.`ticket_id`,NULLIF(@qisutu_automation_rule_id,0),NULLIF(@qisutu_automation_job_id,0),COALESCE(@qisutu_automation_depth,0)+1,COALESCE(@qisutu_suppress_notifications,0),NOW());
    END IF;
    IF NEW.`channel` = 'note' THEN
        INSERT INTO `automation_event` (`event_name`,`ticket_id`,`source_rule_id`,`source_job_id`,`depth`,`suppress_notifications`,`created_at`)
        VALUES ('note_created',NEW.`ticket_id`,NULLIF(@qisutu_automation_rule_id,0),NULLIF(@qisutu_automation_job_id,0),COALESCE(@qisutu_automation_depth,0)+1,COALESCE(@qisutu_suppress_notifications,0),NOW());
    END IF;
END */;;
DELIMITER ;
/*!50003 SET sql_mode              = @saved_sql_mode */ ;
/*!50003 SET character_set_client  = @saved_cs_client */ ;
/*!50003 SET character_set_results = @saved_cs_results */ ;
/*!50003 SET collation_connection  = @saved_col_connection */ ;

--
-- Table structure for table `ticket_article_attachment`
--

DROP TABLE IF EXISTS `ticket_article_attachment`;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!40101 SET character_set_client = utf8mb4 */;
CREATE TABLE `ticket_article_attachment` (
  `id` bigint(20) unsigned NOT NULL AUTO_INCREMENT,
  `ticket_id` bigint(20) unsigned NOT NULL,
  `article_id` bigint(20) unsigned NOT NULL,
  `filename` varchar(255) NOT NULL,
  `content_type` varchar(255) NOT NULL DEFAULT 'application/octet-stream',
  `content` longblob NOT NULL,
  `content_size` bigint(20) unsigned NOT NULL DEFAULT 0,
  `content_id` varchar(255) DEFAULT NULL,
  `content_disposition` varchar(50) NOT NULL DEFAULT 'attachment',
  `created_by_user_id` bigint(20) unsigned NOT NULL DEFAULT 1,
  `created_at` datetime NOT NULL DEFAULT current_timestamp(),
  PRIMARY KEY (`id`),
  KEY `ticket_article_attachment_ticket_id` (`ticket_id`),
  KEY `ticket_article_attachment_article_id` (`article_id`),
  KEY `ticket_article_attachment_created_at` (`created_at`),
  FULLTEXT KEY `ticket_attachment_fulltext_filename` (`filename`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;
/*!40101 SET character_set_client = @saved_cs_client */;

--
-- Table structure for ticket relations and copied article provenance
--

DROP TABLE IF EXISTS `ticket_article_origin`;
DROP TABLE IF EXISTS `ticket_link`;
CREATE TABLE `ticket_link` (
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

CREATE TABLE `ticket_article_origin` (
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

--
-- Table structure for table `ticket_checklist`
--

DROP TABLE IF EXISTS `ticket_checklist`;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!40101 SET character_set_client = utf8mb4 */;
CREATE TABLE `ticket_checklist` (
  `id` bigint(20) unsigned NOT NULL AUTO_INCREMENT,
  `ticket_id` bigint(20) unsigned NOT NULL,
  `template_id` bigint(20) unsigned DEFAULT NULL,
  `name` varchar(255) NOT NULL,
  `description` text DEFAULT NULL,
  `source` enum('automatic','manual','automation') NOT NULL DEFAULT 'manual',
  `sort_order` int(10) unsigned NOT NULL DEFAULT 1000,
  `removed_at` datetime DEFAULT NULL,
  `removed_by_user_id` bigint(20) unsigned DEFAULT NULL,
  `created_by_user_id` bigint(20) unsigned NOT NULL,
  `changed_by_user_id` bigint(20) unsigned NOT NULL,
  `created_at` datetime NOT NULL,
  `changed_at` datetime NOT NULL,
  PRIMARY KEY (`id`),
  KEY `idx_ticket_checklist_ticket` (`ticket_id`,`removed_at`,`sort_order`,`id`),
  KEY `idx_ticket_checklist_ticket_template` (`ticket_id`,`template_id`,`removed_at`),
  KEY `idx_ticket_checklist_template` (`template_id`),
  KEY `fk_ticket_checklist_removed_by` (`removed_by_user_id`),
  KEY `fk_ticket_checklist_created_by` (`created_by_user_id`),
  KEY `fk_ticket_checklist_changed_by` (`changed_by_user_id`),
  CONSTRAINT `fk_ticket_checklist_changed_by` FOREIGN KEY (`changed_by_user_id`) REFERENCES `user_account` (`id`),
  CONSTRAINT `fk_ticket_checklist_created_by` FOREIGN KEY (`created_by_user_id`) REFERENCES `user_account` (`id`),
  CONSTRAINT `fk_ticket_checklist_removed_by` FOREIGN KEY (`removed_by_user_id`) REFERENCES `user_account` (`id`),
  CONSTRAINT `fk_ticket_checklist_template` FOREIGN KEY (`template_id`) REFERENCES `checklist_template` (`id`) ON DELETE SET NULL,
  CONSTRAINT `fk_ticket_checklist_ticket` FOREIGN KEY (`ticket_id`) REFERENCES `ticket` (`id`) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;
/*!40101 SET character_set_client = @saved_cs_client */;

--
-- Table structure for table `ticket_checklist_audit`
--

DROP TABLE IF EXISTS `ticket_checklist_audit`;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!40101 SET character_set_client = utf8mb4 */;
CREATE TABLE `ticket_checklist_audit` (
  `id` bigint(20) unsigned NOT NULL AUTO_INCREMENT,
  `ticket_id` bigint(20) unsigned NOT NULL,
  `ticket_checklist_id` bigint(20) unsigned DEFAULT NULL,
  `ticket_checklist_item_id` bigint(20) unsigned DEFAULT NULL,
  `action` varchar(50) NOT NULL,
  `details` text DEFAULT NULL,
  `created_by_user_id` bigint(20) unsigned NOT NULL,
  `created_at` datetime NOT NULL,
  PRIMARY KEY (`id`),
  KEY `idx_ticket_checklist_audit_ticket` (`ticket_id`,`created_at`,`id`),
  KEY `fk_ticket_checklist_audit_checklist` (`ticket_checklist_id`),
  KEY `fk_ticket_checklist_audit_item` (`ticket_checklist_item_id`),
  KEY `fk_ticket_checklist_audit_created_by` (`created_by_user_id`),
  CONSTRAINT `fk_ticket_checklist_audit_checklist` FOREIGN KEY (`ticket_checklist_id`) REFERENCES `ticket_checklist` (`id`) ON DELETE SET NULL,
  CONSTRAINT `fk_ticket_checklist_audit_created_by` FOREIGN KEY (`created_by_user_id`) REFERENCES `user_account` (`id`),
  CONSTRAINT `fk_ticket_checklist_audit_item` FOREIGN KEY (`ticket_checklist_item_id`) REFERENCES `ticket_checklist_item` (`id`) ON DELETE SET NULL,
  CONSTRAINT `fk_ticket_checklist_audit_ticket` FOREIGN KEY (`ticket_id`) REFERENCES `ticket` (`id`) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;
/*!40101 SET character_set_client = @saved_cs_client */;

--
-- Table structure for table `ticket_checklist_item`
--

DROP TABLE IF EXISTS `ticket_checklist_item`;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!40101 SET character_set_client = utf8mb4 */;
CREATE TABLE `ticket_checklist_item` (
  `id` bigint(20) unsigned NOT NULL AUTO_INCREMENT,
  `ticket_checklist_id` bigint(20) unsigned NOT NULL,
  `template_item_id` bigint(20) unsigned DEFAULT NULL,
  `name` varchar(500) NOT NULL,
  `description` text DEFAULT NULL,
  `is_required` tinyint(1) NOT NULL DEFAULT 0,
  `sort_order` int(10) unsigned NOT NULL DEFAULT 1000,
  `is_done` tinyint(1) NOT NULL DEFAULT 0,
  `completed_by_user_id` bigint(20) unsigned DEFAULT NULL,
  `completed_at` datetime DEFAULT NULL,
  `created_by_user_id` bigint(20) unsigned NOT NULL,
  `changed_by_user_id` bigint(20) unsigned NOT NULL,
  `created_at` datetime NOT NULL,
  `changed_at` datetime NOT NULL,
  PRIMARY KEY (`id`),
  KEY `idx_ticket_checklist_item_checklist` (`ticket_checklist_id`,`sort_order`,`id`),
  KEY `idx_ticket_checklist_item_checklist_done` (`ticket_checklist_id`,`is_done`,`is_required`),
  KEY `idx_ticket_checklist_item_required_open` (`is_required`,`is_done`,`ticket_checklist_id`),
  KEY `fk_ticket_checklist_item_template_item` (`template_item_id`),
  KEY `fk_ticket_checklist_item_completed_by` (`completed_by_user_id`),
  KEY `fk_ticket_checklist_item_created_by` (`created_by_user_id`),
  KEY `fk_ticket_checklist_item_changed_by` (`changed_by_user_id`),
  CONSTRAINT `fk_ticket_checklist_item_changed_by` FOREIGN KEY (`changed_by_user_id`) REFERENCES `user_account` (`id`),
  CONSTRAINT `fk_ticket_checklist_item_checklist` FOREIGN KEY (`ticket_checklist_id`) REFERENCES `ticket_checklist` (`id`) ON DELETE CASCADE,
  CONSTRAINT `fk_ticket_checklist_item_completed_by` FOREIGN KEY (`completed_by_user_id`) REFERENCES `user_account` (`id`),
  CONSTRAINT `fk_ticket_checklist_item_created_by` FOREIGN KEY (`created_by_user_id`) REFERENCES `user_account` (`id`),
  CONSTRAINT `fk_ticket_checklist_item_template_item` FOREIGN KEY (`template_item_id`) REFERENCES `checklist_template_item` (`id`) ON DELETE SET NULL
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;
/*!40101 SET character_set_client = @saved_cs_client */;

--
-- Table structure for table `ticket_dynamic_field`
--

DROP TABLE IF EXISTS `ticket_dynamic_field`;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!40101 SET character_set_client = utf8mb4 */;
CREATE TABLE `ticket_dynamic_field` (
  `id` bigint(20) unsigned NOT NULL AUTO_INCREMENT,
  `name` varchar(100) NOT NULL,
  `label` varchar(255) NOT NULL,
  `field_type` varchar(30) NOT NULL DEFAULT 'text',
  `is_required` tinyint(1) NOT NULL DEFAULT 0,
  `show_empty_value` tinyint(1) NOT NULL DEFAULT 1,
  `default_value` text DEFAULT NULL,
  `active` tinyint(1) NOT NULL DEFAULT 1,
  `sort_order` int(10) unsigned NOT NULL DEFAULT 1000,
  `created_by_user_id` bigint(20) unsigned NOT NULL,
  `changed_by_user_id` bigint(20) unsigned NOT NULL,
  `created_at` timestamp NOT NULL DEFAULT current_timestamp(),
  `changed_at` timestamp NOT NULL DEFAULT current_timestamp() ON UPDATE current_timestamp(),
  PRIMARY KEY (`id`),
  UNIQUE KEY `ticket_dynamic_field_name` (`name`),
  KEY `ticket_dynamic_field_active_sort` (`active`,`sort_order`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;
/*!40101 SET character_set_client = @saved_cs_client */;

--
-- Table structure for table `ticket_dynamic_field_option`
--

DROP TABLE IF EXISTS `ticket_dynamic_field_option`;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!40101 SET character_set_client = utf8mb4 */;
CREATE TABLE `ticket_dynamic_field_option` (
  `id` bigint(20) unsigned NOT NULL AUTO_INCREMENT,
  `field_id` bigint(20) unsigned NOT NULL,
  `option_key` varchar(255) NOT NULL,
  `option_value` varchar(255) NOT NULL,
  `sort_order` int(10) unsigned NOT NULL DEFAULT 1000,
  `created_by_user_id` bigint(20) unsigned NOT NULL,
  `changed_by_user_id` bigint(20) unsigned NOT NULL,
  `created_at` timestamp NOT NULL DEFAULT current_timestamp(),
  `changed_at` timestamp NOT NULL DEFAULT current_timestamp() ON UPDATE current_timestamp(),
  PRIMARY KEY (`id`),
  UNIQUE KEY `ticket_dynamic_field_option_field_key` (`field_id`,`option_key`),
  KEY `ticket_dynamic_field_option_field_sort` (`field_id`,`sort_order`),
  CONSTRAINT `ticket_dynamic_field_option_field_fk` FOREIGN KEY (`field_id`) REFERENCES `ticket_dynamic_field` (`id`) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;
/*!40101 SET character_set_client = @saved_cs_client */;

--
-- Table structure for table `ticket_dynamic_field_option_translation`
--

DROP TABLE IF EXISTS `ticket_dynamic_field_option_translation`;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!40101 SET character_set_client = utf8mb4 */;
CREATE TABLE `ticket_dynamic_field_option_translation` (
  `id` bigint(20) unsigned NOT NULL AUTO_INCREMENT,
  `option_id` bigint(20) unsigned NOT NULL,
  `language` varchar(20) NOT NULL,
  `option_value` varchar(255) NOT NULL,
  `created_by_user_id` bigint(20) unsigned NOT NULL,
  `changed_by_user_id` bigint(20) unsigned NOT NULL,
  `created_at` timestamp NOT NULL DEFAULT current_timestamp(),
  `changed_at` timestamp NOT NULL DEFAULT current_timestamp() ON UPDATE current_timestamp(),
  PRIMARY KEY (`id`),
  UNIQUE KEY `ticket_dynamic_field_option_translation_option_language` (`option_id`,`language`),
  KEY `ticket_dynamic_field_option_translation_language` (`language`),
  CONSTRAINT `ticket_dynamic_field_option_translation_option_fk` FOREIGN KEY (`option_id`) REFERENCES `ticket_dynamic_field_option` (`id`) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;
/*!40101 SET character_set_client = @saved_cs_client */;

--
-- Table structure for table `ticket_dynamic_field_queue`
--

DROP TABLE IF EXISTS `ticket_dynamic_field_queue`;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!40101 SET character_set_client = utf8mb4 */;
CREATE TABLE `ticket_dynamic_field_queue` (
  `field_id` bigint(20) unsigned NOT NULL,
  `queue_id` bigint(20) unsigned NOT NULL,
  `created_by_user_id` bigint(20) unsigned NOT NULL,
  `changed_by_user_id` bigint(20) unsigned NOT NULL,
  `created_at` timestamp NOT NULL DEFAULT current_timestamp(),
  `changed_at` timestamp NOT NULL DEFAULT current_timestamp() ON UPDATE current_timestamp(),
  PRIMARY KEY (`field_id`,`queue_id`),
  KEY `ticket_dynamic_field_queue_queue` (`queue_id`),
  CONSTRAINT `ticket_dynamic_field_queue_field_fk` FOREIGN KEY (`field_id`) REFERENCES `ticket_dynamic_field` (`id`) ON DELETE CASCADE,
  CONSTRAINT `ticket_dynamic_field_queue_queue_fk` FOREIGN KEY (`queue_id`) REFERENCES `ticket_queue` (`id`) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;
/*!40101 SET character_set_client = @saved_cs_client */;

--
-- Table structure for table `ticket_dynamic_field_translation`
--

DROP TABLE IF EXISTS `ticket_dynamic_field_translation`;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!40101 SET character_set_client = utf8mb4 */;
CREATE TABLE `ticket_dynamic_field_translation` (
  `id` bigint(20) unsigned NOT NULL AUTO_INCREMENT,
  `field_id` bigint(20) unsigned NOT NULL,
  `language` varchar(20) NOT NULL,
  `label` varchar(255) NOT NULL,
  `created_by_user_id` bigint(20) unsigned NOT NULL,
  `changed_by_user_id` bigint(20) unsigned NOT NULL,
  `created_at` timestamp NOT NULL DEFAULT current_timestamp(),
  `changed_at` timestamp NOT NULL DEFAULT current_timestamp() ON UPDATE current_timestamp(),
  PRIMARY KEY (`id`),
  UNIQUE KEY `ticket_dynamic_field_translation_field_language` (`field_id`,`language`),
  KEY `ticket_dynamic_field_translation_language` (`language`),
  CONSTRAINT `ticket_dynamic_field_translation_field_fk` FOREIGN KEY (`field_id`) REFERENCES `ticket_dynamic_field` (`id`) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;
/*!40101 SET character_set_client = @saved_cs_client */;

--
-- Table structure for table `ticket_dynamic_field_value`
--

DROP TABLE IF EXISTS `ticket_dynamic_field_value`;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!40101 SET character_set_client = utf8mb4 */;
CREATE TABLE `ticket_dynamic_field_value` (
  `id` bigint(20) unsigned NOT NULL AUTO_INCREMENT,
  `ticket_id` bigint(20) unsigned NOT NULL,
  `field_id` bigint(20) unsigned NOT NULL,
  `value_text` text DEFAULT NULL,
  `created_by_user_id` bigint(20) unsigned NOT NULL,
  `changed_by_user_id` bigint(20) unsigned NOT NULL,
  `created_at` timestamp NOT NULL DEFAULT current_timestamp(),
  `changed_at` timestamp NOT NULL DEFAULT current_timestamp() ON UPDATE current_timestamp(),
  PRIMARY KEY (`id`),
  UNIQUE KEY `ticket_dynamic_field_value_ticket_field` (`ticket_id`,`field_id`),
  KEY `ticket_dynamic_field_value_field` (`field_id`),
  KEY `ticket_dynamic_field_value_field_text` (`field_id`,`value_text`(191)),
  CONSTRAINT `ticket_dynamic_field_value_field_fk` FOREIGN KEY (`field_id`) REFERENCES `ticket_dynamic_field` (`id`) ON DELETE CASCADE,
  CONSTRAINT `ticket_dynamic_field_value_ticket_fk` FOREIGN KEY (`ticket_id`) REFERENCES `ticket` (`id`) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;
/*!40101 SET character_set_client = @saved_cs_client */;
/*!50003 SET @saved_cs_client      = @@character_set_client */ ;
/*!50003 SET @saved_cs_results     = @@character_set_results */ ;
/*!50003 SET @saved_col_connection = @@collation_connection */ ;
/*!50003 SET character_set_client  = utf8mb3 */ ;
/*!50003 SET character_set_results = utf8mb3 */ ;
/*!50003 SET collation_connection  = utf8mb3_general_ci */ ;
/*!50003 SET @saved_sql_mode       = @@sql_mode */ ;
/*!50003 SET sql_mode              = 'STRICT_TRANS_TABLES,ERROR_FOR_DIVISION_BY_ZERO,NO_ENGINE_SUBSTITUTION' */ ;
DELIMITER ;;
/*!50003 CREATE*/ /*!50003 TRIGGER `qisutu_automation_dynamic_field_insert`
AFTER INSERT ON `ticket_dynamic_field_value`
FOR EACH ROW
BEGIN
    INSERT INTO `automation_event` (`event_name`,`ticket_id`,`source_rule_id`,`source_job_id`,`depth`,`suppress_notifications`,`created_at`)
    VALUES ('dynamic_field_changed',NEW.`ticket_id`,NULLIF(@qisutu_automation_rule_id,0),NULLIF(@qisutu_automation_job_id,0),COALESCE(@qisutu_automation_depth,0)+1,COALESCE(@qisutu_suppress_notifications,0),NOW());
END */;;
DELIMITER ;
/*!50003 SET sql_mode              = @saved_sql_mode */ ;
/*!50003 SET character_set_client  = @saved_cs_client */ ;
/*!50003 SET character_set_results = @saved_cs_results */ ;
/*!50003 SET collation_connection  = @saved_col_connection */ ;
/*!50003 SET @saved_cs_client      = @@character_set_client */ ;
/*!50003 SET @saved_cs_results     = @@character_set_results */ ;
/*!50003 SET @saved_col_connection = @@collation_connection */ ;
/*!50003 SET character_set_client  = utf8mb3 */ ;
/*!50003 SET character_set_results = utf8mb3 */ ;
/*!50003 SET collation_connection  = utf8mb3_general_ci */ ;
/*!50003 SET @saved_sql_mode       = @@sql_mode */ ;
/*!50003 SET sql_mode              = 'STRICT_TRANS_TABLES,ERROR_FOR_DIVISION_BY_ZERO,NO_ENGINE_SUBSTITUTION' */ ;
DELIMITER ;;
/*!50003 CREATE*/ /*!50003 TRIGGER `qisutu_automation_dynamic_field_update`
AFTER UPDATE ON `ticket_dynamic_field_value`
FOR EACH ROW
BEGIN
    IF NOT (OLD.`value_text` <=> NEW.`value_text`) THEN
        INSERT INTO `automation_event` (`event_name`,`ticket_id`,`source_rule_id`,`source_job_id`,`depth`,`suppress_notifications`,`created_at`)
        VALUES ('dynamic_field_changed',NEW.`ticket_id`,NULLIF(@qisutu_automation_rule_id,0),NULLIF(@qisutu_automation_job_id,0),COALESCE(@qisutu_automation_depth,0)+1,COALESCE(@qisutu_suppress_notifications,0),NOW());
    END IF;
END */;;
DELIMITER ;
/*!50003 SET sql_mode              = @saved_sql_mode */ ;
/*!50003 SET character_set_client  = @saved_cs_client */ ;
/*!50003 SET character_set_results = @saved_cs_results */ ;
/*!50003 SET collation_connection  = @saved_col_connection */ ;

--
-- Table structure for table `ticket_priority`
--

DROP TABLE IF EXISTS `ticket_priority`;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!40101 SET character_set_client = utf8mb4 */;
CREATE TABLE `ticket_priority` (
  `id` bigint(20) unsigned NOT NULL AUTO_INCREMENT,
  `name` varchar(100) NOT NULL,
  `priority_value` int(11) NOT NULL DEFAULT 3,
  `active` tinyint(1) NOT NULL DEFAULT 1,
  `sort_order` int(11) NOT NULL DEFAULT 1000,
  `created_by_user_id` bigint(20) unsigned NOT NULL,
  `changed_by_user_id` bigint(20) unsigned NOT NULL,
  `created_at` datetime NOT NULL DEFAULT current_timestamp(),
  `changed_at` datetime NOT NULL DEFAULT current_timestamp() ON UPDATE current_timestamp(),
  PRIMARY KEY (`id`),
  UNIQUE KEY `ticket_priority_name` (`name`),
  KEY `ticket_priority_value` (`priority_value`),
  KEY `ticket_priority_active` (`active`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;
/*!40101 SET character_set_client = @saved_cs_client */;

--
-- Table structure for table `ticket_queue`
--

DROP TABLE IF EXISTS `ticket_queue`;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!40101 SET character_set_client = utf8mb4 */;
CREATE TABLE `ticket_queue` (
  `id` bigint(20) unsigned NOT NULL AUTO_INCREMENT,
  `parent_id` bigint(20) unsigned DEFAULT NULL,
  `name` varchar(200) NOT NULL,
  `full_name` varchar(500) NOT NULL,
  `follow_up_allowed` tinyint(1) NOT NULL DEFAULT 1,
  `follow_up_option` varchar(20) NOT NULL DEFAULT 'reopen',
  `system_email_id` bigint(20) unsigned DEFAULT NULL,
  `salutation_id` bigint(20) unsigned DEFAULT NULL,
  `signature_id` bigint(20) unsigned DEFAULT NULL,
  `calendar_id` bigint(20) unsigned DEFAULT NULL,
  `escalation_first_response_minutes` int(10) unsigned NOT NULL DEFAULT 0,
  `escalation_update_minutes` int(10) unsigned NOT NULL DEFAULT 0,
  `escalation_solution_minutes` int(10) unsigned NOT NULL DEFAULT 0,
  `active` tinyint(1) NOT NULL DEFAULT 1,
  `sort_order` int(11) NOT NULL DEFAULT 1000,
  `created_by_user_id` bigint(20) unsigned NOT NULL,
  `changed_by_user_id` bigint(20) unsigned NOT NULL,
  `created_at` datetime NOT NULL DEFAULT current_timestamp(),
  `changed_at` datetime NOT NULL DEFAULT current_timestamp() ON UPDATE current_timestamp(),
  PRIMARY KEY (`id`),
  UNIQUE KEY `ticket_queue_full_name` (`full_name`),
  KEY `ticket_queue_parent_id` (`parent_id`),
  KEY `ticket_queue_active` (`active`),
  KEY `ticket_queue_system_email_id` (`system_email_id`),
  KEY `ticket_queue_salutation_id` (`salutation_id`),
  KEY `ticket_queue_signature_id` (`signature_id`),
  KEY `ticket_queue_calendar_id` (`calendar_id`),
  CONSTRAINT `fk_ticket_queue_parent_id` FOREIGN KEY (`parent_id`) REFERENCES `ticket_queue` (`id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;
/*!40101 SET character_set_client = @saved_cs_client */;

--
-- Table structure for table `ticket_queue_group`
--

DROP TABLE IF EXISTS `ticket_queue_group`;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!40101 SET character_set_client = utf8mb4 */;
CREATE TABLE `ticket_queue_group` (
  `id` bigint(20) unsigned NOT NULL AUTO_INCREMENT,
  `queue_id` bigint(20) unsigned NOT NULL,
  `user_group_id` bigint(20) unsigned NOT NULL,
  `permission_key` varchar(100) NOT NULL,
  `active` tinyint(1) NOT NULL DEFAULT 1,
  `created_by_user_id` bigint(20) unsigned NOT NULL,
  `changed_by_user_id` bigint(20) unsigned NOT NULL,
  `created_at` datetime NOT NULL DEFAULT current_timestamp(),
  `changed_at` datetime NOT NULL DEFAULT current_timestamp() ON UPDATE current_timestamp(),
  PRIMARY KEY (`id`),
  UNIQUE KEY `ticket_queue_group_unique` (`queue_id`,`user_group_id`,`permission_key`),
  KEY `ticket_queue_group_queue_id_idx` (`queue_id`),
  KEY `ticket_queue_group_user_group_id_idx` (`user_group_id`),
  KEY `ticket_queue_group_permission_key_idx` (`permission_key`),
  KEY `ticket_queue_group_active_idx` (`active`),
  CONSTRAINT `fk_ticket_queue_group_queue_id` FOREIGN KEY (`queue_id`) REFERENCES `ticket_queue` (`id`) ON DELETE CASCADE,
  CONSTRAINT `fk_ticket_queue_group_user_group_id` FOREIGN KEY (`user_group_id`) REFERENCES `user_group` (`id`) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;
/*!40101 SET character_set_client = @saved_cs_client */;

--
-- Table structure for table `ticket_state`
--

DROP TABLE IF EXISTS `ticket_state`;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!40101 SET character_set_client = utf8mb4 */;
CREATE TABLE `ticket_state` (
  `id` bigint(20) unsigned NOT NULL AUTO_INCREMENT,
  `name` varchar(100) NOT NULL,
  `state_type` varchar(50) NOT NULL,
  `sla_pause` tinyint(1) NOT NULL DEFAULT 0,
  `active` tinyint(1) NOT NULL DEFAULT 1,
  `sort_order` int(11) NOT NULL DEFAULT 1000,
  `created_by_user_id` bigint(20) unsigned NOT NULL,
  `changed_by_user_id` bigint(20) unsigned NOT NULL,
  `created_at` datetime NOT NULL DEFAULT current_timestamp(),
  `changed_at` datetime NOT NULL DEFAULT current_timestamp() ON UPDATE current_timestamp(),
  PRIMARY KEY (`id`),
  UNIQUE KEY `ticket_state_name` (`name`),
  KEY `ticket_state_type` (`state_type`),
  KEY `ticket_state_active` (`active`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;
/*!40101 SET character_set_client = @saved_cs_client */;

--
-- Table structure for table `user_account`
--

DROP TABLE IF EXISTS `user_account`;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!40101 SET character_set_client = utf8mb4 */;
CREATE TABLE `user_account` (
  `id` bigint(20) unsigned NOT NULL AUTO_INCREMENT,
  `login` varchar(100) NOT NULL,
  `account_type` varchar(20) NOT NULL DEFAULT 'agent',
  `authentication_type` varchar(20) NOT NULL DEFAULT 'local',
  `email` varchar(255) NOT NULL,
  `password_hash` varchar(255) NOT NULL,
  `firstname` varchar(100) NOT NULL DEFAULT '',
  `lastname` varchar(100) NOT NULL DEFAULT '',
  `is_active` tinyint(1) NOT NULL DEFAULT 1,
  `is_system_user` tinyint(1) NOT NULL DEFAULT 0,
  `failed_login_count` int(10) unsigned NOT NULL DEFAULT 0,
  `locked_until` datetime DEFAULT NULL,
  `last_login_at` datetime DEFAULT NULL,
  `password_changed_at` datetime DEFAULT NULL,
  `created_at` datetime NOT NULL DEFAULT current_timestamp(),
  `updated_at` datetime NOT NULL DEFAULT current_timestamp() ON UPDATE current_timestamp(),
  PRIMARY KEY (`id`),
  UNIQUE KEY `user_account_login_type_unique` (`login`,`account_type`),
  UNIQUE KEY `user_account_email_type_unique` (`email`,`account_type`),
  KEY `user_account_is_active_idx` (`is_active`),
  KEY `user_account_account_type_idx` (`account_type`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;
/*!40101 SET character_set_client = @saved_cs_client */;

--
-- Table structure for table `oauth2_authorization_state`
--

DROP TABLE IF EXISTS `user_two_factor_challenge`;
DROP TABLE IF EXISTS `user_two_factor`;
CREATE TABLE `user_two_factor` (
  `user_account_id` bigint(20) unsigned NOT NULL,
  `secret_encrypted` text NOT NULL,
  `enabled` tinyint(1) NOT NULL DEFAULT 0,
  `recovery_code_hashes` text DEFAULT NULL,
  `last_used_counter` bigint(20) unsigned DEFAULT NULL,
  `created_at` datetime NOT NULL DEFAULT current_timestamp(),
  `changed_at` datetime NOT NULL DEFAULT current_timestamp() ON UPDATE current_timestamp(),
  PRIMARY KEY (`user_account_id`),
  KEY `user_two_factor_enabled` (`enabled`),
  CONSTRAINT `user_two_factor_user_fk` FOREIGN KEY (`user_account_id`) REFERENCES `user_account` (`id`) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE `user_two_factor_challenge` (
  `id` bigint(20) unsigned NOT NULL AUTO_INCREMENT,
  `token_hash` char(64) NOT NULL,
  `user_account_id` bigint(20) unsigned NOT NULL,
  `account_type` varchar(20) NOT NULL,
  `mode` varchar(20) NOT NULL DEFAULT 'login',
  `attempts` int(10) unsigned NOT NULL DEFAULT 0,
  `expires_at` datetime NOT NULL,
  `created_at` datetime NOT NULL DEFAULT current_timestamp(),
  PRIMARY KEY (`id`),
  UNIQUE KEY `user_two_factor_challenge_token` (`token_hash`),
  KEY `user_two_factor_challenge_expiry` (`expires_at`),
  CONSTRAINT `user_two_factor_challenge_user_fk` FOREIGN KEY (`user_account_id`) REFERENCES `user_account` (`id`) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!40101 SET character_set_client = utf8mb4 */;
CREATE TABLE `oauth2_authorization_state` (
  `id` bigint(20) unsigned NOT NULL AUTO_INCREMENT,
  `state_hash` char(64) NOT NULL,
  `account_type` varchar(20) NOT NULL DEFAULT 'imap',
  `account_id` bigint(20) unsigned NOT NULL,
  `user_account_id` bigint(20) unsigned NOT NULL,
  `provider` varchar(30) NOT NULL,
  `requested_active` tinyint(1) NOT NULL DEFAULT 1,
  `return_page` varchar(100) NOT NULL,
  `expires_at` datetime NOT NULL,
  `created_at` datetime NOT NULL DEFAULT current_timestamp(),
  PRIMARY KEY (`id`),
  UNIQUE KEY `oauth2_authorization_state_hash_unique` (`state_hash`),
  KEY `oauth2_authorization_state_account_user` (`account_type`,`account_id`,`user_account_id`),
  KEY `oauth2_authorization_state_expires` (`expires_at`),
  CONSTRAINT `oauth2_authorization_state_user_fk` FOREIGN KEY (`user_account_id`) REFERENCES `user_account` (`id`) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;
/*!40101 SET character_set_client = @saved_cs_client */;

--
-- Table structure for table `password_reset_token`
--

DROP TABLE IF EXISTS `password_reset_token`;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!40101 SET character_set_client = utf8mb4 */;
CREATE TABLE `password_reset_token` (
  `id` bigint(20) unsigned NOT NULL AUTO_INCREMENT,
  `user_account_id` bigint(20) unsigned NOT NULL,
  `token_hash` char(64) NOT NULL,
  `requested_ip` varchar(45) DEFAULT NULL,
  `user_agent` varchar(255) DEFAULT NULL,
  `created_at` datetime NOT NULL DEFAULT current_timestamp(),
  `expires_at` datetime NOT NULL,
  `used_at` datetime DEFAULT NULL,
  `invalidated_at` datetime DEFAULT NULL,
  `mail_sent_at` datetime DEFAULT NULL,
  PRIMARY KEY (`id`),
  UNIQUE KEY `password_reset_token_hash_unique` (`token_hash`),
  KEY `password_reset_token_user_created` (`user_account_id`,`created_at`),
  KEY `password_reset_token_expires_at` (`expires_at`),
  KEY `password_reset_token_requested_ip` (`requested_ip`,`created_at`),
  CONSTRAINT `password_reset_token_user_account_fk` FOREIGN KEY (`user_account_id`) REFERENCES `user_account` (`id`) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;
/*!40101 SET character_set_client = @saved_cs_client */;

--
-- Table structure for table `customer_registration_request`
--

DROP TABLE IF EXISTS `customer_registration_request`;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!40101 SET character_set_client = utf8mb4 */;
CREATE TABLE `customer_registration_request` (
  `id` bigint(20) unsigned NOT NULL AUTO_INCREMENT,
  `firstname` varchar(100) NOT NULL,
  `lastname` varchar(100) NOT NULL,
  `email` varchar(255) NOT NULL,
  `company` varchar(255) NOT NULL,
  `language` varchar(10) NOT NULL DEFAULT 'en',
  `token_hash` char(64) NOT NULL,
  `requested_ip` varchar(45) DEFAULT NULL,
  `user_agent` varchar(255) DEFAULT NULL,
  `created_at` datetime NOT NULL DEFAULT current_timestamp(),
  `expires_at` datetime NOT NULL,
  `used_at` datetime DEFAULT NULL,
  `invalidated_at` datetime DEFAULT NULL,
  `mail_sent_at` datetime DEFAULT NULL,
  PRIMARY KEY (`id`),
  UNIQUE KEY `customer_registration_token_unique` (`token_hash`),
  KEY `customer_registration_email_created` (`email`,`created_at`),
  KEY `customer_registration_expires_at` (`expires_at`),
  KEY `customer_registration_ip_created` (`requested_ip`,`created_at`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;
/*!40101 SET character_set_client = @saved_cs_client */;

--
-- Table structure for table `user_dynamic_field`
--

DROP TABLE IF EXISTS `user_dynamic_field`;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!40101 SET character_set_client = utf8mb4 */;
CREATE TABLE `user_dynamic_field` (
  `id` bigint(20) unsigned NOT NULL AUTO_INCREMENT,
  `object_type` varchar(50) NOT NULL,
  `name` varchar(100) NOT NULL,
  `label` varchar(255) NOT NULL,
  `field_type` varchar(30) NOT NULL DEFAULT 'text',
  `is_required` tinyint(1) NOT NULL DEFAULT 0,
  `active` tinyint(1) NOT NULL DEFAULT 1,
  `sort_order` int(10) unsigned NOT NULL DEFAULT 1000,
  `created_by_user_id` bigint(20) unsigned NOT NULL,
  `changed_by_user_id` bigint(20) unsigned NOT NULL,
  `created_at` timestamp NOT NULL DEFAULT current_timestamp(),
  `changed_at` timestamp NOT NULL DEFAULT current_timestamp() ON UPDATE current_timestamp(),
  PRIMARY KEY (`id`),
  UNIQUE KEY `user_dynamic_field_object_name` (`object_type`,`name`),
  KEY `user_dynamic_field_object_active_sort` (`object_type`,`active`,`sort_order`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;
/*!40101 SET character_set_client = @saved_cs_client */;

--
-- Table structure for table `user_dynamic_field_translation`
--

DROP TABLE IF EXISTS `user_dynamic_field_translation`;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!40101 SET character_set_client = utf8mb4 */;
CREATE TABLE `user_dynamic_field_translation` (
  `id` bigint(20) unsigned NOT NULL AUTO_INCREMENT,
  `field_id` bigint(20) unsigned NOT NULL,
  `language` varchar(20) NOT NULL,
  `label` varchar(255) NOT NULL,
  `created_by_user_id` bigint(20) unsigned NOT NULL,
  `changed_by_user_id` bigint(20) unsigned NOT NULL,
  `created_at` timestamp NOT NULL DEFAULT current_timestamp(),
  `changed_at` timestamp NOT NULL DEFAULT current_timestamp() ON UPDATE current_timestamp(),
  PRIMARY KEY (`id`),
  UNIQUE KEY `user_dynamic_field_translation_field_language` (`field_id`,`language`),
  KEY `user_dynamic_field_translation_language` (`language`),
  CONSTRAINT `user_dynamic_field_translation_field_fk` FOREIGN KEY (`field_id`) REFERENCES `user_dynamic_field` (`id`) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;
/*!40101 SET character_set_client = @saved_cs_client */;

--
-- Table structure for table `user_dynamic_field_value`
--

DROP TABLE IF EXISTS `user_dynamic_field_value`;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!40101 SET character_set_client = utf8mb4 */;
CREATE TABLE `user_dynamic_field_value` (
  `id` bigint(20) unsigned NOT NULL AUTO_INCREMENT,
  `object_type` varchar(50) NOT NULL,
  `object_id` bigint(20) unsigned NOT NULL,
  `field_id` bigint(20) unsigned NOT NULL,
  `value_text` text DEFAULT NULL,
  `created_by_user_id` bigint(20) unsigned NOT NULL,
  `changed_by_user_id` bigint(20) unsigned NOT NULL,
  `created_at` timestamp NOT NULL DEFAULT current_timestamp(),
  `changed_at` timestamp NOT NULL DEFAULT current_timestamp() ON UPDATE current_timestamp(),
  PRIMARY KEY (`id`),
  UNIQUE KEY `user_dynamic_field_value_object_field` (`object_type`,`object_id`,`field_id`),
  KEY `user_dynamic_field_value_field` (`field_id`),
  CONSTRAINT `user_dynamic_field_value_field_fk` FOREIGN KEY (`field_id`) REFERENCES `user_dynamic_field` (`id`) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;
/*!40101 SET character_set_client = @saved_cs_client */;

--
-- Table structure for table `user_group`
--

DROP TABLE IF EXISTS `user_group`;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!40101 SET character_set_client = utf8mb4 */;
CREATE TABLE `user_group` (
  `id` bigint(20) unsigned NOT NULL AUTO_INCREMENT,
  `name` varchar(100) NOT NULL,
  `title` varchar(255) NOT NULL DEFAULT '',
  `group_type` varchar(50) NOT NULL DEFAULT 'agent',
  `active` tinyint(1) NOT NULL DEFAULT 1,
  `sort_order` int(11) NOT NULL DEFAULT 1000,
  `created_by_user_id` bigint(20) unsigned NOT NULL,
  `changed_by_user_id` bigint(20) unsigned NOT NULL,
  `created_at` datetime NOT NULL DEFAULT current_timestamp(),
  `changed_at` datetime NOT NULL DEFAULT current_timestamp() ON UPDATE current_timestamp(),
  PRIMARY KEY (`id`),
  UNIQUE KEY `user_group_name_unique` (`name`),
  KEY `user_group_group_type_idx` (`group_type`),
  KEY `user_group_active_idx` (`active`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;
/*!40101 SET character_set_client = @saved_cs_client */;

--
-- Table structure for table `user_group_member`
--

DROP TABLE IF EXISTS `user_group_member`;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!40101 SET character_set_client = utf8mb4 */;
CREATE TABLE `user_group_member` (
  `id` bigint(20) unsigned NOT NULL AUTO_INCREMENT,
  `user_group_id` bigint(20) unsigned NOT NULL,
  `user_account_id` bigint(20) unsigned NOT NULL,
  `role_name` varchar(50) NOT NULL DEFAULT 'member',
  `active` tinyint(1) NOT NULL DEFAULT 1,
  `created_by_user_id` bigint(20) unsigned NOT NULL,
  `changed_by_user_id` bigint(20) unsigned NOT NULL,
  `created_at` datetime NOT NULL DEFAULT current_timestamp(),
  `changed_at` datetime NOT NULL DEFAULT current_timestamp() ON UPDATE current_timestamp(),
  `permission_read` tinyint(1) NOT NULL DEFAULT 0,
  `permission_create` tinyint(1) NOT NULL DEFAULT 0,
  `permission_change` tinyint(1) NOT NULL DEFAULT 0,
  `permission_overview` tinyint(1) NOT NULL DEFAULT 0,
  `permission_full` tinyint(1) NOT NULL DEFAULT 0,
  PRIMARY KEY (`id`),
  UNIQUE KEY `user_group_member_unique` (`user_group_id`,`user_account_id`),
  KEY `user_group_member_user_group_id_idx` (`user_group_id`),
  KEY `user_group_member_user_account_id_idx` (`user_account_id`),
  KEY `user_group_member_active_idx` (`active`),
  CONSTRAINT `fk_user_group_member_user_account_id` FOREIGN KEY (`user_account_id`) REFERENCES `user_account` (`id`) ON DELETE CASCADE,
  CONSTRAINT `fk_user_group_member_user_group_id` FOREIGN KEY (`user_group_id`) REFERENCES `user_group` (`id`) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;
/*!40101 SET character_set_client = @saved_cs_client */;

--
-- Table structure for table `user_group_permission`
--

DROP TABLE IF EXISTS `user_group_permission`;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!40101 SET character_set_client = utf8mb4 */;
CREATE TABLE `user_group_permission` (
  `id` bigint(20) unsigned NOT NULL AUTO_INCREMENT,
  `user_group_id` bigint(20) unsigned NOT NULL,
  `permission_key` varchar(100) NOT NULL,
  `active` tinyint(1) NOT NULL DEFAULT 1,
  `created_by_user_id` bigint(20) unsigned NOT NULL,
  `changed_by_user_id` bigint(20) unsigned NOT NULL,
  `created_at` datetime NOT NULL DEFAULT current_timestamp(),
  `changed_at` datetime NOT NULL DEFAULT current_timestamp() ON UPDATE current_timestamp(),
  PRIMARY KEY (`id`),
  UNIQUE KEY `user_group_permission_unique` (`user_group_id`,`permission_key`),
  KEY `user_group_permission_user_group_id_idx` (`user_group_id`),
  KEY `user_group_permission_permission_key_idx` (`permission_key`),
  KEY `user_group_permission_active_idx` (`active`),
  CONSTRAINT `fk_user_group_permission_user_group_id` FOREIGN KEY (`user_group_id`) REFERENCES `user_group` (`id`) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;
/*!40101 SET character_set_client = @saved_cs_client */;

--
-- Table structure for table `ldap_configuration`
--

DROP TABLE IF EXISTS `ldap_field_mapping`;
DROP TABLE IF EXISTS `ldap_configuration`;
CREATE TABLE `ldap_configuration` (
  `id` bigint(20) unsigned NOT NULL AUTO_INCREMENT,
  `profile_type` varchar(20) NOT NULL DEFAULT 'agent',
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
  `customer_number_attribute` varchar(100) NOT NULL DEFAULT '',
  `customer_name_attribute` varchar(100) NOT NULL DEFAULT '',
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
  KEY `ldap_configuration_profile_active` (`profile_type`,`active`,`id`),
  KEY `ldap_configuration_default_group` (`default_group_id`),
  CONSTRAINT `ldap_configuration_default_group_fk` FOREIGN KEY (`default_group_id`) REFERENCES `user_group` (`id`) ON DELETE SET NULL
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE `ldap_field_mapping` (
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
/*!40101 SET character_set_client = @saved_cs_client */;

--
-- Table structure for table `user_preference`
--

DROP TABLE IF EXISTS `user_preference`;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!40101 SET character_set_client = utf8mb4 */;
CREATE TABLE `user_preference` (
  `id` bigint(20) unsigned NOT NULL AUTO_INCREMENT,
  `user_account_id` bigint(20) unsigned NOT NULL,
  `preference_key` varchar(100) NOT NULL,
  `preference_value` text DEFAULT NULL,
  `created_at` datetime NOT NULL DEFAULT current_timestamp(),
  `changed_at` datetime NOT NULL DEFAULT current_timestamp() ON UPDATE current_timestamp(),
  PRIMARY KEY (`id`),
  UNIQUE KEY `user_preference_user_key_unique` (`user_account_id`,`preference_key`),
  KEY `user_preference_user_account_id` (`user_account_id`),
  CONSTRAINT `fk_user_preference_user_account_id` FOREIGN KEY (`user_account_id`) REFERENCES `user_account` (`id`) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;
/*!40101 SET character_set_client = @saved_cs_client */;

--
-- Table structure for table `user_session`
--

DROP TABLE IF EXISTS `user_session`;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!40101 SET character_set_client = utf8mb4 */;
CREATE TABLE `user_session` (
  `id` bigint(20) unsigned NOT NULL AUTO_INCREMENT,
  `user_account_id` bigint(20) unsigned NOT NULL,
  `session_token_hash` char(64) NOT NULL,
  `ip_address` varchar(45) DEFAULT NULL,
  `user_agent` varchar(255) DEFAULT NULL,
  `is_active` tinyint(1) NOT NULL DEFAULT 1,
  `created_at` datetime NOT NULL DEFAULT current_timestamp(),
  `last_seen_at` datetime NOT NULL DEFAULT current_timestamp(),
  `expires_at` datetime NOT NULL,
  PRIMARY KEY (`id`),
  UNIQUE KEY `user_session_token_hash_unique` (`session_token_hash`),
  KEY `user_session_user_account_id_idx` (`user_account_id`),
  KEY `user_session_expires_at_idx` (`expires_at`),
  KEY `user_session_is_active_idx` (`is_active`),
  CONSTRAINT `user_session_user_account_fk` FOREIGN KEY (`user_account_id`) REFERENCES `user_account` (`id`) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;
/*!40101 SET character_set_client = @saved_cs_client */;

--
-- Time accounting (agent/admin only; entries are immutable)
--

DROP TABLE IF EXISTS `ticket_time_accounting_cancellation`;
DROP TABLE IF EXISTS `ticket_time_accounting`;
DROP TABLE IF EXISTS `time_accounting_activity_type`;

CREATE TABLE `time_accounting_activity_type` (
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

CREATE TABLE `ticket_time_accounting` (
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

CREATE TABLE `ticket_time_accounting_cancellation` (
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

CREATE TABLE `ticket_bulk_action` (
  `id` bigint(20) unsigned NOT NULL AUTO_INCREMENT,
  `created_by_user_id` bigint(20) unsigned NOT NULL,
  `change_reason` text DEFAULT NULL,
  `requested_changes_json` longtext NOT NULL,
  `selected_count` int(10) unsigned NOT NULL DEFAULT 0,
  `success_count` int(10) unsigned NOT NULL DEFAULT 0,
  `skipped_count` int(10) unsigned NOT NULL DEFAULT 0,
  `failed_count` int(10) unsigned NOT NULL DEFAULT 0,
  `status` varchar(30) NOT NULL DEFAULT 'running',
  `created_at` datetime NOT NULL DEFAULT current_timestamp(),
  `completed_at` datetime DEFAULT NULL,
  PRIMARY KEY (`id`),
  KEY `ticket_bulk_action_user_created` (`created_by_user_id`,`created_at`,`id`),
  KEY `ticket_bulk_action_status_created` (`status`,`created_at`),
  CONSTRAINT `ticket_bulk_action_user_fk` FOREIGN KEY (`created_by_user_id`) REFERENCES `user_account` (`id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE `ticket_bulk_action_item` (
  `id` bigint(20) unsigned NOT NULL AUTO_INCREMENT,
  `bulk_action_id` bigint(20) unsigned NOT NULL,
  `ticket_id` bigint(20) unsigned DEFAULT NULL,
  `ticket_number_snapshot` varchar(50) NOT NULL DEFAULT '',
  `result` varchar(30) NOT NULL,
  `error_message` text DEFAULT NULL,
  `changes_json` longtext NOT NULL,
  `created_at` datetime NOT NULL DEFAULT current_timestamp(),
  PRIMARY KEY (`id`),
  KEY `ticket_bulk_action_item_action` (`bulk_action_id`,`id`),
  KEY `ticket_bulk_action_item_ticket` (`ticket_id`,`created_at`,`id`),
  KEY `ticket_bulk_action_item_result` (`result`,`created_at`),
  CONSTRAINT `ticket_bulk_action_item_action_fk` FOREIGN KEY (`bulk_action_id`) REFERENCES `ticket_bulk_action` (`id`) ON DELETE CASCADE,
  CONSTRAINT `ticket_bulk_action_item_ticket_fk` FOREIGN KEY (`ticket_id`) REFERENCES `ticket` (`id`) ON DELETE SET NULL
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- Configurable customer-portal and public ticket forms
CREATE TABLE `ticket_form` (
  `id` bigint(20) unsigned NOT NULL AUTO_INCREMENT,
  `internal_name` varchar(190) NOT NULL,
  `form_type` varchar(20) NOT NULL DEFAULT 'customer',
  `slug` varchar(100) NOT NULL,
  `queue_id` bigint(20) unsigned NOT NULL,
  `process_template_id` bigint(20) unsigned DEFAULT NULL,
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

CREATE TABLE `ticket_form_translation` (
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

CREATE TABLE `ticket_form_customer` (
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

CREATE TABLE `ticket_form_field` (
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

CREATE TABLE `ticket_form_field_translation` (
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

CREATE TABLE `ticket_form_submission` (
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

CREATE TABLE `ticket_form_submission_value` (
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

DELIMITER ;;
CREATE TRIGGER `qisutu_time_accounting_immutable_update`
BEFORE UPDATE ON `ticket_time_accounting`
FOR EACH ROW
BEGIN
    SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Time accounting entries are immutable; create a correction instead';
END;;
CREATE TRIGGER `qisutu_time_accounting_immutable_delete`
BEFORE DELETE ON `ticket_time_accounting`
FOR EACH ROW
BEGIN
    SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Time accounting entries are immutable';
END;;
CREATE TRIGGER `qisutu_time_accounting_cancellation_immutable_update`
BEFORE UPDATE ON `ticket_time_accounting_cancellation`
FOR EACH ROW
BEGIN
    SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Time accounting cancellations are immutable';
END;;
CREATE TRIGGER `qisutu_time_accounting_cancellation_immutable_delete`
BEFORE DELETE ON `ticket_time_accounting_cancellation`
FOR EACH ROW
BEGIN
    SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Time accounting cancellations are immutable';
END;;
DELIMITER ;

-- Qisutu - Open Source Ticket System
-- Copyright (C) 2026 Franziska Steps
-- Qisutu - Kim-KI, https://qisutu.de
--
-- SPDX-FileCopyrightText: 2026 Franziska Steps
-- SPDX-License-Identifier: AGPL-3.0-or-later

-- Immutable, agent-only ticket history. The table intentionally has no
-- foreign key to ticket: an audit trail must survive an automated deletion.
CREATE TABLE IF NOT EXISTS `ticket_history` (
  `id` bigint(20) unsigned NOT NULL AUTO_INCREMENT,
  `event_key` varchar(190) DEFAULT NULL,
  `ticket_id` bigint(20) unsigned NOT NULL,
  `event_type` varchar(50) NOT NULL,
  `event_category` varchar(30) NOT NULL,
  `field_name` varchar(100) DEFAULT NULL,
  `old_value` longtext DEFAULT NULL,
  `new_value` longtext DEFAULT NULL,
  `old_display` longtext DEFAULT NULL,
  `new_display` longtext DEFAULT NULL,
  `article_id` bigint(20) unsigned DEFAULT NULL,
  `related_ticket_id` bigint(20) unsigned DEFAULT NULL,
  `object_type` varchar(50) DEFAULT NULL,
  `object_id` bigint(20) unsigned DEFAULT NULL,
  `actor_user_id` bigint(20) unsigned DEFAULT NULL,
  `actor_type` varchar(30) NOT NULL DEFAULT 'system',
  `actor_name` varchar(255) NOT NULL DEFAULT 'System',
  `source` varchar(50) NOT NULL DEFAULT 'application',
  `details_text` longtext DEFAULT NULL,
  `is_backfill` tinyint(1) NOT NULL DEFAULT 0,
  `created_at` datetime NOT NULL DEFAULT current_timestamp(),
  PRIMARY KEY (`id`),
  UNIQUE KEY `ticket_history_event_key_unique` (`event_key`),
  KEY `ticket_history_ticket_id` (`ticket_id`,`id`),
  KEY `ticket_history_ticket_created_id` (`ticket_id`,`created_at`,`id`),
  KEY `ticket_history_ticket_category_created_id` (`ticket_id`,`event_category`,`created_at`,`id`),
  KEY `ticket_history_actor_created` (`actor_user_id`,`created_at`,`id`),
  KEY `ticket_history_article` (`article_id`),
  KEY `ticket_history_related_ticket` (`related_ticket_id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

DROP TRIGGER IF EXISTS `qisutu_ticket_history_immutable_update`;
DROP TRIGGER IF EXISTS `qisutu_ticket_history_immutable_delete`;
DROP TRIGGER IF EXISTS `qisutu_history_ticket_insert`;
DROP TRIGGER IF EXISTS `qisutu_history_ticket_update`;
DROP TRIGGER IF EXISTS `qisutu_history_article_insert`;
DROP TRIGGER IF EXISTS `qisutu_history_attachment_insert`;
DROP TRIGGER IF EXISTS `qisutu_history_dynamic_field_insert`;
DROP TRIGGER IF EXISTS `qisutu_history_dynamic_field_update`;
DROP TRIGGER IF EXISTS `qisutu_history_dynamic_field_delete`;
DROP TRIGGER IF EXISTS `qisutu_history_time_insert`;
DROP TRIGGER IF EXISTS `qisutu_history_time_cancel_insert`;
DROP TRIGGER IF EXISTS `qisutu_history_link_insert`;
DROP TRIGGER IF EXISTS `qisutu_history_checklist_audit_insert`;
DROP TRIGGER IF EXISTS `qisutu_history_form_submission_insert`;
DROP TRIGGER IF EXISTS `qisutu_history_bulk_item_insert`;

DELIMITER ;;

CREATE TRIGGER `qisutu_ticket_history_immutable_update`
BEFORE UPDATE ON `ticket_history`
FOR EACH ROW
BEGIN
    SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Ticket history entries are immutable';
END;;

CREATE TRIGGER `qisutu_ticket_history_immutable_delete`
BEFORE DELETE ON `ticket_history`
FOR EACH ROW
BEGIN
    SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Ticket history entries are immutable';
END;;

CREATE TRIGGER `qisutu_history_ticket_insert`
AFTER INSERT ON `ticket`
FOR EACH ROW
BEGIN
    DECLARE v_actor_name varchar(255) DEFAULT 'System';
    DECLARE v_actor_type varchar(30) DEFAULT 'system';

    SELECT
      COALESCE(NULLIF(TRIM(CONCAT(`firstname`, ' ', `lastname`)), ''), NULLIF(`login`, ''), `email`, 'System'),
      CASE WHEN `is_system_user` = 1 THEN 'system' ELSE `account_type` END
    INTO v_actor_name, v_actor_type
    FROM `user_account`
    WHERE `id` = NEW.`created_by_user_id`
    LIMIT 1;

    INSERT INTO `ticket_history` (
      `ticket_id`,`event_type`,`event_category`,`object_type`,`object_id`,
      `actor_user_id`,`actor_type`,`actor_name`,`source`,`created_at`
    ) VALUES (
      NEW.`id`,'ticket_created','system','ticket',NEW.`id`,
      NEW.`created_by_user_id`,COALESCE(NULLIF(@qisutu_history_actor_type,''),v_actor_type),
      COALESCE(NULLIF(@qisutu_history_actor_name,''),v_actor_name),
      COALESCE(NULLIF(@qisutu_history_source,''),'application'),NEW.`created_at`
    );
END;;

CREATE TRIGGER `qisutu_history_ticket_update`
AFTER UPDATE ON `ticket`
FOR EACH ROW
BEGIN
    DECLARE v_actor_name varchar(255) DEFAULT 'System';
    DECLARE v_actor_type varchar(30) DEFAULT 'system';
    DECLARE v_source varchar(50) DEFAULT 'application';

    SELECT
      COALESCE(NULLIF(TRIM(CONCAT(`firstname`, ' ', `lastname`)), ''), NULLIF(`login`, ''), `email`, 'System'),
      CASE WHEN `is_system_user` = 1 THEN 'system' ELSE `account_type` END
    INTO v_actor_name, v_actor_type
    FROM `user_account`
    WHERE `id` = NEW.`changed_by_user_id`
    LIMIT 1;

    SET v_actor_name = COALESCE(NULLIF(@qisutu_history_actor_name,''),v_actor_name,'System');
    SET v_actor_type = COALESCE(NULLIF(@qisutu_history_actor_type,''),v_actor_type,'system');
    SET v_source = COALESCE(NULLIF(@qisutu_history_source,''),'application');

    IF NOT (OLD.`title` <=> NEW.`title`) THEN
      INSERT INTO `ticket_history` (`ticket_id`,`event_type`,`event_category`,`field_name`,`old_value`,`new_value`,`old_display`,`new_display`,`object_type`,`object_id`,`actor_user_id`,`actor_type`,`actor_name`,`source`,`created_at`)
      VALUES (NEW.`id`,'title_changed','change','title',OLD.`title`,NEW.`title`,OLD.`title`,NEW.`title`,'ticket',NEW.`id`,NEW.`changed_by_user_id`,v_actor_type,v_actor_name,v_source,NOW());
    END IF;
    IF NOT (OLD.`queue_id` <=> NEW.`queue_id`) THEN
      INSERT INTO `ticket_history` (`ticket_id`,`event_type`,`event_category`,`field_name`,`old_value`,`new_value`,`old_display`,`new_display`,`object_type`,`object_id`,`actor_user_id`,`actor_type`,`actor_name`,`source`,`created_at`)
      VALUES (NEW.`id`,'queue_changed','change','queue_id',OLD.`queue_id`,NEW.`queue_id`,(SELECT `full_name` FROM `ticket_queue` WHERE `id`=OLD.`queue_id` LIMIT 1),(SELECT `full_name` FROM `ticket_queue` WHERE `id`=NEW.`queue_id` LIMIT 1),'ticket',NEW.`id`,NEW.`changed_by_user_id`,v_actor_type,v_actor_name,v_source,NOW());
    END IF;
    IF NOT (OLD.`state_id` <=> NEW.`state_id`) THEN
      INSERT INTO `ticket_history` (`ticket_id`,`event_type`,`event_category`,`field_name`,`old_value`,`new_value`,`old_display`,`new_display`,`object_type`,`object_id`,`actor_user_id`,`actor_type`,`actor_name`,`source`,`created_at`)
      VALUES (NEW.`id`,'state_changed','change','state_id',OLD.`state_id`,NEW.`state_id`,(SELECT `name` FROM `ticket_state` WHERE `id`=OLD.`state_id` LIMIT 1),(SELECT `name` FROM `ticket_state` WHERE `id`=NEW.`state_id` LIMIT 1),'ticket',NEW.`id`,NEW.`changed_by_user_id`,v_actor_type,v_actor_name,v_source,NOW());
    END IF;
    IF NOT (OLD.`priority_id` <=> NEW.`priority_id`) THEN
      INSERT INTO `ticket_history` (`ticket_id`,`event_type`,`event_category`,`field_name`,`old_value`,`new_value`,`old_display`,`new_display`,`object_type`,`object_id`,`actor_user_id`,`actor_type`,`actor_name`,`source`,`created_at`)
      VALUES (NEW.`id`,'priority_changed','change','priority_id',OLD.`priority_id`,NEW.`priority_id`,(SELECT `name` FROM `ticket_priority` WHERE `id`=OLD.`priority_id` LIMIT 1),(SELECT `name` FROM `ticket_priority` WHERE `id`=NEW.`priority_id` LIMIT 1),'ticket',NEW.`id`,NEW.`changed_by_user_id`,v_actor_type,v_actor_name,v_source,NOW());
    END IF;
    IF NOT (OLD.`customer_id` <=> NEW.`customer_id`) THEN
      INSERT INTO `ticket_history` (`ticket_id`,`event_type`,`event_category`,`field_name`,`old_value`,`new_value`,`old_display`,`new_display`,`object_type`,`object_id`,`actor_user_id`,`actor_type`,`actor_name`,`source`,`created_at`)
      VALUES (NEW.`id`,'customer_changed','change','customer_id',OLD.`customer_id`,NEW.`customer_id`,(SELECT `name` FROM `customer` WHERE `id`=OLD.`customer_id` LIMIT 1),(SELECT `name` FROM `customer` WHERE `id`=NEW.`customer_id` LIMIT 1),'ticket',NEW.`id`,NEW.`changed_by_user_id`,v_actor_type,v_actor_name,v_source,NOW());
    END IF;
    IF NOT (OLD.`customer_user_id` <=> NEW.`customer_user_id`) THEN
      INSERT INTO `ticket_history` (`ticket_id`,`event_type`,`event_category`,`field_name`,`old_value`,`new_value`,`old_display`,`new_display`,`object_type`,`object_id`,`actor_user_id`,`actor_type`,`actor_name`,`source`,`created_at`)
      VALUES (NEW.`id`,'customer_user_changed','change','customer_user_id',OLD.`customer_user_id`,NEW.`customer_user_id`,(SELECT COALESCE(NULLIF(TRIM(CONCAT(`firstname`,' ',`lastname`)),''),`login`,`email`) FROM `customer_user` WHERE `id`=OLD.`customer_user_id` LIMIT 1),(SELECT COALESCE(NULLIF(TRIM(CONCAT(`firstname`,' ',`lastname`)),''),`login`,`email`) FROM `customer_user` WHERE `id`=NEW.`customer_user_id` LIMIT 1),'ticket',NEW.`id`,NEW.`changed_by_user_id`,v_actor_type,v_actor_name,v_source,NOW());
    END IF;
    IF NOT (OLD.`owner_user_id` <=> NEW.`owner_user_id`) THEN
      INSERT INTO `ticket_history` (`ticket_id`,`event_type`,`event_category`,`field_name`,`old_value`,`new_value`,`old_display`,`new_display`,`object_type`,`object_id`,`actor_user_id`,`actor_type`,`actor_name`,`source`,`created_at`)
      VALUES (NEW.`id`,'owner_changed','change','owner_user_id',OLD.`owner_user_id`,NEW.`owner_user_id`,(SELECT COALESCE(NULLIF(TRIM(CONCAT(`firstname`,' ',`lastname`)),''),`login`,`email`) FROM `user_account` WHERE `id`=OLD.`owner_user_id` LIMIT 1),(SELECT COALESCE(NULLIF(TRIM(CONCAT(`firstname`,' ',`lastname`)),''),`login`,`email`) FROM `user_account` WHERE `id`=NEW.`owner_user_id` LIMIT 1),'ticket',NEW.`id`,NEW.`changed_by_user_id`,v_actor_type,v_actor_name,v_source,NOW());
    END IF;
    IF NOT (OLD.`responsible_user_id` <=> NEW.`responsible_user_id`) THEN
      INSERT INTO `ticket_history` (`ticket_id`,`event_type`,`event_category`,`field_name`,`old_value`,`new_value`,`old_display`,`new_display`,`object_type`,`object_id`,`actor_user_id`,`actor_type`,`actor_name`,`source`,`created_at`)
      VALUES (NEW.`id`,'responsible_changed','change','responsible_user_id',OLD.`responsible_user_id`,NEW.`responsible_user_id`,(SELECT COALESCE(NULLIF(TRIM(CONCAT(`firstname`,' ',`lastname`)),''),`login`,`email`) FROM `user_account` WHERE `id`=OLD.`responsible_user_id` LIMIT 1),(SELECT COALESCE(NULLIF(TRIM(CONCAT(`firstname`,' ',`lastname`)),''),`login`,`email`) FROM `user_account` WHERE `id`=NEW.`responsible_user_id` LIMIT 1),'ticket',NEW.`id`,NEW.`changed_by_user_id`,v_actor_type,v_actor_name,v_source,NOW());
    END IF;
    IF NOT (OLD.`service_id` <=> NEW.`service_id`) THEN
      INSERT INTO `ticket_history` (`ticket_id`,`event_type`,`event_category`,`field_name`,`old_value`,`new_value`,`old_display`,`new_display`,`object_type`,`object_id`,`actor_user_id`,`actor_type`,`actor_name`,`source`,`created_at`)
      VALUES (NEW.`id`,'service_changed','change','service_id',OLD.`service_id`,NEW.`service_id`,(SELECT `name` FROM `service` WHERE `id`=OLD.`service_id` LIMIT 1),(SELECT `name` FROM `service` WHERE `id`=NEW.`service_id` LIMIT 1),'ticket',NEW.`id`,NEW.`changed_by_user_id`,v_actor_type,v_actor_name,v_source,NOW());
    END IF;
    IF NOT (OLD.`sla_id` <=> NEW.`sla_id`) THEN
      INSERT INTO `ticket_history` (`ticket_id`,`event_type`,`event_category`,`field_name`,`old_value`,`new_value`,`old_display`,`new_display`,`object_type`,`object_id`,`actor_user_id`,`actor_type`,`actor_name`,`source`,`created_at`)
      VALUES (NEW.`id`,'sla_changed','change','sla_id',OLD.`sla_id`,NEW.`sla_id`,COALESCE((SELECT `name` FROM `sla` WHERE `id`=OLD.`sla_id` LIMIT 1),OLD.`sla_name_snapshot`),COALESCE((SELECT `name` FROM `sla` WHERE `id`=NEW.`sla_id` LIMIT 1),NEW.`sla_name_snapshot`),'ticket',NEW.`id`,NEW.`changed_by_user_id`,v_actor_type,v_actor_name,v_source,NOW());
    END IF;
    IF NOT (OLD.`pending_until` <=> NEW.`pending_until`) THEN
      INSERT INTO `ticket_history` (`ticket_id`,`event_type`,`event_category`,`field_name`,`old_value`,`new_value`,`old_display`,`new_display`,`object_type`,`object_id`,`actor_user_id`,`actor_type`,`actor_name`,`source`,`created_at`)
      VALUES (NEW.`id`,'pending_changed','change','pending_until',OLD.`pending_until`,NEW.`pending_until`,OLD.`pending_until`,NEW.`pending_until`,'ticket',NEW.`id`,NEW.`changed_by_user_id`,v_actor_type,v_actor_name,v_source,NOW());
    END IF;
END;;

CREATE TRIGGER `qisutu_history_article_insert`
AFTER INSERT ON `ticket_article`
FOR EACH ROW
BEGIN
    DECLARE v_actor_name varchar(255) DEFAULT 'System';
    DECLARE v_actor_type varchar(30) DEFAULT 'system';

    IF NEW.`sender_type` = 'customer' THEN
      SET v_actor_name = COALESCE(NULLIF(NEW.`from_name`,''),NULLIF(NEW.`from_email`,''),'Customer');
      SET v_actor_type = 'customer';
    ELSE
      SELECT
        COALESCE(NULLIF(TRIM(CONCAT(`firstname`, ' ', `lastname`)), ''), NULLIF(`login`, ''), `email`, 'System'),
        CASE WHEN `is_system_user` = 1 THEN 'system' ELSE `account_type` END
      INTO v_actor_name, v_actor_type
      FROM `user_account`
      WHERE `id` = NEW.`created_by_user_id`
      LIMIT 1;
    END IF;

    INSERT INTO `ticket_history` (`ticket_id`,`event_type`,`event_category`,`field_name`,`new_value`,`new_display`,`article_id`,`object_type`,`object_id`,`actor_user_id`,`actor_type`,`actor_name`,`source`,`details_text`,`created_at`)
    VALUES (NEW.`ticket_id`,'article_created','communication','article',NEW.`channel`,NEW.`subject`,NEW.`id`,'ticket_article',NEW.`id`,CASE WHEN NEW.`sender_type`='customer' THEN NULL ELSE NEW.`created_by_user_id` END,COALESCE(NULLIF(@qisutu_history_actor_type,''),v_actor_type),COALESCE(NULLIF(@qisutu_history_actor_name,''),v_actor_name),COALESCE(NULLIF(@qisutu_history_source,''),NEW.`channel`),CONCAT('visibility=',NEW.`visibility`,'; sender=',NEW.`sender_type`),CASE WHEN COALESCE(@qisutu_history_source,'') IN ('split','merge') THEN NOW() ELSE NEW.`created_at` END);
END;;

CREATE TRIGGER `qisutu_history_attachment_insert`
AFTER INSERT ON `ticket_article_attachment`
FOR EACH ROW
BEGIN
    DECLARE v_actor_name varchar(255) DEFAULT 'System';
    DECLARE v_actor_type varchar(30) DEFAULT 'system';
    SELECT COALESCE(NULLIF(TRIM(CONCAT(`firstname`,' ',`lastname`)),''),NULLIF(`login`,''),`email`,'System'),CASE WHEN `is_system_user`=1 THEN 'system' ELSE `account_type` END
      INTO v_actor_name,v_actor_type FROM `user_account` WHERE `id`=NEW.`created_by_user_id` LIMIT 1;
    INSERT INTO `ticket_history` (`ticket_id`,`event_type`,`event_category`,`field_name`,`new_value`,`new_display`,`article_id`,`object_type`,`object_id`,`actor_user_id`,`actor_type`,`actor_name`,`source`,`details_text`,`created_at`)
    VALUES (NEW.`ticket_id`,'attachment_added','communication','attachment',NEW.`id`,NEW.`filename`,NEW.`article_id`,'ticket_article_attachment',NEW.`id`,NEW.`created_by_user_id`,COALESCE(NULLIF(@qisutu_history_actor_type,''),v_actor_type),COALESCE(NULLIF(@qisutu_history_actor_name,''),v_actor_name),COALESCE(NULLIF(@qisutu_history_source,''),'attachment'),CONCAT(NEW.`content_type`,'; ',NEW.`content_size`,' bytes'),CASE WHEN COALESCE(@qisutu_history_source,'') IN ('split','merge') THEN NOW() ELSE NEW.`created_at` END);
END;;

CREATE TRIGGER `qisutu_history_dynamic_field_insert`
AFTER INSERT ON `ticket_dynamic_field_value`
FOR EACH ROW
BEGIN
    DECLARE v_actor_name varchar(255) DEFAULT 'System';
    DECLARE v_actor_type varchar(30) DEFAULT 'system';
    SELECT COALESCE(NULLIF(TRIM(CONCAT(`firstname`,' ',`lastname`)),''),NULLIF(`login`,''),`email`,'System'),CASE WHEN `is_system_user`=1 THEN 'system' ELSE `account_type` END
      INTO v_actor_name,v_actor_type FROM `user_account` WHERE `id`=NEW.`changed_by_user_id` LIMIT 1;
    INSERT INTO `ticket_history` (`ticket_id`,`event_type`,`event_category`,`field_name`,`new_value`,`new_display`,`object_type`,`object_id`,`actor_user_id`,`actor_type`,`actor_name`,`source`,`details_text`,`created_at`)
    VALUES (NEW.`ticket_id`,'dynamic_field_changed','change',(SELECT `name` FROM `ticket_dynamic_field` WHERE `id`=NEW.`field_id` LIMIT 1),NEW.`value_text`,NEW.`value_text`,'ticket_dynamic_field_value',NEW.`id`,NEW.`changed_by_user_id`,COALESCE(NULLIF(@qisutu_history_actor_type,''),v_actor_type),COALESCE(NULLIF(@qisutu_history_actor_name,''),v_actor_name),COALESCE(NULLIF(@qisutu_history_source,''),'application'),(SELECT `label` FROM `ticket_dynamic_field` WHERE `id`=NEW.`field_id` LIMIT 1),NOW());
END;;

CREATE TRIGGER `qisutu_history_dynamic_field_update`
AFTER UPDATE ON `ticket_dynamic_field_value`
FOR EACH ROW
BEGIN
    DECLARE v_actor_name varchar(255) DEFAULT 'System';
    DECLARE v_actor_type varchar(30) DEFAULT 'system';
    IF NOT (OLD.`value_text` <=> NEW.`value_text`) THEN
      SELECT COALESCE(NULLIF(TRIM(CONCAT(`firstname`,' ',`lastname`)),''),NULLIF(`login`,''),`email`,'System'),CASE WHEN `is_system_user`=1 THEN 'system' ELSE `account_type` END
        INTO v_actor_name,v_actor_type FROM `user_account` WHERE `id`=NEW.`changed_by_user_id` LIMIT 1;
      INSERT INTO `ticket_history` (`ticket_id`,`event_type`,`event_category`,`field_name`,`old_value`,`new_value`,`old_display`,`new_display`,`object_type`,`object_id`,`actor_user_id`,`actor_type`,`actor_name`,`source`,`details_text`,`created_at`)
      VALUES (NEW.`ticket_id`,'dynamic_field_changed','change',(SELECT `name` FROM `ticket_dynamic_field` WHERE `id`=NEW.`field_id` LIMIT 1),OLD.`value_text`,NEW.`value_text`,OLD.`value_text`,NEW.`value_text`,'ticket_dynamic_field_value',NEW.`id`,NEW.`changed_by_user_id`,COALESCE(NULLIF(@qisutu_history_actor_type,''),v_actor_type),COALESCE(NULLIF(@qisutu_history_actor_name,''),v_actor_name),COALESCE(NULLIF(@qisutu_history_source,''),'application'),(SELECT `label` FROM `ticket_dynamic_field` WHERE `id`=NEW.`field_id` LIMIT 1),NOW());
    END IF;
END;;

CREATE TRIGGER `qisutu_history_dynamic_field_delete`
BEFORE DELETE ON `ticket_dynamic_field_value`
FOR EACH ROW
BEGIN
    INSERT INTO `ticket_history` (`ticket_id`,`event_type`,`event_category`,`field_name`,`old_value`,`old_display`,`object_type`,`object_id`,`actor_user_id`,`actor_type`,`actor_name`,`source`,`details_text`,`created_at`)
    VALUES (OLD.`ticket_id`,'dynamic_field_changed','change',(SELECT `name` FROM `ticket_dynamic_field` WHERE `id`=OLD.`field_id` LIMIT 1),OLD.`value_text`,OLD.`value_text`,'ticket_dynamic_field_value',OLD.`id`,NULL,COALESCE(NULLIF(@qisutu_history_actor_type,''),'system'),COALESCE(NULLIF(@qisutu_history_actor_name,''),'System'),COALESCE(NULLIF(@qisutu_history_source,''),'application'),(SELECT `label` FROM `ticket_dynamic_field` WHERE `id`=OLD.`field_id` LIMIT 1),NOW());
END;;

CREATE TRIGGER `qisutu_history_time_insert`
AFTER INSERT ON `ticket_time_accounting`
FOR EACH ROW
BEGIN
    DECLARE v_actor_name varchar(255) DEFAULT 'System';
    DECLARE v_actor_type varchar(30) DEFAULT 'agent';
    SELECT COALESCE(NULLIF(TRIM(CONCAT(`firstname`,' ',`lastname`)),''),NULLIF(`login`,''),`email`,'System'),CASE WHEN `is_system_user`=1 THEN 'system' ELSE `account_type` END
      INTO v_actor_name,v_actor_type FROM `user_account` WHERE `id`=NEW.`created_by_user_id` LIMIT 1;
    INSERT INTO `ticket_history` (`ticket_id`,`event_type`,`event_category`,`field_name`,`new_value`,`new_display`,`article_id`,`object_type`,`object_id`,`actor_user_id`,`actor_type`,`actor_name`,`source`,`details_text`,`created_at`)
    VALUES (NEW.`ticket_id`,'time_added','time','duration_minutes',NEW.`duration_minutes`,CONCAT(NEW.`duration_minutes`,' min'),NEW.`ticket_article_id`,'ticket_time_accounting',NEW.`id`,NEW.`created_by_user_id`,COALESCE(NULLIF(@qisutu_history_actor_type,''),v_actor_type),COALESCE(NULLIF(@qisutu_history_actor_name,''),v_actor_name),COALESCE(NULLIF(@qisutu_history_source,''),NEW.`source`),CONCAT(COALESCE(NEW.`description`,''),CASE WHEN NEW.`is_billable`=1 THEN ' [billable]' ELSE ' [not billable]' END),NEW.`created_at`);
END;;

CREATE TRIGGER `qisutu_history_time_cancel_insert`
AFTER INSERT ON `ticket_time_accounting_cancellation`
FOR EACH ROW
BEGIN
    DECLARE v_ticket_id bigint(20) unsigned DEFAULT 0;
    DECLARE v_actor_name varchar(255) DEFAULT 'System';
    DECLARE v_actor_type varchar(30) DEFAULT 'agent';
    SELECT `ticket_id` INTO v_ticket_id FROM `ticket_time_accounting` WHERE `id`=NEW.`time_accounting_id` LIMIT 1;
    SELECT COALESCE(NULLIF(TRIM(CONCAT(`firstname`,' ',`lastname`)),''),NULLIF(`login`,''),`email`,'System'),CASE WHEN `is_system_user`=1 THEN 'system' ELSE `account_type` END
      INTO v_actor_name,v_actor_type FROM `user_account` WHERE `id`=NEW.`cancelled_by_user_id` LIMIT 1;
    INSERT INTO `ticket_history` (`ticket_id`,`event_type`,`event_category`,`field_name`,`old_value`,`new_value`,`object_type`,`object_id`,`actor_user_id`,`actor_type`,`actor_name`,`source`,`details_text`,`created_at`)
    VALUES (v_ticket_id,'time_cancelled','time','time_accounting_id',NEW.`time_accounting_id`,NEW.`replacement_time_accounting_id`,'ticket_time_accounting_cancellation',NEW.`id`,NEW.`cancelled_by_user_id`,COALESCE(NULLIF(@qisutu_history_actor_type,''),v_actor_type),COALESCE(NULLIF(@qisutu_history_actor_name,''),v_actor_name),COALESCE(NULLIF(@qisutu_history_source,''),'correction'),NEW.`reason`,NEW.`cancelled_at`);
END;;

CREATE TRIGGER `qisutu_history_link_insert`
AFTER INSERT ON `ticket_link`
FOR EACH ROW
BEGIN
    DECLARE v_actor_name varchar(255) DEFAULT 'System';
    DECLARE v_actor_type varchar(30) DEFAULT 'agent';
    DECLARE v_event_type varchar(50) DEFAULT 'ticket_linked';
    SELECT COALESCE(NULLIF(TRIM(CONCAT(`firstname`,' ',`lastname`)),''),NULLIF(`login`,''),`email`,'System'),CASE WHEN `is_system_user`=1 THEN 'system' ELSE `account_type` END
      INTO v_actor_name,v_actor_type FROM `user_account` WHERE `id`=NEW.`created_by_user_id` LIMIT 1;
    SET v_event_type = CASE NEW.`link_type` WHEN 'split' THEN 'ticket_split' WHEN 'merge' THEN 'ticket_merged' ELSE 'ticket_linked' END;
    INSERT INTO `ticket_history` (`ticket_id`,`event_type`,`event_category`,`field_name`,`new_value`,`new_display`,`related_ticket_id`,`object_type`,`object_id`,`actor_user_id`,`actor_type`,`actor_name`,`source`,`created_at`)
    VALUES (NEW.`source_ticket_id`,v_event_type,'system','link_type',NEW.`link_type`,(SELECT `ticket_number` FROM `ticket` WHERE `id`=NEW.`target_ticket_id` LIMIT 1),NEW.`target_ticket_id`,'ticket_link',NEW.`id`,NEW.`created_by_user_id`,COALESCE(NULLIF(@qisutu_history_actor_type,''),v_actor_type),COALESCE(NULLIF(@qisutu_history_actor_name,''),v_actor_name),NEW.`link_type`,NEW.`created_at`);
    INSERT INTO `ticket_history` (`ticket_id`,`event_type`,`event_category`,`field_name`,`new_value`,`new_display`,`related_ticket_id`,`object_type`,`object_id`,`actor_user_id`,`actor_type`,`actor_name`,`source`,`created_at`)
    VALUES (NEW.`target_ticket_id`,v_event_type,'system','link_type',NEW.`link_type`,(SELECT `ticket_number` FROM `ticket` WHERE `id`=NEW.`source_ticket_id` LIMIT 1),NEW.`source_ticket_id`,'ticket_link',NEW.`id`,NEW.`created_by_user_id`,COALESCE(NULLIF(@qisutu_history_actor_type,''),v_actor_type),COALESCE(NULLIF(@qisutu_history_actor_name,''),v_actor_name),NEW.`link_type`,NEW.`created_at`);
END;;

CREATE TRIGGER `qisutu_history_checklist_audit_insert`
AFTER INSERT ON `ticket_checklist_audit`
FOR EACH ROW
BEGIN
    DECLARE v_actor_name varchar(255) DEFAULT 'System';
    DECLARE v_actor_type varchar(30) DEFAULT 'agent';
    SELECT COALESCE(NULLIF(TRIM(CONCAT(`firstname`,' ',`lastname`)),''),NULLIF(`login`,''),`email`,'System'),CASE WHEN `is_system_user`=1 THEN 'system' ELSE `account_type` END
      INTO v_actor_name,v_actor_type FROM `user_account` WHERE `id`=NEW.`created_by_user_id` LIMIT 1;
    INSERT INTO `ticket_history` (`ticket_id`,`event_type`,`event_category`,`field_name`,`new_value`,`new_display`,`object_type`,`object_id`,`actor_user_id`,`actor_type`,`actor_name`,`source`,`details_text`,`created_at`)
    VALUES (NEW.`ticket_id`,NEW.`action`,'system','checklist',NEW.`ticket_checklist_item_id`,NEW.`details`,'ticket_checklist_audit',NEW.`id`,NEW.`created_by_user_id`,COALESCE(NULLIF(@qisutu_history_actor_type,''),v_actor_type),COALESCE(NULLIF(@qisutu_history_actor_name,''),v_actor_name),COALESCE(NULLIF(@qisutu_history_source,''),'checklist'),NEW.`details`,NEW.`created_at`);
END;;

CREATE TRIGGER `qisutu_history_form_submission_insert`
AFTER INSERT ON `ticket_form_submission`
FOR EACH ROW
BEGIN
    INSERT INTO `ticket_history` (`ticket_id`,`event_type`,`event_category`,`field_name`,`new_value`,`new_display`,`object_type`,`object_id`,`actor_user_id`,`actor_type`,`actor_name`,`source`,`details_text`,`created_at`)
    VALUES (NEW.`ticket_id`,'form_submitted','communication','form',NEW.`form_id`,NEW.`form_title_snapshot`,'ticket_form_submission',NEW.`id`,NULL,CASE WHEN NEW.`source`='customer_portal' THEN 'customer' ELSE 'public' END,COALESCE(NULLIF(NEW.`submitter_name`,''),NULLIF(NEW.`submitter_email`,''),'Web form'),NEW.`source`,NEW.`form_name_snapshot`,NEW.`created_at`);
END;;

CREATE TRIGGER `qisutu_history_bulk_item_insert`
AFTER INSERT ON `ticket_bulk_action_item`
FOR EACH ROW
BEGIN
    DECLARE v_actor_id bigint(20) unsigned DEFAULT NULL;
    DECLARE v_actor_name varchar(255) DEFAULT 'System';
    DECLARE v_actor_type varchar(30) DEFAULT 'agent';
    DECLARE v_reason text DEFAULT NULL;
    IF NEW.`ticket_id` IS NOT NULL AND NEW.`result`='success' THEN
      SELECT `created_by_user_id`,`change_reason` INTO v_actor_id,v_reason FROM `ticket_bulk_action` WHERE `id`=NEW.`bulk_action_id` LIMIT 1;
      SELECT COALESCE(NULLIF(TRIM(CONCAT(`firstname`,' ',`lastname`)),''),NULLIF(`login`,''),`email`,'System'),CASE WHEN `is_system_user`=1 THEN 'system' ELSE `account_type` END
        INTO v_actor_name,v_actor_type FROM `user_account` WHERE `id`=v_actor_id LIMIT 1;
      INSERT INTO `ticket_history` (`ticket_id`,`event_type`,`event_category`,`field_name`,`new_value`,`new_display`,`object_type`,`object_id`,`actor_user_id`,`actor_type`,`actor_name`,`source`,`details_text`,`created_at`)
      VALUES (NEW.`ticket_id`,'bulk_action','system','bulk_action_id',NEW.`bulk_action_id`,CONCAT('#',NEW.`bulk_action_id`),'ticket_bulk_action_item',NEW.`id`,v_actor_id,v_actor_type,v_actor_name,'bulk',CONCAT(COALESCE(v_reason,''),CASE WHEN COALESCE(v_reason,'')<>'' THEN '\n' ELSE '' END,LEFT(NEW.`changes_json`,4000)),NEW.`created_at`);
    END IF;
END;;

DELIMITER ;

-- Existing records are imported once and visibly marked as backfilled data.
INSERT IGNORE INTO `ticket_history` (`event_key`,`ticket_id`,`event_type`,`event_category`,`object_type`,`object_id`,`actor_user_id`,`actor_type`,`actor_name`,`source`,`details_text`,`is_backfill`,`created_at`)
SELECT CONCAT('backfill:ticket:',t.`id`),t.`id`,'ticket_created','system','ticket',t.`id`,t.`created_by_user_id`,CASE WHEN COALESCE(u.`is_system_user`,1)=1 THEN 'system' ELSE COALESCE(u.`account_type`,'agent') END,COALESCE(NULLIF(TRIM(CONCAT(u.`firstname`,' ',u.`lastname`)),''),u.`login`,u.`email`,'System'),'migration','Existing ticket',1,t.`created_at`
FROM `ticket` t LEFT JOIN `user_account` u ON u.`id`=t.`created_by_user_id`;

INSERT IGNORE INTO `ticket_history` (`event_key`,`ticket_id`,`event_type`,`event_category`,`field_name`,`new_value`,`new_display`,`article_id`,`object_type`,`object_id`,`actor_user_id`,`actor_type`,`actor_name`,`source`,`details_text`,`is_backfill`,`created_at`)
SELECT CONCAT('backfill:article:',a.`id`),a.`ticket_id`,'article_created','communication','article',a.`channel`,a.`subject`,a.`id`,'ticket_article',a.`id`,CASE WHEN a.`sender_type`='customer' THEN NULL ELSE a.`created_by_user_id` END,CASE WHEN a.`sender_type`='customer' THEN 'customer' WHEN COALESCE(u.`is_system_user`,1)=1 THEN 'system' ELSE COALESCE(u.`account_type`,'agent') END,CASE WHEN a.`sender_type`='customer' THEN COALESCE(NULLIF(a.`from_name`,''),NULLIF(a.`from_email`,''),'Customer') ELSE COALESCE(NULLIF(TRIM(CONCAT(u.`firstname`,' ',u.`lastname`)),''),u.`login`,u.`email`,'System') END,a.`channel`,CONCAT('visibility=',a.`visibility`,'; sender=',a.`sender_type`),1,a.`created_at`
FROM `ticket_article` a LEFT JOIN `user_account` u ON u.`id`=a.`created_by_user_id`;

INSERT IGNORE INTO `ticket_history` (`event_key`,`ticket_id`,`event_type`,`event_category`,`field_name`,`new_value`,`new_display`,`article_id`,`object_type`,`object_id`,`actor_user_id`,`actor_type`,`actor_name`,`source`,`details_text`,`is_backfill`,`created_at`)
SELECT CONCAT('backfill:time:',ta.`id`),ta.`ticket_id`,'time_added','time','duration_minutes',ta.`duration_minutes`,CONCAT(ta.`duration_minutes`,' min'),ta.`ticket_article_id`,'ticket_time_accounting',ta.`id`,ta.`created_by_user_id`,CASE WHEN COALESCE(u.`is_system_user`,0)=1 THEN 'system' ELSE COALESCE(u.`account_type`,'agent') END,COALESCE(NULLIF(TRIM(CONCAT(u.`firstname`,' ',u.`lastname`)),''),u.`login`,u.`email`,'System'),ta.`source`,CONCAT(COALESCE(ta.`description`,''),CASE WHEN ta.`is_billable`=1 THEN ' [billable]' ELSE ' [not billable]' END),1,ta.`created_at`
FROM `ticket_time_accounting` ta LEFT JOIN `user_account` u ON u.`id`=ta.`created_by_user_id`;

INSERT IGNORE INTO `ticket_history` (`event_key`,`ticket_id`,`event_type`,`event_category`,`field_name`,`old_value`,`new_value`,`object_type`,`object_id`,`actor_user_id`,`actor_type`,`actor_name`,`source`,`details_text`,`is_backfill`,`created_at`)
SELECT CONCAT('backfill:time-cancel:',c.`id`),ta.`ticket_id`,'time_cancelled','time','time_accounting_id',c.`time_accounting_id`,c.`replacement_time_accounting_id`,'ticket_time_accounting_cancellation',c.`id`,c.`cancelled_by_user_id`,CASE WHEN COALESCE(u.`is_system_user`,0)=1 THEN 'system' ELSE COALESCE(u.`account_type`,'agent') END,COALESCE(NULLIF(TRIM(CONCAT(u.`firstname`,' ',u.`lastname`)),''),u.`login`,u.`email`,'System'),'correction',c.`reason`,1,c.`cancelled_at`
FROM `ticket_time_accounting_cancellation` c INNER JOIN `ticket_time_accounting` ta ON ta.`id`=c.`time_accounting_id` LEFT JOIN `user_account` u ON u.`id`=c.`cancelled_by_user_id`;

INSERT IGNORE INTO `ticket_history` (`event_key`,`ticket_id`,`event_type`,`event_category`,`field_name`,`new_value`,`new_display`,`related_ticket_id`,`object_type`,`object_id`,`actor_user_id`,`actor_type`,`actor_name`,`source`,`is_backfill`,`created_at`)
SELECT CONCAT('backfill:link-source:',l.`id`),l.`source_ticket_id`,CASE l.`link_type` WHEN 'split' THEN 'ticket_split' WHEN 'merge' THEN 'ticket_merged' ELSE 'ticket_linked' END,'system','link_type',l.`link_type`,t.`ticket_number`,l.`target_ticket_id`,'ticket_link',l.`id`,l.`created_by_user_id`,CASE WHEN COALESCE(u.`is_system_user`,0)=1 THEN 'system' ELSE COALESCE(u.`account_type`,'agent') END,COALESCE(NULLIF(TRIM(CONCAT(u.`firstname`,' ',u.`lastname`)),''),u.`login`,u.`email`,'System'),l.`link_type`,1,l.`created_at`
FROM `ticket_link` l INNER JOIN `ticket` t ON t.`id`=l.`target_ticket_id` LEFT JOIN `user_account` u ON u.`id`=l.`created_by_user_id`;

INSERT IGNORE INTO `ticket_history` (`event_key`,`ticket_id`,`event_type`,`event_category`,`field_name`,`new_value`,`new_display`,`related_ticket_id`,`object_type`,`object_id`,`actor_user_id`,`actor_type`,`actor_name`,`source`,`is_backfill`,`created_at`)
SELECT CONCAT('backfill:link-target:',l.`id`),l.`target_ticket_id`,CASE l.`link_type` WHEN 'split' THEN 'ticket_split' WHEN 'merge' THEN 'ticket_merged' ELSE 'ticket_linked' END,'system','link_type',l.`link_type`,t.`ticket_number`,l.`source_ticket_id`,'ticket_link',l.`id`,l.`created_by_user_id`,CASE WHEN COALESCE(u.`is_system_user`,0)=1 THEN 'system' ELSE COALESCE(u.`account_type`,'agent') END,COALESCE(NULLIF(TRIM(CONCAT(u.`firstname`,' ',u.`lastname`)),''),u.`login`,u.`email`,'System'),l.`link_type`,1,l.`created_at`
FROM `ticket_link` l INNER JOIN `ticket` t ON t.`id`=l.`source_ticket_id` LEFT JOIN `user_account` u ON u.`id`=l.`created_by_user_id`;

INSERT IGNORE INTO `ticket_history` (`event_key`,`ticket_id`,`event_type`,`event_category`,`field_name`,`new_value`,`new_display`,`object_type`,`object_id`,`actor_user_id`,`actor_type`,`actor_name`,`source`,`details_text`,`is_backfill`,`created_at`)
SELECT CONCAT('backfill:checklist:',a.`id`),a.`ticket_id`,a.`action`,'system','checklist',a.`ticket_checklist_item_id`,a.`details`,'ticket_checklist_audit',a.`id`,a.`created_by_user_id`,CASE WHEN COALESCE(u.`is_system_user`,0)=1 THEN 'system' ELSE COALESCE(u.`account_type`,'agent') END,COALESCE(NULLIF(TRIM(CONCAT(u.`firstname`,' ',u.`lastname`)),''),u.`login`,u.`email`,'System'),'checklist',a.`details`,1,a.`created_at`
FROM `ticket_checklist_audit` a LEFT JOIN `user_account` u ON u.`id`=a.`created_by_user_id`;

INSERT IGNORE INTO `ticket_history` (`event_key`,`ticket_id`,`event_type`,`event_category`,`field_name`,`new_value`,`new_display`,`object_type`,`object_id`,`actor_type`,`actor_name`,`source`,`details_text`,`is_backfill`,`created_at`)
SELECT CONCAT('backfill:form:',s.`id`),s.`ticket_id`,'form_submitted','communication','form',s.`form_id`,s.`form_title_snapshot`,'ticket_form_submission',s.`id`,CASE WHEN s.`source`='customer_portal' THEN 'customer' ELSE 'public' END,COALESCE(NULLIF(s.`submitter_name`,''),NULLIF(s.`submitter_email`,''),'Web form'),s.`source`,s.`form_name_snapshot`,1,s.`created_at`
FROM `ticket_form_submission` s;

INSERT IGNORE INTO `ticket_history` (`event_key`,`ticket_id`,`event_type`,`event_category`,`field_name`,`new_value`,`new_display`,`object_type`,`object_id`,`actor_user_id`,`actor_type`,`actor_name`,`source`,`details_text`,`is_backfill`,`created_at`)
SELECT CONCAT('backfill:bulk:',i.`id`),i.`ticket_id`,'bulk_action','system','bulk_action_id',i.`bulk_action_id`,CONCAT('#',i.`bulk_action_id`),'ticket_bulk_action_item',i.`id`,b.`created_by_user_id`,CASE WHEN COALESCE(u.`is_system_user`,0)=1 THEN 'system' ELSE COALESCE(u.`account_type`,'agent') END,COALESCE(NULLIF(TRIM(CONCAT(u.`firstname`,' ',u.`lastname`)),''),u.`login`,u.`email`,'System'),'bulk',CONCAT(COALESCE(b.`change_reason`,''),CASE WHEN COALESCE(b.`change_reason`,'')<>'' THEN '\n' ELSE '' END,LEFT(i.`changes_json`,4000)),1,i.`created_at`
FROM `ticket_bulk_action_item` i INNER JOIN `ticket_bulk_action` b ON b.`id`=i.`bulk_action_id` LEFT JOIN `user_account` u ON u.`id`=b.`created_by_user_id`
WHERE i.`ticket_id` IS NOT NULL AND i.`result`='success';

INSERT IGNORE INTO `ticket_history` (`event_key`,`ticket_id`,`event_type`,`event_category`,`field_name`,`new_value`,`new_display`,`object_type`,`object_id`,`actor_user_id`,`actor_type`,`actor_name`,`source`,`details_text`,`is_backfill`,`created_at`)
SELECT CONCAT('backfill:dynamic:',v.`id`),v.`ticket_id`,'dynamic_field_changed','change',f.`name`,v.`value_text`,v.`value_text`,'ticket_dynamic_field_value',v.`id`,v.`changed_by_user_id`,CASE WHEN COALESCE(u.`is_system_user`,1)=1 THEN 'system' ELSE COALESCE(u.`account_type`,'agent') END,COALESCE(NULLIF(TRIM(CONCAT(u.`firstname`,' ',u.`lastname`)),''),u.`login`,u.`email`,'System'),'migration',f.`label`,1,v.`changed_at`
FROM `ticket_dynamic_field_value` v INNER JOIN `ticket_dynamic_field` f ON f.`id`=v.`field_id` LEFT JOIN `user_account` u ON u.`id`=v.`changed_by_user_id`;

-- Qisutu CMDB
CREATE TABLE IF NOT EXISTS `cmdb_ci_type` (
  `id` bigint(20) unsigned NOT NULL AUTO_INCREMENT,
  `type_key` varchar(100) DEFAULT NULL,
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
  UNIQUE KEY `cmdb_ci_type_key_unique` (`type_key`),
  UNIQUE KEY `cmdb_ci_type_name_unique` (`name`),
  KEY `cmdb_ci_type_active_sort` (`active`,`sort_order`,`name`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE IF NOT EXISTS `cmdb_ci_field_group` (
  `id` bigint(20) unsigned NOT NULL AUTO_INCREMENT,
  `type_id` bigint(20) unsigned NOT NULL,
  `group_key` varchar(100) NOT NULL,
  `label` varchar(255) NOT NULL,
  `description` text DEFAULT NULL,
  `active` tinyint(1) NOT NULL DEFAULT 1,
  `sort_order` int(10) unsigned NOT NULL DEFAULT 1000,
  `created_by_user_id` bigint(20) unsigned NOT NULL,
  `changed_by_user_id` bigint(20) unsigned NOT NULL,
  `created_at` datetime NOT NULL DEFAULT current_timestamp(),
  `changed_at` datetime NOT NULL DEFAULT current_timestamp() ON UPDATE current_timestamp(),
  PRIMARY KEY (`id`),
  UNIQUE KEY `cmdb_ci_field_group_type_key_unique` (`type_id`,`group_key`),
  KEY `cmdb_ci_field_group_type_active_sort` (`type_id`,`active`,`sort_order`,`id`),
  CONSTRAINT `cmdb_ci_field_group_type_fk` FOREIGN KEY (`type_id`) REFERENCES `cmdb_ci_type` (`id`) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE IF NOT EXISTS `cmdb_ci_field` (
  `id` bigint(20) unsigned NOT NULL AUTO_INCREMENT,
  `type_id` bigint(20) unsigned NOT NULL,
  `group_id` bigint(20) unsigned DEFAULT NULL,
  `field_key` varchar(100) NOT NULL,
  `label` varchar(255) NOT NULL,
  `field_type` varchar(30) NOT NULL DEFAULT 'text',
  `is_required` tinyint(1) NOT NULL DEFAULT 0,
  `is_searchable` tinyint(1) NOT NULL DEFAULT 1,
  `is_unique` tinyint(1) NOT NULL DEFAULT 0,
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
  KEY `cmdb_ci_field_group_sort` (`group_id`,`sort_order`,`id`),
  CONSTRAINT `cmdb_ci_field_type_fk` FOREIGN KEY (`type_id`) REFERENCES `cmdb_ci_type` (`id`) ON DELETE CASCADE,
  CONSTRAINT `cmdb_ci_field_group_fk` FOREIGN KEY (`group_id`) REFERENCES `cmdb_ci_field_group` (`id`) ON DELETE SET NULL
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

CREATE TABLE IF NOT EXISTS `cmdb_status` (
  `id` bigint(20) unsigned NOT NULL AUTO_INCREMENT,
  `status_key` varchar(100) NOT NULL,
  `label` varchar(255) NOT NULL,
  `status_class` varchar(30) NOT NULL DEFAULT 'active',
  `color` varchar(20) NOT NULL DEFAULT '#4b6478',
  `active` tinyint(1) NOT NULL DEFAULT 1,
  `sort_order` int(10) unsigned NOT NULL DEFAULT 1000,
  `created_by_user_id` bigint(20) unsigned NOT NULL,
  `changed_by_user_id` bigint(20) unsigned NOT NULL,
  `created_at` datetime NOT NULL DEFAULT current_timestamp(),
  `changed_at` datetime NOT NULL DEFAULT current_timestamp() ON UPDATE current_timestamp(),
  PRIMARY KEY (`id`),
  UNIQUE KEY `cmdb_status_key_unique` (`status_key`),
  KEY `cmdb_status_active_sort` (`active`,`sort_order`,`label`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE IF NOT EXISTS `cmdb_ci_type_status` (
  `type_id` bigint(20) unsigned NOT NULL,
  `status_id` bigint(20) unsigned NOT NULL,
  `is_default` tinyint(1) NOT NULL DEFAULT 0,
  `sort_order` int(10) unsigned NOT NULL DEFAULT 1000,
  PRIMARY KEY (`type_id`,`status_id`),
  KEY `cmdb_ci_type_status_status` (`status_id`,`type_id`),
  CONSTRAINT `cmdb_ci_type_status_type_fk` FOREIGN KEY (`type_id`) REFERENCES `cmdb_ci_type` (`id`) ON DELETE CASCADE,
  CONSTRAINT `cmdb_ci_type_status_status_fk` FOREIGN KEY (`status_id`) REFERENCES `cmdb_status` (`id`) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE IF NOT EXISTS `cmdb_ci` (
  `id` bigint(20) unsigned NOT NULL AUTO_INCREMENT,
  `ci_number` varchar(50) NOT NULL,
  `type_id` bigint(20) unsigned NOT NULL,
  `name` varchar(500) NOT NULL,
  `description` text DEFAULT NULL,
  `status` varchar(100) NOT NULL DEFAULT '',
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

CREATE TABLE IF NOT EXISTS `cmdb_import_profile` (
  `id` bigint(20) unsigned NOT NULL AUTO_INCREMENT,
  `name` varchar(255) NOT NULL,
  `source_key` varchar(100) NOT NULL,
  `delimiter_char` varchar(5) NOT NULL DEFAULT ';',
  `encoding_name` varchar(30) NOT NULL DEFAULT 'UTF-8',
  `type_mode` varchar(20) NOT NULL DEFAULT 'fixed',
  `fixed_type_id` bigint(20) unsigned DEFAULT NULL,
  `type_column` varchar(255) NOT NULL DEFAULT '',
  `external_id_column` varchar(255) NOT NULL DEFAULT '',
  `max_rows` int(10) unsigned NOT NULL DEFAULT 100000,
  `active` tinyint(1) NOT NULL DEFAULT 1,
  `created_by_user_id` bigint(20) unsigned NOT NULL,
  `changed_by_user_id` bigint(20) unsigned NOT NULL,
  `created_at` datetime NOT NULL DEFAULT current_timestamp(),
  `changed_at` datetime NOT NULL DEFAULT current_timestamp() ON UPDATE current_timestamp(),
  PRIMARY KEY (`id`),
  UNIQUE KEY `cmdb_import_profile_source_unique` (`source_key`),
  KEY `cmdb_import_profile_active_name` (`active`,`name`),
  CONSTRAINT `cmdb_import_profile_type_fk` FOREIGN KEY (`fixed_type_id`) REFERENCES `cmdb_ci_type` (`id`) ON DELETE SET NULL
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE IF NOT EXISTS `cmdb_import_mapping` (
  `id` bigint(20) unsigned NOT NULL AUTO_INCREMENT,
  `profile_id` bigint(20) unsigned NOT NULL,
  `source_column` varchar(255) NOT NULL,
  `target_kind` varchar(30) NOT NULL,
  `target_key` varchar(190) NOT NULL DEFAULT '',
  `update_policy` varchar(20) NOT NULL DEFAULT 'always',
  `is_required` tinyint(1) NOT NULL DEFAULT 0,
  `default_value` text DEFAULT NULL,
  `sort_order` int(10) unsigned NOT NULL DEFAULT 1000,
  `created_at` datetime NOT NULL DEFAULT current_timestamp(),
  `changed_at` datetime NOT NULL DEFAULT current_timestamp() ON UPDATE current_timestamp(),
  PRIMARY KEY (`id`),
  UNIQUE KEY `cmdb_import_mapping_unique` (`profile_id`,`source_column`,`target_kind`,`target_key`),
  KEY `cmdb_import_mapping_profile_sort` (`profile_id`,`sort_order`,`id`),
  CONSTRAINT `cmdb_import_mapping_profile_fk` FOREIGN KEY (`profile_id`) REFERENCES `cmdb_import_profile` (`id`) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE IF NOT EXISTS `cmdb_import_value_map` (
  `id` bigint(20) unsigned NOT NULL AUTO_INCREMENT,
  `mapping_id` bigint(20) unsigned NOT NULL,
  `source_value` varchar(500) NOT NULL,
  `target_value` varchar(500) NOT NULL,
  PRIMARY KEY (`id`),
  UNIQUE KEY `cmdb_import_value_map_unique` (`mapping_id`,`source_value`),
  CONSTRAINT `cmdb_import_value_map_mapping_fk` FOREIGN KEY (`mapping_id`) REFERENCES `cmdb_import_mapping` (`id`) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE IF NOT EXISTS `cmdb_import_run` (
  `id` bigint(20) unsigned NOT NULL AUTO_INCREMENT,
  `profile_id` bigint(20) unsigned DEFAULT NULL,
  `file_name` varchar(500) NOT NULL,
  `file_sha256` char(64) NOT NULL,
  `run_mode` varchar(20) NOT NULL DEFAULT 'import',
  `status` varchar(20) NOT NULL DEFAULT 'running',
  `total_count` int(10) unsigned NOT NULL DEFAULT 0,
  `created_count` int(10) unsigned NOT NULL DEFAULT 0,
  `updated_count` int(10) unsigned NOT NULL DEFAULT 0,
  `unchanged_count` int(10) unsigned NOT NULL DEFAULT 0,
  `failed_count` int(10) unsigned NOT NULL DEFAULT 0,
  `error_text` longtext DEFAULT NULL,
  `created_by_user_id` bigint(20) unsigned DEFAULT NULL,
  `started_at` datetime NOT NULL DEFAULT current_timestamp(),
  `finished_at` datetime DEFAULT NULL,
  PRIMARY KEY (`id`),
  KEY `cmdb_import_run_profile_started` (`profile_id`,`started_at`,`id`),
  KEY `cmdb_import_run_status_started` (`status`,`started_at`,`id`),
  CONSTRAINT `cmdb_import_run_profile_fk` FOREIGN KEY (`profile_id`) REFERENCES `cmdb_import_profile` (`id`) ON DELETE SET NULL
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

--
-- Master data CSV import previews and audit log
--

CREATE TABLE IF NOT EXISTS `master_data_import_run` (
  `id` bigint(20) unsigned NOT NULL AUTO_INCREMENT,
  `import_type` varchar(30) NOT NULL,
  `file_name` varchar(255) NOT NULL,
  `file_sha256` char(64) NOT NULL,
  `analysis_sha256` char(64) NOT NULL,
  `status` varchar(30) NOT NULL DEFAULT 'pending',
  `staged_content` longtext DEFAULT NULL,
  `total_count` int(10) unsigned NOT NULL DEFAULT 0,
  `created_count` int(10) unsigned NOT NULL DEFAULT 0,
  `updated_count` int(10) unsigned NOT NULL DEFAULT 0,
  `unchanged_count` int(10) unsigned NOT NULL DEFAULT 0,
  `error_count` int(10) unsigned NOT NULL DEFAULT 0,
  `invitation_count` int(10) unsigned NOT NULL DEFAULT 0,
  `error_summary` longtext DEFAULT NULL,
  `created_by_user_id` bigint(20) unsigned NOT NULL,
  `created_at` datetime NOT NULL DEFAULT current_timestamp(),
  `expires_at` datetime NOT NULL,
  `imported_at` datetime DEFAULT NULL,
  PRIMARY KEY (`id`),
  KEY `master_data_import_type_created` (`import_type`,`created_at`,`id`),
  KEY `master_data_import_status_expires` (`status`,`expires_at`,`id`),
  KEY `master_data_import_created_by` (`created_by_user_id`),
  CONSTRAINT `master_data_import_created_by_fk` FOREIGN KEY (`created_by_user_id`) REFERENCES `user_account` (`id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE IF NOT EXISTS `master_data_import_item` (
  `id` bigint(20) unsigned NOT NULL AUTO_INCREMENT,
  `run_id` bigint(20) unsigned NOT NULL,
  `row_number` int(10) unsigned NOT NULL,
  `record_key` varchar(255) NOT NULL DEFAULT '',
  `action` varchar(20) NOT NULL,
  `message` text DEFAULT NULL,
  `created_at` datetime NOT NULL DEFAULT current_timestamp(),
  PRIMARY KEY (`id`),
  KEY `master_data_import_item_run_action` (`run_id`,`action`,`row_number`,`id`),
  CONSTRAINT `master_data_import_item_run_fk` FOREIGN KEY (`run_id`) REFERENCES `master_data_import_run` (`id`) ON DELETE CASCADE
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

-- Qisutu knowledge base
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
  `status` varchar(20) NOT NULL DEFAULT 'published',
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

-- Qisutu REST API
CREATE TABLE IF NOT EXISTS `api_token` (
  `id` bigint(20) unsigned NOT NULL AUTO_INCREMENT,
  `user_account_id` bigint(20) unsigned NOT NULL,
  `label` varchar(190) NOT NULL,
  `token_prefix` varchar(24) NOT NULL,
  `token_hash` char(64) NOT NULL,
  `scopes_json` text NOT NULL,
  `allowed_ips` text DEFAULT NULL,
  `rate_limit_per_minute` int(10) unsigned NOT NULL DEFAULT 120,
  `active` tinyint(1) NOT NULL DEFAULT 1,
  `expires_at` datetime DEFAULT NULL,
  `last_used_at` datetime DEFAULT NULL,
  `last_used_ip` varchar(45) DEFAULT NULL,
  `created_by_user_id` bigint(20) unsigned NOT NULL,
  `changed_by_user_id` bigint(20) unsigned NOT NULL,
  `created_at` datetime NOT NULL DEFAULT current_timestamp(),
  `changed_at` datetime NOT NULL DEFAULT current_timestamp() ON UPDATE current_timestamp(),
  PRIMARY KEY (`id`),
  UNIQUE KEY `api_token_hash_unique` (`token_hash`),
  KEY `api_token_user_active` (`user_account_id`,`active`,`id`),
  KEY `api_token_prefix` (`token_prefix`),
  CONSTRAINT `api_token_user_fk` FOREIGN KEY (`user_account_id`) REFERENCES `user_account` (`id`),
  CONSTRAINT `api_token_created_by_fk` FOREIGN KEY (`created_by_user_id`) REFERENCES `user_account` (`id`),
  CONSTRAINT `api_token_changed_by_fk` FOREIGN KEY (`changed_by_user_id`) REFERENCES `user_account` (`id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE IF NOT EXISTS `api_request_log` (
  `id` bigint(20) unsigned NOT NULL AUTO_INCREMENT,
  `request_id` char(36) NOT NULL,
  `api_token_id` bigint(20) unsigned DEFAULT NULL,
  `user_account_id` bigint(20) unsigned DEFAULT NULL,
  `method` varchar(10) NOT NULL,
  `request_path` varchar(500) NOT NULL,
  `status_code` smallint(5) unsigned NOT NULL,
  `remote_ip` varchar(45) NOT NULL DEFAULT '',
  `duration_ms` int(10) unsigned NOT NULL DEFAULT 0,
  `result_code` varchar(100) NOT NULL DEFAULT '',
  `resource_type` varchar(50) NOT NULL DEFAULT '',
  `resource_id` bigint(20) unsigned DEFAULT NULL,
  `created_at` datetime NOT NULL DEFAULT current_timestamp(),
  PRIMARY KEY (`id`),
  UNIQUE KEY `api_request_log_request_unique` (`request_id`),
  KEY `api_request_log_token_created` (`api_token_id`,`created_at`,`id`),
  KEY `api_request_log_user_created` (`user_account_id`,`created_at`,`id`),
  KEY `api_request_log_created` (`created_at`,`id`),
  CONSTRAINT `api_request_log_token_fk` FOREIGN KEY (`api_token_id`) REFERENCES `api_token` (`id`) ON DELETE SET NULL,
  CONSTRAINT `api_request_log_user_fk` FOREIGN KEY (`user_account_id`) REFERENCES `user_account` (`id`) ON DELETE SET NULL
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE IF NOT EXISTS `api_idempotency` (
  `id` bigint(20) unsigned NOT NULL AUTO_INCREMENT,
  `api_token_id` bigint(20) unsigned NOT NULL,
  `idempotency_key` varchar(190) NOT NULL,
  `method` varchar(10) NOT NULL,
  `request_path` varchar(500) NOT NULL,
  `request_hash` char(64) NOT NULL,
  `status_code` smallint(5) unsigned NOT NULL,
  `response_json` mediumtext NOT NULL,
  `created_at` datetime NOT NULL DEFAULT current_timestamp(),
  `expires_at` datetime NOT NULL,
  PRIMARY KEY (`id`),
  UNIQUE KEY `api_idempotency_token_key_unique` (`api_token_id`,`idempotency_key`),
  KEY `api_idempotency_expiry` (`expires_at`,`id`),
  CONSTRAINT `api_idempotency_token_fk` FOREIGN KEY (`api_token_id`) REFERENCES `api_token` (`id`) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- Flexible agent reports and statistics
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

CREATE TABLE IF NOT EXISTS `report_schedule` (
  `id` bigint(20) unsigned NOT NULL AUTO_INCREMENT,
  `report_definition_id` bigint(20) unsigned NOT NULL,
  `active` tinyint(1) NOT NULL DEFAULT 0,
  `frequency` varchar(20) NOT NULL DEFAULT 'daily',
  `send_time` time NOT NULL DEFAULT '08:00:00',
  `weekday` tinyint(3) unsigned DEFAULT NULL,
  `monthday` tinyint(3) unsigned DEFAULT NULL,
  `period_type` varchar(30) NOT NULL DEFAULT 'previous_month',
  `period_field` varchar(100) NOT NULL DEFAULT 'created_at',
  `rolling_days` smallint(5) unsigned DEFAULT NULL,
  `formats` varchar(100) NOT NULL DEFAULT 'pdf',
  `next_run_at` datetime DEFAULT NULL,
  `last_run_at` datetime DEFAULT NULL,
  `last_status` varchar(30) NOT NULL DEFAULT '',
  `last_error` text DEFAULT NULL,
  `created_by_user_id` bigint(20) unsigned NOT NULL,
  `changed_by_user_id` bigint(20) unsigned NOT NULL,
  `created_at` datetime NOT NULL DEFAULT current_timestamp(),
  `changed_at` datetime NOT NULL DEFAULT current_timestamp() ON UPDATE current_timestamp(),
  PRIMARY KEY (`id`),
  UNIQUE KEY `report_schedule_report_unique` (`report_definition_id`),
  KEY `report_schedule_due` (`active`,`next_run_at`,`id`),
  CONSTRAINT `report_schedule_report_fk` FOREIGN KEY (`report_definition_id`) REFERENCES `report_definition` (`id`) ON DELETE CASCADE,
  CONSTRAINT `report_schedule_created_by_fk` FOREIGN KEY (`created_by_user_id`) REFERENCES `user_account` (`id`),
  CONSTRAINT `report_schedule_changed_by_fk` FOREIGN KEY (`changed_by_user_id`) REFERENCES `user_account` (`id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE IF NOT EXISTS `report_schedule_recipient` (
  `id` bigint(20) unsigned NOT NULL AUTO_INCREMENT,
  `report_schedule_id` bigint(20) unsigned NOT NULL,
  `recipient_type` varchar(20) NOT NULL,
  `user_account_id` bigint(20) unsigned DEFAULT NULL,
  `email` varchar(255) NOT NULL,
  `display_name` varchar(255) NOT NULL DEFAULT '',
  `created_at` datetime NOT NULL DEFAULT current_timestamp(),
  PRIMARY KEY (`id`),
  UNIQUE KEY `report_schedule_recipient_email_unique` (`report_schedule_id`,`email`),
  KEY `report_schedule_recipient_user` (`user_account_id`,`report_schedule_id`),
  CONSTRAINT `report_schedule_recipient_schedule_fk` FOREIGN KEY (`report_schedule_id`) REFERENCES `report_schedule` (`id`) ON DELETE CASCADE,
  CONSTRAINT `report_schedule_recipient_user_fk` FOREIGN KEY (`user_account_id`) REFERENCES `user_account` (`id`) ON DELETE SET NULL
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE IF NOT EXISTS `report_delivery_log` (
  `id` bigint(20) unsigned NOT NULL AUTO_INCREMENT,
  `report_schedule_id` bigint(20) unsigned DEFAULT NULL,
  `report_definition_id` bigint(20) unsigned DEFAULT NULL,
  `scheduled_for` datetime NOT NULL,
  `status` varchar(30) NOT NULL DEFAULT 'processing',
  `recipients_json` longtext NOT NULL,
  `formats` varchar(100) NOT NULL,
  `period_start` date DEFAULT NULL,
  `period_end` date DEFAULT NULL,
  `error_message` text DEFAULT NULL,
  `started_at` datetime NOT NULL DEFAULT current_timestamp(),
  `finished_at` datetime DEFAULT NULL,
  PRIMARY KEY (`id`),
  UNIQUE KEY `report_delivery_log_run_unique` (`report_schedule_id`,`scheduled_for`),
  KEY `report_delivery_log_report` (`report_definition_id`,`started_at`,`id`),
  KEY `report_delivery_log_status` (`status`,`started_at`,`id`),
  CONSTRAINT `report_delivery_log_schedule_fk` FOREIGN KEY (`report_schedule_id`) REFERENCES `report_schedule` (`id`) ON DELETE SET NULL,
  CONSTRAINT `report_delivery_log_report_fk` FOREIGN KEY (`report_definition_id`) REFERENCES `report_definition` (`id`) ON DELETE SET NULL
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

-- IMAP, SMTP and OAuth2 communication protocol
CREATE TABLE IF NOT EXISTS `communication_log` (
  `id` bigint(20) unsigned NOT NULL AUTO_INCREMENT,
  `trace_id` char(64) NOT NULL,
  `parent_id` bigint(20) unsigned DEFAULT NULL,
  `protocol` varchar(20) NOT NULL,
  `direction` varchar(20) NOT NULL,
  `operation` varchar(50) NOT NULL,
  `status` varchar(20) NOT NULL DEFAULT 'running',
  `account_type` varchar(20) DEFAULT NULL,
  `account_id` bigint(20) unsigned DEFAULT NULL,
  `account_name` varchar(190) DEFAULT NULL,
  `account_email` varchar(255) DEFAULT NULL,
  `server_host` varchar(255) DEFAULT NULL,
  `server_port` int(10) unsigned DEFAULT NULL,
  `connection_security` varchar(50) DEFAULT NULL,
  `ticket_id` bigint(20) unsigned DEFAULT NULL,
  `article_id` bigint(20) unsigned DEFAULT NULL,
  `message_id` varchar(500) DEFAULT NULL,
  `sender_email` varchar(500) DEFAULT NULL,
  `recipient_email` varchar(1000) DEFAULT NULL,
  `subject` varchar(500) DEFAULT NULL,
  `result_summary` text DEFAULT NULL,
  `error_message` text DEFAULT NULL,
  `messages_found` int(10) unsigned NOT NULL DEFAULT 0,
  `messages_processed` int(10) unsigned NOT NULL DEFAULT 0,
  `messages_created` int(10) unsigned NOT NULL DEFAULT 0,
  `messages_updated` int(10) unsigned NOT NULL DEFAULT 0,
  `messages_ignored` int(10) unsigned NOT NULL DEFAULT 0,
  `messages_failed` int(10) unsigned NOT NULL DEFAULT 0,
  `messages_sent` int(10) unsigned NOT NULL DEFAULT 0,
  `bytes_transferred` bigint(20) unsigned NOT NULL DEFAULT 0,
  `duration_ms` bigint(20) unsigned DEFAULT NULL,
  `started_at` datetime(6) NOT NULL DEFAULT current_timestamp(6),
  `finished_at` datetime(6) DEFAULT NULL,
  `created_at` datetime(6) NOT NULL DEFAULT current_timestamp(6),
  PRIMARY KEY (`id`),
  UNIQUE KEY `communication_log_trace_unique` (`trace_id`),
  KEY `communication_log_started_status` (`started_at`,`status`,`id`),
  KEY `communication_log_protocol_started` (`protocol`,`started_at`,`id`),
  KEY `communication_log_account_started` (`account_type`,`account_id`,`started_at`,`id`),
  KEY `communication_log_ticket` (`ticket_id`,`started_at`,`id`),
  KEY `communication_log_parent` (`parent_id`,`id`),
  CONSTRAINT `communication_log_parent_fk` FOREIGN KEY (`parent_id`) REFERENCES `communication_log` (`id`) ON DELETE SET NULL
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE IF NOT EXISTS `communication_log_step` (
  `id` bigint(20) unsigned NOT NULL AUTO_INCREMENT,
  `communication_log_id` bigint(20) unsigned NOT NULL,
  `level` varchar(20) NOT NULL DEFAULT 'info',
  `stage` varchar(50) NOT NULL DEFAULT 'processing',
  `message` varchar(2000) NOT NULL,
  `technical_details` longtext DEFAULT NULL,
  `created_at` datetime(6) NOT NULL DEFAULT current_timestamp(6),
  PRIMARY KEY (`id`),
  KEY `communication_log_step_log_created` (`communication_log_id`,`created_at`,`id`),
  CONSTRAINT `communication_log_step_log_fk` FOREIGN KEY (`communication_log_id`) REFERENCES `communication_log` (`id`) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- S/MIME identities, recipient certificates, policies and article status
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

-- Qisutu add-on packages, operations, settings and extension points
CREATE TABLE IF NOT EXISTS `addon_package` (
  `id` bigint(20) unsigned NOT NULL AUTO_INCREMENT,
  `package_identifier` varchar(190) NOT NULL,
  `name` varchar(255) NOT NULL,
  `vendor` varchar(255) NOT NULL DEFAULT '',
  `version` varchar(50) NOT NULL,
  `description` text DEFAULT NULL,
  `installed_path` varchar(500) NOT NULL,
  `manifest_json` longtext NOT NULL,
  `package_checksum_sha256` char(64) NOT NULL,
  `signature_status` varchar(30) NOT NULL DEFAULT 'unsigned',
  `active` tinyint(1) NOT NULL DEFAULT 0,
  `status` varchar(30) NOT NULL DEFAULT 'installed',
  `last_error` text DEFAULT NULL,
  `installed_by_user_id` bigint(20) unsigned NOT NULL DEFAULT 1,
  `changed_by_user_id` bigint(20) unsigned NOT NULL DEFAULT 1,
  `installed_at` datetime NOT NULL DEFAULT current_timestamp(),
  `changed_at` datetime NOT NULL DEFAULT current_timestamp() ON UPDATE current_timestamp(),
  PRIMARY KEY (`id`),
  UNIQUE KEY `addon_package_identifier_unique` (`package_identifier`),
  KEY `addon_package_active_status` (`active`,`status`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE IF NOT EXISTS `addon_operation` (
  `id` bigint(20) unsigned NOT NULL AUTO_INCREMENT,
  `package_identifier` varchar(190) NOT NULL DEFAULT '',
  `operation_type` varchar(30) NOT NULL,
  `package_filename` varchar(255) NOT NULL DEFAULT '',
  `package_data` longblob DEFAULT NULL,
  `package_checksum_sha256` char(64) NOT NULL DEFAULT '',
  `status` varchar(30) NOT NULL DEFAULT 'pending',
  `requested_by_user_id` bigint(20) unsigned NOT NULL DEFAULT 1,
  `locked_by` varchar(255) DEFAULT NULL,
  `locked_at` datetime DEFAULT NULL,
  `finished_at` datetime DEFAULT NULL,
  `result_message` text DEFAULT NULL,
  `error_message` text DEFAULT NULL,
  `created_at` datetime NOT NULL DEFAULT current_timestamp(),
  `changed_at` datetime NOT NULL DEFAULT current_timestamp() ON UPDATE current_timestamp(),
  PRIMARY KEY (`id`),
  KEY `addon_operation_claim` (`status`,`id`),
  KEY `addon_operation_package` (`package_identifier`,`id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE IF NOT EXISTS `addon_setting` (
  `id` bigint(20) unsigned NOT NULL AUTO_INCREMENT,
  `package_identifier` varchar(190) NOT NULL,
  `setting_key` varchar(190) NOT NULL,
  `setting_value` longtext DEFAULT NULL,
  `is_secret` tinyint(1) NOT NULL DEFAULT 0,
  `changed_by_user_id` bigint(20) unsigned NOT NULL DEFAULT 1,
  `created_at` datetime NOT NULL DEFAULT current_timestamp(),
  `changed_at` datetime NOT NULL DEFAULT current_timestamp() ON UPDATE current_timestamp(),
  PRIMARY KEY (`id`),
  UNIQUE KEY `addon_setting_package_key_unique` (`package_identifier`,`setting_key`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE IF NOT EXISTS `addon_migration` (
  `id` bigint(20) unsigned NOT NULL AUTO_INCREMENT,
  `package_identifier` varchar(190) NOT NULL,
  `migration_key` varchar(255) NOT NULL,
  `package_version` varchar(50) NOT NULL,
  `checksum_sha256` char(64) NOT NULL,
  `applied_at` datetime NOT NULL DEFAULT current_timestamp(),
  PRIMARY KEY (`id`),
  UNIQUE KEY `addon_migration_package_key_unique` (`package_identifier`,`migration_key`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE IF NOT EXISTS `addon_auth_state` (
  `id` bigint(20) unsigned NOT NULL AUTO_INCREMENT,
  `state_hash` char(64) NOT NULL,
  `provider_key` varchar(190) NOT NULL,
  `nonce_encrypted` text NOT NULL,
  `verifier_encrypted` text NOT NULL,
  `return_location` varchar(500) NOT NULL DEFAULT 'index.pl',
  `expires_at` datetime NOT NULL,
  `created_at` datetime NOT NULL DEFAULT current_timestamp(),
  PRIMARY KEY (`id`),
  UNIQUE KEY `addon_auth_state_hash_unique` (`state_hash`),
  KEY `addon_auth_state_expiry` (`expires_at`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE IF NOT EXISTS `addon_external_identity` (
  `id` bigint(20) unsigned NOT NULL AUTO_INCREMENT,
  `provider_key` varchar(190) NOT NULL,
  `external_subject` varchar(255) NOT NULL,
  `user_account_id` bigint(20) unsigned NOT NULL,
  `external_login` varchar(255) NOT NULL DEFAULT '',
  `last_login_at` datetime DEFAULT NULL,
  `created_at` datetime NOT NULL DEFAULT current_timestamp(),
  `changed_at` datetime NOT NULL DEFAULT current_timestamp() ON UPDATE current_timestamp(),
  PRIMARY KEY (`id`),
  UNIQUE KEY `addon_external_identity_subject_unique` (`provider_key`,`external_subject`),
  KEY `addon_external_identity_user` (`user_account_id`),
  CONSTRAINT `addon_external_identity_user_fk` FOREIGN KEY (`user_account_id`) REFERENCES `user_account` (`id`) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE IF NOT EXISTS `addon_task` (
  `id` bigint(20) unsigned NOT NULL AUTO_INCREMENT,
  `package_identifier` varchar(190) NOT NULL,
  `task_key` varchar(190) NOT NULL,
  `handler_class` varchar(255) NOT NULL,
  `interval_seconds` int(10) unsigned NOT NULL DEFAULT 3600,
  `active` tinyint(1) NOT NULL DEFAULT 1,
  `next_run_at` datetime NOT NULL DEFAULT current_timestamp(),
  `last_started_at` datetime DEFAULT NULL,
  `last_finished_at` datetime DEFAULT NULL,
  `last_status` varchar(30) NOT NULL DEFAULT 'never',
  `last_message` text DEFAULT NULL,
  `locked_by` varchar(255) DEFAULT NULL,
  `locked_until` datetime DEFAULT NULL,
  `created_at` datetime NOT NULL DEFAULT current_timestamp(),
  `changed_at` datetime NOT NULL DEFAULT current_timestamp() ON UPDATE current_timestamp(),
  PRIMARY KEY (`id`),
  UNIQUE KEY `addon_task_package_key_unique` (`package_identifier`,`task_key`),
  KEY `addon_task_due` (`active`,`next_run_at`,`locked_until`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE IF NOT EXISTS `addon_event_queue` (
  `id` bigint(20) unsigned NOT NULL AUTO_INCREMENT,
  `package_identifier` varchar(190) NOT NULL,
  `event_name` varchar(190) NOT NULL,
  `event_source` varchar(190) NOT NULL DEFAULT 'qisutu.core',
  `handler_class` varchar(255) NOT NULL,
  `handler_method` varchar(100) NOT NULL DEFAULT 'Handle',
  `payload_json` longtext NOT NULL,
  `result_json` longtext DEFAULT NULL,
  `status` varchar(30) NOT NULL DEFAULT 'pending',
  `attempts` int(10) unsigned NOT NULL DEFAULT 0,
  `available_at` datetime NOT NULL DEFAULT current_timestamp(),
  `locked_by` varchar(255) DEFAULT NULL,
  `locked_at` datetime DEFAULT NULL,
  `last_error` text DEFAULT NULL,
  `created_at` datetime NOT NULL DEFAULT current_timestamp(),
  `finished_at` datetime DEFAULT NULL,
  PRIMARY KEY (`id`),
  KEY `addon_event_queue_claim` (`status`,`available_at`,`id`),
  KEY `addon_event_queue_package` (`package_identifier`,`id`),
  KEY `addon_event_queue_event` (`event_name`,`created_at`),
  CONSTRAINT `addon_event_queue_package_fk` FOREIGN KEY (`package_identifier`) REFERENCES `addon_package` (`package_identifier`) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- Qisutu database migration history
CREATE TABLE IF NOT EXISTS `database_migration` (
  `id` bigint(20) unsigned NOT NULL AUTO_INCREMENT,
  `migration_key` varchar(255) NOT NULL,
  `database_version` varchar(50) NOT NULL,
  `checksum_sha256` char(64) NOT NULL,
  `execution_mode` varchar(20) NOT NULL DEFAULT 'executed',
  `applied_at` datetime NOT NULL DEFAULT current_timestamp(),
  PRIMARY KEY (`id`),
  UNIQUE KEY `database_migration_key_unique` (`migration_key`),
  KEY `database_migration_version_idx` (`database_version`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- Internal agent chat and live ticket presence
CREATE TABLE IF NOT EXISTS `internal_chat_message` (
  `id` bigint(20) unsigned NOT NULL AUTO_INCREMENT,
  `sender_user_id` bigint(20) unsigned NOT NULL,
  `recipient_user_id` bigint(20) unsigned NOT NULL,
  `message_type` varchar(30) NOT NULL DEFAULT 'message',
  `message_text` text NOT NULL,
  `ticket_id` bigint(20) unsigned DEFAULT NULL,
  `ticket_number` varchar(50) NOT NULL DEFAULT '',
  `ticket_title` varchar(500) NOT NULL DEFAULT '',
  `created_at` datetime NOT NULL DEFAULT current_timestamp(),
  `read_at` datetime DEFAULT NULL,
  PRIMARY KEY (`id`),
  KEY `internal_chat_sender_recipient_id` (`sender_user_id`,`recipient_user_id`,`id`),
  KEY `internal_chat_recipient_read_id` (`recipient_user_id`,`read_at`,`id`),
  KEY `internal_chat_ticket_id` (`ticket_id`,`id`),
  CONSTRAINT `internal_chat_sender_fk` FOREIGN KEY (`sender_user_id`) REFERENCES `user_account` (`id`) ON DELETE CASCADE,
  CONSTRAINT `internal_chat_recipient_fk` FOREIGN KEY (`recipient_user_id`) REFERENCES `user_account` (`id`) ON DELETE CASCADE,
  CONSTRAINT `internal_chat_ticket_fk` FOREIGN KEY (`ticket_id`) REFERENCES `ticket` (`id`) ON DELETE SET NULL
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE IF NOT EXISTS `ticket_presence` (
  `id` bigint(20) unsigned NOT NULL AUTO_INCREMENT,
  `ticket_id` bigint(20) unsigned NOT NULL,
  `user_account_id` bigint(20) unsigned NOT NULL,
  `client_id` varchar(64) NOT NULL,
  `created_at` datetime NOT NULL DEFAULT current_timestamp(),
  `last_seen_at` datetime NOT NULL DEFAULT current_timestamp(),
  PRIMARY KEY (`id`),
  UNIQUE KEY `ticket_presence_ticket_user_client_unique` (`ticket_id`,`user_account_id`,`client_id`),
  KEY `ticket_presence_ticket_seen` (`ticket_id`,`last_seen_at`),
  KEY `ticket_presence_user_seen` (`user_account_id`,`last_seen_at`),
  CONSTRAINT `ticket_presence_ticket_fk` FOREIGN KEY (`ticket_id`) REFERENCES `ticket` (`id`) ON DELETE CASCADE,
  CONSTRAINT `ticket_presence_user_fk` FOREIGN KEY (`user_account_id`) REFERENCES `user_account` (`id`) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- Qisutu schema version
CREATE TABLE IF NOT EXISTS `database_version` (
  `id` bigint(20) unsigned NOT NULL AUTO_INCREMENT,
  `version` varchar(50) NOT NULL,
  `installed_at` datetime NOT NULL DEFAULT current_timestamp(),
  PRIMARY KEY (`id`),
  UNIQUE KEY `database_version_version_unique` (`version`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

INSERT INTO `database_version` (`version`) VALUES ('2.0.1');

/*!40103 SET TIME_ZONE=@OLD_TIME_ZONE */;

/*!40101 SET SQL_MODE=@OLD_SQL_MODE */;
/*!40014 SET FOREIGN_KEY_CHECKS=@OLD_FOREIGN_KEY_CHECKS */;
/*!40014 SET UNIQUE_CHECKS=@OLD_UNIQUE_CHECKS */;
/*!40101 SET CHARACTER_SET_CLIENT=@OLD_CHARACTER_SET_CLIENT */;
/*!40101 SET CHARACTER_SET_RESULTS=@OLD_CHARACTER_SET_RESULTS */;
/*!40101 SET COLLATION_CONNECTION=@OLD_COLLATION_CONNECTION */;
/*!40111 SET SQL_NOTES=@OLD_SQL_NOTES */;

-- Dump completed on 2026-07-13  6:32:33
