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

use Encode qw(decode);
use File::Copy qw(copy);
use File::Path qw(make_path);
use File::Spec;
use File::Temp qw(tempdir);
use FindBin;
use Test::More;

my $Root = File::Spec->rel2abs( File::Spec->catdir( $FindBin::Bin, '..' ) );
my @Languages = qw(de en fr it pt-BR pt-PT es nl pl cs tr);

my $InstallerLanguagePath = File::Spec->catdir(
    $Root, 'core', 'language', 'installer',
);
my $English = do File::Spec->catfile( $InstallerLanguagePath, 'en.pm' );
ok( ref $English eq 'HASH', 'English installer reference catalog loads' );
cmp_ok(
    scalar keys %{$English},
    '>=',
    160,
    'installer reference catalog covers the complete browser wizard',
);

my %InstallerCatalog;
for my $Language (@Languages) {
    my $Path = File::Spec->catfile( $InstallerLanguagePath, "$Language.pm" );
    ok( -f $Path && !-l $Path, "$Language installer catalog is present" );

    my $Translation = do $Path;
    ok( ref $Translation eq 'HASH', "$Language installer catalog loads" );
    next if ref $Translation ne 'HASH';
    $InstallerCatalog{$Language} = $Translation;

    my @Missing = sort grep { !exists $Translation->{$_} } keys %{$English};
    my @Extra   = sort grep { !exists $English->{$_} } keys %{$Translation};
    is_deeply( \@Missing, [], "$Language contains every installer translation key" );
    is_deeply( \@Extra, [], "$Language contains no unknown installer translation key" );

    my @Empty = sort grep {
        !defined $Translation->{$_} || $Translation->{$_} eq ''
    } keys %{$English};
    is_deeply( \@Empty, [], "$Language contains no empty installer translations" );

    my @PlaceholderMismatch;
    for my $Key ( keys %{$English} ) {
        next if !exists $Translation->{$Key};
        my @Source = sort( ( $English->{$Key} || '' ) =~ m{(\{[^{}]+\})}g );
        my @Target = sort( ( $Translation->{$Key} || '' ) =~ m{(\{[^{}]+\})}g );
        push @PlaceholderMismatch, $Key
            if join( "\0", @Source ) ne join( "\0", @Target );
    }
    is_deeply(
        \@PlaceholderMismatch,
        [],
        "$Language preserves every installer placeholder",
    );
}

my $InstallScriptPath = File::Spec->catfile( $Root, 'install.sh' );
open my $InstallFH, '<:encoding(UTF-8)', $InstallScriptPath
    or die "Cannot open $InstallScriptPath: $!";
my $InstallScript = do { local $/; <$InstallFH> };
close $InstallFH;

like(
    $InstallScript,
    qr{\nselect_install_language\s*\n\s*if \[\[ "\$ROOT_PATH"},
    'terminal language selection runs before system preparation',
);
like(
    $InstallScript,
    qr{install_language=\$INSTALL_LANGUAGE},
    'selected language is persisted in instance.conf',
);
like(
    $InstallScript,
    qr{if \[\[ ! -t 0 \]\]; then.*?Die Installationssprache muss ausgewählt werden[.]}s,
    'a non-interactive installation cannot silently skip the language choice',
);
unlike(
    $InstallScript,
    qr{if \[\[ ! -t 0 \]\]; then\s+INSTALL_LANGUAGE="de"},
    'a missing terminal no longer silently selects German',
);
cmp_ok(
    index( $InstallScript, 'if [[ ! -t 0 ]]' ),
    '<',
    index( $InstallScript, 'QISUTU_INSTALL_LANGUAGE' ),
    'an interactive terminal always receives the numbered language menu',
);

for my $Index ( 0 .. $#Languages ) {
    my $Selection = $Index + 1;
    my $Language  = $Languages[$Index];
    like(
        $InstallScript,
        qr{\Q$Selection) INSTALL_LANGUAGE="$Language"\E},
        "terminal option $Selection selects $Language",
    );
}

my $BrowserInstallerPath = File::Spec->catfile(
    $Root, 'bin', 'cgi-bin', 'install.pl',
);
open my $BrowserFH, '<:encoding(UTF-8)', $BrowserInstallerPath
    or die "Cannot open $BrowserInstallerPath: $!";
my $BrowserInstaller = do { local $/; <$BrowserFH> };
close $BrowserFH;

like(
    $BrowserInstaller,
    qr{\$State->\{ui_language\}\s*=\s*\$InstallLanguage},
    'browser wizard adopts the terminal language',
);
like(
    $BrowserInstaller,
    qr{\$State->\{default_language\}\s*=\s*\$InstallLanguage},
    'terminal language is preselected as the system default',
);
like(
    $BrowserInstaller,
    qr{<html lang="' \. _Escape\(\$UILanguage\)},
    'browser output declares the active installer language',
);
unlike(
    $BrowserInstaller,
    qr{\$State->\{default_language\}\s*\|\|=\s*'de'},
    'browser installer no longer forces German as the default language',
);

my $RenderRoot = tempdir( CLEANUP => 1 );
for my $Directory (
    [qw(core config)],
    [qw(core language)],
    [qw(core language installer)],
    [qw(install sql)],
    [qw(var install)],
    [qw(var log)],
) {
    make_path( File::Spec->catdir( $RenderRoot, @{$Directory} ) );
}

for my $Relative (
    'release.conf',
    'LICENSE',
    'THIRD_PARTY_NOTICES.md',
    File::Spec->catfile( 'core', 'config', 'QisutuConfig.pm' ),
    File::Spec->catfile( 'install', 'sql', 'schema.sql' ),
    File::Spec->catfile( 'install', 'sql', 'insert.sql' ),
) {
    my $Source = File::Spec->catfile( $Root, split m{/}, $Relative );
    my $Target = File::Spec->catfile( $RenderRoot, split m{/}, $Relative );
    copy( $Source, $Target ) or die "Cannot copy $Source to $Target: $!";
}

for my $Language (@Languages) {
    for my $InstallerCatalogFlag ( 0, 1 ) {
        my @Subdirectory = $InstallerCatalogFlag
            ? qw(core language installer)
            : qw(core language);
        my $Source = File::Spec->catfile(
            $Root, @Subdirectory, "$Language.pm",
        );
        my $Target = File::Spec->catfile(
            $RenderRoot, @Subdirectory, "$Language.pm",
        );
        copy( $Source, $Target ) or die "Cannot copy $Source to $Target: $!";
    }
}

my $InstanceFile = File::Spec->catfile(
    $RenderRoot, 'var', 'install', 'instance.conf',
);
for my $Language (@Languages) {
    open my $InstanceFH, '>:encoding(UTF-8)', $InstanceFile
        or die "Cannot create $InstanceFile: $!";
    print {$InstanceFH} "instance_id=qisutu\n";
    print {$InstanceFH} "web_path=/qisutu\n";
    print {$InstanceFH} "session_cookie=QISUTU_SESSION\n";
    print {$InstanceFH} "db_name=qisutu\n";
    print {$InstanceFH} "db_user=qisutu\n";
    print {$InstanceFH} "install_language=$Language\n";
    close $InstanceFH;

    local %ENV = (
        %ENV,
        QISUTU_HOME     => $RenderRoot,
        REQUEST_METHOD  => 'GET',
        QUERY_STRING    => '',
        CONTENT_LENGTH  => 0,
        HTTP_COOKIE     => '',
        HTTP_HOST       => 'qisutu.example',
        REMOTE_ADDR     => '127.0.0.1',
        GATEWAY_INTERFACE => 'CGI/1.1',
    );
    my $Output = qx{$^X "$BrowserInstallerPath"};
    is( $? >> 8, 0, "$Language browser welcome page renders successfully" );
    $Output = decode( 'UTF-8', $Output );
    like(
        $Output,
        qr{<html lang="\Q$Language\E"},
        "$Language browser welcome page declares the selected language",
    );
    like(
        $Output,
        qr{\Q$InstallerCatalog{$Language}->{WelcomeHeading}\E},
        "$Language browser welcome page uses its translated heading",
    );
}

done_testing();
