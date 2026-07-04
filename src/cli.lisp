(in-package #:cl-weave/cli)

(define-condition cli-error (error)
  ((message :initarg :message :reader cli-error-message))
  (:report (lambda (condition stream)
             (write-string (cli-error-message condition) stream))))

(defstruct (cli-options (:constructor make-cli-options))
  (command :run :type keyword)
  (systems '() :type list)
  (load-files '() :type list)
  (reporter :spec :type keyword)
  name-filter
  output-file
  list
  watch
  (watch-interval 0.5)
  bail
  shard
  (order :defined :type keyword)
  seed
  coverage
  coverage-output
  update-snapshots
  help)

(defvar *cli-option-handlers* (make-hash-table :test #'equal))

(defmacro define-cli-option (flag (options rest) &body body)
  `(setf (gethash ,flag *cli-option-handlers*)
         (lambda (,options ,rest)
           ,@body)))

(defun string-present-p (value)
  (and value (plusp (length value))))

(defun option-token-p (token)
  (and (string-present-p token)
       (>= (length token) 2)
       (char= (char token 0) #\-)
       (char= (char token 1) #\-)))

(defun environment-value (name)
  (let ((value (uiop:getenv name)))
    (when (string-present-p value)
      value)))

(defun truthy-environment-p (name)
  (let ((value (environment-value name)))
    (and value
         (not (member (string-downcase value)
                      '("0" "false" "no" "off")
                      :test #'string=)))))

(defun parse-complete-integer (value name)
  (handler-case
      (parse-integer value :junk-allowed nil)
    (error ()
      (error 'cli-error
             :message (format nil "~A must be an integer: ~A" name value)))))

(defun parse-positive-integer (value name)
  (let ((integer (parse-complete-integer value name)))
    (unless (plusp integer)
      (error 'cli-error :message (format nil "~A must be positive: ~A" name value)))
    integer))

(defun trailing-space-p (string start)
  (loop for index from start below (length string)
        always (find (char string index) '(#\Space #\Tab #\Newline #\Return))))

(defun parse-positive-number (value name)
  (handler-case
      (multiple-value-bind (number position)
          (read-from-string value)
        (unless (and (numberp number)
                     (plusp number)
                     (trailing-space-p value position))
          (error 'cli-error))
        number)
    (error ()
      (error 'cli-error
             :message (format nil "~A must be a positive number: ~A" name value)))))

(defun parse-reporter (value)
  (let ((normalized (string-downcase value)))
    (cond
      ((string= normalized "spec") :spec)
      ((string= normalized "sexp") :sexp)
      ((string= normalized "json") :json)
      ((string= normalized "tap") :tap)
      ((string= normalized "junit") :junit)
      (t (error 'cli-error
                :message (format nil "Unknown reporter: ~A" value))))))

(defun parse-sequence-order (value)
  (let ((normalized (string-downcase value)))
    (cond
      ((string= normalized "defined") :defined)
      ((string= normalized "random") :random)
      ((string= normalized "shuffle") :shuffle)
      (t (error 'cli-error
                :message (format nil "Unknown sequence order: ~A" value))))))

(defun parse-bail (value)
  (let ((normalized (string-downcase value)))
    (cond
      ((member normalized '("true" "yes" "on") :test #'string=) t)
      ((member normalized '("false" "no" "off" "0") :test #'string=) nil)
      (t (parse-positive-integer value "--bail")))))

(defun parse-shard (value)
  (let ((slash (position #\/ value)))
    (unless slash
      (error 'cli-error
             :message (format nil "--shard must use INDEX/COUNT: ~A" value)))
    (let ((index (parse-positive-integer (subseq value 0 slash) "--shard index"))
          (count (parse-positive-integer (subseq value (1+ slash)) "--shard count")))
      (unless (<= index count)
        (error 'cli-error
               :message (format nil "--shard requires INDEX <= COUNT: ~A" value)))
      (list index count))))

(defun require-option-argument (flag rest)
  (let ((value (first rest)))
    (unless (and value (not (option-token-p value)))
      (error 'cli-error :message (format nil "~A requires an argument" flag)))
    value))

(defun option-name-and-inline-value (token)
  (let ((equals (position #\= token)))
    (if equals
        (values (subseq token 0 equals) (subseq token (1+ equals)) t)
        (values token nil nil))))

(defun consume-optional-value (default rest)
  (if (and (first rest) (not (option-token-p (first rest))))
      (values (first rest) (rest rest))
      (values default rest)))

(define-cli-option "--help" (options rest)
  (setf (cli-options-help options) t)
  rest)

(define-cli-option "--system" (options rest)
  (let ((system (require-option-argument "--system" rest)))
    (push system (cli-options-systems options))
    (rest rest)))

(define-cli-option "--load" (options rest)
  (let ((file (require-option-argument "--load" rest)))
    (push file (cli-options-load-files options))
    (rest rest)))

(define-cli-option "--reporter" (options rest)
  (let ((reporter (require-option-argument "--reporter" rest)))
    (setf (cli-options-reporter options) (parse-reporter reporter))
    (rest rest)))

(define-cli-option "--filter" (options rest)
  (let ((filter (require-option-argument "--filter" rest)))
    (setf (cli-options-name-filter options) filter)
    (rest rest)))

(define-cli-option "--output" (options rest)
  (let ((path (require-option-argument "--output" rest)))
    (setf (cli-options-output-file options) path)
    (rest rest)))

(define-cli-option "--list" (options rest)
  (setf (cli-options-list options) t
        (cli-options-command options) :list)
  rest)

(define-cli-option "--watch" (options rest)
  (setf (cli-options-watch options) t
        (cli-options-command options) :watch)
  rest)

(define-cli-option "--watch-interval" (options rest)
  (let ((interval (require-option-argument "--watch-interval" rest)))
    (setf (cli-options-watch-interval options)
          (parse-positive-number interval "--watch-interval"))
    (rest rest)))

(define-cli-option "--bail" (options rest)
  (multiple-value-bind (value remaining)
      (consume-optional-value "true" rest)
    (setf (cli-options-bail options) (parse-bail value))
    remaining))

(define-cli-option "--shard" (options rest)
  (let ((shard (require-option-argument "--shard" rest)))
    (setf (cli-options-shard options) (parse-shard shard))
    (rest rest)))

(define-cli-option "--sequence" (options rest)
  (let ((order (require-option-argument "--sequence" rest)))
    (setf (cli-options-order options) (parse-sequence-order order))
    (rest rest)))

(define-cli-option "--seed" (options rest)
  (let ((seed (require-option-argument "--seed" rest)))
    (setf (cli-options-seed options)
          (parse-positive-integer seed "--seed"))
    (rest rest)))

(define-cli-option "--coverage" (options rest)
  (setf (cli-options-coverage options) t)
  rest)

(define-cli-option "--coverage-output" (options rest)
  (let ((path (require-option-argument "--coverage-output" rest)))
    (setf (cli-options-coverage-output options) path)
    (rest rest)))

(define-cli-option "--update-snapshots" (options rest)
  (setf (cli-options-update-snapshots options) t)
  rest)

(defun options-from-environment ()
  (let ((options (make-cli-options)))
    (when (environment-value "CL_WEAVE_SYSTEM")
      (setf (cli-options-systems options)
            (list (environment-value "CL_WEAVE_SYSTEM"))))
    (when (environment-value "CL_WEAVE_REPORTER")
      (setf (cli-options-reporter options)
            (parse-reporter (environment-value "CL_WEAVE_REPORTER"))))
    (when (environment-value "CL_WEAVE_TEST_FILTER")
      (setf (cli-options-name-filter options)
            (environment-value "CL_WEAVE_TEST_FILTER")))
    (when (environment-value "CL_WEAVE_OUTPUT_FILE")
      (setf (cli-options-output-file options)
            (environment-value "CL_WEAVE_OUTPUT_FILE")))
    (when (environment-value "CL_WEAVE_BAIL")
      (setf (cli-options-bail options)
            (parse-bail (environment-value "CL_WEAVE_BAIL"))))
    (when (environment-value "CL_WEAVE_SHARD")
      (setf (cli-options-shard options)
            (parse-shard (environment-value "CL_WEAVE_SHARD"))))
    (when (environment-value "CL_WEAVE_SEQUENCE")
      (setf (cli-options-order options)
            (parse-sequence-order (environment-value "CL_WEAVE_SEQUENCE"))))
    (when (environment-value "CL_WEAVE_SEQUENCE_SEED")
      (setf (cli-options-seed options)
            (parse-positive-integer (environment-value "CL_WEAVE_SEQUENCE_SEED")
                                    "CL_WEAVE_SEQUENCE_SEED")))
    (when (truthy-environment-p "CL_WEAVE_COVERAGE")
      (setf (cli-options-coverage options) t))
    (when (environment-value "CL_WEAVE_COVERAGE_FILE")
      (setf (cli-options-coverage-output options)
            (environment-value "CL_WEAVE_COVERAGE_FILE")))
    (when (truthy-environment-p "CL_WEAVE_LIST")
      (setf (cli-options-list options) t
            (cli-options-command options) :list))
    (when (truthy-environment-p "CL_WEAVE_WATCH")
      (setf (cli-options-watch options) t
            (cli-options-command options) :watch))
    (when (environment-value "CL_WEAVE_WATCH_INTERVAL")
      (setf (cli-options-watch-interval options)
            (parse-positive-number (environment-value "CL_WEAVE_WATCH_INTERVAL")
                                   "CL_WEAVE_WATCH_INTERVAL")))
    (when (truthy-environment-p "CL_WEAVE_UPDATE_SNAPSHOTS")
      (setf (cli-options-update-snapshots options) t))
    options))

(defun command-token-p (token)
  (member token '("run" "list" "watch" "help") :test #'string=))

(defun apply-command-token (options token)
  (cond
    ((string= token "run") (setf (cli-options-command options) :run))
    ((string= token "list")
     (setf (cli-options-command options) :list
           (cli-options-list options) t))
    ((string= token "watch")
     (setf (cli-options-command options) :watch
           (cli-options-watch options) t))
    ((string= token "help") (setf (cli-options-help options) t))))

(defun handle-option-token (options token rest)
  (multiple-value-bind (flag inline-value inline-p)
      (option-name-and-inline-value token)
    (let ((handler (gethash flag *cli-option-handlers*)))
      (unless handler
        (error 'cli-error :message (format nil "Unknown option: ~A" flag)))
      (funcall handler options (if inline-p (list* inline-value rest) rest)))))

(defun command-allows-positional-system-p (command)
  (member command '(:run :list :watch)))

(defun normalize-cli-arguments (argv)
  (if (and argv (string= (first argv) "--"))
      (rest argv)
      argv))

(defun parse-cli-arguments (argv &optional (options (options-from-environment)))
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
          '("Usage:"
            "  cl-weave run [SYSTEM] [options]"
            "  cl-weave list [SYSTEM] [options]"
            "  cl-weave watch [SYSTEM] [options]"
            ""
            "Options:"
            "  --system SYSTEM           ASDF system to load before running tests"
            "  --load FILE               Lisp file to load before running tests"
            "  --reporter REPORTER       spec, sexp, json, tap, or junit"
            "  --filter TEXT             run tests whose Vitest-style path contains TEXT"
            "  --output FILE             write reporter output to FILE"
            "  --list                    discover tests without executing bodies"
            "  --watch                   rerun an ASDF system when source files change"
            "  --watch-interval SECONDS  polling interval for watch mode"
            "  --bail[=N|true|false]     stop after the first or N failures"
            "  --shard INDEX/COUNT       select a deterministic CI shard"
            "  --sequence ORDER          defined, random, or shuffle"
            "  --seed INTEGER            deterministic random sequence seed"
            "  --coverage                wrap execution with SBCL sb-cover"
            "  --coverage-output FILE    save SBCL coverage state to FILE"
            "  --update-snapshots        update external snapshots during this run"
            "  --help                    print this help")))

(defun ensure-valid-reporter-for-command (options)
  (when (and (cli-options-list options)
             (member (cli-options-reporter options) '(:tap :junit)))
    (error 'cli-error
           :message "List mode supports spec, sexp, and json reporters.")))

(defun load-requested-inputs (options)
  (dolist (system (cli-options-systems options))
    (asdf:load-system system))
  (dolist (file (cli-options-load-files options))
    (load file)))

(defun call-with-output-stream (options callback)
  (let ((output-file (cli-options-output-file options)))
    (if output-file
        (with-open-file (stream output-file
                                :direction :output
                                :if-exists :supersede
                                :if-does-not-exist :create)
          (funcall callback stream))
        (funcall callback *standard-output*))))

(defun run-command (options)
  (ensure-valid-reporter-for-command options)
  (when (and (cli-options-watch options)
             (null (cli-options-systems options)))
    (error 'cli-error :message "Watch mode requires --system SYSTEM."))
  (load-requested-inputs options)
  (let ((cl-weave:*update-snapshots* (cli-options-update-snapshots options)))
    (cond
      ((cli-options-list options)
       (call-with-output-stream
        options
        (lambda (stream)
          (cl-weave:list-tests
           :reporter (cli-options-reporter options)
           :name-filter (cli-options-name-filter options)
           :shard (cli-options-shard options)
           :order (cli-options-order options)
           :seed (cli-options-seed options)
           :stream stream)))
       t)
      ((cli-options-watch options)
       (cl-weave:watch-system (first (cli-options-systems options))
                              :reporter (cli-options-reporter options)
                              :name-filter (cli-options-name-filter options)
                              :shard (cli-options-shard options)
                              :order (cli-options-order options)
                              :seed (cli-options-seed options)
                              :bail (cli-options-bail options)
                              :include-dependencies t
                              :interval (cli-options-watch-interval options)))
      (t
       (call-with-output-stream
        options
        (lambda (stream)
          (cl-weave:run-all
           :reporter (cli-options-reporter options)
           :name-filter (cli-options-name-filter options)
           :shard (cli-options-shard options)
           :order (cli-options-order options)
           :seed (cli-options-seed options)
           :bail (cli-options-bail options)
           :coverage (cli-options-coverage options)
           :coverage-output (cli-options-coverage-output options)
           :stream stream)))))))

#+sbcl
(defun process-arguments ()
  (let ((argv (rest sb-ext:*posix-argv*)))
    (if (and argv (string= (first argv) "--"))
        (rest argv)
        argv)))

#-sbcl
(defun process-arguments ()
  (error 'cli-error :message "cl-weave CLI currently requires SBCL."))

#+sbcl
(defun exit-process (code)
  (sb-ext:exit :code code))

#-sbcl
(defun exit-process (code)
  (uiop:quit code))

(defun main (&optional (argv (process-arguments)))
  (handler-case
      (let ((options (parse-cli-arguments argv)))
        (cond
          ((cli-options-help options)
           (write-string (cli-usage) *standard-output*)
           (exit-process 0))
          ((run-command options)
           (exit-process 0))
          (t
           (exit-process 1))))
    (cli-error (condition)
      (format *error-output* "cl-weave: ~A~%~%~A" condition (cli-usage))
      (exit-process 2))))
