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

use strict;
use warnings;
use utf8;
use Test::More;
use FindBin;
use Encode qw(encode);
use MIME::Base64 qw(encode_base64);
use MIME::QuotedPrint qw(encode_qp);
use lib "$FindBin::Bin/../core/system";
use QisutuHTML;
use QisutuMail;
use QisutuTicket;
use QisutuNotification;

# Exercise the real MIME importer, article storage preparation and ticket-view
# preparation. Only database I/O, access checks and unrelated side effects are
# replaced; the body processing runs through the production methods.
{
    package Local::MailBodyDB;
    sub new { return bless {}, shift }
    sub Error { return '' }
    sub SelectRow {
        my ( $Self, $SQL ) = @_;
        return { next_article_number => 1 } if $SQL =~ /MAX\(article_number\)/;
        die "Unexpected SelectRow: $SQL";
    }
    sub Do {
        my ( $Self, $SQL, @Bind ) = @_;
        if ( $SQL =~ /INSERT INTO ticket_article\s*\((.*?)\)\s*VALUES/s ) {
            my @Columns = split /\s*,\s*/, $1;
            s/^\s+|\s+$//g for @Columns;
            my %Row;
            @Row{@Columns[0 .. $#Bind]} = @Bind;
            $Self->{Article} = { %Row, id => 1 };
            return 1;
        }
        return 1 if $SQL =~ /UPDATE ticket\b/;
        die "Unexpected Do: $SQL";
    }
    sub LastInsertID { return 1 }
    sub SelectAll {
        my ( $Self, $SQL ) = @_;
        return [ { %{ $Self->{Article} } } ] if $SQL =~ /FROM ticket_article a/;
        die "Unexpected SelectAll: $SQL";
    }

    package Local::MailBodyTicket;
    our @ISA = ('QisutuTicket');
    sub TicketGet { return { id => 1 } }
    sub _TicketArticleVisibilityColumnExists { return 1 }
    sub _CustomerAccessData { return }
    sub _ArticleAttachmentsAdd { return 1 }
    sub RecalculateTicketEscalationTimes { return 1 }
    sub _AddonEventEmit { return 1 }
}

my $Mail = QisutuMail->new( Config => {} );
my $Notification = QisutuNotification->new( Config => {} );
my $DB = Local::MailBodyDB->new();
my $Ticket = Local::MailBodyTicket->new( Config => {}, DB => $DB );

sub ImportAndDisplay {
    my ($RawMessage) = @_;
    my $Message = $Mail->MessageParse( RawMessage => $RawMessage );
    my $ArticleID = $Ticket->ArticleCreate(
        TicketID => 1, CreatedByUserID => 1, Channel => 'email',
        SenderType => 'customer', Subject => $Message->{subject},
        Body => $Message->{body}, ContentType => $Message->{content_type},
        SkipTicketAccessCheck => 1, SkipNotification => 1,
    );
    die $Ticket->Error() if !$ArticleID;
    return $Ticket->ArticleList( TicketID => 1 )->[0];
}

sub Message {
    my ( $Body, $Type, $Encoding ) = @_;
    my $Bytes = encode( 'UTF-8', $Body );
    $Bytes = encode_qp($Bytes) if $Encoding eq 'quoted-printable';
    $Bytes = encode_base64($Bytes) if $Encoding eq 'base64';
    return "From: customer\@example.test\r\nTo: support\@example.test\r\n"
        . "Subject: Anfrage\r\nMIME-Version: 1.0\r\n"
        . "Content-Type: $Type; charset=UTF-8\r\n"
        . "Content-Transfer-Encoding: $Encoding\r\n\r\n$Bytes";
}

my @Cases = (
    [ 'empty div with br', '<div>A</div><div><br></div><div>B</div>', "A\n\nB" ],
    [ 'empty paragraph with br', '<p>A</p><p><br></p><p>B</p>', "A\n\nB" ],
    [ 'nbsp paragraph', '<p>A</p><p>&nbsp;</p><p>B</p>', "A\n\nB" ],
    [ 'numeric nbsp', '<div>A</div><div>&#160;</div><div>B</div>', "A\n\nB" ],
    [ 'nested blank line', '<div>A</div><div><div><br></div></div><div>B</div>', "A\n\nB" ],
    [ 'two empty paragraphs', '<p>A</p><p><br></p><p><br></p><p>B</p>', "A\n\n\nB" ],
    [ 'four line breaks', 'A<br><br><br><br>B', "A\n\n\n\nB" ],
    [ 'image spacing', 'A<br><br><img src="cid:example"><br><br><br>B', undef ],
    [ 'signature blank line', '<div>A</div><div><br></div><div class="moz-signature">--<br>Name</div>', "A\n\n--\nName" ],
    [ 'quote blank line', '<blockquote><div>A</div><div><br></div><div>B</div></blockquote>', "A\n\nB" ],
);

for my $Case (@Cases) {
    my ( $Name, $HTML, $Text ) = @{$Case};
    subtest $Name => sub {
        my $Article = ImportAndDisplay( Message( "<html><body>$HTML</body></html>", 'text/html', 'quoted-printable' ) );
        my $Expected = $HTML;
        $Expected =~ s/class="moz-signature"/class="qisutu-mail-signature"/;
        $Expected =~ s/<blockquote>/<blockquote class="qisutu-mail-quote">/;
        is( $Article->{body}, $Expected, 'stored body retains the authored breaks and empty blocks' );
        is( $Article->{body_html}, $Expected, 'ticket display retains the same breaks and empty blocks' );
        if ( defined $Text ) {
            my $Excerpt = $Notification->_ArticleBodyPlainText( Article => $Article );
            is( $Excerpt, $Text, 'notification receives the blank lines from the imported article' );
        }
    };
}

# Reconstructed structure of the reported greeting / introduction / facts case.
my $Inquiry = '<div>Sehr geehrte Damen und Herren,</div><div><br></div>'
    . '<div>wir evaluieren derzeit ein neues Ticketsystem.</div><div><br></div>'
    . '<div>Rahmendaten:</div><ul><li>Anzahl Agenten: 10</li><li>Endanwender: 1300</li></ul>';
my $Article = ImportAndDisplay( Message( $Inquiry, 'text/html', 'base64' ) );
is( $Article->{body_html}, $Inquiry, 'gaps after the greeting and introduction survive base64 mail import and ticket rendering' );
my $Excerpt = $Notification->_ArticleBodyPlainText( Article => $Article );
like( $Excerpt, qr{Herren,\n\nwir evaluieren}, 'notification keeps the first reported gap' );
like( $Excerpt, qr{Ticketsystem\.\n\nRahmendaten:}, 'notification keeps the second reported gap' );
my $NotificationHTML = $Notification->_PlaceholderReplaceHTML(
    HTML => '{{Ticket.ArticleBody[0]}}', Placeholder => { 'Ticket.ArticleBody' => $Excerpt },
);
like( $NotificationHTML, qr{Herren,<br><br>wir evaluieren}, '[0] renders the first gap' );
like( $NotificationHTML, qr{Ticketsystem\.<br><br>Rahmendaten:}, '[0] renders the second gap' );

my $Multipart = "From: customer\@example.test\r\nSubject: Multipart\r\n"
    . "Content-Type: multipart/alternative; boundary=mailbodytest\r\n\r\n"
    . "--mailbodytest\r\nContent-Type: text/plain; charset=UTF-8\r\n\r\nA\r\n\r\nB\r\n"
    . "--mailbodytest\r\nContent-Type: text/html; charset=UTF-8\r\n\r\n"
    . "<div>A</div><div><br></div><div>B</div>\r\n--mailbodytest--\r\n";
$Article = ImportAndDisplay($Multipart);
is( $Article->{content_type}, 'text/html', 'multipart message retains its HTML alternative' );
is( $Article->{body_html}, '<div>A</div><div><br></div><div>B</div>', 'multipart import preserves the empty HTML line' );

$Article = ImportAndDisplay( Message( "A\r\n\r\n\r\nB\r\nC", 'text/plain', 'quoted-printable' ) );
is( $Article->{body}, "A\n\n\nB\nC", 'plain-text import retains consecutive empty lines' );
is( $Article->{body_html}, 'A<br><br><br>B<br>C', 'plain-text ticket rendering retains the line breaks' );

for my $Text ('Grüße', 'Hello', 'Bonjour', 'Ciao', 'Hola', 'Groeten', 'Cześć', 'Dobrý den', 'Merhaba', 'Olá Portugal', 'Olá Brasil') {
    my $Body = "<div>$Text</div><div><br></div><div>123</div>";
    is( ImportAndDisplay( Message( $Body, 'text/html', 'base64' ) )->{body_html}, $Body, 'spacing preservation is independent of message language' );
}

$Article = ImportAndDisplay( Message(
    '<div onclick="bad()">A</div><div><br></div><script>bad()</script><div>B</div>',
    'text/html', '8bit',
) );
is( $Article->{body_html}, '<div>A</div><div><br></div><div>B</div>', 'HTML security filtering still removes executable content while retaining blank lines' );

done_testing();
