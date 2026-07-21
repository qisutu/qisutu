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
use JSON::PP ();

my $Home = $ENV{QISUTU_HOME} || abs_path( File::Spec->catdir( $FindBin::Bin, '..', '..' ) );
$ENV{QISUTU_HOME} ||= $Home;
unshift @INC,
    File::Spec->catdir( $Home, 'core', 'config' ),
    File::Spec->catdir( $Home, 'core', 'system' ),
    File::Spec->catdir( $Home, 'core', 'cpan-lib' );

main();

sub main {
    my $RequestID = _RequestID();
    if ( !-f File::Spec->catfile( $Home, 'var', 'install', 'installed.lock' ) ) {
        return _PrintJSON( Status => 503, RequestID => $RequestID, Body => _Error('not_installed','Qisutu is not installed.',$RequestID) );
    }
    if ( -e File::Spec->catfile( $Home, 'var', 'install', 'update.lock' ) ) {
        return _PrintJSON( Status => 503, RequestID => $RequestID, RetryAfter => 120, Body => _Error('maintenance','Qisutu is currently being updated.',$RequestID) );
    }
    my $Config = eval { require QisutuConfig; QisutuConfig::Load() };
    if (!$Config) {
        return _PrintJSON( Status => 500, RequestID => $RequestID, Body => _Error('configuration_error','Qisutu configuration could not be loaded.',$RequestID) );
    }
    my $DB = eval { require QisutuDB; QisutuDB->new( Config => $Config ) };
    if ( !$DB || !$DB->Connect() ) {
        return _PrintJSON( Status => 503, RequestID => $RequestID, Body => _Error('database_unavailable','Qisutu database is unavailable.',$RequestID) );
    }

    my $Method = uc( $ENV{REQUEST_METHOD} || 'GET' );
    my $Path = $ENV{PATH_INFO} || '';
    if (!$Path) {
        my $URI = $ENV{REQUEST_URI} || '';
        ($Path) = $URI =~ m{api\.pl(/[^?]*)};
    }
    $Path ||= '/v1';
    my $Query = _QueryParse( $ENV{QUERY_STRING} || '' );
    my $Body = {};
    if ( $Method =~ m{\A(?:POST|PATCH|PUT)\z} ) {
        my $Length = $ENV{CONTENT_LENGTH} || 0;
        if ( $Length !~ m{\A\d+\z} || $Length > 50 * 1024 * 1024 ) {
            return _PrintJSON( Status => 413, RequestID => $RequestID, Body => _Error('request_too_large','The request body is too large.',$RequestID) );
        }
        my $Type = $ENV{CONTENT_TYPE} || '';
        if ( $Length && $Type !~ m{application/json}i ) {
            return _PrintJSON( Status => 415, RequestID => $RequestID, Body => _Error('unsupported_media_type','Use Content-Type: application/json.',$RequestID) );
        }
        my $Raw = '';
        if ($Length) {
            binmode STDIN;
            my $Read = read STDIN, $Raw, $Length;
            if ( !defined $Read || $Read != $Length ) {
                return _PrintJSON( Status => 400, RequestID => $RequestID, Body => _Error('invalid_request_body','The request body could not be read.',$RequestID) );
            }
            my $Decoded = eval { JSON::PP->new->utf8(1)->decode($Raw) };
            if ( $@ || ref $Decoded ne 'HASH' ) {
                return _PrintJSON( Status => 400, RequestID => $RequestID, Body => _Error('invalid_json','The request body must be a JSON object.',$RequestID) );
            }
            $Body = $Decoded;
        }
    }

    my %Headers = (
        authorization        => $ENV{HTTP_AUTHORIZATION} || $ENV{REDIRECT_HTTP_AUTHORIZATION} || '',
        'x-qisutu-api-token' => $ENV{HTTP_X_QISUTU_API_TOKEN} || '',
        'idempotency-key'    => $ENV{HTTP_IDEMPOTENCY_KEY} || '',
    );
    my $API = eval { require QisutuRESTAPI; QisutuRESTAPI->new( Config => $Config, DB => $DB ) };
    if (!$API) {
        return _PrintJSON( Status => 500, RequestID => $RequestID, Body => _Error('api_start_failed','Qisutu REST API could not be started.',$RequestID) );
    }
    my $Result = eval {
        $API->Handle(
            Method => $Method, Path => $Path, Query => $Query, Body => $Body, Headers => \%Headers,
            RemoteIP => $ENV{REMOTE_ADDR} || '', RequestID => $RequestID,
        );
    };
    if ( !$Result || $@ ) {
        return _PrintJSON( Status => 500, RequestID => $RequestID, Body => _Error('internal_error','The API request could not be completed.',$RequestID) );
    }
    return _PrintRaw( %{$Result}, RequestID => $RequestID ) if exists $Result->{RawBody};
    return _PrintJSON( Status => $Result->{Status}, RequestID => $RequestID, Body => $Result->{Body} );
}

sub _Error { my($Code,$Message,$RequestID)=@_;return{error=>{code=>$Code,message=>$Message,request_id=>$RequestID}}; }

sub _PrintJSON {
    my (%Param) = @_;
    my $Status = $Param{Status} || 500;
    my %Reason = (200=>'OK',201=>'Created',400=>'Bad Request',401=>'Unauthorized',403=>'Forbidden',404=>'Not Found',409=>'Conflict',413=>'Payload Too Large',415=>'Unsupported Media Type',422=>'Unprocessable Entity',429=>'Too Many Requests',500=>'Internal Server Error',503=>'Service Unavailable');
    my $JSON = JSON::PP->new->utf8(1)->canonical(1)->encode( $Param{Body} || {} );
    print 'Status: '.$Status.' '.($Reason{$Status}||'Response')."\r\n";
    print "Content-Type: application/json; charset=UTF-8\r\nCache-Control: no-store\r\nPragma: no-cache\r\nX-Content-Type-Options: nosniff\r\n";
    print 'X-Request-ID: '.($Param{RequestID}||'')."\r\n";
    print 'Retry-After: '.$Param{RetryAfter}."\r\n" if $Param{RetryAfter};
    print 'Content-Length: '.length($JSON)."\r\n\r\n";
    binmode STDOUT; print $JSON; return;
}

sub _PrintRaw {
    my (%Param) = @_;
    my $Body = defined $Param{RawBody} ? $Param{RawBody} : '';
    my $Filename = $Param{Filename} || 'attachment.bin';
    $Filename =~ s{[\r\n"\\]}{_}g;
    print "Status: 200 OK\r\n";
    print 'Content-Type: '.($Param{ContentType}||'application/octet-stream')."\r\n";
    print 'Content-Disposition: attachment; filename="'.$Filename.'"'."\r\n";
    print "Cache-Control: private, no-store\r\nX-Content-Type-Options: nosniff\r\n";
    print 'X-Request-ID: '.($Param{RequestID}||'')."\r\n";
    print 'Content-Length: '.length($Body)."\r\n\r\n";
    binmode STDOUT; print $Body; return;
}

sub _QueryParse {
    my ($Source)=@_;my%Out;
    for my$Part(split m{[&;]},$Source||''){next if$Part eq'';my($K,$V)=split m{=},$Part,2;$K=_Decode($K);$V=_Decode(defined$V?$V:'');if(exists$Out{$K}){$Out{$K}=[$Out{$K}]if ref$Out{$K}ne'ARRAY';push@{$Out{$K}},$V}else{$Out{$K}=$V}}
    return\%Out;
}
sub _Decode { my($V)=@_;$V=''if!defined$V;$V=~tr/+/ /;$V=~s{%([0-9A-Fa-f]{2})}{chr(hex($1))}eg;return eval{decode('UTF-8',$V,1)}||$V; }
sub _RequestID { my@T=localtime();return sprintf('%04d%02d%02d-%02d%02d%02d-%05d-%08x',$T[5]+1900,$T[4]+1,$T[3],$T[2],$T[1],$T[0],$$,int(rand(0xffffffff))); }
