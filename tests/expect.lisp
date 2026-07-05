(in-package #:cl-weave/tests)

(describe "expect"
  (matcher-pass-cases
    ("to-be" (expect 2 :to-be 2))
    ("to-equal" (expect (list :a 1) :to-equal (list :a 1)))
    ("to-equalp" (expect "ok" :to-equalp "OK"))
    ("to-be-truthy" (expect :value :to-be-truthy))
    ("to-be-falsy" (expect nil :to-be-falsy))
    ("to-be-null" (expect nil :to-be-null))
    ("to-be-defined" (expect :value :to-be-defined))
    ("expect.assertions"
     (progn
       (expect.assertions 2)
       (expect :a :to-be :a)
       (expect-not nil :to-be t)))
    ("expect.hasassertions"
     (progn
       (expect.hasassertions)
       (expect t)))
    #+sbcl
    ("to-be-nan" (expect (quiet-nan) :to-be-nan))
    ("to-be-one-of list" (expect :ready :to-be-one-of '(:pending :ready :done)))
    ("to-be-one-of vector" (expect 2 :to-be-one-of #(1 2 3)))
    ("to-be-one-of hash-table values"
     (let ((table (make-hash-table :test #'equal)))
       (setf (gethash "first" table) :pending
             (gethash "second" table) :ready)
       (expect :ready :to-be-one-of table)))
    ("to-be-one-of failure payload"
     (handler-case
         (progn
           (expect :blocked :to-be-one-of '(:pending :ready :done))
           (error "Expected :to-be-one-of to fail."))
       (cl-weave:assertion-failure (condition)
         (let* ((detail (cl-weave::failure-detail condition))
                (actual (cl-weave::assertion-detail-actual detail))
                (expected (cl-weave::assertion-detail-expected detail)))
           (expect (cl-weave::assertion-detail-matcher detail) :to-be :to-be-one-of)
           (expect (getf actual :value) :to-be :blocked)
           (expect (getf actual :candidates) :to-equal '(:pending :ready :done))
           (expect (getf actual :test) :to-be 'eql)
           (expect (getf actual :candidate-count) :to-be 3)
           (expect (getf actual :matched-index) :to-be-null)
           (expect (getf expected :candidates) :to-equal '(:pending :ready :done))
           (expect (getf expected :test) :to-be 'eql)
           (expect (getf expected :candidate-count) :to-be 3)))))
    ("to-be-nan failure payload"
     (handler-case
         (progn
           (expect 42 :to-be-nan)
           (error "Expected :to-be-nan to fail."))
       (cl-weave:assertion-failure (condition)
         (let* ((detail (cl-weave::failure-detail condition))
                (actual (cl-weave::assertion-detail-actual detail))
                (expected (cl-weave::assertion-detail-expected detail)))
           (expect (cl-weave::assertion-detail-matcher detail) :to-be :to-be-nan)
           (expect (getf actual :value) :to-be 42)
           (expect (getf actual :float) :to-be-falsy)
           (expect (getf actual :nan) :to-be-falsy)
           (expect (getf expected :predicate) :to-be :nan)
           (expect (getf expected :test) :to-be :float-nan-p)))))
    ("to-satisfy" (expect 4 :to-satisfy #'evenp))
    ("to-be-type-of" (expect 10 :to-be-type-of 'integer))
    ("to-be-instance-of"
     (expect (make-instance 'sample-widget) :to-be-instance-of 'sample-widget))
    ("to-contain list" (expect '(:a :b :c) :to-contain :b))
    ("to-contain vector" (expect #(:a :b :c) :to-contain :b))
    ("to-contain string" (expect "common-lisp" :to-contain "lisp"))
    ("to-contain-equal list"
     (expect '((:id 1 :name "Ada") (:id 2 :name "Grace"))
             :to-contain-equal
             '(:id 1 :name "Ada")))
    ("to-contain-equal vector"
     (expect #((:id 1 :roles ("dev")) (:id 2 :roles ("ops")))
             :to-contain-equal
             '(:id 2 :roles ("ops"))))
    ("to-contain-equal hash-table values"
     (let ((table (make-hash-table :test #'equal)))
       (setf (gethash "user" table) '(:name "Ada" :roles ("dev")))
       (expect table :to-contain-equal '(:name "Ada" :roles ("dev")))))
    ("to-match substring"
     (expect "common-lisp" :to-match "lisp"))
    ("to-match predicate"
     (expect "Common Lisp"
             :to-match
             (lambda (text)
               (search "Lisp" text))))
    ("to-match failure payload"
     (handler-case
         (progn
           (expect "common-lisp" :to-match "scheme")
           (error "Expected :to-match to fail."))
       (cl-weave:assertion-failure (condition)
         (let* ((detail (cl-weave::failure-detail condition))
                (actual (cl-weave::assertion-detail-actual detail))
                (expected (cl-weave::assertion-detail-expected detail)))
           (expect (cl-weave::assertion-detail-matcher detail) :to-be :to-match)
           (expect (getf actual :value) :to-equal "common-lisp")
           (expect (getf actual :pattern) :to-equal "scheme")
           (expect (getf actual :mode) :to-be :substring)
           (expect (getf actual :reason) :to-be :no-match)
           (expect (getf expected :pattern) :to-equal "scheme")
           (expect (getf expected :test) :to-be :substring)))))
    ("to-match-object plist subset"
     (expect '(:id 1 :name "Ada" :roles ("dev" "ops"))
             :to-match-object
             '(:name "Ada")))
    ("to-match-object nested plist subset"
     (expect '(:user (:id 1 :profile (:name "Ada" :active t)) :meta :ignored)
             :to-match-object
             '(:user (:profile (:active t)))))
    ("to-match-object vector exact shape"
     (expect #((:id 1 :name "Ada") (:id 2 :name "Grace" :role "compiler"))
             :to-match-object
             #((:id 1) (:role "compiler"))))
    ("to-match-object hash-table subset"
     (let ((table (make-hash-table :test #'equal)))
       (setf (gethash "user" table) '(:name "Ada" :roles #("dev" "ops")))
       (expect table :to-match-object '(("user" . (:roles #("dev" "ops")))))))
    ("to-match-object slot subset"
     (expect (make-instance 'sample-widget :name "Ada" :state :ready)
             :to-match-object
             '((name . "Ada") (state . :ready))))
    ("to-have-length list" (expect '(:a :b :c) :to-have-length 3))
    ("to-have-length vector" (expect #(:a :b :c) :to-have-length 3))
    ("to-have-length string" (expect "abc" :to-have-length 3))
    ("to-have-property plist"
     (expect '(:user (:name "Ada" :roles #("dev" "ops")))
             :to-have-property
             '(:user :name)
             "Ada"))
    ("to-have-property alist"
     (expect '((:user . ((:name . "Ada"))))
             :to-have-property
             '(:user :name)
             "Ada"))
    ("to-have-property hash-table"
     (let ((table (make-hash-table :test #'equal)))
       (setf (gethash "user" table) '(:name "Ada"))
       (expect table :to-have-property #("user" :name) "Ada")))
    ("to-have-property slot"
     (expect (make-instance 'sample-widget :name "Ada")
             :to-have-property
             'name
             "Ada"))
    ("to-have-property sequence index"
     (expect '(:users #("Ada" "Grace"))
             :to-have-property
             '(:users 1)
             "Grace"))
    ("to-be-close-to default digits" (expect 304/1000 :to-be-close-to 3/10))
    ("to-be-close-to explicit digits" (expect (+ 0.1d0 0.2d0) :to-be-close-to 0.3d0 5))
    ("to-be-greater-than" (expect 10 :to-be-greater-than 9))
    ("to-be-greater-than-or-equal" (expect 10 :to-be-greater-than-or-equal 10))
    ("to-be-less-than" (expect 9 :to-be-less-than 10))
    ("to-be-less-than-or-equal" (expect 10 :to-be-less-than-or-equal 10))
    ("to-throw" (expect (lambda () (error "boom")) :to-throw))
    ("to-throw condition type"
     (expect (lambda () (error "typed boom")) :to-throw 'simple-error))
    ("to-throw message substring"
     (expect (lambda () (error "needle in haystack")) :to-throw "needle"))
    ("to-throw predicate"
     (expect (lambda () (error "predicate boom"))
             :to-throw
             (lambda (condition)
               (search "predicate" (princ-to-string condition)))))
    ("expect.resolves" (expect.resolves (lambda () 42) :to-be 42))
    ("expect.rejects condition type"
     (expect.rejects (lambda () (error "missing user")) :to-be-type-of 'simple-error))
    ("expect.resolves rejected thunk payload"
     (handler-case
         (progn
           (expect.resolves (lambda () (error "boom")) :to-be :ok)
           (error "Expected expect.resolves to fail."))
       (cl-weave:assertion-failure (condition)
         (let* ((detail (cl-weave::failure-detail condition))
                (actual (cl-weave::assertion-detail-actual detail))
                (expected (cl-weave::assertion-detail-expected detail)))
           (expect (cl-weave::assertion-detail-matcher detail) :to-be :resolves)
           (expect (getf actual :state) :to-be :rejected)
           (expect (getf actual :condition-type) :to-be 'simple-error)
           (expect (getf actual :message) :to-match "boom")
           (expect expected :to-equal '(:state :resolved))))))
    ("expect.rejects resolved thunk payload"
     (handler-case
         (progn
           (expect.rejects (lambda () :ok) :to-be-type-of 'simple-error)
           (error "Expected expect.rejects to fail."))
       (cl-weave:assertion-failure (condition)
         (let* ((detail (cl-weave::failure-detail condition))
                (actual (cl-weave::assertion-detail-actual detail))
                (expected (cl-weave::assertion-detail-expected detail)))
           (expect (cl-weave::assertion-detail-matcher detail) :to-be :rejects)
           (expect (getf actual :state) :to-be :resolved)
           (expect (getf actual :value) :to-be :ok)
           (expect expected :to-equal '(:state :rejected))))))
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
     (let ((cl-weave::*snapshot-directory* (test-snapshot-directory "cl-weave-core-snapshots"))
           (cl-weave::*snapshot-file-name* "matchers.snapshots"))
       (cl-weave:with-snapshot-updates
         (expect '(:ok 42) :to-match-snapshot "matcher external snapshot"))
       (expect '(:ok 42) :to-match-snapshot "matcher external snapshot")))
    ("to-match-snapshot rejects missing snapshots"
     (let ((cl-weave::*snapshot-directory* (test-snapshot-directory "cl-weave-core-snapshots"))
           (cl-weave::*snapshot-file-name* "missing.snapshots")
           (key (symbol-name (gensym "MISSING-SNAPSHOT-"))))
       (expect (lambda ()
                 (expect '(:missing 42) :to-match-snapshot key))
               :to-throw)))
    ("not" (expect 1 :not :to-be 2))
    ("expect-not" (expect-not 1 :to-be 2))
    ("expect.extend matcher" (expect 5 :to-be-odd))
    ("extend-expect matcher" (expect 5 :to-be-between 1 10)))

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

  (it "reports contain-equal matcher failures with structured data"
    (handler-case
        (progn
          (expect '((:id 1 :name "Ada"))
                  :to-contain-equal
                  '(:id 2 :name "Grace"))
          (expect nil :to-be-truthy))
      (cl-weave:assertion-failure (condition)
        (let* ((detail (cl-weave::failure-detail condition))
               (actual (cl-weave::assertion-detail-actual detail))
               (expected (cl-weave::assertion-detail-expected detail)))
          (expect (cl-weave::assertion-detail-matcher detail) :to-be :to-contain-equal)
          (expect (getf actual :container) :to-equal '((:id 1 :name "Ada")))
          (expect (getf actual :value) :to-equal '(:id 2 :name "Grace"))
          (expect (getf actual :test) :to-be :equalp)
          (expect (getf expected :value) :to-equal '(:id 2 :name "Grace"))
          (expect (getf expected :test) :to-be :equalp)))))

  (it "reports match-object matcher failures with structured path data"
    (handler-case
        (progn
          (expect '(:user (:name "Ada" :roles #("dev")))
                  :to-match-object
                  '(:user (:name "Grace")))
          (expect nil :to-be-truthy))
      (cl-weave:assertion-failure (condition)
        (let* ((detail (cl-weave::failure-detail condition))
               (actual (cl-weave::assertion-detail-actual detail))
               (expected (cl-weave::assertion-detail-expected detail))
               (failure (getf actual :failure)))
          (expect (cl-weave::assertion-detail-matcher detail) :to-be :to-match-object)
          (expect (getf actual :subset) :to-equal '(:user (:name "Grace")))
          (expect (getf failure :path) :to-equal '(:user :name))
          (expect (getf failure :reason) :to-be :value-mismatch)
          (expect (getf failure :actual-value) :to-equal "Ada")
          (expect (getf failure :expected-value) :to-equal "Grace")
          (expect (getf failure :test) :to-be :equalp)
          (expect (getf expected :subset) :to-equal '(:user (:name "Grace")))
          (expect (getf expected :test) :to-be :partial-equalp)))))

  (it "reports property matcher failures with structured path data"
    (handler-case
        (progn
          (expect '(:user (:name "Ada"))
                  :to-have-property
                  '(:user :age)
                  37)
          (expect nil :to-be-truthy))
      (cl-weave:assertion-failure (condition)
        (let* ((detail (cl-weave::failure-detail condition))
               (actual (cl-weave::assertion-detail-actual detail))
               (expected (cl-weave::assertion-detail-expected detail)))
          (expect (cl-weave::assertion-detail-matcher detail) :to-be :to-have-property)
          (expect (getf actual :path) :to-equal '(:user :age))
          (expect (getf actual :present) :to-be nil)
          (expect (getf expected :path) :to-equal '(:user :age))
          (expect (getf expected :value) :to-be 37)))))

  (it "reports close-to matcher failures with structured numeric data"
    (handler-case
        (progn
          (expect 31/100 :to-be-close-to 3/10 2)
          (expect nil :to-be-truthy))
      (cl-weave:assertion-failure (condition)
        (let* ((detail (cl-weave::failure-detail condition))
               (actual (cl-weave::assertion-detail-actual detail))
               (expected (cl-weave::assertion-detail-expected detail)))
          (expect (cl-weave::assertion-detail-matcher detail) :to-be :to-be-close-to)
          (expect (getf actual :value) :to-be 31/100)
          (expect (getf actual :expected-value) :to-be 3/10)
          (expect (getf actual :num-digits) :to-be 2)
          (expect (getf actual :difference) :to-be 1/100)
          (expect (getf actual :threshold) :to-be 1/200)
          (expect (getf expected :value) :to-be 3/10)
          (expect (getf expected :num-digits) :to-be 2)
          (expect (getf expected :threshold) :to-be 1/200)))))

  (it "reports comparison matcher failures with structured numeric data"
    (handler-case
        (progn
          (expect "10" :to-be-greater-than 9)
          (expect nil :to-be-truthy))
      (cl-weave:assertion-failure (condition)
        (let* ((detail (cl-weave::failure-detail condition))
               (actual (cl-weave::assertion-detail-actual detail))
               (expected (cl-weave::assertion-detail-expected detail)))
          (expect (cl-weave::assertion-detail-matcher detail) :to-be :to-be-greater-than)
          (expect (getf actual :value) :to-equal "10")
          (expect (getf actual :expected-value) :to-be 9)
          (expect (getf actual :matcher) :to-be :to-be-greater-than)
          (expect (getf actual :operator) :to-be '>)
          (expect (getf actual :actual-real) :to-be-falsy)
          (expect (getf actual :expected-real) :to-be-truthy)
          (expect (getf expected :value) :to-be 9)
          (expect (getf expected :matcher) :to-be :to-be-greater-than)
          (expect (getf expected :operator) :to-be '>)))))

  (it "signals negated matcher failures with structured data"
    (handler-case
        (progn
          (expect-not 1 :to-be 1)
          (expect nil :to-be-truthy))
      (cl-weave:assertion-failure (condition)
        (let ((detail (cl-weave::failure-detail condition)))
          (expect (cl-weave::assertion-detail-matcher detail) :to-be :to-be)
          (expect (cl-weave::assertion-detail-actual detail) :to-be 1)
          (expect (cl-weave::assertion-detail-expected detail) :to-equal '(1))
          (expect (cl-weave::assertion-detail-negated detail) :to-be-truthy)
          (expect (cl-weave::assertion-detail-pass detail) :to-be-truthy)))))

  (it "reports to-throw failures with structured condition data"
    (handler-case
        (progn
          (expect (lambda () (error "wrong message")) :to-throw "needle")
          (expect nil :to-be-truthy))
      (cl-weave:assertion-failure (condition)
        (let* ((detail (cl-weave::failure-detail condition))
               (actual (cl-weave::assertion-detail-actual detail))
               (expected (cl-weave::assertion-detail-expected detail)))
          (expect (cl-weave::assertion-detail-matcher detail) :to-be :to-throw)
          (expect (getf actual :threw) :to-be-truthy)
          (expect (getf actual :condition-type) :to-be 'simple-error)
          (expect (getf actual :message) :to-contain "wrong message")
          (expect (getf expected :matcher) :to-be :message-substring)
          (expect (getf expected :value) :to-equal "needle")))))

  (it "reports to-throw missing conditions with structured data"
    (handler-case
        (progn
          (expect (lambda () :ok) :to-throw 'simple-error)
          (expect nil :to-be-truthy))
      (cl-weave:assertion-failure (condition)
        (let* ((detail (cl-weave::failure-detail condition))
               (actual (cl-weave::assertion-detail-actual detail))
               (expected (cl-weave::assertion-detail-expected detail)))
          (expect (cl-weave::assertion-detail-matcher detail) :to-be :to-throw)
          (expect (getf actual :threw) :to-be nil)
          (expect (getf actual :condition-type) :to-be nil)
          (expect (getf actual :message) :to-be nil)
          (expect (getf expected :matcher) :to-be :condition-type)
          (expect (getf expected :value) :to-be 'simple-error)))))

  (it "reports missing external snapshots as structured data"
    (let ((cl-weave::*snapshot-directory* (test-snapshot-directory "cl-weave-core-snapshots"))
          (cl-weave::*snapshot-file-name* "missing-structured.snapshots")
          (key (symbol-name (gensym "MISSING-STRUCTURED-SNAPSHOT-"))))
      (handler-case
          (progn
            (expect '(:missing 42) :to-match-snapshot key)
            (expect nil :to-be-truthy))
        (cl-weave:assertion-failure (condition)
          (let* ((detail (cl-weave::failure-detail condition))
                 (actual (cl-weave::assertion-detail-actual detail))
                 (expected (cl-weave::assertion-detail-expected detail)))
            (expect (cl-weave::assertion-detail-matcher detail) :to-be :to-match-snapshot)
            (expect (getf actual :snapshot-key) :to-equal key)
            (expect (getf actual :snapshot-file) :to-contain "missing-structured.snapshots")
            (expect (getf actual :value) :to-equal "(:missing 42)")
            (expect (getf actual :reason) :to-be :missing-snapshot)
            (expect (getf expected :snapshot-key) :to-equal key)
            (expect (getf expected :present) :to-be nil)
            (expect (getf expected :reason) :to-be :missing-snapshot))))))

  (it "reports external snapshot mismatches with first-difference data"
    (let ((cl-weave::*snapshot-directory* (test-snapshot-directory "cl-weave-core-snapshots"))
          (cl-weave::*snapshot-file-name* "mismatch-structured.snapshots")
          (key (symbol-name (gensym "MISMATCH-STRUCTURED-SNAPSHOT-"))))
      (cl-weave:with-snapshot-updates
        (expect '(:ok 42) :to-match-snapshot key))
      (handler-case
          (progn
            (expect '(:ok 43) :to-match-snapshot key)
            (expect nil :to-be-truthy))
        (cl-weave:assertion-failure (condition)
          (let* ((detail (cl-weave::failure-detail condition))
                 (actual (cl-weave::assertion-detail-actual detail))
                 (expected (cl-weave::assertion-detail-expected detail))
                 (difference (getf actual :difference)))
            (expect (cl-weave::assertion-detail-matcher detail) :to-be :to-match-snapshot)
            (expect (getf actual :snapshot-key) :to-equal key)
            (expect (getf actual :reason) :to-be :snapshot-mismatch)
            (expect (getf actual :value) :to-equal "(:ok 43)")
            (expect (getf expected :present) :to-be-truthy)
            (expect (getf expected :value) :to-equal "(:ok 42)")
            (expect difference :to-equal (getf expected :difference))
            (expect (getf difference :line) :to-be 1)
            (expect (getf difference :expected) :to-equal "(:ok 42)")
            (expect (getf difference :actual) :to-equal "(:ok 43)"))))))

  (it "supports public custom matchers with structured failure data"
    (expect 4 :to-be-even)
    (handler-case
        (progn
          (expect 5 :to-be-even)
          (expect nil :to-be-truthy))
      (cl-weave:assertion-failure (condition)
        (let ((detail (cl-weave::failure-detail condition)))
          (expect (cl-weave::assertion-detail-matcher detail) :to-be :to-be-even)
          (expect (cl-weave::assertion-detail-actual detail)
                  :to-equal '(:value 5 :parity :odd))
          (expect (cl-weave::assertion-detail-expected detail)
                  :to-equal '(:parity :even))))))

  (it "supports Vitest-style expect.extend custom matchers"
    (expect 7 :to-be-odd)
    (handler-case
        (progn
          (expect 8 :to-be-odd)
          (expect nil :to-be-truthy))
      (cl-weave:assertion-failure (condition)
        (let ((detail (cl-weave::failure-detail condition)))
          (expect (cl-weave::assertion-detail-matcher detail) :to-be :to-be-odd)
          (expect (cl-weave::assertion-detail-actual detail)
                  :to-equal '(:value 8 :parity :even))
          (expect (cl-weave::assertion-detail-expected detail)
                  :to-equal '(:parity :odd))))))

  (it "supports data-driven extend-expect custom matchers"
    (expect 5 :to-be-between 1 10)
    (handler-case
        (progn
          (expect 11 :to-be-between 1 10)
          (expect nil :to-be-truthy))
      (cl-weave:assertion-failure (condition)
        (let ((detail (cl-weave::failure-detail condition)))
          (expect (cl-weave::assertion-detail-matcher detail) :to-be :to-be-between)
          (expect (cl-weave::assertion-detail-actual detail)
                  :to-equal '(:value 11 :range (1 10)))
          (expect (cl-weave::assertion-detail-expected detail)
                  :to-equal '(:range (1 10)))))))

  (it "exposes stable matcher metadata for AI tooling"
    (let* ((metadata (cl-weave:list-matchers))
           (names (mapcar (lambda (entry) (getf entry :name)) metadata))
           (sorted-names (sort (copy-list names) #'string< :key #'symbol-name))
           (even (cl-weave:matcher-metadata :to-be-even))
           (odd (cl-weave:matcher-metadata :to-be-odd))
           (between (cl-weave:matcher-metadata :to-be-between)))
      (expect names :to-equal sorted-names)
      (expect names :to-contain :to-be)
      (expect even :to-equal
              '(:name :to-be-even
                :description "Passes when ACTUAL is an even integer."))
      (expect odd :to-equal
              '(:name :to-be-odd
                :description "Passes when ACTUAL is an odd integer."))
      (expect between :to-equal
              '(:name :to-be-between
                :description "Passes when ACTUAL is within the inclusive numeric range."))))

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

