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

use FindBin;
use File::Spec;
use Cwd qw(abs_path);
use Encode qw(decode);

my $QisutuHome = $ENV{QISUTU_HOME} || abs_path( File::Spec->catdir( $FindBin::Bin, '..', '..' ) );

$ENV{QISUTU_HOME} ||= $QisutuHome;

if ( $ENV{GATEWAY_INTERFACE} ) {
    my $InstallLock = File::Spec->catfile( $QisutuHome, 'var', 'install', 'installed.lock' );
    if ( !-f $InstallLock ) {
        print "Status: 302 Found\r\nLocation: install.pl\r\nCache-Control: no-store\r\n\r\n";
        exit;
    }

    my $UpdateLock = File::Spec->catfile( $QisutuHome, 'var', 'install', 'update.lock' );
    if ( -e $UpdateLock ) {
        print _MaintenanceResponse();
        exit;
    }
}

unshift @INC,
    File::Spec->catdir( $QisutuHome, 'core', 'config' ),
    File::Spec->catdir( $QisutuHome, 'core', 'system' ),
    File::Spec->catdir( $QisutuHome, 'core', 'output' ),
    File::Spec->catdir( $QisutuHome, 'core', 'module' );

main();


sub _MaintenanceResponse {
    return join '',
        "Status: 503 Service Unavailable\r\n",
        "Content-Type: text/html; charset=UTF-8\r\n",
        "Cache-Control: no-store, no-cache, must-revalidate\r\n",
        "Retry-After: 120\r\n\r\n",
        '<!doctype html><html lang="de"><head><meta charset="utf-8">',
        '<meta name="viewport" content="width=device-width,initial-scale=1">',
        '<title>Qisutu wird aktualisiert</title>',
        '<style>body{margin:0;background:#f4f6f8;color:#1f2933;font-family:Arial,sans-serif}',
        '.box{max-width:680px;margin:12vh auto;padding:36px;background:#fff;border:1px solid #d9e0e7;border-radius:8px}',
        'h1{margin-top:0;font-size:28px}p{font-size:17px;line-height:1.55}</style></head><body>',
        '<main class="box"><h1>Qisutu wird aktualisiert</h1>',
        '<p>Diese Qisutu-Instanz ist während des Updates vorübergehend nicht verfügbar.</p>',
        '<p>Bitte rufe die Seite nach Abschluss des Updates erneut auf.</p></main></body></html>';
}

sub main {
    my $Param = _RequestParams();

    my $Config = _ConfigLoad();
    if ( !$Config ) {
        print _FatalResponse('Qisutu configuration could not be loaded.');
        return;
    }

    my $Output = _ObjectCreate(
        Module => 'QisutuOutput',
        Param  => {
            Config => $Config,
        },
    );

    if ( !$Output ) {
        print _FatalResponse('Qisutu output system could not be loaded.');
        return;
    }

    my $DB = _ObjectCreate(
        Module => 'QisutuDB',
        Param  => {
            Config => $Config,
        },
    );

    if ( !$DB ) {
        print $Output->Response(
            Status => '500 Internal Server Error',
            Body   => 'Qisutu database system could not be loaded.',
        );
        return;
    }

    my $ProgramRegistry = _ObjectCreate(
        Module => 'QisutuProgramRegistry',
        Param  => {
            Config => $Config,
            DB     => $DB,
            Output => $Output,
        },
    );

    if ( !$ProgramRegistry ) {
        print $Output->Response(
            Status => '500 Internal Server Error',
            Body   => 'Qisutu program registry could not be loaded.',
        );
        return;
    }

    my $Dispatcher = _ObjectCreate(
        Module => 'QisutuDispatcher',
        Param  => {
            Config          => $Config,
            DB              => $DB,
            Output          => $Output,
            ProgramRegistry => $ProgramRegistry,
        },
    );

    if ( !$Dispatcher ) {
        print $Output->Response(
            Status => '500 Internal Server Error',
            Body   => 'Qisutu dispatcher could not be loaded.',
        );
        return;
    }

    my $Auth = _ObjectCreate(
        Module => 'QisutuAuth',
        Param  => {
            Config => $Config,
            DB     => $DB,
        },
    );

    my $Session = _ObjectCreate(
        Module => 'QisutuSession',
        Param  => {
            Config => $Config,
            DB     => $DB,
        },
    );

    if ( !$Auth || !$Session ) {
        print $Output->Response(
            Status => '500 Internal Server Error',
            Body   => 'Qisutu login system could not be loaded.',
        );
        return;
    }

    if ( ( $Param->{Page} || '' ) eq 'Logout' ) {
        print _Logout(
            Config  => $Config,
            Output  => $Output,
            Session => $Session,
            Token   => _CookieGet( Name => $Config->{Session}->{CookieName} ),
        );
        return;
    }

    my $SessionToken = _CookieGet( Name => $Config->{Session}->{CookieName} );
    my $CurrentUser;

    if ($SessionToken) {
        $CurrentUser = $Session->Get( Token => $SessionToken );

        if ($CurrentUser) {
            $Session->Touch( Token => $SessionToken );
        }
    }

    if ( $CurrentUser && !( ( $Param->{Step} || '' ) eq 'Login' ) ) {
        print $Dispatcher->Run(
            Request => $Param,
            User    => $CurrentUser,
        );
        return;
    }

    my $LoginModule = _ObjectCreate(
        Module => 'Login',
        Param  => {
            Config  => $Config,
            Output  => $Output,
            DB      => $DB,
            Auth    => $Auth,
            Session => $Session,
        },
    );

    if ( !$LoginModule ) {
        print $Output->Response(
            Status => '500 Internal Server Error',
            Body   => 'Qisutu login module could not be loaded.',
        );
        return;
    }

    print $LoginModule->Run(
        %{$Param},
        IPAddress       => $ENV{REMOTE_ADDR}      || '',
        UserAgent       => $ENV{HTTP_USER_AGENT} || '',
        SecureCookie    => ( ( $ENV{HTTPS} || '' ) eq 'on' ? 1 : 0 ),
        FormAction      => 'index.pl',
        SuccessLocation => 'index.pl',
    );

    return;
}

sub _ConfigLoad {
    my $Loaded = eval {
        require QisutuConfig;
        1;
    };

    if ( !$Loaded ) {
        return;
    }

    my $Config = QisutuConfig::Load();

    return $Config;
}

sub _ObjectCreate {
    my (%Param) = @_;

    my $Module = $Param{Module} || '';
    my $ObjectParam = $Param{Param} || {};

    return if !$Module;

    my $Loaded = eval "require $Module; 1;";

    if ( !$Loaded ) {
        return;
    }

    my $Object = $Module->new( %{$ObjectParam} );

    return $Object;
}

sub _RequestParams {
    my %Param;

    my $QueryString = $ENV{QUERY_STRING} || '';
    _ParamParse(
        Target => \%Param,
        Source => $QueryString,
    );

    if ( ( $ENV{REQUEST_METHOD} || '' ) eq 'POST' ) {
        my $ContentLength = $ENV{CONTENT_LENGTH} || 0;
        my $PostBody      = '';

        if ($ContentLength) {
            binmode STDIN;
            read STDIN, $PostBody, $ContentLength;
        }

        my $ContentType = $ENV{CONTENT_TYPE} || $ENV{HTTP_CONTENT_TYPE} || '';

        if ( $ContentType =~ m{multipart/form-data}i ) {
            _MultipartParse(
                Target      => \%Param,
                Source      => $PostBody,
                ContentType => $ContentType,
            );
        }
        else {
            _ParamParse(
                Target => \%Param,
                Source => $PostBody,
            );
        }
    }

    return \%Param;
}


sub _MultipartParse {
    my (%Param) = @_;

    my $Target      = $Param{Target};
    my $Source      = defined $Param{Source} ? $Param{Source} : '';
    my $ContentType = $Param{ContentType} || '';
    my %Parsed;
    my %Uploads;

    return if !$Target;
    return if $Source eq '';

    my $Boundary = '';
    if ( $ContentType =~ m{boundary="([^"]+)"}i ) {
        $Boundary = $1;
    }
    elsif ( $ContentType =~ m{boundary=([^;\s]+)}i ) {
        $Boundary = $1;
    }

    return if !$Boundary;

    my $Delimiter = '--' . $Boundary;
    my @Parts = split /\Q$Delimiter\E/, $Source;

    PART:
    for my $Part (@Parts) {
        next PART if !defined $Part;
        $Part =~ s{\A\r?\n}{};
        $Part =~ s{\r?\n\z}{};
        next PART if $Part eq '';
        next PART if $Part =~ m{\A--\s*\z};

        my ( $HeaderText, $Content ) = split /\r?\n\r?\n/, $Part, 2;
        next PART if !defined $HeaderText || !defined $Content;

        $Content =~ s{\r?\n\z}{};

        my %Header = _MultipartHeadersParse($HeaderText);
        my $Disposition = $Header{'content-disposition'} || '';
        next PART if $Disposition !~ m{\bform-data\b}i;

        my $Name = _MultipartHeaderParameter( Header => $Disposition, Name => 'name' );
        next PART if !$Name;

        my $Filename = _MultipartHeaderParameter( Header => $Disposition, Name => 'filename*' );
        if ( !$Filename ) {
            $Filename = _MultipartHeaderParameter( Header => $Disposition, Name => 'filename' );
        }

        if ( defined $Filename && $Filename ne '' ) {
            my $PartContentType = $Header{'content-type'} || 'application/octet-stream';
            $PartContentType =~ s{\r|\n}{ }g;
            $PartContentType =~ s{\s+}{ }g;
            $PartContentType =~ s{\A\s+|\s+\z}{}g;
            $PartContentType ||= 'application/octet-stream';

            push @{ $Uploads{$Name} ||= [] }, {
                Filename           => $Filename,
                ContentType        => $PartContentType,
                Content            => $Content,
                ContentSize        => length($Content),
                ContentDisposition => 'attachment',
            };

            next PART;
        }

        _ParamValueStore(
            Target => \%Parsed,
            Key    => $Name,
            Value  => eval { decode( 'UTF-8', $Content, 1 ) } || $Content,
        );
    }

    for my $Name ( keys %Parsed ) {
        $Target->{$Name} = $Parsed{$Name};
    }

    if ( keys %Uploads ) {
        $Target->{__Uploads} ||= {};
        for my $Name ( keys %Uploads ) {
            push @{ $Target->{__Uploads}->{$Name} ||= [] }, @{ $Uploads{$Name} };
        }
    }

    return 1;
}

sub _MultipartHeadersParse {
    my ($HeaderText) = @_;

    my %Header;
    my $Current = '';

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
    my $Name   = lc( $Param{Name} || '' );

    return '' if !$Header || !$Name;

    for my $Part ( split /;/, $Header ) {
        my ( $Key, $Value ) = split /=/, $Part, 2;
        next if !defined $Key || !defined $Value;

        $Key =~ s{\A\s+|\s+\z}{}g;
        $Key = lc $Key;
        next if $Key ne $Name;

        $Value =~ s{\A\s+|\s+\z}{}g;
        if ( $Value =~ m{\A"(.*)"\z}s ) {
            $Value = $1;
            $Value =~ s{\\"}{"}g;
            $Value =~ s{\\\\}{\\}g;
        }

        if ( $Name =~ m{\*\z} && $Value =~ m{\A([^']*)'[^']*'(.*)\z}s ) {
            my $Charset = $1 || 'UTF-8';
            my $Encoded = $2 || '';
            $Encoded =~ s{%([0-9A-Fa-f]{2})}{chr(hex($1))}eg;
            $Value = eval { decode( $Charset, $Encoded, 1 ) } || $Encoded;
        }
        else {
            $Value = eval { decode( 'UTF-8', $Value, 1 ) } || $Value;
        }

        $Value =~ s{\x00}{}g;
        $Value =~ s{\r|\n}{}g;
        $Value =~ s{\A\s+|\s+\z}{}g;

        return $Value;
    }

    return '';
}

sub _ParamParse {
    my (%Param) = @_;

    my $Target = $Param{Target};
    my $Source = $Param{Source} || '';

    return if !$Target;
    return if !$Source;

    my %Parsed;

    for my $Pair ( split /[&;]/, $Source ) {
        next if $Pair eq '';

        my ( $Key, $Value ) = split /=/, $Pair, 2;

        $Key   = _URLDecode( defined $Key   ? $Key   : '' );
        $Value = _URLDecode( defined $Value ? $Value : '' );

        next if $Key eq '';

        _ParamValueStore(
            Target => \%Parsed,
            Key    => $Key,
            Value  => $Value,
        );
    }

    for my $Key ( keys %Parsed ) {
        $Target->{$Key} = $Parsed{$Key};
    }

    return 1;
}

sub _ParamValueStore {
    my (%Param) = @_;

    my $Target = $Param{Target};
    my $Key    = $Param{Key};
    my $Value  = $Param{Value};

    return if !$Target || !defined $Key || $Key eq '';

    if ( !exists $Target->{$Key} ) {
        $Target->{$Key} = $Value;
        return 1;
    }

    if ( ref $Target->{$Key} eq 'ARRAY' ) {
        push @{ $Target->{$Key} }, $Value;
        return 1;
    }

    $Target->{$Key} = [ $Target->{$Key}, $Value ];
    return 1;
}

sub _URLDecode {
    my ($Value) = @_;

    $Value = '' if !defined $Value;

    $Value =~ tr/+/ /;
    $Value =~ s/%([0-9A-Fa-f]{2})/chr(hex($1))/eg;
    $Value = eval { decode( 'UTF-8', $Value, 1 ) } || $Value;

    return $Value;
}

sub _CookieGet {
    my (%Param) = @_;

    my $Name   = $Param{Name} || '';
    my $Cookie = $ENV{HTTP_COOKIE} || '';

    return if !$Name;
    return if !$Cookie;

    for my $Part ( split /;\s*/, $Cookie ) {
        my ( $CookieName, $CookieValue ) = split /=/, $Part, 2;

        next if !defined $CookieName;
        next if $CookieName ne $Name;

        return _URLDecode( defined $CookieValue ? $CookieValue : '' );
    }

    return;
}

sub _Logout {
    my (%Param) = @_;

    my $Config  = $Param{Config};
    my $Output  = $Param{Output};
    my $Session = $Param{Session};
    my $Token   = $Param{Token} || '';

    if ($Token) {
        $Session->Delete( Token => $Token );
    }

    my $Cookie = $Output->CookieDelete(
        Name => $Config->{Session}->{CookieName},
        Path => '/',
    );

    return $Output->Redirect(
        Location => 'index.pl',
        Cookie   => $Cookie,
    );
}

sub _FatalResponse {
    my ($Message) = @_;

    $Message ||= 'Qisutu could not be started.';

    return "Status: 500 Internal Server Error\r\n"
        . "Content-Type: text/plain; charset=UTF-8\r\n\r\n"
        . $Message
        . "\n";
}
