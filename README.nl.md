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

Qisutu is een nieuw opensource-ticketsysteem op basis van Perl/CGI, MariaDB of
MySQL, Template Toolkit en een browserinterface.

Projectwebsite: https://qisutu.de

## Releasestatus

Qisutu is zelfstandig installeerbaar en bevat een agent- en klantportaal,
e-mailverwerking, directoryaanmelding, automatisering, kennisbank, CMDB,
rapporten en REST-API. Qisutu 1.0.2 is een stabiele productieversie en bevindt
zich niet meer in de ontwikkelfase. Interfaces en databasestructuren blijven in
het normale releaseonderhoud evolueren; noodzakelijke wijzigingen worden via de
geïntegreerde updater en blijvend onderhouden datamigraties geleverd.

## Talen

Qisutu 1.0.2 bevat elf volledige interfacetalen: Duits (`de`), Engels (`en`),
Frans (`fr`), Italiaans (`it`), Braziliaans Portugees (`pt-BR`), Europees
Portugees (`pt-PT`), Spaans (`es`), Nederlands (`nl`), Pools (`pl`), Tsjechisch
(`cs`) en Turks (`tr`).

## Installatie

Voer als root in `/opt` uit:

    wget https://ftp.qisutu.de/qisutu-1.0.2.tar.gz
    tar xzf qisutu-1.0.2.tar.gz
    mv qisutu-1.0.2 qisutu

    useradd -d /opt/qisutu -c 'Qisutu user' qisutu
    usermod -G www-data qisutu

    chown qisutu:www-data -R qisutu

    cd /opt/qisutu
    chmod +x install.sh
    ./install.sh

Bij de start vraagt `install.sh` om een van de elf talen. De keuze wordt in de
instantieconfiguratie opgeslagen, de webinstaller opent in die taal en gebruikt
haar als standaard. De mapnaam bepaalt direct de technische instantiewaarden:
`/opt/qisutu` maakt instantie `qisutu`, zonder extra voorvoegsel `qisutu-`.

Open vervolgens het getoonde adres, bijvoorbeeld:

    http://SERVER/qisutu/install.pl

Volg de zes stappen. `install.sh` herkent het besturingssysteem, installeert de
vereiste pakketten en Perl-modules en configureert per instantie een eigen
Apache-integratie, systemd-services, webpad en database. Productie en test
kunnen naast elkaar draaien.

De installer maakt database, gebruiker, structuur uit `install/sql/schema.sql`,
basisdata uit `install/sql/insert.sql` en de eerste beheerder. Het willekeurige
databasewachtwoord wordt direct in `core/config/QisutuConfig.pm` geschreven.
Details en een voorbeeld met twee instanties staan in `INSTALL.md`.

## Update

Voer als root in `/opt` uit:

    wget https://ftp.qisutu.de/qisutu-1.0.2.tar.gz
    tar xzf qisutu-1.0.2.tar.gz

    chown qisutu:www-data -R /opt/qisutu-1.0.2

    cd /opt/qisutu-1.0.2
    chmod +x update.sh
    ./update.sh

    cd /opt
    rm -R qisutu-1.0.2
    rm qisutu-1.0.2.tar.gz

De updater herkent de instantie via `var/install/instance.conf`, stopt alleen
haar daemon en blokkeert alleen haar e-mailophaling. Beheerde bestanden worden
gekopieerd zonder instantie-, Apache- of systemd-configuratie te overschrijven.
Optioneel wordt een databasedump gemaakt. Tabellen en permanente migraties
worden volledig gecontroleerd en aangevuld. Zie `INSTALL.md`.

## Mappenstructuur

- `bin/` – CGI-ingangen, achtergrondprocessen en commandoregelprogramma’s
- `core/` – configuratie, modules, sjablonen, talen en systeemklassen
- `install/sql/schema.sql` – volledige tabelstructuur
- `install/sql/insert.sql` – basisdata voor een nieuwe installatie
- `scriptfiles/` – Apache- en systemd-sjablonen
- `var/static/` – frontendbestanden en componenten van derden

## Add-ons

Sinds versie 0.0.78 heeft Qisutu een modulebeheerder voor gewone ZIP-bestanden
met leesbare `qisutu-module.json`. Beheerders installeren, actualiseren en
verwijderen modules in het beheer; de daemon voert bestandsbewerkingen apart van
het webproces uit. Een module kan eigen links en schermen leveren en geheimen
versleuteld opslaan.

Qisutu 1.0.2 levert ook interne API 1.0: herbruikbare services, duurzaam door de
daemon afgeleverde kernevents, geïsoleerde REST-routes met eigen rechten en
gecontroleerde UI-invoegpunten. Bestaande modules blijven compatibel. Een module
kan API-versie en functies declareren; indien nodig vraagt Qisutu een normale
core-update, zonder klantspecifieke variant. Modules zijn zelfstandige projecten
met volledige broncode. Installatie en beveiliging: `MODULES.md`.

## Tijdregistratie

Agenten kunnen uren en minuten boeken bij tickets, artikelen en wijzigingen.
Elke boeking onderscheidt factureerbare en niet-factureerbare tijd en kan een
activiteitstype krijgen. Handmatige boekingen zijn mogelijk. De gegevens zijn
controleerbaar: een bevoegde correctie annuleert het origineel met verplichte
reden en maakt een gekoppelde vervanging. Aanvankelijk mag alleen de admingroep
corrigeren. Klantschermen en klantartikelen bevatten geen tijdregistratie.

## E-mailophaling en OAuth2

Het beheer bundelt inkomende accounts onder `E-mailophaling` en biedt:

- Standaard-IMAP met gebruikersnaam en wachtwoord
- Microsoft 365 met OAuth2/XOAUTH2
- Google Workspace of Gmail met OAuth2/XOAUTH2

Microsoft en Google leiden na opslaan naar de provider. Qisutu controleert de
OAuth2-terugkeer met een eenmalige statuswaarde, bewaart tokens en test IMAP.
Activering volgt alleen na succes; verlopen tokens worden automatisch vernieuwd.
De instantiedaemon haalt elke vijf minuten mail op, zonder extra cron voor
`qisutu-mail-fetch.pl`.

Een inactief account wordt vóór heractivering getest en kan pas na deactivering
worden verwijderd. Inloggegevens en tokens verdwijnen, Postmaster-logboeken
blijven. `SMTP-instellingen` biedt standaard-SMTP, Microsoft 365 en Google.
Microsoft en Google gebruiken `AUTH XOAUTH2` met scopes
`https://outlook.office.com/SMTP.Send` en `https://mail.google.com/`. Tokens zijn
versleuteld en worden vernieuwd; activering vereist autorisatie en echte test.

Onder `Beheer > Systeeminstellingen` moet een extern bereikbare HTTPS-basis-URL
staan. De getoonde URI moet exact bij de provider geregistreerd zijn. Zie
`INSTALL.md`.

## Communicatielogboek

Het logboek bewaart IMAP-ophalingen, SMTP-verzendingen en OAuth2-operaties met
tijd, duur, resultaat, accountsnapshot en stappen. Er zijn kengetallen en
filters. Alleen technische metadata — afzender, ontvanger, onderwerp, Message-ID
en eventueel ticket — wordt opgeslagen; inhoud en bijlagen niet. Wachtwoorden,
geheimen en tokens worden vooraf verwijderd. Standaardbewaring is 90 dagen; 0
schakelt opruimen uit.

## Automatische klantantwoorden

Er zijn afzonderlijke HTML-sjablonen voor een klantticket, klantantwoord,
antwoord op gesloten ticket en door Postmaster geweigerde e-mail. Elk heeft
onderwerp, CKEditor-tekst, activering en placeholders. Ze zijn aanvankelijk uit.
Een weigeringsantwoord vereist de actie `E-mail weigeren en automatisch antwoord
activeren`; negeren geeft geen antwoord. Agenttickets en -antwoorden sturen geen
extra klantmail.

## LDAP en Active Directory

Er zijn volledig gescheiden profielen voor agenten en voor contacten met hun
klantbedrijven. Elk heeft eigen verbinding, zoekactie, mapping, tests en
activering. Qisutu kiest automatisch het juiste portaalprofiel.

Login, voornaam, achternaam en e-mail zijn verplicht. Het agentprofiel kan extra
velden importeren en een standaardgroep toewijzen. Het klantprofiel vereist ook
een uniek Qisutu-klantnummer en bedrijfsnaam. Verplichte Qisutu-velden vereisen
mapping en waarde.

Agenten worden op canonieke login gekoppeld. Een klantbedrijf wordt op nummer
gevonden of gemaakt en het contact exact daaraan toegewezen. Een reeds gebruikt
e-mailadres veroorzaakt een fout, nooit automatische samenvoeging. Alleen LDAPS
en StartTLS zijn toegestaan; certificaatcontrole is actief en het zoekwachtwoord
versleuteld. Wijziging deactiveert het profiel tot tests slagen. Vindt de
directory niemand, dan kan een bestaand lokaal account nog inloggen; vindt zij
wel iemand, dan is het directorywachtwoord bepalend.

## Klantformulieren en webformulieren

Beheerders maken portaal- en openbare webformulieren met vaste doelqueue,
meertalige teksten en eigen velden. Een klantformulier kan voor iedereen of een
selectie gelden. Zonder individueel formulier blijft standaard ticketaanmaak.

Openbare formulieren krijgen link en iframecode. Content Security Policy,
honeypot, tijdcontrole en limieten beschermen ze. Naam en e-mail zijn verplicht;
er ontstaat geen actief account. Alle waarden worden als onveranderlijke
momentopname naast dynamische velden bewaard. Agenten zien `Formulierinformatie`,
klanten `Uw formuliergegevens`. Latere wijzigingen veranderen oude inzendingen niet.

## CMDB

De CMDB legt geen CI-typen op. Beheerders definiëren typen, veldgroepen,
verplichtingen, keuzes, uniciteit, statussen en relaties en beheren inventaris,
toewijzingen, archivering en imports. Agenten wijzigen geen stamdata; zij zoeken
en koppelen CI’s in tickets en openen ze alleen-lezen. Samenvoegen draagt alle
koppelingen over.

Elke wijziging komt in een onveranderlijke historie. CSV-profielen koppelen
kolommen, waarden en regels aan Qisutu-velden; een externe ID verzorgt matching
per bron. Uitvoering kan handmatig of via cron:

```bash
/opt/qisutu/bin/qisutu-cmdb-import.pl --profile 1 --file /srv/import/idoit.csv
```

Het portaal toont alleen actieve CI’s en velden die expliciet voor de ingelogde
klant of het contact zijn vrijgegeven.

## CSV-import van stamgegevens

Er zijn aparte imports voor klanten, contacten en agenten. Actieve dynamische
velden worden als `dynamic.<veldnaam>` toegevoegd; download daarom de actuele
sjabloon uit het doelsysteem. Elk bestand wordt volledig gecontroleerd. De
preview onderscheidt nieuwe, gewijzigde, ongewijzigde en foutieve regels; één
fout blokkeert alles. Na bevestiging worden alle regels in één transactie
geschreven. Klantnummer of login is uniek. Ontbrekende records worden niet
verwijderd of gedeactiveerd.

Wachtwoorden, groepen en rechten staan niet in CSV. Bestaande rechten blijven en
nieuwe agenten krijgen geen rechten. Na import kunnen nieuwe actieve contacten
en agenten een uitnodiging voor hun eerste wachtwoord ontvangen.

## Kennisbank en FAQ

Alle agenten kunnen meertalige categorieën en FAQ-artikelen maken. Een artikel
heeft een uniek nummer, taal en zichtbaarheid `Alleen agenten` of
`Agenten en klanten`. Groepsrechten, queues, klantspecifieke vrijgave en extra
publicatiestatus horen niet bij de logica. Elke opslag maakt een onveranderlijke
revisie.

Artikelen `Agenten en klanten` verschijnen in het portaal. Naast CKEditor kunnen
agenten oplossing, titel met oplossing of portaallink invoegen. Voor klantzichtbare
e-mails en notities worden alleen `Alleen agenten`-artikelen geblokkeerd. Gebruik
van revisies wordt vastgelegd.

## Agentthema’s

Agenten kiezen hun thema onder `Persoonlijke instellingen`; het wordt als gewone
voorkeur bewaard. Het thema `Kerstmis` voegt subtiele statische decoratie toe aan
agentpagina’s, niet aan beheer of klantportaal. Andere thema’s gebruiken
`core/config/themes`, CSS in `var/static/css/themes` en eventueel afbeeldingen
in `var/static/img/themes`. Het centrale register valideert alles.

## Beveiligingsfuncties

Webwijzigingen gebruiken sessiegebonden CSRF-tokens; de REST-API aparte Bearer
tokens. Headers voorkomen MIME-sniffing en ongewenste inbedding. Cookies zijn
`HttpOnly`, `SameSite=Lax` en bij HTTPS `Secure`.

IMAP/SMTP-wachtwoorden, OAuth-geheimen en -tokens en 2FA-geheimen worden
versleuteld met `var/secure/security.key`, die in een beveiligde back-up hoort.
Agenten en contacten kunnen TOTP per lokaal gegenereerde QR activeren en krijgen
herstelcodes. Beheerders kunnen 2FA per accounttype afdwingen en resetten.

## Databaseconfiguratie

De verbinding staat in `core/config/QisutuConfig.pm`. De installer schrijft
host, poort, database, gebruiker en willekeurig wachtwoord. Strenge rechten
beschermen het bestand.

## Licentie

Qisutu valt onder GNU Affero General Public License versie 3 of later
(`AGPL-3.0-or-later`). De volledige voorwaarden staan in `LICENSE`.

Copyright (C) 2026 Franziska Steps.

## Software van derden

Bestanden van derden behouden hun oorspronkelijke vermeldingen. De samenvatting
staat in `THIRD_PARTY_NOTICES.md`.
