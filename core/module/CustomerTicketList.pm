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

package CustomerTicketList;

use strict;
use warnings;
use utf8;

sub new {
    my ( $Class, %Param ) = @_;

    my $Self = {
        Config  => $Param{Config},
        DB      => $Param{DB},
        Output  => $Param{Output},
        Program => $Param{Program},
    };

    bless $Self, $Class;

    return $Self;
}

sub Run {
    my ( $Self, %Param ) = @_;

    my $Request      = $Param{Request} || {};
    my $User         = $Param{User} || {};
    my $Language     = $Request->{Language} || 'en';
    my $TicketObject = $Self->_TicketObject();
    my $PerPageExplicit = $Self->_PerPageIsValid( $Request->{PerPage} );
    my $PerPage = $Self->_PerPageClean( $Request->{PerPage} );
    my $ListPage = $Self->_ListPageClean( $Request->{ListPage} );
    my $Tickets = [];
    my $TicketCount = 0;

    if ($TicketObject) {
        $TicketCount = $TicketObject->TicketListCount(
            User => $User,
        );

        my $TotalPages = $TicketCount > 0
            ? int( ( $TicketCount + $PerPage - 1 ) / $PerPage )
            : 1;
        $ListPage = $TotalPages if $ListPage > $TotalPages;
        $ListPage = 1 if $ListPage < 1;

        if ($TicketCount) {
            $Tickets = $TicketObject->TicketList(
                Limit    => $PerPage,
                Offset   => ( $ListPage - 1 ) * $PerPage,
                User     => $User,
                ZoomPage => 'CustomerTicketZoom',
                Language => $Language,
            );
        }
    }

    my $TotalPages = $TicketCount > 0
        ? int( ( $TicketCount + $PerPage - 1 ) / $PerPage )
        : 1;
    my $Context = {
        PerPage  => $PerPage,
        ListPage => $ListPage,
    };
    my $PaginationHTML = $Self->_PaginationHTML(
        Context     => $Context,
        CurrentPage => $ListPage,
        TotalPages  => $TotalPages,
        Language    => $Language,
    );

    return {
        Template => 'CustomerTicketList.tt',
        Data     => {
            PageTitle          => 'Translate:CustomerTicketListTitle',
            ProgramTitle       => 'Translate:CustomerTicketListTitle',
            ProgramDescription => 'Translate:ProgramTicketsDescription',
            Tickets            => $Tickets,
            HasTickets         => scalar @{$Tickets} ? 1 : 0,
            TicketCount        => $TicketCount,
            CustomerTicketCreateURL => 'index.pl?Page=CustomerTicketCreate',
            PerPageHTML => $Self->_PerPageHTML(
                Context         => $Context,
                Language        => $Language,
                UserAccountID   => $User->{user_account_id} || 0,
                PerPageExplicit => $PerPageExplicit,
            ),
            PaginationTopHTML    => $PaginationHTML,
            PaginationBottomHTML => $PaginationHTML,
        },
    };
}

sub _PerPageHTML {
    my ( $Self, %Param ) = @_;

    my $Context         = $Param{Context} || {};
    my $Language        = $Param{Language} || 'en';
    my $UserAccountID   = $Param{UserAccountID} || 0;
    my $PerPageExplicit = $Param{PerPageExplicit} ? 1 : 0;
    my $Selected        = $Self->_PerPageClean( $Context->{PerPage} );
    my $StorageKey      = 'qisutu.ticketList.perPage.customer.' . $UserAccountID;

    my $HTML = '<form class="qisutu-ticket-list-per-page-form" method="get" action="index.pl"';
    $HTML .= ' data-qisutu-ticket-list-per-page-form';
    $HTML .= ' data-qisutu-ticket-list-per-page-storage="' . $Self->_Escape($StorageKey) . '"';
    $HTML .= ' data-qisutu-ticket-list-per-page-explicit="' . $PerPageExplicit . '">';
    $HTML .= '<input type="hidden" name="Page" value="CustomerTicketList">';
    $HTML .= '<label class="qisutu-ticket-list-per-page-label">';
    $HTML .= '<span>' . $Self->_Escape( $Self->_Translate( Key => 'TicketListPerPage', Language => $Language ) ) . '</span>';
    $HTML .= '<select name="PerPage" data-qisutu-ticket-list-per-page>';

    for my $Value ( 10, 20, 30, 40, 50 ) {
        my $SelectedAttribute = $Value == $Selected ? ' selected' : '';
        $HTML .= '<option value="' . $Value . '"' . $SelectedAttribute . '>' . $Value . '</option>';
    }

    $HTML .= '</select></label></form>';

    return $HTML;
}

sub _PaginationHTML {
    my ( $Self, %Param ) = @_;

    my $Context     = $Param{Context} || {};
    my $CurrentPage = $Self->_ListPageClean( $Param{CurrentPage} );
    my $TotalPages  = $Self->_ListPageClean( $Param{TotalPages} );
    my $Language    = $Param{Language} || 'en';

    return '' if $TotalPages <= 1;

    $CurrentPage = $TotalPages if $CurrentPage > $TotalPages;

    my @PageItems;
    if ( $TotalPages <= 7 ) {
        @PageItems = ( 1 .. $TotalPages );
    }
    else {
        my %Page = ( 1 => 1, $TotalPages => 1 );
        for my $Number ( $CurrentPage - 2 .. $CurrentPage + 2 ) {
            next if $Number < 1 || $Number > $TotalPages;
            $Page{$Number} = 1;
        }

        my $Previous = 0;
        for my $Number ( sort { $a <=> $b } keys %Page ) {
            push @PageItems, 'ellipsis' if $Previous && $Number > $Previous + 1;
            push @PageItems, $Number;
            $Previous = $Number;
        }
    }

    my $Label = $Self->_Translate( Key => 'TicketListPaginationLabel', Language => $Language );
    my $HTML = '<nav class="qisutu-ticket-list-pagination" aria-label="' . $Self->_Escape($Label) . '">';
    $HTML .= '<span class="qisutu-ticket-list-pagination-label">' . $Self->_Escape( $Self->_Translate( Key => 'TicketListPage', Language => $Language ) ) . '</span>';

    if ( $CurrentPage > 1 ) {
        $HTML .= '<a class="qisutu-ticket-list-page-link qisutu-ticket-list-page-direction" href="' . $Self->_Escape( $Self->_ListURL( PerPage => $Context->{PerPage}, ListPage => $CurrentPage - 1 ) ) . '" aria-label="' . $Self->_Escape( $Self->_Translate( Key => 'TicketListPreviousPage', Language => $Language ) ) . '">‹</a>';
    }

    for my $Item (@PageItems) {
        if ( $Item eq 'ellipsis' ) {
            $HTML .= '<span class="qisutu-ticket-list-page-ellipsis" aria-hidden="true">…</span>';
            next;
        }

        if ( $Item == $CurrentPage ) {
            $HTML .= '<span class="qisutu-ticket-list-page-link qisutu-ticket-list-page-active" aria-current="page">' . $Item . '</span>';
            next;
        }

        $HTML .= '<a class="qisutu-ticket-list-page-link" href="' . $Self->_Escape( $Self->_ListURL( PerPage => $Context->{PerPage}, ListPage => $Item ) ) . '">' . $Item . '</a>';
    }

    if ( $CurrentPage < $TotalPages ) {
        $HTML .= '<a class="qisutu-ticket-list-page-link qisutu-ticket-list-page-direction" href="' . $Self->_Escape( $Self->_ListURL( PerPage => $Context->{PerPage}, ListPage => $CurrentPage + 1 ) ) . '" aria-label="' . $Self->_Escape( $Self->_Translate( Key => 'TicketListNextPage', Language => $Language ) ) . '">›</a>';
    }

    $HTML .= '</nav>';

    return $HTML;
}

sub _ListURL {
    my ( $Self, %Param ) = @_;

    my @Part = (
        'Page=CustomerTicketList',
        'PerPage=' . $Self->_URLEncode( $Self->_PerPageClean( $Param{PerPage} ) ),
    );
    push @Part, 'ListPage=' . $Self->_URLEncode( $Param{ListPage} ) if ( $Param{ListPage} || 1 ) > 1;

    return 'index.pl?' . join( ';', @Part );
}

sub _PerPageIsValid {
    my ( $Self, $Value ) = @_;

    return defined $Value && $Value =~ m{\A(?:10|20|30|40|50)\z} ? 1 : 0;
}

sub _PerPageClean {
    my ( $Self, $Value ) = @_;

    return int($Value) if $Self->_PerPageIsValid($Value);
    return 20;
}

sub _ListPageClean {
    my ( $Self, $Value ) = @_;

    return 1 if !defined $Value || $Value !~ m{\A\d+\z} || $Value < 1;
    return int($Value);
}

sub _TicketObject {
    my ($Self) = @_;

    return if !$Self->{DB};

    my $Loaded = eval {
        require QisutuPermission;
        require QisutuTicket;
        1;
    };

    if ( !$Loaded ) {
        return;
    }

    my $PermissionObject = QisutuPermission->new(
        Config => $Self->{Config},
        DB     => $Self->{DB},
    );

    return QisutuTicket->new(
        Config     => $Self->{Config},
        DB         => $Self->{DB},
        Permission => $PermissionObject,
    );
}

sub _Translate {
    my ( $Self, %Param ) = @_;

    return $Self->{Output}->Translate(
        Key      => $Param{Key},
        Language => $Param{Language} || 'en',
    );
}

sub _Escape {
    my ( $Self, $Value ) = @_;

    return $Self->{Output}->HTMLEscape( defined $Value ? $Value : '' );
}

sub _URLEncode {
    my ( $Self, $Value ) = @_;

    $Value = '' if !defined $Value;
    $Value = "$Value";
    utf8::encode($Value) if utf8::is_utf8($Value);
    $Value =~ s{([^A-Za-z0-9_.~-])}{sprintf '%%%02X', ord($1)}eg;

    return $Value;
}

1;
