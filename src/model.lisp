(in-package #:cl-weave)

(defvar *root-suite* nil)
(defvar *current-suite* nil)
(defvar *test-context* nil)
(defvar *assertion-count* nil)
(defvar *expected-assertion-count* nil)
(defvar *expected-assertion-count-form* nil)
(defvar *has-assertions-required* nil)
(defvar *has-assertions-form* nil)

(defstruct suite
  name
  parent
  focus
  execution-mode
  skip-reason
  todo-reason
  (children '())
   (before-all '())
   (after-all '())
   (before-each '())
   (around-each '())
   (after-each '()))

(defstruct test-case
  name
  function
  focus
  skip-reason
  todo-reason
  retry
  timeout-ms
  concurrent
  execution-mode
  expected-failure-reason
  location)

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
  location
  elapsed-internal-time)

(defstruct test-plan-entry
  path
  status
  reason
  focused
  retry
  timeout-ms
  concurrent
  location)

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

(defun normalize-execution-mode (mode)
  (unless (member mode '(nil :concurrent :sequential))
    (error "cl-weave: execution mode must be NIL, :CONCURRENT, or :SEQUENTIAL, got ~S."
           mode))
  mode)

(defun register-suite (name thunk &key focus execution-mode skip-reason todo-reason)
  (let* ((parent (or *current-suite* (root-suite)))
         (suite (add-child parent (make-suite :name name
                                              :parent parent
                                              :focus focus
                                              :execution-mode (normalize-execution-mode execution-mode)
                                              :skip-reason skip-reason
                                              :todo-reason todo-reason))))
    (let ((*current-suite* suite))
      (funcall thunk))
    suite))

(defun register-test
    (name function &key focus skip-reason todo-reason retry timeout-ms concurrent
       execution-mode expected-failure-reason location)
  (let ((suite (or *current-suite* (root-suite))))
    (add-child suite (make-test-case :name name
                                     :function function
                                     :focus focus
                                     :skip-reason skip-reason
                                     :todo-reason todo-reason
                                     :retry retry
                                     :timeout-ms timeout-ms
                                     :concurrent concurrent
                                     :execution-mode (normalize-execution-mode
                                                      (or execution-mode
                                                          (when concurrent :concurrent)))
                                     :expected-failure-reason expected-failure-reason
                                     :location location))))

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

(defun register-around-each (function)
  (let ((suite (or *current-suite* (root-suite))))
    (setf (suite-around-each suite)
          (append (suite-around-each suite) (list function)))))

(defun register-after-each (function)
  (let ((suite (or *current-suite* (root-suite))))
    (setf (suite-after-each suite)
          (append (suite-after-each suite) (list function)))))

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
    (error "cl-weave: expect.assertions count must be a non-negative integer, got ~S."
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
  (make-assertion-detail
   :form form
   :matcher matcher
   :actual actual
   :expected expected
   :negated nil
   :pass nil))

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
