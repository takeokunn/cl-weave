(in-package #:cl-weave)

(defvar *test-name-filter* nil)

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
       (handler-case
           (call-test-case/k
            suite
            test
            (lambda ()
              (make-event :pass suite test start)))
         (assertion-failure (condition)
           (make-event :fail suite test start
                       :condition condition
                       :assertion (failure-detail condition)))
         (condition (condition)
           (make-event :error suite test start :condition condition)))))))

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

(declaim (ftype (function (suite list function &optional t t t t t) *) collect-children/k))

(defun collect-suite-events/k
    (suite continue &optional focus-enabled ancestor-focused name-filter suppressed-status suppressed-reason)
  (if (selected-suite-p suite focus-enabled ancestor-focused name-filter)
      (multiple-value-bind (active-status active-reason)
          (suite-suppression suite suppressed-status suppressed-reason)
        (if active-status
            (collect-children/k
             suite
             (suite-children suite)
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
                     (lambda (events)
                       (funcall continue events))
                     focus-enabled
                     ancestor-focused
                     name-filter)))
              (call-hooks/k (reverse (suite-after-all suite)) (lambda () nil)))))
      (funcall continue '())))

(defun collect-children/k
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
                 (collect-suite-events/k
                  child
                  (lambda (events)
                    (collect-children/k
                     suite
                     (rest children)
                     (lambda (tail)
                       (funcall continue (append events tail)))
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
                 (collect-children/k
                  suite
                  (rest children)
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
                 (let ((event (if suppressed-status
                                  (suppressed-test-event suite child suppressed-status suppressed-reason)
                                  (run-test-case suite child))))
                   (collect-children/k
                    suite
                    (rest children)
                    (lambda (tail)
                      (funcall continue (cons event tail)))
                    focus-enabled
                    ancestor-focused
                    name-filter
                    suppressed-status
                    suppressed-reason))
                 (collect-children/k
                  suite
                  (rest children)
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
            continue
            focus-enabled
            ancestor-focused
            name-filter
            suppressed-status
            suppressed-reason))))))

(defun collect-events (suite &key name-filter)
  (collect-suite-events/k
   suite
   #'identity
   (focused-suite-p suite)
   nil
   (normalized-test-filter name-filter)))

(defun passed-event-p (event)
  (member (test-event-status event) '(:pass :skip :todo)))

(defun run-all (&key (reporter :spec)
                  (stream *standard-output*)
                  (name-filter *test-name-filter*))
  (let ((events (collect-events (root-suite) :name-filter name-filter)))
    (ecase reporter
      (:spec (report-spec events stream))
      (:sexp (report-sexp events stream))
      (:json (report-json events stream))
      (:junit (report-junit events stream)))
    (every #'passed-event-p events)))
