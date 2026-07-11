(in-package #:cl-weave)

(defvar *test-name-filter* nil)
(defvar *test-sequence-order* :defined)
(defvar *test-sequence-seed* 0)
(defvar *default-retry* 0)
(defvar *default-timeout-ms* nil)
(defvar *max-workers* nil)
(defvar *retry-budget-remaining* 0)
(defvar *runner-default-condition-handler-disabled* nil)
(defvar *runner-propagate-conditions* t)
(defvar *attempt-secondary-conditions* nil)

(defparameter *runner-dynamic-environment-variables*
  '(*root-suite*
    *current-suite*
    *test-context*
    *test-name-filter*
    *test-sequence-order*
    *test-sequence-seed*
    *default-retry*
    *retry-budget-remaining*
    *default-timeout-ms*
    *max-workers*
    *isolated-timeout-seconds*
    *snapshot-directory*
    *snapshot-file-name*
    *update-snapshots*
    *property-test-count*
    *property-seed*
    *recursive-generator-depth*))

(defconstant +stable-hash-modulus+ 4294967296)
(defconstant +stable-hash-offset+ 2166136261)
(defconstant +stable-hash-prime+ 16777619)

(defstruct execution-control
  bail-limit
  (failures 0)
  stopped)

(defmacro with-escape-continuation ((continue) &body body)
  (let ((tag (gensym "ESCAPE-TAG"))
        (value (gensym "VALUE")))
    `(let ((,tag (gensym "ESCAPE-CONTINUATION")))
       (catch ,tag
         (flet ((,continue (,value)
                  (throw ,tag ,value)))
           ,@body)))))

(defun normalize-bail (bail)
  (cond
    ((or (null bail) (eql bail 0)) nil)
    ((eq bail t) 1)
    ((and (integerp bail) (plusp bail)) bail)
    (t (error "Bail must be NIL, T, 0, or a positive integer: ~S" bail))))

(defun failing-event-p (event)
  (member (test-event-status event) '(:fail :error)))

(defun record-event/control (control event)
  (when (and (execution-control-bail-limit control)
             (failing-event-p event))
    (incf (execution-control-failures control))
    (when (>= (execution-control-failures control)
              (execution-control-bail-limit control))
      (setf (execution-control-stopped control) t)))
  event)

(defun suite-lineage (suite)
  (loop for current = suite then (suite-parent current)
        while current
        collect current into suites
        finally (return (nreverse suites))))

(defun effective-before-hooks (suite)
  (loop for current in (suite-lineage suite)
        append (suite-hook current before-each)))

(defun effective-around-hooks (suite)
  (loop for current in (suite-lineage suite)
        append (suite-hook current around-each)))

(defun effective-after-hooks (suite)
  (loop for current in (reverse (suite-lineage suite))
        append (reverse (suite-hook current after-each))))

(defun call-hooks/k (hooks continue)
  (if (null hooks)
      (funcall continue)
      (progn
        (funcall (first hooks))
        (call-hooks/k (rest hooks) continue))))

(defun call-hooks/collect-errors (hooks)
  (loop for hook in hooks
        when (handler-case
                 (progn (funcall hook) nil)
               (error (condition) condition))
          collect it))

(defun call-around-hooks/k (hooks continue)
  (if (null hooks)
      (funcall continue)
      (let ((continuation-errors nil))
        (handler-case
            (funcall
             (first hooks)
             (lambda ()
               (handler-bind
                   ((error (lambda (condition)
                             (pushnew condition continuation-errors :test #'eq))))
                 (call-around-hooks/k (rest hooks) continue))))
          (error (condition)
            (if (member condition continuation-errors :test #'eq)
                (error condition)
                (error 'hook-failure
                       :phase :around-each
                       :causes (list condition))))))))

(defun call-test-case/k (suite test continue)
  (let ((*test-context* (make-hash-table :test #'equal))
        (*assertion-count* 0)
        (*expected-assertion-count* nil)
        (*expected-assertion-count-form* nil)
        (*has-assertions-required* nil)
        (*has-assertions-form* nil))
    (let ((primary-condition nil)
          (result nil))
      (handler-case
          (setf result
                (let ((before-errors
                        (call-hooks/collect-errors
                         (effective-before-hooks suite))))
                  (when before-errors
                    (error 'hook-failure
                           :phase :before-each
                           :causes before-errors))
                  (call-around-hooks/k
                   (effective-around-hooks suite)
                   (lambda ()
                     (funcall (test-case-function test))
                     (verify-assertion-counts)
                     (funcall continue)))))
        (error (condition)
          (setf primary-condition condition)))
      (let ((cleanup-errors
              (call-hooks/collect-errors (effective-after-hooks suite))))
        (cond
          (primary-condition
           (setf *attempt-secondary-conditions* cleanup-errors)
           (error primary-condition))
          (cleanup-errors
           (error 'hook-failure :phase :after-each :causes cleanup-errors))
          (t result))))))

(defun test-path (suite test)
  (append (mapcar #'suite-name (rest (suite-lineage suite)))
          (list (test-case-name test))))

(defun filter-path-string (path)
  (format nil "~{~A~^ > ~}" path))

(defun make-event (status suite test start &key condition secondary-conditions assertion reason)
  (make-test-event
   :status status
   :path (test-path suite test)
   :condition condition
   :secondary-conditions (or secondary-conditions
                             *attempt-secondary-conditions*)
   :assertion assertion
   :reason reason
   :location (test-case-location test)
   :elapsed-internal-time (- (get-internal-real-time) start)))

(defun normalize-retry-count (retry)
  (cond
    ((null retry) 0)
    ((and (integerp retry) (not (minusp retry))) retry)
    (t (error "Retry must be NIL or a non-negative integer: ~S" retry))))

(defun normalize-timeout-ms (timeout-ms)
  (cond
    ((null timeout-ms) nil)
    ((and (integerp timeout-ms) (plusp timeout-ms)) timeout-ms)
    (t (error "Timeout must be NIL or a positive integer in milliseconds: ~S"
              timeout-ms))))

(defun normalize-max-workers (max-workers)
  (cond
    ((null max-workers) nil)
    ((and (integerp max-workers) (plusp max-workers)) max-workers)
    (t (error "Max workers must be NIL or a positive integer: ~S"
              max-workers))))

(defun retry-count (test)
  (normalize-retry-count
   (if (null (test-case-retry test))
       *default-retry*
       (test-case-retry test))))

(defun effective-timeout-ms (test)
  (normalize-timeout-ms
   (or (test-case-timeout-ms test)
       *default-timeout-ms*)))

(defun timeout-seconds (test)
  (let ((timeout-ms (effective-timeout-ms test)))
    (when timeout-ms
      (/ timeout-ms 1000.0))))

#+sbcl
(defun call-test-case-with-timeout/k (suite test timeout continue)
  (if timeout
      (sb-ext:with-timeout timeout
        (call-test-case/k suite test continue))
      (call-test-case/k suite test continue)))

#-sbcl
(defun call-test-case-with-timeout/k (suite test timeout continue)
  (declare (ignore timeout))
  (call-test-case/k suite test continue))

(defun expected-failure-case-p (test)
  (test-case-expected-failure-reason test))

(defun expected-failure-event (suite test start event)
  (let ((reason (expected-failure-case-p test)))
    (cond
      ((null reason)
       event)
      ((eq (test-event-status event) :pass)
       (make-event :fail
                   suite
                   test
                   start
                   :condition (make-condition 'expected-failure-missed
                                              :reason reason)))
      ((and (eq (test-event-status event) :fail)
            (typep (test-event-condition event) 'assertion-failure))
       (let ((cleanup-conditions
               (test-event-secondary-conditions event)))
         (if cleanup-conditions
             (make-event
              :error
              suite
              test
              start
              :condition (make-condition 'hook-failure
                                         :phase :after-each
                                         :causes cleanup-conditions)
              :assertion (test-event-assertion event)
              :secondary-conditions cleanup-conditions)
             (make-event :pass suite test start))))
      (t
       event))))

(defun normalize-restart-skip-reason (reason)
  (cond
    ((null reason) "skipped by skip-test restart")
    ((stringp reason) reason)
    (t (princ-to-string reason))))

(defun call-test-attempt/restarts (suite test start retry)
  (restart-case
      (call-test-case-with-timeout/k
       suite
       test
       (timeout-seconds test)
       (lambda ()
         (make-event :pass suite test start)))
    (continue-test ()
      :report "Continue the current failed test attempt and record it as passed."
      (make-event :pass suite test start))
    (skip-test (&optional reason)
      :report "Skip the current failed test attempt and record it as skipped."
      (make-event :skip
                  suite
                  test
                  start
                  :reason (normalize-restart-skip-reason reason)))
    (retry-test ()
      :report "Retry the current test attempt using the configured retry budget."
      (if (plusp *retry-budget-remaining*)
          (funcall retry)
          (error "The configured retry budget is exhausted.")))))

(defun offer-condition-to-outer-handlers (condition)
  (let ((*runner-default-condition-handler-disabled* t))
    (signal condition)))

(defun call-with-propagated-condition/k (condition continue)
  (when (and *runner-propagate-conditions*
             (not *runner-default-condition-handler-disabled*))
    (offer-condition-to-outer-handlers condition))
  (funcall continue))

(defmacro with-runner-condition-propagation ((enabled) &body body)
  `(let ((*runner-propagate-conditions* ,enabled))
     ,@body))

(defun run-test-attempt/k (suite test start retry continue)
  (let ((*attempt-secondary-conditions* nil))
    (funcall
     continue
     (expected-failure-event
      suite
      test
      start
      (with-escape-continuation (finish-attempt)
        (handler-bind
            (#+sbcl
             (sb-ext:timeout
               (lambda (condition)
                 (funcall
                  finish-attempt
                  (call-with-propagated-condition/k
                   condition
                   (lambda ()
                     (make-event
                      :fail suite test start
                      :condition
                      (make-condition
                       'test-timeout
                       :timeout-ms (effective-timeout-ms test)))))))))
             (assertion-failure
               (lambda (condition)
                 (funcall
                  finish-attempt
                  (call-with-propagated-condition/k
                   condition
                   (lambda ()
                     (make-event
                      :fail suite test start
                      :condition condition
                      :assertion (failure-detail condition)))))))
             (error
               (lambda (condition)
                 (funcall
                  finish-attempt
                  (call-with-propagated-condition/k
                   condition
                   (lambda ()
                     (make-event :error suite test start
                                 :condition condition)))))))
          (call-test-attempt/restarts suite test start retry))))))

(defun retryable-event-p (event)
  (member (test-event-status event) '(:fail :error)))

(defun run-test-attempts (suite test start remaining-retries)
  (with-escape-continuation (finish-attempts)
    (labels ((attempt (retries)
               (let ((*retry-budget-remaining* retries))
                 (run-test-attempt/k
                  suite
                  test
                  start
                  (lambda ()
                    (attempt (1- retries)))
                  (lambda (event)
                    (if (and (plusp retries)
                             (retryable-event-p event))
                        (attempt (1- retries))
                        (funcall finish-attempts event)))))))
      (attempt remaining-retries))))

(defun run-test-case/internal (suite test)
  (let ((start (get-internal-real-time)))
    (cond
      ((test-case-todo-reason test)
       (make-event :todo suite test start :reason (test-case-todo-reason test)))
      ((test-case-skip-reason test)
       (make-event :skip suite test start :reason (test-case-skip-reason test)))
      (t
        (run-test-attempts suite test start (retry-count test))))))

(defun run-test-case (suite test)
  (with-runner-condition-propagation (nil)
    (run-test-case/internal suite test)))

(defun run-test-case/interactively (suite test)
  (with-runner-condition-propagation (t)
    (run-test-case/internal suite test)))
