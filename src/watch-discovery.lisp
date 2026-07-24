(in-package #:cl-weave)

(defun component-source-pathname (component)
  (let ((pathname (ignore-errors (asdf:component-pathname component))))
    (when (and pathname (not (uiop:directory-pathname-p pathname)))
      (uiop:ensure-absolute-pathname pathname))))

(defun collect-component-files/k (component seen-components seen-pathnames continue)
  (cond
    ((gethash component seen-components)
     (funcall continue '()))
    (t
     (setf (gethash component seen-components) t)
     (let ((children (ignore-errors (asdf:component-children component)))
           (source (component-source-pathname component)))
       (labels ((collect-children/k (remaining child-continue)
                  (if (null remaining)
                      (funcall child-continue '())
                      (collect-component-files/k
                       (first remaining)
                       seen-components
                       seen-pathnames
                       (lambda (files)
                         (collect-children/k
                          (rest remaining)
                          (lambda (tail)
                            (funcall child-continue (append files tail)))))))))
         (collect-children/k
          children
          (lambda (child-files)
            (if (and source (probe-file source) (not (gethash source seen-pathnames)))
                (progn
                  (setf (gethash source seen-pathnames) t)
                  (funcall continue (cons source child-files)))
                (funcall continue child-files)))))))))

(defun system-files/k (system include-dependencies continue)
  (let ((seen-components (make-hash-table :test (function eq)))
        (seen-pathnames (make-hash-table :test (function equal))))
    (labels ((collect-system/k (system-designator system-continue)
               (let ((system-object (asdf:find-system system-designator)))
                 (collect-component-files/k
                  system-object
                  seen-components
                  seen-pathnames
                  (lambda (own-files)
                    (if include-dependencies
                        (collect-dependencies/k
                         system-object
                         (asdf:system-depends-on system-object)
                         (lambda (dependency-files)
                           (funcall system-continue
                                    (append own-files dependency-files))))
                        (funcall system-continue own-files))))))
             (collect-dependencies/k
                 (parent-system dependencies dependencies-continue)
               (if (null dependencies)
                   (funcall dependencies-continue (quote ()))
                   (let ((dependency-system
                           (asdf/find-component:resolve-dependency-spec
                            parent-system
                            (first dependencies))))
                     (if dependency-system
                         (collect-system/k
                          dependency-system
                          (lambda (files)
                            (collect-dependencies/k
                             parent-system
                             (rest dependencies)
                             (lambda (tail)
                               (funcall dependencies-continue
                                        (append files tail))))))
                         (collect-dependencies/k
                          parent-system
                          (rest dependencies)
                          dependencies-continue))))))
      (collect-system/k system continue))))

(defun asdf-system-files (system &key include-dependencies)
  "Return existing source files declared by SYSTEM and, optionally, its dependencies."
  (system-files/k system include-dependencies #'identity))

(defun asdf-system-definition-files (system &key include-dependencies)
  "Return existing ASDF definition files for SYSTEM and, optionally, its dependencies."
  (let ((seen-systems (make-hash-table :test #'eq))
        (seen-pathnames (make-hash-table :test #'equal))
        (files nil))
    (labels ((collect-system (system-designator)
               (let ((system-object (asdf:find-system system-designator)))
                 (unless (gethash system-object seen-systems)
                   (setf (gethash system-object seen-systems) t)
                   (let ((pathname (asdf:system-source-file system-object)))
                     (when (and pathname
                                (probe-file pathname)
                                (not (gethash pathname seen-pathnames)))
                       (setf (gethash pathname seen-pathnames) t)
                       (push pathname files)))
                   (when include-dependencies
                     (dolist (dependency
                              (asdf:system-depends-on system-object))
                       (let ((dependency-system
                               (asdf/find-component:resolve-dependency-spec
                                system-object
                                dependency)))
                         (when dependency-system
                           (collect-system dependency-system)))))))))
      (collect-system system)
      (nreverse files))))

(defun watched-system-files (system &key include-dependencies)
  "Return source and definition files that can change SYSTEM's component graph."
  (let ((seen (make-hash-table :test #'equal))
        (files nil))
    (dolist (pathname
             (append
              (asdf-system-files
               system
               :include-dependencies include-dependencies)
              (asdf-system-definition-files
               system
               :include-dependencies include-dependencies)))
      (unless (gethash pathname seen)
        (setf (gethash pathname seen) t)
        (push pathname files)))
    (nreverse files)))

(defun file-content-signature (pathname &optional buffer)
  (with-open-file (stream pathname
                          :direction :input
                          :element-type (quote (unsigned-byte 8)))
    (let ((buffer (or buffer
                      (make-array 8192
                                  :element-type (quote (unsigned-byte 8)))))
          (hash #xcbf29ce484222325)
          (byte-count 0))
      (loop
        for count = (read-sequence buffer stream)
        while (plusp count)
        do (incf byte-count count)
           (loop for index below count
                 do (setf hash
                          (logand #xffffffffffffffff
                                  (* #x100000001b3
                                     (logxor hash (aref buffer index))))))
        finally (return (values hash byte-count))))))

(defun pathname-signature (pathname &optional buffer)
  (handler-case
      (if (probe-file pathname)
          (let ((write-date (file-write-date pathname)))
            (multiple-value-bind (content-hash byte-count)
                (file-content-signature pathname buffer)
              (list :exists t
                    :write-date write-date
                    :length byte-count
                    :hash content-hash)))
          (list :exists nil))
    (error ()
      (list :exists :unknown))))

(defun file-state (pathnames)
  (let ((buffer (make-array 8192
                            :element-type (quote (unsigned-byte 8)))))
    (mapcar (lambda (pathname)
              (cons pathname (pathname-signature pathname buffer)))
            pathnames)))

(defun changed-pathnames (old-state new-state)
  (let ((new-signatures (make-hash-table :test (function equal)))
        (seen (make-hash-table :test (function equal)))
        (changed (quote ())))
    (dolist (entry new-state)
      (setf (gethash (car entry) new-signatures) (cdr entry)))
    (dolist (entry old-state)
      (destructuring-bind (pathname . signature) entry
        (setf (gethash pathname seen) t)
        (multiple-value-bind (new-signature presentp)
            (gethash pathname new-signatures)
          (unless (and presentp (equal signature new-signature))
            (push pathname changed)))))
    (dolist (entry new-state)
      (unless (gethash (car entry) seen)
        (push (car entry) changed)))
    (nreverse changed)))
