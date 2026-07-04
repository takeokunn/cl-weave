(in-package #:cl-weave/tests)

(cl-weave:clear-tests)

(defvar *fixture-value* nil)
(defvar *fixture-events* nil)
(defun sample-size (value) (length value))

(defclass sample-widget () ())

(defmacro sample-unless (condition &body body)
  `(if ,condition
       nil
       (progn ,@body)))

(defmacro matcher-pass-cases (&body cases)
  `(progn
     ,@(loop for (name form) in cases
             collect `(it ,name ,form))))

(defun tree-contains-p (tree value)
  (cond
    ((eql tree value) t)
    ((consp tree)
     (or (tree-contains-p (car tree) value)
         (tree-contains-p (cdr tree) value)))
    (t nil)))

(describe "expect"
  (matcher-pass-cases
    ("to-be" (expect 2 :to-be 2))
    ("to-equal" (expect (list :a 1) :to-equal (list :a 1)))
    ("to-equalp" (expect "ok" :to-equalp "OK"))
    ("to-be-truthy" (expect :value :to-be-truthy))
    ("to-be-falsy" (expect nil :to-be-falsy))
    ("to-be-null" (expect nil :to-be-null))
    ("to-be-defined" (expect :value :to-be-defined))
    ("to-satisfy" (expect 4 :to-satisfy #'evenp))
    ("to-be-type-of" (expect 10 :to-be-type-of 'integer))
    ("to-be-instance-of"
     (expect (make-instance 'sample-widget) :to-be-instance-of 'sample-widget))
    ("to-contain list" (expect '(:a :b :c) :to-contain :b))
    ("to-contain vector" (expect #(:a :b :c) :to-contain :b))
    ("to-contain string" (expect "common-lisp" :to-contain "lisp"))
    ("to-have-length list" (expect '(:a :b :c) :to-have-length 3))
    ("to-have-length vector" (expect #(:a :b :c) :to-have-length 3))
    ("to-have-length string" (expect "abc" :to-have-length 3))
    ("to-be-greater-than" (expect 10 :to-be-greater-than 9))
    ("to-be-greater-than-or-equal" (expect 10 :to-be-greater-than-or-equal 10))
    ("to-be-less-than" (expect 9 :to-be-less-than 10))
    ("to-be-less-than-or-equal" (expect 10 :to-be-less-than-or-equal 10))
    ("to-throw" (expect (lambda () (error "boom")) :to-throw))
    ("to-throw rejects non-throwing thunk"
     (expect (lambda () (expect (lambda () :ok) :to-throw)) :to-throw))
    ("to-throw rejects non-function"
     (expect (lambda () (expect :not-a-function :to-throw)) :to-throw))
    ("to-match-inline-snapshot"
     (expect '(:ok 42) :to-match-inline-snapshot "(:ok 42)"))
    ("not" (expect 1 :not :to-be 2)))

  (it "signals assertion-failure with structured data"
    (handler-case
        (progn
          (expect 1 :to-be 2)
          (expect nil :to-be-truthy))
      (cl-weave:assertion-failure (condition)
        (let ((detail (cl-weave::failure-detail condition)))
          (expect (cl-weave::assertion-detail-matcher detail) :to-be :to-be)
          (expect (cl-weave::assertion-detail-actual detail) :to-be 1)
          (expect (cl-weave::assertion-detail-expected detail) :to-equal '(2)))))))

(describe "macros"
  (it-each ((1 2 3)
            (13 21 34))
      "adds ~A and ~A at macro expansion time"
      (left right total)
    (expect (+ left right) :to-be total))

  (it "expands expect into the assertion engine"
    (expect (macroexpand-1 '(expect (+ 1 1) :to-be 2))
            :to-satisfy
            (lambda (form)
              (tree-contains-p form 'cl-weave::assert-expectation))))

  (it "expands it-only into focused test registration"
    (expect (macroexpand-1 '(it-only "focused" (expect 1 :to-be 1)))
            :to-satisfy
            (lambda (form)
              (and (tree-contains-p form 'cl-weave::register-test)
                   (tree-contains-p form :focus)))))

  (it "compares a single macroexpansion step"
    (expect '(sample-unless ready (setf *fixture-value* :done))
            :to-expand-to
            '(if ready
                 nil
                 (progn (setf *fixture-value* :done))))))

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
    (expect *fixture-events* :to-equal '(:before-each :after-each :before-each :before-all))))

(describe "skips"
  (it-skip "does not run skipped tests" "documented gap")

  (it "reports skipped tests without failing the suite"
    (let* ((test (cl-weave::make-test-case
                  :name "skipped case"
                  :function (lambda () (error "should not run"))
                  :skip-reason "not implemented"))
           (event (cl-weave::run-test-case (cl-weave::root-suite) test)))
      (expect (cl-weave::test-event-status event) :to-be :skip)
      (expect (cl-weave::test-event-reason event) :to-equal "not implemented")
      (expect (cl-weave::passed-event-p event) :to-be-truthy))))

(describe "todos"
  (it-todo "documents pending work" "intentional")

  (it "reports todo tests without running their body"
    (let* ((test (cl-weave::make-test-case
                  :name "todo case"
                  :function (lambda () (error "should not run"))
                  :todo-reason "pending"))
           (event (cl-weave::run-test-case (cl-weave::root-suite) test)))
      (expect (cl-weave::test-event-status event) :to-be :todo)
      (expect (cl-weave::test-event-reason event) :to-equal "pending")
      (expect (cl-weave::passed-event-p event) :to-be-truthy))))

(describe "focus"
  (it "runs only focused tests when any focus exists"
    (let* ((root (cl-weave::make-suite :name "root"))
           (suite (cl-weave::add-child
                   root
                   (cl-weave::make-suite :name "focus" :parent root)))
           (events-log nil))
      (cl-weave::add-child
       root
       (cl-weave::make-test-case
        :name "outside"
        :function (lambda () (push :outside events-log))))
      (cl-weave::add-child
       suite
       (cl-weave::make-test-case
        :name "inside"
        :function (lambda () (push :inside events-log))
        :focus t))
      (let ((events (cl-weave::collect-events root)))
        (expect events-log :to-equal '(:inside))
        (expect (mapcar #'cl-weave::test-event-path events)
                :to-equal '(("focus" "inside")))))))

(describe "mocking"
  (it "restores symbol functions"
    (expect (sample-size '(a b c)) :to-be 3)
    (with-mocked-functions (((symbol-function 'sample-size)
                             (lambda (value)
                               (declare (ignore value))
                               99)))
      (expect (sample-size '(a b c)) :to-be 99))
    (expect (sample-size '(a b c)) :to-be 3)))

(describe "reporters"
  (it "prints AI-readable S-expression results"
    (let ((output (with-output-to-string (stream)
                      (cl-weave::report-sexp
                      (list (cl-weave::make-test-event
                             :status :pass
                             :path '("reporters" "prints")
                             :elapsed-internal-time 0)
                            (cl-weave::make-test-event
                             :status :skip
                             :path '("reporters" "skips")
                             :reason "example"
                             :elapsed-internal-time 0)
                            (cl-weave::make-test-event
                             :status :todo
                             :path '("reporters" "todos")
                             :reason "pending"
                             :elapsed-internal-time 0))
                      stream))))
      (expect output :to-contain ":CL-WEAVE/RESULTS")
      (expect output :to-contain ":SCHEMA-VERSION 2")
      (expect output :to-contain ":SKIPPED")
      (expect output :to-contain ":TODOS")
      (expect output :to-contain ":TODO"))))
