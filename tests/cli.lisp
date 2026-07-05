(in-package #:cl-weave/tests)

(defun normalize-shell-text (text)
  (with-output-to-string (stream)
    (loop with spacing = t
          for character across text
          do (cond
               ((char= character #\')
                nil)
               ((member character '(#\Newline #\Tab #\Return #\Space))
                (unless spacing
                  (write-char #\Space stream)
                  (setf spacing t)))
               (t
                (write-char character stream)
                (setf spacing nil))))))

(defun workflow-command-string (command)
  (format nil "~{~A~^ ~}" command))

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

  (it "parses Vitest camelCase option aliases"
    (let ((options (cl-weave/cli::parse-cli-arguments
                    '("run"
                      "--testNamePattern"
                      "cli"
                      "--outputFile=vitest-results.json"
                      "--testTimeout=1500"
                      "--maxWorkers=5"
                      "--coverageOutput=coverage.out"
                      "--passWithNoTests"
                      "--snapshotDir"
                      "tests/__snapshots__/"
                      "--snapshotFile=vitest.snapshots"
                      "--update")
                    (cl-weave/cli::make-cli-options)))
          (watch-options (cl-weave/cli::parse-cli-arguments
                          '("watch" "cl-weave-tests" "--watchInterval" "2.5")
                          (cl-weave/cli::make-cli-options)))
          (snapshot-options (cl-weave/cli::parse-cli-arguments
                             '("run" "--updateSnapshots" "--testTimeoutMs" "1750")
                             (cl-weave/cli::make-cli-options))))
      (expect (cl-weave/cli::cli-options-name-filter options) :to-equal "cli")
      (expect (cl-weave/cli::cli-options-output-file options)
              :to-equal "vitest-results.json")
      (expect (cl-weave/cli::cli-options-test-timeout-ms options)
              :to-be 1500)
      (expect (cl-weave/cli::cli-options-max-workers options)
              :to-be 5)
      (expect (cl-weave/cli::cli-options-coverage-output options)
              :to-equal "coverage.out")
      (expect (cl-weave/cli::cli-options-pass-with-no-tests options) :to-be t)
      (expect (cl-weave/cli::cli-options-snapshot-directory options)
              :to-equal #P"tests/__snapshots__/")
      (expect (cl-weave/cli::cli-options-snapshot-file options)
              :to-equal "vitest.snapshots")
      (expect (cl-weave/cli::cli-options-update-snapshots options) :to-be t)
      (expect (cl-weave/cli::cli-options-watch-interval watch-options)
              :to-be 2.5)
      (expect (cl-weave/cli::cli-options-update-snapshots snapshot-options)
              :to-be t)
      (expect (cl-weave/cli::cli-options-test-timeout-ms snapshot-options)
              :to-be 1750)))

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
                   (list "watch" "--watchInterval" value)
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
               (expect output :to-contain "\"schemaVersion\":4")
               (expect output :to-contain "\"kind\":\"test-results\"")
               (expect output :to-contain "\"events\":[]")))
        (when (probe-file output-file)
          (delete-file output-file)))))

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
        (expect output :to-contain "\"schemaVersion\":5")
        (expect output :to-contain "\"commands\"")
        (expect output :to-contain "\"metadata\"")
        (expect output :to-contain "\"artifactSchemas\"")
        (expect output :to-contain "\"kind\":\"test-results\"")
        (expect output :to-contain "\"schemaVersion\":4")
        (expect output :to-contain "\"fields\"")
        (expect output :to-contain "\"name\":\"events\"")
        (expect output :to-contain "\"kind\":\"array\"")
        (expect output :to-contain "\"required\":true")
        (expect output :to-contain "\"kind\":\"test-plan\"")
        (expect output :to-contain "\"schemaVersion\":2")
        (expect output :to-contain "\"streaming\":true")
        (expect output :to-contain "\"qualityGates\"")
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
        (expect output :to-contain "\"--testNamePattern\"")
        (expect output :to-contain "\"CL_WEAVE_TEST_FILTER\"")
        (expect output :to-contain "\"--updateSnapshots\"")
        (expect output :to-contain "\"matchers\"")
        (expect output :to-contain "\"to-be-even\"")
        (expect output :to-contain "\"mutationOperators\"")
        (expect output :to-contain "\"arithmetic-operator\"")
        (expect output :to-contain "\"packageExports\"")
        (expect output :to-contain "\"cl-weave\"")
        (expect output :to-contain "\"describe\"")
        (expect output :to-contain "\"expect\"")
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
               (expect output :to-contain "\"schemaVersion\":5")
               (expect output :to-contain "\"artifactSchemas\"")
               (expect output :to-contain "\"qualityGates\"")
               (expect output :to-contain "\"packageExports\"")))
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
      (expect output :not :to-contain "\"cl-weave-metadata\"")
      (expect output :not :to-contain "\"cl-weave\"")
      (expect output :not :to-contain "\"--testNamePattern\"")
      (expect output :not :to-contain "\"describe-it-dsl\"")))

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
      (expect (getf metadata :schema-version) :to-be 5)
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
      (expect (getf coverage-gate :artifacts)
              :to-contain "cl-weave.coverage")
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
      (expect (getf filter-option :aliases) :to-contain "--testNamePattern")
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
      (expect (assoc "metadata" reporter-command-choices :test #'string=)
              :to-equal '("metadata" ("json" "sexp")))
      (expect (second (assoc "metadata" reporter-command-choices :test #'string=))
              :not :to-contain "jsonl")
      (expect (second (assoc "list" reporter-command-choices :test #'string=))
              :not :to-contain "tap")
      (expect sequence-option :not :to-be nil)
      (expect (getf sequence-option :choices)
              :to-equal '("defined" "random" "shuffle"))
      (expect max-workers-option :not :to-be nil)
      (expect (getf max-workers-option :aliases) :to-contain "--maxWorkers")
      (expect (getf max-workers-option :commands) :to-contain "run")
      (expect (getf max-workers-option :commands) :to-contain "watch")
      (expect (getf max-workers-option :commands) :not :to-contain "list")
      (expect (getf max-workers-option :value-kind) :to-be :positive-integer)
      (expect (getf max-workers-option :environment)
              :to-contain "CL_WEAVE_MAX_WORKERS")
      (expect snapshot-option :not :to-be nil)
      (expect (getf snapshot-option :aliases) :to-contain "--update")
      (expect (getf snapshot-option :aliases) :to-contain "--updateSnapshots")
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
           (mutations-schema (find "mutations" schemas
                                   :key (lambda (entry) (getf entry :kind))
                                   :test #'string=))
           (field-name (lambda (entry) (getf entry :name))))
      (expect (getf metadata :schema-version) :to-be 5)
      (expect results-schema :not :to-be nil)
      (expect (getf results-schema :commands) :to-equal '("run" "watch"))
      (expect (getf results-schema :reporters) :to-equal '("json" "sexp"))
      (expect (getf results-schema :schema-version) :to-be 4)
      (expect (getf results-schema :streaming) :to-be nil)
      (expect (find "events" (getf results-schema :fields)
                    :key field-name :test #'string=)
              :not :to-be nil)
      (expect event-schema :not :to-be nil)
      (expect (getf event-schema :reporters) :to-equal '("jsonl"))
      (expect (getf event-schema :streaming) :to-be t)
      (expect (find "event" (getf event-schema :fields)
                    :key field-name :test #'string=)
              :not :to-be nil)
      (expect (getf event-schema :commands) :to-equal '("run" "watch"))
      (expect plan-schema :not :to-be nil)
      (expect (getf plan-schema :commands) :to-equal '("list"))
      (expect (getf plan-schema :schema-version) :to-be 2)
      (expect mutations-schema :not :to-be nil)
      (expect (getf mutations-schema :commands) :to-equal '())
      (expect (getf mutations-schema :reporters) :to-equal '("json" "sexp"))
      (expect (getf mutations-schema :streaming) :to-be nil)
      (expect (mapcar field-name (getf mutations-schema :fields))
              :to-equal '("schemaVersion" "kind" "total" "killed"
                          "survived" "errored" "score" "results"))))

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

  (it "keeps artifact schemas aligned with command reporter contracts"
    (labels ((reporter-choices-for (command metadata)
               (cond
                 ((string= command "run")
                  (getf metadata :reporters))
                 ((string= command "watch")
                  (getf metadata :reporters))
                 ((string= command "list")
                  (getf metadata :list-reporters))
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
               (member name exports :test #'string=)))
        (dolist (entry (getf metadata :vitest-aliases))
          (expect (getf entry :alias) :to-satisfy #'exportedp)
          (expect (getf entry :canonical) :to-satisfy #'exportedp)))))

  (it "keeps package export metadata synchronized with actual packages"
    (flet ((actual-exports (package-name)
             (let ((exports '()))
               (do-external-symbols (symbol (find-package (string-upcase package-name)))
                 (push (string-downcase (symbol-name symbol)) exports))
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

  (it "keeps metadata aliases in Common Lisp reader spelling"
    (dolist (entry (getf (cl-weave/cli::framework-metadata) :vitest-aliases))
      (dolist (name (list (getf entry :alias) (getf entry :canonical)))
        (expect (every (lambda (char)
                         (not (upper-case-p char)))
                       name)
                :to-be t))))

  (it "keeps CLI alias handlers aligned with metadata"
    (cl-weave/cli::ensure-cli-option-aliases-registered)
    (dolist (entry cl-weave/cli::*metadata-cli-options*)
      (let ((canonical (getf entry :name))
            (aliases (getf entry :aliases)))
        (let ((canonical-handler
                (gethash canonical cl-weave/cli::*cli-option-handlers*)))
          (expect canonical-handler :not :to-be nil)
          (dolist (alias aliases)
            (expect (gethash alias cl-weave/cli::*cli-option-handlers*)
                    :to-be canonical-handler))))))

  (it "keeps environment appliers aligned with environment-backed metadata"
    (dolist (entry cl-weave/cli::*metadata-cli-options*)
      (let ((name (getf entry :name))
            (environment (getf entry :environment)))
        (if environment
            (expect (gethash name cl-weave/cli::*cli-environment-appliers*)
                    :not :to-be nil)
            (expect (gethash name cl-weave/cli::*cli-environment-appliers*)
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
          (exit-code nil))
      (expect (cl-weave/cli::cli-options-version flag-options) :to-be t)
      (expect (cl-weave/cli::cli-options-version command-options) :to-be t)
      (expect (cl-weave/cli::cli-version) :to-equal "0.1.0")
      (with-mocked-functions
          (((symbol-function 'cl-weave/cli::exit-process)
            (lambda (code)
              (setf exit-code code))))
        (let ((output (with-output-to-string (*standard-output*)
                        (cl-weave/cli:main '("--version")))))
          (expect output :to-equal (format nil "cl-weave 0.1.0~%"))
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
                     "--testTimeout" "2500")))
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
        (expect (getf observed-arguments :stream) :to-be-truthy))))

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
           ((symbol-function 'asdf:load-asd)
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
                      (pathname-directory cwd)))))))

  (it "normalizes metadata reporter spec to JSON output"
    (let* ((options (cl-weave/cli::parse-cli-arguments
                     '("metadata" "cl-weave-tests" "--reporter" "spec")
                     (cl-weave/cli::make-cli-options)))
           (output (with-output-to-string (stream)
                     (cl-weave/cli::report-framework-metadata options stream))))
      (expect (cl-weave/cli::metadata-reporter options) :to-be :json)
      (expect output :to-contain "\"schemaVersion\":5")
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
               (expect output :to-contain "\"schemaVersion\":5")
               (expect output :to-contain "\"qualityGates\"")
               (expect output :not :to-contain ":KIND")))
        (when (probe-file output-file)
          (delete-file output-file)))))

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
      (expect usage :to-contain "cl-weave metadata [SYSTEM] [options]")
      (expect usage :to-contain "cl-weave version")
      (expect usage :to-contain "cl-weave help")
      (expect usage :to-contain "--reporter REPORTER")
      (expect usage :to-contain "--shard INDEX/COUNT")
      (expect usage :to-contain "--retry INTEGER")
      (expect usage :to-contain "--testTimeout MS")
      (expect usage :to-contain "--testNamePattern TEXT")
      (expect usage :to-contain "--outputFile FILE")
      (expect usage :to-contain "--failWithNoTests")
      (expect usage :to-contain "--snapshotDir DIR")
      (expect usage :to-contain "--snapshotFile FILE")
      (expect usage :to-contain "--updateSnapshots")
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
