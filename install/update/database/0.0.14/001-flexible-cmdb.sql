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

-- Existing installations keep every used type and relation. The former
-- starter records are removed only when they are completely unused.

UPDATE `cmdb_ci_type`
SET `type_key` = CONCAT('legacy_type_', `id`)
WHERE `type_key` IS NULL OR TRIM(`type_key`) = '';

INSERT IGNORE INTO `cmdb_status`
(`status_key`,`label`,`status_class`,`color`,`active`,`sort_order`,`created_by_user_id`,`changed_by_user_id`)
SELECT DISTINCT
  ci.`status`,
  ci.`status`,
  CASE
    WHEN ci.`status` IN ('retired','disposed') THEN 'retired'
    WHEN ci.`status` IN ('stock','repair','maintenance') THEN 'inactive'
    ELSE 'active'
  END,
  '#4b6478',1,1000,1,1
FROM `cmdb_ci` ci
WHERE TRIM(COALESCE(ci.`status`,'')) <> '';

INSERT IGNORE INTO `cmdb_ci_type_status` (`type_id`,`status_id`,`is_default`,`sort_order`)
SELECT DISTINCT ci.`type_id`, s.`id`, 0, s.`sort_order`
FROM `cmdb_ci` ci
INNER JOIN `cmdb_status` s ON s.`status_key` = ci.`status`
WHERE TRIM(COALESCE(ci.`status`,'')) <> '';

-- Former fixed attributes become ordinary, type-specific fields. Values are
-- copied without changing the immutable CI history.
INSERT IGNORE INTO `cmdb_ci_field`
(`type_id`,`group_id`,`field_key`,`label`,`field_type`,`is_required`,`is_searchable`,`is_unique`,`customer_visible`,`default_value`,`active`,`sort_order`,`created_by_user_id`,`changed_by_user_id`)
SELECT t.`id`,NULL,'description','Beschreibung','textarea',0,1,0,0,NULL,1,100,1,1
FROM `cmdb_ci_type` t
WHERE EXISTS (SELECT 1 FROM `cmdb_ci` ci WHERE ci.`type_id`=t.`id` AND TRIM(COALESCE(ci.`description`,''))<>'');

INSERT IGNORE INTO `cmdb_ci_field`
(`type_id`,`group_id`,`field_key`,`label`,`field_type`,`is_required`,`is_searchable`,`is_unique`,`customer_visible`,`default_value`,`active`,`sort_order`,`created_by_user_id`,`changed_by_user_id`)
SELECT t.`id`,NULL,'inventory_number','Inventarnummer','text',0,1,0,0,NULL,1,200,1,1
FROM `cmdb_ci_type` t
WHERE EXISTS (SELECT 1 FROM `cmdb_ci` ci WHERE ci.`type_id`=t.`id` AND TRIM(COALESCE(ci.`inventory_number`,''))<>'');

INSERT IGNORE INTO `cmdb_ci_field`
(`type_id`,`group_id`,`field_key`,`label`,`field_type`,`is_required`,`is_searchable`,`is_unique`,`customer_visible`,`default_value`,`active`,`sort_order`,`created_by_user_id`,`changed_by_user_id`)
SELECT t.`id`,NULL,'serial_number','Seriennummer','text',0,1,0,0,NULL,1,300,1,1
FROM `cmdb_ci_type` t
WHERE EXISTS (SELECT 1 FROM `cmdb_ci` ci WHERE ci.`type_id`=t.`id` AND TRIM(COALESCE(ci.`serial_number`,''))<>'');

INSERT IGNORE INTO `cmdb_ci_field`
(`type_id`,`group_id`,`field_key`,`label`,`field_type`,`is_required`,`is_searchable`,`is_unique`,`customer_visible`,`default_value`,`active`,`sort_order`,`created_by_user_id`,`changed_by_user_id`)
SELECT t.`id`,NULL,'location','Standort','text',0,1,0,0,NULL,1,400,1,1
FROM `cmdb_ci_type` t
WHERE EXISTS (SELECT 1 FROM `cmdb_ci` ci WHERE ci.`type_id`=t.`id` AND TRIM(COALESCE(ci.`location`,''))<>'');

INSERT IGNORE INTO `cmdb_ci_value`
(`ci_id`,`field_id`,`value_text`,`created_by_user_id`,`changed_by_user_id`,`created_at`,`changed_at`)
SELECT ci.`id`,f.`id`,ci.`description`,ci.`created_by_user_id`,ci.`changed_by_user_id`,ci.`created_at`,ci.`changed_at`
FROM `cmdb_ci` ci INNER JOIN `cmdb_ci_field` f ON f.`type_id`=ci.`type_id` AND f.`field_key`='description'
WHERE TRIM(COALESCE(ci.`description`,''))<>'';

INSERT IGNORE INTO `cmdb_ci_value`
(`ci_id`,`field_id`,`value_text`,`created_by_user_id`,`changed_by_user_id`,`created_at`,`changed_at`)
SELECT ci.`id`,f.`id`,ci.`inventory_number`,ci.`created_by_user_id`,ci.`changed_by_user_id`,ci.`created_at`,ci.`changed_at`
FROM `cmdb_ci` ci INNER JOIN `cmdb_ci_field` f ON f.`type_id`=ci.`type_id` AND f.`field_key`='inventory_number'
WHERE TRIM(COALESCE(ci.`inventory_number`,''))<>'';

INSERT IGNORE INTO `cmdb_ci_value`
(`ci_id`,`field_id`,`value_text`,`created_by_user_id`,`changed_by_user_id`,`created_at`,`changed_at`)
SELECT ci.`id`,f.`id`,ci.`serial_number`,ci.`created_by_user_id`,ci.`changed_by_user_id`,ci.`created_at`,ci.`changed_at`
FROM `cmdb_ci` ci INNER JOIN `cmdb_ci_field` f ON f.`type_id`=ci.`type_id` AND f.`field_key`='serial_number'
WHERE TRIM(COALESCE(ci.`serial_number`,''))<>'';

INSERT IGNORE INTO `cmdb_ci_value`
(`ci_id`,`field_id`,`value_text`,`created_by_user_id`,`changed_by_user_id`,`created_at`,`changed_at`)
SELECT ci.`id`,f.`id`,ci.`location`,ci.`created_by_user_id`,ci.`changed_by_user_id`,ci.`created_at`,ci.`changed_at`
FROM `cmdb_ci` ci INNER JOIN `cmdb_ci_field` f ON f.`type_id`=ci.`type_id` AND f.`field_key`='location'
WHERE TRIM(COALESCE(ci.`location`,''))<>'';

DELETE t
FROM `cmdb_ci_type` t
WHERE t.`id` BETWEEN 1 AND 12
  AND t.`name` IN ('Arbeitsplatz','Notebook','Server','Drucker','Netzwerkgerät','Mobilgerät','Software','Anwendung','IT-Service','Lizenz','Vertrag','Standort')
  AND NOT EXISTS (SELECT 1 FROM `cmdb_ci` ci WHERE ci.`type_id`=t.`id`)
  AND NOT EXISTS (SELECT 1 FROM `cmdb_ci_field` f WHERE f.`type_id`=t.`id`);

DELETE rt
FROM `cmdb_relation_type` rt
WHERE rt.`id` BETWEEN 1 AND 7
  AND rt.`name` IN ('depends_on','runs_on','connected_to','part_of','located_at','licensed_by','covered_by')
  AND NOT EXISTS (SELECT 1 FROM `cmdb_ci_relation` r WHERE r.`relation_type_id`=rt.`id`);

