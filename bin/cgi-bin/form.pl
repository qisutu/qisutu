#!/usr/bin/env perl

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

use Cwd qw(abs_path);
use Encode qw(decode);
use File::Spec;
use FindBin;

my $QisutuHome = $ENV{QISUTU_HOME} || abs_path( File::Spec->catdir( $FindBin::Bin, '..', '..' ) );
$ENV{QISUTU_HOME} ||= $QisutuHome;

unshift @INC,
    File::Spec->catdir( $QisutuHome, 'core', 'config' ),
    File::Spec->catdir( $QisutuHome, 'core', 'system' ),
    File::Spec->catdir( $QisutuHome, 'core', 'output' );

main();

sub main {
    my $InstallLock = File::Spec->catfile( $QisutuHome, 'var', 'install', 'installed.lock' );
    if ( $ENV{GATEWAY_INTERFACE} && !-f $InstallLock ) {
        print "Status: 302 Found\r\nLocation: install.pl\r\nCache-Control: no-store\r\n\r\n";
        return;
    }
    my $UpdateLock = File::Spec->catfile( $QisutuHome, 'var', 'install', 'update.lock' );
    if ( -e $UpdateLock ) {
        print _PlainResponse( Status => '503 Service Unavailable', Body => 'Qisutu is being updated.' );
        return;
    }

    my $Request = _RequestParams();
    my $Language = _LanguageClean( $Request->{Language} );

    my $Loaded = eval {
        require QisutuConfig;
        require QisutuDB;
        require QisutuOutput;
        require QisutuSystemSetting;
        require QisutuTicketForm;
        1;
    };
    if ( !$Loaded ) {
        print _PlainResponse( Status => '500 Internal Server Error', Body => 'Qisutu could not be started.' );
        return;
    }

    my $Config = QisutuConfig::Load();
    $Language ||= _LanguageClean( $Config->{Language}->{Default} ) || 'en';
    my $Output = QisutuOutput->new( Config => $Config );
    my $DB = QisutuDB->new( Config => $Config );
    my $FormObject = QisutuTicketForm->new(
        Config => $Config,
        DB     => $DB,
        Output => $Output,
    );
    my $SettingObject = QisutuSystemSetting->new( Config => $Config, DB => $DB );
    my $AttachmentMaxSizeMB = $SettingObject->AttachmentMaxSizeMB();

    my $Slug = ref $Request->{Form} ? '' : ( $Request->{Form} || '' );
    my $Form = $FormObject->FormGet( Slug => $Slug, Language => $Language );
    if ( !$Form && $DB->Error() ) {
        print _PlainResponse( Status => '500 Internal Server Error', Body => 'The form could not be loaded.' );
        return;
    }
    if ( !$Form || !$Form->{active} || ( $Form->{form_type} || '' ) ne 'public' ) {
        my $Body = $Output->RenderSingle(
            Template => 'PublicTicketForm.tt',
            Data     => {
                Language       => $Language,
                StaticBase     => $Config->{Paths}->{StaticURL} || '/qisutu/static',
                SystemName     => $Config->{System}->{Name} || 'Qisutu',
                NotFound       => 1,
                FormError      => 'Translate:PublicTicketFormNotFound',
                FormErrorClass => '',
            },
        );
        print _HTMLResponse( Output => $Output, Status => '404 Not Found', Body => $Body, FrameAncestors => "'none'" );
        return;
    }

    my $FormTranslations = $FormObject->FormTranslationList( FormID => $Form->{id} );
    my $DefaultLanguage = _LanguageClean( $Config->{Language}->{Default} ) || 'en';
    my @FormLanguages = grep {
        my $Row = $FormTranslations->{$_};
        ref $Row eq 'HASH' && defined $Row->{title} && $Row->{title} ne '';
    } keys %{$FormTranslations};
    @FormLanguages = sort {
        ( $a eq $DefaultLanguage ? 0 : 1 ) <=> ( $b eq $DefaultLanguage ? 0 : 1 )
            || $a cmp $b
    } @FormLanguages;
    my $LanguageLinks = [ map {
        {
            code          => uc($_),
            url           => 'form.pl?Form=' . $Slug . '&Language=' . $_,
            active_class  => $_ eq $Language ? 'qisutu-public-form-language-active' : '',
            aria_current  => $_ eq $Language ? 'aria-current="page"' : '',
        }
    } @FormLanguages ];

    my $Success = 0;
    my $TicketNumber = '';
    my $Confirmation = '';
    my $FormError = '';

    if ( ( $ENV{REQUEST_METHOD} || '' ) eq 'POST'
        && ( $Request->{Step} || '' ) eq 'PublicTicketFormSubmit'
    ) {
        my $Created = $FormObject->SubmissionCreate(
            Context   => 'public',
            FormID    => $Form->{id},
            Request   => $Request,
            Language  => $Language,
            IPAddress => $ENV{REMOTE_ADDR} || '',
            UserAgent => $ENV{HTTP_USER_AGENT} || '',
            Attachments => _UploadedAttachments( Request => $Request ),
        );
        if ($Created) {
            $Success      = 1;
            $TicketNumber = $Created->{TicketNumber} || '';
            $Confirmation = $Created->{ConfirmationText}
                || 'Translate:TicketFormConfirmationDefault';
        }
        else {
            $FormError = $FormObject->Error() || 'Translate:TicketCreateFailed';
        }
    }

    my $FieldsHTML = $Success ? '' : $FormObject->FieldsHTML(
        Form     => $Form,
        Request  => $Request,
        Language => $Language,
    );
    $FormError ||= $FormObject->Error();

    my $Body = $Output->RenderSingle(
        Template => 'PublicTicketForm.tt',
        Data     => {
            Language          => $Language,
            LanguageLinks     => $LanguageLinks,
            HasLanguageLinks  => @{$LanguageLinks} > 1 ? 1 : 0,
            StaticBase        => $Config->{Paths}->{StaticURL} || '/qisutu/static',
            SystemName        => $Config->{System}->{Name} || 'Qisutu',
            PublicFormTitle   => $Form->{title},
            PublicFormDescription => $Form->{description},
            PublicFormSubmitLabel => $Form->{submit_label} || 'Translate:TicketFormSubmit',
            PublicFormFieldsHTML  => $FieldsHTML,
            FormAction        => 'form.pl?Form=' . $Slug . '&Language=' . $Language,
            FormID            => $Form->{id},
            FormStartedAt     => time,
            FormError         => $FormError,
            FormErrorClass    => $FormError ? '' : 'qisutu-hidden',
            Success           => $Success,
            ConfirmationText  => $Confirmation,
            TicketNumber      => $TicketNumber,
            HasTicketNumber   => $TicketNumber ? 1 : 0,
            AttachmentMaxSizeMB => $AttachmentMaxSizeMB,
            AttachmentMaxSizeBytes => $AttachmentMaxSizeMB * 1024 * 1024,
        },
    );

    print _HTMLResponse(
        Output         => $Output,
        Status         => '200 OK',
        Body           => $Body,
        FrameAncestors => $FormObject->PublicFrameAncestors( AllowedOrigins => $Form->{allowed_origins} ),
    );
    return;
}

sub _RequestParams {
    my %Param;
    _ParamParse( Target => \%Param, Source => $ENV{QUERY_STRING} || '' );

    if ( ( $ENV{REQUEST_METHOD} || '' ) eq 'POST' ) {
        my $Length = $ENV{CONTENT_LENGTH} || 0;
        $Length = 0 if $Length !~ m{\A\d+\z};
        my $Body = '';
        if ($Length) {
            binmode STDIN;
            read STDIN, $Body, $Length;
        }
        my $ContentType = $ENV{CONTENT_TYPE} || $ENV{HTTP_CONTENT_TYPE} || '';
        if ( $ContentType =~ m{multipart/form-data}i ) {
            _MultipartParse(
                Target      => \%Param,
                Source      => $Body,
                ContentType => $ContentType,
            );
        }
        else {
            _ParamParse( Target => \%Param, Source => $Body );
        }
    }
    return \%Param;
}

sub _UploadedAttachments {
    my (%Param) = @_;
    my $Uploads = ( $Param{Request} || {} )->{__Uploads} || {};
    my $RawList = ref $Uploads->{TicketAttachment} eq 'ARRAY'
        ? $Uploads->{TicketAttachment}
        : ref $Uploads->{'TicketAttachment[]'} eq 'ARRAY'
            ? $Uploads->{'TicketAttachment[]'}
            : [];
    my @Attachments;
    for my $Upload ( @{$RawList} ) {
        next if ref $Upload ne 'HASH' || !defined $Upload->{Content};
        my $Filename = $Upload->{Filename} || '';
        $Filename =~ s{\\}{/}g;
        $Filename =~ s{\A.*/}{}g;
        $Filename =~ s{[\r\n\x00]}{}g;
        $Filename =~ s{\A\s+|\s+\z}{}g;
        next if !$Filename;
        push @Attachments, {
            Filename           => $Filename,
            ContentType        => $Upload->{ContentType} || 'application/octet-stream',
            Content            => $Upload->{Content},
            ContentSize        => $Upload->{ContentSize} || length( $Upload->{Content} ),
            ContentDisposition => 'attachment',
        };
    }
    return \@Attachments;
}

sub _MultipartParse {
    my (%Param) = @_;
    my $Target = $Param{Target};
    my $Source = defined $Param{Source} ? $Param{Source} : '';
    my $ContentType = $Param{ContentType} || '';
    return if !$Target || $Source eq '';

    my $Boundary = $ContentType =~ m{boundary="([^"]+)"}i ? $1
        : $ContentType =~ m{boundary=([^;\s]+)}i ? $1 : '';
    return if !$Boundary;

    my ( %Parsed, %Uploads );
    for my $Part ( split /\Q--$Boundary\E/, $Source ) {
        next if !defined $Part;
        $Part =~ s{\A\r?\n}{};
        $Part =~ s{\r?\n\z}{};
        next if $Part eq '' || $Part =~ m{\A--\s*\z};
        my ( $HeaderText, $Content ) = split /\r?\n\r?\n/, $Part, 2;
        next if !defined $HeaderText || !defined $Content;
        $Content =~ s{\r?\n\z}{};
        my %Header = _MultipartHeadersParse($HeaderText);
        my $Disposition = $Header{'content-disposition'} || '';
        next if $Disposition !~ m{\bform-data\b}i;
        my $Name = _MultipartHeaderParameter( Header => $Disposition, Name => 'name' );
        next if !$Name;
        my $Filename = _MultipartHeaderParameter( Header => $Disposition, Name => 'filename*' )
            || _MultipartHeaderParameter( Header => $Disposition, Name => 'filename' );
        if ($Filename) {
            push @{ $Uploads{$Name} ||= [] }, {
                Filename => $Filename,
                ContentType => $Header{'content-type'} || 'application/octet-stream',
                Content => $Content,
                ContentSize => length($Content),
                ContentDisposition => 'attachment',
            };
            next;
        }
        _ParamValueStore(
            Target => \%Parsed,
            Key    => $Name,
            Value  => eval { decode( 'UTF-8', $Content, 1 ) } || $Content,
        );
    }
    $Target->{$_} = $Parsed{$_} for keys %Parsed;
    for my $Name ( keys %Uploads ) {
        push @{ $Target->{__Uploads}->{$Name} ||= [] }, @{ $Uploads{$Name} };
    }
    return 1;
}

sub _MultipartHeadersParse {
    my ($HeaderText) = @_;
    my ( %Header, $Current );
    for my $Line ( split /\r?\n/, $HeaderText || '' ) {
        if ( $Line =~ m{\A[ \t]+} && $Current ) {
            $Header{$Current} .= ' ' . $Line;
            next;
        }
        my ( $Name, $Value ) = split /:/, $Line, 2;
        next if !defined $Name || !defined $Value;
        $Name =~ s{\A\s+|\s+\z}{}g;
        $Value =~ s{\A\s+|\s+\z}{}g;
        $Current = lc $Name;
        $Header{$Current} = $Value;
    }
    return %Header;
}

sub _MultipartHeaderParameter {
    my (%Param) = @_;
    my $Header = $Param{Header} || '';
    my $Name = lc( $Param{Name} || '' );
    for my $Part ( split /;/, $Header ) {
        my ( $Key, $Value ) = split /=/, $Part, 2;
        next if !defined $Key || !defined $Value;
        $Key =~ s{\A\s+|\s+\z}{}g;
        next if lc($Key) ne $Name;
        $Value =~ s{\A\s+|\s+\z}{}g;
        if ( $Value =~ m{\A"(.*)"\z}s ) {
            $Value = $1;
            $Value =~ s{\\"}{"}g;
            $Value =~ s{\\\\}{\\}g;
        }
        if ( $Name =~ m{\*\z} && $Value =~ m{\A([^']*)'[^']*'(.*)\z}s ) {
            my $Charset = $1 || 'UTF-8';
            my $Encoded = $2 || '';
            $Encoded =~ s{%([0-9A-Fa-f]{2})}{chr hex $1}eg;
            $Value = eval { decode( $Charset, $Encoded, 1 ) } || $Encoded;
        }
        else {
            $Value = eval { decode( 'UTF-8', $Value, 1 ) } || $Value;
        }
        $Value =~ s{[\x00\r\n]}{}g;
        $Value =~ s{\A\s+|\s+\z}{}g;
        return $Value;
    }
    return '';
}

sub _ParamValueStore {
    my (%Param) = @_;
    my $Target = $Param{Target};
    my $Key = $Param{Key};
    return if !$Target || !defined $Key || $Key eq '';
    if ( !exists $Target->{$Key} ) {
        $Target->{$Key} = $Param{Value};
    }
    elsif ( ref $Target->{$Key} eq 'ARRAY' ) {
        push @{ $Target->{$Key} }, $Param{Value};
    }
    else {
        $Target->{$Key} = [ $Target->{$Key}, $Param{Value} ];
    }
    return 1;
}

sub _ParamParse {
    my (%Param) = @_;
    my $Target = $Param{Target};
    for my $Pair ( split /[&;]/, ( $Param{Source} || '' ) ) {
        my ( $Key, $Value ) = split /=/, $Pair, 2;
        $Key   = _URLDecode( defined $Key ? $Key : '' );
        $Value = _URLDecode( defined $Value ? $Value : '' );
        next if !$Key || length $Key > 150 || length $Value > 100_000;
        if ( !exists $Target->{$Key} ) {
            $Target->{$Key} = $Value;
        }
        elsif ( ref $Target->{$Key} eq 'ARRAY' ) {
            push @{ $Target->{$Key} }, $Value;
        }
        else {
            $Target->{$Key} = [ $Target->{$Key}, $Value ];
        }
    }
}

sub _URLDecode {
    my ($Value) = @_;
    $Value ||= '';
    $Value =~ tr/+/ /;
    $Value =~ s{%([0-9A-Fa-f]{2})}{chr hex $1}eg;
    return eval { decode( 'UTF-8', $Value, 1 ) } || $Value;
}

sub _LanguageClean {
    my ($Language) = @_;

    return '' if !defined $Language || ref $Language;
    $Language =~ tr{_}{-};
    return '' if $Language !~ m{\A[A-Za-z]{2,3}(?:-[A-Za-z]{2})?\z};

    if ( $Language =~ m{\A([A-Za-z]{2,3})-([A-Za-z]{2})\z} ) {
        $Language = lc($1) . '-' . uc($2);
    }
    else {
        $Language = lc $Language;
    }

    my $File = File::Spec->catfile( $QisutuHome, 'core', 'language', "$Language.pm" );
    return -f $File && !-l $File ? $Language : '';
}

sub _HTMLResponse {
    my (%Param) = @_;
    my $FrameAncestors = $Param{FrameAncestors} || "'none'";
    return $Param{Output}->Response(
        Status  => $Param{Status} || '200 OK',
        Body    => defined $Param{Body} ? $Param{Body} : '',
        AllowFrame => $FrameAncestors ne "'none'" ? 1 : 0,
        Headers => [
            'Cache-Control: no-store, no-cache, must-revalidate',
            'Pragma: no-cache',
            'X-Content-Type-Options: nosniff',
            'Referrer-Policy: strict-origin-when-cross-origin',
            "Content-Security-Policy: default-src 'self'; style-src 'self'; img-src 'self' data:; form-action 'self'; frame-ancestors $FrameAncestors",
        ],
    );
}

sub _PlainResponse {
    my (%Param) = @_;
    my $Body = defined $Param{Body} ? $Param{Body} : '';
    return "Status: " . ( $Param{Status} || '500 Internal Server Error' )
        . "\r\nContent-Type: text/plain; charset=UTF-8\r\nCache-Control: no-store\r\n\r\n$Body\n";
}
