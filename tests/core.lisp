(in-package #:cl-weave/tests)

(cl-weave:clear-tests)

(defun ensure-directory-suffix (value)
  (let ((string (namestring (pathname value))))
    (if (and (plusp (length string))
             (char= (char string (1- (length string))) #\/))
        string
        (concatenate 'string string "/"))))

(defun test-snapshot-directory (name)
  (merge-pathnames
   (make-pathname :directory (list :relative name))
   (let ((tmp #+sbcl (sb-ext:posix-getenv "TMPDIR")
              #-sbcl nil))
     (if (and tmp (plusp (length tmp)))
         (pathname (ensure-directory-suffix tmp))
         #P"./"))))

(defun test-temporary-pathname (name)
  (merge-pathnames
   name
   (let ((tmp #+sbcl (sb-ext:posix-getenv "TMPDIR")
              #-sbcl nil))
     (if (and tmp (plusp (length tmp)))
         (pathname (ensure-directory-suffix tmp))
         #P"./"))))

(defun read-text-file (pathname)
  (with-open-file (stream pathname :direction :input)
    (let ((contents (make-string (file-length stream))))
      (read-sequence contents stream)
      contents)))

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

(defmacro expect-macroexpands-through (form canonical-symbol)
  `(expect (macroexpand-1 ',form)
           :to-satisfy
           (lambda (expanded)
             (tree-contains-p expanded ',canonical-symbol))))

(defun tree-depth (tree)
  (if (consp tree)
      (1+ (reduce #'max tree :key #'tree-depth :initial-value 0))
      0))

(defmatcher :to-be-even (actual expected)
  (declare (ignore expected))
  (values (and (integerp actual) (evenp actual))
          `(:value ,actual :parity ,(if (and (integerp actual) (evenp actual))
                                        :even
                                        :odd))
          '(:parity :even)))

(expect.extend
  (:to-be-odd (actual expected)
    (declare (ignore expected))
    (values (and (integerp actual) (oddp actual))
            `(:value ,actual :parity ,(if (and (integerp actual) (oddp actual))
                                          :odd
                                          :even))
            '(:parity :odd))))

(extend-expect
 (list
  (list :to-be-between
        (lambda (actual expected)
          (destructuring-bind (low high) expected
            (values (and (realp actual) (<= low actual high))
                    `(:value ,actual :range (,low ,high))
                    `(:range (,low ,high))))))))

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

  (describe.each ((4 5 9))
      "dot table suite ~A plus ~A"
      (left right total)
    (beforeEach
      (setf (gethash :dot-table-total *test-context*) total))
    (it.each ((:alpha :alpha)
              (:beta :beta))
        "runs dot generated case ~A"
        (actual expected)
      (expect actual :to-be expected)
      (expect (+ left right) :to-be total)
      (expect (gethash :dot-table-total *test-context*) :to-be total)))

  (it "expands expect into the assertion engine"
    (expect (macroexpand-1 '(expect (+ 1 1) :to-be 2))
            :to-satisfy
            (lambda (form)
              (tree-contains-p form 'cl-weave::assert-expectation))))

  (it "expands expect-not into a negated matcher assertion"
    (expect (macroexpand-1 '(expect-not (+ 1 1) :to-be 3))
            :to-satisfy
            (lambda (form)
              (and (tree-contains-p form 'cl-weave::assert-expectation)
                   (tree-contains-p form :not)
                   (tree-contains-p form 'expect-not)))))

  (it "expands expect.extend into the custom matcher registry"
    (expect (macroexpand-1
             '(expect.extend
               (:to-be-small (actual expected)
                 (declare (ignore expected))
                 (< actual 10))))
            :to-satisfy
            (lambda (form)
              (and (tree-contains-p form 'expect-extend)
                   (tree-contains-p form :to-be-small)))))

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
             '(it "eventually stable" (:retry 2 :timeout-ms 100 :concurrent t)
                (expect :ok :to-be :ok)))
            :to-satisfy
            (lambda (form)
              (and (tree-contains-p form 'cl-weave::register-test)
                   (tree-contains-p form :retry)
                   (tree-contains-p form 2)
                   (tree-contains-p form :timeout-ms)
                   (tree-contains-p form 100)
                   (tree-contains-p form :execution-mode)
                   (tree-contains-p form :concurrent)))))

  (it "expands false concurrent option into sequential execution metadata"
    (expect (macroexpand-1
             '(it "generated sequential case" (:concurrent nil)
                (expect :ok :to-be :ok)))
            :to-satisfy
            (lambda (form)
              (and (tree-contains-p form 'cl-weave::register-test)
                   (tree-contains-p form :execution-mode)
                   (tree-contains-p form :sequential)))))

  (it "expands it-concurrent into concurrent test registration"
    (expect (macroexpand-1
             '(it-concurrent "parallel case" (:retry 1)
                (expect :ok :to-be :ok)))
            :to-satisfy
            (lambda (form)
              (and (tree-contains-p form 'cl-weave::register-test)
                   (tree-contains-p form :execution-mode)
                   (tree-contains-p form :concurrent)
                   (tree-contains-p form :retry)))))

  (it "expands it-sequential into sequential test registration"
    (expect (macroexpand-1
             '(it-sequential "serial case" (:retry 1)
                (expect :ok :to-be :ok)))
            :to-satisfy
            (lambda (form)
              (and (tree-contains-p form 'cl-weave::register-test)
                   (tree-contains-p form :execution-mode)
                   (tree-contains-p form :sequential)
                   (tree-contains-p form :retry)))))

  (it "expands it-fails into expected-failure registration"
    (expect (macroexpand-1
             '(it-fails "known bug" (:retry 1 :timeout-ms 100)
                (expect 1 :to-be 2)))
            :to-satisfy
            (lambda (form)
              (and (tree-contains-p form 'cl-weave::register-test)
                   (tree-contains-p form :expected-failure-reason)
                   (tree-contains-p form :retry)
                   (tree-contains-p form :timeout-ms)))))

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

  (it "expands describe execution mode macros into suite metadata"
    (expect (macroexpand-1
             '(describe-concurrent "parallel suite"
                (it "case" (expect 1 :to-be 1))))
            :to-satisfy
            (lambda (form)
              (and (tree-contains-p form 'cl-weave::register-suite)
                   (tree-contains-p form :execution-mode)
                   (tree-contains-p form :concurrent))))
    (expect (macroexpand-1
             '(describe-sequential "serial suite"
                (it "case" (expect 1 :to-be 1))))
            :to-satisfy
            (lambda (form)
              (and (tree-contains-p form 'cl-weave::register-suite)
                   (tree-contains-p form :execution-mode)
                   (tree-contains-p form :sequential)))))

  (it "expands conditional test registration into run and skip branches"
    (expect (macroexpand-1
             '(it-skip-if expensivep
                  "conditional case"
                (:retry 2 :timeout-ms 100)
                (expect :ok :to-be :ok)))
            :to-satisfy
            (lambda (form)
              (and (tree-contains-p form 'if)
                   (tree-contains-p form 'it-skip)
                   (tree-contains-p form 'it)
                   (tree-contains-p form :retry)
                   (tree-contains-p form :timeout-ms)))))

  (it "expands conditional suite registration into run and skip branches"
    (expect (macroexpand-1
             '(describe-run-if
                  (member :sbcl *features*)
                  "conditional suite"
                (it "case" (expect :ok :to-be :ok))))
            :to-satisfy
            (lambda (form)
              (and (tree-contains-p form 'if)
                   (tree-contains-p form 'describe)
                   (tree-contains-p form 'describe-skip)
                   (tree-contains-p form "conditional run-if")))))

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

  (test "runs the Vitest test alias as a first-class case"
    (expect (+ 2 2) :to-be 4))

  (it "expands Vitest dot aliases through canonical macros"
    (expect-macroexpands-through
     (test "base alias" (expect :ok :to-be :ok))
     cl-weave:it)
    (expect-macroexpands-through
     (it.concurrent "parallel alias" (expect :ok :to-be :ok))
     cl-weave:it-concurrent)
    (expect-macroexpands-through
     (it.each ((1 2 3))
         "adds ~A and ~A"
         (left right total)
       (expect (+ left right) :to-be total))
     cl-weave:it-each)
    (expect-macroexpands-through
     (it.only.each ((1 2 3))
         "focused ~A and ~A"
         (left right total)
       (expect (+ left right) :to-be total))
     cl-weave:it-only-each)
    (expect-macroexpands-through
     (it.concurrent.each ((1 2 3))
         "parallel ~A and ~A"
         (left right total)
       (expect (+ left right) :to-be total))
     cl-weave:it-concurrent-each)
    (expect-macroexpands-through
     (it.sequential.each ((1 2 3))
         "serial ~A and ~A"
         (left right total)
       (expect (+ left right) :to-be total))
     cl-weave:it-sequential-each)
    (expect-macroexpands-through
     (it.fails "expected failure alias" (expect :ok :to-be :not-ok))
     cl-weave:it-fails)
    (expect-macroexpands-through
     (it.fails.each ((1 2 4))
         "expected failure ~A and ~A"
         (left right total)
       (expect (+ left right) :to-be total))
     cl-weave:it-fails-each)
    (expect-macroexpands-through
     (it.only "focused alias" (expect :ok :to-be :ok))
     cl-weave:it-only)
    (expect-macroexpands-through
     (it.run-if t "conditional alias" (expect :ok :to-be :ok))
     cl-weave:it-run-if)
    (expect-macroexpands-through
     (it.sequential "serial alias" (expect :ok :to-be :ok))
     cl-weave:it-sequential)
    (expect-macroexpands-through
     (it.skip "skipped alias" "because")
     cl-weave:it-skip)
    (expect-macroexpands-through
     (it.skip.each ((1 2 3))
         "skipped ~A and ~A"
         (left right total)
       "because"
       (expect (+ left right) :to-be total))
     cl-weave:it-skip-each)
    (expect-macroexpands-through
     (it.skip-if t "conditional skip alias" (expect :ok :to-be :ok))
     cl-weave:it-skip-if)
    (expect-macroexpands-through
     (it.todo "todo alias" "later")
     cl-weave:it-todo)
    (expect-macroexpands-through
     (it.isolated "isolated alias"
         (:systems ("cl-weave-tests") :timeout 5)
       (expect :ok :to-be :ok))
     cl-weave:it-isolated)
    (expect-macroexpands-through
     (it.property "property alias"
         ((value (gen-integer :min 0 :max 10)))
       (expect value :to-satisfy #'integerp))
     cl-weave:it-property)
    (expect-macroexpands-through
     (test.concurrent "parallel alias" (expect :ok :to-be :ok))
     cl-weave:test-concurrent)
    (expect-macroexpands-through
     (test.concurrent.each ((1 2 3))
         "parallel alias ~A and ~A"
         (left right total)
       (expect (+ left right) :to-be total))
     cl-weave:test-concurrent-each)
    (expect-macroexpands-through
     (test.fails "expected failure alias" (expect :ok :to-be :not-ok))
     cl-weave:test-fails)
    (expect-macroexpands-through
     (test.fails.each ((1 2 4))
         "expected failure alias ~A and ~A"
         (left right total)
       (expect (+ left right) :to-be total))
     cl-weave:test-fails-each)
    (expect-macroexpands-through
     (test.only "focused alias" (expect :ok :to-be :ok))
     cl-weave:test-only)
    (expect-macroexpands-through
     (test.only.each ((1 2 3))
         "focused alias ~A and ~A"
         (left right total)
       (expect (+ left right) :to-be total))
     cl-weave:test-only-each)
    (expect-macroexpands-through
     (test.run-if t "conditional alias" (expect :ok :to-be :ok))
     cl-weave:test-run-if)
    (expect-macroexpands-through
     (test.sequential "serial alias" (expect :ok :to-be :ok))
     cl-weave:test-sequential)
    (expect-macroexpands-through
     (test.sequential.each ((1 2 3))
         "serial alias ~A and ~A"
         (left right total)
       (expect (+ left right) :to-be total))
     cl-weave:test-sequential-each)
    (expect-macroexpands-through
     (test.skip "skipped alias" "because")
     cl-weave:test-skip)
    (expect-macroexpands-through
     (test.skip.each ((1 2 3))
         "skipped alias ~A and ~A"
         (left right total)
       "because"
       (expect (+ left right) :to-be total))
     cl-weave:test-skip-each)
    (expect-macroexpands-through
     (test.skip-if t "conditional skip alias" (expect :ok :to-be :ok))
     cl-weave:test-skip-if)
    (expect-macroexpands-through
     (test.todo "todo alias" "later")
     cl-weave:test-todo)
    (expect-macroexpands-through
     (test.isolated "isolated alias"
         (:systems ("cl-weave-tests") :timeout 5)
       (expect :ok :to-be :ok))
     cl-weave:test-isolated)
    (expect-macroexpands-through
     (test.property "property alias"
         ((value (gen-integer :min 0 :max 10)))
       (expect value :to-satisfy #'integerp))
     cl-weave:test-property)
    (expect-macroexpands-through
     (describe.concurrent "parallel alias"
       (it "case" (expect :ok :to-be :ok)))
     cl-weave:describe-concurrent)
    (expect-macroexpands-through
     (describe.concurrent.each ((1 2 3))
         "parallel suite ~A and ~A"
         (left right total)
       (it "case" (expect (+ left right) :to-be total)))
     cl-weave:describe-concurrent-each)
    (expect-macroexpands-through
     (describe.sequential "serial alias"
       (it "case" (expect :ok :to-be :ok)))
     cl-weave:describe-sequential)
    (expect-macroexpands-through
     (describe.sequential.each ((1 2 3))
         "serial suite ~A and ~A"
         (left right total)
       (it "case" (expect (+ left right) :to-be total)))
     cl-weave:describe-sequential-each)
    (expect-macroexpands-through
     (describe.only "focused alias"
       (it "case" (expect :ok :to-be :ok)))
     cl-weave:describe-only)
    (expect-macroexpands-through
     (describe.only.each ((1 2 3))
         "focused suite ~A and ~A"
         (left right total)
       (it "case" (expect (+ left right) :to-be total)))
     cl-weave:describe-only-each)
    (expect-macroexpands-through
     (describe.run-if t "conditional suite alias"
       (it "case" (expect :ok :to-be :ok)))
     cl-weave:describe-run-if)
    (expect-macroexpands-through
     (describe.skip "skipped suite alias" "because"
       (it "case" (expect :ok :to-be :ok)))
     cl-weave:describe-skip)
    (expect-macroexpands-through
     (describe.skip.each ((1 2 3))
         "skipped suite ~A and ~A"
         (left right total)
       "because"
       (it "case" (expect (+ left right) :to-be total)))
     cl-weave:describe-skip-each)
    (expect-macroexpands-through
     (describe.skip-if t "conditional skipped suite alias"
       (it "case" (expect :ok :to-be :ok)))
     cl-weave:describe-skip-if)
    (expect-macroexpands-through
     (describe.todo "todo suite alias" "later")
     cl-weave:describe-todo)
    (expect-macroexpands-through
     (beforeAll (setf *fixture-value* :ready))
     cl-weave:before-all)
    (expect-macroexpands-through
     (expect.not 1 :to-be 2)
     cl-weave:expect-not))

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
      (:systems ("cl-weave-tests") :timeout 60)
    (expect (+ 2 3) :to-be 5))

  (it "reports child process failures without failing the parent process"
    (let ((result (run-isolated
                   '(error "child boom")
                   :systems '("cl-weave-tests")
                   :package "CL-WEAVE/TESTS"
                   :timeout 60)))
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
          (expect actual :to-contain :seed)
          (expect actual :to-contain :case-index)
          (expect (getf actual :seed) :to-be 1)
          (expect (getf actual :case-index) :to-be 0)
          (expect actual :to-contain :values)
          (expect actual :to-contain :minimal)))))

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
  (declare (ignore path))
  (when (eq form :enabled)
    (list :disabled)))

(describe "mutation testing"
  (it "collects one-at-a-time form mutations"
    (let ((mutations (collect-mutations '(if (= value 1) (+ value 2) nil))))
      (expect (mapcar #'mutation-operator mutations) :to-contain :comparison-operator)
      (expect (mapcar #'mutation-operator mutations) :to-contain :arithmetic-operator)
      (expect (mapcar #'mutation-operator mutations) :to-contain :boolean-literal)
      (expect (mapcar #'mutation-operator mutations) :to-contain :conditional-branch)
      (expect (mapcar #'mutation-form mutations) :to-contain
              '(if (/= value 1) (+ value 2) nil))
      (expect (mapcar #'mutation-form mutations) :to-contain
              '(if (= value 1) (- value 2) nil))))

  (it "supports macro-defined custom mutation operators"
    (let ((mutations (collect-mutations '(:enabled)
                                        :operators '(:keyword-toggle))))
      (expect (length mutations) :to-be 1)
      (expect (mutation-operator (first mutations)) :to-be :keyword-toggle)
      (expect (mutation-path (first mutations)) :to-equal '(0))
      (expect (mutation-original (first mutations)) :to-be :enabled)
      (expect (mutation-replacement (first mutations)) :to-be :disabled)
      (expect (mutation-form (first mutations)) :to-equal '(:disabled))))

  (it "marks surviving and killed mutants"
    (let* ((results (run-mutations '(+ 1 1)
                                   (lambda (form mutation)
                                     (declare (ignore mutation))
                                     (= (eval form) 2))))
           (summary (mutation-summary results)))
      (expect (mapcar #'mutation-result-status results) :to-contain :killed)
      (expect (getf summary :total) :to-be 1)
      (expect (getf summary :killed) :to-be 1)
      (expect (getf summary :survived) :to-be 0)
      (expect (getf summary :score) :to-be 1.0)))

  (it "keeps unexpected harness errors visible"
    (let* ((results (run-mutations '(+ 1 1)
                                   (lambda (form mutation)
                                     (declare (ignore form mutation))
                                     (error "harness failed"))))
           (summary (mutation-summary results)))
      (expect (mapcar #'mutation-result-status results) :to-contain :errored)
      (expect (getf summary :errored) :to-be 1)))

  (it "prints AI-readable mutation reports"
    (let* ((results (run-mutations '(+ 1 1)
                                   (lambda (form mutation)
                                     (declare (ignore mutation))
                                     (= (eval form) 2))))
           (sexp-output (with-output-to-string (stream)
                          (report-mutations-sexp results stream)))
           (json-output (with-output-to-string (stream)
                          (report-mutations-json results stream))))
      (expect sexp-output :to-contain ":CL-WEAVE/MUTATIONS")
      (expect sexp-output :to-contain ":SCHEMA-VERSION 1")
      (expect sexp-output :to-contain ":OPERATOR :ARITHMETIC-OPERATOR")
      (expect json-output :to-contain "\"kind\":\"mutations\"")
      (expect json-output :to-contain "\"killed\":1")
      (expect json-output :to-contain "\"operator\":\"ARITHMETIC-OPERATOR\""))))

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
    (expect *fixture-events* :to-equal '(:before-each :after-each :before-each :before-all)))

  (it "wraps each test body with around-each continuations"
    (let ((root (cl-weave::make-suite :name "root"))
          (events nil))
      (let ((*fixture-value* :outer)
            (cl-weave::*current-suite* root)
            (cl-weave::*root-suite* root))
        (cl-weave::register-suite
         "around"
         (lambda ()
           (before-each
             (push :before events))
           (around-each (next)
             (push (list :enter *fixture-value*) events)
             (let ((*fixture-value* :inner))
               (funcall next))
             (push (list :exit *fixture-value*) events))
           (after-each
             (push :after events))
           (it "case"
             (push (list :body *fixture-value*) events)))))
      (cl-weave::collect-events root)
      (expect (reverse events)
              :to-equal '(:before (:enter 41) (:body :inner) (:exit 41) :after))))

  (it "runs around-each cleanup before after-each when body fails"
    (let ((root (cl-weave::make-suite :name "root"))
          (events nil))
      (let ((cl-weave::*current-suite* root)
            (cl-weave::*root-suite* root))
        (cl-weave::register-suite
         "around cleanup"
         (lambda ()
           (around-each (next)
             (unwind-protect
                  (funcall next)
               (push :around-cleanup events)))
           (after-each
             (push :after events))
           (it "case"
             (error "boom")))))
      (let ((result (cl-weave::collect-events root)))
        (expect (mapcar #'cl-weave::test-event-status result) :to-equal '(:error)))
      (expect (reverse events) :to-equal '(:around-cleanup :after)))))

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
        (expect events :to-equal '(:after-each)))))

  (it "exposes a restart that can continue a failed attempt as passed"
    (let* ((test (cl-weave::make-test-case
                  :name "continue from failure"
                  :function (lambda ()
                              (expect :actual :to-be :expected))))
           (event (handler-bind ((assertion-failure
                                   (lambda (condition)
                                     (declare (ignore condition))
                                     (invoke-restart 'continue-test))))
                    (cl-weave::run-test-case (cl-weave::root-suite) test))))
      (expect (cl-weave::test-event-status event) :to-be :pass)))

  (it "exposes a restart that records a failed attempt as skipped"
    (let* ((test (cl-weave::make-test-case
                  :name "skip from failure"
                  :function (lambda ()
                              (expect :actual :to-be :expected))))
           (event (handler-bind ((assertion-failure
                                   (lambda (condition)
                                     (declare (ignore condition))
                                     (invoke-restart 'skip-test "patched interactively"))))
                    (cl-weave::run-test-case (cl-weave::root-suite) test))))
      (expect (cl-weave::test-event-status event) :to-be :skip)
      (expect (cl-weave::test-event-reason event) :to-equal "patched interactively")))

  (it "exposes a restart that retries without consuming configured retries"
    (let* ((attempts 0)
           (retried nil)
           (test (cl-weave::make-test-case
                  :name "retry from failure"
                  :retry 0
                  :function (lambda ()
                              (incf attempts)
                              (expect attempts :to-be 2))))
           (event (handler-bind ((assertion-failure
                                   (lambda (condition)
                                     (declare (ignore condition))
                                     (unless retried
                                       (setf retried t)
                                       (invoke-restart 'retry-test)))))
                    (cl-weave::run-test-case (cl-weave::root-suite) test))))
      (expect attempts :to-be 2)
      (expect (cl-weave::test-event-status event) :to-be :pass))))

(describe "concurrent tests"
  (it "runs adjacent concurrent tests before either one completes"
    (let* ((root (cl-weave::make-suite :name "root"))
           (suite (cl-weave::add-child
                   root
                   (cl-weave::make-suite :name "concurrent" :parent root)))
           (mutex (sb-thread:make-mutex :name "cl-weave concurrent test log"))
           (events-log nil))
      (labels ((record (event)
                 (sb-thread:with-mutex (mutex)
                   (push event events-log)))
               (recorded-p (event)
                 (sb-thread:with-mutex (mutex)
                   (member event events-log)))
               (wait-until-recorded (event timeout-seconds)
                 (let ((deadline (+ (get-internal-real-time)
                                    (* timeout-seconds internal-time-units-per-second))))
                   (loop until (or (recorded-p event)
                                   (> (get-internal-real-time) deadline))
                         do (sleep 0.01))
                   (recorded-p event))))
        (cl-weave::add-child
         suite
         (cl-weave::make-test-case
          :name "first"
          :concurrent t
          :function (lambda ()
                      (record :first-start)
                      (unless (wait-until-recorded :second-start 1)
                        (error "second concurrent test did not start before first completed"))
                      (record :first-end))))
        (cl-weave::add-child
         suite
         (cl-weave::make-test-case
          :name "second"
          :concurrent t
          :function (lambda ()
                      (record :second-start)
                      (sleep 0.02)
                      (record :second-end))))
        (let* ((events (cl-weave::collect-events root))
               (ordered-log (reverse events-log)))
          (expect (mapcar #'cl-weave::test-event-status events)
                  :to-equal '(:pass :pass))
          (expect (member :second-start ordered-log) :not :to-be nil)
          (expect (member :first-end ordered-log) :not :to-be nil)
          (expect (mapcar #'cl-weave::test-event-path events)
                  :to-equal '(("concurrent" "first")
                              ("concurrent" "second")))))))

  (it "inherits concurrent execution mode from suites"
    (let* ((root (cl-weave::make-suite :name "root"))
           (suite (cl-weave::add-child
                   root
                   (cl-weave::make-suite
                    :name "concurrent suite"
                    :parent root
                    :execution-mode :concurrent)))
           (mutex (sb-thread:make-mutex :name "cl-weave suite concurrent test log"))
           (events-log nil))
      (labels ((record (event)
                 (sb-thread:with-mutex (mutex)
                   (push event events-log)))
               (recorded-p (event)
                 (sb-thread:with-mutex (mutex)
                   (member event events-log)))
               (wait-until-recorded (event timeout-seconds)
                 (let ((deadline (+ (get-internal-real-time)
                                    (* timeout-seconds internal-time-units-per-second))))
                   (loop until (or (recorded-p event)
                                   (> (get-internal-real-time) deadline))
                         do (sleep 0.01))
                   (recorded-p event))))
        (cl-weave::add-child
         suite
         (cl-weave::make-test-case
          :name "first"
          :function (lambda ()
                      (record :first-start)
                      (unless (wait-until-recorded :second-start 1)
                        (error "suite concurrent test did not start beside its sibling"))
                      (record :first-end))))
        (cl-weave::add-child
         suite
         (cl-weave::make-test-case
          :name "second"
          :function (lambda ()
                      (record :second-start)
                      (sleep 0.02)
                      (record :second-end))))
        (let ((events (cl-weave::collect-events root)))
          (expect (mapcar #'cl-weave::test-event-status events)
                  :to-equal '(:pass :pass))
          (expect (mapcar #'cl-weave::test-event-path events)
                  :to-equal '(("concurrent suite" "first")
                              ("concurrent suite" "second")))))))

  (it "keeps bail semantics sequential for concurrent tests"
    (let* ((root (cl-weave::make-suite :name "root"))
           (suite (cl-weave::add-child
                   root
                   (cl-weave::make-suite :name "concurrent bail" :parent root)))
           (events-log nil))
      (cl-weave::add-child
       suite
       (cl-weave::make-test-case
        :name "fails"
        :concurrent t
        :function (lambda ()
                    (push :first events-log)
                    (expect :actual :to-be :expected))))
      (cl-weave::add-child
       suite
       (cl-weave::make-test-case
        :name "must not run"
        :concurrent t
        :function (lambda ()
                    (push :second events-log))))
      (let ((events (cl-weave::collect-events root :bail t)))
        (expect (mapcar #'cl-weave::test-event-status events)
                :to-equal '(:fail))
        (expect events-log :to-equal '(:first))))))

(describe "coverage"
  (it "reports coverage support as a safe boolean"
    (expect (cl-weave:coverage-support-available-p)
            :to-satisfy (lambda (value)
                          (or (eq value t) (eq value nil)))))

  (it "wraps run-all with coverage reset and save hooks"
    (let ((root (cl-weave::make-suite :name "root"))
          (calls nil))
      (cl-weave::add-child
       root
       (cl-weave::make-test-case
        :name "covered"
        :function (lambda ()
                    (push :test calls))))
      (with-mocked-functions
          (((symbol-function 'cl-weave::require-coverage-support)
            (lambda ()
              (push :require calls)
              t))
           ((symbol-function 'cl-weave:reset-coverage)
            (lambda ()
              (push :reset calls)
              t))
           ((symbol-function 'cl-weave:save-coverage)
            (lambda (path)
              (push (list :save path) calls)
              path)))
        (let ((cl-weave::*root-suite* root))
          (expect (with-output-to-string (stream)
                    (expect (cl-weave:run-all
                             :reporter :sexp
                             :stream stream
                             :coverage t
                             :coverage-output "coverage.dat")
                            :to-be-truthy))
                  :to-contain ":CL-WEAVE/RESULTS")))
      (expect (reverse calls)
              :to-equal '(:require :reset :test (:save "coverage.dat")))))

  (it "can preserve existing coverage counters"
    (let ((root (cl-weave::make-suite :name "root"))
          (calls nil))
      (cl-weave::add-child
       root
       (cl-weave::make-test-case
        :name "covered"
        :function (lambda ()
                    (push :test calls))))
      (with-mocked-functions
          (((symbol-function 'cl-weave::require-coverage-support)
            (lambda ()
              (push :require calls)
              t))
           ((symbol-function 'cl-weave:reset-coverage)
            (lambda ()
              (push :reset calls)
              t))
           ((symbol-function 'cl-weave:save-coverage)
            (lambda (path)
              (push (list :save path) calls)
              path)))
        (let ((cl-weave::*root-suite* root))
          (with-output-to-string (stream)
            (expect (cl-weave:run-all
                     :reporter :sexp
                     :stream stream
                     :coverage t
                     :coverage-reset nil
                     :coverage-output "coverage.dat")
                    :to-be-truthy))))
      (expect (reverse calls)
              :to-equal '(:require :test (:save "coverage.dat"))))))

(describe "expected failures"
  (it-fails "passes when the body fails"
    (expect 1 :to-be 2))

  (test-fails "alias passes when the body errors"
    (error "known bug"))

  (it "turns unexpected success into a structured failure"
    (let* ((test (cl-weave::make-test-case
                  :name "known bug"
                  :expected-failure-reason "known bug"
                  :function (lambda () :ok)))
           (event (cl-weave::run-test-case (cl-weave::root-suite) test)))
      (expect (cl-weave::test-event-status event) :to-be :fail)
      (expect (cl-weave::test-event-condition event)
              :to-be-instance-of 'cl-weave:expected-failure-missed)
      (expect (cl-weave:expected-failure-missed-reason
               (cl-weave::test-event-condition event))
              :to-equal "known bug")))

  (it "retries unexpected success until it becomes an expected failure"
    (let* ((attempts 0)
           (test (cl-weave::make-test-case
                  :name "eventually fails"
                  :retry 2
                  :expected-failure-reason "known bug"
                  :function (lambda ()
                              (incf attempts)
                              (when (= attempts 3)
                                (expect :actual :to-be :expected)))))
           (event (cl-weave::run-test-case (cl-weave::root-suite) test)))
      (expect attempts :to-be 3)
      (expect (cl-weave::test-event-status event) :to-be :pass))))

(describe "skips"
  (it "does not run skipped tests"
    (let* ((called nil)
           (test (cl-weave::make-test-case
                  :name "skipped case"
                  :function (lambda () (setf called t))
                  :skip-reason "not implemented"))
           (event (cl-weave::run-test-case (cl-weave::root-suite) test)))
      (expect called :to-be nil)
      (expect (cl-weave::test-event-status event) :to-be :skip)
      (expect (cl-weave::test-event-reason event) :to-equal "not implemented")
      (expect (cl-weave::passed-event-p event) :to-be-truthy)))

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
                :to-equal '(("blocked" "case"))))))

  (it "registers conditional tests as skipped or runnable cases"
    (let ((root (cl-weave::make-suite :name "root"))
          (ran nil))
      (let ((cl-weave::*root-suite* root)
            (cl-weave::*current-suite* nil))
        (it-skip-if t "skip-if true"
          (setf ran :skip-if-true))
        (it-run-if nil "run-if false"
          (setf ran :run-if-false))
        (it-skip-if nil "skip-if false"
          (setf ran :skip-if-false))
        (test-run-if t "test-run-if true"
          (setf ran :test-run-if-true)))
      (let ((events (cl-weave::collect-events root)))
        (expect (mapcar #'cl-weave::test-event-status events)
                :to-equal '(:skip :skip :pass :pass))
        (expect (mapcar #'cl-weave::test-event-reason events)
                :to-equal '("conditional skip" "conditional run-if" nil nil))
        (expect ran :to-be :test-run-if-true))))

  (it "registers conditional suites as skipped or runnable groups"
    (let ((root (cl-weave::make-suite :name "root"))
          (ran nil))
      (let ((cl-weave::*root-suite* root)
            (cl-weave::*current-suite* nil))
        (describe-skip-if t "skip-if suite"
          (before-all (setf ran :skip-before-all))
          (it "case" (setf ran :skip-body)))
        (describe-run-if nil "run-if suite"
          (it "case" (setf ran :run-if-body)))
        (describe-run-if t "enabled suite"
          (it "case" (setf ran :enabled-body))))
      (let ((events (cl-weave::collect-events root)))
        (expect (mapcar #'cl-weave::test-event-status events)
                :to-equal '(:skip :skip :pass))
        (expect (mapcar #'cl-weave::test-event-reason events)
                :to-equal '("conditional skip" "conditional run-if" nil))
        (expect (mapcar #'cl-weave::test-event-path events)
                :to-equal '(("skip-if suite" "case")
                            ("run-if suite" "case")
                            ("enabled suite" "case")))
        (expect ran :to-be :enabled-body)))))

(describe "todos"
  (it "registers todo tests with a stable reason"
    (let ((cl-weave::*root-suite* (cl-weave::make-suite :name "root"))
          (cl-weave::*current-suite* nil))
      (it-todo "documents pending work" "intentional")
      (let ((events (cl-weave::collect-events cl-weave::*root-suite*)))
        (expect (mapcar #'cl-weave::test-event-status events) :to-equal '(:todo))
        (expect (mapcar #'cl-weave::test-event-reason events)
                :to-equal '("intentional")))))

  (it "reports todo tests without running their body"
    (let* ((called nil)
           (test (cl-weave::make-test-case
                  :name "todo case"
                  :function (lambda () (setf called t))
                  :todo-reason "pending"))
           (event (cl-weave::run-test-case (cl-weave::root-suite) test)))
      (expect called :to-be nil)
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
      (expect hook-events :to-equal nil)))

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
        :concurrent t))
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
      (expect (getf location :file) :to-contain "tests/core.lisp")))

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
        :concurrent t))
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
        :concurrent t))
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

(describe "bail"
  (it "stops after the first failing event"
    (let* ((root (cl-weave::make-suite :name "root"))
           (suite (cl-weave::add-child
                   root
                   (cl-weave::make-suite :name "bail" :parent root)))
           (events-log nil))
      (cl-weave::add-child
       suite
       (cl-weave::make-test-case
        :name "first"
        :function (lambda ()
                    (setf events-log (append events-log '(:first)))
                    (expect nil :to-be-truthy))))
      (cl-weave::add-child
       suite
       (cl-weave::make-test-case
        :name "second"
        :function (lambda ()
                    (setf events-log (append events-log '(:second))))))
      (let ((events (cl-weave::collect-events root :bail t)))
        (expect (mapcar #'cl-weave::test-event-status events) :to-equal '(:fail))
        (expect events-log :to-equal '(:first)))))

  (it "accepts an integer failure limit"
    (let* ((root (cl-weave::make-suite :name "root"))
           (suite (cl-weave::add-child
                   root
                   (cl-weave::make-suite :name "bail" :parent root)))
           (events-log nil))
      (cl-weave::add-child
       suite
       (cl-weave::make-test-case
        :name "first"
        :function (lambda ()
                    (setf events-log (append events-log '(:first)))
                    (expect nil :to-be-truthy))))
      (cl-weave::add-child
       suite
       (cl-weave::make-test-case
        :name "second"
        :function (lambda ()
                    (setf events-log (append events-log '(:second))))))
      (cl-weave::add-child
       suite
       (cl-weave::make-test-case
        :name "third"
        :function (lambda ()
                    (setf events-log (append events-log '(:third)))
                    (error "boom"))))
      (cl-weave::add-child
       suite
       (cl-weave::make-test-case
        :name "fourth"
        :function (lambda ()
                    (setf events-log (append events-log '(:fourth))))))
      (let ((events (cl-weave::collect-events root :bail 2)))
        (expect (mapcar #'cl-weave::test-event-status events)
                :to-equal '(:fail :pass :error))
        (expect events-log :to-equal '(:first :second :third)))))

  (it "rejects invalid bail limits with stable errors"
    (let ((root (cl-weave::make-suite :name "root")))
      (dolist (bail '(-1 :yes "1"))
        (expect (lambda ()
                  (cl-weave::collect-events root :bail bail))
                :to-throw
                "Bail must be")))))

(describe "cli"
  (it "parses Vitest-shaped run options into explicit data"
    (let ((options (cl-weave/cli::parse-cli-arguments
                    '("run"
                      "cl-weave-tests"
                      "--reporter=json"
                      "--filter"
                      "parser"
                      "--output"
                      "results.json"
                      "--bail=2"
                      "--shard"
                      "2/4"
                      "--sequence"
                      "random"
                      "--seed"
                      "123"
                      "--coverage"
                      "--coverage-output"
                      "coverage.out"
                      "--fail-with-no-tests"
                      "--snapshot-dir"
                      "tests/__snapshots__/"
                      "--snapshot-file"
                      "cli.snapshots"
                      "--update-snapshots")
                    (cl-weave/cli::make-cli-options))))
      (expect (cl-weave/cli::cli-options-command options) :to-be :run)
      (expect (cl-weave/cli::cli-options-systems options)
              :to-equal '("cl-weave-tests"))
      (expect (cl-weave/cli::cli-options-reporter options) :to-be :json)
      (expect (cl-weave/cli::parse-reporter "jsonl") :to-be :jsonl)
      (expect (cl-weave/cli::parse-reporter "ndjson") :to-be :jsonl)
      (expect (cl-weave/cli::parse-reporter "github") :to-be :github)
      (expect (lambda ()
                (cl-weave/cli::parse-reporter "unknown"))
              :to-throw
              "cl-weave: unknown reporter")
      (expect (cl-weave/cli::cli-options-name-filter options) :to-equal "parser")
      (expect (cl-weave/cli::cli-options-output-file options)
              :to-equal "results.json")
      (expect (cl-weave/cli::cli-options-bail options) :to-be 2)
      (expect (cl-weave/cli::cli-options-shard options) :to-equal '(2 4))
      (expect (cl-weave/cli::cli-options-order options) :to-be :random)
      (expect (cl-weave/cli::cli-options-seed options) :to-be 123)
      (expect (cl-weave/cli::cli-options-coverage options) :to-be t)
      (expect (cl-weave/cli::cli-options-coverage-output options)
              :to-equal "coverage.out")
      (expect (cl-weave/cli::cli-options-pass-with-no-tests options) :to-be nil)
      (expect (cl-weave/cli::cli-options-snapshot-directory options)
              :to-equal #P"tests/__snapshots__/")
      (expect (cl-weave/cli::cli-options-snapshot-file options)
              :to-equal "cli.snapshots")
      (expect (cl-weave/cli::cli-options-update-snapshots options) :to-be t)))

  (it "parses Vitest camelCase option aliases"
    (let ((options (cl-weave/cli::parse-cli-arguments
                    '("run"
                      "--testNamePattern"
                      "cli"
                      "--coverageOutput=coverage.out"
                      "--passWithNoTests"
                      "--snapshotDir"
                      "tests/__snapshots__/"
                      "--snapshotFile=vitest.snapshots"
                      "--update")
                    (cl-weave/cli::make-cli-options)))
          (watch-options (cl-weave/cli::parse-cli-arguments
                          '("watch" "cl-weave-tests" "--watchInterval" "2.5")
                          (cl-weave/cli::make-cli-options)))
          (snapshot-options (cl-weave/cli::parse-cli-arguments
                             '("run" "--updateSnapshots")
                             (cl-weave/cli::make-cli-options))))
      (expect (cl-weave/cli::cli-options-name-filter options) :to-equal "cli")
      (expect (cl-weave/cli::cli-options-coverage-output options)
              :to-equal "coverage.out")
      (expect (cl-weave/cli::cli-options-pass-with-no-tests options) :to-be t)
      (expect (cl-weave/cli::cli-options-snapshot-directory options)
              :to-equal #P"tests/__snapshots__/")
      (expect (cl-weave/cli::cli-options-snapshot-file options)
              :to-equal "vitest.snapshots")
      (expect (cl-weave/cli::cli-options-update-snapshots options) :to-be t)
      (expect (cl-weave/cli::cli-options-watch-interval watch-options)
              :to-be 2.5)
      (expect (cl-weave/cli::cli-options-update-snapshots snapshot-options)
              :to-be t)))

  (it "parses watch intervals as explicit CLI text"
    (labels ((watch-interval-from-env (value)
               (with-mocked-functions
                   (((symbol-function 'uiop:getenv)
                     (lambda (name)
                       (when (string= name "CL_WEAVE_WATCH_INTERVAL")
                         value))))
                 (cl-weave/cli::cli-options-watch-interval
                  (cl-weave/cli::options-from-environment)))))
      (expect (cl-weave/cli::cli-options-watch-interval
               (cl-weave/cli::parse-cli-arguments
                '("watch" "--watch-interval" "0.25")
                (cl-weave/cli::make-cli-options)))
              :to-be 0.25)
      (expect (watch-interval-from-env "0.25") :to-be 0.25)
      (dolist (value '("0" "-1" "1/2" "1 " ".5" "1." "#.(error \"reader\")"))
        (expect (lambda ()
                  (cl-weave/cli::parse-cli-arguments
                   (list "watch" "--watchInterval" value)
                   (cl-weave/cli::make-cli-options)))
                :to-throw
                "--watch-interval must be a positive number")
        (expect (lambda ()
                  (watch-interval-from-env value))
                :to-throw
                "CL_WEAVE_WATCH_INTERVAL must be a positive number"))))

  (it "parses CI snapshot settings from environment variables"
    (with-mocked-functions
        (((symbol-function 'uiop:getenv)
          (lambda (name)
            (cdr (assoc name
                        '(("CL_WEAVE_SNAPSHOT_DIR" . "ci/__snapshots__/")
                          ("CL_WEAVE_SNAPSHOT_FILE" . "ci.snapshots")
                          ("CL_WEAVE_UPDATE_SNAPSHOTS" . "1"))
                        :test #'string=)))))
      (let ((options (cl-weave/cli::options-from-environment)))
        (expect (cl-weave/cli::cli-options-snapshot-directory options)
                :to-equal #P"ci/__snapshots__/")
        (expect (cl-weave/cli::cli-options-snapshot-file options)
                :to-equal "ci.snapshots")
        (expect (cl-weave/cli::cli-options-update-snapshots options) :to-be t))))

  (it "parses no-test policy from flags and environment"
    (let ((options (cl-weave/cli::parse-cli-arguments
                    '("run" "--fail-with-no-tests" "--pass-with-no-tests")
                    (cl-weave/cli::make-cli-options))))
      (expect (cl-weave/cli::cli-options-pass-with-no-tests options) :to-be t))
    (with-mocked-functions
        (((symbol-function 'uiop:getenv)
          (lambda (name)
            (cdr (assoc name
                        '(("CL_WEAVE_PASS_WITH_NO_TESTS" . "false"))
                        :test #'string=)))))
      (let ((options (cl-weave/cli::options-from-environment)))
        (expect (cl-weave/cli::cli-options-pass-with-no-tests options)
                :to-be nil))))

  (it "treats Lisp nil environment tokens as false"
    (with-mocked-functions
        (((symbol-function 'uiop:getenv)
          (lambda (name)
            (cdr (assoc name
                        '(("CL_WEAVE_COVERAGE" . "nil")
                          ("CL_WEAVE_LIST" . "nil")
                          ("CL_WEAVE_WATCH" . "nil")
                          ("CL_WEAVE_UPDATE_SNAPSHOTS" . "nil")
                          ("CL_WEAVE_PASS_WITH_NO_TESTS" . "nil"))
                        :test #'string=)))))
      (let ((options (cl-weave/cli::options-from-environment)))
        (expect (cl-weave/cli::cli-options-coverage options) :to-be nil)
        (expect (cl-weave/cli::cli-options-list options) :to-be nil)
        (expect (cl-weave/cli::cli-options-watch options) :to-be nil)
        (expect (cl-weave/cli::cli-options-update-snapshots options) :to-be nil)
        (expect (cl-weave/cli::cli-options-pass-with-no-tests options)
                :to-be nil))))

  (it "parses bail control from CI environment data"
    (labels ((bail-from (value)
               (with-mocked-functions
                   (((symbol-function 'uiop:getenv)
                     (lambda (name)
                       (when (string= name "CL_WEAVE_BAIL")
                         value))))
                 (cl-weave/cli::cli-options-bail
                  (cl-weave/cli::options-from-environment)))))
      (dolist (value '("0" "false" "no" "off" "nil"))
        (expect (bail-from value) :to-be nil))
      (dolist (value '("true" "yes" "on" "t"))
        (expect (bail-from value) :to-be t))
      (expect (bail-from "3") :to-be 3)
      (dolist (value '("maybe" "-1" "1.5"))
        (expect (lambda ()
                  (bail-from value))
                :to-throw
                "--bail must be true, false, or a positive integer"))))

  (it "requires explicit CI sequence seeds to be positive integers"
    (labels ((seed-from (value)
               (with-mocked-functions
                   (((symbol-function 'uiop:getenv)
                     (lambda (name)
                       (when (string= name "CL_WEAVE_SEQUENCE_SEED")
                         value))))
                 (cl-weave/cli::cli-options-seed
                  (cl-weave/cli::options-from-environment)))))
      (expect (seed-from "42") :to-be 42)
      (dolist (value '("0" "-1" "1.5" "abc"))
        (expect (lambda ()
                  (seed-from value))
                :to-throw
                "CL_WEAVE_SEQUENCE_SEED"))))

  (it "binds snapshot settings during CLI execution"
    (let ((observed nil)
          (options (cl-weave/cli::make-cli-options
                    :snapshot-directory #P"tmp/__snapshots__/"
                    :snapshot-file "cli.snapshots"
                    :update-snapshots t)))
      (with-mocked-functions
          (((symbol-function 'cl-weave:run-all)
            (lambda (&key reporter name-filter shard order seed bail coverage
                     coverage-output pass-with-no-tests stream)
              (declare (ignore reporter name-filter shard order seed bail coverage
                               coverage-output pass-with-no-tests stream))
              (setf observed
                    (list cl-weave:*snapshot-directory*
                          cl-weave:*snapshot-file-name*
                          cl-weave:*update-snapshots*))
              t)))
        (expect (cl-weave/cli::run-command options) :to-be t))
      (expect observed
              :to-equal (list #P"tmp/__snapshots__/" "cli.snapshots" t))))

  (it "writes JSON result artifacts through the CLI output option"
    (let* ((output-file (test-temporary-pathname "cl-weave-cli-results.json"))
           (options (cl-weave/cli::make-cli-options
                     :reporter :json
                     :output-file (namestring output-file))))
      (when (probe-file output-file)
        (delete-file output-file))
      (unwind-protect
           (progn
             (with-mocked-functions
                 (((symbol-function 'cl-weave:run-all)
                   (lambda (&key reporter name-filter shard order seed bail coverage
                            coverage-output pass-with-no-tests stream)
                     (declare (ignore name-filter shard order seed bail coverage
                                      coverage-output pass-with-no-tests))
                     (expect reporter :to-be :json)
                     (cl-weave::report-json nil stream)
                     t)))
               (expect (with-output-to-string (*standard-output*)
                         (cl-weave/cli::run-command options))
                       :to-equal ""))
             (let ((output (read-text-file output-file)))
               (expect output :to-contain "\"schemaVersion\":4")
               (expect output :to-contain "\"kind\":\"test-results\"")
               (expect output :to-contain "\"events\":[]")))
        (when (probe-file output-file)
          (delete-file output-file)))))

  (it "parses list and watch commands without executing tests"
    (let ((list-options (cl-weave/cli::parse-cli-arguments
                         '("list" "cl-weave-tests" "--reporter" "sexp")
                         (cl-weave/cli::make-cli-options)))
          (watch-options (cl-weave/cli::parse-cli-arguments
                          '("watch" "cl-weave-tests" "--watch-interval" "1.5")
                          (cl-weave/cli::make-cli-options))))
      (expect (cl-weave/cli::cli-options-command list-options) :to-be :list)
      (expect (cl-weave/cli::cli-options-list list-options) :to-be t)
      (expect (cl-weave/cli::cli-options-reporter list-options) :to-be :sexp)
      (expect (cl-weave/cli::cli-options-command watch-options) :to-be :watch)
      (expect (cl-weave/cli::cli-options-watch watch-options) :to-be t)
      (expect (cl-weave/cli::cli-options-watch-interval watch-options)
              :to-be 1.5)))

  (it "normalizes SBCL argument separators from nix run"
    (let ((options (cl-weave/cli::parse-cli-arguments
                    '("--" "run" "cl-weave-tests" "--filter" "cli")
                    (cl-weave/cli::make-cli-options))))
      (expect (cl-weave/cli::cli-options-command options) :to-be :run)
      (expect (cl-weave/cli::cli-options-systems options)
              :to-equal '("cl-weave-tests"))
      (expect (cl-weave/cli::cli-options-name-filter options) :to-equal "cli")))

  (it "prints Vitest-compatible version output without running tests"
    (let ((flag-options (cl-weave/cli::parse-cli-arguments
                         '("--version")
                         (cl-weave/cli::make-cli-options)))
          (command-options (cl-weave/cli::parse-cli-arguments
                            '("version")
                            (cl-weave/cli::make-cli-options)))
          (exit-code nil))
      (expect (cl-weave/cli::cli-options-version flag-options) :to-be t)
      (expect (cl-weave/cli::cli-options-version command-options) :to-be t)
      (expect (cl-weave/cli::cli-version) :to-equal "0.1.0")
      (with-mocked-functions
          (((symbol-function 'cl-weave/cli::exit-process)
            (lambda (code)
              (setf exit-code code))))
        (let ((output (with-output-to-string (*standard-output*)
                        (cl-weave/cli:main '("--version")))))
          (expect output :to-equal (format nil "cl-weave 0.1.0~%"))
          (expect exit-code :to-be 0)))))

  (it "rejects CI-incompatible list reporters early"
    (dolist (reporter '("github" "junit"))
      (let ((options (cl-weave/cli::parse-cli-arguments
                      (list "list" "cl-weave-tests" "--reporter" reporter)
                      (cl-weave/cli::make-cli-options))))
        (expect (lambda ()
                  (cl-weave/cli::ensure-valid-reporter-for-command options))
                :to-throw))))

  (it "prints AI-friendly command usage"
    (let ((usage (cl-weave/cli::cli-usage)))
      (expect usage :to-contain "cl-weave run [SYSTEM] [options]")
      (expect usage :to-contain "cl-weave version")
      (expect usage :to-contain "--reporter REPORTER")
      (expect usage :to-contain "--shard INDEX/COUNT")
      (expect usage :to-contain "--testNamePattern TEXT")
      (expect usage :to-contain "--failWithNoTests")
      (expect usage :to-contain "--snapshotDir DIR")
      (expect usage :to-contain "--snapshotFile FILE")
      (expect usage :to-contain "--updateSnapshots")
      (expect usage :to-contain "--version"))))

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
            (lambda (system &key reporter stream name-filter shard order seed bail)
              (declare (ignore stream))
              (push (list system reporter name-filter shard order seed bail) calls)
              t)))
        (setf output
              (with-output-to-string (stream)
                (expect (cl-weave:watch-system
                         "cl-weave"
                         :reporter :json
                         :stream stream
                         :status-stream stream
                         :name-filter "expect"
                         :shard '(1 2)
                         :order :random
                         :seed 123
                         :bail 1
                         :once t)
                        :to-be-truthy))))
      (expect calls :to-equal '(("cl-weave" :json "expect" (1 2) :random 123 1)))
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
      (expect mock :to-have-been-nth-called-with 1 1 2)
      (expect mock :to-have-been-nth-called-with 2 5 8)
      (expect mock :to-have-been-last-called-with 5 8)
      (expect (mock-calls mock) :to-equal '((1 2) (5 8)))
      (clear-mock mock)
      (expect mock :not :to-have-been-called)
      (expect (mock-calls mock) :to-equal nil)
      (expect (mock-results mock) :to-equal nil)))

  (it "matches ordered zero-argument mock calls"
    (let ((mock (make-mock-function (lambda () :pong))))
      (expect (funcall mock) :to-be :pong)
      (expect mock :to-have-been-nth-called-with 1)
      (expect mock :to-have-been-last-called-with)))

  (it "records mock return values including multiple values"
    (let ((mock (make-mock-function (lambda (value)
                                      (values value (* value 2))))))
      (multiple-value-bind (value doubled) (funcall mock 4)
        (expect value :to-be 4)
        (expect doubled :to-be 8))
      (multiple-value-bind (value doubled) (funcall mock 7)
        (expect value :to-be 7)
        (expect doubled :to-be 14))
      (expect mock :to-have-returned)
      (expect mock :to-have-returned-times 2)
      (expect mock :to-have-returned-with 4 8)
      (expect mock :to-have-nth-returned-with 1 4 8)
      (expect mock :to-have-nth-returned-with 2 7 14)
      (expect mock :to-have-last-returned-with 7 14)
      (expect (mock-results mock)
              :to-equal
              '((:type :return :value 4 :values (4 8))
                (:type :return :value 7 :values (7 14))))))

  (it "matches returned order without counting thrown results"
    (let ((mock (let ((state 0))
                  (make-mock-function
                   (lambda ()
                     (incf state)
                     (when (= state 2)
                       (error "mock exploded"))
                     (values state :ok))))))
      (multiple-value-bind (value status) (funcall mock)
        (expect value :to-be 1)
        (expect status :to-be :ok))
      (expect (lambda () (funcall mock)) :to-throw "mock exploded")
      (multiple-value-bind (value status) (funcall mock)
        (expect value :to-be 3)
        (expect status :to-be :ok))
      (expect mock :to-have-returned-times 2)
      (expect mock :to-have-nth-returned-with 1 1 :ok)
      (expect mock :to-have-nth-returned-with 2 3 :ok)
      (expect mock :to-have-last-returned-with 3 :ok)
      (expect mock :to-have-thrown)))

  (it "records thrown conditions from mock functions"
    (let ((mock (make-mock-function (lambda ()
                                      (error "mock exploded")))))
      (expect (lambda () (funcall mock)) :to-throw "mock exploded")
      (expect mock :to-have-thrown)
      (expect mock :not :to-have-returned)
      (expect (getf (first (mock-results mock)) :type) :to-be :throw)
      (expect (getf (first (mock-results mock)) :message)
              :to-contain
              "mock exploded")))

  (it "reports structured mock assertion failures"
    (handler-case
        (let ((mock (make-mock-function (lambda () :ok))))
          (funcall mock)
          (expect mock :to-have-returned-times 2)
          (error "unreachable"))
      (assertion-failure (condition)
        (let ((assertion (cl-weave::failure-detail condition)))
          (expect (cl-weave::assertion-detail-matcher assertion)
                  :to-be
                  :to-have-returned-times)
          (expect (getf (cl-weave::assertion-detail-actual assertion)
                        :return-count)
                  :to-be
                  1)
          (expect (cl-weave::assertion-detail-expected assertion)
                  :to-equal
                  '(:return-count 2))))))

  (it "reports structured ordered mock assertion failures"
    (handler-case
        (let ((mock (make-mock-function (lambda (value) value))))
          (funcall mock :actual)
          (expect mock :to-have-been-nth-called-with 2 :missing)
          (error "unreachable"))
      (assertion-failure (condition)
        (let ((assertion (cl-weave::failure-detail condition)))
          (expect (cl-weave::assertion-detail-matcher assertion)
                  :to-be
                  :to-have-been-nth-called-with)
          (expect (getf (cl-weave::assertion-detail-actual assertion)
                        :call-count)
                  :to-be
                  1)
          (expect (cl-weave::assertion-detail-expected assertion)
                  :to-equal
                  '(:index 2 :arguments (:missing))))))))

(describe "reporters"
  (it "rejects unknown run reporters before dispatch"
    (expect (lambda ()
              (with-output-to-string (stream)
                (cl-weave:run-all :reporter :unknown :stream stream)))
            :to-throw
            "cl-weave: run mode supports"))

  (it "prints AI-readable S-expression results"
    (let ((output (with-output-to-string (stream)
                      (cl-weave::report-sexp
                      (list (cl-weave::make-test-event
                             :status :pass
                             :path '("reporters" "prints")
                             :location '(:file "tests/reporters.lisp")
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
                             :elapsed-internal-time 0)
                            (cl-weave::make-test-event
                             :status :fail
                             :path '("reporters" "fails")
                             :reason "bad"
                             :elapsed-internal-time 0)
                            (cl-weave::make-test-event
                             :status :error
                             :path '("reporters" "errors")
                             :elapsed-internal-time 0))
                      stream))))
      (expect output :to-contain ":CL-WEAVE/RESULTS")
      (expect output :to-contain ":SCHEMA-VERSION 3")
      (expect output :to-contain ":PATH-STRING \"reporters > prints\"")
      (expect output :to-contain ":LOCATION (:FILE \"tests/reporters.lisp\")")
      (expect output :to-contain ":DURATION-MS 0")
      (expect output :to-contain ":SKIPPED")
      (expect output :to-contain ":TODOS")
      (expect output :to-contain ":TODO")
      (expect output :to-contain ":FAILED-PATHS")
      (expect output :to-contain "\"reporters > fails\"")
      (expect output :to-contain ":ERRORED-PATHS")
      (expect output :to-contain "\"reporters > errors\"")))

  (it "prints AI-readable JSON results"
    (let ((output (with-output-to-string (stream)
                    (cl-weave::report-json
                     (list (cl-weave::make-test-event
                            :status :pass
                            :path '("reporters" "json")
                            :location '(:file "tests/reporters.lisp")
                            :elapsed-internal-time 0)
                           (cl-weave::make-test-event
                            :status :skip
                            :path '("reporters" "quotes")
                            :reason "needs \"escaping\""
                            :elapsed-internal-time 0)
                           (cl-weave::make-test-event
                            :status :fail
                            :path '("reporters" "fails")
                            :reason "bad"
                            :elapsed-internal-time 0)
                           (cl-weave::make-test-event
                            :status :error
                            :path '("reporters" "errors")
                            :elapsed-internal-time 0))
                     stream))))
      (expect output :to-contain "\"schemaVersion\":4")
      (expect output :to-contain "\"kind\":\"test-results\"")
      (expect output :to-contain "\"passed\":1")
      (expect output :to-contain "\"skipped\":1")
      (expect output :to-contain "\"failed\":1")
      (expect output :to-contain "\"errored\":1")
      (expect output :to-contain "\"failedPaths\":[\"reporters > fails\"]")
      (expect output :to-contain "\"erroredPaths\":[\"reporters > errors\"]")
      (expect output :to-contain "\"status\":\"pass\"")
      (expect output :to-contain "\"path\":[\"reporters\",\"json\"]")
      (expect output :to-contain "\"pathString\":\"reporters > json\"")
      (expect output :to-contain "\"location\":{\"file\":\"tests\\/reporters.lisp\"}")
      (expect output :to-contain "\"durationMs\":0.000")
      (expect output :to-contain "\"reason\":\"needs \\\"escaping\\\"\"")
      (expect output :to-contain "\"assertion\":null")))

  (it "prints AI-readable JSONL result streams"
    (let ((output (with-output-to-string (stream)
                    (cl-weave::report-jsonl
                     (list (cl-weave::make-test-event
                            :status :pass
                            :path '("reporters" "jsonl")
                            :location '(:file "tests/reporters.lisp")
                            :elapsed-internal-time 0)
                           (cl-weave::make-test-event
                            :status :fail
                            :path '("reporters" "fails")
                            :reason "bad"
                            :elapsed-internal-time 0))
                     stream))))
      (expect (with-input-from-string (stream output)
                (loop for line = (read-line stream nil nil)
                      while line
                      count line))
              :to-be 4)
      (expect output :to-contain "\"kind\":\"test-results-start\"")
      (expect output :to-contain "\"total\":2")
      (expect output :to-contain "\"kind\":\"test-event\"")
      (expect output :to-contain "\"event\":{\"status\":\"pass\"")
      (expect output :to-contain "\"pathString\":\"reporters > jsonl\"")
      (expect output :to-contain "\"kind\":\"test-results-summary\"")
      (expect output :to-contain "\"failed\":1")
      (expect output :to-contain "\"failedPaths\":[\"reporters > fails\"]")))

  (it "escapes JSON strings with portable control-character rules"
    (let ((escaped (cl-weave::json-escaped-string
                    (coerce (list #\" #\\
                                  (code-char 8)
                                  (code-char 9)
                                  (code-char 10)
                                  (code-char 12)
                                  (code-char 13)
                                  (code-char 1))
                            'string))))
      (expect escaped :to-equal
              (concatenate 'string
                           "\\\""
                           "\\\\"
                           "\\b"
                           "\\t"
                           "\\n"
                           "\\f"
                           "\\r"
                           "\\u0001"))))

  (it "prints AI-readable S-expression test plans"
    (let ((output (with-output-to-string (stream)
                    (cl-weave::report-plan-sexp
                     (list (cl-weave::make-test-plan-entry
                            :status :run
                           :path '("plan" "runs")
                            :location '(:file "tests/plan.lisp")
                            :focused t
                            :retry 2
                            :timeout-ms 250
                            :concurrent t)
                           (cl-weave::make-test-plan-entry
                            :status :skip
                            :path '("plan" "skips")
                            :reason "blocked"
                            :focused nil
                            :retry 0))
                     stream))))
      (expect output :to-contain ":CL-WEAVE/TEST-PLAN")
      (expect output :to-contain ":SCHEMA-VERSION 2")
      (expect output :to-contain ":RUNNABLE 1")
      (expect output :to-contain ":SKIPPED 1")
      (expect output :to-contain ":PATH-STRING \"plan > runs\"")
      (expect output :to-contain ":LOCATION")
      (expect output :to-contain ":FILE \"tests/plan.lisp\"")
      (expect output :to-contain ":FOCUSED T")
      (expect output :to-contain ":TIMEOUT-MS 250")
      (expect output :to-contain ":CONCURRENT T")))

  (it "prints AI-readable JSON test plans"
    (let ((output (with-output-to-string (stream)
                    (cl-weave::report-plan-json
                     (list (cl-weave::make-test-plan-entry
                            :status :run
                            :path '("plan" "runs")
                            :location '(:file "tests/plan.lisp")
                            :focused t
                            :retry 2
                            :timeout-ms 250
                            :concurrent t)
                           (cl-weave::make-test-plan-entry
                            :status :skip
                            :path '("plan" "skips")
                            :reason "blocked"
                            :focused nil
                            :retry 0))
                     stream))))
      (expect output :to-contain "\"schemaVersion\":2")
      (expect output :to-contain "\"kind\":\"test-plan\"")
      (expect output :to-contain "\"runnable\":1")
      (expect output :to-contain "\"skipped\":1")
      (expect output :to-contain "\"status\":\"run\"")
      (expect output :to-contain "\"pathString\":\"plan > runs\"")
      (expect output :to-contain "\"location\":{\"file\":\"tests\\/plan.lisp\"}")
      (expect output :to-contain "\"focused\":true")
      (expect output :to-contain "\"retry\":2")
      (expect output :to-contain "\"timeoutMs\":250")
      (expect output :to-contain "\"concurrent\":true")
      (expect output :to-contain "\"reason\":\"blocked\"")))

  (it "prints AI-readable JSONL test plans"
    (let ((output (with-output-to-string (stream)
                    (cl-weave::report-plan-jsonl
                     (list (cl-weave::make-test-plan-entry
                            :status :run
                            :path '("plan" "runs")
                            :location '(:file "tests/plan.lisp")
                            :focused t
                            :retry 2
                            :timeout-ms 250
                            :concurrent t)
                           (cl-weave::make-test-plan-entry
                            :status :skip
                            :path '("plan" "skips")
                            :reason "blocked"
                            :focused nil
                            :retry 0))
                     stream))))
      (expect (with-input-from-string (stream output)
                (loop for line = (read-line stream nil nil)
                      while line
                      count line))
              :to-be 4)
      (expect output :to-contain "\"kind\":\"test-plan-start\"")
      (expect output :to-contain "\"kind\":\"test-plan-entry\"")
      (expect output :to-contain "\"test\":{\"status\":\"run\"")
      (expect output :to-contain "\"pathString\":\"plan > runs\"")
      (expect output :to-contain "\"kind\":\"test-plan-summary\"")
      (expect output :to-contain "\"runnable\":1")
      (expect output :to-contain "\"skipped\":1")))

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
      (expect output :to-contain "<failure message=\"bad &lt;value&gt; &amp; reason\">")))

  (it "sanitizes JUnit XML strings with portable control-character rules"
    (let ((escaped (cl-weave::xml-escaped-string
                    (coerce (list #\< #\> #\& #\" #\'
                                  (code-char 9)
                                  (code-char 10)
                                  (code-char 13)
                                  (code-char 1))
                            'string))))
      (expect escaped :to-equal
              (concatenate 'string
                           "&lt;"
                           "&gt;"
                           "&amp;"
                           "&quot;"
                           "&apos;"
                           (string (code-char 9))
                           (string (code-char 10))
                           (string (code-char 13))
                           "?"))))

  (it "prints CI-readable TAP results"
    (let ((output (with-output-to-string (stream)
                    (cl-weave::report-tap
                     (list (cl-weave::make-test-event
                            :status :pass
                            :path '("reporters" "passes")
                            :elapsed-internal-time 0)
                           (cl-weave::make-test-event
                            :status :skip
                            :path '("reporters" "skips")
                            :reason "needs terminal"
                            :elapsed-internal-time 0)
                           (cl-weave::make-test-event
                            :status :todo
                            :path '("reporters" "todos")
                            :reason "pending"
                            :elapsed-internal-time 0)
                           (cl-weave::make-test-event
                            :status :fail
                            :path '("reporters" "fails")
                            :condition "bad value"
                            :assertion (cl-weave::make-assertion-detail
                                        :form '(expect 1 :to-be 2)
                                        :matcher :to-be
                                        :actual 1
                                        :expected 2
                                        :negated nil
                                        :pass nil)
                            :elapsed-internal-time 0)
                           (cl-weave::make-test-event
                            :status :error
                            :path '("reporters" "errors")
                            :condition "boom"
                            :elapsed-internal-time 0))
                     stream))))
      (expect output :to-contain "TAP version 13")
      (expect output :to-contain "1..5")
      (expect output :to-contain "ok 1 - reporters > passes")
      (expect output :to-contain "ok 2 - reporters > skips # SKIP needs terminal")
      (expect output :to-contain "ok 3 - reporters > todos # TODO pending")
      (expect output :to-contain "not ok 4 - reporters > fails")
      (expect output :to-contain "not ok 5 - reporters > errors")
      (expect output :to-contain "status: \"fail\"")
      (expect output :to-contain "condition: \"bad value\"")
      (expect output :to-contain "matcher: \":TO-BE\"")))

  (it "prints GitHub Actions annotations for failures and errors"
    (let ((output (with-output-to-string (stream)
                    (cl-weave::report-github
                     (list (cl-weave::make-test-event
                            :status :pass
                            :path '("reporters" "passes")
                            :elapsed-internal-time 0)
                           (cl-weave::make-test-event
                            :status :skip
                            :path '("reporters" "skips")
                            :reason "needs terminal"
                            :elapsed-internal-time 0)
                           (cl-weave::make-test-event
                            :status :fail
                            :path '("reporters" "fails")
                            :location '(:file "tests/reporters,case:lisp")
                            :condition (format nil "bad%~%value, x:y")
                            :assertion (cl-weave::make-assertion-detail
                                        :form '(expect 1 :to-be 2)
                                        :matcher :to-be
                                        :actual 1
                                        :expected 2
                                        :negated nil
                                        :pass nil)
                            :elapsed-internal-time 0)
                           (cl-weave::make-test-event
                            :status :error
                            :path '("reporters" "errors")
                            :condition "boom"
                            :elapsed-internal-time 0))
                     stream))))
      (expect output :to-contain "::error file=tests/reporters%2Ccase%3Alisp::")
      (expect output :to-contain "reporters > fails [fail]%0Abad%25%0Avalue, x:y")
      (expect output :to-contain "matcher: :TO-BE")
      (expect output :to-contain "::error::reporters > errors [error]%0Aboom")
      (expect output :not :to-contain "reporters > passes [pass]")
      (expect output :not :to-contain "reporters > skips [skip]")
      (expect output :to-contain "cl-weave: 1 passed, 1 skipped, 0 todo, 1 failed, 1 errored, 4 total"))))
