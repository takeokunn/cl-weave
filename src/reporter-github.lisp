(in-package #:cl-weave)

(defun event-message (event)
  (or (test-event-reason event)
      (when (test-event-condition event)
        (princ-to-string (test-event-condition event)))
      (status-marker (test-event-status event))))

(defun event-detail-string (event)
  (with-output-to-string (stream)
    (when (test-event-condition event)
      (format stream "~A~%" (test-event-condition event)))
    (dolist (condition (test-event-secondary-conditions event))
      (format stream "secondary condition: ~A~%" condition))
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
