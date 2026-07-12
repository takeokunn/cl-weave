(in-package #:cl-weave/tests)

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
