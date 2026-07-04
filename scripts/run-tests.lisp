(require :asdf)

(let ((root (truename ".")))
  (pushnew root asdf:*central-registry* :test #'equal)
  (asdf:load-asd (merge-pathnames "cl-weave.asd" root))
  (asdf:load-asd (merge-pathnames "cl-weave-tests.asd" root))
  (dolist (path '("src/package.lisp"
                  "src/model.lisp"
                  "src/isolation.lisp"
                  "src/matchers.lisp"
                  "src/property.lisp"
                  "src/dsl.lisp"
                  "src/reporters.lisp"
                  "src/runner.lisp"
                  "src/watch.lisp"
                  "tests/package.lisp"
                  "tests/core.lisp"))
    (load (merge-pathnames path root))))

(defun requested-reporter ()
  (let ((reporter #+sbcl (sb-ext:posix-getenv "CL_WEAVE_REPORTER")
                  #-sbcl nil))
    (cond
      ((or (null reporter) (string= reporter "") (string-equal reporter "spec")) :spec)
      ((string-equal reporter "sexp") :sexp)
      ((string-equal reporter "json") :json)
      ((string-equal reporter "junit") :junit)
      (t (error "Unknown CL_WEAVE_REPORTER value: ~A" reporter)))))

(defun requested-test-filter ()
  #+sbcl
  (let ((filter (sb-ext:posix-getenv "CL_WEAVE_TEST_FILTER")))
    (when (and filter (not (string= filter "")))
      filter))
  #-sbcl
  nil)

(defun requested-output-file ()
  #+sbcl
  (let ((path (sb-ext:posix-getenv "CL_WEAVE_OUTPUT_FILE")))
    (when (and path (not (string= path "")))
      path))
  #-sbcl
  nil)

(defun requested-watch-p ()
  #+sbcl
  (let ((value (sb-ext:posix-getenv "CL_WEAVE_WATCH")))
    (and value
         (not (string= value ""))
         (not (string= value "0"))
         (not (string-equal value "false"))))
  #-sbcl
  nil)

(defun requested-watch-interval ()
  #+sbcl
  (let ((value (sb-ext:posix-getenv "CL_WEAVE_WATCH_INTERVAL")))
    (if (and value (not (string= value "")))
        (multiple-value-bind (parsed position)
            (let ((*read-eval* nil))
              (read-from-string value))
          (unless (and (numberp parsed)
                       (plusp parsed)
                       (loop for index from position below (length value)
                             always (find (char value index)
                                          '(#\Space #\Tab #\Newline #\Return))))
            (error "CL_WEAVE_WATCH_INTERVAL must be a positive number: ~A" value))
          parsed)
        0.5))
  #-sbcl
  0.5)

#+sbcl
(if (requested-watch-p)
    (cl-weave:watch-system "cl-weave-tests"
                           :reporter (requested-reporter)
                           :name-filter (requested-test-filter)
                           :include-dependencies t
                           :interval (requested-watch-interval))
    (let ((output-file (requested-output-file)))
      (flet ((run-with-stream (stream)
               (cl-weave:run-all
                :reporter (requested-reporter)
                :name-filter (requested-test-filter)
                :stream stream)))
        (sb-ext:exit
         :code (if (if output-file
                       (with-open-file (stream output-file
                                               :direction :output
                                               :if-exists :supersede
                                               :if-does-not-exist :create)
                         (run-with-stream stream))
                       (run-with-stream *standard-output*))
                   0
                   1)))))

#-sbcl
(error "scripts/run-tests.lisp currently requires SBCL.")
