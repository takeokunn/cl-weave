(in-package #:cl-weave)

(defun copy-hash-table-values (table copy-value)
  (unless (hash-table-p table)
    (error "WITH-RESTORED-HASH-TABLE expects a hash table, got ~S." table))
  (let ((snapshot (make-hash-table :test (hash-table-test table)
                                   :size (hash-table-count table))))
    (maphash (lambda (key value)
               (setf (gethash key snapshot)
                     (funcall copy-value value)))
             table)
    snapshot))

(defun restore-hash-table-values (target snapshot copy-value)
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
              (,saved (copy-hash-table-values ,table ,copier)))
         (unwind-protect
              (progn ,@body)
           (restore-hash-table-values ,table ,saved ,copier))))))

(defmacro with-cleared-hash-table ((place &key (copy-value '#'identity)) &body body)
  (multiple-value-bind (temps values stores writer reader)
      (get-setf-expansion place)
    (declare (ignore stores writer))
    (let ((table (gensym "TABLE-")))
      `(let* (,@(loop for temp in temps
                      for value in values
                      collect `(,temp ,value))
              (,table ,reader))
         (with-restored-hash-table (,table :copy-value ,copy-value)
           (clrhash ,table)
           ,@body)))))

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
