(in-package #:cl-weave/tests)

(describe "property environment and macro expansion"
  (it "rejects invalid shrink step limits"
    (let ((cl-weave:*property-shrink-max-steps* -1))
      (expect (lambda ()
                (cl-weave::shrink-property-values nil '(1) #'identity))
              :to-throw
              'type-error)))

  (it "uses property count from the CI environment"
    (let ((runs 0))
      (with-mocked-functions
          (((symbol-function 'uiop:getenv)
            (lambda (name)
              (cond
                ((string= name "CL_WEAVE_PROPERTY_TESTS") "3")
                ((string= name "CL_WEAVE_PROPERTY_SEED") "5")
                (t nil)))))
        (cl-weave::run-property
         (list (gen-integer :min 1 :max 1))
         (lambda (value)
           (expect value :to-be 1)
           (incf runs)
           t)
         '(value)
         '(property-env-count)))
      (expect runs :to-be 3)))

  (it "rejects invalid property count environment values"
    (with-mocked-functions
        (((symbol-function 'uiop:getenv)
          (lambda (name)
            (when (string= name "CL_WEAVE_PROPERTY_TESTS")
              "not-a-number"))))
      (expect (lambda ()
                (cl-weave::run-property
                 (list (gen-integer :min 1 :max 1))
                 (lambda (value)
                   (declare (ignore value))
                   t)
                 '(value)
                 '(property-invalid-count)))
              :to-throw
              "CL_WEAVE_PROPERTY_TESTS")))

  (it "rejects non-positive property counts"
    (let ((cl-weave:*property-test-count* 0))
      (expect (lambda ()
                (cl-weave::run-property
                 (list (gen-integer :min 1 :max 1))
                 (lambda (value)
                   (declare (ignore value))
                   t)
                 '(value)
                 '(property-zero-count)))
              :to-throw
              "positive integer")))

  (it "rejects invalid property seed environment values"
    (with-mocked-functions
        (((symbol-function 'uiop:getenv)
          (lambda (name)
            (when (string= name "CL_WEAVE_PROPERTY_SEED")
              "not-a-seed"))))
      (expect (lambda ()
                (cl-weave::run-property
                 (list (gen-integer :min 1 :max 1))
                 (lambda (value)
                   (declare (ignore value))
                   t)
                 '(value)
                 '(property-invalid-seed)))
              :to-throw
              "CL_WEAVE_PROPERTY_SEED")))

  (it "expands it-property into the property runner"
    (expect (macroexpand-1
             '(it-property "positive identity"
                  ((value (gen-integer :min 1 :max 3)))
                (expect value :to-be value)))
            :to-satisfy
            (lambda (form)
              (tree-contains-p form 'cl-weave::run-property)))))
(defmutation-operator :keyword-toggle (form path)
  "Toggles :enabled keyword literals to :disabled."
  (declare (ignore path))
  (when (eq form :enabled)
    (list :disabled)))
