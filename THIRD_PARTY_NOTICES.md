# Third-party notices

## QR Code Generator

Qisutu bundles QR Code Generator version 2.0.4 to create TOTP setup QR codes
locally in the browser.

Copyright (c) 2009 Kazuhiko Arase

QR Code Generator is provided under the MIT License. The bundled license text
is included as `var/static/js/qrcode-generator/LICENSE.txt`. Qisutu loads the
library only from its own static file path and does not send the two-factor
secret to a CDN or another external runtime service.

## Chart.js

Qisutu bundles Chart.js version 4.5.1 for the offline dashboard charts.

Copyright (c) 2014-2025 Chart.js Contributors

Chart.js is provided under the MIT License. The bundled license text is
included as `var/static/js/chartjs/LICENSE.md`. Qisutu loads the library only
from its own static file path and does not use a CDN or another external
runtime service.

## CKEditor 5

Qisutu bundles CKEditor 5 version 48.1.0 frontend files.

Copyright (c) 2003-2026, CKSource Holding sp. z o.o. All rights reserved.

The bundled open-source distribution is provided under the GNU General Public
License, version 2 or any later version. The original notices in the CKEditor
files have not been changed. The applicable license text is included as:

- `var/static/js/ckeditor5/LICENSE.md`
- `var/static/css/ckeditor5/LICENSE.md`

CKEditor is a trademark of CKSource Holding sp. z o.o.

## OFORK OAuth2 mail integration

The OAuth2 mail-account flow in `core/system/QisutuOAuth2.pm` was adapted for
the Qisutu core from the OFORK OAuth2 module supplied for this integration.

Copyright (C) 2010-2022 OFORK, https://o-fork.de/

The source module and Qisutu are licensed under the GNU Affero General Public
License, version 3. The adapted Qisutu source file retains the OFORK copyright
and license notice. No separate OFORK add-on or installable module is bundled;
the functionality is integrated into the Qisutu core.
