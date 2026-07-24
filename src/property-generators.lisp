(in-package #:cl-weave)

(defun gen-integer (&key (min -100) (max 100))
  (check-type min integer)
  (check-type max integer)
  (when (> min max)
    (error "cl-weave: gen-integer requires MIN <= MAX, got ~S and ~S." min max))
  (locally
      (declare (notinline make-integer-producer make-integer-shrinker))
    (let ((shrinker (make-integer-shrinker min max)))
      (make-property-generator
       :name :integer
       :produce (make-integer-producer min max)
       :shrink (lambda (value)
                 (when (integerp value)
                   (funcall shrinker value)))))))

(defun gen-boolean ()
  (make-property-generator
   :name :boolean
   :produce (lambda (rng)
              (zerop (property-random-below rng 2)))
   :shrink (lambda (value)
             (when (typep value 'boolean)
               (if value (list nil) nil)))))

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

(defun equalp-hash-test-p (hash-test)
  (or (eq hash-test (quote equalp))
      (eq hash-test (function equalp))
      (eq hash-test (symbol-function (quote equalp)))))

(defun candidate-container-p (value equalp-test-p)
  (or (consp value)
      (and equalp-test-p
           (or (arrayp value)
               (hash-table-p value)
               (typep value (quote structure-object))))))

(defun candidate-requires-safe-equality-p (value hash-test)
  (let ((equal-test-p (equal-hash-test-p hash-test))
        (equalp-test-p (equalp-hash-test-p hash-test)))
    (unless
        (and (or equal-test-p equalp-test-p)
             (candidate-container-p value equalp-test-p))
      (return-from candidate-requires-safe-equality-p nil))
    (let ((states (make-hash-table :test (function eq)))
          (pending (list (list value nil 0))))
      (loop while pending
            for frame = (pop pending)
            for node = (first frame)
            for complete-p = (second frame)
            for depth = (third frame)
            if complete-p
              do (setf (gethash node states) :complete)
            else
            when (candidate-container-p node equalp-test-p)
              do (when (>= depth 128)
                   (return-from candidate-requires-safe-equality-p t))
                 (case (gethash node states)
                   (:visiting
                    (return-from candidate-requires-safe-equality-p t))
                   (:complete)
                   (otherwise
                    (setf (gethash node states) :visiting)
                    (push (list node t depth) pending)
                    (let ((child-depth (1+ depth)))
                      (cond
                        ((consp node)
                         (push (list (cdr node) nil child-depth) pending)
                         (push (list (car node) nil child-depth) pending))
                        ((arrayp node)
                         (dotimes
                             (index
                              (if (vectorp node)
                                  (length node)
                                  (array-total-size node)))
                           (push (list (row-major-aref node index)
                                       nil
                                       child-depth)
                                 pending)))
                        ((hash-table-p node)
                         (maphash
                          (lambda (key item)
                            (push (list item nil child-depth) pending)
                            (push (list key nil child-depth) pending))
                          node))
                        ((typep node (quote structure-object))
                         #+sbcl
                         (dolist (slot (sb-mop:class-slots (class-of node)))
                           (let ((name (sb-mop:slot-definition-name slot)))
                             (when (slot-boundp node name)
                               (push (list (slot-value node name)
                                           nil
                                           child-depth)
                                     pending))))
                         #-sbcl
                         (return-from candidate-requires-safe-equality-p
                           t))))))
            finally (return nil)))))
(defun candidate-pair-seen-p (seen left right)
  (multiple-value-bind (rights present-p) (gethash left seen)
    (unless present-p
      (setf rights (make-hash-table :test #'eq)
            (gethash left seen) rights))
    (prog1
      (nth-value 1 (gethash right rights))
      (setf (gethash right rights) t))))

(defun equal-hash-test-p (hash-test)
  (or (eq hash-test (quote equal))
      (eq hash-test (function equal))
      (eq hash-test (symbol-function (quote equal)))))

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

(defun cycle-safe-candidate-equal-p
    (left right hash-test &optional initial-seen)
  (let ((pending (list (cons left right)))
        (seen (or initial-seen (make-hash-table :test (function eq))))
        (equalp-test-p (equalp-hash-test-p hash-test)))
    (loop while pending
          for pair = (pop pending)
          for left = (car pair)
          for right = (cdr pair)
          unless (eq left right)
            do (cond
                 ((and (consp left) (consp right))
                  (unless (candidate-pair-seen-p seen left right)
                    (push (cons (car left) (car right)) pending)
                    (push (cons (cdr left) (cdr right)) pending)))
                 ((or (consp left) (consp right))
                  (return-from cycle-safe-candidate-equal-p nil))
                 ((and equalp-test-p (arrayp left) (arrayp right))
                  (unless
                      (if (or (vectorp left) (vectorp right))
                          (and (vectorp left)
                               (vectorp right)
                               (= (length left) (length right)))
                          (equal (array-dimensions left)
                                 (array-dimensions right)))
                    (return-from cycle-safe-candidate-equal-p nil))
                  (unless (candidate-pair-seen-p seen left right)
                    (dotimes
                        (index
                         (if (vectorp left)
                             (length left)
                             (array-total-size left)))
                      (push (cons (row-major-aref left index)
                                  (row-major-aref right index))
                            pending))))
                 ((and equalp-test-p
                       (or (arrayp left) (arrayp right)))
                  (return-from cycle-safe-candidate-equal-p nil))
                 ((and equalp-test-p
      (hash-table-p left)
      (hash-table-p right))
  (unless
      (and (eq (hash-table-test left)
               (hash-table-test right))
           (= (hash-table-count left)
              (hash-table-count right)))
    (return-from cycle-safe-candidate-equal-p nil))
  (unless (candidate-pair-seen-p seen left right)
    (let ((table-test (hash-table-test left))
          (safe-left-entries nil)
          (safe-right-entries nil))
      (maphash
       (lambda (key value)
         (when (candidate-requires-safe-equality-p key table-test)
           (push (cons key value) safe-left-entries)))
       left)
      (maphash
       (lambda (key value)
         (when (candidate-requires-safe-equality-p key table-test)
           (push (cons key value) safe-right-entries)))
       right)
      (let* ((safe-left-count (length safe-left-entries))
             (safe-entries
               (append safe-left-entries safe-right-entries))
             (class-ids
               (candidate-equality-class-ids
                (mapcar (function car) safe-entries)
                table-test))
             (left-class-by-key
               (make-hash-table :test (function eq)))
             (right-entry-by-class
               (make-hash-table :test (function eql))))
        (loop for entry in safe-left-entries
              for class-id in class-ids
              do (setf
                  (gethash (car entry) left-class-by-key)
                  class-id))
        (loop for entry in safe-right-entries
              for class-id in (nthcdr safe-left-count class-ids)
              do (setf
                  (gethash class-id right-entry-by-class)
                  entry))
        (maphash
         (lambda (key left-value)
           (if (candidate-requires-safe-equality-p key table-test)
               (multiple-value-bind (class-id classified-p)
                   (gethash key left-class-by-key)
                 (declare (ignore classified-p))
                 (multiple-value-bind (right-entry present-p)
                     (gethash class-id right-entry-by-class)
                   (unless present-p
                     (return-from cycle-safe-candidate-equal-p nil))
                   (push (cons left-value (cdr right-entry)) pending)))
               (multiple-value-bind (right-value present-p)
                   (gethash key right)
                 (unless present-p
                   (return-from cycle-safe-candidate-equal-p nil))
                 (push (cons left-value right-value) pending))))
         left)))))
                 ((and equalp-test-p
                       (or (hash-table-p left) (hash-table-p right)))
                  (return-from cycle-safe-candidate-equal-p nil))
                 ((and equalp-test-p
                       (typep left (quote structure-object))
                       (typep right (quote structure-object)))
                  #+sbcl
                  (unless (eq (class-of left) (class-of right))
                    (return-from cycle-safe-candidate-equal-p nil))
                  #+sbcl
                  (unless (candidate-pair-seen-p seen left right)
                    (dolist (slot (sb-mop:class-slots (class-of left)))
                      (let* ((name (sb-mop:slot-definition-name slot))
                             (left-bound-p (slot-boundp left name))
                             (right-bound-p (slot-boundp right name)))
                        (unless (eq (not (null left-bound-p))
                                    (not (null right-bound-p)))
                          (return-from cycle-safe-candidate-equal-p nil))
                        (when left-bound-p
                          (push (cons (slot-value left name)
                                      (slot-value right name))
                                pending)))))
                  #-sbcl
                  (return-from cycle-safe-candidate-equal-p nil))
                 ((and equalp-test-p
                       (or (typep left (quote structure-object))
                           (typep right (quote structure-object))))
                  (return-from cycle-safe-candidate-equal-p nil))
                 ((not (funcall hash-test left right))
                  (return-from cycle-safe-candidate-equal-p nil)))
          finally (return t))))

(defun remove-duplicate-shrink-candidates (candidates hash-test)
  (let* ((processing (reverse candidates))
         (safe-flags
           (mapcar
            (lambda (candidate)
              (candidate-requires-safe-equality-p candidate hash-test))
            processing))
         (safe-candidates
           (loop for candidate in processing
                 for safe-p in safe-flags
                 when safe-p
                   collect candidate))
         (safe-class-ids
           (candidate-equality-class-ids safe-candidates hash-test))
         (unique nil)
         (seen (make-hash-table :test hash-test))
         (safe-seen (make-hash-table :test (function eql))))
    (loop for candidate in processing
          for safe-p in safe-flags
          do
             (if safe-p
                 (let ((class-id (pop safe-class-ids)))
                   (unless (nth-value 1 (gethash class-id safe-seen))
                     (push candidate unique)
                     (setf (gethash class-id safe-seen) t)))
                 (unless (nth-value 1 (gethash candidate seen))
                   (push candidate unique)
                   (setf (gethash candidate seen) t))))
    unique))

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

(defun sequence-shrink-candidates (value generator)
  (let ((candidates nil)
        (index 0))
    (map nil
         (lambda (element)
           (dolist (shrunk (property-shrink-candidates generator element))
             (push (copy-sequence-and-set-item value index shrunk)
                   candidates))
           (incf index))
         value)
    (nreverse candidates)))

(defun bounded-sequence-shrink-candidates (value
    min-length
    max-length
    predicate
    empty-value
    element-generator
    &key
    (hash-test #'equal))
  (when (funcall predicate value)
    (let ((value-length (length value)))
      (when (<= min-length value-length max-length)
        (let ((element-candidates (sequence-shrink-candidates value element-generator)))
          (remove-duplicate-shrink-candidates
            (remove-if-not
              (lambda (candidate)
                (and
                  (funcall predicate candidate)
                  (<= min-length (length candidate) max-length)))
              (list*
                empty-value
                (subseq value 0 (truncate value-length 2))
                element-candidates))
            hash-test))))))

(defun make-bounded-sequence-generator (name element-generator min-length max-length label predicate
                                             empty-value build-sequence &key (hash-test #'equal))
  (ensure-property-generator element-generator label)
  (ensure-bounded-sequence-lengths min-length max-length label)
  (let ((element-produce (property-generator-produce element-generator)))
    (make-property-generator
     :name name
     :produce (lambda (rng)
                (funcall build-sequence
                         (loop repeat (bounded-sequence-length min-length max-length rng)
                               collect (funcall element-produce rng))))
     :shrink (lambda (value)
               ;; Alternative generators (GEN-ONE-OF) may offer foreign values.
               (bounded-sequence-shrink-candidates
                value min-length max-length predicate empty-value element-generator
                :hash-test hash-test)))))

(defun gen-character (&key (alphabet "abcdefghijklmnopqrstuvwxyz"))
  (let ((choices (ensure-non-empty-sequence alphabet "gen-character ALPHABET")))
    (make-property-generator
     :name :character
     :produce (lambda (rng)
                (elt choices (property-random-below rng (length choices))))
     :shrink (lambda (value)
               (when (characterp value)
                 (let ((first-character (elt choices 0)))
                   (unless (char= value first-character)
                     (list first-character))))))))

(defun gen-member (values)
  (when (null values)
    (error "cl-weave: gen-member requires at least one value."))
  (make-property-generator
   :name :member
   :produce (lambda (rng)
              (nth (property-random-below rng (length values)) values))
   :shrink (lambda (value)
             (when (member value values :test #'equal)
               (let ((first-value (first values)))
                 (unless (equal value first-value)
                   (list first-value)))))))

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
                                     :hash-test #'equal)))

(defun gen-vector (element-generator &key (min-length 0) (max-length 8))
  (make-bounded-sequence-generator :vector element-generator min-length max-length "gen-vector"
                                   #'vectorp #() (lambda (items) (coerce items 'vector))
                                   :hash-test #'equalp))

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
