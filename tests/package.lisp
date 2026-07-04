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
   #:clear-tests
   #:expect
   #:it
   #:it-each
   #:it-only
   #:it-skip
   #:it-todo
   #:with-mocked-functions))
