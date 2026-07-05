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

(defun logic-occurs-in-p (variable value bindings)
  (let ((value (logic-walk value bindings)))
    (cond
      ((eql variable value) t)
      ((consp value)
       (or (logic-occurs-in-p variable (car value) bindings)
           (logic-occurs-in-p variable (cdr value) bindings)))
      (t nil))))

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
      ((logic-variable-p left)
       (if (logic-occurs-in-p left right bindings)
           (values nil nil)
           (values (extend-logic-binding left right bindings) t)))
      ((logic-variable-p right)
       (if (logic-occurs-in-p right left bindings)
           (values nil nil)
           (values (extend-logic-binding right left bindings) t)))
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

(defun split-logic-where-forms (forms)
  (let ((limit nil)
        (limit-present-p nil)
        (clauses forms))
    (when (and clauses
               (consp (first clauses))
               (eq (first (first clauses)) :limit))
      (unless (= 2 (length (first clauses)))
        (error "cl-weave: :limit expects exactly one value, got ~S."
               (first clauses)))
      (setf limit (second (first clauses))
            limit-present-p t
            clauses (rest clauses)))
    (unless clauses
      (error "cl-weave: logic where macros require at least one relation clause."))
    (dolist (clause clauses)
      (unless (and (consp clause) (keywordp (first clause)))
        (error "cl-weave: logic clauses must be non-empty keyword relation lists, got ~S."
               clause)))
    (values clauses limit limit-present-p)))

(defmacro logic-where (facts &body forms)
  (multiple-value-bind (clauses limit limit-present-p)
      (split-logic-where-forms forms)
    `(logic-query ,facts ',clauses ,@(when limit-present-p `(:limit ,limit)))))

(defmacro test-plan-where (plan &body forms)
  (multiple-value-bind (clauses limit limit-present-p)
      (split-logic-where-forms forms)
    `(query-test-plan ,plan ',clauses ,@(when limit-present-p `(:limit ,limit)))))

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
