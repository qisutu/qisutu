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

use File::Find;
use File::Spec;
use FindBin;
use Test::More;

my $Root = File::Spec->catdir( $FindBin::Bin, '..' );
my @Files;

find(
    {
        no_chdir => 1,
        wanted   => sub {
            return if !-f $_;

            my $Relative = File::Spec->abs2rel( $File::Find::name, $Root );
            $Relative =~ s{\\}{/}g;

            return if $Relative =~ m{^var/static/(?:css/ckeditor5|js/(?:chartjs|ckeditor5|qrcode-generator))/};
            return if $Relative =~ m{^(?:LICENSE|COPYRIGHT|release\.sha256)$};

            my $IsQisutuFile =
                   $Relative =~ /\.(?:pm|pl|t|tt|sql|sh|service|path|conf|remove)$/
                || $Relative =~ m{^var/static/js/qisutu-[^/]+\.js$}
                || $Relative =~ m{^var/static/css/qisutu[^/]*\.css$}
                || $Relative =~ m{^(?:README(?:\.[A-Za-z-]+)?|INSTALL|MODULES|THIRD_PARTY_NOTICES)\.md$}
                || $Relative eq '.gitignore';

            push @Files, [ $Relative, $File::Find::name ] if $IsQisutuFile;
        },
    },
    $Root,
);

my @Required = (
    'Qisutu - Open Source Ticket System',
    'Copyright (C) 2026 Franziska Steps',
    'Qisutu - Kim-KI, https://qisutu.de',
    'This file is part of Qisutu.',
    'Qisutu is free software: you can redistribute it and/or modify',
    'Qisutu is distributed in the hope that it will be useful,',
    'You should have received a copy of the GNU Affero General Public License',
    'SPDX-FileCopyrightText: 2026 Franziska Steps',
    'SPDX-License-Identifier: AGPL-3.0-or-later',
);

my @Problems;
for my $Entry ( sort { $a->[0] cmp $b->[0] } @Files ) {
    my ( $Relative, $Path ) = @{$Entry};

    open my $FH, '<:raw', $Path or do {
        push @Problems, "$Relative: nicht lesbar: $!";
        next;
    };

    read $FH, my $ContentStart, 8192;
    close $FH;

    my @HeadLines = split /(?<=\n)/, $ContentStart;
    my $Head = join '', @HeadLines[ 0 .. ( $#HeadLines < 44 ? $#HeadLines : 44 ) ];

    for my $Required (@Required) {
        if ( index( $Head, $Required ) < 0 ) {
            push @Problems, "$Relative: Kopfbereich unvollstaendig; fehlt: $Required";
            last;
        }
    }

    my $TitleCount = () = $Head =~ /Qisutu \- Open Source Ticket System/g;
    my $LicenseCount = () = $Head =~ /SPDX\-License\-Identifier: AGPL\-3\.0\-or\-later/g;
    if ( $TitleCount != 1 || $LicenseCount != 1 ) {
        push @Problems,
            "$Relative: Kopfbereich nicht eindeutig (Titel: $TitleCount, SPDX-Lizenz: $LicenseCount)";
    }

    if ( $Relative =~ /\.(?:pl|sh)$/ && $Head !~ /\A#!/ ) {
        push @Problems, "$Relative: Shebang fehlt in Zeile 1";
    }
}

ok( scalar(@Files) >= 300, 'alle erwarteten Qisutu-Dateien wurden erfasst' );
is_deeply( \@Problems, [], 'alle Qisutu-Dateien besitzen den vollständigen Lizenzkopf' )
    or diag join "\n", @Problems;

done_testing();
