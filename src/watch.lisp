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
  (let ((seen-components (make-hash-table :test #'eq))
        (seen-pathnames (make-hash-table :test #'equal)))
    (labels ((collect-system/k (system-name system-continue)
               (let ((system-object (asdf:find-system system-name)))
                 (collect-component-files/k
                  system-object
                  seen-components
                  seen-pathnames
                  (lambda (own-files)
                    (if include-dependencies
                        (collect-dependencies/k
                         (asdf:system-depends-on system-object)
                         (lambda (dependency-files)
                           (funcall system-continue
                                    (append own-files dependency-files))))
                        (funcall system-continue own-files))))))
             (collect-dependencies/k (dependencies dependencies-continue)
               (if (null dependencies)
                   (funcall dependencies-continue '())
                   (collect-system/k
                    (first dependencies)
                    (lambda (files)
                      (collect-dependencies/k
                       (rest dependencies)
                       (lambda (tail)
                         (funcall dependencies-continue (append files tail)))))))))
      (collect-system/k system continue))))

(defun asdf-system-files (system &key include-dependencies)
  "Return existing source files declared by SYSTEM and, optionally, its dependencies."
  (system-files/k system include-dependencies #'identity))

(defun file-state (pathnames)
  (mapcar (lambda (pathname)
            (cons pathname (ignore-errors (file-write-date pathname))))
          pathnames))

(defun changed-pathnames (old-state new-state)
  (loop for (pathname . write-date) in new-state
        for old-write-date = (cdr (assoc pathname old-state :test #'equal))
        unless (eql write-date old-write-date)
          collect pathname))

(defun run-system (system &key (reporter :spec)
                         (stream *standard-output*)
                         (name-filter *test-name-filter*)
                         shard
                         bail)
  "Load SYSTEM through ASDF, then run the currently registered cl-weave tests."
  (asdf:load-system system :force t)
  (run-all
   :reporter reporter
   :stream stream
   :name-filter name-filter
   :shard shard
   :bail bail))

(defun watch-system (system &key (reporter :spec)
                            (stream *standard-output*)
                            (status-stream *error-output*)
                            (name-filter *test-name-filter*)
                            shard
                            bail
                            include-dependencies
                            (interval 0.5)
                            once)
  "Run SYSTEM once, then rerun it when ASDF-declared source files change."
  (let ((state nil))
    (loop
      for files = (asdf-system-files system :include-dependencies include-dependencies)
      for new-state = (file-state files)
      for changed = (if state
                        (changed-pathnames state new-state)
                        files)
      when changed
        do (format status-stream "~&; cl-weave watch: ~D changed file~:P for ~A~%"
                   (length changed)
                   system)
           (finish-output status-stream)
           (unless (run-system system
                               :reporter reporter
                               :stream stream
                               :name-filter name-filter
                               :shard shard
                               :bail bail)
             (when once
               (return nil)))
           (setf state new-state)
      when once
        return t
      do (sleep interval))))
