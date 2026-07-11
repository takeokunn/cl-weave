(in-package #:cl-weave/tests)

(describe "cli options"
  (it "parses Vitest-shaped run options into explicit data"
    (let ((options (cl-weave/cli::parse-cli-arguments
                    '("run"
                      "cl-weave-tests"
                      "--reporter=json"
                      "--filter"
                      "parser"
                      "--output"
                      "results.json"
                      "--bail=2"
                      "--retry"
                      "3"
                      "--test-timeout-ms"
                      "2500"
                      "--max-workers"
                      "4"
                      "--shard"
                      "2/4"
                      "--sequence"
                      "random"
                      "--seed"
                      "123"
                      "--coverage"
                      "--coverage-output"
                      "coverage.out"
                      "--fail-with-no-tests"
                      "--once"
                      "--snapshot-dir"
                      "tests/__snapshots__/"
                      "--snapshot-file"
                      "cli.snapshots"
                      "--update-snapshots")
                    (cl-weave/cli::make-cli-options))))
      (expect (cl-weave/cli::cli-options-command options) :to-be :run)
      (expect (cl-weave/cli::cli-options-systems options)
              :to-equal '("cl-weave-tests"))
      (expect (cl-weave/cli::cli-options-reporter options) :to-be :json)
      (expect (cl-weave/cli::parse-reporter "jsonl") :to-be :jsonl)
      (expect (lambda ()
                (cl-weave/cli::parse-reporter "ndjson"))
              :to-throw
              "cl-weave: unknown reporter")
      (expect (cl-weave/cli::parse-reporter "github") :to-be :github)
      (expect (lambda ()
                (cl-weave/cli::parse-reporter "unknown"))
              :to-throw
              "cl-weave: unknown reporter")
      (expect (cl-weave/cli::parse-sequence-order "random") :to-be :random)
      (dolist (removed-order '("defined" "shuffle"))
        (expect (lambda ()
                  (cl-weave/cli::parse-sequence-order removed-order))
                :to-throw
                "Unknown sequence order"))
      (expect (cl-weave/cli::cli-options-name-filter options) :to-equal "parser")
      (expect (cl-weave/cli::cli-options-output-file options)
              :to-equal "results.json")
      (expect (cl-weave/cli::cli-options-bail options) :to-be 2)
      (expect (cl-weave/cli::cli-options-retry options) :to-be 3)
      (expect (cl-weave/cli::cli-options-test-timeout-ms options) :to-be 2500)
      (expect (cl-weave/cli::cli-options-max-workers options) :to-be 4)
      (expect (cl-weave/cli::cli-options-shard options) :to-equal '(2 4))
      (expect (cl-weave/cli::cli-options-order options) :to-be :random)
      (expect (cl-weave/cli::cli-options-seed options) :to-be 123)
      (expect (cl-weave/cli::cli-options-coverage options) :to-be t)
      (expect (cl-weave/cli::cli-options-coverage-output options)
              :to-equal "coverage.out")
      (expect (cl-weave/cli::cli-options-pass-with-no-tests options) :to-be nil)
      (expect (cl-weave/cli::cli-options-watch-once options) :to-be t)
      (expect (cl-weave/cli::cli-options-snapshot-directory options)
              :to-equal #P"tests/__snapshots__/")
      (expect (cl-weave/cli::cli-options-snapshot-file options)
              :to-equal "cli.snapshots")
      (expect (cl-weave/cli::cli-options-update-snapshots options) :to-be t)))

  (it "rejects removed CLI compatibility aliases"
    (dolist (argv '(("run" "--testNamePattern" "cli")
                    ("run" "--outputFile=vitest-results.json")
                    ("run" "--testTimeout=1500")
                    ("run" "--testTimeoutMs" "1750")
                    ("run" "--maxWorkers=5")
                    ("run" "--coverageOutput=coverage.out")
                    ("run" "--passWithNoTests")
                    ("run" "--failWithNoTests")
                    ("run" "--snapshotDir" "tests/__snapshots__/")
                    ("run" "--snapshotFile=vitest.snapshots")
                    ("run" "--update")
                    ("run" "--updateSnapshots")
                    ("watch" "cl-weave-tests" "--watchInterval" "2.5")))
      (expect (lambda ()
                (cl-weave/cli::parse-cli-arguments
                 argv
                 (cl-weave/cli::make-cli-options)))
              :to-throw
              "Unknown option")))

  (it "parses watch intervals as explicit CLI text"
    (labels ((watch-interval-from-env (value)
               (with-mocked-functions
                   (((symbol-function 'uiop:getenv)
                     (lambda (name)
                       (when (string= name "CL_WEAVE_WATCH_INTERVAL")
                         value))))
                 (cl-weave/cli::cli-options-watch-interval
                  (cl-weave/cli::options-from-environment)))))
      (expect (cl-weave/cli::cli-options-watch-interval
               (cl-weave/cli::parse-cli-arguments
                '("watch" "--watch-interval" "0.25")
                (cl-weave/cli::make-cli-options)))
              :to-be 0.25)
      (expect (watch-interval-from-env "0.25") :to-be 0.25)
      (dolist (value '("0" "-1" "1/2" "1 " ".5" "1." "#.(error \"reader\")"))
        (expect (lambda ()
                  (cl-weave/cli::parse-cli-arguments
                   (list "watch" "--watch-interval" value)
                   (cl-weave/cli::make-cli-options)))
                :to-throw
                "--watch-interval must be a positive number")
        (expect (lambda ()
                  (watch-interval-from-env value))
                :to-throw
                "CL_WEAVE_WATCH_INTERVAL must be a positive number"))))

  (it "parses watch once policy from flags and environment"
    (let ((options (cl-weave/cli::parse-cli-arguments
                    '("watch" "--once")
                    (cl-weave/cli::make-cli-options))))
      (expect (cl-weave/cli::cli-options-watch-once options) :to-be t))
    (with-mocked-functions
        (((symbol-function 'uiop:getenv)
          (lambda (name)
            (cdr (assoc name
                        '(("CL_WEAVE_WATCH_ONCE" . "1"))
                        :test #'string=)))))
      (let ((options (cl-weave/cli::options-from-environment)))
        (expect (cl-weave/cli::cli-options-watch-once options) :to-be t))))

  (it "parses doctor as a machine-readable command with an optional positional system"
    (let ((options (cl-weave/cli::parse-cli-arguments
                    '("doctor" "--reporter" "json")
                    (cl-weave/cli::make-cli-options))))
      (expect (cl-weave/cli::cli-options-command options) :to-be :doctor)
      (expect (cl-weave/cli::cli-options-reporter options) :to-be :json)
      (expect (cl-weave/cli::cli-options-systems options) :to-equal '()))
    (let ((options (cl-weave/cli::parse-cli-arguments
                    '("doctor" "cl-weave-tests")
                    (cl-weave/cli::make-cli-options))))
      (expect (cl-weave/cli::cli-options-command options) :to-be :doctor)
      (expect (cl-weave/cli::cli-options-systems options)
              :to-equal '("cl-weave-tests"))))

  (it "parses CI snapshot settings from environment variables"
    (with-mocked-functions
        (((symbol-function 'uiop:getenv)
          (lambda (name)
            (cdr (assoc name
                        '(("CL_WEAVE_SNAPSHOT_DIR" . "ci/__snapshots__/")
                          ("CL_WEAVE_SNAPSHOT_FILE" . "ci.snapshots")
                          ("CL_WEAVE_UPDATE_SNAPSHOTS" . "1"))
                        :test #'string=)))))
      (let ((options (cl-weave/cli::options-from-environment)))
        (expect (cl-weave/cli::cli-options-snapshot-directory options)
                :to-equal #P"ci/__snapshots__/")
        (expect (cl-weave/cli::cli-options-snapshot-file options)
                :to-equal "ci.snapshots")
        (expect (cl-weave/cli::cli-options-update-snapshots options) :to-be t))))

  (it "parses no-test policy from flags and environment"
    (let ((options (cl-weave/cli::parse-cli-arguments
                    '("run" "--fail-with-no-tests" "--pass-with-no-tests")
                    (cl-weave/cli::make-cli-options))))
      (expect (cl-weave/cli::cli-options-pass-with-no-tests options) :to-be t))
    (with-mocked-functions
        (((symbol-function 'uiop:getenv)
          (lambda (name)
            (cdr (assoc name
                        '(("CL_WEAVE_PASS_WITH_NO_TESTS" . "false"))
                        :test #'string=)))))
      (let ((options (cl-weave/cli::options-from-environment)))
        (expect (cl-weave/cli::cli-options-pass-with-no-tests options)
                :to-be nil))))

  (it "rejects inline values for flag-only options"
    (dolist (token '("--help=1"
                     "--version=1"
                     "--coverage=false"
                     "--pass-with-no-tests=false"
                     "--fail-with-no-tests=true"
                     "--update-snapshots=false"))
      (expect (lambda ()
                (cl-weave/cli::parse-cli-arguments
                 (list "run" token)
                 (cl-weave/cli::make-cli-options)))
              :to-throw
              "does not accept an inline value")))

  (it "treats Lisp nil environment tokens as false"
    (with-mocked-functions
        (((symbol-function 'uiop:getenv)
          (lambda (name)
            (cdr (assoc name
                        '(("CL_WEAVE_COVERAGE" . "nil")
                          ("CL_WEAVE_LIST" . "nil")
                          ("CL_WEAVE_WATCH" . "nil")
                          ("CL_WEAVE_UPDATE_SNAPSHOTS" . "nil")
                          ("CL_WEAVE_PASS_WITH_NO_TESTS" . "nil"))
                        :test #'string=)))))
      (let ((options (cl-weave/cli::options-from-environment)))
        (expect (cl-weave/cli::cli-options-coverage options) :to-be nil)
        (expect (cl-weave/cli::cli-options-list options) :to-be nil)
        (expect (cl-weave/cli::cli-options-watch options) :to-be nil)
        (expect (cl-weave/cli::cli-options-update-snapshots options) :to-be nil)
        (expect (cl-weave/cli::cli-options-pass-with-no-tests options)
                :to-be nil))))

  (it "parses bail control from CI environment data"
    (labels ((bail-from (value)
               (with-mocked-functions
                   (((symbol-function 'uiop:getenv)
                     (lambda (name)
                       (when (string= name "CL_WEAVE_BAIL")
                         value))))
                 (cl-weave/cli::cli-options-bail
                  (cl-weave/cli::options-from-environment)))))
      (dolist (value '("0" "false" "no" "off" "nil"))
        (expect (bail-from value) :to-be nil))
      (dolist (value '("true" "yes" "on" "t"))
        (expect (bail-from value) :to-be t))
      (expect (bail-from "3") :to-be 3)
      (dolist (value '("maybe" "-1" "1.5"))
        (expect (lambda ()
                  (bail-from value))
                :to-throw
                "--bail must be true, false, or a positive integer"))))

  (it "parses retry and timeout defaults from CI environment data"
    (labels ((options-from (entries)
               (with-mocked-functions
                   (((symbol-function 'uiop:getenv)
                     (lambda (name)
                       (cdr (assoc name entries :test #'string=)))))
                 (cl-weave/cli::options-from-environment))))
      (let ((options (options-from '(("CL_WEAVE_RETRY" . "0")
                                     ("CL_WEAVE_TEST_TIMEOUT" . "2500")))))
        (expect (cl-weave/cli::cli-options-retry options) :to-be 0)
        (expect (cl-weave/cli::cli-options-test-timeout-ms options)
                :to-be 2500))
      (let ((options (options-from '(("CL_WEAVE_RETRY" . "3")
                                     ("CL_WEAVE_TEST_TIMEOUT" . "2500")
                                     ("CL_WEAVE_TEST_TIMEOUT_MS" . "125")
                                     ("CL_WEAVE_MAX_WORKERS" . "4")))))
        (expect (cl-weave/cli::cli-options-retry options) :to-be 3)
        (expect (cl-weave/cli::cli-options-test-timeout-ms options)
                :to-be 2500)
        (expect (cl-weave/cli::cli-options-max-workers options)
                :to-be 4))
      (expect (lambda ()
                (options-from '(("CL_WEAVE_RETRY" . "-1"))))
              :to-throw
              "CL_WEAVE_RETRY must be a non-negative integer")
      (expect (lambda ()
                (options-from '(("CL_WEAVE_TEST_TIMEOUT_MS" . "0"))))
              :to-throw
              "CL_WEAVE_TEST_TIMEOUT_MS must be positive")
      (expect (lambda ()
                (options-from '(("CL_WEAVE_MAX_WORKERS" . "0"))))
              :to-throw
              "CL_WEAVE_MAX_WORKERS must be positive")))

  (it "requires explicit CI sequence seeds to be positive integers"
    (labels ((seed-from (value)
               (with-mocked-functions
                   (((symbol-function 'uiop:getenv)
                     (lambda (name)
                       (when (string= name "CL_WEAVE_SEQUENCE_SEED")
                         value))))
                 (cl-weave/cli::cli-options-seed
                  (cl-weave/cli::options-from-environment)))))
      (expect (seed-from "42") :to-be 42)
      (dolist (value '("0" "-1" "1.5" "abc"))
        (expect (lambda ()
                  (seed-from value))
                :to-throw
                "CL_WEAVE_SEQUENCE_SEED"))))

  (it "accepts representative values for every environment-backed CLI option"
    (labels ((options-from (entries)
               (with-mocked-functions
                   (((symbol-function 'uiop:getenv)
                     (lambda (name)
                       (cdr (assoc name entries :test #'string=)))))
                 (cl-weave/cli::options-from-environment))))
      (dolist (sample
               '(("--system" . (("CL_WEAVE_SYSTEM" . "sample-system")))
                 ("--reporter" . (("CL_WEAVE_REPORTER" . "json")))
                 ("--filter" . (("CL_WEAVE_TEST_FILTER" . "focus")))
                 ("--output" . (("CL_WEAVE_OUTPUT_FILE" . "results.json")))
                 ("--list" . (("CL_WEAVE_LIST" . "1")))
                 ("--watch" . (("CL_WEAVE_WATCH" . "1")))
                 ("--once" . (("CL_WEAVE_WATCH_ONCE" . "1")))
                 ("--watch-interval" . (("CL_WEAVE_WATCH_INTERVAL" . "0.5")))
                 ("--bail" . (("CL_WEAVE_BAIL" . "2")))
                 ("--retry" . (("CL_WEAVE_RETRY" . "1")))
                 ("--test-timeout-ms" . (("CL_WEAVE_TEST_TIMEOUT" . "250")
                                         ("CL_WEAVE_TEST_TIMEOUT_MS" . "125")))
                 ("--max-workers" . (("CL_WEAVE_MAX_WORKERS" . "3")))
                 ("--shard" . (("CL_WEAVE_SHARD" . "1/2")))
                 ("--sequence" . (("CL_WEAVE_SEQUENCE" . "random")))
                 ("--seed" . (("CL_WEAVE_SEQUENCE_SEED" . "11")))
                 ("--coverage" . (("CL_WEAVE_COVERAGE" . "1")))
                 ("--coverage-output" . (("CL_WEAVE_COVERAGE_FILE" . "coverage.out")))
                 ("--pass-with-no-tests" . (("CL_WEAVE_PASS_WITH_NO_TESTS" . "true")))
                 ("--snapshot-dir" . (("CL_WEAVE_SNAPSHOT_DIR" . "tmp/__snapshots__/")))
                 ("--snapshot-file" . (("CL_WEAVE_SNAPSHOT_FILE" . "suite.snapshots")))
                 ("--update-snapshots" . (("CL_WEAVE_UPDATE_SNAPSHOTS" . "1")))))
        (expect (options-from (cdr sample)) :not :to-be nil))))

  (it "binds snapshot settings during CLI execution"
    (let ((observed nil)
          (options (cl-weave/cli::make-cli-options
                    :snapshot-directory #P"tmp/__snapshots__/"
                    :snapshot-file "cli.snapshots"
                    :update-snapshots t)))
      (with-mocked-functions
          (((symbol-function 'cl-weave:run-all)
            (lambda (&key reporter name-filter shard order seed bail coverage
                     retry timeout-ms max-workers coverage-output
                     pass-with-no-tests stream)
              (declare (ignore reporter name-filter shard order seed bail coverage
                               retry timeout-ms max-workers coverage-output
                               pass-with-no-tests stream))
              (setf observed
                    (list cl-weave:*snapshot-directory*
                          cl-weave:*snapshot-file-name*
                          cl-weave:*update-snapshots*))
              t)))
        (expect (cl-weave/cli::run-command options) :to-be t))
      (expect observed
              :to-equal (list #P"tmp/__snapshots__/" "cli.snapshots" t))))

  (it "generates CLI data and field operations from one schema"
    (let* ((expansion
             (macroexpand-1
              '(cl-weave/cli::define-cli-options
                 (:fields value (items '() :type list))
                 (:options
                  (:flag "--value" :kind :value :field :value)
                  (:flag "--item" :kind :collection :field :items))
                 (:environment
                  (:flag "--value" :kind :value :field :value)))))
           (definitions (rest expansion)))
      (expect (first expansion) :to-be 'progn)
      (dolist (name '(defstruct defparameter defun))
        (expect (find name definitions :key #'first) :not :to-be nil))
      (expect (count 'defparameter definitions :key #'first) :to-be 2)
      (expect (count 'defun definitions :key #'first) :to-be 2)))

  (it "rejects invalid CLI schemas during macroexpansion"
    (dolist
        (case
         (list
          (list
           '(cl-weave/cli::define-cli-options
              (:fields value)
              (:options
               (:flag "--value" :kind :value :field :value)
               (:flag "--value" :kind :flag :field :value))
              (:environment))
           "Duplicate command-line CLI flag")
          (list
           '(cl-weave/cli::define-cli-options
              (:fields value)
              (:options)
              (:environment
               (:flag "--value" :kind :value :field :value)
               (:flag "--value" :kind :truthy :field :value)))
           "Duplicate environment CLI flag")
          (list
           '(cl-weave/cli::define-cli-options
              (:fields value)
              (:options (:flag "--missing" :kind :value :field :missing))
              (:environment))
           "Unknown CLI option field")
          (list
           '(cl-weave/cli::define-cli-options
              (:fields value)
              (:options (:flag "--value" :kind :stream :field :value))
              (:environment))
           "Unknown command-line CLI option kind")
          (list
           '(cl-weave/cli::define-cli-options
              (:fields value)
              (:options)
              (:environment (:flag "--value" :kind :stream :field :value)))
           "Unknown environment CLI option kind")))
      (expect (lambda () (macroexpand-1 (first case)))
              :to-throw
              (second case))))

)
