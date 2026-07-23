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

use File::Spec;
use FindBin;
use Test::More;

use lib File::Spec->catdir( $FindBin::Bin, '..', 'core', 'module' );
use lib File::Spec->catdir( $FindBin::Bin, '..', 'core', 'output' );
use lib File::Spec->catdir( $FindBin::Bin, '..', 'core', 'system' );

use AgentTicketZoom;
use QisutuOutput;

my $Root = File::Spec->catdir( $FindBin::Bin, '..' );
my $Config = {
    Paths => {
        Language => File::Spec->catdir( $Root, 'core', 'language' ),
    },
    Language => { Default => 'de' },
};
my $Output = QisutuOutput->new( Config => $Config );
my $Module = AgentTicketZoom->new( Config => $Config, Output => $Output );

is(
    $Module->_ToolArticleSubject( Language => 'de', Action => 'close' ),
    'Notiz',
    'a close note uses the normal German note subject',
);
is(
    $Module->_ToolArticleSubject( Language => 'it', Action => 'close' ),
    'Nota',
    'the close note subject follows the agent language',
);

my $ManualBody = '<p>Abschluss nach Rücksprache mit dem Kunden.</p>';
my $CloseBody = $Module->_ToolArticleBody(
    Summary        => 'Ticket geschlossen: von "Offen" auf "Erfolgreich geschlossen"',
    Body           => $ManualBody,
    IncludeSummary => 0,
);

is( $CloseBody, $ManualBody, 'a close note contains only the manually entered text' );
unlike( $CloseBody, qr{Ticket geschlossen|Offen|Erfolgreich geschlossen}, 'the state transition is not duplicated in the article' );

my $OtherActionBody = $Module->_ToolArticleBody(
    Summary => 'Priorität geändert: von "2 normal" auf "3 hoch"',
    Body    => $ManualBody,
);
like( $OtherActionBody, qr{Priorität geändert}, 'summaries for other ticket tools remain unchanged' );

done_testing();
