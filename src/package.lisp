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
   #:expect
   #:it
   #:it-each
   #:it-skip
   #:run-all
   #:test
   #:test-skip
   #:test-failure
   #:with-mocked-functions))
