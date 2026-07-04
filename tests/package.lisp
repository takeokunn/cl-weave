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
    #:expect
    #:gen-boolean
    #:gen-integer
    #:gen-list
    #:gen-member
    #:gen-one-of
    #:gen-such-that
    #:gen-tuple
    #:it
    #:it-each
    #:it-property
    #:it-only
   #:it-skip
   #:it-todo
   #:make-mock-function
   #:mock-calls
   #:with-mocked-functions))
