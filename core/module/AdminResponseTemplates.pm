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

package AdminResponseTemplates;

use strict;
use warnings;
use utf8;

use QisutuHTML;
use QisutuResponseTemplate;

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
    my $Step     = $Request->{Step} || '';
    my $UserID   = $User->{user_account_id} || 1;
    my $Object   = QisutuResponseTemplate->new(
        Config => $Self->{Config},
        DB     => $Self->{DB},
    );
    my $TemplateLanguage = $Object->LanguageClean(
        $Request->{TemplateLanguage} || $Language,
    );
    my $ErrorMessage = '';
    my $AttachmentMaxSizeMB    = $Self->_AttachmentMaxSizeMB();
    my $AttachmentMaxSizeBytes = $AttachmentMaxSizeMB * 1024 * 1024;

    if ( !$Object->SchemaEnsure() ) {
        $ErrorMessage = $Object->Error() || 'Translate:AdminResponseTemplateSaveFailed';
    }

    if ( !$ErrorMessage && ( $Step eq 'ResponseTemplateCreate' || $Step eq 'ResponseTemplateUpdate' ) ) {
        my $UploadResult = $Self->_UploadedAttachments(
            Request      => $Request,
            MaxSizeBytes => $AttachmentMaxSizeBytes,
        );

        if ( @{ $UploadResult->{Oversized} || [] } ) {
            my $Filename = $UploadResult->{Oversized}->[0]->{Filename} || 'attachment';
            $ErrorMessage = $Self->_Translate(
                Key      => 'AdminResponseTemplateAttachmentTooLarge',
                Language => $Language,
            );
            $ErrorMessage =~ s{\{\{Filename\}\}}{$Filename}g;
            $ErrorMessage =~ s{\{\{MaxSize\}\}}{$AttachmentMaxSizeMB . ' MB'}ge;
        }
        else {
            my $TransactionStarted = $Self->{DB}->BeginWork() ? 1 : 0;

            if ( !$TransactionStarted ) {
                $ErrorMessage = 'Translate:AdminResponseTemplateSaveFailed';
            }
            else {
                my $TemplateID;
                my $Saved;

                if ( $Step eq 'ResponseTemplateCreate' ) {
                    $TemplateID = $Object->TemplateCreate(
                        Language        => $TemplateLanguage,
                        Name            => $Request->{Name},
                        Description     => $Request->{Description},
                        Content         => $Request->{Content},
                        SortOrder       => $Request->{SortOrder},
                        ChangedByUserID => $UserID,
                    );
                    $Saved = $TemplateID ? 1 : 0;
                }
                else {
                    $TemplateID = $Request->{TemplateID} || 0;
                    $Saved = $Object->TemplateUpdate(
                        TemplateID     => $TemplateID,
                        Language       => $TemplateLanguage,
                        Name           => $Request->{Name},
                        Description    => $Request->{Description},
                        Content        => $Request->{Content},
                        Active         => $Request->{Active},
                        SortOrder      => $Request->{SortOrder},
                        ChangedByUserID => $UserID,
                    );
                }

                if ($Saved) {
                    for my $Attachment ( @{ $UploadResult->{Attachments} || [] } ) {
                        if ( !$Object->AttachmentCreate(
                            TemplateID     => $TemplateID,
                            Attachment     => $Attachment,
                            ChangedByUserID => $UserID,
                        ) ) {
                            $Saved = 0;
                            last;
                        }
                    }
                }

                if ( $Saved && $Self->{DB}->Commit() ) {
                    return {
                        Redirect => 'index.pl?Page=AdminResponseTemplates;Action=Edit;TemplateID='
                            . $TemplateID
                            . ';TemplateLanguage='
                            . $Self->_URLEncode($TemplateLanguage),
                    };
                }

                eval { $Self->{DB}->Rollback(); 1; };
                $ErrorMessage = $Object->Error() || $Self->{DB}->Error() || 'Translate:AdminResponseTemplateSaveFailed';
            }
        }

        $Action = $Step eq 'ResponseTemplateCreate' ? 'Create' : 'Edit';
    }
    elsif ( !$ErrorMessage && $Step eq 'ResponseTemplateDeactivate' ) {
        if ( $Object->TemplateDeactivate(
            TemplateID      => $Request->{TemplateID},
            ChangedByUserID => $UserID,
        ) ) {
            return {
                Redirect => 'index.pl?Page=AdminResponseTemplates;TemplateLanguage='
                    . $Self->_URLEncode($TemplateLanguage),
            };
        }
        $ErrorMessage = $Object->Error() || 'Translate:AdminResponseTemplateDeactivateFailed';
    }
    elsif ( !$ErrorMessage && $Step eq 'ResponseTemplateAttachmentDelete' ) {
        my $TemplateID = $Request->{TemplateID} || 0;
        if ( $Object->AttachmentDelete(
            TemplateID   => $TemplateID,
            AttachmentID => $Request->{AttachmentID},
        ) ) {
            return {
                Redirect => 'index.pl?Page=AdminResponseTemplates;Action=Edit;TemplateID='
                    . $TemplateID
                    . ';TemplateLanguage='
                    . $Self->_URLEncode($TemplateLanguage),
            };
        }
        $ErrorMessage = $Object->Error() || 'Translate:AdminResponseTemplateAttachmentDeleteFailed';
        $Action = 'Edit';
    }
    elsif ( !$ErrorMessage && $Step eq 'ResponseTemplateQueueSave' ) {
        my $TemplateID = $Request->{TemplateID} || 0;
        my $QueueIDs   = $Self->_IDList( $Request->{QueueID} );

        if ( $Self->{DB}->BeginWork() ) {
            if ( $Object->TemplateQueueSet(
                TemplateID      => $TemplateID,
                QueueIDs        => $QueueIDs,
                ChangedByUserID => $UserID,
            ) && $Self->{DB}->Commit() ) {
                return {
                    Redirect => 'index.pl?Page=AdminResponseTemplates;Action=TemplateQueue;TemplateID='
                        . $TemplateID
                        . ';TemplateLanguage='
                        . $Self->_URLEncode($TemplateLanguage),
                };
            }
            eval { $Self->{DB}->Rollback(); 1; };
        }
        $ErrorMessage = $Object->Error() || $Self->{DB}->Error() || 'Translate:AdminResponseTemplateAssignmentSaveFailed';
        $Action = 'TemplateQueue';
    }
    elsif ( !$ErrorMessage && $Step eq 'ResponseQueueTemplateSave' ) {
        my $QueueID     = $Request->{QueueID} || 0;
        my $TemplateIDs = $Self->_IDList( $Request->{TemplateID} );

        if ( $Self->{DB}->BeginWork() ) {
            if ( $Object->QueueTemplateSet(
                QueueID         => $QueueID,
                TemplateIDs     => $TemplateIDs,
                ChangedByUserID => $UserID,
            ) && $Self->{DB}->Commit() ) {
                return {
                    Redirect => 'index.pl?Page=AdminResponseTemplates;Action=QueueTemplate;QueueID='
                        . $QueueID
                        . ';TemplateLanguage='
                        . $Self->_URLEncode($TemplateLanguage),
                };
            }
            eval { $Self->{DB}->Rollback(); 1; };
        }
        $ErrorMessage = $Object->Error() || $Self->{DB}->Error() || 'Translate:AdminResponseTemplateAssignmentSaveFailed';
        $Action = 'QueueTemplate';
    }

    my $Templates = $Object->TemplateList(
        IncludeInactive => 1,
        Language        => $TemplateLanguage,
    );
    my $Queues = $Object->QueueList(
        IncludeInactive => 1,
        Language        => $TemplateLanguage,
    );
    my $Template;
    my $AssignmentTemplate;
    my $AssignmentQueue;

    for my $Item ( @{$Templates} ) {
        $Item->{active_label} = $Item->{active} ? 'Translate:CommonYes' : 'Translate:CommonNo';
        $Item->{queue_names} ||= '-';
        $Item->{content_preview} = QisutuHTML->PlainTextPreview( $Item->{content} || '', 120 );
    }

    for my $Queue ( @{$Queues} ) {
        $Queue->{active_label} = $Queue->{active} ? 'Translate:CommonYes' : 'Translate:CommonNo';
        $Queue->{template_names} ||= '-';
    }

    if ( $Action eq 'Edit' ) {
        my $TemplateID = $Request->{TemplateID} || 0;
        $Template = $Object->TemplateGet(
            TemplateID => $TemplateID,
            Language   => $TemplateLanguage,
        );
        if ( !$Template ) {
            $Action = 'List';
            $ErrorMessage ||= $Object->Error() || 'Translate:AdminResponseTemplateNotFound';
        }
        else {
            $Template->{attachments} = $Object->AttachmentList( TemplateID => $TemplateID );
        }
    }
    elsif ( $Action eq 'TemplateQueue' ) {
        my $TemplateID = $Request->{TemplateID} || 0;
        $AssignmentTemplate = $Object->TemplateGet(
            TemplateID => $TemplateID,
            Language   => $TemplateLanguage,
        );
        if ( !$AssignmentTemplate ) {
            $Action = 'List';
            $ErrorMessage ||= $Object->Error() || 'Translate:AdminResponseTemplateNotFound';
        }
        else {
            my %Selected = map { $_ => 1 } @{ $Object->TemplateQueueIDs( TemplateID => $TemplateID ) };
            for my $Queue (@{$Queues}) {
                $Queue->{assignment_checked} = $Selected{ $Queue->{id} || 0 } ? 'checked' : '';
            }
        }
    }
    elsif ( $Action eq 'QueueTemplate' ) {
        my $QueueID = $Request->{QueueID} || 0;
        ($AssignmentQueue) = grep { ( $_->{id} || 0 ) == $QueueID } @{$Queues};
        if ( !$AssignmentQueue ) {
            $Action = 'List';
            $ErrorMessage ||= 'Translate:AdminResponseTemplateQueueNotFound';
        }
        else {
            my %Selected = map { $_ => 1 } @{ $Object->QueueTemplateIDs( QueueID => $QueueID ) };
            for my $Item (@{$Templates}) {
                $Item->{assignment_checked} = $Selected{ $Item->{id} || 0 } ? 'checked' : '';
            }
        }
    }

    if ( !$ErrorMessage && $Object->Error() ) {
        $ErrorMessage = $Object->Error();
    }

    my $FormName        = $Template ? $Template->{name} : ( $Request->{Name} || '' );
    my $FormDescription = $Template ? $Template->{description} : ( $Request->{Description} || '' );
    my $FormContent     = $Template ? $Template->{content} : ( $Request->{Content} || '' );
    my $FormSortOrder   = $Template ? $Template->{sort_order} : ( $Request->{SortOrder} || 1000 );
    my $FormActive      = $Template ? $Template->{active} : 1;

    return {
        Template => 'AdminResponseTemplates.tt',
        Data     => {
            PageTitle          => 'Translate:AdminResponseTemplatesTitle',
            PageCSS            => 'qisutu-response-templates.css?v=2026081601',
            ProgramTitle       => 'Translate:AdminResponseTemplatesTitle',
            ProgramDescription => 'Translate:AdminResponseTemplatesDescription',
            FormAction         => 'index.pl',
            CurrentLanguage    => $TemplateLanguage,
            LanguageOptionsHTML => $Self->_LanguageOptionsHTML(
                Languages => $Object->LanguageList(),
                Selected  => $TemplateLanguage,
            ),
            TemplateList       => $Templates,
            TemplateCount      => scalar @{$Templates},
            QueueList          => $Queues,
            QueueCount         => scalar @{$Queues},
            ShowList           => $Action eq 'List' ? 1 : 0,
            ShowCreate         => $Action eq 'Create' ? 1 : 0,
            ShowEdit           => $Action eq 'Edit' ? 1 : 0,
            ShowTemplateQueue  => $Action eq 'TemplateQueue' ? 1 : 0,
            ShowQueueTemplate  => $Action eq 'QueueTemplate' ? 1 : 0,
            TemplateID         => $Template ? $Template->{id} : ( $Request->{TemplateID} || 0 ),
            TemplateName       => $FormName,
            TemplateDescription => $FormDescription,
            TemplateContent    => $FormContent,
            TemplateSortOrder  => $FormSortOrder,
            TemplateActiveChecked => $FormActive ? 'checked' : '',
            TemplateAttachments => $Template ? ( $Template->{attachments} || [] ) : [],
            HasTemplateAttachments => $Template && @{ $Template->{attachments} || [] } ? 1 : 0,
            AssignmentTemplateID   => $AssignmentTemplate ? $AssignmentTemplate->{id} : 0,
            AssignmentTemplateName => $AssignmentTemplate ? $AssignmentTemplate->{name} : '',
            AssignmentQueueID      => $AssignmentQueue ? $AssignmentQueue->{id} : 0,
            AssignmentQueueName    => $AssignmentQueue ? $AssignmentQueue->{full_name} : '',
            AttachmentMaxSizeMB    => $AttachmentMaxSizeMB,
            ErrorMessage           => $ErrorMessage,
            ErrorClass             => $ErrorMessage ? '' : 'qisutu-hidden',
        },
    };
}

sub _UploadedAttachments {
    my ( $Self, %Param ) = @_;

    my $Request      = $Param{Request} || {};
    my $MaxSizeBytes = $Param{MaxSizeBytes} || 0;
    my $Uploads      = $Request->{__Uploads} || {};
    my $RawList      = [];

    if ( ref $Uploads->{ResponseTemplateAttachment} eq 'ARRAY' ) {
        $RawList = $Uploads->{ResponseTemplateAttachment};
    }
    elsif ( ref $Uploads->{'ResponseTemplateAttachment[]'} eq 'ARRAY' ) {
        $RawList = $Uploads->{'ResponseTemplateAttachment[]'};
    }

    my @Attachments;
    my @Oversized;

    for my $Upload ( @{$RawList} ) {
        next if ref $Upload ne 'HASH';

        my $Filename = $Upload->{Filename} || '';
        $Filename =~ s{\\}{/}g;
        $Filename =~ s{\A.*/}{}g;
        $Filename =~ s{[\r\n\x00]}{}g;
        $Filename =~ s{\A\s+|\s+\z}{}g;
        next if !$Filename;

        my $Content = $Upload->{Content};
        next if !defined $Content;

        my $Size = $Upload->{ContentSize};
        $Size = length($Content) if !defined $Size || $Size !~ m{\A\d+\z};

        my $Attachment = {
            Filename           => $Filename,
            ContentType        => $Upload->{ContentType} || 'application/octet-stream',
            Content            => $Content,
            ContentSize        => $Size,
            ContentDisposition => 'attachment',
        };

        if ( $MaxSizeBytes && $Size > $MaxSizeBytes ) {
            push @Oversized, $Attachment;
        }
        else {
            push @Attachments, $Attachment;
        }
    }

    return {
        Attachments => \@Attachments,
        Oversized   => \@Oversized,
    };
}

sub _AttachmentMaxSizeMB {
    my ($Self) = @_;

    my $Value = 25;
    my $Row = $Self->{DB}->SelectRow(
        'SELECT setting_value
         FROM system_setting
         WHERE setting_key = ?
         LIMIT 1',
        'system.attachment_max_size_mb',
    );

    if ( $Row && defined $Row->{setting_value} && $Row->{setting_value} =~ m{\A\d+\z} && $Row->{setting_value} >= 1 ) {
        $Value = $Row->{setting_value};
    }

    return $Value;
}

sub _IDList {
    my ( $Self, $Value ) = @_;

    my @Values = ref $Value eq 'ARRAY' ? @{$Value} : ( defined $Value ? ($Value) : () );
    my %Seen;
    my @IDs = grep { defined $_ && $_ =~ m{\A\d+\z} && $_ > 0 && !$Seen{$_}++ } @Values;

    return \@IDs;
}

sub _LanguageOptionsHTML {
    my ( $Self, %Param ) = @_;

    my $HTML = '';

    for my $Language ( @{ $Param{Languages} || [] } ) {
        my $Code     = $Language->{code} || '';
        my $Label    = $Language->{label} || $Code;
        my $Selected = $Code eq ( $Param{Selected} || '' ) ? ' selected' : '';

        $HTML .= '<option value="' . $Self->_HTMLEscape($Code) . '"' . $Selected . '>'
            . $Self->_HTMLEscape($Label)
            . '</option>';
    }

    return $HTML;
}

sub _HTMLEscape {
    my ( $Self, $Value ) = @_;

    return $Self->{Output}->HTMLEscape($Value) if $Self->{Output};

    $Value = '' if !defined $Value;
    $Value =~ s{&}{&amp;}g;
    $Value =~ s{<}{&lt;}g;
    $Value =~ s{>}{&gt;}g;
    $Value =~ s{"}{&quot;}g;
    $Value =~ s{'}{&#39;}g;

    return $Value;
}

sub _URLEncode {
    my ( $Self, $Value ) = @_;

    $Value = '' if !defined $Value;
    $Value =~ s{([^A-Za-z0-9_\-\.])}{sprintf('%%%02X', ord($1))}eg;

    return $Value;
}

sub _Translate {
    my ( $Self, %Param ) = @_;

    return $Param{Key} || '' if !$Self->{Output};

    return $Self->{Output}->Translate(
        Key      => $Param{Key},
        Language => $Param{Language} || 'en',
    );
}

1;
