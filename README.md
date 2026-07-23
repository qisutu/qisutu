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

# Qisutu

Qisutu ist ein neues Open-Source-Ticketsystem auf Basis von Perl/CGI,
MariaDB beziehungsweise MySQL, Template Toolkit und einer browserbasierten
Benutzeroberfläche.

Projektwebsite: https://qisutu.de

## Release-Status

Qisutu ist ein eigenständig installierbares Open-Source-Ticketsystem mit
Agenten- und Kundenportal, E-Mail-Verarbeitung, Verzeichnisanmeldung,
Automatisierung, Wissensdatenbank, CMDB, Berichten und REST-API. Qisutu 1.0.1
ist eine stabile, für den produktiven Einsatz freigegebene Version. Qisutu
befindet sich damit nicht mehr in der Entwicklungsphase. Schnittstellen und
Datenbankstrukturen werden im Rahmen der regulären Releasepflege
weiterentwickelt; notwendige Änderungen werden über
den integrierten Updater und die dauerhaft mitgeführten Datenmigrationen
bereitgestellt.

## Installation

Die folgenden Befehle als root im Verzeichnis `/opt` ausführen:

    wget https://o-fork.de/inst-kim/qisutu-1.0.1.tar.gz
    tar xzf qisutu-1.0.1.tar.gz
    mv qisutu-1.0.1 qisutu

    useradd -d /opt/qisutu -c 'Qisutu user' qisutu
    usermod -G www-data qisutu

    chown qisutu:www-data -R qisutu

    cd /opt/qisutu
    chmod +x install.sh
    ./install.sh

Der Name des Instanzverzeichnisses bestimmt die technischen Instanzwerte
unmittelbar. Aus `/opt/qisutu` entsteht die Instanz `qisutu`. Es wird kein
zusätzliches `qisutu-`-Präfix ergänzt.

Anschließend die vom Skript ausgegebene Adresse öffnen, beispielsweise:

    http://SERVER/qisutu/install.pl

Danach den sechs Schritten des Webinstallers folgen.

`install.sh` erkennt das Betriebssystem, installiert die benötigten Pakete und
Perl-Module und richtet für jede Qisutu-Instanz eine eigene Apache-Einbindung,
eigene systemd-Dienste, einen eigenen Webpfad und eine eigene
Datenbankkonfiguration ein. Dadurch können Produktiv- und Testsystem parallel
auf demselben Server laufen.

Der Webinstaller erstellt die jeweilige Datenbank, den festgelegten
Datenbankbenutzer, die Tabellenstruktur aus `install/sql/schema.sql`, die
Grunddaten aus `install/sql/insert.sql` und das erste Administratorkonto. Das
zufällig erzeugte Datenbankpasswort wird direkt in
`core/config/QisutuConfig.pm` der betreffenden Instanz geschrieben.

Ausführliche Hinweise und ein vollständiges Beispiel für zwei parallele
Instanzen stehen in `INSTALL.md`.

## Update

Die folgenden Befehle als root im Verzeichnis `/opt` ausführen:

    wget https://o-fork.de/inst-kim/qisutu-1.0.1.tar.gz
    tar xzf qisutu-1.0.1.tar.gz

    chown qisutu:www-data -R /opt/qisutu-1.0.1

    cd /opt/qisutu-1.0.1
    chmod +x update.sh
    ./update.sh

    cd /opt
    rm -R qisutu-1.0.1
    rm qisutu-1.0.1.tar.gz

Der Updater erkennt die Instanz über `var/install/instance.conf`, stoppt nur
deren Daemon und sperrt deren Mailabruf. Er kopiert alle verwalteten
Programmdateien direkt in die bestehende Installation, ohne Instanzdateien,
Apache-Konfiguration oder systemd-Konfiguration zu überschreiben. Auf Wunsch
erstellt er zusätzlich einen Datenbankdump. Tabellenstruktur und alle dauerhaft
mitgeführten Datenmigrationen werden vollständig geprüft und bei Bedarf
ergänzt. Details stehen in `INSTALL.md`.

## Verzeichnisstruktur

- `bin/` – CGI-Einstieg, Hintergrundprozesse und Kommandozeilenprogramme
- `core/` – Konfiguration, Module, Templates, Sprachen und Systemklassen
- `install/sql/schema.sql` – vollständige Tabellenstruktur
- `install/sql/insert.sql` – Grunddaten für eine Neuinstallation
- `scriptfiles/` – Apache- und systemd-Vorlagen
- `var/static/` – Frontend-Assets und eingebundene Drittanbieter-Assets

## Zusatzmodule

Qisutu besitzt ab Version 0.0.78 einen eigenen Modulmanager für gewöhnliche
Modul-ZIP-Dateien mit lesbarer `qisutu-module.json`.
Administratoren können Zusatzmodule im Adminbereich installieren,
aktualisieren und deinstallieren. Die eigentlichen Dateioperationen führt der
Qisutu-Daemon getrennt vom Webprozess aus. Eigene Admin-Links und
Konfigurationsmasken werden vom jeweiligen Zusatzmodul bereitgestellt;
Geheimnisse können verschlüsselt gespeichert werden.

Mit Qisutu 1.0.1 stellt der Kern zusätzlich die versionierte interne
Zusatzmodul-API 1.0 bereit. Sie umfasst wiederverwendbare Moduldienste,
dauerhaft über den Daemon zugestellte Kernereignisse, isolierte REST-Routen
mit eigenen API-Berechtigungen und kontrollierte UI-Einfügepunkte. Bestehende
Module ohne API-Angabe bleiben kompatibel. Ein Modul kann seine benötigte
API-Version und einzelne Fähigkeiten deklarieren; bei Bedarf fordert Qisutu
vor der Installation ein reguläres Kernupdate an, ohne kundenspezifische
Kernvarianten zu erzeugen.

Der Qisutu-Kern enthält bewusst keine konkreten Zusatzmodule. Zusatzmodule
werden als eigenständige Projekte entwickelt, als normale ZIP-Dateien mit
vollständigem lesbaren Quellcode veröffentlicht und ausschließlich über den
Adminbereich installiert. Installationsablauf und Sicherheitsprüfung beschreibt
`MODULES.md`.

## Zeiterfassung

Agenten können bei der Ticketerstellung, bei Artikeln und bei Ticketänderungen
optional Arbeitszeit in Stunden und Minuten erfassen. Jede Buchung unterscheidet
zwischen abrechenbarer und nicht abrechenbarer Zeit und kann einer im
Adminbereich gepflegten Tätigkeitsart zugeordnet werden. Manuelle Einzelbuchungen
sind ebenfalls möglich.

Zeitbuchungen sind revisionssicher: Sie werden nicht bearbeitet oder gelöscht.
Eine berechtigte Korrektur storniert die ursprüngliche Buchung mit Pflichtgrund
und legt eine verknüpfte Ersatzbuchung an. Die Korrekturberechtigung wird bei
Neuinstallation und Update nur der Admin-Gruppe zugewiesen. Zeitdaten werden
ausschließlich in Agenten- und Administrationsbereichen verarbeitet; Kundenmasken
und Kundenartikel enthalten keine Zeiterfassung.

## E-Mail-Abruf und OAuth2

Der Administrationsbereich bündelt eingehende E-Mail-Konten unter dem einzigen
Menüpunkt `E-Mail-Abruf`. Die dortige Übersicht zeigt vorhandene Konten und
bietet drei Einrichtungsarten an:

- Standard-IMAP mit Benutzername und Passwort
- Microsoft 365 mit OAuth2/XOAUTH2
- Google Workspace beziehungsweise Gmail mit OAuth2/XOAUTH2

Microsoft- und Google-Konten werden nach dem Speichern direkt zum jeweiligen
Anbieter weitergeleitet. Qisutu prüft den OAuth2-Rücksprung mit einem
kurzlebigen, einmalig verwendbaren Statuswert, speichert Access- und
Refresh-Token und testet anschließend die IMAP-Verbindung. Das Konto wird erst
nach erfolgreichem Test aktiviert. Abgelaufene Access-Tokens werden beim
Mailabruf automatisch mit dem Refresh-Token erneuert.

Der instanzbezogene Qisutu-Daemon ruft die eingerichteten Postfächer
automatisch alle fünf Minuten ab. Jede Instanz verwendet dabei ausschließlich
ihr eigenes Installationsverzeichnis und ihre eigene Konfiguration. Ein
zusätzlicher Cronjob für `qisutu-mail-fetch.pl` ist nicht erforderlich.

Inaktive Konten werden vor einer erneuten Aktivierung automatisch auf eine
funktionierende IMAP-/OAuth2-Verbindung geprüft. Ein Konto kann erst nach dem
Deaktivieren endgültig gelöscht werden. Dabei werden seine Zugangsdaten und
OAuth2-Tokens entfernt; vorhandene Postmaster-Verarbeitungsprotokolle bleiben
erhalten und werden vom gelöschten Konto entkoppelt.

Der Menüpunkt `SMTP settings` bietet dieselben klar getrennten Kontoarten für
den ausgehenden Versand: Standard-SMTP, Microsoft 365 und Google
Workspace/Gmail. Microsoft und Google verwenden dabei echte OAuth2-Tokens und
`AUTH XOAUTH2`; Microsoft erhält automatisch den Scope
`https://outlook.office.com/SMTP.Send`, Google den Scope
`https://mail.google.com/`. Access- und Refresh-Tokens werden verschlüsselt
gespeichert und automatisch erneuert. OAuth-SMTP-Konten werden erst nach
erfolgreicher Autorisierung und echtem SMTP-Verbindungstest aktiviert. In der
Kontomaske stehen außerdem `Neu verbinden` und `OAuth-Verbindung trennen` zur
Verfügung.

Vor der Einrichtung muss unter `Administration > System-Einstellungen` eine
von außen erreichbare HTTPS-Basis-URL für Qisutu hinterlegt sein. Die in der
jeweiligen Kontomaske angezeigte Weiterleitungs-URI muss beim OAuth2-Anbieter
exakt als erlaubte Redirect-URI registriert werden. Weitere Hinweise stehen in
`INSTALL.md`.

## Kommunikationsprotokoll

Unter `Administration > Kommunikationsprotokoll` werden IMAP-Abrufe,
SMTP-Versand und OAuth2-Tokenvorgänge mit Startzeit, Dauer, Ergebnis,
Kontosnapshot und einzelnen Verarbeitungsschritten protokolliert. Die Ansicht
bietet Kennzahlen sowie Filter nach Zeitraum, Protokoll, Richtung, Konto,
Status und Suchbegriff. Zu einer Nachricht werden nur technische Metadaten wie
Absender, Empfänger, Betreff, Message-ID und eine mögliche Ticketzuordnung
gespeichert; Nachrichtentexte und Anhänge werden nicht dupliziert.

Passwörter, Client-Secrets sowie Access- und Refresh-Tokens werden vor dem
Speichern aus technischen Antworten entfernt. Die Aufbewahrungsdauer ist in
den System-Einstellungen konfigurierbar und beträgt standardmäßig 90 Tage;
der Wert 0 deaktiviert die automatische Bereinigung.

## Automatische Antworten an Kunden

Unter `Administration > Autom. Antworten` stehen getrennte HTML-Vorlagen für
vier ausschließlich kundenbezogene Ereignisse bereit: ein durch den Kunden
erstelltes Ticket, eine Kundenantwort, eine Kundenantwort auf ein bereits
geschlossenes Ticket und eine durch einen Postmaster-Filter abgelehnte E-Mail.
Jede Vorlage besitzt einen eigenen Betreff, CKEditor-Text, Aktiv-Schalter und
Platzhalter für Ticket, Kundenbenutzer, System und eingehende E-Mail.

Die Vorlagen sind nach Installation oder Update zunächst deaktiviert. Dadurch
entscheidet der Administrator ausdrücklich, welche Bestätigungen versendet
werden. Für eine Ablehnungsantwort muss ein Postmaster-Filter die Aktion
`E-Mail ablehnen und automatische Antwort auslösen` verwenden; die bestehende
Aktion zum vollständigen Ignorieren einer E-Mail bleibt ohne Antwort. Von
Agenten erstellte Tickets und Agentenantworten lösen keine zusätzliche
Kundenmail aus.

## LDAP und Active Directory

Administratoren richten unter `Administration > LDAP / Active Directory` zwei
vollständig getrennte Profile ein: eines ausschließlich für Agenten und eines
für Kundenbenutzer und ihre Kundenunternehmen. Beide Profile besitzen eigene
Verbindungs-, Such-, Mapping-, Test- und Aktivierungseinstellungen. In den
Anmeldemasken ist keine Anbieterauswahl nötig; Qisutu verwendet abhängig vom
Portal automatisch das passende aktive Profil.

Login, Vorname, Nachname und E-Mail sind in beiden Profilen verpflichtende
Mappings. Das Agentenprofil kann zusätzliche Agentenfelder übernehmen und neu
angelegte Agenten einer Standardgruppe zuordnen. Das Kundenprofil benötigt
zusätzlich je ein LDAP-Attribut für die eindeutige Qisutu-Kundennummer und den
Namen des Kundenunternehmens; weitere Kundenbenutzerfelder können ebenfalls
gemappt werden. In Qisutu als erforderlich definierte Zusatzfelder benötigen
ein entsprechendes LDAP-Mapping und einen Wert im Verzeichnis.

Nach einer erfolgreichen Agentenanmeldung verwendet Qisutu den kanonischen
Wert des gemappten Login-Attributs für den Kontenabgleich. Ein bestehender
Agent mit diesem Login wird weiterverwendet, andernfalls wird ein neuer Agent
angelegt. Beim Kundenlogin wird das Kundenunternehmen anhand der gemappten
Kundennummer gefunden oder angelegt. Der Kundenbenutzer wird anhand seines
kanonischen Logins gefunden oder angelegt und genau diesem Unternehmen
zugeordnet. Eine bereits anderweitig verwendete E-Mail-Adresse führt zu einem
Fehler und niemals zu einer automatischen Kontenzusammenführung.

Die Verbindungen sind nur über LDAPS oder StartTLS möglich. Die
Zertifikatsprüfung ist standardmäßig aktiv, und das Passwort eines technischen
Suchkontos wird verschlüsselt gespeichert. Änderungen deaktivieren das
betroffene Profil; vor der erneuten Aktivierung müssen Verbindung,
Benutzersuche und alle Pflichtwerte erfolgreich getestet werden. Findet das
jeweilige aktive Verzeichnis keinen Benutzer, bleibt die Anmeldung eines
vorhandenen lokalen Kontos möglich. Bei einem gefundenen Verzeichniseintrag ist
dagegen dessen Passwortprüfung maßgeblich.

## Kundenformulare und Webformulare

Unter `Administration > Formulare` können Administratoren individuelle
Formulare für das Kundenportal und öffentliche Webformulare anlegen. Jedes
Formular besitzt eine feste Ziel-Queue, mehrsprachige Texte sowie eigene
optionale oder verpflichtende Felder. Kundenformulare können für alle oder nur
für ausgewählte Kunden freigegeben werden. Solange kein individuelles
Kundenformular vorhanden ist, bleibt die bisherige Standard-Ticketerstellung
im Kundenportal verfügbar.

Öffentliche Webformulare erhalten einen Direktlink und fertigen Iframe-Code.
Qisutu schützt sie mit Einbettungsfreigaben über Content Security Policy,
Honeypot und Zeitprüfung sowie konfigurierbaren Limits. Name und E-Mail sind
verpflichtend; Webformular-Kontakte erhalten kein aktives Login-Konto.

Alle Formularwerte werden zusätzlich zu den dynamischen Ticketfeldern als
unveränderlicher Übermittlungsstand gespeichert. Agenten sehen diesen Stand im
Ticket-Zoom unter `Formular-Informationen`, angemeldete Kunden unter
`Ihre Formularangaben`. Spätere Änderungen am Formular verändern bestehende
Übermittlungen nicht.

## CMDB

Die integrierte CMDB arbeitet ohne vorgegebene CI-Typen. Administratoren
definieren CI-Typen, Feldgruppen, Pflicht-, Auswahl- und eindeutige Felder,
Statuskataloge sowie gerichtete Beziehungsarten vollständig selbst. Auch das
CI-Inventar, Kunden- und Ansprechpartnerzuordnungen, Beziehungen, Archivierung
und Importe liegen ausschließlich im Administrationsbereich. Agenten ändern
keine CMDB-Stammdaten; sie suchen und verknüpfen CIs nur im Ticket-Zoom und
öffnen ein bereits verknüpftes CI dort schreibgeschützt. Beim Zusammenfassen
eines Tickets werden dessen CI-Verknüpfungen vollständig in das Zielticket
übernommen.

Jede fachliche Änderung wird in einer unveränderlichen CI-Historie
protokolliert. Herstellerunabhängige CSV-Importprofile ordnen Quellspalten,
Werte und Aktualisierungsregeln den Qisutu-Feldern zu. Der eindeutige Abgleich
erfolgt je Quelle über eine externe ID. Ein gespeichertes Profil kann manuell
oder nachts per Cron ausgeführt werden, zum Beispiel:

```bash
/opt/qisutu/bin/qisutu-cmdb-import.pl --profile 1 --file /srv/import/idoit.csv
```

Im Kundenportal werden ausschließlich aktive, ausdrücklich freigegebene CIs
des angemeldeten Kunden beziehungsweise Ansprechpartners und nur ausdrücklich
freigegebene CI-Felder angezeigt.

## CSV-Importe für Stammdaten

Unter `Administration > CSV-Importe` stehen getrennte Importe für Kunden,
Ansprechpartner und Agenten bereit. Die Grundstruktur ist fest vorgegeben;
aktive dynamische Felder der jeweiligen Qisutu-Installation werden automatisch
als `dynamic.<feldname>` an die Vorlage angehängt. Deshalb sollte die aktuelle
Vorlage immer direkt aus der Zielinstallation heruntergeladen werden.

Jeder Lauf wird zuerst vollständig geprüft. Die Vorschau zeigt neue,
geänderte, unveränderte und fehlerhafte Zeilen; bei einem Fehler ist der Import
gesperrt. Erst nach Bestätigung schreibt Qisutu alle Zeilen gemeinsam in einer
Datenbanktransaktion. Kundennummer beziehungsweise Login dienen als eindeutige
Abgleichschlüssel. Nicht in der CSV enthaltene Datensätze werden weder gelöscht
noch deaktiviert.

Passwörter, Agentengruppen und Berechtigungen sind bewusst nicht Bestandteil
der CSV. Bestehende Agentenrechte bleiben unverändert, neue Agenten erhalten
keine Gruppenrechte. Für neu angelegte aktive Ansprechpartner und Agenten kann
der Administrator nach erfolgreichem Import optional Einladungen zum Setzen
des ersten Passworts versenden.

## Wissensdatenbank und FAQ

Alle Agenten können Kategorien mit mehrsprachigen Bezeichnungen sowie
FAQ-Artikel anlegen und bearbeiten. Artikel besitzen eine eindeutige
FAQ-Nummer, Sprache und genau eine von zwei Sichtbarkeiten: „Nur Agenten“ oder
„Agenten und Kunden“. Gruppenrechte, Queue-Zuordnungen, kundenspezifische
Freigaben und ein zusätzlicher Veröffentlichungsstatus sind bewusst nicht Teil
der FAQ-Logik. Jede Speicherung erzeugt eine neue, unveränderliche Revision.

Im Kundenportal erscheinen alle Artikel mit der Sichtbarkeit „Agenten und
Kunden“. Agenten können beim
Erstellen und Bearbeiten eines Tickets direkt am CKEditor nach FAQ-Artikeln
suchen und Lösung, Titel mit Lösung oder einen Kundenportal-Link an der
aktuellen Cursorposition einfügen. Bei E-Mails und kundensichtbaren Notizen
blockiert Qisutu ausschließlich Artikel mit der Sichtbarkeit „Nur Agenten“.
Die Verwendung einer Revision wird am Artikel und –
soweit bereits vorhanden – am Ticket protokolliert.

## Agenten-Themes

Agenten wählen ihr Oberflächentheme unter `Persönliche Einstellungen` aus.
Die Auswahl wird als normale Benutzerpräferenz gespeichert. Das mitgelieferte
Theme `Weihnachten` ergänzt normale Agentenseiten um dezente, statische
Dekorationen; Administrationsseiten und das Kundenportal bleiben unverändert.

Weitere Themes werden als Konfiguration unter `core/config/themes`, als
eigenes Stylesheet unter `var/static/css/themes` und bei Bedarf mit eigenen
Grafiken unter `var/static/img/themes` ergänzt. Die zentrale Theme-Registry
prüft Schlüssel, Stylesheetpfade, Sichtbarkeit und den Ausschluss von
Administrationsseiten, bevor ein Theme geladen wird.

## Sicherheitsfunktionen

Browserbasierte Änderungen werden mit sitzungsgebundenen CSRF-Tokens
geschützt; die REST-API verwendet davon getrennte Bearer-Tokens. Zentrale
Antwortheader verhindern MIME-Sniffing und unerwünschte Einbettung interner
Masken. Sitzungscookies sind `HttpOnly`, verwenden `SameSite=Lax` und werden
bei HTTPS zusätzlich als `Secure` ausgegeben.

IMAP-/SMTP-Passwörter, OAuth-Client-Secrets, OAuth-Zugriffstokens und
Zwei-Faktor-Geheimnisse werden mit einem installationsabhängigen Schlüssel
verschlüsselt gespeichert. Dieser Schlüssel liegt ausschließlich unter
`var/secure/security.key` und muss Bestandteil einer geschützten
Systemsicherung sein.

Agenten und Kundenbenutzer können in ihren Einstellungen zeitbasierte
Zwei-Faktor-Authentifizierung (TOTP) per QR-Code mit Google Authenticator oder
einer anderen kompatiblen App aktivieren und erhalten einmal verwendbare
Wiederherstellungscodes. Der QR-Code wird ausschließlich lokal im Browser
erzeugt; das Zwei-Faktor-Geheimnis wird nicht an einen externen Dienst
übertragen. Administratoren können 2FA getrennt für
Administratoren, Agenten und Kundenbenutzer erzwingen sowie eine verlorene
Einrichtung am jeweiligen Konto zurücksetzen.

## Datenbankkonfiguration

Die Datenbankverbindung steht direkt in `core/config/QisutuConfig.pm`. Der
Webinstaller trägt Host, Port, Datenbankname, Benutzer und das zufällig erzeugte
Passwort dort automatisch ein. Die Datei wird durch restriktive Dateirechte
geschützt.

## Lizenz

Qisutu ist unter der GNU Affero General Public License, Version 3 oder einer
späteren Version (`AGPL-3.0-or-later`), lizenziert. Die vollständigen
Lizenzbedingungen stehen in `LICENSE`.

Copyright (C) 2026 Franziska Steps.

## Drittanbieter-Software

Eingebundene Drittanbieterdateien behalten ihre ursprünglichen Copyright- und
Lizenzhinweise. Die zusammenfassenden Hinweise stehen in
`THIRD_PARTY_NOTICES.md`.
