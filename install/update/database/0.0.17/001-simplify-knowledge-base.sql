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

-- Vereinfachte FAQ-Logik: alle Agenten pflegen Kategorien und Artikel;
-- die Sichtbarkeit ist die einzige fachliche Freigabe.

UPDATE `knowledge_article`
SET `status` = 'published', `customer_scope` = 'all';

UPDATE `knowledge_article_revision`
SET `status` = 'published', `customer_scope` = 'all';

DELETE FROM `knowledge_article_customer`;
DELETE FROM `knowledge_article_queue`;

DELETE FROM `user_group_permission`
WHERE `permission_key` IN ('knowledge.view', 'knowledge.edit', 'knowledge.publish');

ALTER TABLE `knowledge_article`
MODIFY `status` varchar(20) NOT NULL DEFAULT 'published';
