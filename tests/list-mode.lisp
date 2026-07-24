
(in-package #:cl-weave/tests)

(progn
  (it "accepts empty and maximum plan filters with arbitrary integer seeds"
    (let ((root (cl-weave::make-suite :name "root"))
          (limit cl-weave::+maximum-selection-filter-count+))
      (expect (cl-weave:collect-test-plan
               root
               :location-filter nil
               :test-path-filter nil
               :seed -1)
              :to-be-null)
      (expect (cl-weave:collect-test-plan root :seed (expt 2 256))
              :to-be-null)
      (expect (cl-weave:collect-test-plan
               root
               :location-filter
               (make-list limit
                          :initial-element #P"/tmp/cl-weave/maximum.lisp"))
              :to-be-null)
      (expect (cl-weave:collect-test-plan
               root
               :test-path-filter
               (list (make-list limit :initial-element "part")))
              :to-be-null)
      (expect (cl-weave:collect-test-plan
               root
               :test-path-filter
               (make-list limit :initial-element nil))
              :to-be-null)))

  (it "preflights RUN filters before suite lookup cache and execution"
    (let* ((root (cl-weave::make-suite :name "root"))
           (suite
             (cl-weave::add-child
              root
              (cl-weave::make-suite :name "target" :parent root)))
           (limit cl-weave::+maximum-selection-filter-count+)
           (circular (list #P"/tmp/cl-weave/circular.lisp"))
           (dotted (cons :fast :tail))
           (oversized
             (make-list (1+ limit)
                        :initial-element #P"/tmp/cl-weave/oversized.lisp"))
           (snapshot-count 0)
           (execution-count 0)
           (reporter-count 0))
      (setf (cdr circular) circular)
      (cl-weave::add-child
       suite
       (cl-weave::make-test-case
        :name "must not run"
        :function (lambda () (incf execution-count))))
      (let ((cl-weave::*root-suite* root)
            (cl-weave::*named-suites* (make-hash-table :test #'equal))
            (cl-weave::*test-registry-generation* 0))
        (with-mocked-functions
            (((symbol-function 'cl-weave::snapshot-suite)
              (lambda (selected-suite)
                (incf snapshot-count)
                selected-suite))
             ((symbol-function 'cl-weave::emit-run-report)
              (lambda (&rest arguments)
                (declare (ignore arguments))
                (incf reporter-count))))
          (labels ((exercise ()
                     (dolist (arguments
                              (list
                               (list :location-filter circular)
                               (list :include-tags dotted)
                               (list :location-filter oversized)))
                       (expect
                        (lambda ()
                          (apply #'cl-weave:run
                                 "target"
                                 :stream (make-broadcast-stream)
                                 arguments))
                        :to-throw
                        "finite proper list"))))
            #+sbcl
            (sb-ext:with-timeout 10
              (exercise))
            #-sbcl
            (exercise)))
        (expect cl-weave::*root-suite* :to-be root)
        (expect cl-weave::*test-registry-generation* :to-be 0)
        (expect (hash-table-count cl-weave::*named-suites*) :to-be 0)
        (expect snapshot-count :to-be 0)
        (expect execution-count :to-be 0)
        (expect reporter-count :to-be 0))))

  (it "preflights LIST-TESTS filters before root creation and reporting"
    (let* ((limit cl-weave::+maximum-selection-filter-count+)
           (circular (list #P"/tmp/cl-weave/circular-list.lisp"))
           (dotted (cons :fast :tail))
           (oversized
             (make-list (1+ limit)
                        :initial-element #P"/tmp/cl-weave/oversized-list.lisp"))
           (snapshot-count 0)
           (reporter-count 0))
      (setf (cdr circular) circular)
      (let ((cl-weave::*root-suite* nil)
            (cl-weave::*named-suites* (make-hash-table :test #'equal))
            (cl-weave::*test-registry-generation* 0))
        (with-mocked-functions
            (((symbol-function 'cl-weave::snapshot-suite)
              (lambda (suite)
                (incf snapshot-count)
                suite))
             ((symbol-function 'cl-weave::report-plan-spec)
              (lambda (&rest arguments)
                (declare (ignore arguments))
                (incf reporter-count))))
          (labels ((exercise ()
                     (dolist (arguments
                              (list
                               (list :location-filter circular)
                               (list :include-tags dotted)
                               (list :location-filter oversized)))
                       (expect
                        (lambda ()
                          (apply #'cl-weave:list-tests
                                 :stream (make-broadcast-stream)
                                 arguments))
                        :to-throw
                        "finite proper list"))))
            #+sbcl
            (sb-ext:with-timeout 10
              (exercise))
            #-sbcl
            (exercise)))
        (expect cl-weave::*root-suite* :to-be nil)
        (expect cl-weave::*test-registry-generation* :to-be 0)
        (expect (hash-table-count cl-weave::*named-suites*) :to-be 0)
        (expect snapshot-count :to-be 0)
        (expect reporter-count :to-be 0))))

  (it "copies mutable public filters once before downstream suite access"
    (let* ((target-file #P"/tmp/cl-weave/public-preflight-target.lisp")
           (other-file #P"/tmp/cl-weave/public-preflight-other.lisp")
           (root (cl-weave::make-suite :name "root"))
           (run-name (copy-seq "target"))
           (run-locations (list target-file))
           (run-tags (list :fast))
           (list-name (copy-seq "target"))
           (list-locations (list target-file))
           (list-tags (list :fast)))
      (cl-weave::add-child
       root
       (cl-weave::make-test-case
        :name "target"
        :location (list :file (namestring target-file))
        :tags '("FAST")
        :function (lambda () t)))
      (with-mocked-functions
          (((symbol-function 'cl-weave::resolve-suite-designator)
            (lambda (designator)
              (declare (ignore designator))
              (setf (char run-name 0) #\x
                    (first run-locations) other-file
                    (first run-tags) :slow)
              root))
           ((symbol-function 'cl-weave:root-suite)
            (lambda ()
              (setf (char list-name 0) #\x
                    (first list-locations) other-file
                    (first list-tags) :slow)
              root)))
        (let ((events
                (cl-weave:run
                 :ignored
                 :stream (make-broadcast-stream)
                 :name-filter run-name
                 :location-filter run-locations
                 :include-tags run-tags)))
          (expect (length events) :to-be 1)
          (expect (cl-weave::test-event-status (first events)) :to-be :pass))
        (let ((plan
                (cl-weave:list-tests
                 :stream (make-broadcast-stream)
                 :name-filter list-name
                 :location-filter list-locations
                 :include-tags list-tags)))
          (expect (length plan) :to-be 1)
          (expect (cl-weave:test-plan-entry-path (first plan))
                  :to-equal '("target")))))))


(describe "list mode"
  (progn
  (it "carries normalized tags into plans and machine-readable reporters"
    (let* ((root (cl-weave::make-suite :name "root"))
           (suite (cl-weave::add-child
                   root (cl-weave::make-suite :name "tags" :parent root))))
      (cl-weave::add-child
       suite
       (cl-weave::make-test-case
        :name "case" :tags '("FAST" "UNIT") :function (lambda () t)))
      (let* ((plan (cl-weave:collect-test-plan root))
             (entry (first plan))
             (sexp (with-output-to-string (stream)
                     (cl-weave::report-plan-sexp plan stream)))
             (json (with-output-to-string (stream)
                     (cl-weave::report-plan-json plan stream)))
             (jsonl (with-output-to-string (stream)
                      (cl-weave::report-plan-jsonl plan stream))))
        (expect (cl-weave:test-plan-entry-tags entry)
                :to-equal '("FAST" "UNIT"))
        (expect sexp :to-satisfy (lambda (text) (search ":TAGS (\"FAST\" \"UNIT\")" text)))
        (dolist (text (list json jsonl))
          (expect text :to-satisfy
                  (lambda (output) (search "\"tags\":[\"FAST\",\"UNIT\"]" output)))))))

  (it "preserves suite clone identity and mutable hook invariants"
    (let* ((hook-one (lambda () :one))
           (hook-two (lambda () :two))
           (hooks (list hook-one hook-two))
           (root
             (cl-weave::make-suite
              :name "root"
              :before-all hooks
              :before-all-tail (last hooks)
              :after-all hooks
              :after-all-tail (last hooks)
              :before-each hooks
              :before-each-tail (last hooks)
              :around-each hooks
              :around-each-tail (last hooks)
              :after-each hooks
              :after-each-tail (last hooks)))
           (first-test
             (cl-weave::make-test-case :name "first" :function (lambda () t)))
           (nested (cl-weave::make-suite :name "nested" :parent root))
           (nested-test
             (cl-weave::make-test-case :name "nested test" :function (lambda () t)))
           (last-test
             (cl-weave::make-test-case :name "last" :function (lambda () t))))
      (cl-weave::add-child root first-test)
      (cl-weave::add-child root nested)
      (cl-weave::add-child root last-test)
      (cl-weave::add-child nested nested-test)
      (multiple-value-bind (clone suite-map)
          (cl-weave::clone-suite-tree-unlocked root)
        (let* ((clone-children (cl-weave::suite-children clone))
               (nested-clone (second clone-children)))
          (expect (hash-table-test suite-map) :to-be 'eq)
          (expect (hash-table-count suite-map) :to-be 2)
          (expect (gethash root suite-map) :to-be clone)
          (expect (gethash nested suite-map) :to-be nested-clone)
          (expect (eq clone root) :to-be nil)
          (expect (cl-weave::suite-parent clone) :to-be-null)
          (expect (cl-weave::suite-parent nested-clone) :to-be clone)
          (expect (first clone-children) :to-be first-test)
          (expect (third clone-children) :to-be last-test)
          (expect (first (cl-weave::suite-children nested-clone))
                  :to-be
                  nested-test)
          (dolist (accessors
                    (list
                     (list #'cl-weave::suite-before-all
                           #'cl-weave::suite-before-all-tail)
                     (list #'cl-weave::suite-after-all
                           #'cl-weave::suite-after-all-tail)
                     (list #'cl-weave::suite-before-each
                           #'cl-weave::suite-before-each-tail)
                     (list #'cl-weave::suite-around-each
                           #'cl-weave::suite-around-each-tail)
                     (list #'cl-weave::suite-after-each
                           #'cl-weave::suite-after-each-tail)))
            (destructuring-bind (hooks-accessor tail-accessor) accessors
              (let ((source-hooks (funcall hooks-accessor root))
                    (clone-hooks (funcall hooks-accessor clone)))
                (expect (eq clone-hooks source-hooks) :to-be nil)
                (expect (every #'eq clone-hooks source-hooks) :to-be t)
                (expect (funcall tail-accessor clone)
                        :to-be
                        (last clone-hooks)))))))))

  (progn
  (it "keeps snapshot list spines independent from later source mutations"
    (let* ((hook-one (lambda () :one))
           (hook-two (lambda () :two))
           (root-hooks (list hook-one))
           (root (cl-weave::make-suite
                  :name "root"
                  :before-each root-hooks
                  :before-each-tail (last root-hooks)))
           (first-test (cl-weave::make-test-case :name "first" :function (lambda ())))
           (late-test (cl-weave::make-test-case :name "late" :function (lambda ()))))
      (cl-weave::add-child root first-test)
      (let ((snapshot (cl-weave::snapshot-suite root)))
        (cl-weave::add-child root late-test)
        (let ((cell (list hook-two)))
          (setf (cdr (cl-weave::suite-before-each-tail root)) cell
                (cl-weave::suite-before-each-tail root) cell))
        (expect (mapcar (function cl-weave::test-case-name)
                        (cl-weave::suite-children snapshot))
                :to-equal
                (list "first"))
        (expect (cl-weave::suite-before-each snapshot)
                :to-equal
                (list hook-one))
        (expect (cl-weave::suite-before-each-tail snapshot)
                :to-be
                (last (cl-weave::suite-before-each snapshot))))))

  (it "clones suite trees 50000 levels deep without consuming control stack"
    (let* ((depth 50000)
           (root (cl-weave::make-suite :name "root"))
           (current root))
      (dotimes (index depth)
        (let* ((child
                 (cl-weave::make-suite :name index :parent current))
               (cell (list child)))
          (setf (cl-weave::suite-children current) cell
                (cl-weave::suite-children-tail current) cell
                current child)))
      (multiple-value-bind (clone suite-map)
          (cl-weave::clone-suite-tree-unlocked root)
        (let ((source root)
              (copy clone))
          (loop repeat depth
                do (setf source (first (cl-weave::suite-children source))
                         copy (first (cl-weave::suite-children copy))))
          (expect source :to-be current)
          (expect (cl-weave::suite-name copy) :to-be (1- depth))
          (expect (cl-weave::suite-children copy) :to-be-null)
          (expect (hash-table-count suite-map) :to-be (1+ depth))))))))

  (it "rejects CI-incompatible plan reporters before dispatch"
    (dolist (reporter '(:github :junit :tap))
      (expect (lambda ()
                (with-output-to-string (stream)
                  (cl-weave:list-tests :reporter reporter :stream stream)))
              :to-throw
              "cl-weave: list mode supports")))

  (it "collects selected tests without running hooks or bodies"
    (let* ((root (cl-weave::make-suite :name "root"))
           (events-log nil)
           (suite (cl-weave::add-child
                   root
                   (cl-weave::make-suite
                    :name "plan"
                    :parent root
                    :before-all (list (lambda () (push :before-all events-log)))
                    :after-all (list (lambda () (push :after-all events-log)))
                    :before-each (list (lambda () (push :before-each events-log)))
                    :after-each (list (lambda () (push :after-each events-log)))))))
      (cl-weave::add-child
       suite
       (cl-weave::make-test-case
        :name "runs later"
        :function (lambda () (push :body events-log))
        :retry 2
        :timeout-ms 250
        :execution-mode :concurrent))
      (cl-weave::add-child
       suite
       (cl-weave::make-test-case
        :name "hidden"
        :function (lambda () (push :hidden events-log))))
      (let ((plan (cl-weave:collect-test-plan root :name-filter "runs later")))
        (expect events-log :to-equal nil)
        (expect (mapcar #'cl-weave:test-plan-entry-status plan) :to-equal '(:run))
        (expect (mapcar #'cl-weave:test-plan-entry-path plan)
                :to-equal '(("plan" "runs later")))
        (expect (cl-weave:test-plan-entry-retry (first plan)) :to-be 2)
        (expect (cl-weave:test-plan-entry-timeout-ms (first plan)) :to-be 250)
        (expect (cl-weave:test-plan-entry-concurrent (first plan)) :to-be t))))

  (it "lists inherited and overridden execution modes as concurrent booleans"
    (let* ((root (cl-weave::make-suite :name "root"))
           (suite (cl-weave::add-child
                   root
                   (cl-weave::make-suite
                    :name "plan modes"
                    :parent root
                    :execution-mode :concurrent))))
      (cl-weave::add-child
       suite
       (cl-weave::make-test-case
        :name "inherits"
        :function (lambda () t)))
      (cl-weave::add-child
       suite
       (cl-weave::make-test-case
        :name "overrides"
        :function (lambda () t)
        :execution-mode :sequential))
      (let ((plan (cl-weave:collect-test-plan root)))
        (expect (mapcar #'cl-weave:test-plan-entry-path plan)
                :to-equal '(("plan modes" "inherits")
                            ("plan modes" "overrides")))
        (expect (mapcar #'cl-weave:test-plan-entry-concurrent plan)
                :to-equal '(t nil)))))

  (it "records source locations for macro-registered tests"
    (let* ((plan (cl-weave:collect-test-plan
                  (cl-weave::root-suite)
                  :name-filter "supports public custom matchers with structured failure data"))
           (location (cl-weave:test-plan-entry-location (first plan))))
      (expect (length plan) :to-be 1)
      (expect (getf location :file) :to-contain "tests/expect-extensions.lisp")))

  (it "lists only tests whose source file matches the location filter"
    (let* ((root (cl-weave::make-suite :name "root"))
           (suite (cl-weave::add-child
                   root
                   (cl-weave::make-suite :name "plan-files" :parent root)))
           (target #P"/tmp/cl-weave/plan-target.lisp")
           (other #P"/tmp/cl-weave/plan-other.lisp"))
      (cl-weave::add-child
       suite
       (cl-weave::make-test-case
        :name "target"
        :location (list :file (namestring target))
        :function (lambda () (error "should not run"))))
      (cl-weave::add-child
       suite
       (cl-weave::make-test-case
        :name "other"
        :location (list :file (namestring other))
        :function (lambda () (error "should not run"))))
      (let ((plan (cl-weave:collect-test-plan root :location-filter (list target))))
        (expect (mapcar #'cl-weave:test-plan-entry-path plan)
                :to-equal '(("plan-files" "target"))))))

  (it "lists suppressed suites without running their descendants"
    (let* ((root (cl-weave::make-suite :name "root"))
           (skipped (cl-weave::add-child
                     root
                     (cl-weave::make-suite
                      :name "blocked"
                      :parent root
                      :skip-reason "suite blocked")))
           (todo (cl-weave::add-child
                  root
                  (cl-weave::make-suite
                   :name "pending"
                   :parent root
                   :todo-reason "suite pending"))))
      (cl-weave::add-child
       skipped
       (cl-weave::make-test-case
        :name "case"
        :function (lambda () (error "should not run"))))
      (cl-weave::add-child
       todo
       (cl-weave::make-test-case
        :name "case"
        :function (lambda () (error "should not run"))))
      (let ((plan (cl-weave:collect-test-plan root)))
        (expect (mapcar #'cl-weave:test-plan-entry-status plan)
                :to-equal '(:skip :todo))
        (expect (mapcar #'cl-weave:test-plan-entry-reason plan)
                :to-equal '("suite blocked" "suite pending")))))

  (it "lists focus metadata"
    (let* ((root (cl-weave::make-suite :name "root"))
           (focused (cl-weave::add-child
                     root
                     (cl-weave::make-suite
                      :name "focused"
                      :parent root
                      :focus t))))
      (cl-weave::add-child
       focused
       (cl-weave::make-test-case
        :name "todo case"
        :function (lambda () (error "should not run"))
        :todo-reason "pending"))
      (let ((plan (cl-weave:collect-test-plan root)))
        (expect (mapcar #'cl-weave:test-plan-entry-path plan)
                :to-equal '(("focused" "todo case")))
        (expect (mapcar #'cl-weave:test-plan-entry-status plan) :to-equal '(:todo))
        (expect (mapcar #'cl-weave:test-plan-entry-reason plan)
                :to-equal '("pending"))
        (expect (mapcar #'cl-weave:test-plan-entry-focused plan)
                :to-equal '(t)))))

  (it "lists only describe-only-each descendants as focused plan entries"
    (let ((root (cl-weave::make-suite :name "root"))
          (ran nil))
      (let ((cl-weave::*root-suite* root)
            (cl-weave::*current-suite* nil))
        (describe "plain suite"
          (it "outside"
            (setf ran :outside)))
        (describe-only-each ((1 2 3) (2 3 5))
            "focused suite ~A and ~A"
            (left right total)
          (it "case"
            (setf ran (list left right total)))))
      (let ((plan (cl-weave:collect-test-plan root)))
        (expect ran :to-be nil)
        (expect (mapcar #'cl-weave:test-plan-entry-path plan)
                :to-equal '(("focused suite 1 and 2" "case")
                            ("focused suite 2 and 3" "case")))
        (expect (mapcar #'cl-weave:test-plan-entry-status plan)
                :to-equal '(:run :run))
        (expect (mapcar #'cl-weave:test-plan-entry-focused plan)
                :to-equal '(t t)))))

  (it "exposes test plans as logic facts"
    (let* ((root (cl-weave::make-suite :name "root"))
           (suite (cl-weave::add-child
                   root
                   (cl-weave::make-suite
                    :name "logic"
                    :parent root
                    :focus t))))
      (cl-weave::add-child
       suite
       (cl-weave::make-test-case
        :name "runs"
        :function (lambda () t)
        :retry 2
        :timeout-ms 250
        :execution-mode :concurrent))
      (cl-weave::add-child
       suite
       (cl-weave::make-test-case
        :name "skips"
        :function (lambda () t)
        :skip-reason "blocked"))
      (let ((facts (test-plan-facts (cl-weave:collect-test-plan root))))
        (expect facts :to-contain '(:test ("logic" "runs")))
        (expect facts :to-contain '(:status ("logic" "runs") :run))
        (expect facts :to-contain '(:focused ("logic" "runs")))
        (expect facts :to-contain '(:retry ("logic" "runs") 2))
        (expect facts :to-contain '(:timeout-ms ("logic" "runs") 250))
        (expect facts :to-contain '(:concurrent ("logic" "runs")))
        (expect facts :to-contain '(:reason ("logic" "skips") "blocked")))))

  (it "queries test plans with Prolog-style variables"
    (let* ((root (cl-weave::make-suite :name "root"))
           (suite (cl-weave::add-child
                   root
                   (cl-weave::make-suite
                    :name "logic"
                    :parent root
                    :focus t))))
      (cl-weave::add-child
       suite
       (cl-weave::make-test-case
        :name "runs"
        :function (lambda () t)
        :execution-mode :concurrent))
      (cl-weave::add-child
       suite
       (cl-weave::make-test-case
        :name "skips"
        :function (lambda () t)
        :skip-reason "blocked"))
      (let* ((plan (cl-weave:collect-test-plan root))
             (focused-concurrent
               (query-test-plan plan
                                '((:status ?test :run)
                                  (:focused ?test)
                                  (:concurrent ?test))))
             (limited (query-test-plan plan '((:test ?test)) :limit 1)))
        (expect (logic-variable-p '?test) :to-be t)
        (expect focused-concurrent :to-equal '(((?test . ("logic" "runs")))))
        (expect (length limited) :to-be 1)))))

(progn
  (it "queries facts with Prolog-style macro clauses"
    (let ((facts '((:test ("logic" "runs"))
                   (:status ("logic" "runs") :run)
                   (:concurrent ("logic" "runs"))
                   (:test ("logic" "skips"))
                   (:status ("logic" "skips") :skip))))
      (expect (logic-where facts
                (:status ?test :run)
                (:concurrent ?test))
              :to-equal '(((?test . ("logic" "runs")))))
      (expect (logic-where facts
                (:limit 1)
                (:test ?test))
              :to-equal '(((?test . ("logic" "runs")))))))

  (it "indexes exact path filters without changing path semantics"
    (let* ((count 2000)
           (root (cl-weave::make-suite :name "root"))
           (suite
             (cl-weave::add-child
              root
              (cl-weave::make-suite :name "indexed" :parent root)))
           (filters nil))
      (dotimes (index count)
        (let ((name (format nil "case-~4,'0D" index)))
          (cl-weave::add-child
           suite
           (cl-weave::make-test-case
            :name name
            :function (lambda () t)))
          (push (list (copy-seq "indexed") (copy-seq name)) filters)))
      (dolist (name (list (copy-seq "duplicate")
                          (copy-seq "duplicate")))
        (cl-weave::add-child
         suite
         (cl-weave::make-test-case
          :name name
          :function (lambda () t))))
      (push (list (copy-seq "indexed") (copy-seq "duplicate")) filters)
      (push (list (copy-seq "indexed") (copy-seq "duplicate")) filters)
      (let* ((plan (cl-weave:collect-test-plan
                    root
                    :test-path-filter filters))
             (paths (mapcar #'cl-weave:test-plan-entry-path plan)))
        (expect (length plan) :to-be (+ count 2))
        (expect (first paths) :to-equal '("indexed" "case-0000"))
        (expect (nth (1- count) paths)
                :to-equal '("indexed" "case-1999"))
        (expect (subseq paths count)
                :to-equal '(("indexed" "duplicate")
                            ("indexed" "duplicate")))
        (expect (length (cl-weave:collect-test-plan
                         root
                         :test-path-filter nil))
                :to-be (+ count 2)))))

  (it "computes each test path once per collection traversal"
    (let* ((count 128)
           (root (cl-weave::make-suite :name "root"))
           (suite
             (cl-weave::add-child
              root
              (cl-weave::make-suite :name "path-count" :parent root)))
           (original-test-path
             (symbol-function 'cl-weave::test-path)))
      (dotimes (index count)
        (cl-weave::add-child
         suite
         (cl-weave::make-test-case
          :name (format nil "case-~D" index)
          :function (lambda () t))))
      (dolist (shard (list nil '(1 2)))
        (let ((call-count 0))
          (with-mocked-functions
              (((symbol-function 'cl-weave::test-path)
                (lambda (parent test)
                  (incf call-count)
                  (funcall original-test-path parent test))))
            (cl-weave:collect-test-plan root :shard shard))
          (expect call-count :to-be count)))))

  (it "builds one focus index and uses linear suite membership checks"
    (let* ((depth 1024)
           (root (cl-weave::make-suite :name "root"))
           (parent root)
           (original-build-focus-index
             (symbol-function 'cl-weave::build-focus-index))
           (original-focused-child-p
             (symbol-function 'cl-weave::focused-child-p))
           (original-selected-suite-p
             (symbol-function 'cl-weave::selected-suite-p))
           (focus-index-count 0)
           (recursive-focus-count 0)
           (suite-membership-count 0))
      (dotimes (index depth)
        (let ((child
                (cl-weave::make-suite
                 :name (format nil "level-~D" index)
                 :parent parent)))
          (cl-weave::add-child parent child)
          (setf parent child)))
      (cl-weave::add-child
       parent
       (cl-weave::make-test-case
        :name "focused leaf"
        :focus t
        :function (lambda () t)))
      (with-mocked-functions
          (((symbol-function 'cl-weave::build-focus-index)
            (lambda (suite)
              (incf focus-index-count)
              (funcall original-build-focus-index suite)))
           ((symbol-function 'cl-weave::focused-child-p)
            (lambda (child)
              (incf recursive-focus-count)
              (funcall original-focused-child-p child)))
           ((symbol-function 'cl-weave::selected-suite-p)
            (lambda (suite filter ancestor-focused)
              (incf suite-membership-count)
              (funcall original-selected-suite-p
                       suite filter ancestor-focused))))
        (let ((plan (cl-weave:collect-test-plan root)))
          (expect (length plan) :to-be 1)
          (expect (car (last
                        (cl-weave:test-plan-entry-path (first plan))))
                  :to-equal "focused leaf")))
      (expect focus-index-count :to-be 1)
      (expect recursive-focus-count :to-be 0)
      (expect suite-membership-count
              :to-be-less-than-or-equal
              (1+ depth)))))

(it "derives recursive relations with Prolog-style rules"
    (let ((program (logic-program
                    (:parent "grand" "parent")
                    (:parent "parent" "child")
                    (:- (:ancestor ?left ?right)
                        (:parent ?left ?right))
                    (:- (:ancestor ?left ?right)
                        (:parent ?left ?middle)
                        (:ancestor ?middle ?right)))))
      (expect (logic-run program
                (:ancestor ?left "child"))
              :to-equal
              '(((?left . "parent"))
                ((?left . "grand"))))
      (expect (logic-run program
                (:limit 1)
                (:ancestor ?left "child"))
              :to-equal
              '(((?left . "parent"))))))

(it "rejects cyclic logic bindings"
    (multiple-value-bind (bindings matched-p)
        (cl-weave::unify-logic-values '?x '(:node ?x) nil)
      (declare (ignore bindings))
      (expect matched-p :to-be nil))
    (multiple-value-bind (bindings matched-p)
        (cl-weave::unify-logic-values '(:node ?x) '?x nil)
      (declare (ignore bindings))
      (expect matched-p :to-be nil)))

(it "resolves variables in dotted logic pairs without losing the tail"
    (multiple-value-bind (bindings matched-p)
        (cl-weave::unify-logic-values '(:pair ?head . ?tail)
                                      '(:pair :left . :right)
                                      nil)
      (expect matched-p :to-be t)
      (expect (cl-weave::resolve-logic-value '(:pair ?head . ?tail) bindings)
              :to-equal '(:pair :left . :right))))

(it "resolves long proper lists without consuming stack per element"
    (let* ((length 100000)
           (value (make-list length :initial-element '?value))
           (resolved (cl-weave::resolve-logic-value
                      value '((?value . :resolved)))))
      (expect (length resolved) :to-be length)
      (expect (every (lambda (part) (eq part :resolved)) resolved)
              :to-be t)))

(it "recursively resolves a dotted tail after iterating the list spine"
    (expect (cl-weave::resolve-logic-value
             '(:first ?head . ?tail)
             '((?head . :middle) (?tail . (:tail ?value)) (?value . :end)))
            :to-equal '(:first :middle :tail :end)))

(it "bounds recursive logic searches with explicit recovery restarts"
    (let ((program (logic-program
                    (:- (:loop ?value)
                        (:loop ?value)))))
      (expect (handler-bind
                  ((logic-search-exhausted
                     (lambda (condition)
                       (expect (logic-search-exhausted-limit condition) :to-be 3)
                       (expect (logic-search-exhausted-steps condition) :to-be 3)
                       (expect (logic-search-exhausted-pending condition)
                               :to-satisfy #'plusp)
                       (expect (logic-search-exhausted-partial-results condition)
                               :to-equal nil)
                       (expect (find-restart 'cl-weave:increase-limit condition)
                               :to-be-truthy)
                       (invoke-restart (find-restart 'cl-weave:return-partial-results
                                                     condition)))))
                (logic-query program '((:loop "forever")) :max-steps 3))
              :to-equal nil)))

(it "forwards logic step limits through test plan queries"
    (let ((program (logic-program (:item "found")))
          (exhaustions 0))
      (expect (handler-bind
                  ((logic-search-exhausted
                     (lambda (condition)
                       (incf exhaustions)
                       (invoke-restart (find-restart 'cl-weave:increase-limit condition)
                                       2))))
                (query-test-plan program '((:item ?value)) :max-steps 1))
              :to-equal '(((?value . "found"))))
      (expect exhaustions :to-be 1)))

(it "propagates max steps through logic query macros"
    (let ((program (logic-program
                    (:- (:loop ?value)
                        (:loop ?value))))
          (exhaustions 0))
      (dolist (query (list (lambda ()
                             (logic-run program
                               (:max-steps 2)
                               (:loop "forever")))
                           (lambda ()
                             (logic-where program
                               (:max-steps 2)
                               (:loop "forever")))
                           (lambda ()
                             (test-plan-where program
                               (:max-steps 2)
                               (:loop "forever")))))
        (handler-bind
            ((logic-search-exhausted
               (lambda (condition)
                 (incf exhaustions)
                 (invoke-restart
                  (find-restart 'cl-weave:return-partial-results condition)))))
          (funcall query)))
      (expect exhaustions :to-be 3)))

(it "walks defensive cyclic binding inputs without recursing forever"
    (expect (cl-weave::logic-walk '?x '((?x . ?y) (?y . ?x)))
            :to-satisfy #'logic-variable-p))

(it "queries test plans with macro clauses"
    (let* ((root (cl-weave::make-suite :name "root"))
           (suite (cl-weave::add-child
                   root
                   (cl-weave::make-suite :name "logic" :parent root :focus t))))
      (cl-weave::add-child
       suite
       (cl-weave::make-test-case
        :name "runs"
        :function (lambda () t)
        :execution-mode :concurrent))
      (cl-weave::add-child
       suite
       (cl-weave::make-test-case
        :name "plain"
        :function (lambda () t)))
      (let ((plan (cl-weave:collect-test-plan root)))
        (expect (test-plan-where plan
                  (:status ?test :run)
                  (:focused ?test)
                  (:concurrent ?test))
                :to-equal
                '(((?test . ("logic" "runs"))))))))

(it "queries derived test plan views with rules"
    (let* ((root (cl-weave::make-suite :name "root"))
           (suite (cl-weave::add-child
                   root
                   (cl-weave::make-suite :name "logic" :parent root :focus t))))
      (cl-weave::add-child
       suite
       (cl-weave::make-test-case
        :name "runs"
        :function (lambda () t)
        :execution-mode :concurrent))
      (cl-weave::add-child
       suite
       (cl-weave::make-test-case
        :name "plain"
        :function (lambda () t)))
      (let* ((plan (cl-weave:collect-test-plan root))
             (program (append
                       (test-plan-facts plan)
                       (logic-program
                        (:- (:selected ?test)
                            (:status ?test :run)
                            (:focused ?test)
                            (:concurrent ?test))))))
        (expect (test-plan-where program
                  (:selected ?test))
                :to-equal
                '(((?test . ("logic" "runs"))))))))

(it "preserves plan and event order through deeply nested suite tails"
  (let* ((depth 1024)
         (root (cl-weave::make-suite :name "root"))
         (current root))
    (dotimes (index depth)
      (let ((nested (cl-weave::make-suite
                     :name (format nil "level-~D" index)
                     :parent current)))
        (cl-weave::add-child current nested)
        (cl-weave::add-child
         current
         (cl-weave::make-test-case
          :name (format nil "after-~D" index)
          :function (lambda () t)))
        (setf current nested)))
    (cl-weave::add-child
     current
     (cl-weave::make-test-case :name "leaf" :function (lambda () t)))
    (let* ((expected-names
             (cons "leaf"
                   (loop for index downfrom (1- depth) to 0
                         collect (format nil "after-~D" index))))
           (plan (cl-weave:collect-test-plan root))
           (events (cl-weave::collect-events root)))
      (expect (length plan) :to-be (1+ depth))
      (expect (length events) :to-be (1+ depth))
      (expect (mapcar (lambda (entry)
                        (car (last (cl-weave:test-plan-entry-path entry))))
                      plan)
              :to-equal expected-names)
      (expect (mapcar (lambda (event)
                        (car (last (cl-weave::test-event-path event))))
                      events)
              :to-equal expected-names)
      (expect (mapcar (function cl-weave::test-event-status) events)
              :to-equal (make-list (1+ depth) :initial-element :pass)))))
