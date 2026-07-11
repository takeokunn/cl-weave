(in-package #:cl-weave/tests)

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
