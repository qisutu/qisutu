Qisutu-Datenbankupdates

Der Qisutu-Updater verwendet zwei getrennte Verfahren, die dauerhaft zusammen
im Updatepaket enthalten bleiben müssen.

1. Aktuelle Datenbankstruktur

Die vollständige Sollstruktur steht ausschließlich in:

install/sql/schema.sql

install/update/QisutuSchemaSync.pl vergleicht diese Sollstruktur mit der
vorhandenen MariaDB-Datenbank. Ohne vorhandene Daten zu löschen, ergänzt der
Updater fehlende Tabellen, Spalten, Primärschlüssel, Indizes und Fremdschlüssel.

2. Kumulative Datenmigrationen

Einmalige INSERT-, UPDATE- und Datenumwandlungsschritte liegen dauerhaft unter:

install/update/database/DATENBANKVERSION/

Beispiele:

install/update/database/0.0.2/001-create-password-reset-token.sql
install/update/database/0.0.3/001-create-customer-registration-request.sql
install/update/database/0.0.5/001-insert-new-system-setting.sql

Alle früheren Migrationsdateien bleiben in jedem späteren Updatepaket erhalten.
Dadurch kann eine Installation direkt von einem sehr alten Datenbankstand auf
den aktuellen Stand aktualisiert werden.

Die Tabelle database_migration protokolliert jede einzelne Migrationsdatei mit:

- eindeutigem Migrationsschlüssel
- zugehöriger Datenbankversion
- SHA-256-Prüfsumme
- Ausführungsart
- Ausführungszeitpunkt

Bereits registrierte Migrationen werden nicht erneut ausgeführt. Weicht die
Prüfsumme einer bereits registrierten Datei ab, bricht der Updater ab. Eine
veröffentlichte Migrationsdatei darf deshalb später niemals verändert oder
gelöscht werden.

Bei der erstmaligen Umstellung auf die Einzelprotokollierung werden Migrationen,
deren Versionsstand laut database_version bereits erreicht wurde, als
historisch ausgeführt registriert. Noch fehlende Migrationen werden in
aufsteigender Reihenfolge ausgeführt.

Unterstützt werden .sql- und .pl-Dateien. Dateinamen müssen mit einer laufenden
Nummer beginnen, damit die Reihenfolge eindeutig bleibt.

Neue Pflichtdaten für bestehende Installationen benötigen eine neue
Migrationsdatei. Dieselben Pflichtdaten müssen außerdem bei einer Neuinstallation
über schema.sql oder den Installer erzeugt werden.

Zusätzliche Tabellen oder Spalten werden beim Strukturabgleich nicht entfernt.
Abweichende vorhandene Definitionen werden aus Sicherheitsgründen nur gemeldet.
Potentiell destruktive Änderungen, Umbenennungen und komplexe Datenumwandlungen
müssen ausdrücklich als eigene Migration programmiert werden.
