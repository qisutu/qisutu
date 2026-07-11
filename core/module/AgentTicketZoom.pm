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

package AgentTicketZoom;

use strict;
use warnings;
use utf8;
use JSON::PP qw(encode_json);
use Time::Local qw(timelocal);

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
    my $Language = $Request->{Language} || $Self->{Config}->{Language}->{Default} || 'en';
    my $TicketID = $Request->{TicketID} || 0;
    my $Ticket   = undef;
    my $Articles = [];
    my $ArticleCreateError = '';

    my $TicketObject = $Self->_TicketObject();
    my $AttachmentMaxSizeMB    = $Self->_AttachmentMaxSizeMB();
    my $AttachmentMaxSizeBytes = $AttachmentMaxSizeMB * 1024 * 1024;

    if ( ( $Request->{Step} || '' ) eq 'AgentLookup' ) {
        return $Self->_JSONResponse(
            Data => $Self->_AgentLookup(
                Query => $Request->{Term} || $Request->{term} || $Request->{Query} || $Request->{query} || $Request->{q} || '',
            ),
        );
    }

    if ( ( $Request->{Step} || '' ) eq 'CustomerUserLookup' ) {
        return $Self->_JSONResponse(
            Data => $Self->_CustomerUserLookup(
                Query => $Request->{Term} || $Request->{term} || $Request->{Query} || $Request->{query} || $Request->{q} || '',
            ),
        );
    }

    my $ToolActionError  = '';
    my $ToolActionActive = 'priority';

    if ( $TicketObject && ( $Request->{Step} || '' ) eq 'TicketToolUpdate' ) {
        my $ToolResult = $Self->_TicketToolUpdate(
            Request      => $Request,
            User         => $Param{User} || {},
            Language     => $Language,
            TicketObject => $TicketObject,
            TicketID     => $TicketID,
        );

        $ToolActionActive = $ToolResult->{ActiveTool} || $ToolActionActive;

        if ( $ToolResult->{Success} ) {
            return {
                Redirect => 'index.pl?Page=AgentTicketZoom&TicketID=' . $TicketID,
            };
        }

        $ToolActionError = $ToolResult->{Error} || 'Translate:TicketToolUpdateFailed';
    }


    if ( $TicketObject && ( $Request->{Step} || '' ) eq 'ArticleCreate' ) {
        my $User        = $Param{User} || {};
        my $ArticleMode = $Request->{ArticleMode} || 'note';
        my $Body        = $Request->{Body} || '';
        my $UploadResult = $Self->_UploadedAttachments(
            Request      => $Request,
            MaxSizeBytes => $AttachmentMaxSizeBytes,
        );
        my $Attachments = $UploadResult->{Attachments} || [];

        if ( @{ $UploadResult->{Oversized} || [] } ) {
            $ArticleCreateError = $Self->_AttachmentTooLargeMessage(
                Attachment => $UploadResult->{Oversized}->[0],
                MaxSizeMB  => $AttachmentMaxSizeMB,
                Language   => $Language,
            );
        }

        if ( $ArticleMode ne 'email' && $ArticleMode ne 'forward' ) {
            $ArticleMode = 'note';
        }

        if ( $ArticleMode eq 'email' || $ArticleMode eq 'forward' ) {
            $Body = $Self->_ForwardMailHTMLNormalize( HTML => $Body );
        }

        my $TicketForSubmit = $TicketObject->TicketGet(
            TicketID  => $TicketID,
            User      => $User,
            Language  => $Language,
        );

        if ( !$TicketForSubmit ) {
            $ArticleCreateError = $TicketObject->Error() || 'Translate:TicketArticleCreateFailed';
        }

        my $Channel    = $ArticleMode eq 'note' ? 'note' : 'email';
        my $Visibility = $ArticleMode eq 'forward' ? 'agent' : 'both';
        my $SenderType = 'agent';

        if ( $ArticleMode eq 'note' ) {
            $Visibility = $Request->{CustomerVisible} ? 'both' : 'agent';
        }

        my ( $ToName, $ToEmail ) = ( '', '' );
        my $CcEmail = '';
        my ( $FromName, $FromEmail ) = (
            $Self->_UserName( User => $User ),
            $User->{email} || '',
        );
        my $Subject      = $Request->{Subject} || '';
        my $StatusID     = $Self->_SubmittedStatusID( StatusID => $Request->{StatusID} );
        my $PendingUntil = $Request->{PendingUntil} || '';

        if ( !$ArticleCreateError && !$Self->_BodyHasVisibleContent( Body => $Body ) ) {
            $ArticleCreateError = 'Translate:TicketArticleBodyRequired';
        }

        if ( !$ArticleCreateError && !$StatusID ) {
            $ArticleCreateError = 'Translate:TicketStatusUpdateFailed';
        }

        if ( !$ArticleCreateError && ( $ArticleMode eq 'email' || $ArticleMode eq 'forward' ) ) {
            if ( $ArticleMode eq 'email' ) {
                ( $ToName, $ToEmail ) = $Self->_ReplyRecipient(
                    TicketObject => $TicketObject,
                    TicketID     => $TicketID,
                    User         => $User,
                );
            }

            my $SubmittedTo = $Request->{ReplyTo} || '';
            $ToEmail = $SubmittedTo if $SubmittedTo;

            my $ToCheck = $Self->_EmailRecipientsParse(
                Value    => $ToEmail,
                Required => 1,
            );

            if ( !$ToCheck->{Valid} ) {
                $ArticleCreateError = $ToCheck->{Error} || 'Translate:TicketArticleRecipientRequired';
            }
            else {
                $ToName  = '' if $SubmittedTo;
                $ToEmail = $ToCheck->{Header};
            }

            if ( !$ArticleCreateError ) {
                my $CcCheck = $Self->_EmailRecipientsParse(
                    Value    => $Request->{ReplyCc} || '',
                    Required => 0,
                );

                if ( !$CcCheck->{Valid} ) {
                    $ArticleCreateError = $CcCheck->{Error} || 'Translate:TicketToolForwardRecipientInvalid';
                }
                else {
                    $CcEmail = $CcCheck->{Header};
                }
            }

            ( $FromName, $FromEmail ) = $Self->_ReplySender(
                TicketID => $TicketID,
                User     => $User,
            );

            $Subject ||= $Self->_DefaultReplySubject(
                TicketObject => $TicketObject,
                TicketID     => $TicketID,
                User         => $User,
                Language     => $Language,
            );

            if ( !$ArticleCreateError && $TicketObject->can('TicketSubjectBuild') ) {
                $Subject = $TicketObject->TicketSubjectBuild(
                    TicketID => $TicketID,
                    Subject  => $Subject,
                );
            }

            if ( !$ArticleCreateError ) {
                my $Precheck = $Self->_EmailSendPrecheck(
                    FromEmail => $FromEmail,
                    ToEmail   => $ToEmail,
                );

                if ( !$Precheck->{Success} ) {
                    $ArticleCreateError = $Precheck->{Message} || 'Translate:TicketArticleSendFailed';
                }
            }
        }

        if ( !$ArticleCreateError ) {
            $Self->{DB}->BeginWork() || do {
                $ArticleCreateError = 'Translate:TicketArticleCreateFailed';
            };
        }

        my $ArticleID;

        if ( !$ArticleCreateError ) {
            $ArticleID = $TicketObject->ArticleCreate(
                TicketID        => $TicketID,
                User            => $User,
                Subject         => $Subject,
                Body            => $Body,
                Channel         => $Channel,
                SenderType      => $SenderType,
                FromName        => $FromName,
                FromEmail       => $FromEmail,
                ToName          => $ToName,
                ToEmail         => $ToEmail,
                Cc              => $CcEmail,
                ContentType     => 'text/html',
                Visibility      => $Visibility,
                Language        => $Language,
                CreatedByUserID => $User->{user_account_id},
                ChangedByUserID => $User->{user_account_id},
                Attachments     => $Attachments,
            );

            if ( !$ArticleID ) {
                $ArticleCreateError = $TicketObject->Error() || 'Translate:TicketArticleCreateFailed';
                $Self->{DB}->Rollback();
            }
        }

        if ( !$ArticleCreateError && $ArticleMode eq 'email' ) {
            my $AgentUserID = $User->{user_account_id} || 0;

            if ( !$AgentUserID ) {
                $ArticleCreateError = 'Translate:TicketArticleCreateFailed';
                $Self->{DB}->Rollback();
            }
            elsif ( ( $TicketForSubmit->{owner_user_id} || 0 ) != $AgentUserID ) {
                if (
                    !$TicketObject->TicketOwnerUpdate(
                        TicketID             => $TicketID,
                        OwnerUserID          => $AgentUserID,
                        User                 => $User,
                        ChangedByUserID      => $AgentUserID,
                        SuppressNotification => 1,
                    )
                ) {
                    $ArticleCreateError = $TicketObject->Error() || 'Translate:TicketArticleCreateFailed';
                    $Self->{DB}->Rollback();
                }
            }
        }

        if ( !$ArticleCreateError ) {
            if (
                !$TicketObject->TicketStatusUpdate(
                    TicketID        => $TicketID,
                    StatusID        => $StatusID,
                    ChangedByUserID => $User->{user_account_id},
                    PendingUntil     => $PendingUntil,
                )
            ) {
                $ArticleCreateError = $TicketObject->Error() || 'Translate:TicketStatusUpdateFailed';
                $Self->{DB}->Rollback();
            }
        }

        if ( !$ArticleCreateError && ( $ArticleMode eq 'email' || $ArticleMode eq 'forward' ) ) {
            my $SendResult = $Self->_EmailSend(
                FromName    => $FromName,
                FromEmail   => $FromEmail,
                ToName      => $ToName,
                ToEmail     => $ToEmail,
                Cc          => $CcEmail,
                Subject     => $Subject,
                Body        => $Body,
                Attachments => $Attachments,
            );

            if ( !$SendResult->{Success} ) {
                $ArticleCreateError = $SendResult->{Message} || 'Translate:TicketArticleSendFailed';
                $Self->{DB}->Rollback();
            }
        }

        if ( !$ArticleCreateError ) {
            if ( $Self->{DB}->Commit() ) {
                return {
                    Redirect => 'index.pl?Page=AgentTicketZoom&TicketID=' . $TicketID,
                };
            }

            $ArticleCreateError = 'Translate:TicketArticleCreateFailed';
            $Self->{DB}->Rollback();
        }
    }

    if ($TicketObject) {
        $Ticket = $TicketObject->TicketGet(
            TicketID  => $TicketID,
            User      => $Param{User} || {},
            Language  => $Language,
        );
    }

    if ( !$Ticket ) {
        return {
            Template => 'AgentTicketZoom.tt',
            Data     => {
                PageTitle          => 'Translate:TicketZoomTitle',
                ProgramTitle       => 'Translate:TicketZoomTitle',
                ProgramDescription => 'Translate:TicketZoomDescription',
                TicketFound        => 0,
                TicketListURL      => 'index.pl?Page=AgentTicketList',
            },
        };
    }

    $Articles = $TicketObject->ArticleList(
        TicketID => $Ticket->{id},
        User     => $Param{User} || {},
        Language => $Language,
    );

    my $FallbackSenderName  = '';
    my $FallbackSenderEmail = '';
    my $ArticleIndex        = 0;
    my $ArticleCount        = scalar @{$Articles};
    my $ReplyEmailTemplate  = $Self->_QueueReplyTemplate( TicketID => $Ticket->{id} );

    for my $Article ( @{$Articles} ) {
        $ArticleIndex++;

        $Article->{created_at_display} = $Self->_DateTimeFormat(
            DateTime => $Article->{created_at},
            Language => $Language,
        );

        $Article->{article_open_class} = $ArticleIndex == $ArticleCount
            ? 'qisutu-ticket-article-open'
            : '';

        my $ReplyData = $Self->_ArticleReplyData(
            Ticket             => $Ticket,
            Article            => $Article,
            QueueReplyTemplate => $ReplyEmailTemplate,
            Language           => $Language,
        );

        $Article->{reply_allowed}       = $ReplyData->{Allowed} ? 1 : 0;
        $Article->{reply_button_class}  = $ReplyData->{Allowed} ? '' : 'qisutu-hidden';
        $Article->{reply_to}            = $ReplyData->{To} || '';
        $Article->{reply_cc}            = $ReplyData->{Cc} || '';
        $Article->{reply_subject}       = $ReplyData->{Subject} || '';
        $Article->{reply_body_template} = $ReplyData->{BodyTemplate} || '';

        my $ForwardData = $Self->_ArticleForwardData(
            Article  => $Article,
            Language => $Language,
        );

        $Article->{forward_subject}       = $ForwardData->{Subject} || '';
        $Article->{forward_body_template} = $ForwardData->{BodyTemplate} || '';

        if ( !$FallbackSenderEmail && ( $Article->{channel} || '' ) eq 'email' ) {
            $FallbackSenderEmail = $Article->{from_email} || '';
            $FallbackSenderName  = $Article->{from_name}  || $Article->{sender_name} || '';
        }
    }

    if ( !$FallbackSenderEmail ) {
        for my $Article ( @{$Articles} ) {
            if ( $Article->{from_email} ) {
                $FallbackSenderEmail = $Article->{from_email};
                $FallbackSenderName  = $Article->{from_name} || $Article->{sender_name} || '';
                last;
            }
        }
    }

    my $TicketCustomerUser  = $Ticket->{customer_user_name}  || $FallbackSenderName  || '-';
    my $TicketCustomerEmail = $Ticket->{customer_user_email} || $FallbackSenderEmail || '-';
    my $TicketOwnerAutocompleteValue = $Ticket->{owner_user_id} ? ( $Ticket->{owner_name} || $Ticket->{owner_login} || '' ) : '';
    my $TicketResponsibleAutocompleteValue = $Ticket->{responsible_user_id} ? ( $Ticket->{responsible_name} || $Ticket->{responsible_login} || '' ) : '';
    my $TicketCustomerAutocompleteValue = $Ticket->{customer_user_id}
        ? ( ( $Ticket->{customer_user_name} || $TicketCustomerUser || '' ) . ( ( $Ticket->{customer_name} || '' ) ? ' — ' . $Ticket->{customer_name} : '' ) )
        : '';
    my $StatusOptionsHTML   = $Self->_StatusOptionsHTML(
        Language         => $Language,
        DefaultStateName => 'open',
        CurrentStateName => $Ticket->{state_name},
    );
    my $PriorityOptionsHTML = $Self->_PriorityOptionsHTML(
        CurrentPriorityID => $Ticket->{priority_id},
        Language          => $Language,
    );
    my $QueueOptionsHTML = $Self->_QueueOptionsHTML(
        CurrentQueueID => $Ticket->{queue_id},
    );
    my $ClosedStateOptionsHTML = $Self->_ClosedStateOptionsHTML(
        Language       => $Language,
        CurrentStateID => $Ticket->{state_id},
    );

    my $ArticleEmptyClass = $ArticleCount ? 'qisutu-hidden' : '';
    my $ArticleCreateErrorClass = $ArticleCreateError ? '' : 'qisutu-hidden';
    my $ArticleReplyFormClass = $ArticleCreateError ? '' : 'qisutu-hidden';
    my $TicketToolErrorClass = $ToolActionError ? '' : 'qisutu-hidden';
    my $TicketToolsOverlayClass = $ToolActionError ? '' : 'qisutu-hidden';
    my $TicketToolsOverlayAriaHidden = $ToolActionError ? 'false' : 'true';
    my $TicketToolsButtonExpanded = $ToolActionError ? 'true' : 'false';

    return {
        Template => 'AgentTicketZoom.tt',
        Data     => {
            PageTitle          => $Ticket->{ticket_number} . ' - ' . $Ticket->{title},
            ProgramTitle       => $Ticket->{ticket_number},
            ProgramDescription => $Ticket->{title},
            TicketFound        => 1,
            TicketListURL      => 'index.pl?Page=AgentTicketList',

            TicketID              => $Ticket->{id},
            TicketNumber          => $Ticket->{ticket_number},
            TicketTitle           => $Ticket->{title},
            TicketQueue           => $Ticket->{queue_full_name} || $Ticket->{queue_name},
            TicketState           => $Ticket->{state_name_display},
            TicketStateType       => $Ticket->{state_type},
            TicketPriority        => $Ticket->{priority_name_display} || $Ticket->{priority_name},
            TicketPriorityID      => $Ticket->{priority_id} || 0,
            TicketPriorityValue   => $Ticket->{priority_value},
            TicketAge             => $Self->_AgeFormat(
                DateTime => $Ticket->{created_at},
                Language => $Language,
            ),
            TicketCustomerNumber   => $Ticket->{customer_number},
            TicketCustomerID       => $Ticket->{customer_id} || 0,
            TicketCustomerUserID   => $Ticket->{customer_user_id} || 0,
            TicketCustomer         => $Ticket->{customer_name} || '-',
            TicketCustomerUser     => $TicketCustomerUser,
            TicketCustomerAutocompleteValue => $TicketCustomerAutocompleteValue,
            TicketCustomerEmail    => $TicketCustomerEmail,
            TicketOwnerID          => $Ticket->{owner_user_id} || 0,
            TicketOwner            => $Ticket->{owner_name} || '-',
            TicketOwnerAutocompleteValue => $TicketOwnerAutocompleteValue,
            TicketOwnerEmail       => $Ticket->{owner_email},
            TicketResponsibleID    => $Ticket->{responsible_user_id} || 0,
            TicketResponsible      => $Ticket->{responsible_name} || '-',
            TicketResponsibleAutocompleteValue => $TicketResponsibleAutocompleteValue,
            TicketResponsibleEmail => $Ticket->{responsible_email},
            TicketCreatedAt        => $Self->_DateTimeFormat(
                DateTime => $Ticket->{created_at},
                Language => $Language,
            ),
            TicketChangedAt        => $Self->_DateTimeFormat(
                DateTime => $Ticket->{changed_at},
                Language => $Language,
            ),
            TicketEscalationStateLabel => $Ticket->{escalation_state_label},
            TicketEscalationStateClass => $Ticket->{escalation_state_class},
            TicketFirstResponseDueAt   => $Self->_DateTimeFormat( DateTime => $Ticket->{first_response_due_at}, Language => $Language ) || '-',
            TicketFirstResponseAt      => $Self->_DateTimeFormat( DateTime => $Ticket->{first_response_at}, Language => $Language ) || '-',
            TicketUpdateDueAt          => $Self->_DateTimeFormat( DateTime => $Ticket->{update_due_at}, Language => $Language ) || '-',
            TicketSolutionDueAt        => $Self->_DateTimeFormat( DateTime => $Ticket->{solution_due_at}, Language => $Language ) || '-',
            TicketSolutionAt           => $Self->_DateTimeFormat( DateTime => $Ticket->{solution_at}, Language => $Language ) || '-',
            TicketPendingUntil        => $Self->_DateTimeFormat( DateTime => $Ticket->{pending_until}, Language => $Language ) || '-',
            TicketPendingUntilClass   => $Ticket->{pending_until_class} || '',
            TicketPendingUntilReached => $Ticket->{pending_until_reached} || 0,
            TicketPendingUntilReachedSince => $Ticket->{pending_until_reached_since} || '',
            TicketFirstResponseDueClass => $Ticket->{first_response_due_class} || '',
            TicketFirstResponseEscalated => $Ticket->{first_response_escalated} || 0,
            TicketFirstResponseEscalatedSince => $Ticket->{first_response_escalated_since} || '',
            TicketUpdateDueClass => $Ticket->{update_due_class} || '',
            TicketUpdateEscalated => $Ticket->{update_escalated} || 0,
            TicketUpdateEscalatedSince => $Ticket->{update_escalated_since} || '',
            TicketSolutionDueClass => $Ticket->{solution_due_class} || '',
            TicketSolutionEscalated => $Ticket->{solution_escalated} || 0,
            TicketSolutionEscalatedSince => $Ticket->{solution_escalated_since} || '',

            ArticleList              => $Articles,
            ArticleCount             => $ArticleCount,
            ArticleEmptyClass        => $ArticleEmptyClass,
            ArticleFormAction        => 'index.pl',
            AttachmentMaxSizeMB      => $AttachmentMaxSizeMB,
            AttachmentMaxSizeBytes   => $AttachmentMaxSizeBytes,
            ArticleCreateError       => $ArticleCreateError,
            ArticleCreateErrorClass  => $ArticleCreateErrorClass,
            ArticleReplyFormClass    => $ArticleReplyFormClass,
            TicketReplyEmailTemplate => $ReplyEmailTemplate,
            TicketStatusOptionsHTML  => $StatusOptionsHTML,
            TicketPriorityOptionsHTML => $PriorityOptionsHTML,
            TicketQueueOptionsHTML   => $QueueOptionsHTML,
            TicketClosedStateOptionsHTML => $ClosedStateOptionsHTML,
            TicketToolError          => $ToolActionError,
            TicketToolErrorClass     => $TicketToolErrorClass,
            TicketToolActive         => $ToolActionActive,
            TicketToolsOverlayClass  => $TicketToolsOverlayClass,
            TicketToolsOverlayAriaHidden => $TicketToolsOverlayAriaHidden,
            TicketToolsButtonExpanded => $TicketToolsButtonExpanded,
            DefaultArticleMode       => 'note',
            ReplyFormDefaultTitle    => 'Translate:TicketCreateNote',
            ReplySubmitDefaultLabel  => 'Translate:TicketArticleSaveNote',
        },
    };
}


sub _JSONResponse {
    my ( $Self, %Param ) = @_;

    my $Data = $Param{Data} || { items => [] };
    my $Body = encode_json($Data);

    return {
        Response => $Self->{Output}->Response(
            ContentType => 'application/json; charset=UTF-8',
            Body        => $Body,
        ),
    };
}

sub _AgentLookup {
    my ( $Self, %Param ) = @_;

    my $Query = $Self->_Trim( $Param{Query} );

    return { items => [] } if length($Query) < 2;

    my $Like = '%' . $Query . '%';
    my $Rows = $Self->{DB}->SelectAll(
        'SELECT
            id,
            login,
            email,
            firstname,
            lastname
         FROM user_account
         WHERE account_type = ?
            AND is_active = 1
            AND is_system_user = 0
            AND (
                login LIKE ?
                OR email LIKE ?
                OR firstname LIKE ?
                OR lastname LIKE ?
                OR CONCAT(firstname, " ", lastname) LIKE ?
            )
         ORDER BY login ASC
         LIMIT 20',
        'agent',
        $Like,
        $Like,
        $Like,
        $Like,
        $Like,
    ) || [];

    my @Items;

    for my $Row ( @{$Rows} ) {
        my $Name = $Self->_UserName( User => $Row ) || $Row->{login} || '';
        my $Email = $Row->{email} || '';
        my $Login = $Row->{login} || '';
        my $Label = $Name;

        if ( $Login && $Login ne $Name ) {
            $Label .= ' (' . $Login . ')';
        }

        if ($Email) {
            $Label .= ' <' . $Email . '>';
        }

        push @Items, {
            id          => 0 + ( $Row->{id} || 0 ),
            label       => $Label,
            description => $Email || $Login,
        };
    }

    return { items => \@Items };
}

sub _CustomerUserLookup {
    my ( $Self, %Param ) = @_;

    my $Query = $Self->_Trim( $Param{Query} );

    return { items => [] } if length($Query) < 2;

    my $Like = '%' . $Query . '%';
    my $Rows = $Self->{DB}->SelectAll(
        'SELECT
            cu.id,
            cu.customer_id,
            c.customer_number,
            c.name AS customer_name,
            ua.login,
            ua.email,
            ua.firstname,
            ua.lastname
         FROM customer_user cu
         INNER JOIN customer c
            ON c.id = cu.customer_id
         INNER JOIN user_account ua
            ON ua.id = cu.user_account_id
         WHERE cu.active = 1
            AND c.active = 1
            AND ua.is_active = 1
            AND ua.account_type = ?
            AND (
                c.customer_number LIKE ?
                OR c.name LIKE ?
                OR ua.login LIKE ?
                OR ua.email LIKE ?
                OR ua.firstname LIKE ?
                OR ua.lastname LIKE ?
                OR CONCAT(ua.firstname, " ", ua.lastname) LIKE ?
            )
         ORDER BY c.name ASC, ua.login ASC
         LIMIT 20',
        'customer',
        $Like,
        $Like,
        $Like,
        $Like,
        $Like,
        $Like,
        $Like,
    ) || [];

    my @Items;

    for my $Row ( @{$Rows} ) {
        my $Name = $Self->_UserName( User => $Row ) || $Row->{login} || '';
        my $Email = $Row->{email} || '';
        my $CustomerName = $Row->{customer_name} || '';
        my $CustomerNumber = $Row->{customer_number} || '';
        my $Label = $Name;

        if ($Email) {
            $Label .= ' <' . $Email . '>';
        }

        if ($CustomerName) {
            $Label .= ' — ' . $CustomerName;
        }

        push @Items, {
            id          => 0 + ( $Row->{id} || 0 ),
            customer_id => 0 + ( $Row->{customer_id} || 0 ),
            label       => $Label,
            description => join( ' · ', grep {$_} ( $CustomerNumber, $CustomerName, $Email ) ),
        };
    }

    return { items => \@Items };
}


sub _ArticleForwardData {
    my ( $Self, %Param ) = @_;

    my $Article  = $Param{Article} || {};
    my $Language = $Param{Language} || 'en';
    my $Subject  = $Article->{subject} || 'Ticket';

    $Subject =~ s{\r|\n}{ }g;
    $Subject =~ s{\s+}{ }g;
    $Subject =~ s{\A\s+|\s+\z}{}g;
    $Subject = 'Fwd: ' . $Subject if $Subject !~ m{\A\s*Fwd\s*:}i;

    my $BodyTemplate = '<p><br></p>';
    $BodyTemplate .= '<div style="height:14px; line-height:14px; font-size:14px; margin:0; padding:0;">&nbsp;</div>';
    $BodyTemplate .= $Self->_ForwardHistoryArticleHTML(
        Article  => $Article,
        Language => $Language,
    );

    return {
        Subject      => $Subject,
        BodyTemplate => $BodyTemplate,
    };
}

sub _ArticleReplyData {
    my ( $Self, %Param ) = @_;

    my $Ticket             = $Param{Ticket} || {};
    my $Article            = $Param{Article} || {};
    my $QueueReplyTemplate = $Param{QueueReplyTemplate} || '';
    my $Language           = $Param{Language} || 'en';

    my $Allowed = ( ( $Article->{channel} || '' ) eq 'email' && ( $Article->{visibility} || '' ) ne 'agent' ) ? 1 : 0;

    return {
        Allowed      => 0,
        To           => '',
        Cc           => '',
        Subject      => '',
        BodyTemplate => '',
    } if !$Allowed;

    my $To = $Self->_ArticleReplyRecipient(
        Ticket  => $Ticket,
        Article => $Article,
    );

    my $Subject = $Self->_ArticleReplySubject( Article => $Article );
    my $BodyTemplate = $Self->_ArticleReplyBodyTemplate(
        Ticket             => $Ticket,
        Article            => $Article,
        QueueReplyTemplate => $QueueReplyTemplate,
        Language           => $Language,
    );

    return {
        Allowed      => 1,
        To           => $To,
        Cc           => '',
        Subject      => $Subject,
        BodyTemplate => $BodyTemplate,
    };
}

sub _ArticleReplyRecipient {
    my ( $Self, %Param ) = @_;

    my $Ticket  = $Param{Ticket} || {};
    my $Article = $Param{Article} || {};

    if ( ( $Article->{sender_type} || '' ) eq 'customer' && ( $Article->{from_email} || '' ) ) {
        return $Self->_MailAddressBuild(
            Name  => $Article->{from_name} || $Article->{sender_name} || '',
            Email => $Article->{from_email},
        );
    }

    if ( $Ticket->{customer_user_email} ) {
        return $Self->_MailAddressBuild(
            Name  => $Ticket->{customer_user_name} || '',
            Email => $Ticket->{customer_user_email},
        );
    }

    if ( $Article->{from_email} ) {
        return $Self->_MailAddressBuild(
            Name  => $Article->{from_name} || $Article->{sender_name} || '',
            Email => $Article->{from_email},
        );
    }

    return '';
}

sub _MailAddressBuild {
    my ( $Self, %Param ) = @_;

    my $Name  = $Param{Name} || '';
    my $Email = $Param{Email} || '';

    $Name  =~ s{\r|\n}{ }g;
    $Email =~ s{\r|\n}{ }g;
    $Name  =~ s{<|>}{}g;
    $Name  =~ s{"}{}g;
    $Name  =~ s{\bdefault\b}{}gi;
    $Name  =~ s{\A\s+|\s+\z}{}g;
    $Email =~ s{\A\s+|\s+\z}{}g;

    return '' if !$Email;
    return $Email if !$Name || $Name eq '-';

    return $Name . ' <' . $Email . '>';
}

sub _ArticleReplySubject {
    my ( $Self, %Param ) = @_;

    my $Article = $Param{Article} || {};
    my $Subject = $Article->{subject} || '';

    $Subject =~ s{\r|\n}{ }g;
    $Subject =~ s{\s+}{ }g;
    $Subject =~ s{\A\s+|\s+\z}{}g;
    $Subject ||= 'Ticket';

    return $Subject if $Subject =~ m{\A\s*Re\s*:}i;

    return 'Re: ' . $Subject;
}

sub _ArticleReplyBodyTemplate {
    my ( $Self, %Param ) = @_;

    my $Article            = $Param{Article} || {};
    my $QueueReplyTemplate = $Param{QueueReplyTemplate} || '';
    my $Language           = $Param{Language} || 'en';

    my $HTML = $QueueReplyTemplate || '<p><br></p>';
    $HTML =~ s{\A\s+|\s+\z}{}g;
    $HTML .= '<div style="height:14px; line-height:14px; font-size:14px; margin:0; padding:0;">&nbsp;</div>';
    $HTML .= $Self->_ArticleReplyQuoteHTML(
        Article  => $Article,
        Language => $Language,
    );

    return $HTML;
}

sub _ArticleReplyQuoteHTML {
    my ( $Self, %Param ) = @_;

    my $Article  = $Param{Article} || {};
    my $Language = $Param{Language} || 'en';

    my $CreatedAt = $Article->{created_at_display} || $Self->_DateTimeFormat(
        DateTime => $Article->{created_at},
        Language => $Language,
    );

    my $From = $Article->{from_name} || $Article->{sender_name} || $Article->{from_email} || '-';
    if ( $Article->{from_email} && $From !~ m{\Q$Article->{from_email}\E} ) {
        $From .= ' <' . $Article->{from_email} . '>';
    }

    my $Body = $Article->{body_html} || '';
    $Body = $Self->_ForwardMailHTMLNormalize( HTML => $Body );

    my $Header = $Language eq 'de'
        ? 'Am ' . ( $CreatedAt || '-' ) . ' schrieb ' . ( $From || '-' ) . ':'
        : 'On ' . ( $CreatedAt || '-' ) . ', ' . ( $From || '-' ) . ' wrote:';

    my $HTML = '<div style="margin:14px 0 8px 0; padding:0; font-family:Arial, Helvetica, sans-serif; font-size:13px; line-height:1.35; color:#000000;">'
        . $Self->_Escape($Header)
        . '</div>';

    $HTML .= '<blockquote style="border-left:3px solid #4f8df7; margin:0; padding:0 0 0 10px; color:#000000; font-family:Arial, Helvetica, sans-serif; font-size:13px; line-height:1.35;">'
        . $Body
        . '</blockquote>';

    return $HTML;
}

sub _TicketToolForward {
    my ( $Self, %Param ) = @_;

    my $Request      = $Param{Request} || {};
    my $User         = $Param{User} || {};
    my $Language     = $Param{Language} || 'en';
    my $TicketObject = $Param{TicketObject};
    my $TicketID     = $Param{TicketID} || 0;
    my $ForwardToRaw = $Request->{ForwardTo} || '';
    my $ForwardCcRaw = $Request->{ForwardCc} || '';
    my $Body         = $Request->{ForwardBody} || '';

    $Body = $Self->_ForwardMailHTMLNormalize( HTML => $Body );

    if ( !$TicketObject || $TicketID !~ m{\A\d+\z} || !$TicketID ) {
        return {
            Success => 0,
            Error   => 'Translate:TicketToolForwardSendFailed',
        };
    }

    my $ToCheck = $Self->_EmailRecipientsParse( Value => $ForwardToRaw, Required => 1 );
    if ( !$ToCheck->{Valid} ) {
        return {
            Success => 0,
            Error   => $ToCheck->{Error} || 'Translate:TicketToolForwardRecipientRequired',
        };
    }

    my $CcCheck = $Self->_EmailRecipientsParse( Value => $ForwardCcRaw, Required => 0 );
    if ( !$CcCheck->{Valid} ) {
        return {
            Success => 0,
            Error   => $CcCheck->{Error} || 'Translate:TicketToolForwardRecipientInvalid',
        };
    }

    if ( !$Self->_BodyHasVisibleContent( Body => $Body ) ) {
        return {
            Success => 0,
            Error   => 'Translate:TicketArticleBodyRequired',
        };
    }

    my $Ticket = $TicketObject->TicketGet(
        TicketID => $TicketID,
        User     => $User,
        Language => $Language,
    );

    if ( !$Ticket ) {
        return {
            Success => 0,
            Error   => $TicketObject->Error() || 'Translate:TicketToolForwardSendFailed',
        };
    }

    my ( $FromName, $FromEmail ) = $Self->_ReplySender(
        TicketID => $TicketID,
        User     => $User,
    );

    my $Precheck = $Self->_EmailSendPrecheck(
        FromEmail => $FromEmail,
        ToEmail   => $ToCheck->{Header},
    );

    if ( !$Precheck->{Success} ) {
        return {
            Success => 0,
            Error   => $Precheck->{Message} || 'Translate:TicketToolForwardSendFailed',
        };
    }

    my $RawSubject = $Self->_ForwardSubject(
        Ticket   => $Ticket,
        Language => $Language,
    );

    my $MailSubject = $RawSubject;
    if ( $TicketObject->can('TicketSubjectBuild') ) {
        $MailSubject = $TicketObject->TicketSubjectBuild(
            TicketID => $TicketID,
            Subject  => $RawSubject,
        );
    }

    $Self->{DB}->BeginWork() || return {
        Success => 0,
        Error   => 'Translate:TicketToolForwardSendFailed',
    };

    my $ArticleID = $TicketObject->ArticleCreate(
        TicketID        => $TicketID,
        User            => $User,
        Subject         => $RawSubject,
        Body            => $Body,
        Channel         => 'email',
        SenderType      => 'agent',
        FromName        => $FromName,
        FromEmail       => $FromEmail,
        ToName          => '',
        ToEmail         => $ToCheck->{Header},
        Cc              => $CcCheck->{Header},
        ContentType     => 'text/html',
        Visibility      => 'agent',
        Language        => $Language,
        CreatedByUserID => $User->{user_account_id},
        ChangedByUserID => $User->{user_account_id},
        SkipNotification => 1,
    );

    if ( !$ArticleID ) {
        my $Error = $TicketObject->Error() || 'Translate:TicketArticleCreateFailed';
        $Self->{DB}->Rollback();
        return {
            Success => 0,
            Error   => $Error,
        };
    }

    my $SendResult = $Self->_EmailSend(
        FromName  => $FromName,
        FromEmail => $FromEmail,
        ToName    => '',
        ToEmail   => $ToCheck->{Header},
        Cc        => $CcCheck->{Header},
        Subject   => $MailSubject,
        Body      => $Body,
    );

    if ( !$SendResult->{Success} ) {
        $Self->{DB}->Rollback();
        return {
            Success => 0,
            Error   => $SendResult->{Message} || 'Translate:TicketToolForwardSendFailed',
        };
    }

    if ( !$Self->{DB}->Commit() ) {
        $Self->{DB}->Rollback();
        return {
            Success => 0,
            Error   => 'Translate:TicketToolForwardSendFailed',
        };
    }

    return {
        Success => 1,
    };
}

sub _ForwardSubject {
    my ( $Self, %Param ) = @_;

    my $Ticket = $Param{Ticket} || {};
    my $Title  = $Ticket->{title} || $Ticket->{ticket_number} || '';
    $Title =~ s{\r|\n}{ }g;
    $Title =~ s{\s+}{ }g;
    $Title =~ s{\A\s+|\s+\z}{}g;
    $Title ||= 'Ticket';

    return 'Fwd: ' . $Title;
}

sub _ForwardBodyTemplate {
    my ( $Self, %Param ) = @_;

    my $Ticket   = $Param{Ticket} || {};
    my $Articles = ref $Param{Articles} eq 'ARRAY' ? $Param{Articles} : [];
    my $Language = $Param{Language} || 'en';
    my @VisibleArticles;

    for my $Article ( @{$Articles} ) {
        my $Visibility = lc( $Article->{visibility} || '' );
        next if $Visibility eq 'agent';
        push @VisibleArticles, $Article;
    }

    my $HistoryTitle = $Language eq 'de' ? 'Weitergeleiteter Ticketverlauf' : 'Forwarded ticket history';
    my $TicketLabel  = $Language eq 'de' ? 'Ticket' : 'Ticket';
    my $EmptyText    = $Language eq 'de'
        ? 'Es gibt noch keine für Kunden sichtbaren Artikel in diesem Ticket.'
        : 'There are no customer-visible articles in this ticket yet.';

    my $TicketNumber = $Ticket->{ticket_number} || '';
    my $TicketTitle  = $Ticket->{title} || '';

    my $HTML = '<p><br></p>';
    $HTML .= '<div style="margin-top:18px; padding-top:12px; border-top:1px solid #b8c2cc; font-family:Arial, Helvetica, sans-serif; font-size:13px; line-height:1.45; color:#000000;">';
    $HTML .= '<div style="margin:0 0 10px 0; font-weight:bold; color:#333333;">----- ' . $Self->_Escape($HistoryTitle) . ' -----</div>';
    $HTML .= '<div style="margin:0 0 14px 0; color:#333333;"><strong>'
        . $Self->_Escape($TicketLabel)
        . ':</strong> '
        . $Self->_Escape($TicketNumber);

    if ($TicketTitle) {
        $HTML .= ' &ndash; ' . $Self->_Escape($TicketTitle);
    }

    $HTML .= '</div>';

    if (!@VisibleArticles) {
        $HTML .= '<div style="margin:0 0 12px 0; color:#333333;">' . $Self->_Escape($EmptyText) . '</div>';
        $HTML .= '</div>';
        return $HTML;
    }

    for my $Article ( @VisibleArticles ) {
        $HTML .= $Self->_ForwardHistoryArticleHTML(
            Article  => $Article,
            Language => $Language,
        );
    }

    $HTML .= '</div>';

    return $HTML;
}

sub _ForwardHistoryArticleHTML {
    my ( $Self, %Param ) = @_;

    my $Article  = $Param{Article} || {};
    my $Language = $Param{Language} || 'en';

    my %Label = $Language eq 'de'
        ? (
            OriginalData => 'Ursprüngliche Daten',
            Date         => 'Datum',
            From         => 'Von',
            To           => 'An',
            Cc           => 'CC',
            Subject      => 'Betreff',
            Channel      => 'Kanal',
            Attachments  => 'Anhänge',
        )
        : (
            OriginalData => 'Original data',
            Date         => 'Date',
            From         => 'From',
            To           => 'To',
            Cc           => 'CC',
            Subject      => 'Subject',
            Channel      => 'Channel',
            Attachments  => 'Attachments',
        );

    my $CreatedAt = $Article->{created_at_display} || $Self->_DateTimeFormat(
        DateTime => $Article->{created_at},
        Language => $Language,
    );

    my $From = $Article->{from_name} || $Article->{sender_name} || $Article->{from_email} || '-';
    if ( $Article->{from_email} && $From !~ m{\Q$Article->{from_email}\E} ) {
        $From .= ' <' . $Article->{from_email} . '>';
    }

    my $To = $Article->{to_name} || $Article->{to_email} || $Article->{recipient} || '-';
    if ( $Article->{to_email} && $To !~ m{\Q$Article->{to_email}\E} ) {
        $To .= ' <' . $Article->{to_email} . '>';
    }

    my $Body        = $Article->{body_html} || '';
    my $Subject     = $Article->{subject} || '-';
    my $Channel     = $Article->{channel} || '-';
    my $Cc          = $Article->{cc} || '';
    my $Attachments = ref $Article->{attachments} eq 'ARRAY' ? $Article->{attachments} : [];

    my $HTML = '<div style="margin:0 0 22px 0; padding:0; font-family:Arial, Helvetica, sans-serif; font-size:13px; line-height:1.45; color:#000000;">';
    $HTML .= '<div style="background-color:#dddddd; border:1px solid #bdbdbd; padding:8px 10px; margin:0 0 12px 0; color:#000000;">';
    $HTML .= '<div style="font-weight:bold; margin:0 0 6px 0;">-----' . $Self->_Escape( $Label{OriginalData} ) . '-----</div>';
    $HTML .= $Self->_ForwardMetaLineHTML( Label => $Label{Date},    Value => $CreatedAt || '-' );
    $HTML .= $Self->_ForwardMetaLineHTML( Label => $Label{From},    Value => $From );
    $HTML .= $Self->_ForwardMetaLineHTML( Label => $Label{To},      Value => $To );
    $HTML .= $Self->_ForwardMetaLineHTML( Label => $Label{Cc},      Value => $Cc ) if $Cc;
    $HTML .= $Self->_ForwardMetaLineHTML( Label => $Label{Subject}, Value => $Subject );
    $HTML .= $Self->_ForwardMetaLineHTML( Label => $Label{Channel}, Value => $Channel );

    if ( @{$Attachments} ) {
        my @Names = map { $_->{filename} || '' } @{$Attachments};
        @Names = grep {$_} @Names;
        if (@Names) {
            $HTML .= $Self->_ForwardMetaLineHTML(
                Label => $Label{Attachments},
                Value => join( ', ', @Names ),
            );
        }
    }

    $HTML .= '</div>';
    $HTML .= '<div style="border-left:3px solid #4f8df7; margin:0; padding:0 0 0 10px; color:#000000;">';
    $HTML .= $Body;
    $HTML .= '</div>';
    $HTML .= '</div>';

    return $HTML;
}

sub _ForwardMetaLineHTML {
    my ( $Self, %Param ) = @_;

    my $Label = $Param{Label} || '';
    my $Value = $Param{Value} || '-';

    return '<div style="margin:0 0 2px 0;"><strong>'
        . $Self->_Escape($Label)
        . ':</strong> '
        . $Self->_Escape($Value)
        . '</div>';
}

sub _ForwardMailHTMLNormalize {
    my ( $Self, %Param ) = @_;

    my $HTML = $Param{HTML} || '';

    return '' if !$HTML;

    # CKEditor erzeugt bei Enter normalerweise <p>...</p>. Viele Mailprogramme
    # rendern <p> mit eigenen Standard-Abständen. Deshalb werden die Absätze vor
    # dem Versand mit Inline-Styles versehen, damit einfache Zeilen auch beim
    # Empfänger einfache Zeilen bleiben.
    $HTML =~ s{<p\b([^>]*)>}{ $Self->_ForwardOpeningTagNormalize( Tag => 'p', Attributes => $1 ) }egis;

    # Leere CKEditor-Absätze sollen als echte, kontrollierte Leerzeile erhalten
    # bleiben, aber nicht mit Mailclient-Default-Margins größer werden.
    $HTML =~ s{<p\s+style="margin:0; padding:0; line-height:1\.35;"\s*>\s*(?:<br\s*/?>|&nbsp;|\s)*</p>}{<div style="height:12px; line-height:12px; font-size:12px; margin:0; padding:0;">&nbsp;</div>}gis;

    return $HTML;
}

sub _ForwardOpeningTagNormalize {
    my ( $Self, %Param ) = @_;

    my $Tag        = $Param{Tag} || 'p';
    my $Attributes = defined $Param{Attributes} ? $Param{Attributes} : '';
    my $InlineCSS  = 'margin:0; padding:0; line-height:1.35;';

    if ( $Attributes =~ m{\bstyle\s*=\s*(['"])(.*?)\1}is ) {
        my $Quote = $1;
        my $Style = $2 || '';
        $Style =~ s{\A\s+|\s+\z}{}g;
        $Style = $InlineCSS . ( $Style ? ' ' . $Style : '' );
        $Attributes =~ s{\bstyle\s*=\s*(['"])(.*?)\1}{style=$Quote$Style$Quote}is;
        return '<' . $Tag . $Attributes . '>';
    }

    return '<' . $Tag . $Attributes . ' style="' . $InlineCSS . '">';
}

sub _EmailRecipientsParse {
    my ( $Self, %Param ) = @_;

    my $Value    = $Param{Value} || '';
    my $Required = $Param{Required} ? 1 : 0;

    $Value =~ s{\r|\n}{ }g;
    $Value =~ s{\A\s+|\s+\z}{}g;

    if ( !$Value ) {
        return $Required
            ? { Valid => 0, Error => 'Translate:TicketToolForwardRecipientRequired' }
            : { Valid => 1, Header => '', Emails => [] };
    }

    my @Parts = grep { length } map {
        my $Part = $_;
        $Part =~ s{\A\s+|\s+\z}{}g;
        $Part;
    } split m{[;,]}, $Value;

    @Parts = ($Value) if !@Parts;

    my @Emails;
    my %Seen;

    for my $Part (@Parts) {
        my $Email = $Part;

        if ( $Email =~ m{<([^>]+)>} ) {
            $Email = $1;
        }

        $Email =~ s{\A\s+|\s+\z}{}g;

        if ( $Email !~ m{\A[A-Z0-9._%+\-]+\@[A-Z0-9.\-]+\.[A-Z]{2,}\z}i ) {
            return {
                Valid => 0,
                Error => 'Translate:TicketToolForwardRecipientInvalid',
            };
        }

        my $Key = lc $Email;
        next if $Seen{$Key}++;
        push @Emails, $Email;
    }

    if ( $Required && !@Emails ) {
        return {
            Valid => 0,
            Error => 'Translate:TicketToolForwardRecipientRequired',
        };
    }

    return {
        Valid  => 1,
        Header => join( ', ', @Emails ),
        Emails => \@Emails,
    };
}

sub _TicketToolUpdate {
    my ( $Self, %Param ) = @_;

    my $Request      = $Param{Request} || {};
    my $User         = $Param{User} || {};
    my $Language     = $Param{Language} || 'en';
    my $TicketObject = $Param{TicketObject};
    my $TicketID     = $Param{TicketID} || 0;
    my $Action       = $Self->_Trim( $Request->{ToolAction} );
    my $Body         = $Request->{ToolArticleBody} || '';

    my %Allowed = map { $_ => 1 } qw(priority owner responsible customer queue close);

    if ( !$Allowed{$Action} ) {
        return {
            Success    => 0,
            ActiveTool => 'priority',
            Error      => 'Translate:TicketToolInvalidAction',
        };
    }

    if ( !$TicketObject || $TicketID !~ m{\A\d+\z} || !$TicketID ) {
        return {
            Success    => 0,
            ActiveTool => $Action,
            Error      => 'Translate:TicketToolUpdateFailed',
        };
    }

    if ( !$Self->_BodyHasVisibleContent( Body => $Body ) ) {
        return {
            Success    => 0,
            ActiveTool => $Action,
            Error      => 'Translate:TicketToolArticleBodyRequired',
        };
    }

    my $TicketBefore = $TicketObject->TicketGet(
        TicketID => $TicketID,
        User     => $User,
        Language => $Language,
    );

    if ( !$TicketBefore ) {
        return {
            Success    => 0,
            ActiveTool => $Action,
            Error      => $TicketObject->Error() || 'Translate:TicketToolUpdateFailed',
        };
    }

    my $Summary = '';
    my $UpdateOK;

    if ( $Action eq 'priority' ) {
        my $PriorityID = $Request->{PriorityID} || 0;
        my $Priority = $Self->_PriorityGet( PriorityID => $PriorityID );

        if (!$Priority) {
            return {
                Success    => 0,
                ActiveTool => $Action,
                Error      => 'Translate:TicketToolSelectionRequired',
            };
        }

        if ( ( $TicketBefore->{priority_id} || 0 ) == ( $Priority->{id} || 0 ) ) {
            return {
                Success    => 0,
                ActiveTool => $Action,
                Error      => 'Translate:TicketToolNoChange',
            };
        }

        $Summary = $Self->_ToolSummary(
            Language => $Language,
            Action   => $Action,
            OldValue => $Self->_PriorityDisplayName(
                Name     => $TicketBefore->{priority_name},
                Language => $Language,
            ) || '-',
            NewValue => $Self->_PriorityDisplayName(
                Name     => $Priority->{name},
                Language => $Language,
            ) || '-',
        );

        $Self->{DB}->BeginWork() || return {
            Success    => 0,
            ActiveTool => $Action,
            Error      => 'Translate:TicketToolUpdateFailed',
        };

        $UpdateOK = $TicketObject->TicketPriorityUpdate(
            TicketID        => $TicketID,
            PriorityID      => $Priority->{id},
            User            => $User,
            ChangedByUserID => $User->{user_account_id},
        );
    }
    elsif ( $Action eq 'owner' ) {
        my $OwnerUserID = $Request->{OwnerUserID} || 0;
        my $Agent = $Self->_AgentGet( UserID => $OwnerUserID );

        if (!$Agent) {
            return {
                Success    => 0,
                ActiveTool => $Action,
                Error      => 'Translate:TicketToolSelectionRequired',
            };
        }

        if ( ( $TicketBefore->{owner_user_id} || 0 ) == ( $Agent->{id} || 0 ) ) {
            return {
                Success    => 0,
                ActiveTool => $Action,
                Error      => 'Translate:TicketToolNoChange',
            };
        }

        $Summary = $Self->_ToolSummary(
            Language => $Language,
            Action   => $Action,
            OldValue => $TicketBefore->{owner_name} || '-',
            NewValue => $Self->_UserName( User => $Agent ) || $Agent->{login} || '-',
        );

        $Self->{DB}->BeginWork() || return {
            Success    => 0,
            ActiveTool => $Action,
            Error      => 'Translate:TicketToolUpdateFailed',
        };

        $UpdateOK = $TicketObject->TicketOwnerUpdate(
            TicketID        => $TicketID,
            OwnerUserID     => $Agent->{id},
            User            => $User,
            ChangedByUserID => $User->{user_account_id},
        );
    }
    elsif ( $Action eq 'responsible' ) {
        my $ResponsibleUserID = $Request->{ResponsibleUserID} || 0;
        my $Agent = $Self->_AgentGet( UserID => $ResponsibleUserID );

        if (!$Agent) {
            return {
                Success    => 0,
                ActiveTool => $Action,
                Error      => 'Translate:TicketToolSelectionRequired',
            };
        }

        if ( ( $TicketBefore->{responsible_user_id} || 0 ) == ( $Agent->{id} || 0 ) ) {
            return {
                Success    => 0,
                ActiveTool => $Action,
                Error      => 'Translate:TicketToolNoChange',
            };
        }

        $Summary = $Self->_ToolSummary(
            Language => $Language,
            Action   => $Action,
            OldValue => $TicketBefore->{responsible_name} || '-',
            NewValue => $Self->_UserName( User => $Agent ) || $Agent->{login} || '-',
        );

        $Self->{DB}->BeginWork() || return {
            Success    => 0,
            ActiveTool => $Action,
            Error      => 'Translate:TicketToolUpdateFailed',
        };

        $UpdateOK = $TicketObject->TicketResponsibleUpdate(
            TicketID         => $TicketID,
            ResponsibleUserID => $Agent->{id},
            User             => $User,
            ChangedByUserID  => $User->{user_account_id},
        );
    }
    elsif ( $Action eq 'customer' ) {
        my $CustomerUserID = $Request->{CustomerUserID} || 0;
        my $CustomerUser = $Self->_CustomerUserGet( CustomerUserID => $CustomerUserID );

        if (!$CustomerUser) {
            return {
                Success    => 0,
                ActiveTool => $Action,
                Error      => 'Translate:TicketToolSelectionRequired',
            };
        }

        if ( ( $TicketBefore->{customer_user_id} || 0 ) == ( $CustomerUser->{id} || 0 ) ) {
            return {
                Success    => 0,
                ActiveTool => $Action,
                Error      => 'Translate:TicketToolNoChange',
            };
        }

        my $OldValue = join( ' / ', grep {$_ && $_ ne '-'} ( $TicketBefore->{customer_name} || '-', $TicketBefore->{customer_user_name} || '-' ) ) || '-';
        my $NewValue = join( ' / ', grep {$_} ( $CustomerUser->{customer_name} || '', $Self->_UserName( User => $CustomerUser ) || $CustomerUser->{login} || '' ) ) || '-';

        $Summary = $Self->_ToolSummary(
            Language => $Language,
            Action   => $Action,
            OldValue => $OldValue,
            NewValue => $NewValue,
        );

        $Self->{DB}->BeginWork() || return {
            Success    => 0,
            ActiveTool => $Action,
            Error      => 'Translate:TicketToolUpdateFailed',
        };

        $UpdateOK = $TicketObject->TicketCustomerUserUpdate(
            TicketID        => $TicketID,
            CustomerUserID  => $CustomerUser->{id},
            User            => $User,
            ChangedByUserID => $User->{user_account_id},
        );
    }
    elsif ( $Action eq 'queue' ) {
        my $QueueID = $Request->{QueueID} || 0;
        my $Queue = $Self->_QueueGet( QueueID => $QueueID );

        if (!$Queue) {
            return {
                Success    => 0,
                ActiveTool => $Action,
                Error      => 'Translate:TicketToolSelectionRequired',
            };
        }

        if ( ( $TicketBefore->{queue_id} || 0 ) == ( $Queue->{id} || 0 ) ) {
            return {
                Success    => 0,
                ActiveTool => $Action,
                Error      => 'Translate:TicketToolNoChange',
            };
        }

        $Summary = $Self->_ToolSummary(
            Language => $Language,
            Action   => $Action,
            OldValue => $TicketBefore->{queue_full_name} || $TicketBefore->{queue_name} || '-',
            NewValue => $Queue->{full_name} || $Queue->{name} || '-',
        );

        $Self->{DB}->BeginWork() || return {
            Success    => 0,
            ActiveTool => $Action,
            Error      => 'Translate:TicketToolUpdateFailed',
        };

        $UpdateOK = $TicketObject->TicketQueueUpdate(
            TicketID        => $TicketID,
            QueueID         => $Queue->{id},
            User            => $User,
            ChangedByUserID => $User->{user_account_id},
        );
    }
    elsif ( $Action eq 'close' ) {
        my $ClosedStateID = $Request->{ClosedStateID} || 0;
        my $ClosedState = $Self->_ClosedStateGet( StateID => $ClosedStateID );

        if (!$ClosedState) {
            return {
                Success    => 0,
                ActiveTool => $Action,
                Error      => 'Translate:TicketToolSelectionRequired',
            };
        }

        if ( ( $TicketBefore->{state_id} || 0 ) == ( $ClosedState->{id} || 0 ) ) {
            return {
                Success    => 0,
                ActiveTool => $Action,
                Error      => 'Translate:TicketToolNoChange',
            };
        }

        $Summary = $Self->_ToolSummary(
            Language => $Language,
            Action   => $Action,
            OldValue => $TicketBefore->{state_name_display}
                || $Self->_TicketStateText( State => $TicketBefore->{state_name}, Language => $Language )
                || '-',
            NewValue => $Self->_TicketStateText( State => $ClosedState->{name}, Language => $Language ) || $ClosedState->{name} || '-',
        );

        $Self->{DB}->BeginWork() || return {
            Success    => 0,
            ActiveTool => $Action,
            Error      => 'Translate:TicketToolUpdateFailed',
        };

        $UpdateOK = $TicketObject->TicketCloseUpdate(
            TicketID        => $TicketID,
            StateID         => $ClosedState->{id},
            User            => $User,
            ChangedByUserID => $User->{user_account_id},
        );
    }

    if (!$UpdateOK) {
        my $Error = $TicketObject->Error() || 'Translate:TicketToolUpdateFailed';
        $Self->{DB}->Rollback();
        return {
            Success    => 0,
            ActiveTool => $Action,
            Error      => $Error,
        };
    }

    my $ArticleID = $TicketObject->ArticleCreate(
        TicketID        => $TicketID,
        User            => $User,
        Subject         => $Self->_ToolArticleSubject( Language => $Language, Action => $Action ),
        Body            => $Self->_ToolArticleBody( Summary => $Summary, Body => $Body ),
        Channel         => 'note',
        SenderType      => 'agent',
        FromName        => $Self->_UserName( User => $User ),
        FromEmail       => $User->{email} || '',
        ToName          => '',
        ToEmail         => '',
        ContentType     => 'text/html',
        Visibility      => 'agent',
        Language        => $Language,
        CreatedByUserID => $User->{user_account_id},
        ChangedByUserID => $User->{user_account_id},
        SkipNotification => 1,
    );

    if (!$ArticleID) {
        my $Error = $TicketObject->Error() || 'Translate:TicketArticleCreateFailed';
        $Self->{DB}->Rollback();
        return {
            Success    => 0,
            ActiveTool => $Action,
            Error      => $Error,
        };
    }

    if ( !$Self->{DB}->Commit() ) {
        $Self->{DB}->Rollback();
        return {
            Success    => 0,
            ActiveTool => $Action,
            Error      => 'Translate:TicketToolUpdateFailed',
        };
    }

    return {
        Success    => 1,
        ActiveTool => $Action,
    };
}

sub _PriorityGet {
    my ( $Self, %Param ) = @_;

    my $PriorityID = $Param{PriorityID} || 0;
    return if $PriorityID !~ m{\A\d+\z} || !$PriorityID;

    return $Self->{DB}->SelectRow(
        'SELECT id, name, priority_value
         FROM ticket_priority
         WHERE id = ?
            AND active = 1
         LIMIT 1',
        $PriorityID,
    );
}

sub _AgentGet {
    my ( $Self, %Param ) = @_;

    my $UserID = $Param{UserID} || 0;
    return if $UserID !~ m{\A\d+\z} || !$UserID;

    return $Self->{DB}->SelectRow(
        'SELECT id, login, email, firstname, lastname
         FROM user_account
         WHERE id = ?
            AND account_type = ?
            AND is_active = 1
            AND is_system_user = 0
         LIMIT 1',
        $UserID,
        'agent',
    );
}

sub _CustomerUserGet {
    my ( $Self, %Param ) = @_;

    my $CustomerUserID = $Param{CustomerUserID} || 0;
    return if $CustomerUserID !~ m{\A\d+\z} || !$CustomerUserID;

    return $Self->{DB}->SelectRow(
        'SELECT
            cu.id,
            cu.customer_id,
            c.customer_number,
            c.name AS customer_name,
            ua.login,
            ua.email,
            ua.firstname,
            ua.lastname
         FROM customer_user cu
         INNER JOIN customer c
            ON c.id = cu.customer_id
         INNER JOIN user_account ua
            ON ua.id = cu.user_account_id
         WHERE cu.id = ?
            AND cu.active = 1
            AND c.active = 1
            AND ua.is_active = 1
            AND ua.account_type = ?
         LIMIT 1',
        $CustomerUserID,
        'customer',
    );
}

sub _QueueGet {
    my ( $Self, %Param ) = @_;

    my $QueueID = $Param{QueueID} || 0;
    return if $QueueID !~ m{\A\d+\z} || !$QueueID;

    return $Self->{DB}->SelectRow(
        'SELECT id, name, full_name
         FROM ticket_queue
         WHERE id = ?
            AND active = 1
         LIMIT 1',
        $QueueID,
    );
}

sub _ClosedStateGet {
    my ( $Self, %Param ) = @_;

    my $StateID = $Param{StateID} || 0;
    return if $StateID !~ m{\A\d+\z} || !$StateID;

    return $Self->{DB}->SelectRow(
        'SELECT id, name, state_type
         FROM ticket_state
         WHERE id = ?
            AND active = 1
            AND state_type = ?
         LIMIT 1',
        $StateID,
        'closed',
    );
}

sub _ClosedStateOptionsHTML {
    my ( $Self, %Param ) = @_;

    my $Language       = $Param{Language} || 'en';
    my $CurrentStateID = $Param{CurrentStateID} || 0;
    my $States = $Self->{DB}->SelectAll(
        'SELECT id, name, state_type
         FROM ticket_state
         WHERE active = 1
            AND state_type = ?
         ORDER BY sort_order ASC, id ASC',
        'closed',
    ) || [];

    my $SelectedID = 0;

    for my $State ( @{$States} ) {
        if ( $CurrentStateID && ( $State->{id} || 0 ) == $CurrentStateID ) {
            $SelectedID = $State->{id};
            last;
        }
    }

    $SelectedID = $States->[0]->{id} if !$SelectedID && @{$States};

    my $HTML = '';

    for my $State ( @{$States} ) {
        my $Selected = $SelectedID && ( $State->{id} || 0 ) == $SelectedID ? ' selected' : '';
        my $Label = $Self->_TicketStateText(
            State    => $State->{name},
            Language => $Language,
        );

        $HTML .= '<option value="' . $Self->_Escape( $State->{id} ) . '"' . $Selected . '>'
            . $Self->_Escape( $Label || $State->{name} || '' )
            . '</option>';
    }

    return $HTML;
}

sub _PriorityOptionsHTML {
    my ( $Self, %Param ) = @_;

    my $CurrentPriorityID = $Param{CurrentPriorityID} || 0;
    my $Language          = $Param{Language} || 'en';
    my $Rows = $Self->{DB}->SelectAll(
        'SELECT id, name, priority_value
         FROM ticket_priority
         WHERE active = 1
         ORDER BY sort_order ASC, priority_value ASC, id ASC'
    ) || [];

    my $HTML = '';

    for my $Row ( @{$Rows} ) {
        my $Selected = $CurrentPriorityID && ( $Row->{id} || 0 ) == $CurrentPriorityID ? ' selected' : '';
        my $Label = $Self->_PriorityDisplayName(
            Name     => $Row->{name},
            Language => $Language,
        );
        $HTML .= '<option value="' . $Self->_Escape( $Row->{id} ) . '"' . $Selected . '>'
            . $Self->_Escape($Label)
            . '</option>';
    }

    return $HTML;
}

sub _PriorityDisplayName {
    my ( $Self, %Param ) = @_;

    my $Name     = $Param{Name} || '';
    my $Language = $Param{Language} || 'en';
    my $Key      = lc $Name;

    $Key =~ s{\A\s+}{};
    $Key =~ s{\s+\z}{};
    $Key =~ s{[^a-z0-9]+}{_}g;
    $Key =~ s{\A_+}{};
    $Key =~ s{_+\z}{};

    my %Supported = map { $_ => 1 } qw(
        1_very_low
        2_low
        3_normal
        4_high
        5_very_high
    );

    return $Name if !$Supported{$Key};

    return $Self->{Output}->Translate(
        Key      => 'TicketPriorityName_' . $Key,
        Language => $Language,
    );
}

sub _QueueOptionsHTML {
    my ( $Self, %Param ) = @_;

    my $CurrentQueueID = $Param{CurrentQueueID} || 0;
    my $Rows = $Self->{DB}->SelectAll(
        'SELECT id, name, full_name
         FROM ticket_queue
         WHERE active = 1
         ORDER BY sort_order ASC, full_name ASC, id ASC'
    ) || [];

    my $HTML = '';

    for my $Row ( @{$Rows} ) {
        my $Selected = $CurrentQueueID && ( $Row->{id} || 0 ) == $CurrentQueueID ? ' selected' : '';
        my $Label = $Row->{full_name} || $Row->{name} || '';
        $HTML .= '<option value="' . $Self->_Escape( $Row->{id} ) . '"' . $Selected . '>'
            . $Self->_Escape($Label)
            . '</option>';
    }

    return $HTML;
}

sub _ToolSummary {
    my ( $Self, %Param ) = @_;

    my $Language = $Param{Language} || 'en';
    my $Action   = $Param{Action} || '';
    my $OldValue = $Param{OldValue} || '-';
    my $NewValue = $Param{NewValue} || '-';

    my %DE = (
        priority => 'Priorität geändert',
        owner       => 'Besitzer geändert',
        responsible => 'Verantwortlicher geändert',
        customer    => 'Kunde / Ansprechpartner geändert',
        queue       => 'Queue geändert',
        close       => 'Ticket geschlossen',
    );

    my %EN = (
        priority => 'Priority changed',
        owner       => 'Owner changed',
        responsible => 'Responsible changed',
        customer    => 'Customer / contact changed',
        queue       => 'Queue changed',
        close       => 'Ticket closed',
    );

    my $Label = $Language eq 'de' ? ( $DE{$Action} || 'Ticket-Aktion' ) : ( $EN{$Action} || 'Ticket action' );
    my $From  = $Language eq 'de' ? 'von' : 'from';
    my $To    = $Language eq 'de' ? 'auf' : 'to';

    return $Label . ': ' . $From . ' "' . $OldValue . '" ' . $To . ' "' . $NewValue . '"';
}

sub _ToolArticleSubject {
    my ( $Self, %Param ) = @_;

    my $Language = $Param{Language} || 'en';
    my $Action   = $Param{Action} || '';

    my %DE = (
        priority => 'Ticket-Aktion: Priorität geändert',
        owner       => 'Ticket-Aktion: Besitzer geändert',
        responsible => 'Ticket-Aktion: Verantwortlicher geändert',
        customer    => 'Ticket-Aktion: Kunde / Ansprechpartner geändert',
        queue       => 'Ticket-Aktion: Queue geändert',
        close       => 'Ticket-Aktion: Ticket geschlossen',
    );

    my %EN = (
        priority => 'Ticket action: priority changed',
        owner       => 'Ticket action: owner changed',
        responsible => 'Ticket action: responsible changed',
        customer    => 'Ticket action: customer / contact changed',
        queue       => 'Ticket action: queue changed',
        close       => 'Ticket action: ticket closed',
    );

    return $Language eq 'de' ? ( $DE{$Action} || 'Ticket-Aktion' ) : ( $EN{$Action} || 'Ticket action' );
}

sub _ToolArticleBody {
    my ( $Self, %Param ) = @_;

    my $Summary = $Param{Summary} || '';
    my $Body    = $Param{Body} || '';

    return '<p><strong>' . $Self->_Escape($Summary) . '</strong></p>' . $Body;
}

sub _Trim {
    my ( $Self, $Value ) = @_;

    $Value = '' if !defined $Value;
    $Value =~ s{\A\s+}{};
    $Value =~ s{\s+\z}{};

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

sub _UserName {
    my ( $Self, %Param ) = @_;

    my $User      = $Param{User} || {};
    my $Firstname = $User->{firstname} || '';
    my $Lastname  = $User->{lastname}  || '';
    my $Login     = $User->{login}     || '';
    my $Name      = join ' ', grep {$_} ( $Firstname, $Lastname );

    if ( !$Name ) {
        $Name = $Login;
    }

    return $Name;
}

sub _ReplyRecipient {
    my ( $Self, %Param ) = @_;

    my $TicketObject = $Param{TicketObject};
    my $TicketID     = $Param{TicketID} || 0;
    my $User         = $Param{User} || {};

    return ( '', '' ) if !$TicketObject || !$TicketID;

    my $Ticket = $TicketObject->TicketGet(
        TicketID => $TicketID,
        User     => $User,
    );

    if ($Ticket) {
        my $Name  = $Ticket->{customer_user_name}  || '';
        my $Email = $Ticket->{customer_user_email} || '';

        return ( $Name, $Email ) if $Email;
    }

    my $Articles = $TicketObject->ArticleList( TicketID => $TicketID, User => $User, Language => $Param{Language} || 'en' );

    for ( my $Index = @{$Articles} - 1; $Index >= 0; $Index-- ) {
        my $Article = $Articles->[$Index];

        next if ( $Article->{channel} || '' ) ne 'email';
        next if ( $Article->{sender_type} || '' ) ne 'customer';
        next if !$Article->{from_email};

        return (
            $Article->{from_name} || $Article->{sender_name} || '',
            $Article->{from_email},
        );
    }

    for ( my $Index = @{$Articles} - 1; $Index >= 0; $Index-- ) {
        my $Article = $Articles->[$Index];

        next if !$Article->{from_email};

        return (
            $Article->{from_name} || $Article->{sender_name} || '',
            $Article->{from_email},
        );
    }

    return ( '', '' );
}


sub _QueueAddress {
    my ( $Self, %Param ) = @_;

    my $TicketID = $Param{TicketID} || 0;

    return ( '', '' ) if !$Self->{DB} || !$TicketID;

    my $Row = $Self->{DB}->SelectRow(
        'SELECT
            se.name,
            se.email
         FROM ticket t
         INNER JOIN ticket_queue q
            ON q.id = t.queue_id
         LEFT JOIN system_email se
            ON se.id = q.system_email_id
           AND se.active = 1
         WHERE t.id = ?
         LIMIT 1',
        $TicketID,
    );

    return ( '', '' ) if !$Row;

    return (
        $Row->{name}  || '',
        $Row->{email} || '',
    );
}

sub _ReplySender {
    my ( $Self, %Param ) = @_;

    my $TicketID = $Param{TicketID} || 0;
    my $User     = $Param{User} || {};

    my $UserName  = $Self->_UserName( User => $User );
    my $UserEmail = $User->{email} || '';

    return ( $UserName, $UserEmail ) if !$Self->{DB} || !$TicketID;

    my $Sender = $Self->{DB}->SelectRow(
        'SELECT
            se.name,
            se.email
         FROM ticket t
         INNER JOIN ticket_queue q
            ON q.id = t.queue_id
         LEFT JOIN system_email se
            ON se.id = q.system_email_id
         WHERE t.id = ?
         LIMIT 1',
        $TicketID,
    );

    return (
        $Sender->{name}  || $UserName,
        $Sender->{email} || $UserEmail,
    ) if $Sender;

    return ( $UserName, $UserEmail );
}

sub _DefaultReplySubject {
    my ( $Self, %Param ) = @_;

    my $TicketObject = $Param{TicketObject};
    my $TicketID     = $Param{TicketID} || 0;
    my $User         = $Param{User} || {};
    my $Language     = $Param{Language} || 'en';

    my $Ticket = $TicketObject
        ? $TicketObject->TicketGet( TicketID => $TicketID, User => $User )
        : undef;

    my $TicketNumber = $Ticket ? ( $Ticket->{ticket_number} || $TicketID ) : $TicketID;

    return $Language eq 'de'
        ? 'Antwort zu ' . $TicketNumber
        : 'Reply to ' . $TicketNumber;
}

sub _BodyHasVisibleContent {
    my ( $Self, %Param ) = @_;

    my $Body = $Param{Body} || '';

    $Body =~ s{<style\b[^>]*>.*?</style>}{}gis;
    $Body =~ s{<script\b[^>]*>.*?</script>}{}gis;
    $Body =~ s{<[^>]+>}{}g;
    $Body =~ s{&nbsp;}{ }gi;
    $Body =~ s{&#160;}{ }g;
    $Body =~ s{\s+}{ }g;
    $Body =~ s{\A\s+}{};
    $Body =~ s{\s+\z}{};

    return $Body ? 1 : 0;
}

sub _EmailSendPrecheck {
    my ( $Self, %Param ) = @_;

    eval {
        require QisutuHTML;
        require QisutuMail;
        1;
    } || return {
        Success => 0,
        Message => 'Translate:TicketArticleSendFailed',
    };

    my $Recipients = $Self->_EmailRecipientsParse(
        Value    => $Param{ToEmail} || '',
        Required => 1,
    );

    if ( !$Recipients->{Valid} ) {
        return {
            Success => 0,
            Message => $Recipients->{Error} || 'Translate:TicketArticleRecipientRequired',
        };
    }

    if ( !$Param{FromEmail} ) {
        return {
            Success => 0,
            Message => 'Translate:TicketArticleSenderRequired',
        };
    }

    if ( !$Self->_ActiveSMTPAccount() ) {
        return {
            Success => 0,
            Message => 'Translate:TicketArticleSMTPRequired',
        };
    }

    return {
        Success => 1,
        Message => '',
    };
}

sub _EmailSend {
    my ( $Self, %Param ) = @_;

    eval {
        require QisutuHTML;
        require QisutuMail;
        1;
    } || return {
        Success => 0,
        Message => 'Mail modules could not be loaded',
    };

    my $Recipients = $Self->_EmailRecipientsParse(
        Value    => $Param{ToEmail} || '',
        Required => 1,
    );

    if ( !$Recipients->{Valid} ) {
        return {
            Success => 0,
            Message => $Recipients->{Error} || 'Recipient e-mail address is required',
        };
    }

    my $CcRecipients = $Self->_EmailRecipientsParse(
        Value    => $Param{Cc} || '',
        Required => 0,
    );

    if ( !$CcRecipients->{Valid} ) {
        return {
            Success => 0,
            Message => $CcRecipients->{Error} || 'Invalid CC recipient e-mail address',
        };
    }

    if ( !$Param{FromEmail} ) {
        return {
            Success => 0,
            Message => 'Sender e-mail address is required',
        };
    }

    my $SMTPAccount = $Self->_ActiveSMTPAccount();

    if ( !$SMTPAccount ) {
        return {
            Success => 0,
            Message => 'No active SMTP transport configured',
        };
    }

    my $Body = QisutuHTML->Sanitize( $Param{Body} || '' );

    return QisutuMail->new( Config => $Self->{Config}, DB => $Self->{DB} )->SMTPSend(
        Account   => $SMTPAccount,
        FromName  => $Param{FromName},
        FromEmail => $Param{FromEmail},
        ToName    => $Param{ToName},
        ToEmail   => $Recipients->{Header},
        Cc        => $CcRecipients->{Header},
        Subject   => $Param{Subject},
        Body        => $Body,
        Attachments => $Param{Attachments},
    );
}

sub _UploadedAttachments {
    my ( $Self, %Param ) = @_;

    my $Request      = $Param{Request} || {};
    my $MaxSizeBytes = $Param{MaxSizeBytes} || $Self->_AttachmentMaxSizeMB() * 1024 * 1024;
    my $Uploads      = $Request->{__Uploads} || {};
    my $RawList      = [];

    if ( ref $Uploads->{ArticleAttachment} eq 'ARRAY' ) {
        $RawList = $Uploads->{ArticleAttachment};
    }
    elsif ( ref $Uploads->{'ArticleAttachment[]'} eq 'ARRAY' ) {
        $RawList = $Uploads->{'ArticleAttachment[]'};
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

        my $ContentSize = $Upload->{ContentSize};
        $ContentSize = length($Content) if !defined $ContentSize || $ContentSize !~ m{\A\d+\z};

        my $Attachment = {
            Filename           => $Filename,
            ContentType        => $Upload->{ContentType} || 'application/octet-stream',
            Content            => $Content,
            ContentSize        => $ContentSize,
            ContentDisposition => 'attachment',
        };

        if ( $MaxSizeBytes && $ContentSize > $MaxSizeBytes ) {
            push @Oversized, $Attachment;
            next;
        }

        push @Attachments, $Attachment;
    }

    return {
        Attachments => \@Attachments,
        Oversized   => \@Oversized,
    };
}

sub _AttachmentMaxSizeMB {
    my ($Self) = @_;

    my $Value = 25;

    if ( $Self->{DB} ) {
        my $Loaded = eval {
            require QisutuSystemSetting;
            1;
        };

        if ($Loaded) {
            my $SettingObject = QisutuSystemSetting->new(
                Config => $Self->{Config},
                DB     => $Self->{DB},
            );
            $Value = $SettingObject->AttachmentMaxSizeMB();
        }
    }

    return $Value;
}

sub _AttachmentTooLargeMessage {
    my ( $Self, %Param ) = @_;

    my $Attachment = $Param{Attachment} || {};
    my $MaxSizeMB  = $Param{MaxSizeMB} || 25;
    my $Language   = $Param{Language} || 'en';
    my $Filename   = $Attachment->{Filename} || 'attachment';
    my $Template   = '';

    if ( $Self->{Output} ) {
        $Template = $Self->{Output}->Translate(
            Key      => 'TicketArticleAttachmentTooLargeServer',
            Language => $Language,
        ) || '';
    }

    $Template ||= $Language eq 'de'
        ? 'Der Anhang „{{Filename}}“ überschreitet die erlaubte Maximalgröße von {{MaxSize}}. Bitte wenden Sie sich an den Administrator.'
        : 'The attachment “{{Filename}}” exceeds the permitted maximum size of {{MaxSize}}. Please contact the administrator.';

    my $MaxSizeLabel = $MaxSizeMB . ' MB';
    $Template =~ s{\{\{Filename\}\}}{$Filename}g;
    $Template =~ s{\{\{MaxSize\}\}}{$MaxSizeLabel}g;

    return $Template;
}


sub _QueueReplyTemplate {
    my ( $Self, %Param ) = @_;

    my $TicketID = $Param{TicketID} || 0;

    return '' if !$Self->{DB} || !$TicketID;

    eval {
        require QisutuHTML;
        1;
    } || return '';

    my $Row = $Self->{DB}->SelectRow(
        'SELECT
            sal.content AS salutation_content,
            sig.content AS signature_content
         FROM ticket t
         INNER JOIN ticket_queue q
            ON q.id = t.queue_id
         LEFT JOIN salutation sal
            ON sal.id = q.salutation_id
           AND sal.active = 1
         LEFT JOIN signature sig
            ON sig.id = q.signature_id
           AND sig.active = 1
         WHERE t.id = ?
         LIMIT 1',
        $TicketID,
    );

    return '' if !$Row;

    my $Salutation = QisutuHTML->Sanitize( $Row->{salutation_content} || '' );
    my $Signature  = QisutuHTML->Sanitize( $Row->{signature_content}  || '' );
    my @Parts;

    push @Parts, $Salutation if $Salutation;
    push @Parts, '<p><br></p><p><br></p>';
    push @Parts, $Self->_SystemSignatureWrap( Signature => $Signature ) if $Signature;

    return join "\n", @Parts;
}

sub _SystemSignatureWrap {
    my ( $Self, %Param ) = @_;

    my $Signature = $Param{Signature} || '';
    $Signature =~ s{\A\s+}{};
    $Signature =~ s{\s+\z}{};

    return '' if !$Signature;

    $Signature = $Self->_SystemSignatureBlockToBreaks( HTML => $Signature );

    return $Signature if $Signature =~ m{\bqisutu-mail-signature\b}i;

    return '<div class="qisutu-mail-signature" style="margin-top: 10px; padding-top: 6px; border-top: 1px dashed #cbd5df; color: #5d6b7c; font-size: 13px; line-height: 1.25;">'
        . $Signature
        . '</div>';
}

sub _SystemSignatureBlockToBreaks {
    my ( $Self, %Param ) = @_;

    my $HTML = $Param{HTML} || '';

    return '' if !$HTML;

    # Die Queue-/Systemsignatur wird in eine mailtaugliche, kompakte Form
    # gebracht. Normale <p>/<div>-Blöcke erzeugen in Mailclients oft große
    # Standardabstände. Deshalb werden nur innerhalb der Signatur die Block-
    # Absätze in explizite <br>-Zeilenumbrüche umgewandelt. Leere Absätze
    # bleiben als zusätzliche Leerzeile erhalten.
    for ( 1 .. 8 ) {
        last if $HTML !~ s{<\s*(p|div)\b([^>]*)>(.*?)<\s*/\s*\1\s*>}{
            my $Content = $3 || '';

            if ( $Content =~ m{\A(?:\s|&nbsp;|&#160;|<\s*br\s*/?\s*>)*\z}is ) {
                '<br>';
            }
            else {
                $Content . '<br>';
            }
        }gexis;
    }

    $HTML =~ s{(?:\s*<\s*br\s*/?\s*>\s*){4,}}{<br><br><br>}gis;
    $HTML =~ s{(?:\s*<\s*br\s*/?\s*>\s*)+\z}{}gis;
    $HTML =~ s{\A\s+|\s+\z}{}g;

    return $HTML;
}

sub _ActiveSMTPAccount {
    my ($Self) = @_;

    return if !$Self->{DB};

    return $Self->{DB}->SelectRow(
        'SELECT *
         FROM smtp_account
         WHERE active = 1
         ORDER BY sort_order ASC, id ASC
         LIMIT 1'
    );
}

sub _StatusOptionsHTML {
    my ( $Self, %Param ) = @_;

    my $Language         = $Param{Language} || 'en';
    my $DefaultStateName = $Param{DefaultStateName} || 'open';
    my $CurrentStateName = $Param{CurrentStateName} || '';

    my $States = $Self->{DB}->SelectAll(
        'SELECT id, name, state_type
         FROM ticket_state
         WHERE active = 1
         ORDER BY sort_order ASC, id ASC'
    ) || [];

    my $SelectedID = 0;

    for my $State ( @{$States} ) {
        if ( !$SelectedID && ( $State->{name} || '' ) eq $DefaultStateName ) {
            $SelectedID = $State->{id};
        }
    }

    if ( !$SelectedID ) {
        for my $State ( @{$States} ) {
            if ( !$SelectedID && ( $State->{name} || '' ) eq $CurrentStateName ) {
                $SelectedID = $State->{id};
            }
        }
    }

    my $HTML = '';

    for my $State ( @{$States} ) {
        my $Selected = $SelectedID && $State->{id} == $SelectedID ? ' selected' : '';
        my $Label    = $Self->_TicketStateText(
            State    => $State->{name},
            Language => $Language,
        );

        my $StateTypeAttribute = $State->{state_type}
            ? ' data-state-type="' . $Self->_Escape( $State->{state_type} ) . '"'
            : '';

        $HTML .= '<option value="' . $Self->_Escape( $State->{id} ) . '"' . $Selected . $StateTypeAttribute . '>'
            . $Self->_Escape($Label)
            . '</option>';
    }

    return $HTML;
}

sub _SubmittedStatusID {
    my ( $Self, %Param ) = @_;

    my $StatusID = $Param{StatusID} || 0;

    if ( $StatusID =~ m{\A\d+\z} && $StatusID ) {
        my $State = $Self->{DB}->SelectRow(
            'SELECT id
             FROM ticket_state
             WHERE id = ?
               AND active = 1
             LIMIT 1',
            $StatusID,
        );

        return $State->{id} if $State;
    }

    my $Default = $Self->{DB}->SelectRow(
        'SELECT id
         FROM ticket_state
         WHERE name = ?
           AND active = 1
         LIMIT 1',
        'open',
    );

    return $Default ? $Default->{id} : 0;
}

sub _TicketStatusUpdate {
    my ( $Self, %Param ) = @_;

    my $TicketID        = $Param{TicketID} || 0;
    my $StatusID        = $Param{StatusID} || 0;
    my $ChangedByUserID = $Param{ChangedByUserID} || 1;

    return if $TicketID !~ m{\A\d+\z} || !$TicketID;
    return if $StatusID !~ m{\A\d+\z} || !$StatusID;

    my $State = $Self->{DB}->SelectRow(
        'SELECT id, state_type
         FROM ticket_state
         WHERE id = ?
           AND active = 1
         LIMIT 1',
        $StatusID,
    );

    return if !$State;

    my $StateType = $State->{state_type} || '';

    if ( $StateType eq 'pending' ) {
        return $Self->{DB}->Do(
            'UPDATE ticket
             SET state_id = ?,
                 pending_started_at = COALESCE(pending_started_at, NOW()),
                 changed_by_user_id = ?,
                 changed_at = NOW()
             WHERE id = ?',
            $StatusID,
            $ChangedByUserID,
            $TicketID,
        );
    }

    if ( $StateType eq 'closed' ) {
        return $Self->{DB}->Do(
            'UPDATE ticket
             SET state_id = ?,
                 pending_total_minutes = pending_total_minutes + IF(pending_started_at IS NULL, 0, TIMESTAMPDIFF(MINUTE, pending_started_at, NOW())),
                 pending_started_at = NULL,
                 pending_until = NULL,
                 solution_at = COALESCE(solution_at, NOW()),
                 changed_by_user_id = ?,
                 changed_at = NOW()
             WHERE id = ?',
            $StatusID,
            $ChangedByUserID,
            $TicketID,
        );
    }

    return $Self->{DB}->Do(
        'UPDATE ticket
         SET state_id = ?,
             pending_total_minutes = pending_total_minutes + IF(pending_started_at IS NULL, 0, TIMESTAMPDIFF(MINUTE, pending_started_at, NOW())),
             pending_started_at = NULL,
             pending_until = NULL,
             solution_at = NULL,
             changed_by_user_id = ?,
             changed_at = NOW()
         WHERE id = ?',
        $StatusID,
        $ChangedByUserID,
        $TicketID,
    );
}

sub _TicketStateText {
    my ( $Self, %Param ) = @_;

    my $State    = $Param{State} || '';
    my $Language = $Param{Language} || 'en';
    my $Key      = lc $State;

    $Key =~ s{\A\s+}{};
    $Key =~ s{\s+\z}{};
    $Key =~ s{\+}{ plus }g;
    $Key =~ s{-}{ minus }g;
    $Key =~ s{[^a-z0-9]+}{_}g;
    $Key =~ s{\A_+}{};
    $Key =~ s{_+\z}{};

    my %DE = (
        new                      => 'Neu',
        open                     => 'Offen',
        pending                  => 'Wartend',
        pending_reminder         => 'Warten auf Erinnerung',
        pending_auto_close       => 'Warten auf automatische Schließung',
        pending_auto_close_plus  => 'Warten auf automatische Schließung +',
        pending_auto_close_minus => 'Warten auf automatische Schließung -',
        closed                   => 'Geschlossen',
        closed_successful        => 'Erfolgreich geschlossen',
        closed_unsuccessful      => 'Erfolglos geschlossen',
        resolved                 => 'Gelöst',
        merged                   => 'Zusammengeführt',
        removed                  => 'Entfernt',
        deleted                  => 'Gelöscht',
        escalated                => 'Eskaliert',
    );

    my %EN = (
        new                      => 'New',
        open                     => 'Open',
        pending                  => 'Pending',
        pending_reminder         => 'Pending reminder',
        pending_auto_close       => 'Pending auto close',
        pending_auto_close_plus  => 'Pending auto close +',
        pending_auto_close_minus => 'Pending auto close -',
        closed                   => 'Closed',
        closed_successful        => 'Closed successful',
        closed_unsuccessful      => 'Closed unsuccessful',
        resolved                 => 'Resolved',
        merged                   => 'Merged',
        removed                  => 'Removed',
        deleted                  => 'Deleted',
        escalated                => 'Escalated',
    );

    return $DE{$Key} if $Language eq 'de' && $DE{$Key};
    return $EN{$Key} if $EN{$Key};

    return $State;
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

sub _DateTimeFormat {
    my ( $Self, %Param ) = @_;

    my $DateTime = $Param{DateTime} || '';
    my $Language = $Param{Language} || 'en';

    return '' if !$DateTime;

    if ( $DateTime =~ m{\A(\d{4})-(\d{2})-(\d{2})[ T](\d{2}):(\d{2}):(\d{2})\z} ) {
        my ( $Year, $Month, $Day, $Hour, $Minute, $Second ) = ( $1, $2, $3, $4, $5, $6 );

        if ( $Language eq 'de' ) {
            return "$Day.$Month.$Year $Hour:$Minute:$Second";
        }

        return "$Year-$Month-$Day $Hour:$Minute:$Second";
    }

    return $DateTime;
}

sub _AgeFormat {
    my ( $Self, %Param ) = @_;

    my $DateTime = $Param{DateTime} || '';
    my $Language = $Param{Language} || 'en';

    return '-' if !$DateTime;

    if ( $DateTime !~ m{\A(\d{4})-(\d{2})-(\d{2})[ T](\d{2}):(\d{2}):(\d{2})\z} ) {
        return '-';
    }

    my ( $Year, $Month, $Day, $Hour, $Minute, $Second ) = ( $1, $2, $3, $4, $5, $6 );
    my $CreatedEpoch;

    eval {
        $CreatedEpoch = timelocal( $Second, $Minute, $Hour, $Day, $Month - 1, $Year - 1900 );
        1;
    } || return '-';

    my $AgeSeconds = time() - $CreatedEpoch;

    if ( $AgeSeconds < 0 ) {
        $AgeSeconds = 0;
    }

    my $Minutes = int( $AgeSeconds / 60 );
    my $Hours   = int( $Minutes / 60 );
    my $Days    = int( $Hours / 24 );

    if ( $Language eq 'de' ) {
        return $Days . ( $Days == 1 ? ' Tag' : ' Tage' ) if $Days;
        return $Hours . ( $Hours == 1 ? ' Stunde' : ' Stunden' ) if $Hours;
        return $Minutes . ( $Minutes == 1 ? ' Minute' : ' Minuten' );
    }

    return $Days . ( $Days == 1 ? ' day' : ' days' ) if $Days;
    return $Hours . ( $Hours == 1 ? ' hour' : ' hours' ) if $Hours;
    return $Minutes . ( $Minutes == 1 ? ' minute' : ' minutes' );
}

1;
