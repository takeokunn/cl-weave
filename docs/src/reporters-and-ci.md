# Reporters And CI

## Reporters

```lisp
(cl-weave:run-all :reporter :spec)
(cl-weave:run-all :reporter :sexp)
(cl-weave:run-all :reporter :json)
(cl-weave:run-all :reporter :jsonl)
(cl-weave:run-all :reporter :tap)
(cl-weave:run-all :reporter :github)
(cl-weave:run-all :reporter :junit)
(cl-weave:run-all :reporter :json :name-filter "properties")
(cl-weave:run-all :coverage t
                  :coverage-output "cl-weave.coverage"
                  :coverage-report-directory "cl-weave-coverage-report/")
```

`run-all` returns true when the suite passed and false otherwise.

Coverage support is optional and SBCL-specific. `run-all :coverage t` requires
`sb-cover`, resets counters before execution by default, emits a populated HTML
report with `sb-cover:report` when `:coverage-report-directory` is provided,
and saves readable coverage state with `sb-cover:save-coverage-in-file` when
`:coverage-output` is provided. Empty reports are rejected so CI cannot publish
meaningless coverage artifacts. Pass `:coverage-reset nil` to merge the run
into existing counters.

Use `--coverage` to enable `sb-cover:store-coverage-data` before loading the
requested system. `--coverage-output` saves the coverage state for a subsequent
reporting step, and `--coverage-report-directory` emits the HTML report.

```sh
perl -e 'alarm 360; exec @ARGV' -- nix run . -- run cl-weave/tests --coverage --coverage-output cl-weave.coverage
```

The `:sexp` reporter is the stable Lisp-native AI interface. The `:json`
reporter is the stable external-tool interface. The `:jsonl` reporter emits one
JSON object per line for streaming CI logs and agent ingestion. These structured
reporters include failed and errored path summaries for focused reruns. See
[AI Contract](ai-contract.md). The metadata root also advertises these canonical
non-policy paths through `referenceDocuments` and `citation`, plus support
and lifecycle contracts through `supportChannels`, `securityContacts`,
`lifecycle`, `runtimeSupport`, and `releaseProcess`.

The packaged CLI accepts `--reporter` (`spec`, `sexp`, `json`, `jsonl`, `tap`,
`github`, or `junit`), `--filter`, `--shard`, `--sequence`, `--seed`, `--bail`,
`--retry`, `--test-timeout-ms`, `--max-workers`, `--coverage`, snapshot flags,
and `--output`. Use the `list` command for discovery without execution. Use
`--fail-with-no-tests` when a zero-test filtered CI run must fail. `tap` is for
line-oriented logs, `github` emits GitHub Actions annotations, and `junit`
produces XML for CI ingestion. List mode supports `spec`, `sexp`, `json`, and
`jsonl`.

The CLI uses kebab-case flags consistently, including `--test-name-pattern`,
`--watch-interval`, `--coverage-output`, `--output-file`,
`--test-timeout-ms`, `--pass-with-no-tests`, `--fail-with-no-tests`,
`--snapshot-dir`, `--snapshot-file`, `--max-workers`, and
`--update-snapshots`.

## CI

GitHub Actions runs the same Nix entrypoints used locally:

```sh
perl -e 'alarm 600; exec @ARGV' -- nix flake check --print-build-logs
perl -e 'alarm 360; exec @ARGV' -- nix run . -- run cl-weave/tests --coverage --coverage-output cl-weave.coverage --coverage-report-directory cl-weave-coverage-report/
perl -e 'alarm 360; exec @ARGV' -- nix run . -- run cl-weave/tests --reporter json --output cl-weave-results.json
perl -e 'alarm 360; exec @ARGV' -- nix run . -- run cl-weave/tests --reporter jsonl --output cl-weave-events.jsonl
perl -e 'alarm 360; exec @ARGV' -- nix run . -- run cl-weave/tests --reporter json --filter 'filtering > runs only tests matching a path substring' --output cl-weave-cli-results.json
perl -e 'alarm 120; exec @ARGV' -- nix run . -- metadata cl-weave/tests --reporter json --output cl-weave-metadata.json
perl -e 'alarm 120; exec @ARGV' -- nix run . -- list cl-weave/tests --reporter json --filter 'filtering > runs only tests matching a path substring' --output cl-weave-plan.json
perl -e 'alarm 120; exec @ARGV' -- nix run . -- watch cl-weave/tests --once --reporter json --filter 'filtering > runs only tests matching a path substring' --output cl-weave-watch-once.json
perl -e 'alarm 120; exec @ARGV' -- nix run . -- run cl-weave/tests --reporter tap --filter 'filtering > runs only tests matching a path substring' --output cl-weave-tap.txt
perl -e 'alarm 60; exec @ARGV' -- nix run . -- run cl-weave/tests --filter 'filtering > runs only tests matching a path substring'
perl -e 'alarm 360; exec @ARGV' -- nix run . -- run cl-weave/tests --reporter junit --output cl-weave-junit.xml
```

To enable binary cache reuse across developer machines and GitHub Actions,
create a Cachix cache and add these repository settings:

- variable `CACHIX_CACHE`: public cache name to pull from in CI
- secret `CACHIX_AUTH_TOKEN`: optional write token to push newly built paths

When `CACHIX_CACHE` is set, the workflow enables `cachix/cachix-action`. If
`CACHIX_AUTH_TOKEN` is absent, CI stays in pull-only mode so forked pull
requests and public builds still work. If the token is present, the workflow
pushes fresh build outputs back to the cache. The workflow also pulls from
`nix-community` via `extraPullNames` to reduce cold-start latency.

The workflow runs on Linux and macOS, then uploads `cl-weave-results.json`,
`cl-weave-events.jsonl`, `cl-weave.coverage`, `cl-weave-coverage-report/`,
`cl-weave-cli-results.json`, `cl-weave-metadata.json`, `cl-weave-plan.json`,
`cl-weave-watch-once.json`, `cl-weave-tap.txt`, and `cl-weave-junit.xml` as
`cl-weave-test-reports-${system}` artifacts. JSON result
schema v6 is intended for AI agents and external automation: the root object
identifies itself with `kind: "test-results"`, and every event includes both a
machine `path` and a stable Vitest-style `pathString`, while assertion payloads
stay structurally typed for agent consumption. Ordered cleanup and hook failures
are retained as `secondaryConditions`. JSONL event schema v3 is intended
for streaming automation, coverage is intended for SBCL-side inspection,
metadata is intended for agent discovery, one-shot watch output is intended for
automation that needs watch resolution without entering a polling loop, TAP is
intended for portable smoke output, and JUnit is intended for CI test result
ingestion.
