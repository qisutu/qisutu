#!/usr/bin/env perl
# Qisutu - Open Source Ticket System
# SPDX-License-Identifier: AGPL-3.0-or-later

use strict;
use warnings;
use utf8;

use FindBin;
use lib "$FindBin::Bin/../core/system", "$FindBin::Bin/../core/config", "$FindBin::Bin/../core/module", "$FindBin::Bin/../core/cpan-lib";
use Test::More;

use QisutuTicketPDF;
use AgentTicketZoom;

my $Root = "$FindBin::Bin/..";
my $Logo = "$Root/var/static/img/logo-pdf.jpg";
ok( -f $Logo && -s $Logo, 'local PDF logo is available' );

my $Ticket = {
    id                    => 17,
    ticket_number         => '202607180017',
    title                 => 'Printer does not work',
    queue_name            => 'Support',
    state_name_display    => 'Open',
    priority_name_display => '3 normal',
    customer_name         => 'Example Ltd.',
    customer_user_name    => 'Erika Example',
    customer_user_email   => 'erika@example.invalid',
    owner_name            => 'Qisutu Agent',
    responsible_name      => '-',
    created_at_display    => '18.07.2026 10:00:00',
    changed_at_display    => '18.07.2026 12:00:00',
};

my $LongBody = join ' ', ('This is a deliberately long printable article body.') x 180;
my $Articles = [
    {
        id                     => 41,
        article_number         => 1,
        subject                => 'Customer request',
        body                   => '<p>Hello support,</p><p>' . $LongBody . '</p>',
        content_type           => 'text/html',
        visibility             => 'both',
        visibility_label_display => 'Agent and customer',
        sender_name            => 'Erika Example',
        from_name              => 'Erika Example',
        from_email             => 'erika@example.invalid',
        to_email               => 'support@example.invalid',
        channel                => 'email',
        created_at_display     => '18.07.2026 10:00:00',
        attachments            => [ { filename=>'photo.jpg', filesize=>2048 } ],
    },
    {
        id                     => 42,
        article_number         => 2,
        subject                => 'Internal check',
        body                   => "Internal note\nSecond line",
        content_type           => 'text/plain',
        visibility             => 'agent',
        visibility_label_display => 'Agents only',
        sender_name            => 'Qisutu Agent',
        channel                => 'note',
        created_at_display     => '18.07.2026 11:00:00',
        attachments            => [],
    },
];

my %Labels = (
    Ticket=>'Ticket',Queue=>'Queue',Status=>'Status',Priority=>'Priority',Customer=>'Customer',Contact=>'Contact',
    Email=>'E-mail',Owner=>'Owner',Responsible=>'Responsible',CreatedAt=>'Created',ChangedAt=>'Changed',
    Article=>'Article',From=>'From',To=>'To',Cc=>'Cc',Channel=>'Channel',Visibility=>'Visibility',
    VisibilityAgent=>'Agents only',VisibilityBoth=>'Agent and customer',Attachments=>'Attachments',
    AllArticlesTitle=>'Vollständiges Ticket',SingleArticleTitle=>'Single article',Internal=>'Agents only / internal',
    NoArticles=>'No articles',EmptyArticle=>'(Empty article)',Page=>'Page',GeneratedAt=>'Generated at',
);

my $Object = QisutuTicketPDF->new();
my $PDF = $Object->Create(
    Ticket=>$Ticket,Articles=>$Articles,Labels=>\%Labels,SystemName=>'Qisutu',LogoPath=>$Logo,
    GeneratedAt=>'2026-07-18 12:30:00',SingleArticle=>0,
);
ok( $PDF, 'complete ticket PDF is created' );
like( $PDF, qr{\A%PDF-1\.4}, 'ticket export is a PDF 1.4 document' );
like( $PDF, qr{/Subtype /Image}, 'ticket PDF embeds the local Qisutu logo' );
like( $PDF, qr{/Filter /DCTDecode}, 'embedded logo uses the PDF JPEG image filter' );
like( $PDF, qr{/Count ([2-9]|[1-9][0-9]+)\b}, 'long ticket is split across multiple PDF pages' );
like( $PDF, qr{Agents only / internal}, 'internal articles are clearly labelled' );
like( $PDF, qr{Vollst\xE4ndiges Ticket}, 'European characters are encoded correctly for the PDF font' );
like( $PDF, qr{photo\.jpg}, 'attachment names are included in the PDF' );
like( $PDF, qr{\nxref\n}, 'ticket PDF contains a cross-reference table' );
cmp_ok( length($PDF), '>', 10_000, 'ticket PDF contains ticket, article and logo data' );

my $SinglePDF = $Object->Create(
    Ticket=>$Ticket,Articles=>[ $Articles->[1] ],Labels=>\%Labels,SystemName=>'Qisutu',LogoPath=>$Logo,
    GeneratedAt=>'2026-07-18 12:30:00',SingleArticle=>1,
);
like( $SinglePDF, qr{Single article}, 'single article PDF is labelled accordingly' );
unlike( $SinglePDF, qr{photo\.jpg}, 'single article PDF does not contain data from other articles' );

{
    package Local::TicketPrintOutput;
    sub new { bless {}, shift }
    sub Translate {
        my ( $Self, %Param ) = @_;
        return $Param{Key} || '';
    }
    sub Response {
        my ( $Self, %Param ) = @_;
        return \%Param;
    }

    package Local::TicketPrintTicketObject;
    sub new { bless { Ticket=>$_[1],Articles=>$_[2],All=>0 }, $_[0] }
    sub TicketGet { return $_[0]->{Ticket} }
    sub ArticleList {
        my ( $Self, %Param ) = @_;
        $Self->{All} = $Param{All} ? 1 : 0;
        return $Self->{Articles};
    }
}

package main;

my $FakeTicketObject = Local::TicketPrintTicketObject->new( $Ticket, $Articles );
my $Zoom = AgentTicketZoom->new(
    Config=>{
        System=>{Name=>'Qisutu'},Language=>{Default=>'de'},
        Paths=>{Static=>"$Root/var/static"},
    },
    Output=>Local::TicketPrintOutput->new(),
);
my $Download = $Zoom->_TicketPrintResponse(
    TicketObject=>$FakeTicketObject,TicketID=>$Ticket->{id},ArticleID=>$Articles->[0]->{id},
    User=>{account_type=>'agent',user_account_id=>7},Language=>'de',
);
ok( $FakeTicketObject->{All}, 'ticket print loads all articles without the ticket zoom display limit' );
is( $Download->{Response}->{ContentType}, 'application/pdf', 'ticket zoom returns a PDF download response' );
like( $Download->{Response}->{Headers}->[0], qr{qisutu-ticket-202607180017-article-1\.pdf}, 'single article gets a clear PDF filename' );
like( $Download->{Response}->{Body}, qr{\A%PDF-1\.4}, 'ticket zoom response contains the generated PDF' );
my $Denied = $Zoom->_TicketPrintResponse(
    TicketObject=>$FakeTicketObject,TicketID=>$Ticket->{id},
    User=>{account_type=>'customer',user_account_id=>8},Language=>'de',
);
ok( $Denied->{Redirect}, 'customer accounts cannot use the agent ticket print endpoint' );

my %IntegrationPattern = (
    'core/output/AgentTicketZoom.tt' => qr{Step=TicketPrint},
    'core/module/AgentTicketZoom.pm' => qr{All\s*=>\s*1},
    'core/system/QisutuTicket.pm'    => qr{my \$All\s*=},
);
for my $Path ( sort keys %IntegrationPattern ) {
    open my $FH, '<:raw', "$Root/$Path" or die $!;
    local $/;
    my $Content = <$FH>;
    close $FH;
    like( $Content, $IntegrationPattern{$Path}, "$Path contains ticket print integration" );
}

for my $Language (qw(de en fr it)) {
    my $Translations = do "$Root/core/language/$Language.pm";
    ok( ref $Translations eq 'HASH', "$Language translations load" );
    ok( $Translations->{TicketPrintWhole}, "$Language contains ticket print translations" );
}

done_testing();
