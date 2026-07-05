(in-package #:cl-weave)

(defstruct matcher
  name
  function)

(defvar *matchers* (make-hash-table :test #'eq))

(defstruct mock-state
  implementation
  calls
  results)

(defvar *mock-states* (make-hash-table :test #'eq))
(defvar *snapshot-directory* #P"__snapshots__/")
(defvar *snapshot-file-name* "snapshots.sexp")
(defvar *update-snapshots* nil)

(defun register-matcher (name function)
  (unless (symbolp name)
    (error "cl-weave: matcher name must be a symbol, got ~S." name))
  (unless (functionp function)
    (error "cl-weave: matcher ~S must be registered with a function, got ~S."
           name
           function))
  (setf (gethash name *matchers*)
        (make-matcher :name name :function function))
  name)

(defun matcher-spec-name (spec)
  (cond
    ((and (consp spec) (symbolp (first spec))) (first spec))
    (t (error "cl-weave: matcher spec must start with a symbol name, got ~S." spec))))

(defun matcher-spec-function (spec)
  (cond
    ((and (consp spec) (functionp (second spec))) (second spec))
    (t (error "cl-weave: matcher spec ~S must provide a function as its second value." spec))))

(defun extend-expect (specs)
  (dolist (spec specs specs)
    (register-matcher (matcher-spec-name spec)
                      (matcher-spec-function spec))))

(eval-when (:compile-toplevel :load-toplevel :execute)
  (defun validate-matcher-lambda-list (actual expected operator)
    (unless (and (symbolp actual) (symbolp expected))
      (error "cl-weave: ~S matcher bindings must be symbols, got ~S."
             operator
             (list actual expected)))))

(defmacro defmatcher (name (actual expected) &body body)
  (unless (symbolp name)
    (error "cl-weave: defmatcher name must be a symbol, got ~S." name))
  (validate-matcher-lambda-list actual expected 'defmatcher)
  `(register-matcher ',name
                     (lambda (,actual ,expected)
                       ,@body)))

(defmacro expect-extend (&body definitions)
  `(extend-expect
    (list
     ,@(loop for definition in definitions
             collect
             (destructuring-bind (name (actual expected) &body body) definition
               (unless (symbolp name)
                 (error "cl-weave: expect-extend matcher name must be a symbol, got ~S." name))
               (validate-matcher-lambda-list actual expected 'expect-extend)
               `(list ',name
                      (lambda (,actual ,expected)
                        ,@body)))))))

(defmacro expect.extend (&body definitions)
  `(expect-extend ,@definitions))

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

(defun property-path-segments (path)
  (cond
    ((vectorp path) (coerce path 'list))
    ((listp path) path)
    (t (list path))))

(defun sequence-index-value (sequence index)
  (if (and (integerp index)
           (not (minusp index))
           (< index (length sequence)))
      (values (elt sequence index) t)
      (values nil nil)))

(defun alist-value (entries key)
  (let ((entry (assoc key entries :test #'equal)))
    (if entry
        (values (cdr entry) t)
        (values nil nil))))

(defun plist-value (plist key)
  (loop for tail = plist then (cddr tail)
        while (and (consp tail) (consp (cdr tail)))
        for plist-key = (first tail)
        for value = (second tail)
        when (eql plist-key key)
          return (values value t)
        finally (return (values nil nil))))

(defun object-slot-value (object slot-name)
  (if (symbolp slot-name)
      (handler-case
          (if (slot-exists-p object slot-name)
              (if (slot-boundp object slot-name)
                  (values (slot-value object slot-name) t)
                  (values nil t))
              (values nil nil))
        (error ()
          (values nil nil)))
      (values nil nil)))

(defun property-segment-value (value segment)
  (typecase value
    (hash-table (gethash segment value))
    (cons
     (cond
       ((integerp segment) (sequence-index-value value segment))
       ((consp (first value)) (alist-value value segment))
       (t (plist-value value segment))))
    (vector
     (sequence-index-value value segment))
    (t
     (object-slot-value value segment))))

(defun property-path-value (value path)
  (let ((current value))
    (dolist (segment (property-path-segments path) (values t current))
      (multiple-value-bind (next present-p)
          (property-segment-value current segment)
        (unless present-p
          (return (values nil nil)))
        (setf current next)))))

(defun normalize-property-expected (expected matcher)
  (unless (<= 1 (length expected) 2)
    (error "Matcher ~S expects a property path and optional expected value, got ~D values."
           matcher
           (length expected)))
  (values (first expected)
          (second expected)
          (= (length expected) 2)))

(defun normalize-close-to-expected (expected matcher)
  (unless (<= 1 (length expected) 2)
    (error "Matcher ~S expects an expected number and optional digit count, got ~D values."
           matcher
           (length expected)))
  (let ((target (first expected))
        (digits (if (= (length expected) 2)
                    (second expected)
                    2)))
    (unless (realp target)
      (error "Matcher ~S expects a real target value, got ~S." matcher target))
    (unless (and (integerp digits) (not (minusp digits)))
      (error "Matcher ~S expects a non-negative integer digit count, got ~S."
             matcher
             digits))
    (values target digits)))

(defun close-to-threshold (digits)
  (/ (expt 10 (- digits)) 2))

(defun close-to-report (actual target digits difference threshold)
  (list :value actual
        :expected-value target
        :num-digits digits
        :difference difference
        :threshold threshold))

(defun snapshot-string (value)
  (let ((*print-case* :downcase)
        (*print-circle* t)
        (*print-length* nil)
        (*print-level* nil)
        (*print-pretty* nil))
    (write-to-string value :escape t :readably nil)))

(defun snapshot-file-pathname ()
  (merge-pathnames *snapshot-file-name* *snapshot-directory*))

(defun snapshot-line-list (string)
  (with-input-from-string (stream string)
    (loop for line = (read-line stream nil nil)
          while line
          collect line)))

(defun snapshot-first-difference (expected actual)
  (let* ((expected-lines (snapshot-line-list expected))
         (actual-lines (snapshot-line-list actual))
         (line-count (max (length expected-lines) (length actual-lines))))
    (loop for offset below line-count
          for expected-line = (nth offset expected-lines)
          for actual-line = (nth offset actual-lines)
          unless (equal expected-line actual-line)
            return (list :line (1+ offset)
                         :expected expected-line
                         :actual actual-line))))

(defun snapshot-comparison-values (key actual-string entry)
  (let* ((file (namestring (snapshot-file-pathname)))
         (expected-present-p (not (null entry)))
         (expected-string (and entry (cdr entry)))
         (difference (when expected-present-p
                       (snapshot-first-difference expected-string actual-string)))
         (reason (if expected-present-p
                     :snapshot-mismatch
                     :missing-snapshot)))
    (values (list :snapshot-key key
                  :snapshot-file file
                  :value actual-string
                  :reason reason
                  :difference difference)
            (list :snapshot-key key
                  :snapshot-file file
                  :value expected-string
                  :present expected-present-p
                  :reason reason
                  :difference difference))))

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
      (t
       (multiple-value-bind (reported-actual reported-expected)
           (snapshot-comparison-values key actual-string entry)
         (values nil reported-actual reported-expected))))))

(defun thunk-throws-p (thunk)
  (and (functionp thunk)
       (handler-case
           (progn
             (funcall thunk)
             nil)
         (condition ()
           t))))

(defun thrown-condition (thunk matcher)
  (unless (functionp thunk)
    (error "Matcher ~S expects a function thunk, got ~S." matcher thunk))
  (handler-case
      (progn
        (funcall thunk)
        nil)
    (condition (condition)
      condition)))

(defun condition-class-designator-p (value)
  (or (typep value 'class)
      (and (symbolp value) (find-class value nil))))

(defun condition-class-designator-class (value)
  (if (typep value 'class)
      value
      (find-class value)))

(defun condition-report (condition)
  (when condition
    (list :threw t
          :condition-type (class-name (class-of condition))
          :message (princ-to-string condition))))

(defun no-condition-report ()
  '(:threw nil :condition-type nil :message nil))

(defun normalize-throw-expected (expected matcher)
  (cond
    ((null expected)
     (list :matcher :any))
    ((/= (length expected) 1)
     (error "Matcher ~S expects zero or one expected value, got ~D."
            matcher (length expected)))
    (t
     (let ((value (first expected)))
       (cond
         ((stringp value)
          (list :matcher :message-substring :value value))
         ((condition-class-designator-p value)
          (list :matcher :condition-type
                :value (class-name (condition-class-designator-class value))))
         ((functionp value)
          (list :matcher :predicate :value value))
         (t
          (error "Matcher ~S expected NIL, a condition class designator, string, or predicate, got ~S."
                 matcher value)))))))

(defun thrown-condition-matches-p (condition expectation)
  (case (getf expectation :matcher)
    (:any t)
    (:message-substring
     (not (null (search (getf expectation :value)
                        (princ-to-string condition)))))
    (:condition-type
     (typep condition (getf expectation :value)))
    (:predicate
     (not (null (funcall (getf expectation :value) condition))))
    (otherwise nil)))

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

(defun mop-required (matcher)
  (error "Matcher ~S requires SBCL MOP support." matcher))

(defun class-designator-class (designator matcher)
  (or (typecase designator
        (class designator)
        (symbol (find-class designator nil))
        (t (class-of designator)))
      (error "Matcher ~S cannot resolve class designator ~S." matcher designator)))

(defun class-slot-names (class matcher)
  (declare (ignorable matcher))
  #+sbcl
  (progn
    (sb-mop:finalize-inheritance class)
    (mapcar #'sb-mop:slot-definition-name
            (sb-mop:class-slots class)))
  #-sbcl
  (mop-required matcher))

(defun generic-function-designator-function (designator matcher)
  (let ((function (typecase designator
                    (symbol (when (fboundp designator)
                              (fdefinition designator)))
                    (function designator)
                    (t nil))))
    (unless (typep function 'generic-function)
      (error "Matcher ~S expects a generic function designator, got ~S."
             matcher designator))
    function))

(defun specializer-report-name (specializer)
  #+sbcl
  (cond
    ((typep specializer 'class)
     (class-name specializer))
    ((typep specializer 'sb-mop:eql-specializer)
     (list 'eql (sb-mop:eql-specializer-object specializer)))
    (t specializer))
  #-sbcl
  specializer)

(defun generic-function-specializer-lists (generic-function matcher)
  (declare (ignorable matcher))
  #+sbcl
  (progn
    (mapcar (lambda (method)
              (mapcar #'specializer-report-name
                      (sb-mop:method-specializers method)))
            (sb-mop:generic-function-methods generic-function)))
  #-sbcl
  (mop-required matcher))

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

(defun register-mock-result (state result)
  (setf (mock-state-results state)
        (append (mock-state-results state) (list result))))

(defun mock-state-for (mock)
  (or (gethash mock *mock-states*)
      (error "Value is not a cl-weave mock function: ~S" mock)))

(defun mock-thrown-result (condition)
  (list :type :throw
        :condition-type (class-name (class-of condition))
        :message (princ-to-string condition)))

(defun make-mock-function (&optional (implementation (lambda (&rest arguments)
                                                       (declare (ignore arguments))
                                                       nil)))
  (let* ((state (make-mock-state :implementation implementation
                                 :calls nil
                                 :results nil))
         (mock (lambda (&rest arguments)
                 (register-mock-call state arguments)
                 (handler-case
                     (let ((values (multiple-value-list
                                    (apply (mock-state-implementation state) arguments))))
                       (register-mock-result state
                                             (list :type :return
                                                   :value (first values)
                                                   :values values))
                       (values-list values))
                   (condition (condition)
                     (register-mock-result state (mock-thrown-result condition))
                     (error condition))))))
    (setf (gethash mock *mock-states*) state)
    mock))

(defun mock-calls (mock)
  (copy-tree (mock-state-calls (mock-state-for mock))))

(defun mock-results (mock)
  (copy-tree (mock-state-results (mock-state-for mock))))

(defun clear-mock (mock)
  (let ((state (mock-state-for mock)))
    (setf (mock-state-calls state) nil
          (mock-state-results state) nil))
  mock)

(defun mock-called-with-p (mock expected-arguments)
  (some (lambda (actual-arguments)
          (equal actual-arguments expected-arguments))
        (mock-calls mock)))

(defun mock-returned-with-p (mock expected-values)
  (some (lambda (result)
          (and (eq (getf result :type) :return)
               (equal (getf result :values) expected-values)))
        (mock-results mock)))

(defun one-based-index-expected (index matcher)
  (unless (and (integerp index) (plusp index))
    (error "cl-weave: ~A expects a positive integer index, got ~S."
           matcher
           index))
  index)

(defun expected-index-and-tail (expected matcher)
  (when (null expected)
    (error "cl-weave: ~A expects an index followed by expected values." matcher))
  (values (one-based-index-expected (first expected) matcher)
          (rest expected)))

(defun nth-list-entry (entries index)
  (let ((tail (nthcdr (1- index) entries)))
    (values (first tail) (not (null tail)))))

(defun last-list-entry (entries)
  (let ((tail (last entries)))
    (values (first tail) (not (null tail)))))

(defun return-results (results)
  (remove-if-not (lambda (result)
                   (eq (getf result :type) :return))
                 results))

(defun mock-report (mock)
  (let ((calls (mock-calls mock))
        (results (mock-results mock)))
    (list :call-count (length calls)
          :calls calls
          :result-count (length results)
          :results results
          :return-count (count :return results
                               :key (lambda (result) (getf result :type)))
          :throw-count (count :throw results
                              :key (lambda (result) (getf result :type))))))

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

(defmatcher :to-have-property (actual expected)
  (multiple-value-bind (path expected-value compare-value-p)
      (normalize-property-expected expected :to-have-property)
    (multiple-value-bind (present-p actual-value)
        (property-path-value actual path)
      (values (and present-p
                   (or (not compare-value-p)
                       (equalp actual-value expected-value)))
              (list :path (property-path-segments path)
                    :present present-p
                    :value actual-value)
              (append (list :path (property-path-segments path))
                      (when compare-value-p
                        (list :value expected-value)))))))

(defmatcher :to-be-close-to (actual expected)
  (multiple-value-bind (target digits)
      (normalize-close-to-expected expected :to-be-close-to)
    (let* ((threshold (close-to-threshold digits))
           (difference (when (realp actual)
                         (abs (- target actual)))))
      (values (and difference (< difference threshold))
              (close-to-report actual target digits difference threshold)
              (list :value target
                    :num-digits digits
                    :threshold threshold)))))

(defmatcher :to-be-greater-than (actual expected)
  (> actual (expected-one expected :to-be-greater-than)))

(defmatcher :to-be-greater-than-or-equal (actual expected)
  (>= actual (expected-one expected :to-be-greater-than-or-equal)))

(defmatcher :to-be-less-than (actual expected)
  (< actual (expected-one expected :to-be-less-than)))

(defmatcher :to-be-less-than-or-equal (actual expected)
  (<= actual (expected-one expected :to-be-less-than-or-equal)))

(defmatcher :to-throw (actual expected)
  (let* ((expectation (normalize-throw-expected expected :to-throw))
         (condition (thrown-condition actual :to-throw))
         (actual-report (or (condition-report condition)
                            (no-condition-report))))
    (values (and condition (thrown-condition-matches-p condition expectation))
            actual-report
            expectation)))

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

(defmatcher :to-have-slot (actual expected)
  (let* ((slot-name (expected-one expected :to-have-slot))
         (class (class-designator-class actual :to-have-slot))
         (slots (class-slot-names class :to-have-slot)))
    (values (not (null (member slot-name slots :test #'eq)))
            (list :class (class-name class)
                  :slots slots)
            (list :slot slot-name))))

(defmatcher :to-have-method-specialized-on (actual expected)
  (let* ((expected-specializers (expected-one expected :to-have-method-specialized-on))
         (generic-function
           (generic-function-designator-function actual :to-have-method-specialized-on))
         (methods
           (generic-function-specializer-lists generic-function
                                               :to-have-method-specialized-on)))
    (values (not (null (member expected-specializers methods :test #'equal)))
            (list :methods methods)
            (list :specializers expected-specializers))))

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
  (let ((report (mock-report actual)))
    (values (plusp (getf report :call-count))
            report
            '(:call-count (:min 1)))))

(defmatcher :to-have-been-called-times (actual expected)
  (let* ((times (expected-one expected :to-have-been-called-times))
         (report (mock-report actual)))
    (values (= (getf report :call-count) times)
            report
            (list :call-count times))))

(defmatcher :to-have-been-called-with (actual expected)
  (let ((report (mock-report actual)))
    (values (mock-called-with-p actual expected)
            report
            (list :arguments expected))))

(defmatcher :to-have-been-last-called-with (actual expected)
  (let ((report (mock-report actual)))
    (multiple-value-bind (arguments present-p)
        (last-list-entry (getf report :calls))
      (values (and present-p (equal arguments expected))
              report
              (list :last-arguments expected)))))

(defmatcher :to-have-been-nth-called-with (actual expected)
  (multiple-value-bind (index expected-arguments)
      (expected-index-and-tail expected :to-have-been-nth-called-with)
    (let ((report (mock-report actual)))
      (multiple-value-bind (arguments present-p)
          (nth-list-entry (getf report :calls) index)
        (values (and present-p (equal arguments expected-arguments))
                report
                (list :index index :arguments expected-arguments))))))

(defmatcher :to-have-returned (actual expected)
  (declare (ignore expected))
  (let ((report (mock-report actual)))
    (values (plusp (getf report :return-count))
            report
            '(:return-count (:min 1)))))

(defmatcher :to-have-returned-times (actual expected)
  (let* ((times (expected-one expected :to-have-returned-times))
         (report (mock-report actual)))
    (values (= (getf report :return-count) times)
            report
            (list :return-count times))))

(defmatcher :to-have-returned-with (actual expected)
  (let ((report (mock-report actual)))
    (values (mock-returned-with-p actual expected)
            report
            (list :values expected))))

(defmatcher :to-have-last-returned-with (actual expected)
  (let* ((report (mock-report actual))
         (returns (return-results (getf report :results))))
    (multiple-value-bind (result present-p) (last-list-entry returns)
      (values (and present-p (equal (getf result :values) expected))
              report
              (list :last-values expected)))))

(defmatcher :to-have-nth-returned-with (actual expected)
  (multiple-value-bind (index expected-values)
      (expected-index-and-tail expected :to-have-nth-returned-with)
    (let* ((report (mock-report actual))
           (returns (return-results (getf report :results))))
      (multiple-value-bind (result present-p)
          (nth-list-entry returns index)
        (values (and present-p (equal (getf result :values) expected-values))
                report
                (list :index index :values expected-values))))))

(defmatcher :to-have-thrown (actual expected)
  (declare (ignore expected))
  (let ((report (mock-report actual)))
    (values (plusp (getf report :throw-count))
            report
            '(:throw-count (:min 1)))))

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
