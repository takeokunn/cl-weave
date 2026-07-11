(in-package #:cl-weave/tests)

(describe "property shrinking"
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

  (it "never classifies non-conditions as matching property failures"
    (dolist (pair '((:failure :failure)
                    (:failure nil)
                    (nil :failure)))
      (expect (same-property-failure-p (first pair) (second pair))
              :to-be nil)))

  (it "dispatches every shrink candidate to exactly one continuation"
    (labels ((dispatch (current visited candidate property)
               (let* ((original (make-condition 'simple-error
                                                :format-control "original"
                                                :format-arguments nil))
                      (state (cl-weave::make-property-shrink-state
                              :original original
                              :function property
                              :current current
                              :visited (cons current visited)
                              :steps 1
                              :max-steps 10))
                      (calls nil))
                 (cl-weave::call-property-shrink-candidate/k
                  state 0 candidate
                  (lambda (next-state)
                    (push (list :accept
                                (cl-weave::property-shrink-state-current
                                 next-state))
                          calls))
                  (lambda (rejected-state)
                    (expect rejected-state :to-be state)
                    (push (list :reject) calls)))
                 calls)))
      (dolist (case
               (list
                (list '((:accept (1))) '(2) nil 1
                      (lambda (value) (error "failure: ~S" value)))
                (list '((:reject)) '(2) nil 2
                      (lambda (value) (error "failure: ~S" value)))
                (list '((:reject)) '(2) '((1)) 1
                      (lambda (value) (error "failure: ~S" value)))
                (list '((:reject)) '(2) nil 1 #'identity)
                (list '((:reject)) '(2) nil 1
                      (lambda (value)
                        (declare (ignore value))
                        (error 'type-error :datum 1 :expected-type 'string)))))
        (destructuring-bind (expected current visited candidate property) case
          (expect (dispatch current visited candidate property)
                  :to-equal expected)))))

  (it "stops at the first accepted shrink candidate"
    (let ((generator
            (cl-weave::make-property-generator
             :name :ordered
             :produce #'identity
             :shrink (lambda (value)
                       (if (= value 2) '(1 0) nil)))))
      (expect (cl-weave::shrink-property-values
               (list generator)
               '(2)
               (lambda (value)
                 (error "failure: ~S" value)))
              :to-equal '(1))))

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

)
