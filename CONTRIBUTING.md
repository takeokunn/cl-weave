# Contributing

`cl-weave` is pre-1.0, so contributions should optimize for a small public
surface, reproducible behavior, and AI-readable contracts.

Please read [CODE_OF_CONDUCT.md](CODE_OF_CONDUCT.md) before participating in
issues, pull requests, or reviews.

If you are filing a bug or behavior report, use
[docs/issue-reporting.md](docs/issue-reporting.md) so maintainers get the
reproducer and environment details they need.

If you need the canonical GitHub intake surfaces and their required sections in
one place, review [docs/community-health.md](docs/community-health.md) before
opening the issue or pull request.

## Development Loop

If you use [direnv](https://direnv.net/), running `direnv allow` once loads the
flake's `devShell` (SBCL, Perl, and
[paredit-cli](https://github.com/takeokunn/paredit-cli)) automatically
whenever you `cd` into the repository.

Use the same commands locally that CI uses:

```sh
perl -e 'alarm 360; exec @ARGV' -- sbcl --noinform --non-interactive --load scripts/run-tests.lisp
perl -e 'alarm 600; exec @ARGV' -- nix flake check --print-build-logs
```

When editing `.lisp`/`.asd` sources, prefer `paredit-cli`'s structural
commands (`paredit inspect ...`, `paredit refactor ...`) over hand-editing
balanced delimiters, especially for renames and multi-file refactors. Run
`paredit inspect check --file <path>` after manual edits to confirm the
S-expressions still parse; `nix flake check` runs the same check repo-wide as
the `paredit-lint` check.

For focused CLI checks, prefer the packaged entrypoint:

```sh
perl -e 'alarm 360; exec @ARGV' -- nix run . -- run cl-weave-tests --reporter spec
perl -e 'alarm 120; exec @ARGV' -- nix run . -- metadata cl-weave-tests --reporter json --output cl-weave-metadata.json
```

If ASDF loading fails or times out, treat that as a release blocker. Targeted
source-level checks can explain a defect, but they do not prove packaging,
downstream adoption, or CI readiness.

Run `nix fmt` before committing changes to `flake.nix` so Nix expressions stay
consistently formatted.

## Change Standards

- Keep the core dependency-free unless there is a clear architectural reason.
- Preserve deterministic output for reporters, property tests, ordering, and
  metadata.
- Update tests and documentation together when public CLI behavior, reporter
  schemas, metadata fields, or exported symbols change.
- Keep machine-readable contracts authoritative. Agents should consume
  `cl-weave metadata`, not scrape examples.
- Prefer incremental adoption paths for downstream ASDF projects and Nix CI.

## Pull Requests

Before opening a pull request:

1. Run the SBCL test suite.
2. Run `nix flake check --print-build-logs` when Nix is available.
3. Include the narrowest command that demonstrates the change.
4. Document any intentionally unsupported implementation or platform.
5. Use [docs/pull-request-template.md](docs/pull-request-template.md) and
   [.github/pull_request_template.md](.github/pull_request_template.md) to keep
   the summary, compatibility impact, and validation notes consistent.

For release-oriented changes, review [docs/release-process.md](docs/release-process.md)
so the changelog, metadata, and support docs stay aligned.

If you are deciding where a request belongs or how much context a report needs,
review [docs/support-policy.md](docs/support-policy.md) before opening the
issue or PR.

If the change is compatibility-sensitive or breaks a public surface, review
[docs/versioning-policy.md](docs/versioning-policy.md) before cutting the patch.

If you are deciding whether a request belongs in the project at all, review
[docs/project-scope.md](docs/project-scope.md) and [docs/triage-policy.md](docs/triage-policy.md)
before opening the issue or PR.

If you need to understand maintainer decision authority, review ownership, or
release responsibility before proposing a process change, review
[docs/governance.md](docs/governance.md).
