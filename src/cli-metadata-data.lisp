(in-package #:cl-weave/cli)

(defparameter *metadata-commands*
  '("run" "list" "watch" "doctor" "metadata" "version" "help"))

(defparameter *metadata-extra-environment-variables*
  '("CL_WEAVE_PROPERTY_TESTS"
    "CL_WEAVE_PROPERTY_SEED"
    "CL_WEAVE_COVERAGE_REPORT_DIR"))

(defparameter *metadata-policy-documents*
  '("CONTRIBUTING.md"
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

(defparameter *metadata-reference-documents*
  '((:name "readme"
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

(defparameter *metadata-citation*
  '(:cff-version "1.2.0"
    :message "If you use cl-weave in research, tooling, or documentation, please cite the project using this metadata."
    :title "cl-weave"
    :authors ((:name "takeokunn"))
    :license "MIT"
    :repository-code "https://github.com/takeokunn/cl-weave"
    :url "https://github.com/takeokunn/cl-weave"
    :version "0.1.0"
    :preferred-citation-path "CITATION.cff"))

(defparameter *metadata-distribution-channels*
  '((:name "source-self-test"
     :kind "source-checkout"
     :install-command ()
     :run-command ("sbcl" "--noinform" "--non-interactive" "--load"
                   "scripts/run-tests.lisp")
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

(defparameter *metadata-support-channels*
  '((:name "issue-tracker"
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

(defparameter *metadata-community-health*
  '((:name "bug-report-form"
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

(defparameter *metadata-security-contacts*
  '((:name "security-policy"
     :kind "document"
     :target "SECURITY.md"
     :scope "Private vulnerability reporting guidance and security handling policy.")))

(defparameter *metadata-lifecycle*
  '(:stage "pre-1.0"
    :status "active"
    :supported-line "main"
    :support-document "docs/support-policy.md"
    :versioning-document "docs/versioning-policy.md"
    :security-document "SECURITY.md"))

(defparameter *metadata-governance*
  '(:policy-document "docs/governance.md"
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

(defparameter *metadata-runtime-support*
  '(:policy-document "docs/runtime-support.md"
    :primary-implementation "SBCL"
    :supported-targets ((:implementation "SBCL"
                         :platforms ("Linux" "macOS")
                         :status "supported"))
    :best-effort-targets ((:implementation "Other Common Lisp implementations"
                           :platforms ("implementation-dependent")
                           :status "best-effort"))
    :implementation-specific-features
    ("it-isolated subprocess execution"
     "coverage capture and reset/save integration"
     "allocation assertions in CI-focused tests"
     "MOP-dependent metadata and structural assertions")))

(defparameter *metadata-release-process*
  '(:policy-document "docs/release-process.md"
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

(defparameter *metadata-continuous-integration*
  '(:policy-document "docs/release-process.md"
    :provider "github-actions"
    :workflow-path ".github/workflows/ci.yml"
    :job-name "nix"
    :triggers ("pull_request" "push:main" "workflow_dispatch")
    :systems ("x86_64-linux" "aarch64-darwin")
    :artifact-bundle "cl-weave-test-reports-${{ matrix.system }}"
    :cache-provider "cachix"
    :cache-modes ("pull-only" "push-enabled")
    :quality-gate-source "qualityGates"))

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
               "alarm 360; exec @ARGV" "--" "sh"
               "scripts/run-coverage-gate.sh")
     :timeout-seconds 360
     :artifacts ("cl-weave.coverage" "cl-weave-coverage-report/"
                 "cl-weave-coverage-summary.json")
     :description "Require measured product-source expression and branch coverage to reach 100%, then publish SBCL coverage artifacts.")
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
     :commands ("run" "list" "watch" "doctor" "metadata")
     :argument "REPORTER"
     :value-kind :reporter
     :choices :run-reporters
     :command-choices :reporter-command-choices
     :environment ("CL_WEAVE_REPORTER")
     :description "Reporter name for run, list, watch, doctor, or metadata output")
   (:name "--filter"
     :aliases nil
     :commands ("run" "list" "watch")
     :argument "TEXT"
     :value-kind :test-name-pattern
     :choices nil
     :environment ("CL_WEAVE_TEST_FILTER")
     :description "Run or list tests whose Vitest-style path contains TEXT")
   (:name "--output"
     :aliases nil
     :commands ("run" "list" "watch" "doctor" "metadata")
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
     :aliases nil
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
     :aliases nil
     :commands ("run" "list" "watch")
     :argument "MS"
     :value-kind :milliseconds
     :choices nil
     :environment ("CL_WEAVE_TEST_TIMEOUT" "CL_WEAVE_TEST_TIMEOUT_MS")
     :description "Default per-attempt timeout in milliseconds")
   (:name "--max-workers"
     :aliases nil
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
     :choices ("random")
     :environment ("CL_WEAVE_SEQUENCE")
     :description "Randomize execution order")
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
     :aliases nil
     :commands ("run" "watch")
     :argument "FILE"
     :value-kind :file
     :choices nil
     :environment ("CL_WEAVE_COVERAGE_FILE")
     :description "Save SBCL coverage state to FILE")
   (:name "--pass-with-no-tests"
     :aliases nil
     :commands ("run" "watch")
     :argument nil
     :value-kind :boolean
     :choices nil
     :environment ("CL_WEAVE_PASS_WITH_NO_TESTS")
     :description "Pass when filters select no tests")
   (:name "--fail-with-no-tests"
     :aliases nil
     :commands ("run" "watch")
     :argument nil
     :value-kind :boolean
     :choices nil
     :environment nil
     :description "Fail when filters select no tests")
   (:name "--snapshot-dir"
     :aliases nil
     :commands ("run" "watch")
     :argument "DIR"
     :value-kind :directory
     :choices nil
     :environment ("CL_WEAVE_SNAPSHOT_DIR")
     :description "External snapshot directory")
   (:name "--snapshot-file"
     :aliases nil
     :commands ("run" "watch")
     :argument "FILE"
     :value-kind :file
     :choices nil
     :environment ("CL_WEAVE_SNAPSHOT_FILE")
     :description "External snapshot file name")
   (:name "--update-snapshots"
     :aliases nil
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
  '("vitest-dsl"
    "describe-it-dsl"
    "expect-matchers"
    "smart-s-expression-assertions"
    "fixtures-and-restarts"
    "fixtures"
    "around-each-continuations"
    "mocks-and-spies"
    "mock-functions"
    "snapshots"
    "property-and-mutation"
    "property-tests"
    "mutation-testing"
    "structured-reporting"
    "subprocess-isolation"
    "coverage"
    "watch-and-parallelism"
    "watch"
    "sharding"
    "isolation-and-cps"
    "artifact-schemas"
    "sequence-ordering"
    "retry"
    "timeout"
    "mop-architecture-assertions"
    "logic-test-plan"
    "ai-discovery-metadata"
    "public-package-exports"
    "cps-continuation-helpers"))

(defparameter *metadata-capability-matrix*
  '((:name "vitest-dsl"
     :status "implemented"
     :summary "Vitest-style describe/it DSL with only, skip, todo, each, fails, conditional, concurrent, sequential, property, and isolated variants."
     :public-apis ("describe" "it" "describe-each" "it-each"
                   "it-concurrent" "it-property" "it-isolated")
     :quality-gates ("flake-check" "filtered-smoke" "plan-artifact")
     :documentation ("README.md" "docs/ai-contract.md"))
    (:name "describe-it-dsl"
     :status "implemented"
     :summary "Core describe/it forms and each-style variants define the primary suite authoring surface."
     :public-apis ("describe" "it" "describe-each" "it-each")
     :quality-gates ("flake-check" "filtered-smoke" "plan-artifact")
     :documentation ("README.md" "docs/ai-contract.md"))
    (:name "expect-matchers"
     :status "implemented"
     :summary "Vitest-style expect API with numeric, collection, string, condition, macro, snapshot, mock, performance, and MOP architecture matchers."
     :public-apis ("expect" "expect-not" "expect-resolves" "expect-rejects"
                   "expect-assertions" "expect-has-assertions" "matcher-metadata")
     :quality-gates ("flake-check" "cli-json-results")
     :documentation ("README.md" "docs/ai-contract.md"))
    (:name "smart-s-expression-assertions"
     :status "implemented"
     :summary "Assertion helpers cover plain values, signals, completion, multiple values, and type checks outside matcher chains."
     :public-apis ("expect" "is" "signals" "finishes" "assert-values"
                   "assert-type")
     :quality-gates ("flake-check" "cli-json-results")
     :documentation ("README.md" "docs/ai-contract.md"))
    (:name "fixtures-and-restarts"
     :status "implemented"
     :summary "before/after/around fixtures and interactive restarts for continue, skip, and retry test recovery."
     :public-apis ("before-all" "after-all" "before-each" "after-each"
                   "around-each")
     :quality-gates ("flake-check" "json-results-artifact")
     :documentation ("README.md" "docs/ai-contract.md"))
    (:name "fixtures"
     :status "implemented"
     :summary "before-all, after-all, before-each, and after-each hooks provide reusable fixture setup and teardown."
     :public-apis ("before-all" "after-all" "before-each" "after-each")
     :quality-gates ("flake-check" "json-results-artifact")
     :documentation ("README.md" "docs/ai-contract.md"))
    (:name "around-each-continuations"
     :status "implemented"
     :summary "around-each hooks and continuation helpers support CPS-style wrapping around test bodies and async-style flows."
     :public-apis ("around-each" "with-continuation-result"
                   "with-continuation-values")
     :quality-gates ("flake-check" "json-results-artifact")
     :documentation ("README.md" "docs/ai-contract.md"))
    (:name "mocks-and-spies"
     :status "implemented"
     :summary "Mock functions and spies with call/result metadata and restoration helpers."
     :public-apis ("make-mock-function" "spy-on" "clear-all-mocks"
                   "mock-calls" "mock-results")
     :quality-gates ("flake-check" "cli-json-results")
     :documentation ("README.md" "docs/ai-contract.md"))
    (:name "mock-functions"
     :status "implemented"
     :summary "Raw mock primitives expose direct control over stub behavior, restoration, and recorded calls or results."
     :public-apis ("make-mock-function" "clear-mock" "reset-mock"
                   "mock-restore" "mock-calls" "mock-results")
     :quality-gates ("flake-check" "cli-json-results")
     :documentation ("README.md" "docs/ai-contract.md"))
    (:name "snapshots"
     :status "implemented"
     :summary "Snapshot helpers support update mode, stored entry inspection, and explicit value snapshot assertions."
     :public-apis ("with-snapshot-updates" "snapshot-entries"
                   "snapshot-value")
     :quality-gates ("flake-check" "json-results-artifact")
     :documentation ("README.md" "docs/ai-contract.md"))
    (:name "property-and-mutation"
     :status "implemented"
     :summary "Property checks and mutation testing metadata for stronger behavioral confidence than example tests alone."
     :public-apis ("it-property" "gen-integer" "gen-string"
                   "run-mutations" "list-mutation-operators")
     :quality-gates ("flake-check" "json-results-artifact")
     :documentation ("README.md" "docs/ai-contract.md"))
    (:name "property-tests"
     :status "implemented"
     :summary "Property-test APIs expose generators and quantified assertions for broader input coverage than example-based suites."
     :public-apis ("it-property" "gen-integer" "gen-string"
                   "gen-list" "gen-map" "gen-vector"
                   "gen-state-machine")
     :quality-gates ("flake-check" "json-results-artifact")
     :documentation ("README.md" "docs/ai-contract.md"))
    (:name "mutation-testing"
     :status "implemented"
     :summary "Mutation-test APIs surface operator inventory, mutation runs, and score thresholds."
     :public-apis ("run-mutations" "list-mutation-operators"
                   "assert-mutation-score")
     :quality-gates ("flake-check" "json-results-artifact")
     :documentation ("README.md" "docs/ai-contract.md"))
    (:name "structured-reporting"
     :status "implemented"
     :summary "Spec, SEXP, JSON, JSONL, TAP, GitHub annotation, JUnit, plan, and coverage artifacts with machine-readable schemas."
     :public-apis ("run" "list-tests" "reporter-artifact-schemas"
                   "framework-metadata")
     :quality-gates ("json-results-artifact" "jsonl-events-artifact"
                     "tap-artifact" "junit-artifact" "plan-artifact"
                     "coverage-artifact")
     :documentation ("README.md" "docs/ai-contract.md"))
    (:name "subprocess-isolation"
     :status "implemented"
     :summary "Subprocess isolation APIs protect the main runner from crashes, FFI failures, and process-boundary hazards."
     :public-apis ("it-isolated" "run-isolated"
                   "assert-isolated-success")
     :quality-gates ("flake-check" "json-results-artifact")
     :documentation ("README.md" "docs/ai-contract.md"))
    (:name "coverage"
     :status "implemented"
     :summary "Coverage helpers expose runtime capability checks, state reset, populated HTML report generation, optional sidecar persistence, and suite execution entrypoints."
     :public-apis ("run-all" "reset-coverage" "save-coverage"
                   "coverage-support-available-p")
     :quality-gates ("coverage-artifact" "flake-check")
     :documentation ("README.md" "docs/ai-contract.md"))
    (:name "watch-and-parallelism"
     :status "implemented"
     :summary "Watch-once automation, filtering, sharding, deterministic sequence controls, and bounded adjacent concurrent batches."
     :public-apis ("run" "run-all" "list-tests")
     :quality-gates ("watch-once-artifact" "filtered-smoke" "flake-check")
     :documentation ("README.md" "docs/ai-contract.md"))
    (:name "watch"
     :status "implemented"
     :summary "System-scoped run and watch entrypoints provide CLI-friendly iteration loops for local development."
     :public-apis ("watch-system" "run-system")
     :quality-gates ("watch-once-artifact" "flake-check")
     :documentation ("README.md" "docs/ai-contract.md"))
    (:name "sharding"
     :status "implemented"
     :summary "Shard-aware run and listing entrypoints support partitioned execution without abandoning deterministic plan generation."
     :public-apis ("run" "run-all" "list-tests" "run-system"
                   "watch-system")
     :quality-gates ("plan-artifact" "watch-once-artifact" "flake-check")
     :documentation ("README.md" "docs/ai-contract.md"))
    (:name "isolation-and-cps"
     :status "implemented"
     :summary "Subprocess isolation for crash/FFI boundaries and thunk-based CPS helpers for async-style test flows."
     :public-apis ("it-isolated" "expect-poll"
                   "expect-eventually")
     :quality-gates ("flake-check" "json-results-artifact")
     :documentation ("README.md" "docs/ai-contract.md"))
    (:name "artifact-schemas"
     :status "implemented"
     :summary "Artifact schema metadata defines machine-readable contracts for AI metadata, JSON results, JSONL events, and plan outputs."
     :public-apis ("reporter-artifact-schemas" "framework-metadata")
     :quality-gates ("ai-metadata-artifact" "json-results-artifact"
                     "jsonl-events-artifact" "plan-artifact")
     :documentation ("README.md" "docs/ai-contract.md"))
    (:name "sequence-ordering"
     :status "implemented"
     :summary "Sequence-aware execution preserves stable listing and plan semantics while allowing explicit run-order control."
     :public-apis ("run" "run-all" "list-tests" "collect-test-plan")
     :quality-gates ("plan-artifact" "filtered-smoke" "flake-check")
     :documentation ("README.md" "docs/ai-contract.md"))
    (:name "retry"
     :status "implemented"
     :summary "Retry controls surface per-test retry metadata and runner entrypoints that preserve retry behavior in artifacts."
     :public-apis ("retry-test" "run" "run-all" "list-tests")
     :quality-gates ("plan-artifact" "cli-json-results" "flake-check")
     :documentation ("README.md" "docs/ai-contract.md"))
    (:name "timeout"
     :status "implemented"
     :summary "Timeout declarations and runner integration enforce bounded execution and expose timeout policy through metadata."
     :public-apis ("test-timeout" "test-timeout-ms" "run" "run-all"
                   "list-tests")
     :quality-gates ("plan-artifact" "cli-json-results" "flake-check")
     :documentation ("README.md" "docs/ai-contract.md"))
    (:name "mop-architecture-assertions"
     :status "implemented"
     :summary "MOP-aware matcher metadata documents architecture assertions for slots and specialized methods."
     :public-apis ("list-matchers" "matcher-metadata")
     :quality-gates ("flake-check" "ai-metadata-artifact")
     :documentation ("README.md" "docs/ai-contract.md"))
    (:name "logic-test-plan"
     :status "implemented"
     :summary "Logic-oriented test plan collection and query APIs expose analyzable execution facts before a suite runs."
     :public-apis ("collect-test-plan" "query-test-plan" "test-plan-facts"
                   "test-plan-where")
     :quality-gates ("plan-artifact" "flake-check")
     :documentation ("README.md" "docs/ai-contract.md"))
    (:name "ai-discovery-metadata"
     :status "implemented"
     :summary "Machine-readable CLI discovery, package exports, aliases, matcher metadata, mutation operators, and quality gates."
     :public-apis ("reporter-artifact-schemas" "framework-metadata"
                   "list-matchers" "list-mutation-operators")
     :quality-gates ("ai-metadata-artifact" "flake-check")
     :documentation ("README.md" "docs/ai-contract.md"))
    (:name "public-package-exports"
     :status "implemented"
     :summary "Package export metadata exposes the supported public API surface for both core and CLI packages."
     :public-apis ("framework-metadata" "list-matchers"
                   "list-mutation-operators")
     :quality-gates ("ai-metadata-artifact" "flake-check")
     :documentation ("README.md" "docs/ai-contract.md"))
    (:name "cps-continuation-helpers"
     :status "implemented"
     :summary "Continuation helpers bridge thunk-based CPS flows with polling and eventually-style async assertions."
     :public-apis ("with-continuation-result" "with-continuation-values"
                   "expect-poll" "expect-eventually")
     :quality-gates ("flake-check" "json-results-artifact")
     :documentation ("README.md" "docs/ai-contract.md"))))
