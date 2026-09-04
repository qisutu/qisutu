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

use Test::More;
use FindBin;
use File::Spec;

my $Root = File::Spec->catdir( $FindBin::Bin, '..' );

sub content {
    my ($Relative) = @_;
    my $Path = File::Spec->catfile( $Root, split m{/}, $Relative );
    open my $FH, '<:raw', $Path or die "Cannot read $Path: $!";
    local $/;
    return <$FH>;
}

for my $File (
    qw(
        core/config/programs/KnowledgeBase.pm
        core/config/programs/AgentKnowledgeBase.pm
        core/config/programs/CustomerKnowledgeBase.pm
        core/config/programs/KnowledgeAttachmentDownload.pm
        core/module/AgentKnowledgeBase.pm
        core/module/CustomerKnowledgeBase.pm
        core/module/KnowledgeAttachmentDownload.pm
        core/output/AgentKnowledgeBase.tt
        core/output/CustomerKnowledgeBase.tt
        core/system/QisutuKnowledgeBase.pm
        var/static/js/qisutu-knowledge-insert.js
        install/sql/schema.sql
    )
) {
    ok( -f File::Spec->catfile( $Root, split m{/}, $File ), "$File is part of the release" );
}

my $InsertJS = content('var/static/js/qisutu-knowledge-insert.js');
my $RichTextJS = content('var/static/js/qisutu-richtext.js');
my $InsertRuntimeJS = $InsertJS;
$InsertRuntimeJS =~ s{\A/\*.*?\*/\s*}{}s;
like( $RichTextJS, qr/editor\.model\.insertContent\(modelFragment, editor\.model\.document\.selection\)/, 'CKEditor insertion uses the current cursor selection' );
like( $InsertJS, qr/CustomerSafe/, 'insertion search sends customer-safety context' );
like( $InsertJS, qr/data-qisutu-knowledge-text-mode/, 'multiple text insertion modes are wired' );
like( $InsertJS, qr/KnowledgeAttachmentID/, 'FAQ attachment selections are submitted with the ticket form' );
like( $InsertJS, qr/includeText.*includeAttachments/s, 'FAQ text and attachments are selected independently' );
unlike( $InsertRuntimeJS, qr{https?://}i, 'knowledge insertion has no external runtime dependency' );

my $System = content('core/system/QisutuKnowledgeBase.pm');
like( $System, qr/visibility.*customer/s, 'customer visibility is checked in the backend' );
like( $System, qr/knowledge_article_revision/, 'revisions are persisted' );
like( $System, qr/sub AttachmentsForTicket/, 'FAQ attachments can be converted to ticket attachments' );
like( $System, qr/sub AttachmentGet/, 'FAQ attachment downloads are authorized by the backend' );
unlike( $System, qr/GroupPermission(?:List|Set)/, 'FAQ group permissions are not part of the model' );

my $AgentModule = content('core/module/AgentKnowledgeBase.pm');
like( $AgentModule, qr/Action=CategoryEdit/, 'agents manage FAQ categories' );
my $AgentTemplate = content('core/output/AgentKnowledgeBase.tt');
unlike( $AgentTemplate, qr/name="(?:Status|CustomerScope|QueueID)"/, 'article form only uses visibility for access' );
like(
    $AgentTemplate,
    qr{\[% IF ErrorMessage %\]<div class="qisutu-form-error \[% ErrorClass %\]">\[% ErrorMessage %\]</div>\[% END %\]},
    'the agent FAQ error bar is rendered only when an error message exists',
);
like( $AgentTemplate, qr/enctype="multipart\/form-data"/, 'the FAQ editor accepts file uploads' );
like( $AgentTemplate, qr/name="KnowledgeAttachment"/, 'the FAQ editor provides a multiple attachment input' );

for my $TicketTemplate (qw(core/output/AgentTicketCreate.tt core/output/AgentTicketZoom.tt)) {
    my $Template = content($TicketTemplate);
    like( $Template, qr/data-qisutu-knowledge-include-text/, "$TicketTemplate offers a separate FAQ text selection" );
    like( $Template, qr/data-qisutu-knowledge-include-attachments/, "$TicketTemplate offers a separate FAQ attachment selection" );
    like( $Template, qr/name="KnowledgeAttachmentID"/, "$TicketTemplate preserves selected FAQ attachment IDs" );
}

my $RemovalList = content('release.remove');
unlike( $RemovalList, qr{^\s*[.]/}m, 'the first official release needs no update removal entries' );
ok( !-e File::Spec->catfile( $Root, 'core', 'config', 'programs', 'AdminKnowledgeBase.pm' ), 'obsolete admin navigation is absent from the clean release' );
ok( !-e File::Spec->catfile( $Root, 'core', 'module', 'AdminKnowledgeBase.pm' ), 'obsolete admin module is absent from the clean release' );

my $Schema = content('install/sql/schema.sql');
for my $Table (qw(
    knowledge_category knowledge_category_translation knowledge_article knowledge_article_revision
    knowledge_article_attachment knowledge_article_customer knowledge_article_queue knowledge_article_usage
)) {
    like( $Schema, qr/CREATE TABLE IF NOT EXISTS `\Q$Table\E`/, "$Table is part of the 1.0.2 fresh-install schema" );
}

unlike( $Schema, qr/CREATE TABLE IF NOT EXISTS `knowledge_(?:article|category)_group`/, 'the clean schema contains no obsolete FAQ group tables' );

for my $Language (qw(de en fr it pt-BR pt-PT es nl pl cs tr)) {
    my $Translations = content("core/language/$Language.pm");
    like( $Translations, qr/^\s*KnowledgeBaseNavigation\s*=>/m, "$Language contains knowledge base translations" );
    like( $Translations, qr/^\s*KnowledgeInsertSolution\s*=>/m, "$Language contains editor insertion translations" );
    like( $Translations, qr/^\s*KnowledgeInsertIncludeText\s*=>/m, "$Language contains the FAQ text selection translation" );
    like( $Translations, qr/^\s*KnowledgeInsertIncludeAttachments\s*=>/m, "$Language contains the FAQ attachment selection translation" );
    like( $Translations, qr/^\s*KnowledgeAttachmentLoadFailed\s*=>/m, "$Language contains FAQ attachment error translations" );
}

done_testing();
