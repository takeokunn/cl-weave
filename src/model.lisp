(in-package #:cl-weave)

(defvar *root-suite* nil)
(defvar *current-suite* nil)
(defvar *named-suites* (make-hash-table :test #'equal))
(defvar *test-context* nil)
(defvar *assertion-count* nil)
(defvar *expected-assertion-count* nil)
(defvar *expected-assertion-count-form* nil)
(defvar *has-assertions-required* nil)
(defvar *has-assertions-form* nil)

(defmacro define-record-class (name slots)
  "Define a CLOS data record and its public constructor and predicate."
  (let ((constructor (intern (format nil "MAKE-~A" name)))
        (predicate (intern (format nil "~A-P" name))))
    `(progn
       (defclass ,name ()
         ,(loop for slot in slots
                for initarg = (intern (symbol-name slot) :keyword)
                for accessor = (intern (format nil "~A-~A" name slot))
                collect `(,slot
                          :initarg ,initarg
                          :initform nil
                          :accessor ,accessor)))
       (defun ,constructor (&rest initargs)
         (apply #'make-instance ',name initargs))
       (defun ,predicate (value)
         (typep value ',name)))))

(define-record-class suite
  (name parent focus execution-mode skip-reason todo-reason
   children children-tail
   before-all before-all-tail
   after-all after-all-tail
   before-each before-each-tail
   around-each around-each-tail
   after-each after-each-tail))

(defmethod print-object ((suite suite) stream)
  (print-unreadable-object (suite stream :type t)
    (format stream "~S :children ~D"
            (suite-name suite)
            (length (suite-children suite)))))

(defmacro suite-hook (suite hook)
  (ecase hook
    (before-all `(suite-before-all ,suite))
    (after-all `(suite-after-all ,suite))
    (before-each `(suite-before-each ,suite))
    (around-each `(suite-around-each ,suite))
    (after-each `(suite-after-each ,suite))))

(define-record-class test-case
  (name function focus skip-reason todo-reason retry timeout-ms execution-mode
   expected-failure-reason location))

(defmethod print-object ((test test-case) stream)
  (print-unreadable-object (test stream :type t)
    (format stream "~S :focus ~S"
            (test-case-name test)
            (test-case-focus test))))

(define-record-class assertion-detail
  (form matcher actual expected negated pass))

(defun make-assertion-detail-record
    (form matcher actual expected negated pass)
  (make-assertion-detail
   :form form
   :matcher matcher
   :actual actual
   :expected expected
   :negated negated
   :pass pass))

(define-record-class test-event
  (status path condition secondary-conditions assertion reason location
   elapsed-internal-time))

(define-record-class test-plan-entry
  (path status reason focused retry timeout-ms concurrent location))

(define-record-class benchmark-result
  (samples iterations warmup))

(defun report-test-failure (condition stream)
  (let ((detail (failure-detail condition)))
    (format stream "Test assertion failed: ~S"
            (and detail (assertion-detail-form detail)))))

(define-condition test-failure (error)
  ((detail :initarg :detail :reader failure-detail))
  (:report report-test-failure))

(define-condition assertion-failure (test-failure) ())

(defun report-test-timeout (condition stream)
  (format stream "Test exceeded its ~D ms timeout."
          (test-timeout-ms condition)))

(define-condition test-timeout (error)
  ((timeout-ms :initarg :timeout-ms :reader test-timeout-ms))
  (:report report-test-timeout))

(defun report-expected-failure-missed (condition stream)
  (format stream "Test unexpectedly passed; expected failure: ~A"
          (expected-failure-missed-reason condition)))

(define-condition expected-failure-missed (error)
  ((reason :initarg :reason :reader expected-failure-missed-reason))
  (:report report-expected-failure-missed))

(defun report-hook-failure (condition stream)
  (format stream "~(~A~) hook failed (~D condition~:P): ~{~A~^; ~}"
          (hook-failure-phase condition)
          (length (hook-failure-causes condition))
          (hook-failure-causes condition)))

(define-condition hook-failure (error)
  ((phase :initarg :phase :reader hook-failure-phase)
   (causes :initarg :causes :reader hook-failure-causes))
  (:report report-hook-failure))

(defun root-suite ()
  (or *root-suite*
      (setf *root-suite*
            (make-suite :name "root"))))

(defun current-or-root-suite ()
  (or *current-suite*
      (root-suite)))

(defun clear-tests ()
  (setf *root-suite* nil
        *current-suite* nil
        *named-suites* (make-hash-table :test #'equal))
  t)

(defmacro append-to-tail-list (suite head tail value)
  (let ((suite-var (gensym "SUITE"))
        (value-var (gensym "VALUE"))
        (cell-var (gensym "CELL")))
    `(let* ((,suite-var ,suite)
            (,value-var ,value)
            (,cell-var (list ,value-var)))
       (if (,tail ,suite-var)
           (setf (cdr (,tail ,suite-var)) ,cell-var
                 (,tail ,suite-var) ,cell-var)
           (setf (,head ,suite-var) ,cell-var
                 (,tail ,suite-var) ,cell-var))
       ,value-var)))

(defmacro define-tail-registration (name head tail)
  `(defun ,name (function)
     (append-to-tail-list (current-or-root-suite)
                          ,head
                          ,tail
                          function)))

(defun add-child (parent child)
  (append-to-tail-list parent suite-children suite-children-tail child))

(defun normalize-execution-mode (mode)
  (unless (member mode '(nil :concurrent :sequential))
    (error "cl-weave: execution mode must be NIL, :CONCURRENT, or :SEQUENTIAL, got ~S."
           mode))
  mode)

(defun named-suite-key (name)
  (typecase name
    (symbol (string-upcase (symbol-name name)))
    (string (string-upcase name))
    (t name)))

(defun suite-registration-initargs
    (name parent focus execution-mode skip-reason todo-reason)
  (list :name name
        :parent parent
        :focus focus
        :execution-mode (normalize-execution-mode execution-mode)
        :skip-reason skip-reason
        :todo-reason todo-reason))

(defun test-registration-initargs
    (name function focus skip-reason todo-reason retry timeout-ms
     execution-mode expected-failure-reason location)
  (list :name name
        :function function
        :focus focus
        :skip-reason skip-reason
        :todo-reason todo-reason
        :retry retry
        :timeout-ms timeout-ms
        :execution-mode (normalize-execution-mode execution-mode)
        :expected-failure-reason expected-failure-reason
        :location location))

(defun register-suite (name thunk &key focus execution-mode skip-reason todo-reason)
  (let* ((parent (current-or-root-suite))
         (suite (add-child parent
                           (apply #'make-suite
                                  (suite-registration-initargs
                                   name parent focus execution-mode
                                   skip-reason todo-reason)))))
    (let ((*current-suite* suite))
      (funcall thunk))
    suite))

(defun register-test
  (name function &key focus skip-reason todo-reason retry timeout-ms
       execution-mode expected-failure-reason location)
  (let ((suite (current-or-root-suite)))
    (add-child suite
               (apply #'make-test-case
                      (test-registration-initargs
                       name function focus skip-reason todo-reason retry
                       timeout-ms execution-mode expected-failure-reason
                       location)))))

(define-tail-registration register-before-all suite-before-all suite-before-all-tail)
(define-tail-registration register-after-all suite-after-all suite-after-all-tail)
(define-tail-registration register-before-each suite-before-each suite-before-each-tail)
(define-tail-registration register-around-each suite-around-each suite-around-each-tail)
(define-tail-registration register-after-each suite-after-each suite-after-each-tail)

(defun signal-assertion-failure (detail)
  (error 'assertion-failure :detail detail))

(defun assertion-counting-active-p ()
  (integerp *assertion-count*))

(defun record-assertion ()
  (when (assertion-counting-active-p)
    (incf *assertion-count*))
  t)

(defun require-assertion-counting (form)
  (unless (assertion-counting-active-p)
    (error "cl-weave: ~S must be used inside a running test." form)))

(defmacro with-assertion-counting ((form) &body body)
  `(progn
     (require-assertion-counting ,form)
     ,@body))

(defun set-expected-assertion-count (count form)
  (with-assertion-counting (form)
    (unless (and (integerp count) (not (minusp count)))
      (error "cl-weave: EXPECT-ASSERTIONS count must be a non-negative integer, got ~S."
             count))
    (setf *expected-assertion-count* count
          *expected-assertion-count-form* form)
    count))

(defun set-has-assertions-required (form)
  (with-assertion-counting (form)
    (setf *has-assertions-required* t
          *has-assertions-form* form)
    t))

(defun assertion-count-failure-detail (form matcher actual expected)
  (make-assertion-detail-record form matcher actual expected nil nil))

(defun signal-assertion-count-failure (form matcher actual expected)
  (signal-assertion-failure
   (assertion-count-failure-detail form matcher actual expected)))

(defun verify-assertion-counts ()
  (when (and *expected-assertion-count*
             (/= *assertion-count* *expected-assertion-count*))
    (signal-assertion-count-failure *expected-assertion-count-form*
                                    :assertions
                                    *assertion-count*
                                    *expected-assertion-count*))
  (when (and *has-assertions-required*
             (zerop *assertion-count*))
    (signal-assertion-count-failure *has-assertions-form*
                                    :has-assertions
                                    *assertion-count*
                                    '(:minimum 1)))
  t)
