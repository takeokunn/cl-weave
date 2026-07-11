(in-package #:cl-weave)

(defun signal-continuation-not-called (form)
  (signal-assertion-failure
   (make-assertion-detail
    :form form
    :matcher :continuation-called
    :actual '(:called nil)
    :expected '(:called t)
    :negated nil
    :pass nil)))

(defun ensure-continuation-called (calledp form)
  (unless calledp
    (signal-continuation-not-called form))
  t)

(defun require-continuation-binding-symbol (name form)
  (unless (and name (symbolp name))
    (error "cl-weave: continuation binding in ~S must be a symbol, got ~S."
           form
           name))
  name)

(defmacro with-continuation-values ((values continuation &optional calledp) form &body body)
  (let* ((source `(with-continuation-values
                   (,values ,continuation ,@(when calledp (list calledp)))
                   ,form
                   ,@body))
         (continuation-name (require-continuation-binding-symbol continuation source))
         (captured-values (gensym "CONTINUATION-VALUES-"))
         (called (gensym "CONTINUATION-CALLED-"))
         (continuation-reference (gensym "CONTINUATION-FUNCTION-")))
    `(let ((,captured-values nil)
           (,called nil))
       (flet ((,continuation-name (&rest next-values)
                (setf ,called t
                      ,captured-values next-values)))
         (let ((,continuation-reference (function ,continuation-name)))
           (declare (ignore ,continuation-reference)))
         ,form)
       (ensure-continuation-called ,called ',form)
       (let ((,values ,captured-values)
             ,@(when calledp `((,calledp ,called))))
         ,@body))))

(defmacro with-continuation-result ((value continuation &optional calledp) form &body body)
  (let ((values (gensym "CONTINUATION-VALUES-")))
    `(with-continuation-values (,values ,continuation ,@(when calledp `(,calledp))) ,form
       (let ((,value (first ,values)))
         ,@body))))

