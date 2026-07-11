(in-package #:cl-weave/tests)

(describe "mutation testing"
  (it "collects one-at-a-time form mutations"
    (let ((mutations (collect-mutations '(if (= value 1) (+ value 2) nil))))
      (expect (mapcar #'mutation-operator mutations) :to-contain :comparison-operator)
      (expect (mapcar #'mutation-operator mutations) :to-contain :arithmetic-operator)
      (expect (mapcar #'mutation-operator mutations) :to-contain :boolean-literal)
      (expect (mapcar #'mutation-operator mutations) :to-contain :conditional-branch)
      (expect (mapcar #'mutation-form mutations) :to-contain
              '(if (/= value 1) (+ value 2) nil))
      (expect (mapcar #'mutation-form mutations) :to-contain
              '(if (= value 1) (- value 2) nil))))

  (it "lists mutation operators as deterministic metadata"
    (let ((operators (list-mutation-operators))
          (custom-metadata (mutation-operator-metadata :keyword-toggle)))
      (expect (mapcar (lambda (entry) (getf entry :name)) operators)
              :to-contain
              :arithmetic-operator)
      (expect (mapcar (lambda (entry) (getf entry :name)) operators)
              :to-contain
              :keyword-toggle)
      (expect (getf (mutation-operator-metadata :arithmetic-operator) :description)
              :to-contain
              "arithmetic")
      (expect (getf custom-metadata :description)
              :to-equal
              "Toggles :enabled keyword literals to :disabled.")))

  (it "supports macro-defined custom mutation operators"
    (let ((mutations (collect-mutations '(:enabled)
                                        :operators '(:keyword-toggle))))
      (expect (length mutations) :to-be 1)
      (expect (mutation-operator (first mutations)) :to-be :keyword-toggle)
      (expect (mutation-path (first mutations)) :to-equal '(0))
      (expect (mutation-original (first mutations)) :to-be :enabled)
      (expect (mutation-replacement (first mutations)) :to-be :disabled)
      (expect (mutation-form (first mutations)) :to-equal '(:disabled))))

  (it "marks surviving and killed mutants"
    (let* ((results (run-mutations '(+ 1 1)
                                   (lambda (form mutation)
                                     (declare (ignore mutation))
                                     (= (eval form) 2))))
           (summary (mutation-summary results)))
      (expect (mapcar #'mutation-result-status results) :to-contain :killed)
      (expect (getf summary :total) :to-be 1)
      (expect (getf summary :killed) :to-be 1)
      (expect (getf summary :survived) :to-be 0)
      (expect (getf summary :score) :to-be 1.0)))

  (it "checks mutation score quality gates for CI"
    (let ((killed (run-mutations '(+ 1 1)
                                 (lambda (form mutation)
                                   (declare (ignore mutation))
                                   (= (eval form) 2))))
          (survived (run-mutations '(+ 1 1)
                                   (lambda (form mutation)
                                     (declare (ignore form mutation))
                                     t))))
      (multiple-value-bind (pass-p summary)
          (mutation-score-passes-p killed 1.0)
        (expect pass-p :to-be t)
        (expect (getf summary :score) :to-be 1.0))
      (multiple-value-bind (pass-p summary)
          (mutation-score-passes-p survived 1.0)
        (expect pass-p :to-be nil)
        (expect (getf summary :survived) :to-be 1))
      (expect (assert-mutation-score killed 1.0) :to-satisfy #'listp)
      (handler-case
          (progn
            (assert-mutation-score survived 1.0)
            (expect nil :to-be t))
        (mutation-score-failure (condition)
          (expect (mutation-score-failure-min-score condition) :to-be 1.0)
          (expect (getf (mutation-score-failure-summary condition) :survived)
                  :to-be 1)))))

  (it "keeps unexpected harness errors visible"
    (let* ((results (run-mutations '(+ 1 1)
                                   (lambda (form mutation)
                                     (declare (ignore form mutation))
                                     (error "harness failed"))))
           (summary (mutation-summary results)))
      (expect (mapcar #'mutation-result-status results) :to-contain :errored)
      (expect (getf summary :errored) :to-be 1)))

  (it "prints AI-readable mutation reports"
    (let* ((results (run-mutations '(+ 1 1)
                                   (lambda (form mutation)
                                     (declare (ignore mutation))
                                     (= (eval form) 2))))
           (sexp-output (with-output-to-string (stream)
                          (report-mutations-sexp results stream)))
           (json-output (with-output-to-string (stream)
                          (report-mutations-json results stream))))
      (expect sexp-output :to-contain ":CL-WEAVE/MUTATIONS")
      (expect sexp-output :to-contain ":SCHEMA-VERSION 1")
      (expect sexp-output :to-contain ":OPERATOR :ARITHMETIC-OPERATOR")
      (expect json-output :to-contain "\"kind\":\"mutations\"")
      (expect json-output :to-contain "\"killed\":1")
      (expect json-output :to-contain "\"operator\":\"ARITHMETIC-OPERATOR\""))))
