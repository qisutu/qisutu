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

Ein neues Qisutu-Release wird immer in ein separates Verzeichnis entpackt.
Das neue Paket darf nicht direkt über eine bestehende Installation entpackt
werden. Anschließend wird `update.sh` aus dem neuen Paket mit dem Pfad der zu
aktualisierenden Instanz aufgerufen.

Produktivinstanz aktualisieren:

    cd /tmp/qisutu-neue-version/qisutu
    sudo ./update.sh /opt/qisutu

Zusätzliche Instanz aktualisieren:

    cd /tmp/qisutu-neue-version/qisutu
    sudo ./update.sh /opt/qisutu-test

Das Updateprogramm liest die vorhandene `var/install/instance.conf` und zeigt
vor der Bestätigung den Installationspfad, die Instanzkennung, den Webpfad, die
Datenbank und den systemd-Dienst an. Dadurch wird ausschließlich die explizit
angegebene Qisutu-Instanz aktualisiert. Weitere Installationen auf demselben
Server bleiben in Betrieb.

Während des Updates führt das Programm folgende Schritte aus:

1. Release-Prüfsummen, Versionen und Perl-Syntax prüfen.
2. Den vorhandenen Programmstand sichern und in der Konsole fragen, ob auch
   eine vollständige Datenbanksicherung angelegt werden soll. Das Programm
   weist dabei darauf hin, dass bei großen Installationen genügend freier
   Speicherplatz unter `/var/backups` vorhanden sein muss.
3. Für genau diese Instanz den Wartungsmodus aktivieren.
4. Den zugehörigen Qisutu-Daemon kontrolliert stoppen.
5. Einen bereits laufenden Mailabruf beenden lassen und neue Cronläufe dieser
   Instanz während des Updates überspringen.
6. Erforderliche Änderungen an der bestehenden Datenbank ausführen. Die
   Datenbank wird weder ersetzt noch in eine andere Datenbank übertragen.
7. Die Programmdateien vollständig austauschen, ohne die bestehende
   `QisutuConfig.pm`, `instance.conf`, Protokolle oder temporären Instanzdaten
   zu überschreiben.
8. Apache, Perl-Dateien, Datenbankstand und Daemon prüfen.
9. Bei einem Fehler den vorherigen Programmstand automatisch wiederherstellen.
   Der Datenbankstand kann nur dann automatisch wiederhergestellt werden, wenn
   die Datenbanksicherung vor dem Update bestätigt wurde.

Die Programm- und gegebenenfalls Datenbanksicherungen werden instanzbezogen
abgelegt unter:

    /var/backups/qisutu/INSTANZKENNUNG/JJJJ-MM-TT_HHMMSS/

Wird die Datenbanksicherung abgelehnt, enthält dieses Verzeichnis weiterhin
die Sicherung des Programmstands und der instanzbezogenen Konfiguration. Ein
Datenbankdump wird dann nicht erstellt. Bei Verwendung von `--yes` wird die
Datenbanksicherung ohne weitere Rückfrage angelegt.

Die aktuelle Tabellenstruktur wird bei jedem Update mit
`install/sql/schema.sql` abgeglichen. Fehlende Tabellen, Spalten, Indizes und
Fremdschlüssel werden dabei ergänzt, ohne zusätzliche vorhandene Strukturen zu
löschen.

Einmalige Datenänderungen wie `INSERT`, `UPDATE` oder Datenumwandlungen liegen
kumulativ unter:

    install/update/database/DATENBANKVERSION/

Alle veröffentlichten `.sql`- und `.pl`-Migrationen bleiben dauerhaft in jedem
späteren Updatepaket enthalten. Die Tabelle `database_migration` protokolliert
jede einzelne Datei mit Prüfsumme, sodass sie genau einmal ausgeführt wird und
ein direkter Sprung von einem alten auf den aktuellen Datenbankstand möglich
bleibt. Die Tabelle `database_version` dokumentiert erst nach erfolgreichem
Strukturabgleich und allen fehlenden Migrationen den erreichten Gesamtstand.

