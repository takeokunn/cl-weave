(in-package #:cl-weave/cli)

(declaim (special *metadata-commands*))

(defun command-token-p (token)
  (member token *metadata-commands* :test #'string=))

(defun apply-command-token (options token)
  (cond
    ((string= token "run") (setf (cli-options-command options) :run))
    ((string= token "list")
     (setf (cli-options-command options) :list
           (cli-options-list options) t))
    ((string= token "watch")
     (setf (cli-options-command options) :watch
           (cli-options-watch options) t))
    ((string= token "metadata") (setf (cli-options-command options) :metadata))
    ((string= token "version") (setf (cli-options-version options) t))
    ((string= token "help") (setf (cli-options-help options) t))))

(defun handle-option-token (options token rest)
  (ensure-cli-option-aliases-registered)
  (multiple-value-bind (flag inline-value inline-p)
      (option-name-and-inline-value token)
    (let ((handler (gethash flag *cli-option-handlers*)))
      (unless handler
        (error 'cli-error :message (format nil "Unknown option: ~A" flag)))
      (let ((*current-cli-option-inline-p* inline-p))
        (funcall handler options (if inline-p (list* inline-value rest) rest))))))

(defun command-allows-positional-system-p (command)
  (member command '(:run :list :watch :metadata)))

(defun normalize-cli-arguments (argv)
  (if (and argv (string= (first argv) "--"))
      (rest argv)
      argv))

(defun parse-cli-arguments (argv &optional (options (options-from-environment)))
  (ensure-cli-option-aliases-registered)
  (loop
    with command-seen = nil
    for rest = (normalize-cli-arguments argv) then next
    while rest
    for token = (first rest)
    for tail = (rest rest)
    for next = (cond
                 ((option-token-p token)
                  (handle-option-token options token tail))
                 ((and (not command-seen) (command-token-p token))
                  (setf command-seen t)
                  (apply-command-token options token)
                  tail)
                 ((and (command-allows-positional-system-p
                        (cli-options-command options))
                       (null (cli-options-systems options)))
                  (push token (cli-options-systems options))
                  tail)
                 (t
                  (error 'cli-error
                         :message (format nil "Unexpected argument: ~A" token))))
    finally
       (setf (cli-options-systems options)
             (nreverse (cli-options-systems options))
             (cli-options-load-files options)
             (nreverse (cli-options-load-files options)))
       (return options)))

(defun cli-usage ()
  (format nil "~{~A~%~}"
          (append
           '("Usage:"
             "  cl-weave run [SYSTEM] [options]"
             "  cl-weave list [SYSTEM] [options]"
             "  cl-weave watch [SYSTEM] [options]"
             "  cl-weave metadata [SYSTEM] [options]"
             "  cl-weave version"
             "  cl-weave help"
             ""
             "Options:")
           (loop for entry in (metadata-cli-options)
                 append (cli-option-usage-lines entry)))))
