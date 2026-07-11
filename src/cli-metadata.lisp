(in-package #:cl-weave/cli)

(declaim
 (special *metadata-cli-options*
          *metadata-extra-environment-variables*
          *metadata-commands*
          *metadata-quality-gates*
          *metadata-capabilities*
          *metadata-capability-matrix*
          *metadata-policy-documents*
          *metadata-reference-documents*
          *metadata-citation*
          *metadata-distribution-channels*
          *metadata-support-channels*
          *metadata-community-health*
          *metadata-security-contacts*
          *metadata-lifecycle*
          *metadata-governance*
          *metadata-runtime-support*
          *metadata-release-process*
          *metadata-continuous-integration*))

(defun reporter-keyword-names (reporters)
  (mapcar (lambda (reporter)
            (string-downcase (symbol-name reporter)))
          reporters))

(defun metadata-run-reporters ()
  (reporter-keyword-names cl-weave::*run-reporters*))

(defun metadata-list-reporters ()
  (reporter-keyword-names cl-weave::*list-reporters*))

(defun metadata-output-reporters ()
  '("json" "sexp"))

(defun metadata-reporter-command-choices ()
  (let ((run-reporters (metadata-run-reporters))
        (list-reporters (metadata-list-reporters)))
    `(("run" ,run-reporters)
      ("watch" ,run-reporters)
      ("list" ,list-reporters)
      ("doctor" ,(metadata-output-reporters))
      ("metadata" ,(metadata-output-reporters)))))


(defun cli-option-usage-name (name argument)
  (if argument
      (format nil "~A ~A" name argument)
      name))

(defun cli-option-usage-label (entry)
  (format nil "~{~A~^, ~}"
          (loop for name in (cons (getf entry :name) (getf entry :aliases))
                collect (cli-option-usage-name name (getf entry :argument)))))

(defun cli-option-usage-lines (entry)
  (let* ((label (format nil "  ~A" (cli-option-usage-label entry)))
         (description (getf entry :description))
         (description-column 30))
    (if (< (length label) description-column)
        (list (format nil "~A~VT~A" label description-column description))
        (list label
              (format nil "~VT~A" description-column description)))))

(defun materialized-metadata-cli-option (entry)
  (let ((copy (copy-list entry)))
    (when (eq (getf copy :choices) :run-reporters)
      (setf (getf copy :choices) (metadata-run-reporters)))
    (when (eq (getf copy :command-choices) :reporter-command-choices)
      (setf (getf copy :command-choices) (metadata-reporter-command-choices)))
    copy))

(defun metadata-cli-options ()
  (mapcar #'materialized-metadata-cli-option *metadata-cli-options*))

(defun metadata-environment-variables ()
  (sort (remove-duplicates
         (append *metadata-extra-environment-variables*
                 (loop for entry in (metadata-cli-options)
                       append (getf entry :environment)))
         :test #'string=)
        #'string<))

(defun cli-version ()
  (or (ignore-errors
        (let ((system (asdf:find-system "cl-weave" nil)))
          (and system (asdf:component-version system))))
      "unknown"))

(defun metadata-system ()
  (ignore-errors (asdf:find-system "cl-weave" nil)))

(defun framework-homepage ()
  (let ((system (metadata-system)))
    (and system (asdf:system-homepage system))))

(defun framework-bug-tracker ()
  (let ((system (metadata-system)))
    (and system (asdf:system-bug-tracker system))))

(defun framework-license ()
  (let ((system (metadata-system)))
    (and system (asdf:system-license system))))

(defun package-export-metadata (package-designator)
  (let ((package (or (find-package package-designator)
                     (error 'cli-error
                            :message (format nil "Unknown metadata package: ~A"
                                             package-designator)))))
    (list :name (string-downcase (package-name package))
          :exports
          (sort (loop for symbol being the external-symbols of package
                      collect (symbol-name symbol))
                #'string<))))

(defun metadata-policy-documents ()
  *metadata-policy-documents*)

(defun metadata-reference-documents ()
  *metadata-reference-documents*)

(defun metadata-citation ()
  *metadata-citation*)

(defun metadata-distribution-channels ()
  *metadata-distribution-channels*)

(defun metadata-support-channels ()
  *metadata-support-channels*)

(defun metadata-community-health ()
  *metadata-community-health*)

(defun metadata-security-contacts ()
  *metadata-security-contacts*)

(defun metadata-lifecycle ()
  *metadata-lifecycle*)

(defun metadata-governance ()
  *metadata-governance*)

(defun metadata-runtime-support ()
  *metadata-runtime-support*)

(defun metadata-release-process ()
  *metadata-release-process*)

(defun metadata-continuous-integration ()
  *metadata-continuous-integration*)

(defun framework-metadata ()
  (list
   :kind "cl-weave-metadata"
   :schema-version 22
   :homepage (framework-homepage)
   :bug-tracker (framework-bug-tracker)
   :license (framework-license)
   :version (cli-version)
   :commands *metadata-commands*
   :reporters (metadata-run-reporters)
   :list-reporters (metadata-list-reporters)
   :artifact-schemas (cl-weave:reporter-artifact-schemas)
   :quality-gates *metadata-quality-gates*
   :capabilities *metadata-capabilities*
   :capability-matrix *metadata-capability-matrix*
   :environment (metadata-environment-variables)
   :options (metadata-cli-options)
   :policy-documents (metadata-policy-documents)
   :reference-documents (metadata-reference-documents)
   :citation (metadata-citation)
   :distribution-channels (metadata-distribution-channels)
   :support-channels (metadata-support-channels)
   :community-health (metadata-community-health)
   :security-contacts (metadata-security-contacts)
   :lifecycle (metadata-lifecycle)
   :governance (metadata-governance)
   :runtime-support (metadata-runtime-support)
   :release-process (metadata-release-process)
   :continuous-integration (metadata-continuous-integration)
   :package-exports (list (package-export-metadata :cl-weave)
                          (package-export-metadata :cl-weave/cli))
   :matchers (cl-weave:list-matchers)
   :mutation-operators (cl-weave:list-mutation-operators)))

(defun metadata-reporter (options)
  (let ((reporter (cli-options-reporter options)))
    (cond
      ((eq reporter :spec) :json)
      ((member reporter '(:json :sexp)) reporter)
      (t (error 'cli-error
                :message "cl-weave: metadata mode supports json and sexp reporters.")))))

(defun doctor-reporter (options)
  (let ((reporter (cli-options-reporter options)))
    (cond
      ((eq reporter :spec) :json)
      ((member reporter '(:json :sexp)) reporter)
      (t (error 'cli-error
                :message "cl-weave: doctor mode supports json and sexp reporters.")))))

(defun doctor-check-status (entry)
  (getf entry :status))

(defun doctor-overall-status (checks)
  (cond
    ((find :fail checks :key #'doctor-check-status) :fail)
    ((find :warn checks :key #'doctor-check-status) :warn)
    (t :pass)))

(defun doctor-check (name status summary)
  (list :name name
        :status status
        :summary summary))

(defun doctor-runtime-metadata ()
  (list :lisp-implementation (lisp-implementation-type)
        :lisp-version (lisp-implementation-version)
        :machine-instance (machine-instance)
        :machine-type (machine-type)
        :machine-version (machine-version)
        :software-type (software-type)
        :software-version (software-version)
        :working-directory (uiop:getcwd)))

(defun visible-asdf-system-p (system-name)
  (and system-name
       (not (null (ignore-errors (asdf:find-system system-name nil))))))

(defun doctor-requested-system (options)
  (first (cli-options-systems options)))

(defun doctor-checks (options)
  (let* ((cwd (uiop:getcwd))
         (asd-files (directory-asd-files cwd))
         (metadata (framework-metadata))
         (requested-system (doctor-requested-system options))
         (output-file (cli-options-output-file options)))
    (list
     (doctor-check
      "runtime"
      :pass
      (format nil "~A ~A on ~A"
              (lisp-implementation-type)
              (lisp-implementation-version)
              (software-type)))
     (doctor-check
      "cl-weave-system"
      (if (visible-asdf-system-p "cl-weave") :pass :fail)
      (if (visible-asdf-system-p "cl-weave")
          "ASDF can resolve the bundled cl-weave system."
          "ASDF cannot resolve the bundled cl-weave system."))
     (doctor-check
      "requested-system"
      (cond
        ((null requested-system) :pass)
        ((visible-asdf-system-p requested-system) :pass)
        (t :fail))
      (cond
        ((null requested-system)
         "No ASDF system was requested; doctor is running in runtime-only mode.")
        ((visible-asdf-system-p requested-system)
         (format nil "ASDF can resolve the requested system ~A."
                 requested-system))
        (t
         (format nil "ASDF cannot resolve the requested system ~A."
                 requested-system))))
     (doctor-check
      "workspace-asd-files"
      (if asd-files :pass :warn)
      (if asd-files
          (format nil "Found ~D .asd file(s) in the current working directory."
                  (length asd-files))
          "No .asd files were found in the current working directory."))
     (doctor-check
      "output-target"
      :pass
      (if output-file
          (format nil "Doctor output is configured to write to ~A."
                  output-file)
          "Doctor output is configured to write to standard output."))
     (doctor-check
      "command-metadata"
      (if (member "doctor" (getf metadata :commands) :test #'string=) :pass :fail)
      (if (member "doctor" (getf metadata :commands) :test #'string=)
          "Framework metadata advertises the doctor command."
          "Framework metadata does not advertise the doctor command.")))))

(defun doctor-report (&optional (options (make-cli-options)))
  (let* ((checks (doctor-checks options))
         (status (doctor-overall-status checks)))
    (list :schema-version 1
          :kind "doctor-report"
          :status (metadata-symbol-name status)
          :version (cli-version)
          :runtime (doctor-runtime-metadata)
          :checks
          (loop for entry in checks
                collect (list :name (getf entry :name)
                              :status (metadata-symbol-name
                                       (getf entry :status))
                              :summary (getf entry :summary))))))

(defun metadata-symbol-name (symbol)
  (string-downcase (symbol-name symbol)))

(defun write-json-key (key stream)
  (cl-weave::write-json-string key stream)
  (write-char #\: stream))

(defun write-json-number (value stream)
  (write value :stream stream))

(defun write-json-string-value (value stream)
  (cl-weave::write-json-string value stream))

(defun write-json-array (values element-writer stream)
  (write-char #\[ stream)
  (loop for value in values
        for firstp = t then nil
        unless firstp do (write-char #\, stream)
        do (funcall element-writer value stream))
  (write-char #\] stream))

(defun write-json-object-fields (fields stream)
  (write-char #\{ stream)
  (loop for field in fields
        for firstp = t then nil
        unless firstp do (write-char #\, stream)
        do (destructuring-bind (key writer) field
             (write-json-key key stream)
             (funcall writer stream)))
  (write-char #\} stream))

(defmacro json-field (key value-form writer stream)
  `(list ,key
         (lambda (,stream)
           (,writer ,value-form ,stream))))

(defun call-json-helper (helper value stream)
  (funcall (etypecase helper
             (function helper)
             (symbol (symbol-function helper)))
           value
           stream))

(defun transform-json-value (transformer value)
  (if transformer
      (funcall (etypecase transformer
                 (function transformer)
                 (symbol (symbol-function transformer)))
               value)
      value))

(defun plist-json-field-entry (plist field-spec)
  (destructuring-bind (plist-key json-key writer &optional transformer) field-spec
    (let ((value (transform-json-value transformer (getf plist plist-key))))
      (list json-key
            (lambda (stream)
              (call-json-helper writer value stream))))))

(defun write-json-plist-object (plist field-specs stream)
  (write-json-object-fields
   (mapcar (lambda (field-spec)
             (plist-json-field-entry plist field-spec))
           field-specs)
   stream))

(defun write-json-plist-array (values field-specs stream)
  (write-json-array
   values
   (lambda (value item-stream)
     (write-json-plist-object value field-specs item-stream))
   stream))

(defun write-json-string-list (values stream)
  (write-json-array values #'write-json-string-value stream))

(defun write-json-nullable-string (value stream)
  (if value
      (cl-weave::write-json-string value stream)
      (write-string "null" stream)))

(defun write-json-command-choices (command-choices stream)
  (write-json-array
   command-choices
   (lambda (entry item-stream)
     (destructuring-bind (command choices) entry
       (write-json-object-fields
        (list (json-field "command" command write-json-string-value item-stream)
              (json-field "choices" choices write-json-string-list item-stream))
        item-stream)))
   stream))

(defparameter *json-cli-option-fields*
  '((:name "name" write-json-string-value)
    (:aliases "aliases" write-json-string-list)
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

(defun report-framework-metadata (options stream)
  (let ((metadata (framework-metadata)))
    (case (metadata-reporter options)
      (:json (write-framework-metadata-json metadata stream))
      (:sexp (write metadata :stream stream :pretty t)
             (terpri stream)))))

(defun report-doctor (options stream)
  (let ((report (doctor-report options)))
    (case (doctor-reporter options)
      (:json (write-doctor-report-json report stream))
      (:sexp (write report :stream stream :pretty t)
             (terpri stream)))))
