(in-package #:cl-weave)

(defmacro describe (name &body body)
  `(register-suite ,name (lambda () ,@body)))

(defmacro describe-only (name &body body)
  `(register-suite ,name (lambda () ,@body) :focus t))

(defmacro describe-concurrent (name &body body)
  `(register-suite ,name (lambda () ,@body) :execution-mode :concurrent))

(defmacro describe-sequential (name &body body)
  `(register-suite ,name (lambda () ,@body) :execution-mode :sequential))

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

(defmacro describe-only-each (cases name bindings &body body)
  `(progn
     ,@(loop for case in cases
             collect `(describe-only ,(apply #'format nil name case)
                        (destructuring-bind ,bindings ',case
                          ,@body)))))

(defmacro describe-concurrent-each (cases name bindings &body body)
  `(progn
     ,@(loop for case in cases
             collect `(describe-concurrent ,(apply #'format nil name case)
                        (destructuring-bind ,bindings ',case
                          ,@body)))))

(defmacro describe-sequential-each (cases name bindings &body body)
  `(progn
     ,@(loop for case in cases
             collect `(describe-sequential ,(apply #'format nil name case)
                        (destructuring-bind ,bindings ',case
                          ,@body)))))

(defmacro describe-skip-each (cases name bindings &body body)
  (let ((reason (if (and body (stringp (first body))) (first body) "skipped"))
        (forms (if (and body (stringp (first body))) (rest body) body)))
    `(progn
       ,@(loop for case in cases
               collect `(describe-skip ,(apply #'format nil name case)
                          ,reason
                          (destructuring-bind ,bindings ',case
                            ,@forms))))))

(defmacro describe.each (cases name bindings &body body)
  `(describe-each ,cases ,name ,bindings ,@body))

(defmacro describe.only.each (cases name bindings &body body)
  `(describe-only-each ,cases ,name ,bindings ,@body))

(defmacro describe.concurrent.each (cases name bindings &body body)
  `(describe-concurrent-each ,cases ,name ,bindings ,@body))

(defmacro describe.sequential.each (cases name bindings &body body)
  `(describe-sequential-each ,cases ,name ,bindings ,@body))

(defmacro describe.skip.each (cases name bindings &body body)
  `(describe-skip-each ,cases ,name ,bindings ,@body))

(defmacro describe.only (name &body body)
  `(describe-only ,name ,@body))

(defmacro describe.concurrent (name &body body)
  `(describe-concurrent ,name ,@body))

(defmacro describe.sequential (name &body body)
  `(describe-sequential ,name ,@body))

(defmacro describe.skip (name &body body)
  `(describe-skip ,name ,@body))

(defmacro describe.todo (name &body body)
  `(describe-todo ,name ,@body))

(defmacro describe.skip-if (condition name &body body)
  `(describe-skip-if ,condition ,name ,@body))

(defmacro describe.run-if (condition name &body body)
  `(describe-run-if ,condition ,name ,@body))

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
     `(:execution-mode (if ,(getf options :concurrent) :concurrent :sequential)))))

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

(defmacro it (name &body body)
  (multiple-value-bind (options forms) (split-test-body body)
    `(register-test ,name (lambda () ,@forms)
                    ,@(source-location-option)
                    ,@(test-registration-options options))))

(defmacro it-only (name &body body)
  (multiple-value-bind (options forms) (split-test-body body)
    `(register-test ,name (lambda () ,@forms)
                    :focus t
                    ,@(source-location-option)
                    ,@(test-registration-options options))))

(defmacro it-concurrent (name &body body)
  (multiple-value-bind (options forms) (split-test-body body)
    `(register-test ,name (lambda () ,@forms)
                    :execution-mode :concurrent
                    ,@(source-location-option)
                    ,@(test-registration-options options))))

(defmacro it-sequential (name &body body)
  (multiple-value-bind (options forms) (split-test-body body)
    `(register-test ,name (lambda () ,@forms)
                    :execution-mode :sequential
                    ,@(source-location-option)
                    ,@(test-registration-options options))))

(defmacro it-fails (name &body body)
  (multiple-value-bind (options forms) (split-test-body body)
    `(register-test ,name (lambda () ,@forms)
                    :expected-failure-reason "expected failure"
                    ,@(source-location-option)
                    ,@(test-registration-options options))))

(defmacro it-skip (name &optional (reason "skipped"))
  `(register-test ,name (lambda () nil)
                  :skip-reason ,reason
                  ,@(source-location-option)))

(defmacro it-todo (name &optional (reason "todo"))
  `(register-test ,name (lambda () nil)
                  :todo-reason ,reason
                  ,@(source-location-option)))

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

(defmacro it-only-each (cases name bindings &body body)
  `(progn
     ,@(loop for case in cases
             collect `(it-only ,(apply #'format nil name case)
                        (destructuring-bind ,bindings ',case
                          ,@body)))))

(defmacro it-concurrent-each (cases name bindings &body body)
  `(progn
     ,@(loop for case in cases
             collect `(it-concurrent ,(apply #'format nil name case)
                        (destructuring-bind ,bindings ',case
                          ,@body)))))

(defmacro it-sequential-each (cases name bindings &body body)
  `(progn
     ,@(loop for case in cases
             collect `(it-sequential ,(apply #'format nil name case)
                        (destructuring-bind ,bindings ',case
                          ,@body)))))

(defmacro it-fails-each (cases name bindings &body body)
  `(progn
     ,@(loop for case in cases
             collect `(it-fails ,(apply #'format nil name case)
                        (destructuring-bind ,bindings ',case
                          ,@body)))))

(defmacro it-skip-each (cases name bindings &body body)
  (declare (ignore bindings))
  (let ((reason (if (and body (stringp (first body))) (first body) "skipped")))
    `(progn
       ,@(loop for case in cases
               collect `(it-skip ,(apply #'format nil name case) ,reason)))))

(defmacro it-property (name bindings &body body)
  (let ((names (mapcar #'first bindings))
        (generators (mapcar #'second bindings)))
    `(it ,name
       (run-property
        (list ,@generators)
        (lambda ,names ,@body)
        ',names
        '(it-property ,name ,bindings ,@body)))))

(defmacro it.concurrent (name &body body)
  `(it-concurrent ,name ,@body))

(defmacro it.sequential (name &body body)
  `(it-sequential ,name ,@body))

(defmacro it.each (cases name bindings &body body)
  `(it-each ,cases ,name ,bindings ,@body))

(defmacro it.only.each (cases name bindings &body body)
  `(it-only-each ,cases ,name ,bindings ,@body))

(defmacro it.concurrent.each (cases name bindings &body body)
  `(it-concurrent-each ,cases ,name ,bindings ,@body))

(defmacro it.sequential.each (cases name bindings &body body)
  `(it-sequential-each ,cases ,name ,bindings ,@body))

(defmacro it.fails.each (cases name bindings &body body)
  `(it-fails-each ,cases ,name ,bindings ,@body))

(defmacro it.skip.each (cases name bindings &body body)
  `(it-skip-each ,cases ,name ,bindings ,@body))

(defmacro it.fails (name &body body)
  `(it-fails ,name ,@body))

(defmacro it.isolated (name &body body)
  `(it-isolated ,name ,@body))

(defmacro it.property (name bindings &body body)
  `(it-property ,name ,bindings ,@body))

(defmacro it.only (name &body body)
  `(it-only ,name ,@body))

(defmacro it.run-if (condition name &body body)
  `(it-run-if ,condition ,name ,@body))

(defmacro it.skip (name &optional (reason "skipped"))
  `(it-skip ,name ,reason))

(defmacro it.skip-if (condition name &body body)
  `(it-skip-if ,condition ,name ,@body))

(defmacro it.todo (name &optional (reason "todo"))
  `(it-todo ,name ,reason))

(defmacro test (name &body body)
  `(it ,name ,@body))

(defmacro test-concurrent (name &body body)
  `(it-concurrent ,name ,@body))

(defmacro test-sequential (name &body body)
  `(it-sequential ,name ,@body))

(defmacro test-each (cases name bindings &body body)
  `(it-each ,cases ,name ,bindings ,@body))

(defmacro test-only-each (cases name bindings &body body)
  `(it-only-each ,cases ,name ,bindings ,@body))

(defmacro test-concurrent-each (cases name bindings &body body)
  `(it-concurrent-each ,cases ,name ,bindings ,@body))

(defmacro test-sequential-each (cases name bindings &body body)
  `(it-sequential-each ,cases ,name ,bindings ,@body))

(defmacro test-fails-each (cases name bindings &body body)
  `(it-fails-each ,cases ,name ,bindings ,@body))

(defmacro test-skip-each (cases name bindings &body body)
  `(it-skip-each ,cases ,name ,bindings ,@body))

(defmacro test-only (name &body body)
  `(it-only ,name ,@body))

(defmacro test-fails (name &body body)
  `(it-fails ,name ,@body))

(defmacro test-isolated (name &body body)
  `(it-isolated ,name ,@body))

(defmacro test-property (name bindings &body body)
  `(it-property ,name ,bindings ,@body))

(defmacro test-skip (name &optional (reason "skipped"))
  `(it-skip ,name ,reason))

(defmacro test-todo (name &optional (reason "todo"))
  `(it-todo ,name ,reason))

(defmacro test-skip-if (condition name &body body)
  `(it-skip-if ,condition ,name ,@body))

(defmacro test-run-if (condition name &body body)
  `(it-run-if ,condition ,name ,@body))

(defmacro test.concurrent (name &body body)
  `(test-concurrent ,name ,@body))

(defmacro test.sequential (name &body body)
  `(test-sequential ,name ,@body))

(defmacro test.each (cases name bindings &body body)
  `(test-each ,cases ,name ,bindings ,@body))

(defmacro test.only.each (cases name bindings &body body)
  `(test-only-each ,cases ,name ,bindings ,@body))

(defmacro test.concurrent.each (cases name bindings &body body)
  `(test-concurrent-each ,cases ,name ,bindings ,@body))

(defmacro test.sequential.each (cases name bindings &body body)
  `(test-sequential-each ,cases ,name ,bindings ,@body))

(defmacro test.fails.each (cases name bindings &body body)
  `(test-fails-each ,cases ,name ,bindings ,@body))

(defmacro test.skip.each (cases name bindings &body body)
  `(test-skip-each ,cases ,name ,bindings ,@body))

(defmacro test.fails (name &body body)
  `(test-fails ,name ,@body))

(defmacro test.isolated (name &body body)
  `(test-isolated ,name ,@body))

(defmacro test.only (name &body body)
  `(test-only ,name ,@body))

(defmacro test.property (name bindings &body body)
  `(test-property ,name ,bindings ,@body))

(defmacro test.run-if (condition name &body body)
  `(test-run-if ,condition ,name ,@body))

(defmacro test.skip (name &optional (reason "skipped"))
  `(test-skip ,name ,reason))

(defmacro test.skip-if (condition name &body body)
  `(test-skip-if ,condition ,name ,@body))

(defmacro test.todo (name &optional (reason "todo"))
  `(test-todo ,name ,reason))

(defmacro before-all (&body body)
  `(register-before-all (lambda () ,@body)))

(defmacro after-all (&body body)
  `(register-after-all (lambda () ,@body)))

(defmacro before-each (&body body)
  `(register-before-each (lambda () ,@body)))

(defmacro around-each ((next) &body body)
  `(register-around-each (lambda (,next) ,@body)))

(defmacro after-each (&body body)
  `(register-after-each (lambda () ,@body)))

(defmacro beforeall (&body body)
  `(before-all ,@body))

(defmacro afterall (&body body)
  `(after-all ,@body))

(defmacro beforeeach (&body body)
  `(before-each ,@body))

(defmacro aftereach (&body body)
  `(after-each ,@body))

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
    `(progn
       (record-assertion)
       (let ,(loop for value in values
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
         t))))

(defun expand-smart-truthy-assertion (actual form)
  (let ((value (gensym "ACTUAL-")))
    `(progn
       (record-assertion)
       (let ((,value ,actual))
         (unless ,value
           (signal-smart-assertion-failure
            ',form
            :truthy
            ,value
            t))
         t))))

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
    `(progn
       (record-assertion)
       (let ((,value ,actual))
         (assert-expectation
          ,value
          (list ,@tokens)
          '(,macro-name ,actual ,@expectation))))))

(defun ensure-expect-thunk (thunk matcher form)
  (unless (functionp thunk)
    (signal-assertion-failure
     (make-assertion-detail
      :form form
      :matcher matcher
      :actual (list :callable nil :value thunk)
      :expected '(:callable t)
      :negated nil
      :pass nil)))
  thunk)

(defun rejected-thunk-report (condition)
  (list :state :rejected
        :condition-type (type-of condition)
        :message (princ-to-string condition)))

(defun resolved-thunk-report (value)
  (list :state :resolved :value value))

(defun call-resolving-expectation-thunk (thunk form)
  (let ((callable (ensure-expect-thunk thunk :resolves form)))
    (handler-case
        (funcall callable)
      (condition (condition)
        (signal-assertion-failure
         (make-assertion-detail
          :form form
          :matcher :resolves
          :actual (rejected-thunk-report condition)
          :expected '(:state :resolved)
          :negated nil
          :pass nil))))))

(defun call-rejecting-expectation-thunk (thunk form)
  (let ((callable (ensure-expect-thunk thunk :rejects form)))
    (multiple-value-bind (rejected-p result)
        (handler-case
            (values nil (funcall callable))
          (condition (condition)
            (values t condition)))
      (if rejected-p
          result
          (signal-assertion-failure
           (make-assertion-detail
            :form form
            :matcher :rejects
            :actual (resolved-thunk-report result)
            :expected '(:state :rejected)
            :negated nil
            :pass nil))))))

(defmacro expect (actual &body expectation)
  (if expectation
      (expand-matcher-expectation 'expect actual expectation)
      (expand-smart-assertion actual `(expect ,actual))))

(defmacro expect-not (actual &body expectation)
  (expand-matcher-expectation 'expect-not actual expectation :negated t))

(defmacro expect-assertions (count)
  `(set-expected-assertion-count ,count '(expect-assertions ,count)))

(defmacro expect.assertions (count)
  `(expect-assertions ,count))

(defmacro expect-has-assertions ()
  `(set-has-assertions-required '(expect-has-assertions)))

(defmacro expect.hasAssertions ()
  `(expect-has-assertions))

(defmacro expect.not (actual &body expectation)
  `(expect-not ,actual ,@expectation))

(defmacro expect.resolves (thunk &body expectation)
  `(expect (call-resolving-expectation-thunk
            ,thunk
            '(expect.resolves ,thunk ,@expectation))
           ,@expectation))

(defmacro expect.rejects (thunk &body expectation)
  `(expect (call-rejecting-expectation-thunk
            ,thunk
            '(expect.rejects ,thunk ,@expectation))
           ,@expectation))

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
