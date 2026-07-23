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

package QisutuTheme;

use strict;
use warnings;
use utf8;

use File::Spec;

sub new {
    my ( $Class, %Param ) = @_;

    return bless {
        Config    => $Param{Config} || {},
        Themes    => undef,
        LastError => '',
    }, $Class;
}

sub List {
    my ($Self) = @_;

    return $Self->{Themes} if $Self->{Themes};

    my $ConfigPath = $Self->{Config}->{Paths}->{ThemeConfig};
    if ( !$ConfigPath ) {
        my $BaseConfigPath = $Self->{Config}->{Paths}->{Config} || '';
        $ConfigPath = File::Spec->catdir( $BaseConfigPath, 'themes' ) if $BaseConfigPath;
    }

    my @Themes;
    if ( $ConfigPath && -d $ConfigPath ) {
        opendir my $DirectoryHandle, $ConfigPath or do {
            $Self->{LastError} = "Could not open theme config path: $ConfigPath";
            return $Self->_FallbackList();
        };
        my @Files = sort grep { m{[.]pm\z} } readdir $DirectoryHandle;
        closedir $DirectoryHandle;

        for my $File (@Files) {
            my $Theme = do File::Spec->catfile( $ConfigPath, $File );
            next if ref $Theme ne 'HASH';
            next if !$Self->_ThemeValid( Theme => $Theme );
            push @Themes, { %{$Theme} };
        }
    }

    if ( !grep { ( $_->{Key} || '' ) eq 'default' } @Themes ) {
        push @Themes, @{ $Self->_FallbackList() };
    }

    my %Seen;
    @Themes = grep { !$Seen{ $_->{Key} }++ && $_->{Active} } @Themes;
    @Themes = sort {
        ( $a->{Order} || 0 ) <=> ( $b->{Order} || 0 )
            || ( $a->{Key} || '' ) cmp ( $b->{Key} || '' )
    } @Themes;

    $Self->{Themes} = \@Themes;
    return $Self->{Themes};
}

sub Get {
    my ( $Self, %Param ) = @_;

    my $Key = $Self->KeyClean( Key => $Param{Key} );
    for my $Theme ( @{ $Self->List() } ) {
        return $Theme if ( $Theme->{Key} || '' ) eq $Key;
    }

    return $Self->_DefaultTheme();
}

sub KeyClean {
    my ( $Self, %Param ) = @_;

    my $Key = lc( $Param{Key} || '' );
    $Key =~ s{\A\s+|\s+\z}{}g;
    return 'default' if $Key !~ m{\A[a-z][a-z0-9_-]{0,49}\z};

    for my $Theme ( @{ $Self->List() } ) {
        return $Key if ( $Theme->{Key} || '' ) eq $Key;
    }

    return 'default';
}

sub Resolve {
    my ( $Self, %Param ) = @_;

    my $Theme = $Self->Get( Key => $Param{Key} );
    my $User  = $Param{User} || {};
    my $ActiveName  = $Param{ActiveName} || '';
    my $CurrentName = $Param{CurrentName} || '';

    return $Self->_DefaultTheme() if $Theme->{AgentOnly} && ( $User->{account_type} || '' ) ne 'agent';
    return $Self->_DefaultTheme()
        if $Theme->{ExcludeAdmin} && ( $ActiveName eq 'Admin' || $CurrentName =~ m{\AAdmin} );

    return $Theme;
}

sub Error {
    my ($Self) = @_;
    return $Self->{LastError};
}

sub _ThemeValid {
    my ( $Self, %Param ) = @_;

    my $Theme = $Param{Theme} || {};
    return if ( $Theme->{Key} || '' ) !~ m{\A[a-z][a-z0-9_-]{0,49}\z};
    return if ( $Theme->{Title} || '' ) !~ m{\A[A-Za-z][A-Za-z0-9_]{0,99}\z};
    return if ( $Theme->{BodyClass} || '' ) !~ m{\A[A-Za-z0-9_-]*\z};
    return if ( $Theme->{Stylesheet} || '' ) !~ m{\A(?:themes/[A-Za-z0-9_/-]+[.]css)?\z};
    return if ( $Theme->{Version} || '' ) !~ m{\A[0-9]{1,20}\z};

    return 1;
}

sub _DefaultTheme {
    my ($Self) = @_;

    for my $Theme ( @{ $Self->List() } ) {
        return $Theme if ( $Theme->{Key} || '' ) eq 'default';
    }

    return $Self->_FallbackList()->[0];
}

sub _FallbackList {
    return [ {
        Key          => 'default',
        Title        => 'ThemeDefault',
        Stylesheet   => '',
        BodyClass    => '',
        Version      => '1',
        AgentOnly    => 1,
        ExcludeAdmin => 1,
        Order        => 10,
        Active       => 1,
    } ];
}

1;
