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
          do (case char
               (#\< (write-string "&lt;" stream))
               (#\> (write-string "&gt;" stream))
               (#\& (write-string "&amp;" stream))
               (#\" (write-string "&quot;" stream))
               (#\' (write-string "&apos;" stream))
               (t (write-char char stream))))))

(defun json-escaped-string (value)
  (with-output-to-string (stream)
    (loop for char across (princ-to-string value)
          do (case char
               (#\" (write-string "\\\"" stream))
               (#\\ (write-string "\\\\" stream))
               (#\/ (write-string "\\/" stream))
               (#\Backspace (write-string "\\b" stream))
               (#\Page (write-string "\\f" stream))
               (#\Newline (write-string "\\n" stream))
               (#\Return (write-string "\\r" stream))
               (#\Tab (write-string "\\t" stream))
               (t
                (if (< (char-code char) 32)
                    (format stream "\\u~4,'0X" (char-code char))
                    (write-char char stream)))))))

(defun write-json-string (value stream)
  (format stream "\"~A\"" (json-escaped-string value)))

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

(defun json-write-nullable-string (value stream)
  (if value
      (write-json-string value stream)
      (write-string "null" stream)))

(defun json-write-printed-value (value stream)
  (write-json-string (prin1-to-string value) stream))

(defun json-write-assertion (detail stream)
  (if detail
      (progn
        (write-string "{" stream)
        (write-string "\"form\":" stream)
        (json-write-printed-value (assertion-detail-form detail) stream)
        (write-string ",\"matcher\":" stream)
        (json-write-printed-value (assertion-detail-matcher detail) stream)
        (write-string ",\"actual\":" stream)
        (json-write-printed-value (assertion-detail-actual detail) stream)
        (write-string ",\"expected\":" stream)
        (json-write-printed-value (assertion-detail-expected detail) stream)
        (write-string ",\"negated\":" stream)
        (write-string (if (assertion-detail-negated detail) "true" "false") stream)
        (write-string ",\"pass\":" stream)
        (write-string (if (assertion-detail-pass detail) "true" "false") stream)
        (write-string "}" stream))
      (write-string "null" stream)))

(defun json-write-event (event stream)
  (write-string "{" stream)
  (write-string "\"status\":" stream)
  (write-json-string (json-status-string (test-event-status event)) stream)
  (write-string ",\"path\":" stream)
  (json-write-path (test-event-path event) stream)
  (write-string ",\"pathString\":" stream)
  (write-json-string (path-string (test-event-path event)) stream)
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
  (let ((passed 0)
        (skipped 0)
        (todos 0)
        (failed 0)
        (errored 0))
    (dolist (event events)
      (ecase (test-event-status event)
        (:pass (incf passed))
        (:skip (incf skipped))
        (:todo (incf todos))
        (:fail (incf failed))
        (:error (incf errored)))
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
            passed skipped todos failed errored (length events))
    (values)))

(defun serializable-event (event)
  (list :status (test-event-status event)
        :path (test-event-path event)
        :seconds (event-duration-seconds event)
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
  (prin1 (list :cl-weave/results
                :schema-version 2
                :passed (count :pass events :key #'test-event-status)
                :skipped (count :skip events :key #'test-event-status)
                :todos (count :todo events :key #'test-event-status)
                :failed (count :fail events :key #'test-event-status)
                :errored (count :error events :key #'test-event-status)
                :failed-paths (event-path-strings-with-status events :fail)
                :errored-paths (event-path-strings-with-status events :error)
                :events (mapcar #'serializable-event events))
         stream)
  (terpri stream)
  (values))

(defun report-json (events stream)
  (write-string "{" stream)
  (write-string "\"schemaVersion\":2" stream)
  (format stream ",\"passed\":~D" (count :pass events :key #'test-event-status))
  (format stream ",\"skipped\":~D" (count :skip events :key #'test-event-status))
  (format stream ",\"todos\":~D" (count :todo events :key #'test-event-status))
  (format stream ",\"failed\":~D" (count :fail events :key #'test-event-status))
  (format stream ",\"errored\":~D" (count :error events :key #'test-event-status))
  (write-string ",\"failedPaths\":" stream)
  (json-write-string-list (event-path-strings-with-status events :fail) stream)
  (write-string ",\"erroredPaths\":" stream)
  (json-write-string-list (event-path-strings-with-status events :error) stream)
  (write-string ",\"events\":[" stream)
  (loop for event in events
        for first = t then nil
        do (progn
             (unless first
               (write-string "," stream))
             (json-write-event event stream)))
  (write-string "]}" stream)
  (terpri stream)
  (values))

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
        :reason (test-plan-entry-reason entry)
        :focused (test-plan-entry-focused entry)
        :retry (test-plan-entry-retry entry)
        :timeout-ms (test-plan-entry-timeout-ms entry)))

(defun report-plan-spec (plan stream)
  (dolist (entry plan)
    (format stream "~&[~A] ~A"
            (plan-status-marker (test-plan-entry-status entry))
            (path-string (test-plan-entry-path entry)))
    (when (test-plan-entry-focused entry)
      (write-string " (focused)" stream))
    (when (test-plan-entry-reason entry)
      (format stream "~&    reason: ~A" (test-plan-entry-reason entry))))
  (format stream "~&~%~D runnable, ~D skipped, ~D todo, ~D total~%"
          (count-if #'runnable-plan-entry-p plan)
          (count-if #'skipped-plan-entry-p plan)
          (count-if #'todo-plan-entry-p plan)
          (length plan))
  (values))

(defun report-plan-sexp (plan stream)
  (prin1 (list :cl-weave/test-plan
               :schema-version 1
               :total (length plan)
               :runnable (count-if #'runnable-plan-entry-p plan)
               :skipped (count-if #'skipped-plan-entry-p plan)
               :todos (count-if #'todo-plan-entry-p plan)
               :tests (mapcar #'serializable-plan-entry plan))
         stream)
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
  (write-string "}" stream))

(defun report-plan-json (plan stream)
  (write-string "{" stream)
  (write-string "\"schemaVersion\":1" stream)
  (write-string ",\"kind\":\"test-plan\"" stream)
  (format stream ",\"total\":~D" (length plan))
  (format stream ",\"runnable\":~D" (count-if #'runnable-plan-entry-p plan))
  (format stream ",\"skipped\":~D" (count-if #'skipped-plan-entry-p plan))
  (format stream ",\"todos\":~D" (count-if #'todo-plan-entry-p plan))
  (write-string ",\"tests\":[" stream)
  (loop for entry in plan
        for first = t then nil
        do (progn
             (unless first
               (write-string "," stream))
             (json-write-plan-entry entry stream)))
  (write-string "]}" stream)
  (terpri stream)
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
  (let ((skipped (+ (count :skip events :key #'test-event-status)
                    (count :todo events :key #'test-event-status))))
    (format stream "<?xml version=\"1.0\" encoding=\"UTF-8\"?>~%")
    (format stream "<testsuite name=\"cl-weave\" tests=\"~D\" failures=\"~D\" errors=\"~D\" skipped=\"~D\" time=\"~,3F\">~%"
            (length events)
            (count :fail events :key #'test-event-status)
            (count :error events :key #'test-event-status)
            skipped
            (reduce #'+ events :key #'event-duration-seconds :initial-value 0))
    (dolist (event events)
      (report-junit-event event stream))
    (format stream "</testsuite>~%")
    (values)))
