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
use lib "$FindBin::Bin/../core/system";
use QisutuNotification;
my $N = QisutuNotification->new( Config => {} );
my $Source = <<'HTML';
<div>
  <p>Guten Tag,</p>
  <p>wir planen eine <strong>Migration</strong> und
     benötigen Unterstützung.</p>
  <p>Rahmendaten:</p>
  <ul>
    <li><p>Anzahl Agenten: 10</p></li>
    <li>Endanwender: 1300</li>
    <li>Systeme: Jira &amp; Confluence</li>
  </ul>
  <ol>
    <li>Benötigte AddOns
      <ul><li>Kalender</li><li>Teams</li></ul>
    </li>
    <li>KI-Funktionen</li>
  </ol>
</div>
HTML
my $Text = $N->_ArticleBodyPlainText( Article => { body => $Source, content_type => 'text/html' } );
is($Text, "Guten Tag,\n\nwir planen eine Migration und benötigen Unterstützung.\n\nRahmendaten:\n\n• Anzahl Agenten: 10\n• Endanwender: 1300\n• Systeme: Jira & Confluence\n\n1. Benötigte AddOns\n  • Kalender\n  • Teams\n2. KI-Funktionen", 'rendered paragraph/list gaps and markers survive without source-induced blank lines');
my $P = { 'Ticket.ArticleBody' => $Text };
for my $Syntax ('{{Ticket.ArticleBody[8]}}', '{{ Ticket.ArticleBody[ 8 ] }}') {
 my $HTML = $N->_PlaceholderReplaceHTML( HTML => '<p>'.$Syntax.'</p>', Placeholder => $P );
 like($HTML, qr{• Endanwender: 1300}, "$Syntax includes line eight");
 unlike($HTML, qr{Systeme:}, "$Syntax excludes line nine");
 unlike($HTML, qr{<p>\s*<div|(?:<br>){3}}, "$Syntax has no invalid paragraph wrapper or source-induced gaps");
 ok($N->_ArticleBodyPlaceholderPresent($Syntax), "$Syntax loads the article");
}
like($N->_PlaceholderReplaceHTML( HTML => '{{Ticket.ArticleBody}}', Placeholder => $P ), qr{2[.] KI-Funktionen}, 'full placeholder includes the whole message');
is($N->_PlaceholderReplacePlain( Text => '{{Ticket.ArticleBody[3]}}', Placeholder => $P ), 'Guten Tag, wir planen eine Migration und benötigen Unterstützung.', 'bracketed number also limits a plain-text subject');
is($N->_ArticleBodyPlainText( Article => { body => "One\r\n\r\nTwo\rThree", content_type => 'text/plain' } ), "One\n\nTwo\nThree", 'plain-text line breaks stay intact');
is($N->_ArticleBodyPlainText( Article => { body => '<p>A<br><br>B</p>', content_type => 'text/html' } ), "A\n\nB", 'explicit blank lines stay intact');
is($N->_ArticleBodyPlainText( Article => { body => "<pre>0\n  code\nnext</pre>", content_type => 'text/html' } ), "0\n  code\nnext", 'preformatted content and a zero remain intact');
is($N->_ArticleBodyPlainText( Article => { body => '<table><tr><td>A</td><td>B</td></tr><tr><td>C</td><td>D</td></tr></table>', content_type => 'text/html' } ), "A | B\nC | D", 'table columns remain separated');
is($N->_ArticleBodyPlainText( Article => { body => '<p><strong>Error</strong>: &lt;script&gt;literal&lt;/script&gt;</p><script>bad()</script>', content_type => 'text/html' } ), 'Error: <script>literal</script>', 'inline punctuation and escaped tags stay literal, executable content is removed');
my $Safe = $N->_PlaceholderReplaceHTML( HTML => '{{Ticket.ArticleBody[2]}}', Placeholder => { 'Ticket.ArticleBody' => "<script>literal</script>\n{{Agent.Email}}", 'Agent.Email' => 'private@example.test' } );
like($Safe, qr{&lt;script&gt;literal&lt;/script&gt;}, 'plain article content is HTML-escaped');
like($Safe, qr{\{\{Agent[.]Email\}\}}, 'article text is not interpreted as a second template');
unlike($Safe, qr{private\@example}, 'article content cannot expand agent placeholders');
my $Zero = $N->_PlaceholderReplaceHTML( HTML => '{{Ticket.ArticleBody}}', Placeholder => { 'Ticket.ArticleBody' => '0' } );
like($Zero, qr{>0</div>}, 'a zero-valued article is not discarded');
is($N->_ArticleBodyExcerpt(Text => $Text, Lines => 0), $Text, '[0] includes the complete article');
like($N->_PlaceholderReplaceHTML(HTML => '{{Ticket.ArticleBody[0]}}', Placeholder => $P), qr{2[.] KI-Funktionen}, '[0] renders the complete HTML excerpt');
is($N->_PlaceholderReplacePlain(Text => '{{Ticket.ArticleBody[0]}}', Placeholder => {'Ticket.ArticleBody' => "one\ntwo"}), 'one two', '[0] includes complete plain text');
ok(!$N->_ArticleBodyPlaceholderPresent('{{Ticket.ArticleBody15}}'), 'suffix notation is no longer an article placeholder');
unlike($N->_PlaceholderReplaceHTML(HTML => '{{Ticket.ArticleBody15}}', Placeholder => $P), qr{Guten Tag}, 'suffix notation is no longer expanded');
my @SpacingCase = (
    ['empty paragraph', '<p style="margin:0">A</p><p>&nbsp;</p><p style="margin:0">B</p>', "A\n\nB"],
    ['two empty paragraphs', '<p style="margin:0">A</p><p>&nbsp;</p><p>&nbsp;</p><p style="margin:0">B</p>', "A\n\n\nB"],
    ['empty CKEditor paragraph', '<p style="margin:0">A</p><p><br></p><p style="margin:0">B</p>', "A\n\nB"],
    ['empty paragraph without NBSP', '<p style="margin:0">A</p><p></p><p style="margin:0">B</p>', "A\n\nB"],
    ['empty mail block', '<div>A</div><div>&#160;</div><div>B</div>', "A\n\nB"],
    ['empty mail block with BR', '<div>A</div><div><br></div><div>B</div>', "A\n\nB"],
    ['source indentation', "<div>\n <div>A</div>\n\n <div>B</div>\n</div>", "A\nB"],
    ['paragraph separation', "<p>A</p>\n\n\n<p>B</p>", "A\n\nB"],
    ['explicit zero paragraph margins', '<p style="margin:0">A</p><p style="margin:0">B</p>', "A\nB"],
    ['list items stay compact', '<ul><li><p>A</p></li><li><p>B</p></li></ul>', "• A\n• B"],
    ['section gap after a list', '<ul><li>A</li><li>B</li></ul><ol><li>Next section</li></ol>', "• A\n• B\n\n1. Next section"],
    ['inline margin on a mail block', '<div style="margin-bottom:10px">A</div><div>B</div>', "A\n\nB"],
    ['adjacent margins do not accumulate', '<p style="margin-bottom:10px">A</p><p style="margin-top:10px">B</p>', "A\n\nB"],
    ['source wrapping within inline text', "<div>A\n <strong>B</strong>\n C</div>", 'A B C'],
    ['leading and trailing authored blanks', '<p>&nbsp;</p><div>A</div><p>&nbsp;</p>', "\nA\n"],
);
for my $Case (@SpacingCase) {
    is($N->_ArticleBodyPlainText(Article=>{body=>$Case->[1],content_type=>'text/html'}),$Case->[2],$Case->[0]);
}
my $Sections = $N->_ArticleBodyPlainText(Article=>{content_type=>'text/html',body=>
    '<div>Rahmendaten:</div><ul><li>Anzahl Agenten: 10</li><li>Endanwender: 1300</li></ul>' .
    '<ol><li>Benötigte AddOns<div>Bitte beziffern Sie folgende Module einzeln:</div></li></ol>' .
    '<ul><li>Entra ID – Agenten</li><li>Kim – Prozesse</li></ul><ol><li>KI-Funktionen</li></ol>'});
is($Sections,"Rahmendaten:\n• Anzahl Agenten: 10\n• Endanwender: 1300\n\n1. Benötigte AddOns\nBitte beziffern Sie folgende Module einzeln:\n\n• Entra ID – Agenten\n• Kim – Prozesse\n\n1. KI-Funktionen", 'section structure from the reported example retains all three gaps');
my $SectionsHTML=$N->_PlaceholderReplaceHTML(HTML=>'{{Ticket.ArticleBody[0]}}',Placeholder=>{'Ticket.ArticleBody'=>$Sections});
like($SectionsHTML,qr{Endanwender: 1300<br><br>1[.] Benötigte AddOns},'notification HTML keeps the first section gap');
like($SectionsHTML,qr{Module einzeln:<br><br>• Entra ID},'notification HTML keeps the gap before the module list');
like($SectionsHTML,qr{Kim – Prozesse<br><br>1[.] KI-Funktionen},'notification HTML keeps the next section gap');
is($N->_ArticleBodyExcerpt(Text=>$Sections,Lines=>4),"Rahmendaten:\n• Anzahl Agenten: 10\n• Endanwender: 1300\n",'line limits include real blank lines without pulling in the next section');
done_testing();
