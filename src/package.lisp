(defpackage #:cl-weave
  (:use #:cl)
  (:shadow #:describe)
  (:export
   #:*test-context*
   #:after-each
   #:assertion-failure
   #:before-each
   #:clear-tests
   #:describe
   #:expect
   #:it
   #:it-each
   #:run-all
   #:test
   #:test-failure
   #:with-mocked-functions))
