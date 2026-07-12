# Mutation Testing

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
