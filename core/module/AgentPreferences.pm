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

package AgentPreferences;

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
    my $Prefs   = $Self->_PreferenceObject();
    my $Step    = $Request->{Step} || '';

    if ( $Prefs && $Step eq 'PreferenceSave' ) {
        $Prefs->AgentPreferenceSave(
            UserAccountID => $User->{user_account_id},
            Request       => $Request,
        );

        return { Redirect => 'index.pl?Page=AgentPreferences;Saved=1' } if !$Prefs->Error();
    }

    my $Preference = $Prefs ? $Prefs->AgentPreferenceGet( UserAccountID => $User->{user_account_id} ) : {};
    my $ErrorMessage = $Prefs ? $Prefs->Error() : 'Preference system could not be loaded.';
    my $SuccessMessage = $Request->{Saved} ? 'Translate:PreferencesSaved' : '';

    my $AgentList = $Prefs ? $Prefs->AgentSelectionList( CurrentUserAccountID => $User->{user_account_id} ) : [];

    return {
        Template => 'AgentPreferences.tt',
        Data     => {
            PageTitle                        => 'Translate:AgentPreferencesTitle',
            ProgramTitle                     => 'Translate:AgentPreferencesTitle',
            ProgramDescription               => 'Translate:AgentPreferencesDescription',
            ErrorMessage                     => $ErrorMessage,
            ErrorClass                       => $ErrorMessage ? '' : 'qisutu-hidden',
            SuccessMessage                   => $SuccessMessage,
            SuccessClass                     => $SuccessMessage ? '' : 'qisutu-hidden',
            FormAction                       => 'index.pl',
            LanguageOptions                  => $Self->_LanguageOptions(
                Preference => $Preference,
                Prefs      => $Prefs,
            ),
            TimezoneOptions                  => $Self->_TimezoneOptions(
                Preference => $Preference,
                Prefs      => $Prefs,
            ),
            StartPageDashboardSelected       => ( ( $Preference->{start_page} || '' ) eq 'Dashboard' ? 'selected' : '' ),
            StartPageTicketListSelected      => ( ( $Preference->{start_page} || '' ) eq 'AgentTicketList' ? 'selected' : '' ),
            TicketListLimit                  => $Preference->{ticket_list_limit} || 20,
            AfterReplyStaySelected           => ( ( $Preference->{ticket_after_reply_action} || '' ) eq 'stay' ? 'selected' : '' ),
            AfterReplyListSelected           => ( ( $Preference->{ticket_after_reply_action} || '' ) eq 'list' ? 'selected' : '' ),
            AfterReplyNextSelected           => ( ( $Preference->{ticket_after_reply_action} || '' ) eq 'next' ? 'selected' : '' ),
            NotificationNewTicketChecked     => $Preference->{notification_new_ticket}      ? 'checked' : '',
            NotificationCustomerReplyChecked => $Preference->{notification_customer_reply}  ? 'checked' : '',
            NotificationAssignedTicketChecked => $Preference->{notification_assigned_ticket} ? 'checked' : '',
            NotificationStatusChangeChecked  => $Preference->{notification_status_change}   ? 'checked' : '',
            AbsenceActiveChecked             => $Preference->{absence_active}               ? 'checked' : '',
            AbsenceStart                     => $Self->_DateTimeForInput( $Preference->{absence_start} ),
            AbsenceEnd                       => $Self->_DateTimeForInput( $Preference->{absence_end} ),
            AbsenceReplacementOptions        => $Self->_AgentOptions(
                AgentList => $AgentList,
                Selected  => $Preference->{absence_replacement_user_id},
                Language  => $Preference->{language},
            ),
            AbsenceNote                      => $Preference->{absence_note} || '',
        },
    };
}

sub _PreferenceObject {
    my ($Self) = @_;

    my $Loaded = eval {
        require QisutuUserPreference;
        1;
    };

    return if !$Loaded;

    return QisutuUserPreference->new(
        Config => $Self->{Config},
        DB     => $Self->{DB},
    );
}

sub _LanguageOptions {
    my ( $Self, %Param ) = @_;

    my $Prefs      = $Param{Prefs};
    my $Preference = $Param{Preference} || {};
    my $Selected   = $Preference->{language} || $Self->{Config}->{Language}->{Default} || 'en';
    my $Languages  = $Prefs ? $Prefs->LanguageList() : [ $Selected ];
    my $HTML       = '';

    for my $Language ( @{$Languages} ) {
        my $IsSelected = $Language eq $Selected ? ' selected' : '';
        $HTML .= '<option value="' . $Self->{Output}->HTMLEscape($Language) . '"' . $IsSelected . '>';
        $HTML .= $Self->{Output}->HTMLEscape($Language);
        $HTML .= '</option>' . "\n";
    }

    return $HTML;
}

sub _TimezoneOptions {
    my ( $Self, %Param ) = @_;

    my $Prefs      = $Param{Prefs};
    my $Preference = $Param{Preference} || {};
    my $Selected   = $Preference->{timezone} || 'Europe/Berlin';
    my $Timezones  = $Prefs ? $Prefs->TimezoneList() : [ $Selected ];
    my $HTML       = '';

    for my $Timezone ( @{$Timezones} ) {
        my $IsSelected = $Timezone eq $Selected ? ' selected' : '';
        $HTML .= '<option value="' . $Self->{Output}->HTMLEscape($Timezone) . '"' . $IsSelected . '>';
        $HTML .= $Self->{Output}->HTMLEscape($Timezone);
        $HTML .= '</option>' . "\n";
    }

    return $HTML;
}

sub _AgentOptions {
    my ( $Self, %Param ) = @_;

    my $AgentList = $Param{AgentList} || [];
    my $Selected  = $Param{Selected}  || 0;
    my $Language  = $Param{Language}  || $Self->{Config}->{Language}->{Default} || 'en';
    my $HTML      = '<option value="0">' . $Self->{Output}->HTMLEscape( $Self->{Output}->Translate( Key => 'PreferencesNoReplacement', Language => $Language ) ) . '</option>' . "\n";

    for my $Agent ( @{$AgentList} ) {
        next if ref $Agent ne 'HASH';
        my $ID         = $Agent->{id} || 0;
        my $IsSelected = $ID && $ID == $Selected ? ' selected' : '';
        my $Label      = $Agent->{label} || '';
        $Label .= ' - ' . $Agent->{email} if $Agent->{email};

        $HTML .= '<option value="' . $Self->{Output}->HTMLEscape($ID) . '"' . $IsSelected . '>';
        $HTML .= $Self->{Output}->HTMLEscape($Label);
        $HTML .= '</option>' . "\n";
    }

    return $HTML;
}

sub _DateTimeForInput {
    my ( $Self, $Value ) = @_;

    $Value ||= '';
    $Value =~ s{ }{T};
    $Value =~ s{:00\z}{};

    return $Value;
}

1;
