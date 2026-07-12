(in-package #:cl-weave/cli)

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
    ((string= token "doctor") (setf (cli-options-command options) :doctor))
    ((string= token "metadata") (setf (cli-options-command options) :metadata))
    ((string= token "version") (setf (cli-options-version options) t))
    ((string= token "help") (setf (cli-options-help options) t))))

(defun handle-option-token (options token rest)
  (multiple-value-bind (flag inline-value inline-p)
      (option-name-and-inline-value token)
    (apply-cli-option options flag
                      (if inline-p (list* inline-value rest) rest)
                      inline-p)))

(defun command-allows-positional-system-p (command)
  (member command '(:run :list :watch :doctor :metadata)))

(defun normalize-cli-arguments (argv)
  (if (and argv (string= (first argv) "--"))
      (rest argv)
      argv))

(defun finish-cli-argument-parse (options)
  (setf (cli-options-systems options)
        (nreverse (cli-options-systems options))
        (cli-options-load-files options)
        (nreverse (cli-options-load-files options)))
  options)

(defun parse-cli-argument/k (options command-seen token tail k)
  (cond
    ((option-token-p token)
     (funcall k (handle-option-token options token tail) command-seen))
    ((and (not command-seen) (command-token-p token))
     (apply-command-token options token)
     (funcall k tail t))
    ((and (command-allows-positional-system-p (cli-options-command options))
          (null (cli-options-systems options)))
     (push token (cli-options-systems options))
     (funcall k tail command-seen))
    (t
     (error 'cli-error
            :message (format nil "Unexpected argument: ~A" token)))))

(defun parse-cli-arguments/k (options rest command-seen k)
  (if (null rest)
      (funcall k (finish-cli-argument-parse options))
      (parse-cli-argument/k
       options
       command-seen
       (first rest)
       (rest rest)
       (lambda (next next-command-seen)
         (parse-cli-arguments/k options next next-command-seen k)))))

(defun parse-cli-arguments (argv &optional (options (options-from-environment)))
  (parse-cli-arguments/k options
                         (normalize-cli-arguments argv)
                         nil
                         #'identity))

(defun cli-usage ()
  (format nil "~{~A~%~}"
          (append
           '("Usage:"
             "  cl-weave run [SYSTEM] [options]"
             "  cl-weave list [SYSTEM] [options]"
             "  cl-weave watch [SYSTEM] [options]"
             "  cl-weave doctor [SYSTEM] [options]"
             "  cl-weave metadata [SYSTEM] [options]"
             "  cl-weave version"
             "  cl-weave help"
             ""
             "Options:")
           (loop for entry in (metadata-cli-options)
                 append (cli-option-usage-lines entry)))))
