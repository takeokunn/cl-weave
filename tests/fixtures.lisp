(in-package #:cl-weave/tests)

(describe "fixtures"
  (before-all
    (setf *fixture-events* (list :before-all)))

  (before-each
    (setf *fixture-value* 41)
    (push :before-each *fixture-events*)
    (setf (gethash :trace *test-context*) '(:before)))

  (after-each
    (push :after-each *fixture-events*)
    (setf *fixture-value* nil))

  (after-all
    (setf *fixture-events* nil))

  (it "runs before-each with dynamic context"
    (expect *fixture-events* :to-equal '(:before-each :before-all))
    (expect *fixture-value* :to-be 41)
    (expect (gethash :trace *test-context*) :to-equal '(:before))
    (incf *fixture-value*)
    (expect *fixture-value* :to-be 42))

  (it "keeps before-all state across cases"
    (expect *fixture-events* :to-equal '(:before-each :after-each :before-each :before-all)))

  (it "keeps camelCase fixture aliases out of the public package"
    (dolist (name '("BEFOREALL" "AFTERALL" "BEFOREEACH" "AFTEREACH"))
      (multiple-value-bind (symbol status) (find-symbol name "CL-WEAVE")
        (declare (ignore symbol))
        (expect-not status :to-be :external))))

  (it "represents suite and test metadata as readable structures"
    (let* ((test (cl-weave::make-test-case
                  :name "works"
                  :function (lambda () t)
                  :focus t
                  :location '(:file "example.lisp" :line 12)))
           (suite (cl-weave::make-suite
                   :name "model"
                   :children (list test))))
      (expect suite :to-satisfy #'cl-weave::suite-p)
      (expect test :to-satisfy #'cl-weave::test-case-p)
      (expect (cl-weave::suite-children suite) :to-equal (list test))
      (expect (princ-to-string suite) :to-contain "model")
      (expect (princ-to-string suite) :to-contain ":children 1")
      (expect (princ-to-string test) :to-contain "works")
      (expect (princ-to-string test) :to-contain ":focus T")))

  (it "reports model conditions with actionable context"
    (loop for (condition fragment)
            in (list
                (list (make-condition
                       'cl-weave::assertion-failure
                       :detail (cl-weave::make-assertion-detail
                                :form '(expect value :to-be 42)))
                      "EXPECT VALUE :TO-BE 42")
                (list (make-condition 'cl-weave:test-timeout :timeout-ms 250)
                      "250 ms timeout")
                (list (make-condition
                       'cl-weave:expected-failure-missed
                       :reason "known defect")
                      "known defect"))
          do (let ((*package* (find-package '#:cl-weave/tests)))
               ;; The pretty printer may wrap long assertion forms.
               (expect (normalize-command-document-text
                        (princ-to-string condition))
                       :to-contain fragment))))

  (it "wraps each test body with around-each continuations"
    (let ((root (cl-weave::make-suite :name "root"))
          (events nil))
      (let ((*fixture-value* :outer)
            (cl-weave::*current-suite* root)
            (cl-weave::*root-suite* root))
        (cl-weave::register-suite
         "around"
         (lambda ()
           (before-each
             (push :before events))
           (around-each (next)
             (push (list :enter *fixture-value*) events)
             (let ((*fixture-value* :inner))
               (funcall next))
             (push (list :exit *fixture-value*) events))
           (after-each
             (push :after events))
           (it "case"
             (push (list :body *fixture-value*) events)))))
      (cl-weave::collect-events root)
      (expect (reverse events)
              :to-equal '(:before (:enter 41) (:body :inner) (:exit 41) :after))))

  (it "runs around-each cleanup before after-each when body fails"
    (let ((root (cl-weave::make-suite :name "root"))
          (events nil))
      (let ((cl-weave::*current-suite* root)
            (cl-weave::*root-suite* root))
        (cl-weave::register-suite
         "around cleanup"
         (lambda ()
           (around-each (next)
             (unwind-protect
                  (funcall next)
               (push :around-cleanup events)))
           (after-each
             (push :after events))
           (it "case"
             (error "boom")))))
      (let ((result (cl-weave::collect-events root)))
        (expect (mapcar #'cl-weave::test-event-status result) :to-equal '(:error)))
      (expect (reverse events) :to-equal '(:around-cleanup :after)))))

  (it "normalizes an around-each wrapper error as a hook failure"
    (let* ((cause (make-condition 'simple-error :format-control "wrapper failed"))
           (suite
             (cl-weave::make-suite
              :name "around wrapper"
              :around-each
              (list (lambda (next)
                      (declare (ignore next))
                      (error cause)))))
           (test (cl-weave::make-test-case :name "case" :function (lambda () t)))
           (event (cl-weave::run-test-case suite test))
           (condition (cl-weave::test-event-condition event)))
      (expect (cl-weave::test-event-status event) :to-be :error)
      (expect condition :to-be-instance-of 'cl-weave:hook-failure)
      (expect (cl-weave:hook-failure-phase condition) :to-be :around-each)
      (expect (cl-weave:hook-failure-causes condition) :to-equal (list cause))))

  (it "does not wrap a test error propagated through around-each"
    (let* ((cause (make-condition 'simple-error :format-control "test failed"))
           (suite
             (cl-weave::make-suite
              :name "around continuation"
              :around-each (list (lambda (next) (funcall next)))))
           (test
             (cl-weave::make-test-case
              :name "case"
              :function (lambda () (error cause))))
           (event (cl-weave::run-test-case suite test)))
      (expect (cl-weave::test-event-status event) :to-be :error)
      (expect (cl-weave::test-event-condition event) :to-be cause)))

(describe "fixture failures"
  (it "aggregates before-each failures without running the body"
    (let ((log nil))
      (let* ((suite
               (cl-weave::make-suite
                :name "setup"
                :before-each
                (list (lambda ()
                        (push :first log)
                        (error "first setup"))
                      (lambda ()
                        (push :second log)
                        (error "second setup")))))
             (test
               (cl-weave::make-test-case
                :name "case"
                :function (lambda () (push :body log))))
             (event (cl-weave::run-test-case suite test))
             (condition (cl-weave::test-event-condition event)))
        (expect (cl-weave::test-event-status event) :to-be :error)
        (expect (cl-weave:hook-failure-phase condition) :to-be :before-each)
        (expect (length (cl-weave:hook-failure-causes condition)) :to-be 2)
        (expect log :to-equal '(:second :first)))))

  (it "preserves a primary assertion failure and records every cleanup failure"
    (let* ((cleanup-log nil)
           (suite
             (cl-weave::make-suite
              :name "cleanup"
              :after-each
              (list (lambda ()
                      (push :first cleanup-log)
                      (error "first cleanup"))
                    (lambda ()
                      (push :second cleanup-log)
                      (error "second cleanup")))))
           (test
             (cl-weave::make-test-case
              :name "primary"
              :function
              (lambda ()
                (error 'cl-weave:assertion-failure
                       :detail (cl-weave::make-assertion-detail
                                :form '(expect nil :to-be t))))))
           (event (cl-weave::run-test-case suite test)))
      (expect (cl-weave::test-event-status event) :to-be :fail)
      (expect (cl-weave::test-event-condition event)
              :to-satisfy (lambda (condition)
                            (typep condition 'cl-weave:assertion-failure)))
      (expect cleanup-log :to-equal '(:first :second))
      (expect (length (cl-weave::test-event-secondary-conditions event))
              :to-be 2)))

  (it "represents an otherwise unhandled after-each failure"
    (let* ((suite
             (cl-weave::make-suite
              :name "cleanup"
              :after-each (list (lambda () (error "cleanup")))))
           (test (cl-weave::make-test-case :name "case" :function (lambda () t)))
           (event (cl-weave::run-test-case suite test))
           (condition (cl-weave::test-event-condition event)))
      (expect (cl-weave::test-event-status event) :to-be :error)
      (expect condition
              :to-satisfy (lambda (value)
                            (typep value 'cl-weave:hook-failure)))
      (expect (cl-weave:hook-failure-phase condition) :to-be :after-each)
      (expect (length (cl-weave:hook-failure-causes condition)) :to-be 1)))

  (it "turns suite hook failures into events and still runs all cleanup hooks"
    (let ((root (cl-weave::make-suite :name "root"))
          (log nil))
      (let ((cl-weave::*current-suite* root)
            (cl-weave::*root-suite* root))
        (cl-weave::register-suite
         "broken suite"
         (lambda ()
           (before-all
             (push :before log)
             (error "setup"))
           (after-all
             (push :after-first log)
             (error "first teardown"))
           (after-all
             (push :after-second log)
             (error "second teardown"))
           (it "must not run" (push :body log)))))
      (let* ((events (cl-weave::collect-events root))
             (conditions (mapcar #'cl-weave::test-event-condition events)))
        (expect (mapcar #'cl-weave::test-event-status events)
                :to-equal '(:error :error))
        (expect (mapcar #'cl-weave:hook-failure-phase conditions)
                :to-equal '(:before-all :after-all))
        (expect (length (cl-weave:hook-failure-causes (second conditions)))
                :to-be 2)
        (expect log :to-equal '(:after-first :after-second :before))))))
