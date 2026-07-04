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
  "schemaVersion": 1,
  "passed": 1,
  "skipped": 0,
  "todos": 0,
  "failed": 0,
  "errored": 0,
  "events": [
    {
      "status": "pass",
      "path": ["suite", "case"],
      "seconds": 0.0,
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
