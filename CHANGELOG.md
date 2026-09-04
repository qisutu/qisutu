# Qisutu release notes

This file records human-readable changes and upgrade impact for published Qisutu releases. Publicly known vulnerabilities fixed in a release are listed with their CVE or other public identifier. If no such vulnerability is listed, none was publicly known with an assigned identifier when that release was prepared.

## 2.0.1

Qisutu 2.0.1 introduces direct collaboration between agents. The new internal chat shows which agents are online using a ten-minute activity window and refreshes the agent state every ten minutes. Its launcher is integrated into a stable lower sidebar action area and is positioned immediately before Kim when that add-on is installed. If Kim is absent, the internal-chat and Microsoft Teams launchers remain grouped in that same row directly above the user area instead of being distributed across the navigation or page. Agents can exchange direct messages, see unread messages, retain their conversation history, and explicitly delete the currently selected conversation.

Ticket collaboration is integrated with the chat. The ticket detail view shows which agents currently have the ticket open and lets an agent address any of them directly. If no other agent has the ticket open, an online colleague can be invited from the same presence row; Qisutu opens the direct chat and sends the ticket link together with an invitation message. Tickets can also be handed over directly in the chat. Qisutu verifies that the recipient may edit the ticket queue, changes the owner, creates a handover event in the conversation, and records an internal ticket note naming the sender and recipient.

Reports can now be delivered automatically by e-mail on a daily, weekly, or monthly schedule. A schedule can use the report's fixed filters or dynamically select the previous day, previous week, previous month, or a configurable number of completed days. Several active agents and arbitrary additional e-mail addresses can be combined as recipients. PDF, analysis CSV, and detail CSV attachments can be selected independently, while a delivery log records the result and prevents duplicate scheduled runs.

Customer and public ticket forms can optionally be linked to an active process template from the KimProcesses add-on. The selector is only displayed while KimProcesses is installed, active, and enabled. After a successful form submission, Qisutu starts the selected process automatically. If the process cannot be started or its first step fails, the ticket and its normal confirmation remain intact and Qisutu records the process name and error as an internal note.

Administrators can configure the e-mail retrieval interval in the system settings to 1, 2, 5, 10, 15, or 30 minutes. The running daemon reloads this setting automatically, so changing the interval does not require a service restart.

Services can now be linked directly to configuration items in the CMDB. The service administration shows assigned configuration items and supports adding or removing them through the CMDB search, while each configuration item displays all associated services. Every assignment and removal is recorded in the immutable configuration-item history. The new many-to-many relationship also provides the technical foundation for deriving affected services from configuration items in ITSM incidents, major incidents and changes, and for considering those services in impact displays and change-conflict detection.

FAQ articles in the knowledge base can now contain multiple attachments. Agents can add, review, download, retain, or remove these files while maintaining an article, and customer-visible FAQ attachments are also available through the protected customer portal download. When using a FAQ in either a new ticket or an existing ticket, agents choose independently whether to insert the FAQ text, attach the FAQ files, or do both. The selected FAQ files become normal ticket-article and e-mail attachments, remain removable before submission, and are checked again on the server for visibility, validity, and the configured attachment-size limit.

Upgrade impact: use the included `update.sh` process described in `INSTALL.md`. The database version is 2.0.1. The schema synchronization adds the internal-chat, ticket-presence, report-scheduling, recipient, delivery-log, service-to-configuration-item, and FAQ-attachment structures as well as the optional process-template reference on ticket forms without deleting existing data. The versioned internal add-on API remains at version 1.0.

No publicly known Qisutu runtime vulnerability with a CVE or comparable public identifier was fixed in this release.

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
