(let ((root (truename ".")))
  (dolist (path '("src/package.lisp"
                  "src/model.lisp"
                  "src/matchers.lisp"
                  "src/dsl.lisp"
                  "src/reporters.lisp"
                  "src/runner.lisp"
                  "tests/package.lisp"
                  "tests/core.lisp"))
    (load (merge-pathnames path root))))

(defun requested-reporter ()
  (let ((reporter #+sbcl (sb-ext:posix-getenv "CL_WEAVE_REPORTER")
                  #-sbcl nil))
    (cond
      ((or (null reporter) (string= reporter "") (string-equal reporter "spec")) :spec)
      ((string-equal reporter "sexp") :sexp)
      ((string-equal reporter "junit") :junit)
      (t (error "Unknown CL_WEAVE_REPORTER value: ~A" reporter)))))

#+sbcl
(sb-ext:exit :code (if (cl-weave:run-all :reporter (requested-reporter)) 0 1))

#-sbcl
(error "scripts/run-tests.lisp currently requires SBCL.")
