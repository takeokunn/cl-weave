(in-package #:cl-weave/cli)

(define-condition cli-error (error)
  ((message :initarg :message :reader cli-error-message))
  (:report (lambda (condition stream)
             (write-string (cli-error-message condition) stream))))

(defstruct (cli-options (:constructor make-cli-options))
  (command :run :type keyword)
  (systems '() :type list)
  (load-files '() :type list)
  (reporter :spec :type keyword)
  name-filter
  output-file
  list
  watch
  (watch-interval 0.5)
  bail
  (retry 0)
  test-timeout-ms
  shard
  (order :defined :type keyword)
  seed
  coverage
  coverage-output
  (pass-with-no-tests t)
  snapshot-directory
  snapshot-file
  update-snapshots
  version
  help)

(defvar *cli-option-handlers* (make-hash-table :test #'equal))

(defmacro define-cli-option (flag (options rest) &body body)
  `(setf (gethash ,flag *cli-option-handlers*)
         (lambda (,options ,rest)
           ,@body)))

(defmacro define-cli-option-alias (alias target)
  `(let ((handler (gethash ,target *cli-option-handlers*)))
     (unless handler
       (error "Unknown CLI option alias target: ~A" ,target))
     (setf (gethash ,alias *cli-option-handlers*) handler)))

(defun string-present-p (value)
  (and value (plusp (length value))))

(defun option-token-p (token)
  (and (string-present-p token)
       (>= (length token) 2)
       (char= (char token 0) #\-)
       (char= (char token 1) #\-)))

(defun environment-value (name)
  (let ((value (uiop:getenv name)))
    (when (string-present-p value)
      value)))

(defun truthy-environment-p (name)
  (let ((value (environment-value name)))
    (and value
         (not (member (string-downcase value)
                      '("0" "false" "no" "off" "nil")
                      :test #'string=)))))

(defun parse-boolean (value name)
  (let ((normalized (string-downcase value)))
    (cond
      ((member normalized '("1" "true" "yes" "on") :test #'string=) t)
      ((member normalized '("0" "false" "no" "off" "nil") :test #'string=) nil)
      (t (error 'cli-error
                :message (format nil "~A must be a boolean: ~A" name value))))))

(defun parse-complete-integer (value name)
  (handler-case
      (parse-integer value :junk-allowed nil)
    (error ()
      (error 'cli-error
             :message (format nil "~A must be an integer: ~A" name value)))))

(defun parse-positive-integer (value name)
  (let ((integer (parse-complete-integer value name)))
    (unless (plusp integer)
      (error 'cli-error :message (format nil "~A must be positive: ~A" name value)))
    integer))

(defun parse-non-negative-integer (value name)
  (let ((integer (parse-complete-integer value name)))
    (when (minusp integer)
      (error 'cli-error
             :message (format nil "~A must be a non-negative integer: ~A" name value)))
    integer))

(defun parse-positive-number (value name)
  (labels ((invalid ()
             (error 'cli-error
                    :message (format nil "~A must be a positive number: ~A" name value)))
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

(defun parse-reporter (value)
  (let ((normalized (string-downcase value)))
    (or (loop for (reporter . aliases) in cl-weave::*reporter-aliases*
              when (member normalized aliases :test #'string=)
                return reporter)
        (error 'cli-error
               :message (format nil "cl-weave: unknown reporter: ~A" value)))))

(defun parse-sequence-order (value)
  (let ((normalized (string-downcase value)))
    (cond
      ((string= normalized "defined") :defined)
      ((string= normalized "random") :random)
      ((string= normalized "shuffle") :shuffle)
      (t (error 'cli-error
                :message (format nil "Unknown sequence order: ~A" value))))))

(defun parse-bail (value)
  (let ((normalized (string-downcase value)))
    (cond
      ((member normalized '("true" "yes" "on" "t") :test #'string=) t)
      ((member normalized '("false" "no" "off" "0" "nil") :test #'string=) nil)
      (t
       (let ((parsed (ignore-errors
                       (parse-complete-integer value "--bail"))))
         (unless (and parsed (plusp parsed))
           (error 'cli-error
                  :message (format nil "--bail must be true, false, or a positive integer: ~A" value)))
         parsed)))))

(defun parse-shard (value)
  (let ((slash (position #\/ value)))
    (unless slash
      (error 'cli-error
             :message (format nil "--shard must use INDEX/COUNT: ~A" value)))
    (let ((index (parse-positive-integer (subseq value 0 slash) "--shard index"))
          (count (parse-positive-integer (subseq value (1+ slash)) "--shard count")))
      (unless (<= index count)
        (error 'cli-error
               :message (format nil "--shard requires INDEX <= COUNT: ~A" value)))
      (list index count))))

(defun require-option-argument (flag rest)
  (let ((value (first rest)))
    (unless (and value (not (option-token-p value)))
      (error 'cli-error :message (format nil "~A requires an argument" flag)))
    value))

(defun option-name-and-inline-value (token)
  (let ((equals (position #\= token)))
    (if equals
        (values (subseq token 0 equals) (subseq token (1+ equals)) t)
        (values token nil nil))))

(defun consume-optional-value (default rest)
  (if (and (first rest) (not (option-token-p (first rest))))
      (values (first rest) (rest rest))
      (values default rest)))

(define-cli-option "--help" (options rest)
  (setf (cli-options-help options) t)
  rest)

(define-cli-option "--version" (options rest)
  (setf (cli-options-version options) t)
  rest)

(define-cli-option "--system" (options rest)
  (let ((system (require-option-argument "--system" rest)))
    (push system (cli-options-systems options))
    (rest rest)))

(define-cli-option "--load" (options rest)
  (let ((file (require-option-argument "--load" rest)))
    (push file (cli-options-load-files options))
    (rest rest)))

(define-cli-option "--reporter" (options rest)
  (let ((reporter (require-option-argument "--reporter" rest)))
    (setf (cli-options-reporter options) (parse-reporter reporter))
    (rest rest)))

(define-cli-option "--filter" (options rest)
  (let ((filter (require-option-argument "--filter" rest)))
    (setf (cli-options-name-filter options) filter)
    (rest rest)))

(define-cli-option "--output" (options rest)
  (let ((path (require-option-argument "--output" rest)))
    (setf (cli-options-output-file options) path)
    (rest rest)))

(define-cli-option "--list" (options rest)
  (setf (cli-options-list options) t
        (cli-options-command options) :list)
  rest)

(define-cli-option "--watch" (options rest)
  (setf (cli-options-watch options) t
        (cli-options-command options) :watch)
  rest)

(define-cli-option "--watch-interval" (options rest)
  (let ((interval (require-option-argument "--watch-interval" rest)))
    (setf (cli-options-watch-interval options)
          (parse-positive-number interval "--watch-interval"))
    (rest rest)))

(define-cli-option "--bail" (options rest)
  (multiple-value-bind (value remaining)
      (consume-optional-value "true" rest)
    (setf (cli-options-bail options) (parse-bail value))
    remaining))

(define-cli-option "--retry" (options rest)
  (let ((retry (require-option-argument "--retry" rest)))
    (setf (cli-options-retry options)
          (parse-non-negative-integer retry "--retry"))
    (rest rest)))

(define-cli-option "--test-timeout-ms" (options rest)
  (let ((timeout-ms (require-option-argument "--test-timeout-ms" rest)))
    (setf (cli-options-test-timeout-ms options)
          (parse-positive-integer timeout-ms "--test-timeout-ms"))
    (rest rest)))

(define-cli-option "--test-timeout" (options rest)
  (let ((timeout-ms (require-option-argument "--test-timeout" rest)))
    (setf (cli-options-test-timeout-ms options)
          (parse-positive-integer timeout-ms "--test-timeout"))
    (rest rest)))

(define-cli-option "--shard" (options rest)
  (let ((shard (require-option-argument "--shard" rest)))
    (setf (cli-options-shard options) (parse-shard shard))
    (rest rest)))

(define-cli-option "--sequence" (options rest)
  (let ((order (require-option-argument "--sequence" rest)))
    (setf (cli-options-order options) (parse-sequence-order order))
    (rest rest)))

(define-cli-option "--seed" (options rest)
  (let ((seed (require-option-argument "--seed" rest)))
    (setf (cli-options-seed options)
          (parse-positive-integer seed "--seed"))
    (rest rest)))

(define-cli-option "--coverage" (options rest)
  (setf (cli-options-coverage options) t)
  rest)

(define-cli-option "--coverage-output" (options rest)
  (let ((path (require-option-argument "--coverage-output" rest)))
    (setf (cli-options-coverage-output options) path)
    (rest rest)))

(define-cli-option "--pass-with-no-tests" (options rest)
  (setf (cli-options-pass-with-no-tests options) t)
  rest)

(define-cli-option "--fail-with-no-tests" (options rest)
  (setf (cli-options-pass-with-no-tests options) nil)
  rest)

(define-cli-option "--snapshot-dir" (options rest)
  (let ((directory (require-option-argument "--snapshot-dir" rest)))
    (setf (cli-options-snapshot-directory options) (pathname directory))
    (rest rest)))

(define-cli-option "--snapshot-file" (options rest)
  (let ((file (require-option-argument "--snapshot-file" rest)))
    (setf (cli-options-snapshot-file options) file)
    (rest rest)))

(define-cli-option "--update-snapshots" (options rest)
  (setf (cli-options-update-snapshots options) t)
  rest)

(define-cli-option-alias "--testNamePattern" "--filter")
(define-cli-option-alias "--outputFile" "--output")
(define-cli-option-alias "--watchInterval" "--watch-interval")
(define-cli-option-alias "--testTimeout" "--test-timeout-ms")
(define-cli-option-alias "--testTimeoutMs" "--test-timeout-ms")
(define-cli-option-alias "--coverageOutput" "--coverage-output")
(define-cli-option-alias "--passWithNoTests" "--pass-with-no-tests")
(define-cli-option-alias "--failWithNoTests" "--fail-with-no-tests")
(define-cli-option-alias "--snapshotDir" "--snapshot-dir")
(define-cli-option-alias "--snapshotFile" "--snapshot-file")
(define-cli-option-alias "--update" "--update-snapshots")
(define-cli-option-alias "--updateSnapshots" "--update-snapshots")

(defparameter *metadata-commands*
  '("run" "list" "watch" "metadata" "version" "help"))

(defparameter *metadata-reporters*
  '("spec" "sexp" "json" "jsonl" "tap" "github" "junit"))

(defparameter *metadata-list-reporters*
  '("spec" "sexp" "json" "jsonl"))

(defparameter *metadata-environment-variables*
  '("CL_WEAVE_SYSTEM"
    "CL_WEAVE_REPORTER"
    "CL_WEAVE_TEST_FILTER"
    "CL_WEAVE_OUTPUT_FILE"
    "CL_WEAVE_LIST"
    "CL_WEAVE_WATCH"
    "CL_WEAVE_WATCH_INTERVAL"
    "CL_WEAVE_BAIL"
    "CL_WEAVE_RETRY"
    "CL_WEAVE_TEST_TIMEOUT"
    "CL_WEAVE_TEST_TIMEOUT_MS"
    "CL_WEAVE_SHARD"
    "CL_WEAVE_SEQUENCE"
    "CL_WEAVE_SEQUENCE_SEED"
    "CL_WEAVE_COVERAGE"
    "CL_WEAVE_COVERAGE_FILE"
    "CL_WEAVE_PASS_WITH_NO_TESTS"
    "CL_WEAVE_SNAPSHOT_DIR"
    "CL_WEAVE_SNAPSHOT_FILE"
    "CL_WEAVE_UPDATE_SNAPSHOTS"))

(defparameter *metadata-cli-options*
  '((:name "--system"
     :aliases nil
     :commands ("run" "list" "watch" "metadata")
     :argument "SYSTEM"
     :environment ("CL_WEAVE_SYSTEM")
     :description "ASDF system to load before command execution")
    (:name "--load"
     :aliases nil
     :commands ("run" "list" "watch" "metadata")
     :argument "FILE"
     :environment nil
     :description "Lisp file to load before command execution")
    (:name "--reporter"
     :aliases nil
     :commands ("run" "list" "watch" "metadata")
     :argument "REPORTER"
     :environment ("CL_WEAVE_REPORTER")
     :description "Reporter name for run, list, watch, or metadata output")
    (:name "--filter"
     :aliases ("--testNamePattern")
     :commands ("run" "list" "watch")
     :argument "TEXT"
     :environment ("CL_WEAVE_TEST_FILTER")
     :description "Run or list tests whose Vitest-style path contains TEXT")
    (:name "--output"
     :aliases ("--outputFile")
     :commands ("run" "list" "watch" "metadata")
     :argument "FILE"
     :environment ("CL_WEAVE_OUTPUT_FILE")
     :description "Write reporter output to FILE")
    (:name "--list"
     :aliases nil
     :commands ("run" "list")
     :argument nil
     :environment ("CL_WEAVE_LIST")
     :description "Discover tests without executing test bodies")
    (:name "--watch"
     :aliases nil
     :commands ("run" "watch")
     :argument nil
     :environment ("CL_WEAVE_WATCH")
     :description "Rerun an ASDF system when source files change")
    (:name "--watch-interval"
     :aliases ("--watchInterval")
     :commands ("watch")
     :argument "SECONDS"
     :environment ("CL_WEAVE_WATCH_INTERVAL")
     :description "Polling interval for watch mode")
    (:name "--bail"
     :aliases nil
     :commands ("run" "watch")
     :argument "N|true|false"
     :environment ("CL_WEAVE_BAIL")
     :description "Stop after the first failure, N failures, or disable fast-fail")
    (:name "--retry"
     :aliases nil
     :commands ("run" "list" "watch")
     :argument "INTEGER"
     :environment ("CL_WEAVE_RETRY")
     :description "Retry failing tests INTEGER extra times")
    (:name "--test-timeout-ms"
     :aliases ("--test-timeout" "--testTimeout" "--testTimeoutMs")
     :commands ("run" "list" "watch")
     :argument "MS"
     :environment ("CL_WEAVE_TEST_TIMEOUT" "CL_WEAVE_TEST_TIMEOUT_MS")
     :description "Default per-attempt timeout in milliseconds")
    (:name "--shard"
     :aliases nil
     :commands ("run" "list" "watch")
     :argument "INDEX/COUNT"
     :environment ("CL_WEAVE_SHARD")
     :description "Select a deterministic CI shard")
    (:name "--sequence"
     :aliases nil
     :commands ("run" "list" "watch")
     :argument "ORDER"
     :environment ("CL_WEAVE_SEQUENCE")
     :description "Execution order: defined, random, or shuffle")
    (:name "--seed"
     :aliases nil
     :commands ("run" "list" "watch")
     :argument "INTEGER"
     :environment ("CL_WEAVE_SEQUENCE_SEED")
     :description "Deterministic random sequence seed")
    (:name "--coverage"
     :aliases nil
     :commands ("run" "watch")
     :argument nil
     :environment ("CL_WEAVE_COVERAGE")
     :description "Wrap execution with SBCL sb-cover")
    (:name "--coverage-output"
     :aliases ("--coverageOutput")
     :commands ("run" "watch")
     :argument "FILE"
     :environment ("CL_WEAVE_COVERAGE_FILE")
     :description "Save SBCL coverage state to FILE")
    (:name "--pass-with-no-tests"
     :aliases ("--passWithNoTests")
     :commands ("run" "watch")
     :argument nil
     :environment ("CL_WEAVE_PASS_WITH_NO_TESTS")
     :description "Pass when filters select no tests")
    (:name "--fail-with-no-tests"
     :aliases ("--failWithNoTests")
     :commands ("run" "watch")
     :argument nil
     :environment nil
     :description "Fail when filters select no tests")
    (:name "--snapshot-dir"
     :aliases ("--snapshotDir")
     :commands ("run" "watch")
     :argument "DIR"
     :environment ("CL_WEAVE_SNAPSHOT_DIR")
     :description "External snapshot directory")
    (:name "--snapshot-file"
     :aliases ("--snapshotFile")
     :commands ("run" "watch")
     :argument "FILE"
     :environment ("CL_WEAVE_SNAPSHOT_FILE")
     :description "External snapshot file name")
    (:name "--update-snapshots"
     :aliases ("--update" "--updateSnapshots")
     :commands ("run" "watch")
     :argument nil
     :environment ("CL_WEAVE_UPDATE_SNAPSHOTS")
     :description "Update external snapshots during this run")
    (:name "--version"
     :aliases nil
     :commands ("version")
     :argument nil
     :environment nil
     :description "Print the cl-weave version")
    (:name "--help"
     :aliases nil
     :commands ("help")
     :argument nil
     :environment nil
     :description "Print command usage")))

(defparameter *metadata-capabilities*
  '("describe-it-dsl"
    "vitest-dot-aliases"
    "expect-matchers"
    "smart-s-expression-assertions"
    "fixtures"
    "around-each-continuations"
    "mock-functions"
    "snapshots"
    "property-tests"
    "mutation-testing"
    "subprocess-isolation"
    "coverage"
    "watch"
    "sharding"
    "sequence-ordering"
    "retry"
    "timeout"
    "logic-test-plan"
    "public-package-exports"
    "cps-continuation-helpers"))

(defparameter *metadata-vitest-aliases*
  '(("describe.each" . "describe-each")
    ("describe.skip" . "describe-skip")
    ("describe.skip.each" . "describe-skip-each")
    ("describe.todo" . "describe-todo")
    ("describe.todo.each" . "describe-todo-each")
    ("describe.only" . "describe-only")
    ("describe.only.each" . "describe-only-each")
    ("describe.concurrent" . "describe-concurrent")
    ("describe.concurrent.each" . "describe-concurrent-each")
    ("describe.sequential" . "describe-sequential")
    ("describe.sequential.each" . "describe-sequential-each")
    ("describe.run-if" . "describe-run-if")
    ("describe.skip-if" . "describe-skip-if")
    ("it.each" . "it-each")
    ("it.skip" . "it-skip")
    ("it.skip.each" . "it-skip-each")
    ("it.todo" . "it-todo")
    ("it.todo.each" . "it-todo-each")
    ("it.concurrent" . "it-concurrent")
    ("it.concurrent.each" . "it-concurrent-each")
    ("it.sequential" . "it-sequential")
    ("it.sequential.each" . "it-sequential-each")
    ("it.fails" . "it-fails")
    ("it.fails.each" . "it-fails-each")
    ("it.only" . "it-only")
    ("it.only.each" . "it-only-each")
    ("it.run-if" . "it-run-if")
    ("it.skip-if" . "it-skip-if")
    ("it.property" . "it-property")
    ("it.isolated" . "it-isolated")
    ("test.each" . "test-each")
    ("test.skip" . "test-skip")
    ("test.skip.each" . "test-skip-each")
    ("test.todo" . "test-todo")
    ("test.todo.each" . "test-todo-each")
    ("test.concurrent" . "test-concurrent")
    ("test.concurrent.each" . "test-concurrent-each")
    ("test.sequential" . "test-sequential")
    ("test.sequential.each" . "test-sequential-each")
    ("test.fails" . "test-fails")
    ("test.fails.each" . "test-fails-each")
    ("test.only" . "test-only")
    ("test.only.each" . "test-only-each")
    ("test.run-if" . "test-run-if")
    ("test.skip-if" . "test-skip-if")
    ("test.property" . "test-property")
    ("test.isolated" . "test-isolated")
    ("expect.not" . "expect-not")
    ("expect.resolves" . "expect-resolves")
    ("expect.rejects" . "expect-rejects")
    ("expect.assertions" . "expect-assertions")
    ("expect.hasassertions" . "expect-has-assertions")
    ("expect.extend" . "expect-extend")
    ("vi.fn" . "make-mock-function")
    ("vi.spyon" . "spy-on")
    ("vi.mocked" . "mock-function-p")
    ("vi.ismockfunction" . "mock-function-p")
    ("vi.mockimplementation" . "mock-implementation")
    ("vi.mockreturnvalue" . "mock-return-value")
    ("vi.mockreturnvalues" . "mock-return-values")
    ("vi.mockclear" . "clear-mock")
    ("vi.mockreset" . "reset-mock")
    ("vi.mockrestore" . "mock-restore")
    ("vi.clearallmocks" . "clear-all-mocks")
    ("vi.resetallmocks" . "reset-all-mocks")
    ("vi.restoreallmocks" . "restore-all-mocks")))

(defun options-from-environment ()
  (let ((options (make-cli-options)))
    (when (environment-value "CL_WEAVE_SYSTEM")
      (setf (cli-options-systems options)
            (list (environment-value "CL_WEAVE_SYSTEM"))))
    (when (environment-value "CL_WEAVE_REPORTER")
      (setf (cli-options-reporter options)
            (parse-reporter (environment-value "CL_WEAVE_REPORTER"))))
    (when (environment-value "CL_WEAVE_TEST_FILTER")
      (setf (cli-options-name-filter options)
            (environment-value "CL_WEAVE_TEST_FILTER")))
    (when (environment-value "CL_WEAVE_OUTPUT_FILE")
      (setf (cli-options-output-file options)
            (environment-value "CL_WEAVE_OUTPUT_FILE")))
    (when (environment-value "CL_WEAVE_BAIL")
      (setf (cli-options-bail options)
            (parse-bail (environment-value "CL_WEAVE_BAIL"))))
    (when (environment-value "CL_WEAVE_RETRY")
      (setf (cli-options-retry options)
            (parse-non-negative-integer (environment-value "CL_WEAVE_RETRY")
                                        "CL_WEAVE_RETRY")))
    (when (environment-value "CL_WEAVE_TEST_TIMEOUT")
      (setf (cli-options-test-timeout-ms options)
            (parse-positive-integer (environment-value "CL_WEAVE_TEST_TIMEOUT")
                                    "CL_WEAVE_TEST_TIMEOUT")))
    (when (environment-value "CL_WEAVE_TEST_TIMEOUT_MS")
      (setf (cli-options-test-timeout-ms options)
            (parse-positive-integer (environment-value "CL_WEAVE_TEST_TIMEOUT_MS")
                                    "CL_WEAVE_TEST_TIMEOUT_MS")))
    (when (environment-value "CL_WEAVE_SHARD")
      (setf (cli-options-shard options)
            (parse-shard (environment-value "CL_WEAVE_SHARD"))))
    (when (environment-value "CL_WEAVE_SEQUENCE")
      (setf (cli-options-order options)
            (parse-sequence-order (environment-value "CL_WEAVE_SEQUENCE"))))
    (when (environment-value "CL_WEAVE_SEQUENCE_SEED")
      (setf (cli-options-seed options)
            (parse-positive-integer (environment-value "CL_WEAVE_SEQUENCE_SEED")
                                    "CL_WEAVE_SEQUENCE_SEED")))
    (when (truthy-environment-p "CL_WEAVE_COVERAGE")
      (setf (cli-options-coverage options) t))
    (when (environment-value "CL_WEAVE_COVERAGE_FILE")
      (setf (cli-options-coverage-output options)
            (environment-value "CL_WEAVE_COVERAGE_FILE")))
    (when (environment-value "CL_WEAVE_PASS_WITH_NO_TESTS")
      (setf (cli-options-pass-with-no-tests options)
            (parse-boolean (environment-value "CL_WEAVE_PASS_WITH_NO_TESTS")
                           "CL_WEAVE_PASS_WITH_NO_TESTS")))
    (when (environment-value "CL_WEAVE_SNAPSHOT_DIR")
      (setf (cli-options-snapshot-directory options)
            (pathname (environment-value "CL_WEAVE_SNAPSHOT_DIR"))))
    (when (environment-value "CL_WEAVE_SNAPSHOT_FILE")
      (setf (cli-options-snapshot-file options)
            (environment-value "CL_WEAVE_SNAPSHOT_FILE")))
    (when (truthy-environment-p "CL_WEAVE_LIST")
      (setf (cli-options-list options) t
            (cli-options-command options) :list))
    (when (truthy-environment-p "CL_WEAVE_WATCH")
      (setf (cli-options-watch options) t
            (cli-options-command options) :watch))
    (when (environment-value "CL_WEAVE_WATCH_INTERVAL")
      (setf (cli-options-watch-interval options)
            (parse-positive-number (environment-value "CL_WEAVE_WATCH_INTERVAL")
                                   "CL_WEAVE_WATCH_INTERVAL")))
    (when (truthy-environment-p "CL_WEAVE_UPDATE_SNAPSHOTS")
      (setf (cli-options-update-snapshots options) t))
    options))

(defun command-token-p (token)
  (member token *metadata-commands* :test #'string=))

(defun apply-command-token (options token)
  (cond
    ((string= token "run") (setf (cli-options-command options) :run))
    ((string= token "list")
     (setf (cli-options-command options) :list
           (cli-options-list options) t))
    ((string= token "watch")
     (setf (cli-options-command options) :watch
           (cli-options-watch options) t))
    ((string= token "metadata") (setf (cli-options-command options) :metadata))
    ((string= token "version") (setf (cli-options-version options) t))
    ((string= token "help") (setf (cli-options-help options) t))))

(defun handle-option-token (options token rest)
  (multiple-value-bind (flag inline-value inline-p)
      (option-name-and-inline-value token)
    (let ((handler (gethash flag *cli-option-handlers*)))
      (unless handler
        (error 'cli-error :message (format nil "Unknown option: ~A" flag)))
      (funcall handler options (if inline-p (list* inline-value rest) rest)))))

(defun command-allows-positional-system-p (command)
  (member command '(:run :list :watch :metadata)))

(defun normalize-cli-arguments (argv)
  (if (and argv (string= (first argv) "--"))
      (rest argv)
      argv))

(defun parse-cli-arguments (argv &optional (options (options-from-environment)))
  (loop
    with command-seen = nil
    for rest = (normalize-cli-arguments argv) then next
    while rest
    for token = (first rest)
    for tail = (rest rest)
    for next = (cond
                 ((option-token-p token)
                  (handle-option-token options token tail))
                 ((and (not command-seen) (command-token-p token))
                  (setf command-seen t)
                  (apply-command-token options token)
                  tail)
                 ((and (command-allows-positional-system-p
                        (cli-options-command options))
                       (null (cli-options-systems options)))
                  (push token (cli-options-systems options))
                  tail)
                 (t
                  (error 'cli-error
                         :message (format nil "Unexpected argument: ~A" token))))
    finally
       (setf (cli-options-systems options)
             (nreverse (cli-options-systems options))
             (cli-options-load-files options)
             (nreverse (cli-options-load-files options)))
       (return options)))

(defun cli-usage ()
  (format nil "~{~A~%~}"
          '("Usage:"
            "  cl-weave run [SYSTEM] [options]"
            "  cl-weave list [SYSTEM] [options]"
            "  cl-weave watch [SYSTEM] [options]"
            "  cl-weave metadata [SYSTEM] [options]"
            "  cl-weave version"
            ""
            "Options:"
            "  --system SYSTEM           ASDF system to load before running tests"
            "  --load FILE               Lisp file to load before running tests"
            "  --reporter REPORTER       spec, sexp, json, jsonl, tap, github, or junit"
            "  --filter, --testNamePattern TEXT"
            "                            run tests whose Vitest-style path contains TEXT"
            "  --output, --outputFile FILE"
            "                            write reporter output to FILE"
            "  --list                    discover tests without executing bodies"
            "  --watch                   rerun an ASDF system when source files change"
            "  --watch-interval, --watchInterval SECONDS"
            "                            polling interval for watch mode"
            "  --bail[=N|true|false]     stop after the first or N failures"
            "  --retry INTEGER          retry failing tests INTEGER extra times"
            "  --test-timeout-ms, --test-timeout, --testTimeout MS"
            "                            default per-attempt timeout in milliseconds"
            "  --shard INDEX/COUNT       select a deterministic CI shard"
            "  --sequence ORDER          defined, random, or shuffle"
            "  --seed INTEGER            deterministic random sequence seed"
            "  --coverage                wrap execution with SBCL sb-cover"
            "  --coverage-output, --coverageOutput FILE"
            "                            save SBCL coverage state to FILE"
            "  --pass-with-no-tests, --passWithNoTests"
            "                            pass when filters select no tests"
            "  --fail-with-no-tests, --failWithNoTests"
            "                            fail when filters select no tests"
            "  --snapshot-dir, --snapshotDir DIR"
            "                            external snapshot directory"
            "  --snapshot-file, --snapshotFile FILE"
            "                            external snapshot file name"
            "  --update-snapshots, --update, --updateSnapshots"
            "                            update external snapshots during this run"
            "  --version                print cl-weave version"
            "  --help                    print this help")))

(defun cli-version ()
  (or (ignore-errors
        (let ((system (asdf:find-system "cl-weave" nil)))
          (and system (asdf:component-version system))))
      "unknown"))

(defun package-export-metadata (package-designator)
  (let ((package (or (find-package package-designator)
                     (error 'cli-error
                            :message (format nil "Unknown metadata package: ~A"
                                             package-designator)))))
    (list :name (string-downcase (package-name package))
          :exports
          (sort (loop for symbol being the external-symbols of package
                      collect (string-downcase (symbol-name symbol)))
                #'string<))))

(defun framework-metadata ()
  (list
   :kind "cl-weave-metadata"
   :schema-version 1
   :version (cli-version)
   :commands *metadata-commands*
   :reporters *metadata-reporters*
   :list-reporters *metadata-list-reporters*
   :capabilities *metadata-capabilities*
   :environment *metadata-environment-variables*
   :options *metadata-cli-options*
   :vitest-aliases
   (loop for (alias . canonical) in *metadata-vitest-aliases*
         collect (list :alias alias :canonical canonical))
   :package-exports (list (package-export-metadata :cl-weave)
                          (package-export-metadata :cl-weave/cli))
   :matchers (cl-weave:list-matchers)
   :mutation-operators (cl-weave:list-mutation-operators)))

(defun metadata-reporter (options)
  (let ((reporter (cli-options-reporter options)))
    (cond
      ((eq reporter :spec) :json)
      ((member reporter '(:json :sexp)) reporter)
      (t (error 'cli-error
                :message "cl-weave: metadata mode supports json and sexp reporters.")))))

(defun metadata-symbol-name (symbol)
  (string-downcase (symbol-name symbol)))

(defun write-json-key (key stream)
  (cl-weave::write-json-string key stream)
  (write-char #\: stream))

(defun write-json-number (value stream)
  (write value :stream stream))

(defun write-json-string-value (value stream)
  (cl-weave::write-json-string value stream))

(defun write-json-string-list (values stream)
  (write-char #\[ stream)
  (loop for value in values
        for firstp = t then nil
        unless firstp do (write-char #\, stream)
        do (cl-weave::write-json-string value stream))
  (write-char #\] stream))

(defun write-json-nullable-string (value stream)
  (if value
      (cl-weave::write-json-string value stream)
      (write-string "null" stream)))

(defun write-json-aliases (aliases stream)
  (write-char #\[ stream)
  (loop for entry in aliases
        for firstp = t then nil
        unless firstp do (write-char #\, stream)
        do (progn
             (write-char #\{ stream)
             (write-json-key "alias" stream)
             (cl-weave::write-json-string (getf entry :alias) stream)
             (write-char #\, stream)
             (write-json-key "canonical" stream)
             (cl-weave::write-json-string (getf entry :canonical) stream)
             (write-char #\} stream)))
  (write-char #\] stream))

(defun write-json-cli-options (options stream)
  (write-char #\[ stream)
  (loop for option in options
        for firstp = t then nil
        unless firstp do (write-char #\, stream)
        do (progn
             (write-char #\{ stream)
             (write-json-key "name" stream)
             (cl-weave::write-json-string (getf option :name) stream)
             (write-char #\, stream)
             (write-json-key "aliases" stream)
             (write-json-string-list (getf option :aliases) stream)
             (write-char #\, stream)
             (write-json-key "commands" stream)
             (write-json-string-list (getf option :commands) stream)
             (write-char #\, stream)
             (write-json-key "argument" stream)
             (write-json-nullable-string (getf option :argument) stream)
             (write-char #\, stream)
             (write-json-key "environment" stream)
             (write-json-string-list (getf option :environment) stream)
             (write-char #\, stream)
             (write-json-key "description" stream)
             (write-json-nullable-string (getf option :description) stream)
             (write-char #\} stream)))
  (write-char #\] stream))

(defun write-json-named-metadata (entries stream)
  (write-char #\[ stream)
  (loop for entry in entries
        for firstp = t then nil
        unless firstp do (write-char #\, stream)
        do (progn
             (write-char #\{ stream)
             (write-json-key "name" stream)
             (cl-weave::write-json-string
              (metadata-symbol-name (getf entry :name))
              stream)
             (write-char #\, stream)
             (write-json-key "description" stream)
             (write-json-nullable-string (getf entry :description) stream)
             (write-char #\} stream)))
  (write-char #\] stream))

(defun write-json-package-exports (entries stream)
  (write-char #\[ stream)
  (loop for entry in entries
        for firstp = t then nil
        unless firstp do (write-char #\, stream)
        do (progn
             (write-char #\{ stream)
             (write-json-key "name" stream)
             (cl-weave::write-json-string (getf entry :name) stream)
             (write-char #\, stream)
             (write-json-key "exports" stream)
             (write-json-string-list (getf entry :exports) stream)
             (write-char #\} stream)))
  (write-char #\] stream))

(defparameter *framework-metadata-json-fields*
  '((:schema-version "schemaVersion" write-json-number)
    (:kind "kind" write-json-string-value)
    (:version "version" write-json-string-value)
    (:commands "commands" write-json-string-list)
    (:reporters "reporters" write-json-string-list)
    (:list-reporters "listReporters" write-json-string-list)
    (:capabilities "capabilities" write-json-string-list)
    (:environment "environment" write-json-string-list)
    (:options "options" write-json-cli-options)
    (:vitest-aliases "vitestAliases" write-json-aliases)
    (:package-exports "packageExports" write-json-package-exports)
    (:matchers "matchers" write-json-named-metadata)
    (:mutation-operators "mutationOperators" write-json-named-metadata)))

(defun write-framework-metadata-json-field (field metadata stream)
  (destructuring-bind (metadata-key json-key writer) field
    (write-json-key json-key stream)
    (funcall writer (getf metadata metadata-key) stream)))

(defun write-framework-metadata-json (metadata stream)
  (write-char #\{ stream)
  (loop for field in *framework-metadata-json-fields*
        for firstp = t then nil
        unless firstp do (write-char #\, stream)
        do (write-framework-metadata-json-field field metadata stream))
  (write-char #\} stream)
  (terpri stream))

(defun report-framework-metadata (options stream)
  (let ((metadata (framework-metadata)))
    (case (metadata-reporter options)
      (:json (write-framework-metadata-json metadata stream))
      (:sexp (write metadata :stream stream :pretty t)
             (terpri stream)))))

(defun ensure-valid-reporter-for-command (options)
  (cond
    ((eq (cli-options-command options) :metadata)
     (metadata-reporter options)
     t)
    ((and (cli-options-list options)
          (not (member (cli-options-reporter options)
                       cl-weave::*list-reporters*)))
     (error 'cli-error
            :message "cl-weave: list mode supports spec, sexp, json, and jsonl reporters."))))

(defun load-requested-inputs (options)
  (dolist (system (cli-options-systems options))
    (asdf:load-system system))
  (dolist (file (cli-options-load-files options))
    (load file)))

(defun call-with-output-stream (options callback)
  (let ((output-file (cli-options-output-file options)))
    (if output-file
        (with-open-file (stream output-file
                                :direction :output
                                :if-exists :supersede
                                :if-does-not-exist :create)
          (funcall callback stream))
        (funcall callback *standard-output*))))

(defun run-command (options)
  (ensure-valid-reporter-for-command options)
  (when (and (cli-options-watch options)
             (null (cli-options-systems options)))
    (error 'cli-error :message "Watch mode requires --system SYSTEM."))
  (load-requested-inputs options)
  (let ((cl-weave:*update-snapshots* (cli-options-update-snapshots options))
        (cl-weave:*snapshot-directory*
          (or (cli-options-snapshot-directory options)
              cl-weave:*snapshot-directory*))
        (cl-weave:*snapshot-file-name*
          (or (cli-options-snapshot-file options)
              cl-weave:*snapshot-file-name*)))
    (cond
      ((eq (cli-options-command options) :metadata)
       (call-with-output-stream
        options
        (lambda (stream)
          (report-framework-metadata options stream)))
       t)
      ((cli-options-list options)
       (call-with-output-stream
        options
        (lambda (stream)
          (cl-weave:list-tests
           :reporter (cli-options-reporter options)
           :name-filter (cli-options-name-filter options)
           :shard (cli-options-shard options)
           :order (cli-options-order options)
           :seed (cli-options-seed options)
           :retry (cli-options-retry options)
           :timeout-ms (cli-options-test-timeout-ms options)
           :stream stream)))
       t)
      ((cli-options-watch options)
       (cl-weave:watch-system (first (cli-options-systems options))
                              :reporter (cli-options-reporter options)
                              :name-filter (cli-options-name-filter options)
                              :shard (cli-options-shard options)
                              :order (cli-options-order options)
                              :seed (cli-options-seed options)
                              :bail (cli-options-bail options)
                              :retry (cli-options-retry options)
                              :timeout-ms (cli-options-test-timeout-ms options)
                              :include-dependencies t
                              :interval (cli-options-watch-interval options)))
      (t
       (call-with-output-stream
        options
        (lambda (stream)
          (cl-weave:run-all
           :reporter (cli-options-reporter options)
           :name-filter (cli-options-name-filter options)
           :shard (cli-options-shard options)
           :order (cli-options-order options)
           :seed (cli-options-seed options)
           :bail (cli-options-bail options)
           :retry (cli-options-retry options)
           :timeout-ms (cli-options-test-timeout-ms options)
           :coverage (cli-options-coverage options)
           :coverage-output (cli-options-coverage-output options)
           :pass-with-no-tests (cli-options-pass-with-no-tests options)
           :stream stream)))))))

#+sbcl
(defun process-arguments ()
  (let ((argv (rest sb-ext:*posix-argv*)))
    (if (and argv (string= (first argv) "--"))
        (rest argv)
        argv)))

#-sbcl
(defun process-arguments ()
  (error 'cli-error :message "cl-weave CLI currently requires SBCL."))

#+sbcl
(defun exit-process (code)
  (sb-ext:exit :code code))

#-sbcl
(defun exit-process (code)
  (uiop:quit code))

(defun main (&optional (argv (process-arguments)))
  (handler-case
      (let ((options (parse-cli-arguments argv)))
        (cond
          ((cli-options-version options)
           (format *standard-output* "cl-weave ~A~%" (cli-version))
           (exit-process 0))
          ((cli-options-help options)
           (write-string (cli-usage) *standard-output*)
           (exit-process 0))
          ((run-command options)
           (exit-process 0))
          (t
           (exit-process 1))))
    (cli-error (condition)
      (format *error-output* "cl-weave: ~A~%~%~A" condition (cli-usage))
      (exit-process 2))))
