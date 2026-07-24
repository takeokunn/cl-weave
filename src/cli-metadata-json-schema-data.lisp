(in-package #:cl-weave/metadata)

(defparameter *json-cli-option-fields*
  '((:name "name" write-json-string-value)
    (:commands "commands" write-json-string-list)
    (:argument "argument" write-json-nullable-string)
    (:value-kind "valueKind" write-json-string-value metadata-symbol-name)
    (:choices "choices" write-json-string-list)
    (:command-choices "commandChoices" write-json-command-choices)
    (:environment "environment" write-json-string-list)
    (:description "description" write-json-nullable-string)))

(defparameter *json-name-field*
  '((:name "name" write-json-string-value)))

(defparameter *json-kind-field*
  '((:kind "kind" write-json-string-value)))

(defparameter *json-description-field*
  '((:description "description" write-json-nullable-string)))

(defparameter *json-target-field*
  '((:target "target" write-json-string-value)))

(defparameter *json-path-field*
  '((:path "path" write-json-string-value)))

(defparameter *json-purpose-field*
  '((:purpose "purpose" write-json-nullable-string)))

(defparameter *json-scope-field*
  '((:scope "scope" write-json-nullable-string)))

(defparameter *json-status-field*
  '((:status "status" write-json-string-value)))

(defparameter *json-summary-field*
  '((:summary "summary" write-json-string-value)))

(defparameter *json-name-status-summary-fields*
  (append *json-name-field*
          *json-status-field*
          *json-summary-field*))

(define-json-plist-array-writer write-json-cli-options *json-cli-option-fields*)

(define-json-plist-array-schema
    *json-artifact-field-fields*
    write-json-artifact-fields
  (append *json-name-field*
          *json-kind-field*
          '((:required "required" write-json-boolean))
          *json-description-field*))

(define-json-plist-array-schema
    *json-artifact-schema-fields*
    write-json-artifact-schemas
  '((:kind "kind" write-json-string-value)
    (:commands "commands" write-json-string-list)
    (:reporters "reporters" write-json-string-list)
    (:schema-version "schemaVersion" write-json-number)
    (:streaming "streaming" write-json-boolean)
    (:fields "fields" write-json-artifact-fields)))

(define-json-plist-array-schema
    *json-quality-gate-fields*
    write-json-quality-gates
  (append *json-name-field*
          *json-kind-field*
          '((:command "command" write-json-string-list)
            (:timeout-seconds "timeoutSeconds" write-json-number)
            (:artifacts "artifacts" write-json-string-list))
          *json-description-field*))

(define-json-plist-array-schema
    *json-capability-matrix-fields*
    write-json-capability-matrix
  (append *json-name-status-summary-fields*
          '((:public-apis "publicApis" write-json-string-list)
            (:quality-gates "qualityGates" write-json-string-list)
            (:documentation "documentation" write-json-string-list))))

(define-json-plist-array-schema
    *json-named-metadata-fields*
    write-json-named-metadata
  '((:name "name" write-json-string-value metadata-symbol-name)
    (:description "description" write-json-nullable-string)))

(define-json-plist-array-schema
    *json-package-export-fields*
    write-json-package-exports
  (append *json-name-field*
          '((:exports "exports" write-json-string-list))))

(define-json-plist-array-schema
    *json-reference-document-fields*
    write-json-reference-documents
  (append *json-name-field*
          *json-path-field*
          *json-description-field*))

(define-json-plist-array-schema
    *json-distribution-channel-fields*
    write-json-distribution-channels
  (append *json-name-field*
          *json-kind-field*
          '((:install-command "installCommand" write-json-string-list)
            (:run-command "runCommand" write-json-string-list))
          *json-scope-field*
          '((:references "references" write-json-string-list))))

(defparameter *json-name-kind-target-scope-fields*
  (append *json-name-field*
          *json-kind-field*
          *json-target-field*
          *json-scope-field*))

(define-json-plist-array-schema
    *json-support-channel-fields*
    write-json-support-channels
  *json-name-kind-target-scope-fields*)

(define-json-plist-array-schema
    *json-community-health-contact-link-fields*
    write-json-community-health-contact-links
  (append *json-name-field*
          *json-target-field*
          *json-purpose-field*))

(define-json-plist-array-schema
    *json-community-health-fields*
    write-json-community-health
  (append *json-name-field*
          *json-kind-field*
          *json-path-field*
          *json-purpose-field*
          '((:references "references" write-json-string-list)
            (:required-sections "requiredSections" write-json-string-list)
            (:contact-links "contactLinks"
             write-json-community-health-contact-links))))

(define-json-plist-array-schema
    *json-security-contact-fields*
    write-json-security-contacts
  *json-name-kind-target-scope-fields*)

(define-json-plist-object-schema
    *json-lifecycle-fields*
    write-json-lifecycle
  '((:stage "stage" write-json-string-value)
    (:status "status" write-json-string-value)
    (:supported-line "supportedLine" write-json-string-value)
    (:support-document "supportDocument" write-json-string-value)
    (:versioning-document "versioningDocument" write-json-string-value)))

(define-json-plist-object-schema
    *json-governance-fields*
    write-json-governance
  '((:policy-document "policyDocument" write-json-string-value)
    (:review-ownership "reviewOwnership" write-json-string-value)
    (:maintainer-responsibilities "maintainerResponsibilities"
     write-json-string-list)
    (:decision-documents "decisionDocuments" write-json-string-list)
    (:release-authority "releaseAuthority" write-json-string-value)
    (:continuity-expectation "continuityExpectation" write-json-string-value)))

(define-json-plist-array-schema
    *json-runtime-target-fields*
    write-json-runtime-targets
  '((:implementation "implementation" write-json-string-value)
    (:platforms "platforms" write-json-string-list)
    (:status "status" write-json-string-value)))

(define-json-plist-object-schema
    *json-runtime-support-fields*
    write-json-runtime-support
  '((:policy-document "policyDocument" write-json-string-value)
    (:primary-implementation "primaryImplementation" write-json-string-value)
    (:supported-targets "supportedTargets" write-json-runtime-targets)
    (:best-effort-targets "bestEffortTargets" write-json-runtime-targets)
    (:implementation-specific-features "implementationSpecificFeatures"
     write-json-string-list)))

(define-json-plist-object-schema
    *json-release-process-fields*
    write-json-release-process
  '((:policy-document "policyDocument" write-json-string-value)
    (:release-stage "releaseStage" write-json-string-value)
    (:checklist "checklist" write-json-string-list)
    (:contract-sync-requirements "contractSyncRequirements"
     write-json-string-list)))

(define-json-plist-object-schema
    *json-continuous-integration-fields*
    write-json-continuous-integration
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

(define-json-plist-object-schema
    *json-doctor-runtime-fields*
    write-json-doctor-runtime
  '((:lisp-implementation "lispImplementation" write-json-string-value)
    (:lisp-version "lispVersion" write-json-string-value)
    (:machine-instance "machineInstance" write-json-string-value)
    (:machine-type "machineType" write-json-string-value)
    (:machine-version "machineVersion" write-json-string-value)
    (:software-type "softwareType" write-json-string-value)
    (:software-version "softwareVersion" write-json-string-value)
    (:working-directory "workingDirectory" write-json-string-value)))

(define-json-plist-array-schema
    *json-doctor-check-fields*
    write-json-doctor-checks
  *json-name-status-summary-fields*)

(defparameter *json-framework-core-fields*
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
    (:options "options" write-json-cli-options)))

(defparameter *json-framework-documentation-fields*
  '((:policy-documents "policyDocuments" write-json-string-list)
    (:reference-documents "referenceDocuments"
     write-json-reference-documents)))

(defparameter *json-framework-community-fields*
  '((:distribution-channels "distributionChannels"
     write-json-distribution-channels)
    (:support-channels "supportChannels" write-json-support-channels)
    (:community-health "communityHealth" write-json-community-health)
    (:security-contacts "securityContacts" write-json-security-contacts)))

(defparameter *json-framework-maintenance-fields*
  '((:lifecycle "lifecycle" write-json-lifecycle)
    (:governance "governance" write-json-governance)
    (:runtime-support "runtimeSupport" write-json-runtime-support)
    (:release-process "releaseProcess" write-json-release-process)
    (:continuous-integration "continuousIntegration"
     write-json-continuous-integration)))

(defparameter *json-framework-ecosystem-fields*
  '((:package-exports "packageExports" write-json-package-exports)
    (:matchers "matchers" write-json-named-metadata)
    (:mutation-operators "mutationOperators" write-json-named-metadata)))

(define-json-plist-object-endpoint
    *doctor-report-json-fields*
    write-doctor-report-json-field
    write-doctor-report-json
    report
  '((:schema-version "schemaVersion" write-json-number)
    (:kind "kind" write-json-string-value)
    (:status "status" write-json-string-value)
    (:version "version" write-json-string-value)
    (:runtime "runtime" write-json-doctor-runtime)
    (:checks "checks" write-json-doctor-checks)))

(define-json-plist-object-endpoint
    *framework-metadata-json-fields*
    write-framework-metadata-json-field
    write-framework-metadata-json
    metadata
  (append *json-framework-core-fields*
          *json-framework-documentation-fields*
          *json-framework-community-fields*
          *json-framework-maintenance-fields*
          *json-framework-ecosystem-fields*))
