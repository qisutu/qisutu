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

package QisutuUserPreference;

use strict;
use warnings;
use utf8;

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

sub AgentPreferenceGet {
    my ( $Self, %Param ) = @_;

    my $UserAccountID = $Param{UserAccountID} || 0;

    return $Self->_DefaultAgentPreferences() if $UserAccountID !~ m{\A\d+\z} || !$UserAccountID;

    my $Preference = $Self->_DefaultAgentPreferences();
    my $Rows       = $Self->{DB}->SelectAll(
        'SELECT preference_key, preference_value
         FROM user_preference
         WHERE user_account_id = ?',
        $UserAccountID,
    );

    if ( ref $Rows eq 'ARRAY' ) {
        for my $Row ( @{$Rows} ) {
            next if ref $Row ne 'HASH';
            my $Key = $Row->{preference_key} || '';
            next if !exists $Preference->{$Key};

            $Preference->{$Key} = defined $Row->{preference_value} ? $Row->{preference_value} : '';
        }
    }

    $Preference->{language} = $Self->_LanguageClean( $Preference->{language} );
    $Preference->{timezone} = $Self->_TimezoneClean( $Preference->{timezone} );
    $Preference->{start_page} = $Self->_StartPageClean( $Preference->{start_page} );
    $Preference->{ticket_after_reply_action} = $Self->_AfterReplyActionClean( $Preference->{ticket_after_reply_action} );
    $Preference->{ticket_list_limit} = $Self->_TicketListLimitClean( $Preference->{ticket_list_limit} );
    $Preference->{absence_active} = $Preference->{absence_active} ? 1 : 0;
    $Preference->{absence_replacement_user_id} = $Self->_UserIDClean( $Preference->{absence_replacement_user_id} );

    for my $Key (qw(
        notification_new_ticket
        notification_customer_reply
        notification_assigned_ticket
        notification_status_change
    )) {
        $Preference->{$Key} = $Preference->{$Key} ? 1 : 0;
    }

    return $Preference;
}


sub CustomerPreferenceGet {
    my ( $Self, %Param ) = @_;

    my $UserAccountID = $Param{UserAccountID} || 0;

    return $Self->_DefaultCustomerPreferences() if $UserAccountID !~ m{\A\d+\z} || !$UserAccountID;

    my $Preference = $Self->_DefaultCustomerPreferences();
    my $Rows       = $Self->{DB}->SelectAll(
        'SELECT preference_key, preference_value
         FROM user_preference
         WHERE user_account_id = ?',
        $UserAccountID,
    );

    if ( ref $Rows eq 'ARRAY' ) {
        for my $Row ( @{$Rows} ) {
            next if ref $Row ne 'HASH';
            my $Key = $Row->{preference_key} || '';
            next if !exists $Preference->{$Key};

            $Preference->{$Key} = defined $Row->{preference_value} ? $Row->{preference_value} : '';
        }
    }

    $Preference->{language} = $Self->_LanguageClean( $Preference->{language} );
    $Preference->{timezone} = $Self->_TimezoneClean( $Preference->{timezone} );

    return $Preference;
}

sub CustomerPreferenceSave {
    my ( $Self, %Param ) = @_;

    my $UserAccountID = $Param{UserAccountID} || 0;
    my $Request       = $Param{Request}       || {};

    if ( $UserAccountID !~ m{\A\d+\z} || !$UserAccountID ) {
        $Self->{LastError} = 'User account is required.';
        return;
    }

    my %Preference = (
        language => $Self->_LanguageClean(
            exists $Request->{PreferenceLanguage}
                ? $Request->{PreferenceLanguage}
                : $Request->{Language}
        ),
        timezone => $Self->_TimezoneClean( $Request->{Timezone} ),
    );

    my $CurrentPassword = $Request->{CurrentPassword} || '';
    my $NewPassword     = $Request->{NewPassword}     || '';
    my $RepeatPassword  = $Request->{NewPasswordRepeat} || '';

    if ( $CurrentPassword || $NewPassword || $RepeatPassword ) {
        return if !$Self->_PasswordChange(
            UserAccountID   => $UserAccountID,
            AccountType     => 'customer',
            CurrentPassword => $CurrentPassword,
            NewPassword     => $NewPassword,
            RepeatPassword  => $RepeatPassword,
        );
    }

    for my $Key ( sort keys %Preference ) {
        my $Value = defined $Preference{$Key} ? $Preference{$Key} : '';
        return if !$Self->Set(
            UserAccountID => $UserAccountID,
            Key           => $Key,
            Value         => $Value,
        );
    }

    return 1;
}

sub AgentPreferenceSave {
    my ( $Self, %Param ) = @_;

    my $UserAccountID = $Param{UserAccountID} || 0;
    my $Request       = $Param{Request}       || {};

    if ( $UserAccountID !~ m{\A\d+\z} || !$UserAccountID ) {
        $Self->{LastError} = 'User account is required.';
        return;
    }

    my $Language = $Self->_LanguageClean(
        exists $Request->{PreferenceLanguage}
            ? $Request->{PreferenceLanguage}
            : $Request->{Language}
    );
    my $Timezone = $Self->_TimezoneClean( $Request->{Timezone} );

    my %Preference = (
        language                      => $Language,
        timezone                      => $Timezone,
        start_page                    => $Self->_StartPageClean( $Request->{StartPage} ),
        ticket_list_limit             => $Self->_TicketListLimitClean( $Request->{TicketListLimit} ),
        ticket_after_reply_action     => $Self->_AfterReplyActionClean( $Request->{TicketAfterReplyAction} ),
        notification_new_ticket       => $Request->{NotificationNewTicket}       ? 1 : 0,
        notification_customer_reply   => $Request->{NotificationCustomerReply}   ? 1 : 0,
        notification_assigned_ticket  => $Request->{NotificationAssignedTicket}  ? 1 : 0,
        notification_status_change    => $Request->{NotificationStatusChange}    ? 1 : 0,
        absence_active                => $Request->{AbsenceActive}               ? 1 : 0,
        absence_start                 => $Self->_DateTimeClean( $Request->{AbsenceStart} ),
        absence_end                   => $Self->_DateTimeClean( $Request->{AbsenceEnd} ),
        absence_replacement_user_id   => $Self->_UserIDClean( $Request->{AbsenceReplacementUserID} ),
        absence_note                  => $Self->_Trim( $Request->{AbsenceNote} ),
    );

    if ( $Preference{absence_active} && $Preference{absence_start} && $Preference{absence_end} ) {
        if ( $Preference{absence_end} lt $Preference{absence_start} ) {
            $Self->{LastError} = 'The absence end must be after the absence start.';
            return;
        }
    }

    my $CurrentPassword = $Request->{CurrentPassword} || '';
    my $NewPassword     = $Request->{NewPassword}     || '';
    my $RepeatPassword  = $Request->{NewPasswordRepeat} || '';

    if ( $CurrentPassword || $NewPassword || $RepeatPassword ) {
        return if !$Self->_PasswordChange(
            UserAccountID   => $UserAccountID,
            AccountType     => 'agent',
            CurrentPassword => $CurrentPassword,
            NewPassword     => $NewPassword,
            RepeatPassword  => $RepeatPassword,
        );
    }

    for my $Key ( sort keys %Preference ) {
        my $Value = defined $Preference{$Key} ? $Preference{$Key} : '';
        return if !$Self->Set(
            UserAccountID => $UserAccountID,
            Key           => $Key,
            Value         => $Value,
        );
    }

    return 1;
}

sub Set {
    my ( $Self, %Param ) = @_;

    my $UserAccountID = $Param{UserAccountID} || 0;
    my $Key           = $Param{Key}           || '';
    my $Value         = defined $Param{Value} ? $Param{Value} : '';

    if ( $UserAccountID !~ m{\A\d+\z} || !$UserAccountID || !$Key ) {
        $Self->{LastError} = 'User account and preference key are required.';
        return;
    }

    my $Result = $Self->{DB}->Do(
        'INSERT INTO user_preference (
             user_account_id,
             preference_key,
             preference_value,
             created_at,
             changed_at
         ) VALUES (
             ?, ?, ?, NOW(), NOW()
         )
         ON DUPLICATE KEY UPDATE
             preference_value = VALUES(preference_value),
             changed_at = NOW()',
        $UserAccountID,
        $Key,
        $Value,
    );

    if ( !$Result ) {
        $Self->{LastError} = $Self->{DB}->Error() || 'Preference could not be saved.';
        return;
    }

    return 1;
}

sub AgentSelectionList {
    my ( $Self, %Param ) = @_;

    my $CurrentUserAccountID = $Param{CurrentUserAccountID} || 0;

    my $Rows = $Self->{DB}->SelectAll(
        'SELECT id, login, firstname, lastname, email
         FROM user_account
         WHERE account_type = "agent"
            AND is_active = 1
            AND is_system_user = 0
         ORDER BY firstname ASC, lastname ASC, login ASC'
    ) || [];

    my @List;

    for my $Row ( @{$Rows} ) {
        next if ref $Row ne 'HASH';
        next if $CurrentUserAccountID && ( $Row->{id} || 0 ) == $CurrentUserAccountID;

        my $Name = join ' ', grep {$_} ( $Row->{firstname}, $Row->{lastname} );
        $Name ||= $Row->{login} || '';

        push @List, {
            id    => $Row->{id},
            label => $Name,
            email => $Row->{email} || '',
        };
    }

    return \@List;
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

    return [ sort keys %Language ];
}

sub TimezoneList {
    return [
        'Europe/Berlin',
        'Europe/Paris',
        'Europe/London',
        'UTC',
        'America/New_York',
        'America/Chicago',
        'America/Los_Angeles',
        'Asia/Tokyo',
        'Asia/Singapore',
        'Australia/Sydney',
    ];
}

sub Error {
    my ($Self) = @_;

    return $Self->{LastError};
}


sub _DefaultCustomerPreferences {
    my ($Self) = @_;

    return {
        language => $Self->_LanguageClean( $Self->{Config}->{Language}->{Default} || 'en' ),
        timezone => 'Europe/Berlin',
    };
}

sub _PasswordChange {
    my ( $Self, %Param ) = @_;

    my $UserAccountID   = $Param{UserAccountID}   || 0;
    my $AccountType     = $Param{AccountType}     || '';
    my $CurrentPassword = $Param{CurrentPassword} || '';
    my $NewPassword     = $Param{NewPassword}     || '';
    my $RepeatPassword  = $Param{RepeatPassword}  || '';

    if ( $AccountType ne 'agent' && $AccountType ne 'customer' ) {
        $Self->{LastError} = 'Translate:PreferencesPasswordUserNotFound';
        return;
    }

    if ( !$CurrentPassword || !$NewPassword || !$RepeatPassword ) {
        $Self->{LastError} = 'Translate:PreferencesPasswordAllFieldsRequired';
        return;
    }

    if ( $NewPassword ne $RepeatPassword ) {
        $Self->{LastError} = 'Translate:PreferencesPasswordRepeatMismatch';
        return;
    }

    if ( length $NewPassword < 8 ) {
        $Self->{LastError} = 'Translate:PreferencesPasswordTooShort';
        return;
    }

    my $User = $Self->{DB}->SelectRow(
        'SELECT id, password_hash
         FROM user_account
         WHERE id = ?
            AND account_type = ?
            AND is_active = 1
         LIMIT 1',
        $UserAccountID,
        $AccountType,
    );

    if ( !$User ) {
        $Self->{LastError} = 'Translate:PreferencesPasswordUserNotFound';
        return;
    }

    if ( !$Self->_PasswordVerify( Password => $CurrentPassword, PasswordHash => $User->{password_hash} ) ) {
        $Self->{LastError} = 'Translate:PreferencesPasswordCurrentWrong';
        return;
    }

    my $PasswordHash = $Self->_PasswordHash( Password => $NewPassword );
    my $Result = $Self->{DB}->Do(
        'UPDATE user_account
         SET password_hash = ?,
             password_changed_at = NOW(),
             changed_at = NOW()
         WHERE id = ?
            AND account_type = ?',
        $PasswordHash,
        $UserAccountID,
        $AccountType,
    );

    if ( !$Result ) {
        $Self->{LastError} = $Self->{DB}->Error() || 'Translate:PreferencesPasswordCouldNotBeSaved';
        return;
    }

    return 1;
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

sub _DefaultAgentPreferences {
    my ($Self) = @_;

    return {
        language                      => $Self->_LanguageClean( $Self->{Config}->{Language}->{Default} || 'en' ),
        timezone                      => 'Europe/Berlin',
        start_page                    => 'Dashboard',
        ticket_list_limit             => 20,
        ticket_after_reply_action     => 'stay',
        ticket_list_columns            => 'ticket_number,title,queue,state,priority,customer,customer_user,owner,escalation_state,next_escalation,pending_until,changed',
        notification_new_ticket       => 1,
        notification_customer_reply   => 1,
        notification_assigned_ticket  => 1,
        notification_status_change    => 0,
        absence_active                => 0,
        absence_start                 => '',
        absence_end                   => '',
        absence_replacement_user_id   => 0,
        absence_note                  => '',
    };
}

sub _LanguageClean {
    my ( $Self, $Language ) = @_;

    $Language = $Self->_Trim($Language);
    $Language = $Self->{Config}->{Language}->{Default} || 'en' if !$Language;
    $Language =~ s{[^A-Za-z0-9_-]}{}g;

    return $Language || 'en';
}

sub _TimezoneClean {
    my ( $Self, $Timezone ) = @_;

    $Timezone = $Self->_Trim($Timezone);
    $Timezone = 'Europe/Berlin' if !$Timezone;
    $Timezone =~ s{[^A-Za-z0-9_+\-/]}{}g;

    return $Timezone || 'Europe/Berlin';
}

sub _StartPageClean {
    my ( $Self, $StartPage ) = @_;

    $StartPage = $Self->_Trim($StartPage);

    return 'AgentTicketList' if $StartPage eq 'AgentTicketList';
    return 'Dashboard';
}

sub _TicketListLimitClean {
    my ( $Self, $Limit ) = @_;

    return int($Limit) if defined $Limit && $Limit =~ m{\A(?:10|20|30|40|50)\z};
    return 20;
}

sub _AfterReplyActionClean {
    my ( $Self, $Action ) = @_;

    $Action = $Self->_Trim($Action);

    return 'list' if $Action eq 'list';
    return 'next' if $Action eq 'next';
    return 'stay';
}

sub _DateTimeClean {
    my ( $Self, $Value ) = @_;

    $Value = $Self->_Trim($Value);
    return '' if !$Value;

    $Value =~ s{T}{ }g;
    return '' if $Value !~ m{\A\d{4}-\d{2}-\d{2}(?: \d{2}:\d{2}(?::\d{2})?)?\z};
    $Value .= ':00' if $Value =~ m{\A\d{4}-\d{2}-\d{2} \d{2}:\d{2}\z};

    return $Value;
}

sub _UserIDClean {
    my ( $Self, $Value ) = @_;

    $Value = $Self->_Trim($Value);

    return $Value if $Value =~ m{\A\d+\z};
    return 0;
}

sub _Trim {
    my ( $Self, $Value ) = @_;

    $Value = '' if !defined $Value;
    $Value =~ s{\A\s+}{};
    $Value =~ s{\s+\z}{};

    return $Value;
}

1;
