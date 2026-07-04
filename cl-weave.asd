(in-package #:asdf-user)

(defsystem "cl-weave"
  :description "A modern Common Lisp testing framework inspired by Vitest."
  :author "takeokunn"
  :license "MIT"
  :version "0.1.0"
  :serial t
  :components
  ((:module "src"
    :serial t
    :components
    ((:file "package")
     (:file "model")
     (:file "matchers")
     (:file "dsl")
     (:file "reporters")
     (:file "runner"))))
  :in-order-to ((test-op (test-op "cl-weave-tests"))))
