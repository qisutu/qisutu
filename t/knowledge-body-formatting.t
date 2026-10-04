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
use JSON::PP qw(decode_json);
use lib "$FindBin::Bin/../core/system", "$FindBin::Bin/../core/module", "$FindBin::Bin/../core/output";
use QisutuKnowledgeBase;
use AgentKnowledgeBase;
use CustomerKnowledgeBase;
use CustomerKnowledgeSuggestions;
use QisutuOutput;

{
    package Local::FAQFormattingDB;
    sub new { return bless { Calls => [] }, shift }
    sub Error { return '' }
    sub BeginWork { return 1 }
    sub Commit { return 1 }
    sub Rollback { return 1 }
    sub LastInsertID { return 7 }
    sub SelectAll { return [] }
    sub SelectRow {
        my ( $Self, $SQL, @Bind ) = @_;
        return { id => 1 } if $SQL =~ /FROM knowledge_category WHERE id/;
        return { id => 7 } if $SQL =~ /SELECT a\.id FROM knowledge_article/;
        return { %{ $Self->{Article} } } if $SQL =~ /FROM knowledge_article/;
        return;
    }
    sub Do {
        my ( $Self, $SQL, @Bind ) = @_;
        push @{ $Self->{Calls} }, [ $SQL, @Bind ];
        if ( $SQL =~ /INSERT INTO knowledge_article\s/ ) {
            $Self->{Article}->{content} = $Bind[6];
        }
        elsif ( $SQL =~ /UPDATE knowledge_article SET category_id/ ) {
            $Self->{Article}->{content} = $Bind[5];
        }
        elsif ( $SQL =~ /INSERT INTO knowledge_article_revision/ ) {
            $Self->{RevisionContent} = $Bind[7];
        }
        return 1;
    }
}

my $Root = File::Spec->rel2abs("$FindBin::Bin/..");
my $Config = {
    RootPath => $Root,
    Paths => { Output => "$Root/core/output", Language => "$Root/core/language", SettingConfig => "$Root/core/config/settings" },
    Language => { Default => 'de' },
};
my $Output = QisutuOutput->new( Config => $Config );
my $DB = Local::FAQFormattingDB->new();
my $Knowledge = QisutuKnowledgeBase->new( Config => $Config, DB => $DB, Output => $Output );
my $Agent = AgentKnowledgeBase->new( Config => $Config, DB => $DB, Output => $Output );
my $Customer = CustomerKnowledgeBase->new( Config => $Config, DB => $DB, Output => $Output );
my $Suggestions = CustomerKnowledgeSuggestions->new( Config => $Config, DB => $DB, Output => $Output );
my $Plain = "1. Öffnen Sie die Anmeldung.\r\n\r\n2. Wählen Sie „Kunde“.\n\n3. Geben Sie Ihre E-Mail-Adresse ein.\r\n\r\nDas Passwort muss acht Zeichen enthalten.";
my $Expected = '1. Öffnen Sie die Anmeldung.<br><br>2. Wählen Sie „Kunde“.'.
    '<br><br>3. Geben Sie Ihre E-Mail-Adresse ein.<br><br>Das Passwort muss acht Zeichen enthalten.';
my $LegacyArticle = {
    id => 7, article_number => 'KB00000007', category_id => 1, language => 'de',
    title => 'Passwort vergessen', summary => 'Zugang wiederherstellen',
    content => $Plain, visibility => 'customer', status => 'published',
    revision_number => 1, category_name => 'Anmeldung',
};
$DB->{Article} = { %{$LegacyArticle} };

for my $Method (qw(ArticleGet CustomerArticleGet AgentInsertArticleGet)) {
    my $Article = $Knowledge->$Method( ArticleID => 7, Language => 'de' );
    is( $Article->{content}, $Expected, "$Method preserves all legacy line breaks for HTML display and insertion" );
}
is( $DB->{Article}->{content}, $Plain, 'reading a legacy FAQ does not rewrite its stored content' );
is( scalar( grep { $_->[0] =~ /(?:INSERT INTO|UPDATE|DELETE FROM) knowledge_article/ } @{ $DB->{Calls} } ), 0, 'display does not modify articles or revisions' );

my $Preview = $Suggestions->_View( ArticleID => 7, Language => 'de' );
my ($JSON) = $Preview->{Response} =~ /\r?\n\r?\n(.*)\z/s;
is( decode_json($JSON)->{article}->{content}, $Expected, 'customer suggestion modal receives the complete formatted solution' );

for my $Locale (qw(de en fr it es nl pl cs tr pt-PT pt-BR)) {
    for my $Page ( [ $Agent, 'agent' ], [ $Customer, 'customer' ] ) {
        my $View = $Page->[0]->Run( Request => { Action => 'View', ArticleID => 7, Language => $Locale }, User => {} );
        is( $View->{Data}->{ArticleContent}, $Expected, "$Locale $Page->[1] view uses the formatted content" );
        my $HTML = $Output->RenderSingle( Template => $View->{Template}, Data => { %{ $View->{Data} }, Language => $Locale } );
        like( $HTML, qr{\Q$Expected\E}, "$Locale $Page->[1] template renders the breaks as HTML" );
    }
    my $Edit = $Agent->Run( Request => { Action => 'Edit', ArticleID => 7, Language => $Locale }, User => {} );
    is( $Edit->{Data}->{Content}, $Expected, "$Locale edit loads legacy line breaks as editor HTML" );
    my $Form = $Output->RenderSingle( Template => $Edit->{Template}, Data => {
        %{ $Edit->{Data} }, Language => $Locale, StaticBase => '/custom-static',
    } );
    like( $Form, qr{<textarea[^>]*id="qisutu-knowledge-content"[^>]*>.*?&lt;br&gt;&lt;br&gt;}s, "$Locale textarea safely passes the breaks to CKEditor" );
    like( $Form, qr{src="/custom-static/js/ckeditor5/ckeditor5\.umd\.js".*src="/custom-static/js/qisutu-richtext\.js}s, "$Locale form loads the bundled editor and initializer in order" );
}

for my $ID (0, 7) {
    $DB->{Article} = { %{$LegacyArticle} };
    my $Saved = $Knowledge->ArticleSave(
        ArticleID => $ID, CategoryID => 1, Language => 'de', Title => 'Passwort vergessen',
        Content => $Plain, Visibility => 'customer', ChangedByUserID => 1,
    );
    is( $Saved, 7, $ID ? 'existing FAQ can be saved' : 'new FAQ can be saved' );
    is( $DB->{Article}->{content}, $Expected, 'plain-text fallback saves all breaks as HTML' );
    is( $DB->{RevisionContent}, $Expected, 'revision stores the same complete formatted content' );
}

my $Rich = "<p>Absatz 1</p>\n<p>&nbsp;</p>\n<ul>\n  <li>Erster Punkt</li>\n  <li>Zweiter Punkt</li>\n</ul>\n<p>Absatz 2<br>Neue Zeile</p>";
is( $Knowledge->ContentHTML($Rich), $Rich, 'existing HTML paragraphs, blank paragraphs and lists remain unchanged' );
is( $Knowledge->ContentHTML($Expected), $Expected, 'repeated preparation does not multiply breaks' );
is( $Knowledge->ContentHTML("A\n\n\nB"), 'A<br><br><br>B', 'multiple empty lines are not collapsed' );
is( $Knowledge->ContentHTML("&lt;Beispiel&gt; &amp; Text\nNächste Zeile"), '&lt;Beispiel&gt; &amp; Text<br>Nächste Zeile', 'existing escaped characters are not double-escaped' );
$Knowledge->ArticleSave( ArticleID => 7, CategoryID => 1, Title => 'Richtext', Content => $Rich, ChangedByUserID => 1 );
is( $DB->{Article}->{content}, $Rich, 'rich-text save retains author formatting without turning HTML source indentation into breaks' );
$Knowledge->ArticleSave( ArticleID => 7, CategoryID => 1, Title => 'Sicher', Content => '<p onclick="bad()">A<br><br>B</p><script>bad()</script>', ChangedByUserID => 1 );
is( $DB->{Article}->{content}, '<p>A<br><br>B</p>', 'save still sanitizes executable HTML' );

my $Failed = $Agent->Run( Request => { Step => 'ArticleSave', ArticleID => 7, CategoryID => 1, Title => '', Content => $Plain, Language => 'de' }, User => { user_account_id => 1 } );
ok( $Failed->{Data}->{ErrorMessage}, 'invalid input returns to the form' );
is( $Failed->{Data}->{Content}, $Expected, 'redisplayed form preserves line breaks after a validation error' );
my $Create = $Agent->Run( Request => { Action => 'Create', Language => 'de' }, User => {} );
my $CreateHTML = $Output->RenderSingle( Template => $Create->{Template}, Data => { %{ $Create->{Data} }, StaticBase => '/static' } );
like( $CreateHTML, qr{/js/ckeditor5/ckeditor5\.umd\.js}, 'new FAQ form also loads the rich-text editor' );

done_testing();
