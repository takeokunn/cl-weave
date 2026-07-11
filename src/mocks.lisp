(in-package #:cl-weave)

(defstruct mock-state
  implementation
  calls
  results
  restore
  #+sb-thread
  (lock (sb-thread:make-mutex :name "cl-weave mock state")))

(defvar *mock-states* (make-hash-table :test #'eq))

#+sb-thread
(defvar *mock-registry-lock*
  (sb-thread:make-mutex :name "cl-weave mock registry"))

(defun default-mock-implementation (&rest arguments)
  (declare (ignore arguments))
  nil)

(defun ensure-mock-implementation (implementation)
  (unless (functionp implementation)
    (error "cl-weave: mock implementation must be a function, got ~S."
           implementation))
  implementation)

(defmacro with-mock-state-lock ((state) &body body)
  #+sb-thread
  `(sb-thread:with-mutex ((mock-state-lock ,state))
     ,@body)
  #-sb-thread
  `(progn ,@body))

(defmacro with-mock-registry-lock (&body body)
  #+sb-thread
  `(sb-thread:with-mutex (*mock-registry-lock*)
     ,@body)
  #-sb-thread
  `(progn ,@body))

(defun mock-registry-entries ()
  ;; Never acquire a mock-state lock while holding the registry lock.  Bulk
  ;; operations work from this snapshot so their lock order cannot cycle.
  (with-mock-registry-lock
    (loop for mock being the hash-keys of *mock-states*
            using (hash-value state)
          collect (cons mock state))))

(defun register-mock-call (state arguments)
  (with-mock-state-lock (state)
    (let ((index (length (mock-state-calls state))))
      (setf (mock-state-calls state)
            (append (mock-state-calls state) (list arguments))
            (mock-state-results state)
            (append (mock-state-results state) (list '(:type :incomplete))))
      index)))

(defun register-mock-result (state index result)
  (with-mock-state-lock (state)
    (setf (nth index (mock-state-results state)) result)))

(defun mock-state-for (mock)
  (or (with-mock-registry-lock
        (gethash mock *mock-states*))
      (error "Value is not a cl-weave mock function: ~S" mock)))

(defun mock-thrown-result (condition)
  (list :type :throw
        :condition-type (class-name (class-of condition))
        :message (princ-to-string condition)))

(defun make-mock-function (&optional (implementation #'default-mock-implementation))
  (let* ((state (make-mock-state :implementation (ensure-mock-implementation implementation)
                                 :calls nil
                                 :results nil
                                 :restore nil))
          (mock (lambda (&rest arguments)
                  (let ((index (register-mock-call state arguments))
                        (completed nil)
                        (signaled-error nil))
                    (unwind-protect
                        (handler-bind
                            ((error
                               (lambda (condition)
                                 (setf signaled-error condition))))
                          (let* ((implementation
                                   (with-mock-state-lock (state)
                                     (mock-state-implementation state)))
                                 (values (multiple-value-list
                                          (apply implementation arguments))))
                            (register-mock-result state index
                                                  (list :type :return
                                                        :value (first values)
                                                        :values values))
                            (setf completed t)
                            (values-list values)))
                     (unless completed
                       (register-mock-result
                        state
                        index
                        (if signaled-error
                            (mock-thrown-result signaled-error)
                            '(:type :non-local-exit)))))))))
    (with-mock-registry-lock
      (setf (gethash mock *mock-states*) state))
    mock))

(defun mock-function-p (value)
  (with-mock-registry-lock
    (nth-value 1 (gethash value *mock-states*))))

(defun mock-calls (mock)
  (let ((state (mock-state-for mock)))
    (with-mock-state-lock (state)
      (copy-tree (mock-state-calls state)))))

(defun mock-results (mock)
  (let ((state (mock-state-for mock)))
    (with-mock-state-lock (state)
      (copy-tree (mock-state-results state)))))

(defun mock-implementation (mock implementation)
  (let ((state (mock-state-for mock))
        (implementation (ensure-mock-implementation implementation)))
    (with-mock-state-lock (state)
      (setf (mock-state-implementation state) implementation)))
  mock)

(defun mock-return-values (mock &rest values)
  (mock-implementation mock (lambda (&rest arguments)
                              (declare (ignore arguments))
                              (values-list values))))

(defun mock-return-value (mock value)
  (mock-return-values mock value))

(defun spy-on (symbol)
  (unless (symbolp symbol)
    (error "cl-weave: spy target must be a symbol, got ~S." symbol))
  (unless (fboundp symbol)
    (error "cl-weave: spy target must name a function cell, got ~S." symbol))
  (let* ((original (symbol-function symbol))
         (mock (make-mock-function original))
         (state (mock-state-for mock)))
    (setf (mock-state-restore state)
          (lambda ()
            (setf (mock-state-implementation state) original)
            (when (eq (symbol-function symbol) mock)
              (setf (symbol-function symbol) original))))
    (setf (symbol-function symbol) mock)
    mock))

(defun clear-mock (mock)
  (let ((state (mock-state-for mock)))
    (with-mock-state-lock (state)
      (setf (mock-state-calls state) nil
            (mock-state-results state) nil)))
  mock)

(defun reset-mock (mock)
  (mock-implementation mock #'default-mock-implementation)
  (clear-mock mock)
  mock)

(defun mock-restore (mock)
  (let* ((state (mock-state-for mock))
         (restore (mock-state-restore state)))
    (when restore
      (clear-mock mock)
      (funcall restore)
      (setf (mock-state-restore state) nil))
    mock))

(defun map-mocks (function)
  (dolist (entry (mock-registry-entries))
    (funcall function (car entry) (cdr entry)))
  t)

(defun clear-all-mocks ()
  (map-mocks (lambda (mock state)
               (declare (ignore state))
               (clear-mock mock))))

(defun reset-all-mocks ()
  (map-mocks (lambda (mock state)
               (declare (ignore state))
               (reset-mock mock))))

(defun restore-all-mocks ()
  (map-mocks (lambda (mock state)
               (when (mock-state-restore state)
                 (mock-restore mock)))))

(defun mock-called-with-p (mock expected-arguments)
  (some (lambda (actual-arguments)
          (equal actual-arguments expected-arguments))
        (mock-calls mock)))

(defun mock-returned-with-p (mock expected-values)
  (some (lambda (result)
          (and (eq (getf result :type) :return)
               (equal (getf result :values) expected-values)))
        (mock-results mock)))

(defun one-based-index-expected (index matcher)
  (unless (and (integerp index) (plusp index))
    (error "cl-weave: ~A expects a positive integer index, got ~S."
           matcher
           index))
  index)

(defun expected-index-and-tail (expected matcher)
  (when (null expected)
    (error "cl-weave: ~A expects an index followed by expected values." matcher))
  (values (one-based-index-expected (first expected) matcher)
          (rest expected)))

(defun nth-list-entry (entries index)
  (let ((tail (nthcdr (1- index) entries)))
    (values (first tail) (not (null tail)))))

(defun last-list-entry (entries)
  (let ((tail (last entries)))
    (values (first tail) (not (null tail)))))

(defun return-results (results)
  (remove-if-not (lambda (result)
                   (eq (getf result :type) :return))
                 results))

(defun mock-report (mock)
  (let ((calls (mock-calls mock))
        (results (mock-results mock)))
    (list :call-count (length calls)
          :calls calls
          :result-count (length results)
          :results results
          :return-count (count :return results
                               :key (lambda (result) (getf result :type)))
          :throw-count (count :throw results
                              :key (lambda (result) (getf result :type))))))
