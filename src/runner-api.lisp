(in-package #:cl-weave)

(defun passed-event-p (event)
  (member (test-event-status event) '(:pass :skip :todo)))

(define-condition coverage-unavailable (error)
  ((reason :initarg :reason :reader coverage-unavailable-reason))
  (:report (lambda (condition stream)
             (format stream "Coverage support is unavailable: ~A"
                     (coverage-unavailable-reason condition)))))

(defun coverage-fbound-symbol (name &optional required-p)
  (let ((package (find-package "SB-COVER")))
    (unless package
      (when required-p
        (error 'coverage-unavailable :reason "SB-COVER is not loaded.")))
    (when package
      (multiple-value-bind (symbol status)
          (find-symbol name package)
        (if (and status (fboundp symbol))
            symbol
            (when required-p
              (error 'coverage-unavailable
                     :reason (format nil "SB-COVER:~A is not available." name))))))))

(defun require-coverage-support ()
  #+sbcl
  (handler-case
      (progn
        (require :sb-cover)
        (coverage-fbound-symbol "RESET-COVERAGE" t)
        (coverage-fbound-symbol "SAVE-COVERAGE-IN-FILE" t)
        t)
    (coverage-unavailable (condition)
      (error condition))
    (error (condition)
      (error 'coverage-unavailable :reason condition)))
  #-sbcl
  (error 'coverage-unavailable :reason "Coverage requires SBCL sb-cover."))

(defun coverage-support-available-p ()
  #+sbcl
  (handler-case
      (handler-bind ((warning #'muffle-warning))
        (require-coverage-support))
    (condition ()
      nil))
  #-sbcl
  nil)

(defun reset-coverage ()
  (require-coverage-support)
  (funcall (coverage-fbound-symbol "RESET-COVERAGE" t))
  t)

(defun save-coverage (pathname)
  (require-coverage-support)
  (funcall (coverage-fbound-symbol "SAVE-COVERAGE-IN-FILE" t) pathname)
  pathname)

(defun call-with-coverage (coverage coverage-output coverage-reset thunk)
  (if coverage
      (progn
        (require-coverage-support)
        (when coverage-reset
          (reset-coverage))
        (unwind-protect
             (funcall thunk)
          (when coverage-output
            (save-coverage coverage-output))))
      (funcall thunk)))

(defparameter *reporter-aliases*
  '((:spec "spec")
    (:sexp "sexp")
    (:json "json")
    (:jsonl "jsonl" "ndjson")
    (:tap "tap")
    (:github "github")
    (:junit "junit")))

(defparameter *run-reporters* (mapcar #'first *reporter-aliases*))

(defparameter *list-reporters* '(:spec :sexp :json :jsonl))

(defun ensure-run-reporter (reporter)
  (unless (member reporter *run-reporters*)
    (error "cl-weave: run mode supports spec, sexp, json, jsonl, tap, github, and junit reporters."))
  reporter)

(defun ensure-list-reporter (reporter)
  (unless (member reporter *list-reporters*)
    (error "cl-weave: list mode supports spec, sexp, json, and jsonl reporters."))
  reporter)

(defun run-all (&key (reporter :spec)
                  (stream *standard-output*)
                  (name-filter *test-name-filter*)
                  location-filter
                  shard
                  order
                  seed
                  bail
                  retry
                  timeout-ms
                  max-workers
                  coverage
                  coverage-output
                  (pass-with-no-tests t)
                  (coverage-reset t))
  (ensure-run-reporter reporter)
  (call-with-coverage
   coverage
   coverage-output
   coverage-reset
   (lambda ()
     (let ((events (collect-events
                    (root-suite)
                    :name-filter name-filter
                    :location-filter location-filter
                    :shard shard
                    :order order
                    :seed seed
                    :bail bail
                    :retry retry
                    :timeout-ms timeout-ms
                    :max-workers max-workers)))
       (ecase reporter
         (:spec (report-spec events stream))
         (:sexp (report-sexp events stream))
         (:json (report-json events stream))
         (:jsonl (report-jsonl events stream))
         (:tap (report-tap events stream))
         (:github (report-github events stream))
         (:junit (report-junit events stream)))
       (and (or pass-with-no-tests events)
            (every #'passed-event-p events))))))

(defun list-tests (&key (reporter :spec)
                     (stream *standard-output*)
                     (name-filter *test-name-filter*)
                     location-filter
                     shard
                     order
                     seed
                     retry
                     timeout-ms)
  (ensure-list-reporter reporter)
  (let ((plan (collect-test-plan
               (root-suite)
               :name-filter name-filter
               :location-filter location-filter
               :shard shard
               :order order
               :seed seed
               :retry retry
               :timeout-ms timeout-ms)))
    (ecase reporter
      (:spec (report-plan-spec plan stream))
      (:sexp (report-plan-sexp plan stream))
      (:json (report-plan-json plan stream))
      (:jsonl (report-plan-jsonl plan stream)))
    plan))
