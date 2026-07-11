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
                  :tags '(:unit)
                  :depends-on '("setup")
                  :location '(:file "example.lisp" :line 12)))
           (suite (cl-weave::make-suite
                   :name "model"
                   :children (list test))))
      (expect suite :to-satisfy #'cl-weave::suite-p)
      (expect test :to-satisfy #'cl-weave::test-case-p)
      (expect (cl-weave::suite-children suite) :to-equal (list test))
      (expect (cl-weave::test-case-tags test) :to-equal '(:unit))
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
          do (expect (princ-to-string condition) :to-contain fragment)))

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
