(in-package #:cl-weave)

(defvar *test-name-filter* nil)
(defvar *test-sequence-order* :defined)
(defvar *test-sequence-seed* 0)
(defvar *retry-test-restart-marker* (list :retry-test-restart))
(defvar *runner-default-condition-handler-disabled* nil)

(defconstant +stable-hash-modulus+ 4294967296)
(defconstant +stable-hash-offset+ 2166136261)
(defconstant +stable-hash-prime+ 16777619)

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

(defun effective-around-hooks (suite)
  (loop for current in (suite-lineage suite)
        append (suite-around-each current)))

(defun effective-after-hooks (suite)
  (loop for current in (reverse (suite-lineage suite))
        append (reverse (suite-after-each current))))

(defun call-hooks/k (hooks continue)
  (if (null hooks)
      (funcall continue)
      (progn
        (funcall (first hooks))
        (call-hooks/k (rest hooks) continue))))

(defun call-around-hooks/k (hooks continue)
  (if (null hooks)
      (funcall continue)
      (funcall (first hooks)
               (lambda ()
                 (call-around-hooks/k (rest hooks) continue)))))

(defun call-test-case/k (suite test continue)
  (let ((*test-context* (make-hash-table :test #'equal)))
    (unwind-protect
         (call-hooks/k
          (effective-before-hooks suite)
          (lambda ()
            (call-around-hooks/k
             (effective-around-hooks suite)
             (lambda ()
               (funcall (test-case-function test))
               (funcall continue)))))
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
   :location (test-case-location test)
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
      ((member (test-event-status event) '(:fail :error))
       (make-event :pass suite test start))
      (t
       event))))

(defun normalize-restart-skip-reason (reason)
  (cond
    ((null reason) "skipped by skip-test restart")
    ((stringp reason) reason)
    (t (princ-to-string reason))))

(defun call-test-attempt/restarts (suite test start)
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
      :report "Retry the current test attempt without consuming the configured retry budget."
      *retry-test-restart-marker*)))

(defun offer-condition-to-outer-handlers (condition)
  (let ((*runner-default-condition-handler-disabled* t))
    (signal condition)))

(defun run-test-attempt (suite test start)
  (let ((event nil))
    (block attempt
      (setf event
            (handler-bind
                ((sb-ext:timeout
                   (lambda (condition)
                     (unless *runner-default-condition-handler-disabled*
                       (offer-condition-to-outer-handlers condition)
                       (let ((timeout (make-condition
                                       'test-timeout
                                       :timeout-ms (test-case-timeout-ms test))))
                         (return-from attempt
                           (setf event
                                 (make-event :fail
                                             suite
                                             test
                                             start
                                             :condition timeout)))))))
                 (assertion-failure
                   (lambda (condition)
                     (unless *runner-default-condition-handler-disabled*
                       (offer-condition-to-outer-handlers condition)
                       (return-from attempt
                         (setf event
                               (make-event :fail
                                           suite
                                           test
                                           start
                                           :condition condition
                                           :assertion (failure-detail condition)))))))
                 (condition
                   (lambda (condition)
                     (unless *runner-default-condition-handler-disabled*
                       (offer-condition-to-outer-handlers condition)
                       (return-from attempt
                         (setf event
                               (make-event :error
                                           suite
                                           test
                                           start
                                           :condition condition)))))))
              (call-test-attempt/restarts suite test start))))
    (if (eq event *retry-test-restart-marker*)
        event
        (expected-failure-event suite test start event))))

(defun retryable-event-p (event)
  (member (test-event-status event) '(:fail :error)))

(defun run-test-attempts/k (suite test start remaining-retries)
  (let ((event (run-test-attempt suite test start)))
    (cond
      ((eq event *retry-test-restart-marker*)
       (run-test-attempts/k suite test start remaining-retries))
      ((and (plusp remaining-retries)
            (retryable-event-p event))
       (run-test-attempts/k suite test start (1- remaining-retries)))
      (t
       event))))

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

(defun normalize-shard (shard)
  (when shard
    (unless (and (consp shard)
                 (integerp (first shard))
                 (integerp (second shard))
                 (null (cddr shard))
                 (<= 1 (first shard) (second shard)))
      (error "Shard must be NIL or (INDEX COUNT) with 1 <= INDEX <= COUNT: ~S" shard))
    shard))

(defun shard-includes-ordinal-p (ordinal shard)
  (or (null shard)
      (= (first shard)
         (1+ (mod (1- ordinal) (second shard))))))

(defun base-selected-test-case-p (suite test focus-enabled ancestor-focused name-filter)
  (and (or (not focus-enabled)
           ancestor-focused
           (test-case-focus test))
       (test-path-matches-filter-p (test-path suite test) name-filter)))

(defun collect-shard-paths (suite focus-enabled name-filter shard)
  (when shard
    (let ((paths (make-hash-table :test #'equal))
          (ordinal 0))
      (labels ((visit (current-suite ancestor-focused)
                 (dolist (child (suite-children current-suite))
                   (typecase child
                     (suite
                      (visit child (or ancestor-focused (suite-focus child))))
                     (test-case
                      (when (base-selected-test-case-p
                             current-suite
                             child
                             focus-enabled
                             ancestor-focused
                             name-filter)
                        (incf ordinal)
                        (when (shard-includes-ordinal-p ordinal shard)
                          (setf (gethash (test-path current-suite child) paths)
                                t))))))))
        (visit suite nil))
      paths)))

(defun normalize-sequence-order (order)
  (cond
    ((or (null order) (eq order :defined)) :defined)
    ((member order '(:random :shuffle)) :random)
    (t (error "Sequence order must be NIL, :DEFINED, :RANDOM, or :SHUFFLE: ~S" order))))

(defun normalize-sequence-seed (seed)
  (cond
    ((null seed) 0)
    ((integerp seed) seed)
    (t (error "Sequence seed must be an integer: ~S" seed))))

(defun stable-string-hash (string seed)
  (let ((hash (mod (+ +stable-hash-offset+ seed) +stable-hash-modulus+)))
    (loop for char across string
          do (setf hash
                   (mod (* (logxor hash (char-code char))
                           +stable-hash-prime+)
                        +stable-hash-modulus+))
          finally (return hash))))

(defun sequence-suite-prefix (suite)
  (format nil "~{~A~^ > ~}" (mapcar #'suite-name (rest (suite-lineage suite)))))

(defun sequence-child-label (suite child)
  (format nil "~A :: ~A:~A"
          (sequence-suite-prefix suite)
          (typecase child
            (suite "suite")
            (test-case "test")
            (t "unknown"))
          (typecase child
            (suite (suite-name child))
            (test-case (test-case-name child))
            (t child))))

(defun ordered-children (suite children)
  (if (eq *test-sequence-order* :random)
      (stable-sort
       (copy-list children)
       #'<
       :key (lambda (child)
              (stable-string-hash
               (sequence-child-label suite child)
               *test-sequence-seed*)))
      children))

(defun selected-path-p (path shard-paths)
  (or (null shard-paths)
      (gethash path shard-paths)))

(defun selected-test-case-p (suite test focus-enabled ancestor-focused name-filter shard-paths)
  (let ((path (test-path suite test)))
    (and (base-selected-test-case-p suite test focus-enabled ancestor-focused name-filter)
         (selected-path-p path shard-paths))))

(defun selected-suite-p (suite focus-enabled ancestor-focused name-filter shard-paths)
  (some (lambda (child)
          (typecase child
            (suite
             (let ((child-focused (or ancestor-focused (suite-focus child))))
               (and (or (not focus-enabled)
                        child-focused
                        (focused-child-p child))
                    (selected-suite-p
                     child
                     focus-enabled
                     child-focused
                     name-filter
                     shard-paths))))
            (test-case
             (selected-test-case-p
              suite
              child
              focus-enabled
              ancestor-focused
              name-filter
              shard-paths))
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
   :timeout-ms (test-case-timeout-ms test)
   :concurrent (test-case-concurrent test)
   :location (test-case-location test)))

(defun concurrent-test-case-p (test)
  (and (typep test 'test-case)
       (test-case-concurrent test)))

(defun concurrent-batching-enabled-p (control suppressed-status)
  (and (null suppressed-status)
       (null (execution-control-bail-limit control))))

(defun collect-leading-concurrent-tests
    (suite children focus-enabled ancestor-focused name-filter shard-paths)
  (labels ((walk (remaining selected)
             (let ((child (first remaining)))
               (if (and (concurrent-test-case-p child)
                        (selected-test-case-p
                         suite
                         child
                         focus-enabled
                         ancestor-focused
                         name-filter
                         shard-paths))
                   (walk (rest remaining) (cons child selected))
                   (values (nreverse selected) remaining)))))
    (walk children '())))

(defun run-concurrent-test-cases (suite tests)
  #+sb-thread
  (let ((captured-root-suite *root-suite*)
        (captured-current-suite *current-suite*)
        (captured-test-context *test-context*)
        (captured-test-name-filter *test-name-filter*)
        (captured-test-sequence-order *test-sequence-order*)
        (captured-test-sequence-seed *test-sequence-seed*)
        (captured-isolated-timeout-seconds *isolated-timeout-seconds*)
        (captured-snapshot-directory *snapshot-directory*)
        (captured-snapshot-file-name *snapshot-file-name*)
        (captured-update-snapshots *update-snapshots*)
        (captured-property-test-count *property-test-count*)
        (captured-property-seed *property-seed*)
        (captured-recursive-generator-depth *recursive-generator-depth*))
    (labels ((run-captured-test (test)
               (let ((*root-suite* captured-root-suite)
                     (*current-suite* captured-current-suite)
                     (*test-context* captured-test-context)
                     (*test-name-filter* captured-test-name-filter)
                     (*test-sequence-order* captured-test-sequence-order)
                     (*test-sequence-seed* captured-test-sequence-seed)
                     (*isolated-timeout-seconds* captured-isolated-timeout-seconds)
                     (*snapshot-directory* captured-snapshot-directory)
                     (*snapshot-file-name* captured-snapshot-file-name)
                     (*update-snapshots* captured-update-snapshots)
                     (*property-test-count* captured-property-test-count)
                     (*property-seed* captured-property-seed)
                     (*recursive-generator-depth* captured-recursive-generator-depth))
                 (run-test-case suite test))))
      (let ((threads
              (loop for test in tests
                    collect (let ((worker-test test))
                              (sb-thread:make-thread
                               (lambda ()
                                 (run-captured-test worker-test))
                               :name (format nil "cl-weave: ~A"
                                             (test-case-name worker-test)))))))
        (mapcar #'sb-thread:join-thread threads))))
  #-sb-thread
  (mapcar (lambda (test)
            (run-test-case suite test))
          tests))

(declaim (ftype (function (suite list execution-control function &optional t t t t t t) *) collect-children/k))

(defun collect-suite-events/k
    (suite control continue &optional focus-enabled ancestor-focused name-filter shard-paths suppressed-status suppressed-reason)
  (if (or (execution-control-stopped control)
          (not (selected-suite-p suite focus-enabled ancestor-focused name-filter shard-paths)))
      (funcall continue '())
      (multiple-value-bind (active-status active-reason)
          (suite-suppression suite suppressed-status suppressed-reason)
        (if active-status
            (collect-children/k
             suite
             (ordered-children suite (suite-children suite))
             control
             continue
             focus-enabled
             ancestor-focused
             name-filter
             shard-paths
             active-status
             active-reason)
            (unwind-protect
                 (call-hooks/k
                  (suite-before-all suite)
                  (lambda ()
                    (collect-children/k
                     suite
                     (ordered-children suite (suite-children suite))
                     control
                     (lambda (events)
                       (funcall continue events))
                     focus-enabled
                     ancestor-focused
                     name-filter
                     shard-paths)))
              (call-hooks/k (reverse (suite-after-all suite)) (lambda () nil)))))))

(defun collect-children/k
    (suite children control continue &optional focus-enabled ancestor-focused name-filter shard-paths suppressed-status suppressed-reason)
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
                                  name-filter
                                  shard-paths))))
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
                         shard-paths
                         suppressed-status
                         suppressed-reason)))
                  focus-enabled
                  child-focused
                  name-filter
                  shard-paths
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
                  shard-paths
                  suppressed-status
                  suppressed-reason))))
          (test-case
           (let ((selected (selected-test-case-p
                            suite
                            child
                            focus-enabled
                            ancestor-focused
                            name-filter
                            shard-paths)))
             (if selected
                 (if (and (concurrent-test-case-p child)
                          (concurrent-batching-enabled-p control suppressed-status))
                     (multiple-value-bind (tests rest-children)
                         (collect-leading-concurrent-tests
                          suite
                          children
                          focus-enabled
                          ancestor-focused
                          name-filter
                          shard-paths)
                       (let ((events (mapcar (lambda (event)
                                               (record-event/control control event))
                                             (run-concurrent-test-cases suite tests))))
                         (collect-children/k
                          suite
                          rest-children
                          control
                          (lambda (tail)
                            (funcall continue (append events tail)))
                          focus-enabled
                          ancestor-focused
                          name-filter
                          shard-paths
                          suppressed-status
                          suppressed-reason)))
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
                            shard-paths
                            suppressed-status
                            suppressed-reason))))
                 (collect-children/k
                  suite
                  (rest children)
                  control
                  continue
                  focus-enabled
                  ancestor-focused
                  name-filter
                  shard-paths
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
            shard-paths
            suppressed-status
            suppressed-reason))))))

(defun collect-events (suite &key name-filter bail shard order seed)
  (let* ((focus-enabled (focused-suite-p suite))
         (normalized-filter (normalized-test-filter name-filter))
         (normalized-shard (normalize-shard shard))
         (normalized-order (normalize-sequence-order order))
         (normalized-seed (normalize-sequence-seed seed))
         (shard-paths (collect-shard-paths
                       suite
                       focus-enabled
                       normalized-filter
                       normalized-shard)))
    (let ((*test-sequence-order* normalized-order)
          (*test-sequence-seed* normalized-seed))
      (collect-suite-events/k
       suite
       (make-execution-control :bail-limit (normalize-bail bail))
       #'identity
       focus-enabled
       nil
       normalized-filter
       shard-paths))))

(declaim (ftype (function (suite list function &optional t t t t t t) *) collect-children-plan/k))

(defun collect-suite-plan/k
    (suite continue &optional focus-enabled ancestor-focused name-filter shard-paths suppressed-status suppressed-reason)
  (if (not (selected-suite-p suite focus-enabled ancestor-focused name-filter shard-paths))
      (funcall continue '())
      (multiple-value-bind (active-status active-reason)
          (suite-suppression suite suppressed-status suppressed-reason)
        (collect-children-plan/k
         suite
         (ordered-children suite (suite-children suite))
         continue
         focus-enabled
         ancestor-focused
         name-filter
         shard-paths
         active-status
         active-reason))))

(defun collect-children-plan/k
    (suite children continue &optional focus-enabled ancestor-focused name-filter shard-paths suppressed-status suppressed-reason)
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
                                  name-filter
                                  shard-paths))))
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
                     shard-paths
                     suppressed-status
                     suppressed-reason))
                  focus-enabled
                  child-focused
                  name-filter
                  shard-paths
                  suppressed-status
                  suppressed-reason)
                 (collect-children-plan/k
                  suite
                  (rest children)
                  continue
                  focus-enabled
                  ancestor-focused
                  name-filter
                  shard-paths
                  suppressed-status
                  suppressed-reason))))
          (test-case
           (if (selected-test-case-p suite child focus-enabled ancestor-focused name-filter shard-paths)
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
                  shard-paths
                  suppressed-status
                  suppressed-reason))
               (collect-children-plan/k
                suite
                (rest children)
                continue
                focus-enabled
                ancestor-focused
                name-filter
                shard-paths
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
            shard-paths
            suppressed-status
            suppressed-reason))))))

(defun collect-test-plan (suite &key name-filter shard order seed)
  (let* ((focus-enabled (focused-suite-p suite))
         (normalized-filter (normalized-test-filter name-filter))
         (normalized-shard (normalize-shard shard))
         (normalized-order (normalize-sequence-order order))
         (normalized-seed (normalize-sequence-seed seed))
         (shard-paths (collect-shard-paths
                       suite
                       focus-enabled
                       normalized-filter
                       normalized-shard)))
    (let ((*test-sequence-order* normalized-order)
          (*test-sequence-seed* normalized-seed))
      (collect-suite-plan/k
       suite
       #'identity
       focus-enabled
       nil
       normalized-filter
       shard-paths))))

(defun passed-event-p (event)
  (member (test-event-status event) '(:pass :skip :todo)))

(define-condition coverage-unavailable (error)
  ((reason :initarg :reason :reader coverage-unavailable-reason))
  (:report (lambda (condition stream)
             (format stream "Coverage support is unavailable: ~A"
                     (coverage-unavailable-reason condition)))))

(defun coverage-fbound-symbol (name &optional required-p)
  (let ((package (find-package "SB-COVER")))
    (unless package
      (when required-p
        (error 'coverage-unavailable :reason "SB-COVER is not loaded.")))
    (when package
      (multiple-value-bind (symbol status)
          (find-symbol name package)
        (if (and status (fboundp symbol))
            symbol
            (when required-p
              (error 'coverage-unavailable
                     :reason (format nil "SB-COVER:~A is not available." name))))))))

(defun require-coverage-support ()
  #+sbcl
  (handler-case
      (progn
        (require :sb-cover)
        (coverage-fbound-symbol "RESET-COVERAGE" t)
        (coverage-fbound-symbol "SAVE-COVERAGE-IN-FILE" t)
        t)
    (coverage-unavailable (condition)
      (error condition))
    (error (condition)
      (error 'coverage-unavailable :reason condition)))
  #-sbcl
  (error 'coverage-unavailable :reason "Coverage requires SBCL sb-cover."))

(defun coverage-support-available-p ()
  #+sbcl
  (handler-case
      (handler-bind ((warning #'muffle-warning))
        (require-coverage-support))
    (condition ()
      nil))
  #-sbcl
  nil)

(defun reset-coverage ()
  (require-coverage-support)
  (funcall (coverage-fbound-symbol "RESET-COVERAGE" t))
  t)

(defun save-coverage (pathname)
  (require-coverage-support)
  (funcall (coverage-fbound-symbol "SAVE-COVERAGE-IN-FILE" t) pathname)
  pathname)

(defun call-with-coverage (coverage coverage-output coverage-reset thunk)
  (if coverage
      (progn
        (require-coverage-support)
        (when coverage-reset
          (reset-coverage))
        (unwind-protect
             (funcall thunk)
          (when coverage-output
            (save-coverage coverage-output))))
      (funcall thunk)))

(defun run-all (&key (reporter :spec)
                  (stream *standard-output*)
                  (name-filter *test-name-filter*)
                  shard
                  order
                  seed
                  bail
                  coverage
                  coverage-output
                  (pass-with-no-tests t)
                  (coverage-reset t))
  (call-with-coverage
   coverage
   coverage-output
   coverage-reset
   (lambda ()
     (let ((events (collect-events
                    (root-suite)
                    :name-filter name-filter
                    :shard shard
                    :order order
                    :seed seed
                    :bail bail)))
       (ecase reporter
         (:spec (report-spec events stream))
         (:sexp (report-sexp events stream))
         (:json (report-json events stream))
         (:jsonl (report-jsonl events stream))
         (:tap (report-tap events stream))
         (:github (report-github events stream))
         (:junit (report-junit events stream)))
       (and (or pass-with-no-tests events)
            (every #'passed-event-p events))))))

(defun list-tests (&key (reporter :spec)
                     (stream *standard-output*)
                     (name-filter *test-name-filter*)
                     shard
                     order
                     seed)
  (let ((plan (collect-test-plan
               (root-suite)
               :name-filter name-filter
               :shard shard
               :order order
               :seed seed)))
    (ecase reporter
      (:spec (report-plan-spec plan stream))
      (:sexp (report-plan-sexp plan stream))
      (:json (report-plan-json plan stream))
      (:jsonl (report-plan-jsonl plan stream)))
    plan))
