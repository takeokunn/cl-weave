(in-package #:cl-weave/tests)

(describe "filtering"
  (it "runs only tests matching a path substring"
    (let* ((root (cl-weave::make-suite :name "root"))
           (suite (cl-weave::add-child
                   root
                   (cl-weave::make-suite :name "math" :parent root)))
           (events-log nil))
      (cl-weave::add-child
       suite
       (cl-weave::make-test-case
        :name "adds numbers"
        :function (lambda () (push :add events-log))))
      (cl-weave::add-child
       suite
       (cl-weave::make-test-case
        :name "subtracts numbers"
        :function (lambda () (push :subtract events-log))))
      (let ((events (cl-weave::collect-events root :name-filter "MATH > ADDS")))
        (expect events-log :to-equal '(:add))
        (expect (mapcar #'cl-weave::test-event-path events)
                :to-equal '(("math" "adds numbers"))))))

  (it "does not run suite hooks when no child matches the filter"
    (let* ((root (cl-weave::make-suite :name "root"))
           (hook-events nil)
           (suite (cl-weave::add-child
                   root
                   (cl-weave::make-suite
                    :name "filtered"
                    :parent root
                    :before-all (list (lambda () (push :before-all hook-events)))
                    :after-all (list (lambda () (push :after-all hook-events)))))))
      (cl-weave::add-child
       suite
       (cl-weave::make-test-case
        :name "hidden"
        :function (lambda () (push :test hook-events))))
      (expect (cl-weave::collect-events root :name-filter "missing")
              :to-equal nil)
      (expect hook-events :to-equal nil)))

  (it "runs only tests whose source file matches the location filter"
    (let* ((root (cl-weave::make-suite :name "root"))
           (suite (cl-weave::add-child
                   root
                   (cl-weave::make-suite :name "files" :parent root)))
           (target #P"/tmp/cl-weave/location-target.lisp")
           (other #P"/tmp/cl-weave/location-other.lisp")
           (events-log nil))
      (cl-weave::add-child
       suite
       (cl-weave::make-test-case
        :name "target"
        :location (list :file (namestring target))
        :function (lambda () (push :target events-log))))
      (cl-weave::add-child
       suite
       (cl-weave::make-test-case
        :name "other"
        :location (list :file (namestring other))
        :function (lambda () (push :other events-log))))
      (let ((events (cl-weave::collect-events root :location-filter (list target))))
        (expect events-log :to-equal '(:target))
        (expect (mapcar #'cl-weave::test-event-path events)
                :to-equal '(("files" "target"))))))

  (it "normalizes, includes, and excludes test tags"
    (let* ((root (cl-weave::make-suite :name "root"))
           (suite (cl-weave::add-child
                   root (cl-weave::make-suite :name "tagged" :parent root))))
      (dolist (spec '(("fast unit" (:fast "UNIT" :FAST))
                      ("fast db" (:fast :db))
                      ("slow unit" (:slow :unit))))
        (cl-weave::add-child
         suite
         (cl-weave::make-test-case
          :name (first spec)
          :tags (cl-weave::normalize-tags (second spec))
          :function (lambda () t))))
      (let ((events (cl-weave::collect-events
                     root :include-tags '(fast) :exclude-tags '("db"))))
        (expect (mapcar #'cl-weave::test-event-path events)
                :to-equal '(("tagged" "fast unit"))))))

  (it "combines tag, name, and location filters with AND semantics"
    (let* ((root (cl-weave::make-suite :name "root"))
           (suite (cl-weave::add-child
                   root (cl-weave::make-suite :name "combined" :parent root)))
           (target #P"/tmp/cl-weave/combined-target.lisp"))
      (dolist (name '("wanted" "other"))
        (cl-weave::add-child
         suite
         (cl-weave::make-test-case
          :name name :tags '("FAST")
          :location (list :file (namestring target))
          :function (lambda () t))))
      (let ((events (cl-weave::collect-events
                     root :include-tags '(:fast) :name-filter "wanted"
                     :location-filter (list target))))
        (expect (mapcar #'cl-weave::test-event-path events)
                :to-equal '(("combined" "wanted"))))))

  (it "validates tag filters as proper lists of tag designators"
    (dolist (filter (list :fast '(42) (cons :fast :slow)))
      (expect (lambda ()
                (cl-weave::collect-events
                 (cl-weave::make-suite :name "root") :include-tags filter))
              :to-throw)))

  (it "applies tag filters before assigning shard ordinals"
    (let* ((root (cl-weave::make-suite :name "root"))
           (suite (cl-weave::add-child
                   root (cl-weave::make-suite :name "sharded" :parent root))))
      (dolist (spec '(("first" ("FAST"))
                      ("ignored" ("SLOW"))
                      ("second" ("FAST"))))
        (cl-weave::add-child
         suite
         (cl-weave::make-test-case
          :name (first spec) :tags (second spec) :function (lambda () t))))
      (let ((events (cl-weave::collect-events
                     root :include-tags '(:fast) :shard '(2 2))))
        (expect (mapcar #'cl-weave::test-event-path events)
                :to-equal '(("sharded" "second"))))))

  (it "can fail a run when no tests are selected"
    (let ((cl-weave::*root-suite* (cl-weave::make-suite :name "root"))
          (cl-weave::*current-suite* nil))
      (describe "selected"
        (it "visible"
          (expect t :to-be-truthy)))
      (expect (cl-weave:run-all
               :reporter :sexp
               :stream (make-string-output-stream)
               :name-filter "missing")
              :to-be t)
      (expect (cl-weave:run-all
               :reporter :sexp
               :stream (make-string-output-stream)
               :name-filter "missing"
               :pass-with-no-tests nil)
              :to-be nil))))
