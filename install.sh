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

INSTALL_LANGUAGE=""
INSTALL_LANGUAGE_LABEL=""

select_install_language() {
    local selection=""

    if [[ ! -t 0 ]]; then
        selection="${QISUTU_INSTALL_LANGUAGE:-}"
        if [[ -z "$selection" ]]; then
            echo "Die Installationssprache muss ausgewählt werden." >&2
            echo "Bitte install.sh in einem interaktiven Terminal starten oder QISUTU_INSTALL_LANGUAGE setzen." >&2
            exit 1
        fi

        case "$selection" in
            de) INSTALL_LANGUAGE="de"; INSTALL_LANGUAGE_LABEL="Deutsch" ;;
            en) INSTALL_LANGUAGE="en"; INSTALL_LANGUAGE_LABEL="English" ;;
            fr) INSTALL_LANGUAGE="fr"; INSTALL_LANGUAGE_LABEL="Français" ;;
            it) INSTALL_LANGUAGE="it"; INSTALL_LANGUAGE_LABEL="Italiano" ;;
            pt-BR|pt-br|pt_BR|pt_br) INSTALL_LANGUAGE="pt-BR"; INSTALL_LANGUAGE_LABEL="Português (Brasil)" ;;
            pt-PT|pt-pt|pt_PT|pt_pt) INSTALL_LANGUAGE="pt-PT"; INSTALL_LANGUAGE_LABEL="Português (Portugal)" ;;
            es) INSTALL_LANGUAGE="es"; INSTALL_LANGUAGE_LABEL="Español" ;;
            nl) INSTALL_LANGUAGE="nl"; INSTALL_LANGUAGE_LABEL="Nederlands" ;;
            pl) INSTALL_LANGUAGE="pl"; INSTALL_LANGUAGE_LABEL="Polski" ;;
            cs) INSTALL_LANGUAGE="cs"; INSTALL_LANGUAGE_LABEL="Čeština" ;;
            tr) INSTALL_LANGUAGE="tr"; INSTALL_LANGUAGE_LABEL="Türkçe" ;;
            *)
                echo "Ungültige Installationssprache in QISUTU_INSTALL_LANGUAGE: $selection" >&2
                exit 1
                ;;
        esac
        return
    fi

    printf '\nQisutu – Sprache auswählen / Select language\n\n'
    printf '[1] Wenn Sie Qisutu auf Deutsch verwenden möchten, geben Sie 1 ein.\n'
    printf '[2] If you want to use Qisutu in English, enter 2.\n'
    printf '[3] Pour utiliser Qisutu en français, saisissez 3.\n'
    printf '[4] Per utilizzare Qisutu in italiano, inserire 4.\n'
    printf '[5] Se você deseja usar o Qisutu em português do Brasil, digite 5.\n'
    printf '[6] Se pretender utilizar o Qisutu em português de Portugal, introduza 6.\n'
    printf '[7] Si desea utilizar Qisutu en español, introduzca 7.\n'
    printf '[8] Als u Qisutu in het Nederlands wilt gebruiken, voert u 8 in.\n'
    printf '[9] Aby korzystać z Qisutu w języku polskim, wpisz 9.\n'
    printf '[10] Chcete-li používat Qisutu v češtině, zadejte 10.\n'
    printf '[11] Qisutu’yu Türkçe kullanmak istiyorsanız 11 girin.\n\n'

    while true; do
        printf 'Auswahl / Selection [1-11]: '
        read -r selection
        case "$selection" in
            1) INSTALL_LANGUAGE="de"; INSTALL_LANGUAGE_LABEL="Deutsch"; break ;;
            2) INSTALL_LANGUAGE="en"; INSTALL_LANGUAGE_LABEL="English"; break ;;
            3) INSTALL_LANGUAGE="fr"; INSTALL_LANGUAGE_LABEL="Français"; break ;;
            4) INSTALL_LANGUAGE="it"; INSTALL_LANGUAGE_LABEL="Italiano"; break ;;
            5) INSTALL_LANGUAGE="pt-BR"; INSTALL_LANGUAGE_LABEL="Português (Brasil)"; break ;;
            6) INSTALL_LANGUAGE="pt-PT"; INSTALL_LANGUAGE_LABEL="Português (Portugal)"; break ;;
            7) INSTALL_LANGUAGE="es"; INSTALL_LANGUAGE_LABEL="Español"; break ;;
            8) INSTALL_LANGUAGE="nl"; INSTALL_LANGUAGE_LABEL="Nederlands"; break ;;
            9) INSTALL_LANGUAGE="pl"; INSTALL_LANGUAGE_LABEL="Polski"; break ;;
            10) INSTALL_LANGUAGE="cs"; INSTALL_LANGUAGE_LABEL="Čeština"; break ;;
            11) INSTALL_LANGUAGE="tr"; INSTALL_LANGUAGE_LABEL="Türkçe"; break ;;
            *) printf 'Ungültige Auswahl / Invalid selection.\n' >&2 ;;
        esac
    done

    printf '\n%s\n\n' "$INSTALL_LANGUAGE_LABEL"
}

select_install_language

if [[ "$ROOT_PATH" =~ [[:space:]] ]]; then
    echo "Der Qisutu-Installationspfad darf keine Leerzeichen enthalten: $ROOT_PATH" >&2
    exit 1
fi

mkdir -p "$ROOT_PATH/var/install"
INSTANCE_CONFIG_FILE="$ROOT_PATH/var/install/instance.conf"
LOCK_FILE="$ROOT_PATH/var/install/installed.lock"

instance_name_is_valid() {
    [[ "$1" =~ ^[a-z][a-z0-9-]{0,23}$ ]]
}

set_instance_values_from_directory() {
    local directory_name="$1"
    local database_identifier cookie_identifier

    if ! instance_name_is_valid "$directory_name"; then
        echo "Der Name des Instanzverzeichnisses ist ungültig: $directory_name" >&2
        echo "Er muss mit einem Kleinbuchstaben beginnen und darf höchstens 24 Kleinbuchstaben, Zahlen oder Bindestriche enthalten." >&2
        return 1
    fi

    database_identifier="${directory_name//-/_}"
    cookie_identifier="$(printf '%s' "$directory_name" | tr '[:lower:]-' '[:upper:]_')"

    INSTANCE_NAME="$directory_name"
    INSTANCE_ID="$directory_name"
    WEB_PATH="/$directory_name"
    APACHE_CONF_NAME="$directory_name.conf"
    DAEMON_SERVICE="$directory_name-daemon.service"
    INSTALL_COMPLETE_SERVICE="$directory_name-install-complete.service"
    INSTALL_COMPLETE_PATH="$directory_name-install-complete.path"
    SESSION_COOKIE="${cookie_identifier}_SESSION"
    DB_NAME="$database_identifier"
    DB_USER="$database_identifier"
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
install_language=$INSTALL_LANGUAGE
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
    local escaped_root escaped_web_path escaped_instance escaped_daemon escaped_complete_service escaped_complete_path escaped_user escaped_group escaped_runtime_user

    escaped_root="$(escape_sed_replacement "$ROOT_PATH")"
    escaped_web_path="$(escape_sed_replacement "$WEB_PATH")"
    escaped_instance="$(escape_sed_replacement "$INSTANCE_ID")"
    escaped_daemon="$(escape_sed_replacement "$DAEMON_SERVICE")"
    escaped_complete_service="$(escape_sed_replacement "$INSTALL_COMPLETE_SERVICE")"
    escaped_complete_path="$(escape_sed_replacement "$INSTALL_COMPLETE_PATH")"
    escaped_user="$(escape_sed_replacement "${APACHE_USER:-__QISUTU_APACHE_USER__}")"
    escaped_group="$(escape_sed_replacement "${APACHE_GROUP:-__QISUTU_APACHE_GROUP__}")"
    escaped_runtime_user="$(escape_sed_replacement "${QISUTU_RUNTIME_USER:-qisutu}")"

    sed \
        -e "s|__QISUTU_ROOT__|$escaped_root|g" \
        -e "s|__QISUTU_WEB_PATH__|$escaped_web_path|g" \
        -e "s|__QISUTU_INSTANCE__|$escaped_instance|g" \
        -e "s|__QISUTU_DAEMON_SERVICE__|$escaped_daemon|g" \
        -e "s|__QISUTU_INSTALL_COMPLETE_SERVICE__|$escaped_complete_service|g" \
        -e "s|__QISUTU_INSTALL_COMPLETE_PATH__|$escaped_complete_path|g" \
        -e "s|__QISUTU_APACHE_USER__|$escaped_user|g" \
        -e "s|__QISUTU_APACHE_GROUP__|$escaped_group|g" \
        -e "s|__QISUTU_RUNTIME_USER__|$escaped_runtime_user|g" \
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
INSTANCE_CONFIG_ADJUSTED=0
DIRECTORY_NAME="$(basename "$ROOT_PATH")"

if load_instance_config; then
    INSTANCE_CONFIG_LOADED=1

    if [[ ! -f "$LOCK_FILE" ]]; then
        PREVIOUS_INSTANCE_VALUES="${INSTANCE_ID}|${WEB_PATH}|${APACHE_CONF_NAME}|${DAEMON_SERVICE}|${INSTALL_COMPLETE_SERVICE}|${INSTALL_COMPLETE_PATH}|${SESSION_COOKIE}|${DB_NAME}|${DB_USER}"
        set_instance_values_from_directory "$DIRECTORY_NAME"
        CURRENT_INSTANCE_VALUES="${INSTANCE_ID}|${WEB_PATH}|${APACHE_CONF_NAME}|${DAEMON_SERVICE}|${INSTALL_COMPLETE_SERVICE}|${INSTALL_COMPLETE_PATH}|${SESSION_COOKIE}|${DB_NAME}|${DB_USER}"

        if [[ "$PREVIOUS_INSTANCE_VALUES" != "$CURRENT_INSTANCE_VALUES" ]]; then
            INSTANCE_CONFIG_ADJUSTED=1
            validate_instance_values
            write_instance_config
        fi
    fi
else
    set_instance_values_from_directory "$DIRECTORY_NAME"

    validate_instance_values
    write_instance_config
fi

validate_instance_values
write_instance_config

if [[ -f "$LOCK_FILE" ]]; then
    echo "Diese Qisutu-Instanz ist bereits vollständig installiert." >&2
    echo "Für ein Update entpacke das neue Qisutu-Release in ein separates Verzeichnis und führe dort aus:" >&2
    echo "  sudo ./update.sh $ROOT_PATH" >&2
    exit 1
fi

printf '\nQisutu-Systemvorbereitung\n'
if [[ "$INSTANCE_CONFIG_LOADED" -eq 1 ]]; then
    if [[ "$INSTANCE_CONFIG_ADJUSTED" -eq 1 ]]; then
        printf 'Die noch nicht abgeschlossene Instanzkonfiguration wurde an den Verzeichnisnamen angepasst.\n'
    else
        printf 'Die vorhandene Instanzkonfiguration wird unverändert verwendet.\n'
    fi
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
QISUTU_RUNTIME_USER="qisutu"

if [[ -r /etc/os-release ]]; then
    # shellcheck disable=SC1091
    . /etc/os-release
    OS_ID="${ID:-}"
    OS_LIKE="${ID_LIKE:-}"
fi

install_debian() {
    OS_FAMILY="debian"
    local active_mpm=""
    local cgi_module="cgid"

    export DEBIAN_FRONTEND=noninteractive
    apt-get update
    apt-get install -y \
        apache2 perl mariadb-server mariadb-client ca-certificates openssl \
        libdbi-perl libdbd-mysql-perl libio-socket-ssl-perl libauthen-sasl-perl \
        libnet-ldap-perl

    if command -v a2query >/dev/null 2>&1; then
        active_mpm="$(a2query -M 2>/dev/null || true)"
    fi
    if [[ "$active_mpm" == *prefork* ]]; then
        cgi_module="cgi"
    fi

    a2enmod alias env headers "$cgi_module" >/dev/null
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
        httpd perl mariadb mariadb-server ca-certificates openssl \
        perl-DBI perl-DBD-MySQL perl-IO-Socket-SSL perl-Authen-SASL perl-LDAP

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
        apache2 perl mariadb mariadb-client ca-certificates openssl \
        perl-DBI perl-DBD-mysql perl-IO-Socket-SSL perl-Authen-SASL perl-LDAP

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
        Net::LDAP
        Digest::SHA
        JSON::PP
        IO::Uncompress::Unzip
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

verify_apache_modules() {
    local apache_control=""
    local module_list=""
    local missing=0
    local required_module=""

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

    if ! module_list="$($apache_control -M 2>&1)"; then
        echo "Die aktive Apache-Konfiguration konnte nicht geprüft werden." >&2
        echo "Apache meldet:" >&2
        printf '%s\n' "$module_list" >&2
        echo "Die Qisutu-Systemvorbereitung wurde abgebrochen, ohne fehlende Module zu unterstellen." >&2
        exit 1
    fi

    if [[ -z "$module_list" ]]; then
        echo "Apache hat bei der Modulprüfung keine Modulliste ausgegeben." >&2
        echo "Die Qisutu-Systemvorbereitung wurde abgebrochen." >&2
        exit 1
    fi

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
ensure_qisutu_runtime_user

mkdir -p \
    "$ROOT_PATH/addons" \
    "$ROOT_PATH/var/log" \
    "$ROOT_PATH/var/cache" \
    "$ROOT_PATH/var/tmp" \
    "$ROOT_PATH/var/install" \
    "$ROOT_PATH/var/secure" \
    "$ROOT_PATH/var/static/addons"

find "$ROOT_PATH" -type d -exec chmod 0755 {} +
find "$ROOT_PATH" -type f -exec chmod 0644 {} +
chmod 0755 "$ROOT_PATH/install.sh" "$ROOT_PATH/update.sh"
find "$ROOT_PATH/bin" -maxdepth 1 -type f -name '*.pl' -exec chmod 0775 {} +
find "$ROOT_PATH/bin/cgi-bin" -maxdepth 1 -type f -name '*.pl' -exec chmod 0755 {} +

chown -R "$QISUTU_RUNTIME_USER":"$APACHE_GROUP" "$ROOT_PATH"
chown -R "$QISUTU_RUNTIME_USER":"$APACHE_GROUP" \
    "$ROOT_PATH/var/log" \
    "$ROOT_PATH/var/cache" \
    "$ROOT_PATH/var/tmp" \
    "$ROOT_PATH/var/install"
chmod 0770 \
    "$ROOT_PATH/var/log" \
    "$ROOT_PATH/var/cache" \
    "$ROOT_PATH/var/tmp" \
    "$ROOT_PATH/var/install"
chmod 0755 "$ROOT_PATH/addons" "$ROOT_PATH/var/static/addons"

chown root:"$APACHE_GROUP" "$ROOT_PATH/var/secure"
chmod 0750 "$ROOT_PATH/var/secure"
SECURITY_KEY_FILE="$ROOT_PATH/var/secure/security.key"
if [[ ! -f "$SECURITY_KEY_FILE" ]]; then
    PREVIOUS_UMASK="$(umask)"
    umask 0137
    od -An -N32 -tx1 /dev/urandom | tr -d ' \n' > "$SECURITY_KEY_FILE"
    printf '\n' >> "$SECURITY_KEY_FILE"
    umask "$PREVIOUS_UMASK"
fi
chown root:"$APACHE_GROUP" "$SECURITY_KEY_FILE"
chmod 0640 "$SECURITY_KEY_FILE"
[[ "$(tr -d '[:space:]' < "$SECURITY_KEY_FILE")" =~ ^[0-9a-fA-F]{64}$ ]] || {
    echo "Der installationsabhängige Sicherheitsschlüssel ist ungültig." >&2
    exit 1
}

mkdir -p /run/lock/qisutu
chown "$QISUTU_RUNTIME_USER":"$APACHE_GROUP" /run/lock/qisutu
chmod 0770 /run/lock/qisutu
touch "/run/lock/qisutu/$INSTANCE_ID.runtime.lock"
chown "$QISUTU_RUNTIME_USER":"$APACHE_GROUP" "/run/lock/qisutu/$INSTANCE_ID.runtime.lock"
chmod 0660 "/run/lock/qisutu/$INSTANCE_ID.runtime.lock"

mkdir -p /etc/tmpfiles.d
cat > /etc/tmpfiles.d/qisutu-runtime-lock.conf <<EOF_TMPFILES
d /run/lock/qisutu 0770 $QISUTU_RUNTIME_USER $APACHE_GROUP -
EOF_TMPFILES
chmod 0644 /etc/tmpfiles.d/qisutu-runtime-lock.conf

chown "$QISUTU_RUNTIME_USER":"$APACHE_GROUP" "$ROOT_PATH/core/config/QisutuConfig.pm"
chmod 0660 "$ROOT_PATH/core/config/QisutuConfig.pm"
chown "$QISUTU_RUNTIME_USER":"$APACHE_GROUP" "$INSTANCE_CONFIG_FILE"
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
