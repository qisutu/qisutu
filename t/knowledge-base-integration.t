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
        core/module/AgentKnowledgeBase.pm
        core/module/CustomerKnowledgeBase.pm
        core/output/AgentKnowledgeBase.tt
        core/output/CustomerKnowledgeBase.tt
        core/system/QisutuKnowledgeBase.pm
        var/static/js/qisutu-knowledge-insert.js
        install/update/database/0.0.16/001-create-knowledge-base.sql
        install/update/database/0.0.17/001-simplify-knowledge-base.sql
    )
) {
    ok( -f File::Spec->catfile( $Root, split m{/}, $File ), "$File is part of the release" );
}

my $InsertJS = content('var/static/js/qisutu-knowledge-insert.js');
my $RichTextJS = content('var/static/js/qisutu-richtext.js');
like( $RichTextJS, qr/editor\.model\.insertContent\(modelFragment, editor\.model\.document\.selection\)/, 'CKEditor insertion uses the current cursor selection' );
like( $InsertJS, qr/CustomerSafe/, 'insertion search sends customer-safety context' );
like( $InsertJS, qr/data-qisutu-knowledge-insert-mode/, 'multiple insertion modes are wired' );
unlike( $InsertJS, qr{https?://}i, 'knowledge insertion has no external runtime dependency' );

my $System = content('core/system/QisutuKnowledgeBase.pm');
like( $System, qr/visibility.*customer/s, 'customer visibility is checked in the backend' );
like( $System, qr/knowledge_article_revision/, 'revisions are persisted' );
unlike( $System, qr/GroupPermission(?:List|Set)/, 'FAQ group permissions are not part of the model' );

my $AgentModule = content('core/module/AgentKnowledgeBase.pm');
like( $AgentModule, qr/Action=CategoryEdit/, 'agents manage FAQ categories' );
my $AgentTemplate = content('core/output/AgentKnowledgeBase.tt');
unlike( $AgentTemplate, qr/name="(?:Status|CustomerScope|QueueID)"/, 'article form only uses visibility for access' );

my $RemovalList = content('release.remove');
like( $RemovalList, qr{\./core/config/programs/AdminKnowledgeBase\.pm}, 'obsolete admin navigation is removed on update' );
like( $RemovalList, qr{\./core/module/AdminKnowledgeBase\.pm}, 'obsolete admin module is removed on update' );

my $Migration = content('install/update/database/0.0.16/001-create-knowledge-base.sql');
for my $Table (qw(
    knowledge_category knowledge_category_translation knowledge_article knowledge_article_revision
    knowledge_article_customer knowledge_article_queue knowledge_article_usage
)) {
    like( $Migration, qr/CREATE TABLE IF NOT EXISTS `\Q$Table\E`/, "$Table is created by the update migration" );
}

my $Simplification = content('install/update/database/0.0.17/001-simplify-knowledge-base.sql');
like( $Simplification, qr/DELETE FROM `user_group_permission`/, 'update migration removes obsolete FAQ permissions' );
like( $Simplification, qr/SET `status` = 'published', `customer_scope` = 'all'/, 'existing FAQ articles are normalized' );

for my $Language (qw(de en fr it)) {
    my $Translations = content("core/language/$Language.pm");
    like( $Translations, qr/^\s*KnowledgeBaseNavigation\s*=>/m, "$Language contains knowledge base translations" );
    like( $Translations, qr/^\s*KnowledgeInsertSolution\s*=>/m, "$Language contains editor insertion translations" );
}

done_testing();
