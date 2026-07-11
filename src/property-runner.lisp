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

(defun call-property-shrink-candidate/k
    (original function current visited index candidate accept reject)
  (let ((next (copy-list current)))
    (setf (nth index next) candidate)
    (let ((candidate-condition
            (property-failure-condition function next)))
      (if (and (not (equal next current))
               (not (member next visited :test #'equal))
               candidate-condition
               (same-property-failure-p original candidate-condition))
          (funcall accept next)
          (funcall reject)))))

(defun shrink-property-values (generators values function &optional original-condition)
  (loop with max-steps = (ensure-property-shrink-max-steps
                          *property-shrink-max-steps*)
        with original = (or original-condition
                            (property-failure-condition function values))
        with current = values
        with visited = (list values)
        with steps = 0
        for changed = nil
        do (loop for generator in generators
                 for index from 0
                 for value in current
                 do (loop for candidate in
                          (property-shrink-candidates generator value)
                          do (let ((next-steps
                                    (consume-property-shrink-budget
                                     current steps max-steps)))
                               (unless next-steps
                                 (return-from shrink-property-values current))
                               (setf steps next-steps))
                          when (call-property-shrink-candidate/k
                                original function current visited index candidate
                                (lambda (next)
                                  (setf current next
                                        changed t)
                                  (push next visited)
                                  t)
                                (lambda () nil))
                            do (return)))
        while changed
        finally (return current)))

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
