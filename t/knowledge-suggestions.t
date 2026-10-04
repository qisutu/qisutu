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
use File::Temp qw(tempdir);
use File::Path qw(make_path);
use JSON::PP;
use lib "$FindBin::Bin/../core/system", "$FindBin::Bin/../core/module", "$FindBin::Bin/../core/output";
use QisutuKnowledgeSuggestions;
use CustomerKnowledgeSuggestions;
use AdminKnowledgeSuggestions;
use QisutuOutput;
use QisutuAddonRuntime;
use QisutuProgramRegistry;
my $Root = File::Spec->rel2abs("$FindBin::Bin/..");
my $Config = { RootPath => $Root, Paths => { SettingConfig => "$Root/core/config/settings", Output => "$Root/core/output", Language => "$Root/core/language", ProgramConfig => "$Root/core/config/programs", Addons => "$Root/addons" }, Language => { Default => 'en' } };
{
 package Local::KnowledgeDB;
 sub new { bless { Settings => {}, Fields => [], Calls => [], Published => 1, Rows => [], Error => '' }, shift }
 sub Do {
  my ($S,$SQL,@Bind)=@_;
  push @{$S->{Calls}},[$SQL,@Bind];
  $S->{Settings}->{$Bind[0]}=$Bind[1] if $SQL =~ /INSERT INTO system_setting/;
  return 1;
 }
 sub SelectAll {
  my ($S,$SQL,@Bind)=@_;push @{$S->{Calls}},[$SQL,@Bind];
  return [map {{setting_key=>$_,setting_value=>$S->{Settings}->{$_}}} keys %{$S->{Settings}}] if $SQL =~ /FROM system_setting/;
  return $S->{Fields} if $SQL =~ /FROM ticket_form_field/;
  return $S->{Packages} || [] if $SQL =~ /FROM addon_package/;
  return [] if $SQL =~ /FROM knowledge_attachment/;
  return $S->{Rows};
 }
 sub SelectRow {
  my ($S,$SQL,@Bind)=@_;push @{$S->{Calls}},[$SQL,@Bind];
  return $S->{Published} ? {id=>$Bind[0]} : undef if $SQL =~ /SELECT a[.]id FROM knowledge_article/;
  return { id=>$Bind[0], title=>'VPN', content=>'<p>Reconnect</p><script>bad()</script>', attachments=>[] } if $SQL =~ /a[.]article_number/;
  return;
 }
 sub Error { $_[0]->{Error} }
}
my $DB = Local::KnowledgeDB->new();
my $K = QisutuKnowledgeSuggestions->new(Config=>$Config,DB=>$DB);
is_deeply($K->SettingsGet(), {enabled=>1,max_results=>3,minimum_length=>3}, 'native defaults work with no add-on installed');
ok($K->SettingsSave(Values=>{enabled=>1,max_results=>5,minimum_length=>4},UserID=>7), 'save native settings');
is_deeply($K->SettingsGet(), {enabled=>1,max_results=>5,minimum_length=>4}, 'native settings persist across reads');
ok(!$K->SettingsSave(Values=>{enabled=>1,max_results=>11,minimum_length=>4},UserID=>7), 'invalid limits are rejected');
is($K->SettingsGet()->{max_results},5,'invalid values do not modify settings');
my $Customer={account_type=>'customer',user_account_id=>9};
my $Data=$K->FormData(User=>$Customer,Data=>{ShowLegacyForm=>1,HasQueueOptions=>1,Language=>'de'});
is($Data->{KnowledgeFieldName},'Title','legacy subject bound');
is($Data->{KnowledgeBodyFieldName},'Body','legacy message bound');
is($Data->{KnowledgeMinimumLength},4,'UI uses saved minimum');
$DB->{Fields}=[{id=>20,field_key=>'title'},{id=>21,field_key=>'body'}];
$Data=$K->FormData(User=>$Customer,Data=>{ShowConfiguredForm=>1,FormID=>3,Language=>'pt-BR'});
is($Data->{KnowledgeFieldName},'FormField_20','configured subject bound');
is($Data->{KnowledgeBodyFieldName},'FormField_21','configured message bound');
$DB->{Fields}=[{id=>21,field_key=>'body'}];
is($K->FormData(User=>$Customer,Data=>{ShowConfiguredForm=>1,FormID=>3})->{KnowledgeBodyFieldName},'FormField_21','message-only configured forms work');
is_deeply($K->FormData(User=>$Customer,Data=>{ShowFormSelection=>1}),{},'no suggestions on form selection');
is_deeply($K->FormData(User=>{},Data=>{ShowLegacyForm=>1,HasQueueOptions=>1}),{},'no suggestions on public forms');
my $Prepared=$K->Prepare(Subject=>'VPN',Description=>'<p>Drucker defekt</p>');
ok(grep($_ eq 'vpn',@{$Prepared->{tokens}}),'search includes subject');
ok(grep($_ eq 'drucker',@{$Prepared->{tokens}}),'search includes message');
ok(grep($_ eq 'drucker',@{$K->Prepare(Subject=>'',Description=>'Drucker defekt')->{tokens}}),'empty subject still searches message');
$K->Articles(Subject=>'VPN',Description=>'Drucker',Language=>'de',Limit=>5);
my $SQL=$DB->{Calls}->[-1]->[0];
like($SQL,qr/a[.]search_text/,'article body is searched');
like($SQL,qr/a[.]visibility = 'customer'.*a[.]status = 'published'.*c[.]active = 1.*a[.]language = \?/s,'search restricts visibility, publication, category and language');
like($SQL,qr/LIMIT 5\z/,'configured result limit applied');
$K->Browse(Query=>'',Language=>'de');
like($DB->{Calls}->[-1]->[0],qr/ORDER BY LOWER\(a[.]title\), a[.]id\s+LIMIT 250/,'independent browser works with no ticket text');
my $Out=QisutuOutput->new(Config=>$Config);
my $Portal=CustomerKnowledgeSuggestions->new(Config=>$Config,DB=>$DB,Output=>$Out);
sub response {
 my ($User,%Request)=@_;
 my $R=$Portal->Run(User=>$User,Request=>{__RequestMethod=>'POST',Language=>'de',%Request})->{Response};
 my ($Body)=$R =~ /\r\n\r\n(.*)\z/s;
 return ($R,defined $Body ? JSON::PP->new->utf8->decode($Body) : {});
}
my($R,$Body)=response($Customer,Step=>'Search',Subject=>'',Description=>'Drucker');
like($R,qr/200 OK/,'native search endpoint is available without the addon');
($R,$Body)=response({},Step=>'Browse');like($R,qr/403 Forbidden/,'anonymous access rejected');
($R,$Body)=response({account_type=>'agent',user_account_id=>7},Step=>'Browse');like($R,qr/403 Forbidden/,'customer endpoint rejects agents');
($R,$Body)=response($Customer,Step=>'Search',__RequestMethod=>'GET');like($R,qr/405 Method Not Allowed/,'endpoint requires POST');
($R,$Body)=response($Customer,Step=>'Search',Subject=>[]);like($R,qr/400 Bad Request/,'malformed input rejected');
($R,$Body)=response($Customer,Step=>'View',ArticleID=>42);like($R,qr/200 OK/,'article preview available');
is($Body->{article}->{content},'<p>Reconnect</p>','preview sanitized');
$DB->{Published}=0;
($R,$Body)=response($Customer,Step=>'View',ArticleID=>42);like($R,qr/404 Not Found/,'unpublished/inaccessible article is not delivered');
$K->SettingsSave(Values=>{enabled=>0,max_results=>5,minimum_length=>4},UserID=>7);
is_deeply($K->FormData(User=>$Customer,Data=>{ShowLegacyForm=>1,HasQueueOptions=>1}),{},'disabled suggestions render no UI');
($R,$Body)=response($Customer,Step=>'Search',Subject=>'VPN');is_deeply($Body->{articles},[],'disabled search returns no articles');
($R,$Body)=response($Customer,Step=>'Browse');like($R,qr/403 Forbidden/,'disabled browser is unavailable');
{
 no warnings 'redefine';
 local *QisutuPermission::UserIsAdmin = sub { $_[2] == 7 };
 my $Admin=AdminKnowledgeSuggestions->new(Config=>$Config,DB=>$DB,Output=>$Out);
 my $A=$Admin->Run(User=>{account_type=>'agent',user_account_id=>7},Request=>{__RequestMethod=>'POST',Step=>'SettingsSave',Enabled=>1,MaxResults=>3,MinimumLength=>3});
 like($A->{Redirect},qr/Page=AdminKnowledgeSuggestions/,'administrator saves via native page');
 $A=$Admin->Run(User=>{account_type=>'agent',user_account_id=>8},Request=>{});
 like($A->{Response},qr/403 Forbidden/,'non-admin cannot configure suggestions');
 $A=$Admin->Run(User=>{account_type=>'agent',user_account_id=>7},Request=>{__RequestMethod=>'GET',Step=>'SettingsSave'});
 like($A->{Response},qr/405 Method Not Allowed/,'settings save requires POST');
}
my @Languages=qw(de en fr it es nl pl cs tr pt-PT pt-BR);
for my $Lang (@Languages) {
 my $D=do "$Root/core/language/$Lang.pm";
 ok($D->{KnowledgeSuggestionsChoose} && $D->{KnowledgeSuggestionsSaveFailed} && $D->{NotificationArticleBodyLines},"$Lang includes customer/admin/notification translations");
 my $HTML=$Out->RenderSingle(Template=>'CustomerTicketCreate.tt',Data=>{Language=>$Lang,StaticBase=>'/static',SystemVersion=>'2.0.2',CSRFToken=>'test-token',ShowKnowledgeSuggestions=>1,KnowledgeFieldName=>'Title',KnowledgeBodyFieldName=>'Body',KnowledgeLanguage=>$Lang,KnowledgeEndpoint=>'index.pl?Page=CustomerKnowledgeSuggestions',KnowledgeMinimumLength=>3,KnowledgeDebounce=>350});
 like($HTML,qr{data-csrf-token="test-token"},"$Lang exposes the session CSRF token to the native widget");
 like($HTML,qr{/js/qisutu-knowledge-suggestions[.]js},"$Lang loads the core script");
 unlike($HTML,qr{/addons/|\[%|Translate[.]},"$Lang has no add-on paths or unresolved template markers");
}
my $AddonRoot=tempdir(CLEANUP=>1);
my $PackagePath="$AddonRoot/knowledge-suggestions";
make_path("$PackagePath/programs");
$Config->{Paths}->{Addons}=$AddonRoot;
$DB->{Packages}=[{
 package_identifier=>'de.qisutu.knowledge-suggestions', installed_path=>$PackagePath, version=>'1.0.1',
 manifest_json=>JSON::PP->new->encode({id=>'de.qisutu.knowledge-suggestions',ui_slots=>[{slot=>'page.after',program=>'CustomerTicketCreate',class=>'Qisutu::Addon::KnowledgeSuggestions::UI',method=>'Render'}]}),
}];
for my $Page(qw(AdminKnowledgeSuggestions CustomerKnowledgeSuggestions)) {
 open my $FH,'>',"$PackagePath/programs/$Page.json" or die $!;
 print {$FH} JSON::PP->new->encode({Name=>$Page,Module=>'Qisutu::Addon::KnowledgeSuggestions::Portal',URL=>'index.pl?Page='.$Page});
 close $FH;
}
my $Runtime=QisutuAddonRuntime->Apply(Config=>$Config,DB=>$DB);
is_deeply($Runtime->{UISlots},[],'a valid installed legacy add-on does not contribute a second widget');
is_deeply($Runtime->{LanguagePaths},[],'legacy translations cannot override the native translations');
my $Registry=QisutuProgramRegistry->new(Config=>$Config,DB=>$DB,Output=>$Out);
for my $Page(qw(AdminKnowledgeSuggestions CustomerKnowledgeSuggestions)) {
 my @Programs=grep {$_->{Name} eq $Page} @{$Registry->Programs()};
 is(scalar @Programs,1,"$Page registered exactly once with the old add-on installed");
 is($Programs[0]->{Module},$Page,"$Page uses the core module");
}
done_testing();
