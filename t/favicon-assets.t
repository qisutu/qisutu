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

use File::Spec;
use FindBin;
use Test::More;

my $Root = File::Spec->catdir( $FindBin::Bin, '..' );
my $ImagePath = File::Spec->catdir( $Root, 'var', 'static', 'img' );

my $Favicon = _ReadBinary( File::Spec->catfile( $ImagePath, 'favicon.ico' ) );
is( substr( $Favicon, 0, 6 ), "\x00\x00\x01\x00\x01\x00", 'favicon is a valid single-image ICO file' );
is( ord( substr( $Favicon, 6, 1 ) ), 32, 'favicon contains a 32 pixel wide icon' );
is( ord( substr( $Favicon, 7, 1 ) ), 32, 'favicon contains a 32 pixel high icon' );

my $AppleIcon = _ReadBinary( File::Spec->catfile( $ImagePath, 'apple-touch-icon.png' ) );
is( substr( $AppleIcon, 0, 8 ), "\x89PNG\x0d\x0a\x1a\x0a", 'Apple touch icon is a valid PNG file' );
my ( $Width, $Height ) = unpack( 'NN', substr( $AppleIcon, 16, 8 ) );
is( $Width, 180, 'Apple touch icon is 180 pixels wide' );
is( $Height, 180, 'Apple touch icon is 180 pixels high' );

my $Head = _ReadText( File::Spec->catfile( $Root, 'core', 'output', 'Head.tt' ) );
like( $Head, qr{rel="icon"[^>]+favicon[.]ico}, 'central application head includes the favicon' );
like( $Head, qr{rel="apple-touch-icon"[^>]+apple-touch-icon[.]png}, 'central application head includes the Apple touch icon' );

my $PublicForm = _ReadText( File::Spec->catfile( $Root, 'core', 'output', 'PublicTicketForm.tt' ) );
like( $PublicForm, qr{rel="icon"[^>]+favicon[.]ico}, 'public ticket form includes the favicon' );
like( $PublicForm, qr{rel="apple-touch-icon"[^>]+apple-touch-icon[.]png}, 'public ticket form includes the Apple touch icon' );

my $Installer = _ReadText( File::Spec->catfile( $Root, 'bin', 'cgi-bin', 'install.pl' ) );
like( $Installer, qr{rel=\"icon\"[^>]+favicon[.]ico}, 'web installer includes the favicon' );
like( $Installer, qr{rel=\"apple-touch-icon\"[^>]+apple-touch-icon[.]png}, 'web installer includes the Apple touch icon' );

done_testing();

sub _ReadBinary {
    my ($Path) = @_;
    open my $Handle, '<:raw', $Path or die "Cannot read $Path: $!";
    local $/;
    my $Content = <$Handle>;
    close $Handle;
    return defined $Content ? $Content : '';
}

sub _ReadText {
    my ($Path) = @_;
    open my $Handle, '<:encoding(UTF-8)', $Path or die "Cannot read $Path: $!";
    local $/;
    my $Content = <$Handle>;
    close $Handle;
    return defined $Content ? $Content : '';
}
