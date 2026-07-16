#!/usr/bin/env bash

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

set -Eeuo pipefail

usage() {
    cat <<'EOF_USAGE'
Verwendung:
  sudo ./update.sh /opt/qisutu
  sudo ./update.sh /opt/qisutu-test

Optionen:
  --yes       Rückfragen überspringen und eine Datenbanksicherung erstellen
  --help      Diese Hilfe anzeigen

Das Updatepaket ist das Verzeichnis, in dem dieses update.sh liegt.
Der angegebene Pfad muss auf eine bereits installierte Qisutu-Instanz zeigen.
EOF_USAGE
}

fail() {
    echo "FEHLER: $*" >&2
    return 1
}

trim() {
    local value="$1"
    value="${value#"${value%%[![:space:]]*}"}"
    value="${value%"${value##*[![:space:]]}"}"
    printf '%s' "$value"
}

version_is_valid() {
    [[ "$1" =~ ^[0-9]+([.][0-9]+)*([+-][A-Za-z0-9.-]+)?$ ]]
}

version_lt() {
    local left="$1"
    local right="$2"
    [[ "$left" != "$right" ]] && [[ "$(printf '%s\n%s\n' "$left" "$right" | sort -V | head -n 1)" == "$left" ]]
}

version_gt() {
    version_lt "$2" "$1"
}

version_le() {
    [[ "$1" == "$2" ]] || version_lt "$1" "$2"
}

escape_sed_replacement() {
    printf '%s' "$1" | sed 's/[&|\\]/\\&/g'
}

load_key_value_file() {
    local file="$1"
    local purpose="$2"
    local key value

    [[ -r "$file" ]] || fail "$purpose kann nicht gelesen werden: $file"

    while IFS='=' read -r key value; do
        key="$(trim "$key")"
        value="$(trim "${value:-}")"
        [[ -n "$key" ]] || continue
        [[ "$key" == \#* ]] && continue

        case "$purpose:$key" in
            release:product) PRODUCT="$value" ;;
            release:version) RELEASE_VERSION="$value" ;;
            release:minimum_program_version) MINIMUM_PROGRAM_VERSION="$value" ;;
            release:database_version) TARGET_DATABASE_VERSION="$value" ;;
            instance:instance_id) INSTANCE_ID="$value" ;;
            instance:web_path) WEB_PATH="$value" ;;
            instance:apache_conf_name) APACHE_CONF_NAME="$value" ;;
            instance:daemon_service) DAEMON_SERVICE="$value" ;;
            instance:install_complete_service) INSTALL_COMPLETE_SERVICE="$value" ;;
            instance:install_complete_path) INSTALL_COMPLETE_PATH="$value" ;;
            instance:session_cookie) SESSION_COOKIE="$value" ;;
            instance:db_name) DB_NAME="$value" ;;
            instance:db_user) DB_USER="$value" ;;
        esac
    done < "$file"
}

validate_instance_config() {
    [[ "$INSTANCE_ID" =~ ^[a-z][a-z0-9-]{0,47}$ ]] || fail "Ungültige Instanzkennung in instance.conf: $INSTANCE_ID"
    [[ "$WEB_PATH" =~ ^/[A-Za-z0-9][A-Za-z0-9_/-]*$ ]] || fail "Ungültiger Webpfad in instance.conf: $WEB_PATH"
    [[ "$WEB_PATH" != */ && "$WEB_PATH" != *"//"* && "$WEB_PATH" != *".."* ]] || fail "Ungültiger Webpfad in instance.conf: $WEB_PATH"
    [[ "$APACHE_CONF_NAME" =~ ^[A-Za-z0-9][A-Za-z0-9._-]*\.conf$ ]] || fail "Ungültiger Apache-Konfigurationsname: $APACHE_CONF_NAME"
    [[ "$DAEMON_SERVICE" =~ ^[A-Za-z0-9][A-Za-z0-9_.@-]*\.service$ ]] || fail "Ungültiger Daemon-Dienstname: $DAEMON_SERVICE"
    [[ "$DB_NAME" =~ ^[A-Za-z][A-Za-z0-9_]{0,63}$ ]] || fail "Ungültiger Datenbankname: $DB_NAME"
    [[ "$DB_USER" =~ ^[A-Za-z][A-Za-z0-9_]{0,63}$ ]] || fail "Ungültiger Datenbankbenutzer: $DB_USER"
}

command_required() {
    command -v "$1" >/dev/null 2>&1 || fail "Benötigtes Programm wurde nicht gefunden: $1"
}

mail_fetch_running() {
    local command_file command_line

    for command_file in /proc/[0-9]*/cmdline; do
        [[ -r "$command_file" ]] || continue
        command_line="$(tr '\0' ' ' < "$command_file" 2>/dev/null || true)"
        if [[ "$command_line" == *"$TARGET_ROOT/bin/qisutu-mail-fetch.pl"* ]]; then
            return 0
        fi
    done

    return 1
}

mail_fetch_block() {
    local mail_file="$TARGET_ROOT/bin/qisutu-mail-fetch.pl"
    local saved_file="$TARGET_ROOT/bin/.qisutu-mail-fetch.pl.update-backup"

    [[ -f "$mail_file" ]] || fail "Der Mailabruf der Instanz wurde nicht gefunden: $mail_file"

    if [[ -f "$saved_file" ]]; then
        if grep -Fq 'QISUTU_UPDATE_TEMPORARY_MAIL_BLOCK' "$mail_file" 2>/dev/null; then
            mv -f "$saved_file" "$mail_file"
        else
            fail "Es existiert bereits eine unklare Update-Sicherungsdatei: $saved_file"
        fi
    fi

    mv "$mail_file" "$saved_file"
    cat > "$mail_file" <<'EOF_MAIL_BLOCK'
#!/usr/bin/env perl
# QISUTU_UPDATE_TEMPORARY_MAIL_BLOCK
use strict;
use warnings;
print STDERR "Qisutu update is active. Mail fetch skipped.\n";
exit 0;
EOF_MAIL_BLOCK
    chmod 0755 "$mail_file"
    chown "$APACHE_USER:$APACHE_GROUP" "$mail_file"
    MAIL_FETCH_BLOCKED=1

    local waited=0
    while mail_fetch_running; do
        if (( waited >= 600 )); then
            fail "Ein laufender Qisutu-Mailabruf wurde innerhalb der zulässigen Wartezeit nicht beendet."
        fi
        sleep 1
        waited=$(( waited + 1 ))
    done
}

mail_fetch_restore() {
    local mail_file="$TARGET_ROOT/bin/qisutu-mail-fetch.pl"
    local saved_file="$TARGET_ROOT/bin/.qisutu-mail-fetch.pl.update-backup"

    if [[ -f "$saved_file" ]]; then
        rm -f "$mail_file"
        mv -f "$saved_file" "$mail_file"
    fi
    MAIL_FETCH_BLOCKED=0
}

mysql_config_create() {
    QISUTU_HOME="$TARGET_ROOT" perl \
        -I"$TARGET_ROOT/core/config" \
        -MQisutuConfig \
        -e '
            use strict;
            use warnings;
            my $file = shift @ARGV;
            my $config = QisutuConfig::Load();
            my $db = $config->{Database} || {};
            sub quote_value {
                my ($value) = @_;
                $value = q{} if !defined $value;
                $value =~ s/\\/\\\\/g;
                $value =~ s/"/\\"/g;
                $value =~ s/\n/\\n/g;
                $value =~ s/\r/\\r/g;
                $value =~ s/\t/\\t/g;
                return qq{"$value"};
            }
            open my $fh, q{>}, $file or die "Cannot write $file: $!\n";
            chmod 0600, $file;
            print {$fh} "[client]\n";
            print {$fh} "host=", quote_value($db->{Host} || q{localhost}), "\n";
            print {$fh} "port=", 0 + ($db->{Port} || 3306), "\n";
            print {$fh} "user=", quote_value($db->{User} || q{}), "\n";
            print {$fh} "password=", quote_value($db->{Password} || q{}), "\n";
            print {$fh} "default-character-set=utf8mb4\n";
            close $fh or die "Cannot close $file: $!\n";
        ' "$MYSQL_CONFIG_FILE"

    chmod 0600 "$MYSQL_CONFIG_FILE"
}

config_value_get() {
    local field="$1"

    QISUTU_HOME="$TARGET_ROOT" perl \
        -I"$TARGET_ROOT/core/config" \
        -MQisutuConfig \
        -e '
            use strict;
            use warnings;
            my $field = shift @ARGV;
            my $config = QisutuConfig::Load();
            if ($field eq q{program_version}) {
                print $config->{System}->{Version} || q{};
            }
            elsif ($field eq q{database_name}) {
                print $config->{Database}->{Name} || q{};
            }
            elsif ($field eq q{instance_id}) {
                print $config->{System}->{InstanceID} || q{};
            }
        ' "$field"
}

perl_syntax_check() {
    local root="$1"
    local file

    local check_output

    while IFS= read -r -d '' file; do
        if ! check_output="$(
            QISUTU_HOME="$root" perl \
                -I"$root/core/config" \
                -I"$root/core/system" \
                -I"$root/core/output" \
                -I"$root/core/module" \
                -I"$root/core/cpan-lib" \
                -c "$file" 2>&1
        )"; then
            echo "$check_output" >&2
            fail "Perl-Syntaxprüfung fehlgeschlagen: $file"
        fi
    done < <(find "$root/bin" "$root/core" "$root/install/update" -type f \( -name '*.pl' -o -name '*.pm' \) -print0)
}

program_version_patch() {
    local config_file="$1"

    RELEASE_VERSION_ENV="$RELEASE_VERSION" perl -0pi -e '
        my $version = $ENV{RELEASE_VERSION_ENV};
        my $count = s{(Version\s*=>\s*)\x27[^\x27]*\x27}{$1 . "\x27" . $version . "\x27"}e;
        die "Qisutu program version could not be updated\n" if $count != 1;
    ' "$config_file"
}

stage_prepare() {
    rm -rf "$STAGE_ROOT"
    mkdir -p "$STAGE_ROOT"
    cp -a "$SOURCE_ROOT/." "$STAGE_ROOT/"

    rm -f "$STAGE_ROOT/core/config/QisutuConfig.pm"
    cp -a "$TARGET_ROOT/core/config/QisutuConfig.pm" "$STAGE_ROOT/core/config/QisutuConfig.pm"

    local path
    for path in var/install var/log var/cache var/tmp log; do
        if [[ -e "$TARGET_ROOT/$path" ]]; then
            rm -rf "$STAGE_ROOT/$path"
            mkdir -p "$(dirname "$STAGE_ROOT/$path")"
            cp -a "$TARGET_ROOT/$path" "$STAGE_ROOT/$path"
        fi
    done

    local runtime_apache="$TARGET_ROOT/scriptfiles/$INSTANCE_ID-apache-runtime.conf"
    if [[ -f "$runtime_apache" ]]; then
        cp -a "$runtime_apache" "$STAGE_ROOT/scriptfiles/$INSTANCE_ID-apache-runtime.conf"
    fi

    rm -f "$STAGE_ROOT/bin/.qisutu-mail-fetch.pl.update-backup"
    program_version_patch "$STAGE_ROOT/core/config/QisutuConfig.pm"

    installation_permissions_apply "$STAGE_ROOT"
}

installation_permissions_apply() {
    local root="$1"
    local path executable_file
    local executable_files=(
        qisutu-daemon.pl
        qisutu-mail-fetch.pl
        qisutu-search-index-rebuild.pl
        qisutu-ticket-escalation-check.pl
    )

    [[ -d "$root" ]] || fail "Qisutu-Verzeichnis für die Rechtevergabe fehlt: $root"

    # Der bestehende Besitzer der ausgewählten Instanz wird beibehalten.
    # Dadurch wird bei mehreren Installationen nicht eigenmächtig ein anderer
    # Systembenutzer für die Programmdateien gesetzt.
    chown -R "$TARGET_OWNER:$TARGET_GROUP" "$root"

    find "$root" -type d -exec chmod 0755 {} +
    find "$root" -type f -exec chmod 0644 {} +

    chmod 0755 "$root/install.sh" "$root/update.sh"
    find "$root/bin" -type f -name '*.pl' -exec chmod 0755 {} +

    for executable_file in "${executable_files[@]}"; do
        if [[ -f "$root/bin/$executable_file" ]]; then
            chmod 0775 "$root/bin/$executable_file"
        fi
    done

    for path in var/install var/log var/cache var/tmp; do
        mkdir -p "$root/$path"
        chown -R "$TARGET_OWNER:$TARGET_GROUP" "$root/$path"
        chmod 0770 "$root/$path"
    done

    chown "$TARGET_OWNER:$TARGET_GROUP" "$root/core/config/QisutuConfig.pm"
    chmod 0660 "$root/core/config/QisutuConfig.pm"

    chown "$TARGET_OWNER:$TARGET_GROUP" "$root/var/install/instance.conf"
    chmod 0640 "$root/var/install/instance.conf"

    if [[ -f "$root/var/install/update.lock" ]]; then
        chown "$TARGET_OWNER:$TARGET_GROUP" "$root/var/install/update.lock"
        chmod 0660 "$root/var/install/update.lock"
    fi
}

database_current_version_get() {
    local table_exists current_version

    table_exists="$(
        "$DB_CLIENT" --defaults-extra-file="$MYSQL_CONFIG_FILE" --batch --skip-column-names "$DB_NAME" \
            -e "SELECT COUNT(*) FROM INFORMATION_SCHEMA.TABLES WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'database_version' AND TABLE_TYPE = 'BASE TABLE'"
    )"

    if [[ "$table_exists" != "1" ]]; then
        printf '0.0.0\n'
        return
    fi

    current_version="$(
        "$DB_CLIENT" --defaults-extra-file="$MYSQL_CONFIG_FILE" --batch --skip-column-names "$DB_NAME" \
            -e 'SELECT version FROM database_version ORDER BY id DESC LIMIT 1' | head -n 1
    )"

    if [[ -z "$current_version" ]]; then
        printf '0.0.0\n'
    else
        printf '%s\n' "$current_version"
    fi
}

database_schema_synchronize() {
    local schema_file="$STAGE_ROOT/install/sql/schema.sql"
    local sync_program="$STAGE_ROOT/install/update/QisutuSchemaSync.pl"
    local status_file="$TEMP_ROOT/schema-sync.status"
    local status_key status_value schema_changed=""

    [[ -r "$schema_file" ]] || fail "Die aktuelle Datenbank-Sollstruktur fehlt: $schema_file"
    [[ -r "$sync_program" ]] || fail "Das Programm für den Datenbankabgleich fehlt: $sync_program"

    rm -f "$status_file"

    # Vor dem Aufruf wird DB_CHANGED vorsorglich gesetzt. Falls der Abgleich
    # nach bereits ausgeführten DDL-Anweisungen fehlschlägt, kann die
    # Fehlerbehandlung die Datenbanksicherung zuverlässig zurückspielen.
    DB_CHANGED=1

    QISUTU_HOME="$STAGE_ROOT" perl \
        -I"$STAGE_ROOT/core/config" \
        -I"$STAGE_ROOT/core/system" \
        -I"$STAGE_ROOT/core/cpan-lib" \
        "$sync_program" \
        --schema "$schema_file" \
        --status-file "$status_file"

    [[ -r "$status_file" ]] || fail "Der Datenbankabgleich hat keine Statusdatei erzeugt."

    while IFS='=' read -r status_key status_value; do
        case "$status_key" in
            changed) schema_changed="$status_value" ;;
        esac
    done < "$status_file"

    case "$schema_changed" in
        0) DB_CHANGED=0 ;;
        1) DB_CHANGED=1 ;;
        *) fail "Der Änderungsstatus des Datenbankabgleichs ist ungültig." ;;
    esac
}


sql_literal_escape() {
    local value="$1"
    value="${value//\'/\'\'}"
    printf '%s' "$value"
}

database_migrations_apply() {
    local installed_database_version="$1"
    local migrations_root="$STAGE_ROOT/install/update/database"
    local version_directory migration_version migration_file migration_name
    local migration_key migration_checksum stored_record stored_checksum stored_mode
    local escaped_key escaped_version escaped_checksum
    local executed_count=0 baseline_count=0 skipped_count=0 file_count=0

    [[ -d "$migrations_root" ]] || fail "Verzeichnis für kumulative Datenmigrationen fehlt: $migrations_root"

    echo "Prüfe die dauerhaft mitgelieferten Datenmigrationen."

    while IFS= read -r migration_version; do
        [[ -n "$migration_version" ]] || continue
        version_is_valid "$migration_version" || fail "Ungültiges Datenmigrationsverzeichnis: $migration_version"
        version_le "$migration_version" "$TARGET_DATABASE_VERSION" || fail "Die Datenmigration $migration_version ist neuer als der erwartete Datenbankstand $TARGET_DATABASE_VERSION."

        version_directory="$migrations_root/$migration_version"
        file_count=0

        while IFS= read -r -d '' migration_file; do
            file_count=$(( file_count + 1 ))
            migration_name="$(basename "$migration_file")"

            [[ "$migration_name" =~ ^[A-Za-z0-9][A-Za-z0-9._-]*\.(sql|pl)$ ]] \
                || fail "Ungültiger Dateiname einer Datenmigration: $migration_file"

            migration_key="$migration_version/$migration_name"
            (( ${#migration_key} <= 255 )) || fail "Der Schlüssel der Datenmigration ist zu lang: $migration_key"

            migration_checksum="$(sha256sum "$migration_file" | awk '{print $1}')"
            [[ "$migration_checksum" =~ ^[0-9a-f]{64}$ ]] || fail "Die Prüfsumme der Datenmigration ist ungültig: $migration_key"

            escaped_key="$(sql_literal_escape "$migration_key")"
            stored_record="$(
                "$DB_CLIENT" --defaults-extra-file="$MYSQL_CONFIG_FILE" --batch --skip-column-names "$DB_NAME" \
                    -e "SELECT CONCAT(checksum_sha256, CHAR(9), execution_mode) FROM database_migration WHERE migration_key = '$escaped_key' LIMIT 1"
            )"

            if [[ -n "$stored_record" ]]; then
                IFS=$'\t' read -r stored_checksum stored_mode <<< "$stored_record"
                [[ "$stored_checksum" == "$migration_checksum" ]] \
                    || fail "Die bereits registrierte Datenmigration $migration_key besitzt im Updatepaket eine andere Prüfsumme. Alte Migrationen dürfen nachträglich nicht verändert werden."
                echo "  Bereits erledigt: $migration_key ($stored_mode)"
                skipped_count=$(( skipped_count + 1 ))
                continue
            fi

            escaped_version="$(sql_literal_escape "$migration_version")"
            escaped_checksum="$(sql_literal_escape "$migration_checksum")"

            if version_le "$migration_version" "$installed_database_version"; then
                echo "  Historischen Stand übernehmen: $migration_key"
                DB_CHANGED=1
                "$DB_CLIENT" --defaults-extra-file="$MYSQL_CONFIG_FILE" "$DB_NAME" \
                    -e "INSERT INTO database_migration (migration_key, database_version, checksum_sha256, execution_mode) VALUES ('$escaped_key', '$escaped_version', '$escaped_checksum', 'legacy')"
                baseline_count=$(( baseline_count + 1 ))
                continue
            fi

            DB_CHANGED=1
            case "$migration_file" in
                *.sql)
                    echo "  SQL ausführen: $migration_key"
                    "$DB_CLIENT" --defaults-extra-file="$MYSQL_CONFIG_FILE" "$DB_NAME" < "$migration_file"
                    ;;
                *.pl)
                    echo "  Perl ausführen: $migration_key"
                    QISUTU_HOME="$STAGE_ROOT" \
                    QISUTU_DATABASE_MIGRATION_VERSION="$migration_version" \
                    QISUTU_DATABASE_MIGRATION_KEY="$migration_key" \
                    perl \
                        -I"$STAGE_ROOT/core/config" \
                        -I"$STAGE_ROOT/core/system" \
                        -I"$STAGE_ROOT/core/cpan-lib" \
                        "$migration_file"
                    ;;
                *)
                    fail "Nicht unterstützte Datenmigration: $migration_file"
                    ;;
            esac

            "$DB_CLIENT" --defaults-extra-file="$MYSQL_CONFIG_FILE" "$DB_NAME" \
                -e "INSERT INTO database_migration (migration_key, database_version, checksum_sha256, execution_mode) VALUES ('$escaped_key', '$escaped_version', '$escaped_checksum', 'executed')"
            executed_count=$(( executed_count + 1 ))
        done < <(find "$version_directory" -maxdepth 1 -type f \( -name '*.sql' -o -name '*.pl' \) -print0 | sort -zV)

        if (( file_count == 0 )); then
            fail "Das Datenmigrationsverzeichnis $version_directory enthält keine .sql- oder .pl-Datei."
        fi
    done < <(find "$migrations_root" -mindepth 1 -maxdepth 1 -type d -printf '%f\n' | sort -V)

    printf 'Datenmigrationen: %d ausgeführt, %d historisch übernommen, %d bereits erledigt.\n' \
        "$executed_count" "$baseline_count" "$skipped_count"
}

database_target_version_record() {
    local version_exists escaped_version

    escaped_version="$(sql_literal_escape "$TARGET_DATABASE_VERSION")"
    version_exists="$(
        "$DB_CLIENT" --defaults-extra-file="$MYSQL_CONFIG_FILE" --batch --skip-column-names "$DB_NAME" \
            -e "SELECT COUNT(*) FROM database_version WHERE version = '$escaped_version'"
    )"

    if [[ "$version_exists" == "0" ]]; then
        echo "Trage den erfolgreich erreichten Datenbankstand $TARGET_DATABASE_VERSION ein."
        DB_CHANGED=1
        "$DB_CLIENT" --defaults-extra-file="$MYSQL_CONFIG_FILE" "$DB_NAME" \
            -e "INSERT INTO database_version (version) VALUES ('$escaped_version')"
    elif [[ "$version_exists" != "1" ]]; then
        fail "Der Datenbankstand $TARGET_DATABASE_VERSION konnte nicht eindeutig geprüft werden."
    fi
}

daemon_service_render() {
    local source_file="$TARGET_ROOT/scriptfiles/qisutu-daemon.service"
    local target_file="/etc/systemd/system/$DAEMON_SERVICE"
    local temporary_file="$TEMP_ROOT/daemon.service"
    local escaped_root escaped_instance escaped_user escaped_group escaped_web escaped_daemon escaped_complete_service escaped_complete_path

    [[ -f "$source_file" ]] || fail "Die Vorlage des Daemon-Dienstes fehlt: $source_file"

    escaped_root="$(escape_sed_replacement "$TARGET_ROOT")"
    escaped_instance="$(escape_sed_replacement "$INSTANCE_ID")"
    escaped_user="$(escape_sed_replacement "$APACHE_USER")"
    escaped_group="$(escape_sed_replacement "$APACHE_GROUP")"
    escaped_web="$(escape_sed_replacement "$WEB_PATH")"
    escaped_daemon="$(escape_sed_replacement "$DAEMON_SERVICE")"
    escaped_complete_service="$(escape_sed_replacement "$INSTALL_COMPLETE_SERVICE")"
    escaped_complete_path="$(escape_sed_replacement "$INSTALL_COMPLETE_PATH")"

    sed \
        -e "s|__QISUTU_ROOT__|$escaped_root|g" \
        -e "s|__QISUTU_INSTANCE__|$escaped_instance|g" \
        -e "s|__QISUTU_APACHE_USER__|$escaped_user|g" \
        -e "s|__QISUTU_APACHE_GROUP__|$escaped_group|g" \
        -e "s|__QISUTU_WEB_PATH__|$escaped_web|g" \
        -e "s|__QISUTU_DAEMON_SERVICE__|$escaped_daemon|g" \
        -e "s|__QISUTU_INSTALL_COMPLETE_SERVICE__|$escaped_complete_service|g" \
        -e "s|__QISUTU_INSTALL_COMPLETE_PATH__|$escaped_complete_path|g" \
        "$source_file" > "$temporary_file"

    install -o root -g root -m 0644 "$temporary_file" "$target_file"
    SYSTEMD_CHANGED=1
}

apache_config_test() {
    if command -v apache2ctl >/dev/null 2>&1; then
        apache2ctl configtest
    elif command -v httpd >/dev/null 2>&1; then
        httpd -t
    elif command -v apachectl >/dev/null 2>&1; then
        apachectl configtest
    else
        fail "Apache-Konfigurationsprüfung ist nicht verfügbar."
    fi
}

rollback() {
    local line="$1"
    local command="$2"

    trap - ERR
    set +e

    echo >&2
    echo "Das Qisutu-Update ist fehlgeschlagen." >&2
    echo "Fehler bei Zeile $line: $command" >&2
    echo "Der vorherige Programmstand wird wiederhergestellt." >&2

    if (( SWAPPED == 1 )); then
        if [[ -e "$TARGET_ROOT" ]]; then
            rm -rf "$FAILED_ROOT"
            mv "$TARGET_ROOT" "$FAILED_ROOT"
        fi
        if [[ -e "$OLD_ROOT" ]]; then
            mv "$OLD_ROOT" "$TARGET_ROOT"
        fi
        SWAPPED=0
    fi

    if (( MAIL_FETCH_BLOCKED == 1 )) && [[ -d "$TARGET_ROOT" ]]; then
        mail_fetch_restore
    fi

    if (( DB_CHANGED == 1 )); then
        if (( DATABASE_BACKUP_CREATED == 1 )) && [[ -s "$DATABASE_DUMP_FILE" ]] && [[ -f "$MYSQL_CONFIG_FILE" ]]; then
            echo "Datenbank wird aus der Sicherung wiederhergestellt." >&2
            "$DB_CLIENT" --defaults-extra-file="$MYSQL_CONFIG_FILE" < "$DATABASE_DUMP_FILE" >&2
        else
            echo "ACHTUNG: Die Datenbank wurde vor dem Update nicht gesichert." >&2
            echo "Bereits ausgeführte Datenbankänderungen können deshalb nicht automatisch zurückgesetzt werden." >&2
        fi
    fi

    if (( SYSTEMD_CHANGED == 1 )); then
        if [[ -f "$BACKUP_DIR/systemd/$DAEMON_SERVICE" ]]; then
            cp -a "$BACKUP_DIR/systemd/$DAEMON_SERVICE" "/etc/systemd/system/$DAEMON_SERVICE"
        else
            rm -f "/etc/systemd/system/$DAEMON_SERVICE"
        fi
        systemctl daemon-reload >/dev/null 2>&1
    fi

    if [[ -d "$TARGET_ROOT" ]]; then
        rm -f "$TARGET_ROOT/var/install/update.lock"
    fi

    if (( SERVICE_WAS_ACTIVE == 1 )); then
        systemctl start "$DAEMON_SERVICE" >/dev/null 2>&1
    fi

    if [[ -n "${RUNTIME_LOCK_FD:-}" ]]; then
        flock -u "$RUNTIME_LOCK_FD" >/dev/null 2>&1
    fi

    echo "Sicherungsverzeichnis: ${BACKUP_DIR:-nicht angelegt}" >&2
    exit 1
}

if [[ ${EUID:-$(id -u)} -ne 0 ]]; then
    fail "Bitte dieses Updateprogramm als root ausführen: sudo ./update.sh /opt/qisutu"
fi

TARGET_ARGUMENT=""
ASSUME_YES=0

while (( $# > 0 )); do
    case "$1" in
        --yes)
            ASSUME_YES=1
            shift
            ;;
        --help|-h)
            usage
            exit 0
            ;;
        --*)
            fail "Unbekannte Option: $1"
            ;;
        *)
            if [[ -n "$TARGET_ARGUMENT" ]]; then
                fail "Es darf nur ein Qisutu-Installationspfad angegeben werden."
            fi
            TARGET_ARGUMENT="$1"
            shift
            ;;
    esac
done

[[ -n "$TARGET_ARGUMENT" ]] || { usage; exit 1; }

SOURCE_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
[[ -d "$TARGET_ARGUMENT" ]] || fail "Die angegebene Qisutu-Installation existiert nicht: $TARGET_ARGUMENT"
TARGET_ROOT="$(cd "$TARGET_ARGUMENT" && pwd -P)"

[[ "$SOURCE_ROOT" != "$TARGET_ROOT" ]] || fail "Das Updatepaket darf nicht mit der zu aktualisierenden Installation identisch sein. Entpacke das neue ZIP in ein separates Verzeichnis."
[[ "$TARGET_ROOT" != *[[:space:]]* ]] || fail "Der Qisutu-Installationspfad darf keine Leerzeichen enthalten: $TARGET_ROOT"

TARGET_OWNER="$(stat -c '%U' "$TARGET_ROOT")"
TARGET_GROUP="$(stat -c '%G' "$TARGET_ROOT")"
[[ "$TARGET_OWNER" =~ ^[A-Za-z_][A-Za-z0-9_-]*$ ]] || fail "Der bisherige Besitzer der Qisutu-Installation konnte nicht bestimmt werden."
[[ "$TARGET_GROUP" =~ ^[A-Za-z_][A-Za-z0-9_-]*$ ]] || fail "Die bisherige Gruppe der Qisutu-Installation konnte nicht bestimmt werden."
id "$TARGET_OWNER" >/dev/null 2>&1 || fail "Der bisherige Besitzer der Qisutu-Installation existiert nicht: $TARGET_OWNER"
getent group "$TARGET_GROUP" >/dev/null 2>&1 || fail "Die bisherige Gruppe der Qisutu-Installation existiert nicht: $TARGET_GROUP"

PRODUCT=""
RELEASE_VERSION=""
MINIMUM_PROGRAM_VERSION=""
TARGET_DATABASE_VERSION=""
INSTANCE_ID=""
WEB_PATH=""
APACHE_CONF_NAME=""
DAEMON_SERVICE=""
INSTALL_COMPLETE_SERVICE=""
INSTALL_COMPLETE_PATH=""
SESSION_COOKIE=""
DB_NAME=""
DB_USER=""

load_key_value_file "$SOURCE_ROOT/release.conf" release
[[ "$PRODUCT" == "Qisutu" ]] || fail "Dieses Paket ist kein gültiges Qisutu-Updatepaket."
version_is_valid "$RELEASE_VERSION" || fail "Ungültige Programmversion im Updatepaket: $RELEASE_VERSION"
version_is_valid "$MINIMUM_PROGRAM_VERSION" || fail "Ungültige minimale Ausgangsversion: $MINIMUM_PROGRAM_VERSION"
version_is_valid "$TARGET_DATABASE_VERSION" || fail "Ungültige Datenbankversion im Updatepaket: $TARGET_DATABASE_VERSION"

INSTANCE_CONFIG_FILE="$TARGET_ROOT/var/install/instance.conf"
INSTALL_LOCK_FILE="$TARGET_ROOT/var/install/installed.lock"
UPDATE_LOCK_FILE="$TARGET_ROOT/var/install/update.lock"

[[ -f "$INSTALL_LOCK_FILE" ]] || fail "Der Pfad ist keine vollständig installierte Qisutu-Instanz: installed.lock fehlt."
[[ -f "$TARGET_ROOT/core/config/QisutuConfig.pm" ]] || fail "QisutuConfig.pm fehlt in der ausgewählten Installation."
load_key_value_file "$INSTANCE_CONFIG_FILE" instance
validate_instance_config

command_required perl
command_required find
command_required sort
command_required tar
command_required flock
command_required systemctl
command_required sed
command_required install
command_required sha256sum
command_required stat

[[ -f "$SOURCE_ROOT/release.sha256" ]] || fail "Prüfsummenliste des Updatepakets fehlt: release.sha256"
if ! ( cd "$SOURCE_ROOT" && sha256sum --check --quiet release.sha256 ); then
    fail "Die Prüfsummen des Qisutu-Updatepakets sind ungültig. Das Paket wird nicht installiert."
fi

if command -v mariadb >/dev/null 2>&1; then
    DB_CLIENT="mariadb"
elif command -v mysql >/dev/null 2>&1; then
    DB_CLIENT="mysql"
else
    fail "MariaDB-/MySQL-Kommandozeilenprogramm wurde nicht gefunden."
fi

DB_DUMP_CLIENT=""
if command -v mariadb-dump >/dev/null 2>&1; then
    DB_DUMP_CLIENT="mariadb-dump"
elif command -v mysqldump >/dev/null 2>&1; then
    DB_DUMP_CLIENT="mysqldump"
fi

SYSTEMD_FILE="/etc/systemd/system/$DAEMON_SERVICE"
[[ -f "$SYSTEMD_FILE" ]] || fail "Der systemd-Dienst der Instanz wurde nicht gefunden: $SYSTEMD_FILE"

APACHE_USER="$(sed -n 's/^User=//p' "$SYSTEMD_FILE" | head -n 1)"
APACHE_GROUP="$(sed -n 's/^Group=//p' "$SYSTEMD_FILE" | head -n 1)"
[[ "$APACHE_USER" =~ ^[A-Za-z_][A-Za-z0-9_-]*$ ]] || fail "Der Benutzer des Daemon-Dienstes konnte nicht bestimmt werden."
[[ "$APACHE_GROUP" =~ ^[A-Za-z_][A-Za-z0-9_-]*$ ]] || fail "Die Gruppe des Daemon-Dienstes konnte nicht bestimmt werden."
id "$APACHE_USER" >/dev/null 2>&1 || fail "Der Qisutu-Systembenutzer existiert nicht: $APACHE_USER"
getent group "$APACHE_GROUP" >/dev/null 2>&1 || fail "Die Qisutu-Systemgruppe existiert nicht: $APACHE_GROUP"

CURRENT_PROGRAM_VERSION="$(config_value_get program_version)"
CONFIG_DB_NAME="$(config_value_get database_name)"
CONFIG_INSTANCE_ID="$(config_value_get instance_id)"
version_is_valid "$CURRENT_PROGRAM_VERSION" || fail "Die installierte Qisutu-Programmversion konnte nicht bestimmt werden."
[[ "$CONFIG_DB_NAME" == "$DB_NAME" ]] || fail "Datenbankname in QisutuConfig.pm ($CONFIG_DB_NAME) und instance.conf ($DB_NAME) stimmen nicht überein."
[[ -z "$CONFIG_INSTANCE_ID" || "$CONFIG_INSTANCE_ID" == "$INSTANCE_ID" ]] || fail "Instanzkennung in QisutuConfig.pm ($CONFIG_INSTANCE_ID) und instance.conf ($INSTANCE_ID) stimmen nicht überein."

if version_lt "$CURRENT_PROGRAM_VERSION" "$MINIMUM_PROGRAM_VERSION"; then
    fail "Dieses Update benötigt mindestens Qisutu $MINIMUM_PROGRAM_VERSION. Installiert ist $CURRENT_PROGRAM_VERSION."
fi
if ! version_lt "$CURRENT_PROGRAM_VERSION" "$RELEASE_VERSION"; then
    fail "Das Updatepaket $RELEASE_VERSION ist nicht neuer als die installierte Version $CURRENT_PROGRAM_VERSION."
fi

printf '\nAusgewählte Qisutu-Instanz\n'
printf '  Installationspfad: %s\n' "$TARGET_ROOT"
printf '  Instanzkennung:    %s\n' "$INSTANCE_ID"
printf '  Webpfad:           %s\n' "$WEB_PATH"
printf '  Datenbank:         %s\n' "$DB_NAME"
printf '  Daemon:            %s\n' "$DAEMON_SERVICE"
printf '  Besitzer:          %s:%s\n' "$TARGET_OWNER" "$TARGET_GROUP"
printf '  Installiert:       %s\n' "$CURRENT_PROGRAM_VERSION"
printf '  Update auf:        %s\n\n' "$RELEASE_VERSION"

if (( ASSUME_YES == 0 )); then
    if [[ ! -t 0 ]]; then
        fail "Ohne interaktive Eingabe muss die Option --yes verwendet werden."
    fi
    read -r -p "Diese Qisutu-Instanz jetzt aktualisieren? [j/N]: " ANSWER
    case "$ANSWER" in
        j|J|ja|Ja|JA|y|Y|yes|Yes|YES) ;;
        *) echo "Update abgebrochen."; exit 0 ;;
    esac
fi

TEMP_ROOT="$(mktemp -d "/tmp/qisutu-update-${INSTANCE_ID}.XXXXXX")"
MYSQL_CONFIG_FILE="$TEMP_ROOT/mysql-client.cnf"
STAGE_ROOT="$(dirname "$TARGET_ROOT")/.$(basename "$TARGET_ROOT").update-$RELEASE_VERSION-$$"
OLD_ROOT="$(dirname "$TARGET_ROOT")/.$(basename "$TARGET_ROOT").rollback-$$"
FAILED_ROOT="$TEMP_ROOT/failed-installation"
TIMESTAMP="$(date '+%Y-%m-%d_%H%M%S')"
BACKUP_DIR="/var/backups/qisutu/$INSTANCE_ID/$TIMESTAMP"
DATABASE_DUMP_FILE="$BACKUP_DIR/database.sql"
RUNTIME_LOCK_DIR="/run/lock/qisutu"
RUNTIME_LOCK_FILE="$RUNTIME_LOCK_DIR/$INSTANCE_ID.runtime.lock"
UPDATE_MANAGER_LOCK_FILE="$RUNTIME_LOCK_DIR/$INSTANCE_ID.update-manager.lock"

SWAPPED=0
DB_CHANGED=0
DATABASE_BACKUP_ENABLED=1
DATABASE_BACKUP_CREATED=0
SYSTEMD_CHANGED=0
MAIL_FETCH_BLOCKED=0
SERVICE_WAS_ACTIVE=0
RUNTIME_LOCK_FD=""

mkdir -p "$RUNTIME_LOCK_DIR"
chown "root:$APACHE_GROUP" "$RUNTIME_LOCK_DIR"
chmod 0770 "$RUNTIME_LOCK_DIR"

exec {UPDATE_MANAGER_FD}>>"$UPDATE_MANAGER_LOCK_FILE"
chown "root:$APACHE_GROUP" "$UPDATE_MANAGER_LOCK_FILE"
chmod 0660 "$UPDATE_MANAGER_LOCK_FILE"
flock -n -x "$UPDATE_MANAGER_FD" || fail "Für diese Qisutu-Instanz läuft bereits ein Update."

trap 'rollback "$LINENO" "$BASH_COMMAND"' ERR

mysql_config_create
"$DB_CLIENT" --defaults-extra-file="$MYSQL_CONFIG_FILE" "$DB_NAME" -e 'SELECT 1' >/dev/null
CURRENT_DATABASE_VERSION="$(database_current_version_get)"
version_is_valid "$CURRENT_DATABASE_VERSION" || fail "Die aktuelle Datenbankversion konnte nicht aus database_version gelesen werden."

printf 'Datenbankstand:       %s\n' "$CURRENT_DATABASE_VERSION"
printf 'Erforderlicher Stand: %s\n\n' "$TARGET_DATABASE_VERSION"

if (( ASSUME_YES == 0 )); then
    printf 'Datenbanksicherung vor dem Update\n'
    printf '  Die vollständige Datenbank wird unter folgendem Pfad gesichert:\n'
    printf '  %s\n\n' "$DATABASE_DUMP_FILE"
    printf '  ACHTUNG: Bei großen Qisutu-Installationen mit vielen Tickets und\n'
    printf '  Anhängen kann diese Sicherung sehr viel Speicherplatz benötigen.\n'
    printf '  Stelle vor dem Fortfahren sicher, dass auf dem Datenträger unter\n'
    printf '  /var/backups genügend freier Plattenplatz vorhanden ist.\n\n'
    printf '  Ohne Datenbanksicherung können Datenbankänderungen bei einem\n'
    printf '  fehlgeschlagenen Update nicht automatisch zurückgesetzt werden.\n\n'

    while true; do
        read -r -p "Soll die Datenbank vor dem Update vollständig gesichert werden? [J/n]: " BACKUP_ANSWER
        case "$BACKUP_ANSWER" in
            ""|j|J|ja|Ja|JA|y|Y|yes|Yes|YES)
                DATABASE_BACKUP_ENABLED=1
                break
                ;;
            n|N|nein|Nein|NEIN|no|No|NO)
                DATABASE_BACKUP_ENABLED=0
                break
                ;;
            *)
                echo "Bitte antworte mit j oder n."
                ;;
        esac
    done
fi

if (( DATABASE_BACKUP_ENABLED == 1 )) && [[ -z "$DB_DUMP_CLIENT" ]]; then
    fail "Für die gewählte Datenbanksicherung wurde weder mariadb-dump noch mysqldump gefunden."
fi

if version_gt "$CURRENT_DATABASE_VERSION" "$TARGET_DATABASE_VERSION"; then
    fail "Die vorhandene Datenbankversion $CURRENT_DATABASE_VERSION ist neuer als das Updatepaket erwartet."
fi

printf 'Prüfe die Perl-Dateien des Updatepakets.\n'
perl_syntax_check "$SOURCE_ROOT"

mkdir -p "$BACKUP_DIR/systemd" "$BACKUP_DIR/apache"
chmod 0700 "$BACKUP_DIR"
cp -a "$INSTANCE_CONFIG_FILE" "$BACKUP_DIR/instance.conf"
cp -a "$TARGET_ROOT/core/config/QisutuConfig.pm" "$BACKUP_DIR/QisutuConfig.pm"
cp -a "$SYSTEMD_FILE" "$BACKUP_DIR/systemd/$DAEMON_SERVICE"

for apache_file in \
    "/etc/apache2/sites-available/$APACHE_CONF_NAME" \
    "/etc/apache2/sites-enabled/$APACHE_CONF_NAME" \
    "/etc/apache2/conf-available/$APACHE_CONF_NAME" \
    "/etc/apache2/conf-enabled/$APACHE_CONF_NAME" \
    "/etc/httpd/conf.d/$APACHE_CONF_NAME"; do
    if [[ -e "$apache_file" || -L "$apache_file" ]]; then
        cp -a "$apache_file" "$BACKUP_DIR/apache/$(echo "$apache_file" | sed 's|/|_|g')"
    fi
done

echo "Sichere den vorhandenen Programmstand."
tar --numeric-owner -czpf "$BACKUP_DIR/program.tar.gz" \
    -C "$(dirname "$TARGET_ROOT")" "$(basename "$TARGET_ROOT")"

if systemctl is-active --quiet "$DAEMON_SERVICE"; then
    SERVICE_WAS_ACTIVE=1
fi

touch "$UPDATE_LOCK_FILE"
chown "$APACHE_USER:$APACHE_GROUP" "$UPDATE_LOCK_FILE"
chmod 0660 "$UPDATE_LOCK_FILE"

echo "Stoppe den Daemon $DAEMON_SERVICE."
systemctl stop "$DAEMON_SERVICE"
if systemctl is-active --quiet "$DAEMON_SERVICE"; then
    fail "Der Daemon $DAEMON_SERVICE konnte nicht gestoppt werden."
fi

mail_fetch_block

touch "$RUNTIME_LOCK_FILE"
chown "$APACHE_USER:$APACHE_GROUP" "$RUNTIME_LOCK_FILE"
chmod 0660 "$RUNTIME_LOCK_FILE"
exec {RUNTIME_LOCK_FD}>>"$RUNTIME_LOCK_FILE"
echo "Warte, bis laufende Prozesse dieser Instanz beendet sind."
flock -x "$RUNTIME_LOCK_FD"

if (( DATABASE_BACKUP_ENABLED == 1 )); then
    echo "Sichere die bestehende Datenbank $DB_NAME."
    "$DB_DUMP_CLIENT" \
        --defaults-extra-file="$MYSQL_CONFIG_FILE" \
        --single-transaction \
        --quick \
        --routines \
        --events \
        --triggers \
        --hex-blob \
        --default-character-set=utf8mb4 \
        --databases "$DB_NAME" \
        --add-drop-database > "$DATABASE_DUMP_FILE"
    chmod 0600 "$DATABASE_DUMP_FILE"
    [[ -s "$DATABASE_DUMP_FILE" ]] || fail "Die Datenbanksicherung ist leer."
    DATABASE_BACKUP_CREATED=1
else
    echo "Die Datenbanksicherung wurde auf Wunsch übersprungen."
fi

stage_prepare
perl_syntax_check "$STAGE_ROOT"
database_schema_synchronize
database_migrations_apply "$CURRENT_DATABASE_VERSION"
database_target_version_record

rm -rf "$OLD_ROOT"
mv "$TARGET_ROOT" "$OLD_ROOT"
mv "$STAGE_ROOT" "$TARGET_ROOT"
SWAPPED=1
MAIL_FETCH_BLOCKED=0

# Nach dem atomaren Austausch werden Besitzer und Rechte nochmals direkt auf
# dem endgültigen Installationspfad gesetzt. Das verhindert, dass Daemon oder
# Cronjob mit den Eigentümern/Rechten des entpackten Updatepakets arbeiten.
installation_permissions_apply "$TARGET_ROOT"

daemon_service_render
systemctl daemon-reload
apache_config_test

INSTALLED_VERSION_AFTER="$(config_value_get program_version)"
[[ "$INSTALLED_VERSION_AFTER" == "$RELEASE_VERSION" ]] || fail "Die installierte Programmversion ist nach dem Austausch nicht korrekt."

DATABASE_VERSION_AFTER="$(database_current_version_get)"
[[ "$DATABASE_VERSION_AFTER" == "$TARGET_DATABASE_VERSION" ]] || fail "Die Datenbankversion ist nach dem Update nicht korrekt."

perl_syntax_check "$TARGET_ROOT"

rm -f "$UPDATE_LOCK_FILE"

if (( SERVICE_WAS_ACTIVE == 1 )); then
    echo "Starte den Daemon $DAEMON_SERVICE."
    systemctl start "$DAEMON_SERVICE"
    systemctl is-active --quiet "$DAEMON_SERVICE" || fail "Der Daemon $DAEMON_SERVICE läuft nach dem Update nicht."
fi

flock -u "$RUNTIME_LOCK_FD"
rm -rf "$OLD_ROOT"
rm -rf "$TEMP_ROOT"
trap - ERR

printf '\nQisutu wurde erfolgreich aktualisiert.\n'
printf '  Instanz:      %s\n' "$INSTANCE_ID"
printf '  Version:      %s\n' "$RELEASE_VERSION"
printf '  DB-Stand:     %s\n' "$TARGET_DATABASE_VERSION"
printf '  Sicherung:    %s\n' "$BACKUP_DIR"
if (( DATABASE_BACKUP_CREATED == 1 )); then
    printf '  DB-Sicherung: erstellt\n'
else
    printf '  DB-Sicherung: nicht erstellt\n'
fi
printf '  Webadresse:   %s\n' "$WEB_PATH"
