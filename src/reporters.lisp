(in-package #:cl-weave)

(defun event-duration-seconds (event)
  (/ (test-event-elapsed-internal-time event)
     internal-time-units-per-second))

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
               :events (mapcar #'serializable-event events))
         stream)
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
