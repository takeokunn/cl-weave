(in-package #:cl-weave)

(defstruct mutation
  id
  operator
  path
  original
  replacement
  form)

(defstruct mutation-result
  mutation
  status
  condition)

(defstruct mutation-operator
  name
  description
  function)

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
  (setf (gethash name *mutation-operators*)
        (make-mutation-operator :name name
                                :description description
                                :function function))
  name)

(defmacro defmutation-operator (name (form path) &body body)
  `(register-mutation-operator
    ,name
    (lambda (,form ,path)
      ,@body)))

(defun mutation-operator-named (name)
  (or (gethash name *mutation-operators*)
      (error "Unknown mutation operator: ~S" name)))

(defun mutation-operator-list (operators)
  (mapcar (lambda (operator)
            (etypecase operator
              (keyword (mutation-operator-named operator))
              (mutation-operator operator)))
          operators))

(defun operator-symbol-replacement (form replacements)
  (when (and (consp form) (symbolp (first form)))
    (let ((replacement (second (assoc (first form) replacements :test #'eq))))
      (when replacement
        (list (cons replacement (rest form)))))))

(defmutation-operator :arithmetic-operator (form path)
  (declare (ignore path))
  (operator-symbol-replacement form *arithmetic-operator-mutations*))

(defmutation-operator :comparison-operator (form path)
  (declare (ignore path))
  (operator-symbol-replacement form *comparison-operator-mutations*))

(defmutation-operator :boolean-literal (form path)
  (declare (ignore path))
  (cond
    ((eq form t) (list nil))
    ((null form) (list t))
    (t nil)))

(defmutation-operator :conditional-branch (form path)
  (declare (ignore path))
  (when (and (consp form) (eq (first form) 'if) (>= (length form) 3))
    (let ((test (second form))
          (then-form (third form))
          (else-form (fourth form)))
      (list `(if ,test ,else-form ,then-form)))))

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
