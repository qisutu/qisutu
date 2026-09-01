# Security Policy

## Supported versions

Security updates are provided for the latest stable Qisutu release. Users should update to the latest stable release before reporting a problem that has already been corrected there.

## Reporting a vulnerability

Do not report suspected vulnerabilities through a public GitHub issue, discussion, or pull request.

Send a private report to `support@qisutu.de` with the subject `Qisutu security report`. Include, where possible:

- the affected Qisutu version and installed add-ons;
- the affected component or endpoint;
- the prerequisites and steps needed to reproduce the problem;
- the observed and expected behavior;
- the possible security impact;
- logs, proof-of-concept material, or screenshots with credentials and personal data removed;
- whether the issue has already been disclosed elsewhere.

Qisutu will acknowledge a vulnerability report within 14 calendar days. The initial response will confirm receipt or request information required to reproduce and assess the report. Valid reports are investigated privately. A fix and coordinated disclosure date will be prepared according to severity and practical release constraints.

Please do not access data that does not belong to you, disrupt production systems, or disclose a suspected vulnerability before a fix or an agreed disclosure date is available.

## Public disclosure and updates

Confirmed vulnerabilities fixed in a release are identified in the release notes. When a CVE or another public vulnerability identifier exists at release time, that identifier is included. Security fixes are distributed through the same HTTPS release channel and update process as other Qisutu releases.

## Scope

This process covers the Qisutu source code in this repository. Vulnerabilities that only affect an operating system, database, web server, browser, or separately distributed add-on should also be reported to the maintainer of that component.
