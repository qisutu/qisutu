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
use FindBin;
use IPC::Open3;
use JSON::PP;
use POSIX qw(strftime);
use Symbol qw(gensym);

my $RootPath = $ENV{QISUTU_HOME} || abs_path( File::Spec->catdir( $FindBin::Bin, '..', '..' ) );
my $InstallPath = File::Spec->catdir( $RootPath, 'var', 'install' );
my $LockFile = File::Spec->catfile( $InstallPath, 'installed.lock' );
my $SchemaFile = File::Spec->catfile( $RootPath, 'install', 'sql', 'schema.sql' );
my $ConfigFile = File::Spec->catfile( $RootPath, 'core', 'config', 'QisutuConfig.pm' );
my $LicenseFile = File::Spec->catfile( $RootPath, 'LICENSE' );
my $ThirdPartyFile = File::Spec->catfile( $RootPath, 'THIRD_PARTY_NOTICES.md' );
my $LogFile = File::Spec->catfile( $RootPath, 'var', 'log', 'install.log' );
my $BootstrapFile = File::Spec->catfile( $InstallPath, 'database-bootstrap.conf' );
my $InstanceFile = File::Spec->catfile( $InstallPath, 'instance.conf' );

my %InstanceConfig = (
    instance_id    => 'qisutu',
    web_path       => '/qisutu',
    session_cookie => 'QISUTU_SESSION',
    db_name        => 'qisutu',
    db_user        => 'qisutu',
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

my $InstanceID       = $InstanceConfig{instance_id};
my $WebPath          = $InstanceConfig{web_path};
my $SessionCookieName = $InstanceConfig{session_cookie};
my $InstallCookieName = $SessionCookieName . '_INSTALL';
my $DefaultDBName    = $InstanceConfig{db_name};
my $DefaultDBUser    = $InstanceConfig{db_user};

binmode STDOUT, ':raw';

my $Request = _RequestParams();
my ( $Token, $State, $NewSession ) = _SessionLoadOrCreate();
my $Step = $Request->{Step} || 1;
$Step = 1 if $Step !~ m{\A[1-6]\z};

if ( -f $LockFile && !( $Step == 6 && $State->{show_final} ) ) {
    _PrintResponse(
        Body => _Page(
            Step    => 6,
            Title   => 'Qisutu ist bereits installiert',
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
        $Error = 'Die Installationssitzung ist ungültig. Bitte lade die Seite neu.';
    }
    elsif ( $Action eq 'Begin' ) {
        my $Checks = _SystemChecks();
        if ( grep { $_->{critical} && !$_->{ok} } @{$Checks} ) {
            $Error = 'Mindestens eine zwingende Systemvoraussetzung ist nicht erfüllt.';
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
            $Error = 'Die Lizenzbedingungen müssen bestätigt werden.';
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
            $Error = $Result->{error} || 'Die Datenbankinstallation ist fehlgeschlagen.';
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
            $Error = 'Die Datenbank wurde noch nicht eingerichtet.';
            $Step  = 3;
        }
        else {
            _Redirect( Location => 'install.pl?Step=4', Cookie => $NewSession ? _SessionCookie($Token) : '' );
        }
    }
    elsif ( $Action eq 'SaveSystem' ) {
        my $Result = _SystemSettingsSave( Request => $Request, State => $State );
        if ( !$Result->{success} ) {
            $Error = $Result->{error} || 'Die Systemeinstellungen konnten nicht gespeichert werden.';
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
            $Error = 'Die Systemeinstellungen wurden noch nicht gespeichert.';
            $Step  = 4;
        }
        else {
            $State->{mail_done}  = 1;
            $State->{mail_skip}  = 1;
            $State->{show_final} = 1;
            _StateSave( $Token, $State );
            _InstallationLockCreate($State);
            _Redirect( Location => 'install.pl?Step=6', Cookie => $NewSession ? _SessionCookie($Token) : '' );
        }
    }
    elsif ( $Action eq 'SaveMail' ) {
        my $Result = _MailSettingsSave( Request => $Request, State => $State );
        if ( !$Result->{success} ) {
            $Error = $Result->{error} || 'Die E-Mail-Einstellungen konnten nicht gespeichert werden.';
            $Step  = 5;
        }
        else {
            $State = $Result->{state};
            $State->{show_final} = 1;
            _StateSave( $Token, $State );
            _InstallationLockCreate($State);
            _Redirect( Location => 'install.pl?Step=6', Cookie => $NewSession ? _SessionCookie($Token) : '' );
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
    $Title   = 'Willkommen bei Qisutu';
    $Content = _WelcomeHTML( Error => $Error, State => $State );
}
elsif ( $Step == 2 ) {
    $Title   = 'Lizenzbedingungen';
    $Content = _LicenseHTML( Error => $Error, State => $State );
}
elsif ( $Step == 3 ) {
    $Title   = 'Datenbank einrichten';
    $Content = _DatabaseHTML( Error => $Error, State => $State, Request => $Request );
}
elsif ( $Step == 4 ) {
    $Title   = 'Systemeinstellungen';
    $Content = _SystemHTML( Error => $Error, State => $State, Request => $Request );
}
elsif ( $Step == 5 ) {
    $Title   = 'E-Mail-Einstellungen';
    $Content = _MailHTML( Error => $Error, State => $State, Request => $Request );
}
else {
    $Title   = 'Installation abgeschlossen';
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
        my $Label = $Check->{ok} ? 'OK' : ( $Check->{critical} ? 'Fehler' : 'Hinweis' );
        $HasError = 1 if $Check->{critical} && !$Check->{ok};
        $Rows .= '<tr><td>' . _Escape( $Check->{name} ) . '</td><td>' . _Escape( $Check->{detail} )
            . '</td><td><span class="qisutu-install-status ' . $Class . '">' . $Label . '</span></td></tr>';
    }

    return _ErrorHTML( $Param{Error} ) . qq{
        <div class="qisutu-install-welcome">
            <div>
                <h2>Willkommen bei Qisutu</h2>
                <p>Dieser Assistent richtet das Qisutu Ticketsystem, die Datenbank, den ersten Administrator und die wichtigsten Systemeinstellungen ein.</p>
                <p>Die Installation führt dich Schritt für Schritt durch alle erforderlichen Angaben und prüft die wichtigsten Voraussetzungen automatisch.</p>
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
        <h3>Instanz</h3>
        <div class="qisutu-install-credentials">
            <div><span>Instanzkennung</span><strong>} . _Escape($InstanceID) . qq{</strong></div>
            <div><span>Webpfad</span><strong>} . _Escape($WebPath) . qq{</strong></div>
            <div><span>Datenbankname</span><strong>} . _Escape($DefaultDBName) . qq{</strong></div>
            <div><span>Datenbankbenutzer</span><strong>} . _Escape($DefaultDBUser) . qq{</strong></div>
        </div>
        <h3>Systemprüfung</h3>
        <div class="qisutu-install-table-wrap"><table><thead><tr><th>Prüfung</th><th>Ergebnis</th><th>Status</th></tr></thead><tbody>$Rows</tbody></table></div>
        <form method="post" action="install.pl">
            <input type="hidden" name="Step" value="1">
            <input type="hidden" name="Action" value="Begin">
            <input type="hidden" name="CSRFToken" value="} . _Escape( $Param{State}->{csrf_token} ) . qq{">
            <div class="qisutu-install-actions"><button class="primary" type="submit"} . ( $HasError ? ' disabled' : '' ) . qq{>Installation starten</button></div>
        </form>
    };
}

sub _LicenseHTML {
    my (%Param) = @_;
    my $License = _FileRead($LicenseFile);
    my $Third   = _FileRead($ThirdPartyFile);

    return _ErrorHTML( $Param{Error} ) . qq{
        <p>Qisutu wird unter der GNU Affero General Public License, Version 3 oder später, veröffentlicht.</p>
        <div class="qisutu-install-license"><h3>AGPL-3.0-or-later</h3><pre>} . _Escape($License) . qq{</pre></div>
        <div class="qisutu-install-license"><h3>Hinweise zu Drittanbieter-Komponenten</h3><pre>} . _Escape($Third) . qq{</pre></div>
        <form method="post" action="install.pl">
            <input type="hidden" name="Step" value="2">
            <input type="hidden" name="Action" value="AcceptLicense">
            <input type="hidden" name="CSRFToken" value="} . _Escape( $Param{State}->{csrf_token} ) . qq{">
            <label class="qisutu-install-check"><input type="checkbox" name="LicenseAccepted" value="1" required> Ich habe die Lizenzbedingungen und Hinweise gelesen und akzeptiert.</label>
            <div class="qisutu-install-actions"><button class="primary" type="submit">Weiter</button></div>
        </form>
    };
}

sub _DatabaseHTML {
    my (%Param) = @_;
    my $State = $Param{State};

    if ( $State->{database_done} ) {
        return _ErrorHTML( $Param{Error} ) . qq{
            <div class="qisutu-install-success"><strong>Die Datenbank wurde erfolgreich eingerichtet.</strong></div>
            } . ( $State->{database_warning} ? '<div class="qisutu-install-error"><strong>Sicherheitshinweis:</strong> ' . _Escape( $State->{database_warning} ) . '</div>' : '' ) . qq{
            <p>Bitte schreibe dir diese Daten auf und bewahre sie sicher auf. Das Datenbankpasswort wurde direkt in <code>core/config/QisutuConfig.pm</code> eingetragen.</p>
            <div class="qisutu-install-credentials">
                <div><span>Datenbankserver</span><strong>} . _Escape( $State->{db_host} ) . qq{</strong></div>
                <div><span>Datenbankname</span><strong>} . _Escape( $State->{db_name} ) . qq{</strong></div>
                <div><span>Datenbankbenutzer</span><strong>} . _Escape( $State->{db_user} ) . qq{</strong></div>
                <div><span>Datenbankpasswort</span><strong class="credential">} . _Escape( $State->{db_password} ) . qq{</strong></div>
            </div>
            <form method="post" action="install.pl">
                <input type="hidden" name="Step" value="3">
                <input type="hidden" name="Action" value="ContinueAfterDatabase">
                <input type="hidden" name="CSRFToken" value="} . _Escape( $State->{csrf_token} ) . qq{">
                <div class="qisutu-install-actions"><button class="primary" type="submit">Weiter zu den Systemeinstellungen</button></div>
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
        <p>Der Datenbank-Administrator wird nur für die Einrichtung verwendet. Sein Passwort wird nicht gespeichert.</p>
        <form method="post" action="install.pl" autocomplete="off">
            <input type="hidden" name="Step" value="3">
            <input type="hidden" name="Action" value="InstallDatabase">
            <input type="hidden" name="CSRFToken" value="} . _Escape( $State->{csrf_token} ) . qq{">
            <div class="qisutu-install-grid">
                } . _Field( 'Datenbankserver', 'DBHost', $Host, 'text', 1 ) .
                _Field( 'Port', 'DBPort', $Port, 'number', 1 ) .
                _Field( 'Datenbankname', 'DBName', $Name, 'text', 1, 'readonly' ) .
                _Field( 'Datenbankbenutzer für Qisutu', 'DBUser', $User, 'text', 1, 'readonly' ) .
                _Field( 'Datenbank-Administrator', 'DBAdminUser', $AdminUser, 'text', 1 ) .
                _Field( 'Passwort des Datenbank-Administrators', 'DBAdminPassword', '', 'password', 0 ) . qq{
            </div>
            } . ( -r $BootstrapFile ? '<label class="qisutu-install-check"><input type="checkbox" name="UseBootstrap" value="1" checked> Automatisch vorbereitete lokale Datenbankberechtigung verwenden. Die Administratorfelder oben werden dabei nicht gespeichert.</label>' : '' ) . qq{
            <div class="qisutu-install-note">Eine vorhandene Datenbank wird nur akzeptiert, wenn sie vollständig leer ist. Bestehende Tabellen werden nicht überschrieben.</div>
            <div class="qisutu-install-actions"><button class="primary" type="submit">Datenbank erstellen und befüllen</button></div>
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
                <div class="qisutu-install-field"><label for="HTTPType">Protokoll</label><select id="HTTPType" name="HTTPType"><option value="http"} . ( $HTTP eq 'http' ? ' selected' : '' ) . qq{>HTTP</option><option value="https"} . ( $HTTP eq 'https' ? ' selected' : '' ) . qq{>HTTPS</option></select></div>
                } . _Field( 'FQDN / Servername', 'FQDN', $FQDN, 'text', 1 ) .
                _Field( 'Webpfad', 'WebPath', $WebPath, 'text', 1, 'readonly' ) .
                _Field( 'Administrator-E-Mail-Adresse', 'AdminEmail', $Email, 'email', 1 ) . qq{
                <div class="qisutu-install-field"><label for="DefaultLanguage">Standardsprache</label><select id="DefaultLanguage" name="DefaultLanguage">} . _LanguageOptions($Language) . qq{</select></div>
                } . _Field( 'Zeitzone', 'Timezone', $Timezone, 'text', 1 ) .
                _Field( 'Ticket-Hook', 'TicketHook', $TicketHook, 'text', 1 ) .
                _Field( 'Maximale Anhangsgröße in MB', 'AttachmentMaxSize', $Attachment, 'number', 1 ) . qq{
            </div>
            <div class="qisutu-install-actions"><button class="primary" type="submit">Systemeinstellungen speichern</button></div>
        </form>
    };
}

sub _MailHTML {
    my (%Param) = @_;
    my $State = $Param{State};
    my $Request = $Param{Request} || {};

    return _ErrorHTML( $Param{Error} ) . qq{
        <p>Die E-Mail-Konfiguration ist optional. Der Aufbau ist bereits für weitere Verbindungstypen vorbereitet; derzeit stehen IMAP und SMTP zur Verfügung.</p>
        <form method="post" action="install.pl" autocomplete="off">
            <input type="hidden" name="Step" value="5">
            <input type="hidden" name="Action" value="SaveMail">
            <input type="hidden" name="CSRFToken" value="} . _Escape( $State->{csrf_token} ) . qq{">
            <section class="qisutu-install-mail-section">
                <label class="qisutu-install-check"><input type="checkbox" name="IMAPEnabled" value="1"} . ( $Request->{IMAPEnabled} ? ' checked' : '' ) . qq{> Eingehende E-Mails über IMAP einrichten</label>
                <div class="qisutu-install-grid">
                    } . _SelectField( 'Verbindungstyp', 'InboundConnectionType', 'imap', [ [ imap => 'IMAP' ] ] ) .
                    _Field( 'Bezeichnung', 'IMAPName', $Request->{IMAPName} || 'Standard IMAP', 'text', 0 ) .
                    _Field( 'E-Mail-Adresse', 'IMAPEmail', $Request->{IMAPEmail} || '', 'email', 0 ) .
                    _Field( 'IMAP-Server', 'IMAPHost', $Request->{IMAPHost} || '', 'text', 0 ) .
                    _Field( 'Port', 'IMAPPort', $Request->{IMAPPort} || '993', 'number', 0 ) .
                    _SelectField( 'Verschlüsselung', 'IMAPSecurity', $Request->{IMAPSecurity} || 'imaps', [ [ imap => 'Keine / IMAP' ], [ imap_starttls => 'STARTTLS' ], [ imaps => 'SSL/TLS' ] ] ) .
                    _Field( 'Benutzername', 'IMAPUsername', $Request->{IMAPUsername} || '', 'text', 0 ) .
                    _Field( 'Passwort', 'IMAPPassword', '', 'password', 0 ) .
                    _Field( 'Ziel-Queue', 'IMAPQueue', 'Posteingang', 'text', 0, 'readonly' ) . qq{
                </div>
            </section>
            <section class="qisutu-install-mail-section">
                <label class="qisutu-install-check"><input type="checkbox" name="SMTPEnabled" value="1"} . ( $Request->{SMTPEnabled} ? ' checked' : '' ) . qq{> Ausgehende E-Mails über SMTP einrichten</label>
                <div class="qisutu-install-grid">
                    } . _SelectField( 'Verbindungstyp', 'OutboundConnectionType', 'smtp', [ [ smtp => 'SMTP' ] ] ) .
                    _Field( 'Bezeichnung', 'SMTPName', $Request->{SMTPName} || 'Standard SMTP', 'text', 0 ) .
                    _Field( 'Absenderadresse', 'SMTPEmail', $Request->{SMTPEmail} || $State->{admin_email} || '', 'email', 0 ) .
                    _Field( 'SMTP-Server', 'SMTPHost', $Request->{SMTPHost} || '', 'text', 0 ) .
                    _Field( 'Port', 'SMTPPort', $Request->{SMTPPort} || '587', 'number', 0 ) .
                    _SelectField( 'Verschlüsselung', 'SMTPSecurity', $Request->{SMTPSecurity} || 'smtp_starttls', [ [ smtp => 'Keine / SMTP' ], [ smtp_starttls => 'STARTTLS' ], [ smtps => 'SSL/TLS' ] ] ) .
                    _Field( 'Benutzername', 'SMTPUsername', $Request->{SMTPUsername} || '', 'text', 0 ) .
                    _Field( 'Passwort', 'SMTPPassword', '', 'password', 0 ) . qq{
                </div>
            </section>
            <div class="qisutu-install-actions"><button class="secondary" type="submit" name="Action" value="SkipMail" formnovalidate>E-Mail-Konfiguration überspringen</button><button class="primary" type="submit">Verbindungen testen und speichern</button></div>
        </form>
    };
}

sub _FinalHTML {
    my (%Param) = @_;
    my $State = $Param{State};
    my $LoginURL = $State->{login_url} || "$WebPath/index.pl";

    return _ErrorHTML( $Param{Error} ) . qq{
        <div class="qisutu-install-success"><strong>Qisutu wurde erfolgreich installiert.</strong></div>
        <p>Bitte schreibe dir die folgenden Zugangsdaten auf. Das Administratorpasswort wird nach dem Verlassen dieser Seite nicht erneut angezeigt.</p>
        <div class="qisutu-install-credentials">
            <div><span>Login-Adresse</span><strong><a href="} . _Escape($LoginURL) . qq{">} . _Escape($LoginURL) . qq{</a></strong></div>
            <div><span>Benutzername</span><strong>admin</strong></div>
            <div><span>Administratorpasswort</span><strong class="credential">} . _Escape( $State->{admin_password} || '' ) . qq{</strong></div>
            <div><span>Datenbankname</span><strong>} . _Escape( $State->{db_name} || '' ) . qq{</strong></div>
            <div><span>Datenbankbenutzer</span><strong>} . _Escape( $State->{db_user} || '' ) . qq{</strong></div>
            <div><span>Datenbankpasswort</span><strong class="credential">} . _Escape( $State->{db_password} || '' ) . qq{</strong></div>
        </div>
        <form method="post" action="install.pl">
            <input type="hidden" name="Step" value="6">
            <input type="hidden" name="Action" value="Finish">
            <input type="hidden" name="CSRFToken" value="} . _Escape( $State->{csrf_token} ) . qq{">
            <div class="qisutu-install-actions"><button class="primary" type="submit">Zugangsdaten notiert – zum Qisutu Login</button></div>
        </form>
    };
}

sub _InstalledHTML {
    my $BaseURL = _ConfigBaseURLRead() || "$WebPath/index.pl";
    $BaseURL .= '/index.pl' if $BaseURL !~ m{index\.pl\z};
    return qq{
        <div class="qisutu-install-success"><strong>Qisutu wurde bereits installiert.</strong></div>
        <p>Eine erneute Installation ist aus Sicherheitsgründen gesperrt.</p>
        <div class="qisutu-install-actions"><a class="button primary" href="} . _Escape($BaseURL) . qq{">Zum Qisutu Login</a></div>
    };
}

sub _DatabaseInstall {
    my (%Param) = @_;
    my $Request = $Param{Request};
    my $State   = $Param{State};

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
            return { success => 0, error => 'Die automatische lokale Datenbankberechtigung kann nur für localhost verwendet werden.' }
                if $Host !~ m{\A(?:localhost|127\.0\.0\.1|::1)\z}i;
            $AdminUser = $Bootstrap->{user};
            $AdminPass = $Bootstrap->{password};
            $UsingBootstrap = 1;
        }
    }

    return { success => 0, error => 'Datenbankserver, Datenbankname und Datenbank-Administrator sind Pflichtfelder.' }
        if !$Host || !$DBName || !$AdminUser;
    return { success => 0, error => 'Der Datenbankport ist ungültig.' } if $Port !~ m{\A\d+\z} || $Port < 1 || $Port > 65535;
    return { success => 0, error => 'Der Datenbankname darf nur Buchstaben, Zahlen und Unterstriche enthalten.' } if $DBName !~ m{\A[A-Za-z0-9_]+\z};
    return { success => 0, error => 'Die Datenbank-Schemadatei fehlt.' } if !-r $SchemaFile;

    my $DBILoaded = eval { require DBI; require DBD::mysql; 1 };
    return { success => 0, error => 'DBI oder DBD::mysql ist nicht installiert. Bitte zuerst install.sh als root ausführen.' } if !$DBILoaded;

    my $AdminDSN = "DBI:mysql:host=$Host;port=$Port;mysql_enable_utf8mb4=1";
    my $AdminDBH = DBI->connect( $AdminDSN, $AdminUser, $AdminPass, { RaiseError => 0, PrintError => 0, AutoCommit => 1, mysql_enable_utf8mb4 => 1 } );
    return { success => 0, error => 'Die Verbindung als Datenbank-Administrator ist fehlgeschlagen: ' . ( $DBI::errstr || 'unbekannter Fehler' ) } if !$AdminDBH;

    my ($Exists) = $AdminDBH->selectrow_array( 'SELECT COUNT(*) FROM information_schema.SCHEMATA WHERE SCHEMA_NAME = ?', undef, $DBName );
    my $Existed = $Exists ? 1 : 0;
    my $TableCount = 0;
    if ($Existed) {
        ($TableCount) = $AdminDBH->selectrow_array( 'SELECT COUNT(*) FROM information_schema.TABLES WHERE TABLE_SCHEMA = ?', undef, $DBName );
        if ($TableCount) {
            $AdminDBH->disconnect();
            return { success => 0, error => "Die Datenbank $DBName enthält bereits Tabellen und wird nicht überschrieben." };
        }
    }

    my $DBPassword = _RandomPassword(32);
    my $AdminPassword = _RandomPassword(24);
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
        my $Message = $AdminDBH->errstr || 'Der vorhandene Datenbankbenutzer konnte nicht geprüft werden.';
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
        my $Message = $@ || $AdminDBH->errstr || 'Datenbank oder Benutzer konnten nicht angelegt werden';
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

    my $Import = _SchemaImport( Host => $Host, Port => $Port, DBName => $DBName, DBUser => $DBUser, DBPassword => $DBPassword );
    if ( !$Import->{success} ) {
        _DatabaseCleanup( DBH => $AdminDBH, DBName => $DBName, Existed => $Existed, DBUser => $DBUser, GrantHost => $GrantHost, DropUser => $UserCreated );
        $AdminDBH->disconnect();
        return { success => 0, error => 'Das Datenbankschema konnte nicht importiert werden: ' . $Import->{error} };
    }

    my $AppDSN = "DBI:mysql:database=$DBName;host=$Host;port=$Port;mysql_enable_utf8mb4=1";
    my $DBH = DBI->connect( $AppDSN, $DBUser, $DBPassword, { RaiseError => 0, PrintError => 0, AutoCommit => 1, mysql_enable_utf8mb4 => 1 } );
    if ( !$DBH ) {
        _DatabaseCleanup( DBH => $AdminDBH, DBName => $DBName, Existed => $Existed, DBUser => $DBUser, GrantHost => $GrantHost, DropUser => $UserCreated );
        $AdminDBH->disconnect();
        return { success => 0, error => 'Die Verbindung mit dem neuen Qisutu-Datenbankbenutzer ist fehlgeschlagen: ' . ( $DBI::errstr || '' ) };
    }

    my $Insert = _InitialDataInsert( DBH => $DBH, AdminPassword => $AdminPassword );
    if ( !$Insert->{success} ) {
        $DBH->disconnect();
        _DatabaseCleanup( DBH => $AdminDBH, DBName => $DBName, Existed => $Existed, DBUser => $DBUser, GrantHost => $GrantHost, DropUser => $UserCreated );
        $AdminDBH->disconnect();
        return { success => 0, error => 'Die Grunddaten konnten nicht angelegt werden: ' . $Insert->{error} };
    }

    $DBH->disconnect();

    $State->{db_host}       = $Host;
    $State->{db_port}       = 0 + $Port;
    $State->{db_name}       = $DBName;
    $State->{db_user}       = $DBUser;
    $State->{db_password}   = $DBPassword;
    $State->{admin_password}= $AdminPassword;
    $State->{database_done} = 1;
    $State->{default_language} = 'de';
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

sub _InitialDataInsert {
    my (%Param) = @_;
    my $DBH = $Param{DBH};
    my $AdminPassword = $Param{AdminPassword};
    my $Hash = _PasswordHash($AdminPassword);
    return { success => 0, error => 'Das Administratorpasswort konnte nicht sicher gehasht werden.' } if !$Hash;

    my $OK = eval {
        $DBH->begin_work();
        $DBH->do('INSERT INTO user_account (id, login, account_type, email, password_hash, firstname, lastname, is_active, is_system_user, password_changed_at) VALUES (1, ?, ?, ?, ?, ?, ?, 1, 0, NOW())', undef, 'admin', 'agent', 'admin@localhost.invalid', $Hash, 'Qisutu', 'Administrator') or die $DBH->errstr;
        $DBH->do('INSERT INTO user_group (id, name, title, group_type, active, sort_order, created_by_user_id, changed_by_user_id) VALUES (1, ?, ?, ?, 1, 100, 1, 1)', undef, 'admin', 'Administrators', 'agent') or die $DBH->errstr;
        $DBH->do('INSERT INTO user_group_member (user_group_id, user_account_id, role_name, active, created_by_user_id, changed_by_user_id, permission_read, permission_create, permission_change, permission_overview, permission_full) VALUES (1, 1, ?, 1, 1, 1, 1, 1, 1, 1, 1)', undef, 'admin') or die $DBH->errstr;
        $DBH->do('INSERT INTO user_group_permission (user_group_id, permission_key, active, created_by_user_id, changed_by_user_id) VALUES (1, ?, 1, 1, 1)', undef, 'admin.view') or die $DBH->errstr;

        my @Queues = ( [ 1, 'Posteingang', 100 ], [ 2, 'Junk', 200 ], [ 3, 'Spam', 300 ] );
        for my $Queue (@Queues) {
            $DBH->do('INSERT INTO ticket_queue (id, name, full_name, follow_up_allowed, active, sort_order, created_by_user_id, changed_by_user_id) VALUES (?, ?, ?, 1, 1, ?, 1, 1)', undef, $Queue->[0], $Queue->[1], $Queue->[1], $Queue->[2]) or die $DBH->errstr;
            $DBH->do('INSERT INTO ticket_queue_group (queue_id, user_group_id, permission_key, active, created_by_user_id, changed_by_user_id) VALUES (?, 1, ?, 1, 1, 1)', undef, $Queue->[0], 'ticket.full') or die $DBH->errstr;
        }

        my @States = (
            [ 1, 'new',                     'new',     0, 100 ],
            [ 2, 'open',                    'open',    0, 200 ],
            [ 3, 'closed successful',       'closed',  0, 300 ],
            [ 4, 'closed unsuccessful',     'closed',  0, 400 ],
            [ 5, 'pending reminder',        'pending', 0, 500 ],
            [ 6, 'merged',                  'closed',  0, 600 ],
            [ 7, 'pending auto close+',     'pending', 0, 700 ],
            [ 8, 'pending auto close-',     'pending', 0, 800 ],
        );
        for my $State (@States) {
            $DBH->do('INSERT INTO ticket_state (id, name, state_type, sla_pause, active, sort_order, created_by_user_id, changed_by_user_id) VALUES (?, ?, ?, ?, 1, ?, 1, 1)', undef, @{$State}) or die $DBH->errstr;
        }

        my @Priorities = (
            [ 1, '1 very low', 1, 100 ], [ 2, '2 low', 2, 200 ], [ 3, '3 normal', 3, 300 ],
            [ 4, '4 high', 4, 400 ], [ 5, '5 very high', 5, 500 ],
        );
        for my $Priority (@Priorities) {
            $DBH->do('INSERT INTO ticket_priority (id, name, priority_value, active, sort_order, created_by_user_id, changed_by_user_id) VALUES (?, ?, ?, 1, ?, 1, 1)', undef, @{$Priority}) or die $DBH->errstr;
        }

        my $TicketNumber = strftime( '%Y%m%d', localtime ) . '0001';
        my $WelcomeBody = '<p>Willkommen bei Qisutu.</p><p>Die Installation wurde erfolgreich abgeschlossen. Als Nächstes kannst du Queues, Benutzer, E-Mail-Konten, Services, SLAs und weitere Systemeinstellungen einrichten.</p><p>Wir wünschen dir viel Erfolg mit Qisutu.</p>';
        $DBH->do('INSERT INTO ticket (id, ticket_number, title, queue_id, state_id, priority_id, owner_user_id, responsible_user_id, created_by_user_id, changed_by_user_id, last_agent_article_at) VALUES (1, ?, ?, 1, 1, 3, 1, 1, 1, 1, NOW())', undef, $TicketNumber, 'Willkommen bei Qisutu') or die $DBH->errstr;
        $DBH->do('INSERT INTO ticket_article (ticket_id, article_number, channel, sender_type, from_name, from_email, subject, body, search_text, content_type, visibility, internal, created_by_user_id, changed_by_user_id, created_at, changed_at) VALUES (1, 1, ?, ?, ?, ?, ?, ?, ?, ?, ?, 1, 1, 1, NOW(), NOW())', undef, 'note', 'agent', 'Qisutu', 'support@qisutu.de', 'Willkommen bei Qisutu', $WelcomeBody, 'Willkommen bei Qisutu Installation erfolgreich', 'text/html', 'agent') or die $DBH->errstr;

        $DBH->commit();
        1;
    };

    if ( !$OK ) {
        my $Error = $@ || $DBH->errstr || 'unbekannter Fehler';
        eval { $DBH->rollback() };
        return { success => 0, error => $Error };
    }

    return { success => 1 };
}

sub _SystemSettingsSave {
    my (%Param) = @_;
    my $Request = $Param{Request};
    my $State   = $Param{State};
    return { success => 0, error => 'Die Datenbank muss zuerst eingerichtet werden.' } if !$State->{database_done};

    my $HTTP = $Request->{HTTPType} || '';
    my $FQDN = _Trim( $Request->{FQDN} );
    my $Email = lc _Trim( $Request->{AdminEmail} );
    my $Language = $Request->{DefaultLanguage} || '';
    my $Timezone = _Trim( $Request->{Timezone} );
    my $TicketHook = _Trim( $Request->{TicketHook} );
    my $Attachment = _Trim( $Request->{AttachmentMaxSize} );

    return { success => 0, error => 'Das Protokoll ist ungültig.' } if $HTTP ne 'http' && $HTTP ne 'https';
    return { success => 0, error => 'Der FQDN oder Servername ist ungültig.' } if !$FQDN || $FQDN !~ m{\A[A-Za-z0-9.\-:\[\]]+\z};
    return { success => 0, error => 'Die Administrator-E-Mail-Adresse ist ungültig.' } if $Email !~ m{\A[^\s\@]+\@[^\s\@]+\.[^\s\@]+\z};
    return { success => 0, error => 'Die Standardsprache ist ungültig.' } if $Language !~ m{\A(?:de|en|fr|it)\z};
    return { success => 0, error => 'Die Zeitzone ist ungültig.' } if !$Timezone || $Timezone !~ m{\A[A-Za-z0-9_+\-/]+\z};
    return { success => 0, error => 'Der Ticket-Hook ist ungültig.' } if !$TicketHook || length($TicketHook) > 50;
    return { success => 0, error => 'Die maximale Anhangsgröße muss zwischen 1 und 10240 MB liegen.' } if $Attachment !~ m{\A\d+\z} || $Attachment < 1 || $Attachment > 10240;

    $State->{http_type} = $HTTP;
    $State->{fqdn} = $FQDN;
    $State->{admin_email} = $Email;
    $State->{default_language} = $Language;
    $State->{timezone} = $Timezone;
    $State->{ticket_hook} = $TicketHook;
    $State->{attachment_max_size} = 0 + $Attachment;
    $State->{base_url} = "$HTTP://$FQDN$WebPath";
    $State->{login_url} = $State->{base_url} . '/index.pl';

    my $DBH = _ApplicationDBConnect($State);
    return { success => 0, error => 'Die Qisutu-Datenbankverbindung ist fehlgeschlagen: ' . ( $DBI::errstr || '' ) } if !$DBH;

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
        my $Message = $@ || $DBH->errstr || 'unbekannter Fehler';
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
    return { success => 0, error => 'Die Systemeinstellungen müssen zuerst gespeichert werden.' } if !$State->{system_done};

    my $IMAPEnabled = $Request->{IMAPEnabled} ? 1 : 0;
    my $SMTPEnabled = $Request->{SMTPEnabled} ? 1 : 0;
    return { success => 0, error => 'Aktiviere mindestens IMAP oder SMTP oder überspringe die E-Mail-Konfiguration.' } if !$IMAPEnabled && !$SMTPEnabled;

    my %AllowedSecurity = map { $_ => 1 } qw(imap imap_starttls imaps smtp smtp_starttls smtps);
    my $DBH = _ApplicationDBConnect($State);
    return { success => 0, error => 'Die Datenbankverbindung ist fehlgeschlagen.' } if !$DBH;

    my @TestMessages;
    my ($IMAP, $SMTP);

    if ($IMAPEnabled) {
        $IMAP = {
            name       => _Trim( $Request->{IMAPName} ) || 'Standard IMAP',
            email      => lc _Trim( $Request->{IMAPEmail} ),
            host       => _Trim( $Request->{IMAPHost} ),
            port       => _Trim( $Request->{IMAPPort} ),
            security   => $Request->{IMAPSecurity} || '',
            username   => _Trim( $Request->{IMAPUsername} ),
            password   => defined $Request->{IMAPPassword} ? $Request->{IMAPPassword} : '',
        };
        if ( !$IMAP->{email} || !$IMAP->{host} || !$IMAP->{username} || !$IMAP->{password} || $IMAP->{port} !~ m{\A\d+\z} || !$AllowedSecurity{ $IMAP->{security} } ) {
            $DBH->disconnect();
            return { success => 0, error => 'Bitte fülle alle aktivierten IMAP-Felder vollständig und gültig aus.' };
        }
        my $Test = _MailConnectionTest( Type => 'imap', Data => $IMAP, State => $State );
        if ( !$Test->{success} ) {
            $DBH->disconnect();
            return { success => 0, error => 'Die IMAP-Verbindung ist fehlgeschlagen: ' . $Test->{message} };
        }
        push @TestMessages, $Test->{message};
    }

    if ($SMTPEnabled) {
        $SMTP = {
            name       => _Trim( $Request->{SMTPName} ) || 'Standard SMTP',
            email      => lc _Trim( $Request->{SMTPEmail} ),
            host       => _Trim( $Request->{SMTPHost} ),
            port       => _Trim( $Request->{SMTPPort} ),
            security   => $Request->{SMTPSecurity} || '',
            username   => _Trim( $Request->{SMTPUsername} ),
            password   => defined $Request->{SMTPPassword} ? $Request->{SMTPPassword} : '',
        };
        if ( !$SMTP->{email} || !$SMTP->{host} || !$SMTP->{username} || !$SMTP->{password} || $SMTP->{port} !~ m{\A\d+\z} || !$AllowedSecurity{ $SMTP->{security} } ) {
            $DBH->disconnect();
            return { success => 0, error => 'Bitte fülle alle aktivierten SMTP-Felder vollständig und gültig aus.' };
        }
        my $Test = _MailConnectionTest( Type => 'smtp', Data => $SMTP, State => $State );
        if ( !$Test->{success} ) {
            $DBH->disconnect();
            return { success => 0, error => 'Die SMTP-Verbindung ist fehlgeschlagen: ' . $Test->{message} };
        }
        push @TestMessages, $Test->{message};
    }

    my $OK = eval {
        $DBH->begin_work();
        if ($IMAPEnabled) {
            $DBH->do('INSERT INTO postmaster_imap_account (name, email, queue_id, imap_host, imap_security, imap_port, imap_auth_type, imap_username, imap_password, active, sort_order, last_check_at, last_check_status, last_check_message, created_by_user_id, changed_by_user_id) VALUES (?, ?, 1, ?, ?, ?, ?, ?, ?, 1, 100, NOW(), ?, ?, 1, 1)', undef, $IMAP->{name}, $IMAP->{email}, $IMAP->{host}, $IMAP->{security}, $IMAP->{port}, 'password', $IMAP->{username}, $IMAP->{password}, 'ok', 'IMAP connection successful') or die $DBH->errstr;
        }
        if ($SMTPEnabled) {
            $DBH->do('INSERT INTO smtp_account (name, smtp_host, smtp_security, smtp_port, smtp_auth_type, smtp_username, smtp_password, active, sort_order, last_check_at, last_check_status, last_check_message, created_by_user_id, changed_by_user_id) VALUES (?, ?, ?, ?, ?, ?, ?, 1, 100, NOW(), ?, ?, 1, 1)', undef, $SMTP->{name}, $SMTP->{host}, $SMTP->{security}, $SMTP->{port}, 'password', $SMTP->{username}, $SMTP->{password}, 'ok', 'SMTP connection successful') or die $DBH->errstr;
        }
        my $SystemEmail = $SMTPEnabled ? $SMTP->{email} : $IMAP->{email};
        $DBH->do('INSERT INTO system_email (name, email, active, sort_order, created_by_user_id, changed_by_user_id) VALUES (?, ?, 1, 100, 1, 1)', undef, 'Qisutu System Email', $SystemEmail) or die $DBH->errstr;
        my $SystemEmailID = $DBH->{mysql_insertid};
        $DBH->do('UPDATE ticket_queue SET system_email_id = ?, changed_by_user_id = 1 WHERE id = 1', undef, $SystemEmailID) or die $DBH->errstr;
        $DBH->commit();
        1;
    };

    if ( !$OK ) {
        my $Message = $@ || $DBH->errstr || 'unbekannter Fehler';
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

    unshift @INC,
        File::Spec->catdir( $RootPath, 'core', 'config' ),
        File::Spec->catdir( $RootPath, 'core', 'system' );

    my $Loaded = eval { require QisutuMail; 1 };
    return { success => 0, message => "QisutuMail konnte nicht geladen werden: $@" } if !$Loaded;

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
        message => _MailMessage( $Result ? $Result->{Message} : 'Verbindungstest fehlgeschlagen' ),
    };
}

sub _MailMessage {
    my ($Message) = @_;
    my %Map = (
        'Translate:AdminSMTPConnectionOK' => 'SMTP-Verbindung erfolgreich',
        'Translate:AdminIMAPConnectionOK' => 'IMAP-Verbindung erfolgreich',
        'Translate:AdminSMTPConnectionFailed' => 'Verbindung zum SMTP-Server nicht möglich',
        'Translate:AdminIMAPConnectionFailed' => 'Verbindung zum IMAP-Server nicht möglich',
        'Translate:AdminSMTPAuthFailed' => 'SMTP-Anmeldung fehlgeschlagen',
        'Translate:AdminIMAPAuthFailed' => 'IMAP-Anmeldung fehlgeschlagen',
        'Translate:AdminSMTPSSLRequired' => 'IO::Socket::SSL fehlt für SMTP',
        'Translate:AdminIMAPSSLRequired' => 'IO::Socket::SSL fehlt für IMAP',
    );
    return $Map{$Message} || $Message || 'Verbindungstest fehlgeschlagen';
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
    return { success => 0, error => 'Temporäre Datenbankberechtigung ist ungültig.' }
        if !$Bootstrap || !$Bootstrap->{user} || !$DBH;

    my $Account = $DBH->quote( $Bootstrap->{user} ) . '@' . $DBH->quote('localhost');
    my $Result = eval { $DBH->do("DROP USER IF EXISTS $Account") };
    if ( !$Result ) {
        return {
            success => 0,
            error   => 'Der temporäre Datenbankbenutzer ' . $Bootstrap->{user} . ' konnte nicht automatisch entfernt werden: '
                . ( $DBH->errstr || $@ || 'unbekannter Fehler' ),
        };
    }

    unlink $BootstrapFile;
    return { success => 1 };
}

sub _SchemaImport {
    my (%Param) = @_;
    my $ErrorHandle = gensym;
    local $ENV{MYSQL_PWD} = $Param{DBPassword};
    my $DatabaseCLI = _DatabaseCLI();
    return { success => 0, error => 'Weder mariadb noch mysql wurde gefunden.' } if !$DatabaseCLI;

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
    return { success => 0, error => "mysql konnte nicht gestartet werden: $@" } if !$PID;

    open my $SchemaHandle, '<:raw', $SchemaFile or return { success => 0, error => "Schemadatei kann nicht gelesen werden: $!" };
    while ( read( $SchemaHandle, my $Buffer, 65536 ) ) {
        print {$In} $Buffer;
    }
    close $SchemaHandle;
    close $In;
    local $/;
    my $Stdout = <$Out> // '';
    my $Stderr = <$ErrorHandle> // '';
    close $Out;
    close $ErrorHandle;
    waitpid( $PID, 0 );
    my $Exit = $? >> 8;

    $Stderr =~ s{\Q$Param{DBPassword}\E}{[PASSWORT ENTFERNT]}g if $Param{DBPassword};
    return { success => 0, error => _Trim($Stderr) || "mysql wurde mit Status $Exit beendet" } if $Exit != 0;
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
        return { success => 0, error => "QisutuConfig.pm kann nicht geschrieben werden: $!" };
    }
    print {$FH} $Config;
    close $FH or return { success => 0, error => "QisutuConfig.pm konnte nicht vollständig gespeichert werden: $!" };
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
            Module        => "\$RootPath/core/module",
            Output        => "\$RootPath/core/output",
            System        => "\$RootPath/core/system",
            Language      => "\$RootPath/core/language",
            Var           => "\$RootPath/var",
            Log           => "\$RootPath/var/log",
            Cache         => "\$RootPath/var/cache",
            Static        => "\$RootPath/var/static",
            StaticURL     => '$WebPath/static',
        },

        System => {
            Name       => 'Qisutu',
            Version    => '0.0.8',
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
        Paths => { Var => "$RootPath/var", Log => "$RootPath/var/log", Static => "$RootPath/var/static", StaticURL => "$WebPath/static" },
        System => { Name => 'Qisutu', InstanceID => $InstanceID, WebPath => $WebPath, BaseURL => $State->{base_url} || '', TicketHook => $State->{ticket_hook} || 'Qisutu' },
    };
}

sub _SystemChecks {
    my @Checks;
    push @Checks, { name => 'Perl', ok => $] >= 5.026 ? 1 : 0, critical => 1, detail => sprintf( 'Version %.3f', $] ) };
    push @Checks, _ModuleCheck( 'DBI', 1 );
    push @Checks, _ModuleCheck( 'DBD::mysql', 1 );
    push @Checks, _ModuleCheck( 'IO::Socket::SSL', 1 );
    push @Checks, _ModuleCheck( 'Authen::SASL', 1 );
    push @Checks, _ModuleCheck( 'MIME::Base64', 1 );
    push @Checks, _ModuleCheck( 'MIME::QuotedPrint', 1 );
    push @Checks, _ModuleCheck( 'Net::SMTP', 1 );
    my $DatabaseCLI = _DatabaseCLI();
    push @Checks, { name => 'MariaDB/MySQL Client', ok => $DatabaseCLI ? 1 : 0, critical => 1, detail => $DatabaseCLI ? $DatabaseCLI : 'nicht gefunden' };
    push @Checks, { name => 'Apache CGI', ok => $ENV{GATEWAY_INTERFACE} ? 1 : 0, critical => 1, detail => $ENV{GATEWAY_INTERFACE} || 'nicht über CGI aufgerufen' };
    push @Checks, { name => 'Datenbankschema', ok => -r $SchemaFile ? 1 : 0, critical => 1, detail => -r $SchemaFile ? 'lesbar' : 'fehlt' };
    push @Checks, { name => 'QisutuConfig.pm', ok => -w $ConfigFile ? 1 : 0, critical => 1, detail => -w $ConfigFile ? 'beschreibbar' : 'nicht beschreibbar' };
    push @Checks, { name => 'Installationsverzeichnis', ok => -w $InstallPath ? 1 : 0, critical => 1, detail => -w $InstallPath ? 'beschreibbar' : 'nicht beschreibbar' };
    my $Crypt = crypt( 'test', '$6$abcdefghijklmnop$' ) || '';
    push @Checks, { name => 'SHA-512 Passwort-Hash', ok => $Crypt =~ m{\A\$6\$} ? 1 : 0, critical => 1, detail => $Crypt =~ m{\A\$6\$} ? 'verfügbar' : 'nicht verfügbar' };
    return \@Checks;
}

sub _ModuleCheck {
    my ( $Module, $Critical ) = @_;
    my $OK = eval "require $Module; 1;" ? 1 : 0;
    return { name => "Perl-Modul $Module", ok => $OK, critical => $Critical, detail => $OK ? 'vorhanden' : 'nicht installiert' };
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
    my @Chars = ( 'a' .. 'z', 'A' .. 'Z', 0 .. 9, '!', '@', '#', '%', '_', '-', '+', '=' );
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
    my $State = { csrf_token => _RandomToken(), created_at => time, remote_addr => $ENV{REMOTE_ADDR} || '' };
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
    my @Labels = ( 'Willkommen', 'Lizenz', 'Datenbank', 'System', 'E-Mail', 'Abschluss' );
    my $Progress = '';
    for my $Index ( 1 .. 6 ) {
        my $Class = $Index < $Step ? 'done' : $Index == $Step ? 'active' : '';
        $Progress .= '<div class="' . $Class . '"><span>' . $Index . '</span><small>' . $Labels[ $Index - 1 ] . '</small></div>';
    }

    return '<!doctype html><html lang="de"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width, initial-scale=1"><meta name="robots" content="noindex,nofollow"><title>'
        . _Escape( $Param{Title} ) . ' - Qisutu Installation</title><link rel="stylesheet" href="' . $WebPath . '/static/css/qisutu-install.css?v=20260714"></head><body>'
        . '<div class="qisutu-install-shell"><header><div class="brand"><img src="' . $WebPath . '/static/img/logo.png" alt="Qisutu"><strong>Qisutu Installation</strong></div><div class="step-text">Schritt ' . $Step . ' von 6</div></header>'
        . '<nav class="qisutu-install-progress" aria-label="Installationsfortschritt">' . $Progress . '</nav>'
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

sub _LanguageOptions {
    my ($Selected) = @_;
    my @Options = ( [ de => 'Deutsch' ], [ en => 'English' ], [ fr => 'Français' ], [ it => 'Italiano' ] );
    return join '', map { '<option value="' . $_->[0] . '"' . ( $_->[0] eq $Selected ? ' selected' : '' ) . '>' . _Escape( $_->[1] ) . '</option>' } @Options;
}

sub _ErrorHTML {
    my ($Error) = @_;
    return '' if !$Error;
    return '<div class="qisutu-install-error"><strong>Fehler:</strong> ' . _Escape($Error) . '</div>';
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
