# Qisutu

Qisutu is a new open-source ticket system under active development. The current
codebase uses Perl/CGI, MariaDB or MySQL, Template Toolkit templates and a
browser-based user interface.

Project website: https://qisutu.de

## Development status

Qisutu is currently in an early development phase. Interfaces, database
structures and installation procedures may still change. The current repository
should not yet be treated as a finished production release.

## Repository structure

- `bin/` – CGI entry point and command-line jobs
- `core/` – configuration, programs, modules, templates, languages and system classes
- `database/qisutu.sql` – MariaDB/MySQL structure dump without application data
- `scriptfiles/` – Apache configuration example
- `var/static/` – Qisutu frontend assets and bundled third-party assets

## Database configuration

The database connection is configured directly in
`core/config/QisutuConfig.pm`. During installation, enter the database host,
port, database name, database user and database password in the `Database`
section of that file.

## License

Qisutu is licensed under the GNU Affero General Public License, version 3 or any
later version (`AGPL-3.0-or-later`). See `LICENSE` for the complete terms.

Copyright (C) 2026 Franziska Steps.

## Third-party software

Bundled third-party files retain their original copyright and license notices.
CKEditor 5 is located below `var/static/js/ckeditor5/` and
`var/static/css/ckeditor5/`; its license information is stored in the respective
`LICENSE.md` files and summarized in `THIRD_PARTY_NOTICES.md`.
