(in-package #:cl-weave)

(defun generated-property-values (generators rng)
  (mapcar (lambda (generator)
            (funcall (property-generator-produce generator) rng))
          generators))

(defun property-failure-condition (function values)
  (handler-case
      (progn
        (apply function values)
        nil)
    (error (condition)
      condition)))

(defgeneric same-property-failure-p (original candidate)
  (:documentation
   "Return true when CANDIDATE represents the same property failure as ORIGINAL."))

(defmethod same-property-failure-p ((original condition) (candidate condition))
  (eq (class-of original) (class-of candidate)))

(defmethod same-property-failure-p (original candidate)
  (declare (ignore original candidate))
  nil)

(defstruct (property-shrink-bounce
            (:constructor make-property-shrink-bounce (thunk)))
  (thunk nil :type function :read-only t))

(defun trampoline-property-shrink (step)
  (loop while (property-shrink-bounce-p step)
        do (setf step
                 (funcall (property-shrink-bounce-thunk step)))
        finally (return step)))

(defun property-shrink-state-with-attempt (state steps)
  (make-property-shrink-state
   :original (property-shrink-state-original state)
   :function (property-shrink-state-function state)
   :current (property-shrink-state-current state)
   :visited (property-shrink-state-visited state)
   :steps steps
   :max-steps (property-shrink-state-max-steps state)))

(defun property-shrink-state-with-current (state current)
  (make-property-shrink-state
   :original (property-shrink-state-original state)
   :function (property-shrink-state-function state)
   :current current
   :visited (cons current (property-shrink-state-visited state))
   :steps (property-shrink-state-steps state)
   :max-steps (property-shrink-state-max-steps state)))

(defun call-property-shrink-candidate/k (state index candidate accept reject)
  (let ((next (copy-list (property-shrink-state-current state))))
    (setf (nth index next) candidate)
    (let ((candidate-condition
            (property-failure-condition
             (property-shrink-state-function state) next)))
      (if (and (not (equal next (property-shrink-state-current state)))
               (not (member next (property-shrink-state-visited state)
                            :test #'equal))
               candidate-condition
               (same-property-failure-p
                (property-shrink-state-original state) candidate-condition))
          (funcall accept (property-shrink-state-with-current state next))
          (funcall reject state)))))

(defun try-property-shrink-candidates/k
    (state index candidates accept reject complete)
  (if (null candidates)
      (funcall reject state)
      (let ((next-steps
              (consume-property-shrink-budget
               (property-shrink-state-current state)
               (property-shrink-state-steps state)
               (property-shrink-state-max-steps state))))
        (if (null next-steps)
            (funcall complete state)
            (let ((attempted-state
                    (property-shrink-state-with-attempt state next-steps)))
              (call-property-shrink-candidate/k
               attempted-state index (first candidates) accept
               (lambda (rejected-state)
                 (make-property-shrink-bounce
                  (lambda ()
                    (try-property-shrink-candidates/k
                     rejected-state index (rest candidates)
                     accept reject complete))))))))))

(defun advance-property-shrink/k
    (state generators index accept complete)
  (if (null generators)
      (funcall complete state)
      (let* ((generator (first generators))
             (value (nth index (property-shrink-state-current state)))
             (candidates (property-shrink-candidates generator value)))
        (try-property-shrink-candidates/k
         state index candidates accept
         (lambda (rejected-state)
           (make-property-shrink-bounce
            (lambda ()
              (advance-property-shrink/k
               rejected-state (rest generators) (1+ index)
               accept complete))))
         complete))))

(defun shrink-property-state/k (state generators complete)
  (advance-property-shrink/k
   state generators 0
   (lambda (accepted-state)
     (make-property-shrink-bounce
      (lambda ()
        (shrink-property-state/k accepted-state generators complete))))
   complete))

(defun shrink-property-values (generators values function &optional original-condition)
  (let ((state
          (make-property-shrink-state
           :original (or original-condition
                         (property-failure-condition function values))
           :function function
           :current values
           :visited (list values)
           :steps 0
           :max-steps
           (ensure-property-shrink-max-steps *property-shrink-max-steps*))))
    (trampoline-property-shrink
     (shrink-property-state/k
      state generators
      (lambda (final-state)
        (property-shrink-state-current final-state))))))

(defun signal-property-failure (names form values minimal seed case-index condition)
  (signal-assertion-failure
   (make-assertion-detail
    :form form
    :matcher :property
    :actual (list :seed seed
                  :case-index case-index
                  :values values
                  :minimal minimal
                  :condition (princ-to-string condition))
    :expected names
    :negated nil
    :pass nil)))

(defun run-property (generators function names form)
  (let* ((seed (property-seed))
         (rng (make-property-rng-from-seed seed)))
    (loop for case-index from 0 below (property-test-count)
          for values = (generated-property-values generators rng)
          for condition = (property-failure-condition function values)
          when condition
            do (let ((minimal (shrink-property-values generators values function
                                                      condition)))
                 (signal-property-failure names form values minimal seed case-index condition))))
  t)
