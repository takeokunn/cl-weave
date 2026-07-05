(in-package #:cl-weave/tests)

(describe "isolation"
  (it "expands it-isolated into the isolated runner"
    (expect (macroexpand-1
             '(it-isolated "child process"
                  (:systems ("cl-weave-tests") :timeout 5)
                (expect 1 :to-be 1)))
            :to-satisfy
            (lambda (form)
              (and (tree-contains-p form 'cl-weave::run-isolated)
                   (tree-contains-p form 'cl-weave::assert-isolated-success)))))

  (it-isolated "runs assertions in a child SBCL process"
      (:systems ("cl-weave-tests") :timeout 180)
    (expect (+ 2 3) :to-be 5))

  (it "reports child process failures without failing the parent process"
    (let ((result (run-isolated
                   '(error "child boom")
                   :systems '("cl-weave-tests")
                   :package "CL-WEAVE/TESTS"
                   :timeout 180)))
      (expect (isolated-result-status result) :to-be :fail)
      (expect (isolated-result-exit-code result) :to-be 1)
      (expect (isolated-result-stderr result) :to-contain "child boom")))

  (it "terminates isolated tests on timeout"
    (let ((result (run-isolated
                   '(sleep 2)
                   :systems '("cl-weave-tests")
                   :package "CL-WEAVE/TESTS"
                   :timeout 0.1)))
      (expect (isolated-result-status result) :to-be :timeout)
      (expect (isolated-result-timed-out-p result) :to-be-truthy))))

