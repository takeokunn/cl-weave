(in-package #:cl-weave)

(defparameter *smart-assertion-operators*
  '(= /= < <= > >= eql equal equalp string= string-equal))

(defun smart-assertion-operator-p (operator)
  (member operator *smart-assertion-operators* :test #'eq))

(defun signal-smart-assertion-failure (form matcher actual expected)
  (signal-assertion-failure
   (make-assertion-detail
    :form form
    :matcher matcher
    :actual actual
    :expected expected
    :negated nil
    :pass nil)))

(defun operand-report-form (source value)
  (list :form source :value value))

(defun smart-predicate-form-p (form)
  (and (consp form)
       (symbolp (first form))
       (smart-assertion-operator-p (first form))
       (rest form)))

(defun expand-smart-predicate-assertion (actual form)
  (let* ((operator (first actual))
         (operands (rest actual))
         (values (loop for operand in operands collect (gensym "OPERAND-"))))
    `(progn
       (record-assertion)
       (let ,(loop for value in values
                   for operand in operands
                   collect `(,value ,operand))
         (unless (,operator ,@values)
           (signal-smart-assertion-failure
            ',form
            ',operator
            (list ,@(loop for operand in operands
                          for value in values
                          collect `(operand-report-form ',operand ,value)))
            ',actual))
         t))))

(defun expand-smart-truthy-assertion (actual form)
  (let ((value (gensym "ACTUAL-")))
    `(progn
       (record-assertion)
       (let ((,value ,actual))
         (unless ,value
           (signal-smart-assertion-failure
            ',form
            :truthy
            ,value
            t))
         t))))

(defun expand-smart-assertion (actual form)
  (if (smart-predicate-form-p actual)
      (expand-smart-predicate-assertion actual form)
      (expand-smart-truthy-assertion actual form)))

(defun expand-matcher-expectation (macro-name actual expectation &key negated)
  (when (null expectation)
    (error "cl-weave: ~A requires a matcher, for example (~(~A~) value :to-be expected)."
           macro-name
           macro-name))
  (let ((value (gensym "ACTUAL-"))
        (tokens (if negated
                    `(:not ,@expectation)
                    expectation)))
    `(progn
       (record-assertion)
       (let ((,value ,actual))
         (assert-expectation
          ,value
          (list ,@tokens)
          '(,macro-name ,actual ,@expectation))))))

(defun ensure-expect-thunk (thunk matcher form)
  (unless (functionp thunk)
    (signal-assertion-failure
     (make-assertion-detail
      :form form
      :matcher matcher
      :actual (list :callable nil :value thunk)
      :expected '(:callable t)
      :negated nil
      :pass nil)))
  thunk)

(defparameter *expect-poll-default-timeout-ms* 1000)
(defparameter *expect-poll-default-interval-ms* 50)

(defun split-expect-poll-body (body)
  (if (and body (option-plist-form-p (first body)))
      (values (first body) (rest body))
      (values nil body)))

(defun unknown-plist-keys (plist allowed-keys)
  (loop for (key nil) on plist by #'cddr
        unless (member key allowed-keys :test #'eq)
          collect key))

(defun normalize-expect-poll-options (options form)
  (let ((raw-options options))
    (unless (or (null raw-options)
                (option-plist-form-p raw-options))
      (error "cl-weave: EXPECT-POLL options in ~S must be a property list, got ~S."
             form
             raw-options))
    (let ((unknown-keys (unknown-plist-keys raw-options '(:timeout-ms :interval-ms))))
      (when unknown-keys
        (error "cl-weave: EXPECT-POLL options in ~S contain unsupported keys ~S."
               form
               unknown-keys))
      (let ((timeout-ms (if (plist-key-present-p raw-options :timeout-ms)
                            (getf raw-options :timeout-ms)
                            *expect-poll-default-timeout-ms*))
            (interval-ms (if (plist-key-present-p raw-options :interval-ms)
                             (getf raw-options :interval-ms)
                             *expect-poll-default-interval-ms*)))
        (unless (and (realp timeout-ms) (not (minusp timeout-ms)))
          (error "cl-weave: EXPECT-POLL :timeout-ms in ~S must be a non-negative real, got ~S."
                 form
                 timeout-ms))
        (unless (and (realp interval-ms) (not (minusp interval-ms)))
          (error "cl-weave: EXPECT-POLL :interval-ms in ~S must be a non-negative real, got ~S."
                 form
                 interval-ms))
        (list :timeout-ms timeout-ms
              :interval-ms interval-ms)))))

(defun elapsed-internal-time-ms (started-at)
  (/ (* (- (get-internal-real-time) started-at) 1000)
     internal-time-units-per-second))

(defun poll-last-assertion-report (detail)
  (list :matcher (assertion-detail-matcher detail)
        :actual (assertion-detail-actual detail)
        :expected (assertion-detail-expected detail)
        :negated (assertion-detail-negated detail)
        :pass (assertion-detail-pass detail)))

(defun signal-expect-poll-timeout (form timeout-ms interval-ms attempts last-value last-condition last-detail)
  (signal-assertion-failure
   (make-assertion-detail
    :form form
    :matcher :poll
    :actual (append
             (list :attempts attempts
                   :timeout-ms timeout-ms
                   :interval-ms interval-ms
                   :last-value last-value)
             (when last-condition
               (list :last-condition (rejected-thunk-report last-condition)))
             (when last-detail
               (list :last-assertion (poll-last-assertion-report last-detail))))
    :expected '(:state :pass)
    :negated nil
    :pass nil)))

(defun call-polling-expectation-thunk (thunk expectation options form)
  (let* ((callable (ensure-expect-thunk thunk :poll form))
         (normalized-options (normalize-expect-poll-options options form))
         (timeout-ms (getf normalized-options :timeout-ms))
         (interval-ms (getf normalized-options :interval-ms))
         (started-at (get-internal-real-time))
         (attempts 0)
         (last-value nil)
         (last-condition nil)
         (last-detail nil)
         (passed-p nil))
    (loop
      do (incf attempts)
        (handler-case
            (let ((value (funcall callable)))
              (setf last-value value
                    last-condition nil)
              (handler-case
                  (multiple-value-bind (pass detail)
                      (assert-expectation value expectation form)
                    (setf last-detail detail
                          passed-p pass))
                (assertion-failure (condition)
                  (setf last-detail (failure-detail condition)
                        passed-p nil)))
              (when (>= (elapsed-internal-time-ms started-at) timeout-ms)
                (signal-expect-poll-timeout form
                                            timeout-ms
                                            interval-ms
                                            attempts
                                            last-value
                                            last-condition
                                            last-detail))
              (when passed-p
                (return value)))
           (condition (condition)
             (setf last-condition condition)))
         (when (>= (elapsed-internal-time-ms started-at) timeout-ms)
           (signal-expect-poll-timeout form
                                       timeout-ms
                                       interval-ms
                                       attempts
                                       last-value
                                       last-condition
                                       last-detail))
         (when (plusp interval-ms)
           (sleep (/ interval-ms 1000.0))))))

(defun rejected-thunk-report (condition)
  (list :state :rejected
        :condition-type (type-of condition)
        :message (princ-to-string condition)))

(defun resolved-thunk-report (value)
  (list :state :resolved :value value))

(defun call-resolving-expectation-thunk (thunk form)
  (let ((callable (ensure-expect-thunk thunk :resolves form)))
    (handler-case
        (funcall callable)
      (condition (condition)
        (signal-assertion-failure
         (make-assertion-detail
          :form form
          :matcher :resolves
          :actual (rejected-thunk-report condition)
          :expected '(:state :resolved)
          :negated nil
          :pass nil))))))

(defun call-rejecting-expectation-thunk (thunk form)
  (let ((callable (ensure-expect-thunk thunk :rejects form)))
    (multiple-value-bind (rejected-p result)
        (handler-case
            (values nil (funcall callable))
          (condition (condition)
            (values t condition)))
      (if rejected-p
          result
          (signal-assertion-failure
           (make-assertion-detail
            :form form
            :matcher :rejects
            :actual (resolved-thunk-report result)
            :expected '(:state :rejected)
            :negated nil
            :pass nil))))))

