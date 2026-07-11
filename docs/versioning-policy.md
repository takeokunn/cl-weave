# Versioning Policy

`cl-weave` is pre-1.0, so version numbers communicate change scope without
promising semantic-version compatibility.

## Current Model

- `0.x` releases may include breaking changes whenever that is the smallest
  correct fix for the public surface.
- A breaking change should still be explicit in the changelog, docs, and tests.
- Non-breaking changes should preserve the documented CLI output, reporter
  shape, and machine-readable metadata.

## Public Surface Discipline

- Prefer one coherent public API over layered aliases and transition shims.
- Remove obsolete surfaces instead of carrying compatibility wrappers forward.
- When a public contract changes, update docs, metadata, and tests in the same
  change.

## Migration Policy

- Document the replacement surface at the point of removal.
- Keep regression tests only for the surviving public API.
- Prefer short, explicit migration notes over long-lived deprecated code paths.

## Release Notes

Each release should make it clear whether it is:

1. additive only,
2. behavior-preserving, or
3. intentionally breaking for a documented reason.

That label should match the actual change set and the regression tests that
support it.

Before cutting a release or documenting a public break, review
[release-process.md](release-process.md) and
[maintenance-policy.md](maintenance-policy.md) so the changelog, validation
story, and support expectations stay aligned.
