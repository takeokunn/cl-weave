(in-package #:cl-weave)

(defvar *root-suite* nil)
(defvar *current-suite* nil)
(defvar *named-suites* (make-hash-table :test #'equal))
(defvar *test-context* nil)
(defvar *assertion-count* nil)
(defvar *expected-assertion-count* nil)
(defvar *expected-assertion-count-form* nil)
(defvar *has-assertions-required* nil)
(defvar *has-assertions-form* nil)

(defun make-suite-record
    (name parent focus execution-mode skip-reason todo-reason)
  (vector 'suite name parent focus execution-mode skip-reason todo-reason
          '() nil '() nil '() nil '() nil '() nil '() nil))

(defun make-test-case-record
    (name function focus skip-reason todo-reason retry timeout-ms concurrent
     tags depends-on execution-mode expected-failure-reason location)
  (vector 'test-case name function focus skip-reason todo-reason retry timeout-ms
          concurrent tags depends-on execution-mode expected-failure-reason
          location))

(defun make-assertion-detail-record (form matcher actual expected negated pass)
  (vector 'assertion-detail form matcher actual expected negated pass))

(defun record-tag-p (value tag size)
  (and (simple-vector-p value)
       (= (length value) size)
       (eq (svref value 0) tag)))

(defun make-suite (&key name parent focus execution-mode skip-reason todo-reason
                     (children nil) children-tail
                     (before-all nil) before-all-tail
                     (after-all nil) after-all-tail
                     (before-each nil) before-each-tail
                     (around-each nil) around-each-tail
                     (after-each nil) after-each-tail)
  (vector 'suite name parent focus execution-mode skip-reason todo-reason
          children children-tail before-all before-all-tail after-all after-all-tail
          before-each before-each-tail around-each around-each-tail after-each
          after-each-tail))

(defun suite-p (value) (record-tag-p value 'suite 19))
(deftype suite () '(satisfies suite-p))
(defun suite-name (record) (svref record 1))
(defun suite-parent (record) (svref record 2))
(defun suite-focus (record) (svref record 3))
(defun suite-execution-mode (record) (svref record 4))
(defun suite-skip-reason (record) (svref record 5))
(defun suite-todo-reason (record) (svref record 6))
(defun suite-children (record) (svref record 7))
(defun suite-children-tail (record) (svref record 8))
(defun suite-before-all (record) (svref record 9))
(defun suite-before-all-tail (record) (svref record 10))
(defun suite-after-all (record) (svref record 11))
(defun suite-after-all-tail (record) (svref record 12))
(defun suite-before-each (record) (svref record 13))
(defun suite-before-each-tail (record) (svref record 14))
(defun suite-around-each (record) (svref record 15))
(defun suite-around-each-tail (record) (svref record 16))
(defun suite-after-each (record) (svref record 17))
(defun suite-after-each-tail (record) (svref record 18))

(defun (setf suite-children) (value record) (setf (svref record 7) value))
(defun (setf suite-children-tail) (value record) (setf (svref record 8) value))
(defun (setf suite-before-all) (value record) (setf (svref record 9) value))
(defun (setf suite-before-all-tail) (value record) (setf (svref record 10) value))
(defun (setf suite-after-all) (value record) (setf (svref record 11) value))
(defun (setf suite-after-all-tail) (value record) (setf (svref record 12) value))
(defun (setf suite-before-each) (value record) (setf (svref record 13) value))
(defun (setf suite-before-each-tail) (value record) (setf (svref record 14) value))
(defun (setf suite-around-each) (value record) (setf (svref record 15) value))
(defun (setf suite-around-each-tail) (value record) (setf (svref record 16) value))
(defun (setf suite-after-each) (value record) (setf (svref record 17) value))
(defun (setf suite-after-each-tail) (value record) (setf (svref record 18) value))

(defun make-test-case (&key name function focus skip-reason todo-reason retry
                         timeout-ms concurrent tags depends-on execution-mode
                         expected-failure-reason location)
  (vector 'test-case name function focus skip-reason todo-reason retry timeout-ms
          concurrent tags depends-on execution-mode expected-failure-reason
          location))

(defun test-case-p (value) (record-tag-p value 'test-case 14))
(deftype test-case () '(satisfies test-case-p))
(defun test-case-name (record) (svref record 1))
(defun test-case-function (record) (svref record 2))
(defun test-case-focus (record) (svref record 3))
(defun test-case-skip-reason (record) (svref record 4))
(defun test-case-todo-reason (record) (svref record 5))
(defun test-case-retry (record) (svref record 6))
(defun test-case-timeout-ms (record) (svref record 7))
(defun test-case-concurrent (record) (svref record 8))
(defun test-case-tags (record) (svref record 9))
(defun test-case-depends-on (record) (svref record 10))
(defun test-case-execution-mode (record) (svref record 11))
(defun test-case-expected-failure-reason (record) (svref record 12))
(defun test-case-location (record) (svref record 13))

(defun make-assertion-detail (&key form matcher actual expected negated pass)
  (vector 'assertion-detail form matcher actual expected negated pass))

(defun assertion-detail-p (value) (record-tag-p value 'assertion-detail 7))
(defun assertion-detail-form (record) (svref record 1))
(defun assertion-detail-matcher (record) (svref record 2))
(defun assertion-detail-actual (record) (svref record 3))
(defun assertion-detail-expected (record) (svref record 4))
(defun assertion-detail-negated (record) (svref record 5))
(defun assertion-detail-pass (record) (svref record 6))

(defun make-test-event (&key status path condition assertion reason location
                          elapsed-internal-time)
  (vector 'test-event status path condition assertion reason location
          elapsed-internal-time))

(defun test-event-p (value) (record-tag-p value 'test-event 8))
(defun test-event-status (record) (svref record 1))
(defun test-event-path (record) (svref record 2))
(defun test-event-condition (record) (svref record 3))
(defun test-event-assertion (record) (svref record 4))
(defun test-event-reason (record) (svref record 5))
(defun test-event-location (record) (svref record 6))
(defun test-event-elapsed-internal-time (record) (svref record 7))

(defun make-test-plan-entry (&key path status reason focused retry timeout-ms
                               concurrent tags depends-on location)
  (vector 'test-plan-entry path status reason focused retry timeout-ms concurrent
          tags depends-on location))

(defun test-plan-entry-p (value) (record-tag-p value 'test-plan-entry 11))
(defun test-plan-entry-path (record) (svref record 1))
(defun test-plan-entry-status (record) (svref record 2))
(defun test-plan-entry-reason (record) (svref record 3))
(defun test-plan-entry-focused (record) (svref record 4))
(defun test-plan-entry-retry (record) (svref record 5))
(defun test-plan-entry-timeout-ms (record) (svref record 6))
(defun test-plan-entry-concurrent (record) (svref record 7))
(defun test-plan-entry-tags (record) (svref record 8))
(defun test-plan-entry-depends-on (record) (svref record 9))
(defun test-plan-entry-location (record) (svref record 10))

(define-condition test-failure (error)
  ((detail :initarg :detail :reader failure-detail)))

(define-condition assertion-failure (test-failure) ())

(define-condition test-timeout (error)
  ((timeout-ms :initarg :timeout-ms :reader test-timeout-ms)))

(define-condition expected-failure-missed (error)
  ((reason :initarg :reason :reader expected-failure-missed-reason)))

(defun root-suite ()
  (or *root-suite*
      (setf *root-suite*
            (make-suite-record "root" nil nil nil nil nil))))

(defun clear-tests ()
  (setf *root-suite* nil
        *current-suite* nil
        *named-suites* (make-hash-table :test #'equal))
  t)

(defun add-child (parent child)
  (let ((cell (list child)))
    (if (suite-children-tail parent)
        (setf (cdr (suite-children-tail parent)) cell
              (suite-children-tail parent) cell)
        (setf (suite-children parent) cell
              (suite-children-tail parent) cell)))
  child)

(defun normalize-execution-mode (mode)
  (unless (member mode '(nil :concurrent :sequential))
    (error "cl-weave: execution mode must be NIL, :CONCURRENT, or :SEQUENTIAL, got ~S."
           mode))
  mode)

(defun named-suite-key (name)
  (typecase name
    (symbol (string-upcase (symbol-name name)))
    (string (string-upcase name))
    (t name)))

(defun ensure-suite (name &key parent focus execution-mode skip-reason todo-reason)
  (or (gethash (named-suite-key name) *named-suites*)
      (let* ((suite-parent (or parent (root-suite)))
             (suite (add-child suite-parent
                               (make-suite-record
                                name suite-parent focus
                                (normalize-execution-mode execution-mode)
                                skip-reason todo-reason))))
        (setf (gethash (named-suite-key name) *named-suites*) suite)
        suite)))

(defun register-named-suite (name &key parent focus execution-mode skip-reason todo-reason)
  (apply #'ensure-suite
         (list name
               :parent (when parent (apply #'ensure-suite (list parent)))
               :focus focus
               :execution-mode execution-mode
               :skip-reason skip-reason
               :todo-reason todo-reason)))

(defun register-suite (name thunk &key focus execution-mode skip-reason todo-reason)
  (let* ((parent (or *current-suite* (root-suite)))
         (suite (add-child parent
                           (make-suite-record
                            name parent focus
                            (normalize-execution-mode execution-mode)
                            skip-reason todo-reason))))
    (let ((*current-suite* suite))
      (funcall thunk))
    suite))

(defun register-test
    (name function &key focus skip-reason todo-reason retry timeout-ms concurrent
       tags depends-on execution-mode expected-failure-reason location)
  (let ((suite (or *current-suite* (root-suite))))
    (add-child suite
               (make-test-case-record
                name function focus skip-reason todo-reason retry timeout-ms
                concurrent tags depends-on
                (normalize-execution-mode
                 (or execution-mode
                     (when concurrent :concurrent)))
                expected-failure-reason location))))

(defun register-test-in-suite
    (suite-name name function &key focus skip-reason todo-reason retry timeout-ms concurrent
       tags depends-on execution-mode expected-failure-reason location)
  (let ((*current-suite* (apply #'ensure-suite (list suite-name))))
    (apply #'register-test
           (list name function
                 :focus focus
                 :skip-reason skip-reason
                 :todo-reason todo-reason
                 :retry retry
                 :timeout-ms timeout-ms
                 :concurrent concurrent
                 :tags tags
                 :depends-on depends-on
                 :execution-mode execution-mode
                 :expected-failure-reason expected-failure-reason
                 :location location))))

(defun register-before-all (function)
  (let* ((suite (or *current-suite* (root-suite)))
         (cell (list function)))
    (if (suite-before-all-tail suite)
        (setf (cdr (suite-before-all-tail suite)) cell
              (suite-before-all-tail suite) cell)
        (setf (suite-before-all suite) cell
              (suite-before-all-tail suite) cell))
    function))

(defun register-after-all (function)
  (let* ((suite (or *current-suite* (root-suite)))
         (cell (list function)))
    (if (suite-after-all-tail suite)
        (setf (cdr (suite-after-all-tail suite)) cell
              (suite-after-all-tail suite) cell)
        (setf (suite-after-all suite) cell
              (suite-after-all-tail suite) cell))
    function))

(defun register-before-each (function)
  (let* ((suite (or *current-suite* (root-suite)))
         (cell (list function)))
    (if (suite-before-each-tail suite)
        (setf (cdr (suite-before-each-tail suite)) cell
              (suite-before-each-tail suite) cell)
        (setf (suite-before-each suite) cell
              (suite-before-each-tail suite) cell))
    function))

(defun register-around-each (function)
  (let* ((suite (or *current-suite* (root-suite)))
         (cell (list function)))
    (if (suite-around-each-tail suite)
        (setf (cdr (suite-around-each-tail suite)) cell
              (suite-around-each-tail suite) cell)
        (setf (suite-around-each suite) cell
              (suite-around-each-tail suite) cell))
    function))

(defun register-after-each (function)
  (let* ((suite (or *current-suite* (root-suite)))
         (cell (list function)))
    (if (suite-after-each-tail suite)
        (setf (cdr (suite-after-each-tail suite)) cell
              (suite-after-each-tail suite) cell)
        (setf (suite-after-each suite) cell
              (suite-after-each-tail suite) cell))
    function))

(defun signal-assertion-failure (detail)
  (error 'assertion-failure :detail detail))

(defun assertion-counting-active-p ()
  (integerp *assertion-count*))

(defun record-assertion ()
  (when (assertion-counting-active-p)
    (incf *assertion-count*))
  t)

(defun require-assertion-counting (form)
  (unless (assertion-counting-active-p)
    (error "cl-weave: ~S must be used inside a running test." form)))

(defun set-expected-assertion-count (count form)
  (require-assertion-counting form)
  (unless (and (integerp count) (not (minusp count)))
    (error "cl-weave: expect.assertions count must be a non-negative integer, got ~S."
           count))
  (setf *expected-assertion-count* count
        *expected-assertion-count-form* form)
  count)

(defun set-has-assertions-required (form)
  (require-assertion-counting form)
  (setf *has-assertions-required* t
        *has-assertions-form* form)
  t)

(defun assertion-count-failure-detail (form matcher actual expected)
  (make-assertion-detail-record form matcher actual expected nil nil))

(defun verify-assertion-counts ()
  (when (and *expected-assertion-count*
             (/= *assertion-count* *expected-assertion-count*))
    (signal-assertion-failure
     (assertion-count-failure-detail
      *expected-assertion-count-form*
      :assertions
      *assertion-count*
      *expected-assertion-count*)))
  (when (and *has-assertions-required*
             (zerop *assertion-count*))
    (signal-assertion-failure
     (assertion-count-failure-detail
      *has-assertions-form*
      :has-assertions
       *assertion-count*
      '(:minimum 1))))
  t)
