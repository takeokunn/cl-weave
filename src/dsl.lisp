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

(defmacro describe-todo-each (cases name bindings &body body)
  (let ((reason (if (and body (stringp (first body))) (first body) "todo"))
        (forms (if (and body (stringp (first body))) (rest body) body)))
    `(progn
       ,@(loop for case in cases
               collect `(describe-todo ,(apply #'format nil name case)
                          ,reason
                          (destructuring-bind ,bindings ',case
                            ,@forms))))))

(defmacro define-suite-alias (alias target)
  `(defmacro ,alias (name &body body)
     (list* ',target name body)))

(defmacro define-suite-each-alias (alias target)
  `(defmacro ,alias (cases name bindings &body body)
     (list* ',target cases name bindings body)))

(defmacro define-conditional-suite-alias (alias target)
  `(defmacro ,alias (condition name &body body)
     (list* ',target condition name body)))

(define-suite-each-alias describe.each describe-each)
(define-suite-each-alias describe.only.each describe-only-each)
(define-suite-each-alias describe.concurrent.each describe-concurrent-each)
(define-suite-each-alias describe.sequential.each describe-sequential-each)
(define-suite-each-alias describe.skip.each describe-skip-each)
(define-suite-each-alias describe.todo.each describe-todo-each)

(define-suite-alias describe.only describe-only)
(define-suite-alias describe.concurrent describe-concurrent)
(define-suite-alias describe.sequential describe-sequential)
(define-suite-alias describe.skip describe-skip)
(define-suite-alias describe.todo describe-todo)

(define-conditional-suite-alias describe.skip-if describe-skip-if)
(define-conditional-suite-alias describe.run-if describe-run-if)

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

(defmacro it-todo-each (cases name bindings &body body)
  (declare (ignore bindings))
  (let ((reason (if (and body (stringp (first body))) (first body) "todo")))
    `(progn
       ,@(loop for case in cases
               collect `(it-todo ,(apply #'format nil name case) ,reason)))))

(defmacro it-property (name bindings &body body)
  (let ((names (mapcar #'first bindings))
        (generators (mapcar #'second bindings)))
    `(it ,name
       (run-property
        (list ,@generators)
        (lambda ,names ,@body)
        ',names
        '(it-property ,name ,bindings ,@body)))))

(defmacro define-test-like-alias (alias target)
  `(defmacro ,alias (name &body body)
     (list* ',target name body)))

(defmacro define-test-like-each-alias (alias target)
  `(defmacro ,alias (cases name bindings &body body)
     (list* ',target cases name bindings body)))

(defmacro define-test-property-alias (alias target)
  `(defmacro ,alias (name bindings &body body)
     (list* ',target name bindings body)))

(defmacro define-test-control-alias (alias target default-reason)
  `(defmacro ,alias (name &optional (reason ,default-reason))
     (list ',target name reason)))

(defmacro define-conditional-test-alias (alias target)
  `(defmacro ,alias (condition name &body body)
     (list* ',target condition name body)))

(define-test-like-alias it.concurrent it-concurrent)
(define-test-like-alias it.sequential it-sequential)
(define-test-like-alias it.fails it-fails)
(define-test-like-alias it.isolated it-isolated)
(define-test-like-alias it.only it-only)

(define-test-like-each-alias it.each it-each)
(define-test-like-each-alias it.only.each it-only-each)
(define-test-like-each-alias it.concurrent.each it-concurrent-each)
(define-test-like-each-alias it.sequential.each it-sequential-each)
(define-test-like-each-alias it.fails.each it-fails-each)
(define-test-like-each-alias it.skip.each it-skip-each)
(define-test-like-each-alias it.todo.each it-todo-each)

(define-test-property-alias it.property it-property)
(define-conditional-test-alias it.run-if it-run-if)
(define-conditional-test-alias it.skip-if it-skip-if)
(define-test-control-alias it.skip it-skip "skipped")
(define-test-control-alias it.todo it-todo "todo")

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

(defmacro test-todo-each (cases name bindings &body body)
  `(it-todo-each ,cases ,name ,bindings ,@body))

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

(define-test-like-alias test.concurrent test-concurrent)
(define-test-like-alias test.sequential test-sequential)
(define-test-like-alias test.fails test-fails)
(define-test-like-alias test.isolated test-isolated)
(define-test-like-alias test.only test-only)

(define-test-like-each-alias test.each test-each)
(define-test-like-each-alias test.only.each test-only-each)
(define-test-like-each-alias test.concurrent.each test-concurrent-each)
(define-test-like-each-alias test.sequential.each test-sequential-each)
(define-test-like-each-alias test.fails.each test-fails-each)
(define-test-like-each-alias test.skip.each test-skip-each)
(define-test-like-each-alias test.todo.each test-todo-each)

(define-test-property-alias test.property test-property)
(define-conditional-test-alias test.run-if test-run-if)
(define-conditional-test-alias test.skip-if test-skip-if)
(define-test-control-alias test.skip test-skip "skipped")
(define-test-control-alias test.todo test-todo "todo")

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

(defun signal-continuation-not-called (form)
  (signal-assertion-failure
   (make-assertion-detail
    :form form
    :matcher :continuation-called
    :actual '(:called nil)
    :expected '(:called t)
    :negated nil
    :pass nil)))

(defun ensure-continuation-called (calledp form)
  (unless calledp
    (signal-continuation-not-called form))
  t)

(defun require-continuation-binding-symbol (name form)
  (unless (and name (symbolp name))
    (error "cl-weave: continuation binding in ~S must be a symbol, got ~S."
           form
           name))
  name)

(defmacro with-continuation-values ((values continuation &optional calledp) form &body body)
  (let* ((source `(with-continuation-values
                   (,values ,continuation ,@(when calledp (list calledp)))
                   ,form
                   ,@body))
         (continuation-name (require-continuation-binding-symbol continuation source))
         (captured-values (gensym "CONTINUATION-VALUES-"))
         (called (gensym "CONTINUATION-CALLED-")))
    `(let ((,captured-values nil)
           (,called nil))
       (flet ((,continuation-name (&rest next-values)
                (setf ,called t
                      ,captured-values next-values)))
         ,form)
       (ensure-continuation-called ,called ',form)
       (let ((,values ,captured-values)
             ,@(when calledp `((,calledp ,called))))
         ,@body))))

(defmacro with-continuation-result ((value continuation &optional calledp) form &body body)
  (let ((values (gensym "CONTINUATION-VALUES-")))
    `(with-continuation-values (,values ,continuation ,@(when calledp `(,calledp))) ,form
       (let ((,value (first ,values)))
         ,@body))))

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

(defmacro expect.hasassertions ()
  `(expect-has-assertions))

(defmacro expect.not (actual &body expectation)
  `(expect-not ,actual ,@expectation))

(defmacro expect-resolves (thunk &body expectation)
  `(expect (call-resolving-expectation-thunk
            ,thunk
            '(expect-resolves ,thunk ,@expectation))
           ,@expectation))

(defmacro expect.resolves (thunk &body expectation)
  `(expect-resolves ,thunk ,@expectation))

(defmacro expect-rejects (thunk &body expectation)
  `(expect (call-rejecting-expectation-thunk
            ,thunk
            '(expect-rejects ,thunk ,@expectation))
           ,@expectation))

(defmacro expect.rejects (thunk &body expectation)
  `(expect-rejects ,thunk ,@expectation))

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
