(in-package #:cl-weave)

(defmacro describe (name &body body)
  `(register-suite ,name (lambda () ,@body)))

(defmacro it (name &body body)
  `(register-test ,name (lambda () ,@body)))

(defmacro it-skip (name &optional (reason "skipped"))
  `(register-test ,name (lambda () nil) :skip-reason ,reason))

(defmacro it-each (cases name bindings &body body)
  `(progn
     ,@(loop for case in cases
             collect `(it ,(apply #'format nil name case)
                        (destructuring-bind ,bindings ',case
                          ,@body)))))

(defmacro test (name &body body)
  `(it ,name ,@body))

(defmacro test-skip (name &optional (reason "skipped"))
  `(it-skip ,name ,reason))

(defmacro before-all (&body body)
  `(register-before-all (lambda () ,@body)))

(defmacro after-all (&body body)
  `(register-after-all (lambda () ,@body)))

(defmacro before-each (&body body)
  `(register-before-each (lambda () ,@body)))

(defmacro after-each (&body body)
  `(register-after-each (lambda () ,@body)))

(defmacro expect (actual &body expectation)
  (let ((value (gensym "ACTUAL-")))
    `(let ((,value ,actual))
       (assert-expectation
        ,value
        (list ,@expectation)
        '(expect ,actual ,@expectation)))))

(defmacro with-mocked-functions (bindings &body body)
  (let ((saved (gensym "SAVED-")))
    `(let ((,saved
             (list
              ,@(loop for (place replacement) in bindings
                      collect place))))
       (unwind-protect
            (progn
              ,@(loop for (place replacement) in bindings
                      collect `(setf ,place ,replacement))
              ,@body)
         ,@(loop for (place nil) in bindings
                 for index from 0
                 collect `(setf ,place (nth ,index ,saved)))))))
