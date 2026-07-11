(in-package #:cl-weave/tests)

(describe "community health"
  (it "keeps OSS operations documents discoverable"
    (let ((root (uiop:getcwd))
          (readme (read-text-file (merge-pathnames #P"README.md" (uiop:getcwd))))
          (contributing (read-text-file (merge-pathnames #P"CONTRIBUTING.md"
                                                         (uiop:getcwd))))
          (security (read-text-file (merge-pathnames #P"SECURITY.md"
                                                     (uiop:getcwd))))
          (changelog (read-text-file (merge-pathnames #P"CHANGELOG.md"
                                                      (uiop:getcwd)))))
      (dolist (path '("LICENSE" "CITATION.cff" "CONTRIBUTING.md" "SECURITY.md" "CHANGELOG.md"))
        (expect (probe-file (merge-pathnames path root)) :not :to-be nil)
        (expect readme :to-contain path))
      (expect readme :to-contain ".github/pull_request_template.md")
      (dolist (path '(".github/ISSUE_TEMPLATE/bug_report.md"
                      ".github/ISSUE_TEMPLATE/feature_request.md"
                      ".github/ISSUE_TEMPLATE/config.yml"
                      ".github/pull_request_template.md"
                      ".github/CODEOWNERS"))
        (expect (probe-file (merge-pathnames path root)) :not :to-be nil)
        (expect readme :to-contain path))
      (expect (probe-file (merge-pathnames "docs/community-health.md" root))
              :not :to-be nil)
      (expect readme :to-contain "docs/community-health.md")
      (expect readme :to-contain "docs/governance.md")
      (expect contributing :to-contain "nix flake check")
      (expect contributing :to-contain "cl-weave metadata")
      (expect contributing :to-contain ".github/pull_request_template.md")
      (expect contributing :to-contain "docs/community-health.md")
      (expect contributing :to-contain "docs/governance.md")
      (expect security :to-contain "subprocess isolation")
      (expect security :to-contain "snapshot writes")
      (expect changelog :to-contain "Unreleased")
      (expect changelog :to-contain "machine-readable policy document metadata")))

  (it "keeps the changelog aligned with release policy expectations"
    (let* ((changelog (normalize-markdown-text
                       (read-text-file
                        (merge-pathnames #P"CHANGELOG.md" (uiop:getcwd)))))
           (maintenance-document (normalize-markdown-text
                                  (read-text-file
                                   (merge-pathnames #P"docs/maintenance-policy.md"
                                                    (uiop:getcwd)))))
           (versioning-document (normalize-markdown-text
                                 (read-text-file
                                  (merge-pathnames #P"docs/versioning-policy.md"
                                                   (uiop:getcwd))))))
      (dolist (phrase '("## Unreleased"
                        "### Release Classification"
                        "### Public Surface Notes"
                        "### Migration Notes"
                        "### User-visible Changes"
                        "additive only"))
        (expect changelog :to-contain (normalize-markdown-text phrase)))
      (dolist (phrase '("public-surface discipline"
                        "migration steps"
                        "user-visible changes"))
        (expect maintenance-document :to-contain phrase))
      (dolist (phrase '("additive only"
                        "behavior-preserving"
                        "intentionally breaking"))
        (expect versioning-document :to-contain phrase))
      (expect changelog
              :to-contain
              (normalize-markdown-text
               "No downstream migration steps are currently required."))
      (expect changelog
              :to-contain
              (normalize-markdown-text
               "Existing CLI output, reporter shapes, and machine-readable metadata remain the expected public surface"))))

  (it "keeps citation and license contracts synchronized with repository metadata"
    (let* ((metadata (cl-weave/cli::framework-metadata))
           (reference-documents (getf metadata :reference-documents))
           (citation (getf metadata :citation))
           (citation-entry (find "CITATION.cff"
                                 reference-documents
                                 :key (lambda (entry) (getf entry :path))
                                 :test #'string=))
           (license-entry (find "LICENSE"
                                reference-documents
                                :key (lambda (entry) (getf entry :path))
                                :test #'string=))
           (citation-document (read-text-file
                               (merge-pathnames #P"CITATION.cff"
                                                (uiop:getcwd))))
           (license-document (read-text-file
                              (merge-pathnames #P"LICENSE"
                                               (uiop:getcwd))))
           (author-name (getf (first (getf citation :authors)) :name)))
      (expect citation-entry :not :to-be nil)
      (expect license-entry :not :to-be nil)
      (expect (probe-file (merge-pathnames "CITATION.cff" (uiop:getcwd)))
              :not :to-be nil)
      (expect (probe-file (merge-pathnames "LICENSE" (uiop:getcwd)))
              :not :to-be nil)
      (expect (getf citation :preferred-citation-path)
              :to-equal "CITATION.cff")
      (expect citation-document
              :to-contain
              (format nil "cff-version: ~A" (getf citation :cff-version)))
      (expect citation-document
              :to-contain
              (format nil "message: \"~A\"" (getf citation :message)))
      (expect citation-document
              :to-contain
              (format nil "title: \"~A\"" (getf citation :title)))
      (expect citation-document
              :to-contain
              (format nil "license: \"~A\"" (getf citation :license)))
      (expect citation-document
              :to-contain
              (format nil "repository-code: \"~A\"" (getf citation :repository-code)))
      (expect citation-document
              :to-contain
              (format nil "url: \"~A\"" (getf citation :url)))
      (expect citation-document
              :to-contain
              (format nil "version: \"~A\"" (getf citation :version)))
      (expect citation-document
              :to-contain
              (format nil "name: \"~A\"" author-name))
      (expect license-document :to-contain "MIT License")
      (expect license-document :to-contain author-name)))

  (it "keeps the community health contract synchronized with GitHub intake files"
    (let* ((metadata (cl-weave/cli::framework-metadata))
           (entries (getf metadata :community-health))
           (document (normalize-markdown-text
                      (read-text-file
                       (merge-pathnames #P"docs/community-health.md"
                                        (uiop:getcwd))))))
      (expect (getf metadata :policy-documents)
              :to-contain "docs/community-health.md")
      (expect document :to-contain "# Community Health")
      (dolist (entry entries)
        (expect (probe-file (merge-pathnames (getf entry :path) (uiop:getcwd)))
                :not :to-be nil)
        (expect document :to-contain (getf entry :path))
        (dolist (reference (getf entry :references))
          (expect (probe-file (merge-pathnames reference (uiop:getcwd)))
                  :not :to-be nil)
          (unless (string= reference "docs/community-health.md")
            (expect document :to-contain reference)))
        (let ((entry-text (normalize-markdown-text
                           (read-text-file
                            (merge-pathnames (getf entry :path)
                                             (uiop:getcwd))))))
          (dolist (section (getf entry :required-sections))
            (expect entry-text
                    :to-contain
                    (normalize-markdown-text
                     (format nil "# ~A" section))))
          (dolist (link (getf entry :contact-links))
            (expect entry-text :to-contain (getf link :name))
            (expect entry-text :to-contain (getf link :target)))))))

  (it "keeps support and security routing synchronized with public intake surfaces"
    (let* ((metadata (cl-weave/cli::framework-metadata))
           (homepage (getf metadata :homepage))
           (policy-documents (getf metadata :policy-documents))
           (reference-documents (getf metadata :reference-documents))
           (support-channels (getf metadata :support-channels))
           (security-contacts (getf metadata :security-contacts))
           (readme (normalize-markdown-text
                    (read-text-file
                     (merge-pathnames #P"README.md"
                                      (uiop:getcwd)))))
           (support-document (normalize-markdown-text
                              (read-text-file
                               (merge-pathnames #P"docs/support-policy.md"
                                                (uiop:getcwd)))))
           (security-document (normalize-markdown-text
                               (read-text-file
                                (merge-pathnames #P"SECURITY.md"
                                                 (uiop:getcwd)))))
           (issue-guide (normalize-markdown-text
                         (read-text-file
                          (merge-pathnames #P"docs/issue-reporting.md"
                                           (uiop:getcwd)))))
           (issue-config (read-text-file
                          (merge-pathnames #P".github/ISSUE_TEMPLATE/config.yml"
                                           (uiop:getcwd))))
           (support-policy-url (format nil "~A/blob/main/docs/support-policy.md"
                                       homepage))
           (security-policy-url (format nil "~A/blob/main/SECURITY.md"
                                        homepage)))
      (dolist (path policy-documents)
        (expect (probe-file (merge-pathnames path (uiop:getcwd)))
                :not :to-be nil)
        (expect readme :to-contain path))
      (dolist (entry reference-documents)
        (let ((path (getf entry :path)))
          (expect (probe-file (merge-pathnames path (uiop:getcwd)))
                  :not :to-be nil)
          (unless (string= path "README.md")
            (expect readme :to-contain path))))
      (dolist (channel support-channels)
        (expect (getf channel :target) :not :to-be nil)
        (case (intern (string-upcase (getf channel :name)) :keyword)
          (:ISSUE-TRACKER
           (expect readme :to-contain (getf channel :target))
           (expect support-document :to-contain "Use the issue tracker")
           (expect issue-guide :to-contain "Use this guide when filing bugs")
           (expect issue-guide :to-contain "support-policy.md"))
          (:PULL-REQUESTS
           (expect readme :to-contain (getf channel :target))
           (expect support-document :to-contain "Use pull requests"))
          (:SUPPORT-POLICY
           (expect readme :to-contain (getf channel :target))
           (expect (probe-file (merge-pathnames (getf channel :target)
                                                (uiop:getcwd)))
                   :not :to-be nil)
           (expect issue-config :to-contain "name: Support policy")
           (expect issue-config :to-contain support-policy-url)
           (expect issue-config
                   :to-contain
                   "about: Check whether the request belongs in issue tracking and what detail is required."))))
      (dolist (entry security-contacts)
        (expect (probe-file (merge-pathnames (getf entry :target) (uiop:getcwd)))
                :not :to-be nil)
        (expect readme :to-contain (getf entry :target))
        (expect support-document :to-contain "Use private security reporting")
        (expect security-document :to-contain "# Reporting")
        (expect security-document :to-contain "Report vulnerabilities privately")
        (expect security-document :to-contain "docs/support-policy.md")
        (expect issue-guide :to-contain "security process")
        (expect issue-guide :to-contain "SECURITY.md")
        (expect issue-config :to-contain "name: Security policy")
        (expect issue-config :to-contain security-policy-url)
        (expect issue-config
                :to-contain
                "about: Report vulnerabilities through the private security contact path."))))

  (it "keeps issue reporting guidance synchronized with bug intake contracts"
    (let* ((metadata (cl-weave/cli::framework-metadata))
           (community-health (getf metadata :community-health))
           (bug-report-entry (find "bug-report-form" community-health
                                   :key (lambda (entry) (getf entry :name))
                                   :test #'string=))
           (issue-guide (normalize-markdown-text
                         (read-text-file
                          (merge-pathnames #P"docs/issue-reporting.md"
                                           (uiop:getcwd)))))
           (support-document (normalize-markdown-text
                              (read-text-file
                               (merge-pathnames #P"docs/support-policy.md"
                                                (uiop:getcwd)))))
           (community-document (normalize-markdown-text
                                (read-text-file
                                 (merge-pathnames #P"docs/community-health.md"
                                                  (uiop:getcwd)))))
           (bug-template (normalize-markdown-text
                          (read-text-file
                           (merge-pathnames #P".github/ISSUE_TEMPLATE/bug_report.md"
                                            (uiop:getcwd))))))
      (expect bug-report-entry :not :to-be nil)
      (expect (getf metadata :policy-documents)
              :to-contain "docs/issue-reporting.md")
      (expect issue-guide :to-contain "# Issue Reporting Guide")
      (expect issue-guide :to-contain "support-policy.md")
      (expect issue-guide :to-contain "security process")
      (expect issue-guide :to-contain "SECURITY.md")
      (dolist (detail '("The exact command you ran."
                        "The `cl-weave` version or commit if you are testing a local checkout."
                        "The Common Lisp implementation and version."
                        "Your operating system and shell if the issue touches the CLI."
                        "The expected result and the actual result."
                        "The smallest reproducer you can provide."
                        "Any machine-readable metadata or reporter output that shows the failure."))
        (expect issue-guide
                :to-contain
                (normalize-markdown-text detail)))
      (dolist (detail '("exact command or API entrypoint"
                        "version or commit"
                        "implementation and runtime details"
                        "operating system and shell, when relevant"
                        "expected behavior"
                        "actual behavior"
                        "smallest reproduction you can provide"))
        (expect support-document :to-contain (normalize-markdown-text detail)))
      (expect community-document :to-contain "docs/issue-reporting.md")
      (dolist (section (getf bug-report-entry :required-sections))
        (expect bug-template
                :to-contain
                (normalize-markdown-text
                 (format nil "# ~A" section))))
      (expect bug-template :to-contain "docs/issue-reporting.md")
      (expect bug-template :to-contain "canonical reproduction details")))

  (it "keeps pull request intake guidance synchronized with PR contracts"
    (let* ((metadata (cl-weave/cli::framework-metadata))
           (community-health (getf metadata :community-health))
           (pr-entry (find "pull-request-template" community-health
                           :key (lambda (entry) (getf entry :name))
                           :test #'string=))
           (community-document (normalize-markdown-text
                                (read-text-file
                                 (merge-pathnames #P"docs/community-health.md"
                                                  (uiop:getcwd)))))
           (triage-document (normalize-markdown-text
                             (read-text-file
                              (merge-pathnames #P"docs/triage-policy.md"
                                               (uiop:getcwd)))))
           (release-document (normalize-markdown-text
                              (read-text-file
                               (merge-pathnames #P"docs/release-process.md"
                                                (uiop:getcwd)))))
           (pr-guidance (normalize-markdown-text
                         (read-text-file
                          (merge-pathnames #P"docs/pull-request-template.md"
                                           (uiop:getcwd)))))
           (pr-template (normalize-markdown-text
                         (read-text-file
                          (merge-pathnames #P".github/pull_request_template.md"
                                           (uiop:getcwd))))))
      (expect pr-entry :not :to-be nil)
      (expect community-document :to-contain "docs/pull-request-template.md")
      (expect triage-document :to-contain "Keep PRs narrowly scoped when possible.")
      (expect triage-document :to-contain "Include tests for any behavior change")
      (expect triage-document :to-contain "Call out compatibility impact explicitly")
      (expect triage-document
              :to-contain
              "Link to the relevant issue, policy, or contract document")
      (expect release-document :to-contain "docs/pull-request-template.md")
      (expect release-document :to-contain ".github/pull_request_template.md")
      (expect release-document :to-contain "follow-up risk")
      (dolist (section (getf pr-entry :required-sections))
        (let ((heading (normalize-markdown-text
                        (format nil "# ~A" section))))
          (expect pr-template :to-contain heading)
          (expect pr-guidance :to-contain heading)))
      (expect pr-guidance :to-contain "## Related Issue Or Policy")
      (expect pr-guidance :to-contain "## Notes For Reviewers")
      (expect pr-template :to-contain "docs/pull-request-template.md")))

  (it "keeps runtime support metadata synchronized with published support docs"
    (let* ((metadata (cl-weave/cli::framework-metadata))
           (runtime-support (getf metadata :runtime-support))
           (readme (read-text-file #P"README.md"))
           (runtime-document (read-text-file #P"docs/runtime-support.md")))
      (expect (getf metadata :policy-documents)
              :to-contain "docs/runtime-support.md")
      (expect (getf runtime-support :policy-document)
              :to-equal "docs/runtime-support.md")
      (expect readme :to-contain "## Supported Runtime")
      (expect readme :to-contain "[docs/runtime-support.md](docs/runtime-support.md)")
      (expect readme :to-contain (getf runtime-support :primary-implementation))
      (expect readme :to-contain "Linux and macOS")
      (expect readme :to-contain "subprocess isolation")
      (expect readme :to-contain "coverage handling")
      (expect runtime-document
              :to-contain (getf runtime-support :primary-implementation))
      (dolist (entry (getf runtime-support :supported-targets))
        (expect runtime-document :to-contain (getf entry :implementation))
        (expect runtime-document :to-contain (getf entry :status))
        (dolist (platform (getf entry :platforms))
          (expect runtime-document :to-contain platform)))
      (dolist (entry (getf runtime-support :best-effort-targets))
        (expect runtime-document :to-contain (getf entry :implementation))
        (expect runtime-document :to-contain (getf entry :status))
        (dolist (platform (getf entry :platforms))
          (if (string= platform "implementation-dependent")
              (progn
                (expect runtime-document
                        :to-contain
                        "Other Common Lisp implementations may work")
                (expect runtime-document :to-contain "best-effort"))
              (expect runtime-document :to-contain platform))))
      (dolist (feature (getf runtime-support :implementation-specific-features))
        (expect runtime-document
                :to-contain
                (cond ((string= feature "it-isolated subprocess execution")
                       "`it-isolated` subprocess execution")
                      ((string= feature
                                "MOP-dependent metadata and structural assertions")
                       "some MOP-dependent metadata and structural assertions")
                      (t
                       feature))))))

  (it "keeps the governance document aligned with maintainer operations"
    (let* ((metadata (cl-weave/cli::framework-metadata))
           (governance (getf metadata :governance))
           (document (normalize-markdown-text
                      (read-text-file
                       (merge-pathnames #P"docs/governance.md"
                                        (uiop:getcwd)))))
           (contributing (normalize-markdown-text
                          (read-text-file
                           (merge-pathnames #P"CONTRIBUTING.md"
                                            (uiop:getcwd)))))
           (codeowners (read-text-file
                        (merge-pathnames (getf governance :review-ownership)
                                         (uiop:getcwd)))))
      (expect (getf metadata :policy-documents) :to-contain "docs/governance.md")
      (expect (getf governance :policy-document) :to-equal "docs/governance.md")
      (expect (getf governance :review-ownership)
              :to-equal ".github/CODEOWNERS")
      (expect (probe-file (merge-pathnames (getf governance :review-ownership)
                                           (uiop:getcwd)))
              :not :to-be nil)
      (expect codeowners :to-contain "@")
      (expect document :to-contain "# Governance")
      (dolist (path (append (mapcar (lambda (path)
                                      (subseq path (1+ (or (position #\/ path :from-end t)
                                                           -1))))
                                    (getf governance :decision-documents))
                            '("../SECURITY.md"
                              "../.github/CODEOWNERS")))
        (expect document :to-contain path))
      (dolist (phrase '("triaging issues and pull requests against"
                        "support-policy.md"
                        "versioning-policy.md"
                        "machine-readable metadata, release notes, and policy documents in sync"
                        "regression coverage for public-surface changes"
                        "private reporting path"
                        "Maintainers cut releases from the validated default branch state only."
                        "If the active maintainer set changes"
                        "machine-readable metadata in the same patch."
                        "public CLI behavior"
                        "reporter shapes"
                        "exported symbols"))
        (expect document :to-contain phrase))
      (dolist (phrase '("review ownership"
                        "release responsibility"
                        "docs/governance.md"))
        (expect contributing :to-contain phrase))
      (dolist (phrase '("*"
                        "@"))
        (expect codeowners :to-contain phrase))))

  (it "keeps the release-process document synchronized with release metadata"
    (let* ((metadata (cl-weave/cli::framework-metadata))
           (release-process (getf metadata :release-process))
           (document (normalize-markdown-text
                      (read-text-file
                       (merge-pathnames (getf release-process :policy-document)
                                        (uiop:getcwd))))))
      (expect document :to-contain "# Release Process")
      (dolist (item (getf release-process :checklist))
        (expect document :to-contain (normalize-markdown-text item)))
      (dolist (item (getf release-process :contract-sync-requirements))
        (expect document :to-contain (normalize-markdown-text item)))))

  (it "keeps lifecycle metadata synchronized with compatibility policies"
    (let* ((metadata (cl-weave/cli::framework-metadata))
           (lifecycle (getf metadata :lifecycle))
           (support-document (normalize-markdown-text
                              (read-text-file
                               (merge-pathnames (getf lifecycle :support-document)
                                                (uiop:getcwd)))))
           (versioning-document (normalize-markdown-text
                                 (read-text-file
                                  (merge-pathnames (getf lifecycle :versioning-document)
                                                   (uiop:getcwd)))))
           (maintenance-document (normalize-markdown-text
                                  (read-text-file
                                   (merge-pathnames #P"docs/maintenance-policy.md"
                                                    (uiop:getcwd)))))
           (contributing-document (normalize-markdown-text
                                   (read-text-file
                                    (merge-pathnames #P"CONTRIBUTING.md"
                                                     (uiop:getcwd)))))
           (ai-contract (read-text-file
                         (merge-pathnames #P"docs/ai-contract.md"
                                          (uiop:getcwd)))))
      (expect (getf metadata :policy-documents)
              :to-contain (getf lifecycle :support-document))
      (expect (getf metadata :policy-documents)
              :to-contain (getf lifecycle :versioning-document))
      (expect (getf metadata :policy-documents)
              :to-contain "docs/maintenance-policy.md")
      (expect support-document :to-contain "release-process.md")
      (expect support-document :to-contain "versioning-policy.md")
      (expect support-document :to-contain "CONTRIBUTING.md")
      (expect support-document :to-contain "runtime-support.md")
      (expect versioning-document :to-contain (getf lifecycle :stage))
      (expect versioning-document :to-contain "breaking changes")
      (expect versioning-document :to-contain "reporter shape")
      (expect versioning-document :to-contain "release-process.md")
      (expect versioning-document :to-contain "maintenance-policy.md")
      (expect maintenance-document
              :to-contain
              "current development line is the primary support target")
      (expect maintenance-document :to-contain "support boundaries")
      (expect maintenance-document :to-contain "versioning policy")
      (expect maintenance-document :to-contain "CONTRIBUTING.md")
      (expect maintenance-document :to-contain "release-process.md")
      (expect contributing-document
              :to-contain
              (normalize-markdown-text (getf lifecycle :support-document)))
      (expect contributing-document
              :to-contain
              (normalize-markdown-text (getf lifecycle :versioning-document)))
      (expect ai-contract :to-contain "\"lifecycle\": {")
      (expect ai-contract
              :to-contain
              (format nil "\"stage\": \"~A\"" (getf lifecycle :stage)))
      (expect ai-contract
              :to-contain
              (format nil "\"supportedLine\": \"~A\""
                      (getf lifecycle :supported-line)))
      (expect ai-contract
              :to-contain
              (format nil "\"supportDocument\": \"~A\""
                      (getf lifecycle :support-document)))
      (expect ai-contract
              :to-contain
              (format nil "\"versioningDocument\": \"~A\""
                      (getf lifecycle :versioning-document)))
      (expect ai-contract
              :to-contain
              (format nil "\"securityDocument\": \"~A\""
                      (getf lifecycle :security-document))))))
