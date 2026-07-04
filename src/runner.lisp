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

(defun focused-child-p (child)
  (typecase child
    (suite
     (or (suite-focus child)
         (some #'focused-child-p (suite-children child))))
    (test-case
     (test-case-focus child))))

(defun focused-suite-p (suite)
  (some #'focused-child-p (suite-children suite)))

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

(declaim (ftype (function (suite list function &optional t t) *) collect-children/k))

(defun collect-suite-events/k (suite continue &optional focus-enabled ancestor-focused)
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
           ancestor-focused)))
    (call-hooks/k (reverse (suite-after-all suite)) (lambda () nil))))

(defun collect-children/k (suite children continue &optional focus-enabled ancestor-focused)
  (if (null children)
      (funcall continue '())
      (let ((child (first children)))
        (typecase child
          (suite
           (let ((selected (or (not focus-enabled)
                               ancestor-focused
                               (focused-child-p child))))
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
                     ancestor-focused))
                  focus-enabled
                  (or ancestor-focused (suite-focus child)))
                 (collect-children/k
                  suite
                  (rest children)
                  continue
                  focus-enabled
                  ancestor-focused))))
          (test-case
           (let ((selected (or (not focus-enabled)
                               ancestor-focused
                               (test-case-focus child))))
             (if selected
                 (let ((event (run-test-case suite child)))
                   (collect-children/k
                    suite
                    (rest children)
                    (lambda (tail)
                      (funcall continue (cons event tail)))
                    focus-enabled
                    ancestor-focused))
                 (collect-children/k
                  suite
                  (rest children)
                  continue
                  focus-enabled
                  ancestor-focused))))
          (t
           (collect-children/k
            suite
            (rest children)
            continue
            focus-enabled
            ancestor-focused))))))

(defun collect-events (suite)
  (collect-suite-events/k suite #'identity (focused-suite-p suite) nil))

(defun passed-event-p (event)
  (member (test-event-status event) '(:pass :skip :todo)))

(defun run-all (&key (reporter :spec) (stream *standard-output*))
  (let ((events (collect-events (root-suite))))
    (ecase reporter
      (:spec (report-spec events stream))
      (:sexp (report-sexp events stream))
      (:junit (report-junit events stream)))
    (every #'passed-event-p events)))
