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

set -euo pipefail

if [[ ${EUID:-$(id -u)} -ne 0 ]]; then
    echo "Bitte dieses Installationsprogramm als root ausführen: sudo ./install.sh" >&2
    exit 1
fi

ROOT_PATH="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"

if [[ "$ROOT_PATH" =~ [[:space:]] ]]; then
    echo "Der Qisutu-Installationspfad darf keine Leerzeichen enthalten: $ROOT_PATH" >&2
    exit 1
fi

mkdir -p "$ROOT_PATH/var/install"
INSTANCE_CONFIG_FILE="$ROOT_PATH/var/install/instance.conf"
LOCK_FILE="$ROOT_PATH/var/install/installed.lock"

normalize_instance_name() {
    local value="$1"

    value="$(printf '%s' "$value" | tr '[:upper:]_' '[:lower:]-')"
    value="$(printf '%s' "$value" | sed -E 's/[^a-z0-9-]+/-/g; s/-+/-/g; s/^-+//; s/-+$//')"
    value="${value#qisutu-}"

    printf '%s' "$value"
}

instance_name_is_valid() {
    [[ "$1" =~ ^[a-z][a-z0-9-]{0,15}$ ]]
}

load_instance_config() {
    [[ -r "$INSTANCE_CONFIG_FILE" ]] || return 1

    while IFS='=' read -r key value; do
        case "$key" in
            instance_id) INSTANCE_ID="$value" ;;
            web_path) WEB_PATH="$value" ;;
            apache_conf_name) APACHE_CONF_NAME="$value" ;;
            daemon_service) DAEMON_SERVICE="$value" ;;
            install_complete_service) INSTALL_COMPLETE_SERVICE="$value" ;;
            install_complete_path) INSTALL_COMPLETE_PATH="$value" ;;
            session_cookie) SESSION_COOKIE="$value" ;;
            db_name) DB_NAME="$value" ;;
            db_user) DB_USER="$value" ;;
        esac
    done < "$INSTANCE_CONFIG_FILE"

    return 0
}

validate_instance_values() {
    if [[ ! "$INSTANCE_ID" =~ ^[a-z][a-z0-9-]{0,47}$ ]]; then
        echo "Die gespeicherte Instanzkennung ist ungültig: $INSTANCE_ID" >&2
        exit 1
    fi

    if [[ ! "$WEB_PATH" =~ ^/[A-Za-z0-9][A-Za-z0-9_/-]*$ ]] \
        || [[ "$WEB_PATH" == */ ]] \
        || [[ "$WEB_PATH" == *"//"* ]] \
        || [[ "$WEB_PATH" == *".."* ]]; then
        echo "Der gespeicherte Webpfad ist ungültig: $WEB_PATH" >&2
        exit 1
    fi

    if [[ ! "$APACHE_CONF_NAME" =~ ^[A-Za-z0-9][A-Za-z0-9._-]*\.conf$ ]]; then
        echo "Der gespeicherte Apache-Konfigurationsname ist ungültig: $APACHE_CONF_NAME" >&2
        exit 1
    fi

    if [[ ! "$DAEMON_SERVICE" =~ ^[A-Za-z0-9][A-Za-z0-9_.@-]*\.service$ ]]; then
        echo "Der gespeicherte systemd-Dienstname ist ungültig: $DAEMON_SERVICE" >&2
        exit 1
    fi

    if [[ ! "$INSTALL_COMPLETE_SERVICE" =~ ^[A-Za-z0-9][A-Za-z0-9_.@-]*\.service$ ]]; then
        echo "Der gespeicherte Abschlussdienst ist ungültig: $INSTALL_COMPLETE_SERVICE" >&2
        exit 1
    fi

    if [[ ! "$INSTALL_COMPLETE_PATH" =~ ^[A-Za-z0-9][A-Za-z0-9_.@-]*\.path$ ]]; then
        echo "Der gespeicherte systemd-Pfadname ist ungültig: $INSTALL_COMPLETE_PATH" >&2
        exit 1
    fi

    if [[ ! "$SESSION_COOKIE" =~ ^[A-Z][A-Z0-9_]{2,63}$ ]]; then
        echo "Der gespeicherte Session-Cookie-Name ist ungültig: $SESSION_COOKIE" >&2
        exit 1
    fi

    if [[ ! "$DB_NAME" =~ ^[A-Za-z][A-Za-z0-9_]{0,63}$ ]]; then
        echo "Der gespeicherte Datenbankname ist ungültig: $DB_NAME" >&2
        exit 1
    fi

    if [[ ! "$DB_USER" =~ ^[A-Za-z][A-Za-z0-9_]{0,23}$ ]]; then
        echo "Der gespeicherte Datenbankbenutzer ist ungültig: $DB_USER" >&2
        exit 1
    fi
}

write_instance_config() {
    cat > "$INSTANCE_CONFIG_FILE" <<EOF_INSTANCE
instance_id=$INSTANCE_ID
web_path=$WEB_PATH
apache_conf_name=$APACHE_CONF_NAME
daemon_service=$DAEMON_SERVICE
install_complete_service=$INSTALL_COMPLETE_SERVICE
install_complete_path=$INSTALL_COMPLETE_PATH
session_cookie=$SESSION_COOKIE
db_name=$DB_NAME
db_user=$DB_USER
EOF_INSTANCE
    chmod 0640 "$INSTANCE_CONFIG_FILE"
}

escape_sed_replacement() {
    printf '%s' "$1" | sed 's/[&|\\]/\\&/g'
}

ensure_link_target_available() {
    local link_path="$1"
    local expected_target="$2"

    if [[ -L "$link_path" ]]; then
        local current_target
        current_target="$(readlink -f "$link_path" 2>/dev/null || true)"
        if [[ "$current_target" != "$expected_target" ]]; then
            echo "Die Datei $link_path gehört bereits zu einer anderen Installation:" >&2
            echo "  $current_target" >&2
            exit 1
        fi
    elif [[ -e "$link_path" ]]; then
        echo "Die Datei $link_path existiert bereits und wird nicht überschrieben." >&2
        exit 1
    fi
}

ensure_web_path_available() {
    local directory file
    local directories=(
        /etc/apache2/sites-enabled
        /etc/apache2/conf-enabled
        /etc/apache2/conf.d
        /etc/httpd/conf.d
    )

    for directory in "${directories[@]}"; do
        [[ -d "$directory" ]] || continue
        while IFS= read -r -d '' file; do
            if grep -Fq "ScriptAlias $WEB_PATH/ " "$file" 2>/dev/null; then
                if ! grep -Fq "$ROOT_PATH/bin/cgi-bin/" "$file" 2>/dev/null; then
                    echo "Der Webpfad $WEB_PATH wird bereits von einer anderen Apache-Konfiguration verwendet:" >&2
                    echo "  $file" >&2
                    exit 1
                fi
            fi
        done < <(find -L "$directory" -maxdepth 1 -type f -print0 2>/dev/null)
    done
}

ensure_systemd_target_available() {
    local target_file="$1"
    local ownership_marker="$2"

    [[ -e "$target_file" ]] || return 0
    if ! grep -Fq "$ownership_marker" "$target_file" 2>/dev/null; then
        echo "Die systemd-Datei $target_file gehört bereits zu einer anderen Installation und wird nicht überschrieben." >&2
        exit 1
    fi
}

render_template() {
    local source_file="$1"
    local target_file="$2"
    local escaped_root escaped_web_path escaped_instance escaped_daemon escaped_complete_service escaped_complete_path escaped_user escaped_group

    escaped_root="$(escape_sed_replacement "$ROOT_PATH")"
    escaped_web_path="$(escape_sed_replacement "$WEB_PATH")"
    escaped_instance="$(escape_sed_replacement "$INSTANCE_ID")"
    escaped_daemon="$(escape_sed_replacement "$DAEMON_SERVICE")"
    escaped_complete_service="$(escape_sed_replacement "$INSTALL_COMPLETE_SERVICE")"
    escaped_complete_path="$(escape_sed_replacement "$INSTALL_COMPLETE_PATH")"
    escaped_user="$(escape_sed_replacement "${APACHE_USER:-__QISUTU_APACHE_USER__}")"
    escaped_group="$(escape_sed_replacement "${APACHE_GROUP:-__QISUTU_APACHE_GROUP__}")"

    sed \
        -e "s|__QISUTU_ROOT__|$escaped_root|g" \
        -e "s|__QISUTU_WEB_PATH__|$escaped_web_path|g" \
        -e "s|__QISUTU_INSTANCE__|$escaped_instance|g" \
        -e "s|__QISUTU_DAEMON_SERVICE__|$escaped_daemon|g" \
        -e "s|__QISUTU_INSTALL_COMPLETE_SERVICE__|$escaped_complete_service|g" \
        -e "s|__QISUTU_INSTALL_COMPLETE_PATH__|$escaped_complete_path|g" \
        -e "s|__QISUTU_APACHE_USER__|$escaped_user|g" \
        -e "s|__QISUTU_APACHE_GROUP__|$escaped_group|g" \
        "$source_file" > "$target_file"

    chmod 0644 "$target_file"
}

INSTANCE_ID=""
WEB_PATH=""
APACHE_CONF_NAME=""
DAEMON_SERVICE=""
INSTALL_COMPLETE_SERVICE=""
INSTALL_COMPLETE_PATH=""
SESSION_COOKIE=""
DB_NAME=""
DB_USER=""
INSTANCE_NAME=""
INSTANCE_CONFIG_LOADED=0

if load_instance_config; then
    INSTANCE_CONFIG_LOADED=1
else
    DIRECTORY_NAME="$(basename "$ROOT_PATH")"

    if [[ "$DIRECTORY_NAME" == "qisutu" ]]; then
        INSTANCE_ID="qisutu"
        WEB_PATH="/qisutu"
        APACHE_CONF_NAME="qisutu.conf"
        DAEMON_SERVICE="qisutu-daemon.service"
        INSTALL_COMPLETE_SERVICE="qisutu-install-complete.service"
        INSTALL_COMPLETE_PATH="qisutu-install-complete.path"
        SESSION_COOKIE="QISUTU_SESSION"
        DB_NAME="qisutu"
        DB_USER="qisutu"
    else
        DEFAULT_INSTANCE_NAME="$DIRECTORY_NAME"
        DEFAULT_INSTANCE_NAME="${DEFAULT_INSTANCE_NAME#qisutu-}"
        DEFAULT_INSTANCE_NAME="$(normalize_instance_name "$DEFAULT_INSTANCE_NAME")"
        [[ -n "$DEFAULT_INSTANCE_NAME" ]] || DEFAULT_INSTANCE_NAME="test"

        INSTANCE_NAME="$(normalize_instance_name "${QISUTU_INSTANCE_NAME:-}")"

        if [[ -z "$INSTANCE_NAME" ]]; then
            if [[ -t 0 ]]; then
                while true; do
                    printf '\nZusätzliche Qisutu-Instanz erkannt.\n'
                    printf 'Bitte gib nur einen kurzen Namen ein, zum Beispiel test oder entwicklung.\n'
                    read -r -p "Name der zusätzlichen Instanz [$DEFAULT_INSTANCE_NAME]: " INSTANCE_NAME_INPUT
                    INSTANCE_NAME="$(normalize_instance_name "${INSTANCE_NAME_INPUT:-$DEFAULT_INSTANCE_NAME}")"

                    if instance_name_is_valid "$INSTANCE_NAME"; then
                        break
                    fi

                    echo "Der Name muss mit einem Buchstaben beginnen und darf höchstens 16 Kleinbuchstaben, Zahlen oder Bindestriche enthalten."
                done
            else
                INSTANCE_NAME="$DEFAULT_INSTANCE_NAME"
            fi
        fi

        if ! instance_name_is_valid "$INSTANCE_NAME"; then
            echo "Ungültiger Name für die zusätzliche Qisutu-Instanz: $INSTANCE_NAME" >&2
            echo "Erlaubt sind höchstens 16 Kleinbuchstaben, Zahlen und Bindestriche; der erste Buchstabe muss ein Buchstabe sein." >&2
            exit 1
        fi

        INSTANCE_ID="qisutu-$INSTANCE_NAME"
        INSTANCE_DB_SUFFIX="${INSTANCE_NAME//-/_}"
        INSTANCE_COOKIE_SUFFIX="$(printf '%s' "$INSTANCE_NAME" | tr '[:lower:]-' '[:upper:]_')"
        WEB_PATH="/$INSTANCE_ID"
        APACHE_CONF_NAME="$INSTANCE_ID.conf"
        DAEMON_SERVICE="$INSTANCE_ID-daemon.service"
        INSTALL_COMPLETE_SERVICE="$INSTANCE_ID-install-complete.service"
        INSTALL_COMPLETE_PATH="$INSTANCE_ID-install-complete.path"
        SESSION_COOKIE="QISUTU_${INSTANCE_COOKIE_SUFFIX}_SESSION"
        DB_NAME="qisutu_${INSTANCE_DB_SUFFIX}"
        DB_USER="qisutu_${INSTANCE_DB_SUFFIX}"
    fi

    validate_instance_values
    write_instance_config
fi

validate_instance_values

if [[ -f "$LOCK_FILE" ]]; then
    echo "Diese Qisutu-Instanz ist bereits vollständig installiert." >&2
    echo "Für ein Update entpacke das neue Qisutu-Release in ein separates Verzeichnis und führe dort aus:" >&2
    echo "  sudo ./update.sh $ROOT_PATH" >&2
    exit 1
fi

printf '\nQisutu-Systemvorbereitung\n'
if [[ "$INSTANCE_CONFIG_LOADED" -eq 1 ]]; then
    printf 'Die vorhandene Instanzkonfiguration wird unverändert verwendet.\n'
elif [[ "$INSTANCE_ID" == "qisutu" ]]; then
    printf 'Normale Qisutu-Installation erkannt. Es sind keine weiteren Angaben erforderlich.\n'
else
    printf 'Zusätzliche Qisutu-Instanz "%s" wird eingerichtet.\n' "$INSTANCE_NAME"
fi
printf '  Installationspfad: %s\n' "$ROOT_PATH"
printf '  Webpfad:           %s\n' "$WEB_PATH"
printf '  Datenbank:         %s\n\n' "$DB_NAME"

OS_ID=""
OS_LIKE=""
OS_FAMILY=""
APACHE_USER=""
APACHE_GROUP=""
APACHE_SERVICE=""
DB_SERVICE=""
APACHE_CONF_TARGET=""
APACHE_RUNTIME_CONF="$ROOT_PATH/scriptfiles/$INSTANCE_ID-apache-runtime.conf"

if [[ -r /etc/os-release ]]; then
    # shellcheck disable=SC1091
    . /etc/os-release
    OS_ID="${ID:-}"
    OS_LIKE="${ID_LIKE:-}"
fi

install_debian() {
    OS_FAMILY="debian"
    export DEBIAN_FRONTEND=noninteractive
    apt-get update
    apt-get install -y \
        apache2 perl mariadb-server mariadb-client ca-certificates \
        libdbi-perl libdbd-mysql-perl libio-socket-ssl-perl libauthen-sasl-perl

    a2enmod alias env cgid headers >/dev/null
    APACHE_USER="www-data"
    APACHE_GROUP="www-data"
    APACHE_SERVICE="apache2"
    DB_SERVICE="mariadb"
    APACHE_CONF_TARGET="/etc/apache2/sites-available/$APACHE_CONF_NAME"

    render_template "$ROOT_PATH/scriptfiles/qisutu-apache.conf" "$APACHE_RUNTIME_CONF"
    ensure_web_path_available
    ensure_link_target_available "$APACHE_CONF_TARGET" "$APACHE_RUNTIME_CONF"

    a2disconf "$APACHE_CONF_NAME" >/dev/null 2>&1 || true
    a2dissite "$APACHE_CONF_NAME" >/dev/null 2>&1 || true
    rm -f \
        "/etc/apache2/conf-enabled/$APACHE_CONF_NAME" \
        "/etc/apache2/conf-available/$APACHE_CONF_NAME"

    ln -sfn "$APACHE_RUNTIME_CONF" "$APACHE_CONF_TARGET"
    a2ensite "$APACHE_CONF_NAME" >/dev/null
}

install_rhel() {
    OS_FAMILY="rhel"
    local package_manager="dnf"
    command -v dnf >/dev/null 2>&1 || package_manager="yum"

    "$package_manager" install -y \
        httpd perl mariadb mariadb-server ca-certificates \
        perl-DBI perl-DBD-MySQL perl-IO-Socket-SSL perl-Authen-SASL

    if ! "$package_manager" install -y policycoreutils-python-utils; then
        "$package_manager" install -y policycoreutils-python
    fi

    APACHE_USER="apache"
    APACHE_GROUP="apache"
    APACHE_SERVICE="httpd"
    DB_SERVICE="mariadb"
    APACHE_CONF_TARGET="/etc/httpd/conf.d/$APACHE_CONF_NAME"

    render_template "$ROOT_PATH/scriptfiles/qisutu-apache.conf" "$APACHE_RUNTIME_CONF"
    ensure_web_path_available
    ensure_link_target_available "$APACHE_CONF_TARGET" "$APACHE_RUNTIME_CONF"
    ln -sfn "$APACHE_RUNTIME_CONF" "$APACHE_CONF_TARGET"
}

install_suse() {
    OS_FAMILY="suse"
    zypper --non-interactive install \
        apache2 perl mariadb mariadb-client ca-certificates \
        perl-DBI perl-DBD-mysql perl-IO-Socket-SSL perl-Authen-SASL

    a2enmod alias env cgi headers >/dev/null

    APACHE_USER="wwwrun"
    APACHE_GROUP="www"
    APACHE_SERVICE="apache2"
    DB_SERVICE="mariadb"
    APACHE_CONF_TARGET="/etc/apache2/conf.d/$APACHE_CONF_NAME"

    render_template "$ROOT_PATH/scriptfiles/qisutu-apache.conf" "$APACHE_RUNTIME_CONF"
    ensure_web_path_available
    ensure_link_target_available "$APACHE_CONF_TARGET" "$APACHE_RUNTIME_CONF"
    ln -sfn "$APACHE_RUNTIME_CONF" "$APACHE_CONF_TARGET"
}

verify_perl_modules() {
    local module
    local missing=0
    local modules=(
        DBI
        DBD::mysql
        IO::Socket::SSL
        Authen::SASL
        MIME::Base64
        MIME::QuotedPrint
        Net::SMTP
        Digest::SHA
        JSON::PP
    )

    for module in "${modules[@]}"; do
        if ! perl -M"$module" -e 1 >/dev/null 2>&1; then
            echo "Fehlendes Perl-Modul nach der Paketinstallation: $module" >&2
            missing=1
        fi
    done

    if [[ $missing -ne 0 ]]; then
        echo "Die Qisutu-Systemvorbereitung wurde abgebrochen, weil benötigte Perl-Module fehlen." >&2
        exit 1
    fi
}

verify_apache_modules() {
    local apache_control=""
    local module_list=""
    local missing=0

    if command -v apache2ctl >/dev/null 2>&1; then
        apache_control="apache2ctl"
    elif command -v apachectl >/dev/null 2>&1; then
        apache_control="apachectl"
    elif command -v httpd >/dev/null 2>&1; then
        apache_control="httpd"
    fi

    if [[ -z "$apache_control" ]]; then
        echo "Apache-Kontrollprogramm wurde nicht gefunden." >&2
        exit 1
    fi

    module_list="$($apache_control -M 2>&1 || true)"

    for required_module in alias_module env_module headers_module; do
        if ! grep -qE "(^|[[:space:]])${required_module}([[:space:]]|$)" <<<"$module_list"; then
            echo "Fehlendes Apache-Modul: $required_module" >&2
            missing=1
        fi
    done

    if ! grep -qE '(^|[[:space:]])cgi(d)?_module([[:space:]]|$)' <<<"$module_list"; then
        echo "Fehlendes Apache-CGI-Modul: cgi_module oder cgid_module" >&2
        missing=1
    fi

    if [[ $missing -ne 0 ]]; then
        echo "Die Qisutu-Systemvorbereitung wurde abgebrochen, weil benötigte Apache-Module fehlen." >&2
        exit 1
    fi
}

configure_selinux() {
    if [[ "$OS_FAMILY" != "rhel" ]]; then
        return
    fi

    if ! command -v getenforce >/dev/null 2>&1 || [[ "$(getenforce)" == "Disabled" ]]; then
        return
    fi

    setsebool -P httpd_enable_cgi 1
    setsebool -P httpd_can_network_connect_db 1
    setsebool -P httpd_can_network_connect 1

    semanage fcontext -a -t httpd_sys_content_t "${ROOT_PATH}(/.*)?" 2>/dev/null \
        || semanage fcontext -m -t httpd_sys_content_t "${ROOT_PATH}(/.*)?"
    semanage fcontext -a -t httpd_sys_script_exec_t "${ROOT_PATH}/bin/cgi-bin(/.*)?" 2>/dev/null \
        || semanage fcontext -m -t httpd_sys_script_exec_t "${ROOT_PATH}/bin/cgi-bin(/.*)?"
    semanage fcontext -a -t httpd_sys_rw_content_t "${ROOT_PATH}/var(/.*)?" 2>/dev/null \
        || semanage fcontext -m -t httpd_sys_rw_content_t "${ROOT_PATH}/var(/.*)?"
    semanage fcontext -a -t httpd_sys_rw_content_t "${ROOT_PATH}/core/config/QisutuConfig\\.pm" 2>/dev/null \
        || semanage fcontext -m -t httpd_sys_rw_content_t "${ROOT_PATH}/core/config/QisutuConfig\\.pm"

    restorecon -RF "$ROOT_PATH"
}

configure_firewall() {
    if ! command -v firewall-cmd >/dev/null 2>&1; then
        return
    fi

    if ! systemctl is-active --quiet firewalld; then
        return
    fi

    firewall-cmd --permanent --add-service=http >/dev/null
    firewall-cmd --reload >/dev/null
}

case " $OS_ID $OS_LIKE " in
    *" debian "*|*" ubuntu "*) install_debian ;;
    *" rhel "*|*" fedora "*|*" centos "*|*" rocky "*|*" almalinux "*) install_rhel ;;
    *" suse "*|*" opensuse "*) install_suse ;;
    *)
        echo "Nicht unterstütztes Betriebssystem: ${OS_ID:-unbekannt}" >&2
        echo "Unterstützt werden Debian/Ubuntu, RHEL/Rocky/Alma/Fedora und openSUSE/SLES." >&2
        exit 1
        ;;
esac

verify_perl_modules
verify_apache_modules

mkdir -p \
    "$ROOT_PATH/var/log" \
    "$ROOT_PATH/var/cache" \
    "$ROOT_PATH/var/tmp" \
    "$ROOT_PATH/var/install"

find "$ROOT_PATH" -type d -exec chmod 0755 {} +
find "$ROOT_PATH" -type f -exec chmod 0644 {} +
chmod 0755 "$ROOT_PATH/install.sh" "$ROOT_PATH/update.sh"
find "$ROOT_PATH/bin" -maxdepth 1 -type f -name '*.pl' -exec chmod 0775 {} +
find "$ROOT_PATH/bin/cgi-bin" -maxdepth 1 -type f -name '*.pl' -exec chmod 0755 {} +

chown -R root:"$APACHE_GROUP" "$ROOT_PATH"
chown -R "$APACHE_USER":"$APACHE_GROUP" \
    "$ROOT_PATH/var/log" \
    "$ROOT_PATH/var/cache" \
    "$ROOT_PATH/var/tmp" \
    "$ROOT_PATH/var/install"
chmod 0770 \
    "$ROOT_PATH/var/log" \
    "$ROOT_PATH/var/cache" \
    "$ROOT_PATH/var/tmp" \
    "$ROOT_PATH/var/install"

mkdir -p /run/lock/qisutu
chown root:"$APACHE_GROUP" /run/lock/qisutu
chmod 0770 /run/lock/qisutu

chown root:"$APACHE_GROUP" "$ROOT_PATH/core/config/QisutuConfig.pm"
chmod 0660 "$ROOT_PATH/core/config/QisutuConfig.pm"
chown root:"$APACHE_GROUP" "$INSTANCE_CONFIG_FILE"
chmod 0640 "$INSTANCE_CONFIG_FILE"

configure_selinux
configure_firewall

ensure_systemd_target_available "/etc/systemd/system/$DAEMON_SERVICE" "QISUTU_HOME=$ROOT_PATH"
render_template "$ROOT_PATH/scriptfiles/qisutu-daemon.service" "/etc/systemd/system/$DAEMON_SERVICE"

if [[ ! -f "$LOCK_FILE" ]]; then
    ensure_systemd_target_available "/etc/systemd/system/$INSTALL_COMPLETE_SERVICE" "$DAEMON_SERVICE"
    ensure_systemd_target_available "/etc/systemd/system/$INSTALL_COMPLETE_PATH" "PathExists=$ROOT_PATH/var/install/installed.lock"

    render_template "$ROOT_PATH/scriptfiles/qisutu-install-complete.service" "/etc/systemd/system/$INSTALL_COMPLETE_SERVICE"
    render_template "$ROOT_PATH/scriptfiles/qisutu-install-complete.path" "/etc/systemd/system/$INSTALL_COMPLETE_PATH"
else
    systemctl disable --now "$INSTALL_COMPLETE_PATH" >/dev/null 2>&1 || true
    systemctl stop "$INSTALL_COMPLETE_SERVICE" >/dev/null 2>&1 || true
    rm -f \
        "/etc/systemd/system/$INSTALL_COMPLETE_PATH" \
        "/etc/systemd/system/$INSTALL_COMPLETE_SERVICE"
fi

systemctl daemon-reload
systemctl enable --now "$DB_SERVICE"

BOOTSTRAP_FILE="$ROOT_PATH/var/install/database-bootstrap.conf"
DB_CLI=""
command -v mariadb >/dev/null 2>&1 && DB_CLI="mariadb"
if [[ -z "$DB_CLI" ]] && command -v mysql >/dev/null 2>&1; then
    DB_CLI="mysql"
fi

if [[ ! -f "$LOCK_FILE" ]]; then
    BOOTSTRAP_USER="${DB_USER:0:22}_installer"
    if [[ -n "$DB_CLI" ]] && "$DB_CLI" --protocol=socket -uroot -e 'SELECT 1' >/dev/null 2>&1; then
        BOOTSTRAP_PASSWORD="$(od -An -N24 -tx1 /dev/urandom | tr -d ' \n')"
        "$DB_CLI" --protocol=socket -uroot <<SQL
CREATE USER IF NOT EXISTS '${BOOTSTRAP_USER}'@'localhost' IDENTIFIED BY '${BOOTSTRAP_PASSWORD}';
ALTER USER '${BOOTSTRAP_USER}'@'localhost' IDENTIFIED BY '${BOOTSTRAP_PASSWORD}';
GRANT ALL PRIVILEGES ON *.* TO '${BOOTSTRAP_USER}'@'localhost' WITH GRANT OPTION;
SQL
        PREVIOUS_UMASK="$(umask)"
        umask 077
        cat > "$BOOTSTRAP_FILE" <<EOF_BOOTSTRAP
host=localhost
port=3306
user=${BOOTSTRAP_USER}
password=${BOOTSTRAP_PASSWORD}
EOF_BOOTSTRAP
        umask "$PREVIOUS_UMASK"
        chown "$APACHE_USER":"$APACHE_GROUP" "$BOOTSTRAP_FILE"
        chmod 0600 "$BOOTSTRAP_FILE"
    else
        rm -f "$BOOTSTRAP_FILE"
        echo "Hinweis: Es konnte kein temporärer lokaler Datenbank-Installer angelegt werden."
        echo "Die Datenbank-Administrator-Zugangsdaten müssen im Webinstaller eingegeben werden."
    fi

    systemctl enable --now "$INSTALL_COMPLETE_PATH"
else
    rm -f "$BOOTSTRAP_FILE"
    systemctl enable --now "$DAEMON_SERVICE"
fi

if command -v apache2ctl >/dev/null 2>&1; then
    apache2ctl configtest
elif command -v httpd >/dev/null 2>&1; then
    httpd -t
fi

systemctl enable "$APACHE_SERVICE"
systemctl restart "$APACHE_SERVICE"

HOST_NAME="$(hostname -f 2>/dev/null || hostname)"

echo
echo "Die Systemvorbereitung für die Instanz '$INSTANCE_ID' wurde erfolgreich abgeschlossen."
if [[ -f "$LOCK_FILE" ]]; then
    echo "Die Instanz ist bereits installiert und wurde aktualisiert."
    echo "Qisutu ist erreichbar unter:"
    echo
    echo "  http://${HOST_NAME}${WEB_PATH}/index.pl"
else
    echo "Öffne jetzt den Qisutu-Webinstaller:"
    echo
    echo "  http://${HOST_NAME}${WEB_PATH}/install.pl"
    echo
    echo "Nach Abschluss des Webinstallers wird der Dienst $DAEMON_SERVICE automatisch aktiviert."
fi
