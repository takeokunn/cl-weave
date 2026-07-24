(in-package #:cl-weave/tests)

(describe "sequence"
  (it "runs and lists tests in deterministic seeded order"
    (let* ((root (cl-weave::make-suite :name "root"))
           (suite (cl-weave::add-child
                   root
                   (cl-weave::make-suite :name "sequence" :parent root))))
      (dolist (name '("alpha" "beta" "gamma" "delta"))
        (cl-weave::add-child
         suite
         (cl-weave::make-test-case
          :name name
          :function (lambda () t))))
      (let ((events (cl-weave::collect-events root :order :random :seed 7))
            (plan (cl-weave:collect-test-plan root :order :random :seed 7)))
        (expect (mapcar #'cl-weave::test-event-path events)
                :to-equal '(("sequence" "gamma")
                            ("sequence" "beta")
                            ("sequence" "delta")
                            ("sequence" "alpha")))
        (expect (mapcar #'cl-weave:test-plan-entry-path plan)
                :to-equal (mapcar #'cl-weave::test-event-path events)))))

  (it "preserves child order when randomized hashes collide"
    (let* ((suite (cl-weave::make-suite :name "sequence-collision"))
           (first (cl-weave::make-test-case :name "duplicate"
                                            :function (lambda () t)))
           (second (cl-weave::make-test-case :name "duplicate"
                                             :function (lambda () t)))
           (children (list first second)))
      (let ((cl-weave:*test-sequence-order* :random)
            (cl-weave:*test-sequence-seed* 17))
        (expect (every #'eq
                       (cl-weave::ordered-children suite children)
                       children)
                :to-be t))))

  (it "applies sharding before seeded ordering"
    (let* ((root (cl-weave::make-suite :name "root"))
           (suite (cl-weave::add-child
                   root
                   (cl-weave::make-suite :name "sequence-shard" :parent root))))
      (dolist (name '("one" "two" "three" "four"))
        (cl-weave::add-child
         suite
         (cl-weave::make-test-case
          :name name
          :function (lambda () t))))
      (let* ((events (cl-weave::collect-events
                      root
                      :shard '(1 2)
                      :order :random
                      :seed 11))
             (names (mapcar (lambda (path) (second path))
                            (mapcar #'cl-weave::test-event-path events))))
        (expect (sort (copy-list names) #'string<)
                :to-equal '("one" "three")))))

  (it "rejects invalid sequence controls with stable errors"
    (let ((root (cl-weave::make-suite :name "root")))
      (expect (lambda ()
                (cl-weave::collect-events root :order :reverse))
              :to-throw
              "Sequence order must")
      (expect (lambda ()
                (cl-weave:collect-test-plan root :seed "123"))
              :to-throw
              "Sequence seed must"))))

(describe "sequence public controls"
  (it "provides deterministic defaults"
    (expect cl-weave:*test-sequence-order* :to-be :defined)
    (expect cl-weave:*test-sequence-seed* :to-be 0))

  (it "supports dynamic sequence control bindings"
    (let ((cl-weave:*test-sequence-order* :random)
          (cl-weave:*test-sequence-seed* 29))
      (expect cl-weave:*test-sequence-order* :to-be :random)
      (expect cl-weave:*test-sequence-seed* :to-be 29))))
