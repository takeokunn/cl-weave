(in-package #:cl-weave)

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

(defstruct coverage-options
  output
  report-directory
  reset
  include-pathnames
  exclude-pathnames
  minimum-expression
  minimum-branch)

(defun normalize-coverage-pathname-designator (value description)
  (when value
    (cond
      ((pathnamep value)
       (make-pathname :defaults value))
      ((stringp value)
       (copy-seq value))
      (t
       (error "cl-weave: ~A must be a pathname designator or NIL."
              description)))))

(defun valid-coverage-threshold-p (value)
  (handler-case
      (and (realp value)
           (= value value)
           (<= 0 value 100))
    (arithmetic-error () nil)
    (error () nil)))

(defun normalize-coverage-threshold (value description)
  (when value
    (unless (valid-coverage-threshold-p value)
      (error "cl-weave: ~A must be a finite real number between 0 and 100."
             description))
    value))

(defun normalize-coverage-source-pathnames (value description)
  (normalize-bounded-proper-list
   value
   description
   (lambda (pathname)
     (unless (or (pathnamep pathname) (stringp pathname))
       (error "cl-weave: each ~A entry must be a pathname designator."
              description))
     (location-pathname-designator pathname))))

(defun normalize-coverage-options
    (coverage-output coverage-report-directory coverage-reset
     include-pathnames exclude-pathnames minimum-expression minimum-branch)
  (let* ((output
           (normalize-coverage-pathname-designator
            coverage-output
            "coverage-output"))
         (report-directory
           (normalize-coverage-pathname-designator
            coverage-report-directory
            "coverage-report-directory"))
         (minimum-expression
           (normalize-coverage-threshold
            minimum-expression
            "coverage-minimum-expression"))
         (minimum-branch
           (normalize-coverage-threshold
            minimum-branch
            "coverage-minimum-branch"))
         (source-pathnames-consumed-p
           (or report-directory minimum-expression minimum-branch)))
    (make-coverage-options
     :output output
     :report-directory report-directory
     :reset (not (null coverage-reset))
     :include-pathnames
     (when source-pathnames-consumed-p
       (normalize-coverage-source-pathnames
        include-pathnames
        "coverage-include-pathnames"))
     :exclude-pathnames
     (when source-pathnames-consumed-p
       (normalize-coverage-source-pathnames
        exclude-pathnames
        "coverage-exclude-pathnames"))
     :minimum-expression minimum-expression
     :minimum-branch minimum-branch)))

(defun call-with-coverage (coverage coverage-output coverage-report-directory coverage-reset thunk
                          &key include-pathnames exclude-pathnames
                            minimum-expression minimum-branch)
  (if coverage
      (let ((options
              (normalize-coverage-options
               coverage-output
               coverage-report-directory
               coverage-reset
               include-pathnames
               exclude-pathnames
               minimum-expression
               minimum-branch)))
        (require-coverage-support)
        (when (coverage-options-reset options)
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
             (collect-coverage-cleanup-failures
              (coverage-options-report-directory options)
              (coverage-options-output options)
              (coverage-options-include-pathnames options)
              (coverage-options-exclude-pathnames options)
              (coverage-options-minimum-expression options)
              (coverage-options-minimum-branch options))
             (or primary-error (not completed-p))))))
      (funcall thunk)))
