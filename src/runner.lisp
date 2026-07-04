(in-package #:cl-weave)

(defvar *test-name-filter* nil)

(defstruct execution-control
  bail-limit
  (failures 0)
  stopped)

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
        append (suite-before-each current)))

(defun effective-after-hooks (suite)
  (loop for current in (reverse (suite-lineage suite))
        append (reverse (suite-after-each current))))

(defun call-hooks/k (hooks continue)
  (if (null hooks)
      (funcall continue)
      (progn
        (funcall (first hooks))
        (call-hooks/k (rest hooks) continue))))

(defun call-test-case/k (suite test continue)
  (let ((*test-context* (make-hash-table :test #'equal)))
    (unwind-protect
         (call-hooks/k
          (effective-before-hooks suite)
          (lambda ()
            (funcall (test-case-function test))
            (funcall continue)))
      (call-hooks/k (effective-after-hooks suite) (lambda () nil)))))

(defun test-path (suite test)
  (append (mapcar #'suite-name (rest (suite-lineage suite)))
          (list (test-case-name test))))

(defun filter-path-string (path)
  (format nil "~{~A~^ > ~}" path))

(defun make-event (status suite test start &key condition assertion reason)
  (make-test-event
   :status status
   :path (test-path suite test)
   :condition condition
   :assertion assertion
   :reason reason
   :elapsed-internal-time (- (get-internal-real-time) start)))

(defun retry-count (test)
  (let ((retry (test-case-retry test)))
    (if (and (integerp retry) (plusp retry))
        retry
        0)))

(defun timeout-seconds (test)
  (let ((timeout-ms (test-case-timeout-ms test)))
    (when (and (numberp timeout-ms) (plusp timeout-ms))
      (/ timeout-ms 1000.0))))

(defun call-test-case-with-timeout/k (suite test timeout continue)
  (if timeout
      (sb-ext:with-timeout timeout
        (call-test-case/k suite test continue))
      (call-test-case/k suite test continue)))

(defun run-test-attempt (suite test start)
  (handler-case
      (call-test-case-with-timeout/k
       suite
       test
       (timeout-seconds test)
       (lambda ()
         (make-event :pass suite test start)))
    (sb-ext:timeout ()
      (let ((condition (make-condition 'test-timeout
                                       :timeout-ms (test-case-timeout-ms test))))
        (make-event :fail suite test start :condition condition)))
    (assertion-failure (condition)
      (make-event :fail suite test start
                  :condition condition
                  :assertion (failure-detail condition)))
    (condition (condition)
      (make-event :error suite test start :condition condition))))

(defun retryable-event-p (event)
  (member (test-event-status event) '(:fail :error)))

(defun run-test-attempts/k (suite test start remaining-retries)
  (let ((event (run-test-attempt suite test start)))
    (if (and (plusp remaining-retries)
             (retryable-event-p event))
        (run-test-attempts/k suite test start (1- remaining-retries))
        event)))

(defun focused-child-p (child)
  (typecase child
    (suite
     (or (suite-focus child)
         (some #'focused-child-p (suite-children child))))
    (test-case
     (test-case-focus child))))

(defun focused-suite-p (suite)
  (some #'focused-child-p (suite-children suite)))

(defun normalized-test-filter (filter)
  (when (and filter (not (string= filter "")))
    (string-downcase filter)))

(defun test-path-matches-filter-p (path filter)
  (or (null filter)
      (search filter
              (string-downcase (filter-path-string path))
              :test #'char=)))

(defun selected-test-case-p (suite test focus-enabled ancestor-focused name-filter)
  (and (or (not focus-enabled)
           ancestor-focused
           (test-case-focus test))
       (test-path-matches-filter-p (test-path suite test) name-filter)))

(defun selected-suite-p (suite focus-enabled ancestor-focused name-filter)
  (some (lambda (child)
          (typecase child
            (suite
             (let ((child-focused (or ancestor-focused (suite-focus child))))
               (and (or (not focus-enabled)
                        child-focused
                        (focused-child-p child))
                    (selected-suite-p child focus-enabled child-focused name-filter))))
            (test-case
             (selected-test-case-p suite child focus-enabled ancestor-focused name-filter))
            (t nil)))
        (suite-children suite)))

(defun run-test-case (suite test)
  (let ((start (get-internal-real-time)))
    (cond
      ((test-case-todo-reason test)
       (make-event :todo suite test start :reason (test-case-todo-reason test)))
      ((test-case-skip-reason test)
       (make-event :skip suite test start :reason (test-case-skip-reason test)))
      (t
       (run-test-attempts/k suite test start (retry-count test))))))

(defun suite-suppression (suite inherited-status inherited-reason)
  (cond
    (inherited-status
     (values inherited-status inherited-reason))
    ((suite-todo-reason suite)
     (values :todo (suite-todo-reason suite)))
    ((suite-skip-reason suite)
     (values :skip (suite-skip-reason suite)))
    (t
     (values nil nil))))

(defun suppressed-test-event (suite test status reason)
  (make-event status suite test (get-internal-real-time) :reason reason))

(defun planned-test-status (test suppressed-status)
  (or suppressed-status
      (when (test-case-todo-reason test) :todo)
      (when (test-case-skip-reason test) :skip)
      :run))

(defun planned-test-reason (test suppressed-status suppressed-reason status)
  (if suppressed-status
      suppressed-reason
      (ecase status
        (:run nil)
        (:todo (test-case-todo-reason test))
        (:skip (test-case-skip-reason test)))))

(defun make-plan-entry (suite test status reason focus-enabled ancestor-focused)
  (make-test-plan-entry
   :path (test-path suite test)
   :status status
   :reason reason
   :focused (and focus-enabled (or ancestor-focused (test-case-focus test)))
   :retry (retry-count test)
   :timeout-ms (test-case-timeout-ms test)))

(declaim (ftype (function (suite list execution-control function &optional t t t t t) *) collect-children/k))

(defun collect-suite-events/k
    (suite control continue &optional focus-enabled ancestor-focused name-filter suppressed-status suppressed-reason)
  (if (or (execution-control-stopped control)
          (not (selected-suite-p suite focus-enabled ancestor-focused name-filter)))
      (funcall continue '())
      (multiple-value-bind (active-status active-reason)
          (suite-suppression suite suppressed-status suppressed-reason)
        (if active-status
            (collect-children/k
             suite
             (suite-children suite)
             control
             continue
             focus-enabled
             ancestor-focused
             name-filter
             active-status
             active-reason)
            (unwind-protect
                 (call-hooks/k
                  (suite-before-all suite)
                  (lambda ()
                    (collect-children/k
                     suite
                     (suite-children suite)
                     control
                     (lambda (events)
                       (funcall continue events))
                     focus-enabled
                     ancestor-focused
                     name-filter)))
              (call-hooks/k (reverse (suite-after-all suite)) (lambda () nil)))))))

(defun collect-children/k
    (suite children control continue &optional focus-enabled ancestor-focused name-filter suppressed-status suppressed-reason)
  (if (or (null children) (execution-control-stopped control))
      (funcall continue '())
      (let ((child (first children)))
        (typecase child
          (suite
           (let* ((child-focused (or ancestor-focused (suite-focus child)))
                  (selected (and (or (not focus-enabled)
                                     child-focused
                                     (focused-child-p child))
                                 (selected-suite-p
                                  child
                                  focus-enabled
                                  child-focused
                                  name-filter))))
             (if selected
                 (collect-suite-events/k
                  child
                  control
                  (lambda (events)
                    (if (execution-control-stopped control)
                        (funcall continue events)
                        (collect-children/k
                         suite
                         (rest children)
                         control
                         (lambda (tail)
                           (funcall continue (append events tail)))
                         focus-enabled
                         ancestor-focused
                         name-filter
                         suppressed-status
                         suppressed-reason)))
                  focus-enabled
                  child-focused
                  name-filter
                  suppressed-status
                  suppressed-reason)
                 (collect-children/k
                  suite
                  (rest children)
                  control
                  continue
                  focus-enabled
                  ancestor-focused
                  name-filter
                  suppressed-status
                  suppressed-reason))))
          (test-case
           (let ((selected (selected-test-case-p
                            suite
                            child
                            focus-enabled
                            ancestor-focused
                            name-filter)))
             (if selected
                 (let ((event (record-event/control
                               control
                               (if suppressed-status
                                   (suppressed-test-event suite child suppressed-status suppressed-reason)
                                   (run-test-case suite child)))))
                   (if (execution-control-stopped control)
                       (funcall continue (list event))
                       (collect-children/k
                        suite
                        (rest children)
                        control
                        (lambda (tail)
                          (funcall continue (cons event tail)))
                        focus-enabled
                        ancestor-focused
                        name-filter
                        suppressed-status
                        suppressed-reason)))
                 (collect-children/k
                  suite
                  (rest children)
                  control
                  continue
                  focus-enabled
                  ancestor-focused
                  name-filter
                  suppressed-status
                  suppressed-reason))))
          (t
           (collect-children/k
            suite
            (rest children)
            control
            continue
            focus-enabled
            ancestor-focused
            name-filter
            suppressed-status
            suppressed-reason))))))

(defun collect-events (suite &key name-filter bail)
  (collect-suite-events/k
   suite
   (make-execution-control :bail-limit (normalize-bail bail))
   #'identity
   (focused-suite-p suite)
   nil
   (normalized-test-filter name-filter)))

(declaim (ftype (function (suite list function &optional t t t t t) *) collect-children-plan/k))

(defun collect-suite-plan/k
    (suite continue &optional focus-enabled ancestor-focused name-filter suppressed-status suppressed-reason)
  (if (not (selected-suite-p suite focus-enabled ancestor-focused name-filter))
      (funcall continue '())
      (multiple-value-bind (active-status active-reason)
          (suite-suppression suite suppressed-status suppressed-reason)
        (collect-children-plan/k
         suite
         (suite-children suite)
         continue
         focus-enabled
         ancestor-focused
         name-filter
         active-status
         active-reason))))

(defun collect-children-plan/k
    (suite children continue &optional focus-enabled ancestor-focused name-filter suppressed-status suppressed-reason)
  (if (null children)
      (funcall continue '())
      (let ((child (first children)))
        (typecase child
          (suite
           (let* ((child-focused (or ancestor-focused (suite-focus child)))
                  (selected (and (or (not focus-enabled)
                                     child-focused
                                     (focused-child-p child))
                                 (selected-suite-p
                                  child
                                  focus-enabled
                                  child-focused
                                  name-filter))))
             (if selected
                 (collect-suite-plan/k
                  child
                  (lambda (entries)
                    (collect-children-plan/k
                     suite
                     (rest children)
                     (lambda (tail)
                       (funcall continue (append entries tail)))
                     focus-enabled
                     ancestor-focused
                     name-filter
                     suppressed-status
                     suppressed-reason))
                  focus-enabled
                  child-focused
                  name-filter
                  suppressed-status
                  suppressed-reason)
                 (collect-children-plan/k
                  suite
                  (rest children)
                  continue
                  focus-enabled
                  ancestor-focused
                  name-filter
                  suppressed-status
                  suppressed-reason))))
          (test-case
           (if (selected-test-case-p suite child focus-enabled ancestor-focused name-filter)
               (let* ((status (planned-test-status child suppressed-status))
                  (reason (planned-test-reason child suppressed-status suppressed-reason status))
                      (entry (make-plan-entry
                              suite
                              child
                              status
                              reason
                              focus-enabled
                              ancestor-focused)))
                 (collect-children-plan/k
                  suite
                  (rest children)
                  (lambda (tail)
                    (funcall continue (cons entry tail)))
                  focus-enabled
                  ancestor-focused
                  name-filter
                  suppressed-status
                  suppressed-reason))
               (collect-children-plan/k
                suite
                (rest children)
                continue
                focus-enabled
                ancestor-focused
                name-filter
                suppressed-status
                suppressed-reason)))
          (t
           (collect-children-plan/k
            suite
            (rest children)
            continue
            focus-enabled
            ancestor-focused
            name-filter
            suppressed-status
            suppressed-reason))))))

(defun collect-test-plan (suite &key name-filter)
  (collect-suite-plan/k
   suite
   #'identity
   (focused-suite-p suite)
   nil
   (normalized-test-filter name-filter)))

(defun passed-event-p (event)
  (member (test-event-status event) '(:pass :skip :todo)))

(defun run-all (&key (reporter :spec)
                  (stream *standard-output*)
                  (name-filter *test-name-filter*)
                  bail)
  (let ((events (collect-events (root-suite) :name-filter name-filter :bail bail)))
    (ecase reporter
      (:spec (report-spec events stream))
      (:sexp (report-sexp events stream))
      (:json (report-json events stream))
      (:junit (report-junit events stream)))
    (every #'passed-event-p events)))

(defun list-tests (&key (reporter :spec)
                     (stream *standard-output*)
                     (name-filter *test-name-filter*))
  (let ((plan (collect-test-plan (root-suite) :name-filter name-filter)))
    (ecase reporter
      (:spec (report-plan-spec plan stream))
      (:sexp (report-plan-sexp plan stream))
      (:json (report-plan-json plan stream)))
    plan))
