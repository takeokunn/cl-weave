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
  concurrent
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

(defun logic-variable-p (value)
  (and (symbolp value)
       (< 0 (length (symbol-name value)))
       (char= #\? (char (symbol-name value) 0))))

(defun logic-binding-value (variable bindings)
  (let ((binding (assoc variable bindings)))
    (if binding
        (values (cdr binding) t)
        (values nil nil))))

(defun logic-walk (value bindings)
  (if (logic-variable-p value)
      (multiple-value-bind (bound found-p) (logic-binding-value value bindings)
        (if found-p
            (logic-walk bound bindings)
            value))
      value))

(defun extend-logic-binding (variable value bindings)
  (acons variable value bindings))

(defun unify-logic-values (left right bindings)
  (let ((left (logic-walk left bindings))
        (right (logic-walk right bindings)))
    (cond
      ((and (consp left) (consp right))
       (multiple-value-bind (head-bindings head-ok-p)
           (unify-logic-values (first left) (first right) bindings)
         (if head-ok-p
             (unify-logic-values (rest left) (rest right) head-bindings)
             (values nil nil))))
      ((logic-variable-p left) (values (extend-logic-binding left right bindings) t))
      ((logic-variable-p right) (values (extend-logic-binding right left bindings) t))
      ((equal left right) (values bindings t))
      (t (values nil nil)))))

(defun resolve-logic-value (value bindings)
  (let ((value (logic-walk value bindings)))
    (if (consp value)
        (mapcar (lambda (part) (resolve-logic-value part bindings)) value)
        value)))

(defun normalize-logic-bindings (bindings)
  (mapcar (lambda (binding)
            (cons (car binding) (resolve-logic-value (cdr binding) bindings)))
          (reverse bindings)))

(defun logic-query (facts clauses &key limit)
  (unless (or (null limit) (and (integerp limit) (plusp limit)))
    (error "cl-weave: logic-query limit must be NIL or a positive integer, got ~S."
           limit))
  (labels ((below-limit-p (results)
             (or (null limit) (< (length results) limit)))
           (solve (pending bindings results)
             (cond
               ((not (below-limit-p results)) results)
               ((null pending) (cons (normalize-logic-bindings bindings) results))
               (t
                (let ((clause (first pending))
                      (rest-clauses (rest pending)))
                  (dolist (fact facts results)
                    (when (below-limit-p results)
                      (multiple-value-bind (next-bindings matched-p)
                          (unify-logic-values clause fact bindings)
                        (when matched-p
                          (setf results
                                (solve rest-clauses next-bindings results)))))))))))
    (nreverse (solve clauses nil nil))))

(defun test-plan-entry-facts (entry)
  (let ((path (test-plan-entry-path entry)))
    (append
     (list (list :test path)
           (list :status path (test-plan-entry-status entry))
           (list :retry path (test-plan-entry-retry entry)))
     (when (test-plan-entry-reason entry)
       (list (list :reason path (test-plan-entry-reason entry))))
     (when (test-plan-entry-focused entry)
       (list (list :focused path)))
     (when (test-plan-entry-timeout-ms entry)
       (list (list :timeout-ms path (test-plan-entry-timeout-ms entry))))
     (when (test-plan-entry-concurrent entry)
       (list (list :concurrent path)))
     (when (test-plan-entry-location entry)
       (list (list :location path (test-plan-entry-location entry)))))))

(defun test-plan-facts (plan)
  (mapcan #'test-plan-entry-facts plan))

(defun query-test-plan (plan clauses &key limit)
  (logic-query (test-plan-facts plan) clauses :limit limit))

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
    (name function &key focus skip-reason todo-reason retry timeout-ms concurrent
       expected-failure-reason location)
  (let ((suite (or *current-suite* (root-suite))))
    (add-child suite (make-test-case :name name
                                     :function function
                                     :focus focus
                                     :skip-reason skip-reason
                                     :todo-reason todo-reason
                                     :retry retry
                                     :timeout-ms timeout-ms
                                     :concurrent concurrent
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

(defun register-after-each (function)
  (let ((suite (or *current-suite* (root-suite))))
    (setf (suite-after-each suite)
          (append (suite-after-each suite) (list function)))))

(defun signal-assertion-failure (detail)
  (error 'assertion-failure :detail detail))
