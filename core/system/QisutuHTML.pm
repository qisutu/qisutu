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

package QisutuHTML;

use strict;
use warnings;
use utf8;

sub IncomingNormalize {
    my ( $Class, $HTML ) = @_;

    $HTML = '' if !defined $HTML;
    $HTML =~ s{\r\n}{\n}g;
    $HTML =~ s{\r}{\n}g;
    $HTML =~ s{\x00}{}g;

    $HTML = $Class->_BodyExtract($HTML);
    $HTML = $Class->_MailScaffoldRemove($HTML);
    $HTML = $Class->_ClientMailClassNormalize($HTML);
    $HTML = $Class->_MailQuoteNormalize($HTML);

    # Antwortköpfe ohne echte Blockquote-Struktur werden ausschließlich beim
    # Import neuer E-Mails markiert. Alte gespeicherte Artikel werden beim
    # Anzeigen nicht nachträglich umgebaut.
    $HTML = $Class->_MailQuoteMarkerWrap($HTML);

    $HTML = $Class->_SignatureWrap($HTML);
    $HTML = $Class->_EmptyBlockClean($HTML);
    $HTML = $Class->_ImageSpacingNormalize($HTML);
    $HTML = $Class->_WhitespaceNormalize($HTML);

    return $HTML;
}

sub Sanitize {
    my ( $Class, $HTML ) = @_;

    $HTML = '' if !defined $HTML;

    $HTML =~ s{<!--.*?-->}{}gs;
    $HTML =~ s{<\s*(script|style|iframe|object|embed|link|meta|base|form|input|button|textarea|select|option)[^>]*>.*?<\s*/\s*\1\s*>}{}gsi;
    $HTML =~ s{<\s*/?\s*(script|style|iframe|object|embed|link|meta|base|form|input|button|textarea|select|option)[^>]*>}{}gsi;

    my %Void = map { $_ => 1 } qw(br img);
    my %Allowed = map { $_ => 1 } qw(
        a b blockquote br code div em figcaption figure h2 h3 h4 h5 h6 hr i img
        li ol p pre s span strong table tbody td th thead tr u ul
    );

    $HTML =~ s{<\s*(/)?\s*([a-zA-Z0-9]+)([^>]*)>}{
        my $Close = $1 || '';
        my $Tag   = lc $2;
        my $Attr  = defined $3 ? $3 : '';

        if ( !$Allowed{$Tag} ) {
            '';
        }
        elsif ($Close) {
            $Void{$Tag} ? '' : "</$Tag>";
        }
        else {
            my $CleanAttr = $Class->_CleanAttributes( Tag => $Tag, Attr => $Attr );
            $Void{$Tag} ? "<$Tag$CleanAttr>" : "<$Tag$CleanAttr>";
        }
    }gex;

    return $HTML;
}

sub PlainTextPreview {
    my ( $Class, $HTML, $Limit ) = @_;

    $HTML  = '' if !defined $HTML;
    $Limit = 120 if !$Limit;

    $HTML =~ s{<\s*br\s*/?\s*>}{ }gi;
    $HTML =~ s{<[^>]+>}{ }g;
    $HTML = $Class->_EntityDecode($HTML);
    $HTML =~ s{\s+}{ }g;
    $HTML =~ s{\A\s+|\s+\z}{}g;

    if ( length $HTML > $Limit ) {
        $HTML = substr( $HTML, 0, $Limit - 3 ) . '...';
    }

    return $HTML;
}

sub PlainTextToHTML {
    my ( $Class, $Text ) = @_;

    $Text = '' if !defined $Text;
    $Text = $Class->_Escape($Text);
    $Text =~ s{\r\n|\r|\n}{<br>}g;

    return $Text;
}

sub _BodyExtract {
    my ( $Class, $HTML ) = @_;

    $HTML ||= '';

    if ( $HTML =~ m{<\s*body\b[^>]*>(.*?)<\s*/\s*body\s*>}is ) {
        return $1;
    }

    return $HTML;
}

sub _MailScaffoldRemove {
    my ( $Class, $HTML ) = @_;

    $HTML ||= '';
    $HTML =~ s{<!DOCTYPE[^>]*>}{}gis;
    $HTML =~ s{<\s*head\b[^>]*>.*?<\s*/\s*head\s*>}{}gis;
    $HTML =~ s{<\s*title\b[^>]*>.*?<\s*/\s*title\s*>}{}gis;
    $HTML =~ s{<\s*meta\b[^>]*>}{}gis;

    return $HTML;
}

sub _ClientMailClassNormalize {
    my ( $Class, $HTML ) = @_;

    $HTML ||= '';

    # Signaturen aus verbreiteten Mailclients normalisieren, damit die
    # Qisutu-Anzeige sie einheitlich dezenter rendern kann.
    $HTML =~ s{\bclass\s*=\s*(["'])(?=[^"']*\bmoz-signature\b)[^"']*\1}{class="qisutu-mail-signature"}gix;
    $HTML =~ s{\bclass\s*=\s*(["'])(?=[^"']*\b(?:gmail_signature|AppleMailSignature)\b)[^"']*\1}{class="qisutu-mail-signature"}gix;

    # Antwort-/Weiterleitungszitate aus Mailclients normalisieren. Nach dem
    # Sanitizing bleiben nur Qisutu-eigene Klassen erhalten. Dadurch werden
    # alte Mailteile im Ticket wieder wie in Mailprogrammen optisch maskiert.
    $HTML =~ s{\bclass\s*=\s*(["'])(?=[^"']*\bmoz-cite-prefix\b)[^"']*\1}{class="qisutu-mail-quote-head"}gix;
    $HTML =~ s{\bclass\s*=\s*(["'])(?=[^"']*\b(?:gmail_quote|gmail_attr|yahoo_quoted|WordSection1)\b)[^"']*\1}{class="qisutu-mail-quote-wrap"}gix;

    return $HTML;
}

sub DisplayNormalize {
    my ( $Class, $HTML ) = @_;

    $HTML = '' if !defined $HTML;

    # Keine Reparatur/Maskierung beim Anzeigen. Eingehende Mails werden beim
    # Import normalisiert; vorhandene gespeicherte Artikel bleiben unverändert.
    return $HTML;
}

sub _MailQuoteNormalize {
    my ( $Class, $HTML ) = @_;

    $HTML ||= '';

    # Vorhandene Blockquote-Strukturen aus Mailprogrammen eindeutig als
    # Mailzitat kennzeichnen. Ohne globale Kontextsuche, damit große Mails
    # mit Bildern nicht hängen bleiben.
    $HTML =~ s{<\s*blockquote\b([^>]*)>}{
        my $Attr = $1 || '';
        if ( $Attr =~ m{\bclass\s*=\s*(["'])([^"']*)\1}i ) {
            my $Quote = $2;
            if ( $Quote !~ m{\bqisutu-mail-quote\b} ) {
                $Attr =~ s{\bclass\s*=\s*(["'])([^"']*)\1}{class="$2 qisutu-mail-quote"}i;
            }
            '<blockquote' . $Attr . '>';
        }
        else {
            '<blockquote class="qisutu-mail-quote"' . $Attr . '>';
        }
    }gexis;

    # Bekannte Mailclient-Klassen zusätzlich normalisieren.
    $HTML =~ s{\bclass\s*=\s*(["'])(?=[^"']*\bmoz-cite-prefix\b)[^"']*\1}{class="qisutu-mail-quote-head"}gix;
    $HTML =~ s{\bclass\s*=\s*(["'])(?=[^"']*\b(?:gmail_quote|gmail_attr|yahoo_quoted)\b)[^"']*\1}{class="qisutu-mail-quote-wrap"}gix;

    return $HTML;
}

sub _MailQuoteMarkerWrap {
    my ( $Class, $HTML ) = @_;

    $HTML ||= '';

    return $HTML if $HTML =~ m{qisutu-mail-quote-head|qisutu-mail-quote-wrap}i;

    # Fallback für neu importierte Antworten ohne klare Mailclient-Klasse.
    # Diese Funktion wird nicht mehr beim Anzeigen vorhandener Artikel genutzt.
    my $QuoteHead = qr{\b(?:Am|On)\b[^<\n]{0,240}?(?:schrieb|wrote)[^:<\n]{0,80}:}i;

    return $HTML if $HTML !~ m{$QuoteHead};

    my $Start = $-[0];
    my $End   = $+[0];

    return $HTML if !defined $Start || !defined $End || $End <= $Start;

    my $Before = substr( $HTML, 0, $Start );
    my $Head   = substr( $HTML, $Start, $End - $Start );
    my $After  = substr( $HTML, $End );

    $After =~ s{\A\s*(?:<\s*br\s*/?\s*>\s*)?}{}i;
    return $HTML if $After !~ m{\S};

    # Die Originalstruktur möglichst erhalten: Wenn direkt ein vorhandenes
    # Blockquote folgt, wird nur der Kopf markiert, nicht nochmals gekapselt.
    if ( $After =~ m{\A\s*<\s*blockquote\b}i ) {
        return $Before
            . '<div class="qisutu-mail-quote-head">' . $Head . '</div>'
            . $After;
    }

    return $Before
        . '<div class="qisutu-mail-quote-head">' . $Head . '</div>'
        . '<blockquote class="qisutu-mail-quote">' . $After . '</blockquote>';
}

sub _SignatureWrap {
    my ( $Class, $HTML ) = @_;

    $HTML ||= '';

    return $HTML if $HTML =~ m{qisutu-mail-signature}i;

    if ( $HTML =~ s{(<\s*(?:p|div|span)\b[^>]*>\s*--\s*<\s*/\s*(?:p|div|span)\s*>)(.*)\z}{<div class="qisutu-mail-signature">$1$2</div>}is ) {
        return $HTML;
    }

    if ( $HTML =~ s{(?:<\s*br\s*/?\s*>\s*)?--\s*<\s*br\s*/?\s*>(.*)\z}{<div class="qisutu-mail-signature">--<br>$1</div>}is ) {
        return $HTML;
    }

    return $HTML;
}

sub _EmptyBlockClean {
    my ( $Class, $HTML ) = @_;

    $HTML ||= '';

    for ( 1 .. 12 ) {
        last if $HTML !~ s{<\s*(p|div)\b[^>]*>(?:\s|&nbsp;|&#160;|<\s*br\s*/?\s*>)*<\s*/\s*\1\s*>}{}gis;
    }

    return $HTML;
}

sub _ImageSpacingNormalize {
    my ( $Class, $HTML ) = @_;

    $HTML ||= '';

    for ( 1 .. 6 ) {
        $HTML =~ s{(?:\s|&nbsp;|&#160;|<\s*br\s*/?\s*>|<\s*(?:p|div)\b[^>]*>\s*<\s*/\s*(?:p|div)\s*>)+(?=<\s*img\b)}{}gis;
        $HTML =~ s{(<\s*img\b[^>]*>)(?:\s|&nbsp;|&#160;|<\s*br\s*/?\s*>|<\s*(?:p|div)\b[^>]*>\s*<\s*/\s*(?:p|div)\s*>)+}{$1<br>}gis;
    }

    return $HTML;
}

sub _WhitespaceNormalize {
    my ( $Class, $HTML ) = @_;

    $HTML ||= '';
    $HTML =~ s{(?:\s*<\s*br\s*/?\s*>\s*){3,}}{<br><br>}gis;
    $HTML =~ s{\A\s+}{};
    $HTML =~ s{\s+\z}{};

    return $HTML;
}

sub _CleanAttributes {
    my ( $Class, %Param ) = @_;

    my $Tag  = $Param{Tag}  || '';
    my $Attr = $Param{Attr} || '';
    my @Clean;

    while ( $Attr =~ m{([a-zA-Z0-9:_-]+)\s*=\s*(?:"([^"]*)"|'([^']*)'|([^\s"'>]+))}g ) {
        my $Name  = lc $1;
        my $Value = defined $2 ? $2 : defined $3 ? $3 : defined $4 ? $4 : '';

        next if $Name =~ m{\Aon};

        if ( $Name eq 'style' ) {
            my $Style = $Class->_CleanStyle($Value);
            push @Clean, 'style="' . $Class->_Escape($Style) . '"' if $Style;
            next;
        }

        if ( $Name eq 'class' ) {
            my %AllowedClass = map { $_ => 1 } qw(
                qisutu-mail-signature
                qisutu-mail-quote
                qisutu-mail-quote-head
                qisutu-mail-quote-wrap
            );
            my @ClassList = grep { $AllowedClass{$_} } split m{\s+}, $Value;
            push @Clean, 'class="' . join( ' ', @ClassList ) . '"' if @ClassList;
            next;
        }

        if ( $Tag eq 'a' && ( $Name eq 'href' || $Name eq 'target' || $Name eq 'rel' ) ) {
            next if $Name eq 'href' && $Value =~ m{\A\s*(?:javascript|data):}i;
            $Value = '_blank' if $Name eq 'target' && $Value ne '_self';
            $Value = 'noopener noreferrer' if $Name eq 'rel';
            push @Clean, $Name . '="' . $Class->_Escape($Value) . '"';
            next;
        }

        if ( $Tag eq 'img' && ( $Name eq 'src' || $Name eq 'alt' || $Name eq 'width' || $Name eq 'height' ) ) {
            next if $Name eq 'src' && $Value =~ m{\A\s*javascript:}i;
            next if ( $Name eq 'width' || $Name eq 'height' ) && $Value !~ m{\A\d{1,4}\z};
            push @Clean, $Name . '="' . $Class->_Escape($Value) . '"';
            next;
        }

        if ( ( $Tag eq 'th' || $Tag eq 'td' ) && ( $Name eq 'colspan' || $Name eq 'rowspan' ) ) {
            next if $Value !~ m{\A\d{1,2}\z};
            push @Clean, $Name . '="' . $Class->_Escape($Value) . '"';
            next;
        }
    }

    return @Clean ? ' ' . join( ' ', @Clean ) : '';
}

sub _CleanStyle {
    my ( $Class, $Style ) = @_;

    $Style = '' if !defined $Style;
    return '' if $Style =~ m{(?:expression|url\s*\(|javascript:)}i;

    my @Clean;
    for my $Part ( split /;/, $Style ) {
        my ( $Name, $Value ) = split /:/, $Part, 2;
        next if !defined $Name || !defined $Value;

        $Name  =~ s{\A\s+|\s+\z}{}g;
        $Value =~ s{\A\s+|\s+\z}{}g;
        $Name = lc $Name;

        if ( $Name eq 'text-align' ) {
            next if $Value !~ m{\A(?:left|right|center|justify)\z}i;
            push @Clean, "$Name: $Value";
            next;
        }

        if ( $Name eq 'font-weight' ) {
            next if $Value !~ m{\A(?:normal|bold|[1-9]00)\z}i;
            push @Clean, "$Name: $Value";
            next;
        }

        if ( $Name eq 'font-family' ) {
            next if $Value !~ m{\A[A-Za-z0-9 ,\-_'\"]{1,120}\z};
            push @Clean, "$Name: $Value";
            next;
        }

        if ( $Name eq 'color' || $Name eq 'background-color' || $Name eq 'background' ) {
            next if $Value !~ m{\A(?:#[0-9a-f]{3,8}|rgb\([0-9,\s.]+\)|rgba\([0-9,\s.]+\)|hsl\([0-9,\s.%]+\)|hsla\([0-9,\s.%]+\)|[a-z]+)\z}i;
            push @Clean, "$Name: $Value";
            next;
        }

        if ( $Name eq 'line-height' ) {
            next if $Value !~ m{\A(?:[0-9](?:\.[0-9]+)?|[0-9]{1,3}(?:\.[0-9]+)?(?:px|em|rem|%))\z}i;
            push @Clean, "$Name: $Value";
            next;
        }

        if ( $Name =~ m{\A(?:font-size|height|margin|margin-top|margin-right|margin-bottom|margin-left|padding|padding-top|padding-right|padding-bottom|padding-left)\z} ) {
            next if $Value !~ m{\A(?:0|[0-9]{1,3}(?:\.[0-9]+)?(?:px|em|rem|%))(?:\s+(?:0|[0-9]{1,3}(?:\.[0-9]+)?(?:px|em|rem|%))){0,3}\z}i;
            push @Clean, "$Name: $Value";
            next;
        }

        if ( $Name =~ m{\A(?:border|border-left|border-top|border-right|border-bottom)\z} ) {
            next if $Value !~ m{\A(?:0|[0-9]{1,2}px\s+(?:solid|dashed|dotted)\s+(?:#[0-9a-f]{3,8}|[a-z]+))\z}i;
            push @Clean, "$Name: $Value";
            next;
        }
    }

    return join '; ', @Clean;
}

sub _EntityDecode {
    my ( $Class, $Text ) = @_;

    $Text =~ s/&nbsp;/ /g;
    $Text =~ s/&amp;/&/g;
    $Text =~ s/&lt;/</g;
    $Text =~ s/&gt;/>/g;
    $Text =~ s/&quot;/"/g;
    $Text =~ s/&#39;/'/g;

    return $Text;
}

sub _Escape {
    my ( $Class, $Value ) = @_;

    $Value = '' if !defined $Value;
    $Value =~ s/&/&amp;/g;
    $Value =~ s/</&lt;/g;
    $Value =~ s/>/&gt;/g;
    $Value =~ s/"/&quot;/g;
    $Value =~ s/'/&#39;/g;

    return $Value;
}

1;
