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
use FindBin;
use File::Spec;
use Test::More;
use lib "$FindBin::Bin/../core/system", "$FindBin::Bin/../core/module", "$FindBin::Bin/../core/output";
use AgentKnowledgeBase;
use KnowledgeBase;
use QisutuOutput;
use QisutuProgramRegistry;
use QisutuDispatcher;

{
    package Local::NoKnowledgeAccessDB;
    sub new { return bless {}, shift; }
    sub AUTOLOAD { die 'Unauthorized request touched the database'; }
    sub DESTROY {}
}
my $Root=File::Spec->rel2abs("$FindBin::Bin/..");
my $Config={Paths=>{Config=>"$Root/core/config",ProgramConfig=>"$Root/core/config/programs",Language=>"$Root/core/language"}};
my $Output=QisutuOutput->new(Config=>$Config);
my $DB=Local::NoKnowledgeAccessDB->new();
my $Agent=AgentKnowledgeBase->new(Config=>$Config,Output=>$Output,DB=>$DB);
my $Parent=KnowledgeBase->new(Config=>$Config,Output=>$Output,DB=>$DB);
my $Registry=QisutuProgramRegistry->new(Config=>$Config);
my $Dispatcher=QisutuDispatcher->new(Config=>$Config,Output=>$Output,ProgramRegistry=>$Registry);
my $Customer={user_account_id=>2,customer_user_id=>1,account_type=>'customer'};
for my $User ($Customer,{}, {user_account_id=>2}, {account_type=>'agent'}) {
    for my $Request (
        {Step=>'SearchJSON',Query=>'VPN'}, {Step=>'ArticleGetJSON',ArticleID=>1},
        {Action=>'View',ArticleID=>1}, {Action=>'Edit',ArticleID=>1}, {Action=>'Create'},
        {Step=>'ArticleSave',ArticleID=>1,Content=>'<p>changed</p>'},
        {Step=>'CategorySave',CategoryID=>1}, {Step=>'CategoryToggle',CategoryID=>1,Active=>0},
        {Step=>'UsageRecord',ArticleID=>1},
    ) {
        my $Result=$Agent->Run(Request=>$Request,User=>$User);
        like($Result->{Response},qr{\AStatus: 403 Forbidden},'every agent operation denies non-agent or incomplete identity before DB access');
    }
}
my $Program=$Registry->ProgramGet(Name=>'KnowledgeBase');
is($Program->{Module},'KnowledgeBase','shared navigation uses safe landing module');
ok($Dispatcher->_PermissionCheck(Program=>$Program,User=>$Customer),'customer keeps access to navigation parent');
ok(!$Dispatcher->_PermissionCheck(Program=>$Registry->ProgramGet(Name=>'AgentKnowledgeBase'),User=>$Customer),'agent route denies customer');
for my $Step ('SearchJSON','ArticleGetJSON','ArticleSave','CategorySave','CategoryToggle') {
    my $Result=$Parent->Run(Request=>{Step=>$Step,ArticleID=>1},User=>$Customer);
    is($Result->{Redirect},'index.pl?Page=CustomerKnowledgeBase','shared customer route ignores all agent operation parameters');
}
is($Parent->Run(User=>{user_account_id=>1,account_type=>'agent'})->{Redirect},'index.pl?Page=AgentKnowledgeBase','agent landing route remains available');
like($Parent->Run(User=>{})->{Response},qr{\AStatus: 403 Forbidden},'unauthenticated parent request denied');
done_testing();
