(in-package #:cl-weave/tests)

(cl-weave:clear-tests)

(defvar *fixture-value* nil)
(defun sample-size (value) (length value))

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
    ("to-satisfy" (expect 4 :to-satisfy #'evenp))
    ("to-be-type-of" (expect 10 :to-be-type-of 'integer))
    ("to-contain list" (expect '(:a :b :c) :to-contain :b))
    ("to-contain vector" (expect #(:a :b :c) :to-contain :b))
    ("to-contain string" (expect "common-lisp" :to-contain "lisp"))
    ("to-be-greater-than" (expect 10 :to-be-greater-than 9))
    ("to-be-greater-than-or-equal" (expect 10 :to-be-greater-than-or-equal 10))
    ("to-be-less-than" (expect 9 :to-be-less-than 10))
    ("to-be-less-than-or-equal" (expect 10 :to-be-less-than-or-equal 10))
    ("to-throw" (expect (lambda () (error "boom")) :to-throw))
    ("to-throw rejects non-throwing thunk"
     (expect (lambda () (expect (lambda () :ok) :to-throw)) :to-throw))
    ("to-throw rejects non-function"
     (expect (lambda () (expect :not-a-function :to-throw)) :to-throw))
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
              (tree-contains-p form 'cl-weave::assert-expectation)))))

  (it "compares a single macroexpansion step"
    (expect '(sample-unless ready (setf *fixture-value* :done))
            :to-expand-to
            '(if ready
                 nil
                 (progn (setf *fixture-value* :done)))))

(describe "fixtures"
  (before-each
    (setf *fixture-value* 41)
    (setf (gethash :trace *test-context*) '(:before)))

  (after-each
    (setf *fixture-value* nil))

  (it "runs before-each with dynamic context"
    (expect *fixture-value* :to-be 41)
    (expect (gethash :trace *test-context*) :to-equal '(:before))
    (incf *fixture-value*)
    (expect *fixture-value* :to-be 42)))

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
                            :elapsed-internal-time 0))
                     stream))))
      (expect output :to-contain ":CL-WEAVE/RESULTS")
      (expect output :to-contain ":SCHEMA-VERSION"))))
