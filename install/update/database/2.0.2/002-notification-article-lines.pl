#!/usr/bin/env perl

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

use strict;
use warnings;
use utf8;
use QisutuConfig;
use QisutuDB;

my $Config = QisutuConfig->Load();
my $DB = QisutuDB->new( Config => $Config );
$DB->Connect() || die "Agent notification migration: database connection failed\n";
my $Rows = $DB->SelectAll('SELECT id, subject, body_html FROM agent_notification_template');
die "Agent notification migration: templates could not be loaded\n" if !defined $Rows;
for my $Row (@{$Rows}) {
    my $Subject = $Row->{subject} // '';
    my $Body = $Row->{body_html} // '';
    # Correct templates saved using the briefly introduced suffix notation.
    $Subject =~ s{\{\{\s*Ticket[.]ArticleBody(\d{1,4})\s*\}\}}{'{{Ticket.ArticleBody[' . $1 . ']}}'}ge;
    $Body =~ s{\{\{\s*Ticket[.]ArticleBody(\d{1,4})\s*\}\}}{'{{Ticket.ArticleBody[' . $1 . ']}}'}ge;
    # Set the requested default without changing explicitly configured limits.
    $Body =~ s{\{\{\s*Ticket[.]ArticleBody\s*\}\}}{'{{Ticket.ArticleBody[15]}}'}ge;
    next if $Body eq ($Row->{body_html} // '') && $Subject eq ($Row->{subject} // '');
    $DB->Do(
        'UPDATE agent_notification_template SET subject = ?, body_html = ?
         WHERE id = ? AND BINARY subject = BINARY ? AND BINARY body_html = BINARY ?',
        $Subject, $Body, $Row->{id}, $Row->{subject}, $Row->{body_html},
    ) || die "Agent notification migration: template update failed\n";
}
$DB->Disconnect();
1;
