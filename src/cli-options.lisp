(in-package #:cl-weave/cli)

(define-condition cli-error (error)
  ((message :initarg :message :reader cli-error-message))
  (:report (lambda (condition stream)
             (write-string (cli-error-message condition) stream))))

(defmacro define-cli-spec-accessors (&rest specifications)
  `(progn
     ,@(loop for (name key) in specifications
             collect `(defun ,name (spec)
                        (getf spec ,key)))))

(define-cli-spec-accessors
  (cli-spec-flag :flag)
  (cli-spec-field :field)
  (cli-spec-kind :kind)
  (cli-spec-command :command)
  (cli-spec-parser :parser)
  (cli-spec-argument-name :argument-name)
  (cli-spec-default :default)
  (cli-spec-value :value)
  (cli-spec-environment :environment)
  (cli-entry-name :name)
  (cli-entry-environment :environment))

(defmacro define-cli-options (&body clauses)
  (labels ((clause (name)
             (or (assoc name clauses)
                 (error "DEFINE-CLI-OPTIONS requires a ~S clause." name)))
           (field-name (definition)
             (if (consp definition) (first definition) definition))
           (validate-specs (specs namespace fields allowed-kinds)
             (let ((flags '()))
               (dolist (spec specs)
                 (let ((flag (cli-spec-flag spec))
                       (field (cli-spec-field spec))
                       (kind (cli-spec-kind spec)))
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
                    when (eq (cli-spec-kind spec) :collection)
                      collect (cli-spec-field spec))))
           (field-accessors
             (loop for field in fields
                   collect
                   (cons field
                         (intern (format nil "CLI-OPTIONS-~A" field)
                                 (find-package '#:cl-weave/cli)))))
           (collection-accessors
             (loop for field in collection-fields
                   collect (assoc field field-accessors))))
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
           (let ((accessor (cdr (assoc field ',field-accessors))))
             (unless accessor
               (error "Unknown CLI option field: ~S" field))
             (funcall (fdefinition (list 'setf accessor)) value options))
           options)
         (defun push-cli-option-field (options field value)
           (let ((accessor (cdr (assoc field ',collection-accessors))))
             (unless accessor
               (error "Unknown collection CLI option field: ~S" field))
             (funcall (fdefinition (list 'setf accessor))
                      (cons value (funcall accessor options))
                      options))
           options)))))

(defun cli-option-spec (flag)
  (find flag *cli-option-specs* :key #'cli-spec-flag
        :test #'string=))

(defun cli-environment-spec (flag)
  (find flag *cli-environment-specs* :key #'cli-spec-flag
        :test #'string=))

(defun apply-cli-option-command (options spec)
  (let ((command (cli-spec-command spec)))
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
    (ecase (cli-spec-kind spec)
      (:flag
       (when inline-p
         (error 'cli-error
                :message (format nil "~A does not accept an inline value" flag)))
       (set-cli-option-field options (cli-spec-field spec)
                             (if (member :value spec) (cli-spec-value spec) t))
       (apply-cli-option-command options spec)
       rest)
      (:collection
       (push-cli-option-field options (cli-spec-field spec)
                              (require-option-argument flag rest))
       (rest rest))
      (:value
       (let* ((raw (require-option-argument flag rest))
              (name (or (cli-spec-argument-name spec) flag))
              (value (call-cli-option-parser (cli-spec-parser spec) raw name)))
         (set-cli-option-field options (cli-spec-field spec) value)
         (rest rest)))
      (:optional-value
       (multiple-value-bind (raw remaining)
           (consume-optional-value (cli-spec-default spec) rest)
         (let* ((name (or (cli-spec-argument-name spec) flag))
                (value (call-cli-option-parser (cli-spec-parser spec) raw name)))
           (set-cli-option-field options (cli-spec-field spec) value)
           remaining))))))

(defun apply-cli-option-environment (options entry)
  (let* ((binding (first-environment-binding (cli-entry-environment entry)))
         (name (car binding))
         (value (cdr binding))
         (option-name (cli-entry-name entry))
         (spec (cli-environment-spec option-name)))
    (when binding
      (unless spec
        (error 'cli-error
               :message (format nil
                                 "Unhandled environment-backed CLI option: ~A"
                                 option-name)))
      (ecase (cli-spec-kind spec)
        (:value
         (set-cli-option-field
          options
          (cli-spec-field spec)
          (call-cli-option-parser (cli-spec-parser spec) value name)))
        (:truthy
         (when (truthy-environment-p name)
           (set-cli-option-field options (cli-spec-field spec) t)
           (apply-cli-option-command options spec)))))))

(defun options-from-environment ()
  (let ((options (make-cli-options)))
    (dolist (entry *metadata-cli-options*)
      (apply-cli-option-environment options entry))
    options))
