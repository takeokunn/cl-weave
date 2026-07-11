(in-package #:cl-weave)

(defun make-mutation (&key id operator path original replacement form)
  (vector :mutation id operator path original replacement form))

(defun mutation-p (value)
  (and (simple-vector-p value)
       (= (length value) 7)
       (eq (aref value 0) :mutation)))

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

(defun mutation-result-p (value)
  (and (simple-vector-p value)
       (= (length value) 4)
       (eq (aref value 0) :mutation-result)))

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

(defun walk-mutation-form (form function &optional path)
  (funcall function form path)
  (when (consp form)
    (loop for element in form
          for index from 0
          do (walk-mutation-form element function (append path (list index))))))

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

(defun run-mutation (mutation test)
  (handler-case
      (make-mutation-result
       :mutation mutation
       :status (if (funcall test (mutation-form mutation) mutation)
                   :survived
                   :killed))
    (assertion-failure (condition)
      (make-mutation-result :mutation mutation
                            :status :killed
                            :condition condition))
    (error (condition)
      (make-mutation-result :mutation mutation
                            :status :errored
                            :condition condition))))

(defun run-mutations (form test &key (operators *default-mutation-operators*))
  (check-type test function)
  (mapcar (lambda (mutation)
            (run-mutation mutation test))
          (collect-mutations form :operators operators)))

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
    (values (and (zerop (getf summary :survived))
                 (zerop (getf summary :errored))
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
