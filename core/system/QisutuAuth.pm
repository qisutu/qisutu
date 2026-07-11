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

package QisutuAuth;

use strict;
use warnings;
use utf8;

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

sub LoginCheck {
    my ( $Self, %Param ) = @_;

    my $Login       = $Param{Login}       || '';
    my $Password    = $Param{Password}    || '';
    my $AccountType = $Param{AccountType} || '';

    $Login =~ s/^\s+//;
    $Login =~ s/\s+$//;

    if ( $AccountType ne 'agent' && $AccountType ne 'customer' ) {
        $Self->{LastError} = 'Valid account type is required';
        return;
    }

    if ( !$Login || !$Password ) {
        $Self->{LastError} = 'Login, password and account type are required';
        return;
    }

    my $User = $Self->{DB}->SelectRow(
        'SELECT id, login, account_type, email, password_hash, firstname, lastname, is_active, failed_login_count, locked_until
         FROM user_account
         WHERE login = ?
            AND account_type = ?
         LIMIT 1',
        $Login,
        $AccountType,
    );

    if ( !$User ) {
        $Self->{LastError} = 'Invalid login or password';
        return;
    }

    if ( !$User->{is_active} ) {
        $Self->{LastError} = 'User account is inactive';
        return;
    }

    if ( $User->{locked_until} ) {
        my $Locked = $Self->{DB}->SelectRow(
            'SELECT CASE WHEN locked_until > NOW() THEN 1 ELSE 0 END AS is_locked
             FROM user_account
             WHERE id = ?',
            $User->{id},
        );

        if ( $Locked && $Locked->{is_locked} ) {
            $Self->{LastError} = 'User account is temporarily locked';
            return;
        }
    }

    my $PasswordOK = $Self->_PasswordVerify(
        Password     => $Password,
        PasswordHash => $User->{password_hash},
    );

    if ( !$PasswordOK ) {
        $Self->_FailedLoginIncrease( UserID => $User->{id} );
        $Self->{LastError} = 'Invalid login or password';
        return;
    }

    $Self->{DB}->Do(
        'UPDATE user_account
         SET failed_login_count = 0,
             locked_until = NULL,
             last_login_at = NOW()
         WHERE id = ?',
        $User->{id},
    );

    delete $User->{password_hash};
    delete $User->{failed_login_count};
    delete $User->{locked_until};

    return $User;
}

sub _PasswordVerify {
    my ( $Self, %Param ) = @_;

    my $Password     = $Param{Password}     || '';
    my $PasswordHash = $Param{PasswordHash} || '';

    return if !$Password || !$PasswordHash;

    my $CheckHash = crypt( $Password, $PasswordHash );

    return if !$CheckHash;
    return if $CheckHash ne $PasswordHash;

    return 1;
}

sub _FailedLoginIncrease {
    my ( $Self, %Param ) = @_;

    my $UserID = $Param{UserID};

    return if !$UserID;

    $Self->{DB}->Do(
        'UPDATE user_account
         SET failed_login_count = failed_login_count + 1,
             locked_until = CASE
                 WHEN failed_login_count + 1 >= 5 THEN DATE_ADD(NOW(), INTERVAL 15 MINUTE)
                 ELSE locked_until
             END
         WHERE id = ?',
        $UserID,
    );

    return 1;
}

sub Error {
    my ($Self) = @_;

    return $Self->{LastError};
}

1;
