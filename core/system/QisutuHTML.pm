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

    # Leere Absätze und <br>-Folgen gehören zum verfassten Mailinhalt.
    # Sie dürfen weder gelöscht noch gekürzt werden, auch nicht vor oder
    # hinter Bildern. Die Sicherheitsfilterung erfolgt separat in Sanitize.
    $HTML =~ s{\A\s+}{};
    $HTML =~ s{\s+\z}{};

    return $HTML;
}

sub Sanitize {
    my ( $Class, $HTML ) = @_;

    $HTML = '' if !defined $HTML;

    # Rebuild markup from individual tokens. Every literal angle bracket in
    # text is escaped, including malformed tags. Removing a token therefore
    # cannot join its neighbours into a new, unchecked HTML tag.
    $HTML =~ s/\x00//g;
    my %Void = map { $_ => 1 } qw(br hr img);
    my %Allowed = map { $_ => 1 } qw(
        a b blockquote br code div em figcaption figure h2 h3 h4 h5 h6 hr i img
        li ol p pre s span strong table tbody td th thead tr u ul
    );

    my %DropContent = map { $_ => 1 } qw(
        script style iframe object form button textarea select option template
        svg math xmp noembed noframes noscript plaintext title
    );
    my %RawText = map { $_ => 1 } qw(
        script style iframe textarea xmp noembed noframes noscript plaintext title
    );
    my $Result = '';
    my $Position = 0;
    my $Length = length $HTML;
    my $SkipTag = '';
    my $SkipDepth = 0;

    while ( $Position < $Length ) {
        if ( $SkipTag && $RawText{$SkipTag} ) {
            pos($HTML) = $Position;
            last if $HTML !~ m{</\Q$SkipTag\E(?=[\s/>])[^>]*>}gi;
            $Position = pos($HTML);
            $SkipTag = '';
            $SkipDepth = 0;
            next;
        }
        my $Start = index( $HTML, '<', $Position );
        $Start = $Length if $Start < 0;
        if ( !$SkipTag ) {
            $Result .= $Class->_HTMLTextEscape( substr( $HTML, $Position, $Start - $Position ) );
        }
        last if $Start == $Length;
        $Position = $Start;

        if ( substr( $HTML, $Start, 4 ) eq '<!--' ) {
            pos($HTML) = $Start + 4;
            $Position = $HTML =~ /--!?>/g ? pos($HTML) : $Length;
            next;
        }

        pos($HTML) = $Start;
        if ( $HTML !~ m{\G<(/?)([a-zA-Z][a-zA-Z0-9:_-]*)(?=[\s/>])}gc ) {
            $Result .= '&lt;' if !$SkipTag;
            $Position++;
            next;
        }
        my ( $Close, $Tag ) = ( $1, lc $2 );
        my $AttributeStart = pos($HTML);
        my $End = $AttributeStart;
        my $Complete = 0;

        # Quotes can contain angle brackets. Scan each input character at
        # most once, even for incomplete or deliberately malformed tags.
        while ( $End < $Length ) {
            my $Character = substr( $HTML, $End, 1 );
            if ( $Character eq '"' || $Character eq "'" ) {
                my $QuoteEnd = index( $HTML, $Character, $End + 1 );
                $End = $QuoteEnd < 0 ? $Length : $QuoteEnd + 1;
                next;
            }
            last if $Character eq '<';
            if ( $Character eq '>' ) {
                $Complete = 1;
                last;
            }
            $End++;
        }

        if (!$Complete) {
            $Result .= $Class->_HTMLTextEscape( substr( $HTML, $Start, $End - $Start ) ) if !$SkipTag;
            $Position = $End;
            next;
        }
        $Position = $End + 1;
        if ($SkipTag) {
            if ( $Tag eq $SkipTag ) {
                $SkipDepth += $Close ? -1 : 1;
                $SkipTag = '' if !$SkipDepth;
            }
            next;
        }
        if ( $DropContent{$Tag} && !$Close ) {
            $SkipTag = $Tag;
            $SkipDepth = 1;
            next;
        }
        next if !$Allowed{$Tag};
        if ($Close) {
            $Result .= "</$Tag>" if !$Void{$Tag};
            next;
        }
        my $Attr = substr( $HTML, $AttributeStart, $End - $AttributeStart );
        $Result .= '<' . $Tag . $Class->_CleanAttributes( Tag => $Tag, Attr => $Attr ) . '>';
    }

    return $Result;
}

sub _HTMLTextEscape {
    my ( $Class, $Text ) = @_;
    # Keep character references and authored whitespace unchanged. Decoding
    # text entities cannot produce markup in the browser's HTML tokenizer.
    $Text =~ s/</&lt;/g;
    $Text =~ s/>/&gt;/g;
    return $Text;
}

sub PlainTextSearch {
    my ( $Class, $Content ) = @_;

    $Content = '' if !defined $Content;
    $Content =~ s{<!--.*?-->}{ }gs;
    $Content =~ s{<\s*(script|style|iframe|object|embed)[^>]*>.*?<\s*/\s*\1\s*>}{ }gsi;
    $Content =~ s{<\s*br\s*/?\s*>}{\n}gi;
    $Content =~ s{<\s*/\s*(?:p|div|li|tr|h[1-6]|blockquote|pre)\s*>}{\n}gi;
    $Content =~ s{<[^>]+>}{ }g;
    $Content = $Class->_EntityDecode($Content);
    $Content =~ s{\s+}{ }g;
    $Content =~ s{\A\s+|\s+\z}{}g;

    return $Content;
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

sub _CleanAttributes {
    my ( $Class, %Param ) = @_;

    my $Tag  = $Param{Tag}  || '';
    my $Attr = $Param{Attr} || '';
    my @Clean;
    my %Seen;

    while ( $Attr =~ m{([a-zA-Z0-9:_-]+)\s*=\s*(?:"([^"]*)"|'([^']*)'|([^\s"'>]+))}g ) {
        my $Name  = lc $1;
        my $Value = defined $2 ? $2 : defined $3 ? $3 : defined $4 ? $4 : '';

        next if $Name =~ m{\Aon};
        next if $Seen{$Name}++;
        $Value = $Class->_AttributeEntityDecode($Value);

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
            if ( $Name eq 'href' ) {
                $Value = $Class->_SafeURL( Value => $Value, Image => 0 );
                next if !defined $Value;
            }
            $Value = '_blank' if $Name eq 'target' && $Value ne '_self';
            $Value = 'noopener noreferrer' if $Name eq 'rel';
            push @Clean, $Name . '="' . $Class->_Escape($Value) . '"';
            next;
        }

        if ( $Tag eq 'img' && ( $Name eq 'src' || $Name eq 'alt' || $Name eq 'width' || $Name eq 'height' ) ) {
            if ( $Name eq 'src' ) {
                $Value = $Class->_SafeURL( Value => $Value, Image => 1 );
                next if !defined $Value;
            }
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

sub _AttributeEntityDecode {
    my ( $Class, $Value ) = @_;
    my %Named = (
        amp => '&', lt => '<', gt => '>', quot => '"', apos => "'",
        AMP => '&', LT => '<', GT => '>', QUOT => '"',
        colon => ':', Tab => "\t", NewLine => "\n", nbsp => chr(160),
    );
    # Decode once, just as an HTML attribute is parsed once. Remaining
    # unknown references are escaped on output and cannot become a scheme.
    $Value =~ s{&(?:\#(x[0-9a-f]+|[0-9]+);?|([A-Za-z][A-Za-z0-9]+);)}{
        my ( $Number, $Name ) = ( $1, $2 );
        if (defined $Number) {
            my $Hex = $Number =~ s/^x//i;
            $Number =~ s/^0+//;
            my $Code = length($Number) > ( $Hex ? 6 : 7 ) ? 0xfffd
                : $Hex ? hex($Number || '0') : 0 + ($Number || 0);
            $Code > 0 && $Code <= 0x10ffff && !( $Code >= 0xd800 && $Code <= 0xdfff )
                ? chr($Code) : chr(0xfffd);
        }
        else {
            exists $Named{$Name} ? $Named{$Name} : '&' . $Name . ';';
        }
    }gexi;
    return $Value;
}

sub _SafeURL {
    my ( $Class, %Param ) = @_;
    my $Value = $Param{Value};
    # Browsers remove embedded ASCII tabs/newlines before reading a scheme.
    # Reject all controls instead of checking only a literal "javascript:".
    return if $Value =~ /[\x00-\x1f\x7f]/;
    $Value =~ s/\A +| +\z//g;
    if ( $Value =~ m{\A([a-z][a-z0-9+.-]*):}i ) {
        my $Scheme = lc $1;
        my %Allowed = $Param{Image}
            ? map { $_ => 1 } qw(http https cid)
            : map { $_ => 1 } qw(http https mailto tel ftp);
        if ( $Param{Image} && $Scheme eq 'data' ) {
            return $Value if $Value =~ m{\Adata:image/(?:png|jpe?g|gif|webp|bmp|x-icon|vnd\.microsoft\.icon|avif);base64,[a-z0-9+/]*={0,2}\z}i;
            return;
        }
        return if !$Allowed{$Scheme};
    }
    else {
        # Relative URLs have no colon in their first path component. This
        # also rejects obfuscated/invalid schemes rather than guessing.
        return if $Value =~ m{\A[^/?\#]*:};
    }
    return $Value;
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
