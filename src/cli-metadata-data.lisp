(in-package #:cl-weave/cli)

(defparameter *metadata-commands*
  '("run" "list" "watch" "metadata" "version" "help"))

(defparameter *metadata-extra-environment-variables*
  '("CL_WEAVE_PROPERTY_TESTS"
    "CL_WEAVE_PROPERTY_SEED"))

(defparameter *metadata-quality-gates*
  '((:name "flake-check"
     :kind "nix"
     :command ("nix" "flake" "check" "--print-build-logs")
     :timeout-seconds 600
     :artifacts nil
     :description "Run the complete Nix flake validation suite.")
    (:name "cli-json-results"
     :kind "cli"
     :command ("nix" "run" "." "--" "run" "cl-weave-tests"
               "--reporter" "json" "--filter"
               "filtering > runs only tests matching a path substring"
               "--output" "cl-weave-cli-results.json")
     :timeout-seconds 360
     :artifacts ("cl-weave-cli-results.json")
     :description "Verify the packaged CLI can emit schema-versioned JSON results.")
    (:name "json-results-artifact"
     :kind "script"
     :command ("nix" "develop" "--command" "perl" "-e"
               "alarm 360; exec @ARGV" "--" "env" "CL_WEAVE_REPORTER=json"
               "CL_WEAVE_OUTPUT_FILE=cl-weave-results.json"
               "sbcl" "--noinform" "--non-interactive" "--load"
               "scripts/run-tests.lisp")
     :timeout-seconds 360
     :artifacts ("cl-weave-results.json")
     :description "Verify the in-repo script can emit JSON results for CI artifacts.")
    (:name "ai-metadata-artifact"
     :kind "cli"
     :command ("nix" "run" "." "--" "metadata" "cl-weave-tests"
               "--reporter" "json" "--output" "cl-weave-metadata.json")
     :timeout-seconds 120
     :artifacts ("cl-weave-metadata.json")
     :description "Verify agent discovery metadata through the packaged CLI.")
    (:name "jsonl-events-artifact"
     :kind "script"
     :command ("nix" "develop" "--command" "perl" "-e"
               "alarm 360; exec @ARGV" "--" "env" "CL_WEAVE_REPORTER=jsonl"
               "CL_WEAVE_OUTPUT_FILE=cl-weave-events.jsonl"
               "sbcl" "--noinform" "--non-interactive" "--load"
               "scripts/run-tests.lisp")
     :timeout-seconds 360
     :artifacts ("cl-weave-events.jsonl")
     :description "Verify JSONL streaming event output for automation.")
    (:name "coverage-artifact"
     :kind "script"
     :command ("nix" "develop" "--command" "perl" "-e"
               "alarm 360; exec @ARGV" "--" "env" "CL_WEAVE_COVERAGE=1"
               "CL_WEAVE_COVERAGE_FILE=cl-weave.coverage"
               "sbcl" "--noinform" "--non-interactive" "--load"
               "scripts/run-tests.lisp")
     :timeout-seconds 360
     :artifacts ("cl-weave.coverage")
     :description "Verify SBCL coverage sidecar generation for CI artifacts.")
    (:name "plan-artifact"
     :kind "cli"
     :command ("nix" "run" "." "--" "list" "cl-weave-tests"
               "--reporter" "json" "--filter"
               "filtering > runs only tests matching a path substring"
               "--output" "cl-weave-plan.json")
     :timeout-seconds 120
     :artifacts ("cl-weave-plan.json")
     :description "Verify machine-readable test discovery output for agents.")
    (:name "watch-once-artifact"
     :kind "cli"
     :command ("nix" "run" "." "--" "watch" "cl-weave-tests"
               "--once" "--reporter" "json" "--filter"
               "filtering > runs only tests matching a path substring"
               "--output" "cl-weave-watch-once.json")
     :timeout-seconds 120
     :artifacts ("cl-weave-watch-once.json")
     :description "Verify one-shot watch mode through the packaged CLI.")
    (:name "tap-artifact"
     :kind "cli"
     :command ("nix" "run" "." "--" "run" "cl-weave-tests"
               "--reporter" "tap" "--filter"
               "filtering > runs only tests matching a path substring"
               "--output" "cl-weave-tap.txt")
     :timeout-seconds 120
     :artifacts ("cl-weave-tap.txt")
     :description "Verify TAP output for line-oriented CI logs.")
    (:name "filtered-smoke"
     :kind "script"
     :command ("nix" "develop" "--command" "perl" "-e"
               "alarm 60; exec @ARGV" "--" "env"
               "CL_WEAVE_TEST_FILTER=filtering > runs only tests matching a path substring"
               "sbcl" "--noinform" "--non-interactive" "--load"
               "scripts/run-tests.lisp")
     :timeout-seconds 60
     :artifacts nil
     :description "Verify environment-driven filtering in the in-repo script runner.")
    (:name "junit-artifact"
     :kind "script"
     :command ("nix" "develop" "--command" "perl" "-e"
               "alarm 360; exec @ARGV" "--" "env" "CL_WEAVE_REPORTER=junit"
               "CL_WEAVE_OUTPUT_FILE=cl-weave-junit.xml"
               "sbcl" "--noinform" "--non-interactive" "--load"
               "scripts/run-tests.lisp")
     :timeout-seconds 360
     :artifacts ("cl-weave-junit.xml")
     :description "Verify CI-oriented JUnit report generation.")))

(defparameter *metadata-cli-options*
  '((:name "--system"
     :aliases nil
     :commands ("run" "list" "watch" "metadata")
     :argument "SYSTEM"
     :value-kind :asdf-system
     :choices nil
     :environment ("CL_WEAVE_SYSTEM")
     :description "ASDF system to load before command execution")
    (:name "--load"
     :aliases nil
     :commands ("run" "list" "watch" "metadata")
     :argument "FILE"
     :value-kind :file
     :choices nil
     :environment nil
     :description "Lisp file to load before command execution")
    (:name "--reporter"
     :aliases nil
     :commands ("run" "list" "watch" "metadata")
     :argument "REPORTER"
     :value-kind :reporter
     :choices :run-reporters
     :command-choices :reporter-command-choices
     :environment ("CL_WEAVE_REPORTER")
     :description "Reporter name for run, list, watch, or metadata output")
    (:name "--filter"
     :aliases ("--testNamePattern")
     :commands ("run" "list" "watch")
     :argument "TEXT"
     :value-kind :test-name-pattern
     :choices nil
     :environment ("CL_WEAVE_TEST_FILTER")
     :description "Run or list tests whose Vitest-style path contains TEXT")
    (:name "--output"
     :aliases ("--outputFile")
     :commands ("run" "list" "watch" "metadata")
     :argument "FILE"
     :value-kind :file
     :choices nil
     :environment ("CL_WEAVE_OUTPUT_FILE")
     :description "Write reporter output to FILE")
    (:name "--list"
     :aliases nil
     :commands ("run" "list")
     :argument nil
     :value-kind :boolean
     :choices nil
     :environment ("CL_WEAVE_LIST")
     :description "Discover tests without executing test bodies")
    (:name "--watch"
     :aliases nil
     :commands ("run" "watch")
     :argument nil
     :value-kind :boolean
     :choices nil
     :environment ("CL_WEAVE_WATCH")
     :description "Rerun an ASDF system when source files change")
    (:name "--once"
     :aliases nil
     :commands ("watch")
     :argument nil
     :value-kind :boolean
     :choices nil
     :environment ("CL_WEAVE_WATCH_ONCE")
     :description "Run watch mode once without waiting for file changes")
    (:name "--watch-interval"
     :aliases ("--watchInterval")
     :commands ("watch")
     :argument "SECONDS"
     :value-kind :seconds
     :choices nil
     :environment ("CL_WEAVE_WATCH_INTERVAL")
     :description "Polling interval for watch mode")
    (:name "--bail"
     :aliases nil
     :commands ("run" "watch")
     :argument "N|true|false"
     :value-kind :boolean-or-positive-integer
     :choices nil
     :environment ("CL_WEAVE_BAIL")
     :description "Stop after the first failure, N failures, or disable fast-fail")
    (:name "--retry"
     :aliases nil
     :commands ("run" "list" "watch")
     :argument "INTEGER"
     :value-kind :non-negative-integer
     :choices nil
     :environment ("CL_WEAVE_RETRY")
     :description "Retry failing tests INTEGER extra times")
    (:name "--test-timeout-ms"
     :aliases ("--test-timeout" "--testTimeout" "--testTimeoutMs")
     :commands ("run" "list" "watch")
     :argument "MS"
     :value-kind :milliseconds
     :choices nil
     :environment ("CL_WEAVE_TEST_TIMEOUT" "CL_WEAVE_TEST_TIMEOUT_MS")
     :description "Default per-attempt timeout in milliseconds")
    (:name "--max-workers"
     :aliases ("--maxWorkers")
     :commands ("run" "watch")
     :argument "INTEGER"
     :value-kind :positive-integer
     :choices nil
     :environment ("CL_WEAVE_MAX_WORKERS")
     :description "Limit concurrently executing tests to INTEGER workers")
    (:name "--shard"
     :aliases nil
     :commands ("run" "list" "watch")
     :argument "INDEX/COUNT"
     :value-kind :shard
     :choices nil
     :environment ("CL_WEAVE_SHARD")
     :description "Select a deterministic CI shard")
    (:name "--sequence"
     :aliases nil
     :commands ("run" "list" "watch")
     :argument "ORDER"
     :value-kind :sequence-order
     :choices ("defined" "random" "shuffle")
     :environment ("CL_WEAVE_SEQUENCE")
     :description "Execution order: defined, random, or shuffle")
    (:name "--seed"
     :aliases nil
     :commands ("run" "list" "watch")
     :argument "INTEGER"
     :value-kind :integer
     :choices nil
     :environment ("CL_WEAVE_SEQUENCE_SEED")
     :description "Deterministic random sequence seed")
    (:name "--coverage"
     :aliases nil
     :commands ("run" "watch")
     :argument nil
     :value-kind :boolean
     :choices nil
     :environment ("CL_WEAVE_COVERAGE")
     :description "Wrap execution with SBCL sb-cover")
    (:name "--coverage-output"
     :aliases ("--coverageOutput")
     :commands ("run" "watch")
     :argument "FILE"
     :value-kind :file
     :choices nil
     :environment ("CL_WEAVE_COVERAGE_FILE")
     :description "Save SBCL coverage state to FILE")
    (:name "--pass-with-no-tests"
     :aliases ("--passWithNoTests")
     :commands ("run" "watch")
     :argument nil
     :value-kind :boolean
     :choices nil
     :environment ("CL_WEAVE_PASS_WITH_NO_TESTS")
     :description "Pass when filters select no tests")
    (:name "--fail-with-no-tests"
     :aliases ("--failWithNoTests")
     :commands ("run" "watch")
     :argument nil
     :value-kind :boolean
     :choices nil
     :environment nil
     :description "Fail when filters select no tests")
    (:name "--snapshot-dir"
     :aliases ("--snapshotDir")
     :commands ("run" "watch")
     :argument "DIR"
     :value-kind :directory
     :choices nil
     :environment ("CL_WEAVE_SNAPSHOT_DIR")
     :description "External snapshot directory")
    (:name "--snapshot-file"
     :aliases ("--snapshotFile")
     :commands ("run" "watch")
     :argument "FILE"
     :value-kind :file
     :choices nil
     :environment ("CL_WEAVE_SNAPSHOT_FILE")
     :description "External snapshot file name")
    (:name "--update-snapshots"
     :aliases ("--update" "--updateSnapshots")
     :commands ("run" "watch")
     :argument nil
     :value-kind :boolean
     :choices nil
     :environment ("CL_WEAVE_UPDATE_SNAPSHOTS")
     :description "Update external snapshots during this run")
    (:name "--version"
     :aliases nil
     :commands ("version")
     :argument nil
     :value-kind :boolean
     :choices nil
     :environment nil
     :description "Print the cl-weave version")
    (:name "--help"
     :aliases nil
     :commands ("help")
     :argument nil
     :value-kind :boolean
     :choices nil
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
    ("describe.runIf" . "describe-run-if")
    ("describe.run-if" . "describe-run-if")
    ("describe.skipIf" . "describe-skip-if")
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
    ("it.runIf" . "it-run-if")
    ("it.run-if" . "it-run-if")
    ("it.skipIf" . "it-skip-if")
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
    ("test.runIf" . "test-run-if")
    ("test.run-if" . "test-run-if")
    ("test.skipIf" . "test-skip-if")
    ("test.skip-if" . "test-skip-if")
    ("test.property" . "test-property")
    ("test.isolated" . "test-isolated")
    ("expect.not" . "expect-not")
    ("expect.resolves" . "expect-resolves")
    ("expect.rejects" . "expect-rejects")
    ("expect.assertions" . "expect-assertions")
    ("expect.hasAssertions" . "expect-has-assertions")
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
