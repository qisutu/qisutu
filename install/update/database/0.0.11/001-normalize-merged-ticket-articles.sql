-- Qisutu - Open Source Ticket System
-- Copyright (C) 2026 Franziska Steps
-- Qisutu - Kim-KI, https://qisutu.de
--
-- SPDX-FileCopyrightText: 2026 Franziska Steps
-- SPDX-License-Identifier: AGPL-3.0-or-later

-- Releases up to database version 0.0.10 copied articles during a merge.
-- Keep the target copy, remove the duplicate source article, and move any
-- article that was added to the source after the merge into the target.

DROP TEMPORARY TABLE IF EXISTS `qisutu_merge_article_cleanup`;

CREATE TEMPORARY TABLE `qisutu_merge_article_cleanup` (
  `source_ticket_id` bigint(20) unsigned NOT NULL,
  `target_ticket_id` bigint(20) unsigned NOT NULL,
  `source_article_id` bigint(20) unsigned NOT NULL,
  `target_article_id` bigint(20) unsigned NOT NULL,
  PRIMARY KEY (`source_article_id`),
  KEY `qisutu_merge_cleanup_target` (`target_ticket_id`,`target_article_id`)
) ENGINE=InnoDB;

INSERT IGNORE INTO `qisutu_merge_article_cleanup` (
  `source_ticket_id`, `target_ticket_id`, `source_article_id`, `target_article_id`
)
SELECT
  o.`source_ticket_id`, o.`target_ticket_id`, o.`source_article_id`, o.`target_article_id`
FROM `ticket_article_origin` o
INNER JOIN `ticket_link` l ON l.`id` = o.`ticket_link_id`
WHERE o.`origin_type` = 'merge'
  AND l.`link_type` = 'merge'
  AND o.`source_article_id` <> o.`target_article_id`;

-- Time entries remain on the source shell but no longer point at a moved or
-- removed article.
DROP TRIGGER IF EXISTS `qisutu_time_accounting_immutable_update`;

UPDATE `ticket_time_accounting` ta
INNER JOIN `ticket_link` l
  ON l.`source_ticket_id` = ta.`ticket_id`
 AND l.`link_type` = 'merge'
SET ta.`ticket_article_id` = NULL
WHERE ta.`ticket_article_id` IS NOT NULL;

DELIMITER ;;
CREATE TRIGGER `qisutu_time_accounting_immutable_update`
BEFORE UPDATE ON `ticket_time_accounting`
FOR EACH ROW
BEGIN
    SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Time accounting entries are immutable; create a correction instead';
END;;
DELIMITER ;

-- The provenance row must continue to reference an existing article after
-- the old duplicate is removed.
UPDATE `ticket_article_origin` o
INNER JOIN `qisutu_merge_article_cleanup` m
  ON m.`source_ticket_id` = o.`source_ticket_id`
 AND m.`target_ticket_id` = o.`target_ticket_id`
 AND m.`source_article_id` = o.`source_article_id`
 AND m.`target_article_id` = o.`target_article_id`
SET o.`source_article_id` = o.`target_article_id`
WHERE o.`origin_type` = 'merge';

DELETE a
FROM `ticket_article_attachment` a
INNER JOIN `qisutu_merge_article_cleanup` m
  ON m.`source_ticket_id` = a.`ticket_id`
 AND m.`source_article_id` = a.`article_id`;

DELETE a
FROM `ticket_article` a
INNER JOIN `qisutu_merge_article_cleanup` m
  ON m.`source_ticket_id` = a.`ticket_id`
 AND m.`source_article_id` = a.`id`;

-- Preserve any article that was written into an already merged source by an
-- older release. These articles are moved now and receive merge provenance.
INSERT IGNORE INTO `ticket_article_origin` (
  `ticket_link_id`, `source_ticket_id`, `source_article_id`,
  `target_ticket_id`, `target_article_id`, `origin_type`,
  `created_by_user_id`, `created_at`
)
SELECT
  l.`id`, l.`source_ticket_id`, a.`id`,
  l.`target_ticket_id`, a.`id`, 'merge',
  l.`created_by_user_id`, l.`created_at`
FROM `ticket_link` l
INNER JOIN `ticket_article` a ON a.`ticket_id` = l.`source_ticket_id`
LEFT JOIN `ticket_article_origin` o ON o.`target_article_id` = a.`id`
WHERE l.`link_type` = 'merge'
  AND o.`id` IS NULL;

UPDATE `ticket_article_attachment` aa
INNER JOIN `ticket_article` a ON a.`id` = aa.`article_id`
INNER JOIN `ticket_link` l
  ON l.`source_ticket_id` = a.`ticket_id`
 AND l.`link_type` = 'merge'
SET aa.`ticket_id` = l.`target_ticket_id`;

UPDATE `ticket_article` a
INNER JOIN `ticket_link` l
  ON l.`source_ticket_id` = a.`ticket_id`
 AND l.`link_type` = 'merge'
LEFT JOIN (
  SELECT `ticket_id`, MAX(`article_number`) AS `max_article_number`
  FROM `ticket_article`
  GROUP BY `ticket_id`
) totals ON totals.`ticket_id` = l.`target_ticket_id`
SET
  a.`article_number` = COALESCE(totals.`max_article_number`, 0) + a.`article_number`,
  a.`ticket_id` = l.`target_ticket_id`;

UPDATE `ticket` source_ticket
INNER JOIN `ticket_link` l
  ON l.`source_ticket_id` = source_ticket.`id`
 AND l.`link_type` = 'merge'
SET
  source_ticket.`last_customer_article_at` = NULL,
  source_ticket.`last_agent_article_at` = NULL;

UPDATE `ticket` target_ticket
INNER JOIN (
  SELECT DISTINCT `target_ticket_id`
  FROM `ticket_link`
  WHERE `link_type` = 'merge'
) merged_target ON merged_target.`target_ticket_id` = target_ticket.`id`
SET
  target_ticket.`last_customer_article_at` = (
    SELECT MAX(a.`created_at`)
    FROM `ticket_article` a
    WHERE a.`ticket_id` = target_ticket.`id`
      AND a.`sender_type` = 'customer'
  ),
  target_ticket.`last_agent_article_at` = (
    SELECT MAX(a.`created_at`)
    FROM `ticket_article` a
    WHERE a.`ticket_id` = target_ticket.`id`
      AND a.`sender_type` = 'agent'
  );

DROP TEMPORARY TABLE IF EXISTS `qisutu_merge_article_cleanup`;
