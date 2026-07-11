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

(defmacro describe.each (cases name bindings &body body)
  (list* 'describe-each cases name bindings body))

(defmacro describe.only.each (cases name bindings &body body)
  (list* 'describe-only-each cases name bindings body))

(defmacro describe.concurrent.each (cases name bindings &body body)
  (list* 'describe-concurrent-each cases name bindings body))

(defmacro describe.sequential.each (cases name bindings &body body)
  (list* 'describe-sequential-each cases name bindings body))

(defmacro describe.skip.each (cases name bindings &body body)
  (list* 'describe-skip-each cases name bindings body))

(defmacro describe.todo.each (cases name bindings &body body)
  (list* 'describe-todo-each cases name bindings body))

(defmacro describe.only (name &body body)
  (list* 'describe-only name body))

(defmacro describe.concurrent (name &body body)
  (list* 'describe-concurrent name body))

(defmacro describe.sequential (name &body body)
  (list* 'describe-sequential name body))

(defmacro describe.skip (name &body body)
  (list* 'describe-skip name body))

(defmacro describe.todo (name &body body)
  (list* 'describe-todo name body))

(defmacro describe.skip-if (condition name &body body)
  (list* 'describe-skip-if condition name body))

(defmacro describe.skipIf (condition name &body body)
  (list* 'describe-skip-if condition name body))

(defmacro describe.run-if (condition name &body body)
  (list* 'describe-run-if condition name body))

(defmacro describe.runIf (condition name &body body)
  (list* 'describe-run-if condition name body))

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

(defun suite-test-registration-form (suite-name name forms options)
  `(register-test-in-suite ,suite-name ,name (lambda () ,@forms)
                           ,@options
                           ,@(source-location-option)))

(defun compat-test-name-form (name)
  (if (symbolp name) `',name name))

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

(eval-when (:compile-toplevel :load-toplevel :execute)
  (setf (macro-function 'it.concurrent) (macro-function 'it-concurrent)
        (macro-function 'it.sequential) (macro-function 'it-sequential)
        (macro-function 'it.fails) (macro-function 'it-fails)
        (macro-function 'it.isolated) (macro-function 'it-isolated)
        (macro-function 'it.only) (macro-function 'it-only)
        (macro-function 'it.each) (macro-function 'it-each)
        (macro-function 'it.only.each) (macro-function 'it-only-each)
        (macro-function 'it.concurrent.each) (macro-function 'it-concurrent-each)
        (macro-function 'it.sequential.each) (macro-function 'it-sequential-each)
        (macro-function 'it.fails.each) (macro-function 'it-fails-each)
        (macro-function 'it.skip.each) (macro-function 'it-skip-each)
        (macro-function 'it.todo.each) (macro-function 'it-todo-each)
        (macro-function 'it.property) (macro-function 'it-property)
        (macro-function 'it.run-if) (macro-function 'it-run-if)
        (macro-function 'it.runIf) (macro-function 'it-run-if)
        (macro-function 'it.skip-if) (macro-function 'it-skip-if)
        (macro-function 'it.skipIf) (macro-function 'it-skip-if)
        (macro-function 'it.skip) (macro-function 'it-skip)
        (macro-function 'it.todo) (macro-function 'it-todo)))

(defmacro test (name &body body)
  `(it ,name ,@body))

(defun compat-copy-hash-table (table copy-value)
  (unless (hash-table-p table)
    (error "WITH-RESTORED-HASH-TABLE expects a hash table, got ~S." table))
  (let ((snapshot (make-hash-table :test (hash-table-test table)
                                   :size (hash-table-count table))))
    (maphash (lambda (key value)
               (setf (gethash key snapshot)
                     (funcall copy-value value)))
             table)
    snapshot))

(defun compat-restore-hash-table (target snapshot copy-value)
  (unless (hash-table-p target)
    (error "WITH-RESTORED-HASH-TABLE expects a hash table, got ~S." target))
  (clrhash target)
  (maphash (lambda (key value)
             (setf (gethash key target)
                   (funcall copy-value value)))
           snapshot)
  target)

(defmacro with-replaced-function ((name replacement) &body body)
  (let ((target (gensym "TARGET-"))
        (saved (gensym "SAVED-"))
        (had-binding (gensym "HAD-BINDING-")))
    `(let* ((,target ',name))
       (unless (symbolp ,target)
         (error "WITH-REPLACED-FUNCTION expects a function symbol, got ~S." ,target))
       (let ((,had-binding (fboundp ,target))
             (,saved (ignore-errors (symbol-function ,target))))
         (unwind-protect
              (progn
                (setf (symbol-function ,target) ,replacement)
                ,@body)
           (if ,had-binding
               (setf (symbol-function ,target) ,saved)
               (fmakunbound ,target)))))))

(defmacro with-restored-binding ((place) &body body)
  (multiple-value-bind (temps values stores writer reader)
      (get-setf-expansion place)
    (unless (= (length stores) 1)
      (error "WITH-RESTORED-BINDING supports only single-value places, got ~S."
             place))
    (let ((saved (gensym "SAVED-")))
      `(let* (,@(loop for temp in temps
                      for value in values
                      collect `(,temp ,value))
              (,saved ,reader))
         (unwind-protect
              (progn ,@body)
           (let ((,(first stores) ,saved))
             ,writer))))))

(defmacro with-restored-bindings (bindings &body body)
  (labels ((normalize-binding (binding)
             (if (consp binding)
                 binding
                 (list binding))))
    (if bindings
        `(with-restored-binding ,(normalize-binding (first bindings))
           (with-restored-bindings ,(rest bindings)
             ,@body))
        `(progn ,@body))))

(defmacro with-restored-hash-table ((place &key (copy-value '#'identity)) &body body)
  (multiple-value-bind (temps values stores writer reader)
      (get-setf-expansion place)
    (declare (ignore stores writer))
    (let ((table (gensym "TABLE-"))
          (copier (gensym "COPY-VALUE-"))
          (saved (gensym "SAVED-")))
      `(let* (,@(loop for temp in temps
                      for value in values
                      collect `(,temp ,value))
              (,table ,reader)
              (,copier ,copy-value)
              (,saved (compat-copy-hash-table ,table ,copier)))
         (unwind-protect
              (progn ,@body)
           (compat-restore-hash-table ,table ,saved ,copier))))))

(defmacro with-cleared-hash-table ((place &key (copy-value '#'identity)) &body body)
  `(with-restored-hash-table (,place :copy-value ,copy-value)
     (clrhash ,place)
     ,@body))

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

(eval-when (:compile-toplevel :load-toplevel :execute)
  (setf (macro-function 'test.concurrent) (macro-function 'test-concurrent)
        (macro-function 'test.sequential) (macro-function 'test-sequential)
        (macro-function 'test.fails) (macro-function 'test-fails)
        (macro-function 'test.isolated) (macro-function 'test-isolated)
        (macro-function 'test.only) (macro-function 'test-only)
        (macro-function 'test.each) (macro-function 'test-each)
        (macro-function 'test.only.each) (macro-function 'test-only-each)
        (macro-function 'test.concurrent.each) (macro-function 'test-concurrent-each)
        (macro-function 'test.sequential.each) (macro-function 'test-sequential-each)
        (macro-function 'test.fails.each) (macro-function 'test-fails-each)
        (macro-function 'test.skip.each) (macro-function 'test-skip-each)
        (macro-function 'test.todo.each) (macro-function 'test-todo-each)
        (macro-function 'test.property) (macro-function 'test-property)
        (macro-function 'test.run-if) (macro-function 'test-run-if)
        (macro-function 'test.runIf) (macro-function 'test-run-if)
        (macro-function 'test.skip-if) (macro-function 'test-skip-if)
        (macro-function 'test.skipIf) (macro-function 'test-skip-if)
        (macro-function 'test.skip) (macro-function 'test-skip)
        (macro-function 'test.todo) (macro-function 'test-todo)))

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
         (called (gensym "CONTINUATION-CALLED-"))
         (continuation-reference (gensym "CONTINUATION-FUNCTION-")))
    `(let ((,captured-values nil)
           (,called nil))
       (flet ((,continuation-name (&rest next-values)
                (setf ,called t
                      ,captured-values next-values)))
         (let ((,continuation-reference (function ,continuation-name)))
           (declare (ignore ,continuation-reference)))
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

(defparameter *expect-poll-default-timeout-ms* 1000)
(defparameter *expect-poll-default-interval-ms* 50)

(defun split-expect-poll-body (body)
  (if (and body (option-plist-form-p (first body)))
      (values (first body) (rest body))
      (values nil body)))

(defun unknown-plist-keys (plist allowed-keys)
  (loop for (key nil) on plist by #'cddr
        unless (member key allowed-keys :test #'eq)
          collect key))

(defun normalize-expect-poll-options (options form)
  (let ((raw-options options))
    (unless (or (null raw-options)
                (option-plist-form-p raw-options))
      (error "cl-weave: expect.poll options in ~S must be a property list, got ~S."
             form
             raw-options))
    (let ((unknown-keys (unknown-plist-keys raw-options '(:timeout-ms :interval-ms))))
      (when unknown-keys
        (error "cl-weave: expect.poll options in ~S contain unsupported keys ~S."
               form
               unknown-keys))
      (let ((timeout-ms (if (plist-key-present-p raw-options :timeout-ms)
                            (getf raw-options :timeout-ms)
                            *expect-poll-default-timeout-ms*))
            (interval-ms (if (plist-key-present-p raw-options :interval-ms)
                             (getf raw-options :interval-ms)
                             *expect-poll-default-interval-ms*)))
        (unless (and (realp timeout-ms) (not (minusp timeout-ms)))
          (error "cl-weave: expect.poll :timeout-ms in ~S must be a non-negative real, got ~S."
                 form
                 timeout-ms))
        (unless (and (realp interval-ms) (not (minusp interval-ms)))
          (error "cl-weave: expect.poll :interval-ms in ~S must be a non-negative real, got ~S."
                 form
                 interval-ms))
        (list :timeout-ms timeout-ms
              :interval-ms interval-ms)))))

(defun elapsed-internal-time-ms (started-at)
  (/ (* (- (get-internal-real-time) started-at) 1000)
     internal-time-units-per-second))

(defun poll-last-assertion-report (detail)
  (list :matcher (assertion-detail-matcher detail)
        :actual (assertion-detail-actual detail)
        :expected (assertion-detail-expected detail)
        :negated (assertion-detail-negated detail)
        :pass (assertion-detail-pass detail)))

(defun signal-expect-poll-timeout (form timeout-ms interval-ms attempts last-value last-condition last-detail)
  (signal-assertion-failure
   (make-assertion-detail
    :form form
    :matcher :poll
    :actual (append
             (list :attempts attempts
                   :timeout-ms timeout-ms
                   :interval-ms interval-ms
                   :last-value last-value)
             (when last-condition
               (list :last-condition (rejected-thunk-report last-condition)))
             (when last-detail
               (list :last-assertion (poll-last-assertion-report last-detail))))
    :expected '(:state :pass)
    :negated nil
    :pass nil)))

(defun call-polling-expectation-thunk (thunk expectation options form)
  (let* ((callable (ensure-expect-thunk thunk :poll form))
         (normalized-options (normalize-expect-poll-options options form))
         (timeout-ms (getf normalized-options :timeout-ms))
         (interval-ms (getf normalized-options :interval-ms))
         (started-at (get-internal-real-time))
         (attempts 0)
         (last-value nil)
         (last-condition nil)
         (last-detail nil)
         (passed-p nil))
    (loop
      do (incf attempts)
        (handler-case
            (let ((value (funcall callable)))
              (setf last-value value
                    last-condition nil)
              (handler-case
                  (multiple-value-bind (pass detail)
                      (assert-expectation value expectation form)
                    (setf last-detail detail
                          passed-p pass))
                (assertion-failure (condition)
                  (setf last-detail (failure-detail condition)
                        passed-p nil)))
              (when (>= (elapsed-internal-time-ms started-at) timeout-ms)
                (signal-expect-poll-timeout form
                                            timeout-ms
                                            interval-ms
                                            attempts
                                            last-value
                                            last-condition
                                            last-detail))
              (when passed-p
                (return value)))
           (condition (condition)
             (setf last-condition condition)))
         (when (>= (elapsed-internal-time-ms started-at) timeout-ms)
           (signal-expect-poll-timeout form
                                       timeout-ms
                                       interval-ms
                                       attempts
                                       last-value
                                       last-condition
                                       last-detail))
         (when (plusp interval-ms)
           (sleep (/ interval-ms 1000.0))))))

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

(defmacro is (form &optional reason)
  (declare (ignore reason))
  `(expect ,form))

(defmacro is-true (form &optional reason)
  `(is ,form ,reason))

(defmacro is-false (form &optional reason)
  (declare (ignore reason))
  `(expect ,form :to-be-falsy))

(defmacro signals (condition-type &body body)
  `(expect (lambda () ,@body) :to-throw ',condition-type))

(defmacro finishes (&body body)
  `(expect (lambda () ,@body) :not :to-throw))

(defmacro fail (&optional (reason "explicit failure") &rest args)
  `(let ((reason ,(if args
                      `(format nil ,reason ,@args)
                      reason)))
     (record-assertion)
     (signal-assertion-failure
      (make-assertion-detail
       :form '(fail)
       :matcher :fail
       :actual reason
       :expected '(:no-explicit-failure)
       :negated nil
       :pass nil))))

(defmacro skip (&optional (reason "skipped"))
  `(let ((reason ,reason))
     (let ((restart (find-restart 'skip-test)))
       (if restart
           (invoke-restart restart reason)
           (error "cl-weave: skip requested outside a running test: ~A" reason)))))

(defmacro assert-true (form &optional reason)
  `(is ,form ,reason))

(defmacro assert-false (form &optional reason)
  (declare (ignore reason))
  `(expect ,form :to-be-falsy))

(defmacro assert-null (form &optional reason)
  (declare (ignore reason))
  `(expect ,form :to-be-null))

(defmacro assert-not-null (form &optional reason)
  (declare (ignore reason))
  `(expect ,form :not :to-be-null))

(defmacro assert-equal (expected actual &optional reason)
  (declare (ignore reason))
  `(expect ,actual :to-equal ,expected))

(defmacro assert-eq (expected actual &optional reason)
  (declare (ignore reason))
  `(expect ,actual :to-be ,expected))

(defmacro assert-eql (expected actual &optional reason)
  (declare (ignore reason))
  `(expect (eql ,actual ,expected)))

(defmacro assert-= (expected actual &optional reason)
  (declare (ignore reason))
  `(expect (= ,actual ,expected)))

(defmacro assert-string= (expected actual &optional reason)
  (declare (ignore reason))
  `(expect (string= ,actual ,expected)))

(defmacro assert-string-contains (substring string &optional reason)
  (declare (ignore reason))
  `(expect ,string :to-contain ,substring))

(defmacro assert-bool (expected actual &optional reason)
  (declare (ignore reason))
  `(expect (not (null ,actual)) :to-be (not (null ,expected))))

(defmacro assert-list-contains (expected-element list-form &optional reason)
  (declare (ignore reason))
  `(expect ,list-form :to-contain ,expected-element))

(defmacro assert-type (type-name object &optional reason)
  (declare (ignore reason))
  `(expect ,object :to-be-type-of ',type-name))

(defmacro assert-type-equal (expected-type actual-type &optional reason)
  (declare (ignore reason))
  `(expect ,actual-type :to-equal ,expected-type))

(defmacro assert-values (form &rest expected-values)
  `(expect (multiple-value-list ,form) :to-equal (list ,@expected-values)))

(defmacro assert-signals (condition-type &body body)
  `(signals ,condition-type ,@body))

(defmacro assert-no-signals (&body body)
  `(finishes ,@body))

(defun %finite-real-p (value)
  (and (realp value)
       (or (not (floatp value))
           (and (ignore-errors (= value value))
                (< most-negative-double-float value most-positive-double-float)))))

(defun %set-equal-p (expected actual test)
  (and (= (length expected) (length actual))
       (every (lambda (item) (find item actual :test test)) expected)
       (every (lambda (item) (find item expected :test test)) actual)))

(defun %monotonic-p (sequence predicate)
  (loop for (a b) on sequence
        while b
        always (funcall predicate a b)))

(defun %record-predicate-symbol (type-symbol)
  (and (symbolp type-symbol)
       (find-symbol (format nil "~A-P" (symbol-name type-symbol))
                    (symbol-package type-symbol))))

(defmacro is-equal (expected actual &optional reason)
  `(assert-equal ,expected ,actual ,reason))

(defmacro is-not-equal (unexpected actual &optional reason)
  (declare (ignore reason))
  `(expect (not (equal ,unexpected ,actual)) :to-be-truthy))

(defmacro is-eq (expected actual &optional reason)
  `(assert-eq ,expected ,actual ,reason))

(defmacro is-not-eq (unexpected actual &optional reason)
  (declare (ignore reason))
  `(expect (not (eq ,unexpected ,actual)) :to-be-truthy))

(defmacro is-real (form &optional reason)
  (declare (ignore reason))
  `(expect (realp ,form)))

(defmacro is-keyword (form &optional reason)
  (declare (ignore reason))
  `(expect (keywordp ,form)))

(defmacro is-integer (form &optional reason)
  (declare (ignore reason))
  `(expect (integerp ,form)))

(defmacro is-number (form &optional reason)
  (declare (ignore reason))
  `(expect (numberp ,form)))

(defmacro is-float (form &optional reason)
  (declare (ignore reason))
  `(expect (floatp ,form)))

(defmacro is-symbol (form &optional reason)
  (declare (ignore reason))
  `(expect (symbolp ,form)))

(defmacro is-double-float (form &optional reason)
  (declare (ignore reason))
  `(expect (typep ,form 'double-float)))

(defmacro is-near (expected actual &optional (epsilon 1d-9) reason)
  (declare (ignore reason))
  `(expect (<= (abs (- ,actual ,expected)) ,epsilon)))

(defmacro is-list (form &optional reason)
  (declare (ignore reason))
  `(expect (listp ,form)))

(defmacro is-member (item sequence &rest member-options)
  `(expect (member ,item ,sequence ,@member-options) :to-be-truthy))

(defmacro is-not-member (item sequence &rest member-options)
  `(expect (not (member ,item ,sequence ,@member-options)) :to-be-truthy))

(defmacro is-fact (fact facts &optional reason)
  (declare (ignore reason))
  `(is-member ,fact ,facts :test #'equal))

(defmacro is-nil (form &optional reason)
  `(assert-null ,form ,reason))

(defmacro is-non-nil (form &optional reason)
  (declare (ignore reason))
  `(expect ,form :to-be-truthy))

(defmacro is-positive (form &optional reason)
  (declare (ignore reason))
  `(expect (let ((value ,form))
             (and (realp value) (> value 0)))))

(defmacro is-negative (form &optional reason)
  (declare (ignore reason))
  `(expect (let ((value ,form))
             (and (realp value) (< value 0)))))

(defmacro is-zero (form &optional (epsilon 0) reason)
  (declare (ignore reason))
  `(expect (let ((value ,form)
                 (epsilon ,epsilon))
             (and (numberp value)
                  (numberp epsilon)
                  (if (zerop epsilon)
                      (zerop value)
                      (<= (abs value) epsilon))))))

(defmacro is-between (lo value hi &optional reason)
  (declare (ignore reason))
  `(expect (<= ,lo ,value ,hi)))

(defmacro is-empty (sequence &optional reason)
  (declare (ignore reason))
  `(expect (let ((sequence ,sequence))
             (and (typep sequence 'sequence)
                  (zerop (length sequence))))))

(defmacro is-finite (form &optional reason)
  (declare (ignore reason))
  `(expect (%finite-real-p ,form)))

(defmacro is-string (form &optional reason)
  (declare (ignore reason))
  `(expect (stringp ,form)))

(defmacro is-string-contains (substring string &optional reason)
  `(assert-string-contains ,substring ,string ,reason))

(defmacro is-type (expected-type value &optional reason)
  (declare (ignore reason))
  `(expect (typep ,value ,expected-type)))

(defmacro is-record (expected-type record &optional reason)
  (declare (ignore reason))
  `(expect (let* ((expected-type ,expected-type)
                  (record ,record)
                  (predicate (%record-predicate-symbol expected-type)))
             (and predicate (funcall predicate record)))))

(defmacro is-every (predicate sequence &optional type-name reason)
  (declare (ignore type-name reason))
  `(expect (every ,predicate ,sequence)))

(defmacro assert-set-equal (expected actual &key (test #'equal))
  `(expect (%set-equal-p ,expected ,actual ,test)))

(defmacro assert-within-tolerance (expected actual tolerance)
  `(expect (let ((expected ,expected)
                 (actual ,actual)
                 (tolerance ,tolerance))
             (and (realp expected)
                  (realp actual)
                  (realp tolerance)
                  (not (minusp tolerance))
                  (<= (abs (- expected actual)) tolerance)))))

(defmacro assert-within-tolerance-percent (expected actual percent)
  `(expect (let* ((expected ,expected)
                  (actual ,actual)
                  (percent ,percent)
                  (denominator (max (abs expected) 1d-12)))
             (and (realp expected)
                  (realp actual)
                  (realp percent)
                  (not (minusp percent))
                  (<= (/ (abs (- expected actual)) denominator) percent)))))

(defmacro assert-monotonic-increasing (sequence)
  `(expect (let ((sequence ,sequence))
             (and (listp sequence)
                  (%monotonic-p sequence #'<=)))))

(defmacro assert-monotonic-decreasing (sequence)
  `(expect (let ((sequence ,sequence))
             (and (listp sequence)
                  (%monotonic-p sequence #'>=)))))

(defmacro expect-poll (thunk &body body)
  (multiple-value-bind (options expectation) (split-expect-poll-body body)
    (when (null expectation)
      (error "cl-weave: expect.poll requires a matcher, for example (expect.poll thunk :to-be expected)."))
    `(progn
       (record-assertion)
       (call-polling-expectation-thunk
        ,thunk
        (list ,@expectation)
        ,(if options
             `(list ,@options)
             nil)
        '(expect-poll ,thunk ,@body)))))

(defmacro expect.poll (thunk &body body)
  `(expect-poll ,thunk ,@body))

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
