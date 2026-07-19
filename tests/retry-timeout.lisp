

(in-package #:cl-weave/tests)
(describe "tag filter normalization"
  (it "accepts maximum include and exclude tags in canonical first order"
    (let* ((limit cl-weave::+maximum-tag-count+)
           (include-tags (make-list limit :initial-element :fast))
           (exclude-tags (make-list limit :initial-element :database))
           (root (cl-weave::make-suite :name "root"))
           (root-calls 0)
           (captured-options nil))
      (setf (first include-tags) :fast
            (second include-tags) "slow"
            (third include-tags) 'fast
            (fourth include-tags) :other
            (first exclude-tags) "database"
            (second exclude-tags) :cache
            (third exclude-tags) "DATABASE")
      (with-mocked-functions
          (((symbol-function 'cl-weave:root-suite)
            (lambda ()
              (incf root-calls)
              root))
           ((symbol-function 'cl-weave::collect-events-with-options)
            (lambda (suite options)
              (declare (ignore suite))
              (setf captured-options options)
              nil)))
        #+sbcl
        (sb-ext:with-timeout 10
          (expect
           (cl-weave:run-all
            :reporter :sexp
            :stream (make-broadcast-stream)
            :include-tags include-tags
            :exclude-tags exclude-tags)
           :to-be-truthy))
        #-sbcl
        (expect
         (cl-weave:run-all
          :reporter :sexp
          :stream (make-broadcast-stream)
          :include-tags include-tags
          :exclude-tags exclude-tags)
         :to-be-truthy))
      (expect root-calls :to-be 1)
      (expect captured-options :to-be-truthy)
      (expect (cl-weave::collection-options-include-tags captured-options)
              :to-equal '("FAST" "SLOW" "OTHER"))
      (expect (cl-weave::collection-options-exclude-tags captured-options)
              :to-equal '("DATABASE" "CACHE")))))


(describe "run-all input preflight"
  (it "validates every run-all collection option before coverage and suite access"
    (labels ((exercise ()
               (let* ((root (cl-weave::make-suite :name "root"))
                      (limit cl-weave::+maximum-selection-filter-count+)
                      (location-cycle (list #P"/tmp/cl-weave/cycle.lisp"))

(path-cycle (list (list "suite" "test")))
(tag-limit cl-weave::+maximum-tag-count+)
(include-tag-cycle (list :fast))
(exclude-tag-cycle (list :slow))
(shard-cycle (list 1 2))

                      (coverage-require 0)
                      (coverage-reset 0)
                      (coverage-cleanup 0)
                      (suite-root 0)
                      (suite-snapshot 0)
                      (executed 0)
                      (artifact 0))
                 (setf (cdr location-cycle) location-cycle)

(setf (cdr path-cycle) path-cycle)
(setf (cdr include-tag-cycle) include-tag-cycle)
(setf (cdr exclude-tag-cycle) exclude-tag-cycle)
(setf (cddr shard-cycle) shard-cycle)

                 (cl-weave::add-child
                  root
                  (cl-weave::make-test-case
                   :name "must not run"
                   :function (lambda () (incf executed))))
                 (with-mocked-functions
                     (((symbol-function 'cl-weave::require-coverage-support)
                       (lambda () (incf coverage-require)))
                      ((symbol-function 'cl-weave:reset-coverage)
                       (lambda () (incf coverage-reset)))
                      ((symbol-function 'cl-weave:coverage-statistics)
                       (lambda (&key include-pathnames exclude-pathnames)
                         (declare (ignore include-pathnames exclude-pathnames))
                         (incf coverage-cleanup)
                         '(:expression-covered 0 :expression-total 0
                           :branch-covered 0 :branch-total 0)))
                      ((symbol-function 'cl-weave::save-coverage-report)
                       (lambda (path &key include-pathnames exclude-pathnames)
                         (declare (ignore path
                                          include-pathnames
                                          exclude-pathnames))
                         (incf artifact)))
                      ((symbol-function 'cl-weave:save-coverage)
                       (lambda (path)
                         (declare (ignore path))
                         (incf artifact)))
                      ((symbol-function 'cl-weave:root-suite)
                       (lambda ()
                         (incf suite-root)
                         root))
                      ((symbol-function 'cl-weave::snapshot-suite)
                       (lambda (suite)
                         (incf suite-snapshot)
                         suite)))
                   (dolist (arguments
                            (list
                             (list :name-filter 42)
                             (list :location-filter location-cycle)
                             (list :location-filter
                                   (cons #P"/tmp/cl-weave/dotted.lisp" :tail))
                             (list :location-filter
                                   (make-list (1+ limit)
                                              :initial-element
                                              #P"/tmp/cl-weave/oversized.lisp"))
                             (list :test-path-filter path-cycle)
                             (list :test-path-filter
                                   (cons (list "suite" "test") :tail))
                             (list :test-path-filter
                                   (make-list (1+ limit)
                                              :initial-element nil))

(list :include-tags (cons :fast :tail))
(list :include-tags include-tag-cycle)
(list :include-tags
      (make-list (1+ tag-limit) :initial-element :fast))
(list :exclude-tags exclude-tag-cycle)
(list :exclude-tags
      (make-list (1+ tag-limit) :initial-element :slow))

                             (list :exclude-tags (cons :slow :tail))

(list :shard shard-cycle)
(list :shard
      (make-list (1+ tag-limit) :initial-element 1))
(list :shard
      (list 1
            (1+ cl-weave::+maximum-shard-count+)))

                             (list :order :defined)
                             (list :seed 1.5)
                             (list :bail
                                   (1+ cl-weave::+maximum-bail-limit+))
                             (list :retry
                                   (1+ cl-weave::+maximum-retry-count+))
                             (list :timeout-ms
                                   (1+ cl-weave::+maximum-timeout-ms+))
                             (list :max-workers
                                   (1+ cl-weave::+maximum-worker-count+))))
                     (expect
                      (lambda ()
                        (apply #'cl-weave:run-all
                               :reporter :sexp
                               :stream (make-broadcast-stream)
                               :coverage t
                               :coverage-output "unused.coverage"
                               :coverage-report-directory "unused-report/"
                               :coverage-minimum-expression 0
                               arguments))
                      :to-throw)))
                 (expect coverage-require :to-be 0)
                 (expect coverage-reset :to-be 0)
                 (expect coverage-cleanup :to-be 0)
                 (expect suite-root :to-be 0)
                 (expect suite-snapshot :to-be 0)
                 (expect executed :to-be 0)
                 (expect artifact :to-be 0))))
      #+sbcl
      (sb-ext:with-timeout 10
        (exercise))
      #-sbcl
      (exercise))))


(describe "retry and timeout"
  (it "keeps the test continuation inside the platform timeout boundary"
    (let* ((continuation-calls 0)
           (suite (cl-weave::make-suite :name "timeout continuation"))
           (test (cl-weave::make-test-case
                  :name "single continuation"
                  :function (lambda () :completed)))
           (cl-weave::*platform-capabilities* '(:timeout))
           (cl-weave::*platform-timeout-caller*
             (lambda (timeout callable continue)
               (declare (ignore timeout))
               (funcall continue (funcall callable)))))
      (expect
       (cl-weave::call-test-case-with-timeout/k
        suite
        test
        1.0
        (lambda ()
          (incf continuation-calls)
          :continued))
       :to-be :continued)
      (expect continuation-calls :to-be 1)))

  (it "retries failing tests until they pass"
    (let* ((attempts 0)
           (test (cl-weave::make-test-case
                  :name "eventual pass"
                  :retry 2
                  :function (lambda ()
                              (incf attempts)
                              (when (< attempts 3)
                                (expect attempts :to-be 3)))))
           (event (cl-weave::run-test-case (cl-weave::root-suite) test)))
      (expect attempts :to-be 3)
      (expect (cl-weave::test-event-status event) :to-be :pass)))

  (it "stops retrying after the configured retry budget"
    (let* ((attempts 0)
           (test (cl-weave::make-test-case
                  :name "always fails"
                  :retry 2
                  :function (lambda ()
                              (incf attempts)
                              (expect attempts :to-be 10))))
           (event (cl-weave::run-test-case (cl-weave::root-suite) test)))
      (expect attempts :to-be 3)
      (expect (cl-weave::test-event-status event) :to-be :fail)
      (expect (cl-weave::test-event-assertion event) :to-be-defined)))

  (it "applies global retry defaults to tests without local retry options"
    (let* ((attempts 0)
           (suite (cl-weave::make-suite :name "global retry"))
           (test (cl-weave::make-test-case
                  :name "eventual pass"
                  :function (lambda ()
                              (incf attempts)
                              (when (< attempts 3)
                                (expect attempts :to-be 3))))))
      (cl-weave::add-child suite test)
      (let ((events (cl-weave::collect-events suite :retry 2)))
        (expect attempts :to-be 3)
        (expect (mapcar #'cl-weave::test-event-status events)
                :to-equal '(:pass)))))

  (it "lets local retry options override global retry defaults"
    (let* ((attempts 0)
           (suite (cl-weave::make-suite :name "local retry"))
           (test (cl-weave::make-test-case
                  :name "still fails"
                  :retry 0
                  :function (lambda ()
                              (incf attempts)
                              (expect attempts :to-be 10)))))
      (cl-weave::add-child suite test)
      (let ((events (cl-weave::collect-events suite :retry 2)))
        (expect attempts :to-be 1)
        (expect (mapcar #'cl-weave::test-event-status events)
                :to-equal '(:fail)))))

  (it "reports timed out tests as structured failures"
    (let* ((test (cl-weave::make-test-case
                  :name "slow"
                  :timeout-ms 10
                  :function (lambda () (sleep 0.1))))
           (event (cl-weave::run-test-case (cl-weave::root-suite) test)))
      (expect (cl-weave::test-event-status event) :to-be :fail)
      (expect (cl-weave::test-event-condition event)
              :to-be-instance-of 'cl-weave:test-timeout)
      (expect (cl-weave:test-timeout-ms (cl-weave::test-event-condition event))
              :to-be 10)))

  (it "applies global timeout defaults to tests without local timeout options"
    (let* ((suite (cl-weave::make-suite :name "global timeout"))
           (test (cl-weave::make-test-case
                  :name "slow"
                  :function (lambda () (sleep 0.1)))))
      (cl-weave::add-child suite test)
      (let* ((events (cl-weave::collect-events suite :timeout-ms 10))
             (event (first events)))
        (expect (cl-weave::test-event-status event) :to-be :fail)
        (expect (cl-weave::test-event-condition event)
                :to-be-instance-of 'cl-weave:test-timeout)
        (expect (cl-weave:test-timeout-ms
                 (cl-weave::test-event-condition event))
                :to-be 10))))

  (it "lists and bounds effective retry and timeout defaults"
    (let* ((suite (cl-weave::make-suite :name "plan defaults"))
           (defaulted (cl-weave::make-test-case
                       :name "defaulted"
                       :function (lambda () t)))
           (local (cl-weave::make-test-case
                   :name "local"
                   :retry 0
                   :timeout-ms 25
                   :function (lambda () t))))
      (cl-weave::add-child suite defaulted)
      (cl-weave::add-child suite local)
      (let ((plan (cl-weave:collect-test-plan
                   suite
                   :retry 2
                   :timeout-ms 100)))
        (expect (mapcar #'cl-weave:test-plan-entry-retry plan)
                :to-equal '(2 0))
        (expect (mapcar #'cl-weave:test-plan-entry-timeout-ms plan)
                :to-equal '(100 25))))
    (expect (cl-weave::collect-events
             (cl-weave::make-suite :name "empty")
             :retry cl-weave::+maximum-retry-count+
             :timeout-ms cl-weave::+maximum-timeout-ms+)
            :to-be-null)
    (dolist (option
             (list
              (list :retry
                    (1+ cl-weave::+maximum-retry-count+)
                    "Retry must be")
              (list :timeout-ms
                    (1+ cl-weave::+maximum-timeout-ms+)
                    "Timeout must be")))
      (let ((executed nil)
            (root (cl-weave::make-suite :name "root")))
        (cl-weave::add-child
         root
         (cl-weave::make-test-case
          :name "must not run"
          :function (lambda () (setf executed t))))
        (expect (lambda ()
                  (apply #'cl-weave::collect-events
                         root
                         (list (first option) (second option))))
                :to-throw
                (third option))
        (expect executed :to-be nil))))

  (it "validates public run limits before coverage side effects"
    (dolist (option
             (list
              (list :retry
                    (1+ cl-weave::+maximum-retry-count+)
                    "Retry must be")
              (list :timeout-ms
                    (1+ cl-weave::+maximum-timeout-ms+)
                    "Timeout must be")
              (list :max-workers
                    (1+ cl-weave::+maximum-worker-count+)
                    "Max workers must be")
              (list :bail
                    (1+ cl-weave::+maximum-bail-limit+)
                    "Bail must be")
              (list :shard
                    (list 1 (1+ cl-weave::+maximum-shard-count+))
                    "Shard must be NIL")))
      (destructuring-bind (key value error-message) option
        (let ((coverage-calls 0)
              (executed 0)
              (root (cl-weave::make-suite :name "root")))
          (cl-weave::add-child
           root
           (cl-weave::make-test-case
            :name "must not run"
            :function (lambda () (incf executed))))
          (with-mocked-functions
              (((symbol-function 'cl-weave::require-coverage-support)
                (lambda ()
                  (incf coverage-calls)))
               ((symbol-function 'cl-weave:reset-coverage)
                (lambda ()
                  (incf coverage-calls)))
               ((symbol-function 'cl-weave:save-coverage)
                (lambda (path)
                  (declare (ignore path))
                  (incf coverage-calls))))
            (let ((cl-weave::*root-suite* root))
              (expect
               (lambda ()
                 (apply #'cl-weave:run-all
                        :reporter :sexp
                        :stream (make-broadcast-stream)
                        :coverage t
                        :coverage-output "unused.coverage"
                        (list key value)))
               :to-throw
               error-message)))
          (expect coverage-calls :to-be 0)
          (expect executed :to-be 0)))))

  (it "fails a test when expect-assertions count is not met"
    (let* ((test (cl-weave::make-test-case
                  :name "missing assertion"
                  :function (lambda ()
                              (expect-assertions 2)
                              (expect :only :to-be :only))))
           (event (cl-weave::run-test-case (cl-weave::root-suite) test))
           (assertion (cl-weave::test-event-assertion event)))
      (expect (cl-weave::test-event-status event) :to-be :fail)
      (expect (cl-weave::assertion-detail-matcher assertion) :to-be :assertions)
      (expect (cl-weave::assertion-detail-actual assertion) :to-be 1)
      (expect (cl-weave::assertion-detail-expected assertion) :to-be 2)))

  (it "fails a test when expect-has-assertions observes no assertions"
    (let* ((test (cl-weave::make-test-case
                  :name "missing assertions"
                  :function (lambda ()
                              (expect-has-assertions))))
           (event (cl-weave::run-test-case (cl-weave::root-suite) test))
           (assertion (cl-weave::test-event-assertion event)))
      (expect (cl-weave::test-event-status event) :to-be :fail)
      (expect (cl-weave::assertion-detail-matcher assertion) :to-be :has-assertions)
      (expect (cl-weave::assertion-detail-actual assertion) :to-be 0)
      (expect (cl-weave::assertion-detail-expected assertion) :to-equal '(:minimum 1))))

  (it "resets assertion counts for each retry attempt"
    (let* ((attempts 0)
           (test (cl-weave::make-test-case
                  :name "eventual assertion count"
                  :retry 1
                  :function (lambda ()
                              (incf attempts)
                              (expect-assertions 1)
                              (if (= attempts 1)
                                  (progn
                                    (expect :first :to-be :first)
                                    (expect :extra :to-be :extra))
                                  (expect :second :to-be :second)))))
           (event (cl-weave::run-test-case (cl-weave::root-suite) test)))
      (expect attempts :to-be 2)
      (expect (cl-weave::test-event-status event) :to-be :pass)))

  (it "runs after-each cleanup when an attempt times out"
    (let* ((events nil)
           (suite (cl-weave::make-suite
                   :name "timeout cleanup"
                   :after-each (list (lambda () (push :after-each events)))))
           (test (cl-weave::make-test-case
                  :name "slow"
                  :timeout-ms 10
                  :function (lambda () (sleep 0.1)))))
      (cl-weave::add-child suite test)
      (let ((event (cl-weave::run-test-case suite test)))
        (expect (cl-weave::test-event-status event) :to-be :fail)
        (expect events :to-equal '(:after-each)))))

  (it "exposes a restart that can continue a failed attempt as passed"
    (let* ((test (cl-weave::make-test-case
                  :name "continue from failure"
                  :function (lambda ()
                              (expect :actual :to-be :expected))))
           (event (handler-bind ((assertion-failure
                                   (lambda (condition)
                                     (declare (ignore condition))
                                     (invoke-restart 'continue-test))))
                    (cl-weave::run-test-case/interactively (cl-weave::root-suite) test))))
      (expect (cl-weave::test-event-status event) :to-be :pass)))

  (it "exposes a restart that records a failed attempt as skipped"
    (let* ((test (cl-weave::make-test-case
                  :name "skip from failure"
                  :function (lambda ()
                              (expect :actual :to-be :expected))))
           (event (handler-bind ((assertion-failure
                                   (lambda (condition)
                                     (declare (ignore condition))
                                     (invoke-restart 'skip-test "patched interactively"))))
                    (cl-weave::run-test-case/interactively (cl-weave::root-suite) test))))
      (expect (cl-weave::test-event-status event) :to-be :skip)
      (expect (cl-weave::test-event-reason event) :to-equal "patched interactively")))

  (it "allows warnings and notification conditions to continue"
    (dolist (test-function
             (list (lambda ()
                     (warn "nonfatal warning"))
                   (lambda ()
                     (signal (make-condition 'simple-condition
                                             :format-control "notification")))))
      (let* ((test (cl-weave::make-test-case
                    :name "non-error condition"
                    :function test-function))
             (event (handler-bind ((warning #'muffle-warning))
                      (cl-weave::run-test-case (cl-weave::root-suite) test))))
        (expect (cl-weave::test-event-status event) :to-be :pass))))

  (it "charges interactive retries to the configured retry budget"
    (dolist (case '((1 2 :pass)
                    (0 1 :error)))
      (destructuring-bind (retry expected-attempts expected-status) case
        (let* ((attempts 0)
               (test (cl-weave::make-test-case
                      :name "retry from failure"
                      :retry retry
                      :function (lambda ()
                                  (incf attempts)
                                  (expect attempts :to-be 2))))
               (event
                 (handler-bind ((assertion-failure
                                  (lambda (condition)
                                    (declare (ignore condition))
                                    (invoke-restart 'retry-test))))
                   (cl-weave::run-test-case/interactively
                    (cl-weave::root-suite)
                    test))))
          (expect attempts :to-be expected-attempts)
          (expect (cl-weave::test-event-status event) :to-be expected-status)))))

  (it "uses the same continuation path for automatic and interactive retries"
    (dolist (interactive-p '(nil t))
      (let* ((attempts 0)
             (test (cl-weave::make-test-case
                    :name "continuation retry"
                    :retry 1
                    :function (lambda ()
                                (incf attempts)
                                (expect attempts :to-be 2))))
             (run (lambda ()
                    (if interactive-p
                        (handler-bind
                            ((assertion-failure
                               (lambda (condition)
                                 (declare (ignore condition))
                                 (invoke-restart 'retry-test))))
                          (cl-weave::run-test-case/interactively
                           (cl-weave::root-suite)
                           test))
                        (cl-weave::run-test-case
                         (cl-weave::root-suite)
                         test))))
             (event (funcall run)))
        (expect attempts :to-be 2)
        (expect (cl-weave::test-event-status event) :to-be :pass)))))
