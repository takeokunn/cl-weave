(in-package #:cl-weave)

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
      ;; SERIOUS-CONDITION (not ERROR) so platform timeouts, which SBCL
      ;; signals as a bare serious condition, still reach the cleanup hooks.
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
        (serious-condition (condition)
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

