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
  sudo ./update.sh
  sudo ./update.sh /opt/qisutu
  sudo ./update.sh /opt/qisutu-test

Optionen:
  --yes       Rückfragen überspringen und eine Datenbanksicherung erstellen
  --help      Diese Hilfe anzeigen

Das Updatepaket ist das Verzeichnis, in dem dieses update.sh liegt.
Ohne Pfadangabe wird die Installation unter /opt/qisutu aktualisiert.
Ein angegebener Pfad muss auf eine bereits installierte Qisutu-Instanz zeigen.
Die Programmdateien werden direkt in dieser Installation aktualisiert.
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

ensure_net_ldap_module() {
    local os_id=""
    local os_like=""
    local package_manager=""

    perl -MNet::LDAP -e 1 >/dev/null 2>&1 && return

    if [[ -r /etc/os-release ]]; then
        # shellcheck disable=SC1091
        . /etc/os-release
        os_id="${ID:-}"
        os_like="${ID_LIKE:-}"
    fi

    echo "Das benötigte Perl-Modul Net::LDAP wird installiert."
    case " $os_id $os_like " in
        *" debian "*|*" ubuntu "*)
            command_required apt-get
            export DEBIAN_FRONTEND=noninteractive
            apt-get update
            apt-get install -y libnet-ldap-perl
            ;;
        *" rhel "*|*" fedora "*|*" centos "*|*" rocky "*|*" almalinux "*)
            package_manager="dnf"
            command -v dnf >/dev/null 2>&1 || package_manager="yum"
            command_required "$package_manager"
            "$package_manager" install -y perl-LDAP
            ;;
        *" suse "*|*" opensuse "*|*" sles "*)
            command_required zypper
            zypper --non-interactive install perl-LDAP
            ;;
        *)
            fail "Net::LDAP fehlt. Installiere das Paket für Net::LDAP mit der Paketverwaltung und starte das Update erneut."
            ;;
    esac

    perl -MNet::LDAP -e 1 >/dev/null 2>&1 \
        || fail "Das Perl-Modul Net::LDAP ist nach der Paketinstallation weiterhin nicht verfügbar."
}

ensure_qisutu_runtime_user() {
    local nologin_shell="/usr/sbin/nologin"

    if [[ ! -x "$nologin_shell" ]]; then
        nologin_shell="/sbin/nologin"
    fi
    if [[ ! -x "$nologin_shell" ]]; then
        nologin_shell="/bin/false"
    fi

    if ! id "$QISUTU_RUNTIME_USER" >/dev/null 2>&1; then
        useradd \
            --system \
            --no-create-home \
            --home-dir /nonexistent \
            --shell "$nologin_shell" \
            --gid "$APACHE_GROUP" \
            "$QISUTU_RUNTIME_USER"
    fi

    usermod -a -G "$APACHE_GROUP" "$QISUTU_RUNTIME_USER"
}

daemon_runtime_user_migrate() {
    case "$APACHE_USER" in
        "$QISUTU_RUNTIME_USER")
            return
            ;;
        www-data|apache|wwwrun)
            sed -i "s/^User=.*/User=$QISUTU_RUNTIME_USER/" "$SYSTEMD_FILE"
            grep -Fxq "User=$QISUTU_RUNTIME_USER" "$SYSTEMD_FILE" \
                || fail "Der Laufzeitbenutzer konnte im Daemon-Dienst nicht korrigiert werden."
            DAEMON_USER_CHANGED=1
            systemctl daemon-reload
            ;;
        *)
            printf 'Hinweis: Der individuell konfigurierte Daemon-Benutzer %s bleibt unverändert.\n' "$APACHE_USER"
            ;;
    esac
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
    local file check_output

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

program_registry_check() {
    local root="$1"

    QISUTU_HOME="$root" perl \
        -I"$root/core/config" \
        -I"$root/core/system" \
        -I"$root/core/output" \
        -I"$root/core/module" \
        -MQisutuConfig \
        -MQisutuOutput \
        -MQisutuProgramRegistry \
        -e '
            use strict;
            use warnings;
            use File::Spec;

            my $Config = QisutuConfig::Load();
            my $ProgramPath = $Config->{Paths}->{ProgramConfig}
                || File::Spec->catdir( $Config->{Paths}->{Config}, q{programs} );

            opendir my $DH, $ProgramPath
                or die "Program config directory cannot be opened: $ProgramPath: $!\n";
            my @Files = sort grep { /[.]pm\z/ } readdir $DH;
            closedir $DH;

            die "No program registrations found in $ProgramPath\n" if !@Files;

            my %Name;
            my @Program;

            for my $File (@Files) {
                my $FullPath = File::Spec->catfile( $ProgramPath, $File );
                my $Program = do $FullPath;
                if ( !defined $Program ) {
                    my $Error = $@ || $! || q{unknown error};
                    die "Program registration cannot be loaded: $FullPath: $Error\n";
                }
                die "Program registration does not return a hash: $FullPath\n"
                    if ref $Program ne q{HASH};

                my $Name = $Program->{Name} || q{};
                my $Module = $Program->{Module} || q{};
                my $Type = $Program->{Type} || q{ProgramOnly};

                die "Program registration has no Name: $FullPath\n" if !$Name;
                die "Duplicate program registration: $Name\n" if $Name{$Name}++;
                die "Program registration has no Module: $FullPath\n" if !$Module;
                die "Invalid module name in program registration $Name: $Module\n"
                    if $Module !~ m{\A[A-Za-z_][A-Za-z0-9_:]*\z};
                die "Invalid program type in $Name: $Type\n"
                    if $Type !~ m{\A(?:MainNavigation|SubNavigation|ProgramOnly)\z};

                push @Program, $Program;
            }

            for my $Program (@Program) {
                next if ( $Program->{Type} || q{ProgramOnly} ) ne q{SubNavigation};
                my $Parent = $Program->{Parent} || q{};
                die "Sub-navigation program has no parent: $Program->{Name}\n" if !$Parent;
                die "Parent program is not registered for $Program->{Name}: $Parent\n"
                    if !$Name{$Parent};
            }

            my $Output = QisutuOutput->new( Config => $Config );
            my $Registry = QisutuProgramRegistry->new(
                Config => $Config,
                Output => $Output,
            );
            my $Registered = $Registry->Programs();
            my $LastError = $Registry->Error() || q{};
            die "Program registry error: $LastError\n" if $LastError;
            die "Program registry count differs from program files\n"
                if @{$Registered} != @Program;

            for my $Program (@Program) {
                my $Name = $Program->{Name};
                die "Program is missing from registry: $Name\n"
                    if !$Registry->ProgramGet( Name => $Name );
            }
        '
}


program_version_patch() {
    local config_file="$1"

    RELEASE_VERSION_ENV="$RELEASE_VERSION" perl -0pi -e '
        my $version = $ENV{RELEASE_VERSION_ENV};
        my $count = s{(Version\s*=>\s*)\x27[^\x27]*\x27}{$1 . "\x27" . $version . "\x27"}e;
        die "Qisutu program version could not be updated\n" if $count != 1;
    ' "$config_file"
}

config_preservation_snapshot() {
    cp -p "$TARGET_ROOT/core/config/QisutuConfig.pm" "$CONFIG_BEFORE_FILE"
    cp -p "$TARGET_ROOT/var/install/instance.conf" "$INSTANCE_BEFORE_FILE"
}

config_preservation_verify() {
    local before_normalized="$TEMP_ROOT/QisutuConfig.before.normalized"
    local after_normalized="$TEMP_ROOT/QisutuConfig.after.normalized"

    cp -p "$CONFIG_BEFORE_FILE" "$before_normalized"
    cp -p "$TARGET_ROOT/core/config/QisutuConfig.pm" "$after_normalized"

    perl -0pi -e "s{(Version\\s*=>\\s*)'[^']*'}{\$1'__QISUTU_VERSION__'}g" "$before_normalized" "$after_normalized"

    cmp -s "$before_normalized" "$after_normalized" \
        || fail "QisutuConfig.pm wurde außerhalb der Programmversion verändert."
    cmp -s "$INSTANCE_BEFORE_FILE" "$TARGET_ROOT/var/install/instance.conf" \
        || fail "Die bestehende instance.conf wurde beim Update verändert."
}

manifest_path_validate() {
    local manifest_path="$1"
    local relative_path

    if [[ "$manifest_path" != ./* ]]; then
        fail "Ungültiger Dateipfad in release.sha256: $manifest_path"
        return 1
    fi
    relative_path="${manifest_path#./}"
    if [[ -z "$relative_path" ]]; then
        fail "Leerer Dateipfad in release.sha256."
        return 1
    fi
    if [[ "$relative_path" == *[[:space:]]* ]]; then
        fail "Dateipfade mit Leerzeichen sind im Updatepaket nicht zulässig: $relative_path"
        return 1
    fi
    case "/$relative_path/" in
        *"/../"*|*"/./"*|*"//"*)
            fail "Unsicherer Dateipfad in release.sha256: $relative_path"
            return 1
            ;;
    esac
    printf '%s' "$relative_path"
}

path_is_protected() {
    local relative_path="$1"

    case "$relative_path" in
        addons|addons/*) return 0 ;;
        core/config/QisutuConfig.pm) return 0 ;;
        var/install|var/install/*) return 0 ;;
        var/log|var/log/*) return 0 ;;
        var/cache|var/cache/*) return 0 ;;
        var/tmp|var/tmp/*) return 0 ;;
        var/static/addons|var/static/addons/*) return 0 ;;
        var/secure|var/secure/*) return 0 ;;
        scriptfiles/"$INSTANCE_ID"-apache-runtime.conf) return 0 ;;
    esac

    return 1
}

removed_path_validate() {
    local removal_path="$1"
    local relative_path

    relative_path="$(manifest_path_validate "$removal_path")"

    case "$relative_path" in
        release.sha256|release.remove|release.conf|install.sh|update.sh)
            fail "Release-Steuerdatei darf nicht als veraltet markiert werden: $relative_path"
            return 1
            ;;
    esac

    if path_is_protected "$relative_path"; then
        fail "Geschützter Installationspfad darf nicht als veraltet markiert werden: $relative_path"
        return 1
    fi

    printf '%s' "$relative_path"
}

package_manifest_source_validate() {
    local manifest_file="$SOURCE_ROOT/release.sha256"
    local removal_file="$SOURCE_ROOT/release.remove"
    local checksum manifest_path extra relative_path source_file source_symlink check_output removal_line removal_path
    local -A manifest_paths=()
    local -A removed_paths=()
    local manifest_count=0

    [[ -r "$manifest_file" ]] || fail "Prüfsummenliste des Updatepakets fehlt oder ist nicht lesbar: $manifest_file"

    while read -r checksum manifest_path extra; do
        [[ -n "$checksum" || -n "$manifest_path" || -n "$extra" ]] || continue
        [[ -z "${extra:-}" ]] || fail "Ungültiger Eintrag in release.sha256: $checksum $manifest_path $extra"
        [[ "$checksum" =~ ^[0-9a-f]{64}$ ]] || fail "Ungültige SHA-256-Prüfsumme in release.sha256: $checksum"
        relative_path="$(manifest_path_validate "$manifest_path")"
        [[ -z "${manifest_paths[$relative_path]+x}" ]] || fail "Doppelter Dateipfad in release.sha256: $relative_path"
        [[ -f "$SOURCE_ROOT/$relative_path" && ! -L "$SOURCE_ROOT/$relative_path" ]] \
            || fail "Datei aus release.sha256 fehlt im Updatepaket: $relative_path"
        manifest_paths["$relative_path"]=1
        manifest_count=$(( manifest_count + 1 ))
    done < "$manifest_file"

    (( manifest_count > 0 )) || fail "release.sha256 enthält keine Programmdateien."
    [[ -n "${manifest_paths[release.remove]+x}" ]] \
        || fail "release.remove fehlt in release.sha256."

    if ! check_output="$(cd "$SOURCE_ROOT" && sha256sum --check --quiet release.sha256 2>&1)"; then
        echo "$check_output" >&2
        fail "Die Prüfsummen des Qisutu-Updatepakets sind ungültig. Das Paket wird nicht installiert."
    fi

    while IFS= read -r removal_line || [[ -n "$removal_line" ]]; do
        removal_line="$(trim "$removal_line")"
        [[ -n "$removal_line" ]] || continue
        [[ "$removal_line" == \#* ]] && continue

        read -r removal_path extra <<< "$removal_line"
        [[ -z "${extra:-}" ]] || fail "Ungültiger Eintrag in release.remove: $removal_line"
        relative_path="$(removed_path_validate "$removal_path")"
        [[ -z "${removed_paths[$relative_path]+x}" ]] \
            || fail "Doppelter Dateipfad in release.remove: $relative_path"
        [[ -z "${manifest_paths[$relative_path]+x}" ]] \
            || fail "Dateipfad steht gleichzeitig in release.sha256 und release.remove: $relative_path"
        removed_paths["$relative_path"]=1
    done < "$removal_file"

    while IFS= read -r -d '' source_file; do
        relative_path="${source_file#"$SOURCE_ROOT/"}"
        [[ "$relative_path" == "release.sha256" ]] && continue
        [[ -n "${manifest_paths[$relative_path]+x}" || -n "${removed_paths[$relative_path]+x}" ]] \
            || fail "Programmdatei ist nicht in release.sha256 eingetragen: $relative_path"
    done < <(find "$SOURCE_ROOT" -type f -print0)

    while IFS= read -r -d '' source_symlink; do
        relative_path="${source_symlink#"$SOURCE_ROOT/"}"
        [[ -n "${removed_paths[$relative_path]+x}" ]] && continue
        fail "Symbolische Links sind im Updatepaket nicht zulässig: $relative_path"
    done < <(find "$SOURCE_ROOT" -type l -print0)
}

package_obsolete_source_files_remove() {
    local removal_line removal_path relative_path source_file extra
    local removed_count=0

    while IFS= read -r removal_line || [[ -n "$removal_line" ]]; do
        removal_line="$(trim "$removal_line")"
        [[ -n "$removal_line" ]] || continue
        [[ "$removal_line" == \#* ]] && continue

        read -r removal_path extra <<< "$removal_line"
        relative_path="$(removed_path_validate "$removal_path")"
        source_file="$SOURCE_ROOT/$relative_path"

        if [[ -d "$source_file" && ! -L "$source_file" ]]; then
            fail "Eine veraltete Programmdatei ist im Updatepaket ein Verzeichnis: $relative_path"
        fi
        if [[ -e "$source_file" || -L "$source_file" ]]; then
            rm -f -- "$source_file"
            removed_count=$(( removed_count + 1 ))
        fi
    done < "$SOURCE_ROOT/release.remove"

    printf 'Veraltete Dateien aus dem Updateverzeichnis entfernt: %d\n' "$removed_count"
}

database_migration_package_validate() {
    local migrations_root="$SOURCE_ROOT/install/update/database"
    local migration_version version_directory migration_file migration_name file_count
    local -A migration_keys=()

    [[ -d "$migrations_root" ]] || fail "Verzeichnis für kumulative Datenmigrationen fehlt im Updatepaket: $migrations_root"

    while IFS= read -r migration_version; do
        [[ -n "$migration_version" ]] || continue
        version_is_valid "$migration_version" || fail "Ungültiges Datenmigrationsverzeichnis: $migration_version"
        version_le "$migration_version" "$TARGET_DATABASE_VERSION" \
            || fail "Die Datenmigration $migration_version ist neuer als der erwartete Datenbankstand $TARGET_DATABASE_VERSION."

        version_directory="$migrations_root/$migration_version"
        file_count=0
        while IFS= read -r -d '' migration_file; do
            file_count=$(( file_count + 1 ))
            migration_name="$(basename "$migration_file")"
            [[ "$migration_name" =~ ^[0-9]{3,}-[A-Za-z0-9][A-Za-z0-9._-]*\.(sql|pl)$ ]] \
                || fail "Ungültiger Dateiname einer Datenmigration: $migration_file"
            [[ ! -L "$migration_file" ]] || fail "Symbolische Links sind für Datenmigrationen nicht zulässig: $migration_file"
            [[ -z "${migration_keys[$migration_version/$migration_name]+x}" ]] \
                || fail "Doppelte Datenmigration im Updatepaket: $migration_version/$migration_name"
            migration_keys["$migration_version/$migration_name"]=1
        done < <(find "$version_directory" -maxdepth 1 -type f \( -name '*.sql' -o -name '*.pl' \) -print0 | sort -zV)

        (( file_count > 0 )) || fail "Das Datenmigrationsverzeichnis $version_directory enthält keine .sql- oder .pl-Datei."
    done < <(find "$migrations_root" -mindepth 1 -maxdepth 1 -type d -printf '%f\n' | sort -V)
}


database_migrations_preflight() {
    local migrations_root="$SOURCE_ROOT/install/update/database"
    local migration_version migration_file migration_name migration_key
    local table_exists stored_key stored_checksum extra
    local -A package_keys=()

    while IFS= read -r migration_version; do
        [[ -n "$migration_version" ]] || continue
        while IFS= read -r -d '' migration_file; do
            migration_name="$(basename "$migration_file")"
            migration_key="$migration_version/$migration_name"
            package_keys["$migration_key"]=1
        done < <(find "$migrations_root/$migration_version" -maxdepth 1 -type f \( -name '*.sql' -o -name '*.pl' \) -print0 | sort -zV)
    done < <(find "$migrations_root" -mindepth 1 -maxdepth 1 -type d -printf '%f\n' | sort -V)

    table_exists="$(
        "$DB_CLIENT" --defaults-extra-file="$MYSQL_CONFIG_FILE" --batch --skip-column-names "$DB_NAME" \
            -e "SELECT COUNT(*) FROM INFORMATION_SCHEMA.TABLES WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'database_migration' AND TABLE_TYPE = 'BASE TABLE'"
    )"

    [[ "$table_exists" == "0" || "$table_exists" == "1" ]] \
        || fail "Die Tabelle database_migration konnte nicht eindeutig geprüft werden."

    if [[ "$table_exists" == "0" ]]; then
        echo "Für diese Installation existiert noch kein Migrationsprotokoll."
        return
    fi

    while IFS=$'\t' read -r stored_key stored_checksum extra; do
        [[ -n "${stored_key:-}" ]] || continue
        [[ -z "${extra:-}" ]] || fail "Ungültiger Datensatz in database_migration: $stored_key"
        [[ -n "${package_keys[$stored_key]+x}" ]] \
            || fail "Eine bereits protokollierte Datenmigration fehlt im Updatepaket: $stored_key"
        [[ "$stored_checksum" =~ ^[0-9a-f]{64}$ ]] \
            || fail "Ungültige gespeicherte Prüfsumme für die Datenmigration: $stored_key"
    done < <(
        "$DB_CLIENT" --defaults-extra-file="$MYSQL_CONFIG_FILE" --batch --skip-column-names "$DB_NAME" \
            -e "SELECT migration_key, checksum_sha256 FROM database_migration ORDER BY migration_key"
    )

    echo "Alle bereits protokollierten Datenmigrationen sind im Updatepaket enthalten."
}

old_manifest_snapshot() {
    if [[ -f "$TARGET_ROOT/release.sha256" && ! -L "$TARGET_ROOT/release.sha256" ]]; then
        cp -p "$TARGET_ROOT/release.sha256" "$OLD_MANIFEST_FILE"
    else
        : > "$OLD_MANIFEST_FILE"
    fi
}

obsolete_managed_files_remove() {
    local checksum manifest_path extra relative_path target_file removal_line removal_path
    local -A new_paths=()
    local -A explicitly_removed_paths=()
    local removed_count=0

    while read -r checksum manifest_path extra; do
        [[ -n "$checksum" || -n "$manifest_path" || -n "$extra" ]] || continue
        relative_path="$(manifest_path_validate "$manifest_path")"
        new_paths["$relative_path"]=1
    done < "$SOURCE_ROOT/release.sha256"

    while IFS= read -r removal_line || [[ -n "$removal_line" ]]; do
        removal_line="$(trim "$removal_line")"
        [[ -n "$removal_line" ]] || continue
        [[ "$removal_line" == \#* ]] && continue

        read -r removal_path extra <<< "$removal_line"
        relative_path="$(removed_path_validate "$removal_path")"
        explicitly_removed_paths["$relative_path"]=1
        target_file="$TARGET_ROOT/$relative_path"

        if [[ -d "$target_file" && ! -L "$target_file" ]]; then
            fail "Eine veraltete Programmdatei ist im Ziel ein Verzeichnis: $relative_path"
        fi
        if [[ -e "$target_file" || -L "$target_file" ]]; then
            rm -f -- "$target_file"
            removed_count=$(( removed_count + 1 ))
            FILES_CHANGED=1
        fi
    done < "$SOURCE_ROOT/release.remove"

    while read -r checksum manifest_path extra; do
        [[ -n "$checksum" || -n "$manifest_path" || -n "$extra" ]] || continue
        [[ "$checksum" =~ ^[0-9a-f]{64}$ ]] || continue
        relative_path="$(manifest_path_validate "$manifest_path")"
        [[ -z "${new_paths[$relative_path]+x}" ]] || continue
        [[ -z "${explicitly_removed_paths[$relative_path]+x}" ]] || continue
        path_is_protected "$relative_path" && continue

        target_file="$TARGET_ROOT/$relative_path"
        if [[ -d "$target_file" && ! -L "$target_file" ]]; then
            fail "Eine nicht mehr benötigte Programmdatei ist im Ziel ein Verzeichnis: $relative_path"
        fi
        if [[ -e "$target_file" || -L "$target_file" ]]; then
            rm -f -- "$target_file"
            removed_count=$(( removed_count + 1 ))
            FILES_CHANGED=1
        fi
    done < "$OLD_MANIFEST_FILE"

    printf 'Nicht mehr benötigte verwaltete Dateien entfernt: %d\n' "$removed_count"
}

package_files_copy_direct() {
    local checksum manifest_path extra relative_path target_file
    local created_count=0 updated_count=0 protected_count=0
    local -a copy_paths=()

    echo "Übertrage die Programmdateien direkt nach $TARGET_ROOT."
    FILES_CHANGED=1

    while read -r checksum manifest_path extra; do
        [[ -n "$checksum" || -n "$manifest_path" || -n "$extra" ]] || continue
        relative_path="$(manifest_path_validate "$manifest_path")"

        if path_is_protected "$relative_path"; then
            protected_count=$(( protected_count + 1 ))
            continue
        fi

        target_file="$TARGET_ROOT/$relative_path"
        [[ ! -d "$target_file" || -L "$target_file" ]] \
            || fail "Eine Programmdatei kann nicht übertragen werden, weil im Ziel ein Verzeichnis existiert: $relative_path"

        if [[ -e "$target_file" || -L "$target_file" ]]; then
            updated_count=$(( updated_count + 1 ))
        else
            created_count=$(( created_count + 1 ))
        fi

        rm -f -- "$target_file"
        copy_paths+=("./$relative_path")
    done < "$SOURCE_ROOT/release.sha256"

    if (( ${#copy_paths[@]} > 0 )); then
        (
            cd "$SOURCE_ROOT"
            cp -p --parents -- "${copy_paths[@]}" "$TARGET_ROOT"
        )
    fi

    cp -p -- "$SOURCE_ROOT/release.sha256" "$TARGET_ROOT/release.sha256"
    FILES_CHANGED=1

    printf 'Programmdateien: %d neu, %d aktualisiert, %d geschützt.\n' \
        "$created_count" "$updated_count" "$protected_count"
}

installation_permissions_apply() {
    local checksum manifest_path extra relative_path target_file source_directory relative_directory target_directory
    local security_key_file previous_umask
    local -a managed_files=()
    local -a managed_directories=()

    chown "$TARGET_OWNER:$TARGET_GROUP" "$TARGET_ROOT"
    chmod 0755 "$TARGET_ROOT"

    while IFS= read -r -d '' source_directory; do
        [[ "$source_directory" != "$SOURCE_ROOT" ]] || continue
        relative_directory="${source_directory#"$SOURCE_ROOT/"}"
        path_is_protected "$relative_directory" && continue
        target_directory="$TARGET_ROOT/$relative_directory"
        mkdir -p "$target_directory"
        managed_directories+=("$target_directory")
    done < <(find "$SOURCE_ROOT" -type d -print0)

    while read -r checksum manifest_path extra; do
        [[ -n "$checksum" || -n "$manifest_path" || -n "$extra" ]] || continue
        relative_path="$(manifest_path_validate "$manifest_path")"
        path_is_protected "$relative_path" && continue
        target_file="$TARGET_ROOT/$relative_path"
        [[ -f "$target_file" && ! -L "$target_file" ]] || fail "Programmdatei fehlt bei der Rechtevergabe: $relative_path"
        managed_files+=("$target_file")
    done < "$SOURCE_ROOT/release.sha256"

    if (( ${#managed_directories[@]} > 0 )); then
        chown "$TARGET_OWNER:$TARGET_GROUP" "${managed_directories[@]}"
        chmod 0755 "${managed_directories[@]}"
    fi
    if (( ${#managed_files[@]} > 0 )); then
        chown "$TARGET_OWNER:$TARGET_GROUP" "${managed_files[@]}"
        chmod 0644 "${managed_files[@]}"
    fi
    chmod 0755 "$TARGET_ROOT/install.sh" "$TARGET_ROOT/update.sh"
    find "$TARGET_ROOT/bin" -maxdepth 1 -type f -name '*.pl' -exec chmod 0775 {} +
    if [[ -d "$TARGET_ROOT/bin/cgi-bin" ]]; then
        find "$TARGET_ROOT/bin/cgi-bin" -maxdepth 1 -type f -name '*.pl' -exec chmod 0755 {} +
    fi

    for target_directory in var/install var/log var/cache var/tmp; do
        mkdir -p "$TARGET_ROOT/$target_directory"
        chown "$TARGET_OWNER:$TARGET_GROUP" "$TARGET_ROOT/$target_directory"
        chmod 0770 "$TARGET_ROOT/$target_directory"
    done

    mkdir -p "$TARGET_ROOT/addons" "$TARGET_ROOT/var/static/addons"
    chown "$TARGET_OWNER:$TARGET_GROUP" "$TARGET_ROOT/addons" "$TARGET_ROOT/var/static/addons"
    chmod 0755 "$TARGET_ROOT/addons" "$TARGET_ROOT/var/static/addons"

    mkdir -p "$TARGET_ROOT/var/secure"
    chown root:"$APACHE_GROUP" "$TARGET_ROOT/var/secure"
    chmod 0750 "$TARGET_ROOT/var/secure"
    security_key_file="$TARGET_ROOT/var/secure/security.key"
    if [[ ! -f "$security_key_file" ]]; then
        previous_umask="$(umask)"
        umask 0137
        od -An -N32 -tx1 /dev/urandom | tr -d ' \n' > "$security_key_file"
        printf '\n' >> "$security_key_file"
        umask "$previous_umask"
    fi
    chown root:"$APACHE_GROUP" "$security_key_file"
    chmod 0640 "$security_key_file"
    [[ "$(tr -d '[:space:]' < "$security_key_file")" =~ ^[0-9a-fA-F]{64}$ ]] \
        || fail "Der installationsabhängige Sicherheitsschlüssel ist ungültig."

    chown "$TARGET_OWNER:$TARGET_GROUP" "$TARGET_ROOT/core/config/QisutuConfig.pm"
    chmod 0660 "$TARGET_ROOT/core/config/QisutuConfig.pm"

    chown "$TARGET_OWNER:$TARGET_GROUP" "$TARGET_ROOT/var/install/instance.conf"
    chmod 0640 "$TARGET_ROOT/var/install/instance.conf"

    if [[ -f "$TARGET_ROOT/var/install/update.lock" ]]; then
        chown "$TARGET_OWNER:$TARGET_GROUP" "$TARGET_ROOT/var/install/update.lock"
        chmod 0660 "$TARGET_ROOT/var/install/update.lock"
    fi
}

package_tree_verify() {
    local source_manifest_checksum installed_manifest_checksum check_output

    [[ -f "$TARGET_ROOT/release.sha256" && ! -L "$TARGET_ROOT/release.sha256" ]] \
        || fail "release.sha256 fehlt im installierten Programmstand."
    [[ -f "$TARGET_ROOT/core/config/QisutuConfig.pm" && ! -L "$TARGET_ROOT/core/config/QisutuConfig.pm" ]] \
        || fail "Die installationsbezogene QisutuConfig.pm fehlt nach dem Update."

    source_manifest_checksum="$(sha256sum "$SOURCE_ROOT/release.sha256" | awk '{print $1}')"
    installed_manifest_checksum="$(sha256sum "$TARGET_ROOT/release.sha256" | awk '{print $1}')"
    [[ "$installed_manifest_checksum" == "$source_manifest_checksum" ]] \
        || fail "Die installierte release.sha256 stimmt nicht mit dem Updatepaket überein."

    if ! check_output="$(
        cd "$TARGET_ROOT"
        awk '$2 != "./core/config/QisutuConfig.pm" { print }' "$SOURCE_ROOT/release.sha256" \
            | sha256sum --check --quiet - 2>&1
    )"; then
        echo "$check_output" >&2
        fail "Mindestens eine Programmdatei wurde nicht vollständig in die bestehende Installation übertragen."
    fi
}

sql_literal_escape() {
    local value="$1"
    value="${value//\'/\'\'}"
    printf '%s' "$value"
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
    local status_file="$TEMP_ROOT/schema-sync.status"
    local status_key status_value schema_changed=""

    [[ -r "$TARGET_ROOT/install/sql/schema.sql" ]] || fail "Die aktuelle Datenbank-Sollstruktur fehlt."
    [[ -r "$TARGET_ROOT/install/update/QisutuSchemaSync.pl" ]] || fail "Das Programm für den Datenbankabgleich fehlt."

    rm -f "$status_file"

    QISUTU_HOME="$TARGET_ROOT" perl \
        -I"$TARGET_ROOT/core/config" \
        -I"$TARGET_ROOT/core/system" \
        -I"$TARGET_ROOT/core/cpan-lib" \
        "$TARGET_ROOT/install/update/QisutuSchemaSync.pl" \
        --schema "$TARGET_ROOT/install/sql/schema.sql" \
        --status-file "$status_file"

    [[ -r "$status_file" ]] || fail "Der Datenbankabgleich hat keine Statusdatei erzeugt."

    while IFS='=' read -r status_key status_value; do
        case "$status_key" in
            changed) schema_changed="$status_value" ;;
        esac
    done < "$status_file"

    case "$schema_changed" in
        0) ;;
        1) DB_CHANGED=1 ;;
        *) fail "Der Änderungsstatus des Datenbankabgleichs ist ungültig." ;;
    esac
}

database_migrations_apply() {
    local migrations_root="$TARGET_ROOT/install/update/database"
    local version_directory migration_version migration_file migration_name
    local migration_key migration_checksum stored_count stored_mode
    local escaped_key escaped_version escaped_checksum
    local executed_count=0 skipped_count=0 file_count=0

    [[ -d "$migrations_root" ]] || fail "Verzeichnis für kumulative Datenmigrationen fehlt: $migrations_root"

    echo "Prüfe und ergänze die dauerhaft mitgeführten Datenmigrationen."

    while IFS= read -r migration_version; do
        [[ -n "$migration_version" ]] || continue
        version_is_valid "$migration_version" || fail "Ungültiges Datenmigrationsverzeichnis: $migration_version"
        version_le "$migration_version" "$TARGET_DATABASE_VERSION" \
            || fail "Die Datenmigration $migration_version ist neuer als der erwartete Datenbankstand $TARGET_DATABASE_VERSION."

        version_directory="$migrations_root/$migration_version"
        file_count=0

        while IFS= read -r -d '' migration_file; do
            file_count=$(( file_count + 1 ))
            migration_name="$(basename "$migration_file")"
            migration_key="$migration_version/$migration_name"
            (( ${#migration_key} <= 255 )) || fail "Der Schlüssel der Datenmigration ist zu lang: $migration_key"
            migration_checksum="$(sha256sum "$migration_file" | awk '{print $1}')"
            [[ "$migration_checksum" =~ ^[0-9a-f]{64}$ ]] \
                || fail "Die Prüfsumme der Datenmigration ist ungültig: $migration_key"

            escaped_key="$(sql_literal_escape "$migration_key")"
            stored_count="$(
                "$DB_CLIENT" --defaults-extra-file="$MYSQL_CONFIG_FILE" --batch --skip-column-names "$DB_NAME" \
                    -e "SELECT COUNT(*) FROM database_migration WHERE migration_key = '$escaped_key'"
            )"

            if [[ "$stored_count" == "1" ]]; then
                stored_mode="$(
                    "$DB_CLIENT" --defaults-extra-file="$MYSQL_CONFIG_FILE" --batch --skip-column-names "$DB_NAME" \
                        -e "SELECT execution_mode FROM database_migration WHERE migration_key = '$escaped_key' LIMIT 1"
                )"
                echo "  Bereits erledigt: $migration_key (${stored_mode:-protokolliert})"
                skipped_count=$(( skipped_count + 1 ))
                continue
            fi
            [[ "$stored_count" == "0" ]] \
                || fail "Die Datenmigration ist im Migrationsprotokoll nicht eindeutig: $migration_key"

            escaped_version="$(sql_literal_escape "$migration_version")"
            escaped_checksum="$(sql_literal_escape "$migration_checksum")"
            DB_CHANGED=1

            case "$migration_file" in
                *.sql)
                    echo "  SQL ausführen: $migration_key"
                    "$DB_CLIENT" --defaults-extra-file="$MYSQL_CONFIG_FILE" "$DB_NAME" < "$migration_file"
                    ;;
                *.pl)
                    echo "  Perl ausführen: $migration_key"
                    QISUTU_HOME="$TARGET_ROOT" \
                    QISUTU_DATABASE_MIGRATION_VERSION="$migration_version" \
                    QISUTU_DATABASE_MIGRATION_KEY="$migration_key" \
                    perl \
                        -I"$TARGET_ROOT/core/config" \
                        -I"$TARGET_ROOT/core/system" \
                        -I"$TARGET_ROOT/core/cpan-lib" \
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

        (( file_count > 0 )) || fail "Das Datenmigrationsverzeichnis $version_directory enthält keine .sql- oder .pl-Datei."
    done < <(find "$migrations_root" -mindepth 1 -maxdepth 1 -type d -printf '%f\n' | sort -V)

    printf 'Datenmigrationen: %d ausgeführt, %d bereits erledigt.\n' "$executed_count" "$skipped_count"
}


database_migrations_verify() {
    local migrations_root="$TARGET_ROOT/install/update/database"
    local migration_version migration_file migration_name migration_key
    local escaped_key stored_count
    local verified_count=0

    while IFS= read -r migration_version; do
        [[ -n "$migration_version" ]] || continue
        while IFS= read -r -d '' migration_file; do
            migration_name="$(basename "$migration_file")"
            migration_key="$migration_version/$migration_name"
            escaped_key="$(sql_literal_escape "$migration_key")"
            stored_count="$(
                "$DB_CLIENT" --defaults-extra-file="$MYSQL_CONFIG_FILE" --batch --skip-column-names "$DB_NAME" \
                    -e "SELECT COUNT(*) FROM database_migration WHERE migration_key = '$escaped_key'"
            )"
            [[ "$stored_count" == "1" ]] \
                || fail "Die Datenmigration wurde nicht vollständig protokolliert: $migration_key"
            verified_count=$(( verified_count + 1 ))
        done < <(find "$migrations_root/$migration_version" -maxdepth 1 -type f \( -name '*.sql' -o -name '*.pl' \) -print0 | sort -zV)
    done < <(find "$migrations_root" -mindepth 1 -maxdepth 1 -type d -printf '%f\n' | sort -V)

    printf 'Protokollierte Datenmigrationen geprüft: %d\n' "$verified_count"
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

path_state() {
    local path="$1"

    if [[ -L "$path" ]]; then
        printf 'symlink|%s|%s|%s\n' "$(readlink "$path")" "$(stat -c '%U:%G' "$path")" "$(stat -c '%a' "$path")"
    elif [[ -f "$path" ]]; then
        printf 'file|%s|%s|%s\n' "$(sha256sum "$path" | awk '{print $1}')" "$(stat -c '%U:%G' "$path")" "$(stat -c '%a' "$path")"
    elif [[ -e "$path" ]]; then
        printf 'other|%s|%s\n' "$(stat -c '%F' "$path")" "$(stat -c '%U:%G:%a' "$path")"
    else
        printf 'missing\n'
    fi
}

operator_config_snapshot() {
    local path
    : > "$OPERATOR_CONFIG_BEFORE_FILE"

    for path in \
        "/etc/systemd/system/$DAEMON_SERVICE" \
        "/etc/apache2/sites-available/$APACHE_CONF_NAME" \
        "/etc/apache2/sites-enabled/$APACHE_CONF_NAME" \
        "/etc/apache2/conf-available/$APACHE_CONF_NAME" \
        "/etc/apache2/conf-enabled/$APACHE_CONF_NAME" \
        "/etc/httpd/conf.d/$APACHE_CONF_NAME" \
        "$TARGET_ROOT/scriptfiles/$INSTANCE_ID-apache-runtime.conf"; do
        printf '%s\t%s\n' "$path" "$(path_state "$path")" >> "$OPERATOR_CONFIG_BEFORE_FILE"
    done
}

operator_config_verify() {
    local path expected actual

    while IFS=$'\t' read -r path expected; do
        actual="$(path_state "$path")"
        [[ "$actual" == "$expected" ]] || fail "Eine Betreiber-Konfiguration wurde beim Update verändert: $path"
    done < "$OPERATOR_CONFIG_BEFORE_FILE"
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

update_failed() {
    local line="$1"
    local command="$2"

    trap - ERR
    set +e

    echo >&2
    echo "Das Qisutu-Update ist fehlgeschlagen." >&2
    echo "Fehler bei Zeile $line: $command" >&2

    if [[ -n "${RUNTIME_LOCK_FD:-}" ]]; then
        flock -u "$RUNTIME_LOCK_FD" >/dev/null 2>&1
    fi

    if (( FILES_CHANGED == 0 && DB_CHANGED == 0 )); then
        if (( UPDATE_LOCK_CREATED_BY_RUN == 1 )); then
            rm -f "$UPDATE_LOCK_FILE"
        fi
        if (( SERVICE_WAS_ACTIVE == 1 )); then
            systemctl start "$DAEMON_SERVICE" >/dev/null 2>&1
        fi
    else
        echo "Die Wartungssperre bleibt aktiv und der Daemon bleibt gestoppt." >&2
        echo "Behebe den gemeldeten Fehler und führe dasselbe Update erneut aus." >&2
    fi

    rm -rf "${TEMP_ROOT:-}" >/dev/null 2>&1
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

if [[ -z "$TARGET_ARGUMENT" ]]; then
    TARGET_ARGUMENT="/opt/qisutu"
fi

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
QISUTU_RUNTIME_USER="qisutu"
DAEMON_USER_CHANGED=0

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
UPDATE_LOCK_PREEXISTED=0
UPDATE_LOCK_CREATED_BY_RUN=0
if [[ -e "$UPDATE_LOCK_FILE" ]]; then
    UPDATE_LOCK_PREEXISTED=1
fi

[[ -f "$INSTALL_LOCK_FILE" ]] || fail "Der Pfad ist keine vollständig installierte Qisutu-Instanz: installed.lock fehlt."
[[ -f "$TARGET_ROOT/core/config/QisutuConfig.pm" ]] || fail "QisutuConfig.pm fehlt in der ausgewählten Installation."
load_key_value_file "$INSTANCE_CONFIG_FILE" instance
validate_instance_config

command_required perl
command_required find
command_required sort
command_required flock
command_required systemctl
command_required sed
command_required sha256sum
command_required stat
command_required awk
command_required cmp
command_required cp
command_required mv
command_required rm
command_required mkdir
command_required chmod
command_required chown
command_required readlink
command_required openssl
command_required useradd
command_required usermod

package_manifest_source_validate
package_obsolete_source_files_remove
database_migration_package_validate
ensure_net_ldap_module

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
ensure_qisutu_runtime_user
TARGET_OWNER="$QISUTU_RUNTIME_USER"
TARGET_GROUP="$APACHE_GROUP"

CURRENT_PROGRAM_VERSION="$(config_value_get program_version)"
CONFIG_DB_NAME="$(config_value_get database_name)"
CONFIG_INSTANCE_ID="$(config_value_get instance_id)"
version_is_valid "$CURRENT_PROGRAM_VERSION" || fail "Die installierte Qisutu-Programmversion konnte nicht bestimmt werden."
[[ "$CONFIG_DB_NAME" == "$DB_NAME" ]] || fail "Datenbankname in QisutuConfig.pm ($CONFIG_DB_NAME) und instance.conf ($DB_NAME) stimmen nicht überein."
[[ -z "$CONFIG_INSTANCE_ID" || "$CONFIG_INSTANCE_ID" == "$INSTANCE_ID" ]] || fail "Instanzkennung in QisutuConfig.pm ($CONFIG_INSTANCE_ID) und instance.conf ($INSTANCE_ID) stimmen nicht überein."

if version_lt "$CURRENT_PROGRAM_VERSION" "$MINIMUM_PROGRAM_VERSION"; then
    fail "Dieses Update benötigt mindestens Qisutu $MINIMUM_PROGRAM_VERSION. Installiert ist $CURRENT_PROGRAM_VERSION."
fi
if version_gt "$CURRENT_PROGRAM_VERSION" "$RELEASE_VERSION"; then
    fail "Die installierte Version $CURRENT_PROGRAM_VERSION ist neuer als dieses Updatepaket $RELEASE_VERSION."
fi
if [[ "$CURRENT_PROGRAM_VERSION" == "$RELEASE_VERSION" && ! -f "$UPDATE_LOCK_FILE" ]]; then
    fail "Qisutu $RELEASE_VERSION ist bereits vollständig installiert."
fi

printf '\nAusgewählte Qisutu-Instanz\n'
printf '  Installationspfad: %s\n' "$TARGET_ROOT"
printf '  Instanzkennung:    %s\n' "$INSTANCE_ID"
printf '  Webpfad:           %s\n' "$WEB_PATH"
printf '  Datenbank:         %s\n' "$DB_NAME"
printf '  Daemon:            %s\n' "$DAEMON_SERVICE"
printf '  Besitzer:          %s:%s\n' "$TARGET_OWNER" "$TARGET_GROUP"
printf '  Installiert:       %s\n' "$CURRENT_PROGRAM_VERSION"
printf '  Update auf:        %s\n' "$RELEASE_VERSION"
if (( UPDATE_LOCK_PREEXISTED == 1 )); then
    printf '  Zustand:           Fortsetzung eines nicht abgeschlossenen Updates\n'
fi
printf '\n'

if (( ASSUME_YES == 0 )); then
    if [[ ! -t 0 ]]; then
        fail "Ohne interaktive Eingabe muss die Option --yes verwendet werden."
    fi
    read -r -p "Diese Qisutu-Instanz jetzt direkt aktualisieren? [j/N]: " ANSWER
    case "$ANSWER" in
        j|J|ja|Ja|JA|y|Y|yes|Yes|YES) ;;
        *) echo "Update abgebrochen."; exit 0 ;;
    esac
fi

TEMP_ROOT="$(mktemp -d "/tmp/qisutu-update-${INSTANCE_ID}.XXXXXX")"
MYSQL_CONFIG_FILE="$TEMP_ROOT/mysql-client.cnf"
OLD_MANIFEST_FILE="$TEMP_ROOT/release.sha256.old"
CONFIG_BEFORE_FILE="$TEMP_ROOT/QisutuConfig.pm.before"
INSTANCE_BEFORE_FILE="$TEMP_ROOT/instance.conf.before"
OPERATOR_CONFIG_BEFORE_FILE="$TEMP_ROOT/operator-config.before"
TIMESTAMP="$(date '+%Y-%m-%d_%H%M%S')"
BACKUP_DIR="/var/backups/qisutu/$INSTANCE_ID/$TIMESTAMP"
DATABASE_DUMP_FILE="$BACKUP_DIR/database.sql"
RUNTIME_LOCK_DIR="/run/lock/qisutu"
RUNTIME_LOCK_FILE="$RUNTIME_LOCK_DIR/$INSTANCE_ID.runtime.lock"
UPDATE_MANAGER_LOCK_FILE="$RUNTIME_LOCK_DIR/$INSTANCE_ID.update-manager.lock"

FILES_CHANGED=0
DB_CHANGED=0
DATABASE_BACKUP_ENABLED=1
DATABASE_BACKUP_CREATED=0
SERVICE_WAS_ACTIVE=0
RUNTIME_LOCK_FD=""

mkdir -p "$RUNTIME_LOCK_DIR"
chown "$QISUTU_RUNTIME_USER:$APACHE_GROUP" "$RUNTIME_LOCK_DIR"
chmod 0770 "$RUNTIME_LOCK_DIR"

mkdir -p /etc/tmpfiles.d
cat > /etc/tmpfiles.d/qisutu-runtime-lock.conf <<EOF_TMPFILES
d /run/lock/qisutu 0770 $QISUTU_RUNTIME_USER $APACHE_GROUP -
EOF_TMPFILES
chmod 0644 /etc/tmpfiles.d/qisutu-runtime-lock.conf

exec {UPDATE_MANAGER_FD}>>"$UPDATE_MANAGER_LOCK_FILE"
chown "root:$APACHE_GROUP" "$UPDATE_MANAGER_LOCK_FILE"
chmod 0660 "$UPDATE_MANAGER_LOCK_FILE"
flock -n -x "$UPDATE_MANAGER_FD" || fail "Für diese Qisutu-Instanz läuft bereits ein Update."

trap 'update_failed "$LINENO" "$BASH_COMMAND"' ERR

mysql_config_create
"$DB_CLIENT" --defaults-extra-file="$MYSQL_CONFIG_FILE" "$DB_NAME" -e 'SELECT 1' >/dev/null
CURRENT_DATABASE_VERSION="$(database_current_version_get)"
version_is_valid "$CURRENT_DATABASE_VERSION" || fail "Die aktuelle Datenbankversion konnte nicht aus database_version gelesen werden."

printf 'Datenbankstand:       %s\n' "$CURRENT_DATABASE_VERSION"
printf 'Erforderlicher Stand: %s\n\n' "$TARGET_DATABASE_VERSION"

if version_gt "$CURRENT_DATABASE_VERSION" "$TARGET_DATABASE_VERSION"; then
    fail "Die vorhandene Datenbankversion $CURRENT_DATABASE_VERSION ist neuer als das Updatepaket erwartet."
fi

printf 'Prüfe das Updatepaket vollständig, bevor die Installation verändert wird.\n'
perl_syntax_check "$SOURCE_ROOT"
program_registry_check "$SOURCE_ROOT"
perl "$SOURCE_ROOT/install/update/QisutuSchemaSync.pl" --schema "$SOURCE_ROOT/install/sql/schema.sql" --parse-only
database_migrations_preflight
printf 'Alle Vorprüfungen wurden erfolgreich abgeschlossen.\n\n'

if (( ASSUME_YES == 0 )); then
    printf 'Optionale Datenbanksicherung vor dem Update\n'
    printf '  Die vollständige Datenbank kann unter folgendem Pfad gesichert werden:\n'
    printf '  %s\n\n' "$DATABASE_DUMP_FILE"
    printf '  ACHTUNG: Bei großen Installationen kann diese Sicherung sehr viel\n'
    printf '  Speicherplatz benötigen. Prüfe vorher den freien Platz unter /var/backups.\n\n'
    printf '  Die vollständige Systemsicherung muss entsprechend der\n'
    printf '  Betreiberanweisung bereits vor dem Update vorhanden sein.\n\n'

    while true; do
        read -r -p "Soll zusätzlich ein Datenbankdump erstellt werden? [J/n]: " BACKUP_ANSWER
        case "$BACKUP_ANSWER" in
            ""|j|J|ja|Ja|JA|y|Y|yes|Yes|YES) DATABASE_BACKUP_ENABLED=1; break ;;
            n|N|nein|Nein|NEIN|no|No|NO) DATABASE_BACKUP_ENABLED=0; break ;;
            *) echo "Bitte antworte mit j oder n." ;;
        esac
    done
fi

if (( DATABASE_BACKUP_ENABLED == 1 )) && [[ -z "$DB_DUMP_CLIENT" ]]; then
    fail "Für die gewählte Datenbanksicherung wurde weder mariadb-dump noch mysqldump gefunden."
fi

old_manifest_snapshot
config_preservation_snapshot
operator_config_snapshot

if systemctl is-active --quiet "$DAEMON_SERVICE"; then
    SERVICE_WAS_ACTIVE=1
fi

if [[ ! -e "$UPDATE_LOCK_FILE" ]]; then
    touch "$UPDATE_LOCK_FILE"
    UPDATE_LOCK_CREATED_BY_RUN=1
fi
chown "$TARGET_OWNER:$TARGET_GROUP" "$UPDATE_LOCK_FILE"
chmod 0660 "$UPDATE_LOCK_FILE"

echo "Stoppe den Daemon $DAEMON_SERVICE."
systemctl stop "$DAEMON_SERVICE"
if systemctl is-active --quiet "$DAEMON_SERVICE"; then
    fail "Der Daemon $DAEMON_SERVICE konnte nicht gestoppt werden."
fi


touch "$RUNTIME_LOCK_FILE"
chown "$QISUTU_RUNTIME_USER:$APACHE_GROUP" "$RUNTIME_LOCK_FILE"
chmod 0660 "$RUNTIME_LOCK_FILE"
exec {RUNTIME_LOCK_FD}>>"$RUNTIME_LOCK_FILE"
echo "Warte, bis laufende Prozesse dieser Instanz beendet sind."
flock -x "$RUNTIME_LOCK_FD"

if (( DATABASE_BACKUP_ENABLED == 1 )); then
    mkdir -p "$BACKUP_DIR"
    chmod 0700 "$BACKUP_DIR"
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
    echo "Der zusätzliche Datenbankdump wurde übersprungen."
fi

obsolete_managed_files_remove
package_files_copy_direct
installation_permissions_apply
package_tree_verify
perl_syntax_check "$TARGET_ROOT"
program_registry_check "$TARGET_ROOT"

# Die Sollstruktur wird zuerst ergänzt. Danach werden alle dauerhaft
# mitgeführten und noch nicht protokollierten INSERT-/UPDATE-/Datenmigrationen
# ausgeführt. Ein zweiter Schemaabgleich bestätigt den Endzustand.
database_schema_synchronize
database_migrations_apply
database_schema_synchronize
database_migrations_verify
database_target_version_record

DATABASE_VERSION_AFTER="$(database_current_version_get)"
[[ "$DATABASE_VERSION_AFTER" == "$TARGET_DATABASE_VERSION" ]] || fail "Die Datenbankversion ist nach dem Update nicht korrekt."

operator_config_verify
apache_config_test

program_version_patch "$TARGET_ROOT/core/config/QisutuConfig.pm"
installation_permissions_apply
config_preservation_verify

INSTALLED_VERSION_AFTER="$(config_value_get program_version)"
[[ "$INSTALLED_VERSION_AFTER" == "$RELEASE_VERSION" ]] || fail "Die installierte Programmversion ist nach dem Update nicht korrekt."

daemon_runtime_user_migrate

rm -f "$UPDATE_LOCK_FILE"

if (( SERVICE_WAS_ACTIVE == 1 || UPDATE_LOCK_PREEXISTED == 1 )); then
    echo "Starte den Daemon $DAEMON_SERVICE."
    systemctl start "$DAEMON_SERVICE"
    systemctl is-active --quiet "$DAEMON_SERVICE" || fail "Der Daemon $DAEMON_SERVICE läuft nach dem Update nicht."
fi

flock -u "$RUNTIME_LOCK_FD"
rm -rf "$TEMP_ROOT"
trap - ERR

printf '\nQisutu wurde erfolgreich aktualisiert.\n'
printf '  Instanz:      %s\n' "$INSTANCE_ID"
printf '  Version:      %s\n' "$RELEASE_VERSION"
printf '  DB-Stand:     %s\n' "$TARGET_DATABASE_VERSION"
if (( DATABASE_BACKUP_CREATED == 1 )); then
    printf '  DB-Sicherung: %s\n' "$DATABASE_DUMP_FILE"
else
    printf '  DB-Sicherung: nicht erstellt\n'
fi
printf '  Apache:       vorhandene Konfiguration unverändert\n'
if (( DAEMON_USER_CHANGED == 1 )); then
    printf '  systemd:      Daemon-Laufzeitbenutzer auf %s korrigiert\n' "$QISUTU_RUNTIME_USER"
else
    printf '  systemd:      vorhandene Konfiguration unverändert\n'
fi
printf '  Webadresse:   %s\n' "$WEB_PATH"
