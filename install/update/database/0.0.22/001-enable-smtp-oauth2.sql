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

-- Qisutu 0.0.22: OAuth authorization states can target IMAP or SMTP accounts.
-- Existing records are IMAP states and retain that meaning.
--
-- The schema synchronizer runs before cumulative migrations and may already
-- have added the new column. Every step is therefore conditional. This also
-- repairs an update that stopped after one of the earlier ALTER statements.

SET @qisutu_fk_exists = (
  SELECT COUNT(*)
  FROM information_schema.TABLE_CONSTRAINTS
  WHERE CONSTRAINT_SCHEMA = DATABASE()
    AND TABLE_NAME = 'oauth2_authorization_state'
    AND CONSTRAINT_NAME = 'oauth2_authorization_state_account_fk'
    AND CONSTRAINT_TYPE = 'FOREIGN KEY'
);
SET @qisutu_sql = IF(
  @qisutu_fk_exists > 0,
  'ALTER TABLE `oauth2_authorization_state` DROP FOREIGN KEY `oauth2_authorization_state_account_fk`',
  'SELECT 1'
);
PREPARE qisutu_stmt FROM @qisutu_sql;
EXECUTE qisutu_stmt;
DEALLOCATE PREPARE qisutu_stmt;

SET @qisutu_column_exists = (
  SELECT COUNT(*)
  FROM information_schema.COLUMNS
  WHERE TABLE_SCHEMA = DATABASE()
    AND TABLE_NAME = 'oauth2_authorization_state'
    AND COLUMN_NAME = 'account_type'
);
SET @qisutu_sql = IF(
  @qisutu_column_exists = 0,
  'ALTER TABLE `oauth2_authorization_state` ADD COLUMN `account_type` varchar(20) NOT NULL DEFAULT ''imap'' AFTER `state_hash`',
  'SELECT 1'
);
PREPARE qisutu_stmt FROM @qisutu_sql;
EXECUTE qisutu_stmt;
DEALLOCATE PREPARE qisutu_stmt;

SET @qisutu_index_columns = (
  SELECT GROUP_CONCAT(COLUMN_NAME ORDER BY SEQ_IN_INDEX SEPARATOR ',')
  FROM information_schema.STATISTICS
  WHERE TABLE_SCHEMA = DATABASE()
    AND TABLE_NAME = 'oauth2_authorization_state'
    AND INDEX_NAME = 'oauth2_authorization_state_account_user'
);
SET @qisutu_sql = IF(
  @qisutu_index_columns IS NOT NULL
    AND @qisutu_index_columns <> 'account_type,account_id,user_account_id',
  'ALTER TABLE `oauth2_authorization_state` DROP INDEX `oauth2_authorization_state_account_user`',
  'SELECT 1'
);
PREPARE qisutu_stmt FROM @qisutu_sql;
EXECUTE qisutu_stmt;
DEALLOCATE PREPARE qisutu_stmt;

SET @qisutu_index_exists = (
  SELECT COUNT(DISTINCT INDEX_NAME)
  FROM information_schema.STATISTICS
  WHERE TABLE_SCHEMA = DATABASE()
    AND TABLE_NAME = 'oauth2_authorization_state'
    AND INDEX_NAME = 'oauth2_authorization_state_account_user'
);
SET @qisutu_sql = IF(
  @qisutu_index_exists = 0,
  'ALTER TABLE `oauth2_authorization_state` ADD KEY `oauth2_authorization_state_account_user` (`account_type`,`account_id`,`user_account_id`)',
  'SELECT 1'
);
PREPARE qisutu_stmt FROM @qisutu_sql;
EXECUTE qisutu_stmt;
DEALLOCATE PREPARE qisutu_stmt;
