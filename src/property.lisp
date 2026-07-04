(in-package #:cl-weave)

(defvar *property-test-count* 100)
(defvar *property-seed* 8675309)
(defvar *recursive-generator-depth* nil)

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

(defun property-shrink-candidates (generator value)
  (handler-case
      (funcall (property-generator-shrink generator) value)
    (error ()
      nil)))

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

(defun gen-map (function generator &key (name :map))
  (ensure-property-generator generator "gen-map")
  (unless (functionp function)
    (error "cl-weave: gen-map requires FUNCTION to be a function, got ~S."
           function))
  (make-property-generator
   :name name
   :produce (lambda (rng)
              (funcall function
                       (funcall (property-generator-produce generator) rng)))
   :shrink (lambda (value)
             (declare (ignore value))
             nil)))

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
                      append (property-shrink-candidates generator value))
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

(defun gen-recursive (base-generator builder &key (max-depth 4))
  (ensure-property-generator base-generator "gen-recursive")
  (unless (functionp builder)
    (error "cl-weave: gen-recursive requires BUILDER to be a function, got ~S."
           builder))
  (unless (and (integerp max-depth) (not (minusp max-depth)))
    (error "cl-weave: gen-recursive requires a non-negative integer MAX-DEPTH, got ~S."
           max-depth))
  (let (self step)
    (labels ((produce-value (rng)
               (let ((depth (or *recursive-generator-depth* max-depth)))
                 (if (<= depth 0)
                     (funcall (property-generator-produce base-generator) rng)
                     (let ((*recursive-generator-depth* (1- depth)))
                       (if (zerop (property-random-below rng 3))
                           (funcall (property-generator-produce base-generator) rng)
                           (funcall (property-generator-produce step) rng))))))
             (shrink-value (value)
               (remove-duplicates
                (append (property-shrink-candidates base-generator value)
                        (property-shrink-candidates step value))
                :test #'equal)))
      (setf self
            (make-property-generator
             :name :recursive-self
             :produce #'produce-value
             :shrink #'shrink-value))
      (setf step (funcall builder self))
      (ensure-property-generator step "gen-recursive builder")
      (make-property-generator
       :name :recursive
       :produce #'produce-value
       :shrink #'shrink-value))))

(defun gen-symbol (&key (names '("x" "y" "value" "state")) package)
  (gen-map
   (lambda (name)
     (if package
         (intern name package)
         (make-symbol name)))
   (gen-member names)
   :name :symbol))

(defun gen-keyword (&optional (names '("x" "y" "value" "state")))
  (gen-map
   (lambda (name)
     (intern name "KEYWORD"))
   (gen-member names)
   :name :keyword))

(defun gen-sexp (&key
                   (atoms (gen-one-of (gen-integer :min -8 :max 8)
                                      (gen-boolean)
                                      (gen-keyword)))
                   (max-depth 4)
                   (max-list-length 4))
  (gen-recursive
   atoms
   (lambda (self)
     (gen-list self :min-length 0 :max-length max-list-length))
   :max-depth max-depth))

(defun gen-form (&key
                   (atoms (gen-one-of (gen-integer :min -8 :max 8)
                                      (gen-boolean)
                                      (gen-symbol :package "CL-USER")))
                   (operators '(progn list cons + - *))
                   (max-depth 4)
                   (max-arguments 3))
  (gen-recursive
   atoms
   (lambda (self)
     (gen-map
      (lambda (parts)
        (destructuring-bind (operator arguments) parts
          (cons operator arguments)))
      (gen-tuple (gen-member operators)
                 (gen-list self :min-length 0 :max-length max-arguments))
      :name :form))
   :max-depth max-depth))

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
            do (let ((minimal (shrink-property-values generators values function)))
                 (signal-property-failure names form values minimal seed case-index condition))))
  t)
