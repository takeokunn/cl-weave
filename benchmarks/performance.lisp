(require :asdf)

(let* ((directory (uiop:pathname-directory-pathname *load-truename*))
       (system-file (merge-pathnames "../cl-weave.asd" directory)))
  (asdf:load-asd system-file)
  (asdf:load-system "cl-weave"))

(defpackage #:cl-weave/benchmarks (:use #:cl))

(in-package #:cl-weave/benchmarks)

(defparameter *warmup-count* 3)

(defparameter *sample-count* 9)

(defparameter *calibration-target-seconds* 0.05d0)

(defparameter *maximum-iterations* 1048576)

(defvar *blackhole* nil)

(defun elapsed-seconds (start end)
  (/ (- end start) (coerce internal-time-units-per-second 'double-float)))

(defun invoke-n (function iterations)
  (loop repeat iterations
        do (setf *blackhole* (funcall function))))

(defun calibrate-iterations (function)
  (loop with iterations = 1
        do (let ((start (get-internal-real-time)))
      (invoke-n function iterations)
      (let ((elapsed (elapsed-seconds start (get-internal-real-time))))
        (when (or
            (>= elapsed *calibration-target-seconds*)
            (>= iterations *maximum-iterations*))
          (return iterations))
        (setf iterations (min *maximum-iterations* (* iterations 2)))))))

(defun median (numbers)
  (let* ((sorted (sort (copy-list numbers) #'<))
         (count (length sorted))
         (middle (floor count 2)))
    (if (oddp count) (nth middle sorted)
      (/ (+ (nth (1- middle) sorted) (nth middle sorted)) 2))))

(defun measure-sample (function iterations)
  (sb-ext:gc :full t)
  (let ((bytes-before (sb-ext:get-bytes-consed))
        (start (get-internal-real-time)))
    (invoke-n function iterations)
    (let ((elapsed (elapsed-seconds start (get-internal-real-time)))
          (bytes (- (sb-ext:get-bytes-consed) bytes-before)))
      (values
        (/ (* elapsed 1000000000d0) iterations)
        (/ (coerce bytes 'double-float) iterations)))))

(defun benchmark (name problem-size function)
  (loop repeat *warmup-count*
        do (funcall function))
  (let ((iterations (calibrate-iterations function))
        (time-samples nil)
        (allocation-samples nil))
    (loop repeat *sample-count*
          do (multiple-value-bind (nanoseconds bytes) (measure-sample function iterations)
        (push nanoseconds time-samples)
        (push bytes allocation-samples)))
    (format
      t
      "~S~%"
      (list
        :benchmark
        name
        :problem-size
        problem-size
        :iterations
        iterations
        :warmup
        *warmup-count*
        :samples
        *sample-count*
        :median-ns/op
        (median time-samples)
        :minimum-ns/op
        (reduce #'min time-samples)
        :median-bytes/op
        (median allocation-samples)))))

(defun make-suite-fixture (&key (suite-count 32) (tests-per-suite 32))
  (let ((root (cl-weave::make-suite :name "benchmark root")))
    (loop for suite-index below suite-count
          for suite = (cl-weave::make-suite :name (format nil "suite-~D" suite-index) :parent root)
          do (cl-weave::add-child root suite) (loop for test-index below tests-per-suite
            do (cl-weave::add-child
          suite
          (cl-weave::make-test-case
            :name
            (format nil "test-~D" test-index)
            :function
            (lambda ()
              nil)))))
    root))

(defun make-random-order-fixture (count)
  (let ((suite (cl-weave::make-suite :name "ordered children")))
    (loop for index below
          count
          do (cl-weave::add-child
        suite
        (cl-weave::make-test-case
          :name
          (format nil "child-~6,'0D" index)
          :function
          (lambda ()
            nil))))
    suite))

(defun make-event-fixture (count)
  (let ((statuses #(:pass :skip :todo :fail :error)))
    (loop for index below
          count
          for status = (aref statuses (mod index (length statuses)))
          collect (cl-weave::make-test-event
        :status
        status
        :path
        (list "benchmark" (format nil "event-~D" index))
        :elapsed-internal-time
        0))))

(defun make-plan-fixture (count)
  (let ((statuses #(:run :skip :todo)))
    (loop for index below
          count
          collect (cl-weave::make-test-plan-entry
        :status
        (aref statuses (mod index (length statuses)))
        :path
        (list "benchmark" (format nil "plan-~D" index))))))

(defun make-concurrency-fixture (count)
  (let ((suite (cl-weave::make-suite :name "concurrency")))
    (values
      suite
      (loop for index below
            count
            collect (cl-weave::make-test-case
          :name
          (format nil "worker-~D" index)
          :execution-mode
          :concurrent
          :function
          (lambda ()
            nil))))))

(defun run-benchmarks ()
  (let* ((*print-pretty* nil)
         (suite-tree (make-suite-fixture))
         (ordered-suite (make-random-order-fixture 2048))
         (ordered-children (cl-weave::suite-children ordered-suite))
         (events (make-event-fixture 4096))
         (plan (make-plan-fixture 4096)))
    (format
      t
      "~S~%"
      (list
        :format-version
        1
        :implementation
        (lisp-implementation-type)
        :implementation-version
        (lisp-implementation-version)
        :machine
        (machine-type)))
    (benchmark
      "clone-suite-tree-unlocked"
      '(:suites 33 :tests 1024)
      (lambda ()
        (cl-weave::clone-suite-tree-unlocked suite-tree)))
    (benchmark
      "snapshot-suite"
      '(:suites 33 :tests 1024)
      (lambda ()
        (cl-weave::snapshot-suite suite-tree)))
    (benchmark
      "ordered-children/random"
      '(:children 2048 :seed 8675309)
      (lambda ()
        (let ((cl-weave::*test-sequence-order* :random)
              (cl-weave::*test-sequence-seed* 8675309))
          (cl-weave::ordered-children ordered-suite ordered-children))))
    (benchmark
      "result-summary"
      '(:events 4096)
      (lambda ()
        (cl-weave::result-summary events)))
    (benchmark
      "plan-summary"
      '(:entries 4096)
      (lambda ()
        (cl-weave::plan-summary plan)))
    (multiple-value-bind (suite tests) (make-concurrency-fixture 32)
      (benchmark
        "runner-concurrency/8-workers"
        (quote (:tests 32 :max-workers 8))
        (lambda ()
          (let ((cl-weave::*max-workers* 8))
            (cl-weave::run-concurrent-test-cases suite tests))))
      (benchmark
        "runner-concurrency/1-worker"
        (quote (:tests 32 :max-workers 1))
        (lambda ()
          (let ((cl-weave::*max-workers* 1))
            (cl-weave::run-concurrent-test-cases suite tests)))))))

(run-benchmarks)
