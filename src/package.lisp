(defpackage #:cl-weave
  (:use #:cl)
  (:shadow #:describe)
  (:export
   #:*test-context*
   #:around-each
   #:after-all
   #:after-each
   #:assert-mutation-score
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
   #:describe-concurrent
   #:describe-concurrent-each
   #:describe-each
   #:describe-only
   #:describe-only-each
   #:describe-run-if
   #:describe-sequential
   #:describe-sequential-each
   #:describe-skip
   #:describe-skip-each
   #:describe-skip-if
   #:describe-todo
   #:describe-todo-each
   #:defmatcher
   #:extend-expect
   #:explain!
   #:expect
   #:expect-assertions
   #:expect-extend
   #:expect-has-assertions
   #:expect-not
   #:expect-poll
   #:expect-rejects
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
   #:hook-failure
   #:hook-failure-causes
   #:hook-failure-phase
   #:*isolated-timeout-seconds*
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
   #:it
   #:it-concurrent
   #:it-concurrent-each
   #:it-each
   #:it-fails
   #:it-fails-each
   #:it-isolated
   #:it-property
   #:it-only
   #:it-only-each
   #:it-run-if
   #:it-sequential
   #:it-sequential-each
   #:it-skip
   #:it-skip-each
   #:it-skip-if
   #:it-todo
   #:it-todo-each
   #:list-tests
   #:logic-program
   #:logic-query
   #:logic-search-exhausted
   #:logic-search-exhausted-limit
   #:logic-search-exhausted-partial-results
   #:logic-search-exhausted-pending
   #:logic-search-exhausted-steps
   #:increase-limit
   #:return-partial-results
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
   #:*property-shrink-max-steps*
   #:*property-test-count*
   #:property-shrink-limit
   #:property-shrink-limit-max-steps
   #:property-shrink-limit-steps
   #:property-shrink-limit-values
   #:property-shrinker-error
   #:property-shrinker-error-cause
   #:property-shrinker-error-generator
   #:property-shrinker-error-value
   #:retry-shrinker
   #:same-property-failure-p
   #:skip-shrinking
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
   #:test-plan-facts
   #:test-plan-where
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

(defun runtime-source-directory ()
  (or (ignore-errors
        (asdf:system-relative-pathname "cl-weave" "src/"))
      (make-pathname :name nil
                     :type nil
                     :defaults *load-truename*)))

(defvar *runtime-source-directory* (runtime-source-directory))

(defparameter *local-project-system-source-files*
  '(("cl-weave"
     "package.lisp"
     "model.lisp"
     "logic.lisp"
     "isolation.lisp"
     "snapshots.lisp"
     "mocks.lisp"
     "matcher-core.lisp"
     "matcher-structural.lisp"
     "matcher-runtime.lisp"
     "matcher-builtins.lisp"
     "expectation.lisp"
     "property-core.lisp"
     "property-generators.lisp"
     "property-runner.lisp"
     "mutation.lisp"
     "registration.lisp"
     "fixtures.lisp"
     "continuations.lisp"
     "expect-runtime.lisp"
     "expect.lisp"
     "reporter-schema.lisp"
     "reporter-json.lisp"
     "reporter-results.lisp"
     "reporter-tap.lisp"
     "reporter-github.lisp"
     "reporter-plan.lisp"
     "reporter-mutation.lisp"
     "reporter-junit.lisp"
     "runner-execution.lisp"
     "runner-selection.lisp"
     "runner-planning.lisp"
     "runner-concurrency.lisp"
     "runner-collection.lisp"
     "runner-api.lisp"
     "watch.lisp"
     "cli-options.lisp"
     "cli-metadata-project-data.lisp"
     "cli-metadata-quality-data.lisp"
     "cli-metadata-option-data.lisp"
     "cli-metadata-capability-data.lisp"
     "cli-metadata-core.lisp"
     "cli-metadata-doctor.lisp"
     "cli-metadata-json-core.lisp"
     "cli-metadata-json-schema.lisp"
     "cli-metadata-reporting.lisp"
     "cli.lisp"
     "cli-execution.lisp")
    ("cl-weave-tests"
     "tests/package.lisp"
     "tests/support.lisp"
     "tests/expect-core.lisp"
     "tests/expect-failures.lisp"
     "tests/expect-extensions.lisp"
     "tests/expect-records.lisp"
     "tests/macros.lisp"
     "tests/isolation.lisp"
     "tests/property-support.lisp"
     "tests/property-generators.lisp"
     "tests/property-shrinking.lisp"
     "tests/property-environment.lisp"
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
     "tests/cli-support.lisp"
     "tests/cli-options.lisp"
     "tests/cli-execution.lisp"
     "tests/cli-metadata-core.lisp"
     "tests/cli-metadata-ci.lisp"
     "tests/cli-metadata-capabilities.lisp"
     "tests/cli-metadata-contracts.lisp"
     "tests/cli-entrypoint.lisp"
     "tests/community-health.lisp"
     "tests/asdf-integration.lisp"
     "tests/mocking.lisp"
     "tests/reporter-formats.lisp"
     "tests/reporter-plans.lisp"
     "tests/reporter-schemas.lisp"
     "tests/reporter-ci.lisp"
     "tests/reporter-status.lisp"
     "tests/reporter-runtime.lisp")))

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
