(in-package #:asdf-user)

(defsystem "cl-weave"
  :description "A modern Common Lisp testing framework inspired by Vitest."
  :author "takeokunn"
  :license "MIT"
  :homepage "https://github.com/takeokunn/cl-weave"
  :bug-tracker "https://github.com/takeokunn/cl-weave/issues"
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
     (:file "registration")
     (:file "fixtures")
     (:file "continuations")
     (:file "expect-runtime")
     (:file "expect")
     (:file "reporter-schema")
     (:file "reporter-json")
     (:file "reporter-results")
     (:file "reporter-tap")
     (:file "reporter-github")
     (:file "reporter-plan")
     (:file "reporter-mutation")
     (:file "reporter-junit")
     (:file "runner-execution")
     (:file "runner-selection")
     (:file "runner-planning")
     (:file "runner-concurrency")
     (:file "runner-collection")
     (:file "runner-api")
     (:file "watch")
     (:file "cli-options")
     (:file "cli-metadata-data")
     (:file "cli-metadata")
     (:file "cli")
     (:file "cli-execution"))))
  :in-order-to ((test-op (test-op "cl-weave-tests"))))
