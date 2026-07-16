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

package QisutuMail;

use strict;
use warnings;
use utf8;

use Encode qw(decode encode);
use IO::Socket::INET;
use MIME::Base64 qw(decode_base64 encode_base64);
use MIME::QuotedPrint qw(decode_qp encode_qp);
use Net::SMTP;
use POSIX qw(strftime);
use QisutuHTML;
use QisutuSystemSetting;

sub new {
    my ( $Class, %Param ) = @_;

    my $Self = {
        Config    => $Param{Config},
        DB        => $Param{DB},
        LastError => '',
    };

    bless $Self, $Class;

    return $Self;
}

sub SMTPTest {
    my ( $Self, %Param ) = @_;

    my $Account = $Param{Account} || {};

    if ( exists $Account->{outbound_enabled} && !$Account->{outbound_enabled} ) {
        return $Self->_Result( Success => 0, Message => 'Translate:AdminSMTPDisabled' );
    }

    if ( ( $Self->_AccountValue( Account => $Account, Prefix => 'smtp', Key => 'auth_type' ) || 'password' ) eq 'oauth2' ) {
        return $Self->_Result( Success => 0, Message => 'Translate:AdminOAuth2FlowMissing' );
    }

    my $Host     = $Self->_AccountValue( Account => $Account, Prefix => 'smtp', Key => 'host' ) || '';
    my $Security = $Self->_AccountValue( Account => $Account, Prefix => 'smtp', Key => 'security' ) || 'smtp_starttls';
    my $Port     = $Self->_AccountValue( Account => $Account, Prefix => 'smtp', Key => 'port' ) || $Self->_DefaultPort($Security);

    if ( !$Host ) {
        return $Self->_Result( Success => 0, Message => 'Translate:AdminSMTPHostRequired' );
    }

    if ( $Security eq 'smtp_starttls' || $Security eq 'smtps' ) {
        return $Self->_Result( Success => 0, Message => 'Translate:AdminSMTPSSLRequired' )
            if !$Self->_SSLAvailable();
    }

    my %SMTPParam = (
        Port    => $Port,
        Timeout => 15,
        Hello   => 'qisutu.local',
    );

    if ( $Security eq 'smtps' ) {
        $SMTPParam{SSL} = 1;
    }

    my $SMTP = Net::SMTP->new( $Host, %SMTPParam );

    if ( !$SMTP ) {
        return $Self->_Result( Success => 0, Message => 'Translate:AdminSMTPConnectionFailed' );
    }

    if ( $Security eq 'smtp_starttls' ) {
        if ( !$SMTP->can('starttls') || !$SMTP->starttls() ) {
            my $Message = $SMTP->message() || 'Translate:AdminSMTPSTARTTLSFailed';
            $SMTP->quit();
            return $Self->_Result( Success => 0, Message => $Message );
        }
    }

    my $AuthType = $Self->_AccountValue( Account => $Account, Prefix => 'smtp', Key => 'auth_type' ) || 'password';
    my $Username = $Self->_AccountValue( Account => $Account, Prefix => 'smtp', Key => 'username' ) || '';
    my $Password = $Self->_AccountValue( Account => $Account, Prefix => 'smtp', Key => 'password' ) || '';

    if ( $AuthType eq 'password' && ( !$Username || !$Password ) ) {
        $SMTP->quit();
        return $Self->_Result( Success => 0, Message => 'Translate:AdminSMTPCredentialsRequired' );
    }

    if ($Username) {
        if ( !$SMTP->auth( $Username, $Password ) ) {
            my $Message = $SMTP->message() || 'Translate:AdminSMTPAuthFailed';
            $SMTP->quit();
            return $Self->_Result( Success => 0, Message => $Message );
        }
    }

    $SMTP->quit();

    return $Self->_Result( Success => 1, Message => 'Translate:AdminSMTPConnectionOK' );
}

sub SMTPSend {
    my ( $Self, %Param ) = @_;

    my $Account      = $Param{Account} || {};
    my $FromName     = $Self->_HeaderValueClean( $Param{FromName}  || '' );
    my $FromEmail    = $Self->_EmailClean( $Param{FromEmail} || '' );
    my $ToName       = $Self->_HeaderValueClean( $Param{ToName}    || '' );
    my @ToEmails     = $Self->_EmailListClean( $Param{ToEmail} || '' );
    my @CcEmails     = $Self->_EmailListClean( $Param{Cc} || $Param{CC} || '' );
    my $ToEmail      = @ToEmails ? $ToEmails[0] : '';
    my $ReplyToName  = $Self->_HeaderValueClean( $Param{ReplyToName}  || '' );
    my $ReplyToEmail = $Self->_EmailClean( $Param{ReplyToEmail} || '' );
    my $EnvelopeFrom = $Self->_EmailClean( $Param{EnvelopeFrom} || $FromEmail );
    my $Subject      = $Self->_HeaderValueClean( $Param{Subject} || '' );
    my $Body         = $Param{Body} || '';
    my $PlainBody    = defined $Param{PlainBody} ? $Param{PlainBody} : '';
    my $InlineImages = ref $Param{InlineImages} eq 'ARRAY' ? $Param{InlineImages} : [];
    my $Attachments  = ref $Param{Attachments}  eq 'ARRAY' ? $Param{Attachments}  : [];

    my $AttachmentCheck = $Self->_AttachmentListLimitApply( Attachments => $Attachments );
    if ( @{ $AttachmentCheck->{Rejected} || [] } ) {
        my $Rejected = $AttachmentCheck->{Rejected}->[0] || {};
        return $Self->_Result(
            Success => 0,
            Message => $Self->_AttachmentTooLargeMessage( Attachment => $Rejected ),
        );
    }
    $Attachments = $AttachmentCheck->{Allowed};

    if ( exists $Account->{active} && !$Account->{active} ) {
        return $Self->_Result( Success => 0, Message => 'Translate:AdminSMTPDisabled' );
    }

    if ( ( $Self->_AccountValue( Account => $Account, Prefix => 'smtp', Key => 'auth_type' ) || 'password' ) eq 'oauth2' ) {
        return $Self->_Result( Success => 0, Message => 'Translate:AdminOAuth2FlowMissing' );
    }

    if ( !$FromEmail || !$ToEmail || !$EnvelopeFrom ) {
        return $Self->_Result( Success => 0, Message => 'SMTP sender and recipient are required' );
    }

    my $Host     = $Self->_AccountValue( Account => $Account, Prefix => 'smtp', Key => 'host' ) || '';
    my $Security = $Self->_AccountValue( Account => $Account, Prefix => 'smtp', Key => 'security' ) || 'smtp_starttls';
    my $Port     = $Self->_AccountValue( Account => $Account, Prefix => 'smtp', Key => 'port' ) || $Self->_DefaultPort($Security);

    if ( !$Host ) {
        return $Self->_Result( Success => 0, Message => 'Translate:AdminSMTPHostRequired' );
    }

    if ( $Security eq 'smtp_starttls' || $Security eq 'smtps' ) {
        return $Self->_Result( Success => 0, Message => 'Translate:AdminSMTPSSLRequired' )
            if !$Self->_SSLAvailable();
    }

    my %SMTPParam = (
        Port    => $Port,
        Timeout => 15,
        Hello   => 'qisutu.local',
    );

    if ( $Security eq 'smtps' ) {
        $SMTPParam{SSL} = 1;
    }

    my $SMTP = Net::SMTP->new( $Host, %SMTPParam );

    if ( !$SMTP ) {
        return $Self->_Result( Success => 0, Message => 'Translate:AdminSMTPConnectionFailed' );
    }

    if ( $Security eq 'smtp_starttls' ) {
        if ( !$SMTP->can('starttls') || !$SMTP->starttls() ) {
            my $Message = $SMTP->message() || 'Translate:AdminSMTPSTARTTLSFailed';
            $SMTP->quit();
            return $Self->_Result( Success => 0, Message => $Message );
        }
    }

    my $Username = $Self->_AccountValue( Account => $Account, Prefix => 'smtp', Key => 'username' ) || '';
    my $Password = $Self->_AccountValue( Account => $Account, Prefix => 'smtp', Key => 'password' ) || '';
    my $AuthType = $Self->_AccountValue( Account => $Account, Prefix => 'smtp', Key => 'auth_type' ) || 'password';

    if ( $AuthType eq 'password' && ( !$Username || !$Password ) ) {
        $SMTP->quit();
        return $Self->_Result( Success => 0, Message => 'Translate:AdminSMTPCredentialsRequired' );
    }

    if ($Username) {
        if ( !$SMTP->auth( $Username, $Password ) ) {
            my $Message = $SMTP->message() || 'Translate:AdminSMTPAuthFailed';
            $SMTP->quit();
            return $Self->_Result( Success => 0, Message => $Message );
        }
    }

    my $Message = $Self->_SMTPMessageBuild(
        FromName  => $FromName,
        FromEmail => $FromEmail,
        ToName    => $ToName,
        ToEmail   => join( ', ', @ToEmails ),
        Cc        => join( ', ', @CcEmails ),
        Subject      => $Subject,
        Body         => $Body,
        PlainBody    => $PlainBody,
        ReplyToName  => $ReplyToName,
        ReplyToEmail => $ReplyToEmail,
        InlineImages => $InlineImages,
        Attachments  => $Attachments,
    );

    my @EnvelopeRecipients = ( @ToEmails, @CcEmails );

    if (
        !$SMTP->mail($EnvelopeFrom)
        || !$SMTP->to(@EnvelopeRecipients)
        || !$SMTP->data()
    ) {
        my $MessageText = $SMTP->message() || 'SMTP envelope could not be prepared';
        $SMTP->quit();
        return $Self->_Result( Success => 0, Message => $MessageText );
    }

    $SMTP->datasend($Message);

    if ( !$SMTP->dataend() ) {
        my $MessageText = $SMTP->message() || 'SMTP message could not be sent';
        $SMTP->quit();
        return $Self->_Result( Success => 0, Message => $MessageText );
    }

    $SMTP->quit();

    return $Self->_Result( Success => 1, Message => 'SMTP message sent' );
}

sub IMAPTest {
    my ( $Self, %Param ) = @_;

    my $Account = $Param{Account} || {};

    if ( exists $Account->{inbound_enabled} && !$Account->{inbound_enabled} ) {
        return $Self->_Result( Success => 0, Message => 'Translate:AdminIMAPDisabled' );
    }

    if ( ( $Self->_AccountValue( Account => $Account, Prefix => 'imap', Key => 'auth_type' ) || 'password' ) eq 'oauth2' ) {
        return $Self->_Result( Success => 0, Message => 'Translate:AdminOAuth2FlowMissing' );
    }

    my $Host     = $Self->_AccountValue( Account => $Account, Prefix => 'imap', Key => 'host' ) || '';
    my $Security = $Self->_AccountValue( Account => $Account, Prefix => 'imap', Key => 'security' ) || 'imap_starttls';
    my $Port     = $Self->_AccountValue( Account => $Account, Prefix => 'imap', Key => 'port' ) || $Self->_DefaultPort($Security);

    if ( !$Host ) {
        return $Self->_Result( Success => 0, Message => 'Translate:AdminIMAPHostRequired' );
    }

    if ( $Security eq 'imap_starttls' || $Security eq 'imaps' ) {
        return $Self->_Result( Success => 0, Message => 'Translate:AdminIMAPSSLRequired' )
            if !$Self->_SSLAvailable();
    }

    my $Socket = $Self->_IMAPSocket(
        Host     => $Host,
        Port     => $Port,
        Security => $Security,
    );

    return $Socket if ref $Socket eq 'HASH';

    my $Greeting = $Self->_IMAPRead( Socket => $Socket );
    if ( $Greeting !~ m{\A\*\s+OK}i ) {
        $Self->_SocketClose($Socket);
        return $Self->_Result( Success => 0, Message => 'Translate:AdminIMAPGreetingFailed' );
    }

    if ( $Security eq 'imap_starttls' ) {
        my $StartTLS = $Self->_IMAPCommand(
            Socket  => $Socket,
            Tag     => 'A001',
            Command => 'STARTTLS',
        );

        if ( $StartTLS !~ m{A001\s+OK}i ) {
            $Self->_SocketClose($Socket);
            return $Self->_Result( Success => 0, Message => 'Translate:AdminIMAPSTARTTLSFailed' );
        }

        my $SSLStarted = IO::Socket::SSL->start_SSL(
            $Socket,
            SSL_hostname => $Host,
        );

        if ( !$SSLStarted ) {
            $Self->_SocketClose($Socket);
            return $Self->_Result( Success => 0, Message => 'Translate:AdminIMAPTLSHandshakeFailed' );
        }
    }

    my $Username = $Self->_AccountValue( Account => $Account, Prefix => 'imap', Key => 'username' ) || '';
    my $Password = $Self->_AccountValue( Account => $Account, Prefix => 'imap', Key => 'password' ) || '';

    if ( !$Username || !$Password ) {
        $Self->_IMAPCommand(
            Socket  => $Socket,
            Tag     => 'A003',
            Command => 'LOGOUT',
        );
        $Self->_SocketClose($Socket);
        return $Self->_Result( Success => 0, Message => 'Translate:AdminIMAPCredentialsRequired' );
    }

    my $Login = $Self->_IMAPCommand(
        Socket  => $Socket,
        Tag     => 'A002',
        Command => 'LOGIN '
            . $Self->_IMAPQuote($Username)
            . ' '
            . $Self->_IMAPQuote($Password),
    );

    if ( $Login !~ m{A002\s+OK}i ) {
        $Self->_IMAPCommand(
            Socket  => $Socket,
            Tag     => 'A003',
            Command => 'LOGOUT',
        );
        $Self->_SocketClose($Socket);
        return $Self->_Result( Success => 0, Message => 'Translate:AdminIMAPAuthFailed' );
    }

    my $List = $Self->_IMAPCommand(
        Socket  => $Socket,
        Tag     => 'A004',
        Command => 'LIST "" "*"',
    );

    $Self->_IMAPCommand(
        Socket  => $Socket,
        Tag     => 'A005',
        Command => 'LOGOUT',
    );
    $Self->_SocketClose($Socket);

    if ( $List !~ m{A004\s+OK}i ) {
        return $Self->_Result( Success => 0, Message => 'Translate:AdminIMAPFolderListFailed' );
    }

    return $Self->_Result( Success => 1, Message => 'Translate:AdminIMAPConnectionOK' );
}

sub IMAPFetchNewMessages {
    my ( $Self, %Param ) = @_;

    my $Account = $Param{Account} || {};
    my $Limit   = $Param{Limit} || 20;

    if ( $Limit !~ m{\A\d+\z} || $Limit < 1 ) {
        $Limit = 20;
    }

    if ( $Limit > 100 ) {
        $Limit = 100;
    }

    if ( exists $Account->{inbound_enabled} && !$Account->{inbound_enabled} ) {
        return $Self->_Result( Success => 0, Message => 'Translate:AdminIMAPDisabled' );
    }

    if ( ( $Self->_AccountValue( Account => $Account, Prefix => 'imap', Key => 'auth_type' ) || 'password' ) eq 'oauth2' ) {
        return $Self->_Result( Success => 0, Message => 'Translate:AdminOAuth2FlowMissing' );
    }

    my $Session = $Self->_IMAPLoginSession( Account => $Account );
    return $Session if ref $Session ne 'HASH' || !$Session->{Socket};

    my $Socket = $Session->{Socket};
    my $Select = $Self->_IMAPCommand(
        Socket  => $Socket,
        Tag     => 'A003',
        Command => 'SELECT "INBOX"',
    );

    if ( $Select !~ m{A003\s+OK}i ) {
        $Self->_IMAPLogout( Socket => $Socket, Tag => 'A004' );
        return $Self->_Result( Success => 0, Message => 'Translate:AdminIMAPFolderSelectFailed' );
    }

    my $Search = $Self->_IMAPCommand(
        Socket  => $Socket,
        Tag     => 'A005',
        Command => 'UID SEARCH UNSEEN',
    );

    if ( $Search !~ m{A005\s+OK}i ) {
        $Self->_IMAPLogout( Socket => $Socket, Tag => 'A006' );
        return $Self->_Result( Success => 0, Message => 'Translate:AdminIMAPSearchFailed' );
    }

    my @UIDs = $Search =~ m{\*\s+SEARCH\s+([0-9 ]*)}i ? split m{\s+}, $1 : ();
    @UIDs = grep { $_ && $_ =~ m{\A\d+\z} } @UIDs;

    if ( @UIDs > $Limit ) {
        @UIDs = @UIDs[ 0 .. $Limit - 1 ];
    }

    my @Messages;
    my $TagCounter = 7;

    for my $UID (@UIDs) {
        my $Tag = 'A' . sprintf '%03d', $TagCounter++;
        my $Fetch = $Self->_IMAPCommand(
            Socket  => $Socket,
            Tag     => $Tag,
            Command => 'UID FETCH ' . $UID . ' BODY.PEEK[]',
        );

        next if $Fetch !~ m{\Q$Tag\E\s+OK}i;

        my $RawMessage = $Self->_IMAPFetchBody($Fetch);
        next if !$RawMessage;

        my $Message = $Self->_MessageParse($RawMessage);
        $Message->{uid} = $UID;
        push @Messages, $Message;
    }

    $Self->_IMAPLogout( Socket => $Socket, Tag => 'A' . sprintf '%03d', $TagCounter );

    return {
        Success  => 1,
        Status   => 'ok',
        Message  => 'Messages fetched',
        Messages => \@Messages,
    };
}

sub IMAPDeleteMessage {
    my ( $Self, %Param ) = @_;

    my $Account = $Param{Account} || {};
    my $UID     = $Param{UID} || 0;

    if ( $UID !~ m{\A\d+\z} || !$UID ) {
        return $Self->_Result( Success => 0, Message => 'Valid IMAP UID is required' );
    }

    my $Session = $Self->_IMAPLoginSession( Account => $Account );
    return $Session if ref $Session ne 'HASH' || !$Session->{Socket};

    my $Socket = $Session->{Socket};
    my $Select = $Self->_IMAPCommand(
        Socket  => $Socket,
        Tag     => 'A003',
        Command => 'SELECT "INBOX"',
    );

    if ( $Select !~ m{A003\s+OK}i ) {
        $Self->_IMAPLogout( Socket => $Socket, Tag => 'A004' );
        return $Self->_Result( Success => 0, Message => 'Translate:AdminIMAPFolderSelectFailed' );
    }

    my $Store = $Self->_IMAPCommand(
        Socket  => $Socket,
        Tag     => 'A005',
        Command => 'UID STORE ' . $UID . ' +FLAGS.SILENT (\Deleted)',
    );

    my $Expunge = $Self->_IMAPCommand(
        Socket  => $Socket,
        Tag     => 'A006',
        Command => 'EXPUNGE',
    );

    $Self->_IMAPLogout( Socket => $Socket, Tag => 'A007' );

    if ( $Store !~ m{A005\s+OK}i ) {
        return $Self->_Result( Success => 0, Message => 'Translate:AdminIMAPDeleteFailed' );
    }

    if ( $Expunge !~ m{A006\s+OK}i ) {
        return $Self->_Result( Success => 0, Message => 'Translate:AdminIMAPExpungeFailed' );
    }

    return $Self->_Result( Success => 1, Message => 'Message deleted' );
}

sub _IMAPLoginSession {
    my ( $Self, %Param ) = @_;

    my $Account  = $Param{Account} || {};
    my $Host     = $Self->_AccountValue( Account => $Account, Prefix => 'imap', Key => 'host' ) || '';
    my $Security = $Self->_AccountValue( Account => $Account, Prefix => 'imap', Key => 'security' ) || 'imap_starttls';
    my $Port     = $Self->_AccountValue( Account => $Account, Prefix => 'imap', Key => 'port' ) || $Self->_DefaultPort($Security);

    if ( !$Host ) {
        return $Self->_Result( Success => 0, Message => 'Translate:AdminIMAPHostRequired' );
    }

    if ( $Security eq 'imap_starttls' || $Security eq 'imaps' ) {
        return $Self->_Result( Success => 0, Message => 'Translate:AdminIMAPSSLRequired' )
            if !$Self->_SSLAvailable();
    }

    my $Socket = $Self->_IMAPSocket(
        Host     => $Host,
        Port     => $Port,
        Security => $Security,
    );

    return $Socket if ref $Socket eq 'HASH';

    my $Greeting = $Self->_IMAPRead( Socket => $Socket );
    if ( $Greeting !~ m{\A\*\s+OK}i ) {
        $Self->_SocketClose($Socket);
        return $Self->_Result( Success => 0, Message => 'Translate:AdminIMAPGreetingFailed' );
    }

    if ( $Security eq 'imap_starttls' ) {
        my $StartTLS = $Self->_IMAPCommand(
            Socket  => $Socket,
            Tag     => 'A001',
            Command => 'STARTTLS',
        );

        if ( $StartTLS !~ m{A001\s+OK}i ) {
            $Self->_SocketClose($Socket);
            return $Self->_Result( Success => 0, Message => 'Translate:AdminIMAPSTARTTLSFailed' );
        }

        my $SSLStarted = IO::Socket::SSL->start_SSL(
            $Socket,
            SSL_hostname => $Host,
        );

        if ( !$SSLStarted ) {
            $Self->_SocketClose($Socket);
            return $Self->_Result( Success => 0, Message => 'Translate:AdminIMAPTLSHandshakeFailed' );
        }
    }

    my $Username = $Self->_AccountValue( Account => $Account, Prefix => 'imap', Key => 'username' ) || '';
    my $Password = $Self->_AccountValue( Account => $Account, Prefix => 'imap', Key => 'password' ) || '';

    if ( !$Username || !$Password ) {
        $Self->_IMAPCommand(
            Socket  => $Socket,
            Tag     => 'A003',
            Command => 'LOGOUT',
        );
        $Self->_SocketClose($Socket);
        return $Self->_Result( Success => 0, Message => 'Translate:AdminIMAPCredentialsRequired' );
    }

    my $Login = $Self->_IMAPCommand(
        Socket  => $Socket,
        Tag     => 'A002',
        Command => 'LOGIN '
            . $Self->_IMAPQuote($Username)
            . ' '
            . $Self->_IMAPQuote($Password),
    );

    if ( $Login !~ m{A002\s+OK}i ) {
        $Self->_IMAPCommand(
            Socket  => $Socket,
            Tag     => 'A003',
            Command => 'LOGOUT',
        );
        $Self->_SocketClose($Socket);
        return $Self->_Result( Success => 0, Message => 'Translate:AdminIMAPAuthFailed' );
    }

    return {
        Socket => $Socket,
    };
}

sub _IMAPLogout {
    my ( $Self, %Param ) = @_;

    my $Socket = $Param{Socket};
    my $Tag    = $Param{Tag} || 'A999';

    if ($Socket) {
        $Self->_IMAPCommand(
            Socket  => $Socket,
            Tag     => $Tag,
            Command => 'LOGOUT',
        );
        $Self->_SocketClose($Socket);
    }

    return 1;
}

sub _IMAPSocket {
    my ( $Self, %Param ) = @_;

    my $Host     = $Param{Host};
    my $Port     = $Param{Port};
    my $Security = $Param{Security};

    if ( $Security eq 'imaps' ) {
        my $Socket = IO::Socket::SSL->new(
            PeerHost     => $Host,
            PeerPort     => $Port,
            Timeout      => 15,
            SSL_hostname => $Host,
        );

        return $Socket if $Socket;

        return $Self->_Result( Success => 0, Message => 'Translate:AdminIMAPSConnectionFailed' );
    }

    my $Socket = IO::Socket::INET->new(
        PeerHost => $Host,
        PeerPort => $Port,
        Proto    => 'tcp',
        Timeout  => 15,
    );

    return $Socket if $Socket;

    return $Self->_Result( Success => 0, Message => 'Translate:AdminIMAPConnectionFailed' );
}

sub _IMAPCommand {
    my ( $Self, %Param ) = @_;

    my $Socket  = $Param{Socket};
    my $Tag     = $Param{Tag};
    my $Command = $Param{Command};

    print {$Socket} $Tag . ' ' . $Command . "\r\n";

    return $Self->_IMAPRead(
        Socket => $Socket,
        Tag    => $Tag,
    );
}

sub _IMAPRead {
    my ( $Self, %Param ) = @_;

    my $Socket = $Param{Socket};
    my $Tag    = $Param{Tag} || '';
    my $Data   = '';

    local $SIG{ALRM} = sub { die "timeout\n" };

    eval {
        alarm 15;
        while ( my $Line = <$Socket> ) {
            $Data .= $Line;
            last if !$Tag;
            last if $Line =~ m{\A\Q$Tag\E\s+}i;
        }
        alarm 0;
        1;
    } || do {
        alarm 0;
    };

    return $Data;
}

sub _IMAPFetchBody {
    my ( $Self, $Response ) = @_;

    return '' if !$Response;

    if ( $Response =~ m{BODY(?:\.PEEK)?\[\]\s+\{\d+\}\r?\n(.*)\r?\n\)\r?\nA\d+\s+OK}is ) {
        return $1;
    }

    if ( $Response =~ m{RFC822\s+\{\d+\}\r?\n(.*)\r?\n\)\r?\nA\d+\s+OK}is ) {
        return $1;
    }

    return '';
}

sub _MessageParse {
    my ( $Self, $RawMessage ) = @_;

    $RawMessage ||= '';
    $RawMessage =~ s{\r\n}{\n}g;
    $RawMessage =~ s{\r}{\n}g;

    my ( $HeaderText, $Body ) = split m{\n\n}, $RawMessage, 2;
    $HeaderText ||= '';
    $Body       ||= '';

    $HeaderText =~ s{\n[ \t]+}{ }g;

    my %Header;
    for my $Line ( split m{\n}, $HeaderText ) {
        next if $Line !~ m{\A([^:]+):\s*(.*)\z};
        my $Name  = lc $1;
        my $Value = $2;
        $Header{$Name} = defined $Header{$Name} ? $Header{$Name} . ', ' . $Value : $Value;
    }

    my $Subject = $Self->_HeaderDecode( $Header{subject} || '(no subject)' );
    my ( $FromName, $FromEmail ) = $Self->_AddressParse( $Header{from} || '' );
    my ( $ToName,   $ToEmail )   = $Self->_AddressParse( $Header{to}   || '' );

    my $ContentType = $Header{'content-type'} || 'text/plain';
    my $Encoding    = lc( $Header{'content-transfer-encoding'} || '' );

    my $ParsedBody = $Self->_MessageBodyDecode(
        Body        => $Body,
        ContentType => $ContentType,
        Encoding    => $Encoding,
    );

    return {
        subject      => $Subject,
        from_name    => $FromName,
        from_email   => $FromEmail,
        to_name      => $ToName,
        to_email     => $ToEmail,
        body         => $ParsedBody->{Body},
        content_type         => $ParsedBody->{ContentType},
        attachments          => $ParsedBody->{Attachments} || [],
        rejected_attachments => $ParsedBody->{RejectedAttachments} || [],
    };
}

sub _MessageBodyDecode {
    my ( $Self, %Param ) = @_;

    my $Body        = $Param{Body} || '';
    my $ContentType = $Param{ContentType} || 'text/plain';
    my $Encoding    = $Param{Encoding} || '';

    my $Decoded = $Self->_MIMEBodyPartDecode(
        Body        => $Body,
        ContentType => $ContentType,
        Encoding    => $Encoding,
        Depth       => 0,
    );

    my %InlineImagePartByID = %{ $Decoded->{InlineImagePartByID} || {} };
    my @HTMLParts           = @{ $Decoded->{HTMLParts} || [] };
    my @PlainParts          = @{ $Decoded->{PlainParts} || [] };
    my @Attachments         = @{ $Decoded->{Attachments} || [] };

    my $DecodedBody = '';
    my $DecodedType = 'text/plain';

    if (@HTMLParts) {
        $DecodedBody = join '<br><br>', grep { defined $_ && $_ =~ m{\S} } @HTMLParts;

        my %ReferencedCID = map { $_ => 1 } @{ $Self->_HTMLCIDReferences( HTML => $DecodedBody ) };
        my %InlineImageByID;
        my %HandledInlinePart;

        for my $CID ( keys %InlineImagePartByID ) {
            my $Part = $InlineImagePartByID{$CID};
            next if ref $Part ne 'HASH';

            my $PartKey = $Self->_InlineImagePartKey($Part);
            my $IsReferenced = 0;
            for my $ReferenceID ( @{ $Part->{ReferenceIDs} || [] } ) {
                if ( $ReferencedCID{$ReferenceID} ) {
                    $IsReferenced = 1;
                    last;
                }
            }

            if ($IsReferenced) {
                my $ImageDataURI = $Self->_InlineImageDataURIFromRaw(
                    Raw         => $Part->{Content},
                    ContentType => $Part->{ContentType},
                );

                if ($ImageDataURI) {
                    for my $ReferenceID ( @{ $Part->{ReferenceIDs} || [] } ) {
                        $InlineImageByID{$ReferenceID} = $ImageDataURI;
                    }
                }
                elsif ( !$HandledInlinePart{$PartKey}++ ) {
                    push @Attachments, $Self->_AttachmentFromInlineImagePart($Part);
                }

                next;
            }

            if ( !$HandledInlinePart{$PartKey}++ ) {
                push @Attachments, $Self->_AttachmentFromInlineImagePart($Part);
            }
        }

        $DecodedBody = $Self->_HTMLCIDImagesReplace(
            HTML            => $DecodedBody,
            InlineImageByID => \%InlineImageByID,
        ) if %InlineImageByID;

        $DecodedBody = QisutuHTML->IncomingNormalize($DecodedBody);
        $DecodedType = 'text/html';
    }
    elsif (@PlainParts) {
        $DecodedBody = join "\n\n", grep { defined $_ && $_ =~ m{\S} } @PlainParts;
        $DecodedBody = $Self->_IncomingPlainTextClean($DecodedBody);
        $DecodedType = 'text/plain';

        my %HandledInlinePart;
        for my $CID ( keys %InlineImagePartByID ) {
            my $Part = $InlineImagePartByID{$CID};
            next if ref $Part ne 'HASH';

            my $PartKey = $Self->_InlineImagePartKey($Part);
            next if $HandledInlinePart{$PartKey}++;

            push @Attachments, $Self->_AttachmentFromInlineImagePart($Part);
        }
    }

    $DecodedBody =~ s{\A\s+}{};
    $DecodedBody =~ s{\s+\z}{};

    my $AttachmentLimit = $Self->_AttachmentListLimitApply( Attachments => \@Attachments );
    my $Rejected        = $AttachmentLimit->{Rejected} || [];

    if ( @{$Rejected} ) {
        $DecodedBody = $Self->_IncomingAttachmentLimitNoticeAppend(
            Body        => $DecodedBody,
            ContentType => $DecodedType,
            Rejected    => $Rejected,
        );
    }

    return {
        Body                => $DecodedBody,
        ContentType         => $DecodedType,
        Attachments         => $AttachmentLimit->{Allowed} || [],
        RejectedAttachments => $Rejected,
    };
}

sub _MIMEBodyPartDecode {
    my ( $Self, %Param ) = @_;

    my $Body        = $Param{Body} || '';
    my $ContentType = $Param{ContentType} || 'text/plain';
    my $Encoding    = lc( $Param{Encoding} || '' );
    my $Depth       = $Param{Depth} || 0;

    my $Result = {
        PlainParts          => [],
        HTMLParts           => [],
        InlineImagePartByID => {},
        Attachments         => [],
    };

    return $Result if $Depth > 20;

    if ( $ContentType =~ m{\Amultipart/}i ) {
        my $Boundary = $Self->_ContentTypeBoundary($ContentType);
        return $Result if !$Boundary;

        my @Parts = $Self->_MultipartSplit(
            Body     => $Body,
            Boundary => $Boundary,
        );

        for my $Part (@Parts) {
            next if !defined $Part || $Part !~ m{\S};

            my ( $PartHeaderText, $PartBody ) = split m{\n\n}, $Part, 2;
            next if !defined $PartBody;

            my %PartHeader = $Self->_MIMEHeaderParse($PartHeaderText);
            my $SubResult = $Self->_MIMEBodyPartDecode(
                Body               => $PartBody,
                ContentType        => $PartHeader{'content-type'} || 'text/plain',
                Encoding           => $PartHeader{'content-transfer-encoding'} || '',
                ContentDisposition => $PartHeader{'content-disposition'} || '',
                ContentID          => $PartHeader{'content-id'} || '',
                ContentLocation    => $PartHeader{'content-location'} || '',
                Depth              => $Depth + 1,
            );

            push @{ $Result->{PlainParts} },      @{ $SubResult->{PlainParts} || [] };
            push @{ $Result->{HTMLParts} },       @{ $SubResult->{HTMLParts} || [] };
            push @{ $Result->{Attachments} },     @{ $SubResult->{Attachments} || [] };
            $Result->{InlineImagePartByID}->{$_} = $SubResult->{InlineImagePartByID}->{$_}
                for keys %{ $SubResult->{InlineImagePartByID} || {} };
        }

        return $Result;
    }

    my $Disposition     = $Param{ContentDisposition} || '';
    my $ContentID       = $Self->_ContentIDNormalize( $Param{ContentID} || '' );
    my $ContentLocation = $Self->_CIDReferenceNormalize( $Param{ContentLocation} || '' );
    my $BaseType        = $Self->_ContentTypeBase($ContentType);
    my $Filename        = $Self->_PartFilename(
        ContentType        => $ContentType,
        ContentDisposition => $Disposition,
    );

    if ( $BaseType =~ m{\Atext/(?:plain|html)\z}i && !$Self->_PartIsAttachment( Disposition => $Disposition, Filename => $Filename, ContentID => $ContentID, ContentType => $BaseType ) ) {
        my $DecodedBody = $Self->_BodyDecode(
            Body        => $Body,
            Encoding    => $Encoding,
            ContentType => $ContentType,
        );

        if ( $BaseType eq 'text/html' ) {
            push @{ $Result->{HTMLParts} }, $DecodedBody if $DecodedBody =~ m{\S};
        }
        else {
            push @{ $Result->{PlainParts} }, $DecodedBody if $DecodedBody =~ m{\S};
        }

        return $Result;
    }

    my $Raw = $Self->_BodyTransferDecodeRaw(
        Body     => $Body,
        Encoding => $Encoding,
    );

    return $Result if !defined $Raw || !length $Raw;

    if (
        $BaseType =~ m{\Aimage/(?:png|jpeg|jpg|gif|webp)\z}i
        && $ContentID
        && lc($Disposition) !~ m{\A\s*attachment\b}
    ) {
        my @ReferenceIDs = grep { $_ } ( $ContentID, $ContentLocation );
        my $Part = {
            Filename           => $Self->_FilenameClean( $Filename || $Self->_DefaultAttachmentFilename( ContentType => $BaseType ) ),
            ContentType        => $BaseType || 'application/octet-stream',
            Content            => $Raw,
            ContentSize        => length($Raw),
            ContentID          => $ContentID,
            ContentDisposition => $Self->_ContentDispositionBase($Disposition) || 'inline',
            ReferenceIDs       => \@ReferenceIDs,
        };

        for my $ReferenceID (@ReferenceIDs) {
            $Result->{InlineImagePartByID}->{$ReferenceID} = $Part;
        }

        return $Result;
    }

    if ( $Self->_PartIsAttachment( Disposition => $Disposition, Filename => $Filename, ContentID => $ContentID, ContentType => $BaseType ) ) {
        $Filename ||= $Self->_DefaultAttachmentFilename( ContentType => $BaseType );

        push @{ $Result->{Attachments} }, {
            Filename           => $Self->_FilenameClean($Filename),
            ContentType        => $BaseType || 'application/octet-stream',
            Content            => $Raw,
            ContentSize        => length($Raw),
            ContentID          => $ContentID,
            ContentDisposition => $Self->_ContentDispositionBase($Disposition) || 'attachment',
        };
    }

    return $Result;
}

sub _PartIsAttachment {
    my ( $Self, %Param ) = @_;

    my $Disposition = lc( $Param{Disposition} || '' );
    my $Filename    = $Param{Filename} || '';
    my $ContentID   = $Param{ContentID} || '';
    my $ContentType = lc( $Param{ContentType} || '' );

    return 1 if $Disposition =~ m{\A\s*attachment\b};
    return 0 if $ContentID && $ContentType =~ m{\Aimage/} && $Disposition !~ m{\A\s*attachment\b};
    return 1 if $Filename && $ContentType !~ m{\Atext/(?:plain|html)\z};

    return 0;
}

sub _HTMLCIDReferences {
    my ( $Self, %Param ) = @_;

    my $HTML = $Param{HTML} || '';
    my %Reference;

    while ( $HTML =~ m{\bsrc\s*=\s*(["'])\s*cid:([^"']+)\1}gix ) {
        my $CID = $Self->_CIDReferenceNormalize($2);
        $Reference{$CID} = 1 if $CID;
    }

    while ( $HTML =~ m{\bsrc\s*=\s*cid:([^\s>]+)}gix ) {
        my $CID = $Self->_CIDReferenceNormalize($1);
        $Reference{$CID} = 1 if $CID;
    }

    while ( $HTML =~ m{url\(\s*(["']?)cid:([^"')]+)\1\s*\)}gix ) {
        my $CID = $Self->_CIDReferenceNormalize($2);
        $Reference{$CID} = 1 if $CID;
    }

    return [ keys %Reference ];
}

sub _InlineImagePartKey {
    my ( $Self, $Part ) = @_;

    return '' if ref $Part ne 'HASH';
    return join '|',
        $Part->{ContentID} || '',
        $Part->{Filename} || '',
        $Part->{ContentType} || '',
        $Part->{ContentSize} || length( $Part->{Content} || '' );
}

sub _AttachmentFromInlineImagePart {
    my ( $Self, $Part ) = @_;

    $Part = {} if ref $Part ne 'HASH';

    return {
        Filename           => $Self->_FilenameClean( $Part->{Filename} || $Self->_DefaultAttachmentFilename( ContentType => $Part->{ContentType} || 'application/octet-stream' ) ),
        ContentType        => $Part->{ContentType} || 'application/octet-stream',
        Content            => $Part->{Content} || '',
        ContentSize        => $Part->{ContentSize} || length( $Part->{Content} || '' ),
        ContentID          => $Part->{ContentID} || '',
        ContentDisposition => 'attachment',
    };
}

sub _ContentDispositionBase {
    my ( $Self, $Disposition ) = @_;

    $Disposition ||= '';
    $Disposition =~ s{;.*\z}{};
    $Disposition =~ s{\A\s+|\s+\z}{}g;

    return lc($Disposition) || '';
}

sub _ContentTypeBase {
    my ( $Self, $ContentType ) = @_;

    $ContentType ||= 'application/octet-stream';
    $ContentType =~ s{;.*\z}{};
    $ContentType =~ s{\A\s+|\s+\z}{}g;
    $ContentType = lc $ContentType;
    $ContentType = 'image/jpeg' if $ContentType eq 'image/jpg';
    $ContentType ||= 'application/octet-stream';

    return $ContentType;
}

sub _PartFilename {
    my ( $Self, %Param ) = @_;

    my $Disposition = $Param{ContentDisposition} || '';
    my $ContentType = $Param{ContentType} || '';

    for my $Header ( $Disposition, $ContentType ) {
        my $Value = $Self->_HeaderParameterDecode( Header => $Header, Name => 'filename' );
        return $Value if $Value;

        $Value = $Self->_HeaderParameterDecode( Header => $Header, Name => 'name' );
        return $Value if $Value;
    }

    return '';
}

sub _HeaderParameterDecode {
    my ( $Self, %Param ) = @_;

    my $Header = $Param{Header} || '';
    my $Name   = $Param{Name}   || '';

    return '' if !$Header || !$Name;

    my $Value = '';
    if ( $Header =~ m{(?:^|;)\s*\Q$Name\E\*\s*=\s*(?:"([^"]*)"|'([^']*)'|([^;\s]+))}i ) {
        $Value = defined $1 ? $1 : defined $2 ? $2 : $3;
        $Value = $Self->_RFC2231Decode($Value);
    }
    elsif ( $Header =~ m{(?:^|;)\s*\Q$Name\E\s*=\s*(?:"([^"]*)"|'([^']*)'|([^;]+))}i ) {
        $Value = defined $1 ? $1 : defined $2 ? $2 : $3;
    }

    $Value ||= '';
    $Value =~ s{\A\s+|\s+\z}{}g;
    $Value =~ s{\A"|"\z}{}g;
    $Value =~ s{\A'|'\z}{}g;
    $Value = $Self->_HeaderDecode($Value);

    return $Value;
}

sub _RFC2231Decode {
    my ( $Self, $Value ) = @_;

    $Value ||= '';

    my $Charset = 'UTF-8';
    my $Data    = $Value;

    if ( $Value =~ m{\A([^']*)'[^']*'(.*)\z}s ) {
        $Charset = $1 || 'UTF-8';
        $Data    = $2;
    }

    $Data =~ s{%([0-9A-Fa-f]{2})}{chr(hex($1))}eg;

    my $Decoded = eval { decode( $Charset, $Data, 1 ) };
    $Decoded = decode( 'UTF-8', $Data, 1 ) if !defined $Decoded;

    return $Decoded;
}

sub _DefaultAttachmentFilename {
    my ( $Self, %Param ) = @_;

    my $ContentType = $Param{ContentType} || 'application/octet-stream';
    my %ExtensionFor = (
        'application/pdf' => 'pdf',
        'text/plain'      => 'txt',
        'text/html'       => 'html',
        'image/png'       => 'png',
        'image/jpeg'      => 'jpg',
        'image/gif'       => 'gif',
        'image/webp'      => 'webp',
    );

    my $Extension = $ExtensionFor{ lc $ContentType } || 'bin';

    return 'attachment.' . $Extension;
}

sub _MIMEHeaderParse {
    my ( $Self, $HeaderText ) = @_;

    $HeaderText ||= '';
    $HeaderText =~ s{\r\n}{\n}g;
    $HeaderText =~ s{\r}{\n}g;
    $HeaderText =~ s{\n[ \t]+}{ }g;

    my %Header;
    for my $Line ( split m{\n}, $HeaderText ) {
        next if $Line !~ m{\A([^:]+):\s*(.*)\z};
        my $Name  = lc $1;
        my $Value = $2;
        $Header{$Name} = defined $Header{$Name} ? $Header{$Name} . ', ' . $Value : $Value;
    }

    return %Header;
}

sub _ContentIDNormalize {
    my ( $Self, $Value ) = @_;

    $Value ||= '';
    $Value =~ s{\r\n}{ }g;
    $Value =~ s{\r|\n}{ }g;
    $Value =~ s{\A\s+|\s+\z}{}g;
    $Value =~ s{\A<}{};
    $Value =~ s{>\z}{};

    return $Self->_CIDReferenceNormalize($Value);
}

sub _CIDReferenceNormalize {
    my ( $Self, $Value ) = @_;

    $Value ||= '';
    $Value =~ s{\r\n}{ }g;
    $Value =~ s{\r|\n}{ }g;
    $Value =~ s{\A\s+|\s+\z}{}g;
    $Value =~ s{\A['"]|['"]\z}{}g;
    $Value =~ s{\Acid:}{}i;
    $Value =~ s{\A<}{};
    $Value =~ s{>\z}{};
    $Value =~ s{\A\s+|\s+\z}{}g;

    return lc $Value;
}

sub _InlineImageDataURIFromRaw {
    my ( $Self, %Param ) = @_;

    my $Raw         = $Param{Raw};
    my $ContentType = $Param{ContentType} || '';

    return '' if !defined $Raw || !length $Raw;

    my $MimeType = lc $ContentType;
    $MimeType =~ s{;.*\z}{};
    $MimeType =~ s{\A\s+|\s+\z}{}g;
    $MimeType = 'image/jpeg' if $MimeType eq 'image/jpg';

    return '' if $MimeType !~ m{\Aimage/(?:png|jpeg|gif|webp)\z};
    return '' if length($Raw) > 8 * 1024 * 1024;

    my $Encoded = encode_base64( $Raw, '' );

    return 'data:' . $MimeType . ';base64,' . $Encoded;
}

sub _InlineImageDataURI {
    my ( $Self, %Param ) = @_;

    my $Body        = $Param{Body} || '';
    my $Encoding    = lc( $Param{Encoding} || '' );
    my $ContentType = $Param{ContentType} || '';

    my $Raw = $Self->_BodyTransferDecodeRaw(
        Body     => $Body,
        Encoding => $Encoding,
    );

    return $Self->_InlineImageDataURIFromRaw(
        Raw         => $Raw,
        ContentType => $ContentType,
    );
}

sub _BodyTransferDecodeRaw {
    my ( $Self, %Param ) = @_;

    my $Body     = $Param{Body} || '';
    my $Encoding = lc( $Param{Encoding} || '' );

    $Body =~ s{\r\n}{\n}g;
    $Body =~ s{\r}{\n}g;

    if ( $Encoding eq 'base64' ) {
        return decode_base64($Body);
    }

    if ( $Encoding eq 'quoted-printable' ) {
        return decode_qp($Body);
    }

    return $Body;
}

sub _HTMLCIDImagesReplace {
    my ( $Self, %Param ) = @_;

    my $HTML            = $Param{HTML} || '';
    my $InlineImageByID = ref $Param{InlineImageByID} eq 'HASH' ? $Param{InlineImageByID} : {};

    return $HTML if !$HTML || !%{$InlineImageByID};

    $HTML =~ s{(\bsrc\s*=\s*)(["'])(cid:([^"']+))\2}{
        my $Prefix = $1;
        my $Quote  = $2;
        my $CID    = $Self->_CIDReferenceNormalize($4);
        my $Data   = $InlineImageByID->{$CID} || '';
        $Data ? $Prefix . $Quote . $Data . $Quote : $&;
    }gexi;

    $HTML =~ s{(\bsrc\s*=\s*)(cid:([^\s>]+))}{
        my $Prefix = $1;
        my $CID    = $Self->_CIDReferenceNormalize($3);
        my $Data   = $InlineImageByID->{$CID} || '';
        $Data ? $Prefix . '"' . $Data . '"' : $&;
    }gexi;

    return $HTML;
}

sub _ContentTypeBoundary {
    my ( $Self, $ContentType ) = @_;

    $ContentType ||= '';

    my $Boundary = '';
    if ( $ContentType =~ m{boundary\s*=\s*"([^"]+)"}i ) {
        $Boundary = $1;
    }
    elsif ( $ContentType =~ m{boundary\s*=\s*'([^']+)'}i ) {
        $Boundary = $1;
    }
    elsif ( $ContentType =~ m{boundary\s*=\s*([^;\s]+)}i ) {
        $Boundary = $1;
    }

    $Boundary =~ s{\A\s+|\s+\z}{}g;
    $Boundary =~ s{\A"|"\z}{}g;
    $Boundary =~ s{\A'|'\z}{}g;

    return $Boundary;
}

sub _ContentTypeCharset {
    my ( $Self, $ContentType ) = @_;

    $ContentType ||= '';

    my $Charset = '';
    if ( $ContentType =~ m{charset\s*=\s*"([^"]+)"}i ) {
        $Charset = $1;
    }
    elsif ( $ContentType =~ m{charset\s*=\s*'([^']+)'}i ) {
        $Charset = $1;
    }
    elsif ( $ContentType =~ m{charset\s*=\s*([^;\s]+)}i ) {
        $Charset = $1;
    }

    $Charset =~ s{\A\s+|\s+\z}{}g;
    $Charset =~ s{\A"|"\z}{}g;
    $Charset =~ s{\A'|'\z}{}g;

    return $Charset || 'UTF-8';
}

sub _MultipartSplit {
    my ( $Self, %Param ) = @_;

    my $Body     = $Param{Body} || '';
    my $Boundary = $Param{Boundary} || '';

    return () if !$Boundary;

    $Body =~ s{\r\n}{\n}g;
    $Body =~ s{\r}{\n}g;

    my @Parts;
    my $BoundaryRegex = quotemeta $Boundary;

    while ( $Body =~ m{(?:\A|\n)--$BoundaryRegex[ \t]*\n(.*?)(?=\n--$BoundaryRegex(?:--)?[ \t]*(?:\n|\z))}sg ) {
        push @Parts, $1;
    }

    if (!@Parts) {
        my @Segments = split m{\n--$BoundaryRegex(?:--)?[ \t]*(?:\n|\z)}, "\n" . $Body;
        shift @Segments if @Segments;
        @Parts = grep { defined $_ && $_ =~ m{\S} } @Segments;
    }

    return @Parts;
}

sub _BodyDecode {
    my ( $Self, %Param ) = @_;

    my $Body        = $Param{Body} || '';
    my $Encoding    = lc( $Param{Encoding} || '' );
    my $ContentType = $Param{ContentType} || '';
    my $Charset     = $Self->_ContentTypeCharset($ContentType);

    $Body =~ s{\r\n}{\n}g;
    $Body =~ s{\r}{\n}g;

    if ( $Encoding eq 'base64' ) {
        $Body = decode_base64($Body);
    }
    elsif ( $Encoding eq 'quoted-printable' ) {
        $Body = decode_qp($Body);
    }

    my $Decoded = eval { decode( $Charset, $Body, 1 ) };
    if ( !defined $Decoded ) {
        $Decoded = decode( 'UTF-8', $Body, 1 );
    }

    $Decoded =~ s{\r\n}{\n}g;
    $Decoded =~ s{\r}{\n}g;

    return $Decoded;
}

sub _IncomingPlainTextClean {
    my ( $Self, $Body ) = @_;

    $Body = '' if !defined $Body;
    $Body =~ s{\r\n}{\n}g;
    $Body =~ s{\r}{\n}g;
    $Body =~ s{\x00}{}g;
    $Body =~ s{\n--[A-Za-z0-9'()+_,\-\.\/:=\?]{8,}(?:--)?[ \t]*(?=\n|\z).*\z}{}s;
    $Body =~ s{\nContent-Type:\s+text/(?:plain|html).*\z}{}is;
    $Body =~ s{\nContent-Transfer-Encoding:\s+(?:base64|quoted-printable|7bit|8bit).*\z}{}is;
    $Body =~ s{\A\s+}{};
    $Body =~ s{\s+\z}{};

    return $Body;
}

sub _AttachmentMaxSizeMB {
    my ($Self) = @_;

    return $Self->{AttachmentMaxSizeMBCache}
        if defined $Self->{AttachmentMaxSizeMBCache};

    my $Value = 25;

    if ( $Self->{DB} ) {
        $Value = QisutuSystemSetting->new(
            Config => $Self->{Config},
            DB     => $Self->{DB},
        )->AttachmentMaxSizeMB();
    }

    $Self->{AttachmentMaxSizeMBCache} = 0 + $Value;

    return $Self->{AttachmentMaxSizeMBCache};
}

sub _AttachmentListLimitApply {
    my ( $Self, %Param ) = @_;

    my $Attachments = ref $Param{Attachments} eq 'ARRAY' ? $Param{Attachments} : [];
    my $LimitBytes  = $Self->_AttachmentMaxSizeMB() * 1024 * 1024;
    my @Allowed;
    my @Rejected;

    for my $Attachment ( @{$Attachments} ) {
        next if ref $Attachment ne 'HASH';

        my $Content = $Attachment->{Content};
        my $Size    = $Attachment->{ContentSize};
        $Size = length($Content) if !defined $Size || $Size !~ m{\A\d+\z};
        $Attachment->{ContentSize} = $Size;

        if ( $LimitBytes && $Size > $LimitBytes ) {
            push @Rejected, $Attachment;
            next;
        }

        push @Allowed, $Attachment;
    }

    return {
        Allowed  => \@Allowed,
        Rejected => \@Rejected,
    };
}

sub _AttachmentTooLargeMessage {
    my ( $Self, %Param ) = @_;

    my $Attachment = $Param{Attachment} || {};
    my $Filename   = $Attachment->{Filename} || 'attachment';
    my $LimitMB    = $Self->_AttachmentMaxSizeMB();

    return 'Attachment "' . $Filename . '" exceeds the permitted maximum size of ' . $LimitMB . ' MB';
}

sub _IncomingAttachmentLimitNoticeAppend {
    my ( $Self, %Param ) = @_;

    my $Body        = $Param{Body} || '';
    my $ContentType = $Param{ContentType} || 'text/plain';
    my $Rejected    = ref $Param{Rejected} eq 'ARRAY' ? $Param{Rejected} : [];
    my $LimitMB     = $Self->_AttachmentMaxSizeMB();
    my $Language    = 'en';

    if ( $Self->{DB} ) {
        $Language = QisutuSystemSetting->new(
            Config => $Self->{Config},
            DB     => $Self->{DB},
        )->Get(
            Key     => 'system.default_language',
            Default => $Self->{Config}->{Language}->{Default} || 'en',
        ) || 'en';
    }
    else {
        $Language = $Self->{Config}->{Language}->{Default} || 'en';
    }

    my @Line;
    for my $Attachment ( @{$Rejected} ) {
        my $Filename = $Attachment->{Filename} || 'attachment';
        my $Size     = $Attachment->{ContentSize} || length( $Attachment->{Content} || '' );
        my $SizeText = $Self->_ByteSizeFormat($Size);

        if ( $Language eq 'de' ) {
            push @Line, 'Anhang nicht importiert: ' . $Filename . ' (' . $SizeText . '). Maximale Größe: ' . $LimitMB . ' MB.';
        }
        else {
            push @Line, 'Attachment not imported: ' . $Filename . ' (' . $SizeText . '). Maximum size: ' . $LimitMB . ' MB.';
        }
    }

    if ( $ContentType eq 'text/html' ) {
        my $Title = $Language eq 'de' ? 'Hinweis zu Anhängen' : 'Attachment notice';
        my $HTML = '<hr><p><strong>' . $Self->_HTMLEscape($Title) . '</strong></p><ul>';
        $HTML .= '<li>' . $Self->_HTMLEscape($_) . '</li>' for @Line;
        $HTML .= '</ul>';
        return $Body . $HTML;
    }

    return $Body . "\n\n---\n" . join( "\n", @Line );
}

sub _ByteSizeFormat {
    my ( $Self, $Size ) = @_;

    $Size = 0 if !defined $Size || $Size !~ m{\A\d+(?:\.\d+)?\z};

    return sprintf( '%.1f GB', $Size / 1024 / 1024 / 1024 ) if $Size >= 1024 * 1024 * 1024;
    return sprintf( '%.1f MB', $Size / 1024 / 1024 ) if $Size >= 1024 * 1024;
    return sprintf( '%.1f KB', $Size / 1024 ) if $Size >= 1024;
    return $Size . ' B';
}

sub _HTMLEscape {
    my ( $Self, $Value ) = @_;

    $Value = '' if !defined $Value;
    $Value =~ s{&}{&amp;}g;
    $Value =~ s{<}{&lt;}g;
    $Value =~ s{>}{&gt;}g;
    $Value =~ s{"}{&quot;}g;
    $Value =~ s{'}{&#39;}g;

    return $Value;
}

sub _SMTPMessageBuild {
    my ( $Self, %Param ) = @_;

    my $FromName     = $Self->_HeaderValueClean( $Param{FromName}  || '' );
    my $FromEmail    = $Self->_EmailClean( $Param{FromEmail} || '' );
    my $ToName       = $Self->_HeaderValueClean( $Param{ToName}    || '' );
    my @ToEmails     = $Self->_EmailListClean( $Param{ToEmail} || '' );
    my @CcEmails     = $Self->_EmailListClean( $Param{Cc} || $Param{CC} || '' );
    my $ToEmail      = @ToEmails ? $ToEmails[0] : '';
    my $ReplyToName  = $Self->_HeaderValueClean( $Param{ReplyToName}  || '' );
    my $ReplyToEmail = $Self->_EmailClean( $Param{ReplyToEmail} || '' );
    my $Subject      = $Self->_HeaderValueClean( $Param{Subject} || '' );
    my $Body         = $Param{Body} || '';
    my $PlainBody    = defined $Param{PlainBody} ? $Param{PlainBody} : '';
    my $InlineImages = ref $Param{InlineImages} eq 'ARRAY' ? $Param{InlineImages} : [];
    my $Attachments  = ref $Param{Attachments}  eq 'ARRAY' ? $Param{Attachments}  : [];
    my $Date         = $Self->_MailDateRFC2822();

    my $MessageIDHost = $FromEmail;
    $MessageIDHost =~ s{\A.*@}{};
    $MessageIDHost =~ s{[^A-Za-z0-9.\-]}{}g;
    $MessageIDHost ||= 'qisutu.local';

    my @Header = (
        'Date: ' . $Date,
        'From: ' . $Self->_AddressFormat( Name => $FromName, Email => $FromEmail ),
        'To: ' . $Self->_AddressListFormat( Name => $ToName, Emails => \@ToEmails ),
        'Subject: ' . $Self->_HeaderEncode($Subject),
        'Message-ID: <' . time() . '.' . int( rand(1000000) ) . '@' . $MessageIDHost . '>',
        'MIME-Version: 1.0',
    );

    if (@CcEmails) {
        push @Header, 'Cc: ' . $Self->_AddressListFormat( Emails => \@CcEmails );
    }

    if ($ReplyToEmail) {
        push @Header, 'Reply-To: ' . $Self->_AddressFormat( Name => $ReplyToName, Email => $ReplyToEmail );
    }

    my $EncodedBody = encode_base64( encode( 'UTF-8', $Body ), "\r\n" );
    $EncodedBody =~ s{\r?\n\z}{};

    my $EncodedPlainBody = '';
    if ( length $PlainBody ) {
        $EncodedPlainBody = encode_base64( encode( 'UTF-8', $PlainBody ), "\r\n" );
        $EncodedPlainBody =~ s{\r?\n\z}{};
    }

    if ( @{$Attachments} ) {
        my $MixedBoundary = $Self->_MIMEBoundary();
        push @Header, 'Content-Type: multipart/mixed; boundary="' . $MixedBoundary . '"';

        my @Part;
        push @Part, '--' . $MixedBoundary;

        if ( @{$InlineImages} ) {
            push @Part, $Self->_SMTPRelatedPart(
                EncodedBody      => $EncodedBody,
                EncodedPlainBody => $EncodedPlainBody,
                InlineImages     => $InlineImages,
            );
        }
        elsif ($EncodedPlainBody) {
            push @Part, $Self->_SMTPAlternativePart(
                EncodedBody      => $EncodedBody,
                EncodedPlainBody => $EncodedPlainBody,
            );
        }
        else {
            push @Part, $Self->_SMTPHTMLPart( EncodedBody => $EncodedBody );
        }

        for my $Attachment ( @{$Attachments} ) {
            my $AttachmentPart = $Self->_SMTPAttachmentPart($Attachment);
            next if !$AttachmentPart;
            push @Part, '--' . $MixedBoundary;
            push @Part, $AttachmentPart;
        }

        push @Part, '--' . $MixedBoundary . '--';

        return join( "\r\n", @Header ) . "\r\n\r\n" . join( "\r\n", @Part ) . "\r\n";
    }

    if ( @{$InlineImages} ) {
        my $RelatedBoundary = $Self->_MIMEBoundary();
        my $RelatedType = $EncodedPlainBody ? 'multipart/alternative' : 'text/html';
        push @Header, 'Content-Type: multipart/related; type="' . $RelatedType . '"; boundary="' . $RelatedBoundary . '"';

        my @Part;
        push @Part, '--' . $RelatedBoundary;

        if ($EncodedPlainBody) {
            push @Part, $Self->_SMTPAlternativePart(
                EncodedBody      => $EncodedBody,
                EncodedPlainBody => $EncodedPlainBody,
            );
        }
        else {
            push @Part, $Self->_SMTPHTMLPart( EncodedBody => $EncodedBody );
        }

        for my $Image ( @{$InlineImages} ) {
            my $ImagePart = $Self->_SMTPInlineImagePart($Image);
            next if !$ImagePart;
            push @Part,
                '--' . $RelatedBoundary,
                $ImagePart;
        }

        push @Part, '--' . $RelatedBoundary . '--';

        return join( "\r\n", @Header ) . "\r\n\r\n" . join( "\r\n", @Part ) . "\r\n";
    }

    if ($EncodedPlainBody) {
        my $AlternativeBoundary = $Self->_MIMEBoundary();
        push @Header, 'Content-Type: multipart/alternative; boundary="' . $AlternativeBoundary . '"';

        my @Part = (
            '--' . $AlternativeBoundary,
            $Self->_SMTPTextPart( EncodedBody => $EncodedPlainBody ),
            '--' . $AlternativeBoundary,
            $Self->_SMTPHTMLPart( EncodedBody => $EncodedBody ),
            '--' . $AlternativeBoundary . '--',
        );

        return join( "\r\n", @Header ) . "\r\n\r\n" . join( "\r\n", @Part ) . "\r\n";
    }

    push @Header,
        'Content-Type: text/html; charset=UTF-8',
        'Content-Transfer-Encoding: base64';

    return join( "\r\n", @Header ) . "\r\n\r\n" . $EncodedBody . "\r\n";
}

sub _SMTPTextPart {
    my ( $Self, %Param ) = @_;

    my $EncodedBody = $Param{EncodedBody} || '';

    return join "\r\n",
        'Content-Type: text/plain; charset=UTF-8',
        'Content-Transfer-Encoding: base64',
        '',
        $EncodedBody;
}

sub _SMTPAlternativePart {
    my ( $Self, %Param ) = @_;

    my $EncodedBody      = $Param{EncodedBody} || '';
    my $EncodedPlainBody = $Param{EncodedPlainBody} || '';
    my $Boundary         = $Self->_MIMEBoundary();

    return join "\r\n",
        'Content-Type: multipart/alternative; boundary="' . $Boundary . '"',
        '',
        '--' . $Boundary,
        $Self->_SMTPTextPart( EncodedBody => $EncodedPlainBody ),
        '--' . $Boundary,
        $Self->_SMTPHTMLPart( EncodedBody => $EncodedBody ),
        '--' . $Boundary . '--';
}

sub _SMTPHTMLPart {
    my ( $Self, %Param ) = @_;

    my $EncodedBody = $Param{EncodedBody} || '';

    return join "\r\n",
        'Content-Type: text/html; charset=UTF-8',
        'Content-Transfer-Encoding: base64',
        '',
        $EncodedBody;
}

sub _SMTPRelatedPart {
    my ( $Self, %Param ) = @_;

    my $EncodedBody      = $Param{EncodedBody} || '';
    my $EncodedPlainBody = $Param{EncodedPlainBody} || '';
    my $InlineImages     = ref $Param{InlineImages} eq 'ARRAY' ? $Param{InlineImages} : [];
    my $Boundary         = $Self->_MIMEBoundary();
    my @Part;

    my $RelatedType = $EncodedPlainBody ? 'multipart/alternative' : 'text/html';

    push @Part,
        'Content-Type: multipart/related; type="' . $RelatedType . '"; boundary="' . $Boundary . '"',
        '',
        '--' . $Boundary;

    if ($EncodedPlainBody) {
        push @Part, $Self->_SMTPAlternativePart(
            EncodedBody      => $EncodedBody,
            EncodedPlainBody => $EncodedPlainBody,
        );
    }
    else {
        push @Part, $Self->_SMTPHTMLPart( EncodedBody => $EncodedBody );
    }

    for my $Image ( @{$InlineImages} ) {
        my $ImagePart = $Self->_SMTPInlineImagePart($Image);
        next if !$ImagePart;
        push @Part,
            '--' . $Boundary,
            $ImagePart;
    }

    push @Part, '--' . $Boundary . '--';

    return join "\r\n", @Part;
}

sub _SMTPInlineImagePart {
    my ( $Self, $Image ) = @_;

    my $ImageContent = $Self->_InlineImageContent($Image);
    return '' if !$ImageContent;

    my $ContentID = $Self->_ContentIDClean( $Image->{ContentID} || '' );
    return '' if !$ContentID;

    my $MimeType = $Self->_HeaderValueClean( $Image->{MimeType} || $Self->_MimeTypeByFilename( $Image->{Filename} || $Image->{Path} || '' ) );
    $MimeType ||= 'application/octet-stream';

    my $Filename = $Self->_FilenameClean( $Image->{Filename} || $Image->{Path} || 'inline-image' );
    my $EncodedImage = encode_base64( $ImageContent, "\r\n" );
    $EncodedImage =~ s{\r?\n\z}{};

    return join "\r\n",
        'Content-Type: ' . $MimeType . '; name="' . $Filename . '"',
        'Content-Transfer-Encoding: base64',
        'Content-ID: <' . $ContentID . '>',
        'Content-Disposition: inline; filename="' . $Filename . '"',
        '',
        $EncodedImage;
}

sub _SMTPAttachmentPart {
    my ( $Self, $Attachment ) = @_;

    return '' if ref $Attachment ne 'HASH';

    my $Content = $Attachment->{Content};
    return '' if !defined $Content || !length $Content;

    my $Filename = $Self->_FilenameClean( $Attachment->{Filename} || 'attachment.bin' );
    my $MimeType = $Self->_HeaderValueClean( $Attachment->{ContentType} || $Self->_MimeTypeByFilename($Filename) );
    $MimeType ||= 'application/octet-stream';

    my $EncodedContent = encode_base64( $Content, "\r\n" );
    $EncodedContent =~ s{\r?\n\z}{};

    return join "\r\n",
        'Content-Type: ' . $MimeType . '; name="' . $Filename . '"',
        'Content-Transfer-Encoding: base64',
        'Content-Disposition: attachment; filename="' . $Filename . '"',
        '',
        $EncodedContent;
}

sub _InlineImageContent {
    my ( $Self, $Image ) = @_;

    return '' if ref $Image ne 'HASH';

    if ( defined $Image->{Content} && length $Image->{Content} ) {
        return $Image->{Content};
    }

    my $Path = $Image->{Path} || '';
    return '' if !$Path || !-f $Path || !-r $Path;

    local $/;
    open my $FH, '<', $Path or return '';
    binmode $FH;
    my $Content = <$FH>;
    close $FH;

    return $Content || '';
}

sub _MIMEBoundary {
    my ($Self) = @_;

    return '=_QISUTU_' . time() . '_' . int( rand(1000000) );
}

sub _ContentIDClean {
    my ( $Self, $Value ) = @_;

    $Value ||= '';
    $Value =~ s{[^A-Za-z0-9_.\-]}{}g;

    return $Value;
}

sub _FilenameClean {
    my ( $Self, $Value ) = @_;

    $Value ||= 'inline-image';
    $Value =~ s{\\}{/}g;
    $Value =~ s{\A.*/}{}g;
    $Value =~ s{[\r\n"]}{}g;
    $Value =~ s{[^A-Za-z0-9_.\-]}{_}g;
    $Value ||= 'inline-image';

    return $Value;
}

sub _MimeTypeByFilename {
    my ( $Self, $Filename ) = @_;

    $Filename ||= '';

    return 'image/png'  if $Filename =~ m{\.png\z}i;
    return 'image/jpeg' if $Filename =~ m{\.jpe?g\z}i;
    return 'image/gif'  if $Filename =~ m{\.gif\z}i;
    return 'image/webp' if $Filename =~ m{\.webp\z}i;
    return 'image/svg+xml' if $Filename =~ m{\.svg\z}i;
    return 'application/pdf' if $Filename =~ m{\.pdf\z}i;
    return 'text/plain' if $Filename =~ m{\.txt\z}i;
    return 'text/csv' if $Filename =~ m{\.csv\z}i;
    return 'application/msword' if $Filename =~ m{\.doc\z}i;
    return 'application/vnd.openxmlformats-officedocument.wordprocessingml.document' if $Filename =~ m{\.docx\z}i;
    return 'application/vnd.ms-excel' if $Filename =~ m{\.xls\z}i;
    return 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet' if $Filename =~ m{\.xlsx\z}i;
    return 'application/vnd.ms-powerpoint' if $Filename =~ m{\.ppt\z}i;
    return 'application/vnd.openxmlformats-officedocument.presentationml.presentation' if $Filename =~ m{\.pptx\z}i;
    return 'application/zip' if $Filename =~ m{\.zip\z}i;

    return 'application/octet-stream';
}

sub _MailDateRFC2822 {
    my ( $Self, $Time ) = @_;

    $Time ||= time();

    my @WeekDays = qw(Sun Mon Tue Wed Thu Fri Sat);
    my @Months   = qw(Jan Feb Mar Apr May Jun Jul Aug Sep Oct Nov Dec);
    my ( $Second, $Minute, $Hour, $MonthDay, $Month, $Year, $WeekDay ) = localtime($Time);
    my $TZ = strftime( '%z', localtime($Time) ) || '+0000';

    return sprintf '%s, %02d %s %04d %02d:%02d:%02d %s',
        $WeekDays[$WeekDay] || 'Mon',
        $MonthDay,
        $Months[$Month] || 'Jan',
        $Year + 1900,
        $Hour,
        $Minute,
        $Second,
        $TZ;
}

sub _EmailListClean {
    my ( $Self, $Value ) = @_;

    $Value = '' if !defined $Value;
    $Value =~ s{\r|\n}{ }g;
    $Value =~ s{\A\s+|\s+\z}{}g;

    return () if !$Value;

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
        next if $Email !~ m{\A[A-Z0-9._%+\-]+\@[A-Z0-9.\-]+\.[A-Z]{2,}\z}i;

        my $Key = lc $Email;
        next if $Seen{$Key}++;
        push @Emails, $Email;
    }

    return @Emails;
}

sub _AddressListFormat {
    my ( $Self, %Param ) = @_;

    my $Name   = $Param{Name} || '';
    my $Emails = ref $Param{Emails} eq 'ARRAY' ? $Param{Emails} : [];

    return '' if !@{$Emails};

    if ( @{$Emails} == 1 ) {
        return $Self->_AddressFormat(
            Name  => $Name,
            Email => $Emails->[0],
        );
    }

    return join ', ', map { '<' . $_ . '>' } @{$Emails};
}

sub _HeaderValueClean {
    my ( $Self, $Value ) = @_;

    $Value = '' if !defined $Value;
    $Value =~ s{\r|\n}{ }g;
    $Value =~ s{\s+}{ }g;
    $Value =~ s{\A\s+|\s+\z}{}g;

    return $Value;
}

sub _EmailClean {
    my ( $Self, $Email ) = @_;

    $Email = '' if !defined $Email;
    $Email =~ s{\r|\n}{}g;
    $Email =~ s{\A\s+|\s+\z}{}g;

    if ( $Email =~ m{<([^>]+)>} ) {
        $Email = $1;
    }

    $Email =~ s{\A\s+|\s+\z}{}g;

    return $Email;
}

sub _AddressFormat {
    my ( $Self, %Param ) = @_;

    my $Name  = $Param{Name}  || '';
    my $Email = $Param{Email} || '';

    if ( !$Name ) {
        return '<' . $Email . '>';
    }

    my $EncodedName = $Self->_HeaderEncode($Name);

    if ( $EncodedName ne $Name ) {
        return $EncodedName . ' <' . $Email . '>';
    }

    $Name =~ s{"}{\\"}g;

    return '"' . $Name . '" <' . $Email . '>';
}

sub _HeaderEncode {
    my ( $Self, $Value ) = @_;

    $Value ||= '';

    if ( $Value =~ m{[^\x20-\x7E]} ) {
        return '=?UTF-8?B?' . encode_base64( encode( 'UTF-8', $Value ), '' ) . '?=';
    }

    return $Value;
}

sub _HeaderDecode {
    my ( $Self, $Value ) = @_;

    $Value ||= '';
    $Value =~ s{=\?([^?]+)\?([bqBQ])\?([^?]+)\?=}{
        my $Charset = $1 || 'UTF-8';
        my $Encoding = lc $2;
        my $Data = $3 || '';

        if ( $Encoding eq 'b' ) {
            $Data = decode_base64($Data);
        }
        else {
            $Data =~ s{_}{ }g;
            $Data = decode_qp($Data);
        }

        decode( $Charset, $Data, 1 );
    }eg;

    return $Value;
}

sub _AddressParse {
    my ( $Self, $Address ) = @_;

    $Address = $Self->_HeaderDecode( $Address || '' );

    my $Name  = '';
    my $Email = '';

    if ( $Address =~ m{\A\s*"?([^"<]*)"?\s*<([^>]+)>} ) {
        $Name  = $1 || '';
        $Email = $2 || '';
    }
    elsif ( $Address =~ m{([A-Z0-9._%+\-]+@[A-Z0-9.\-]+\.[A-Z]{2,})}i ) {
        $Email = $1;
    }

    $Name  =~ s{\A\s+|\s+\z}{}g;
    $Email =~ s{\A\s+|\s+\z}{}g;

    return ( $Name, $Email );
}

sub _IMAPQuote {
    my ( $Self, $Value ) = @_;

    $Value = '' if !defined $Value;
    $Value =~ s{\\}{\\\\}g;
    $Value =~ s{"}{\\"}g;

    return '"' . $Value . '"';
}

sub _SocketClose {
    my ( $Self, $Socket ) = @_;

    close $Socket if $Socket;

    return 1;
}

sub _SSLAvailable {
    my ($Self) = @_;

    return eval {
        require IO::Socket::SSL;
        IO::Socket::SSL->import();
        1;
    } ? 1 : 0;
}

sub _DefaultPort {
    my ( $Self, $Security ) = @_;

    my %Port = (
        smtp          => 25,
        smtp_starttls => 587,
        smtps         => 465,
        imap          => 143,
        imap_starttls => 143,
        imaps         => 993,
    );

    return $Port{$Security} || 0;
}

sub _AccountValue {
    my ( $Self, %Param ) = @_;

    my $Account = $Param{Account} || {};
    my $Prefix  = $Param{Prefix}  || '';
    my $Key     = $Param{Key}     || '';

    return if !$Key;

    my $PrefixedKey = $Prefix ? $Prefix . '_' . $Key : $Key;

    return $Account->{$PrefixedKey} if exists $Account->{$PrefixedKey};
    return $Account->{$Key}         if exists $Account->{$Key};

    return;
}

sub _Result {
    my ( $Self, %Param ) = @_;

    return {
        Success => $Param{Success} ? 1 : 0,
        Status  => $Param{Success} ? 'ok' : 'error',
        Message => $Param{Message} || '',
    };
}

sub Error {
    my ($Self) = @_;

    return $Self->{LastError};
}

1;
