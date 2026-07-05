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
      (expect (isolated-result-stderr result) :to-contain "child boom")
      (expect (isolated-result-script-path result) :to-be nil)
      (expect (isolated-result-stdout-path result) :to-be nil)
      (expect (isolated-result-stderr-path result) :to-be nil)
      (expect (isolated-result-home-path result) :to-be nil)))

  (it "terminates isolated tests on timeout"
    (let ((result (run-isolated
                   '(sleep 2)
                   :systems '("cl-weave-tests")
                   :package "CL-WEAVE/TESTS"
                   :timeout 0.1)))
      (expect (isolated-result-status result) :to-be :timeout)
      (expect (isolated-result-timed-out-p result) :to-be-truthy)))

  (it "keeps isolated artifacts only when keep-files is enabled"
    (let ((result (run-isolated
                   '(progn
                      (format t "ok")
                      (format *error-output* "warn"))
                   :systems '("cl-weave-tests")
                   :package "CL-WEAVE/TESTS"
                   :timeout 180
                   :keep-files t)))
      (unwind-protect
           (progn
             (expect (isolated-result-status result) :to-be :pass)
             (expect (probe-file (isolated-result-script-path result)) :to-be-truthy)
             (expect (probe-file (isolated-result-stdout-path result)) :to-be-truthy)
             (expect (probe-file (isolated-result-stderr-path result)) :to-be-truthy)
             (expect (probe-file (isolated-result-home-path result)) :to-be-truthy))
        (when (isolated-result-script-path result)
          (ignore-errors (delete-file (isolated-result-script-path result))))
        (when (isolated-result-stdout-path result)
          (ignore-errors (delete-file (isolated-result-stdout-path result))))
        (when (isolated-result-stderr-path result)
          (ignore-errors (delete-file (isolated-result-stderr-path result))))
        (when (isolated-result-home-path result)
          (ignore-errors
            (uiop:delete-directory-tree (isolated-result-home-path result)
                                        :validate t
                                        :if-does-not-exist :ignore)))))))
