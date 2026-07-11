(in-package #:cl-weave/tests)

#+sb-thread
(describe "concurrent tests"
  (it "runs adjacent concurrent tests before either one completes"
    (let* ((root (cl-weave::make-suite :name "root"))
           (suite (cl-weave::add-child
                   root
                   (cl-weave::make-suite :name "concurrent" :parent root)))
           (mutex (sb-thread:make-mutex :name "cl-weave concurrent test log"))
           (events-log nil))
      (labels ((record (event)
                 (sb-thread:with-mutex (mutex)
                   (push event events-log)))
               (recorded-p (event)
                 (sb-thread:with-mutex (mutex)
                   (member event events-log)))
               (wait-until-recorded (event timeout-seconds)
                 (let ((deadline (+ (get-internal-real-time)
                                    (* timeout-seconds internal-time-units-per-second))))
                   (loop until (or (recorded-p event)
                                   (> (get-internal-real-time) deadline))
                         do (sleep 0.01))
                   (recorded-p event))))
        (cl-weave::add-child
         suite
         (cl-weave::make-test-case
          :name "first"
          :concurrent t
          :function (lambda ()
                      (record :first-start)
                      (unless (wait-until-recorded :second-start 1)
                        (error "second concurrent test did not start before first completed"))
                      (record :first-end))))
        (cl-weave::add-child
         suite
         (cl-weave::make-test-case
          :name "second"
          :concurrent t
          :function (lambda ()
                      (record :second-start)
                      (sleep 0.02)
                      (record :second-end))))
        (let* ((events (cl-weave::collect-events root))
               (ordered-log (reverse events-log)))
          (expect (mapcar #'cl-weave::test-event-status events)
                  :to-equal '(:pass :pass))
          (expect (member :second-start ordered-log) :not :to-be nil)
          (expect (member :first-end ordered-log) :not :to-be nil)
          (expect (mapcar #'cl-weave::test-event-path events)
                  :to-equal '(("concurrent" "first")
                              ("concurrent" "second")))))))

  (it "limits concurrent tests to max worker batches"
    (let* ((root (cl-weave::make-suite :name "root"))
           (suite (cl-weave::add-child
                   root
                   (cl-weave::make-suite :name "worker limit" :parent root)))
           (mutex (sb-thread:make-mutex :name "cl-weave max worker test log"))
           (events-log nil))
      (labels ((record (event)
                 (sb-thread:with-mutex (mutex)
                   (push event events-log))))
        (cl-weave::add-child
         suite
         (cl-weave::make-test-case
          :name "first"
          :concurrent t
          :function (lambda ()
                      (record :first-start)
                      (sleep 0.02)
                      (record :first-end))))
        (cl-weave::add-child
         suite
         (cl-weave::make-test-case
          :name "second"
          :concurrent t
          :function (lambda ()
                      (record :second-start)
                      (record :second-end))))
        (let ((events (cl-weave::collect-events root :max-workers 1)))
          (expect (mapcar #'cl-weave::test-event-status events)
                  :to-equal '(:pass :pass))
          (expect (reverse events-log)
                  :to-equal '(:first-start :first-end
                              :second-start :second-end))))))

  (it "rejects invalid max worker limits with stable errors"
    (let ((root (cl-weave::make-suite :name "root")))
      (dolist (workers '(0 -1 :many "2"))
        (expect (lambda ()
                  (cl-weave::collect-events root :max-workers workers))
                :to-throw
                "Max workers must be"))))

  (it "inherits concurrent execution mode from suites"
    (let* ((root (cl-weave::make-suite :name "root"))
           (suite (cl-weave::add-child
                   root
                   (cl-weave::make-suite
                    :name "concurrent suite"
                    :parent root
                    :execution-mode :concurrent)))
           (mutex (sb-thread:make-mutex :name "cl-weave suite concurrent test log"))
           (events-log nil))
      (labels ((record (event)
                 (sb-thread:with-mutex (mutex)
                   (push event events-log)))
               (recorded-p (event)
                 (sb-thread:with-mutex (mutex)
                   (member event events-log)))
               (wait-until-recorded (event timeout-seconds)
                 (let ((deadline (+ (get-internal-real-time)
                                    (* timeout-seconds internal-time-units-per-second))))
                   (loop until (or (recorded-p event)
                                   (> (get-internal-real-time) deadline))
                         do (sleep 0.01))
                   (recorded-p event))))
        (cl-weave::add-child
         suite
         (cl-weave::make-test-case
          :name "first"
          :function (lambda ()
                      (record :first-start)
                      (unless (wait-until-recorded :second-start 1)
                        (error "suite concurrent test did not start beside its sibling"))
                      (record :first-end))))
        (cl-weave::add-child
         suite
         (cl-weave::make-test-case
          :name "second"
          :function (lambda ()
                      (record :second-start)
                      (sleep 0.02)
                      (record :second-end))))
        (let ((events (cl-weave::collect-events root)))
          (expect (mapcar #'cl-weave::test-event-status events)
                  :to-equal '(:pass :pass))
          (expect (mapcar #'cl-weave::test-event-path events)
                  :to-equal '(("concurrent suite" "first")
                              ("concurrent suite" "second")))))))

  (it "keeps bail semantics sequential for concurrent tests"
    (let* ((root (cl-weave::make-suite :name "root"))
           (suite (cl-weave::add-child
                   root
                   (cl-weave::make-suite :name "concurrent bail" :parent root)))
           (events-log nil))
      (cl-weave::add-child
       suite
       (cl-weave::make-test-case
        :name "fails"
        :concurrent t
        :function (lambda ()
                    (push :first events-log)
                    (expect :actual :to-be :expected))))
      (cl-weave::add-child
       suite
       (cl-weave::make-test-case
        :name "must not run"
        :concurrent t
        :function (lambda ()
                    (push :second events-log))))
      (let ((events (cl-weave::collect-events root :bail t)))
        (expect (mapcar #'cl-weave::test-event-status events)
                :to-equal '(:fail))
        (expect events-log :to-equal '(:first))))))
