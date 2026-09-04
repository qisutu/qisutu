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

use QisutuKnowledgeBase;

{
    package Local::KnowledgeDB;

    sub new { return bless { calls => [] }, shift; }
    sub SelectRow {
        my ( $Self, $SQL, @Bind ) = @_;
        return { id => $Bind[0] || 1 } if $SQL =~ /FROM knowledge_category WHERE id/;
        return undef if $SQL =~ /FROM knowledge_article WHERE id/;
        return undef;
    }
    sub SelectAll { return []; }
    sub BeginWork { return 1; }
    sub Commit { return 1; }
    sub Rollback { return 1; }
    sub LastInsertID { return 42; }
    sub Error { return ''; }
    sub Do {
        my ( $Self, $SQL, @Bind ) = @_;
        my $PlaceholderCount = () = $SQL =~ /\?/g;
        die "placeholder mismatch: $PlaceholderCount != " . scalar(@Bind) . "\n$SQL"
            if $PlaceholderCount != @Bind;
        push @{ $Self->{calls} }, [ $SQL, @Bind ];
        return 1;
    }
}

my $DB = Local::KnowledgeDB->new();
my $Object = QisutuKnowledgeBase->new(
    Config => { Language => { Default => 'de' } },
    DB     => $DB,
);

is_deeply(
    $Object->_IDList( [ 2, '2', 0, 'x', 5, 5 ] ),
    [ 2, 5 ],
    'numeric ID lists are validated and de-duplicated',
);

ok(
    !$Object->_ArticleCustomerAllowed(
        Article => { id => 1, visibility => 'internal', status => 'published', customer_scope => 'all' },
        CustomerID => 4,
    ),
    'internal article is never customer-safe',
);
ok(
    $Object->_ArticleCustomerAllowed(
        Article => { id => 1, visibility => 'customer', status => 'draft', customer_scope => 'selected' },
    ),
    'customer visibility alone makes an article customer-safe',
);

my $ArticleID = $Object->ArticleSave(
    CategoryID      => 3,
    Language        => 'de',
    Title           => 'Drucker neu starten',
    Summary         => 'Kurzanleitung',
    Keywords        => 'Drucker, Neustart',
    Content         => '<p>Lösung</p><script>alert(1)</script>',
    Visibility      => 'customer',
    CustomerScope   => 'selected',
    Status          => 'draft',
    CustomerIDs     => [ 7 ],
    QueueIDs        => [ 2 ],
    Attachments     => [ {
        Filename    => '../printer-guide.pdf',
        ContentType => 'application/pdf',
        Content     => 'pdf-bytes',
        ContentSize => 9,
    } ],
    ChangedByUserID => 9,
);

is( $ArticleID, 42, 'article is created transactionally' );
ok(
    scalar( grep { $_->[0] =~ /INSERT INTO knowledge_article_revision/ } @{ $DB->{calls} } ),
    'immutable article revision is stored',
);
is(
    scalar( grep { $_->[0] =~ /INSERT INTO knowledge_article_(?:customer|queue)/ } @{ $DB->{calls} } ),
    0,
    'customer and queue assignments are ignored',
);
my ($ArticleInsert) = grep { $_->[0] =~ /INSERT INTO knowledge_article\s/ } @{ $DB->{calls} };
unlike( join( ' ', @{$ArticleInsert} ), qr/<script/i, 'article HTML is sanitized before storage' );
like( join( ' ', @{$ArticleInsert} ), qr/published/, 'article is always stored as published technical data' );
like( join( ' ', @{$ArticleInsert} ), qr/all/, 'article is always stored without a customer restriction' );
my ($AttachmentInsert) = grep { $_->[0] =~ /INSERT INTO knowledge_article_attachment/ } @{ $DB->{calls} };
ok( $AttachmentInsert, 'an uploaded FAQ attachment is stored in the article transaction' );
is( $AttachmentInsert->[2], 'printer-guide.pdf', 'FAQ attachment filenames are reduced to their basename' );

done_testing();
