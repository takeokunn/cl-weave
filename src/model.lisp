(in-package #:cl-weave)

(defvar *root-suite* nil)
(defvar *current-suite* nil)
(defvar *test-context* nil)

(defstruct suite
  name
  parent
  focus
  skip-reason
  todo-reason
  (children '())
  (before-all '())
  (after-all '())
  (before-each '())
  (after-each '()))

(defstruct test-case
  name
  function
  focus
  skip-reason
  todo-reason
  retry
  timeout-ms
  expected-failure-reason)

(defstruct assertion-detail
  form
  matcher
  actual
  expected
  negated
  pass)

(defstruct test-event
  status
  path
  condition
  assertion
  reason
  elapsed-internal-time)

(defstruct test-plan-entry
  path
  status
  reason
  focused
  retry
  timeout-ms)

(define-condition test-failure (error)
  ((detail :initarg :detail :reader failure-detail))
  (:report (lambda (condition stream)
             (format stream "Test assertion failed: ~S"
                     (assertion-detail-form (failure-detail condition))))))

(define-condition assertion-failure (test-failure) ())

(define-condition test-timeout (error)
  ((timeout-ms :initarg :timeout-ms :reader test-timeout-ms))
  (:report (lambda (condition stream)
             (format stream "Test exceeded timeout of ~Dms"
                     (test-timeout-ms condition)))))

(define-condition expected-failure-missed (error)
  ((reason :initarg :reason :reader expected-failure-missed-reason))
  (:report (lambda (condition stream)
             (format stream "Expected test to fail, but it passed: ~A"
                     (expected-failure-missed-reason condition)))))

(defun root-suite ()
  (or *root-suite*
      (setf *root-suite* (make-suite :name "root"))))

(defun clear-tests ()
  (setf *root-suite* nil
        *current-suite* nil)
  t)

(defun add-child (parent child)
  (setf (suite-children parent)
        (append (suite-children parent) (list child)))
  child)

(defun register-suite (name thunk &key focus skip-reason todo-reason)
  (let* ((parent (or *current-suite* (root-suite)))
         (suite (add-child parent (make-suite :name name
                                              :parent parent
                                              :focus focus
                                              :skip-reason skip-reason
                                              :todo-reason todo-reason))))
    (let ((*current-suite* suite))
      (funcall thunk))
    suite))

(defun register-test
    (name function &key focus skip-reason todo-reason retry timeout-ms expected-failure-reason)
  (let ((suite (or *current-suite* (root-suite))))
    (add-child suite (make-test-case :name name
                                     :function function
                                     :focus focus
                                     :skip-reason skip-reason
                                     :todo-reason todo-reason
                                     :retry retry
                                     :timeout-ms timeout-ms
                                     :expected-failure-reason expected-failure-reason))))

(defun register-before-all (function)
  (let ((suite (or *current-suite* (root-suite))))
    (setf (suite-before-all suite)
          (append (suite-before-all suite) (list function)))))

(defun register-after-all (function)
  (let ((suite (or *current-suite* (root-suite))))
    (setf (suite-after-all suite)
          (append (suite-after-all suite) (list function)))))

(defun register-before-each (function)
  (let ((suite (or *current-suite* (root-suite))))
    (setf (suite-before-each suite)
          (append (suite-before-each suite) (list function)))))

(defun register-after-each (function)
  (let ((suite (or *current-suite* (root-suite))))
    (setf (suite-after-each suite)
          (append (suite-after-each suite) (list function)))))

(defun signal-assertion-failure (detail)
  (error 'assertion-failure :detail detail))
