(in-package #:cl-weave)

(defstruct mutation
  (id nil :type (or null integer) :read-only t)
  (operator nil :type (or null keyword) :read-only t)
  (path nil :type list :read-only t)
  (original nil :read-only t)
  (replacement nil :read-only t)
  (form nil :read-only t))

(defstruct mutation-result
  (mutation nil :type (or null mutation) :read-only t)
  (status nil :type (or null keyword) :read-only t)
  (condition nil :type (or null condition) :read-only t))

(define-condition mutation-score-failure (error)
  ((summary :initarg :summary :reader mutation-score-failure-summary)
   (min-score :initarg :min-score :reader mutation-score-failure-min-score))
  (:report (lambda (condition stream)
             (format stream "Mutation score ~,2F is below required score ~,2F."
                     (getf (mutation-score-failure-summary condition) :score)
                     (mutation-score-failure-min-score condition)))))
