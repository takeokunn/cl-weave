(in-package #:cl-weave)

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
      (error "cl-weave: EXPECT-POLL requires a matcher, for example (EXPECT-POLL thunk :to-be expected)."))
    `(progn
       (record-assertion)
       (call-polling-expectation-thunk
        ,thunk
        (list ,@expectation)
        ,(if options
             `(list ,@options)
             nil)
        '(expect-poll ,thunk ,@body)))))

(defmacro expect-assertions (count)
  `(set-expected-assertion-count ,count '(expect-assertions ,count)))

(defmacro expect-has-assertions ()
  `(set-has-assertions-required '(expect-has-assertions)))

(defmacro expect-resolves (thunk &body expectation)
  `(expect (call-resolving-expectation-thunk
            ,thunk
            '(expect-resolves ,thunk ,@expectation))
           ,@expectation))

(defmacro expect-rejects (thunk &body expectation)
  `(expect (call-rejecting-expectation-thunk
            ,thunk
            '(expect-rejects ,thunk ,@expectation))
           ,@expectation))

(defmacro with-snapshot-updates (&body body)
  `(let ((*update-snapshots* t))
     ,@body))

(defmacro with-mocked-functions (bindings &environment environment &body body)
  (let ((expansions
          (loop for (place replacement) in bindings
                collect
                (multiple-value-bind (temps values stores writer reader)
                    (get-setf-expansion place environment)
                  (unless (= (length stores) 1)
                    (error "WITH-MOCKED-FUNCTIONS supports only single-value places, got ~S."
                           place))
                  (list temps values (first stores) writer reader replacement
                        (gensym "SAVED-"))))))
    `(let* (,@(loop for (temps values nil nil reader nil saved) in expansions
                    append (append
                            (loop for temp in temps
                                  for value in values
                                  collect `(,temp ,value))
                            `((,saved ,reader)))))
       (unwind-protect
            (progn
              ,@(loop for (nil nil store writer nil replacement nil) in expansions
                      collect `(let ((,store ,replacement))
                                 ,writer))
              ,@body)
         ,@(loop for (nil nil store writer nil nil saved) in expansions
                 collect `(let ((,store ,saved))
                            ,writer))))))
