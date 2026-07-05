(in-package #:cl-weave/tests)

(describe "macros"
  (it-each ((1 2 3)
            (13 21 34))
      "adds ~A and ~A at macro expansion time"
      (left right total)
    (expect (+ left right) :to-be total))

  (test-each ((2 3 5)
              (5 8 13))
      "aliases test-each for ~A and ~A"
      (left right total)
    (expect (+ left right) :to-be total))

  (describe-each ((3 4 7)
                  (8 13 21))
      "table suite ~A plus ~A"
      (left right total)
    (before-each
      (setf (gethash :table-total *test-context*) total))
    (it "runs generated nested cases with fixtures"
      (expect (+ left right) :to-be total)
      (expect (gethash :table-total *test-context*) :to-be total)))

  (describe.each ((4 5 9))
      "dot table suite ~A plus ~A"
      (left right total)
    (before-each
      (setf (gethash :dot-table-total *test-context*) total))
    (it.each ((:alpha :alpha)
              (:beta :beta))
        "runs dot generated case ~A"
        (actual expected)
      (expect actual :to-be expected)
      (expect (+ left right) :to-be total)
      (expect (gethash :dot-table-total *test-context*) :to-be total)))

  (it "expands expect into the assertion engine"
    (expect (macroexpand-1 '(expect (+ 1 1) :to-be 2))
            :to-satisfy
            (lambda (form)
              (tree-contains-p form 'cl-weave::assert-expectation))))

  (it "expands expect-not into a negated matcher assertion"
    (expect (macroexpand-1 '(expect-not (+ 1 1) :to-be 3))
            :to-satisfy
            (lambda (form)
              (and (tree-contains-p form 'cl-weave::assert-expectation)
                   (tree-contains-p form :not)
                   (tree-contains-p form 'expect-not)))))

  (it "expands expect.resolves into canonical expect-resolves"
    (expect (macroexpand-1 '(expect.resolves (lambda () :ok) :to-be :ok))
            :to-satisfy
            (lambda (form)
              (tree-contains-p form 'expect-resolves))))

  (it "expands expect-resolves into resolving thunk evaluation"
    (expect (macroexpand-1 '(expect-resolves (lambda () :ok) :to-be :ok))
            :to-satisfy
            (lambda (form)
              (and (tree-contains-p form 'cl-weave::call-resolving-expectation-thunk)
                   (tree-contains-p form 'expect-resolves)))))

  (it "expands expect.rejects into canonical expect-rejects"
    (expect (macroexpand-1 '(expect.rejects (lambda () (error "boom")) :to-be-type-of 'simple-error))
            :to-satisfy
            (lambda (form)
              (tree-contains-p form 'expect-rejects))))

  (it "expands expect-rejects into rejecting thunk evaluation"
    (expect (macroexpand-1 '(expect-rejects (lambda () (error "boom")) :to-be-type-of 'simple-error))
            :to-satisfy
            (lambda (form)
              (and (tree-contains-p form 'cl-weave::call-rejecting-expectation-thunk)
                   (tree-contains-p form 'expect-rejects)))))

  (it "expands expect.extend into the custom matcher registry"
    (expect (macroexpand-1
             '(expect.extend
               (:to-be-small (actual expected)
                 (declare (ignore expected))
                 (< actual 10))))
            :to-satisfy
            (lambda (form)
              (and (tree-contains-p form 'expect-extend)
                   (tree-contains-p form :to-be-small)))))

  (it "expands smart expect into operand capture"
    (expect (macroexpand-1 '(expect (= (+ 1 1) 2)))
            :to-satisfy
            (lambda (form)
              (and (tree-contains-p form 'cl-weave::signal-smart-assertion-failure)
                   (tree-contains-p form 'cl-weave::operand-report-form)))))

  (it "expands with-continuation-result through the CPS value collector"
    (expect (macroexpand-1
             '(with-continuation-result (result next calledp)
                  (funcall producer #'next)
                (list result calledp)))
            :to-satisfy
            (lambda (form)
              (and (tree-contains-p form 'cl-weave:with-continuation-values)
                   (tree-contains-p form 'next)
                   (tree-contains-p form 'calledp)
                   (tree-contains-p form 'result)))))

  (it "expands with-continuation-values into a local continuation gate"
    (expect (macroexpand-1
             '(with-continuation-values (values next calledp)
                  (funcall producer #'next)
                values))
            :to-satisfy
            (lambda (form)
              (and (tree-contains-p form 'flet)
                   (tree-contains-p form 'next)
                   (tree-contains-p form 'cl-weave::ensure-continuation-called)
                   (tree-contains-p form 'calledp)
                   (tree-contains-p form 'values)))))

  (it "rejects non-symbol continuation bindings at macro expansion time"
    (expect (lambda ()
              (macroexpand
               '(with-continuation-result (result 42)
                    :not-called
                  result)))
            :to-throw))

  (it "expands it-only into focused test registration"
    (expect (macroexpand-1 '(it-only "focused" (expect 1 :to-be 1)))
            :to-satisfy
            (lambda (form)
              (and (tree-contains-p form 'cl-weave::register-test)
                   (tree-contains-p form :focus)))))

  (it "expands it options into retry and timeout metadata"
    (expect (macroexpand-1
             '(it "eventually stable" (:retry 2 :timeout-ms 100 :concurrent t)
                (expect :ok :to-be :ok)))
            :to-satisfy
            (lambda (form)
              (and (tree-contains-p form 'cl-weave::register-test)
                   (tree-contains-p form :retry)
                   (tree-contains-p form 2)
                   (tree-contains-p form :timeout-ms)
                   (tree-contains-p form 100)
                   (tree-contains-p form :execution-mode)
                   (tree-contains-p form :concurrent)))))

  (it "expands false concurrent option into sequential execution metadata"
    (expect (macroexpand-1
             '(it "generated sequential case" (:concurrent nil)
                (expect :ok :to-be :ok)))
            :to-satisfy
            (lambda (form)
              (and (tree-contains-p form 'cl-weave::register-test)
                   (tree-contains-p form :execution-mode)
                   (tree-contains-p form :sequential)))))

  (it "expands it-concurrent into concurrent test registration"
    (expect (macroexpand-1
             '(it-concurrent "parallel case" (:retry 1)
                (expect :ok :to-be :ok)))
            :to-satisfy
            (lambda (form)
              (and (tree-contains-p form 'cl-weave::register-test)
                   (tree-contains-p form :execution-mode)
                   (tree-contains-p form :concurrent)
                   (tree-contains-p form :retry)))))

  (it "expands it-sequential into sequential test registration"
    (expect (macroexpand-1
             '(it-sequential "serial case" (:retry 1)
                (expect :ok :to-be :ok)))
            :to-satisfy
            (lambda (form)
              (and (tree-contains-p form 'cl-weave::register-test)
                   (tree-contains-p form :execution-mode)
                   (tree-contains-p form :sequential)
                   (tree-contains-p form :retry)))))

  (it "expands it-fails into expected-failure registration"
    (expect (macroexpand-1
             '(it-fails "known bug" (:retry 1 :timeout-ms 100)
                (expect 1 :to-be 2)))
            :to-satisfy
            (lambda (form)
              (and (tree-contains-p form 'cl-weave::register-test)
                   (tree-contains-p form :expected-failure-reason)
                   (tree-contains-p form :retry)
                   (tree-contains-p form :timeout-ms)))))

  (it "expands describe-skip into skipped suite registration"
    (expect (macroexpand-1
             '(describe-skip "blocked" "upstream gap"
                (it "case" (expect 1 :to-be 1))))
            :to-satisfy
            (lambda (form)
              (and (tree-contains-p form 'cl-weave::register-suite)
                   (tree-contains-p form :skip-reason)
                   (tree-contains-p form "upstream gap")))))

  (it "expands describe-todo into todo suite registration"
    (expect (macroexpand-1
             '(describe-todo "pending" "needs design"
                (it "case" (expect 1 :to-be 1))))
            :to-satisfy
            (lambda (form)
              (and (tree-contains-p form 'cl-weave::register-suite)
                   (tree-contains-p form :todo-reason)
                   (tree-contains-p form "needs design")))))

  (it "expands describe execution mode macros into suite metadata"
    (expect (macroexpand-1
             '(describe-concurrent "parallel suite"
                (it "case" (expect 1 :to-be 1))))
            :to-satisfy
            (lambda (form)
              (and (tree-contains-p form 'cl-weave::register-suite)
                   (tree-contains-p form :execution-mode)
                   (tree-contains-p form :concurrent))))
    (expect (macroexpand-1
             '(describe-sequential "serial suite"
                (it "case" (expect 1 :to-be 1))))
            :to-satisfy
            (lambda (form)
              (and (tree-contains-p form 'cl-weave::register-suite)
                   (tree-contains-p form :execution-mode)
                   (tree-contains-p form :sequential)))))

  (it "expands conditional test registration into run and skip branches"
    (expect (macroexpand-1
             '(it-skip-if expensivep
                  "conditional case"
                (:retry 2 :timeout-ms 100)
                (expect :ok :to-be :ok)))
            :to-satisfy
            (lambda (form)
              (and (tree-contains-p form 'if)
                   (tree-contains-p form 'it-skip)
                   (tree-contains-p form 'it)
                   (tree-contains-p form :retry)
                   (tree-contains-p form :timeout-ms)))))

  (it "expands conditional suite registration into run and skip branches"
    (expect (macroexpand-1
             '(describe-run-if
                  (member :sbcl *features*)
                  "conditional suite"
                (it "case" (expect :ok :to-be :ok))))
            :to-satisfy
            (lambda (form)
              (and (tree-contains-p form 'if)
                   (tree-contains-p form 'describe)
                   (tree-contains-p form 'describe-skip)
                   (tree-contains-p form "conditional run-if")))))

  (it "expands describe-each into independent suites"
    (expect (macroexpand-1
             '(describe-each ((1 2 3))
                  "suite ~A"
                  (left right total)
                (it "adds" (expect (+ left right) :to-be total))))
            :to-satisfy
            (lambda (form)
              (and (tree-contains-p form 'cl-weave::describe)
                   (tree-contains-p form 'destructuring-bind)))))

  (it "expands test-each through the it-each macro"
    (expect (macroexpand-1
             '(test-each ((1 2 3))
                  "adds ~A and ~A"
                  (left right total)
                (expect (+ left right) :to-be total)))
            :to-satisfy
            (lambda (form)
              (tree-contains-p form 'cl-weave:it-each))))

  (test "runs the Vitest test alias as a first-class case"
    (expect (+ 2 2) :to-be 4))

  (it "expands Vitest dot aliases through canonical macros"
    (expect-macroexpands-through
     (test "base alias" (expect :ok :to-be :ok))
     cl-weave:it)
    (expect-macroexpands-through
     (it.concurrent "parallel alias" (expect :ok :to-be :ok))
     cl-weave:it-concurrent)
    (expect-macroexpands-through
     (it.each ((1 2 3))
         "adds ~A and ~A"
         (left right total)
       (expect (+ left right) :to-be total))
     cl-weave:it-each)
    (expect-macroexpands-through
     (it.only.each ((1 2 3))
         "focused ~A and ~A"
         (left right total)
       (expect (+ left right) :to-be total))
     cl-weave:it-only-each)
    (expect-macroexpands-through
     (it.concurrent.each ((1 2 3))
         "parallel ~A and ~A"
         (left right total)
       (expect (+ left right) :to-be total))
     cl-weave:it-concurrent-each)
    (expect-macroexpands-through
     (it.sequential.each ((1 2 3))
         "serial ~A and ~A"
         (left right total)
       (expect (+ left right) :to-be total))
     cl-weave:it-sequential-each)
    (expect-macroexpands-through
     (it.fails "expected failure alias" (expect :ok :to-be :not-ok))
     cl-weave:it-fails)
    (expect-macroexpands-through
     (it.fails.each ((1 2 4))
         "expected failure ~A and ~A"
         (left right total)
       (expect (+ left right) :to-be total))
     cl-weave:it-fails-each)
    (expect-macroexpands-through
     (it.only "focused alias" (expect :ok :to-be :ok))
     cl-weave:it-only)
    (expect-macroexpands-through
     (it.run-if t "conditional alias" (expect :ok :to-be :ok))
     cl-weave:it-run-if)
    (expect-macroexpands-through
     (it.runIf t "conditional camel alias" (expect :ok :to-be :ok))
     cl-weave:it-run-if)
    (expect-macroexpands-through
     (it.sequential "serial alias" (expect :ok :to-be :ok))
     cl-weave:it-sequential)
    (expect-macroexpands-through
     (it.skip "skipped alias" "because")
     cl-weave:it-skip)
    (expect-macroexpands-through
     (it.skip.each ((1 2 3))
         "skipped ~A and ~A"
         (left right total)
       "because"
       (expect (+ left right) :to-be total))
     cl-weave:it-skip-each)
    (expect-macroexpands-through
     (it.skip-if t "conditional skip alias" (expect :ok :to-be :ok))
     cl-weave:it-skip-if)
    (expect-macroexpands-through
     (it.skipIf t "conditional skip camel alias" (expect :ok :to-be :ok))
     cl-weave:it-skip-if)
    (expect-macroexpands-through
     (it.todo "todo alias" "later")
     cl-weave:it-todo)
    (expect-macroexpands-through
     (it.todo.each ((1 2 3))
         "todo ~A and ~A"
         (left right total)
       "later"
       (expect (+ left right) :to-be total))
     cl-weave:it-todo-each)
    (expect-macroexpands-through
     (it.isolated "isolated alias"
         (:systems ("cl-weave-tests") :timeout 5)
       (expect :ok :to-be :ok))
     cl-weave:it-isolated)
    (expect-macroexpands-through
     (it.property "property alias"
         ((value (gen-integer :min 0 :max 10)))
       (expect value :to-satisfy #'integerp))
     cl-weave:it-property)
    (expect-macroexpands-through
     (expect.assertions 1)
     cl-weave:expect-assertions)
    (expect-macroexpands-through
     (expect.hasassertions)
     cl-weave:expect-has-assertions)
    (expect-macroexpands-through
     (|expect.hasAssertions|)
     cl-weave:expect-has-assertions)
    (expect-macroexpands-through
     (test.concurrent "parallel alias" (expect :ok :to-be :ok))
     cl-weave:test-concurrent)
    (expect-macroexpands-through
     (test.concurrent.each ((1 2 3))
         "parallel alias ~A and ~A"
         (left right total)
       (expect (+ left right) :to-be total))
     cl-weave:test-concurrent-each)
    (expect-macroexpands-through
     (test.fails "expected failure alias" (expect :ok :to-be :not-ok))
     cl-weave:test-fails)
    (expect-macroexpands-through
     (test.fails.each ((1 2 4))
         "expected failure alias ~A and ~A"
         (left right total)
       (expect (+ left right) :to-be total))
     cl-weave:test-fails-each)
    (expect-macroexpands-through
     (test.only "focused alias" (expect :ok :to-be :ok))
     cl-weave:test-only)
    (expect-macroexpands-through
     (test.only.each ((1 2 3))
         "focused alias ~A and ~A"
         (left right total)
       (expect (+ left right) :to-be total))
     cl-weave:test-only-each)
    (expect-macroexpands-through
     (test.run-if t "conditional alias" (expect :ok :to-be :ok))
     cl-weave:test-run-if)
    (expect-macroexpands-through
     (test.runIf t "conditional camel alias" (expect :ok :to-be :ok))
     cl-weave:test-run-if)
    (expect-macroexpands-through
     (test.sequential "serial alias" (expect :ok :to-be :ok))
     cl-weave:test-sequential)
    (expect-macroexpands-through
     (test.sequential.each ((1 2 3))
         "serial alias ~A and ~A"
         (left right total)
       (expect (+ left right) :to-be total))
     cl-weave:test-sequential-each)
    (expect-macroexpands-through
     (test.skip "skipped alias" "because")
     cl-weave:test-skip)
    (expect-macroexpands-through
     (test.skip.each ((1 2 3))
         "skipped alias ~A and ~A"
         (left right total)
       "because"
       (expect (+ left right) :to-be total))
     cl-weave:test-skip-each)
    (expect-macroexpands-through
     (test.skip-if t "conditional skip alias" (expect :ok :to-be :ok))
     cl-weave:test-skip-if)
    (expect-macroexpands-through
     (test.skipIf t "conditional skip camel alias" (expect :ok :to-be :ok))
     cl-weave:test-skip-if)
    (expect-macroexpands-through
     (test.todo "todo alias" "later")
     cl-weave:test-todo)
    (expect-macroexpands-through
     (test.todo.each ((1 2 3))
         "todo alias ~A and ~A"
         (left right total)
       "later"
       (expect (+ left right) :to-be total))
     cl-weave:test-todo-each)
    (expect-macroexpands-through
     (test.isolated "isolated alias"
         (:systems ("cl-weave-tests") :timeout 5)
       (expect :ok :to-be :ok))
     cl-weave:test-isolated)
    (expect-macroexpands-through
     (test.property "property alias"
         ((value (gen-integer :min 0 :max 10)))
       (expect value :to-satisfy #'integerp))
     cl-weave:test-property)
    (expect-macroexpands-through
     (describe.concurrent "parallel alias"
       (it "case" (expect :ok :to-be :ok)))
     cl-weave:describe-concurrent)
    (expect-macroexpands-through
     (describe.concurrent.each ((1 2 3))
         "parallel suite ~A and ~A"
         (left right total)
       (it "case" (expect (+ left right) :to-be total)))
     cl-weave:describe-concurrent-each)
    (expect-macroexpands-through
     (describe.sequential "serial alias"
       (it "case" (expect :ok :to-be :ok)))
     cl-weave:describe-sequential)
    (expect-macroexpands-through
     (describe.sequential.each ((1 2 3))
         "serial suite ~A and ~A"
         (left right total)
       (it "case" (expect (+ left right) :to-be total)))
     cl-weave:describe-sequential-each)
    (expect-macroexpands-through
     (describe.only "focused alias"
       (it "case" (expect :ok :to-be :ok)))
     cl-weave:describe-only)
    (expect-macroexpands-through
     (describe.only.each ((1 2 3))
         "focused suite ~A and ~A"
         (left right total)
       (it "case" (expect (+ left right) :to-be total)))
     cl-weave:describe-only-each)
    (expect-macroexpands-through
     (describe.run-if t "conditional suite alias"
       (it "case" (expect :ok :to-be :ok)))
     cl-weave:describe-run-if)
    (expect-macroexpands-through
     (describe.runIf t "conditional suite camel alias"
       (it "case" (expect :ok :to-be :ok)))
     cl-weave:describe-run-if)
    (expect-macroexpands-through
     (describe.skip "skipped suite alias" "because"
       (it "case" (expect :ok :to-be :ok)))
     cl-weave:describe-skip)
    (expect-macroexpands-through
     (describe.skip.each ((1 2 3))
         "skipped suite ~A and ~A"
         (left right total)
       "because"
       (it "case" (expect (+ left right) :to-be total)))
     cl-weave:describe-skip-each)
    (expect-macroexpands-through
     (describe.skip-if t "conditional skipped suite alias"
       (it "case" (expect :ok :to-be :ok)))
     cl-weave:describe-skip-if)
    (expect-macroexpands-through
     (describe.skipIf t "conditional skipped suite camel alias"
       (it "case" (expect :ok :to-be :ok)))
     cl-weave:describe-skip-if)
    (expect-macroexpands-through
     (describe.todo "todo suite alias" "later")
     cl-weave:describe-todo)
    (expect-macroexpands-through
     (describe.todo.each ((1 2 3))
         "todo suite ~A and ~A"
         (left right total)
       "later"
       (it "case" (expect (+ left right) :to-be total)))
     cl-weave:describe-todo-each)
    (expect-macroexpands-through
     (expect.not 1 :to-be 2)
     cl-weave:expect-not)
    (expect-macroexpands-through
     (expect.resolves (lambda () :ok) :to-be :ok)
     cl-weave:expect-resolves)
    (expect-macroexpands-through
     (expect.rejects (lambda () (error "boom")) :to-be-type-of 'simple-error)
     cl-weave:expect-rejects))

  (it "compares a single macroexpansion step"
    (expect '(sample-unless ready (setf *fixture-value* :done))
            :to-expand-to
            '(if ready
                 nil
                 (progn (setf *fixture-value* :done))))))
