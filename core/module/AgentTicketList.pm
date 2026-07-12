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

    my $DynamicFields = $TicketObject
        ? $TicketObject->TicketListDynamicFieldList( Language => $Language )
        : [];
    my $ColumnDefinitions = $Self->_ColumnDefinitions(
        DynamicFields => $DynamicFields,
        Language      => $Language,
    );
    my $AllowedColumn = { map { $_->{key} => $_ } @{$ColumnDefinitions} };

    my $View = $Self->_ViewClean( $Request->{View} );
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
            ActiveViewLabel    => $Self->_ViewLabel( View => $View, Language => $Language ),
            FilterHTML         => $Self->_FilterHTML(
                Context       => $Context,
                FilterOptions => $FilterOptions,
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
        [ escalated => 'TicketListViewEscalated' ],
        [ my        => 'TicketListViewMyTickets' ],
    );
    my $HTML = '';

    for my $View (@View) {
        my ( $Key, $LabelKey ) = @{$View};
        my %URLContext = %{$Context};
        $URLContext{View} = $Key;
        $URLContext{ListPage} = 1;
        my $URL = $Self->_ListURL(%URLContext);
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

    my %Key = (
        new       => 'TicketListViewNew',
        open      => 'TicketListViewOpen',
        pending   => 'TicketListViewPending',
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

sub _ListURL {
    my ( $Self, %Param ) = @_;

    my @Part = ('Page=AgentTicketList');
    push @Part, 'View=' . $Self->_URLEncode( $Param{View} || 'new' );
    push @Part, 'FilterQueueID=' . $Self->_URLEncode( $Param{FilterQueueID} ) if $Param{FilterQueueID};
    push @Part, 'FilterCustomerID=' . $Self->_URLEncode( $Param{FilterCustomerID} ) if $Param{FilterCustomerID};
    push @Part, 'FilterCustomerUserID=' . $Self->_URLEncode( $Param{FilterCustomerUserID} ) if $Param{FilterCustomerUserID};
    push @Part, 'FilterOwnerID=' . $Self->_URLEncode( $Param{FilterOwnerID} ) if $Param{FilterOwnerID};
    push @Part, 'SortBy=' . $Self->_URLEncode( $Param{SortBy} || 'changed' );
    push @Part, 'SortDirection=' . $Self->_URLEncode( $Param{SortDirection} || 'desc' );
    push @Part, 'PerPage=' . $Self->_URLEncode( $Param{PerPage} || 20 );
    push @Part, 'ListPage=' . $Self->_URLEncode( $Param{ListPage} ) if ( $Param{ListPage} || 1 ) > 1;

    return 'index.pl?' . join( ';', @Part );
}

sub _ViewClean {
    my ( $Self, $View ) = @_;

    return $View if defined $View && $View =~ m{\A(?:new|open|pending|escalated|my)\z};
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
