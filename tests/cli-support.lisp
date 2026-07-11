(in-package #:cl-weave/tests)

(defun workflow-step-blocks (workflow)
  (loop with marker = "      - name:"
        with length = (length workflow)
        for start = (search marker workflow)
          then (and end (search marker workflow :start2 end))
        while start
        for end = (or (search marker workflow :start2 (+ start (length marker)))
                      length)
        collect (subseq workflow start end)))

(defun workflow-step-for-command (workflow command)
  (let ((command-text (normalize-shell-text (workflow-command-string command))))
    (find-if (lambda (step)
               (search command-text (normalize-shell-text step)))
             (workflow-step-blocks workflow))))

(defun workflow-timeout-minutes-for-command (workflow command)
  (let ((step (workflow-step-for-command workflow command)))
    (when step
      (let* ((marker "timeout-minutes:")
             (marker-position (search marker step)))
        (when marker-position
          (let* ((line-start (+ marker-position (length marker)))
                 (line-end (or (position #\Newline step :start line-start)
                               (length step)))
                 (line (string-trim '(#\Space #\Tab)
                                    (subseq step line-start line-end))))
            (parse-integer line)))))))

(defun minimum-workflow-timeout-minutes (timeout-seconds)
  (ceiling timeout-seconds 60))

(defun workflow-artifact-section (workflow)
  (let ((section-position (search "path: |" workflow)))
    (if section-position
        (subseq workflow section-position)
        "")))

(defun workflow-covers-quality-gate-p (workflow gate)
  (not (null (workflow-step-for-command workflow (getf gate :command)))))

(defun flake-check-names (flake)
  (loop with marker = " = mkCheck {"
        for line in (uiop:split-string flake :separator '(#\Newline))
        for trimmed = (string-trim '(#\Space #\Tab) line)
        for position = (search marker trimmed)
        when position
          collect (subseq trimmed 0 position)))

(defun packaged-cli-initializes-output-translations-p (flake)
  (not (null
        (search
         "(asdf:initialize-output-translations (quote (:output-translations (t (:home \".cache\" \"common-lisp\" :implementation)) :ignore-inherited-configuration)))"
         flake
         :test #'char=))))

