# cl-weave

[![CI](https://github.com/takeokunn/cl-weave/actions/workflows/ci.yml/badge.svg?branch=main)](https://github.com/takeokunn/cl-weave/actions/workflows/ci.yml)

`cl-weave` is a modern Common Lisp testing framework inspired by Vitest and
designed around Lisp's strengths: macros, conditions, dynamic bindings, and
reproducible Nix workflows.

The project is intentionally dependency-free at the core. It should be easy to
run in CI, embed in ASDF projects, and extend from the REPL.

See [docs/README.md](docs/README.md) for the full documentation index:
adoption, the AI contract, Nix workflow, and every governance and policy
document in one place.

## Support

Use [docs/support-policy.md](docs/support-policy.md) for the canonical support
boundaries.

Use [docs/issue-reporting.md](docs/issue-reporting.md) for reproducible bugs
and behavior questions.

Use [private GitHub security advisories](https://github.com/takeokunn/cl-weave/security/advisories/new)
for vulnerability reporting. Do not put exploit details in a public issue.

## Status

Pre-1.0. The capability list below is the intended public surface, and it is
validated by the CI entrypoints in this README on Linux and macOS. Pre-1.0
releases may still introduce deliberate breaking changes; the expectations are
documented in [docs/versioning-policy.md](docs/versioning-policy.md):

- `describe` / `it` hierarchical test DSL
- `expect` matcher assertions with readable failure reports
- smart S-expression assertions that capture operand values
- `it-each` and `describe-each` compile-time table tests
- canonical hyphenated variants such as `it-only`, `describe-concurrent`,
  `expect-not`, `expect-resolves`, and `expect-assertions`
- `it-property` deterministic property tests with shrinking
- form-level mutation testing with macro-defined operators
- `it-isolated` subprocess tests for FFI and crash boundaries
- `before-all` / `after-all`, `before-each` / `after-each`, and CPS `around-each` dynamic fixtures
- `describe-skip` / `it-skip` skipped suites and cases
- `describe-skip-if` / `it-skip-if` and `run-if` conditional registration
- `describe-only` / `it-only` focused runs
- `describe-todo` / `it-todo` todo suites and cases
- Vitest-style test name filtering for focused local and CI runs
- Vitest-style test discovery list mode for AI agents and CI tooling
- AI-friendly CLI metadata for typed/enumerated options, artifact schemas with field maps, capability matrix, package exports, policy documents, matchers, mutations, and MOP architecture assertions
- source file metadata in structured reporters and test plans
- Vitest-style deterministic sequence ordering for flaky-test reproduction
- Vitest-style `:bail` execution control for fast-fail CI runs
- Vitest-style per-test `:retry` and `:timeout-ms` controls
- Vitest-style `it-concurrent` / `describe-concurrent` parallel execution modes
- Vitest-style `it-fails` expected-failure cases
- FiveAM-style migration guidance for the native suite DSL
- Vitest-style length, instance, inline snapshot, and external snapshot matchers
- CI-friendly thunk runtime and allocation assertions
- SBCL `sb-cover` reset/save integration for CI coverage artifacts
- Vitest-style mock functions with call history assertions
- ASDF system definitions
- ASDF-aware system runner and watch mode
- spec, S-expression, JSON, JSONL, TAP, GitHub Actions, and JUnit XML reporters
- non-zero process exit on failure for CI
- safe dynamic global function mocking with `with-mocked-functions`

## Quick Start

```lisp
(defpackage #:example/tests
  (:use #:cl)
  (:shadowing-import-from #:cl-weave #:describe)
  (:import-from #:cl-weave #:expect #:it))

(in-package #:example/tests)

(describe "math"
  (it "adds numbers"
    (expect (+ 1 1) :to-be 2))

  (it "checks predicates as data"
    (expect (= (+ 1 1) 2)))

  (it "compares structures"
    (expect (list :ok 42) :to-equal (list :ok 42))))
```

Run the self-test suite:

```sh
perl -e 'alarm 360; exec @ARGV' -- sbcl --noinform --non-interactive --load scripts/run-tests.lisp
```

With Nix:

```sh
nix develop
nix run . -- --help
nix profile install .
perl -e 'alarm 600; exec @ARGV' -- nix flake check
perl -e 'alarm 360; exec @ARGV' -- nix run . -- run cl-weave/tests --reporter spec
```

Without cloning the repository first:

```sh
nix run github:takeokunn/cl-weave -- --help
nix profile install github:takeokunn/cl-weave
```

The packaged CLI is intended for local use, CI, and AI
agents:

```sh
perl -e 'alarm 360; exec @ARGV' -- nix run . -- run cl-weave/tests --reporter json --output cl-weave-results.json --retry 2 --test-timeout-ms 10000
perl -e 'alarm 360; exec @ARGV' -- nix run . -- run cl-weave/tests --reporter jsonl --output cl-weave-events.jsonl
perl -e 'alarm 360; exec @ARGV' -- nix run . -- run my-project-tests --update-snapshots --snapshot-dir tests/__snapshots__/ --snapshot-file snapshots.sexp
perl -e 'alarm 120; exec @ARGV' -- nix run . -- list cl-weave/tests --reporter json --filter 'math > adds'
perl -e 'alarm 120; exec @ARGV' -- nix run . -- metadata cl-weave/tests --output cl-weave-metadata.json
perl -e 'alarm 120; exec @ARGV' -- nix run . -- doctor --reporter json --output cl-weave-doctor.json
perl -e 'alarm 360; exec @ARGV' -- nix run . -- run cl-weave/tests --bail=1 --sequence random --seed 12345
perl -e 'alarm 360; exec @ARGV' -- nix run . -- watch cl-weave/tests --filter parser
perl -e 'alarm 120; exec @ARGV' -- nix run . -- watch cl-weave/tests --once --reporter json --filter 'math > adds' --output cl-weave-watch-once.json
```

Lisp-side agents can read the full structured framework metadata with
`(cl-weave:framework-metadata)` and the artifact-only contract with
`(cl-weave:reporter-artifact-schemas)` without shelling out to the CLI.

## Adoption

See [docs/adoption.md](docs/adoption.md)
for the integration recipe. It covers ASDF wiring, Nix entrypoints, CI
commands, migration guidance for FiveAM-style suites, and top-level runner
helpers such as `run`, `explain!`, and `results-status`. Migrate suite by
suite rather than rewriting everything at once, and keep existing CI
entrypoints green until the new `cl-weave` entrypoint matches them.

### AI Discovery

Agents and generators should start from runtime metadata instead of scraping
source files or examples:

```sh
perl -e 'alarm 120; exec @ARGV' -- nix run . -- metadata cl-weave/tests --reporter json --output cl-weave-metadata.json
```

The metadata payload advertises CLI commands, typed options, finite choices,
command-specific choices, environment variables, CI quality gates, public
package exports, matchers, mutation operators,
`mop-architecture-assertions`, `capabilityMatrix`, `artifactSchemas`, and
`distributionChannels`.
For runtime self-diagnostics, `doctor --reporter json` emits a structured
`doctor-report` artifact without requiring an ASDF system argument.
The report separates bundled `cl-weave` visibility, optional requested-system
resolution, workspace `.asd` discovery, and output-target configuration so CI
and agents can distinguish environment drift from an actually missing target
system.
`artifactSchemas` is the contract for structured artifacts
such as JSON run results, JSONL run events, JSON test plans, JSONL plan entries,
doctor reports, and mutation reports. Each entry declares the artifact kind, producing
commands, supported reporters, artifact-local `schemaVersion`, streaming mode,
and field map, so agents can plan parsers and CI integrations without
hard-coding reporter internals. Result artifacts intentionally advertise both
`run` and `watch`, because `watch --once` emits the same machine-readable shape
as a normal run. `qualityGates` exposes validation commands as argv vectors
with explicit timeouts and expected artifacts, so agents can reproduce CI
without scraping prose.
`distributionChannels` is the canonical install and run table for source
checkout execution, local Nix packaging, and remote Nix packaging. Agents
should prefer its `installCommand` and `runCommand` vectors over inferring
entrypoints from surrounding prose examples. The maintainer-facing verification
and scope boundary for those channels lives in
[docs/distribution-policy.md](docs/distribution-policy.md).
`capabilityMatrix` is the readiness table: each entry links a high-level
feature to implemented status, representative public APIs, validation gates,
and canonical documentation. The complete artifact and capability lists are
intentionally discovered from the command output; documentation examples are
illustrative.

## Supported Runtime

`cl-weave` targets SBCL first. Linux and macOS are intended CI targets, and
SBCL-specific features such as subprocess isolation and coverage handling are
documented in [docs/runtime-support.md](docs/runtime-support.md). A platform is
release-ready only when the ASDF load gate and the relevant CI entrypoints pass
there.

### Capability Matrix

Runtime metadata exposes `capabilityMatrix` so humans and agents can evaluate
framework readiness without guessing from examples. Every advertised
capability has a corresponding readiness entry; highlighted areas include
`vitest-dsl`, `expect-matchers`,
`fixtures-and-restarts`, `mocks-and-spies`, `property-and-mutation`,
`structured-reporting`, `watch-and-parallelism`, `isolation-and-cps`, and
`ai-discovery-metadata`.

## CI

GitHub Actions runs the same Nix entrypoints used locally:

```sh
perl -e 'alarm 600; exec @ARGV' -- nix flake check --print-build-logs
nix develop --command perl -e 'alarm 360; exec @ARGV' -- env CL_WEAVE_REPORTER=json CL_WEAVE_OUTPUT_FILE=cl-weave-results.json sbcl --dynamic-space-size 4096 --noinform --non-interactive --load scripts/run-tests.lisp
nix develop --command perl -e 'alarm 360; exec @ARGV' -- env CL_WEAVE_REPORTER=jsonl CL_WEAVE_OUTPUT_FILE=cl-weave-events.jsonl sbcl --dynamic-space-size 4096 --noinform --non-interactive --load scripts/run-tests.lisp
nix develop --command sh scripts/run-coverage-gate.sh
nix develop --command perl scripts/test-coverage-gate.pl
perl -e 'alarm 360; exec @ARGV' -- nix run . -- run cl-weave/tests --reporter json --filter 'filtering > runs only tests matching a path substring' --output cl-weave-cli-results.json
perl -e 'alarm 120; exec @ARGV' -- nix run . -- metadata cl-weave/tests --reporter json --output cl-weave-metadata.json
perl -e 'alarm 120; exec @ARGV' -- nix run . -- list cl-weave/tests --reporter json --filter 'filtering > runs only tests matching a path substring' --output cl-weave-plan.json
perl -e 'alarm 120; exec @ARGV' -- nix run . -- watch cl-weave/tests --once --reporter json --filter 'filtering > runs only tests matching a path substring' --output cl-weave-watch-once.json
perl -e 'alarm 120; exec @ARGV' -- nix run . -- run cl-weave/tests --reporter tap --filter 'filtering > runs only tests matching a path substring' --output cl-weave-tap.txt
nix develop --command perl -e 'alarm 60; exec @ARGV' -- env CL_WEAVE_TEST_FILTER='filtering > runs only tests matching a path substring' sbcl --dynamic-space-size 4096 --noinform --non-interactive --load scripts/run-tests.lisp
nix develop --command perl -e 'alarm 360; exec @ARGV' -- env CL_WEAVE_REPORTER=junit CL_WEAVE_OUTPUT_FILE=cl-weave-junit.xml sbcl --dynamic-space-size 4096 --noinform --non-interactive --load scripts/run-tests.lisp
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

## API

### Suites And Cases

```lisp
(describe "suite name"
  (it "case name"
    (expect ...)))
```

`describe` forms can be nested. Tests are registered when the file is loaded.
Because Common Lisp already exports `CL:DESCRIBE`, test packages should import
`cl-weave:describe` with `:shadowing-import-from`.

### Assertions

```lisp
(expect actual :to-be expected)
(expect (= actual expected))
(expect (< low value high))
(expect actual :to-equal expected)
(expect value :to-be-greater-than 10)
(expect values :to-have-length 3)
(expect (lambda () (parse-integer "42")) :to-run-under-ms 5)
(expect (lambda () (loop repeat 10 collect :x)) :to-allocate-under 4096)
(expect form :to-match-inline-snapshot "(:ok 42)")
(let ((*snapshot-directory* #P"tests/__snapshots__/")
      (*snapshot-file-name* "snapshots.sexp"))
  (with-snapshot-updates
    (expect form :to-match-snapshot "suite/case"))
  (expect form :to-match-snapshot "suite/case")
  (with-snapshot-updates
    (expect '((:pc 0 :acc 0) (:pc 1 :acc 1))
            :to-match-snapshot-sequence
            "vm/run"))
  (expect '((:pc 0 :acc 0) (:pc 1 :acc 1))
          :to-match-snapshot-sequence
          "vm/run"))
(expect value :not :to-be nil)
(expect-not value :to-be nil)
(expect-resolves (lambda () (fetch-account)) :to-satisfy #'account-ready-p)
(expect-rejects (lambda () (error "missing user")) :to-be-type-of 'simple-error)
(expect-poll (lambda () (current-state job)) (:timeout-ms 200 :interval-ms 10) :to-be :ready)
(expect-assertions 2)
(expect-has-assertions)
```

With matcher syntax, `expect` captures the original S-expression and reports
matcher, actual, expected, negation, and pass metadata through conditions and
reporters. `expect-not` is Vitest-style sugar for matcher assertions that
should fail when the underlying matcher passes; it uses the same structured
failure payload as `(expect value :not matcher ...)`.

`expect-resolves` and `expect-rejects` express asynchronous-style assertions
with Lisp thunks. `expect-resolves` runs a zero-argument function and applies the
matcher to its primary returned value. If the thunk signals a condition, the
assertion fails with `:matcher :resolves` and `:actual` containing `:state`,
`:condition-type`, and `:message`. `expect-rejects` requires the thunk to
signal a condition and then applies the matcher to that condition object; a
normally returned value fails with `:matcher :rejects`.
`expect-poll` repeatedly evaluates a zero-argument thunk until the matcher
passes or the timeout expires. Polling failures report `:matcher :poll` with
structured timeout metadata such as `:attempts`, `:timeout-ms`,
`:interval-ms`, `:last-value`, and optional `:last-condition`.
`expect-assertions` and `expect-has-assertions` are checked at the end of each
test attempt and reset for retries and concurrent tests. Declaration forms do
not count as assertions; executed `expect`, `expect-not`, smart assertions,
and the thunk expectation macros `expect-resolves` and `expect-rejects` count
once.

With no matcher, `expect` treats the form as a smart assertion. Predicate forms
using `=`, `/=`, `<`, `<=`, `>`, `>=`, `eql`, `equal`, `equalp`, `string=`, or
`string-equal` are macro-expanded into single-evaluation operand capture:

```lisp
(expect (= (parse-integer "42") 41))
```

The failure report includes the original predicate and a list of operand forms
with their evaluated values, which is intended to be both REPL-friendly and
AI-friendly. Any other bare form is checked as truthy.

`with-snapshot-updates` enables deterministic external snapshot creation and
updates inside a dynamic scope. For command-line usage,
`CL_WEAVE_UPDATE_SNAPSHOTS=1`, `CL_WEAVE_SNAPSHOT_DIR`, and
`CL_WEAVE_SNAPSHOT_FILE` provide the same dynamic settings for CI and agents.
External snapshot failures report `:snapshot-key`, `:snapshot-file`, `:value`,
`:reason`, and first-difference data through the normal structured assertion
payload, so agents do not need to parse human-readable failure strings.
`:to-match-snapshot-sequence` stores a list or non-string vector of replay
states as deterministic `prefix[n]` snapshot keys, for example `vm/run[0]` and
`vm/run[1]`. Snapshot update mode replaces all entries for that prefix, which
prunes stale states. Verification fails on missing, mismatched, or unexpected
extra stored states and adds `:snapshot-prefix`, `:snapshot-index`, and
`:snapshot-count` to the structured payload.
`snapshot-entries` returns the current external snapshot alist, and
`snapshot-value` returns the serialized value plus a presence flag for one
explicit key. These APIs are intended for replay tools and CI agents that need
to inspect snapshot artifacts without depending on private file readers.

Built-in matchers:

- `:to-be`
- `:to-equal`
- `:to-equalp`
- `:to-be-one-of`
- `:to-be-truthy`
- `:to-be-falsy`
- `:to-be-null`
- `:to-be-defined`
- `:to-be-nan`
- `:to-satisfy`
- `:to-be-type-of`
- `:to-be-instance-of`
- `:to-contain`
- `:to-match`
- `:to-contain-equal`
- `:to-match-object`
- `:to-have-length`
- `:to-have-property`
- `:to-be-close-to`
- `:to-be-greater-than`
- `:to-be-greater-than-or-equal`
- `:to-be-less-than`
- `:to-be-less-than-or-equal`
- `:to-throw`
- `:to-run-under-ms`
- `:to-allocate-under`
- `:to-have-slot`
- `:to-have-method-specialized-on`
- `:to-expand-to`
- `:to-match-inline-snapshot`
- `:to-match-snapshot`
- `:to-match-snapshot-sequence`
- `:to-have-been-called`
- `:to-have-been-called-times`
- `:to-have-been-called-with`
- `:to-have-been-last-called-with`
- `:to-have-been-nth-called-with`
- `:to-have-returned`
- `:to-have-returned-times`
- `:to-have-returned-with`
- `:to-have-last-returned-with`
- `:to-have-nth-returned-with`
- `:to-have-thrown`

`:to-be-one-of` accepts one candidate collection and passes when the actual
value is `eql` to one of its members. Lists and vectors are treated as candidate
sequences; hash tables use their values:

```lisp
(expect :ready :to-be-one-of '(:pending :ready :done))
(expect 2 :to-be-one-of #(1 2 3))
```

Failures report `:value`, `:candidates`, `:test`, `:candidate-count`, and
`:matched-index`, so CI and AI agents can distinguish "candidate missing" from
wrong matcher usage.

`:to-throw` accepts an optional expected condition class designator, message
substring, or predicate function. Failures report `:threw`, `:condition-type`,
and `:message` in `:actual`, plus the normalized throw matcher in `:expected`:

```lisp
(expect (lambda () (error "missing user")) :to-throw 'simple-error)
(expect (lambda () (error "missing user")) :to-throw "missing")
(expect (lambda () (error "missing user"))
        :to-throw
        (lambda (condition)
          (search "user" (princ-to-string condition))))
```

Custom matchers use `defmatcher` or the data-driven
`extend-expect`. Each matcher receives the evaluated actual value and the
remaining expected operands as a list. Return the pass boolean, then optional
reported actual and expected values for structured reporters:

```lisp
(cl-weave:defmatcher :to-have-status (response expected)
  "Checks that a response plist has the expected HTTP status."
  (let ((actual-status (getf response :status))
        (wanted-status (first expected)))
    (values (= actual-status wanted-status)
            actual-status
            wanted-status)))

(expect '(:status 201 :body "created") :to-have-status 201)
```

Macro-based bulk registration keeps related domain matchers together:

```lisp
(cl-weave:expect-extend
  (:to-be-cache-hit (response expected)
    "Checks that a response plist came from cache."
    (declare (ignore expected))
    (let ((state (getf response :cache)))
      (values (eq state :hit)
              `(:cache ,state)
              '(:cache :hit)))))
```

AI agents and generators can emit plain matcher data with `extend-expect`:

```lisp
(cl-weave:extend-expect
 (list
  (list :to-have-status
        (lambda (response expected)
          (let ((actual-status (getf response :status))
                (wanted-status (first expected)))
            (values (= actual-status wanted-status)
                    `(:status ,actual-status)
                    `(:status ,wanted-status))))
        :description
        "Checks that a response plist has the expected HTTP status.")))
```

Matcher metadata is first-class data for AI tools, documentation generators,
and editor integrations:

```lisp
(cl-weave:list-matchers)
;; => ((:name :to-be :description nil)
;;     (:name :to-have-status
;;      :description "Checks that a response plist has the expected HTTP status.")
;;     ...)

(cl-weave:matcher-metadata :to-have-status)
;; => (:name :to-have-status
;;     :description "Checks that a response plist has the expected HTTP status.")
```

### Performance And Allocation

Performance assertions accept thunks so the measured form is executed exactly
inside the matcher:

```lisp
(expect (lambda () (parse-integer "42")) :to-run-under-ms 5)
(expect (lambda () (loop repeat 10 collect :x)) :to-allocate-under 4096)
```

Each matcher executes its thunk once. If you assert both runtime and allocation,
the body runs once per matcher. Failure reports include `:elapsed-seconds`,
`:elapsed-ms`, `:bytes-consed`, and the returned multiple values in `:values`.
Allocation measurement uses the implementation's byte-consing counter; it is
currently backed by SBCL and fails clearly on implementations that do not expose
one.

### Property Assertions

`:to-match` mirrors Vitest `toMatch(pattern)` for strings. A string pattern
checks substring containment; a function designator acts as a Lisp-native
predicate and passes when it returns a non-`nil` value:

```lisp
(expect "common-lisp" :to-match "lisp")
(expect "Common Lisp"
        :to-match
        (lambda (text)
          (search "Lisp" text)))
```

Failures report the actual `:value`, requested `:pattern`, matching `:mode`,
and normalized `:reason`, so reporters can distinguish non-string actual
values, invalid patterns, predicate errors, and ordinary misses.

`:to-be-nan` mirrors Vitest `toBeNaN()` for floating-point NaN values. It
accepts no expected operands. Failure payloads include `:value`, `:type`,
`:float`, and `:nan`; expected data is `(:predicate :nan :test :float-nan-p)`.

`:to-contain-equal` mirrors Vitest `toContainEqual(value)` for Lisp data. It
checks sequence elements and hash-table values with `equalp`, so structurally
equal lists, vectors, strings, numbers, characters, and nested data pass without
requiring object identity:

```lisp
(expect '((:id 1 :name "Ada") (:id 2 :name "Grace"))
        :to-contain-equal
        '(:id 2 :name "Grace"))
```

Failures report the searched `:container`, expected `:value`, and comparison
`:test`, allowing reporters and agents to explain whether the failure came from
membership or equality semantics.

`:to-match-object` mirrors Vitest `toMatchObject(subset)` for Lisp records.
Expected property lists, association lists, and hash tables are treated as
partial object shapes; actual values may be property lists, association lists,
hash tables, or slot-bearing instances. Nested expected objects are checked
recursively with `equalp`. Expected vectors match actual sequences
element-by-element with the same length and order:

```lisp
(expect '(:user (:name "Ada" :roles #("dev" "ops"))
          :meta :ignored)
        :to-match-object
        '(:user (:roles #("dev" "ops"))))
```

Failures report the original `:value`, requested `:subset`, and a normalized
`:failure` payload with `:path`, `:reason`, `:actual-value`, and
`:expected-value`. This gives humans and agents a stable explanation of the
first divergent property.

`:to-have-property` is Vitest-style `toHaveProperty(path, value?)` for Lisp
data. The path can be a scalar, list, or vector. It traverses property lists,
association lists, hash tables, CLOS slots, and integer sequence indexes:

```lisp
(expect '(:user (:name "Ada" :roles #("dev" "ops")))
        :to-have-property
        '(:user :roles 1)
        "ops")
```

Failures report `:path`, `:present`, and `:value` in `:actual`, plus the
expected path and optional value in `:expected`.

### Close Numeric Assertions

`:to-be-close-to` mirrors Vitest `toBeCloseTo(value, numDigits?)`. The default
digit count is `2`, and a value passes when
`abs(expected - actual) < 10^-digits / 2`:

```lisp
(expect (+ 0.1d0 0.2d0) :to-be-close-to 0.3d0 5)
```

Failures report `:value`, `:expected-value`, `:num-digits`, `:difference`, and
`:threshold`, so reporters can display numeric drift without reparsing strings.

The ordering matchers `:to-be-greater-than`,
`:to-be-greater-than-or-equal`, `:to-be-less-than`, and
`:to-be-less-than-or-equal` accept real expected values and fail cleanly for
non-real actual values. Failure payloads include `:value`, `:expected-value`,
`:matcher`, `:operator`, `:actual-real`, and `:expected-real`.

### MOP Architecture Assertions

MOP architecture assertions let tests describe class and generic-function shape
without ad-hoc reflection helpers:

```lisp
(expect 'widget :to-have-slot 'state)
(expect #'render-widget :to-have-method-specialized-on '(widget stream))
```

These matchers report normalized slot and method-specializer lists through the
structured reporters, which keeps architecture tests AI-readable.

### Mutation Testing

`collect-mutations` walks a Lisp form and returns one-at-a-time mutant data.
`run-mutations` accepts a predicate that returns true when the mutant survives
the caller's checks and false when the mutant is killed:

```lisp
(cl-weave:run-mutations
 '(+ 1 1)
 (lambda (form mutation)
   (declare (ignore mutation))
   (= (eval form) 2)))
```

Mutation operators are data-backed and macro-extensible:

```lisp
(cl-weave:defmutation-operator :keyword-toggle (form path)
  "Toggles :enabled keyword literals to :disabled."
  (declare (ignore path))
  (when (eq form :enabled)
    (list :disabled)))

(cl-weave:collect-mutations '(:enabled)
                            :operators '(:keyword-toggle))
```

The first string form in `defmutation-operator` becomes stable operator
metadata. `list-mutation-operators` returns deterministic plist metadata for
CI tools and agents:

```lisp
(cl-weave:list-mutation-operators)
;; => ((:name :arithmetic-operator :description "...")
;;     (:name :keyword-toggle :description "..."))
```

The built-in operators cover arithmetic calls, comparison calls, boolean
literals, and `if` branch swaps. `report-mutations-sexp` and
`report-mutations-json` emit stable, AI-readable mutation reports with killed,
survived, errored, and score fields.

Use `mutation-score-passes-p` or `assert-mutation-score` to turn mutation
results into CI gates. A gate passes only when the score meets the threshold
and there are no survived or errored mutants:

```lisp
(let ((results (cl-weave:run-mutations
                '(+ 1 1)
                (lambda (form mutation)
                  (declare (ignore mutation))
                  (= (eval form) 2)))))
  (cl-weave:assert-mutation-score results 0.95))
```

### Table Tests

```lisp
(it-each ((1 2 3)
          (13 21 34))
    "adds ~A and ~A"
    (left right total)
  (expect (+ left right) :to-be total))

(describe-each ((:json "application/json")
                (:sexp "application/s-expression"))
    "~A reporter"
    (reporter content-type)
  (it "declares its content type"
    (expect content-type :to-satisfy #'stringp)))

(describe-each ((:json "application/json"))
    "~A reporter with fixtures"
    (reporter content-type)
  (before-each
    (setf (gethash :content-type *test-context*) content-type))
  (it-each ((:ok :ok))
      "runs generated case ~A"
      (actual expected)
    (expect actual :to-be expected)))

(it-only-each ((1 2 3))
    "focuses generated case ~A and ~A"
    (left right total)
  (expect (+ left right) :to-be total))

(it-skip-each ((:slow :case))
    "skips generated case ~A"
    (kind label)
  "blocked by upstream"
  (expect (list kind label) :to-equal '(:slow :case)))

(it-todo-each ((:parser :stream) (:ffi :crash-boundary))
    "documents generated todo ~A"
    (area label)
  "needs design")
```

`it-each` expands into independent `it` forms at macro expansion time.
`describe-each` expands into independent `describe` forms, so nested
fixtures and cases keep the same semantics as hand-written suites. Table forms
compose with canonical modifiers such as `it-only-each`,
`it-concurrent-each`, `it-sequential-each`, `it-fails-each`, `it-skip-each`,
and `it-todo-each`. Fixture hooks use the canonical Lisp names.
`docs/ai-contract.md` is the machine-readable normalization contract for
agents. Runtime metadata also exposes `referenceDocuments`, `citation`,
`supportChannels`, `securityContacts`, `lifecycle`, `runtimeSupport`, and
`releaseProcess` so external tools can discover canonical docs, citation
metadata, support routing, disclosure paths, platform support, release
policy, and project status without scraping prose.

### Conditional Runs

```lisp
(it-skip-if (not (probe-file #P"/tmp/service.sock"))
    "talks to a local service"
  (expect (probe-file #P"/tmp/service.sock") :to-be-truthy))

(it-run-if (member :sbcl *features*)
    "uses SBCL allocation counters"
  (expect (lambda () (list :ok)) :to-allocate-under 4096))

(describe-run-if (member :linux *features*)
    "linux-only integration"
  (it "checks a platform boundary"
    (expect :ok :to-be :ok)))
```

`it-skip-if` and `describe-skip-if` register skipped tests or suites when the
condition is true. `it-run-if` and `describe-run-if` register skipped tests or
suites when the condition is false.
Conditions are evaluated while the test file registers tests; skipped branches
emit ordinary `:skip` events with deterministic reasons, and their hooks and
bodies are not executed.

### Property Tests

```lisp
(it-property "addition is commutative"
    ((left (gen-integer :min -100 :max 100))
     (right (gen-integer :min -100 :max 100)))
  (expect (+ left right) :to-be (+ right left)))
```

Property generators are plain data objects. `it-property` runs generated examples
through the normal assertion engine, then reports the original failing values and
the minimized values through the same structured `assertion-failure` path used by
`expect`. Failure payloads also include the seed and zero-based generated case
index, so CI and agents can reproduce the run with `CL_WEAVE_PROPERTY_SEED`.

Built-in generators:

- `(gen-integer :min -100 :max 100)`
- `(gen-boolean)`
- `(gen-character :alphabet "abc")`
- `(gen-member '(:a :b :c))`
- `(gen-map function generator :name :derived)`
- `(gen-list generator :min-length 0 :max-length 8)`
- `(gen-string :min-length 0 :max-length 16 :alphabet "abc")`
- `(gen-vector generator :min-length 0 :max-length 8)`
- `(gen-state-machine initial-state transition event-generator :min-length 0 :max-length 16)`
- `(gen-one-of generator-a generator-b ...)`
- `(gen-recursive base-generator builder :max-depth 4)`
- `(gen-symbol :names '("x" "y") :package "CL-USER")`
- `(gen-keyword '("left" "right"))`
- `(gen-sexp :max-depth 4 :max-list-length 4)`
- `(gen-form :operators '(progn list cons) :max-depth 4 :max-arguments 3)`
- `(gen-tuple generator-a generator-b ...)`
- `(gen-such-that predicate generator :attempts 100)`

Generator combinators keep data and logic separate: generators describe how
values are produced and shrunk, while `it-property` owns execution, failure
capture, and reporting. `gen-list` shrinks both list structure and individual
elements; `gen-string` and `gen-vector` apply the same structural and element
shrinking to sequence-heavy APIs; `gen-state-machine` generates bounded event
streams and replayed state traces as `(:initial ... :events ... :states ...
:final ...)`, shrinking the event stream while recomputing states through the
same transition function; `gen-recursive` gives the builder a self-referential
generator for bounded S-expression and AST shapes; `gen-sexp` and `gen-form`
provide common Lisp data and macro-expansion inputs without embedding runner
logic in tests; `gen-tuple` shrinks each slot through its corresponding
generator; `gen-such-that` keeps generated and shrunk values inside the
predicate.

```lisp
(it-property "command shape is stable"
    ((command (gen-tuple (gen-one-of (gen-member '(:open :close))
                                     (gen-member '(:resize)))
                         (gen-such-that #'plusp
                                        (gen-integer :min 1 :max 20)))))
  (destructuring-bind (kind count) command
    (expect kind :to-satisfy #'keywordp)
    (expect count :to-satisfy #'plusp)))

(it-property "forms stay bounded"
    ((form (gen-form :operators '(quote if progn)
                     :max-depth 3
                     :max-arguments 2)))
  (expect form :to-satisfy (lambda (value) (or (atom value) (consp value)))))

(it-property "state machine traces stay replayable"
    ((trace (gen-state-machine
             :idle
             (lambda (state event)
               (ecase event
                 (:start :running)
                 (:stop :idle)
                 (:error :failed)))
             (gen-member '(:start :stop :error))
             :min-length 1
             :max-length 5)))
  (expect (getf trace :states) :to-satisfy
          (lambda (states)
            (= (length states) (1+ (length (getf trace :events))))))
  (expect (getf trace :final) :to-be (first (last (getf trace :states)))))
```

Use `*property-test-count*` and `*property-seed*` for dynamic REPL control, or
`CL_WEAVE_PROPERTY_TESTS` and `CL_WEAVE_PROPERTY_SEED` for reproducible CI runs.
`CL_WEAVE_PROPERTY_TESTS` must be a positive integer. Both CI environment
variables are parsed strictly, so invalid values fail fast with a `cl-weave:`
diagnostic instead of silently running zero generated cases.

### Fixtures

```lisp
(defvar *state*)

(describe "with fixture"
  (before-all
    (setf *state* (make-hash-table)))

  (before-all
    (setf (gethash :created *state*) t))

  (before-each
    (setf (gethash :trace *state*) nil))

  (around-each (next)
    (let ((*state* *state*))
      (unwind-protect
           (funcall next)
        (remhash :scratch *state*))))

  (after-each
    (remhash :trace *state*))

  (after-all
    (setf *state* nil))

  (it "uses dynamic state"
    (setf (gethash :x *state*) 1)
    (expect (gethash :x *state*) :to-be 1)))
```

`before-all` / `after-all` bodies run once around a suite. `before-each` /
`after-each` bodies run around every test in the current suite and nested suites.
`around-each` receives a continuation for the remaining around hooks and test
body, so special variables can be dynamically rebound around only the case.
Use `unwind-protect` inside `around-each` when the fixture owns cleanup.
Fixture hooks intentionally use canonical Lisp names rather than camelCase
aliases, because Common Lisp uppercases unescaped symbols while reading source.

### CPS Continuation Helpers

Use `with-continuation-result` when testing callback/CPS APIs that receive a
continuation function. The macro binds the continuation name supplied in the
binding list, runs the form, asserts that the continuation was called, and then
exposes the first value passed to it.

```lisp
(it "tests a CPS parser"
  (with-continuation-result (node next calledp)
      (parse-token-cps "42" #'next)
    (expect calledp :to-be-truthy)
    (expect node :to-equal '(:number 42))))
```

Use `with-continuation-values` when the continuation carries multiple values:

```lisp
(with-continuation-values (values next)
    (decode-cps input #'next)
  (expect values :to-equal '(:ok (:amount 100))))
```

### Skipping

```lisp
(describe-skip "upstream-dependent suite" "waiting for upstream behavior"
  (it "documents a blocked case"
    (expect :unreachable :to-be :reachable)))

(it-skip "documents a pending case" "waiting for upstream behavior")
```

Skipped suites report selected descendant cases as `:skip` without running suite
hooks or test bodies. Skipped cases use the same event status and do not fail
`run-all`.

### Focus And Todo

```lisp
(describe-only "focused suite"
  (it "runs inside focused suite"
    (expect :selected :to-be :selected)))

(it-only "focuses a single case"
  (expect (+ 40 2) :to-be 42))

(it-todo "documents a missing edge case" "needs property generator")
(it-todo-each ((:ast) (:ffi))
    "documents future coverage for ~A"
    (area)
  "needs generator")

(describe-todo "future protocol" "needs design"
  (it "documents the expected shape"
    (expect :draft :to-be :stable)))

(describe-todo-each ((:json) (:sexp))
    "future ~A reporter"
    (reporter)
  "needs snapshot contract"
  (it "documents pending reporter behavior"
    (expect reporter :to-satisfy #'keywordp)))
```

When any suite or case is focused, `run-all` executes only the focused path.
Todo suites report selected descendant cases as `:todo` without running suite
hooks or test bodies. Todo cases use the same event status and do not fail
`run-all`.

### Retry And Timeout

```lisp
(it "eventually observes an external state" (:retry 2 :timeout-ms 500)
  (expect (probe-state) :to-be :ready))

(it "supports retry options" (:retry 1)
  (expect (+ 20 22) :to-be 42))

(it-fails "documents a known parser bug" (:retry 1)
  (expect (parse-fragment input) :to-be :accepted))
```

`:retry` is the number of extra attempts after the first attempt. Fixtures and
dynamic `*test-context*` are recreated for every attempt. `:timeout-ms` fails the
case if a single attempt exceeds the configured wall-clock budget. Timeout
failures are reported as `test-timeout` conditions.

CLI and CI runs can set suite-wide defaults with `--retry`,
`CL_WEAVE_RETRY`, `--test-timeout-ms`, `CL_WEAVE_TEST_TIMEOUT_MS`,
`CL_WEAVE_TEST_TIMEOUT`, `--max-workers`, or `CL_WEAVE_MAX_WORKERS`. Per-test
options take priority over
global defaults, so `:retry 0` disables a global retry budget for one case,
`:timeout-ms` replaces the global per-attempt timeout, and `--max-workers`
bounds adjacent concurrent worker batches.

`it-fails` inverts one runnable case only when its test attempt signals
`assertion-failure`. An implementation error or timeout remains visible as
`:error` or `:fail`; an unexpectedly passing body is reported as `:fail` with
`expected-failure-missed`.

### Interactive Restarts

Every runnable attempt installs Common Lisp restarts while the body and
`before-each` / `after-each` hooks are active:

```lisp
(handler-bind ((cl-weave:assertion-failure
                 (lambda (condition)
                   (declare (ignore condition))
                   (invoke-restart 'cl-weave:retry-test))))
  (cl-weave:run-all))
```

`continue-test` records the current attempt as `:pass`, `skip-test` records it
as `:skip` with an optional reason, and `retry-test` reruns the attempt while
consuming the configured `:retry` budget. If no handler or debugger invokes a
restart, CI behavior is unchanged and the original failure, error, or timeout is
reported normally.

### Concurrent Tests

```lisp
(it-concurrent "fetches account metadata" (:timeout-ms 1000)
  (expect (fetch-account) :to-satisfy #'account-ready-p))

(it "uses option form when macros generate cases" (:concurrent t :retry 1)
  (expect (probe-cache) :to-be :warm))

(describe-concurrent "parallel-safe API checks"
  (it "fetches account" (expect (fetch-account) :to-satisfy #'account-ready-p))
  (it-sequential "uses shared rate-limit bucket"
    (expect (probe-rate-limit) :to-be :available)))
```

`it-concurrent` and `(:concurrent t)` mark a case as safe
to run beside adjacent concurrent cases. `describe-concurrent` /
`describe-concurrent` applies the same execution mode to descendants, and
`it-sequential` opts a single case back out. Report order
stays deterministic: events are emitted in the selected definition order. When
`:bail` is enabled, concurrent batching is disabled so fast-fail behavior
remains exact. `run-all :max-workers N`, `--max-workers N`, and
`CL_WEAVE_MAX_WORKERS=N` bound the number of worker threads used for each
adjacent concurrent batch.

### Filtering

```lisp
(cl-weave:run-all :name-filter "math > adds")
```

`name-filter` is a case-insensitive substring matched against the rendered test
path, for example `suite > nested suite > case`. Filtering composes with
`describe-only` and `it-only`: focus narrows the candidate set first, then the
name filter selects matching paths.

For command-line and CI usage, `CL_WEAVE_TEST_FILTER` provides the same filter:

```sh
perl -e 'alarm 120; exec @ARGV' -- env CL_WEAVE_TEST_FILTER='math > adds' sbcl --noinform --non-interactive --load scripts/run-tests.lisp
```

Suites with no selected descendants do not run `before-all` or `after-all`, so
filtered runs do not leak fixture side effects from unrelated suites.
By default, a filter that selects zero tests exits successfully. CI jobs that
must reject empty selections can pass `--fail-with-no-tests`, set
`CL_WEAVE_PASS_WITH_NO_TESTS=false`, or call
`(cl-weave:run-all :pass-with-no-tests nil)`.

### Sharding

```lisp
(cl-weave:run-all :shard '(1 3))
(cl-weave:list-tests :reporter :json :shard '(2 3))
```

Shard indexes are one-based and use `(INDEX COUNT)`. cl-weave first applies
focus and `name-filter`, then assigns a stable discovery ordinal to the selected
tests. A test belongs to shard `INDEX` when its ordinal maps to that slot.

For command-line and CI usage, `CL_WEAVE_SHARD` uses `INDEX/COUNT`:

```sh
perl -e 'alarm 120; exec @ARGV' -- env CL_WEAVE_SHARD=1/3 CL_WEAVE_REPORTER=json sbcl --noinform --non-interactive --load scripts/run-tests.lisp
```

Sharding composes with filtering, list mode, bail, ASDF `run-system`, and watch
mode. Suites with no descendants in the requested shard do not run
`before-all` or `after-all`.

### Sequence Ordering

```lisp
(cl-weave:run-all :order :random :seed 12345)
(cl-weave:list-tests :reporter :json :order :random :seed 12345)
```

The default order is `:defined`. `:order :random` applies a deterministic,
seeded order inside each suite while preserving suite hook boundaries. The same
seed produces the same execution order and list-mode order across SBCL
processes.

Selection is resolved before ordering: focus, `name-filter`, and shard choose
the test set first, then sequence ordering decides the order of the remaining
children. This keeps CI shard membership stable when teams rotate seeds to
reproduce order-dependent failures.

For command-line and CI usage:

```sh
perl -e 'alarm 360; exec @ARGV' -- env CL_WEAVE_SEQUENCE=random CL_WEAVE_SEQUENCE_SEED=12345 sbcl --noinform --non-interactive --load scripts/run-tests.lisp
```

### Test Listing

```lisp
(cl-weave:list-tests :reporter :json :name-filter "math")
(cl-weave:collect-test-plan (cl-weave::root-suite) :name-filter "math")
```

List mode discovers selected tests without executing suite hooks or test
bodies. It composes with focus, filtering, skipped suites, and todo suites, and
emits `:run`, `:skip`, or `:todo` plan entries with `path`, `pathString`,
`location`, `reason`, `focused`, `retry`, `timeout-ms`, `concurrent`, `tags`,
and `dependsOn` metadata. `location` records the macro source file when
available; JSON emits `null` for manually constructed tests without source
metadata. `tags` and `dependsOn` are descriptive metadata only; cl-weave does
not infer filtering or dependency ordering from them.

For command-line and CI usage, `CL_WEAVE_LIST=1` prints the selected test plan
and exits with status `0`:

```sh
perl -e 'alarm 120; exec @ARGV' -- env CL_WEAVE_LIST=1 CL_WEAVE_REPORTER=json CL_WEAVE_TEST_FILTER='math' sbcl --noinform --non-interactive --load scripts/run-tests.lisp
```

List mode supports `spec`, `sexp`, `json`, and `jsonl` reporters. `CL_WEAVE_OUTPUT_FILE`
can write the plan payload to an artifact file.

AI agents can also query plans as plain Lisp facts:

```lisp
(cl-weave:test-plan-where
 (cl-weave:collect-test-plan (cl-weave::root-suite))
 (:status ?test :run)
 (:focused ?test)
 (:concurrent ?test))
;; => (((?test . ("suite" "case"))))
```

`test-plan-facts` emits data such as `(:test path)`, `(:status path status)`,
`:focused`, `:reason`, `:retry`, `:timeout-ms`, `:concurrent`, and `:location`.
`logic-where`, `logic-program`, `logic-run`, and `test-plan-where` keep data and
logic separate: relations stay plain lists, while query and rule syntax stays in
macros. Variables are symbols whose names start with `?`, clauses are matched
left-to-right, and `(:limit n)` caps backtracking results.

Rules use a Prolog-style `(:- head goal...)` form:

```lisp
(let ((program (cl-weave:logic-program
                (:parent "grand" "parent")
                (:parent "parent" "child")
                (:- (:ancestor ?left ?right)
                    (:parent ?left ?right))
                (:- (:ancestor ?left ?right)
                    (:parent ?left ?middle)
                    (:ancestor ?middle ?right)))))
  (cl-weave:logic-run program
    (:ancestor ?left "child")))
;; => (((?left . "parent"))
;;     ((?left . "grand")))
```

`query-test-plan` and `test-plan-where` accept either collected plan entries or
an already-expanded logic program, so derived views can be layered on top of
`test-plan-facts` without a second adapter:

```lisp
(let* ((plan (cl-weave:collect-test-plan (cl-weave::root-suite)))
       (program (append
                 (cl-weave:test-plan-facts plan)
                 (cl-weave:logic-program
                  (:- (:selected ?test)
                      (:status ?test :run)
                      (:focused ?test))))))
  (cl-weave:test-plan-where program
    (:selected ?test)))
```

### Bail

```lisp
(cl-weave:run-all :bail t)
(cl-weave:run-all :bail 2)
```

`:bail t` stops after the first `:fail` or `:error` event. A positive integer
stops after that many failing or errored events. Skips and todos do not count
toward the bail limit.

For command-line and CI usage, `CL_WEAVE_BAIL` accepts `true`, `yes`, `on`,
`t`, `false`, `no`, `off`, `0`, `nil`, or a positive integer:

```sh
perl -e 'alarm 120; exec @ARGV' -- env CL_WEAVE_BAIL=1 sbcl --noinform --non-interactive --load scripts/run-tests.lisp
```

Bail composes with focus and filtering. Reporters emit only the events that were
selected and executed before the runner stopped.

### Mocking

```lisp
(let ((add (make-mock-function (lambda (left right)
                                 (+ left right)))))
  (expect (funcall add 1 2) :to-be 3)
  (expect (funcall add 5 8) :to-be 13)
  (expect add :to-have-been-called)
  (expect add :to-have-been-called-times 2)
  (expect add :to-have-been-called-with 1 2)
  (expect add :to-have-been-nth-called-with 1 1 2)
  (expect add :to-have-been-last-called-with 5 8)
  (expect add :to-have-returned)
  (expect add :to-have-returned-times 2)
  (expect add :to-have-returned-with 3)
  (expect add :to-have-nth-returned-with 1 3)
  (expect add :to-have-last-returned-with 13)
  (expect (mock-calls add) :to-equal '((1 2) (5 8)))
  (expect (mock-results add)
          :to-equal
          '((:type :return :value 3 :values (3))
            (:type :return :value 13 :values (13))))
  (clear-mock add))

(with-mocked-functions (((symbol-function 'now) (lambda () 0)))
  (expect (now) :to-be 0))

(let ((spy (spy-on 'now)))
  (mock-return-value spy 42)
  (expect (now) :to-be 42)
  (mock-restore spy))
```

`make-mock-function` creates an inspectable function object. `mock-function-p`
tests whether a value is a registered cl-weave mock without signalling on
non-functions. `mock-calls` returns a copy
of the recorded argument lists, `mock-results` returns return/throw reports,
and `clear-mock` resets both histories for one mock. `reset-mock` resets
histories and replaces that mock's implementation with
the default no-op function.
`mock-implementation` replaces an existing mock's active implementation.
`mock-return-value` pins a single return value, while `mock-return-values` pin
Common Lisp multiple values.
`clear-all-mocks` resets histories for every registered mock without replacing
their implementations; `reset-all-mocks` applies the reset behavior to every
registered mock. `spy-on` replaces a symbol's function cell with a registered mock
that calls the original function by default. `mock-restore` restores that
function cell when it is still bound to the spy,
reset the spy history, and restore the spy implementation to the original
function. `restore-all-mocks` applies that behavior to every active spy while
leaving regular mocks untouched.
`:to-have-returned-with` accepts Common Lisp multiple values as matcher
operands, for example
`(expect mock :to-have-returned-with :ok 42)`. Nth mock matchers use one-based
indices. Nth returned matchers count only successful returns, while
`mock-results` still keeps thrown result reports.

`with-mocked-functions` temporarily rewrites global function cells. The
original function cells are restored with `unwind-protect`.

### Subprocess Isolation

```lisp
(it-isolated "ffi parser rejects invalid input"
    (:systems ("my-project-tests") :timeout 5 :keep-files :on-failure)
  (expect (parse-native-buffer #(0 1 2)) :to-equal :invalid))

(let ((result (run-isolated
               '(error "native boundary failed")
               :systems '("my-project-tests")
               :package "MY-PROJECT/TESTS"
               :timeout 5
               :keep-files :on-failure)))
  (expect (isolated-result-status result) :to-be :fail))
```

`it-isolated` runs the body in a fresh SBCL subprocess and reports non-zero
exits or timeouts as normal structured assertion failures. Use it around FFI,
native parser, and crash-boundary tests where the parent REPL or CI process
must stay alive. `run-isolated` returns captured stdout/stderr strings in all
cases. `:keep-files` accepts `nil`, `t`, or `:on-failure`; the last option keeps
artifacts only for non-passing child processes. When files are retained, the
generated script, stdout, stderr, and temporary HOME directory paths are exposed
via
`isolated-result-script-path`, `isolated-result-stdout-path`,
`isolated-result-stderr-path`, and `isolated-result-home-path`. With the
default `:keep-files nil`, those path accessors return `nil` and the temporary
artifacts are deleted before control returns to the parent process.

### Reporters

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

When `CL_WEAVE_COVERAGE=1` is set, `scripts/run-tests.lisp` enables
`sb-cover:store-coverage-data` while loading the product system, then disables
instrumentation before loading the test system. This keeps test helpers out of
the measured code while forcing a coverage-aware product reload.

Run `scripts/run-coverage-gate.sh` for the CI coverage contract. It requires
every Lisp file under `src/` to be present in the SB-COVER report and requires
aggregate product expression and branch coverage to stay at or above the 87%
ratchet baseline (raise the threshold as coverage grows). Missing source
measurements or a lower rate fail the command. The gate writes its
machine-readable result to `cl-weave-coverage-summary.json`.

The `:sexp` reporter is the stable Lisp-native AI interface. The `:json`
reporter is the stable external-tool interface. The `:jsonl` reporter emits one
JSON object per line for streaming CI logs and agent ingestion. These structured
reporters include failed and errored path summaries for focused reruns. See
`docs/ai-contract.md`. The metadata root also advertises these canonical
non-policy paths through `referenceDocuments` and `citation`, plus support
and lifecycle contracts through `supportChannels`, `securityContacts`,
`lifecycle`, `runtimeSupport`, and `releaseProcess`.

`scripts/run-tests.lisp` accepts `CL_WEAVE_REPORTER=spec`, `sexp`, `json`, `jsonl`,
`tap`, `github`, or `junit`, accepts `CL_WEAVE_TEST_FILTER` for path substring filtering, accepts
`CL_WEAVE_SHARD=INDEX/COUNT` for CI partitioning, accepts `CL_WEAVE_LIST=1` for
discovery without execution, accepts `CL_WEAVE_SEQUENCE=random` plus positive
`CL_WEAVE_SEQUENCE_SEED=N` for deterministic order reproduction, and accepts
`CL_WEAVE_BAIL` for fast-fail runs. It also accepts `CL_WEAVE_RETRY=N` for a
global retry default and `CL_WEAVE_TEST_TIMEOUT_MS=N` or
`CL_WEAVE_TEST_TIMEOUT=N` for a global per-attempt timeout default, plus
`CL_WEAVE_MAX_WORKERS=N` to bound adjacent concurrent worker batches. Boolean
environment variables treat
`0`, `false`, `no`, `off`, and `nil` as false. Set
`CL_WEAVE_PASS_WITH_NO_TESTS=false` to fail CI when filters select no tests.
Set `CL_WEAVE_COVERAGE=1` to wrap execution with SBCL `sb-cover`, set
`CL_WEAVE_COVERAGE_REPORT_DIR=path/` to emit a populated HTML coverage report,
and set `CL_WEAVE_COVERAGE_FILE=path` to save the coverage state as a CI
artifact.
Set `CL_WEAVE_SNAPSHOT_DIR`, `CL_WEAVE_SNAPSHOT_FILE`, and
`CL_WEAVE_UPDATE_SNAPSHOTS=1` to control snapshot location and updates from CI.
Set `CL_WEAVE_OUTPUT_FILE=path` to write reporter output directly to an
artifact file while preserving the process exit code contract. Use `tap` for
line-oriented CI logs, `github` for GitHub Actions annotations, and `junit`
when a CI service should ingest test results as XML. List mode supports `spec`,
`sexp`, `json`, and `jsonl`.

The CLI uses kebab-case flags consistently, including `--test-name-pattern`,
`--watch-interval`, `--coverage-output`, `--output-file`,
`--test-timeout-ms`, `--pass-with-no-tests`, `--fail-with-no-tests`,
`--snapshot-dir`, `--snapshot-file`, `--max-workers`, and
`--update-snapshots`.

### ASDF System Runner and Watch Mode

```lisp
(cl-weave:asdf-system-files "my-project-tests" :include-dependencies t)
(cl-weave:run-system "my-project-tests" :reporter :spec)
(cl-weave:watch-system "my-project-tests"
                       :reporter :json
                       :name-filter "parser"
                       :shard '(1 2)
                       :bail 1
                       :coverage t
                       :coverage-output "my-project-tests.coverage"
                       :pass-with-no-tests t
                       :include-dependencies t
                       :interval 0.5)
```

`asdf-system-files` returns the existing source files declared by an ASDF
system. `run-system` reloads the system with ASDF, then runs the currently
registered cl-weave tests. `watch-system` uses ASDF dependency information and
file write dates to rerun only after declared source files change. When every
changed file is already a registered test-definition file, watch mode narrows
the rerun to those files only. Changes to non-test files, newly added files, or
deleted files fall back to a full-suite rerun so implementation edits cannot
silently skip affected tests.
Coverage collection and `:pass-with-no-tests` policy are forwarded on every
watch rerun, so local watch sessions exercise the same success criteria and
coverage artifact path as an equivalent one-shot `run-all`.
Reporter output goes to `:stream`; watch status goes to `:status-stream`, which
defaults to `*error-output*`.

The script runner enables watch mode with environment variables:

```sh
perl -e 'alarm 360; exec @ARGV' -- env CL_WEAVE_WATCH=1 sbcl --noinform --load scripts/run-tests.lisp
perl -e 'alarm 360; exec @ARGV' -- env CL_WEAVE_WATCH=1 CL_WEAVE_WATCH_ONCE=1 sbcl --noinform --load scripts/run-tests.lisp
perl -e 'alarm 360; exec @ARGV' -- env CL_WEAVE_WATCH=1 CL_WEAVE_WATCH_INTERVAL=0.25 sbcl --noinform --load scripts/run-tests.lisp
```

CI should keep `CL_WEAVE_WATCH` unset and use `CL_WEAVE_REPORTER=junit`,
`CL_WEAVE_REPORTER=tap`, `CL_WEAVE_REPORTER=json`, or
`CL_WEAVE_REPORTER=jsonl`.

## Project Operations

- Adoption guide: [docs/adoption.md](docs/adoption.md)
- AI contract: [docs/ai-contract.md](docs/ai-contract.md)
- Issue reporting guide: [docs/issue-reporting.md](docs/issue-reporting.md)
- Pull request guidance: [docs/pull-request-template.md](docs/pull-request-template.md)
- Pull request form: [.github/pull_request_template.md](.github/pull_request_template.md)
- Pull request queue: <https://github.com/takeokunn/cl-weave/pulls>
- Bug report form: [.github/ISSUE_TEMPLATE/bug_report.md](.github/ISSUE_TEMPLATE/bug_report.md)
- Feature request form: [.github/ISSUE_TEMPLATE/feature_request.md](.github/ISSUE_TEMPLATE/feature_request.md)
- Issue template routing: [.github/ISSUE_TEMPLATE/config.yml](.github/ISSUE_TEMPLATE/config.yml)
- Community health contract: [docs/community-health.md](docs/community-health.md)
- Code ownership: [.github/CODEOWNERS](.github/CODEOWNERS)
- Governance: [docs/governance.md](docs/governance.md)
- Maintenance policy: [docs/maintenance-policy.md](docs/maintenance-policy.md)
- Distribution policy: [docs/distribution-policy.md](docs/distribution-policy.md)
- Support policy: [docs/support-policy.md](docs/support-policy.md)
- Runtime support: [docs/runtime-support.md](docs/runtime-support.md)
- Release process: [docs/release-process.md](docs/release-process.md)
- Versioning policy: [docs/versioning-policy.md](docs/versioning-policy.md)
- Project scope: [docs/project-scope.md](docs/project-scope.md)
- Triage policy: [docs/triage-policy.md](docs/triage-policy.md)
- Security reporting: <https://github.com/takeokunn/cl-weave/security/advisories/new>
- Issue tracker: <https://github.com/takeokunn/cl-weave/issues>
- Release notes: <https://github.com/takeokunn/cl-weave/releases>

Runtime metadata mirrors these operations surfaces through `policyDocuments`,
`referenceDocuments`, `supportChannels`, `communityHealth`,
`securityContacts`, `lifecycle`, `runtimeSupport`, and `releaseProcess` for
agent-side OSS operations discovery.

## License

MIT. See [LICENSE](LICENSE).
