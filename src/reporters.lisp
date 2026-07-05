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

(defun json-escaped-string (value)
  (with-output-to-string (stream)
    (loop for char across (princ-to-string value)
          for code = (char-code char)
          do (case code
               (34 (write-string "\\\"" stream))
               (92 (write-string "\\\\" stream))
               (47 (write-string "\\/" stream))
               (8 (write-string "\\b" stream))
               (9 (write-string "\\t" stream))
               (10 (write-string "\\n" stream))
               (12 (write-string "\\f" stream))
               (13 (write-string "\\r" stream))
               (t
                (if (< code 32)
                    (format stream "\\u~4,'0X" code)
                    (write-char char stream)))))))

(defun write-json-string (value stream)
  (format stream "\"~A\"" (json-escaped-string value)))

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

(defparameter *reporter-artifact-schemas*
  '((:kind "test-results"
     :commands ("run" "watch")
     :reporters ("json" "sexp")
     :schema-version 5
     :streaming nil
     :fields ((:name "schemaVersion" :kind "integer" :required t
               :description "Artifact-local schema version.")
              (:name "kind" :kind "string" :required t
               :description "Artifact discriminator.")
              (:name "events" :kind "array" :required t
               :description "Ordered test events.")
              (:name "summary" :kind "object" :required t
               :description "Aggregated run counts and failure paths.")))
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
     :schema-version 2
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
     :schema-version 2
     :streaming nil
     :fields ((:name "schemaVersion" :kind "integer" :required t
               :description "Artifact-local schema version.")
              (:name "kind" :kind "string" :required t
               :description "Artifact discriminator.")
              (:name "tests" :kind "array" :required t
               :description "Discovered test plan entries.")
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
     :schema-version 1
     :streaming t
     :fields ((:name "schemaVersion" :kind "integer" :required t
               :description "Artifact-local schema version.")
              (:name "kind" :kind "string" :required t
               :description "Artifact discriminator.")
              (:name "test" :kind "object" :required t
               :description "Single test plan entry.")))
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
               :description "Per-mutation execution results.")))))

(defun reporter-artifact-schemas ()
  "Return structured reporter artifact schema metadata."
  *reporter-artifact-schemas*)

(defun json-status-string (status)
  (string-downcase (symbol-name status)))

(defun json-write-path (path stream)
  (write-char #\[ stream)
  (loop for part in path
        for first = t then nil
         do (progn
              (unless first
                (write-string "," stream))
              (write-json-string part stream)))
  (write-char #\] stream))

(defun json-write-string-list (values stream)
  (write-char #\[ stream)
  (loop for value in values
        for first = t then nil
        do (progn
             (unless first
               (write-string "," stream))
             (write-json-string value stream)))
  (write-char #\] stream))

(defun event-path-strings-with-status (events status)
  (loop for event in events
        when (eq (test-event-status event) status)
          collect (path-string (test-event-path event))))

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

(defun json-write-summary-count-fields (summary field-specs stream)
  (loop for spec in field-specs
        do (format stream ",\"~A\":~D"
                   (getf spec :json-key)
                   (getf summary (getf spec :plist-key)))))

(defun json-write-nullable-string (value stream)
  (if value
      (write-json-string value stream)
      (write-string "null" stream)))

(defun json-write-printed-value (value stream)
  (write-json-string (prin1-to-string value) stream))

(defun proper-list-p (value)
  (loop for tail = value then (cdr tail)
        do (cond
             ((null tail) (return t))
             ((consp tail))
             (t (return nil)))))

(defun keyword-json-key (symbol)
  (let* ((source (string-downcase (symbol-name symbol)))
         (parts '())
         (start 0))
    (loop for position = (position #\- source :start start)
          do (if position
                 (progn
                   (push (subseq source start position) parts)
                   (setf start (1+ position)))
                 (progn
                   (push (subseq source start) parts)
                   (return))))
    (let ((ordered (nreverse parts)))
      (with-output-to-string (stream)
        (when ordered
          (write-string (first ordered) stream)
          (dolist (part (rest ordered))
            (when (plusp (length part))
              (write-char (char-upcase (char part 0)) stream)
              (write-string (subseq part 1) stream))))))))

(defun json-object-key-string (key)
  (typecase key
    (keyword (keyword-json-key key))
    (string key)
    (symbol (string-downcase (symbol-name key)))
    (t (princ-to-string key))))

(defun json-plist-p (value)
  (and (proper-list-p value)
       (evenp (length value))
       (loop for tail on value by #'cddr
             always (keywordp (car tail)))))

(defun json-alist-p (value)
  (and (proper-list-p value)
       (every (lambda (entry)
                (and (consp entry)
                     (let ((key (car entry)))
                       (or (keywordp key)
                           (stringp key)
                           (symbolp key)))))
              value)))

(defun json-write-array (values stream)
  (write-char #\[ stream)
  (loop for value in values
        for first = t then nil
        do (progn
             (unless first
               (write-string "," stream))
             (json-write-value value stream)))
  (write-char #\] stream))

(defun json-write-object (pairs stream)
  (write-char #\{ stream)
  (loop for (key . value) in pairs
        for first = t then nil
        do (progn
             (unless first
               (write-string "," stream))
             (write-json-string (json-object-key-string key) stream)
             (write-char #\: stream)
             (json-write-value value stream)))
  (write-char #\} stream))

(defun json-write-value (value stream)
  (typecase value
    (null (write-string "null" stream))
    ((eql t) (write-string "true" stream))
    (string (write-json-string value stream))
    (character (write-json-string (string value) stream))
    (number (princ value stream))
    (pathname (write-json-string (namestring value) stream))
    (keyword (write-json-string (string-downcase (symbol-name value)) stream))
    (vector
     (write-char #\[ stream)
     (loop for index from 0 below (length value)
           for first = t then nil
           do (progn
                (unless first
                  (write-string "," stream))
                (json-write-value (aref value index) stream)))
     (write-char #\] stream))
    (cons
     (cond
       ((json-plist-p value)
        (json-write-object
         (loop for (key val) on value by #'cddr
               collect (cons key val))
         stream))
       ((json-alist-p value)
        (json-write-object value stream))
       ((proper-list-p value)
        (json-write-array value stream))
       (t
        (json-write-printed-value value stream))))
    (symbol (write-json-string (princ-to-string value) stream))
    (t (json-write-printed-value value stream))))

(defun json-write-assertion (detail stream)
  (if detail
      (progn
        (write-string "{" stream)
        (write-string "\"form\":" stream)
        (json-write-printed-value (assertion-detail-form detail) stream)
        (write-string ",\"matcher\":" stream)
        (json-write-printed-value (assertion-detail-matcher detail) stream)
        (write-string ",\"actual\":" stream)
        (json-write-value (assertion-detail-actual detail) stream)
        (write-string ",\"expected\":" stream)
        (json-write-value (assertion-detail-expected detail) stream)
        (write-string ",\"negated\":" stream)
        (write-string (if (assertion-detail-negated detail) "true" "false") stream)
        (write-string ",\"pass\":" stream)
        (write-string (if (assertion-detail-pass detail) "true" "false") stream)
        (write-string "}" stream))
      (write-string "null" stream)))

(defun json-write-location (location stream)
  (let ((file (and location (getf location :file))))
    (if file
        (progn
          (write-string "{\"file\":" stream)
          (write-json-string file stream)
          (write-string "}" stream))
        (write-string "null" stream))))

(defun json-write-event (event stream)
  (write-string "{" stream)
  (write-string "\"status\":" stream)
  (write-json-string (json-status-string (test-event-status event)) stream)
  (write-string ",\"path\":" stream)
  (json-write-path (test-event-path event) stream)
  (write-string ",\"pathString\":" stream)
  (write-json-string (path-string (test-event-path event)) stream)
  (write-string ",\"location\":" stream)
  (json-write-location (test-event-location event) stream)
  (format stream ",\"seconds\":~,6F" (event-duration-seconds event))
  (format stream ",\"durationMs\":~,3F" (event-duration-ms event))
  (write-string ",\"condition\":" stream)
  (json-write-nullable-string
   (when (test-event-condition event)
     (princ-to-string (test-event-condition event)))
   stream)
  (write-string ",\"reason\":" stream)
  (json-write-nullable-string (test-event-reason event) stream)
  (write-string ",\"assertion\":" stream)
  (json-write-assertion (test-event-assertion event) stream)
  (write-string "}" stream))

(defun report-assertion-detail (detail stream)
  (when detail
    (format stream "~&    form: ~S" (assertion-detail-form detail))
    (when (assertion-detail-matcher detail)
      (format stream "~&    matcher: ~S" (assertion-detail-matcher detail))
      (format stream "~&    actual: ~S" (assertion-detail-actual detail))
      (format stream "~&    expected: ~S" (assertion-detail-expected detail))
      (format stream "~&    negated: ~S" (assertion-detail-negated detail)))))

(defun report-spec (events stream)
  (let ((summary (result-summary events)))
    (dolist (event events)
      (format stream "~&[~A] ~A (~,3Fs)"
              (status-marker (test-event-status event))
              (path-string (test-event-path event))
              (event-duration-seconds event))
      (when (test-event-reason event)
        (format stream "~&    reason: ~A" (test-event-reason event)))
      (unless (member (test-event-status event) '(:pass :skip :todo))
        (format stream "~&    condition: ~A" (test-event-condition event))
        (report-assertion-detail (test-event-assertion event) stream)))
    (format stream "~&~%~D passed, ~D skipped, ~D todo, ~D failed, ~D errored, ~D total~%"
            (getf summary :passed)
            (getf summary :skipped)
            (getf summary :todos)
            (getf summary :failed)
            (getf summary :errored)
            (getf summary :total))
    (values)))

(defun serializable-event (event)
  (list :status (test-event-status event)
        :path (test-event-path event)
        :path-string (path-string (test-event-path event))
        :location (test-event-location event)
        :seconds (event-duration-seconds event)
        :duration-ms (event-duration-ms event)
        :condition (when (test-event-condition event)
                      (princ-to-string (test-event-condition event)))
        :reason (test-event-reason event)
        :assertion (let ((detail (test-event-assertion event)))
                      (when detail
                        (list :form (assertion-detail-form detail)
                              :matcher (assertion-detail-matcher detail)
                              :actual (assertion-detail-actual detail)
                              :expected (assertion-detail-expected detail)
                              :negated (assertion-detail-negated detail)
                              :pass (assertion-detail-pass detail))))))

(defun report-sexp (events stream)
  (let ((summary (result-summary events)))
    (prin1 (append (list :cl-weave/results
                         :schema-version 3)
                   summary
                   (list :events (mapcar #'serializable-event events)))
           stream))
  (terpri stream)
  (values))

(defun json-write-results-summary-fields (summary stream)
  (json-write-summary-count-fields summary *result-summary-field-specs* stream)
  (write-string ",\"failedPaths\":" stream)
  (json-write-string-list (getf summary :failed-paths) stream)
  (write-string ",\"erroredPaths\":" stream)
  (json-write-string-list (getf summary :errored-paths) stream))

(defun report-json (events stream)
  (let ((summary (result-summary events)))
  (write-string "{" stream)
  (write-string "\"schemaVersion\":5" stream)
  (write-string ",\"kind\":\"test-results\"" stream)
  (json-write-results-summary-fields summary stream)
  (write-string ",\"events\":[" stream)
  (loop for event in events
        for first = t then nil
        do (progn
             (unless first
               (write-string "," stream))
             (json-write-event event stream)))
  (write-string "]}" stream)
  (terpri stream)
  (values)))

(defun report-jsonl (events stream)
  (let ((summary (result-summary events)))
  (write-string "{\"schemaVersion\":1,\"kind\":\"test-results-start\",\"total\":" stream)
  (princ (getf summary :total) stream)
  (write-string "}" stream)
  (terpri stream)
  (dolist (event events)
    (write-string "{\"schemaVersion\":2,\"kind\":\"test-event\",\"event\":" stream)
    (json-write-event event stream)
    (write-string "}" stream)
    (terpri stream))
  (write-string "{\"schemaVersion\":1,\"kind\":\"test-results-summary\"" stream)
  (json-write-results-summary-fields summary stream)
  (write-string "}" stream)
  (terpri stream)
  (values)))

(defun tap-line-string (value)
  (with-output-to-string (stream)
    (loop for char across (princ-to-string value)
          do (case char
               ((#\Newline #\Return #\Tab) (write-char #\Space stream))
               (t (write-char char stream))))))

(defun tap-quoted-string (value)
  (format nil "\"~A\"" (json-escaped-string (tap-line-string value))))

(defun tap-directive (event)
  (let ((reason (test-event-reason event)))
    (ecase (test-event-status event)
      (:skip (format nil " # SKIP~@[ ~A~]" (when reason (tap-line-string reason))))
      (:todo (format nil " # TODO~@[ ~A~]" (when reason (tap-line-string reason))))
      ((:pass :fail :error) ""))))

(defun report-tap-assertion (detail stream)
  (when detail
    (format stream "  assertion:~%")
    (format stream "    form: ~A~%"
            (tap-quoted-string (prin1-to-string (assertion-detail-form detail))))
    (format stream "    matcher: ~A~%"
            (tap-quoted-string (prin1-to-string (assertion-detail-matcher detail))))
    (format stream "    actual: ~A~%"
            (tap-quoted-string (prin1-to-string (assertion-detail-actual detail))))
    (format stream "    expected: ~A~%"
            (tap-quoted-string (prin1-to-string (assertion-detail-expected detail))))
    (format stream "    negated: ~:[false~;true~]~%"
            (assertion-detail-negated detail))))

(defun report-tap-diagnostics (event stream)
  (unless (member (test-event-status event) '(:pass :skip :todo))
    (format stream "  ---~%")
    (format stream "  status: ~A~%"
            (tap-quoted-string (json-status-string (test-event-status event))))
    (when (test-event-condition event)
      (format stream "  condition: ~A~%"
              (tap-quoted-string (princ-to-string (test-event-condition event)))))
    (report-tap-assertion (test-event-assertion event) stream)
    (format stream "  ...~%")))

(defun report-tap (events stream)
  (format stream "TAP version 13~%")
  (format stream "1..~D~%" (length events))
  (loop for event in events
        for index from 1
        for status = (test-event-status event)
        do (progn
             (format stream "~:[not ok~;ok~] ~D - ~A~A~%"
                     (member status '(:pass :skip :todo))
                     index
                     (tap-line-string (path-string (test-event-path event)))
                     (tap-directive event))
             (report-tap-diagnostics event stream)))
  (values))

(defun event-message (event)
  (or (test-event-reason event)
      (when (test-event-condition event)
        (princ-to-string (test-event-condition event)))
      (status-marker (test-event-status event))))

(defun event-detail-string (event)
  (with-output-to-string (stream)
    (when (test-event-condition event)
      (format stream "~A~%" (test-event-condition event)))
    (report-assertion-detail (test-event-assertion event) stream)))

(defun github-escaped-data (value)
  (with-output-to-string (stream)
    (loop for char across (princ-to-string value)
          do (case char
               (#\% (write-string "%25" stream))
               (#\Return (write-string "%0D" stream))
               (#\Newline (write-string "%0A" stream))
               (t (write-char char stream))))))

(defun github-escaped-property (value)
  (with-output-to-string (stream)
    (loop for char across (github-escaped-data value)
          do (case char
               (#\: (write-string "%3A" stream))
               (#\, (write-string "%2C" stream))
               (t (write-char char stream))))))

(defun github-annotatable-event-p (event)
  (member (test-event-status event) '(:fail :error)))

(defun github-event-file (event)
  (getf (test-event-location event) :file))

(defun github-event-message (event)
  (with-output-to-string (stream)
    (format stream "~A [~A]"
            (path-string (test-event-path event))
            (json-status-string (test-event-status event)))
    (let ((detail (event-detail-string event)))
      (when (plusp (length detail))
        (format stream "~%~A" detail)))))

(defun report-github-event (event stream)
  (write-string "::error" stream)
  (let ((file (github-event-file event)))
    (when file
      (format stream " file=~A" (github-escaped-property file))))
  (format stream "::~A~%" (github-escaped-data (github-event-message event))))

(defun report-github (events stream)
  (let ((summary (result-summary events)))
    (dolist (event events)
      (when (github-annotatable-event-p event)
        (report-github-event event stream)))
    (format stream "cl-weave: ~D passed, ~D skipped, ~D todo, ~D failed, ~D errored, ~D total~%"
            (getf summary :passed)
            (getf summary :skipped)
            (getf summary :todos)
            (getf summary :failed)
            (getf summary :errored)
            (getf summary :total))
    (values)))

(defun plan-status-marker (status)
  (ecase status
    (:run "RUN")
    (:skip "SKIP")
    (:todo "TODO")))

(defun runnable-plan-entry-p (entry)
  (eq (test-plan-entry-status entry) :run))

(defun skipped-plan-entry-p (entry)
  (eq (test-plan-entry-status entry) :skip))

(defun todo-plan-entry-p (entry)
  (eq (test-plan-entry-status entry) :todo))

(defun serializable-plan-entry (entry)
  (list :status (test-plan-entry-status entry)
        :path (test-plan-entry-path entry)
        :path-string (path-string (test-plan-entry-path entry))
        :location (test-plan-entry-location entry)
        :reason (test-plan-entry-reason entry)
        :focused (test-plan-entry-focused entry)
        :retry (test-plan-entry-retry entry)
        :timeout-ms (test-plan-entry-timeout-ms entry)
        :concurrent (test-plan-entry-concurrent entry)))

(defun report-plan-spec (plan stream)
  (let ((summary (plan-summary plan)))
  (dolist (entry plan)
    (format stream "~&[~A] ~A"
            (plan-status-marker (test-plan-entry-status entry))
            (path-string (test-plan-entry-path entry)))
    (when (test-plan-entry-focused entry)
      (write-string " (focused)" stream))
    (when (test-plan-entry-reason entry)
      (format stream "~&    reason: ~A" (test-plan-entry-reason entry))))
  (format stream "~&~%~D runnable, ~D skipped, ~D todo, ~D total~%"
          (getf summary :runnable)
          (getf summary :skipped)
          (getf summary :todos)
          (getf summary :total))
  (values)))

(defun report-plan-sexp (plan stream)
  (let ((summary (plan-summary plan)))
    (prin1 (append (list :cl-weave/test-plan
                         :schema-version 2)
                   summary
                   (list :tests (mapcar #'serializable-plan-entry plan)))
           stream))
  (terpri stream)
  (values))

(defun json-write-plan-entry (entry stream)
  (write-string "{" stream)
  (write-string "\"status\":" stream)
  (write-json-string (json-status-string (test-plan-entry-status entry)) stream)
  (write-string ",\"path\":" stream)
  (json-write-path (test-plan-entry-path entry) stream)
  (write-string ",\"pathString\":" stream)
  (write-json-string (path-string (test-plan-entry-path entry)) stream)
  (write-string ",\"location\":" stream)
  (json-write-location (test-plan-entry-location entry) stream)
  (write-string ",\"reason\":" stream)
  (json-write-nullable-string (test-plan-entry-reason entry) stream)
  (write-string ",\"focused\":" stream)
  (write-string (if (test-plan-entry-focused entry) "true" "false") stream)
  (format stream ",\"retry\":~D" (test-plan-entry-retry entry))
  (write-string ",\"timeoutMs\":" stream)
  (let ((timeout-ms (test-plan-entry-timeout-ms entry)))
    (if timeout-ms
        (princ timeout-ms stream)
        (write-string "null" stream)))
  (write-string ",\"concurrent\":" stream)
  (write-string (if (test-plan-entry-concurrent entry) "true" "false") stream)
  (write-string "}" stream))

(defun report-plan-json (plan stream)
  (let ((summary (plan-summary plan)))
  (write-string "{" stream)
  (write-string "\"schemaVersion\":2" stream)
  (write-string ",\"kind\":\"test-plan\"" stream)
  (format stream ",\"total\":~D" (getf summary :total))
  (json-write-summary-count-fields summary *plan-summary-field-specs* stream)
  (write-string ",\"tests\":[" stream)
  (loop for entry in plan
        for first = t then nil
        do (progn
             (unless first
               (write-string "," stream))
             (json-write-plan-entry entry stream)))
  (write-string "]}" stream)
  (terpri stream)
  (values)))

(defun report-plan-jsonl (plan stream)
  (let ((summary (plan-summary plan)))
  (write-string "{\"schemaVersion\":1,\"kind\":\"test-plan-start\",\"total\":" stream)
  (princ (getf summary :total) stream)
  (write-string "}" stream)
  (terpri stream)
  (dolist (entry plan)
    (write-string "{\"schemaVersion\":1,\"kind\":\"test-plan-entry\",\"test\":" stream)
    (json-write-plan-entry entry stream)
    (write-string "}" stream)
    (terpri stream))
  (write-string "{\"schemaVersion\":1,\"kind\":\"test-plan-summary\"" stream)
  (format stream ",\"total\":~D" (getf summary :total))
  (json-write-summary-count-fields summary *plan-summary-field-specs* stream)
  (write-string "}" stream)
  (terpri stream)
  (values)))

(defun serializable-mutation (mutation)
  (list :id (mutation-id mutation)
        :operator (mutation-operator mutation)
        :path (mutation-path mutation)
        :original (mutation-original mutation)
        :replacement (mutation-replacement mutation)
        :form (mutation-form mutation)))

(defun serializable-mutation-result (result)
  (list :status (mutation-result-status result)
        :condition (when (mutation-result-condition result)
                     (princ-to-string (mutation-result-condition result)))
        :mutation (serializable-mutation (mutation-result-mutation result))))

(defun report-mutations-sexp (results stream)
  (prin1 (list :cl-weave/mutations
               :schema-version 1
               :summary (mutation-summary results)
               :results (mapcar #'serializable-mutation-result results))
         stream)
  (terpri stream)
  (values))

(defun json-write-integer-list (values stream)
  (write-char #\[ stream)
  (loop for value in values
        for first = t then nil
        do (progn
             (unless first
               (write-string "," stream))
             (princ value stream)))
  (write-char #\] stream))

(defun json-write-mutation (mutation stream)
  (write-string "{" stream)
  (format stream "\"id\":~D" (mutation-id mutation))
  (write-string ",\"operator\":" stream)
  (write-json-string (mutation-operator mutation) stream)
  (write-string ",\"path\":" stream)
  (json-write-integer-list (mutation-path mutation) stream)
  (write-string ",\"original\":" stream)
  (json-write-printed-value (mutation-original mutation) stream)
  (write-string ",\"replacement\":" stream)
  (json-write-printed-value (mutation-replacement mutation) stream)
  (write-string ",\"form\":" stream)
  (json-write-printed-value (mutation-form mutation) stream)
  (write-string "}" stream))

(defun json-write-mutation-result (result stream)
  (write-string "{" stream)
  (write-string "\"status\":" stream)
  (write-json-string (json-status-string (mutation-result-status result)) stream)
  (write-string ",\"condition\":" stream)
  (json-write-nullable-string
   (when (mutation-result-condition result)
     (princ-to-string (mutation-result-condition result)))
   stream)
  (write-string ",\"mutation\":" stream)
  (json-write-mutation (mutation-result-mutation result) stream)
  (write-string "}" stream))

(defun report-mutations-json (results stream)
  (let ((summary (mutation-summary results)))
    (write-string "{" stream)
    (write-string "\"schemaVersion\":1" stream)
    (write-string ",\"kind\":\"mutations\"" stream)
    (format stream ",\"total\":~D" (getf summary :total))
    (format stream ",\"killed\":~D" (getf summary :killed))
    (format stream ",\"survived\":~D" (getf summary :survived))
    (format stream ",\"errored\":~D" (getf summary :errored))
    (format stream ",\"score\":~,6F" (getf summary :score))
    (write-string ",\"results\":[" stream)
    (loop for result in results
          for first = t then nil
          do (progn
               (unless first
                 (write-string "," stream))
               (json-write-mutation-result result stream)))
    (write-string "]}" stream)
    (terpri stream)
    (values)))

(defun junit-classname (path)
  (dotted-path-string (butlast path)))

(defun junit-test-name (path)
  (or (car (last path)) "anonymous"))

(defun report-junit-event (event stream)
  (let ((status (test-event-status event)))
    (format stream "  <testcase classname=\"~A\" name=\"~A\" time=\"~,3F\">~%"
            (xml-escaped-string (junit-classname (test-event-path event)))
            (xml-escaped-string (junit-test-name (test-event-path event)))
            (event-duration-seconds event))
    (ecase status
      (:pass)
      (:skip
       (format stream "    <skipped message=\"~A\"/>~%"
               (xml-escaped-string (event-message event))))
      (:todo
       (format stream "    <skipped message=\"TODO: ~A\"/>~%"
               (xml-escaped-string (event-message event))))
      (:fail
       (format stream "    <failure message=\"~A\">~A</failure>~%"
               (xml-escaped-string (event-message event))
               (xml-escaped-string (event-detail-string event))))
      (:error
       (format stream "    <error message=\"~A\">~A</error>~%"
               (xml-escaped-string (event-message event))
               (xml-escaped-string (event-detail-string event)))))
    (format stream "  </testcase>~%")))

(defun report-junit (events stream)
  (let* ((summary (result-summary events))
         (skipped (+ (getf summary :skipped)
                     (getf summary :todos))))
    (format stream "<?xml version=\"1.0\" encoding=\"UTF-8\"?>~%")
    (format stream "<testsuite name=\"cl-weave\" tests=\"~D\" failures=\"~D\" errors=\"~D\" skipped=\"~D\" time=\"~,3F\">~%"
            (getf summary :total)
            (getf summary :failed)
            (getf summary :errored)
            skipped
            (reduce #'+ events :key #'event-duration-seconds :initial-value 0))
    (dolist (event events)
      (report-junit-event event stream))
    (format stream "</testsuite>~%")
    (values)))
