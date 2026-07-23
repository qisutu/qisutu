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

use lib File::Spec->catdir( $FindBin::Bin, '..', 'core', 'system' );

use QisutuDispatcher;
use QisutuTheme;
use QisutuUserPreference;

my $Root = File::Spec->catdir( $FindBin::Bin, '..' );
my $Config = {
    Paths => {
        Config      => File::Spec->catdir( $Root, 'core', 'config' ),
        ThemeConfig => File::Spec->catdir( $Root, 'core', 'config', 'themes' ),
        Language    => File::Spec->catdir( $Root, 'core', 'language' ),
        Output      => File::Spec->catdir( $Root, 'core', 'output' ),
        StaticURL   => '/qisutu/static',
    },
    Language => { Default => 'de' },
    System   => { Name => 'Qisutu', Version => '0.0.79' },
};

my $ThemeObject = QisutuTheme->new( Config => $Config );
is_deeply(
    [ map { $_->{Key} } @{ $ThemeObject->List() } ],
    [ 'default', 'christmas' ],
    'the central registry exposes the default and Christmas themes in order',
);
is( $ThemeObject->KeyClean( Key => 'christmas' ), 'christmas', 'the Christmas preference is accepted' );
is( $ThemeObject->KeyClean( Key => '../../bad.css' ), 'default', 'an unsafe theme preference falls back to default' );

my $AgentChristmas = $ThemeObject->Resolve(
    Key         => 'christmas',
    User        => { account_type => 'agent' },
    ActiveName  => 'Tickets',
    CurrentName => 'AgentTicketList',
);
is( $AgentChristmas->{BodyClass}, 'qisutu-theme-christmas', 'the Christmas body class is active on agent pages' );
is( $AgentChristmas->{Stylesheet}, 'themes/christmas.css', 'the agent page receives the separate Christmas stylesheet' );

my $AdminTheme = $ThemeObject->Resolve(
    Key         => 'christmas',
    User        => { account_type => 'agent' },
    ActiveName  => 'Admin',
    CurrentName => 'AdminAgents',
);
is( $AdminTheme->{Key}, 'default', 'administration pages always resolve to the default theme' );
is( $AdminTheme->{Stylesheet}, '', 'administration pages never load Christmas CSS' );

my $CustomerTheme = $ThemeObject->Resolve(
    Key         => 'christmas',
    User        => { account_type => 'customer' },
    ActiveName  => 'Tickets',
    CurrentName => 'CustomerTicketList',
);
is( $CustomerTheme->{Key}, 'default', 'the customer portal always resolves to the default theme' );

{
    package Local::ThemeDB;

    sub new { return bless { Rows => [], Writes => [] }, shift }
    sub Error { return '' }
    sub SelectAll { return [ map { { %$_ } } @{ shift->{Rows} } ] }
    sub Do {
        my ( $Self, $SQL, @Bind ) = @_;
        push @{ $Self->{Writes} }, \@Bind;
        return 1;
    }
}

my $DB = Local::ThemeDB->new();
$DB->{Rows} = [ { preference_key => 'theme', preference_value => 'christmas' } ];
my $Preferences = QisutuUserPreference->new( Config => $Config, DB => $DB );
is(
    $Preferences->AgentPreferenceGet( UserAccountID => 8 )->{theme},
    'christmas',
    'the selected theme is read from the existing preference table',
);

$DB->{Writes} = [];
ok(
    $Preferences->AgentPreferenceSave(
        UserAccountID => 8,
        Request       => {
            PreferenceLanguage   => 'de',
            Timezone             => 'Europe/Berlin',
            Theme                => 'christmas',
            StartPage            => 'Dashboard',
            TicketListLimit      => 20,
            TicketAfterReplyAction => 'stay',
        },
    ),
    'agent preferences including the theme can be saved',
);
my ($ThemeWrite) = grep { ( $_->[1] || '' ) eq 'theme' } @{ $DB->{Writes} };
is_deeply( $ThemeWrite, [ 8, 'theme', 'christmas' ], 'the theme is persisted as a normal user preference' );

my $Dispatcher = QisutuDispatcher->new( Config => $Config );
my $DispatcherAdminTheme = $Dispatcher->_ThemeData(
    User        => { account_type => 'agent' },
    Preference  => { theme => 'christmas' },
    ActiveName  => 'Admin',
    CurrentName => 'AdminQueues',
);
is( $DispatcherAdminTheme->{Stylesheet}, '', 'the dispatcher enforces the administration exclusion' );

{
    package Local::ThemeProgramRegistry;
    sub NavigationHTML { return '' }
}
{
    package Local::ThemeDispatcher;
    use parent 'QisutuDispatcher';
    sub _UserPreferenceGet { return { language => 'de', timezone => 'Europe/Berlin', theme => 'christmas' } }
    sub _DefaultLanguage { return 'de' }
}
my $LayoutDispatcher = Local::ThemeDispatcher->new(
    Config          => $Config,
    ProgramRegistry => bless( {}, 'Local::ThemeProgramRegistry' ),
);
my $AgentLayout = $LayoutDispatcher->_BaseData(
    User        => { user_account_id => 8, account_type => 'agent', login => 'agent' },
    ActiveName  => 'Tickets',
    CurrentName => 'AgentTicketList',
);
like( $AgentLayout->{BodyClass}, qr{\bqisutu-page-agentticketlist\b}, 'the layout exposes a stable page class for theme placement' );
like( $AgentLayout->{BodyClass}, qr{\bqisutu-theme-christmas\b}, 'the agent layout activates the selected theme class' );
is( $AgentLayout->{ThemeCSS}, 'themes/christmas.css', 'the agent layout loads the selected theme stylesheet' );

my $AdminLayout = $LayoutDispatcher->_BaseData(
    User        => { user_account_id => 8, account_type => 'agent', login => 'agent' },
    ActiveName  => 'Admin',
    CurrentName => 'AdminAgents',
);
unlike( $AdminLayout->{BodyClass}, qr{qisutu-theme-christmas}, 'the administration layout contains no Christmas class' );
is( $AdminLayout->{ThemeCSS}, '', 'the administration layout contains no Christmas stylesheet' );

my $PreferencesTemplatePath = File::Spec->catfile( $Root, 'core', 'output', 'AgentPreferences.tt' );
open my $PreferencesTemplateHandle, '<:encoding(UTF-8)', $PreferencesTemplatePath or die $!;
my $PreferencesTemplate = do { local $/; <$PreferencesTemplateHandle> };
close $PreferencesTemplateHandle;
like( $PreferencesTemplate, qr{<select name="Theme">}, 'personal agent settings contain the theme selector' );
like( $PreferencesTemplate, qr{RAW[.]ThemeOptions}, 'available themes come from the central registry' );

my $HeadPath = File::Spec->catfile( $Root, 'core', 'output', 'Head.tt' );
open my $HeadHandle, '<:encoding(UTF-8)', $HeadPath or die $!;
my $HeadTemplate = do { local $/; <$HeadHandle> };
close $HeadHandle;
like( $HeadTemplate, qr{IF ThemeCSS}, 'theme CSS is loaded only when the dispatcher resolves an active theme' );

my $ChristmasCSSPath = File::Spec->catfile( $Root, 'var', 'static', 'css', 'themes', 'christmas.css' );
ok( -s $ChristmasCSSPath, 'the Christmas theme has its own stylesheet' );
open my $CSSHandle, '<:encoding(UTF-8)', $ChristmasCSSPath or die $!;
my $ChristmasCSS = do { local $/; <$CSSHandle> };
close $CSSHandle;
for my $Asset (qw(santa-hat santa reindeer sleigh gift)) {
    like( $ChristmasCSS, qr{\Q$Asset.svg\E}, "the Christmas stylesheet uses the $Asset decoration" );
    ok(
        -s File::Spec->catfile( $Root, 'var', 'static', 'img', 'themes', 'christmas', $Asset . '.svg' ),
        "the $Asset vector asset exists",
    );
}
unlike( $ChristmasCSS, qr{\@keyframes|animation\s*:}, 'the subtle theme contains no distracting animation' );

done_testing();
