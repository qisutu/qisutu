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

package AdminChecklists;

use strict;
use warnings;
use utf8;

use QisutuChecklist;

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

    my $Request  = $Param{Request} || {};
    my $User     = $Param{User} || {};
    my $Language = $Request->{Language} || $Self->{Config}->{Language}->{Default} || 'en';
    my $Action   = $Request->{Action} || 'List';
    my $Step     = $Request->{Step} || '';
    my $AddItemRequested = ( $Request->{FormAction} || '' ) eq 'AddChecklistItem' ? 1 : 0;
    my $UserID   = $User->{user_account_id} || 1;

    if ($AddItemRequested) {
        $Action = ( $Request->{TemplateID} || 0 ) ? 'Edit' : 'Create';
        $Step   = '';
    }
    my $Object   = QisutuChecklist->new( Config => $Self->{Config}, DB => $Self->{DB} );
    my $Error    = '';

    if ( $Step eq 'ChecklistCreate' || $Step eq 'ChecklistUpdate' ) {
        my $IsCreate = $Step eq 'ChecklistCreate' ? 1 : 0;
        my $TemplateID = $Request->{TemplateID} || 0;
        my $Items = $Self->_ItemsFromRequest( Request => $Request );

        if ( $Self->{DB}->BeginWork() ) {
            my $Saved;
            if ($IsCreate) {
                $TemplateID = $Object->TemplateCreate(
                    Name            => $Request->{Name},
                    Description     => $Request->{Description},
                    UsageMode       => $Request->{UsageMode},
                    SortOrder       => $Request->{SortOrder},
                    ChangedByUserID => $UserID,
                );
                $Saved = $TemplateID ? 1 : 0;
            }
            else {
                $Saved = $Object->TemplateUpdate(
                    TemplateID      => $TemplateID,
                    Name            => $Request->{Name},
                    Description     => $Request->{Description},
                    UsageMode       => $Request->{UsageMode},
                    SortOrder       => $Request->{SortOrder},
                    Active          => $Request->{Active},
                    ChangedByUserID => $UserID,
                );
            }

            if ( $Saved ) {
                $Saved = $Object->TemplateItemsSet(
                    TemplateID      => $TemplateID,
                    Items           => $Items,
                    ChangedByUserID => $UserID,
                );
            }

            if ( $Saved && $Self->{DB}->Commit() ) {
                return { Redirect => 'index.pl?Page=AdminChecklists;Action=Edit;TemplateID=' . $TemplateID };
            }
            eval { $Self->{DB}->Rollback(); 1; };
        }
        $Error = $Object->Error() || $Self->{DB}->Error() || 'Translate:AdminChecklistSaveFailed';
        $Action = $IsCreate ? 'Create' : 'Edit';
    }
    elsif ( $Step eq 'ChecklistDeactivate' ) {
        if ( $Object->TemplateDeactivate(
            TemplateID      => $Request->{TemplateID},
            ChangedByUserID => $UserID,
        ) ) {
            return { Redirect => 'index.pl?Page=AdminChecklists' };
        }
        $Error = $Object->Error() || 'Translate:AdminChecklistDeactivateFailed';
    }
    elsif ( $Step =~ m{\AChecklist(?:TemplateQueue|TemplateService|TemplateCustomer|QueueTemplate|ServiceTemplate|CustomerTemplate)Save\z} ) {
        my %Map = (
            ChecklistTemplateQueueSave => [ 'TemplateQueueSet', 'TemplateID', 'QueueID', 'QueueIDs', 'TemplateQueue', 'TemplateID' ],
            ChecklistTemplateServiceSave => [ 'TemplateServiceSet', 'TemplateID', 'ServiceID', 'ServiceIDs', 'TemplateService', 'TemplateID' ],
            ChecklistTemplateCustomerSave => [ 'TemplateCustomerSet', 'TemplateID', 'CustomerID', 'CustomerIDs', 'TemplateCustomer', 'TemplateID' ],
            ChecklistQueueTemplateSave => [ 'QueueTemplateSet', 'QueueID', 'TemplateID', 'TemplateIDs', 'QueueTemplate', 'QueueID' ],
            ChecklistServiceTemplateSave => [ 'ServiceTemplateSet', 'ServiceID', 'TemplateID', 'TemplateIDs', 'ServiceTemplate', 'ServiceID' ],
            ChecklistCustomerTemplateSave => [ 'CustomerTemplateSet', 'CustomerID', 'TemplateID', 'TemplateIDs', 'CustomerTemplate', 'CustomerID' ],
        );
        my $Data = $Map{$Step};
        if ($Data) {
            my ( $Method, $PrimaryName, $ListName, $MethodListName, $RedirectAction, $RedirectParam ) = @{$Data};
            my $PrimaryID = $Request->{$PrimaryName} || 0;
            my $IDs = $Self->_IDList( $Request->{$ListName} );
            if ( $Self->{DB}->BeginWork() ) {
                my %Call = (
                    $PrimaryName     => $PrimaryID,
                    $MethodListName  => $IDs,
                    ChangedByUserID  => $UserID,
                );
                if ( $Object->$Method(%Call) && $Self->{DB}->Commit() ) {
                    return { Redirect => 'index.pl?Page=AdminChecklists;Action=' . $RedirectAction . ';' . $RedirectParam . '=' . $PrimaryID };
                }
                eval { $Self->{DB}->Rollback(); 1; };
            }
            $Error = $Object->Error() || $Self->{DB}->Error() || 'Translate:AdminChecklistAssignmentSaveFailed';
            $Action = $RedirectAction;
        }
    }

    my $Templates = $Object->TemplateList( IncludeInactive => 1 );
    my $Queues    = $Object->QueueList( IncludeInactive => 1 );
    my $Services  = $Object->ServiceList( IncludeInactive => 1 );
    my $Customers = $Object->CustomerList( IncludeInactive => 1 );

    my $Template;
    if ( $Action eq 'Edit' ) {
        $Template = $Object->TemplateGet( TemplateID => $Request->{TemplateID} || 0 );
        if ( !$Template ) {
            $Error ||= $Object->Error() || 'Translate:AdminChecklistNotFound';
            $Action = 'List';
        }
    }

    my %Assignment = $Self->_AssignmentPrepare(
        Action    => $Action,
        Request   => $Request,
        Object    => $Object,
        Templates => $Templates,
        Queues    => $Queues,
        Services  => $Services,
        Customers => $Customers,
    );
    if ( $Assignment{Invalid} ) {
        $Error ||= 'Translate:AdminChecklistAssignmentTargetNotFound';
        $Action = 'List';
        %Assignment = ();
    }

    my $Form;
    my $Items;

    if ($AddItemRequested) {
        $Form  = $Request;
        $Items = $Self->_ItemsFromRequest( Request => $Request );

        # The server-side fallback must not create several unused empty rows.
        # If an empty item already exists, keep it instead of appending another.
        my $HasEmptyItem = 0;
        for my $Item ( @{$Items} ) {
            my $Name = defined $Item->{Name} ? $Item->{Name} : '';
            my $Description = defined $Item->{Description} ? $Item->{Description} : '';
            $Name =~ s{\A\s+|\s+\z}{}g;
            $Description =~ s{\A\s+|\s+\z}{}g;
            if ( $Name eq '' && $Description eq '' ) {
                $HasEmptyItem = 1;
                last;
            }
        }

        if ( !$HasEmptyItem ) {
            push @{$Items}, {
                Name        => '',
                Description => '',
                IsRequired  => 0,
                SortOrder   => ( scalar(@{$Items}) + 1 ) * 1000,
            };
        }
    }
    else {
        $Form  = $Template || ( $Action eq 'Create' ? $Request : {} );
        $Items = $Template ? ( $Template->{items} || [] ) : $Self->_ItemsFromRequest( Request => $Request );
    }

    if ( $Action eq 'Create' && !@{$Items} ) {
        $Items = [ { Name => '', Description => '', IsRequired => 0, SortOrder => 1000 } ];
    }

    for my $Item ( @{$Items} ) {
        $Item->{name} = $Item->{Name} if !defined $Item->{name};
        $Item->{description} = $Item->{Description} if !defined $Item->{description};
        $Item->{is_required} = $Item->{IsRequired} if !defined $Item->{is_required};
        $Item->{sort_order} = $Item->{SortOrder} if !defined $Item->{sort_order};
        $Item->{required_checked} = $Item->{is_required} ? 'checked' : '';
    }

    for my $Row ( @{$Templates} ) {
        $Row->{active_label} = $Row->{active} ? 'Translate:CommonYes' : 'Translate:CommonNo';
        $Row->{usage_label} = 'Translate:' . (
            ( $Row->{usage_mode} || '' ) eq 'automatic' ? 'AdminChecklistUsageAutomatic'
            : ( $Row->{usage_mode} || '' ) eq 'both' ? 'AdminChecklistUsageBoth'
            : 'AdminChecklistUsageManual'
        );
        $Row->{queue_names}    ||= '-';
        $Row->{service_names}  ||= '-';
        $Row->{customer_names} ||= '-';
    }

    my $Usage = $Form->{usage_mode} || $Form->{UsageMode} || 'manual';

    my $ShowList       = $Action eq 'List' ? 1 : 0;
    my $ShowCreate     = $Action eq 'Create' ? 1 : 0;
    my $ShowEdit       = $Action eq 'Edit' ? 1 : 0;
    my $ShowAssignment = $Action =~ m{\A(?:TemplateQueue|TemplateService|TemplateCustomer|QueueTemplate|ServiceTemplate|CustomerTemplate)\z} ? 1 : 0;

    return {
        Template => 'AdminChecklists.tt',
        Data => {
            PageTitle          => 'Translate:AdminChecklistsTitle',
            ProgramTitle       => 'Translate:AdminChecklistsTitle',
            ProgramDescription => 'Translate:AdminChecklistsDescription',
            ErrorMessage       => $Error,
            ErrorClass         => $Error ? '' : 'qisutu-hidden',
            ShowList           => $ShowList,
            ShowCreate         => $ShowCreate,
            ShowEdit           => $ShowEdit,
            ShowForm           => ( $ShowCreate || $ShowEdit ) ? 1 : 0,
            ShowBackToList     => $ShowList ? 0 : 1,
            ShowAssignment     => $ShowAssignment,
            AssignmentAction   => $Action,
            TemplateList       => $Templates,
            TemplateCount      => scalar @{$Templates},
            QueueList          => $Queues,
            ServiceList        => $Services,
            CustomerList       => $Customers,
            FormStep           => $Action eq 'Create' ? 'ChecklistCreate' : 'ChecklistUpdate',
            FormTitle          => $Action eq 'Create' ? 'Translate:AdminChecklistCreate' : 'Translate:AdminChecklistEdit',
            FormTemplateID     => $Form->{id} || $Form->{TemplateID} || '',
            FormName           => $Form->{name} || $Form->{Name} || '',
            FormDescription    => $Form->{description} || $Form->{Description} || '',
            FormSortOrder      => $Form->{sort_order} || $Form->{SortOrder} || 1000,
            FormActiveChecked  => (
                $AddItemRequested && $Action eq 'Edit'
                    ? ( $Form->{Active} ? 'checked' : '' )
                    : ( !defined $Form->{active} || $Form->{active} ? 'checked' : '' )
            ),
            UsageAutomaticSelected => $Usage eq 'automatic' ? 'selected' : '',
            UsageManualSelected    => $Usage eq 'manual' ? 'selected' : '',
            UsageBothSelected      => $Usage eq 'both' ? 'selected' : '',
            FormItems          => $Items,
            FormItemCount      => scalar @{$Items},
            FormSubmitLabel    => $ShowCreate ? 'Translate:AdminCreate' : 'Translate:AdminSave',
            TemplateRowsHTML   => $Self->_TemplateRowsHTML(
                Templates => $Templates,
                Language  => $Language,
            ),
            AssignmentOverviewHTML => $Self->_AssignmentOverviewHTML(
                Queues    => $Queues,
                Services  => $Services,
                Customers => $Customers,
                Language  => $Language,
            ),
            FormItemsHTML => $Self->_FormItemsHTML(
                Items    => $Items,
                Language => $Language,
            ),
            AssignmentTitle    => $Assignment{Title} || '',
            AssignmentSubtitle => $Assignment{Subtitle} || '',
            AssignmentStep     => $Assignment{Step} || '',
            AssignmentPrimaryName => $Assignment{PrimaryName} || '',
            AssignmentPrimaryID   => $Assignment{PrimaryID} || '',
            AssignmentRows     => $Assignment{Rows} || [],
            AssignmentRowsHTML => $Self->_AssignmentRowsHTML(
                Rows     => $Assignment{Rows} || [],
                Action   => $Action,
                Language => $Language,
            ),
        },
    };
}

sub _TemplateRowsHTML {
    my ( $Self, %Param ) = @_;

    my $Language = $Param{Language} || 'en';
    my $Edit = $Self->{Output}->Translate( Key => 'AdminEdit', Language => $Language );
    my $Deactivate = $Self->{Output}->Translate( Key => 'AdminDeactivate', Language => $Language );
    my $Queues = $Self->{Output}->Translate( Key => 'AdminChecklistQueues', Language => $Language );
    my $Services = $Self->{Output}->Translate( Key => 'AdminChecklistServices', Language => $Language );
    my $Customers = $Self->{Output}->Translate( Key => 'AdminChecklistCustomers', Language => $Language );
    my $Yes = $Self->{Output}->Translate( Key => 'CommonYes', Language => $Language );
    my $No  = $Self->{Output}->Translate( Key => 'CommonNo', Language => $Language );
    my %UsageLabel = (
        automatic => $Self->{Output}->Translate( Key => 'AdminChecklistUsageAutomatic', Language => $Language ),
        manual    => $Self->{Output}->Translate( Key => 'AdminChecklistUsageManual', Language => $Language ),
        both      => $Self->{Output}->Translate( Key => 'AdminChecklistUsageBoth', Language => $Language ),
    );

    my $HTML = '';
    for my $Checklist ( @{ $Param{Templates} || [] } ) {
        my $ID = int( $Checklist->{id} || 0 );
        my $Description = $Checklist->{description}
            ? '<div class="qisutu-admin-table-subtitle">' . $Self->{Output}->HTMLEscape( $Checklist->{description} ) . '</div>'
            : '';
        my $Usage = $UsageLabel{ $Checklist->{usage_mode} || '' } || $UsageLabel{manual};

        $HTML .= '<tr>';
        $HTML .= '<td><strong>' . $Self->{Output}->HTMLEscape( $Checklist->{name} || '' ) . '</strong>' . $Description . '</td>';
        $HTML .= '<td>' . $Self->{Output}->HTMLEscape($Usage) . '</td>';
        $HTML .= '<td>' . int( $Checklist->{item_count} || 0 ) . '</td>';
        $HTML .= '<td>' . int( $Checklist->{required_item_count} || 0 ) . '</td>';
        $HTML .= '<td>' . $Self->{Output}->HTMLEscape( $Checklist->{active} ? $Yes : $No ) . '</td>';
        $HTML .= '<td><div class="qisutu-admin-row-actions">';
        $HTML .= '<a class="qisutu-button qisutu-button-small qisutu-button-secondary" href="index.pl?Page=AdminChecklists;Action=Edit;TemplateID=' . $ID . '">' . $Self->{Output}->HTMLEscape($Edit) . '</a>';
        $HTML .= '<a class="qisutu-button qisutu-button-small qisutu-button-secondary" href="index.pl?Page=AdminChecklists;Action=TemplateQueue;TemplateID=' . $ID . '">' . $Self->{Output}->HTMLEscape($Queues) . '</a>';
        $HTML .= '<a class="qisutu-button qisutu-button-small qisutu-button-secondary" href="index.pl?Page=AdminChecklists;Action=TemplateService;TemplateID=' . $ID . '">' . $Self->{Output}->HTMLEscape($Services) . '</a>';
        $HTML .= '<a class="qisutu-button qisutu-button-small qisutu-button-secondary" href="index.pl?Page=AdminChecklists;Action=TemplateCustomer;TemplateID=' . $ID . '">' . $Self->{Output}->HTMLEscape($Customers) . '</a>';
        if ( $Checklist->{active} ) {
            $HTML .= '<form class="qisutu-inline-form" method="post" action="index.pl">';
            $HTML .= '<input type="hidden" name="Page" value="AdminChecklists">';
            $HTML .= '<input type="hidden" name="Step" value="ChecklistDeactivate">';
            $HTML .= '<input type="hidden" name="TemplateID" value="' . $ID . '">';
            $HTML .= '<button class="qisutu-button qisutu-button-small qisutu-button-danger" type="submit">' . $Self->{Output}->HTMLEscape($Deactivate) . '</button>';
            $HTML .= '</form>';
        }
        $HTML .= '</div></td></tr>';
    }

    return $HTML;
}

sub _AssignmentOverviewHTML {
    my ( $Self, %Param ) = @_;

    my $Language = $Param{Language} || 'en';
    my $QueueTitle = $Self->{Output}->Translate( Key => 'TicketQueue', Language => $Language );
    my $ServiceTitle = $Self->{Output}->Translate( Key => 'TicketService', Language => $Language );
    my $CustomerTitle = $Self->{Output}->Translate( Key => 'TicketCustomer', Language => $Language );
    my $ChecklistTitle = $Self->{Output}->Translate( Key => 'AdminChecklistsTitle', Language => $Language );

    my $HTML = '<div class="qisutu-checklist-assignment-columns">';
    $HTML .= '<div><h3>' . $Self->{Output}->HTMLEscape($QueueTitle) . ' → ' . $Self->{Output}->HTMLEscape($ChecklistTitle) . '</h3>';
    for my $Queue ( @{ $Param{Queues} || [] } ) {
        $HTML .= '<a class="qisutu-checklist-assignment-link" href="index.pl?Page=AdminChecklists;Action=QueueTemplate;QueueID=' . int( $Queue->{id} || 0 ) . '">' . $Self->{Output}->HTMLEscape( $Queue->{full_name} || $Queue->{name} || '' ) . '</a>';
    }
    $HTML .= '</div><div><h3>' . $Self->{Output}->HTMLEscape($ServiceTitle) . ' → ' . $Self->{Output}->HTMLEscape($ChecklistTitle) . '</h3>';
    for my $Service ( @{ $Param{Services} || [] } ) {
        $HTML .= '<a class="qisutu-checklist-assignment-link" href="index.pl?Page=AdminChecklists;Action=ServiceTemplate;ServiceID=' . int( $Service->{id} || 0 ) . '">' . $Self->{Output}->HTMLEscape( $Service->{full_name} || $Service->{name} || '' ) . '</a>';
    }
    $HTML .= '</div><div><h3>' . $Self->{Output}->HTMLEscape($CustomerTitle) . ' → ' . $Self->{Output}->HTMLEscape($ChecklistTitle) . '</h3>';
    for my $Customer ( @{ $Param{Customers} || [] } ) {
        my $Label = ( $Customer->{name} || '' ) . ( ( $Customer->{customer_number} || '' ) ? ' (' . $Customer->{customer_number} . ')' : '' );
        $HTML .= '<a class="qisutu-checklist-assignment-link" href="index.pl?Page=AdminChecklists;Action=CustomerTemplate;CustomerID=' . int( $Customer->{id} || 0 ) . '">' . $Self->{Output}->HTMLEscape($Label) . '</a>';
    }
    $HTML .= '</div></div>';

    return $HTML;
}

sub _FormItemsHTML {
    my ( $Self, %Param ) = @_;

    my $Language = $Param{Language} || 'en';
    my $ItemText = $Self->{Output}->Translate( Key => 'AdminChecklistItemText', Language => $Language );
    my $DescriptionText = $Self->{Output}->Translate( Key => 'AdminChecklistItemDescription', Language => $Language );
    my $SortOrder = $Self->{Output}->Translate( Key => 'AdminSortOrder', Language => $Language );
    my $Required = $Self->{Output}->Translate( Key => 'AdminChecklistRequiredBeforeClose', Language => $Language );
    my $Remove = $Self->{Output}->Translate( Key => 'AdminRemove', Language => $Language );

    my $HTML = '';
    my $Index = 0;
    for my $Item ( @{ $Param{Items} || [] } ) {
        my $ItemID = int( $Item->{id} || $Item->{ItemID} || 0 );
        my $Name = defined $Item->{name} ? $Item->{name} : ( $Item->{Name} || '' );
        my $Description = defined $Item->{description} ? $Item->{description} : ( $Item->{Description} || '' );
        my $Sort = $Item->{sort_order} || $Item->{SortOrder} || 1000;
        my $Checked = ( $Item->{is_required} || $Item->{IsRequired} ) ? ' checked' : '';

        $HTML .= '<div class="qisutu-checklist-admin-item" data-qisutu-checklist-item-row draggable="true">';
        $HTML .= '<input type="hidden" name="ItemRowIndex" value="' . $Index . '">';
        $HTML .= '<input type="hidden" name="ItemID_' . $Index . '" value="' . $ItemID . '">';
        $HTML .= '<span class="qisutu-checklist-drag-handle" aria-hidden="true">↕</span>';
        $HTML .= '<div class="qisutu-form-field qisutu-checklist-admin-item-name"><label>' . $Self->{Output}->HTMLEscape($ItemText) . '</label>';
        $HTML .= '<input type="text" name="ItemName_' . $Index . '" value="' . $Self->{Output}->HTMLEscape($Name) . '"></div>';
        $HTML .= '<div class="qisutu-form-field qisutu-checklist-admin-item-description"><label>' . $Self->{Output}->HTMLEscape($DescriptionText) . '</label>';
        $HTML .= '<textarea name="ItemDescription_' . $Index . '" rows="3">' . $Self->{Output}->HTMLEscape($Description) . '</textarea></div>';
        $HTML .= '<div class="qisutu-form-field qisutu-checklist-admin-item-sort"><label>' . $Self->{Output}->HTMLEscape($SortOrder) . '</label>';
        $HTML .= '<input type="number" name="ItemSortOrder_' . $Index . '" value="' . int($Sort) . '" min="1"></div>';
        $HTML .= '<label class="qisutu-form-checkbox qisutu-checklist-required-checkbox"><input type="checkbox" name="ItemRequired_' . $Index . '" value="1"' . $Checked . '><span>' . $Self->{Output}->HTMLEscape($Required) . '</span></label>';
        $HTML .= '<button class="qisutu-button qisutu-button-small qisutu-button-danger qisutu-checklist-admin-item-remove" type="button" data-qisutu-checklist-item-remove>' . $Self->{Output}->HTMLEscape($Remove) . '</button>';
        $HTML .= '</div>';
        $Index++;
    }

    return $HTML;
}

sub _AssignmentRowsHTML {
    my ( $Self, %Param ) = @_;

    my $Action = $Param{Action} || '';
    my $InputName = $Action eq 'TemplateQueue' ? 'QueueID'
        : $Action eq 'TemplateService' ? 'ServiceID'
        : $Action eq 'TemplateCustomer' ? 'CustomerID'
        : 'TemplateID';

    my $HTML = '';
    for my $Row ( @{ $Param{Rows} || [] } ) {
        $HTML .= '<label class="qisutu-assignment-checkbox">';
        $HTML .= '<input type="checkbox" name="' . $InputName . '" value="' . int( $Row->{id} || 0 ) . '"' . ( $Row->{assignment_checked} ? ' checked' : '' ) . '>';
        $HTML .= '<span>' . $Self->{Output}->HTMLEscape( $Row->{assignment_label} || '' ) . '</span>';
        $HTML .= '</label>';
    }

    return $HTML;
}

sub _AssignmentPrepare {
    my ( $Self, %Param ) = @_;
    my $Action = $Param{Action} || '';
    return if $Action !~ m{\A(?:TemplateQueue|TemplateService|TemplateCustomer|QueueTemplate|ServiceTemplate|CustomerTemplate)\z};

    my $Object = $Param{Object};
    my ( $PrimaryID, $Primary, $Rows, $Selected, $Step, $Title, $PrimaryName );

    if ( $Action =~ m{\ATemplate} ) {
        $PrimaryID = $Param{Request}->{TemplateID} || 0;
        ($Primary) = grep { ( $_->{id} || 0 ) == $PrimaryID } @{ $Param{Templates} || [] };
        return ( Invalid => 1 ) if !$Primary;
        $PrimaryName = 'TemplateID';
        if ( $Action eq 'TemplateQueue' ) {
            $Rows = $Param{Queues};
            $Selected = $Object->TemplateQueueIDs( TemplateID => $PrimaryID );
            $Step = 'ChecklistTemplateQueueSave';
            $Title = 'Translate:AdminChecklistAssignQueues';
        }
        elsif ( $Action eq 'TemplateService' ) {
            $Rows = $Param{Services};
            $Selected = $Object->TemplateServiceIDs( TemplateID => $PrimaryID );
            $Step = 'ChecklistTemplateServiceSave';
            $Title = 'Translate:AdminChecklistAssignServices';
        }
        else {
            $Rows = $Param{Customers};
            $Selected = $Object->TemplateCustomerIDs( TemplateID => $PrimaryID );
            $Step = 'ChecklistTemplateCustomerSave';
            $Title = 'Translate:AdminChecklistAssignCustomers';
        }
    }
    else {
        my ( $List, $IDName, $ReverseMethod, $ListName );
        if ( $Action eq 'QueueTemplate' ) {
            $List = $Param{Queues}; $IDName = 'QueueID'; $ReverseMethod = 'QueueTemplateIDs'; $ListName = 'Queues';
            $Step = 'ChecklistQueueTemplateSave'; $Title = 'Translate:AdminChecklistQueueAssignTemplates';
        }
        elsif ( $Action eq 'ServiceTemplate' ) {
            $List = $Param{Services}; $IDName = 'ServiceID'; $ReverseMethod = 'ServiceTemplateIDs'; $ListName = 'Services';
            $Step = 'ChecklistServiceTemplateSave'; $Title = 'Translate:AdminChecklistServiceAssignTemplates';
        }
        else {
            $List = $Param{Customers}; $IDName = 'CustomerID'; $ReverseMethod = 'CustomerTemplateIDs'; $ListName = 'Customers';
            $Step = 'ChecklistCustomerTemplateSave'; $Title = 'Translate:AdminChecklistCustomerAssignTemplates';
        }
        $PrimaryID = $Param{Request}->{$IDName} || 0;
        ($Primary) = grep { ( $_->{id} || 0 ) == $PrimaryID } @{ $List || [] };
        return ( Invalid => 1 ) if !$Primary;
        $PrimaryName = $IDName;
        $Rows = $Param{Templates};
        $Selected = $Object->$ReverseMethod( $IDName => $PrimaryID );
    }

    my %Selected = map { $_ => 1 } @{ $Selected || [] };
    for my $Row ( @{ $Rows || [] } ) {
        $Row->{assignment_checked} = $Selected{ $Row->{id} || 0 } ? 'checked' : '';
        $Row->{assignment_label} = $Row->{full_name} || $Row->{name}
            || ( ( $Row->{customer_number} || '' ) ? ( $Row->{customer_number} . ' - ' . ( $Row->{name} || '' ) ) : '' );
    }

    return (
        Title       => $Title,
        Subtitle    => $Primary->{full_name} || $Primary->{name} || $Primary->{customer_number} || '',
        Step        => $Step,
        PrimaryName => $PrimaryName,
        PrimaryID   => $PrimaryID,
        Rows        => $Rows || [],
    );
}

sub _ItemsFromRequest {
    my ( $Self, %Param ) = @_;
    my $Request = $Param{Request} || {};

    my %Index;
    for my $Value ( @{ $Self->_ValueList( $Request->{ItemRowIndex} ) } ) {
        $Index{$Value} = 1 if defined $Value && $Value =~ m{\A\d+\z};
    }

    # Fallback: derive row indexes directly from the submitted input names.
    # This makes checklist item processing independent of the helper field and
    # also preserves dynamically added rows if a browser or proxy omits it.
    for my $Key ( keys %{$Request} ) {
        if ( $Key =~ m{\AItem(?:ID|Name|Description|Required|SortOrder)_(\d+)\z} ) {
            $Index{$1} = 1;
        }
    }

    my @Items;
    for my $Index ( sort { $a <=> $b } keys %Index ) {
        push @Items, {
            ItemID      => $Request->{'ItemID_' . $Index} || 0,
            Name        => defined $Request->{'ItemName_' . $Index} ? $Request->{'ItemName_' . $Index} : '',
            Description => defined $Request->{'ItemDescription_' . $Index} ? $Request->{'ItemDescription_' . $Index} : '',
            IsRequired  => $Request->{'ItemRequired_' . $Index} ? 1 : 0,
            SortOrder  => $Request->{'ItemSortOrder_' . $Index} || ( ( $Index + 1 ) * 1000 ),
        };
    }
    return \@Items;
}

sub _IDList {
    my ( $Self, $Value ) = @_;
    return [ grep { defined $_ && $_ =~ m{\A\d+\z} && $_ > 0 } @{ $Self->_ValueList($Value) } ];
}

sub _ValueList {
    my ( $Self, $Value ) = @_;
    return [] if !defined $Value;
    return [ @{$Value} ] if ref $Value eq 'ARRAY';
    return [$Value];
}

1;
