(in-package #:cl-weave/tests)

(defun expect-property-constructor-errors (cases)
  (dolist (case cases)
    (destructuring-bind (thunk diagnostic) case
      (expect thunk :to-throw diagnostic))))

