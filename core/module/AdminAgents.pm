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

package AdminAgents;

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

    my $Request = $Param{Request} || {};
    my $User    = $Param{User}    || {};
    my $Admin   = $Self->_AdminObject();
    my $Step    = $Request->{Step} || '';

    if ( $Admin && $Step eq 'AgentCreate' ) {
        $Admin->AgentCreate(
            Login           => $Request->{Login},
            Email           => $Request->{Email},
            Password        => $Request->{Password},
            Firstname       => $Request->{Firstname},
            Lastname        => $Request->{Lastname},
            Request         => $Request,
            ChangedByUserID => $User->{user_account_id},
        );

        return { Redirect => 'index.pl?Page=AdminAgents' } if !$Admin->Error();
    }
    elsif ( $Admin && $Step eq 'AgentUpdate' ) {
        $Admin->AgentUpdate(
            UserAccountID   => $Request->{UserAccountID},
            Login           => $Request->{Login},
            Email           => $Request->{Email},
            Password        => $Request->{Password},
            Firstname       => $Request->{Firstname},
            Lastname        => $Request->{Lastname},
            IsActive        => $Request->{IsActive},
            Request         => $Request,
            ChangedByUserID => $User->{user_account_id},
        );

        return { Redirect => 'index.pl?Page=AdminAgents;Action=Edit;UserAccountID=' . ( $Request->{UserAccountID} || 0 ) } if !$Admin->Error();
    }
    elsif ( $Admin && $Step eq 'AgentDeactivate' ) {
        $Admin->AgentDeactivate(
            UserAccountID   => $Request->{UserAccountID},
            ChangedByUserID => $User->{user_account_id},
        );

        return { Redirect => 'index.pl?Page=AdminAgents' } if !$Admin->Error();
    }
    elsif ( $Admin && $Step eq 'AgentActivate' ) {
        $Admin->AgentActivate(
            UserAccountID   => $Request->{UserAccountID},
            ChangedByUserID => $User->{user_account_id},
        );

        return { Redirect => 'index.pl?Page=AdminAgents' } if !$Admin->Error();
    }
    elsif ( $Admin && $Step eq 'AgentTwoFactorReset' ) {
        my $TwoFactor = $Self->_TwoFactorObject();
        if ($TwoFactor) {
            $TwoFactor->Reset(
                UserAccountID => $Request->{UserAccountID},
            );
            return {
                Redirect => 'index.pl?Page=AdminAgents;Action=Edit;UserAccountID=' . ( $Request->{UserAccountID} || 0 ) . ';TwoFactorReset=1'
            } if !$TwoFactor->Error();
            $Admin->{LastError} = $TwoFactor->Error();
        }
    }
    elsif ( $Admin && $Step eq 'AgentGroupPermissionUpdate' ) {
        $Admin->UserGroupPermissionUpdate(
            UserAccountID   => $Request->{UserAccountID},
            GroupID         => $Request->{GroupID},
            PermissionRead  => $Request->{PermissionRead},
            PermissionCreate => $Request->{PermissionCreate},
            PermissionChange => $Request->{PermissionChange},
            PermissionOverview => $Request->{PermissionOverview},
            PermissionFull  => $Request->{PermissionFull},
            ChangedByUserID => $User->{user_account_id},
        );

        return { Redirect => 'index.pl?Page=AdminAgents;Action=Edit;UserAccountID=' . ( $Request->{UserAccountID} || 0 ) } if !$Admin->Error();
    }
    elsif ( $Admin && $Step eq 'AgentGroupRemove' ) {
        $Admin->UserGroupRemove(
            UserAccountID   => $Request->{UserAccountID},
            GroupID         => $Request->{GroupID},
            ChangedByUserID => $User->{user_account_id},
        );

        return { Redirect => 'index.pl?Page=AdminAgents;Action=Edit;UserAccountID=' . ( $Request->{UserAccountID} || 0 ) } if !$Admin->Error();
    }
    elsif ( $Admin && $Step eq 'AgentDynamicFieldCreate' ) {
        $Admin->AgentDynamicFieldCreate(
            Name            => $Request->{Name},
            LabelByLanguage => $Self->_LabelByLanguageFromRequest(
                Admin   => $Admin,
                Request => $Request,
            ),
            FieldType       => $Request->{FieldType},
            IsRequired      => $Request->{IsRequired},
            SortOrder       => $Request->{SortOrder},
            ChangedByUserID => $User->{user_account_id},
        );

        return { Redirect => 'index.pl?Page=AdminAgents' } if !$Admin->Error();
    }
    elsif ( $Admin && $Step eq 'AgentDynamicFieldUpdate' ) {
        $Admin->AgentDynamicFieldUpdate(
            FieldID         => $Request->{FieldID},
            LabelByLanguage => $Self->_LabelByLanguageFromRequest(
                Admin   => $Admin,
                Request => $Request,
            ),
            FieldType       => $Request->{FieldType},
            IsRequired      => $Request->{IsRequired},
            Active          => $Request->{Active},
            SortOrder       => $Request->{SortOrder},
            ChangedByUserID => $User->{user_account_id},
        );

        return { Redirect => 'index.pl?Page=AdminAgents;Action=FieldEdit;FieldID=' . ( $Request->{FieldID} || 0 ) } if !$Admin->Error();
    }
    elsif ( $Admin && $Step eq 'AgentDynamicFieldDelete' ) {
        $Admin->AgentDynamicFieldDelete(
            FieldID         => $Request->{FieldID},
            ChangedByUserID => $User->{user_account_id},
        );

        return { Redirect => 'index.pl?Page=AdminAgents' } if !$Admin->Error();
    }

    my $Action     = $Request->{Action} || 'List';
    my $Language   = $Request->{Language} || $Self->{Config}->{Language}->{Default} || 'en';
    my $AgentList  = $Admin ? $Admin->AgentList() : [];
    my $GroupList  = $Admin ? $Admin->GroupList() : [];
    my $LanguageList = $Admin ? $Admin->LanguageList() : [];
    my $FieldList  = $Admin ? $Admin->AgentDynamicFieldList( Language => $Language, IncludeInactive => 1 ) : [];
    my $ActiveFieldList = $Admin ? $Admin->AgentDynamicFieldList( Language => $Language ) : [];
    my $Agent;
    my $Field;
    my $AgentGroupList = [];
    my $FieldTranslation = {};
    my $FieldValue = {};

    my $AuthenticationLocalLabel = $Self->{Output}->Translate(
        Key      => 'AdminAuthenticationLocal',
        Language => $Language,
    );
    my $AuthenticationLDAPLabel = $Self->{Output}->Translate(
        Key      => 'AdminAuthenticationLDAP',
        Language => $Language,
    );
    my $AuthenticationExternalLabel = $Self->{Output}->Translate(
        Key      => 'AdminAuthenticationExternal',
        Language => $Language,
    );
    for my $AgentEntry ( @{$AgentList} ) {
        my $AuthenticationType = $AgentEntry->{authentication_type} || 'local';
        $AgentEntry->{authentication_label} = $AuthenticationType eq 'ldap'
            ? $AuthenticationLDAPLabel
            : ( $AuthenticationType eq 'external' ? $AuthenticationExternalLabel : $AuthenticationLocalLabel );
        $AgentEntry->{action_step} = $AgentEntry->{is_active} ? 'AgentDeactivate' : 'AgentActivate';
        $AgentEntry->{action_label} = $AgentEntry->{is_active} ? 'Translate:AdminDeactivate' : 'Translate:AdminActivate';
        $AgentEntry->{action_button_class} = $AgentEntry->{is_active} ? 'qisutu-button-danger' : 'qisutu-button-primary';
    }

    if ( $Admin && $Action eq 'Edit' ) {
        $Agent = $Admin->AgentGet( UserAccountID => $Request->{UserAccountID} );
        if ($Agent) {
            $FieldValue = $Admin->AgentDynamicFieldValueList(
                UserAccountID => $Agent->{id},
            );
            $AgentGroupList = $Admin->UserGroupList(
                UserAccountID => $Agent->{id},
            );

            for my $Group ( @{$AgentGroupList} ) {
                $Group->{permission_read_checked}     = $Group->{permission_read} ? 'checked' : '';
                $Group->{permission_create_checked}   = $Group->{permission_create} ? 'checked' : '';
                $Group->{permission_change_checked}   = $Group->{permission_change} ? 'checked' : '';
                $Group->{permission_overview_checked} = $Group->{permission_overview} ? 'checked' : '';
                $Group->{permission_full_checked}     = $Group->{permission_full} ? 'checked' : '';
            }
        }
        else {
            $Action = 'List';
        }
    }

    if ( $Admin && $Action eq 'FieldEdit' ) {
        $Field = $Admin->AgentDynamicFieldGet( FieldID => $Request->{FieldID} );
        if ($Field) {
            $FieldTranslation = $Admin->AgentDynamicFieldTranslationList(
                FieldID => $Field->{id},
            );
        }
        else {
            $Action = 'List';
        }
    }

    my $ErrorMessage = $Admin ? $Admin->Error() : '';
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
        Value     => {},
        MinRows   => 1,
        Language  => $Language,
    );
    my $EditTranslationRows = $Self->_TranslationRows(
        Value     => $FieldTranslation,
        MinRows   => 1,
        Language  => $Language,
    );

    return {
        Template => 'AdminAgents.tt',
        Data     => {
            PageTitle          => 'Translate:AdminAgentsTitle',
            ProgramTitle       => 'Translate:AdminAgentsTitle',
            ProgramDescription => 'Translate:AdminAgentsDescription',
            AgentList          => $AgentList,
            GroupList          => $GroupList,
            AgentGroupList     => $AgentGroupList,
            FieldList          => $FieldList,
            LanguageList       => $LanguageList,
            AgentCount         => scalar @{$AgentList},
            ErrorMessage       => $ErrorMessage,
            ErrorClass         => $ErrorMessage ? '' : 'qisutu-hidden',
            FormAction         => 'index.pl',
            ShowList           => $Action eq 'List' ? 1 : 0,
            ShowCreate         => $Action eq 'Create' ? 1 : 0,
            ShowEdit           => $Action eq 'Edit' ? 1 : 0,
            ShowFieldCreate    => $Action eq 'FieldCreate' ? 1 : 0,
            ShowFieldEdit      => $Action eq 'FieldEdit' ? 1 : 0,
            AgentID            => $Agent ? $Agent->{id} : '',
            AgentLogin         => $Agent ? $Agent->{login} : '',
            AgentEmail         => $Agent ? $Agent->{email} : '',
            AgentFirstname     => $Agent ? $Agent->{firstname} : '',
            AgentLastname      => $Agent ? $Agent->{lastname} : '',
            AgentGroups        => $Agent ? $Agent->{group_names} : '',
            AgentAuthenticationLabel => $Agent && ( $Agent->{authentication_type} || 'local' ) eq 'ldap'
                ? $AuthenticationLDAPLabel
                : ( $Agent && ( $Agent->{authentication_type} || 'local' ) eq 'external'
                    ? $AuthenticationExternalLabel : $AuthenticationLocalLabel ),
            AgentLDAPAuthentication => $Agent && ( $Agent->{authentication_type} || 'local' ) eq 'ldap' ? 1 : 0,
            AgentActiveChecked => $Agent && $Agent->{is_active} ? 'checked' : '',
            TwoFactorResetSuccess => $Request->{TwoFactorReset} ? 1 : 0,
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

sub _TwoFactorObject {
    my ($Self) = @_;
    my $Loaded = eval { require QisutuTwoFactor; 1 };
    return if !$Loaded;
    return QisutuTwoFactor->new( Config => $Self->{Config}, DB => $Self->{DB} );
}

sub _DynamicFieldFormFields {
    my ( $Self, %Param ) = @_;

    my $FieldList  = $Param{FieldList} || [];
    my $FieldValue = $Param{FieldValue} || {};
    my $HTML       = '';

    for my $Field ( @{$FieldList} ) {
        my $FieldID  = $Field->{id};
        my $Name     = 'DynamicField_' . $FieldID;
        my $Label    = $Self->_Escape( $Field->{label} || $Field->{name} || '' );
        my $Value    = $Self->_Escape( $FieldValue->{$FieldID} || '' );
        my $Required = $Field->{is_required} ? ' required' : '';
        my $Type     = $Field->{field_type} || 'text';

        if ( $Type eq 'textarea' ) {
            $HTML .= '<div class="qisutu-form-field"><label>' . $Label . '</label><textarea name="' . $Name . '"' . $Required . '>' . $Value . '</textarea></div>';
        }
        else {
            if ( $Type eq 'phone' ) {
                $Type = 'text';
            }

            $HTML .= '<div class="qisutu-form-field"><label>' . $Label . '</label><input type="' . $Type . '" name="' . $Name . '" value="' . $Value . '"' . $Required . '></div>';
        }
    }

    return $HTML;
}

sub _FieldTypeOptions {
    my ( $Self, %Param ) = @_;

    my $Selected = $Param{Selected} || 'text';
    my @Types    = qw(text textarea email phone date number);
    my $HTML     = '';

    for my $Type (@Types) {
        my $SelectedAttribute = $Type eq $Selected ? ' selected' : '';
        my $EscapedType       = $Self->_Escape($Type);

        $HTML .= '<option value="' . $EscapedType . '"' . $SelectedAttribute . '>' . $EscapedType . '</option>';
    }

    return $HTML;
}

sub _TranslationRows {
    my ( $Self, %Param ) = @_;

    my $Value   = $Param{Value} || {};
    my $MinRows = $Param{MinRows} || 1;
    my $Language = $Param{Language} || $Self->{Config}->{Language}->{Default} || 'en';
    my @Codes   = sort keys %{$Value};
    my $HTML    = '';
    my $Index   = 0;

    if ( !@Codes ) {
        @Codes = ( $Self->{Config}->{Language}->{Default} || 'en' );
    }

    for my $Code (@Codes) {
        $Index++;
        $HTML .= $Self->_TranslationRowHTML(
            Index    => $Index,
            Language => $Code,
            Label    => $Value->{$Code} || '',
            UILanguage => $Language,
        );
    }

    while ( $Index < $MinRows ) {
        $Index++;
        $HTML .= $Self->_TranslationRowHTML(
            Index    => $Index,
            Language => '',
            Label    => '',
            UILanguage => $Language,
        );
    }

    return {
        HTML  => $HTML,
        Count => $Index,
    };
}

sub _TranslationRowHTML {
    my ( $Self, %Param ) = @_;

    my $Index    = $Param{Index} || 1;
    my $Language = $Param{Language} || '';
    my $Label    = $Param{Label} || '';
    my $UILanguage = $Param{UILanguage} || $Self->{Config}->{Language}->{Default} || 'en';
    my $LanguageLabel = $Self->{Output}
        ? $Self->{Output}->Translate( Key => 'AdminTranslationLanguage', Language => $UILanguage )
        : 'Language';
    my $DisplayNameLabel = $Self->{Output}
        ? $Self->{Output}->Translate( Key => 'AdminDisplayName', Language => $UILanguage )
        : 'Display name';
    my $RemoveLabel = $Self->{Output}
        ? $Self->{Output}->Translate( Key => 'AdminRemove', Language => $UILanguage )
        : 'Remove';

    return '<div class="qisutu-translation-row" data-qisutu-translation-row>'
        . '<div class="qisutu-form-field">'
        . '<label>' . $Self->_Escape($LanguageLabel) . '</label>'
        . '<select name="TranslationLanguage_' . $Index . '">'
        . $Self->_TranslationLanguageOptions( Selected => $Language )
        . '</select>'
        . '</div>'
        . '<div class="qisutu-form-field">'
        . '<label>' . $Self->_Escape($DisplayNameLabel) . '</label>'
        . '<input type="text" name="TranslationLabel_' . $Index . '" value="' . $Self->_Escape($Label) . '">'
        . '</div>'
        . '<button class="qisutu-button qisutu-button-secondary qisutu-button-small" type="button" data-qisutu-translation-remove>' . $Self->_Escape($RemoveLabel) . '</button>'
        . '</div>';
}

sub _LabelByLanguageFromRequest {
    my ( $Self, %Param ) = @_;

    my $Request = $Param{Request} || {};
    my %SupportedLanguage = map { $_ => 1 } qw(de en fr it es nl pl cs tr pt-BR pt-PT);
    my %Label;
    my $RowCount = $Request->{TranslationRowCount} || 0;

    if ( $RowCount !~ m{\A\d+\z} ) {
        $RowCount = 0;
    }

    if ( !$RowCount ) {
        for my $Key ( keys %{$Request} ) {
            if ( $Key =~ m{\ATranslationLanguage_(\d+)\z} && $1 > $RowCount ) {
                $RowCount = $1;
            }
        }
    }

    for my $Index ( 1 .. $RowCount ) {
        my $Code  = $Request->{ 'TranslationLanguage_' . $Index } || '';
        my $Value = $Request->{ 'TranslationLabel_' . $Index } || '';

        $Code =~ s{[^A-Za-z0-9_-]}{}g;
        next if !$Code || !$Value || !$SupportedLanguage{$Code};

        $Label{$Code} = $Value;
    }

    return \%Label;
}

sub _TranslationLanguageOptions {
    my ( $Self, %Param ) = @_;

    my $Selected = $Param{Selected} || '';
    my @Language = (
        [ ''      => '-' ],
        [ de      => 'de - German' ],
        [ en      => 'en - English' ],
        [ fr      => 'fr - French' ],
        [ it      => 'it - Italian' ],
        [ es      => 'es - Spanish' ],
        [ nl      => 'nl - Dutch' ],
        [ pl      => 'pl - Polish' ],
        [ cs      => 'cs - Czech' ],
        [ tr      => 'tr - Turkish' ],
        [ 'pt-BR' => 'pt-BR - Portuguese (Brazil)' ],
        [ 'pt-PT' => 'pt-PT - Portuguese (Portugal)' ],
    );
    my $HTML = '';

    for my $Language (@Language) {
        my ( $Code, $Label ) = @{$Language};
        my $SelectedAttribute = $Code eq $Selected ? ' selected' : '';

        $HTML .= '<option value="' . $Self->_Escape($Code) . '"' . $SelectedAttribute . '>' . $Self->_Escape($Label) . '</option>';
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
