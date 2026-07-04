(in-package #:cl-weave/tests)

(cl-weave:clear-tests)

(defvar *fixture-value* nil)
(defvar *fixture-events* nil)
(defun sample-size (value) (length value))

(defclass sample-widget ()
  ((name :initarg :name :reader sample-widget-name)
   (state :initarg :state :initform :new :reader sample-widget-state)))

(defgeneric render-widget (widget stream))

(defmethod render-widget ((widget sample-widget) stream)
  (declare (ignore stream))
  (sample-widget-name widget))

(defmacro sample-unless (condition &body body)
  `(if ,condition
       nil
       (progn ,@body)))

(defmacro matcher-pass-cases (&body cases)
  `(progn
     ,@(loop for (name form) in cases
             collect `(it ,name ,form))))

(defun tree-contains-p (tree value)
  (cond
    ((equal tree value) t)
    ((consp tree)
     (or (tree-contains-p (car tree) value)
         (tree-contains-p (cdr tree) value)))
    (t nil)))

(defun tree-depth (tree)
  (if (consp tree)
      (1+ (reduce #'max tree :key #'tree-depth :initial-value 0))
      0))

(describe "expect"
  (matcher-pass-cases
    ("to-be" (expect 2 :to-be 2))
    ("to-equal" (expect (list :a 1) :to-equal (list :a 1)))
    ("to-equalp" (expect "ok" :to-equalp "OK"))
    ("to-be-truthy" (expect :value :to-be-truthy))
    ("to-be-falsy" (expect nil :to-be-falsy))
    ("to-be-null" (expect nil :to-be-null))
    ("to-be-defined" (expect :value :to-be-defined))
    ("to-satisfy" (expect 4 :to-satisfy #'evenp))
    ("to-be-type-of" (expect 10 :to-be-type-of 'integer))
    ("to-be-instance-of"
     (expect (make-instance 'sample-widget) :to-be-instance-of 'sample-widget))
    ("to-contain list" (expect '(:a :b :c) :to-contain :b))
    ("to-contain vector" (expect #(:a :b :c) :to-contain :b))
    ("to-contain string" (expect "common-lisp" :to-contain "lisp"))
    ("to-have-length list" (expect '(:a :b :c) :to-have-length 3))
    ("to-have-length vector" (expect #(:a :b :c) :to-have-length 3))
    ("to-have-length string" (expect "abc" :to-have-length 3))
    ("to-be-greater-than" (expect 10 :to-be-greater-than 9))
    ("to-be-greater-than-or-equal" (expect 10 :to-be-greater-than-or-equal 10))
    ("to-be-less-than" (expect 9 :to-be-less-than 10))
    ("to-be-less-than-or-equal" (expect 10 :to-be-less-than-or-equal 10))
    ("to-throw" (expect (lambda () (error "boom")) :to-throw))
    ("to-run-under-ms" (expect (lambda () (+ 1 1)) :to-run-under-ms 1000))
    ("to-cons-less-than"
     (expect (lambda () nil) :to-cons-less-than most-positive-fixnum))
    ("to-have-slot symbol" (expect 'sample-widget :to-have-slot 'name))
    ("to-have-slot instance"
     (expect (make-instance 'sample-widget :name "ok") :to-have-slot 'state))
    ("to-have-method-specialized-on"
     (expect #'render-widget :to-have-method-specialized-on '(sample-widget t)))
    ("to-throw rejects non-throwing thunk"
     (expect (lambda () (expect (lambda () :ok) :to-throw)) :to-throw))
    ("to-throw rejects non-function"
     (expect (lambda () (expect :not-a-function :to-throw)) :to-throw))
    ("smart equality assertion" (expect (= (+ 1 1) 2)))
    ("smart relational assertion" (expect (< 1 2 3)))
    ("smart truthy assertion" (expect (member :b '(:a :b :c))))
    ("to-match-inline-snapshot"
     (expect '(:ok 42) :to-match-inline-snapshot "(:ok 42)"))
    ("to-match-snapshot"
     (let ((cl-weave::*snapshot-directory* #P"/tmp/cl-weave-core-snapshots/")
           (cl-weave::*snapshot-file-name* "matchers.snapshots"))
       (cl-weave:with-snapshot-updates
         (expect '(:ok 42) :to-match-snapshot "matcher external snapshot"))
       (expect '(:ok 42) :to-match-snapshot "matcher external snapshot")))
    ("to-match-snapshot rejects missing snapshots"
     (let ((cl-weave::*snapshot-directory* #P"/tmp/cl-weave-core-snapshots/")
           (cl-weave::*snapshot-file-name* "missing.snapshots")
           (key (symbol-name (gensym "MISSING-SNAPSHOT-"))))
       (expect (lambda ()
                 (expect '(:missing 42) :to-match-snapshot key))
               :to-throw)))
    ("not" (expect 1 :not :to-be 2)))

  (it "signals assertion-failure with structured data"
    (handler-case
        (progn
          (expect 1 :to-be 2)
          (expect nil :to-be-truthy))
      (cl-weave:assertion-failure (condition)
        (let ((detail (cl-weave::failure-detail condition)))
          (expect (cl-weave::assertion-detail-matcher detail) :to-be :to-be)
          (expect (cl-weave::assertion-detail-actual detail) :to-be 1)
          (expect (cl-weave::assertion-detail-expected detail) :to-equal '(2))))))

  (it "signals smart assertion failures with operand values"
    (handler-case
        (progn
          (expect (= (+ 1 1) 3))
          (expect nil :to-be-truthy))
      (cl-weave:assertion-failure (condition)
        (let* ((detail (cl-weave::failure-detail condition))
               (actual (cl-weave::assertion-detail-actual detail)))
          (expect (cl-weave::assertion-detail-matcher detail) :to-be '=)
          (expect actual :to-contain '(:form (+ 1 1) :value 2))
          (expect actual :to-contain '(:form 3 :value 3))
          (expect (cl-weave::assertion-detail-expected detail)
                  :to-equal '(= (+ 1 1) 3))))))

  (it "reports performance measurements in assertion failures"
    (handler-case
        (progn
          (expect (lambda () (sleep 0.001)) :to-run-under-ms 0)
          (expect nil :to-be-truthy))
      (cl-weave:assertion-failure (condition)
        (let* ((detail (cl-weave::failure-detail condition))
               (actual (cl-weave::assertion-detail-actual detail)))
          (expect (cl-weave::assertion-detail-matcher detail) :to-be :to-run-under-ms)
          (expect actual :to-contain :elapsed-ms)
          (expect actual :to-contain :elapsed-seconds)
          (expect actual :to-contain :bytes-consed)
          (expect actual :to-contain :values)
          (expect (cl-weave::assertion-detail-expected detail)
                  :to-equal '(:max-ms 0)))))))

(describe "macros"
  (it-each ((1 2 3)
            (13 21 34))
      "adds ~A and ~A at macro expansion time"
      (left right total)
    (expect (+ left right) :to-be total))

  (test-each ((2 3 5)
              (5 8 13))
      "aliases test-each for ~A and ~A"
      (left right total)
    (expect (+ left right) :to-be total))

  (describe-each ((3 4 7)
                  (8 13 21))
      "table suite ~A plus ~A"
      (left right total)
    (before-each
      (setf (gethash :table-total *test-context*) total))
    (it "runs generated nested cases with fixtures"
      (expect (+ left right) :to-be total)
      (expect (gethash :table-total *test-context*) :to-be total)))

  (it "expands expect into the assertion engine"
    (expect (macroexpand-1 '(expect (+ 1 1) :to-be 2))
            :to-satisfy
            (lambda (form)
              (tree-contains-p form 'cl-weave::assert-expectation))))

  (it "expands smart expect into operand capture"
    (expect (macroexpand-1 '(expect (= (+ 1 1) 2)))
            :to-satisfy
            (lambda (form)
              (and (tree-contains-p form 'cl-weave::signal-smart-assertion-failure)
                   (tree-contains-p form 'cl-weave::operand-report-form)))))

  (it "expands it-only into focused test registration"
    (expect (macroexpand-1 '(it-only "focused" (expect 1 :to-be 1)))
            :to-satisfy
            (lambda (form)
              (and (tree-contains-p form 'cl-weave::register-test)
                   (tree-contains-p form :focus)))))

  (it "expands it options into retry and timeout metadata"
    (expect (macroexpand-1
             '(it "eventually stable" (:retry 2 :timeout-ms 100)
                (expect :ok :to-be :ok)))
            :to-satisfy
            (lambda (form)
              (and (tree-contains-p form 'cl-weave::register-test)
                   (tree-contains-p form :retry)
                   (tree-contains-p form 2)
                   (tree-contains-p form :timeout-ms)
                   (tree-contains-p form 100)))))

  (it "expands describe-skip into skipped suite registration"
    (expect (macroexpand-1
             '(describe-skip "blocked" "upstream gap"
                (it "case" (expect 1 :to-be 1))))
            :to-satisfy
            (lambda (form)
              (and (tree-contains-p form 'cl-weave::register-suite)
                   (tree-contains-p form :skip-reason)
                   (tree-contains-p form "upstream gap")))))

  (it "expands describe-todo into todo suite registration"
    (expect (macroexpand-1
             '(describe-todo "pending" "needs design"
                (it "case" (expect 1 :to-be 1))))
            :to-satisfy
            (lambda (form)
              (and (tree-contains-p form 'cl-weave::register-suite)
                   (tree-contains-p form :todo-reason)
                   (tree-contains-p form "needs design")))))

  (it "expands describe-each into independent suites"
    (expect (macroexpand-1
             '(describe-each ((1 2 3))
                  "suite ~A"
                  (left right total)
                (it "adds" (expect (+ left right) :to-be total))))
            :to-satisfy
            (lambda (form)
              (and (tree-contains-p form 'cl-weave::describe)
                   (tree-contains-p form 'destructuring-bind)))))

  (it "expands test-each through the it-each macro"
    (expect (macroexpand-1
             '(test-each ((1 2 3))
                  "adds ~A and ~A"
                  (left right total)
                (expect (+ left right) :to-be total)))
            :to-satisfy
            (lambda (form)
              (tree-contains-p form 'cl-weave:it-each))))

  (it "compares a single macroexpansion step"
    (expect '(sample-unless ready (setf *fixture-value* :done))
            :to-expand-to
            '(if ready
                 nil
                 (progn (setf *fixture-value* :done))))))

(describe "isolation"
  (it "expands it-isolated into the isolated runner"
    (expect (macroexpand-1
             '(it-isolated "child process"
                  (:systems ("cl-weave-tests") :timeout 5)
                (expect 1 :to-be 1)))
            :to-satisfy
            (lambda (form)
              (and (tree-contains-p form 'cl-weave::run-isolated)
                   (tree-contains-p form 'cl-weave::assert-isolated-success)))))

  (it-isolated "runs assertions in a child SBCL process"
      (:systems ("cl-weave-tests") :timeout 20)
    (expect (+ 2 3) :to-be 5))

  (it "reports child process failures without failing the parent process"
    (let ((result (run-isolated
                   '(error "child boom")
                   :systems '("cl-weave-tests")
                   :package "CL-WEAVE/TESTS"
                   :timeout 20)))
      (expect (isolated-result-status result) :to-be :fail)
      (expect (isolated-result-exit-code result) :to-be 1)
      (expect (isolated-result-stderr result) :to-contain "child boom")))

  (it "terminates isolated tests on timeout"
    (let ((result (run-isolated
                   '(sleep 2)
                   :systems '("cl-weave-tests")
                   :package "CL-WEAVE/TESTS"
                   :timeout 0.1)))
      (expect (isolated-result-status result) :to-be :timeout)
      (expect (isolated-result-timed-out-p result) :to-be-truthy))))

(describe "properties"
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
          (expect actual :to-contain :values)
          (expect actual :to-contain :minimal)))))

  (it "expands it-property into the property runner"
    (expect (macroexpand-1
             '(it-property "positive identity"
                  ((value (gen-integer :min 1 :max 3)))
                (expect value :to-be value)))
            :to-satisfy
            (lambda (form)
              (tree-contains-p form 'cl-weave::run-property)))))

(describe "fixtures"
  (before-all
    (setf *fixture-events* (list :before-all)))

  (before-each
    (setf *fixture-value* 41)
    (push :before-each *fixture-events*)
    (setf (gethash :trace *test-context*) '(:before)))

  (after-each
    (push :after-each *fixture-events*)
    (setf *fixture-value* nil))

  (after-all
    (setf *fixture-events* nil))

  (it "runs before-each with dynamic context"
    (expect *fixture-events* :to-equal '(:before-each :before-all))
    (expect *fixture-value* :to-be 41)
    (expect (gethash :trace *test-context*) :to-equal '(:before))
    (incf *fixture-value*)
    (expect *fixture-value* :to-be 42))

  (it "keeps before-all state across cases"
    (expect *fixture-events* :to-equal '(:before-each :after-each :before-each :before-all))))

(describe "retry and timeout"
  (it "retries failing tests until they pass"
    (let* ((attempts 0)
           (test (cl-weave::make-test-case
                  :name "eventual pass"
                  :retry 2
                  :function (lambda ()
                              (incf attempts)
                              (when (< attempts 3)
                                (expect attempts :to-be 3)))))
           (event (cl-weave::run-test-case (cl-weave::root-suite) test)))
      (expect attempts :to-be 3)
      (expect (cl-weave::test-event-status event) :to-be :pass)))

  (it "stops retrying after the configured retry budget"
    (let* ((attempts 0)
           (test (cl-weave::make-test-case
                  :name "always fails"
                  :retry 2
                  :function (lambda ()
                              (incf attempts)
                              (expect attempts :to-be 10))))
           (event (cl-weave::run-test-case (cl-weave::root-suite) test)))
      (expect attempts :to-be 3)
      (expect (cl-weave::test-event-status event) :to-be :fail)
      (expect (cl-weave::test-event-assertion event) :to-be-defined)))

  (it "reports timed out tests as structured failures"
    (let* ((test (cl-weave::make-test-case
                  :name "slow"
                  :timeout-ms 10
                  :function (lambda () (sleep 0.1))))
           (event (cl-weave::run-test-case (cl-weave::root-suite) test)))
      (expect (cl-weave::test-event-status event) :to-be :fail)
      (expect (cl-weave::test-event-condition event)
              :to-be-instance-of 'cl-weave:test-timeout)
      (expect (cl-weave:test-timeout-ms (cl-weave::test-event-condition event))
              :to-be 10)))

  (it "runs after-each cleanup when an attempt times out"
    (let* ((events nil)
           (suite (cl-weave::make-suite
                   :name "timeout cleanup"
                   :after-each (list (lambda () (push :after-each events)))))
           (test (cl-weave::make-test-case
                  :name "slow"
                  :timeout-ms 10
                  :function (lambda () (sleep 0.1)))))
      (cl-weave::add-child suite test)
      (let ((event (cl-weave::run-test-case suite test)))
        (expect (cl-weave::test-event-status event) :to-be :fail)
        (expect events :to-equal '(:after-each))))))

(describe "skips"
  (it-skip "does not run skipped tests" "documented gap")

  (it "reports skipped tests without failing the suite"
    (let* ((test (cl-weave::make-test-case
                  :name "skipped case"
                  :function (lambda () (error "should not run"))
                  :skip-reason "not implemented"))
           (event (cl-weave::run-test-case (cl-weave::root-suite) test)))
      (expect (cl-weave::test-event-status event) :to-be :skip)
      (expect (cl-weave::test-event-reason event) :to-equal "not implemented")
      (expect (cl-weave::passed-event-p event) :to-be-truthy)))

  (it "reports skipped suite descendants without running hooks or bodies"
    (let* ((root (cl-weave::make-suite :name "root"))
           (suite (cl-weave::add-child
                   root
                   (cl-weave::make-suite
                    :name "blocked"
                    :parent root
                    :skip-reason "suite blocked"
                    :before-all (list (lambda () (error "before-all should not run")))
                    :after-all (list (lambda () (error "after-all should not run")))
                    :before-each (list (lambda () (error "before-each should not run")))
                    :after-each (list (lambda () (error "after-each should not run")))))))
      (cl-weave::add-child
       suite
       (cl-weave::make-test-case
        :name "case"
        :function (lambda () (error "test body should not run"))))
      (let ((events (cl-weave::collect-events root)))
        (expect (mapcar #'cl-weave::test-event-status events) :to-equal '(:skip))
        (expect (mapcar #'cl-weave::test-event-reason events)
                :to-equal '("suite blocked"))
        (expect (mapcar #'cl-weave::test-event-path events)
                :to-equal '(("blocked" "case")))))))

(describe "todos"
  (it-todo "documents pending work" "intentional")

  (it "reports todo tests without running their body"
    (let* ((test (cl-weave::make-test-case
                  :name "todo case"
                  :function (lambda () (error "should not run"))
                  :todo-reason "pending"))
           (event (cl-weave::run-test-case (cl-weave::root-suite) test)))
      (expect (cl-weave::test-event-status event) :to-be :todo)
      (expect (cl-weave::test-event-reason event) :to-equal "pending")
      (expect (cl-weave::passed-event-p event) :to-be-truthy)))

  (it "reports todo suite descendants without running hooks or bodies"
    (let* ((root (cl-weave::make-suite :name "root"))
           (suite (cl-weave::add-child
                   root
                   (cl-weave::make-suite
                    :name "pending"
                    :parent root
                    :todo-reason "suite pending"
                    :before-all (list (lambda () (error "before-all should not run")))
                    :after-all (list (lambda () (error "after-all should not run")))
                    :before-each (list (lambda () (error "before-each should not run")))
                    :after-each (list (lambda () (error "after-each should not run")))))))
      (cl-weave::add-child
       suite
       (cl-weave::make-test-case
        :name "case"
        :function (lambda () (error "test body should not run"))))
      (let ((events (cl-weave::collect-events root)))
        (expect (mapcar #'cl-weave::test-event-status events) :to-equal '(:todo))
        (expect (mapcar #'cl-weave::test-event-reason events)
                :to-equal '("suite pending"))
        (expect (mapcar #'cl-weave::test-event-path events)
                :to-equal '(("pending" "case")))))))

(describe "focus"
  (it "runs only focused tests when any focus exists"
    (let* ((root (cl-weave::make-suite :name "root"))
           (suite (cl-weave::add-child
                   root
                   (cl-weave::make-suite :name "focus" :parent root)))
           (events-log nil))
      (cl-weave::add-child
       root
       (cl-weave::make-test-case
        :name "outside"
        :function (lambda () (push :outside events-log))))
      (cl-weave::add-child
       suite
       (cl-weave::make-test-case
        :name "inside"
        :function (lambda () (push :inside events-log))
        :focus t))
      (let ((events (cl-weave::collect-events root)))
        (expect events-log :to-equal '(:inside))
        (expect (mapcar #'cl-weave::test-event-path events)
                :to-equal '(("focus" "inside")))))))

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
      (expect hook-events :to-equal nil))))

(describe "asdf integration"
  (it "collects source files from ASDF systems"
    (let ((files (cl-weave:asdf-system-files "cl-weave" :include-dependencies nil)))
      (expect files :to-satisfy
              (lambda (paths)
                (some (lambda (pathname)
                        (search "src/runner.lisp" (namestring pathname)))
                      paths)))
      (expect files :to-satisfy
              (lambda (paths)
                (some (lambda (pathname)
                        (search "src/watch.lisp" (namestring pathname)))
                      paths)))))

  (it "detects changed file states"
    (let* ((pathname #P"/tmp/cl-weave-watch-state.lisp")
           (old-state (list (cons pathname 1)))
           (new-state (list (cons pathname 2))))
      (expect (cl-weave::changed-pathnames old-state new-state)
              :to-equal (list pathname))
      (expect (cl-weave::changed-pathnames new-state new-state)
              :to-equal nil)))

  (it "runs watch mode once without reloading the active test suite"
    (let ((calls nil)
          (output nil))
      (with-mocked-functions
          (((symbol-function 'cl-weave:run-system)
            (lambda (system &key reporter stream name-filter)
              (declare (ignore stream))
              (push (list system reporter name-filter) calls)
              t)))
        (setf output
              (with-output-to-string (stream)
                (expect (cl-weave:watch-system
                         "cl-weave"
                         :reporter :json
                         :stream stream
                         :status-stream stream
                         :name-filter "expect"
                         :once t)
                        :to-be-truthy))))
      (expect calls :to-equal '(("cl-weave" :json "expect")))
      (expect output :to-contain "cl-weave watch"))))

(describe "mocking"
  (it "restores symbol functions"
    (expect (sample-size '(a b c)) :to-be 3)
    (with-mocked-functions (((symbol-function 'sample-size)
                             (lambda (value)
                               (declare (ignore value))
                               99)))
      (expect (sample-size '(a b c)) :to-be 99))
    (expect (sample-size '(a b c)) :to-be 3))

  (it "records mock function calls"
    (let ((mock (make-mock-function (lambda (left right)
                                      (+ left right)))))
      (expect (funcall mock 1 2) :to-be 3)
      (expect (funcall mock 5 8) :to-be 13)
      (expect mock :to-have-been-called)
      (expect mock :to-have-been-called-times 2)
      (expect mock :to-have-been-called-with 1 2)
      (expect (mock-calls mock) :to-equal '((1 2) (5 8)))
      (clear-mock mock)
      (expect mock :not :to-have-been-called)
      (expect (mock-calls mock) :to-equal nil))))

(describe "reporters"
  (it "prints AI-readable S-expression results"
    (let ((output (with-output-to-string (stream)
                      (cl-weave::report-sexp
                      (list (cl-weave::make-test-event
                             :status :pass
                             :path '("reporters" "prints")
                             :elapsed-internal-time 0)
                            (cl-weave::make-test-event
                             :status :skip
                             :path '("reporters" "skips")
                             :reason "example"
                             :elapsed-internal-time 0)
                            (cl-weave::make-test-event
                             :status :todo
                             :path '("reporters" "todos")
                             :reason "pending"
                             :elapsed-internal-time 0))
                      stream))))
      (expect output :to-contain ":CL-WEAVE/RESULTS")
      (expect output :to-contain ":SCHEMA-VERSION 2")
      (expect output :to-contain ":SKIPPED")
      (expect output :to-contain ":TODOS")
      (expect output :to-contain ":TODO")))

  (it "prints AI-readable JSON results"
    (let ((output (with-output-to-string (stream)
                    (cl-weave::report-json
                     (list (cl-weave::make-test-event
                            :status :pass
                            :path '("reporters" "json")
                            :elapsed-internal-time 0)
                           (cl-weave::make-test-event
                            :status :skip
                            :path '("reporters" "quotes")
                            :reason "needs \"escaping\""
                            :elapsed-internal-time 0))
                     stream))))
      (expect output :to-contain "\"schemaVersion\":2")
      (expect output :to-contain "\"passed\":1")
      (expect output :to-contain "\"skipped\":1")
      (expect output :to-contain "\"status\":\"pass\"")
      (expect output :to-contain "\"path\":[\"reporters\",\"json\"]")
      (expect output :to-contain "\"pathString\":\"reporters > json\"")
      (expect output :to-contain "\"durationMs\":0.000")
      (expect output :to-contain "\"reason\":\"needs \\\"escaping\\\"\"")
      (expect output :to-contain "\"assertion\":null")))

  (it "prints CI-readable JUnit XML results"
    (let ((output (with-output-to-string (stream)
                    (cl-weave::report-junit
                     (list (cl-weave::make-test-event
                            :status :pass
                            :path '("reporters" "passes")
                            :elapsed-internal-time 0)
                           (cl-weave::make-test-event
                            :status :skip
                            :path '("reporters" "skips")
                            :reason "needs <thing>"
                            :elapsed-internal-time 0)
                           (cl-weave::make-test-event
                            :status :todo
                            :path '("reporters" "todos")
                            :reason "pending"
                            :elapsed-internal-time 0)
                           (cl-weave::make-test-event
                            :status :fail
                            :path '("reporters" "fails")
                            :reason "bad <value> & reason"
                            :elapsed-internal-time 0))
                     stream))))
      (expect output :to-contain "<?xml version=\"1.0\" encoding=\"UTF-8\"?>")
      (expect output :to-contain "<testsuite name=\"cl-weave\" tests=\"4\"")
      (expect output :to-contain "failures=\"1\"")
      (expect output :to-contain "errors=\"0\"")
      (expect output :to-contain "skipped=\"2\"")
      (expect output :to-contain "<skipped message=\"needs &lt;thing&gt;\"/>")
      (expect output :to-contain "<skipped message=\"TODO: pending\"/>")
      (expect output :to-contain "<failure message=\"bad &lt;value&gt; &amp; reason\">"))))
