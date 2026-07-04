(in-package #:cl-weave)

(defmacro describe (name &body body)
  `(register-suite ,name (lambda () ,@body)))

(defmacro describe-only (name &body body)
  `(register-suite ,name (lambda () ,@body) :focus t))

(defmacro describe-skip (name &body body)
  (let ((reason (if (and body (stringp (first body))) (first body) "skipped"))
        (forms (if (and body (stringp (first body))) (rest body) body)))
    `(register-suite ,name (lambda () ,@forms) :skip-reason ,reason)))

(defmacro describe-todo (name &body body)
  (let ((reason (if (and body (stringp (first body))) (first body) "todo"))
        (forms (if (and body (stringp (first body))) (rest body) body)))
    `(register-suite ,name (lambda () ,@forms) :todo-reason ,reason)))

(defmacro describe-skip-if (condition name &body body)
  `(if ,condition
       (describe-skip ,name "conditional skip" ,@body)
       (describe ,name ,@body)))

(defmacro describe-run-if (condition name &body body)
  `(if ,condition
       (describe ,name ,@body)
       (describe-skip ,name "conditional run-if" ,@body)))

(defmacro describe-each (cases name bindings &body body)
  `(progn
     ,@(loop for case in cases
             collect `(describe ,(apply #'format nil name case)
                        (destructuring-bind ,bindings ',case
                          ,@body)))))

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
     `(:timeout-ms ,(getf options :timeout-ms)))))

(defun split-test-body (body)
  (if (and body (option-plist-form-p (first body)))
      (values (first body) (rest body))
      (values nil body)))

(defmacro it (name &body body)
  (multiple-value-bind (options forms) (split-test-body body)
    `(register-test ,name (lambda () ,@forms)
                    ,@(test-registration-options options))))

(defmacro it-only (name &body body)
  (multiple-value-bind (options forms) (split-test-body body)
    `(register-test ,name (lambda () ,@forms)
                    :focus t
                    ,@(test-registration-options options))))

(defmacro it-fails (name &body body)
  (multiple-value-bind (options forms) (split-test-body body)
    `(register-test ,name (lambda () ,@forms)
                    :expected-failure-reason "expected failure"
                    ,@(test-registration-options options))))

(defmacro it-skip (name &optional (reason "skipped"))
  `(register-test ,name (lambda () nil) :skip-reason ,reason))

(defmacro it-todo (name &optional (reason "todo"))
  `(register-test ,name (lambda () nil) :todo-reason ,reason))

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
         (systems (isolated-systems-option-form options))
         (form `(progn ,@forms)))
    `(it ,name
       (assert-isolated-success
        (run-isolated ',form
                      :systems ,systems
                      :package ,package
                      :timeout ,timeout)
        ',form))))

(defmacro it-each (cases name bindings &body body)
  `(progn
     ,@(loop for case in cases
             collect `(it ,(apply #'format nil name case)
                         (destructuring-bind ,bindings ',case
                           ,@body)))))

(defmacro it-property (name bindings &body body)
  (let ((names (mapcar #'first bindings))
        (generators (mapcar #'second bindings)))
    `(it ,name
       (run-property
        (list ,@generators)
        (lambda ,names ,@body)
        ',names
        '(it-property ,name ,bindings ,@body)))))

(defmacro test (name &body body)
  `(it ,name ,@body))

(defmacro test-each (cases name bindings &body body)
  `(it-each ,cases ,name ,bindings ,@body))

(defmacro test-only (name &body body)
  `(it-only ,name ,@body))

(defmacro test-fails (name &body body)
  `(it-fails ,name ,@body))

(defmacro test-skip (name &optional (reason "skipped"))
  `(it-skip ,name ,reason))

(defmacro test-todo (name &optional (reason "todo"))
  `(it-todo ,name ,reason))

(defmacro test-skip-if (condition name &body body)
  `(it-skip-if ,condition ,name ,@body))

(defmacro test-run-if (condition name &body body)
  `(it-run-if ,condition ,name ,@body))

(defmacro before-all (&body body)
  `(register-before-all (lambda () ,@body)))

(defmacro after-all (&body body)
  `(register-after-all (lambda () ,@body)))

(defmacro before-each (&body body)
  `(register-before-each (lambda () ,@body)))

(defmacro after-each (&body body)
  `(register-after-each (lambda () ,@body)))

(defparameter *smart-assertion-operators*
  '(= /= < <= > >= eql equal equalp string= string-equal))

(defun smart-assertion-operator-p (operator)
  (member operator *smart-assertion-operators* :test #'eq))

(defun signal-smart-assertion-failure (form matcher actual expected)
  (signal-assertion-failure
   (make-assertion-detail
    :form form
    :matcher matcher
    :actual actual
    :expected expected
    :negated nil
    :pass nil)))

(defun operand-report-form (source value)
  (list :form source :value value))

(defun smart-predicate-form-p (form)
  (and (consp form)
       (symbolp (first form))
       (smart-assertion-operator-p (first form))
       (rest form)))

(defun expand-smart-predicate-assertion (actual form)
  (let* ((operator (first actual))
         (operands (rest actual))
         (values (loop for operand in operands collect (gensym "OPERAND-"))))
    `(let ,(loop for value in values
                 for operand in operands
                 collect `(,value ,operand))
       (unless (,operator ,@values)
         (signal-smart-assertion-failure
          ',form
          ',operator
          (list ,@(loop for operand in operands
                        for value in values
                        collect `(operand-report-form ',operand ,value)))
          ',actual))
       t)))

(defun expand-smart-truthy-assertion (actual form)
  (let ((value (gensym "ACTUAL-")))
    `(let ((,value ,actual))
       (unless ,value
         (signal-smart-assertion-failure
          ',form
          :truthy
          ,value
          t))
       t)))

(defun expand-smart-assertion (actual form)
  (if (smart-predicate-form-p actual)
      (expand-smart-predicate-assertion actual form)
      (expand-smart-truthy-assertion actual form)))

(defun expand-matcher-expectation (macro-name actual expectation &key negated)
  (when (null expectation)
    (error "cl-weave: ~A requires a matcher, for example (~(~A~) value :to-be expected)."
           macro-name
           macro-name))
  (let ((value (gensym "ACTUAL-"))
        (tokens (if negated
                    `(:not ,@expectation)
                    expectation)))
    `(let ((,value ,actual))
       (assert-expectation
        ,value
        (list ,@tokens)
        '(,macro-name ,actual ,@expectation)))))

(defmacro expect (actual &body expectation)
  (if expectation
      (expand-matcher-expectation 'expect actual expectation)
      (expand-smart-assertion actual `(expect ,actual))))

(defmacro expect-not (actual &body expectation)
  (expand-matcher-expectation 'expect-not actual expectation :negated t))

(defmacro with-snapshot-updates (&body body)
  `(let ((*update-snapshots* t))
     ,@body))

(defmacro with-mocked-functions (bindings &body body)
  (let ((saved (gensym "SAVED-")))
    `(let ((,saved
             (list
              ,@(loop for (place replacement) in bindings
                      collect place))))
       (unwind-protect
            (progn
              ,@(loop for (place replacement) in bindings
                      collect `(setf ,place ,replacement))
              ,@body)
         ,@(loop for (place nil) in bindings
                 for index from 0
                 collect `(setf ,place (nth ,index ,saved)))))))
