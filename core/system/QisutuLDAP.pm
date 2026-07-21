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

package QisutuLDAP;

use strict;
use warnings;
use utf8;

use Encode qw(decode encode FB_DEFAULT);
use QisutuSecurity;

sub new {
    my ( $Class, %Param ) = @_;

    my $Self = {
        Config                 => $Param{Config} || {},
        DB                     => $Param{DB},
        DirectoryAuthenticator => $Param{DirectoryAuthenticator},
        Security               => QisutuSecurity->new( Config => $Param{Config} || {} ),
        LastError              => '',
    };

    bless $Self, $Class;
    return $Self;
}

sub Error {
    return $_[0]->{LastError} || '';
}

sub ModuleAvailable {
    return eval { require Net::LDAP; 1 } ? 1 : 0;
}

sub ConfigurationGet {
    my ( $Self, %Param ) = @_;
    $Self->{LastError} = '';

    my $SQL = 'SELECT * FROM ldap_configuration';
    my @Bind;
    my @Where;

    if ( $Param{ConfigurationID} ) {
        push @Where, 'id = ?';
        push @Bind, $Param{ConfigurationID};
    }
    if ( $Param{ProfileType} ) {
        my $ProfileType = $Self->_ProfileType( $Param{ProfileType} );
        return {} if !$ProfileType;
        push @Where, 'profile_type = ?';
        push @Bind, $ProfileType;
    }
    if ( $Param{Active} ) {
        push @Where, 'active = 1';
    }

    $SQL .= ' WHERE ' . join( ' AND ', @Where ) if @Where;
    $SQL .= ' ORDER BY active DESC, id ASC LIMIT 1';
    my $Configuration = $Self->{DB}->SelectRow( $SQL, @Bind );
    return {} if !$Configuration && !$Self->{DB}->Error();

    if ( !$Configuration ) {
        $Self->{LastError} = $Self->{DB}->Error() || 'Translate:LDAPConfigurationLoadFailed';
        return {};
    }

    $Configuration->{has_bind_password} = $Configuration->{bind_password_encrypted} ? 1 : 0;
    delete $Configuration->{bind_password_encrypted} if !$Param{IncludeEncryptedSecret};
    return $Configuration;
}

sub ConfigurationSave {
    my ( $Self, %Param ) = @_;
    $Self->{LastError} = '';

    my $ProfileType = $Self->_ProfileType( $Param{ProfileType} || 'agent' );
    return if !$ProfileType;

    my $Existing = $Param{ConfigurationID}
        ? $Self->ConfigurationGet(
            ConfigurationID     => $Param{ConfigurationID},
            ProfileType         => $ProfileType,
            IncludeEncryptedSecret => 1,
        )
        : $Self->ConfigurationGet(
            ProfileType            => $ProfileType,
            IncludeEncryptedSecret => 1,
        );
    return if $Self->{LastError};
    if ( $Param{ConfigurationID} && !$Existing->{id} ) {
        $Self->{LastError} = 'Translate:LDAPConfigurationLoadFailed';
        return;
    }

    my $Name              = $Self->_Trim( $Param{Name} ) || 'LDAP / Active Directory';
    my $DirectoryType     = $Self->_Trim( $Param{DirectoryType} ) || 'active_directory';
    my $Host              = $Self->_Trim( $Param{Host} );
    my $Port              = $Param{Port} || 0;
    my $Security          = $Self->_Trim( $Param{ConnectionSecurity} ) || 'ldaps';
    my $VerifyCertificate = $Param{VerifyCertificate} ? 1 : 0;
    my $CAFile            = $Self->_Trim( $Param{CAFile} );
    my $BindDN            = $Self->_Trim( $Param{BindDN} );
    my $BindPassword      = defined $Param{BindPassword} ? $Param{BindPassword} : '';
    my $BaseDN            = $Self->_Trim( $Param{BaseDN} );
    my $UserFilter        = $Self->_Trim( $Param{UserFilter} ) || '(objectClass=person)';
    my $LoginAttribute    = $Self->_Trim( $Param{LoginAttribute} );
    my $FirstnameAttribute = $Self->_Trim( $Param{FirstnameAttribute} );
    my $LastnameAttribute = $Self->_Trim( $Param{LastnameAttribute} );
    my $EmailAttribute    = $Self->_Trim( $Param{EmailAttribute} );
    my $CustomerNumberAttribute = $Self->_Trim( $Param{CustomerNumberAttribute} );
    my $CustomerNameAttribute = $Self->_Trim( $Param{CustomerNameAttribute} );
    my $DefaultGroupID    = $Param{DefaultGroupID} || 0;
    my $UpdateOnLogin     = $Param{UpdateOnLogin} ? 1 : 0;
    my $UserID            = $Param{ChangedByUserID} || 1;
    my $Mappings          = ref $Param{Mappings} eq 'ARRAY' ? $Param{Mappings} : [];

    if ( $DirectoryType !~ m{\A(?:ldap|active_directory)\z} ) {
        $Self->{LastError} = 'Translate:LDAPDirectoryTypeInvalid';
        return;
    }
    if ( !$Host || length($Host) > 255 || $Host =~ m{[\s/:]} ) {
        $Self->{LastError} = 'Translate:LDAPHostInvalid';
        return;
    }
    if ( $Port !~ m{\A\d+\z} || $Port < 1 || $Port > 65535 ) {
        $Self->{LastError} = 'Translate:LDAPPortInvalid';
        return;
    }
    if ( $Security !~ m{\A(?:ldaps|starttls)\z} ) {
        $Self->{LastError} = 'Translate:LDAPSecurityInvalid';
        return;
    }
    if ( !$BaseDN || length($BaseDN) > 1000 ) {
        $Self->{LastError} = 'Translate:LDAPBaseDNRequired';
        return;
    }
    if ( !$Self->_FilterLooksValid($UserFilter) ) {
        $Self->{LastError} = 'Translate:LDAPUserFilterInvalid';
        return;
    }

    for my $RequiredMapping (
        [ $LoginAttribute,     'Translate:LDAPLoginAttributeRequired' ],
        [ $FirstnameAttribute, 'Translate:LDAPFirstnameAttributeRequired' ],
        [ $LastnameAttribute,  'Translate:LDAPLastnameAttributeRequired' ],
        [ $EmailAttribute,     'Translate:LDAPEmailAttributeRequired' ],
        )
    {
        if ( !$Self->_AttributeValid( $RequiredMapping->[0] ) ) {
            $Self->{LastError} = $RequiredMapping->[1];
            return;
        }
    }

    if ( $ProfileType eq 'customer' ) {
        for my $RequiredMapping (
            [ $CustomerNumberAttribute, 'Translate:LDAPCustomerNumberAttributeRequired' ],
            [ $CustomerNameAttribute,   'Translate:LDAPCustomerNameAttributeRequired' ],
            )
        {
            if ( !$Self->_AttributeValid( $RequiredMapping->[0] ) ) {
                $Self->{LastError} = $RequiredMapping->[1];
                return;
            }
        }
    }

    if ( ( $BindDN && !$BindPassword && !( $Existing->{bind_password_encrypted} || '' ) ) || ( !$BindDN && $BindPassword ) ) {
        $Self->{LastError} = 'Translate:LDAPBindCredentialsIncomplete';
        return;
    }
    if ( length($Name) > 100 || length($CAFile) > 500 || length($BindDN) > 1000 ) {
        $Self->{LastError} = 'Translate:LDAPConfigurationValueTooLong';
        return;
    }
    $DefaultGroupID = 0 if $ProfileType ne 'agent';
    if ( $DefaultGroupID && $DefaultGroupID !~ m{\A\d+\z} ) {
        $Self->{LastError} = 'Translate:LDAPDefaultGroupInvalid';
        return;
    }
    if ($DefaultGroupID) {
        my $Group = $Self->{DB}->SelectRow(
            'SELECT id FROM user_group
             WHERE id = ? AND active = 1 AND group_type = "agent" LIMIT 1',
            $DefaultGroupID,
        );
        if ( !$Group ) {
            $Self->{LastError} = 'Translate:LDAPDefaultGroupInvalid';
            return;
        }
    }

    my %ValidField;
    my $Fields = $Self->{DB}->SelectAll(
        'SELECT id, object_type, is_required FROM user_dynamic_field
         WHERE object_type IN ("agent", "customer_user") AND active = 1'
    );
    if ( !$Fields ) {
        $Self->{LastError} = $Self->{DB}->Error() || 'Translate:LDAPFieldMappingLoadFailed';
        return;
    }
    for my $Field ( @{$Fields} ) {
        $ValidField{ ( $Field->{object_type} || '' ) . ':' . ( $Field->{id} || 0 ) } = $Field;
    }

    my %MappedField;
    my $ExpectedObjectType = $ProfileType eq 'agent' ? 'agent' : 'customer_user';
    for my $Mapping ( @{$Mappings} ) {
        next if ref $Mapping ne 'HASH';
        my $ObjectType = $Mapping->{ObjectType} || '';
        my $FieldID    = $Mapping->{FieldID} || 0;
        my $Attribute  = $Self->_Trim( $Mapping->{LDAPAttribute} );
        next if !$Attribute;
        if ( $ObjectType ne $ExpectedObjectType
            || !$ValidField{"$ObjectType:$FieldID"}
            || !$Self->_AttributeValid($Attribute) ) {
            $Self->{LastError} = 'Translate:LDAPFieldMappingInvalid';
            return;
        }
        $MappedField{"$ObjectType:$FieldID"} = 1;
    }
    for my $Key ( keys %ValidField ) {
        my $Field = $ValidField{$Key};
        next if ( $Field->{object_type} || '' ) ne $ExpectedObjectType || !$Field->{is_required};
        if ( !$MappedField{$Key} ) {
            $Self->{LastError} = $ProfileType eq 'agent'
                ? 'Translate:LDAPRequiredAgentFieldMappingMissing'
                : 'Translate:LDAPRequiredCustomerFieldMappingMissing';
            return;
        }
    }

    my $EncryptedPassword = $Existing->{bind_password_encrypted} || '';
    if ($BindPassword) {
        $EncryptedPassword = $Self->{Security}->Encrypt( Value => $BindPassword );
        if ( !defined $EncryptedPassword ) {
            $Self->{LastError} = $Self->{Security}->Error() || 'Translate:LDAPBindPasswordEncryptionFailed';
            return;
        }
    }
    $EncryptedPassword = '' if !$BindDN;

    my $Started = $Self->{DB}->BeginWork();
    if ( !$Started ) {
        $Self->{LastError} = $Self->{DB}->Error() || 'Translate:LDAPConfigurationSaveFailed';
        return;
    }

    my $ConfigurationID = $Existing->{id} || 0;
    my $OK = eval {
        if ($ConfigurationID) {
            $Self->{DB}->Do(
                'UPDATE ldap_configuration
                 SET name = ?, directory_type = ?, host = ?, port = ?, connection_security = ?,
                     verify_certificate = ?, ca_file = ?, bind_dn = ?, bind_password_encrypted = ?,
                     base_dn = ?, user_filter = ?, login_attribute = ?, firstname_attribute = ?,
                     lastname_attribute = ?, email_attribute = ?, customer_number_attribute = ?,
                     customer_name_attribute = ?, default_group_id = ?,
                     update_on_login = ?, active = 0, last_test_at = NULL,
                     last_test_status = "", last_test_message = NULL,
                     changed_by_user_id = ?
                 WHERE id = ?',
                $Name, $DirectoryType, $Host, $Port, $Security,
                $VerifyCertificate, $CAFile, $BindDN, $EncryptedPassword,
                $BaseDN, $UserFilter, $LoginAttribute, $FirstnameAttribute,
                $LastnameAttribute, $EmailAttribute, $CustomerNumberAttribute,
                $CustomerNameAttribute, $DefaultGroupID || undef,
                $UpdateOnLogin, $UserID, $ConfigurationID,
            ) || die( $Self->{DB}->Error() || 'configuration update failed' );
        }
        else {
            $Self->{DB}->Do(
                'INSERT INTO ldap_configuration (
                    profile_type, name, directory_type, host, port, connection_security, verify_certificate,
                    ca_file, bind_dn, bind_password_encrypted, base_dn, user_filter,
                    login_attribute, firstname_attribute, lastname_attribute, email_attribute,
                    customer_number_attribute, customer_name_attribute, default_group_id,
                    update_on_login, active, created_by_user_id, changed_by_user_id
                 ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, 0, ?, ?)',
                $ProfileType, $Name, $DirectoryType, $Host, $Port, $Security, $VerifyCertificate,
                $CAFile, $BindDN, $EncryptedPassword, $BaseDN, $UserFilter,
                $LoginAttribute, $FirstnameAttribute, $LastnameAttribute, $EmailAttribute,
                $CustomerNumberAttribute, $CustomerNameAttribute,
                $DefaultGroupID || undef, $UpdateOnLogin, $UserID, $UserID,
            ) || die( $Self->{DB}->Error() || 'configuration create failed' );
            $ConfigurationID = $Self->{DB}->LastInsertID('ldap_configuration') || 0;
            die 'configuration id missing' if !$ConfigurationID;
        }

        $Self->{DB}->Do(
            'DELETE FROM ldap_field_mapping WHERE ldap_configuration_id = ?',
            $ConfigurationID,
        ) || die( $Self->{DB}->Error() || 'mapping delete failed' );

        for my $Mapping ( @{$Mappings} ) {
            next if ref $Mapping ne 'HASH';
            my $ObjectType = $Mapping->{ObjectType} || '';
            my $FieldID    = $Mapping->{FieldID} || 0;
            my $Attribute  = $Self->_Trim( $Mapping->{LDAPAttribute} );
            next if !$Attribute;
            $Self->{DB}->Do(
                'INSERT INTO ldap_field_mapping (
                    ldap_configuration_id, object_type, field_id, ldap_attribute,
                    is_required, update_on_login, clear_empty, created_by_user_id, changed_by_user_id
                 ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)',
                $ConfigurationID, $ObjectType, $FieldID, $Attribute,
                ( $Mapping->{IsRequired} || $ValidField{"$ObjectType:$FieldID"}->{is_required} ) ? 1 : 0,
                $Mapping->{UpdateOnLogin} ? 1 : 0,
                $Mapping->{ClearEmpty} ? 1 : 0,
                $UserID, $UserID,
            ) || die( $Self->{DB}->Error() || 'mapping create failed' );
        }

        $Self->{DB}->Commit() || die( $Self->{DB}->Error() || 'commit failed' );
        1;
    };

    if ( !$OK ) {
        my $Error = $@ || 'configuration save failed';
        eval { $Self->{DB}->Rollback() };
        $Error =~ s{\s+at\s+.*\z}{}s;
        $Self->{LastError} = 'Translate:LDAPConfigurationSaveFailed';
        return;
    }

    return $ConfigurationID;
}

sub ConfigurationTest {
    my ( $Self, %Param ) = @_;
    $Self->{LastError} = '';

    my $Configuration = $Self->_ConfigurationRuntimeGet(
        ConfigurationID => $Param{ConfigurationID},
        ProfileType     => $Param{ProfileType} || 'agent',
    );
    return if !$Configuration;

    my $Login = $Self->_Trim( $Param{TestLogin} );
    if ( !$Login ) {
        $Self->{LastError} = 'Translate:LDAPTestLoginRequired';
        return;
    }

    my $Result = $Self->_DirectoryAuthenticate(
        Configuration => $Configuration,
        Login         => $Login,
        Password      => $Param{TestPassword} || '',
        SearchOnly    => $Param{TestPassword} ? 0 : 1,
        ObjectType    => ( $Configuration->{profile_type} || 'agent' ) eq 'customer'
            ? 'customer_user' : 'agent',
    );

    my $Success = $Result && ( $Result->{Status} || '' ) eq 'success'
        && $Self->_DirectoryResultValidate(
            Configuration => $Configuration,
            Attributes    => $Result->{Attributes},
            ObjectType    => ( $Configuration->{profile_type} || 'agent' ) eq 'customer'
                ? 'customer_user' : 'agent',
        );
    my $Message = $Success
        ? 'Translate:LDAPTestSuccessful'
        : ( $Self->{LastError} || ( $Result && $Result->{Error} ) || 'Translate:LDAPTestFailed' );

    my $TestStored = $Self->{DB}->Do(
        'UPDATE ldap_configuration
         SET last_test_at = NOW(), last_test_status = ?, last_test_message = ?, changed_by_user_id = ?
         WHERE id = ?',
        $Success ? 'success' : 'failed',
        $Message,
        $Param{ChangedByUserID} || 1,
        $Configuration->{id},
    );
    if ( !$TestStored ) {
        $Self->{LastError} = $Self->{DB}->Error() || 'Translate:LDAPTestFailed';
        return;
    }

    if ( !$Success ) {
        $Self->{LastError} = $Message;
        return;
    }

    return { Success => 1, Message => $Message };
}

sub ConfigurationActivate {
    my ( $Self, %Param ) = @_;
    $Self->{LastError} = '';

    my $ProfileType = $Self->_ProfileType( $Param{ProfileType} || 'agent' );
    return if !$ProfileType;
    my $Configuration = $Self->ConfigurationGet(
        ConfigurationID => $Param{ConfigurationID},
        ProfileType     => $ProfileType,
    );
    if ( !$Configuration->{id} || ( $Configuration->{last_test_status} || '' ) ne 'success' ) {
        $Self->{LastError} = 'Translate:LDAPSuccessfulTestRequired';
        return;
    }
    if ( !$Self->ModuleAvailable() ) {
        $Self->{LastError} = 'Translate:LDAPModuleMissing';
        return;
    }

    my $Started = $Self->{DB}->BeginWork();
    if ( !$Started ) {
        $Self->{LastError} = $Self->{DB}->Error() || 'Translate:LDAPActivationFailed';
        return;
    }
    my $OK = eval {
        $Self->{DB}->Do(
            'UPDATE ldap_configuration SET active = 0 WHERE profile_type = ?',
            $ProfileType,
        )
            || die( $Self->{DB}->Error() || 'deactivation failed' );
        $Self->{DB}->Do(
            'UPDATE ldap_configuration SET active = 1, changed_by_user_id = ? WHERE id = ?',
            $Param{ChangedByUserID} || 1,
            $Configuration->{id},
        ) || die( $Self->{DB}->Error() || 'activation failed' );
        $Self->{DB}->Commit() || die( $Self->{DB}->Error() || 'commit failed' );
        1;
    };
    if ( !$OK ) {
        eval { $Self->{DB}->Rollback() };
        $Self->{LastError} = 'Translate:LDAPActivationFailed';
        return;
    }
    return 1;
}

sub ConfigurationDeactivate {
    my ( $Self, %Param ) = @_;
    $Self->{LastError} = '';
    my $ProfileType = $Self->_ProfileType( $Param{ProfileType} || 'agent' );
    return if !$ProfileType;
    my $OK = $Self->{DB}->Do(
        'UPDATE ldap_configuration SET active = 0, changed_by_user_id = ? WHERE id = ? AND profile_type = ?',
        $Param{ChangedByUserID} || 1,
        $Param{ConfigurationID} || 0,
        $ProfileType,
    );
    if ( !$OK ) {
        $Self->{LastError} = $Self->{DB}->Error() || 'Translate:LDAPDeactivationFailed';
        return;
    }
    return 1;
}

sub FieldDefinitionList {
    my ( $Self, %Param ) = @_;
    $Self->{LastError} = '';

    my $Language = $Param{Language} || $Self->{Config}->{Language}->{Default} || 'en';
    my $Rows = $Self->{DB}->SelectAll(
        'SELECT f.id, f.object_type, f.name,
                COALESCE(current_translation.label, f.label, f.name) AS label,
                f.field_type, f.is_required
         FROM user_dynamic_field f
         LEFT JOIN user_dynamic_field_translation current_translation
           ON current_translation.field_id = f.id AND current_translation.language = ?
         WHERE f.object_type IN ("agent", "customer_user") AND f.active = 1
         ORDER BY f.object_type ASC, f.sort_order ASC, f.id ASC',
        $Language,
    );
    if ( !$Rows ) {
        $Self->{LastError} = $Self->{DB}->Error() || 'Translate:LDAPFieldMappingLoadFailed';
        return [];
    }
    return $Rows;
}

sub FieldMappingList {
    my ( $Self, %Param ) = @_;
    $Self->{LastError} = '';
    my $Rows = $Self->{DB}->SelectAll(
        'SELECT object_type, field_id, ldap_attribute, is_required, update_on_login, clear_empty
         FROM ldap_field_mapping WHERE ldap_configuration_id = ?',
        $Param{ConfigurationID} || 0,
    );
    if ( !$Rows ) {
        $Self->{LastError} = $Self->{DB}->Error() || 'Translate:LDAPFieldMappingLoadFailed';
        return [];
    }
    return $Rows;
}

sub AuthenticateAgent {
    my ( $Self, %Param ) = @_;
    $Self->{LastError} = '';

    my $Configuration = $Self->_ConfigurationRuntimeGet( Active => 1, ProfileType => 'agent' );
    return { Handled => 0 } if !$Configuration && !$Self->{LastError};
    return { Handled => 1 } if !$Configuration;

    my $Result = $Self->_DirectoryAuthenticate(
        Configuration => $Configuration,
        Login         => $Param{Login} || '',
        Password      => $Param{Password} || '',
        ObjectType    => 'agent',
    );
    if ( !$Result ) {
        $Self->{LastError} ||= 'Translate:LDAPAuthenticationFailed';
        return { Handled => 1 };
    }
    if ( ( $Result->{Status} || '' ) eq 'not_found' ) {
        return { Handled => 0 };
    }
    if ( ( $Result->{Status} || '' ) ne 'success' ) {
        $Self->{LastError} = $Result->{Error} || 'Translate:LDAPAuthenticationFailed';
        return { Handled => 1 };
    }

    return { Handled => 1 } if !$Self->_DirectoryResultValidate(
        Configuration => $Configuration,
        Attributes    => $Result->{Attributes},
        ObjectType    => 'agent',
    );

    my $User = $Self->_AgentProvision(
        Configuration => $Configuration,
        Attributes    => $Result->{Attributes},
    );
    return { Handled => 1 } if !$User;

    return { Handled => 1, User => $User };
}

sub AuthenticateCustomer {
    my ( $Self, %Param ) = @_;
    $Self->{LastError} = '';

    my $Configuration = $Self->_ConfigurationRuntimeGet( Active => 1, ProfileType => 'customer' );
    return { Handled => 0 } if !$Configuration && !$Self->{LastError};
    return { Handled => 1 } if !$Configuration;

    my $Result = $Self->_DirectoryAuthenticate(
        Configuration => $Configuration,
        Login         => $Param{Login} || '',
        Password      => $Param{Password} || '',
        ObjectType    => 'customer_user',
    );
    if ( !$Result ) {
        $Self->{LastError} ||= 'Translate:LDAPAuthenticationFailed';
        return { Handled => 1 };
    }
    if ( ( $Result->{Status} || '' ) eq 'not_found' ) {
        return { Handled => 0 };
    }
    if ( ( $Result->{Status} || '' ) ne 'success' ) {
        $Self->{LastError} = $Result->{Error} || 'Translate:LDAPAuthenticationFailed';
        return { Handled => 1 };
    }

    return { Handled => 1 } if !$Self->_DirectoryResultValidate(
        Configuration => $Configuration,
        Attributes    => $Result->{Attributes},
        ObjectType    => 'customer_user',
    );

    my $User = $Self->_CustomerProvision(
        Configuration => $Configuration,
        Attributes    => $Result->{Attributes},
    );
    return { Handled => 1 } if !$User;

    return { Handled => 1, User => $User };
}

sub _AgentProvision {
    my ( $Self, %Param ) = @_;
    my $Configuration = $Param{Configuration} || {};
    my $Attributes    = $Param{Attributes} || {};

    my $Login = $Self->_AttributeValue( $Attributes, $Configuration->{login_attribute} );
    my $Firstname = $Self->_AttributeValue( $Attributes, $Configuration->{firstname_attribute} );
    my $Lastname = $Self->_AttributeValue( $Attributes, $Configuration->{lastname_attribute} );
    my $Email = $Self->_AttributeValue( $Attributes, $Configuration->{email_attribute} );

    my $Started = $Self->{DB}->BeginWork();
    if ( !$Started ) {
        $Self->{LastError} = $Self->{DB}->Error() || 'Translate:LDAPAgentProvisionFailed';
        return;
    }

    my $User;
    my $OK = eval {
        $User = $Self->{DB}->SelectRow(
            'SELECT id, login, account_type, authentication_type, email, firstname, lastname,
                    is_active, is_system_user
             FROM user_account
             WHERE login = ? AND account_type = "agent" LIMIT 1 FOR UPDATE',
            $Login,
        );

        if ( $User && !$User->{is_active} ) {
            die 'Translate:LDAPAgentInactive';
        }

        my $EmailOwner = $Self->{DB}->SelectRow(
            'SELECT id, login FROM user_account
             WHERE LOWER(email) = LOWER(?) AND account_type = "agent"
               AND (? = 0 OR id <> ?) LIMIT 1 FOR UPDATE',
            $Email,
            $User ? $User->{id} : 0,
            $User ? $User->{id} : 0,
        );
        if ($EmailOwner) {
            die 'Translate:LDAPAgentEmailConflict';
        }

        my $NewAgent = 0;
        if ($User) {
            if ( $Configuration->{update_on_login} ) {
                $Self->{DB}->Do(
                    'UPDATE user_account
                     SET email = ?, firstname = ?, lastname = ?, authentication_type = "ldap",
                         password_hash = "!LDAP!", failed_login_count = 0, locked_until = NULL,
                         last_login_at = NOW(), updated_at = NOW()
                     WHERE id = ?',
                    $Email, $Firstname, $Lastname, $User->{id},
                ) || die( $Self->{DB}->Error() || 'agent update failed' );
            }
            else {
                $Self->{DB}->Do(
                    'UPDATE user_account
                     SET authentication_type = "ldap", password_hash = "!LDAP!",
                         failed_login_count = 0, locked_until = NULL, last_login_at = NOW(), updated_at = NOW()
                     WHERE id = ?',
                    $User->{id},
                ) || die( $Self->{DB}->Error() || 'agent authentication update failed' );
            }
        }
        else {
            $Self->{DB}->Do(
                'INSERT INTO user_account (
                    login, account_type, authentication_type, email, password_hash,
                    firstname, lastname, is_active, is_system_user, last_login_at
                 ) VALUES (?, "agent", "ldap", ?, "!LDAP!", ?, ?, 1, 0, NOW())',
                $Login, $Email, $Firstname, $Lastname,
            ) || die( $Self->{DB}->Error() || 'agent create failed' );
            my $ID = $Self->{DB}->LastInsertID('user_account') || 0;
            die 'agent id missing' if !$ID;
            $User = {
                id                  => $ID,
                login               => $Login,
                account_type        => 'agent',
                authentication_type => 'ldap',
                email               => $Email,
                firstname           => $Firstname,
                lastname            => $Lastname,
                is_active           => 1,
                is_system_user      => 0,
            };
            $NewAgent = 1;
        }

        my $Mappings = $Self->_RuntimeMappingList(
            ConfigurationID => $Configuration->{id},
            ObjectType      => 'agent',
        );
        die $Self->{LastError} if $Self->{LastError};

        for my $Mapping ( @{$Mappings} ) {
            next if !$NewAgent && !$Mapping->{update_on_login};
            my $Value = $Self->_AttributeValue( $Attributes, $Mapping->{ldap_attribute} );
            if ( !$Value && $Mapping->{is_required} ) {
                die 'Translate:LDAPRequiredDynamicFieldMissing';
            }
            next if !$Value && !$Mapping->{clear_empty};
            $Self->{DB}->Do(
                'INSERT INTO user_dynamic_field_value (
                    object_type, object_id, field_id, value_text, created_by_user_id, changed_by_user_id
                 ) VALUES ("agent", ?, ?, ?, 1, 1)
                 ON DUPLICATE KEY UPDATE value_text = VALUES(value_text),
                    changed_by_user_id = 1, changed_at = CURRENT_TIMESTAMP',
                $User->{id}, $Mapping->{field_id}, $Value,
            ) || die( $Self->{DB}->Error() || 'dynamic value update failed' );
        }

        if ( $NewAgent && $Configuration->{default_group_id} ) {
            $Self->{DB}->Do(
                'INSERT INTO user_group_member (
                    user_group_id, user_account_id, role_name, active,
                    created_by_user_id, changed_by_user_id
                 ) VALUES (?, ?, "member", 1, 1, 1)
                 ON DUPLICATE KEY UPDATE active = 1, changed_by_user_id = 1,
                    changed_at = CURRENT_TIMESTAMP',
                $Configuration->{default_group_id}, $User->{id},
            ) || die( $Self->{DB}->Error() || 'default group assignment failed' );
        }

        $Self->{DB}->Commit() || die( $Self->{DB}->Error() || 'commit failed' );
        1;
    };

    if ( !$OK ) {
        my $Error = $@ || 'Translate:LDAPAgentProvisionFailed';
        eval { $Self->{DB}->Rollback() };
        $Error =~ s{\s+at\s+.*\z}{}s;
        $Self->{LastError} = $Error =~ m{\ATranslate:} ? $Error : 'Translate:LDAPAgentProvisionFailed';
        return;
    }

    $User->{email} = $Email if $Configuration->{update_on_login};
    $User->{firstname} = $Firstname if $Configuration->{update_on_login};
    $User->{lastname} = $Lastname if $Configuration->{update_on_login};
    $User->{authentication_type} = 'ldap';
    return $User;
}

sub _CustomerProvision {
    my ( $Self, %Param ) = @_;
    my $Configuration = $Param{Configuration} || {};
    my $Attributes    = $Param{Attributes} || {};

    my $Login = $Self->_AttributeValue( $Attributes, $Configuration->{login_attribute} );
    my $Firstname = $Self->_AttributeValue( $Attributes, $Configuration->{firstname_attribute} );
    my $Lastname = $Self->_AttributeValue( $Attributes, $Configuration->{lastname_attribute} );
    my $Email = $Self->_AttributeValue( $Attributes, $Configuration->{email_attribute} );
    my $CustomerNumber = $Self->_AttributeValue( $Attributes, $Configuration->{customer_number_attribute} );
    my $CustomerName = $Self->_AttributeValue( $Attributes, $Configuration->{customer_name_attribute} );

    my $Started = $Self->{DB}->BeginWork();
    if ( !$Started ) {
        $Self->{LastError} = $Self->{DB}->Error() || 'Translate:LDAPCustomerProvisionFailed';
        return;
    }

    my ( $User, $Customer, $CustomerUser );
    my $OK = eval {
        $Customer = $Self->{DB}->SelectRow(
            'SELECT id, customer_number, name, active
             FROM customer WHERE customer_number = ? LIMIT 1 FOR UPDATE',
            $CustomerNumber,
        );
        if ( $Customer && !$Customer->{active} ) {
            die 'Translate:LDAPCustomerInactive';
        }
        if ($Customer) {
            if ( $Configuration->{update_on_login} ) {
                $Self->{DB}->Do(
                    'UPDATE customer
                     SET name = ?, changed_by_user_id = 1, changed_at = CURRENT_TIMESTAMP
                     WHERE id = ?',
                    $CustomerName, $Customer->{id},
                ) || die( $Self->{DB}->Error() || 'customer update failed' );
                $Customer->{name} = $CustomerName;
            }
        }
        else {
            $Self->{DB}->Do(
                'INSERT INTO customer (
                    customer_number, name, active, created_by_user_id, changed_by_user_id
                 ) VALUES (?, ?, 1, 1, 1)',
                $CustomerNumber, $CustomerName,
            ) || die( $Self->{DB}->Error() || 'customer create failed' );
            my $CustomerID = $Self->{DB}->LastInsertID('customer') || 0;
            die 'customer id missing' if !$CustomerID;
            $Customer = {
                id              => $CustomerID,
                customer_number => $CustomerNumber,
                name            => $CustomerName,
                active          => 1,
            };
        }

        $User = $Self->{DB}->SelectRow(
            'SELECT id, login, account_type, authentication_type, email, firstname, lastname,
                    is_active, is_system_user
             FROM user_account
             WHERE login = ? AND account_type = "customer" LIMIT 1 FOR UPDATE',
            $Login,
        );
        if ( $User && !$User->{is_active} ) {
            die 'Translate:LDAPCustomerUserInactive';
        }

        my $EmailOwner = $Self->{DB}->SelectRow(
            'SELECT id, login FROM user_account
             WHERE LOWER(email) = LOWER(?) AND account_type = "customer"
               AND (? = 0 OR id <> ?) LIMIT 1 FOR UPDATE',
            $Email,
            $User ? $User->{id} : 0,
            $User ? $User->{id} : 0,
        );
        if ($EmailOwner) {
            die 'Translate:LDAPCustomerUserEmailConflict';
        }

        my $NewUser = 0;
        if ($User) {
            if ( $Configuration->{update_on_login} ) {
                $Self->{DB}->Do(
                    'UPDATE user_account
                     SET email = ?, firstname = ?, lastname = ?, authentication_type = "ldap",
                         password_hash = "!LDAP!", failed_login_count = 0, locked_until = NULL,
                         last_login_at = NOW(), updated_at = NOW()
                     WHERE id = ?',
                    $Email, $Firstname, $Lastname, $User->{id},
                ) || die( $Self->{DB}->Error() || 'customer user update failed' );
                $User->{email} = $Email;
                $User->{firstname} = $Firstname;
                $User->{lastname} = $Lastname;
            }
            else {
                $Self->{DB}->Do(
                    'UPDATE user_account
                     SET authentication_type = "ldap", password_hash = "!LDAP!",
                         failed_login_count = 0, locked_until = NULL,
                         last_login_at = NOW(), updated_at = NOW()
                     WHERE id = ?',
                    $User->{id},
                ) || die( $Self->{DB}->Error() || 'customer authentication update failed' );
            }
        }
        else {
            $Self->{DB}->Do(
                'INSERT INTO user_account (
                    login, account_type, authentication_type, email, password_hash,
                    firstname, lastname, is_active, is_system_user, last_login_at
                 ) VALUES (?, "customer", "ldap", ?, "!LDAP!", ?, ?, 1, 0, NOW())',
                $Login, $Email, $Firstname, $Lastname,
            ) || die( $Self->{DB}->Error() || 'customer user create failed' );
            my $UserID = $Self->{DB}->LastInsertID('user_account') || 0;
            die 'customer user id missing' if !$UserID;
            $User = {
                id                  => $UserID,
                login               => $Login,
                account_type        => 'customer',
                authentication_type => 'ldap',
                email               => $Email,
                firstname           => $Firstname,
                lastname            => $Lastname,
                is_active           => 1,
                is_system_user      => 0,
            };
            $NewUser = 1;
        }

        my $ExistingRelation = $Self->{DB}->SelectRow(
            'SELECT id, active FROM customer_user
             WHERE customer_id = ? AND user_account_id = ? LIMIT 1 FOR UPDATE',
            $Customer->{id}, $User->{id},
        );
        my $NewRelation = !$ExistingRelation || !$ExistingRelation->{active} ? 1 : 0;

        $Self->{DB}->Do(
            'UPDATE customer_user
             SET active = 0, changed_by_user_id = 1, changed_at = CURRENT_TIMESTAMP
             WHERE user_account_id = ? AND customer_id <> ? AND active = 1',
            $User->{id}, $Customer->{id},
        ) || die( $Self->{DB}->Error() || 'old customer assignment update failed' );

        $Self->{DB}->Do(
            'INSERT INTO customer_user (
                customer_id, user_account_id, active, created_by_user_id, changed_by_user_id
             ) VALUES (?, ?, 1, 1, 1)
             ON DUPLICATE KEY UPDATE active = 1, changed_by_user_id = 1,
                changed_at = CURRENT_TIMESTAMP',
            $Customer->{id}, $User->{id},
        ) || die( $Self->{DB}->Error() || 'customer assignment failed' );

        $CustomerUser = $Self->{DB}->SelectRow(
            'SELECT id, customer_id, user_account_id, active
             FROM customer_user
             WHERE customer_id = ? AND user_account_id = ? LIMIT 1',
            $Customer->{id}, $User->{id},
        );
        die 'customer assignment id missing' if !$CustomerUser || !$CustomerUser->{id};

        my $Mappings = $Self->_RuntimeMappingList(
            ConfigurationID => $Configuration->{id},
            ObjectType      => 'customer_user',
        );
        die $Self->{LastError} if $Self->{LastError};

        for my $Mapping ( @{$Mappings} ) {
            next if !$NewUser && !$NewRelation && !$Mapping->{update_on_login};
            my $Value = $Self->_AttributeValue( $Attributes, $Mapping->{ldap_attribute} );
            if ( !$Value && $Mapping->{is_required} ) {
                die 'Translate:LDAPRequiredDynamicFieldMissing';
            }
            next if !$Value && !$Mapping->{clear_empty};
            $Self->{DB}->Do(
                'INSERT INTO user_dynamic_field_value (
                    object_type, object_id, field_id, value_text, created_by_user_id, changed_by_user_id
                 ) VALUES ("customer_user", ?, ?, ?, 1, 1)
                 ON DUPLICATE KEY UPDATE value_text = VALUES(value_text),
                    changed_by_user_id = 1, changed_at = CURRENT_TIMESTAMP',
                $CustomerUser->{id}, $Mapping->{field_id}, $Value,
            ) || die( $Self->{DB}->Error() || 'dynamic value update failed' );
        }

        $Self->{DB}->Commit() || die( $Self->{DB}->Error() || 'commit failed' );
        1;
    };

    if ( !$OK ) {
        my $Error = $@ || 'Translate:LDAPCustomerProvisionFailed';
        eval { $Self->{DB}->Rollback() };
        $Error =~ s{\s+at\s+.*\z}{}s;
        $Self->{LastError} = $Error =~ m{\ATranslate:} ? $Error : 'Translate:LDAPCustomerProvisionFailed';
        return;
    }

    $User->{authentication_type} = 'ldap';
    $User->{customer_id} = $Customer->{id};
    $User->{customer_user_id} = $CustomerUser->{id};
    return $User;
}

sub _DirectoryResultValidate {
    my ( $Self, %Param ) = @_;
    my $Configuration = $Param{Configuration} || {};
    my $Attributes    = $Param{Attributes} || {};

    my @Required = (
        [ $Configuration->{login_attribute}, 'Translate:LDAPLoginValueMissing', 100 ],
        [ $Configuration->{firstname_attribute}, 'Translate:LDAPFirstnameValueMissing', 100 ],
        [ $Configuration->{lastname_attribute}, 'Translate:LDAPLastnameValueMissing', 100 ],
        [ $Configuration->{email_attribute}, 'Translate:LDAPEmailValueMissing', 255 ],
    );
    if ( ( $Param{ObjectType} || 'agent' ) eq 'customer_user' ) {
        push @Required,
            [ $Configuration->{customer_number_attribute}, 'Translate:LDAPCustomerNumberValueMissing', 100 ],
            [ $Configuration->{customer_name_attribute}, 'Translate:LDAPCustomerNameValueMissing', 255 ];
    }
    for my $Required (@Required) {
        my $Value = $Self->_AttributeValue( $Attributes, $Required->[0] );
        if ( !$Value || length($Value) > $Required->[2] ) {
            $Self->{LastError} = $Required->[1];
            return;
        }
    }

    my $Email = $Self->_AttributeValue( $Attributes, $Configuration->{email_attribute} );
    if ( $Email !~ m{\A[^\s\@]+\@[^\s\@]+\.[^\s\@]+\z} || length($Email) > 255 ) {
        $Self->{LastError} = 'Translate:LDAPEmailValueInvalid';
        return;
    }

    my $Mappings = $Self->_RuntimeMappingList(
        ConfigurationID => $Configuration->{id},
        ObjectType      => $Param{ObjectType} || 'agent',
    );
    return if $Self->{LastError};
    for my $Mapping ( @{$Mappings} ) {
        next if !$Mapping->{is_required};
        if ( !$Self->_AttributeValue( $Attributes, $Mapping->{ldap_attribute} ) ) {
            $Self->{LastError} = 'Translate:LDAPRequiredDynamicFieldMissing';
            return;
        }
    }
    return 1;
}

sub _DirectoryAuthenticate {
    my ( $Self, %Param ) = @_;

    if ( ref $Self->{DirectoryAuthenticator} eq 'CODE' ) {
        return $Self->{DirectoryAuthenticator}->(%Param);
    }

    if ( !$Self->ModuleAvailable() ) {
        return { Status => 'error', Error => 'Translate:LDAPModuleMissing' };
    }

    my $Configuration = $Param{Configuration} || {};
    my $ObjectType = $Param{ObjectType} || 'agent';
    my $Login = $Self->_Trim( $Param{Login} );
    my $Password = $Param{Password} || '';
    return { Status => 'error', Error => 'Translate:LDAPLoginValueMissing' } if !$Login;
    return { Status => 'invalid_credentials', Error => 'Translate:LDAPAuthenticationFailed' }
        if !$Param{SearchOnly} && !$Password;

    my %Connect = (
        port    => $Configuration->{port},
        timeout => 10,
    );
    if ( $Configuration->{connection_security} eq 'ldaps' ) {
        $Connect{scheme} = 'ldaps';
        $Connect{verify} = $Configuration->{verify_certificate} ? 'require' : 'none';
        $Connect{verifycn_scheme} = 'ldap' if $Configuration->{verify_certificate};
        $Connect{cafile} = $Configuration->{ca_file} if $Configuration->{ca_file};
    }

    my $LDAP = eval { Net::LDAP->new( $Configuration->{host}, %Connect ) };
    if ( !$LDAP ) {
        return { Status => 'error', Error => 'Translate:LDAPConnectionFailed' };
    }

    if ( $Configuration->{connection_security} eq 'starttls' ) {
        my %TLS = ( verify => $Configuration->{verify_certificate} ? 'require' : 'none' );
        $TLS{verifycn_scheme} = 'ldap' if $Configuration->{verify_certificate};
        $TLS{cafile} = $Configuration->{ca_file} if $Configuration->{ca_file};
        my $TLSResult = $LDAP->start_tls(%TLS);
        if ( $TLSResult->code ) {
            eval { $LDAP->unbind() };
            return { Status => 'error', Error => 'Translate:LDAPTLSFailed' };
        }
    }

    my $BindResult = $Configuration->{bind_dn}
        ? $LDAP->bind( $Configuration->{bind_dn}, password => $Configuration->{bind_password} || '' )
        : $LDAP->bind();
    if ( $BindResult->code ) {
        eval { $LDAP->unbind() };
        return { Status => 'error', Error => 'Translate:LDAPServiceBindFailed' };
    }

    my $Filter = '(&' . $Configuration->{user_filter} . '('
        . $Configuration->{login_attribute} . '=' . $Self->_FilterEscape($Login) . '))';
    my %Attribute;
    for my $Name (
        $Configuration->{login_attribute},
        $Configuration->{firstname_attribute},
        $Configuration->{lastname_attribute},
        $Configuration->{email_attribute},
        ( $ObjectType eq 'customer_user' ? $Configuration->{customer_number_attribute} : () ),
        ( $ObjectType eq 'customer_user' ? $Configuration->{customer_name_attribute} : () ),
        )
    {
        $Attribute{lc $Name} = $Name if $Name;
    }
    my $Mappings = $Self->_RuntimeMappingList(
        ConfigurationID => $Configuration->{id},
        ObjectType      => $ObjectType,
    );
    if ( $Self->{LastError} ) {
        eval { $LDAP->unbind() };
        return { Status => 'error', Error => $Self->{LastError} };
    }
    for my $Mapping ( @{$Mappings || []} ) {
        my $Name = $Mapping->{ldap_attribute} || '';
        $Attribute{lc $Name} = $Name if $Name;
    }

    my $Search = $LDAP->search(
        base      => $Configuration->{base_dn},
        scope     => 'sub',
        filter    => $Filter,
        attrs     => [ values %Attribute ],
        sizelimit => 2,
        timelimit => 10,
    );
    if ( $Search->code ) {
        eval { $LDAP->unbind() };
        return { Status => 'error', Error => 'Translate:LDAPSearchFailed' };
    }
    my @Entry = $Search->entries();
    if ( !@Entry ) {
        eval { $LDAP->unbind() };
        return { Status => 'not_found' };
    }
    if ( @Entry != 1 ) {
        eval { $LDAP->unbind() };
        return { Status => 'multiple', Error => 'Translate:LDAPSearchNotUnique' };
    }

    my %Attributes;
    for my $Name ( values %Attribute ) {
        my $Values = $Entry[0]->get_value( $Name, asref => 1 ) || [];
        $Attributes{lc $Name} = [ map { $Self->_DecodeLDAPValue($_) } @{$Values} ];
    }

    if ( !$Param{SearchOnly} ) {
        my $UserBind = $LDAP->bind( $Entry[0]->dn(), password => $Password );
        if ( $UserBind->code ) {
            eval { $LDAP->unbind() };
            return { Status => 'invalid_credentials', Error => 'Translate:LDAPAuthenticationFailed' };
        }
    }

    eval { $LDAP->unbind() };
    return {
        Status     => 'success',
        Attributes => \%Attributes,
    };
}

sub _ConfigurationRuntimeGet {
    my ( $Self, %Param ) = @_;
    my $Configuration = $Self->ConfigurationGet(
        %Param,
        IncludeEncryptedSecret => 1,
    );
    return if !$Configuration->{id};

    my $Encrypted = delete $Configuration->{bind_password_encrypted};
    if ($Encrypted) {
        my $Password = $Self->{Security}->Decrypt( Value => $Encrypted );
        if ( !defined $Password ) {
            $Self->{LastError} = $Self->{Security}->Error() || 'Translate:LDAPBindPasswordDecryptionFailed';
            return;
        }
        $Configuration->{bind_password} = $Password;
    }
    else {
        $Configuration->{bind_password} = '';
    }
    return $Configuration;
}

sub _RuntimeMappingList {
    my ( $Self, %Param ) = @_;
    my $Rows = $Self->{DB}->SelectAll(
        'SELECT m.field_id, m.ldap_attribute, m.is_required, m.update_on_login, m.clear_empty,
                f.field_type, f.name
         FROM ldap_field_mapping m
         INNER JOIN user_dynamic_field f ON f.id = m.field_id
         WHERE m.ldap_configuration_id = ? AND m.object_type = ? AND f.active = 1
         ORDER BY f.sort_order ASC, f.id ASC',
        $Param{ConfigurationID} || 0,
        $Param{ObjectType} || 'agent',
    );
    if ( !$Rows ) {
        $Self->{LastError} = $Self->{DB}->Error() || 'Translate:LDAPFieldMappingLoadFailed';
        return [];
    }
    return $Rows;
}

sub _AttributeValue {
    my ( $Self, $Attributes, $Name ) = @_;
    return '' if ref $Attributes ne 'HASH' || !$Name;
    my $Value = $Attributes->{lc $Name};
    if ( ref $Value eq 'ARRAY' ) {
        return $Self->_Trim( $Value->[0] );
    }
    return $Self->_Trim($Value);
}

sub _DecodeLDAPValue {
    my ( $Self, $Value ) = @_;
    return '' if !defined $Value;
    return $Value if utf8::is_utf8($Value);
    return decode( 'UTF-8', $Value, FB_DEFAULT );
}

sub _AttributeValid {
    my ( $Self, $Attribute ) = @_;
    return $Attribute && length($Attribute) <= 100
        && $Attribute =~ m{\A(?:[A-Za-z][A-Za-z0-9-]*|[0-9]+(?:\.[0-9]+)+)\z} ? 1 : 0;
}

sub _FilterLooksValid {
    my ( $Self, $Filter ) = @_;
    return if !$Filter || length($Filter) > 2000 || $Filter =~ m{\x00};
    return if $Filter !~ m{\A\(.*\)\z}s;
    my $Depth = 0;
    my $Escaped = 0;
    for my $Character ( split //, $Filter ) {
        if ($Escaped) {
            $Escaped = 0;
            next;
        }
        if ( $Character eq '\\' ) {
            $Escaped = 1;
            next;
        }
        $Depth++ if $Character eq '(';
        $Depth-- if $Character eq ')';
        return if $Depth < 0;
    }
    return $Depth == 0 ? 1 : 0;
}

sub _FilterEscape {
    my ( $Self, $Value ) = @_;
    my $Bytes = encode( 'UTF-8', defined $Value ? $Value : '' );
    $Bytes =~ s{([\x00\x28\x29\x2a\x5c])}{sprintf '\\%02x', ord($1)}ge;
    return $Bytes;
}

sub _Trim {
    my ( $Self, $Value ) = @_;
    $Value = '' if !defined $Value || ref $Value;
    $Value =~ s{\A\s+|\s+\z}{}g;
    return $Value;
}

sub _ProfileType {
    my ( $Self, $ProfileType ) = @_;
    $ProfileType = $Self->_Trim($ProfileType) || 'agent';
    if ( $ProfileType !~ m{\A(?:agent|customer)\z} ) {
        $Self->{LastError} = 'Translate:LDAPProfileTypeInvalid';
        return;
    }
    return $ProfileType;
}

1;
