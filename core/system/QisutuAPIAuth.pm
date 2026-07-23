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

package QisutuAPIAuth;

use strict;
use warnings;
use utf8;

use Digest::SHA qw(sha256_hex);
use JSON::PP ();

sub new {
    my ( $Class, %Param ) = @_;
    my $Self = {
        Config    => $Param{Config},
        DB        => $Param{DB},
        LastError => '',
    };
    bless $Self, $Class;
    return $Self;
}

sub ScopeDefinitions {
    my ($Self) = @_;
    my @Definition = (
        { Key => 'tickets.read',          Label => 'APIScopeTicketsRead',          Group => 'tickets' },
        { Key => 'tickets.create',        Label => 'APIScopeTicketsCreate',        Group => 'tickets' },
        { Key => 'tickets.status',        Label => 'APIScopeTicketsStatus',        Group => 'tickets' },
        { Key => 'tickets.properties',    Label => 'APIScopeTicketsProperties',    Group => 'tickets' },
        { Key => 'tickets.articles',      Label => 'APIScopeTicketArticles',       Group => 'communication' },
        { Key => 'tickets.internal_notes',Label => 'APIScopeInternalNotes',        Group => 'communication' },
        { Key => 'tickets.attachments',   Label => 'APIScopeAttachments',          Group => 'communication' },
        { Key => 'master_data.read',      Label => 'APIScopeMasterDataRead',       Group => 'data' },
        { Key => 'customers.read',        Label => 'APIScopeCustomersRead',        Group => 'customers' },
        { Key => 'customers.write',       Label => 'APIScopeCustomersWrite',       Group => 'customers', AdminOnly => 1 },
    );
    my %Known = map { $_->{Key} => 1 } @Definition;
    for my $Route ( @{ ( $Self->{Config}->{AddonRuntime} || {} )->{RESTRoutes} || [] } ) {
        next if ref $Route ne 'HASH';
        for my $Scope ( @{ ref $Route->{scopes} eq 'ARRAY' ? $Route->{scopes} : [] } ) {
            next if !$Scope || $Known{$Scope}++;
            push @Definition, {
                Key   => $Scope,
                Label => $Scope,
                Group => 'addons',
            };
        }
    }
    return \@Definition;
}

sub ScopeAllowed {
    my ( $Self, %Param ) = @_;
    my $Token = $Param{Token} || {};
    my $Scope = $Param{Scope} || '';
    return 0 if !$Scope;
    my %Allowed = map { $_ => 1 } @{ $Token->{scopes} || [] };
    return $Allowed{$Scope} ? 1 : 0;
}

sub TokenCreate {
    my ( $Self, %Param ) = @_;

    my $UserAccountID = $Self->_ID( $Param{UserAccountID} );
    my $ChangedBy     = $Self->_ID( $Param{ChangedByUserID} );
    my $Label         = $Self->_Trim( $Param{Label} );
    my $Scopes        = ref $Param{Scopes} eq 'ARRAY' ? $Param{Scopes} : [];
    my $AllowedIPs    = $Self->_AllowedIPsNormalize( $Param{AllowedIPs} );
    my $RateLimit     = $Param{RateLimitPerMinute} || 120;
    my $Lifetime      = $Param{Lifetime} || 'never';

    if ( !$UserAccountID || !$ChangedBy || !$Label ) {
        $Self->{LastError} = 'API token user and label are required';
        return;
    }
    if ( length($Label) > 190 ) {
        $Self->{LastError} = 'API token label is too long';
        return;
    }
    if ( !defined $AllowedIPs ) {
        $Self->{LastError} = 'API allowed IP address list is invalid';
        return;
    }

    my $User = $Self->{DB}->SelectRow(
        'SELECT id, account_type, is_active, is_system_user
         FROM user_account
         WHERE id = ? AND is_active = 1 AND is_system_user = 0
         LIMIT 1',
        $UserAccountID,
    );
    if (!$User) {
        $Self->{LastError} = 'API user was not found or is inactive';
        return;
    }

    my %Known = map { $_->{Key} => $_ } @{ $Self->ScopeDefinitions() };
    my %Seen;
    my @Scopes;
    for my $Scope ( @{$Scopes} ) {
        next if !$Known{$Scope} || $Seen{$Scope}++;
        push @Scopes, $Scope;
    }
    if (!@Scopes) {
        $Self->{LastError} = 'At least one API permission is required';
        return;
    }

    $RateLimit = 120 if $RateLimit !~ m{\A\d+\z};
    $RateLimit = 10 if $RateLimit < 10;
    $RateLimit = 5000 if $RateLimit > 5000;

    my %LifetimeSQL = (
        '30d'  => 'DATE_ADD(NOW(), INTERVAL 30 DAY)',
        '90d'  => 'DATE_ADD(NOW(), INTERVAL 90 DAY)',
        '365d' => 'DATE_ADD(NOW(), INTERVAL 365 DAY)',
        never  => 'NULL',
    );
    my $ExpiresSQL = $LifetimeSQL{$Lifetime} || $LifetimeSQL{never};

    my $Secret = $Self->_RandomHex(48);
    if (!$Secret) {
        $Self->{LastError} = 'Secure API token generation failed';
        return;
    }
    my $PlainToken = 'qst_' . $Secret;
    my $Prefix     = substr( $PlainToken, 0, 16 );
    my $Hash       = sha256_hex($PlainToken);
    my $ScopeJSON  = JSON::PP->new->canonical(1)->encode(\@Scopes);

    my $Result = $Self->{DB}->Do(
        'INSERT INTO api_token (
            user_account_id, label, token_prefix, token_hash, scopes_json,
            allowed_ips, rate_limit_per_minute, active, expires_at,
            created_by_user_id, changed_by_user_id
         ) VALUES (?, ?, ?, ?, ?, ?, ?, 1, ' . $ExpiresSQL . ', ?, ?)',
        $UserAccountID,
        $Label,
        $Prefix,
        $Hash,
        $ScopeJSON,
        $AllowedIPs,
        $RateLimit,
        $ChangedBy,
        $ChangedBy,
    );
    if (!$Result) {
        $Self->{LastError} = $Self->{DB}->Error() || 'API token could not be stored';
        return;
    }

    return {
        ID         => $Self->{DB}->LastInsertID('api_token'),
        PlainToken => $PlainToken,
        Prefix     => $Prefix,
        Scopes     => \@Scopes,
    };
}

sub TokenList {
    my ( $Self, %Param ) = @_;
    my $Rows = $Self->{DB}->SelectAll(
        'SELECT
            at.id, at.user_account_id, at.label, at.token_prefix, at.scopes_json,
            at.allowed_ips, at.rate_limit_per_minute, at.active, at.expires_at,
            at.last_used_at, at.last_used_ip, at.created_at,
            ua.login, ua.email, ua.firstname, ua.lastname, ua.account_type, ua.is_active
         FROM api_token at
         INNER JOIN user_account ua ON ua.id = at.user_account_id
         ORDER BY at.active DESC, at.created_at DESC, at.id DESC'
    ) || [];
    for my $Row ( @{$Rows} ) {
        $Row->{scopes} = $Self->_ScopesDecode( $Row->{scopes_json} );
        $Row->{user_name} = $Self->_UserName($Row);
        $Row->{expired} = $Row->{expires_at} && $Row->{expires_at} lt $Self->_Now() ? 1 : 0;
    }
    return $Rows;
}

sub TokenDeactivate {
    my ( $Self, %Param ) = @_;
    my $TokenID   = $Self->_ID( $Param{TokenID} );
    my $ChangedBy = $Self->_ID( $Param{ChangedByUserID} );
    return if !$TokenID || !$ChangedBy;
    my $Result = $Self->{DB}->Do(
        'UPDATE api_token
         SET active = 0, changed_by_user_id = ?, changed_at = NOW()
         WHERE id = ? AND active = 1',
        $ChangedBy,
        $TokenID,
    );
    if (!$Result) {
        $Self->{LastError} = $Self->{DB}->Error() || 'API token could not be deactivated';
        return;
    }
    return 1;
}

sub UserSearch {
    my ( $Self, %Param ) = @_;
    my $Search = $Self->_Trim( $Param{Search} );
    my $Like = '%' . $Self->_LikeEscape($Search) . '%';
    my $Rows = $Self->{DB}->SelectAll(
        'SELECT
            ua.id AS user_account_id, ua.login, ua.email, ua.firstname, ua.lastname,
            ua.account_type, c.name AS customer_name
         FROM user_account ua
         LEFT JOIN customer_user cu ON cu.user_account_id = ua.id AND cu.active = 1
         LEFT JOIN customer c ON c.id = cu.customer_id
         WHERE ua.is_active = 1
           AND ua.is_system_user = 0
           AND (? = "" OR ua.login LIKE ? ESCAPE "\\\\" OR ua.email LIKE ? ESCAPE "\\\\"
                OR ua.firstname LIKE ? ESCAPE "\\\\" OR ua.lastname LIKE ? ESCAPE "\\\\"
                OR c.name LIKE ? ESCAPE "\\\\")
         ORDER BY ua.account_type ASC, ua.lastname ASC, ua.firstname ASC, ua.login ASC
         LIMIT 50',
        $Search, $Like, $Like, $Like, $Like, $Like,
    ) || [];
    for my $Row ( @{$Rows} ) {
        $Row->{user_name} = $Self->_UserName($Row);
    }
    return $Rows;
}

sub UserGet {
    my ( $Self, %Param ) = @_;
    my $UserAccountID = $Self->_ID( $Param{UserAccountID} );
    return if !$UserAccountID;

    my $Row = $Self->{DB}->SelectRow(
        'SELECT
            ua.id AS user_account_id, ua.login, ua.email, ua.firstname, ua.lastname,
            ua.account_type, c.name AS customer_name
         FROM user_account ua
         LEFT JOIN customer_user cu ON cu.user_account_id = ua.id AND cu.active = 1
         LEFT JOIN customer c ON c.id = cu.customer_id
         WHERE ua.id = ?
           AND ua.is_active = 1
           AND ua.is_system_user = 0
         LIMIT 1',
        $UserAccountID,
    );
    return if !$Row;
    $Row->{user_name} = $Self->_UserName($Row);
    return $Row;
}

sub Authenticate {
    my ( $Self, %Param ) = @_;
    my $PlainToken = $Param{PlainToken} || '';
    my $RemoteIP   = $Param{RemoteIP} || '';
    if ( $PlainToken !~ m{\Aqst_[0-9a-f]{96}\z} ) {
        $Self->{LastError} = 'invalid_token';
        return;
    }

    my $Row = $Self->{DB}->SelectRow(
        'SELECT
            at.id AS api_token_id, at.user_account_id, at.label AS api_token_label,
            at.scopes_json, at.allowed_ips, at.rate_limit_per_minute, at.expires_at,
            ua.login, ua.account_type, ua.email, ua.firstname, ua.lastname, ua.is_active,
            ua.is_system_user, cu.id AS customer_user_id, cu.customer_id
         FROM api_token at
         INNER JOIN user_account ua ON ua.id = at.user_account_id
         LEFT JOIN customer_user cu ON cu.user_account_id = ua.id AND cu.active = 1
         WHERE at.token_hash = ?
           AND at.active = 1
           AND (at.expires_at IS NULL OR at.expires_at > NOW())
           AND ua.is_active = 1
           AND ua.is_system_user = 0
         LIMIT 1',
        sha256_hex($PlainToken),
    );
    if (!$Row) {
        $Self->{LastError} = 'invalid_token';
        return;
    }
    if ( !$Self->_IPAllowed( RemoteIP => $RemoteIP, AllowedIPs => $Row->{allowed_ips} ) ) {
        $Self->{LastError} = 'ip_not_allowed';
        return;
    }

    my $Rate = $Self->{DB}->SelectRow(
        'SELECT COUNT(*) AS request_count
         FROM api_request_log
         WHERE api_token_id = ? AND created_at >= DATE_SUB(NOW(), INTERVAL 1 MINUTE)',
        $Row->{api_token_id},
    );
    if ( $Rate && ( $Rate->{request_count} || 0 ) >= ( $Row->{rate_limit_per_minute} || 120 ) ) {
        $Self->{LastError} = 'rate_limit_exceeded';
        return;
    }

    $Self->{DB}->Do(
        'UPDATE api_token SET last_used_at = NOW(), last_used_ip = ? WHERE id = ?',
        $RemoteIP,
        $Row->{api_token_id},
    );

    $Row->{scopes} = $Self->_ScopesDecode( $Row->{scopes_json} );
    return $Row;
}

sub RequestLogCreate {
    my ( $Self, %Param ) = @_;
    return $Self->{DB}->Do(
        'INSERT INTO api_request_log (
            request_id, api_token_id, user_account_id, method, request_path,
            status_code, remote_ip, duration_ms, result_code, resource_type, resource_id
         ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)',
        $Param{RequestID} || '',
        $Param{TokenID} || undef,
        $Param{UserID} || undef,
        substr( $Param{Method} || '', 0, 10 ),
        substr( $Param{Path} || '', 0, 500 ),
        $Param{StatusCode} || 500,
        substr( $Param{RemoteIP} || '', 0, 45 ),
        $Param{DurationMS} || 0,
        substr( $Param{ResultCode} || '', 0, 100 ),
        substr( $Param{ResourceType} || '', 0, 50 ),
        $Param{ResourceID} || undef,
    );
}

sub RequestLogList {
    my ( $Self, %Param ) = @_;
    my $Limit = $Param{Limit} || 100;
    $Limit = 20 if $Limit < 20;
    $Limit = 500 if $Limit > 500;
    return $Self->{DB}->SelectAll(
        'SELECT l.*, at.label AS token_label, at.token_prefix, ua.login, ua.email
         FROM api_request_log l
         LEFT JOIN api_token at ON at.id = l.api_token_id
         LEFT JOIN user_account ua ON ua.id = l.user_account_id
         ORDER BY l.created_at DESC, l.id DESC LIMIT ' . int($Limit)
    ) || [];
}

sub IdempotencyGet {
    my ( $Self, %Param ) = @_;
    my $Row = $Self->{DB}->SelectRow(
        'SELECT method, request_path, request_hash, status_code, response_json
         FROM api_idempotency
         WHERE api_token_id = ? AND idempotency_key = ? AND expires_at > NOW()
         LIMIT 1',
        $Param{TokenID},
        $Param{Key},
    );
    return $Row;
}

sub IdempotencyStore {
    my ( $Self, %Param ) = @_;
    $Self->{DB}->Do('DELETE FROM api_idempotency WHERE expires_at <= NOW()');
    return $Self->{DB}->Do(
        'INSERT INTO api_idempotency (
            api_token_id, idempotency_key, method, request_path, request_hash,
            status_code, response_json, expires_at
         ) VALUES (?, ?, ?, ?, ?, ?, ?, DATE_ADD(NOW(), INTERVAL 24 HOUR))',
        $Param{TokenID}, $Param{Key}, $Param{Method}, $Param{Path},
        $Param{RequestHash}, $Param{StatusCode}, $Param{ResponseJSON},
    );
}

sub Error { return $_[0]->{LastError} || ''; }

sub _RandomHex {
    my ( $Self, $Bytes ) = @_;
    $Bytes ||= 32;
    open my $FH, '<:raw', '/dev/urandom' or return;
    my $Data = '';
    my $Read = read $FH, $Data, $Bytes;
    close $FH;
    return if !$Read || $Read != $Bytes;
    return unpack 'H*', $Data;
}

sub _ScopesDecode {
    my ( $Self, $JSON ) = @_;
    my $Data = eval { JSON::PP->new->decode( $JSON || '[]' ) };
    return ref $Data eq 'ARRAY' ? $Data : [];
}

sub _AllowedIPsNormalize {
    my ( $Self, $Value ) = @_;
    $Value = $Self->_Trim($Value);
    return '' if !$Value;
    my @Items = grep {$_} map { $Self->_Trim($_) } split m{[,\r\n]+}, $Value;
    return if @Items > 100;
    for my $IP (@Items) {
        return if $IP !~ m{\A(?:[0-9a-fA-F:.]+)\z};
    }
    return join ',', @Items;
}

sub _IPAllowed {
    my ( $Self, %Param ) = @_;
    my $Allowed = $Param{AllowedIPs} || '';
    return 1 if !$Allowed;
    my $Remote = lc( $Param{RemoteIP} || '' );
    return 0 if !$Remote;
    return scalar grep { lc( $Self->_Trim($_) ) eq $Remote } split m{,}, $Allowed;
}

sub _UserName {
    my ( $Self, $User ) = @_;
    my $Name = $Self->_Trim( join ' ', grep { defined && $_ ne '' } ( $User->{firstname}, $User->{lastname} ) );
    return $Name || $User->{login} || $User->{email} || '-';
}

sub _Now {
    my @T = localtime();
    return sprintf '%04d-%02d-%02d %02d:%02d:%02d', $T[5] + 1900, $T[4] + 1, $T[3], $T[2], $T[1], $T[0];
}

sub _ID {
    my ( $Self, $Value ) = @_;
    return $Value && $Value =~ m{\A\d+\z} ? int($Value) : 0;
}

sub _Trim {
    my ( $Self, $Value ) = @_;
    $Value = '' if !defined $Value;
    $Value =~ s{\A\s+|\s+\z}{}g;
    return $Value;
}

sub _LikeEscape {
    my ( $Self, $Value ) = @_;
    $Value =~ s{([%_\\])}{\\$1}g;
    return $Value;
}

1;
