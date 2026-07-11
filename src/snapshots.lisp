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

(defun snapshot-entry (key entries)
  (assoc key entries :test #'string=))

(defun snapshot-entries ()
  (copy-tree (read-snapshot-file)))

(defun snapshot-value (key)
  (unless (stringp key)
    (error "cl-weave:snapshot-value expects a string snapshot key."))
  (let ((entry (snapshot-entry key (read-snapshot-file))))
    (if entry
        (values (cdr entry) t)
        (values nil nil))))

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

(defun snapshot-sequence-prefix-from-expected (expected)
  (unless (= (length expected) 1)
    (error "Matcher :to-match-snapshot-sequence expects exactly one string snapshot key prefix, got ~D values."
           (length expected)))
  (let ((prefix (first expected)))
    (unless (stringp prefix)
      (error "Matcher :to-match-snapshot-sequence expects a string snapshot key prefix."))
    prefix))

(defun snapshot-sequence-values (actual)
  (typecase actual
    (list actual)
    ((and vector (not string))
     (coerce actual 'list))
    (t
     (error "Matcher :to-match-snapshot-sequence expects a list or non-string vector of states, got ~S."
            actual))))

(defun snapshot-sequence-key (prefix index)
  (format nil "~A[~D]" prefix index))

(defun snapshot-sequence-key-index (prefix key)
  (when (stringp key)
    (let* ((prefix-length (length prefix))
           (key-length (length key)))
      (when (and (> key-length (+ prefix-length 2))
                 (string= key prefix :end1 prefix-length :end2 prefix-length)
                 (char= (char key prefix-length) #\[)
                 (char= (char key (1- key-length)) #\]))
        (let ((index 0))
          (loop for position from (1+ prefix-length) below (1- key-length)
                for digit = (digit-char-p (char key position) 10)
                unless digit
                  do (return nil)
                do (setf index (+ (* index 10) digit))
                finally (return index)))))))

(defun snapshot-sequence-entry-p (prefix entry)
  (and (consp entry)
       (snapshot-sequence-key-index prefix (car entry))))

(defun remove-snapshot-sequence-entries (prefix entries)
  (remove-if (lambda (entry)
               (snapshot-sequence-entry-p prefix entry))
             entries))

(defun snapshot-sequence-context-values (actual expected prefix index count)
  (values (append actual
                  (list :snapshot-prefix prefix
                        :snapshot-index index
                        :snapshot-count count))
          (append expected
                  (list :snapshot-prefix prefix
                        :snapshot-index index
                        :snapshot-count count))))

(defun snapshot-sequence-extra-values (prefix index count entry)
  (let ((file (namestring (snapshot-file-pathname))))
    (values (list :snapshot-prefix prefix
                  :snapshot-key (car entry)
                  :snapshot-file file
                  :snapshot-index index
                  :snapshot-count count
                  :value nil
                  :present nil
                  :reason :unexpected-snapshot)
            (list :snapshot-prefix prefix
                  :snapshot-key (car entry)
                  :snapshot-file file
                  :snapshot-index index
                  :snapshot-count count
                  :value (cdr entry)
                  :present t
                  :reason :unexpected-snapshot))))

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

(defun snapshot-sequence-match-or-update-p (actual expected)
  (let* ((prefix (snapshot-sequence-prefix-from-expected expected))
         (values (snapshot-sequence-values actual))
         (count (length values))
         (entries (read-snapshot-file)))
    (if (snapshot-update-enabled-p)
        (let ((next-entries (remove-snapshot-sequence-entries prefix entries)))
          (loop for value in values
                for index from 0
                do (setf next-entries
                         (replace-snapshot-entry
                          (snapshot-sequence-key prefix index)
                          (snapshot-string value)
                          next-entries)))
          (write-snapshot-file next-entries)
          t)
        (loop for value in values
              for index from 0
              for key = (snapshot-sequence-key prefix index)
              for actual-string = (snapshot-string value)
              for entry = (snapshot-entry key entries)
              unless (and entry (string= actual-string (cdr entry)))
                do (multiple-value-bind (reported-actual reported-expected)
                       (snapshot-comparison-values key actual-string entry)
                     (multiple-value-bind (sequence-actual sequence-expected)
                         (snapshot-sequence-context-values
                          reported-actual reported-expected prefix index count)
                       (return (values nil sequence-actual sequence-expected))))
              finally
                 (let ((extra-entry
                         (find-if (lambda (entry)
                                    (let ((index (and (consp entry)
                                                      (snapshot-sequence-key-index
                                                       prefix
                                                       (car entry)))))
                                      (and index (>= index count))))
                                  entries)))
                   (if extra-entry
                       (let ((extra-index
                               (snapshot-sequence-key-index prefix (car extra-entry))))
                         (multiple-value-bind (reported-actual reported-expected)
                             (snapshot-sequence-extra-values
                              prefix extra-index count extra-entry)
                           (return (values nil reported-actual reported-expected))))
                       (return t)))))))
