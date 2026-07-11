#+sbcl
(load (merge-pathnames "contrib/asdf.fasl" (sb-int:sbcl-homedir-pathname))
      :verbose nil
      :print nil)
#-sbcl
(require :asdf)

(defparameter *runner-pathname* *load-truename*)

(defun project-root ()
  (truename
   (merge-pathnames
    "../"
    (make-pathname :name nil :type nil :defaults *runner-pathname*))))

(defun read-system-definition (pathname)
  (with-open-file (stream pathname)
    (loop for form = (read stream nil nil)
          while form
          when (and (consp form)
                    (symbolp (first form))
                    (string= (symbol-name (first form)) "DEFSYSTEM"))
            return form
          finally
             (error "cl-weave: no DEFSYSTEM form in ~A" pathname))))

(defun component-source-pathnames (components directory)
  (loop for component in components
        append
        (case (first component)
          (:file
           (list (merge-pathnames
                  (make-pathname :name (second component) :type "lisp")
                  directory)))
          (:module
           (component-source-pathnames
            (getf (cddr component) :components)
            (merge-pathnames
             (make-pathname :directory (list :relative (second component)))
             directory)))
          (otherwise
           (error "cl-weave: unsupported ASD component: ~S" component)))))

(defun system-source-pathnames (asd-pathname)
  (let ((definition (read-system-definition asd-pathname)))
    (component-source-pathnames
     (getf (cddr definition) :components)
     (make-pathname :name nil :type nil :defaults asd-pathname))))

(defun load-system-sources (asd-name &key compile)
  (let* ((asd-pathname (merge-pathnames asd-name (project-root)))
         #+sbcl
         (sb-ext:*evaluator-mode* (if compile :compile :interpret)))
    (dolist (source (system-source-pathnames asd-pathname))
      (load source :verbose nil :print nil))))

(defun requested-reporter ()
  (let ((reporter #+sbcl (sb-ext:posix-getenv "CL_WEAVE_REPORTER")
                  #-sbcl nil))
    (cond
      ((or (null reporter) (string= reporter "") (string-equal reporter "spec")) :spec)
      ((string-equal reporter "sexp") :sexp)
      ((string-equal reporter "json") :json)
      ((string-equal reporter "jsonl") :jsonl)
      ((string-equal reporter "tap") :tap)
      ((string-equal reporter "github") :github)
      ((string-equal reporter "junit") :junit)
      (t (error "cl-weave: unknown CL_WEAVE_REPORTER value: ~A" reporter)))))

(defun requested-test-filter ()
  #+sbcl
  (let ((filter (sb-ext:posix-getenv "CL_WEAVE_TEST_FILTER")))
    (when (and filter (not (string= filter "")))
      filter))
  #-sbcl
  nil)

(defun environment-falsy-p (value)
  (or (string= value "0")
      (string-equal value "false")
      (string-equal value "no")
      (string-equal value "off")
      (string-equal value "nil")))

(defun requested-truthy-environment-p (name)
  #+sbcl
  (let ((value (sb-ext:posix-getenv name)))
    (and value
         (not (string= value ""))
         (not (environment-falsy-p value))))
  #-sbcl
  (declare (ignore name))
  #-sbcl
  nil)

(defun requested-pass-with-no-tests ()
  #+sbcl
  (let ((value (sb-ext:posix-getenv "CL_WEAVE_PASS_WITH_NO_TESTS")))
    (cond
      ((or (null value) (string= value "")) t)
      ((or (string-equal value "1")
           (string-equal value "true")
           (string-equal value "yes")
           (string-equal value "on"))
       t)
      ((or (string-equal value "0")
           (string-equal value "false")
           (string-equal value "no")
           (string-equal value "off")
           (string-equal value "nil"))
       nil)
      (t
       (error "cl-weave: CL_WEAVE_PASS_WITH_NO_TESTS must be a boolean: ~A" value))))
  #-sbcl
  t)

(defun requested-bail ()
  #+sbcl
  (let ((value (sb-ext:posix-getenv "CL_WEAVE_BAIL")))
    (cond
      ((or (null value)
           (string= value "")
           (string= value "0")
           (string-equal value "false")
           (string-equal value "no")
           (string-equal value "off")
           (string-equal value "nil"))
       nil)
      ((or (string-equal value "true")
           (string-equal value "yes")
           (string-equal value "on")
           (string-equal value "t"))
       t)
      (t
       (multiple-value-bind (parsed position)
           (parse-integer value :junk-allowed t)
         (unless (and parsed
                      (plusp parsed)
                      (= position (length value)))
           (error "cl-weave: CL_WEAVE_BAIL must be true, false, or a positive integer: ~A" value))
         parsed))))
  #-sbcl
  nil)

(defun parse-positive-integer (value name)
  (multiple-value-bind (parsed position)
      (parse-integer value :junk-allowed t)
    (unless (and parsed
                 (plusp parsed)
                 (= position (length value)))
      (error "cl-weave: ~A must contain a positive integer: ~A" name value))
    parsed))

(defun parse-non-negative-integer (value name)
  (multiple-value-bind (parsed position)
      (parse-integer value :junk-allowed t)
    (unless (and parsed
                 (not (minusp parsed))
                 (= position (length value)))
      (error "cl-weave: ~A must contain a non-negative integer: ~A" name value))
    parsed))

(defun requested-retry ()
  #+sbcl
  (let ((value (sb-ext:posix-getenv "CL_WEAVE_RETRY")))
    (if (and value (not (string= value "")))
        (parse-non-negative-integer value "CL_WEAVE_RETRY")
        nil))
  #-sbcl
  nil)

(defun requested-test-timeout-ms ()
  #+sbcl
  (let* ((timeout-ms (sb-ext:posix-getenv "CL_WEAVE_TEST_TIMEOUT_MS"))
         (timeout (sb-ext:posix-getenv "CL_WEAVE_TEST_TIMEOUT"))
         (value (or timeout-ms timeout))
         (name (if timeout-ms
                   "CL_WEAVE_TEST_TIMEOUT_MS"
                   "CL_WEAVE_TEST_TIMEOUT")))
    (if (and value (not (string= value "")))
        (parse-positive-integer value name)
        nil))
  #-sbcl
  nil)

(defun requested-shard ()
  #+sbcl
  (let ((value (sb-ext:posix-getenv "CL_WEAVE_SHARD")))
    (when (and value (not (string= value "")))
      (let ((slash (position #\/ value)))
        (unless slash
          (error "cl-weave: CL_WEAVE_SHARD must use INDEX/COUNT, for example 1/3: ~A" value))
        (let ((index (parse-positive-integer
                      (subseq value 0 slash)
                      "CL_WEAVE_SHARD index"))
              (count (parse-positive-integer
                      (subseq value (1+ slash))
                      "CL_WEAVE_SHARD count")))
          (unless (<= index count)
            (error "cl-weave: CL_WEAVE_SHARD requires INDEX <= COUNT: ~A" value))
          (list index count)))))
  #-sbcl
  nil)

(defun parse-complete-integer (value name)
  (multiple-value-bind (parsed position)
      (parse-integer value :junk-allowed t)
    (unless (and parsed
                 (= position (length value)))
      (error "cl-weave: ~A must contain an integer: ~A" name value))
    parsed))

(defun requested-sequence-order ()
  #+sbcl
  (let ((value (sb-ext:posix-getenv "CL_WEAVE_SEQUENCE")))
    (cond
      ((or (null value) (string= value "")) nil)
      ((string-equal value "random") :random)
      (t (error "cl-weave: CL_WEAVE_SEQUENCE must be random: ~A" value))))
  #-sbcl
  nil)

(defun requested-sequence-seed ()
  #+sbcl
  (let ((value (sb-ext:posix-getenv "CL_WEAVE_SEQUENCE_SEED")))
    (if (and value (not (string= value "")))
        (parse-positive-integer value "CL_WEAVE_SEQUENCE_SEED")
        0))
  #-sbcl
  0)

(defun requested-output-file ()
  #+sbcl
  (let ((path (sb-ext:posix-getenv "CL_WEAVE_OUTPUT_FILE")))
    (when (and path (not (string= path "")))
      path))
  #-sbcl
  nil)

(defun requested-coverage-p ()
  (requested-truthy-environment-p "CL_WEAVE_COVERAGE"))

(defun requested-coverage-output ()
  #+sbcl
  (let ((path (sb-ext:posix-getenv "CL_WEAVE_COVERAGE_FILE")))
    (when (and path (not (string= path "")))
      path))
  #-sbcl
  nil)

(defun requested-coverage-report-directory ()
  #+sbcl
  (let ((path (sb-ext:posix-getenv "CL_WEAVE_COVERAGE_REPORT_DIR")))
    (when (and path (not (string= path "")))
      path))
  #-sbcl
  nil)

(defun requested-list-p ()
  (requested-truthy-environment-p "CL_WEAVE_LIST"))

(defun requested-watch-p ()
  (requested-truthy-environment-p "CL_WEAVE_WATCH"))

(defun requested-watch-once-p ()
  (requested-truthy-environment-p "CL_WEAVE_WATCH_ONCE"))

(defun requested-snapshot-directory ()
  #+sbcl
  (let ((path (sb-ext:posix-getenv "CL_WEAVE_SNAPSHOT_DIR")))
    (when (and path (not (string= path "")))
      (pathname path)))
  #-sbcl
  nil)

(defun requested-snapshot-file ()
  #+sbcl
  (let ((path (sb-ext:posix-getenv "CL_WEAVE_SNAPSHOT_FILE")))
    (when (and path (not (string= path "")))
      path))
  #-sbcl
  nil)

(defun requested-update-snapshots-p ()
  (requested-truthy-environment-p "CL_WEAVE_UPDATE_SNAPSHOTS"))

(defun parse-positive-number (value name)
  (labels ((invalid ()
             (error "cl-weave: ~A must be a positive number: ~A" name value))
           (digits-p (string)
             (and (plusp (length string))
                  (every #'digit-char-p string)))
           (component (string)
             (unless (digits-p string)
               (invalid))
             (parse-integer string :junk-allowed nil)))
    (let* ((first-dot (position #\. value))
           (second-dot (and first-dot
                            (position #\. value :start (1+ first-dot)))))
      (when (or (string= value "") second-dot)
        (invalid))
      (let ((number
              (if first-dot
                  (let* ((whole (component (subseq value 0 first-dot)))
                         (fraction-text (subseq value (1+ first-dot)))
                         (fraction (component fraction-text))
                         (denominator (expt 10 (length fraction-text))))
                    (float (+ whole (/ fraction denominator)) 1.0))
                  (component value))))
        (unless (plusp number)
          (invalid))
        number))))

(defun requested-watch-interval ()
  #+sbcl
  (let ((value (sb-ext:posix-getenv "CL_WEAVE_WATCH_INTERVAL")))
    (if (and value (not (string= value "")))
        (parse-positive-number value "CL_WEAVE_WATCH_INTERVAL")
        0.5))
  #-sbcl
  0.5)

(defun enable-coverage-compilation ()
  #+sbcl
  (progn
    (require :sb-cover)
    (let* ((package (or (find-package :sb-cover)
                        (error "SB-COVER package is unavailable after REQUIRE.")))
           (quality (or (find-symbol "STORE-COVERAGE-DATA" package)
                        (error "SB-COVER:STORE-COVERAGE-DATA is unavailable."))))
      (proclaim (list 'optimize (list quality 3))))
    t)
  #-sbcl
  nil)

(defun disable-coverage-compilation ()
  #+sbcl
  (let* ((package (or (find-package :sb-cover)
                      (error "SB-COVER package is unavailable.")))
         (quality (or (find-symbol "STORE-COVERAGE-DATA" package)
                      (error "SB-COVER:STORE-COVERAGE-DATA is unavailable."))))
    (proclaim (list 'optimize (list quality 0)))
    t)
  #-sbcl
  nil)

(defun load-project-systems (&key coverage)
  (cond
    (coverage
     (enable-coverage-compilation)
     (load-system-sources "cl-weave.asd" :compile t)
     ;; Test code exercises the product but must not contribute to its score.
     (disable-coverage-compilation)
     (load-system-sources "cl-weave-tests.asd"))
    (t
     (load-system-sources "cl-weave.asd")
     (load-system-sources "cl-weave-tests.asd"))))

(load-project-systems :coverage (requested-coverage-p))

#+sbcl
(let ((reporter (requested-reporter))
      (output-file (requested-output-file))
      (coverage (requested-coverage-p))
      (coverage-output (requested-coverage-output))
      (coverage-report-directory (requested-coverage-report-directory))
      (snapshot-directory (requested-snapshot-directory))
      (snapshot-file (requested-snapshot-file))
      (update-snapshots (requested-update-snapshots-p))
      (shard (requested-shard))
      (sequence-order (requested-sequence-order))
      (sequence-seed (requested-sequence-seed))
      (retry (requested-retry))
      (test-timeout-ms (requested-test-timeout-ms)))
  (flet ((with-requested-stream (callback)
           (if output-file
               (with-open-file (stream output-file
                                       :direction :output
                                       :if-exists :supersede
                                       :if-does-not-exist :create)
                 (funcall callback stream))
               (funcall callback *standard-output*))))
    (let ((cl-weave:*snapshot-directory*
            (or snapshot-directory cl-weave:*snapshot-directory*))
          (cl-weave:*snapshot-file-name*
            (or snapshot-file cl-weave:*snapshot-file-name*))
          (cl-weave:*update-snapshots* update-snapshots))
      (cond
        ((requested-list-p)
         (with-requested-stream
          (lambda (stream)
            (cl-weave:list-tests
             :reporter reporter
             :name-filter (requested-test-filter)
             :shard shard
             :order sequence-order
             :seed sequence-seed
             :retry retry
             :timeout-ms test-timeout-ms
             :stream stream)))
         (sb-ext:exit :code 0))
        ((requested-watch-p)
         (cl-weave:watch-system "cl-weave-tests"
                                :reporter reporter
                                :name-filter (requested-test-filter)
                                :shard shard
                                :order sequence-order
                                :seed sequence-seed
                                :retry retry
                                :timeout-ms test-timeout-ms
                                :bail (requested-bail)
                                :include-dependencies t
                                :once (requested-watch-once-p)
                                :interval (requested-watch-interval)))
        (t
         (sb-ext:exit
          :code (if (with-requested-stream
                      (lambda (stream)
                        (cl-weave:run-all
                         :reporter reporter
                         :name-filter (requested-test-filter)
                         :shard shard
                         :order sequence-order
                         :seed sequence-seed
                         :retry retry
                         :timeout-ms test-timeout-ms
                         :bail (requested-bail)
                         :coverage coverage
                         :coverage-reset (not coverage)
                         :coverage-output coverage-output
                         :coverage-report-directory coverage-report-directory
                         :pass-with-no-tests (requested-pass-with-no-tests)
                         :stream stream)))
                    0
                    1)))))))

#-sbcl
(error "cl-weave: scripts/run-tests.lisp currently requires SBCL.")
