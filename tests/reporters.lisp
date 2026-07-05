(in-package #:cl-weave/tests)

(describe "reporters"
  (it "rejects unknown run reporters before dispatch"
    (expect (lambda ()
              (with-output-to-string (stream)
                (cl-weave:run-all :reporter :unknown :stream stream)))
            :to-throw
            "cl-weave: run mode supports"))

  (it "prints AI-readable S-expression results"
    (let ((output (with-output-to-string (stream)
                      (cl-weave::report-sexp
                      (list (cl-weave::make-test-event
                             :status :pass
                             :path '("reporters" "prints")
                             :location '(:file "tests/reporters.lisp")
                             :elapsed-internal-time 0)
                            (cl-weave::make-test-event
                             :status :skip
                             :path '("reporters" "skips")
                             :reason "example"
                             :elapsed-internal-time 0)
                            (cl-weave::make-test-event
                            :status :todo
                            :path '("reporters" "todos")
                            :reason "pending"
                             :elapsed-internal-time 0)
                            (cl-weave::make-test-event
                             :status :fail
                             :path '("reporters" "fails")
                             :reason "bad"
                             :elapsed-internal-time 0)
                            (cl-weave::make-test-event
                             :status :error
                             :path '("reporters" "errors")
                             :elapsed-internal-time 0))
                      stream))))
      (expect output :to-contain ":CL-WEAVE/RESULTS")
      (expect output :to-contain ":SCHEMA-VERSION 3")
      (expect output :to-contain ":PATH-STRING \"reporters > prints\"")
      (expect output :to-contain ":LOCATION (:FILE \"tests/reporters.lisp\")")
      (expect output :to-contain ":DURATION-MS 0")
      (expect output :to-contain ":SKIPPED")
      (expect output :to-contain ":TODOS")
      (expect output :to-contain ":TODO")
      (expect output :to-contain ":FAILED-PATHS")
      (expect output :to-contain "\"reporters > fails\"")
      (expect output :to-contain ":ERRORED-PATHS")
      (expect output :to-contain "\"reporters > errors\"")))

  (it "prints AI-readable JSON results"
    (let ((output (with-output-to-string (stream)
                    (cl-weave::report-json
                     (list (cl-weave::make-test-event
                            :status :pass
                            :path '("reporters" "json")
                            :location '(:file "tests/reporters.lisp")
                            :elapsed-internal-time 0)
                           (cl-weave::make-test-event
                            :status :skip
                            :path '("reporters" "quotes")
                            :reason "needs \"escaping\""
                            :elapsed-internal-time 0)
                           (cl-weave::make-test-event
                            :status :fail
                            :path '("reporters" "fails")
                            :reason "bad"
                            :elapsed-internal-time 0)
                           (cl-weave::make-test-event
                            :status :error
                            :path '("reporters" "errors")
                            :elapsed-internal-time 0))
                     stream))))
      (expect output :to-contain "\"schemaVersion\":5")
      (expect output :to-contain "\"kind\":\"test-results\"")
      (expect output :to-contain "\"passed\":1")
      (expect output :to-contain "\"skipped\":1")
      (expect output :to-contain "\"failed\":1")
      (expect output :to-contain "\"errored\":1")
      (expect output :to-contain "\"failedPaths\":[\"reporters > fails\"]")
      (expect output :to-contain "\"erroredPaths\":[\"reporters > errors\"]")
      (expect output :to-contain "\"status\":\"pass\"")
      (expect output :to-contain "\"path\":[\"reporters\",\"json\"]")
      (expect output :to-contain "\"pathString\":\"reporters > json\"")
      (expect output :to-contain "\"location\":{\"file\":\"tests\\/reporters.lisp\"}")
      (expect output :to-contain "\"durationMs\":0.000")
      (expect output :to-contain "\"reason\":\"needs \\\"escaping\\\"\"")
      (expect output :to-contain "\"assertion\":null")))

  (it "serializes assertion payloads as structured JSON data"
    (let ((output (with-output-to-string (stream)
                    (cl-weave::report-json
                     (list (cl-weave::make-test-event
                            :status :fail
                            :path '("reporters" "isolated")
                            :condition "isolated process failed"
                            :assertion (cl-weave::make-assertion-detail
                                        :form '(expect (run-isolated body) :to-satisfy #'identity)
                                        :matcher :isolated
                                        :actual '(:status :timeout
                                                  :exit-code nil
                                                  :timed-out-p t
                                                  :elapsed-ms 100
                                                  :stdout ""
                                                  :stderr ""
                                                  :script-path "/tmp/cl-weave-isolated.lisp"
                                                  :stdout-path "/tmp/cl-weave-isolated.stdout"
                                                  :stderr-path "/tmp/cl-weave-isolated.stderr"
                                                  :home-path "/tmp/cl-weave-home/")
                                        :expected '(:status :pass :exit-code 0)
                                        :negated nil
                                        :pass nil)
                            :elapsed-internal-time 0))
                     stream))))
      (expect output :to-contain "\"schemaVersion\":5")
      (expect output :to-contain "\"matcher\":\":ISOLATED\"")
      (expect output :to-contain "\"actual\":{\"status\":\"timeout\"")
      (expect output :to-contain "\"timedOutP\":true")
      (expect output :to-contain "\"elapsedMs\":100")
      (expect output :to-contain "\"scriptPath\":\"\\/tmp\\/cl-weave-isolated.lisp\"")
      (expect output :to-contain "\"stdoutPath\":\"\\/tmp\\/cl-weave-isolated.stdout\"")
      (expect output :to-contain "\"stderrPath\":\"\\/tmp\\/cl-weave-isolated.stderr\"")
      (expect output :to-contain "\"homePath\":\"\\/tmp\\/cl-weave-home\\/\"")
      (expect output :to-contain "\"expected\":{\"status\":\"pass\",\"exitCode\":0}")))

  (it "prints AI-readable JSONL result streams"
    (let ((output (with-output-to-string (stream)
                    (cl-weave::report-jsonl
                     (list (cl-weave::make-test-event
                            :status :pass
                            :path '("reporters" "jsonl")
                            :location '(:file "tests/reporters.lisp")
                            :elapsed-internal-time 0)
                           (cl-weave::make-test-event
                            :status :fail
                            :path '("reporters" "fails")
                            :reason "bad"
                            :elapsed-internal-time 0))
                     stream))))
      (expect (with-input-from-string (stream output)
                (loop for line = (read-line stream nil nil)
                      while line
                      count line))
              :to-be 4)
      (expect output :to-contain "\"kind\":\"test-results-start\"")
      (expect output :to-contain "\"schemaVersion\":1,\"kind\":\"test-results-start\"")
      (expect output :to-contain "\"total\":2")
      (expect output :to-contain "\"kind\":\"test-event\"")
      (expect output :to-contain "\"schemaVersion\":2,\"kind\":\"test-event\"")
      (expect output :to-contain "\"event\":{\"status\":\"pass\"")
      (expect output :to-contain "\"pathString\":\"reporters > jsonl\"")
      (expect output :to-contain "\"kind\":\"test-results-summary\"")
      (expect output :to-contain "\"schemaVersion\":1,\"kind\":\"test-results-summary\"")
      (expect output :to-contain "\"failed\":1")
      (expect output :to-contain "\"failedPaths\":[\"reporters > fails\"]")))

  (it "escapes JSON strings with portable control-character rules"
    (let ((escaped (cl-weave::json-escaped-string
                    (coerce (list #\" #\\
                                  (code-char 8)
                                  (code-char 9)
                                  (code-char 10)
                                  (code-char 12)
                                  (code-char 13)
                                  (code-char 1))
                            'string))))
      (expect escaped :to-equal
              (concatenate 'string
                           "\\\""
                           "\\\\"
                           "\\b"
                           "\\t"
                           "\\n"
                           "\\f"
                           "\\r"
                           "\\u0001"))))

  (it "prints AI-readable S-expression test plans"
    (let ((output (with-output-to-string (stream)
                    (cl-weave::report-plan-sexp
                     (list (cl-weave::make-test-plan-entry
                            :status :run
                           :path '("plan" "runs")
                            :location '(:file "tests/plan.lisp")
                            :focused t
                            :retry 2
                            :timeout-ms 250
                            :concurrent t)
                           (cl-weave::make-test-plan-entry
                            :status :skip
                            :path '("plan" "skips")
                            :reason "blocked"
                            :focused nil
                            :retry 0))
                     stream))))
      (expect output :to-contain ":CL-WEAVE/TEST-PLAN")
      (expect output :to-contain ":SCHEMA-VERSION 2")
      (expect output :to-contain ":RUNNABLE 1")
      (expect output :to-contain ":SKIPPED 1")
      (expect output :to-contain ":PATH-STRING \"plan > runs\"")
      (expect output :to-contain ":LOCATION")
      (expect output :to-contain ":FILE \"tests/plan.lisp\"")
      (expect output :to-contain ":FOCUSED T")
      (expect output :to-contain ":TIMEOUT-MS 250")
      (expect output :to-contain ":CONCURRENT T")))

  (it "prints AI-readable JSON test plans"
    (let ((output (with-output-to-string (stream)
                    (cl-weave::report-plan-json
                     (list (cl-weave::make-test-plan-entry
                            :status :run
                            :path '("plan" "runs")
                            :location '(:file "tests/plan.lisp")
                            :focused t
                            :retry 2
                            :timeout-ms 250
                            :concurrent t)
                           (cl-weave::make-test-plan-entry
                            :status :skip
                            :path '("plan" "skips")
                            :reason "blocked"
                            :focused nil
                            :retry 0))
                     stream))))
      (expect output :to-contain "\"schemaVersion\":2")
      (expect output :to-contain "\"kind\":\"test-plan\"")
      (expect output :to-contain "\"runnable\":1")
      (expect output :to-contain "\"skipped\":1")
      (expect output :to-contain "\"status\":\"run\"")
      (expect output :to-contain "\"pathString\":\"plan > runs\"")
      (expect output :to-contain "\"location\":{\"file\":\"tests\\/plan.lisp\"}")
      (expect output :to-contain "\"focused\":true")
      (expect output :to-contain "\"retry\":2")
      (expect output :to-contain "\"timeoutMs\":250")
      (expect output :to-contain "\"concurrent\":true")
      (expect output :to-contain "\"reason\":\"blocked\"")))

  (it "prints AI-readable JSONL test plans"
    (let ((output (with-output-to-string (stream)
                    (cl-weave::report-plan-jsonl
                     (list (cl-weave::make-test-plan-entry
                            :status :run
                            :path '("plan" "runs")
                            :location '(:file "tests/plan.lisp")
                            :focused t
                            :retry 2
                            :timeout-ms 250
                            :concurrent t)
                           (cl-weave::make-test-plan-entry
                            :status :skip
                            :path '("plan" "skips")
                            :reason "blocked"
                            :focused nil
                            :retry 0))
                     stream))))
      (expect (with-input-from-string (stream output)
                (loop for line = (read-line stream nil nil)
                      while line
                      count line))
              :to-be 4)
      (expect output :to-contain "\"kind\":\"test-plan-start\"")
      (expect output :to-contain "\"schemaVersion\":1,\"kind\":\"test-plan-start\"")
      (expect output :to-contain "\"kind\":\"test-plan-entry\"")
      (expect output :to-contain "\"schemaVersion\":1,\"kind\":\"test-plan-entry\"")
      (expect output :to-contain "\"test\":{\"status\":\"run\"")
      (expect output :to-contain "\"pathString\":\"plan > runs\"")
      (expect output :to-contain "\"kind\":\"test-plan-summary\"")
      (expect output :to-contain "\"schemaVersion\":1,\"kind\":\"test-plan-summary\"")
      (expect output :to-contain "\"runnable\":1")
      (expect output :to-contain "\"skipped\":1")))

  (it "prints CI-readable JUnit XML results"
    (let ((output (with-output-to-string (stream)
                    (cl-weave::report-junit
                     (list (cl-weave::make-test-event
                            :status :pass
                            :path '("reporters" "passes")
                            :elapsed-internal-time 0)
                           (cl-weave::make-test-event
                            :status :skip
                            :path '("reporters" "skips")
                            :reason "needs <thing>"
                            :elapsed-internal-time 0)
                           (cl-weave::make-test-event
                            :status :todo
                            :path '("reporters" "todos")
                            :reason "pending"
                            :elapsed-internal-time 0)
                           (cl-weave::make-test-event
                            :status :fail
                            :path '("reporters" "fails")
                            :reason "bad <value> & reason"
                            :elapsed-internal-time 0))
                     stream))))
      (expect output :to-contain "<?xml version=\"1.0\" encoding=\"UTF-8\"?>")
      (expect output :to-contain "<testsuite name=\"cl-weave\" tests=\"4\"")
      (expect output :to-contain "failures=\"1\"")
      (expect output :to-contain "errors=\"0\"")
      (expect output :to-contain "skipped=\"2\"")
      (expect output :to-contain "<skipped message=\"needs &lt;thing&gt;\"/>")
      (expect output :to-contain "<skipped message=\"TODO: pending\"/>")
      (expect output :to-contain "<failure message=\"bad &lt;value&gt; &amp; reason\">")))

  (it "sanitizes JUnit XML strings with portable control-character rules"
    (let ((escaped (cl-weave::xml-escaped-string
                    (coerce (list #\< #\> #\& #\" #\'
                                  (code-char 9)
                                  (code-char 10)
                                  (code-char 13)
                                  (code-char 1))
                            'string))))
      (expect escaped :to-equal
              (concatenate 'string
                           "&lt;"
                           "&gt;"
                           "&amp;"
                           "&quot;"
                           "&apos;"
                           (string (code-char 9))
                           (string (code-char 10))
                           (string (code-char 13))
                           "?"))))

  (it "prints CI-readable TAP results"
    (let ((output (with-output-to-string (stream)
                    (cl-weave::report-tap
                     (list (cl-weave::make-test-event
                            :status :pass
                            :path '("reporters" "passes")
                            :elapsed-internal-time 0)
                           (cl-weave::make-test-event
                            :status :skip
                            :path '("reporters" "skips")
                            :reason "needs terminal"
                            :elapsed-internal-time 0)
                           (cl-weave::make-test-event
                            :status :todo
                            :path '("reporters" "todos")
                            :reason "pending"
                            :elapsed-internal-time 0)
                           (cl-weave::make-test-event
                            :status :fail
                            :path '("reporters" "fails")
                            :condition "bad value"
                            :assertion (cl-weave::make-assertion-detail
                                        :form '(expect 1 :to-be 2)
                                        :matcher :to-be
                                        :actual 1
                                        :expected 2
                                        :negated nil
                                        :pass nil)
                            :elapsed-internal-time 0)
                           (cl-weave::make-test-event
                            :status :error
                            :path '("reporters" "errors")
                            :condition "boom"
                            :elapsed-internal-time 0))
                     stream))))
      (expect output :to-contain "TAP version 13")
      (expect output :to-contain "1..5")
      (expect output :to-contain "ok 1 - reporters > passes")
      (expect output :to-contain "ok 2 - reporters > skips # SKIP needs terminal")
      (expect output :to-contain "ok 3 - reporters > todos # TODO pending")
      (expect output :to-contain "not ok 4 - reporters > fails")
      (expect output :to-contain "not ok 5 - reporters > errors")
      (expect output :to-contain "status: \"fail\"")
      (expect output :to-contain "condition: \"bad value\"")
      (expect output :to-contain "matcher: \":TO-BE\"")))

  (it "preserves unicode while normalizing TAP line breaks"
    (let ((output (with-output-to-string (stream)
                    (cl-weave::report-tap
                     (list (cl-weave::make-test-event
                            :status :skip
                            :path '("parser" "handles λ")
                            :reason (format nil "line1~%line2~C絵文字😀" #\Tab)
                            :elapsed-internal-time 0)
                           (cl-weave::make-test-event
                            :status :fail
                            :path '("parser" "keeps 雪")
                            :condition (format nil "壊れた~%入力")
                            :elapsed-internal-time 0))
                     stream))))
      (expect output :to-contain "ok 1 - parser > handles λ # SKIP line1 line2 絵文字😀")
      (expect output :to-contain "not ok 2 - parser > keeps 雪")
      (expect output :to-contain "condition: \"壊れた 入力\"")))

  (it "prints GitHub Actions annotations for failures and errors"
    (let ((output (with-output-to-string (stream)
                    (cl-weave::report-github
                     (list (cl-weave::make-test-event
                            :status :pass
                            :path '("reporters" "passes")
                            :elapsed-internal-time 0)
                           (cl-weave::make-test-event
                            :status :skip
                            :path '("reporters" "skips")
                            :reason "needs terminal"
                            :elapsed-internal-time 0)
                           (cl-weave::make-test-event
                            :status :fail
                            :path '("reporters" "fails")
                            :location '(:file "tests/reporters,case:lisp")
                            :condition (format nil "bad%~%value, x:y")
                            :assertion (cl-weave::make-assertion-detail
                                        :form '(expect 1 :to-be 2)
                                        :matcher :to-be
                                        :actual 1
                                        :expected 2
                                        :negated nil
                                        :pass nil)
                            :elapsed-internal-time 0)
                           (cl-weave::make-test-event
                            :status :error
                            :path '("reporters" "errors")
                            :condition "boom"
                            :elapsed-internal-time 0))
                     stream))))
      (expect output :to-contain "::error file=tests/reporters%2Ccase%3Alisp::")
      (expect output :to-contain "reporters > fails [fail]%0Abad%25%0Avalue, x:y")
      (expect output :to-contain "matcher: :TO-BE")
      (expect output :to-contain "::error::reporters > errors [error]%0Aboom")
      (expect output :not :to-contain "reporters > passes [pass]")
      (expect output :not :to-contain "reporters > skips [skip]")
      (expect output :to-contain "cl-weave: 1 passed, 1 skipped, 0 todo, 1 failed, 1 errored, 4 total")))

  (it "preserves unicode while percent-encoding GitHub annotation control characters"
    (let ((output (with-output-to-string (stream)
                    (cl-weave::report-github
                     (list (cl-weave::make-test-event
                            :status :fail
                            :path '("parser" "handles λ")
                            :location '(:file "tests/雪,λ.lisp")
                            :condition (format nil "bad%~%絵文字😀")
                            :elapsed-internal-time 0))
                     stream))))
      (expect output :to-contain "::error file=tests/雪%2Cλ.lisp::")
      (expect output :to-contain "parser > handles λ [fail]%0Abad%25%0A絵文字😀")
      (expect output :to-contain "cl-weave: 0 passed, 0 skipped, 0 todo, 1 failed, 0 errored, 1 total"))))
