(in-package #:cl-weave)

(defvar *test-name-filter* nil)
(defvar *test-sequence-order* :defined)
(defvar *test-sequence-seed* 0)
(defvar *default-retry* 0)
(defvar *default-timeout-ms* nil)
(defvar *max-workers* nil)
(defvar *retry-budget-remaining* 0)
(defvar *runner-default-condition-handler-disabled* nil)
(defvar *runner-propagate-conditions* t)
(defvar *attempt-secondary-conditions* nil)

(defparameter *runner-dynamic-environment-variables*
  '(*root-suite*
    *current-suite*
    *test-context*
    *test-name-filter*
    *test-sequence-order*
    *test-sequence-seed*
    *default-retry*
    *retry-budget-remaining*
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

(defmacro with-escape-continuation ((continue) &body body)
  (let ((tag (gensym "ESCAPE-TAG"))
        (value (gensym "VALUE")))
    `(let ((,tag (cons 'escape-continuation nil)))
       (catch ,tag
         (let ((,continue (lambda (,value)
                            (throw ,tag ,value))))
           ,@body)))))

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

