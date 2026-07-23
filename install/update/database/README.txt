Qisutu-Datenbankupdates ab dem ersten offiziellen Release 1.0.1

Qisutu 1.0.1 ist die erste öffentlich unterstützte Version und wird nur neu
installiert. Ihre vollständige Datenbankbasis steht in:

install/sql/schema.sql
install/sql/insert.sql

Die während der Entwicklung verwendeten Migrationen der Versionen 0.0.x sind
nicht Bestandteil des offiziellen Pakets. Es gibt keine unterstützte
Vorabinstallation, die auf 1.0.1 aktualisiert werden muss.

Für spätere offizielle Updates bleiben zwei Verfahren erhalten:

1. Aktuelle Datenbankstruktur

install/update/QisutuSchemaSync.pl vergleicht die Sollstruktur aus
install/sql/schema.sql mit der vorhandenen MariaDB-Datenbank. Ohne vorhandene
Daten zu löschen, ergänzt der Updater fehlende Tabellen, Spalten,
Primärschlüssel, Indizes und Fremdschlüssel. Nach den Datenmigrationen wird
dieser Abgleich erneut ausgeführt, damit der endgültige Strukturstand geprüft
ist.

2. Kumulative Datenmigrationen ab 1.0.2

Notwendige INSERT-, UPDATE- und Datenumwandlungsschritte liegen künftig unter:

install/update/database/DATENBANKVERSION/

Beispiel:

install/update/database/1.0.2/001-beispiel.sql

Jede ab 1.0.2 veröffentlichte Migration bleibt unverändert in allen späteren
Updatepaketen enthalten. Dadurch kann eine offizielle Installation direkt von
einem älteren veröffentlichten Stand aktualisiert werden.

Die Tabelle database_migration protokolliert jede einzelne Migrationsdatei mit:

- eindeutigem Migrationsschlüssel
- zugehöriger Datenbankversion
- SHA-256-Prüfsumme
- Ausführungsart
- Ausführungszeitpunkt

Jede noch nicht protokollierte Migration wird ausgeführt, unabhängig davon,
welcher Gesamtstand zuvor in database_version eingetragen war. Dadurch werden
auch fehlende Pflicht-INSERTs und andere Datenanpassungen nachgeholt. Bereits
protokollierte Migrationen werden anhand ihres eindeutigen Migrationsschlüssels
nicht erneut ausgeführt. Die zusätzlich gespeicherte Prüfsumme dokumentiert den
bei der Ausführung vorhandenen Dateistand.

Eine ab 1.0.2 veröffentlichte Migration behält dauerhaft denselben Verzeichnis- und
Dateinamen und darf nicht aus späteren Updatepaketen entfernt werden. Jede
Migration muss den bestehenden Datenzustand selbst prüfen und wiederholbar
sicher sein, beispielsweise durch CREATE TABLE IF NOT EXISTS, INSERT ... ON
DUPLICATE KEY UPDATE oder ausdrückliche Existenzprüfungen. Das ist notwendig,
weil eine Datenänderung erfolgreich gewesen sein kann, bevor ihre
Protokollierung durch einen späteren Fehler unterbrochen wurde.

Unterstützt werden .sql- und .pl-Dateien. Dateinamen müssen mit einer laufenden
Nummer beginnen, damit die Reihenfolge eindeutig bleibt.

Neue Pflichtdaten für bestehende Installationen benötigen immer eine neue,
dauerhaft mitgeführte Migrationsdatei. Dieselben Pflichtdaten müssen außerdem
für Neuinstallationen in install/sql/insert.sql enthalten sein.

Zusätzliche Tabellen oder Spalten werden beim Strukturabgleich nicht entfernt.
Potentiell destruktive Änderungen, Umbenennungen und komplexe
Datenumwandlungen müssen ausdrücklich als eigene, abgesicherte Migration
programmiert werden.
