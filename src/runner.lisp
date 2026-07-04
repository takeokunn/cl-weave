(in-package #:cl-weave)

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

(defun make-event (status suite test start &key condition assertion reason)
  (make-test-event
   :status status
   :path (test-path suite test)
   :condition condition
   :assertion assertion
   :reason reason
   :elapsed-internal-time (- (get-internal-real-time) start)))

(defun run-test-case (suite test)
  (let ((start (get-internal-real-time)))
    (if (test-case-skip-reason test)
        (make-event :skip suite test start :reason (test-case-skip-reason test))
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
            (make-event :error suite test start :condition condition))))))

(declaim (ftype (function (suite list function) *) collect-children/k))

(defun collect-suite-events/k (suite continue)
  (unwind-protect
       (call-hooks/k
        (suite-before-all suite)
        (lambda ()
          (collect-children/k
           suite
           (suite-children suite)
           (lambda (events)
             (funcall continue events)))))
    (call-hooks/k (reverse (suite-after-all suite)) (lambda () nil))))

(defun collect-children/k (suite children continue)
  (if (null children)
      (funcall continue '())
      (let ((child (first children)))
        (typecase child
          (suite
           (collect-suite-events/k
            child
            (lambda (events)
              (collect-children/k
               suite
               (rest children)
               (lambda (tail)
                 (funcall continue (append events tail)))))))
          (test-case
           (let ((event (run-test-case suite child)))
             (collect-children/k
              suite
              (rest children)
              (lambda (tail)
                (funcall continue (cons event tail))))))
          (t
           (collect-children/k suite (rest children) continue))))))

(defun collect-events (suite)
  (collect-suite-events/k suite #'identity))

(defun passed-event-p (event)
  (member (test-event-status event) '(:pass :skip)))

(defun run-all (&key (reporter :spec) (stream *standard-output*))
  (let ((events (collect-events (root-suite))))
    (ecase reporter
      (:spec (report-spec events stream))
      (:sexp (report-sexp events stream)))
    (every #'passed-event-p events)))
