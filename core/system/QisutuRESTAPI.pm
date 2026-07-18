# Qisutu - Open Source Ticket System
# Copyright (C) 2026 Franziska Steps
# SPDX-License-Identifier: AGPL-3.0-or-later

package QisutuRESTAPI;

use strict;
use warnings;
use utf8;

use Digest::SHA qw(sha256_hex);
use JSON::PP ();
use MIME::Base64 qw(decode_base64);
use Time::HiRes qw(time);

use QisutuAdmin;
use QisutuAPIAuth;
use QisutuDynamicField;
use QisutuPermission;
use QisutuTicket;

sub new {
    my ( $Class, %Param ) = @_;
    my $Permission = QisutuPermission->new( Config => $Param{Config}, DB => $Param{DB} );
    my $Self = {
        Config     => $Param{Config},
        DB         => $Param{DB},
        Permission => $Permission,
        Auth       => QisutuAPIAuth->new( Config => $Param{Config}, DB => $Param{DB} ),
        Ticket     => QisutuTicket->new( Config => $Param{Config}, DB => $Param{DB}, Permission => $Permission ),
        Admin      => QisutuAdmin->new( Config => $Param{Config}, DB => $Param{DB} ),
        Dynamic    => QisutuDynamicField->new( Config => $Param{Config}, DB => $Param{DB} ),
    };
    bless $Self, $Class;
    return $Self;
}

sub Handle {
    my ( $Self, %Param ) = @_;
    my $Method    = uc( $Param{Method} || 'GET' );
    my $Path      = $Param{Path} || '/v1';
    my $Query     = ref $Param{Query} eq 'HASH' ? $Param{Query} : {};
    my $Body      = ref $Param{Body} eq 'HASH' ? $Param{Body} : {};
    my $Headers   = ref $Param{Headers} eq 'HASH' ? $Param{Headers} : {};
    my $RemoteIP  = $Param{RemoteIP} || '';
    my $RequestID = $Param{RequestID} || '';
    my $Started   = time();

    $Path =~ s{\?.*\z}{};
    $Path =~ s{//+}{/}g;
    $Path = '/' . $Path if $Path !~ m{\A/};
    $Path =~ s{/\z}{} if $Path ne '/';

    if ( $Method eq 'GET' && $Path eq '/v1/ping' ) {
        return $Self->_Finalize(
            Param => \%Param, Started => $Started,
            Result => $Self->_OK( 200, { status => 'ok', version => $Self->{Config}->{System}->{Version} || '' } ),
        );
    }
    if ( $Method eq 'GET' && $Path eq '/v1/openapi.json' ) {
        return $Self->_Finalize(
            Param => \%Param, Started => $Started,
            Result => $Self->_OK( 200, $Self->OpenAPIDocument() ),
        );
    }

    my $PlainToken = $Self->_BearerToken($Headers);
    my $Token = $Self->{Auth}->Authenticate( PlainToken => $PlainToken, RemoteIP => $RemoteIP );
    if (!$Token) {
        my $Code = $Self->{Auth}->Error() || 'invalid_token';
        my $Status = $Code eq 'rate_limit_exceeded' ? 429 : 401;
        $Status = 403 if $Code eq 'ip_not_allowed';
        return $Self->_Finalize(
            Param => \%Param, Started => $Started,
            Result => $Self->_Error( $Status, $Code, $Self->_AuthErrorMessage($Code), $RequestID ),
        );
    }

    my $Result;
    my $IdempotencyKey = $Headers->{'idempotency-key'} || '';
    if ( $Method eq 'POST' && $IdempotencyKey ) {
        if ( $IdempotencyKey !~ m{\A[A-Za-z0-9._:-]{8,190}\z} ) {
            $Result = $Self->_Error( 400, 'invalid_idempotency_key', 'Idempotency-Key must contain 8 to 190 safe characters.', $RequestID );
        }
        else {
            my $RequestHash = sha256_hex( JSON::PP->new->canonical(1)->encode($Body) );
            my $Stored = $Self->{Auth}->IdempotencyGet( TokenID => $Token->{api_token_id}, Key => $IdempotencyKey );
            if ($Stored) {
                if ( $Stored->{method} ne $Method || $Stored->{request_path} ne $Path || $Stored->{request_hash} ne $RequestHash ) {
                    $Result = $Self->_Error( 409, 'idempotency_conflict', 'This Idempotency-Key was already used for a different request.', $RequestID );
                }
                else {
                    my $StoredBody = eval { JSON::PP->new->decode( $Stored->{response_json} ) } || {};
                    $Result = { Status => 0 + $Stored->{status_code}, Body => $StoredBody, ResultCode => 'idempotent_replay' };
                }
            }
            if (!$Result) {
                $Result = $Self->_Route( Method => $Method, Path => $Path, Query => $Query, Body => $Body, Token => $Token, RequestID => $RequestID );
                my $Encoded = JSON::PP->new->canonical(1)->encode( $Result->{Body} || {} );
                $Self->{Auth}->IdempotencyStore(
                    TokenID => $Token->{api_token_id}, Key => $IdempotencyKey,
                    Method => $Method, Path => $Path, RequestHash => $RequestHash,
                    StatusCode => $Result->{Status}, ResponseJSON => $Encoded,
                );
            }
        }
    }
    else {
        $Result = $Self->_Route( Method => $Method, Path => $Path, Query => $Query, Body => $Body, Token => $Token, RequestID => $RequestID );
    }

    $Result->{TokenID} = $Token->{api_token_id};
    $Result->{UserID}  = $Token->{user_account_id};
    return $Self->_Finalize( Param => \%Param, Started => $Started, Result => $Result );
}

sub _Route {
    my ( $Self, %Param ) = @_;
    my $Method = $Param{Method};
    my $Path   = $Param{Path};
    my $Token  = $Param{Token};
    my $Body   = $Param{Body};
    my $Query  = $Param{Query};
    my $RID    = $Param{RequestID};

    if ( $Method eq 'GET' && $Path eq '/v1/me' ) {
        return $Self->_OK( 200, {
            id => 0 + $Token->{user_account_id}, login => $Token->{login}, email => $Token->{email},
            firstname => $Token->{firstname}, lastname => $Token->{lastname}, account_type => $Token->{account_type},
            token_label => $Token->{api_token_label}, scopes => $Token->{scopes},
        } );
    }

    if ( $Path eq '/v1/tickets' && $Method eq 'GET' ) {
        return $Self->_NeedScope( $Token, 'tickets.read', $RID ) || $Self->_TicketList( Query => $Query, Token => $Token, RequestID => $RID );
    }
    if ( $Path eq '/v1/tickets' && $Method eq 'POST' ) {
        return $Self->_NeedScope( $Token, 'tickets.create', $RID ) || $Self->_TicketCreate( Body => $Body, Token => $Token, RequestID => $RID );
    }
    if ( $Path =~ m{\A/v1/tickets/(\d+)\z} ) {
        my $TicketID = $1;
        if ( $Method eq 'GET' ) {
            return $Self->_NeedScope( $Token, 'tickets.read', $RID ) || $Self->_TicketGet( TicketID => $TicketID, Token => $Token, RequestID => $RID );
        }
        if ( $Method eq 'PATCH' ) {
            return $Self->_TicketUpdate( TicketID => $TicketID, Body => $Body, Token => $Token, RequestID => $RID );
        }
    }
    if ( $Path =~ m{\A/v1/tickets/(\d+)/articles\z} ) {
        my $TicketID = $1;
        if ( $Method eq 'GET' ) {
            return $Self->_NeedScope( $Token, 'tickets.read', $RID ) || $Self->_ArticleList( TicketID => $TicketID, Token => $Token, RequestID => $RID );
        }
        if ( $Method eq 'POST' ) {
            return $Self->_NeedScope( $Token, 'tickets.articles', $RID ) || $Self->_ArticleCreate( TicketID => $TicketID, Body => $Body, Token => $Token, RequestID => $RID );
        }
    }
    if ( $Path =~ m{\A/v1/attachments/(\d+)\z} && $Method eq 'GET' ) {
        return $Self->_NeedScope( $Token, 'tickets.attachments', $RID ) || $Self->_AttachmentGet( AttachmentID => $1, Token => $Token, RequestID => $RID );
    }

    if ( $Path =~ m{\A/v1/master-data/(queues|states|priorities|services|slas|dynamic-fields)\z} && $Method eq 'GET' ) {
        return $Self->_NeedScope( $Token, 'master_data.read', $RID ) || $Self->_MasterData( Type => $1, Token => $Token, RequestID => $RID );
    }

    if ( $Path eq '/v1/customers' && $Method eq 'GET' ) {
        return $Self->_NeedScope( $Token, 'customers.read', $RID ) || $Self->_CustomersList( Token => $Token, RequestID => $RID );
    }
    if ( $Path eq '/v1/customers' && $Method eq 'POST' ) {
        return $Self->_NeedScope( $Token, 'customers.write', $RID ) || $Self->_CustomerCreate( Body => $Body, Token => $Token, RequestID => $RID );
    }
    if ( $Path =~ m{\A/v1/customers/(\d+)\z} && $Method eq 'PATCH' ) {
        return $Self->_NeedScope( $Token, 'customers.write', $RID ) || $Self->_CustomerUpdate( CustomerID => $1, Body => $Body, Token => $Token, RequestID => $RID );
    }
    if ( $Path eq '/v1/customer-users' && $Method eq 'GET' ) {
        return $Self->_NeedScope( $Token, 'customers.read', $RID ) || $Self->_CustomerUsersList( Token => $Token, RequestID => $RID );
    }
    if ( $Path eq '/v1/customer-users' && $Method eq 'POST' ) {
        return $Self->_NeedScope( $Token, 'customers.write', $RID ) || $Self->_CustomerUserCreate( Body => $Body, Token => $Token, RequestID => $RID );
    }
    if ( $Path =~ m{\A/v1/customer-users/(\d+)\z} && $Method eq 'PATCH' ) {
        return $Self->_NeedScope( $Token, 'customers.write', $RID ) || $Self->_CustomerUserUpdate( CustomerUserID => $1, Body => $Body, Token => $Token, RequestID => $RID );
    }

    return $Self->_Error( 404, 'not_found', 'The requested API endpoint does not exist.', $RID );
}

sub _TicketList {
    my ( $Self, %Param ) = @_;
    my $Query = $Param{Query};
    my $User  = $Self->_User($Param{Token});
    my $Page = $Self->_Page( $Query->{page} );
    my $PerPage = $Self->_PerPage( $Query->{per_page} );
    my $Search = { Active => 0 };
    if ( defined $Query->{query} && $Query->{query} ne '' ) {
        $Search = { Active => 1, Text => $Query->{query}, Mode => 'all', Scopes => { Ticket => 1, Article => 1 } };
    }
    for my $Pair ( [queue_id=>'QueueIDs'], [state_id=>'StateIDs'], [priority_id=>'PriorityIDs'], [customer_id=>'CustomerIDs'], [customer_user_id=>'CustomerUserIDs'], [owner_user_id=>'OwnerIDs'], [service_id=>'ServiceIDs'] ) {
        if ( $Query->{ $Pair->[0] } && $Query->{ $Pair->[0] } =~ m{\A\d+\z} ) {
            $Search->{Active} = 1;
            $Search->{ $Pair->[1] } = [ 0 + $Query->{ $Pair->[0] } ];
        }
    }
    my %List = (
        User => $User, Limit => $PerPage, Offset => ($Page - 1) * $PerPage,
        Search => $Search, SortBy => $Query->{sort_by} || 'changed', SortDirection => $Query->{sort_direction} || 'desc',
    );
    my $Rows = $Self->{Ticket}->TicketList(%List);
    if ( $Self->{Ticket}->Error() ) {
        return $Self->_ObjectError( $Self->{Ticket}->Error(), $Param{RequestID} );
    }
    my $Total = $Self->{Ticket}->TicketListCount(%List);
    my @Items = map { $Self->_TicketPublic($_) } @{$Rows || []};
    return $Self->_OK( 200, \@Items, { page => $Page, per_page => $PerPage, total => 0 + $Total } );
}

sub _TicketGet {
    my ( $Self, %Param ) = @_;
    my $Ticket = $Self->{Ticket}->TicketGet( TicketID => $Param{TicketID}, User => $Self->_User($Param{Token}) );
    return $Self->_ObjectError( $Self->{Ticket}->Error() || 'Ticket not found', $Param{RequestID} ) if !$Ticket;
    my $Public = $Self->_TicketPublic($Ticket);
    $Public->{dynamic_fields} = $Self->_TicketDynamicValues( $Param{TicketID} );
    return $Self->_OK( 200, $Public );
}

sub _TicketCreate {
    my ( $Self, %Param ) = @_;
    my $Body = $Param{Body};
    my $Token = $Param{Token};
    my $User = $Self->_User($Token);
    for my $Required (qw(queue_id title body)) {
        return $Self->_Error( 422, 'validation_failed', "Required field '$Required' is missing.", $Param{RequestID} ) if !defined $Body->{$Required} || $Body->{$Required} eq '';
    }
    my $Attachments = $Self->_Attachments($Body->{attachments},$Param{RequestID});
    return $Attachments if ref $Attachments eq 'HASH' && $Attachments->{Status};

    my $TicketID;
    if ( ( $User->{account_type} || '' ) eq 'customer' ) {
        $TicketID = $Self->{Ticket}->TicketCreateFromCustomer(
            User => $User, QueueID => $Body->{queue_id}, Title => $Body->{title}, Body => $Body->{body},
            ContentType => $Body->{content_type} || 'text/plain', Attachments => $Attachments,
        );
    }
    else {
        return $Self->_Error( 422, 'validation_failed', "Required field 'customer_user_id' is missing.", $Param{RequestID} ) if !$Body->{customer_user_id};
        my $StateID = $Body->{state_id} || $Self->_DefaultID('state');
        my $PriorityID = $Body->{priority_id} || $Self->_DefaultID('priority');
        my $DynamicRequest = $Self->_DynamicRequest( $Body->{dynamic_fields} );
        $TicketID = $Self->{Ticket}->TicketCreateFromAgent(
            User => $User, QueueID => $Body->{queue_id}, ServiceID => $Body->{service_id},
            CustomerUserID => $Body->{customer_user_id}, OwnerUserID => $Body->{owner_user_id},
            ResponsibleUserID => $Body->{responsible_user_id}, Title => $Body->{title}, Body => $Body->{body},
            ContentType => $Body->{content_type} || 'text/plain', StateID => $StateID, PriorityID => $PriorityID,
            PendingUntil => $Body->{pending_until}, SendEmail => 0, Attachments => $Attachments,
            DynamicFieldRequest => $DynamicRequest, Language => 'en',
        );
    }
    return $Self->_ObjectError( $Self->{Ticket}->Error() || 'Ticket could not be created', $Param{RequestID} ) if !$TicketID;
    my $Result = $Self->_TicketGet( TicketID => $TicketID, Token => $Token, RequestID => $Param{RequestID} );
    $Result->{Status} = 201;
    $Result->{ResourceType} = 'ticket'; $Result->{ResourceID} = $TicketID;
    return $Result;
}

sub _TicketUpdate {
    my ( $Self, %Param ) = @_;
    my $Body = $Param{Body};
    my $Token = $Param{Token};
    my $User = $Self->_User($Token);
    my $RID = $Param{RequestID};
    my $Ticket = $Self->{Ticket}->TicketGet( TicketID => $Param{TicketID}, User => $User );
    return $Self->_ObjectError( $Self->{Ticket}->Error() || 'Ticket not found', $RID ) if !$Ticket;

    my %StatusField = map { $_ => 1 } qw(state_id pending_until);
    my %PropertyField = map { $_ => 1 } qw(priority_id queue_id service_id customer_user_id owner_user_id responsible_user_id);
    return $Self->_Error( 422, 'validation_failed', 'At least one ticket field is required.', $RID ) if !keys %{$Body};
    my @Unknown = grep { !$StatusField{$_} && !$PropertyField{$_} } keys %{$Body};
    return $Self->_Error( 422, 'validation_failed', 'Unsupported ticket fields: ' . join(', ', sort @Unknown), $RID ) if @Unknown;
    return $Self->_Error( 422, 'validation_failed', "Field 'pending_until' requires 'state_id'.", $RID ) if exists $Body->{pending_until} && !exists $Body->{state_id};
    if ( ( exists $Body->{state_id} || exists $Body->{pending_until} ) && !$Self->{Auth}->ScopeAllowed( Token => $Token, Scope => 'tickets.status' ) ) {
        return $Self->_Error( 403, 'scope_missing', 'The token is not permitted to change ticket status.', $RID );
    }
    if ( scalar grep { exists $Body->{$_} } keys %PropertyField ) {
        return $Self->_Error( 403, 'scope_missing', 'The token is not permitted to change ticket properties.', $RID ) if !$Self->{Auth}->ScopeAllowed( Token => $Token, Scope => 'tickets.properties' );
    }
    if ( ( $User->{account_type} || '' ) eq 'agent' ) {
        my $Allowed = $Self->{Permission}->QueueAccessCheck( UserID => $User->{user_account_id}, QueueID => $Ticket->{queue_id}, Permission => 'ticket.edit' );
        return $Self->_Error( 403, 'permission_denied', 'The Qisutu user is not permitted to change this ticket.', $RID ) if !$Allowed;
    }

    my @Changes = (
        [ state_id => 'TicketStatusUpdate', 'StatusID' ],
        [ priority_id => 'TicketPriorityUpdate', 'PriorityID' ],
        [ queue_id => 'TicketQueueUpdate', 'QueueID' ],
        [ service_id => 'TicketServiceUpdate', 'ServiceID' ],
        [ customer_user_id => 'TicketCustomerUserUpdate', 'CustomerUserID' ],
        [ owner_user_id => 'TicketOwnerUpdate', 'OwnerUserID' ],
        [ responsible_user_id => 'TicketResponsibleUpdate', 'ResponsibleUserID' ],
    );
    for my $Change (@Changes) {
        next if !exists $Body->{ $Change->[0] };
        my %Call = (
            TicketID => $Param{TicketID}, User => $User, ChangedByUserID => $User->{user_account_id},
            $Change->[2] => defined $Body->{ $Change->[0] } ? $Body->{ $Change->[0] } : 0,
        );
        $Call{PendingUntil} = $Body->{pending_until} if $Change->[0] eq 'state_id';
        $Call{AllowUnassigned} = 1 if $Change->[0] eq 'owner_user_id' || $Change->[0] eq 'responsible_user_id';
        my $OK = $Self->{Ticket}->can( $Change->[1] )->( $Self->{Ticket}, %Call );
        return $Self->_ObjectError( $Self->{Ticket}->Error() || 'Ticket change failed', $RID ) if !$OK;
    }
    my $Result = $Self->_TicketGet( TicketID => $Param{TicketID}, Token => $Token, RequestID => $RID );
    $Result->{ResourceType} = 'ticket'; $Result->{ResourceID} = $Param{TicketID};
    return $Result;
}

sub _ArticleList {
    my ( $Self, %Param ) = @_;
    my $Rows = $Self->{Ticket}->ArticleList( TicketID => $Param{TicketID}, User => $Self->_User($Param{Token}), Limit => 500 );
    return $Self->_ObjectError( $Self->{Ticket}->Error(), $Param{RequestID} ) if $Self->{Ticket}->Error();
    my @Public;
    for my $A (@{$Rows || []}) {
        push @Public, {
            id => 0 + $A->{id}, ticket_id => 0 + $A->{ticket_id}, article_number => $A->{article_number},
            channel => $A->{channel}, sender_type => $A->{sender_type}, visibility => $A->{visibility},
            from_name => $A->{from_name}, from_email => $A->{from_email}, to_name => $A->{to_name}, to_email => $A->{to_email},
            cc => $A->{cc}, subject => $A->{subject}, body => $A->{body}, content_type => $A->{content_type},
            created_at => $A->{created_at}, attachments => [ map { +{ id=>0+$_->{id}, filename=>$_->{filename}, content_type=>$_->{content_type}, content_size=>0+($_->{content_size}||0) } } @{ $A->{attachments} || [] } ],
        };
    }
    return $Self->_OK( 200, \@Public, { total => scalar @Public } );
}

sub _ArticleCreate {
    my ( $Self, %Param ) = @_;
    my $Body = $Param{Body};
    my $Token = $Param{Token};
    my $User = $Self->_User($Token);
    return $Self->_Error( 422, 'validation_failed', "Required field 'body' is missing.", $Param{RequestID} ) if !defined $Body->{body} || $Body->{body} eq '';
    my $Internal = $Body->{internal} ? 1 : 0;
    if ($Internal && !$Self->{Auth}->ScopeAllowed( Token => $Token, Scope => 'tickets.internal_notes' )) {
        return $Self->_Error( 403, 'scope_missing', 'The token is not permitted to create internal notes.', $Param{RequestID} );
    }
    $Internal = 0 if ( $User->{account_type} || '' ) eq 'customer';
    my $Attachments = $Self->_Attachments($Body->{attachments},$Param{RequestID});
    return $Attachments if ref $Attachments eq 'HASH' && $Attachments->{Status};
    if (@{$Attachments} && !$Self->{Auth}->ScopeAllowed( Token => $Token, Scope => 'tickets.attachments' )) {
        return $Self->_Error( 403, 'scope_missing', 'The token is not permitted to add attachments.', $Param{RequestID} );
    }
    my $ArticleID = $Self->{Ticket}->ArticleCreate(
        TicketID => $Param{TicketID}, User => $User, Subject => $Body->{subject} || '', Body => $Body->{body},
        Channel => 'web', SenderType => ( $User->{account_type} || '' ) eq 'customer' ? 'customer' : 'agent',
        FromName => join(' ', grep {$_} ($User->{firstname},$User->{lastname})), FromEmail => $User->{email},
        ContentType => $Body->{content_type} || 'text/plain', Visibility => $Internal ? 'agent' : 'both',
        Internal => $Internal, CreatedByUserID => $User->{user_account_id}, ChangedByUserID => $User->{user_account_id}, Attachments => $Attachments,
    );
    return $Self->_ObjectError( $Self->{Ticket}->Error() || 'Article could not be created', $Param{RequestID} ) if !$ArticleID;
    my $Result = $Self->_OK( 201, { id => 0 + $ArticleID, ticket_id => 0 + $Param{TicketID} } );
    $Result->{ResourceType} = 'article'; $Result->{ResourceID} = $ArticleID;
    return $Result;
}

sub _AttachmentGet {
    my ( $Self, %Param ) = @_;
    my $A = $Self->{Ticket}->ArticleAttachmentGet( AttachmentID => $Param{AttachmentID}, User => $Self->_User($Param{Token}) );
    return $Self->_ObjectError( $Self->{Ticket}->Error() || 'Attachment not found', $Param{RequestID} ) if !$A;
    return {
        Status => 200, RawBody => $A->{content}, ContentType => $A->{content_type},
        Filename => $A->{filename}, ResultCode => 'ok', ResourceType => 'attachment', ResourceID => $A->{id},
    };
}

sub _MasterData {
    my ( $Self, %Param ) = @_;
    my %SQL = (
        queues => 'SELECT id, name, full_name AS label, active, sort_order FROM ticket_queue WHERE active = 1 ORDER BY sort_order, full_name, id',
        states => 'SELECT id, name AS label, state_type, active, sort_order FROM ticket_state WHERE active = 1 ORDER BY sort_order, name, id',
        priorities => 'SELECT id, name AS label, priority_value, active, sort_order FROM ticket_priority WHERE active = 1 ORDER BY sort_order, priority_value, name, id',
        services => 'SELECT id, name, full_name AS label, active, sort_order FROM service WHERE active = 1 ORDER BY sort_order, full_name, id',
        slas => 'SELECT id, name AS label, service_id, active, sort_order FROM sla WHERE active = 1 ORDER BY sort_order, name, id',
    );
    my $Rows;
    if ( $Param{Type} eq 'dynamic-fields' ) {
        $Rows = $Self->{Dynamic}->FieldList( Language => 'en' );
        for my $Field ( @{$Rows || []} ) {
            $Field->{options} = $Self->{Dynamic}->OptionList( FieldID => $Field->{id} ) || [];
        }
    }
    else {
        $Rows = $Self->{DB}->SelectAll( $SQL{ $Param{Type} } ) || [];
        if ( $Param{Type} eq 'queues' ) {
            my %Allowed = map { $_ => 1 } @{ $Self->{Permission}->QueueIDList( UserID => $Param{Token}->{user_account_id}, Permission => 'ticket.view' ) || [] };
            $Rows = [ grep { $Allowed{ $_->{id} } } @{$Rows} ];
        }
    }
    return $Self->_OK( 200, $Rows, { total => scalar @{$Rows || []} } );
}

sub _CustomersList {
    my ( $Self, %Param ) = @_;
    my $Denied = $Self->_AdminOnly( $Param{Token}, $Param{RequestID} );
    return $Denied if $Denied;
    return $Self->_OK( 200, $Self->{Admin}->CustomerList() || [] );
}
sub _CustomerUsersList {
    my ( $Self, %Param ) = @_;
    my $Denied = $Self->_AdminOnly( $Param{Token}, $Param{RequestID} );
    return $Denied if $Denied;
    return $Self->_OK( 200, $Self->{Admin}->CustomerUserList() || [] );
}
sub _CustomerCreate {
    my ( $Self, %Param ) = @_;
    my $Denied = $Self->_AdminOnly( $Param{Token}, $Param{RequestID} );
    return $Denied if $Denied;
    my $B = $Param{Body};
    my $OK = $Self->{Admin}->CustomerCreate( CustomerNumber => $B->{customer_number}, Name => $B->{name}, ChangedByUserID => $Param{Token}->{user_account_id}, Request => $Self->_CustomerDynamicRequest($B->{dynamic_fields}) );
    return $Self->_ObjectError( $Self->{Admin}->Error(), $Param{RequestID} ) if !$OK;
    my $Row = $Self->{DB}->SelectRow('SELECT id FROM customer WHERE customer_number = ? LIMIT 1',$B->{customer_number});
    my $ID = $Row->{id};
    my $R = $Self->_OK(201,{ id=>0+$ID, customer_number=>$B->{customer_number}, name=>$B->{name} });
    $R->{ResourceType}='customer';$R->{ResourceID}=$ID;return $R;
}
sub _CustomerUpdate {
    my ( $Self, %Param ) = @_;
    my $Denied = $Self->_AdminOnly( $Param{Token}, $Param{RequestID} );
    return $Denied if $Denied;
    my $Existing=$Self->{Admin}->CustomerGet(CustomerID=>$Param{CustomerID});return $Self->_ObjectError($Self->{Admin}->Error(),$Param{RequestID}) if !$Existing;
    my $B=$Param{Body};my $OK=$Self->{Admin}->CustomerUpdate(CustomerID=>$Param{CustomerID},CustomerNumber=>defined$B->{customer_number}?$B->{customer_number}:$Existing->{customer_number},Name=>defined$B->{name}?$B->{name}:$Existing->{name},Active=>exists$B->{active}?$B->{active}:$Existing->{active},ChangedByUserID=>$Param{Token}->{user_account_id},Request=>$Self->_CustomerDynamicRequest($B->{dynamic_fields}));
    return $Self->_ObjectError($Self->{Admin}->Error(),$Param{RequestID}) if !$OK;my $R=$Self->_OK(200,$Self->{Admin}->CustomerGet(CustomerID=>$Param{CustomerID}));$R->{ResourceType}='customer';$R->{ResourceID}=$Param{CustomerID};return $R;
}
sub _CustomerUserCreate {
    my ( $Self, %Param ) = @_;
    my $Denied = $Self->_AdminOnly( $Param{Token}, $Param{RequestID} );
    return $Denied if $Denied;
    my $B=$Param{Body};for my $K(qw(customer_id login email password)){return $Self->_Error(422,'validation_failed',"Required field '$K' is missing.",$Param{RequestID}) if !$B->{$K};}
    return $Self->_Error(422,'validation_failed','password must contain 8 to 128 characters.',$Param{RequestID}) if length($B->{password})<8 || length($B->{password})>128;
    my $OK=$Self->{Admin}->CustomerUserCreate(CustomerID=>$B->{customer_id},Login=>$B->{login},Email=>$B->{email},Password=>$B->{password},Firstname=>$B->{firstname},Lastname=>$B->{lastname},ChangedByUserID=>$Param{Token}->{user_account_id},Request=>$Self->_CustomerUserDynamicRequest($B->{dynamic_fields}));
    return $Self->_ObjectError($Self->{Admin}->Error(),$Param{RequestID}) if !$OK;my $Row=$Self->{DB}->SelectRow('SELECT cu.id FROM customer_user cu INNER JOIN user_account ua ON ua.id=cu.user_account_id WHERE ua.account_type="customer" AND ua.login=? LIMIT 1',$B->{login});my$ID=$Row->{id};my$R=$Self->_OK(201,{id=>0+$ID,login=>$B->{login},email=>$B->{email}});$R->{ResourceType}='customer_user';$R->{ResourceID}=$ID;return$R;
}
sub _CustomerUserUpdate {
    my ( $Self, %Param ) = @_;
    my $Denied = $Self->_AdminOnly( $Param{Token}, $Param{RequestID} );
    return $Denied if $Denied;
    my$E=$Self->{Admin}->CustomerUserGet(CustomerUserID=>$Param{CustomerUserID});return$Self->_ObjectError($Self->{Admin}->Error(),$Param{RequestID})if!$E;my$B=$Param{Body};my$OK=$Self->{Admin}->CustomerUserUpdate(CustomerUserID=>$Param{CustomerUserID},CustomerID=>defined$B->{customer_id}?$B->{customer_id}:$E->{customer_id},Login=>defined$B->{login}?$B->{login}:$E->{login},Email=>defined$B->{email}?$B->{email}:$E->{email},Password=>$B->{password}||'',Firstname=>defined$B->{firstname}?$B->{firstname}:$E->{firstname},Lastname=>defined$B->{lastname}?$B->{lastname}:$E->{lastname},Active=>exists$B->{active}?$B->{active}:$E->{active},ChangedByUserID=>$Param{Token}->{user_account_id},Request=>$Self->_CustomerUserDynamicRequest($B->{dynamic_fields}));return$Self->_ObjectError($Self->{Admin}->Error(),$Param{RequestID})if!$OK;my$R=$Self->_OK(200,$Self->{Admin}->CustomerUserGet(CustomerUserID=>$Param{CustomerUserID}));$R->{ResourceType}='customer_user';$R->{ResourceID}=$Param{CustomerUserID};return$R;
}

sub _TicketPublic {
    my ( $Self, $T ) = @_;
    my %Out;
    for my $K (qw(id ticket_number title queue_id queue_name queue_full_name state_id state_name state_type priority_id priority_name priority_value customer_id customer_name customer_number customer_user_id customer_user_name customer_user_email owner_user_id owner_name responsible_user_id responsible_name service_id service_name sla_id sla_name_display pending_until escalation_state first_response_due_at update_due_at solution_due_at created_at changed_at)) {
        $Out{$K} = $T->{$K};
    }
    for my $K (qw(id queue_id state_id priority_id customer_id customer_user_id owner_user_id responsible_user_id service_id sla_id priority_value)) {
        $Out{$K} = 0 + $Out{$K} if defined $Out{$K} && $Out{$K} ne '';
    }
    return \%Out;
}

sub _TicketDynamicValues {
    my ( $Self, $TicketID ) = @_;
    return $Self->{DB}->SelectAll(
        'SELECT f.id AS field_id, f.name, f.label, f.field_type, v.value_text AS value
         FROM ticket_dynamic_field_value v INNER JOIN ticket_dynamic_field f ON f.id=v.field_id
         WHERE v.ticket_id=? AND f.active=1 ORDER BY f.sort_order,f.id',$TicketID
    ) || [];
}

sub _DynamicRequest {
    my ( $Self, $Values ) = @_;
    my %R;return \%R if ref $Values ne 'HASH';for my $ID(keys%{$Values}){next if$ID!~m{\A\d+\z};$R{'TicketDynamicField_'.$ID}=$Values->{$ID};}return\%R;
}
sub _CustomerDynamicRequest { my($Self,$V)=@_;my%R;return\%R if ref$V ne'HASH';for my$ID(keys%$V){next if$ID!~m{\A\d+\z};$R{'CustomerDynamicField_'.$ID}=$V->{$ID};}return\%R; }
sub _CustomerUserDynamicRequest { my($Self,$V)=@_;my%R;return\%R if ref$V ne'HASH';for my$ID(keys%$V){next if$ID!~m{\A\d+\z};$R{'CustomerUserDynamicField_'.$ID}=$V->{$ID};}return\%R; }

sub _Attachments {
    my ( $Self, $Items, $RID ) = @_;
    return [] if !$Items;return $Self->_Error(422,'validation_failed','attachments must be an array.',$RID) if ref$Items ne'ARRAY';my@A;
    for my$I(@{$Items}){return$Self->_Error(422,'validation_failed','Each attachment needs filename and content_base64.',$RID)if ref$I ne'HASH'||!$I->{filename}||!defined$I->{content_base64};my$Encoded=$I->{content_base64};$Encoded=~s{\s+}{}g;return$Self->_Error(422,'validation_failed','Attachment content is not valid base64.',$RID)if$Encoded!~m{\A(?:[A-Za-z0-9+/]{4})*(?:[A-Za-z0-9+/]{2}==|[A-Za-z0-9+/]{3}=)?\z};my$C=decode_base64($Encoded);push@A,{Filename=>$I->{filename},ContentType=>$I->{content_type}||'application/octet-stream',Content=>$C,ContentSize=>length($C)};}return\@A;
}
sub _DefaultID { my($Self,$Type)=@_;my($Table,$Order)=$Type eq'state'?('ticket_state','sort_order, id'):('ticket_priority','ABS(priority_value-3), sort_order, id');my$R=$Self->{DB}->SelectRow("SELECT id FROM $Table WHERE active=1 ORDER BY $Order LIMIT 1");return$R->{id}||0; }
sub _User { my($Self,$T)=@_;return{user_account_id=>$T->{user_account_id},login=>$T->{login},email=>$T->{email},firstname=>$T->{firstname},lastname=>$T->{lastname},account_type=>$T->{account_type},customer_user_id=>$T->{customer_user_id},customer_id=>$T->{customer_id}}; }
sub _AdminOnly { my($Self,$T,$RID)=@_;return if$Self->{Permission}->UserIsAdmin(UserID=>$T->{user_account_id});return$Self->_Error(403,'permission_denied','Customer master data requires an administrator user.',$RID); }
sub _NeedScope { my($Self,$T,$S,$RID)=@_;return if$Self->{Auth}->ScopeAllowed(Token=>$T,Scope=>$S);return$Self->_Error(403,'scope_missing',"The token is missing permission '$S'.",$RID); }
sub _Page { my($Self,$V)=@_;return$V&&$V=~m{\A\d+\z}&&$V>0?int$V:1; }
sub _PerPage { my($Self,$V)=@_;$V=$V&&$V=~m{\A\d+\z}?int$V:50;$V=1 if$V<1;$V=100 if$V>100;return$V; }
sub _ObjectError { my($Self,$E,$RID)=@_;my$Status=$E=~m{denied}i?403:$E=~m{not found|was not found}i?404:422;return$Self->_Error($Status,$Status==403?'permission_denied':$Status==404?'not_found':'validation_failed',$E||'The request could not be processed.',$RID); }
sub _OK { my($Self,$Status,$Data,$Meta)=@_;my$B={data=>$Data};$B->{meta}=$Meta if$Meta;return{Status=>$Status,Body=>$B,ResultCode=>'ok'}; }
sub _Error { my($Self,$Status,$Code,$Message,$RID)=@_;return{Status=>$Status,Body=>{error=>{code=>$Code,message=>$Message,request_id=>$RID||''}},ResultCode=>$Code}; }
sub _BearerToken { my($Self,$H)=@_;my$A=$H->{authorization}||'';return$1 if$A=~m{\ABearer\s+(\S+)\s*\z}i;return$H->{'x-qisutu-api-token'}||''; }
sub _AuthErrorMessage { my($Self,$C)=@_;return'The request rate limit has been exceeded.'if$C eq'rate_limit_exceeded';return'This token may not be used from the current IP address.'if$C eq'ip_not_allowed';return'The API token is missing, invalid, expired or inactive.'; }

sub _Finalize {
    my ( $Self, %Param ) = @_;
    my $P=$Param{Param};my$R=$Param{Result};my$MS=int((time()-$Param{Started})*1000);
    $Self->{Auth}->RequestLogCreate(RequestID=>$P->{RequestID},TokenID=>$R->{TokenID},UserID=>$R->{UserID},Method=>$P->{Method},Path=>$P->{Path},StatusCode=>$R->{Status},RemoteIP=>$P->{RemoteIP},DurationMS=>$MS,ResultCode=>$R->{ResultCode},ResourceType=>$R->{ResourceType},ResourceID=>$R->{ResourceID});return$R;
}

sub OpenAPIDocument {
    my ($Self)=@_;
    my $Base=($Self->{Config}->{System}->{WebPath}||'/qisutu').'/api.pl/v1';
    return {openapi=>'3.0.3',info=>{title=>'Qisutu REST API',version=>'1.0.0',description=>'Local, versioned REST API. Bearer tokens are created by a Qisutu administrator.'},servers=>[{url=>$Base}],security=>[{bearerAuth=>[]}],paths=>{
        '/ping'=>{get=>{security=>[],summary=>'Health check'}},'/me'=>{get=>{summary=>'Current API identity'}},
        '/tickets'=>{get=>{summary=>'List accessible tickets'},post=>{summary=>'Create a ticket'}},
        '/tickets/{ticket_id}'=>{get=>{summary=>'Read a ticket'},patch=>{summary=>'Change status, queue, priority, service or assignment'}},
        '/tickets/{ticket_id}/articles'=>{get=>{summary=>'List ticket articles'},post=>{summary=>'Add a reply or internal note'}},
        '/attachments/{attachment_id}'=>{get=>{summary=>'Download an attachment'}},
        '/master-data/{type}'=>{get=>{summary=>'Read queues, states, priorities, services, SLAs or dynamic fields'}},
        '/customers'=>{get=>{summary=>'List customers'},post=>{summary=>'Create a customer'}},
        '/customer-users'=>{get=>{summary=>'List customer users'},post=>{summary=>'Create a customer user'}},
    },components=>{securitySchemes=>{bearerAuth=>{type=>'http',scheme=>'bearer',bearerFormat=>'Qisutu API token'}}}};
}

1;
