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

package QisutuTicketPDF;

use strict;
use warnings;
use utf8;

use Encode qw(decode encode FB_CROAK FB_DEFAULT);
use QisutuHTML;

sub new {
    my ( $Class, %Param ) = @_;

    return bless {
        Config    => $Param{Config} || {},
        LastError => '',
    }, $Class;
}

sub Error {
    my ($Self) = @_;
    return $Self->{LastError} || '';
}

sub Create {
    my ( $Self, %Param ) = @_;

    $Self->{LastError} = '';

    my $Ticket   = $Param{Ticket} || {};
    my $Articles = ref $Param{Articles} eq 'ARRAY' ? $Param{Articles} : [];
    my $Labels   = ref $Param{Labels} eq 'HASH' ? $Param{Labels} : {};

    if ( !$Ticket->{id} || !$Ticket->{ticket_number} ) {
        $Self->{LastError} = 'Valid ticket data is required';
        return;
    }

    my $Logo = $Self->_JPEGRead( Path => $Param{LogoPath} );
    my $State = {
        Pages       => [],
        Content     => '',
        Y           => 0,
        Ticket      => $Ticket,
        Labels      => $Labels,
        SystemName  => $Param{SystemName} || 'Qisutu',
        GeneratedAt => $Param{GeneratedAt} || '',
        Single      => $Param{SingleArticle} ? 1 : 0,
        Logo        => $Logo,
    };

    $Self->_PageStart( State => $State );
    $Self->_TicketSummary( State => $State );

    if ( !@{$Articles} ) {
        $Self->_EnsureSpace( State => $State, Height => 48 );
        $Self->_TextBlock(
            State => $State,
            Text  => $Labels->{NoArticles} || 'No articles are available.',
            X     => 32,
            Width => 531,
            Size  => 10,
            Color => [ 0.35, 0.42, 0.49 ],
        );
    }
    else {
        for my $Index ( 0 .. $#{$Articles} ) {
            $Self->_Article(
                State   => $State,
                Article => $Articles->[$Index],
                Index   => $Index + 1,
                Count   => scalar @{$Articles},
            );
        }
    }

    $Self->_PageFinish( State => $State );
    $Self->_FootersAdd( State => $State );

    return $Self->_PDFBuild(
        Pages => $State->{Pages},
        Logo  => $Logo,
        Title => ( $Ticket->{ticket_number} || '' ) . ' - ' . ( $Ticket->{title} || '' ),
    );
}

sub _TicketSummary {
    my ( $Self, %Param ) = @_;

    my $State  = $Param{State};
    my $Ticket = $State->{Ticket};
    my $Label  = $State->{Labels};

    $Self->_TextBlock(
        State => $State,
        Text  => ( $Label->{Ticket} || 'Ticket' ) . ' ' . ( $Ticket->{ticket_number} || '' ),
        X     => 32,
        Width => 531,
        Size  => 18,
        Bold  => 1,
        Color => [ 0.05, 0.11, 0.16 ],
        Gap   => 2,
    );
    $Self->_TextBlock(
        State => $State,
        Text  => $Ticket->{title} || '-',
        X     => 32,
        Width => 531,
        Size  => 11,
        Bold  => 1,
        Color => [ 0.19, 0.25, 0.31 ],
        Gap   => 9,
    );

    my @Meta = (
        [ $Label->{Queue}       || 'Queue',       $Ticket->{queue_full_name} || $Ticket->{queue_name} || '-' ],
        [ $Label->{Status}      || 'Status',      $Ticket->{state_name_display} || $Ticket->{state_name} || '-' ],
        [ $Label->{Priority}    || 'Priority',    $Ticket->{priority_name_display} || $Ticket->{priority_name} || '-' ],
        [ $Label->{Customer}    || 'Customer',    $Ticket->{customer_name} || '-' ],
        [ $Label->{Contact}     || 'Contact',     $Ticket->{customer_user_name} || '-' ],
        [ $Label->{Email}       || 'E-mail',      $Ticket->{customer_user_email} || '-' ],
        [ $Label->{Owner}       || 'Owner',       $Ticket->{owner_name} || '-' ],
        [ $Label->{Responsible} || 'Responsible', $Ticket->{responsible_name} || '-' ],
        [ $Label->{CreatedAt}   || 'Created',     $Ticket->{created_at_display} || $Ticket->{created_at} || '-' ],
        [ $Label->{ChangedAt}   || 'Changed',     $Ticket->{changed_at_display} || $Ticket->{changed_at} || '-' ],
    );

    $Self->_EnsureSpace( State => $State, Height => 116 );
    my $StartY = $State->{Y};
    $State->{Content} .= $Self->_Rect( 32, $StartY - 104, 531, 104, 0.965, 0.975, 0.982 );
    $State->{Content} .= $Self->_StrokeRect( 32, $StartY - 104, 531, 104, 0.82, 0.87, 0.91 );

    for my $Index ( 0 .. $#Meta ) {
        my $Column = $Index % 2;
        my $Row    = int( $Index / 2 );
        my $X      = 44 + $Column * 260;
        my $Y      = $StartY - 16 - $Row * 19;
        $State->{Content} .= $Self->_Text( $X, $Y, 7.2, $Meta[$Index]->[0], 1, 0.38, 0.44, 0.50 );
        $State->{Content} .= $Self->_Text( $X + 78, $Y, 8.2, $Self->_Truncate( $Meta[$Index]->[1], 39 ), 0, 0.10, 0.15, 0.20 );
    }
    $State->{Y} = $StartY - 120;

    $Self->_TextBlock(
        State => $State,
        Text  => $State->{Single}
            ? ( $Label->{SingleArticleTitle} || 'Single article' )
            : ( $Label->{AllArticlesTitle} || 'Complete ticket' ),
        X     => 32,
        Width => 531,
        Size  => 13,
        Bold  => 1,
        Color => [ 0.015, 0.31, 0.41 ],
        Gap   => 8,
    );
}

sub _Article {
    my ( $Self, %Param ) = @_;

    my $State   = $Param{State};
    my $Article = $Param{Article} || {};
    my $Label   = $State->{Labels};
    my $Internal = ( $Article->{visibility} || '' ) eq 'agent' ? 1 : 0;

    $Self->_EnsureSpace( State => $State, Height => 94 );

    my $HeaderY = $State->{Y};
    my @Background = $Internal ? ( 1.00, 0.94, 0.90 ) : ( 0.91, 0.96, 0.98 );
    my @Border     = $Internal ? ( 0.95, 0.43, 0.25 ) : ( 0.64, 0.80, 0.86 );
    $State->{Content} .= $Self->_Rect( 32, $HeaderY - 44, 531, 44, @Background );
    $State->{Content} .= $Self->_StrokeRect( 32, $HeaderY - 44, 531, 44, @Border );

    my $ArticleNumber = $Article->{article_number} || $Article->{id} || $Param{Index};
    my $Heading = ( $Label->{Article} || 'Article' ) . ' ' . $ArticleNumber;
    if ($Internal) {
        $Heading .= ' · ' . ( $Label->{Internal} || 'Internal' );
    }
    $State->{Content} .= $Self->_Text( 44, $HeaderY - 16, 9, $Heading, 1, 0.04, 0.18, 0.24 );
    $State->{Content} .= $Self->_Text( 44, $HeaderY - 32, 8.2, $Self->_Truncate( $Article->{subject} || '-', 78 ), 1, 0.18, 0.23, 0.29 );
    $State->{Content} .= $Self->_Text( 442, $HeaderY - 16, 7.2, $Self->_Truncate( $Article->{created_at_display} || $Article->{created_at} || '-', 24 ), 0, 0.38, 0.44, 0.50 );
    $State->{Y} = $HeaderY - 54;

    my $From = $Article->{from_name} || $Article->{sender_name} || $Article->{from_email} || '-';
    if ( $Article->{from_email} && $From !~ m{\Q$Article->{from_email}\E} ) {
        $From .= ' <' . $Article->{from_email} . '>';
    }
    my $To = $Article->{to_name} || $Article->{to_email} || $Article->{recipient} || '-';
    if ( $Article->{to_email} && $To !~ m{\Q$Article->{to_email}\E} ) {
        $To .= ' <' . $Article->{to_email} . '>';
    }
    my $Visibility = $Article->{visibility_label_display}
        || ( $Internal ? ( $Label->{VisibilityAgent} || 'Agents only' ) : ( $Label->{VisibilityBoth} || 'Agents and customers' ) );

    my @Meta = (
        ( $Label->{From} || 'From' ) . ': ' . $From,
        ( $Label->{To} || 'To' ) . ': ' . $To,
        ( $Label->{Channel} || 'Channel' ) . ': ' . ( $Article->{channel} || '-' )
            . ' · ' . ( $Label->{Visibility} || 'Visibility' ) . ': ' . $Visibility,
    );
    push @Meta, ( $Label->{Cc} || 'Cc' ) . ': ' . $Article->{cc} if $Article->{cc};

    for my $Line (@Meta) {
        $Self->_TextBlock(
            State => $State,
            Text  => $Line,
            X     => 44,
            Width => 507,
            Size  => 7.8,
            Color => [ 0.33, 0.39, 0.45 ],
            Gap   => 1,
        );
    }
    $State->{Y} -= 5;

    my $Body = $Self->_ArticlePlainText( Article => $Article );
    $Body = $Label->{EmptyArticle} || '(empty article)' if $Body !~ m{\S};
    $Self->_TextBlock(
        State => $State,
        Text  => $Body,
        X     => 44,
        Width => 507,
        Size  => 9,
        Color => [ 0.08, 0.12, 0.16 ],
        Gap   => 4,
    );

    my $Attachments = ref $Article->{attachments} eq 'ARRAY' ? $Article->{attachments} : [];
    if ( @{$Attachments} ) {
        my @Names = map {
            my $Name = $_->{filename} || $_->{Filename} || 'attachment';
            my $Size = $_->{content_size} || $_->{filesize} || $_->{size} || $_->{Size} || 0;
            $Name . ( $Size ? ' (' . $Self->_FileSize($Size) . ')' : '' );
        } @{$Attachments};
        $Self->_TextBlock(
            State => $State,
            Text  => ( $Label->{Attachments} || 'Attachments' ) . ': ' . join( ', ', @Names ),
            X     => 44,
            Width => 507,
            Size  => 7.8,
            Bold  => 1,
            Color => [ 0.24, 0.31, 0.37 ],
            Gap   => 3,
        );
    }

    $State->{Content} .= $Self->_Line( 32, $State->{Y}, 563, $State->{Y}, 0.84, 0.88, 0.91, 0.7 );
    $State->{Y} -= 16;
}

sub _ArticlePlainText {
    my ( $Self, %Param ) = @_;

    my $Article = $Param{Article} || {};
    my $Text    = $Article->{body} || '';

    if ( ( $Article->{content_type} || '' ) =~ m{text/html}i || $Text =~ m{<[^>]+>} ) {
        $Text =~ s{<!--.*?-->}{}gs;
        $Text =~ s{<\s*(?:script|style|iframe|object|embed)[^>]*>.*?<\s*/\s*(?:script|style|iframe|object|embed)\s*>}{}gsi;
        $Text =~ s{<\s*br\s*/?\s*>}{\n}gi;
        $Text =~ s{<\s*/\s*(?:p|div|li|tr|h[1-6]|blockquote|pre|table)\s*>}{\n}gi;
        $Text =~ s{<\s*li\b[^>]*>}{- }gi;
        $Text =~ s{<[^>]+>}{ }g;
        my @Line;
        for my $Line ( split /\n/, $Text, -1 ) {
            $Line = QisutuHTML->PlainTextSearch($Line);
            push @Line, $Line;
        }
        $Text = join "\n", @Line;
    }

    $Text =~ s{\r\n|\r}{\n}g;
    $Text =~ s{[\t ]+}{ }g;
    $Text =~ s{\n[\t ]+}{\n}g;
    $Text =~ s{\n{4,}}{\n\n\n}g;
    $Text =~ s{\A\s+|\s+\z}{}g;

    return $Text;
}

sub _TextBlock {
    my ( $Self, %Param ) = @_;

    my $State      = $Param{State};
    my $Text       = defined $Param{Text} ? "$Param{Text}" : '';
    my $X          = $Param{X} || 32;
    my $Width      = $Param{Width} || 531;
    my $Size       = $Param{Size} || 9;
    my $LineHeight = $Param{LineHeight} || $Size * 1.35;
    my $Color      = $Param{Color} || [ 0, 0, 0 ];
    my $MaxChars   = int( $Width / ( $Size * 0.52 ) );
    $MaxChars = 12 if $MaxChars < 12;

    my @Lines = $Self->_Wrap( Text => $Text, Max => $MaxChars );
    @Lines = ('') if !@Lines;

    for my $Line (@Lines) {
        $Self->_EnsureSpace( State => $State, Height => $LineHeight + 2 );
        $State->{Content} .= $Self->_Text(
            $X,
            $State->{Y} - $Size,
            $Size,
            $Line,
            $Param{Bold} ? 1 : 0,
            @{$Color},
        );
        $State->{Y} -= $LineHeight;
    }
    $State->{Y} -= defined $Param{Gap} ? $Param{Gap} : 2;
}

sub _Wrap {
    my ( $Self, %Param ) = @_;

    my $Text = defined $Param{Text} ? "$Param{Text}" : '';
    my $Max  = $Param{Max} || 80;
    my @Out;

    for my $Paragraph ( split /\n/, $Text, -1 ) {
        if ( $Paragraph eq '' ) {
            push @Out, '';
            next;
        }

        my @Word = split /\s+/, $Paragraph;
        my $Line = '';
        for my $Word (@Word) {
            while ( length($Word) > $Max ) {
                if ($Line) {
                    push @Out, $Line;
                    $Line = '';
                }
                push @Out, substr( $Word, 0, $Max, '' );
            }
            if ( !$Line ) {
                $Line = $Word;
            }
            elsif ( length($Line) + 1 + length($Word) <= $Max ) {
                $Line .= ' ' . $Word;
            }
            else {
                push @Out, $Line;
                $Line = $Word;
            }
        }
        push @Out, $Line if length $Line;
    }

    return @Out;
}

sub _EnsureSpace {
    my ( $Self, %Param ) = @_;

    my $State  = $Param{State};
    my $Height = $Param{Height} || 20;
    return if $State->{Y} - $Height >= 48;

    $Self->_PageFinish( State => $State );
    $Self->_PageStart( State => $State );
}

sub _PageStart {
    my ( $Self, %Param ) = @_;

    my $State = $Param{State};
    my $Label = $State->{Labels};
    $State->{Content} = '';

    $State->{Content} .= $Self->_Rect( 0, 778, 595, 64, 0.004, 0.314, 0.408 );
    $State->{Content} .= $Self->_Rect( 24, 787, 46, 46, 1, 1, 1 );
    $State->{Content} .= $Self->_StrokeRect( 24, 787, 46, 46, 0.82, 0.90, 0.93 );
    if ( $State->{Logo} ) {
        $State->{Content} .= "q 40 0 0 40 27 790 cm /Logo Do Q\n";
    }
    $State->{Content} .= $Self->_Text( 82, 811, 17, $State->{SystemName}, 1, 1, 1, 1 );
    $State->{Content} .= $Self->_Text(
        82,
        792,
        8.5,
        $State->{Single}
            ? ( $Label->{SingleArticleTitle} || 'Single article' )
            : ( $Label->{AllArticlesTitle} || 'Complete ticket' ),
        0,
        0.82,
        0.93,
        0.96,
    );
    $State->{Content} .= $Self->_Text( 430, 811, 8.5, $State->{Ticket}->{ticket_number} || '', 1, 1, 1, 1 );
    $State->{Y} = 758;
}

sub _PageFinish {
    my ( $Self, %Param ) = @_;

    my $State = $Param{State};
    return if !defined $State->{Content} || $State->{Content} eq '';

    push @{ $State->{Pages} }, $State->{Content};
    $State->{Content} = '';
}

sub _FootersAdd {
    my ( $Self, %Param ) = @_;

    my $State = $Param{State};
    my $Count = scalar @{ $State->{Pages} };
    my $Label = $State->{Labels};
    for my $Index ( 0 .. $#{ $State->{Pages} } ) {
        my $Footer = ( $State->{SystemName} || 'Qisutu' )
            . ' · ' . ( $State->{Ticket}->{ticket_number} || '' )
            . ' · ' . ( $Label->{Page} || 'Page' ) . ' ' . ( $Index + 1 ) . '/' . $Count;
        if ( $State->{GeneratedAt} ) {
            $Footer .= ' · ' . ( $Label->{GeneratedAt} || 'Generated' ) . ' ' . $State->{GeneratedAt};
        }
        $State->{Pages}->[$Index] .= $Self->_Line( 32, 35, 563, 35, 0.84, 0.88, 0.91, 0.6 );
        $State->{Pages}->[$Index] .= $Self->_Text( 32, 21, 7, $Footer, 0, 0.42, 0.47, 0.52 );
    }
}

sub _JPEGRead {
    my ( $Self, %Param ) = @_;

    my $Path = $Param{Path} || '';
    return if !$Path || !-f $Path || !-r $Path;

    open my $FH, '<:raw', $Path or return;
    local $/;
    my $Data = <$FH>;
    close $FH;
    return if !defined $Data || substr( $Data, 0, 2 ) ne "\xFF\xD8";

    my ( $Width, $Height, $Components );
    my $Offset = 2;
    while ( $Offset + 9 < length $Data ) {
        $Offset++ while $Offset < length($Data) && ord( substr( $Data, $Offset, 1 ) ) != 0xFF;
        last if $Offset + 4 >= length $Data;
        $Offset++ while $Offset < length($Data) && ord( substr( $Data, $Offset, 1 ) ) == 0xFF;
        last if $Offset >= length $Data;
        my $Marker = ord substr( $Data, $Offset, 1 );
        $Offset++;
        next if $Marker == 0xD8 || $Marker == 0xD9;
        last if $Marker == 0xDA;
        last if $Offset + 2 > length $Data;
        my $Length = unpack 'n', substr( $Data, $Offset, 2 );
        last if $Length < 2 || $Offset + $Length > length $Data;
        if ( $Marker =~ m{\A(?:192|193|194|195|197|198|199|201|202|203|205|206|207)\z} ) {
            $Height     = unpack 'n', substr( $Data, $Offset + 3, 2 );
            $Width      = unpack 'n', substr( $Data, $Offset + 5, 2 );
            $Components = ord substr( $Data, $Offset + 7, 1 );
            last;
        }
        $Offset += $Length;
    }

    return if !$Width || !$Height || !$Components;
    return {
        Data       => $Data,
        Width      => $Width,
        Height     => $Height,
        Components => $Components,
    };
}

sub _PDFBuild {
    my ( $Self, %Param ) = @_;

    my @PageContent = @{ $Param{Pages} || [] };
    my $Logo        = $Param{Logo};
    my @Objects;
    push @Objects, '<< /Type /Catalog /Pages 2 0 R >>';

    my $FirstPageID = $Logo ? 6 : 5;
    my @Kids = map { ( $FirstPageID + $_ * 2 ) . ' 0 R' } 0 .. $#PageContent;
    push @Objects, '<< /Type /Pages /Kids [' . join( ' ', @Kids ) . '] /Count ' . scalar(@Kids) . ' >>';
    push @Objects, '<< /Type /Font /Subtype /Type1 /BaseFont /Helvetica /Encoding /WinAnsiEncoding >>';
    push @Objects, '<< /Type /Font /Subtype /Type1 /BaseFont /Helvetica-Bold /Encoding /WinAnsiEncoding >>';

    if ($Logo) {
        my $ColorSpace = ( $Logo->{Components} || 3 ) == 1 ? '/DeviceGray' : '/DeviceRGB';
        push @Objects,
            '<< /Type /XObject /Subtype /Image /Width ' . $Logo->{Width}
            . ' /Height ' . $Logo->{Height}
            . ' /ColorSpace ' . $ColorSpace
            . ' /BitsPerComponent 8 /Filter /DCTDecode /Length ' . bytes::length( $Logo->{Data} ) . " >>\nstream\n"
            . $Logo->{Data} . "\nendstream";
    }

    for my $Index ( 0 .. $#PageContent ) {
        my $PageID   = $FirstPageID + $Index * 2;
        my $StreamID = $PageID + 1;
        my $Resources = '/Font << /F1 3 0 R /F2 4 0 R >>';
        $Resources .= ' /XObject << /Logo 5 0 R >>' if $Logo;
        push @Objects,
            '<< /Type /Page /Parent 2 0 R /MediaBox [0 0 595 842] /Resources << '
            . $Resources . ' >> /Contents ' . $StreamID . ' 0 R >>';
        push @Objects,
            '<< /Length ' . bytes::length( $PageContent[$Index] ) . " >>\nstream\n"
            . $PageContent[$Index] . "\nendstream";
    }

    my $PDF = "%PDF-1.4\n%\xE2\xE3\xCF\xD3\n";
    my @Offsets = (0);
    for my $Index ( 0 .. $#Objects ) {
        push @Offsets, bytes::length($PDF);
        $PDF .= ( $Index + 1 ) . " 0 obj\n" . $Objects[$Index] . "\nendobj\n";
    }
    my $XRef = bytes::length($PDF);
    $PDF .= "xref\n0 " . ( scalar(@Objects) + 1 ) . "\n0000000000 65535 f \n";
    for my $Index ( 1 .. $#Offsets ) {
        $PDF .= sprintf "%010d 00000 n \n", $Offsets[$Index];
    }
    $PDF .= "trailer\n<< /Size " . ( scalar(@Objects) + 1 ) . " /Root 1 0 R >>\nstartxref\n$XRef\n%%EOF\n";

    return $PDF;
}

sub _Text {
    my ( $Self, $X, $Y, $Size, $Text, $Bold, $R, $G, $B ) = @_;
    $R //= 0;
    $G //= 0;
    $B //= 0;
    return sprintf(
        '%.3f %.3f %.3f rg BT /F%s %.2f Tf %.2f %.2f Td (%s) Tj ET' . "\n",
        $R, $G, $B, $Bold ? 2 : 1, $Size, $X, $Y, $Self->_PDFText($Text),
    );
}

sub _Rect {
    my ( $Self, $X, $Y, $W, $H, $R, $G, $B ) = @_;
    return sprintf '%.3f %.3f %.3f rg %.2f %.2f %.2f %.2f re f' . "\n", $R, $G, $B, $X, $Y, $W, $H;
}

sub _StrokeRect {
    my ( $Self, $X, $Y, $W, $H, $R, $G, $B ) = @_;
    return sprintf '%.3f %.3f %.3f RG %.2f %.2f %.2f %.2f re S' . "\n", $R, $G, $B, $X, $Y, $W, $H;
}

sub _Line {
    my ( $Self, $X1, $Y1, $X2, $Y2, $R, $G, $B, $Width ) = @_;
    return sprintf '%.3f %.3f %.3f RG %.2f w %.2f %.2f m %.2f %.2f l S' . "\n", $R, $G, $B, $Width || 1, $X1, $Y1, $X2, $Y2;
}

sub _PDFText {
    my ( $Self, $Value ) = @_;
    $Value = '' if !defined $Value;
    $Value = "$Value";
    if ( !utf8::is_utf8($Value) && $Value =~ m{[\x80-\xFF]} ) {
        my $Decoded = eval { decode( 'UTF-8', $Value, FB_CROAK ) };
        $Value = $Decoded if defined $Decoded;
    }
    $Value = encode( 'cp1252', $Value, FB_DEFAULT ) if utf8::is_utf8($Value);
    $Value =~ s{\\}{\\\\}g;
    $Value =~ s{\(}{\\(}g;
    $Value =~ s{\)}{\\)}g;
    $Value =~ s{\r|\n}{ }g;
    return $Value;
}

sub _Truncate {
    my ( $Self, $Value, $Length ) = @_;
    $Value = '' if !defined $Value;
    $Value =~ s{\s+}{ }g;
    return length($Value) > $Length ? substr( $Value, 0, $Length - 1 ) . '…' : $Value;
}

sub _FileSize {
    my ( $Self, $Bytes ) = @_;
    $Bytes ||= 0;
    return $Bytes . ' B' if $Bytes < 1024;
    return sprintf '%.1f KB', $Bytes / 1024 if $Bytes < 1024 * 1024;
    return sprintf '%.1f MB', $Bytes / ( 1024 * 1024 );
}

1;
