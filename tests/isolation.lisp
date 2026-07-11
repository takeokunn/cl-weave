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
      (expect (cl-weave:isolated-result-elapsed-ms result) :to-be-greater-than-or-equal 0)
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

  (it "retries temp directory allocation after a collision"
    (let* ((temporary-directory (uiop:temporary-directory))
           (collision-name "cl-weave-isolated-home-collision")
           (fresh-name "cl-weave-isolated-home-fresh")
           (collision-path (merge-pathnames
                            (make-pathname :directory (list :relative collision-name))
                            temporary-directory))
           (fresh-path (merge-pathnames
                        (make-pathname :directory (list :relative fresh-name))
                        temporary-directory))
           (names (list collision-name fresh-name)))
      (ensure-directories-exist collision-path)
      (when (probe-file fresh-path)
        (uiop:delete-directory-tree fresh-path
                                    :validate t
                                    :if-does-not-exist :ignore))
      (unwind-protect
           (with-mocked-functions
               (((symbol-function 'cl-weave::isolated-temp-name)
                 (lambda (prefix)
                   (declare (ignore prefix))
                   (pop names))))
             (let ((allocated (cl-weave::isolated-temp-directory "ignored")))
               (expect (namestring allocated) :to-be (namestring fresh-path))
               (expect (probe-file allocated) :to-be-truthy)))
        (uiop:delete-directory-tree collision-path
                                    :validate t
                                    :if-does-not-exist :ignore)
        (uiop:delete-directory-tree fresh-path
                                    :validate t
                                    :if-does-not-exist :ignore))))

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
                                        :if-does-not-exist :ignore))))))

  (it "keeps isolated artifacts only on failure when requested"
    (let ((pass-result (run-isolated
                        '(expect 1 :to-be 1)
                        :systems '("cl-weave-tests")
                        :package "CL-WEAVE/TESTS"
                        :timeout 180
                        :keep-files :on-failure))
          (fail-result (run-isolated
                        '(error "keep failure artifacts")
                        :systems '("cl-weave-tests")
                        :package "CL-WEAVE/TESTS"
                        :timeout 180
                        :keep-files :on-failure)))
      (unwind-protect
           (progn
             (expect (isolated-result-status pass-result) :to-be :pass)
             (expect (isolated-result-script-path pass-result) :to-be nil)
             (expect (isolated-result-status fail-result) :to-be :fail)
             (expect (probe-file (isolated-result-script-path fail-result)) :to-be-truthy)
             (expect (probe-file (isolated-result-stdout-path fail-result)) :to-be-truthy)
             (expect (probe-file (isolated-result-stderr-path fail-result)) :to-be-truthy)
             (expect (probe-file (isolated-result-home-path fail-result)) :to-be-truthy))
        (when (isolated-result-script-path fail-result)
          (ignore-errors (delete-file (isolated-result-script-path fail-result))))
        (when (isolated-result-stdout-path fail-result)
          (ignore-errors (delete-file (isolated-result-stdout-path fail-result))))
        (when (isolated-result-stderr-path fail-result)
          (ignore-errors (delete-file (isolated-result-stderr-path fail-result))))
        (when (isolated-result-home-path fail-result)
          (ignore-errors
            (uiop:delete-directory-tree (isolated-result-home-path fail-result)
                                        :validate t
                                        :if-does-not-exist :ignore))))))

  (it "passes keep-files through it-isolated"
    (expect (macroexpand-1
             '(it-isolated "child process"
                  (:systems ("cl-weave-tests") :timeout 5 :keep-files :on-failure)
                (expect 1 :to-be 1)))
            :to-satisfy
            (lambda (form)
              (and (tree-contains-p form :keep-files)
                   (tree-contains-p form :on-failure))))))
