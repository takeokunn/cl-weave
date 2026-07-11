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

(defmacro suite-hook (suite hook)
  (ecase hook
    (before-all `(suite-before-all ,suite))
    (after-all `(suite-after-all ,suite))
    (before-each `(suite-before-each ,suite))
    (around-each `(suite-around-each ,suite))
    (after-each `(suite-after-each ,suite))))

(define-record-class test-case
  (name function focus skip-reason todo-reason retry timeout-ms concurrent
   tags depends-on execution-mode expected-failure-reason location))

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
  (status path condition assertion reason location elapsed-internal-time))

(define-record-class test-plan-entry
  (path status reason focused retry timeout-ms concurrent tags depends-on
   location))

(define-condition test-failure (error)
  ((detail :initarg :detail :reader failure-detail))
  (:report
   (lambda (condition stream)
     (let ((detail (failure-detail condition)))
       (format stream "Test assertion failed: ~S"
               (and detail (assertion-detail-form detail)))))))

(define-condition assertion-failure (test-failure) ())

(define-condition test-timeout (error)
  ((timeout-ms :initarg :timeout-ms :reader test-timeout-ms))
  (:report
   (lambda (condition stream)
     (format stream "Test exceeded its ~D ms timeout."
             (test-timeout-ms condition)))))

(define-condition expected-failure-missed (error)
  ((reason :initarg :reason :reader expected-failure-missed-reason))
  (:report
   (lambda (condition stream)
     (format stream "Test unexpectedly passed; expected failure: ~A"
             (expected-failure-missed-reason condition)))))

(defun root-suite ()
  (or *root-suite*
      (setf *root-suite*
            (make-suite :name "root"))))

(defun clear-tests ()
  (setf *root-suite* nil
        *current-suite* nil
        *named-suites* (make-hash-table :test #'equal))
  t)

(defun add-child (parent child)
  (let ((cell (list child)))
    (if (suite-children-tail parent)
        (setf (cdr (suite-children-tail parent)) cell
              (suite-children-tail parent) cell)
        (setf (suite-children parent) cell
              (suite-children-tail parent) cell)))
  child)

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

(defun register-suite (name thunk &key focus execution-mode skip-reason todo-reason)
  (let* ((parent (or *current-suite* (root-suite)))
         (suite (add-child parent
                           (apply #'make-suite
                                  (list
                                   :name name
                                   :parent parent
                                   :focus focus
                                   :execution-mode
                                   (normalize-execution-mode execution-mode)
                                   :skip-reason skip-reason
                                   :todo-reason todo-reason)))))
    (let ((*current-suite* suite))
      (funcall thunk))
    suite))

(defun register-test
    (name function &key focus skip-reason todo-reason retry timeout-ms concurrent
       tags depends-on execution-mode expected-failure-reason location)
  (let ((suite (or *current-suite* (root-suite))))
    (add-child suite
               (apply #'make-test-case
                      (list
                       :name name
                       :function function
                       :focus focus
                       :skip-reason skip-reason
                       :todo-reason todo-reason
                       :retry retry
                       :timeout-ms timeout-ms
                       :concurrent concurrent
                       :tags tags
                       :depends-on depends-on
                       :execution-mode
                       (normalize-execution-mode
                        (or execution-mode
                            (when concurrent :concurrent)))
                       :expected-failure-reason expected-failure-reason
                       :location location)))))

(defun register-before-all (function)
  (let* ((suite (or *current-suite* (root-suite)))
         (cell (list function)))
    (if (suite-before-all-tail suite)
        (setf (cdr (suite-before-all-tail suite)) cell
              (suite-before-all-tail suite) cell)
        (setf (suite-before-all suite) cell
              (suite-before-all-tail suite) cell))
    function))

(defun register-after-all (function)
  (let* ((suite (or *current-suite* (root-suite)))
         (cell (list function)))
    (if (suite-after-all-tail suite)
        (setf (cdr (suite-after-all-tail suite)) cell
              (suite-after-all-tail suite) cell)
        (setf (suite-after-all suite) cell
              (suite-after-all-tail suite) cell))
    function))

(defun register-before-each (function)
  (let* ((suite (or *current-suite* (root-suite)))
         (cell (list function)))
    (if (suite-before-each-tail suite)
        (setf (cdr (suite-before-each-tail suite)) cell
              (suite-before-each-tail suite) cell)
        (setf (suite-before-each suite) cell
              (suite-before-each-tail suite) cell))
    function))

(defun register-around-each (function)
  (let* ((suite (or *current-suite* (root-suite)))
         (cell (list function)))
    (if (suite-around-each-tail suite)
        (setf (cdr (suite-around-each-tail suite)) cell
              (suite-around-each-tail suite) cell)
        (setf (suite-around-each suite) cell
              (suite-around-each-tail suite) cell))
    function))

(defun register-after-each (function)
  (let* ((suite (or *current-suite* (root-suite)))
         (cell (list function)))
    (if (suite-after-each-tail suite)
        (setf (cdr (suite-after-each-tail suite)) cell
              (suite-after-each-tail suite) cell)
        (setf (suite-after-each suite) cell
              (suite-after-each-tail suite) cell))
    function))

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

(defun set-expected-assertion-count (count form)
  (require-assertion-counting form)
  (unless (and (integerp count) (not (minusp count)))
    (error "cl-weave: EXPECT-ASSERTIONS count must be a non-negative integer, got ~S."
           count))
  (setf *expected-assertion-count* count
        *expected-assertion-count-form* form)
  count)

(defun set-has-assertions-required (form)
  (require-assertion-counting form)
  (setf *has-assertions-required* t
        *has-assertions-form* form)
  t)

(defun assertion-count-failure-detail (form matcher actual expected)
  (make-assertion-detail-record form matcher actual expected nil nil))

(defun verify-assertion-counts ()
  (when (and *expected-assertion-count*
             (/= *assertion-count* *expected-assertion-count*))
    (signal-assertion-failure
     (assertion-count-failure-detail
      *expected-assertion-count-form*
      :assertions
      *assertion-count*
      *expected-assertion-count*)))
  (when (and *has-assertions-required*
             (zerop *assertion-count*))
    (signal-assertion-failure
     (assertion-count-failure-detail
      *has-assertions-form*
      :has-assertions
       *assertion-count*
      '(:minimum 1))))
  t)
