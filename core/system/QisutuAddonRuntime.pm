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

package QisutuAddonRuntime;

use strict;
use warnings;
use utf8;

use File::Spec;
use JSON::PP;

sub Apply {
    my ( $Class, %Param ) = @_;
    my $Config = $Param{Config} || {};
    my $DB     = $Param{DB};
    my $Root   = $Config->{Paths}->{Addons}
        || File::Spec->catdir( $Config->{RootPath} || '/opt/qisutu', 'addons' );

    my $Runtime = {
        APIVersion       => '1.0',
        Capabilities     => [qw(
            settings.v1 programs.v1 authentication.v1 tasks.v1
            services.v1 events.v1 rest-routes.v1 ui-slots.v1
        )],
        Packages         => [],
        LibraryPaths     => [],
        ProgramPaths     => [],
        TemplatePaths    => [],
        LanguagePaths    => [],
        AuthProviders    => [],
        Services         => [],
        EventSubscribers => [],
        RESTRoutes       => [],
        UISlots          => [],
    };
    $Config->{AddonRuntime} = $Runtime;
    return $Runtime if !$DB;

    my $Rows = eval {
        $DB->SelectAll(
            'SELECT package_identifier, version, installed_path, manifest_json
             FROM addon_package
             WHERE active = 1 AND status = "installed"
             ORDER BY package_identifier'
        );
    } || [];

    my %INC = map { $_ => 1 } @INC;
    for my $Row ( @{$Rows} ) {
        my $Identifier = lc( $Row->{package_identifier} || '' );
        my $Path = $Row->{installed_path} || '';
        next if $Identifier !~ m{\A[a-z][a-z0-9-]*(?:\.[a-z0-9][a-z0-9-]*)+\z};
        next if !$Path || index( $Path, $Root . '/' ) != 0;
        next if $Path =~ m{(?:\A|/)\.\.(?:/|\z)} || !-d $Path || -l $Path;
        my $Manifest = eval { JSON::PP->new->utf8(1)->decode( $Row->{manifest_json} || '{}' ) };
        next if !$Manifest || ref $Manifest ne 'HASH' || ( $Manifest->{id} || '' ) ne $Identifier;

        my $Lib = File::Spec->catdir( $Path, 'lib' );
        if ( -d $Lib && !-l $Lib ) {
            push @{ $Runtime->{LibraryPaths} }, $Lib;
            if ( !$INC{$Lib}++ ) {
                unshift @INC, $Lib;
            }
        }
        for my $Pair (
            [ ProgramPaths  => 'programs' ],
            [ TemplatePaths => 'templates' ],
            [ LanguagePaths => 'languages' ],
        ) {
            my $Directory = File::Spec->catdir( $Path, $Pair->[1] );
            push @{ $Runtime->{ $Pair->[0] } }, $Directory if -d $Directory && !-l $Directory;
        }
        for my $Provider ( @{ ref $Manifest->{auth_providers} eq 'ARRAY' ? $Manifest->{auth_providers} : [] } ) {
            next if ref $Provider ne 'HASH';
            push @{ $Runtime->{AuthProviders} }, {
                %{$Provider},
                package_identifier => $Identifier,
            };
        }
        for my $Definition (
            [ services          => 'Services' ],
            [ event_subscribers => 'EventSubscribers' ],
            [ rest_routes       => 'RESTRoutes' ],
            [ ui_slots          => 'UISlots' ],
        ) {
            for my $Item ( @{ ref $Manifest->{ $Definition->[0] } eq 'ARRAY' ? $Manifest->{ $Definition->[0] } : [] } ) {
                next if ref $Item ne 'HASH';
                push @{ $Runtime->{ $Definition->[1] } }, {
                    %{$Item},
                    package_identifier => $Identifier,
                    package_version    => $Row->{version} || '',
                    package_path       => $Path,
                };
            }
        }
        push @{ $Runtime->{Packages} }, {
            Identifier => $Identifier,
            Version    => $Row->{version} || '',
            Path       => $Path,
            Manifest   => $Manifest,
        };
    }
    return $Runtime;
}

1;
