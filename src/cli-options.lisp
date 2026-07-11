(in-package #:cl-weave/cli)

(declaim (special *metadata-cli-options*))

(define-condition cli-error (error)
  ((message :initarg :message :reader cli-error-message))
  (:report (lambda (condition stream)
             (write-string (cli-error-message condition) stream))))

(defmacro define-cli-options (&body clauses)
  (labels ((clause (name)
             (or (assoc name clauses)
                 (error "DEFINE-CLI-OPTIONS requires a ~S clause." name)))
           (field-name (definition)
             (if (consp definition) (first definition) definition))
           (validate-specs (specs namespace fields allowed-kinds)
             (let ((flags '()))
               (dolist (spec specs)
                 (let ((flag (getf spec :flag))
                       (field (getf spec :field))
                       (kind (getf spec :kind)))
                   (unless (and (stringp flag) (plusp (length flag)))
                     (error "~A CLI spec requires a non-empty string :FLAG: ~S"
                            namespace spec))
                   (when (member flag flags :test #'string=)
                     (error "Duplicate ~A CLI flag: ~A" namespace flag))
                   (push flag flags)
                   (unless (member field fields)
                     (error "Unknown CLI option field ~S in ~A spec ~S"
                            field namespace flag))
                   (unless (member kind allowed-kinds)
                     (error "Unknown ~A CLI option kind ~S in spec ~S"
                            namespace kind flag)))))))
    (let* ((field-definitions (rest (clause :fields)))
           (option-specs (rest (clause :options)))
           (environment-specs (rest (clause :environment)))
           (fields (mapcar (lambda (definition)
                             (intern (symbol-name (field-name definition)) :keyword))
                           field-definitions))
           (collection-fields
             (remove-duplicates
              (loop for spec in option-specs
                    when (eq (getf spec :kind) :collection)
                      collect (getf spec :field)))))
      (when (/= (length clauses) 3)
        (error "DEFINE-CLI-OPTIONS accepts only :FIELDS, :OPTIONS, and :ENVIRONMENT."))
      (validate-specs option-specs "command-line" fields
                      '(:flag :collection :value :optional-value))
      (validate-specs environment-specs "environment" fields '(:value :truthy))
      `(progn
         (defstruct (cli-options (:constructor make-cli-options))
           ,@field-definitions)
         (defparameter *cli-option-specs* ',option-specs)
         (defparameter *cli-environment-specs* ',environment-specs)
         (defun set-cli-option-field (options field value)
           (ecase field
             ,@(loop for field in fields
                     for accessor = (intern (format nil "CLI-OPTIONS-~A" field)
                                            (find-package '#:cl-weave/cli))
                     collect `(,field (setf (,accessor options) value))))
           options)
         (defun push-cli-option-field (options field value)
           (ecase field
             ,@(loop for field in collection-fields
                     for accessor = (intern (format nil "CLI-OPTIONS-~A" field)
                                            (find-package '#:cl-weave/cli))
                     collect `(,field (push value (,accessor options)))))
           options)))))

(define-cli-options
  (:fields
   (command :run :type keyword)
   (systems '() :type list)
   (load-files '() :type list)
   (reporter :spec :type keyword)
   name-filter output-file list watch watch-once
   (watch-interval 0.5)
   bail
   (retry 0)
   test-timeout-ms max-workers shard
   (order nil :type (or null keyword))
   seed coverage coverage-output
   (pass-with-no-tests t)
   snapshot-directory snapshot-file update-snapshots version help)
  (:options
   (:flag "--help" :kind :flag :field :help)
   (:flag "--version" :kind :flag :field :version)
   (:flag "--list" :kind :flag :field :list :command :list)
   (:flag "--watch" :kind :flag :field :watch :command :watch)
   (:flag "--once" :kind :flag :field :watch-once)
   (:flag "--coverage" :kind :flag :field :coverage)
   (:flag "--pass-with-no-tests" :kind :flag :field :pass-with-no-tests)
   (:flag "--fail-with-no-tests" :kind :flag :field :pass-with-no-tests :value nil)
   (:flag "--update-snapshots" :kind :flag :field :update-snapshots)
   (:flag "--system" :kind :collection :field :systems)
   (:flag "--load" :kind :collection :field :load-files)
   (:flag "--reporter" :kind :value :field :reporter :parser parse-reporter-option)
   (:flag "--filter" :kind :value :field :name-filter)
   (:flag "--output" :kind :value :field :output-file)
   (:flag "--watch-interval" :kind :value :field :watch-interval :parser parse-positive-number)
   (:flag "--retry" :kind :value :field :retry :parser parse-non-negative-integer)
   (:flag "--test-timeout-ms" :kind :value :field :test-timeout-ms :parser parse-positive-integer)
   (:flag "--max-workers" :kind :value :field :max-workers :parser parse-positive-integer)
   (:flag "--shard" :kind :value :field :shard :parser parse-shard-option)
   (:flag "--sequence" :kind :value :field :order :parser parse-sequence-order-option)
   (:flag "--seed" :kind :value :field :seed :parser parse-positive-integer)
   (:flag "--coverage-output" :kind :value :field :coverage-output)
   (:flag "--snapshot-dir" :kind :value :field :snapshot-directory :parser parse-pathname-option)
   (:flag "--snapshot-file" :kind :value :field :snapshot-file)
   (:flag "--bail" :kind :optional-value :field :bail :parser parse-bail-option :default "true"))
  (:environment
   (:flag "--system" :kind :value :field :systems :parser parse-system-list-option)
   (:flag "--reporter" :kind :value :field :reporter :parser parse-reporter-option)
   (:flag "--filter" :kind :value :field :name-filter)
   (:flag "--output" :kind :value :field :output-file)
   (:flag "--watch-interval" :kind :value :field :watch-interval :parser parse-positive-number)
   (:flag "--bail" :kind :value :field :bail :parser parse-bail-option)
   (:flag "--retry" :kind :value :field :retry :parser parse-non-negative-integer)
   (:flag "--test-timeout-ms" :kind :value :field :test-timeout-ms :parser parse-positive-integer)
   (:flag "--max-workers" :kind :value :field :max-workers :parser parse-positive-integer)
   (:flag "--shard" :kind :value :field :shard :parser parse-shard-option)
   (:flag "--sequence" :kind :value :field :order :parser parse-sequence-order-option)
   (:flag "--seed" :kind :value :field :seed :parser parse-positive-integer)
   (:flag "--coverage-output" :kind :value :field :coverage-output)
   (:flag "--pass-with-no-tests" :kind :value :field :pass-with-no-tests :parser parse-boolean)
   (:flag "--snapshot-dir" :kind :value :field :snapshot-directory :parser parse-pathname-option)
   (:flag "--snapshot-file" :kind :value :field :snapshot-file)
   (:flag "--list" :kind :truthy :field :list :command :list)
   (:flag "--watch" :kind :truthy :field :watch :command :watch)
   (:flag "--once" :kind :truthy :field :watch-once)
   (:flag "--coverage" :kind :truthy :field :coverage)
   (:flag "--update-snapshots" :kind :truthy :field :update-snapshots)))

(defun cli-option-spec (flag)
  (find flag *cli-option-specs* :key (lambda (entry) (getf entry :flag))
        :test #'string=))

(defun cli-environment-spec (flag)
  (find flag *cli-environment-specs* :key (lambda (entry) (getf entry :flag))
        :test #'string=))

(defun apply-cli-option-command (options spec)
  (let ((command (getf spec :command)))
    (when command
      (set-cli-option-field options :command command))))

(defun call-cli-option-parser (parser value name)
  (if parser
      (funcall parser value name)
      value))

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
    (or (loop for reporter in (cl-weave:run-reporters)
              when (string= normalized (string-downcase (symbol-name reporter)))
                return reporter)
        (error 'cli-error
               :message (format nil "cl-weave: unknown reporter: ~A" value)))))

(defun parse-sequence-order (value)
  (if (string-equal value "random")
      :random
      (error 'cli-error
             :message (format nil "Unknown sequence order: ~A" value))))

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

(defun parse-system-list-option (value ignore)
  (declare (ignore ignore))
  (list value))

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

(defun apply-cli-option (options flag rest inline-p)
  (let ((spec (cli-option-spec flag)))
    (unless spec
      (error 'cli-error :message (format nil "Unknown option: ~A" flag)))
    (ecase (getf spec :kind)
      (:flag
       (when inline-p
         (error 'cli-error
                :message (format nil "~A does not accept an inline value" flag)))
       (set-cli-option-field options (getf spec :field)
                             (if (member :value spec) (getf spec :value) t))
       (apply-cli-option-command options spec)
       rest)
      (:collection
       (push-cli-option-field options (getf spec :field)
                              (require-option-argument flag rest))
       (rest rest))
      (:value
       (let* ((raw (require-option-argument flag rest))
              (name (getf spec :argument-name flag))
              (value (call-cli-option-parser (getf spec :parser) raw name)))
         (set-cli-option-field options (getf spec :field) value)
         (rest rest)))
      (:optional-value
       (multiple-value-bind (raw remaining)
           (consume-optional-value (getf spec :default) rest)
         (let* ((name (getf spec :argument-name flag))
                (value (call-cli-option-parser (getf spec :parser) raw name)))
           (set-cli-option-field options (getf spec :field) value)
           remaining))))))

(defun apply-cli-option-environment (options entry)
  (let* ((binding (first-environment-binding (getf entry :environment)))
         (name (car binding))
         (value (cdr binding))
         (option-name (getf entry :name))
         (spec (cli-environment-spec option-name)))
    (when binding
      (unless spec
        (error 'cli-error
               :message (format nil
                                 "Unhandled environment-backed CLI option: ~A"
                                 option-name)))
      (ecase (getf spec :kind)
        (:value
         (set-cli-option-field
          options
          (getf spec :field)
          (call-cli-option-parser (getf spec :parser) value name)))
        (:truthy
         (when (truthy-environment-p name)
           (set-cli-option-field options (getf spec :field) t)
           (apply-cli-option-command options spec)))))))

(defun options-from-environment ()
  (let ((options (make-cli-options)))
    (dolist (entry *metadata-cli-options*)
      (apply-cli-option-environment options entry))
    options))
