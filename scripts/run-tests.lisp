(require :asdf)

(let ((root (truename ".")))
  (pushnew root asdf:*central-registry* :test #'equal)
  (asdf:load-asd (merge-pathnames "cl-weave.asd" root))
  (asdf:load-asd (merge-pathnames "cl-weave-tests.asd" root))
  (dolist (path '("src/package.lisp"
                  "src/model.lisp"
                  "src/isolation.lisp"
                  "src/matchers.lisp"
                  "src/property.lisp"
                  "src/mutation.lisp"
                  "src/dsl.lisp"
                  "src/reporters.lisp"
                  "src/runner.lisp"
                  "src/watch.lisp"
                  "src/cli.lisp"
                  "tests/package.lisp"
                  "tests/core.lisp"))
    (load (merge-pathnames path root))))

(defun requested-reporter ()
  (let ((reporter #+sbcl (sb-ext:posix-getenv "CL_WEAVE_REPORTER")
                  #-sbcl nil))
    (cond
      ((or (null reporter) (string= reporter "") (string-equal reporter "spec")) :spec)
      ((string-equal reporter "sexp") :sexp)
      ((string-equal reporter "json") :json)
      ((or (string-equal reporter "jsonl")
           (string-equal reporter "ndjson"))
       :jsonl)
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
      ((or (null value) (string= value "") (string-equal value "defined")) :defined)
      ((or (string-equal value "random") (string-equal value "shuffle")) :random)
      (t (error "cl-weave: CL_WEAVE_SEQUENCE must be defined, random, or shuffle: ~A" value))))
  #-sbcl
  :defined)

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

(defun requested-list-p ()
  (requested-truthy-environment-p "CL_WEAVE_LIST"))

(defun requested-watch-p ()
  (requested-truthy-environment-p "CL_WEAVE_WATCH"))

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

(defun requested-watch-interval ()
  #+sbcl
  (let ((value (sb-ext:posix-getenv "CL_WEAVE_WATCH_INTERVAL")))
    (if (and value (not (string= value "")))
        (multiple-value-bind (parsed position)
            (let ((*read-eval* nil))
              (read-from-string value))
          (unless (and (numberp parsed)
                       (plusp parsed)
                       (loop for index from position below (length value)
                             always (find (char value index)
                                          '(#\Space #\Tab #\Newline #\Return))))
            (error "cl-weave: CL_WEAVE_WATCH_INTERVAL must be a positive number: ~A" value))
          parsed)
        0.5))
  #-sbcl
  0.5)

#+sbcl
(let ((reporter (requested-reporter))
      (output-file (requested-output-file))
      (coverage (requested-coverage-p))
      (coverage-output (requested-coverage-output))
      (snapshot-directory (requested-snapshot-directory))
      (snapshot-file (requested-snapshot-file))
      (update-snapshots (requested-update-snapshots-p))
      (shard (requested-shard))
      (sequence-order (requested-sequence-order))
      (sequence-seed (requested-sequence-seed)))
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
             :stream stream)))
         (sb-ext:exit :code 0))
        ((requested-watch-p)
         (cl-weave:watch-system "cl-weave-tests"
                                :reporter reporter
                                :name-filter (requested-test-filter)
                                :shard shard
                                :order sequence-order
                                :seed sequence-seed
                                :bail (requested-bail)
                                :include-dependencies t
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
                         :bail (requested-bail)
                         :coverage coverage
                         :coverage-output coverage-output
                         :pass-with-no-tests (requested-pass-with-no-tests)
                         :stream stream)))
                    0
                    1)))))))

#-sbcl
(error "cl-weave: scripts/run-tests.lisp currently requires SBCL.")
