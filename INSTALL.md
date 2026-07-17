# Qisutu installieren

## Voraussetzungen

- ein unterstütztes Linux-System
- root-Zugriff für die Systemvorbereitung
- Netzwerkzugriff auf die Paketquellen des Betriebssystems
- ein Installationspfad ohne Leerzeichen

Empfohlene und vollständig unterstützte Referenzplattform ist Ubuntu Server
LTS. Zusätzlich besitzt der Installer eigene Installationswege für:

- Debian
- RHEL, Rocky Linux, AlmaLinux, CentOS und Fedora
- openSUSE und SLES

Andere Distributionen werden nicht stillschweigend wie Ubuntu behandelt. Das
Installationsskript bricht dort mit einer eindeutigen Meldung ab.

## 1. Archiv entpacken

Jede Qisutu-Instanz benötigt ein eigenes Hauptverzeichnis.

Beispiele:

    /opt/qisutu
    /opt/qisutu-test

Für ein Testsystem muss das entpackte Verzeichnis daher vor der Installation
beispielsweise `/opt/qisutu-test` heißen.

## 2. Systemvorbereitung starten

Im Hauptverzeichnis der betreffenden Instanz ausführen:

    sudo ./install.sh

### Normale Installation

Liegt Qisutu im empfohlenen Verzeichnis `/opt/qisutu`, nimmt das Skript alle
Instanzwerte automatisch. Es werden keine technischen Namen abgefragt.
Automatisch verwendet werden unter anderem:

    Webpfad:          /qisutu
    Apache-Datei:     qisutu.conf
    systemd-Dienst:   qisutu-daemon.service
    Session-Cookie:   QISUTU_SESSION
    Datenbank:        qisutu
    Datenbankbenutzer:qisutu

### Zusätzliche Test- oder Entwicklungsinstanz

Jede weitere Instanz wird in ein eigenes Verzeichnis entpackt, zum Beispiel:

    /opt/qisutu-test

Beim ersten Aufruf fragt `install.sh` ausschließlich nach einem kurzen,
verständlichen Namen:

    Name der zusätzlichen Instanz [test]:

Mit der Eingabetaste wird der Vorschlag übernommen. Alle technischen Namen
werden daraus automatisch erzeugt:

    Webpfad:          /qisutu-test
    Apache-Datei:     qisutu-test.conf
    systemd-Dienst:   qisutu-test-daemon.service
    Session-Cookie:   QISUTU_TEST_SESSION
    Datenbank:        qisutu_test
    Datenbankbenutzer:qisutu_test

Falsche technische Angaben wie Webpfad, Dienstname oder Cookie können dadurch
nicht mehr eingegeben werden. Der Name wird unmittelbar geprüft; bei einer
ungültigen Eingabe fragt das Skript erneut, statt die Installation am Ende
abzubrechen.

Die automatisch ermittelten Werte werden in `var/install/instance.conf`
gespeichert. Bei späteren Aufrufen von `install.sh` wird diese vorhandene
Instanzkonfiguration unverändert wiederverwendet und es erscheint keine neue
Abfrage.

Das Skript installiert Apache, MariaDB beziehungsweise MySQL-Clientwerkzeuge,
Perl und die benötigten Perl-Module einschließlich `Authen::SASL`. Nach der
Paketinstallation prüft es alle benötigten Mail- und Datenbankmodule.

Die Apache-Konfiguration wird distributionsabhängig eingebunden:

- Debian und Ubuntu: `sites-available/INSTANZ.conf` und Aktivierung über
  `sites-enabled/` mit `a2ensite`
- RHEL, Rocky Linux, AlmaLinux, CentOS und Fedora:
  `/etc/httpd/conf.d/INSTANZ.conf`
- openSUSE und SLES: `/etc/apache2/conf.d/INSTANZ.conf`

Jede Instanz erhält außerdem eigene systemd-Dateien. Dadurch können
beispielsweise folgende Dienste parallel laufen:

    qisutu-daemon.service
    qisutu-test-daemon.service

Auf Systemen der RHEL-Familie richtet das Skript bei aktivem SELinux die
notwendigen Dateikontexte und SELinux-Schalter für CGI-, Datenbank- und
Netzwerkverbindungen ein. Ist `firewalld` aktiv, wird HTTP freigegeben.

Auf lokalen MariaDB-Installationen erzeugt das Skript pro Instanz einen
temporären, zufällig gesicherten Datenbank-Installationsbenutzer. Der
Webinstaller entfernt ihn nach erfolgreicher Datenbankeinrichtung wieder.

## 3. Webinstaller ausführen

Die von `install.sh` ausgegebene Adresse im Browser öffnen.

Produktivbeispiel:

    http://SERVER/qisutu/install.pl

Testbeispiel:

    http://SERVER/qisutu-test/install.pl

Der Assistent führt durch:

1. Willkommen, Instanzdaten und Systemprüfung
2. Lizenzbestätigung
3. Datenbank und Grunddaten
4. Systemeinstellungen einschließlich Protokoll und FQDN
5. optionale IMAP-/SMTP-Konfiguration
6. Abschluss und erste Zugangsdaten

Datenbankname und Datenbankbenutzer stammen aus der zuvor festgelegten
Instanzkonfiguration und werden im Webinstaller nicht mehr eigenmächtig
geändert. Der Installer erzeugt zufällige Passwörter für den jeweiligen
Datenbankbenutzer und den ersten Benutzer `admin`. Das Datenbankpasswort wird
direkt in `core/config/QisutuConfig.pm` dieser Instanz gespeichert.

Die vollständige Tabellenstruktur wird aus `install/sql/schema.sql` importiert.
Alle festen Grunddaten der Neuinstallation stehen getrennt davon in
`install/sql/insert.sql`. Das zufällig erzeugte Administratorpasswort wird nach
dem Grunddatenimport sicher gehasht in das vorbereitete Administratorkonto
eingetragen.

## 4. Abschluss

Nach Abschluss wird innerhalb der betreffenden Instanz
`var/install/installed.lock` angelegt. Damit ist ausschließlich der Installer
dieser Instanz gesperrt. Der eigene systemd-Pfad aktiviert danach den zu dieser
Instanz gehörenden Qisutu-Daemon.

Beispielzugänge:

    http://SERVER/qisutu/index.pl
    http://SERVER/qisutu-test/index.pl

## Mehrere Instanzen auf demselben Server

Jede Instanz benötigt nur ein eigenes Hauptverzeichnis. Aus `/opt/qisutu`
und `/opt/qisutu-test` erzeugt das Installationsskript automatisch getrennte
Webpfade, Apache-Dateien, systemd-Dienste, Session-Cookies, Datenbanken und
Datenbankbenutzer. Diese internen Werte müssen nicht vom Benutzer eingegeben
werden.

E-Mail-Zugänge des Testsystems müssen von den produktiven Postfächern getrennt
bleiben. Die E-Mail-Konfiguration kann bei der Testinstallation übersprungen
werden.

## Protokolle

Jede Instanz besitzt ihr eigenes Installationsprotokoll:

    var/log/install.log

Passwörter werden nicht in das Installationsprotokoll geschrieben.

## Temporäre Abschlussdienste

Während der Webinstallation wartet eine instanzbezogene systemd-Path-Unit auf `var/install/installed.lock`. Nach erfolgreichem Abschluss startet die zugehörige einmalige Service-Unit den Qisutu-Daemon. Anschließend werden beide temporären Abschluss-Units automatisch deaktiviert und aus `/etc/systemd/system` entfernt. Dauerhaft aktiv bleibt ausschließlich der jeweilige Qisutu-Daemon.
## Updates einer vorhandenen Qisutu-Instanz

Vor jedem Update muss entsprechend der Betreiberanweisung eine vollständige
Systemsicherung der Qisutu-Installation und ihrer Datenbank vorhanden sein.
Qisutu erstellt keine zusätzliche Programmsicherung.

Ein neues Qisutu-Release wird in ein separates Verzeichnis entpackt. Das neue
Paket darf nicht direkt über die bestehende Installation entpackt werden.
Anschließend wird `update.sh` aus dem neuen Paket mit dem Pfad der zu
aktualisierenden Instanz aufgerufen.

Produktivinstanz aktualisieren:

    cd /tmp/qisutu-neue-version/qisutu
    sudo ./update.sh /opt/qisutu

Zusätzliche Instanz aktualisieren:

    cd /tmp/qisutu-neue-version/qisutu
    sudo ./update.sh /opt/qisutu-test

Das Updateprogramm liest die vorhandene `var/install/instance.conf` und zeigt
vor der Bestätigung Installationspfad, Instanzkennung, Webpfad, Datenbank und
systemd-Dienst an. Es aktualisiert ausschließlich die angegebene Instanz.

Während des Updates führt das Programm folgende Schritte aus:

1. Release-Prüfsummen, Versionen, Schemadatei, Perl-Syntax und
   Programmregistrierung prüfen.
2. Auf Wunsch einen zusätzlichen vollständigen Datenbankdump erstellen und auf
   den dafür erforderlichen freien Speicherplatz hinweisen.
3. Für genau diese Instanz den Wartungsmodus aktivieren, den Daemon stoppen,
   laufende Prozesse beenden lassen und neue Mailabrufe sperren.
4. Alle verwalteten Programmdateien direkt in die bestehende Installation
   kopieren. Vorhandene Dateien werden ersetzt, neue Dateien und Verzeichnisse
   werden angelegt und nicht mehr veröffentlichte verwaltete Dateien entfernt.
5. Instanz- und Betreiberdateien unverändert erhalten. Dazu gehören
   `core/config/QisutuConfig.pm` mit Ausnahme der Versionsnummer,
   `var/install/instance.conf`, Logs, Cache, temporäre Laufzeitdaten,
   instanzbezogene Runtime-Dateien, die bestehende Apache-Konfiguration und die
   bestehende systemd-Konfiguration.
6. Die aktuelle Datenbank-Sollstruktur aus `install/sql/schema.sql` mit der
   vorhandenen Datenbank vergleichen und fehlende Tabellen, Spalten, Indizes,
   Primärschlüssel und Fremdschlüssel ergänzen.
7. Alle dauerhaft mitgeführten und noch nicht protokollierten SQL- und
   Perl-Migrationen aus `install/update/database/` ausführen. Dadurch werden
   auch notwendige `INSERT`-, `UPDATE`- und Datenumwandlungsschritte unabhängig
   von der bisherigen Qisutu-Version nachgeholt.
8. Schema, Migrationsprotokoll, Datenbankstand, Programmdateien,
   Betreiberkonfigurationen, Apache und Daemon prüfen.
9. Wartungsmodus beenden und den zuvor laufenden Daemon wieder starten.

Der Updater baut keinen zweiten Qisutu-Programmbaum auf, verschiebt keine
Installationsverzeichnisse und legt keine automatische Programmsicherung an.
Bei einem Fehler nach begonnenen Datei- oder Datenbankänderungen bleibt die
Wartungssperre aktiv. Nach Behebung des gemeldeten Fehlers wird dasselbe Update
erneut ausgeführt.

Die vorhandenen Apache-Dateien und Symlinks unter `sites-available`,
`sites-enabled`, `conf-available` und `conf-enabled` sowie der vorhandene
systemd-Dienst unter `/etc/systemd/system` werden nicht neu erzeugt und nicht
überschrieben. Der Updater prüft ausdrücklich, dass ihr Inhalt und ihre
Dateieigenschaften unverändert geblieben sind.

Die aktuelle Tabellenstruktur wird bei jedem Update mit
`install/sql/schema.sql` abgeglichen. Zusätzliche bestehende Tabellen oder
Spalten werden nicht gelöscht. Abweichende vorhandene Definitionen werden aus
Sicherheitsgründen gemeldet und nicht automatisch destruktiv geändert.

Einmalige Datenänderungen wie `INSERT`, `UPDATE` oder Datenumwandlungen liegen
kumulativ unter:

    install/update/database/DATENBANKVERSION/

Alle veröffentlichten `.sql`- und `.pl`-Migrationen bleiben dauerhaft in jedem
späteren Updatepaket enthalten. Jede Migration muss so programmiert sein, dass
sie den bereits vorhandenen Datenzustand prüft und bei Bedarf nur die fehlenden
Daten ergänzt oder umwandelt. Die Tabelle `database_migration` protokolliert jede Datei unter ihrem dauerhaft
eindeutigen Migrationsschlüssel und speichert zusätzlich ihre Prüfsumme.
Nicht protokollierte Migrationen werden immer in aufsteigender Reihenfolge
ausgeführt; bereits protokollierte Migrationen werden anhand ihres Schlüssels
nicht erneut ausgeführt. Danach wird nochmals die vollständige Sollstruktur
geprüft und erst dann der aktuelle Stand in `database_version` eingetragen.
