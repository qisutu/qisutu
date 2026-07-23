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

package QisutuAddonAPI;

use strict;
use warnings;
use utf8;

sub new {
    my ( $Class, %Param ) = @_;
    my $Identifier = lc( $Param{Identifier} || '' );
    return if $Identifier !~ m{\A[a-z][a-z0-9-]*(?:\.[a-z0-9][a-z0-9-]*)+\z};

    my $Self = {
        Config     => $Param{Config} || {},
        DB         => $Param{DB},
        Identifier => $Identifier,
        LastError  => '',
    };
    bless $Self, $Class;
    return $Self;
}

sub Version {
    my ($Self) = @_;
    return ( $Self->{Config}->{AddonRuntime} || {} )->{APIVersion} || '1.0';
}

sub Identifier {
    my ($Self) = @_;
    return $Self->{Identifier};
}

sub CapabilityList {
    my ($Self) = @_;
    return [ @{ ( $Self->{Config}->{AddonRuntime} || {} )->{Capabilities} || [] } ];
}

sub CapabilityAvailable {
    my ( $Self, %Param ) = @_;
    my $Capability = $Param{Capability} || '';
    my %Available = map { $_ => 1 } @{ $Self->CapabilityList() };
    return $Available{$Capability} ? 1 : 0;
}

sub SettingsGet {
    my ($Self) = @_;
    require QisutuAddonManager;
    my $Manager = QisutuAddonManager->new( Config => $Self->{Config}, DB => $Self->{DB} );
    return $Manager->SettingsGet( Identifier => $Self->{Identifier} );
}

sub SettingsSave {
    my ( $Self, %Param ) = @_;
    require QisutuAddonManager;
    my $Manager = QisutuAddonManager->new( Config => $Self->{Config}, DB => $Self->{DB} );
    my $OK = $Manager->SettingsSave(
        Identifier => $Self->{Identifier},
        Values     => ref $Param{Values} eq 'HASH' ? $Param{Values} : {},
        UserID     => $Param{UserID} || 1,
    );
    $Self->{LastError} = $Manager->Error() if !$OK;
    return $OK;
}

sub ServiceGet {
    my ( $Self, %Param ) = @_;
    $Self->{LastError} = '';
    my $Requested = $Param{Service} || '';
    my ( $Identifier, $Key ) = $Requested =~ m{\A([a-z][a-z0-9-]*(?:\.[a-z0-9][a-z0-9-]*)+):([a-z][a-z0-9_.-]*)\z}
        ? ( $1, $2 )
        : ( $Self->{Identifier}, $Requested );
    if ( !$Key || $Key !~ m{\A[a-z][a-z0-9_.-]{0,189}\z} ) {
        $Self->{LastError} = 'invalid add-on service key';
        return;
    }

    my ($Definition) = grep {
        ( $_->{package_identifier} || '' ) eq $Identifier
            && ( $_->{key} || '' ) eq $Key
    } @{ ( $Self->{Config}->{AddonRuntime} || {} )->{Services} || [] };
    if ( !$Definition ) {
        $Self->{LastError} = 'add-on service is not registered';
        return;
    }

    my $CacheKey = $Identifier . ':' . $Key;
    my $Cache = $Self->{Config}->{AddonRuntime}->{ServiceObjects} ||= {};
    return $Cache->{$CacheKey} if $Cache->{$CacheKey};

    my $Class = $Definition->{class} || '';
    if ( $Class !~ m{\AQisutu::Addon::[A-Za-z0-9_:]+\z} || !eval "require $Class; 1;" ) {
        $Self->{LastError} = $@ || 'add-on service class could not be loaded';
        return;
    }
    my $API = QisutuAddonAPI->new(
        Config     => $Self->{Config},
        DB         => $Self->{DB},
        Identifier => $Identifier,
    );
    my $Object = eval {
        $Class->new(
            Config     => $Self->{Config},
            DB         => $Self->{DB},
            API        => $API,
            Definition => $Definition,
        );
    };
    if ( !$Object ) {
        $Self->{LastError} = $@ || 'add-on service could not be created';
        return;
    }
    $Cache->{$CacheKey} = $Object;
    return $Object;
}

sub EventEmit {
    my ( $Self, %Param ) = @_;
    require QisutuAddonEvent;
    my $Event = QisutuAddonEvent->new( Config => $Self->{Config}, DB => $Self->{DB} );
    my $OK = $Event->Emit(
        Event   => $Param{Event},
        Payload => ref $Param{Payload} eq 'HASH' ? $Param{Payload} : {},
        Source  => $Self->{Identifier},
    );
    $Self->{LastError} = $Event->Error() if !$OK;
    return $OK;
}

sub Error {
    my ($Self) = @_;
    return $Self->{LastError} || '';
}

1;
