(in-package #:asdf-user)

(defsystem "cl-weave-tests"
  :description "Self tests for cl-weave."
  :author "takeokunn"
  :license "MIT"
  :depends-on ("cl-weave")
  :serial t
  :components
  ((:module "tests"
    :serial t
    :components
    ((:file "package")
     (:file "support")
     (:file "expect")
     (:file "macros")
     (:file "isolation")
     (:file "properties")
     (:file "mutation")
     (:file "fixtures")
     (:file "cps")
     (:file "retry-timeout")
     (:file "concurrent")
     (:file "coverage")
     (:file "expected-failures")
     (:file "skips")
     (:file "todos")
     (:file "focus")
     (:file "filtering")
     (:file "sharding")
     (:file "sequence")
     (:file "list-mode")
     (:file "bail")
     (:file "cli")
     (:file "asdf-integration")
     (:file "mocking")
     (:file "reporters"))))
  :perform (test-op (op c)
             (declare (ignore op c))
             (unless (uiop:symbol-call :cl-weave :run-all :reporter :spec)
               (uiop:quit 1))))
