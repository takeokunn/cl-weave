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
  (let ((seen (make-hash-table :test #'equal))
        (changed '()))
    (labels ((collect-differences (left right)
               (dolist (entry left)
                 (destructuring-bind (pathname . write-date) entry
                   (setf (gethash pathname seen) t)
                   (unless (eql write-date
                                (cdr (assoc pathname right :test #'equal)))
                     (push pathname changed))))))
      (collect-differences old-state new-state)
      (dolist (entry new-state)
        (destructuring-bind (pathname . write-date) entry
          (declare (ignore write-date))
          (unless (gethash pathname seen)
            (push pathname changed))))
      (nreverse changed))))

(defun collect-registered-test-files (suite)
  (let ((files '()))
    (labels ((visit (current-suite)
               (dolist (child (suite-children current-suite))
                 (typecase child
                   (suite (visit child))
                   (test-case
                    (let ((file (getf (test-case-location child) :file)))
                      (when file
                        (pushnew (uiop:ensure-absolute-pathname file)
                                 files
                                 :test #'equal))))))))
      (visit suite))
    files))

(defun selective-watch-location-filter (changed)
  (let ((registered-files (collect-registered-test-files (root-suite))))
    (when (and changed
               registered-files
               (every (lambda (pathname)
                        (member pathname registered-files :test #'equal))
                      changed))
      changed)))

(defun watch-scope (location-filter)
  (if location-filter :changed-tests :full-suite))

(defun watch-cycle-plan (state new-state)
  (let* ((changed (if state
                      (changed-pathnames state new-state)
                      (mapcar #'car new-state)))
         (location-filter (and state (selective-watch-location-filter changed))))
    (list :changed changed
          :location-filter location-filter
          :scope (watch-scope location-filter)
          :new-state new-state)))

(defun watch-sleep (seconds)
  (sleep seconds))

(defun run-system-argument-pairs (&key reporter stream name-filter location-filter
                                    shard order seed bail coverage
                                    coverage-output pass-with-no-tests retry
                                    timeout-ms max-workers)
  (list :reporter reporter
        :stream stream
        :name-filter name-filter
        :location-filter location-filter
        :shard shard
        :order order
        :seed seed
        :bail bail
        :coverage coverage
        :coverage-output coverage-output
        :pass-with-no-tests pass-with-no-tests
        :retry retry
        :timeout-ms timeout-ms
        :max-workers max-workers))

(defun watch-cycle-run-arguments (&key reporter stream name-filter location-filter
                                    shard order seed bail coverage
                                    coverage-output pass-with-no-tests retry
                                    timeout-ms max-workers)
  (run-system-argument-pairs
   :reporter reporter
   :stream stream
   :name-filter name-filter
   :location-filter location-filter
   :shard shard
   :order order
   :seed seed
   :bail bail
   :coverage coverage
   :coverage-output coverage-output
   :pass-with-no-tests pass-with-no-tests
   :retry retry
   :timeout-ms timeout-ms
   :max-workers max-workers))

(defun run-system (system &key (reporter :spec)
                         (stream *standard-output*)
                         (name-filter *test-name-filter*)
                         location-filter
                         shard
                         order
                         seed
                         bail
                         coverage
                         coverage-output
                         pass-with-no-tests
                         retry
                         timeout-ms
                         max-workers)
  "Load SYSTEM through ASDF, then run the currently registered cl-weave tests."
  (asdf:load-system system :force t)
  (apply #'run-all
         (run-system-argument-pairs
          :reporter reporter
          :stream stream
          :name-filter name-filter
          :location-filter location-filter
          :shard shard
          :order order
          :seed seed
          :bail bail
          :coverage coverage
          :coverage-output coverage-output
          :pass-with-no-tests pass-with-no-tests
          :retry retry
          :timeout-ms timeout-ms
          :max-workers max-workers)))

(defun run-watch-cycle (system plan &key reporter stream status-stream
                                  name-filter shard order seed bail
                                  coverage coverage-output
                                  pass-with-no-tests retry timeout-ms
                                  max-workers once)
  (let ((changed (getf plan :changed))
        (location-filter (getf plan :location-filter))
        (scope (getf plan :scope)))
    (if (null changed)
        (values nil t)
        (progn
          (format status-stream "~&; cl-weave watch: ~D changed file~:P for ~A (~A)~%"
                  (length changed)
                  system
                  scope)
          (finish-output status-stream)
          (if (or (apply #'run-system
                         system
                         (watch-cycle-run-arguments
                          :reporter reporter
                          :stream stream
                          :name-filter name-filter
                          :location-filter location-filter
                          :shard shard
                          :order order
                          :seed seed
                          :bail bail
                          :coverage coverage
                          :coverage-output coverage-output
                          :pass-with-no-tests pass-with-no-tests
                          :retry retry
                          :timeout-ms timeout-ms
                          :max-workers max-workers))
                  (not once))
              (values (getf plan :new-state) t)
              (values nil nil))))))

(defun watch-system (system &key (reporter :spec)
                            (stream *standard-output*)
                            (status-stream *error-output*)
                            (name-filter *test-name-filter*)
                            shard
                            order
                            seed
                            bail
                            coverage
                            coverage-output
                            pass-with-no-tests
                            retry
                            timeout-ms
                            max-workers
                            include-dependencies
                            (interval 0.5)
                            once)
  "Run SYSTEM once, then rerun it when ASDF-declared source files change."
  (let ((state nil))
    (loop
      for files = (asdf-system-files system :include-dependencies include-dependencies)
      for new-state = (file-state files)
      for plan = (watch-cycle-plan state new-state)
      do (multiple-value-bind (next-state continuep)
             (run-watch-cycle
              system
              plan
              :reporter reporter
              :stream stream
              :status-stream status-stream
              :name-filter name-filter
              :shard shard
              :order order
              :seed seed
              :bail bail
              :coverage coverage
              :coverage-output coverage-output
              :pass-with-no-tests pass-with-no-tests
              :retry retry
              :timeout-ms timeout-ms
              :max-workers max-workers
              :once once)
           (unless continuep
             (return nil))
           (when next-state
             (setf state next-state)))
      when once
        return t
      do (watch-sleep interval))))
