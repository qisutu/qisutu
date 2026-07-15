Qisutu-Datenbank-Updates

Für eine Qisutu-Version, die Änderungen an der bestehenden Datenbank benötigt,
wird hier ein Unterverzeichnis mit der neuen Datenbankversion angelegt.

Beispiel:

install/update/database/0.0.2/001-add-ticket-field.sql
install/update/database/0.0.2/002-create-new-table.sql

Der Updater führt die Versionsverzeichnisse und die darin enthaltenen Dateien
in aufsteigender Reihenfolge aus. Unterstützt werden .sql- und .pl-Dateien.
Nach erfolgreichem Abschluss wird die jeweilige Version in der bestehenden
Tabelle database_version eingetragen.
