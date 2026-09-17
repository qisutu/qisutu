-- Qisutu - Copyright (C) 2026 Franziska Steps
-- SPDX-License-Identifier: AGPL-3.0-or-later
-- Contact names live in user_account. Correct the history trigger before
-- removing the automatically assigned web-form contacts from existing tickets.
DROP TRIGGER IF EXISTS `qisutu_history_ticket_update`;
DELIMITER ;;
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
      VALUES (NEW.`id`,'customer_user_changed','change','customer_user_id',OLD.`customer_user_id`,NEW.`customer_user_id`,(SELECT COALESCE(NULLIF(TRIM(CONCAT(ua.`firstname`,' ',ua.`lastname`)),''),ua.`login`,ua.`email`) FROM `customer_user` cu INNER JOIN `user_account` ua ON ua.`id`=cu.`user_account_id` WHERE cu.`id`=OLD.`customer_user_id` LIMIT 1),(SELECT COALESCE(NULLIF(TRIM(CONCAT(ua.`firstname`,' ',ua.`lastname`)),''),ua.`login`,ua.`email`) FROM `customer_user` cu INNER JOIN `user_account` ua ON ua.`id`=cu.`user_account_id` WHERE cu.`id`=NEW.`customer_user_id` LIMIT 1),'ticket',NEW.`id`,NEW.`changed_by_user_id`,v_actor_type,v_actor_name,v_source,NOW());
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
DELIMITER ;
