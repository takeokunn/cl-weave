(in-package #:cl-weave/tests)

(describe "macros"
  (it-each ((1 2 3)
            (13 21 34))
      "adds ~A and ~A at macro expansion time"
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

  (describe-each ((4 5 9))
      "dot table suite ~A plus ~A"
      (left right total)
    (before-each
      (setf (gethash :dot-table-total *test-context*) total))
    (it-each ((:alpha :alpha)
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

  (it "expands expect-resolves into canonical expect-resolves"
    (expect (macroexpand-1 '(expect-resolves (lambda () :ok) :to-be :ok))
            :to-satisfy
            (lambda (form)
              (tree-contains-p form 'expect-resolves))))

  (it "expands expect-resolves into resolving thunk evaluation"
    (expect (macroexpand-1 '(expect-resolves (lambda () :ok) :to-be :ok))
            :to-satisfy
            (lambda (form)
              (and (tree-contains-p form 'cl-weave::call-resolving-expectation-thunk)
                   (tree-contains-p form 'expect-resolves)))))

  (it "expands expect-rejects into canonical expect-rejects"
    (expect (macroexpand-1 '(expect-rejects (lambda () (error "boom")) :to-be-type-of 'simple-error))
            :to-satisfy
            (lambda (form)
              (tree-contains-p form 'expect-rejects))))

  (it "expands expect-poll into canonical expect-poll"
    (expect (macroexpand-1 '(expect-poll (lambda () :ok) :to-be :ok))
            :to-satisfy
            (lambda (form)
              (tree-contains-p form 'expect-poll))))

  (it "expands expect-rejects into rejecting thunk evaluation"
    (expect (macroexpand-1 '(expect-rejects (lambda () (error "boom")) :to-be-type-of 'simple-error))
            :to-satisfy
            (lambda (form)
              (and (tree-contains-p form 'cl-weave::call-rejecting-expectation-thunk)
                   (tree-contains-p form 'expect-rejects)))))

  (it "expands expect-poll into polling thunk evaluation"
    (expect (macroexpand-1 '(expect-poll (lambda () :ok) (:timeout-ms 10 :interval-ms 0) :to-be :ok))
            :to-satisfy
            (lambda (form)
              (and (tree-contains-p form 'cl-weave::call-polling-expectation-thunk)
                   (tree-contains-p form 'expect-poll)
                   (tree-contains-p form :timeout-ms)
                   (tree-contains-p form :interval-ms)))))

  (it "expands expect-extend into the custom matcher registry"
    (expect (macroexpand-1
             '(expect-extend
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
             '(it "eventually stable" (:retry 2 :timeout-ms 100
                                      :execution-mode :concurrent)
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

  (it "expands explicit sequential execution metadata"
    (expect (macroexpand-1
             '(it "generated sequential case" (:execution-mode :sequential)
                (expect :ok :to-be :ok)))
            :to-satisfy
            (lambda (form)
              (and (tree-contains-p form 'cl-weave::register-test)
                   (tree-contains-p form :execution-mode)
                   (tree-contains-p form :sequential)))))

  (it "rejects removed compatibility metadata options"
    (dolist (option '(:tags :depends-on :concurrent))
      (expect (lambda ()
                (macroexpand-1
                 `(it "removed metadata" (,option nil)
                    (expect :ok :to-be :ok))))
              :to-throw)))

  (it "validates registration macro syntax at expansion time"
    (dolist (case '(((it "duplicate" (:retry 1 :retry 2) t)
                     "Duplicate test option")
                    ((it-concurrent "conflict" (:execution-mode :sequential) t)
                     "conflicts with fixed mode")
                    ((it-skip-each ((1)) "skip ~A" (value) "reason" value)
                     "does not accept a test body")
                    ((it-todo-each ((1)) "todo ~A" (value) (print value))
                     "does not accept a test body")
                    ((it-property "bad" ((value)) value)
                     "must have the form (NAME GENERATOR)")
                    ((describe-each dynamic-cases "suite ~A" (value) value)
                     "literal proper list")
                    ((describe-each ((1)) dynamic-name (value) value)
                     "literal format string")
                    ((describe-each (not-a-case) "suite ~A" (value) value)
                     "case 0 must be a literal proper list")))
      (destructuring-bind (form message-fragment) case
        (handler-case
            (progn
              (macroexpand-1 form)
              (error "Expected macro expansion to reject ~S." form))
          (error (condition)
            (expect (princ-to-string condition)
                    :to-satisfy
                    (lambda (message)
                      (search message-fragment message))))))))

  (it "normalizes a repeated fixed execution mode"
    (let ((expansion (macroexpand-1
                      '(it-concurrent "parallel"
                           (:execution-mode :concurrent :retry 1)
                         t))))
      (expect (loop for tail on expansion
                    count (eq (first tail) :execution-mode))
              :to-be 1)))

  (it "restores replaced functions and bindings after temporary mutation"
    (expect (sample-size '(a b c)) :to-be 3)
    (with-replaced-function (sample-size (lambda (value)
                                           (+ 10 (length value))))
      (expect (sample-size '(a b c)) :to-be 13))
    (expect (sample-size '(a b c)) :to-be 3)

    (setf *fixture-value* :outer)
    (with-restored-binding (*fixture-value*)
      (setf *fixture-value* :inner)
      (expect *fixture-value* :to-be :inner))
    (expect *fixture-value* :to-be :outer)

    (setf *fixture-value* :root
          *fixture-events* '(:original))
    (with-restored-bindings ((*fixture-value*) (*fixture-events*))
      (setf *fixture-value* :mutated
            *fixture-events* '(:changed))
      (expect *fixture-value* :to-be :mutated)
      (expect *fixture-events* :to-equal '(:changed)))
    (expect *fixture-value* :to-be :root)
    (expect *fixture-events* :to-equal '(:original))

    (let ((table (make-hash-table :test #'equal)))
      (setf (gethash "keep" table) 1
            (gethash "drop" table) 2)
      (with-restored-hash-table (table)
        (remhash "keep" table)
        (setf (gethash "drop" table) 99
              (gethash "add" table) 3)
        (expect (gethash "drop" table) :to-be 99)
        (expect (gethash "add" table) :to-be 3))
      (expect (hash-table-count table) :to-be 2)
      (expect (gethash "keep" table) :to-be 1)
      (expect (gethash "drop" table) :to-be 2)
      (expect (nth-value 1 (gethash "add" table)) :to-be nil))

    (let ((table (make-hash-table :test #'equal)))
      (setf (gethash "persist" table) 1)
      (with-cleared-hash-table (table)
        (expect (hash-table-count table) :to-be 0)
        (setf (gethash "ephemeral" table) 2)
        (expect (gethash "ephemeral" table) :to-be 2))
      (expect (hash-table-count table) :to-be 1)
      (expect (gethash "persist" table) :to-be 1)
      (expect (nth-value 1 (gethash "ephemeral" table)) :to-be nil))

    (let* ((table (make-hash-table :test #'equal))
           (tables (vector table))
           (place-evaluations 0))
      (setf (gethash "persist" table) 1)
      (with-cleared-hash-table
          ((aref tables (progn (incf place-evaluations) 0)))
        (expect place-evaluations :to-be 1)
        (expect (hash-table-count table) :to-be 0))
      (expect place-evaluations :to-be 1)
      (expect (gethash "persist" table) :to-be 1)))

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

  (it "does not export removed Vitest compatibility aliases"
    (dolist (name '("IT.CONCURRENT" "TEST.ONLY" "DESCRIBE.EACH" "VI.FN"))
      (expect (nth-value 1 (find-symbol name :cl-weave))
              :not :to-be :external)))

  (it "compares a single macroexpansion step"
    (expect '(sample-unless ready (setf *fixture-value* :done))
            :to-expand-to
            '(if ready
                 nil
                 (progn (setf *fixture-value* :done)))))

  (it "reports the expanded form when to-expand-to fails"
    (handler-case
        (progn
          (expect '(sample-unless ready (setf *fixture-value* :done))
                  :to-expand-to
                  '(when ready (setf *fixture-value* :done)))
          (error "Expected to-expand-to to fail."))
      (cl-weave:assertion-failure (condition)
        (let ((detail (cl-weave::failure-detail condition)))
          (expect (cl-weave::assertion-detail-actual detail)
                  :to-equal
                  '(if ready nil (progn (setf *fixture-value* :done))))
          (expect (cl-weave::assertion-detail-expected detail)
                  :to-equal
                  '(when ready (setf *fixture-value* :done))))))))
