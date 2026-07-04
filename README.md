# cl-weave

`cl-weave` is a modern Common Lisp testing framework inspired by Vitest and
designed around Lisp's strengths: macros, conditions, dynamic bindings, and
reproducible Nix workflows.

The project is intentionally dependency-free at the core. It should be easy to
run in CI, embed in ASDF projects, and extend from the REPL.

## Status

Early MVP. The current focus is a solid core:

- `describe` / `it` hierarchical test DSL
- `expect` matcher assertions with readable failure reports
- smart S-expression assertions that capture operand values
- `it-each` / `test-each` and `describe-each` compile-time table tests
- `it-property` deterministic property tests with shrinking
- `it-isolated` subprocess tests for FFI and crash boundaries
- `before-all` / `after-all` and `before-each` / `after-each` dynamic fixtures
- `describe-skip` / `it-skip` / `test-skip` skipped suites and cases
- `describe-skip-if` / `it-skip-if` and `run-if` conditional registration
- `describe-only` / `it-only` focused runs
- `describe-todo` / `it-todo` / `test-todo` todo suites and cases
- Vitest-style test name filtering for focused local and CI runs
- Vitest-style test discovery list mode for AI agents and CI tooling
- source file metadata in structured reporters and test plans
- Vitest-style deterministic sequence ordering for flaky-test reproduction
- Vitest-style `:bail` execution control for fast-fail CI runs
- Vitest-style per-test `:retry` and `:timeout-ms` controls
- Vitest-style `it-concurrent` / `test-concurrent` parallel cases
- Vitest-style `it-fails` / `test-fails` expected-failure cases
- Vitest-style length, instance, inline snapshot, and external snapshot matchers
- CI-friendly thunk runtime and allocation assertions
- SBCL `sb-cover` reset/save integration for CI coverage artifacts
- Vitest-style mock functions with call history assertions
- ASDF system definitions
- ASDF-aware system runner and watch mode
- spec, S-expression, JSON, TAP, and JUnit XML reporters
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
sbcl --noinform --non-interactive --load scripts/run-tests.lisp
```

With Nix:

```sh
nix develop
nix flake check
```

## CI

GitHub Actions runs the same Nix entrypoints used locally:

```sh
nix flake check --print-build-logs
nix develop --command env CL_WEAVE_REPORTER=json sbcl --noinform --non-interactive --load scripts/run-tests.lisp
nix develop --command env CL_WEAVE_REPORTER=tap sbcl --noinform --non-interactive --load scripts/run-tests.lisp
nix develop --command env CL_WEAVE_REPORTER=junit sbcl --noinform --non-interactive --load scripts/run-tests.lisp
nix develop --command env CL_WEAVE_LIST=1 CL_WEAVE_REPORTER=json sbcl --noinform --non-interactive --load scripts/run-tests.lisp
nix develop --command env CL_WEAVE_TEST_FILTER='math > adds' sbcl --noinform --non-interactive --load scripts/run-tests.lisp
nix develop --command env CL_WEAVE_SEQUENCE=random CL_WEAVE_SEQUENCE_SEED=12345 sbcl --noinform --non-interactive --load scripts/run-tests.lisp
nix develop --command env CL_WEAVE_BAIL=1 sbcl --noinform --non-interactive --load scripts/run-tests.lisp
nix develop --command env CL_WEAVE_COVERAGE=1 CL_WEAVE_COVERAGE_FILE=cl-weave.coverage sbcl --noinform --non-interactive --load scripts/run-tests.lisp
```

The workflow uploads `cl-weave-results.json` and `cl-weave-junit.xml` as the
`cl-weave-test-reports` artifact. JSON schema v2 is intended for AI agents and
external automation: every event includes both a machine `path` and a stable
Vitest-style `pathString`. JUnit is intended for CI test result ingestion.

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
(expect (lambda () (loop repeat 10 collect :x)) :to-cons-less-than 4096)
(expect form :to-match-inline-snapshot "(:ok 42)")
(let ((*snapshot-directory* #P"tests/__snapshots__/"))
  (with-snapshot-updates
    (expect form :to-match-snapshot "suite/case"))
  (expect form :to-match-snapshot "suite/case"))
(expect value :not :to-be nil)
(expect-not value :to-be nil)
```

With matcher syntax, `expect` captures the original S-expression and reports
matcher, actual, expected, negation, and pass metadata through conditions and
reporters. `expect-not` is Vitest-style sugar for matcher assertions that
should fail when the underlying matcher passes; it uses the same structured
failure payload as `(expect value :not matcher ...)`.

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
`CL_WEAVE_UPDATE_SNAPSHOTS=1` enables the same update mode.

Built-in matchers:

- `:to-be`
- `:to-equal`
- `:to-equalp`
- `:to-be-truthy`
- `:to-be-falsy`
- `:to-be-null`
- `:to-be-defined`
- `:to-satisfy`
- `:to-be-type-of`
- `:to-be-instance-of`
- `:to-contain`
- `:to-have-length`
- `:to-be-greater-than`
- `:to-be-greater-than-or-equal`
- `:to-be-less-than`
- `:to-be-less-than-or-equal`
- `:to-throw`
- `:to-run-under-ms`
- `:to-cons-less-than`
- `:to-have-slot`
- `:to-have-method-specialized-on`
- `:to-expand-to`
- `:to-match-inline-snapshot`
- `:to-match-snapshot`
- `:to-have-been-called`
- `:to-have-been-called-times`
- `:to-have-been-called-with`

Custom matchers use `defmatcher`. The matcher receives the evaluated actual
value and the remaining expected operands as a list. Return the pass boolean,
then optional reported actual and expected values for structured reporters:

```lisp
(cl-weave:defmatcher :to-have-status (response expected)
  (let ((actual-status (getf response :status))
        (wanted-status (first expected)))
    (values (= actual-status wanted-status)
            actual-status
            wanted-status)))

(expect '(:status 201 :body "created") :to-have-status 201)
```

### Performance And Allocation

Performance assertions accept thunks so the measured form is executed exactly
inside the matcher:

```lisp
(expect (lambda () (parse-integer "42")) :to-run-under-ms 5)
(expect (lambda () (loop repeat 10 collect :x)) :to-cons-less-than 4096)
```

Each matcher executes its thunk once. If you assert both runtime and allocation,
the body runs once per matcher. Failure reports include `:elapsed-seconds`,
`:elapsed-ms`, `:bytes-consed`, and the returned multiple values in `:values`.
Allocation measurement uses the implementation's byte-consing counter; it is
currently backed by SBCL and fails clearly on implementations that do not expose
one.

### MOP Architecture Assertions

MOP architecture assertions let tests describe class and generic-function shape
without ad-hoc reflection helpers:

```lisp
(expect 'widget :to-have-slot 'state)
(expect #'render-widget :to-have-method-specialized-on '(widget stream))
```

These matchers report normalized slot and method-specializer lists through the
structured reporters, which keeps architecture tests AI-readable.

### Table Tests

```lisp
(it-each ((1 2 3)
          (13 21 34))
    "adds ~A and ~A"
    (left right total)
  (expect (+ left right) :to-be total))

(test-each ((2 3 5)
            (5 8 13))
    "also adds ~A and ~A"
    (left right total)
  (expect (+ left right) :to-be total))

(describe-each ((:json "application/json")
                (:sexp "application/s-expression"))
    "~A reporter"
    (reporter content-type)
  (it "declares its content type"
    (expect content-type :to-satisfy #'stringp)))
```

`it-each` and `test-each` expand into independent `it` forms at macro expansion
time. `describe-each` expands into independent `describe` forms, so nested
fixtures and cases keep the same semantics as hand-written suites.

### Conditional Runs

```lisp
(it-skip-if (not (probe-file #P"/tmp/service.sock"))
    "talks to a local service"
  (expect (probe-file #P"/tmp/service.sock") :to-be-truthy))

(it-run-if (member :sbcl *features*)
    "uses SBCL allocation counters"
  (expect (lambda () (list :ok)) :to-cons-less-than 4096))

(describe-run-if (member :linux *features*)
    "linux-only integration"
  (it "checks a platform boundary"
    (expect :ok :to-be :ok)))
```

`it-skip-if`, `test-skip-if`, and `describe-skip-if` register skipped tests or
suites when the condition is true. `it-run-if`, `test-run-if`, and
`describe-run-if` register skipped tests or suites when the condition is false.
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
- `(gen-member '(:a :b :c))`
- `(gen-map function generator :name :derived)`
- `(gen-list generator :min-length 0 :max-length 8)`
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
elements; `gen-recursive` gives the builder a self-referential generator for
bounded S-expression and AST shapes; `gen-sexp` and `gen-form` provide common
Lisp data and macro-expansion inputs without embedding runner logic in tests;
`gen-tuple` shrinks each slot through its corresponding generator;
`gen-such-that` keeps generated and shrunk values inside the predicate.

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
```

Use `*property-test-count*` and `*property-seed*` for dynamic REPL control, or
`CL_WEAVE_PROPERTY_TESTS` and `CL_WEAVE_PROPERTY_SEED` for reproducible CI runs.

### Fixtures

```lisp
(defvar *state*)

(describe "with fixture"
  (before-all
    (setf *state* (make-hash-table)))

  (before-each
    (setf (gethash :trace *state*) nil))

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

### Skipping

```lisp
(describe-skip "upstream-dependent suite" "waiting for upstream behavior"
  (it "documents a blocked case"
    (expect :unreachable :to-be :reachable)))

(it-skip "documents a pending case" "waiting for upstream behavior")
(test-skip "alias for it-skip")
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
(test-todo "alias for it-todo")

(describe-todo "future protocol" "needs design"
  (it "documents the expected shape"
    (expect :draft :to-be :stable)))
```

When any suite or case is focused, `run-all` executes only the focused path.
Todo suites report selected descendant cases as `:todo` without running suite
hooks or test bodies. Todo cases use the same event status and do not fail
`run-all`.

### Retry And Timeout

```lisp
(it "eventually observes an external state" (:retry 2 :timeout-ms 500)
  (expect (probe-state) :to-be :ready))

(test "alias with the same options" (:retry 1)
  (expect (+ 20 22) :to-be 42))

(it-fails "documents a known parser bug" (:retry 1)
  (expect (parse-fragment input) :to-be :accepted))
```

`:retry` is the number of extra attempts after the first attempt. Fixtures and
dynamic `*test-context*` are recreated for every attempt. `:timeout-ms` fails the
case if a single attempt exceeds the configured wall-clock budget. Timeout
failures are reported as `test-timeout` conditions.

`it-fails` and `test-fails` invert one runnable case: any assertion failure,
error, or timeout is reported as `:pass`; an unexpectedly passing body is
reported as `:fail` with `expected-failure-missed`.

### Concurrent Tests

```lisp
(it-concurrent "fetches account metadata" (:timeout-ms 1000)
  (expect (fetch-account) :to-satisfy #'account-ready-p))

(test "uses option form when macros generate cases" (:concurrent t :retry 1)
  (expect (probe-cache) :to-be :warm))
```

`it-concurrent`, `test-concurrent`, and `(:concurrent t)` mark a case as safe
to run beside adjacent concurrent cases. Report order stays deterministic:
events are emitted in the selected definition order. When `:bail` is enabled,
concurrent batching is disabled so fast-fail behavior remains exact.

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
CL_WEAVE_TEST_FILTER='math > adds' sbcl --noinform --non-interactive --load scripts/run-tests.lisp
```

Suites with no selected descendants do not run `before-all` or `after-all`, so
filtered runs do not leak fixture side effects from unrelated suites.

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
CL_WEAVE_SHARD=1/3 CL_WEAVE_REPORTER=json sbcl --noinform --non-interactive --load scripts/run-tests.lisp
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
CL_WEAVE_SEQUENCE=random CL_WEAVE_SEQUENCE_SEED=12345 sbcl --noinform --non-interactive --load scripts/run-tests.lisp
```

### Test Listing

```lisp
(cl-weave:list-tests :reporter :json :name-filter "math")
(cl-weave:collect-test-plan (cl-weave::root-suite) :name-filter "math")
```

List mode discovers selected tests without executing suite hooks or test
bodies. It composes with focus, filtering, skipped suites, and todo suites, and
emits `:run`, `:skip`, or `:todo` plan entries with `path`, `pathString`,
`location`, `reason`, `focused`, `retry`, `timeout-ms`, and `concurrent`
metadata. `location` records the macro source file when available; JSON emits
`null` for manually constructed tests without source metadata.

For command-line and CI usage, `CL_WEAVE_LIST=1` prints the selected test plan
and exits with status `0`:

```sh
CL_WEAVE_LIST=1 CL_WEAVE_REPORTER=json CL_WEAVE_TEST_FILTER='math' sbcl --noinform --non-interactive --load scripts/run-tests.lisp
```

List mode supports `spec`, `sexp`, and `json` reporters. `CL_WEAVE_OUTPUT_FILE`
can write the plan payload to an artifact file.

### Bail

```lisp
(cl-weave:run-all :bail t)
(cl-weave:run-all :bail 2)
```

`:bail t` stops after the first `:fail` or `:error` event. A positive integer
stops after that many failing or errored events. Skips and todos do not count
toward the bail limit.

For command-line and CI usage, `CL_WEAVE_BAIL` accepts `true`, `false`, `0`,
or a positive integer:

```sh
CL_WEAVE_BAIL=1 sbcl --noinform --non-interactive --load scripts/run-tests.lisp
```

Bail composes with focus and filtering. Reporters emit only the events that were
selected and executed before the runner stopped.

### Mocking

```lisp
(let ((add (make-mock-function (lambda (left right)
                                 (+ left right)))))
  (expect (funcall add 1 2) :to-be 3)
  (expect add :to-have-been-called)
  (expect add :to-have-been-called-times 1)
  (expect add :to-have-been-called-with 1 2)
  (expect (mock-calls add) :to-equal '((1 2)))
  (clear-mock add))

(with-mocked-functions (((symbol-function 'now) (lambda () 0)))
  (expect (now) :to-be 0))
```

`make-mock-function` creates an inspectable function object, close to
Vitest's `vi.fn`. `mock-calls` returns a copy of the recorded argument lists,
and `clear-mock` resets the call history.

`with-mocked-functions` temporarily rewrites global function cells. The
original function cells are restored with `unwind-protect`.

### Subprocess Isolation

```lisp
(it-isolated "ffi parser rejects invalid input"
    (:systems ("my-project-tests") :timeout 5)
  (expect (parse-native-buffer #(0 1 2)) :to-equal :invalid))

(let ((result (run-isolated
               '(error "native boundary failed")
               :systems '("my-project-tests")
               :package "MY-PROJECT/TESTS"
               :timeout 5)))
  (expect (isolated-result-status result) :to-be :fail))
```

`it-isolated` runs the body in a fresh SBCL subprocess and reports non-zero
exits or timeouts as normal structured assertion failures. Use it around FFI,
native parser, and crash-boundary tests where the parent REPL or CI process
must stay alive.

### Reporters

```lisp
(cl-weave:run-all :reporter :spec)
(cl-weave:run-all :reporter :sexp)
(cl-weave:run-all :reporter :json)
(cl-weave:run-all :reporter :tap)
(cl-weave:run-all :reporter :junit)
(cl-weave:run-all :reporter :json :name-filter "properties")
(cl-weave:run-all :coverage t :coverage-output "cl-weave.coverage")
```

`run-all` returns true when the suite passed and false otherwise.

Coverage support is optional and SBCL-specific. `run-all :coverage t` requires
`sb-cover`, resets counters before execution by default, and saves a readable
coverage state with `sb-cover:save-coverage-in-file` when `:coverage-output` is
provided. Pass `:coverage-reset nil` to merge the run into existing counters.
Projects remain responsible for loading code with SBCL coverage instrumentation;
cl-weave only manages the test-run reset/save boundary.

The `:sexp` reporter is the stable Lisp-native AI interface. The `:json`
reporter is the stable external-tool interface. Both include failed and errored
path summaries for focused reruns. See `docs/ai-contract.md`.

`scripts/run-tests.lisp` accepts `CL_WEAVE_REPORTER=spec`, `sexp`, `json`,
`tap`, or `junit`, accepts `CL_WEAVE_TEST_FILTER` for path substring filtering, accepts
`CL_WEAVE_SHARD=INDEX/COUNT` for CI partitioning, accepts `CL_WEAVE_LIST=1` for
discovery without execution, accepts `CL_WEAVE_SEQUENCE=random` plus
`CL_WEAVE_SEQUENCE_SEED=N` for deterministic order reproduction, and accepts
`CL_WEAVE_BAIL` for fast-fail runs. Set `CL_WEAVE_COVERAGE=1` to wrap
execution with SBCL `sb-cover`, and set `CL_WEAVE_COVERAGE_FILE=path` to save
the coverage state as a CI artifact.
Set `CL_WEAVE_OUTPUT_FILE=path` to write reporter output directly to an
artifact file while preserving the process exit code contract. Use `tap` for
line-oriented CI logs and `junit` when a CI service should ingest test results
as XML. List mode supports `spec`, `sexp`, and `json`.

### ASDF System Runner and Watch Mode

```lisp
(cl-weave:asdf-system-files "my-project-tests" :include-dependencies t)
(cl-weave:run-system "my-project-tests" :reporter :spec)
(cl-weave:watch-system "my-project-tests"
                       :reporter :json
                       :name-filter "parser"
                       :shard '(1 2)
                       :bail 1
                       :include-dependencies t
                       :interval 0.5)
```

`asdf-system-files` returns the existing source files declared by an ASDF
system. `run-system` reloads the system with ASDF, then runs the currently
registered cl-weave tests. `watch-system` uses ASDF dependency information and
file write dates to rerun only after declared source files change.
Reporter output goes to `:stream`; watch status goes to `:status-stream`, which
defaults to `*error-output*`.

The script runner enables watch mode with environment variables:

```sh
CL_WEAVE_WATCH=1 sbcl --noinform --load scripts/run-tests.lisp
CL_WEAVE_WATCH=1 CL_WEAVE_WATCH_INTERVAL=0.25 sbcl --noinform --load scripts/run-tests.lisp
```

CI should keep `CL_WEAVE_WATCH` unset and use `CL_WEAVE_REPORTER=junit`,
`CL_WEAVE_REPORTER=tap`, or `CL_WEAVE_REPORTER=json`.

## Roadmap

MVP quality comes first. The intended direction is:

- mutation testing

## License

MIT
