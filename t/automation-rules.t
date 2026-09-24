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
use JSON::PP qw(encode_json decode_json);
use Storable qw(dclone);
use lib "$FindBin::Bin/../core/system", "$FindBin::Bin/../core/module", "$FindBin::Bin/../core/output";
use QisutuAutomation;
use AdminAutomationRules;
use QisutuOutput;

{
    package Local::AutomationDB;
    sub new { return bless { rows => {}, calls => [] }, shift; }
    sub Error { return ''; }
    sub SelectAll {
        my ( $Self, $SQL, @Bind ) = @_;
        die "Unexpected query: $SQL" if $SQL !~ /FROM automation_rule/;
        return [ map { Storable::dclone($_) } grep { $_->{rule_type} eq $Bind[0] } values %{ $Self->{rows} } ];
    }
    sub SelectRow {
        my ( $Self, $SQL, @Bind ) = @_;
        die "Unexpected query: $SQL" if $SQL !~ /FROM automation_rule/;
        return $Self->{rows}{$Bind[0]} ? Storable::dclone( $Self->{rows}{$Bind[0]} ) : undef;
    }
    sub Do {
        my ( $Self, $SQL, @Bind ) = @_;
        push @{ $Self->{calls} }, [ $SQL, @Bind ];
        return undef if $Self->{fail};
        if ( $SQL =~ /UPDATE automation_rule\s+SET name/ ) {
            my $ID = pop @Bind;
            return '0E0' if !$Self->{rows}{$ID};
            my @Fields = qw(name description rule_type event_name conditions_json actions_json schedule_json next_run_at active sort_order changed_by_user_id);
            die 'Unexpected update values' if @Fields != @Bind;
            @{ $Self->{rows}{$ID} }{@Fields} = @Bind;
            return 1;
        }
        if ( $SQL eq 'DELETE FROM automation_rule WHERE id = ? AND rule_type = ?' ) {
            my $Row = $Self->{rows}{$Bind[0]};
            return '0E0' if !$Row || $Row->{rule_type} ne $Bind[1];
            delete $Self->{rows}{$Bind[0]};
            return 1;
        }
        die "Unexpected mutation: $SQL";
    }
}

my $Root = File::Spec->rel2abs( "$FindBin::Bin/.." );
my $Config = { Paths => { Output => "$Root/core/output", Language => "$Root/core/language" } };
my $Output = QisutuOutput->new( Config => $Config );
my $DB = Local::AutomationDB->new();
my $Object = QisutuAutomation->new( Config => $Config, DB => $DB );
my $Options = {
    Queues => [ { id => 1, name => 'Spam' }, { id => 2, name => 'Junk' }, { id => 3, name => 'Support' } ],
    States => [], Priorities => [], Customers => [], CustomerUsers => [], Owners => [], Responsibles => [],
    Services => [], SLAs => [], ChecklistTemplates => [], ChecklistItems => [], DynamicFields => [],
};

{
    no warnings 'redefine';
    local *QisutuAutomation::Options = sub { return $Options; };
    for my $Type (qw(schedule trigger)) {
        subtest "$Type rule queue changes and deletion" => sub {
            my $ID = $Type eq 'schedule' ? 7 : 8;
            my $Page = $Type eq 'schedule' ? 'AdminAutomationSchedules' : 'AdminAutomationTriggers';
            $DB->{rows}{$ID} = {
                id => $ID, name => 'Rule <test>', description => '', rule_type => $Type,
                event_name => 'ticket_created', active => 1, sort_order => 1000,
                conditions_json => encode_json({ Search => { QueueIDs => [1] } }),
                actions_json => encode_json({ QueueID => 3 }),
                schedule_json => encode_json({ type => 'every_minutes', interval_minutes => 15 }),
            };
            my $Module = AdminAutomationRules->new(
                Config => $Config, DB => $DB, Output => $Output, Program => { RuleType => $Type },
            );
            my $Request = $Module->_RequestFromRule( Rule => $Object->RuleGet( RuleID => $ID ) );
            $Request->{Step} = 'RuleUpdate';
            $Request->{ConditionQueueID} = 2;
            $Request->{__RequestMethod} = 'POST';
            $Request->{Language} = 'de';
            my $Saved = $Module->Run( Request => $Request, User => { user_account_id => 1 } );
            like( $Saved->{Redirect} || '', qr/Action=Edit;RuleID=$ID\z/, 'saving redirects back to the updated rule' );
            my $Reloaded = $Object->RuleGet( RuleID => $ID );
            is_deeply( $Reloaded->{conditions}{Search}{QueueIDs}, [2], 'new queue replaces the previous queue in stored conditions' );
            is( $Reloaded->{actions}{QueueID}, 3, 'changing the selection queue retains the target queue' );
            my $Edit = $Module->Run( Request => { Action => 'Edit', RuleID => $ID, Language => 'de' } );
            like( $Edit->{Data}{QueueOptionsHTML}, qr/value="2" selected/, 'reopened form selects the new queue' );
            unlike( $Edit->{Data}{QueueOptionsHTML}, qr/value="1" selected/, 'reopened form does not revert to the previous queue' );

            $Request->{ConditionQueueID} = [2, 3];
            $Request->{ActionQueueID} = 1;
            $Module->Run( Request => $Request, User => { user_account_id => 1 } );
            $Reloaded = $Object->RuleGet( RuleID => $ID );
            is_deeply( $Reloaded->{conditions}{Search}{QueueIDs}, [2, 3], 'multiple selection queues persist' );
            is( $Reloaded->{actions}{QueueID}, 1, 'the action target queue can also change' );

            delete $Request->{ConditionQueueID};
            $Module->Run( Request => $Request, User => { user_account_id => 1 } );
            is_deeply( $Object->RuleGet( RuleID => $ID )->{conditions}{Search}{QueueIDs}, [], 'clearing the queue selection persists' );

            my $List = $Module->Run( Request => { Language => 'de' } );
            $List->{Data}{CSRFToken} = 'test-csrf';
            $List->{Data}{Language} = 'de';
            $List->{Data}{StaticBase} = '/static';
            my $HTML = $Output->RenderSingle( Template => $List->{Template}, Data => $List->{Data} );
            like( $HTML, qr/method="post"[^>]*data-qisutu-automation-delete/, 'overview offers a deletion POST form' );
            like( $HTML, qr/name="CSRFToken" value="test-csrf"/, 'deletion form receives the CSRF token' );
            like( $HTML, qr/name="Step" value="RuleDelete"/, 'deletion form sends the deletion operation' );
            like( $HTML, qr/qisutu-automation[.]js/, 'overview loads deletion confirmation behavior' );
            like( $HTML, qr/Rule &lt;test&gt;/, 'rule names are escaped in the deletion prompt' );

            $Edit->{Data}{CSRFToken} = 'test-csrf';
            $HTML = $Output->RenderSingle( Template => $Edit->{Template}, Data => $Edit->{Data} );
            like( $HTML, qr{</form>\s*<form[^>]*data-qisutu-automation-delete}s, 'edit view uses a separate deletion form' );

            my $CallCount = scalar @{ $DB->{calls} };
            my $Denied = $Module->Run( Request => { Step => 'RuleDelete', RuleID => $ID, __RequestMethod => 'GET' } );
            like( $Denied->{Response}, qr/405 Method Not Allowed/, 'deletion by GET is rejected' );
            is( scalar @{ $DB->{calls} }, $CallCount, 'GET performs no mutation' );
            ok( !$Object->RuleDelete( RuleID => $ID, RuleType => $Type eq 'schedule' ? 'trigger' : 'schedule' ), 'wrong rule type cannot be deleted' );
            ok( $DB->{rows}{$ID}, 'wrong-type request preserves the rule' );

            $DB->{fail} = 1;
            my $Failed = $Module->Run( Request => { Step => 'RuleDelete', RuleID => $ID, __RequestMethod => 'POST' } );
            ok( $Failed->{Data}{ErrorMessage}, 'database failure is shown instead of reporting successful deletion' );
            ok( $DB->{rows}{$ID}, 'failed deletion preserves the rule' );
            $DB->{fail} = 0;
            my $Deleted = $Module->Run( Request => { Step => 'RuleDelete', RuleID => $ID, __RequestMethod => 'POST' } );
            is( $Deleted->{Redirect}, 'index.pl?Page=' . $Page, 'successful deletion returns to the matching overview' );
            ok( !exists $DB->{rows}{$ID}, 'deleted rule is removed' );
            ok( !$Object->RuleDelete( RuleID => $ID, RuleType => $Type ), 'already deleted rule is not reported as deleted again' );
        };
    }
}

for my $ID (undef, 0, -1, '7 OR 1=1', [7]) {
    my $CallCount = scalar @{ $DB->{calls} };
    ok( !$Object->RuleDelete( RuleID => $ID, RuleType => 'schedule' ), 'invalid rule ID is rejected' );
    is( scalar @{ $DB->{calls} }, $CallCount, 'invalid rule ID never reaches a database mutation' );
}

done_testing();
