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

#+sbcl
(sb-ext:exit :code (if (cl-weave:run-all :reporter :spec) 0 1))

#-sbcl
(error "scripts/run-tests.lisp currently requires SBCL.")
