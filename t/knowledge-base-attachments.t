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
    package Local::KnowledgeAttachmentDB;

    sub new {
        my ( $Class, %Param ) = @_;
        return bless { %Param, calls => [] }, $Class;
    }

    sub SelectAll {
        my ( $Self, $SQL, @Bind ) = @_;
        push @{ $Self->{calls} }, [ SelectAll => $SQL, @Bind ];
        return $Self->{rows};
    }

    sub SelectRow {
        my ( $Self, $SQL, @Bind ) = @_;
        push @{ $Self->{calls} }, [ SelectRow => $SQL, @Bind ];
        return $Self->{row};
    }

    sub Error { return shift->{error} || ''; }
}

my $DB = Local::KnowledgeAttachmentDB->new(
    rows => [ {
        id                 => 17,
        article_id         => 4,
        filename           => 'manual.pdf',
        content_type       => 'application/pdf',
        content            => 'pdf-bytes',
        content_size       => 2048,
        created_by_user_id => 3,
        created_at         => '2026-09-04 12:00:00',
    } ],
);
my $Object = QisutuKnowledgeBase->new(
    Config => { Language => { Default => 'de' } },
    DB     => $DB,
);

my $List = $Object->AttachmentList( ArticleID => 4 );
is( scalar @{$List}, 1, 'FAQ attachments are listed for an article' );
is( $List->[0]->{size_display}, '2.0 KB', 'FAQ attachment sizes are formatted' );
like( $List->[0]->{download_url}, qr/KnowledgeAttachmentDownload/, 'FAQ attachment download URL uses the protected endpoint' );

my $ForTicket = $Object->AttachmentsForTicket(
    AttachmentIDs => [ 17 ],
    CustomerSafe  => 1,
);
is( scalar @{$ForTicket}, 1, 'selected FAQ attachments are returned for a ticket article' );
is( $ForTicket->[0]->{Filename}, 'manual.pdf', 'ticket attachment keeps the FAQ filename' );
is( $ForTicket->[0]->{Content}, 'pdf-bytes', 'ticket attachment includes the stored bytes' );
is( $ForTicket->[0]->{knowledge_attachment_id}, 17, 'the source FAQ attachment remains identifiable in the form' );
my ($SafeCall) = grep { $_->[0] eq 'SelectAll' && $_->[1] =~ /attachment[.]id IN/ } @{ $DB->{calls} };
like( $SafeCall->[1], qr/article[.]visibility = "customer"/, 'customer-visible tickets only accept customer-visible FAQ attachments' );

my $MissingDB = Local::KnowledgeAttachmentDB->new( rows => [] );
my $MissingObject = QisutuKnowledgeBase->new(
    Config => { Language => { Default => 'de' } },
    DB     => $MissingDB,
);
ok(
    !defined $MissingObject->AttachmentsForTicket( AttachmentIDs => [ 99 ], CustomerSafe => 0 ),
    'unknown or manipulated FAQ attachment IDs are rejected',
);
is( $MissingObject->Error(), 'Translate:KnowledgeAttachmentLoadFailed', 'selection rejection returns a specific error' );

my $DownloadDB = Local::KnowledgeAttachmentDB->new(
    row => {
        id              => 17,
        article_id      => 4,
        filename        => 'manual.pdf',
        content_type    => 'application/pdf',
        content         => 'pdf-bytes',
        content_size    => 9,
        language        => 'de',
        visibility      => 'internal',
        category_active => 1,
    },
);
my $DownloadObject = QisutuKnowledgeBase->new(
    Config => { Language => { Default => 'de' } },
    DB     => $DownloadDB,
);
ok(
    $DownloadObject->AttachmentGet(
        AttachmentID => 17,
        User         => { account_type => 'agent', user_account_id => 8 },
        Language     => 'de',
    ),
    'agents can download internal FAQ attachments',
);
ok(
    !$DownloadObject->AttachmentGet(
        AttachmentID => 17,
        User         => { account_type => 'customer', user_account_id => 9 },
        Language     => 'de',
    ),
    'customers cannot download internal FAQ attachments',
);

$DownloadDB->{row}->{visibility} = 'customer';
ok(
    $DownloadObject->AttachmentGet(
        AttachmentID => 17,
        User         => { account_type => 'customer', user_account_id => 9 },
        Language     => 'de',
    ),
    'customers can download attachments of customer-visible FAQs in their language',
);
ok(
    !$DownloadObject->AttachmentGet(
        AttachmentID => 17,
        User         => { account_type => 'customer', user_account_id => 9 },
        Language     => 'en',
    ),
    'customer downloads cannot bypass the FAQ language view',
);

done_testing();
