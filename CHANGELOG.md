# Qisutu release notes

This file records human-readable changes and upgrade impact for published Qisutu releases. Publicly known vulnerabilities fixed in a release are listed with their CVE or other public identifier. If no such vulnerability is listed, none was publicly known with an assigned identifier when that release was prepared.

## 1.0.3

Qisutu 1.0.3 is a stable maintenance and quality release. Customer and public ticket forms now accept multiple attachments, enforce the configured maximum attachment size, and provide localized selection and error messages. Administrators can optionally keep standard customer ticket creation available alongside configured customer forms. Customer queue selection has also been corrected so that customers can choose from the active target queues.

System-generated HTML email messages can now use a configurable company name and company logo. The report designer has been reorganized for clearer and more responsive operation, and reports can be shared with multiple active agent groups through a compact multiple-selection control. Inactive agents can be reactivated directly from the agent overview. File-selection controls are localized in all eleven interface languages, the Italian translation has been comprehensively revised, and layout problems in reports, the knowledge base, and other wide administrative views have been corrected.

Additional corrections improve indexing rules for the public login page, protect salutations and signatures in the agent ticket editor against accidental changes, and remove unwanted spacing around these template elements. The release also adds complete external REST API documentation, contribution and development guidance, a security-reporting policy, a maintained changelog, Perl::Critic configuration, a static-analysis command, and additional regression tests.

Upgrade impact: use the included `update.sh` process described in `INSTALL.md`. The database version remains 1.0.2 and no new database migration is required. The versioned internal add-on API remains unchanged.

No publicly known Qisutu runtime vulnerability with a CVE or comparable public identifier was fixed in this release.

## 1.0.2

Qisutu 1.0.2 is a stable production release. It introduces the versioned internal add-on API 1.0, controlled add-on REST routes and permissions, durable daemon-delivered core events, and controlled user-interface insertion points. Existing add-ons without an API declaration remain compatible.

The release also expands operational ticketing and administration with time accounting, Microsoft 365 and Google OAuth2 for mail retrieval and SMTP, communication logging with secret redaction, configurable customer auto-responses, separate LDAP and Active Directory profiles, customer and public forms, a configurable CMDB, transactional CSV master-data imports, a revisioned knowledge base, two-factor authentication, and eleven complete interface languages.

Upgrade impact: use the included `update.sh` process described in `INSTALL.md`. The updater preserves instance configuration, can create a database backup, applies maintained database migrations, and updates managed program files. Add-ons that declare a required internal API version may require the corresponding Qisutu core version.

No publicly known Qisutu runtime vulnerability with a CVE or comparable public identifier was fixed in this release.

## Release-note policy

Every future stable release must add a section before publication. It must describe major user-visible changes, compatibility and migration effects, and every Qisutu runtime vulnerability fixed by the release that already has a CVE or comparable public identifier. Release notes are not generated from the raw Git commit log.
