(in-package #:cl-weave/tests)

(describe "property generators and shrinker contracts"
  (it "validates integer generator bounds"
    (expect (lambda () (gen-integer :min 0.5)) :to-throw 'type-error)
    (expect (lambda () (gen-integer :max "10")) :to-throw 'type-error)
    (expect (lambda () (gen-integer :min 2 :max 1))
            :to-throw "MIN <= MAX"))

  (it "rejects invalid generator compositions at construction time"
    (expect-property-constructor-errors
     (list
      (list (lambda () (gen-character :alphabet "")) "non-empty sequence")
      (list (lambda () (gen-member nil)) "at least one value")
      (list (lambda () (gen-map :not-a-function (gen-boolean))) "FUNCTION")
      (list (lambda () (gen-map #'identity :not-a-generator)) "property generator")
      (list (lambda () (gen-list :not-a-generator)) "property generator")
      (list (lambda () (gen-list (gen-boolean) :min-length 2 :max-length 1))
            "MIN-LENGTH <= MAX-LENGTH")
      (list (lambda () (gen-string :min-length 2 :max-length 1))
            "MIN-LENGTH <= MAX-LENGTH")
      (list (lambda () (gen-vector :not-a-generator)) "property generator")
      (list (lambda () (gen-vector (gen-boolean) :min-length 2 :max-length 1))
            "MIN-LENGTH <= MAX-LENGTH")
      (list (lambda () (gen-one-of)) "at least one property generator")
      (list (lambda () (gen-tuple (gen-boolean) :not-a-generator))
            "property generator")
      (list (lambda () (gen-such-that #'identity (gen-boolean) :attempts 0))
            "positive integer ATTEMPTS")
      (list (lambda () (gen-such-that #'identity :not-a-generator))
            "property generator")
      (list (lambda () (gen-recursive (gen-boolean) :not-a-function))
            "BUILDER")
      (list (lambda () (gen-recursive (gen-boolean) #'identity :max-depth -1))
            "non-negative integer MAX-DEPTH"))))

  (it "keeps integer production and shrinking within bounds"
    (let* ((singleton (gen-integer :min 5 :max 5))
           (positive (gen-integer :min 2 :max 10))
           (negative (gen-integer :min -10 :max -2))
           (rng (cl-weave::make-property-rng :state 1)))
      (expect (funcall (cl-weave::property-generator-produce singleton) rng)
              :to-be 5)
      (expect (funcall (cl-weave::property-generator-shrink positive) 8)
              :to-equal '(2 4))
      (expect (funcall (cl-weave::property-generator-shrink negative) -8)
              :to-equal '(-10 -4))))

  (it "shrinks heterogeneous one-of values through matching built-in domains"
    (let ((generator (gen-one-of (gen-character :alphabet "ab")
                                 (gen-integer :min 0 :max 10))))
      (expect (cl-weave::property-shrink-candidates generator 5)
              :to-equal (list 0 2))
      (expect (cl-weave::property-shrink-candidates generator #\b)
              :to-equal (list #\a))))

  (it "guards structured shrinkers from foreign one-of values"
    (let ((state-machine
            (gen-one-of
             (gen-state-machine 0
                                (lambda (state event)
                                  (declare (ignore event))
                                  (1+ state))
                                (gen-member (list :inc)))
             (gen-member (list :foreign :other))))
          (tuple
            (gen-one-of
             (gen-tuple (gen-integer :min 0 :max 10) (gen-boolean))
             (gen-integer :min 0 :max 10))))
      (expect (cl-weave::property-shrink-candidates state-machine :other)
              :to-equal (list :foreign))
      (expect (cl-weave::property-shrink-candidates tuple 8)
              :to-equal (list 0 4))))

  (it "does not hide genuine shrinker failures in one-of"
    (let* ((cause (make-condition 'simple-error :format-control "broken"))
           (broken
             (cl-weave::make-property-generator
              :name :broken
              :produce #'identity
              :shrink (lambda (value)
                        (declare (ignore value))
                        (error cause))))
           (generator (gen-one-of (gen-character :alphabet "ab") broken)))
      (expect (lambda ()
                (cl-weave::property-shrink-candidates generator #\b))
              :to-throw 'property-shrinker-error)))

  (it "deduplicates recursive shrink candidates by last occurrence"
    (let* ((base
             (cl-weave::make-property-generator
              :name :base
              :produce #'identity
              :shrink (lambda (value)
                        (declare (ignore value))
                        '((:shared) (:base) (:shared)))))
           (step
             (cl-weave::make-property-generator
              :name :step
              :produce #'identity
              :shrink (lambda (value)
                        (declare (ignore value))
                        '((:step) (:shared)))))
           (generator
             (gen-recursive base
                            (lambda (self)
                              (declare (ignore self))
                              step))))
      (expect (cl-weave::property-shrink-candidates generator :value)
              :to-equal '((:base) (:step) (:shared)))))

  (it "exposes shrinker failures with recovery restarts"
    (let* ((attempts 0)
           (cause (make-condition 'simple-error :format-control "broken"))
           (generator
             (cl-weave::make-property-generator
              :name :broken
              :produce #'identity
              :shrink (lambda (value)
                        (declare (ignore value))
                        (incf attempts)
                        (if (= attempts 1)
                            (error cause)
                            '(:recovered))))))
      (handler-bind
          ((property-shrinker-error
             (lambda (condition)
               (expect (property-shrinker-error-generator condition)
                       :to-be generator)
               (expect (property-shrinker-error-value condition) :to-be :value)
               (expect (property-shrinker-error-cause condition) :to-be cause)
               (let ((restart (find-restart 'retry-shrinker condition)))
                 (expect restart :not :to-be nil)
                 (invoke-restart restart)))))
        (expect (cl-weave::property-shrink-candidates generator :value)
                :to-equal '(:recovered)))
      (handler-bind
          ((property-shrinker-error
             (lambda (condition)
               (let ((restart (find-restart 'use-value condition)))
                 (expect restart :not :to-be nil)
                 (invoke-restart restart '(:replacement))))))
        (setf attempts 0)
        (expect (cl-weave::property-shrink-candidates generator :value)
                :to-equal '(:replacement)))
      (handler-bind
          ((property-shrinker-error
             (lambda (condition)
               (let ((restart (find-restart 'skip-shrinking condition)))
                 (expect restart :not :to-be nil)
                 (invoke-restart restart)))))
        (setf attempts 0)
        (expect (cl-weave::property-shrink-candidates generator :value)
                :to-be nil))
      (setf attempts 0)
      (handler-case
          (progn
            (cl-weave::property-shrink-candidates generator :value)
            (error "Expected the shrinker error to be signaled."))
        (property-shrinker-error (condition)
          (expect (property-shrinker-error-cause condition) :to-be cause)))))

  (it "deduplicates circular candidates without looping"
    (let* ((cycle-a (cons :cycle nil))
           (cycle-b (cons :cycle nil))
           (cycle-last (cons :cycle nil))
           (shared-tail (list :tail))
           (shared-a (cons :shared shared-tail))
           (shared-b (cons :shared shared-tail))
           (source
             (cl-weave::make-property-generator
              :name :circular-candidates
              :produce #'identity
              :shrink (lambda (value)
                        (declare (ignore value))
                        (list cycle-a shared-a cycle-b shared-b cycle-last))))
           (idle
             (cl-weave::make-property-generator
              :name :idle
              :produce #'identity
              :shrink (lambda (value)
                        (declare (ignore value))
                        nil)))
           (one-of (gen-one-of source))
           (tuple (gen-tuple source idle)))
      (setf (cdr cycle-a) cycle-a
            (cdr cycle-b) cycle-b
            (cdr cycle-last) cycle-last)
      (flet ((exercise ()
               (let ((direct
                       (cl-weave::remove-duplicate-shrink-candidates
                        (list cycle-a shared-a cycle-b shared-b cycle-last)
                        #'equal))
                     (one-of-candidates
                       (cl-weave::property-shrink-candidates one-of :value))
                     (tuple-candidates
                       (cl-weave::property-shrink-candidates
                        tuple
                        (list :left :right))))
                 (expect (length direct) :to-be 2)
                 (expect (first direct) :to-be shared-b)
                 (expect (second direct) :to-be cycle-last)
                 (expect (length one-of-candidates) :to-be 2)
                 (expect (first one-of-candidates) :to-be shared-b)
                 (expect (second one-of-candidates) :to-be cycle-last)
                 (expect (length tuple-candidates) :to-be 2)
                 (expect (first (first tuple-candidates)) :to-be shared-b)
                 (expect (second (first tuple-candidates)) :to-be :right)
                 (expect (first (second tuple-candidates)) :to-be cycle-last)
                 (expect (second (second tuple-candidates)) :to-be :right))))
        #+sbcl
        (sb-ext:with-timeout 2
          (exercise))
        #-sbcl
        (exercise))))

  (it "rejects non-list and improper shrink candidates without traversing cycles"
    (dolist (candidates
             (list #(:vector)
                   (cons :head :tail)
                   (let ((cycle (list :cycle)))
                     (setf (cdr cycle) cycle)
                     cycle)))
      (let* ((generator
               (cl-weave::make-property-generator
                :name :invalid-candidates
                :produce #'identity
                :shrink (lambda (value)
                          (declare (ignore value))
                          candidates)))
             (cause nil))
        (handler-bind
            ((property-shrinker-error
               (lambda (condition)
                 (setf cause (property-shrinker-error-cause condition))
                 (expect (find-restart 'retry-shrinker condition)
                         :not :to-be nil)
                 (expect (find-restart 'use-value condition)
                         :not :to-be nil)
                 (expect (find-restart 'skip-shrinking condition)
                         :not :to-be nil)
                 (invoke-restart (find-restart 'skip-shrinking condition)))))
          (expect (cl-weave::property-shrink-candidates generator :value)
                  :to-be nil))
        (expect cause :to-satisfy (lambda (condition)
                                    (typep condition 'error))))))

  (it "validates replacement shrink candidates under the same restarts"
    (let ((generator
            (cl-weave::make-property-generator
             :name :replacement
             :produce #'identity
             :shrink (lambda (value)
                       (declare (ignore value))
                       (error "initial failure"))))
          (signals 0))
      (handler-bind
          ((property-shrinker-error
             (lambda (condition)
               (incf signals)
               (let ((restart (find-restart 'use-value condition)))
                 (expect restart :not :to-be nil)
                 (invoke-restart restart
                                 (if (= signals 1)
                                     #(:invalid)
                                     '(:valid)))))))
        (expect (cl-weave::property-shrink-candidates generator :value)
                :to-equal '(:valid)))
      (expect signals :to-be 2)))

  (it "recognizes only finite proper shrink candidate lists"
    (dolist (value (list nil '(:one) '(:one :two)))
      (expect (cl-weave::finite-proper-list-p value) :to-be t))
    (dolist (value (list :atom (cons :head :tail)))
      (expect (cl-weave::finite-proper-list-p value) :to-be nil))
    (let ((cycle (list :cycle)))
      (setf (cdr cycle) cycle)
      (expect (cl-weave::finite-proper-list-p cycle) :to-be nil)))

  (it "prints actionable shrinker failure diagnostics"
    (let* ((generator
             (cl-weave::make-property-generator
              :name :diagnostic-generator
              :produce #'identity
              :shrink #'identity))
           (condition
             (make-condition 'property-shrinker-error
                             :generator generator
                             :value '(:input 7)
                             :cause (make-condition
                                     'simple-error
                                     :format-control "invalid candidate")))
           (message (princ-to-string condition)))
      (dolist (fragment '("DIAGNOSTIC-GENERATOR"
                          "(:INPUT 7)"
                          "invalid candidate"))
        (expect message :to-contain fragment))))

  (it-property "checks integer addition commutativity"
      ((left (gen-integer :min -20 :max 20))
       (right (gen-integer :min -20 :max 20)))
    (expect (+ left right) :to-be (+ right left)))

  (it-property "checks list reversal involution"
      ((values (gen-list (gen-member '(:a :b :c)) :max-length 6)))
    (expect (reverse (reverse values)) :to-equal values))

  (it-property "checks boolean identity"
      ((flag (gen-boolean)))
    (expect (not (not flag)) :to-be flag))

  (it-property "composes tuple generators"
      ((pair (gen-tuple (gen-integer :min 0 :max 10)
                        (gen-member '(:ok :retry)))))
    (destructuring-bind (count state) pair
      (expect count :to-satisfy (lambda (value) (<= 0 value 10)))
      (expect '(:ok :retry) :to-contain state)))

  (it-property "filters generated values"
      ((even (gen-such-that #'evenp (gen-integer :min 0 :max 20))))
    (expect even :to-satisfy #'evenp))

  (it-property "chooses among generator alternatives"
      ((value (gen-one-of (gen-member '(:left :right))
                          (gen-member '(:up :down)))))
    (expect '(:left :right :up :down) :to-contain value))

  (it-property "generates bounded recursive s-expressions"
      ((form (gen-recursive
              (gen-member '(:x :y 0 1))
              (lambda (self)
                (gen-one-of
                 (gen-list self :min-length 1 :max-length 3)
                 (gen-tuple (gen-member '(quote if progn)) self)))
              :max-depth 3)))
    (expect (tree-depth form) :to-be-less-than-or-equal 4)
    (expect form :to-satisfy (lambda (value) (or (atom value) (consp value)))))

  (it-property "maps generated values"
      ((value (gen-map #'1+ (gen-integer :min 0 :max 5))))
    (expect value :to-satisfy (lambda (number) (<= 1 number 6))))

  (it-property "generates symbols and keywords"
      ((symbol (gen-symbol :names '("ALPHA" "BETA") :package "CL-USER"))
       (keyword (gen-keyword '("LEFT" "RIGHT"))))
    (expect symbol :to-satisfy #'symbolp)
    (expect (symbol-package symbol) :to-be (find-package "CL-USER"))
    (expect keyword :to-satisfy #'keywordp))

  (it-property "generates characters from an alphabet"
      ((character (gen-character :alphabet "abc")))
    (expect character :to-satisfy #'characterp)
    (expect "abc" :to-contain (string character)))

  (it-property "generates bounded strings"
      ((value (gen-string :min-length 2 :max-length 5 :alphabet "ab")))
    (expect value :to-satisfy #'stringp)
    (expect value :to-satisfy
            (lambda (string)
              (<= 2 (length string) 5)))
    (expect value :to-satisfy
            (lambda (string)
              (every (lambda (character)
                       (find character "ab" :test #'char=))
                     string))))

  (it-property "generates bounded vectors"
      ((value (gen-vector (gen-member '(:left :right))
                          :min-length 1
                          :max-length 4)))
    (expect value :to-satisfy #'vectorp)
    (expect value :to-satisfy
            (lambda (vector)
              (<= 1 (length vector) 4)))
    (expect value :to-satisfy
            (lambda (vector)
              (every (lambda (entry)
                       (member entry '(:left :right)))
                     vector))))

  (it-property "generates replayable state-machine traces"
      ((trace (gen-state-machine
               0
               (lambda (state event)
                 (ecase event
                   (:inc (1+ state))
                   (:dec (1- state))
                   (:reset 0)))
               (gen-member '(:inc :dec :reset))
               :min-length 1
               :max-length 5)))
    (let ((events (getf trace :events))
          (states (getf trace :states)))
      (expect (getf trace :initial) :to-be 0)
      (expect events :to-satisfy
              (lambda (value)
                (<= 1 (length value) 5)))
      (expect states :to-satisfy
              (lambda (value)
                (= (length value) (1+ (length events)))))
      (expect (first states) :to-be 0)
      (expect (getf trace :final) :to-be (first (last states)))))

  (it-property "generates bounded s-expression trees"
      ((form (gen-sexp :max-depth 3 :max-list-length 3)))
    (expect (tree-depth form) :to-be-less-than-or-equal 4)
    (expect form :to-satisfy (lambda (value) (or (atom value) (consp value)))))

  (it-property "generates operator-headed forms"
      ((form (gen-form :operators '(progn list)
                       :max-depth 2
                       :max-arguments 2)))
    (expect form :to-satisfy
            (lambda (value)
              (or (atom value)
                  (and (consp value)
                       (member (first value) '(progn list)))))))

  (it "short-circuits element shrinking for oversized sequences"
    (let* ((shrink-calls 0)
           (element-generator
             (cl-weave::make-property-generator
              :name :counted-element
              :produce #'identity
              :shrink (lambda (value)
                        (declare (ignore value))
                        (incf shrink-calls)
                        nil)))
           (generator (gen-vector element-generator :max-length 16))
           (bounded-candidates
             (cl-weave::property-shrink-candidates
              generator
              (make-array 8 :initial-element :value))))
      (expect shrink-calls :to-be 8)
      (expect (length bounded-candidates) :to-be 2)
      (expect (length (first bounded-candidates)) :to-be 0)
      (expect (length (second bounded-candidates)) :to-be 4)
      (setf shrink-calls 0)
      (let ((oversized (make-array 2000000 :initial-element :value)))
        #+sbcl
        (sb-ext:gc :full t)
        (let* ((before
                 #+sbcl (sb-ext:get-bytes-consed)
                 #-sbcl 0)
               (oversized-candidates
                 (cl-weave::property-shrink-candidates generator oversized))
               (allocated
                 #+sbcl (- (sb-ext:get-bytes-consed) before)
                 #-sbcl 0))
          (expect shrink-calls :to-be 0)
          (expect oversized-candidates :to-equal nil)
          #+sbcl
          (expect (< allocated (* 1024 1024)) :to-be t)))))

  (it "validates malformed and failing child shrinkers through composites"
    (let ((cycle (list :cycle))
          (cause (make-condition 'simple-error :format-control "child failed")))
      (setf (cdr cycle) cycle)
      (labels ((make-child (name shrink)
                 (cl-weave::make-property-generator
                  :name name
                  :produce #'identity
                  :shrink shrink))
               (assert-child-error (child composite value expected-cause)
                 (let ((observed nil))
                   (handler-bind
                       ((property-shrinker-error
                          (lambda (condition)
                            (setf observed condition)
                            (expect (find-restart 'retry-shrinker condition)
                                    :not :to-be nil)
                            (expect (find-restart 'use-value condition)
                                    :not :to-be nil)
                            (expect (find-restart 'skip-shrinking condition)
                                    :not :to-be nil)
                            (invoke-restart 'skip-shrinking))))
                     (cl-weave::property-shrink-candidates composite value))
                   (expect observed :not :to-be nil)
                   (expect (property-shrinker-error-generator observed)
                           :to-be
                           child)
                   (if expected-cause
                       (expect (property-shrinker-error-cause observed)
                               :to-be
                               expected-cause)
                       (expect (property-shrinker-error-cause observed)
                               :to-satisfy
                               (lambda (condition) (typep condition 'error)))))))
        (let* ((vector-child
                 (make-child :vector-child
                             (lambda (value)
                               (declare (ignore value))
                               #(:invalid))))
               (dotted-child
                 (make-child :dotted-child
                             (lambda (value)
                               (declare (ignore value))
                               (cons :invalid :tail))))
               (circular-child
                 (make-child :circular-child
                             (lambda (value)
                               (declare (ignore value))
                               cycle)))
               (failing-child
                 (make-child :failing-child
                             (lambda (value)
                               (declare (ignore value))
                               (error cause)))))
          (assert-child-error
           vector-child
           (gen-list vector-child :min-length 1 :max-length 4)
           '(:value)
           nil)
          (assert-child-error
           dotted-child
           (gen-vector dotted-child :min-length 1 :max-length 4)
           #(:value)
           nil)
          (assert-child-error
           circular-child
           (gen-tuple circular-child)
           '(:value)
           nil)
          (assert-child-error
           failing-child
           (gen-such-that (constantly t) failing-child)
           :value
           cause)))))


)

(defstruct equalp-shrink-candidate value)
  (defstruct (recursive-equalp-shrink-candidate
               (:include equalp-shrink-candidate))
    next
    alternate)

(describe "cycle-safe shrink candidate deduplication"
  (it "preserves the last equal cons self-cycle"
    (let ((first (cons :cycle nil))
          (middle (cons :cycle nil))
          (last (cons :cycle nil)))
      (setf (cdr first) first
            (cdr middle) middle
            (cdr last) last)
      (flet ((exercise ()
               (let ((candidates
                       (cl-weave::remove-duplicate-shrink-candidates
                        (list first middle last)
                        #'equal)))
                 (expect (length candidates) :to-be 1)
                 (expect (first candidates) :to-be last))))
        #+sbcl
        (sb-ext:with-timeout 2
          (exercise))
        #-sbcl
        (exercise))))

  (it "preserves the last equalp vector self-cycle"
    (let ((first (make-array 1))
          (middle (make-array 1))
          (last (make-array 1)))
      (setf (aref first 0) first
            (aref middle 0) middle
            (aref last 0) last)
      (flet ((exercise ()
               (let ((candidates
                       (cl-weave::remove-duplicate-shrink-candidates
                        (list first middle last)
                        #'equalp)))
                 (expect (length candidates) :to-be 1)
                 (expect (first candidates) :to-be last))))
        #+sbcl
        (sb-ext:with-timeout 2
          (exercise))
        #-sbcl
        (exercise))))

  (it "does not mistake shared DAGs for cycles" (let* ((shared-leaf (list :leaf)) (shared-list (list shared-leaf shared-leaf)) (copied-list (list (list :leaf) (list :leaf))) (vector-leaf (list :leaf)) (shared-vector (vector vector-leaf vector-leaf)) (copied-vector (vector (list :leaf) (list :leaf)))) (expect (cl-weave::candidate-requires-safe-equality-p shared-list (function equal)) :to-be nil) (expect (cl-weave::candidate-requires-safe-equality-p copied-list (function equal)) :to-be nil) (expect (cl-weave::candidate-requires-safe-equality-p shared-vector (function equalp)) :to-be nil) (expect (cl-weave::candidate-requires-safe-equality-p copied-vector (function equalp)) :to-be nil) (let ((list-result (cl-weave::remove-duplicate-shrink-candidates (list shared-list copied-list) (function equal))) (vector-result (cl-weave::remove-duplicate-shrink-candidates (list shared-vector copied-vector) (function equalp)))) (expect (length list-result) :to-be 1) (expect (first list-result) :to-be copied-list) (expect (length vector-result) :to-be 1) (expect (first vector-result) :to-be copied-vector))))

  (it "keeps equalp structure semantics in vector shrinking"
    (let* ((first (make-equalp-shrink-candidate :value 7))
           (last (make-equalp-shrink-candidate :value 7))
           (element-generator
             (cl-weave::make-property-generator
              :name :equalp-structure-candidates
              :produce #'identity
              :shrink (lambda (value)
                        (declare (ignore value))
                        (list first last))))
           (generator
             (gen-vector element-generator :min-length 1 :max-length 1))
           (candidates
             (cl-weave::property-shrink-candidates
              generator
              (vector (make-equalp-shrink-candidate :value 8)))))
      (expect (length candidates) :to-be 1)
      (expect (aref (first candidates) 0) :to-be last)))

  (it "deduplicates 100000 acyclic candidates without quadratic fallback" (flet ((exercise () (let* ((values (loop for index below 100000 collect index)) (composites (loop for index below 100000 collect (list index))) (unique (cl-weave::remove-duplicate-shrink-candidates values (function equal))) (duplicates (cl-weave::remove-duplicate-shrink-candidates (append values values) (function equal))) (composite-unique (cl-weave::remove-duplicate-shrink-candidates composites (function equal))) (composite-duplicates (cl-weave::remove-duplicate-shrink-candidates (append composites composites) (function equal)))) (expect unique :to-equal values) (expect duplicates :to-equal values) (expect (length composite-unique) :to-be 100000) (expect (first composite-unique) :to-be (first composites)) (expect (length composite-duplicates) :to-be 100000) (expect (first composite-duplicates) :to-be (first composites))))) #+sbcl (sb-ext:with-timeout 10 (exercise)) #-sbcl (exercise)))

  (it "preserves composite equality on the acyclic hash fast path" (labels ((make-table (test entries) (let ((table (make-hash-table :test test))) (dolist (entry entries table) (setf (gethash (car entry) table) (cdr entry)))))) (let* ((dotted-first (cons 1 2)) (dotted-last (cons 1 2)) (list-first (list :nested (list 1 2))) (list-last (list :nested (list 1 2))) (vector-first (vector "X" (list 1 2))) (vector-last (vector "x" (list 1 2))) (array-first (make-array (quote (2 5)) :initial-contents (quote ((0 1 2 3 4) (5 6 7 8 9))))) (array-last (make-array (quote (2 5)) :initial-contents (quote ((0 1 2 3 4) (5 6 7 8 9))))) (array-late-different (make-array (quote (2 5)) :initial-contents (quote ((0 1 2 3 4) (5 6 7 8 10))))) (array-shape-different (make-array (quote (5 2)) :initial-contents (quote ((0 1) (2 3) (4 5) (6 7) (8 9))))) (table-first (make-table (quote equal) (quote ((:present . nil) (:value . 2))))) (table-last (make-table (quote equal) (quote ((:value . 2) (:present . nil))))) (table-missing (make-table (quote equal) (quote ((:missing . nil) (:value . 2))))) (table-test-diff (make-table (quote eql) (quote ((:present . nil) (:value . 2)))))) (dolist (case (list (list dotted-first dotted-last (function equal)) (list list-first list-last (function equal)) (list vector-first vector-last (function equalp)) (list array-first array-last (function equalp)) (list table-first table-last (function equalp)))) (let ((result (cl-weave::remove-duplicate-shrink-candidates (list (first case) (second case)) (third case)))) (expect (length result) :to-be 1) (expect (first result) :to-be (second case)))) (dolist (different (list array-late-different array-shape-different table-missing table-test-diff)) (expect (length (cl-weave::remove-duplicate-shrink-candidates (list (if (arrayp different) array-first table-first) different) (function equalp))) :to-be 2)))))

  (it "compares deep-keyed and recursive equalp hash tables safely"
  (labels ((make-deep-key (leaf)
             (loop repeat 100000
                   do (setf leaf (cons leaf nil))
                   finally (return leaf)))
           (make-key-table (test key value)
             (let ((table (make-hash-table :test test)))
               (setf (gethash key table) value)
               table))
           (make-large-scalar-table (reverse-p)
             (let ((table (make-hash-table :test (function equal))))
               (loop repeat 5000
                     for ordinal from 0
                     for key = (if reverse-p
                                   (- 4999 ordinal)
                                   ordinal)
                     do (setf (gethash key table) key))
               table))
           (make-cyclic-eq-key-table ()
             (let ((key (cons :cycle nil))
                   (table (make-hash-table :test (function eq))))
               (setf (cdr key) key
                     (gethash key table) :same)
               table))
           (make-self-value-table ()
             (let ((table (make-hash-table :test (function equal))))
               (setf (gethash :self table) table)
               table))
           (make-self-key-table (test value &optional extra-entry-p)
             (let ((table (make-hash-table :test test)))
               (setf (gethash table table) value)
               (when extra-entry-p
                 (setf (gethash :extra table) t))
               table))
           (make-mutual-table-cycle ()
             (let ((left (make-hash-table :test (function equal)))
                   (right (make-hash-table :test (function equal))))
               (setf (gethash :peer left) right
                     (gethash :peer right) left)
               left))
           (make-owner-key-value-cycle ()
             (let* ((owner (make-hash-table :test (function equalp)))
                    (key (cons :owner owner))
                    (value (make-hash-table :test (function equalp))))
               (setf (gethash :owner value) owner
                     (gethash key owner) value)
               owner)))
    (flet ((exercise ()
             (let* ((self-first (make-self-value-table))
                    (self-last (make-self-value-table))
                    (mutual-first (make-mutual-table-cycle))
                    (mutual-last (make-mutual-table-cycle))
                    (owner-first (make-owner-key-value-cycle))
                    (owner-last (make-owner-key-value-cycle))
                    (large-first (make-large-scalar-table nil))
                    (large-last (make-large-scalar-table t))
                    (cyclic-key-first (make-cyclic-eq-key-table))
                    (cyclic-key-last (make-cyclic-eq-key-table))
                    (deep-first-key (make-deep-key :same))
                    (deep-last-key (make-deep-key :same))
                    (deep-different-key (make-deep-key :different))
                    (deep-first
                      (make-key-table (function equal) deep-first-key :same))
                    (deep-last
                      (make-key-table (function equal) deep-last-key :same))
                    (deep-different
                      (make-key-table
                       (function equal)
                       deep-different-key
                       :same))
                    (equalp-self-key-first
                      (make-self-key-table (function equalp) :same))
                    (equalp-self-key-last
                      (make-self-key-table (function equalp) :same))
                    (self-key-base
                      (make-self-key-table (function eq) :same))
                    (self-key-value-different
                      (make-self-key-table (function eq) :different))
                    (self-key-test-different
                      (make-self-key-table (function eql) :same))
                    (self-key-count-different
                      (make-self-key-table (function eq) :same t)))
               (labels ((expect-last (first last)
                          (let ((result
                                  (cl-weave::remove-duplicate-shrink-candidates
                                   (list first last)
                                   (function equalp))))
                            (expect (length result) :to-be 1)
                            (expect (first result) :to-be last))))
                 (expect
                  (cl-weave::candidate-requires-safe-equality-p
                   deep-first
                   (function equalp))
                  :to-be t)
                 (expect-last self-first self-last)
                 (expect-last mutual-first mutual-last)
                 (expect-last owner-first owner-last)
                 (expect-last large-first large-last)
                 (expect-last deep-first deep-last)
                 (expect-last equalp-self-key-first equalp-self-key-last)
                 (expect
                  (length
                   (cl-weave::remove-duplicate-shrink-candidates
                    (list cyclic-key-first cyclic-key-last)
                    (function equalp)))
                  :to-be 2)
                 (expect
                  (length
                   (cl-weave::remove-duplicate-shrink-candidates
                    (list deep-first deep-different)
                    (function equalp)))
                  :to-be 2)
                 (dolist (different
                           (list self-key-value-different
                                 self-key-test-different
                                 self-key-count-different))
                   (expect
                    (length
                     (cl-weave::remove-duplicate-shrink-candidates
                      (list self-key-base different)
                      (function equalp)))
                    :to-be 2))))))
      #+sbcl
      (sb-ext:with-timeout 20
        (exercise))
      #-sbcl
      (exercise))))

(it "compares equal cons cycles and bisimilar shapes safely"
  (labels ((exercise ()
             (dolist (link (list (function rplaca) (function rplacd)))
               (let ((first (cons :cycle :tail))
                     (middle (cons :cycle :tail))
                     (last (cons :cycle :tail)))
                 (funcall link first first)
                 (funcall link middle middle)
                 (funcall link last last)
                 (let ((result
                         (cl-weave::remove-duplicate-shrink-candidates
                          (list first middle last)
                          (function equal))))
                   (expect (length result) :to-be 1)
                   (expect (first result) :to-be last))))
             (let ((one-cycle (cons :cycle nil))
                   (two-cycle-first (cons :cycle nil))
                   (two-cycle-last (cons :cycle nil)))
               (setf (cdr one-cycle) one-cycle
                     (cdr two-cycle-first) two-cycle-last
                     (cdr two-cycle-last) two-cycle-first)
               (let ((result
                       (cl-weave::remove-duplicate-shrink-candidates
                        (list one-cycle two-cycle-first)
                        (function equal))))
                 (expect (length result) :to-be 1)
                 (expect (first result) :to-be two-cycle-first)))))
    #+sbcl
    (sb-ext:with-timeout 5
      (exercise))
    #-sbcl
    (exercise)))

(it "compares recursive equalp structures safely"
  (labels ((make-self-node (value)
             (let ((node
                     (make-recursive-equalp-shrink-candidate :value value)))
               (setf (recursive-equalp-shrink-candidate-next node) node
                     (recursive-equalp-shrink-candidate-alternate node) node)
               node))
           (make-mutual-node (peer-value)
             (let ((root
                     (make-recursive-equalp-shrink-candidate :value :root))
                   (peer
                     (make-recursive-equalp-shrink-candidate
                      :value peer-value)))
               (setf (recursive-equalp-shrink-candidate-next root) peer
                     (recursive-equalp-shrink-candidate-next peer) root)
               root))
           (make-shared-node ()
             (let ((leaf
                     (make-recursive-equalp-shrink-candidate :value :leaf)))
               (make-recursive-equalp-shrink-candidate
                :value :root
                :next leaf
                :alternate leaf)))
           (expect-result (left right expected-count)
             (let ((result
                     (cl-weave::remove-duplicate-shrink-candidates
                      (list left right)
                      #'equalp)))
               (expect (length result) :to-be expected-count)
               (when (= expected-count 1)
                 (expect (first result) :to-be right)))))
    (flet ((exercise ()
             (let* ((self-first (make-self-node :same))
                    (self-last (make-self-node :same))
                    (self-different (make-self-node :different))
                    (mutual-first (make-mutual-node :peer))
                    (mutual-last (make-mutual-node :peer))
                    (mutual-different (make-mutual-node :different))
                    (shared-first (make-shared-node))
                    (shared-last (make-shared-node))
                    (other-class
                      (make-equalp-shrink-candidate :value :root)))
               (expect
                (cl-weave::candidate-requires-safe-equality-p
                 self-first #'equalp)
                :to-be t)
               (expect
                (cl-weave::candidate-requires-safe-equality-p
                 mutual-first #'equalp)
                :to-be t)
               #+sbcl
               (expect
                (cl-weave::candidate-requires-safe-equality-p
                 shared-first #'equalp)
                :to-be nil)
               #-sbcl
               (expect
                (cl-weave::candidate-requires-safe-equality-p
                 shared-first #'equalp)
                :to-be t)
               #+sbcl
               (progn
                 (expect-result self-first self-last 1)
                 (expect-result mutual-first mutual-last 1)
                 (expect-result shared-first shared-last 1))
               #-sbcl
               (progn
                 (expect-result self-first self-last 2)
                 (expect-result mutual-first mutual-last 2)
                 (expect-result shared-first shared-last 2)
                 (expect-result self-first self-first 1))
               (expect-result self-first self-different 2)
               (expect-result mutual-first mutual-different 2)
               (expect-result shared-first other-class 2))))
      #+sbcl
      (sb-ext:with-timeout 5
        (exercise))
      #-sbcl
      (exercise))))

 (it "honors vector fill-pointer equalp semantics safely"
  (labels ((make-fill-vector (capacity fill-pointer tail)
             (let ((value
                     (make-array capacity
                                 :fill-pointer fill-pointer
                                 :initial-element tail)))
               (setf (aref value 0) 1
                     (aref value 1) 2)
               value))
           (expect-equal-candidates (first last)
             (let ((result
                     (cl-weave::remove-duplicate-shrink-candidates
                      (list first last)
                      (function equalp))))
               (expect (length result) :to-be 1)
               (expect (first result) :to-be last))))
    (flet ((exercise ()
             (let* ((tail-first (make-fill-vector 4 2 :first-tail))
                    (tail-last (make-fill-vector 4 2 :last-tail))
                    (capacity-last (make-fill-vector 6 2 :last-tail))
                    (capacity-ten (make-fill-vector 10 5 :same-tail))
                    (capacity-five (make-fill-vector 5 5 :same-tail))
                    (plain-last (vector 1 2))
                    (length-last (make-fill-vector 4 3 3))
                    (inactive-self-first (make-fill-vector 4 2 nil))
                    (inactive-self-last (make-fill-vector 4 2 nil)))
               (setf (aref inactive-self-first 2) inactive-self-first
                     (aref inactive-self-last 2) inactive-self-last)
               (expect
                (cl-weave::candidate-requires-safe-equality-p
                 inactive-self-first
                 (function equalp))
                :to-be nil)
               (expect (equalp tail-first capacity-last) :to-be t)
               (expect (equalp capacity-ten capacity-five) :to-be t)
               (expect-equal-candidates tail-first tail-last)
               (expect-equal-candidates tail-first capacity-last)
               (expect-equal-candidates capacity-ten capacity-five)
               (expect-equal-candidates tail-first plain-last)
               (expect-equal-candidates
                inactive-self-first
                inactive-self-last)
               (expect
                (length
                 (cl-weave::remove-duplicate-shrink-candidates
                  (list tail-first length-last)
                  (function equalp)))
                :to-be 2))))
      #+sbcl
      (sb-ext:with-timeout 5
        (exercise))
      #-sbcl
      (exercise))))
(progn
(it "deduplicates deeply nested acyclic conses without stack recursion"
  (flet ((exercise ()
           (labels ((make-deep-candidate (leaf)
                      (loop repeat 100000
                            do (setf leaf (cons leaf nil))
                            finally (return leaf))))
             (let* ((first (make-deep-candidate :same))
                    (last (make-deep-candidate :same))
                    (different (make-deep-candidate :different))
                    (equal-result
                      (cl-weave::remove-duplicate-shrink-candidates
                       (list first last)
                       (function equal)))
                    (equalp-result
                      (cl-weave::remove-duplicate-shrink-candidates
                       (list first last)
                       (function equalp)))
                    (different-result
                      (cl-weave::remove-duplicate-shrink-candidates
                       (list first different)
                       (function equalp))))
               (expect
                (cl-weave::candidate-requires-safe-equality-p
                 first
                 (function equal))
                :to-be t)
               (expect
                (cl-weave::candidate-requires-safe-equality-p
                 first
                 (function equalp))
                :to-be t)
               (expect (length equal-result) :to-be 1)
               (expect (first equal-result) :to-be last)
               (expect (length equalp-result) :to-be 1)
               (expect (first equalp-result) :to-be last)
               (expect (length different-result) :to-be 2)
               (expect (first different-result) :to-be first)
               (expect (second different-result) :to-be different)))))
    #+sbcl
    (sb-ext:with-timeout 20
      (exercise))
    #-sbcl
    (exercise)))
(it "classifies mixed cycles and EQUALP hash tables exactly"
  (labels ((make-mixed-cycle ()
             (let ((root (cons :root nil))
                   (items (make-array 1)))
               (setf (cdr root) items
                     (aref items 0) root)
               root))
           (make-table (test entries)
             (let ((table (make-hash-table :test test)))
               (dolist (entry entries table)
                 (setf (gethash (car entry) table)
                       (cdr entry))))))
    (flet ((exercise ()
             (let* ((mixed-first (make-mixed-cycle))
                    (mixed-last (make-mixed-cycle))
                    (equalp-first
                      (make-table
                       (function equalp)
                       (list (cons #\A "VALUE")
                             (cons 1 "NUMBER"))))
                    (equalp-last
                      (make-table
                       (function equalp)
                       (list (cons 1.0 "number")
                             (cons #\a "value"))))
                    (different-test
                      (make-table
                       (function equal)
                       (list (cons #\a "value")
                             (cons 1 "number"))))
                    (candidates
                      (list mixed-first
                            mixed-last
                            equalp-first
                            equalp-last
                            different-test))
                    (classes
                      (cl-weave::candidate-equality-class-ids
                       candidates
                       (function equalp)))
                    (result
                      (cl-weave::remove-duplicate-shrink-candidates
                       candidates
                       (function equalp))))
               (expect (first classes) :to-be (second classes))
               (expect (third classes) :to-be (fourth classes))
               (expect (= (fourth classes) (fifth classes)) :to-be nil)
               (expect (length result) :to-be 3)
               (expect (first result) :to-be mixed-last)
               (expect (second result) :to-be equalp-last)
               (expect (third result) :to-be different-test))))
      #+sbcl
      (sb-ext:with-timeout 5
        (exercise))
      #-sbcl
      (exercise))))
))
