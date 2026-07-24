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

  (defvar *watch-test-dependency-index* nil)
(defvar *watch-registered-test-files* nil)
(defvar *watch-index-suite* nil)
(defvar *watch-index-generation* -1)

(progn
  (defconstant +watch-test-index-build-attempts+ 3)

  (defun copy-watch-index-designator (value)
    (if (stringp value)
        (copy-seq value)
        value))

  (defun copy-watch-index-name (name)
    (unless (stringp name)
      (error "cl-weave: watch index name must be a string."))
    (copy-seq name))

  (defun snapshot-watch-test-location (location)
    (when location
      (list :file
            (copy-watch-index-designator
             (getf location :file)))))

  (defun snapshot-watch-test-suite-unlocked (suite)
    (flet ((snapshot-test (test)
             (make-test-case
              :name
              (copy-watch-index-name
               (test-case-name test))
              :location
              (snapshot-watch-test-location
               (test-case-location test))
              :watch-dependencies
              (mapcar (function copy-watch-index-designator)
                      (test-case-watch-dependencies test)))))
      (let* ((snapshot-root
               (make-suite
                :name
                (copy-watch-index-name
                 (suite-name suite))))
             (worklist (list (cons suite snapshot-root))))
        (loop while worklist
              for entry = (pop worklist)
              for current-suite = (car entry)
              for snapshot-suite = (cdr entry)
              do
                 (let ((children nil)
                       (tail nil))
                   (dolist (child (suite-children current-suite))
                     (let ((snapshot-child
                             (cond
                               ((suite-p child)
                                (make-suite
                                 :name
                                 (copy-watch-index-name
                                  (suite-name child))
                                 :parent snapshot-suite))
                               ((test-case-p child)
                                (snapshot-test child)))))
                       (when snapshot-child
                         (let ((cell (list snapshot-child)))
                           (if tail
                               (setf (cdr tail) cell)
                               (setf children cell))
                           (setf tail cell))
                         (when (suite-p child)
                           (push (cons child snapshot-child)
                                 worklist)))))
                   (setf (suite-children snapshot-suite) children
                         (suite-children-tail snapshot-suite) tail))
              finally (return snapshot-root)))))

  (defun snapshot-watch-test-index-input-unlocked (suite)
    (values (snapshot-watch-test-suite-unlocked suite)
            *test-registry-generation*))

  (defun build-watch-test-index-unlocked (suite)
    (let ((index (make-hash-table :test (function equal)))
          (seen-files (make-hash-table :test (function equal)))
          (registered-files (quote ()))
          (worklist (list (cons nil suite))))
      (loop while worklist
            for entry = (pop worklist)
            for parent-suite = (car entry)
            for node = (cdr entry)
            do
               (cond
                 ((suite-p node)
                  (dolist (child
                           (reverse (copy-list (suite-children node))))
                    (push (cons node child) worklist)))
                 ((test-case-p node)
                  (let ((path (test-path parent-suite node))
                        (source (test-location-pathname node)))
                    (when (and source
                               (not (gethash source seen-files)))
                      (setf (gethash source seen-files) t)
                      (push source registered-files))
                    (dolist (dependency
                             (test-effective-watch-dependencies node))
                      (push path (gethash dependency index)))))))
      (values index registered-files)))

  (defun build-watch-test-index (suite)
    (multiple-value-bind (snapshot generation)
        (with-test-registry-lock
          (snapshot-watch-test-index-input-unlocked suite))
      (declare (ignore generation))
      (build-watch-test-index-unlocked snapshot))))

(progn
  (defun watch-test-index-cache-valid-p-unlocked (suite)
    (and (eq suite *watch-index-suite*)
         (= *watch-index-generation*
            *test-registry-generation*)))

  (defun cached-watch-test-index-unlocked (suite)
    (when (watch-test-index-cache-valid-p-unlocked suite)
      (values *watch-test-dependency-index*
              *watch-registered-test-files*
              t)))

  (defun publish-watch-test-index-unlocked
      (suite generation index registered-files)
    (cond
      ((watch-test-index-cache-valid-p-unlocked suite)
       (values *watch-test-dependency-index*
               *watch-registered-test-files*
               t))
      ((= generation *test-registry-generation*)
       (setf *watch-test-dependency-index* index
             *watch-registered-test-files* registered-files
             *watch-index-suite* suite
             *watch-index-generation* generation)
       (values index registered-files t))
      (t
       (values nil nil nil))))

  (defun ensure-watch-test-index-unlocked (suite)
    "Build without holding the registry lock; callers must not hold that lock."
    (loop repeat +watch-test-index-build-attempts+
          do
             (multiple-value-bind
                   (cached-index cached-files cached-p
                    snapshot generation)
                 (with-test-registry-lock
                   (multiple-value-bind
                         (index registered-files valid-p)
                       (cached-watch-test-index-unlocked suite)
                     (if valid-p
                         (values index registered-files t nil nil)
                         (multiple-value-bind
                               (new-snapshot new-generation)
                             (snapshot-watch-test-index-input-unlocked
                              suite)
                           (values nil nil nil
                                   new-snapshot
                                   new-generation)))))
               (when cached-p
                 (return-from ensure-watch-test-index-unlocked
                   (values cached-index cached-files)))
               (multiple-value-bind (index registered-files)
                   (build-watch-test-index-unlocked snapshot)
                 (multiple-value-bind
                       (published-index published-files published-p)
                     (with-test-registry-lock
                       (publish-watch-test-index-unlocked
                        suite generation index registered-files))
                   (when published-p
                     (return-from ensure-watch-test-index-unlocked
                       (values published-index published-files)))))))
    (multiple-value-bind (index registered-files valid-p)
        (with-test-registry-lock
          (cached-watch-test-index-unlocked suite))
      (if valid-p
          (values index registered-files)
          (error
           "Test registry changed during ~D watch index build attempts."
           +watch-test-index-build-attempts+))))

  (defun ensure-watch-test-index (suite)
    (ensure-watch-test-index-unlocked suite)))

(defun collect-registered-test-files (suite)
  (multiple-value-bind (index files)
      (ensure-watch-test-index suite)
    (declare (ignore index))
    (copy-list files)))

(defun selective-watch-location-filter (changed)
  (multiple-value-bind (index registered-files)
      (ensure-watch-test-index (root-suite))
    (declare (ignore index))
    (let ((registered (make-hash-table :test #'equal)))
      (dolist (pathname registered-files)
        (setf (gethash pathname registered) t))
      (when (and changed
                 registered-files
                 (every (lambda (pathname)
                          (gethash pathname registered))
                        changed))
        changed))))

(defun test-effective-watch-dependencies (test)
  (let ((seen (make-hash-table :test #'equal))
        (dependencies '()))
    (labels ((add-dependency (pathname)
               (unless (gethash pathname seen)
                 (setf (gethash pathname seen) t)
                 (push pathname dependencies))))
      (let ((source (test-location-pathname test)))
        (when source
          (add-dependency source)))
      (dolist (pathname (test-case-watch-dependencies test))
        (add-dependency pathname)))
    (nreverse dependencies)))

(defun watch-test-path-selection (suite changed)
"Return selected test paths and true when every changed file is declared."
(multiple-value-bind (index registered-files)
    (ensure-watch-test-index suite)
  (declare (ignore registered-files))
  (let ((selected (quote ()))
        (seen (make-hash-table :test (function equal))))
    (dolist (pathname changed (values (nreverse selected) t))
      (multiple-value-bind (matches presentp)
          (gethash pathname index)
        (unless presentp
          (return-from watch-test-path-selection (values nil nil)))
        (dolist (path matches)
          (unless (gethash path seen)
            (setf (gethash path seen) t)
            (push path selected))))))))

(defun watch-scope (location-filter test-path-filter)
(if (or location-filter test-path-filter) :changed-tests :full-suite))

(defun watch-cycle-plan (state new-state)
(let ((initialp (null state))
      (changed (if state
                   (changed-pathnames state new-state)
                   (mapcar (function car) new-state))))
  (when (and state (null changed))
    (return-from watch-cycle-plan
      (list :changed nil
            :location-filter nil
            :scope :full-suite
            :initialp nil
            :new-state new-state)))
  (let ((location-filter
          (and state (selective-watch-location-filter changed))))
    (multiple-value-bind (test-path-filter selectivep)
        (if (and state (null location-filter))
            (watch-test-path-selection (root-suite) changed)
            (values nil nil))
      (declare (ignore selectivep))
      (append (list :changed changed
                    :location-filter location-filter)
              (when test-path-filter
                (list :test-path-filter test-path-filter))
              (list :scope (watch-scope location-filter test-path-filter)
                    :initialp initialp
                    :new-state new-state))))))

(defun watch-sleep (seconds)
(sleep seconds))

(defun run-system-argument-pairs (&key reporter stream name-filter location-filter
                                  test-path-filter
                                  shard order seed bail coverage
                                  coverage-output coverage-report-directory
                                  coverage-include-pathnames coverage-exclude-pathnames
                                  coverage-minimum-expression coverage-minimum-branch
                                  pass-with-no-tests retry
                                  timeout-ms max-workers)
(append (list :reporter reporter
      :stream stream
      :name-filter name-filter
      :location-filter location-filter
      :shard shard
      :order order
      :seed seed
      :bail bail
      :coverage coverage
      :coverage-output coverage-output
      :coverage-report-directory coverage-report-directory
      :coverage-include-pathnames coverage-include-pathnames
      :coverage-exclude-pathnames coverage-exclude-pathnames
      :coverage-minimum-expression coverage-minimum-expression
      :coverage-minimum-branch coverage-minimum-branch
      :pass-with-no-tests pass-with-no-tests
      :retry retry
      :timeout-ms timeout-ms
              :max-workers max-workers)
        (when test-path-filter
          (list :test-path-filter test-path-filter))))

(defvar *watch-incremental-reload-p* nil)
  (defvar *watch-changed-pathnames* nil)

  (progn
  (defun clone-suite-registry-unlocked (root)
    (clone-suite-tree-unlocked root))
  (defun clone-suite-registry (root)
    (with-test-registry-lock
      (clone-suite-registry-unlocked root))))

  (defun clone-named-suite-table-unlocked (suite-map)
  (let ((cloned (make-hash-table :test #'equal)))
    (maphash
     (lambda (key suite)
       (multiple-value-bind (clone presentp)
           (gethash suite suite-map)
         (when presentp
           (setf (gethash key cloned) clone))))
     *named-suites*)
    cloned))

  (progn
  (defun clone-registration-owner-table-unlocked (suite-map)
    (let ((cloned (make-hash-table :test #'eq)))
      (maphash
       (lambda (registration pathname)
         (multiple-value-bind (clone suitep)
             (gethash registration suite-map)
           (setf (gethash (if suitep clone registration) cloned)
                 pathname)))
       *registration-owners*)
      cloned))
  (defun clone-test-registry-state ()
    (with-test-registry-lock
      (multiple-value-bind (root suite-map)
          (clone-suite-registry-unlocked *root-suite*)
        (values root
                (clone-named-suite-table-unlocked suite-map)
                (clone-registration-owner-table-unlocked suite-map)
                *test-registry-generation*))))
  (defun test-registry-generation-snapshot ()
    (with-test-registry-lock
      *test-registry-generation*))
  (defun publish-test-registry-state
      (expected-generation root named-suites owners generation)
    (with-test-registry-lock
      (when (= expected-generation *test-registry-generation*)
        (setf *root-suite* root
              *current-suite* nil
              *named-suites* named-suites
              *registration-owners* owners
              *test-registry-generation* generation)
        t))))

  (defun suite-sibling-ordinal (suite)
    (let ((parent (suite-parent suite))
          (ordinal 0))
      (unless parent
        (return-from suite-sibling-ordinal 0))
      (dolist (child (suite-children parent))
        (when (and (suite-p child)
                   (equal (suite-name child) (suite-name suite)))
          (when (eq child suite)
            (return-from suite-sibling-ordinal ordinal))
          (incf ordinal)))
      (error "cl-weave: suite is not present in its parent: ~S." suite)))

  (defun suite-stable-path (suite)
    (let ((path nil)
          (current suite))
      (loop for parent = (suite-parent current)
            while parent
            do (push (cons (suite-name current)
                           (suite-sibling-ordinal current))
                     path)
               (setf current parent))
      path))

  (defun suite-child-at-segment (suite segment)
    (let ((ordinal 0))
      (dolist (child (suite-children suite))
        (when (and (suite-p child)
                   (equal (suite-name child) (car segment)))
          (when (= ordinal (cdr segment))
            (return-from suite-child-at-segment child))
          (incf ordinal))))
    (error "cl-weave: replacement suite anchor is missing at ~S." segment))

  (defun find-suite-by-stable-path (root path)
    (reduce #'suite-child-at-segment path :initial-value root))

  (defun changed-pathname-table (pathnames)
    (let ((table (make-hash-table :test #'equal)))
      (dolist (pathname pathnames table)
        (setf (gethash (uiop:ensure-absolute-pathname pathname) table) t))))

  (defun changed-registration-p (registration changed-pathnames)
    (let ((owner (gethash registration *registration-owners*)))
      (and owner (gethash owner changed-pathnames))))

  (defun foreign-registrations (registrations changed-pathnames)
    (remove-if (lambda (registration)
                 (changed-registration-p registration changed-pathnames))
               registrations))

  (progn
  (defstruct (suite-preservation-node
             (:constructor make-suite-preservation-node (segment suite)))
  segment
  suite
  record
  children)

  (defun suite-preservation-record (suite changed-pathnames)
    (labels ((pattern (registrations)
               (mapcar (lambda (registration)
                         (unless (changed-registration-p
                                  registration changed-pathnames)
                           (list registration)))
                       registrations)))
      (let ((children (pattern (suite-children suite)))
            (before-all (pattern (suite-before-all suite)))
            (after-all (pattern (suite-after-all suite)))
            (before-each (pattern (suite-before-each suite)))
            (around-each (pattern (suite-around-each suite)))
            (after-each (pattern (suite-after-each suite))))
        (when (or (some (function null) children)
                  (some (function null) before-all)
                  (some (function null) after-all)
                  (some (function null) before-each)
                  (some (function null) around-each)
                  (some (function null) after-each))
          (list :children-pattern children
                :before-all-pattern before-all
                :after-all-pattern after-all
                :before-each-pattern before-each
                :around-each-pattern around-each
                :after-each-pattern after-each))))))

  (progn
  (defun collect-suite-preservation-records-unlocked
      (root changed-pathnames)
    (let ((tree
            (when root
              (make-suite-preservation-node nil root)))
          (visits 0))
      (when tree
        (let ((stack (list (list :enter root tree))))
          (loop while stack
                do (destructuring-bind (phase suite node)
                       (pop stack)
                     (ecase phase
                       (:enter
                        (incf visits)
                        (setf (suite-preservation-node-record node)
                              (suite-preservation-record
                               suite changed-pathnames))
                        (let ((sibling-ordinals
                                (make-hash-table
                                 :test (function equal)))
                              (children nil)
                              (child-work nil))
                          (dolist (child (suite-children suite))
                            (when (suite-p child)
                              (let* ((name (suite-name child))
                                     (ordinal
                                       (gethash
                                        name sibling-ordinals 0))
                                     (child-node
                                       (make-suite-preservation-node
                                        (cons name ordinal)
                                        child)))
                                (setf (gethash name sibling-ordinals)
                                      (1+ ordinal))
                                (push child-node children)
                                (push (list :enter child child-node)
                                      child-work))))
                          (setf (suite-preservation-node-children node)
                                (nreverse children))
                          (push (list :exit suite node) stack)
                          (dolist (work child-work)
                            (push work stack))))
                       (:exit
                        (setf (suite-preservation-node-children node)
                              (delete-if-not
                               (lambda (child)
                                 (or
                                  (suite-preservation-node-record
                                   child)
                                  (suite-preservation-node-children
                                   child)))
                               (suite-preservation-node-children
                                node)))))))))
      (values
       (and tree
            (or (suite-preservation-node-record tree)
                (suite-preservation-node-children tree))
            tree)
       visits)))

  (defun collect-suite-preservation-records
      (root changed-pathnames)
    (with-test-registry-lock
      (collect-suite-preservation-records-unlocked
       root changed-pathnames))))

  (progn
  (defun prune-changed-registrations-unlocked
      (root changed-pathnames)
    (let ((stack (when root (list (list :enter root)))))
      (loop while stack
            do (destructuring-bind (phase suite)
                   (pop stack)
                 (ecase phase
                   (:enter
                    (push (list :exit suite) stack)
                    (let ((children nil))
                      (dolist (child (suite-children suite))
                        (when (suite-p child)
                          (push child children)))
                      (dolist (child children)
                        (push (list :enter child) stack))))
                   (:exit
                    (let ((children
                            (foreign-registrations
                             (suite-children suite)
                             changed-pathnames))
                          (before-all
                            (foreign-registrations
                             (suite-before-all suite)
                             changed-pathnames))
                          (after-all
                            (foreign-registrations
                             (suite-after-all suite)
                             changed-pathnames))
                          (before-each
                            (foreign-registrations
                             (suite-before-each suite)
                             changed-pathnames))
                          (around-each
                            (foreign-registrations
                             (suite-around-each suite)
                             changed-pathnames))
                          (after-each
                            (foreign-registrations
                             (suite-after-each suite)
                             changed-pathnames)))
                      (setf (suite-children suite) children
                            (suite-children-tail suite) (last children)
                            (suite-before-all suite) before-all
                            (suite-before-all-tail suite) (last before-all)
                            (suite-after-all suite) after-all
                            (suite-after-all-tail suite) (last after-all)
                            (suite-before-each suite) before-each
                            (suite-before-each-tail suite) (last before-each)
                            (suite-around-each suite) around-each
                            (suite-around-each-tail suite) (last around-each)
                            (suite-after-each suite) after-each
                            (suite-after-each-tail suite) (last after-each))))))))
    (note-test-registry-change-unlocked)
    root)

  (defun prune-changed-registrations
      (root changed-pathnames)
    (with-test-registry-lock
      (prune-changed-registrations-unlocked
       root changed-pathnames))))

  (defun merge-suite-preservation-record (suite record)
  (labels ((merge-pattern (registrations pattern)
             (let ((anchors (make-hash-table :test (function eq)))
                   (merged nil))
               (dolist (slot pattern)
                 (when slot
                   (setf (gethash (car slot) anchors) t)))
               (let ((remaining
                       (remove-if (lambda (registration)
                                    (gethash registration anchors))
                                  registrations)))
                 (dolist (slot pattern)
                   (cond
                     (slot
                      (push (car slot) merged))
                     (remaining
                      (push (pop remaining) merged))))
                 (nconc (nreverse merged) remaining)))))
    (let ((children
            (merge-pattern (suite-children suite)
                           (getf record :children-pattern)))
          (before-all
            (merge-pattern (suite-before-all suite)
                           (getf record :before-all-pattern)))
          (after-all
            (merge-pattern (suite-after-all suite)
                           (getf record :after-all-pattern)))
          (before-each
            (merge-pattern (suite-before-each suite)
                           (getf record :before-each-pattern)))
          (around-each
            (merge-pattern (suite-around-each suite)
                           (getf record :around-each-pattern)))
          (after-each
            (merge-pattern (suite-after-each suite)
                           (getf record :after-each-pattern))))
      (dolist (slot (getf record :children-pattern))
        (when (and slot (suite-p (car slot)))
          (setf (suite-parent (car slot)) suite)))
      (setf (suite-children suite) children
            (suite-children-tail suite) (last children)
            (suite-before-all suite) before-all
            (suite-before-all-tail suite) (last before-all)
            (suite-after-all suite) after-all
            (suite-after-all-tail suite) (last after-all)
            (suite-before-each suite) before-each
            (suite-before-each-tail suite) (last before-each)
            (suite-around-each suite) around-each
            (suite-around-each-tail suite) (last around-each)
            (suite-after-each suite) after-each
            (suite-after-each-tail suite) (last after-each))
      suite)))

  (progn
  (defun merge-suite-preservation-records-unlocked (root tree)
    (let ((stack (when tree (list (list root tree))))
          (visits 0))
      (loop while stack
            do (destructuring-bind (suite node)
                   (pop stack)
                 (let ((record
                         (suite-preservation-node-record node))
                       (child-nodes
                         (suite-preservation-node-children node)))
                   (when record
                     (merge-suite-preservation-record suite record))
                   (when child-nodes
                     (let ((child-index
                             (make-hash-table
                              :test (function equal)))
                           (suite-index
                             (make-hash-table
                              :test (function eq)))
                           (sibling-ordinals
                             (make-hash-table
                              :test (function equal)))
                           (child-work nil))
                       (dolist (child (suite-children suite))
                         (incf visits)
                         (when (suite-p child)
                           (let* ((name (suite-name child))
                                  (ordinal
                                    (gethash
                                     name sibling-ordinals 0))
                                  (segment (cons name ordinal)))
                             (setf (gethash name sibling-ordinals)
                                   (1+ ordinal)
                                   (gethash segment child-index)
                                   child
                                   (gethash child suite-index)
                                   child))))
                       (dolist (child-node child-nodes)
                         (let* ((segment
                                  (suite-preservation-node-segment
                                   child-node))
                                (original-suite
                                  (suite-preservation-node-suite
                                   child-node))
                                (child
                                  (or
                                   (gethash original-suite suite-index)
                                   (gethash segment child-index))))
                           (unless child
                             (error
                              "Suite path segment not found: ~S"
                              segment))
                           (push (list child child-node)
                                 child-work)))
                       (dolist (work child-work)
                         (push work stack)))))))
      (when tree
        (note-test-registry-change-unlocked))
      (values root visits)))

  (defun merge-suite-preservation-records (root tree)
    (with-test-registry-lock
      (merge-suite-preservation-records-unlocked
       root tree))))

  (progn
  (defun registry-reachable-objects-unlocked (root)
    (let ((registrations (make-hash-table :test #'eq))
          (suites (make-hash-table :test #'eq))
          (stack (when root (list root))))
      (flet ((record-list (values)
               (dolist (value values)
                 (setf (gethash value registrations) t))))
        (loop while stack
              for suite = (pop stack)
              unless (gethash suite suites)
                do (setf (gethash suite registrations) t
                         (gethash suite suites) t)
                   (record-list (suite-before-all suite))
                   (record-list (suite-after-all suite))
                   (record-list (suite-before-each suite))
                   (record-list (suite-around-each suite))
                   (record-list (suite-after-each suite))
                   (dolist (child (suite-children suite))
                     (setf (gethash child registrations) t)
                     (when (suite-p child)
                       (push child stack)))))
      (values registrations suites)))

  (defun registry-reachable-objects (root)
    (with-test-registry-lock
      (registry-reachable-objects-unlocked root))))

  (progn
  (defun compact-registration-owner-table-unlocked (root)
    (multiple-value-bind (reachable suites)
        (registry-reachable-objects-unlocked root)
      (declare (ignore suites))
      (let ((compacted (make-hash-table :test #'eq)))
        (maphash
         (lambda (registration pathname)
           (when (gethash registration reachable)
             (setf (gethash registration compacted) pathname)))
         *registration-owners*)
        compacted)))
  (defun compact-registration-owner-table (root)
    (with-test-registry-lock
      (compact-registration-owner-table-unlocked root))))

  (progn
  (defun compact-named-suite-table-unlocked (root)
    (multiple-value-bind (registrations reachable-suites)
        (registry-reachable-objects-unlocked root)
      (declare (ignore registrations))
      (let ((compacted (make-hash-table :test #'equal)))
        (maphash
         (lambda (key suite)
           (when (gethash suite reachable-suites)
             (setf (gethash key compacted) suite)))
         *named-suites*)
        compacted)))
  (defun compact-named-suite-table (root)
    (with-test-registry-lock
      (compact-named-suite-table-unlocked root))))

  (defun collect-system-source-components (system)
  (let ((seen-components (make-hash-table :test #'eq))
        (components nil))
    (dolist (component
             (asdf:required-components (asdf:find-system system)))
      (when (and (component-source-pathname component)
                 (not (gethash component seen-components)))
        (setf (gethash component seen-components) t)
        (push component components)))
    (nreverse components)))

  (defun incremental-system-reload-plan (system changed-pathnames)
  (let* ((system (asdf:find-system system))
         (components (asdf:required-components system))
         (component-set (make-hash-table :test (function eq)))
         (changed (changed-pathname-table changed-pathnames))
         (reverse-dependencies (make-hash-table :test (function eq)))
         (reverse-dependency-membership
           (make-hash-table :test (function eq)))
         (reload-set (make-hash-table :test (function eq)))
         (queue nil)
         (operations
           (list (asdf:make-operation (quote asdf:prepare-op))
                 (asdf:make-operation (quote asdf:compile-op))
                 (asdf:make-operation (quote asdf:load-op)))))
    (labels ((ancestor-p (ancestor component)
               (loop for parent = (asdf:component-parent component)
                       then (asdf:component-parent parent)
                     while parent
                     thereis (eq parent ancestor))))
      (dolist (component components)
        (setf (gethash component component-set) t)
        (let ((source (component-source-pathname component)))
          (when (and source (gethash source changed))
            (setf (gethash component reload-set) t)
            (push component queue))))
      (dolist (component components)
        (dolist (operation operations)
          (dolist (dependency
                   (asdf/plan:direct-dependencies operation component))
            (let ((dependency-component (cdr dependency)))
              (when (and (gethash dependency-component component-set)
                         (not (eq dependency-component component))
                         (not (ancestor-p dependency-component component))
                         (not (ancestor-p component dependency-component)))
                (let ((dependents
                        (or
                         (gethash dependency-component
                                  reverse-dependency-membership)
                         (setf
                          (gethash dependency-component
                                   reverse-dependency-membership)
                          (make-hash-table :test (function eq))))))
                  (unless (gethash component dependents)
                    (setf (gethash component dependents) t)
                    (push component
                          (gethash dependency-component
                                   reverse-dependencies)))))))))
      (loop while queue
            for component = (pop queue)
            do (dolist (dependent (gethash component reverse-dependencies))
                 (unless (gethash dependent reload-set)
                   (setf (gethash dependent reload-set) t)
                   (push dependent queue)))))
    (let ((reload-components nil)
          (reload-pathnames nil))
      (dolist (component components)
        (let ((source (component-source-pathname component)))
          (when (and source (gethash component reload-set))
            (push component reload-components)
            (push source reload-pathnames))))
      (values (nreverse reload-components)
              (nreverse reload-pathnames)))))

  (defun asdf-definition-pathname-p (pathname)
    (let ((type (pathname-type pathname)))
      (and type (string-equal type "asd"))))

  (defun atomic-full-system-reload (system)
  (let ((expected-generation
          (test-registry-generation-snapshot)))
    (multiple-value-bind (root named-suites owners generation)
        (let ((*root-suite* nil)
              (*current-suite* nil)
              (*named-suites* (make-hash-table :test #'equal))
              (*registration-owners* (make-hash-table :test #'eq))
              (*test-registry-generation*
                (1+ expected-generation)))
          (asdf:load-system system :force t)
          (values *root-suite*
                  *named-suites*
                  *registration-owners*
                  *test-registry-generation*))
      (unless
          (publish-test-registry-state
           expected-generation
           root
           named-suites
           owners
           generation)
        (error
         "cl-weave: test registry changed during full reload; reload result was discarded."))))
  t)

  (defun atomic-incremental-system-reload
    (system changed-pathnames)
  (multiple-value-bind (reload-components reload-pathnames)
      (incremental-system-reload-plan system changed-pathnames)
    (when reload-components
      (multiple-value-bind
          (cloned-root cloned-named-suites cloned-owners
           expected-generation)
          (clone-test-registry-state)
        (multiple-value-bind (root named-suites owners generation)
            (let ((*root-suite* cloned-root)
                  (*current-suite* nil)
                  (*named-suites* cloned-named-suites)
                  (*registration-owners* cloned-owners)
                  (*test-registry-generation* expected-generation))
              (let* ((changed
                       (changed-pathname-table reload-pathnames))
                     (records
                       (collect-suite-preservation-records-unlocked
                        *root-suite*
                        changed))
                     (compile-op
                       (asdf:make-operation 'asdf:compile-op))
                     (load-op
                       (asdf:make-operation 'asdf:load-op)))
                (prune-changed-registrations-unlocked
                 *root-suite* changed)
                (dolist (component reload-components)
                  (asdf:perform compile-op component)
                  (asdf:perform load-op component))
                (merge-suite-preservation-records-unlocked
                 *root-suite* records)
                (setf *registration-owners*
                      (compact-registration-owner-table-unlocked
                       *root-suite*)
                      *named-suites*
                      (compact-named-suite-table-unlocked
                       *root-suite*))
                (values *root-suite*
                        *named-suites*
                        *registration-owners*
                        *test-registry-generation*)))
          (unless
              (publish-test-registry-state
               expected-generation
               root
               named-suites
               owners
               generation)
            (error
             "cl-weave: test registry changed during incremental reload; reload result was discarded.")))))
    t))

  (defun run-system (system &key (reporter :spec)
                         (stream *standard-output*)
                         (name-filter *test-name-filter*)
                         location-filter
                         test-path-filter
                         shard
                         order
                         seed
                         bail
                         coverage
                         coverage-output
                         coverage-report-directory
                         coverage-include-pathnames coverage-exclude-pathnames
                         coverage-minimum-expression coverage-minimum-branch
                         pass-with-no-tests
                         retry
                         timeout-ms
                         max-workers)
    "Reload SYSTEM through ASDF, then run the currently registered cl-weave tests."
    (if (and *watch-incremental-reload-p*
             *watch-changed-pathnames*
             (notany #'asdf-definition-pathname-p *watch-changed-pathnames*))
        (atomic-incremental-system-reload system *watch-changed-pathnames*)
        (atomic-full-system-reload system))
    (apply #'run-all
           (run-system-argument-pairs
            :reporter reporter
            :stream stream
            :name-filter name-filter
            :location-filter location-filter
            :test-path-filter test-path-filter
            :shard shard
            :order order
            :seed seed
            :bail bail
            :coverage coverage
            :coverage-output coverage-output
            :coverage-report-directory coverage-report-directory
            :coverage-include-pathnames coverage-include-pathnames
            :coverage-exclude-pathnames coverage-exclude-pathnames
            :coverage-minimum-expression coverage-minimum-expression
            :coverage-minimum-branch coverage-minimum-branch
            :pass-with-no-tests pass-with-no-tests
            :retry retry
            :timeout-ms timeout-ms
            :max-workers max-workers)))

(defun run-watched-system (system &rest arguments)
  "Reload SYSTEM with an isolated registry for a watch cycle."
  (let* ((changed-marker (member :changed-pathnames arguments))
         (changed-pathnames (and changed-marker (second changed-marker)))
         (run-arguments
           (if changed-marker
               (append (ldiff arguments changed-marker)
                       (cddr changed-marker))
               arguments)))
    (let ((*watch-incremental-reload-p* (not (null changed-marker)))
          (*watch-changed-pathnames* changed-pathnames))
      (apply #'run-system system run-arguments))))

(defun run-watch-cycle (system plan &key reporter stream status-stream
                                name-filter shard order seed bail
                                coverage coverage-output
                                coverage-report-directory
                                coverage-include-pathnames coverage-exclude-pathnames
                                coverage-minimum-expression coverage-minimum-branch
                                pass-with-no-tests retry timeout-ms
                                max-workers once)
  (let ((changed (getf plan :changed))
        (location-filter (getf plan :location-filter))
        (test-path-filter (getf plan :test-path-filter))
        (scope (getf plan :scope)))
    (if (null changed)
        (values nil t)
        (progn
          (format status-stream "~&; cl-weave watch: ~D changed file~:P for ~A (~A)~%"
                  (length changed)
                  system
                  scope)
          (finish-output status-stream)
          (if (or (apply #'run-watched-system
                         system
                         (append
                          (run-system-argument-pairs
                           :reporter reporter
                           :stream stream
                           :name-filter name-filter
                           :location-filter location-filter
                           :test-path-filter test-path-filter
                           :shard shard
                           :order order
                           :seed seed
                           :bail bail
                           :coverage coverage
                           :coverage-output coverage-output
                           :coverage-report-directory coverage-report-directory
                           :coverage-include-pathnames coverage-include-pathnames
                           :coverage-exclude-pathnames coverage-exclude-pathnames
                           :coverage-minimum-expression coverage-minimum-expression
                           :coverage-minimum-branch coverage-minimum-branch
                           :pass-with-no-tests pass-with-no-tests
                           :retry retry
                           :timeout-ms timeout-ms
                           :max-workers max-workers)
                          (unless (getf plan :initialp)
                            (list :changed-pathnames changed))))
                  (not once))
              (values (getf plan :new-state) t)
              (values nil nil))))))

(defun merge-refreshed-watch-state (next-state refreshed-state)
  (let ((next-write-dates (make-hash-table :test (function equal))))
    (dolist (entry next-state)
      (setf (gethash (car entry) next-write-dates) (cdr entry)))
    (mapcar (lambda (entry)
              (multiple-value-bind (write-date presentp)
                  (gethash (car entry) next-write-dates)
                (cons (car entry)
                      (if presentp write-date (cdr entry)))))
            refreshed-state)))

(defun valid-watch-interval-p (interval)
  (and (realp interval)
       #+sbcl
       (or (not (floatp interval))
           (and (not (sb-ext:float-nan-p interval))
                (not (sb-ext:float-infinity-p interval))))
       #-sbcl
       t
       (plusp interval)))

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
                            coverage-report-directory
                            coverage-include-pathnames coverage-exclude-pathnames
                            coverage-minimum-expression coverage-minimum-branch
                            pass-with-no-tests
                            retry
                            timeout-ms
                            max-workers
                            include-dependencies
                            (interval 0.5)
                            once)
  "Run SYSTEM once, then rerun it when ASDF source or definition files change."
  (unless (valid-watch-interval-p interval)
  (error "cl-weave: watch interval must be a positive finite real number."))
(let ((state nil)
        (files (watched-system-files
                system
                :include-dependencies include-dependencies)))
    (loop
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
              :coverage-report-directory coverage-report-directory
              :coverage-include-pathnames coverage-include-pathnames
              :coverage-exclude-pathnames coverage-exclude-pathnames
              :coverage-minimum-expression coverage-minimum-expression
              :coverage-minimum-branch coverage-minimum-branch
              :pass-with-no-tests pass-with-no-tests
              :retry retry
              :timeout-ms timeout-ms
              :max-workers max-workers
              :once once)
           (unless continuep
             (return nil))
           (when next-state
             (if once
                 (setf state next-state)
                 (let* ((refreshed-files
                          (watched-system-files
                           system
                           :include-dependencies include-dependencies))
                        (refreshed-state (file-state refreshed-files)))
                   (setf files refreshed-files
                         state (merge-refreshed-watch-state
                                next-state
                                refreshed-state))))))
      when once
        return t
      do (watch-sleep interval))))
