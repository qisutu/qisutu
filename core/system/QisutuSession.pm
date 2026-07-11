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

package QisutuSession;

use strict;
use warnings;
use utf8;

use Digest::SHA qw(sha256_hex);

sub new {
    my ( $Class, %Param ) = @_;

    my $Self = {
        DB        => $Param{DB},
        Config    => $Param{Config},
        LastError => '',
    };

    bless $Self, $Class;

    return $Self;
}

sub Create {
    my ( $Self, %Param ) = @_;

    my $UserID    = $Param{UserID};
    my $IPAddress = $Param{IPAddress} || '';
    my $UserAgent = $Param{UserAgent} || '';

    if ( !$UserID ) {
        $Self->{LastError} = 'UserID is required';
        return;
    }

    if ( length $UserAgent > 255 ) {
        $UserAgent = substr( $UserAgent, 0, 255 );
    }

    my $Token     = $Self->_TokenCreate();
    my $TokenHash = $Self->_TokenHash( Token => $Token );
    my $Lifetime  = $Self->{Config}->{Session}->{LifetimeSeconds} || 28800;

    my $Result = $Self->{DB}->Do(
        'INSERT INTO user_session (
             user_account_id,
             session_token_hash,
             ip_address,
             user_agent,
             is_active,
             created_at,
             last_seen_at,
             expires_at
         ) VALUES (
             ?, ?, ?, ?, 1, NOW(), NOW(), DATE_ADD(NOW(), INTERVAL ? SECOND)
         )',
        $UserID,
        $TokenHash,
        $IPAddress,
        $UserAgent,
        $Lifetime,
    );

    if ( !$Result ) {
        $Self->{LastError} = $Self->{DB}->Error() || 'Session could not be created';
        return;
    }

    return {
        Token     => $Token,
        TokenHash => $TokenHash,
        UserID    => $UserID,
    };
}

sub Get {
    my ( $Self, %Param ) = @_;

    my $Token = $Param{Token} || '';

    if ( !$Token ) {
        $Self->{LastError} = 'Session token is required';
        return;
    }

    my $TokenHash = $Self->_TokenHash( Token => $Token );

    my $Session = $Self->{DB}->SelectRow(
        'SELECT
             s.id,
             s.user_account_id,
             s.session_token_hash,
             s.ip_address,
             s.user_agent,
             s.created_at,
             s.last_seen_at,
             s.expires_at,
             u.login,
             u.account_type,
             u.email,
             u.firstname,
             u.lastname,
             u.is_active,
             u.is_system_user,
             cu.id AS customer_user_id,
             cu.customer_id,
             c.customer_number,
             c.name AS customer_name
         FROM user_session s
         INNER JOIN user_account u
             ON u.id = s.user_account_id
         LEFT JOIN customer_user cu
             ON cu.user_account_id = u.id
             AND cu.active = 1
         LEFT JOIN customer c
             ON c.id = cu.customer_id
             AND c.active = 1
         WHERE s.session_token_hash = ?
             AND s.is_active = 1
             AND s.expires_at > NOW()
         LIMIT 1',
        $TokenHash,
    );

    if ( !$Session ) {
        $Self->{LastError} = 'Session is invalid or expired';
        return;
    }

    if ( !$Session->{is_active} ) {
        $Self->{LastError} = 'User account is inactive';
        return;
    }

    return $Session;
}

sub Touch {
    my ( $Self, %Param ) = @_;

    my $Token = $Param{Token} || '';

    if ( !$Token ) {
        $Self->{LastError} = 'Session token is required';
        return;
    }

    my $TokenHash = $Self->_TokenHash( Token => $Token );
    my $Lifetime  = $Self->{Config}->{Session}->{LifetimeSeconds} || 28800;

    my $Result = $Self->{DB}->Do(
        'UPDATE user_session
         SET last_seen_at = NOW(),
             expires_at = DATE_ADD(NOW(), INTERVAL ? SECOND)
         WHERE session_token_hash = ?
             AND is_active = 1
             AND expires_at > NOW()',
        $Lifetime,
        $TokenHash,
    );

    if ( !$Result ) {
        $Self->{LastError} = $Self->{DB}->Error() || 'Session could not be updated';
        return;
    }

    return 1;
}

sub Delete {
    my ( $Self, %Param ) = @_;

    my $Token = $Param{Token} || '';

    if ( !$Token ) {
        $Self->{LastError} = 'Session token is required';
        return;
    }

    my $TokenHash = $Self->_TokenHash( Token => $Token );

    my $Result = $Self->{DB}->Do(
        'UPDATE user_session
         SET is_active = 0
         WHERE session_token_hash = ?',
        $TokenHash,
    );

    if ( !$Result ) {
        $Self->{LastError} = $Self->{DB}->Error() || 'Session could not be deleted';
        return;
    }

    return 1;
}

sub DeleteExpired {
    my ($Self) = @_;

    my $Result = $Self->{DB}->Do(
        'UPDATE user_session
         SET is_active = 0
         WHERE is_active = 1
             AND expires_at <= NOW()',
    );

    if ( !$Result ) {
        $Self->{LastError} = $Self->{DB}->Error() || 'Expired sessions could not be deleted';
        return;
    }

    return 1;
}

sub _TokenCreate {
    my ($Self) = @_;

    my $Random = '';

    if ( open my $RandomHandle, '<', '/dev/urandom' ) {
        read $RandomHandle, $Random, 32;
        close $RandomHandle;
    }

    if ( length $Random < 32 ) {
        $Random .= time() . $$ . rand() . {};
    }

    return sha256_hex( $Random . time() . $$ . rand() );
}

sub _TokenHash {
    my ( $Self, %Param ) = @_;

    my $Token = $Param{Token} || '';

    return sha256_hex($Token);
}

sub Error {
    my ($Self) = @_;

    return $Self->{LastError};
}

1;
