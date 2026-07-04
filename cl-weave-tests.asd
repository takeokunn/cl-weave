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
     (:file "core"))))
  :perform (test-op (op c)
             (declare (ignore op c))
             (unless (uiop:symbol-call :cl-weave :run-all :reporter :spec)
               (uiop:quit 1))))
