(in-package #:cl-weave/tests)

(describe "expected failures"
  (it-fails "passes when the body fails"
    (expect 1 :to-be 2))

  (it "turns unexpected success into a structured failure"
    (let* ((test (cl-weave::make-test-case
                  :name "known bug"
                  :expected-failure-reason "known bug"
                  :function (lambda () :ok)))
           (event (cl-weave::run-test-case (cl-weave::root-suite) test)))
      (expect (cl-weave::test-event-status event) :to-be :fail)
      (expect (cl-weave::test-event-condition event)
              :to-be-instance-of 'cl-weave:expected-failure-missed)
      (expect (cl-weave:expected-failure-missed-reason
               (cl-weave::test-event-condition event))
              :to-equal "known bug")))

  (it "retries unexpected success until it becomes an expected failure"
    (let* ((attempts 0)
           (test (cl-weave::make-test-case
                  :name "eventually fails"
                  :retry 2
                  :expected-failure-reason "known bug"
                  :function (lambda ()
                              (incf attempts)
                              (when (= attempts 3)
                                (expect :actual :to-be :expected)))))
           (event (cl-weave::run-test-case (cl-weave::root-suite) test)))
      (expect attempts :to-be 3)
      (expect (cl-weave::test-event-status event) :to-be :pass))))
