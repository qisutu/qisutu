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

package AdminCustomerUsers;

use strict;
use warnings;
use utf8;
use parent 'AdminCustomers';

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

    my $Request = $Param{Request} || {};
    my $User    = $Param{User}    || {};
    my $Admin   = $Self->_AdminObject();
    my $Step    = $Request->{Step} || '';

    if ( $Admin && $Step eq 'CustomerUserCreate' ) {
        $Admin->CustomerUserCreate(
            CustomerID      => $Request->{CustomerID},
            Login           => $Request->{Login},
            Email           => $Request->{Email},
            Password        => $Request->{Password},
            Firstname       => $Request->{Firstname},
            Lastname        => $Request->{Lastname},
            Request         => $Request,
            ChangedByUserID => $User->{user_account_id},
        );

        if ( !$Admin->Error() ) {
            my $AssignedTicketCount = $Admin->CustomerUserAutoAssignTicketCount();
            my $Redirect = 'index.pl?Page=AdminCustomerUsers';
            if ($AssignedTicketCount) {
                $Redirect .= ';AutoAssignedTicketCount=' . $AssignedTicketCount;
            }

            return { Redirect => $Redirect };
        }
    }
    elsif ( $Admin && $Step eq 'CustomerUserUpdate' ) {
        $Admin->CustomerUserUpdate(
            CustomerUserID  => $Request->{CustomerUserID},
            CustomerID      => $Request->{CustomerID},
            Login           => $Request->{Login},
            Email           => $Request->{Email},
            Password        => $Request->{Password},
            Firstname       => $Request->{Firstname},
            Lastname        => $Request->{Lastname},
            Active          => $Request->{Active},
            Request         => $Request,
            ChangedByUserID => $User->{user_account_id},
        );

        return { Redirect => 'index.pl?Page=AdminCustomerUsers;Action=Edit;CustomerUserID=' . ( $Request->{CustomerUserID} || 0 ) } if !$Admin->Error();
    }
    elsif ( $Admin && $Step eq 'CustomerUserDeactivate' ) {
        $Admin->CustomerUserDeactivate(
            CustomerUserID  => $Request->{CustomerUserID},
            ChangedByUserID => $User->{user_account_id},
        );

        return { Redirect => 'index.pl?Page=AdminCustomerUsers' } if !$Admin->Error();
    }
    elsif ( $Admin && $Step eq 'CustomerUserDynamicFieldCreate' ) {
        $Admin->CustomerUserDynamicFieldCreate(
            Name            => $Request->{Name},
            LabelByLanguage => $Self->_LabelByLanguageFromRequest(
                Request => $Request,
            ),
            FieldType       => $Request->{FieldType},
            IsRequired      => $Request->{IsRequired},
            SortOrder       => $Request->{SortOrder},
            ChangedByUserID => $User->{user_account_id},
        );

        return { Redirect => 'index.pl?Page=AdminCustomerUsers' } if !$Admin->Error();
    }
    elsif ( $Admin && $Step eq 'CustomerUserDynamicFieldUpdate' ) {
        $Admin->CustomerUserDynamicFieldUpdate(
            FieldID         => $Request->{FieldID},
            LabelByLanguage => $Self->_LabelByLanguageFromRequest(
                Request => $Request,
            ),
            FieldType       => $Request->{FieldType},
            IsRequired      => $Request->{IsRequired},
            Active          => $Request->{Active},
            SortOrder       => $Request->{SortOrder},
            ChangedByUserID => $User->{user_account_id},
        );

        return { Redirect => 'index.pl?Page=AdminCustomerUsers;Action=FieldEdit;FieldID=' . ( $Request->{FieldID} || 0 ) } if !$Admin->Error();
    }
    elsif ( $Admin && $Step eq 'CustomerUserDynamicFieldDelete' ) {
        $Admin->CustomerUserDynamicFieldDelete(
            FieldID         => $Request->{FieldID},
            ChangedByUserID => $User->{user_account_id},
        );

        return { Redirect => 'index.pl?Page=AdminCustomerUsers' } if !$Admin->Error();
    }

    my $Action           = $Request->{Action} || 'List';
    my $Language         = $Request->{Language} || $Self->{Config}->{Language}->{Default} || 'en';
    my $CustomerList     = $Admin ? $Admin->CustomerList() : [];
    my $CustomerUserList = $Admin ? $Admin->CustomerUserList() : [];
    my $FieldList        = $Admin ? $Admin->CustomerUserDynamicFieldList( Language => $Language, IncludeInactive => 1 ) : [];
    my $ActiveFieldList  = $Admin ? $Admin->CustomerUserDynamicFieldList( Language => $Language ) : [];
    my $CustomerUser;
    my $Field;
    my $FieldTranslation = {};
    my $FieldValue       = {};

    if ( $Admin && $Action eq 'Edit' ) {
        $CustomerUser = $Admin->CustomerUserGet( CustomerUserID => $Request->{CustomerUserID} );
        if ( !$CustomerUser ) {
            $Action = 'List';
        }
        else {
            $FieldValue = $Admin->CustomerUserDynamicFieldValueList(
                CustomerUserID => $CustomerUser->{id},
            );
        }
    }

    if ( $Admin && $Action eq 'FieldEdit' ) {
        $Field = $Admin->CustomerUserDynamicFieldGet( FieldID => $Request->{FieldID} );
        if ($Field) {
            $FieldTranslation = $Admin->CustomerUserDynamicFieldTranslationList(
                FieldID => $Field->{id},
            );
        }
        else {
            $Action = 'List';
        }
    }

    my $ErrorMessage = $Admin ? $Admin->Error() : '';
    my $SuccessMessage = '';
    my $AutoAssignedTicketCount = $Request->{AutoAssignedTicketCount} || 0;

    if ( $AutoAssignedTicketCount =~ m{\A\d+\z} && $AutoAssignedTicketCount > 0 ) {
        if ( $AutoAssignedTicketCount == 1 ) {
            $SuccessMessage = 'Customer user created. 1 existing ticket was assigned automatically.';
        }
        else {
            $SuccessMessage = 'Customer user created. ' . $AutoAssignedTicketCount . ' existing tickets were assigned automatically.';
        }
    }

    my $CreateFields = $Self->_DynamicFieldFormFields(
        FieldList  => $ActiveFieldList,
        FieldValue => {},
    );
    my $EditFields = $Self->_DynamicFieldFormFields(
        FieldList  => $ActiveFieldList,
        FieldValue => $FieldValue,
    );
    my $TranslationLanguageOptions = $Self->_TranslationLanguageOptions(
        Selected => '',
    );
    my $CreateTranslationRows = $Self->_TranslationRows(
        Value    => {},
        MinRows  => 1,
        Language => $Language,
    );
    my $EditTranslationRows = $Self->_TranslationRows(
        Value    => $FieldTranslation,
        MinRows  => 1,
        Language => $Language,
    );

    return {
        Template => 'AdminCustomerUsers.tt',
        Data     => {
            PageTitle          => 'Translate:AdminCustomerUsersTitle',
            ProgramTitle       => 'Translate:AdminCustomerUsersTitle',
            ProgramDescription => 'Translate:AdminCustomerUsersDescription',
            CustomerList       => $CustomerList,
            CustomerUserList   => $CustomerUserList,
            FieldList          => $FieldList,
            CustomerUserCount  => scalar @{$CustomerUserList},
            ErrorMessage       => $ErrorMessage,
            ErrorClass         => $ErrorMessage ? '' : 'qisutu-hidden',
            SuccessMessage     => $SuccessMessage,
            SuccessClass       => $SuccessMessage ? '' : 'qisutu-hidden',
            FormAction         => 'index.pl',
            ShowList           => $Action eq 'List' ? 1 : 0,
            ShowCreate         => $Action eq 'Create' ? 1 : 0,
            ShowEdit           => $Action eq 'Edit' ? 1 : 0,
            ShowFieldCreate    => $Action eq 'FieldCreate' ? 1 : 0,
            ShowFieldEdit      => $Action eq 'FieldEdit' ? 1 : 0,
            CustomerUserID     => $CustomerUser ? $CustomerUser->{id} : '',
            CustomerUserLogin  => $CustomerUser ? $CustomerUser->{login} : '',
            CustomerUserEmail  => $CustomerUser ? $CustomerUser->{email} : '',
            CustomerUserFirstname => $CustomerUser ? $CustomerUser->{firstname} : '',
            CustomerUserLastname  => $CustomerUser ? $CustomerUser->{lastname} : '',
            CustomerUserCustomer  => $CustomerUser ? $CustomerUser->{customer_number} . ' - ' . $CustomerUser->{customer_name} : '',
            CustomerUserActiveChecked => $CustomerUser && $CustomerUser->{active} ? 'checked' : '',
            CustomerCreateOptionsHTML => $Self->_CustomerOptions(
                CustomerList => $CustomerList,
            ),
            CustomerEditOptionsHTML => $Self->_CustomerOptions(
                CustomerList => $CustomerList,
                SelectedID   => $CustomerUser ? $CustomerUser->{customer_id} : '',
            ),
            FieldID            => $Field ? $Field->{id} : '',
            FieldName          => $Field ? $Field->{name} : '',
            FieldType          => $Field ? $Field->{field_type} : '',
            FieldSortOrder     => $Field ? $Field->{sort_order} : '',
            FieldRequiredChecked => $Field && $Field->{is_required} ? 'checked' : '',
            FieldActiveChecked   => $Field && $Field->{active} ? 'checked' : '',
            CreateDynamicFieldsHTML => $CreateFields,
            EditDynamicFieldsHTML   => $EditFields,
            TranslationLanguageOptionsHTML => $TranslationLanguageOptions,
            CreateTranslationRowsHTML      => $CreateTranslationRows->{HTML},
            CreateTranslationRowCount      => $CreateTranslationRows->{Count},
            EditTranslationRowsHTML        => $EditTranslationRows->{HTML},
            EditTranslationRowCount        => $EditTranslationRows->{Count},
            FieldCreateTypeOptionsHTML => $Self->_FieldTypeOptions(),
            FieldEditTypeOptionsHTML   => $Self->_FieldTypeOptions(
                Selected => $Field ? $Field->{field_type} : '',
            ),
        },
    };
}

sub _CustomerOptions {
    my ( $Self, %Param ) = @_;

    my $CustomerList = $Param{CustomerList} || [];
    my $SelectedID   = $Param{SelectedID} || '';
    my $HTML         = '';

    for my $Customer ( @{$CustomerList} ) {
        next if ref $Customer ne 'HASH';

        my $ID       = $Customer->{id} || '';
        my $Selected = $ID && $ID eq $SelectedID ? ' selected' : '';
        my $Label    = ( $Customer->{customer_number} || '' ) . ' - ' . ( $Customer->{name} || '' );

        $HTML .= '<option value="' . $Self->_Escape($ID) . '"' . $Selected . '>' . $Self->_Escape($Label) . '</option>';
    }

    return $HTML;
}

sub _Escape {
    my ( $Self, $Value ) = @_;

    if ( $Self->{Output} ) {
        return $Self->{Output}->HTMLEscape($Value);
    }

    $Value = '' if !defined $Value;
    $Value =~ s/&/&amp;/g;
    $Value =~ s/</&lt;/g;
    $Value =~ s/>/&gt;/g;
    $Value =~ s/"/&quot;/g;
    $Value =~ s/'/&#39;/g;

    return $Value;
}

sub _AdminObject {
    my ($Self) = @_;

    return if !$Self->{DB};

    my $Loaded = eval {
        require QisutuAdmin;
        1;
    };

    return if !$Loaded;

    return QisutuAdmin->new(
        Config => $Self->{Config},
        DB     => $Self->{DB},
    );
}

1;
