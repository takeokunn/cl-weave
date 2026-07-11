(in-package #:cl-weave/tests)

(defun expect-text-contract (text required &optional forbidden)
  (dolist (fragment required)
    (expect text :to-contain fragment))
  (dolist (fragment forbidden)
    (expect text :not :to-contain fragment)))

(defun expect-json-field-contracts-documented (document field-tables)
  (dolist (fields field-tables)
    (dolist (field fields)
      (destructuring-bind (metadata-key json-key writer) field
        (declare (ignore metadata-key writer))
        (expect document :to-contain json-key)))))

(describe "cli metadata"
  (it "prints AI-friendly framework metadata"
    (let ((options (cl-weave/cli::parse-cli-arguments
                    '("metadata" "cl-weave-tests")
                    (cl-weave/cli::make-cli-options))))
      (expect (cl-weave/cli::cli-options-command options) :to-be :metadata)
      (expect (cl-weave/cli::cli-options-systems options)
              :to-equal '("cl-weave-tests"))
      (let ((output (with-output-to-string (stream)
                      (cl-weave/cli::report-framework-metadata options stream))))
        (expect-text-contract
         output
         '("\"kind\":\"cl-weave-metadata\"" "\"schemaVersion\":22"
           "\"homepage\"" "\"bugTracker\"" "\"commands\"" "\"metadata\""
           "\"artifactSchemas\"" "\"kind\":\"test-results\"" "\"schemaVersion\":6"
           "\"fields\"" "\"name\":\"events\"" "\"kind\":\"array\"" "\"required\":true"
           "\"kind\":\"test-plan\"" "\"schemaVersion\":2" "\"streaming\":true"
           "\"qualityGates\"" "\"capabilityMatrix\"" "\"citation\"" "\"cffVersion\":\"1.2.0\""
           "\"distributionChannels\"" "\"name\":\"source-self-test\"" "\"installCommand\":[]"
           "\"runCommand\":[\"sbcl\",\"--noinform\",\"--non-interactive\",\"--load\",\"scripts\\/run-tests.lisp\"]"
           "\"governance\"" "\"policyDocument\":\"docs\\/governance.md\""
           "\"reviewOwnership\":\".github\\/CODEOWNERS\"" "\"maintainerResponsibilities\""
           "\"decisionDocuments\"" "\"name\":\"vitest-dsl\"" "\"publicApis\""
           "\"qualityGates\":[\"flake-check\",\"filtered-smoke\",\"plan-artifact\"]"
           "\"documentation\":[\"README.md\",\"docs\\/ai-contract.md\"]" "\"name\":\"flake-check\""
           "\"command\":[\"nix\",\"flake\",\"check\",\"--print-build-logs\"]" "\"timeoutSeconds\":600"
           "\"name\":\"ai-metadata-artifact\"" "\"cl-weave-metadata.json\"" "\"name\":\"tap-artifact\""
           "\"Verify TAP output for line-oriented CI logs.\"" "\"name\":\"filtered-smoke\""
           "\"CL_WEAVE_TEST_FILTER=filtering > runs only tests matching a path substring\""
           "\"options\"" "\"listReporters\"" "\"valueKind\"" "\"commandChoices\""
           "\"name\":\"--reporter\"" "\"command\":\"metadata\"" "\"choices\":[\"json\",\"sexp\"]"
           "\"--filter\"" "\"CL_WEAVE_TEST_FILTER\"" "\"--update-snapshots\"" "\"matchers\""
           "\"to-be-even\"" "\"mutationOperators\"" "\"arithmetic-operator\"" "\"packageExports\""
           "\"cl-weave\"" "\"DESCRIBE\"" "\"EXPECT\"" "\"expect-has-assertions\"")
         '("\"--testNamePattern\"" "\"--updateSnapshots\"" "\"vitestAliases\"")))))

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
      (expect-json-field-contracts-documented
       docs
       (list cl-weave/metadata::*framework-metadata-json-fields*
             cl-weave/cli::*json-capability-matrix-fields*
             cl-weave/cli::*json-reference-document-fields*
             cl-weave/cli::*json-citation-fields*
             cl-weave/cli::*json-citation-author-fields*
             cl-weave/cli::*json-distribution-channel-fields*
             cl-weave/cli::*json-community-health-fields*
             cl-weave/cli::*json-community-health-contact-link-fields*
             cl-weave/cli::*json-governance-fields*
             cl-weave/cli::*json-continuous-integration-fields*))))

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
           (metadata (getf (cl-weave/metadata:framework-metadata) :release-process)))
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
    (let ((metadata (cl-weave/metadata:framework-metadata)))
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
