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

## Static analysis release gate

Qisutu uses the FLOSS static-analysis tool Perl::Critic for all first-party Perl source files. Install Perl::Critic with your operating-system package manager or with:

`cpan Perl::Critic`

Run the repository's fixed analysis profile from the repository root:

`tools/qisutu-static-analysis`

The command analyzes the Perl files below `bin`, `core`, `t`, and `tools`, while excluding bundled third-party modules below `core/cpan-lib`. The committed `.perlcriticrc` profile includes high-severity correctness checks and checks for dangerous constructs associated with common vulnerabilities, including string evaluation, unsafe file opening, unchecked system calls, and prohibited modules.

This command is a mandatory release gate and must complete successfully before every production release. Its result is recorded with the release test results. Every confirmed exploitable finding of medium or higher severity must be corrected before release; suppressing such a finding is not permitted. A false positive may be suppressed only with a narrowly scoped source annotation that documents the technical reason and is reviewed by a maintainer.

Web-facing changes are additionally tested against malformed input, missing permissions, and unsuccessful authentication. Confirmed medium or higher severity findings from dynamic testing must also be corrected before release.

## Release checklist

Before publishing a production release, maintainers must complete and record all of the following:

1. `prove -Icore/system -Icore/config -Icore/cpan-lib -r t`
2. `tools/qisutu-static-analysis`
3. Review of test and analysis output; no confirmed medium or higher severity exploitable finding may remain open.
