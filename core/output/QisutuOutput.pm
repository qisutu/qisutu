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

package QisutuOutput;

use strict;
use warnings;
use utf8;

use Encode qw(encode);
use File::Spec;

sub new {
    my ( $Class, %Param ) = @_;

    my $Self = {
        Config    => $Param{Config},
        LastError => '',
    };

    bless $Self, $Class;

    return $Self;
}

sub Render {
    my ( $Self, %Param ) = @_;

    my $Template = $Param{Template} || '';
    my $Data     = $Param{Data}     || {};
    my $Head      = $Param{Head}     || 'Head.tt';
    my $Header    = $Param{Header}   || 'Header.tt';
    my $Footer    = $Param{Footer}   || 'Footer.tt';

    if ( !$Template ) {
        $Self->{LastError} = 'Template is required';
        return;
    }

    my $Content = '';

    for my $TemplateFile ( $Head, $Header, $Template, $Footer ) {
        my $Part = $Self->_TemplateLoad(
            Template => $TemplateFile,
            Data     => $Data,
        );

        if ( !defined $Part ) {
            return;
        }

        $Content .= $Part;
    }

    $Content = $Self->_CSRFFieldsInject(
        Content => $Content,
        Token   => $Data->{CSRFToken} || '',
    );

    return $Content;
}

sub RenderSingle {
    my ( $Self, %Param ) = @_;

    my $Template = $Param{Template} || '';
    my $Data     = $Param{Data}     || {};

    if ( !$Template ) {
        $Self->{LastError} = 'Template is required';
        return;
    }

    my $Content = $Self->_TemplateLoad(
        Template => $Template,
        Data     => $Data,
    );

    return if !defined $Content;

    return $Self->_CSRFFieldsInject(
        Content => $Content,
        Token   => $Data->{CSRFToken} || '',
    );
}

sub Response {
    my ( $Self, %Param ) = @_;

    my $Body        = defined $Param{Body} ? $Param{Body} : '';
    my $Status      = $Param{Status}      || '200 OK';
    my $ContentType = $Param{ContentType} || 'text/html; charset=UTF-8';
    my $Cookie      = $Param{Cookie}      || '';
    my $Headers     = ref $Param{Headers} eq 'ARRAY' ? $Param{Headers} : [];

    if ( $ContentType =~ m{\Atext/}i && $ContentType !~ m{charset=}i ) {
        $ContentType .= '; charset=UTF-8';
    }

    my @Header;

    push @Header, "Status: $Status";
    push @Header, "Content-Type: $ContentType";

    my %Existing = map {
        my ($Name) = split /:/, $_ || '', 2;
        ( lc( $Name || '' ) => 1 )
    } @{$Headers};

    push @Header, 'X-Content-Type-Options: nosniff' if !$Existing{'x-content-type-options'};
    push @Header, 'Referrer-Policy: strict-origin-when-cross-origin' if !$Existing{'referrer-policy'};
    push @Header, 'X-Frame-Options: DENY' if !$Existing{'x-frame-options'} && !$Param{AllowFrame};
    push @Header, 'Permissions-Policy: camera=(), microphone=(), geolocation=()' if !$Existing{'permissions-policy'};
    if ( ( $ENV{HTTPS} || '' ) eq 'on' && !$Existing{'strict-transport-security'} ) {
        push @Header, 'Strict-Transport-Security: max-age=31536000';
    }

    if ($Cookie) {
        push @Header, "Set-Cookie: $Cookie";
    }

    for my $ExtraHeader ( @{$Headers} ) {
        next if !defined $ExtraHeader;
        $ExtraHeader =~ s{\r|\n}{}g;
        next if $ExtraHeader !~ m{\A[A-Za-z0-9\-]+:\s*.+\z};
        push @Header, $ExtraHeader;
    }

    if ( utf8::is_utf8($Body) ) {
        $Body = encode( 'UTF-8', $Body );
    }

    return join( "\r\n", @Header ) . "\r\n\r\n" . $Body;
}

sub Redirect {
    my ( $Self, %Param ) = @_;

    my $Location = $Param{Location} || '';
    my $Cookie   = $Param{Cookie}   || '';

    if ( !$Location ) {
        $Self->{LastError} = 'Redirect location is required';
        return;
    }

    my @Header;

    push @Header, 'Status: 302 Found';
    push @Header, "Location: $Location";
    push @Header, 'X-Content-Type-Options: nosniff';
    push @Header, 'Referrer-Policy: strict-origin-when-cross-origin';
    push @Header, 'X-Frame-Options: DENY';
    push @Header, 'Permissions-Policy: camera=(), microphone=(), geolocation=()';
    if ( ( $ENV{HTTPS} || '' ) eq 'on' ) {
        push @Header, 'Strict-Transport-Security: max-age=31536000';
    }

    if ($Cookie) {
        push @Header, "Set-Cookie: $Cookie";
    }

    return join( "\r\n", @Header ) . "\r\n\r\n";
}

sub CookieCreate {
    my ( $Self, %Param ) = @_;

    my $Name     = $Param{Name}     || '';
    my $Value    = $Param{Value}    || '';
    my $MaxAge   = $Param{MaxAge}   || 0;
    my $Path     = $Param{Path}     || '/';
    my $SameSite = $Param{SameSite} || 'Lax';
    my $Secure   = $Param{Secure}   || 0;
    my $HttpOnly = exists $Param{HttpOnly} ? $Param{HttpOnly} : 1;

    if ( !$Name ) {
        $Self->{LastError} = 'Cookie name is required';
        return;
    }

    my @Parts;

    push @Parts, $Name . '=' . $Self->_CookieEscape($Value);
    push @Parts, "Path=$Path";

    if ($MaxAge) {
        push @Parts, "Max-Age=$MaxAge";
    }

    if ($HttpOnly) {
        push @Parts, 'HttpOnly';
    }

    if ($Secure) {
        push @Parts, 'Secure';
    }

    push @Parts, "SameSite=$SameSite";

    return join '; ', @Parts;
}

sub CookieDelete {
    my ( $Self, %Param ) = @_;

    my $Name = $Param{Name} || '';
    my $Path = $Param{Path} || '/';

    if ( !$Name ) {
        $Self->{LastError} = 'Cookie name is required';
        return;
    }

    return join '; ',
        $Name . '=',
        "Path=$Path",
        'Max-Age=0',
        'HttpOnly',
        'SameSite=Lax';
}

sub _CSRFFieldsInject {
    my ( $Self, %Param ) = @_;

    my $Content = defined $Param{Content} ? $Param{Content} : '';
    my $Token   = $Param{Token} || '';
    return $Content if !$Token;

    my $Escaped = $Self->HTMLEscape($Token);
    $Content =~ s{
        (<form\b(?=[^>]*\bmethod\s*=\s*["']?post\b)[^>]*>)
        (?!\s*<input\b[^>]*\bname\s*=\s*["']CSRFToken["'])
    }{$1 . '<input type="hidden" name="CSRFToken" value="' . $Escaped . '">'}egix;

    return $Content;
}

sub _FileRead {
    my ( $Self, %Param ) = @_;

    my $File = $Param{File};
    my $FileHandle;

    if ( !open $FileHandle, '<:encoding(UTF-8)', $File ) {
        $Self->{LastError} = "Could not read file: $File";
        return;
    }

    local $/;
    my $Content = <$FileHandle>;

    close $FileHandle;

    return $Content;
}

sub _TemplateLoad {
    my ( $Self, %Param ) = @_;

    my $Template = $Param{Template} || '';
    my $Data     = $Param{Data}     || {};

    if ( !$Template ) {
        $Self->{LastError} = 'Template file is required';
        return;
    }

    if ( $Template =~ m{\.\.} || $Template =~ m{^/} ) {
        $Self->{LastError} = 'Invalid template name';
        return;
    }

    my $OutputPath = $Self->{Config}->{Paths}->{Output};
    my $File       = File::Spec->catfile( $OutputPath, $Template );

    if ( !-f $File ) {
        $Self->{LastError} = "Template not found: $Template";
        return;
    }

    my $Content = $Self->_FileRead( File => $File );

    if ( !defined $Content ) {
        return;
    }

    return $Self->_TemplateReplace(
        Content => $Content,
        Data    => $Data,
    );
}

sub _TemplateReplace {
    my ( $Self, %Param ) = @_;

    my $Content  = $Param{Content} || '';
    my $Data     = $Param{Data}    || {};
    my $Language = $Data->{Language} || $Self->{Config}->{Language}->{Default} || 'en';

    # Remove Template Toolkit style comments before any template processing.
    # Qisutu uses its own small template engine, therefore comment handling
    # must be implemented explicitly.
    $Content =~ s{\[\%\s*\#.*?\%\]}{}gs;

    $Content = $Self->_TemplateForeach(
        Content => $Content,
        Data    => $Data,
    );

    $Content = $Self->_TemplateIf(
        Content => $Content,
        Data    => $Data,
    );

    $Content =~ s{\[\%\s*Translate\.([A-Za-z0-9_]+)\s*\%\]}{
        $Self->_Translate(
            Key      => $1,
            Language => $Language,
        )
    }gex;

    $Content =~ s{\[\%\s*RAW\.([A-Za-z0-9_]+)\s*\%\]}{
        $Self->_ValueTranslate(
            Value    => exists $Data->{$1} && defined $Data->{$1} ? $Data->{$1} : '',
            Language => $Language,
        )
    }gex;

    $Content =~ s{\[\%\s*([A-Za-z0-9_]+)\s*\%\]}{
        $Self->_HTMLEscape(
            $Self->_ValueTranslate(
                Value    => exists $Data->{$1} && defined $Data->{$1} ? $Data->{$1} : '',
                Language => $Language,
            )
        )
    }gex;

    return $Content;
}

sub _TemplateIf {
    my ( $Self, %Param ) = @_;

    my $Content = $Param{Content} || '';
    my $Data    = $Param{Data}    || {};
    my $Pos     = 0;

    my ( $Rendered ) = $Self->_TemplateIfParse(
        Content => $Content,
        Data    => $Data,
        PosRef  => \$Pos,
        Stop    => {},
    );

    return $Rendered;
}

sub _TemplateIfParse {
    my ( $Self, %Param ) = @_;

    my $Content = $Param{Content} || '';
    my $Data    = $Param{Data}    || {};
    my $PosRef  = $Param{PosRef};
    my $Stop    = $Param{Stop}    || {};
    my $Output  = '';

    $$PosRef ||= 0;

    while ( $$PosRef < length $Content ) {
        pos($Content) = $$PosRef;

        if ( $Content !~ m{\[\%\s*(IF\s+([A-Za-z0-9_]+)|ELSE|END)\s*\%\]}gc ) {
            $Output .= substr( $Content, $$PosRef );
            $$PosRef = length $Content;
            last;
        }

        my $TagStart = $-[0];
        my $TagEnd   = $+[0];
        my $Tag      = $1;
        my $Key      = $2 || '';

        $Output .= substr( $Content, $$PosRef, $TagStart - $$PosRef );
        $$PosRef = $TagEnd;

        if ( $Tag =~ m{\AIF\s+} ) {
            my ( $TruePart, $StopTag ) = $Self->_TemplateIfParse(
                Content => $Content,
                Data    => $Data,
                PosRef  => $PosRef,
                Stop    => {
                    ELSE => 1,
                    END  => 1,
                },
            );

            my $FalsePart = '';

            if ( $StopTag eq 'ELSE' ) {
                my ( $ParsedFalsePart ) = $Self->_TemplateIfParse(
                    Content => $Content,
                    Data    => $Data,
                    PosRef  => $PosRef,
                    Stop    => {
                        END => 1,
                    },
                );

                $FalsePart = $ParsedFalsePart;
            }

            $Output .= $Data->{$Key} ? $TruePart : $FalsePart;
            next;
        }

        if ( $Tag eq 'ELSE' || $Tag eq 'END' ) {
            if ( $Stop->{$Tag} ) {
                return ( $Output, $Tag );
            }

            $Output .= substr( $Content, $TagStart, $TagEnd - $TagStart );
            next;
        }
    }

    return ( $Output, '' );
}

sub _TemplateForeach {
    my ( $Self, %Param ) = @_;

    my $Content = $Param{Content} || '';
    my $Data    = $Param{Data}    || {};

    while (
        $Content =~ s{
            \[\%\s*FOREACH\s+([A-Za-z0-9_]+)\s+IN\s+([A-Za-z0-9_]+)\s*\%\]
            (.*?)
            \[\%\s*END\s*\%\]
        }{
            my $ItemName = $1;
            my $ListName = $2;
            my $Block    = defined $3 ? $3 : '';
            my $List     = $Data->{$ListName};
            my $HTML     = '';

            if ( ref $List eq 'ARRAY' ) {
                for my $Item ( @{$List} ) {
                    next if ref $Item ne 'HASH';

                    my $Part = $Block;

                    $Part =~ s{\[\%\s*RAW\.\Q$ItemName\E\.([A-Za-z0-9_]+)\s*\%\]}{
                        my $Value = exists $Item->{$1} && defined $Item->{$1} ? $Item->{$1} : '';
                        $Self->_ValueTranslate(
                            Value    => $Value,
                            Language => $Data->{Language} || $Self->{Config}->{Language}->{Default} || 'en',
                        );
                    }gex;

                    $Part =~ s{\[\%\s*\Q$ItemName\E\.([A-Za-z0-9_]+)\s*\%\]}{
                        my $Value = exists $Item->{$1} && defined $Item->{$1} ? $Item->{$1} : '';
                        $Self->_HTMLEscape(
                            $Self->_ValueTranslate(
                                Value    => $Value,
                                Language => $Data->{Language} || $Self->{Config}->{Language}->{Default} || 'en',
                            )
                        );
                    }gex;

                    $HTML .= $Self->_TemplateReplace(
                        Content => $Part,
                        Data    => $Data,
                    );
                }
            }

            $HTML;
        }gsex
        )
    {
    }

    return $Content;
}

sub _ValueTranslate {
    my ( $Self, %Param ) = @_;

    my $Value    = $Param{Value};
    my $Language = $Param{Language} || 'en';

    $Value = '' if !defined $Value;

    if ( $Value =~ m{\ATranslate:([A-Za-z0-9_]+)\z} ) {
        return $Self->_Translate(
            Key      => $1,
            Language => $Language,
        );
    }

    return $Value;
}

sub _Translate {
    my ( $Self, %Param ) = @_;

    my $Key      = $Param{Key}      || '';
    my $Language = $Param{Language} || 'en';

    return '' if !$Key;

    my $LanguageData = $Self->_LanguageData( Language => $Language );

    if ( $LanguageData && exists $LanguageData->{$Key} ) {
        return $LanguageData->{$Key};
    }

    if ( $Language ne 'en' ) {
        my $EnglishData = $Self->_LanguageData( Language => 'en' );

        if ( $EnglishData && exists $EnglishData->{$Key} ) {
            return $EnglishData->{$Key};
        }
    }

    return $Key;
}

sub _LanguageData {
    my ( $Self, %Param ) = @_;

    my $Language = $Param{Language} || 'en';

    $Language =~ s/[^A-Za-z0-9_-]//g;

    if ( !$Language ) {
        $Language = 'en';
    }

    $Self->{LanguageCache} ||= {};

    if ( exists $Self->{LanguageCache}->{$Language} ) {
        return $Self->{LanguageCache}->{$Language};
    }

    my $LanguagePath = $Self->{Config}->{Paths}->{Language};
    my $File         = File::Spec->catfile( $LanguagePath, "$Language.pm" );

    if ( !-f $File ) {
        $Self->{LanguageCache}->{$Language} = {};
        return $Self->{LanguageCache}->{$Language};
    }

    my $Data = do $File;

    if ( !$Data || ref $Data ne 'HASH' ) {
        $Self->{LanguageCache}->{$Language} = {};
        return $Self->{LanguageCache}->{$Language};
    }

    $Self->{LanguageCache}->{$Language} = $Data;

    return $Self->{LanguageCache}->{$Language};
}

sub _HTMLEscape {
    my ( $Self, $Value ) = @_;

    $Value = '' if !defined $Value;

    $Value =~ s/&/&amp;/g;
    $Value =~ s/</&lt;/g;
    $Value =~ s/>/&gt;/g;
    $Value =~ s/"/&quot;/g;
    $Value =~ s/'/&#39;/g;

    return $Value;
}

sub HTMLEscape {
    my ( $Self, $Value ) = @_;

    return $Self->_HTMLEscape($Value);
}

sub Translate {
    my ( $Self, %Param ) = @_;

    return $Self->_Translate(%Param);
}

sub _CookieEscape {
    my ( $Self, $Value ) = @_;

    $Value = '' if !defined $Value;

    $Value =~ s/([^A-Za-z0-9_\-\.~])/sprintf("%%%02X", ord($1))/eg;

    return $Value;
}

sub Error {
    my ($Self) = @_;

    return $Self->{LastError};
}

1;
