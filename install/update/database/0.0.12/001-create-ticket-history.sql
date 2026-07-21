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
