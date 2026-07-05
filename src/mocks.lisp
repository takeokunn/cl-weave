(in-package #:cl-weave)

(defstruct mock-state
  implementation
  calls
  results
  restore)

(defvar *mock-states* (make-hash-table :test #'eq))

(defun default-mock-implementation (&rest arguments)
  (declare (ignore arguments))
  nil)

(defun ensure-mock-implementation (implementation)
  (unless (functionp implementation)
    (error "cl-weave: mock implementation must be a function, got ~S."
           implementation))
  implementation)

(defun register-mock-call (state arguments)
  (setf (mock-state-calls state)
        (append (mock-state-calls state) (list arguments))))

(defun register-mock-result (state result)
  (setf (mock-state-results state)
        (append (mock-state-results state) (list result))))

(defun mock-state-for (mock)
  (or (gethash mock *mock-states*)
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
                 (register-mock-call state arguments)
                 (handler-case
                     (let ((values (multiple-value-list
                                    (apply (mock-state-implementation state) arguments))))
                       (register-mock-result state
                                             (list :type :return
                                                   :value (first values)
                                                   :values values))
                       (values-list values))
                   (condition (condition)
                     (register-mock-result state (mock-thrown-result condition))
                     (error condition))))))
    (setf (gethash mock *mock-states*) state)
    mock))

(defmacro define-vitest-mock-aliases (&body definitions)
  `(progn
     ,@(mapcar (lambda (definition)
                 (destructuring-bind (name lambda-list &body body) definition
                   `(defun ,name ,lambda-list
                      ,@body)))
               definitions)))

(defun mock-function-p (value)
  (nth-value 1 (gethash value *mock-states*)))

(defun mock-calls (mock)
  (copy-tree (mock-state-calls (mock-state-for mock))))

(defun mock-results (mock)
  (copy-tree (mock-state-results (mock-state-for mock))))

(defun mock-implementation (mock implementation)
  (setf (mock-state-implementation (mock-state-for mock))
        (ensure-mock-implementation implementation))
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
    (setf (mock-state-calls state) nil
          (mock-state-results state) nil))
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
  (maphash (lambda (mock state)
             (funcall function mock state))
           *mock-states*)
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

(define-vitest-mock-aliases
  (vi.fn (&optional (implementation #'default-mock-implementation))
    (make-mock-function implementation))
  (vi.ismockfunction (value)
    (mock-function-p value))
  (vi.mocked (value)
    (mock-function-p value))
  (vi.mockimplementation (mock implementation)
    (mock-implementation mock implementation))
  (vi.mockreturnvalues (mock &rest values)
    (apply #'mock-return-values mock values))
  (vi.mockreturnvalue (mock value)
    (mock-return-value mock value))
  (vi.spyon (symbol)
    (spy-on symbol))
  (vi.mockclear (mock)
    (clear-mock mock))
  (vi.mockreset (mock)
    (reset-mock mock))
  (vi.mockrestore (mock)
    (mock-restore mock))
  (vi.clearallmocks ()
    (clear-all-mocks))
  (vi.resetallmocks ()
    (reset-all-mocks))
  (vi.restoreallmocks ()
    (restore-all-mocks)))

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
