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

package AdminCustomerServices;

use strict;
use warnings;
use utf8;

use QisutuAdmin;
use QisutuService;

sub new {
    my ( $Class, %Param ) = @_;
    my $Self = { Config => $Param{Config}, DB => $Param{DB}, Output => $Param{Output}, Program => $Param{Program} };
    bless $Self, $Class;
    return $Self;
}

sub Run {
    my ( $Self, %Param ) = @_;
    my $Request = $Param{Request} || {};
    my $User = $Param{User} || {};
    my $AdminObject = QisutuAdmin->new( Config => $Self->{Config}, DB => $Self->{DB} );
    my $ServiceObject = QisutuService->new( Config => $Self->{Config}, DB => $Self->{DB} );
    my $CustomerID = $Request->{CustomerID} || 0;

    if ( ( $Request->{Step} || '' ) eq 'CustomerServiceSave' ) {
        my $Rows = $ServiceObject->ServiceList();
        my @Assignments;
        for my $Row ( @{$Rows} ) {
            my $ID = $Row->{id} || 0;
            push @Assignments, {
                ServiceID => $ID,
                SLAID     => $Request->{ 'SLAID_' . $ID },
                Active    => $Request->{ 'ServiceActive_' . $ID } ? 1 : 0,
            };
        }

        my $OK = $ServiceObject->CustomerServiceSave(
            CustomerID     => $CustomerID,
            Assignments    => \@Assignments,
            ChangedByUserID => $User->{user_account_id},
        );
        return { Redirect => 'index.pl?Page=AdminCustomerServices;CustomerID=' . $CustomerID } if $OK && !$ServiceObject->Error();
    }

    my $CustomerList = $AdminObject->CustomerList();
    my $Customer;
    if ($CustomerID) {
        $Customer = $AdminObject->CustomerGet( CustomerID => $CustomerID );
        $CustomerID = 0 if !$Customer;
    }

    my $AssignmentList = $CustomerID ? $ServiceObject->CustomerServiceList( CustomerID => $CustomerID ) : [];
    for my $Row ( @{$AssignmentList} ) {
        $Row->{active_checked} = $Row->{assigned} ? 'checked' : '';
        $Row->{service_active_label} = $Row->{service_active} ? 'Translate:AdminActiveYes' : 'Translate:AdminActiveNo';
        $Row->{assignment_disabled} = $Row->{service_active} && @{ $Row->{sla_list} || [] } ? '' : 'disabled';
        $Row->{sla_options_html} = $Self->_SLAOptions(
            List => $Row->{sla_list}, SelectedID => $Row->{sla_id},
        );
    }

    my $Error = $ServiceObject->Error() || $AdminObject->Error() || '';

    return {
        Template => 'AdminCustomerServices.tt',
        Data => {
            PageTitle => 'Translate:AdminCustomerServicesTitle', ProgramTitle => 'Translate:AdminCustomerServicesTitle', ProgramDescription => 'Translate:AdminCustomerServicesDescription',
            FormAction => 'index.pl', CustomerList => $CustomerList, CustomerID => $CustomerID, CustomerName => $Customer ? $Customer->{name} : '',
            CustomerOptionsHTML => $Self->_CustomerOptions( List => $CustomerList, SelectedID => $CustomerID ),
            AssignmentList => $AssignmentList, HasCustomer => $CustomerID ? 1 : 0,
            ErrorMessage => $Error, ErrorClass => $Error ? '' : 'qisutu-hidden',
        },
    };
}

sub _CustomerOptions {
    my ( $Self, %Param ) = @_;
    my $HTML = '';
    for my $Row ( @{ $Param{List} || [] } ) {
        my $Selected = ( $Row->{id} || 0 ) == ( $Param{SelectedID} || 0 ) ? ' selected' : '';
        my $Label = ( $Row->{name} || '' ) . ( ( $Row->{customer_number} || '' ) ne '' ? ' (' . $Row->{customer_number} . ')' : '' );
        $HTML .= '<option value="' . $Self->{Output}->HTMLEscape( $Row->{id} || '' ) . '"' . $Selected . '>' . $Self->{Output}->HTMLEscape($Label) . '</option>';
    }
    return $HTML;
}

sub _SLAOptions {
    my ( $Self, %Param ) = @_;
    my $HTML = '';
    for my $Row ( @{ $Param{List} || [] } ) {
        my $Selected = ( $Row->{id} || 0 ) == ( $Param{SelectedID} || 0 ) ? ' selected' : '';
        $HTML .= '<option value="' . $Self->{Output}->HTMLEscape( $Row->{id} || '' ) . '"' . $Selected . '>' . $Self->{Output}->HTMLEscape( $Row->{name} || '' ) . '</option>';
    }
    return $HTML;
}

1;
