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

package CustomerTicketCreate;

use strict;
use warnings;
use utf8;
use QisutuCMDB;

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

    my $TicketObject = $Self->_TicketObject();
    my $FormObject   = $Self->_TicketFormObject();
    my $Request      = $Param{Request} || {};
    my $User         = $Param{User} || {};
    my $Language     = $Request->{Language} || $User->{language}
        || $Self->{Config}->{Language}->{Default} || 'en';
    my $CMDBObject   = QisutuCMDB->new( Config => $Self->{Config}, DB => $Self->{DB}, Output => $Self->{Output} );
    my $CreateError  = '';
    my $QueueList    = [];

    if ($TicketObject) {
        $QueueList = $TicketObject->CustomerQueueList( User => $User );
    }

    my $Forms = [];
    if ( $FormObject && $User->{customer_id} ) {
        $Forms = $FormObject->FormListForCustomer(
            CustomerID => $User->{customer_id},
            Language   => $Language,
        );
    }

    my %AllowedForm = map { ( $_->{id} || 0 ) => $_ } @{$Forms};
    my $SelectedFormID = $Request->{FormID} || 0;
    $SelectedFormID = $Forms->[0]->{id} if @{$Forms} == 1 && !$SelectedFormID;
    my $SelectedForm = $AllowedForm{$SelectedFormID};

    if ( $FormObject && ( $Request->{Step} || '' ) eq 'CustomerTicketFormSubmit' ) {
        if ($SelectedForm) {
            my $Created = $FormObject->SubmissionCreate(
                Context   => 'customer',
                FormID    => $SelectedForm->{id},
                User      => $User,
                Request   => $Request,
                Language  => $Language,
                UserAgent => $ENV{HTTP_USER_AGENT} || '',
            );
            if ( $Created && $Created->{TicketID} ) {
                if ( $Request->{CMDBCIID} ) {
                    $CMDBObject->TicketLinkAdd(
                        TicketID       => $Created->{TicketID},
                        CIID           => $Request->{CMDBCIID},
                        User           => $User,
                        CustomerContext => 1,
                    );
                }
                return {
                    Redirect => 'index.pl?Page=CustomerTicketZoom&TicketID=' . $Created->{TicketID},
                };
            }
            $CreateError = $FormObject->Error() || 'Translate:TicketCreateFailed';
        }
        else {
            $CreateError = 'Translate:TicketFormUnavailable';
        }
    }

    # Keep the established ticket form available until an administrator creates
    # the first individual customer form.
    if ( !@{$Forms} && $TicketObject && ( $Request->{Step} || '' ) eq 'CustomerTicketCreate' ) {
        my $TicketID = $TicketObject->TicketCreateFromCustomer(
            User        => $User,
            QueueID     => $Request->{QueueID},
            Title       => $Request->{Title},
            Body        => $Request->{Body},
            ContentType => 'text/html',
        );

        if ($TicketID) {
            if ( $Request->{CMDBCIID} ) {
                $CMDBObject->TicketLinkAdd(
                    TicketID        => $TicketID,
                    CIID            => $Request->{CMDBCIID},
                    User            => $User,
                    CustomerContext => 1,
                );
            }
            return {
                Redirect => 'index.pl?Page=CustomerTicketZoom&TicketID=' . $TicketID,
            };
        }

        $CreateError = $TicketObject->Error() || 'Translate:TicketCreateFailed';
    }

    my @FormCards;
    for my $Form ( @{$Forms} ) {
        push @FormCards, {
            %{$Form},
            open_url => 'index.pl?Page=CustomerTicketCreate&FormID=' . ( $Form->{id} || 0 ),
            queue_display => $Form->{queue_full_name} || $Form->{queue_name} || '-',
        };
    }

    my $FieldsHTML = '';
    if ($SelectedForm) {
        $FieldsHTML = $FormObject->FieldsHTML(
            Form     => $SelectedForm,
            Request  => $Request,
            Language => $Language,
        );
        $CreateError ||= $FormObject->Error();
    }
    my $CMDBSelectionHTML = $CMDBObject->CustomerTicketSelectionHTML(
        User     => $User,
        Selected => $Request->{CMDBCIID},
        Language => $Language,
    );

    return {
        Template => 'CustomerTicketCreate.tt',
        Data     => {
            PageTitle          => 'Translate:TicketCreateNew',
            ProgramTitle       => 'Translate:TicketCreateNew',
            ProgramDescription => 'Translate:ProgramTicketsDescription',
            TicketListURL      => 'index.pl?Page=CustomerTicketList',
            QueueOptionsHTML   => $Self->_QueueOptionsHTML( QueueList => $QueueList ),
            HasQueueOptions    => scalar @{$QueueList} ? 1 : 0,
            ShowLegacyForm     => @{$Forms} ? 0 : 1,
            ShowFormSelection  => @{$Forms} > 1 && !$SelectedForm ? 1 : 0,
            ShowConfiguredForm => $SelectedForm ? 1 : 0,
            TicketForms        => \@FormCards,
            FormID             => $SelectedForm ? $SelectedForm->{id} : '',
            TicketFormTitle    => $SelectedForm ? $SelectedForm->{title} : '',
            TicketFormDescription => $SelectedForm ? $SelectedForm->{description} : '',
            TicketFormSubmitLabel => $SelectedForm
                ? ( $SelectedForm->{submit_label} || 'Translate:TicketFormSubmit' ) : '',
            TicketFormFieldsHTML => $FieldsHTML,
            CMDBSelectionHTML    => $CMDBSelectionHTML,
            FormSelectionURL   => 'index.pl?Page=CustomerTicketCreate',
            CreateError        => $CreateError,
            CreateErrorClass   => $CreateError ? '' : 'qisutu-hidden',
            FormAction         => 'index.pl',
        },
    };
}

sub _QueueOptionsHTML {
    my ( $Self, %Param ) = @_;

    my $QueueList = $Param{QueueList} || [];
    my $HTML      = '';

    for my $Queue ( @{$QueueList} ) {
        my $Name = $Queue->{full_name} || $Queue->{name} || '';
        $HTML .= '<option value="' . $Self->_Escape( $Queue->{id} ) . '">' . $Self->_Escape($Name) . '</option>';
    }

    return $HTML;
}

sub _Escape {
    my ( $Self, $Value ) = @_;

    $Value = '' if !defined $Value;

    if ( $Self->{Output} ) {
        return $Self->{Output}->HTMLEscape($Value);
    }

    $Value =~ s{&}{&amp;}g;
    $Value =~ s{<}{&lt;}g;
    $Value =~ s{>}{&gt;}g;
    $Value =~ s{"}{&quot;}g;

    return $Value;
}

sub _TicketObject {
    my ($Self) = @_;

    return if !$Self->{DB};

    my $Loaded = eval {
        require QisutuPermission;
        require QisutuTicket;
        1;
    };

    if ( !$Loaded ) {
        return;
    }

    my $PermissionObject = QisutuPermission->new(
        Config => $Self->{Config},
        DB     => $Self->{DB},
    );

    return QisutuTicket->new(
        Config     => $Self->{Config},
        DB         => $Self->{DB},
        Permission => $PermissionObject,
    );
}

sub _TicketFormObject {
    my ($Self) = @_;

    return if !$Self->{DB};

    my $Loaded = eval {
        require QisutuPermission;
        require QisutuTicketForm;
        1;
    };
    return if !$Loaded;

    my $PermissionObject = QisutuPermission->new(
        Config => $Self->{Config},
        DB     => $Self->{DB},
    );

    return QisutuTicketForm->new(
        Config     => $Self->{Config},
        DB         => $Self->{DB},
        Output     => $Self->{Output},
        Permission => $PermissionObject,
    );
}

1;
