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

package AgentInternalChat;

use strict;
use warnings;
use utf8;

use JSON::PP qw(encode_json);
use QisutuInternalChat;

sub new {
    my ( $Class, %Param ) = @_;

    my $Self = {
        Config  => $Param{Config} || {},
        DB      => $Param{DB},
        Output  => $Param{Output},
        Program => $Param{Program} || {},
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
    my $UserID   = $User->{user_account_id} || 0;
    my $Chat     = QisutuInternalChat->new( Config => $Self->{Config}, DB => $Self->{DB} );

    if ( ( $User->{account_type} || '' ) ne 'agent' || !$UserID ) {
        return $Self->_JSON( Status => '403 Forbidden', Data => {
            success => 0,
            message => $Self->_Translate( Key => 'InternalChatAccessDenied', Language => $Language ),
        });
    }

    if ( $Step eq 'State' ) {
        my $Agents = $Chat->AgentList( UserID => $UserID );
        my $UnreadCount = $Chat->UnreadCount( UserID => $UserID );
        return $Self->_ChatResult(
            Chat     => $Chat,
            Language => $Language,
            Data     => {
                agents       => $Agents || [],
                unread_count => $UnreadCount,
            },
            Success => $Chat->Error() ? 0 : 1,
        );
    }

    if ( $Step eq 'Unread' ) {
        my $UnreadCount = $Chat->UnreadCount( UserID => $UserID );
        return $Self->_ChatResult(
            Chat     => $Chat,
            Language => $Language,
            Data     => { unread_count => $UnreadCount },
            Success  => $Chat->Error() ? 0 : 1,
        );
    }

    if ( $Step eq 'Messages' ) {
        my $Messages = $Chat->MessageList(
            UserID    => $UserID,
            PartnerID => $Request->{PartnerID},
            SinceID   => $Request->{SinceID},
        );
        return $Self->_ChatResult(
            Chat     => $Chat,
            Language => $Language,
            Data     => {
                messages    => $Messages || [],
                unread_count => $Chat->UnreadCount( UserID => $UserID ),
            },
            Success => defined $Messages ? 1 : 0,
        );
    }

    if ( $Step eq 'Send' ) {
        my $MessageID = $Chat->MessageCreate(
            User      => $User,
            PartnerID => $Request->{PartnerID},
            TicketID  => $Request->{TicketID},
            Text      => $Request->{Message},
        );
        return $Self->_ChatResult(
            Chat     => $Chat,
            Language => $Language,
            Data     => { message_id => 0 + ( $MessageID || 0 ) },
            Success  => $MessageID ? 1 : 0,
        );
    }

    if ( $Step eq 'Delete' ) {
        my $MessageID = $Chat->ConversationDelete(
            UserID    => $UserID,
            PartnerID => $Request->{PartnerID},
        );
        return $Self->_ChatResult(
            Chat     => $Chat,
            Language => $Language,
            Data     => {
                message_id => 0 + ( $MessageID || 0 ),
                message    => $MessageID
                    ? $Self->_Translate( Key => 'InternalChatDeleteSuccess', Language => $Language )
                    : '',
            },
            Success => $MessageID ? 1 : 0,
        );
    }

    if ( $Step eq 'Transfer' ) {
        my $Result = $Chat->TicketTransfer(
            User        => $User,
            PartnerID   => $Request->{PartnerID},
            TicketID    => $Request->{TicketID},
            Language    => $Language,
            NoteSubject => $Self->_Translate(
                Key      => 'InternalChatTransferNoteSubject',
                Language => $Language,
            ),
            NoteBody => $Self->_Translate(
                Key      => 'InternalChatTransferNoteBody',
                Language => $Language,
            ),
        );
        return $Self->_ChatResult(
            Chat     => $Chat,
            Language => $Language,
            Data     => {
                transfer => $Result || {},
                message  => $Result
                    ? $Self->_Translate( Key => 'InternalChatTransferSuccess', Language => $Language )
                    : '',
            },
            Success => $Result ? 1 : 0,
        );
    }

    if ( $Step eq 'TicketPresence' ) {
        my $Agents = $Chat->TicketPresenceUpdate(
            User     => $User,
            TicketID => $Request->{TicketID},
            ClientID => $Request->{ClientID},
        );
        return $Self->_ChatResult(
            Chat     => $Chat,
            Language => $Language,
            Data     => { agents => $Agents || [] },
            Success  => defined $Agents ? 1 : 0,
        );
    }

    if ( $Step eq 'TicketPresenceLeave' ) {
        my $Success = $Chat->TicketPresenceLeave(
            User     => $User,
            TicketID => $Request->{TicketID},
            ClientID => $Request->{ClientID},
        );
        return $Self->_JSON( Data => { success => $Success ? 1 : 0 } );
    }

    return $Self->_JSON( Status => '400 Bad Request', Data => {
        success => 0,
        message => $Self->_Translate( Key => 'InternalChatRequestInvalid', Language => $Language ),
    });
}

sub _ChatResult {
    my ( $Self, %Param ) = @_;

    my $Success = $Param{Success} ? 1 : 0;
    my %Data = (
        success => $Success,
        %{ $Param{Data} || {} },
    );

    if ( !$Success ) {
        my $Error = $Param{Chat} ? $Param{Chat}->Error() : '';
        $Error =~ s{\ATranslate:}{};
        $Data{message} = $Self->_Translate(
            Key      => $Error || 'InternalChatRequestFailed',
            Language => $Param{Language} || 'en',
        );
    }

    return $Self->_JSON( Data => \%Data );
}

sub _Translate {
    my ( $Self, %Param ) = @_;

    return $Self->{Output}->Translate(
        Key      => $Param{Key} || 'InternalChatRequestFailed',
        Language => $Param{Language} || 'en',
    );
}

sub _JSON {
    my ( $Self, %Param ) = @_;

    return {
        Response => $Self->{Output}->Response(
            Status      => $Param{Status} || '200 OK',
            ContentType => 'application/json; charset=UTF-8',
            Headers     => [ 'Cache-Control: no-store' ],
            Body        => encode_json( $Param{Data} || {} ),
        ),
    };
}

1;
