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

package AdminAgentNotifications;

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

    my $Request  = $Param{Request} || {};
    my $User     = $Param{User} || {};
    my $Language = $Request->{Language} || $Self->{Config}->{Language}->{Default} || 'en';
    my $Action   = $Request->{Action} || 'List';
    my $Type     = $Request->{NotificationType} || '';
    my $Error    = '';

    my $Notification = $Self->_NotificationObject();

    if ( !$Notification ) {
        $Error = 'Agent notification module could not be loaded';
        $Action = 'List';
    }

    if ( $Notification && ( $Request->{Step} || '' ) eq 'NotificationUpdate' ) {
        if (
            $Notification->TemplateUpdate(
                NotificationType => $Type,
                Subject          => $Request->{Subject},
                BodyHTML         => $Request->{BodyHTML},
                Active           => $Request->{Active},
                ChangedByUserID  => $User->{user_account_id},
            )
            )
        {
            return {
                Redirect => 'index.pl?Page=AdminAgentNotifications;Action=Edit;NotificationType=' . $Self->_URLEncode($Type),
            };
        }

        $Error = $Notification->Error() || 'Agent notification template could not be saved';
        $Action = 'Edit';
    }

    my $TemplateList = $Notification ? $Notification->TemplateList() : [];
    my $Template;

    if ( $Notification && $Action eq 'Edit' ) {
        $Template = $Notification->TemplateGet(
            NotificationType => $Type,
        );

        if ( !$Template ) {
            $Error ||= $Notification->Error() || 'Agent notification template was not found';
            $Action = 'List';
        }
    }

    my $PlaceholderList = $Notification ? $Notification->PlaceholderList() : [];

    return {
        Template => 'AdminAgentNotifications.tt',
        Data     => {
            PageTitle          => 'Translate:AdminAgentNotificationsTitle',
            ProgramTitle       => 'Translate:AdminAgentNotificationsTitle',
            ProgramDescription => 'Translate:AdminAgentNotificationsDescription',
            TemplateList       => $TemplateList,
            TemplateCount      => scalar @{$TemplateList},
            PlaceholderList    => $PlaceholderList,
            PlaceholderCount   => scalar @{$PlaceholderList},
            CurrentType        => $Template ? ( $Template->{notification_type} || '' ) : '',
            CurrentName        => $Template ? ( $Template->{name} || '' ) : '',
            CurrentSubject     => $Template ? ( $Template->{subject} || '' ) : '',
            CurrentBodyHTML    => $Template ? ( $Template->{body_html} || '' ) : '',
            CurrentActiveChecked => $Template && $Template->{active} ? 'checked' : '',
            ShowList           => $Action eq 'List' ? 1 : 0,
            ShowEdit           => $Action eq 'Edit' ? 1 : 0,
            ErrorMessage       => $Error,
            ErrorClass         => $Error ? '' : 'qisutu-hidden',
            FormAction         => 'index.pl',
        },
    };
}

sub _NotificationObject {
    my ($Self) = @_;

    return if !$Self->{DB};

    my $Loaded = eval {
        require QisutuNotification;
        1;
    };

    return if !$Loaded;

    return QisutuNotification->new(
        Config => $Self->{Config},
        DB     => $Self->{DB},
    );
}

sub _URLEncode {
    my ( $Self, $Value ) = @_;

    $Value = '' if !defined $Value;
    $Value =~ s{([^A-Za-z0-9_\-\.])}{sprintf('%%%02X', ord($1))}eg;

    return $Value;
}

1;
