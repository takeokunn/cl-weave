(in-package #:cl-weave)

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

