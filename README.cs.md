<!--
Qisutu - Open Source Ticket System
Copyright (C) 2026 Franziska Steps
Qisutu - Kim-KI, https://qisutu.de

This file is part of Qisutu.

Qisutu is free software: you can redistribute it and/or modify
it under the terms of the GNU Affero General Public License as published by
the Free Software Foundation, either version 3 of the License, or
(at your option) any later version.

Qisutu is distributed in the hope that it will be useful,
but WITHOUT ANY WARRANTY; without even the implied warranty of
MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the
GNU Affero General Public License for more details.

You should have received a copy of the GNU Affero General Public License
along with Qisutu. If not, see <https://www.gnu.org/licenses/>.

SPDX-FileCopyrightText: 2026 Franziska Steps
SPDX-License-Identifier: AGPL-3.0-or-later
-->

[Deutsch](README.md) | [English](README.en.md) | [Français](README.fr.md) | [Italiano](README.it.md) | [Português (Brasil)](README.pt-BR.md) | [Português (Portugal)](README.pt-PT.md) | [Español](README.es.md) | [Nederlands](README.nl.md) | [Polski](README.pl.md) | [Čeština](README.cs.md) | [Türkçe](README.tr.md)

# Qisutu

Qisutu je nový open source systém požadavků založený na Perl/CGI, MariaDB nebo
MySQL, Template Toolkit a uživatelském rozhraní v prohlížeči.

Web projektu: https://qisutu.de

## Stav vydání

Qisutu je samostatně instalovatelný systém s portály agentů a zákazníků,
zpracováním e-mailů, adresářovým přihlášením, automatizací, znalostní bází,
CMDB, reporty a REST API. Qisutu 1.0.2 je stabilní produkční vydání a již není
ve vývojové fázi. Rozhraní a databáze se dále vyvíjejí v běžné údržbě; změny
dodává integrovaný aktualizátor a trvale udržované migrace.

## Jazyky

Qisutu 1.0.2 obsahuje jedenáct úplných jazyků: němčinu (`de`), angličtinu (`en`),
francouzštinu (`fr`), italštinu (`it`), brazilskou portugalštinu (`pt-BR`),
evropskou portugalštinu (`pt-PT`), španělštinu (`es`), nizozemštinu (`nl`),
polštinu (`pl`), češtinu (`cs`) a turečtinu (`tr`).

## Instalace

Jako root v `/opt` spusťte:

    wget https://ftp.qisutu.de/qisutu-1.0.2.tar.gz
    tar xzf qisutu-1.0.2.tar.gz
    mv qisutu-1.0.2 qisutu

    useradd -d /opt/qisutu -c 'Qisutu user' qisutu
    usermod -G www-data qisutu
    chown qisutu:www-data -R qisutu

    cd /opt/qisutu
    chmod +x install.sh
    ./install.sh

`install.sh` nejprve nabídne jedenáct jazyků. Volba se uloží do konfigurace,
webový instalátor se v ní otevře a nastaví ji jako výchozí. Název adresáře přímo
určuje instanci: `/opt/qisutu` vytvoří `qisutu` bez další předpony. Poté otevřete:

    http://SERVER/qisutu/install.pl

Projděte šest kroků. Skript zjistí systém, nainstaluje balíčky a Perl moduly a
pro každou instanci nastaví vlastní Apache, systemd služby, webovou cestu a
databázi. Instalátor vytvoří tabulky z `install/sql/schema.sql`, data z
`install/sql/insert.sql` a administrátora; náhodné heslo uloží do
`core/config/QisutuConfig.pm`. Podrobnosti jsou v `INSTALL.md`.

## Aktualizace

Jako root v `/opt` spusťte:

    wget https://ftp.qisutu.de/qisutu-1.0.2.tar.gz
    tar xzf qisutu-1.0.2.tar.gz
    chown qisutu:www-data -R /opt/qisutu-1.0.2
    cd /opt/qisutu-1.0.2
    chmod +x update.sh
    ./update.sh
    cd /opt
    rm -R qisutu-1.0.2
    rm qisutu-1.0.2.tar.gz

Aktualizátor rozpozná instanci podle `var/install/instance.conf`, zastaví jen
její daemon a poštu a nepřepíše konfiguraci instance, Apache ani systemd.
Volitelně vytvoří dump a ověří tabulky i migrace. Viz `INSTALL.md`.

## Struktura adresářů

- `bin/` – CGI, procesy na pozadí a příkazové programy
- `core/` – konfigurace, moduly, šablony, jazyky a systémové třídy
- `install/sql/schema.sql` a `install/sql/insert.sql` – struktura a počáteční data
- `scriptfiles/` – šablony Apache a systemd
- `var/static/` – frontend a soubory třetích stran

## Doplňkové moduly

Od 0.0.78 spravuje Qisutu běžné ZIP moduly s čitelným `qisutu-module.json`.
Daemon provádí souborové operace odděleně od webu; moduly mohou mít vlastní
obrazovky a šifrovaná tajemství. API 1.0 nabízí služby, trvalé události, izolované
REST trasy a řízené body UI. Starší moduly zůstávají kompatibilní a potřebnou
verzi jádra zajistí běžná aktualizace bez zákaznických variant. Viz `MODULES.md`.

## Evidence času

Agenti zapisují hodiny a minuty, rozlišují účtovatelný čas a typ aktivity.
Záznamy jsou auditovatelné: oprava zruší původní položku s důvodem a vytvoří
propojenou náhradu. Zpočátku opravuje jen admin. Zákaznické obrazovky čas nemají.

## E-mail a OAuth2

`Načítání e-mailů` nabízí standardní IMAP, Microsoft 365 OAuth2/XOAUTH2 a Google
Workspace/Gmail OAuth2/XOAUTH2. Návrat OAuth2 se ověřuje jednorázovým stavem,
tokeny se šifrují a obnovují a účet se aktivuje až po skutečném testu. Daemon
načítá každých pět minut bez cronu pro `qisutu-mail-fetch.pl`. Neaktivní účet se
před aktivací testuje a maže až po deaktivaci; logy zůstávají.

SMTP podporuje stejné typy, `AUTH XOAUTH2` a rozsahy
`https://outlook.office.com/SMTP.Send` a `https://mail.google.com/`. Externě
dostupná HTTPS URL a přesná návratová URI se nastavují v systémových nastaveních.

## Komunikační protokol

Protokol obsahuje IMAP, SMTP a OAuth2 operace, čas, výsledek a kroky. Ukládá jen
technická metadata, nikoli text a přílohy; hesla a tokeny odstraní. Výchozí
uchování je 90 dní, 0 automatické čištění vypne.

## Automatické odpovědi

Samostatné HTML šablony pokrývají nový zákaznický požadavek, odpověď, odpověď na
uzavřený požadavek a e-mail odmítnutý filtrem. Jsou zpočátku vypnuté. Odmítnutí
musí výslovně spustit odpověď; akce agentů další zákaznický e-mail neposílají.

## LDAP a Active Directory

Existují oddělené profily agentů a zákaznických kontaktů. Každý má vlastní
spojení, vyhledávání, mapování a testy. Povinné jsou login, jméno, příjmení a
e-mail; zákazník navíc potřebuje jedinečné číslo a název společnosti. Účty se
párují kanonickým loginem, e-mailová kolize způsobí chybu, nikoli sloučení.
Povoleny jsou jen LDAPS a StartTLS s kontrolou certifikátu. Změna profil vypne do
úspěšného testu; nenalezený uživatel může použít existující místní účet.

## Zákaznické a webové formuláře

Formuláře mají pevnou cílovou frontu, vícejazyčné texty a vlastní pole. Mohou být
pro všechny nebo vybrané zákazníky; bez nich zůstává standardní tvorba. Veřejné
formuláře dostanou link a iframe a chrání je CSP, honeypot, časová kontrola a
limity. Nevytvářejí aktivní účet. Hodnoty se ukládají jako neměnný snímek a
pozdější změny stará podání nemění.

## CMDB

Administrátoři sami definují typy CI, pole, stavy a vztahy a spravují inventář,
přiřazení a importy. Agenti CI jen hledají, propojují a čtou; sloučení převede
vazby. Historie je neměnná a CSV profily párují zdroj přes externí ID:

```bash
/opt/qisutu/bin/qisutu-cmdb-import.pl --profile 1 --file /srv/import/idoit.csv
```

Portál ukazuje jen výslovně povolené aktivní CI a pole.

## CSV import kmenových dat

Samostatné importy slouží zákazníkům, kontaktům a agentům. Dynamická pole se
přidávají jako `dynamic.<názevpole>`. Celý soubor se nejprve ověří a jedna chyba
zablokuje import; po potvrzení se vše zapíše v transakci. Chybějící záznamy se
nemažou. CSV neobsahuje hesla, skupiny ani práva; novým účtům lze poslat pozvánku.

## Znalostní báze a FAQ

FAQ má jedinečné číslo, jazyk a viditelnost `Jen agenti` nebo `Agenti a zákazníci`.
Každé uložení vytváří neměnnou revizi. Veřejné články jsou v portálu a agent je
může u CKEditoru vložit jako řešení či odkaz. Interní články se blokují v obsahu
viditelném zákazníkovi; použití revize se zaznamenává.

## Motivy agentů

Motiv je běžná osobní preference. Dodaný motiv `Vánoce` zdobí jen agentní stránky.
Další motivy používají `core/config/themes`, `var/static/css/themes` a případně
`var/static/img/themes`; centrální registr vše ověří.

## Zabezpečení

Webové změny chrání CSRF tokeny a REST API oddělené Bearer tokeny. Cookies jsou
`HttpOnly`, `SameSite=Lax` a přes HTTPS `Secure`. Hesla, OAuth tokeny a 2FA
tajemství šifruje klíč `var/secure/security.key`, který patří do chráněné zálohy.
Agenti a kontakty mohou zapnout TOTP pomocí lokálně vytvořeného QR a obnovovacích
kódů; správci mohou 2FA vynutit a resetovat.

## Konfigurace databáze

Připojení je v `core/config/QisutuConfig.pm`; instalátor zapíše host, port,
databázi, uživatele a náhodné heslo. Soubor chrání omezená práva.

## Licence

Qisutu používá GNU Affero General Public License verze 3 nebo novější
(`AGPL-3.0-or-later`). Úplné znění je v `LICENSE`.

Copyright (C) 2026 Franziska Steps.

## Software třetích stran

Soubory třetích stran si zachovávají původní oznámení; souhrn je v
`THIRD_PARTY_NOTICES.md`.
