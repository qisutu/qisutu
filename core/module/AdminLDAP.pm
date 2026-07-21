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

package AdminLDAP;

use strict;
use warnings;
use utf8;

use QisutuLDAP;

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

sub Run {
    my ( $Self, %Param ) = @_;

    my $Request = $Param{Request} || {};
    my $User    = $Param{User} || {};
    my $Step    = $Self->_Scalar( $Request->{Step} );
    my $ProfileType = $Self->_Scalar( $Request->{ProfileType} ) || 'agent';
    $ProfileType = 'agent' if $ProfileType ne 'agent' && $ProfileType ne 'customer';
    my $ObjectType = $ProfileType eq 'customer' ? 'customer_user' : 'agent';
    my $UserID  = $User->{user_account_id} || 1;
    my $Language = $Self->_Scalar( $Request->{Language} )
        || $Self->{Config}->{Language}->{Default} || 'en';
    $Self->{Language} = $Language;
    my $LDAP = QisutuLDAP->new( Config => $Self->{Config}, DB => $Self->{DB} );
    my $ErrorMessage = '';
    my $NoticeMessage = '';
    my $NoticeClass = 'qisutu-hidden';

    my $AllFieldDefinitions = $LDAP->FieldDefinitionList( Language => $Language ) || [];
    my $FieldDefinitions = [
        grep { ( $_->{object_type} || '' ) eq $ObjectType } @{$AllFieldDefinitions}
    ];
    my $Configuration = $LDAP->ConfigurationGet( ProfileType => $ProfileType ) || {};
    my $ConfigurationID = $Configuration->{id} || 0;

    if ( $Step eq 'LDAPConfigurationSave' ) {
        my $SavedID = $LDAP->ConfigurationSave(
            ConfigurationID     => $Request->{ConfigurationID},
            ProfileType         => $ProfileType,
            Name                => $Request->{Name},
            DirectoryType       => $Request->{DirectoryType},
            Host                => $Request->{Host},
            Port                => $Request->{Port},
            ConnectionSecurity  => $Request->{ConnectionSecurity},
            VerifyCertificate   => $Request->{VerifyCertificate},
            CAFile              => $Request->{CAFile},
            BindDN              => $Request->{BindDN},
            BindPassword        => $Request->{BindPassword},
            BaseDN              => $Request->{BaseDN},
            UserFilter          => $Request->{UserFilter},
            LoginAttribute      => $Request->{LoginAttribute},
            FirstnameAttribute  => $Request->{FirstnameAttribute},
            LastnameAttribute   => $Request->{LastnameAttribute},
            EmailAttribute      => $Request->{EmailAttribute},
            CustomerNumberAttribute => $Request->{CustomerNumberAttribute},
            CustomerNameAttribute   => $Request->{CustomerNameAttribute},
            DefaultGroupID      => $Request->{DefaultGroupID},
            UpdateOnLogin       => $Request->{UpdateOnLogin},
            Mappings            => $Self->_MappingsFromRequest(
                Request          => $Request,
                FieldDefinitions => $FieldDefinitions,
            ),
            ChangedByUserID     => $UserID,
        );
        if ($SavedID) {
            return { Redirect => 'index.pl?Page=AdminLDAP;ProfileType=' . $ProfileType . ';Status=saved' };
        }
        $ErrorMessage = $LDAP->Error();
    }
    elsif ( $Step eq 'LDAPConfigurationTest' ) {
        my $Result = $LDAP->ConfigurationTest(
            ConfigurationID => $Request->{ConfigurationID},
            ProfileType     => $ProfileType,
            TestLogin       => $Request->{TestLogin},
            TestPassword    => $Request->{TestPassword},
            ChangedByUserID => $UserID,
        );
        if ($Result) {
            $NoticeMessage = $Result->{Message};
            $NoticeClass = 'qisutu-form-success';
        }
        else {
            $ErrorMessage = $LDAP->Error();
        }
    }
    elsif ( $Step eq 'LDAPConfigurationActivate' ) {
        if ( $LDAP->ConfigurationActivate(
            ConfigurationID => $Request->{ConfigurationID},
            ProfileType     => $ProfileType,
            ChangedByUserID => $UserID,
        ) ) {
            return { Redirect => 'index.pl?Page=AdminLDAP;ProfileType=' . $ProfileType . ';Status=activated' };
        }
        $ErrorMessage = $LDAP->Error();
    }
    elsif ( $Step eq 'LDAPConfigurationDeactivate' ) {
        if ( $LDAP->ConfigurationDeactivate(
            ConfigurationID => $Request->{ConfigurationID},
            ProfileType     => $ProfileType,
            ChangedByUserID => $UserID,
        ) ) {
            return { Redirect => 'index.pl?Page=AdminLDAP;ProfileType=' . $ProfileType . ';Status=deactivated' };
        }
        $ErrorMessage = $LDAP->Error();
    }

    $Configuration = $LDAP->ConfigurationGet( ProfileType => $ProfileType ) || {};
    $ConfigurationID = $Configuration->{id} || 0;
    my $FieldMappings = $ConfigurationID
        ? ( $LDAP->FieldMappingList( ConfigurationID => $ConfigurationID ) || [] )
        : [];
    my %MappingByField = map {
        ( ( $_->{object_type} || '' ) . ':' . ( $_->{field_id} || 0 ) => $_ )
    } @{$FieldMappings};

    my $Submitted = $Step eq 'LDAPConfigurationSave' && $ErrorMessage ? 1 : 0;
    my $Source = $Submitted ? $Request : $Configuration;
    my ( @AgentMapping, @CustomerMapping );
    for my $Field ( @{$FieldDefinitions} ) {
        my $Key = ( $Field->{object_type} || '' ) . ':' . ( $Field->{id} || 0 );
        my $Stored = $MappingByField{$Key} || {};
        my $Prefix = 'Mapping_' . ( $Field->{object_type} || '' ) . '_' . ( $Field->{id} || 0 );
        my $Attribute = $Submitted
            ? $Self->_Scalar( $Request->{ $Prefix . '_Attribute' } )
            : ( $Stored->{ldap_attribute} || '' );
        my $QisutuRequired = $Field->{is_required} ? 1 : 0;
        my $Required = $QisutuRequired ? 1 : $Submitted
            ? ( $Request->{ $Prefix . '_Required' } ? 1 : 0 )
            : ( $Stored->{is_required} ? 1 : 0 );
        my $Update = $Submitted
            ? ( $Request->{ $Prefix . '_Update' } ? 1 : 0 )
            : ( exists $Stored->{update_on_login} ? ( $Stored->{update_on_login} ? 1 : 0 ) : 1 );
        my $Clear = $Submitted
            ? ( $Request->{ $Prefix . '_Clear' } ? 1 : 0 )
            : ( $Stored->{clear_empty} ? 1 : 0 );
        my $Row = {
            id                 => $Field->{id},
            name               => $Field->{name},
            label              => $Field->{label},
            field_type         => $Field->{field_type},
            qisutu_required    => $Field->{is_required} ? 'Translate:LDAPFieldRequiredInQisutu' : '',
            input_name         => $Prefix . '_Attribute',
            required_name      => $Prefix . '_Required',
            update_name        => $Prefix . '_Update',
            clear_name         => $Prefix . '_Clear',
            ldap_attribute     => $Attribute,
            attribute_required => $QisutuRequired ? 'required' : '',
            required_checked   => $Required ? 'checked' : '',
            required_disabled  => $QisutuRequired ? 'disabled' : '',
            update_checked     => $Update ? 'checked' : '',
            clear_checked      => $Clear ? 'checked' : '',
        };
        if ( ( $Field->{object_type} || '' ) eq 'agent' ) {
            push @AgentMapping, $Row;
        }
        else {
            push @CustomerMapping, $Row;
        }
    }

    my $Status = $Self->_Scalar( $Request->{Status} );
    if ( !$NoticeMessage && $Status ) {
        my %Message = (
            saved       => 'Translate:LDAPConfigurationSavedTestRequired',
            activated   => 'Translate:LDAPConfigurationActivated',
            deactivated => 'Translate:LDAPConfigurationDeactivated',
        );
        $NoticeMessage = $Message{$Status} || '';
        $NoticeClass = $NoticeMessage ? 'qisutu-form-success' : 'qisutu-hidden';
    }
    $ErrorMessage ||= $LDAP->Error() || '';

    my $DirectoryType = $Self->_SourceValue( $Source, 'DirectoryType', 'directory_type', 'active_directory' );
    my $ConnectionSecurity = $Self->_SourceValue( $Source, 'ConnectionSecurity', 'connection_security', 'ldaps' );
    my $VerifyCertificate = $Submitted
        ? ( $Request->{VerifyCertificate} ? 1 : 0 )
        : ( !$ConfigurationID || $Configuration->{verify_certificate} ? 1 : 0 );
    my $UpdateOnLogin = $Submitted
        ? ( $Request->{UpdateOnLogin} ? 1 : 0 )
        : ( !$ConfigurationID || $Configuration->{update_on_login} ? 1 : 0 );

    return {
        Template => 'AdminLDAP.tt',
        Data     => {
            PageTitle          => $ProfileType eq 'agent'
                ? 'Translate:LDAPAgentProfileTitle' : 'Translate:LDAPCustomerProfileTitle',
            ProgramTitle       => $ProfileType eq 'agent'
                ? 'Translate:LDAPAgentProfileTitle' : 'Translate:LDAPCustomerProfileTitle',
            ProgramDescription => $ProfileType eq 'agent'
                ? 'Translate:LDAPAgentProfileDescription' : 'Translate:LDAPCustomerProfileDescription',
            FormAction         => 'index.pl',
            ProfileType        => $ProfileType,
            IsAgentProfile     => $ProfileType eq 'agent' ? 1 : 0,
            IsCustomerProfile  => $ProfileType eq 'customer' ? 1 : 0,
            AgentProfileClass  => $ProfileType eq 'agent' ? 'qisutu-button-primary' : 'qisutu-button-secondary',
            CustomerProfileClass => $ProfileType eq 'customer' ? 'qisutu-button-primary' : 'qisutu-button-secondary',
            ErrorMessage       => $ErrorMessage,
            ErrorClass         => $ErrorMessage ? 'qisutu-form-error' : 'qisutu-hidden',
            NoticeMessage      => $NoticeMessage,
            NoticeClass        => $NoticeMessage ? $NoticeClass : 'qisutu-hidden',
            ConfigurationID    => $ConfigurationID,
            HasConfiguration   => $ConfigurationID ? 1 : 0,
            LDAPActive         => $Configuration->{active} ? 1 : 0,
            LDAPInactive       => $Configuration->{active} ? 0 : 1,
            LDAPTested         => ( $Configuration->{last_test_status} || '' ) eq 'success' ? 1 : 0,
            LDAPModuleMissing  => $LDAP->ModuleAvailable() ? 0 : 1,
            ConfigurationName  => $Self->_SourceValue(
                $Source, 'Name', 'name',
                $ProfileType eq 'agent' ? 'Agenten-LDAP / Active Directory' : 'Kunden-LDAP / Active Directory',
            ),
            DirectoryTypeOptionsHTML => $Self->_Options(
                Selected => $DirectoryType,
                Options  => [
                    [ active_directory => 'Translate:LDAPDirectoryTypeActiveDirectory' ],
                    [ ldap             => 'Translate:LDAPDirectoryTypeLDAP' ],
                ],
            ),
            LDAPHost           => $Self->_SourceValue( $Source, 'Host', 'host', '' ),
            LDAPPort           => $Self->_SourceValue( $Source, 'Port', 'port', 636 ),
            SecurityOptionsHTML => $Self->_Options(
                Selected => $ConnectionSecurity,
                Options  => [
                    [ ldaps    => 'Translate:LDAPSecurityLDAPS' ],
                    [ starttls => 'Translate:LDAPSecurityStartTLS' ],
                ],
            ),
            VerifyCertificateChecked => $VerifyCertificate ? 'checked' : '',
            LDAPCAFile         => $Self->_SourceValue( $Source, 'CAFile', 'ca_file', '' ),
            LDAPBindDN         => $Self->_SourceValue( $Source, 'BindDN', 'bind_dn', '' ),
            LDAPHasBindPassword => $Configuration->{has_bind_password} ? 1 : 0,
            LDAPBaseDN         => $Self->_SourceValue( $Source, 'BaseDN', 'base_dn', '' ),
            LDAPUserFilter     => $Self->_SourceValue(
                $Source,
                'UserFilter',
                'user_filter',
                '(&(objectCategory=person)(objectClass=user)(!(userAccountControl:1.2.840.113556.1.4.803:=2)))',
            ),
            LDAPLoginAttribute => $Self->_SourceValue( $Source, 'LoginAttribute', 'login_attribute', 'sAMAccountName' ),
            LDAPFirstnameAttribute => $Self->_SourceValue( $Source, 'FirstnameAttribute', 'firstname_attribute', 'givenName' ),
            LDAPLastnameAttribute => $Self->_SourceValue( $Source, 'LastnameAttribute', 'lastname_attribute', 'sn' ),
            LDAPEmailAttribute => $Self->_SourceValue( $Source, 'EmailAttribute', 'email_attribute', 'mail' ),
            LDAPCustomerNumberAttribute => $Self->_SourceValue(
                $Source, 'CustomerNumberAttribute', 'customer_number_attribute', 'companyNumber',
            ),
            LDAPCustomerNameAttribute => $Self->_SourceValue(
                $Source, 'CustomerNameAttribute', 'customer_name_attribute', 'company',
            ),
            DefaultGroupOptionsHTML => $Self->_GroupOptions(
                Selected => $Self->_SourceValue( $Source, 'DefaultGroupID', 'default_group_id', 0 ),
            ),
            UpdateOnLoginChecked => $UpdateOnLogin ? 'checked' : '',
            AgentFieldMappings   => \@AgentMapping,
            CustomerFieldMappings => \@CustomerMapping,
            HasAgentFieldMappings => @AgentMapping ? 1 : 0,
            HasCustomerFieldMappings => @CustomerMapping ? 1 : 0,
            LDAPLastTestAt       => $Configuration->{last_test_at} || '',
            LDAPLastTestMessage  => $Configuration->{last_test_message} || '',
        },
    };
}

sub _MappingsFromRequest {
    my ( $Self, %Param ) = @_;
    my $Request = $Param{Request} || {};
    my @Mapping;
    for my $Field ( @{ $Param{FieldDefinitions} || [] } ) {
        my $ObjectType = $Field->{object_type} || '';
        my $FieldID    = $Field->{id} || 0;
        my $Prefix = 'Mapping_' . $ObjectType . '_' . $FieldID;
        push @Mapping, {
            ObjectType    => $ObjectType,
            FieldID       => $FieldID,
            LDAPAttribute => $Request->{ $Prefix . '_Attribute' },
            IsRequired    => $Field->{is_required} || $Request->{ $Prefix . '_Required' },
            UpdateOnLogin => $Request->{ $Prefix . '_Update' },
            ClearEmpty    => $Request->{ $Prefix . '_Clear' },
        };
    }
    return \@Mapping;
}

sub _GroupOptions {
    my ( $Self, %Param ) = @_;
    my $Selected = $Param{Selected} || 0;
    my $Rows = $Self->{DB}->SelectAll(
        'SELECT id, name, title FROM user_group WHERE active = 1 AND group_type = "agent"
         ORDER BY sort_order ASC, name ASC'
    ) || [];
    my $HTML = '<option value="0">' . $Self->_Escape( $Self->_Text('LDAPNoDefaultGroup') ) . '</option>';
    for my $Row ( @{$Rows} ) {
        my $ID = $Row->{id} || 0;
        my $Label = $Row->{name} || '';
        $Label .= ' – ' . $Row->{title} if $Row->{title};
        $HTML .= '<option value="' . $Self->_Escape($ID) . '"'
            . ( $ID == $Selected ? ' selected' : '' ) . '>'
            . $Self->_Escape($Label) . '</option>';
    }
    return $HTML;
}

sub _Options {
    my ( $Self, %Param ) = @_;
    my $HTML = '';
    for my $Option ( @{ $Param{Options} || [] } ) {
        my ( $Value, $Label ) = @{$Option};
        $HTML .= '<option value="' . $Self->_Escape($Value) . '"'
            . ( $Value eq ( $Param{Selected} || '' ) ? ' selected' : '' ) . '>'
            . $Self->_Escape( $Self->_Text( $Label =~ s{\ATranslate:}{}r ) ) . '</option>';
    }
    return $HTML;
}

sub _Text {
    my ( $Self, $Key ) = @_;
    return $Self->{Output}->Translate(
        Key      => $Key,
        Language => $Self->{Language} || $Self->{Config}->{Language}->{Default} || 'en',
    );
}

sub _SourceValue {
    my ( $Self, $Source, $RequestKey, $DatabaseKey, $Default ) = @_;
    return $Source->{$RequestKey} if exists $Source->{$RequestKey} && defined $Source->{$RequestKey};
    return $Source->{$DatabaseKey} if exists $Source->{$DatabaseKey} && defined $Source->{$DatabaseKey};
    return $Default;
}

sub _Escape {
    my ( $Self, $Value ) = @_;
    return $Self->{Output}->HTMLEscape( defined $Value ? $Value : '' );
}

sub _Scalar {
    my ( $Self, $Value ) = @_;
    return '' if !defined $Value || ref $Value;
    return $Value;
}

1;
