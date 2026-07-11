(defpackage #:cl-weave
  (:use #:cl)
  (:shadow #:describe)
  (:export
   #:*test-context*
   #:around-each
   #:after-all
   #:after-each
   #:assert-=
   #:assert-bool
   #:assert-eq
   #:assert-eql
   #:assert-equal
   #:assert-false
   #:assert-list-contains
   #:assert-monotonic-decreasing
   #:assert-monotonic-increasing
   #:assert-no-signals
   #:assert-not-null
   #:assert-null
   #:assert-mutation-score
   #:assert-set-equal
   #:assert-signals
   #:assert-string=
   #:assert-string-contains
   #:assert-true
   #:assert-type
   #:assert-type-equal
   #:assert-values
   #:assert-within-tolerance
   #:assert-within-tolerance-percent
   #:assertion-failure
   #:before-all
   #:before-each
   #:clear-tests
   #:collect-test-plan
   #:collect-mutations
   #:continue-test
   #:coverage-support-available-p
   #:coverage-unavailable
   #:coverage-unavailable-reason
   #:defmutation-operator
   #:describe
   #:describe.concurrent
   #:describe-concurrent
   #:describe.concurrent.each
   #:describe-concurrent-each
   #:describe.each
   #:describe-each
   #:describe.only
   #:describe-only
   #:describe.only.each
   #:describe-only-each
   #:describe.run-if
   #:describe-run-if
   #:describe.sequential
   #:describe-sequential
   #:describe.sequential.each
   #:describe-sequential-each
   #:describe.skip
   #:describe-skip
   #:describe.skip.each
   #:describe-skip-each
   #:describe.skip-if
   #:describe-skip-if
   #:describe.todo
   #:describe-todo
   #:describe.todo.each
   #:describe-todo-each
   #:defmatcher
   #:extend-expect
   #:explain!
   #:expect
   #:expect.assertions
   #:expect-assertions
   #:expect.extend
   #:expect-extend
   #:expect.hasassertions
   #:expect-has-assertions
   #:expect.not
   #:expect-not
   #:expect.poll
   #:expect-poll
   #:expect.rejects
   #:expect-rejects
   #:expect.resolves
   #:expect-resolves
   #:expected-failure-missed
   #:expected-failure-missed-reason
   #:fail
   #:finishes
   #:gen-boolean
   #:gen-character
   #:gen-integer
   #:gen-keyword
   #:gen-list
   #:gen-map
   #:gen-member
   #:gen-one-of
   #:gen-recursive
   #:gen-form
   #:gen-sexp
   #:gen-state-machine
   #:gen-string
   #:gen-such-that
   #:gen-symbol
   #:gen-tuple
   #:gen-vector
   #:*isolated-timeout-seconds*
   #:assert-isolated-success
   #:isolated-result
   #:isolated-result-elapsed-ms
   #:isolated-result-exit-code
   #:isolated-result-home-path
   #:isolated-result-script-path
   #:isolated-result-status
   #:isolated-result-stderr
   #:isolated-result-stderr-path
   #:isolated-result-stdout
   #:isolated-result-stdout-path
   #:isolated-result-timed-out-p
   #:is
   #:is-between
   #:is-double-float
   #:is-empty
   #:is-eq
   #:is-equal
   #:is-every
   #:is-false
   #:is-fact
   #:is-finite
   #:is-float
   #:is-integer
   #:is-keyword
   #:is-list
   #:is-member
   #:is-near
   #:is-negative
   #:is-nil
   #:is-non-nil
   #:is-not-eq
   #:is-not-equal
   #:is-not-member
   #:is-number
   #:is-positive
   #:is-real
   #:is-string
   #:is-string-contains
   #:is-symbol
   #:is-true
   #:is-type
   #:is-record
   #:is-zero
   #:it
   #:it.concurrent
   #:it-concurrent
   #:it.concurrent.each
   #:it-concurrent-each
   #:it.each
   #:it-each
   #:it.fails
   #:it-fails
   #:it.fails.each
   #:it-fails-each
   #:it.isolated
   #:it-isolated
   #:it.property
   #:it-property
   #:it.only
   #:it-only
   #:it.only.each
   #:it-only-each
   #:it.run-if
   #:it-run-if
   #:it.sequential
   #:it-sequential
   #:it.sequential.each
   #:it-sequential-each
   #:it.skip
   #:it-skip
   #:it.skip.each
   #:it-skip-each
   #:it.skip-if
   #:it-skip-if
   #:it.todo
   #:it-todo
   #:it.todo.each
   #:it-todo-each
   #:list-tests
   #:logic-program
   #:logic-query
   #:logic-run
   #:logic-variable-p
   #:logic-where
   #:list-matchers
   #:list-mutation-operators
   #:matcher
   #:matcher-description
   #:matcher-metadata
   #:matcher-name
   #:mutation
   #:mutation-form
   #:mutation-id
   #:mutation-operator
   #:mutation-operator-description
   #:mutation-operator-metadata
   #:mutation-operator-name
   #:mutation-original
   #:mutation-path
   #:mutation-replacement
   #:mutation-result
   #:mutation-result-condition
   #:mutation-result-mutation
   #:mutation-result-status
   #:mutation-score-failure
   #:mutation-score-failure-min-score
   #:mutation-score-failure-summary
   #:mutation-score-passes-p
   #:mutation-summary
   #:*property-seed*
   #:*property-test-count*
   #:same-property-failure-p
   #:*snapshot-directory*
   #:*snapshot-file-name*
   #:*update-snapshots*
   #:snapshot-entries
   #:snapshot-value
   #:with-snapshot-updates
   #:with-continuation-result
   #:with-continuation-values
   #:with-cleared-hash-table
   #:clear-all-mocks
   #:clear-mock
   #:make-mock-function
   #:mock-function-p
   #:mock-implementation
   #:mock-return-value
   #:mock-return-values
   #:reset-all-mocks
   #:reset-mock
   #:restore-all-mocks
   #:reporter-artifact-schemas
   #:framework-metadata
   #:skip
   #:mock-restore
   #:spy-on
   #:vi.clearallmocks
   #:vi.fn
   #:vi.ismockfunction
   #:vi.mocked
   #:vi.mockclear
   #:vi.mockimplementation
   #:vi.mockreset
   #:vi.mockrestore
   #:vi.mockreturnvalue
   #:vi.mockreturnvalues
   #:vi.resetallmocks
   #:vi.restoreallmocks
   #:vi.spyon
   #:mock-calls
   #:mock-results
   #:*test-sequence-order*
   #:*test-sequence-seed*
   #:*test-name-filter*
   #:*default-retry*
   #:*default-timeout-ms*
   #:asdf-system-files
   #:report-mutations-json
   #:report-mutations-sexp
   #:results-status
   #:run
   #:run-all
   #:run-isolated
   #:run-mutations
   #:run-system
   #:signals
   #:query-test-plan
   #:reset-coverage
   #:save-coverage
   #:retry-test
   #:skip-test
   #:test-plan-entry
   #:test-plan-entry-focused
   #:test-plan-entry-location
   #:test-plan-entry-path
   #:test-plan-entry-reason
   #:test-plan-entry-retry
   #:test-plan-entry-status
   #:test-plan-entry-timeout-ms
   #:test-plan-entry-concurrent
   #:test-plan-entry-tags
   #:test-plan-entry-depends-on
   #:test-plan-facts
   #:test-plan-where
   #:test
   #:test.concurrent
   #:test-concurrent
   #:test.concurrent.each
   #:test-concurrent-each
   #:test.each
   #:test-each
   #:test.fails
   #:test-fails
   #:test.fails.each
   #:test-fails-each
   #:test.isolated
   #:test-isolated
   #:test.only
   #:test-only
   #:test.only.each
   #:test-only-each
   #:test.property
   #:test-property
   #:test.run-if
   #:test-run-if
   #:test.sequential
   #:test-sequential
   #:test.sequential.each
   #:test-sequential-each
   #:test.skip
   #:test-skip
   #:test.skip.each
   #:test-skip-each
   #:test.skip-if
   #:test-skip-if
   #:test.todo
   #:test-todo
   #:test.todo.each
   #:test-todo-each
   #:test-failure
   #:test-timeout
   #:test-timeout-ms
   #:*max-workers*
   #:watch-system
   #:with-mocked-functions
   #:with-replaced-function
   #:with-restored-binding
   #:with-restored-bindings
   #:with-restored-hash-table))

(in-package #:cl-weave)

(defvar *runtime-source-directory*
  #.(make-pathname :name nil
                   :type nil
                   :defaults (or *compile-file-truename*
                                 *load-truename*)))

(defparameter *local-project-system-source-files*
  '(("cl-weave"
     "package.lisp"
     "model.lisp"
     "logic.lisp"
     "isolation.lisp"
     "snapshots.lisp"
     "mocks.lisp"
     "matchers.lisp"
     "property.lisp"
     "mutation.lisp"
     "dsl.lisp"
     "reporters.lisp"
     "runner.lisp"
     "runner-api.lisp"
     "watch.lisp"
     "cli-options.lisp"
     "cli-metadata-data.lisp"
     "cli-metadata.lisp"
     "cli.lisp"
     "cli-execution.lisp")
    ("cl-weave-tests"
     "tests/package.lisp"
     "tests/support.lisp"
     "tests/expect.lisp"
     "tests/macros.lisp"
     "tests/isolation.lisp"
     "tests/properties.lisp"
     "tests/mutation.lisp"
     "tests/fixtures.lisp"
     "tests/cps.lisp"
     "tests/retry-timeout.lisp"
     "tests/concurrent.lisp"
     "tests/coverage.lisp"
     "tests/expected-failures.lisp"
     "tests/skips.lisp"
     "tests/todos.lisp"
     "tests/focus.lisp"
     "tests/filtering.lisp"
     "tests/sharding.lisp"
     "tests/sequence.lisp"
     "tests/list-mode.lisp"
     "tests/bail.lisp"
     "tests/cli.lisp"
     "tests/community-health.lisp"
     "tests/asdf-integration.lisp"
     "tests/mocking.lisp"
     "tests/reporters.lisp")))

(defun %local-project-system-name (system)
  (etypecase system
    (string system)
    (symbol (symbol-name system))
    (t (princ-to-string system))))

(defun local-project-system-p (system)
  (not (null (assoc (%local-project-system-name system)
                    *local-project-system-source-files*
                    :test #'string-equal))))

(defun local-project-system-root (system)
  (if (string-equal (%local-project-system-name system) "cl-weave")
      *runtime-source-directory*
      (uiop:ensure-directory-pathname
       (merge-pathnames "../" *runtime-source-directory*))))

(defun local-project-system-source-files (system)
  (cdr (assoc (%local-project-system-name system)
              *local-project-system-source-files*
              :test #'string-equal)))

(defun local-project-system-dependencies (system)
  (when (string-equal (%local-project-system-name system) "cl-weave-tests")
    '("cl-weave")))

(defun load-local-system (system &optional loaded-systems)
  (let ((system-name (%local-project-system-name system)))
    (dolist (dependency (local-project-system-dependencies system-name))
      (load-local-system dependency loaded-systems))
    (unless (and loaded-systems (gethash system-name loaded-systems))
      (when loaded-systems
        (setf (gethash system-name loaded-systems) t))
      (dolist (runtime-file (local-project-system-source-files system-name))
        (load (merge-pathnames runtime-file
                               (local-project-system-root system-name)))))
    t))

(defpackage #:cl-weave/cli
  (:use #:cl)
  (:export
   #:main))
