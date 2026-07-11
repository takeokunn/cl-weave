(in-package #:cl-weave)

(defun event-duration-seconds (event)
  (/ (test-event-elapsed-internal-time event)
     internal-time-units-per-second))

(defun event-duration-ms (event)
  (* (event-duration-seconds event) 1000))

(defun status-marker (status)
  (ecase status
    (:pass "PASS")
    (:skip "SKIP")
    (:todo "TODO")
    (:fail "FAIL")
    (:error "ERROR")))

(defun path-string (path)
  (format nil "~{~A~^ > ~}" path))

(defun dotted-path-string (path)
  (if path
      (format nil "~{~A~^.~}" path)
      "cl-weave"))

(defun xml-escaped-string (value)
  (with-output-to-string (stream)
    (loop for char across (princ-to-string value)
          for code = (char-code char)
          do (case code
               (60 (write-string "&lt;" stream))
               (62 (write-string "&gt;" stream))
               (38 (write-string "&amp;" stream))
               (34 (write-string "&quot;" stream))
               (39 (write-string "&apos;" stream))
               (t
                (if (and (< code 32)
                         (not (member code '(9 10 13))))
                    (write-char #\? stream)
                    (write-char char stream)))))))

(defparameter *result-summary-field-specs*
  '((:status :pass :plist-key :passed :json-key "passed")
    (:status :skip :plist-key :skipped :json-key "skipped")
    (:status :todo :plist-key :todos :json-key "todos")
    (:status :fail :plist-key :failed :json-key "failed")
    (:status :error :plist-key :errored :json-key "errored")))

(defparameter *plan-summary-field-specs*
  '((:status :run :plist-key :runnable :json-key "runnable")
    (:status :skip :plist-key :skipped :json-key "skipped")
    (:status :todo :plist-key :todos :json-key "todos")))

(defmacro define-reporter-artifact-schemas (&body schemas)
  "Define reporter schema data after validating its declarative contract."
  (labels ((property-present-p (plist property)
             (loop for (key) on plist by #'cddr
                   thereis (eq key property)))
           (require-property (plist property context)
             (unless (property-present-p plist property)
               (error "~A must declare ~S." context property))
             (getf plist property))
           (ensure-unique (values context)
             (let ((duplicate (find-if (lambda (value)
                                         (> (count value values :test #'equal) 1))
                                       values)))
               (when duplicate
                 (error "~A contains duplicate ~S." context duplicate)))))
    (ensure-unique (mapcar (lambda (schema)
                             (require-property schema :kind "Reporter schema"))
                           schemas)
                   "Reporter schema kinds")
    (dolist (schema schemas)
      (let ((kind (getf schema :kind)))
        (dolist (property '(:commands :reporters :schema-version
                            :streaming :fields))
          (require-property schema property
                            (format nil "Reporter schema ~S" kind)))
        (let ((fields (getf schema :fields)))
          (ensure-unique
           (mapcar (lambda (field)
                     (require-property field :name
                                       (format nil "Field in schema ~S" kind)))
                   fields)
           (format nil "Field names in reporter schema ~S" kind))
          (dolist (field fields)
            (require-property field :kind
                              (format nil "Field ~S in schema ~S"
                                      (getf field :name) kind))
            (require-property field :required
                              (format nil "Field ~S in schema ~S"
                                      (getf field :name) kind)))))))
  `(defparameter *reporter-artifact-schemas* ',schemas))

(define-reporter-artifact-schemas
  (:kind "test-results"
     :commands ("run" "watch")
     :reporters ("json")
     :schema-version 6
     :streaming nil
     :fields ((:name "schemaVersion" :kind "integer" :required t
               :description "Artifact-local schema version.")
              (:name "kind" :kind "string" :required t
               :description "Artifact discriminator.")
              (:name "events" :kind "array" :required t
               :description "Ordered test events.")
              (:name "passed" :kind "integer" :required t)
              (:name "skipped" :kind "integer" :required t)
              (:name "todos" :kind "integer" :required t)
              (:name "failed" :kind "integer" :required t)
              (:name "errored" :kind "integer" :required t)
              (:name "failedPaths" :kind "array" :required t)
              (:name "erroredPaths" :kind "array" :required t)))
    (:kind "cl-weave/results"
     :commands ("run" "watch")
     :reporters ("sexp")
     :schema-version 4
     :streaming nil
     :fields ((:name "schema-version" :kind "integer" :required t)
              (:name "events" :kind "list" :required t)
              (:name "passed" :kind "integer" :required t)
              (:name "skipped" :kind "integer" :required t)
              (:name "todos" :kind "integer" :required t)
              (:name "failed" :kind "integer" :required t)
              (:name "errored" :kind "integer" :required t)
              (:name "failed-paths" :kind "list" :required t)
              (:name "errored-paths" :kind "list" :required t)))
    (:kind "test-results-start"
     :commands ("run" "watch")
     :reporters ("jsonl")
     :schema-version 1
     :streaming t
     :fields ((:name "schemaVersion" :kind "integer" :required t
               :description "Artifact-local schema version.")
              (:name "kind" :kind "string" :required t
               :description "Artifact discriminator.")
              (:name "total" :kind "integer" :required t
               :description "Number of planned tests.")))
    (:kind "test-event"
     :commands ("run" "watch")
     :reporters ("jsonl")
     :schema-version 3
     :streaming t
     :fields ((:name "schemaVersion" :kind "integer" :required t
               :description "Artifact-local schema version.")
              (:name "kind" :kind "string" :required t
               :description "Artifact discriminator.")
              (:name "event" :kind "object" :required t
               :description "Single test event payload.")))
    (:kind "test-results-summary"
     :commands ("run" "watch")
     :reporters ("jsonl")
     :schema-version 1
     :streaming t
     :fields ((:name "schemaVersion" :kind "integer" :required t
               :description "Artifact-local schema version.")
              (:name "kind" :kind "string" :required t
               :description "Artifact discriminator.")
              (:name "passed" :kind "integer" :required t
               :description "Passed test count.")
              (:name "skipped" :kind "integer" :required t
               :description "Skipped test count.")
              (:name "todos" :kind "integer" :required t
               :description "Todo test count.")
              (:name "failed" :kind "integer" :required t
               :description "Failed assertion count.")
              (:name "errored" :kind "integer" :required t
               :description "Errored test count.")
              (:name "failedPaths" :kind "array" :required t
               :description "Vitest-style paths with failed assertions.")
              (:name "erroredPaths" :kind "array" :required t
               :description "Vitest-style paths with unexpected errors.")))
    (:kind "test-plan"
     :commands ("list")
     :reporters ("json" "sexp")
     :schema-version 3
     :streaming nil
     :fields ((:name "schemaVersion" :kind "integer" :required t
               :description "Artifact-local schema version.")
               (:name "kind" :kind "string" :required t
                :description "Artifact discriminator.")
               (:name "tests" :kind "array" :required t
                :description "Discovered entries using the test-plan-entry test field shape.")
               (:name "summary" :kind "object" :required t
                :description "Aggregated discovery counts.")))
    (:kind "test-plan-start"
     :commands ("list")
     :reporters ("jsonl")
     :schema-version 1
     :streaming t
     :fields ((:name "schemaVersion" :kind "integer" :required t
               :description "Artifact-local schema version.")
              (:name "kind" :kind "string" :required t
               :description "Artifact discriminator.")
              (:name "total" :kind "integer" :required t
               :description "Number of discovered tests.")))
    (:kind "test-plan-entry"
     :commands ("list")
     :reporters ("jsonl")
     :schema-version 2
     :streaming t
     :fields ((:name "schemaVersion" :kind "integer" :required t
               :description "Artifact-local schema version.")
               (:name "kind" :kind "string" :required t
                :description "Artifact discriminator.")
               (:name "test" :kind "object" :required t
                :description "Single test plan entry.")
               (:name "test.status" :kind "string" :required t
                :description "Planned execution status: run, skip, or todo.")
               (:name "test.path" :kind "array" :required t
                :description "Vitest-style hierarchical test path.")
               (:name "test.pathString" :kind "string" :required t
                :description "Human-readable test path joined with >.")
               (:name "test.location" :kind "object" :required t
                :description "Source location object.")
               (:name "test.reason" :kind "string" :required t
                :description "Nullable skip, todo, or expected-failure reason.")
               (:name "test.focused" :kind "boolean" :required t
                :description "Whether the entry was focused.")
               (:name "test.retry" :kind "integer" :required t
                :description "Retry count for the entry.")
               (:name "test.timeoutMs" :kind "integer" :required t
                :description "Nullable per-entry timeout in milliseconds.")
               (:name "test.concurrent" :kind "boolean" :required t
                :description "Whether the entry requested concurrent execution.")))
    (:kind "test-plan-summary"
     :commands ("list")
     :reporters ("jsonl")
     :schema-version 1
     :streaming t
     :fields ((:name "schemaVersion" :kind "integer" :required t
               :description "Artifact-local schema version.")
              (:name "kind" :kind "string" :required t
               :description "Artifact discriminator.")
              (:name "total" :kind "integer" :required t
               :description "Total discovered tests.")
              (:name "runnable" :kind "integer" :required t
               :description "Runnable discovered tests.")
              (:name "skipped" :kind "integer" :required t
               :description "Skipped discovered tests.")
              (:name "todos" :kind "integer" :required t
               :description "Todo discovered tests.")))
    (:kind "doctor-report"
     :commands ("doctor")
     :reporters ("json" "sexp")
     :schema-version 1
     :streaming nil
     :fields ((:name "schemaVersion" :kind "integer" :required t
               :description "Artifact-local schema version.")
              (:name "kind" :kind "string" :required t
               :description "Artifact discriminator.")
              (:name "status" :kind "string" :required t
               :description "Overall diagnostic status.")
              (:name "version" :kind "string" :required t
               :description "Resolved cl-weave CLI version.")
              (:name "runtime" :kind "object" :required t
               :description "Current Lisp and host runtime details.")
              (:name "checks" :kind "array" :required t
               :description "Ordered self-diagnostic checks.")))
    (:kind "mutations"
     :commands ()
     :reporters ("json" "sexp")
     :schema-version 1
     :streaming nil
     :fields ((:name "schemaVersion" :kind "integer" :required t
               :description "Artifact-local schema version.")
              (:name "kind" :kind "string" :required t
               :description "Artifact discriminator.")
              (:name "total" :kind "integer" :required t
               :description "Total generated mutations.")
              (:name "killed" :kind "integer" :required t
               :description "Mutations rejected by the test predicate.")
              (:name "survived" :kind "integer" :required t
               :description "Mutations accepted by the test predicate.")
              (:name "errored" :kind "integer" :required t
               :description "Mutations that raised unexpected conditions.")
              (:name "score" :kind "number" :required t
               :description "Killed-to-total mutation score.")
              (:name "results" :kind "array" :required t
               :description "Per-mutation execution results."))))

(defun reporter-artifact-schemas ()
  "Return structured reporter artifact schema metadata."
  (copy-tree *reporter-artifact-schemas*))

(defun summary-count (items status accessor)
  (count status items :key accessor))

(defun collect-summary-fields (items accessor field-specs)
  (loop for spec in field-specs
        append (list (getf spec :plist-key)
                     (summary-count items (getf spec :status) accessor))))

(defun result-summary (events)
  (append (list :total (length events))
          (collect-summary-fields events #'test-event-status
                                  *result-summary-field-specs*)
          (list :failed-paths (event-path-strings-with-status events :fail)
                :errored-paths (event-path-strings-with-status events :error))))

(defun plan-summary (plan)
  (append (list :total (length plan))
          (collect-summary-fields plan #'test-plan-entry-status
                                  *plan-summary-field-specs*)))
