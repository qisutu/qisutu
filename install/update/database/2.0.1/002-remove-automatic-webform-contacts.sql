-- Qisutu - Copyright (C) 2026 Franziska Steps
-- SPDX-License-Identifier: AGPL-3.0-or-later
-- Remove only inactive, never-password-initialized accounts carrying the
-- exact marker written by the former public-form contact creation code.
-- The normal updater runs this with the application and daemon stopped.
SET @qisutu_suppress_notifications = 1;
SET @qisutu_history_source = 'webform_cleanup';
SET @qisutu_history_actor_type = 'system';
SET @qisutu_history_actor_name = 'Qisutu';

START TRANSACTION;

CREATE TEMPORARY TABLE qisutu_webform_cleanup_customers (
    id BIGINT UNSIGNED NOT NULL PRIMARY KEY
);
INSERT INTO qisutu_webform_cleanup_customers (id)
SELECT id FROM customer
WHERE customer_number = 'QISUTU-WEBFORM'
  AND name = 'Web form contacts'
  AND created_by_user_id = 1;

CREATE TEMPORARY TABLE qisutu_webform_cleanup_contacts (
    user_account_id BIGINT UNSIGNED NOT NULL PRIMARY KEY,
    customer_user_id BIGINT UNSIGNED NOT NULL,
    customer_id BIGINT UNSIGNED NOT NULL
);
INSERT INTO qisutu_webform_cleanup_contacts (user_account_id, customer_user_id, customer_id)
SELECT ua.id, cu.id, cu.customer_id
FROM user_account ua
INNER JOIN customer_user cu ON cu.user_account_id = ua.id
INNER JOIN qisutu_webform_cleanup_customers c ON c.id = cu.customer_id
WHERE ua.account_type = 'customer'
  AND ua.is_active = 0
  AND ua.is_system_user = 0
  AND ua.password_changed_at IS NULL
  AND ua.password_hash REGEXP '^QISUTU_WEBFORM_CONTACT_[a-f0-9]{64}$'
  AND cu.created_by_user_id = 1
  AND NOT EXISTS (
      SELECT 1 FROM customer_user other_contact
      WHERE other_contact.user_account_id = ua.id AND other_contact.id <> cu.id
  )
  AND NOT EXISTS (
      SELECT 1 FROM cmdb_ci ci WHERE ci.customer_user_id = cu.id
  );

-- Remember the affected tickets and their existing automation events. The
-- cleanup must not schedule business rules when the daemon starts again.
CREATE TEMPORARY TABLE qisutu_webform_cleanup_tickets (
    id BIGINT UNSIGNED NOT NULL PRIMARY KEY,
    previous_event_id BIGINT UNSIGNED NOT NULL
);
INSERT INTO qisutu_webform_cleanup_tickets (id, previous_event_id)
SELECT DISTINCT t.id, COALESCE((SELECT MAX(id) FROM automation_event), 0)
FROM ticket t
LEFT JOIN qisutu_webform_cleanup_contacts contact
  ON contact.customer_user_id = t.customer_user_id
  OR contact.user_account_id = t.created_by_user_id
  OR contact.user_account_id = t.changed_by_user_id
LEFT JOIN qisutu_webform_cleanup_customers container ON container.id = t.customer_id
WHERE contact.user_account_id IS NOT NULL
   OR (container.id IS NOT NULL AND t.customer_user_id IS NULL AND EXISTS (
       SELECT 1 FROM ticket_form_submission submission
       WHERE submission.ticket_id = t.id AND submission.source = 'webform'
   ));

-- Detach the synthetic contact, without changing ticket contents or timestamps.
UPDATE ticket
SET customer_user_id = NULL, changed_by_user_id = 1, changed_at = changed_at
WHERE customer_user_id IN (
    SELECT customer_user_id FROM qisutu_webform_cleanup_contacts
);

-- This also covers public submissions whose e-mail already belonged to a
-- real account: the former implementation assigned only the synthetic customer.
UPDATE ticket
SET customer_id = NULL, changed_by_user_id = 1, changed_at = changed_at
WHERE customer_id IN (SELECT id FROM qisutu_webform_cleanup_customers)
  AND customer_user_id IS NULL
  AND EXISTS (
      SELECT 1 FROM ticket_form_submission submission
      WHERE submission.ticket_id = ticket.id AND submission.source = 'webform'
  );

-- These IDs were technical authors of the public submission, not logins.
-- Keep their articles, dynamic values and automatically generated checklists.
UPDATE ticket SET created_by_user_id = 1, changed_at = changed_at
WHERE created_by_user_id IN (SELECT user_account_id FROM qisutu_webform_cleanup_contacts);
UPDATE ticket SET changed_by_user_id = 1, changed_at = changed_at
WHERE changed_by_user_id IN (SELECT user_account_id FROM qisutu_webform_cleanup_contacts);
UPDATE ticket_article SET created_by_user_id = 1
WHERE created_by_user_id IN (SELECT user_account_id FROM qisutu_webform_cleanup_contacts);
UPDATE ticket_article SET changed_by_user_id = 1
WHERE changed_by_user_id IN (SELECT user_account_id FROM qisutu_webform_cleanup_contacts);
UPDATE ticket_dynamic_field_value SET created_by_user_id = 1, changed_at = changed_at
WHERE created_by_user_id IN (SELECT user_account_id FROM qisutu_webform_cleanup_contacts);
UPDATE ticket_dynamic_field_value SET changed_by_user_id = 1, changed_at = changed_at
WHERE changed_by_user_id IN (SELECT user_account_id FROM qisutu_webform_cleanup_contacts);
UPDATE ticket_checklist SET created_by_user_id = 1
WHERE created_by_user_id IN (SELECT user_account_id FROM qisutu_webform_cleanup_contacts);
UPDATE ticket_checklist SET changed_by_user_id = 1
WHERE changed_by_user_id IN (SELECT user_account_id FROM qisutu_webform_cleanup_contacts);
UPDATE ticket_checklist SET removed_by_user_id = 1
WHERE removed_by_user_id IN (SELECT user_account_id FROM qisutu_webform_cleanup_contacts);
UPDATE ticket_checklist_item SET created_by_user_id = 1
WHERE created_by_user_id IN (SELECT user_account_id FROM qisutu_webform_cleanup_contacts);
UPDATE ticket_checklist_item SET changed_by_user_id = 1
WHERE changed_by_user_id IN (SELECT user_account_id FROM qisutu_webform_cleanup_contacts);
UPDATE ticket_checklist_item SET completed_by_user_id = 1
WHERE completed_by_user_id IN (SELECT user_account_id FROM qisutu_webform_cleanup_contacts);
UPDATE ticket_checklist_audit SET created_by_user_id = 1
WHERE created_by_user_id IN (SELECT user_account_id FROM qisutu_webform_cleanup_contacts);

DELETE FROM customer_user
WHERE id IN (SELECT customer_user_id FROM qisutu_webform_cleanup_contacts);
DELETE FROM user_account
WHERE id IN (SELECT user_account_id FROM qisutu_webform_cleanup_contacts);

-- Delete an unused synthetic customer only. Any explicitly configured service,
-- form, checklist, knowledge-base or CMDB relationship keeps that customer.
DELETE FROM customer
WHERE id IN (SELECT id FROM qisutu_webform_cleanup_customers)
  AND NOT EXISTS (SELECT 1 FROM customer_user cu WHERE cu.customer_id = customer.id)
  AND NOT EXISTS (SELECT 1 FROM ticket t WHERE t.customer_id = customer.id)
  AND NOT EXISTS (SELECT 1 FROM customer_service s WHERE s.customer_id = customer.id)
  AND NOT EXISTS (SELECT 1 FROM checklist_template_customer c WHERE c.customer_id = customer.id)
  AND NOT EXISTS (SELECT 1 FROM ticket_form_customer f WHERE f.customer_id = customer.id)
  AND NOT EXISTS (SELECT 1 FROM knowledge_article_customer a WHERE a.customer_id = customer.id)
  AND NOT EXISTS (SELECT 1 FROM cmdb_ci ci WHERE ci.customer_id = customer.id);

-- Retain the migration events as processed records. Existing pending events
-- remain untouched; only events generated above are excluded from rule jobs.
UPDATE automation_event
SET processed_at = NOW()
WHERE processed_at IS NULL AND event_name = 'ticket_changed'
  AND suppress_notifications = 1
  AND source_rule_id IS NULL AND source_job_id IS NULL
  AND EXISTS (
      SELECT 1 FROM qisutu_webform_cleanup_tickets changed_ticket
      WHERE changed_ticket.id = automation_event.ticket_id
        AND automation_event.id > changed_ticket.previous_event_id
  );

COMMIT;
DROP TEMPORARY TABLE qisutu_webform_cleanup_tickets;
DROP TEMPORARY TABLE qisutu_webform_cleanup_contacts;
DROP TEMPORARY TABLE qisutu_webform_cleanup_customers;
