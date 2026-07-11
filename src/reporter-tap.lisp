(in-package #:cl-weave)

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
    (dolist (condition (test-event-secondary-conditions event))
      (format stream "  secondary condition: ~A~%"
              (tap-quoted-string (princ-to-string condition))))
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
