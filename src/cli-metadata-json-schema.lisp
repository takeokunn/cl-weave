(in-package #:cl-weave/cli)

(defparameter *json-cli-option-fields*
  '((:name "name" write-json-string-value)
    (:commands "commands" write-json-string-list)
    (:argument "argument" write-json-nullable-string)
    (:value-kind "valueKind" write-json-string-value metadata-symbol-name)
    (:choices "choices" write-json-string-list)
    (:command-choices "commandChoices" write-json-command-choices)
    (:environment "environment" write-json-string-list)
    (:description "description" write-json-nullable-string)))

(defun write-json-cli-options (options stream)
  (write-json-plist-array options *json-cli-option-fields* stream))

(defun write-json-boolean (value stream)
  (write-string (if value "true" "false") stream))

(defparameter *json-artifact-field-fields*
  '((:name "name" write-json-string-value)
    (:kind "kind" write-json-string-value)
    (:required "required" write-json-boolean)
    (:description "description" write-json-nullable-string)))

(defun write-json-artifact-fields (fields stream)
  (write-json-plist-array fields *json-artifact-field-fields* stream))

(defparameter *json-artifact-schema-fields*
  '((:kind "kind" write-json-string-value)
    (:commands "commands" write-json-string-list)
    (:reporters "reporters" write-json-string-list)
    (:schema-version "schemaVersion" write-json-number)
    (:streaming "streaming" write-json-boolean)
    (:fields "fields" write-json-artifact-fields)))

(defun write-json-artifact-schemas (schemas stream)
  (write-json-plist-array schemas *json-artifact-schema-fields* stream))

(defparameter *json-quality-gate-fields*
  '((:name "name" write-json-string-value)
    (:kind "kind" write-json-string-value)
    (:command "command" write-json-string-list)
    (:timeout-seconds "timeoutSeconds" write-json-number)
    (:artifacts "artifacts" write-json-string-list)
    (:description "description" write-json-nullable-string)))

(defun write-json-quality-gates (gates stream)
  (write-json-plist-array gates *json-quality-gate-fields* stream))

(defparameter *json-capability-matrix-fields*
  '((:name "name" write-json-string-value)
    (:status "status" write-json-string-value)
    (:summary "summary" write-json-string-value)
    (:public-apis "publicApis" write-json-string-list)
    (:quality-gates "qualityGates" write-json-string-list)
    (:documentation "documentation" write-json-string-list)))

(defun write-json-capability-matrix (entries stream)
  (write-json-plist-array entries *json-capability-matrix-fields* stream))

(defparameter *json-named-metadata-fields*
  '((:name "name" write-json-string-value metadata-symbol-name)
    (:description "description" write-json-nullable-string)))

(defun write-json-named-metadata (entries stream)
  (write-json-plist-array entries *json-named-metadata-fields* stream))

(defparameter *json-package-export-fields*
  '((:name "name" write-json-string-value)
    (:exports "exports" write-json-string-list)))

(defun write-json-package-exports (entries stream)
  (write-json-plist-array entries *json-package-export-fields* stream))

(defparameter *json-reference-document-fields*
  '((:name "name" write-json-string-value)
    (:path "path" write-json-string-value)
    (:description "description" write-json-nullable-string)))

(defun write-json-reference-documents (entries stream)
  (write-json-plist-array entries *json-reference-document-fields* stream))

(defparameter *json-citation-author-fields*
  '((:name "name" write-json-string-value)))

(defun write-json-citation-authors (entries stream)
  (write-json-plist-array entries *json-citation-author-fields* stream))

(defparameter *json-citation-fields*
  '((:cff-version "cffVersion" write-json-string-value)
    (:message "message" write-json-string-value)
    (:title "title" write-json-string-value)
    (:authors "authors" write-json-citation-authors)
    (:license "license" write-json-string-value)
    (:repository-code "repositoryCode" write-json-string-value)
    (:url "url" write-json-string-value)
    (:version "version" write-json-string-value)
    (:preferred-citation-path "preferredCitationPath"
     write-json-string-value)))

(defun write-json-citation (entry stream)
  (write-json-plist-object entry *json-citation-fields* stream))

(defparameter *json-distribution-channel-fields*
  '((:name "name" write-json-string-value)
    (:kind "kind" write-json-string-value)
    (:install-command "installCommand" write-json-string-list)
    (:run-command "runCommand" write-json-string-list)
    (:scope "scope" write-json-nullable-string)
    (:references "references" write-json-string-list)))

(defun write-json-distribution-channels (entries stream)
  (write-json-plist-array entries *json-distribution-channel-fields* stream))

(defparameter *json-support-channel-fields*
  '((:name "name" write-json-string-value)
    (:kind "kind" write-json-string-value)
    (:target "target" write-json-string-value)
    (:scope "scope" write-json-nullable-string)))

(defun write-json-support-channels (entries stream)
  (write-json-plist-array entries *json-support-channel-fields* stream))

(defparameter *json-community-health-contact-link-fields*
  '((:name "name" write-json-string-value)
    (:target "target" write-json-string-value)
    (:purpose "purpose" write-json-nullable-string)))

(defun write-json-community-health-contact-links (entries stream)
  (write-json-plist-array entries *json-community-health-contact-link-fields*
                          stream))

(defparameter *json-community-health-fields*
  '((:name "name" write-json-string-value)
    (:kind "kind" write-json-string-value)
    (:path "path" write-json-string-value)
    (:purpose "purpose" write-json-nullable-string)
    (:references "references" write-json-string-list)
    (:required-sections "requiredSections" write-json-string-list)
    (:contact-links "contactLinks"
     write-json-community-health-contact-links)))

(defun write-json-community-health (entries stream)
  (write-json-plist-array entries *json-community-health-fields* stream))

(defparameter *json-security-contact-fields*
  '((:name "name" write-json-string-value)
    (:kind "kind" write-json-string-value)
    (:target "target" write-json-string-value)
    (:scope "scope" write-json-nullable-string)))

(defun write-json-security-contacts (entries stream)
  (write-json-plist-array entries *json-security-contact-fields* stream))

(defparameter *json-lifecycle-fields*
  '((:stage "stage" write-json-string-value)
    (:status "status" write-json-string-value)
    (:supported-line "supportedLine" write-json-string-value)
    (:support-document "supportDocument" write-json-string-value)
    (:versioning-document "versioningDocument" write-json-string-value)
    (:security-document "securityDocument" write-json-string-value)))

(defun write-json-lifecycle (entry stream)
  (write-json-plist-object entry *json-lifecycle-fields* stream))

(defparameter *json-governance-fields*
  '((:policy-document "policyDocument" write-json-string-value)
    (:review-ownership "reviewOwnership" write-json-string-value)
    (:maintainer-responsibilities "maintainerResponsibilities"
     write-json-string-list)
    (:decision-documents "decisionDocuments" write-json-string-list)
    (:release-authority "releaseAuthority" write-json-string-value)
    (:continuity-expectation "continuityExpectation" write-json-string-value)))

(defun write-json-governance (entry stream)
  (write-json-plist-object entry *json-governance-fields* stream))

(defparameter *json-runtime-target-fields*
  '((:implementation "implementation" write-json-string-value)
    (:platforms "platforms" write-json-string-list)
    (:status "status" write-json-string-value)))

(defun write-json-runtime-targets (entries stream)
  (write-json-plist-array entries *json-runtime-target-fields* stream))

(defparameter *json-runtime-support-fields*
  '((:policy-document "policyDocument" write-json-string-value)
    (:primary-implementation "primaryImplementation" write-json-string-value)
    (:supported-targets "supportedTargets" write-json-runtime-targets)
    (:best-effort-targets "bestEffortTargets" write-json-runtime-targets)
    (:implementation-specific-features "implementationSpecificFeatures"
     write-json-string-list)))

(defun write-json-runtime-support (entry stream)
  (write-json-plist-object entry *json-runtime-support-fields* stream))

(defparameter *json-release-process-fields*
  '((:policy-document "policyDocument" write-json-string-value)
    (:release-stage "releaseStage" write-json-string-value)
    (:checklist "checklist" write-json-string-list)
    (:contract-sync-requirements "contractSyncRequirements"
     write-json-string-list)))

(defun write-json-release-process (entry stream)
  (write-json-plist-object entry *json-release-process-fields* stream))

(defparameter *json-continuous-integration-fields*
  '((:policy-document "policyDocument" write-json-string-value)
    (:provider "provider" write-json-string-value)
    (:workflow-path "workflowPath" write-json-string-value)
    (:job-name "jobName" write-json-string-value)
    (:triggers "triggers" write-json-string-list)
    (:systems "systems" write-json-string-list)
    (:artifact-bundle "artifactBundle" write-json-string-value)
    (:cache-provider "cacheProvider" write-json-string-value)
    (:cache-modes "cacheModes" write-json-string-list)
    (:quality-gate-source "qualityGateSource" write-json-string-value)))

(defun write-json-continuous-integration (entry stream)
  (write-json-plist-object entry *json-continuous-integration-fields* stream))

(defparameter *json-doctor-runtime-fields*
  '((:lisp-implementation "lispImplementation" write-json-string-value)
    (:lisp-version "lispVersion" write-json-string-value)
    (:machine-instance "machineInstance" write-json-string-value)
    (:machine-type "machineType" write-json-string-value)
    (:machine-version "machineVersion" write-json-string-value)
    (:software-type "softwareType" write-json-string-value)
    (:software-version "softwareVersion" write-json-string-value)
    (:working-directory "workingDirectory" write-json-string-value)))

(defun write-json-doctor-runtime (entry stream)
  (write-json-plist-object entry *json-doctor-runtime-fields* stream))

(defparameter *json-doctor-check-fields*
  '((:name "name" write-json-string-value)
    (:status "status" write-json-string-value)
    (:summary "summary" write-json-string-value)))

(defun write-json-doctor-checks (entries stream)
  (write-json-plist-array entries *json-doctor-check-fields* stream))

(defparameter *doctor-report-json-fields*
  '((:schema-version "schemaVersion" write-json-number)
    (:kind "kind" write-json-string-value)
    (:status "status" write-json-string-value)
    (:version "version" write-json-string-value)
    (:runtime "runtime" write-json-doctor-runtime)
    (:checks "checks" write-json-doctor-checks)))

(defun write-doctor-report-json-field (field report stream)
  (destructuring-bind (report-key json-key writer) field
    (write-json-key json-key stream)
    (funcall writer (getf report report-key) stream)))

(defun write-doctor-report-json (report stream)
  (write-char #\{ stream)
  (loop for field in *doctor-report-json-fields*
        for firstp = t then nil
        unless firstp do (write-char #\, stream)
        do (write-doctor-report-json-field field report stream))
  (write-char #\} stream)
  (terpri stream))

(defparameter *framework-metadata-json-fields*
  '((:schema-version "schemaVersion" write-json-number)
    (:kind "kind" write-json-string-value)
    (:version "version" write-json-string-value)
    (:homepage "homepage" write-json-nullable-string)
    (:bug-tracker "bugTracker" write-json-nullable-string)
    (:license "license" write-json-nullable-string)
    (:commands "commands" write-json-string-list)
    (:reporters "reporters" write-json-string-list)
    (:list-reporters "listReporters" write-json-string-list)
    (:artifact-schemas "artifactSchemas" write-json-artifact-schemas)
    (:quality-gates "qualityGates" write-json-quality-gates)
    (:capabilities "capabilities" write-json-string-list)
    (:capability-matrix "capabilityMatrix" write-json-capability-matrix)
    (:environment "environment" write-json-string-list)
    (:options "options" write-json-cli-options)
    (:policy-documents "policyDocuments" write-json-string-list)
    (:reference-documents "referenceDocuments" write-json-reference-documents)
    (:citation "citation" write-json-citation)
    (:distribution-channels "distributionChannels"
     write-json-distribution-channels)
    (:support-channels "supportChannels" write-json-support-channels)
    (:community-health "communityHealth" write-json-community-health)
    (:security-contacts "securityContacts" write-json-security-contacts)
    (:lifecycle "lifecycle" write-json-lifecycle)
    (:governance "governance" write-json-governance)
    (:runtime-support "runtimeSupport" write-json-runtime-support)
    (:release-process "releaseProcess" write-json-release-process)
    (:continuous-integration "continuousIntegration"
     write-json-continuous-integration)
    (:package-exports "packageExports" write-json-package-exports)
    (:matchers "matchers" write-json-named-metadata)
    (:mutation-operators "mutationOperators" write-json-named-metadata)))

(defun write-framework-metadata-json-field (field metadata stream)
  (destructuring-bind (metadata-key json-key writer) field
    (write-json-key json-key stream)
    (funcall writer (getf metadata metadata-key) stream)))

(defun write-framework-metadata-json (metadata stream)
  (write-char #\{ stream)
  (loop for field in *framework-metadata-json-fields*
        for firstp = t then nil
        unless firstp do (write-char #\, stream)
        do (write-framework-metadata-json-field field metadata stream))
  (write-char #\} stream)
  (terpri stream))

