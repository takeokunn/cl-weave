# Release Process

This document describes the intended release flow for `cl-weave` while the
project remains pre-1.0.

## Release Goals

- Keep the public CLI and reporter contracts stable unless the changelog calls
  out a deliberate break.
- Keep machine-readable metadata and human-facing documentation in sync.
- Keep downstream ASDF consumers able to adopt new versions with a small
  upgrade step.

For public-surface discipline and migration expectations, see
[versioning-policy.md](versioning-policy.md).

## Suggested Release Checklist

1. Run the full test suite.
2. Run `nix flake check --print-build-logs` when Nix is available.
3. Summarize user-visible changes in the release notes.
4. Check that `README.md` and `docs/maintenance-policy.md` still match the
   current workflow.
5. Review `docs/pull-request-template.md` and
   `.github/pull_request_template.md` so release-bound changes still capture
   public-surface notes, validation commands, and follow-up risk in a
   consistent format.
6. Verify that `cl-weave metadata` still advertises the expected package links,
   reporter list, and schema versions.
7. Verify that `docs/distribution-policy.md` still matches the documented
   source and Nix install paths.
8. Confirm the release notes mention any intentional public-surface breaks or
   migration steps.

## Maintenance Boundaries

- Security fixes and correctness fixes target the current mainline behavior
  first.
- If release branches are introduced later, backports should follow the current
  maintenance policy.
- Keep `distributionChannels`, `README.md`, and
  `docs/distribution-policy.md` synchronized when install paths change.
- Update tests and `docs/ai-contract.md` when a machine-readable contract
  changes.
