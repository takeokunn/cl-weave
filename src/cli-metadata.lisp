(in-package #:cl-weave/cli)

(declaim
 (special *metadata-cli-options*
          *metadata-extra-environment-variables*
          *metadata-commands*
          *metadata-quality-gates*
          *metadata-capabilities*
          *metadata-vitest-aliases*))

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

(defun package-export-metadata (package-designator)
  (let ((package (or (find-package package-designator)
                     (error 'cli-error
                            :message (format nil "Unknown metadata package: ~A"
                                             package-designator)))))
    (list :name (string-downcase (package-name package))
          :exports
          (sort (loop for symbol being the external-symbols of package
                      collect (string-downcase (symbol-name symbol)))
                #'string<))))

(defun framework-metadata ()
  (list
   :kind "cl-weave-metadata"
   :schema-version 5
   :version (cli-version)
   :commands *metadata-commands*
   :reporters (metadata-run-reporters)
   :list-reporters (metadata-list-reporters)
   :artifact-schemas (cl-weave:reporter-artifact-schemas)
   :quality-gates *metadata-quality-gates*
   :capabilities *metadata-capabilities*
   :environment (metadata-environment-variables)
   :options (metadata-cli-options)
   :vitest-aliases
   (loop for (alias . canonical) in *metadata-vitest-aliases*
         collect (list :alias alias :canonical canonical))
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

(defparameter *json-alias-fields*
  '((:alias "alias" write-json-string-value)
    (:canonical "canonical" write-json-string-value)))

(defun write-json-aliases (aliases stream)
  (write-json-plist-array aliases *json-alias-fields* stream))

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

(defparameter *framework-metadata-json-fields*
  '((:schema-version "schemaVersion" write-json-number)
    (:kind "kind" write-json-string-value)
    (:version "version" write-json-string-value)
    (:commands "commands" write-json-string-list)
    (:reporters "reporters" write-json-string-list)
    (:list-reporters "listReporters" write-json-string-list)
    (:artifact-schemas "artifactSchemas" write-json-artifact-schemas)
    (:quality-gates "qualityGates" write-json-quality-gates)
    (:capabilities "capabilities" write-json-string-list)
    (:environment "environment" write-json-string-list)
    (:options "options" write-json-cli-options)
    (:vitest-aliases "vitestAliases" write-json-aliases)
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
