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

INSERT INTO system_setting (setting_key, setting_value, created_by_user_id, changed_by_user_id)
SELECT CONCAT('knowledge.suggestions.', defaults.setting_key),
    CASE
        WHEN defaults.setting_key = 'enabled' AND p.active = 0 THEN '0'
        WHEN defaults.setting_key = 'enabled' AND s.setting_value IN ('0', '1') THEN s.setting_value
        WHEN defaults.setting_key = 'max_results' AND s.setting_value REGEXP '^([1-9]|10)$' THEN s.setting_value
        WHEN defaults.setting_key = 'minimum_length' AND s.setting_value REGEXP '^([2-9]|10)$' THEN s.setting_value
        ELSE defaults.default_value
    END, 1, 1
FROM addon_package p
CROSS JOIN (
    SELECT 'enabled' AS setting_key, '1' AS default_value
    UNION ALL SELECT 'max_results', '3'
    UNION ALL SELECT 'minimum_length', '3'
) defaults
LEFT JOIN addon_setting s ON s.package_identifier = p.package_identifier AND s.setting_key = defaults.setting_key
WHERE p.package_identifier = 'de.qisutu.knowledge-suggestions' AND p.status = 'installed'
    AND NOT EXISTS (
        SELECT 1 FROM system_setting native
        WHERE native.setting_key = CONCAT('knowledge.suggestions.', defaults.setting_key)
    );
