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
         :test (function char=)))))

(defun workflow-action-reference (line)
  (let ((uses-position (search "uses:" line)))
    (when uses-position
      (let* ((reference-start (+ uses-position (length "uses:")))
             (comment-position (position #\# line :start reference-start))
             (reference-end (or comment-position (length line))))
        (string-trim (list #\Space #\Tab)
                     (subseq line reference-start reference-end))))))

(defun workflow-remote-action-lines (workflow)
  (loop for line in (uiop:split-string workflow :separator (list #\Newline))
        for reference = (workflow-action-reference line)
        when (and reference
                  (position #\@ reference)
                  (not (uiop:string-prefix-p "./" reference)))
          collect line))

(defun workflow-action-immutably-pinned-p (line)
  (let* ((reference (workflow-action-reference line))
         (at-position (and reference (position #\@ reference :from-end t)))
         (revision (and at-position (subseq reference (1+ at-position)))))
    (and revision
         (= (length revision) 40)
         (every (lambda (character)
                  (or (digit-char-p character)
                      (find character "abcdef" :test (function char=))))
                revision))))

(defun workflow-step-for-name (workflow name)
  (let ((marker (format nil "- name: ~A" name)))
    (find-if (lambda (step)
               (search marker step))
             (workflow-step-blocks workflow))))

(defun workflow-job-block (workflow name)
  (let* ((marker (format nil "~%  ~A:~%" name))
         (job-indent (format nil "~%  "))
         (start (search marker workflow)))
    (when start
      (let* ((contents-start (+ start (length marker)))
             (end
               (loop for candidate = (search job-indent workflow
                                             :start2 contents-start)
                       then (search job-indent workflow
                                    :start2 (1+ candidate))
                     while candidate
                     when (let ((name-start (+ candidate (length job-indent))))
                            (and (< name-start (length workflow))
                                 (not (member (char workflow name-start)
                                              (list #\Space #\Tab)))))
                       return candidate
                     finally (return (length workflow)))))
        (subseq workflow start end)))))

(defun workflow-job-preamble (workflow name)
  (let ((job (workflow-job-block workflow name)))
    (when job
      (let ((steps-position (search "    steps:" job)))
        (subseq job 0 (or steps-position (length job)))))))
