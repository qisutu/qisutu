# Contributing to Qisutu

Thank you for your interest in contributing to Qisutu. Contributions that improve the ticket system, its documentation, translations, tests, installation, or accessibility are welcome.

## Before you start

- Search the existing GitHub issues and pull requests to avoid duplicate work.
- For a bug, open a GitHub issue and describe the affected Qisutu version, the expected behavior, the actual behavior, and reproducible steps.
- For a larger change or a change to public interfaces, open an issue first so the approach can be discussed before implementation.
- Do not publish suspected security vulnerabilities in a public issue. Report them privately by email to support@qisutu.de.

## Submitting a contribution

1. Fork the repository.
2. Create a focused branch from the current `main` branch.
3. Make one coherent change per pull request.
4. Preserve UTF-8 encoding and the existing directory and naming conventions.
5. Add or update tests and documentation when the change affects behavior.
6. Run the tests relevant to the changed code and run `tools/qisutu-static-analysis` for Perl changes. Describe the results in the pull request.
7. Open a pull request against `main` and explain the problem, the solution, and any compatibility or migration effects.

Pull requests must not contain credentials, personal data, generated installation secrets, customer information, or unrelated formatting changes. They should remain compatible with the supported installation and update process unless the proposed incompatibility has been discussed and accepted in advance.

The complete test command, static-analysis release gate, warning policy, and policy requiring tests for major new functionality are documented in `DEVELOPMENT.md`.

## Code and documentation expectations

- Follow the style and structure of the surrounding Perl, JavaScript, CSS, SQL, and Template Toolkit code.
- Keep changes readable and limited to what is required for the contribution.
- Do not remove existing copyright or license notices.
- Document new configuration settings, user-visible behavior, database changes, REST interfaces, and module API changes.
- New user-facing text must be translatable and must not be hard-coded where Qisutu uses language resources.
- Third-party components must have licenses compatible with Qisutu and must be recorded in the appropriate notices.

## Review

Maintainers review contributions for correctness, security, compatibility, licensing, documentation, and test coverage. Review may result in requested changes. Submission does not guarantee acceptance.

## License

By submitting a contribution, you agree that it may be distributed under the same license as Qisutu, the GNU Affero General Public License, version 3 or any later version (`AGPL-3.0-or-later`). You confirm that you have the right to submit the contribution.
