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

# Qisutu-Zusatzmodule verwalten

Qisutu installiert fertige Zusatzmodule aus gewöhnlichen ZIP-Dateien. Das ZIP
enthält den vollständigen lesbaren Modulquellcode und im Modulhauptverzeichnis
die Installationsbeschreibung `qisutu-module.json`. Es gibt kein eigenes
binäres Paketformat und kein Werkzeug zur Modulerstellung im Qisutu-Kern.

Administratoren laden ein Modul unter `Administration > Zusatzmodule` hoch.
Qisutu erkennt anhand der Modulkennung selbstständig, ob es sich um eine
Neuinstallation oder ein Update handelt. Ein Update wird nur mit einer höheren
Modulversion akzeptiert. Die eigentliche Dateioperation führt der
Qisutu-Daemon außerhalb des Webprozesses aus.

## Installationsbeschreibung

`qisutu-module.json` ist eine lesbare JSON-Datei. Sie verwendet
`"manifest_version": 1` und enthält mindestens Modulkennung, Name, Version,
kompatible Qisutu-Versionen sowie die vollständige Dateiliste. Jeder Eintrag
der Dateiliste nennt den relativen Pfad und die Berechtigung `0644` oder – nur
für Skripte unter `bin/` – `0755`.

Das ZIP darf `qisutu-module.json` direkt oder gemeinsam mit allen Moduldateien
in genau einem äußeren Modulordner enthalten. Nicht deklarierte Dateien,
fehlende Dateien, absolute Pfade, Pfadwechsel mit `..`, doppelte Einträge und
unzulässige Hauptverzeichnisse werden abgewiesen. Zulässig sind `lib/`,
`programs/`, `templates/`, `languages/`, `static/`, `migrations/`, `bin/` und
`apache/` sowie die üblichen Dokumentations- und Lizenzdateien im Modulstamm.

Perl-Klassen bleiben im Namensraum `Qisutu::Addon`. Programme eines Moduls
liegen als lesbare JSON-Dateien unter `programs/` und können eigene
Admin-Menüpunkte und eigene Administrationsmasken bereitstellen. Qisutu
verhindert, dass ein Modul vorhandene Kernprogramme, Kerntemplates oder
Kernübersetzungen überschreibt.

## Lebenszyklus

- Installation prüft das gesamte ZIP, legt das Modul getrennt unter `addons/`
  ab und aktiviert seine deklarierten Programme und Hintergrundaufgaben.
- Update verlangt eine höhere Modulversion und ersetzt die Moduldateien
  atomar. Einstellungen und Moduldaten bleiben erhalten.
- Deinstallation entfernt Moduldateien, veröffentlichte statische Dateien und
  Hintergrundaufgaben. Einstellungen, Identitätszuordnungen,
  Migrationshistorie und fachliche Moduldaten bleiben zur Sicherheit erhalten.

Die Entwicklung und Zusammenstellung eines Zusatzmoduls erfolgt vollständig
außerhalb von Qisutu. Der Qisutu-Kern liefert weder Beispielmodule noch
Generatoren oder Bauwerkzeuge für Zusatzmodule aus.

## Versionierte interne Zusatzmodul-API

Qisutu 1.0.1 stellt die interne Zusatzmodul-API `1.0` bereit. Alle neuen
Erweiterungspunkte sind ergänzend; vorhandene Manifeste ohne `addon_api`
bleiben gültig. Ein neues Modul kann seine Anforderungen ausdrücklich nennen:

```json
"addon_api": {
  "minimum": "1.0",
  "maximum": "1.99",
  "capabilities": [
    "services.v1",
    "events.v1",
    "rest-routes.v1",
    "ui-slots.v1"
  ]
}
```

Der Modulmanager lehnt die Installation ab, wenn die laufende Standardversion
von Qisutu die geforderte API oder eine Fähigkeit nicht besitzt. Dann wird
zuerst Qisutu aktualisiert und anschließend dasselbe eigenständige Modul-ZIP
installiert. Es entstehen keine kunden- oder modulspezifischen Qisutu-Kerne.

Die API stellt jeder Handlerklasse ein Objekt `API` bereit. Wesentliche
Methoden sind:

- `Version()` und `CapabilityAvailable(Capability => 'events.v1')`
- `Identifier()` für die eigene Modulkennung
- `SettingsGet()` und `SettingsSave(Values => {...}, UserID => ...)`
- `ServiceGet(Service => 'service.key')` für den eigenen Dienst
- `ServiceGet(Service => 'anderes.modul:service.key')` für einen ausdrücklich
  veröffentlichten Dienst eines anderen aktiven Moduls
- `EventEmit(Event => 'hersteller.modul.ereignis', Payload => {...})`

Alle Perl-Klassen der folgenden Erweiterungspunkte müssen im Namensraum
`Qisutu::Addon` liegen.

## Wiederverwendbare Moduldienste

Ein Modul veröffentlicht einen Dienst mit:

```json
"services": [
  {
    "key": "directory.agent",
    "class": "Qisutu::Addon::Example::DirectoryService"
  }
]
```

Qisutu lädt die Klasse erst bei Bedarf und erzeugt sie mit `Config`, `DB`,
`API` und `Definition`. Das erzeugte Objekt wird innerhalb des laufenden
Prozesses wiederverwendet. Dadurch können mehrere Programme, Aufgaben,
REST-Handler oder andere Module dieselbe fachliche Implementierung nutzen.

## Ereignisse und Daemon-Verarbeitung

Abonnements stehen in `event_subscribers`:

```json
"event_subscribers": [
  {
    "key": "ticket-created",
    "event": "ticket.created",
    "class": "Qisutu::Addon::Example::TicketEvent",
    "method": "Handle",
    "mode": "async"
  },
  {
    "key": "all-ticket-events",
    "event": "ticket.*",
    "class": "Qisutu::Addon::Example::AuditEvent",
    "method": "Handle",
    "mode": "async"
  }
]
```

`async` ist der Standard. Qisutu speichert jede Zustellung dauerhaft in
`addon_event_queue`; der Qisutu-Daemon sperrt die Arbeit pro Datensatz,
wiederholt fehlgeschlagene Zustellungen bis zu dreimal und kennzeichnet das
Endergebnis. Fehler eines Zusatzmoduls verhindern daher nicht die ursprüngliche
Ticket- oder E-Mail-Aktion. `sync` ist nur für sehr kurze, rein lokale Handler
vorgesehen und wird ebenfalls gegen Fehler des Moduls abgeschirmt.

Der Handler wird mit `Event`, `Source`, `Payload` und `API` aufgerufen und gibt
bei Erfolg einen wahren Wert oder einen Hash zurück. Qisutu 1.0.1 veröffentlicht:

- `ticket.created`, `article.created`
- `ticket.state_changed`, `ticket.priority_changed`, `ticket.queue_changed`
- `ticket.service_changed`, `ticket.customer_changed`
- `ticket.owner_changed`, `ticket.responsible_changed`
- `mail.received`, `mail.sent`
- `addon.installed`, `addon.updated`, `addon.uninstalling`

Ereignisnutzdaten enthalten Kennungen und technische Metadaten, aber keine
Nachrichtenkörper, Passwörter oder Modulgeheimnisse. Eigene Ereignisse müssen
einen mehrteiligen, stabilen Namen besitzen, beispielsweise
`hersteller.modul.synchronisiert`.

## Eigene REST-Routen

REST-Routen eines Moduls liegen ausschließlich unter dem eigenen Namensraum:

```json
"rest_routes": [
  {
    "key": "agent-sync-status",
    "method": "GET",
    "path": "/v1/addons/example.entraid/agents/{agent_id}",
    "class": "Qisutu::Addon::Example::AgentREST",
    "handler_method": "Handle",
    "scopes": ["example.entraid.read"],
    "access_types": ["agent"]
  }
]
```

Zulässig sind `GET`, `POST`, `PUT`, `PATCH` und `DELETE`. Platzhalter bestehen
aus einem sicheren Namen in geschweiften Klammern. Qisutu authentifiziert das
API-Token vor dem Modulaufruf, prüft alle deklarierten Scopes und optional den
Kontotyp. Eigene Scopes erscheinen automatisch in der normalen
API-Tokenverwaltung unter „Zusatzmodule“.

Der Handler erhält `Method`, `Path`, `PathParameters`, `Query`, `Body`, `Token`,
`RequestID` und `API`. Er gibt beispielsweise
`{ Status => 200, Data => {...} }` zurück. Direkte CGI-Ausgabe, freie
Header-Manipulation und das Überschreiben einer Kernroute sind nicht möglich.

## Kontrollierte UI-Einfügepunkte

Zusätzliche Inhalte werden nicht durch Änderungen an Kerntemplates eingebaut,
sondern über benannte Einfügepunkte:

```json
"ui_slots": [
  {
    "key": "directory-status",
    "slot": "admin.after",
    "class": "Qisutu::Addon::Example::StatusUI",
    "method": "Render",
    "order": 1000,
    "access_types": ["agent"]
  }
]
```

Unterstützt werden jeweils `.before` und `.after` für `page`, `dashboard`,
`ticket.zoom` und `admin`. Optional begrenzt `program` den Einfügepunkt auf
ein konkretes registriertes Programm. Der Handler erhält `Slot`, `Program`,
`User`, `Data` und `API` und gibt ausschließlich den Namen eines eigenen
Templates sowie dessen Daten zurück, beispielsweise
`{ Template => 'ExampleStatus.tt', Data => {...} }`. Die Ausgabe wird über den
normalen Qisutu-Template- und CSRF-Mechanismus erzeugt.

## Bestehende Schnittstellen

Die bisherigen Schnittstellen bleiben Bestandteil der API 1.0:

- `settings` für Text-, Geheimnis-, Boolean-, Integer- und Auswahleinstellungen
- `programs/*.json` für eigene Programme, Admin-Links und Masken
- `auth_providers` für Agenten- oder Kundenanmeldung
- `tasks` für wiederkehrende Daemon-Aufgaben; Aufgaben erhalten jetzt ebenfalls
  das Objekt `API`
- `migrations` für unveränderliche, protokollierte SQL-Migrationen
- `templates`, `languages` und `static` für isolierte Oberflächenbestandteile

Erweiterungspunkte werden in zukünftigen Kernversionen innerhalb ihrer
Hauptversion kompatibel gehalten. Eine inkompatible Neugestaltung erhält eine
neue API-Hauptversion und ersetzt die API 1.0 nicht stillschweigend.
