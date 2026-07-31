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

use Digest::SHA qw(sha256_hex);
use File::Path qw(make_path);
use File::Spec;
use File::Temp qw(tempdir);
use FindBin;
use IO::Compress::Zip qw($ZipError);
use JSON::PP;
use Test::More;

use lib File::Spec->catdir( $FindBin::Bin, '..', 'core', 'config' );
use lib File::Spec->catdir( $FindBin::Bin, '..', 'core', 'system' );
use lib File::Spec->catdir( $FindBin::Bin, '..', 'core', 'output' );
use QisutuAddonManager;
use QisutuAddonRuntime;
use QisutuOutput;
use QisutuProgramRegistry;

my $Root = File::Spec->catdir( $FindBin::Bin, '..' );
ok( !-d File::Spec->catdir( $Root, 'contrib' ), 'the Qisutu core release contains no bundled add-on source tree' );
my $Blob = _GenericModuleZIP( Version => '1.0.0' );
ok( length($Blob) > 500, 'the generic source-module ZIP fixture is non-empty' );

my $Config = {
    RootPath => $Root,
    Paths => {
        Addons      => File::Spec->catdir( $Root, 'addons' ),
        Static      => File::Spec->catdir( $Root, 'var', 'static' ),
        Output      => File::Spec->catdir( $Root, 'core', 'output' ),
        Language    => File::Spec->catdir( $Root, 'core', 'language' ),
        ProgramConfig => File::Spec->catdir( $Root, 'core', 'config', 'programs' ),
    },
    System => { Version => '0.0.79' },
    Language => { Default => 'de' },
};
my $Manager = QisutuAddonManager->new( Config => $Config );
my $Inspection = $Manager->PackageInspect( Content => $Blob );
ok( $Inspection, 'an ordinary source-module ZIP passes the same validation used by the admin upload' )
    or diag $Manager->Error();
is( $Inspection->{Manifest}->{manifest_version}, 1, 'the readable installation description uses manifest version 1' );
is( $Inspection->{Manifest}->{id}, 'example.lifecycle', 'the module has a stable generic identifier' );
is( $Inspection->{Manifest}->{version}, '1.0.0', 'the generic fixture has a real semantic version' );
is( $Inspection->{SignatureStatus}, 'source-zip', 'the upload is recorded as a source ZIP' );
ok( $Manager->_VersionGreater( '1.0.0', '1.0.0-rc.1' ), 'semantic-version comparison treats a final release as newer than its prerelease' );
ok( exists $Inspection->{Files}->{'lib/Qisutu/Addon/Example/AuthProvider.pm'}, 'the ZIP contains an isolated provider class' );
ok( exists $Inspection->{Files}->{'lib/Qisutu/Addon/Example/SyncTask.pm'}, 'the ZIP contains an isolated background task class' );
ok( exists $Inspection->{Files}->{'static/js/example.js'}, 'the ZIP contains readable JavaScript source' );
is( $Inspection->{Manifest}->{addon_api}->{minimum}, '1.0', 'the manifest may request the stable add-on API' );
is( $Inspection->{Manifest}->{services}->[0]->{key}, 'example.service', 'the manifest declares a reusable module service' );
is( $Inspection->{Manifest}->{event_subscribers}->[0]->{event}, 'ticket.*', 'the manifest declares an asynchronous core-event subscription' );
is( $Inspection->{Manifest}->{rest_routes}->[0]->{path}, '/v1/addons/example.lifecycle/status', 'the manifest declares an isolated REST route' );
is( $Inspection->{Manifest}->{ui_slots}->[0]->{slot}, 'admin.after', 'the manifest declares a controlled UI slot' );

my %FutureAPIFiles = %{ $Inspection->{Files} };
my $FutureAPIManifest = JSON::PP->new->utf8(1)->decode( $FutureAPIFiles{'qisutu-module.json'} );
$FutureAPIManifest->{addon_api}->{minimum} = '2.0';
$FutureAPIFiles{'qisutu-module.json'} = JSON::PP->new->canonical(1)->utf8(1)->encode($FutureAPIManifest);
my $FutureAPIZIP = _ZipCreate( map { ( 'ExampleLifecycle/' . $_ ) => $FutureAPIFiles{$_} } keys %FutureAPIFiles );
ok( !$Manager->PackageInspect( Content => $FutureAPIZIP ), 'a module requiring a future add-on API is rejected before installation' );
like( $Manager->Error(), qr{AddonAPIIncompatible}, 'an incompatible internal API has a specific error' );

my %FutureCapabilityFiles = %{ $Inspection->{Files} };
my $FutureCapabilityManifest = JSON::PP->new->utf8(1)->decode( $FutureCapabilityFiles{'qisutu-module.json'} );
push @{ $FutureCapabilityManifest->{addon_api}->{capabilities} }, 'future.v9';
$FutureCapabilityFiles{'qisutu-module.json'} = JSON::PP->new->canonical(1)->utf8(1)->encode($FutureCapabilityManifest);
my $FutureCapabilityZIP = _ZipCreate( map { ( 'ExampleLifecycle/' . $_ ) => $FutureCapabilityFiles{$_} } keys %FutureCapabilityFiles );
ok( !$Manager->PackageInspect( Content => $FutureCapabilityZIP ), 'a module requiring an unavailable capability is rejected before installation' );
like( $Manager->Error(), qr{AddonCapabilityUnavailable}, 'an unavailable API capability has a specific error' );

my %UndeclaredFiles = %{ $Inspection->{Files} };
$UndeclaredFiles{'static/js/not-declared.js'} = "window.NotDeclared = true;\n";
my $UndeclaredZIP = _ZipCreate(
    map { ( 'ExampleLifecycle/' . $_ ) => $UndeclaredFiles{$_} } keys %UndeclaredFiles
);
ok( !$Manager->PackageInspect( Content => $UndeclaredZIP ), 'a source file missing from the readable installation description is rejected' );
like( $Manager->Error(), qr{AddonPackageFileUndeclared}, 'undeclared source files have a specific error' );

my %UnsafePermissionFiles = %{ $Inspection->{Files} };
my $UnsafePermissionManifest = JSON::PP->new->utf8(1)->decode( $UnsafePermissionFiles{'qisutu-module.json'} );
$UnsafePermissionManifest->{files}->[0]->{permission} = '0777';
$UnsafePermissionFiles{'qisutu-module.json'} = JSON::PP->new->canonical(1)->utf8(1)->encode($UnsafePermissionManifest);
my $UnsafePermissionZIP = _ZipCreate(
    map { ( 'ExampleLifecycle/' . $_ ) => $UnsafePermissionFiles{$_} } keys %UnsafePermissionFiles
);
ok( !$Manager->PackageInspect( Content => $UnsafePermissionZIP ), 'an unsafe permission in qisutu-module.json is rejected' );
like( $Manager->Error(), qr{AddonManifestFilesInvalid}, 'unsafe declared permissions have a specific error' );

my $Corrupt = substr( $Blob, 0, length($Blob) - 12 );
ok( !$Manager->PackageInspect( Content => $Corrupt ), 'a truncated module ZIP is rejected' );

my $Unsafe = _ZipCreate(
    '../outside.pm' => 'unsafe',
    'qisutu-module.json' => '{}',
    'checksums.sha256' => '',
);
ok( !$Manager->PackageInspect( Content => $Unsafe ), 'a module ZIP path traversal entry is rejected' );
like( $Manager->Error(), qr{AddonPackagePathInvalid}, 'unsafe path rejection has a specific error' );

{
    package Local::LifecycleDB;
    sub new { bless { Package => undef }, $_[0] }
    sub Error { return $_[0]->{Error} || '' }
    sub SelectRow {
        my ( $Self, $SQL, @Bind ) = @_;
        return $Self->{Package} if $SQL =~ m{FROM addon_package};
        return if $SQL =~ m{FROM addon_migration};
        return;
    }
    sub SelectAll {
        my ( $Self, $SQL, @Bind ) = @_;
        return [] if $SQL =~ m{FROM addon_task};
        return [] if $SQL =~ m{FROM addon_setting};
        return [];
    }
    sub Do {
        my ( $Self, $SQL, @Bind ) = @_;
        if ( $SQL =~ m{INSERT INTO addon_package} ) {
            $Self->{Package} = {
                package_identifier => $Bind[0], name => $Bind[1], vendor => $Bind[2],
                version => $Bind[3], description => $Bind[4], installed_path => $Bind[5],
                manifest_json => $Bind[6], package_checksum_sha256 => $Bind[7],
                signature_status => $Bind[8], active => 1,
                status => 'installed',
            };
        }
        elsif ( $SQL =~ m{UPDATE addon_package SET active = 0, status = "removing"} ) {
            $Self->{Package}->{active} = 0;
            $Self->{Package}->{status} = 'removing';
        }
        elsif ( $SQL =~ m{DELETE FROM addon_package} ) {
            $Self->{Package} = undef;
        }
        return 1;
    }
}

my $LifecycleRoot = tempdir( CLEANUP => 1 );
my $LifecycleDB = Local::LifecycleDB->new();
my $LifecycleConfig = {
    RootPath => $LifecycleRoot,
    Paths => {
        Addons => File::Spec->catdir( $LifecycleRoot, 'addons' ),
        Static => File::Spec->catdir( $LifecycleRoot, 'var', 'static' ),
    },
    System => { Version => '0.0.79' },
};
my $LifecycleManager = QisutuAddonManager->new( Config => $LifecycleConfig, DB => $LifecycleDB );
my $InstalledResult = $LifecycleManager->_PackageInstallOrUpdate( Operation => {
    id => 1, operation_type => 'install', package_identifier => 'example.lifecycle', package_data => $Blob,
    package_checksum_sha256 => sha256_hex($Blob), requested_by_user_id => 1,
} );
ok( $InstalledResult, 'the daemon-side lifecycle installs the validated source ZIP on disk' )
    or diag $LifecycleManager->Error();
ok( -f File::Spec->catfile( $LifecycleDB->{Package}->{installed_path}, 'qisutu-module.json' ), 'installation publishes the manifest below the isolated add-on root' );
ok( $LifecycleDB->{Package}->{active}, 'a newly installed add-on becomes active without a separate core configuration function' );
is( ( stat File::Spec->catfile( $LifecycleDB->{Package}->{installed_path}, 'bin', 'example-task.pl' ) )[2] & 07777, 0755, 'declared executable permissions are applied only to module scripts' );

my $UpdateBlob = _ZIPWithVersion( Inspection => $Inspection, Version => '1.0.1' );
my $UpdatedResult = $LifecycleManager->_PackageInstallOrUpdate( Operation => {
    id => 2, operation_type => 'update', package_identifier => 'example.lifecycle', package_data => $UpdateBlob,
    package_checksum_sha256 => sha256_hex($UpdateBlob), requested_by_user_id => 1,
} );
ok( $UpdatedResult, 'the daemon-side lifecycle updates an installed source ZIP' )
    or diag $LifecycleManager->Error();
is( $LifecycleDB->{Package}->{version}, '1.0.1', 'the higher package version replaces the installed version' );
ok( $LifecycleDB->{Package}->{active}, 'an updated module remains available immediately' );
my $UninstalledResult = $LifecycleManager->_PackageUninstall( Operation => {
    id => 3, package_identifier => 'example.lifecycle', requested_by_user_id => 1,
} );
ok( $UninstalledResult, 'the daemon-side lifecycle uninstalls the add-on' )
    or diag $LifecycleManager->Error();
ok( !$LifecycleDB->{Package}, 'uninstallation removes the active package registry entry' );

my $Temporary = tempdir( CLEANUP => 1 );
my $AddonRoot = File::Spec->catdir( $Temporary, 'addons' );
my $Installed = File::Spec->catdir( $AddonRoot, 'example', 'runtime' );
make_path(
    File::Spec->catdir( $Installed, 'lib' ),
    File::Spec->catdir( $Installed, 'programs' ),
    File::Spec->catdir( $Installed, 'templates' ),
    File::Spec->catdir( $Installed, 'languages' ),
);
_WriteRaw( File::Spec->catfile( $Installed, 'templates', 'AddonProbe.tt' ), '<p>[% Translate.AddonProbeText %]</p>' );
_WriteRaw( File::Spec->catfile( $Installed, 'languages', 'de.json' ), '{"AddonProbeText":"Zusatzmodul aktiv"}' );
_WriteRaw(
    File::Spec->catfile( $Installed, 'programs', 'AddonProbe.json' ),
    JSON::PP->new->canonical(1)->encode({
        Name => 'AddonProbe', Module => 'Qisutu::Addon::Probe', Title => 'AddonProbeText',
        URL => 'index.pl?Page=AddonProbe', Type => 'ProgramOnly', AccessTypes => ['agent'], Active => 1,
    }),
);
my $RuntimeManifest = JSON::PP->new->canonical(1)->encode({
    manifest_version => 1, id => 'example.runtime', name => 'Runtime probe', version => '1.0.0',
    auth_providers => [{ key => 'probe-agent', class => 'Qisutu::Addon::ProbeAuth', account_type => 'agent' }],
    services => [{ key => 'probe.service', class => 'Qisutu::Addon::ProbeService' }],
    event_subscribers => [{ key => 'probe-event', event => 'ticket.*', class => 'Qisutu::Addon::ProbeEvent' }],
    rest_routes => [{ key => 'probe-rest', method => 'GET', path => '/v1/addons/example.runtime/status', class => 'Qisutu::Addon::ProbeREST', scopes => ['probe.read'] }],
    ui_slots => [{ key => 'probe-ui', slot => 'page.after', class => 'Qisutu::Addon::ProbeUI' }],
});

{
    package Local::AddonDB;
    sub new { bless { Row => $_[1] }, $_[0] }
    sub SelectAll { return [ $_[0]->{Row} ] }
}
my $RuntimeConfig = {
    RootPath => $Temporary,
    Paths => {
        Addons => $AddonRoot,
        Output => File::Spec->catdir( $Root, 'core', 'output' ),
        Language => File::Spec->catdir( $Root, 'core', 'language' ),
        ProgramConfig => File::Spec->catdir( $Root, 'core', 'config', 'programs' ),
    },
    Language => { Default => 'de' },
};
my $Runtime = QisutuAddonRuntime->Apply(
    Config => $RuntimeConfig,
    DB => Local::AddonDB->new({
        package_identifier => 'example.runtime', version => '1.0.0',
        installed_path => $Installed, manifest_json => $RuntimeManifest,
    }),
);
is( scalar @{ $Runtime->{Packages} }, 1, 'the runtime registers one active validated add-on' );
is( $Runtime->{AuthProviders}->[0]->{key}, 'probe-agent', 'the runtime exposes the add-on authentication provider' );
is( $Runtime->{APIVersion}, '1.0', 'the runtime exposes the stable add-on API version' );
ok( grep( { $_ eq 'events.v1' } @{ $Runtime->{Capabilities} } ), 'the runtime publishes its event capability' );
is( $Runtime->{Services}->[0]->{key}, 'probe.service', 'the runtime registers reusable services' );
is( $Runtime->{EventSubscribers}->[0]->{event}, 'ticket.*', 'the runtime registers event subscribers' );
is( $Runtime->{RESTRoutes}->[0]->{path}, '/v1/addons/example.runtime/status', 'the runtime registers isolated REST routes' );
is( $Runtime->{UISlots}->[0]->{slot}, 'page.after', 'the runtime registers controlled UI slots' );
ok( grep( { $_ eq File::Spec->catdir( $Installed, 'lib' ) } @INC ), 'the active add-on library is added to the Perl load path' );

my $Output = QisutuOutput->new( Config => $RuntimeConfig );
my $Rendered = $Output->RenderSingle( Template => 'AddonProbe.tt', Data => { Language => 'de' } );
like( $Rendered || '', qr{Zusatzmodul aktiv}, 'add-on templates and JSON translations render through the Qisutu output system' );

my $Registry = QisutuProgramRegistry->new( Config => $RuntimeConfig );
my $Program = $Registry->ProgramGet( Name => 'AddonProbe' );
ok( $Program, 'an active add-on program definition is registered' );
is( $Program->{Module}, 'Qisutu::Addon::Probe', 'the add-on program retains its isolated module class' );

my $Schema = _ReadRaw( File::Spec->catfile( $Root, 'install', 'sql', 'schema.sql' ) );
for my $Table (qw(addon_package addon_operation addon_setting addon_migration addon_auth_state addon_external_identity addon_task addon_event_queue)) {
    like( $Schema, qr{CREATE TABLE IF NOT EXISTS `\Q$Table\E`}, "fresh installations create $Table" );
}
like( $Schema, qr{INSERT INTO `database_version` \(`version`\) VALUES \('1[.]0[.]1'\)}, 'fresh installations use database version 1.0.1' );

my $Insert = _ReadRaw( File::Spec->catfile( $Root, 'install', 'sql', 'insert.sql' ) );
like( $Insert, qr{admin[.]addon[.]manage}, 'fresh installations grant the dedicated add-on management permission to administrators' );
like( $Schema, qr{CREATE TABLE IF NOT EXISTS `addon_event_queue`}, 'fresh installations create the persistent add-on event queue' );
my $Release = _ReadRaw( File::Spec->catfile( $Root, 'release.conf' ) );
like( $Release, qr{^version=1[.]0[.]2$}m, 'the versioned add-on API is included in release 1.0.1' );
like( $Release, qr{^database_version=1[.]0[.]1$}m, 'the add-on schema is included in the official database baseline' );
opendir my $BinDirectory, File::Spec->catdir( $Root, 'bin' ) or die "Cannot inspect bin directory: $!";
my @ModuleBuilder = grep { m{addon.*build}i } readdir $BinDirectory;
closedir $BinDirectory;
is( scalar @ModuleBuilder, 0, 'the Qisutu core contains no module creation or build tool' );
my $ModuleDocumentation = _ReadRaw( File::Spec->catfile( $Root, 'MODULES.md' ) );
unlike( $ModuleDocumentation, qr{Paket bauen|addon.*build}i, 'the module administration documentation contains no module build function' );
like( $ModuleDocumentation, qr{qisutu-module[.]json}, 'the readable JSON installation description is documented' );
my $AdminTemplate = _ReadRaw( File::Spec->catfile( $Root, 'core', 'output', 'AdminAddons.tt' ) );
like( $AdminTemplate, qr{accept="[.]zip,application/zip"}, 'the admin upload accepts ordinary ZIP files' );
my @AdminModuleSteps = sort( $AdminTemplate =~ m{name="Step" value="([A-Za-z]+)"}g );
is_deeply( \@AdminModuleSteps, [qw(PackageUninstall PackageUpload)], 'the core admin screen only installs, updates and uninstalls modules' );
my $ManagerSource = _ReadRaw( File::Spec->catfile( $Root, 'core', 'system', 'QisutuAddonManager.pm' ) );
like( $ManagerSource, qr{Filename !~ m\{\\[.]zip}, 'the module manager rejects non-ZIP upload names' );

my $Login = _ReadRaw( File::Spec->catfile( $Root, 'core', 'module', 'Login.pm' ) );
like( $Login, qr{ExternalAuthBegin}, 'the login flow supports generic external provider initiation' );
like( $Login, qr{ExternalAuthCallback}, 'the login flow supports generic external provider callbacks' );
like( $Login, qr{TwoFactor\}->Required}, 'external login continues through the existing two-factor policy' );
like( $Login, qr{auto_redirect}, 'the login flow supports provider-controlled automatic redirection' );
like( $Login, qr{ShowLocalAgentLogin}, 'the login flow can hide local agent authentication for a provider' );
my $AuthProvider = _ReadRaw( File::Spec->catfile( $Root, 'core', 'system', 'QisutuAuthProvider.pm' ) );
like( $AuthProvider, qr{CodeChallenge}, 'the generic provider contract supplies PKCE data' );
like( $AuthProvider, qr{nonce_encrypted}, 'the generic provider stores the OIDC nonce encrypted' );
like( $AuthProvider, qr{verifier_encrypted}, 'the generic provider stores the PKCE verifier encrypted' );
like( $AuthProvider, qr{auto_redirect_setting}, 'authentication providers may declare an automatic redirect setting' );
like( $AuthProvider, qr{allow_local_login_setting}, 'authentication providers may declare a local-login setting' );
my $LoginTemplate = _ReadRaw( File::Spec->catfile( $Root, 'core', 'output', 'Login.tt' ) );
like( $LoginTemplate, qr{IF ShowLocalAgentLogin}, 'the login template conditionally displays the local agent option' );
my $Update = _ReadRaw( File::Spec->catfile( $Root, 'update.sh' ) );
like( $Update, qr{addons\|addons/[*]\) return 0}, 'the core updater protects installed add-on files' );
like( $Update, qr{var/static/addons\|var/static/addons/[*]\) return 0}, 'the core updater protects published add-on assets' );

done_testing();

sub _ZipCreate {
    my (%Files) = @_;
    my $Blob = '';
    my @Names = sort keys %Files;
    my $First = shift @Names;
    my $Zip = IO::Compress::Zip->new( \$Blob, Name => $First ) or die $ZipError;
    print {$Zip} $Files{$First};
    for my $Name (@Names) {
        $Zip->newStream( Name => $Name ) or die $ZipError;
        print {$Zip} $Files{$Name};
    }
    $Zip->close();
    return $Blob;
}

sub _GenericModuleZIP {
    my (%Param) = @_;
    my $Version = $Param{Version} || '1.0.0';
    my %Files = (
        'README.md' => "# Generic Qisutu add-on test fixture\n",
        'lib/Qisutu/Addon/Example/AuthProvider.pm' => <<'PERL',
package Qisutu::Addon::Example::AuthProvider;
use strict;
use warnings;
sub new { return bless {}, shift }
1;
PERL
        'lib/Qisutu/Addon/Example/SyncTask.pm' => <<'PERL',
package Qisutu::Addon::Example::SyncTask;
use strict;
use warnings;
sub new { return bless {}, shift }
sub Run { return { Success => 1 } }
1;
PERL
        'lib/Qisutu/Addon/Example/Service.pm' => "package Qisutu::Addon::Example::Service; use strict; use warnings; sub new { bless {}, shift } 1;\n",
        'lib/Qisutu/Addon/Example/Event.pm' => "package Qisutu::Addon::Example::Event; use strict; use warnings; sub new { bless {}, shift } sub Handle { return { success => 1 } } 1;\n",
        'lib/Qisutu/Addon/Example/REST.pm' => "package Qisutu::Addon::Example::REST; use strict; use warnings; sub new { bless {}, shift } sub Handle { return { Status => 200, Data => {} } } 1;\n",
        'lib/Qisutu/Addon/Example/UI.pm' => "package Qisutu::Addon::Example::UI; use strict; use warnings; sub new { bless {}, shift } sub Render { return { Template => 'Example.tt', Data => {} } } 1;\n",
        'static/js/example.js' => "window.QisutuExampleModule = true;\n",
        'bin/example-task.pl' => "#!/usr/bin/env perl\nuse strict;\nuse warnings;\nexit 0;\n",
    );
    $Files{'qisutu-module.json'} = JSON::PP->new->canonical(1)->utf8(1)->encode({
        manifest_version => 1,
        id => 'example.lifecycle',
        name => 'Generic lifecycle fixture',
        vendor => 'Qisutu test suite',
        version => $Version,
        description => 'Generated in memory and never shipped as an add-on.',
        license => 'AGPL-3.0-or-later',
        qisutu => { minimum => '0.0.78', maximum => '0.99.99' },
        addon_api => { minimum => '1.0', maximum => '1.99', capabilities => [qw(services.v1 events.v1 rest-routes.v1 ui-slots.v1)] },
        files => [ map {
            { path => $_, permission => $_ =~ m{\Abin/} ? '0755' : '0644' }
        } sort keys %Files ],
        auth_providers => [{
            key => 'example-agent',
            class => 'Qisutu::Addon::Example::AuthProvider',
            label => 'Example',
            account_type => 'agent',
        }],
        tasks => [{
            key => 'example-task',
            class => 'Qisutu::Addon::Example::SyncTask',
            interval_seconds => 3600,
        }],
        services => [{ key => 'example.service', class => 'Qisutu::Addon::Example::Service' }],
        event_subscribers => [{ key => 'example-ticket-events', event => 'ticket.*', class => 'Qisutu::Addon::Example::Event', method => 'Handle', mode => 'async' }],
        rest_routes => [{ key => 'example-status', method => 'GET', path => '/v1/addons/example.lifecycle/status', class => 'Qisutu::Addon::Example::REST', handler_method => 'Handle', scopes => ['example.read'], access_types => ['agent'] }],
        ui_slots => [{ key => 'example-admin-after', slot => 'admin.after', class => 'Qisutu::Addon::Example::UI', method => 'Render', order => 1000, access_types => ['agent'] }],
        settings => [{ key => 'enabled', type => 'boolean', default => 0, label => 'Example' }],
    });
    return _ZipCreate( map { ( 'ExampleLifecycle/' . $_ ) => $Files{$_} } keys %Files );
}

sub _ZIPWithVersion {
    my (%Param) = @_;
    my %Files = %{ $Param{Inspection}->{Files} };
    my $Manifest = JSON::PP->new->utf8(1)->decode( $Files{'qisutu-module.json'} );
    $Manifest->{version} = $Param{Version};
    $Files{'qisutu-module.json'} = JSON::PP->new->canonical(1)->utf8(1)->encode($Manifest);
    return _ZipCreate( map { ( 'ExampleLifecycle/' . $_ ) => $Files{$_} } keys %Files );
}

sub _ReadRaw {
    my ($Path) = @_;
    open my $Handle, '<:raw', $Path or die "Cannot read $Path: $!";
    local $/;
    my $Content = <$Handle>;
    close $Handle;
    return defined $Content ? $Content : '';
}

sub _WriteRaw {
    my ( $Path, $Content ) = @_;
    open my $Handle, '>:raw', $Path or die "Cannot write $Path: $!";
    print {$Handle} $Content;
    close $Handle;
}
