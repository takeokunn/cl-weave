(in-package #:cl-weave/tests)

(describe "tag filter normalization"
  (it "accepts maximum include and exclude tags in canonical first order"
    (let* ((limit cl-weave::+maximum-tag-count+)
           (include-tags (make-list limit :initial-element :fast))
           (exclude-tags (make-list limit :initial-element :database))
           (root (cl-weave::make-suite :name "root"))
           (root-calls 0)
           (captured-options nil))
      (setf (first include-tags) :fast
            (second include-tags) "slow"
            (third include-tags) 'fast
            (fourth include-tags) :other
            (first exclude-tags) "database"
            (second exclude-tags) :cache
            (third exclude-tags) "DATABASE")
      (with-mocked-functions
          (((symbol-function 'cl-weave:root-suite)
            (lambda ()
              (incf root-calls)
              root))
           ((symbol-function 'cl-weave::collect-events-with-options)
            (lambda (suite options)
              (declare (ignore suite))
              (setf captured-options options)
              nil)))
        #+sbcl
        (sb-ext:with-timeout 10
          (expect
           (cl-weave:run-all
            :reporter :sexp
            :stream (make-broadcast-stream)
            :include-tags include-tags
            :exclude-tags exclude-tags)
           :to-be-truthy))
        #-sbcl
        (expect
         (cl-weave:run-all
          :reporter :sexp
          :stream (make-broadcast-stream)
          :include-tags include-tags
          :exclude-tags exclude-tags)
         :to-be-truthy))
      (expect root-calls :to-be 1)
      (expect captured-options :to-be-truthy)
      (expect (cl-weave::collection-options-include-tags captured-options)
              :to-equal '("FAST" "SLOW" "OTHER"))
      (expect (cl-weave::collection-options-exclude-tags captured-options)
              :to-equal '("DATABASE" "CACHE")))))
