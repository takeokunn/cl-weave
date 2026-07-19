(in-package #:cl-weave)

(progn
  #+sbcl
  (eval-when (:compile-toplevel :load-toplevel :execute)
    (require :sb-posix))
  (defvar *isolated-timeout-seconds* 5))
  (defvar *isolated-max-output-bytes* (* 1024 1024))

(defstruct isolated-result status
  exit-code
  stdout
  stderr
  timed-out-p
  stdout-truncated-p
  stderr-truncated-p
  output-limit-exceeded-p
  elapsed-ms
  script-path
  stdout-path
  stderr-path
  home-path)

(defun finite-proper-list-p (object)
    (loop with slow = object
          with fast = object
          do (cond
               ((null fast) (return t))
               ((atom fast) (return nil))
               ((null (cdr fast)) (return t))
               ((atom (cdr fast)) (return nil))
               (t
                (setf slow (cdr slow)
                      fast (cddr fast))
                (when (eq slow fast)
                  (return nil))))))

  (defun normalize-isolated-systems (systems)
    (cond
      ((null systems) nil)
      ((stringp systems) (list systems))
      ((symbolp systems) (list (string-downcase (symbol-name systems))))
      ((finite-proper-list-p systems)
       (mapcar
         (lambda (system)
           (etypecase system
             (string system)
             (symbol (string-downcase (symbol-name system)))))
         systems))
      (t
       (error
         "cl-weave: isolated systems must be a string, symbol, or finite proper list."))))

(defun isolated-temp-name (prefix)
  (format nil "~A-~36R-~36R-~36R"
          prefix
          (get-internal-real-time)
          (get-universal-time)
          (random (expt 36 8))))

(defun isolated-temp-pathname (directory name type)
  (let ((pathname (merge-pathnames (make-pathname :name name :type type) directory)))
    (with-open-file (stream
        pathname
        :direction
        :output
        :if-exists
        :error
        :if-does-not-exist
        :create)
      (declare (ignorable stream)))
    (require :sb-posix)
    (funcall
      (symbol-function (find-symbol "CHMOD" "SB-POSIX"))
      (namestring pathname)
      #o600)
    pathname))

(defun isolated-temp-directory (prefix)
    (require :sb-posix)
    (let* ((template
          (merge-pathnames
            (make-pathname :name (format nil "~A-XXXXXX" prefix))
            (uiop:temporary-directory)))
           (mkdtemp (symbol-function (find-symbol "MKDTEMP" "SB-POSIX")))
           (created (funcall mkdtemp (namestring template))))
      (uiop:ensure-directory-pathname created)))
  #+
  sbcl
  (defun isolated-sbcl-program ()
  (or (when (and (boundp 'sb-ext:*runtime-pathname*)
                 sb-ext:*runtime-pathname*)
        (namestring sb-ext:*runtime-pathname*))
      "sbcl"))

#+sbcl
  (defstruct isolated-output-budget
    maximum-bytes
    (written-bytes 0))

  #+sbcl
  (defclass isolated-capped-output-stream (sb-gray:fundamental-character-output-stream)
    ((stream :initarg :stream :reader isolated-capped-output-stream-stream)
     (budget :initarg :budget :reader isolated-capped-output-stream-budget)
     (truncated-p :initform nil :accessor isolated-capped-output-stream-truncated-p)))

  #+sbcl
  (defmethod sb-gray:stream-write-char ((stream isolated-capped-output-stream) character)
    (let ((budget (isolated-capped-output-stream-budget stream)))
      (if (< (isolated-output-budget-written-bytes budget)
             (isolated-output-budget-maximum-bytes budget))
          (progn
            (write-byte (char-code character)
                        (isolated-capped-output-stream-stream stream))
            (incf (isolated-output-budget-written-bytes budget)))
          (setf (isolated-capped-output-stream-truncated-p stream) t)))
    character)

  #+sbcl
  (defmethod sb-gray:stream-write-string
      ((stream isolated-capped-output-stream) string &optional (start 0) end)
    (loop for index from start below (or end (length string))
          do (sb-gray:stream-write-char stream (char string index)))
    string)

  #+sbcl
  (defun read-isolated-output (pathname)
    (if (probe-file pathname)
        (with-open-file (stream pathname
                          :direction :input
                          :element-type '(unsigned-byte 8))
          (let ((octets
                  (make-array
                    (file-length stream)
                    :element-type '(unsigned-byte 8))))
            (read-sequence octets stream)
            (sb-ext:octets-to-string
              octets
              :external-format '(:utf-8 :replacement #\Replacement_Character))))
        ""))

  #-sbcl
  (defun read-isolated-output (pathname)
    (if (probe-file pathname)
        (uiop:read-file-string pathname)
        ""))

(defun maybe-path-namestring (pathname keep-files)
  (and keep-files pathname (namestring pathname)))

(defun normalize-isolated-keep-files (keep-files)
  (case keep-files
    ((nil) nil)
    ((t) t)
    (:on-failure :on-failure)
    (otherwise
     (error "cl-weave: isolated keep-files must be NIL, T, or :ON-FAILURE, got ~S."
            keep-files))))

(defun isolated-retain-files-p (keep-files status)
  (case keep-files
    ((nil) nil)
    ((t) t)
    (:on-failure (not (eq status :pass)))))

#+

sbcl

(defun isolated-environment-entry-name-p (name entry)
  (let ((prefix (concatenate 'string name "=")))
    (and (>= (length entry) (length prefix))
         (string= prefix (subseq entry 0 (length prefix))))))

#+

sbcl

(defun isolated-process-environment (home &optional (entries (sb-ext:posix-environ)))
  (let* ((cache (merge-pathnames #p".cache/" home))
         (temporary (merge-pathnames #p"tmp/" home))
         (inherited-variable-names
           '("ASDF_OUTPUT_TRANSLATIONS"
             "CL_SOURCE_REGISTRY"
             "DYLD_FALLBACK_LIBRARY_PATH"
             "DYLD_LIBRARY_PATH"
             "LANG"
             "LANGUAGE"
             "LC_ALL"
             "LC_CTYPE"
             "LD_LIBRARY_PATH"
             "LOGNAME"
             "NIX_PATH"
             "NIX_PROFILES"
             "NIX_SSL_CERT_FILE"
             "PATH"
             "PWD"
             "SBCL_HOME"
             "SHELL"
             "SSL_CERT_FILE"
             "TZ"
             "USER"))
         (replacements
           (list
             (format nil "HOME=~A" (namestring home))
             (format nil "TMPDIR=~A" (namestring temporary))
             (format nil "TMP=~A" (namestring temporary))
             (format nil "TEMP=~A" (namestring temporary))
             (format nil "XDG_CACHE_HOME=~A" (namestring cache)))))
    (ensure-directories-exist cache)
    (ensure-directories-exist temporary)
    (append
      replacements
      (loop for entry in entries
            when (some
                   (lambda (name)
                     (isolated-environment-entry-name-p name entry))
                   inherited-variable-names)
              collect entry))))

#+

sbcl

(defun write-isolated-worker-script (pathname marker form systems package)
    (with-open-file (stream pathname :direction :output :if-exists :supersede)
      (let ((*package* (find-package "KEYWORD"))
            (*print-case* :downcase)
            (*print-pretty* t)
            (*print-readably* t)
            (*print-circle* t)
            (marker-stream (gensym "MARKER-STREAM"))
            (completion-code (gensym "COMPLETION-CODE")))
        (write
          `(progn
             (progn
  (require :sb-posix)
  (funcall
   (symbol-function (find-symbol "SETPGID" "SB-POSIX"))
   0
   (funcall
    (symbol-function (find-symbol "GETPGID" "SB-POSIX"))
    (funcall
     (symbol-function (find-symbol "GETPPID" "SB-POSIX")))))
  (require :asdf))
             (pushnew
               (truename ".")
               (symbol-value (find-symbol "*CENTRAL-REGISTRY*" "ASDF"))
               :test #'equal)
             ,@(loop for system in systems
                     collect `(funcall
                                (symbol-function (find-symbol "LOAD-SYSTEM" "ASDF"))
                                ,system)))
          :stream stream)
        (terpri stream)
        (write
          `(in-package ,(string-upcase (string package)))
          :stream stream)
        (terpri stream)
        (write
          `(let ((,completion-code
                   (handler-case
                       (progn
                         ,form
                         0)
                     (serious-condition (condition)
                       (format *error-output* "~&~A~%" condition)
                       (funcall
                         (symbol-function (find-symbol "PRINT-BACKTRACE" "SB-DEBUG"))
                         :stream *error-output*)
                       1))))
             (finish-output *standard-output*)
             (finish-output *error-output*)
             (with-open-file (,marker-stream
                 ,(namestring marker)
                 :direction :output
                 :if-exists :supersede
                 :if-does-not-exist :create
                 :element-type '(unsigned-byte 8))
               (write-byte (+ 48 ,completion-code) ,marker-stream)
               (write-byte 10 ,marker-stream)
               (finish-output ,marker-stream)))
          :stream stream)
        (terpri stream)))
    pathname)

  (defun write-isolated-script
    (pathname worker ready marker anchor-control-fd completion-control-fd
     anchor-lifetime-fd)
  (with-open-file (stream pathname :direction :output :if-exists :supersede)
    (let ((*package* (find-package "KEYWORD"))
          (*print-case* :downcase)
          (*print-pretty* t)
          (*print-readably* t)
          (*print-circle* t)
          (ignored (gensym "IGNORED"))
          (input-fd (gensym "INPUT-FD"))
          (fd (gensym "FD"))
          (fd-flags (gensym "FD-FLAGS"))
          (anchor-process (gensym "ANCHOR-PROCESS"))
          (anchor-stream (gensym "ANCHOR-STREAM"))
          (ready-stream (gensym "READY-STREAM"))
          (worker-process (gensym "WORKER-PROCESS"))
          (marker-stream (gensym "MARKER-STREAM"))
          (completion-stream (gensym "COMPLETION-STREAM"))
          (completion-code (gensym "COMPLETION-CODE"))
          (marker-octets (gensym "MARKER-OCTETS"))
          (marker-count (gensym "MARKER-COUNT"))
          (worker-status (gensym "WORKER-STATUS"))
          (worker-exit-code (gensym "WORKER-EXIT-CODE")))
      (write
       `(progn
          (require :sb-posix)
          (progn
            (funcall
             (symbol-function (find-symbol "SETPGID" "SB-POSIX"))
             0
             (funcall
              (symbol-function (find-symbol "GETPGID" "SB-POSIX"))
              (funcall
               (symbol-function (find-symbol "GETPPID" "SB-POSIX")))))
            (funcall (symbol-function (find-symbol "SETSID" "SB-POSIX"))))
          (funcall
           (symbol-function (find-symbol "ENABLE-INTERRUPT" "SB-SYS"))
           (symbol-value (find-symbol "SIGTERM" "SB-UNIX"))
           (lambda (&rest ,ignored)
             (declare (ignore ,ignored))))
          (dolist (,fd (list ,anchor-control-fd ,completion-control-fd))
            (let ((,fd-flags
                    (funcall
                     (symbol-function (find-symbol "FCNTL" "SB-POSIX"))
                     ,fd
                     (symbol-value (find-symbol "F-GETFD" "SB-POSIX")))))
              (funcall
               (symbol-function (find-symbol "FCNTL" "SB-POSIX"))
               ,fd
               (symbol-value (find-symbol "F-SETFD" "SB-POSIX"))
               (logior ,fd-flags 1))))
          (let ((,input-fd
                  (funcall
                   (symbol-function (find-symbol "OPEN" "SB-POSIX"))
                   "/dev/null"
                   (symbol-value (find-symbol "O-RDONLY" "SB-POSIX")))))
            (unwind-protect
                 (funcall
                  (symbol-function (find-symbol "DUP2" "SB-POSIX"))
                  ,input-fd
                  0)
              (unless (= ,input-fd 0)
                (funcall
                 (symbol-function (find-symbol "CLOSE" "SB-POSIX"))
                 ,input-fd))))
          (let ((,anchor-process
                  (sb-ext:run-program
                   ,(isolated-sbcl-program)
                   (list
                    "--noinform"
                    "--no-userinit"
                    "--no-sysinit"
                    "--disable-debugger"
                    "--eval"
                    (format
 nil
 "(progn (require :sb-posix) (let ((supervisor-pid (funcall (symbol-function (find-symbol \"GETPPID\" \"SB-POSIX\"))))) (funcall (symbol-function (find-symbol \"SETPGID\" \"SB-POSIX\")) 0 (funcall (symbol-function (find-symbol \"GETPGID\" \"SB-POSIX\")) supervisor-pid)) (let* ((fd ~D) (fcntl (symbol-function (find-symbol \"FCNTL\" \"SB-POSIX\"))) (flags (funcall fcntl fd (symbol-value (find-symbol \"F-GETFD\" \"SB-POSIX\"))))) (funcall fcntl fd (symbol-value (find-symbol \"F-SETFD\" \"SB-POSIX\")) (logior flags 1))) (write-line \"1\") (finish-output) (loop :until (probe-file ~S) do (unless (= (funcall (symbol-function (find-symbol \"GETPPID\" \"SB-POSIX\"))) supervisor-pid) (sb-ext:exit :code 0)) (sleep 0.001)) (sb-sys:enable-interrupt sb-unix:sigterm (lambda (&rest ignored) (declare (ignore ignored)))) (loop (sleep 3600))))"
 ,anchor-lifetime-fd
 ,(namestring (merge-pathnames #p"ack" ready))))
                   :search t
                   :wait nil
                   :input nil
                   :output :stream
                   :error nil
                   :preserve-fds (list ,anchor-lifetime-fd))))
            (progn
  (let ((cl-user::anchor-ready-line
          (read-line (sb-ext:process-output ,anchor-process) nil nil)))
    (unless (equal cl-user::anchor-ready-line "1")
      (error "Isolated anchor failed to join the supervisor process group.")))
  (funcall
   (symbol-function (find-symbol "CLOSE" "SB-POSIX"))
   ,anchor-lifetime-fd))
            (with-open-stream
                (,anchor-stream
                 (sb-sys:make-fd-stream
                  ,anchor-control-fd
                  :output t
                  :element-type 'character
                  :external-format :ascii
                  :buffering :none
                  :auto-close t))
              (format ,anchor-stream "~D~%" (sb-ext:process-pid ,anchor-process))
              (finish-output ,anchor-stream))
            (with-open-file (,ready-stream
                             ,(namestring ready)
                             :direction :output
                             :if-exists :supersede
                             :if-does-not-exist :create)
              (declare (ignore ,ready-stream)))
            (loop :until (probe-file
                          ,(namestring (merge-pathnames #p"ack" ready)))
                  do (sleep 0.001))
            (let ((,worker-process
                    (sb-ext:run-program
                     ,(isolated-sbcl-program)
                     (list "--script" ,(namestring worker))
                     :search t
                     :wait nil
                     :input t
                     :output t
                     :error t)))
              (sb-ext:process-wait ,worker-process)
              (let* ((,worker-status (sb-ext:process-status ,worker-process))
                     (,worker-exit-code
                       (and (eq ,worker-status :exited)
                            (sb-ext:process-exit-code ,worker-process)))
                     (,completion-code
                       (when (and (eq ,worker-status :exited)
                                  (eql ,worker-exit-code 0)
                                  (probe-file ,(namestring marker)))
                         (handler-case
                             (with-open-file
                                 (,marker-stream
                                  ,(namestring marker)
                                  :direction :input
                                  :element-type '(unsigned-byte 8))
                               (let* ((,marker-octets
                                        (make-array
                                         3
                                         :element-type '(unsigned-byte 8)))
                                      (,marker-count
                                        (read-sequence
                                         ,marker-octets ,marker-stream)))
                                 (and (= ,marker-count 2)
                                      (member (aref ,marker-octets 0) '(48 49))
                                      (= (aref ,marker-octets 1) 10)
                                      (- (aref ,marker-octets 0) 48))))
                           (error () nil)))))
                (with-open-stream
                    (,completion-stream
                     (sb-sys:make-fd-stream
                      ,completion-control-fd
                      :output t
                      :element-type '(unsigned-byte 8)
                      :buffering :none
                      :auto-close t))
                  (write-byte (+ 48 (or ,completion-code 1))
                              ,completion-stream)
                  (write-byte 10 ,completion-stream)
                  (finish-output ,completion-stream))
                (loop (sleep 3600))))))
       :stream stream)
      (terpri stream)))
  pathname)

#+

sbcl

(progn
  (defun isolated-pid-identities (pid)
    (handler-case
        (progn
          (require :sb-posix)
          (let ((process-group-id
                  (funcall
                   (symbol-function (find-symbol "GETPGID" "SB-POSIX"))
                   pid))
                (session-id
                  (funcall
                   (symbol-function (find-symbol "GETSID" "SB-POSIX"))
                   pid)))
            (values pid process-group-id session-id t)))
      (error ()
        (values nil nil nil nil))))

  (defun isolated-process-identities (process)
    (isolated-pid-identities (sb-ext:process-pid process))))

  (progn
  (defstruct
      (isolated-process-group-authority
       (:constructor make-isolated-process-group-authority
           (process process-group-id anchor-pid anchor-lifetime-fd
            &optional (session-id process-group-id))))
    process
    process-group-id
    session-id
    anchor-pid
    anchor-lifetime-fd
    (state :active :type symbol)
    (term-attempted-p nil :type boolean)
    (kill-attempted-p nil :type boolean)
    (active-p t :type boolean))

  (defun isolated-anchor-lifetime-valid-p (anchor-lifetime-fd)
    (and anchor-lifetime-fd
         (not
          (handler-case
              (sb-sys:wait-until-fd-usable
               anchor-lifetime-fd :input 0 nil)
            (error () t)))))

  (defun capture-isolated-process-group-authority
      (process anchor-pid anchor-lifetime-fd parent-session-id)
    (multiple-value-bind (pid process-group-id session-id leader-valid-p)
        (isolated-process-identities process)
      (multiple-value-bind
          (current-anchor-pid anchor-process-group-id anchor-session-id
           anchor-valid-p)
          (isolated-pid-identities anchor-pid)
        (when (and leader-valid-p
                   anchor-valid-p
                   (= pid process-group-id session-id)
                   (= anchor-pid current-anchor-pid)
                   (/= anchor-pid pid)
                   (= anchor-process-group-id process-group-id)
                   (= anchor-session-id session-id)
                   (/= session-id parent-session-id)
                   (isolated-anchor-lifetime-valid-p anchor-lifetime-fd))
          (make-isolated-process-group-authority
           process process-group-id anchor-pid anchor-lifetime-fd session-id)))))

  (defun isolated-process-group-owned-p
      (process anchor-pid anchor-lifetime-fd parent-session-id)
    (not
     (null
      (capture-isolated-process-group-authority
       process anchor-pid anchor-lifetime-fd parent-session-id)))))

  (progn
  (defun isolated-deadline (started timeout)
    (+ started
       (ceiling (* timeout internal-time-units-per-second))))

  (defun isolated-deadline-expired-p (deadline)
    (>= (get-internal-real-time) deadline))

  (defun isolated-deadline-remaining-seconds (deadline)
    (max 0
         (/ (- deadline (get-internal-real-time))
            internal-time-units-per-second)))

  (defun isolated-earlier-deadline (deadline seconds)
    (min deadline
         (+ (get-internal-real-time)
            (ceiling (* seconds internal-time-units-per-second)))))

  (defun isolated-sleep-before-deadline (seconds deadline)
    (let ((duration
            (min seconds
                 (isolated-deadline-remaining-seconds deadline))))
      (when (plusp duration)
        (sleep duration))))

  (defun close-isolated-fd (fd)
    (when fd
      (ignore-errors
        (funcall
         (symbol-function (find-symbol "CLOSE" "SB-POSIX"))
         fd))))

  (defun configure-isolated-control-read-fd (fd)
    (let* ((fcntl (symbol-function (find-symbol "FCNTL" "SB-POSIX")))
           (flags
             (funcall
              fcntl fd (symbol-value (find-symbol "F-GETFL" "SB-POSIX")))))
      (funcall
       fcntl
       fd
       (symbol-value (find-symbol "F-SETFL" "SB-POSIX"))
       (logior flags (symbol-value (find-symbol "O-NONBLOCK" "SB-POSIX"))))
      fd))

  (defstruct
      (isolated-control-frame
       (:constructor %make-isolated-control-frame
           (maximum-bytes octets)))
    maximum-bytes
    octets
    (eof-p nil :type boolean)
    (invalid-p nil :type boolean))

  (defun make-isolated-control-frame (maximum-bytes)
    (%make-isolated-control-frame
     maximum-bytes
     (make-array
      maximum-bytes
      :element-type '(unsigned-byte 8)
      :adjustable t
      :fill-pointer 0)))

  (defun poll-isolated-control-frame (fd frame)
    (cond
      ((isolated-control-frame-invalid-p frame) :invalid)
      ((isolated-control-frame-eof-p frame) :eof)
      ((not
        (handler-case
            (sb-sys:wait-until-fd-usable fd :input 0 nil)
          (error ()
            (setf (isolated-control-frame-invalid-p frame) t)
            nil)))
       (if (isolated-control-frame-invalid-p frame)
           :invalid
           :pending))
      (t
       (let* ((maximum-bytes
                (isolated-control-frame-maximum-bytes frame))
              (buffer
                (make-array
                 (1+ maximum-bytes)
                 :element-type '(unsigned-byte 8)))
              (count
                (handler-case
                    (sb-sys:with-pinned-objects (buffer)
                      (funcall
                       (symbol-function (find-symbol "READ" "SB-POSIX"))
                       fd
                       (sb-sys:vector-sap buffer)
                       (length buffer)))
                  (error () nil))))
         (cond
           ((null count)
            (setf (isolated-control-frame-invalid-p frame) t)
            :invalid)
           ((zerop count)
            (setf (isolated-control-frame-eof-p frame) t)
            :eof)
           ((> count
               (- maximum-bytes
                  (length (isolated-control-frame-octets frame))))
            (setf (isolated-control-frame-invalid-p frame) t)
            :invalid)
           (t
            (loop for index below count
                  do (vector-push-extend
                      (aref buffer index)
                      (isolated-control-frame-octets frame)))
            :pending))))))

  (defun isolated-completion-frame-code (fd frame)
    (case (poll-isolated-control-frame fd frame)
      (:invalid (values nil :invalid))
      (:eof
       (let ((octets (isolated-control-frame-octets frame)))
         (if (and (= (length octets) 2)
                  (member (aref octets 0) '(48 49))
                  (= (aref octets 1) 10))
             (values (- (aref octets 0) 48) :complete)
             (values nil :invalid))))
      (t (values nil :pending))))

  (defun isolated-anchor-frame-pid (fd frame)
    (case (poll-isolated-control-frame fd frame)
      (:invalid (values nil :invalid))
      (:eof
       (let* ((octets (isolated-control-frame-octets frame))
              (length (length octets)))
         (if (and (<= 2 length 32)
                  (= (aref octets (1- length)) 10)
                  (/= (aref octets 0) 48)
                  (loop for index below (1- length)
                        always (<= 48 (aref octets index) 57)))
             (values
              (parse-integer
               (coerce
                (loop for index below (1- length)
                      collect (code-char (aref octets index)))
                'string))
              :complete)
             (values nil :invalid))))
      (t (values nil :pending))))

  (defun acknowledge-isolated-process-group
      (process ready anchor-pid anchor-lifetime-fd parent-session-id
       &optional authority-cell)
    (let ((authority
            (and (probe-file ready)
                 (capture-isolated-process-group-authority
                  process anchor-pid anchor-lifetime-fd parent-session-id))))
      (when authority
        (when authority-cell
          (setf (car authority-cell) authority))
        (with-open-file (stream
                         (merge-pathnames #p"ack" ready)
                         :direction :output
                         :if-exists :supersede
                         :if-does-not-exist :create)
          (declare (ignorable stream)))
        authority))))

  (defun isolated-process-group-acknowledged-p
    (process ready anchor-pid anchor-lifetime-fd parent-session-id)
  (and (probe-file (merge-pathnames #p"ack" ready))
       (isolated-process-group-owned-p
        process anchor-pid anchor-lifetime-fd parent-session-id)))

  (progn)

  (defun read-isolated-completion-code (completion)
  (when (probe-file completion)
    (handler-case
        (with-open-file (stream completion
                          :direction :input
                          :element-type '(unsigned-byte 8))
          (let* ((octets
                   (make-array 3 :element-type '(unsigned-byte 8)))
                 (count (read-sequence octets stream)))
            (and (= count 2)
                 (member (aref octets 0) '(48 49))
                 (= (aref octets 1) 10)
                 (- (aref octets 0) 48))))
      (error () nil))))

  (defun isolated-process-output-stream (process)
    (sb-ext:process-output process))

  (defun isolated-process-error-stream (process)
    (sb-ext:process-error process))

  (defun isolated-process-alive-p (process)
    (sb-ext:process-alive-p process))

  (defun wait-for-isolated-process-exit (process)
    (sb-ext:process-wait process))

  (defun reap-isolated-process (process deadline)
  (loop
    (multiple-value-bind (alive-p known-p)
        (handler-case
            (values (isolated-process-alive-p process) t)
          (error ()
            (values nil nil)))
      (cond
        ((not known-p)
         (return :pending))
        ((not alive-p)
         (return
           (handler-case
               (progn
                 (wait-for-isolated-process-exit process)
                 :reaped)
             (error () :pending))))
        ((isolated-deadline-expired-p deadline)
         (return :pending))
        (t
         (isolated-sleep-before-deadline 0.01 deadline))))))

  (defun isolated-process-kill (process signal &optional (whom :pid))
    (sb-ext:process-kill process signal whom))

  (progn
  (defun retire-isolated-process-group-authority (authority state)
    (setf (isolated-process-group-authority-state authority) state
          (isolated-process-group-authority-active-p authority) nil)
    state)

  (defun isolated-process-group-authority-anchor-valid-p (authority)
    (and
     (isolated-anchor-lifetime-valid-p
      (isolated-process-group-authority-anchor-lifetime-fd authority))
     (multiple-value-bind
         (anchor-pid process-group-id session-id valid-p)
         (isolated-pid-identities
          (isolated-process-group-authority-anchor-pid authority))
       (and valid-p
            (= anchor-pid
               (isolated-process-group-authority-anchor-pid authority))
            (= process-group-id
               (isolated-process-group-authority-process-group-id authority))
            (= session-id
               (isolated-process-group-authority-session-id authority))))))

  (defun isolated-process-aliveness (process)
    (handler-case
        (if (isolated-process-alive-p process) :alive :dead)
      (error () :unknown)))

  (defun isolated-process-group-authority-leader-valid-p (authority)
    (multiple-value-bind (process-id process-group-id session-id valid-p)
        (isolated-process-identities
         (isolated-process-group-authority-process authority))
      (if valid-p
          (and (= process-id
                  (isolated-process-group-authority-process-group-id authority))
               (= process-group-id
                  (isolated-process-group-authority-process-group-id authority))
               (= session-id
                  (isolated-process-group-authority-session-id authority)))
          (eq (isolated-process-aliveness
               (isolated-process-group-authority-process authority))
              :dead))))

  (defun isolated-process-group-authority-identity-valid-p (authority)
    (and (isolated-process-group-authority-active-p authority)
         (isolated-process-group-authority-anchor-valid-p authority)
         (isolated-process-group-authority-leader-valid-p authority)))

  (defun isolated-system-call-error-number-p (error-number name)
    (when error-number
      (require :sb-posix)
      (let ((error-symbol (find-symbol name "SB-POSIX")))
        (and error-symbol
             (boundp error-symbol)
             (= error-number (symbol-value error-symbol))))))

  (defun isolated-no-such-process-error-p (error-number)
    (isolated-system-call-error-number-p error-number "ESRCH"))

  (defun isolated-interrupted-system-call-error-p (error-number)
    (isolated-system-call-error-number-p error-number "EINTR"))

  (defun isolated-kill-process-group-id (process-group-id signal)
    (handler-case
        (progn
          (funcall
           (symbol-function (find-symbol "KILL" "SB-POSIX"))
           (- process-group-id)
           signal)
          (values t nil))
      (sb-posix:syscall-error (condition)
        (values nil (sb-posix:syscall-errno condition)))
      (error ()
        (values nil nil))))

  (defun signal-isolated-process-group (authority signal deadline)
    (labels ((retire-undelivered ()
               (retire-isolated-process-group-authority
                authority
                (if (= signal 9)
                    :kill-undelivered
                    :signal-undelivered))))
      (cond
        ((not (isolated-process-group-authority-active-p authority))
         (values nil
                 (isolated-process-group-authority-state authority)))
        ((and (= signal 15)
              (isolated-process-group-authority-term-attempted-p authority))
         (values nil :already-attempted))
        ((and (= signal 9)
              (isolated-process-group-authority-kill-attempted-p authority))
         (values nil :already-attempted))
        ((not
          (isolated-process-group-authority-identity-valid-p authority))
         (retire-isolated-process-group-authority authority :scope-lost)
         (values nil :scope-lost))
        (t
         (loop
           (multiple-value-bind (sent-p error-number)
               (isolated-kill-process-group-id
                (isolated-process-group-authority-process-group-id authority)
                signal)
             (cond
               (sent-p
                (when (= signal 15)
                  (setf
                   (isolated-process-group-authority-term-attempted-p authority)
                   t))
                (when (= signal 9)
                  (setf
                   (isolated-process-group-authority-kill-attempted-p authority)
                   t))
                (setf (isolated-process-group-authority-state authority)
                      (case signal
                        (15 :term-sent)
                        (9 :kill-sent)
                        (t
                         (isolated-process-group-authority-state authority))))
                (return (values t :sent)))
               ((isolated-no-such-process-error-p error-number)
                (retire-isolated-process-group-authority authority :retired)
                (return (values nil :absent)))
               ((isolated-interrupted-system-call-error-p error-number)
                (if (isolated-deadline-expired-p deadline)
                    (progn
                      (retire-undelivered)
                      (return (values nil :error)))
                    (isolated-sleep-before-deadline 0.001 deadline)))
               (t
                (retire-undelivered)
                (return (values nil :error))))))))))

  (defun isolated-process-group-present-p (authority deadline)
    (multiple-value-bind (sent-p status)
        (signal-isolated-process-group authority 0 deadline)
      (declare (ignore sent-p))
      (values (member status (list :sent :error)) status)))

  (defun wait-for-isolated-process-group-absence (authority deadline)
    (loop
      (multiple-value-bind (present-p status)
          (isolated-process-group-present-p authority deadline)
        (unless present-p
          (return
            (if (member status
                        (list :scope-lost
                              :signal-undelivered
                              :kill-undelivered))
                :scope-lost
                :absent))))
      (when (isolated-deadline-expired-p deadline)
        (return :timeout))
      (isolated-sleep-before-deadline 0.01 deadline)))

  (progn
 (defun wait-for-isolated-anchor-lifetime-exit (anchor-lifetime-fd deadline)
   (loop
     (unless (isolated-anchor-lifetime-valid-p anchor-lifetime-fd)
       (return :exited))
     (when (isolated-deadline-expired-p deadline)
       (return :pending))
     (isolated-sleep-before-deadline 0.01 deadline)))

 (defun wait-for-isolated-anchor-exit (authority deadline)
   (wait-for-isolated-anchor-lifetime-exit
    (isolated-process-group-authority-anchor-lifetime-fd authority)
    deadline))))

  (progn (progn
  (defconstant +isolated-cleanup-retry-count+ 3)
  (defconstant +isolated-process-group-term-wait-seconds+ 1/20)
  (defconstant +isolated-process-group-kill-wait-seconds+ 1/4)

  (defun terminate-isolated-process
      (process process-group-authority parent-session-id deadline)
    (declare (ignore parent-session-id))
    (let ((deadline
            (if (isolated-deadline-expired-p deadline)
                (isolated-deadline
                 (get-internal-real-time)
                 (+ +isolated-process-group-term-wait-seconds+
                    +isolated-process-group-kill-wait-seconds+))
                deadline)))
      (labels ((alive-p ()
                 (ignore-errors (isolated-process-alive-p process)))
               (send-pid (signal)
                 (ignore-errors
                   (isolated-process-kill process signal)))
               (reap ()
                 (reap-isolated-process process deadline))
               (retire-and-reap ()
                 (let ((reap-status (reap)))
                   (when (eq reap-status :reaped)
                     (retire-isolated-process-group-authority
                      process-group-authority :retired))
                   reap-status)))
        (if (isolated-process-group-authority-p process-group-authority)
            (case
                (isolated-process-group-authority-state
                 process-group-authority)
              (:retired
               (reap))
              ((:scope-lost :signal-undelivered :kill-undelivered)
               :pending)
              (:kill-sent
               (if (eq (wait-for-isolated-anchor-exit
                        process-group-authority deadline)
                       :exited)
                   (retire-and-reap)
                   :pending))
              (t
               (multiple-value-bind (term-sent-p term-status)
                   (signal-isolated-process-group
                    process-group-authority 15 deadline)
                 (declare (ignore term-sent-p))
                 (case term-status
                   ((:scope-lost :signal-undelivered :kill-undelivered :error)
                    :pending)
                   (:absent
                    (reap))
                   (t
                    (let ((term-deadline
                            (isolated-earlier-deadline
                             deadline
                             +isolated-process-group-term-wait-seconds+)))
                      (loop
                        (unless
                            (isolated-anchor-lifetime-valid-p
                             (isolated-process-group-authority-anchor-lifetime-fd
                              process-group-authority))
                          (return-from terminate-isolated-process
                            (retire-and-reap)))
                        (when (isolated-deadline-expired-p term-deadline)
                          (return))
                        (isolated-sleep-before-deadline 0.005 term-deadline)))
                    (multiple-value-bind (kill-sent-p kill-status)
                        (signal-isolated-process-group
                         process-group-authority 9 deadline)
                      (declare (ignore kill-sent-p))
                      (case kill-status
                        (:absent
                         (reap))
                        (:sent
                         (if (eq (wait-for-isolated-anchor-exit
                                  process-group-authority deadline)
                                 :exited)
                             (retire-and-reap)
                             :pending))
                        (t :pending))))))))
            (progn
              (when (alive-p)
                (send-pid 15)
                (isolated-sleep-before-deadline 0.05 deadline)
                (when (alive-p)
                  (send-pid 9)))
              (reap))))))) (defconstant +isolated-cleanup-claim-limit+ 8)
(defconstant +isolated-cleanup-high-water-mark+ 64)
(defconstant +isolated-cleanup-warning-interval-seconds+ 60)
(defconstant +isolated-cleanup-quarantine-attempts+ 3)
(defconstant +isolated-cleanup-attempt-seconds+ 1/2)

(defstruct
    (isolated-cleanup-owner
     (:constructor make-isolated-cleanup-owner
         (&key id process authority parent-session-id home delete-home-p
          completion-control-fd anchor-lifetime-fd
          (state :held) (attempts 0) (next-at 0) last-error)))
  id
  process
  authority
  parent-session-id
  home
  delete-home-p
  completion-control-fd
  anchor-lifetime-fd
  state
  attempts
  next-at
  last-error)

(defvar *isolated-cleanup-registry* nil)
(defvar *isolated-cleanup-next-id* 0)
(defvar *isolated-cleanup-last-warning-at* nil)
  (defconstant +isolated-cleanup-unrestricted-claim-scope+ :unrestricted)
  (defvar *isolated-cleanup-claim-scope*
    +isolated-cleanup-unrestricted-claim-scope+)
#+sb-thread
(defvar *isolated-cleanup-registry-mutex*
  (sb-thread:make-mutex :name "cl-weave isolated cleanup registry"))
#+sb-thread
(defvar *isolated-cleanup-registry-condition*
  (sb-thread:make-waitqueue :name "cl-weave isolated cleanup registry"))
#+sb-thread
(defvar *isolated-cleanup-worker* nil)

(defmacro with-isolated-cleanup-registry-lock (&body body)
  #+sb-thread
  `(sb-thread:with-mutex (*isolated-cleanup-registry-mutex*)
     ,@body)
  #-sb-thread
  `(progn ,@body))

(defun isolated-cleanup-now ()
  (/ (get-internal-real-time) internal-time-units-per-second))

(defun isolated-cleanup-retry-delay (attempts)
  (min 2 (* 1/20 (expt 2 (min attempts 5)))))

(defun isolated-cleanup-claimable-p (owner now)
  (and (member (isolated-cleanup-owner-state owner)
               '(:ready :backoff :quarantined))
       (<= (isolated-cleanup-owner-next-at owner) now)))

(progn
  (defun publish-isolated-cleanup-owner (owner publish-local-owner)
    (let ((entry (list owner)))
      (multiple-value-bind (warn-p count)
          (flet ((register-owner ()
                   (with-isolated-cleanup-registry-lock
                     (when (member owner *isolated-cleanup-registry* :test #'eq)
                       (error "Isolated cleanup owner is already registered"))
                     (setf (isolated-cleanup-owner-id owner)
                           (incf *isolated-cleanup-next-id*)
                           (isolated-cleanup-owner-state owner) :held
                           (isolated-cleanup-owner-next-at owner) 0
                           *isolated-cleanup-registry*
                           (nconc *isolated-cleanup-registry* entry))
                     (funcall publish-local-owner owner)
                     (let* ((now (isolated-cleanup-now))
                            (count (length *isolated-cleanup-registry*))
                            (warn-p
                              (and
                               (>= count +isolated-cleanup-high-water-mark+)
                               (or
                                (null *isolated-cleanup-last-warning-at*)
                                (>=
                                 (- now *isolated-cleanup-last-warning-at*)
                                 +isolated-cleanup-warning-interval-seconds+)))))
                       (when warn-p
                         (setf *isolated-cleanup-last-warning-at* now))
                       (values warn-p count)))))
            #+sb-thread
            (sb-sys:without-interrupts (register-owner))
            #-sb-thread
            (register-owner))
        (when warn-p
          (warn "cl-weave has ~D deferred isolated cleanups" count))
        owner)))

  (defun isolated-cleanup-register (owner)
    (publish-isolated-cleanup-owner
     owner
     (lambda (registered-owner)
       (declare (ignore registered-owner))))))

(progn
  (defun discard-held-isolated-cleanup-owner (owner)
    (flet ((discard-owner ()
             (with-isolated-cleanup-registry-lock
               (when
                   (and
                    (member owner *isolated-cleanup-registry* :test #'eq)
                    (eq (isolated-cleanup-owner-state owner) :held))
                 (setf *isolated-cleanup-registry*
                       (delete owner *isolated-cleanup-registry* :test #'eq)
                       (isolated-cleanup-owner-state owner) :released
                       (isolated-cleanup-owner-process owner) nil
                       (isolated-cleanup-owner-authority owner) nil
                       (isolated-cleanup-owner-home owner) nil
                       (isolated-cleanup-owner-completion-control-fd owner) nil
                       (isolated-cleanup-owner-anchor-lifetime-fd owner) nil)
                 #+sb-thread
                 (sb-thread:condition-broadcast
                  *isolated-cleanup-registry-condition*)
                 t))))
      #+sb-thread
      (sb-sys:without-interrupts (discard-owner))
      #-sb-thread
      (discard-owner)))

  (defun handoff-isolated-cleanup-owner
      (owner authority delete-home-p release-local-owner)
    (let ((transitioned-p nil))
      (unwind-protect
          (flet ((transfer-owner ()
                   (with-isolated-cleanup-registry-lock
                     (when
                         (and
                          (member owner *isolated-cleanup-registry* :test #'eq)
                          (eq (isolated-cleanup-owner-state owner) :held))
                       (setf (isolated-cleanup-owner-authority owner) authority
                             (isolated-cleanup-owner-delete-home-p owner)
                             delete-home-p)
                       (funcall release-local-owner)
                       (setf (isolated-cleanup-owner-state owner) :ready
                             (isolated-cleanup-owner-next-at owner)
                             (isolated-cleanup-now)
                             transitioned-p t)
                       #+sb-thread
                       (sb-thread:condition-broadcast
                        *isolated-cleanup-registry-condition*)))))
            #+sb-thread
            (sb-sys:without-interrupts (transfer-owner))
            #-sb-thread
            (transfer-owner))
        (when transitioned-p
          #+sb-thread
          (ensure-isolated-cleanup-worker)
          #-sb-thread
          (pump-isolated-cleanups)))
      transitioned-p))

  (defun claim-isolated-cleanup (publish-current-owner)
    (let ((claimed-owner nil))
      (flet ((claim-owner ()
               (with-isolated-cleanup-registry-lock
                 (let ((now (isolated-cleanup-now)))
                   (setf claimed-owner
                         (find-if
                          (lambda (owner)
                            (and
                             (or
                              (eq
                               *isolated-cleanup-claim-scope*
                               +isolated-cleanup-unrestricted-claim-scope+)
                              (member
                               owner
                               *isolated-cleanup-claim-scope*
                               :test #'eq))
                             (isolated-cleanup-claimable-p owner now)))
                          *isolated-cleanup-registry*))
                   (when claimed-owner
                     (setf (isolated-cleanup-owner-state claimed-owner)
                           :running
                           *isolated-cleanup-registry*
                           (nconc
                            (delete
                             claimed-owner
                             *isolated-cleanup-registry*
                             :test #'eq
                             :count 1)
                            (list claimed-owner)))
                     (funcall publish-current-owner claimed-owner))))))
        #+sb-thread
        (sb-sys:without-interrupts (claim-owner))
        #-sb-thread
        (claim-owner))
      claimed-owner)))

(defun defer-isolated-cleanup-owner (owner condition)
  (flet ((defer-owner ()
           (with-isolated-cleanup-registry-lock
             (when
                 (and
                  (member owner *isolated-cleanup-registry* :test #'eq)
                  (member
                   (isolated-cleanup-owner-state owner)
                   '(:running :releasing)))
               (let* ((attempts
                        (incf (isolated-cleanup-owner-attempts owner)))
                      (state
                        (if
                         (>=
                          attempts
                          +isolated-cleanup-quarantine-attempts+)
                         :quarantined
                         :backoff)))
                 (setf (isolated-cleanup-owner-state owner) state
                       (isolated-cleanup-owner-next-at owner)
                       (+
                        (isolated-cleanup-now)
                        (isolated-cleanup-retry-delay attempts))
                       (isolated-cleanup-owner-last-error owner)
                       (and condition (princ-to-string condition)))
                 #+sb-thread
                 (sb-thread:condition-broadcast
                  *isolated-cleanup-registry-condition*)
                 state)))))
    #+sb-thread
    (sb-sys:without-interrupts (defer-owner))
    #-sb-thread
    (defer-owner)))

(defun delete-isolated-cleanup-home (home)
  (when home
    (uiop:delete-directory-tree
     home :validate t :if-does-not-exist :ignore)))

(defun release-isolated-cleanup-owner (owner)
  (let ((release-started-p nil)
        (release-completed-p nil)
        (completion-control-fd nil)
        (anchor-lifetime-fd nil)
        (home nil)
        (delete-home-p nil)
        (completion-close-attempted-p nil)
        (anchor-close-attempted-p nil)
        (close-condition nil))
    (labels ((begin-release ()
               (with-isolated-cleanup-registry-lock
                 (when (and (member owner *isolated-cleanup-registry*
                                    :test #'eq)
                            (eq (isolated-cleanup-owner-state owner) :running))
                   (let ((authority
                           (isolated-cleanup-owner-authority owner)))
                     (setf completion-control-fd
                           (isolated-cleanup-owner-completion-control-fd owner)
                           anchor-lifetime-fd
                           (isolated-cleanup-owner-anchor-lifetime-fd owner)
                           home (isolated-cleanup-owner-home owner)
                           delete-home-p
                           (isolated-cleanup-owner-delete-home-p owner)
                           release-started-p t
                           (isolated-cleanup-owner-state owner) :releasing
                           (isolated-cleanup-owner-completion-control-fd owner)
                           nil
                           (isolated-cleanup-owner-anchor-lifetime-fd owner) nil
                           (isolated-cleanup-owner-process owner) nil
                           (isolated-cleanup-owner-authority owner) nil)
                     (when (isolated-process-group-authority-p authority)
                       (setf
                        (isolated-process-group-authority-anchor-lifetime-fd
                         authority)
                        nil))
                     #+sb-thread
                     (sb-thread:condition-broadcast
                      *isolated-cleanup-registry-condition*)
                     t))))
             (remember-close-error (condition)
               (unless close-condition
                 (setf close-condition condition)))
             (close-completion-once ()
               (unless completion-close-attempted-p
                 (setf completion-close-attempted-p t)
                 (when completion-control-fd
                   (handler-case
                       (close-isolated-fd completion-control-fd)
                     (error (condition)
                       (remember-close-error condition))))))
             (close-anchor-once ()
               (unless anchor-close-attempted-p
                 (setf anchor-close-attempted-p t)
                 (when anchor-lifetime-fd
                   (handler-case
                       (close-isolated-fd anchor-lifetime-fd)
                     (error (condition)
                       (remember-close-error condition))))))
             (close-release-fds ()
               (unwind-protect
                   (close-completion-once)
                 (unless (eql anchor-lifetime-fd completion-control-fd)
                   (close-anchor-once))))
             (defer-release (condition)
               (let ((state
                       (defer-isolated-cleanup-owner owner condition)))
                 (when state
                   (setf release-completed-p t))
                 state))
             (finish-release ()
               (with-isolated-cleanup-registry-lock
                 (when (and (member owner *isolated-cleanup-registry*
                                    :test #'eq)
                            (eq (isolated-cleanup-owner-state owner)
                                :releasing))
                   (setf (isolated-cleanup-owner-home owner) nil
                         (isolated-cleanup-owner-state owner) :released
                         *isolated-cleanup-registry*
                         (delete owner *isolated-cleanup-registry* :test #'eq)
                         release-completed-p t)
                   #+sb-thread
                   (sb-thread:condition-broadcast
                    *isolated-cleanup-registry-condition*)
                   :released))))
      (unwind-protect
          (progn
            #+sb-thread
            (sb-sys:without-interrupts (begin-release))
            #-sb-thread
            (begin-release)
            (unless release-started-p
              (return-from release-isolated-cleanup-owner :not-running))
            #+sb-thread
            (sb-sys:without-interrupts (close-release-fds))
            #-sb-thread
            (close-release-fds)
            (handler-case
    (progn
      (when delete-home-p
        (delete-isolated-cleanup-home home))
      (if close-condition
          #+sb-thread
          (sb-sys:without-interrupts
            (defer-release close-condition))
          #-sb-thread
          (defer-release close-condition)
          #+sb-thread
          (sb-sys:without-interrupts (finish-release))
          #-sb-thread
          (finish-release)))
  (error (condition)
    #+sb-thread
    (sb-sys:without-interrupts (defer-release condition))
    #-sb-thread
    (defer-release condition))))
        (when (and release-started-p (not release-completed-p))
          #+sb-thread
          (sb-sys:without-interrupts
            (close-release-fds)
            (defer-release close-condition))
          #-sb-thread
          (progn
            (close-release-fds)
            (defer-release close-condition)))))))

(defun process-isolated-cleanup-owner (owner)
  (let* ((process (isolated-cleanup-owner-process owner))
         (authority (isolated-cleanup-owner-authority owner))
         (deadline
           (isolated-deadline
            (get-internal-real-time)
            +isolated-cleanup-attempt-seconds+)))
    (handler-case
        (let ((status
                (cond
                  ((null process) :reaped)
                  ((and (isolated-process-group-authority-p authority)
                        (eq (isolated-process-group-authority-state authority)
                            :scope-lost))
                   (if (eq
                        (wait-for-isolated-anchor-lifetime-exit
                         (isolated-cleanup-owner-anchor-lifetime-fd owner)
                         deadline)
                        :exited)
                       (reap-isolated-process process deadline)
                       :pending))
                  (t
                   (let ((terminate-status
                           (terminate-isolated-process
                            process authority
                            (isolated-cleanup-owner-parent-session-id owner)
                            deadline)))
                     (if (and (eq terminate-status :reaped)
                              (null authority))
                         (if (eq
                              (wait-for-isolated-anchor-lifetime-exit
                               (isolated-cleanup-owner-anchor-lifetime-fd owner)
                               deadline)
                              :exited)
                             :reaped
                             :pending)
                         terminate-status))))))
          (if (eq status :reaped)
              (release-isolated-cleanup-owner owner)
              (defer-isolated-cleanup-owner owner nil)))
      (error (condition)
        (defer-isolated-cleanup-owner owner condition)))))

(defun pump-isolated-cleanups ()
  (loop with processed-count = 0
        repeat +isolated-cleanup-claim-limit+
        do (let ((owner nil)
                 (processed-p nil))
             (unwind-protect
                 (progn
                   (claim-isolated-cleanup
                    (lambda (claimed-owner)
                      (setf owner claimed-owner)))
                   (unless owner
                     (return-from pump-isolated-cleanups processed-count))
                   (process-isolated-cleanup-owner owner)
                   (setf processed-p t)
                   (incf processed-count))
               (when (and owner (not processed-p))
                 #+sb-thread
                 (sb-sys:without-interrupts
                   (defer-isolated-cleanup-owner owner nil))
                 #-sb-thread
                 (defer-isolated-cleanup-owner owner nil))))
        finally (return processed-count)))

(defun isolated-cleanup-next-wait ()
  (let* ((now (isolated-cleanup-now))
         (next-times
           (loop for owner in *isolated-cleanup-registry*
                 when (member (isolated-cleanup-owner-state owner)
                              '(:ready :backoff :quarantined))
                   collect (isolated-cleanup-owner-next-at owner))))
    (if next-times
        (max 0 (- (reduce #'min next-times) now))
        1)))

#+sb-thread
(progn
  (defun wait-on-isolated-cleanup-condition (timeout)
    (sb-thread:condition-wait
     *isolated-cleanup-registry-condition*
     *isolated-cleanup-registry-mutex*
     :timeout timeout))

  (defun isolated-cleanup-worker-wait ()
    (unwind-protect
        (progn
          (sb-thread:grab-mutex *isolated-cleanup-registry-mutex*)
          (loop
            (when (some (lambda (owner)
                          (isolated-cleanup-claimable-p
                           owner (isolated-cleanup-now)))
                        *isolated-cleanup-registry*)
              (return))
            (wait-on-isolated-cleanup-condition
             (isolated-cleanup-next-wait))
            (unless (sb-thread:holding-mutex-p
                     *isolated-cleanup-registry-mutex*)
              (sb-thread:grab-mutex *isolated-cleanup-registry-mutex*))))
      (when (sb-thread:holding-mutex-p
             *isolated-cleanup-registry-mutex*)
        (sb-thread:release-mutex *isolated-cleanup-registry-mutex*)))))

#+sb-thread
(defun isolated-cleanup-worker-loop ()
  (loop
    (handler-case
        (progn
          (pump-isolated-cleanups)
          (isolated-cleanup-worker-wait))
      (error (condition)
        (warn "cl-weave isolated cleanup worker error: ~A" condition)
        (sleep 1)))))

(progn
  #+sb-thread
  (progn
    (defun isolated-cleanup-worker-alive-p (worker)
      (and worker
           (not (eq worker :starting))
           (sb-thread:thread-alive-p worker)))

    (defun make-isolated-cleanup-worker-thread (entrypoint)
      (sb-thread:make-thread
       entrypoint
       :name "cl-weave isolated cleanup worker"))

    (defun publish-isolated-cleanup-worker-candidate (candidate)
      (let ((notification-error nil))
        (with-isolated-cleanup-registry-lock
          (unless (eq *isolated-cleanup-worker* :starting)
            (error "Isolated cleanup worker startup reservation was lost."))
          (setf *isolated-cleanup-worker* candidate)
          (handler-case
              (sb-thread:condition-broadcast
               *isolated-cleanup-registry-condition*)
            (error (condition)
              (setf notification-error condition))))
        (when notification-error
          (warn
           "Unable to broadcast isolated cleanup worker publication: ~A"
           notification-error))
        candidate))

    (defun ensure-isolated-cleanup-worker ()
      (loop
        (let ((reserved-p nil)
              (wait-p nil)
              (existing-worker nil)
              (candidate nil)
              (candidate-action :abort)
              (candidate-gate (sb-thread:make-semaphore :count 0))
              (published-p nil)
              (fallback-scope nil))
          (handler-case
              (let ((result
                      (unwind-protect
                          (progn
                            (sb-sys:without-interrupts
                              (with-isolated-cleanup-registry-lock
                                (let ((worker *isolated-cleanup-worker*))
                                  (cond
                                    ((eq worker :starting)
                                     (setf wait-p t))
                                    ((isolated-cleanup-worker-alive-p worker)
                                     (setf existing-worker worker))
                                    (t
                                     (setf reserved-p t
                                           *isolated-cleanup-worker*
                                           :starting))))))
                            (cond
                              (existing-worker
                               existing-worker)
                              (wait-p
                               (sleep 0.001)
                               nil)
                              (t
                               (sb-sys:without-interrupts
                                 (setf candidate
                                       (make-isolated-cleanup-worker-thread
                                        (lambda ()
                                          (sb-thread:wait-on-semaphore
                                           candidate-gate)
                                          (when (eq candidate-action :run)
                                            (isolated-cleanup-worker-loop))))))
                               (publish-isolated-cleanup-worker-candidate
                                candidate))))
                        (when reserved-p
                          (sb-sys:without-interrupts
                            (with-isolated-cleanup-registry-lock
                              (setf published-p
                                    (and candidate
                                         (eq *isolated-cleanup-worker*
                                             candidate)))
                              (unless published-p
                                (when (eq *isolated-cleanup-worker* :starting)
                                  (setf *isolated-cleanup-worker* nil))
                                (setf fallback-scope
                                      (copy-list
                                       *isolated-cleanup-registry*))))
                            (when candidate
                              (setf candidate-action
                                    (if published-p :run :abort))
                              (sb-thread:signal-semaphore candidate-gate)))
                          (when (and candidate (not published-p))
                            (sb-thread:join-thread candidate))))))
                (cond
                  (existing-worker
                   (return existing-worker))
                  (wait-p)
                  (published-p
                   (return result))
                  (reserved-p
                   (error
                    "Isolated cleanup worker publication did not commit."))))
            (error (condition)
              (if (and reserved-p (not published-p))
                  (progn
                    (warn
                     "Unable to start isolated cleanup worker: ~A"
                     condition)
                    (sb-sys:without-interrupts (sb-sys:with-local-interrupts (let ((*isolated-cleanup-claim-scope* fallback-scope)) (pump-isolated-cleanups))))
                    (return nil))
                  (error condition))))))))

  #-sb-thread
  (defun ensure-isolated-cleanup-worker ()
    nil))

(defun activate-isolated-cleanup-owner (owner)
  (let ((registered-p nil))
    (unwind-protect
        (publish-isolated-cleanup-owner
         owner
         (lambda (registered-owner)
           (declare (ignore registered-owner))
           (setf registered-p t)))
      (when registered-p
        (handoff-isolated-cleanup-owner
         owner
         (isolated-cleanup-owner-authority owner)
         (isolated-cleanup-owner-delete-home-p owner)
         (lambda ()
           (setf registered-p nil)))))
    owner))

(defun isolated-cleanup-snapshots ()
  (with-isolated-cleanup-registry-lock
    (mapcar
     (lambda (owner)
       (list :id (isolated-cleanup-owner-id owner)
             :state (isolated-cleanup-owner-state owner)
             :attempts (isolated-cleanup-owner-attempts owner)
             :cleanup-pending-p
             (not (null (isolated-cleanup-owner-process owner)))
             :artifact-pending-p
             (not (null (isolated-cleanup-owner-home owner)))
             :last-error
             (let ((error (isolated-cleanup-owner-last-error owner)))
               (and error (copy-seq error)))))
     *isolated-cleanup-registry*)))

(defun drain-isolated-cleanups (&key (cycles 1))
  (loop repeat (min 8 (max 0 cycles))
        sum (pump-isolated-cleanups))))

  (defun isolated-cleanup-pending-status-p (status)
    (member
      status
      (list
        :cleanup-pending
        :timeout-cleanup-pending
        :output-limit-cleanup-pending
        :leader-exited-cleanup-pending)))

  (defun completed-isolated-cleanup-status (status)
    (case status
      (:cleanup-pending :finished)
      (:timeout-cleanup-pending :timeout)
      (:output-limit-cleanup-pending :output-limit)
      (:leader-exited-cleanup-pending :leader-exited)
      (t status)))

  (defun retry-isolated-process-cleanup
    (process process-group-authority parent-session-id deadline)
  (loop
    with cleanup-status = :pending
    for attempt from 1 to +isolated-cleanup-retry-count+
    do
       (setf cleanup-status
             (terminate-isolated-process
              process process-group-authority parent-session-id deadline))
       (when (eq cleanup-status :reaped)
         (return :reaped))
       (when (and (< attempt +isolated-cleanup-retry-count+)
                  (not (isolated-deadline-expired-p deadline)))
         (isolated-sleep-before-deadline 0.01 deadline))
    finally (return cleanup-status)))

(progn
  (defconstant +isolated-stream-drain-quantum+ (* 64 1024))
  (defconstant +isolated-stream-final-drain-quantum+ (* 4 1024))
  (defconstant +isolated-stream-final-drain-seconds+ 0.1))
(defun drain-isolated-stream
    (input output
     &optional (maximum-characters +isolated-stream-drain-quantum+))
  (loop with count = 0
        repeat maximum-characters
        for character = (read-char-no-hang input nil :eof)
        do (cond
             ((eq character :eof)
              (return (values t count)))
             ((null character)
              (return (values nil count)))
             (t
              (write-char character output)
              (incf count)))
        finally (return (values nil count))))

(defun drain-isolated-streams-available
    (stdout-stream stdout-output stderr-stream stderr-output)
  (let ((deadline
          (isolated-deadline
           (get-internal-real-time)
           +isolated-stream-final-drain-seconds+))
        (stdout-eof-p (null stdout-stream))
        (stderr-eof-p (null stderr-stream)))
    (loop until (and stdout-eof-p stderr-eof-p)
          while (not (isolated-deadline-expired-p deadline))
          do
             (let ((progress 0))
               (unless stdout-eof-p
                 (multiple-value-bind (eof-p count)
                     (drain-isolated-stream
                      stdout-stream stdout-output
                      +isolated-stream-final-drain-quantum+)
                   (setf stdout-eof-p eof-p)
                   (incf progress count)))
               (unless stderr-eof-p
                 (multiple-value-bind (eof-p count)
                     (drain-isolated-stream
                      stderr-stream stderr-output
                      +isolated-stream-final-drain-quantum+)
                   (setf stderr-eof-p eof-p)
                   (incf progress count)))
               (when (and (zerop progress)
                          (not (and stdout-eof-p stderr-eof-p)))
                 (isolated-sleep-before-deadline 0.001 deadline)))
          finally (return (values stdout-eof-p stderr-eof-p)))))

(defun wait-isolated-process
    (process deadline ready anchor-control-fd completion-control-fd
     anchor-lifetime-fd parent-session-id stdout-stream stderr-stream
     stdout-output stderr-output
     &optional (process-group-authority-cell (list nil)))
  (let ((anchor-frame (make-isolated-control-frame 32))
        (completion-frame (make-isolated-control-frame 2))
        (anchor-pid nil)
        (drained-quantum-p nil))
    (labels ((authority ()
               (car process-group-authority-cell))
             (drain-once ()
               (multiple-value-bind (stdout-eof-p stdout-count)
                   (drain-isolated-stream stdout-stream stdout-output)
                 (declare (ignore stdout-eof-p))
                 (multiple-value-bind (stderr-eof-p stderr-count)
                     (drain-isolated-stream stderr-stream stderr-output)
                   (declare (ignore stderr-eof-p))
                   (or (= stdout-count +isolated-stream-drain-quantum+)
                       (= stderr-count +isolated-stream-drain-quantum+)))))
             (finish-draining ()
               (drain-isolated-streams-available
                stdout-stream stdout-output stderr-stream stderr-output))
             (pending-status (status)
               (case status
                 (:timeout :timeout-cleanup-pending)
                 (:output-limit :output-limit-cleanup-pending)
                 (:leader-exited :leader-exited-cleanup-pending)
                 (t :cleanup-pending)))
             (terminate (status &optional logical-exit-code)
 (let* ((authority-value (authority))
        (reap-status
         (terminate-isolated-process
          process authority-value parent-session-id deadline))
        (cleanup-status
         (if (and (eq reap-status :reaped) (null authority-value))
             (if (eq (wait-for-isolated-anchor-lifetime-exit
                      anchor-lifetime-fd
                      (isolated-deadline
                       (get-internal-real-time)
                       (+ +isolated-process-group-term-wait-seconds+
                          +isolated-process-group-kill-wait-seconds+)))
                     :exited)
                 :reaped
                 :pending)
             reap-status)))
   (when (eq cleanup-status :reaped)
     (finish-draining))
   (values
    (if (eq cleanup-status :reaped)
        status
        (pending-status status))
    (or logical-exit-code
        (and (eq cleanup-status :reaped)
             (sb-ext:process-exit-code process)))
    (eq cleanup-status :reaped)
    authority-value))))
      (loop
        (unless anchor-pid
          (multiple-value-bind (published-pid publication-status)
              (isolated-anchor-frame-pid anchor-control-fd anchor-frame)
            (case publication-status
              (:complete
               (setf anchor-pid published-pid))
              (:invalid
               (return (terminate :leader-exited 1))))))
        (unless (authority)
          (when anchor-pid
            (acknowledge-isolated-process-group
             process ready anchor-pid anchor-lifetime-fd parent-session-id
             process-group-authority-cell)))
        (setf drained-quantum-p (drain-once))
        (multiple-value-bind (completion-code completion-status)
            (isolated-completion-frame-code
             completion-control-fd completion-frame)
          (case completion-status
            (:complete
             (when (authority)
               (return (terminate :finished completion-code))))
            (:invalid
             (return (terminate :leader-exited 1)))))
        (when (and anchor-pid
                   (not (authority))
                   (not (isolated-anchor-lifetime-valid-p
                         anchor-lifetime-fd)))
          (return (terminate :leader-exited 1)))
        (unless (or (authority)
                    (isolated-process-alive-p process))
          (return (terminate :leader-exited 1)))
        (let ((status
                (cond
                  ((or
                    (isolated-capped-output-stream-truncated-p stdout-output)
                    (isolated-capped-output-stream-truncated-p stderr-output))
                   :output-limit)
                  ((isolated-deadline-expired-p deadline) :timeout))))
          (when status
            (return (terminate status))))
        (unless drained-quantum-p
          (isolated-sleep-before-deadline 0.01 deadline))))))

#+

sbcl

(defun run-isolated (form
    &key
    (systems (quote ("cl-weave")))
    (package (package-name *package*))
    (timeout *isolated-timeout-seconds*)
    (max-output-bytes *isolated-max-output-bytes*)
    keep-files)
  (let ((started (get-internal-real-time)))
    (unless
        (and
         (realp timeout)
         (handler-case
             (and (plusp timeout)
                  (or (rationalp timeout)
                      (and
                       (not (sb-ext:float-infinity-p timeout))
                       (not (sb-ext:float-nan-p timeout)))))
           (arithmetic-error () nil)
           (error () nil)))
      (error "cl-weave: isolated timeout must be a positive finite real number."))
    (unless (and (integerp max-output-bytes) (plusp max-output-bytes))
      (error
       "cl-weave: isolated max-output-bytes must be a positive integer, got ~S."
       max-output-bytes))
    (require :sb-posix)
    (let* ((deadline (isolated-deadline started timeout))
           (systems (normalize-isolated-systems systems))
           (keep-files (normalize-isolated-keep-files keep-files))
           (home (isolated-temp-directory "cl-weave-isolated"))
           (anchor-control-pipe (multiple-value-list (sb-posix:pipe)))
           (completion-control-pipe (multiple-value-list (sb-posix:pipe)))
           (anchor-lifetime-pipe (multiple-value-list (sb-posix:pipe)))
           (anchor-control-read-fd (first anchor-control-pipe))
           (anchor-control-write-fd (second anchor-control-pipe))
           (completion-control-read-fd (first completion-control-pipe))
           (completion-control-write-fd (second completion-control-pipe))
           (anchor-lifetime-read-fd (first anchor-lifetime-pipe))
           (anchor-lifetime-write-fd (second anchor-lifetime-pipe))
           (parent-session-id
             (funcall
              (symbol-function (find-symbol "GETSID" "SB-POSIX")) 0))
           (process-group-authority-cell (list nil))
           (retain-files (isolated-retain-files-p keep-files :fail))
           (process nil)
           (cleanup-owner nil)
           (cleanup-transferred-p nil)
           result)
      (configure-isolated-control-read-fd anchor-control-read-fd)
      (configure-isolated-control-read-fd completion-control-read-fd)
      (configure-isolated-control-read-fd anchor-lifetime-read-fd)
      (unwind-protect
          (let* ((script (isolated-temp-pathname home "script" "lisp"))
                 (worker (isolated-temp-pathname home "worker" "lisp"))
                 (stdout (isolated-temp-pathname home "stdout" "out"))
                 (stderr (isolated-temp-pathname home "stderr" "err"))
                 (ready (merge-pathnames #p"ready" home))
                 (marker (merge-pathnames #p"worker-completion" home))
                 wait-status
                 exit-code
                 cleanup-complete-p
                 stdout-truncated-p
                 stderr-truncated-p)
            (write-isolated-worker-script worker marker form systems package)
            (write-isolated-script
             script worker ready marker anchor-control-write-fd
             completion-control-write-fd anchor-lifetime-write-fd)
            (with-open-file (stdout-file
                             stdout
                             :direction :output
                             :if-exists :supersede
                             :element-type (quote (unsigned-byte 8)))
              (with-open-file (stderr-file
                               stderr
                               :direction :output
                               :if-exists :supersede
                               :element-type (quote (unsigned-byte 8)))
                (let* ((output-budget
                         (make-isolated-output-budget
                          :maximum-bytes max-output-bytes))
                       (stdout-output
                         (make-instance
                          (quote isolated-capped-output-stream)
                          :stream stdout-file
                          :budget output-budget))
                       (stderr-output
                         (make-instance
                          (quote isolated-capped-output-stream)
                          :stream stderr-file
                          :budget output-budget))
                       (stdout-stream nil)
                       (stderr-stream nil))
                  (setf process
                        (sb-ext:run-program
                         (isolated-sbcl-program)
                         (list "--script" (namestring script))
                         :search t
                         :wait nil
                         :input nil
                         :output :stream
                         :error :stream
                         :external-format :latin-1
                         :environment (isolated-process-environment home)
                         :preserve-fds
                         (list anchor-control-write-fd
                               completion-control-write-fd
                               anchor-lifetime-write-fd)))
                  (close-isolated-fd anchor-control-write-fd)
                  (close-isolated-fd completion-control-write-fd)
                  (close-isolated-fd anchor-lifetime-write-fd)
                  (progn
  (setf anchor-control-write-fd nil
        completion-control-write-fd nil
        anchor-lifetime-write-fd nil)
  (publish-isolated-cleanup-owner
   (make-isolated-cleanup-owner
    :process process
    :parent-session-id parent-session-id
    :home home
    :delete-home-p t
    :completion-control-fd completion-control-read-fd
    :anchor-lifetime-fd anchor-lifetime-read-fd
    :state :held)
   (lambda (registered-owner)
     (setf cleanup-owner registered-owner))))
                  cleanup-owner
                  (unwind-protect
                      (progn
                        (setf stdout-stream
                              (isolated-process-output-stream process)
                              stderr-stream
                              (isolated-process-error-stream process))
                        (multiple-value-setq
                            (wait-status exit-code cleanup-complete-p)
                          (wait-isolated-process
                           process deadline ready anchor-control-read-fd
                           completion-control-read-fd anchor-lifetime-read-fd
                           parent-session-id stdout-stream stderr-stream
                           stdout-output stderr-output
                           process-group-authority-cell))
                        (when cleanup-complete-p
                          (setf process nil))
                        (setf stdout-truncated-p
                              (isolated-capped-output-stream-truncated-p
                               stdout-output)
                              stderr-truncated-p
                              (isolated-capped-output-stream-truncated-p
                               stderr-output)))
                    (when process
                      (let* ((authority-value
                               (car process-group-authority-cell))
                             (reap-status
                               (ignore-errors
                                (retry-isolated-process-cleanup
                                 process authority-value parent-session-id
                                 deadline)))
                             (cleanup-status
                               (if (and (eq reap-status :reaped)
                                        (null authority-value))
                                   (if
                                    (eq
                                     (wait-for-isolated-anchor-lifetime-exit
                                      anchor-lifetime-read-fd
                                      (isolated-deadline
                                       (get-internal-real-time)
                                       (+
                                        +isolated-process-group-term-wait-seconds+
                                        +isolated-process-group-kill-wait-seconds+)))
                                     :exited)
                                    :reaped
                                    :pending)
                                   reap-status)))
                        (when (eq cleanup-status :reaped)
                          (drain-isolated-streams-available
                           stdout-stream stdout-output
                           stderr-stream stderr-output)
                          (setf cleanup-complete-p t
                                process nil
                                wait-status
                                (completed-isolated-cleanup-status
                                 wait-status)))))
                    (when stdout-stream
                      (ignore-errors (close stdout-stream)))
                    (when stderr-stream
                      (ignore-errors (close stderr-stream))))
                  (when (null process)
                    (discard-held-isolated-cleanup-owner cleanup-owner)
                    (setf cleanup-owner nil))
                  (finish-output stdout-file)
                  (finish-output stderr-file))))
            (let* ((elapsed-ms
                     (/ (* 1000 (- (get-internal-real-time) started))
                        internal-time-units-per-second))
                   (output-limit-exceeded-p
                     (or stdout-truncated-p stderr-truncated-p))
                   (status
                     (cond
                       ((member wait-status
                                (list :timeout :timeout-cleanup-pending))
                        :timeout)
                       (output-limit-exceeded-p :fail)
                       ((and (eq wait-status :finished)
                             (eql exit-code 0))
                        :pass)
                       (t :fail))))
              (setf retain-files
                    (isolated-retain-files-p keep-files status)
                    result
                    (make-isolated-result
                     :status status
                     :exit-code exit-code
                     :stdout (read-isolated-output stdout)
                     :stderr
                     (format nil
                             "~A~:[~;~%cl-weave: isolated cleanup incomplete; child process may still be running and final output may be incomplete.~%~]"
                             (read-isolated-output stderr)
                             (isolated-cleanup-pending-status-p wait-status))
                     :timed-out-p
                     (not
                      (null
                       (member wait-status
                               (list :timeout :timeout-cleanup-pending))))
                     :stdout-truncated-p stdout-truncated-p
                     :stderr-truncated-p stderr-truncated-p
                     :output-limit-exceeded-p output-limit-exceeded-p
                     :elapsed-ms elapsed-ms
                     :script-path (maybe-path-namestring script retain-files)
                     :stdout-path (maybe-path-namestring stdout retain-files)
                     :stderr-path (maybe-path-namestring stderr retain-files)
                     :home-path (maybe-path-namestring home retain-files)))
              (when (and process cleanup-owner)
                (handoff-isolated-cleanup-owner
                 cleanup-owner
                 (car process-group-authority-cell)
                 (not retain-files)
                 (lambda ()
                   (setf process nil
                         completion-control-read-fd nil
                         anchor-lifetime-read-fd nil
                         (car process-group-authority-cell) nil
                         cleanup-transferred-p t))))
              result))
        (when process
          (unless cleanup-owner
  (publish-isolated-cleanup-owner
   (make-isolated-cleanup-owner
    :process process
    :parent-session-id parent-session-id
    :home home
    :delete-home-p (not retain-files)
    :completion-control-fd completion-control-read-fd
    :anchor-lifetime-fd anchor-lifetime-read-fd
    :state :held)
   (lambda (registered-owner)
     (setf cleanup-owner registered-owner))))
          (handoff-isolated-cleanup-owner
           cleanup-owner
           (car process-group-authority-cell)
           (not retain-files)
           (lambda ()
             (setf process nil
                   completion-control-read-fd nil
                   anchor-lifetime-read-fd nil
                   (car process-group-authority-cell) nil
                   cleanup-transferred-p t))))
        (when (and cleanup-owner (null process))
          (discard-held-isolated-cleanup-owner cleanup-owner)
          (setf cleanup-owner nil))
        (close-isolated-fd anchor-control-read-fd)
        (close-isolated-fd anchor-control-write-fd)
        (close-isolated-fd completion-control-read-fd)
        (close-isolated-fd completion-control-write-fd)
        (close-isolated-fd anchor-lifetime-read-fd)
        (close-isolated-fd anchor-lifetime-write-fd)
        (unless (or retain-files cleanup-transferred-p)
          (ignore-errors
           (uiop:delete-directory-tree
            home
            :validate t
            :if-does-not-exist :ignore)))))))

#-

sbcl

(defun run-isolated (form &key systems package timeout max-output-bytes keep-files)
  (declare (ignore form systems package timeout max-output-bytes keep-files))
  (error "cl-weave: run-isolated currently requires SBCL."))

(defun signal-isolated-failure (result form)
  (signal-assertion-failure
    (make-assertion-detail
      :form
      form
      :matcher
      :isolated
      :actual
      (list
        :status
        (isolated-result-status result)
        :exit-code
        (isolated-result-exit-code result)
        :timed-out-p
        (isolated-result-timed-out-p result)
        :stdout-truncated-p
        (isolated-result-stdout-truncated-p result)
        :stderr-truncated-p
        (isolated-result-stderr-truncated-p result)
        :output-limit-exceeded-p
        (isolated-result-output-limit-exceeded-p result)
        :elapsed-ms
        (isolated-result-elapsed-ms result)
        :stdout
        (isolated-result-stdout result)
        :stderr
        (isolated-result-stderr result)
        :script-path
        (isolated-result-script-path result)
        :stdout-path
        (isolated-result-stdout-path result)
        :stderr-path
        (isolated-result-stderr-path result)
        :home-path
        (isolated-result-home-path result))
      :expected
      '(:status :pass :exit-code 0)
      :negated
      nil
      :pass
      nil)))
