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

use lib "$FindBin::Bin/../core/system", "$FindBin::Bin/../core/module";

use AdminLDAP;
use QisutuAuth;
use QisutuLDAP;

{
    package Local::CustomerLDAPDB;

    sub new {
        my ($Class) = @_;
        return bless {
            Configurations => [
                {
                    id => 1, profile_type => 'agent', active => 1,
                    login_attribute => 'uid', firstname_attribute => 'givenName',
                    lastname_attribute => 'sn', email_attribute => 'mail',
                },
                {
                    id => 2, profile_type => 'customer', active => 1, update_on_login => 1,
                    login_attribute => 'customerLogin', firstname_attribute => 'givenName',
                    lastname_attribute => 'sn', email_attribute => 'mail',
                    customer_number_attribute => 'companyNumber',
                    customer_name_attribute => 'company',
                },
            ],
            Customers => [], Users => [], Relations => [], DynamicValues => [],
            NextCustomerID => 10, NextUserID => 20, NextRelationID => 30,
            Error => '',
        }, $Class;
    }

    sub SelectRow {
        my ( $Self, $SQL, @Bind ) = @_;
        if ( $SQL =~ /FROM ldap_configuration/ ) {
            my ($ProfileType) = grep { defined $_ && ($_ eq 'agent' || $_ eq 'customer') } @Bind;
            my ($Row) = grep {
                ( !$ProfileType || $_->{profile_type} eq $ProfileType )
                    && ( $SQL !~ /active = 1/ || $_->{active} )
            } @{ $Self->{Configurations} };
            return $Row ? { %{$Row} } : undef;
        }
        if ( $SQL =~ /FROM customer WHERE customer_number/ ) {
            my ($Row) = grep { $_->{customer_number} eq $Bind[0] } @{ $Self->{Customers} };
            return $Row ? { %{$Row} } : undef;
        }
        if ( $SQL =~ /FROM user_account\s+WHERE login = .*account_type = "customer"/s ) {
            my ($Row) = grep {
                $_->{login} eq $Bind[0] && $_->{account_type} eq 'customer'
            } @{ $Self->{Users} };
            return $Row ? { %{$Row} } : undef;
        }
        if ( $SQL =~ /LOWER\(email\).*account_type = "customer"/s ) {
            my ( $Email, $Ignored, $ExcludedID ) = @Bind;
            my ($Row) = grep {
                lc( $_->{email} || '' ) eq lc($Email) && $_->{account_type} eq 'customer'
                    && $_->{id} != $ExcludedID
            } @{ $Self->{Users} };
            return $Row ? { id => $Row->{id}, login => $Row->{login} } : undef;
        }
        if ( $SQL =~ /FROM customer_user/ ) {
            my ( $CustomerID, $UserID ) = @Bind;
            my ($Row) = grep {
                $_->{customer_id} == $CustomerID && $_->{user_account_id} == $UserID
            } @{ $Self->{Relations} };
            return $Row ? { %{$Row} } : undef;
        }
        return undef;
    }

    sub SelectAll {
        my ( $Self, $SQL, @Bind ) = @_;
        if ( $SQL =~ /FROM ldap_field_mapping/ ) {
            return [] if ( $Bind[1] || '' ) ne 'customer_user';
            return [ {
                field_id => 77, ldap_attribute => 'department', is_required => 1,
                update_on_login => 1, clear_empty => 0, field_type => 'text', name => 'department',
            } ];
        }
        return [];
    }

    sub Do {
        my ( $Self, $SQL, @Bind ) = @_;
        if ( $SQL =~ /INSERT INTO customer \(/ ) {
            my $ID = ++$Self->{NextCustomerID};
            push @{ $Self->{Customers} }, {
                id => $ID, customer_number => $Bind[0], name => $Bind[1], active => 1,
            };
            $Self->{LastInsert}->{customer} = $ID;
            return 1;
        }
        if ( $SQL =~ /UPDATE customer\s+SET name/s ) {
            my ($Row) = grep { $_->{id} == $Bind[1] } @{ $Self->{Customers} };
            $Row->{name} = $Bind[0] if $Row;
            return $Row ? 1 : undef;
        }
        if ( $SQL =~ /INSERT INTO user_account/ ) {
            my $ID = ++$Self->{NextUserID};
            push @{ $Self->{Users} }, {
                id => $ID, login => $Bind[0], account_type => 'customer',
                authentication_type => 'ldap', email => $Bind[1],
                firstname => $Bind[2], lastname => $Bind[3],
                is_active => 1, is_system_user => 0,
            };
            $Self->{LastInsert}->{user_account} = $ID;
            return 1;
        }
        if ( $SQL =~ /UPDATE user_account\s+SET email/s ) {
            my ($Row) = grep { $_->{id} == $Bind[3] } @{ $Self->{Users} };
            return if !$Row;
            @{$Row}{qw(email firstname lastname authentication_type)} = ( @Bind[0..2], 'ldap' );
            return 1;
        }
        if ( $SQL =~ /UPDATE user_account\s+SET authentication_type/s ) {
            my ($Row) = grep { $_->{id} == $Bind[0] } @{ $Self->{Users} };
            $Row->{authentication_type} = 'ldap' if $Row;
            return $Row ? 1 : undef;
        }
        if ( $SQL =~ /UPDATE customer_user\s+SET active = 0/s ) {
            for my $Row ( @{ $Self->{Relations} } ) {
                $Row->{active} = 0
                    if $Row->{user_account_id} == $Bind[0] && $Row->{customer_id} != $Bind[1];
            }
            return 1;
        }
        if ( $SQL =~ /INSERT INTO customer_user/ ) {
            my ($Row) = grep {
                $_->{customer_id} == $Bind[0] && $_->{user_account_id} == $Bind[1]
            } @{ $Self->{Relations} };
            if ($Row) {
                $Row->{active} = 1;
            }
            else {
                $Row = {
                    id => ++$Self->{NextRelationID}, customer_id => $Bind[0],
                    user_account_id => $Bind[1], active => 1,
                };
                push @{ $Self->{Relations} }, $Row;
            }
            $Self->{LastInsert}->{customer_user} = $Row->{id};
            return 1;
        }
        if ( $SQL =~ /INSERT INTO user_dynamic_field_value/ ) {
            push @{ $Self->{DynamicValues} }, {
                object_type => 'customer_user', object_id => $Bind[0],
                field_id => $Bind[1], value => $Bind[2],
            };
            return 1;
        }
        return 1;
    }

    sub BeginWork { return 1 }
    sub Commit { return 1 }
    sub Rollback { return 1 }
    sub LastInsertID { return $_[0]->{LastInsert}->{ $_[1] } || 0 }
    sub Error { return $_[0]->{Error} || '' }
}

{
    package Local::CustomerAuthoritativeLDAP;
    sub new { return bless { Result => $_[1], Error => $_[2] || '' }, $_[0] }
    sub AuthenticateCustomer { return $_[0]->{Result} }
    sub AuthenticateAgent { die 'agent LDAP must not be called for a customer sign-in' }
    sub Error { return $_[0]->{Error} }
}

{
    package Local::NoCustomerLocalDB;
    sub SelectRow { die 'local customer authentication must not be called' }
}

{
    package Local::LDAPOutput;
    sub Translate { my ( $Self, %Param ) = @_; return $Param{Key} || '' }
    sub HTMLEscape { return defined $_[1] ? $_[1] : '' }
}

{
    package Local::LDAPConfigurationInsertDB;
    sub new { return bless { Calls => [], Error => '' }, $_[0] }
    sub SelectRow { return undef }
    sub SelectAll { return [] }
    sub Do {
        my ( $Self, $SQL, @Bind ) = @_;
        push @{ $Self->{Calls} }, { SQL => $SQL, Bind => \@Bind };
        return 1;
    }
    sub BeginWork { return 1 }
    sub Commit { return 1 }
    sub Rollback { return 1 }
    sub LastInsertID { return 99 }
    sub Error { return $_[0]->{Error} || '' }
}

my $DB = Local::CustomerLDAPDB->new();
my @DirectoryCall;
my $LDAP = QisutuLDAP->new(
    Config => {}, DB => $DB,
    DirectoryAuthenticator => sub {
        my (%Param) = @_;
        push @DirectoryCall, {
            profile_type => $Param{Configuration}->{profile_type},
            object_type  => $Param{ObjectType},
        };
        return {
            Status => 'success',
            Attributes => {
                customerlogin => ['anna.customer'], givenname => ['Anna'], sn => ['Kundin'],
                mail => ['anna@example.test'], companynumber => ['C-100'],
                company => ['Beispiel GmbH'], department => ['Einkauf'],
            },
        };
    },
);

is( $LDAP->ConfigurationGet( ProfileType => 'agent' )->{id}, 1, 'the agent profile is loaded independently' );
is( $LDAP->ConfigurationGet( ProfileType => 'customer' )->{id}, 2, 'the customer profile is loaded independently' );
ok( !$LDAP->ConfigurationGet( ProfileType => 'invalid' )->{id}, 'an unknown LDAP profile cannot be loaded' );
is( $LDAP->Error(), 'Translate:LDAPProfileTypeInvalid', 'an invalid LDAP profile has a specific error' );

my $MissingCompanyMapping = $LDAP->ConfigurationSave(
    ConfigurationID => 2, ProfileType => 'customer',
    Host => 'ldap.example.test', Port => 636, ConnectionSecurity => 'ldaps',
    BaseDN => 'ou=customers,dc=example,dc=test', UserFilter => '(objectClass=person)',
    LoginAttribute => 'customerLogin', FirstnameAttribute => 'givenName',
    LastnameAttribute => 'sn', EmailAttribute => 'mail', CustomerNameAttribute => 'company',
    Mappings => [], ChangedByUserID => 1,
);
ok( !$MissingCompanyMapping, 'a customer LDAP profile cannot be saved without a customer-number mapping' );
is( $LDAP->Error(), 'Translate:LDAPCustomerNumberAttributeRequired', 'the missing customer-number mapping is identified' );

my $InsertDB = Local::LDAPConfigurationInsertDB->new();
my $InsertLDAP = QisutuLDAP->new( Config => {}, DB => $InsertDB );
is(
    $InsertLDAP->ConfigurationSave(
        ProfileType => 'customer', Name => 'Customers',
        Host => 'ldap.example.test', Port => 636, ConnectionSecurity => 'ldaps',
        VerifyCertificate => 1, BaseDN => 'ou=customers,dc=example,dc=test',
        UserFilter => '(objectClass=person)', LoginAttribute => 'customerLogin',
        FirstnameAttribute => 'givenName', LastnameAttribute => 'sn', EmailAttribute => 'mail',
        CustomerNumberAttribute => 'companyNumber', CustomerNameAttribute => 'company',
        UpdateOnLogin => 1, Mappings => [], ChangedByUserID => 1,
    ),
    99,
    'a new customer LDAP profile can be stored independently',
);
my ($InsertCall) = grep { $_->{SQL} =~ /INSERT INTO ldap_configuration/ } @{ $InsertDB->{Calls} };
ok( $InsertCall, 'customer LDAP profile creation uses its own configuration row' );
is( $InsertCall->{Bind}->[0], 'customer', 'the new configuration row is marked as the customer profile' );
my $PlaceholderCount = () = $InsertCall->{SQL} =~ /\?/g;
is( $PlaceholderCount, scalar @{ $InsertCall->{Bind} }, 'customer profile SQL has one bind value per placeholder' );

my $AgentProfileUsed = '';
my $AgentLDAP = QisutuLDAP->new(
    Config => {}, DB => $DB,
    DirectoryAuthenticator => sub {
        my (%Param) = @_;
        $AgentProfileUsed = $Param{Configuration}->{profile_type};
        return { Status => 'not_found' };
    },
);
is( $AgentLDAP->AuthenticateAgent( Login => 'agent', Password => 'secret' )->{Handled}, 0,
    'an agent absent from agent LDAP may continue to local authentication' );
is( $AgentProfileUsed, 'agent', 'agent authentication never uses the customer LDAP profile' );

my $AdminResult = AdminLDAP->new(
    Config => { Language => { Default => 'de' } }, DB => $DB,
    Output => bless( {}, 'Local::LDAPOutput' ),
)->Run(
    Request => { ProfileType => 'customer' },
    User => { user_account_id => 1 },
);
is( $AdminResult->{Data}->{ProfileType}, 'customer', 'LDAP administration keeps the selected customer profile' );
is( $AdminResult->{Data}->{ConfigurationID}, 2, 'LDAP administration loads the independent customer configuration' );
ok( $AdminResult->{Data}->{IsCustomerProfile}, 'LDAP administration enables customer-specific mapping controls' );

my $Result = $LDAP->AuthenticateCustomer( Login => 'anna', Password => 'secret' );
ok( $Result->{User}, 'a customer user can authenticate against the customer LDAP profile' );
is( $DirectoryCall[0]->{profile_type}, 'customer', 'customer authentication never uses the agent LDAP profile' );
is( $DirectoryCall[0]->{object_type}, 'customer_user', 'the customer-user mapping is used for the directory query' );
is( scalar @{ $DB->{Customers} }, 1, 'the mapped customer company is provisioned' );
is( $DB->{Customers}->[0]->{customer_number}, 'C-100', 'the mapped customer number identifies the company' );
is( scalar @{ $DB->{Users} }, 1, 'the Qisutu customer account is provisioned' );
is( $DB->{Users}->[0]->{account_type}, 'customer', 'the provisioned account is a customer account' );
is( scalar @{ $DB->{Relations} }, 1, 'one active company assignment is provisioned' );
is( $Result->{User}->{customer_id}, $DB->{Customers}->[0]->{id}, 'the authenticated user includes the customer company id' );
is( $Result->{User}->{customer_user_id}, $DB->{Relations}->[0]->{id}, 'the authenticated user includes the customer-user assignment id' );
is( $DB->{DynamicValues}->[0]->{object_type}, 'customer_user', 'dynamic LDAP data is written to the customer-user assignment' );
is( $DB->{DynamicValues}->[0]->{value}, 'Einkauf', 'the mapped customer-user value is provisioned' );

my $Second = $LDAP->AuthenticateCustomer( Login => 'anna', Password => 'secret' );
ok( $Second->{User}, 'an existing LDAP customer user can sign in again' );
is( scalar @{ $DB->{Customers} }, 1, 'a repeated sign-in does not duplicate the customer company' );
is( scalar @{ $DB->{Users} }, 1, 'a repeated sign-in does not duplicate the customer account' );
is( scalar( grep { $_->{active} } @{ $DB->{Relations} } ), 1, 'a repeated sign-in keeps exactly one active company assignment' );

my $NotFoundLDAP = QisutuLDAP->new(
    Config => {}, DB => Local::CustomerLDAPDB->new(),
    DirectoryAuthenticator => sub { return { Status => 'not_found' } },
);
is( $NotFoundLDAP->AuthenticateCustomer( Login => 'local', Password => 'secret' )->{Handled}, 0,
    'a customer missing from customer LDAP may continue to local authentication' );

my $AuthoritativeLDAP = Local::CustomerAuthoritativeLDAP->new(
    { Handled => 1 }, 'Translate:LDAPAuthenticationFailed',
);
my $Auth = QisutuAuth->new(
    Config => {}, DB => bless( {}, 'Local::NoCustomerLocalDB' ), LDAP => $AuthoritativeLDAP,
);
my $User = eval {
    $Auth->LoginCheck( Login => 'customer', Password => 'wrong', AccountType => 'customer' );
};
ok( !$@, 'a failed authoritative customer LDAP login does not query local authentication' );
ok( !$User, 'wrong customer LDAP credentials never fall back to a local password' );

my $Root = "$FindBin::Bin/..";
open my $TemplateFH, '<:encoding(UTF-8)', "$Root/core/output/AdminLDAP.tt" or die $!;
my $Template = do { local $/; <$TemplateFH> };
close $TemplateFH;
like( $Template, qr{ProfileType=agent}, 'LDAP administration exposes an agent profile selector' );
like( $Template, qr{ProfileType=customer}, 'LDAP administration exposes a customer profile selector' );
like( $Template, qr{name="CustomerNumberAttribute"[^>]*required}, 'customer number mapping is mandatory in administration' );
like( $Template, qr{name="CustomerNameAttribute"[^>]*required}, 'customer name mapping is mandatory in administration' );

open my $SchemaFH, '<:encoding(UTF-8)', "$Root/install/sql/schema.sql" or die $!;
my $Schema = do { local $/; <$SchemaFH> };
close $SchemaFH;
like( $Schema, qr{`profile_type` varchar\(20\) NOT NULL DEFAULT 'agent'}, 'fresh installations include separate LDAP profile types' );
like( $Schema, qr{`customer_number_attribute` varchar\(100\)}, 'fresh installations include customer-company mapping attributes' );

done_testing();
