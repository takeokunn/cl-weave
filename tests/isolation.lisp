(in-package #:cl-weave/tests)

(it "captures uncapped stdout and stderr bursts without loss"
      (let* ((burst-size (* 256 1024))
             (result
               (run-isolated
                '(progn
                   (dotimes (index (* 256 1024))
                     (declare (ignore index))
                     (write-char #\x))
                   (dotimes (index (* 256 1024))
                     (declare (ignore index))
                     (write-char #\y *error-output*)))
                :systems '("cl-weave/tests")
                :package "CL-WEAVE/TESTS"
                :timeout 180
                :max-output-bytes (* 1024 1024))))
        (expect (isolated-result-status result) :to-be :pass)
        (expect (cl-weave:isolated-result-stdout result)
                :to-equal
                (make-string burst-size :initial-element #\x))
        (expect (isolated-result-stderr result)
                :to-equal
                (make-string burst-size :initial-element #\y))
        (expect (cl-weave::isolated-result-output-limit-exceeded-p result)
                :to-be nil)))
(progn
(describe "isolation cleanup completion"
  (it "cleans descendants while the trusted supervisor remains alive"
    (let* ((pid-path
             (merge-pathnames
              (make-pathname
               :name (cl-weave::isolated-temp-name "cl-weave-live-supervisor")
               :type "pid")
              (uiop:temporary-directory)))
           result)
      (unwind-protect
           (progn
             (setf result
                   (run-isolated
                    `(let ((cl-user::child
                             (sb-ext:run-program
                              "/bin/sleep"
                              (list "30")
                              :wait nil
                              :input t)))
                       (with-open-file (cl-user::stream
                                        ,(namestring pid-path)
                                        :direction :output
                                        :if-exists :supersede
                                        :if-does-not-exist :create)
                         (format cl-user::stream
                                 "~D"
                                 (sb-ext:process-pid cl-user::child))
                         (finish-output cl-user::stream)))
                    :systems nil
                    :package "CL-USER"
                    :timeout 10))
             (expect (isolated-result-status result) :to-be :pass)
             (expect-isolated-test-process-dead pid-path))
        (when (probe-file pid-path)
          (ignore-errors (delete-file pid-path))))))

  (it "kills a TERM-ignoring worker before returning after supervisor SIGKILL"
    (let* ((pid-path
             (merge-pathnames
              (make-pathname
               :name
               (cl-weave::isolated-temp-name
                 "cl-weave-killed-supervisor-worker")
               :type "pid")
              (uiop:temporary-directory)))
           (original-temp-directory
             (symbol-function
               (quote cl-weave::isolated-temp-directory)))
           home
           pid
           result)
      (unwind-protect
           (progn
             (setf
               (symbol-function
                 (quote cl-weave::isolated-temp-directory))
               (lambda (prefix)
                 (let ((directory
                         (funcall original-temp-directory prefix)))
                   (setf home directory)
                   directory)))
             (setf result
                   (run-isolated
                    `(progn
                       (require :sb-posix)
                       (funcall
                        (symbol-function
                         (find-symbol "ENABLE-INTERRUPT" "SB-SYS"))
                        (symbol-value
                         (find-symbol "SIGTERM" "SB-UNIX"))
                        (lambda (&rest cl-user::ignored)
                          (declare (ignore cl-user::ignored))))
                       (with-open-file
                           (cl-user::stream
                            ,(namestring pid-path)
                            :direction :output
                            :if-exists :supersede
                            :if-does-not-exist :create)
                         (format
                          cl-user::stream
                          "~D"
                          (funcall
                           (symbol-function
                            (find-symbol "GETPID" "SB-POSIX"))))
                         (finish-output cl-user::stream))
                       (funcall
                        (symbol-function (find-symbol "KILL" "SB-POSIX"))
                        (funcall
                         (symbol-function
                          (find-symbol "GETPPID" "SB-POSIX")))
                        9)
                       (loop (sleep 3600)))
                    :systems nil
                    :package "CL-USER"
                    :timeout 10))
             (setf
               pid
               (parse-integer
                 (uiop:read-file-string pid-path)))
             (expect (isolated-result-status result) :to-be :fail)
             (expect
               (search
                 "isolated cleanup incomplete"
                 (isolated-result-stderr result))
               :to-be nil)
             (expect (isolated-result-home-path result) :to-be nil)
             (expect home :to-be-truthy)
             (expect (probe-file home) :to-be nil)
             (expect (isolated-test-process-alive-p pid) :to-be nil))
        (setf
          (symbol-function
            (quote cl-weave::isolated-temp-directory))
          original-temp-directory)
        (when
            (and
             (null pid)
             (probe-file pid-path))
          (setf
            pid
            (ignore-errors
              (parse-integer
                (uiop:read-file-string pid-path)))))
        (when
            (and
             pid
             (isolated-test-process-alive-p pid))
          (require :sb-posix)
          (ignore-errors
            (funcall
             (symbol-function (find-symbol "KILL" "SB-POSIX"))
             pid
             9))
          (loop
            repeat 200
            while (isolated-test-process-alive-p pid)
            do (sleep 0.01)))
        (when (probe-file pid-path)
          (ignore-errors (delete-file pid-path)))
        (when (and home (probe-file home))
          (ignore-errors
            (uiop:delete-directory-tree
             home
             :validate t
             :if-does-not-exist :ignore))))))

  (progn
  (it "retries pending cleanup until the process is reaped"
    (let ((original
            (symbol-function
             (quote cl-weave::terminate-isolated-process)))
          (deadline
            (cl-weave::isolated-deadline
             (get-internal-real-time)
             1))
          (attempts 0))
      (unwind-protect
           (progn
             (setf
              (symbol-function
               (quote cl-weave::terminate-isolated-process))
              (lambda
                  (process process-group-authority parent-session-id
                   actual-deadline)
                (declare
                 (ignore
                  process process-group-authority parent-session-id))
                (expect actual-deadline :to-be deadline)
                (if (= (incf attempts) 2)
                    :reaped
                    :pending)))
             (expect
              (cl-weave::retry-isolated-process-cleanup
               nil nil 0 deadline)
              :to-be
              :reaped)
             (expect attempts :to-be 2))
        (setf
         (symbol-function
          (quote cl-weave::terminate-isolated-process))
         original))))

  (it "uses bounded final draining after pending cleanup is reaped"
    (let ((original-wait
            (symbol-function
             (quote cl-weave::wait-isolated-process))))
      (unwind-protect
           (progn
             (setf
              (symbol-function
               (quote cl-weave::wait-isolated-process))
              (lambda
                  (process deadline ready anchor-control-fd
                   completion-control-fd anchor-lifetime-fd
                   parent-session-id stdout-stream stderr-stream
                   stdout-output stderr-output
                   process-group-authority-cell)
                (declare
                 (ignore
                  process deadline ready anchor-control-fd
                  completion-control-fd anchor-lifetime-fd
                  parent-session-id stdout-stream stderr-stream
                  stdout-output stderr-output
                  process-group-authority-cell))
                (values :cleanup-pending nil nil nil)))
             (let ((result
                     (run-isolated
                      (quote (sleep 30))
                      :systems nil
                      :package "CL-USER"
                      :timeout 10)))
               (expect (isolated-result-status result) :to-be :fail)
               (expect (isolated-result-home-path result) :to-be nil)))
        (setf
         (symbol-function
          (quote cl-weave::wait-isolated-process))
         original-wait)))))

  (progn
  (it "transitions cleanup owners through backoff and quarantine"
    (let ((cl-weave::*isolated-cleanup-registry* nil)
          (cl-weave::*isolated-cleanup-next-id* 0)
          (cl-weave::*isolated-cleanup-last-warning-at* nil)
          (cl-weave::*isolated-cleanup-worker* nil)
          (cl-weave::*isolated-cleanup-registry-mutex*
            (sb-thread:make-mutex :name "cleanup transition test"))
          (cl-weave::*isolated-cleanup-registry-condition*
            (sb-thread:make-waitqueue :name "cleanup transition test"))
          (now 0)
          (released-local-owner-p nil)
          (owner
            (cl-weave::make-isolated-cleanup-owner
             :process :process
             :parent-session-id 10
             :state :held)))
      (labels ((claim-owner ()
                 (let ((published-owner nil))
                   (expect
                    (cl-weave::claim-isolated-cleanup
                     (lambda (claimed-owner)
                       (setf published-owner claimed-owner)))
                    :to-be
                    owner)
                   (expect published-owner :to-be owner))))
        (with-mocked-functions
            (((symbol-function 'cl-weave::isolated-cleanup-now)
              (lambda () now))
             ((symbol-function 'cl-weave::ensure-isolated-cleanup-worker)
              (lambda () nil))
             ((symbol-function 'cl-weave::close-isolated-fd)
              (lambda (fd) (declare (ignore fd))))
             ((symbol-function 'cl-weave::delete-isolated-cleanup-home)
              (lambda (home) (declare (ignore home)))))
          (cl-weave::isolated-cleanup-register owner)
          (expect
           (cl-weave::handoff-isolated-cleanup-owner
            owner nil t
            (lambda () (setf released-local-owner-p t)))
           :to-be-truthy)
          (expect released-local-owner-p :to-be-truthy)
          (expect (cl-weave::isolated-cleanup-owner-state owner)
                  :to-be
                  :ready)
          (claim-owner)
          (expect (cl-weave::defer-isolated-cleanup-owner owner "first")
                  :to-be
                  :backoff)
          (expect (cl-weave::isolated-cleanup-owner-attempts owner) :to-be 1)
          (expect (cl-weave::isolated-cleanup-owner-next-at owner) :to-be 1/10)
          (expect (cl-weave::isolated-cleanup-owner-last-error owner)
                  :to-equal
                  "first")
          (setf now 1/10)
          (claim-owner)
          (expect (cl-weave::defer-isolated-cleanup-owner owner "second")
                  :to-be
                  :backoff)
          (expect (cl-weave::isolated-cleanup-owner-attempts owner) :to-be 2)
          (expect (cl-weave::isolated-cleanup-owner-next-at owner) :to-be 3/10)
          (setf now 3/10)
          (claim-owner)
          (expect (cl-weave::defer-isolated-cleanup-owner owner "third")
                  :to-be
                  :quarantined)
          (expect (cl-weave::isolated-cleanup-owner-attempts owner) :to-be 3)
          (expect (cl-weave::isolated-cleanup-owner-next-at owner) :to-be 7/10)
          (setf now 7/10)
          (claim-owner)
          (expect (cl-weave::release-isolated-cleanup-owner owner)
                  :to-be
                  :released)
          (expect (cl-weave::isolated-cleanup-owner-state owner)
                  :to-be
                  :released)
          (expect cl-weave::*isolated-cleanup-registry* :to-be nil)))))

  (it "rotates seventeen ready cleanup owners in bounded fair batches"
    (let* ((owners
             (loop for id from 1 to 17
                   collect
                   (cl-weave::make-isolated-cleanup-owner
                    :id id
                    :process :process
                    :state :ready
                    :next-at 0)))
           (cl-weave::*isolated-cleanup-registry* (copy-list owners))
           (cl-weave::*isolated-cleanup-registry-mutex*
             (sb-thread:make-mutex :name "cleanup fairness test"))
           (cl-weave::*isolated-cleanup-registry-condition*
             (sb-thread:make-waitqueue :name "cleanup fairness test"))
           (seen nil))
      (with-mocked-functions
          (((symbol-function 'cl-weave::isolated-cleanup-now)
            (lambda () 0))
           ((symbol-function 'cl-weave::process-isolated-cleanup-owner)
            (lambda (owner)
              (push (cl-weave::isolated-cleanup-owner-id owner) seen)
              (setf (cl-weave::isolated-cleanup-owner-state owner) :ready))))
        (expect (cl-weave::pump-isolated-cleanups) :to-be 8)
        (expect (nreverse seen) :to-equal '(1 2 3 4 5 6 7 8))
        (setf seen nil)
        (expect (cl-weave::pump-isolated-cleanups) :to-be 8)
        (expect (nreverse seen) :to-equal '(9 10 11 12 13 14 15 16))
        (setf seen nil)
        (expect (cl-weave::pump-isolated-cleanups) :to-be 8)
        (expect (nreverse seen) :to-equal '(17 1 2 3 4 5 6 7)))))

  (it "keeps registered cleanup owners strongly reachable across full GC"
    (let ((cl-weave::*isolated-cleanup-registry* nil)
          (cl-weave::*isolated-cleanup-next-id* 0)
          (cl-weave::*isolated-cleanup-last-warning-at* nil)
          (cl-weave::*isolated-cleanup-registry-mutex*
            (sb-thread:make-mutex :name "cleanup strong registry test"))
          (cl-weave::*isolated-cleanup-registry-condition*
            (sb-thread:make-waitqueue :name "cleanup strong registry test"))
          (weak-owner nil))
      (let ((owner
              (cl-weave::make-isolated-cleanup-owner
               :process :process
               :home #p"/tmp/cl-weave-strong-owner/"
               :state :held)))
        (cl-weave::isolated-cleanup-register owner)
        (setf weak-owner (sb-ext:make-weak-pointer owner)))
      (sb-ext:gc :full t)
      (expect (sb-ext:weak-pointer-value weak-owner) :to-be-truthy)
      (expect (length cl-weave::*isolated-cleanup-registry*) :to-be 1)
      (expect (length (cl-weave::isolated-cleanup-snapshots)) :to-be 1)))

  (it "rate limits high-water warnings without rejecting owners"
    (let ((cl-weave::*isolated-cleanup-registry* nil)
          (cl-weave::*isolated-cleanup-next-id* 0)
          (cl-weave::*isolated-cleanup-last-warning-at* nil)
          (cl-weave::*isolated-cleanup-registry-mutex*
            (sb-thread:make-mutex :name "cleanup warning test"))
          (cl-weave::*isolated-cleanup-registry-condition*
            (sb-thread:make-waitqueue :name "cleanup warning test"))
          (now 0)
          (warning-count 0))
      (with-mocked-functions
          (((symbol-function 'cl-weave::isolated-cleanup-now)
            (lambda () now)))
        (handler-bind
            ((warning
               (lambda (condition)
                 (incf warning-count)
                 (muffle-warning condition))))
          (loop repeat 65
                do
                   (cl-weave::isolated-cleanup-register
                    (cl-weave::make-isolated-cleanup-owner
                     :process :process)))
          (setf now 59)
          (cl-weave::isolated-cleanup-register
           (cl-weave::make-isolated-cleanup-owner :process :process))
          (setf now 60)
          (cl-weave::isolated-cleanup-register
           (cl-weave::make-isolated-cleanup-owner :process :process)))
        (expect warning-count :to-be 2)
        (expect (length cl-weave::*isolated-cleanup-registry*) :to-be 67)
        (expect
         (mapcar #'cl-weave::isolated-cleanup-owner-id
                 cl-weave::*isolated-cleanup-registry*)
         :to-equal
         (loop for id from 1 to 67 collect id)))))

  (it "closes distinct and aliased owner descriptors at most once across nonlocal exit"
    (dolist (case '((11 12 (11 12)) (11 11 (11))))
      (destructuring-bind
          (completion-control-fd anchor-lifetime-fd expected)
          case
        (let* ((owner
                 (cl-weave::make-isolated-cleanup-owner
                  :completion-control-fd completion-control-fd
                  :anchor-lifetime-fd anchor-lifetime-fd
                  :state :running))
               (cl-weave::*isolated-cleanup-registry* (list owner))
               (cl-weave::*isolated-cleanup-registry-mutex*
                 (sb-thread:make-mutex :name "cleanup close test"))
               (cl-weave::*isolated-cleanup-registry-condition*
                 (sb-thread:make-waitqueue :name "cleanup close test"))
               (close-calls nil)
               (first-close-p t))
          (with-mocked-functions
              (((symbol-function 'cl-weave::close-isolated-fd)
                (lambda (fd)
                  (when fd
                    (push fd close-calls)
                    (when first-close-p
                      (setf first-close-p nil)
                      (throw 'cleanup-close-boundary :interrupted)))))
               ((symbol-function 'cl-weave::delete-isolated-cleanup-home)
                (lambda (home) (declare (ignore home)))))
            (expect
             (catch 'cleanup-close-boundary
               (cl-weave::release-isolated-cleanup-owner owner))
             :to-be
             :interrupted)
            (expect (nreverse close-calls) :to-equal expected)
            (setf close-calls nil)
            (catch 'cleanup-close-boundary
              (cl-weave::release-isolated-cleanup-owner owner))
            (expect close-calls :to-be nil))))))

  (it "observes scope-lost authority without signaling its process group"
    (let* ((authority
             (cl-weave::make-isolated-process-group-authority
              :process 100 101 42 100))
           (owner
             (cl-weave::make-isolated-cleanup-owner
              :process :process
              :authority authority
              :parent-session-id 99
              :anchor-lifetime-fd 42
              :state :running))
           (cl-weave::*isolated-cleanup-registry* (list owner))
           (cl-weave::*isolated-cleanup-registry-mutex*
             (sb-thread:make-mutex :name "cleanup scope-lost test"))
           (cl-weave::*isolated-cleanup-registry-condition*
             (sb-thread:make-waitqueue :name "cleanup scope-lost test"))
           (wait-statuses '(:pending :exited))
           (wait-count 0)
           (reap-count 0)
           (terminate-count 0))
      (setf (cl-weave::isolated-process-group-authority-state authority)
            :scope-lost)
      (with-mocked-functions
          (((symbol-function
             'cl-weave::wait-for-isolated-anchor-lifetime-exit)
            (lambda (fd deadline)
              (declare (ignore fd deadline))
              (incf wait-count)
              (pop wait-statuses)))
           ((symbol-function 'cl-weave::reap-isolated-process)
            (lambda (process deadline)
              (declare (ignore process deadline))
              (incf reap-count)
              :reaped))
           ((symbol-function 'cl-weave::terminate-isolated-process)
            (lambda (&rest arguments)
              (declare (ignore arguments))
              (incf terminate-count)
              :reaped))
           ((symbol-function 'cl-weave::close-isolated-fd)
            (lambda (fd) (declare (ignore fd))))
           ((symbol-function 'cl-weave::delete-isolated-cleanup-home)
            (lambda (home) (declare (ignore home)))))
        (cl-weave::process-isolated-cleanup-owner owner)
        (expect (cl-weave::isolated-cleanup-owner-state owner)
                :to-be
                :backoff)
        (setf (cl-weave::isolated-cleanup-owner-state owner) :running)
        (cl-weave::process-isolated-cleanup-owner owner)
        (expect wait-count :to-be 2)
        (expect reap-count :to-be 1)
        (expect terminate-count :to-be 0)
        (expect cl-weave::*isolated-cleanup-registry* :to-be nil))))

  (it "bounds explicit cleanup draining to eight cycles"
  (let ((pump-count 0))
    (with-mocked-functions
        (((symbol-function 'cl-weave::pump-isolated-cleanups)
          (lambda ()
            (incf pump-count)
            1)))
      (expect (cl-weave::drain-isolated-cleanups :cycles -1) :to-be 0)
      (expect pump-count :to-be 0)
      (expect (cl-weave::drain-isolated-cleanups :cycles 0) :to-be 0)
      (expect pump-count :to-be 0)
      (expect (cl-weave::drain-isolated-cleanups :cycles 1) :to-be 1)
      (expect pump-count :to-be 1)
      (expect (cl-weave::drain-isolated-cleanups :cycles 100) :to-be 8)
      (expect pump-count :to-be 9))))

  (it "keeps nil-policy artifact paths private until deferred deletion"
    (let* ((home
             (cl-weave::isolated-temp-directory "cl-weave-cleanup-private"))
           (script (merge-pathnames #p"script.lisp" home))
           (stdout (merge-pathnames #p"stdout.out" home))
           (stderr (merge-pathnames #p"stderr.err" home))
           (owner
             (cl-weave::make-isolated-cleanup-owner
              :id 1
              :process :process
              :parent-session-id 10
              :home home
              :delete-home-p t
              :state :ready
              :next-at 0))
           (cl-weave::*isolated-cleanup-registry* (list owner))
           (cl-weave::*isolated-cleanup-registry-mutex*
             (sb-thread:make-mutex :name "cleanup private path test"))
           (cl-weave::*isolated-cleanup-registry-condition*
             (sb-thread:make-waitqueue :name "cleanup private path test"))
           (now 0)
           (terminate-count 0)
           (result
             (cl-weave::make-isolated-result
              :status :fail
              :script-path (cl-weave::maybe-path-namestring script nil)
              :stdout-path (cl-weave::maybe-path-namestring stdout nil)
              :stderr-path (cl-weave::maybe-path-namestring stderr nil)
              :home-path (cl-weave::maybe-path-namestring home nil))))
      (unwind-protect
          (with-mocked-functions
              (((symbol-function 'cl-weave::isolated-cleanup-now)
                (lambda () now))
               ((symbol-function 'cl-weave::terminate-isolated-process)
                (lambda (&rest arguments)
                  (declare (ignore arguments))
                  (if (= (incf terminate-count) 1)
                      :pending
                      :reaped)))
               ((symbol-function
                 'cl-weave::wait-for-isolated-anchor-lifetime-exit)
                (lambda (fd deadline)
                  (declare (ignore fd deadline))
                  :exited))
               ((symbol-function 'cl-weave::close-isolated-fd)
                (lambda (fd) (declare (ignore fd)))))
            (expect (isolated-result-home-path result) :to-be nil)
            (expect (isolated-result-script-path result) :to-be nil)
            (expect (isolated-result-stdout-path result) :to-be nil)
            (expect (isolated-result-stderr-path result) :to-be nil)
            (expect (cl-weave::isolated-cleanup-owner-home owner) :to-be home)
            (expect (probe-file home) :to-be-truthy)
            (expect (cl-weave::pump-isolated-cleanups) :to-be 1)
            (expect (cl-weave::isolated-cleanup-owner-state owner)
                    :to-be
                    :backoff)
            (expect (probe-file home) :to-be-truthy)
            (setf now 1)
            (expect (cl-weave::pump-isolated-cleanups) :to-be 1)
            (expect cl-weave::*isolated-cleanup-registry* :to-be nil)
            (expect (probe-file home) :to-be nil))
        (when (probe-file home)
          (uiop:delete-directory-tree
           home :validate t :if-does-not-exist :ignore)))))

  (it "returns primitive-only immutable cleanup snapshots"
    (let* ((owner
             (cl-weave::make-isolated-cleanup-owner
              :id 9
              :process (list :opaque-process)
              :authority (list :opaque-authority)
              :home #p"/tmp/private-cleanup-home/"
              :state :ready
              :attempts 2
              :last-error "boom"))
           (cl-weave::*isolated-cleanup-registry* (list owner))
           (cl-weave::*isolated-cleanup-registry-mutex*
             (sb-thread:make-mutex :name "cleanup snapshot test"))
           (snapshot (first (cl-weave::isolated-cleanup-snapshots))))
      (expect
       (loop for tail on snapshot by #'cddr collect (first tail))
       :to-equal
       '(:id :state :attempts :cleanup-pending-p :artifact-pending-p
         :last-error))
      (expect
       (loop for (key value) on snapshot by #'cddr
             always
             (and (keywordp key)
                  (or (null value)
                      (numberp value)
                      (stringp value)
                      (keywordp value)
                      (eq value t))))
       :to-be-truthy)
      (setf (getf snapshot :state) :mutated
            (char (getf snapshot :last-error) 0) #\X)
      (expect
       (first (cl-weave::isolated-cleanup-snapshots))
       :to-equal
       '(:id 9 :state :ready :attempts 2 :cleanup-pending-p t
         :artifact-pending-p t :last-error "boom"))))

  (it "returns every claimed owner to a claimable state after pump unwind"
    (let* ((owners
             (loop for id from 1 to 3
                   collect
                   (cl-weave::make-isolated-cleanup-owner
                    :id id
                    :process :process
                    :state :ready
                    :next-at 0)))
           (cl-weave::*isolated-cleanup-registry* (copy-list owners))
           (cl-weave::*isolated-cleanup-registry-mutex*
             (sb-thread:make-mutex :name "cleanup unwind test"))
           (cl-weave::*isolated-cleanup-registry-condition*
             (sb-thread:make-waitqueue :name "cleanup unwind test"))
           (now 0)
           (interrupt-p t)
           (processed nil)
           (max-running 0))
      (with-mocked-functions
          (((symbol-function 'cl-weave::isolated-cleanup-now)
            (lambda () now))
           ((symbol-function 'cl-weave::process-isolated-cleanup-owner)
            (lambda (owner)
              (setf max-running
                    (max max-running
                         (count :running owners
                                :key
                                #'cl-weave::isolated-cleanup-owner-state)))
              (if interrupt-p
                  (throw 'cleanup-pump-boundary :interrupted)
                  (progn
                    (push (cl-weave::isolated-cleanup-owner-id owner)
                          processed)
                    (cl-weave::defer-isolated-cleanup-owner owner nil))))))
        (expect
         (catch 'cleanup-pump-boundary
           (cl-weave::pump-isolated-cleanups))
         :to-be
         :interrupted)
        (expect max-running :to-be 1)
        (expect
         (some (lambda (owner)
                 (eq (cl-weave::isolated-cleanup-owner-state owner) :running))
               owners)
         :to-be
         nil)
        (setf interrupt-p nil
              now 1)
        (expect (cl-weave::pump-isolated-cleanups) :to-be 3)
        (expect (sort processed #'<) :to-equal '(1 2 3))
        (expect
         (some (lambda (owner)
                 (eq (cl-weave::isolated-cleanup-owner-state owner) :running))
               owners)
         :to-be
         nil))))

  (it "starts one cleanup worker and recovers from thread creation failure"
      (let ((cl-weave::*isolated-cleanup-worker* nil)
            (cl-weave::*isolated-cleanup-registry* nil)
            (cl-weave::*isolated-cleanup-registry-mutex*
              (sb-thread:make-mutex :name "cleanup worker singleton test"))
            (cl-weave::*isolated-cleanup-registry-condition*
              (sb-thread:make-waitqueue :name "cleanup worker singleton test"))
            (entered (sb-thread:make-semaphore :count 0))
            (stop (sb-thread:make-semaphore :count 0))
            (make-count 0)
            (fallback-count 0)
            (fallback-interrupts-enabled-p nil)
            (entrypoint-observed-p nil)
            (initial-result :unset)
            (first-result nil)
            (second-result nil)
            (live-thread nil)
            (live-thread-alive-p nil)
            (mutex-held-p nil))
        (unwind-protect
            (progn
              (with-mocked-functions
                  (((symbol-function
                     'cl-weave::make-isolated-cleanup-worker-thread)
                    (lambda (entrypoint)
                      (if (= (incf make-count) 1)
                          (error "thread creation failed")
                          (setf live-thread
                                (sb-thread:make-thread entrypoint)))))
                   ((symbol-function 'cl-weave::isolated-cleanup-worker-loop)
                    (lambda ()
                      (sb-thread:signal-semaphore entered)
                      (sb-thread:wait-on-semaphore stop)))
                   ((symbol-function 'cl-weave::pump-isolated-cleanups)
                    (lambda ()
                      (setf fallback-interrupts-enabled-p
                            sb-sys:*interrupts-enabled*)
                      (incf fallback-count)
                      0)))
                (handler-bind
                    ((warning
                       (lambda (condition)
                         (muffle-warning condition))))
                  (setf initial-result
                        (sb-ext:with-timeout 5
                          (cl-weave::ensure-isolated-cleanup-worker))))
                (setf first-result
                      (sb-ext:with-timeout 5
                        (cl-weave::ensure-isolated-cleanup-worker))
                      second-result
                      (sb-ext:with-timeout 5
                        (cl-weave::ensure-isolated-cleanup-worker))
                      entrypoint-observed-p
                      (sb-ext:with-timeout 5
                        (sb-thread:wait-on-semaphore entered))
                      live-thread-alive-p
                      (and live-thread
                           (sb-thread:thread-alive-p live-thread))
                      mutex-held-p
                      (sb-thread:holding-mutex-p
                       cl-weave::*isolated-cleanup-registry-mutex*)))
              (expect initial-result :to-be nil)
              (expect make-count :to-be 2)
              (expect fallback-count :to-be 1)
              (expect fallback-interrupts-enabled-p :to-be-truthy)
              (expect first-result :to-be live-thread)
              (expect second-result :to-be live-thread)
              (expect entrypoint-observed-p :to-be-truthy)
              (expect live-thread-alive-p :to-be-truthy)
              (expect mutex-held-p :to-be nil))
          (when live-thread
            (sb-thread:signal-semaphore stop)
            (handler-case
                (sb-ext:with-timeout 5
                  (sb-thread:join-thread live-thread))
              (sb-ext:timeout ()
                (ignore-errors (sb-thread:terminate-thread live-thread))
                (ignore-errors (sb-thread:join-thread live-thread))))))))

  (it "shares one cleanup worker across concurrent callers"
    (let* ((original-worker cl-weave::*isolated-cleanup-worker*)
           (original-registry cl-weave::*isolated-cleanup-registry*)
           (original-mutex cl-weave::*isolated-cleanup-registry-mutex*)
           (original-condition cl-weave::*isolated-cleanup-registry-condition*)
           (test-mutex
             (sb-thread:make-mutex :name "concurrent cleanup worker test"))
           (test-condition
             (sb-thread:make-waitqueue :name "concurrent cleanup worker test"))
           (caller-count 8)
           (ready (sb-thread:make-semaphore :count 0))
           (start (sb-thread:make-semaphore :count 0))
           (entered (sb-thread:make-semaphore :count 0))
           (stop (sb-thread:make-semaphore :count 0))
           (make-mutex (sb-thread:make-mutex :name "cleanup worker make count"))
           (make-count 0)
           (candidates nil)
           (callers nil)
           (results (make-array caller-count :initial-element nil))
           (errors (make-array caller-count :initial-element nil)))
      (unwind-protect
          (progn
            (setf cl-weave::*isolated-cleanup-worker* nil
                  cl-weave::*isolated-cleanup-registry* nil
                  cl-weave::*isolated-cleanup-registry-mutex* test-mutex
                  cl-weave::*isolated-cleanup-registry-condition* test-condition)
            (with-mocked-functions
                (((symbol-function
                   'cl-weave::make-isolated-cleanup-worker-thread)
                  (lambda (entrypoint)
                    (let ((thread (sb-thread:make-thread entrypoint)))
                      (sb-thread:with-mutex (make-mutex)
                        (incf make-count)
                        (push thread candidates))
                      thread)))
                 ((symbol-function 'cl-weave::isolated-cleanup-worker-loop)
                  (lambda ()
                    (sb-thread:signal-semaphore entered)
                    (sb-thread:wait-on-semaphore stop))))
              (setf callers
                    (loop for index below caller-count
                          collect
                          (let ((slot index))
                            (sb-thread:make-thread
                             (lambda ()
                               (sb-thread:signal-semaphore ready)
                               (sb-thread:wait-on-semaphore start)
                               (handler-case
                                   (setf (aref results slot)
                                         (cl-weave::ensure-isolated-cleanup-worker))
                                 (error (condition)
                                   (setf (aref errors slot) condition))))))))
              (dotimes (index caller-count)
                (declare (ignore index))
                (sb-ext:with-timeout 5
                  (sb-thread:wait-on-semaphore ready)))
              (dotimes (index caller-count)
                (declare (ignore index))
                (sb-thread:signal-semaphore start))
              (dolist (caller callers)
                (sb-ext:with-timeout 5
                  (sb-thread:join-thread caller)))
              (sb-ext:with-timeout 5
                (sb-thread:wait-on-semaphore entered))
              (let ((worker (aref results 0)))
                (expect make-count :to-be 1)
                (expect (every #'null (coerce errors 'list)) :to-be-truthy)
                (expect
                 (every (lambda (result) (eq result worker))
                        (coerce results 'list))
                 :to-be-truthy)
                (expect cl-weave::*isolated-cleanup-worker* :to-be worker)
                (expect (sb-thread:thread-alive-p worker) :to-be-truthy))))
        (dolist (candidate candidates)
          (sb-thread:signal-semaphore stop))
        (dolist (caller callers)
          (when (sb-thread:thread-alive-p caller)
            (ignore-errors (sb-thread:terminate-thread caller)))
          (ignore-errors (sb-thread:join-thread caller)))
        (dolist (candidate candidates)
          (handler-case
              (sb-ext:with-timeout 5
                (sb-thread:join-thread candidate))
            (sb-ext:timeout ()
              (ignore-errors (sb-thread:terminate-thread candidate))
              (ignore-errors (sb-thread:join-thread candidate)))))
        (setf cl-weave::*isolated-cleanup-worker* original-worker
              cl-weave::*isolated-cleanup-registry* original-registry
              cl-weave::*isolated-cleanup-registry-mutex* original-mutex
              cl-weave::*isolated-cleanup-registry-condition* original-condition))))

  (it "limits startup failure fallback to the failure-boundary owner snapshot"
      (let* ((boundary-owner
               (cl-weave::make-isolated-cleanup-owner :id 1 :state :ready))
             (late-owner
               (cl-weave::make-isolated-cleanup-owner :id 2 :state :ready))
             (initial-registry (list boundary-owner))
             (cl-weave::*isolated-cleanup-worker* nil)
             (cl-weave::*isolated-cleanup-registry* initial-registry)
             (cl-weave::*isolated-cleanup-registry-mutex*
               (sb-thread:make-mutex :name "cleanup fallback snapshot test"))
             (cl-weave::*isolated-cleanup-registry-condition*
               (sb-thread:make-waitqueue :name "cleanup fallback snapshot test"))
             (warning-count 0)
             (fallback-count 0)
             (observed-scope nil)
             (observed-registry nil)
             (mutex-held-during-fallback-p nil)
             (result :unset))
        (with-mocked-functions
            (((symbol-function
               'cl-weave::make-isolated-cleanup-worker-thread)
              (lambda (entrypoint)
                (declare (ignore entrypoint))
                (error "thread creation failed at snapshot boundary")))
             ((symbol-function 'cl-weave::pump-isolated-cleanups)
              (lambda ()
                (incf fallback-count)
                (setf observed-scope cl-weave::*isolated-cleanup-claim-scope*
                      observed-registry
                      (copy-list cl-weave::*isolated-cleanup-registry*)
                      mutex-held-during-fallback-p
                      (sb-thread:holding-mutex-p
                       cl-weave::*isolated-cleanup-registry-mutex*))
                0)))
          (handler-bind
              ((warning
                 (lambda (condition)
                   (when (search "Unable to start isolated cleanup worker"
                                 (princ-to-string condition))
                     (incf warning-count)
                     (setf cl-weave::*isolated-cleanup-registry*
                           (list late-owner)))
                   (muffle-warning condition))))
            (setf result
                  (sb-ext:with-timeout 5
                    (cl-weave::ensure-isolated-cleanup-worker)))))
        (expect result :to-be nil)
        (expect warning-count :to-be 1)
        (expect fallback-count :to-be 1)
        (expect observed-scope :not :to-be initial-registry)
        (expect (length observed-scope) :to-be 1)
        (expect (first observed-scope) :to-be boundary-owner)
        (expect (member late-owner observed-scope :test #'eq) :to-be nil)
        (expect (length observed-registry) :to-be 1)
        (expect (first observed-registry) :to-be late-owner)
        (expect mutex-held-during-fallback-p :to-be nil)
        (expect cl-weave::*isolated-cleanup-worker* :to-be nil)))

  (progn
  (it "rolls back cleanup worker publication after helper failure"
    (let ((cl-weave::*isolated-cleanup-worker* nil)
          (cl-weave::*isolated-cleanup-registry* nil)
          (cl-weave::*isolated-cleanup-registry-mutex*
            (sb-thread:make-mutex :name "cleanup worker precommit error test"))
          (cl-weave::*isolated-cleanup-registry-condition*
            (sb-thread:make-waitqueue :name "cleanup worker precommit error test"))
          (make-count 0)
          (worker-loop-count 0)
          (worker-loop-count-before-publication nil)
          (fallback-count 0)
          (candidate-thread nil)
          (candidate-ended-p nil)
          (candidate-alive-before-publication-p nil)
          (result :unset)
          (global-worker-after :unset)
          (mutex-held-p nil)
          (candidate-alive-after-p nil))
      (with-mocked-functions
          (((symbol-function
             'cl-weave::make-isolated-cleanup-worker-thread)
            (lambda (entrypoint)
              (incf make-count)
              (setf candidate-thread
                    (sb-thread:make-thread
                     (lambda ()
                       (unwind-protect
                           (funcall entrypoint)
                         (setf candidate-ended-p t)))))))
           ((symbol-function
             'cl-weave::publish-isolated-cleanup-worker-candidate)
            (lambda (candidate)
              (setf worker-loop-count-before-publication worker-loop-count
                    candidate-alive-before-publication-p
                    (sb-thread:thread-alive-p candidate))
              (error "publication failed")))
           ((symbol-function 'cl-weave::isolated-cleanup-worker-loop)
            (lambda ()
              (incf worker-loop-count)))
           ((symbol-function 'cl-weave::pump-isolated-cleanups)
            (lambda ()
              (incf fallback-count)
              0)))
        (handler-bind
            ((warning
               (lambda (condition)
                 (muffle-warning condition))))
          (setf result
                (sb-ext:with-timeout 5
                  (cl-weave::ensure-isolated-cleanup-worker))))
        (setf global-worker-after cl-weave::*isolated-cleanup-worker*
              mutex-held-p
              (sb-thread:holding-mutex-p
               cl-weave::*isolated-cleanup-registry-mutex*)
              candidate-alive-after-p
              (and candidate-thread
                   (sb-thread:thread-alive-p candidate-thread))))
      (expect result :to-be nil)
      (expect make-count :to-be 1)
      (expect worker-loop-count-before-publication :to-be 0)
      (expect candidate-alive-before-publication-p :to-be-truthy)
      (expect worker-loop-count :to-be 0)
      (expect fallback-count :to-be 1)
      (expect global-worker-after :to-be nil)
      (expect mutex-held-p :to-be nil)
      (expect candidate-ended-p :to-be-truthy)
      (expect candidate-alive-after-p :to-be nil)))

  (it "rolls back cleanup worker publication after helper nonlocal exit"
    (let ((cl-weave::*isolated-cleanup-worker* nil)
          (cl-weave::*isolated-cleanup-registry* nil)
          (cl-weave::*isolated-cleanup-registry-mutex*
            (sb-thread:make-mutex :name "cleanup worker precommit throw test"))
          (cl-weave::*isolated-cleanup-registry-condition*
            (sb-thread:make-waitqueue :name "cleanup worker precommit throw test"))
          (make-count 0)
          (worker-loop-count 0)
          (worker-loop-count-before-publication nil)
          (fallback-count 0)
          (candidate-thread nil)
          (candidate-ended-p nil)
          (candidate-alive-before-publication-p nil)
          (result :unset)
          (global-worker-after :unset)
          (mutex-held-p nil)
          (candidate-alive-after-p nil))
      (with-mocked-functions
          (((symbol-function
             'cl-weave::make-isolated-cleanup-worker-thread)
            (lambda (entrypoint)
              (incf make-count)
              (setf candidate-thread
                    (sb-thread:make-thread
                     (lambda ()
                       (unwind-protect
                           (funcall entrypoint)
                         (setf candidate-ended-p t)))))))
           ((symbol-function
             'cl-weave::publish-isolated-cleanup-worker-candidate)
            (lambda (candidate)
              (setf worker-loop-count-before-publication worker-loop-count
                    candidate-alive-before-publication-p
                    (sb-thread:thread-alive-p candidate))
              (throw 'cleanup-worker-publication-boundary :interrupted)))
           ((symbol-function 'cl-weave::isolated-cleanup-worker-loop)
            (lambda ()
              (incf worker-loop-count)))
           ((symbol-function 'cl-weave::pump-isolated-cleanups)
            (lambda ()
              (incf fallback-count)
              0)))
        (setf result
              (sb-ext:with-timeout 5
                (catch 'cleanup-worker-publication-boundary
                  (cl-weave::ensure-isolated-cleanup-worker))))
        (setf global-worker-after cl-weave::*isolated-cleanup-worker*
              mutex-held-p
              (sb-thread:holding-mutex-p
               cl-weave::*isolated-cleanup-registry-mutex*)
              candidate-alive-after-p
              (and candidate-thread
                   (sb-thread:thread-alive-p candidate-thread))))
      (expect result :to-be :interrupted)
      (expect make-count :to-be 1)
      (expect worker-loop-count-before-publication :to-be 0)
      (expect candidate-alive-before-publication-p :to-be-truthy)
      (expect worker-loop-count :to-be 0)
      (expect fallback-count :to-be 0)
      (expect global-worker-after :to-be nil)
      (expect mutex-held-p :to-be nil)
      (expect candidate-ended-p :to-be-truthy)
      (expect candidate-alive-after-p :to-be nil)))

  (it "retains the cleanup worker after publication broadcast failure"
    (let ((cl-weave::*isolated-cleanup-worker* nil)
          (cl-weave::*isolated-cleanup-registry* nil)
          (cl-weave::*isolated-cleanup-registry-mutex*
            (sb-thread:make-mutex :name "cleanup worker postcommit error test"))
          (cl-weave::*isolated-cleanup-registry-condition*
            (sb-thread:make-waitqueue :name "cleanup worker postcommit error test"))
          (entered (sb-thread:make-semaphore :count 0))
          (stop (sb-thread:make-semaphore :count 0))
          (make-count 0)
          (broadcast-count 0)
          (fallback-count 0)
          (notification-warning-count 0)
          (startup-warning-count 0)
          (entrypoint-observed-p nil)
          (candidate-thread nil)
          (first-result nil)
          (second-result nil)
          (global-worker-after nil)
          (candidate-alive-p nil)
          (mutex-held-p nil))
      (unwind-protect
          (progn
            (sb-ext:without-package-locks
(with-mocked-functions
                (((symbol-function
                   'cl-weave::make-isolated-cleanup-worker-thread)
                  (lambda (entrypoint)
                    (incf make-count)
                    (setf candidate-thread
                          (sb-thread:make-thread entrypoint))))
                 ((symbol-function 'cl-weave::isolated-cleanup-worker-loop)
                  (lambda ()
                    (sb-thread:signal-semaphore entered)
                    (sb-thread:wait-on-semaphore stop)))
                 ((symbol-function 'cl-weave::pump-isolated-cleanups)
                  (lambda ()
                    (incf fallback-count)
                    0))
                 ((symbol-function 'sb-thread:condition-broadcast)
                  (lambda (condition)
                    (declare (ignore condition))
                    (incf broadcast-count)
                    (error "publication broadcast failed"))))
              (handler-bind
                  ((warning
                     (lambda (condition)
                       (let ((message (princ-to-string condition)))
                         (when (search
                                "Unable to broadcast isolated cleanup worker publication"
                                message)
                           (incf notification-warning-count))
                         (when (search
                                "Unable to start isolated cleanup worker"
                                message)
                           (incf startup-warning-count)))
                       (muffle-warning condition))))
                (setf first-result
                      (sb-ext:with-timeout 5
                        (cl-weave::ensure-isolated-cleanup-worker))))
              (setf entrypoint-observed-p
                    (sb-ext:with-timeout 5
                      (sb-thread:wait-on-semaphore entered))
                    second-result
                    (sb-ext:with-timeout 5
                      (cl-weave::ensure-isolated-cleanup-worker))
                    global-worker-after cl-weave::*isolated-cleanup-worker*
                    candidate-alive-p
                    (and candidate-thread
                         (sb-thread:thread-alive-p candidate-thread))
                    mutex-held-p
                    (sb-thread:holding-mutex-p
                     cl-weave::*isolated-cleanup-registry-mutex*))))
            (expect make-count :to-be 1)
            (expect broadcast-count :to-be 1)
            (expect fallback-count :to-be 0)
            (expect notification-warning-count :to-be 1)
            (expect startup-warning-count :to-be 0)
            (expect first-result :to-be candidate-thread)
            (expect second-result :to-be candidate-thread)
            (expect global-worker-after :to-be candidate-thread)
            (expect entrypoint-observed-p :to-be-truthy)
            (expect candidate-alive-p :to-be-truthy)
            (expect mutex-held-p :to-be nil))
        (when candidate-thread
          (sb-thread:signal-semaphore stop)
          (handler-case
              (sb-ext:with-timeout 5
                (sb-thread:join-thread candidate-thread))
            (sb-ext:timeout ()
              (ignore-errors
                (sb-thread:terminate-thread candidate-thread))
              (ignore-errors
                (sb-thread:join-thread candidate-thread))))))))

  (it "retains the cleanup worker after publication broadcast nonlocal exit"
    (let ((cl-weave::*isolated-cleanup-worker* nil)
          (cl-weave::*isolated-cleanup-registry* nil)
          (cl-weave::*isolated-cleanup-registry-mutex*
            (sb-thread:make-mutex :name "cleanup worker postcommit throw test"))
          (cl-weave::*isolated-cleanup-registry-condition*
            (sb-thread:make-waitqueue :name "cleanup worker postcommit throw test"))
          (entered (sb-thread:make-semaphore :count 0))
          (stop (sb-thread:make-semaphore :count 0))
          (make-count 0)
          (broadcast-count 0)
          (fallback-count 0)
          (startup-warning-count 0)
          (entrypoint-observed-p nil)
          (candidate-thread nil)
          (first-result nil)
          (second-result nil)
          (global-worker-after nil)
          (candidate-alive-p nil)
          (mutex-held-p nil))
      (unwind-protect
          (progn
            (sb-ext:without-package-locks
(with-mocked-functions
                (((symbol-function
                   'cl-weave::make-isolated-cleanup-worker-thread)
                  (lambda (entrypoint)
                    (incf make-count)
                    (setf candidate-thread
                          (sb-thread:make-thread entrypoint))))
                 ((symbol-function 'cl-weave::isolated-cleanup-worker-loop)
                  (lambda ()
                    (sb-thread:signal-semaphore entered)
                    (sb-thread:wait-on-semaphore stop)))
                 ((symbol-function 'cl-weave::pump-isolated-cleanups)
                  (lambda ()
                    (incf fallback-count)
                    0))
                 ((symbol-function 'sb-thread:condition-broadcast)
                  (lambda (condition)
                    (declare (ignore condition))
                    (incf broadcast-count)
                    (throw 'cleanup-worker-broadcast-boundary :interrupted))))
              (handler-bind
                  ((warning
                     (lambda (condition)
                       (when (search
                              "Unable to start isolated cleanup worker"
                              (princ-to-string condition))
                         (incf startup-warning-count))
                       (muffle-warning condition))))
                (setf first-result
                      (sb-ext:with-timeout 5
                        (catch 'cleanup-worker-broadcast-boundary
                          (cl-weave::ensure-isolated-cleanup-worker)))))
              (setf entrypoint-observed-p
                    (sb-ext:with-timeout 5
                      (sb-thread:wait-on-semaphore entered))
                    second-result
                    (sb-ext:with-timeout 5
                      (cl-weave::ensure-isolated-cleanup-worker))
                    global-worker-after cl-weave::*isolated-cleanup-worker*
                    candidate-alive-p
                    (and candidate-thread
                         (sb-thread:thread-alive-p candidate-thread))
                    mutex-held-p
                    (sb-thread:holding-mutex-p
                     cl-weave::*isolated-cleanup-registry-mutex*))))
            (expect make-count :to-be 1)
            (expect broadcast-count :to-be 1)
            (expect fallback-count :to-be 0)
            (expect startup-warning-count :to-be 0)
            (expect first-result :to-be :interrupted)
            (expect second-result :to-be candidate-thread)
            (expect global-worker-after :to-be candidate-thread)
            (expect entrypoint-observed-p :to-be-truthy)
            (expect candidate-alive-p :to-be-truthy)
            (expect mutex-held-p :to-be nil))
        (when candidate-thread
          (sb-thread:signal-semaphore stop)
          (handler-case
              (sb-ext:with-timeout 5
                (sb-thread:join-thread candidate-thread))
            (sb-ext:timeout ()
              (ignore-errors
                (sb-thread:terminate-thread candidate-thread))
              (ignore-errors
                (sb-thread:join-thread candidate-thread)))))))))

  (it "replaces a dead cleanup worker pointer"
    (let* ((dead-thread (sb-thread:make-thread (lambda () nil)))
           (cl-weave::*isolated-cleanup-worker* dead-thread)
           (cl-weave::*isolated-cleanup-registry* nil)
           (cl-weave::*isolated-cleanup-registry-mutex*
             (sb-thread:make-mutex :name "cleanup dead worker test"))
           (cl-weave::*isolated-cleanup-registry-condition*
             (sb-thread:make-waitqueue :name "cleanup dead worker test"))
           (entered (sb-thread:make-semaphore :count 0))
           (stop (sb-thread:make-semaphore :count 0))
           (make-count 0)
           (entrypoint-observed-p nil)
           (live-thread nil)
           (worker-result nil)
           (global-worker-after nil)
           (live-thread-alive-p nil)
           (mutex-held-p nil))
      (sb-ext:with-timeout 5
        (sb-thread:join-thread dead-thread))
      (unwind-protect
          (progn
            (with-mocked-functions
                (((symbol-function
                   'cl-weave::make-isolated-cleanup-worker-thread)
                  (lambda (entrypoint)
                    (incf make-count)
                    (setf live-thread
                          (sb-thread:make-thread entrypoint))))
                 ((symbol-function 'cl-weave::isolated-cleanup-worker-loop)
                  (lambda ()
                    (sb-thread:signal-semaphore entered)
                    (sb-thread:wait-on-semaphore stop))))
              (setf worker-result
                    (sb-ext:with-timeout 5
                      (cl-weave::ensure-isolated-cleanup-worker))
                    entrypoint-observed-p
                    (sb-ext:with-timeout 5
                      (sb-thread:wait-on-semaphore entered))
                    global-worker-after cl-weave::*isolated-cleanup-worker*
                    live-thread-alive-p
                    (and live-thread
                         (sb-thread:thread-alive-p live-thread))
                    mutex-held-p
                    (sb-thread:holding-mutex-p
                     cl-weave::*isolated-cleanup-registry-mutex*)))
            (expect worker-result :to-be live-thread)
            (expect worker-result :not :to-be dead-thread)
            (expect global-worker-after :to-be live-thread)
            (expect make-count :to-be 1)
            (expect entrypoint-observed-p :to-be-truthy)
            (expect live-thread-alive-p :to-be-truthy)
            (expect mutex-held-p :to-be nil))
        (when live-thread
          (sb-thread:signal-semaphore stop)
          (handler-case
              (sb-ext:with-timeout 5
                (sb-thread:join-thread live-thread))
            (sb-ext:timeout ()
              (ignore-errors
                (sb-thread:terminate-thread live-thread))
              (ignore-errors
                (sb-thread:join-thread live-thread))))))))

  (progn
  (it "publishes handoff progress despite worker-start interruption"
    (let ((cl-weave::*isolated-cleanup-registry* nil)
          (cl-weave::*isolated-cleanup-next-id* 0)
          (cl-weave::*isolated-cleanup-last-warning-at* nil)
          (cl-weave::*isolated-cleanup-registry-mutex*
            (sb-thread:make-mutex :name "cleanup handoff test"))
          (cl-weave::*isolated-cleanup-registry-condition*
            (sb-thread:make-waitqueue :name "cleanup handoff test"))
          (owner
            (cl-weave::make-isolated-cleanup-owner
             :process nil
             :state :held))
          (release-called-p nil)
          (handoff-result :unset)
          (pump-result nil)
          (owner-state-after nil)
          (registry-after :unset))
      (with-mocked-functions
          (((symbol-function 'cl-weave::isolated-cleanup-now)
            (lambda () 0))
           ((symbol-function 'cl-weave::ensure-isolated-cleanup-worker)
            (lambda ()
              (throw 'cleanup-handoff-boundary :interrupted)))
           ((symbol-function 'cl-weave::close-isolated-fd)
            (lambda (fd) (declare (ignore fd))))
           ((symbol-function 'cl-weave::delete-isolated-cleanup-home)
            (lambda (home) (declare (ignore home)))))
        (cl-weave::isolated-cleanup-register owner)
        (setf handoff-result
              (sb-ext:with-timeout 5
                (catch 'cleanup-handoff-boundary
                  (cl-weave::handoff-isolated-cleanup-owner
                   owner nil nil
                   (lambda ()
                     (setf release-called-p t)))))
              pump-result
              (sb-ext:with-timeout 5
                (cl-weave::pump-isolated-cleanups))
              owner-state-after
              (cl-weave::isolated-cleanup-owner-state owner)
              registry-after cl-weave::*isolated-cleanup-registry*))
      (expect handoff-result :to-be :interrupted)
      (expect release-called-p :to-be-truthy)
      (expect pump-result :to-be 1)
      (expect owner-state-after :to-be :released)
      (expect registry-after :to-be nil)))

  (it "runs handoff fallback with interrupts enabled after worker creation failure"
    (let ((cl-weave::*isolated-cleanup-worker* nil)
          (cl-weave::*isolated-cleanup-registry* nil)
          (cl-weave::*isolated-cleanup-next-id* 0)
          (cl-weave::*isolated-cleanup-last-warning-at* nil)
          (cl-weave::*isolated-cleanup-registry-mutex*
            (sb-thread:make-mutex :name "cleanup handoff fallback test"))
          (cl-weave::*isolated-cleanup-registry-condition*
            (sb-thread:make-waitqueue :name "cleanup handoff fallback test"))
          (owner
            (cl-weave::make-isolated-cleanup-owner
             :process nil
             :state :held))
          (release-called-p nil)
          (make-count 0)
          (fallback-count 0)
          (fallback-interrupts-enabled-p nil)
          (handoff-result nil)
          (owner-state-after nil)
          (global-worker-after :unset)
          (mutex-held-p nil))
      (with-mocked-functions
          (((symbol-function 'cl-weave::isolated-cleanup-now)
            (lambda () 0))
           ((symbol-function
             'cl-weave::make-isolated-cleanup-worker-thread)
            (lambda (entrypoint)
              (declare (ignore entrypoint))
              (incf make-count)
              (error "thread creation failed during handoff")))
           ((symbol-function 'cl-weave::pump-isolated-cleanups)
            (lambda ()
              (setf fallback-interrupts-enabled-p
                    sb-sys:*interrupts-enabled*)
              (incf fallback-count)
              0)))
        (cl-weave::isolated-cleanup-register owner)
        (handler-bind
            ((warning
               (lambda (condition)
                 (muffle-warning condition))))
          (setf handoff-result
                (sb-ext:with-timeout 5
                  (cl-weave::handoff-isolated-cleanup-owner
                   owner nil nil
                   (lambda ()
                     (setf release-called-p t))))))
        (setf owner-state-after
              (cl-weave::isolated-cleanup-owner-state owner)
              global-worker-after cl-weave::*isolated-cleanup-worker*
              mutex-held-p
              (sb-thread:holding-mutex-p
               cl-weave::*isolated-cleanup-registry-mutex*)))
      (expect handoff-result :to-be-truthy)
      (expect release-called-p :to-be-truthy)
      (expect owner-state-after :to-be :ready)
      (expect make-count :to-be 1)
      (expect fallback-count :to-be 1)
      (expect fallback-interrupts-enabled-p :to-be-truthy)
      (expect global-worker-after :to-be nil)
      (expect mutex-held-p :to-be nil))))

  (progn
  (it "reacquires the cleanup mutex after condition wait returns unlocked"
      (let* ((owner
               (cl-weave::make-isolated-cleanup-owner
                :id 1
                :state :backoff
                :next-at 10))
             (cl-weave::*isolated-cleanup-registry* (list owner))
             (cl-weave::*isolated-cleanup-registry-mutex*
               (sb-thread:make-mutex :name "cleanup wait reacquire test"))
             (cl-weave::*isolated-cleanup-registry-condition*
               (sb-thread:make-waitqueue :name "cleanup wait reacquire test"))
             (held-before-wait-p nil)
             (wait-count 0))
        (with-mocked-functions
            (((symbol-function 'cl-weave::isolated-cleanup-now)
              (lambda () 0))
             ((symbol-function 'cl-weave::wait-on-isolated-cleanup-condition)
              (lambda (timeout)
                (declare (ignore timeout))
                (setf held-before-wait-p
                      (sb-thread:holding-mutex-p
                       cl-weave::*isolated-cleanup-registry-mutex*))
                (incf wait-count)
                (sb-thread:release-mutex
                 cl-weave::*isolated-cleanup-registry-mutex*)
                (setf (cl-weave::isolated-cleanup-owner-state owner) :ready
                      (cl-weave::isolated-cleanup-owner-next-at owner) 0))))
          (cl-weave::isolated-cleanup-worker-wait)
          (expect held-before-wait-p :to-be-truthy)
          (expect wait-count :to-be 1)
          (expect
           (sb-thread:holding-mutex-p
            cl-weave::*isolated-cleanup-registry-mutex*)
           :to-be
           nil))))

  (it "releases the cleanup mutex after interruption during acquisition"
      (let* ((cl-weave::*isolated-cleanup-registry* nil)
             (cl-weave::*isolated-cleanup-registry-mutex*
               (sb-thread:make-mutex :name "cleanup acquisition unwind test"))
             (cl-weave::*isolated-cleanup-registry-condition*
               (sb-thread:make-waitqueue :name "cleanup acquisition unwind test"))
             (target-mutex cl-weave::*isolated-cleanup-registry-mutex*)
             (original-grab (symbol-function 'sb-thread:grab-mutex))
             (original-release (symbol-function 'sb-thread:release-mutex))
             (caught nil))
        (unwind-protect
             (progn
               (sb-ext:without-package-locks
                 (with-mocked-functions
                     (((symbol-function 'sb-thread:grab-mutex)
                       (lambda (mutex &rest arguments)
                         (apply original-grab mutex arguments)
                         (when (eq mutex target-mutex)
                           (throw 'cleanup-worker-acquire-boundary :interrupted)))))
                   (setf caught
                         (catch 'cleanup-worker-acquire-boundary
                           (cl-weave::isolated-cleanup-worker-wait)))))
               (expect caught :to-be :interrupted)
               (expect (sb-thread:holding-mutex-p target-mutex)
                       :to-be
                       nil))
          (when (sb-thread:holding-mutex-p target-mutex)
            (funcall original-release target-mutex))))))))
(describe "isolated final output draining"
          (it "returns when a session-escaped writer keeps stdout ready"
              (let* ((pid-path
                      (merge-pathnames
                       (make-pathname
                        :name (cl-weave::isolated-temp-name "cl-weave-escaped-writer")
                        :type "pid")
                       (uiop:temporary-directory)))
                     (result-path
                      (merge-pathnames
                       (make-pathname
                        :name (cl-weave::isolated-temp-name "cl-weave-drain-result")
                        :type "sexp")
                       (uiop:temporary-directory)))
                     (marker (namestring pid-path))
                     (writer-form
                      `(progn
                         (require :sb-posix)
                         (funcall
                          (symbol-function (find-symbol "SETSID" "SB-POSIX")))
                         (with-open-file
                             (cl-user::stream
                              ,marker
                              :direction :output
                              :if-exists :supersede
                              :if-does-not-exist :create)
                           (write
                            (list (funcall (symbol-function (find-symbol "GETPID" "SB-POSIX"))) ,marker)
                            :stream cl-user::stream)
                           (finish-output cl-user::stream))
                         (let ((cl-user::chunk
                                (make-string 65536 :initial-element #\x)))
                           (loop
                            (write-string cl-user::chunk)
                            (finish-output)))))
                     (isolated-form
                      `(let ((cl-user::writer
                              (sb-ext:run-program
                               ,(cl-weave::isolated-sbcl-program)
                               (list
                                "--noinform"
                                "--disable-debugger"
                                "--non-interactive"
                                "--eval"
                                ,(prin1-to-string writer-form))
                               :search t
                               :wait nil
                               :input t
                               :output t
                               :error t)))
                         (declare (ignore cl-user::writer))
                         (sleep 30)))
                     (nested-form
                      `(let ((cl-user::result
                              (cl-weave:run-isolated
                               (quote ,isolated-form)
                               :systems nil
                               :package "CL-USER"
                               :timeout 30
                               :max-output-bytes 4096)))
                         (with-open-file
                             (cl-user::stream
                              ,(namestring result-path)
                              :direction :output
                              :if-exists :supersede
                              :if-does-not-exist :create)
                           (write
                            (list
                             (cl-weave:isolated-result-status cl-user::result)
                             (cl-weave::isolated-result-output-limit-exceeded-p
                              cl-user::result))
                            :stream cl-user::stream))))
                     (asd-path (asdf:system-source-file "cl-weave"))
                     process
                     completed-p)
                (labels ((read-writer-identity ()
                           (ignore-errors
                             (when (probe-file pid-path)
                               (with-open-file (stream pid-path :direction :input)
                                 (read stream nil nil)))))
                         (writer-process-command (pid)
                           (ignore-errors
                             (uiop:run-program
                              (list
                               "/bin/ps"
                               "-ww"
                               "-p"
                               (princ-to-string pid)
                               "-o"
                               "command=")
                              :output :string
                              :ignore-error-status t)))
                         (writer-process-matches-p (identity)
                           (and (consp identity)
                                (integerp (first identity))
                                (and (stringp (second identity)) (string= (second identity) marker))
                                (let ((command
                                       (writer-process-command (first identity))))
                                  (and command (search marker command))))))
                  (unwind-protect
                       (progn
                         (setf process
                               (sb-ext:run-program
                                (cl-weave::isolated-sbcl-program)
                                (list
                                 "--noinform"
                                 "--disable-debugger"
                                 "--non-interactive"
                                 "--eval"
                                 "(require :asdf)"
                                 "--eval"
                                 (format nil
                                         "(asdf:load-asd ~S)"
                                         (namestring asd-path))
                                 "--eval"
                                 "(asdf:load-system \"cl-weave\")"
                                 "--eval"
                                 (prin1-to-string nested-form))
                                :search t
                                :wait nil
                                :input t
                                :output t
                                :error t))
                         (loop repeat 1000
                               when (not (sb-ext:process-alive-p process))
                               do (setf completed-p t)
                               (return)
                               do (sleep 0.01))
                         (expect completed-p :to-be-truthy)
                         (when completed-p
                           (sb-ext:process-wait process)
                           (expect (sb-ext:process-exit-code process) :to-be 0)
                           (expect (probe-file pid-path) :to-be-truthy)
                           (expect (probe-file result-path) :to-be-truthy)
                           (when (probe-file result-path)
                             (with-open-file (stream result-path :direction :input)
                               (expect (read stream) :to-equal (quote (:fail t)))))))
                    (when (and process
                               (ignore-errors (sb-ext:process-alive-p process)))
                      (ignore-errors (sb-ext:process-kill process 9))
                      (ignore-errors (sb-ext:process-wait process)))
                    (let ((identity
                           (loop repeat 100
                                 for candidate = (read-writer-identity)
                                 when (writer-process-matches-p candidate)
                                 do (return candidate)
                                 do (sleep 0.01))))
                      (when (writer-process-matches-p identity)
                        (require :sb-posix)
                        (ignore-errors
                          (funcall
                           (symbol-function (find-symbol "KILL" "SB-POSIX"))
                           (first identity)
                           9)))
                      (loop repeat 200
                            while (writer-process-matches-p identity)
                            do (sleep 0.01))
                      (expect (writer-process-matches-p identity) :to-be nil))
                    (dolist (path (list pid-path result-path))
                      (when (probe-file path)
                        (ignore-errors (delete-file path))))))))))
