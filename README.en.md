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

Qisutu is a new open-source ticket system based on Perl/CGI, MariaDB or MySQL,
Template Toolkit, and a browser-based user interface.

Project website: https://qisutu.de

## Release status

Qisutu is an independently installable open-source ticket system with an agent
and customer portal, email processing, directory authentication, automation,
knowledge base, CMDB, reports, and REST API. Qisutu 1.0.2 is a stable release
approved for production use. Qisutu is therefore no longer in the development
phase. Interfaces and database structures continue to evolve as part of regular
release maintenance; required changes are delivered through the integrated
updater and permanently maintained data migrations.

## Languages

Qisutu 1.0.2 includes eleven complete interface languages: German (`de`),
English (`en`), French (`fr`), Italian (`it`), Brazilian Portuguese (`pt-BR`),
European Portuguese (`pt-PT`), Spanish (`es`), Dutch (`nl`), Polish (`pl`),
Czech (`cs`), and Turkish (`tr`).

## Installation

Run the following commands as root in `/opt`:

    wget https://ftp.qisutu.de/qisutu-1.0.2.tar.gz
    tar xzf qisutu-1.0.2.tar.gz
    mv qisutu-1.0.2 qisutu

    useradd -d /opt/qisutu -c 'Qisutu user' qisutu
    usermod -G www-data qisutu

    chown qisutu:www-data -R qisutu

    cd /opt/qisutu
    chmod +x install.sh
    ./install.sh

At the very beginning, `install.sh` asks for one of the eleven interface
languages. The selection is stored in the instance configuration, the web
installer opens immediately in that language, and the language is adopted as
the preset default for Qisutu.

The instance directory name directly determines the technical instance values.
`/opt/qisutu` creates the `qisutu` instance. No additional `qisutu-` prefix is
added.

Then open the address printed by the script, for example:

    http://SERVER/qisutu/install.pl

Follow the six steps of the web installer.

`install.sh` detects the operating system, installs the required packages and
Perl modules, and configures a separate Apache integration, systemd services,
web path, and database configuration for each Qisutu instance. Production and
test systems can therefore run side by side on the same server.

The web installer creates the selected database, the defined database user,
the table structure from `install/sql/schema.sql`, the base data from
`install/sql/insert.sql`, and the first administrator account. The randomly
generated database password is written directly to
`core/config/QisutuConfig.pm` for that instance.

Detailed instructions and a complete example for two parallel instances are
available in `INSTALL.md`.

## Update

Run the following commands as root in `/opt`:

    wget https://ftp.qisutu.de/qisutu-1.0.2.tar.gz
    tar xzf qisutu-1.0.2.tar.gz

    chown qisutu:www-data -R /opt/qisutu-1.0.2

    cd /opt/qisutu-1.0.2
    chmod +x update.sh
    ./update.sh

    cd /opt
    rm -R qisutu-1.0.2
    rm qisutu-1.0.2.tar.gz

The updater identifies the instance through `var/install/instance.conf`, stops
only its daemon, and locks only its mail retrieval. It copies all managed
program files directly into the existing installation without overwriting
instance files, Apache configuration, or systemd configuration. On request it
also creates a database dump. The table structure and all permanently
maintained data migrations are checked completely and supplemented where
necessary. Details are available in `INSTALL.md`.

## Directory structure

- `bin/` – CGI entry points, background processes, and command-line programs
- `core/` – configuration, modules, templates, languages, and system classes
- `install/sql/schema.sql` – complete table structure
- `install/sql/insert.sql` – base data for a new installation
- `scriptfiles/` – Apache and systemd templates
- `var/static/` – frontend assets and bundled third-party assets

## Add-ons

Starting with version 0.0.78, Qisutu has its own module manager for ordinary
module ZIP files with a readable `qisutu-module.json`. Administrators can
install, update, and uninstall add-ons in the administration area. The actual
file operations are performed by the Qisutu daemon, separately from the web
process. Each add-on provides its own administration links and configuration
screens; secrets can be stored in encrypted form.

With Qisutu 1.0.2, the core also provides the versioned internal add-on API 1.0.
It includes reusable module services, core events delivered persistently by the
daemon, isolated REST routes with their own API permissions, and controlled UI
insertion points. Existing modules without an API declaration remain
compatible. A module can declare its required API version and individual
capabilities; when necessary, Qisutu requests a regular core update before
installation without creating customer-specific core variants.

The Qisutu core deliberately contains no specific add-ons. Add-ons are
developed as independent projects, published as normal ZIP files with complete
readable source code, and installed exclusively through the administration
area. `MODULES.md` describes the installation process and security checks.

## Time accounting

Agents can optionally record working time in hours and minutes when creating a
ticket, adding articles, or changing a ticket. Each booking distinguishes
between billable and non-billable time and can be assigned to an activity type
maintained in the administration area. Manual individual bookings are also
possible.

Time bookings are audit-proof: they are not edited or deleted. An authorized
correction cancels the original booking with a mandatory reason and creates a
linked replacement booking. For new installations and updates, correction
permission is assigned only to the admin group. Time data is processed only in
agent and administration areas; customer screens and customer articles contain
no time accounting.

## Email retrieval and OAuth2

The administration area combines incoming email accounts under the single menu
item `Email retrieval`. Its overview shows existing accounts and offers three
setup types:

- Standard IMAP with username and password
- Microsoft 365 with OAuth2/XOAUTH2
- Google Workspace or Gmail with OAuth2/XOAUTH2

After saving, Microsoft and Google accounts are redirected directly to the
respective provider. Qisutu verifies the OAuth2 return with a short-lived,
single-use state value, stores access and refresh tokens, and then tests the
IMAP connection. The account is activated only after a successful test. Expired
access tokens are renewed automatically with the refresh token during mail
retrieval.

The instance-specific Qisutu daemon automatically retrieves configured
mailboxes every five minutes. Each instance uses only its own installation
directory and configuration. No additional cron job is required for
`qisutu-mail-fetch.pl`.

Inactive accounts are automatically tested for a working IMAP/OAuth2
connection before reactivation. An account can be deleted permanently only
after it has been deactivated. Its credentials and OAuth2 tokens are removed,
while existing postmaster processing logs are retained and detached from the
deleted account.

The `SMTP settings` menu item offers the same clearly separated account types
for outgoing mail: standard SMTP, Microsoft 365, and Google Workspace/Gmail.
Microsoft and Google use real OAuth2 tokens and `AUTH XOAUTH2`; Microsoft is
automatically granted the `https://outlook.office.com/SMTP.Send` scope and
Google the `https://mail.google.com/` scope. Access and refresh tokens are
stored encrypted and renewed automatically. OAuth SMTP accounts are activated
only after successful authorization and a real SMTP connection test. The
account screen also provides `Reconnect` and `Disconnect OAuth connection`.

Before setup, an externally reachable HTTPS base URL for Qisutu must be stored
under `Administration > System settings`. The redirect URI shown in the
respective account screen must be registered exactly as an allowed redirect URI
with the OAuth2 provider. Further information is available in `INSTALL.md`.

## Communication log

Under `Administration > Communication log`, IMAP retrievals, SMTP deliveries,
and OAuth2 token operations are logged with start time, duration, result,
account snapshot, and individual processing steps. The view provides metrics
and filters by time period, protocol, direction, account, status, and search
term. Only technical metadata such as sender, recipient, subject, Message-ID,
and a possible ticket assignment is stored for a message; message bodies and
attachments are not duplicated.

Passwords, client secrets, and access and refresh tokens are removed from
technical responses before storage. Retention can be configured in the system
settings and defaults to 90 days; a value of 0 disables automatic cleanup.

## Automatic replies to customers

Under `Administration > Automatic replies`, separate HTML templates are
available for four exclusively customer-related events: a ticket created by a
customer, a customer reply, a customer reply to an already closed ticket, and
an email rejected by a postmaster filter. Each template has its own subject,
CKEditor body, active switch, and placeholders for the ticket, customer user,
system, and incoming email.

After installation or update, the templates are initially disabled. The
administrator therefore explicitly decides which confirmations are sent. For a
rejection response, a postmaster filter must use the action `Reject email and
trigger automatic reply`; the existing action for completely ignoring an email
remains without a response. Tickets and agent replies do not trigger an
additional customer email.

## LDAP and Active Directory

Under `Administration > LDAP / Active Directory`, administrators configure two
completely separate profiles: one exclusively for agents and one for customer
users and their customer companies. Both profiles have their own connection,
search, mapping, testing, and activation settings. No provider selection is
required on the login screens; Qisutu automatically uses the appropriate active
profile for the portal.

Login, first name, last name, and email are mandatory mappings in both profiles.
The agent profile can import additional agent fields and assign newly created
agents to a default group. The customer profile additionally requires one LDAP
attribute for the unique Qisutu customer number and one for the customer company
name; further customer-user fields can also be mapped. Additional fields marked
as required in Qisutu require a corresponding LDAP mapping and a value in the
directory.

After a successful agent login, Qisutu uses the canonical value of the mapped
login attribute to match the account. An existing agent with that login is
reused; otherwise a new agent is created. At customer login, the customer
company is found or created using the mapped customer number. The customer user
is found or created using the canonical login and assigned to exactly that
company. An email address already used elsewhere causes an error and never an
automatic account merge.

Connections are possible only through LDAPS or StartTLS. Certificate validation
is enabled by default, and the password of a technical search account is stored
encrypted. Changes disable the affected profile; connection, user search, and
all mandatory values must be tested successfully before reactivation. If the
respective active directory does not find a user, an existing local account can
still log in. If a directory entry is found, its password verification is
decisive.

## Customer forms and web forms

Under `Administration > Forms`, administrators can create individual forms for
the customer portal and public web forms. Each form has a fixed destination
queue, multilingual texts, and its own optional or mandatory fields. Customer
forms can be enabled for all or only selected customers. As long as no
individual customer form exists, the previous standard ticket creation remains
available in the customer portal.

Public web forms receive a direct link and ready-to-use iframe code. Qisutu
protects them with embedding permissions through Content Security Policy,
honeypot and timing checks, and configurable limits. Name and email are
mandatory; web-form contacts do not receive an active login account.

All form values are stored as an immutable submission snapshot in addition to
the dynamic ticket fields. Agents see this snapshot in ticket zoom under
`Form information`, while logged-in customers see it under `Your form data`.
Later changes to the form do not alter existing submissions.

## CMDB

The integrated CMDB works without predefined CI types. Administrators define CI
types, field groups, required, selection, and unique fields, status catalogs,
and directed relationship types entirely themselves. The CI inventory,
customer and contact assignments, relationships, archiving, and imports are
also handled exclusively in the administration area. Agents do not modify CMDB
master data; they only search for and link CIs in ticket zoom and open an
already linked CI there in read-only mode. When tickets are merged, all CI
links are transferred to the target ticket.

Every functional change is recorded in an immutable CI history. Vendor-neutral
CSV import profiles map source columns, values, and update rules to Qisutu
fields. Unique matching is performed for each source using an external ID. A
saved profile can be run manually or nightly by cron, for example:

```bash
/opt/qisutu/bin/qisutu-cmdb-import.pl --profile 1 --file /srv/import/idoit.csv
```

The customer portal shows only active CIs explicitly released for the logged-in
customer or contact, and only CI fields that have explicitly been released.

## CSV imports for master data

Under `Administration > CSV imports`, separate imports are available for
customers, contacts, and agents. The base structure is fixed; active dynamic
fields of the respective Qisutu installation are automatically appended to the
template as `dynamic.<fieldname>`. The current template should therefore always
be downloaded directly from the target installation.

Each run is first checked in full. The preview shows new, changed, unchanged,
and erroneous rows; any error blocks the import. Only after confirmation does
Qisutu write all rows together in a database transaction. Customer number or
login is used as the unique matching key. Records not included in the CSV are
neither deleted nor disabled.

Passwords, agent groups, and permissions are deliberately not part of the CSV.
Existing agent permissions remain unchanged and new agents receive no group
permissions. After a successful import, the administrator can optionally send
invitations to newly created active contacts and agents to set their first
password.

## Knowledge base and FAQ

All agents can create and edit categories with multilingual names and FAQ
articles. Articles have a unique FAQ number, a language, and exactly one of two
visibility levels: `Agents only` or `Agents and customers`. Group permissions,
queue assignments, customer-specific releases, and an additional publication
status are deliberately not part of the FAQ logic. Each save creates a new,
immutable revision.

All articles with the visibility `Agents and customers` appear in the customer
portal. While creating or editing a ticket, agents can search for FAQ articles
directly next to CKEditor and insert the solution, title with solution, or a
customer-portal link at the current cursor position. For emails and
customer-visible notes, Qisutu blocks only articles with the visibility
`Agents only`. Use of a revision is logged on the article and, where already
available, on the ticket.

## Agent themes

Agents select their interface theme under `Personal settings`. The selection is
stored as a normal user preference. The included `Christmas` theme adds subtle,
static decorations to normal agent pages; administration pages and the customer
portal remain unchanged.

Additional themes are added as configuration under `core/config/themes`, as a
separate stylesheet under `var/static/css/themes`, and, when required, with
their own graphics under `var/static/img/themes`. Before loading a theme, the
central theme registry checks keys, stylesheet paths, visibility, and exclusion
from administration pages.

## Security features

Browser-based changes are protected with session-bound CSRF tokens; the REST
API uses separate bearer tokens. Central response headers prevent MIME sniffing
and unwanted embedding of internal screens. Session cookies are `HttpOnly`, use
`SameSite=Lax`, and are additionally issued as `Secure` over HTTPS.

IMAP/SMTP passwords, OAuth client secrets, OAuth access tokens, and two-factor
secrets are stored encrypted with an installation-specific key. This key is
located exclusively under `var/secure/security.key` and must be included in a
protected system backup.

Agents and customer users can activate time-based two-factor authentication
(TOTP) in their settings using a QR code with Google Authenticator or another
compatible app and receive one-time recovery codes. The QR code is generated
only locally in the browser; the two-factor secret is not sent to an external
service. Administrators can enforce 2FA separately for administrators, agents,
and customer users and reset a lost setup on the respective account.

## Database configuration

The database connection is stored directly in `core/config/QisutuConfig.pm`.
The web installer automatically enters the host, port, database name, user, and
randomly generated password. Restrictive file permissions protect the file.

## Project documentation

- `INSTALL.md` – installation, parallel instances, and updates
- `MODULES.md` – add-on format and internal add-on API
- `API.md` – complete external REST API reference
- `DEVELOPMENT.md` – tests, warnings, and development policy
- `CONTRIBUTING.md` – bug reports and contributions
- `SECURITY.md` – private vulnerability reporting
- `CHANGELOG.md` – release notes and upgrade impact

## License

Qisutu is licensed under the GNU Affero General Public License, version 3 or any
later version (`AGPL-3.0-or-later`). The complete license terms are available
in `LICENSE`.

Copyright (C) 2026 Franziska Steps.

## Third-party software

Bundled third-party files retain their original copyright and license notices.
A summary is available in `THIRD_PARTY_NOTICES.md`.
