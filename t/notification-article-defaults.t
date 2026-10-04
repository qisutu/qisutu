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
use Test::More;
use FindBin;
use File::Spec;
use lib "$FindBin::Bin/../core/system", "$FindBin::Bin/../core/output";
use QisutuNotification;
use QisutuAgentNotificationTemplates;
use QisutuOutput;
my $Root = File::Spec->rel2abs("$FindBin::Bin/..");
my $Output = QisutuOutput->new(Config => {Paths => {Output => "$Root/core/output", Language => "$Root/core/language"}, Language => {Default => 'en'}});
for my $Language (qw(de en fr it es nl pl cs tr pt-PT pt-BR)) {
    my $Templates = QisutuAgentNotificationTemplates->Templates(Language => $Language);
    is(scalar(grep {$_->{body_html} =~ /\{\{Ticket[.]ArticleBody\[15\]\}\}/} @{$Templates}), 6, "$Language: every standard template defaults to [15]");
    my $HTML = $Output->RenderSingle(Template => 'AdminAgentNotifications.tt', Data => {
        Language => $Language, ShowEdit => 1,
        CurrentBodyHTML => $Templates->[0]->{body_html},
        PlaceholderList => QisutuNotification->PlaceholderList(),
    });
    like($HTML, qr{<textarea[^>]*name="BodyHTML"[^>]*>.*\{\{Ticket[.]ArticleBody\[15\]\}\}.*</textarea>}s, "$Language: editor displays [15]");
    like($HTML, qr{<span>[^<]*\{\{Ticket[.]ArticleBody\[0\]\}\}[^<]*</span>}, "$Language: full-text placeholder card displays the [0] example");
    unlike($HTML, qr{\{\{Ticket[.]ArticleBody15\}\}|Translate:NotificationArticleBody}, "$Language: help contains no suffix notation or unresolved translation");
}

BEGIN {
    $INC{'QisutuConfig.pm'} = __FILE__;
    $INC{'QisutuDB.pm'} = __FILE__;
}
{
    package QisutuConfig;
    sub Load {return {}}
    package QisutuDB;
    our $TestDB;
    sub new {$TestDB}
    package Local::NotificationMigrationDB;
    sub Connect {1}
    sub Disconnect {1}
    sub SelectAll { [map {{%{$_}}} @{$_[0]->{Rows}}] }
    sub Do {
        my ($Self,$SQL,$Subject,$Body,$ID,$OldSubject,$OldBody)=@_;
        my ($Row)=grep {$_->{id}==$ID} @{$Self->{Rows}};
        die 'unguarded migration' if $SQL !~ /BINARY subject = BINARY \?/ || $SQL !~ /BINARY body_html = BINARY \?/;
        die 'unexpected overwrite' if $Row->{subject} ne $OldSubject || $Row->{body_html} ne $OldBody;
        $Row->{subject}=$Subject; $Row->{body_html}=$Body; $Self->{Writes}++;
        return 1;
    }
}
$QisutuDB::TestDB = bless {Rows => [
    {id=>1,subject=>'New ticket',body_html=>'<p>Custom text</p><p>{{Ticket.ArticleBody}}</p>'},
    {id=>2,subject=>'Reply',body_html=>'<p>{{Ticket.ArticleBody[5]}}</p>'},
    {id=>3,subject=>'No excerpt',body_html=>'<p>Custom text only</p>'},
    {id=>4,subject=>'{{Ticket.ArticleBody2}}',body_html=>'<p>{{Ticket.ArticleBody8}}</p>'},
    {id=>5,subject=>'Full text',body_html=>'<p>{{Ticket.ArticleBody[0]}}</p>'},
    {id=>6,subject=>'Whitespace',body_html=>'<p>{{ Ticket.ArticleBody }}</p>'},
],Writes=>0}, 'Local::NotificationMigrationDB';
my $Migration = "$Root/install/update/database/2.0.2/002-notification-article-lines.pl";
ok(do($Migration), 'existing-template migration completes') or diag($@ || $!);
my $Rows=$QisutuDB::TestDB->{Rows};
is($Rows->[0]->{body_html},'<p>Custom text</p><p>{{Ticket.ArticleBody[15]}}</p>','default changes to [15] while custom text stays intact');
is($Rows->[1]->{body_html},'<p>{{Ticket.ArticleBody[5]}}</p>','explicit line count stays intact');
is($Rows->[2]->{body_html},'<p>Custom text only</p>','intentionally omitted excerpt stays omitted');
is($Rows->[3]->{subject},'{{Ticket.ArticleBody[2]}}','saved suffix in subject is corrected');
is($Rows->[3]->{body_html},'<p>{{Ticket.ArticleBody[8]}}</p>','saved suffix in body is corrected with its configured count');
is($Rows->[4]->{body_html},'<p>{{Ticket.ArticleBody[0]}}</p>','explicit full-text setting stays intact');
is($Rows->[5]->{body_html},'<p>{{Ticket.ArticleBody[15]}}</p>','whitespace variant receives the default');
is($QisutuDB::TestDB->{Writes},3,'only affected templates are written');
ok(do($Migration), 'migration can safely run again') or diag($@ || $!);
is($QisutuDB::TestDB->{Writes},3,'rerunning the migration does not rewrite templates');
done_testing();
