(in-package #:cl-weave)

(defun split-reasoned-body (body default-reason)
  (if (and body (stringp (first body)))
      (values (first body) (rest body))
      (values default-reason body)))

(defun registration-proper-list-p (value)
  (handler-case
      (progn (length value) t)
    (type-error () nil)))

(defun suite-registration-form (name forms options)
  `(register-suite ,name (lambda () ,@forms) ,@options))

(defun validate-suite-each-syntax (cases name bindings target)
  (unless (registration-proper-list-p cases)
    (error "~S requires CASES to be a literal proper list, got ~S." target cases))
  (unless (stringp name)
    (error "~S requires NAME to be a literal format string, got ~S." target name))
  (unless (registration-proper-list-p bindings)
    (error "~S requires BINDINGS to be a literal proper list, got ~S." target bindings))
  (loop for case in cases
        for index from 0
        unless (registration-proper-list-p case)
          do (error "~S case ~D must be a literal proper list, got ~S." target index case))
  (values))

(defun suite-each-cases (cases name bindings forms target)
  (validate-suite-each-syntax cases name bindings target)
  (loop for case in cases
        for index from 0
        collect `(,target ,(handler-case
                               (apply #'format nil name case)
                             (error (condition)
                               (error "~S case ~D does not match format string ~S: ~A"
                                      target index name condition)))
                   (destructuring-bind ,bindings ',case
                     ,@forms))))

(defmacro describe (suite-name &body body)
  (suite-registration-form suite-name body nil))

(defmacro describe-only (suite-name &body body)
  (suite-registration-form suite-name body '(:focus t)))

(defmacro describe-concurrent (suite-name &body body)
  (suite-registration-form suite-name body '(:execution-mode :concurrent)))

(defmacro describe-sequential (suite-name &body body)
  (suite-registration-form suite-name body '(:execution-mode :sequential)))

(defmacro describe-skip (suite-name &body body)
  (multiple-value-bind (reason forms) (split-reasoned-body body "skipped")
    (suite-registration-form suite-name forms (list :skip-reason reason))))

(defmacro describe-todo (suite-name &body body)
  (multiple-value-bind (reason forms) (split-reasoned-body body "todo")
    (suite-registration-form suite-name forms (list :todo-reason reason))))

(defmacro describe-skip-if (condition name &body body)
  `(if ,condition
       (describe-skip ,name "conditional skip" ,@body)
       (describe ,name ,@body)))

(defmacro describe-run-if (condition name &body body)
  `(if ,condition
       (describe ,name ,@body)
       (describe-skip ,name "conditional run-if" ,@body)))

(defmacro describe-each (cases suite-name bindings &body body)
  `(progn ,@(suite-each-cases cases suite-name bindings body 'describe)))

(defmacro describe-only-each (cases suite-name bindings &body body)
  `(progn ,@(suite-each-cases cases suite-name bindings body 'describe-only)))

(defmacro describe-concurrent-each (cases suite-name bindings &body body)
  `(progn ,@(suite-each-cases cases suite-name bindings body 'describe-concurrent)))

(defmacro describe-sequential-each (cases suite-name bindings &body body)
  `(progn ,@(suite-each-cases cases suite-name bindings body 'describe-sequential)))

(defmacro describe-skip-each (cases suite-name bindings &body body)
  (multiple-value-bind (reason forms) (split-reasoned-body body "skipped")
    `(progn
       ,@(loop for case in cases
               collect `(describe-skip ,(apply #'format nil suite-name case)
                          ,reason
                          (destructuring-bind ,bindings ',case
                            ,@forms))))))

(defmacro describe-todo-each (cases suite-name bindings &body body)
  (multiple-value-bind (reason forms) (split-reasoned-body body "todo")
    `(progn
       ,@(loop for case in cases
               collect `(describe-todo ,(apply #'format nil suite-name case)
                          ,reason
                          (destructuring-bind ,bindings ',case
                            ,@forms))))))

(defun option-plist-form-p (form)
  (and (consp form)
       (evenp (length form))
       (loop for (key nil) on form by #'cddr
             always (keywordp key))))

(defun plist-key-present-p (plist key)
  (loop for (candidate nil) on plist by #'cddr
        thereis (eq candidate key)))

(defun ensure-unique-option-keys (options)
  (loop with seen = '()
        for (key nil) on options by #'cddr
        when (member key seen)
          do (error "Duplicate test option ~S." key)
        do (push key seen))
  options)

(defun test-registration-options (options)
  (ensure-unique-option-keys options)
  (loop for (key nil) on options by #'cddr
        unless (member key '(:retry :timeout-ms :execution-mode))
          do (error "Unknown test option ~S." key))
  (append
   (when (plist-key-present-p options :retry)
     `(:retry ,(getf options :retry)))
   (when (plist-key-present-p options :timeout-ms)
     `(:timeout-ms ,(getf options :timeout-ms)))
   (when (plist-key-present-p options :execution-mode)
     `(:execution-mode ,(getf options :execution-mode)))))

(defun source-location-form ()
  `',(let ((pathname (or *compile-file-pathname* *load-pathname*)))
       (when pathname
         (list :file (namestring pathname)))))

(defun source-location-option ()
  `(:location ,(source-location-form)))

(defun split-test-body (body)
  (if (and body (option-plist-form-p (first body)))
      (values (first body) (rest body))
      (values nil body)))

(defun test-registration-form (name forms options)
  `(register-test ,name (lambda () ,@forms)
                  ,@options
                  ,@(source-location-option)))

(defun test-options-with-registration-options (options prefix-options)
  (let* ((registration-options (test-registration-options options))
         (fixed-mode (getf prefix-options :execution-mode))
         (requested-mode (getf registration-options :execution-mode)))
    (when (and fixed-mode requested-mode (not (eql fixed-mode requested-mode)))
      (error "Execution mode ~S conflicts with fixed mode ~S."
             requested-mode fixed-mode))
    (append prefix-options
            (if fixed-mode
                (loop for (key value) on registration-options by #'cddr
                      unless (eq key :execution-mode)
                        append (list key value))
                registration-options))))

(defmacro it (test-name &body body)
  (multiple-value-bind (options forms) (split-test-body body)
    (test-registration-form
     test-name
     forms
     (test-options-with-registration-options options '()))))

(defmacro it-only (test-name &body body)
  (multiple-value-bind (options forms) (split-test-body body)
    (test-registration-form
     test-name
     forms
     (test-options-with-registration-options options '(:focus t)))))

(defmacro it-concurrent (test-name &body body)
  (multiple-value-bind (options forms) (split-test-body body)
    (test-registration-form
     test-name
     forms
     (test-options-with-registration-options options '(:execution-mode :concurrent)))))

(defmacro it-sequential (test-name &body body)
  (multiple-value-bind (options forms) (split-test-body body)
    (test-registration-form
     test-name
     forms
     (test-options-with-registration-options options '(:execution-mode :sequential)))))

(defmacro it-fails (test-name &body body)
  (multiple-value-bind (options forms) (split-test-body body)
    (test-registration-form
     test-name
     forms
     (test-options-with-registration-options
      options
      '(:expected-failure-reason "expected failure")))))

(defmacro it-skip (test-name &optional (reason "skipped"))
  (test-registration-form test-name '(nil) (list :skip-reason reason)))

(defmacro it-todo (test-name &optional (reason "todo"))
  (test-registration-form test-name '(nil) (list :todo-reason reason)))

(defmacro it-skip-if (condition name &body body)
  `(if ,condition
       (it-skip ,name "conditional skip")
       (it ,name ,@body)))

(defmacro it-run-if (condition name &body body)
  `(if ,condition
       (it ,name ,@body)
       (it-skip ,name "conditional run-if")))

(defun isolated-option-form (options key fallback)
  (if (getf options key)
      (getf options key)
      fallback))

(defun isolated-systems-option-form (options)
  (let ((systems (getf options :systems)))
    (cond
      ((null systems) ''("cl-weave"))
      ((and (listp systems)
            (not (eq (first systems) 'quote)))
       `',systems)
      (t systems))))

(defmacro it-isolated (name &body body)
  (let* ((options (when (and body (option-plist-form-p (first body)))
                    (first body)))
         (forms (if options (rest body) body))
         (timeout (isolated-option-form options :timeout '*isolated-timeout-seconds*))
         (package (isolated-option-form options :package (package-name *package*)))
         (keep-files (isolated-option-form options :keep-files nil))
         (systems (isolated-systems-option-form options))
         (form `(progn ,@forms)))
    `(it ,name
       (let ((result (run-isolated ',form
                                   :systems ,systems
                                   :package ,package
                                   :timeout ,timeout
                                   :keep-files ,keep-files)))
         (if (eq (isolated-result-status result) :pass)
             t
             (signal-isolated-failure result ',form))))))

(defmacro it-each (cases test-name bindings &body body)
  `(progn
     ,@(suite-each-cases cases test-name bindings body 'it)))

(defmacro it-only-each (cases test-name bindings &body body)
  `(progn
     ,@(suite-each-cases cases test-name bindings body 'it-only)))

(defmacro it-concurrent-each (cases test-name bindings &body body)
  `(progn
     ,@(suite-each-cases cases test-name bindings body 'it-concurrent)))

(defmacro it-sequential-each (cases test-name bindings &body body)
  `(progn
     ,@(suite-each-cases cases test-name bindings body 'it-sequential)))

(defmacro it-fails-each (cases test-name bindings &body body)
  `(progn
     ,@(suite-each-cases cases test-name bindings body 'it-fails)))

(defmacro it-skip-each (cases test-name bindings &body body)
  (validate-suite-each-syntax cases test-name bindings 'it-skip-each)
  (multiple-value-bind (reason forms) (split-reasoned-body body "skipped")
    (when forms
      (error "IT-SKIP-EACH does not accept a test body; only an optional reason string is allowed."))
    `(progn
       ,@(loop for case in cases
               collect `(it-skip ,(apply #'format nil test-name case) ,reason)))))

(defmacro it-todo-each (cases test-name bindings &body body)
  (validate-suite-each-syntax cases test-name bindings 'it-todo-each)
  (multiple-value-bind (reason forms) (split-reasoned-body body "todo")
    (when forms
      (error "IT-TODO-EACH does not accept a test body; only an optional reason string is allowed."))
    `(progn
       ,@(loop for case in cases
               collect `(it-todo ,(apply #'format nil test-name case) ,reason)))))

(defmacro it-property (name bindings &body body)
  (unless (registration-proper-list-p bindings)
    (error "IT-PROPERTY requires BINDINGS to be a literal proper list, got ~S." bindings))
  (loop for binding in bindings
        for index from 0
        unless (and (registration-proper-list-p binding)
                    (= (length binding) 2)
                    (symbolp (first binding))
                    (first binding))
          do (error "IT-PROPERTY binding ~D must have the form (NAME GENERATOR), got ~S."
                    index binding))
  (let ((names (mapcar #'first bindings))
        (generators (mapcar #'second bindings)))
    `(it ,name
       (run-property
        (list ,@generators)
        (lambda ,names ,@body)
        ',names
        '(it-property ,name ,bindings ,@body)))))
