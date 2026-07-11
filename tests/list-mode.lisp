(in-package #:cl-weave/tests)

(describe "list mode"
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
        :concurrent t
        :tags '(:fast :migration)
        :depends-on '(bootstrap)))
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
        (expect (cl-weave:test-plan-entry-concurrent (first plan)) :to-be t)
        (expect (cl-weave:test-plan-entry-tags (first plan))
                :to-equal '(:fast :migration))
        (expect (cl-weave:test-plan-entry-depends-on (first plan))
                :to-equal '(bootstrap)))))

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
      (expect (getf location :file) :to-contain "tests/expect.lisp")))

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
        :concurrent t
        :tags '(:fast :migration)
        :depends-on '(bootstrap)))
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
        (expect facts :to-contain '(:tag ("logic" "runs") :fast))
        (expect facts :to-contain '(:tag ("logic" "runs") :migration))
        (expect facts :to-contain '(:depends-on ("logic" "runs") bootstrap))
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
        :concurrent t
        :tags '(:fast)
        :depends-on '(bootstrap)))
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
                                  (:concurrent ?test)
                                  (:tag ?test :fast)
                                  (:depends-on ?test bootstrap))))
             (limited (query-test-plan plan '((:test ?test)) :limit 1)))
        (expect (logic-variable-p '?test) :to-be t)
        (expect focused-concurrent :to-equal '(((?test . ("logic" "runs")))))
        (expect (length limited) :to-be 1)))))

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
        :concurrent t))
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
        :concurrent t))
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
