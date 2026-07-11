(in-package #:cl-weave/tests)

(describe "retry and timeout"
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

  (it "lists effective retry and timeout defaults in test plans"
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
                :to-equal '(100 25)))))

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
          (expect (cl-weave::test-event-status event) :to-be expected-status))))))
