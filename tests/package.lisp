(defpackage #:cl-weave/tests
  (:use #:cl)
  (:shadowing-import-from #:cl-weave
   #:describe)
  (:import-from #:cl-weave
   #:*test-context*
   #:after-all
   #:after-each
   #:assertion-failure
   #:before-all
   #:before-each
   #:clear-mock
   #:clear-tests
   #:describe-each
   #:describe-skip
   #:describe-todo
   #:expect
   #:gen-boolean
   #:gen-form
   #:gen-integer
   #:gen-keyword
   #:gen-list
   #:gen-map
   #:gen-member
   #:gen-one-of
   #:gen-recursive
   #:gen-sexp
   #:gen-such-that
   #:gen-symbol
   #:gen-tuple
   #:it
   #:it-each
   #:it-isolated
   #:it-property
   #:it-only
   #:it-skip
   #:it-todo
   #:isolated-result-exit-code
   #:isolated-result-status
   #:isolated-result-stderr
   #:isolated-result-timed-out-p
   #:make-mock-function
   #:mock-calls
   #:run-isolated
   #:test-each
   #:with-mocked-functions))
