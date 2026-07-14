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

package AgentTicketList;

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
    my $User         = $Param{User}    || {};
    my $Language     = $Request->{Language} || 'en';
    my $TicketObject = $Self->_TicketObject();
    my $PreferenceObject = $Self->_PreferenceObject();
    my $Preference = $PreferenceObject
        ? $PreferenceObject->AgentPreferenceGet( UserAccountID => $User->{user_account_id} )
        : {};

    my $SearchOptions = $TicketObject
        ? $TicketObject->TicketSearchOptions( User => $User, Language => $Language )
        : $Self->_EmptySearchOptions();
    my $Search = $Self->_SearchClean(
        Request       => $Request,
        DynamicFields => $SearchOptions->{DynamicFields},
    );
    my $SearchActive = $Search->{Active} ? 1 : 0;

    my $DynamicFields = $TicketObject
        ? $TicketObject->TicketListDynamicFieldList( Language => $Language )
        : [];
    my $ColumnDefinitions = $Self->_ColumnDefinitions(
        DynamicFields => $DynamicFields,
        Language      => $Language,
    );
    my $AllowedColumn = { map { $_->{key} => $_ } @{$ColumnDefinitions} };

    my $View = $Self->_ViewClean( $Request->{View}, SearchActive => $SearchActive );
    my $FilterQueueID        = $Self->_FilterIDClean( $Request->{FilterQueueID} );
    my $FilterCustomerID     = $Self->_FilterIDClean( $Request->{FilterCustomerID} );
    my $FilterCustomerUserID = $Self->_FilterIDClean( $Request->{FilterCustomerUserID} );
    my $FilterOwnerID        = $Self->_OwnerFilterClean( $Request->{FilterOwnerID} );
    my $SortBy = $Self->_SortByClean(
        SortBy        => $Request->{SortBy},
        AllowedColumn => $AllowedColumn,
    );
    my $SortDirection = $Self->_SortDirectionClean( $Request->{SortDirection} );
    my $PerPageExplicit = $Self->_PerPageIsValid( $Request->{PerPage} );
    my $PerPage = $Self->_PerPageClean(
        Value   => $Request->{PerPage},
        Default => $Self->_TicketListLimit( User => $User, Preference => $Preference ),
    );
    my $ListPage = $Self->_ListPageClean( $Request->{ListPage} );

    if ( $PreferenceObject && ( $Request->{Step} || '' ) eq 'TicketListColumnsSave' ) {
        my @Selected;

        for my $Column ( @{$ColumnDefinitions} ) {
            my $Key = $Column->{key};
            next if !$Request->{ 'Column_' . $Key };
            push @Selected, $Key;
        }

        @Selected = @{ $Self->_DefaultColumnKeys() } if !@Selected;

        $PreferenceObject->Set(
            UserAccountID => $User->{user_account_id},
            Key           => 'ticket_list_columns',
            Value         => join( ',', @Selected ),
        );

        if ( !$PreferenceObject->Error() ) {
            return {
                Redirect => $Self->_ListURL(
                    View                 => $View,
                    FilterQueueID        => $FilterQueueID,
                    FilterCustomerID     => $FilterCustomerID,
                    FilterCustomerUserID => $FilterCustomerUserID,
                    FilterOwnerID        => $FilterOwnerID,
                    SortBy               => $SortBy,
                    SortDirection        => $SortDirection,
                    PerPage              => $PerPage,
                    ListPage             => $ListPage,
                    Search               => $Search,
                ),
            };
        }
    }

    my $SelectedColumnKeys = $Self->_SelectedColumnKeys(
        Value         => $Preference->{ticket_list_columns},
        AllowedColumn => $AllowedColumn,
    );
    my %SelectedColumn = map { $_ => 1 } @{$SelectedColumnKeys};
    my @VisibleColumns = grep { $SelectedColumn{ $_->{key} } } @{$ColumnDefinitions};

    if ( !$SelectedColumn{$SortBy} ) {
        $SortBy = 'changed';
        $SortDirection = 'desc';
    }

    my $Tickets = [];
    my $TicketCount = 0;
    my $FilterOptions = {
        Queues        => [],
        Customers     => [],
        CustomerUsers => [],
        Owners        => [],
    };

    if ($TicketObject) {
        $FilterOptions = $TicketObject->TicketListFilterOptions(
            User => $User,
        );

        $TicketCount = $TicketObject->TicketListCount(
            User                 => $User,
            View                 => $View,
            FilterQueueID        => $FilterQueueID,
            FilterCustomerID     => $FilterCustomerID,
            FilterCustomerUserID => $FilterCustomerUserID,
            FilterOwnerID        => $FilterOwnerID,
            Search               => $Search,
        );

        my $TotalPages = $TicketCount > 0
            ? int( ( $TicketCount + $PerPage - 1 ) / $PerPage )
            : 1;
        $ListPage = $TotalPages if $ListPage > $TotalPages;
        $ListPage = 1 if $ListPage < 1;

        my @VisibleDynamicFields = grep { $_->{dynamic} } @VisibleColumns;

        if ($TicketCount) {
            $Tickets = $TicketObject->TicketList(
                Limit                => $PerPage,
                Offset               => ( $ListPage - 1 ) * $PerPage,
                User                 => $User,
                ZoomPage             => 'AgentTicketZoom',
                Language             => $Language,
                View                 => $View,
                FilterQueueID        => $FilterQueueID,
                FilterCustomerID     => $FilterCustomerID,
                FilterCustomerUserID => $FilterCustomerUserID,
                FilterOwnerID        => $FilterOwnerID,
                SortBy               => $SortBy,
                SortDirection        => $SortDirection,
                DynamicFields        => \@VisibleDynamicFields,
                Search               => $Search,
            );
        }
    }

    my $TotalPages = $TicketCount > 0
        ? int( ( $TicketCount + $PerPage - 1 ) / $PerPage )
        : 1;

    my $Context = {
        View                 => $View,
        FilterQueueID        => $FilterQueueID,
        FilterCustomerID     => $FilterCustomerID,
        FilterCustomerUserID => $FilterCustomerUserID,
        FilterOwnerID        => $FilterOwnerID,
        SortBy               => $SortBy,
        SortDirection        => $SortDirection,
        PerPage              => $PerPage,
        ListPage             => $ListPage,
        Search               => $Search,
    };

    my $ErrorMessage = '';
    if ($PreferenceObject && $PreferenceObject->Error()) {
        $ErrorMessage = $PreferenceObject->Error();
    }
    elsif ($TicketObject && $TicketObject->Error()) {
        $ErrorMessage = $TicketObject->Error();
    }

    my $PaginationHTML = $Self->_PaginationHTML(
        Context      => $Context,
        CurrentPage  => $ListPage,
        TotalPages   => $TotalPages,
        Language     => $Language,
    );

    return {
        Template => 'AgentTicketList.tt',
        Data     => {
            PageTitle          => 'Translate:AgentTicketListTitle',
            ProgramTitle       => 'Translate:AgentTicketListTitle',
            ProgramDescription => 'Translate:ProgramTicketsDescription',
            TicketCount        => $TicketCount,
            ErrorMessage       => $ErrorMessage,
            ErrorClass         => $ErrorMessage ? '' : 'qisutu-hidden',
            ViewMenuHTML       => $Self->_ViewMenuHTML( Context => $Context, Language => $Language ),
            ActiveViewLabel    => $Self->_ViewLabel( View => $View, Language => $Language, SearchActive => $SearchActive ),
            FilterHTML         => $Self->_FilterHTML(
                Context       => $Context,
                FilterOptions => $FilterOptions,
                Language      => $Language,
            ),
            SearchActive      => $SearchActive,
            SearchStatusHTML  => $Self->_SearchStatusHTML(
                Context     => $Context,
                TicketCount => $TicketCount,
                Language    => $Language,
            ),
            SearchOverlayHTML => $Self->_SearchOverlayHTML(
                Search        => $Search,
                SearchOptions => $SearchOptions,
                Context       => $Context,
                Language      => $Language,
            ),
            PerPageHTML => $Self->_PerPageHTML(
                Context          => $Context,
                Language         => $Language,
                UserAccountID    => $User->{user_account_id} || 0,
                PerPageExplicit  => $PerPageExplicit,
                ListType         => 'agent',
            ),
            PaginationTopHTML    => $PaginationHTML,
            PaginationBottomHTML => $PaginationHTML,
            ColumnChooserHTML => $Self->_ColumnChooserHTML(
                Columns        => $ColumnDefinitions,
                SelectedColumn => \%SelectedColumn,
                Context        => $Context,
                Language       => $Language,
            ),
            TableHTML => $Self->_TableHTML(
                Tickets       => $Tickets,
                Columns       => \@VisibleColumns,
                Context       => $Context,
                Language      => $Language,
                UserAccountID => $User->{user_account_id} || 0,
            ),
            HasTickets => scalar @{$Tickets} ? 1 : 0,
        },
    };
}

sub _ColumnDefinitions {
    my ( $Self, %Param ) = @_;

    my $Language      = $Param{Language} || 'en';
    my $DynamicFields = $Param{DynamicFields} || [];

    my @Columns = (
        { key => 'ticket_number',     label => $Self->_Translate( Key => 'TicketNumber', Language => $Language ) },
        { key => 'title',             label => $Self->_Translate( Key => 'TicketTitle', Language => $Language ) },
        { key => 'queue',             label => $Self->_Translate( Key => 'TicketQueue', Language => $Language ) },
        { key => 'state',             label => $Self->_Translate( Key => 'TicketState', Language => $Language ) },
        { key => 'priority',          label => $Self->_Translate( Key => 'TicketPriority', Language => $Language ) },
        { key => 'customer',          label => $Self->_Translate( Key => 'TicketCustomer', Language => $Language ) },
        { key => 'customer_user',     label => $Self->_Translate( Key => 'TicketCustomerUser', Language => $Language ) },
        { key => 'owner',             label => $Self->_Translate( Key => 'TicketOwner', Language => $Language ) },
        { key => 'responsible',       label => $Self->_Translate( Key => 'TicketResponsible', Language => $Language ) },
        { key => 'created',           label => $Self->_Translate( Key => 'TicketCreated', Language => $Language ) },
        { key => 'changed',           label => $Self->_Translate( Key => 'TicketChanged', Language => $Language ) },
        { key => 'age',               label => $Self->_Translate( Key => 'TicketAge', Language => $Language ) },
        { key => 'escalation_state',  label => $Self->_Translate( Key => 'TicketEscalationState', Language => $Language ) },
        { key => 'next_escalation',   label => $Self->_Translate( Key => 'TicketListNextEscalation', Language => $Language ) },
        { key => 'pending_until',     label => $Self->_Translate( Key => 'TicketPendingUntil', Language => $Language ) },
    );

    for my $Field ( @{$DynamicFields} ) {
        next if ref $Field ne 'HASH';
        next if !$Field->{column_key};

        my $ContextLabel = '';
        if ( ( $Field->{target_type} || '' ) eq 'customer' ) {
            $ContextLabel = $Self->_Translate( Key => 'TicketCustomer', Language => $Language );
        }
        elsif ( ( $Field->{target_type} || '' ) eq 'customer_user' ) {
            $ContextLabel = $Self->_Translate( Key => 'TicketCustomerUser', Language => $Language );
        }
        elsif ( ( $Field->{target_type} || '' ) eq 'owner' ) {
            $ContextLabel = $Self->_Translate( Key => 'TicketOwner', Language => $Language );
        }
        elsif ( ( $Field->{target_type} || '' ) eq 'responsible' ) {
            $ContextLabel = $Self->_Translate( Key => 'TicketResponsible', Language => $Language );
        }

        my $Label = $Field->{label} || $Field->{name} || '';
        $Label = $ContextLabel . ': ' . $Label if $ContextLabel;

        push @Columns, {
            %{$Field},
            key     => $Field->{column_key},
            label   => $Label,
            dynamic => 1,
        };
    }

    return \@Columns;
}

sub _DefaultColumnKeys {
    return [ qw(
        ticket_number
        title
        queue
        state
        priority
        customer
        customer_user
        owner
        escalation_state
        next_escalation
        pending_until
        changed
    ) ];
}

sub _SelectedColumnKeys {
    my ( $Self, %Param ) = @_;

    my $Value         = defined $Param{Value} ? $Param{Value} : '';
    my $AllowedColumn = $Param{AllowedColumn} || {};
    my @Selected;
    my %Seen;

    for my $Key ( split /,/, $Value ) {
        $Key = $Self->_Trim($Key);
        next if !$AllowedColumn->{$Key};
        next if $Seen{$Key}++;
        push @Selected, $Key;
    }

    if ( !@Selected ) {
        for my $Key ( @{ $Self->_DefaultColumnKeys() } ) {
            next if !$AllowedColumn->{$Key};
            push @Selected, $Key;
        }
    }

    return \@Selected;
}

sub _ViewMenuHTML {
    my ( $Self, %Param ) = @_;

    my $Context  = $Param{Context} || {};
    my $Language = $Param{Language} || 'en';
    my @View = (
        [ new       => 'TicketListViewNew' ],
        [ open      => 'TicketListViewOpen' ],
        [ pending   => 'TicketListViewPending' ],
        [ closed    => 'TicketListViewClosed' ],
        [ escalated => 'TicketListViewEscalated' ],
        [ my        => 'TicketListViewMyTickets' ],
    );
    my $HTML = '';

    for my $View (@View) {
        my ( $Key, $LabelKey ) = @{$View};
        my %URLContext = %{$Context};
        $URLContext{View} = $Key;
        $URLContext{ListPage} = 1;
        delete $URLContext{Search};
        my $URL = $Self->_ListURL(%URLContext);
        $URL =~ s{;}{&}g;
        my $Active = ( $Context->{View} || '' ) eq $Key ? ' qisutu-ticket-list-view-active' : '';
        my $Current = ( $Context->{View} || '' ) eq $Key ? '<span aria-hidden="true">✓</span>' : '<span aria-hidden="true"></span>';

        $HTML .= '<a class="qisutu-ticket-list-view-option' . $Active . '" href="' . $Self->_Escape($URL) . '">';
        $HTML .= $Current;
        $HTML .= '<span>' . $Self->_Escape( $Self->_Translate( Key => $LabelKey, Language => $Language ) ) . '</span>';
        $HTML .= '</a>';
    }

    return $HTML;
}

sub _ViewLabel {
    my ( $Self, %Param ) = @_;

    if ( $Param{SearchActive} ) {
        return $Self->_Translate(
            Key      => 'TicketSearchTitle',
            Language => $Param{Language} || 'en',
        );
    }

    my %Key = (
        new       => 'TicketListViewNew',
        open      => 'TicketListViewOpen',
        pending   => 'TicketListViewPending',
        closed    => 'TicketListViewClosed',
        escalated => 'TicketListViewEscalated',
        my        => 'TicketListViewMyTickets',
    );

    return $Self->_Translate(
        Key      => $Key{ $Param{View} || 'new' } || 'TicketListViewNew',
        Language => $Param{Language} || 'en',
    );
}

sub _FilterHTML {
    my ( $Self, %Param ) = @_;

    my $Context       = $Param{Context} || {};
    my $FilterOptions = $Param{FilterOptions} || {};
    my $Language      = $Param{Language} || 'en';

    my $HTML = '<form class="qisutu-ticket-list-filter-form" method="get" action="index.pl" data-qisutu-ticket-list-filter-form>';
    $HTML .= '<input type="hidden" name="Page" value="AgentTicketList">';
    $HTML .= '<input type="hidden" name="View" value="' . $Self->_Escape( $Context->{View} || 'new' ) . '">';
    $HTML .= '<input type="hidden" name="SortBy" value="' . $Self->_Escape( $Context->{SortBy} || 'changed' ) . '">';
    $HTML .= '<input type="hidden" name="SortDirection" value="' . $Self->_Escape( $Context->{SortDirection} || 'desc' ) . '">';
    $HTML .= '<input type="hidden" name="PerPage" value="' . $Self->_Escape( $Context->{PerPage} || 20 ) . '">';
    $HTML .= $Self->_SearchHiddenHTML( Search => $Context->{Search} );

    $HTML .= $Self->_FilterSelectHTML(
        Name        => 'FilterQueueID',
        Label       => $Self->_Translate( Key => 'TicketQueue', Language => $Language ),
        EmptyLabel  => $Self->_Translate( Key => 'TicketListAllQueues', Language => $Language ),
        Selected    => $Context->{FilterQueueID},
        Options     => $FilterOptions->{Queues},
    );
    $HTML .= $Self->_FilterSelectHTML(
        Name        => 'FilterCustomerID',
        Label       => $Self->_Translate( Key => 'TicketCustomer', Language => $Language ),
        EmptyLabel  => $Self->_Translate( Key => 'TicketListAllCustomers', Language => $Language ),
        Selected    => $Context->{FilterCustomerID},
        Options     => $FilterOptions->{Customers},
    );
    $HTML .= $Self->_FilterSelectHTML(
        Name        => 'FilterCustomerUserID',
        Label       => $Self->_Translate( Key => 'TicketCustomerUser', Language => $Language ),
        EmptyLabel  => $Self->_Translate( Key => 'TicketListAllCustomerUsers', Language => $Language ),
        Selected    => $Context->{FilterCustomerUserID},
        Options     => $FilterOptions->{CustomerUsers},
    );
    $HTML .= $Self->_FilterSelectHTML(
        Name        => 'FilterOwnerID',
        Label       => $Self->_Translate( Key => 'TicketOwner', Language => $Language ),
        EmptyLabel  => $Self->_Translate( Key => 'TicketListAllOwners', Language => $Language ),
        Selected    => $Context->{FilterOwnerID},
        Options     => $FilterOptions->{Owners},
        IncludeUnassigned => 1,
        UnassignedLabel   => $Self->_Translate( Key => 'TicketListUnassigned', Language => $Language ),
    );

    my $HasFilter = $Context->{FilterQueueID} || $Context->{FilterCustomerID} || $Context->{FilterCustomerUserID} || $Context->{FilterOwnerID};
    if ($HasFilter) {
        my %ResetContext = %{$Context};
        $ResetContext{FilterQueueID} = '';
        $ResetContext{FilterCustomerID} = '';
        $ResetContext{FilterCustomerUserID} = '';
        $ResetContext{FilterOwnerID} = '';
        $ResetContext{ListPage} = 1;
        $HTML .= '<a class="qisutu-button qisutu-button-secondary qisutu-ticket-list-filter-reset" href="' . $Self->_Escape( $Self->_ListURL(%ResetContext) ) . '">';
        $HTML .= $Self->_Escape( $Self->_Translate( Key => 'TicketListResetFilters', Language => $Language ) );
        $HTML .= '</a>';
    }

    $HTML .= '</form>';

    return $HTML;
}

sub _FilterSelectHTML {
    my ( $Self, %Param ) = @_;

    my $Name     = $Param{Name} || '';
    my $Label    = $Param{Label} || '';
    my $Selected = defined $Param{Selected} ? $Param{Selected} : '';
    my $Options  = $Param{Options} || [];
    my $HTML     = '<label class="qisutu-ticket-list-filter">';
    $HTML .= '<span>' . $Self->_Escape($Label) . '</span>';
    $HTML .= '<select name="' . $Self->_Escape($Name) . '" data-qisutu-ticket-list-filter>';
    $HTML .= '<option value="">' . $Self->_Escape( $Param{EmptyLabel} || '' ) . '</option>';

    if ( $Param{IncludeUnassigned} ) {
        my $SelectedAttribute = $Selected eq 'unassigned' ? ' selected' : '';
        $HTML .= '<option value="unassigned"' . $SelectedAttribute . '>' . $Self->_Escape( $Param{UnassignedLabel} || '' ) . '</option>';
    }

    for my $Option ( @{$Options} ) {
        next if ref $Option ne 'HASH';
        my $Value = defined $Option->{id} ? $Option->{id} : '';
        my $Text  = $Option->{label} || $Option->{name} || '';
        my $SelectedAttribute = "$Value" eq "$Selected" ? ' selected' : '';
        $HTML .= '<option value="' . $Self->_Escape($Value) . '"' . $SelectedAttribute . '>' . $Self->_Escape($Text) . '</option>';
    }

    $HTML .= '</select></label>';

    return $HTML;
}

sub _ColumnChooserHTML {
    my ( $Self, %Param ) = @_;

    my $Columns        = $Param{Columns} || [];
    my $SelectedColumn = $Param{SelectedColumn} || {};
    my $Context        = $Param{Context} || {};
    my $Language       = $Param{Language} || 'en';
    my $HTML           = '<form method="post" action="index.pl" class="qisutu-ticket-list-column-form">';

    $HTML .= '<input type="hidden" name="Page" value="AgentTicketList">';
    $HTML .= '<input type="hidden" name="Step" value="TicketListColumnsSave">';

    for my $Name (qw(View FilterQueueID FilterCustomerID FilterCustomerUserID FilterOwnerID SortBy SortDirection PerPage ListPage)) {
        my $Value = $Context->{$Name} || '';
        $HTML .= '<input type="hidden" name="' . $Self->_Escape($Name) . '" value="' . $Self->_Escape($Value) . '">';
    }
    $HTML .= $Self->_SearchHiddenHTML( Search => $Context->{Search} );

    $HTML .= '<div class="qisutu-ticket-list-column-grid">';
    for my $Column ( @{$Columns} ) {
        my $Key = $Column->{key};
        my $Checked = $SelectedColumn->{$Key} ? ' checked' : '';
        $HTML .= '<label class="qisutu-ticket-list-column-option">';
        $HTML .= '<input type="checkbox" name="Column_' . $Self->_Escape($Key) . '" value="1"' . $Checked . '>';
        $HTML .= '<span>' . $Self->_Escape( $Column->{label} || $Key ) . '</span>';
        $HTML .= '</label>';
    }
    $HTML .= '</div>';
    $HTML .= '<div class="qisutu-ticket-list-column-actions">';
    $HTML .= '<button class="qisutu-button qisutu-button-primary" type="submit">' . $Self->_Escape( $Self->_Translate( Key => 'AdminSave', Language => $Language ) ) . '</button>';
    $HTML .= '<button class="qisutu-button qisutu-button-secondary" type="button" data-qisutu-ticket-list-columns-close>' . $Self->_Escape( $Self->_Translate( Key => 'AdminCancel', Language => $Language ) ) . '</button>';
    $HTML .= '</div></form>';

    return $HTML;
}

sub _PerPageHTML {
    my ( $Self, %Param ) = @_;

    my $Context         = $Param{Context} || {};
    my $Language        = $Param{Language} || 'en';
    my $UserAccountID   = $Param{UserAccountID} || 0;
    my $PerPageExplicit = $Param{PerPageExplicit} ? 1 : 0;
    my $ListType        = $Param{ListType} || 'agent';
    my $Selected        = $Self->_PerPageClean(
        Value   => $Context->{PerPage},
        Default => 20,
    );
    my $StorageKey = 'qisutu.ticketList.perPage.' . $ListType . '.' . $UserAccountID;

    my $HTML = '<form class="qisutu-ticket-list-per-page-form" method="get" action="index.pl"';
    $HTML .= ' data-qisutu-ticket-list-per-page-form';
    $HTML .= ' data-qisutu-ticket-list-per-page-storage="' . $Self->_Escape($StorageKey) . '"';
    $HTML .= ' data-qisutu-ticket-list-per-page-explicit="' . $PerPageExplicit . '">';
    $HTML .= '<input type="hidden" name="Page" value="AgentTicketList">';

    for my $Name (qw(View FilterQueueID FilterCustomerID FilterCustomerUserID FilterOwnerID SortBy SortDirection)) {
        my $Value = $Context->{$Name} || '';
        next if $Value eq '' && $Name =~ m{\AFilter};
        $HTML .= '<input type="hidden" name="' . $Self->_Escape($Name) . '" value="' . $Self->_Escape($Value) . '">';
    }
    $HTML .= $Self->_SearchHiddenHTML( Search => $Context->{Search} );

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
        my %PreviousContext = %{$Context};
        $PreviousContext{ListPage} = $CurrentPage - 1;
        $HTML .= '<a class="qisutu-ticket-list-page-link qisutu-ticket-list-page-direction" href="' . $Self->_Escape( $Self->_ListURL(%PreviousContext) ) . '" aria-label="' . $Self->_Escape( $Self->_Translate( Key => 'TicketListPreviousPage', Language => $Language ) ) . '">‹</a>';
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

        my %PageContext = %{$Context};
        $PageContext{ListPage} = $Item;
        $HTML .= '<a class="qisutu-ticket-list-page-link" href="' . $Self->_Escape( $Self->_ListURL(%PageContext) ) . '">' . $Item . '</a>';
    }

    if ( $CurrentPage < $TotalPages ) {
        my %NextContext = %{$Context};
        $NextContext{ListPage} = $CurrentPage + 1;
        $HTML .= '<a class="qisutu-ticket-list-page-link qisutu-ticket-list-page-direction" href="' . $Self->_Escape( $Self->_ListURL(%NextContext) ) . '" aria-label="' . $Self->_Escape( $Self->_Translate( Key => 'TicketListNextPage', Language => $Language ) ) . '">›</a>';
    }

    $HTML .= '</nav>';

    return $HTML;
}

sub _TableHTML {
    my ( $Self, %Param ) = @_;

    my $Tickets       = $Param{Tickets} || [];
    my $Columns       = $Param{Columns} || [];
    my $Context       = $Param{Context} || {};
    my $Language      = $Param{Language} || 'en';
    my $UserAccountID = $Param{UserAccountID} || 0;

    return '' if !@{$Tickets};

    my $HTML = '<div class="qisutu-table-wrap qisutu-ticket-list-wrap">';
    $HTML .= '<table class="qisutu-table qisutu-ticket-list-table qisutu-ticket-list-table-agent qisutu-ticket-list-table-flexible" data-qisutu-ticket-list-resizable data-qisutu-ticket-list-user-id="' . $Self->_Escape($UserAccountID) . '">';
    $HTML .= '<colgroup>';
    for my $Column ( @{$Columns} ) {
        my $Key = $Column->{key} || '';
        $HTML .= '<col data-qisutu-ticket-list-col="' . $Self->_Escape($Key) . '">';
    }
    $HTML .= '</colgroup><thead><tr>';

    for my $Column ( @{$Columns} ) {
        my $Key = $Column->{key};
        my $Current = ( $Context->{SortBy} || '' ) eq $Key;
        my $Direction = $Current && ( $Context->{SortDirection} || '' ) eq 'asc' ? 'desc' : 'asc';
        my %SortContext = %{$Context};
        $SortContext{SortBy} = $Key;
        $SortContext{SortDirection} = $Direction;
        $SortContext{ListPage} = 1;
        my $Indicator = '';
        if ($Current) {
            $Indicator = ( $Context->{SortDirection} || '' ) eq 'asc' ? '▲' : '▼';
        }

        $HTML .= '<th scope="col" class="qisutu-ticket-list-sort-heading" data-qisutu-ticket-list-heading="' . $Self->_Escape($Key) . '">';
        $HTML .= '<a href="' . $Self->_Escape( $Self->_ListURL(%SortContext) ) . '" aria-label="' . $Self->_Escape( $Column->{label} || $Key ) . '">';
        $HTML .= '<span>' . $Self->_Escape( $Column->{label} || $Key ) . '</span>';
        $HTML .= '<span class="qisutu-ticket-list-sort-indicator" aria-hidden="true">' . $Indicator . '</span>';
        $HTML .= '</a>';
        $HTML .= '<span class="qisutu-ticket-list-resize-handle" role="separator" aria-orientation="vertical" tabindex="0" data-qisutu-ticket-list-resize="' . $Self->_Escape($Key) . '" aria-label="' . $Self->_Escape( $Column->{label} || $Key ) . '"></span>';
        $HTML .= '</th>';
    }

    $HTML .= '</tr></thead><tbody>';

    for my $Ticket ( @{$Tickets} ) {
        $HTML .= '<tr class="qisutu-ticket-list-row">';
        for my $Column ( @{$Columns} ) {
            my $Key   = $Column->{key};
            my $Label = $Column->{label} || $Key;
            my $Value = $Self->_TicketColumnValue(
                Ticket  => $Ticket,
                Column  => $Column,
                Language => $Language,
            );
            my $Class = 'qisutu-ticket-list-cell qisutu-ticket-list-cell-' . $Self->_CSSKey($Key);
            $HTML .= '<td class="' . $Class . '" data-qisutu-ticket-list-cell="' . $Self->_Escape($Key) . '" data-label="' . $Self->_Escape($Label) . '">' . $Value . '</td>';
        }
        $HTML .= '</tr>';
    }

    $HTML .= '</tbody></table></div>';

    return $HTML;
}

sub _TicketColumnValue {
    my ( $Self, %Param ) = @_;

    my $Ticket = $Param{Ticket} || {};
    my $Column = $Param{Column} || {};
    my $Key    = $Column->{key} || '';

    if ( $Key eq 'ticket_number' ) {
        return '<a class="qisutu-ticket-list-number-link" href="' . $Self->_Escape( $Ticket->{ticket_zoom_url} || '#' ) . '">' . $Self->_Escape( $Ticket->{ticket_number} || '-' ) . '</a>';
    }
    if ( $Key eq 'title' ) {
        return '<a class="qisutu-ticket-title-link" href="' . $Self->_Escape( $Ticket->{ticket_zoom_url} || '#' ) . '" title="' . $Self->_Escape( $Ticket->{title} || '' ) . '">' . $Self->_Escape( $Ticket->{title} || '-' ) . '</a>';
    }
    if ( $Key eq 'queue' ) {
        return $Self->_Escape( $Ticket->{queue_name} || '-' );
    }
    if ( $Key eq 'state' ) {
        return $Self->_Escape( $Self->_DisplayValue( Value => $Ticket->{state_name_display}, Language => $Param{Language} ) || '-' );
    }
    if ( $Key eq 'priority' ) {
        return $Self->_Escape( $Self->_DisplayValue( Value => $Ticket->{priority_name_display} || $Ticket->{priority_name}, Language => $Param{Language} ) || '-' );
    }
    if ( $Key eq 'customer' ) {
        return $Self->_Escape( $Ticket->{customer_name} || '-' );
    }
    if ( $Key eq 'customer_user' ) {
        return $Self->_Escape( $Ticket->{customer_user_name} || '-' );
    }
    if ( $Key eq 'owner' ) {
        return $Self->_Escape( $Ticket->{owner_name} || '-' );
    }
    if ( $Key eq 'responsible' ) {
        return $Self->_Escape( $Ticket->{responsible_name} || '-' );
    }
    if ( $Key eq 'created' ) {
        return $Self->_Escape( $Ticket->{created_at_display} || '-' );
    }
    if ( $Key eq 'changed' ) {
        return $Self->_Escape( $Ticket->{changed_at_display} || '-' );
    }
    if ( $Key eq 'age' ) {
        return $Self->_Escape( $Ticket->{age_display} || '-' );
    }
    if ( $Key eq 'escalation_state' ) {
        return '<span class="qisutu-escalation-badge ' . $Self->_Escape( $Ticket->{escalation_state_class} || '' ) . '">' . $Self->_Escape( $Self->_DisplayValue( Value => $Ticket->{escalation_state_label}, Language => $Param{Language} ) || '-' ) . '</span>';
    }
    if ( $Key eq 'next_escalation' ) {
        return $Self->_Escape( $Ticket->{next_escalation_at_display} || '-' );
    }
    if ( $Key eq 'pending_until' ) {
        return $Self->_Escape( $Ticket->{pending_until_display} || '-' );
    }
    if ( $Column->{dynamic} ) {
        my $Value = ref $Ticket->{dynamic_values} eq 'HASH'
            ? $Ticket->{dynamic_values}->{$Key}
            : '';
        return $Self->_Escape( defined $Value && $Value ne '' ? $Value : '-' );
    }

    return '-';
}

sub _EmptySearchOptions {
    return {
        Queues => [], States => [], Priorities => [], Customers => [], CustomerUsers => [],
        Owners => [], Responsibles => [], Services => [], SLAs => [], DynamicFields => [],
    };
}

sub _SearchClean {
    my ( $Self, %Param ) = @_;

    my $Request = $Param{Request} || {};
    my $Active  = $Request->{SearchActive} ? 1 : 0;
    my $Search = {
        Active => $Active,
        Text   => $Self->_SearchTextClean( $Request->{SearchText}, 500 ),
        Mode   => ( defined $Request->{SearchMode} && $Request->{SearchMode} =~ m{\A(?:all|any|phrase)\z} )
            ? $Request->{SearchMode}
            : 'all',
        TicketNumber => $Self->_SearchTextClean( $Request->{SearchTicketNumber}, 100 ),
        Title        => $Self->_SearchTextClean( $Request->{SearchTitle}, 500 ),
        Scopes       => {
            title      => $Request->{SearchScopeTitle}      ? 1 : 0,
            article    => $Request->{SearchScopeArticle}    ? 1 : 0,
            people     => $Request->{SearchScopePeople}     ? 1 : 0,
            attachment => $Request->{SearchScopeAttachment} ? 1 : 0,
        },
        QueueIDs        => $Self->_SearchValueListClean( $Request->{SearchQueueID}, 1 ),
        StateIDs        => $Self->_SearchValueListClean( $Request->{SearchStateID}, 1 ),
        PriorityIDs     => $Self->_SearchValueListClean( $Request->{SearchPriorityID}, 1 ),
        CustomerIDs     => $Self->_SearchValueListClean( $Request->{SearchCustomerID}, 1 ),
        CustomerUserIDs => $Self->_SearchValueListClean( $Request->{SearchCustomerUserID}, 1 ),
        OwnerIDs        => $Self->_SearchValueListClean( $Request->{SearchOwnerID}, 1, AllowUnassigned => 1 ),
        ResponsibleIDs  => $Self->_SearchValueListClean( $Request->{SearchResponsibleID}, 1, AllowUnassigned => 1 ),
        ServiceIDs      => $Self->_SearchValueListClean( $Request->{SearchServiceID}, 1 ),
        SLAIDs          => $Self->_SearchValueListClean( $Request->{SearchSLAID}, 1 ),
        Escalation      => $Self->_SearchAllowedListClean(
            Value   => $Request->{SearchEscalation},
            Allowed => { map { $_ => 1 } qw(normal warning escalated no_sla first_open update_open solution_open) },
        ),
        Dynamic => [],
    };

    for my $Key (qw(
        CreatedFrom CreatedTo ChangedFrom ChangedTo SolutionFrom SolutionTo PendingFrom PendingTo
        FirstResponseDueFrom FirstResponseDueTo UpdateDueFrom UpdateDueTo SolutionDueFrom SolutionDueTo
    )) {
        $Search->{$Key} = $Self->_SearchDateTimeInputClean( $Request->{ 'Search' . $Key } );
    }

    my $HasScope = grep { $Search->{Scopes}->{$_} } keys %{ $Search->{Scopes} };
    if ( !$HasScope ) {
        $Search->{Scopes} = { title => 1, article => 1, people => 1, attachment => 1 };
    }

    for my $Field ( @{ $Param{DynamicFields} || [] } ) {
        next if ref $Field ne 'HASH';
        my $ID = $Field->{id} || 0;
        next if !$ID;
        my $Type = $Field->{field_type} || 'text';
        my $Operator = $Self->_SearchTextClean( $Request->{ 'SearchDynamicOperator_' . $ID }, 30 );
        my %Allowed;
        if ( $Type eq 'number' ) {
            %Allowed = map { $_ => 1 } qw(exact from to between empty not_empty);
        }
        elsif ( $Type eq 'date' ) {
            %Allowed = map { $_ => 1 } qw(from to between empty not_empty);
        }
        elsif ( $Type eq 'dropdown' ) {
            %Allowed = map { $_ => 1 } qw(any empty not_empty);
        }
        elsif ( $Type eq 'multiselect' ) {
            %Allowed = map { $_ => 1 } qw(any all empty not_empty);
        }
        else {
            %Allowed = map { $_ => 1 } qw(contains starts exact empty not_empty);
        }
        next if !$Allowed{$Operator};

        my $Dynamic = {
            id       => 0 + $ID,
            type     => $Type,
            operator => $Operator,
            value    => $Type eq 'date'
                ? $Self->_SearchDateTimeInputClean( $Request->{ 'SearchDynamicValue_' . $ID } )
                : $Self->_SearchTextClean( $Request->{ 'SearchDynamicValue_' . $ID }, 1000 ),
            value_to => $Type eq 'date'
                ? $Self->_SearchDateTimeInputClean( $Request->{ 'SearchDynamicValueTo_' . $ID } )
                : $Self->_SearchTextClean( $Request->{ 'SearchDynamicValueTo_' . $ID }, 1000 ),
            values => $Self->_SearchValueListClean( $Request->{ 'SearchDynamicValues_' . $ID }, 0 ),
        };

        my $HasValue = $Dynamic->{value} ne '' || $Dynamic->{value_to} ne '' || @{ $Dynamic->{values} };
        next if !$HasValue && $Operator !~ m{\A(?:empty|not_empty)\z};
        push @{ $Search->{Dynamic} }, $Dynamic;
    }

    return $Search;
}

sub _SearchTextClean {
    my ( $Self, $Value, $Limit ) = @_;
    return '' if !defined $Value || ref $Value;
    $Value =~ s{\x00}{}g;
    $Value =~ s{\A\s+|\s+\z}{}g;
    $Limit ||= 1000;
    $Value = substr( $Value, 0, $Limit ) if length($Value) > $Limit;
    return $Value;
}

sub _SearchDateTimeInputClean {
    my ( $Self, $Value ) = @_;
    $Value = $Self->_SearchTextClean( $Value, 30 );
    return $Value if $Value =~ m{\A\d{4}-\d{2}-\d{2}(?:T\d{2}:\d{2}(?::\d{2})?)?\z};
    return '';
}

sub _SearchValueListClean {
    my ( $Self, $Value, $Numeric, %Param ) = @_;
    my @Raw = !defined $Value ? () : ref $Value eq 'ARRAY' ? @{$Value} : ($Value);
    my %Seen;
    my @Clean;
    for my $Item (@Raw) {
        next if !defined $Item || ref $Item;
        $Item = $Self->_SearchTextClean( $Item, 255 );
        next if $Item eq '';
        if ( $Numeric ) {
            if ( $Param{AllowUnassigned} && $Item eq 'unassigned' ) {
                next if $Seen{$Item}++;
                push @Clean, $Item;
                next;
            }
            next if $Item !~ m{\A\d+\z} || !$Item;
            $Item = 0 + $Item;
        }
        next if $Seen{$Item}++;
        push @Clean, $Item;
    }
    return \@Clean;
}

sub _SearchAllowedListClean {
    my ( $Self, %Param ) = @_;
    my $Allowed = $Param{Allowed} || {};
    my @Raw = !defined $Param{Value} ? () : ref $Param{Value} eq 'ARRAY' ? @{ $Param{Value} } : ( $Param{Value} );
    my %Seen;
    return [ grep { $Allowed->{$_} && !$Seen{$_}++ } @Raw ];
}

sub _SearchStatusHTML {
    my ( $Self, %Param ) = @_;
    my $Context = $Param{Context} || {};
    my $Search = $Context->{Search} || {};
    return '' if !$Search->{Active};

    my $Language = $Param{Language} || 'en';
    my %Reset = %{$Context};
    delete $Reset{Search};
    $Reset{View} = 'new';
    $Reset{ListPage} = 1;

    my $HTML = '<div class="qisutu-ticket-search-active">';
    $HTML .= '<div><strong>' . $Self->_Escape( $Self->_Translate( Key => 'TicketSearchActive', Language => $Language ) ) . '</strong>';
    $HTML .= '<span>' . $Self->_Escape( $Param{TicketCount} || 0 ) . ' ' . $Self->_Escape( $Self->_Translate( Key => 'TicketSearchHits', Language => $Language ) ) . '</span></div>';
    $HTML .= '<div class="qisutu-ticket-search-active-actions">';
    $HTML .= '<button class="qisutu-button qisutu-button-secondary" type="button" data-qisutu-ticket-search-open>' . $Self->_Escape( $Self->_Translate( Key => 'TicketSearchEdit', Language => $Language ) ) . '</button>';
    $HTML .= '<a class="qisutu-button qisutu-button-secondary" href="' . $Self->_Escape( $Self->_ListURL(%Reset) ) . '">' . $Self->_Escape( $Self->_Translate( Key => 'TicketSearchReset', Language => $Language ) ) . '</a>';
    $HTML .= '</div></div>';
    return $HTML;
}

sub _SearchOverlayHTML {
    my ( $Self, %Param ) = @_;

    my $Search  = $Param{Search} || {};
    my $Options = $Param{SearchOptions} || $Self->_EmptySearchOptions();
    my $Context = $Param{Context} || {};
    my $Language = $Param{Language} || 'en';

    my $HTML = '<div class="qisutu-ticket-search-overlay" data-qisutu-ticket-search-overlay hidden>';
    $HTML .= '<section class="qisutu-ticket-search-dialog" role="dialog" aria-modal="true" aria-labelledby="qisutu-ticket-search-title">';
    $HTML .= '<header class="qisutu-ticket-search-header"><div><h2 id="qisutu-ticket-search-title">' . $Self->_Escape( $Self->_Translate( Key => 'TicketSearchTitle', Language => $Language ) ) . '</h2>';
    $HTML .= '<p>' . $Self->_Escape( $Self->_Translate( Key => 'TicketSearchDescription', Language => $Language ) ) . '</p></div>';
    $HTML .= '<button class="qisutu-ticket-search-close" type="button" aria-label="' . $Self->_Escape( $Self->_Translate( Key => 'AdminCancel', Language => $Language ) ) . '" data-qisutu-ticket-search-close>×</button></header>';

    $HTML .= '<form class="qisutu-ticket-search-form" method="get" action="index.pl" data-qisutu-ticket-search-form>';
    $HTML .= '<input type="hidden" name="Page" value="AgentTicketList">';
    $HTML .= '<input type="hidden" name="SearchActive" value="1">';
    $HTML .= '<input type="hidden" name="View" value="">';
    $HTML .= '<input type="hidden" name="SortBy" value="' . $Self->_Escape( $Context->{SortBy} || 'changed' ) . '">';
    $HTML .= '<input type="hidden" name="SortDirection" value="' . $Self->_Escape( $Context->{SortDirection} || 'desc' ) . '">';
    $HTML .= '<input type="hidden" name="PerPage" value="' . $Self->_Escape( $Context->{PerPage} || 20 ) . '">';

    $HTML .= '<div class="qisutu-ticket-search-content">';

    $HTML .= '<section class="qisutu-ticket-search-section"><h3>' . $Self->_Escape( $Self->_Translate( Key => 'TicketSearchFreeText', Language => $Language ) ) . '</h3>';
    $HTML .= '<div class="qisutu-ticket-search-grid qisutu-ticket-search-grid-main">';
    $HTML .= $Self->_SearchInputHTML(
        Name => 'SearchText', LabelKey => 'TicketSearchTerm', Value => $Search->{Text}, Language => $Language,
        Class => 'qisutu-ticket-search-wide', PlaceholderKey => 'TicketSearchTermPlaceholder',
    );
    $HTML .= $Self->_SearchSelectHTML(
        Name => 'SearchMode', LabelKey => 'TicketSearchMode', Value => $Search->{Mode} || 'all', Language => $Language,
        Options => [
            [ all => 'TicketSearchModeAll' ], [ any => 'TicketSearchModeAny' ], [ phrase => 'TicketSearchModePhrase' ],
        ],
    );
    $HTML .= '</div>';
    $HTML .= '<div class="qisutu-ticket-search-scope"><span>' . $Self->_Escape( $Self->_Translate( Key => 'TicketSearchIn', Language => $Language ) ) . '</span>';
    for my $Scope (
        [ title => 'SearchScopeTitle' => 'TicketSearchScopeTitle' ],
        [ article => 'SearchScopeArticle' => 'TicketSearchScopeArticle' ],
        [ people => 'SearchScopePeople' => 'TicketSearchScopePeople' ],
        [ attachment => 'SearchScopeAttachment' => 'TicketSearchScopeAttachment' ],
    ) {
        my ( $Key, $Name, $LabelKey ) = @{$Scope};
        my $Checked = $Search->{Scopes}->{$Key} ? ' checked' : '';
        $HTML .= '<label><input type="checkbox" name="' . $Name . '" value="1"' . $Checked . '><span>' . $Self->_Escape( $Self->_Translate( Key => $LabelKey, Language => $Language ) ) . '</span></label>';
    }
    $HTML .= '</div></section>';

    $HTML .= '<section class="qisutu-ticket-search-section"><h3>' . $Self->_Escape( $Self->_Translate( Key => 'TicketSearchTicketData', Language => $Language ) ) . '</h3>';
    $HTML .= '<div class="qisutu-ticket-search-grid">';
    $HTML .= $Self->_SearchInputHTML( Name => 'SearchTicketNumber', LabelKey => 'TicketNumber', Value => $Search->{TicketNumber}, Language => $Language );
    $HTML .= $Self->_SearchInputHTML( Name => 'SearchTitle', LabelKey => 'TicketTitle', Value => $Search->{Title}, Language => $Language );
    $HTML .= $Self->_SearchMultiSelectHTML( Name => 'SearchQueueID', LabelKey => 'TicketQueue', Values => $Search->{QueueIDs}, Options => $Options->{Queues}, Language => $Language );
    $HTML .= $Self->_SearchMultiSelectHTML( Name => 'SearchStateID', LabelKey => 'TicketState', Values => $Search->{StateIDs}, Options => $Options->{States}, Language => $Language, DisplayTranslate => 1 );
    $HTML .= $Self->_SearchMultiSelectHTML( Name => 'SearchPriorityID', LabelKey => 'TicketPriority', Values => $Search->{PriorityIDs}, Options => $Options->{Priorities}, Language => $Language, DisplayTranslate => 1 );
    $HTML .= $Self->_SearchMultiSelectHTML( Name => 'SearchCustomerID', LabelKey => 'TicketCustomer', Values => $Search->{CustomerIDs}, Options => $Options->{Customers}, Language => $Language );
    $HTML .= $Self->_SearchMultiSelectHTML( Name => 'SearchCustomerUserID', LabelKey => 'TicketCustomerUser', Values => $Search->{CustomerUserIDs}, Options => $Options->{CustomerUsers}, Language => $Language );
    $HTML .= $Self->_SearchMultiSelectHTML( Name => 'SearchOwnerID', LabelKey => 'TicketOwner', Values => $Search->{OwnerIDs}, Options => $Options->{Owners}, Language => $Language, IncludeUnassigned => 1 );
    $HTML .= $Self->_SearchMultiSelectHTML( Name => 'SearchResponsibleID', LabelKey => 'TicketResponsible', Values => $Search->{ResponsibleIDs}, Options => $Options->{Responsibles}, Language => $Language, IncludeUnassigned => 1 );
    $HTML .= $Self->_SearchMultiSelectHTML( Name => 'SearchServiceID', LabelKey => 'TicketService', Values => $Search->{ServiceIDs}, Options => $Options->{Services}, Language => $Language );
    $HTML .= $Self->_SearchMultiSelectHTML( Name => 'SearchSLAID', LabelKey => 'TicketSLA', Values => $Search->{SLAIDs}, Options => $Options->{SLAs}, Language => $Language );
    $HTML .= '</div></section>';

    $HTML .= '<section class="qisutu-ticket-search-section"><div class="qisutu-ticket-search-section-title"><h3>' . $Self->_Escape( $Self->_Translate( Key => 'TicketSearchPeriods', Language => $Language ) ) . '</h3>';
    $HTML .= '<div class="qisutu-ticket-search-quick-periods" data-qisutu-search-quick-periods>';
    $HTML .= '<span>' . $Self->_Escape( $Self->_Translate( Key => 'TicketSearchQuickCreated', Language => $Language ) ) . '</span>';
    for my $Quick ( [today=>'TicketSearchToday'], [yesterday=>'TicketSearchYesterday'], [7=>'TicketSearchLast7Days'], [30=>'TicketSearchLast30Days'], [year=>'TicketSearchThisYear'] ) {
        $HTML .= '<button type="button" data-qisutu-search-period="' . $Quick->[0] . '">' . $Self->_Escape( $Self->_Translate( Key => $Quick->[1], Language => $Language ) ) . '</button>';
    }
    $HTML .= '</div></div><div class="qisutu-ticket-search-range-grid">';
    for my $Range (
        [ Created => 'TicketCreated' ], [ Changed => 'TicketChanged' ], [ Solution => 'TicketSearchSolved' ],
        [ Pending => 'TicketPendingUntil' ], [ FirstResponseDue => 'TicketSearchFirstResponseDue' ],
        [ UpdateDue => 'TicketSearchUpdateDue' ], [ SolutionDue => 'TicketSearchSolutionDue' ],
    ) {
        $HTML .= $Self->_SearchDateRangeHTML(
            Prefix => $Range->[0], LabelKey => $Range->[1], Search => $Search, Language => $Language,
        );
    }
    $HTML .= '</div></section>';

    $HTML .= '<section class="qisutu-ticket-search-section"><h3>' . $Self->_Escape( $Self->_Translate( Key => 'TicketSearchSLAEscalation', Language => $Language ) ) . '</h3>';
    $HTML .= '<div class="qisutu-ticket-search-checkbox-grid">';
    my %EscalationSelected = map { $_ => 1 } @{ $Search->{Escalation} || [] };
    for my $Item (
        [normal=>'TicketSearchEscalationNormal'], [warning=>'TicketSearchEscalationWarning'], [escalated=>'TicketSearchEscalationBreached'],
        [no_sla=>'TicketSearchWithoutSLA'], [first_open=>'TicketSearchFirstResponseOpen'], [update_open=>'TicketSearchUpdateOpen'], [solution_open=>'TicketSearchSolutionOpen'],
    ) {
        my $Checked = $EscalationSelected{$Item->[0]} ? ' checked' : '';
        $HTML .= '<label><input type="checkbox" name="SearchEscalation" value="' . $Item->[0] . '"' . $Checked . '><span>' . $Self->_Escape( $Self->_Translate( Key => $Item->[1], Language => $Language ) ) . '</span></label>';
    }
    $HTML .= '</div></section>';

    if ( @{ $Options->{DynamicFields} || [] } ) {
        $HTML .= '<section class="qisutu-ticket-search-section"><h3>' . $Self->_Escape( $Self->_Translate( Key => 'TicketSearchDynamicFields', Language => $Language ) ) . '</h3>';
        $HTML .= '<div class="qisutu-ticket-search-dynamic-list">';
        my %Current = map { $_->{id} => $_ } @{ $Search->{Dynamic} || [] };
        for my $Field ( @{ $Options->{DynamicFields} } ) {
            $HTML .= $Self->_SearchDynamicFieldHTML(
                Field => $Field, Current => $Current{ $Field->{id} } || {}, Language => $Language,
            );
        }
        $HTML .= '</div></section>';
    }

    $HTML .= '</div>';
    $HTML .= '<footer class="qisutu-ticket-search-actions">';
    $HTML .= '<button class="qisutu-button qisutu-button-primary" type="submit">' . $Self->_Escape( $Self->_Translate( Key => 'TicketSearchSubmit', Language => $Language ) ) . '</button>';
    $HTML .= '<button class="qisutu-button qisutu-button-secondary" type="reset" data-qisutu-ticket-search-clear>' . $Self->_Escape( $Self->_Translate( Key => 'TicketSearchClearForm', Language => $Language ) ) . '</button>';
    $HTML .= '<button class="qisutu-button qisutu-button-secondary" type="button" data-qisutu-ticket-search-close>' . $Self->_Escape( $Self->_Translate( Key => 'AdminCancel', Language => $Language ) ) . '</button>';
    $HTML .= '</footer></form></section></div>';

    return $HTML;
}

sub _SearchInputHTML {
    my ( $Self, %Param ) = @_;
    my $Language = $Param{Language} || 'en';
    my $Class = $Param{Class} ? ' ' . $Param{Class} : '';
    my $Placeholder = $Param{PlaceholderKey}
        ? ' placeholder="' . $Self->_Escape( $Self->_Translate( Key => $Param{PlaceholderKey}, Language => $Language ) ) . '"'
        : '';
    return '<label class="qisutu-ticket-search-field' . $Class . '"><span>'
        . $Self->_Escape( $Self->_Translate( Key => $Param{LabelKey}, Language => $Language ) )
        . '</span><input type="text" name="' . $Self->_Escape( $Param{Name} ) . '" value="'
        . $Self->_Escape( $Param{Value} || '' ) . '"' . $Placeholder . '></label>';
}

sub _SearchSelectHTML {
    my ( $Self, %Param ) = @_;
    my $Language = $Param{Language} || 'en';
    my $HTML = '<label class="qisutu-ticket-search-field"><span>' . $Self->_Escape( $Self->_Translate( Key => $Param{LabelKey}, Language => $Language ) ) . '</span>';
    $HTML .= '<select name="' . $Self->_Escape( $Param{Name} ) . '">';
    for my $Option ( @{ $Param{Options} || [] } ) {
        my $Selected = ( $Param{Value} || '' ) eq $Option->[0] ? ' selected' : '';
        $HTML .= '<option value="' . $Self->_Escape( $Option->[0] ) . '"' . $Selected . '>' . $Self->_Escape( $Self->_Translate( Key => $Option->[1], Language => $Language ) ) . '</option>';
    }
    $HTML .= '</select></label>';
    return $HTML;
}

sub _SearchMultiSelectHTML {
    my ( $Self, %Param ) = @_;
    my $Language = $Param{Language} || 'en';
    my %Selected = map { ( "$_" => 1 ) } @{ $Param{Values} || [] };
    my $HTML = '<label class="qisutu-ticket-search-field"><span>' . $Self->_Escape( $Self->_Translate( Key => $Param{LabelKey}, Language => $Language ) ) . '</span>';
    $HTML .= '<select name="' . $Self->_Escape( $Param{Name} ) . '" multiple size="5">';
    if ( $Param{IncludeUnassigned} ) {
        $HTML .= '<option value="unassigned"' . ( $Selected{unassigned} ? ' selected' : '' ) . '>' . $Self->_Escape( $Self->_Translate( Key => 'TicketListUnassigned', Language => $Language ) ) . '</option>';
    }
    for my $Option ( @{ $Param{Options} || [] } ) {
        next if ref $Option ne 'HASH';
        my $ID = $Option->{id};
        my $Label = $Option->{label} || $Option->{name} || $ID;
        $Label = $Self->_DisplayValue( Value => $Label, Language => $Language ) if $Param{DisplayTranslate};
        $HTML .= '<option value="' . $Self->_Escape($ID) . '"' . ( $Selected{"$ID"} ? ' selected' : '' ) . '>' . $Self->_Escape($Label) . '</option>';
    }
    $HTML .= '</select><small>' . $Self->_Escape( $Self->_Translate( Key => 'TicketSearchMultiSelectHint', Language => $Language ) ) . '</small></label>';
    return $HTML;
}

sub _SearchDateRangeHTML {
    my ( $Self, %Param ) = @_;
    my $Prefix = $Param{Prefix};
    my $Language = $Param{Language} || 'en';
    my $Search = $Param{Search} || {};
    return '<fieldset class="qisutu-ticket-search-range"><legend>' . $Self->_Escape( $Self->_Translate( Key => $Param{LabelKey}, Language => $Language ) ) . '</legend>'
        . '<label><span>' . $Self->_Escape( $Self->_Translate( Key => 'TicketSearchFrom', Language => $Language ) ) . '</span><input type="datetime-local" name="Search' . $Prefix . 'From" value="' . $Self->_Escape( $Search->{ $Prefix . 'From' } || '' ) . '"></label>'
        . '<label><span>' . $Self->_Escape( $Self->_Translate( Key => 'TicketSearchTo', Language => $Language ) ) . '</span><input type="datetime-local" name="Search' . $Prefix . 'To" value="' . $Self->_Escape( $Search->{ $Prefix . 'To' } || '' ) . '"></label></fieldset>';
}

sub _SearchDynamicFieldHTML {
    my ( $Self, %Param ) = @_;
    my $Field = $Param{Field} || {};
    my $Current = $Param{Current} || {};
    my $Language = $Param{Language} || 'en';
    my $ID = $Field->{id} || 0;
    my $Type = $Field->{field_type} || 'text';
    my $Operator = $Current->{operator} || '';
    my $HTML = '<div class="qisutu-ticket-search-dynamic" data-qisutu-search-dynamic><strong>' . $Self->_Escape( $Field->{label} || $Field->{name} || '' ) . '</strong>';
    $HTML .= '<div class="qisutu-ticket-search-dynamic-controls"><select name="SearchDynamicOperator_' . $ID . '" data-qisutu-search-dynamic-operator>';
    $HTML .= '<option value="">' . $Self->_Escape( $Self->_Translate( Key => 'TicketSearchNotRestricted', Language => $Language ) ) . '</option>';

    my @Operators;
    if ( $Type eq 'number' ) {
        @Operators = ([exact=>'TicketSearchOperatorExact'],[from=>'TicketSearchOperatorFrom'],[to=>'TicketSearchOperatorTo'],[between=>'TicketSearchOperatorBetween'],[empty=>'TicketSearchOperatorEmpty'],[not_empty=>'TicketSearchOperatorNotEmpty']);
    }
    elsif ( $Type eq 'date' ) {
        @Operators = ([from=>'TicketSearchOperatorFrom'],[to=>'TicketSearchOperatorTo'],[between=>'TicketSearchOperatorBetween'],[empty=>'TicketSearchOperatorEmpty'],[not_empty=>'TicketSearchOperatorNotEmpty']);
    }
    elsif ( $Type eq 'dropdown' ) {
        @Operators = ([any=>'TicketSearchOperatorAnySelected'],[empty=>'TicketSearchOperatorEmpty'],[not_empty=>'TicketSearchOperatorNotEmpty']);
    }
    elsif ( $Type eq 'multiselect' ) {
        @Operators = ([any=>'TicketSearchOperatorAnySelected'],[all=>'TicketSearchOperatorAllSelected'],[empty=>'TicketSearchOperatorEmpty'],[not_empty=>'TicketSearchOperatorNotEmpty']);
    }
    else {
        @Operators = ([contains=>'TicketSearchOperatorContains'],[starts=>'TicketSearchOperatorStarts'],[exact=>'TicketSearchOperatorExact'],[empty=>'TicketSearchOperatorEmpty'],[not_empty=>'TicketSearchOperatorNotEmpty']);
    }
    for my $Item (@Operators) {
        $HTML .= '<option value="' . $Item->[0] . '"' . ( $Operator eq $Item->[0] ? ' selected' : '' ) . '>' . $Self->_Escape( $Self->_Translate( Key => $Item->[1], Language => $Language ) ) . '</option>';
    }
    $HTML .= '</select>';

    if ( $Type eq 'dropdown' || $Type eq 'multiselect' ) {
        my %Selected = map { ( "$_" => 1 ) } @{ $Current->{values} || [] };
        my $Multiple = ' multiple size="4"';
        $HTML .= '<select name="SearchDynamicValues_' . $ID . '"' . $Multiple . ' data-qisutu-search-dynamic-value>';
        for my $Option ( @{ $Field->{options} || [] } ) {
            my $Key = defined $Option->{option_key} ? $Option->{option_key} : '';
            $HTML .= '<option value="' . $Self->_Escape($Key) . '"' . ( $Selected{$Key} ? ' selected' : '' ) . '>' . $Self->_Escape( $Option->{option_value} || $Key ) . '</option>';
        }
        $HTML .= '</select>';
    }
    else {
        my $InputType = $Type eq 'date' ? 'datetime-local' : $Type eq 'number' ? 'number' : 'text';
        my $Step = $Type eq 'number' ? ' step="any"' : $Type eq 'date' ? ' step="60"' : '';
        $HTML .= '<input type="' . $InputType . '" name="SearchDynamicValue_' . $ID . '" value="' . $Self->_Escape( $Current->{value} || '' ) . '"' . $Step . ' data-qisutu-search-dynamic-value>';
        if ( $Type eq 'date' || $Type eq 'number' ) {
            $HTML .= '<input type="' . $InputType . '" name="SearchDynamicValueTo_' . $ID . '" value="' . $Self->_Escape( $Current->{value_to} || '' ) . '"' . $Step . ' data-qisutu-search-dynamic-value-to>';
        }
    }
    $HTML .= '</div></div>';
    return $HTML;
}

sub _SearchURLParts {
    my ( $Self, %Param ) = @_;
    my $Search = ref $Param{Search} eq 'HASH' ? $Param{Search} : {};
    return [] if !$Search->{Active};
    my @Part;
    for my $Pair ( @{ $Self->_SearchPairs( Search => $Search ) } ) {
        push @Part, $Self->_URLEncode( $Pair->[0] ) . '=' . $Self->_URLEncode( $Pair->[1] );
    }
    return \@Part;
}

sub _SearchHiddenHTML {
    my ( $Self, %Param ) = @_;
    my $Search = ref $Param{Search} eq 'HASH' ? $Param{Search} : {};
    return '' if !$Search->{Active};
    my $HTML = '';
    for my $Pair ( @{ $Self->_SearchPairs( Search => $Search ) } ) {
        $HTML .= '<input type="hidden" name="' . $Self->_Escape( $Pair->[0] ) . '" value="' . $Self->_Escape( $Pair->[1] ) . '">';
    }
    return $HTML;
}

sub _SearchPairs {
    my ( $Self, %Param ) = @_;
    my $Search = $Param{Search} || {};
    return [] if !$Search->{Active};
    my @Pair = ( [ SearchActive => 1 ] );

    my %Scalar = (
        SearchText => 'Text', SearchMode => 'Mode', SearchTicketNumber => 'TicketNumber', SearchTitle => 'Title',
        SearchCreatedFrom => 'CreatedFrom', SearchCreatedTo => 'CreatedTo', SearchChangedFrom => 'ChangedFrom', SearchChangedTo => 'ChangedTo',
        SearchSolutionFrom => 'SolutionFrom', SearchSolutionTo => 'SolutionTo', SearchPendingFrom => 'PendingFrom', SearchPendingTo => 'PendingTo',
        SearchFirstResponseDueFrom => 'FirstResponseDueFrom', SearchFirstResponseDueTo => 'FirstResponseDueTo',
        SearchUpdateDueFrom => 'UpdateDueFrom', SearchUpdateDueTo => 'UpdateDueTo', SearchSolutionDueFrom => 'SolutionDueFrom', SearchSolutionDueTo => 'SolutionDueTo',
    );
    for my $Name ( sort keys %Scalar ) {
        my $Value = $Search->{ $Scalar{$Name} };
        push @Pair, [ $Name => $Value ] if defined $Value && $Value ne '';
    }
    for my $Scope ( [SearchScopeTitle=>'title'], [SearchScopeArticle=>'article'], [SearchScopePeople=>'people'], [SearchScopeAttachment=>'attachment'] ) {
        push @Pair, [ $Scope->[0] => 1 ] if $Search->{Scopes}->{ $Scope->[1] };
    }
    my %Array = (
        SearchQueueID=>'QueueIDs', SearchStateID=>'StateIDs', SearchPriorityID=>'PriorityIDs', SearchCustomerID=>'CustomerIDs',
        SearchCustomerUserID=>'CustomerUserIDs', SearchOwnerID=>'OwnerIDs', SearchResponsibleID=>'ResponsibleIDs',
        SearchServiceID=>'ServiceIDs', SearchSLAID=>'SLAIDs', SearchEscalation=>'Escalation',
    );
    for my $Name ( sort keys %Array ) {
        push @Pair, map { [ $Name => $_ ] } @{ $Search->{ $Array{$Name} } || [] };
    }
    for my $Dynamic ( @{ $Search->{Dynamic} || [] } ) {
        my $ID = $Dynamic->{id};
        push @Pair, [ 'SearchDynamicOperator_' . $ID => $Dynamic->{operator} ];
        push @Pair, [ 'SearchDynamicValue_' . $ID => $Dynamic->{value} ] if $Dynamic->{value} ne '';
        push @Pair, [ 'SearchDynamicValueTo_' . $ID => $Dynamic->{value_to} ] if $Dynamic->{value_to} ne '';
        push @Pair, map { [ 'SearchDynamicValues_' . $ID => $_ ] } @{ $Dynamic->{values} || [] };
    }
    return \@Pair;
}

sub _ListURL {
    my ( $Self, %Param ) = @_;

    my @Part = ('Page=AgentTicketList');
    my $SearchActive = ref $Param{Search} eq 'HASH' && $Param{Search}->{Active};
    push @Part, 'View=' . $Self->_URLEncode( $Param{View} || ( $SearchActive ? '' : 'new' ) );
    push @Part, 'FilterQueueID=' . $Self->_URLEncode( $Param{FilterQueueID} ) if $Param{FilterQueueID};
    push @Part, 'FilterCustomerID=' . $Self->_URLEncode( $Param{FilterCustomerID} ) if $Param{FilterCustomerID};
    push @Part, 'FilterCustomerUserID=' . $Self->_URLEncode( $Param{FilterCustomerUserID} ) if $Param{FilterCustomerUserID};
    push @Part, 'FilterOwnerID=' . $Self->_URLEncode( $Param{FilterOwnerID} ) if $Param{FilterOwnerID};
    push @Part, 'SortBy=' . $Self->_URLEncode( $Param{SortBy} || 'changed' );
    push @Part, 'SortDirection=' . $Self->_URLEncode( $Param{SortDirection} || 'desc' );
    push @Part, 'PerPage=' . $Self->_URLEncode( $Param{PerPage} || 20 );
    push @Part, 'ListPage=' . $Self->_URLEncode( $Param{ListPage} ) if ( $Param{ListPage} || 1 ) > 1;
    push @Part, @{ $Self->_SearchURLParts( Search => $Param{Search} ) };

    return 'index.pl?' . join( ';', @Part );
}

sub _ViewClean {
    my ( $Self, $View, %Param ) = @_;

    return '' if $Param{SearchActive};
    return $View if defined $View && $View =~ m{\A(?:new|open|pending|closed|escalated|my)\z};
    return 'new';
}

sub _FilterIDClean {
    my ( $Self, $Value ) = @_;

    return $Value if defined $Value && $Value =~ m{\A\d+\z} && $Value > 0;
    return '';
}

sub _OwnerFilterClean {
    my ( $Self, $Value ) = @_;

    return 'unassigned' if defined $Value && $Value eq 'unassigned';
    return $Self->_FilterIDClean($Value);
}

sub _SortByClean {
    my ( $Self, %Param ) = @_;

    my $SortBy        = $Param{SortBy} || '';
    my $AllowedColumn = $Param{AllowedColumn} || {};

    return $SortBy if $AllowedColumn->{$SortBy};
    return 'changed';
}

sub _SortDirectionClean {
    my ( $Self, $Direction ) = @_;

    return 'asc' if defined $Direction && lc($Direction) eq 'asc';
    return 'desc';
}

sub _TicketListLimit {
    my ( $Self, %Param ) = @_;

    my $Preference = $Param{Preference} || {};
    return $Self->_PerPageClean(
        Value   => $Preference->{ticket_list_limit},
        Default => 20,
    );
}

sub _PerPageIsValid {
    my ( $Self, $Value ) = @_;

    return defined $Value && $Value =~ m{\A(?:10|20|30|40|50)\z} ? 1 : 0;
}

sub _PerPageClean {
    my ( $Self, %Param ) = @_;

    my $Value   = $Param{Value};
    my $Default = $Param{Default};

    return int($Value) if $Self->_PerPageIsValid($Value);
    return int($Default) if $Self->_PerPageIsValid($Default);
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

    return if !$Loaded;

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

sub _PreferenceObject {
    my ($Self) = @_;

    return if !$Self->{DB};

    my $Loaded = eval {
        require QisutuUserPreference;
        1;
    };

    return if !$Loaded;

    return QisutuUserPreference->new(
        Config => $Self->{Config},
        DB     => $Self->{DB},
    );
}


sub _DisplayValue {
    my ( $Self, %Param ) = @_;

    my $Value = defined $Param{Value} ? $Param{Value} : '';

    if ( $Value =~ m{\ATranslate:([A-Za-z0-9_]+)\z} ) {
        return $Self->_Translate(
            Key      => $1,
            Language => $Param{Language} || 'en',
        );
    }

    return $Value;
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

sub _CSSKey {
    my ( $Self, $Value ) = @_;

    $Value = '' if !defined $Value;
    $Value =~ s{[^A-Za-z0-9_-]}{-}g;

    return $Value;
}

sub _Trim {
    my ( $Self, $Value ) = @_;

    $Value = '' if !defined $Value;
    $Value =~ s{\A\s+}{};
    $Value =~ s{\s+\z}{};

    return $Value;
}

1;
