(in-package #:cl-weave/tests)

(describe "cli entrypoint"
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
        (expect (getf observed-arguments :order) :to-be nil)
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
             (expect stderr :not :to-contain "\"schemaVersion\":6")
             (let ((output (read-text-file output-file)))
               (expect output :to-contain "\"schemaVersion\":6")
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

  (it "loads project systems through ASDF"
    (let* ((options (cl-weave/cli::make-cli-options
                     :systems '("cl-weave-tests")))
           (loaded-asdf-systems '()))
      (with-mocked-functions
          (((symbol-function 'asdf:find-system)
            (lambda (&rest args)
              (declare (ignore args))
              :cl-weave-tests))
           ((symbol-function 'asdf:load-system)
            (lambda (system)
              (push system loaded-asdf-systems)
              :loaded-asdf)))
        (expect (cl-weave/cli::load-requested-inputs options) :to-be nil)
        (expect loaded-asdf-systems :to-equal '("cl-weave-tests")))))

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

  (it "rejects unsupported structured reporters early"
    (dolist (contract
             '(("doctor" cl-weave/cli::doctor-reporter
                "cl-weave: doctor mode supports json and sexp reporters.")
               ("metadata" cl-weave/cli::metadata-reporter
                "cl-weave: metadata mode supports json and sexp reporters.")))
      (destructuring-bind (command reporter-function message) contract
        (dolist (reporter '("tap" "github" "junit" "jsonl"))
          (let ((options (cl-weave/cli::parse-cli-arguments
                          (list command "--reporter" reporter)
                          (cl-weave/cli::make-cli-options))))
            (expect (lambda ()
                      (funcall reporter-function options))
                    :to-throw
                    message))))))

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
      (dolist (entry (getf (cl-weave/metadata:framework-metadata) :options))
        (let ((name (getf entry :name))
              (argument (getf entry :argument)))
          (expect usage
                  :to-contain
                  (if argument
                      (format nil "~A ~A" name argument)
))))))
