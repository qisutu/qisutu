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

package AdminCustomerAutoResponses;

use strict;
use warnings;
use utf8;

use QisutuCustomerAutoResponse;

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
    my $User    = $Param{User} || {};
    my $Action  = $Request->{Action} || 'List';
    my $Type    = $Request->{ResponseType} || '';
    my $Error   = '';

    my $Response = QisutuCustomerAutoResponse->new(
        Config => $Self->{Config},
        DB     => $Self->{DB},
    );

    if ( ( $Request->{Step} || '' ) eq 'AutoResponseUpdate' ) {
        if ( $Response->TemplateUpdate(
            ResponseType    => $Type,
            Subject         => $Request->{Subject},
            BodyHTML        => $Request->{BodyHTML},
            Active          => $Request->{Active},
            ChangedByUserID => $User->{user_account_id},
        ) ) {
            return {
                Redirect => 'index.pl?Page=AdminCustomerAutoResponses;Action=Edit;ResponseType=' . $Self->_URLEncode($Type),
            };
        }

        $Error = $Response->Error() || 'Customer auto-response template could not be saved';
        $Action = 'Edit';
    }

    my $TemplateList = $Response->TemplateList();
    $Error ||= $Response->Error();
    my $Template;

    if ( $Action eq 'Edit' ) {
        $Template = $Response->TemplateGet( ResponseType => $Type );
        if ( !$Template ) {
            $Error ||= $Response->Error() || 'Customer auto-response template was not found';
            $Action = 'List';
        }
    }

    my $PlaceholderList = $Response->PlaceholderList();

    return {
        Template => 'AdminCustomerAutoResponses.tt',
        Data     => {
            PageTitle             => 'Translate:AdminCustomerAutoResponsesTitle',
            ProgramTitle          => 'Translate:AdminCustomerAutoResponsesTitle',
            ProgramDescription    => 'Translate:AdminCustomerAutoResponsesDescription',
            TemplateList          => $TemplateList,
            TemplateCount         => scalar @{$TemplateList},
            PlaceholderList       => $PlaceholderList,
            CurrentType           => $Template ? ( $Template->{response_type} || '' ) : '',
            CurrentName           => $Template ? ( $Template->{name} || '' ) : '',
            CurrentSubject        => $Template ? ( $Template->{subject} || '' ) : '',
            CurrentBodyHTML       => $Template ? ( $Template->{body_html} || '' ) : '',
            CurrentActiveChecked  => $Template && $Template->{active} ? 'checked' : '',
            ShowList              => $Action eq 'List' ? 1 : 0,
            ShowEdit              => $Action eq 'Edit' ? 1 : 0,
            ErrorMessage          => $Error,
            ErrorClass            => $Error ? '' : 'qisutu-hidden',
            FormAction            => 'index.pl',
        },
    };
}

sub _URLEncode {
    my ( $Self, $Value ) = @_;

    $Value = '' if !defined $Value;
    $Value =~ s{([^A-Za-z0-9_\-\.])}{sprintf('%%%02X', ord($1))}eg;
    return $Value;
}

1;
