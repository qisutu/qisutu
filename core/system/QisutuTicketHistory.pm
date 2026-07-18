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

package QisutuTicketHistory;

use strict;
use warnings;
use utf8;
use JSON::PP qw(decode_json);

sub new {
    my ( $Class, %Param ) = @_;

    my $Self = {
        Config => $Param{Config},
        DB     => $Param{DB},
        Output => $Param{Output},
    };

    bless $Self, $Class;
    return $Self;
}

sub List {
    my ( $Self, %Param ) = @_;

    my $TicketID = $Param{TicketID} || 0;
    return { Items => [], HasMore => 0, NextBeforeID => 0 }
        if $TicketID !~ m{\A\d+\z} || !$TicketID;

    my $Category = $Param{Category} || 'all';
    my %AllowedCategory = map { $_ => 1 } qw(all change communication time system);
    $Category = 'all' if !$AllowedCategory{$Category};

    my $BeforeID = $Param{BeforeID} || 0;
    $BeforeID = 0 if $BeforeID !~ m{\A\d+\z};

    my $Limit = $Param{Limit} || 50;
    $Limit = 50 if $Limit !~ m{\A\d+\z} || $Limit < 1;
    $Limit = 100 if $Limit > 100;

    my @Where = ('ticket_id = ?');
    my @Bind  = ($TicketID);

    if ( $Category ne 'all' ) {
        push @Where, 'event_category = ?';
        push @Bind, $Category;
    }
    if ($BeforeID) {
        my $Cursor = $Self->{DB}->SelectRow(
            'SELECT id, created_at FROM ticket_history WHERE id = ? AND ticket_id = ? LIMIT 1',
            $BeforeID,
            $TicketID,
        );
        if ($Cursor) {
            push @Where, '(created_at < ? OR (created_at = ? AND id < ?))';
            push @Bind, $Cursor->{created_at}, $Cursor->{created_at}, $BeforeID;
        }
    }

    my $Rows = $Self->{DB}->SelectAll(
        'SELECT * FROM ticket_history WHERE '
            . join( ' AND ', @Where )
            . ' ORDER BY created_at DESC, id DESC LIMIT ' . int( $Limit + 1 ),
        @Bind,
    ) || [];

    my $HasMore = @{$Rows} > $Limit ? 1 : 0;
    pop @{$Rows} if $HasMore;

    return {
        Items        => $Rows,
        HasMore      => $HasMore,
        NextBeforeID => @{$Rows} ? ( $Rows->[-1]->{id} || 0 ) : 0,
    };
}

sub TimelineHTML {
    my ( $Self, %Param ) = @_;

    my $Items    = ref $Param{Items} eq 'ARRAY' ? $Param{Items} : [];
    my $Language = $Param{Language} || 'en';

    if ( !@{$Items} ) {
        return '<div class="qisutu-ticket-history-empty" data-qisutu-ticket-history-empty>'
            . $Self->_Escape( $Self->_Translate( Key => 'TicketHistoryEmpty', Language => $Language ) )
            . '</div>';
    }

    my $HTML = '';
    for my $Item ( @{$Items} ) {
        my $Category = $Item->{event_category} || 'system';
        $Category = 'system' if $Category !~ m{\A(?:change|communication|time|system)\z};

        my $Title = $Self->_Translate(
            Key      => $Self->_EventTitleKey( $Item->{event_type} ),
            Language => $Language,
        );
        my $Actor = $Item->{actor_name} || $Self->_Translate( Key => 'TicketHistorySystem', Language => $Language );
        my $Source = $Self->_Translate(
            Key      => $Self->_SourceKey( $Item->{source} ),
            Language => $Language,
        );
        my $DateTime = $Self->_DateTimeFormat(
            DateTime => $Item->{created_at},
            Language => $Language,
        );
        my $Initial = uc substr( $Actor || 'S', 0, 1 );

        $HTML .= '<article class="qisutu-ticket-history-entry qisutu-ticket-history-entry-'
            . $Self->_Escape($Category) . '" data-qisutu-ticket-history-entry="'
            . int( $Item->{id} || 0 ) . '">';
        $HTML .= '<div class="qisutu-ticket-history-marker" aria-hidden="true">'
            . $Self->_Escape($Initial) . '</div>';
        $HTML .= '<div class="qisutu-ticket-history-card">';
        $HTML .= '<header><div><strong>' . $Self->_Escape($Title) . '</strong>';
        if ( $Item->{is_backfill} ) {
            $HTML .= '<span class="qisutu-ticket-history-backfill">'
                . $Self->_Escape( $Self->_Translate( Key => 'TicketHistoryBackfill', Language => $Language ) )
                . '</span>';
        }
        $HTML .= '</div><time datetime="' . $Self->_Escape( $Item->{created_at} || '' ) . '">'
            . $Self->_Escape($DateTime) . '</time></header>';
        $HTML .= '<div class="qisutu-ticket-history-meta"><strong>' . $Self->_Escape($Actor)
            . '</strong><span>·</span><span>' . $Self->_Escape($Source) . '</span></div>';

        $HTML .= $Self->_ValueChangeHTML( Item => $Item, Language => $Language );
        $HTML .= $Self->_DetailsHTML( Item => $Item, Language => $Language );

        if ( $Item->{article_id} ) {
            $HTML .= '<a class="qisutu-ticket-history-link" href="#qisutu-ticket-article-'
                . int( $Item->{article_id} ) . '">'
                . $Self->_Escape( $Self->_Translate( Key => 'TicketHistoryOpenArticle', Language => $Language ) )
                . '</a>';
        }
        if ( $Item->{related_ticket_id} ) {
            my $Number = $Item->{new_display} || ( '#' . $Item->{related_ticket_id} );
            $HTML .= '<a class="qisutu-ticket-history-link" href="index.pl?Page=AgentTicketZoom&amp;TicketID='
                . int( $Item->{related_ticket_id} ) . '">'
                . $Self->_Escape( $Self->_Translate( Key => 'TicketHistoryRelatedTicket', Language => $Language ) )
                . ': ' . $Self->_Escape($Number) . '</a>';
        }
        $HTML .= '</div></article>';
    }

    return $HTML;
}

sub _ValueChangeHTML {
    my ( $Self, %Param ) = @_;

    my $Item     = $Param{Item} || {};
    my $Language = $Param{Language} || 'en';
    my $Old = defined $Item->{old_display} && $Item->{old_display} ne ''
        ? $Item->{old_display}
        : $Item->{old_value};
    my $New = defined $Item->{new_display} && $Item->{new_display} ne ''
        ? $Item->{new_display}
        : $Item->{new_value};

    return '' if ( $Item->{event_category} || '' ) ne 'change';
    return '' if ( !defined $Old || $Old eq '' ) && ( !defined $New || $New eq '' );

    $Old = $Self->_DisplayValue(
        Field    => $Item->{field_name},
        Value    => $Old,
        Language => $Language,
    ) if defined $Old && $Old ne '';
    $New = $Self->_DisplayValue(
        Field    => $Item->{field_name},
        Value    => $New,
        Language => $Language,
    ) if defined $New && $New ne '';

    $Old = $Self->_Translate( Key => 'TicketHistoryEmptyValue', Language => $Language )
        if !defined $Old || $Old eq '';
    $New = $Self->_Translate( Key => 'TicketHistoryEmptyValue', Language => $Language )
        if !defined $New || $New eq '';

    my $Field = '';
    if ( ( $Item->{event_type} || '' ) eq 'dynamic_field_changed' && $Item->{details_text} ) {
        $Field = $Item->{details_text};
    }

    my $HTML = '<div class="qisutu-ticket-history-change">';
    if ($Field) {
        $HTML .= '<span class="qisutu-ticket-history-field">' . $Self->_Escape($Field) . '</span>';
    }
    $HTML .= '<div><span class="qisutu-ticket-history-old">' . $Self->_Escape($Old)
        . '</span><span class="qisutu-ticket-history-arrow" aria-hidden="true">→</span><strong>'
        . $Self->_Escape($New) . '</strong></div></div>';
    return $HTML;
}

sub _DisplayValue {
    my ( $Self, %Param ) = @_;
    my $Field    = $Param{Field} || '';
    my $Value    = defined $Param{Value} ? $Param{Value} : '';
    my $Language = $Param{Language} || 'en';

    if ( $Field eq 'pending_until' && $Value =~ m{\A\d{4}-\d{2}-\d{2}\s+\d{2}:\d{2}:\d{2}\z} ) {
        return $Self->_DateTimeFormat( DateTime => $Value, Language => $Language );
    }

    my $Key = lc $Value;
    $Key =~ s{\A\s+|\s+\z}{}g;
    if ( $Field eq 'state_id' ) {
        $Key =~ s{\+}{ plus }g;
        $Key =~ s{-}{ minus }g;
        $Key =~ s{[^a-z0-9]+}{_}g;
        $Key =~ s{\A_+|_+\z}{}g;
        if ($Key) {
            my $TranslationKey = 'TicketStateName_' . $Key;
            my $Translated = $Self->_Translate( Key => $TranslationKey, Language => $Language );
            return $Translated ne $TranslationKey ? $Translated : $Value;
        }
    }
    if ( $Field eq 'priority_id' ) {
        $Key =~ s{[^a-z0-9]+}{_}g;
        $Key =~ s{\A_+|_+\z}{}g;
        if ($Key) {
            my $TranslationKey = 'TicketPriorityName_' . $Key;
            my $Translated = $Self->_Translate( Key => $TranslationKey, Language => $Language );
            return $Translated ne $TranslationKey ? $Translated : $Value;
        }
    }
    return $Value;
}

sub _DetailsHTML {
    my ( $Self, %Param ) = @_;

    my $Item     = $Param{Item} || {};
    my $Language = $Param{Language} || 'en';
    my $Details  = $Item->{details_text} || '';
    return '' if !$Details;

    return '' if ( $Item->{event_type} || '' ) eq 'ticket_created' && $Item->{is_backfill};
    return '' if ( $Item->{event_type} || '' ) eq 'article_created';
    return '' if ( $Item->{event_type} || '' ) eq 'dynamic_field_changed';
    return '' if $Item->{related_ticket_id} && $Details eq ( $Item->{new_display} || '' );

    if ( ( $Item->{event_type} || '' ) eq 'time_added' ) {
        my $Billable = $Details =~ s{\s*\[billable\]\s*\z}{} ? 1 : 0;
        $Details =~ s{\s*\[not billable\]\s*\z}{};
        my $Label = $Self->_Translate(
            Key      => $Billable ? 'TicketHistoryBillable' : 'TicketHistoryNotBillable',
            Language => $Language,
        );
        return '<div class="qisutu-ticket-history-details"><span>' . $Self->_Escape($Label) . '</span>'
            . ( $Details ne '' ? '<p>' . $Self->_Escape($Details) . '</p>' : '' ) . '</div>';
    }

    if ( ( $Item->{event_type} || '' ) eq 'bulk_action' ) {
        my ( $Reason, $JSONText ) = ( $Details, '' );
        if ( $Details =~ m{(\[[\s\S]*\])\s*\z} ) {
            $JSONText = $1;
            $Reason = substr( $Details, 0, length($Details) - length($JSONText) );
            $Reason =~ s{\s+\z}{};
        }
        my $Changes = $JSONText ? eval { decode_json($JSONText) } : [];
        my $HTML = '<div class="qisutu-ticket-history-details">';
        if ($Reason) {
            $HTML .= '<p>' . $Self->_Escape($Reason) . '</p>';
        }
        if ( ref $Changes eq 'ARRAY' && @{$Changes} ) {
            $HTML .= '<ul>';
            for my $Change ( @{$Changes} ) {
                next if ref $Change ne 'HASH';
                my $Label = $Change->{label_key}
                    ? $Self->_Translate( Key => $Change->{label_key}, Language => $Language )
                    : ( $Change->{field} || '' );
                $HTML .= '<li><span>' . $Self->_Escape($Label) . '</span><strong>'
                    . $Self->_Escape( $Change->{old_value} || '-' ) . ' → '
                    . $Self->_Escape( $Change->{new_value} || '-' ) . '</strong></li>';
            }
            $HTML .= '</ul>';
        }
        $HTML .= '</div>';
        return $HTML;
    }

    return '<div class="qisutu-ticket-history-details"><p>' . $Self->_Escape($Details) . '</p></div>';
}

sub _EventTitleKey {
    my ( $Self, $EventType ) = @_;
    my %Map = (
        ticket_created         => 'TicketHistoryEventCreated',
        title_changed          => 'TicketHistoryEventTitleChanged',
        queue_changed          => 'TicketHistoryEventQueueChanged',
        state_changed          => 'TicketHistoryEventStateChanged',
        priority_changed       => 'TicketHistoryEventPriorityChanged',
        customer_changed       => 'TicketHistoryEventCustomerChanged',
        customer_user_changed  => 'TicketHistoryEventCustomerUserChanged',
        owner_changed          => 'TicketHistoryEventOwnerChanged',
        responsible_changed    => 'TicketHistoryEventResponsibleChanged',
        service_changed        => 'TicketHistoryEventServiceChanged',
        sla_changed            => 'TicketHistoryEventSLAChanged',
        pending_changed        => 'TicketHistoryEventPendingChanged',
        article_created        => 'TicketHistoryEventArticleCreated',
        attachment_added       => 'TicketHistoryEventAttachmentAdded',
        dynamic_field_changed  => 'TicketHistoryEventDynamicFieldChanged',
        time_added             => 'TicketHistoryEventTimeAdded',
        time_cancelled         => 'TicketHistoryEventTimeCancelled',
        ticket_linked          => 'TicketHistoryEventLinked',
        ticket_split           => 'TicketHistoryEventSplit',
        ticket_merged          => 'TicketHistoryEventMerged',
        cmdb_ci_linked         => 'TicketHistoryEventCMDBLinked',
        cmdb_ci_unlinked       => 'TicketHistoryEventCMDBUnlinked',
        checklist_added        => 'TicketHistoryEventChecklistAdded',
        checklist_removed      => 'TicketHistoryEventChecklistRemoved',
        item_completed         => 'TicketHistoryEventChecklistItemCompleted',
        item_reopened          => 'TicketHistoryEventChecklistItemReopened',
        checklist_completed    => 'TicketHistoryEventChecklistCompleted',
        close_blocked          => 'TicketHistoryEventCloseBlocked',
        form_submitted         => 'TicketHistoryEventFormSubmitted',
        bulk_action            => 'TicketHistoryEventBulkAction',
    );
    return $Map{ $EventType || '' } || 'TicketHistoryEventChanged';
}

sub _SourceKey {
    my ( $Self, $Source ) = @_;
    my %Map = (
        application => 'TicketHistorySourceApplication',
        email       => 'TicketHistorySourceEmail',
        note        => 'TicketHistorySourceNote',
        web         => 'TicketHistorySourceWeb',
        customer_portal => 'TicketHistorySourceCustomerPortal',
        webform         => 'TicketHistorySourceWebForm',
        bulk        => 'TicketHistorySourceBulk',
        automation  => 'TicketHistorySourceAutomation',
        migration   => 'TicketHistorySourceMigration',
        checklist   => 'TicketHistorySourceChecklist',
        manual      => 'TicketHistorySourceManual',
        correction  => 'TicketHistorySourceCorrection',
        split       => 'TicketHistorySourceSplit',
        merge       => 'TicketHistorySourceMerge',
        related     => 'TicketHistorySourceLink',
        attachment  => 'TicketHistorySourceAttachment',
    );
    return $Map{ $Source || '' } || 'TicketHistorySourceApplication';
}

sub _DateTimeFormat {
    my ( $Self, %Param ) = @_;
    my $Value    = $Param{DateTime} || '';
    my $Language = $Param{Language} || 'en';

    if ( $Value =~ m{\A(\d{4})-(\d{2})-(\d{2})\s+(\d{2}):(\d{2}):(\d{2})\z} ) {
        return $Language eq 'de'
            ? "$3.$2.$1 $4:$5:$6"
            : "$1-$2-$3 $4:$5:$6";
    }
    return $Value;
}

sub _Translate {
    my ( $Self, %Param ) = @_;
    return $Self->{Output}->Translate(%Param) if $Self->{Output};
    return $Param{Key} || '';
}

sub _Escape {
    my ( $Self, $Value ) = @_;
    $Value = '' if !defined $Value;
    return $Self->{Output}->HTMLEscape($Value) if $Self->{Output};
    $Value =~ s{&}{&amp;}g;
    $Value =~ s{<}{&lt;}g;
    $Value =~ s{>}{&gt;}g;
    $Value =~ s{"}{&quot;}g;
    $Value =~ s{'}{&#39;}g;
    return $Value;
}

1;
