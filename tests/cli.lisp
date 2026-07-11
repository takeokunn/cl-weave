(in-package #:cl-weave/tests)

(defun workflow-step-blocks (workflow)
  (loop with marker = "      - name:"
        with length = (length workflow)
        for start = (search marker workflow)
          then (and end (search marker workflow :start2 end))
        while start
        for end = (or (search marker workflow :start2 (+ start (length marker)))
                      length)
        collect (subseq workflow start end)))

(defun workflow-step-for-command (workflow command)
  (let ((command-text (normalize-shell-text (workflow-command-string command))))
    (find-if (lambda (step)
               (search command-text (normalize-shell-text step)))
             (workflow-step-blocks workflow))))

(defun workflow-timeout-minutes-for-command (workflow command)
  (let ((step (workflow-step-for-command workflow command)))
    (when step
      (let* ((marker "timeout-minutes:")
             (marker-position (search marker step)))
        (when marker-position
          (let* ((line-start (+ marker-position (length marker)))
                 (line-end (or (position #\Newline step :start line-start)
                               (length step)))
                 (line (string-trim '(#\Space #\Tab)
                                    (subseq step line-start line-end))))
            (parse-integer line)))))))

(defun minimum-workflow-timeout-minutes (timeout-seconds)
  (ceiling timeout-seconds 60))

(defun workflow-artifact-section (workflow)
  (let ((section-position (search "path: |" workflow)))
    (if section-position
        (subseq workflow section-position)
        "")))

(defun workflow-covers-quality-gate-p (workflow gate)
  (not (null (workflow-step-for-command workflow (getf gate :command)))))

(defun flake-check-names (flake)
  (loop with marker = " = mkCheck {"
        for line in (uiop:split-string flake :separator '(#\Newline))
        for trimmed = (string-trim '(#\Space #\Tab) line)
        for position = (search marker trimmed)
        when position
          collect (subseq trimmed 0 position)))

(defun packaged-cli-initializes-output-translations-p (flake)
  (not (null
        (search
         "(asdf:initialize-output-translations (quote (:output-translations (t (:home \".cache\" \"common-lisp\" :implementation)) :ignore-inherited-configuration)))"
         flake
         :test #'char=))))

(describe "cli"
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
      (expect (cl-weave/cli::parse-reporter "ndjson") :to-be :jsonl)
      (expect (cl-weave/cli::parse-reporter "github") :to-be :github)
      (expect (lambda ()
                (cl-weave/cli::parse-reporter "unknown"))
              :to-throw
              "cl-weave: unknown reporter")
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
                 ("--sequence" . (("CL_WEAVE_SEQUENCE" . "shuffle")))
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

  (it "writes JSON result artifacts through the CLI output option"
    (let* ((output-file (test-temporary-pathname "cl-weave-cli-results.json"))
           (options (cl-weave/cli::make-cli-options
                     :reporter :json
                     :output-file (namestring output-file))))
      (when (probe-file output-file)
        (delete-file output-file))
      (unwind-protect
           (progn
             (with-mocked-functions
                 (((symbol-function 'cl-weave:run-all)
                   (lambda (&key reporter name-filter shard order seed bail coverage
                            retry timeout-ms max-workers coverage-output
                            pass-with-no-tests stream)
                     (declare (ignore name-filter shard order seed bail coverage
                                      retry timeout-ms max-workers coverage-output
                                      pass-with-no-tests))
                     (expect reporter :to-be :json)
                     (cl-weave::report-json nil stream)
                     t)))
               (expect (with-output-to-string (*standard-output*)
                         (cl-weave/cli::run-command options))
                       :to-equal ""))
             (let ((output (read-text-file output-file)))
               (expect output :to-contain "\"schemaVersion\":5")
               (expect output :to-contain "\"kind\":\"test-results\"")
               (expect output :to-contain "\"events\":[]")))
        (when (probe-file output-file)
          (delete-file output-file))))

  (it "parses list and watch commands without executing tests"
    (let ((list-options (cl-weave/cli::parse-cli-arguments
                         '("list" "cl-weave-tests" "--reporter" "sexp")
                         (cl-weave/cli::make-cli-options)))
          (watch-options (cl-weave/cli::parse-cli-arguments
                          '("watch" "cl-weave-tests" "--watch-interval" "1.5")
                          (cl-weave/cli::make-cli-options))))
      (expect (cl-weave/cli::cli-options-command list-options) :to-be :list)
      (expect (cl-weave/cli::cli-options-list list-options) :to-be t)
      (expect (cl-weave/cli::cli-options-reporter list-options) :to-be :sexp)
      (expect (cl-weave/cli::cli-options-command watch-options) :to-be :watch)
      (expect (cl-weave/cli::cli-options-watch watch-options) :to-be t)
      (expect (cl-weave/cli::cli-options-watch-once watch-options) :to-be nil)
      (expect (cl-weave/cli::cli-options-watch-interval watch-options)
              :to-be 1.5)))

  (it "forwards coverage settings through CLI watch mode"
    (let ((options (cl-weave/cli::make-cli-options
                    :command :watch
                    :watch t
                    :systems '("cl-weave")
                    :reporter :json
                    :name-filter "watch"
                    :coverage t
                    :coverage-output "watch.coverage.sexp"
                    :pass-with-no-tests t
                    :watch-once t
                    :watch-interval 1.25
                    :max-workers 4)))
      (multiple-value-bind (system arguments)
          (cl-weave/cli::watch-command-call-arguments options)
        (expect system
                :to-satisfy
                (lambda (value)
                  (string= value "cl-weave")))
        (expect arguments
                :to-equal
                '(:reporter :json
                  :name-filter "watch"
                  :shard nil
                  :order :defined
                  :seed nil
                  :bail nil
                  :coverage t
                  :coverage-output "watch.coverage.sexp"
                  :pass-with-no-tests t
                  :retry 0
                  :timeout-ms nil
                  :max-workers 4
                  :include-dependencies t
                  :once t
                  :interval 1.25)))))

  (it "prints AI-friendly framework metadata"
    (let ((options (cl-weave/cli::parse-cli-arguments
                    '("metadata" "cl-weave-tests")
                    (cl-weave/cli::make-cli-options))))
      (expect (cl-weave/cli::cli-options-command options) :to-be :metadata)
      (expect (cl-weave/cli::cli-options-systems options)
              :to-equal '("cl-weave-tests"))
      (let ((output (with-output-to-string (stream)
                      (cl-weave/cli::report-framework-metadata options stream))))
        (expect output :to-contain "\"kind\":\"cl-weave-metadata\"")
        (expect output :to-contain "\"schemaVersion\":22")
        (expect output :to-contain "\"homepage\"")
        (expect output :to-contain "\"bugTracker\"")
        (expect output :to-contain "\"commands\"")
        (expect output :to-contain "\"metadata\"")
        (expect output :to-contain "\"artifactSchemas\"")
        (expect output :to-contain "\"kind\":\"test-results\"")
        (expect output :to-contain "\"schemaVersion\":5")
        (expect output :to-contain "\"fields\"")
        (expect output :to-contain "\"name\":\"events\"")
        (expect output :to-contain "\"kind\":\"array\"")
        (expect output :to-contain "\"required\":true")
        (expect output :to-contain "\"kind\":\"test-plan\"")
        (expect output :to-contain "\"schemaVersion\":2")
        (expect output :to-contain "\"streaming\":true")
        (expect output :to-contain "\"name\":\"test.tags\"")
        (expect output :to-contain "\"name\":\"test.dependsOn\"")
        (expect output :to-contain "\"qualityGates\"")
        (expect output :to-contain "\"capabilityMatrix\"")
        (expect output :to-contain "\"citation\"")
        (expect output :to-contain "\"cffVersion\":\"1.2.0\"")
        (expect output :to-contain "\"distributionChannels\"")
        (expect output :to-contain "\"name\":\"source-self-test\"")
        (expect output :to-contain "\"installCommand\":[]")
        (expect output :to-contain
                "\"runCommand\":[\"sbcl\",\"--noinform\",\"--non-interactive\",\"--load\",\"scripts\\/run-tests.lisp\"]")
        (expect output :to-contain "\"governance\"")
        (expect output :to-contain "\"policyDocument\":\"docs\\/governance.md\"")
        (expect output :to-contain "\"reviewOwnership\":\".github\\/CODEOWNERS\"")
        (expect output :to-contain "\"maintainerResponsibilities\"")
        (expect output :to-contain "\"decisionDocuments\"")
        (expect output :to-contain "\"name\":\"vitest-dsl\"")
        (expect output :to-contain "\"publicApis\"")
        (expect output :to-contain "\"qualityGates\":[\"flake-check\",\"filtered-smoke\",\"plan-artifact\"]")
        (expect output :to-contain "\"documentation\":[\"README.md\",\"docs\\/ai-contract.md\"]")
        (expect output :to-contain "\"name\":\"flake-check\"")
        (expect output :to-contain "\"command\":[\"nix\",\"flake\",\"check\",\"--print-build-logs\"]")
        (expect output :to-contain "\"timeoutSeconds\":600")
        (expect output :to-contain "\"name\":\"ai-metadata-artifact\"")
        (expect output :to-contain "\"cl-weave-metadata.json\"")
        (expect output :to-contain "\"name\":\"tap-artifact\"")
        (expect output :to-contain "\"Verify TAP output for line-oriented CI logs.\"")
        (expect output :to-contain "\"name\":\"filtered-smoke\"")
        (expect output :to-contain "\"CL_WEAVE_TEST_FILTER=filtering > runs only tests matching a path substring\"")
        (expect output :to-contain "\"options\"")
        (expect output :to-contain "\"listReporters\"")
        (expect output :to-contain "\"valueKind\"")
        (expect output :to-contain "\"commandChoices\"")
        (expect output :to-contain "\"name\":\"--reporter\"")
        (expect output :to-contain "\"command\":\"metadata\"")
        (expect output :to-contain "\"choices\":[\"json\",\"sexp\"]")
        (expect output :to-contain "\"--filter\"")
        (expect output :not :to-contain "\"--testNamePattern\"")
        (expect output :to-contain "\"CL_WEAVE_TEST_FILTER\"")
        (expect output :to-contain "\"--update-snapshots\"")
        (expect output :not :to-contain "\"--updateSnapshots\"")
        (expect output :to-contain "\"matchers\"")
        (expect output :to-contain "\"to-be-even\"")
        (expect output :to-contain "\"mutationOperators\"")
        (expect output :to-contain "\"arithmetic-operator\"")
        (expect output :to-contain "\"packageExports\"")
        (expect output :to-contain "\"cl-weave\"")
        (expect output :to-contain "\"DESCRIBE\"")
        (expect output :to-contain "\"EXPECT\"")
        (expect output :to-contain "\"vitestAliases\"")
        (expect output :to-contain "\"describe.only.each\"")
        (expect output :to-contain "\"it.property\"")
        (expect output :to-contain "\"test.isolated\"")
        (expect output :to-contain "\"expect.hasassertions\"")
        (expect output :to-contain "\"vi.mocked\"")
        (expect output :to-contain "\"vi.mockreturnvalues\"")
        (expect output :to-contain "\"vi.clearallmocks\"")
        (expect output :to-contain "\"vi.spyon\""))))

  (it "allows Lisp-native metadata output"
    (let ((options (cl-weave/cli::parse-cli-arguments
                    '("metadata" "--reporter" "sexp")
                    (cl-weave/cli::make-cli-options))))
      (let ((output (with-output-to-string (stream)
                      (cl-weave/cli::report-framework-metadata options stream))))
        (expect output :to-contain ":KIND \"cl-weave-metadata\"")
        (expect output :to-contain ":OPTIONS")
        (expect output :to-contain ":PACKAGE-EXPORTS"))))

  (it "prints machine-readable doctor output"
    (let ((options (cl-weave/cli::parse-cli-arguments
                    '("doctor" "--reporter" "json")
                    (cl-weave/cli::make-cli-options))))
      (let ((output (with-output-to-string (stream)
                      (cl-weave/cli::report-doctor options stream))))
        (expect output :to-contain "\"kind\":\"doctor-report\"")
        (expect output :to-contain "\"schemaVersion\":1")
        (expect output :to-contain "\"status\":\"")
        (expect output :to-contain "\"runtime\"")
        (expect output :to-contain "\"checks\"")
        (expect output :to-contain "\"name\":\"command-metadata\"")
        (expect output :to-contain "\"name\":\"workspace-asd-files\""))))

  (it "renders doctor output from the parsed CLI options"
    (let* ((options (cl-weave/cli::parse-cli-arguments
                     '("doctor" "definitely-missing-system"
                       "--reporter" "json"
                       "--output" "doctor.json")
                     (cl-weave/cli::make-cli-options)))
           (output (with-output-to-string (stream)
                     (cl-weave/cli::report-doctor options stream))))
      (expect output :to-contain "\"name\":\"requested-system\"")
      (expect output :to-contain "\"status\":\"fail\"")
      (expect output :to-contain "definitely-missing-system")
      (expect output :to-contain "\"name\":\"output-target\"")
      (expect output :to-contain "doctor.json")))

  (it "allows Lisp-native doctor output"
    (let ((options (cl-weave/cli::parse-cli-arguments
                    '("doctor" "--reporter" "sexp")
                    (cl-weave/cli::make-cli-options))))
      (let ((output (with-output-to-string (stream)
                      (cl-weave/cli::report-doctor options stream))))
        (expect output :to-contain ":KIND \"doctor-report\"")
        (expect output :to-contain ":CHECKS")
        (expect output :to-contain ":RUNTIME"))))

  (it "treats doctor without a positional system as runtime-only diagnostics"
    (let* ((options (cl-weave/cli::parse-cli-arguments
                     '("doctor" "--reporter" "json")
                     (cl-weave/cli::make-cli-options)))
           (report (cl-weave/cli::doctor-report options))
           (checks (getf report :checks))
           (requested-system
             (find "requested-system" checks
                   :key (lambda (entry) (getf entry :name))
                   :test #'string=))
           (output-target
             (find "output-target" checks
                   :key (lambda (entry) (getf entry :name))
                   :test #'string=)))
      (expect (getf requested-system :status) :to-equal "pass")
      (expect (getf requested-system :summary)
              :to-contain "runtime-only mode")
      (expect (getf output-target :status) :to-equal "pass")
      (expect (getf output-target :summary)
              :to-contain "standard output")))

  (it "reports requested-system failures independently from runtime diagnostics"
    (let* ((options (cl-weave/cli::parse-cli-arguments
                     '("doctor" "definitely-missing-system" "--output" "doctor.json")
                     (cl-weave/cli::make-cli-options)))
           (report (cl-weave/cli::doctor-report options))
           (checks (getf report :checks))
           (cl-weave-system
             (find "cl-weave-system" checks
                   :key (lambda (entry) (getf entry :name))
                   :test #'string=))
           (requested-system
             (find "requested-system" checks
                   :key (lambda (entry) (getf entry :name))
                   :test #'string=))
           (output-target
             (find "output-target" checks
                   :key (lambda (entry) (getf entry :name))
                   :test #'string=)))
      (expect (getf cl-weave-system :status) :to-equal "pass")
      (expect (getf requested-system :status) :to-equal "fail")
      (expect (getf requested-system :summary)
              :to-contain "definitely-missing-system")
      (expect (getf output-target :summary)
              :to-contain "doctor.json")))

  (it "keeps the AI contract synchronized with metadata root fields"
    (let ((docs (read-text-file (merge-pathnames #P"docs/ai-contract.md"
                                                 (uiop:getcwd)))))
      (dolist (field cl-weave/cli::*framework-metadata-json-fields*)
        (destructuring-bind (metadata-key json-key writer) field
          (declare (ignore metadata-key writer))
          (expect docs :to-contain json-key)))
      (dolist (field cl-weave/cli::*json-capability-matrix-fields*)
        (destructuring-bind (metadata-key json-key writer) field
          (declare (ignore metadata-key writer))
          (expect docs :to-contain json-key)))
      (dolist (field cl-weave/cli::*json-reference-document-fields*)
        (destructuring-bind (metadata-key json-key writer) field
          (declare (ignore metadata-key writer))
          (expect docs :to-contain json-key)))
      (dolist (field cl-weave/cli::*json-citation-fields*)
        (destructuring-bind (metadata-key json-key writer) field
          (declare (ignore metadata-key writer))
          (expect docs :to-contain json-key)))
      (dolist (field cl-weave/cli::*json-citation-author-fields*)
        (destructuring-bind (metadata-key json-key writer) field
          (declare (ignore metadata-key writer))
          (expect docs :to-contain json-key)))
      (dolist (field cl-weave/cli::*json-distribution-channel-fields*)
        (destructuring-bind (metadata-key json-key writer) field
          (declare (ignore metadata-key writer))
          (expect docs :to-contain json-key)))
      (dolist (field cl-weave/cli::*json-community-health-fields*)
        (destructuring-bind (metadata-key json-key writer) field
          (declare (ignore metadata-key writer))
          (expect docs :to-contain json-key)))
      (dolist (field cl-weave/cli::*json-community-health-contact-link-fields*)
        (destructuring-bind (metadata-key json-key writer) field
          (declare (ignore metadata-key writer))
          (expect docs :to-contain json-key)))
      (dolist (field cl-weave/cli::*json-governance-fields*)
        (destructuring-bind (metadata-key json-key writer) field
          (declare (ignore metadata-key writer))
          (expect docs :to-contain json-key)))
      (dolist (field cl-weave/cli::*json-continuous-integration-fields*)
        (destructuring-bind (metadata-key json-key writer) field
          (declare (ignore metadata-key writer))
          (expect docs :to-contain json-key)))))

  (it "keeps the AI contract example version synchronized with the CLI version"
    (let* ((docs (read-text-file (merge-pathnames #P"docs/ai-contract.md"
                                                  (uiop:getcwd))))
           (version (cl-weave/cli::cli-version)))
      (expect version :not :to-equal "unknown")
      (expect docs :to-contain (format nil "\"version\": \"~A\"" version))))

  (it "keeps the AI contract release-process example synchronized with metadata"
    (let* ((docs (read-text-file (merge-pathnames #P"docs/ai-contract.md"
                                                  (uiop:getcwd))))
           (normalized-docs (normalize-markdown-text docs))
           (metadata (getf (cl-weave/cli::framework-metadata) :release-process)))
      (expect normalized-docs
              :to-contain
              (normalize-markdown-text
               (format nil "\"policyDocument\": \"~A\"" (getf metadata :policy-document))))
      (expect normalized-docs
              :to-contain
              (normalize-markdown-text
               (format nil "\"releaseStage\": \"~A\"" (getf metadata :release-stage))))
      (dolist (item (getf metadata :checklist))
        (expect normalized-docs
                :to-contain
                (normalize-markdown-text item)))
      (dolist (item (getf metadata :contract-sync-requirements))
        (expect normalized-docs
                :to-contain
                (normalize-markdown-text item)))))

  (it "advertises canonical project links as metadata"
    (let ((metadata (cl-weave/cli::framework-metadata)))
      (expect (getf metadata :homepage)
              :to-equal "https://github.com/takeokunn/cl-weave")
      (expect (getf metadata :bug-tracker)
              :to-equal "https://github.com/takeokunn/cl-weave/issues")
      (expect (getf metadata :license)
              :to-equal "MIT")
      (expect (getf metadata :policy-documents)
              :to-equal '("CONTRIBUTING.md"
                          "CODE_OF_CONDUCT.md"
                          "SECURITY.md"
                          "docs/community-health.md"
                          "docs/distribution-policy.md"
                          "docs/governance.md"
                          "docs/issue-reporting.md"
                          "docs/maintenance-policy.md"
                          "docs/project-scope.md"
                          "docs/pull-request-template.md"
                          "docs/release-process.md"
                          "docs/runtime-support.md"
                          "docs/support-policy.md"
                          "docs/triage-policy.md"
                          "docs/versioning-policy.md"))
      (expect (getf metadata :reference-documents)
              :to-equal '((:name "readme"
                           :path "README.md"
                           :description "Primary user-facing guide and CLI reference.")
                          (:name "citation"
                           :path "CITATION.cff"
                           :description "Canonical citation metadata for research, cataloging, and downstream attribution.")
                          (:name "ai-contract"
                           :path "docs/ai-contract.md"
                           :description "Machine-readable contract and metadata normalization guide.")
                          (:name "adoption-guide"
                           :path "docs/adoption.md"
                           :description "Migration guidance and downstream adoption plan.")
                          (:name "release-notes"
                           :path "CHANGELOG.md"
                           :description "User-visible changes and release history.")
                          (:name "license"
                           :path "LICENSE"
                           :description "Canonical project license text.")))
      (expect (getf metadata :citation)
              :to-equal '(:cff-version "1.2.0"
                          :message "If you use cl-weave in research, tooling, or documentation, please cite the project using this metadata."
                          :title "cl-weave"
                          :authors ((:name "takeokunn"))
                          :license "MIT"
                          :repository-code "https://github.com/takeokunn/cl-weave"
                          :url "https://github.com/takeokunn/cl-weave"
                          :version "0.1.0"
                          :preferred-citation-path "CITATION.cff"))
      (expect (getf metadata :distribution-channels)
              :to-equal '((:name "source-self-test"
                           :kind "source-checkout"
                           :install-command ()
                           :run-command ("sbcl" "--noinform" "--non-interactive" "--load" "scripts/run-tests.lisp")
                           :scope "Run the bundled self-test suite from a source checkout."
                           :references ("README.md"
                                        "docs/distribution-policy.md"))
                          (:name "nix-local-cli"
                           :kind "nix"
                           :install-command ("nix" "profile" "install" ".")
                           :run-command ("nix" "run" "." "--" "--help")
                           :scope "Install and run the packaged CLI from the current checkout."
                           :references ("README.md"
                                        "docs/distribution-policy.md"))
                          (:name "nix-remote-cli"
                           :kind "nix"
                           :install-command ("nix" "profile" "install" "github:takeokunn/cl-weave")
                           :run-command ("nix" "run" "github:takeokunn/cl-weave" "--" "--help")
                           :scope "Install and run the packaged CLI without cloning the repository."
                           :references ("README.md"
                                        "docs/distribution-policy.md"))))
      (expect (getf metadata :support-channels)
              :to-equal '((:name "issue-tracker"
                           :kind "github"
                           :target "https://github.com/takeokunn/cl-weave/issues"
                           :scope "Reproducible bugs, documentation gaps, and concrete feature requests.")
                          (:name "pull-requests"
                           :kind "github"
                           :target "https://github.com/takeokunn/cl-weave/pulls"
                           :scope "Validated fixes that are ready for review.")
                          (:name "support-policy"
                           :kind "document"
                           :target "docs/support-policy.md"
                           :scope "Canonical support boundaries, report contents, and escalation guidance.")))
      (expect (getf metadata :community-health)
              :to-equal '((:name "bug-report-form"
                           :kind "github-issue-template"
                           :path ".github/ISSUE_TEMPLATE/bug_report.md"
                           :purpose "Structured bug intake that routes reporters to the canonical issue reporting guide."
                           :references ("docs/community-health.md"
                                        "docs/issue-reporting.md")
                           :required-sections ("Summary"
                                               "Reproduction"
                                               "Expected Behavior"
                                               "Actual Behavior"
                                               "Validation"
                                               "Additional Context")
                           :contact-links nil)
                          (:name "feature-request-form"
                           :kind "github-issue-template"
                           :path ".github/ISSUE_TEMPLATE/feature_request.md"
                           :purpose "Structured feature intake that reinforces project scope and validation expectations."
                           :references ("docs/community-health.md"
                                        "docs/project-scope.md"
                                        "docs/support-policy.md")
                           :required-sections ("Problem"
                                               "Proposed Change"
                                               "Validation Plan"
                                               "Scope Check"
                                               "Compatibility Notes")
                           :contact-links nil)
                          (:name "issue-template-config"
                           :kind "github-issue-template-config"
                           :path ".github/ISSUE_TEMPLATE/config.yml"
                           :purpose "GitHub issue chooser configuration that redirects support and security traffic to canonical policies."
                           :references ("docs/community-health.md"
                                        "docs/support-policy.md"
                                        "SECURITY.md"
                                        "docs/issue-reporting.md")
                           :required-sections nil
                           :contact-links ((:name "Support policy"
                                            :target "https://github.com/takeokunn/cl-weave/blob/main/docs/support-policy.md"
                                            :purpose "Check whether the request belongs in issue tracking and what detail is required.")
                                           (:name "Security policy"
                                            :target "https://github.com/takeokunn/cl-weave/blob/main/SECURITY.md"
                                            :purpose "Report vulnerabilities through the private security contact path.")
                                           (:name "Issue reporting guide"
                                            :target "https://github.com/takeokunn/cl-weave/blob/main/docs/issue-reporting.md"
                                            :purpose "Review the canonical reproduction format before filing a bug.")))
                          (:name "pull-request-template"
                           :kind "github-pull-request-template"
                           :path ".github/pull_request_template.md"
                           :purpose "Default PR body that mirrors the canonical review checklist and compatibility prompts."
                           :references ("docs/community-health.md"
                                        "docs/pull-request-template.md")
                           :required-sections ("Summary"
                                               "Validation"
                                               "Compatibility Impact"
                                               "Follow-up Risk")
                           :contact-links nil)
                          (:name "codeowners"
                           :kind "github-codeowners"
                           :path ".github/CODEOWNERS"
                           :purpose "Review ownership declaration for repository-wide changes."
                           :references ("docs/community-health.md"
                                        "docs/governance.md")
                           :required-sections nil
                           :contact-links nil)))
      (expect (getf metadata :security-contacts)
              :to-equal '((:name "security-policy"
                           :kind "document"
                           :target "SECURITY.md"
                           :scope "Private vulnerability reporting guidance and security handling policy.")))
      (expect (getf metadata :lifecycle)
              :to-equal '(:stage "pre-1.0"
                          :status "active"
                          :supported-line "main"
                          :support-document "docs/support-policy.md"
                          :versioning-document "docs/versioning-policy.md"
                          :security-document "SECURITY.md"))
      (expect (getf metadata :governance)
              :to-equal '(:policy-document "docs/governance.md"
                          :review-ownership ".github/CODEOWNERS"
                          :maintainer-responsibilities
                          ("Triaging issues and pull requests against the documented project scope and support boundaries."
                           "Protecting compatibility expectations recorded in the versioning policy."
                           "Keeping machine-readable metadata, release notes, and policy documents synchronized."
                           "Requiring regression coverage for public-surface changes when practical."
                           "Handling security-sensitive reports through the private SECURITY.md path.")
                          :decision-documents
                          ("docs/project-scope.md"
                           "docs/support-policy.md"
                           "docs/triage-policy.md"
                           "docs/versioning-policy.md"
                           "docs/release-process.md")
                          :release-authority
                          "Maintainers cut releases from the validated default branch state only."
                          :continuity-expectation
                          "When the maintainer set changes, update governance, linked policies, and machine-readable metadata in the same patch."))
      (expect (getf metadata :runtime-support)
              :to-equal '(:policy-document "docs/runtime-support.md"
                          :primary-implementation "SBCL"
                          :supported-targets ((:implementation "SBCL"
                                               :platforms ("Linux" "macOS")
                                               :status "supported"))
                          :best-effort-targets
                          ((:implementation "Other Common Lisp implementations"
                            :platforms ("implementation-dependent")
                            :status "best-effort"))
                          :implementation-specific-features
                          ("it-isolated subprocess execution"
                           "coverage capture and reset/save integration"
                           "allocation assertions in CI-focused tests"
                           "MOP-dependent metadata and structural assertions")))
      (expect (getf metadata :release-process)
              :to-equal '(:policy-document "docs/release-process.md"
                          :release-stage "pre-1.0"
                          :checklist
                          ("Run the full test suite."
                           "Run nix flake check --print-build-logs when Nix is available."
                           "Review CHANGELOG.md and summarize user-visible changes."
                           "Check that README.md, CONTRIBUTING.md, SECURITY.md, and docs/maintenance-policy.md still match the current workflow."
                           "Review docs/pull-request-template.md and .github/pull_request_template.md so release-bound changes still capture public-surface notes, validation commands, and follow-up risk in a consistent format."
                           "Verify that cl-weave metadata still advertises the expected package links, reporter list, and schema versions."
                           "Verify that docs/distribution-policy.md still matches the documented source and Nix install paths."
                           "Confirm the release notes mention any intentional public-surface breaks or migration steps.")
                          :contract-sync-requirements
                          ("Keep machine-readable metadata and human-facing documentation in sync."
                           "Keep distributionChannels, README.md, and docs/distribution-policy.md synchronized when install paths change."
                           "Update tests and docs/ai-contract.md when a machine-readable contract changes.")))
      (expect (getf metadata :continuous-integration)
              :to-equal '(:policy-document "docs/release-process.md"
                          :provider "github-actions"
                          :workflow-path ".github/workflows/ci.yml"
                          :job-name "nix"
                          :triggers ("pull_request" "push:main" "workflow_dispatch")
                          :systems ("x86_64-linux" "aarch64-darwin")
                          :artifact-bundle "cl-weave-test-reports-${{ matrix.system }}"
                          :cache-provider "cachix"
                          :cache-modes ("pull-only" "push-enabled")
                          :quality-gate-source "qualityGates"))))

  (it "writes AI metadata artifacts through the CLI output option"
    (let* ((output-file (test-temporary-pathname "cl-weave-metadata.json"))
           (options (cl-weave/cli::parse-cli-arguments
                     (list "metadata"
                           "--reporter" "json"
                           "--output" (namestring output-file))
                     (cl-weave/cli::make-cli-options))))
      (when (probe-file output-file)
        (delete-file output-file))
      (unwind-protect
           (progn
             (expect (with-output-to-string (*standard-output*)
                       (cl-weave/cli::run-command options))
                     :to-equal "")
             (let ((output (read-text-file output-file)))
               (expect output :to-contain "\"kind\":\"cl-weave-metadata\"")
    (expect output :to-contain "\"schemaVersion\":22")
               (expect output :to-contain "\"artifactSchemas\"")
               (expect output :to-contain "\"qualityGates\"")
               (expect output :to-contain "\"capabilityMatrix\"")
               (expect output :to-contain "\"packageExports\"")
               (expect output :to-contain "\"policyDocuments\"")
               (expect output :to-contain "\"referenceDocuments\"")
               (expect output :to-contain "\"citation\"")
               (expect output :to-contain "\"distributionChannels\"")
               (expect output :to-contain "\"supportChannels\"")
               (expect output :to-contain "\"communityHealth\"")
               (expect output :to-contain "\"requiredSections\"")
               (expect output :to-contain "\"contactLinks\"")
               (expect output :to-contain "\"purpose\":\"Check whether the request belongs in issue tracking and what detail is required.\"")
               (expect output :to-contain "\"securityContacts\"")
               (expect output :to-contain "\"lifecycle\"")
               (expect output :to-contain "\"governance\"")
               (expect output :to-contain "\"runtimeSupport\"")
               (expect output :to-contain "\"releaseProcess\"")
               (expect output :to-contain "\"continuousIntegration\""))))
        (when (probe-file output-file)
          (delete-file output-file)))))

  (it "serializes framework metadata from the supplied plist"
    (let* ((metadata (list
                      :kind "custom-metadata"
                      :schema-version 7
                      :version "test-version"
                      :commands '("custom-command")
                      :reporters '("custom-reporter")
                      :list-reporters '("custom-list-reporter")
                      :runtime-support
                      (list :policy-document "docs/runtime-support.md"
                            :primary-implementation "SBCL"
                            :supported-targets
                            (list (list :implementation "SBCL"
                                        :platforms '("Linux")
                                        :status "supported"))
                            :best-effort-targets
                            (list (list :implementation "Other CL"
                                        :platforms '("implementation-dependent")
                                        :status "best-effort"))
                            :implementation-specific-features
                            '("custom runtime feature"))
                      :governance
                      (list :policy-document "docs/governance.md"
                            :review-ownership ".github/CODEOWNERS"
                            :maintainer-responsibilities
                            '("custom maintainer responsibility")
                            :decision-documents
                            '("docs/project-scope.md")
                            :release-authority "custom release authority"
                            :continuity-expectation "custom continuity expectation")
                      :release-process
                      (list :policy-document "docs/release-process.md"
                            :release-stage "pre-1.0"
                            :checklist '("custom release check")
                            :contract-sync-requirements
                            '("custom sync requirement"))
                      :continuous-integration
                      (list :policy-document "docs/release-process.md"
                            :provider "github-actions"
                            :workflow-path ".github/workflows/ci.yml"
                            :job-name "nix"
                            :triggers '("pull_request")
                            :systems '("x86_64-linux")
                            :artifact-bundle "cl-weave-test-reports-${{ matrix.system }}"
                            :cache-provider "cachix"
                            :cache-modes '("pull-only")
                            :quality-gate-source "qualityGates")
                      :artifact-schemas
                      (list (list :kind "custom-artifact"
                                  :commands '()
                                  :reporters '("custom-reporter")
                                  :schema-version 9
                                  :streaming t
                                  :fields
                                  (list (list :name "payload"
                                              :kind "object"
                                              :required t
                                              :description "custom payload"))))
                      :quality-gates
                      (list (list :name "custom-gate"
                                  :kind "custom-kind"
                                  :command '("custom" "check")
                                  :timeout-seconds 42
                                  :artifacts '("custom-artifact.json")
                                  :description "custom gate"))
                      :capabilities '("custom-capability")
                      :capability-matrix
                      (list (list :name "custom-capability"
                                  :status "implemented"
                                  :summary "custom capability summary"
                                  :public-apis '("custom-api")
                                  :quality-gates '("custom-gate")
                                  :documentation '("CUSTOM.md")))
                      :environment '("CUSTOM_ENV")
                      :options
                      (list (list :name "--custom"
                                  :aliases '("--customAlias")
                                  :commands '("custom-command")
                                  :argument "VALUE"
                                  :value-kind :custom-value
                                  :choices '("custom-choice")
                                  :command-choices
                                  '(("custom-command" ("custom-choice")))
                                  :environment '("CUSTOM_ENV")
                                  :description "custom option"))
                      :vitest-aliases
                      (list (list :alias "custom.alias"
                                  :canonical "custom-canonical"))
                      :package-exports
                      (list (list :name "custom-package"
                                  :exports '("custom-export")))
                      :matchers
                      (list (list :name :custom-matcher
                                  :description "custom matcher"))
                      :distribution-channels
                      (list (list :name "custom-distribution"
                                  :kind "custom"
                                  :install-command '("custom" "install")
                                  :run-command '("custom" "run")
                                  :scope "custom scope"
                                  :references '("CUSTOM.md")))
                      :mutation-operators
                      (list (list :name :custom-mutator
                                  :description "custom mutation operator"))))
           (output (with-output-to-string (stream)
                     (cl-weave/cli::write-framework-metadata-json
                      metadata stream))))
      (expect output :to-contain "\"kind\":\"custom-metadata\"")
      (expect output :to-contain "\"schemaVersion\":7")
      (expect output :to-contain "\"custom-command\"")
      (expect output :to-contain "\"custom-list-reporter\"")
      (expect output :to-contain "\"artifactSchemas\"")
      (expect output :to-contain "\"kind\":\"custom-artifact\"")
      (expect output :to-contain "\"commands\":[]")
      (expect output :to-contain "\"schemaVersion\":9")
      (expect output :to-contain "\"streaming\":true")
      (expect output :to-contain "\"fields\"")
      (expect output :to-contain "\"name\":\"payload\"")
      (expect output :to-contain "\"description\":\"custom payload\"")
      (expect output :to-contain "\"qualityGates\"")
      (expect output :to-contain "\"name\":\"custom-gate\"")
      (expect output :to-contain "\"kind\":\"custom-kind\"")
      (expect output :to-contain "\"command\":[\"custom\",\"check\"]")
      (expect output :to-contain "\"timeoutSeconds\":42")
      (expect output :to-contain "\"custom-artifact.json\"")
      (expect output :to-contain "\"capabilityMatrix\"")
      (expect output :to-contain "\"status\":\"implemented\"")
      (expect output :to-contain "\"summary\":\"custom capability summary\"")
      (expect output :to-contain "\"publicApis\":[\"custom-api\"]")
      (expect output :to-contain "\"documentation\":[\"CUSTOM.md\"]")
      (expect output :to-contain "\"--custom\"")
      (expect output :to-contain "\"--customAlias\"")
      (expect output :to-contain "\"valueKind\":\"custom-value\"")
      (expect output :to-contain "\"choices\":[\"custom-choice\"]")
      (expect output :to-contain "\"commandChoices\"")
      (expect output :to-contain "\"command\":\"custom-command\"")
      (expect output :to-contain "\"CUSTOM_ENV\"")
      (expect output :to-contain "\"custom option\"")
      (expect output :to-contain "\"custom.alias\"")
      (expect output :to-contain "\"custom-package\"")
      (expect output :to-contain "\"custom-matcher\"")
      (expect output :to-contain "\"distributionChannels\"")
      (expect output :to-contain "\"name\":\"custom-distribution\"")
      (expect output :to-contain "\"installCommand\":[\"custom\",\"install\"]")
      (expect output :to-contain "\"runCommand\":[\"custom\",\"run\"]")
      (expect output :to-contain "\"governance\"")
      (expect output :to-contain "\"reviewOwnership\":\".github\\/CODEOWNERS\"")
      (expect output :to-contain "\"custom maintainer responsibility\"")
      (expect output :to-contain "\"custom release authority\"")
      (expect output :to-contain "\"runtimeSupport\"")
      (expect output :to-contain "\"releaseProcess\"")
      (expect output :to-contain "\"continuousIntegration\"")
      (expect output :to-contain "\"workflowPath\":\".github\\/workflows\\/ci.yml\"")
      (expect output :to-contain "\"cacheModes\":[\"pull-only\"]")
      (expect output :to-contain "\"primaryImplementation\":\"SBCL\"")
      (expect output :to-contain "\"releaseStage\":\"pre-1.0\"")
      (expect output :not :to-contain "\"cl-weave-metadata\"")
      (expect output :not :to-contain "\"cl-weave\"")
      (expect output :not :to-contain "\"--testNamePattern\"")
      (expect output :not :to-contain "\"describe-it-dsl\"")))

  (it "advertises CI workflow operations as structured metadata"
    (let* ((metadata (cl-weave/cli::framework-metadata))
           (ci (getf metadata :continuous-integration)))
      (expect (getf metadata :schema-version) :to-be 22)
      (expect ci :not :to-be nil)
      (expect (getf ci :policy-document) :to-equal "docs/release-process.md")
      (expect (getf ci :provider) :to-equal "github-actions")
      (expect (getf ci :workflow-path) :to-equal ".github/workflows/ci.yml")
      (expect (getf ci :job-name) :to-equal "nix")
      (expect (getf ci :triggers)
              :to-equal '("pull_request" "push:main" "workflow_dispatch"))
      (expect (getf ci :systems)
              :to-equal '("x86_64-linux" "aarch64-darwin"))
      (expect (getf ci :artifact-bundle)
              :to-equal "cl-weave-test-reports-${{ matrix.system }}")
      (expect (getf ci :cache-provider) :to-equal "cachix")
      (expect (getf ci :cache-modes)
              :to-equal '("pull-only" "push-enabled"))
      (expect (getf ci :quality-gate-source) :to-equal "qualityGates")))

  (it "advertises CI quality gates as structured metadata"
    (let* ((metadata (cl-weave/cli::framework-metadata))
           (gates (getf metadata :quality-gates))
           (flake-gate (find "flake-check" gates
                             :key (lambda (entry) (getf entry :name))
                             :test #'string=))
           (metadata-gate (find "ai-metadata-artifact" gates
                                :key (lambda (entry) (getf entry :name))
                                :test #'string=))
           (jsonl-gate (find "jsonl-events-artifact" gates
                             :key (lambda (entry) (getf entry :name))
                             :test #'string=))
           (coverage-gate (find "coverage-artifact" gates
                                :key (lambda (entry) (getf entry :name))
                                :test #'string=))
           (watch-once-gate (find "watch-once-artifact" gates
                                  :key (lambda (entry) (getf entry :name))
                                  :test #'string=))
           (junit-gate (find "junit-artifact" gates
                             :key (lambda (entry) (getf entry :name))
                             :test #'string=)))
      (expect (getf metadata :schema-version) :to-be 22)
      (expect flake-gate :not :to-be nil)
      (expect (getf flake-gate :kind) :to-equal "nix")
      (expect (getf flake-gate :command)
              :to-equal '("nix" "flake" "check" "--print-build-logs"))
      (expect (getf flake-gate :timeout-seconds) :to-be 600)
      (expect (getf flake-gate :artifacts) :to-equal '())
      (expect metadata-gate :not :to-be nil)
      (expect (getf metadata-gate :command) :to-contain "metadata")
      (expect (getf metadata-gate :artifacts)
              :to-contain "cl-weave-metadata.json")
      (expect jsonl-gate :not :to-be nil)
      (expect (getf jsonl-gate :command)
              :to-contain "CL_WEAVE_OUTPUT_FILE=cl-weave-events.jsonl")
      (expect (getf jsonl-gate :artifacts)
              :to-contain "cl-weave-events.jsonl")
      (expect coverage-gate :not :to-be nil)
      (expect (getf coverage-gate :command)
              :to-contain "CL_WEAVE_COVERAGE=1")
      (expect (getf coverage-gate :command)
              :to-contain "CL_WEAVE_COVERAGE_FILE=cl-weave.coverage")
      (expect (getf coverage-gate :command)
              :to-contain
              "CL_WEAVE_COVERAGE_REPORT_DIR=cl-weave-coverage-report/")
      (expect (getf coverage-gate :artifacts)
              :to-contain "cl-weave.coverage")
      (expect (getf coverage-gate :artifacts)
              :to-contain "cl-weave-coverage-report/")
      (expect watch-once-gate :not :to-be nil)
      (expect (getf watch-once-gate :command)
              :to-equal '("nix" "run" "." "--" "watch" "cl-weave-tests"
                          "--once" "--reporter" "json" "--filter"
                          "filtering > runs only tests matching a path substring"
                          "--output" "cl-weave-watch-once.json"))
      (expect (getf watch-once-gate :timeout-seconds) :to-be 120)
      (expect (getf watch-once-gate :artifacts)
              :to-equal '("cl-weave-watch-once.json"))
      (expect junit-gate :not :to-be nil)
      (expect (getf junit-gate :command)
              :to-contain "CL_WEAVE_OUTPUT_FILE=cl-weave-junit.xml")
      (expect (getf junit-gate :artifacts)
              :to-contain "cl-weave-junit.xml")))

  (it "keeps CI workflow contract synchronized with metadata"
    (let* ((metadata (cl-weave/cli::framework-metadata))
           (ci (getf metadata :continuous-integration))
           (workflow (read-text-file #P".github/workflows/ci.yml")))
      (expect (probe-file (merge-pathnames (getf ci :workflow-path) (uiop:getcwd)))
              :not :to-be nil)
      (expect workflow :to-contain "pull_request:")
      (expect workflow :to-contain "branches: [main]")
      (expect workflow :to-contain "workflow_dispatch:")
      (dolist (system (getf ci :systems))
        (expect workflow :to-contain system))
      (expect workflow :to-contain
              (format nil "name: ~A" (getf ci :artifact-bundle)))
      (expect workflow :to-contain "uses: cachix/cachix-action@v17")
      (dolist (mode (getf ci :cache-modes))
        (expect workflow :to-contain mode))
      (expect (getf ci :quality-gate-source) :to-equal "qualityGates")
      (expect (getf metadata :quality-gates) :to-satisfy #'consp)))

  (it "keeps CI workflow quality gates synchronized with metadata"
    (let* ((metadata (cl-weave/cli::framework-metadata))
           (gates (getf metadata :quality-gates))
           (workflow (read-text-file #P".github/workflows/ci.yml"))
           (artifact-section (workflow-artifact-section workflow)))
      (dolist (gate gates)
        (expect (workflow-covers-quality-gate-p workflow gate) :to-be-truthy)
        (expect (workflow-timeout-minutes-for-command
                 workflow
                 (getf gate :command))
                :to-satisfy
                (lambda (timeout-minutes)
                  (and (integerp timeout-minutes)
                       (>= timeout-minutes
                           (minimum-workflow-timeout-minutes
                            (getf gate :timeout-seconds))))))
        (dolist (artifact (getf gate :artifacts))
          (expect artifact-section :to-contain artifact)))))

  (it "keeps flake checks synchronized with metadata quality gates"
    (let* ((metadata (cl-weave/cli::framework-metadata))
           (gate-names (sort (remove "flake-check"
                                     (mapcar (lambda (entry) (getf entry :name))
                                             (getf metadata :quality-gates))
                                     :test #'string=)
                             #'string<))
           (check-names (sort (remove "test"
                                      (flake-check-names
                                       (read-text-file #P"flake.nix"))
                                      :test #'string=)
                              #'string<)))
      (expect gate-names :to-equal check-names)))

  (it "keeps distribution channel metadata synchronized with README and flake packaging"
    (let* ((metadata (cl-weave/cli::framework-metadata))
           (channels (getf metadata :distribution-channels))
           (readme (read-text-file #P"README.md"))
           (flake (read-text-file #P"flake.nix"))
           (source-channel (find "source-self-test" channels
                                 :key (lambda (entry) (getf entry :name))
                                 :test #'string=))
           (local-channel (find "nix-local-cli" channels
                                :key (lambda (entry) (getf entry :name))
                                :test #'string=))
           (remote-channel (find "nix-remote-cli" channels
                                 :key (lambda (entry) (getf entry :name))
                                 :test #'string=))
           (homepage (getf metadata :homepage))
           (github-prefix "https://github.com/")
           (remote-ref (concatenate 'string
                                    "github:"
                                    (subseq homepage (length github-prefix)))))
      (dolist (channel channels)
        (dolist (reference (getf channel :references))
          (expect (probe-file (merge-pathnames reference (uiop:getcwd)))
                  :not :to-be nil))
        (unless (null (getf channel :install-command))
          (expect (markdown-contains-command-p readme
                                               (getf channel :install-command))
                  :to-be t))
        (expect (markdown-contains-command-p readme
                                             (getf channel :run-command))
                :to-be t))
      (expect source-channel :not :to-be nil)
      (expect (probe-file #P"scripts/run-tests.lisp") :not :to-be nil)
      (expect local-channel :not :to-be nil)
      (expect flake :to-contain "packages = forAllSystems")
      (expect flake :to-contain "apps = forAllSystems")
      (expect flake :to-contain "meta.mainProgram = \"cl-weave\";")
      (expect flake :to-contain "program = \"${package}/bin/cl-weave\";")
      (expect remote-channel :not :to-be nil)
      (expect homepage :to-satisfy
              (lambda (value)
                (and (stringp value)
                     (string= github-prefix
                              (subseq value 0
                                      (min (length value)
                                           (length github-prefix)))))))
      (expect (getf remote-channel :install-command) :to-contain remote-ref)
      (expect (getf remote-channel :run-command) :to-contain remote-ref)))

  (it "keeps the distribution policy synchronized with distribution metadata"
    (let* ((metadata (cl-weave/cli::framework-metadata))
           (channels (getf metadata :distribution-channels))
           (readme (normalize-markdown-text
                    (read-text-file
                     (merge-pathnames #P"README.md"
                                      (uiop:getcwd)))))
           (distribution-document-raw
             (read-text-file
              (merge-pathnames #P"docs/distribution-policy.md"
                               (uiop:getcwd))))
           (distribution-document (normalize-markdown-text
                                   distribution-document-raw))
           (ai-contract (normalize-markdown-text
                         (read-text-file
                          (merge-pathnames #P"docs/ai-contract.md"
                                           (uiop:getcwd))))))
      (expect (getf metadata :policy-documents)
              :to-contain "docs/distribution-policy.md")
      (expect readme :to-contain "docs/distribution-policy.md")
      (expect distribution-document :to-contain "# Distribution Policy")
      (expect distribution-document :to-contain "distributionChannels")
      (expect distribution-document :to-contain "README.md")
      (expect distribution-document :to-contain "docs/ai-contract.md")
      (expect distribution-document :to-contain "flake.nix")
      (expect distribution-document :to-contain "SBOMs")
      (expect distribution-document :to-contain "provenance attestations")
      (dolist (channel channels)
        (expect distribution-document :to-contain (getf channel :name))
        (dolist (reference (getf channel :references))
          (unless (string= reference "docs/distribution-policy.md")
            (expect distribution-document :to-contain reference)))
        (unless (null (getf channel :install-command))
          (expect (markdown-contains-command-p distribution-document-raw
                                               (getf channel :install-command))
                  :to-be t))
        (expect (markdown-contains-command-p distribution-document-raw
                                             (getf channel :run-command))
                :to-be t))
      (expect ai-contract :to-contain "docs/distribution-policy.md")))

  (it "keeps the packaged CLI wrapper safe for parallel ASDF loads"
    (expect (packaged-cli-initializes-output-translations-p
             (read-text-file #P"flake.nix"))
            :to-be t))

  (it "advertises parsed CLI options as structured metadata"
    (let* ((metadata (cl-weave/cli::framework-metadata))
           (options (getf metadata :options))
           (filter-option (find "--filter" options
                                :key (lambda (entry) (getf entry :name))
                                :test #'string=))
           (reporter-option (find "--reporter" options
                                  :key (lambda (entry) (getf entry :name))
                                  :test #'string=))
           (reporter-command-choices
             (getf reporter-option :command-choices))
           (sequence-option (find "--sequence" options
                                  :key (lambda (entry) (getf entry :name))
                                  :test #'string=))
           (max-workers-option (find "--max-workers" options
                                     :key (lambda (entry) (getf entry :name))
                                     :test #'string=))
           (snapshot-option (find "--update-snapshots" options
                                  :key (lambda (entry) (getf entry :name))
                                  :test #'string=)))
      (expect filter-option :not :to-be nil)
      (expect (getf filter-option :aliases) :to-equal '())
      (expect (getf filter-option :commands) :to-contain "run")
      (expect (getf filter-option :value-kind) :to-be :test-name-pattern)
      (expect (getf filter-option :choices) :to-equal '())
      (expect (getf filter-option :environment) :to-contain "CL_WEAVE_TEST_FILTER")
      (expect reporter-option :not :to-be nil)
      (expect (getf reporter-option :choices) :to-contain "json")
      (expect (getf reporter-option :choices) :to-contain "junit")
      (expect (assoc "run" reporter-command-choices :test #'string=)
              :to-equal
              '("run" ("spec" "sexp" "json" "jsonl" "tap" "github" "junit")))
      (expect (assoc "watch" reporter-command-choices :test #'string=)
              :to-equal
              '("watch" ("spec" "sexp" "json" "jsonl" "tap" "github" "junit")))
      (expect (assoc "list" reporter-command-choices :test #'string=)
              :to-equal
              '("list" ("spec" "sexp" "json" "jsonl")))
      (expect (assoc "doctor" reporter-command-choices :test #'string=)
              :to-equal '("doctor" ("json" "sexp")))
      (expect (assoc "metadata" reporter-command-choices :test #'string=)
              :to-equal '("metadata" ("json" "sexp")))
      (expect (second (assoc "doctor" reporter-command-choices :test #'string=))
              :not :to-contain "jsonl")
      (expect (second (assoc "metadata" reporter-command-choices :test #'string=))
              :not :to-contain "jsonl")
      (expect (second (assoc "list" reporter-command-choices :test #'string=))
              :not :to-contain "tap")
      (expect sequence-option :not :to-be nil)
      (expect (getf sequence-option :choices)
              :to-equal '("defined" "random" "shuffle"))
      (expect max-workers-option :not :to-be nil)
      (expect (getf max-workers-option :aliases) :to-equal '())
      (expect (getf max-workers-option :commands) :to-contain "run")
      (expect (getf max-workers-option :commands) :to-contain "watch")
      (expect (getf max-workers-option :commands) :not :to-contain "list")
      (expect (getf max-workers-option :value-kind) :to-be :positive-integer)
      (expect (getf max-workers-option :environment)
              :to-contain "CL_WEAVE_MAX_WORKERS")
      (expect snapshot-option :not :to-be nil)
      (expect (getf snapshot-option :aliases) :to-equal '())
      (expect (getf snapshot-option :value-kind) :to-be :boolean)
      (expect (getf snapshot-option :environment)
              :to-contain "CL_WEAVE_UPDATE_SNAPSHOTS")))

  (it "advertises property test environment controls as metadata"
    (let ((environment (getf (cl-weave/cli::framework-metadata) :environment)))
      (expect environment :to-contain "CL_WEAVE_PROPERTY_TESTS")
      (expect environment :to-contain "CL_WEAVE_PROPERTY_SEED")))

  (it "advertises watch once controls as metadata"
    (let* ((metadata (cl-weave/cli::framework-metadata))
           (environment (getf metadata :environment))
         (options (getf metadata :options))
           (watch-once-option (find "--once" options
                                    :key (lambda (entry) (getf entry :name))
                                    :test #'string=)))
      (expect environment :to-contain "CL_WEAVE_WATCH_ONCE")
      (expect watch-once-option :not :to-be nil)
      (expect (getf watch-once-option :commands) :to-equal '("watch"))
      (expect (getf watch-once-option :value-kind) :to-be :boolean)
      (expect (getf watch-once-option :environment)
              :to-equal '("CL_WEAVE_WATCH_ONCE"))))

  (it "advertises reporter artifact schemas as structured metadata"
    (let* ((metadata (cl-weave/cli::framework-metadata))
           (schemas (getf metadata :artifact-schemas))
           (results-schema (find "test-results" schemas
                                 :key (lambda (entry) (getf entry :kind))
                                 :test #'string=))
           (event-schema (find "test-event" schemas
                               :key (lambda (entry) (getf entry :kind))
                               :test #'string=))
            (plan-schema (find "test-plan" schemas
                               :key (lambda (entry) (getf entry :kind))
                               :test #'string=))
            (plan-entry-schema (find "test-plan-entry" schemas
                                      :key (lambda (entry) (getf entry :kind))
                                      :test #'string=))
            (mutations-schema (find "mutations" schemas
                                    :key (lambda (entry) (getf entry :kind))
                                    :test #'string=))
           (field-name (lambda (entry) (getf entry :name))))
      (expect (getf metadata :schema-version) :to-be 22)
      (expect results-schema :not :to-be nil)
      (expect (getf results-schema :commands) :to-equal '("run" "watch"))
      (expect (getf results-schema :reporters) :to-equal '("json" "sexp"))
      (expect (getf results-schema :schema-version) :to-be 5)
      (expect (getf results-schema :streaming) :to-be nil)
      (expect (find "events" (getf results-schema :fields)
                    :key field-name :test #'string=)
              :not :to-be nil)
      (expect event-schema :not :to-be nil)
      (expect (getf event-schema :reporters) :to-equal '("jsonl"))
      (expect (getf event-schema :schema-version) :to-be 2)
      (expect (getf event-schema :streaming) :to-be t)
      (expect (find "event" (getf event-schema :fields)
                    :key field-name :test #'string=)
              :not :to-be nil)
      (expect (getf event-schema :commands) :to-equal '("run" "watch"))
      (expect plan-schema :not :to-be nil)
      (expect (getf plan-schema :commands) :to-equal '("list"))
      (expect (getf plan-schema :schema-version) :to-be 3)
      (expect plan-entry-schema :not :to-be nil)
      (expect (getf plan-entry-schema :schema-version) :to-be 2)
      (expect (mapcar field-name (getf plan-entry-schema :fields))
              :to-contain "test.tags")
      (expect (mapcar field-name (getf plan-entry-schema :fields))
              :to-contain "test.dependsOn")
      (expect mutations-schema :not :to-be nil)
      (expect (getf mutations-schema :commands) :to-equal '())
      (expect (getf mutations-schema :reporters) :to-equal '("json" "sexp"))
      (expect (getf mutations-schema :streaming) :to-be nil)
      (expect (mapcar field-name (getf mutations-schema :fields))
              :to-equal '("schemaVersion" "kind" "total" "killed"
                          "survived" "errored" "score" "results"))
      (let ((doctor-schema (find "doctor-report" schemas
                                 :key (lambda (entry) (getf entry :kind))
                                 :test #'string=)))
        (expect doctor-schema :not :to-be nil)
        (expect (getf doctor-schema :commands) :to-equal '("doctor"))
        (expect (getf doctor-schema :reporters) :to-equal '("json" "sexp"))
        (expect (getf doctor-schema :schema-version) :to-be 1)
        (expect (getf doctor-schema :streaming) :to-be nil)
        (expect (mapcar field-name (getf doctor-schema :fields))
                :to-equal '("schemaVersion" "kind" "status" "version"
                            "runtime" "checks")))))

  (it "keeps README adoption and CI contracts synchronized with metadata"
    (let* ((readme (read-text-file (merge-pathnames #P"README.md"
                                                    (uiop:getcwd))))
           (normalized-readme (normalize-shell-text readme))
           (metadata (cl-weave/cli::framework-metadata))
           (gates (getf metadata :quality-gates)))
      (expect readme :to-contain "## Adoption")
      (expect readme :to-contain "### AI Discovery")
      (expect readme :to-contain "## CI")
      (dolist (gate gates)
        (expect normalized-readme
                :to-contain
                (normalize-shell-text
                 (workflow-command-string (getf gate :command))))
        (dolist (artifact (getf gate :artifacts))
          (expect readme :to-contain artifact)))))

  (it "keeps mutation artifact schema aligned with mutation reporters"
    (let* ((schema (find "mutations"
                         (cl-weave:reporter-artifact-schemas)
                         :key (lambda (entry) (getf entry :kind))
                         :test #'string=))
           (field-names (mapcar (lambda (entry) (getf entry :name))
                                (getf schema :fields)))
           (results (run-mutations '(+ 1 1)
                                   (lambda (form mutation)
                                     (declare (ignore mutation))
                                     (= (eval form) 2))))
           (json-output (with-output-to-string (stream)
                          (report-mutations-json results stream))))
      (expect schema :not :to-be nil)
      (expect field-names
              :to-equal '("schemaVersion" "kind" "total" "killed"
                          "survived" "errored" "score" "results"))
      (dolist (field field-names)
        (expect json-output :to-contain (format nil "\"~A\"" field)))
      (expect json-output :not :to-contain "\"operators\"")
      (expect json-output :not :to-contain "\"summary\"")))

  (it "derives artifact schema metadata from reporter contracts"
    (expect (cl-weave:reporter-artifact-schemas)
            :to-be cl-weave::*reporter-artifact-schemas*)
    (expect (getf (cl-weave/cli::framework-metadata) :artifact-schemas)
            :to-be (cl-weave:reporter-artifact-schemas)))

  (it "exposes framework metadata through the public Lisp API"
    (let ((public-metadata (cl-weave:framework-metadata))
          (cli-metadata (cl-weave/cli::framework-metadata)))
      (expect public-metadata :to-equal cli-metadata)
      (expect (getf public-metadata :artifact-schemas)
              :to-equal (cl-weave:reporter-artifact-schemas))
      (expect (getf public-metadata :citation)
              :to-equal (getf cli-metadata :citation))))

  (it "keeps artifact schemas aligned with command reporter contracts"
    (labels ((reporter-choices-for (command metadata)
               (cond
                 ((string= command "run")
                 (getf metadata :reporters))
                 ((string= command "watch")
                  (getf metadata :reporters))
                 ((string= command "list")
                  (getf metadata :list-reporters))
                 ((string= command "doctor")
                  '("json" "sexp"))
                 (t '())))
             (expect-schema-reporters-valid-for-command (schema metadata)
               (let ((commands (getf schema :commands)))
                 (when commands
                   (expect commands :to-satisfy #'listp)
                   (dolist (command commands)
                     (expect (member command (getf metadata :commands) :test #'string=)
                             :not :to-be nil)
                     (let ((choices (reporter-choices-for command metadata)))
                       (expect choices :to-satisfy #'consp)
                       (dolist (reporter (getf schema :reporters))
                         (expect (member reporter choices :test #'string=)
                                 :not :to-be nil))))))))
      (let ((metadata (cl-weave/cli::framework-metadata)))
        (dolist (schema (getf metadata :artifact-schemas))
          (expect-schema-reporters-valid-for-command schema metadata)
          (if (getf schema :streaming)
              (expect (getf schema :reporters) :to-equal '("jsonl"))
              (expect (getf schema :reporters) :not :to-contain "jsonl"))))))

  (it "keeps reporter metadata synchronized with implemented reporters"
    (flet ((reporter-name (reporter)
             (string-downcase (symbol-name reporter))))
      (let ((metadata (cl-weave/cli::framework-metadata)))
        (expect (getf metadata :reporters)
                :to-equal (mapcar #'reporter-name cl-weave::*run-reporters*))
        (expect (getf metadata :list-reporters)
                :to-equal (mapcar #'reporter-name cl-weave::*list-reporters*)))))

  (it "keeps Vitest aliases aligned with public package exports"
    (let* ((metadata (cl-weave/cli::framework-metadata))
           (exports (getf (find "cl-weave"
                                (getf metadata :package-exports)
                                :key (lambda (entry) (getf entry :name))
                                :test #'string=)
                          :exports)))
      (flet ((exportedp (name)
               (or (member name exports :test #'string=)
                   (member (string-upcase name) exports :test #'string=))))
        (dolist (entry (getf metadata :vitest-aliases))
          (expect (getf entry :canonical) :to-satisfy #'exportedp)))))

  (it "keeps package export metadata synchronized with actual packages"
    (flet ((actual-exports (package-name)
             (let ((exports '()))
               (do-external-symbols (symbol (find-package (string-upcase package-name)))
                 (push (symbol-name symbol) exports))
               (sort exports #'string<)))
           (metadata-exports (package-name metadata)
             (getf (find package-name
                         (getf metadata :package-exports)
                         :key (lambda (entry) (getf entry :name))
                         :test #'string=)
                   :exports)))
      (let ((metadata (cl-weave/cli::framework-metadata)))
        (let ((declared-core (metadata-exports "cl-weave" metadata))
              (actual-core (actual-exports "cl-weave"))
              (declared-cli (metadata-exports "cl-weave/cli" metadata))
              (actual-cli (actual-exports "cl-weave/cli")))
          (expect declared-core :to-equal actual-core)
          (expect declared-cli :to-equal actual-cli)))))

  (it "keeps framework metadata identifiers unique"
    (labels ((duplicate-strings (values)
               (let ((seen (make-hash-table :test #'equal))
                     (duplicates '()))
                 (dolist (value values)
                   (if (gethash value seen)
                       (pushnew value duplicates :test #'string=)
                       (setf (gethash value seen) t)))
                 (sort duplicates #'string<)))
             (expect-unique-strings (values)
               (expect (duplicate-strings values) :to-equal '()))
             (metadata-names (entries)
               (mapcar (lambda (entry)
                         (string-downcase (symbol-name (getf entry :name))))
                       entries)))
      (let ((metadata (cl-weave/cli::framework-metadata)))
        (dolist (key '(:commands :reporters :list-reporters
                       :capabilities :environment))
          (expect-unique-strings (getf metadata key)))
        (expect-unique-strings
         (mapcar (lambda (entry) (getf entry :name))
                 (getf metadata :capability-matrix)))
        (dolist (entry (getf metadata :capability-matrix))
          (expect (member (getf entry :name)
                          (getf metadata :capabilities)
                          :test #'string=)
                  :not :to-be nil)
          (expect (getf entry :status) :to-equal "implemented")
          (expect (getf entry :summary) :to-satisfy #'stringp)
          (expect (getf entry :public-apis) :to-satisfy #'consp)
          (expect-unique-strings (getf entry :public-apis))
          (expect (getf entry :quality-gates) :to-satisfy #'consp)
          (expect-unique-strings (getf entry :quality-gates))
          (dolist (gate-name (getf entry :quality-gates))
            (expect (find gate-name (getf metadata :quality-gates)
                          :key (lambda (gate) (getf gate :name))
                          :test #'string=)
                    :not :to-be nil))
          (expect (getf entry :documentation) :to-satisfy #'consp)
          (expect-unique-strings (getf entry :documentation))
          (dolist (document (getf entry :documentation))
            (expect (probe-file (merge-pathnames document (uiop:getcwd)))
                    :not :to-be nil)))
        (dolist (capability (getf metadata :capabilities))
          (expect (find capability
                        (getf metadata :capability-matrix)
                        :key (lambda (entry) (getf entry :name))
                        :test #'string=)
                  :not :to-be nil))
        (expect-unique-strings (getf metadata :policy-documents))
        (dolist (document (getf metadata :policy-documents))
          (expect (probe-file (merge-pathnames document (uiop:getcwd)))
                  :not :to-be nil))
        (expect-unique-strings
         (mapcar (lambda (entry)
                   (getf entry :name))
                 (getf metadata :reference-documents)))
        (expect-unique-strings
         (mapcar (lambda (entry) (getf entry :path))
                 (getf metadata :reference-documents)))
        (dolist (entry (getf metadata :reference-documents))
          (expect (getf entry :description) :to-satisfy #'stringp)
          (expect (probe-file (merge-pathnames (getf entry :path) (uiop:getcwd)))
                  :not :to-be nil))
        (expect-unique-strings
         (mapcar (lambda (entry) (getf entry :name))
                 (getf metadata :support-channels)))
        (dolist (entry (getf metadata :support-channels))
          (expect (getf entry :scope) :to-satisfy #'stringp)
          (when (string= (getf entry :kind) "document")
            (expect (probe-file (merge-pathnames (getf entry :target) (uiop:getcwd)))
                    :not :to-be nil)))
        (expect-unique-strings
         (mapcar (lambda (entry) (getf entry :name))
                 (getf metadata :community-health)))
        (dolist (entry (getf metadata :community-health))
          (expect (getf entry :kind) :to-satisfy #'stringp)
          (expect (getf entry :path) :to-satisfy #'stringp)
          (expect (probe-file (merge-pathnames (getf entry :path) (uiop:getcwd)))
                  :not :to-be nil)
          (expect (getf entry :references) :to-satisfy #'listp)
          (expect-unique-strings (getf entry :references))
          (dolist (reference (getf entry :references))
            (expect (probe-file (merge-pathnames reference (uiop:getcwd)))
                    :not :to-be nil))
          (expect (getf entry :required-sections) :to-satisfy #'listp)
          (expect-unique-strings (getf entry :required-sections))
          (expect (getf entry :contact-links) :to-satisfy #'listp)
          (expect-unique-strings
           (mapcar (lambda (link) (getf link :name))
                   (getf entry :contact-links)))
          (dolist (link (getf entry :contact-links))
            (expect (getf link :target) :to-satisfy #'stringp)
            (expect (getf link :purpose) :to-satisfy
                    (lambda (value) (or (null value) (stringp value))))))
        (expect-unique-strings
         (mapcar (lambda (entry) (getf entry :name))
                 (getf metadata :security-contacts)))
        (dolist (entry (getf metadata :security-contacts))
          (expect (getf entry :scope) :to-satisfy #'stringp)
          (when (string= (getf entry :kind) "document")
            (expect (probe-file (merge-pathnames (getf entry :target) (uiop:getcwd)))
                    :not :to-be nil)))
        (let ((lifecycle (getf metadata :lifecycle)))
          (dolist (key '(:support-document :versioning-document :security-document))
            (expect (probe-file (merge-pathnames (getf lifecycle key) (uiop:getcwd)))
                    :not :to-be nil)))
        (let ((runtime-support (getf metadata :runtime-support)))
          (expect (probe-file (merge-pathnames (getf runtime-support :policy-document)
                                               (uiop:getcwd)))
                  :not :to-be nil)
          (expect-unique-strings
           (mapcar (lambda (entry) (getf entry :implementation))
                   (getf runtime-support :supported-targets)))
          (expect-unique-strings
           (mapcar (lambda (entry) (getf entry :implementation))
                   (getf runtime-support :best-effort-targets)))
          (dolist (entry (append (getf runtime-support :supported-targets)
                                 (getf runtime-support :best-effort-targets)))
            (expect (getf entry :status) :to-satisfy #'stringp)
            (expect (getf entry :platforms) :to-satisfy #'listp)
            (expect-unique-strings (getf entry :platforms)))
          (expect-unique-strings
           (getf runtime-support :implementation-specific-features)))
        (let ((release-process (getf metadata :release-process)))
          (expect (probe-file (merge-pathnames (getf release-process :policy-document)
                                               (uiop:getcwd)))
                  :not :to-be nil)
          (expect-unique-strings (getf release-process :checklist))
          (expect-unique-strings
           (getf release-process :contract-sync-requirements)))
        (let ((ci (getf metadata :continuous-integration)))
          (expect (probe-file (merge-pathnames (getf ci :workflow-path)
                                               (uiop:getcwd)))
                  :not :to-be nil)
          (expect-unique-strings (getf ci :triggers))
          (expect-unique-strings (getf ci :systems))
          (expect-unique-strings (getf ci :cache-modes)))
        (expect-unique-strings
         (mapcar (lambda (entry) (getf entry :name))
                 (getf metadata :options)))
        (expect-unique-strings
         (loop for entry in (getf metadata :options)
               append (cons (getf entry :name)
                            (getf entry :aliases))))
        (dolist (entry (getf metadata :options))
          (expect (getf entry :value-kind) :not :to-be nil)
          (expect (member :choices entry) :not :to-be nil)
          (expect (getf entry :choices) :to-satisfy #'listp)
          (expect-unique-strings (getf entry :choices))
          (dolist (command-entry (getf entry :command-choices))
            (destructuring-bind (command choices) command-entry
              (expect (member command (getf entry :commands) :test #'string=)
                      :not :to-be nil)
              (expect-unique-strings choices)
              (dolist (choice choices)
                (expect (member choice (getf entry :choices) :test #'string=)
                        :not :to-be nil))))
          (dolist (command (getf entry :commands))
            (expect (member command (getf metadata :commands) :test #'string=)
                    :not :to-be nil))
          (dolist (variable (getf entry :environment))
            (expect (member variable (getf metadata :environment) :test #'string=)
                    :not :to-be nil)))
        (expect-unique-strings (mapcar (lambda (entry) (getf entry :alias))
                                       (getf metadata :vitest-aliases)))
        (expect-unique-strings (mapcar (lambda (entry) (getf entry :name))
                                       (getf metadata :package-exports)))
        (dolist (entry (getf metadata :package-exports))
          (expect-unique-strings (getf entry :exports)))
        (expect-unique-strings (metadata-names (getf metadata :matchers)))
        (dolist (matcher '("to-allocate-under" "to-have-slot"
                           "to-have-method-specialized-on"))
          (expect (member matcher (metadata-names (getf metadata :matchers))
                          :test #'string=)
                  :not :to-be nil))
        (expect (member "mop-architecture-assertions"
                        (getf metadata :capabilities)
                        :test #'string=)
                :not :to-be nil)
        (expect (member "artifact-schemas"
                        (getf metadata :capabilities)
                        :test #'string=)
                :not :to-be nil)
        (expect-unique-strings (metadata-names (getf metadata :mutation-operators)))
        (expect-unique-strings
         (mapcar (lambda (entry) (getf entry :kind))
                 (getf metadata :artifact-schemas)))
        (expect-unique-strings
         (mapcar (lambda (entry) (getf entry :name))
                 (getf metadata :quality-gates)))
        (dolist (entry (getf metadata :quality-gates))
          (expect (getf entry :name) :to-satisfy #'stringp)
          (expect (getf entry :kind) :to-satisfy #'stringp)
          (expect (getf entry :command) :to-satisfy #'consp)
          (expect (getf entry :timeout-seconds) :to-satisfy #'plusp)
          (expect (getf entry :artifacts) :to-satisfy #'listp)
          (expect (getf entry :description) :to-satisfy
                  (lambda (value) (or (null value) (stringp value))))
          (dolist (argument (getf entry :command))
            (expect argument :to-satisfy #'stringp))
          (dolist (artifact (getf entry :artifacts))
            (expect artifact :to-satisfy #'stringp)))
        (dolist (entry (getf metadata :artifact-schemas))
          (expect (getf entry :schema-version) :to-satisfy #'plusp)
          (expect (getf entry :streaming) :to-satisfy
                  (lambda (value) (member value '(nil t))))
          (expect (getf entry :commands) :to-satisfy #'listp)
          (expect-unique-strings (getf entry :commands))
          (dolist (command (getf entry :commands))
            (expect (member command
                            (getf metadata :commands)
                            :test #'string=)
                    :not :to-be nil))
          (dolist (reporter (getf entry :reporters))
            (expect (member reporter (getf metadata :reporters) :test #'string=)
                    :not :to-be nil))
          (expect (getf entry :fields) :to-satisfy #'consp)
          (expect-unique-strings
           (mapcar (lambda (field) (getf field :name))
                   (getf entry :fields)))
          (dolist (field (getf entry :fields))
            (expect (getf field :name) :to-satisfy #'stringp)
            (expect (getf field :kind) :to-satisfy #'stringp)
            (expect (getf field :required) :to-satisfy
                    (lambda (value) (member value '(nil t))))
            (expect (getf field :description) :to-satisfy
                    (lambda (value) (or (null value) (stringp value))))))
        (dolist (reporter (getf metadata :list-reporters))
          (expect (member reporter (getf metadata :reporters) :test #'string=)
                  :not :to-be nil)))))

  (it "advertises framework metadata in machine-readable capability APIs"
    (let ((capability-matrix
            (getf (cl-weave/cli::framework-metadata) :capability-matrix)))
      (dolist (capability-name '("structured-reporting"
                                 "artifact-schemas"
                                 "ai-discovery-metadata"
                                 "public-package-exports"))
        (let* ((entry (find capability-name
                            capability-matrix
                            :key (lambda (item) (getf item :name))
                            :test #'string=))
               (public-apis (getf entry :public-apis)))
          (expect entry :not :to-be nil)
          (expect public-apis :to-contain "framework-metadata")))))

  (it "keeps metadata canonical names in Common Lisp reader spelling"
    (dolist (entry (getf (cl-weave/cli::framework-metadata) :vitest-aliases))
      (let ((canonical (getf entry :canonical)))
        (expect (every (lambda (char)
                         (not (upper-case-p char)))
                       canonical)
                :to-be t))))

  (it "keeps environment specs aligned with environment-backed metadata"
    (dolist (entry cl-weave/cli::*metadata-cli-options*)
      (let ((name (getf entry :name))
            (environment (getf entry :environment)))
        (if environment
            (expect (cl-weave/cli::cli-environment-spec name)
                    :not :to-be nil)
            (expect (cl-weave/cli::cli-environment-spec name)
                    :to-be nil)))))

  (it "normalizes SBCL argument separators from nix run"
    (let ((options (cl-weave/cli::parse-cli-arguments
                    '("--" "run" "cl-weave-tests" "--filter" "cli")
                    (cl-weave/cli::make-cli-options))))
      (expect (cl-weave/cli::cli-options-command options) :to-be :run)
      (expect (cl-weave/cli::cli-options-systems options)
              :to-equal '("cl-weave-tests"))
      (expect (cl-weave/cli::cli-options-name-filter options) :to-equal "cli")))

  (it "prints Vitest-compatible version output without running tests"
    (let ((flag-options (cl-weave/cli::parse-cli-arguments
                         '("--version")
                         (cl-weave/cli::make-cli-options)))
          (command-options (cl-weave/cli::parse-cli-arguments
                            '("version")
                            (cl-weave/cli::make-cli-options)))
          (exit-code nil)
          (version (cl-weave/cli::cli-version)))
      (expect (cl-weave/cli::cli-options-version flag-options) :to-be t)
      (expect (cl-weave/cli::cli-options-version command-options) :to-be t)
      (expect version :not :to-equal "unknown")
      (with-mocked-functions
          (((symbol-function 'cl-weave/cli::exit-process)
            (lambda (code)
              (setf exit-code code))))
        (let ((output (with-output-to-string (*standard-output*)
                        (cl-weave/cli:main '("--version")))))
          (expect output :to-equal (format nil "cl-weave ~A~%" version))
          (expect exit-code :to-be 0)))))

  (it "prints help output without dispatching test execution"
    (let ((flag-options (cl-weave/cli::parse-cli-arguments
                         '("--help")
                         (cl-weave/cli::make-cli-options)))
          (command-options (cl-weave/cli::parse-cli-arguments
                            '("help")
                            (cl-weave/cli::make-cli-options)))
          (exit-code nil)
          (run-command-called nil))
      (expect (cl-weave/cli::cli-options-help flag-options) :to-be t)
      (expect (cl-weave/cli::cli-options-help command-options) :to-be t)
      (with-mocked-functions
          (((symbol-function 'cl-weave/cli::exit-process)
            (lambda (code)
              (setf exit-code code)))
           ((symbol-function 'cl-weave/cli::run-command)
            (lambda (options)
              (declare (ignore options))
              (setf run-command-called t)
              t)))
        (let ((output (with-output-to-string (*standard-output*)
                        (cl-weave/cli:main '("help")))))
          (expect output :to-contain "cl-weave run [SYSTEM] [options]")
          (expect output :to-contain "cl-weave metadata [SYSTEM] [options]")
          (expect exit-code :to-be 0)
          (expect run-command-called :to-be nil)))))

  (it "dispatches list mode through main with structured arguments"
    (let ((exit-code nil)
          (observed nil))
      (with-mocked-functions
          (((symbol-function 'cl-weave/cli::exit-process)
            (lambda (code)
              (setf exit-code code)))
           ((symbol-function 'cl-weave/cli::load-requested-inputs)
            (lambda (options)
              (declare (ignore options))
              nil))
           ((symbol-function 'cl-weave:list-tests)
            (lambda (&key reporter name-filter shard order seed retry timeout-ms stream)
              (declare (ignore stream))
              (setf observed
                    (list :reporter reporter
                          :name-filter name-filter
                          :shard shard
                          :order order
                          :seed seed
                          :retry retry
                          :timeout-ms timeout-ms))
              t)))
        (expect (with-output-to-string (*standard-output*)
                  (cl-weave/cli:main
                   '("list" "cl-weave-tests"
                     "--reporter" "json"
                     "--filter" "cli"
                     "--shard" "2/4"
                     "--sequence" "random"
                     "--seed" "42"
                     "--retry" "3"
                     "--test-timeout-ms" "2500")))
                :to-equal "")
        (expect exit-code :to-be 0)
        (expect observed
                :to-equal
                '(:reporter :json
                  :name-filter "cli"
                  :shard (2 4)
                  :order :random
                  :seed 42
                  :retry 3
                  :timeout-ms 2500)))))

  (it "dispatches watch mode through main with system-scoped arguments"
    (let ((exit-code nil)
          (observed-system nil)
          (observed-arguments nil))
      (with-mocked-functions
          (((symbol-function 'cl-weave/cli::exit-process)
            (lambda (code)
              (setf exit-code code)))
           ((symbol-function 'cl-weave/cli::load-requested-inputs)
            (lambda (options)
              (declare (ignore options))
              nil))
           ((symbol-function 'cl-weave:watch-system)
            (lambda (system &rest arguments)
              (setf observed-system system
                    observed-arguments arguments)
              t)))
        (expect (with-output-to-string (*standard-output*)
                  (cl-weave/cli:main
                   '("watch" "cl-weave-tests"
                     "--reporter" "jsonl"
                     "--filter" "watch"
                     "--coverage"
                     "--coverage-output" "watch.coverage"
                     "--pass-with-no-tests"
                     "--once"
                     "--watch-interval" "1.5"
                     "--max-workers" "4")))
                :to-equal "")
        (expect exit-code :to-be 0)
        (expect observed-system :to-equal "cl-weave-tests")
        (expect (getf observed-arguments :reporter) :to-be :jsonl)
        (expect (getf observed-arguments :name-filter) :to-equal "watch")
        (expect (getf observed-arguments :shard) :to-be nil)
        (expect (getf observed-arguments :order) :to-be :defined)
        (expect (getf observed-arguments :seed) :to-be nil)
        (expect (getf observed-arguments :bail) :to-be nil)
        (expect (getf observed-arguments :coverage) :to-be t)
        (expect (getf observed-arguments :coverage-output)
                :to-equal "watch.coverage")
        (expect (getf observed-arguments :pass-with-no-tests) :to-be t)
        (expect (getf observed-arguments :retry) :to-be 0)
        (expect (getf observed-arguments :timeout-ms) :to-be nil)
        (expect (getf observed-arguments :max-workers) :to-be 4)
        (expect (getf observed-arguments :include-dependencies) :to-be t)
        (expect (getf observed-arguments :once) :to-be t)
        (expect (getf observed-arguments :interval) :to-equal 1.5)
        (expect (getf observed-arguments :stream) :to-be-truthy)
        (expect (getf observed-arguments :status-stream) :to-be-truthy))))

  (it "writes watch artifacts to --output while keeping watch status on stderr"
    (let* ((output-file (test-temporary-pathname "cl-weave-watch-once.json"))
           (stdout "")
           (stderr "")
           (exit-code nil))
      (when (probe-file output-file)
        (delete-file output-file))
      (unwind-protect
           (progn
             (with-mocked-functions
                 (((symbol-function 'cl-weave/cli::exit-process)
                   (lambda (code)
                     (setf exit-code code)))
                  ((symbol-function 'cl-weave/cli::load-requested-inputs)
                   (lambda (options)
                     (declare (ignore options))
                     nil))
                  ((symbol-function 'cl-weave:watch-system)
                   (lambda (system &key reporter stream status-stream name-filter
                                         shard order seed bail coverage
                                         coverage-output pass-with-no-tests retry
                                         timeout-ms max-workers include-dependencies
                                         once interval)
                     (declare (ignore system shard order seed bail coverage
                                      coverage-output pass-with-no-tests retry
                                      timeout-ms max-workers include-dependencies
                                      interval))
                     (expect reporter :to-be :json)
                     (expect name-filter :to-equal "watch")
                     (expect once :to-be t)
                     (write-string "; cl-weave watch: FULL-SUITE" status-stream)
                     (cl-weave::report-json nil stream)
                     t)))
               (setf stdout
                     (with-output-to-string (*standard-output*)
                       (setf stderr
                             (with-output-to-string (*error-output*)
                               (cl-weave/cli:main
                                (list "watch"
                                      "cl-weave-tests"
                                      "--once"
                                      "--reporter" "json"
                                      "--filter" "watch"
                                      "--output" (namestring output-file))))))))
             (expect exit-code :to-be 0)
             (expect stdout :to-equal "")
             (expect stderr :to-contain "cl-weave watch: FULL-SUITE")
             (expect stderr :not :to-contain "\"schemaVersion\":5")
             (let ((output (read-text-file output-file)))
               (expect output :to-contain "\"schemaVersion\":5")
               (expect output :to-contain "\"kind\":\"test-results\"")
               (expect output :not :to-contain "cl-weave watch"))))
        (when (probe-file output-file)
          (delete-file output-file)))))

  (it "returns CLI error status for watch mode without a target system"
    (let ((exit-code nil)
          (stderr ""))
      (with-mocked-functions
          (((symbol-function 'cl-weave/cli::exit-process)
            (lambda (code)
              (setf exit-code code))))
        (setf stderr
              (with-output-to-string (*error-output*)
                (cl-weave/cli:main '("watch")))))
      (expect exit-code :to-be 2)
      (expect stderr :to-contain
              "Watch mode requires SYSTEM as a positional argument or --system SYSTEM.")
      (expect stderr :to-contain "cl-weave watch [SYSTEM] [options]")))

  (it "returns CLI error status for watch mode with multiple target systems"
    (let ((exit-code nil)
          (stderr "")
          (watch-called-p nil))
      (with-mocked-functions
          (((symbol-function 'cl-weave/cli::exit-process)
            (lambda (code)
              (setf exit-code code)))
           ((symbol-function 'cl-weave/cli::load-requested-inputs)
            (lambda (options)
              (declare (ignore options))
              nil))
           ((symbol-function 'cl-weave:watch-system)
            (lambda (&rest arguments)
              (declare (ignore arguments))
              (setf watch-called-p t)
              t)))
        (setf stderr
              (with-output-to-string (*error-output*)
                (cl-weave/cli:main
                 '("watch" "--system" "cl-weave-tests" "--system" "sample-system")))))
      (expect exit-code :to-be 2)
      (expect watch-called-p :to-be nil)
      (expect stderr :to-contain
              "Watch mode accepts exactly one SYSTEM target.")
      (expect stderr :to-contain "cl-weave watch [SYSTEM] [options]")))

  (it "rejects CI-incompatible list reporters early"
    (dolist (reporter '("github" "junit"))
      (let ((options (cl-weave/cli::parse-cli-arguments
                      (list "list" "cl-weave-tests" "--reporter" reporter)
                      (cl-weave/cli::make-cli-options))))
        (expect (lambda ()
                  (cl-weave/cli::ensure-valid-reporter-for-command options))
                :to-throw))))

  (it "rejects unsupported run and watch reporters at the CLI boundary"
    (dolist (command '(:run :watch))
      (let ((options (cl-weave/cli::make-cli-options
                      :command command
                      :reporter :unknown
                      :systems '("cl-weave-tests")
                      :watch (eq command :watch))))
        (expect (lambda ()
                  (cl-weave/cli::ensure-valid-reporter-for-command options))
                :to-throw
                "cl-weave: run mode supports spec, sexp, json, jsonl, tap, github, and junit reporters."))))

  (it "bootstraps local ASDF definitions before loading requested systems"
    (let* ((cwd #P"/tmp/cl-weave-bootstrap/")
           (asd-file #P"/tmp/cl-weave-bootstrap/example.asd")
           (options (cl-weave/cli::make-cli-options :systems '("example")))
           (bootstrapped nil)
           (loaded-asds '())
           (loaded-systems '()))
      (with-mocked-functions
          (((symbol-function 'uiop:getcwd)
            (lambda () cwd))
           ((symbol-function 'cl-weave/cli::directory-asd-files)
            (lambda (directory)
              (declare (ignore directory))
              (list asd-file)))
           ((symbol-function 'load)
            (lambda (pathname)
              (push pathname loaded-asds)
              (setf bootstrapped t)))
           ((symbol-function 'asdf:find-system)
            (lambda (system &optional errorp)
              (declare (ignore errorp))
              (and bootstrapped (string= system "example") :example)))
           ((symbol-function 'asdf:load-system)
            (lambda (system)
              (push system loaded-systems)
              :loaded)))
        (expect (cl-weave/cli::load-requested-inputs options) :to-be nil)
        (expect loaded-asds :to-equal (list asd-file))
        (expect loaded-systems :to-equal '("example")))))

  (it "loads local project systems directly instead of routing them through ASDF"
    (let* ((options (cl-weave/cli::make-cli-options
                     :systems '("cl-weave-tests")))
           (loaded-local-systems '())
           (loaded-asdf-systems '()))
      (with-mocked-functions
          (((symbol-function 'cl-weave::load-local-system)
            (lambda (system &optional loaded-systems)
              (declare (ignore loaded-systems))
              (push system loaded-local-systems)
              :loaded-local))
           ((symbol-function 'asdf:find-system)
            (lambda (&rest args)
              (declare (ignore args))
              (error "asdf:find-system should not be called for local systems")))
           ((symbol-function 'asdf:load-system)
            (lambda (system)
              (push system loaded-asdf-systems)
              :loaded-asdf)))
        (expect (cl-weave/cli::load-requested-inputs options) :to-be nil)
        (expect loaded-local-systems :to-equal '("cl-weave-tests"))
        (expect loaded-asdf-systems :to-equal '()))))

  (it "reports actionable CLI errors when requested systems remain unavailable"
    (let* ((cwd #P"/tmp/cl-weave-missing/")
           (helper-file #P"/tmp/cl-weave-missing/support/helper.lisp")
           (helper-directory
             (uiop:pathname-directory-pathname helper-file))
           (options (cl-weave/cli::make-cli-options
                     :systems '("missing-system")
                     :load-files (list helper-file)))
           (searched-directories '())
           (message nil))
      (with-mocked-functions
          (((symbol-function 'uiop:getcwd)
            (lambda () cwd))
           ((symbol-function 'cl-weave/cli::system-bootstrap-directories)
            (lambda (ignored-options)
              (declare (ignore ignored-options))
              (list cwd helper-directory)))
           ((symbol-function 'cl-weave/cli::directory-asd-files)
            (lambda (directory)
              (push (pathname-directory directory) searched-directories)
              '()))
           ((symbol-function 'asdf:find-system)
            (lambda (system &optional errorp)
              (declare (ignore system errorp))
              nil)))
        (handler-case
            (cl-weave/cli::load-requested-inputs options)
          (cl-weave/cli::cli-error (condition)
            (setf message (princ-to-string condition))))
        (expect message :to-contain "Unable to locate ASDF system \"missing-system\"")
        (expect message :to-contain "CL_SOURCE_REGISTRY")
        (expect searched-directories
                :to-equal
                (list (pathname-directory helper-directory)
                      (pathname-directory cwd))))))

  (it "normalizes metadata reporter spec to JSON output"
    (let* ((options (cl-weave/cli::parse-cli-arguments
                     '("metadata" "cl-weave-tests" "--reporter" "spec")
                     (cl-weave/cli::make-cli-options)))
           (output (with-output-to-string (stream)
                     (cl-weave/cli::report-framework-metadata options stream))))
      (expect (cl-weave/cli::metadata-reporter options) :to-be :json)
      (expect output :to-contain "\"schemaVersion\":22")
      (expect output :to-contain "\"kind\":\"cl-weave-metadata\"")))

  (it "normalizes spec metadata reporter before writing output"
    (let* ((output-file (test-temporary-pathname "cl-weave-metadata-spec.json"))
           (options (cl-weave/cli::parse-cli-arguments
                     (list "metadata" "--reporter" "spec"
                           "--output" (namestring output-file))
                     (cl-weave/cli::make-cli-options))))
      (when (probe-file output-file)
        (delete-file output-file))
      (unwind-protect
           (progn
             (expect (with-output-to-string (*standard-output*)
                       (cl-weave/cli::run-command options))
                     :to-equal "")
              (let ((output (read-text-file output-file)))
              (expect output :to-contain "\"kind\":\"cl-weave-metadata\"")
              (expect output :to-contain "\"schemaVersion\":22")
              (expect output :to-contain "\"qualityGates\"")
              (expect output :not :to-contain ":KIND")))
        (when (probe-file output-file)
          (delete-file output-file)))))

  (it "normalizes doctor reporter spec to JSON output"
    (let* ((options (cl-weave/cli::parse-cli-arguments
                     '("doctor" "--reporter" "spec")
                     (cl-weave/cli::make-cli-options)))
           (output (with-output-to-string (stream)
                     (cl-weave/cli::report-doctor options stream))))
      (expect (cl-weave/cli::doctor-reporter options) :to-be :json)
      (expect output :to-contain "\"schemaVersion\":1")
      (expect output :to-contain "\"kind\":\"doctor-report\"")))

  (it "rejects unsupported doctor reporters early"
    (dolist (reporter '("tap" "github" "junit" "jsonl"))
      (let ((options (cl-weave/cli::parse-cli-arguments
                      (list "doctor" "--reporter" reporter)
                      (cl-weave/cli::make-cli-options))))
        (expect (lambda ()
                  (cl-weave/cli::doctor-reporter options))
                :to-throw
                "cl-weave: doctor mode supports json and sexp reporters."))))

  (it "rejects unsupported metadata reporters early"
    (dolist (reporter '("tap" "github" "junit" "jsonl"))
      (let ((options (cl-weave/cli::parse-cli-arguments
                      (list "metadata" "cl-weave-tests" "--reporter" reporter)
                      (cl-weave/cli::make-cli-options))))
        (expect (lambda ()
                  (cl-weave/cli::metadata-reporter options))
                :to-throw
                "cl-weave: metadata mode supports json and sexp reporters."))))

  (it "prints AI-friendly command usage"
    (let ((usage (cl-weave/cli::cli-usage)))
      (expect usage :to-contain "cl-weave run [SYSTEM] [options]")
      (expect usage :to-contain "cl-weave doctor [SYSTEM] [options]")
      (expect usage :to-contain "cl-weave metadata [SYSTEM] [options]")
      (expect usage :to-contain "cl-weave version")
      (expect usage :to-contain "cl-weave help")
      (expect usage :to-contain "--reporter REPORTER")
      (expect usage :to-contain "--shard INDEX/COUNT")
      (expect usage :to-contain "--retry INTEGER")
      (expect usage :to-contain "--test-timeout-ms MS")
      (expect usage :to-contain "--filter TEXT")
      (expect usage :to-contain "--output FILE")
      (expect usage :to-contain "--fail-with-no-tests")
      (expect usage :to-contain "--snapshot-dir DIR")
      (expect usage :to-contain "--snapshot-file FILE")
      (expect usage :to-contain "--update-snapshots")
      (expect usage :to-contain "--version")))

  (it "keeps command usage synchronized with CLI option metadata"
    (let ((usage (cl-weave/cli::cli-usage)))
      (dolist (entry (getf (cl-weave/cli::framework-metadata) :options))
        (dolist (name (cons (getf entry :name) (getf entry :aliases)))
          (let ((argument (getf entry :argument)))
            (expect usage
                    :to-contain
                    (if argument
                        (format nil "~A ~A" name argument)
                        name)))))))
