(in-package #:cl-weave)

(defun suite-lineage (suite)
  (loop for current = suite then (suite-parent current)
        while current
        collect current into suites
        finally (return (nreverse suites))))

(defun effective-hook-lists (suite)
  (let ((before-hooks nil)
        (around-hooks nil)
        (after-hooks nil))
    (dolist (current (suite-lineage suite)
                     (values (nreverse before-hooks)
                             (nreverse around-hooks)
                             after-hooks))
      (dolist (hook (suite-hook current before-each))
        (push hook before-hooks))
      (dolist (hook (suite-hook current around-each))
        (push hook around-hooks))
      (dolist (hook (suite-hook current after-each))
        (push hook after-hooks)))))

(defun call-hooks/collect-errors (hooks)
  (loop for hook in hooks
        when (handler-case
                 (progn (funcall hook) nil)
               (serious-condition (condition) condition))
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
    (multiple-value-bind (before-hooks around-hooks after-hooks)
        (effective-hook-lists suite)
      (let ((primary-condition nil)
            (result nil)
            (cleanup-errors nil))
        ;; SERIOUS-CONDITION includes both ERROR and implementation conditions that
        ;; cannot be classified portably as ERROR, such as SBCL timeout conditions.
        (unwind-protect
             (handler-case
                 (setf result
                       (let ((before-errors
                               (call-hooks/collect-errors before-hooks)))
                         (when before-errors
                           (error 'hook-failure
                                  :phase :before-each
                                  :causes before-errors))
                         (call-around-hooks/k
                          around-hooks
                          (lambda ()
                            (funcall (test-case-function test))
                            (verify-assertion-counts)
                            (funcall continue)))))
               (serious-condition (condition)
                 (setf primary-condition condition)))
          (setf cleanup-errors
                (call-hooks/collect-errors after-hooks)))
        (cond
          (primary-condition
           (setf *attempt-secondary-conditions* cleanup-errors)
           (error primary-condition))
          (cleanup-errors
           (error 'hook-failure :phase :after-each :causes cleanup-errors))
          (t result))))))
