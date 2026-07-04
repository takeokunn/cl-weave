(defpackage #:cl-weave
  (:use #:cl)
  (:shadow #:describe)
  (:export
   #:*test-context*
   #:after-all
   #:after-each
   #:assertion-failure
   #:before-all
   #:before-each
   #:clear-tests
   #:describe
   #:describe-only
   #:expect
   #:it
   #:it-each
   #:it-only
   #:it-skip
   #:it-todo
   #:run-all
   #:test
   #:test-only
   #:test-skip
   #:test-todo
   #:test-failure
   #:with-mocked-functions))
