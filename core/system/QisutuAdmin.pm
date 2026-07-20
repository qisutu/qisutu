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

package QisutuAdmin;

use strict;
use warnings;
use utf8;

use QisutuHTML;
use QisutuMail;
use QisutuOAuth2;
use QisutuSecurity;

sub new {
    my ( $Class, %Param ) = @_;

    my $Self = {
        DB        => $Param{DB},
        Config    => $Param{Config},
        LastError => '',
        Security  => QisutuSecurity->new( Config => $Param{Config} ),
    };

    bless $Self, $Class;

    return $Self;
}

sub AgentList {
    my ($Self) = @_;

    my $Rows = $Self->{DB}->SelectAll(
        'SELECT
            ua.id,
            ua.login,
            ua.account_type,
            ua.email,
            ua.firstname,
            ua.lastname,
            ua.is_active,
            ua.created_at,
            GROUP_CONCAT(DISTINCT ug.name ORDER BY ug.sort_order ASC, ug.name ASC SEPARATOR ", ") AS group_names
         FROM user_account ua
         LEFT JOIN customer_user cu
            ON cu.user_account_id = ua.id
         LEFT JOIN user_group_member ugm
            ON ugm.user_account_id = ua.id
            AND ugm.active = 1
         LEFT JOIN user_group ug
            ON ug.id = ugm.user_group_id
            AND ug.active = 1
         WHERE ua.is_system_user = 0
            AND ua.account_type = "agent"
            AND cu.id IS NULL
         GROUP BY ua.id, ua.login, ua.account_type, ua.email, ua.firstname, ua.lastname, ua.is_active, ua.created_at
         ORDER BY ua.login ASC'
    );

    return $Self->_RowsPrepare( Rows => $Rows );
}

sub AgentGet {
    my ( $Self, %Param ) = @_;

    my $UserAccountID = $Param{UserAccountID} || 0;

    return if $UserAccountID !~ m{\A\d+\z} || !$UserAccountID;

    my $Agent = $Self->{DB}->SelectRow(
        'SELECT
            ua.id,
            ua.login,
            ua.account_type,
            ua.email,
            ua.firstname,
            ua.lastname,
            ua.is_active,
            ua.created_at,
            GROUP_CONCAT(DISTINCT ug.name ORDER BY ug.sort_order ASC, ug.name ASC SEPARATOR ", ") AS group_names
         FROM user_account ua
         LEFT JOIN customer_user cu
            ON cu.user_account_id = ua.id
         LEFT JOIN user_group_member ugm
            ON ugm.user_account_id = ua.id
            AND ugm.active = 1
         LEFT JOIN user_group ug
            ON ug.id = ugm.user_group_id
            AND ug.active = 1
         WHERE ua.id = ?
            AND ua.is_system_user = 0
            AND ua.account_type = "agent"
            AND cu.id IS NULL
         GROUP BY ua.id, ua.login, ua.account_type, ua.email, ua.firstname, ua.lastname, ua.is_active, ua.created_at
         LIMIT 1',
        $UserAccountID,
    );

    if ( !$Agent ) {
        $Self->{LastError} = 'Agent was not found';
        return;
    }

    return $Self->_RowsPrepare( Rows => [$Agent] )->[0];
}

sub CustomerList {
    my ($Self) = @_;

    my $Rows = $Self->{DB}->SelectAll(
        'SELECT
            c.id,
            c.customer_number,
            c.name,
            c.active,
            c.created_at,
            COUNT(cu.id) AS user_count
         FROM customer c
         LEFT JOIN customer_user cu
            ON cu.customer_id = c.id
            AND cu.active = 1
         GROUP BY c.id, c.customer_number, c.name, c.active, c.created_at
         ORDER BY c.name ASC'
    );

    return $Self->_RowsPrepare( Rows => $Rows );
}

sub CustomerGet {
    my ( $Self, %Param ) = @_;

    my $CustomerID = $Param{CustomerID} || 0;

    return if $CustomerID !~ m{\A\d+\z} || !$CustomerID;

    my $Customer = $Self->{DB}->SelectRow(
        'SELECT
            id,
            customer_number,
            name,
            active,
            created_at
         FROM customer
         WHERE id = ?
         LIMIT 1',
        $CustomerID,
    );

    if ( !$Customer ) {
        $Self->{LastError} = 'Customer was not found';
        return;
    }

    return $Self->_RowsPrepare( Rows => [$Customer] )->[0];
}

sub CustomerUserList {
    my ($Self) = @_;

    my $Rows = $Self->{DB}->SelectAll(
        'SELECT
            cu.id,
            cu.customer_id,
            cu.user_account_id,
            cu.active,
            c.customer_number,
            c.name AS customer_name,
            ua.login,
            ua.email,
            ua.firstname,
            ua.lastname,
            ua.is_active
         FROM customer_user cu
         INNER JOIN customer c
            ON c.id = cu.customer_id
         INNER JOIN user_account ua
            ON ua.id = cu.user_account_id
         ORDER BY c.name ASC, ua.login ASC'
    );

    return $Self->_RowsPrepare( Rows => $Rows );
}

sub CustomerUserGet {
    my ( $Self, %Param ) = @_;

    my $CustomerUserID = $Param{CustomerUserID} || 0;

    return if $CustomerUserID !~ m{\A\d+\z} || !$CustomerUserID;

    my $CustomerUser = $Self->{DB}->SelectRow(
        'SELECT
            cu.id,
            cu.customer_id,
            cu.user_account_id,
            cu.active,
            c.customer_number,
            c.name AS customer_name,
            ua.login,
            ua.email,
            ua.firstname,
            ua.lastname,
            ua.is_active
         FROM customer_user cu
         INNER JOIN customer c
            ON c.id = cu.customer_id
         INNER JOIN user_account ua
            ON ua.id = cu.user_account_id
         WHERE cu.id = ?
         LIMIT 1',
        $CustomerUserID,
    );

    if ( !$CustomerUser ) {
        $Self->{LastError} = 'Customer user was not found';
        return;
    }

    return $Self->_RowsPrepare( Rows => [$CustomerUser] )->[0];
}

sub QueueList {
    my ($Self) = @_;

    my $Rows = $Self->{DB}->SelectAll(
        'SELECT
            tq.id,
            tq.parent_id,
            parent.full_name AS parent_full_name,
            tq.name,
            tq.full_name,
            tq.follow_up_allowed,
            tq.system_email_id,
            tq.salutation_id,
            tq.signature_id,
            tq.calendar_id,
            tq.escalation_first_response_minutes,
            tq.escalation_update_minutes,
            tq.escalation_solution_minutes,
            se.email AS system_email,
            sal.name AS salutation_name,
            sig.name AS signature_name,
            cal.name AS calendar_name,
            tq.active,
            tq.sort_order,
            GROUP_CONCAT(DISTINCT ug.name ORDER BY ug.sort_order ASC, ug.name ASC SEPARATOR ", ") AS group_names
         FROM ticket_queue tq
         LEFT JOIN ticket_queue parent
            ON parent.id = tq.parent_id
         LEFT JOIN system_email se
            ON se.id = tq.system_email_id
         LEFT JOIN salutation sal
            ON sal.id = tq.salutation_id
         LEFT JOIN signature sig
            ON sig.id = tq.signature_id
         LEFT JOIN calendar cal
            ON cal.id = tq.calendar_id
         LEFT JOIN ticket_queue_group tqg
            ON tqg.queue_id = tq.id
            AND tqg.active = 1
            AND tqg.permission_key = "ticket.view"
         LEFT JOIN user_group ug
            ON ug.id = tqg.user_group_id
            AND ug.active = 1
         GROUP BY
            tq.id, tq.parent_id, parent.full_name, tq.name, tq.full_name,
            tq.follow_up_allowed, tq.system_email_id, tq.salutation_id,
            tq.signature_id, tq.calendar_id,
            tq.escalation_first_response_minutes, tq.escalation_update_minutes,
            tq.escalation_solution_minutes, se.email, sal.name, sig.name,
            cal.name, tq.active, tq.sort_order
         ORDER BY tq.sort_order ASC, tq.full_name ASC'
    );

    return $Self->_RowsPrepare( Rows => $Rows );
}

sub QueueGet {
    my ( $Self, %Param ) = @_;

    my $QueueID = $Param{QueueID} || 0;

    return if $QueueID !~ m{\A\d+\z} || !$QueueID;

    my $Queue = $Self->{DB}->SelectRow(
        'SELECT
            tq.id,
            tq.parent_id,
            parent.full_name AS parent_full_name,
            tq.name,
            tq.full_name,
            tq.follow_up_allowed,
            tq.system_email_id,
            tq.salutation_id,
            tq.signature_id,
            tq.calendar_id,
            tq.escalation_first_response_minutes,
            tq.escalation_update_minutes,
            tq.escalation_solution_minutes,
            se.email AS system_email,
            sal.name AS salutation_name,
            sig.name AS signature_name,
            cal.name AS calendar_name,
            tq.active,
            tq.sort_order
         FROM ticket_queue tq
         LEFT JOIN ticket_queue parent
            ON parent.id = tq.parent_id
         LEFT JOIN system_email se
            ON se.id = tq.system_email_id
         LEFT JOIN salutation sal
            ON sal.id = tq.salutation_id
         LEFT JOIN signature sig
            ON sig.id = tq.signature_id
         LEFT JOIN calendar cal
            ON cal.id = tq.calendar_id
         WHERE tq.id = ?
         LIMIT 1',
        $QueueID,
    );

    if ( !$Queue ) {
        $Self->{LastError} = 'Queue was not found';
        return;
    }

    return $Self->_RowsPrepare( Rows => [$Queue] )->[0];
}

sub SystemEmailList {
    my ( $Self, %Param ) = @_;

    return $Self->_MasterDataList(
        Table           => 'system_email',
        ExtraSelect     => 'email',
        IncludeInactive => $Param{IncludeInactive},
    );
}

sub SalutationList {
    my ( $Self, %Param ) = @_;

    return $Self->_MasterDataList(
        Table           => 'salutation',
        ExtraSelect     => 'content',
        IncludeInactive => $Param{IncludeInactive},
    );
}

sub SignatureList {
    my ( $Self, %Param ) = @_;

    return $Self->_MasterDataList(
        Table           => 'signature',
        ExtraSelect     => 'content',
        IncludeInactive => $Param{IncludeInactive},
    );
}

sub CalendarList {
    my ( $Self, %Param ) = @_;

    return $Self->_MasterDataList(
        Table           => 'calendar',
        ExtraSelect     => 'timezone',
        IncludeInactive => $Param{IncludeInactive},
    );
}

sub SystemEmailGet {
    my ( $Self, %Param ) = @_;

    return $Self->_MasterDataGet(
        Table       => 'system_email',
        ExtraSelect => 'email',
        ID          => $Param{SystemEmailID},
    );
}

sub SystemEmailCreate {
    my ( $Self, %Param ) = @_;

    return $Self->_MasterDataCreate(
        Table           => 'system_email',
        ExtraColumn     => 'email',
        ExtraValue      => $Param{Email},
        Name            => $Param{Name},
        SortOrder       => $Param{SortOrder},
        ChangedByUserID => $Param{ChangedByUserID},
    );
}

sub SystemEmailUpdate {
    my ( $Self, %Param ) = @_;

    return $Self->_MasterDataUpdate(
        Table           => 'system_email',
        ExtraColumn     => 'email',
        ExtraValue      => $Param{Email},
        ID              => $Param{SystemEmailID},
        Name            => $Param{Name},
        Active          => $Param{Active},
        SortOrder       => $Param{SortOrder},
        ChangedByUserID => $Param{ChangedByUserID},
    );
}

sub SystemEmailDeactivate {
    my ( $Self, %Param ) = @_;

    return $Self->_MasterDataDeactivate(
        Table           => 'system_email',
        ID              => $Param{SystemEmailID},
        ChangedByUserID => $Param{ChangedByUserID},
    );
}

sub SalutationGet {
    my ( $Self, %Param ) = @_;

    return $Self->_MasterDataGet(
        Table       => 'salutation',
        ExtraSelect => 'content',
        ID          => $Param{SalutationID},
    );
}

sub SalutationCreate {
    my ( $Self, %Param ) = @_;

    return $Self->_MasterDataCreate(
        Table           => 'salutation',
        ExtraColumn     => 'content',
        ExtraValue      => $Param{Content},
        Name            => $Param{Name},
        SortOrder       => $Param{SortOrder},
        ChangedByUserID => $Param{ChangedByUserID},
    );
}

sub SalutationUpdate {
    my ( $Self, %Param ) = @_;

    return $Self->_MasterDataUpdate(
        Table           => 'salutation',
        ExtraColumn     => 'content',
        ExtraValue      => $Param{Content},
        ID              => $Param{SalutationID},
        Name            => $Param{Name},
        Active          => $Param{Active},
        SortOrder       => $Param{SortOrder},
        ChangedByUserID => $Param{ChangedByUserID},
    );
}

sub SalutationDeactivate {
    my ( $Self, %Param ) = @_;

    return $Self->_MasterDataDeactivate(
        Table           => 'salutation',
        ID              => $Param{SalutationID},
        ChangedByUserID => $Param{ChangedByUserID},
    );
}

sub SignatureGet {
    my ( $Self, %Param ) = @_;

    return $Self->_MasterDataGet(
        Table       => 'signature',
        ExtraSelect => 'content',
        ID          => $Param{SignatureID},
    );
}

sub SignatureCreate {
    my ( $Self, %Param ) = @_;

    return $Self->_MasterDataCreate(
        Table           => 'signature',
        ExtraColumn     => 'content',
        ExtraValue      => $Param{Content},
        Name            => $Param{Name},
        SortOrder       => $Param{SortOrder},
        ChangedByUserID => $Param{ChangedByUserID},
    );
}

sub SignatureUpdate {
    my ( $Self, %Param ) = @_;

    return $Self->_MasterDataUpdate(
        Table           => 'signature',
        ExtraColumn     => 'content',
        ExtraValue      => $Param{Content},
        ID              => $Param{SignatureID},
        Name            => $Param{Name},
        Active          => $Param{Active},
        SortOrder       => $Param{SortOrder},
        ChangedByUserID => $Param{ChangedByUserID},
    );
}

sub SignatureDeactivate {
    my ( $Self, %Param ) = @_;

    return $Self->_MasterDataDeactivate(
        Table           => 'signature',
        ID              => $Param{SignatureID},
        ChangedByUserID => $Param{ChangedByUserID},
    );
}

sub CalendarGet {
    my ( $Self, %Param ) = @_;

    return $Self->_MasterDataGet(
        Table       => 'calendar',
        ExtraSelect => 'timezone',
        ID          => $Param{CalendarID},
    );
}

sub CalendarCreate {
    my ( $Self, %Param ) = @_;

    my $Name      = $Self->_Trim( $Param{Name} );
    my $Timezone  = $Self->_Trim( $Param{Timezone} ) || 'Europe/Berlin';
    my $SortOrder = $Param{SortOrder} || 1000;
    my $UserID    = $Param{ChangedByUserID} || 1;

    if ( !$Name || !$Timezone ) {
        $Self->{LastError} = 'Name and timezone are required';
        return;
    }

    if ( $SortOrder !~ m{\A\d+\z} ) {
        $SortOrder = 1000;
    }

    my $Result = $Self->{DB}->Do(
        'INSERT INTO calendar (
            name,
            timezone,
            active,
            sort_order,
            created_by_user_id,
            changed_by_user_id
         ) VALUES (
            ?, ?, 1, ?, ?, ?
         )',
        $Name,
        $Timezone,
        $SortOrder,
        $UserID,
        $UserID,
    );

    if ( !$Result ) {
        $Self->{LastError} = $Self->{DB}->Error() || 'Calendar could not be created';
        return;
    }

    return $Self->{DB}->LastInsertID('calendar') || 1;
}

sub CalendarUpdate {
    my ( $Self, %Param ) = @_;

    return $Self->_MasterDataUpdate(
        Table           => 'calendar',
        ExtraColumn     => 'timezone',
        ExtraValue      => $Param{Timezone},
        ID              => $Param{CalendarID},
        Name            => $Param{Name},
        Active          => $Param{Active},
        SortOrder       => $Param{SortOrder},
        ChangedByUserID => $Param{ChangedByUserID},
    );
}

sub CalendarDeactivate {
    my ( $Self, %Param ) = @_;

    return $Self->_MasterDataDeactivate(
        Table           => 'calendar',
        ID              => $Param{CalendarID},
        ChangedByUserID => $Param{ChangedByUserID},
    );
}



sub PostmasterIMAPAccountList {
    my ($Self) = @_;

    $Self->_MailIntegrationSchemaEnsure() || return [];

    my $Rows = $Self->{DB}->SelectAll(
        'SELECT
            pia.*,
            tq.full_name AS queue_name
         FROM postmaster_imap_account pia
         LEFT JOIN ticket_queue tq
            ON tq.id = pia.queue_id
         ORDER BY pia.sort_order ASC, pia.name ASC'
    );

    return $Self->_RowsPrepare( Rows => $Rows );
}

sub PostmasterIMAPAccountInboundList {
    my ($Self) = @_;

    $Self->_MailIntegrationSchemaEnsure() || return [];

    my $Rows = $Self->{DB}->SelectAll(
        'SELECT
            pia.*,
            tq.full_name AS queue_name
         FROM postmaster_imap_account pia
         LEFT JOIN ticket_queue tq
            ON tq.id = pia.queue_id
         WHERE pia.active = 1
         ORDER BY pia.sort_order ASC, pia.name ASC'
    );

    return $Self->_RowsPrepare( Rows => $Rows );
}

sub PostmasterIMAPAccountGet {
    my ( $Self, %Param ) = @_;

    $Self->_MailIntegrationSchemaEnsure() || return;

    my $AccountID = $Param{AccountID} || 0;

    return if $AccountID !~ m{\A\d+\z} || !$AccountID;

    my $Account = $Self->{DB}->SelectRow(
        'SELECT
            pia.*,
            tq.full_name AS queue_name
         FROM postmaster_imap_account pia
         LEFT JOIN ticket_queue tq
            ON tq.id = pia.queue_id
         WHERE pia.id = ?
         LIMIT 1',
        $AccountID,
    );

    if ( !$Account ) {
        $Self->{LastError} = 'Postmaster IMAP account was not found';
        return;
    }

    return $Self->_RowsPrepare( Rows => [$Account] )->[0];
}

sub PostmasterIMAPAccountCreate {
    my ( $Self, %Param ) = @_;

    $Self->_MailIntegrationSchemaEnsure() || return;

    my $Prepared = $Self->_IMAPAccountPrepare(%Param);
    return if !$Prepared;

    my $UserID  = $Param{ChangedByUserID} || 1;
    my $OAuth2  = $Prepared->{IMAPAuthType} eq 'oauth2' ? 1 : 0;
    my $Active  = $OAuth2 ? 0 : ( $Param{Active} ? 1 : 0 );
    my $TestResult;

    if ($OAuth2) {
        if ( !$Prepared->{OAuthClientSecret} ) {
            $Self->{LastError} = 'Translate:AdminOAuthClientSecretRequired';
            return;
        }
        $TestResult = {
            Success => 1,
            Status  => 'pending',
            Message => 'Translate:AdminOAuthAuthorizationPending',
        };
    }
    else {
        my $TestAccount = $Self->_IMAPAccountFromPrepared(
            Prepared => $Prepared,
            Active   => $Active,
        );
        $TestResult = QisutuMail->new( Config => $Self->{Config}, DB => $Self->{DB} )->IMAPTest(
            Account => $TestAccount,
        );

        if ( !$TestResult || !$TestResult->{Success} ) {
            $Self->{LastError} = $TestResult ? $TestResult->{Message} : 'IMAP connection test failed';
            return;
        }
    }

    my $EncryptedIMAPPassword = $Self->_SecretEncrypt( $Prepared->{IMAPPassword} );
    return if $Self->{LastError};
    my $EncryptedOAuthClientSecret = $Self->_SecretEncrypt( $Prepared->{OAuthClientSecret} );
    return if $Self->{LastError};

    my $Result = $Self->{DB}->Do(
        'INSERT INTO postmaster_imap_account (
            name,
            email,
            queue_id,
            imap_host,
            imap_security,
            imap_port,
            imap_auth_type,
            imap_username,
            imap_password,
            oauth_provider,
            oauth_client_id,
            oauth_client_secret,
            oauth_tenant_id,
            oauth_scope,
            active,
            sort_order,
            last_check_at,
            last_check_status,
            last_check_message,
            created_by_user_id,
            changed_by_user_id
         ) VALUES (
            ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, NOW(), ?, ?, ?, ?
         )',
        $Prepared->{Name},
        $Prepared->{Email},
        $Prepared->{QueueID},
        $Prepared->{IMAPHost},
        $Prepared->{IMAPSecurity},
        $Prepared->{IMAPPort},
        $Prepared->{IMAPAuthType},
        $Prepared->{IMAPUsername},
        $EncryptedIMAPPassword,
        $Prepared->{OAuthProvider},
        $Prepared->{OAuthClientID},
        $EncryptedOAuthClientSecret,
        $Prepared->{OAuthTenantID},
        $Prepared->{OAuthScope},
        $Active,
        $Prepared->{SortOrder},
        $TestResult->{Status},
        $TestResult->{Message},
        $UserID,
        $UserID,
    );

    if ( !$Result ) {
        $Self->{LastError} = $Self->{DB}->Error() || 'Postmaster IMAP account could not be created';
        return;
    }

    return $Self->{DB}->LastInsertID('postmaster_imap_account') || 1;
}

sub PostmasterIMAPAccountUpdate {
    my ( $Self, %Param ) = @_;

    $Self->_MailIntegrationSchemaEnsure() || return;

    my $AccountID = $Param{AccountID} || 0;

    if ( $AccountID !~ m{\A\d+\z} || !$AccountID ) {
        $Self->{LastError} = 'Postmaster IMAP account is required';
        return;
    }

    my $Prepared = $Self->_IMAPAccountPrepare(%Param);
    return if !$Prepared;

    my $UserID = $Param{ChangedByUserID} || 1;
    my $OAuth2 = $Prepared->{IMAPAuthType} eq 'oauth2' ? 1 : 0;
    my $Active = $OAuth2 ? 0 : ( $Param{Active} ? 1 : 0 );
    my $Existing = $Self->PostmasterIMAPAccountGet( AccountID => $AccountID );
    return if !$Existing;
    my $TestResult;

    if ($OAuth2) {
        if ( !$Prepared->{OAuthClientSecret} && !$Existing->{oauth_client_secret} ) {
            $Self->{LastError} = 'Translate:AdminOAuthClientSecretRequired';
            return;
        }
        $TestResult = {
            Success => 1,
            Status  => 'pending',
            Message => 'Translate:AdminOAuthAuthorizationPending',
        };
    }
    else {
        my $TestAccount = $Self->_IMAPAccountFromPrepared(
            Prepared => $Prepared,
            Existing => $Existing,
            Active   => $Active,
        );
        $TestResult = QisutuMail->new( Config => $Self->{Config}, DB => $Self->{DB} )->IMAPTest(
            Account => $TestAccount,
        );

        if ( !$TestResult || !$TestResult->{Success} ) {
            $Self->{LastError} = $TestResult ? $TestResult->{Message} : 'IMAP connection test failed';
            return;
        }
    }

    my @Set = (
        'name = ?',
        'email = ?',
        'queue_id = ?',
        'imap_host = ?',
        'imap_security = ?',
        'imap_port = ?',
        'imap_auth_type = ?',
        'imap_username = ?',
        'oauth_provider = ?',
        'oauth_client_id = ?',
        'oauth_tenant_id = ?',
        'oauth_scope = ?',
        'active = ?',
        'sort_order = ?',
        'last_check_at = NOW()',
        'last_check_status = ?',
        'last_check_message = ?',
        'changed_by_user_id = ?',
    );

    my @Bind = (
        $Prepared->{Name},
        $Prepared->{Email},
        $Prepared->{QueueID},
        $Prepared->{IMAPHost},
        $Prepared->{IMAPSecurity},
        $Prepared->{IMAPPort},
        $Prepared->{IMAPAuthType},
        $Prepared->{IMAPUsername},
        $Prepared->{OAuthProvider},
        $Prepared->{OAuthClientID},
        $Prepared->{OAuthTenantID},
        $Prepared->{OAuthScope},
        $Active,
        $Prepared->{SortOrder},
        $TestResult->{Status},
        $TestResult->{Message},
        $UserID,
    );

    if ( $Prepared->{IMAPPassword} ne '' ) {
        my $Encrypted = $Self->_SecretEncrypt( $Prepared->{IMAPPassword} );
        return if $Self->{LastError};
        push @Set, 'imap_password = ?';
        push @Bind, $Encrypted;
    }

    if ( $Prepared->{OAuthClientSecret} ne '' ) {
        my $Encrypted = $Self->_SecretEncrypt( $Prepared->{OAuthClientSecret} );
        return if $Self->{LastError};
        push @Set, 'oauth_client_secret = ?';
        push @Bind, $Encrypted;
    }

    if ( !$OAuth2 ) {
        push @Set,
            'oauth_access_token = NULL',
            'oauth_refresh_token = NULL',
            'oauth_token_expires_at = NULL';
    }

    push @Bind, $AccountID;

    my $Result = $Self->{DB}->Do(
        'UPDATE postmaster_imap_account
         SET ' . join( ', ', @Set ) . '
         WHERE id = ?',
        @Bind,
    );

    if ( !$Result ) {
        $Self->{LastError} = $Self->{DB}->Error() || 'Postmaster IMAP account could not be updated';
        return;
    }

    return $AccountID;
}

sub PostmasterIMAPAccountActiveSet {
    my ( $Self, %Param ) = @_;

    my $AccountID = $Param{AccountID} || 0;
    my $UserID    = $Param{ChangedByUserID} || 1;
    my $Active    = $Param{Active} ? 1 : 0;

    if ( $AccountID !~ m{\A\d+\z} || !$AccountID ) {
        $Self->{LastError} = 'Postmaster IMAP account is required';
        return;
    }

    my $Result = $Self->{DB}->Do(
        'UPDATE postmaster_imap_account
         SET active = ?,
             changed_by_user_id = ?
         WHERE id = ?',
        $Active,
        $UserID,
        $AccountID,
    );

    if ( !$Result ) {
        $Self->{LastError} = $Self->{DB}->Error() || 'Postmaster IMAP account could not be activated';
        return;
    }

    return 1;
}

sub PostmasterIMAPAccountDeactivate {
    my ( $Self, %Param ) = @_;

    $Self->_MailIntegrationSchemaEnsure() || return;

    my $AccountID = $Param{AccountID} || 0;
    my $UserID    = $Param{ChangedByUserID} || 1;

    return if $AccountID !~ m{\A\d+\z} || !$AccountID;

    my $Result = $Self->{DB}->Do(
        'UPDATE postmaster_imap_account
         SET active = 0,
             changed_by_user_id = ?
         WHERE id = ?',
        $UserID,
        $AccountID,
    );

    if ( !$Result ) {
        $Self->{LastError} = $Self->{DB}->Error() || 'Postmaster IMAP account could not be deactivated';
        return;
    }

    return 1;
}

sub PostmasterIMAPAccountActivate {
    my ( $Self, %Param ) = @_;

    $Self->_MailIntegrationSchemaEnsure() || return;

    my $AccountID = $Param{AccountID} || 0;
    my $UserID    = $Param{ChangedByUserID} || 1;

    if ( $AccountID !~ m{\A\d+\z} || !$AccountID ) {
        $Self->{LastError} = 'Translate:AdminMailAccountMissing';
        return;
    }

    my $Account = $Self->PostmasterIMAPAccountGet( AccountID => $AccountID );
    return if !$Account;

    return 1 if $Account->{active};

    my $TestResult = $Self->PostmasterIMAPAccountTest(
        AccountID       => $AccountID,
        ChangedByUserID => $UserID,
    );

    if ( !$TestResult || !$TestResult->{Success} ) {
        $Self->{LastError} = $TestResult
            ? ( $TestResult->{Message} || 'Translate:AdminMailAccountActivationFailed' )
            : ( $Self->{LastError} || 'Translate:AdminMailAccountActivationFailed' );
        return;
    }

    return $Self->PostmasterIMAPAccountActiveSet(
        AccountID       => $AccountID,
        Active          => 1,
        ChangedByUserID => $UserID,
    );
}

sub PostmasterIMAPAccountDelete {
    my ( $Self, %Param ) = @_;

    $Self->_MailIntegrationSchemaEnsure() || return;

    my $AccountID = $Param{AccountID} || 0;

    if ( $AccountID !~ m{\A\d+\z} || !$AccountID ) {
        $Self->{LastError} = 'Translate:AdminMailAccountMissing';
        return;
    }

    if ( !$Self->{DB}->BeginWork() ) {
        $Self->{LastError} = $Self->{DB}->Error() || 'Translate:AdminMailAccountDeleteFailed';
        return;
    }

    my $Account = $Self->{DB}->SelectRow(
        'SELECT id, active
         FROM postmaster_imap_account
         WHERE id = ?
         LIMIT 1
         FOR UPDATE',
        $AccountID,
    );

    if ( !$Account ) {
        $Self->{DB}->Rollback();
        $Self->{LastError} = 'Translate:AdminMailAccountMissing';
        return;
    }

    if ( $Account->{active} ) {
        $Self->{DB}->Rollback();
        $Self->{LastError} = 'Translate:AdminMailAccountDeleteActiveBlocked';
        return;
    }

    my $LogsDetached = $Self->{DB}->Do(
        'UPDATE postmaster_filter_run
         SET imap_account_id = NULL
         WHERE imap_account_id = ?',
        $AccountID,
    );
    if ( !$LogsDetached ) {
        $Self->{DB}->Rollback();
        $Self->{LastError} = $Self->{DB}->Error() || 'Translate:AdminMailAccountDeleteFailed';
        return;
    }

    my $OAuthStateDeleted = $Self->{DB}->Do(
        'DELETE FROM oauth2_authorization_state
         WHERE account_type = ? AND account_id = ?',
        'imap',
        $AccountID,
    );
    if ( !$OAuthStateDeleted ) {
        $Self->{DB}->Rollback();
        $Self->{LastError} = $Self->{DB}->Error() || 'Translate:AdminMailAccountDeleteFailed';
        return;
    }

    my $Deleted = $Self->{DB}->Do(
        'DELETE FROM postmaster_imap_account
         WHERE id = ?',
        $AccountID,
    );
    if ( !$Deleted ) {
        $Self->{DB}->Rollback();
        $Self->{LastError} = $Self->{DB}->Error() || 'Translate:AdminMailAccountDeleteFailed';
        return;
    }

    if ( !$Self->{DB}->Commit() ) {
        $Self->{DB}->Rollback();
        $Self->{LastError} = $Self->{DB}->Error() || 'Translate:AdminMailAccountDeleteFailed';
        return;
    }

    return 1;
}

sub PostmasterIMAPAccountTest {
    my ( $Self, %Param ) = @_;

    my $AccountID = $Param{AccountID} || 0;
    my $UserID    = $Param{ChangedByUserID} || 1;

    if ( $AccountID !~ m{\A\d+\z} || !$AccountID ) {
        $Self->{LastError} = 'Postmaster IMAP account is required';
        return;
    }

    my $Account = $Self->PostmasterIMAPAccountGet( AccountID => $AccountID );
    return if !$Account;

    my $Result = QisutuMail->new( Config => $Self->{Config}, DB => $Self->{DB} )->IMAPTest(
        Account => $Account,
    );

    $Self->{DB}->Do(
        'UPDATE postmaster_imap_account
         SET last_check_at = NOW(),
             last_check_status = ?,
             last_check_message = ?,
             changed_by_user_id = ?
         WHERE id = ?',
        $Result->{Status},
        $Result->{Message},
        $UserID,
        $AccountID,
    );

    return $Result;
}

sub SMTPAccountList {
    my ($Self) = @_;

    $Self->_MailIntegrationSchemaEnsure() || return [];

    my $Rows = $Self->{DB}->SelectAll(
        'SELECT *
         FROM smtp_account
         ORDER BY active DESC, sort_order ASC, name ASC'
    );

    return $Self->_RowsPrepare( Rows => $Rows );
}

sub SMTPAccountGet {
    my ( $Self, %Param ) = @_;

    $Self->_MailIntegrationSchemaEnsure() || return;

    my $AccountID = $Param{AccountID} || 0;

    return if $AccountID !~ m{\A\d+\z} || !$AccountID;

    my $Account = $Self->{DB}->SelectRow(
        'SELECT *
         FROM smtp_account
         WHERE id = ?
         LIMIT 1',
        $AccountID,
    );

    if ( !$Account ) {
        $Self->{LastError} = 'SMTP account was not found';
        return;
    }

    return $Self->_RowsPrepare( Rows => [$Account] )->[0];
}

sub SMTPAccountCreate {
    my ( $Self, %Param ) = @_;

    $Self->_MailIntegrationSchemaEnsure() || return;

    my $Prepared = $Self->_SMTPAccountPrepare(%Param);
    return if !$Prepared;

    my $UserID = $Param{ChangedByUserID} || 1;
    my $OAuth2 = $Prepared->{SMTPAuthType} eq 'oauth2' ? 1 : 0;
    my $Active = $OAuth2 ? 0 : ( $Param{Active} ? 1 : 0 );
    my $TestResult;
    if ($OAuth2) {
        if ( !$Prepared->{OAuthClientSecret} ) {
            $Self->{LastError} = 'Translate:AdminOAuthClientSecretRequired';
            return;
        }
        $TestResult = {
            Success => 1,
            Status  => 'pending',
            Message => 'Translate:AdminOAuthAuthorizationPending',
        };
    }
    else {
        my $TestAccount = $Self->_SMTPAccountFromPrepared(
            Prepared => $Prepared,
            Active   => $Active,
        );
        $TestResult = QisutuMail->new( Config => $Self->{Config}, DB => $Self->{DB} )->SMTPTest(
            Account => $TestAccount,
        );
        if ( !$TestResult || !$TestResult->{Success} ) {
            $Self->{LastError} = $TestResult ? $TestResult->{Message} : 'SMTP connection test failed';
            return;
        }
    }

    if ($Active) {
        $Self->{DB}->Do(
            'UPDATE smtp_account SET active = 0 WHERE active = 1'
        );
    }

    my $EncryptedSMTPPassword = $Self->_SecretEncrypt( $Prepared->{SMTPPassword} );
    return if $Self->{LastError};
    my $EncryptedOAuthClientSecret = $Self->_SecretEncrypt( $Prepared->{OAuthClientSecret} );
    return if $Self->{LastError};

    my $Result = $Self->{DB}->Do(
        'INSERT INTO smtp_account (
            name,
            smtp_host,
            smtp_security,
            smtp_port,
            smtp_auth_type,
            smtp_username,
            smtp_password,
            oauth_provider,
            oauth_client_id,
            oauth_client_secret,
            oauth_tenant_id,
            oauth_scope,
            active,
            sort_order,
            last_check_at,
            last_check_status,
            last_check_message,
            created_by_user_id,
            changed_by_user_id
         ) VALUES (
            ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, NOW(), ?, ?, ?, ?
         )',
        $Prepared->{Name},
        $Prepared->{SMTPHost},
        $Prepared->{SMTPSecurity},
        $Prepared->{SMTPPort},
        $Prepared->{SMTPAuthType},
        $Prepared->{SMTPUsername},
        $EncryptedSMTPPassword,
        $Prepared->{OAuthProvider},
        $Prepared->{OAuthClientID},
        $EncryptedOAuthClientSecret,
        $Prepared->{OAuthTenantID},
        $Prepared->{OAuthScope},
        $Active,
        $Prepared->{SortOrder},
        $TestResult->{Status},
        $TestResult->{Message},
        $UserID,
        $UserID,
    );

    if ( !$Result ) {
        $Self->{LastError} = $Self->{DB}->Error() || 'SMTP account could not be created';
        return;
    }

    return $Self->{DB}->LastInsertID('smtp_account') || 1;
}

sub SMTPAccountUpdate {
    my ( $Self, %Param ) = @_;

    $Self->_MailIntegrationSchemaEnsure() || return;

    my $AccountID = $Param{AccountID} || 0;

    if ( $AccountID !~ m{\A\d+\z} || !$AccountID ) {
        $Self->{LastError} = 'SMTP account is required';
        return;
    }

    my $Prepared = $Self->_SMTPAccountPrepare(%Param);
    return if !$Prepared;

    my $UserID = $Param{ChangedByUserID} || 1;
    my $OAuth2 = $Prepared->{SMTPAuthType} eq 'oauth2' ? 1 : 0;
    my $Active = $OAuth2 ? 0 : ( $Param{Active} ? 1 : 0 );
    my $Existing = $Self->SMTPAccountGet( AccountID => $AccountID );
    return if !$Existing;
    my $TestResult;
    if ($OAuth2) {
        if ( !$Prepared->{OAuthClientSecret} && !$Existing->{oauth_client_secret} ) {
            $Self->{LastError} = 'Translate:AdminOAuthClientSecretRequired';
            return;
        }
        $TestResult = {
            Success => 1,
            Status  => 'pending',
            Message => 'Translate:AdminOAuthAuthorizationPending',
        };
    }
    else {
        my $TestAccount = $Self->_SMTPAccountFromPrepared(
            Prepared => $Prepared,
            Existing => $Existing,
            Active   => $Active,
        );
        $TestResult = QisutuMail->new( Config => $Self->{Config}, DB => $Self->{DB} )->SMTPTest(
            Account => $TestAccount,
        );
        if ( !$TestResult || !$TestResult->{Success} ) {
            $Self->{LastError} = $TestResult ? $TestResult->{Message} : 'SMTP connection test failed';
            return;
        }
    }

    if ($Active) {
        $Self->{DB}->Do(
            'UPDATE smtp_account SET active = 0 WHERE id <> ?',
            $AccountID,
        );
    }

    my @Set = (
        'name = ?',
        'smtp_host = ?',
        'smtp_security = ?',
        'smtp_port = ?',
        'smtp_auth_type = ?',
        'smtp_username = ?',
        'oauth_provider = ?',
        'oauth_client_id = ?',
        'oauth_tenant_id = ?',
        'oauth_scope = ?',
        'active = ?',
        'sort_order = ?',
        'last_check_at = NOW()',
        'last_check_status = ?',
        'last_check_message = ?',
        'changed_by_user_id = ?',
    );

    my @Bind = (
        $Prepared->{Name},
        $Prepared->{SMTPHost},
        $Prepared->{SMTPSecurity},
        $Prepared->{SMTPPort},
        $Prepared->{SMTPAuthType},
        $Prepared->{SMTPUsername},
        $Prepared->{OAuthProvider},
        $Prepared->{OAuthClientID},
        $Prepared->{OAuthTenantID},
        $Prepared->{OAuthScope},
        $Active,
        $Prepared->{SortOrder},
        $TestResult->{Status},
        $TestResult->{Message},
        $UserID,
    );

    if ( $Prepared->{SMTPPassword} ne '' ) {
        my $Encrypted = $Self->_SecretEncrypt( $Prepared->{SMTPPassword} );
        return if $Self->{LastError};
        push @Set, 'smtp_password = ?';
        push @Bind, $Encrypted;
    }

    if ( $Prepared->{OAuthClientSecret} ne '' ) {
        my $Encrypted = $Self->_SecretEncrypt( $Prepared->{OAuthClientSecret} );
        return if $Self->{LastError};
        push @Set, 'oauth_client_secret = ?';
        push @Bind, $Encrypted;
    }

    if ( !$OAuth2 ) {
        push @Set,
            'oauth_client_secret = NULL',
            'oauth_access_token = NULL',
            'oauth_refresh_token = NULL',
            'oauth_token_expires_at = NULL';
    }
    else {
        push @Set, 'smtp_password = NULL';
    }

    push @Bind, $AccountID;

    my $Result = $Self->{DB}->Do(
        'UPDATE smtp_account
         SET ' . join( ', ', @Set ) . '
         WHERE id = ?',
        @Bind,
    );

    if ( !$Result ) {
        $Self->{LastError} = $Self->{DB}->Error() || 'SMTP account could not be updated';
        return;
    }

    return $AccountID;
}

sub SMTPAccountActiveSet {
    my ( $Self, %Param ) = @_;

    my $AccountID = $Param{AccountID} || 0;
    my $UserID    = $Param{ChangedByUserID} || 1;
    my $Active    = $Param{Active} ? 1 : 0;
    if ( !$AccountID || $AccountID !~ m{\A\d+\z} ) {
        $Self->{LastError} = 'SMTP account is required';
        return;
    }
    if ($Active) {
        $Self->{DB}->Do( 'UPDATE smtp_account SET active = 0 WHERE id <> ?', $AccountID );
    }
    my $Result = $Self->{DB}->Do(
        'UPDATE smtp_account SET active = ?, changed_by_user_id = ? WHERE id = ?',
        $Active,
        $UserID,
        $AccountID,
    );
    if ( !$Result ) {
        $Self->{LastError} = $Self->{DB}->Error() || 'SMTP account could not be activated';
        return;
    }
    return 1;
}

sub SMTPAccountDeactivate {
    my ( $Self, %Param ) = @_;

    $Self->_MailIntegrationSchemaEnsure() || return;

    my $AccountID = $Param{AccountID} || 0;
    my $UserID    = $Param{ChangedByUserID} || 1;

    return if $AccountID !~ m{\A\d+\z} || !$AccountID;

    my $Result = $Self->{DB}->Do(
        'UPDATE smtp_account
         SET active = 0,
             changed_by_user_id = ?
         WHERE id = ?',
        $UserID,
        $AccountID,
    );

    if ( !$Result ) {
        $Self->{LastError} = $Self->{DB}->Error() || 'SMTP account could not be deactivated';
        return;
    }

    return 1;
}

sub SMTPAccountTest {
    my ( $Self, %Param ) = @_;

    my $AccountID = $Param{AccountID} || 0;
    my $UserID    = $Param{ChangedByUserID} || 1;

    if ( $AccountID !~ m{\A\d+\z} || !$AccountID ) {
        $Self->{LastError} = 'SMTP account is required';
        return;
    }

    my $Account = $Self->SMTPAccountGet( AccountID => $AccountID );
    return if !$Account;

    my $Result = QisutuMail->new( Config => $Self->{Config}, DB => $Self->{DB} )->SMTPTest(
        Account => $Account,
    );

    $Self->{DB}->Do(
        'UPDATE smtp_account
         SET last_check_at = NOW(),
             last_check_status = ?,
             last_check_message = ?,
             changed_by_user_id = ?
         WHERE id = ?',
        $Result->{Status},
        $Result->{Message},
        $UserID,
        $AccountID,
    );

    return $Result;
}

sub GroupList {
    my ($Self) = @_;

    my $Rows = $Self->{DB}->SelectAll(
        'SELECT
            ug.id,
            ug.name,
            ug.title,
            ug.group_type,
            ug.active,
            ug.sort_order,
            COUNT(DISTINCT ugm.user_account_id) AS member_count
         FROM user_group ug
         LEFT JOIN user_group_member ugm
            ON ugm.user_group_id = ug.id
            AND ugm.active = 1
         GROUP BY ug.id, ug.name, ug.title, ug.group_type, ug.active, ug.sort_order
         ORDER BY ug.sort_order ASC, ug.name ASC'
    );

    return $Self->_RowsPrepare( Rows => $Rows );
}

sub GroupGet {
    my ( $Self, %Param ) = @_;

    my $GroupID = $Param{GroupID} || 0;

    return if $GroupID !~ m{\A\d+\z} || !$GroupID;

    my $Group = $Self->{DB}->SelectRow(
        'SELECT
            id,
            name,
            title,
            group_type,
            active,
            sort_order
         FROM user_group
         WHERE id = ?
         LIMIT 1',
        $GroupID,
    );

    if ( !$Group ) {
        $Self->{LastError} = 'Group was not found';
        return;
    }

    return $Self->_RowsPrepare( Rows => [$Group] )->[0];
}

sub AgentCreate {
    my ( $Self, %Param ) = @_;

    my $Login     = $Self->_Trim( $Param{Login} );
    my $Email     = $Self->_Trim( $Param{Email} );
    my $Password  = $Param{Password} || '';
    my $Firstname = $Self->_Trim( $Param{Firstname} );
    my $Lastname  = $Self->_Trim( $Param{Lastname} );
    my $UserID    = $Param{ChangedByUserID} || 1;

    if ( !$Login || !$Email || !$Password ) {
        $Self->{LastError} = 'Login, email and password are required';
        return;
    }

    return if !$Self->_UserAccountDuplicateCheck(
        AccountType => 'agent',
        Login       => $Login,
        Email       => $Email,
    );

    return if !$Self->AgentDynamicFieldValueValidate(
        Request => $Param{Request} || {},
    );

    my $PasswordHash = $Self->_PasswordHash( Password => $Password );

    my $Result = $Self->{DB}->Do(
        'INSERT INTO user_account (
            login,
            account_type,
            email,
            password_hash,
            firstname,
            lastname,
            is_active,
            is_system_user,
            password_changed_at
         ) VALUES (
            ?, "agent", ?, ?, ?, ?, 1, 0, NOW()
         )',
        $Login,
        $Email,
        $PasswordHash,
        $Firstname,
        $Lastname,
    );

    if ( !$Result ) {
        return if $Self->_UserAccountDuplicateErrorFromDB(
            AccountType => 'agent',
            Login       => $Login,
            Email       => $Email,
        );

        $Self->{LastError} = $Self->{DB}->Error() || 'Agent could not be created';
        return;
    }

    my $NewUserID = $Self->{DB}->LastInsertID('user_account');

    $Self->AgentDynamicFieldValueSave(
        UserAccountID   => $NewUserID,
        Request         => $Param{Request} || {},
        ChangedByUserID => $UserID,
    );

    return 1;
}

sub AgentUpdate {
    my ( $Self, %Param ) = @_;

    my $UserAccountID = $Param{UserAccountID} || 0;
    my $Login         = $Self->_Trim( $Param{Login} );
    my $Email         = $Self->_Trim( $Param{Email} );
    my $Firstname     = $Self->_Trim( $Param{Firstname} );
    my $Lastname      = $Self->_Trim( $Param{Lastname} );
    my $Password      = $Param{Password} || '';
    my $IsActive      = $Param{IsActive} ? 1 : 0;
    my $UserID        = $Param{ChangedByUserID} || 1;

    if ( $UserAccountID !~ m{\A\d+\z} || !$UserAccountID || !$Login || !$Email ) {
        $Self->{LastError} = 'Agent, login and email are required';
        return;
    }

    return if !$Self->_UserAccountDuplicateCheck(
        AccountType   => 'agent',
        UserAccountID => $UserAccountID,
        Login         => $Login,
        Email         => $Email,
    );

    return if !$Self->AgentDynamicFieldValueValidate(
        Request => $Param{Request} || {},
    );

    my $Result;

    if ($Password) {
        my $PasswordHash = $Self->_PasswordHash( Password => $Password );

        $Result = $Self->{DB}->Do(
            'UPDATE user_account
             SET login = ?,
                 email = ?,
                 firstname = ?,
                 lastname = ?,
                 password_hash = ?,
                 password_changed_at = NOW(),
                 is_active = ?
             WHERE id = ?',
            $Login,
            $Email,
            $Firstname,
            $Lastname,
            $PasswordHash,
            $IsActive,
            $UserAccountID,
        );
    }
    else {
        $Result = $Self->{DB}->Do(
            'UPDATE user_account
             SET login = ?,
                 email = ?,
                 firstname = ?,
                 lastname = ?,
                 is_active = ?
             WHERE id = ?',
            $Login,
            $Email,
            $Firstname,
            $Lastname,
            $IsActive,
            $UserAccountID,
        );
    }

    if ( !$Result ) {
        return if $Self->_UserAccountDuplicateErrorFromDB(
            AccountType => 'agent',
            Login       => $Login,
            Email       => $Email,
        );

        $Self->{LastError} = $Self->{DB}->Error() || 'Agent could not be updated';
        return;
    }

    $Self->AgentDynamicFieldValueSave(
        UserAccountID   => $UserAccountID,
        Request         => $Param{Request} || {},
        ChangedByUserID => $UserID,
    );

    return 1;
}

sub AgentDeactivate {
    my ( $Self, %Param ) = @_;

    my $UserAccountID = $Param{UserAccountID} || 0;

    return if $UserAccountID !~ m{\A\d+\z} || !$UserAccountID;

    my $Result = $Self->{DB}->Do(
        'UPDATE user_account
         SET is_active = 0
         WHERE id = ?',
        $UserAccountID,
    );

    if ( !$Result ) {
        $Self->{LastError} = $Self->{DB}->Error() || 'Agent could not be deactivated';
        return;
    }

    return 1;
}

sub UserGroupAdd {
    my ( $Self, %Param ) = @_;

    my $UserAccountID = $Param{UserAccountID} || 0;
    my $GroupID       = $Param{GroupID} || 0;
    my $UserID        = $Param{ChangedByUserID} || 1;
    my $Read          = $Param{PermissionRead} ? 1 : 0;
    my $Create        = $Param{PermissionCreate} ? 1 : 0;
    my $Change        = $Param{PermissionChange} ? 1 : 0;
    my $Overview      = $Param{PermissionOverview} ? 1 : 0;
    my $Full          = $Param{PermissionFull} ? 1 : 0;

    return if $UserAccountID !~ m{\A\d+\z} || !$UserAccountID;
    return if $GroupID !~ m{\A\d+\z} || !$GroupID;

    my $Group = $Self->_GroupGet( GroupID => $GroupID );
    return if !$Group;

    my $Result = $Self->{DB}->Do(
        'INSERT INTO user_group_member (
            user_group_id,
            user_account_id,
            role_name,
            permission_read,
            permission_create,
            permission_change,
            permission_overview,
            permission_full,
            active,
            created_by_user_id,
            changed_by_user_id
         ) VALUES (
            ?, ?, "member", ?, ?, ?, ?, ?, 1, ?, ?
         )
         ON DUPLICATE KEY UPDATE
            active = 1,
            permission_read = VALUES(permission_read),
            permission_create = VALUES(permission_create),
            permission_change = VALUES(permission_change),
            permission_overview = VALUES(permission_overview),
            permission_full = VALUES(permission_full),
            changed_by_user_id = VALUES(changed_by_user_id),
            changed_at = CURRENT_TIMESTAMP',
        $Group->{id},
        $UserAccountID,
        $Read,
        $Create,
        $Change,
        $Overview,
        $Full,
        $UserID,
        $UserID,
    );

    if ( !$Result ) {
        $Self->{LastError} = $Self->{DB}->Error() || 'Group assignment could not be saved';
        return;
    }

    return 1;
}

sub UserGroupList {
    my ( $Self, %Param ) = @_;

    my $UserAccountID = $Param{UserAccountID} || 0;

    return [] if $UserAccountID !~ m{\A\d+\z} || !$UserAccountID;

    my $Rows = $Self->{DB}->SelectAll(
        'SELECT
            ugm.user_group_id,
            ug.name,
            ug.title,
            ug.group_type,
            ugm.permission_read,
            ugm.permission_create,
            ugm.permission_change,
            ugm.permission_overview,
            ugm.permission_full
         FROM user_group_member ugm
         INNER JOIN user_group ug
            ON ug.id = ugm.user_group_id
         WHERE ugm.user_account_id = ?
            AND ugm.active = 1
            AND ug.active = 1
         ORDER BY ug.sort_order ASC, ug.name ASC',
        $UserAccountID,
    );

    return $Self->_RowsPrepare( Rows => $Rows );
}

sub GroupAgentList {
    my ( $Self, %Param ) = @_;

    my $GroupID = $Param{GroupID} || 0;

    return [] if $GroupID !~ m{\A\d+\z} || !$GroupID;

    my $Rows = $Self->{DB}->SelectAll(
        'SELECT
            ugm.user_group_id,
            ugm.user_account_id,
            ua.login,
            ua.email,
            ua.firstname,
            ua.lastname,
            ugm.permission_read,
            ugm.permission_create,
            ugm.permission_change,
            ugm.permission_overview,
            ugm.permission_full
         FROM user_group_member ugm
         INNER JOIN user_account ua
            ON ua.id = ugm.user_account_id
         LEFT JOIN customer_user cu
            ON cu.user_account_id = ua.id
         WHERE ugm.user_group_id = ?
            AND ugm.active = 1
            AND ua.is_system_user = 0
            AND ua.account_type = "agent"
            AND cu.id IS NULL
         ORDER BY ua.login ASC',
        $GroupID,
    );

    return $Self->_RowsPrepare( Rows => $Rows );
}

sub UserGroupPermissionUpdate {
    my ( $Self, %Param ) = @_;

    my $UserAccountID = $Param{UserAccountID} || 0;
    my $GroupID       = $Param{GroupID} || 0;
    my $UserID        = $Param{ChangedByUserID} || 1;

    return if $UserAccountID !~ m{\A\d+\z} || !$UserAccountID;
    return if $GroupID !~ m{\A\d+\z} || !$GroupID;

    my $Result = $Self->{DB}->Do(
        'UPDATE user_group_member
         SET permission_read = ?,
             permission_create = ?,
             permission_change = ?,
             permission_overview = ?,
             permission_full = ?,
             changed_by_user_id = ?,
             changed_at = CURRENT_TIMESTAMP
         WHERE user_account_id = ?
            AND user_group_id = ?
            AND active = 1',
        $Param{PermissionRead} ? 1 : 0,
        $Param{PermissionCreate} ? 1 : 0,
        $Param{PermissionChange} ? 1 : 0,
        $Param{PermissionOverview} ? 1 : 0,
        $Param{PermissionFull} ? 1 : 0,
        $UserID,
        $UserAccountID,
        $GroupID,
    );

    if ( !$Result ) {
        $Self->{LastError} = $Self->{DB}->Error() || 'Group permissions could not be saved';
        return;
    }

    return 1;
}

sub UserGroupRemove {
    my ( $Self, %Param ) = @_;

    my $UserAccountID = $Param{UserAccountID} || 0;
    my $GroupID       = $Param{GroupID} || 0;
    my $UserID        = $Param{ChangedByUserID} || 1;

    return if $UserAccountID !~ m{\A\d+\z} || !$UserAccountID;
    return if $GroupID !~ m{\A\d+\z} || !$GroupID;

    my $Result = $Self->{DB}->Do(
        'UPDATE user_group_member
         SET active = 0,
             changed_by_user_id = ?,
             changed_at = CURRENT_TIMESTAMP
         WHERE user_account_id = ?
            AND user_group_id = ?',
        $UserID,
        $UserAccountID,
        $GroupID,
    );

    if ( !$Result ) {
        $Self->{LastError} = $Self->{DB}->Error() || 'Group assignment could not be removed';
        return;
    }

    return 1;
}

sub GroupPermissionList {
    my ($Self) = @_;

    my $Rows = $Self->{DB}->SelectAll(
        'SELECT
            ugp.user_group_id,
            ug.name AS group_name,
            ug.title AS group_title,
            ugp.permission_key
         FROM user_group_permission ugp
         INNER JOIN user_group ug
            ON ug.id = ugp.user_group_id
         WHERE ugp.active = 1
            AND ug.active = 1
         ORDER BY ug.sort_order ASC, ug.name ASC, ugp.permission_key ASC'
    );

    return $Self->_RowsPrepare( Rows => $Rows );
}

sub GroupPermissionRemove {
    my ( $Self, %Param ) = @_;

    my $GroupID    = $Param{GroupID} || 0;
    my $Permission = $Self->_Trim( $Param{Permission} );
    my $UserID     = $Param{ChangedByUserID} || 1;

    return if $GroupID !~ m{\A\d+\z} || !$GroupID;
    return if !$Permission;

    my $Result = $Self->{DB}->Do(
        'UPDATE user_group_permission
         SET active = 0,
             changed_by_user_id = ?,
             changed_at = CURRENT_TIMESTAMP
         WHERE user_group_id = ?
            AND permission_key = ?',
        $UserID,
        $GroupID,
        $Permission,
    );

    if ( !$Result ) {
        $Self->{LastError} = $Self->{DB}->Error() || 'Program permission could not be removed';
        return;
    }

    return 1;
}

sub QueuePermissionList {
    my ($Self) = @_;

    my $Rows = $Self->{DB}->SelectAll(
        'SELECT
            tqg.queue_id,
            tq.full_name AS queue_name,
            tqg.user_group_id,
            ug.name AS group_name,
            ug.title AS group_title,
            tqg.permission_key
         FROM ticket_queue_group tqg
         INNER JOIN ticket_queue tq
            ON tq.id = tqg.queue_id
         INNER JOIN user_group ug
            ON ug.id = tqg.user_group_id
         WHERE tqg.active = 1
            AND tq.active = 1
            AND ug.active = 1
         ORDER BY tq.full_name ASC, ug.sort_order ASC, ug.name ASC, tqg.permission_key ASC'
    );

    return $Self->_RowsPrepare( Rows => $Rows );
}

sub QueuePermissionAdd {
    my ( $Self, %Param ) = @_;

    my $QueueID    = $Param{QueueID} || 0;
    my $GroupID    = $Param{GroupID} || 0;
    my $Permission = $Self->_Trim( $Param{Permission} );
    my $UserID     = $Param{ChangedByUserID} || 1;

    return if $QueueID !~ m{\A\d+\z} || !$QueueID;
    return if $GroupID !~ m{\A\d+\z} || !$GroupID;
    return if !$Permission;

    my $Result = $Self->{DB}->Do(
        'INSERT INTO ticket_queue_group (
            queue_id,
            user_group_id,
            permission_key,
            active,
            created_by_user_id,
            changed_by_user_id
         ) VALUES (
            ?, ?, ?, 1, ?, ?
         )
         ON DUPLICATE KEY UPDATE
            active = 1,
            changed_by_user_id = VALUES(changed_by_user_id),
            changed_at = CURRENT_TIMESTAMP',
        $QueueID,
        $GroupID,
        $Permission,
        $UserID,
        $UserID,
    );

    if ( !$Result ) {
        $Self->{LastError} = $Self->{DB}->Error() || 'Queue permission could not be saved';
        return;
    }

    return 1;
}

sub QueuePermissionRemove {
    my ( $Self, %Param ) = @_;

    my $QueueID    = $Param{QueueID} || 0;
    my $GroupID    = $Param{GroupID} || 0;
    my $Permission = $Self->_Trim( $Param{Permission} );
    my $UserID     = $Param{ChangedByUserID} || 1;

    return if $QueueID !~ m{\A\d+\z} || !$QueueID;
    return if $GroupID !~ m{\A\d+\z} || !$GroupID;
    return if !$Permission;

    my $Result = $Self->{DB}->Do(
        'UPDATE ticket_queue_group
         SET active = 0,
             changed_by_user_id = ?,
             changed_at = CURRENT_TIMESTAMP
         WHERE queue_id = ?
            AND user_group_id = ?
            AND permission_key = ?',
        $UserID,
        $QueueID,
        $GroupID,
        $Permission,
    );

    if ( !$Result ) {
        $Self->{LastError} = $Self->{DB}->Error() || 'Queue permission could not be removed';
        return;
    }

    return 1;
}

sub AgentDynamicFieldList {
    my ( $Self, %Param ) = @_;

    my $Language        = $Self->_LanguageClean( $Param{Language} || $Self->{Config}->{Language}->{Default} || 'en' );
    my $DefaultLanguage = $Self->_LanguageClean( $Self->{Config}->{Language}->{Default} || 'en' );
    my $IncludeInactive = $Param{IncludeInactive} ? 1 : 0;
    my $WhereActive     = $IncludeInactive ? '' : 'AND f.active = 1';

    my $Rows = $Self->{DB}->SelectAll(
        'SELECT
            f.id,
            f.name,
            COALESCE(current_translation.label, default_translation.label, f.label, f.name) AS label,
            f.field_type,
            f.is_required,
            f.active,
            f.sort_order
         FROM user_dynamic_field f
         LEFT JOIN user_dynamic_field_translation current_translation
            ON current_translation.field_id = f.id
            AND current_translation.language = ?
         LEFT JOIN user_dynamic_field_translation default_translation
            ON default_translation.field_id = f.id
            AND default_translation.language = ?
         WHERE f.object_type = "agent"
            ' . $WhereActive . '
         ORDER BY f.sort_order ASC, label ASC, f.id ASC',
        $Language,
        $DefaultLanguage,
    );

    return $Self->_RowsPrepare( Rows => $Rows );
}

sub AgentDynamicFieldGet {
    my ( $Self, %Param ) = @_;

    my $FieldID = $Param{FieldID} || 0;

    return if $FieldID !~ m{\A\d+\z} || !$FieldID;

    my $Field = $Self->{DB}->SelectRow(
        'SELECT
            id,
            name,
            field_type,
            is_required,
            active,
            sort_order
         FROM user_dynamic_field
         WHERE id = ?
            AND object_type = "agent"
         LIMIT 1',
        $FieldID,
    );

    if ( !$Field ) {
        $Self->{LastError} = 'Field was not found';
        return;
    }

    return $Self->_RowsPrepare( Rows => [$Field] )->[0];
}

sub AgentDynamicFieldCreate {
    my ( $Self, %Param ) = @_;

    my $Name      = $Self->_Trim( $Param{Name} );
    my $FieldType = $Self->_Trim( $Param{FieldType} ) || 'text';
    my $Required  = $Param{IsRequired} ? 1 : 0;
    my $SortOrder = $Param{SortOrder} || 1000;
    my $UserID    = $Param{ChangedByUserID} || 1;
    my $Labels    = $Param{LabelByLanguage} || {};
    my $DefaultLabel = $Self->_FirstTranslationLabel( Labels => $Labels );

    if ( !$Name || !$DefaultLabel ) {
        $Self->{LastError} = 'Field name and label are required';
        return;
    }

    if ( $Name !~ m{\A[A-Za-z][A-Za-z0-9_]*\z} ) {
        $Self->{LastError} = 'Database field must use ASCII letters, numbers and underscores and must start with a letter';
        return;
    }

    if ( $FieldType !~ m{\A(?:text|textarea|email|phone|date|number)\z} ) {
        $FieldType = 'text';
    }

    if ( $SortOrder !~ m{\A\d+\z} ) {
        $SortOrder = 1000;
    }

    my $Result = $Self->{DB}->Do(
        'INSERT INTO user_dynamic_field (
            object_type,
            name,
            label,
            field_type,
            is_required,
            active,
            sort_order,
            created_by_user_id,
            changed_by_user_id
         ) VALUES (
            "agent", ?, ?, ?, ?, 1, ?, ?, ?
         )',
        $Name,
        $DefaultLabel,
        $FieldType,
        $Required,
        $SortOrder,
        $UserID,
        $UserID,
    );

    if ( !$Result ) {
        $Self->{LastError} = $Self->{DB}->Error() || 'Field could not be created';
        return;
    }

    my $FieldID = $Self->{DB}->LastInsertID('user_dynamic_field');

    $Self->AgentDynamicFieldTranslationSave(
        FieldID         => $FieldID,
        LabelByLanguage => $Labels,
        ChangedByUserID => $UserID,
    );

    return if $Self->Error();

    return 1;
}

sub AgentDynamicFieldUpdate {
    my ( $Self, %Param ) = @_;

    my $FieldID   = $Param{FieldID} || 0;
    my $FieldType = $Self->_Trim( $Param{FieldType} ) || 'text';
    my $Required  = $Param{IsRequired} ? 1 : 0;
    my $Active    = $Param{Active} ? 1 : 0;
    my $SortOrder = $Param{SortOrder} || 1000;
    my $UserID    = $Param{ChangedByUserID} || 1;
    my $Labels    = $Param{LabelByLanguage} || {};
    my $DefaultLabel = $Self->_FirstTranslationLabel( Labels => $Labels );

    if ( $FieldID !~ m{\A\d+\z} || !$FieldID || !$DefaultLabel ) {
        $Self->{LastError} = 'Field and default label are required';
        return;
    }

    if ( $FieldType !~ m{\A(?:text|textarea|email|phone|date|number)\z} ) {
        $FieldType = 'text';
    }

    if ( $SortOrder !~ m{\A\d+\z} ) {
        $SortOrder = 1000;
    }

    my $Result = $Self->{DB}->Do(
        'UPDATE user_dynamic_field
         SET label = ?,
             field_type = ?,
             is_required = ?,
             active = ?,
             sort_order = ?,
             changed_by_user_id = ?
         WHERE id = ?
            AND object_type = "agent"',
        $DefaultLabel,
        $FieldType,
        $Required,
        $Active,
        $SortOrder,
        $UserID,
        $FieldID,
    );

    if ( !$Result ) {
        $Self->{LastError} = $Self->{DB}->Error() || 'Field could not be updated';
        return;
    }

    $Self->AgentDynamicFieldTranslationSave(
        FieldID         => $FieldID,
        LabelByLanguage => $Labels,
        ChangedByUserID => $UserID,
    );

    return if $Self->Error();

    return 1;
}

sub AgentDynamicFieldDelete {
    my ( $Self, %Param ) = @_;

    my $FieldID = $Param{FieldID} || 0;

    if ( $FieldID !~ m{\A\d+\z} || !$FieldID ) {
        $Self->{LastError} = 'Field is required';
        return;
    }

    my $Result = $Self->{DB}->Do(
        'DELETE FROM user_dynamic_field
         WHERE id = ?
            AND object_type = "agent"',
        $FieldID,
    );

    if ( !$Result ) {
        $Self->{LastError} = $Self->{DB}->Error() || 'Field could not be deleted';
        return;
    }

    return 1;
}

sub AgentDynamicFieldTranslationList {
    my ( $Self, %Param ) = @_;

    my $FieldID = $Param{FieldID} || 0;

    return {} if $FieldID !~ m{\A\d+\z} || !$FieldID;

    my $Rows = $Self->{DB}->SelectAll(
        'SELECT
            language,
            label
         FROM user_dynamic_field_translation
         WHERE field_id = ?',
        $FieldID,
    );

    if ( !$Rows ) {
        $Self->{LastError} = $Self->{DB}->Error() || 'Field translations could not be loaded';
        return {};
    }

    my %Translation;

    for my $Row ( @{$Rows} ) {
        $Translation{ $Row->{language} } = defined $Row->{label} ? $Row->{label} : '';
    }

    return \%Translation;
}

sub AgentDynamicFieldTranslationSave {
    my ( $Self, %Param ) = @_;

    my $FieldID = $Param{FieldID} || 0;
    my $Labels  = $Param{LabelByLanguage} || {};
    my $UserID  = $Param{ChangedByUserID} || 1;

    return if $FieldID !~ m{\A\d+\z} || !$FieldID;

    my @Language = sort keys %{$Labels};

    if ( !@Language ) {
        $Self->{LastError} = 'At least one field translation is required';
        return;
    }

    my $DeleteResult = $Self->{DB}->Do(
        'DELETE FROM user_dynamic_field_translation
         WHERE field_id = ?',
        $FieldID,
    );

    if ( !$DeleteResult ) {
        $Self->{LastError} = $Self->{DB}->Error() || 'Field translations could not be deleted';
        return;
    }

    for my $Language (@Language) {
        my $Label    = $Self->_Trim( $Labels->{$Language} );

        if ( !$Label ) {
            $Self->{LastError} = 'Field translation label is required';
            return;
        }

        if ( $Language !~ m{\A[A-Za-z]{2,3}(?:[-_][A-Za-z0-9]{2,8})?\z} ) {
            $Self->{LastError} = 'Field translation language is invalid';
            return;
        }

        my $Result = $Self->{DB}->Do(
            'INSERT INTO user_dynamic_field_translation (
                field_id,
                language,
                label,
                created_by_user_id,
                changed_by_user_id
             ) VALUES (
                ?, ?, ?, ?, ?
             )
             ON DUPLICATE KEY UPDATE
                label = VALUES(label),
                changed_by_user_id = VALUES(changed_by_user_id),
                changed_at = CURRENT_TIMESTAMP',
            $FieldID,
            $Language,
            $Label,
            $UserID,
            $UserID,
        );

        if ( !$Result ) {
            $Self->{LastError} = $Self->{DB}->Error() || 'Field translation could not be saved';
            return;
        }
    }

    return 1;
}

sub AgentDynamicFieldValueList {
    my ( $Self, %Param ) = @_;

    my $UserAccountID = $Param{UserAccountID} || 0;

    return {} if $UserAccountID !~ m{\A\d+\z} || !$UserAccountID;

    my $Rows = $Self->{DB}->SelectAll(
        'SELECT
            field_id,
            value_text
         FROM user_dynamic_field_value
         WHERE object_type = "agent"
            AND object_id = ?',
        $UserAccountID,
    );

    if ( !$Rows ) {
        $Self->{LastError} = $Self->{DB}->Error() || 'Field values could not be loaded';
        return {};
    }

    my %Value;

    for my $Row ( @{$Rows} ) {
        $Value{ $Row->{field_id} } = defined $Row->{value_text} ? $Row->{value_text} : '';
    }

    return \%Value;
}

sub AgentDynamicFieldValueSave {
    my ( $Self, %Param ) = @_;

    my $UserAccountID = $Param{UserAccountID} || 0;
    my $Request       = $Param{Request} || {};
    my $UserID        = $Param{ChangedByUserID} || 1;

    return 1 if $UserAccountID !~ m{\A\d+\z} || !$UserAccountID;

    my $FieldList = $Self->AgentDynamicFieldList();
    return if $Self->Error();

    for my $Field ( @{$FieldList} ) {
        my $Key   = 'DynamicField_' . $Field->{id};
        my $Value = $Self->_Trim( $Request->{$Key} );

        if ( $Field->{is_required} && !$Value ) {
            $Self->{LastError} = 'Required dynamic field is empty';
            return;
        }

        my $Result = $Self->{DB}->Do(
            'INSERT INTO user_dynamic_field_value (
                object_type,
                object_id,
                field_id,
                value_text,
                created_by_user_id,
                changed_by_user_id
             ) VALUES (
                "agent", ?, ?, ?, ?, ?
             )
             ON DUPLICATE KEY UPDATE
                value_text = VALUES(value_text),
                changed_by_user_id = VALUES(changed_by_user_id),
                changed_at = CURRENT_TIMESTAMP',
            $UserAccountID,
            $Field->{id},
            $Value,
            $UserID,
            $UserID,
        );

        if ( !$Result ) {
            $Self->{LastError} = $Self->{DB}->Error() || 'Field value could not be saved';
            return;
        }
    }

    return 1;
}

sub AgentDynamicFieldValueValidate {
    my ( $Self, %Param ) = @_;

    my $Request = $Param{Request} || {};
    my $FieldList = $Self->AgentDynamicFieldList();

    return if $Self->Error();

    for my $Field ( @{$FieldList} ) {
        next if !$Field->{is_required};

        my $Key   = 'DynamicField_' . $Field->{id};
        my $Value = $Self->_Trim( $Request->{$Key} );

        if ( !$Value ) {
            $Self->{LastError} = 'Required dynamic field is empty';
            return;
        }
    }

    return 1;
}

sub CustomerDynamicFieldList {
    my ( $Self, %Param ) = @_;

    return $Self->_DynamicFieldList( ObjectType => 'customer', %Param );
}

sub CustomerDynamicFieldGet {
    my ( $Self, %Param ) = @_;

    return $Self->_DynamicFieldGet( ObjectType => 'customer', %Param );
}

sub CustomerDynamicFieldCreate {
    my ( $Self, %Param ) = @_;

    return $Self->_DynamicFieldCreate( ObjectType => 'customer', %Param );
}

sub CustomerDynamicFieldUpdate {
    my ( $Self, %Param ) = @_;

    return $Self->_DynamicFieldUpdate( ObjectType => 'customer', %Param );
}

sub CustomerDynamicFieldDelete {
    my ( $Self, %Param ) = @_;

    return $Self->_DynamicFieldDelete( ObjectType => 'customer', %Param );
}

sub CustomerDynamicFieldTranslationList {
    my ( $Self, %Param ) = @_;

    return $Self->_DynamicFieldTranslationList(%Param);
}

sub CustomerDynamicFieldValueList {
    my ( $Self, %Param ) = @_;

    return $Self->_DynamicFieldValueList(
        ObjectType => 'customer',
        ObjectID   => $Param{CustomerID},
    );
}

sub CustomerDynamicFieldValueSave {
    my ( $Self, %Param ) = @_;

    return $Self->_DynamicFieldValueSave(
        ObjectType      => 'customer',
        ObjectID        => $Param{CustomerID},
        Request         => $Param{Request},
        ChangedByUserID => $Param{ChangedByUserID},
    );
}

sub CustomerDynamicFieldValueValidate {
    my ( $Self, %Param ) = @_;

    return $Self->_DynamicFieldValueValidate(
        ObjectType => 'customer',
        Request    => $Param{Request},
    );
}

sub CustomerUserDynamicFieldList {
    my ( $Self, %Param ) = @_;

    return $Self->_DynamicFieldList( ObjectType => 'customer_user', %Param );
}

sub CustomerUserDynamicFieldGet {
    my ( $Self, %Param ) = @_;

    return $Self->_DynamicFieldGet( ObjectType => 'customer_user', %Param );
}

sub CustomerUserDynamicFieldCreate {
    my ( $Self, %Param ) = @_;

    return $Self->_DynamicFieldCreate( ObjectType => 'customer_user', %Param );
}

sub CustomerUserDynamicFieldUpdate {
    my ( $Self, %Param ) = @_;

    return $Self->_DynamicFieldUpdate( ObjectType => 'customer_user', %Param );
}

sub CustomerUserDynamicFieldDelete {
    my ( $Self, %Param ) = @_;

    return $Self->_DynamicFieldDelete( ObjectType => 'customer_user', %Param );
}

sub CustomerUserDynamicFieldTranslationList {
    my ( $Self, %Param ) = @_;

    return $Self->_DynamicFieldTranslationList(%Param);
}

sub CustomerUserDynamicFieldValueList {
    my ( $Self, %Param ) = @_;

    return $Self->_DynamicFieldValueList(
        ObjectType => 'customer_user',
        ObjectID   => $Param{CustomerUserID},
    );
}

sub CustomerUserDynamicFieldValueSave {
    my ( $Self, %Param ) = @_;

    return $Self->_DynamicFieldValueSave(
        ObjectType      => 'customer_user',
        ObjectID        => $Param{CustomerUserID},
        Request         => $Param{Request},
        ChangedByUserID => $Param{ChangedByUserID},
    );
}

sub CustomerUserDynamicFieldValueValidate {
    my ( $Self, %Param ) = @_;

    return $Self->_DynamicFieldValueValidate(
        ObjectType => 'customer_user',
        Request    => $Param{Request},
    );
}

sub CustomerCreate {
    my ( $Self, %Param ) = @_;

    my $CustomerNumber = $Self->_Trim( $Param{CustomerNumber} );
    my $Name           = $Self->_Trim( $Param{Name} );
    my $UserID         = $Param{ChangedByUserID} || 1;

    if ( !$CustomerNumber || !$Name ) {
        $Self->{LastError} = 'Customer number and name are required';
        return;
    }

    return if !$Self->CustomerDynamicFieldValueValidate(
        Request => $Param{Request} || {},
    );

    my $Result = $Self->{DB}->Do(
        'INSERT INTO customer (
            customer_number,
            name,
            active,
            created_by_user_id,
            changed_by_user_id
         ) VALUES (
            ?, ?, 1, ?, ?
         )',
        $CustomerNumber,
        $Name,
        $UserID,
        $UserID,
    );

    if ( !$Result ) {
        $Self->{LastError} = $Self->{DB}->Error() || 'Customer could not be created';
        return;
    }

    my $CustomerID = $Self->{DB}->LastInsertID('customer');

    $Self->CustomerDynamicFieldValueSave(
        CustomerID      => $CustomerID,
        Request         => $Param{Request} || {},
        ChangedByUserID => $UserID,
    );

    return if $Self->Error();

    return 1;
}

sub CustomerUpdate {
    my ( $Self, %Param ) = @_;

    my $CustomerID     = $Param{CustomerID} || 0;
    my $CustomerNumber = $Self->_Trim( $Param{CustomerNumber} );
    my $Name           = $Self->_Trim( $Param{Name} );
    my $Active         = $Param{Active} ? 1 : 0;
    my $UserID         = $Param{ChangedByUserID} || 1;

    if ( $CustomerID !~ m{\A\d+\z} || !$CustomerID || !$CustomerNumber || !$Name ) {
        $Self->{LastError} = 'Customer ID, customer number and name are required';
        return;
    }

    return if !$Self->CustomerDynamicFieldValueValidate(
        Request => $Param{Request} || {},
    );

    my $Result = $Self->{DB}->Do(
        'UPDATE customer
         SET customer_number = ?,
             name = ?,
             active = ?,
             changed_by_user_id = ?
         WHERE id = ?',
        $CustomerNumber,
        $Name,
        $Active,
        $UserID,
        $CustomerID,
    );

    if ( !$Result ) {
        $Self->{LastError} = $Self->{DB}->Error() || 'Customer could not be updated';
        return;
    }

    $Self->CustomerDynamicFieldValueSave(
        CustomerID      => $CustomerID,
        Request         => $Param{Request} || {},
        ChangedByUserID => $UserID,
    );

    return if $Self->Error();

    return 1;
}

sub CustomerDeactivate {
    my ( $Self, %Param ) = @_;

    my $CustomerID = $Param{CustomerID} || 0;

    return if $CustomerID !~ m{\A\d+\z} || !$CustomerID;

    my $Result = $Self->{DB}->Do(
        'UPDATE customer
         SET active = 0,
             changed_by_user_id = ?
         WHERE id = ?',
        $Param{ChangedByUserID} || 1,
        $CustomerID,
    );

    if ( !$Result ) {
        $Self->{LastError} = $Self->{DB}->Error() || 'Customer could not be deactivated';
        return;
    }

    return 1;
}

sub CustomerUserCreate {
    my ( $Self, %Param ) = @_;

    my $CustomerID     = $Param{CustomerID} || 0;
    my $Login          = $Self->_Trim( $Param{Login} );
    my $Email          = $Self->_Trim( $Param{Email} );
    my $Password       = $Param{Password} || '';
    my $Firstname      = $Self->_Trim( $Param{Firstname} );
    my $Lastname       = $Self->_Trim( $Param{Lastname} );
    my $UserID         = $Param{ChangedByUserID} || 1;

    if ( $CustomerID !~ m{\A\d+\z} || !$CustomerID || !$Login || !$Email || !$Password ) {
        $Self->{LastError} = 'Customer ID, login, email and password are required';
        return;
    }

    return if !$Self->_UserAccountDuplicateCheck(
        AccountType => 'customer',
        Login       => $Login,
        Email       => $Email,
    );

    return if !$Self->CustomerUserDynamicFieldValueValidate(
        Request => $Param{Request} || {},
    );

    my $Customer = $Self->{DB}->SelectRow(
        'SELECT id
         FROM customer
         WHERE id = ?
            AND active = 1
         LIMIT 1',
        $CustomerID,
    );

    if ( !$Customer ) {
        $Self->{LastError} = 'Customer was not found';
        return;
    }

    my $PasswordHash = $Self->_PasswordHash( Password => $Password );

    my $Result = $Self->{DB}->Do(
        'INSERT INTO user_account (
            login,
            account_type,
            email,
            password_hash,
            firstname,
            lastname,
            is_active,
            is_system_user,
            password_changed_at
         ) VALUES (
            ?, "customer", ?, ?, ?, ?, 1, 0, NOW()
         )',
        $Login,
        $Email,
        $PasswordHash,
        $Firstname,
        $Lastname,
    );

    if ( !$Result ) {
        return if $Self->_UserAccountDuplicateErrorFromDB(
            AccountType => 'customer',
            Login       => $Login,
            Email       => $Email,
        );

        $Self->{LastError} = $Self->{DB}->Error() || 'Customer user account could not be created';
        return;
    }

    my $NewUserID = $Self->{DB}->LastInsertID('user_account');

    $Result = $Self->{DB}->Do(
        'INSERT INTO customer_user (
            customer_id,
            user_account_id,
            active,
            created_by_user_id,
            changed_by_user_id
         ) VALUES (
            ?, ?, 1, ?, ?
         )',
        $Customer->{id},
        $NewUserID,
        $UserID,
        $UserID,
    );

    if ( !$Result ) {
        $Self->{LastError} = $Self->{DB}->Error() || 'Customer user could not be created';
        return;
    }

    my $CustomerUserID = $Self->{DB}->LastInsertID('customer_user');

    $Self->CustomerUserDynamicFieldValueSave(
        CustomerUserID  => $CustomerUserID,
        Request         => $Param{Request} || {},
        ChangedByUserID => $UserID,
    );

    return if $Self->Error();

    my $AssignedTicketCount = $Self->_CustomerUserTicketsAutoAssign(
        CustomerID     => $Customer->{id},
        CustomerUserID => $CustomerUserID,
        Email          => $Email,
        ChangedByUserID => $UserID,
    );

    return if $Self->Error();

    $Self->{LastCustomerUserAutoAssignTicketCount} = $AssignedTicketCount || 0;

    return 1;
}

sub CustomerUserUpdate {
    my ( $Self, %Param ) = @_;

    my $CustomerUserID = $Param{CustomerUserID} || 0;
    my $CustomerID     = $Param{CustomerID} || 0;
    my $Login          = $Self->_Trim( $Param{Login} );
    my $Email          = $Self->_Trim( $Param{Email} );
    my $Password       = $Param{Password} || '';
    my $Firstname      = $Self->_Trim( $Param{Firstname} );
    my $Lastname       = $Self->_Trim( $Param{Lastname} );
    my $Active         = $Param{Active} ? 1 : 0;
    my $UserID         = $Param{ChangedByUserID} || 1;

    if (
        $CustomerUserID !~ m{\A\d+\z} || !$CustomerUserID
        || $CustomerID !~ m{\A\d+\z} || !$CustomerID
        || !$Login || !$Email
        )
    {
        $Self->{LastError} = 'Customer user ID, customer, login and email are required';
        return;
    }

    my $CustomerUser = $Self->{DB}->SelectRow(
        'SELECT id, user_account_id
         FROM customer_user
         WHERE id = ?
         LIMIT 1',
        $CustomerUserID,
    );

    if ( !$CustomerUser ) {
        $Self->{LastError} = 'Customer user was not found';
        return;
    }

    return if !$Self->_UserAccountDuplicateCheck(
        AccountType   => 'customer',
        UserAccountID => $CustomerUser->{user_account_id},
        Login         => $Login,
        Email         => $Email,
    );

    return if !$Self->CustomerUserDynamicFieldValueValidate(
        Request => $Param{Request} || {},
    );

    my $Customer = $Self->{DB}->SelectRow(
        'SELECT id
         FROM customer
         WHERE id = ?
         LIMIT 1',
        $CustomerID,
    );

    if ( !$Customer ) {
        $Self->{LastError} = 'Customer was not found';
        return;
    }

    my $UserUpdateSQL = 'UPDATE user_account
         SET login = ?,
             email = ?,
             firstname = ?,
             lastname = ?,
             is_active = ?';
    my @UserBind = (
        $Login,
        $Email,
        $Firstname,
        $Lastname,
        $Active,
    );

    if ($Password) {
        $UserUpdateSQL .= ',
             password_hash = ?,
             password_changed_at = NOW()';
        push @UserBind, $Self->_PasswordHash( Password => $Password );
    }

    $UserUpdateSQL .= '
         WHERE id = ?';
    push @UserBind, $CustomerUser->{user_account_id};

    my $Result = $Self->{DB}->Do( $UserUpdateSQL, @UserBind );

    if ( !$Result ) {
        return if $Self->_UserAccountDuplicateErrorFromDB(
            AccountType => 'customer',
            Login       => $Login,
            Email       => $Email,
        );

        $Self->{LastError} = $Self->{DB}->Error() || 'Customer user account could not be updated';
        return;
    }

    $Result = $Self->{DB}->Do(
        'UPDATE customer_user
         SET customer_id = ?,
             active = ?,
             changed_by_user_id = ?
         WHERE id = ?',
        $CustomerID,
        $Active,
        $UserID,
        $CustomerUserID,
    );

    if ( !$Result ) {
        $Self->{LastError} = $Self->{DB}->Error() || 'Customer user could not be updated';
        return;
    }

    $Self->CustomerUserDynamicFieldValueSave(
        CustomerUserID  => $CustomerUserID,
        Request         => $Param{Request} || {},
        ChangedByUserID => $UserID,
    );

    return if $Self->Error();

    return 1;
}

sub CustomerUserDeactivate {
    my ( $Self, %Param ) = @_;

    my $CustomerUserID = $Param{CustomerUserID} || 0;

    return if $CustomerUserID !~ m{\A\d+\z} || !$CustomerUserID;

    my $Result = $Self->{DB}->Do(
        'UPDATE customer_user
         SET active = 0,
             changed_by_user_id = ?
         WHERE id = ?',
        $Param{ChangedByUserID} || 1,
        $CustomerUserID,
    );

    if ( !$Result ) {
        $Self->{LastError} = $Self->{DB}->Error() || 'Customer user could not be deactivated';
        return;
    }

    $Self->{DB}->Do(
        'UPDATE user_account ua
         INNER JOIN customer_user cu
            ON cu.user_account_id = ua.id
         SET ua.is_active = 0
         WHERE cu.id = ?',
        $CustomerUserID,
    );

    return 1;
}

sub QueueCreate {
    my ( $Self, %Param ) = @_;

    my $Name           = $Self->_Trim( $Param{Name} );
    my $ParentQueueID  = $Param{ParentQueueID} || 0;
    my $GroupID        = $Param{GroupID} || 0;
    my $SortOrder      = $Param{SortOrder} || 1000;
    my $FollowUpAllowed = $Param{FollowUpAllowed} ? 1 : 0;
    my $SystemEmailID  = $Self->_OptionalID( $Param{SystemEmailID} );
    my $SalutationID   = $Self->_OptionalID( $Param{SalutationID} );
    my $SignatureID    = $Self->_OptionalID( $Param{SignatureID} );
    my $CalendarID     = $Self->_OptionalID( $Param{CalendarID} );
    my $EscalationFirstResponse = $Self->_UnsignedInteger( $Param{EscalationFirstResponseMinutes} );
    my $EscalationUpdate = $Self->_UnsignedInteger( $Param{EscalationUpdateMinutes} );
    my $EscalationSolution = $Self->_UnsignedInteger( $Param{EscalationSolutionMinutes} );
    my $UserID         = $Param{ChangedByUserID} || 1;

    if ( !$Name || !$GroupID || !$SystemEmailID ) {
        $Self->{LastError} = 'Translate:AdminQueueNameGroupSystemEmailRequired';
        return;
    }

    if ( $SortOrder !~ m{\A\d+\z} ) {
        $SortOrder = 1000;
    }

    my $ParentID;
    my $FullName = $Name;

    if ($ParentQueueID) {
        if ( $ParentQueueID !~ m{\A\d+\z} ) {
            $Self->{LastError} = 'Parent queue ID is invalid';
            return;
        }

        my $Parent = $Self->{DB}->SelectRow(
            'SELECT id, full_name
             FROM ticket_queue
             WHERE id = ?
                AND active = 1
             LIMIT 1',
            $ParentQueueID,
        );

        if ( !$Parent ) {
            $Self->{LastError} = 'Parent queue was not found';
            return;
        }

        $ParentID = $Parent->{id};
        $FullName = $Parent->{full_name} . '::' . $Name;
    }

    my $Result = $Self->{DB}->Do(
        'INSERT INTO ticket_queue (
            parent_id,
            name,
            full_name,
            follow_up_allowed,
            system_email_id,
            salutation_id,
            signature_id,
            calendar_id,
            escalation_first_response_minutes,
            escalation_update_minutes,
            escalation_solution_minutes,
            active,
            sort_order,
            created_by_user_id,
            changed_by_user_id
         ) VALUES (
            ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, 1, ?, ?, ?
         )',
        $ParentID,
        $Name,
        $FullName,
        $FollowUpAllowed,
        $SystemEmailID,
        $SalutationID,
        $SignatureID,
        $CalendarID,
        $EscalationFirstResponse,
        $EscalationUpdate,
        $EscalationSolution,
        $SortOrder,
        $UserID,
        $UserID,
    );

    if ( !$Result ) {
        $Self->{LastError} = $Self->{DB}->Error() || 'Queue could not be created';
        return;
    }

    my $QueueID = $Self->{DB}->LastInsertID('ticket_queue');

    if ($GroupID) {
        $Self->QueueGroupAdd(
            QueueID          => $QueueID,
            GroupID          => $GroupID,
            ChangedByUserID  => $UserID,
        );
    }

    return 1;
}

sub QueueUpdate {
    my ( $Self, %Param ) = @_;

    my $QueueID        = $Param{QueueID} || 0;
    my $Name           = $Self->_Trim( $Param{Name} );
    my $ParentQueueID  = $Param{ParentQueueID} || 0;
    my $GroupID        = $Param{GroupID} || 0;
    my $SortOrder      = $Param{SortOrder} || 1000;
    my $Active         = $Param{Active} ? 1 : 0;
    my $FollowUpAllowed = $Param{FollowUpAllowed} ? 1 : 0;
    my $SystemEmailID  = $Self->_OptionalID( $Param{SystemEmailID} );
    my $SalutationID   = $Self->_OptionalID( $Param{SalutationID} );
    my $SignatureID    = $Self->_OptionalID( $Param{SignatureID} );
    my $CalendarID     = $Self->_OptionalID( $Param{CalendarID} );
    my $EscalationFirstResponse = $Self->_UnsignedInteger( $Param{EscalationFirstResponseMinutes} );
    my $EscalationUpdate = $Self->_UnsignedInteger( $Param{EscalationUpdateMinutes} );
    my $EscalationSolution = $Self->_UnsignedInteger( $Param{EscalationSolutionMinutes} );
    my $UserID         = $Param{ChangedByUserID} || 1;

    if ( $QueueID !~ m{\A\d+\z} || !$QueueID || !$Name || !$GroupID || !$SystemEmailID ) {
        $Self->{LastError} = 'Translate:AdminQueueNameGroupSystemEmailRequired';
        return;
    }

    if ( $SortOrder !~ m{\A\d+\z} ) {
        $SortOrder = 1000;
    }

    my $ParentID;
    my $FullName = $Name;

    if ($ParentQueueID) {
        if ( $ParentQueueID !~ m{\A\d+\z} ) {
            $Self->{LastError} = 'Parent queue ID is invalid';
            return;
        }

        if ( $ParentQueueID == $QueueID ) {
            $Self->{LastError} = 'Queue cannot be its own parent';
            return;
        }

        my $Parent = $Self->{DB}->SelectRow(
            'SELECT id, full_name
             FROM ticket_queue
             WHERE id = ?
                AND active = 1
             LIMIT 1',
            $ParentQueueID,
        );

        if ( !$Parent ) {
            $Self->{LastError} = 'Parent queue was not found';
            return;
        }

        $ParentID = $Parent->{id};
        $FullName = $Parent->{full_name} . '::' . $Name;
    }

    my $Result = $Self->{DB}->Do(
        'UPDATE ticket_queue
         SET parent_id = ?,
             name = ?,
             full_name = ?,
             follow_up_allowed = ?,
             system_email_id = ?,
             salutation_id = ?,
             signature_id = ?,
             calendar_id = ?,
             escalation_first_response_minutes = ?,
             escalation_update_minutes = ?,
             escalation_solution_minutes = ?,
             active = ?,
             sort_order = ?,
             changed_by_user_id = ?
         WHERE id = ?',
        $ParentID,
        $Name,
        $FullName,
        $FollowUpAllowed,
        $SystemEmailID,
        $SalutationID,
        $SignatureID,
        $CalendarID,
        $EscalationFirstResponse,
        $EscalationUpdate,
        $EscalationSolution,
        $Active,
        $SortOrder,
        $UserID,
        $QueueID,
    );

    if ( !$Result ) {
        $Self->{LastError} = $Self->{DB}->Error() || 'Queue could not be updated';
        return;
    }

    if ($GroupID) {
        $Self->QueueGroupSet(
            QueueID         => $QueueID,
            GroupID         => $GroupID,
            ChangedByUserID => $UserID,
        );
        return if $Self->{LastError};
    }

    return 1;
}

sub QueueDeactivate {
    my ( $Self, %Param ) = @_;

    my $QueueID = $Param{QueueID} || 0;

    return if $QueueID !~ m{\A\d+\z} || !$QueueID;

    my $Result = $Self->{DB}->Do(
        'UPDATE ticket_queue
         SET active = 0,
             changed_by_user_id = ?
         WHERE id = ?',
        $Param{ChangedByUserID} || 1,
        $QueueID,
    );

    if ( !$Result ) {
        $Self->{LastError} = $Self->{DB}->Error() || 'Queue could not be deactivated';
        return;
    }

    return 1;
}

sub QueuePrimaryGroupID {
    my ( $Self, %Param ) = @_;

    my $QueueID = $Param{QueueID} || 0;

    return if $QueueID !~ m{\A\d+\z} || !$QueueID;

    my $Row = $Self->{DB}->SelectRow(
        'SELECT user_group_id
         FROM ticket_queue_group
         WHERE queue_id = ?
            AND active = 1
            AND permission_key = "ticket.view"
         ORDER BY id ASC
         LIMIT 1',
        $QueueID,
    );

    return $Row ? $Row->{user_group_id} : '';
}

sub QueueGroupSet {
    my ( $Self, %Param ) = @_;

    my $QueueID = $Param{QueueID} || 0;
    my $GroupID = $Param{GroupID} || 0;
    my $UserID  = $Param{ChangedByUserID} || 1;

    return if $QueueID !~ m{\A\d+\z} || !$QueueID;
    return if $GroupID !~ m{\A\d+\z} || !$GroupID;

    my $Result = $Self->{DB}->Do(
        'UPDATE ticket_queue_group
         SET active = 0,
             changed_by_user_id = ?,
             changed_at = CURRENT_TIMESTAMP
         WHERE queue_id = ?',
        $UserID,
        $QueueID,
    );

    if ( !$Result ) {
        $Self->{LastError} = $Self->{DB}->Error() || 'Queue group assignment could not be changed';
        return;
    }

    return $Self->QueueGroupAdd(
        QueueID         => $QueueID,
        GroupID         => $GroupID,
        ChangedByUserID => $UserID,
    );
}

sub QueueGroupAdd {
    my ( $Self, %Param ) = @_;

    my $QueueID   = $Param{QueueID} || 0;
    my $GroupID   = $Param{GroupID} || 0;
    my $UserID    = $Param{ChangedByUserID} || 1;

    return if $QueueID !~ m{\A\d+\z} || !$QueueID;
    return if $GroupID !~ m{\A\d+\z} || !$GroupID;

    my $Group = $Self->_GroupGet( GroupID => $GroupID );
    return if !$Group;

    for my $Permission (qw(ticket.view ticket.create ticket.edit)) {
        my $Result = $Self->{DB}->Do(
            'INSERT INTO ticket_queue_group (
                queue_id,
                user_group_id,
                permission_key,
                active,
                created_by_user_id,
                changed_by_user_id
             ) VALUES (
                ?, ?, ?, 1, ?, ?
             )
             ON DUPLICATE KEY UPDATE
                active = 1,
                changed_by_user_id = VALUES(changed_by_user_id),
                changed_at = CURRENT_TIMESTAMP',
            $QueueID,
            $Group->{id},
            $Permission,
            $UserID,
            $UserID,
        );

        if ( !$Result ) {
            $Self->{LastError} = $Self->{DB}->Error() || 'Queue group assignment could not be saved';
            return;
        }
    }

    return 1;
}

sub GroupCreate {
    my ( $Self, %Param ) = @_;

    my $Name       = $Self->_Trim( $Param{Name} );
    my $Title      = $Self->_Trim( $Param{Title} );
    my $GroupType  = $Self->_Trim( $Param{GroupType} ) || 'agent';
    my $SortOrder  = $Param{SortOrder} || 1000;
    my $UserID     = $Param{ChangedByUserID} || 1;

    if ( !$Name ) {
        $Self->{LastError} = 'Group name is required';
        return;
    }

    if ( $SortOrder !~ m{\A\d+\z} ) {
        $SortOrder = 1000;
    }

    my $Result = $Self->{DB}->Do(
        'INSERT INTO user_group (
            name,
            title,
            group_type,
            active,
            sort_order,
            created_by_user_id,
            changed_by_user_id
         ) VALUES (
            ?, ?, ?, 1, ?, ?, ?
         )',
        $Name,
        $Title,
        $GroupType,
        $SortOrder,
        $UserID,
        $UserID,
    );

    if ( !$Result ) {
        $Self->{LastError} = $Self->{DB}->Error() || 'Group could not be created';
        return;
    }

    return 1;
}

sub GroupDeactivate {
    my ( $Self, %Param ) = @_;

    my $GroupID = $Param{GroupID} || 0;

    return if $GroupID !~ m{\A\d+\z} || !$GroupID;

    my $Result = $Self->{DB}->Do(
        'UPDATE user_group
         SET active = 0,
             changed_by_user_id = ?
         WHERE id = ?',
        $Param{ChangedByUserID} || 1,
        $GroupID,
    );

    if ( !$Result ) {
        $Self->{LastError} = $Self->{DB}->Error() || 'Group could not be deactivated';
        return;
    }

    return 1;
}

sub GroupPermissionAdd {
    my ( $Self, %Param ) = @_;

    my $GroupID    = $Param{GroupID} || 0;
    my $Permission = $Self->_Trim( $Param{Permission} );
    my $UserID     = $Param{ChangedByUserID} || 1;

    return if $GroupID !~ m{\A\d+\z} || !$GroupID;
    return if !$Permission;

    my $Result = $Self->{DB}->Do(
        'INSERT INTO user_group_permission (
            user_group_id,
            permission_key,
            active,
            created_by_user_id,
            changed_by_user_id
         ) VALUES (
            ?, ?, 1, ?, ?
         )
         ON DUPLICATE KEY UPDATE
            active = 1,
            changed_by_user_id = VALUES(changed_by_user_id),
            changed_at = CURRENT_TIMESTAMP',
        $GroupID,
        $Permission,
        $UserID,
        $UserID,
    );

    if ( !$Result ) {
        $Self->{LastError} = $Self->{DB}->Error() || 'Group permission could not be saved';
        return;
    }

    return 1;
}

sub LanguageList {
    my ($Self) = @_;

    my $DefaultLanguage = $Self->_LanguageClean( $Self->{Config}->{Language}->{Default} || 'en' );
    my $LanguagePath    = $Self->{Config}->{Paths}->{Language};
    my %Language        = ( $DefaultLanguage => 1 );

    if ( $LanguagePath && opendir my $DirectoryHandle, $LanguagePath ) {
        while ( my $Entry = readdir $DirectoryHandle ) {
            next if $Entry !~ m{\A([A-Za-z0-9_-]+)\.pm\z};

            my $Code = $Self->_LanguageClean($1);
            $Language{$Code} = 1 if $Code;
        }

        closedir $DirectoryHandle;
    }

    my @Sorted = sort grep { $_ ne $DefaultLanguage } keys %Language;
    my @List   = (
        {
            code       => $DefaultLanguage,
            is_default => 1,
        },
    );

    for my $Code (@Sorted) {
        push @List, {
            code       => $Code,
            is_default => 0,
        };
    }

    return \@List;
}

sub _DynamicFieldList {
    my ( $Self, %Param ) = @_;

    my $ObjectType      = $Self->_Trim( $Param{ObjectType} );
    my $Language        = $Self->_LanguageClean( $Param{Language} || $Self->{Config}->{Language}->{Default} || 'en' );
    my $DefaultLanguage = $Self->_LanguageClean( $Self->{Config}->{Language}->{Default} || 'en' );
    my $IncludeInactive = $Param{IncludeInactive} ? 1 : 0;
    my $WhereActive     = $IncludeInactive ? '' : 'AND f.active = 1';

    return [] if !$ObjectType;

    my $Rows = $Self->{DB}->SelectAll(
        'SELECT
            f.id,
            f.name,
            COALESCE(current_translation.label, default_translation.label, f.label, f.name) AS label,
            f.field_type,
            f.is_required,
            f.active,
            f.sort_order
         FROM user_dynamic_field f
         LEFT JOIN user_dynamic_field_translation current_translation
            ON current_translation.field_id = f.id
            AND current_translation.language = ?
         LEFT JOIN user_dynamic_field_translation default_translation
            ON default_translation.field_id = f.id
            AND default_translation.language = ?
         WHERE f.object_type = ?
            ' . $WhereActive . '
         ORDER BY f.sort_order ASC, label ASC, f.id ASC',
        $Language,
        $DefaultLanguage,
        $ObjectType,
    );

    return $Self->_RowsPrepare( Rows => $Rows );
}

sub _DynamicFieldGet {
    my ( $Self, %Param ) = @_;

    my $ObjectType = $Self->_Trim( $Param{ObjectType} );
    my $FieldID    = $Param{FieldID} || 0;

    return if !$ObjectType;
    return if $FieldID !~ m{\A\d+\z} || !$FieldID;

    my $Field = $Self->{DB}->SelectRow(
        'SELECT
            id,
            name,
            field_type,
            is_required,
            active,
            sort_order
         FROM user_dynamic_field
         WHERE id = ?
            AND object_type = ?
         LIMIT 1',
        $FieldID,
        $ObjectType,
    );

    if ( !$Field ) {
        $Self->{LastError} = 'Field was not found';
        return;
    }

    return $Self->_RowsPrepare( Rows => [$Field] )->[0];
}

sub _DynamicFieldCreate {
    my ( $Self, %Param ) = @_;

    my $ObjectType = $Self->_Trim( $Param{ObjectType} );
    my $Name       = $Self->_Trim( $Param{Name} );
    my $FieldType  = $Self->_Trim( $Param{FieldType} ) || 'text';
    my $Required   = $Param{IsRequired} ? 1 : 0;
    my $SortOrder  = $Param{SortOrder} || 1000;
    my $UserID     = $Param{ChangedByUserID} || 1;
    my $Labels     = $Param{LabelByLanguage} || {};
    my $DefaultLabel = $Self->_FirstTranslationLabel( Labels => $Labels );

    if ( !$ObjectType || !$Name || !$DefaultLabel ) {
        $Self->{LastError} = 'Field name and label are required';
        return;
    }

    if ( $Name !~ m{\A[A-Za-z][A-Za-z0-9_]*\z} ) {
        $Self->{LastError} = 'Database field must use ASCII letters, numbers and underscores and must start with a letter';
        return;
    }

    if ( $FieldType !~ m{\A(?:text|textarea|email|phone|date|number)\z} ) {
        $FieldType = 'text';
    }

    if ( $SortOrder !~ m{\A\d+\z} ) {
        $SortOrder = 1000;
    }

    my $Result = $Self->{DB}->Do(
        'INSERT INTO user_dynamic_field (
            object_type,
            name,
            label,
            field_type,
            is_required,
            active,
            sort_order,
            created_by_user_id,
            changed_by_user_id
         ) VALUES (
            ?, ?, ?, ?, ?, 1, ?, ?, ?
         )',
        $ObjectType,
        $Name,
        $DefaultLabel,
        $FieldType,
        $Required,
        $SortOrder,
        $UserID,
        $UserID,
    );

    if ( !$Result ) {
        $Self->{LastError} = $Self->{DB}->Error() || 'Field could not be created';
        return;
    }

    my $FieldID = $Self->{DB}->LastInsertID('user_dynamic_field');

    $Self->_DynamicFieldTranslationSave(
        FieldID         => $FieldID,
        LabelByLanguage => $Labels,
        ChangedByUserID => $UserID,
    );

    return if $Self->Error();

    return 1;
}

sub _DynamicFieldUpdate {
    my ( $Self, %Param ) = @_;

    my $ObjectType = $Self->_Trim( $Param{ObjectType} );
    my $FieldID    = $Param{FieldID} || 0;
    my $FieldType  = $Self->_Trim( $Param{FieldType} ) || 'text';
    my $Required   = $Param{IsRequired} ? 1 : 0;
    my $Active     = $Param{Active} ? 1 : 0;
    my $SortOrder  = $Param{SortOrder} || 1000;
    my $UserID     = $Param{ChangedByUserID} || 1;
    my $Labels     = $Param{LabelByLanguage} || {};
    my $DefaultLabel = $Self->_FirstTranslationLabel( Labels => $Labels );

    if ( !$ObjectType || $FieldID !~ m{\A\d+\z} || !$FieldID || !$DefaultLabel ) {
        $Self->{LastError} = 'Field and default label are required';
        return;
    }

    if ( $FieldType !~ m{\A(?:text|textarea|email|phone|date|number)\z} ) {
        $FieldType = 'text';
    }

    if ( $SortOrder !~ m{\A\d+\z} ) {
        $SortOrder = 1000;
    }

    my $Result = $Self->{DB}->Do(
        'UPDATE user_dynamic_field
         SET label = ?,
             field_type = ?,
             is_required = ?,
             active = ?,
             sort_order = ?,
             changed_by_user_id = ?
         WHERE id = ?
            AND object_type = ?',
        $DefaultLabel,
        $FieldType,
        $Required,
        $Active,
        $SortOrder,
        $UserID,
        $FieldID,
        $ObjectType,
    );

    if ( !$Result ) {
        $Self->{LastError} = $Self->{DB}->Error() || 'Field could not be updated';
        return;
    }

    $Self->_DynamicFieldTranslationSave(
        FieldID         => $FieldID,
        LabelByLanguage => $Labels,
        ChangedByUserID => $UserID,
    );

    return if $Self->Error();

    return 1;
}

sub _DynamicFieldDelete {
    my ( $Self, %Param ) = @_;

    my $ObjectType = $Self->_Trim( $Param{ObjectType} );
    my $FieldID    = $Param{FieldID} || 0;

    if ( !$ObjectType || $FieldID !~ m{\A\d+\z} || !$FieldID ) {
        $Self->{LastError} = 'Field is required';
        return;
    }

    my $Result = $Self->{DB}->Do(
        'DELETE FROM user_dynamic_field
         WHERE id = ?
            AND object_type = ?',
        $FieldID,
        $ObjectType,
    );

    if ( !$Result ) {
        $Self->{LastError} = $Self->{DB}->Error() || 'Field could not be deleted';
        return;
    }

    return 1;
}

sub _DynamicFieldTranslationList {
    my ( $Self, %Param ) = @_;

    my $FieldID = $Param{FieldID} || 0;

    return {} if $FieldID !~ m{\A\d+\z} || !$FieldID;

    my $Rows = $Self->{DB}->SelectAll(
        'SELECT
            language,
            label
         FROM user_dynamic_field_translation
         WHERE field_id = ?',
        $FieldID,
    );

    if ( !$Rows ) {
        $Self->{LastError} = $Self->{DB}->Error() || 'Field translations could not be loaded';
        return {};
    }

    my %Translation;

    for my $Row ( @{$Rows} ) {
        $Translation{ $Row->{language} } = defined $Row->{label} ? $Row->{label} : '';
    }

    return \%Translation;
}

sub _DynamicFieldTranslationSave {
    my ( $Self, %Param ) = @_;

    my $FieldID = $Param{FieldID} || 0;
    my $Labels  = $Param{LabelByLanguage} || {};
    my $UserID  = $Param{ChangedByUserID} || 1;

    return if $FieldID !~ m{\A\d+\z} || !$FieldID;

    my @Language = sort keys %{$Labels};

    if ( !@Language ) {
        $Self->{LastError} = 'At least one field translation is required';
        return;
    }

    my $DeleteResult = $Self->{DB}->Do(
        'DELETE FROM user_dynamic_field_translation
         WHERE field_id = ?',
        $FieldID,
    );

    if ( !$DeleteResult ) {
        $Self->{LastError} = $Self->{DB}->Error() || 'Field translations could not be deleted';
        return;
    }

    for my $Language (@Language) {
        my $Label = $Self->_Trim( $Labels->{$Language} );

        if ( !$Label ) {
            $Self->{LastError} = 'Field translation label is required';
            return;
        }

        if ( $Language !~ m{\A[A-Za-z]{2,3}(?:[-_][A-Za-z0-9]{2,8})?\z} ) {
            $Self->{LastError} = 'Field translation language is invalid';
            return;
        }

        my $Result = $Self->{DB}->Do(
            'INSERT INTO user_dynamic_field_translation (
                field_id,
                language,
                label,
                created_by_user_id,
                changed_by_user_id
             ) VALUES (
                ?, ?, ?, ?, ?
             )
             ON DUPLICATE KEY UPDATE
                label = VALUES(label),
                changed_by_user_id = VALUES(changed_by_user_id),
                changed_at = CURRENT_TIMESTAMP',
            $FieldID,
            $Language,
            $Label,
            $UserID,
            $UserID,
        );

        if ( !$Result ) {
            $Self->{LastError} = $Self->{DB}->Error() || 'Field translation could not be saved';
            return;
        }
    }

    return 1;
}

sub _DynamicFieldValueList {
    my ( $Self, %Param ) = @_;

    my $ObjectType = $Self->_Trim( $Param{ObjectType} );
    my $ObjectID   = $Param{ObjectID} || 0;

    return {} if !$ObjectType;
    return {} if $ObjectID !~ m{\A\d+\z} || !$ObjectID;

    my $Rows = $Self->{DB}->SelectAll(
        'SELECT
            field_id,
            value_text
         FROM user_dynamic_field_value
         WHERE object_type = ?
            AND object_id = ?',
        $ObjectType,
        $ObjectID,
    );

    if ( !$Rows ) {
        $Self->{LastError} = $Self->{DB}->Error() || 'Field values could not be loaded';
        return {};
    }

    my %Value;

    for my $Row ( @{$Rows} ) {
        $Value{ $Row->{field_id} } = defined $Row->{value_text} ? $Row->{value_text} : '';
    }

    return \%Value;
}

sub _DynamicFieldValueSave {
    my ( $Self, %Param ) = @_;

    my $ObjectType = $Self->_Trim( $Param{ObjectType} );
    my $ObjectID   = $Param{ObjectID} || 0;
    my $Request    = $Param{Request} || {};
    my $UserID     = $Param{ChangedByUserID} || 1;

    return 1 if !$ObjectType;
    return 1 if $ObjectID !~ m{\A\d+\z} || !$ObjectID;

    my $FieldList = $Self->_DynamicFieldList( ObjectType => $ObjectType );
    return if $Self->Error();

    for my $Field ( @{$FieldList} ) {
        my $Key   = 'DynamicField_' . $Field->{id};
        my $Value = $Self->_Trim( $Request->{$Key} );

        if ( $Field->{is_required} && !$Value ) {
            $Self->{LastError} = 'Required dynamic field is empty';
            return;
        }

        my $Result = $Self->{DB}->Do(
            'INSERT INTO user_dynamic_field_value (
                object_type,
                object_id,
                field_id,
                value_text,
                created_by_user_id,
                changed_by_user_id
             ) VALUES (
                ?, ?, ?, ?, ?, ?
             )
             ON DUPLICATE KEY UPDATE
                value_text = VALUES(value_text),
                changed_by_user_id = VALUES(changed_by_user_id),
                changed_at = CURRENT_TIMESTAMP',
            $ObjectType,
            $ObjectID,
            $Field->{id},
            $Value,
            $UserID,
            $UserID,
        );

        if ( !$Result ) {
            $Self->{LastError} = $Self->{DB}->Error() || 'Field value could not be saved';
            return;
        }
    }

    return 1;
}

sub _DynamicFieldValueValidate {
    my ( $Self, %Param ) = @_;

    my $ObjectType = $Self->_Trim( $Param{ObjectType} );
    my $Request    = $Param{Request} || {};

    return if !$ObjectType;

    my $FieldList = $Self->_DynamicFieldList( ObjectType => $ObjectType );

    return if $Self->Error();

    for my $Field ( @{$FieldList} ) {
        next if !$Field->{is_required};

        my $Key   = 'DynamicField_' . $Field->{id};
        my $Value = $Self->_Trim( $Request->{$Key} );

        if ( !$Value ) {
            $Self->{LastError} = 'Required dynamic field is empty';
            return;
        }
    }

    return 1;
}

sub _MasterDataList {
    my ( $Self, %Param ) = @_;

    my $Table           = $Self->_MasterDataTable( $Param{Table} );
    my $ExtraSelect     = $Self->_MasterDataColumn( $Param{ExtraSelect} );
    my $IncludeInactive = $Param{IncludeInactive} ? 1 : 0;

    return [] if !$Table;

    my $WhereActive = $IncludeInactive ? '' : 'WHERE active = 1';
    my $SQL = 'SELECT id, name';

    if ($ExtraSelect) {
        $SQL .= ', ' . $ExtraSelect;
    }

    $SQL .= ', active, sort_order
        FROM ' . $Table . '
        ' . $WhereActive . '
        ORDER BY sort_order ASC, name ASC';

    my $Rows = $Self->{DB}->SelectAll($SQL);

    return $Self->_RowsPrepare( Rows => $Rows );
}

sub _MasterDataGet {
    my ( $Self, %Param ) = @_;

    my $Table       = $Self->_MasterDataTable( $Param{Table} );
    my $ExtraSelect = $Self->_MasterDataColumn( $Param{ExtraSelect} );
    my $ID          = $Param{ID} || 0;

    return if !$Table;
    return if $ID !~ m{\A\d+\z} || !$ID;

    my $SQL = 'SELECT id, name';

    if ($ExtraSelect) {
        $SQL .= ', ' . $ExtraSelect;
    }

    $SQL .= ', active, sort_order
        FROM ' . $Table . '
        WHERE id = ?
        LIMIT 1';

    my $Row = $Self->{DB}->SelectRow( $SQL, $ID );

    if ( !$Row ) {
        $Self->{LastError} = 'Entry was not found';
        return;
    }

    return $Self->_RowsPrepare( Rows => [$Row] )->[0];
}

sub _MasterDataCreate {
    my ( $Self, %Param ) = @_;

    my $Table       = $Self->_MasterDataTable( $Param{Table} );
    my $ExtraColumn = $Self->_MasterDataColumn( $Param{ExtraColumn} );
    my $Name        = $Self->_Trim( $Param{Name} );
    my $ExtraValue  = $Self->_Trim( $Param{ExtraValue} );
    my $SortOrder   = $Param{SortOrder} || 1000;
    my $UserID      = $Param{ChangedByUserID} || 1;

    return if !$Table || !$ExtraColumn;

    if ( !$Name || !$ExtraValue ) {
        $Self->{LastError} = 'Name and value are required';
        return;
    }

    if ( $SortOrder !~ m{\A\d+\z} ) {
        $SortOrder = 1000;
    }

    if ( $Table eq 'salutation' || $Table eq 'signature' ) {
        $ExtraValue = QisutuHTML->Sanitize($ExtraValue);
    }

    my $Result = $Self->{DB}->Do(
        'INSERT INTO ' . $Table . ' (
            name,
            ' . $ExtraColumn . ',
            active,
            sort_order,
            created_by_user_id,
            changed_by_user_id
         ) VALUES (
            ?, ?, 1, ?, ?, ?
         )',
        $Name,
        $ExtraValue,
        $SortOrder,
        $UserID,
        $UserID,
    );

    if ( !$Result ) {
        $Self->{LastError} = $Self->{DB}->Error() || 'Entry could not be created';
        return;
    }

    return 1;
}

sub _MasterDataUpdate {
    my ( $Self, %Param ) = @_;

    my $Table       = $Self->_MasterDataTable( $Param{Table} );
    my $ExtraColumn = $Self->_MasterDataColumn( $Param{ExtraColumn} );
    my $ID          = $Param{ID} || 0;
    my $Name        = $Self->_Trim( $Param{Name} );
    my $ExtraValue  = $Self->_Trim( $Param{ExtraValue} );
    my $Active      = $Param{Active} ? 1 : 0;
    my $SortOrder   = $Param{SortOrder} || 1000;
    my $UserID      = $Param{ChangedByUserID} || 1;

    return if !$Table || !$ExtraColumn;

    if ( $ID !~ m{\A\d+\z} || !$ID || !$Name || !$ExtraValue ) {
        $Self->{LastError} = 'Entry, name and value are required';
        return;
    }

    if ( $SortOrder !~ m{\A\d+\z} ) {
        $SortOrder = 1000;
    }

    if ( $Table eq 'salutation' || $Table eq 'signature' ) {
        $ExtraValue = QisutuHTML->Sanitize($ExtraValue);
    }

    my $Result = $Self->{DB}->Do(
        'UPDATE ' . $Table . '
         SET name = ?,
             ' . $ExtraColumn . ' = ?,
             active = ?,
             sort_order = ?,
             changed_by_user_id = ?
         WHERE id = ?',
        $Name,
        $ExtraValue,
        $Active,
        $SortOrder,
        $UserID,
        $ID,
    );

    if ( !$Result ) {
        $Self->{LastError} = $Self->{DB}->Error() || 'Entry could not be updated';
        return;
    }

    return 1;
}

sub _MasterDataDeactivate {
    my ( $Self, %Param ) = @_;

    my $Table  = $Self->_MasterDataTable( $Param{Table} );
    my $ID     = $Param{ID} || 0;
    my $UserID = $Param{ChangedByUserID} || 1;

    return if !$Table;
    return if $ID !~ m{\A\d+\z} || !$ID;

    my $Result = $Self->{DB}->Do(
        'UPDATE ' . $Table . '
         SET active = 0,
             changed_by_user_id = ?
         WHERE id = ?',
        $UserID,
        $ID,
    );

    if ( !$Result ) {
        $Self->{LastError} = $Self->{DB}->Error() || 'Entry could not be deactivated';
        return;
    }

    return 1;
}

sub _MasterDataTable {
    my ( $Self, $Table ) = @_;

    my %Allowed = map { $_ => 1 } qw(system_email salutation signature calendar);

    return $Table if $Table && $Allowed{$Table};

    $Self->{LastError} = 'Invalid master data table';
    return;
}

sub _MasterDataColumn {
    my ( $Self, $Column ) = @_;

    my %Allowed = map { $_ => 1 } qw(email content timezone);

    return $Column if $Column && $Allowed{$Column};

    $Self->{LastError} = 'Invalid master data column';
    return;
}

sub _GroupGet {
    my ( $Self, %Param ) = @_;

    my $GroupID = $Param{GroupID} || 0;

    return if $GroupID !~ m{\A\d+\z} || !$GroupID;

    my $Group = $Self->{DB}->SelectRow(
        'SELECT id, name
         FROM user_group
         WHERE id = ?
            AND active = 1
         LIMIT 1',
        $GroupID,
    );

    if ( !$Group ) {
        $Self->{LastError} = 'Group was not found';
        return;
    }

    return $Group;
}

sub CustomerUserAutoAssignTicketCount {
    my ($Self) = @_;

    return $Self->{LastCustomerUserAutoAssignTicketCount} || 0;
}

sub _CustomerUserTicketsAutoAssign {
    my ( $Self, %Param ) = @_;

    my $CustomerID     = $Param{CustomerID} || 0;
    my $CustomerUserID = $Param{CustomerUserID} || 0;
    my $Email          = $Self->_Trim( $Param{Email} );
    my $ChangedByUserID = $Param{ChangedByUserID} || 1;

    if (
        $CustomerID !~ m{\A\d+\z} || !$CustomerID
        || $CustomerUserID !~ m{\A\d+\z} || !$CustomerUserID
        || !$Email
        )
    {
        return 0;
    }

    my $Result = $Self->{DB}->Do(
        'UPDATE ticket t
         SET t.customer_id = ?,
             t.customer_user_id = ?,
             t.changed_by_user_id = ?,
             t.changed_at = t.changed_at
         WHERE t.customer_user_id IS NULL
            AND (t.customer_id IS NULL OR t.customer_id = ?)
            AND EXISTS (
                SELECT 1
                FROM ticket_article ta
                WHERE ta.ticket_id = t.id
                    AND ta.sender_type = "customer"
                    AND LOWER(TRIM(ta.from_email)) = LOWER(TRIM(?))
                LIMIT 1
            )',
        $CustomerID,
        $CustomerUserID,
        $ChangedByUserID,
        $CustomerID,
        $Email,
    );

    if ( !defined $Result ) {
        $Self->{LastError} = $Self->{DB}->Error() || 'Existing tickets could not be assigned to the customer user';
        return;
    }

    return 0 + $Result;
}

sub _UserAccountDuplicateCheck {
    my ( $Self, %Param ) = @_;

    my $AccountType   = $Self->_Trim( $Param{AccountType} );
    my $UserAccountID = $Param{UserAccountID} || 0;
    my $Login         = $Self->_Trim( $Param{Login} );
    my $Email         = $Self->_Trim( $Param{Email} );

    return 1 if !$AccountType || !$Login || !$Email;

    my $LoginExists = $Self->{DB}->SelectRow(
        'SELECT id
         FROM user_account
         WHERE login = ?
            AND account_type = ?
            AND id <> ?
         LIMIT 1',
        $Login,
        $AccountType,
        $UserAccountID,
    );

    if ($LoginExists) {
        $Self->{LastError} = $Self->_UserAccountDuplicateMessage(
            AccountType => $AccountType,
            Field       => 'login',
            Value       => $Login,
        );
        return;
    }

    my $EmailExists = $Self->{DB}->SelectRow(
        'SELECT id
         FROM user_account
         WHERE email = ?
            AND account_type = ?
            AND id <> ?
         LIMIT 1',
        $Email,
        $AccountType,
        $UserAccountID,
    );

    if ($EmailExists) {
        $Self->{LastError} = $Self->_UserAccountDuplicateMessage(
            AccountType => $AccountType,
            Field       => 'email',
            Value       => $Email,
        );
        return;
    }

    return 1;
}

sub _UserAccountDuplicateErrorFromDB {
    my ( $Self, %Param ) = @_;

    my $Error = $Self->{DB}->Error() || '';
    return if !$Error;

    if ( $Error =~ m{user_account_login_type_unique}i ) {
        $Self->{LastError} = $Self->_UserAccountDuplicateMessage(
            AccountType => $Param{AccountType},
            Field       => 'login',
            Value       => $Param{Login},
        );
        return 1;
    }

    if ( $Error =~ m{user_account_email_type_unique}i ) {
        $Self->{LastError} = $Self->_UserAccountDuplicateMessage(
            AccountType => $Param{AccountType},
            Field       => 'email',
            Value       => $Param{Email},
        );
        return 1;
    }

    return;
}

sub _UserAccountDuplicateMessage {
    my ( $Self, %Param ) = @_;

    my $AccountType = $Self->_Trim( $Param{AccountType} );
    my $Field       = $Self->_Trim( $Param{Field} );
    my $Value       = $Self->_Trim( $Param{Value} );
    my $UserType    = $AccountType eq 'customer' ? 'customer user' : 'agent';

    if ( $Field eq 'email' ) {
        return 'The e-mail address "' . $Value . '" is already used by another ' . $UserType . '.';
    }

    return 'The login "' . $Value . '" is already used by another ' . $UserType . '.';
}

sub _RowsPrepare {
    my ( $Self, %Param ) = @_;

    my $Rows = $Param{Rows};

    if ( !$Rows ) {
        $Self->{LastError} = $Self->{DB}->Error() || 'List could not be loaded';
        return [];
    }

    for my $Row ( @{$Rows} ) {
        for my $Key ( keys %{$Row} ) {
            $Row->{$Key} = '' if !defined $Row->{$Key};
        }

        for my $SecretKey ( qw(imap_password smtp_password oauth_client_secret oauth_access_token oauth_refresh_token) ) {
            next if !exists $Row->{$SecretKey} || ( $Row->{$SecretKey} || '' ) !~ m{\Aqse1:};
            my $Plain = $Self->{Security}->Decrypt( Value => $Row->{$SecretKey} );
            if ( !defined $Plain ) {
                my $Error = $Self->{Security}->Error() || 'Stored secret could not be decrypted';
                $Self->{LastError} = $Error;
                $Row->{_secret_error} ||= $Error;
                # Keep the encrypted value intact. QisutuMail can then report
                # the actual decryption error instead of mistaking it for a
                # missing password. The value is never rendered in a password
                # input by the administration templates.
                next;
            }
            $Row->{$SecretKey} = $Plain;
        }

        if ( exists $Row->{active} ) {
            $Row->{active_label} = $Row->{active} ? 'Translate:AdminActiveYes' : 'Translate:AdminActiveNo';
        }

        if ( exists $Row->{is_active} ) {
            $Row->{active_label} = $Row->{is_active} ? 'Translate:AdminActiveYes' : 'Translate:AdminActiveNo';
        }

        if ( exists $Row->{follow_up_allowed} ) {
            $Row->{follow_up_allowed_label} = $Row->{follow_up_allowed} ? 'Translate:AdminActiveYes' : 'Translate:AdminActiveNo';
        }

        if ( exists $Row->{inbound_enabled} ) {
            $Row->{inbound_enabled_label} = $Row->{inbound_enabled} ? 'Translate:AdminActiveYes' : 'Translate:AdminActiveNo';
        }

        if ( exists $Row->{outbound_enabled} ) {
            $Row->{outbound_enabled_label} = $Row->{outbound_enabled} ? 'Translate:AdminActiveYes' : 'Translate:AdminActiveNo';
        }
    }

    return $Rows;
}

sub _SecretEncrypt {
    my ( $Self, $Value ) = @_;
    return '' if !defined $Value || $Value eq '';
    my $Encrypted = $Self->{Security}->Encrypt( Value => $Value );
    if ( !defined $Encrypted ) {
        $Self->{LastError} = $Self->{Security}->Error() || 'Secret could not be encrypted';
        return '';
    }
    return $Encrypted;
}

sub _PasswordHash {
    my ( $Self, %Param ) = @_;

    my $Password = $Param{Password} || '';
    my @Chars    = ( 'a' .. 'z', 'A' .. 'Z', 0 .. 9, '.', '/' );
    my $Salt     = '';

    for ( 1 .. 16 ) {
        $Salt .= $Chars[ int rand @Chars ];
    }

    return crypt( $Password, '$6$' . $Salt . '$' );
}

sub _Trim {
    my ( $Self, $Value ) = @_;

    $Value = '' if !defined $Value;
    $Value =~ s{\A\s+}{};
    $Value =~ s{\s+\z}{};

    return $Value;
}

sub _LanguageClean {
    my ( $Self, $Language ) = @_;

    $Language = '' if !defined $Language;
    $Language =~ s{[^A-Za-z0-9_-]}{}g;

    return $Language || 'en';
}

sub _OptionalID {
    my ( $Self, $Value ) = @_;

    $Value = 0 if !defined $Value || $Value eq '';

    return if $Value !~ m{\A\d+\z} || !$Value;

    return $Value;
}

sub _UnsignedInteger {
    my ( $Self, $Value ) = @_;

    $Value = 0 if !defined $Value || $Value eq '';

    if ( $Value !~ m{\A\d+\z} ) {
        return 0;
    }

    return $Value;
}

sub _FirstTranslationLabel {
    my ( $Self, %Param ) = @_;

    my $Labels = $Param{Labels} || {};
    my $DefaultLanguage = $Self->_LanguageClean( $Self->{Config}->{Language}->{Default} || 'en' );

    if ( $Labels->{$DefaultLanguage} ) {
        return $Self->_Trim( $Labels->{$DefaultLanguage} );
    }

    for my $Language ( sort keys %{$Labels} ) {
        my $Label = $Self->_Trim( $Labels->{$Language} );
        return $Label if $Label;
    }

    return '';
}

sub _MailIntegrationSchemaEnsure {
    my ($Self) = @_;

    return 1 if $Self->{MailIntegrationSchemaChecked};

    my @SQL = (
        'CREATE TABLE IF NOT EXISTS postmaster_imap_account (
            id BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
            name VARCHAR(100) NOT NULL,
            email VARCHAR(255) NOT NULL,
            queue_id BIGINT UNSIGNED NULL,
            imap_host VARCHAR(255) NOT NULL DEFAULT "",
            imap_security VARCHAR(30) NOT NULL DEFAULT "imap_starttls",
            imap_port INT UNSIGNED NOT NULL DEFAULT 143,
            imap_auth_type VARCHAR(30) NOT NULL DEFAULT "password",
            imap_username VARCHAR(255) NOT NULL DEFAULT "",
            imap_password TEXT NULL,
            oauth_provider VARCHAR(100) NOT NULL DEFAULT "",
            oauth_client_id TEXT NULL,
            oauth_client_secret TEXT NULL,
            oauth_tenant_id VARCHAR(255) NOT NULL DEFAULT "",
            oauth_scope TEXT NULL,
            oauth_access_token MEDIUMTEXT NULL,
            oauth_refresh_token MEDIUMTEXT NULL,
            oauth_token_expires_at DATETIME NULL,
            active TINYINT(1) NOT NULL DEFAULT 1,
            sort_order INT UNSIGNED NOT NULL DEFAULT 1000,
            last_check_at DATETIME NULL,
            last_check_status VARCHAR(30) NOT NULL DEFAULT "",
            last_check_message TEXT NULL,
            created_by_user_id BIGINT UNSIGNED NOT NULL DEFAULT 1,
            changed_by_user_id BIGINT UNSIGNED NOT NULL DEFAULT 1,
            created_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
            changed_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
            PRIMARY KEY (id),
            UNIQUE KEY postmaster_imap_account_name (name),
            KEY postmaster_imap_account_active_sort (active, sort_order),
            KEY postmaster_imap_account_queue_id (queue_id)
        ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci',

        'ALTER TABLE postmaster_imap_account
            ADD COLUMN IF NOT EXISTS queue_id BIGINT UNSIGNED NULL AFTER email,
            ADD COLUMN IF NOT EXISTS imap_host VARCHAR(255) NOT NULL DEFAULT "",
            ADD COLUMN IF NOT EXISTS imap_security VARCHAR(30) NOT NULL DEFAULT "imap_starttls",
            ADD COLUMN IF NOT EXISTS imap_port INT UNSIGNED NOT NULL DEFAULT 143,
            ADD COLUMN IF NOT EXISTS imap_auth_type VARCHAR(30) NOT NULL DEFAULT "password",
            ADD COLUMN IF NOT EXISTS imap_username VARCHAR(255) NOT NULL DEFAULT "",
            ADD COLUMN IF NOT EXISTS imap_password TEXT NULL,
            ADD COLUMN IF NOT EXISTS oauth_provider VARCHAR(100) NOT NULL DEFAULT "",
            ADD COLUMN IF NOT EXISTS oauth_client_id TEXT NULL,
            ADD COLUMN IF NOT EXISTS oauth_client_secret TEXT NULL,
            ADD COLUMN IF NOT EXISTS oauth_tenant_id VARCHAR(255) NOT NULL DEFAULT "",
            ADD COLUMN IF NOT EXISTS oauth_scope TEXT NULL,
            ADD COLUMN IF NOT EXISTS oauth_access_token MEDIUMTEXT NULL,
            ADD COLUMN IF NOT EXISTS oauth_refresh_token MEDIUMTEXT NULL,
            ADD COLUMN IF NOT EXISTS oauth_token_expires_at DATETIME NULL,
            ADD COLUMN IF NOT EXISTS active TINYINT(1) NOT NULL DEFAULT 1,
            ADD COLUMN IF NOT EXISTS sort_order INT UNSIGNED NOT NULL DEFAULT 1000,
            ADD COLUMN IF NOT EXISTS last_check_at DATETIME NULL,
            ADD COLUMN IF NOT EXISTS last_check_status VARCHAR(30) NOT NULL DEFAULT "",
            ADD COLUMN IF NOT EXISTS last_check_message TEXT NULL',

        'ALTER TABLE postmaster_imap_account
            ADD INDEX IF NOT EXISTS postmaster_imap_account_queue_id (queue_id)',

        'CREATE TABLE IF NOT EXISTS oauth2_authorization_state (
            id BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
            state_hash CHAR(64) NOT NULL,
            account_type VARCHAR(20) NOT NULL DEFAULT "imap",
            account_id BIGINT UNSIGNED NOT NULL,
            user_account_id BIGINT UNSIGNED NOT NULL,
            provider VARCHAR(30) NOT NULL,
            requested_active TINYINT(1) NOT NULL DEFAULT 1,
            return_page VARCHAR(100) NOT NULL,
            expires_at DATETIME NOT NULL,
            created_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
            PRIMARY KEY (id),
            UNIQUE KEY oauth2_authorization_state_hash_unique (state_hash),
            KEY oauth2_authorization_state_account_user (account_type, account_id, user_account_id),
            KEY oauth2_authorization_state_expires (expires_at),
            CONSTRAINT oauth2_authorization_state_user_fk FOREIGN KEY (user_account_id)
                REFERENCES user_account (id) ON DELETE CASCADE
        ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci',

        'ALTER TABLE oauth2_authorization_state
            ADD COLUMN IF NOT EXISTS account_type VARCHAR(20) NOT NULL DEFAULT "imap" AFTER state_hash',

        'CREATE TABLE IF NOT EXISTS smtp_account (
            id BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
            name VARCHAR(100) NOT NULL,
            smtp_host VARCHAR(255) NOT NULL DEFAULT "",
            smtp_security VARCHAR(30) NOT NULL DEFAULT "smtp_starttls",
            smtp_port INT UNSIGNED NOT NULL DEFAULT 587,
            smtp_auth_type VARCHAR(30) NOT NULL DEFAULT "password",
            smtp_username VARCHAR(255) NOT NULL DEFAULT "",
            smtp_password TEXT NULL,
            oauth_provider VARCHAR(100) NOT NULL DEFAULT "",
            oauth_client_id TEXT NULL,
            oauth_client_secret TEXT NULL,
            oauth_tenant_id VARCHAR(255) NOT NULL DEFAULT "",
            oauth_scope TEXT NULL,
            oauth_access_token MEDIUMTEXT NULL,
            oauth_refresh_token MEDIUMTEXT NULL,
            oauth_token_expires_at DATETIME NULL,
            active TINYINT(1) NOT NULL DEFAULT 1,
            sort_order INT UNSIGNED NOT NULL DEFAULT 1000,
            last_check_at DATETIME NULL,
            last_check_status VARCHAR(30) NOT NULL DEFAULT "",
            last_check_message TEXT NULL,
            created_by_user_id BIGINT UNSIGNED NOT NULL DEFAULT 1,
            changed_by_user_id BIGINT UNSIGNED NOT NULL DEFAULT 1,
            created_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
            changed_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
            PRIMARY KEY (id),
            UNIQUE KEY smtp_account_name (name),
            KEY smtp_account_active_sort (active, sort_order)
        ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci',

        'ALTER TABLE smtp_account
            ADD COLUMN IF NOT EXISTS smtp_host VARCHAR(255) NOT NULL DEFAULT "",
            ADD COLUMN IF NOT EXISTS smtp_security VARCHAR(30) NOT NULL DEFAULT "smtp_starttls",
            ADD COLUMN IF NOT EXISTS smtp_port INT UNSIGNED NOT NULL DEFAULT 587,
            ADD COLUMN IF NOT EXISTS smtp_auth_type VARCHAR(30) NOT NULL DEFAULT "password",
            ADD COLUMN IF NOT EXISTS smtp_username VARCHAR(255) NOT NULL DEFAULT "",
            ADD COLUMN IF NOT EXISTS smtp_password TEXT NULL,
            ADD COLUMN IF NOT EXISTS oauth_provider VARCHAR(100) NOT NULL DEFAULT "",
            ADD COLUMN IF NOT EXISTS oauth_client_id TEXT NULL,
            ADD COLUMN IF NOT EXISTS oauth_client_secret TEXT NULL,
            ADD COLUMN IF NOT EXISTS oauth_tenant_id VARCHAR(255) NOT NULL DEFAULT "",
            ADD COLUMN IF NOT EXISTS oauth_scope TEXT NULL,
            ADD COLUMN IF NOT EXISTS oauth_access_token MEDIUMTEXT NULL,
            ADD COLUMN IF NOT EXISTS oauth_refresh_token MEDIUMTEXT NULL,
            ADD COLUMN IF NOT EXISTS oauth_token_expires_at DATETIME NULL,
            ADD COLUMN IF NOT EXISTS active TINYINT(1) NOT NULL DEFAULT 1,
            ADD COLUMN IF NOT EXISTS sort_order INT UNSIGNED NOT NULL DEFAULT 1000,
            ADD COLUMN IF NOT EXISTS last_check_at DATETIME NULL,
            ADD COLUMN IF NOT EXISTS last_check_status VARCHAR(30) NOT NULL DEFAULT "",
            ADD COLUMN IF NOT EXISTS last_check_message TEXT NULL'
    );

    for my $SQL (@SQL) {
        my $OK = $Self->{DB}->Do($SQL);

        if ( !$OK ) {
            $Self->{LastError} = $Self->{DB}->Error() || 'Mail integration schema could not be prepared';
            return;
        }
    }

    $Self->{MailIntegrationSchemaChecked} = 1;

    return 1;
}



sub _IMAPAccountPrepare {
    my ( $Self, %Param ) = @_;

    my $Name         = $Self->_Trim( $Param{Name} );
    my $Email        = $Self->_Trim( $Param{Email} );
    my $QueueID      = $Param{QueueID} || 0;
    my $IMAPSecurity = $Self->_SecurityClean( $Param{IMAPSecurity}, 'imap_starttls' );
    my $IMAPAuthType = $Self->_AuthTypeClean( $Param{IMAPAuthType} );
    my $SortOrder    = $Self->_UnsignedInteger( $Param{SortOrder} ) || 1000;

    if ( !$Name || !$Email ) {
        $Self->{LastError} = 'Name and e-mail address are required';
        return;
    }

    if ( $Email !~ m{\A[^@\s]+@[^@\s]+\.[^@\s]+\z} ) {
        $Self->{LastError} = 'A valid e-mail address is required';
        return;
    }

    if ( $QueueID !~ m{\A\d+\z} || !$QueueID ) {
        $Self->{LastError} = 'Queue is required';
        return;
    }

    my $Queue = $Self->QueueGet( QueueID => $QueueID );

    if ( !$Queue ) {
        $Self->{LastError} = 'Queue is required';
        return;
    }

    my $OAuthProvider     = $Self->_Trim( $Param{OAuthProvider} );
    my $OAuthClientID     = $Self->_Trim( $Param{OAuthClientID} );
    my $OAuthClientSecret = defined $Param{OAuthClientSecret} ? $Param{OAuthClientSecret} : '';
    my $OAuthTenantID     = $Self->_Trim( $Param{OAuthTenantID} );
    my $OAuthScope        = $Self->_Trim( $Param{OAuthScope} );
    my $IMAPHost          = $Self->_Trim( $Param{IMAPHost} );
    my $IMAPPort          = $Self->_UnsignedInteger( $Param{IMAPPort} ) || $Self->_DefaultMailPort($IMAPSecurity);
    my $IMAPUsername      = $Self->_Trim( $Param{IMAPUsername} );

    if ( $IMAPAuthType eq 'oauth2' ) {
        my $OAuthObject = QisutuOAuth2->new( Config => $Self->{Config}, DB => $Self->{DB} );
        $OAuthProvider = $OAuthObject->ProviderNormalize($OAuthProvider);
        my $Definition = $OAuthObject->ProviderDefinition(
            Provider => $OAuthProvider,
            Account  => { oauth_tenant_id => $OAuthTenantID },
        );

        if ( !$Definition ) {
            $Self->{LastError} = 'Translate:AdminOAuthProviderInvalid';
            return;
        }
        if ( !$OAuthClientID ) {
            $Self->{LastError} = 'Translate:AdminOAuthClientIDRequired';
            return;
        }

        $OAuthTenantID = 'common' if $OAuthProvider eq 'microsoft' && !$OAuthTenantID;
        if ( $OAuthProvider eq 'microsoft' && $OAuthTenantID !~ m{\A[A-Za-z0-9.-]+\z} ) {
            $Self->{LastError} = 'Translate:AdminOAuthTenantInvalid';
            return;
        }

        $IMAPHost     = $Definition->{IMAPHost};
        $IMAPSecurity = $Definition->{IMAPSecurity};
        $IMAPPort     = $Definition->{IMAPPort};
        $IMAPUsername ||= $Email;
        $OAuthScope   = $Definition->{Scope};
    }
    else {
        $OAuthProvider     = '';
        $OAuthClientID     = '';
        $OAuthClientSecret = '';
        $OAuthTenantID     = '';
        $OAuthScope        = '';
    }

    return {
        Name          => $Name,
        Email         => $Email,
        QueueID       => $Queue->{id},
        IMAPHost      => $IMAPHost,
        IMAPSecurity  => $IMAPSecurity,
        IMAPPort      => $IMAPPort,
        IMAPAuthType  => $IMAPAuthType,
        IMAPUsername  => $IMAPUsername,
        IMAPPassword  => defined $Param{IMAPPassword} ? $Param{IMAPPassword} : '',
        OAuthProvider => $OAuthProvider,
        OAuthClientID => $OAuthClientID,
        OAuthClientSecret => $OAuthClientSecret,
        OAuthTenantID => $OAuthTenantID,
        OAuthScope    => $OAuthScope,
        SortOrder     => $SortOrder,
    };
}

sub _SMTPAccountPrepare {
    my ( $Self, %Param ) = @_;

    my $Name         = $Self->_Trim( $Param{Name} );
    my $SMTPSecurity = $Self->_SecurityClean( $Param{SMTPSecurity}, 'smtp_starttls' );
    my $SMTPAuthType = $Self->_AuthTypeClean( $Param{SMTPAuthType} );
    my $SortOrder    = $Self->_UnsignedInteger( $Param{SortOrder} ) || 1000;

    if ( !$Name ) {
        $Self->{LastError} = 'Name is required';
        return;
    }

    my $OAuthProvider     = $Self->_Trim( $Param{OAuthProvider} );
    my $OAuthClientID     = $Self->_Trim( $Param{OAuthClientID} );
    my $OAuthClientSecret = defined $Param{OAuthClientSecret} ? $Param{OAuthClientSecret} : '';
    my $OAuthTenantID     = $Self->_Trim( $Param{OAuthTenantID} );
    my $OAuthScope        = $Self->_Trim( $Param{OAuthScope} );
    my $SMTPHost          = $Self->_Trim( $Param{SMTPHost} );
    my $SMTPPort          = $Self->_UnsignedInteger( $Param{SMTPPort} ) || $Self->_DefaultMailPort($SMTPSecurity);
    my $SMTPUsername      = $Self->_Trim( $Param{SMTPUsername} );

    if ( !$SMTPUsername ) {
        $Self->{LastError} = 'Translate:AdminSMTPCredentialsRequired';
        return;
    }

    if ( $SMTPAuthType eq 'oauth2' ) {
        my $OAuthObject = QisutuOAuth2->new( Config => $Self->{Config}, DB => $Self->{DB} );
        $OAuthProvider = $OAuthObject->ProviderNormalize($OAuthProvider);
        my $Definition = $OAuthObject->ProviderDefinition(
            Provider    => $OAuthProvider,
            AccountType => 'smtp',
            Account     => { oauth_tenant_id => $OAuthTenantID },
        );
        if ( !$Definition ) {
            $Self->{LastError} = 'Translate:AdminOAuthProviderInvalid';
            return;
        }
        if ( !$OAuthClientID ) {
            $Self->{LastError} = 'Translate:AdminOAuthClientIDRequired';
            return;
        }
        $OAuthTenantID = 'common' if $OAuthProvider eq 'microsoft' && !$OAuthTenantID;
        if ( $OAuthProvider eq 'microsoft' && $OAuthTenantID !~ m{\A[A-Za-z0-9.-]+\z} ) {
            $Self->{LastError} = 'Translate:AdminOAuthTenantInvalid';
            return;
        }
        $SMTPHost     = $Definition->{SMTPHost};
        $SMTPSecurity = $Definition->{SMTPSecurity};
        $SMTPPort     = $Definition->{SMTPPort};
        $OAuthScope   = $Definition->{Scope};
    }
    else {
        $OAuthProvider     = '';
        $OAuthClientID     = '';
        $OAuthClientSecret = '';
        $OAuthTenantID     = '';
        $OAuthScope        = '';
        if ( !$SMTPHost ) {
            $Self->{LastError} = 'Translate:AdminSMTPHostRequired';
            return;
        }
    }

    return {
        Name          => $Name,
        SMTPHost      => $SMTPHost,
        SMTPSecurity  => $SMTPSecurity,
        SMTPPort      => $SMTPPort,
        SMTPAuthType  => $SMTPAuthType,
        SMTPUsername  => $SMTPUsername,
        SMTPPassword  => defined $Param{SMTPPassword} ? $Param{SMTPPassword} : '',
        OAuthProvider => $OAuthProvider,
        OAuthClientID => $OAuthClientID,
        OAuthClientSecret => $OAuthClientSecret,
        OAuthTenantID => $OAuthTenantID,
        OAuthScope    => $OAuthScope,
        SortOrder     => $SortOrder,
    };
}

sub _IMAPAccountFromPrepared {
    my ( $Self, %Param ) = @_;

    my $Prepared = $Param{Prepared} || {};
    my $Existing = $Param{Existing} || {};

    return {
        inbound_enabled     => 1,
        imap_host           => $Prepared->{IMAPHost},
        imap_security       => $Prepared->{IMAPSecurity},
        imap_port           => $Prepared->{IMAPPort},
        imap_auth_type      => $Prepared->{IMAPAuthType},
        imap_username       => $Prepared->{IMAPUsername},
        imap_password       => $Prepared->{IMAPPassword} ne '' ? $Prepared->{IMAPPassword} : ( $Existing->{imap_password} || '' ),
        oauth_provider      => $Prepared->{OAuthProvider},
        oauth_client_id     => $Prepared->{OAuthClientID},
        oauth_client_secret => $Prepared->{OAuthClientSecret} ne '' ? $Prepared->{OAuthClientSecret} : ( $Existing->{oauth_client_secret} || '' ),
        oauth_tenant_id     => $Prepared->{OAuthTenantID},
        oauth_scope         => $Prepared->{OAuthScope},
    };
}

sub _SMTPAccountFromPrepared {
    my ( $Self, %Param ) = @_;

    my $Prepared = $Param{Prepared} || {};
    my $Existing = $Param{Existing} || {};

    return {
        outbound_enabled    => 1,
        smtp_host           => $Prepared->{SMTPHost},
        smtp_security       => $Prepared->{SMTPSecurity},
        smtp_port           => $Prepared->{SMTPPort},
        smtp_auth_type      => $Prepared->{SMTPAuthType},
        smtp_username       => $Prepared->{SMTPUsername},
        smtp_password       => $Prepared->{SMTPPassword} ne '' ? $Prepared->{SMTPPassword} : ( $Existing->{smtp_password} || '' ),
        oauth_provider      => $Prepared->{OAuthProvider},
        oauth_client_id     => $Prepared->{OAuthClientID},
        oauth_client_secret => $Prepared->{OAuthClientSecret} ne '' ? $Prepared->{OAuthClientSecret} : ( $Existing->{oauth_client_secret} || '' ),
        oauth_tenant_id     => $Prepared->{OAuthTenantID},
        oauth_scope         => $Prepared->{OAuthScope},
    };
}

sub _SecurityClean {
    my ( $Self, $Value, $Default ) = @_;

    my %Allowed = map { $_ => 1 } qw(smtp smtp_starttls smtps imap imap_starttls imaps);

    $Value = $Self->_Trim($Value);

    return $Allowed{$Value} ? $Value : $Default;
}

sub _AuthTypeClean {
    my ( $Self, $Value ) = @_;

    my %Allowed = map { $_ => 1 } qw(password oauth2);

    $Value = $Self->_Trim($Value);

    return $Allowed{$Value} ? $Value : 'password';
}

sub _DefaultMailPort {
    my ( $Self, $Security ) = @_;

    my %Port = (
        smtp          => 25,
        smtp_starttls => 587,
        smtps         => 465,
        imap          => 143,
        imap_starttls => 143,
        imaps         => 993,
    );

    return $Port{$Security} || 0;
}

sub Error {
    my ($Self) = @_;

    return $Self->{LastError};
}

1;
