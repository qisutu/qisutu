Qisutu-Datenbankupdates

Der Qisutu-Updater verwendet dauerhaft zwei getrennte Verfahren. Beide müssen
in jedem späteren Updatepaket vollständig enthalten bleiben.

1. Aktuelle Datenbankstruktur

Die vollständige Sollstruktur steht ausschließlich in:

install/sql/schema.sql

install/update/QisutuSchemaSync.pl vergleicht diese Sollstruktur mit der
vorhandenen MariaDB-Datenbank. Ohne vorhandene Daten zu löschen, ergänzt der
Updater fehlende Tabellen, Spalten, Primärschlüssel, Indizes und
Fremdschlüssel. Nach den Datenmigrationen wird dieser Abgleich erneut
ausgeführt, damit der endgültige Strukturstand geprüft ist.

2. Kumulative Datenmigrationen

Notwendige INSERT-, UPDATE- und Datenumwandlungsschritte liegen dauerhaft unter:

install/update/database/DATENBANKVERSION/

Beispiele:

install/update/database/0.0.2/001-create-password-reset-token.sql
install/update/database/0.0.3/001-create-customer-registration-request.sql
install/update/database/0.0.5/001-create-postmaster-filter.sql
install/update/database/0.0.6/001-create-time-accounting.sql

Alle früheren Migrationsdateien bleiben unverändert in jedem späteren
Updatepaket erhalten. Dadurch kann eine Installation direkt von einem sehr
alten Stand auf den aktuellen Stand aktualisiert werden.

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

Eine veröffentlichte Migration behält dauerhaft denselben Verzeichnis- und
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
