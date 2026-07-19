




(in-package #:cl-weave/tests)
(describe "collection snapshot before coverage"
  (it "uses one copied collection preflight across coverage setup"
    (let* ((root (cl-weave::make-suite :name "root"))
           (target #P"/tmp/cl-weave/collection-snapshot.lisp")
           (other #P"/tmp/cl-weave/collection-mutated.lisp")
           (name-filter (copy-seq "runs"))
           (location-filter (list target))
           (path-component (copy-seq "runs"))
           (test-path-filter (list (list path-component)))
           (include-tag (copy-seq "fast"))
           (exclude-tag (copy-seq "slow"))
           (include-tags (list include-tag))
           (exclude-tags (list exclude-tag))
           (coverage-require 0)
           (coverage-reset 0)
           (suite-root 0)
           (suite-snapshot 0)
           (executed 0))
      (cl-weave::add-child
       root
       (cl-weave::make-test-case
        :name "runs"
        :location (list :file (namestring target))
        :tags '("FAST")
        :function (lambda () (incf executed))))
      (with-mocked-functions
          (((symbol-function 'cl-weave::require-coverage-support)
            (lambda ()
              (incf coverage-require)
              (setf (char name-filter 0) #\x
                    (car location-filter) other
                    (char path-component 0) #\x
                    (char include-tag 0) #\x
                    (car exclude-tags) "fast")))
           ((symbol-function 'cl-weave:reset-coverage)
            (lambda () (incf coverage-reset)))
           ((symbol-function 'cl-weave:root-suite)
            (lambda ()
              (incf suite-root)
              root))
           ((symbol-function 'cl-weave::snapshot-suite)
            (lambda (suite)
              (incf suite-snapshot)
              suite)))
        (expect
         (cl-weave:run-all
          :reporter :sexp
          :stream (make-broadcast-stream)
          :coverage t
          :name-filter name-filter
          :location-filter location-filter
          :test-path-filter test-path-filter
          :include-tags include-tags
          :exclude-tags exclude-tags)
         :to-be-truthy))
      (expect coverage-require :to-be 1)
      (expect coverage-reset :to-be 1)
      (expect suite-root :to-be 1)
      (expect suite-snapshot :to-be 1)
      (expect executed :to-be 1))))


(describe "unconsumed coverage filters"
  (it "ignores source filters when no coverage artifact consumes them"
    (labels ((exercise ()
               (let ((root (cl-weave::make-suite :name "root"))
                     (include-cycle (list #P"/tmp/cl-weave/include-cycle/"))
                     (coverage-require 0)
                     (coverage-reset 0)
                     (coverage-cleanup 0)
                     (suite-root 0)
                     (suite-snapshot 0)
                     (executed 0)
                     (artifact 0))
                 (setf (cdr include-cycle) include-cycle)
                 (cl-weave::add-child
                  root
                  (cl-weave::make-test-case
                   :name "runs"
                   :function (lambda () (incf executed))))
                 (with-mocked-functions
                     (((symbol-function 'cl-weave::require-coverage-support)
                       (lambda () (incf coverage-require)))
                      ((symbol-function 'cl-weave:reset-coverage)
                       (lambda () (incf coverage-reset)))
                      ((symbol-function 'cl-weave:coverage-statistics)
                       (lambda (&key include-pathnames exclude-pathnames)
                         (declare (ignore include-pathnames exclude-pathnames))
                         (incf coverage-cleanup)))
                      ((symbol-function 'cl-weave::save-coverage-report)
                       (lambda (path &key include-pathnames exclude-pathnames)
                         (declare (ignore path include-pathnames exclude-pathnames))
                         (incf artifact)))
                      ((symbol-function 'cl-weave:save-coverage)
                       (lambda (path)
                         (declare (ignore path))
                         (incf artifact)))
                      ((symbol-function 'cl-weave:root-suite)
                       (lambda ()
                         (incf suite-root)
                         root))
                      ((symbol-function 'cl-weave::snapshot-suite)
                       (lambda (suite)
                         (incf suite-snapshot)
                         suite)))
                   (expect
                    (cl-weave:run-all
                     :reporter :sexp
                     :stream (make-broadcast-stream)
                     :coverage t
                     :coverage-reset :enabled
                     :coverage-include-pathnames include-cycle
                     :coverage-exclude-pathnames
                     (cons #P"/tmp/cl-weave/exclude/" :tail))
                    :to-be-truthy))
                 (expect coverage-require :to-be 1)
                 (expect coverage-reset :to-be 1)
                 (expect coverage-cleanup :to-be 0)
                 (expect suite-root :to-be 1)
                 (expect suite-snapshot :to-be 1)
                 (expect executed :to-be 1)
                 (expect artifact :to-be 0))))
      #+sbcl
      (sb-ext:with-timeout 10
        (exercise))
      #-sbcl
      (exercise))))


(describe "coverage boundary controls"
  (it "accepts threshold boundaries and generalized coverage controls"
  (let* ((root (cl-weave::make-suite :name "root"))
         (source-pathnames (list "src/"))
         (expected-source
           (make-pathname
            :defaults
            (uiop:ensure-absolute-pathname #P"src/" (uiop:getcwd))))
         (coverage-require 0)
         (coverage-reset 0)
         (coverage-cleanup 0)
         (suite-root 0)
         (suite-snapshot 0)
         (executed 0)
         (observed-source-pathnames nil))
    (cl-weave::add-child
     root
     (cl-weave::make-test-case
      :name "runs"
      :function (lambda () (incf executed))))
    (with-mocked-functions
        (((symbol-function 'cl-weave::require-coverage-support)
          (lambda ()
            (incf coverage-require)
            (setf (car source-pathnames) 42)))
         ((symbol-function 'cl-weave:reset-coverage)
          (lambda () (incf coverage-reset)))
         ((symbol-function 'cl-weave:coverage-statistics)
          (lambda (&key include-pathnames exclude-pathnames)
            (declare (ignore exclude-pathnames))
            (incf coverage-cleanup)
            (setf observed-source-pathnames include-pathnames)
            '(:expression-covered 0 :expression-total 0
              :branch-covered 0 :branch-total 0)))
         ((symbol-function 'cl-weave:root-suite)
          (lambda ()
            (incf suite-root)
            root))
         ((symbol-function 'cl-weave::snapshot-suite)
          (lambda (suite)
            (incf suite-snapshot)
            suite)))
      (expect
       (cl-weave:run-all
        :reporter :sexp
        :stream (make-broadcast-stream)
        :coverage :enabled
        :coverage-reset :enabled
        :coverage-include-pathnames source-pathnames
        :coverage-minimum-expression 0
        :coverage-minimum-branch 100)
       :to-be-truthy))
    (expect coverage-require :to-be 1)
    (expect coverage-reset :to-be 1)
    (expect coverage-cleanup :to-be 1)
    (expect suite-root :to-be 1)
    (expect suite-snapshot :to-be 1)
    (expect executed :to-be 1)
    (expect observed-source-pathnames
            :to-satisfy
            (lambda (pathnames)
              (and (= (length pathnames) 1)
                   (pathnamep (first pathnames))
                   (uiop:absolute-pathname-p (first pathnames))
                   (equal (first pathnames) expected-source)))))))


(describe "coverage disabled preflight"
  (it "ignores invalid coverage-only options when coverage is disabled"
    (labels ((exercise ()
               (let ((root (cl-weave::make-suite :name "root"))
                     (include-cycle (list #P"/tmp/cl-weave/include-cycle/"))
                     (coverage-require 0)
                     (coverage-reset 0)
                     (coverage-cleanup 0)
                     (suite-root 0)
                     (suite-snapshot 0)
                     (executed 0)
                     (artifact 0))
                 (setf (cdr include-cycle) include-cycle)
                 (cl-weave::add-child
                  root
                  (cl-weave::make-test-case
                   :name "runs"
                   :function (lambda () (incf executed))))
                 (with-mocked-functions
                     (((symbol-function 'cl-weave::require-coverage-support)
                       (lambda () (incf coverage-require)))
                      ((symbol-function 'cl-weave:reset-coverage)
                       (lambda () (incf coverage-reset)))
                      ((symbol-function 'cl-weave:coverage-statistics)
                       (lambda (&key include-pathnames exclude-pathnames)
                         (declare (ignore include-pathnames exclude-pathnames))
                         (incf coverage-cleanup)))
                      ((symbol-function 'cl-weave::save-coverage-report)
                       (lambda (path &key include-pathnames exclude-pathnames)
                         (declare (ignore path include-pathnames exclude-pathnames))
                         (incf artifact)))
                      ((symbol-function 'cl-weave:save-coverage)
                       (lambda (path)
                         (declare (ignore path))
                         (incf artifact)))
                      ((symbol-function 'cl-weave:root-suite)
                       (lambda ()
                         (incf suite-root)
                         root))
                      ((symbol-function 'cl-weave::snapshot-suite)
                       (lambda (suite)
                         (incf suite-snapshot)
                         suite)))
                   (expect
                    (cl-weave:run-all
                     :reporter :sexp
                     :stream (make-broadcast-stream)
                     :coverage nil
                     :coverage-output 42
                     :coverage-report-directory 42
                     :coverage-reset :arbitrary
                     :coverage-include-pathnames include-cycle
                     :coverage-exclude-pathnames
                     (cons #P"/tmp/cl-weave/exclude/" :tail)
                     :coverage-minimum-expression #C(1 1)
                     :coverage-minimum-branch 101)
                    :to-be-truthy))
                 (expect coverage-require :to-be 0)
                 (expect coverage-reset :to-be 0)
                 (expect coverage-cleanup :to-be 0)
                 (expect suite-root :to-be 1)
                 (expect suite-snapshot :to-be 1)
                 (expect executed :to-be 1)
                 (expect artifact :to-be 0))))
      #+sbcl
      (sb-ext:with-timeout 10
        (exercise))
      #-sbcl
      (exercise))))


(describe "coverage input preflight"
  (it "validates coverage options before lifecycle suite and artifacts"
    (labels ((exercise ()
               (let* ((root (cl-weave::make-suite :name "root"))
                      (limit cl-weave::+maximum-selection-filter-count+)
                      (include-cycle (list #P"/tmp/cl-weave/include-cycle/"))
                      (coverage-require 0)
                      (coverage-reset 0)
                      (coverage-cleanup 0)
                      (suite-root 0)
                      (suite-snapshot 0)
                      (executed 0)
                      (artifact 0))
                 (setf (cdr include-cycle) include-cycle)
                 (cl-weave::add-child
                  root
                  (cl-weave::make-test-case
                   :name "must not run"
                   :function (lambda () (incf executed))))
                 (with-mocked-functions
                     (((symbol-function 'cl-weave::require-coverage-support)
                       (lambda () (incf coverage-require)))
                      ((symbol-function 'cl-weave:reset-coverage)
                       (lambda () (incf coverage-reset)))
                      ((symbol-function 'cl-weave:coverage-statistics)
                       (lambda (&key include-pathnames exclude-pathnames)
                         (declare (ignore include-pathnames exclude-pathnames))
                         (incf coverage-cleanup)
                         '(:expression-covered 0 :expression-total 0
                           :branch-covered 0 :branch-total 0)))
                      ((symbol-function 'cl-weave::save-coverage-report)
                       (lambda (path &key include-pathnames exclude-pathnames)
                         (declare (ignore path include-pathnames exclude-pathnames))
                         (incf artifact)))
                      ((symbol-function 'cl-weave:save-coverage)
                       (lambda (path)
                         (declare (ignore path))
                         (incf artifact)))
                      ((symbol-function 'cl-weave:root-suite)
                       (lambda ()
                         (incf suite-root)
                         root))
                      ((symbol-function 'cl-weave::snapshot-suite)
                       (lambda (suite)
                         (incf suite-snapshot)
                         suite)))
                   (dolist (arguments
                            (list
                             (list :coverage-output 42)
                             (list :coverage-report-directory 42)
                             (list :coverage-minimum-expression -1)
                             (list :coverage-minimum-branch 101)
                             (list :coverage-minimum-expression #C(1 1))
                             #+sbcl
                             (list :coverage-minimum-expression
                                   (sb-kernel:make-double-float #x7ff00000 0))
                             (list :coverage-report-directory "unused-report/"
                                   :coverage-include-pathnames include-cycle)
                             (list :coverage-minimum-expression 0
                                   :coverage-exclude-pathnames
                                   (cons #P"/tmp/cl-weave/exclude/" :tail))
                             (list :coverage-report-directory "unused-report/"
                                   :coverage-include-pathnames
                                   (make-list (1+ limit)
                                              :initial-element
                                              #P"/tmp/cl-weave/include/"))
                             (list :coverage-minimum-branch 100
                                   :coverage-exclude-pathnames (list 42))))
                     (expect
                      (lambda ()
                        (apply #'cl-weave:run-all
                               :reporter :sexp
                               :stream (make-broadcast-stream)
                               :coverage :enabled
                               arguments))
                      :to-throw)))
                 (expect coverage-require :to-be 0)
                 (expect coverage-reset :to-be 0)
                 (expect coverage-cleanup :to-be 0)
                 (expect suite-root :to-be 0)
                 (expect suite-snapshot :to-be 0)
                 (expect executed :to-be 0)
                 (expect artifact :to-be 0))))
      #+sbcl
      (sb-ext:with-timeout 10
        (exercise))
      #-sbcl
      (exercise))))


(defun exercise-coverage-report-failure (finder)
  (let ((directory (make-test-temporary-directory "coverage-report-failure"))
        (cl-weave::*coverage-report-finder* finder))
    (handler-case
        (progn
          (cl-weave::save-coverage-report directory)
          nil)
      (error (condition)
        condition))))

(describe "coverage"
  (it "filters coverage sources with exclusions taking precedence"
    (let* ((root (make-test-temporary-directory "coverage-filter"))
           (included (merge-pathnames #P"src/included.lisp" root))
           (excluded-directory (merge-pathnames #P"src/generated/" root))
           (excluded (merge-pathnames #P"generated.lisp" excluded-directory))
           (matcher (cl-weave::coverage-source-matcher
                     (list (merge-pathnames #P"src/" root))
                     (list excluded-directory))))
      (expect (funcall matcher included) :to-be-truthy)
      (expect (funcall matcher excluded) :to-be nil)))

  (it "accepts zero-item coverage and rejects unmet thresholds"
    (expect (cl-weave::check-coverage-thresholds
             '(:expression-covered 0 :expression-total 0
               :branch-covered 0 :branch-total 0)
             100 100)
            :to-be-truthy)
    (expect (lambda ()
              (cl-weave::check-coverage-thresholds
               '(:expression-covered 7 :expression-total 10
                 :branch-covered 8 :branch-total 10)
               75 80))
            :to-throw "Coverage threshold failed"))

  (it "enforces thresholds without requiring an HTML report"
    (with-mocked-functions
        (((symbol-function 'cl-weave::require-coverage-support) (lambda () t))
         ((symbol-function 'cl-weave:reset-coverage) (lambda () t))
         ((symbol-function 'cl-weave:coverage-statistics)
          (lambda (&key include-pathnames exclude-pathnames)
            (declare (ignore include-pathnames exclude-pathnames))
            '(:expression-covered 1 :expression-total 2
              :branch-covered 1 :branch-total 2))))
      (expect (lambda ()
                (cl-weave::call-with-coverage
                 t nil nil t (lambda () t)
                 :minimum-expression 75))
              :to-throw "Coverage threshold failed")))

  (it "reports coverage support as a safe boolean"
    (expect (cl-weave:coverage-support-available-p)
            :to-satisfy (lambda (value)
                          (or (eq value t) (eq value nil)))))

  (it "does not initialize or save coverage when coverage is disabled"
    (let ((calls nil))
      (with-mocked-functions
          (((symbol-function 'cl-weave::require-coverage-support)
            (lambda ()
              (push :require calls)))
           ((symbol-function 'cl-weave::save-coverage-report)
            (lambda (path)
              (push (list :report path) calls)))
           ((symbol-function 'cl-weave:save-coverage)
            (lambda (path)
              (push (list :save path) calls))))
        (expect (multiple-value-list
                 (cl-weave::call-with-coverage
                  nil "coverage.dat" "coverage-report/" t
                  (lambda ()
                    (values :first :second))))
                :to-equal '(:first :second)))
      (expect calls :to-be-null)))

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

  (it "generates a populated HTML coverage report when requested"
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
           ((symbol-function 'cl-weave::save-coverage-report)
            (lambda (path)
              (push (list :report path) calls)
              path))
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
                     :coverage-report-directory "coverage-report/"
                     :coverage-output "coverage.dat")
                    :to-be-truthy))))
      (expect (reverse calls)
              :to-equal '(:require :reset :test
                          (:report "coverage-report/")
                          (:save "coverage.dat")))))

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
              :to-equal '(:require :test (:save "coverage.dat")))))

  (it "saves coverage when the covered run errors"
    (let ((calls nil))
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
        (expect (lambda ()
                  (cl-weave::call-with-coverage
                   t
                   "coverage.dat"
                   nil
                   t
                   (lambda ()
                     (push :body calls)
                     (error "boom"))))
                :to-throw "boom"))
      (expect (reverse calls)
              :to-equal '(:require :reset :body (:save "coverage.dat")))))

  (it "attempts the sidecar after an HTML report failure"
    (let ((calls nil))
      (with-mocked-functions
          (((symbol-function 'cl-weave::require-coverage-support)
            (lambda () t))
           ((symbol-function 'cl-weave::save-coverage-report)
            (lambda (path)
              (push (list :report path) calls)
              (error "report failed")))
           ((symbol-function 'cl-weave:save-coverage)
            (lambda (path)
              (push (list :save path) calls)
              path)))
        (expect (lambda ()
                  (cl-weave::call-with-coverage
                   t "coverage.dat" "coverage-report/" nil
                   (lambda () :result)))
                :to-throw "Coverage cleanup failed"))
      (expect (reverse calls)
              :to-equal '((:report "coverage-report/")
                          (:save "coverage.dat")))))

  (it "allows callers to explicitly ignore cleanup failures"
    (with-mocked-functions
        (((symbol-function 'cl-weave::require-coverage-support)
          (lambda () t))
         ((symbol-function 'cl-weave:save-coverage)
          (lambda (path)
            (declare (ignore path))
            (error "sidecar failed"))))
      (handler-bind
          ((cl-weave::coverage-cleanup-failure
             (lambda (condition)
               (declare (ignore condition))
               (invoke-restart 'cl-weave::ignore-coverage-cleanup-failure))))
        (expect (cl-weave::call-with-coverage
                 t "coverage.dat" nil nil
                 (lambda () :result))
                :to-equal :result))))

  (it "preserves the primary error while reporting cleanup failures"
    (let ((observed-cleanup nil))
      (with-mocked-functions
          (((symbol-function 'cl-weave::require-coverage-support)
            (lambda () t))
           ((symbol-function 'cl-weave::save-coverage-report)
            (lambda (path)
              (declare (ignore path))
              (error "report failed")))
           ((symbol-function 'cl-weave:save-coverage)
            (lambda (path)
              (declare (ignore path))
              (error "sidecar failed"))))
        (handler-bind
            ((cl-weave::coverage-cleanup-failure
               (lambda (condition)
                 (setf observed-cleanup condition))))
          (expect (lambda ()
                    (cl-weave::call-with-coverage
                     t "coverage.dat" "coverage-report/" nil
                     (lambda ()
                       (error "primary failed"))))
                  :to-throw "primary failed")))
      (expect observed-cleanup :to-be-truthy)
      (expect (mapcar #'car
                      (cl-weave::coverage-cleanup-failures observed-cleanup))
              :to-equal '(:report :data))))

  (it "runs every cleanup without replacing a non-local exit"
    (let ((calls nil)
          (observed-cleanup nil))
      (with-mocked-functions
          (((symbol-function 'cl-weave::require-coverage-support)
            (lambda () t))
           ((symbol-function 'cl-weave::save-coverage-report)
            (lambda (path)
              (push (list :report path) calls)
              (error "report failed")))
           ((symbol-function 'cl-weave:save-coverage)
            (lambda (path)
              (push (list :save path) calls)
              path)))
        (handler-bind
            ((cl-weave::coverage-cleanup-failure
               (lambda (condition)
                 (setf observed-cleanup condition))))
          (expect (catch 'covered-exit
                    (cl-weave::call-with-coverage
                     t "coverage.dat" "coverage-report/" nil
                     (lambda ()
                       (push :body calls)
                       (throw 'covered-exit :escaped))))
                  :to-equal :escaped)))
      (expect (reverse calls)
              :to-equal '(:body
                          (:report "coverage-report/")
                          (:save "coverage.dat")))
      (expect observed-cleanup :to-be-truthy)))

  (it "defines report failures from data"
    (loop for (name finder expected-type message)
            in `((:report-unavailable
                  ,(lambda (name)
                     (declare (ignore name))
                     nil)
                  cl-weave:coverage-unavailable
                  "SB-COVER:REPORT is not available")
                 (:index-missing
                  ,(lambda (name)
                     (declare (ignore name))
                     (lambda (directory)
                       (declare (ignore directory))))
                  error
                  "did not produce")
                 (:report-error
                  ,(lambda (name)
                     (declare (ignore name))
                     (lambda (directory)
                       (declare (ignore directory))
                       (error "report generation failed")))
                  error
                  "report generation failed"))
          for condition = (exercise-coverage-report-failure finder)
          do (expect condition :to-satisfy
                     (lambda (value)
                       (typep value expected-type)))
             (expect (princ-to-string condition) :to-contain message)))

  (it "rejects empty HTML coverage reports"
    (let ((directory (make-test-temporary-directory "coverage-report")))
      (let ((cl-weave::*coverage-report-finder*
              (lambda (name)
                (expect name :to-equal "REPORT")
                (lambda (pathname)
                  (ensure-directories-exist (merge-pathnames #P"cover-index.html"
                                                             pathname))
                  (with-open-file (stream (merge-pathnames #P"cover-index.html"
                                                           pathname)
                                          :direction :output
                                          :if-exists :supersede
                                          :if-does-not-exist :create)
                    (write-line "<h3>No code coverage data found.</h3>" stream))
                  pathname))))
        (expect (lambda ()
                  (cl-weave::save-coverage-report directory))
                :to-throw "Coverage report at")))))
