# Changelog

This project follows a pre-1.0 changelog. Entries should describe user-visible
framework, CLI, reporter, metadata, and Nix workflow changes.

## Unreleased

### Release Classification

- breaking cleanup

### Public Surface Notes

- Legacy `assert-*` and `is-*` compatibility aliases were removed in favor of
  the canonical `expect`, `expect-not`, `signals`, and `finishes` surface.
- Existing CLI output, reporter shapes, and machine-readable metadata remain
  the expected public surface for these changes.

### Migration Notes

- Replace legacy assertion aliases with the canonical expectation macros.

### User-visible Changes

- Added a `formatter` flake output (`nixfmt`) so `nix fmt` formats `flake.nix`.
- Added an `overlays.default` flake output so downstream flakes can consume
  `cl-weave` as `pkgs.cl-weave` without re-deriving the package.
- Added package `meta` (description, homepage, license, platforms) to the
  flake's `cl-weave` derivation.
- Added a `.envrc` so `direnv allow` loads the flake's devShell automatically.
- Added `docs/README.md` as a documentation index linking the README, AI
  contract, Nix workflow, and every governance and policy document.
- Corrected `docs/runtime-support.md`, which described an ASDF-loading
  timeout as an open blocker after it had already been fixed.

## 0.1.0 - 2026-07-11

First tagged release. `cl-weave` is a Vitest-inspired Common Lisp testing
framework with a dependency-free core, structured machine-readable reporters,
and AI-agent-oriented runtime metadata.

### Release Classification

- initial release

### Public Surface Notes

- The public surface for this release is the documented DSL, matcher set,
  runner API, CLI commands, reporter shapes, and machine-readable metadata
  described in `README.md` and `docs/ai-contract.md`.

### Migration Notes

- New adopters should follow `docs/adoption.md`; there are no migration steps
  because this is the first tagged release.

### User-visible Changes

- Added the Vitest-style test DSL: `describe` / `it` / `test` suites and
  cases, `expect` matcher assertions, smart S-expression assertions, table
  tests, focus, skip, todo, retry, timeout, bail, sharding, sequence
  ordering, filtering, concurrent execution modes, and expected failures.
- Added property-based testing with deterministic shrinking, form-level
  mutation testing with CI score gates, subprocess isolation for FFI and
  crash boundaries, inline and external snapshot matchers, mock functions
  with call-history matchers, and CPS continuation helpers.
- Added spec, S-expression, JSON, JSONL/NDJSON, TAP, GitHub Actions, and
  JUnit XML reporters with stable, versioned artifact schemas.
- Added the `cl-weave` CLI with `run`, `list`, `watch`, `doctor`,
  `metadata`, `version`, and `help` commands, Vitest-shaped option aliases,
  and environment-variable equivalents for CI automation.
- Added AI-friendly runtime metadata: typed CLI options with finite choices,
  artifact schemas with field maps, a capability matrix, package exports,
  matchers, mutation operators, MOP architecture assertions, distribution
  channels, and lifecycle contracts.
- Added ASDF system definitions, an ASDF-aware system runner, and watch mode
  with dependency-aware rerun narrowing.
- Added Nix flake packaging with reproducible CI entrypoints for Linux and
  macOS.
- Added OSS operations documents for contribution flow, security reporting, and
  release notes.
- Added code of conduct and maintenance policy documentation to clarify
  participation norms and support boundaries.
- Added issue reporting and release process guides so contributors and
  maintainers have clearer entry points for bugs and releases.
- Added a copyable issue report template so bug reports include the command,
  environment, expected behavior, and reproducer in a consistent format.
- Added a pull request template so reviews include summary, surface impact, and
  validation notes in a consistent format.
- Added a README CI badge and support section to make the current maintenance
  and reporting entry points easier to find.
- Added a versioning policy so public-surface, migration, and pre-1.0 breaking
  change expectations are explicit.
- Added project scope and triage policy documents to clarify what belongs in the
  framework and how reports should be prioritized.
- Added support policy documentation to clarify issue, PR, and private security
  reporting boundaries.
- Added machine-readable policy document metadata so downstream tooling can
  discover the canonical contribution, security, and maintenance guidance.
- Added ASDF homepage and bug tracker metadata so downstream tooling can find
  the canonical project source and support channel.
- Added license metadata to the machine-readable contract so downstream tooling
  can report governance details without guessing from source files.
- Added a `.gitignore` so compiled FASL files and local CI artifacts stay out
  of version control.
