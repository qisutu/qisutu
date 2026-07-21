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

-- Qisutu 0.0.25: separate LDAP profiles for agents and customer users/customers.

SET @qisutu_column_exists = (
  SELECT COUNT(*) FROM information_schema.COLUMNS
  WHERE TABLE_SCHEMA = DATABASE()
    AND TABLE_NAME = 'ldap_configuration'
    AND COLUMN_NAME = 'profile_type'
);
SET @qisutu_sql = IF(
  @qisutu_column_exists = 0,
  'ALTER TABLE `ldap_configuration` ADD COLUMN `profile_type` varchar(20) NOT NULL DEFAULT ''agent'' AFTER `id`',
  'SELECT 1'
);
PREPARE qisutu_stmt FROM @qisutu_sql;
EXECUTE qisutu_stmt;
DEALLOCATE PREPARE qisutu_stmt;

UPDATE `ldap_configuration`
SET `profile_type` = 'agent'
WHERE `profile_type` IS NULL OR `profile_type` = '';

SET @qisutu_column_exists = (
  SELECT COUNT(*) FROM information_schema.COLUMNS
  WHERE TABLE_SCHEMA = DATABASE()
    AND TABLE_NAME = 'ldap_configuration'
    AND COLUMN_NAME = 'customer_number_attribute'
);
SET @qisutu_sql = IF(
  @qisutu_column_exists = 0,
  'ALTER TABLE `ldap_configuration` ADD COLUMN `customer_number_attribute` varchar(100) NOT NULL DEFAULT '''' AFTER `email_attribute`',
  'SELECT 1'
);
PREPARE qisutu_stmt FROM @qisutu_sql;
EXECUTE qisutu_stmt;
DEALLOCATE PREPARE qisutu_stmt;

SET @qisutu_column_exists = (
  SELECT COUNT(*) FROM information_schema.COLUMNS
  WHERE TABLE_SCHEMA = DATABASE()
    AND TABLE_NAME = 'ldap_configuration'
    AND COLUMN_NAME = 'customer_name_attribute'
);
SET @qisutu_sql = IF(
  @qisutu_column_exists = 0,
  'ALTER TABLE `ldap_configuration` ADD COLUMN `customer_name_attribute` varchar(100) NOT NULL DEFAULT '''' AFTER `customer_number_attribute`',
  'SELECT 1'
);
PREPARE qisutu_stmt FROM @qisutu_sql;
EXECUTE qisutu_stmt;
DEALLOCATE PREPARE qisutu_stmt;

SET @qisutu_index_exists = (
  SELECT COUNT(*) FROM information_schema.STATISTICS
  WHERE TABLE_SCHEMA = DATABASE()
    AND TABLE_NAME = 'ldap_configuration'
    AND INDEX_NAME = 'ldap_configuration_profile_active'
);
SET @qisutu_sql = IF(
  @qisutu_index_exists = 0,
  'ALTER TABLE `ldap_configuration` ADD INDEX `ldap_configuration_profile_active` (`profile_type`,`active`,`id`)',
  'SELECT 1'
);
PREPARE qisutu_stmt FROM @qisutu_sql;
EXECUTE qisutu_stmt;
DEALLOCATE PREPARE qisutu_stmt;
