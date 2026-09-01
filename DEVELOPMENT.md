# Qisutu development and test policy

Qisutu is distributed as Perl source and browser assets and does not require a separate compilation step. Installation and update behavior is documented in `INSTALL.md`.

## Automated tests

From the repository root, run the complete public test suite with:

`prove -Icore/system -Icore/config -Icore/cpan-lib -r t`

Run an individual test by replacing `-r t` with its path, for example:

`prove -Icore/system -Icore/config -Icore/cpan-lib t/rest-api.t`

Tests use Perl's standard TAP format and are released under the same AGPL-3.0-or-later license as Qisutu. A test must exit successfully and report no failed assertions before a release is approved. Test failures and relevant warnings are treated as defects and must be resolved or explicitly shown to be caused by an unsupported test environment.

## Policy for changes

Major new functionality and corrections for reproducible defects must include or update automated tests whenever the behavior can be tested reliably. Tests must cover the successful path and relevant validation, permission, or error paths. Documentation and migration tests must be updated when public behavior, external interfaces, database structures, installation, or updates change.

Recent examples include the public REST API tests in `t/rest-api.t`, add-on framework tests in `t/addon-framework.t`, customer automatic-response tests in `t/customer-auto-responses.t`, LDAP authentication tests in `t/ldap-authentication.t`, and release-integrity tests in `t/release-package-integrity.t`.

## Perl warnings and syntax checks

Production Perl files use `strict` and `warnings`. Changed Perl files must keep these modes enabled. Syntax can be checked with the repository's configured include paths, for example:

`perl -Icore/system -Icore/config -Icore/cpan-lib -c core/system/QisutuRESTAPI.pm`

Warnings produced by the test suite or syntax checks must be investigated and corrected. Warning suppression must be limited to a documented, unavoidable case and must not hide unrelated warnings.

## Release analysis

Before a major production release, maintainers review the changed Perl code with a FLOSS static analysis tool in addition to Perl's syntax, `strict`, and `warnings` checks. Confirmed exploitable findings of medium or higher severity must be corrected before release. Web-facing changes are also tested against malformed input, missing permissions, and unsuccessful authentication; confirmed medium or higher severity findings from dynamic testing are corrected before release.

The exact tool and command used for a release must be recorded with the internal release test results because the applicable checks depend on the changed languages and components.
