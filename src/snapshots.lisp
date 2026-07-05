(in-package #:cl-weave)

(defvar *snapshot-directory* #P"__snapshots__/")
(defvar *snapshot-file-name* "snapshots.sexp")
(defvar *update-snapshots* nil)

(defun snapshot-string (value)
  (let ((*print-case* :downcase)
        (*print-circle* t)
        (*print-length* nil)
        (*print-level* nil)
        (*print-pretty* nil))
    (write-to-string value :escape t :readably nil)))

(defun snapshot-file-pathname ()
  (merge-pathnames *snapshot-file-name* *snapshot-directory*))

(defun snapshot-line-list (string)
  (with-input-from-string (stream string)
    (loop for line = (read-line stream nil nil)
          while line
          collect line)))

(defun snapshot-first-difference (expected actual)
  (let* ((expected-lines (snapshot-line-list expected))
         (actual-lines (snapshot-line-list actual))
         (line-count (max (length expected-lines) (length actual-lines))))
    (loop for offset below line-count
          for expected-line = (nth offset expected-lines)
          for actual-line = (nth offset actual-lines)
          unless (equal expected-line actual-line)
            return (list :line (1+ offset)
                         :expected expected-line
                         :actual actual-line))))

(defun snapshot-comparison-values (key actual-string entry)
  (let* ((file (namestring (snapshot-file-pathname)))
         (expected-present-p (not (null entry)))
         (expected-string (and entry (cdr entry)))
         (difference (when expected-present-p
                       (snapshot-first-difference expected-string actual-string)))
         (reason (if expected-present-p
                     :snapshot-mismatch
                     :missing-snapshot)))
    (values (list :snapshot-key key
                  :snapshot-file file
                  :value actual-string
                  :reason reason
                  :difference difference)
            (list :snapshot-key key
                  :snapshot-file file
                  :value expected-string
                  :present expected-present-p
                  :reason reason
                  :difference difference))))

(defun read-snapshot-file ()
  (let ((file (snapshot-file-pathname)))
    (when (probe-file file)
      (with-open-file (stream file :direction :input)
        (let ((*read-eval* nil))
          (read stream nil nil))))))

(defun write-snapshot-file (entries)
  (let ((file (snapshot-file-pathname)))
    (ensure-directories-exist file)
    (with-open-file (stream file
                            :direction :output
                            :if-exists :supersede
                            :if-does-not-exist :create)
      (let ((*print-case* :downcase)
            (*print-circle* t)
            (*print-pretty* t))
        (prin1 entries stream)
        (terpri stream)))))

(defun snapshot-entry (key entries)
  (assoc key entries :test #'string=))

(defun replace-snapshot-entry (key value entries)
  (let ((entry (snapshot-entry key entries)))
    (if entry
        (progn
          (setf (cdr entry) value)
          entries)
        (append entries (list (cons key value))))))

(defun snapshot-update-token-p (value)
  (member (string-downcase value)
          '("1" "true" "yes" "update")
          :test #'string=))

(defun snapshot-update-enabled-p ()
  (or *update-snapshots*
      #+sbcl
      (let ((value (sb-ext:posix-getenv "CL_WEAVE_UPDATE_SNAPSHOTS")))
        (and value (snapshot-update-token-p value)))
      #-sbcl
      nil))

(defun snapshot-key-from-expected (expected)
  (unless (= (length expected) 1)
    (error "Matcher :to-match-snapshot expects exactly one string snapshot key, got ~D values."
           (length expected)))
  (let ((key (first expected)))
    (unless (stringp key)
      (error "Matcher :to-match-snapshot expects a string snapshot key."))
    key))

(defun snapshot-match-or-update-p (actual expected)
  (let* ((key (snapshot-key-from-expected expected))
         (actual-string (snapshot-string actual))
         (entries (read-snapshot-file))
         (entry (snapshot-entry key entries)))
    (cond
      ((and entry (string= actual-string (cdr entry))) t)
      ((snapshot-update-enabled-p)
       (write-snapshot-file
        (replace-snapshot-entry key actual-string entries))
       t)
      (t
       (multiple-value-bind (reported-actual reported-expected)
           (snapshot-comparison-values key actual-string entry)
         (values nil reported-actual reported-expected))))))
