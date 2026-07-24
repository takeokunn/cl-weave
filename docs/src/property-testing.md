# Property Testing

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

## Built-In Generators

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
predicate. `gen-such-that` validates its arguments eagerly: `predicate` must be
a function and `attempts` must be a positive integer, so a misplaced value
(for example passing a symbol instead of `#'plusp`) signals a `cl-weave` error
at construction time rather than failing deep inside generation.

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
