#!/usr/bin/env perl

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

use strict;
use warnings;
use utf8;

use FindBin;
use Test::More;

use lib "$FindBin::Bin/../core/system", "$FindBin::Bin/../core/output";

use QisutuAuth;
use QisutuLDAP;
use QisutuOutput;

{
    package Local::LDAPDB;

    sub new {
        my ( $Class, %Param ) = @_;
        return bless {
            Configuration => $Param{Configuration},
            Users         => $Param{Users} || [],
            Mappings      => $Param{Mappings} || [],
            Fields        => $Param{Fields} || [],
            InsertCount   => 0,
            NextID        => 100,
            Error         => '',
        }, $Class;
    }

    sub SelectRow {
        my ( $Self, $SQL, @Bind ) = @_;

        if ( $SQL =~ /FROM ldap_configuration/ ) {
            return $Self->{Configuration} ? { %{ $Self->{Configuration} } } : undef;
        }
        if ( $SQL =~ /WHERE login = .*account_type = "agent"/s ) {
            my $Login = $Bind[0];
            my ($User) = grep { $_->{login} eq $Login && $_->{account_type} eq 'agent' } @{ $Self->{Users} };
            return $User ? { %{$User} } : undef;
        }
        if ( $SQL =~ /LOWER\(email\)/ ) {
            my ( $Email, $Ignored, $ExcludedID ) = @Bind;
            my ($User) = grep {
                lc( $_->{email} || '' ) eq lc($Email)
                    && $_->{account_type} eq 'agent'
                    && $_->{id} != $ExcludedID
            } @{ $Self->{Users} };
            return $User ? { id => $User->{id}, login => $User->{login} } : undef;
        }
        return undef;
    }

    sub SelectAll {
        my ( $Self, $SQL ) = @_;
        return [ map { { %{$_} } } @{ $Self->{Mappings} } ]
            if $SQL =~ /FROM ldap_field_mapping/;
        return [ map { { %{$_} } } @{ $Self->{Fields} } ]
            if $SQL =~ /FROM user_dynamic_field/;
        return [];
    }

    sub Do {
        my ( $Self, $SQL, @Bind ) = @_;

        if ( $SQL =~ /UPDATE user_account\s+SET email =/s ) {
            my ( $Email, $Firstname, $Lastname, $ID ) = @Bind;
            my ($User) = grep { $_->{id} == $ID } @{ $Self->{Users} };
            return if !$User;
            $User->{email} = $Email;
            $User->{firstname} = $Firstname;
            $User->{lastname} = $Lastname;
            $User->{authentication_type} = 'ldap';
            return 1;
        }
        if ( $SQL =~ /UPDATE user_account\s+SET authentication_type = "ldap"/s ) {
            my $ID = $Bind[-1];
            my ($User) = grep { $_->{id} == $ID } @{ $Self->{Users} };
            return if !$User;
            $User->{authentication_type} = 'ldap';
            return 1;
        }
        if ( $SQL =~ /INSERT INTO user_account/ ) {
            my ( $Login, $Email, $Firstname, $Lastname ) = @Bind;
            my $ID = ++$Self->{NextID};
            push @{ $Self->{Users} }, {
                id => $ID, login => $Login, account_type => 'agent',
                authentication_type => 'ldap', email => $Email,
                firstname => $Firstname, lastname => $Lastname,
                is_active => 1, is_system_user => 0,
            };
            $Self->{LastInsertID} = $ID;
            $Self->{InsertCount}++;
            return 1;
        }
        return 1;
    }

    sub BeginWork    { return 1 }
    sub Commit       { return 1 }
    sub Rollback     { return 1 }
    sub LastInsertID { return $_[0]->{LastInsertID} }
    sub Error        { return $_[0]->{Error} || '' }
}

{
    package Local::AuthLDAP;
    sub new { return bless { Result => $_[1], Error => $_[2] || '' }, $_[0] }
    sub AuthenticateAgent { return $_[0]->{Result} }
    sub Error { return $_[0]->{Error} }
}

{
    package Local::NoLocalDB;
    sub SelectRow { die "local authentication must not be called" }
}

my $Root = "$FindBin::Bin/..";
my $Configuration = {
    id => 1, active => 1, update_on_login => 1,
    login_attribute => 'userPrincipalName',
    firstname_attribute => 'givenName',
    lastname_attribute => 'sn',
    email_attribute => 'mail',
};

sub LDAPObject {
    my (%Param) = @_;
    return QisutuLDAP->new(
        Config => {},
        DB => $Param{DB},
        DirectoryAuthenticator => sub { return $Param{Result} },
    );
}

my $FilterLDAP = QisutuLDAP->new( Config => {}, DB => undef );
is(
    $FilterLDAP->_FilterEscape("a*(b)\\\0"),
    'a\2a\28b\29\5c\00',
    'LDAP filter metacharacters are escaped before a login is searched',
);

my $ExistingDB = Local::LDAPDB->new(
    Configuration => $Configuration,
    Users => [ {
        id => 7, login => 'ud@example.test', account_type => 'agent',
        authentication_type => 'local', email => 'old@example.test',
        firstname => 'Alt', lastname => 'Name', is_active => 1, is_system_user => 0,
    } ],
);
my $ExistingLDAP = LDAPObject(
    DB => $ExistingDB,
    Result => {
        Status => 'success',
        Attributes => {
            userprincipalname => ['ud@example.test'],
            givenname => ['Uwe'], sn => ['Dieckmann'], mail => ['ud@example.test'],
        },
    },
);
my $ExistingResult = $ExistingLDAP->AuthenticateAgent( Login => 'UD', Password => 'secret' );
is( $ExistingResult->{User}->{id}, 7, 'the canonical value of the mapped login field reuses the existing agent' );
is( $ExistingDB->{InsertCount}, 0, 'an exact mapped-login match never creates a duplicate agent' );
is( $ExistingDB->{Users}->[0]->{authentication_type}, 'ldap', 'the reused account is switched to directory authentication' );
is( $ExistingDB->{Users}->[0]->{firstname}, 'Uwe', 'mapped standard data is updated on login' );

my $NewDB = Local::LDAPDB->new( Configuration => $Configuration );
my $NewLDAP = LDAPObject(
    DB => $NewDB,
    Result => {
        Status => 'success',
        Attributes => {
            userprincipalname => ['new.agent@example.test'],
            givenname => ['New'], sn => ['Agent'], mail => ['new.agent@example.test'],
        },
    },
);
my $NewResult = $NewLDAP->AuthenticateAgent( Login => 'typed-value', Password => 'secret' );
ok( $NewResult->{User}, 'a directory agent is provisioned after the first successful login' );
is( $NewDB->{InsertCount}, 1, 'a new agent is created only when the mapped login does not exist' );
is( $NewDB->{Users}->[0]->{login}, 'new.agent@example.test', 'the configured directory attribute supplies the Qisutu login' );

my $ConflictDB = Local::LDAPDB->new(
    Configuration => $Configuration,
    Users => [ {
        id => 8, login => 'other.agent', account_type => 'agent', authentication_type => 'local',
        email => 'shared@example.test', firstname => 'Other', lastname => 'Agent',
        is_active => 1, is_system_user => 0,
    } ],
);
my $ConflictLDAP = LDAPObject(
    DB => $ConflictDB,
    Result => {
        Status => 'success',
        Attributes => {
            userprincipalname => ['new.agent'], givenname => ['New'], sn => ['Agent'],
            mail => ['shared@example.test'],
        },
    },
);
my $ConflictResult = $ConflictLDAP->AuthenticateAgent( Login => 'new.agent', Password => 'secret' );
ok( !$ConflictResult->{User}, 'an email collision with another login blocks automatic provisioning' );
is( $ConflictLDAP->Error(), 'Translate:LDAPAgentEmailConflict', 'the collision has a specific administrator-facing error' );
is( $ConflictDB->{InsertCount}, 0, 'an email collision cannot create a duplicate account' );

my $MissingDB = Local::LDAPDB->new( Configuration => $Configuration );
my $MissingLDAP = LDAPObject(
    DB => $MissingDB,
    Result => {
        Status => 'success',
        Attributes => {
            userprincipalname => ['missing.name'], givenname => [], sn => ['Agent'],
            mail => ['missing@example.test'],
        },
    },
);
my $MissingResult = $MissingLDAP->AuthenticateAgent( Login => 'missing.name', Password => 'secret' );
ok( !$MissingResult->{User}, 'provisioning is blocked if one of the four mandatory mapped values is empty' );
is( $MissingLDAP->Error(), 'Translate:LDAPFirstnameValueMissing', 'the missing mandatory firstname is identified' );

my $RequiredMappingDB = Local::LDAPDB->new(
    Fields => [ { id => 55, object_type => 'agent', is_required => 1 } ],
);
my $RequiredMappingLDAP = QisutuLDAP->new( Config => {}, DB => $RequiredMappingDB );
my $RequiredMappingSave = $RequiredMappingLDAP->ConfigurationSave(
    Host => 'ldap.example.test', Port => 636, ConnectionSecurity => 'ldaps',
    VerifyCertificate => 1, BaseDN => 'ou=users,dc=example,dc=test',
    UserFilter => '(objectClass=person)', LoginAttribute => 'uid',
    FirstnameAttribute => 'givenName', LastnameAttribute => 'sn', EmailAttribute => 'mail',
    UpdateOnLogin => 1, Mappings => [], ChangedByUserID => 1,
);
ok( !$RequiredMappingSave, 'a required Qisutu agent field cannot be left unmapped' );
is( $RequiredMappingLDAP->Error(), 'Translate:LDAPRequiredAgentFieldMappingMissing', 'the missing required custom-field mapping has a specific error' );

my $NotFoundDB = Local::LDAPDB->new( Configuration => $Configuration );
my $NotFoundLDAP = LDAPObject( DB => $NotFoundDB, Result => { Status => 'not_found' } );
is( $NotFoundLDAP->AuthenticateAgent( Login => 'local', Password => 'secret' )->{Handled}, 0, 'no directory entry allows the normal local-login lookup' );

my $AuthoritativeLDAP = Local::AuthLDAP->new( { Handled => 1 }, 'Translate:LDAPAuthenticationFailed' );
my $AuthoritativeAuth = QisutuAuth->new( Config => {}, DB => bless( {}, 'Local::NoLocalDB' ), LDAP => $AuthoritativeLDAP );
my $AuthoritativeUser = eval {
    $AuthoritativeAuth->LoginCheck( Login => 'agent', Password => 'wrong', AccountType => 'agent' );
};
ok( !$@, 'a failed authoritative directory login does not call the local database authentication path' );
ok( !$AuthoritativeUser, 'wrong directory credentials do not fall back to a local password' );

open my $LoginFH, '<:encoding(UTF-8)', "$Root/core/output/Login.tt" or die $!;
my $LoginTemplate = do { local $/; <$LoginFH> };
close $LoginFH;
unlike(
    $LoginTemplate,
    qr{name="(?:LDAP|AuthenticationProvider)"|Active Directory},
    'the login form contains no selectable LDAP backend; optional external add-ons are rendered separately',
);

open my $LDAPTemplateFH, '<:encoding(UTF-8)', "$Root/core/output/AdminLDAP.tt" or die $!;
my $LDAPTemplate = do { local $/; <$LDAPTemplateFH> };
close $LDAPTemplateFH;
for my $RequiredName ( qw(LoginAttribute FirstnameAttribute LastnameAttribute EmailAttribute) ) {
    like( $LDAPTemplate, qr{name="$RequiredName"[^>]*required}, "$RequiredName is a mandatory administrator mapping" );
}
like( $LDAPTemplate, qr{Mapping[.]attribute_required}, 'Qisutu-required agent fields also render a mandatory LDAP attribute input' );
like( $LDAPTemplate, qr{CustomerFieldMappings}, 'the independent customer profile renders customer-user mapping controls' );

my $Output = QisutuOutput->new( Config => {
    Paths => { Output => "$Root/core/output", Language => "$Root/core/language" },
    Language => { Default => 'de' },
} );
my $Rendered = $Output->RenderSingle(
    Template => 'AdminLDAP.tt',
    Data => {
        Language => 'de', ConfigurationID => 1, HasConfiguration => 1,
        LDAPActive => 0, LDAPModuleMissing => 0, LDAPHasBindPassword => 0,
        HasAgentFieldMappings => 1, HasCustomerFieldMappings => 1,
        DirectoryTypeOptionsHTML => '<option>Active Directory</option>',
        SecurityOptionsHTML => '<option>LDAPS</option>', DefaultGroupOptionsHTML => '<option>Keine</option>',
        AgentFieldMappings => [ { label => 'Straße', name => 'street', field_type => 'text', input_name => 'Mapping_agent_1_Attribute', required_name => 'Mapping_agent_1_Required', update_name => 'Mapping_agent_1_Update', clear_name => 'Mapping_agent_1_Clear' } ],
        CustomerFieldMappings => [ { label => 'Ort', name => 'city', field_type => 'text', input_name => 'Mapping_customer_user_2_Attribute', required_name => 'Mapping_customer_user_2_Required', update_name => 'Mapping_customer_user_2_Update', clear_name => 'Mapping_customer_user_2_Clear' } ],
    },
);
ok( defined $Rendered && length $Rendered, 'the central LDAP administration template renders' );
unlike( $Rendered || '', qr{\[\%}, 'LDAP administration rendering leaves no template directives behind' );
like( $Rendered || '', qr{Mapping_agent_1_Attribute}, 'the rendered page includes agent dynamic-field mapping controls' );
like( $Rendered || '', qr{Mapping_customer_user_2_Attribute}, 'the rendered page includes active customer-user mapping controls' );

for my $File ( qw(install.sh update.sh bin/cgi-bin/install.pl install/sql/schema.sql) ) {
    open my $FH, '<:encoding(UTF-8)', "$Root/$File" or die $!;
    my $Content = do { local $/; <$FH> };
    close $FH;
    like( $Content, qr{(?:Net::LDAP|net-ldap|perl-LDAP|ldap_configuration)}, "$File contains the LDAP installation or schema integration" );
}

open my $ReleaseFH, '<:encoding(UTF-8)', "$Root/release.conf" or die $!;
my $Release = do { local $/; <$ReleaseFH> };
close $ReleaseFH;
like( $Release, qr{^version=1[.]0[.]2$}m, 'the current release uses program version 1.0.1' );
like( $Release, qr{^database_version=1[.]0[.]1$}m, 'the first official release uses database version 1.0.1' );

done_testing();
