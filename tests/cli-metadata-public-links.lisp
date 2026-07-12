(in-package #:cl-weave/tests)

(describe "cli metadata public links"
  (it "advertises canonical project links as metadata"
    (let ((metadata (cl-weave/metadata:framework-metadata)))
      (expect (getf metadata :homepage)
              :to-equal "https://github.com/takeokunn/cl-weave")
      (expect (getf metadata :bug-tracker)
              :to-equal "https://github.com/takeokunn/cl-weave/issues")
      (expect (getf metadata :license)
              :to-equal "MIT")
      (expect (getf metadata :policy-documents)
              :to-equal '("docs/community-health.md"
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
                          (:name "ai-contract"
                           :path "docs/ai-contract.md"
                           :description "Machine-readable contract and metadata normalization guide.")
                          (:name "adoption-guide"
                           :path "docs/adoption.md"
                           :description "Migration guidance and downstream adoption plan.")
                          (:name "license"
                           :path "LICENSE"
                           :description "Canonical project license text.")))
      (expect (getf metadata :distribution-channels)
              :to-equal '((:name "source-self-test"
                           :kind "nix"
                           :install-command ()
                           :run-command ("nix" "run" "." "--" "run" "cl-weave/tests")
                           :scope "Run the bundled ASDF test system through the packaged CLI."
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
                                        "docs/issue-reporting.md")
                           :required-sections nil
                           :contact-links ((:name "Support policy"
                                            :target "https://github.com/takeokunn/cl-weave/blob/main/docs/support-policy.md"
                                            :purpose "Check whether the request belongs in issue tracking and what detail is required.")
                                           (:name "Security reporting"
                                            :target "https://github.com/takeokunn/cl-weave/security/advisories/new"
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
              :to-equal '((:name "security-reporting"
                           :kind "github"
                           :target "https://github.com/takeokunn/cl-weave/security/advisories/new"
                           :scope "Private vulnerability reporting through GitHub security advisories.")))
      (expect (getf metadata :lifecycle)
              :to-equal '(:stage "pre-1.0"
                          :status "active"
                          :supported-line "main"
                          :support-document "docs/support-policy.md"
                          :versioning-document "docs/versioning-policy.md"))
      (expect (getf metadata :governance)
              :to-equal '(:policy-document "docs/governance.md"
                          :review-ownership ".github/CODEOWNERS"
                          :maintainer-responsibilities
                          ("Triaging issues and pull requests against the documented project scope and support boundaries."
                           "Protecting compatibility expectations recorded in the versioning policy."
                           "Keeping machine-readable metadata, release notes, and policy documents synchronized."
                           "Requiring regression coverage for public-surface changes when practical."
                           "Handling security-sensitive reports through private GitHub security advisories.")
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
                           "Summarize user-visible changes in the release notes."
                           "Check that README.md and docs/maintenance-policy.md still match the current workflow."
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

)
