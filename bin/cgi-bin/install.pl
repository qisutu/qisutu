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

use Cwd qw(abs_path);
use Digest::SHA qw(sha256_hex);
use Encode qw(decode encode);
use File::Basename qw(dirname);
use File::Spec;
use Fcntl qw(:flock);
use FindBin;
use IPC::Open3;
use JSON::PP;
use POSIX qw(strftime);
use Symbol qw(gensym);

my $RootPath = $ENV{QISUTU_HOME} || abs_path( File::Spec->catdir( $FindBin::Bin, '..', '..' ) );
$ENV{QISUTU_HOME} ||= $RootPath;

unshift @INC,
    File::Spec->catdir( $RootPath, 'core', 'config' ),
    File::Spec->catdir( $RootPath, 'core', 'system' ),
    File::Spec->catdir( $RootPath, 'core', 'cpan-lib' );

my $InstallPath = File::Spec->catdir( $RootPath, 'var', 'install' );
my $LockFile = File::Spec->catfile( $InstallPath, 'installed.lock' );
my $SchemaFile = File::Spec->catfile( $RootPath, 'install', 'sql', 'schema.sql' );
my $InsertFile = File::Spec->catfile( $RootPath, 'install', 'sql', 'insert.sql' );
my $ConfigFile = File::Spec->catfile( $RootPath, 'core', 'config', 'QisutuConfig.pm' );
my $ReleaseFile = File::Spec->catfile( $RootPath, 'release.conf' );
my $LicenseFile = File::Spec->catfile( $RootPath, 'LICENSE' );
my $ThirdPartyFile = File::Spec->catfile( $RootPath, 'THIRD_PARTY_NOTICES.md' );
my $LogFile = File::Spec->catfile( $RootPath, 'var', 'log', 'install.log' );
my $BootstrapFile = File::Spec->catfile( $InstallPath, 'database-bootstrap.conf' );
my $InstanceFile = File::Spec->catfile( $InstallPath, 'instance.conf' );
my $InstallerOperationLockFile = File::Spec->catfile( $InstallPath, 'installer-operation.lock' );
my $InstallerLanguagePath = File::Spec->catdir( $RootPath, 'core', 'language', 'installer' );
my $ProgramVersion = '0.0.1';

if ( open my $ReleaseHandle, '<:encoding(UTF-8)', $ReleaseFile ) {
    while ( my $Line = <$ReleaseHandle> ) {
        if ( $Line =~ m{\Aversion=([0-9]+(?:[.][0-9]+){2})\s*\z} ) {
            $ProgramVersion = $1;
            last;
        }
    }
    close $ReleaseHandle;
}

my %InstanceConfig = (
    instance_id    => 'qisutu',
    web_path       => '/qisutu',
    session_cookie => 'QISUTU_SESSION',
    db_name        => 'qisutu',
    db_user        => 'qisutu',
    install_language => 'de',
);

if ( -r $InstanceFile ) {
    open my $InstanceHandle, '<:encoding(UTF-8)', $InstanceFile;
    if ($InstanceHandle) {
        while ( my $Line = <$InstanceHandle> ) {
            $Line =~ s{[\r\n]+\z}{};
            next if $Line !~ m{\A([a-z_]+)=(.*)\z};
            $InstanceConfig{$1} = $2;
        }
        close $InstanceHandle;
    }
}

$InstanceConfig{instance_id} = 'qisutu'
    if $InstanceConfig{instance_id} !~ m{\A[a-z][a-z0-9-]{0,47}\z};
$InstanceConfig{web_path} = '/qisutu'
    if $InstanceConfig{web_path} !~ m{\A/[A-Za-z0-9][A-Za-z0-9_/-]*\z}
    || $InstanceConfig{web_path} =~ m{//|\.\.|/\z};
$InstanceConfig{session_cookie} = 'QISUTU_SESSION'
    if $InstanceConfig{session_cookie} !~ m{\A[A-Z][A-Z0-9_]{2,63}\z};
$InstanceConfig{db_name} = 'qisutu'
    if $InstanceConfig{db_name} !~ m{\A[A-Za-z][A-Za-z0-9_]{0,63}\z};
$InstanceConfig{db_user} = 'qisutu'
    if $InstanceConfig{db_user} !~ m{\A[A-Za-z][A-Za-z0-9_]{0,23}\z};
$InstanceConfig{install_language} = _LanguageCanonical( $InstanceConfig{install_language} );
$InstanceConfig{install_language} = 'de'
    if !_InstallerLanguageAvailable( $InstanceConfig{install_language} );

my $InstanceID       = $InstanceConfig{instance_id};
my $WebPath          = $InstanceConfig{web_path};
my $SessionCookieName = $InstanceConfig{session_cookie};
my $InstallCookieName = $SessionCookieName . '_INSTALL';
my $DefaultDBName    = $InstanceConfig{db_name};
my $DefaultDBUser    = $InstanceConfig{db_user};
my $InstallLanguage  = $InstanceConfig{install_language};
my $UILanguage       = $InstallLanguage;
my $InstallerText    = {};
my $InstallerEnglish = {};

binmode STDOUT, ':raw';

my $Request = _RequestParams();
my ( $Token, $State, $NewSession ) = _SessionLoadOrCreate();
if ( !$State->{welcome_done}
    && (
        ( $State->{ui_language} || '' ) ne $InstallLanguage
        || ( $State->{default_language} || '' ) ne $InstallLanguage
    )
) {
    $State->{ui_language}      = $InstallLanguage;
    $State->{default_language} = $InstallLanguage;
    _StateSave( $Token, $State );
}
$UILanguage = _LanguageCanonical(
    $State->{ui_language}
        || $State->{default_language}
        || $InstallLanguage
);
$UILanguage = $InstallLanguage if !_InstallerLanguageAvailable($UILanguage);
_InstallerLanguageLoad($UILanguage);
my $Step = $Request->{Step} || 1;
$Step = 1 if $Step !~ m{\A[1-6]\z};

if ( -f $LockFile && !( $Step == 6 && $State->{show_final} ) ) {
    _PrintResponse(
        Body => _Page(
            Step    => 6,
            Title   => _I('AlreadyInstalledTitle'),
            Content => _InstalledHTML(),
        ),
        Cookie => $NewSession ? _SessionCookie($Token) : '',
    );
    exit;
}

if ( $Step > 1 && !$State->{welcome_done} ) {
    $Step = 1;
}
elsif ( $Step > 2 && !$State->{license_done} ) {
    $Step = 2;
}
elsif ( $Step > 3 && !$State->{database_done} ) {
    $Step = 3;
}
elsif ( $Step > 4 && !$State->{system_done} ) {
    $Step = 4;
}
elsif ( $Step > 5 && !$State->{show_final} ) {
    $Step = 5;
}

my $Action = $Request->{Action} || '';
my $Error  = '';

if ( ( $ENV{REQUEST_METHOD} || '' ) eq 'POST' ) {
    if ( !$Request->{CSRFToken} || $Request->{CSRFToken} ne ( $State->{csrf_token} || '' ) ) {
        $Error = _I('SessionInvalid');
    }
    elsif ( $Action eq 'Begin' ) {
        my $Checks = _SystemChecks();
        if ( grep { $_->{critical} && !$_->{ok} } @{$Checks} ) {
            $Error = _I('RequiredCheckFailed');
            $Step  = 1;
        }
        else {
            $State->{welcome_done} = 1;
            _StateSave( $Token, $State );
            _Redirect( Location => 'install.pl?Step=2', Cookie => $NewSession ? _SessionCookie($Token) : '' );
        }
    }
    elsif ( $Action eq 'AcceptLicense' ) {
        if ( !$Request->{LicenseAccepted} ) {
            $Error = _I('LicenseConfirmRequired');
            $Step  = 2;
        }
        else {
            $State->{license_done} = 1;
            _StateSave( $Token, $State );
            _Redirect( Location => 'install.pl?Step=3', Cookie => $NewSession ? _SessionCookie($Token) : '' );
        }
    }
    elsif ( $Action eq 'InstallDatabase' ) {
        my $Result = _DatabaseInstall( Request => $Request, State => $State );
        if ( !$Result->{success} ) {
            $Error = $Result->{error} || _I('DatabaseInstallFailed');
            $Step  = 3;
        }
        else {
            $State = $Result->{state};
            _StateSave( $Token, $State );
            $Step = 3;
        }
    }
    elsif ( $Action eq 'ContinueAfterDatabase' ) {
        if ( !$State->{database_done} ) {
            $Error = _I('DatabaseNotReady');
            $Step  = 3;
        }
        else {
            _Redirect( Location => 'install.pl?Step=4', Cookie => $NewSession ? _SessionCookie($Token) : '' );
        }
    }
    elsif ( $Action eq 'SaveSystem' ) {
        my $Result = _SystemSettingsSave( Request => $Request, State => $State );
        if ( !$Result->{success} ) {
            $Error = $Result->{error} || _I('SystemSaveFailed');
            $Step  = 4;
        }
        else {
            $State = $Result->{state};
            _StateSave( $Token, $State );
            _Redirect( Location => 'install.pl?Step=5', Cookie => $NewSession ? _SessionCookie($Token) : '' );
        }
    }
    elsif ( $Action eq 'SkipMail' ) {
        if ( !$State->{system_done} ) {
            $Error = _I('SystemNotSaved');
            $Step  = 4;
        }
        else {
            $State->{mail_done}  = 1;
            $State->{mail_skip}  = 1;
            my $Result = _InstallationFinalize(
                Token => $Token,
                State => $State,
            );
            if ( !$Result->{success} ) {
                $Error = $Result->{error} || _I('InstallationFinalizeFailed');
                $Step  = 5;
            }
            else {
                $State = $Result->{state};
                _Redirect( Location => 'install.pl?Step=6', Cookie => $NewSession ? _SessionCookie($Token) : '' );
            }
        }
    }
    elsif ( $Action eq 'SaveMail' ) {
        my $Result = _MailSettingsSave( Request => $Request, State => $State );
        if ( !$Result->{success} ) {
            $Error = $Result->{error} || _I('MailSaveFailed');
            $Step  = 5;
        }
        else {
            $State = $Result->{state};
            my $Finalize = _InstallationFinalize(
                Token => $Token,
                State => $State,
            );
            if ( !$Finalize->{success} ) {
                $Error = $Finalize->{error} || _I('InstallationFinalizeFailed');
                $Step  = 5;
            }
            else {
                $State = $Finalize->{state};
                _Redirect( Location => 'install.pl?Step=6', Cookie => $NewSession ? _SessionCookie($Token) : '' );
            }
        }
    }
    elsif ( $Action eq 'Finish' ) {
        my $LoginURL = $State->{login_url} || "$WebPath/index.pl";
        _StateDelete($Token);
        _Redirect( Location => $LoginURL, Cookie => _SessionCookieDelete() );
    }
}

my $Content;
my $Title;

if ( $Step == 1 ) {
    $Title   = _I('TitleWelcome');
    $Content = _WelcomeHTML( Error => $Error, State => $State );
}
elsif ( $Step == 2 ) {
    $Title   = _I('TitleLicense');
    $Content = _LicenseHTML( Error => $Error, State => $State );
}
elsif ( $Step == 3 ) {
    $Title   = _I('TitleDatabase');
    $Content = _DatabaseHTML( Error => $Error, State => $State, Request => $Request );
}
elsif ( $Step == 4 ) {
    $Title   = _I('TitleSystem');
    $Content = _SystemHTML( Error => $Error, State => $State, Request => $Request );
}
elsif ( $Step == 5 ) {
    $Title   = _I('TitleMail');
    $Content = _MailHTML( Error => $Error, State => $State, Request => $Request );
}
else {
    $Title   = _I('TitleComplete');
    $Content = _FinalHTML( Error => $Error, State => $State );
}

_PrintResponse(
    Body   => _Page( Step => $Step, Title => $Title, Content => $Content ),
    Cookie => $NewSession ? _SessionCookie($Token) : '',
);

sub _WelcomeHTML {
    my (%Param) = @_;
    my $Checks = _SystemChecks();
    my $Rows = '';
    my $HasError = 0;

    for my $Check ( @{$Checks} ) {
        my $Class = $Check->{ok} ? 'ok' : ( $Check->{critical} ? 'error' : 'warning' );
        my $Label = $Check->{ok} ? 'OK' : ( $Check->{critical} ? _I('StatusError') : _I('StatusNotice') );
        $HasError = 1 if $Check->{critical} && !$Check->{ok};
        $Rows .= '<tr><td>' . _Escape( $Check->{name} ) . '</td><td>' . _Escape( $Check->{detail} )
            . '</td><td><span class="qisutu-install-status ' . $Class . '">' . $Label . '</span></td></tr>';
    }

    return _ErrorHTML( $Param{Error} ) . qq{
        <div class="qisutu-install-welcome">
            <div>
                <h2>} . _Escape( _I('WelcomeHeading') ) . qq{</h2>
                <p>} . _Escape( _I('WelcomeIntro') ) . qq{</p>
                <p>} . _Escape( _I('WelcomeSteps') ) . qq{</p>
            </div>
            <div class="qisutu-install-company">
                <strong>Franziska Steps</strong><br>
                Qisutu - Kim-KI<br>
                82 Chemin des Launes<br>
                06510 Carros<br>
                France<br><br>
                +33 6 98 21 25 38<br>
                <a href="mailto:support\@qisutu.de">support\@qisutu.de</a>
            </div>
        </div>
        <h3>} . _Escape( _I('Instance') ) . qq{</h3>
        <div class="qisutu-install-credentials">
            <div><span>} . _Escape( _I('InstanceID') ) . qq{</span><strong>} . _Escape($InstanceID) . qq{</strong></div>
            <div><span>} . _Escape( _I('WebPath') ) . qq{</span><strong>} . _Escape($WebPath) . qq{</strong></div>
            <div><span>} . _Escape( _I('DatabaseName') ) . qq{</span><strong>} . _Escape($DefaultDBName) . qq{</strong></div>
            <div><span>} . _Escape( _I('DatabaseUser') ) . qq{</span><strong>} . _Escape($DefaultDBUser) . qq{</strong></div>
        </div>
        <h3>} . _Escape( _I('SystemCheck') ) . qq{</h3>
        <div class="qisutu-install-table-wrap"><table><thead><tr><th>} . _Escape( _I('Check') ) . qq{</th><th>} . _Escape( _I('Result') ) . qq{</th><th>} . _Escape( _I('Status') ) . qq{</th></tr></thead><tbody>$Rows</tbody></table></div>
        <form method="post" action="install.pl">
            <input type="hidden" name="Step" value="1">
            <input type="hidden" name="Action" value="Begin">
            <input type="hidden" name="CSRFToken" value="} . _Escape( $Param{State}->{csrf_token} ) . qq{">
            <div class="qisutu-install-actions"><button class="primary" type="submit"} . ( $HasError ? ' disabled' : '' ) . qq{>} . _Escape( _I('StartInstallation') ) . qq{</button></div>
        </form>
    };
}

sub _LicenseHTML {
    my (%Param) = @_;
    my $License = _FileRead($LicenseFile);
    my $Third   = _FileRead($ThirdPartyFile);

    return _ErrorHTML( $Param{Error} ) . qq{
        <p>} . _Escape( _I('LicenseIntro') ) . qq{</p>
        <div class="qisutu-install-license"><h3>AGPL-3.0-or-later</h3><pre>} . _Escape($License) . qq{</pre></div>
        <div class="qisutu-install-license"><h3>} . _Escape( _I('ThirdPartyNotices') ) . qq{</h3><pre>} . _Escape($Third) . qq{</pre></div>
        <form method="post" action="install.pl">
            <input type="hidden" name="Step" value="2">
            <input type="hidden" name="Action" value="AcceptLicense">
            <input type="hidden" name="CSRFToken" value="} . _Escape( $Param{State}->{csrf_token} ) . qq{">
            <label class="qisutu-install-check"><input type="checkbox" name="LicenseAccepted" value="1" required> } . _Escape( _I('LicenseAccepted') ) . qq{</label>
            <div class="qisutu-install-actions"><button class="primary" type="submit">} . _Escape( _I('Continue') ) . qq{</button></div>
        </form>
    };
}

sub _DatabaseHTML {
    my (%Param) = @_;
    my $State = $Param{State};

    if ( $State->{database_done} ) {
        return _ErrorHTML( $Param{Error} ) . qq{
            <div class="qisutu-install-success"><strong>} . _Escape( _I('DatabaseSuccess') ) . qq{</strong></div>
            } . ( $State->{database_warning} ? '<div class="qisutu-install-error"><strong>' . _Escape( _I('SecurityNotice') ) . '</strong> ' . _Escape( $State->{database_warning} ) . '</div>' : '' ) . qq{
            <p>} . _Escape( _I('DatabaseCredentialsNote') ) . qq{</p>
            <div class="qisutu-install-credentials">
                <div><span>} . _Escape( _I('DatabaseServer') ) . qq{</span><strong>} . _Escape( $State->{db_host} ) . qq{</strong></div>
                <div><span>} . _Escape( _I('DatabaseName') ) . qq{</span><strong>} . _Escape( $State->{db_name} ) . qq{</strong></div>
                <div><span>} . _Escape( _I('DatabaseUser') ) . qq{</span><strong>} . _Escape( $State->{db_user} ) . qq{</strong></div>
                <div><span>} . _Escape( _I('DatabasePassword') ) . qq{</span><div class="qisutu-install-credential-value"><strong id="qisutu-install-database-password-step3" class="credential">} . _Escape( $State->{db_password} ) . qq{</strong><button class="qisutu-install-copy" type="button" data-copy-target="qisutu-install-database-password-step3" data-copy-label="} . _Escape( _I('Copy') ) . qq{" data-copied-label="} . _Escape( _I('Copied') ) . qq{">} . _Escape( _I('Copy') ) . qq{</button></div></div>
            </div>
            <form method="post" action="install.pl">
                <input type="hidden" name="Step" value="3">
                <input type="hidden" name="Action" value="ContinueAfterDatabase">
                <input type="hidden" name="CSRFToken" value="} . _Escape( $State->{csrf_token} ) . qq{">
                <div class="qisutu-install-actions"><button class="primary" type="submit">} . _Escape( _I('ContinueSystem') ) . qq{</button></div>
            </form>
        };
    }

    my $Request = $Param{Request} || {};
    my $Host = $Request->{DBHost} || 'localhost';
    my $Port = $Request->{DBPort} || '3306';
    my $Name = $DefaultDBName;
    my $User = $DefaultDBUser;
    my $AdminUser = $Request->{DBAdminUser} || 'root';

    return _ErrorHTML( $Param{Error} ) . qq{
        <p>} . _Escape( _I('DatabaseAdminIntro') ) . qq{</p>
        <form method="post" action="install.pl" autocomplete="off">
            <input type="hidden" name="Step" value="3">
            <input type="hidden" name="Action" value="InstallDatabase">
            <input type="hidden" name="CSRFToken" value="} . _Escape( $State->{csrf_token} ) . qq{">
            <div class="qisutu-install-grid">
                } . _Field( _I('DatabaseServer'), 'DBHost', $Host, 'text', 1 ) .
                _Field( _I('Port'), 'DBPort', $Port, 'number', 1 ) .
                _Field( _I('DatabaseName'), 'DBName', $Name, 'text', 1, 'readonly' ) .
                _Field( _I('DatabaseUserQisutu'), 'DBUser', $User, 'text', 1, 'readonly' ) .
                _Field( _I('DatabaseAdmin'), 'DBAdminUser', $AdminUser, 'text', 1 ) .
                _Field( _I('DatabaseAdminPassword'), 'DBAdminPassword', '', 'password', 0 ) . qq{
            </div>
            } . ( -r $BootstrapFile ? '<label class="qisutu-install-check"><input type="checkbox" name="UseBootstrap" value="1" checked> ' . _Escape( _I('UseBootstrap') ) . '</label>' : '' ) . qq{
            <div class="qisutu-install-note">} . _Escape( _I('EmptyDatabaseNote') ) . qq{</div>
            <div class="qisutu-install-actions"><button class="primary" type="submit">} . _Escape( _I('CreateDatabase') ) . qq{</button></div>
        </form>
    };
}

sub _SystemHTML {
    my (%Param) = @_;
    my $State = $Param{State};
    my $Request = $Param{Request} || {};
    my $HTTP = $Request->{HTTPType} || $State->{http_type} || ( ( $ENV{HTTPS} || '' ) eq 'on' ? 'https' : 'http' );
    my $FQDN = $Request->{FQDN} || $State->{fqdn} || $ENV{HTTP_HOST} || '';
    $FQDN =~ s{:\d+\z}{} if $FQDN !~ m{\A\[};
    my $Email = $Request->{AdminEmail} || $State->{admin_email} || '';
    my $Language = $Request->{DefaultLanguage} || $State->{default_language} || 'de';
    my $Timezone = $Request->{Timezone} || $State->{timezone} || 'Europe/Paris';
    my $TicketHook = $Request->{TicketHook} || $State->{ticket_hook} || 'Qisutu';
    my $Attachment = $Request->{AttachmentMaxSize} || $State->{attachment_max_size} || '25';

    return _ErrorHTML( $Param{Error} ) . qq{
        <form method="post" action="install.pl">
            <input type="hidden" name="Step" value="4">
            <input type="hidden" name="Action" value="SaveSystem">
            <input type="hidden" name="CSRFToken" value="} . _Escape( $State->{csrf_token} ) . qq{">
            <div class="qisutu-install-grid">
                <div class="qisutu-install-field"><label for="HTTPType">} . _Escape( _I('Protocol') ) . qq{</label><select id="HTTPType" name="HTTPType"><option value="http"} . ( $HTTP eq 'http' ? ' selected' : '' ) . qq{>HTTP</option><option value="https"} . ( $HTTP eq 'https' ? ' selected' : '' ) . qq{>HTTPS</option></select></div>
                } . _Field( _I('FQDN'), 'FQDN', $FQDN, 'text', 1 ) .
                _Field( _I('WebPath'), 'WebPath', $WebPath, 'text', 1, 'readonly' ) .
                _Field( _I('AdminEmail'), 'AdminEmail', $Email, 'email', 1 ) . qq{
                <div class="qisutu-install-field"><label for="DefaultLanguage">} . _Escape( _I('DefaultLanguage') ) . qq{</label><select id="DefaultLanguage" name="DefaultLanguage">} . _LanguageOptions($Language) . qq{</select></div>
                } . _Field( _I('Timezone'), 'Timezone', $Timezone, 'text', 1 ) .
                _Field( _I('TicketHook'), 'TicketHook', $TicketHook, 'text', 1 ) .
                _Field( _I('AttachmentMax'), 'AttachmentMaxSize', $Attachment, 'number', 1 ) . qq{
            </div>
            <div class="qisutu-install-actions"><button class="primary" type="submit">} . _Escape( _I('SaveSystem') ) . qq{</button></div>
        </form>
    };
}

sub _MailHTML {
    my (%Param) = @_;
    my $State = $Param{State};
    my $Request = $Param{Request} || {};

    return _ErrorHTML( $Param{Error} ) . qq{
        <p>} . _Escape( _I('MailOptionalIntro') ) . qq{</p>
        <form method="post" action="install.pl" autocomplete="off">
            <input type="hidden" name="Step" value="5">
            <input type="hidden" name="Action" value="SaveMail">
            <input type="hidden" name="CSRFToken" value="} . _Escape( $State->{csrf_token} ) . qq{">
            <section class="qisutu-install-mail-section">
                <label class="qisutu-install-check"><input type="checkbox" name="IMAPEnabled" value="1"} . ( $Request->{IMAPEnabled} ? ' checked' : '' ) . qq{> } . _Escape( _I('SetupIMAP') ) . qq{</label>
                <div class="qisutu-install-grid">
                    } . _SelectField( _I('ConnectionType'), 'InboundConnectionType', 'imap', [ [ imap => 'IMAP' ] ] ) .
                    _Field( _I('Name'), 'IMAPName', $Request->{IMAPName} || _I('DefaultIMAP'), 'text', 0 ) .
                    _Field( _I('EmailAddress'), 'IMAPEmail', $Request->{IMAPEmail} || '', 'email', 0 ) .
                    _Field( _I('IMAPServer'), 'IMAPHost', $Request->{IMAPHost} || '', 'text', 0 ) .
                    _Field( _I('Port'), 'IMAPPort', $Request->{IMAPPort} || '993', 'number', 0 ) .
                    _SelectField( _I('Encryption'), 'IMAPSecurity', $Request->{IMAPSecurity} || 'imaps', [ [ imap => _I('NoneIMAP') ], [ imap_starttls => 'STARTTLS' ], [ imaps => 'SSL/TLS' ] ] ) .
                    _Field( _I('Username'), 'IMAPUsername', $Request->{IMAPUsername} || '', 'text', 0 ) .
                    _Field( _I('Password'), 'IMAPPassword', '', 'password', 0 ) .
                    _Field( _I('TargetQueue'), 'IMAPQueue', _I('InboxQueue'), 'text', 0, 'readonly' ) . qq{
                </div>
            </section>
            <section class="qisutu-install-mail-section">
                <label class="qisutu-install-check"><input type="checkbox" name="SMTPEnabled" value="1"} . ( $Request->{SMTPEnabled} ? ' checked' : '' ) . qq{> } . _Escape( _I('SetupSMTP') ) . qq{</label>
                <div class="qisutu-install-grid">
                    } . _SelectField( _I('ConnectionType'), 'OutboundConnectionType', 'smtp', [ [ smtp => 'SMTP' ] ] ) .
                    _Field( _I('Name'), 'SMTPName', $Request->{SMTPName} || _I('DefaultSMTP'), 'text', 0 ) .
                    _Field( _I('SenderAddress'), 'SMTPEmail', $Request->{SMTPEmail} || '', 'email', 0 ) .
                    _Field( _I('SMTPServer'), 'SMTPHost', $Request->{SMTPHost} || '', 'text', 0 ) .
                    _Field( _I('Port'), 'SMTPPort', $Request->{SMTPPort} || '587', 'number', 0 ) .
                    _SelectField( _I('Encryption'), 'SMTPSecurity', $Request->{SMTPSecurity} || 'smtp_starttls', [ [ smtp => _I('NoneSMTP') ], [ smtp_starttls => 'STARTTLS' ], [ smtps => 'SSL/TLS' ] ] ) .
                    _Field( _I('Username'), 'SMTPUsername', $Request->{SMTPUsername} || '', 'text', 0 ) .
                    _Field( _I('Password'), 'SMTPPassword', '', 'password', 0 ) . qq{
                </div>
            </section>
            <div class="qisutu-install-actions"><button class="secondary" type="submit" name="Action" value="SkipMail" formnovalidate>} . _Escape( _I('SkipMail') ) . qq{</button><button class="primary" type="submit">} . _Escape( _I('TestSaveConnections') ) . qq{</button></div>
        </form>
    };
}

sub _FinalHTML {
    my (%Param) = @_;
    my $State = $Param{State};
    my $LoginURL = $State->{login_url} || "$WebPath/index.pl";

    return _ErrorHTML( $Param{Error} ) . qq{
        <div class="qisutu-install-success"><strong>} . _Escape( _I('InstallSuccess') ) . qq{</strong></div>
        <p>} . _Escape( _I('FinalCredentialsNote') ) . qq{</p>
        <div class="qisutu-install-credentials">
            <div><span>} . _Escape( _I('LoginAddress') ) . qq{</span><strong><a href="} . _Escape($LoginURL) . qq{">} . _Escape($LoginURL) . qq{</a></strong></div>
            <div><span>} . _Escape( _I('Username') ) . qq{</span><strong>admin</strong></div>
            <div><span>} . _Escape( _I('AdminPassword') ) . qq{</span><div class="qisutu-install-credential-value"><strong id="qisutu-install-admin-password" class="credential">} . _Escape( $State->{admin_password} || '' ) . qq{</strong><button class="qisutu-install-copy" type="button" data-copy-target="qisutu-install-admin-password" data-copy-label="} . _Escape( _I('Copy') ) . qq{" data-copied-label="} . _Escape( _I('Copied') ) . qq{">} . _Escape( _I('Copy') ) . qq{</button></div></div>
            <div><span>} . _Escape( _I('DatabaseName') ) . qq{</span><strong>} . _Escape( $State->{db_name} || '' ) . qq{</strong></div>
            <div><span>} . _Escape( _I('DatabaseUser') ) . qq{</span><strong>} . _Escape( $State->{db_user} || '' ) . qq{</strong></div>
            <div><span>} . _Escape( _I('DatabasePassword') ) . qq{</span><div class="qisutu-install-credential-value"><strong id="qisutu-install-database-password-final" class="credential">} . _Escape( $State->{db_password} || '' ) . qq{</strong><button class="qisutu-install-copy" type="button" data-copy-target="qisutu-install-database-password-final" data-copy-label="} . _Escape( _I('Copy') ) . qq{" data-copied-label="} . _Escape( _I('Copied') ) . qq{">} . _Escape( _I('Copy') ) . qq{</button></div></div>
        </div>
        <form method="post" action="install.pl">
            <input type="hidden" name="Step" value="6">
            <input type="hidden" name="Action" value="Finish">
            <input type="hidden" name="CSRFToken" value="} . _Escape( $State->{csrf_token} ) . qq{">
            <div class="qisutu-install-actions"><button class="primary" type="submit">} . _Escape( _I('CredentialsNoted') ) . qq{</button></div>
        </form>
    };
}

sub _InstalledHTML {
    my $BaseURL = _ConfigBaseURLRead() || "$WebPath/index.pl";
    $BaseURL .= '/index.pl' if $BaseURL !~ m{index\.pl\z};
    return qq{
        <div class="qisutu-install-success"><strong>} . _Escape( _I('AlreadyInstalled') ) . qq{</strong></div>
        <p>} . _Escape( _I('InstallLocked') ) . qq{</p>
        <div class="qisutu-install-actions"><a class="button primary" href="} . _Escape($BaseURL) . qq{">} . _Escape( _I('ToLogin') ) . qq{</a></div>
    };
}

sub _DatabaseInstall {
    my (%Param) = @_;
    my $Request = $Param{Request};
    my $State   = $Param{State};

    my $OperationLock = _InstallerOperationLock();
    return { success => 0, error => _I('InstallerOperationLockFailed') }
        if !$OperationLock;

    my $Host      = _Trim( $Request->{DBHost} );
    my $Port      = _Trim( $Request->{DBPort} );
    my $DBName    = $DefaultDBName;
    my $DBUser    = $DefaultDBUser;
    my $AdminUser = _Trim( $Request->{DBAdminUser} );
    my $AdminPass = defined $Request->{DBAdminPassword} ? $Request->{DBAdminPassword} : '';
    my $UsingBootstrap = 0;
    my $Bootstrap;

    if ( $Request->{UseBootstrap} && -r $BootstrapFile ) {
        $Bootstrap = _BootstrapCredentials();
        if ($Bootstrap) {
            return { success => 0, error => _I('BootstrapLocalOnly') }
                if $Host !~ m{\A(?:localhost|127\.0\.0\.1|::1)\z}i;
            $AdminUser = $Bootstrap->{user};
            $AdminPass = $Bootstrap->{password};
            $UsingBootstrap = 1;
        }
    }

    return { success => 0, error => _I('DatabaseRequired') }
        if !$Host || !$DBName || !$AdminUser;
    return { success => 0, error => _I('DatabasePortInvalid') } if $Port !~ m{\A\d+\z} || $Port < 1 || $Port > 65535;
    return { success => 0, error => _I('DatabaseNameInvalid') } if $DBName !~ m{\A[A-Za-z0-9_]+\z};
    return { success => 0, error => _I('SchemaMissing') } if !-r $SchemaFile;
    return { success => 0, error => _I('SeedMissing') } if !-r $InsertFile;

    my $DBILoaded = eval { require DBI; require DBD::mysql; 1 };
    return { success => 0, error => _I('DBModulesMissing') } if !$DBILoaded;

    my $DBPassword = _RandomPassword(32);
    my $AdminPassword = _RandomPassword(24);
    my $AdminPasswordHash = _PasswordHash($AdminPassword);
    return { success => 0, error => _I('AdminPasswordHashFailed') }
        if !$AdminPasswordHash;

    my $AdminDSN = "DBI:mysql:host=$Host;port=$Port;mysql_enable_utf8mb4=1";
    my $AdminDBH = DBI->connect( $AdminDSN, $AdminUser, $AdminPass, { RaiseError => 0, PrintError => 0, AutoCommit => 1, mysql_enable_utf8mb4 => 1 } );
    return {
        success => 0,
        error   => _I(
            'AdminConnectionFailed',
            error => $DBI::errstr || _I('UnknownError'),
        ),
    } if !$AdminDBH;

    my ($Exists) = $AdminDBH->selectrow_array( 'SELECT COUNT(*) FROM information_schema.SCHEMATA WHERE SCHEMA_NAME = ?', undef, $DBName );
    my $Existed = $Exists ? 1 : 0;
    my $TableCount = 0;
    if ($Existed) {
        ($TableCount) = $AdminDBH->selectrow_array( 'SELECT COUNT(*) FROM information_schema.TABLES WHERE TABLE_SCHEMA = ?', undef, $DBName );
        if ($TableCount) {
            $AdminDBH->disconnect();
            return { success => 0, error => _I( 'DatabaseNotEmpty', database => $DBName ) };
        }
    }

    my $GrantHost = $Host =~ m{\Alocalhost\z}i ? 'localhost'
        : $Host eq '127.0.0.1' ? '127.0.0.1'
        : $Host eq '::1' ? '::1'
        : '%';
    my $QuotedDB = '`' . $DBName . '`';
    my $Account = $AdminDBH->quote($DBUser) . '@' . $AdminDBH->quote($GrantHost);
    my $QuotedPassword = $AdminDBH->quote($DBPassword);

    my ($UserExists) = $AdminDBH->selectrow_array(
        'SELECT COUNT(*) FROM mysql.user WHERE User = ? AND Host = ?',
        undef,
        $DBUser,
        $GrantHost,
    );
    if ( !defined $UserExists ) {
        my $Message = $AdminDBH->errstr || _I('ExistingUserCheckFailed');
        $AdminDBH->disconnect();
        return { success => 0, error => $Message };
    }

    my $UserCreated = 0;
    my $OK = eval {
        $AdminDBH->do("CREATE DATABASE IF NOT EXISTS $QuotedDB CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci") or die $AdminDBH->errstr;
        if ($UserExists) {
            $AdminDBH->do("ALTER USER $Account IDENTIFIED BY $QuotedPassword") or die $AdminDBH->errstr;
        }
        else {
            $AdminDBH->do("CREATE USER $Account IDENTIFIED BY $QuotedPassword") or die $AdminDBH->errstr;
            $UserCreated = 1;
        }
        $AdminDBH->do("GRANT ALL PRIVILEGES ON $QuotedDB.* TO $Account") or die $AdminDBH->errstr;
        1;
    };

    if ( !$OK ) {
        my $Message = $@ || $AdminDBH->errstr || _I('DatabaseCreateFailed');
        $Message =~ s{\s+at\s+\S+\s+line\s+\d+\.?\s*\z}{};
        _DatabaseCleanup(
            DBH       => $AdminDBH,
            DBName    => $DBName,
            Existed   => $Existed,
            DBUser    => $DBUser,
            GrantHost => $GrantHost,
            DropUser  => $UserCreated,
        );
        $AdminDBH->disconnect();
        return { success => 0, error => $Message };
    }

    my $SchemaImport = _SQLImport(
        File       => $SchemaFile,
        Host       => $Host,
        Port       => $Port,
        DBName     => $DBName,
        DBUser     => $DBUser,
        DBPassword => $DBPassword,
    );
    if ( !$SchemaImport->{success} ) {
        _DatabaseCleanup( DBH => $AdminDBH, DBName => $DBName, Existed => $Existed, DBUser => $DBUser, GrantHost => $GrantHost, DropUser => $UserCreated );
        $AdminDBH->disconnect();
        return { success => 0, error => _I( 'SchemaImportFailed', error => $SchemaImport->{error} ) };
    }

    my $DataImport = _SQLImport(
        File       => $InsertFile,
        Host       => $Host,
        Port       => $Port,
        DBName     => $DBName,
        DBUser     => $DBUser,
        DBPassword => $DBPassword,
    );
    if ( !$DataImport->{success} ) {
        _DatabaseCleanup( DBH => $AdminDBH, DBName => $DBName, Existed => $Existed, DBUser => $DBUser, GrantHost => $GrantHost, DropUser => $UserCreated );
        $AdminDBH->disconnect();
        return { success => 0, error => _I( 'SeedImportFailed', error => $DataImport->{error} ) };
    }

    my $AppDSN = "DBI:mysql:database=$DBName;host=$Host;port=$Port;mysql_enable_utf8mb4=1";
    my $DBH = DBI->connect( $AppDSN, $DBUser, $DBPassword, { RaiseError => 0, PrintError => 0, AutoCommit => 1, mysql_enable_utf8mb4 => 1 } );
    if ( !$DBH ) {
        _DatabaseCleanup( DBH => $AdminDBH, DBName => $DBName, Existed => $Existed, DBUser => $DBUser, GrantHost => $GrantHost, DropUser => $UserCreated );
        $AdminDBH->disconnect();
        return { success => 0, error => _I( 'AppDBConnectionFailed', error => $DBI::errstr || _I('UnknownError') ) };
    }

    my $Finalize = _InitialDataFinalize(
        DBH               => $DBH,
        AdminPasswordHash => $AdminPasswordHash,
    );
    if ( !$Finalize->{success} ) {
        $DBH->disconnect();
        _DatabaseCleanup( DBH => $AdminDBH, DBName => $DBName, Existed => $Existed, DBUser => $DBUser, GrantHost => $GrantHost, DropUser => $UserCreated );
        $AdminDBH->disconnect();
        return { success => 0, error => _I( 'SeedFinalizeFailed', error => $Finalize->{error} ) };
    }

    my $CredentialVerification = _AdminCredentialVerify(
        DBH      => $DBH,
        Password => $AdminPassword,
    );
    if ( !$CredentialVerification->{success} ) {
        $DBH->disconnect();
        _DatabaseCleanup( DBH => $AdminDBH, DBName => $DBName, Existed => $Existed, DBUser => $DBUser, GrantHost => $GrantHost, DropUser => $UserCreated );
        $AdminDBH->disconnect();
        return {
            success => 0,
            error   => $CredentialVerification->{error}
                || _I('AdminCredentialVerificationFailed'),
        };
    }

    $DBH->disconnect();

    $State->{db_host}       = $Host;
    $State->{db_port}       = 0 + $Port;
    $State->{db_name}       = $DBName;
    $State->{db_user}       = $DBUser;
    $State->{db_password}   = $DBPassword;
    $State->{admin_password}= $AdminPassword;
    $State->{database_done} = 1;
    $State->{default_language} ||= $InstallLanguage;
    $State->{ui_language}      ||= $InstallLanguage;
    $State->{ticket_hook} = 'Qisutu';
    $State->{attachment_max_size} = 25;

    my $ConfigResult = _ConfigWrite($State);
    if ( !$ConfigResult->{success} ) {
        _DatabaseCleanup( DBH => $AdminDBH, DBName => $DBName, Existed => $Existed, DBUser => $DBUser, GrantHost => $GrantHost, DropUser => $UserCreated );
        $AdminDBH->disconnect();
        return { success => 0, error => $ConfigResult->{error} };
    }

    if ( $UsingBootstrap && $Bootstrap ) {
        my $BootstrapResult = _BootstrapDelete( $Bootstrap, $AdminDBH );
        if ( !$BootstrapResult->{success} ) {
            $State->{database_warning} = $BootstrapResult->{error};
        }
    }
    $AdminDBH->disconnect();

    _Log('Datenbank und Grunddaten wurden erfolgreich eingerichtet.');
    return { success => 1, state => $State };
}

sub _InitialDataFinalize {
    my (%Param) = @_;
    my $DBH = $Param{DBH};
    my $AdminPasswordHash = $Param{AdminPasswordHash} || '';

    return { success => 0, error => _I('SeedConnectionMissing') }
        if !$DBH;
    return { success => 0, error => _I('AdminPasswordHashMissing') }
        if !$AdminPasswordHash;

    my $Statement = $DBH->prepare(
        'UPDATE user_account
         SET password_hash = ?, password_changed_at = NOW()
         WHERE id = 1
             AND password_hash = ?'
    );
    return { success => 0, error => $DBH->errstr || _I('AdminAccountPrepareFailed') }
        if !$Statement;

    my $Result = $Statement->execute(
        $AdminPasswordHash,
        'QISUTU_ADMIN_PASSWORD_NOT_SET',
    );
    if ( !defined $Result ) {
        my $Error = $Statement->errstr || $DBH->errstr || _I('AdminPasswordSaveFailed');
        $Statement->finish();
        return { success => 0, error => $Error };
    }
    $Statement->finish();

    return { success => 0, error => _I('AdminAccountNotFound') }
        if $Result != 1;

    return { success => 1 };
}

sub _AdminCredentialVerify {
    my (%Param) = @_;
    my $DBH      = $Param{DBH};
    my $Password = defined $Param{Password} ? $Param{Password} : '';

    return { success => 0, error => _I('AdminCredentialVerificationFailed') }
        if !$DBH || !$Password;

    my $Account = $DBH->selectrow_hashref(
        'SELECT id, login, account_type, authentication_type, is_active, password_hash
         FROM user_account
         WHERE id = 1
            AND login = ?
            AND account_type = ?
         LIMIT 1',
        undef,
        'admin',
        'agent',
    );
    return { success => 0, error => _I('AdminCredentialVerificationFailed') }
        if !$Account
        || ( $Account->{authentication_type} || 'local' ) ne 'local'
        || !$Account->{is_active}
        || !$Account->{password_hash};

    my $CheckHash = crypt( $Password, $Account->{password_hash} ) || '';
    return { success => 0, error => _I('AdminCredentialVerificationFailed') }
        if !$CheckHash || $CheckHash ne $Account->{password_hash};

    return { success => 1 };
}

sub _AdminCredentialSynchronize {
    my ($State) = @_;
    my $Password = $State->{admin_password} || '';
    return { success => 0, error => _I('AdminCredentialVerificationFailed') }
        if !$Password;

    my $DBH = _ApplicationDBConnect($State);
    return { success => 0, error => _I('DatabaseConnectionFailed') } if !$DBH;

    my $PasswordHash = _PasswordHash($Password);
    if ( !$PasswordHash ) {
        $DBH->disconnect();
        return { success => 0, error => _I('AdminPasswordHashFailed') };
    }

    my $Result = $DBH->do(
        'UPDATE user_account
         SET password_hash = ?,
             authentication_type = ?,
             is_active = 1,
             failed_login_count = 0,
             locked_until = NULL,
             password_changed_at = NOW()
         WHERE id = 1
            AND login = ?
            AND account_type = ?',
        undef,
        $PasswordHash,
        'local',
        'admin',
        'agent',
    );
    if ( !defined $Result || $Result != 1 ) {
        my $Error = $DBH->errstr || _I('AdminPasswordSaveFailed');
        $DBH->disconnect();
        return { success => 0, error => $Error };
    }

    my $Verification = _AdminCredentialVerify(
        DBH      => $DBH,
        Password => $Password,
    );
    $DBH->disconnect();
    return $Verification;
}

sub _InstallationFinalize {
    my (%Param) = @_;
    my $Token = $Param{Token} || '';
    my $State = $Param{State};

    return { success => 0, error => _I('SessionInvalid') }
        if !$Token || !$State;

    my $OperationLock = _InstallerOperationLock();
    return { success => 0, error => _I('InstallerOperationLockFailed') }
        if !$OperationLock;
    return { success => 0, error => _I('AlreadyInstalled') }
        if -f $LockFile;

    my $CredentialResult = _AdminCredentialSynchronize($State);
    return $CredentialResult if !$CredentialResult->{success};

    $State->{show_final} = 1;
    _StateSave( $Token, $State );
    _InstallationLockCreate($State);

    return { success => 1, state => $State };
}

sub _InstallerOperationLock {
    open my $LockHandle, '>>', $InstallerOperationLockFile or return;
    flock( $LockHandle, LOCK_EX ) or return;
    return $LockHandle;
}

sub _SystemSettingsSave {
    my (%Param) = @_;
    my $Request = $Param{Request};
    my $State   = $Param{State};
    return { success => 0, error => _I('DatabaseFirst') } if !$State->{database_done};

    my $HTTP = $Request->{HTTPType} || '';
    my $FQDN = _Trim( $Request->{FQDN} );
    my $Email = lc _Trim( $Request->{AdminEmail} );
    my $Language = $Request->{DefaultLanguage} || '';
    my $Timezone = _Trim( $Request->{Timezone} );
    my $TicketHook = _Trim( $Request->{TicketHook} );
    my $Attachment = _Trim( $Request->{AttachmentMaxSize} );

    return { success => 0, error => _I('ProtocolInvalid') } if $HTTP ne 'http' && $HTTP ne 'https';
    return { success => 0, error => _I('FQDNInvalid') } if !$FQDN || $FQDN !~ m{\A[A-Za-z0-9.\-:\[\]]+\z};
    return { success => 0, error => _I('AdminEmailInvalid') } if $Email !~ m{\A[^\s\@]+\@[^\s\@]+\.[^\s\@]+\z};
    return { success => 0, error => _I('DefaultLanguageInvalid') } if !_LanguageValid($Language);
    return { success => 0, error => _I('TimezoneInvalid') } if !$Timezone || $Timezone !~ m{\A[A-Za-z0-9_+\-/]+\z};
    return { success => 0, error => _I('TicketHookInvalid') } if !$TicketHook || length($TicketHook) > 50;
    return { success => 0, error => _I('AttachmentSizeInvalid') } if $Attachment !~ m{\A\d+\z} || $Attachment < 1 || $Attachment > 10240;

    $State->{http_type} = $HTTP;
    $State->{fqdn} = $FQDN;
    $State->{admin_email} = $Email;
    $State->{default_language} = $Language;
    $State->{ui_language} = $Language;
    $State->{timezone} = $Timezone;
    $State->{ticket_hook} = $TicketHook;
    $State->{attachment_max_size} = 0 + $Attachment;
    $State->{base_url} = "$HTTP://$FQDN$WebPath";
    $State->{login_url} = $State->{base_url} . '/index.pl';

    my $DBH = _ApplicationDBConnect($State);
    return { success => 0, error => _I( 'QisutuDBConnectionFailed', error => $DBI::errstr || _I('UnknownError') ) } if !$DBH;

    my %Settings = (
        'system.http_type'              => $HTTP,
        'system.fqdn'                   => $FQDN,
        'system.web_path'               => $WebPath,
        'system.default_language'       => $Language,
        'system.ticket_hook'            => $TicketHook,
        'system.attachment_max_size_mb' => 0 + $Attachment,
        'system.admin_email'            => $Email,
        'system.timezone'               => $Timezone,
    );

    my $OK = eval {
        $DBH->begin_work();
        my $STH = $DBH->prepare('INSERT INTO system_setting (setting_key, setting_value, created_by_user_id, changed_by_user_id) VALUES (?, ?, 1, 1) ON DUPLICATE KEY UPDATE setting_value = VALUES(setting_value), changed_by_user_id = 1');
        for my $Key ( sort keys %Settings ) {
            $STH->execute( $Key, $Settings{$Key} ) or die $STH->errstr;
        }
        $DBH->do('UPDATE user_account SET email = ?, updated_at = NOW() WHERE id = 1', undef, $Email) or die $DBH->errstr;
        $DBH->commit();
        1;
    };

    if ( !$OK ) {
        my $Message = $@ || $DBH->errstr || _I('UnknownError');
        eval { $DBH->rollback() };
        $DBH->disconnect();
        return { success => 0, error => $Message };
    }
    $DBH->disconnect();

    my $ConfigResult = _ConfigWrite($State);
    return { success => 0, error => $ConfigResult->{error} } if !$ConfigResult->{success};

    $State->{system_done} = 1;
    _Log('Systemeinstellungen wurden gespeichert.');
    return { success => 1, state => $State };
}

sub _MailSettingsSave {
    my (%Param) = @_;
    my $Request = $Param{Request};
    my $State   = $Param{State};
    return { success => 0, error => _I('SystemSettingsFirst') } if !$State->{system_done};

    my $IMAPEnabled = $Request->{IMAPEnabled} ? 1 : 0;
    my $SMTPEnabled = $Request->{SMTPEnabled} ? 1 : 0;
    return { success => 0, error => _I('MailEnableOrSkip') } if !$IMAPEnabled && !$SMTPEnabled;

    my %AllowedSecurity = map { $_ => 1 } qw(imap imap_starttls imaps smtp smtp_starttls smtps);
    my $DBH = _ApplicationDBConnect($State);
    return { success => 0, error => _I('DatabaseConnectionFailed') } if !$DBH;

    my @TestMessages;
    my ($IMAP, $SMTP);

    my $SecurityLoaded = eval {
        require QisutuConfig;
        require QisutuSecurity;
        1;
    };
    if ( !$SecurityLoaded ) {
        my $SecurityLoadError = $@ || _I('UnknownError');
        $SecurityLoadError =~ s{[\r\n]+}{ }g;
        _Log("Sicherheitssystem für Zugangsdaten konnte nicht geladen werden: $SecurityLoadError");
        $DBH->disconnect();
        return { success => 0, error => _I('CredentialSecurityFailed') };
    }
    my $Security = QisutuSecurity->new( Config => QisutuConfig::Load() );

    if ($IMAPEnabled) {
        $IMAP = {
            name       => _Trim( $Request->{IMAPName} ) || _I('DefaultIMAP'),
            email      => lc _Trim( $Request->{IMAPEmail} ),
            host       => _Trim( $Request->{IMAPHost} ),
            port       => _Trim( $Request->{IMAPPort} ),
            security   => $Request->{IMAPSecurity} || '',
            username   => _Trim( $Request->{IMAPUsername} ),
            password   => defined $Request->{IMAPPassword} ? $Request->{IMAPPassword} : '',
        };
        if ( !$IMAP->{email} || !$IMAP->{host} || !$IMAP->{username} || !$IMAP->{password} || $IMAP->{port} !~ m{\A\d+\z} || !$AllowedSecurity{ $IMAP->{security} } ) {
            $DBH->disconnect();
            return { success => 0, error => _I('IMAPFieldsInvalid') };
        }
        my $Test = _MailConnectionTest( Type => 'imap', Data => $IMAP, State => $State );
        if ( !$Test->{success} ) {
            $DBH->disconnect();
            return { success => 0, error => _I( 'IMAPConnectionFailed', error => $Test->{message} ) };
        }
        push @TestMessages, $Test->{message};
    }

    if ($SMTPEnabled) {
        $SMTP = {
            name       => _Trim( $Request->{SMTPName} ) || _I('DefaultSMTP'),
            email      => lc _Trim( $Request->{SMTPEmail} ),
            host       => _Trim( $Request->{SMTPHost} ),
            port       => _Trim( $Request->{SMTPPort} ),
            security   => $Request->{SMTPSecurity} || '',
            username   => _Trim( $Request->{SMTPUsername} ),
            password   => defined $Request->{SMTPPassword} ? $Request->{SMTPPassword} : '',
        };
        if ( !$SMTP->{email} || !$SMTP->{host} || !$SMTP->{username} || !$SMTP->{password} || $SMTP->{port} !~ m{\A\d+\z} || !$AllowedSecurity{ $SMTP->{security} } ) {
            $DBH->disconnect();
            return { success => 0, error => _I('SMTPFieldsInvalid') };
        }
        my $Test = _MailConnectionTest( Type => 'smtp', Data => $SMTP, State => $State );
        if ( !$Test->{success} ) {
            $DBH->disconnect();
            return { success => 0, error => _I( 'SMTPConnectionFailed', error => $Test->{message} ) };
        }
        push @TestMessages, $Test->{message};
    }

    my $OK = eval {
        $DBH->begin_work();
        if ($IMAPEnabled) {
            my $EncryptedPassword = $Security->Encrypt( Value => $IMAP->{password} );
            die( $Security->Error() || 'IMAP password encryption failed' ) if !defined $EncryptedPassword;
            $DBH->do('INSERT INTO postmaster_imap_account (name, email, queue_id, imap_host, imap_security, imap_port, imap_auth_type, imap_username, imap_password, active, sort_order, last_check_at, last_check_status, last_check_message, created_by_user_id, changed_by_user_id) VALUES (?, ?, 1, ?, ?, ?, ?, ?, ?, 1, 100, NOW(), ?, ?, 1, 1)', undef, $IMAP->{name}, $IMAP->{email}, $IMAP->{host}, $IMAP->{security}, $IMAP->{port}, 'password', $IMAP->{username}, $EncryptedPassword, 'ok', 'IMAP connection successful') or die $DBH->errstr;
        }
        if ($SMTPEnabled) {
            my $EncryptedPassword = $Security->Encrypt( Value => $SMTP->{password} );
            die( $Security->Error() || 'SMTP password encryption failed' ) if !defined $EncryptedPassword;
            $DBH->do('INSERT INTO smtp_account (name, smtp_host, smtp_security, smtp_port, smtp_auth_type, smtp_username, smtp_password, active, sort_order, last_check_at, last_check_status, last_check_message, created_by_user_id, changed_by_user_id) VALUES (?, ?, ?, ?, ?, ?, ?, 1, 100, NOW(), ?, ?, 1, 1)', undef, $SMTP->{name}, $SMTP->{host}, $SMTP->{security}, $SMTP->{port}, 'password', $SMTP->{username}, $EncryptedPassword, 'ok', 'SMTP connection successful') or die $DBH->errstr;
        }
        my $SystemEmail = $IMAPEnabled ? $IMAP->{email} : $SMTP->{email};
        $DBH->do('INSERT INTO system_email (name, email, active, sort_order, created_by_user_id, changed_by_user_id) VALUES (?, ?, 1, 100, 1, 1)', undef, 'Qisutu System Email', $SystemEmail) or die $DBH->errstr;
        my $SystemEmailID = $DBH->{mysql_insertid};
        $DBH->do('UPDATE ticket_queue SET system_email_id = ?, changed_by_user_id = 1 WHERE id = 1', undef, $SystemEmailID) or die $DBH->errstr;
        $DBH->commit();
        1;
    };

    if ( !$OK ) {
        my $Message = $@ || $DBH->errstr || _I('UnknownError');
        eval { $DBH->rollback() };
        $DBH->disconnect();
        return { success => 0, error => $Message };
    }

    $DBH->disconnect();
    $State->{mail_done} = 1;
    $State->{mail_skip} = 0;
    _Log('E-Mail-Einstellungen wurden getestet und gespeichert.');
    return { success => 1, state => $State };
}

sub _MailConnectionTest {
    my (%Param) = @_;
    my $Type = $Param{Type};
    my $Data = $Param{Data};
    my $State = $Param{State};

    my $Loaded = eval { require QisutuMail; 1 };
    return { success => 0, message => _I( 'QisutuMailLoadFailed', error => $@ ) } if !$Loaded;

    my $Config = _ConfigHash($State);
    my $Mail = QisutuMail->new( Config => $Config, DB => undef );
    my $Result;
    if ( $Type eq 'imap' ) {
        $Result = $Mail->IMAPTest( Account => {
            inbound_enabled => 1,
            imap_host       => $Data->{host},
            imap_port       => $Data->{port},
            imap_security   => $Data->{security},
            imap_auth_type  => 'password',
            imap_username   => $Data->{username},
            imap_password   => $Data->{password},
        } );
    }
    else {
        $Result = $Mail->SMTPTest( Account => {
            outbound_enabled => 1,
            smtp_host       => $Data->{host},
            smtp_port       => $Data->{port},
            smtp_security   => $Data->{security},
            smtp_auth_type  => 'password',
            smtp_username   => $Data->{username},
            smtp_password   => $Data->{password},
        } );
    }

    return {
        success => $Result && $Result->{Success} ? 1 : 0,
        message => _MailMessage( $Result ? $Result->{Message} : _I('MailTestFailed') ),
    };
}

sub _MailMessage {
    my ($Message) = @_;
    my %Map = (
        'Translate:AdminSMTPConnectionOK'     => _I('SMTPConnectionOK'),
        'Translate:AdminIMAPConnectionOK'     => _I('IMAPConnectionOK'),
        'Translate:AdminSMTPConnectionFailed' => _I('SMTPServerUnavailable'),
        'Translate:AdminIMAPConnectionFailed' => _I('IMAPServerUnavailable'),
        'Translate:AdminSMTPAuthFailed'        => _I('SMTPAuthFailed'),
        'Translate:AdminIMAPAuthFailed'        => _I('IMAPAuthFailed'),
        'Translate:AdminSMTPSSLRequired'       => _I('SMTPSSLRequired'),
        'Translate:AdminIMAPSSLRequired'       => _I('IMAPSSLRequired'),
    );
    return $Map{$Message} || $Message || _I('MailTestFailed');
}

sub _BootstrapCredentials {
    return if !-r $BootstrapFile;
    my $Text = _FileRead($BootstrapFile);
    my %Data;
    for my $Line ( split /\n/, $Text ) {
        next if $Line !~ m{\A([a-z_]+)=(.*)\z};
        $Data{$1} = $2;
    }
    return if !$Data{user} || !$Data{password};
    return \%Data;
}

sub _BootstrapDelete {
    my ( $Bootstrap, $DBH ) = @_;
    return { success => 0, error => _I('BootstrapInvalid') }
        if !$Bootstrap || !$Bootstrap->{user} || !$DBH;

    my $Account = $DBH->quote( $Bootstrap->{user} ) . '@' . $DBH->quote('localhost');
    my $Result = eval { $DBH->do("DROP USER IF EXISTS $Account") };
    if ( !$Result ) {
        return {
            success => 0,
            error   => _I(
                'BootstrapDeleteFailed',
                user  => $Bootstrap->{user},
                error => $DBH->errstr || $@ || _I('UnknownError'),
            ),
        };
    }

    unlink $BootstrapFile;
    return { success => 1 };
}

sub _SQLImport {
    my (%Param) = @_;
    my $SQLFile = $Param{File} || '';

    return { success => 0, error => _I('SQLFileMissing') }
        if !$SQLFile || !-r $SQLFile;

    my $ErrorHandle = gensym;
    local $ENV{MYSQL_PWD} = $Param{DBPassword};
    my $DatabaseCLI = _DatabaseCLI();
    return { success => 0, error => _I('DatabaseCLIMissing') } if !$DatabaseCLI;

    my @Command = (
        $DatabaseCLI,
        '--default-character-set=utf8mb4',
        '--host=' . $Param{Host},
        '--port=' . $Param{Port},
        '--user=' . $Param{DBUser},
        $Param{DBName},
    );

    my ( $In, $Out );
    my $PID = eval { open3( $In, $Out, $ErrorHandle, @Command ) };
    return { success => 0, error => _I( 'DatabaseCLIStartFailed', error => $@ ) } if !$PID;

    open my $SQLHandle, '<:raw', $SQLFile
        or return { success => 0, error => _I( 'SQLReadFailed', error => $! ) };
    while ( read( $SQLHandle, my $Buffer, 65536 ) ) {
        print {$In} $Buffer;
    }
    close $SQLHandle;
    close $In;
    local $/;
    my $Stdout = <$Out> // '';
    my $Stderr = <$ErrorHandle> // '';
    close $Out;
    close $ErrorHandle;
    waitpid( $PID, 0 );
    my $Exit = $? >> 8;

    $Stderr =~ s{\Q$Param{DBPassword}\E}{[PASSWORT ENTFERNT]}g if $Param{DBPassword};
    return {
        success => 0,
        error   => _Trim($Stderr) || _I( 'DatabaseCLIExit', status => $Exit ),
    } if $Exit != 0;
    return { success => 1 };
}

sub _DatabaseCleanup {
    my (%Param) = @_;
    my $DBH = $Param{DBH};
    my $DBName = $Param{DBName};
    return if !$DBH || $DBName !~ m{\A[A-Za-z0-9_]+\z};
    eval {
        $DBH->do("DROP DATABASE IF EXISTS `$DBName`");
        if ( $Param{Existed} ) {
            $DBH->do("CREATE DATABASE `$DBName` CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci");
        }
        if ( $Param{DropUser} && $Param{DBUser} && $Param{GrantHost} ) {
            my $Account = $DBH->quote( $Param{DBUser} ) . '@' . $DBH->quote( $Param{GrantHost} );
            $DBH->do("DROP USER IF EXISTS $Account");
        }
    };
}

sub _ApplicationDBConnect {
    my ($State) = @_;
    my $Loaded = eval { require DBI; require DBD::mysql; 1 };
    return if !$Loaded;
    my $DSN = sprintf 'DBI:mysql:database=%s;host=%s;port=%s;mysql_enable_utf8mb4=1', $State->{db_name}, $State->{db_host}, $State->{db_port};
    return DBI->connect( $DSN, $State->{db_user}, $State->{db_password}, { RaiseError => 0, PrintError => 0, AutoCommit => 1, mysql_enable_utf8mb4 => 1 } );
}

sub _ConfigWrite {
    my ($State) = @_;
    my $Config = _ConfigText($State);
    my $FH;
    if ( !open $FH, '>:encoding(UTF-8)', $ConfigFile ) {
        return { success => 0, error => _I( 'ConfigWriteFailed', error => $! ) };
    }
    print {$FH} $Config;
    close $FH or return { success => 0, error => _I( 'ConfigSaveFailed', error => $! ) };
    chmod 0660, $ConfigFile;
    return { success => 1 };
}

sub _ConfigText {
    my ($State) = @_;
    my $Host = _PerlQuote( $State->{db_host} || 'localhost' );
    my $Port = $State->{db_port} || 3306;
    my $Name = _PerlQuote( $State->{db_name} || $DefaultDBName );
    my $User = _PerlQuote( $State->{db_user} || $DefaultDBUser );
    my $Password = _PerlQuote( $State->{db_password} || 'CHANGE-ME-DURING-INSTALLATION' );
    my $Language = _PerlQuote( $State->{default_language} || 'de' );
    my $BaseURL = _PerlQuote( $State->{base_url} || '' );
    my $TicketHook = _PerlQuote( $State->{ticket_hook} || 'Qisutu' );
    my $ConfiguredRootPath = _PerlQuote($RootPath);
    my $ConfiguredCookieName = _PerlQuote($SessionCookieName);
    my $ConfiguredInstanceID = _PerlQuote($InstanceID);
    my $ConfiguredWebPath = _PerlQuote($WebPath);
    my $ConfiguredProgramVersion = _PerlQuote($ProgramVersion);

    return <<"CONFIG";
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

package QisutuConfig;

use strict;
use warnings;
use utf8;

sub Load {
    my \$RootPath = \$ENV{QISUTU_HOME} || '$ConfiguredRootPath';

    return {
        RootPath => \$RootPath,

        Database => {
            Type     => 'mysql',
            Host     => '$Host',
            Port     => $Port,
            Name     => '$Name',
            User     => '$User',
            Password => '$Password',
            Charset  => 'utf8mb4',
        },

        Session => {
            CookieName      => '$ConfiguredCookieName',
            LifetimeSeconds => 28800,
        },

        Language => {
            Default => '$Language',
        },

        Paths => {
            Core          => "\$RootPath/core",
            Config        => "\$RootPath/core/config",
            ProgramConfig => "\$RootPath/core/config/programs",
            SettingConfig => "\$RootPath/core/config/settings",
            ThemeConfig   => "\$RootPath/core/config/themes",
            Module        => "\$RootPath/core/module",
            Output        => "\$RootPath/core/output",
            System        => "\$RootPath/core/system",
            Language      => "\$RootPath/core/language",
            Var           => "\$RootPath/var",
            Log           => "\$RootPath/var/log",
            Cache         => "\$RootPath/var/cache",
            Static        => "\$RootPath/var/static",
            StaticURL     => '$WebPath/static',
            SecurityKey   => "\$RootPath/var/secure/security.key",
        },

        System => {
            Name       => 'Qisutu',
            Version    => '$ConfiguredProgramVersion',
            InstanceID => '$ConfiguredInstanceID',
            WebPath    => '$ConfiguredWebPath',
            BaseURL    => '$BaseURL',
            TicketHook => '$TicketHook',
        },
    };
}

1;
CONFIG
}

sub _ConfigHash {
    my ($State) = @_;
    return {
        RootPath => $RootPath,
        Database => { Host => $State->{db_host}, Port => $State->{db_port}, Name => $State->{db_name}, User => $State->{db_user}, Password => $State->{db_password}, Charset => 'utf8mb4' },
        Session => { CookieName => $SessionCookieName, LifetimeSeconds => 28800 },
        Language => { Default => $State->{default_language} || 'de' },
        Paths => { Var => "$RootPath/var", Log => "$RootPath/var/log", Static => "$RootPath/var/static", StaticURL => "$WebPath/static", SecurityKey => "$RootPath/var/secure/security.key" },
        System => { Name => 'Qisutu', InstanceID => $InstanceID, WebPath => $WebPath, BaseURL => $State->{base_url} || '', TicketHook => $State->{ticket_hook} || 'Qisutu' },
    };
}

sub _SystemChecks {
    my @Checks;
    push @Checks, {
        name     => 'Perl',
        ok       => $] >= 5.026 ? 1 : 0,
        critical => 1,
        detail   => _I( 'VersionLabel', version => sprintf( '%.3f', $] ) ),
    };
    push @Checks, _ModuleCheck( 'DBI', 1 );
    push @Checks, _ModuleCheck( 'DBD::mysql', 1 );
    push @Checks, _ModuleCheck( 'IO::Socket::SSL', 1 );
    push @Checks, _ModuleCheck( 'Authen::SASL', 1 );
    push @Checks, _ModuleCheck( 'MIME::Base64', 1 );
    push @Checks, _ModuleCheck( 'MIME::QuotedPrint', 1 );
    push @Checks, _ModuleCheck( 'Net::SMTP', 1 );
    push @Checks, _ModuleCheck( 'Net::LDAP', 1 );
    my $DatabaseCLI = _DatabaseCLI();
    push @Checks, { name => 'MariaDB/MySQL Client', ok => $DatabaseCLI ? 1 : 0, critical => 1, detail => $DatabaseCLI ? $DatabaseCLI : _I('NotFound') };
    push @Checks, { name => 'Apache CGI', ok => $ENV{GATEWAY_INTERFACE} ? 1 : 0, critical => 1, detail => $ENV{GATEWAY_INTERFACE} || _I('NotViaCGI') };
    push @Checks, { name => _I('DatabaseSchema'), ok => -r $SchemaFile ? 1 : 0, critical => 1, detail => -r $SchemaFile ? _I('Readable') : _I('Missing') };
    push @Checks, { name => _I('SeedData'), ok => -r $InsertFile ? 1 : 0, critical => 1, detail => -r $InsertFile ? _I('Readable') : _I('Missing') };
    push @Checks, { name => 'QisutuConfig.pm', ok => -w $ConfigFile ? 1 : 0, critical => 1, detail => -w $ConfigFile ? _I('Writable') : _I('NotWritable') };
    push @Checks, { name => _I('InstallationDirectory'), ok => -w $InstallPath ? 1 : 0, critical => 1, detail => -w $InstallPath ? _I('Writable') : _I('NotWritable') };
    my $Crypt = crypt( 'test', '$6$abcdefghijklmnop$' ) || '';
    push @Checks, { name => _I('PasswordHash'), ok => $Crypt =~ m{\A\$6\$} ? 1 : 0, critical => 1, detail => $Crypt =~ m{\A\$6\$} ? _I('Available') : _I('Unavailable') };
    return \@Checks;
}

sub _ModuleCheck {
    my ( $Module, $Critical ) = @_;
    my $OK = eval "require $Module; 1;" ? 1 : 0;
    return {
        name     => _I( 'PerlModule', module => $Module ),
        ok       => $OK,
        critical => $Critical,
        detail   => $OK ? _I('Present') : _I('NotInstalled'),
    };
}

sub _DatabaseCLI {
    return 'mariadb' if _CommandExists('mariadb');
    return 'mysql' if _CommandExists('mysql');
    return '';
}

sub _CommandExists {
    my ($Command) = @_;
    for my $Path ( split /:/, $ENV{PATH} || '' ) {
        return 1 if -x File::Spec->catfile( $Path, $Command );
    }
    return 0;
}

sub _PasswordHash {
    my ($Password) = @_;
    my @Chars = ( 'a' .. 'z', 'A' .. 'Z', 0 .. 9, '.', '/' );
    my $Salt = join '', map { $Chars[ _RandomInt( scalar @Chars ) ] } 1 .. 16;
    return crypt( $Password, '$6$' . $Salt . '$' );
}

sub _RandomPassword {
    my ($Length) = @_;
    my @Chars = split //, 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789@#%_+';
    return join '', map { $Chars[ _RandomInt( scalar @Chars ) ] } 1 .. $Length;
}

sub _RandomToken {
    my $Bytes = '';
    if ( open my $Random, '<:raw', '/dev/urandom' ) {
        read $Random, $Bytes, 64;
        close $Random;
    }
    $Bytes ||= join ':', time, $$, rand(), {}, $ENV{REMOTE_ADDR} || '';
    return sha256_hex($Bytes);
}

sub _RandomInt {
    my ($Maximum) = @_;
    my $Bytes = '';
    if ( open my $Random, '<:raw', '/dev/urandom' ) {
        read $Random, $Bytes, 4;
        close $Random;
    }
    my $Number = length($Bytes) == 4 ? unpack( 'N', $Bytes ) : int( rand( 0xffffffff ) );
    return $Number % $Maximum;
}

sub _SessionLoadOrCreate {
    my $Cookie = _CookieGet($InstallCookieName);
    if ( $Cookie && $Cookie =~ m{\A[a-f0-9]{64}\z} ) {
        my $State = _StateLoad($Cookie);
        return ( $Cookie, $State, 0 ) if $State;
    }
    my $Token = _RandomToken();
    my $State = {
        csrf_token      => _RandomToken(),
        created_at      => time,
        remote_addr     => $ENV{REMOTE_ADDR} || '',
        ui_language     => $InstallLanguage,
        default_language => $InstallLanguage,
    };
    _StateSave( $Token, $State );
    return ( $Token, $State, 1 );
}

sub _StateFile {
    my ($Token) = @_;
    return File::Spec->catfile( $InstallPath, "session-$Token.json" );
}

sub _StateLoad {
    my ($Token) = @_;
    my $File = _StateFile($Token);
    return if !-f $File;
    my $JSON = _FileRead($File);
    my $State = eval { JSON::PP->new->utf8(0)->decode($JSON) };
    return if !$State || ref $State ne 'HASH';
    return if $State->{remote_addr} && ( $ENV{REMOTE_ADDR} || '' ) && $State->{remote_addr} ne ( $ENV{REMOTE_ADDR} || '' );
    return $State;
}

sub _StateSave {
    my ( $Token, $State ) = @_;
    my $File = _StateFile($Token);
    my $JSON = JSON::PP->new->utf8(1)->canonical(1)->encode($State);
    open my $FH, '>:raw', $File or die "Installationsstatus kann nicht gespeichert werden: $!";
    print {$FH} $JSON;
    close $FH;
    chmod 0600, $File;
}

sub _StateDelete {
    my ($Token) = @_;
    unlink _StateFile($Token);
}

sub _InstallationLockCreate {
    my ($State) = @_;
    open my $FH, '>:encoding(UTF-8)', $LockFile or die "Installationssperre kann nicht erstellt werden: $!";
    print {$FH} "installed_at=" . strftime( '%Y-%m-%d %H:%M:%S', localtime ) . "\n";
    print {$FH} "instance_id=$InstanceID\n";
    print {$FH} "web_path=$WebPath\n";
    print {$FH} "base_url=" . ( $State->{base_url} || '' ) . "\n";
    close $FH;
    chmod 0640, $LockFile;
    _Log('Installation wurde abgeschlossen.');
}

sub _Page {
    my (%Param) = @_;
    my $Step = $Param{Step};
    my @Labels = map { _I($_) } qw(
        ProgressWelcome
        ProgressLicense
        ProgressDatabase
        ProgressSystem
        ProgressEmail
        ProgressFinish
    );
    my $Progress = '';
    for my $Index ( 1 .. 6 ) {
        my $Class = $Index < $Step ? 'done' : $Index == $Step ? 'active' : '';
        $Progress .= '<div class="' . $Class . '"><span>' . $Index . '</span><small>' . $Labels[ $Index - 1 ] . '</small></div>';
    }

    return '<!doctype html><html lang="' . _Escape($UILanguage) . '"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width, initial-scale=1"><meta name="robots" content="noindex,nofollow"><title>'
        . _Escape( $Param{Title} ) . ' - ' . _Escape( _I('PageBrand') ) . '</title><link rel="icon" type="image/x-icon" sizes="32x32" href="' . $WebPath . '/static/img/favicon.ico?v=2026072101"><link rel="apple-touch-icon" sizes="180x180" href="' . $WebPath . '/static/img/apple-touch-icon.png?v=2026072101"><link rel="stylesheet" href="' . $WebPath . '/static/css/qisutu-install.css?v=2026073001"><script src="' . $WebPath . '/static/js/qisutu-install.js?v=2026073001" defer></script></head><body>'
        . '<div class="qisutu-install-shell"><header><div class="brand"><img src="' . $WebPath . '/static/img/logo.png" alt="Qisutu"><strong>' . _Escape( _I('PageBrand') ) . '</strong></div><div class="step-text">' . _Escape( _I( 'StepOf', step => $Step, total => 6 ) ) . '</div></header>'
        . '<nav class="qisutu-install-progress" aria-label="' . _Escape( _I('ProgressAria') ) . '">' . $Progress . '</nav>'
        . '<main><h1>' . _Escape( $Param{Title} ) . '</h1>' . $Param{Content} . '</main>'
        . '<footer>Qisutu - Open Source Ticket System · AGPL-3.0-or-later</footer></div></body></html>';
}

sub _Field {
    my ( $Label, $Name, $Value, $Type, $Required, $Extra ) = @_;
    return '<div class="qisutu-install-field"><label for="' . _Escape($Name) . '">' . _Escape($Label) . '</label><input id="' . _Escape($Name) . '" type="' . _Escape($Type) . '" name="' . _Escape($Name) . '" value="' . _Escape( defined $Value ? $Value : '' ) . '"' . ( $Required ? ' required' : '' ) . ( $Extra ? ' ' . $Extra : '' ) . '></div>';
}

sub _SelectField {
    my ( $Label, $Name, $Selected, $Options ) = @_;
    my $HTML = '<div class="qisutu-install-field"><label for="' . _Escape($Name) . '">' . _Escape($Label) . '</label><select id="' . _Escape($Name) . '" name="' . _Escape($Name) . '">';
    for my $Option ( @{$Options} ) {
        $HTML .= '<option value="' . _Escape( $Option->[0] ) . '"' . ( $Option->[0] eq $Selected ? ' selected' : '' ) . '>' . _Escape( $Option->[1] ) . '</option>';
    }
    return $HTML . '</select></div>';
}

sub _InstallerLanguageLoad {
    my ($Language) = @_;

    $InstallerEnglish = _InstallerCatalogLoad('en');
    $InstallerText    = _InstallerCatalogLoad($Language);
    $InstallerText    = $InstallerEnglish if !%{$InstallerText};

    return;
}

sub _InstallerCatalogLoad {
    my ($Language) = @_;

    $Language = _LanguageCanonical($Language);
    return {} if !$Language;

    my $File = File::Spec->catfile( $InstallerLanguagePath, "$Language.pm" );
    return {} if !-f $File || -l $File;

    my $Catalog = do $File;
    return ref $Catalog eq 'HASH' ? $Catalog : {};
}

sub _InstallerLanguageAvailable {
    my ($Language) = @_;

    $Language = _LanguageCanonical($Language);
    return if !$Language;

    my $CoreFile = File::Spec->catfile( $RootPath, 'core', 'language', "$Language.pm" );
    my $InstallFile = File::Spec->catfile( $InstallerLanguagePath, "$Language.pm" );
    return -f $CoreFile && !-l $CoreFile && -f $InstallFile && !-l $InstallFile ? 1 : 0;
}

sub _LanguageCanonical {
    my ($Language) = @_;

    return '' if !defined $Language || ref $Language;
    $Language =~ s{\A\s+|\s+\z}{}g;
    $Language =~ tr{_}{-};
    return '' if $Language !~ m{\A[A-Za-z]{2,3}(?:-[A-Za-z]{2})?\z};

    if ( $Language =~ m{\A([A-Za-z]{2,3})-([A-Za-z]{2})\z} ) {
        return lc($1) . '-' . uc($2);
    }

    return lc $Language;
}

sub _I {
    my ( $Key, %Param ) = @_;

    my $Text = exists $InstallerText->{$Key}
        ? $InstallerText->{$Key}
        : exists $InstallerEnglish->{$Key}
            ? $InstallerEnglish->{$Key}
            : $Key;

    for my $Name ( sort { length($b) <=> length($a) } keys %Param ) {
        my $Value = defined $Param{$Name} ? $Param{$Name} : '';
        $Text =~ s{\{\Q$Name\E\}}{$Value}g;
    }

    return $Text;
}

sub _LanguageOptions {
    my ($Selected) = @_;
    my @Options = (
        [ de      => 'Deutsch' ],
        [ en      => 'English' ],
        [ fr      => 'Français' ],
        [ it      => 'Italiano' ],
        [ 'pt-BR' => 'Português (Brasil)' ],
        [ 'pt-PT' => 'Português (Portugal)' ],
        [ es      => 'Español' ],
        [ nl      => 'Nederlands' ],
        [ pl      => 'Polski' ],
        [ cs      => 'Čeština' ],
        [ tr      => 'Türkçe' ],
    );
    return join '', map { '<option value="' . $_->[0] . '"' . ( $_->[0] eq $Selected ? ' selected' : '' ) . '>' . _Escape( $_->[1] ) . '</option>' } @Options;
}

sub _LanguageValid {
    my ($Language) = @_;

    $Language = _LanguageCanonical($Language);
    return if !$Language;

    my $File = File::Spec->catfile( $RootPath, 'core', 'language', "$Language.pm" );
    return -f $File && !-l $File ? 1 : 0;
}

sub _ErrorHTML {
    my ($Error) = @_;
    return '' if !$Error;
    return '<div class="qisutu-install-error"><strong>' . _Escape( _I('ErrorPrefix') ) . '</strong> ' . _Escape($Error) . '</div>';
}

sub _RequestParams {
    my %Param;
    _ParamParse( \%Param, $ENV{QUERY_STRING} || '' );
    if ( ( $ENV{REQUEST_METHOD} || '' ) eq 'POST' ) {
        my $Length = $ENV{CONTENT_LENGTH} || 0;
        $Length = 0 if $Length !~ m{\A\d+\z} || $Length > 1_000_000;
        my $Body = '';
        read STDIN, $Body, $Length if $Length;
        _ParamParse( \%Param, $Body );
    }
    return \%Param;
}

sub _ParamParse {
    my ( $Target, $Source ) = @_;
    for my $Pair ( split /[&;]/, $Source ) {
        next if $Pair eq '';
        my ( $Key, $Value ) = split /=/, $Pair, 2;
        $Key = _URLDecode( $Key // '' );
        $Value = _URLDecode( $Value // '' );
        $Target->{$Key} = $Value;
    }
}

sub _URLDecode {
    my ($Value) = @_;
    $Value =~ tr/+/ /;
    $Value =~ s/%([0-9A-Fa-f]{2})/chr(hex($1))/eg;
    return eval { decode( 'UTF-8', $Value, 1 ) } || $Value;
}

sub _CookieGet {
    my ($Name) = @_;
    for my $Pair ( split /;\s*/, $ENV{HTTP_COOKIE} || '' ) {
        my ( $Key, $Value ) = split /=/, $Pair, 2;
        return $Value if ( $Key || '' ) eq $Name;
    }
    return '';
}

sub _SessionCookie {
    my ($Token) = @_;
    my $Secure = ( $ENV{HTTPS} || '' ) eq 'on' ? '; Secure' : '';
    return "$InstallCookieName=$Token; Path=$WebPath/; HttpOnly; SameSite=Strict$Secure";
}

sub _SessionCookieDelete {
    return "$InstallCookieName=; Path=$WebPath/; Max-Age=0; HttpOnly; SameSite=Strict";
}

sub _Redirect {
    my (%Param) = @_;
    my @Headers = ( 'Status: 302 Found', 'Location: ' . $Param{Location} );
    push @Headers, 'Set-Cookie: ' . $Param{Cookie} if $Param{Cookie};
    print join( "\r\n", @Headers ) . "\r\n\r\n";
    exit;
}

sub _PrintResponse {
    my (%Param) = @_;
    my $Body = $Param{Body} // '';
    $Body = encode( 'UTF-8', $Body ) if utf8::is_utf8($Body);
    my @Headers = ( 'Status: 200 OK', 'Content-Type: text/html; charset=UTF-8', 'Cache-Control: no-store, private', 'Pragma: no-cache', 'X-Content-Type-Options: nosniff', 'X-Frame-Options: DENY', "Content-Security-Policy: default-src 'self'; style-src 'self'; img-src 'self' data:; form-action 'self'; frame-ancestors 'none'" );
    push @Headers, 'Set-Cookie: ' . $Param{Cookie} if $Param{Cookie};
    print join( "\r\n", @Headers ) . "\r\n\r\n" . $Body;
}

sub _ConfigBaseURLRead {
    return '' if !-r $ConfigFile;
    my $Text = _FileRead($ConfigFile);
    return $1 if $Text =~ m{BaseURL\s*=>\s*'([^']*)'};
    return '';
}

sub _FileRead {
    my ($File) = @_;
    return '' if !-r $File;
    open my $FH, '<:encoding(UTF-8)', $File or return '';
    local $/;
    my $Content = <$FH> // '';
    close $FH;
    return $Content;
}

sub _PerlQuote {
    my ($Value) = @_;
    $Value = '' if !defined $Value;
    $Value =~ s{\\}{\\\\}g;
    $Value =~ s{'}{\\'}g;
    return $Value;
}

sub _Trim {
    my ($Value) = @_;
    $Value = '' if !defined $Value;
    $Value =~ s{\A\s+}{};
    $Value =~ s{\s+\z}{};
    return $Value;
}

sub _Escape {
    my ($Value) = @_;
    $Value = '' if !defined $Value;
    $Value =~ s{&}{&amp;}g;
    $Value =~ s{<}{&lt;}g;
    $Value =~ s{>}{&gt;}g;
    $Value =~ s{"}{&quot;}g;
    $Value =~ s{'}{&#39;}g;
    return $Value;
}

sub _Log {
    my ($Message) = @_;
    return if !$Message;
    if ( open my $FH, '>>:encoding(UTF-8)', $LogFile ) {
        print {$FH} strftime( '%Y-%m-%d %H:%M:%S', localtime ) . " $Message\n";
        close $FH;
    }
}
