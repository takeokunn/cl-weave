(in-package #:cl-weave)

(defvar *property-test-count* 100)
(defvar *property-seed* 8675309)
(defvar *recursive-generator-depth* nil)

(defparameter *property-shrink-max-steps* 1000)

(define-condition property-shrink-limit (error)
  ((values :initarg :values :reader property-shrink-limit-values)
   (steps :initarg :steps :reader property-shrink-limit-steps)
   (max-steps :initarg :max-steps :reader property-shrink-limit-max-steps))
  (:report (lambda (condition stream)
             (format stream "Property shrinking exceeded the ~D step limit at ~S."
                     (property-shrink-limit-max-steps condition)
                     (property-shrink-limit-values condition)))))

(defstruct property-rng
  state)

(defstruct property-generator
  name
  produce
  shrink)

;; Shrink functions must return a finite list. The shrink budget bounds candidate
;; evaluation, but cannot interrupt construction or traversal of an infinite list.

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

(defun ensure-property-shrink-max-steps (max-steps)
  (unless (and (integerp max-steps) (not (minusp max-steps)))
    (error 'type-error
           :datum max-steps
           :expected-type '(integer 0 *)))
  max-steps)

(defun consume-property-shrink-budget (values steps max-steps)
  (if (< steps max-steps)
      (1+ steps)
      (restart-case
          (error 'property-shrink-limit
                 :values values
                 :steps steps
                 :max-steps max-steps)
        (accept-current () nil))))

(defun parse-environment-integer (name value)
  (handler-case
      (parse-integer value :junk-allowed nil)
    (error ()
      (error "cl-weave: ~A must be an integer, got ~S." name value))))

(defun environment-integer (name fallback)
  (let ((value (uiop:getenv name)))
    (if (and value (plusp (length value)))
        (parse-environment-integer name value)
        fallback)))

(defun ensure-positive-property-count (count source)
  (unless (and (integerp count) (plusp count))
    (error "cl-weave: ~A must be a positive integer, got ~S." source count))
  count)

(defun property-test-count ()
  (ensure-positive-property-count
   (environment-integer "CL_WEAVE_PROPERTY_TESTS" *property-test-count*)
   "CL_WEAVE_PROPERTY_TESTS or *property-test-count*"))

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

(defun ensure-non-empty-sequence (value label)
  (unless (and (typep value 'sequence) (plusp (length value)))
    (error "cl-weave: ~A requires a non-empty sequence, got ~S." label value))
  value)

(defun gen-character (&key (alphabet "abcdefghijklmnopqrstuvwxyz"))
  (let ((choices (ensure-non-empty-sequence alphabet "gen-character ALPHABET")))
    (make-property-generator
     :name :character
     :produce (lambda (rng)
                (elt choices (property-random-below rng (length choices))))
     :shrink (lambda (value)
               (let ((first-character (elt choices 0)))
                 (unless (char= value first-character)
                   (list first-character)))))))

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

(defun gen-string (&key (min-length 0)
                        (max-length 16)
                        (alphabet "abcdefghijklmnopqrstuvwxyz"))
  (when (> min-length max-length)
    (error "cl-weave: gen-string requires MIN-LENGTH <= MAX-LENGTH, got ~S and ~S."
           min-length max-length))
  (let ((character-generator (gen-character :alphabet alphabet)))
    (make-property-generator
     :name :string
     :produce (lambda (rng)
                (let* ((length (+ min-length
                                  (property-random-below
                                   rng
                                   (1+ (- max-length min-length)))))
                       (value (make-string length)))
                  (loop for index from 0 below length
                        do (setf (char value index)
                                 (funcall (property-generator-produce
                                           character-generator)
                                          rng)))
                  value))
     :shrink (lambda (value)
               (let ((structural-candidates
                       (list "" (subseq value 0 (truncate (length value) 2))))
                     (character-candidates
                       (loop for index from 0 below (length value)
                             append
                             (loop for shrunk in
                                   (funcall (property-generator-shrink
                                             character-generator)
                                            (char value index))
                                   collect (let ((next (copy-seq value)))
                                             (setf (char next index) shrunk)
                                             next)))))
                 (remove-duplicates
                  (remove-if-not
                   (lambda (candidate)
                     (and (stringp candidate)
                          (<= min-length (length candidate) max-length)))
                   (append structural-candidates character-candidates))
                  :test #'string=))))))

(defun gen-vector (element-generator &key (min-length 0) (max-length 8))
  (ensure-property-generator element-generator "gen-vector")
  (when (> min-length max-length)
    (error "cl-weave: gen-vector requires MIN-LENGTH <= MAX-LENGTH, got ~S and ~S."
           min-length max-length))
  (make-property-generator
   :name :vector
   :produce (lambda (rng)
              (coerce
               (loop repeat (+ min-length
                               (property-random-below rng
                                                      (1+ (- max-length min-length))))
                     collect (funcall (property-generator-produce element-generator)
                                      rng))
               'vector))
   :shrink (lambda (value)
             (let ((structural-candidates
                     (list #() (subseq value 0 (truncate (length value) 2))))
                   (element-candidates
                     (loop for index from 0 below (length value)
                           append
                           (loop for shrunk in
                                 (funcall (property-generator-shrink element-generator)
                                          (aref value index))
                                 collect (let ((next (copy-seq value)))
                                           (setf (aref next index) shrunk)
                                           next)))))
               (remove-duplicates
                (remove-if-not
                 (lambda (candidate)
                   (and (vectorp candidate)
                        (<= min-length (length candidate) max-length)))
                 (append structural-candidates element-candidates))
                :test #'equalp)))))

(defun state-machine-trace (initial-state transition events)
  (let ((state initial-state)
        (states (list initial-state)))
    (dolist (event events)
      (setf state (funcall transition state event))
      (push state states))
    (let ((ordered-states (nreverse states)))
      (list :initial initial-state
            :events events
            :states ordered-states
            :final (car (last ordered-states))))))

(defun gen-state-machine (initial-state transition event-generator
                          &key (min-length 0) (max-length 16))
  (unless (functionp transition)
    (error "cl-weave: gen-state-machine requires TRANSITION to be a function, got ~S."
           transition))
  (let ((events-generator (gen-list event-generator
                                    :min-length min-length
                                    :max-length max-length)))
    (make-property-generator
     :name :state-machine
     :produce (lambda (rng)
                (state-machine-trace
                 initial-state
                 transition
                 (funcall (property-generator-produce events-generator) rng)))
     :shrink (lambda (trace)
               (loop for events in
                     (property-shrink-candidates events-generator
                                                 (getf trace :events))
                     collect (state-machine-trace initial-state
                                                  transition
                                                  events))))))

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
                          for next = (copy-list current)
                          do (setf (nth index next) candidate)
                          do (let ((next-steps
                                    (consume-property-shrink-budget
                                     current steps max-steps)))
                               (unless next-steps
                                 (return-from shrink-property-values current))
                               (setf steps next-steps))
                          do (let ((candidate-condition
                                    (property-failure-condition function next)))
                               (when (and (not (equal next current))
                                          (not (member next visited :test #'equal))
                                          candidate-condition
                                          (same-property-failure-p
                                           original candidate-condition))
                                 (setf current next
                                       changed t)
                                 (push next visited)
                                 (return)))))
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
