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

package QisutuAddonREST;

use strict;
use warnings;
use utf8;

use QisutuAddonAPI;

sub new {
    my ( $Class, %Param ) = @_;
    my $Self = {
        Config => $Param{Config} || {},
        DB     => $Param{DB},
        Auth   => $Param{Auth},
    };
    bless $Self, $Class;
    return $Self;
}

sub Dispatch {
    my ( $Self, %Param ) = @_;
    my $Method = uc( $Param{Method} || '' );
    my $Path   = $Param{Path} || '';
    for my $Route ( @{ ( $Self->{Config}->{AddonRuntime} || {} )->{RESTRoutes} || [] } ) {
        next if ref $Route ne 'HASH' || uc( $Route->{method} || '' ) ne $Method;
        my $PathParameters = $Self->_PathMatch( Definition => $Route->{path}, Path => $Path );
        next if !$PathParameters;

        my @Scopes = ref $Route->{scopes} eq 'ARRAY'
            ? @{ $Route->{scopes} }
            : ( $Route->{scope} ? ( $Route->{scope} ) : () );
        for my $Scope (@Scopes) {
            if ( !$Self->{Auth} || !$Self->{Auth}->ScopeAllowed( Token => $Param{Token}, Scope => $Scope ) ) {
                return {
                    Status => 403,
                    Body => { error => {
                        code => 'scope_missing',
                        message => "The token is missing permission '$Scope'.",
                        request_id => $Param{RequestID} || '',
                    } },
                    ResultCode => 'scope_missing',
                };
            }
        }
        if ( ref $Route->{access_types} eq 'ARRAY' && @{ $Route->{access_types} } ) {
            my %Allowed = map { $_ => 1 } @{ $Route->{access_types} };
            my $AccountType = $Param{Token}->{account_type} || '';
            if ( !$Allowed{$AccountType} ) {
                return {
                    Status => 403,
                    Body => { error => {
                        code => 'permission_denied',
                        message => 'The authenticated account may not use this add-on endpoint.',
                        request_id => $Param{RequestID} || '',
                    } },
                    ResultCode => 'permission_denied',
                };
            }
        }

        my $Class = $Route->{class} || '';
        my $HandlerMethod = $Route->{handler_method} || 'Handle';
        return $Self->_Failure( RequestID => $Param{RequestID} )
            if $Class !~ m{\AQisutu::Addon::[A-Za-z0-9_:]+\z}
            || $HandlerMethod !~ m{\A[A-Za-z][A-Za-z0-9_]*\z}
            || !eval "require $Class; 1;";
        my $API = QisutuAddonAPI->new(
            Config     => $Self->{Config},
            DB         => $Self->{DB},
            Identifier => $Route->{package_identifier},
        );
        my $Handler = eval {
            $Class->new(
                Config => $Self->{Config}, DB => $Self->{DB}, API => $API,
                Definition => $Route,
            );
        };
        return $Self->_Failure( RequestID => $Param{RequestID} )
            if !$Handler || !$Handler->can($HandlerMethod);
        my $Result = eval {
            $Handler->$HandlerMethod(
                Method         => $Method,
                Path           => $Path,
                PathParameters => $PathParameters,
                Query          => $Param{Query} || {},
                Body           => $Param{Body} || {},
                Token          => $Param{Token} || {},
                RequestID      => $Param{RequestID} || '',
                API            => $API,
            );
        };
        return $Self->_Failure( RequestID => $Param{RequestID} )
            if !$Result || ref $Result ne 'HASH';
        my $Status = $Result->{Status} || 200;
        return $Self->_Failure( RequestID => $Param{RequestID} )
            if $Status !~ m{\A\d+\z} || $Status < 200 || $Status > 599;
        my $Body = exists $Result->{Body}
            ? $Result->{Body}
            : { data => exists $Result->{Data} ? $Result->{Data} : {} };
        return $Self->_Failure( RequestID => $Param{RequestID} )
            if ref $Body ne 'HASH' && ref $Body ne 'ARRAY';
        return {
            Status       => 0 + $Status,
            Body         => $Body,
            ResultCode   => $Result->{ResultCode} || 'addon_ok',
            ResourceType => $Result->{ResourceType},
            ResourceID   => $Result->{ResourceID},
        };
    }
    return;
}

sub RouteDocumentList {
    my ($Self) = @_;
    my @List;
    for my $Route ( @{ ( $Self->{Config}->{AddonRuntime} || {} )->{RESTRoutes} || [] } ) {
        push @List, {
            package => $Route->{package_identifier},
            method  => uc( $Route->{method} || '' ),
            path    => $Route->{path} || '',
            scopes  => ref $Route->{scopes} eq 'ARRAY' ? $Route->{scopes} : [],
            summary => $Route->{summary} || '',
        };
    }
    return \@List;
}

sub _PathMatch {
    my ( $Self, %Param ) = @_;
    my $Definition = $Param{Definition} || '';
    my @Names;
    my @Segments = split m{/}, $Definition, -1;
    my @Regex;
    for my $Segment (@Segments) {
        if ( $Segment =~ m{\A\{([a-z][a-z0-9_]*)\}\z} ) {
            push @Names, $1;
            push @Regex, '([^/]+)';
        }
        else {
            $Segment =~ s{([\[\]().+*?^$|\\])}{\\$1}g;
            push @Regex, $Segment;
        }
    }
    my $Regex = join '/', @Regex;
    my $Path = $Param{Path} || '';
    return if $Path !~ m{\A$Regex\z};
    my @Value = @Names ? ( $Path =~ m{\A$Regex\z} ) : ();
    my %Parameter;
    for my $Index ( 0 .. $#Names ) {
        $Parameter{ $Names[$Index] } = $Value[$Index];
    }
    return \%Parameter;
}

sub _Failure {
    my ( $Self, %Param ) = @_;
    return {
        Status => 500,
        Body => { error => {
            code       => 'addon_handler_failed',
            message    => 'The add-on endpoint could not process this request.',
            request_id => $Param{RequestID} || '',
        } },
        ResultCode => 'addon_handler_failed',
    };
}

1;
