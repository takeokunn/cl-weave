(in-package #:cl-weave)

(defmacro describe (name &body body)
  `(register-suite ,name (lambda () ,@body)))

(defmacro describe-only (name &body body)
  `(register-suite ,name (lambda () ,@body) :focus t))

(defmacro it (name &body body)
  `(register-test ,name (lambda () ,@body)))

(defmacro it-only (name &body body)
  `(register-test ,name (lambda () ,@body) :focus t))

(defmacro it-skip (name &optional (reason "skipped"))
  `(register-test ,name (lambda () nil) :skip-reason ,reason))

(defmacro it-todo (name &optional (reason "todo"))
  `(register-test ,name (lambda () nil) :todo-reason ,reason))

(defmacro it-each (cases name bindings &body body)
  `(progn
     ,@(loop for case in cases
             collect `(it ,(apply #'format nil name case)
                         (destructuring-bind ,bindings ',case
                           ,@body)))))

(defvar *property-test-count* 100)
(defvar *property-seed* 8675309)

(defstruct property-rng
  state)

(defstruct property-generator
  name
  produce
  shrink)

(defun ensure-property-generator (value label)
  (unless (property-generator-p value)
    (error "cl-weave: ~A must be a property generator, got ~S." label value))
  value)

(defun ensure-property-generators (generators label)
  (when (null generators)
    (error "cl-weave: ~A requires at least one property generator." label))
  (mapcar (lambda (generator)
            (ensure-property-generator generator label))
          generators))

(defun environment-integer (name fallback)
  (or #+sbcl
      (let ((value (sb-ext:posix-getenv name)))
        (when value
          (parse-integer value)))
      #-sbcl nil
      fallback))

(defun property-test-count ()
  (environment-integer "CL_WEAVE_PROPERTY_TESTS" *property-test-count*))

(defun property-seed ()
  (environment-integer "CL_WEAVE_PROPERTY_SEED" *property-seed*))

(defun make-property-rng-from-seed (seed)
  (make-property-rng :state (mod (abs seed) 2147483648)))

(defun property-random-below (rng limit)
  (when (<= limit 0)
    (error "cl-weave: random limit must be positive, got ~S." limit))
  (setf (property-rng-state rng)
        (mod (+ (* (property-rng-state rng) 1103515245) 12345)
             2147483648))
  (mod (property-rng-state rng) limit))

(defun gen-integer (&key (min -100) (max 100))
  (when (> min max)
    (error "cl-weave: gen-integer requires MIN <= MAX, got ~S and ~S." min max))
  (make-property-generator
   :name :integer
   :produce (lambda (rng)
              (+ min (property-random-below rng (1+ (- max min)))))
   :shrink (lambda (value)
             (remove-duplicates
              (remove-if-not
               (lambda (candidate)
                 (and (integerp candidate) (<= min candidate max)))
               (list 0 min (truncate value 2)))
              :test #'eql))))

(defun gen-boolean ()
  (make-property-generator
   :name :boolean
   :produce (lambda (rng)
              (zerop (property-random-below rng 2)))
   :shrink (lambda (value)
             (if value (list nil) nil))))

(defun gen-member (values)
  (when (null values)
    (error "cl-weave: gen-member requires at least one value."))
  (make-property-generator
   :name :member
   :produce (lambda (rng)
              (nth (property-random-below rng (length values)) values))
   :shrink (lambda (value)
             (let ((first-value (first values)))
               (unless (eql value first-value)
                 (list first-value))))))

(defun gen-list (element-generator &key (min-length 0) (max-length 8))
  (ensure-property-generator element-generator "gen-list")
  (when (> min-length max-length)
    (error "cl-weave: gen-list requires MIN-LENGTH <= MAX-LENGTH, got ~S and ~S."
           min-length max-length))
  (make-property-generator
   :name :list
   :produce (lambda (rng)
              (loop repeat (+ min-length
                              (property-random-below rng
                                                     (1+ (- max-length min-length))))
                    collect (funcall (property-generator-produce element-generator) rng)))
   :shrink (lambda (value)
             (let ((structural-candidates
                     (list nil (subseq value 0 (truncate (length value) 2))))
                   (element-candidates
                     (loop for index from 0
                           for element in value
                           append
                           (loop for shrunk in
                                 (funcall (property-generator-shrink element-generator)
                                          element)
                                 collect (let ((next (copy-list value)))
                                           (setf (nth index next) shrunk)
                                           next)))))
               (remove-duplicates
                (remove-if-not
                 (lambda (candidate)
                   (and (listp candidate)
                        (<= min-length (length candidate) max-length)))
                 (append structural-candidates element-candidates))
                :test #'equal)))))

(defun gen-one-of (&rest generators)
  (let ((choices (ensure-property-generators generators "gen-one-of")))
    (make-property-generator
     :name :one-of
     :produce (lambda (rng)
                (let ((generator (nth (property-random-below rng (length choices))
                                      choices)))
                  (funcall (property-generator-produce generator) rng)))
     :shrink (lambda (value)
               (remove-duplicates
                (loop for generator in choices
                      append (funcall (property-generator-shrink generator) value))
                :test #'equal)))))

(defun gen-tuple (&rest generators)
  (let ((elements (ensure-property-generators generators "gen-tuple")))
    (make-property-generator
     :name :tuple
     :produce (lambda (rng)
                (loop for generator in elements
                      collect (funcall (property-generator-produce generator) rng)))
     :shrink (lambda (value)
               (remove-duplicates
                (loop for generator in elements
                      for index from 0
                      for element in value
                      append
                      (loop for shrunk in
                            (funcall (property-generator-shrink generator) element)
                            collect (let ((next (copy-list value)))
                                      (setf (nth index next) shrunk)
                                      next)))
                :test #'equal)))))

(defun gen-such-that (predicate generator &key (attempts 100))
  (ensure-property-generator generator "gen-such-that")
  (unless (and (integerp attempts) (plusp attempts))
    (error "cl-weave: gen-such-that requires a positive integer ATTEMPTS, got ~S."
           attempts))
  (make-property-generator
   :name :such-that
   :produce (lambda (rng)
              (loop repeat attempts
                    for value = (funcall (property-generator-produce generator) rng)
                    when (funcall predicate value)
                      return value
                    finally
                       (error "cl-weave: gen-such-that could not produce a matching value in ~D attempts."
                              attempts)))
   :shrink (lambda (value)
             (remove-if-not predicate
                            (funcall (property-generator-shrink generator) value)))))

(defun generated-property-values (generators rng)
  (mapcar (lambda (generator)
            (funcall (property-generator-produce generator) rng))
          generators))

(defun property-failure-condition (function values)
  (handler-case
      (progn
        (apply function values)
        nil)
    (condition (condition)
      condition)))

(defun shrink-property-values (generators values function)
  (loop with current = values
        for changed = nil
        do (loop for generator in generators
                 for index from 0
                 for value in current
                 do (loop for candidate in
                          (funcall (property-generator-shrink generator) value)
                          for next = (copy-list current)
                          do (setf (nth index next) candidate)
                          when (and (not (equal next current))
                                    (property-failure-condition function next))
                            do (setf current next
                                     changed t)
                               (return)))
        while changed
        finally (return current)))

(defun signal-property-failure (names form values minimal condition)
  (signal-assertion-failure
   (make-assertion-detail
    :form form
    :matcher :property
    :actual (list :values values
                  :minimal minimal
                  :condition (princ-to-string condition))
    :expected names
    :negated nil
    :pass nil)))

(defun run-property (generators function names form)
  (let ((rng (make-property-rng-from-seed (property-seed))))
    (loop repeat (property-test-count)
          for values = (generated-property-values generators rng)
          for condition = (property-failure-condition function values)
          when condition
            do (let ((minimal (shrink-property-values generators values function)))
                 (signal-property-failure names form values minimal condition))))
  t)

(defmacro it-property (name bindings &body body)
  (let ((names (mapcar #'first bindings))
        (generators (mapcar #'second bindings)))
    `(it ,name
       (run-property
        (list ,@generators)
        (lambda ,names ,@body)
        ',names
        '(it-property ,name ,bindings ,@body)))))

(defmacro test (name &body body)
  `(it ,name ,@body))

(defmacro test-only (name &body body)
  `(it-only ,name ,@body))

(defmacro test-skip (name &optional (reason "skipped"))
  `(it-skip ,name ,reason))

(defmacro test-todo (name &optional (reason "todo"))
  `(it-todo ,name ,reason))

(defmacro before-all (&body body)
  `(register-before-all (lambda () ,@body)))

(defmacro after-all (&body body)
  `(register-after-all (lambda () ,@body)))

(defmacro before-each (&body body)
  `(register-before-each (lambda () ,@body)))

(defmacro after-each (&body body)
  `(register-after-each (lambda () ,@body)))

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
    `(let ,(loop for value in values
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
       t)))

(defun expand-smart-truthy-assertion (actual form)
  (let ((value (gensym "ACTUAL-")))
    `(let ((,value ,actual))
       (unless ,value
         (signal-smart-assertion-failure
          ',form
          :truthy
          ,value
          t))
       t)))

(defun expand-smart-assertion (actual form)
  (if (smart-predicate-form-p actual)
      (expand-smart-predicate-assertion actual form)
      (expand-smart-truthy-assertion actual form)))

(defmacro expect (actual &body expectation)
  (if expectation
      (let ((value (gensym "ACTUAL-")))
        `(let ((,value ,actual))
           (assert-expectation
            ,value
            (list ,@expectation)
            '(expect ,actual ,@expectation))))
      (expand-smart-assertion actual `(expect ,actual))))

(defmacro with-snapshot-updates (&body body)
  `(let ((*update-snapshots* t))
     ,@body))

(defmacro with-mocked-functions (bindings &body body)
  (let ((saved (gensym "SAVED-")))
    `(let ((,saved
             (list
              ,@(loop for (place replacement) in bindings
                      collect place))))
       (unwind-protect
            (progn
              ,@(loop for (place replacement) in bindings
                      collect `(setf ,place ,replacement))
              ,@body)
         ,@(loop for (place nil) in bindings
                 for index from 0
                 collect `(setf ,place (nth ,index ,saved)))))))
