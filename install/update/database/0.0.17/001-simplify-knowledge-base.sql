-- Qisutu - Open Source Ticket System
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
