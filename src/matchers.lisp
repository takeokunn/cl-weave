(in-package #:cl-weave)

(defstruct matcher
  name
  function)

(defvar *matchers* (make-hash-table :test #'eq))

(defstruct mock-state
  implementation
  calls)

(defvar *mock-states* (make-hash-table :test #'eq))
(defvar *snapshot-directory* #P"__snapshots__/")
(defvar *snapshot-file-name* "snapshots.sexp")
(defvar *update-snapshots* nil)

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

(defun non-negative-real-expected (expected matcher label)
  (let ((value (expected-one expected matcher)))
    (unless (and (realp value) (not (minusp value)))
      (error "Matcher ~S expects a non-negative real ~A, got ~S."
             matcher label value))
    value))

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

(defun snapshot-file-pathname ()
  (merge-pathnames *snapshot-file-name* *snapshot-directory*))

(defun read-snapshot-file ()
  (let ((file (snapshot-file-pathname)))
    (when (probe-file file)
      (with-open-file (stream file :direction :input)
        (let ((*read-eval* nil))
          (read stream nil nil))))))

(defun write-snapshot-file (entries)
  (let ((file (snapshot-file-pathname)))
    (ensure-directories-exist file)
    (with-open-file (stream file
                            :direction :output
                            :if-exists :supersede
                            :if-does-not-exist :create)
      (let ((*print-case* :downcase)
            (*print-circle* t)
            (*print-pretty* t))
        (prin1 entries stream)
        (terpri stream)))))

(defun snapshot-entry (key entries)
  (assoc key entries :test #'string=))

(defun replace-snapshot-entry (key value entries)
  (let ((entry (snapshot-entry key entries)))
    (if entry
        (progn
          (setf (cdr entry) value)
          entries)
        (append entries (list (cons key value))))))

(defun snapshot-update-token-p (value)
  (member (string-downcase value)
          '("1" "true" "yes" "update")
          :test #'string=))

(defun snapshot-update-enabled-p ()
  (or *update-snapshots*
      #+sbcl
      (let ((value (sb-ext:posix-getenv "CL_WEAVE_UPDATE_SNAPSHOTS")))
        (and value (snapshot-update-token-p value)))
      #-sbcl
      nil))

(defun snapshot-key (expected)
  (let ((key (expected-one expected :to-match-snapshot)))
    (unless (stringp key)
      (error "Matcher :to-match-snapshot expects a string snapshot key."))
    key))

(defun snapshot-match-or-update-p (actual expected)
  (let* ((key (snapshot-key expected))
         (actual-string (snapshot-string actual))
         (entries (read-snapshot-file))
         (entry (snapshot-entry key entries)))
    (cond
      ((and entry (string= actual-string (cdr entry))) t)
      ((snapshot-update-enabled-p)
       (write-snapshot-file
        (replace-snapshot-entry key actual-string entries))
       t)
      (t nil))))

(defun thunk-throws-p (thunk)
  (and (functionp thunk)
       (handler-case
           (progn
             (funcall thunk)
             nil)
         (condition ()
           t))))

(defun current-bytes-consed ()
  #+sbcl
  (sb-ext:get-bytes-consed)
  #-sbcl
  nil)

(defun measure-thunk (thunk matcher)
  (unless (functionp thunk)
    (error "Matcher ~S expects a function thunk, got ~S." matcher thunk))
  (let* ((start-time (get-internal-real-time))
         (start-bytes (current-bytes-consed))
         (values (multiple-value-list (funcall thunk)))
         (end-time (get-internal-real-time))
         (end-bytes (current-bytes-consed))
         (elapsed-seconds (/ (- end-time start-time)
                             internal-time-units-per-second))
         (elapsed-ms (* elapsed-seconds 1000)))
    (list :elapsed-seconds (coerce elapsed-seconds 'double-float)
          :elapsed-ms (coerce elapsed-ms 'double-float)
          :bytes-consed (when (and start-bytes end-bytes)
                          (- end-bytes start-bytes))
          :values values)))

(defun measured-bytes-consed (measurement matcher)
  (let ((bytes (getf measurement :bytes-consed)))
    (unless bytes
      (error "Matcher ~S cannot read bytes consed on this Common Lisp implementation."
             matcher))
    bytes))

(defun matcher-result-values (matcher actual expected)
  (let ((values (multiple-value-list
                 (funcall (matcher-function matcher) actual expected))))
    (values (first values)
            (if (>= (length values) 2) (second values) actual)
            (if (>= (length values) 3) (third values) expected))))

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

(defmatcher :to-run-under-ms (actual expected)
  (let* ((max-ms (non-negative-real-expected expected :to-run-under-ms "millisecond threshold"))
         (measurement (measure-thunk actual :to-run-under-ms)))
    (values (< (getf measurement :elapsed-ms) max-ms)
            measurement
            (list :max-ms max-ms))))

(defmatcher :to-cons-less-than (actual expected)
  (let* ((max-bytes (non-negative-real-expected expected :to-cons-less-than "byte threshold"))
         (measurement (measure-thunk actual :to-cons-less-than))
         (bytes (measured-bytes-consed measurement :to-cons-less-than)))
    (values (< bytes max-bytes)
            measurement
            (list :max-bytes max-bytes))))

(defmatcher :to-expand-to (actual expected)
  (equal (expand-once actual)
         (expected-one expected :to-expand-to)))

(defmatcher :to-match-inline-snapshot (actual expected)
  (string= (snapshot-string actual)
           (expected-one expected :to-match-inline-snapshot)))

(defmatcher :to-match-snapshot (actual expected)
  (snapshot-match-or-update-p actual expected))

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
           (raw-pass nil)
           (reported-actual nil)
           (reported-expected nil)
           (pass nil))
      (multiple-value-setq (raw-pass reported-actual reported-expected)
        (matcher-result-values matcher actual expected))
      (setf pass
            (if negated (not raw-pass) raw-pass))
      (unless pass
        (signal-assertion-failure
         (make-assertion-detail
          :form form
          :matcher matcher-name
          :actual reported-actual
          :expected reported-expected
          :negated negated
          :pass raw-pass)))
      pass)))
