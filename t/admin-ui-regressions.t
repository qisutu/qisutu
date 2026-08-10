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

my $Root = File::Spec->catdir( $FindBin::Bin, '..' );

sub content {
    my (@Parts) = @_;
    my $Path = File::Spec->catfile( $Root, @Parts );

    open my $FH, '<:encoding(UTF-8)', $Path or die "Cannot read $Path: $!";
    local $/;
    my $Content = <$FH>;
    close $FH;

    return $Content;
}

my $German = content( 'core', 'language', 'de.pm' );
unlike( $German, qr{Kundenbenutz}, 'the German UI no longer uses the old customer-user term' );
like( $German, qr{AdminCustomerUsersTitle\s*=>\s*'Ansprechpartner'}, 'the administration navigation says Ansprechpartner' );
like( $German, qr{AdminCustomerUserFieldCreate\s*=>\s*'Ansprechpartnerfeld anlegen'}, 'related field labels use Ansprechpartner consistently' );

my $Notification = content( 'core', 'system', 'QisutuNotification.pm' );
my $AutoResponse = content( 'core', 'system', 'QisutuCustomerAutoResponse.pm' );
unlike( $Notification . $AutoResponse, qr{Kundenbenutz}, 'visible placeholder descriptions also use Ansprechpartner' );

my $Head = content( 'core', 'output', 'Head.tt' );
my $Footer = content( 'core', 'output', 'Footer.tt' );
like( $Head, qr{css/qisutu[.]css[?]v=\[% SystemVersion %\]}, 'the main stylesheet cache follows the installed Qisutu version' );
like( $Footer, qr{js/qisutu-sidebar[.]js[?]v=\[% SystemVersion %\]}, 'the sidebar script cache follows the installed Qisutu version' );

my $Sidebar = content( 'var', 'static', 'js', 'qisutu-sidebar.js' );
like( $Sidebar, qr{qisutu[.]sidebar[.]scrollTop}, 'the navigation scroll position has its own session key' );
like( $Sidebar, qr{sessionStorage[.]setItem\(ScrollStorageKey}, 'the navigation scroll position is stored' );
like( $Sidebar, qr{Navigation[.]scrollTop = StoredPosition}, 'the navigation scroll position is restored after a page change' );
like( $Sidebar, qr{qisutu-subnav-item-active}, 'the active administration item is brought into view without stored state' );

my $QueueTemplate = content( 'core', 'output', 'AdminQueues.tt' );
my $QueueCSS = content( 'var', 'static', 'css', 'qisutu.css' );
my $FieldsetCount = () = $QueueTemplate =~ /<fieldset class="qisutu-admin-radio-group">/g;
is( $FieldsetCount, 2, 'queue creation and editing use the radio-card fieldset' );
like( $QueueCSS, qr![.]qisutu-admin-radio-group\s*\{[^}]*display:\s*grid!s, 'queue follow-up choices are stacked in a grid' );
like( $QueueCSS, qr![.]qisutu-admin-radio-group label\s*\{[^}]*display:\s*flex!s, 'each queue follow-up choice has a separate card layout' );

my $AgentTemplate = content( 'core', 'output', 'AdminAgents.tt' );
like( $AgentTemplate, qr{qisutu-admin-agent-list-table}, 'the agent overview uses its bounded table layout' );
like( $QueueCSS, qr![.]qisutu-admin-agent-list-table\s*\{[^}]*table-layout:\s*fixed!s, 'the agent table cannot widen the complete workspace' );
like( $QueueCSS, qr![.]qisutu-admin-agent-list-table th,\s*[.]qisutu-admin-agent-list-table td\s*\{[^}]*overflow-wrap:\s*anywhere!s, 'long group lists wrap inside the agent table' );
like( $QueueCSS, qr![.]qisutu-ticket-form-fields select\[multiple\]\s*\{[^}]*height:\s*auto[^}]*min-height:\s*132px!s, 'customer-form multiselects retain their visible multi-row height' );

my $TicketListTemplate = content( 'core', 'output', 'AgentTicketList.tt' );
like( $TicketListTemplate, qr{name="Step" value="TicketListDefaultViewSave"}, 'the agent ticket list contains the explicit default-view button' );

for my $Language (qw(de en fr it nl pl pt-BR pt-PT es cs tr)) {
    my $LanguageContent = content( 'core', 'language', $Language . '.pm' );
    like( $LanguageContent, qr{TicketListSaveDefaultView\s*=>}, "the default-view button is translated in $Language" );
    like( $LanguageContent, qr{TicketChecklistDetails\s*=>}, "the checklist details button is translated in $Language" );
    like( $LanguageContent, qr{TicketChecklistDetailsTitle\s*=>}, "the checklist details title is translated in $Language" );
    like( $LanguageContent, qr{TicketChangeAccessDenied\s*=>}, "the read-only ticket error is translated in $Language" );
}

my $ChecklistAdminJS = content( 'var', 'static', 'js', 'qisutu-checklists-admin.js' );
like( $ChecklistAdminJS, qr{qisutu-checklist-drag-handle[^\n]+draggable}, 'only the checklist drag handle is draggable' );
unlike( $ChecklistAdminJS, qr{row[.]setAttribute\('draggable'}, 'the complete checklist row is no longer draggable' );
like( $ChecklistAdminJS, qr{addEventListener\('drop'.*?preventDefault}s, 'checklist drops are consumed instead of inserting transfer text into fields' );
like( $ChecklistAdminJS, qr{data-label-save}, 'new checklist rows include their explicit save action' );

my $ChecklistAdminModule = content( 'core', 'module', 'AdminChecklists.pm' );
like( $ChecklistAdminModule, qr{qisutu-checklist-admin-item-actions}, 'existing checklist rows include explicit save and remove actions' );

my $TicketZoomModule = content( 'core', 'module', 'AgentTicketZoom.pm' );
like( $TicketZoomModule, qr{data-qisutu-checklist-details-open}, 'ticket checklist items expose the details overlay button' );
like( $TicketZoomModule, qr{\$Action ne 'service' && !\$Self->_BodyHasVisibleContent}, 'service changes can be saved without an additional editor note' );

my $TicketZoomTemplate = content( 'core', 'output', 'AgentTicketZoom.tt' );
unlike( $TicketZoomTemplate, qr{id="qisutu-ticket-tool-service-body"[^>]*\brequired\b}, 'the hidden service editor field no longer blocks the save button' );

like( $QueueCSS, qr![.]qisutu-automation-form\s*\{[^}]*max-width:\s*none!s, 'automation trigger forms use the available workspace width' );
like( $QueueCSS, qr![.]qisutu-ticket-checklist-item-meta\s*\{[^}]*flex-direction:\s*column!s, 'checklist details are placed below the required badge' );

my $TicketSystem = content( 'core', 'system', 'QisutuTicket.pm' );
unlike( $TicketSystem, qr{Ticket change access denied}, 'the raw English read-only ticket error is no longer emitted' );
like( $TicketSystem, qr{Translate:TicketChangeAccessDenied}, 'ticket change denial uses the translated message key' );

done_testing();
