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

package AdminKnowledgeSuggestions;

use strict;
use warnings;
use utf8;

use QisutuKnowledgeSuggestions;
use QisutuPermission;


sub new {
    my ( $Class, %Param ) = @_;
    return bless { %Param }, $Class;
}

sub Run {
    my ( $Self, %Param ) = @_;
    my $Request = $Param{Request} || {};
    my $User = $Param{User} || {};
    my $UserID = $User->{user_account_id};
    my $Permission = QisutuPermission->new( Config => $Self->{Config}, DB => $Self->{DB} );
    if ( ( $User->{account_type} || '' ) ne 'agent'
        || !defined $UserID || ref $UserID || $UserID !~ m{\A[1-9][0-9]*\z}
        || !$Permission->UserIsAdmin( UserID => $UserID )
    ) {
        return { Response => $Self->{Output}->Response(
            Status => '403 Forbidden', Body => 'Forbidden.', Headers => ['Cache-Control: no-store'],
        ) };
    }

    my $Manager = QisutuKnowledgeSuggestions->new( Config => $Self->{Config}, DB => $Self->{DB} );
    my $Settings = $Manager->SettingsGet() || {};
    my $Error = '';
    my $Step = !ref $Request->{Step} ? ( $Request->{Step} || '' ) : '';

    if ( $Step eq 'SettingsSave' ) {
        if ( ( $Request->{__RequestMethod} || '' ) ne 'POST' ) {
            return { Response => $Self->{Output}->Response(
                Status => '405 Method Not Allowed', Body => 'POST required.',
                Headers => ['Allow: POST', 'Cache-Control: no-store'],
            ) };
        }
        my $Maximum = $Request->{MaxResults};
        my $Minimum = $Request->{MinimumLength};
        if ( !defined $Maximum || ref $Maximum || $Maximum !~ m{\A(?:[1-9]|10)\z}
            || !defined $Minimum || ref $Minimum || $Minimum !~ m{\A(?:[2-9]|10)\z}
            || ref $Request->{Enabled}
        ) {
            $Error = 'Translate:KnowledgeSuggestionsInvalid';
        }
        else {
            my $Values = {
                enabled => ( $Request->{Enabled} || '' ) eq '1' ? 1 : 0,
                max_results => 0 + $Maximum,
                minimum_length => 0 + $Minimum,
            };
            if ( $Manager->SettingsSave( Values => $Values, UserID => $UserID ) ) {
                return { Redirect => 'index.pl?Page=AdminKnowledgeSuggestions&Status=saved' };
            }
            $Error = 'Translate:KnowledgeSuggestionsSaveFailed';
        }
    }

    my $Notice = !ref $Request->{Status} && ( $Request->{Status} || '' ) eq 'saved'
        ? 'Translate:KnowledgeSuggestionsSaved' : '';
    my $Maximum = $Settings->{max_results};
    my $Minimum = $Settings->{minimum_length};
    $Maximum = 3 if !defined $Maximum || ref $Maximum || $Maximum !~ m{\A(?:[1-9]|10)\z};
    $Minimum = 3 if !defined $Minimum || ref $Minimum || $Minimum !~ m{\A(?:[2-9]|10)\z};
    return {
        Template => 'AdminKnowledgeSuggestions.tt',
        Data => {
            PageTitle => 'Translate:KnowledgeSuggestionsAdminTitle',
            ProgramTitle => 'Translate:KnowledgeSuggestionsAdminTitle',
            ProgramDescription => 'Translate:KnowledgeSuggestionsAdminDescription',
            EnabledChecked => $Settings->{enabled} ? 'checked' : '',
            MaxResults => $Maximum,
            MinimumLength => $Minimum,
            ErrorMessage => $Error,
            ErrorClass => $Error ? '' : 'qisutu-hidden',
            NoticeMessage => $Notice,
            NoticeClass => $Notice ? '' : 'qisutu-hidden',
        },
    };
}

1;
