(in-package #:cl-weave)

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

