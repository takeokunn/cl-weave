(in-package #:cl-weave/metadata)

(defparameter *metadata-quality-gates*
  '((:name "flake-check"
     :kind "nix"
     :command ("nix" "flake" "check" "--print-build-logs")
     :timeout-seconds 600
     :artifacts nil
     :description "Run the complete Nix flake validation suite.")
    (:name "cli-json-results"
     :kind "cli"
     :command ("nix" "run" "." "--" "run" "cl-weave/tests"
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
               "sbcl" "--dynamic-space-size" "4096"
               "--noinform" "--non-interactive" "--load"
               "scripts/run-tests.lisp")
     :timeout-seconds 360
     :artifacts ("cl-weave-results.json")
     :description "Verify the in-repo script can emit JSON results for CI artifacts.")
    (:name "ai-metadata-artifact"
     :kind "cli"
     :command ("nix" "run" "." "--" "metadata" "cl-weave/tests"
               "--reporter" "json" "--output" "cl-weave-metadata.json")
     :timeout-seconds 120
     :artifacts ("cl-weave-metadata.json")
     :description "Verify agent discovery metadata through the packaged CLI.")
    (:name "jsonl-events-artifact"
     :kind "script"
     :command ("nix" "develop" "--command" "perl" "-e"
               "alarm 360; exec @ARGV" "--" "env" "CL_WEAVE_REPORTER=jsonl"
               "CL_WEAVE_OUTPUT_FILE=cl-weave-events.jsonl"
               "sbcl" "--dynamic-space-size" "4096"
               "--noinform" "--non-interactive" "--load"
               "scripts/run-tests.lisp")
     :timeout-seconds 360
     :artifacts ("cl-weave-events.jsonl")
     :description "Verify JSONL streaming event output for automation.")
    (:name "coverage-artifact"
     :kind "script"
     :command ("nix" "develop" "--command" "sh"
               "scripts/run-coverage-gate.sh")
     :timeout-seconds 360
     :artifacts ("cl-weave.coverage" "cl-weave-coverage-report/"
                 "cl-weave-coverage-summary.json")
     :description "Require measured product-source expression and branch coverage to stay at or above the 87% ratchet baseline, then publish SBCL coverage artifacts.")
    (:name "coverage-gate-unit"
     :kind "script"
     :command ("nix" "develop" "--command" "perl"
               "scripts/test-coverage-gate.pl")
     :timeout-seconds 30
     :artifacts nil
     :description "Verify the coverage gate's threshold logic with its Perl unit tests.")
    (:name "plan-artifact"
     :kind "cli"
     :command ("nix" "run" "." "--" "list" "cl-weave/tests"
               "--reporter" "json" "--filter"
               "filtering > runs only tests matching a path substring"
               "--output" "cl-weave-plan.json")
     :timeout-seconds 120
     :artifacts ("cl-weave-plan.json")
     :description "Verify machine-readable test discovery output for agents.")
    (:name "watch-once-artifact"
     :kind "cli"
     :command ("nix" "run" "." "--" "watch" "cl-weave/tests"
               "--once" "--reporter" "json" "--filter"
               "filtering > runs only tests matching a path substring"
               "--output" "cl-weave-watch-once.json")
     :timeout-seconds 120
     :artifacts ("cl-weave-watch-once.json")
     :description "Verify one-shot watch mode through the packaged CLI.")
    (:name "tap-artifact"
     :kind "cli"
     :command ("nix" "run" "." "--" "run" "cl-weave/tests"
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
               "sbcl" "--dynamic-space-size" "4096"
               "--noinform" "--non-interactive" "--load"
               "scripts/run-tests.lisp")
     :timeout-seconds 60
     :artifacts nil
     :description "Verify environment-driven filtering in the in-repo script runner.")
    (:name "junit-artifact"
     :kind "script"
     :command ("nix" "develop" "--command" "perl" "-e"
               "alarm 360; exec @ARGV" "--" "env" "CL_WEAVE_REPORTER=junit"
               "CL_WEAVE_OUTPUT_FILE=cl-weave-junit.xml"
               "sbcl" "--dynamic-space-size" "4096"
               "--noinform" "--non-interactive" "--load"
               "scripts/run-tests.lisp")
     :timeout-seconds 360
     :artifacts ("cl-weave-junit.xml")
     :description "Verify CI-oriented JUnit report generation.")))
