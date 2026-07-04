(defpackage #:cl-weave/tests
  (:use #:cl)
  (:shadowing-import-from #:cl-weave
   #:describe)
  (:import-from #:cl-weave
   #:*test-context*
   #:after-each
   #:assertion-failure
   #:before-each
   #:clear-tests
   #:expect
   #:it
   #:it-each
   #:with-mocked-functions))
