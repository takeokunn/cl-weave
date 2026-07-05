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
                   t
                   (lambda ()
                     (push :body calls)
                     (error "boom"))))
                :to-throw "boom"))
      (expect (reverse calls)
              :to-equal '(:require :reset :body (:save "coverage.dat"))))))

