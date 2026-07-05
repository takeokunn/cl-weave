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

(defun read-text-file (pathname)
  (with-open-file (stream pathname :direction :input)
    (let ((contents (make-string (file-length stream))))
      (read-sequence contents stream)
      contents)))

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

