(in-package #:cl-weave)

(progn
  (defun eq-hash-test-p (hash-test)
    (or (eq hash-test (quote eq))
        (eq hash-test (function eq))
        (eq hash-test (symbol-function (quote eq)))))

  (defun eql-hash-test-p (hash-test)
    (or (eq hash-test (quote eql))
        (eq hash-test (function eql))
        (eq hash-test (symbol-function (quote eql)))))

  (defun candidate-hash-test-token (hash-test)
    (cond
      ((eq-hash-test-p hash-test) :eq)
      ((eql-hash-test-p hash-test) :eql)
      ((equal-hash-test-p hash-test) :equal)
      ((equalp-hash-test-p hash-test) :equalp)
      (t hash-test)))

  (defun candidate-hash-test-function (test-token)
    (case test-token
      (:eq (function eq))
      (:eql (function eql))
      (:equal (function equal))
      (:equalp (function equalp))
      (otherwise test-token)))

  (defstruct candidate-equality-node
    object
    test
    base
    unordered-p
    children
    parents
    (remaining 0)
    (color 0))

  (defun candidate-equality-class-ids (candidates hash-test)
    (let ((nodes nil)
          (pending nil)
          (atom-number 0)
          (container-caches (make-hash-table :test (function eq)))
          (atom-caches (make-hash-table :test (function eq))))
      (labels
          ((cache-for (test-token caches test)
             (multiple-value-bind (cache present-p)
                 (gethash test-token caches)
               (unless present-p
                 (setf cache (make-hash-table :test test)
                       (gethash test-token caches) cache))
               cache))
           (make-node (object test-token &key base unordered-p children expand-p)
             (let ((node
                     (make-candidate-equality-node
                      :object object
                      :test test-token
                      :base base
                      :unordered-p unordered-p
                      :children children)))
               (push node nodes)
               (when expand-p
                 (push node pending))
               node))
           (ensure-node (object test-token)
             (let* ((test
                      (candidate-hash-test-function test-token))
                    (equalp-test-p (eq test-token :equalp)))
               (if (and (member test-token (quote (:equal :equalp))) (candidate-container-p object equalp-test-p))
                   (let ((cache
                           (cache-for
                            test-token
                            container-caches
                            (function eq))))
                     (multiple-value-bind (node present-p)
                         (gethash object cache)
                       (unless present-p
                         (setf node
                               (make-node
                                object
                                test-token
                                :expand-p t)
                               (gethash object cache) node))
                       node))
                   (let ((cache
                           (cache-for test-token atom-caches test)))
                     (multiple-value-bind (node present-p)
                         (gethash object cache)
                       (unless present-p
                         (setf node
                               (make-node
                                object
                                test-token
                                :base
                                (list :atom (incf atom-number)))
                               (gethash object cache) node))
                       node)))))
           (entry-node (key value table-test value-test)
             (make-node
              nil
              value-test
              :base (list :entry)
              :children
              (list
               (ensure-node
                key
                (candidate-hash-test-token table-test))
               (ensure-node value value-test)))))
        (let* ((root-test (candidate-hash-test-token hash-test))
               (roots
                 (mapcar
                  (lambda (candidate)
                    (ensure-node candidate root-test))
                  candidates)))
          (loop while pending
                for node = (pop pending)
                for object = (candidate-equality-node-object node)
                for test-token = (candidate-equality-node-test node)
                do
                   (cond
                     ((consp object)
                      (setf
                       (candidate-equality-node-base node) (list :cons)
                       (candidate-equality-node-children node)
                       (list
                        (ensure-node (car object) test-token)
                        (ensure-node (cdr object) test-token))))
                     ((arrayp object)
                      (setf
                       (candidate-equality-node-base node)
                       (if (vectorp object)
                           (list :vector (length object))
                           (list :array (array-dimensions object)))
                       (candidate-equality-node-children node)
                       (loop for index below
                             (if (vectorp object)
                                 (length object)
                                 (array-total-size object))
                             collect
                             (ensure-node
                              (row-major-aref object index)
                              test-token))))
                     ((hash-table-p object)
                      (let ((entries nil)
                            (table-test (hash-table-test object)))
                        (maphash
                         (lambda (key value)
                           (push
                            (entry-node
                             key value table-test test-token)
                            entries))
                         object)
                        (setf
                         (candidate-equality-node-base node)
                         (list
                          :hash-table
                          table-test
                          (hash-table-count object))
                         (candidate-equality-node-unordered-p node) t
                         (candidate-equality-node-children node) entries)))
                     ((typep object (quote structure-object))
                      #+sbcl
                      (let ((boundness nil)
                            (children nil))
                        (dolist
                            (slot
                             (sb-mop:class-slots (class-of object)))
                          (let* ((name
                                   (sb-mop:slot-definition-name slot))
                                 (bound-p
                                   (slot-boundp object name)))
                            (push (not (null bound-p)) boundness)
                            (when bound-p
                              (push
                               (ensure-node
                                (slot-value object name)
                                test-token)
                               children))))
                        (setf
                         (candidate-equality-node-base node)
                         (list
                          :structure
                          (class-of object)
                          (nreverse boundness))
                         (candidate-equality-node-children node)
                         (nreverse children)))
                      #-sbcl
                      (error
                       "Cycle-safe structure equality is unsupported on this implementation."))))
          (dolist (node nodes)
            (setf
             (candidate-equality-node-remaining node)
             (length (candidate-equality-node-children node)))
            (dolist (child (candidate-equality-node-children node))
              (push node (candidate-equality-node-parents child))))
          (let ((queue nil)
                (processed nil)
                (fixed-class-count 0)
                (fixed-classes (make-hash-table :test (function equal))))
            (dolist (node nodes)
              (when (zerop (candidate-equality-node-remaining node))
                (push node queue)))
            (loop while queue
                  for node = (pop queue)
                  do
                     (push node processed)
                     (dolist (parent
                              (candidate-equality-node-parents node))
                       (when
                           (zerop
                            (decf
                             (candidate-equality-node-remaining
                              parent)))
                         (push parent queue))))
            (labels
                ((ordered-colors (node color-function)
                   (let ((colors
                           (mapcar
                            color-function
                            (candidate-equality-node-children node))))
                     (if (candidate-equality-node-unordered-p node)
                         (sort colors (function <))
                         colors))))
              (dolist (node (nreverse processed))
                (let* ((descriptor
                         (list
                          (candidate-equality-node-base node)
                          (ordered-colors
                           node
                           (lambda (child)
                             (candidate-equality-node-color child)))))
                       (color
                         (multiple-value-bind (existing present-p)
                             (gethash descriptor fixed-classes)
                           (if present-p
                               existing
                               (setf
                                (gethash descriptor fixed-classes)
                                (incf fixed-class-count))))))
                  (setf (candidate-equality-node-color node) color)))
              (let ((unresolved
                      (remove-if
                       (lambda (node)
                         (zerop
                          (candidate-equality-node-remaining node)))
                       nodes)))
                (when unresolved
                  (labels
                      ((encoded-child-color (child)
                         (if
                             (zerop
                              (candidate-equality-node-remaining child))
                             (ash
                              (candidate-equality-node-color child)
                              1)
                             (1+
                              (ash
                               (candidate-equality-node-color child)
                               1))))
                       (assign-partition (descriptor-function)
                         (let ((classes
                                 (make-hash-table
                                  :test (function equal)))
                               (class-count 0)
                               (next-colors
                                 (make-hash-table
                                  :test (function eq))))
                           (dolist (node unresolved)
                             (let* ((descriptor
                                      (funcall
                                       descriptor-function
                                       node))
                                    (color
                                      (multiple-value-bind
                                          (existing present-p)
                                          (gethash descriptor classes)
                                        (if present-p
                                            existing
                                            (setf
                                             (gethash descriptor classes)
                                             (incf class-count))))))
                               (setf (gethash node next-colors) color)))
                           (values next-colors class-count))))
                    (multiple-value-bind (colors class-count)
                        (assign-partition
                         (lambda (node)
                           (list
                            (candidate-equality-node-base node)
                            (ordered-colors
                             node
                             (lambda (child)
                               (if
                                   (zerop
                                    (candidate-equality-node-remaining
                                     child))
                                   (ash
                                    (candidate-equality-node-color child)
                                    1)
                                   1))))))
                      (maphash
                       (lambda (node color)
                         (setf
                          (candidate-equality-node-color node)
                          color))
                       colors)
                      (loop
                        (multiple-value-bind
                            (next-colors next-class-count)
                            (assign-partition
                             (lambda (node)
                               (list
                                (candidate-equality-node-color node)
                                (candidate-equality-node-base node)
                                (ordered-colors
                                 node
                                 (function encoded-child-color)))))
                          (when (= next-class-count class-count)
                            (maphash
                             (lambda (node color)
                               (setf
                                (candidate-equality-node-color node)
                                (+ fixed-class-count color)))
                             next-colors)
                            (return))
                          (setf class-count next-class-count)
                          (maphash
                           (lambda (node color)
                             (setf
                              (candidate-equality-node-color node)
                              color))
                           next-colors))))))))
            (mapcar
             (lambda (root)
               (candidate-equality-node-color root))
             roots)))))))

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

(defun state-machine-trace-p (trace)
    (and (finite-proper-list-p trace)
         (= (length trace) 8)
         (eq (first trace) :initial)
         (eq (third trace) :events)
         (finite-proper-list-p (fourth trace))
         (eq (fifth trace) :states)
         (finite-proper-list-p (sixth trace))
         (= (length (sixth trace)) (1+ (length (fourth trace))))
         (eq (seventh trace) :final)))

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
               (when (state-machine-trace-p trace)
                 (let ((trace-events (state-machine-trace-events trace)))
                   (when (<= min-length (length trace-events) max-length)
                     (loop for events in
                           (property-shrink-candidates events-generator trace-events)
                           collect (state-machine-trace initial-state
                                                        transition
                                                        events)))))))))

(defun gen-one-of (&rest generators)
  (let ((choices (ensure-property-generators generators "gen-one-of")))
    (make-property-generator
     :name :one-of
     :produce (lambda (rng)
                (let ((generator (nth (property-random-below rng (length choices))
                                      choices)))
                  (funcall (property-generator-produce generator) rng)))
     :shrink (lambda (value)
               (let ((candidates nil))
                 (dolist (generator choices)
                   (dolist (candidate
                            (property-shrink-candidates generator value))
                     (push candidate candidates)))
                 (remove-duplicate-shrink-candidates
                  (nreverse candidates) #'equal))))))

(defun gen-tuple (&rest generators)
  (let ((elements (ensure-property-generators generators "gen-tuple")))
    (make-property-generator
     :name :tuple
     :produce (lambda (rng)
                (loop for generator in elements
                      collect (funcall (property-generator-produce generator) rng)))
     :shrink (lambda (value)
               (when (and (finite-proper-list-p value)
                          (= (length value) (length elements)))
                 (let ((candidates nil))
                   (loop for generator in elements
                         for index from 0
                         for element in value
                         do (dolist
                                (shrunk
                                 (property-shrink-candidates generator element))
                              (push
                               (copy-sequence-and-set-item value index shrunk)
                               candidates)))
                   (remove-duplicate-shrink-candidates
                    (nreverse candidates) #'equal)))))))



(defun gen-such-that (predicate generator &key (attempts 100))
  (ensure-property-generator generator "gen-such-that")
  (unless (functionp predicate)
    (error "cl-weave: gen-such-that requires PREDICATE to be a function, got ~S."
           predicate))
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
                            (property-shrink-candidates generator value)))))

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
               (remove-duplicate-shrink-candidates
                (append (property-shrink-candidates base-generator value)
                        (property-shrink-candidates step value))
                #'equal)))
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
