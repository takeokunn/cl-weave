# cl-weave AI Contract

`cl-weave` exposes structured test output as S-expressions and JSON so agents
can parse results without scraping human text.

## CLI Metadata Contract

Agents should use `cl-weave metadata [SYSTEM]` as the discovery entrypoint
before generating tests or interpreting project-specific matcher failures. The
command loads the requested ASDF system and then emits JSON by default:

```sh
timeout 120s nix run . -- metadata cl-weave-tests --output cl-weave-metadata.json
```

The JSON root is stable:

```json
{
  "schemaVersion": 1,
  "kind": "cl-weave-metadata",
  "version": "0.1.0",
  "commands": ["run", "list", "watch", "metadata", "version", "help"],
  "reporters": ["spec", "sexp", "json", "jsonl", "tap", "github", "junit"],
  "listReporters": ["spec", "sexp", "json", "jsonl"],
  "capabilities": ["describe-it-dsl"],
  "environment": ["CL_WEAVE_REPORTER"],
  "vitestAliases": [{"alias": "it.each", "canonical": "it-each"}],
  "packageExports": [{"name": "cl-weave", "exports": ["describe", "expect", "it"]}],
  "matchers": [{"name": "to-be", "description": null}],
  "mutationOperators": [{"name": "arithmetic-operator", "description": "..."}]
}
```

`--reporter sexp` prints the same data as a Lisp plist. `--reporter spec` is
accepted as the default CLI reporter and normalized to JSON for this command.
`packageExports` lists public external symbols by package in lower-case CL reader
spelling so agents can discover the supported DSL and runtime API without
scraping `package.lisp`.

## DSL Alias Contract

Vitest-shaped aliases are source-level macros only. Agents may normalize them
to the canonical hyphenated forms when reasoning about test plans:

- `describe.each` -> `describe-each`
- `describe.only` -> `describe-only`
- `describe.only.each` -> `describe-only-each`
- `describe.concurrent` -> `describe-concurrent`
- `describe.concurrent.each` -> `describe-concurrent-each`
- `describe.sequential` -> `describe-sequential`
- `describe.sequential.each` -> `describe-sequential-each`
- `describe.run-if` -> `describe-run-if`
- `describe.skip` / `describe.skip-if` / `describe.todo` -> canonical skip and todo suite macros
- `describe.skip.each` -> `describe-skip-each`
- `describe.todo.each` -> `describe-todo-each`
- `it.each` -> `it-each`
- `it.concurrent` -> `it-concurrent`
- `it.concurrent.each` -> `it-concurrent-each`
- `it.sequential` -> `it-sequential`
- `it.sequential.each` -> `it-sequential-each`
- `it.isolated` -> `it-isolated`
- `it.property` -> `it-property`
- `it.fails` -> `it-fails`
- `it.fails.each` -> `it-fails-each`
- `it.only` -> `it-only`
- `it.only.each` -> `it-only-each`
- `it.run-if` -> `it-run-if`
- `it.skip` / `it.skip-if` / `it.todo` -> canonical skip and todo macros
- `it.skip.each` -> `it-skip-each`
- `it.todo.each` -> `it-todo-each`
- `test` -> `it`
- `test.each` -> `test-each`
- `test.concurrent` -> `test-concurrent`
- `test.concurrent.each` -> `test-concurrent-each`
- `test.sequential` -> `test-sequential`
- `test.sequential.each` -> `test-sequential-each`
- `test.isolated` -> `test-isolated`
- `test.property` -> `test-property`
- `test.fails` -> `test-fails`
- `test.fails.each` -> `test-fails-each`
- `test.only` -> `test-only`
- `test.only.each` -> `test-only-each`
- `test.run-if` -> `test-run-if`
- `test.skip` / `test.skip-if` / `test.todo` -> canonical skip and todo macros
- `test.skip.each` -> `test-skip-each`
- `test.todo.each` -> `test-todo-each`
- `expect.assertions` -> `expect-assertions`
- `expect.hasassertions` -> `expect-has-assertions`
- `expect.not` -> `expect-not`
- `expect.extend` -> `expect-extend`
- `expect.resolves` -> `expect-resolves`
- `expect.rejects` -> `expect-rejects`
Fixture hooks are exported as canonical Lisp forms: `before-all`, `after-all`,
`before-each`, `around-each`, and `after-each`. Dotted Vitest-shaped aliases use
Common Lisp's actual unescaped reader spelling: JavaScript camelCase names are
lower-case in source, package exports, and metadata.

## S-Expression Reporter

```lisp
(cl-weave:run-all :reporter :sexp)
```

The reporter prints one form:

```lisp
(:cl-weave/results
 :schema-version 3
 :passed 1
 :skipped 0
 :todos 0
 :failed 0
 :errored 0
 :events
 ((:status :pass
   :path ("suite" "case")
   :path-string "suite > case"
   :location (:file "tests/example.lisp")
   :seconds 0
   :duration-ms 0
   :condition nil
   :reason nil
   :assertion nil)))
```

For assertion failures, `:assertion` contains:

```lisp
(:form (expect actual :to-be expected)
 :matcher :to-be
 :actual actual-value
 :expected (expected-value)
 :negated nil
 :pass nil)
```

Custom matchers registered with `cl-weave:defmatcher`,
`cl-weave:expect.extend`, or `cl-weave:extend-expect` use the same assertion
payload. The matcher keyword is stored in `:matcher`; the optional second and
third return values become `:actual` and `:expected`, which lets AI agents read
domain-specific failure data without parsing human messages.

Custom matcher definitions may attach a human-readable description as data.
`defmatcher` and `expect.extend` read a leading string in the body.
`extend-expect` accepts either a trailing string or `:description string`.
Agents can inspect the registry without macroexpanding test files:

```lisp
(cl-weave:list-matchers)
;; => ((:name :to-be :description nil)
;;     (:name :to-have-status
;;      :description "Checks that a response plist has the expected HTTP status."))

(cl-weave:matcher-metadata :to-have-status)
;; => (:name :to-have-status
;;     :description "Checks that a response plist has the expected HTTP status.")
```

`extend-expect` accepts a list of matcher specs. Each spec starts with a symbol
name and a two-argument function:

```lisp
((:to-have-status #<function>))
```

The function receives `(actual expected-operands)` and should return:

```lisp
(values pass-p reported-actual reported-expected)
```

`:to-throw` accepts no expected value, a condition class designator, a message
substring, or a predicate function. Failure payloads use:

```lisp
(:actual (:threw t
          :condition-type simple-error
          :message "missing user")
 :expected (:matcher :message-substring
            :value "needle"))
```

Mock function matchers report call and result histories in `:actual`:

```lisp
(:call-count 1
 :calls ((1 2))
 :result-count 1
 :results ((:type :return :value 3 :values (3)))
 :return-count 1
 :throw-count 0)
```

Thrown mock calls use `(:type :throw :condition-type simple-error :message "...")`.
`vi.fn` is a Vitest-shaped alias for `make-mock-function`; both constructors
produce the same mock function contract and result history shape.
`mock-function-p`, `vi.ismockfunction`, and `vi.mocked` return true only for
registered cl-weave mock functions and return false, not an error, for other
values.
`mock-implementation` and `vi.mockimplementation` mutate the implementation of
an existing mock and return that mock. `mock-return-value` /
`vi.mockreturnvalue` and `mock-return-values` / `vi.mockreturnvalues` are
constant return setters for single and Common Lisp multiple values.
`clear-mock` and `vi.mockclear` clear one registered mock history while
preserving its implementation.
`clear-all-mocks` and `vi.clearallmocks` clear every registered mock history
while preserving mock implementations.
`reset-mock` and `vi.mockreset` clear one mock history and replace its
implementation with the default no-op function. `reset-all-mocks` and
`vi.resetallmocks` apply that reset behavior to every registered mock.
`spy-on` and `vi.spyon` replace a symbol function cell with a registered mock
whose default implementation calls the original function. `mock-restore` /
`vi.mockrestore` restore the function cell only when it is still bound to that
spy, clear the spy history, and restore the spy implementation to the original
function. `restore-all-mocks` and `vi.restoreallmocks` restore active spies
without resetting regular `vi.fn` mocks.
Return-value matchers compare their operands with the recorded Common Lisp
multiple values list. Ordered mock matchers use one-based indices:
`:to-have-been-nth-called-with` reports `(:index n :arguments (...))`, and
`:to-have-nth-returned-with` reports `(:index n :values (...))`. Nth returned
assertions count only successful `:return` results; thrown results remain in
`:results` but do not consume a returned index.

Smart assertions use the same shape. For predicate forms such as
`(expect (= (+ 1 1) 3))`, the matcher is the predicate symbol and `:actual`
contains operand reports:

```lisp
(:form (expect (= (+ 1 1) 3))
 :matcher =
 :actual ((:form (+ 1 1) :value 2)
          (:form 3 :value 3))
 :expected (= (+ 1 1) 3)
 :negated nil
 :pass nil)
```

## JSON Reporter

```lisp
(cl-weave:run-all :reporter :json)
```

The reporter prints one JSON object:

```json
{
  "schemaVersion": 4,
  "kind": "test-results",
  "passed": 1,
  "skipped": 0,
  "todos": 0,
  "failed": 0,
  "errored": 0,
  "failedPaths": [],
  "erroredPaths": [],
  "events": [
    {
      "status": "pass",
      "path": ["suite", "case"],
      "pathString": "suite > case",
      "location": {"file": "tests/example.lisp"},
      "seconds": 0.0,
      "durationMs": 0.0,
      "condition": null,
      "reason": null,
      "assertion": null
    }
  ]
}
```

`location` is source metadata captured by the `it` family of macros. Portable
Common Lisp does not expose reliable source line numbers across implementations,
so the stable contract is the source file path only. JSON reporters emit
`null` when a test was constructed manually without location metadata.

The JSONL reporter is a streaming contract for CI logs and AI agents:

```lisp
(cl-weave:run-all :reporter :jsonl)
```

It prints one JSON object per line:

```jsonl
{"schemaVersion":1,"kind":"test-results-start","total":1}
{"schemaVersion":1,"kind":"test-event","event":{"status":"pass","path":["suite","case"],"pathString":"suite > case","location":{"file":"tests/example.lisp"},"seconds":0.0,"durationMs":0.0,"condition":null,"reason":null,"assertion":null}}
{"schemaVersion":1,"kind":"test-results-summary","passed":1,"skipped":0,"todos":0,"failed":0,"errored":0,"failedPaths":[],"erroredPaths":[]}
```

`test-event.event` uses the same object shape as JSON result `events` entries.
`test-results-summary` uses the same counts and rerun path summaries as the JSON
result root object. The alias `CL_WEAVE_REPORTER=ndjson` selects the same
reporter as `jsonl`.

For script-driven CI and agent runs, `scripts/run-tests.lisp` can write the
same reporter payload directly to an artifact file:

```sh
timeout 360s env CL_WEAVE_REPORTER=json CL_WEAVE_OUTPUT_FILE=cl-weave-results.json sbcl --noinform --non-interactive --load scripts/run-tests.lisp
```

`CL_WEAVE_OUTPUT_FILE` affects only reporter output. The process still exits
with `0` when all selected events pass, skip, or todo, and exits with `1` when
any selected event fails or errors. Empty selections exit with `0` by default;
set `CL_WEAVE_PASS_WITH_NO_TESTS=false`, pass `--fail-with-no-tests`, or call
`run-all` with `:pass-with-no-tests nil` when CI must reject a zero-test run.

External snapshots are sidecar artifacts controlled by dynamic bindings or
CLI/environment settings:

```sh
CL_WEAVE_UPDATE_SNAPSHOTS=1 CL_WEAVE_SNAPSHOT_DIR=tests/__snapshots__/ CL_WEAVE_SNAPSHOT_FILE=snapshots.sexp \
  timeout 360s sbcl --noinform --non-interactive --load scripts/run-tests.lisp
```

Snapshot files are Lisp-readable alists keyed by the explicit snapshot key
passed to `:to-match-snapshot`. They do not alter reporter schemas, so agents
can compare reporter artifacts and snapshot artifacts independently.

Snapshot assertion failures use the normal `:assertion` payload. For missing
snapshots, `:actual` and `:expected` contain `:snapshot-key`, `:snapshot-file`,
`:value`, `:reason :missing-snapshot`, and `:present nil` on the expected side.
For mismatches, both sides include `:reason :snapshot-mismatch` and matching
`:difference` data:

```lisp
(:matcher :to-match-snapshot
 :actual (:snapshot-key "suite/case"
          :snapshot-file "tests/__snapshots__/snapshots.sexp"
          :value "(:ok 43)"
          :reason :snapshot-mismatch
          :difference (:line 1 :expected "(:ok 42)" :actual "(:ok 43)"))
 :expected (:snapshot-key "suite/case"
            :snapshot-file "tests/__snapshots__/snapshots.sexp"
            :value "(:ok 42)"
            :present t
            :reason :snapshot-mismatch
            :difference (:line 1 :expected "(:ok 42)" :actual "(:ok 43)")))
```

Coverage output is a separate artifact, not a reporter schema field:

```sh
timeout 360s env CL_WEAVE_COVERAGE=1 CL_WEAVE_COVERAGE_FILE=cl-weave.coverage sbcl --noinform --non-interactive --load scripts/run-tests.lisp
```

The coverage artifact is SBCL `sb-cover` state written with
`sb-cover:save-coverage-in-file`. Agents should treat it as a sidecar file and
continue to parse S-expression or JSON reporter output for test results.

## Mutation Reports

Mutation reports are explicit API output, not part of `run-all` reporter
payloads. Agents can call `run-mutations`, then serialize the resulting list
with `report-mutations-sexp` or `report-mutations-json`.

Mutation operators expose stable metadata separately from mutation results:

```lisp
(cl-weave:list-mutation-operators)
;; => ((:name :arithmetic-operator
;;      :description "Swaps arithmetic operator heads such as +, -, *, and /.")
;;     ...)

(cl-weave:mutation-operator-metadata :arithmetic-operator)
;; => (:name :arithmetic-operator
;;     :description "Swaps arithmetic operator heads such as +, -, *, and /.")
```

```lisp
(let ((results (cl-weave:run-mutations
                '(+ 1 1)
                (lambda (form mutation)
                  (declare (ignore mutation))
                  (= (eval form) 2)))))
  (cl-weave:report-mutations-sexp results *standard-output*)
  (cl-weave:report-mutations-json results *standard-output*))
```

The S-expression mutation schema is:

```lisp
(:cl-weave/mutations
 :schema-version 1
 :summary (:total 1 :killed 1 :survived 0 :errored 0 :score 1.0)
 :results
 ((:status :killed
   :condition nil
   :mutation (:id 1
              :operator :arithmetic-operator
              :path ()
              :original (+ 1 1)
              :replacement (- 1 1)
              :form (- 1 1)))))
```

The JSON mutation schema is:

```json
{
  "schemaVersion": 1,
  "kind": "mutations",
  "total": 1,
  "killed": 1,
  "survived": 0,
  "errored": 0,
  "score": 1.0,
  "results": [
    {
      "status": "killed",
      "condition": null,
      "mutation": {
        "id": 1,
        "operator": "ARITHMETIC-OPERATOR",
        "path": [],
        "original": "(+ 1 1)",
        "replacement": "(- 1 1)",
        "form": "(- 1 1)"
      }
    }
  ]
}
```

`status` is one of `killed`, `survived`, or `errored`. Assertion failures from
cl-weave expectations count as killed mutants. Other signaled errors are kept
as `errored` so agents can distinguish production-code kills from harness
faults.

## TAP Reporter

```lisp
(cl-weave:run-all :reporter :tap)
```

The TAP reporter emits TAP version 13 for line-oriented CI logs:

```tap
TAP version 13
1..2
ok 1 - math > adds
not ok 2 - math > subtracts
  ---
  status: "fail"
  condition: "Expected 1 to be 2"
  ...
```

Skipped and todo events use TAP directives:

```tap
ok 1 - parser > waits for fixture # SKIP fixture unavailable
ok 2 - parser > handles unicode # TODO pending implementation
```

TAP is intentionally a stream format. Agents that need stable field names,
path arrays, assertion payloads, and focused rerun metadata should use the
S-expression or JSON reporters.

## GitHub Actions Reporter

```lisp
(cl-weave:run-all :reporter :github)
```

The GitHub Actions reporter emits workflow command annotations for failed and
errored tests:

```text
::error file=tests/math.lisp::math > subtracts [fail]%0AExpected 1 to be 2
cl-weave: 1 passed, 0 skipped, 0 todo, 1 failed, 0 errored, 2 total
```

Only `:fail` and `:error` events become annotations. Passing, skipped, and todo
events are represented only in the summary line so CI logs stay actionable.
Annotation data uses GitHub workflow command escaping. `file` is emitted when
source location metadata is available; otherwise cl-weave emits an annotation
without a `file` property.

This reporter is a CI log affordance, not a structured artifact schema. Agents
that need stable fields should continue to use the S-expression or JSON
reporters.

For assertion failures, `assertion` contains:

```json
{
  "form": "(EXPECT ACTUAL :TO-BE EXPECTED)",
  "matcher": ":TO-BE",
  "actual": "ACTUAL-VALUE",
  "expected": "(EXPECTED-VALUE)",
  "negated": false,
  "pass": false
}
```

For smart assertions, `matcher`, `actual`, and `expected` are still printable
Lisp strings. A failing `(expect (= (+ 1 1) 3))` serializes the operand report
through the `actual` field, so agents can read the exact evaluated values
without scraping the human spec reporter.

Assertion count declarations are per test attempt. They are reset for retries
and concurrent tests, and the declaration forms do not increment the assertion
counter. A failing exact count check uses:

```lisp
(:form (expect-assertions 2)
 :matcher :assertions
 :actual 1
 :expected 2
 :negated nil
 :pass nil)
```

A failing "at least one assertion" check uses:

```lisp
(:form (expect-has-assertions)
 :matcher :has-assertions
 :actual 0
 :expected (:minimum 1)
 :negated nil
 :pass nil)
```

`path` is the canonical machine path. `pathString` is the same path rendered in
the Vitest-style human format used by filtering. `seconds` is retained for
JUnit parity; `durationMs` is the preferred field for dashboards and agents.
`failedPaths` and `erroredPaths` contain `pathString` values that can be passed
back through `CL_WEAVE_TEST_FILTER` for focused CI or agent reruns.

Performance and allocation matchers report measured values instead of the input
thunk when they fail. For example, a failing `:to-run-under-ms` assertion uses:

```lisp
(:actual (:elapsed-seconds 0.001d0
          :elapsed-ms 1.0d0
          :bytes-consed 0
          :values (:ok))
 :expected (:max-ms 0))
```

`:to-cons-less-than` uses the same `:actual` shape and reports
`(:max-bytes n)` as `:expected`. JSON reporters stringify these Lisp payloads in
the existing `actual` and `expected` fields so agents can parse the measurement
without scraping human-oriented output.

Negated matcher assertions use either explicit matcher syntax or Vitest-style
DSL sugar:

```lisp
(expect value :not :to-be expected)
(expect-not value :to-be expected)
```

Both forms run through the same assertion engine. Failing negated assertions
set `:negated t` in the assertion detail and preserve the raw matcher result in
`:pass`, so agents can tell that the matcher itself succeeded but the negated
expectation failed.

Vitest-style resolving and rejecting assertions use Lisp thunks instead of
JavaScript promises:

```lisp
(expect.resolves (lambda () (fetch-account)) :to-satisfy #'account-ready-p)
(expect.rejects (lambda () (error "missing user")) :to-be-type-of 'simple-error)
```

`expect.resolves` applies the matcher to the thunk's primary value. If the
thunk signals a condition first, the assertion detail uses:

```lisp
(:matcher :resolves
 :actual (:state :rejected
          :condition-type simple-error
          :message "missing user")
 :expected (:state :resolved))
```

`expect.rejects` applies the matcher to the condition object. If the thunk
returns normally, the assertion detail uses:

```lisp
(:matcher :rejects
 :actual (:state :resolved :value :ok)
 :expected (:state :rejected))
```

String pattern matchers report normalized pattern semantics. A failing
`:to-match` assertion uses:

```lisp
(:actual (:value "common-lisp"
          :pattern "scheme"
          :mode :substring
          :reason :no-match)
 :expected (:pattern "scheme"
            :test :substring))
```

String patterns use substring search. Function designators use
`:mode :predicate` and pass when the predicate returns a non-`nil` value.
Failure reasons are `:not-a-string`, `:no-match`, `:predicate-false`,
`:predicate-error`, and `:invalid-pattern`.

NaN matchers report both type information and predicate results. A failing
`:to-be-nan` assertion uses:

```lisp
(:actual (:value 42
          :type integer
          :float nil
          :nan nil)
 :expected (:predicate :nan
            :test :float-nan-p))
```

`:to-be-nan` accepts no expected operands and passes only when the actual value
is a floating-point NaN.

Strict membership matchers report the candidate collection and match position.
A failing `:to-be-one-of` assertion uses:

```lisp
(:actual (:value :blocked
          :candidates (:pending :ready :done)
          :test eql
          :candidate-count 3
          :matched-index nil)
 :expected (:candidates (:pending :ready :done)
            :test eql
            :candidate-count 3))
```

`:to-be-one-of` accepts one list, vector, or hash table of candidates and uses
`eql`, matching the strict identity semantics of `:to-be`. Hash tables are
searched by value, not by key.

Deep containment matchers report the searched container and equality predicate.
A failing `:to-contain-equal` assertion uses:

```lisp
(:actual (:container ((:id 1 :name "Ada"))
          :value (:id 2 :name "Grace")
          :test :equalp)
 :expected (:value (:id 2 :name "Grace")
            :test :equalp))
```

The matcher searches sequence elements and hash-table values with `equalp`.
Use `:to-contain` for substring checks and shallow `equal` membership; use
`:to-contain-equal` when nested Lisp data should compare structurally.

Partial object matchers report the original value, requested subset, and the
first divergent path. A failing `:to-match-object` assertion uses:

```lisp
(:actual (:value (:user (:name "Ada"))
          :subset (:user (:name "Grace"))
          :failure (:path (:user :name)
                    :reason :value-mismatch
                    :actual-value "Ada"
                    :expected-value "Grace"
                    :test :equalp))
 :expected (:subset (:user (:name "Grace"))
            :test :partial-equalp))
```

The subset can be a property list, association list, or hash table. Actual
objects can be property lists, association lists, hash tables, or CLOS objects
with matching slot names. Expected vectors are matched against actual sequences
with exact length and order. Failure reasons are `:missing-property`,
`:value-mismatch`, `:length-mismatch`, and `:type-mismatch`.

Property matchers report normalized path traversal data. A failing
`:to-have-property` assertion uses:

```lisp
(:actual (:path (:user :age)
          :present nil
          :value nil)
 :expected (:path (:user :age)
            :value 37))
```

When the path exists but the optional expected value differs, `:present` is true
and `:value` contains the value found at that path. Paths are always reported as
lists, even when the caller used a scalar or vector path.

Close numeric matchers report the comparison tolerance as data. A failing
`:to-be-close-to` assertion uses:

```lisp
(:actual (:value 31/100
          :expected-value 3/10
          :num-digits 2
          :difference 1/100
          :threshold 1/200)
 :expected (:value 3/10
            :num-digits 2
            :threshold 1/200))
```

Ordering matchers report the operator and real-number classification. A failing
`:to-be-greater-than` assertion for a non-real actual value uses:

```lisp
(:actual (:value "10"
          :expected-value 9
          :matcher :to-be-greater-than
          :operator >
          :actual-real nil
          :expected-real t)
 :expected (:value 9
            :matcher :to-be-greater-than
            :operator >))
```

The same payload shape applies to `:to-be-greater-than-or-equal`,
`:to-be-less-than`, and `:to-be-less-than-or-equal`.

MOP architecture matchers report normalized architecture data instead of the raw
input designator. A failing `:to-have-slot` assertion uses:

```lisp
(:actual (:class widget
          :slots (name state))
 :expected (:slot missing-slot))
```

A failing `:to-have-method-specialized-on` assertion uses:

```lisp
(:actual (:methods ((widget stream)
                    (widget t)))
 :expected (:specializers (missing t)))
```

Specializers are printed as class names; EQL specializers are printed as
`(eql value)`.

## Test Selection

Agents can narrow execution without changing source files:

```lisp
(cl-weave:run-all :reporter :json :name-filter "suite > case")
```

`name-filter` is a case-insensitive substring matched against the human path
format `suite > nested suite > case`. The command runner exposes the same
contract through `CL_WEAVE_TEST_FILTER`.

CLI flags use canonical kebab-case names and expose Vitest-shaped aliases for
agent-generated commands: `--testNamePattern` maps to `--filter`,
`--outputFile` maps to `--output`, `--watchInterval` maps to
`--watch-interval`, `--coverageOutput` maps to `--coverage-output`,
`--testTimeout` and `--testTimeoutMs` map to `--test-timeout-ms`,
`--passWithNoTests` maps to `--pass-with-no-tests`, `--failWithNoTests` maps
to `--fail-with-no-tests`, `--snapshotDir` maps to `--snapshot-dir`,
`--snapshotFile` maps to `--snapshot-file`, and both `--update` and
`--updateSnapshots` map to `--update-snapshots`.

Filtering changes which events are emitted; it does not change the event shape
or reporter schema versions. If no test matches, reporters emit zero events and
the run is considered successful by default because no selected test failed.
Set `:pass-with-no-tests nil` or use the CLI/environment equivalent to make an
empty selection fail while keeping reporter payloads empty.

Suite-level `describe-skip`, `describe-skip-each`, `describe-todo`, and
`describe-todo-each` compose with the same selection rules. Selected descendant
cases are emitted as ordinary `:skip` or `:todo` events with the suite reason in
`:reason`; suite hooks and test bodies are not executed while the suite is
suppressed.

Conditional registration macros keep the same reporter contract.
`it-skip-if`, `test-skip-if`, and `describe-skip-if` emit ordinary `:skip`
events when their condition is true. `it-run-if`, `test-run-if`, and
`describe-run-if` emit ordinary `:skip` events when their condition is false.
The deterministic reasons are `"conditional skip"` and `"conditional run-if"`.
Conditions are evaluated while the test file registers tests; reporters do not
add a new event field or schema version for conditional registration.

## Sharding Contract

Agents can partition selected tests for CI without changing source files:

```lisp
(cl-weave:run-all :reporter :json :name-filter "suite" :shard '(1 3))
(cl-weave:list-tests :reporter :json :shard '(2 3))
```

The command runner exposes the same contract through `CL_WEAVE_SHARD=INDEX/COUNT`.
Indexes are one-based and must satisfy `1 <= INDEX <= COUNT`.

Sharding is applied after focus and `name-filter`. The runner assigns a stable
discovery ordinal to each selected test and keeps only the ordinals that belong
to the requested shard. Reporter schemas are unchanged. If a shard selects no
tests, reporters emit zero events and the run is considered successful.

Suites with no descendants in the requested shard do not run `before-all` or
`after-all`, which keeps unrelated fixture side effects out of parallel CI jobs.

## Sequence Order Contract

Agents can reproduce order-dependent failures without changing source files:

```lisp
(cl-weave:run-all :reporter :json :order :random :seed 12345)
(cl-weave:list-tests :reporter :json :order :random :seed 12345)
```

The command runner exposes the same contract through
`CL_WEAVE_SEQUENCE=random` and `CL_WEAVE_SEQUENCE_SEED=N`. Accepted order values
are `defined`, `random`, and `shuffle`; `shuffle` is an alias for `random`.
`:defined` is the default. When `CL_WEAVE_SEQUENCE_SEED` is explicitly set, it
must be a positive integer so failed CI runs can be reproduced from logs without
ambiguous seed parsing.

Ordering is applied after focus, `name-filter`, and shard selection. Shard
membership remains stable across seeds. Ordering is local to each suite so
`before-all`, `after-all`, `before-each`, `around-each`, and `after-each`
boundaries are preserved. Reporter schemas are unchanged. The same seed and
same test tree produce the same execution and list-mode order across SBCL
processes.

## Fixture Continuation Contract

`around-each` registers a single-argument hook. The argument is the continuation
for the remaining `around-each` hooks and the test body. `before-each` hooks run
before `around-each`; `after-each` hooks run after the continuation returns or
unwinds. Around hooks compose from outer suites to inner suites. Use
`unwind-protect` inside an around hook for deterministic cleanup. Reporter
schemas are unchanged.

## CPS Continuation Helper Contract

`with-continuation-result` and `with-continuation-values` bind the continuation
symbol supplied in the binding list while evaluating their form. The tested CPS
API should call that local function, usually as `#'next`.

```lisp
(with-continuation-result (value next calledp)
    (compute-cps input #'next)
  (expect calledp :to-be-truthy)
  (expect value :to-equal expected))
```

`with-continuation-result` binds the first value passed to the continuation.
`with-continuation-values` binds the complete value list. The optional third
binding receives whether the continuation was called. If the continuation is not
called, cl-weave signals `assertion-failure` with matcher
`:continuation-called`, actual `(:called nil)`, and expected `(:called t)`.

## Test Plan Contract

Agents can discover selected tests without executing hooks or test bodies:

```lisp
(cl-weave:list-tests :reporter :json :name-filter "parser")
(cl-weave:collect-test-plan (cl-weave::root-suite) :name-filter "parser")
```

The command runner exposes the same discovery mode through `CL_WEAVE_LIST=1`:

```sh
timeout 120s env CL_WEAVE_LIST=1 CL_WEAVE_REPORTER=json CL_WEAVE_TEST_FILTER='parser' CL_WEAVE_SHARD=1/2 CL_WEAVE_SEQUENCE=random CL_WEAVE_SEQUENCE_SEED=12345 sbcl --noinform --non-interactive --load scripts/run-tests.lisp
```

The JSON test plan reporter prints one object:

```json
{
  "schemaVersion": 2,
  "kind": "test-plan",
  "total": 1,
  "runnable": 1,
  "skipped": 0,
  "todos": 0,
  "tests": [
    {
      "status": "run",
      "path": ["suite", "case"],
      "pathString": "suite > case",
      "location": {"file": "tests/example.lisp"},
      "reason": null,
      "focused": false,
      "retry": 0,
      "timeoutMs": null,
      "concurrent": false
    }
  ]
}
```

The S-expression test plan reporter uses the same data:

```lisp
(:cl-weave/test-plan
 :schema-version 2
 :total 1
 :runnable 1
 :skipped 0
 :todos 0
 :tests
 ((:status :run
   :path ("suite" "case")
   :path-string "suite > case"
   :location (:file "tests/example.lisp")
   :reason nil
   :focused nil
   :retry 0
   :timeout-ms nil
   :concurrent nil)))
```

Plan `status` is `:run`, `:skip`, or `:todo`; JSON uses `run`, `skip`, or
`todo`. Focus and `CL_WEAVE_TEST_FILTER` narrow discovery with the same rules as
execution. Suite-level skip and todo suppression produces selected descendant
plan entries without running suite hooks or case bodies. `pathString` can be
fed back to `CL_WEAVE_TEST_FILTER` for focused execution after discovery.

The JSONL test plan reporter uses the same entry shape as JSON test plan
`tests` entries:

```jsonl
{"schemaVersion":1,"kind":"test-plan-start","total":1}
{"schemaVersion":1,"kind":"test-plan-entry","test":{"status":"run","path":["suite","case"],"pathString":"suite > case","location":{"file":"tests/example.lisp"},"reason":null,"focused":false,"retry":0,"timeoutMs":null,"concurrent":false}}
{"schemaVersion":1,"kind":"test-plan-summary","total":1,"runnable":1,"skipped":0,"todos":0}
```

List mode supports `spec`, `sexp`, `json`, and `jsonl` reporters. It exits with status
`0` after writing the plan, including when no tests match.

Agents that need symbolic selection can avoid parsing reporter output and use
the Lisp-native logic layer:

```lisp
(cl-weave:test-plan-facts (cl-weave:collect-test-plan (cl-weave::root-suite)))
;; => ((:test ("suite" "case"))
;;     (:status ("suite" "case") :run)
;;     (:retry ("suite" "case") 0)
;;     ...)

(cl-weave:test-plan-where
 (cl-weave:collect-test-plan (cl-weave::root-suite))
 (:status ?test :run)
 (:focused ?test))
;; => (((?test . ("suite" "case"))))
```

Logic variables are symbols whose names start with `?`. Facts and clauses are
plain lists, matched left-to-right by `logic-query`. `logic-where` and
`test-plan-where` are macro syntax over that data contract; use `(:limit n)` as
the first form to cap backtracking results. The stable public relation names are
`:test`, `:status`, `:reason`, `:focused`, `:retry`, `:timeout-ms`,
`:concurrent`, and `:location`.

## Bail Contract

Agents can stop after the first failure or after a fixed number of failing
events:

```lisp
(cl-weave:run-all :reporter :json :bail t)
(cl-weave:run-all :reporter :json :bail 2)
```

The command runner exposes the same control through `CL_WEAVE_BAIL`. Accepted
values are `true`, `yes`, `on`, `t`, `false`, `no`, `off`, `0`, `nil`, or a
positive integer. Other boolean environment variables use the same false tokens:
`0`, `false`, `no`, `off`, and `nil`.

Bail counts only emitted `:fail` and `:error` events. `:pass`, `:skip`, and
`:todo` events do not advance the counter. When the limit is reached, reporters
emit only the selected events that were executed before the runner stopped.
The event shape, summary fields, `schemaVersion`, `path`, `pathString`, and
`location` contracts are unchanged.

## Retry And Timeout Contract

Case options are passed as a keyword plist immediately after the case name:

```lisp
(it "eventually stable" (:retry 2 :timeout-ms 500)
  (expect (probe) :to-be :ready))

(it-concurrent "parallel-safe case" (:timeout-ms 500)
  (expect (probe-independent-service) :to-be :ready))

(describe.concurrent "parallel-safe suite"
  (it "inherits concurrent mode"
    (expect (probe-independent-service) :to-be :ready))
  (it.sequential "uses shared state"
    (expect (probe-shared-state) :to-be :ready)))
```

`:retry` is the number of extra attempts after the first attempt. Retries apply
only to `:fail` and `:error` attempt events. The runner emits only the final
event, so reporter schemas do not expose intermediate attempts.

Command runners can set a global retry default with `--retry N` or
`CL_WEAVE_RETRY=N`. Local `:retry` wins over the global default, including
`:retry 0` for one-shot cases inside a globally retried suite.

`:timeout-ms` is a per-attempt wall-clock budget. When an attempt times out, the
final event status is `:fail`, `:condition` prints a `test-timeout`, and
`:assertion` is `nil`. Fixture hooks are still executed through the same
`before-each` / `around-each` / `after-each` contract as ordinary test attempts.

Command runners can set a global timeout default with `--test-timeout-ms N`,
`--test-timeout N`, `--testTimeout N`, `--testTimeoutMs N`,
`CL_WEAVE_TEST_TIMEOUT_MS=N`, or `CL_WEAVE_TEST_TIMEOUT=N`. Local
`:timeout-ms` wins over the global default. List mode and structured test-plan
reporters expose the effective retry and timeout values after applying these
defaults.

`:concurrent t`, `it-concurrent`, and `test-concurrent` mark a case as safe for
parallel execution with adjacent concurrent cases. `describe-concurrent` /
`describe.concurrent` applies the same mode to descendants, while
`it-sequential`, `test-sequential`, and the dot aliases opt individual cases out.
Reporter schemas continue to expose the effective mode as the stable
`concurrent` boolean. Event arrays and test-plan arrays remain in selected
definition order. `:bail` disables concurrent batching to keep fast-fail
semantics exact.

## Expected Failure Contract

`it-fails` and `test-fails` register ordinary runnable cases with the same
option plist as `it`.

```lisp
(it-fails "documents a known parser bug" (:retry 1 :timeout-ms 500)
  (expect (parse-fragment input) :to-be :accepted))
```

Reporter schemas are unchanged. A raw assertion failure, error, or timeout
becomes final status `:pass`. A raw normal completion becomes final status
`:fail` with an `expected-failure-missed` condition. `:reason` remains reserved
for skip and todo events; expected-failure metadata is not emitted as an event
reason.

Retry observes transformed attempt events. This means an unexpectedly passing
expected-failure case is retryable as `:fail`, while the first raw failure or
error becomes `:pass` and stops retrying.

## Interactive Restart Contract

Each runnable attempt exposes three Common Lisp restarts while fixtures, the
test body, and timeout boundary are active:

- `continue-test` returns a normal `:pass` event for the current attempt.
- `skip-test` returns a normal `:skip` event and accepts an optional reason.
- `retry-test` reruns the attempt without decrementing the configured `:retry`
  count.

Reporter schemas are unchanged. The final event is still one of the ordinary
event statuses, and no intermediate retry or restart metadata is emitted. If no
handler or debugger invokes a restart, failures, errors, and timeouts keep the
same CI behavior described above.

## Table-Driven Macro Expansion

`it-each`, `test-each`, and `describe-each` are compile-time expansion helpers,
not runtime loop constructs.

```lisp
(it-each ((1 2 3)
          (13 21 34))
    "adds ~A and ~A"
    (left right total)
  (expect (+ left right) :to-be total))
```

`it-each` and `test-each` emit independent `it` registrations. `describe-each`
emits independent `describe` registrations, and the generated suite bodies use
the same fixture, assertion, filtering, and reporter contracts as hand-written
suites.

Reporters do not expose table metadata. Agents should treat expanded table cases
as ordinary events whose identity is the formatted path emitted by the runner.

## ASDF Runner Contract

Agents can discover declared source files before choosing a focused run:

```lisp
(cl-weave:asdf-system-files "my-project-tests" :include-dependencies t)
```

`run-system` and `watch-system` preserve reporter contracts because both call
`run-all` after ASDF loading:

```lisp
(cl-weave:run-system "my-project-tests" :reporter :json :name-filter "parser" :shard '(1 2) :order :random :seed 12345 :bail 1)
(cl-weave:watch-system "my-project-tests" :reporter :json :shard '(1 2) :order :random :seed 12345 :bail 1 :once t)
```

`watch-system` writes status lines to `:status-stream`, which defaults to
`*error-output*`, and writes reporter payloads to `:stream`. CI should keep
`CL_WEAVE_WATCH` unset; watch mode is for local agents and REPL sessions.

## Property Failure Contract

`it-property` failures are normal assertion failures with matcher `:property`.
The assertion payload keeps the original generated values and the minimized
values in `:actual`, plus the deterministic seed and zero-based generated case
index needed for focused reproduction:

```lisp
(:actual (:seed 12345
          :case-index 7
          :values (17 (:open 2))
          :minimal (1 (:open 1))
          :condition "Assertion failed ...")
 :expected (value command))
```

Generator combinators do not create new event types. `src/property.lisp` owns
generator data, value production, shrinking, and property execution;
`src/dsl.lisp` only expands `it-property` into that runner. `gen-map`,
`gen-one-of`, `gen-recursive`, `gen-tuple`, and `gen-such-that` only affect
generated values and shrink candidates before the same `assertion-failure`
payload is reported. `gen-symbol`, `gen-keyword`, `gen-sexp`, and `gen-form`
are convenience generators for Lisp-native property tests and macro-expansion
inputs.

Property CI controls are strict. `CL_WEAVE_PROPERTY_TESTS` must parse as a
positive integer, and `CL_WEAVE_PROPERTY_SEED` must parse as an integer. Invalid
values are cl-weave errors, not implementation-level parser errors, so agents
can treat them as configuration failures.

## Isolated Process Contract

`it-isolated` expands to a normal `it` case that calls `run-isolated` and then
asserts the returned `isolated-result` succeeded. The child process loads the
declared ASDF systems before evaluating the body.

```lisp
(it-isolated "native boundary"
    (:systems ("my-project-tests") :timeout 5)
  (expect (call-native) :to-be :ok))
```

`run-isolated` returns an `isolated-result` with:

```lisp
(:status :pass-or-fail-or-timeout
 :exit-code 0
 :stdout "..."
 :stderr "..."
 :timed-out-p nil
 :elapsed-ms 12
 :script-path "/tmp/cl-weave-isolated-....lisp")
```

When `it-isolated` fails, the assertion matcher is `:isolated` and the payload
keeps the child process diagnostics:

```lisp
(:actual (:status :timeout
          :exit-code nil
          :timed-out-p t
          :elapsed-ms 100
          :stdout ""
          :stderr ""
          :script-path "/tmp/cl-weave-isolated-....lisp")
 :expected (:status :pass :exit-code 0))
```

This is intended for FFI and crash-boundary tests where agents must preserve
the parent runner while still receiving parseable failure data.

## Stability

- `:schema-version` and `schemaVersion` change only when the shape changes.
- JSON result artifacts use `kind: "test-results"` so agents can classify
  artifacts without filename or command context.
- `:path` is a list of suite names followed by the case name.
- `:status` is one of `:pass`, `:skip`, `:todo`, `:fail`, or `:error`; JSON
  uses the corresponding lowercase strings.
- `:condition` is a printable string or `nil`; JSON uses a string or `null`.
- `:reason` is a skip or todo reason string for `:skip` and `:todo` events,
  otherwise `nil`; JSON uses a string or `null`.
- `:assertion` is `nil` unless the failure came from `expect`; JSON uses an
  object or `null`.
- JSON `form`, `matcher`, `actual`, and `expected` fields are printable Lisp
  strings.
