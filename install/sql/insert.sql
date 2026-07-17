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

SET NAMES utf8mb4;

START TRANSACTION;

INSERT INTO `user_account` (
    `id`,
    `login`,
    `account_type`,
    `email`,
    `password_hash`,
    `firstname`,
    `lastname`,
    `is_active`,
    `is_system_user`,
    `password_changed_at`
) VALUES (
    1,
    'admin',
    'agent',
    'admin@localhost.invalid',
    'QISUTU_ADMIN_PASSWORD_NOT_SET',
    'Qisutu',
    'Administrator',
    1,
    0,
    NOW()
);

INSERT INTO `user_group` (
    `id`,
    `name`,
    `title`,
    `group_type`,
    `active`,
    `sort_order`,
    `created_by_user_id`,
    `changed_by_user_id`
) VALUES (
    1,
    'admin',
    'Administrators',
    'agent',
    1,
    100,
    1,
    1
);

INSERT INTO `user_group_member` (
    `user_group_id`,
    `user_account_id`,
    `role_name`,
    `active`,
    `created_by_user_id`,
    `changed_by_user_id`,
    `permission_read`,
    `permission_create`,
    `permission_change`,
    `permission_overview`,
    `permission_full`
) VALUES (
    1,
    1,
    'admin',
    1,
    1,
    1,
    1,
    1,
    1,
    1,
    1
);

INSERT INTO `user_group_permission` (
    `user_group_id`,
    `permission_key`,
    `active`,
    `created_by_user_id`,
    `changed_by_user_id`
) VALUES (
    1,
    'admin.view',
    1,
    1,
    1
);

INSERT INTO `ticket_queue` (
    `id`,
    `name`,
    `full_name`,
    `follow_up_allowed`,
    `active`,
    `sort_order`,
    `created_by_user_id`,
    `changed_by_user_id`
) VALUES
    (1, 'Posteingang', 'Posteingang', 1, 1, 100, 1, 1),
    (2, 'Junk',        'Junk',        1, 1, 200, 1, 1),
    (3, 'Spam',        'Spam',        1, 1, 300, 1, 1);

INSERT INTO `ticket_queue_group` (
    `queue_id`,
    `user_group_id`,
    `permission_key`,
    `active`,
    `created_by_user_id`,
    `changed_by_user_id`
) VALUES
    (1, 1, 'ticket.full', 1, 1, 1),
    (2, 1, 'ticket.full', 1, 1, 1),
    (3, 1, 'ticket.full', 1, 1, 1);

INSERT INTO `ticket_state` (
    `id`,
    `name`,
    `state_type`,
    `sla_pause`,
    `active`,
    `sort_order`,
    `created_by_user_id`,
    `changed_by_user_id`
) VALUES
    (1, 'new',                 'new',     0, 1, 100, 1, 1),
    (2, 'open',                'open',    0, 1, 200, 1, 1),
    (3, 'closed successful',   'closed',  0, 1, 300, 1, 1),
    (4, 'closed unsuccessful', 'closed',  0, 1, 400, 1, 1),
    (5, 'pending reminder',    'pending', 0, 1, 500, 1, 1),
    (6, 'merged',              'closed',  0, 1, 600, 1, 1),
    (7, 'pending auto close+', 'pending', 0, 1, 700, 1, 1),
    (8, 'pending auto close-', 'pending', 0, 1, 800, 1, 1);

INSERT INTO `ticket_priority` (
    `id`,
    `name`,
    `priority_value`,
    `active`,
    `sort_order`,
    `created_by_user_id`,
    `changed_by_user_id`
) VALUES
    (1, '1 very low',  1, 1, 100, 1, 1),
    (2, '2 low',       2, 1, 200, 1, 1),
    (3, '3 normal',    3, 1, 300, 1, 1),
    (4, '4 high',      4, 1, 400, 1, 1),
    (5, '5 very high', 5, 1, 500, 1, 1);

INSERT INTO `ticket` (
    `id`,
    `ticket_number`,
    `title`,
    `queue_id`,
    `state_id`,
    `priority_id`,
    `owner_user_id`,
    `responsible_user_id`,
    `created_by_user_id`,
    `changed_by_user_id`,
    `last_agent_article_at`
) VALUES (
    1,
    CONCAT(DATE_FORMAT(CURRENT_DATE(), '%Y%m%d'), '0001'),
    'Willkommen bei Qisutu',
    1,
    1,
    3,
    1,
    1,
    1,
    1,
    NOW()
);

INSERT INTO `ticket_article` (
    `ticket_id`,
    `article_number`,
    `channel`,
    `sender_type`,
    `from_name`,
    `from_email`,
    `subject`,
    `body`,
    `search_text`,
    `content_type`,
    `visibility`,
    `internal`,
    `created_by_user_id`,
    `changed_by_user_id`,
    `created_at`,
    `changed_at`
) VALUES (
    1,
    1,
    'note',
    'agent',
    'Qisutu',
    'support@qisutu.de',
    'Willkommen bei Qisutu',
    '<p>Willkommen bei Qisutu.</p><p>Die Installation wurde erfolgreich abgeschlossen. Als Nächstes kannst du Queues, Benutzer, E-Mail-Konten, Services, SLAs und weitere Systemeinstellungen einrichten.</p><p>Wir wünschen dir viel Erfolg mit Qisutu.</p>',
    'Willkommen bei Qisutu Installation erfolgreich',
    'text/html',
    'agent',
    1,
    1,
    1,
    NOW(),
    NOW()
);

COMMIT;
