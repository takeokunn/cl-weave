(in-package #:cl-weave)

(defstruct matcher
  name
  function)

(defvar *matchers* (make-hash-table :test #'eq))

(defstruct mock-state
  implementation
  calls)

(defvar *mock-states* (make-hash-table :test #'eq))

(defmacro defmatcher (name (actual expected) &body body)
  `(setf (gethash ,name *matchers*)
         (make-matcher
          :name ,name
          :function (lambda (,actual ,expected)
                      ,@body))))

(defun matcher-named (name)
  (or (gethash name *matchers*)
      (error "Unknown cl-weave matcher: ~S" name)))

(defun expected-one (expected matcher)
  (unless (= (length expected) 1)
    (error "Matcher ~S expects one expected value, got ~D." matcher (length expected)))
  (first expected))

(defun contains-value-p (container value)
  (typecase container
    (string (and (stringp value) (not (null (search value container)))))
    (list (not (null (member value container :test #'equal))))
    (vector (not (null (find value container :test #'equal))))
    (t nil)))

(defun sequence-length (value)
  (when (typep value 'sequence)
    (length value)))

(defun snapshot-string (value)
  (let ((*print-case* :downcase)
        (*print-circle* t)
        (*print-length* nil)
        (*print-level* nil)
        (*print-pretty* nil))
    (write-to-string value :escape t :readably nil)))

(defun thunk-throws-p (thunk)
  (and (functionp thunk)
       (handler-case
           (progn
             (funcall thunk)
             nil)
         (condition ()
           t))))

(defun expand-once (form)
  (macroexpand-1 form))

(defun register-mock-call (state arguments)
  (setf (mock-state-calls state)
        (append (mock-state-calls state) (list arguments))))

(defun mock-state-for (mock)
  (or (gethash mock *mock-states*)
      (error "Value is not a cl-weave mock function: ~S" mock)))

(defun make-mock-function (&optional (implementation (lambda (&rest arguments)
                                                       (declare (ignore arguments))
                                                       nil)))
  (let* ((state (make-mock-state :implementation implementation
                                 :calls nil))
         (mock (lambda (&rest arguments)
                 (register-mock-call state arguments)
                 (apply (mock-state-implementation state) arguments))))
    (setf (gethash mock *mock-states*) state)
    mock))

(defun mock-calls (mock)
  (copy-tree (mock-state-calls (mock-state-for mock))))

(defun clear-mock (mock)
  (setf (mock-state-calls (mock-state-for mock)) nil)
  mock)

(defun mock-called-with-p (mock expected-arguments)
  (some (lambda (actual-arguments)
          (equal actual-arguments expected-arguments))
        (mock-calls mock)))

(defmatcher :to-be (actual expected)
  (eql actual (expected-one expected :to-be)))

(defmatcher :to-equal (actual expected)
  (equal actual (expected-one expected :to-equal)))

(defmatcher :to-equalp (actual expected)
  (equalp actual (expected-one expected :to-equalp)))

(defmatcher :to-be-truthy (actual expected)
  (declare (ignore expected))
  (not (null actual)))

(defmatcher :to-be-falsy (actual expected)
  (declare (ignore expected))
  (null actual))

(defmatcher :to-be-null (actual expected)
  (declare (ignore expected))
  (null actual))

(defmatcher :to-be-defined (actual expected)
  (declare (ignore expected))
  (not (null actual)))

(defmatcher :to-satisfy (actual expected)
  (funcall (expected-one expected :to-satisfy) actual))

(defmatcher :to-be-type-of (actual expected)
  (typep actual (expected-one expected :to-be-type-of)))

(defmatcher :to-be-instance-of (actual expected)
  (typep actual (expected-one expected :to-be-instance-of)))

(defmatcher :to-contain (actual expected)
  (contains-value-p actual (expected-one expected :to-contain)))

(defmatcher :to-have-length (actual expected)
  (let ((length (sequence-length actual)))
    (and length (= length (expected-one expected :to-have-length)))))

(defmatcher :to-be-greater-than (actual expected)
  (> actual (expected-one expected :to-be-greater-than)))

(defmatcher :to-be-greater-than-or-equal (actual expected)
  (>= actual (expected-one expected :to-be-greater-than-or-equal)))

(defmatcher :to-be-less-than (actual expected)
  (< actual (expected-one expected :to-be-less-than)))

(defmatcher :to-be-less-than-or-equal (actual expected)
  (<= actual (expected-one expected :to-be-less-than-or-equal)))

(defmatcher :to-throw (actual expected)
  (declare (ignore expected))
  (thunk-throws-p actual))

(defmatcher :to-expand-to (actual expected)
  (equal (expand-once actual)
         (expected-one expected :to-expand-to)))

(defmatcher :to-match-inline-snapshot (actual expected)
  (string= (snapshot-string actual)
           (expected-one expected :to-match-inline-snapshot)))

(defmatcher :to-have-been-called (actual expected)
  (declare (ignore expected))
  (not (null (mock-calls actual))))

(defmatcher :to-have-been-called-times (actual expected)
  (= (length (mock-calls actual))
     (expected-one expected :to-have-been-called-times)))

(defmatcher :to-have-been-called-with (actual expected)
  (mock-called-with-p actual expected))

(defun normalize-expectation (tokens)
  (when (null tokens)
    (error "cl-weave: expect requires a matcher, for example (expect value :to-be expected)."))
  (if (eq (first tokens) :not)
      (values t (second tokens) (cddr tokens))
      (values nil (first tokens) (rest tokens))))

(defun assert-expectation (actual expectation form)
  (multiple-value-bind (negated matcher-name expected) (normalize-expectation expectation)
    (let* ((matcher (matcher-named matcher-name))
           (raw-pass (funcall (matcher-function matcher) actual expected))
           (pass (if negated (not raw-pass) raw-pass)))
      (unless pass
        (signal-assertion-failure
         (make-assertion-detail
          :form form
          :matcher matcher-name
          :actual actual
          :expected expected
          :negated negated
          :pass raw-pass)))
      pass)))
