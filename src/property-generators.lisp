(in-package #:cl-weave)

(defun gen-integer (&key (min -100) (max 100))
  (check-type min integer)
  (check-type max integer)
  (when (> min max)
    (error "cl-weave: gen-integer requires MIN <= MAX, got ~S and ~S." min max))
  (locally
      (declare (notinline make-integer-producer make-integer-shrinker))
    (make-property-generator
     :name :integer
     :produce (make-integer-producer min max)
     :shrink (make-integer-shrinker min max))))

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

(defun ensure-bounded-sequence-lengths (min-length max-length label)
  (when (> min-length max-length)
    (error "cl-weave: ~A requires MIN-LENGTH <= MAX-LENGTH, got ~S and ~S."
           label min-length max-length)))

(defun bounded-sequence-length (min-length max-length rng)
  (+ min-length
     (property-random-below rng (1+ (- max-length min-length)))))

(defun copy-sequence-and-set-item (value index item)
  (etypecase value
    (list
     (let ((next (copy-list value)))
       (setf (nth index next) item)
       next))
    (string
     (let ((next (copy-seq value)))
       (setf (char next index) item)
       next))
    (vector
     (let ((next (copy-seq value)))
       (setf (aref next index) item)
       next))))

(defun sequence-shrink-candidates (value shrinker)
  (loop for index from 0 below (length value)
        append
        (loop for shrunk in (funcall shrinker (elt value index))
              collect (copy-sequence-and-set-item value index shrunk))))

(defun bounded-sequence-shrink-candidates (value min-length max-length predicate empty-value element-shrinker
                                             &key (test #'equal))
  (when (funcall predicate value)
    (let ((element-candidates (sequence-shrink-candidates value element-shrinker)))
      (remove-duplicates
       (remove-if-not
        (lambda (candidate)
          (and (funcall predicate candidate)
               (<= min-length (length candidate) max-length)))
        (append (list empty-value (subseq value 0 (truncate (length value) 2)))
                element-candidates))
       :test test))))

(defun make-bounded-sequence-generator (name element-generator min-length max-length label predicate
                                             empty-value build-sequence &key (test #'equal))
  (ensure-property-generator element-generator label)
  (ensure-bounded-sequence-lengths min-length max-length label)
  (let ((element-produce (property-generator-produce element-generator))
        (element-shrink (property-generator-shrink element-generator)))
    (make-property-generator
     :name name
     :produce (lambda (rng)
                (funcall build-sequence
                         (loop repeat (bounded-sequence-length min-length max-length rng)
                               collect (funcall element-produce rng))))
     :shrink (lambda (value)
               ;; Alternative generators (GEN-ONE-OF) may offer foreign values.
               (bounded-sequence-shrink-candidates
                value min-length max-length predicate empty-value element-shrink
                :test test)))))

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
  (make-bounded-sequence-generator :list element-generator min-length max-length "gen-list"
                                   #'finite-proper-list-p nil #'identity))

(defun gen-string (&key (min-length 0)
                        (max-length 16)
                        (alphabet "abcdefghijklmnopqrstuvwxyz"))
  (let ((character-generator (gen-character :alphabet alphabet)))
    (make-bounded-sequence-generator :string character-generator min-length max-length
                                     "gen-string" #'stringp "" (lambda (items) (coerce items 'string))
                                     :test #'string=)))

(defun gen-vector (element-generator &key (min-length 0) (max-length 8))
  (make-bounded-sequence-generator :vector element-generator min-length max-length "gen-vector"
                                   #'vectorp #() (lambda (items) (coerce items 'vector))
                                   :test #'equalp))

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

(defun state-machine-trace-events (trace)
  (getf trace :events))

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
                                                 (state-machine-trace-events trace))
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
