# Contributing to cl-weave

Thank you for improving `cl-weave`. This project values small, reviewable
changes with a clear user-facing reason and reproducible validation.

## Before You Start

- Read the [project scope](docs/src/project-scope.md) and
  [support policy](docs/src/support-policy.md).
- Discuss substantial API, reporter, metadata, or runtime changes in an issue
  before investing in an implementation.
- Do not report security vulnerabilities in public issues. Follow
  [SECURITY.md](SECURITY.md) instead.

## Development Environment

Nix provides the supported development environment and toolchain:

```sh
nix develop
nix flake check --print-build-logs
```

For a focused test run, use the packaged CLI:

```sh
nix run . -- run cl-weave/tests --filter 'path substring'
```

The supported release target is SBCL on Linux. See
[Runtime Support](docs/src/runtime-support.md) for capability and portability
boundaries.

## Pull Requests

- Keep a pull request focused on one problem.
- Add or update tests for behavior changes.
- Update public documentation and machine-readable metadata with public API,
  CLI, reporter, or policy changes.
- State the commands you ran and any validation that could not run.
- Follow the repository pull request template and
  [review expectations](docs/src/governance.md#review-and-merge-expectations).

The complete contributor workflow, including issue triage and release-facing
requirements, is documented in [the project documentation](docs/src/README.md).
