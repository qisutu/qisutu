# Qisutu

Qisutu ist ein neues Open-Source-Ticketsystem auf Basis von Perl/CGI,
MariaDB beziehungsweise MySQL, Template Toolkit und einer browserbasierten
Benutzeroberfläche.

Projektwebsite: https://qisutu.de

## Entwicklungsstatus

Qisutu befindet sich in einer frühen Entwicklungsphase. Schnittstellen,
Datenbankstrukturen und Installationsabläufe können sich noch ändern. Der
aktuelle Stand ist noch keine fertige Produktivversion.

## Installation

1. Das Qisutu-Archiv in ein eigenes Instanzverzeichnis entpacken, zum Beispiel
   `/opt/qisutu` oder `/opt/qisutu-test`.
2. Im entpackten Verzeichnis als root ausführen:

       sudo ./install.sh

3. Bei einer normalen Installation unter `/opt/qisutu` sind keine technischen
   Eingaben erforderlich. Liegt das System beispielsweise unter
   `/opt/qisutu-test`, fragt das Skript nur nach einem kurzen verständlichen
   Namen für die zusätzliche Instanz; `test` ist bereits vorgeschlagen.
4. Anschließend die vom Skript ausgegebene Adresse öffnen, beispielsweise:

       http://SERVER/qisutu/install.pl
       http://SERVER/qisutu-test/install.pl

5. Den sechs Schritten des Webinstallers folgen.

`install.sh` erkennt das Betriebssystem, installiert die benötigten Pakete und
Perl-Module und richtet für jede Qisutu-Instanz eine eigene Apache-Einbindung,
eigene systemd-Dienste, einen eigenen Webpfad und eine eigene
Datenbankkonfiguration ein. Dadurch können Produktiv- und Testsystem parallel
auf demselben Server laufen.

Der Webinstaller erstellt die jeweilige Datenbank, den festgelegten
Datenbankbenutzer, die Tabellenstruktur aus `install/sql/schema.sql`, die
Grunddaten aus `install/sql/insert.sql` und das erste Administratorkonto. Das
zufällig erzeugte Datenbankpasswort wird direkt in
`core/config/QisutuConfig.pm` der betreffenden Instanz geschrieben.

Ausführliche Hinweise und ein vollständiges Beispiel für zwei parallele
Instanzen stehen in `INSTALL.md`.

## Update

Ein neues Release wird separat entpackt und mit dem Pfad der gewünschten
Installation gestartet:

    sudo ./update.sh /opt/qisutu
    sudo ./update.sh /opt/qisutu-test

Der Updater erkennt die Instanz über `var/install/instance.conf`, stoppt nur
deren Daemon und sperrt deren Mailabruf. Er kopiert alle verwalteten
Programmdateien direkt in die bestehende Installation, ohne Instanzdateien,
Apache-Konfiguration oder systemd-Konfiguration zu überschreiben. Auf Wunsch
erstellt er zusätzlich einen Datenbankdump. Tabellenstruktur und alle dauerhaft
mitgeführten Datenmigrationen werden vollständig geprüft und bei Bedarf
ergänzt. Details stehen in `INSTALL.md`.

## Verzeichnisstruktur

- `bin/` – CGI-Einstieg, Hintergrundprozesse und Kommandozeilenprogramme
- `core/` – Konfiguration, Module, Templates, Sprachen und Systemklassen
- `install/sql/schema.sql` – vollständige Tabellenstruktur
- `install/sql/insert.sql` – Grunddaten für eine Neuinstallation
- `scriptfiles/` – Apache- und systemd-Vorlagen
- `var/static/` – Frontend-Assets und eingebundene Drittanbieter-Assets

## Zeiterfassung

Agenten können bei der Ticketerstellung, bei Artikeln und bei Ticketänderungen
optional Arbeitszeit in Stunden und Minuten erfassen. Jede Buchung unterscheidet
zwischen abrechenbarer und nicht abrechenbarer Zeit und kann einer im
Adminbereich gepflegten Tätigkeitsart zugeordnet werden. Manuelle Einzelbuchungen
sind ebenfalls möglich.

Zeitbuchungen sind revisionssicher: Sie werden nicht bearbeitet oder gelöscht.
Eine berechtigte Korrektur storniert die ursprüngliche Buchung mit Pflichtgrund
und legt eine verknüpfte Ersatzbuchung an. Die Korrekturberechtigung wird bei
Neuinstallation und Update nur der Admin-Gruppe zugewiesen. Zeitdaten werden
ausschließlich in Agenten- und Administrationsbereichen verarbeitet; Kundenmasken
und Kundenartikel enthalten keine Zeiterfassung.

## Datenbankkonfiguration

Die Datenbankverbindung steht direkt in `core/config/QisutuConfig.pm`. Der
Webinstaller trägt Host, Port, Datenbankname, Benutzer und das zufällig erzeugte
Passwort dort automatisch ein. Die Datei wird durch restriktive Dateirechte
geschützt.

## Lizenz

Qisutu ist unter der GNU Affero General Public License, Version 3 oder einer
späteren Version (`AGPL-3.0-or-later`), lizenziert. Die vollständigen
Lizenzbedingungen stehen in `LICENSE`.

Copyright (C) 2026 Franziska Steps.

## Drittanbieter-Software

Eingebundene Drittanbieterdateien behalten ihre ursprünglichen Copyright- und
Lizenzhinweise. Die zusammenfassenden Hinweise stehen in
`THIRD_PARTY_NOTICES.md`.
