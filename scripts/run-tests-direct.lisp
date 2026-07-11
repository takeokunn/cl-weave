(require :asdf)

(defun direct-project-root ()
  (truename
   (make-pathname :directory (butlast (pathname-directory *load-truename*))
                  :name nil
                  :type nil
                  :defaults *load-truename*)))

(defun direct-read-system-components (asd-path system-name)
  (with-open-file (stream asd-path :direction :input)
    (loop for form = (read stream nil nil)
          while form
          when (and (consp form)
                    (string-equal (symbol-name (first form)) "DEFSYSTEM")
                    (string-equal (string (second form)) system-name))
            return (getf (cddr form) :components)
          finally (error "cl-weave: system ~A was not found in ~A."
                         system-name asd-path))))

(defun direct-component-paths (components base)
  (loop for component in components
        for kind = (first component)
        for name = (second component)
        append
        (cond
          ((eq kind :file)
           (list (merge-pathnames (make-pathname :name name :type "lisp") base)))
          ((eq kind :module)
           (direct-component-paths
            (getf (cddr component) :components)
            (merge-pathnames (make-pathname :directory `(:relative ,name)) base)))
          (t
           (error "cl-weave: unsupported direct-load component ~S." component)))))

(defun direct-coverage-requested-p ()
  #+sbcl
  (let ((value (sb-ext:posix-getenv "CL_WEAVE_COVERAGE")))
    (and value
         (not (member value '("" "0" "false" "no" "off" "nil")
                      :test #'string-equal))))
  #-sbcl
  nil)

(defun direct-enable-coverage-compilation ()
  #+sbcl
  (when (direct-coverage-requested-p)
    (require :sb-cover)
    (let* ((package (or (find-package :sb-cover)
                        (error "SB-COVER package is unavailable after REQUIRE.")))
           (quality (or (find-symbol "STORE-COVERAGE-DATA" package)
                        (error "SB-COVER:STORE-COVERAGE-DATA is unavailable."))))
      (proclaim (list 'optimize (list quality 3)))))
  #-sbcl
  nil)

(defun direct-load-source (source)
  (format *error-output* "cl-weave: direct loading ~A~%" source)
  (with-open-file (stream source :direction :input)
    (let ((*load-pathname* source)
          (*load-truename* (truename source)))
      (loop for index from 1
            for form = (read stream nil stream)
            until (eq form stream)
            do (format *error-output* "cl-weave: evaluating ~A form ~D~%"
                       source index)
               (eval form)
               (format *error-output* "cl-weave: completed ~A form ~D~%"
                       source index)))))

(defun direct-load-system-sources (root asd-name system-name)
  (let* ((asd-path (merge-pathnames asd-name root))
         (components (direct-read-system-components asd-path system-name)))
    (dolist (source (direct-component-paths components root))
      (direct-load-source source))))

(let ((root (direct-project-root)))
  (direct-enable-coverage-compilation)
  (direct-load-system-sources root "cl-weave.asd" "cl-weave")
  (direct-load-system-sources root "cl-weave-tests.asd" "cl-weave-tests")
  (pushnew :cl-weave-direct-load *features*)
  (load (merge-pathnames "scripts/run-tests.lisp" root)))
