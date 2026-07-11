(in-package #:cl-weave/tests)

(defun expect-text-contract (text required &optional forbidden)
  (dolist (fragment required)
    (expect text :to-contain fragment))
  (dolist (fragment forbidden)
    (expect text :not :to-contain fragment)))

(defmacro define-metadata-contract-tests (value &rest required-fragments)
  `(expect-text-contract ,value ',required-fragments))

(defun expect-json-field-contracts-documented (document field-tables)
  (dolist (fields field-tables)
    (dolist (field fields)
      (destructuring-bind (metadata-key json-key writer) field
        (declare (ignore metadata-key writer))
        (expect document :to-contain json-key)))))

(in-package #:cl-weave/tests)

(describe "cli metadata schema contracts"
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

)
