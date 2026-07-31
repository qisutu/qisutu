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

package AdminQueues;

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
    my $Admin   = $Self->_AdminObject();
    my $Step    = $Request->{Step} || '';
    my $Language = $Request->{Language} || $Self->{Config}->{Language}->{Default} || 'en';

    if ( $Admin && $Step eq 'QueueCreate' ) {
        $Admin->QueueCreate(
            Name                           => $Request->{Name},
            ParentQueueID                  => $Request->{ParentQueueID},
            GroupID                        => $Request->{GroupID},
            FollowUpOption                 => $Request->{FollowUpOption},
            SystemEmailID                  => $Request->{SystemEmailID},
            SalutationID                   => $Request->{SalutationID},
            SignatureID                    => $Request->{SignatureID},
            CalendarID                     => $Request->{CalendarID},
            EscalationFirstResponseMinutes => $Request->{EscalationFirstResponseMinutes},
            EscalationUpdateMinutes        => $Request->{EscalationUpdateMinutes},
            EscalationSolutionMinutes      => $Request->{EscalationSolutionMinutes},
            SortOrder                      => $Request->{SortOrder},
            ChangedByUserID                => $User->{user_account_id},
        );

        return { Redirect => 'index.pl?Page=AdminQueues' } if !$Admin->Error();
    }
    elsif ( $Admin && $Step eq 'QueueUpdate' ) {
        $Admin->QueueUpdate(
            QueueID                        => $Request->{QueueID},
            Name                           => $Request->{Name},
            ParentQueueID                  => $Request->{ParentQueueID},
            FollowUpOption                 => $Request->{FollowUpOption},
            GroupID                        => $Request->{GroupID},
            SystemEmailID                  => $Request->{SystemEmailID},
            SalutationID                   => $Request->{SalutationID},
            SignatureID                    => $Request->{SignatureID},
            CalendarID                     => $Request->{CalendarID},
            EscalationFirstResponseMinutes => $Request->{EscalationFirstResponseMinutes},
            EscalationUpdateMinutes        => $Request->{EscalationUpdateMinutes},
            EscalationSolutionMinutes      => $Request->{EscalationSolutionMinutes},
            Active                         => $Request->{Active},
            SortOrder                      => $Request->{SortOrder},
            ChangedByUserID                => $User->{user_account_id},
        );

        return { Redirect => 'index.pl?Page=AdminQueues;Action=Edit;QueueID=' . ( $Request->{QueueID} || 0 ) } if !$Admin->Error();
    }
    elsif ( $Admin && $Step eq 'QueueDeactivate' ) {
        $Admin->QueueDeactivate(
            QueueID         => $Request->{QueueID},
            ChangedByUserID => $User->{user_account_id},
        );

        return { Redirect => 'index.pl?Page=AdminQueues' } if !$Admin->Error();
    }
    my $Action          = $Request->{Action} || 'List';
    my $QueueList       = $Admin ? $Admin->QueueList() : [];
    my $GroupList       = $Admin ? $Admin->GroupList() : [];
    my $SystemEmailList = $Admin ? $Admin->SystemEmailList() : [];
    my $SalutationList  = $Admin ? $Admin->SalutationList( Language => $Language ) : [];
    my $SignatureList   = $Admin ? $Admin->SignatureList( Language => $Language ) : [];
    my $CalendarList    = $Admin ? $Admin->CalendarList() : [];
    my $Queue;
    my $QueuePrimaryGroupID = '';

    if ( $Admin && $Action eq 'Edit' ) {
        $Queue = $Admin->QueueGet( QueueID => $Request->{QueueID} );
        if ( !$Queue ) {
            $Action = 'List';
        }
        else {
            $QueuePrimaryGroupID = $Admin->QueuePrimaryGroupID( QueueID => $Queue->{id} ) || '';
        }
    }

    my $QueueFollowUpOption = $Queue ? ( $Queue->{follow_up_option} || '' ) : 'reopen';
    if ( $QueueFollowUpOption !~ m{\A(?:reopen|new_ticket|reject)\z} ) {
        $QueueFollowUpOption = !$Queue || $Queue->{follow_up_allowed} ? 'reopen' : 'reject';
    }

    my $ErrorMessage = $Admin ? $Admin->Error() : '';

    return {
        Template => 'AdminQueues.tt',
        Data     => {
            PageTitle          => 'Translate:AdminQueuesTitle',
            ProgramTitle       => 'Translate:AdminQueuesTitle',
            ProgramDescription => 'Translate:AdminQueuesDescription',
            QueueList          => $QueueList,
            GroupList          => $GroupList,
            QueueCount         => scalar @{$QueueList},
            ErrorMessage       => $ErrorMessage,
            ErrorClass         => $ErrorMessage ? '' : 'qisutu-hidden',
            FormAction         => 'index.pl',
            ShowList           => $Action eq 'List' ? 1 : 0,
            ShowCreate         => $Action eq 'Create' ? 1 : 0,
            ShowEdit           => $Action eq 'Edit' ? 1 : 0,
            QueueID            => $Queue ? $Queue->{id} : '',
            QueueName          => $Queue ? $Queue->{name} : '',
            QueueFullName      => $Queue ? $Queue->{full_name} : '',
            QueueSortOrder     => $Queue ? $Queue->{sort_order} : 1000,
            QueueActiveChecked => $Queue && $Queue->{active} ? 'checked' : '',
            QueueFollowUpReopenChecked    => $QueueFollowUpOption eq 'reopen' ? 'checked' : '',
            QueueFollowUpNewTicketChecked => $QueueFollowUpOption eq 'new_ticket' ? 'checked' : '',
            QueueFollowUpRejectChecked    => $QueueFollowUpOption eq 'reject' ? 'checked' : '',
            QueueEscalationFirstResponseMinutes => $Queue ? $Queue->{escalation_first_response_minutes} : 0,
            QueueEscalationUpdateMinutes        => $Queue ? $Queue->{escalation_update_minutes} : 0,
            QueueEscalationSolutionMinutes      => $Queue ? $Queue->{escalation_solution_minutes} : 0,
            CreateParentQueueOptionsHTML => $Self->_OptionHTML(
                List       => $QueueList,
                ValueKey   => 'id',
                LabelKey   => 'full_name',
                SelectedID => '',
            ),
            EditParentQueueOptionsHTML => $Self->_OptionHTML(
                List       => $QueueList,
                ValueKey   => 'id',
                LabelKey   => 'full_name',
                SelectedID => $Queue ? $Queue->{parent_id} : '',
                SkipID     => $Queue ? $Queue->{id} : '',
            ),
            CreateGroupOptionsHTML => $Self->_OptionHTML(
                List       => $GroupList,
                ValueKey   => 'id',
                LabelKeys  => [ 'name', 'title' ],
                SelectedID => '',
            ),
            EditGroupOptionsHTML => $Self->_OptionHTML(
                List       => $GroupList,
                ValueKey   => 'id',
                LabelKeys  => [ 'name', 'title' ],
                SelectedID => $QueuePrimaryGroupID,
            ),
            CreateSystemEmailOptionsHTML => $Self->_OptionHTML(
                List       => $SystemEmailList,
                ValueKey   => 'id',
                LabelKeys  => [ 'name', 'email' ],
                SelectedID => '',
            ),
            EditSystemEmailOptionsHTML => $Self->_OptionHTML(
                List       => $SystemEmailList,
                ValueKey   => 'id',
                LabelKeys  => [ 'name', 'email' ],
                SelectedID => $Queue ? $Queue->{system_email_id} : '',
            ),
            CreateSalutationOptionsHTML => $Self->_OptionHTML(
                List       => $SalutationList,
                ValueKey   => 'id',
                LabelKey   => 'name',
                SelectedID => '',
            ),
            EditSalutationOptionsHTML => $Self->_OptionHTML(
                List       => $SalutationList,
                ValueKey   => 'id',
                LabelKey   => 'name',
                SelectedID => $Queue ? $Queue->{salutation_id} : '',
            ),
            CreateSignatureOptionsHTML => $Self->_OptionHTML(
                List       => $SignatureList,
                ValueKey   => 'id',
                LabelKey   => 'name',
                SelectedID => '',
            ),
            EditSignatureOptionsHTML => $Self->_OptionHTML(
                List       => $SignatureList,
                ValueKey   => 'id',
                LabelKey   => 'name',
                SelectedID => $Queue ? $Queue->{signature_id} : '',
            ),
            CreateCalendarOptionsHTML => $Self->_OptionHTML(
                List       => $CalendarList,
                ValueKey   => 'id',
                LabelKeys  => [ 'name', 'timezone' ],
                SelectedID => '',
            ),
            EditCalendarOptionsHTML => $Self->_OptionHTML(
                List       => $CalendarList,
                ValueKey   => 'id',
                LabelKeys  => [ 'name', 'timezone' ],
                SelectedID => $Queue ? $Queue->{calendar_id} : '',
            ),
        },
    };
}

sub _OptionHTML {
    my ( $Self, %Param ) = @_;

    my $List       = $Param{List} || [];
    my $ValueKey   = $Param{ValueKey} || 'id';
    my $LabelKey   = $Param{LabelKey} || '';
    my $LabelKeys  = $Param{LabelKeys} || [];
    my $SelectedID = $Param{SelectedID} || '';
    my $SkipID     = $Param{SkipID} || '';
    my $HTML       = '';

    if ( $LabelKey && !@{$LabelKeys} ) {
        $LabelKeys = [$LabelKey];
    }

    for my $Item ( @{$List} ) {
        next if ref $Item ne 'HASH';

        my $Value = $Item->{$ValueKey} || '';
        next if $SkipID && $Value eq $SkipID;

        my @LabelPart;

        for my $Key ( @{$LabelKeys} ) {
            push @LabelPart, $Item->{$Key} if defined $Item->{$Key} && $Item->{$Key} ne '';
        }

        my $Label    = join ' ', @LabelPart;
        my $Selected = $Value && $Value eq $SelectedID ? ' selected' : '';

        $HTML .= '<option value="' . $Self->_Escape($Value) . '"' . $Selected . '>' . $Self->_Escape($Label) . '</option>';
    }

    return $HTML;
}

sub _Escape {
    my ( $Self, $Value ) = @_;

    if ( $Self->{Output} ) {
        return $Self->{Output}->HTMLEscape($Value);
    }

    $Value = '' if !defined $Value;
    $Value =~ s/&/&amp;/g;
    $Value =~ s/</&lt;/g;
    $Value =~ s/>/&gt;/g;
    $Value =~ s/"/&quot;/g;
    $Value =~ s/'/&#39;/g;

    return $Value;
}

sub _AdminObject {
    my ($Self) = @_;

    return if !$Self->{DB};

    my $Loaded = eval {
        require QisutuAdmin;
        1;
    };

    return if !$Loaded;

    return QisutuAdmin->new(
        Config => $Self->{Config},
        DB     => $Self->{DB},
    );
}

1;
