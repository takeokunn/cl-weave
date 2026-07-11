(in-package #:cl-weave/tests)

(describe "properties"
  (it "validates integer generator bounds"
    (expect (lambda () (gen-integer :min 0.5)) :to-throw 'type-error)
    (expect (lambda () (gen-integer :max "10")) :to-throw 'type-error)
    (expect (lambda () (gen-integer :min 2 :max 1))
            :to-throw "MIN <= MAX"))

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

  (it "shrinks heterogeneous generator alternatives safely"
    (let ((generator (gen-one-of (gen-member '(:a :b))
                                 (gen-list (gen-member '(:x :y))
                                           :min-length 1
                                           :max-length 2))))
      (expect (funcall (cl-weave::property-generator-shrink generator) :b)
              :to-equal '(:a))
      (expect (funcall (cl-weave::property-generator-shrink generator) '(:x :y))
              :to-satisfy
              (lambda (candidates)
                (member '(:x) candidates :test #'equal)))))

  (it "shrinks strings and vectors safely"
    (let ((string-generator (gen-string :min-length 1 :max-length 4 :alphabet "ab"))
          (vector-generator (gen-vector (gen-member '(:a :b))
                                        :min-length 1
                                        :max-length 3)))
      (expect (funcall (cl-weave::property-generator-shrink string-generator)
                       "bb")
              :to-contain "ab")
      (expect (funcall (cl-weave::property-generator-shrink vector-generator)
                       #(:b :b))
              :to-contain-equal #(:a :b))))

  (it "shrinks state-machine traces by event stream"
    (let* ((transition (lambda (state event)
                         (ecase event
                           (:inc (1+ state))
                           (:dec (1- state)))))
           (generator (gen-state-machine
                       0 transition (gen-member '(:inc :dec))
                       :min-length 1
                       :max-length 3))
           (trace '(:initial 0 :events (:inc :inc) :states (0 1 2) :final 2))
           (candidates (funcall (cl-weave::property-generator-shrink generator)
                                trace))
           (single-event (find-if
                          (lambda (candidate)
                            (equal (getf candidate :events) '(:inc)))
                          candidates)))
      (expect single-event :to-satisfy #'identity)
      (expect (getf single-event :states) :to-equal '(0 1))
      (expect (getf single-event :final) :to-be 1)))

  (it "rejects invalid state-machine transitions"
    (expect (lambda ()
              (gen-state-machine 0 :not-a-function (gen-member '(:inc))))
            :to-throw "TRANSITION"))

  (it "reports generated and minimized values on failure"
    (handler-case
        (let ((cl-weave:*property-test-count* 20)
              (cl-weave:*property-seed* 1))
          (cl-weave::run-property
           (list (gen-integer :min 1 :max 5))
           (lambda (value)
             (expect value :to-be 0))
           '(value)
           '(property-failure-example)))
      (assertion-failure (condition)
        (let* ((detail (cl-weave::failure-detail condition))
               (actual (cl-weave::assertion-detail-actual detail)))
          (expect (cl-weave::assertion-detail-matcher detail) :to-be :property)
          (expect actual :to-contain :seed)
          (expect actual :to-contain :case-index)
          (expect (getf actual :seed) :to-be 1)
          (expect (getf actual :case-index) :to-be 0)
          (expect actual :to-contain :values)
          (expect actual :to-contain :minimal)))))

  (it "does not treat warnings as property failures"
    (let ((cl-weave:*property-test-count* 3)
          (cl-weave:*property-seed* 17)
          (runs 0))
      (handler-bind ((warning (lambda (condition)
                                (declare (ignore condition))
                                (invoke-restart 'muffle-warning))))
        (expect (cl-weave::run-property
                 (list (gen-integer :min 5 :max 5))
                 (lambda (value)
                   (incf runs)
                   (warn "generated ~S" value))
                 '(value)
                 '(warning-property))
                :to-be t))
      (expect runs :to-be 3)))

  (it "matches property failures by condition type by default"
    (expect (same-property-failure-p
             (make-condition 'simple-error
                             :format-control "first"
                             :format-arguments nil)
             (make-condition 'simple-error
                             :format-control "second"
                             :format-arguments nil))
            :to-be t)
    (expect (same-property-failure-p
             (make-condition 'simple-error
                             :format-control "failure"
                             :format-arguments nil)
             (make-condition 'type-error :datum 1 :expected-type 'string))
            :to-be nil))

  (it "does not shrink a property failure into a different error type"
    (let ((cl-weave:*property-test-count* 1)
          (cl-weave:*property-seed* 23)
          (generator
            (cl-weave::make-property-generator
             :name :heterogeneous-failure
             :produce (lambda (rng)
                        (declare (ignore rng))
                        2)
             :shrink (lambda (value)
                       (if (= value 2) '(1 0) '())))))
      (handler-case
          (cl-weave::run-property
           (list generator)
           (lambda (value)
             (case value
               (1 (error "different failure"))
               (otherwise (expect value :to-be -1))))
           '(value)
           '(heterogeneous-property-failure))
        (assertion-failure (condition)
          (let* ((detail (cl-weave::failure-detail condition))
                 (actual (cl-weave::assertion-detail-actual detail)))
            (expect (getf actual :minimal) :to-equal '(0)))))))

  (it "stops shrinking when candidates form a cycle"
    (let ((generator
            (cl-weave::make-property-generator
             :name :cyclic
             :produce (lambda (rng)
                        (declare (ignore rng))
                        :a)
             :shrink (lambda (value)
                       (ecase value
                         (:a '(:b))
                         (:b '(:a)))))))
      (expect (cl-weave::shrink-property-values
               (list generator) '(:a)
               (lambda (value) (error "failure at ~S" value)))
              :to-equal '(:b))))

  (it "offers the current value when the shrink step limit is reached"
    (let ((cl-weave:*property-shrink-max-steps* 1)
          (generator
            (cl-weave::make-property-generator
             :name :unbounded
             :produce (lambda (rng) (declare (ignore rng)) 3)
             :shrink (lambda (value) (list (1- value)))))
          (limit nil))
      (handler-bind
          ((property-shrink-limit
             (lambda (condition)
               (setf limit condition)
               (invoke-restart 'accept-current))))
        (expect (cl-weave::shrink-property-values
                 (list generator) '(3)
                 (lambda (value) (error "failure at ~S" value)))
                :to-equal '(2)))
      (expect (property-shrink-limit-values limit) :to-equal '(2))
      (expect (property-shrink-limit-steps limit) :to-be 1)
      (expect (property-shrink-limit-max-steps limit) :to-be 1)))

  (it "spends the shrink budget on rejected candidates"
    (let ((cl-weave:*property-shrink-max-steps* 2)
          (evaluated nil)
          (limit nil)
          (generator
            (cl-weave::make-property-generator
             :name :rejected
             :produce (lambda (rng) (declare (ignore rng)) 3)
             :shrink (lambda (value)
                       (declare (ignore value))
                       '(2 1 0)))))
      (handler-bind
          ((property-shrink-limit
             (lambda (condition)
               (setf limit condition)
               (invoke-restart 'accept-current))))
        (expect (cl-weave::shrink-property-values
                 (list generator) '(3)
                 (lambda (value)
                   (push value evaluated)
                   (when (= value 3)
                     (error "original failure"))))
                :to-equal '(3)))
      (expect evaluated :to-equal '(1 2 3))
      (expect (property-shrink-limit-steps limit) :to-be 2)))

  (it "rejects invalid shrink step limits"
    (let ((cl-weave:*property-shrink-max-steps* -1))
      (expect (lambda ()
                (cl-weave::shrink-property-values nil '(1) #'identity))
              :to-throw
              'type-error)))

  (it "uses property count from the CI environment"
    (let ((runs 0))
      (with-mocked-functions
          (((symbol-function 'uiop:getenv)
            (lambda (name)
              (cond
                ((string= name "CL_WEAVE_PROPERTY_TESTS") "3")
                ((string= name "CL_WEAVE_PROPERTY_SEED") "5")
                (t nil)))))
        (cl-weave::run-property
         (list (gen-integer :min 1 :max 1))
         (lambda (value)
           (expect value :to-be 1)
           (incf runs)
           t)
         '(value)
         '(property-env-count)))
      (expect runs :to-be 3)))

  (it "rejects invalid property count environment values"
    (with-mocked-functions
        (((symbol-function 'uiop:getenv)
          (lambda (name)
            (when (string= name "CL_WEAVE_PROPERTY_TESTS")
              "not-a-number"))))
      (expect (lambda ()
                (cl-weave::run-property
                 (list (gen-integer :min 1 :max 1))
                 (lambda (value)
                   (declare (ignore value))
                   t)
                 '(value)
                 '(property-invalid-count)))
              :to-throw
              "CL_WEAVE_PROPERTY_TESTS")))

  (it "rejects non-positive property counts"
    (let ((cl-weave:*property-test-count* 0))
      (expect (lambda ()
                (cl-weave::run-property
                 (list (gen-integer :min 1 :max 1))
                 (lambda (value)
                   (declare (ignore value))
                   t)
                 '(value)
                 '(property-zero-count)))
              :to-throw
              "positive integer")))

  (it "rejects invalid property seed environment values"
    (with-mocked-functions
        (((symbol-function 'uiop:getenv)
          (lambda (name)
            (when (string= name "CL_WEAVE_PROPERTY_SEED")
              "not-a-seed"))))
      (expect (lambda ()
                (cl-weave::run-property
                 (list (gen-integer :min 1 :max 1))
                 (lambda (value)
                   (declare (ignore value))
                   t)
                 '(value)
                 '(property-invalid-seed)))
              :to-throw
              "CL_WEAVE_PROPERTY_SEED")))

  (it "expands it-property into the property runner"
    (expect (macroexpand-1
             '(it-property "positive identity"
                  ((value (gen-integer :min 1 :max 3)))
                (expect value :to-be value)))
            :to-satisfy
            (lambda (form)
              (tree-contains-p form 'cl-weave::run-property)))))

(defmutation-operator :keyword-toggle (form path)
  "Toggles :enabled keyword literals to :disabled."
  (declare (ignore path))
  (when (eq form :enabled)
    (list :disabled)))
