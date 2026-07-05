(in-package #:cl-weave/tests)

(describe "sharding"
  (it "runs a deterministic one-based shard after filtering"
    (let* ((root (cl-weave::make-suite :name "root"))
           (suite (cl-weave::add-child
                   root
                   (cl-weave::make-suite :name "sharded" :parent root)))
           (events-log nil))
      (dolist (name '("alpha" "beta" "gamma" "delta"))
        (cl-weave::add-child
         suite
         (cl-weave::make-test-case
          :name name
          :function (lambda () (push name events-log)))))
      (let ((events (cl-weave::collect-events
                     root
                     :name-filter "sharded"
                     :shard '(2 2))))
        (expect (reverse events-log) :to-equal '("beta" "delta"))
        (expect (mapcar #'cl-weave::test-event-path events)
                :to-equal '(("sharded" "beta") ("sharded" "delta"))))))

  (it "does not run hooks for suites outside the current shard"
    (let* ((root (cl-weave::make-suite :name "root"))
           (hook-events nil)
           (hidden (cl-weave::add-child
                    root
                    (cl-weave::make-suite
                     :name "hidden"
                     :parent root
                     :before-all (list (lambda () (push :hidden-before hook-events)))
                     :after-all (list (lambda () (push :hidden-after hook-events))))))
           (visible (cl-weave::add-child
                     root
                     (cl-weave::make-suite :name "visible" :parent root))))
      (cl-weave::add-child
       hidden
       (cl-weave::make-test-case
        :name "first"
        :function (lambda () (push :hidden hook-events))))
      (cl-weave::add-child
       visible
       (cl-weave::make-test-case
        :name "second"
        :function (lambda () (push :visible hook-events))))
      (let ((events (cl-weave::collect-events root :shard '(2 2))))
        (expect hook-events :to-equal '(:visible))
        (expect (mapcar #'cl-weave::test-event-path events)
                :to-equal '(("visible" "second"))))))

  (it "lists only tests in the requested shard"
    (let* ((root (cl-weave::make-suite :name "root"))
           (suite (cl-weave::add-child
                   root
                   (cl-weave::make-suite :name "plan-shard" :parent root))))
      (dolist (name '("one" "two" "three"))
        (cl-weave::add-child
         suite
         (cl-weave::make-test-case
          :name name
          :function (lambda () (error "should not run")))))
      (let ((plan (cl-weave:collect-test-plan root :shard '(1 2))))
        (expect (mapcar #'cl-weave:test-plan-entry-path plan)
                :to-equal '(("plan-shard" "one") ("plan-shard" "three"))))))

  (it "rejects invalid shard specs with stable errors"
    (let ((root (cl-weave::make-suite :name "root")))
      (dolist (shard '((0 2) (3 2) (1) (1 2 3) "1/2"))
        (expect (lambda ()
                  (cl-weave::collect-events root :shard shard))
                :to-throw
                "Shard must be NIL")))))

