(in-package #:cl-weave/tests)

(cl-weave:clear-tests)

(defun ensure-directory-suffix (value)
  (let ((string (namestring (pathname value))))
    (if (and (plusp (length string))
             (char= (char string (1- (length string))) #\/))
        string
        (concatenate 'string string "/"))))

(defun usable-temporary-root-p (value)
  (and value
       (plusp (length value))
       (not (search "/homeless-shelter" value))))

(defun test-temporary-root ()
  (let* ((tmp #+sbcl (sb-ext:posix-getenv "TMPDIR")
              #-sbcl nil)
         (nix-build-top #+sbcl (sb-ext:posix-getenv "NIX_BUILD_TOP")
                        #-sbcl nil)
         (pwd #+sbcl (sb-ext:posix-getenv "PWD")
              #-sbcl nil)
         (cwd (ignore-errors (namestring (uiop:getcwd))))
         (root (find-if #'usable-temporary-root-p
                        (list nix-build-top pwd tmp cwd))))
    (unless root
      (error "No usable temporary root is available."))
    (pathname (ensure-directory-suffix root))))

(defun test-snapshot-directory (name)
  (merge-pathnames
   (make-pathname :directory (list :relative name))
   (test-temporary-root)))

(defun test-temporary-pathname (name)
  (merge-pathnames
   name
   (test-temporary-root)))

(defun make-test-temporary-directory (prefix)
  (loop repeat 100
        for directory = (merge-pathnames
                         (make-pathname
                          :directory
                          (list :relative
                                (format nil "~A-~36R-~36R"
                                        prefix
                                        (get-universal-time)
                                        (random (expt 36 6)))))
                         (test-temporary-root))
        unless (probe-file directory)
          do (ensure-directories-exist (merge-pathnames #P".keep" directory))
             (return directory)
        finally (error "Failed to allocate test temporary directory for ~A." prefix)))

(defun read-text-file (pathname)
  (with-open-file (stream pathname :direction :input)
    (let ((contents (make-string (file-length stream))))
      (read-sequence contents stream)
      contents)))

(defun normalize-shell-text (text)
  (with-output-to-string (stream)
    (loop with spacing = t
          for character across text
          do (cond
               ((char= character #\')
                nil)
               ((member character '(#\Newline #\Tab #\Return #\Space))
                (unless spacing
                  (write-char #\Space stream)
                  (setf spacing t)))
               (t
                (write-char character stream)
                (setf spacing nil))))))

(defun normalize-markdown-text (text)
  (labels ((collapse-markdown-spacing ()
             (with-output-to-string (stream)
               (loop with spacing = t
                     for character across text
                     do (cond
                          ((member character '(#\` #\Newline #\Tab #\Return #\Space))
                           (unless spacing
                             (write-char #\Space stream)
                             (setf spacing t)))
                          (t
                           (write-char character stream)
                           (setf spacing nil))))))
           (tight-punctuation-p (character)
             (member character '(#\, #\. #\: #\; #\) #\]))))
    (let* ((collapsed (string-trim '(#\Space)
                                   (collapse-markdown-spacing))))
      (with-output-to-string (stream)
        (loop for index from 0 below (length collapsed)
              for character = (char collapsed index)
              for next = (and (< (1+ index) (length collapsed))
                              (char collapsed (1+ index)))
              unless (and (char= character #\Space)
                          next
                          (tight-punctuation-p next))
                do (write-char character stream))))))

(defun workflow-command-string (command)
  (format nil "~{~A~^ ~}" command))

(defun normalize-command-document-text (text)
  (with-output-to-string (stream)
    (loop with spacing = t
          for character across text
          do (cond
               ((member character '(#\` #\Newline #\Tab #\Return #\Space))
                (unless spacing
                  (write-char #\Space stream)
                  (setf spacing t)))
               (t
                (write-char character stream)
                (setf spacing nil))))))

(defun split-normalized-words (text)
  (remove ""
          (uiop:split-string text :separator '(#\Space))
          :test #'string=))

(defun ordered-word-subsequence-p (needle haystack)
  (loop with haystack-length = (length haystack)
        with position = 0
        for word in needle
        do (loop while (and (< position haystack-length)
                            (not (string= word (nth position haystack))))
                 do (incf position))
           (when (>= position haystack-length)
             (return-from ordered-word-subsequence-p nil))
           (incf position)
        finally (return t)))

(defun markdown-contains-command-p (markdown command)
  (ordered-word-subsequence-p
   (split-normalized-words
    (normalize-shell-text (workflow-command-string command)))
   (split-normalized-words
    (normalize-command-document-text markdown))))

(defvar *fixture-value* nil)
(defvar *fixture-events* nil)
(defun sample-size (value) (length value))

(defclass sample-widget ()
  ((name :initarg :name :reader sample-widget-name)
   (state :initarg :state :initform :new :reader sample-widget-state)))

(defgeneric render-widget (widget stream))

(defmethod render-widget ((widget sample-widget) stream)
  (declare (ignore stream))
  (sample-widget-name widget))

(defgeneric render-widget-mode (mode stream))

(defmethod render-widget-mode ((mode (eql :preview)) stream)
  (declare (ignore stream))
  mode)

(defmethod render-widget-mode ((mode sample-widget) stream)
  (declare (ignore stream))
  (sample-widget-name mode))

(defmacro sample-unless (condition &body body)
  `(if ,condition
       nil
       (progn ,@body)))

(defmacro matcher-pass-cases (&body cases)
  `(progn
     ,@(loop for (name form) in cases
             collect `(it ,name ,form))))

(defun tree-contains-p (tree value)
  (cond
    ((equal tree value) t)
    ((consp tree)
     (or (tree-contains-p (car tree) value)
         (tree-contains-p (cdr tree) value)))
    (t nil)))

(defmacro expect-macroexpands-through (form canonical-symbol)
  `(expect (macroexpand-1 ',form)
           :to-satisfy
           (lambda (expanded)
             (tree-contains-p expanded ',canonical-symbol))))

#+sbcl
(defun quiet-nan ()
  (sb-kernel:make-double-float #x7ff80000 0))

(defun tree-depth (tree)
  (if (consp tree)
      (1+ (reduce #'max tree :key #'tree-depth :initial-value 0))
      0))

(defmatcher :to-be-even (actual expected)
  "Passes when ACTUAL is an even integer."
  (declare (ignore expected))
  (values (and (integerp actual) (evenp actual))
          `(:value ,actual :parity ,(if (and (integerp actual) (evenp actual))
                                        :even
                                        :odd))
          '(:parity :even)))

(expect.extend
  (:to-be-odd (actual expected)
    "Passes when ACTUAL is an odd integer."
    (declare (ignore expected))
    (values (and (integerp actual) (oddp actual))
            `(:value ,actual :parity ,(if (and (integerp actual) (oddp actual))
                                          :odd
                                          :even))
            '(:parity :odd))))

(extend-expect
  (list
  (list :to-be-between
        (lambda (actual expected)
          (destructuring-bind (low high) expected
            (values (and (realp actual) (<= low actual high))
                    `(:value ,actual :range (,low ,high))
                    `(:range (,low ,high)))))
        :description
        "Passes when ACTUAL is within the inclusive numeric range.")))
