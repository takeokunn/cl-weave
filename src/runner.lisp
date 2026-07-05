(in-package #:cl-weave)

(defvar *test-name-filter* nil)
(defvar *test-sequence-order* :defined)
(defvar *test-sequence-seed* 0)
(defvar *default-retry* 0)
(defvar *default-timeout-ms* nil)
(defvar *max-workers* nil)
(defvar *retry-test-restart-marker* (list :retry-test-restart))
(defvar *runner-default-condition-handler-disabled* nil)
(defvar *runner-propagate-conditions* t)

(defparameter *runner-dynamic-environment-variables*
  '(*root-suite*
    *current-suite*
    *test-context*
    *test-name-filter*
    *test-sequence-order*
    *test-sequence-seed*
    *default-retry*
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
  (let ((*test-context* (make-hash-table :test #'equal))
        (*assertion-count* 0)
        (*expected-assertion-count* nil)
        (*expected-assertion-count-form* nil)
        (*has-assertions-required* nil)
        (*has-assertions-form* nil))
    (unwind-protect
         (call-hooks/k
          (effective-before-hooks suite)
          (lambda ()
            (call-around-hooks/k
             (effective-around-hooks suite)
             (lambda ()
               (funcall (test-case-function test))
               (verify-assertion-counts)
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

(defmacro with-runner-condition-propagation ((enabled) &body body)
  `(let ((*runner-propagate-conditions* ,enabled))
     ,@body))

(defun run-test-attempt (suite test start)
  (let ((event nil))
    (block attempt
      (setf event
            (handler-bind
                 ((sb-ext:timeout
                    (lambda (condition)
                      (when (and *runner-propagate-conditions*
                                 (not *runner-default-condition-handler-disabled*))
                        (offer-condition-to-outer-handlers condition))
                      (let ((timeout (make-condition
                                      'test-timeout
                                     :timeout-ms (effective-timeout-ms test))))
                        (return-from attempt
                          (setf event
                                (make-event :fail
                                            suite
                                            test
                                            start
                                            :condition timeout))))))
                 (assertion-failure
                    (lambda (condition)
                      (when (and *runner-propagate-conditions*
                                 (not *runner-default-condition-handler-disabled*))
                        (offer-condition-to-outer-handlers condition))
                      (return-from attempt
                        (setf event
                              (make-event :fail
                                          suite
                                          test
                                          start
                                          :condition condition
                                          :assertion (failure-detail condition))))))
                 (condition
                    (lambda (condition)
                      (when (and *runner-propagate-conditions*
                                 (not *runner-default-condition-handler-disabled*))
                        (offer-condition-to-outer-handlers condition))
                      (return-from attempt
                        (setf event
                              (make-event :error
                                          suite
                                          test
                                          start
                                          :condition condition))))))
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

(defun location-pathname-designator (designator)
  (etypecase designator
    (pathname (uiop:ensure-absolute-pathname designator))
    (string (uiop:ensure-absolute-pathname designator))))

(defun normalize-location-filter (location-filter)
  (when location-filter
    (mapcar #'location-pathname-designator location-filter)))

(defun test-location-pathname (test)
  (let ((file (getf (test-case-location test) :file)))
    (when file
      (location-pathname-designator file))))

(defun test-location-matches-filter-p (test location-filter)
  (or (null location-filter)
      (let ((pathname (test-location-pathname test)))
        (and pathname
             (member pathname location-filter :test #'equal)))))

(defun base-selected-test-case-p (suite test focus-enabled ancestor-focused name-filter location-filter)
  (and (or (not focus-enabled)
           ancestor-focused
           (test-case-focus test))
       (test-path-matches-filter-p (test-path suite test) name-filter)
       (test-location-matches-filter-p test location-filter)))

(defun collect-shard-paths (suite focus-enabled name-filter location-filter shard)
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
                             name-filter
                             location-filter)
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

(defun selected-test-case-p (suite test focus-enabled ancestor-focused name-filter location-filter shard-paths)
  (let ((path (test-path suite test)))
    (and (base-selected-test-case-p suite test focus-enabled ancestor-focused name-filter location-filter)
         (selected-path-p path shard-paths))))

(defun selected-suite-p (suite focus-enabled ancestor-focused name-filter location-filter shard-paths)
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
                     location-filter
                     shard-paths))))
            (test-case
             (selected-test-case-p
              suite
              child
              focus-enabled
              ancestor-focused
              name-filter
              location-filter
              shard-paths))
            (t nil)))
        (suite-children suite)))

(defun selected-child-suite-p
    (child focus-enabled child-focused name-filter location-filter shard-paths)
  (and (or (not focus-enabled)
           child-focused
           (focused-child-p child))
       (selected-suite-p child
                         focus-enabled
                         child-focused
                         name-filter
                         location-filter
                         shard-paths)))

(defun selected-child-test-p
    (suite child focus-enabled ancestor-focused name-filter location-filter shard-paths)
  (selected-test-case-p suite
                        child
                        focus-enabled
                        ancestor-focused
                        name-filter
                        location-filter
                        shard-paths))

(defun run-test-case/internal (suite test)
  (let ((start (get-internal-real-time)))
    (cond
      ((test-case-todo-reason test)
       (make-event :todo suite test start :reason (test-case-todo-reason test)))
      ((test-case-skip-reason test)
       (make-event :skip suite test start :reason (test-case-skip-reason test)))
      (t
        (run-test-attempts/k suite test start (retry-count test))))))

(defun run-test-case (suite test)
  (with-runner-condition-propagation (nil)
    (run-test-case/internal suite test)))

(defun run-test-case/interactively (suite test)
  (with-runner-condition-propagation (t)
    (run-test-case/internal suite test)))

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

(defun effective-suite-execution-mode (suite inherited-mode)
  (or (suite-execution-mode suite)
      inherited-mode))

(defun effective-test-execution-mode (test inherited-mode)
  (or (test-case-execution-mode test)
      (when (test-case-concurrent test) :concurrent)
      inherited-mode))

(defun effective-concurrent-test-case-p (test inherited-mode)
  (and (typep test 'test-case)
       (eq (effective-test-execution-mode test inherited-mode) :concurrent)))

(defun make-plan-entry
    (suite test status reason focus-enabled ancestor-focused execution-mode)
  (make-test-plan-entry
   :path (test-path suite test)
   :status status
   :reason reason
   :focused (and focus-enabled (or ancestor-focused (test-case-focus test)))
   :retry (retry-count test)
   :timeout-ms (effective-timeout-ms test)
   :concurrent (effective-concurrent-test-case-p test execution-mode)
   :location (test-case-location test)))

(defun concurrent-batching-enabled-p (control suppressed-status)
  (and (null suppressed-status)
       (null (execution-control-bail-limit control))))

(defun collect-leading-concurrent-tests
    (suite children focus-enabled ancestor-focused name-filter location-filter shard-paths execution-mode)
  (labels ((walk (remaining selected)
             (let ((child (first remaining)))
               (if (and (effective-concurrent-test-case-p child execution-mode)
                        (selected-test-case-p
                         suite
                         child
                         focus-enabled
                         ancestor-focused
                         name-filter
                         location-filter
                         shard-paths))
                   (walk (rest remaining) (cons child selected))
                   (values (nreverse selected) remaining)))))
    (walk children '())))

(defun worker-batch-size (tests)
  (let ((limit (normalize-max-workers *max-workers*)))
    (if limit
        (min limit (length tests))
        (length tests))))

(defun split-worker-batch/k (tests limit continue)
  (labels ((take/k (remaining remaining-limit collected)
             (if (or (null remaining) (zerop remaining-limit))
                 (funcall continue (nreverse collected) remaining)
                 (take/k (rest remaining)
                         (1- remaining-limit)
                         (cons (first remaining) collected)))))
    (take/k tests limit '())))

(defun run-worker-batches/k (tests batch-size run-batch continue)
  (if (null tests)
      (funcall continue '())
      (split-worker-batch/k
       tests
       batch-size
       (lambda (batch remaining)
         (let ((events (funcall run-batch batch)))
           (run-worker-batches/k
            remaining
            batch-size
            run-batch
            (lambda (tail)
              (funcall continue (append events tail)))))))))

(defun capture-runner-dynamic-environment ()
  (mapcar #'symbol-value *runner-dynamic-environment-variables*))

(defmacro with-runner-dynamic-environment (values-form &body body)
  `(progv *runner-dynamic-environment-variables*
          ,values-form
     ,@body))

(defun run-concurrent-test-cases (suite tests)
  #+sb-thread
  (let ((captured-environment
          (capture-runner-dynamic-environment)))
    (labels ((run-captured-test (test)
               (with-runner-dynamic-environment captured-environment
                  (run-test-case/internal suite test))))
      (flet ((run-batch (batch)
               (let ((threads
                       (loop for test in batch
                             collect (let ((worker-test test))
                                       (sb-thread:make-thread
                                        (lambda ()
                                          (run-captured-test worker-test))
                                        :name (format nil "cl-weave: ~A"
                                                      (test-case-name worker-test)))))))
                 (mapcar #'sb-thread:join-thread threads))))
        (run-worker-batches/k tests (worker-batch-size tests) #'run-batch #'identity))))
  #-sb-thread
  (mapcar (lambda (test)
            (run-test-case/internal suite test))
          tests))

(declaim (ftype (function (suite list execution-control function &optional t t t t t t t t) *) collect-children/k))

(defun collect-suite-events/k
    (suite control continue &optional focus-enabled ancestor-focused name-filter location-filter shard-paths suppressed-status suppressed-reason inherited-execution-mode)
  (if (or (execution-control-stopped control)
          (not (selected-suite-p suite focus-enabled ancestor-focused name-filter location-filter shard-paths)))
      (funcall continue '())
      (let ((active-execution-mode
              (effective-suite-execution-mode suite inherited-execution-mode)))
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
               location-filter
               shard-paths
               active-status
               active-reason
               active-execution-mode)
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
                       location-filter
                       shard-paths
                       nil
                       nil
                       active-execution-mode)))
                (call-hooks/k (reverse (suite-after-all suite)) (lambda () nil))))))))

(defun collect-children/k
    (suite children control continue &optional focus-enabled ancestor-focused name-filter location-filter shard-paths suppressed-status suppressed-reason execution-mode)
  (macrolet ((recur (remaining next-continue)
               `(collect-children/k
                 suite
                 ,remaining
                 control
                 ,next-continue
                 focus-enabled
                 ancestor-focused
                 name-filter
                 location-filter
                 shard-paths
                 suppressed-status
                 suppressed-reason
                 execution-mode)))
    (labels ((continue-with-tail (head-events remaining)
               (recur remaining
                      (lambda (tail)
                        (funcall continue (append head-events tail)))))
             (continue-with-event (event)
               (if (execution-control-stopped control)
                   (funcall continue (list event))
                   (recur (rest children)
                          (lambda (tail)
                            (funcall continue (cons event tail)))))))
      (if (or (null children) (execution-control-stopped control))
          (funcall continue '())
          (let ((child (first children)))
            (typecase child
              (suite
               (let ((child-focused (or ancestor-focused (suite-focus child))))
                 (if (selected-child-suite-p
                      child
                      focus-enabled
                      child-focused
                      name-filter
                      location-filter
                      shard-paths)
                     (collect-suite-events/k
                      child
                      control
                      (lambda (events)
                        (if (execution-control-stopped control)
                            (funcall continue events)
                            (continue-with-tail events (rest children))))
                      focus-enabled
                      child-focused
                      name-filter
                      location-filter
                      shard-paths
                      suppressed-status
                      suppressed-reason
                      execution-mode)
                     (recur (rest children) continue))))
              (test-case
               (if (selected-child-test-p
                    suite
                    child
                    focus-enabled
                    ancestor-focused
                    name-filter
                    location-filter
                    shard-paths)
                   (if (and (effective-concurrent-test-case-p child execution-mode)
                            (concurrent-batching-enabled-p control suppressed-status))
                       (multiple-value-bind (tests rest-children)
                           (collect-leading-concurrent-tests
                            suite
                            children
                            focus-enabled
                            ancestor-focused
                            name-filter
                            location-filter
                            shard-paths
                            execution-mode)
                         (continue-with-tail
                          (mapcar (lambda (event)
                                    (record-event/control control event))
                                  (run-concurrent-test-cases suite tests))
                          rest-children))
                       (continue-with-event
                        (record-event/control
                         control
                         (if suppressed-status
                             (suppressed-test-event suite child suppressed-status suppressed-reason)
                              (run-test-case/internal suite child)))))
                   (recur (rest children) continue)))
              (t
               (recur (rest children) continue))))))))

(defun call-with-collection-context
    (suite name-filter location-filter shard order seed retry timeout-ms max-workers continue)
  (let* ((focus-enabled (focused-suite-p suite))
         (normalized-filter (normalized-test-filter name-filter))
         (normalized-location-filter (normalize-location-filter location-filter))
         (normalized-shard (normalize-shard shard))
         (normalized-order (normalize-sequence-order order))
         (normalized-seed (normalize-sequence-seed seed))
         (normalized-retry (normalize-retry-count retry))
         (normalized-timeout-ms (normalize-timeout-ms timeout-ms))
         (normalized-max-workers (normalize-max-workers max-workers))
         (shard-paths (collect-shard-paths
                       suite
                       focus-enabled
                       normalized-filter
                       normalized-location-filter
                       normalized-shard)))
    (let ((*test-sequence-order* normalized-order)
          (*test-sequence-seed* normalized-seed)
          (*default-retry* normalized-retry)
          (*default-timeout-ms* normalized-timeout-ms)
          (*max-workers* normalized-max-workers))
      (funcall continue
               focus-enabled
               normalized-filter
               normalized-location-filter
               shard-paths))))

(defun collect-events (suite &key name-filter location-filter bail shard order seed retry timeout-ms max-workers)
  (with-runner-condition-propagation (nil)
    (call-with-collection-context
     suite
     name-filter
     location-filter
     shard
     order
     seed
     retry
     timeout-ms
     max-workers
     (lambda (focus-enabled normalized-filter normalized-location-filter shard-paths)
       (collect-suite-events/k
        suite
        (make-execution-control :bail-limit (normalize-bail bail))
        #'identity
        focus-enabled
        nil
        normalized-filter
        normalized-location-filter
        shard-paths)))))

(declaim (ftype (function (suite list function &optional t t t t t t t t) *) collect-children-plan/k))

(defun collect-suite-plan/k
    (suite continue &optional focus-enabled ancestor-focused name-filter location-filter shard-paths suppressed-status suppressed-reason inherited-execution-mode)
  (if (not (selected-suite-p suite focus-enabled ancestor-focused name-filter location-filter shard-paths))
      (funcall continue '())
      (let ((active-execution-mode
              (effective-suite-execution-mode suite inherited-execution-mode)))
        (multiple-value-bind (active-status active-reason)
            (suite-suppression suite suppressed-status suppressed-reason)
          (collect-children-plan/k
           suite
           (ordered-children suite (suite-children suite))
           continue
           focus-enabled
           ancestor-focused
           name-filter
           location-filter
           shard-paths
           active-status
           active-reason
           active-execution-mode)))))

(defun collect-children-plan/k
    (suite children continue &optional focus-enabled ancestor-focused name-filter location-filter shard-paths suppressed-status suppressed-reason execution-mode)
  (macrolet ((recur (remaining next-continue)
               `(collect-children-plan/k
                 suite
                 ,remaining
                 ,next-continue
                 focus-enabled
                 ancestor-focused
                 name-filter
                 location-filter
                 shard-paths
                 suppressed-status
                 suppressed-reason
                 execution-mode)))
    (labels ((continue-with-tail (entries)
               (recur (rest children)
                      (lambda (tail)
                        (funcall continue (append entries tail)))))
             (continue-with-entry (entry)
               (recur (rest children)
                      (lambda (tail)
                        (funcall continue (cons entry tail))))))
      (if (null children)
          (funcall continue '())
          (let ((child (first children)))
            (typecase child
              (suite
               (let ((child-focused (or ancestor-focused (suite-focus child))))
                 (if (selected-child-suite-p
                      child
                      focus-enabled
                      child-focused
                      name-filter
                      location-filter
                      shard-paths)
                     (collect-suite-plan/k
                      child
                      #'continue-with-tail
                      focus-enabled
                      child-focused
                      name-filter
                      location-filter
                      shard-paths
                      suppressed-status
                      suppressed-reason
                      execution-mode)
                     (recur (rest children) continue))))
              (test-case
               (if (selected-child-test-p
                    suite
                    child
                    focus-enabled
                    ancestor-focused
                    name-filter
                    location-filter
                    shard-paths)
                   (let* ((status (planned-test-status child suppressed-status))
                          (reason (planned-test-reason child suppressed-status suppressed-reason status))
                          (entry (make-plan-entry
                                  suite
                                  child
                                  status
                                  reason
                                  focus-enabled
                                  ancestor-focused
                                  execution-mode)))
                     (continue-with-entry entry))
                   (recur (rest children) continue)))
              (t
               (recur (rest children) continue))))))))

(defun collect-test-plan (suite &key name-filter location-filter shard order seed retry timeout-ms)
  (call-with-collection-context
   suite
   name-filter
   location-filter
   shard
   order
   seed
   retry
   timeout-ms
   nil
   (lambda (focus-enabled normalized-filter normalized-location-filter shard-paths)
     (collect-suite-plan/k
      suite
      #'identity
      focus-enabled
      nil
      normalized-filter
      normalized-location-filter
      shard-paths))))
