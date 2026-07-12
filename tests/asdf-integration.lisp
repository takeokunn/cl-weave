(in-package #:cl-weave/tests)

(describe "asdf integration"
  (it "reloads systems through ASDF without accumulating registered tests"
    (let ((loaded-systems nil)
          (suite-counts nil)
          (cl-weave::*root-suite* nil)
          (cl-weave::*current-suite* nil)
          (cl-weave::*named-suites* (make-hash-table :test #'equal)))
      (with-mocked-functions
          (((symbol-function 'asdf:load-system)
            (lambda (system &key force)
              (push (list system force) loaded-systems)
              (cl-weave::register-suite "loaded" (lambda () nil))
              t))
           ((symbol-function 'cl-weave:run-all)
            (lambda (&rest arguments)
              (declare (ignore arguments))
              (push (length (cl-weave::suite-children
                             (cl-weave::root-suite)))
                    suite-counts)
              t)))
        (expect (cl-weave:run-system "cl-weave/tests") :to-be-truthy)
        (expect (cl-weave:run-system "cl-weave/tests") :to-be-truthy)
        (expect (nreverse loaded-systems)
                :to-equal '(("cl-weave/tests" t) ("cl-weave/tests" t)))
        (expect (nreverse suite-counts) :to-equal '(1 1)))))

  (it "clears registered tests before each watched system reload"
    (let ((suite-counts nil))
      (labels ((mock-run-system (system &rest arguments)
                 (declare (ignore system arguments))
                 (cl-weave::register-suite "watched" (lambda () nil))
                 (push (length (cl-weave::suite-children
                                (cl-weave::root-suite)))
                       suite-counts)
                 t))
        (with-mocked-functions
            (((symbol-function 'cl-weave:run-system) #'mock-run-system))
          (cl-weave::run-watched-system "watched")
          (cl-weave::run-watched-system "watched")))
      (expect suite-counts :to-equal '(1 1))))

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

  (it "detects changed file states"
    (let* ((pathname #P"/tmp/cl-weave-watch-state.lisp")
           (deleted #P"/tmp/cl-weave-watch-deleted.lisp")
           (old-state (list (cons pathname 1)
                            (cons deleted 7)))
           (new-state (list (cons pathname 2))))
      (expect (cl-weave::changed-pathnames old-state new-state)
              :to-equal (list pathname deleted))
      (expect (cl-weave::changed-pathnames new-state new-state)
              :to-equal nil)))

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
                      :new-state new-state)))))

  (it "derives a full-suite watch plan for the initial run"
    (let* ((test-file #P"/tmp/cl-weave/watch-plan-initial.lisp")
           (new-state (list (cons test-file 1))))
      (expect (cl-weave::watch-cycle-plan nil new-state)
              :to-equal
              (list :changed (list test-file)
                    :location-filter nil
                    :scope :full-suite
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
                                  pass-with-no-tests retry timeout-ms
                                  max-workers)
              (declare (ignore stream))
              (push (list system reporter name-filter shard order seed bail
                          location-filter coverage coverage-output
                          pass-with-no-tests retry timeout-ms max-workers)
                    calls)
              t)))
        (setf output
              (with-output-to-string (stream)
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
                        :to-be-truthy))))
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
            (((symbol-function 'cl-weave:asdf-system-files)
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
                                    pass-with-no-tests retry timeout-ms
                                    max-workers)
                (declare (ignore stream))
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
          (setf output
                (with-output-to-string (stream)
                  (catch 'watch-stop
                    (cl-weave:watch-system
                     "cl-weave"
                     :reporter :json
                     :stream stream
                     :status-stream stream
                     :name-filter "watch"
                     :once nil))))))
      (expect (reverse calls)
              :to-satisfy
              (lambda (value)
                (equal value
                       (list (list "cl-weave" :json "watch" nil nil nil nil nil
                                   nil nil nil nil nil nil)
                             (list "cl-weave" :json "watch" (list test-file)
                                   nil nil nil nil nil nil nil nil nil nil)))))
      (expect output :to-contain "CHANGED-TESTS")))

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
            (((symbol-function 'cl-weave:asdf-system-files)
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
                                    pass-with-no-tests retry timeout-ms
                                    max-workers)
                (declare (ignore stream))
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
          (setf output
                (with-output-to-string (stream)
                  (catch 'watch-stop
                    (cl-weave:watch-system
                     "cl-weave"
                     :reporter :json
                     :stream stream
                     :status-stream stream
                     :name-filter "watch"
                     :once nil))))))
      (expect (reverse calls)
              :to-satisfy
              (lambda (value)
                (equal value
                       (list (list "cl-weave" :json "watch" nil nil nil nil nil
                                   nil nil nil nil nil nil)
                             (list "cl-weave" :json "watch" nil nil nil nil nil
                                   nil nil nil nil nil nil)))))
      (expect output :to-contain "FULL-SUITE"))))
