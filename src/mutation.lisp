(in-package #:cl-weave)

(defun make-mutation (&key id operator path original replacement form)
  (vector :mutation id operator path original replacement form))

(defun mutation-id (mutation)
  (aref mutation 1))

(defun mutation-operator (mutation)
  (aref mutation 2))

(defun mutation-path (mutation)
  (aref mutation 3))

(defun mutation-original (mutation)
  (aref mutation 4))

(defun mutation-replacement (mutation)
  (aref mutation 5))

(defun mutation-form (mutation)
  (aref mutation 6))

(defun make-mutation-result (&key mutation status condition)
  (vector :mutation-result mutation status condition))

(defun mutation-result-mutation (result)
  (aref result 1))

(defun mutation-result-status (result)
  (aref result 2))

(defun mutation-result-condition (result)
  (aref result 3))

(define-condition mutation-score-failure (error)
  ((summary :initarg :summary :reader mutation-score-failure-summary)
   (min-score :initarg :min-score :reader mutation-score-failure-min-score))
  (:report (lambda (condition stream)
             (format stream "Mutation score ~,2F is below required score ~,2F."
                     (getf (mutation-score-failure-summary condition) :score)
                     (mutation-score-failure-min-score condition)))))

(defun make-mutation-operator (&key name description function)
  (vector :mutation-operator name description function))

(defun mutation-operator-p (value)
  (and (simple-vector-p value)
       (= (length value) 4)
       (eq (aref value 0) :mutation-operator)))

(defun mutation-operator-name (operator)
  (aref operator 1))

(defun mutation-operator-description (operator)
  (aref operator 2))

(defun mutation-operator-function (operator)
  (aref operator 3))

(defvar *mutation-operators* (make-hash-table :test #'eq))

(defparameter *default-mutation-operators*
  '(:arithmetic-operator :comparison-operator :boolean-literal :conditional-branch))

(defparameter *arithmetic-operator-mutations*
  '((+ -)
    (- +)
    (* /)
    (/ *)))

(defparameter *comparison-operator-mutations*
  '((= /=)
    (/= =)
    (< >=)
    (> <=)
    (<= >)
    (>= <)))

(defun register-mutation-operator (name function &key description)
  (check-type name keyword)
  (check-type function function)
  (when description
    (check-type description string))
  (setf (gethash name *mutation-operators*)
        (make-mutation-operator :name name
                                :description description
                                :function function))
  name)

(defmacro defmutation-operator (name (form path) &body body)
  (let ((description (when (stringp (first body))
                       (first body)))
        (forms (if (stringp (first body))
                   (rest body)
                   body)))
    `(register-mutation-operator
      ,name
      (lambda (,form ,path)
        ,@forms)
      :description ,description)))

(defun mutation-operator-named (name)
  (or (gethash name *mutation-operators*)
      (error "Unknown mutation operator: ~S" name)))

(defun mutation-operator-list (operators)
  (mapcar (lambda (operator)
            (cond
              ((keywordp operator)
               (mutation-operator-named operator))
              ((mutation-operator-p operator)
               operator)
              (t
               (error "Invalid mutation operator designator: ~S" operator))))
          operators))

(defun mutation-operator-metadata (operator)
  (let ((operator (cond
                    ((keywordp operator)
                     (mutation-operator-named operator))
                    ((mutation-operator-p operator)
                     operator)
                    (t
                     (error "Invalid mutation operator designator: ~S" operator)))))
    (list :name (mutation-operator-name operator)
          :description (mutation-operator-description operator))))

(defun list-mutation-operators ()
  (mapcar #'mutation-operator-metadata
          (sort (loop for operator being the hash-values of *mutation-operators*
                      collect operator)
                #'string<
                :key (lambda (operator)
                       (symbol-name (mutation-operator-name operator))))))

(defun operator-symbol-replacement (form replacements)
  (when (and (consp form) (symbolp (first form)))
    (let ((replacement (second (assoc (first form) replacements :test #'eq))))
      (when replacement
        (list (cons replacement (rest form)))))))

(register-mutation-operator
 :arithmetic-operator
 (lambda (form path)
   (declare (ignore path))
   (operator-symbol-replacement form *arithmetic-operator-mutations*))
 :description "Swaps arithmetic operator heads such as +, -, *, and /.")

(register-mutation-operator
 :comparison-operator
 (lambda (form path)
   (declare (ignore path))
   (operator-symbol-replacement form *comparison-operator-mutations*))
 :description "Swaps comparison operator heads such as =, /=, <, >, <=, and >=.")

(register-mutation-operator
 :boolean-literal
 (lambda (form path)
   (declare (ignore path))
   (cond
     ((eq form t) (list nil))
     ((null form) (list t))
     (t nil)))
 :description "Flips literal T and NIL forms.")

(register-mutation-operator
 :conditional-branch
 (lambda (form path)
   (declare (ignore path))
   (when (and (consp form) (eq (first form) 'if) (>= (length form) 3))
     (let ((test (second form))
           (then-form (third form))
           (else-form (fourth form)))
       (list `(if ,test ,else-form ,then-form)))))
 :description "Swaps IF then/else branches while preserving the test form.")

(defstruct (mutation-walk-context
             (:constructor make-mutation-walk-context (visitor path)))
  (visitor nil :type function :read-only t)
  (path nil :type list :read-only t))

(defun mutation-child-context (context &rest indexes)
  (make-mutation-walk-context
   (mutation-walk-context-visitor context)
   (append (mutation-walk-context-path context) indexes)))

(defun walk-mutation-form (form visitor &optional path)
  (labels ((declaration-form-p (candidate)
             (and (consp candidate) (eq (first candidate) 'declare)))
           (walk-child (node context &rest indexes)
             (walk node (apply #'mutation-child-context context indexes)))
           (walk-body (body context start &key docstring-p)
             (loop for element in body
                   for index from start
                   for first-p = t then nil
                   unless (or (declaration-form-p element)
                              (and docstring-p first-p (stringp element)))
                     do (walk-child element context index)))
           (walk-binding-value (binding context binding-index value-index)
             (when (consp (nthcdr value-index binding))
               (walk-child (nth value-index binding)
                           context 1 binding-index value-index)))
           (walk-bindings (bindings context)
             (loop for binding in bindings
                   for binding-index from 0
                   do (walk-binding-value binding context binding-index 1)))
           (walk-local-definitions (definitions context)
             (loop for definition in definitions
                   for definition-index from 0
                   when (and (consp definition) (consp (rest definition)))
                     do (walk-body (cddr definition)
                                   (mutation-child-context context 1 definition-index)
                                   2
                                   :docstring-p t)))
           (walk-value-pairs (elements context start)
             (loop for element in elements
                   for index from start
                   when (evenp index)
                     do (walk-child element context index)))
           (walk-clauses (clauses context start body-offset)
             (loop for clause in clauses
                   for clause-index from start
                   when (and (consp clause)
                             (or (zerop body-offset) (consp (rest clause))))
                     do (walk-body (nthcdr body-offset clause)
                                   (mutation-child-context context clause-index)
                                   body-offset)))
           (walk-do (node context)
             (walk-bindings (second node) context)
             (loop for binding in (second node)
                   for binding-index from 0
                   do (walk-binding-value binding context binding-index 2))
             (let ((end-clause (third node)))
               (when (consp end-clause)
                 (walk-body end-clause (mutation-child-context context 2) 0)))
             (walk-body (cdddr node) context 3))
           (walk-application-subforms (node context)
             ;; Function names and special-form operators are syntax, not
             ;; evaluated subforms. Keywords retain their data-list use.
             (loop for element in node
                   for index from 0
                   when (or (plusp index)
                            (keywordp (first node))
                            (and (zerop index) (consp element)))
                     do (walk-child element context index)))
           (walk (node context)
             (funcall (mutation-walk-context-visitor context)
                      node
                      (mutation-walk-context-path context))
             (when (consp node)
               (case (first node)
                  ((quote declare) nil)
                  (function
                   (let ((function-form (second node)))
                     (when (and (consp function-form)
                                (eq (first function-form) 'lambda))
                       (walk-body (cddr function-form)
                                  (mutation-child-context context 1)
                                  2
                                  :docstring-p t))))
                 (lambda
                  (walk-body (cddr node) context 2 :docstring-p t))
                 ((defun defmacro)
                  (walk-body (cdddr node) context 3 :docstring-p t))
                 ((let let*)
                  (walk-bindings (second node) context)
                  (walk-body (cddr node) context 2))
                 ((flet labels)
                  (walk-local-definitions (second node) context)
                  (walk-body (cddr node) context 2))
                 (macrolet
                  (walk-local-definitions (second node) context)
                  (walk-body (cddr node) context 2))
                 (symbol-macrolet
                  (walk-bindings (second node) context)
                  (walk-body (cddr node) context 2))
                 ((multiple-value-bind destructuring-bind)
                  (when (consp (cddr node))
                    (walk-child (third node) context 2))
                  (walk-body (cdddr node) context 3))
                 ((dolist dotimes)
                  (let ((binding (second node)))
                    (when (consp (rest binding))
                      (walk-child (second binding) context 1 1))
                    (when (consp (cddr binding))
                      (walk-child (third binding) context 1 2)))
                  (walk-body (cddr node) context 2))
                 ((do do*)
                  (walk-do node context))
                 ((setq psetq)
                  (walk-value-pairs (rest node) context 1))
                 (cond
                  (walk-clauses (rest node) context 1 0))
                 ((handler-case restart-case)
                  (when (consp (rest node))
                    (walk-child (second node) context 1))
                  (walk-clauses (cddr node) context 2 2))
                 (handler-bind
                  (walk-bindings (second node) context)
                  (walk-body (cddr node) context 2))
                 ((block return-from)
                  (walk-body (cddr node) context 2))
                 (go nil)
                 (the
                  (when (consp (cddr node))
                    (walk-child (third node) context 2)))
                 (eval-when
                  (walk-body (cddr node) context 2))
                 ((locally unwind-protect multiple-value-prog1)
                  (walk-body (rest node) context 1))
                 ((multiple-value-call progv)
                  (walk-body (rest node) context 1))
                 (tagbody
                  (loop for element in (rest node)
                        for index from 1
                        unless (or (symbolp element) (numberp element))
                          do (walk-child element context index)))
                 (otherwise
                  (walk-application-subforms node context))))))
    (walk form (make-mutation-walk-context visitor path))))

(defun replace-mutation-path (form path replacement)
  (if (null path)
      replacement
      (loop for element in form
            for index from 0
            collect (if (= index (first path))
                        (replace-mutation-path element (rest path) replacement)
                        element))))

(defun collect-mutations (form &key (operators *default-mutation-operators*))
  (let ((operator-list (mutation-operator-list operators))
        (mutations '())
        (next-id 0))
    (walk-mutation-form
     form
     (lambda (node path)
       (dolist (operator operator-list)
         (dolist (replacement
                  (funcall (mutation-operator-function operator) node path))
           (unless (equal replacement node)
             (incf next-id)
             (push (make-mutation
                    :id next-id
                    :operator (mutation-operator-name operator)
                    :path path
                    :original node
                    :replacement replacement
                    :form (replace-mutation-path form path replacement))
                   mutations))))))
    (nreverse mutations)))

(defun normalized-mutation-timeout-ms (timeout-ms)
  (cond
    ((null timeout-ms) nil)
    ((and (integerp timeout-ms) (plusp timeout-ms))
     (require-platform-capability :timeout)
     timeout-ms)
    (t (error "Mutation timeout must be NIL or a positive integer in milliseconds: ~S"
              timeout-ms))))

(defun call-mutation-test (mutation test timeout-ms)
  (call-with-platform-timeout/k
   (and timeout-ms (/ timeout-ms 1000.0))
   (lambda () (funcall test (mutation-form mutation) mutation))
   #'identity))

(defun run-mutation (mutation test timeout-ms)
  (handler-case
      (make-mutation-result
       :mutation mutation
       :status (if (call-mutation-test mutation test timeout-ms)
                    :survived
                    :killed))
    (assertion-failure (condition)
      (make-mutation-result :mutation mutation
                            :status :killed
                            :condition condition))
    (platform-timeout ()
      (make-mutation-result :mutation mutation
                            :status :errored
                            :condition (make-condition 'test-timeout
                                                       :timeout-ms timeout-ms)))
    (error (condition)
      (make-mutation-result :mutation mutation
                            :status :errored
                            :condition condition))))

(defun run-mutations (form test &key (operators *default-mutation-operators*)
                                     timeout-ms)
  (check-type test function)
  (let ((timeout-ms (normalized-mutation-timeout-ms timeout-ms)))
    (mapcar (lambda (mutation)
              (run-mutation mutation test timeout-ms))
            (collect-mutations form :operators operators))))

(defun mutation-summary (results)
  (let* ((total (length results))
         (killed (count :killed results :key #'mutation-result-status))
         (survived (count :survived results :key #'mutation-result-status))
         (errored (count :errored results :key #'mutation-result-status)))
    (list :total total
          :killed killed
          :survived survived
          :errored errored
          :score (if (zerop total)
                     1.0
                     (/ killed total 1.0)))))

(defun normalized-mutation-score-threshold (min-score)
  (unless (and (realp min-score) (<= 0 min-score 1))
    (error "Mutation score threshold must be a real number between 0 and 1, got ~S."
           min-score))
  min-score)

(defun mutation-score-passes-p (results min-score)
  (let* ((min-score (normalized-mutation-score-threshold min-score))
         (summary (mutation-summary results)))
    (values (and (zerop (getf summary :errored))
                 (>= (getf summary :score) min-score))
            summary)))

(defun assert-mutation-score (results min-score)
  (multiple-value-bind (pass-p summary)
      (mutation-score-passes-p results min-score)
    (unless pass-p
      (error 'mutation-score-failure
             :summary summary
             :min-score min-score))
    summary))
