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

package AgentTicketCreate;

use strict;
use warnings;
use utf8;

use JSON::PP qw(encode_json);
use QisutuService;
use QisutuTimeAccounting;
use QisutuCMDB;
use QisutuKnowledgeBase;

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
    my $Step     = $Request->{Step} || '';
    my $CMDBObject = QisutuCMDB->new( Config => $Self->{Config}, DB => $Self->{DB}, Output => $Self->{Output} );
    my $KnowledgeObject = QisutuKnowledgeBase->new( Config => $Self->{Config}, DB => $Self->{DB}, Output => $Self->{Output} );
    my $KnowledgePermission = $KnowledgeObject->PermissionLevel( User => $User );

    if ( $Step eq 'AgentLookup' ) {
        return $Self->_JSONResponse(
            Data => $Self->_AgentLookup(
                Query => $Request->{Term} || $Request->{term} || $Request->{Query} || $Request->{query} || $Request->{q} || '',
            ),
        );
    }

    if ( $Step eq 'CustomerUserLookup' ) {
        return $Self->_JSONResponse(
            Data => $Self->_CustomerUserLookup(
                Query => $Request->{Term} || $Request->{term} || $Request->{Query} || $Request->{query} || $Request->{q} || '',
            ),
        );
    }

    if ( $Step eq 'CustomerUserInfo' ) {
        return $Self->_JSONResponse(
            Data => $Self->_CustomerUserInfo(
                CustomerUserID => $Request->{CustomerUserID},
                Language       => $Language,
            ),
        );
    }

    if ( $Step eq 'CMDBLookup' ) {
        my $Permission = $CMDBObject->PermissionLevel( User => $User );
        return $Self->_JSONResponse(
            Data => {
                success => $Permission->{View} ? 1 : 0,
                items   => $Permission->{View} ? $CMDBObject->SearchItems(
                    Query => $Request->{Term} || $Request->{term} || $Request->{Query} || $Request->{query} || $Request->{q} || '',
                    Limit => 30,
                ) : [],
            },
        );
    }

    if ( $Step eq 'ServiceOptions' ) {
        return $Self->_JSONResponse(
            Data => $Self->_ServiceOptionsData(
                CustomerUserID => $Request->{CustomerUserID},
                Language       => $Language,
            ),
        );
    }

    if ( $Step eq 'QueueTemplate' ) {
        return $Self->_JSONResponse(
            Data => $Self->_QueueTemplateData(
                QueueID => $Request->{QueueID},
                User    => $User,
            ),
        );
    }

    if ( $Step eq 'DynamicFields' ) {
        my $QueueCheck = $Self->_QueueTemplateData(
            QueueID => $Request->{QueueID},
            User    => $User,
        );
        my $DynamicFieldObject = $Self->_DynamicFieldObject();

        my $HTML = '';
        my $Success = $QueueCheck->{success} && $DynamicFieldObject ? 1 : 0;

        if ($Success) {
            $HTML = $DynamicFieldObject->FormHTML(
                QueueID  => $Request->{QueueID},
                Language => $Language,
                IDPrefix => 'qisutu-agent-ticket-create-dynamic-field',
            );
            $Success = 0 if $DynamicFieldObject->Error();
        }

        return $Self->_JSONResponse(
            Data => {
                success => $Success,
                html    => $Success ? $HTML : '',
            },
        );
    }

    my $TicketObject          = $Self->_TicketObject();
    my $DynamicFieldObject    = $Self->_DynamicFieldObject();
    my $ServiceObject         = QisutuService->new( Config => $Self->{Config}, DB => $Self->{DB} );
    my $TimeAccountingObject  = QisutuTimeAccounting->new( Config => $Self->{Config}, DB => $Self->{DB}, Output => $Self->{Output} );
    my $AttachmentMaxSizeMB   = $Self->_AttachmentMaxSizeMB();
    my $AttachmentMaxSizeByte = $AttachmentMaxSizeMB * 1024 * 1024;
    my $IsSubmit              = $Step eq 'AgentTicketCreate' ? 1 : 0;
    my $CreateError           = '';
    my $SendEmail             = $IsSubmit ? ( $Request->{SendEmail} ? 1 : 0 ) : 1;
    my $TimeAccountingInput;

    if ($IsSubmit) {
        $TimeAccountingInput = $TimeAccountingObject->InputParse( Request => $Request );
        $CreateError = $TimeAccountingObject->Error() if !$TimeAccountingInput;
    }

    my $QueueList = $Self->_QueueList( User => $User );
    my $QueueID   = $Request->{QueueID} || 0;
    my $ServiceID = $Request->{ServiceID} || 0;
    my $StateID   = $Request->{StateID} || $Self->_DefaultStateID();
    my $PriorityID = $Request->{PriorityID} || $Self->_DefaultPriorityID();
    my $PendingUntil = $Request->{PendingUntil} || '';
    my $StateType    = $Self->_StateTypeGet( StateID => $StateID );
    my $IsPending    = $StateType eq 'pending' ? 1 : 0;

    my $Body = $Request->{Body} || '';
    if ( !$IsSubmit && $QueueID ) {
        $Body = $Self->_QueueTemplateHTML( QueueID => $QueueID );
    }

    if ( $IsSubmit && $TicketObject ) {
        my $UploadResult = $Self->_UploadedAttachments(
            Request      => $Request,
            MaxSizeBytes => $AttachmentMaxSizeByte,
        );
        my $Attachments = $UploadResult->{Attachments} || [];

        if ( @{ $UploadResult->{Oversized} || [] } ) {
            $CreateError = $Self->_AttachmentTooLargeMessage(
                Attachment => $UploadResult->{Oversized}->[0],
                MaxSizeMB  => $AttachmentMaxSizeMB,
                Language   => $Language,
            );
        }

        if ( !$CreateError && ( $Request->{OwnerUserSearch} || '' ) ne '' && !( $Request->{OwnerUserID} || 0 ) ) {
            $CreateError = 'Translate:AgentTicketCreateOwnerInvalid';
        }

        if ( !$CreateError && ( $Request->{ResponsibleUserSearch} || '' ) ne '' && !( $Request->{ResponsibleUserID} || 0 ) ) {
            $CreateError = 'Translate:AgentTicketCreateResponsibleInvalid';
        }

        if ( !$CreateError ) {
            my $CcCheck = $Self->_EmailRecipientsParse(
                Value    => $Request->{Cc} || '',
                Required => 0,
            );

            if ( !$CcCheck->{Valid} ) {
                $CreateError = $CcCheck->{Error} || 'Translate:AgentTicketCreateCcInvalid';
            }
            else {
                $Request->{Cc} = $CcCheck->{Header};
            }
        }

        if ( !$CreateError && $ServiceID ) {
            my $CustomerID = $ServiceObject->CustomerIDFromCustomerUser(
                CustomerUserID => $Request->{CustomerUserID},
            );
            my $ResolvedSLA = $CustomerID ? $ServiceObject->SLAResolve(
                CustomerID => $CustomerID,
                ServiceID  => $ServiceID,
            ) : undef;
            if ( !$ResolvedSLA ) {
                $CreateError = $ServiceObject->Error() || 'Translate:TicketServiceNotAvailable';
            }
        }

        if ( !$CreateError && $QueueID ) {
            if ( !$DynamicFieldObject ) {
                $CreateError = 'Translate:AdminDynamicFieldLoadFailed';
            }
            elsif ( !$DynamicFieldObject->TicketValueValidate(
                QueueID  => $QueueID,
                Request  => $Request,
                Language => $Language,
            ) ) {
                $CreateError = $DynamicFieldObject->Error() || 'Translate:TicketDynamicFieldInvalid';
            }
        }

        if ( !$CreateError ) {
            my $TicketID = $TicketObject->TicketCreateFromAgent(
                User              => $User,
                QueueID           => $QueueID,
                ServiceID         => $ServiceID,
                CustomerUserID    => $Request->{CustomerUserID},
                OwnerUserID       => $Request->{OwnerUserID},
                ResponsibleUserID => $Request->{ResponsibleUserID},
                Title             => $Request->{Title},
                Body              => $Body,
                ContentType       => 'text/html',
                Cc                => $Request->{Cc},
                StateID           => $StateID,
                PriorityID        => $PriorityID,
                PendingUntil      => $PendingUntil,
                SendEmail         => $SendEmail,
                Attachments       => $Attachments,
                DynamicFieldRequest => $Request,
                Language            => $Language,
                TimeAccounting      => $TimeAccountingInput,
            );

            if ($TicketID) {
                if ( $Request->{CMDBCIID} && $CMDBObject->PermissionLevel( User => $User )->{Change} ) {
                    $CMDBObject->TicketLinkAdd(
                        TicketID => $TicketID,
                        CIID     => $Request->{CMDBCIID},
                        User     => $User,
                    );
                }
                my @KnowledgeUsage = ref $Request->{KnowledgeUsage} eq 'ARRAY'
                    ? @{ $Request->{KnowledgeUsage} }
                    : defined $Request->{KnowledgeUsage} && $Request->{KnowledgeUsage} ne ''
                        ? ( $Request->{KnowledgeUsage} )
                        : ();
                for my $Usage (@KnowledgeUsage) {
                    next if !defined $Usage || $Usage !~ m{\A(\d+)\|(solution|title_solution|link)\z};
                    $KnowledgeObject->UsageRecord(
                        ArticleID => $1,
                        TicketID  => $TicketID,
                        UserID    => $User->{user_account_id},
                        Context   => 'ticket_create',
                        InsertMode => $2,
                    );
                }
                return {
                    Redirect => 'index.pl?Page=AgentTicketZoom&TicketID=' . $TicketID,
                };
            }

            $CreateError = $TicketObject->Error() || 'Translate:TicketCreateFailed';
        }
    }
    elsif ( $IsSubmit && !$TicketObject ) {
        $CreateError = 'Translate:TicketCreateFailed';
    }

    my $HasQueueOptions = @{$QueueList} ? 1 : 0;
    my $QueueOptionsHTML = $Self->_QueueOptionsHTML(
        QueueList       => $QueueList,
        CurrentQueueID  => $QueueID,
        Language         => $Language,
    );
    my $StatusOptionsHTML = $Self->_StatusOptionsHTML(
        CurrentStateID => $StateID,
        Language       => $Language,
    );
    my $PriorityOptionsHTML = $Self->_PriorityOptionsHTML(
        CurrentPriorityID => $PriorityID,
        Language          => $Language,
    );
    my $ServiceData = $Request->{CustomerUserID}
        ? $Self->_ServiceOptionsData(
            CustomerUserID => $Request->{CustomerUserID},
            Language       => $Language,
        )
        : { success => 1, items => [] };
    my $ServiceOptionsHTML = $Self->_ServiceOptionsHTML(
        Items             => $ServiceData->{items} || [],
        CurrentServiceID  => $ServiceID,
        Language          => $Language,
    );
    my $SelectedService = {};
    for my $Item ( @{ $ServiceData->{items} || [] } ) {
        if ( ( $Item->{id} || 0 ) == $ServiceID ) {
            $SelectedService = $Item;
            last;
        }
    }

    my $TicketDynamicFieldsHTML = $DynamicFieldObject && $QueueID
        ? $DynamicFieldObject->FormHTML(
            QueueID  => $QueueID,
            Request  => $Request,
            Language => $Language,
            IDPrefix => 'qisutu-agent-ticket-create-dynamic-field',
        )
        : '';
    my $TimeAccountingFieldsHTML = $TimeAccountingObject->FormHTML(
        Language => $Language,
        Request  => $CreateError ? $Request : {},
        IDPrefix => 'qisutu-agent-ticket-create-time-accounting',
    );

    return {
        Template => 'AgentTicketCreate.tt',
        Data     => {
            PageTitle          => 'Translate:AgentTicketCreateTitle',
            ProgramTitle       => 'Translate:AgentTicketCreateTitle',
            ProgramDescription => 'Translate:AgentTicketCreateDescription',
            TicketListURL      => 'index.pl?Page=AgentTicketList',
            FormAction         => 'index.pl',
            HasQueueOptions    => $HasQueueOptions,
            QueueOptionsHTML   => $QueueOptionsHTML,
            ServiceOptionsHTML => $ServiceOptionsHTML,
            ServiceID          => $ServiceID,
            ServiceOptionsURL  => 'index.pl?Page=AgentTicketCreate&Step=ServiceOptions',
            ServiceSLAName     => $SelectedService->{sla_name} || '',
            ServiceSLACalendar => $SelectedService->{calendar_name} || '',
            ServiceSLASource   => 'Translate:TicketSLASourceCustomer',
            ServiceSLAFirstResponseMinutes => $SelectedService->{first_response_minutes} || 0,
            ServiceSLAUpdateMinutes        => $SelectedService->{update_minutes} || 0,
            ServiceSLASolutionMinutes      => $SelectedService->{solution_minutes} || 0,
            ServiceSLAUpdateMode => ( $SelectedService->{update_mode} || '' ) eq 'regular' ? 'Translate:AdminSLAUpdateModeRegular' : 'Translate:AdminSLAUpdateModeCustomer',
            ServiceSLAInfoClass => $ServiceID && $SelectedService->{sla_id} ? '' : 'qisutu-hidden',
            StatusOptionsHTML  => $StatusOptionsHTML,
            PriorityOptionsHTML => $PriorityOptionsHTML,
            TicketDynamicFieldsHTML => $TicketDynamicFieldsHTML,
            TimeAccountingFieldsHTML => $TimeAccountingFieldsHTML,
            CreateError        => $CreateError,
            CreateErrorClass   => $CreateError ? '' : 'qisutu-hidden',
            SendEmailChecked   => $SendEmail ? 'checked' : '',
            CustomerUserID     => $Request->{CustomerUserID} || '',
            CustomerUserSearch => $Request->{CustomerUserSearch} || '',
            CMDBCIID           => $Request->{CMDBCIID} || '',
            CMDBCISearch       => $Request->{CMDBCISearch} || '',
            Cc                  => $Request->{Cc} || '',
            OwnerUserID         => $Request->{OwnerUserID} || '',
            OwnerUserSearch     => $Request->{OwnerUserSearch} || '',
            ResponsibleUserID   => $Request->{ResponsibleUserID} || '',
            ResponsibleUserSearch => $Request->{ResponsibleUserSearch} || '',
            Title               => $Request->{Title} || '',
            Body                => $Body,
            PendingUntil        => $PendingUntil,
            PendingUntilFieldClass => $IsPending ? '' : 'qisutu-hidden',
            PendingUntilRequired   => $IsPending ? 'required' : '',
            AttachmentMaxSizeMB => $AttachmentMaxSizeMB,
            AttachmentMaxSizeBytes => $AttachmentMaxSizeByte,
            HasKnowledgeAccess  => $KnowledgePermission->{View} ? 1 : 0,
        },
    };
}

sub _JSONResponse {
    my ( $Self, %Param ) = @_;

    my $Body = encode_json( $Param{Data} || {} );

    return {
        Response => $Self->{Output}->Response(
            ContentType => 'application/json; charset=UTF-8',
            Body        => $Body,
        ),
    };
}

sub _QueueList {
    my ( $Self, %Param ) = @_;

    my $User = $Param{User} || {};
    my $PermissionObject = $Self->_PermissionObject();

    return [] if !$PermissionObject;

    my $QueueIDs = $PermissionObject->QueueIDList(
        UserID     => $User->{user_account_id},
        Permission => 'ticket.create',
    ) || [];

    return [] if !@{$QueueIDs};

    my $Placeholders = join ', ', ('?') x @{$QueueIDs};
    return $Self->{DB}->SelectAll(
        'SELECT id, name, full_name
         FROM ticket_queue
         WHERE active = 1
           AND id IN (' . $Placeholders . ')
         ORDER BY sort_order ASC, full_name ASC, id ASC',
        @{$QueueIDs},
    ) || [];
}

sub _QueueOptionsHTML {
    my ( $Self, %Param ) = @_;

    my $Rows      = $Param{QueueList} || [];
    my $CurrentID = $Param{CurrentQueueID} || 0;
    my $Language  = $Param{Language} || $Self->{Config}->{Language}->{Default} || 'en';
    my $Placeholder = $Self->_Translation(
        Key      => 'AgentTicketCreateQueuePlaceholder',
        Language => $Language,
        Fallback => $Language eq 'de' ? 'Bitte Queue auswählen' : 'Please select a queue',
    );
    my $HTML = '<option value="">' . $Self->_Escape($Placeholder) . '</option>';

    for my $Row ( @{$Rows} ) {
        my $Selected = $CurrentID && $Row->{id} == $CurrentID ? ' selected' : '';
        my $Name = $Row->{full_name} || $Row->{name} || '';
        $HTML .= '<option value="' . $Self->_Escape( $Row->{id} ) . '"' . $Selected . '>'
            . $Self->_Escape($Name)
            . '</option>';
    }

    return $HTML;
}

sub _StatusOptionsHTML {
    my ( $Self, %Param ) = @_;

    my $CurrentID = $Param{CurrentStateID} || 0;
    my $Language  = $Param{Language} || 'en';
    my $Rows = $Self->{DB}->SelectAll(
        'SELECT id, name, state_type
         FROM ticket_state
         WHERE active = 1
         ORDER BY sort_order ASC, id ASC'
    ) || [];
    my $HTML = '';

    for my $Row ( @{$Rows} ) {
        my $Selected = $CurrentID && $Row->{id} == $CurrentID ? ' selected' : '';
        my $Label = $Self->_StateDisplayName(
            State    => $Row->{name},
            Language => $Language,
        );
        $HTML .= '<option value="' . $Self->_Escape( $Row->{id} ) . '" data-state-type="'
            . $Self->_Escape( $Row->{state_type} || '' ) . '"' . $Selected . '>'
            . $Self->_Escape($Label)
            . '</option>';
    }

    return $HTML;
}

sub _PriorityOptionsHTML {
    my ( $Self, %Param ) = @_;

    my $CurrentID = $Param{CurrentPriorityID} || 0;
    my $Language  = $Param{Language} || 'en';
    my $Rows = $Self->{DB}->SelectAll(
        'SELECT id, name
         FROM ticket_priority
         WHERE active = 1
         ORDER BY sort_order ASC, priority_value ASC, id ASC'
    ) || [];
    my $HTML = '';

    for my $Row ( @{$Rows} ) {
        my $Selected = $CurrentID && $Row->{id} == $CurrentID ? ' selected' : '';
        my $Label = $Self->_PriorityDisplayName(
            Priority => $Row->{name},
            Language => $Language,
        );
        $HTML .= '<option value="' . $Self->_Escape( $Row->{id} ) . '"' . $Selected . '>'
            . $Self->_Escape($Label)
            . '</option>';
    }

    return $HTML;
}

sub _StateTypeGet {
    my ( $Self, %Param ) = @_;

    my $StateID = $Param{StateID} || 0;
    return '' if $StateID !~ m{\A\d+\z} || !$StateID;

    my $Row = $Self->{DB}->SelectRow(
        'SELECT state_type
         FROM ticket_state
         WHERE id = ?
           AND active = 1
         LIMIT 1',
        $StateID,
    );

    return $Row ? ( $Row->{state_type} || '' ) : '';
}

sub _DefaultStateID {
    my ($Self) = @_;

    my $Row = $Self->{DB}->SelectRow(
        'SELECT id
         FROM ticket_state
         WHERE name = ?
           AND active = 1
         ORDER BY sort_order ASC, id ASC
         LIMIT 1',
        'new',
    );

    return $Row ? ( $Row->{id} || 0 ) : 0;
}

sub _DefaultPriorityID {
    my ($Self) = @_;

    my $Row = $Self->{DB}->SelectRow(
        'SELECT id
         FROM ticket_priority
         WHERE active = 1
         ORDER BY CASE WHEN name = ? THEN 0 ELSE 1 END,
                  ABS(priority_value - 3) ASC,
                  sort_order ASC,
                  id ASC
         LIMIT 1',
        '3 normal',
    );

    return $Row ? ( $Row->{id} || 0 ) : 0;
}

sub _AgentLookup {
    my ( $Self, %Param ) = @_;

    my $Query = $Self->_Trim( $Param{Query} );
    return { items => [] } if length($Query) < 2;

    my $Like = '%' . $Query . '%';
    my $Rows = $Self->{DB}->SelectAll(
        'SELECT id, login, email, firstname, lastname
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
         ORDER BY lastname ASC, firstname ASC, login ASC
         LIMIT 20',
        'agent',
        $Like, $Like, $Like, $Like, $Like,
    ) || [];

    my @Items;
    for my $Row ( @{$Rows} ) {
        my $Name  = $Self->_UserName( User => $Row ) || $Row->{login} || '';
        my $Email = $Row->{email} || '';
        my $Login = $Row->{login} || '';
        my $Label = $Name;
        $Label .= ' (' . $Login . ')' if $Login && $Login ne $Name;
        $Label .= ' <' . $Email . '>' if $Email;

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
         INNER JOIN customer c ON c.id = cu.customer_id
         INNER JOIN user_account ua ON ua.id = cu.user_account_id
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
         ORDER BY c.name ASC, ua.lastname ASC, ua.firstname ASC, ua.login ASC
         LIMIT 20',
        'customer',
        $Like, $Like, $Like, $Like, $Like, $Like, $Like,
    ) || [];

    my @Items;
    for my $Row ( @{$Rows} ) {
        my $Name           = $Self->_UserName( User => $Row ) || $Row->{login} || '';
        my $Email          = $Row->{email} || '';
        my $CustomerName   = $Row->{customer_name} || '';
        my $CustomerNumber = $Row->{customer_number} || '';
        my $Label          = $Name;
        $Label .= ' <' . $Email . '>' if $Email;
        $Label .= ' — ' . $CustomerName if $CustomerName;

        push @Items, {
            id          => 0 + ( $Row->{id} || 0 ),
            customer_id => 0 + ( $Row->{customer_id} || 0 ),
            label       => $Label,
            description => join( ' · ', grep {$_} ( $CustomerNumber, $CustomerName, $Email ) ),
        };
    }

    return { items => \@Items };
}

sub _CustomerUserInfo {
    my ( $Self, %Param ) = @_;

    my $CustomerUserID = $Param{CustomerUserID} || 0;
    my $Language       = $Param{Language} || $Self->{Config}->{Language}->{Default} || 'en';

    return { success => 0 }
        if $CustomerUserID !~ m{\A\d+\z} || !$CustomerUserID;

    my $Row = $Self->{DB}->SelectRow(
        'SELECT
            cu.id AS customer_user_id,
            cu.active AS customer_user_active,
            c.id AS customer_id,
            c.customer_number,
            c.name AS customer_name,
            c.active AS customer_active,
            ua.email,
            ua.firstname,
            ua.lastname,
            ua.is_active AS user_account_active
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

    return { success => 0 } if !$Row;

    my $ActiveYes = $Self->_Translation(
        Key      => 'AdminActiveYes',
        Language => $Language,
        Fallback => $Language eq 'de' ? 'Ja' : 'Yes',
    );
    my $ActiveNo = $Self->_Translation(
        Key      => 'AdminActiveNo',
        Language => $Language,
        Fallback => $Language eq 'de' ? 'Nein' : 'No',
    );

    my @CustomerFields = (
        {
            label => $Self->_Translation(
                Key      => 'AdminCustomerNumber',
                Language => $Language,
                Fallback => $Language eq 'de' ? 'Kundennummer' : 'Customer number',
            ),
            value => $Row->{customer_number} || '',
        },
        {
            label => $Self->_Translation(
                Key      => 'AdminName',
                Language => $Language,
                Fallback => $Language eq 'de' ? 'Name' : 'Name',
            ),
            value => $Row->{customer_name} || '',
        },
        {
            label => $Self->_Translation(
                Key      => 'AdminActive',
                Language => $Language,
                Fallback => $Language eq 'de' ? 'Aktiv' : 'Active',
            ),
            value => $Row->{customer_active} ? $ActiveYes : $ActiveNo,
        },
    );

    push @CustomerFields, @{ $Self->_DynamicFieldInformationList(
        ObjectType => 'customer',
        ObjectID   => $Row->{customer_id},
        Language   => $Language,
    ) };

    my @CustomerUserFields = (
        {
            label => $Self->_Translation(
                Key      => 'AdminFirstname',
                Language => $Language,
                Fallback => $Language eq 'de' ? 'Vorname' : 'First name',
            ),
            value => $Row->{firstname} || '',
        },
        {
            label => $Self->_Translation(
                Key      => 'AdminLastname',
                Language => $Language,
                Fallback => $Language eq 'de' ? 'Nachname' : 'Last name',
            ),
            value => $Row->{lastname} || '',
        },
        {
            label => $Self->_Translation(
                Key      => 'AdminEmail',
                Language => $Language,
                Fallback => $Language eq 'de' ? 'E-Mail' : 'Email',
            ),
            value => $Row->{email} || '',
        },
        {
            label => $Self->_Translation(
                Key      => 'AdminActive',
                Language => $Language,
                Fallback => $Language eq 'de' ? 'Aktiv' : 'Active',
            ),
            value => $Row->{customer_user_active} && $Row->{user_account_active} ? $ActiveYes : $ActiveNo,
        },
    );

    push @CustomerUserFields, @{ $Self->_DynamicFieldInformationList(
        ObjectType => 'customer_user',
        ObjectID   => $Row->{customer_user_id},
        Language   => $Language,
    ) };

    return {
        success       => 1,
        customer      => { fields => \@CustomerFields },
        customer_user => { fields => \@CustomerUserFields },
    };
}

sub _DynamicFieldInformationList {
    my ( $Self, %Param ) = @_;

    my $ObjectType      = $Param{ObjectType} || '';
    my $ObjectID        = $Param{ObjectID} || 0;
    my $Language        = $Param{Language} || $Self->{Config}->{Language}->{Default} || 'en';
    my $DefaultLanguage = $Self->{Config}->{Language}->{Default} || 'en';

    return [] if !$ObjectType;
    return [] if $ObjectID !~ m{\A\d+\z} || !$ObjectID;

    my $Rows = $Self->{DB}->SelectAll(
        'SELECT
            COALESCE(current_translation.label, default_translation.label, f.label, f.name) AS label,
            f.field_type,
            COALESCE(v.value_text, "") AS value_text
         FROM user_dynamic_field f
         LEFT JOIN user_dynamic_field_translation current_translation
            ON current_translation.field_id = f.id
           AND current_translation.language = ?
         LEFT JOIN user_dynamic_field_translation default_translation
            ON default_translation.field_id = f.id
           AND default_translation.language = ?
         LEFT JOIN user_dynamic_field_value v
            ON v.field_id = f.id
           AND v.object_type = ?
           AND v.object_id = ?
         WHERE f.object_type = ?
           AND f.active = 1
         ORDER BY f.sort_order ASC, label ASC, f.id ASC',
        $Language,
        $DefaultLanguage,
        $ObjectType,
        $ObjectID,
        $ObjectType,
    ) || [];

    my @Fields;
    for my $Field ( @{$Rows} ) {
        push @Fields, {
            label      => $Field->{label} || '',
            value      => defined $Field->{value_text} ? $Field->{value_text} : '',
            field_type => $Field->{field_type} || 'text',
        };
    }

    return \@Fields;
}

sub _Translation {
    my ( $Self, %Param ) = @_;

    my $Key      = $Param{Key} || '';
    my $Language = $Param{Language} || $Self->{Config}->{Language}->{Default} || 'en';
    my $Fallback = defined $Param{Fallback} ? $Param{Fallback} : $Key;

    return $Fallback if !$Key || !$Self->{Output};

    my $Translated = $Self->{Output}->Translate(
        Key      => $Key,
        Language => $Language,
    );

    return $Translated && $Translated ne $Key ? $Translated : $Fallback;
}

sub _ServiceOptionsData {
    my ( $Self, %Param ) = @_;

    my $CustomerUserID = $Param{CustomerUserID} || 0;
    my $Language       = $Param{Language} || $Self->{Config}->{Language}->{Default} || 'en';
    my $ServiceObject  = QisutuService->new( Config => $Self->{Config}, DB => $Self->{DB} );
    my $CustomerID     = $ServiceObject->CustomerIDFromCustomerUser(
        CustomerUserID => $CustomerUserID,
    );

    return { success => 0, items => [] } if !$CustomerID;

    my $Rows = $ServiceObject->AvailableServiceTreeList( CustomerID => $CustomerID );
    return { success => 0, items => [], error => $ServiceObject->Error() } if $ServiceObject->Error();

    my @Items;
    for my $Row ( @{$Rows} ) {
        push @Items, {
            id                     => $Row->{id},
            parent_id              => $Row->{parent_id} || 0,
            depth                  => $Row->{depth} || 0,
            has_children           => $Row->{has_children} ? 1 : 0,
            selectable             => $Row->{selectable} ? 1 : 0,
            name                   => $Row->{name} || $Row->{full_name} || '',
            label                  => $Row->{name} || $Row->{full_name} || '',
            full_label             => $Row->{full_name} || $Row->{name} || '',
            sla_id                 => $Row->{sla_id} || 0,
            sla_name               => $Row->{sla_name} || '',
            calendar_name          => $Row->{calendar_name} || '',
            update_mode            => $Row->{update_mode} || 'customer_response',
            first_response_minutes => $Row->{first_response_minutes} || 0,
            update_minutes         => $Row->{update_minutes} || 0,
            solution_minutes       => $Row->{solution_minutes} || 0,
            assignment_source      => $Row->{assignment_source} || 'customer',
            assignment_source_label => $Self->_Translation(
                Key      => ( $Row->{assignment_source} || '' ) eq 'customer' ? 'TicketSLASourceCustomer' : 'TicketSLASourceDefault',
                Language => $Language,
                Fallback => ( $Row->{assignment_source} || '' ) eq 'customer' ? 'Customer assignment' : 'Service default',
            ),
            update_mode_label => $Self->_Translation(
                Key      => ( $Row->{update_mode} || '' ) eq 'regular' ? 'AdminSLAUpdateModeRegular' : 'AdminSLAUpdateModeCustomer',
                Language => $Language,
                Fallback => ( $Row->{update_mode} || '' ) eq 'regular' ? 'Regular update' : 'After customer response',
            ),
        };
    }

    return { success => 1, items => \@Items };
}

sub _ServiceOptionsHTML {
    my ( $Self, %Param ) = @_;

    my $Items = $Param{Items} || [];
    my $CurrentServiceID = $Param{CurrentServiceID} || 0;
    my $Language = $Param{Language} || $Self->{Config}->{Language}->{Default} || 'en';
    my $HTML = '<option value="">' . $Self->_Escape(
        $Self->_Translation(
            Key      => 'TicketServiceSelect',
            Language => $Language,
            Fallback => 'Select service',
        )
    ) . '</option>';

    for my $Item ( @{$Items} ) {
        my $ID = $Item->{id} || 0;
        next if !$ID;

        my $Selected = $ID == $CurrentServiceID ? ' selected' : '';
        my $Disabled = $Item->{selectable} ? '' : ' disabled';
        my $Indent = ( "\x{00A0}\x{00A0}" x ( $Item->{depth} || 0 ) );
        my $FallbackLabel = $Indent . ( $Item->{name} || $Item->{full_label} || '' );

        $HTML .= '<option value="' . $Self->_Escape($ID) . '"'
            . $Selected . $Disabled
            . ' data-qisutu-service-node="1"'
            . ' data-parent-id="' . $Self->_Escape( $Item->{parent_id} || 0 ) . '"'
            . ' data-service-name="' . $Self->_Escape( $Item->{name} || '' ) . '"'
            . ' data-service-full-name="' . $Self->_Escape( $Item->{full_label} || '' ) . '"'
            . ' data-service-selectable="' . ( $Item->{selectable} ? 1 : 0 ) . '"'
            . ' data-service-has-children="' . ( $Item->{has_children} ? 1 : 0 ) . '"'
            . ' data-service-depth="' . $Self->_Escape( $Item->{depth} || 0 ) . '">'
            . $Self->_Escape($FallbackLabel) . '</option>';
    }

    return $HTML;
}

sub _QueueTemplateData {
    my ( $Self, %Param ) = @_;

    my $QueueID = $Param{QueueID} || 0;
    my $User    = $Param{User} || {};

    return { success => 0, body_template => '' }
        if $QueueID !~ m{\A\d+\z} || !$QueueID;

    my $PermissionObject = $Self->_PermissionObject();
    return { success => 0, body_template => '' } if !$PermissionObject;

    my $Allowed = $PermissionObject->QueueAccessCheck(
        UserID     => $User->{user_account_id},
        QueueID    => $QueueID,
        Permission => 'ticket.create',
    );

    return { success => 0, body_template => '' } if !$Allowed;

    return {
        success       => 1,
        body_template => $Self->_QueueTemplateHTML( QueueID => $QueueID ),
    };
}

sub _QueueTemplateHTML {
    my ( $Self, %Param ) = @_;

    my $QueueID = $Param{QueueID} || 0;
    return '' if !$QueueID;

    my $Loaded = eval {
        require QisutuHTML;
        1;
    };
    return '' if !$Loaded;

    my $Row = $Self->{DB}->SelectRow(
        'SELECT
            sal.content AS salutation_content,
            sig.content AS signature_content
         FROM ticket_queue q
         LEFT JOIN salutation sal
            ON sal.id = q.salutation_id
           AND sal.active = 1
         LEFT JOIN signature sig
            ON sig.id = q.signature_id
           AND sig.active = 1
         WHERE q.id = ?
           AND q.active = 1
         LIMIT 1',
        $QueueID,
    );

    return '' if !$Row;

    my $Salutation = QisutuHTML->Sanitize( $Row->{salutation_content} || '' );
    my $Signature  = QisutuHTML->Sanitize( $Row->{signature_content} || '' );
    my @Parts;

    if ($Salutation) {
        $Salutation = $Self->_SystemSignatureBlockToBreaks( HTML => $Salutation );
        push @Parts, '<div class="qisutu-mail-salutation">' . $Salutation . '</div>';
    }

    push @Parts, '<p><br></p><p><br></p>';

    if ($Signature) {
        $Signature = $Self->_SystemSignatureBlockToBreaks( HTML => $Signature );
        push @Parts, '<div class="qisutu-mail-signature" style="margin-top: 10px; padding-top: 6px; border-top: 1px dashed #cbd5df; color: #5d6b7c; font-size: 13px; line-height: 1.25;">'
            . $Signature
            . '</div>';
    }

    return join "\n", @Parts;
}

sub _SystemSignatureBlockToBreaks {
    my ( $Self, %Param ) = @_;

    my $HTML = $Param{HTML} || '';
    return '' if !$HTML;

    for ( 1 .. 8 ) {
        last if $HTML !~ s{<\s*(p|div)\b([^>]*)>(.*?)<\s*/\s*\1\s*>}{
            my $Content = $3 || '';
            $Content =~ m{\A(?:\s|&nbsp;|&#160;|<\s*br\s*/?\s*>)*\z}is
                ? '<br>'
                : $Content . '<br>';
        }egis;
    }

    $HTML =~ s{(?:\s*<\s*br\s*/?\s*>\s*){4,}}{<br><br><br>}gis;
    $HTML =~ s{(?:\s*<\s*br\s*/?\s*>\s*)+\z}{}gis;
    $HTML =~ s{\A\s+|\s+\z}{}g;

    return $HTML;
}

sub _UploadedAttachments {
    my ( $Self, %Param ) = @_;

    my $Request      = $Param{Request} || {};
    my $MaxSizeBytes = $Param{MaxSizeBytes} || 0;
    my $Uploads      = $Request->{__Uploads} || {};
    my $RawList      = [];

    if ( ref $Uploads->{TicketAttachment} eq 'ARRAY' ) {
        $RawList = $Uploads->{TicketAttachment};
    }
    elsif ( ref $Uploads->{'TicketAttachment[]'} eq 'ARRAY' ) {
        $RawList = $Uploads->{'TicketAttachment[]'};
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
    my $Loaded = eval {
        require QisutuSystemSetting;
        1;
    };

    if ( $Loaded && $Self->{DB} ) {
        my $SettingObject = QisutuSystemSetting->new(
            Config => $Self->{Config},
            DB     => $Self->{DB},
        );
        $Value = $SettingObject->AttachmentMaxSizeMB();
    }

    return $Value;
}

sub _AttachmentTooLargeMessage {
    my ( $Self, %Param ) = @_;

    my $Attachment = $Param{Attachment} || {};
    my $MaxSizeMB  = $Param{MaxSizeMB} || 25;
    my $Language   = $Param{Language} || 'en';
    my $Filename   = $Attachment->{Filename} || 'attachment';
    my $Template   = $Self->{Output}->Translate(
        Key      => 'TicketArticleAttachmentTooLargeServer',
        Language => $Language,
    ) || '';

    $Template ||= $Language eq 'de'
        ? 'Der Anhang „{{Filename}}“ überschreitet die erlaubte Maximalgröße von {{MaxSize}}. Bitte wenden Sie sich an den Administrator.'
        : 'The attachment “{{Filename}}” exceeds the permitted maximum size of {{MaxSize}}. Please contact the administrator.';

    $Template =~ s{\{\{Filename\}\}}{$Filename}g;
    $Template =~ s{\{\{MaxSize\}\}}{$MaxSizeMB . ' MB'}ge;

    return $Template;
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

    my @Emails;
    my %Seen;

    for my $Part (@Parts) {
        my $Email = $Part;
        $Email = $1 if $Email =~ m{<([^>]+)>};
        $Email =~ s{\A\s+|\s+\z}{}g;

        if ( $Email !~ m{\A[A-Z0-9._%+\-]+\@[A-Z0-9.\-]+\.[A-Z]{2,}\z}i ) {
            return { Valid => 0, Error => 'Translate:AgentTicketCreateCcInvalid' };
        }

        my $Key = lc $Email;
        next if $Seen{$Key}++;
        push @Emails, $Email;
    }

    return {
        Valid  => 1,
        Header => join( ', ', @Emails ),
        Emails => \@Emails,
    };
}

sub _StateDisplayName {
    my ( $Self, %Param ) = @_;

    my $Name = $Param{State} || '';
    my $Key  = lc $Name;
    $Key =~ s{\+}{ plus }g;
    $Key =~ s{-}{ minus }g;
    $Key =~ s{[^a-z0-9]+}{_}g;
    $Key =~ s{\A_+|_+\z}{}g;

    my $TranslationKey = 'TicketStateName_' . $Key;
    my $Translated = $Self->{Output}->Translate(
        Key      => $TranslationKey,
        Language => $Param{Language} || 'en',
    );

    return $Translated && $Translated ne $TranslationKey ? $Translated : $Name;
}

sub _PriorityDisplayName {
    my ( $Self, %Param ) = @_;

    my $Name = $Param{Priority} || '';
    my $Key  = lc $Name;
    $Key =~ s{[^a-z0-9]+}{_}g;
    $Key =~ s{\A_+|_+\z}{}g;

    my $TranslationKey = 'TicketPriorityName_' . $Key;
    my $Translated = $Self->{Output}->Translate(
        Key      => $TranslationKey,
        Language => $Param{Language} || 'en',
    );

    return $Translated && $Translated ne $TranslationKey ? $Translated : $Name;
}

sub _UserName {
    my ( $Self, %Param ) = @_;

    my $User = $Param{User} || {};
    my $Name = join ' ', grep { defined $_ && length $_ } ( $User->{firstname}, $User->{lastname} );
    return $Name || $User->{login} || $User->{email} || '';
}

sub _Trim {
    my ( $Self, $Value ) = @_;

    $Value = '' if !defined $Value;
    $Value =~ s{\A\s+|\s+\z}{}g;
    return $Value;
}

sub _Escape {
    my ( $Self, $Value ) = @_;

    $Value = '' if !defined $Value;
    return $Self->{Output}->HTMLEscape($Value) if $Self->{Output};

    $Value =~ s{&}{&amp;}g;
    $Value =~ s{<}{&lt;}g;
    $Value =~ s{>}{&gt;}g;
    $Value =~ s{"}{&quot;}g;
    return $Value;
}

sub _PermissionObject {
    my ($Self) = @_;

    return $Self->{PermissionObject} if $Self->{PermissionObject};
    return if !$Self->{DB};

    my $Loaded = eval {
        require QisutuPermission;
        1;
    };
    return if !$Loaded;

    $Self->{PermissionObject} = QisutuPermission->new(
        Config => $Self->{Config},
        DB     => $Self->{DB},
    );

    return $Self->{PermissionObject};
}

sub _DynamicFieldObject {
    my ($Self) = @_;

    return $Self->{DynamicFieldObject} if $Self->{DynamicFieldObject};
    return if !$Self->{DB};

    my $Loaded = eval {
        require QisutuDynamicField;
        1;
    };
    return if !$Loaded;

    $Self->{DynamicFieldObject} = QisutuDynamicField->new(
        Config => $Self->{Config},
        DB     => $Self->{DB},
        Output => $Self->{Output},
    );

    return $Self->{DynamicFieldObject};
}

sub _TicketObject {
    my ($Self) = @_;

    return if !$Self->{DB};

    my $Loaded = eval {
        require QisutuTicket;
        1;
    };
    return if !$Loaded;

    return QisutuTicket->new(
        Config     => $Self->{Config},
        DB         => $Self->{DB},
        Permission => $Self->_PermissionObject(),
    );
}

1;
