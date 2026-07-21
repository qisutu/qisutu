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

DROP TRIGGER IF EXISTS `qisutu_automation_ticket_insert`;
DROP TRIGGER IF EXISTS `qisutu_automation_ticket_update`;
DROP TRIGGER IF EXISTS `qisutu_automation_article_insert`;
DROP TRIGGER IF EXISTS `qisutu_automation_dynamic_field_insert`;
DROP TRIGGER IF EXISTS `qisutu_automation_dynamic_field_update`;

DELIMITER ;;

CREATE TRIGGER `qisutu_automation_ticket_insert`
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
END;;

CREATE TRIGGER `qisutu_automation_ticket_update`
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
END;;

CREATE TRIGGER `qisutu_automation_article_insert`
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
END;;

CREATE TRIGGER `qisutu_automation_dynamic_field_insert`
AFTER INSERT ON `ticket_dynamic_field_value`
FOR EACH ROW
BEGIN
    INSERT INTO `automation_event` (`event_name`,`ticket_id`,`source_rule_id`,`source_job_id`,`depth`,`suppress_notifications`,`created_at`)
    VALUES ('dynamic_field_changed',NEW.`ticket_id`,NULLIF(@qisutu_automation_rule_id,0),NULLIF(@qisutu_automation_job_id,0),COALESCE(@qisutu_automation_depth,0)+1,COALESCE(@qisutu_suppress_notifications,0),NOW());
END;;

CREATE TRIGGER `qisutu_automation_dynamic_field_update`
AFTER UPDATE ON `ticket_dynamic_field_value`
FOR EACH ROW
BEGIN
    IF NOT (OLD.`value_text` <=> NEW.`value_text`) THEN
        INSERT INTO `automation_event` (`event_name`,`ticket_id`,`source_rule_id`,`source_job_id`,`depth`,`suppress_notifications`,`created_at`)
        VALUES ('dynamic_field_changed',NEW.`ticket_id`,NULLIF(@qisutu_automation_rule_id,0),NULLIF(@qisutu_automation_job_id,0),COALESCE(@qisutu_automation_depth,0)+1,COALESCE(@qisutu_suppress_notifications,0),NOW());
    END IF;
END;;

DELIMITER ;
