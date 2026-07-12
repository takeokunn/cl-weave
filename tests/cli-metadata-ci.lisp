(in-package #:cl-weave/tests)

(describe "cli metadata CI"
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
                                  :commands '("custom-command")
                                  :argument "VALUE"
                                  :value-kind :custom-value
                                  :choices '("custom-choice")
                                  :command-choices
                                  '(("custom-command" ("custom-choice")))
                                  :environment '("CUSTOM_ENV")
                                  :description "custom option"))
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
                     (cl-weave/metadata::write-framework-metadata-json
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
      (expect output :not :to-contain "\"aliases\":")
      (expect output :to-contain "\"valueKind\":\"custom-value\"")
      (expect output :to-contain "\"choices\":[\"custom-choice\"]")
      (expect output :to-contain "\"commandChoices\"")
      (expect output :to-contain "\"command\":\"custom-command\"")
      (expect output :to-contain "\"CUSTOM_ENV\"")
      (expect output :to-contain "\"custom option\"")
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
    (let* ((metadata (cl-weave/metadata:framework-metadata))
           (ci (getf metadata :continuous-integration)))
      (expect (getf metadata :schema-version) :to-be 23)
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
    (let* ((metadata (cl-weave/metadata:framework-metadata))
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
           (watch-once-gate (find "watch-once-artifact" gates
                                  :key (lambda (entry) (getf entry :name))
                                  :test #'string=))
           (junit-gate (find "junit-artifact" gates
                             :key (lambda (entry) (getf entry :name))
                             :test #'string=)))
      (expect (getf metadata :schema-version) :to-be 23)
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
      (expect (getf jsonl-gate :command) :to-contain "jsonl")
      (expect (getf jsonl-gate :artifacts)
              :to-contain "cl-weave-events.jsonl")
      (expect watch-once-gate :not :to-be nil)
      (expect (getf watch-once-gate :command)
              :to-equal '("nix" "run" "." "--" "watch" "cl-weave/tests"
                          "--once" "--reporter" "json" "--filter"
                          "filtering > runs only tests matching a path substring"
                          "--output" "cl-weave-watch-once.json"))
      (expect (getf watch-once-gate :timeout-seconds) :to-be 120)
      (expect (getf watch-once-gate :artifacts)
              :to-equal '("cl-weave-watch-once.json"))
      (expect junit-gate :not :to-be nil)
      (expect (getf junit-gate :command) :to-contain "junit")
      (expect (getf junit-gate :artifacts)
              :to-contain "cl-weave-junit.xml")))

  (it "keeps CI workflow contract synchronized with metadata"
    (let* ((metadata (cl-weave/metadata:framework-metadata))
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
    (let* ((metadata (cl-weave/metadata:framework-metadata))
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
    (let* ((metadata (cl-weave/metadata:framework-metadata))
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
    (let* ((metadata (cl-weave/metadata:framework-metadata))
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
      (expect (getf source-channel :run-command)
              :to-equal '("nix" "run" "." "--" "run" "cl-weave/tests"))
      (expect (probe-file #P"scripts/") :to-be nil)
      (expect local-channel :not :to-be nil)
      (expect flake :to-contain "packages = forAllSystems")
      (expect flake :to-contain "apps = forAllSystems")
      (expect flake :to-contain "mainProgram = \"cl-weave\";")
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
    (let* ((metadata (cl-weave/metadata:framework-metadata))
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

)
