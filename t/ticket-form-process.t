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
use lib "$FindBin::Bin/../core/config", "$FindBin::Bin/../core/system", "$FindBin::Bin/../core/output", "$FindBin::Bin/../core/cpan-lib";
use Test::More;

BEGIN {
    $INC{'Qisutu/Addon/KimProcesses/Runtime.pm'} = __FILE__;
    $INC{'Qisutu/Addon/KimProcesses/Process.pm'} = __FILE__;
}

{
    package Qisutu::Addon::KimProcesses::Runtime;
    our $Mode = 'error';
    sub new { return bless {}, shift }
    sub Start { return 77 }
    sub Error { return '' }
    sub InstanceGet {
        return $Mode eq 'error'
            ? { id => 77, status => 'error', last_error => 'First action failed' }
            : { id => 77, status => 'active', last_error => '' };
    }
}

{
    package Qisutu::Addon::KimProcesses::Process;
    sub new { return bless {}, shift }
    sub TemplateGet { return { id => 5, name => 'Onboarding' } }
}

{
    package Local::ProcessOutput;
    sub new { return bless {}, shift }
    sub Translate {
        my ( $Self, %Param ) = @_;
        return 'Process start failed' if $Param{Key} eq 'TicketFormProcessStartFailedSubject';
        return 'Process {process} failed: {error}' if $Param{Key} eq 'TicketFormProcessStartFailedBody';
        return $Param{Key};
    }
}

{
    package Local::ProcessTicket;
    sub new { return bless { Articles => [] }, shift }
    sub ArticleCreate {
        my ( $Self, %Param ) = @_;
        push @{ $Self->{Articles} }, \%Param;
        return 101;
    }
}

{
    package Local::ProcessDB;
    sub new { return bless {}, shift }
}

use QisutuTicketForm;

my $Object = QisutuTicketForm->new(
    Config => { Language => { Default => 'de' } },
    DB => Local::ProcessDB->new(),
    Output => Local::ProcessOutput->new(),
);
my $Ticket = Local::ProcessTicket->new();

{
    no warnings 'redefine';
    local *QisutuAddonManager::PackageGet = sub { return { active => 1, status => 'installed' } };
    local *QisutuAddonManager::SettingsGet = sub { return { enabled => 1, kim_api_token => 'secret' } };
    local $Qisutu::Addon::KimProcesses::Runtime::Mode = 'error';

    ok(
        $Object->_ProcessAutoStart(
            Form => { process_template_id => 5 }, TicketID => 44,
            TicketObject => $Ticket, Language => 'de',
        ),
        'a failed process start does not fail the ticket-form submission',
    );
}

is( scalar @{ $Ticket->{Articles} }, 1, 'a failed automatic process writes one ticket article' );
is( $Ticket->{Articles}->[0]->{Visibility}, 'agent', 'the failure article is internal' );
is( $Ticket->{Articles}->[0]->{Internal}, 1, 'the failure article carries the internal marker' );
like( $Ticket->{Articles}->[0]->{Body}, qr{Onboarding.*First action failed}, 'the internal note contains process name and error' );

{
    no warnings 'redefine';
    local *QisutuAddonManager::PackageGet = sub { return { active => 0, status => 'installed' } };
    ok(
        $Object->_ProcessAutoStart(
            Form => { process_template_id => 5 }, TicketID => 45,
            TicketObject => $Ticket, Language => 'de',
        ),
        'a disabled add-on is skipped without affecting the ticket',
    );
}
is( scalar @{ $Ticket->{Articles} }, 1, 'the disabled add-on does not create a failure note' );

open my $SchemaFH, '<:raw', "$FindBin::Bin/../install/sql/schema.sql" or die $!;
my $Schema = do { local $/; <$SchemaFH> };
close $SchemaFH;
like( $Schema, qr{process_template_id.*DEFAULT NULL}, 'the form-to-process mapping is stored without an add-on foreign key' );

done_testing();
