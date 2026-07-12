# Documentation Index

This directory holds the policy, contract, and reference documents that back
the [README](../README.md). Start there for the DSL, matcher, and CLI
reference; use this page to find everything else.

## Using cl-weave

- [Adoption Guide](adoption.md) — the shortest path from an existing Common
  Lisp test setup to `cl-weave`.
- [Runtime Support](runtime-support.md) — supported implementations,
  platforms, and the ASDF load gate that defines a release-ready runtime.
- [AI Contract](ai-contract.md) — the machine-readable CLI metadata, reporter
  schemas, and lifecycle contracts that agents and CI tooling can rely on
  instead of scraping human-readable output.
- [doctor-report](doctor-report.md) — what `cl-weave doctor` checks and how to
  read its machine-readable self-diagnostic output.

## Contributing

- [CONTRIBUTING.md](../CONTRIBUTING.md) — the development loop, change
  standards, and pull request expectations.
- [Issue Reporting Guide](issue-reporting.md) — what to include when filing a
  bug or behavior report.
- [Pull Request Template](pull-request-template.md) — the canonical PR
  summary, compatibility impact, and validation notes format.
- [Community Health](community-health.md) — the GitHub intake surfaces under
  `.github/` and how they map to these policy documents.
- [CODE_OF_CONDUCT.md](../CODE_OF_CONDUCT.md) — participation expectations for
  issues, pull requests, and reviews.
- [SECURITY.md](../SECURITY.md) — private vulnerability reporting.

## Project Governance

- [Project Scope](project-scope.md) — what belongs in the framework.
- [Triage Policy](triage-policy.md) — how issues and pull requests are
  prioritized.
- [Support Policy](support-policy.md) — issue, PR, and private security
  reporting boundaries.
- [Versioning Policy](versioning-policy.md) — how pre-1.0 version numbers
  communicate change scope and migration expectations.
- [Maintenance Policy](maintenance-policy.md) — how the project evolves and
  publishes upgrade notes.
- [Governance](governance.md) — the maintainer operating model and decision
  authority.
- [Distribution Policy](distribution-policy.md) — canonical distribution
  channels and how maintainers verify them.
- [Release Process](release-process.md) — the release flow while the project
  remains pre-1.0.
- [CITATION.cff](../CITATION.cff) — how to cite this project.

## Nix Workflow

The [flake.nix](../flake.nix) at the repository root packages `cl-weave` as a
Nix flake:

- `nix develop` — a devShell with SBCL, Perl, and
  [`paredit-cli`](https://github.com/takeokunn/paredit-cli) for structural
  S-expression edits.
- `nix run . -- <command>` — the packaged CLI (`run`, `list`, `watch`,
  `doctor`, `metadata`, `version`, `help`).
- `nix flake check` — every CI entrypoint (test suite, reporters, coverage
  gate, AI metadata, CLI smoke tests, `paredit-lint` structural parse check)
  as reproducible derivations.
- `nix fmt` — formats `flake.nix` with `nixfmt`.

Running `direnv allow` loads the devShell automatically; see
[CONTRIBUTING.md](../CONTRIBUTING.md) for the full development loop.
