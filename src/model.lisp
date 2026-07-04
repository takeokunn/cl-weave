(in-package #:cl-weave)

(defvar *root-suite* nil)
(defvar *current-suite* nil)
(defvar *test-context* nil)

(defstruct suite
  name
  parent
  (children '())
  (before-each '())
  (after-each '()))

(defstruct test-case
  name
  function)

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
  elapsed-internal-time)

(define-condition test-failure (error)
  ((detail :initarg :detail :reader failure-detail))
  (:report (lambda (condition stream)
             (format stream "Test assertion failed: ~S"
                     (assertion-detail-form (failure-detail condition))))))

(define-condition assertion-failure (test-failure) ())

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

(defun register-suite (name thunk)
  (let* ((parent (or *current-suite* (root-suite)))
         (suite (add-child parent (make-suite :name name :parent parent))))
    (let ((*current-suite* suite))
      (funcall thunk))
    suite))

(defun register-test (name function)
  (let ((suite (or *current-suite* (root-suite))))
    (add-child suite (make-test-case :name name :function function))))

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
