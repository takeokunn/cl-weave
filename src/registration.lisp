(in-package #:cl-weave)

(defun split-reasoned-body (body default-reason)
  (if (and body (stringp (first body)))
      (values (first body) (rest body))
      (values default-reason body)))

(defun suite-registration-form (name forms options)
  `(register-suite ,name (lambda () ,@forms) ,@options))

(defun suite-each-cases (cases name bindings forms target)
  (loop for case in cases
        collect `(,target ,(apply #'format nil name case)
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

(defun test-registration-options (options)
  (append
   (when (plist-key-present-p options :retry)
     `(:retry ,(getf options :retry)))
   (when (plist-key-present-p options :timeout-ms)
     `(:timeout-ms ,(getf options :timeout-ms)))
   (when (plist-key-present-p options :concurrent)
     `(:execution-mode (if ,(getf options :concurrent) :concurrent :sequential)))
   (when (plist-key-present-p options :tags)
     `(:tags ,(getf options :tags)))
   (when (plist-key-present-p options :depends-on)
     `(:depends-on ,(getf options :depends-on)))))

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
  (append prefix-options (test-registration-options options)))

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
       (assert-isolated-success
        (run-isolated ',form
                      :systems ,systems
                      :package ,package
                      :timeout ,timeout
                      :keep-files ,keep-files)
        ',form))))

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
  (declare (ignore bindings))
  (multiple-value-bind (reason forms) (split-reasoned-body body "skipped")
    (declare (ignore forms))
    `(progn
       ,@(loop for case in cases
               collect `(it-skip ,(apply #'format nil test-name case) ,reason)))))

(defmacro it-todo-each (cases test-name bindings &body body)
  (declare (ignore bindings))
  (multiple-value-bind (reason forms) (split-reasoned-body body "todo")
    (declare (ignore forms))
    `(progn
       ,@(loop for case in cases
               collect `(it-todo ,(apply #'format nil test-name case) ,reason)))))

(defmacro it-property (name bindings &body body)
  (let ((names (mapcar #'first bindings))
        (generators (mapcar #'second bindings)))
    `(it ,name
       (run-property
        (list ,@generators)
        (lambda ,names ,@body)
        ',names
        '(it-property ,name ,bindings ,@body)))))

