# Qisutu - Open Source Ticket System
# Copyright (C) 2026 Franziska Steps
# Qisutu - Kim-KI, https://qisutu.de
#
# This file is part of Qisutu.
#
# Qisutu is free software: you can redistribute it and/or modify
# it under the terms of the GNU Affero General Public License as published by
# the Free Software Foundation, either version 3 of the License, or
# (at your option) any later version.
#
# Qisutu is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the
# GNU Affero General Public License for more details.
#
# You should have received a copy of the GNU Affero General Public License
# along with Qisutu. If not, see <https://www.gnu.org/licenses/>.
#
# SPDX-FileCopyrightText: 2026 Franziska Steps
# SPDX-License-Identifier: AGPL-3.0-or-later

[
    {
        Key => 'knowledge.suggestions.enabled', Module => 'Translate:KnowledgeBaseNavigation', Group => 'Translate:KnowledgeSuggestionsNavigation',
        Name => 'Translate:KnowledgeSuggestionsEnabled',
        Description => 'Translate:KnowledgeSuggestionsEnabledHint',
        Type => 'boolean', Default => 1, Minimum => 0, Maximum => 1,
        Active => 1,
    },
    {
        Key => 'knowledge.suggestions.max_results', Module => 'Translate:KnowledgeBaseNavigation', Group => 'Translate:KnowledgeSuggestionsNavigation',
        Name => 'Translate:KnowledgeSuggestionsMaxResults',
        Description => 'Translate:KnowledgeSuggestionsMaxResultsHint',
        Type => 'integer', Default => 3, Minimum => 1, Maximum => 10,
        Active => 1,
    },
    {
        Key => 'knowledge.suggestions.minimum_length', Module => 'Translate:KnowledgeBaseNavigation', Group => 'Translate:KnowledgeSuggestionsNavigation',
        Name => 'Translate:KnowledgeSuggestionsMinimumLength',
        Description => 'Translate:KnowledgeSuggestionsMinimumLengthHint',
        Type => 'integer', Default => 3, Minimum => 2, Maximum => 10,
        Active => 1,
    },
]
