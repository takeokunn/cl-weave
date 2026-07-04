# cl-weave AI Contract

`cl-weave` exposes structured test output as S-expressions so agents can parse
results without scraping human text.

## Reporter

```lisp
(cl-weave:run-all :reporter :sexp)
```

The reporter prints one form:

```lisp
(:cl-weave/results
 :schema-version 1
 :passed 1
 :failed 0
 :errored 0
 :events
 ((:status :pass
   :path ("suite" "case")
   :seconds 0
   :condition nil
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

## Stability

- `:schema-version` changes only when the shape changes.
- `:path` is a list of suite names followed by the case name.
- `:status` is one of `:pass`, `:fail`, or `:error`.
- `:condition` is a printable string or `nil`.
- `:assertion` is `nil` unless the failure came from `expect`.
