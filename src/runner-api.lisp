(in-package #:cl-weave)

(defun passed-event-p (event)
  (member (test-event-status event) '(:pass :skip :todo)))

(define-condition coverage-unavailable (error)
  ((reason :initarg :reason :reader coverage-unavailable-reason))
  (:report (lambda (condition stream)
             (format stream "Coverage support is unavailable: ~A"
                     (coverage-unavailable-reason condition)))))

;; The base is a plain CONDITION, not an ERROR: during unwinds the cleanup
;; failure is SIGNALed as a notification, and an ERROR subtype would be
;; captured by enclosing ERROR handlers (matchers, the runner), replacing
;; the primary control transfer.
(define-condition coverage-cleanup-failure (condition)
  ((failures :initarg :failures :reader coverage-cleanup-failures))
  (:report (lambda (condition stream)
             (format stream "Coverage cleanup failed: ~{~A~^; ~}"
                     (mapcar #'cdr (coverage-cleanup-failures condition))))))

;; When no control transfer is in flight the same failure is a real error.
(define-condition coverage-cleanup-error (coverage-cleanup-failure error) ())

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

(defun coverage-report-empty-p (pathname)
  (with-open-file (stream pathname :direction :input)
    (loop for line = (read-line stream nil nil)
          while line
          thereis (search "No code coverage data found." line))))

(defparameter *coverage-report-finder* #'coverage-fbound-symbol)

(defun coverage-source-matcher (include-pathnames exclude-pathnames)
  (labels ((normalized (pathname)
             (namestring (uiop:ensure-absolute-pathname pathname)))
           (matches-p (source candidate)
             (let ((candidate (normalized candidate)))
               (or (string= source candidate)
                   (and (uiop:directory-pathname-p (pathname candidate))
                        (uiop:string-prefix-p candidate source))))))
    (let ((includes (mapcar #'normalized include-pathnames))
          (excludes (mapcar #'normalized exclude-pathnames)))
      (lambda (source)
        (let ((source (normalized source)))
          (and (or (null includes)
                   (some (lambda (candidate) (matches-p source candidate)) includes))
               (not (some (lambda (candidate) (matches-p source candidate)) excludes))))))))

(defun coverage-internal-symbol (name &optional required-p)
  (let ((package (find-package "SB-COVER")))
    (multiple-value-bind (symbol status)
        (and package (find-symbol name package))
      (if status
          symbol
          (when required-p
            (error 'coverage-unavailable
                   :reason (format nil "SB-COVER internal ~A is not available." name)))))))

(defun coverage-statistics (&key include-pathnames exclude-pathnames)
  (let ((refresh (coverage-internal-symbol "REFRESH-COVERAGE-BITS" t))
        (coverage-info (coverage-internal-symbol "*CODE-COVERAGE-INFO*" t))
        (compute (coverage-internal-symbol "COMPUTE-FILE-INFO" t))
        (ok-of (coverage-internal-symbol "OK-OF" t))
        (all-of (coverage-internal-symbol "ALL-OF" t))
        (matcher (coverage-source-matcher include-pathnames exclude-pathnames))
        (expression-covered 0)
        (expression-total 0)
        (branch-covered 0)
        (branch-total 0))
    (funcall refresh)
    (maphash
     (lambda (source ignored)
       (declare (ignore ignored))
       (when (and (funcall matcher source) (probe-file source))
         (multiple-value-bind (counts)
             (funcall compute source :default)
           (incf expression-covered (funcall ok-of (getf counts :expression)))
           (incf expression-total (funcall all-of (getf counts :expression)))
           (incf branch-covered (funcall ok-of (getf counts :branch)))
           (incf branch-total (funcall all-of (getf counts :branch))))))
     (let ((value (and (boundp coverage-info) (symbol-value coverage-info))))
       (unless (and (consp value) (hash-table-p (car value)))
         (error 'coverage-unavailable
                :reason "SB-COVER coverage data has an unsupported representation."))
       (car value)))
    (list :expression-covered expression-covered
          :expression-total expression-total
          :branch-covered branch-covered
          :branch-total branch-total)))

(defun coverage-percentage (covered total)
  (if (zerop total) 100.0 (* 100.0 (/ covered total))))

(defun check-coverage-thresholds (statistics minimum-expression minimum-branch)
  (loop for (kind minimum covered-key total-key)
          in `((:expression ,minimum-expression :expression-covered :expression-total)
               (:branch ,minimum-branch :branch-covered :branch-total))
        when minimum
          do (let ((actual (coverage-percentage (getf statistics covered-key)
                                                (getf statistics total-key))))
               (when (< actual minimum)
                 (error "Coverage threshold failed for ~A: ~,2F% is below ~,2F%."
                        kind actual minimum))))
  statistics)

(defun save-coverage-report (pathname &key include-pathnames exclude-pathnames)
  (let* ((directory (pathname pathname))
         (index-path (merge-pathnames #P"cover-index.html" directory))
         (matcher (coverage-source-matcher include-pathnames exclude-pathnames)))
    (ensure-directories-exist index-path)
    (let ((report (funcall *coverage-report-finder* "REPORT")))
      (unless report
        (error 'coverage-unavailable :reason "SB-COVER:REPORT is not available."))
      (if (or include-pathnames exclude-pathnames)
          (funcall report directory :if-matches matcher)
          (funcall report directory)))
    (unless (probe-file index-path)
      (error "Coverage report at ~A did not produce ~A." directory index-path))
    (when (coverage-report-empty-p index-path)
      (error "Coverage report at ~A did not capture any coverage data." index-path))
    directory))

(defun collect-coverage-cleanup-failures (coverage-report-directory coverage-output
                                          include-pathnames exclude-pathnames
                                          minimum-expression minimum-branch)
  (loop for (kind pathname saver)
            in `((:report ,coverage-report-directory
                          ,(lambda (path)
                             (if (or include-pathnames exclude-pathnames)
                                 (save-coverage-report
                                  path
                                  :include-pathnames include-pathnames
                                  :exclude-pathnames exclude-pathnames)
                                 (save-coverage-report path))))
                 (:threshold ,(or minimum-expression minimum-branch)
                             ,(lambda (ignored)
                                (declare (ignore ignored))
                                (check-coverage-thresholds
                                 (coverage-statistics
                                  :include-pathnames include-pathnames
                                  :exclude-pathnames exclude-pathnames)
                                 minimum-expression minimum-branch)))
                 (:data ,coverage-output ,#'save-coverage))
        when pathname
          append (handler-case
                     (progn
                       (funcall saver pathname)
                       nil)
                   (error (condition)
                     (list (cons kind condition))))))

(defun handle-coverage-cleanup-failures (failures preserve-control-transfer-p)
  (when failures
    (if preserve-control-transfer-p
        (signal 'coverage-cleanup-failure :failures failures)
        (let ((threshold-failure (assoc :threshold failures)))
          (when threshold-failure
            (error (cdr threshold-failure)))
          (restart-case
              (error 'coverage-cleanup-error :failures failures)
            (ignore-coverage-cleanup-failure ()
              :report "Ignore failures while saving coverage artifacts."))))))

(defun call-with-coverage (coverage coverage-output coverage-report-directory coverage-reset thunk
                          &key include-pathnames exclude-pathnames
                            minimum-expression minimum-branch)
  (if coverage
      (progn
        (require-coverage-support)
        (when coverage-reset
          (reset-coverage))
        (let ((completed-p nil)
              (primary-error nil))
          (unwind-protect
               (handler-case
                   (multiple-value-prog1 (funcall thunk)
                     (setf completed-p t))
                 (error (condition)
                   (setf primary-error condition)
                   (error condition)))
            (handle-coverage-cleanup-failures
             (collect-coverage-cleanup-failures coverage-report-directory
                                                coverage-output
                                                include-pathnames exclude-pathnames
                                                minimum-expression minimum-branch)
             (or primary-error (not completed-p))))))
      (funcall thunk)))

(defparameter *run-reporters*
  '(:spec :sexp :json :jsonl :tap :github :junit))

(defparameter *list-reporters* '(:spec :sexp :json :jsonl))

(defun run-reporters ()
  (copy-list *run-reporters*))

(defun list-reporters ()
  (copy-list *list-reporters*))

(defun ensure-run-reporter (reporter)
  (unless (member reporter (run-reporters))
    (error "cl-weave: run mode supports spec, sexp, json, jsonl, tap, github, and junit reporters."))
  reporter)

(defun ensure-list-reporter (reporter)
  (unless (member reporter (list-reporters))
    (error "cl-weave: list mode supports spec, sexp, json, and jsonl reporters."))
  reporter)

(defun emit-run-report (reporter events stream)
  (when reporter
    (ensure-run-reporter reporter)
    (ecase reporter
      (:spec (report-spec events stream))
      (:sexp (report-sexp events stream))
      (:json (report-json events stream))
      (:jsonl (report-jsonl events stream))
      (:tap (report-tap events stream))
      (:github (report-github events stream))
      (:junit (report-junit events stream)))))

(defun find-suite-by-designator (suite-designator &optional (suite (root-suite)))
  (let ((target (named-suite-key suite-designator)))
    (labels ((walk (node)
               (when (suite-p node)
                 (or (and (equal (named-suite-key (suite-name node)) target)
                          node)
                     (loop for child in (suite-children node)
                           thereis (and (suite-p child)
                                        (walk child)))))))
      (walk suite))))

(defun resolve-suite-designator (suite-designator)
  (cond
    ((null suite-designator) (root-suite))
    ((suite-p suite-designator) suite-designator)
    (t
     (let* ((key (named-suite-key suite-designator))
            (suite (or (gethash key *named-suites*)
                       (find-suite-by-designator suite-designator))))
       (when suite
         (setf (gethash key *named-suites*) suite))
       (or suite
           (error "cl-weave: unknown suite designator ~S." suite-designator))))))

(defun normalize-run-results (results)
  (labels ((collect (value acc)
             (cond
               ((null value) acc)
               ((test-event-p value) (cons value acc))
               ((consp value) (collect (car value)
                                       (collect (cdr value) acc)))
               (t
                (error "cl-weave: expected test events or nested event lists, got ~S."
                       value)))))
    (nreverse (collect results '()))))

(defun run (suite-designator
            &key reporter
              (stream *standard-output*)
              (name-filter *test-name-filter*)
              location-filter
              include-tags
              exclude-tags
              shard
              order
              seed
              bail
              retry
              timeout-ms
              max-workers)
  (let ((events (collect-events
                 (resolve-suite-designator suite-designator)
                 :name-filter name-filter
                 :location-filter location-filter
                 :include-tags include-tags
                 :exclude-tags exclude-tags
                 :shard shard
                 :order order
                 :seed seed
                 :bail bail
                 :retry retry
                 :timeout-ms timeout-ms
                 :max-workers max-workers)))
    (emit-run-report reporter events stream)
    events))

(defun explain! (results &optional (stream *standard-output*))
  (report-spec (normalize-run-results results) stream)
  (values))

(defun results-status (results)
  (every #'passed-event-p (normalize-run-results results)))

(defun run-all (&key (reporter :spec)
                  (stream *standard-output*)
                  (name-filter *test-name-filter*)
                  location-filter
                  test-path-filter
                  include-tags
                  exclude-tags
                  shard
                  order
                  seed
                  bail
                  retry
                  timeout-ms
                  max-workers
                  coverage
                  coverage-output
                  coverage-report-directory
                  coverage-include-pathnames
                  coverage-exclude-pathnames
                  coverage-minimum-expression
                  coverage-minimum-branch
                  (pass-with-no-tests t)
                  (coverage-reset t))
  (ensure-run-reporter reporter)
  (call-with-coverage
   coverage
   coverage-output
   coverage-report-directory
   coverage-reset
   (lambda ()
     (let ((events (collect-events
                    (root-suite)
                    :name-filter name-filter
                    :location-filter location-filter
                    :test-path-filter test-path-filter
                    :include-tags include-tags
                    :exclude-tags exclude-tags
                    :shard shard
                    :order order
                    :seed seed
                    :bail bail
                    :retry retry
                    :timeout-ms timeout-ms
                    :max-workers max-workers)))
       (emit-run-report reporter events stream)
       (and (or pass-with-no-tests events)
            (every #'passed-event-p events))))
   :include-pathnames coverage-include-pathnames
   :exclude-pathnames coverage-exclude-pathnames
   :minimum-expression coverage-minimum-expression
   :minimum-branch coverage-minimum-branch))

(defun list-tests (&key (reporter :spec)
                     (stream *standard-output*)
                     (name-filter *test-name-filter*)
                     location-filter
                     include-tags
                     exclude-tags
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
               :include-tags include-tags
               :exclude-tags exclude-tags
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
