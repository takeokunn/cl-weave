# cl-weave AI Contract

`cl-weave` exposes structured test output as S-expressions and JSON so agents
can parse results without scraping human text.

## S-Expression Reporter

```lisp
(cl-weave:run-all :reporter :sexp)
```

The reporter prints one form:

```lisp
(:cl-weave/results
 :schema-version 2
 :passed 1
 :skipped 0
 :todos 0
 :failed 0
 :errored 0
 :events
 ((:status :pass
   :path ("suite" "case")
   :seconds 0
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
  "schemaVersion": 2,
  "passed": 1,
  "skipped": 0,
  "todos": 0,
  "failed": 0,
  "errored": 0,
  "events": [
    {
      "status": "pass",
      "path": ["suite", "case"],
      "pathString": "suite > case",
      "seconds": 0.0,
      "durationMs": 0.0,
      "condition": null,
      "reason": null,
      "assertion": null
    }
  ]
}
```

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

`path` is the canonical machine path. `pathString` is the same path rendered in
the Vitest-style human format used by filtering. `seconds` is retained for
JUnit parity; `durationMs` is the preferred field for dashboards and agents.

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

Filtering changes which events are emitted; it does not change the event shape
or reporter schema versions. If no test matches, reporters emit zero events and
the run is considered successful because no selected test failed.

Suite-level `describe-skip` and `describe-todo` compose with the same selection
rules. Selected descendant cases are emitted as ordinary `:skip` or `:todo`
events with the suite reason in `:reason`; suite hooks and test bodies are not
executed while the suite is suppressed.

## Retry And Timeout Contract

Case options are passed as a keyword plist immediately after the case name:

```lisp
(it "eventually stable" (:retry 2 :timeout-ms 500)
  (expect (probe) :to-be :ready))
```

`:retry` is the number of extra attempts after the first attempt. Retries apply
only to `:fail` and `:error` attempt events. The runner emits only the final
event, so reporter schemas do not expose intermediate attempts.

`:timeout-ms` is a per-attempt wall-clock budget. When an attempt times out, the
final event status is `:fail`, `:condition` prints a `test-timeout`, and
`:assertion` is `nil`. Fixture hooks are still executed through the same
`before-each` / `after-each` contract as ordinary test attempts.

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
(cl-weave:run-system "my-project-tests" :reporter :json :name-filter "parser")
(cl-weave:watch-system "my-project-tests" :reporter :json :once t)
```

`watch-system` writes status lines to `:status-stream`, which defaults to
`*error-output*`, and writes reporter payloads to `:stream`. CI should keep
`CL_WEAVE_WATCH` unset; watch mode is for local agents and REPL sessions.

## Property Failure Contract

`it-property` failures are normal assertion failures with matcher `:property`.
The assertion payload keeps the original generated values and the minimized
values in `:actual`:

```lisp
(:actual (:values (17 (:open 2))
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
