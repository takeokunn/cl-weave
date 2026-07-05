(in-package #:cl-weave/cli)

(declaim (special *metadata-cli-options*))

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
  watch-once
  (watch-interval 0.5)
  bail
  (retry 0)
  test-timeout-ms
  max-workers
  shard
  (order :defined :type keyword)
  seed
  coverage
  coverage-output
  (pass-with-no-tests t)
  snapshot-directory
  snapshot-file
  update-snapshots
  version
  help)

(defvar *cli-option-handlers* (make-hash-table :test #'equal))
(defvar *cli-environment-appliers* (make-hash-table :test #'equal))
(defvar *cli-option-aliases-registered-p* nil)

(defmacro define-cli-option (flag (options rest) &body body)
  `(setf (gethash ,flag *cli-option-handlers*)
         (lambda (,options ,rest)
           ,@body)))

(defmacro define-cli-option-alias (alias target)
  `(let ((handler (gethash ,target *cli-option-handlers*)))
     (unless handler
       (error "Unknown CLI option alias target: ~A" ,target))
     (setf (gethash ,alias *cli-option-handlers*) handler)))

(defmacro define-cli-environment-applier (flag (options name value) &body body)
  `(setf (gethash ,flag *cli-environment-appliers*)
         (lambda (,options ,name ,value)
           (declare (ignorable ,options ,name ,value))
           ,@body)))

(defmacro define-cli-flag-option (flag place &optional (value t value-supplied-p) command)
  `(define-cli-option ,flag (options rest)
     (setf ,place ,(if value-supplied-p value t))
     ,@(when command
         `((setf (cli-options-command options) ,command)))
     rest))

(defmacro define-cli-value-option (flag place parser &optional argument-name)
  (let ((value-name (gensym "VALUE"))
        (raw-name (gensym "RAW"))
        (name (or argument-name flag)))
    `(define-cli-option ,flag (options rest)
       (let* ((,raw-name (require-option-argument ,flag rest))
              (,value-name ,(if parser
                                `(funcall ,parser ,raw-name ,name)
                                raw-name)))
         (setf ,place ,value-name)
         (rest rest)))))

(defmacro define-cli-optional-value-option (flag place parser default &optional argument-name)
  (let ((raw-name (gensym "RAW"))
        (value-name (gensym "VALUE"))
        (name (or argument-name flag)))
    `(define-cli-option ,flag (options rest)
       (multiple-value-bind (,raw-name remaining)
           (consume-optional-value ,default rest)
         (let ((,value-name ,(if parser
                                 `(funcall ,parser ,raw-name ,name)
                                 raw-name)))
           (setf ,place ,value-name)
           remaining)))))

(defmacro define-cli-environment-value-applier (flag place parser)
  (let ((parsed-name (gensym "PARSED")))
    `(define-cli-environment-applier ,flag (options name value)
       (let ((,parsed-name ,(if parser
                                `(funcall ,parser value name)
                                'value)))
         (setf ,place ,parsed-name)))))

(defmacro define-cli-truthy-environment-applier (flag &body body)
  `(define-cli-environment-applier ,flag (options name value)
     (declare (ignore value))
     (when (truthy-environment-p name)
       ,@body)))

(defmacro define-cli-collection-options (&body specs)
  `(progn
     ,@(loop for (flag slot-reader argument-name) in specs
             collect
             `(define-cli-option ,flag (options rest)
                (let ((value (require-option-argument ,flag rest)))
                  (push value (,slot-reader options))
                  (rest rest))))))

(defmacro define-cli-flag-options (&body specs)
  `(progn
     ,@(loop for spec in specs
             collect
             (destructuring-bind (flag place &key (value t value-supplied-p) command) spec
               `(define-cli-flag-option ,flag ,place
                  ,@(if value-supplied-p (list value) '())
                  ,@(when command (list command)))))))

(defmacro define-cli-value-options (&body specs)
  `(progn
     ,@(loop for (flag place parser &optional argument-name) in specs
             collect
             `(define-cli-value-option ,flag ,place ,parser ,argument-name))))

(defmacro define-cli-optional-value-options (&body specs)
  `(progn
     ,@(loop for (flag place parser default &optional argument-name) in specs
             collect
             `(define-cli-optional-value-option ,flag ,place ,parser ,default
                ,argument-name))))

(defmacro define-cli-environment-value-appliers (&body specs)
  `(progn
     ,@(loop for (flag place parser) in specs
             collect
             `(define-cli-environment-value-applier ,flag ,place ,parser))))

(defmacro define-cli-truthy-environment-appliers (&body specs)
  `(progn
     ,@(loop for (flag . body) in specs
             collect
             `(define-cli-truthy-environment-applier ,flag
                ,@body))))

(defun register-metadata-cli-option-aliases ()
  (unless (boundp '*metadata-cli-options*)
    (error "CLI metadata options are not loaded yet"))
  (loop for entry in *metadata-cli-options*
        for canonical = (getf entry :name)
        do (loop for alias in (getf entry :aliases)
                 do (define-cli-option-alias alias canonical)))
  (setf *cli-option-aliases-registered-p* t))

(defun ensure-cli-option-aliases-registered ()
  (unless *cli-option-aliases-registered-p*
    (register-metadata-cli-option-aliases)))

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
                      '("0" "false" "no" "off" "nil")
                      :test #'string=)))))

(defun first-environment-binding (names)
  (loop for name in names
        for value = (environment-value name)
        when value
          return (cons name value)))

(defun parse-boolean (value name)
  (let ((normalized (string-downcase value)))
    (cond
      ((member normalized '("1" "true" "yes" "on") :test #'string=) t)
      ((member normalized '("0" "false" "no" "off" "nil") :test #'string=) nil)
      (t (error 'cli-error
                :message (format nil "~A must be a boolean: ~A" name value))))))

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

(defun parse-non-negative-integer (value name)
  (let ((integer (parse-complete-integer value name)))
    (when (minusp integer)
      (error 'cli-error
             :message (format nil "~A must be a non-negative integer: ~A" name value)))
    integer))

(defun parse-positive-number (value name)
  (labels ((invalid ()
             (error 'cli-error
                    :message (format nil "~A must be a positive number: ~A" name value)))
           (digits-p (string)
             (and (plusp (length string))
                  (every #'digit-char-p string)))
           (component (string)
             (unless (digits-p string)
               (invalid))
             (parse-integer string :junk-allowed nil)))
    (let* ((first-dot (position #\. value))
           (second-dot (and first-dot
                            (position #\. value :start (1+ first-dot)))))
      (when (or (string= value "") second-dot)
        (invalid))
      (let ((number
              (if first-dot
                  (let* ((whole (component (subseq value 0 first-dot)))
                         (fraction-text (subseq value (1+ first-dot)))
                         (fraction (component fraction-text))
                         (denominator (expt 10 (length fraction-text))))
                    (float (+ whole (/ fraction denominator)) 1.0))
                  (component value))))
        (unless (plusp number)
          (invalid))
        number))))

(defun parse-reporter (value)
  (let ((normalized (string-downcase value)))
    (or (loop for (reporter . aliases) in cl-weave::*reporter-aliases*
              when (member normalized aliases :test #'string=)
                return reporter)
        (error 'cli-error
               :message (format nil "cl-weave: unknown reporter: ~A" value)))))

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
      ((member normalized '("true" "yes" "on" "t") :test #'string=) t)
      ((member normalized '("false" "no" "off" "0" "nil") :test #'string=) nil)
      (t
       (let ((parsed (ignore-errors
                       (parse-complete-integer value "--bail"))))
         (unless (and parsed (plusp parsed))
           (error 'cli-error
                  :message (format nil "--bail must be true, false, or a positive integer: ~A" value)))
         parsed)))))

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

(defun parse-reporter-option (value ignore)
  (declare (ignore ignore))
  (parse-reporter value))

(defun parse-bail-option (value ignore)
  (declare (ignore ignore))
  (parse-bail value))

(defun parse-shard-option (value ignore)
  (declare (ignore ignore))
  (parse-shard value))

(defun parse-sequence-order-option (value ignore)
  (declare (ignore ignore))
  (parse-sequence-order value))

(defun parse-pathname-option (value ignore)
  (declare (ignore ignore))
  (pathname value))

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

(define-cli-flag-options
  ("--help" (cli-options-help options))
  ("--version" (cli-options-version options))
  ("--list" (cli-options-list options) :value t :command :list)
  ("--watch" (cli-options-watch options) :value t :command :watch)
  ("--once" (cli-options-watch-once options))
  ("--coverage" (cli-options-coverage options))
  ("--pass-with-no-tests" (cli-options-pass-with-no-tests options))
  ("--fail-with-no-tests" (cli-options-pass-with-no-tests options) :value nil)
  ("--update-snapshots" (cli-options-update-snapshots options)))

(define-cli-collection-options
  ("--system" cli-options-systems "SYSTEM")
  ("--load" cli-options-load-files "FILE"))

(define-cli-value-options
  ("--reporter" (cli-options-reporter options) #'parse-reporter-option)
  ("--filter" (cli-options-name-filter options) nil)
  ("--output" (cli-options-output-file options) nil)
  ("--watch-interval" (cli-options-watch-interval options) #'parse-positive-number)
  ("--retry" (cli-options-retry options) #'parse-non-negative-integer)
  ("--test-timeout-ms" (cli-options-test-timeout-ms options) #'parse-positive-integer)
  ("--test-timeout" (cli-options-test-timeout-ms options) #'parse-positive-integer)
  ("--max-workers" (cli-options-max-workers options) #'parse-positive-integer)
  ("--shard" (cli-options-shard options) #'parse-shard-option)
  ("--sequence" (cli-options-order options) #'parse-sequence-order-option)
  ("--seed" (cli-options-seed options) #'parse-positive-integer)
  ("--coverage-output" (cli-options-coverage-output options) nil)
  ("--snapshot-dir" (cli-options-snapshot-directory options) #'parse-pathname-option)
  ("--snapshot-file" (cli-options-snapshot-file options) nil))

(define-cli-optional-value-options
  ("--bail" (cli-options-bail options) #'parse-bail-option "true"))

(define-cli-environment-value-appliers
  ("--system" (cli-options-systems options) #'list)
  ("--reporter" (cli-options-reporter options) #'parse-reporter-option)
  ("--filter" (cli-options-name-filter options) nil)
  ("--output" (cli-options-output-file options) nil)
  ("--watch-interval" (cli-options-watch-interval options) #'parse-positive-number)
  ("--bail" (cli-options-bail options) #'parse-bail-option)
  ("--retry" (cli-options-retry options) #'parse-non-negative-integer)
  ("--test-timeout-ms" (cli-options-test-timeout-ms options) #'parse-positive-integer)
  ("--max-workers" (cli-options-max-workers options) #'parse-positive-integer)
  ("--shard" (cli-options-shard options) #'parse-shard-option)
  ("--sequence" (cli-options-order options) #'parse-sequence-order-option)
  ("--seed" (cli-options-seed options) #'parse-positive-integer)
  ("--coverage-output" (cli-options-coverage-output options) nil)
  ("--pass-with-no-tests" (cli-options-pass-with-no-tests options) #'parse-boolean)
  ("--snapshot-dir" (cli-options-snapshot-directory options) #'parse-pathname-option)
  ("--snapshot-file" (cli-options-snapshot-file options) nil))

(define-cli-truthy-environment-appliers
  ("--list"
   (setf (cli-options-list options) t
         (cli-options-command options) :list))
  ("--watch"
   (setf (cli-options-watch options) t
         (cli-options-command options) :watch))
  ("--once"
   (setf (cli-options-watch-once options) t))
  ("--coverage"
   (setf (cli-options-coverage options) t))
  ("--update-snapshots"
   (setf (cli-options-update-snapshots options) t)))

(defun apply-cli-option-environment (options entry)
  (let* ((binding (first-environment-binding (getf entry :environment)))
         (name (car binding))
         (value (cdr binding))
         (option-name (getf entry :name))
         (applier (gethash option-name *cli-environment-appliers*)))
    (when binding
      (unless applier
        (error 'cli-error
               :message (format nil
                                "Unhandled environment-backed CLI option: ~A"
                                option-name)))
      (funcall applier options name value))))

(defun options-from-environment ()
  (let ((options (make-cli-options)))
    (dolist (entry *metadata-cli-options*)
      (apply-cli-option-environment options entry))
    options))
