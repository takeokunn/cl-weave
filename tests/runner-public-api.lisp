(in-package #:cl-weave/tests)

(defmacro with-registered-demo-suites ((&rest names) &body body)
  "Run BODY against a fresh root suite containing one passing test per name."
  `(let ((cl-weave::*root-suite* (cl-weave::make-suite :name "root"))
         (cl-weave::*current-suite* nil)
         (cl-weave::*named-suites* (make-hash-table :test #'equal)))
     ,@(loop for name in names
             collect `(describe ,name
                        (it "passes"
                          (expect 1 :to-be 1))))
     ,@body))

(describe "runner public API"
  (it "exports the registered root suite"
    (with-registered-demo-suites ("root suite api")
      (multiple-value-bind (symbol status)
          (find-symbol "ROOT-SUITE" "CL-WEAVE")
        (expect status :to-be :external)
        (expect symbol :to-be 'cl-weave:root-suite))
      (expect (cl-weave:root-suite) :to-be cl-weave::*root-suite*)))

  (it "runs a suite selected by its name designator"
    (with-registered-demo-suites ("selected api suite" "other api suite")
      (let ((events (cl-weave:run "selected api suite"
                                  :reporter :sexp
                                  :stream (make-broadcast-stream))))
        (expect (length events) :to-be 1)
        (expect (cl-weave::test-event-status (first events)) :to-be :pass)
        (expect (cl-weave::test-event-path (first events))
                :to-equal '("selected api suite" "passes")))))

  (it "caches named suite designators between runs"
    (with-registered-demo-suites ("cached api suite")
      (cl-weave:run "cached api suite" :stream (make-broadcast-stream))
      (let ((cached (gethash (cl-weave::named-suite-key "cached api suite")
                             cl-weave::*named-suites*)))
        (expect cached :to-satisfy #'cl-weave::suite-p)
        (expect (cl-weave:run "cached api suite"
                              :stream (make-broadcast-stream))
                :to-satisfy #'consp))))

  (it "runs a suite object and the root suite designator directly"
    (with-registered-demo-suites ("object api suite")
      (let ((suite (cl-weave::find-suite-by-designator "object api suite")))
        (expect suite :to-satisfy #'cl-weave::suite-p)
        (expect (length (cl-weave:run suite :stream (make-broadcast-stream)))
                :to-be 1)
        (expect (length (cl-weave:run nil :stream (make-broadcast-stream)))
                :to-be 1))))

  (it "emits every run reporter format from RUN"
    (with-registered-demo-suites ("reporting api suite")
      (dolist (reporter '(:spec :sexp :json :jsonl :tap :github :junit))
        (let ((output (with-output-to-string (stream)
                        (cl-weave:run "reporting api suite"
                                      :reporter reporter
                                      :stream stream))))
          (expect (plusp (length output)) :to-be-truthy)))))

  (it "rejects unknown suite designators"
    (with-registered-demo-suites ("known api suite")
      (expect (lambda ()
                (cl-weave:run "missing api suite"
                              :stream (make-broadcast-stream)))
              :to-throw "unknown suite designator")))

  (it "finds nested suites by designator"
    (let ((cl-weave::*root-suite* (cl-weave::make-suite :name "root"))
          (cl-weave::*current-suite* nil)
          (cl-weave::*named-suites* (make-hash-table :test #'equal)))
      (describe "outer api suite"
        (describe "inner api suite"
          (it "passes" (expect 1 :to-be 1))))
      (let ((inner (cl-weave::find-suite-by-designator "inner api suite")))
        (expect inner :to-satisfy #'cl-weave::suite-p)
        (expect (cl-weave::suite-name inner) :to-equal "inner api suite"))
      (expect (cl-weave::find-suite-by-designator "absent api suite")
              :to-be nil)))

  (it "normalizes nested run results and rejects foreign values"
    (with-registered-demo-suites ("normalized api suite")
      (let ((events (cl-weave:run "normalized api suite"
                                  :stream (make-broadcast-stream))))
        (expect (cl-weave::normalize-run-results (list nil events (first events)))
                :to-satisfy
                (lambda (normalized)
                  (every #'cl-weave::test-event-p normalized)))
        (expect (lambda ()
                  (cl-weave::normalize-run-results (list :not-an-event)))
                :to-throw "expected test events")
        (expect (with-output-to-string (stream)
                  (cl-weave:explain! events stream))
                :to-contain "passes"))))

  (it "lists plans through every list reporter"
    (with-registered-demo-suites ("planned api suite")
      (dolist (reporter '(:spec :sexp :json :jsonl))
        (let ((output (with-output-to-string (stream)
                        (cl-weave:list-tests :reporter reporter
                                             :stream stream))))
          (expect (plusp (length output)) :to-be-truthy)))
      (expect (length (cl-weave:list-tests :stream (make-broadcast-stream)))
              :to-be 1)))

  (it "rejects run-only reporters in list mode"
    (with-registered-demo-suites ("rejecting api suite")
      (expect (lambda ()
                (cl-weave:list-tests :reporter :tap
                                     :stream (make-broadcast-stream)))
              :to-throw "list mode supports"))))
