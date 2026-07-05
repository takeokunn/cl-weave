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
     (:file "logic")
     (:file "isolation")
     (:file "snapshots")
     (:file "mocks")
     (:file "matchers")
     (:file "property")
     (:file "mutation")
     (:file "dsl")
     (:file "reporters")
     (:file "runner")
     (:file "runner-api")
     (:file "watch")
     (:file "cli-options")
     (:file "cli-metadata-data")
     (:file "cli-metadata")
     (:file "cli")
     (:file "cli-execution"))))
  :in-order-to ((test-op (test-op "cl-weave-tests"))))
