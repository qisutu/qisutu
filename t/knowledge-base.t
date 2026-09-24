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
    'internal article is never directly visible in the customer portal',
);
ok(
    $Object->_ArticleCustomerAllowed(
        Article => { id => 1, visibility => 'customer', status => 'draft', customer_scope => 'selected' },
    ),
    'customer visibility permits direct access in the customer portal',
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

{
    no warnings 'redefine';
    my $Article = {
        id              => 7,
        article_number  => 'KB00000007',
        title           => 'Agent FAQ',
        content         => '<p>Restart the printer.</p>',
        visibility      => 'internal',
        revision_number => 2,
        attachment_count => 1,
        attachments     => [ {
            id => 17, filename => 'manual.pdf', content_type => 'application/pdf', content_size => 9,
        } ],
    };
    local *QisutuKnowledgeBase::ArticleList = sub { return [ $Article ]; };
    local *QisutuKnowledgeBase::ArticleGet = sub {
        my ( $Self, %Param ) = @_;
        return $Param{ArticleID} == $Article->{id} ? $Article : undef;
    };
    local *QisutuSystemSetting::BaseURL = sub { return 'https://qisutu.example'; };

    for my $Visibility (qw(internal customer)) {
        $Article->{visibility} = $Visibility;
        for my $CustomerSafe (0, 1) {
            subtest "$Visibility FAQ in agent message with CustomerSafe=$CustomerSafe" => sub {
                my $Results = $Object->AgentInsertSearch( CustomerSafe => $CustomerSafe );
                is( $Results->[0]->{can_insert}, 1, 'search result allows agent insertion' );
                my $Selected = $Object->AgentInsertArticleGet(
                    ArticleID => 7, CustomerSafe => $CustomerSafe,
                );
                is( $Selected->{can_insert}, 1, 'selected article can be inserted into the reply' );
                is( $Selected->{content}, $Article->{content}, 'FAQ solution is available for insertion' );
                is( $Selected->{attachments}->[0]->{id}, 17, 'FAQ attachment is available for selection' );
                if ( $Visibility eq 'internal' ) {
                    is( $Selected->{portal_url}, '', 'internal FAQ has no customer-portal link' );
                }
                else {
                    like( $Selected->{portal_url}, qr/CustomerKnowledgeBase.*ArticleID=7/, 'customer FAQ retains its portal link' );
                }
                is( $Article->{visibility}, $Visibility, 'using the FAQ does not change its portal visibility' );
            };
        }
    }
    ok( !defined $Object->AgentInsertArticleGet( ArticleID => 99, CustomerSafe => 1 ), 'missing FAQ cannot be inserted' );
}

done_testing();
