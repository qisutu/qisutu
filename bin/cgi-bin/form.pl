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
        require QisutuSecurity;
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
    my $Security = QisutuSecurity->new( Config => $Config );
    my $DB = QisutuDB->new( Config => $Config );
    my $FormObject = QisutuTicketForm->new(
        Config => $Config,
        DB     => $DB,
        Output => $Output,
    );

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
        if ( !$Security->PublicCSRFTokenVerify(
            Token   => $Request->{CSRFToken} || '',
            Purpose => 'public-ticket-form:' . $Slug,
        ) ) {
            print _HTMLResponse(
                Output         => $Output,
                Status         => '403 Forbidden',
                Body           => 'Die Anfrage konnte aus Sicherheitsgründen nicht verarbeitet werden. Bitte laden Sie das Formular neu.',
                FrameAncestors => $FormObject->PublicFrameAncestors( AllowedOrigins => $Form->{allowed_origins} ),
            );
            return;
        }

        my $Created = $FormObject->SubmissionCreate(
            Context   => 'public',
            FormID    => $Form->{id},
            Request   => $Request,
            Language  => $Language,
            IPAddress => $ENV{REMOTE_ADDR} || '',
            UserAgent => $ENV{HTTP_USER_AGENT} || '',
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
            CSRFToken          => $Security->PublicCSRFTokenCreate(
                Purpose => 'public-ticket-form:' . $Slug,
            ),
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
        if ( $Length > 524_288 ) {
            return \%Param;
        }
        my $Body = '';
        if ($Length) {
            binmode STDIN;
            read STDIN, $Body, $Length;
        }
        _ParamParse( Target => \%Param, Source => $Body );
    }
    return \%Param;
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
