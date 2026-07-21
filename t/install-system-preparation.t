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

use File::Path qw(make_path);
use File::Spec;
use File::Temp qw(tempdir);
use FindBin;
use IPC::Open3;
use Symbol qw(gensym);
use Test::More;

my $InstallPath = "$FindBin::Bin/../install.sh";
my $SyntaxResult = system( 'bash', '-n', $InstallPath );
is( $SyntaxResult, 0, 'install.sh has valid Bash syntax' );

open my $InstallFH, '<', $InstallPath or die "Cannot open $InstallPath: $!";
local $/;
my $Install = <$InstallFH>;
close $InstallFH;

like(
    $Install,
    qr{active_mpm="\$\(a2query -M 2>/dev/null \|\| true\)"},
    'Debian and Ubuntu installation inspects the active Apache MPM',
);
like(
    $Install,
    qr{if \[\[ "\$active_mpm" == \*prefork\* \]\]; then\s+cgi_module="cgi"}s,
    'prefork installations use mod_cgi instead of mod_cgid',
);
like(
    $Install,
    qr{a2enmod alias env headers "\$cgi_module"},
    'all required Apache modules are enabled explicitly',
);
like(
    $Install,
    qr{if ! module_list="\$\(\$apache_control -M 2>&1\)"; then},
    'Apache module inspection keeps the real command failure separate from the module list',
);
unlike(
    $Install,
    qr{module_list="\$\(\$apache_control -M 2>&1 \|\| true\)"},
    'Apache module inspection no longer suppresses configuration errors',
);

like(
    $Install,
    qr{QISUTU_RUNTIME_USER="qisutu"},
    'the installer defines the dedicated Qisutu runtime user',
);
like(
    $Install,
    qr{usermod -a -G "\$APACHE_GROUP" "\$QISUTU_RUNTIME_USER"},
    'the runtime user is added to the web-server group',
);
like(
    $Install,
    qr{chown -R "\$QISUTU_RUNTIME_USER":"\$APACHE_GROUP" "\$ROOT_PATH"},
    'the installed program tree belongs to the runtime user and web-server group',
);
like(
    $Install,
    qr{chown "\$QISUTU_RUNTIME_USER":"\$APACHE_GROUP" /run/lock/qisutu},
    'the shared runtime-lock directory is writable by the Qisutu runtime user',
);

my $DaemonTemplatePath = "$FindBin::Bin/../scriptfiles/qisutu-daemon.service";
open my $DaemonTemplateFH, '<', $DaemonTemplatePath or die "Cannot open $DaemonTemplatePath: $!";
my $DaemonTemplate = do { local $/; <$DaemonTemplateFH> };
close $DaemonTemplateFH;
like(
    $DaemonTemplate,
    qr{^User=__QISUTU_RUNTIME_USER__$}m,
    'the daemon uses the dedicated Qisutu runtime user',
);
like(
    $DaemonTemplate,
    qr{^Group=__QISUTU_APACHE_GROUP__$}m,
    'the daemon retains the web-server group for shared access',
);

my $UpdatePath = "$FindBin::Bin/../update.sh";
open my $UpdateFH, '<', $UpdatePath or die "Cannot open $UpdatePath: $!";
my $Update = do { local $/; <$UpdateFH> };
close $UpdateFH;
like(
    $Update,
    qr{TARGET_OWNER="\$QISUTU_RUNTIME_USER"\s+TARGET_GROUP="\$APACHE_GROUP"},
    'updates restore the runtime user and shared web-server group as installation owners',
);
like(
    $Update,
    qr{chown "\$QISUTU_RUNTIME_USER:\$APACHE_GROUP" "\$RUNTIME_LOCK_DIR"},
    'updates repair the runtime-lock directory ownership',
);
like(
    $Update,
    qr{www-data\|apache\|wwwrun\).*?User=\$QISUTU_RUNTIME_USER}s,
    'updates migrate daemon units generated with the former web-server runtime user',
);
unlike(
    $Update,
    qr{log\|log/\*\)\s+return\s+0},
    'the updater no longer protects the obsolete root log directory',
);
unlike(
    $Update,
    qr{for\s+target_directory\s+in[^\n]*\slog(?:\s|;)},
    'the updater no longer creates the obsolete root log directory',
);
ok(
    !-e "$FindBin::Bin/../log",
    'the obsolete root log directory is absent from the release',
);

my ($InstanceNameValidator) = $Install =~ /(instance_name_is_valid\(\) \{.*?^\})/ms;
my ($InstanceValueBuilder) = $Install =~ /(set_instance_values_from_directory\(\) \{.*?^\})/ms;
ok( $InstanceNameValidator, 'instance-directory validation can be isolated for behavioral tests' );
ok( $InstanceValueBuilder, 'instance-value generation can be isolated for behavioral tests' );

my $InstanceHarness = File::Spec->catfile( tempdir( CLEANUP => 1 ), 'instance-values.sh' );
open my $InstanceHarnessFH, '>', $InstanceHarness or die "Cannot create instance-value harness: $!";
print {$InstanceHarnessFH} <<'INSTANCE_HARNESS_HEAD';
set -euo pipefail
INSTANCE_NAME=""
INSTANCE_ID=""
WEB_PATH=""
APACHE_CONF_NAME=""
DAEMON_SERVICE=""
INSTALL_COMPLETE_SERVICE=""
INSTALL_COMPLETE_PATH=""
SESSION_COOKIE=""
DB_NAME=""
DB_USER=""
INSTANCE_HARNESS_HEAD
print {$InstanceHarnessFH} "$InstanceNameValidator\n$InstanceValueBuilder\n";
print {$InstanceHarnessFH} <<'INSTANCE_HARNESS_TAIL';
set_instance_values_from_directory qisututest
printf '%s\n' \
    "$INSTANCE_NAME" \
    "$INSTANCE_ID" \
    "$WEB_PATH" \
    "$APACHE_CONF_NAME" \
    "$DAEMON_SERVICE" \
    "$INSTALL_COMPLETE_SERVICE" \
    "$INSTALL_COMPLETE_PATH" \
    "$SESSION_COOKIE" \
    "$DB_NAME" \
    "$DB_USER"
INSTANCE_HARNESS_TAIL
close $InstanceHarnessFH;

my $InstanceOutput = qx{/bin/bash "$InstanceHarness"};
is( $? >> 8, 0, 'qisututest instance values are generated successfully' );
is(
    $InstanceOutput,
    join( "\n",
        'qisututest',
        'qisututest',
        '/qisututest',
        'qisututest.conf',
        'qisututest-daemon.service',
        'qisututest-install-complete.service',
        'qisututest-install-complete.path',
        'QISUTUTEST_SESSION',
        'qisututest',
        'qisututest',
        '',
    ),
    'the directory name maps one-to-one to all qisututest instance values',
);
unlike(
    $Install,
    qr{INSTANCE_ID="qisutu-\$INSTANCE_NAME"},
    'the installer no longer prepends qisutu- to an additional instance',
);
unlike(
    $Install,
    qr{DB_NAME="qisutu_\$\{INSTANCE_DB_SUFFIX\}"},
    'the installer no longer prepends qisutu_ to an additional database',
);
like(
    $Install,
    qr{if \[\[ ! -f "\$LOCK_FILE" \]\]; then.*?set_instance_values_from_directory "\$DIRECTORY_NAME".*?write_instance_config}s,
    'an unfinished legacy installation is realigned to its actual directory name',
);
like(
    $Install,
    qr{printf '%s\\n' "\$module_list" >&2},
    'the concrete Apache diagnostic is returned to the administrator',
);
like(
    $Install,
    qr{ohne fehlende Module zu unterstellen},
    'a failed Apache inspection is not reported as a list of missing modules',
);

my ($VerifyFunction) = $Install =~ /(verify_apache_modules\(\) \{.*?^\})/ms;
ok( $VerifyFunction, 'Apache verification function can be isolated for behavioral tests' );

my $FakeBin = tempdir( CLEANUP => 1 );
my $FakeApache = File::Spec->catfile( $FakeBin, 'apache2ctl' );
open my $ApacheFH, '>', $FakeApache or die "Cannot create fake apache2ctl: $!";
print {$ApacheFH} <<'FAKE_APACHE';
#!/usr/bin/env bash
case "${FAKE_APACHE_MODE:-success}" in
    success)
        printf 'Loaded Modules:\n alias_module (shared)\n env_module (shared)\n headers_module (shared)\n cgid_module (shared)\n'
        exit 0
        ;;
    configuration_error)
        printf 'AH00526: Syntax error in a configured virtual host\n' >&2
        exit 1
        ;;
    missing_header)
        printf 'Loaded Modules:\n alias_module (shared)\n env_module (shared)\n cgid_module (shared)\n'
        exit 0
        ;;
esac
FAKE_APACHE
close $ApacheFH;
chmod 0755, $FakeApache or die "Cannot chmod fake apache2ctl: $!";

my $Harness = File::Spec->catfile( $FakeBin, 'verify-apache.sh' );
open my $HarnessFH, '>', $Harness or die "Cannot create Apache verification harness: $!";
print {$HarnessFH} "set -euo pipefail\n$VerifyFunction\nverify_apache_modules\n";
close $HarnessFH;

sub RunApacheVerification {
    my ($Mode) = @_;
    local $ENV{FAKE_APACHE_MODE} = $Mode;
    local $ENV{PATH} = "$FakeBin:$ENV{PATH}";

    my $ErrorFH = gensym;
    my $PID = open3( undef, my $OutputFH, $ErrorFH, '/bin/bash', $Harness );
    my $Output = do { local $/; <$OutputFH> // '' };
    my $Error  = do { local $/; <$ErrorFH>  // '' };
    waitpid $PID, 0;

    return ( $? >> 8, $Output . $Error );
}

my ( $SuccessStatus, $SuccessOutput ) = RunApacheVerification('success');
is( $SuccessStatus, 0, 'a complete Apache module list passes verification' );
is( $SuccessOutput, '', 'successful Apache verification stays quiet' );

my ( $ConfigStatus, $ConfigOutput ) = RunApacheVerification('configuration_error');
isnt( $ConfigStatus, 0, 'an Apache configuration error stops the preparation' );
like( $ConfigOutput, qr{AH00526: Syntax error in a configured virtual host}, 'the original Apache configuration error is preserved' );
unlike( $ConfigOutput, qr{Fehlendes Apache-Modul}, 'a configuration error is not mislabeled as missing modules' );

my ( $MissingStatus, $MissingOutput ) = RunApacheVerification('missing_header');
isnt( $MissingStatus, 0, 'a genuinely incomplete module list stops the preparation' );
like( $MissingOutput, qr{Fehlendes Apache-Modul: headers_module}, 'a genuinely missing module is named precisely' );
unlike( $MissingOutput, qr{Fehlendes Apache-Modul: (?:alias|env)_module}, 'loaded modules are not reported as missing' );

my $ApacheTemplatePath = "$FindBin::Bin/../scriptfiles/qisutu-apache.conf";
open my $ApacheTemplateFH, '<', $ApacheTemplatePath or die "Cannot open $ApacheTemplatePath: $!";
my $ApacheTemplate = do { local $/; <$ApacheTemplateFH> };
close $ApacheTemplateFH;

like(
    $ApacheTemplate,
    qr{<Directory "__QISUTU_ROOT__/bin/cgi-bin/">.*?\n\s*CGIPassAuth On\s*\n.*?</Directory>}s,
    'CGIPassAuth is placed inside the CGI directory context accepted by Apache',
);
unlike(
    $ApacheTemplate,
    qr{^CGIPassAuth\s+On\s*$}m,
    'CGIPassAuth is not emitted in the global virtual-host context',
);
is(
    scalar( () = $ApacheTemplate =~ /CGIPassAuth\s+On/g ),
    1,
    'the Apache template contains exactly one CGIPassAuth directive',
);

my $WebInstallerPath = "$FindBin::Bin/../bin/cgi-bin/install.pl";
my $WebInstallerSyntax = system( $^X, '-c', $WebInstallerPath );
is( $WebInstallerSyntax, 0, 'the web installer has valid Perl syntax' );

open my $WebInstallerFH, '<:encoding(UTF-8)', $WebInstallerPath or die "Cannot open $WebInstallerPath: $!";
my $WebInstaller = do { local $/; <$WebInstallerFH> };
close $WebInstallerFH;

my $RootPathPosition = index( $WebInstaller, 'my $RootPath =' );
my $LibraryPathPosition = index( $WebInstaller, 'unshift @INC' );
my $RequestPosition = index( $WebInstaller, 'my $Request = _RequestParams()' );
ok(
    $RootPathPosition >= 0
        && $LibraryPathPosition > $RootPathPosition
        && $RequestPosition > $LibraryPathPosition,
    'the web installer configures its application module paths before handling a request',
);

my $InstallerBootstrap = substr( $WebInstaller, $RootPathPosition, $RequestPosition - $RootPathPosition );
for my $RequiredLibrary (qw(config system cpan-lib)) {
    like(
        $InstallerBootstrap,
        qr{File::Spec->catdir\( \$RootPath, 'core', '\Q$RequiredLibrary\E' \)},
        "the web installer includes core/$RequiredLibrary in its module path",
    );
}
is(
    scalar( () = $WebInstaller =~ /unshift \@INC/g ),
    1,
    'the web installer configures the module path once at startup instead of too late in the mail test',
);

my $ProjectRoot = "$FindBin::Bin/..";
my $SecurityLoadStatus = system(
    $^X,
    '-I' . "$ProjectRoot/core/config",
    '-I' . "$ProjectRoot/core/system",
    '-I' . "$ProjectRoot/core/cpan-lib",
    '-MQisutuConfig',
    '-MQisutuSecurity',
    '-e',
    'my $config = QisutuConfig::Load(); my $security = QisutuSecurity->new(Config => $config); exit(ref($security) eq q{QisutuSecurity} ? 0 : 1);',
);
is( $SecurityLoadStatus, 0, 'the web installer module paths load QisutuConfig and QisutuSecurity together' );

my $InstallerSecurityRoot = tempdir( CLEANUP => 1 );
make_path( File::Spec->catdir( $InstallerSecurityRoot, 'var', 'secure' ) );
my $InstallerSecurityKey = File::Spec->catfile( $InstallerSecurityRoot, 'var', 'secure', 'security.key' );
open my $InstallerSecurityKeyFH, '>', $InstallerSecurityKey or die "Cannot create installer security key: $!";
print {$InstallerSecurityKeyFH} ( '42' x 32 ) . "\n";
close $InstallerSecurityKeyFH;

{
    local $ENV{QISUTU_HOME} = $InstallerSecurityRoot;
    my $EncryptionStatus = system(
        $^X,
        '-I' . "$ProjectRoot/core/config",
        '-I' . "$ProjectRoot/core/system",
        '-I' . "$ProjectRoot/core/cpan-lib",
        '-MQisutuConfig',
        '-MQisutuSecurity',
        '-e',
        'my $config = QisutuConfig::Load(); my $security = QisutuSecurity->new(Config => $config); my $encrypted = $security->Encrypt(Value => q{installer-mail-password}); exit(defined($encrypted) && $encrypted =~ m{^qse1:} ? 0 : 1);',
    );
    is( $EncryptionStatus, 0, 'the web installer module paths and generated key location encrypt a mail password' );
}

like(
    $WebInstaller,
    qr{_Log\("Sicherheitssystem für Zugangsdaten konnte nicht geladen werden: \$SecurityLoadError"\)},
    'a future security-module load failure is written to the installation log with its real cause',
);

my ($ConfigTemplateSource) = $WebInstaller =~ /(sub _ConfigText \{.*?^\})/ms;
ok( $ConfigTemplateSource, 'the generated Qisutu configuration can be inspected' );
like(
    $ConfigTemplateSource,
    qr{SecurityKey\s+=>\s+"\\\$RootPath/var/secure/security[.]key"},
    'the freshly generated configuration retains the installation security-key path',
);
like(
    $ConfigTemplateSource,
    qr{Version\s+=>\s+'\$ConfiguredProgramVersion'},
    'the freshly generated configuration uses the version from release.conf',
);
unlike(
    $ConfigTemplateSource,
    qr{Version\s+=>\s+'0[.]0[.]35'},
    'the web installer no longer writes the obsolete hard-coded program version',
);

done_testing();
