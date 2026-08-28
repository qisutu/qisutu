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
    my $AttachmentMaxSizeMB    = $Self->_AttachmentMaxSizeMB();
    my $AttachmentMaxSizeBytes = $AttachmentMaxSizeMB * 1024 * 1024;
    my $StandardTicketWithForms = $Self->_CustomerStandardTicketWithForms();

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
    $SelectedFormID = $Forms->[0]->{id}
        if @{$Forms} == 1 && !$SelectedFormID && !$StandardTicketWithForms;
    my $SelectedForm = $AllowedForm{$SelectedFormID};
    my $StandardTicketSelected = ( $Request->{StandardTicket} || '' ) eq '1'
        && ( !@{$Forms} || $StandardTicketWithForms ) ? 1 : 0;

    if ( $FormObject && ( $Request->{Step} || '' ) eq 'CustomerTicketFormSubmit' ) {
        if ($SelectedForm) {
            my $UploadResult = $Self->_UploadedAttachments(
                Request      => $Request,
                MaxSizeBytes => $AttachmentMaxSizeBytes,
            );
            if ( @{ $UploadResult->{Oversized} || [] } ) {
                $CreateError = $Self->_AttachmentTooLargeMessage(
                    Attachment => $UploadResult->{Oversized}->[0],
                    MaxSizeMB  => $AttachmentMaxSizeMB,
                    Language   => $Language,
                );
            }
            my $Created;
            if ( !$CreateError ) {
                $Created = $FormObject->SubmissionCreate(
                    Context     => 'customer',
                    FormID      => $SelectedForm->{id},
                    User        => $User,
                    Request     => $Request,
                    Language    => $Language,
                    UserAgent   => $ENV{HTTP_USER_AGENT} || '',
                    Attachments => $UploadResult->{Attachments},
                );
            }
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
            $CreateError ||= $FormObject->Error() || 'Translate:TicketCreateFailed';
        }
        else {
            $CreateError = 'Translate:TicketFormUnavailable';
        }
    }

    if ( $TicketObject && ( $Request->{Step} || '' ) eq 'CustomerTicketCreate'
        && ( !@{$Forms} || $StandardTicketWithForms )
    ) {
        my $UploadResult = $Self->_UploadedAttachments(
            Request      => $Request,
            MaxSizeBytes => $AttachmentMaxSizeBytes,
        );
        my $TicketID;
        if ( @{ $UploadResult->{Oversized} || [] } ) {
            $CreateError = $Self->_AttachmentTooLargeMessage(
                Attachment => $UploadResult->{Oversized}->[0],
                MaxSizeMB  => $AttachmentMaxSizeMB,
                Language   => $Language,
            );
        }
        else {
            $TicketID = $TicketObject->TicketCreateFromCustomer(
                User        => $User,
                QueueID     => $Request->{QueueID},
                Title       => $Request->{Title},
                Body        => $Request->{Body},
                ContentType => 'text/html',
                Attachments => $UploadResult->{Attachments},
            );
        }

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

        $CreateError ||= $TicketObject->Error() || 'Translate:TicketCreateFailed';
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
            ShowLegacyForm     => !$SelectedForm && ( !@{$Forms} || $StandardTicketSelected ) ? 1 : 0,
            ShowFormSelection  => @{$Forms} && !$SelectedForm && !$StandardTicketSelected ? 1 : 0,
            ShowConfiguredForm => $SelectedForm ? 1 : 0,
            ShowStandardTicketCard => @{$Forms} && $StandardTicketWithForms ? 1 : 0,
            StandardTicketURL  => 'index.pl?Page=CustomerTicketCreate&StandardTicket=1',
            ShowStandardBackToSelection => @{$Forms} && $StandardTicketSelected ? 1 : 0,
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
            AttachmentMaxSizeMB => $AttachmentMaxSizeMB,
            AttachmentMaxSizeBytes => $AttachmentMaxSizeBytes,
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

sub _UploadedAttachments {
    my ( $Self, %Param ) = @_;

    my $Request      = $Param{Request} || {};
    my $MaxSizeBytes = $Param{MaxSizeBytes} || 0;
    my $Uploads      = $Request->{__Uploads} || {};
    my $RawList      = ref $Uploads->{TicketAttachment} eq 'ARRAY'
        ? $Uploads->{TicketAttachment}
        : ref $Uploads->{'TicketAttachment[]'} eq 'ARRAY'
            ? $Uploads->{'TicketAttachment[]'}
            : [];
    my ( @Attachments, @Oversized );

    for my $Upload ( @{$RawList} ) {
        next if ref $Upload ne 'HASH';
        my $Filename = $Upload->{Filename} || '';
        $Filename =~ s{\\}{/}g;
        $Filename =~ s{\A.*/}{}g;
        $Filename =~ s{[\r\n\x00]}{}g;
        $Filename =~ s{\A\s+|\s+\z}{}g;
        next if !$Filename || !defined $Upload->{Content};
        my $ContentSize = $Upload->{ContentSize};
        $ContentSize = length $Upload->{Content}
            if !defined $ContentSize || $ContentSize !~ m{\A\d+\z};
        my $Attachment = {
            Filename           => $Filename,
            ContentType        => $Upload->{ContentType} || 'application/octet-stream',
            Content            => $Upload->{Content},
            ContentSize        => $ContentSize,
            ContentDisposition => 'attachment',
        };
        if ( $MaxSizeBytes && $ContentSize > $MaxSizeBytes ) {
            push @Oversized, $Attachment;
        }
        else {
            push @Attachments, $Attachment;
        }
    }
    return { Attachments => \@Attachments, Oversized => \@Oversized };
}

sub _AttachmentMaxSizeMB {
    my ($Self) = @_;
    my $Value = 25;
    if ( $Self->{DB} && eval { require QisutuSystemSetting; 1 } ) {
        $Value = QisutuSystemSetting->new(
            Config => $Self->{Config}, DB => $Self->{DB},
        )->AttachmentMaxSizeMB();
    }
    return $Value;
}

sub _CustomerStandardTicketWithForms {
    my ($Self) = @_;

    return 0 if !$Self->{DB} || !eval { require QisutuSystemSetting; 1 };
    return QisutuSystemSetting->new(
        Config => $Self->{Config}, DB => $Self->{DB},
    )->CustomerStandardTicketWithForms();
}

sub _AttachmentTooLargeMessage {
    my ( $Self, %Param ) = @_;
    my $Filename = $Param{Attachment}->{Filename} || 'attachment';
    my $MaxSizeMB = $Param{MaxSizeMB} || 25;
    my $Language = $Param{Language} || 'en';
    my $Template = $Self->{Output}->Translate(
        Key => 'TicketArticleAttachmentTooLargeServer', Language => $Language,
    ) || '';
    $Template ||= $Language eq 'de'
        ? 'Der Anhang „{{Filename}}“ überschreitet die erlaubte Maximalgröße von {{MaxSize}}. Bitte wenden Sie sich an den Administrator.'
        : 'The attachment “{{Filename}}” exceeds the permitted maximum size of {{MaxSize}}. Please contact the administrator.';
    $Template =~ s{\{\{Filename\}\}}{$Filename}g;
    my $MaxSize = $MaxSizeMB . ' MB';
    $Template =~ s{\{\{MaxSize\}\}}{$MaxSize}g;
    return $Template;
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
