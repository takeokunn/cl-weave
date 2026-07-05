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

