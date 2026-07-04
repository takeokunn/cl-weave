(in-package #:cl-weave)

(defun event-duration-seconds (event)
  (/ (test-event-elapsed-internal-time event)
     internal-time-units-per-second))

(defun status-marker (status)
  (ecase status
    (:pass "PASS")
    (:fail "FAIL")
    (:error "ERROR")))

(defun path-string (path)
  (format nil "~{~A~^ > ~}" path))

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
        (failed 0)
        (errored 0))
    (dolist (event events)
      (ecase (test-event-status event)
        (:pass (incf passed))
        (:fail (incf failed))
        (:error (incf errored)))
      (format stream "~&[~A] ~A (~,3Fs)"
              (status-marker (test-event-status event))
              (path-string (test-event-path event))
              (event-duration-seconds event))
      (unless (eq (test-event-status event) :pass)
        (format stream "~&    condition: ~A" (test-event-condition event))
        (report-assertion-detail (test-event-assertion event) stream)))
    (format stream "~&~%~D passed, ~D failed, ~D errored, ~D total~%"
            passed failed errored (length events))
    (values)))

(defun serializable-event (event)
  (list :status (test-event-status event)
        :path (test-event-path event)
        :seconds (event-duration-seconds event)
        :condition (when (test-event-condition event)
                     (princ-to-string (test-event-condition event)))
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
               :schema-version 1
               :passed (count :pass events :key #'test-event-status)
               :failed (count :fail events :key #'test-event-status)
               :errored (count :error events :key #'test-event-status)
               :events (mapcar #'serializable-event events))
         stream)
  (terpri stream)
  (values))
