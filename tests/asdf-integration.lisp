(in-package #:cl-weave/tests)

(describe "asdf integration"
  (it "reloads systems through ASDF without accumulating registered tests"
  (let ((loaded-systems nil)
        (suite-counts nil)
        (cl-weave::*root-suite* nil)
        (cl-weave::*current-suite* nil)
        (cl-weave::*named-suites* (make-hash-table :test (function equal))))
    (with-mocked-functions
        (((symbol-function (quote asdf:load-system))
          (lambda (system &key force)
            (push (list system force) loaded-systems)
            (cl-weave::register-suite "loaded" (lambda () nil))
            t))
         ((symbol-function (quote cl-weave:run-all))
          (lambda (&rest arguments)
            (declare (ignore arguments))
            (push (length (cl-weave::suite-children
                           (cl-weave::root-suite)))
                  suite-counts)
            t)))
      (expect (cl-weave:run-system "cl-weave/tests") :to-be-truthy)
      (expect (cl-weave:run-system "cl-weave/tests") :to-be-truthy)
      (expect (nreverse loaded-systems)
              :to-equal (quote (("cl-weave/tests" t) ("cl-weave/tests" t))))
      (expect (nreverse suite-counts) :to-equal (quote (1 1))))))

  (it "clears registered tests before each watched system reload"
    (let ((suite-counts nil)
          (cl-weave::*root-suite* nil)
          (cl-weave::*current-suite* nil)
          (cl-weave::*named-suites* (make-hash-table :test #'equal)))
      (with-mocked-functions
          (((symbol-function 'asdf:load-system)
            (lambda (system &key force)
              (declare (ignore system force))
              (cl-weave::register-suite "watched" (lambda () nil))
              t))
           ((symbol-function 'cl-weave:run-all)
            (lambda (&rest arguments)
              (declare (ignore arguments))
              (push (length (cl-weave::suite-children
                             (cl-weave::root-suite)))
                    suite-counts)
              t)))
        (cl-weave::run-watched-system "watched")
        (cl-weave::run-watched-system "watched"))
      (expect (nreverse suite-counts) :to-equal '(1 1))))

  (it "collects source files from ASDF systems"
    (let ((files (cl-weave:asdf-system-files "cl-weave" :include-dependencies nil)))
      (expect files :to-satisfy
              (lambda (paths)
                (some (lambda (pathname)
                        (search "src/runner-api.lisp" (namestring pathname)))
                      paths)))
      (expect files :to-satisfy
              (lambda (paths)
                (some (lambda (pathname)
                        (search "src/watch.lisp" (namestring pathname)))
                      paths)))))
(it "resolves versioned and feature ASDF dependencies"
    (let ((root-system (asdf:find-system "cl-weave"))
          (dependency-system (asdf:find-system "cl-weave/tests"))
          (visited-systems nil))
      (with-mocked-functions
          (((symbol-function (quote asdf:system-depends-on))
            (lambda (system)
              (push system visited-systems)
              (if (eq system root-system)
                  (list (list :version "cl-weave" "0")
                        (list :feature
                              (first *features*)
                              "cl-weave/tests")
                        (list :feature
                              :cl-weave-feature-that-does-not-exist
                              "cl-weave/missing"))
                  nil))))
        (cl-weave::asdf-system-definition-files
         root-system
         :include-dependencies t)
        (expect
         (member dependency-system visited-systems :test (function eq))
         :to-satisfy
         (function identity)))))

  (it "detects changed, deleted, and added file states in stable order"
    (let* ((pathname #P"/tmp/cl-weave-watch-state.lisp")
           (deleted #P"/tmp/cl-weave-watch-deleted.lisp")
           (unreadable #P"/tmp/cl-weave-watch-unreadable.lisp")
           (added #P"/tmp/cl-weave-watch-added.lisp")
           (old-state (list (cons pathname 1)
                            (cons deleted 7)
                            (cons unreadable nil)))
           (new-state (list (cons pathname 2)
                            (cons unreadable nil)
                            (cons added 9))))
      (expect (cl-weave::changed-pathnames old-state new-state)
              :to-equal (list pathname deleted added))
      (expect (cl-weave::changed-pathnames new-state new-state)
              :to-equal nil)))

  #+sbcl
  (it "detects same-size content changes with an unchanged modification time"
    (let* ((directory (make-test-temporary-directory "watch-signature"))
           (pathname (merge-pathnames #P"watched.bin" directory)))
      (unwind-protect
          (progn
            (with-open-file (stream pathname
                                    :direction :output
                                    :if-exists :supersede
                                    :element-type (quote (unsigned-byte 8)))
              (write-sequence #(65 66 67 68) stream))
            (let* ((old-state (cl-weave::file-state (list pathname)))
                   (modified-time
                     (sb-posix:stat-mtime
                      (sb-posix:stat (namestring pathname)))))
              (with-open-file (stream pathname
                                      :direction :output
                                      :if-exists :supersede
                                      :element-type (quote (unsigned-byte 8)))
                (write-sequence #(87 88 89 90) stream))
              (sb-posix:utime (namestring pathname)
                              modified-time
                              modified-time)
              (let ((new-state (cl-weave::file-state (list pathname))))
                (expect (getf (cdr (first new-state)) :write-date)
                        :to-be
                        (getf (cdr (first old-state)) :write-date))
                (expect (getf (cdr (first new-state)) :length)
                        :to-be
                        (getf (cdr (first old-state)) :length))
                (expect (equal (getf (cdr (first new-state)) :hash)
                               (getf (cdr (first old-state)) :hash))
                        :to-be-falsy)
                (expect (cl-weave::changed-pathnames old-state new-state)
                        :to-equal (list pathname)))))
        (uiop:delete-directory-tree directory
                                    :validate t
                                    :if-does-not-exist :ignore))))

  (it "rejects invalid watch intervals before enumerating watched files"
    (let ((enumeration-count 0))
      (with-mocked-functions
          (((symbol-function (quote cl-weave::watched-system-files))
            (lambda (&rest arguments)
              (declare (ignore arguments))
              (incf enumeration-count)
              (error "watched files must not be enumerated"))))
        (dolist (interval
                 (append (list 0 -1 "0.5")
                         #+sbcl
                         (list (quiet-nan)
                               sb-ext:double-float-positive-infinity)
                         #-sbcl
                         nil))
          (let ((message
                  (handler-case
                      (progn
                        (cl-weave:watch-system "cl-weave"
                                               :interval interval
                                               :once t)
                        nil)
                    (error (condition)
                      (princ-to-string condition)))))
            (expect message
                    :to-equal
                    "cl-weave: watch interval must be a positive finite real number."))))
      (expect enumeration-count :to-be 0)))

  (it "selects changed registered test files for watch reruns even when they were deleted"
    (let* ((test-file #P"/tmp/cl-weave/watch-deleted-test.lisp")
           (root (cl-weave::make-suite :name "root"))
           (suite (cl-weave::add-child
                   root
                   (cl-weave::make-suite :name "watch" :parent root))))
      (cl-weave::add-child
       suite
       (cl-weave::make-test-case
        :name "deleted-target"
        :location (list :file (namestring test-file))
        :function (lambda () t)))
      (let ((cl-weave::*root-suite* root))
        (expect (cl-weave::selective-watch-location-filter (list test-file))
                :to-equal (list test-file)))))

  (it "falls back to the full suite when watch sees new unregistered files"
    (let* ((test-file #P"/tmp/cl-weave/watch-registered-test.lisp")
           (new-file #P"/tmp/cl-weave/watch-new-helper.lisp")
           (root (cl-weave::make-suite :name "root"))
           (suite (cl-weave::add-child
                   root
                   (cl-weave::make-suite :name "watch" :parent root))))
      (cl-weave::add-child
       suite
       (cl-weave::make-test-case
        :name "registered-target"
        :location (list :file (namestring test-file))
        :function (lambda () t)))
      (let ((cl-weave::*root-suite* root))
        (expect (cl-weave::selective-watch-location-filter (list new-file))
                :to-be nil)
        (expect (cl-weave::selective-watch-location-filter (list test-file new-file))
                :to-be nil))))

  (it "selects only tests that declare a changed watch dependency"
    (let* ((test-file #P"/tmp/cl-weave/tests/watch-dependencies.lisp")
           (helper-a #P"/tmp/cl-weave/src/helper-a.lisp")
           (helper-b #P"/tmp/cl-weave/src/helper-b.lisp")
           (root (cl-weave::make-suite :name "root"))
           (suite (cl-weave::add-child
                   root
                   (cl-weave::make-suite :name "watch" :parent root))))
      (cl-weave::add-child
       suite
       (cl-weave::make-test-case
        :name "helper-a test"
        :location (list :file (namestring test-file))
        :watch-dependencies (list helper-a)
        :function (lambda () t)))
      (cl-weave::add-child
       suite
       (cl-weave::make-test-case
        :name "helper-b test"
        :location (list :file (namestring test-file))
        :watch-dependencies (list helper-b)
        :function (lambda () t)))
      (multiple-value-bind (paths selectivep)
          (cl-weave::watch-test-path-selection root (list helper-a))
        (expect selectivep :to-be-truthy)
        (expect paths :to-equal '(("watch" "helper-a test"))))
      (multiple-value-bind (paths selectivep)
          (cl-weave::watch-test-path-selection
           root
           (list helper-a #P"/tmp/cl-weave/src/unknown.lisp"))
        (expect paths :to-be nil)
        (expect selectivep :to-be nil))))

  (progn
  (it "normalizes relative watch dependencies against the test definition file"
    (let ((dependencies
            (cl-weave::normalize-watch-dependencies
             '("../src/parser.lisp")
             '(:file "/tmp/cl-weave/tests/parser-test.lisp"))))
      (expect dependencies
              :to-equal (list #P"/tmp/cl-weave/src/parser.lisp"))))

  (it "builds the watch index from a private snapshot outside the registry lock"
  (let ((cl-weave::*test-registry-generation* 0)
        (cl-weave::*watch-test-dependency-index* nil)
        (cl-weave::*watch-registered-test-files* nil)
        (cl-weave::*watch-index-suite* nil)
        (cl-weave::*watch-index-generation* -1))
    (let* ((suite-name (copy-seq "watch"))
           (test-name (copy-seq "snapshot target"))
           (source-name
             (copy-seq "/tmp/cl-weave/tests/watch-snapshot.lisp"))
           (replacement-source
             #P"/tmp/cl-weave/tests/watch-mutated.lisp")
           (dependency
             #P"/tmp/cl-weave/src/watch-snapshot-helper.lisp")
           (replacement-dependency
             #P"/tmp/cl-weave/src/watch-mutated-helper.lisp")
           (root (cl-weave::make-suite :name "root"))
           (suite
             (cl-weave::make-suite :name suite-name :parent root))
           (test
             (cl-weave::make-test-case
              :name test-name
              :location (list :file source-name)
              :watch-dependencies (list dependency)
              :function (lambda () t)))
           (original-test-path
             (symbol-function 'cl-weave::test-path))
           (original-location-pathname
             (symbol-function 'cl-weave::test-location-pathname))
           (original-effective-dependencies
             (symbol-function
              'cl-weave::test-effective-watch-dependencies))
           (snapshot-suite-name nil)
           (snapshot-test-name nil)
           (mutated nil)
           (watch-paths nil))
      (cl-weave::add-child root suite)
      (cl-weave::add-child suite test)
      (labels ((registry-lock-available-p ()
                 #+sb-thread
                 (let ((acquired
                         (handler-case
                             (sb-thread:grab-mutex
                              cl-weave::*test-registry-lock*
                              :waitp nil)
                           (error () nil))))
                   (when acquired
                     (sb-thread:release-mutex
                      cl-weave::*test-registry-lock*))
                   acquired)
                 #-sb-thread
                 t)
               (check-snapshot-object (snapshot live)
                 (expect (registry-lock-available-p) :to-be-truthy)
                 (expect (eq snapshot live) :to-be nil)))
        (with-mocked-functions
            (((symbol-function 'cl-weave::test-path)
              (lambda (snapshot-suite snapshot-test)
                (check-snapshot-object snapshot-suite suite)
                (check-snapshot-object snapshot-test test)
                (setf snapshot-suite-name
                      (cl-weave::suite-name snapshot-suite)
                      snapshot-test-name
                      (cl-weave::test-case-name snapshot-test))
                (unless mutated
                  (setf mutated t
                        (char suite-name 0) #\X
                        (char test-name 0) #\X
                        (getf (cl-weave::test-case-location test) :file)
                        replacement-source
                        (first
                         (cl-weave::test-case-watch-dependencies test))
                        replacement-dependency))
                (funcall original-test-path
                         snapshot-suite snapshot-test)))
             ((symbol-function 'cl-weave::test-location-pathname)
              (lambda (snapshot-test)
                (check-snapshot-object snapshot-test test)
                (funcall original-location-pathname snapshot-test)))
             ((symbol-function
               'cl-weave::test-effective-watch-dependencies)
              (lambda (snapshot-test)
                (check-snapshot-object snapshot-test test)
                (funcall original-effective-dependencies snapshot-test))))
          (multiple-value-bind (index registered-files)
              (cl-weave::ensure-watch-test-index root)
            (expect mutated :to-be-truthy)
            (expect (eq snapshot-suite-name suite-name) :to-be nil)
            (expect (eq snapshot-test-name test-name) :to-be nil)
            (expect snapshot-suite-name :to-equal "watch")
            (expect snapshot-test-name :to-equal "snapshot target")
            (expect suite-name :to-equal "Xatch")
            (expect test-name :to-equal "Xnapshot target")
            (expect registered-files
                    :to-equal
                    (list #P"/tmp/cl-weave/tests/watch-snapshot.lisp"))
            (let ((paths (gethash dependency index)))
              (expect (length paths) :to-be 1)
              (expect (length (first paths)) :to-be 2)
              (expect (first (first paths)) :to-equal "watch")
              (expect (second (first paths))
                      :to-equal "snapshot target")
              (setf (char suite-name 0) #\w
                    (char test-name 0) #\s)
              (setf watch-paths paths))
            (expect (gethash replacement-dependency index)
                    :to-be nil)
            (expect (gethash replacement-source index)
                    :to-be nil)))
        (expect
         (length
          (cl-weave:collect-test-plan
           root :test-path-filter watch-paths))
         :to-be 1)))))

  (it "retries a generation conflict without publishing its stale watch index"
    (let ((cl-weave::*test-registry-generation* 0)
          (cl-weave::*watch-test-dependency-index* nil)
          (cl-weave::*watch-registered-test-files* nil)
          (cl-weave::*watch-index-suite* nil)
          (cl-weave::*watch-index-generation* -1))
      (let* ((source-a #P"/tmp/cl-weave/tests/watch-conflict-a.lisp")
             (source-b #P"/tmp/cl-weave/tests/watch-conflict-b.lisp")
             (dependency-a #P"/tmp/cl-weave/src/watch-conflict-a.lisp")
             (dependency-b #P"/tmp/cl-weave/src/watch-conflict-b.lisp")
             (root (cl-weave::make-suite :name "root"))
             (suite
               (cl-weave::make-suite :name "watch" :parent root))
             (first-test
               (cl-weave::make-test-case
                :name "first"
                :location (list :file source-a)
                :watch-dependencies (list dependency-a)
                :function (lambda () t)))
             (second-test
               (cl-weave::make-test-case
                :name "second"
                :location (list :file source-b)
                :watch-dependencies (list dependency-b)
                :function (lambda () t)))
             (sentinel-suite
               (cl-weave::make-suite :name "sentinel"))
             (sentinel-index
               (make-hash-table :test (function equal)))
             (sentinel-files (list #P"/tmp/cl-weave/sentinel.lisp"))
             (build-count 0)
             (original-build
               (symbol-function
                'cl-weave::build-watch-test-index-unlocked)))
        (cl-weave::add-child root suite)
        (cl-weave::add-child suite first-test)
        (with-mocked-functions
            (((symbol-function
               'cl-weave::build-watch-test-index-unlocked)
              (lambda (snapshot)
                (incf build-count)
                (when (= build-count 2)
                  (expect cl-weave::*watch-index-suite*
                          :to-be sentinel-suite)
                  (expect cl-weave::*watch-test-dependency-index*
                          :to-be sentinel-index)
                  (expect cl-weave::*watch-registered-test-files*
                          :to-be sentinel-files))
                (multiple-value-bind (index registered-files)
                    (funcall original-build snapshot)
                  (when (= build-count 1)
                    (cl-weave::add-child suite second-test)
                    (cl-weave::with-test-registry-lock
                      (setf cl-weave::*watch-index-suite* sentinel-suite
                            cl-weave::*watch-test-dependency-index*
                            sentinel-index
                            cl-weave::*watch-registered-test-files*
                            sentinel-files
                            cl-weave::*watch-index-generation*
                            cl-weave::*test-registry-generation*)))
                  (values index registered-files)))))
          (multiple-value-bind (index registered-files)
              (cl-weave::ensure-watch-test-index root)
            (expect build-count :to-be 2)
            (expect registered-files :to-equal (list source-b source-a))
            (expect (gethash dependency-a index)
                    :to-equal '(("watch" "first")))
            (expect (gethash dependency-b index)
                    :to-equal '(("watch" "second")))
            (expect cl-weave::*watch-index-suite* :to-be root)
            (expect cl-weave::*watch-index-generation*
                    :to-be cl-weave::*test-registry-generation*))))))

  (progn
(progn
  (it "reuses a valid watch index and invalidates it by generation"
    (let ((cl-weave::*test-registry-generation* 0)
          (cl-weave::*watch-test-dependency-index* nil)
          (cl-weave::*watch-registered-test-files* nil)
          (cl-weave::*watch-index-suite* nil)
          (cl-weave::*watch-index-generation* -1))
      (let* ((source-a #P"/tmp/cl-weave/tests/watch-cache-a.lisp")
             (source-b #P"/tmp/cl-weave/tests/watch-cache-b.lisp")
             (dependency #P"/tmp/cl-weave/src/watch-cache-helper.lisp")
             (root (cl-weave::make-suite :name "root"))
             (suite
               (cl-weave::make-suite :name "watch" :parent root))
             (first-test
               (cl-weave::make-test-case
                :name "first"
                :location (list :file source-a)
                :watch-dependencies (list dependency)
                :function (lambda () t)))
             (second-test
               (cl-weave::make-test-case
                :name "second"
                :location (list :file source-b)
                :watch-dependencies (list dependency)
                :function (lambda () t)))
             (build-count 0)
             (original-build
               (symbol-function
                'cl-weave::build-watch-test-index-unlocked)))
        (cl-weave::add-child root suite)
        (cl-weave::add-child suite first-test)
        (cl-weave::add-child suite second-test)
        (with-mocked-functions
            (((symbol-function
               'cl-weave::build-watch-test-index-unlocked)
              (lambda (snapshot)
                (incf build-count)
                (funcall original-build snapshot))))
          (multiple-value-bind (first-index first-files)
              (cl-weave::ensure-watch-test-index root)
            (multiple-value-bind (cached-index cached-files)
                (cl-weave::ensure-watch-test-index root)
              (expect cached-index :to-be first-index)
              (expect cached-files :to-be first-files)
              (expect cached-files :to-equal (list source-b source-a)))
            (multiple-value-bind (paths selectivep)
                (cl-weave::watch-test-path-selection
                 root (list dependency))
              (expect selectivep :to-be-truthy)
              (expect paths
                      :to-equal
                      '(("watch" "second")
                        ("watch" "first"))))
            (expect build-count :to-be 1)
            (cl-weave::note-test-registry-change)
            (multiple-value-bind (rebuilt-index rebuilt-files)
                (cl-weave::ensure-watch-test-index root)
              (expect (eq rebuilt-index first-index) :to-be nil)
              (expect rebuilt-files :to-equal first-files)
              (expect build-count :to-be 2)))))))

  #+sb-thread
  (it "returns the winning cache object when a concurrent build loses publication"
    (let* ((source #P"/tmp/cl-weave/tests/watch-cas-race.lisp")
           (dependency #P"/tmp/cl-weave/src/watch-cas-race-helper.lisp")
           (root (cl-weave::make-suite :name "root"))
           (suite (cl-weave::make-suite :name "watch" :parent root))
           (test (cl-weave::make-test-case
                  :name "target"
                  :location (list :file source)
                  :watch-dependencies (list dependency)
                  :function (lambda () t)))
           (original-build
             (symbol-function
              'cl-weave::build-watch-test-index-unlocked))
           (first-build-ready
             (sb-thread:make-semaphore :count 0))
           (release-loser
             (sb-thread:make-semaphore :count 0))
           (build-lock
             (sb-thread:make-mutex
              :name "watch index CAS test build lock"))
           (build-count 0)
           (expected-generation nil)
           (old-index nil)
           (old-files nil)
           (old-suite nil)
           (old-generation nil)
           (loser-built-index nil)
           (loser-built-files nil)
           (loser-index nil)
           (loser-files nil)
           (winner-index nil)
           (winner-files nil)
           (loser-error nil)
           (winner-error nil)
           (loser-thread nil)
           (winner-thread nil))
      (cl-weave::add-child root suite)
      (cl-weave::add-child suite test)
      (cl-weave::with-test-registry-lock
        (setf expected-generation
              cl-weave::*test-registry-generation*
              old-index
              cl-weave::*watch-test-dependency-index*
              old-files
              cl-weave::*watch-registered-test-files*
              old-suite
              cl-weave::*watch-index-suite*
              old-generation
              cl-weave::*watch-index-generation*
              cl-weave::*watch-test-dependency-index* nil
              cl-weave::*watch-registered-test-files* nil
              cl-weave::*watch-index-suite* nil
              cl-weave::*watch-index-generation* -1))
      (unwind-protect
          (sb-ext:with-timeout 10
            (with-mocked-functions
                (((symbol-function
                   'cl-weave::build-watch-test-index-unlocked)
                  (lambda (snapshot)
                    (multiple-value-bind (index registered-files)
                        (funcall original-build snapshot)
                      (let ((pausep nil))
                        (sb-thread:with-mutex (build-lock)
                          (incf build-count)
                          (when (= build-count 1)
                            (setf loser-built-index index
                                  loser-built-files registered-files
                                  pausep t)
                            (sb-thread:signal-semaphore
                             first-build-ready)))
                        (when pausep
                          (sb-thread:wait-on-semaphore release-loser))
                        (values index registered-files))))))
              (setf loser-thread
                    (sb-thread:make-thread
                     (lambda ()
                       (handler-case
                           (multiple-value-setq
                               (loser-index loser-files)
                             (cl-weave::ensure-watch-test-index root))
                         (error (condition)
                           (setf loser-error condition))))
                     :name "watch index CAS loser"))
              (sb-thread:wait-on-semaphore first-build-ready)
              (setf winner-thread
                    (sb-thread:make-thread
                     (lambda ()
                       (handler-case
                           (multiple-value-setq
                               (winner-index winner-files)
                             (cl-weave::ensure-watch-test-index root))
                         (error (condition)
                           (setf winner-error condition))))
                     :name "watch index CAS winner"))
              (sb-thread:join-thread winner-thread)
              (sb-thread:signal-semaphore release-loser)
              (sb-thread:join-thread loser-thread)
              (expect loser-error :to-be nil)
              (expect winner-error :to-be nil)
              (expect build-count :to-be 2)
              (expect (eq loser-built-index winner-index) :to-be nil)
              (expect (eq loser-built-files winner-files) :to-be nil)
              (expect loser-index :to-be winner-index)
              (expect loser-files :to-be winner-files)
              (expect cl-weave::*watch-test-dependency-index*
                      :to-be winner-index)
              (expect cl-weave::*watch-registered-test-files*
                      :to-be winner-files)
              (expect cl-weave::*watch-index-suite* :to-be root)
              (expect cl-weave::*watch-index-generation*
                      :to-be expected-generation)
              (expect cl-weave::*test-registry-generation*
                      :to-be expected-generation)))
        (sb-thread:signal-semaphore release-loser)
        (when (and loser-thread
                   (sb-thread:thread-alive-p loser-thread))
          (ignore-errors
            (sb-thread:join-thread loser-thread)))
        (when (and winner-thread
                   (sb-thread:thread-alive-p winner-thread))
          (ignore-errors
            (sb-thread:join-thread winner-thread)))
        (cl-weave::with-test-registry-lock
          (setf cl-weave::*watch-test-dependency-index* old-index
                cl-weave::*watch-registered-test-files* old-files
                cl-weave::*watch-index-suite* old-suite
                cl-weave::*watch-index-generation* old-generation))))))

(progn
(it "bounds watch index rebuilds under repeated generation conflicts"
  (let ((cl-weave::*test-registry-generation* 0)
        (cl-weave::*watch-test-dependency-index* nil)
        (cl-weave::*watch-registered-test-files* nil)
        (cl-weave::*watch-index-suite* nil)
        (cl-weave::*watch-index-generation* -1))
    (let* ((root (cl-weave::make-suite :name "root"))
           (suite (cl-weave::make-suite :name "watch" :parent root))
           (test (cl-weave::make-test-case
                  :name "target"
                  :location (list :file #P"/tmp/cl-weave/tests/watch-bounded.lisp")
                  :watch-dependencies
                  (list #P"/tmp/cl-weave/src/watch-bounded-helper.lisp")
                  :function (lambda () t)))
           (build-count 0)
           (original-build
            (symbol-function 'cl-weave::build-watch-test-index-unlocked)))
      (cl-weave::add-child root suite)
      (cl-weave::add-child suite test)
      (with-mocked-functions
          (((symbol-function 'cl-weave::build-watch-test-index-unlocked)
            (lambda (snapshot)
              (incf build-count)
              (multiple-value-prog1
                  (funcall original-build snapshot)
                (cl-weave::note-test-registry-change)))))
        (expect (lambda () (cl-weave::ensure-watch-test-index root))
                :to-throw
                "Test registry changed during 3 watch index build attempts.")
        (expect build-count
                :to-be cl-weave::+watch-test-index-build-attempts+)
        (expect cl-weave::*watch-test-dependency-index* :to-be nil)
        (expect cl-weave::*watch-registered-test-files* :to-be nil)))))

(progn
  (it "indexes deeply nested watch suites without recursive traversal"
    (let ((cl-weave::*test-registry-generation* 0)
          (cl-weave::*watch-test-dependency-index* nil)
          (cl-weave::*watch-registered-test-files* nil)
          (cl-weave::*watch-index-suite* nil)
          (cl-weave::*watch-index-generation* -1))
      (let* ((depth 1024)
             (source #P"/tmp/cl-weave/tests/watch-deep.lisp")
             (dependency #P"/tmp/cl-weave/src/watch-deep-helper.lisp")
             (root (cl-weave::make-suite :name "root"))
             (current root))
        (dotimes (index depth)
          (let ((nested
                  (cl-weave::make-suite
                   :name (format nil "level-~D" index)
                   :parent current)))
            (cl-weave::add-child current nested)
            (setf current nested)))
        (cl-weave::add-child
         current
         (cl-weave::make-test-case
          :name "leaf"
          :location (list :file source)
          :watch-dependencies (list dependency)
          :function (lambda () t)))
        (multiple-value-bind (index registered-files)
            (cl-weave::ensure-watch-test-index root)
          (let ((paths (gethash dependency index)))
            (expect registered-files :to-equal (list source))
            (expect (length paths) :to-be 1)
            (expect (length (first paths)) :to-be (1+ depth))
            (expect (first (first paths)) :to-equal "level-0")
            (expect (car (last (first paths))) :to-equal "leaf"))))))

  (progn
  (it "traverses fifty thousand nested watch suites without consuming control stack"
      (let* ((cl-weave::*test-registry-generation* 0)
             (depth 50000)
             (root (cl-weave::make-suite :name "root"))
             (current root)
             (changed (make-hash-table :test (function equal))))
        (dotimes (index depth)
          (let ((nested
                  (cl-weave::make-suite
                   :name (format nil "level-~D" index)
                   :parent current)))
            (cl-weave::add-child current nested)
            (setf current nested)))
        (labels ((exercise ()
                   (let ((path (cl-weave::suite-stable-path current)))
                     (expect (length path) :to-be depth)
                     (expect (first path) :to-equal (cons "level-0" 0))
                     (expect (car (last path))
                             :to-equal
                             (cons (format nil "level-~D" (1- depth)) 0)))
                   (expect
                    (cl-weave::collect-suite-preservation-records root changed)
                    :to-equal
                    nil)
                   (expect
                    (cl-weave::prune-changed-registrations root changed)
                    :to-be
                    root)
                   (multiple-value-bind (registrations suites)
                       (cl-weave::registry-reachable-objects root)
                     (expect (hash-table-count registrations)
                             :to-be
                             (1+ depth))
                     (expect (hash-table-count suites)
                             :to-be
                             (1+ depth)))))
          #+sbcl
          (sb-ext:with-timeout 30
            (exercise))
          #-sbcl
          (exercise))))

  (it
  "preserves every suite in a deep hierarchy with linear visits"
  (let* ((depth 4096)
         (changed-pathname
           #P"/tmp/cl-weave/watch-deep-preservation.lisp")
         (changed
           (cl-weave::changed-pathname-table
            (list changed-pathname)))
         (location (list :file changed-pathname))
         (root (cl-weave::make-suite :name "root"))
         (current root))
    (let ((cl-weave::*root-suite* root)
          (cl-weave::*current-suite* root)
          (cl-weave::*registration-owners*
            (make-hash-table :test (function eq)))
          (cl-weave::*test-registry-generation* 0))
      (labels ((record-suite-owner (suite)
                 (cl-weave::record-registration-owner suite location)
                 suite)
               (register-hook (suite hook)
                 (let ((cl-weave::*current-suite* suite))
                   (cl-weave::register-before-each
                    hook :location location))))
        (register-hook root (lambda () :old-root))
        (dotimes (index depth)
          (let ((nested
                  (record-suite-owner
                    (cl-weave::make-suite
                     :name (format nil "level-~D" index)
                     :parent current)))
                (hook (lambda () index)))
            (cl-weave::add-child current nested)
            (register-hook nested hook)
            (setf current nested)))
        (multiple-value-bind (tree collection-visits)
            (cl-weave::collect-suite-preservation-records
             root changed)
          (expect collection-visits :to-be (1+ depth))
          (let* ((replacement-root
                   (cl-weave::make-suite :name "root"))
                 (replacement-current replacement-root)
                 (replacement-suites (list replacement-root))
                 (replacement-hooks nil))
            (setf cl-weave::*root-suite* replacement-root
                  cl-weave::*current-suite* replacement-root)
            (let ((hook (lambda () :new-root)))
              (register-hook replacement-root hook)
              (push hook replacement-hooks))
            (dotimes (index depth)
              (let ((nested
                      (record-suite-owner
                        (cl-weave::make-suite
                         :name (format nil "level-~D" index)
                         :parent replacement-current)))
                    (hook (lambda () index)))
                (cl-weave::add-child replacement-current nested)
                (register-hook nested hook)
                (push nested replacement-suites)
                (push hook replacement-hooks)
                (setf replacement-current nested)))
            (setf replacement-suites
                  (nreverse replacement-suites)
                  replacement-hooks
                  (nreverse replacement-hooks))
            (multiple-value-bind (merged-root merge-visits)
                (cl-weave::merge-suite-preservation-records
                 replacement-root tree)
              (expect merged-root :to-be replacement-root)
              (expect merge-visits :to-be depth)
              (let ((parent nil))
                (loop for suite in replacement-suites
                      for hook in replacement-hooks
                      do (expect
                           (cl-weave::suite-parent suite)
                           :to-be
                           parent)
                         (expect
                           (cl-weave::suite-before-each suite)
                           :to-equal
                           (list hook))
                         (expect
                           (cl-weave::suite-before-each-tail suite)
                           :to-be
                           (last
                             (cl-weave::suite-before-each suite)))
                         (expect
                           (cl-weave::suite-children-tail suite)
                           :to-be
                           (last
                             (cl-weave::suite-children suite)))
                         (setf parent suite))))))))))))
)
))


(it "rejects malformed watch dependency lists without rendering circular input"
  (let* ((limit cl-weave::+maximum-watch-dependency-count+)
         (location '(:file "/tmp/cl-weave/tests/watch-boundary.lisp"))
         (circular (list "circular-secret.lisp"))
         (dotted (cons "dotted.lisp" "tail"))
         (oversized
           (make-list (1+ limit)
                      :initial-element #P"/tmp/cl-weave/src/helper.lisp")))
    (setf (cdr circular) circular)
    (labels ((normalize (dependencies)
               (cl-weave::normalize-watch-dependencies dependencies location)))
      #+sbcl
      (sb-ext:with-timeout 10
        (let ((condition
                (handler-case
                    (progn (normalize circular) nil)
                  (error (caught) caught))))
          (expect condition :to-be-truthy)
          (expect (princ-to-string condition)
                  :to-contain "finite proper list")
          (expect (princ-to-string condition)
                  :to-satisfy
                  (lambda (message)
                    (null (search "circular-secret" message)))))
        (expect (lambda () (normalize dotted))
                :to-throw "finite proper list")
        (expect (lambda () (normalize oversized))
                :to-throw "finite proper list")))))

(progn
  (it "accepts the watch dependency limit and preserves canonical first order"
    (let* ((limit cl-weave::+maximum-watch-dependency-count+)
           (helper-a #P"/tmp/cl-weave/src/helper-a.lisp")
           (helper-b #P"/tmp/cl-weave/src/helper-b.lisp")
           (dependencies (make-list limit :initial-element helper-a)))
      (setf (first dependencies) "../src/helper-a.lisp"
            (second dependencies) helper-b
            (third dependencies) "/tmp/cl-weave/src/helper-a.lisp")
      #+sbcl
      (sb-ext:with-timeout 10
        (expect
         (cl-weave::normalize-watch-dependencies
          dependencies
          '(:file "/tmp/cl-weave/tests/watch-boundary.lisp"))
         :to-equal
         (list helper-a helper-b)))))

  (it "selects the maximum registered change set in linear input order"
    (let* ((limit cl-weave::+maximum-watch-dependency-count+)
           (registered-files
             (loop for index below limit
                   collect
                   (make-pathname
                    :name (write-to-string index)
                    :type "lisp"
                    :defaults #P"/tmp/cl-weave/tests/watch.lisp")))
           (changed (reverse (copy-list registered-files)))
           (root (cl-weave::make-suite :name "root")))
      (with-mocked-functions
          (((symbol-function 'cl-weave:root-suite)
            (lambda () root))
           ((symbol-function 'cl-weave::ensure-watch-test-index)
            (lambda (suite)
              (expect suite :to-be root)
              (values (make-hash-table :test #'equal)
                      registered-files))))
        #+sbcl
        (sb-ext:with-timeout 10
          (let ((selected
                  (cl-weave::selective-watch-location-filter changed)))
            (expect selected :to-be changed)
            (expect (first selected) :to-equal (first changed))
            (expect (car (last selected)) :to-equal
                    (car (last changed))))))))

  (it "deduplicates the maximum effective dependency set in source-first order"
    (let* ((limit cl-weave::+maximum-watch-dependency-count+)
           (source #P"/tmp/cl-weave/tests/watch-boundary.lisp")
           (dependencies
             (loop for index below (1- limit)
                   collect
                   (make-pathname
                    :name (write-to-string index)
                    :type "lisp"
                    :defaults #P"/tmp/cl-weave/src/watch.lisp")))
           (test
             (cl-weave::make-test-case
              :name "watch boundary"
              :location (list :file (namestring source))
              :watch-dependencies (cons source dependencies)
              :function (lambda () t))))
      #+sbcl
      (sb-ext:with-timeout 10
        (let ((effective
                (cl-weave::test-effective-watch-dependencies test)))
          (expect (length effective) :to-be limit)
          (expect (first effective) :to-equal source)
          (expect (second effective) :to-equal (first dependencies))
          (expect (car (last effective)) :to-equal
                  (car (last dependencies))))))))
(it "builds a dependency-filtered watch plan"
    (let* ((test-file #P"/tmp/cl-weave/tests/watch-plan.lisp")
           (helper #P"/tmp/cl-weave/src/watch-helper.lisp")
           (root (cl-weave::make-suite :name "root"))
           (suite (cl-weave::add-child
                   root
                   (cl-weave::make-suite :name "watch" :parent root)))
           (old-state (list (cons helper 1)))
           (new-state (list (cons helper 2))))
      (cl-weave::add-child
       suite
       (cl-weave::make-test-case
        :name "dependent"
        :location (list :file (namestring test-file))
        :watch-dependencies (list helper)
        :function (lambda () t)))
      (let ((cl-weave::*root-suite* root))
        (expect (cl-weave::watch-cycle-plan old-state new-state)
                :to-equal
                (list :changed (list helper)
      :location-filter nil
      :test-path-filter '(("watch" "dependent"))
      :scope :changed-tests
      :initialp nil
      :new-state new-state)))))


  (it "derives a changed-tests watch plan from registered file changes"
    (let* ((test-file #P"/tmp/cl-weave/watch-plan-target.lisp")
           (root (cl-weave::make-suite :name "root"))
           (suite (cl-weave::add-child
                   root
                   (cl-weave::make-suite :name "watch" :parent root)))
           (old-state (list (cons test-file 1)))
           (new-state (list (cons test-file 2))))
      (cl-weave::add-child
       suite
       (cl-weave::make-test-case
        :name "plan-target"
        :location (list :file (namestring test-file))
        :function (lambda () t)))
      (let ((cl-weave::*root-suite* root))
        (expect (cl-weave::watch-cycle-plan old-state new-state)
                :to-equal
                (list :changed (list test-file)
      :location-filter (list test-file)
      :scope :changed-tests
      :initialp nil
      :new-state new-state)))))

  (it "derives a full-suite watch plan for the initial run"
    (let* ((test-file #P"/tmp/cl-weave/watch-plan-initial.lisp")
           (new-state (list (cons test-file 1))))
      (expect (cl-weave::watch-cycle-plan nil new-state)
              :to-equal
              (list :changed (list test-file)
      :location-filter nil
      :scope :full-suite
      :initialp t
      :new-state new-state))))

  (it "skips reruns when watch sees no changed files"
    (let ((calls nil))
      (with-mocked-functions
          (((symbol-function 'cl-weave::run-watched-system)
            (lambda (&rest arguments)
              (push arguments calls)
              (error "run-system should not be called when nothing changed"))))
        (multiple-value-bind (next-state continuep)
            (cl-weave::run-watch-cycle
             "cl-weave"
             (list :changed nil
                   :location-filter nil
                   :scope :full-suite
                   :new-state '((#P"/tmp/cl-weave/unchanged.lisp" . 1)))
             :reporter :json
             :stream *standard-output*
             :status-stream *error-output*
             :once nil)
          (expect next-state :to-be nil)
          (expect continuep :to-be-truthy)
          (expect calls :to-equal nil)))))

  (it "returns failure in once mode when the watched run fails"
    (multiple-value-bind (next-state continuep)
        (with-mocked-functions
            (((symbol-function 'cl-weave::run-watched-system)
              (lambda (&rest arguments)
                (declare (ignore arguments))
                nil)))
          (cl-weave::run-watch-cycle
           "cl-weave"
           (list :changed (list #P"/tmp/cl-weave/failed-watch.lisp")
                 :location-filter nil
                 :scope :full-suite
                 :new-state '((#P"/tmp/cl-weave/failed-watch.lisp" . 2)))
           :reporter :json
           :stream *standard-output*
           :status-stream (make-string-output-stream)
           :once t))
      (expect next-state :to-be nil)
      (expect continuep :to-be nil)))

  (it "runs watch mode once without reloading the active test suite"
    (let ((calls nil)
          (output nil))
      (with-mocked-functions
          (((symbol-function 'cl-weave:run-system)
            (lambda (system &key reporter stream name-filter shard order seed
                                  location-filter
                                  bail coverage coverage-output
                                  coverage-report-directory
                                  coverage-include-pathnames coverage-exclude-pathnames
                                  coverage-minimum-expression coverage-minimum-branch
                                  pass-with-no-tests retry timeout-ms
                                  max-workers)
              (declare (ignore stream))
              (declare (ignore coverage-report-directory))
              (declare (ignore coverage-include-pathnames coverage-exclude-pathnames
                               coverage-minimum-expression coverage-minimum-branch))
              (push (list system reporter name-filter shard order seed bail
                          location-filter coverage coverage-output
                          pass-with-no-tests retry timeout-ms max-workers)
                    calls)
              t)))
        (with-captured-output (output stream)
          (expect (cl-weave:watch-system
                   "cl-weave"
                   :reporter :json
                   :stream stream
                   :status-stream stream
                   :name-filter "expect"
                   :shard '(1 2)
                   :order :random
                   :seed 123
                   :bail 1
                   :coverage t
                   :coverage-output "watch.coverage.sexp"
                   :pass-with-no-tests t
                   :retry 2
                   :timeout-ms 250
                   :max-workers 3
                  :once t)
                  :to-be-truthy)))
      (expect calls
              :to-equal '(("cl-weave" :json "expect" (1 2) :random 123 1 nil t
                           "watch.coverage.sexp" t 2 250 3)))
      (expect output :to-contain "FULL-SUITE")
      (expect output :to-contain "cl-weave watch")))

  (it "reruns only changed registered test files in watch mode"
    (let* ((test-file #P"/tmp/cl-weave/watch-target.lisp")
           (root (cl-weave::make-suite :name "root"))
           (suite (cl-weave::add-child
                   root
                   (cl-weave::make-suite :name "watch" :parent root)))
           (states (list (list (cons test-file 1))
                          (list (cons test-file 1))
                          (list (cons test-file 2))))
           (calls nil)
           (output nil))
      (cl-weave::add-child
       suite
       (cl-weave::make-test-case
        :name "target"
        :location (list :file (namestring test-file))
        :function (lambda () t)))
      (let ((cl-weave::*root-suite* root))
        (with-mocked-functions
            (((symbol-function 'cl-weave::watched-system-files)
              (lambda (system &key include-dependencies)
                (declare (ignore system include-dependencies))
                (list test-file)))
             ((symbol-function 'cl-weave::file-state)
              (lambda (files)
                (declare (ignore files))
                (or (pop states)
                    (error "missing mocked file state"))))
             ((symbol-function 'cl-weave:run-system)
              (lambda (system &key reporter stream name-filter location-filter shard
                                    order seed bail coverage coverage-output
                                    coverage-report-directory
                                    coverage-include-pathnames coverage-exclude-pathnames
                                    coverage-minimum-expression coverage-minimum-branch
                                    pass-with-no-tests retry timeout-ms
                                    max-workers)
                (declare (ignore stream))
                (declare (ignore coverage-report-directory))
                (declare (ignore coverage-include-pathnames coverage-exclude-pathnames
                                 coverage-minimum-expression coverage-minimum-branch))
                (push (list system reporter name-filter location-filter shard order
                            seed bail coverage coverage-output
                            pass-with-no-tests retry timeout-ms max-workers)
                      calls)
                ;; A real reload re-registers the suite; restore it after
                ;; RUN-WATCHED-SYSTEM's CLEAR-TESTS so the next cycle can
                ;; narrow reruns to registered test files.
                (setf cl-weave::*root-suite* root)
                (when (= (length calls) 2)
                  (throw 'watch-stop t))
                t))
             ((symbol-function 'cl-weave::watch-sleep)
              (lambda (seconds)
                (declare (ignore seconds))
                nil)))
          (with-captured-output (output stream :stop-tag 'watch-stop)
            (cl-weave:watch-system
             "cl-weave"
             :reporter :json
             :stream stream
             :status-stream stream
             :name-filter "watch"
             :once nil))))
      (expect (reverse calls)
              :to-satisfy
              (lambda (value)
                (equal value
                       (list (list "cl-weave" :json "watch" nil nil nil nil nil
                                   nil nil nil nil nil nil)
                             (list "cl-weave" :json "watch" (list test-file)
                                   nil nil nil nil nil nil nil nil nil nil)))))
      (expect output :to-contain "CHANGED-TESTS")))





  (it
  "refreshes the cached ASDF graph after a definition file changes"
  (let* ((definition-file #P"/tmp/cl-weave/cl-weave.asd")
         (test-file #P"/tmp/cl-weave/watch-target.lisp")
         (new-file #P"/tmp/cl-weave/new-target.lisp")
         (root (cl-weave::make-suite :name "root"))
         (suite
        (cl-weave::add-child root (cl-weave::make-suite :name "watch" :parent root)))
         (states
        (list
          (list (cons definition-file 1) (cons test-file 1))
          (list (cons definition-file 1) (cons test-file 1))
          (list (cons definition-file 1) (cons test-file 1))
          (list (cons definition-file 2) (cons test-file 1))
          (list (cons definition-file 2) (cons test-file 1) (cons new-file 1))
          (list (cons definition-file 2) (cons test-file 1) (cons new-file 1))))
         (calls nil)
         (graph-count 0)
         (graph-count-at-change nil)
         (include-dependencies-calls nil)
         (file-state-files nil)
         (file-state-count 0)
         (sleep-count 0)
         (output nil))
    (cl-weave::add-child
      suite
      (cl-weave::make-test-case
        :name
        "target"
        :location
        (list :file (namestring test-file))
        :function
        (lambda ()
          t)))
    (let ((cl-weave::*root-suite* root))
      (with-mocked-functions
        (((symbol-function 'cl-weave::watched-system-files)
            (lambda (system &key include-dependencies)
              (declare (ignore system))
              (incf graph-count)
              (push include-dependencies include-dependencies-calls)
              (if (= graph-count 3) (list definition-file test-file new-file)
                (list definition-file test-file))))
          ((symbol-function 'cl-weave::file-state)
            (lambda (files)
              (incf file-state-count)
              (push files file-state-files)
              (when (= file-state-count 4)
                (setf graph-count-at-change graph-count))
              (or (pop states) (error "missing mocked file state"))))
          ((symbol-function 'cl-weave:run-system)
            (lambda (system
                &key
                reporter
                stream
                name-filter
                location-filter
                shard
                order
                seed
                bail
                coverage
                coverage-output
                coverage-report-directory
                coverage-include-pathnames
                coverage-exclude-pathnames
                coverage-minimum-expression
                coverage-minimum-branch
                pass-with-no-tests
                retry
                timeout-ms
                max-workers)
              (declare (ignore stream))
              (declare (ignore coverage-report-directory))
              (declare (ignore
                  coverage-include-pathnames
                  coverage-exclude-pathnames
                  coverage-minimum-expression
                  coverage-minimum-branch))
              (push
                (list
                  system
                  reporter
                  name-filter
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
                calls)
              (setf cl-weave::*root-suite* root)
              t))
          ((symbol-function 'cl-weave::watch-sleep)
            (lambda (seconds)
              (declare (ignore seconds))
              (incf sleep-count)
              (when (= sleep-count 4)
                (throw 'watch-stop t)))))
        (with-captured-output
          (output stream :stop-tag 'watch-stop)
          (cl-weave:watch-system
            "cl-weave"
            :reporter
            :json
            :stream
            stream
            :status-stream
            stream
            :name-filter
            "watch"
            :include-dependencies
            t
            :once
            nil))))
    (expect graph-count-at-change :to-be 2)
    (expect graph-count :to-be 3)
    (expect (reverse include-dependencies-calls) :to-equal '(t t t))
    (expect
      (reverse calls)
      :to-satisfy
      (lambda (value)
        (equal
          value
          (list
            (list "cl-weave" :json "watch" nil nil nil nil nil nil nil nil nil nil nil)
            (list "cl-weave" :json "watch" nil nil nil nil nil nil nil nil nil nil nil)))))
    (expect
      (car file-state-files)
      :to-equal
      (list definition-file test-file new-file))
    (expect
      (second file-state-files)
      :to-equal
      (list definition-file test-file new-file))
    (expect output :to-contain "FULL")))

  (it "falls back to the full suite when non-test files change in watch mode"
    (let* ((test-file #P"/tmp/cl-weave/watch-suite-test.lisp")
           (impl-file #P"/tmp/cl-weave/watch-impl.lisp")
           (root (cl-weave::make-suite :name "root"))
           (suite (cl-weave::add-child
                   root
                   (cl-weave::make-suite :name "watch" :parent root)))
           (states (list (list (cons test-file 1)
                               (cons impl-file 1))
                         (list (cons test-file 1)
                               (cons impl-file 1))
                         (list (cons test-file 1)
                               (cons impl-file 2))))
           (calls nil)
           (output nil))
      (cl-weave::add-child
       suite
       (cl-weave::make-test-case
        :name "target"
        :location (list :file (namestring test-file))
        :function (lambda () t)))
      (let ((cl-weave::*root-suite* root))
        (with-mocked-functions
            (((symbol-function 'cl-weave::watched-system-files)
              (lambda (system &key include-dependencies)
                (declare (ignore system include-dependencies))
                (list test-file impl-file)))
             ((symbol-function 'cl-weave::file-state)
              (lambda (files)
                (declare (ignore files))
                (or (pop states)
                    (error "missing mocked file state"))))
             ((symbol-function 'cl-weave:run-system)
              (lambda (system &key reporter stream name-filter location-filter shard
                                    order seed bail coverage coverage-output
                                    coverage-report-directory
                                    coverage-include-pathnames coverage-exclude-pathnames
                                    coverage-minimum-expression coverage-minimum-branch
                                    pass-with-no-tests retry timeout-ms
                                    max-workers)
                (declare (ignore stream))
                (declare (ignore coverage-report-directory))
                (declare (ignore coverage-include-pathnames coverage-exclude-pathnames
                                 coverage-minimum-expression coverage-minimum-branch))
                (push (list system reporter name-filter location-filter shard order
                            seed bail coverage coverage-output
                            pass-with-no-tests retry timeout-ms max-workers)
                      calls)
                ;; A real reload re-registers the suite; restore it after
                ;; RUN-WATCHED-SYSTEM's CLEAR-TESTS so the next cycle can
                ;; narrow reruns to registered test files.
                (setf cl-weave::*root-suite* root)
                (when (= (length calls) 2)
                  (throw 'watch-stop t))
                t))
             ((symbol-function 'cl-weave::watch-sleep)
              (lambda (seconds)
                (declare (ignore seconds))
                nil)))
          (with-captured-output (output stream :stop-tag 'watch-stop)
            (cl-weave:watch-system
             "cl-weave"
             :reporter :json
             :stream stream
             :status-stream stream
             :name-filter "watch"
             :once nil))))
      (expect (reverse calls)
              :to-satisfy
              (lambda (value)
                (equal value
                       (list (list "cl-weave" :json "watch" nil nil nil nil nil
                                   nil nil nil nil nil nil)
                             (list "cl-weave" :json "watch" nil nil nil nil nil
                                   nil nil nil nil nil nil)))))
      (expect output :to-contain "FULL-SUITE"))))

(describe
  "watch state refresh"
  (it
    "keeps pre-run dates for existing files and initializes new files"
    (let* ((existing #P"/tmp/cl-weave/existing.lisp")
           (added #P"/tmp/cl-weave/added.lisp")
           (next-state (list (cons existing 2)))
           (refreshed-state (list (cons existing 3) (cons added 4))))
      (expect
        (cl-weave::merge-refreshed-watch-state next-state refreshed-state)
        :to-equal
        (list (cons existing 2) (cons added 4)))))
  (it
    "skips test selection when no files changed"
    (let ((state (list (cons #P"/tmp/cl-weave/unchanged.lisp" 1))))
      (with-mocked-functions
        (((symbol-function (quote cl-weave::watch-test-path-selection))
            (lambda (&rest arguments)
              (declare (ignore arguments))
              (error "test selection must not run"))))
        (expect (getf (cl-weave::watch-cycle-plan state state) :changed) :to-be nil))))
  (it
    "reloads only a changed component and its transitive dependents"
    (let* ((directory (make-test-temporary-directory "watch-forward-dependencies"))
           (system-name (string-downcase (symbol-name (gensym "CL-WEAVE-WATCH-FORWARD-"))))
           (source-names (list "provider" "unrelated" "dependent" "leaf")))
      (unwind-protect (progn
          (dolist (source-name source-names)
            (with-open-file (stream
                (merge-pathnames (make-pathname :name source-name :type "lisp") directory)
                :direction
                :output
                :if-exists
                :supersede
                :if-does-not-exist
                :create)
              (format stream "(in-package #:cl-user)~%")))
          (eval
            (list
              (quote asdf:defsystem)
              system-name
              :pathname
              directory
              :serial
              nil
              :components
              (quote
                ((:file "provider")
                  (:file "unrelated")
                  (:file "dependent" :depends-on ("provider"))
                  (:file "leaf" :depends-on ("dependent"))))))
          (let* ((system (asdf:find-system system-name))
                 (provider (asdf:find-component system "provider")))
            (multiple-value-bind (components pathnames) (cl-weave::incremental-system-reload-plan
                system
                (list (asdf:component-pathname provider)))
              (expect
                (mapcar (function asdf:component-name) components)
                :to-equal
                (list "provider" "dependent" "leaf"))
              (expect
                pathnames
                :to-equal
                (mapcar (function asdf:component-pathname) components)))))
        (when (asdf:find-system system-name nil)
          (asdf:clear-system system-name))
        (uiop:delete-directory-tree directory :validate t :if-does-not-exist :ignore))))
  (progn
(it
  "restores changed registrations between foreign sibling slots"
  (let* ((changed-pathname #P"/tmp/cl-weave/watch-changed-registration.lisp")
         (changed (cl-weave::changed-pathname-table (list changed-pathname)))
         (location (list :file changed-pathname))
         (root (cl-weave::make-suite :name "root"))
         (foreign-before
           (cl-weave::make-suite :name "foreign-before" :parent root))
         (old-changed
           (cl-weave::make-suite :name "old-changed" :parent root))
         (foreign-after
           (cl-weave::make-suite :name "foreign-after" :parent root))
         (new-changed
           (cl-weave::make-suite :name "new-changed" :parent root))
         (foreign-before-hook (lambda () :foreign-before))
         (old-changed-hook (lambda () :old-changed))
         (foreign-after-hook (lambda () :foreign-after))
         (new-changed-hook (lambda () :new-changed)))
    (let ((cl-weave::*root-suite* root)
          (cl-weave::*current-suite* root)
          (cl-weave::*registration-owners* (make-hash-table :test (function eq)))
          (cl-weave::*test-registry-generation* 0))
      (dolist (child (list foreign-before old-changed foreign-after))
        (cl-weave::add-child root child))
      (cl-weave::record-registration-owner old-changed location)
      (cl-weave::register-before-each foreign-before-hook)
      (cl-weave::register-before-each old-changed-hook :location location)
      (cl-weave::register-before-each foreign-after-hook)
      (let ((records
              (cl-weave::collect-suite-preservation-records root changed)))
        (cl-weave::prune-changed-registrations root changed)
        (cl-weave::add-child root new-changed)
        (cl-weave::record-registration-owner new-changed location)
        (cl-weave::register-before-each new-changed-hook :location location)
        (cl-weave::merge-suite-preservation-records root records))
      (expect
        (cl-weave::suite-children root)
        :to-equal
        (list foreign-before new-changed foreign-after))
      (expect
        (cl-weave::suite-before-each root)
        :to-equal
        (list foreign-before-hook new-changed-hook foreign-after-hook))
      (expect
        (count old-changed (cl-weave::suite-children root) :test (function eq))
        :to-be
        0)
      (expect
        (count new-changed (cl-weave::suite-children root) :test (function eq))
        :to-be
        1)
      (expect
        (count
          old-changed-hook
          (cl-weave::suite-before-each root)
          :test
          (function eq))
        :to-be
        0)
      (expect
        (count
          new-changed-hook
          (cl-weave::suite-before-each root)
          :test
          (function eq))
        :to-be
        1)
      (expect
        (cl-weave::suite-children-tail root)
        :to-be
        (last (cl-weave::suite-children root)))
      (expect
        (cl-weave::suite-before-each-tail root)
        :to-be
        (last (cl-weave::suite-before-each root))))))
(it
  "preserves duplicate suite identity when an earlier changed sibling is renamed"
  (let* ((changed-pathname
           #P"/tmp/cl-weave/watch-duplicate-suite-rename.lisp")
         (changed
           (cl-weave::changed-pathname-table
            (list changed-pathname)))
         (location (list :file changed-pathname))
         (root (cl-weave::make-suite :name "root"))
         (foreign-before
           (cl-weave::make-suite
            :name "duplicate" :parent root))
         (old-changed
           (cl-weave::make-suite
            :name "duplicate" :parent root))
         (foreign-after
           (cl-weave::make-suite
            :name "duplicate" :parent root))
         (renamed
           (cl-weave::make-suite
            :name "renamed" :parent root))
         (old-hook (lambda () :old))
         (new-hook (lambda () :new)))
    (let ((cl-weave::*root-suite* root)
          (cl-weave::*current-suite* root)
          (cl-weave::*registration-owners*
            (make-hash-table :test (function eq)))
          (cl-weave::*test-registry-generation* 0))
      (dolist
          (child
            (list foreign-before old-changed foreign-after))
        (cl-weave::add-child root child))
      (cl-weave::record-registration-owner
       old-changed location)
      (let ((cl-weave::*current-suite* foreign-after))
        (cl-weave::register-before-each
         old-hook :location location))
      (multiple-value-bind (records collection-visits)
          (cl-weave::collect-suite-preservation-records
           root changed)
        (expect collection-visits :to-be 4)
        (let ((preserved-node
                (car
                 (cl-weave::suite-preservation-node-children
                  records))))
          (expect
            (cl-weave::suite-preservation-node-segment
             preserved-node)
            :to-equal
            (cons "duplicate" 2))
          (expect
            (cl-weave::suite-preservation-node-suite
             preserved-node)
            :to-be
            foreign-after))
        (cl-weave::prune-changed-registrations
         root changed)
        (cl-weave::add-child root renamed)
        (cl-weave::record-registration-owner renamed location)
        (let ((cl-weave::*current-suite* foreign-after))
          (cl-weave::register-before-each
           new-hook :location location))
        (multiple-value-bind (merged-root merge-visits)
            (cl-weave::merge-suite-preservation-records
             root records)
          (expect merged-root :to-be root)
          (expect merge-visits :to-be 3)))
      (expect
        (cl-weave::suite-children root)
        :to-equal
        (list foreign-before renamed foreign-after))
      (expect (cl-weave::suite-parent foreign-before)
        :to-be root)
      (expect (cl-weave::suite-parent renamed)
        :to-be root)
      (expect (cl-weave::suite-parent foreign-after)
        :to-be root)
      (expect
        (cl-weave::suite-before-each foreign-after)
        :to-equal
        (list new-hook))
      (expect
        (cl-weave::suite-children-tail root)
        :to-be
        (last (cl-weave::suite-children root)))
      (expect
        (cl-weave::suite-before-each-tail foreign-after)
        :to-be
        (last
         (cl-weave::suite-before-each foreign-after))))))
(it
  "preserves every duplicate sibling ordinal with linear visits"
  (let* ((width 2048)
         (changed-pathname
           #P"/tmp/cl-weave/watch-duplicate-suite.lisp")
         (changed
           (cl-weave::changed-pathname-table
            (list changed-pathname)))
         (location (list :file changed-pathname))
         (root (cl-weave::make-suite :name "root")))
    (let ((cl-weave::*root-suite* root)
          (cl-weave::*current-suite* root)
          (cl-weave::*registration-owners*
            (make-hash-table :test (function eq)))
          (cl-weave::*test-registry-generation* 0))
      (dotimes (index width)
        (let ((suite
                (cl-weave::make-suite
                 :name "duplicate" :parent root))
              (hook (lambda () index)))
          (cl-weave::add-child root suite)
          (cl-weave::record-registration-owner suite location)
          (let ((cl-weave::*current-suite* suite))
            (cl-weave::register-before-each
             hook :location location))))
      (multiple-value-bind (tree collection-visits)
          (cl-weave::collect-suite-preservation-records
           root changed)
        (expect collection-visits :to-be (1+ width))
        (expect
          (mapcar
            (function cl-weave::suite-preservation-node-segment)
            (cl-weave::suite-preservation-node-children tree))
          :to-equal
          (loop for ordinal below width
                collect (cons "duplicate" ordinal)))
        (let ((replacement-root
                (cl-weave::make-suite :name "root"))
              (replacement-hooks nil))
          (setf cl-weave::*root-suite* replacement-root
                cl-weave::*current-suite* replacement-root)
          (dotimes (index width)
            (let ((suite
                    (cl-weave::make-suite
                     :name "duplicate"
                     :parent replacement-root))
                  (hook (lambda () index)))
              (cl-weave::add-child replacement-root suite)
              (cl-weave::record-registration-owner suite location)
              (let ((cl-weave::*current-suite* suite))
                (cl-weave::register-before-each
                 hook :location location))
              (push hook replacement-hooks)))
          (setf replacement-hooks (nreverse replacement-hooks))
          (multiple-value-bind (merged-root merge-visits)
              (cl-weave::merge-suite-preservation-records
               replacement-root tree)
            (expect merged-root :to-be replacement-root)
            (expect merge-visits :to-be width)
            (let ((children
                    (cl-weave::suite-children replacement-root)))
              (expect (length children) :to-be width)
              (expect
                (every
                  (lambda (suite)
                    (equal (cl-weave::suite-name suite)
                           "duplicate"))
                  children)
                :to-be
                t)
              (expect
                (every
                  (lambda (suite)
                    (eq (cl-weave::suite-parent suite)
                        replacement-root))
                  children)
                :to-be
                t)
              (expect
                (mapcar
                  (lambda (suite)
                    (first
                      (cl-weave::suite-before-each suite)))
                  children)
                :to-equal
                replacement-hooks)
              (expect
                (every
                  (lambda (suite)
                    (eq
                      (cl-weave::suite-before-each-tail suite)
                      (last
                        (cl-weave::suite-before-each suite))))
                  children)
                :to-be
                t)
              (expect
                (cl-weave::suite-children-tail replacement-root)
                :to-be
                (last children)))))))))
  (it
    "deduplicates dependency edges and terminates dependency cycles"
    (let* ((provider (gensym "PROVIDER-"))
           (unrelated (gensym "UNRELATED-"))
           (dependent (gensym "DEPENDENT-"))
           (cycle-peer (gensym "CYCLE-PEER-"))
           (components (list provider unrelated dependent cycle-peer))
           (pathnames (make-hash-table :test (function eq))))
      (setf
        (gethash provider pathnames) #P"/tmp/cl-weave/provider.lisp"
        (gethash unrelated pathnames) #P"/tmp/cl-weave/unrelated.lisp"
        (gethash dependent pathnames) #P"/tmp/cl-weave/dependent.lisp"
        (gethash cycle-peer pathnames) #P"/tmp/cl-weave/cycle-peer.lisp")
      (with-mocked-functions
        (((symbol-function (quote asdf:find-system))
            (lambda (system)
              system))
          ((symbol-function (quote asdf:required-components))
            (lambda (system)
              (declare (ignore system))
              components))
          ((symbol-function (quote asdf:make-operation))
            (lambda (operation-class)
              operation-class))
          ((symbol-function (quote asdf/plan:direct-dependencies))
            (lambda (operation component)
              (cond
                ((eq component dependent)
                  (list
                    (cons operation provider)
                    (cons operation cycle-peer)))
                ((eq component cycle-peer)
                  (list (cons operation dependent)))
                (t nil))))
          ((symbol-function (quote asdf:component-parent))
            (lambda (component)
              (declare (ignore component))
              nil))
          ((symbol-function (quote cl-weave::component-source-pathname))
            (lambda (component)
              (gethash component pathnames))))
        (multiple-value-bind (reload-components reload-pathnames)
            (cl-weave::incremental-system-reload-plan
              (gensym "SYSTEM-")
              (list (gethash provider pathnames)))
          (expect
            reload-components
            :to-equal
            (list provider dependent cycle-peer))
          (expect
            reload-pathnames
            :to-equal
            (list
              (gethash provider pathnames)
              (gethash dependent pathnames)
              (gethash cycle-peer pathnames)))))))
  (it
    "snapshots only the generation before a full system reload"
    (let* ((system (gensym "SYSTEM-"))
           (old-root (cl-weave::make-suite :name "old-root"))
           (clone-calls 0)
           (observed-load nil)
           (cl-weave::*root-suite* old-root)
           (cl-weave::*current-suite* old-root)
           (cl-weave::*named-suites* (make-hash-table :test (function equal)))
           (cl-weave::*registration-owners*
             (make-hash-table :test (function eq)))
           (cl-weave::*test-registry-generation* 11))
      (with-mocked-functions
        (((symbol-function (quote cl-weave::clone-test-registry-state))
            (lambda ()
              (incf clone-calls)
              (values
                cl-weave::*root-suite*
                (make-hash-table :test (function equal))
                (make-hash-table :test (function eq))
                cl-weave::*test-registry-generation*)))
          ((symbol-function (quote asdf:load-system))
            (lambda (loaded-system &key force)
              (setf observed-load (list loaded-system force))
              (cl-weave::register-suite "replacement" (lambda () nil))
              t)))
        (expect
          (cl-weave::atomic-full-system-reload system)
          :to-be
          t)
        (expect clone-calls :to-be 0)
        (expect observed-load :to-equal (list system t))
        (expect
          (eq cl-weave::*root-suite* old-root)
          :to-be
          nil)
        (expect
          cl-weave::*test-registry-generation*
          :to-be-greater-than
          11))))
))
