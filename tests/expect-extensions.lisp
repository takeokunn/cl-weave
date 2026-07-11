(in-package #:cl-weave/tests)

(describe "expect extensions and measurements"
  (it "supports public custom matchers with structured failure data"
    (expect 4 :to-be-even)
    (handler-case
        (progn
          (expect 5 :to-be-even)
          (expect nil :to-be-truthy))
      (cl-weave:assertion-failure (condition)
        (with-assertion-detail (detail condition)
          (expect (cl-weave::assertion-detail-matcher detail) :to-be :to-be-even)
          (expect (cl-weave::assertion-detail-actual detail)
                  :to-equal '(:value 5 :parity :odd))
          (expect (cl-weave::assertion-detail-expected detail)
                  :to-equal '(:parity :even))))))

  (it "supports Vitest-style expect-extend custom matchers"
    (expect 7 :to-be-odd)
    (handler-case
        (progn
          (expect 8 :to-be-odd)
          (expect nil :to-be-truthy))
      (cl-weave:assertion-failure (condition)
        (with-assertion-detail (detail condition)
          (expect (cl-weave::assertion-detail-matcher detail) :to-be :to-be-odd)
          (expect (cl-weave::assertion-detail-actual detail)
                  :to-equal '(:value 8 :parity :even))
          (expect (cl-weave::assertion-detail-expected detail)
                  :to-equal '(:parity :odd))))))

  (it "supports data-driven extend-expect custom matchers"
    (expect 5 :to-be-between 1 10)
    (handler-case
        (progn
          (expect 11 :to-be-between 1 10)
          (expect nil :to-be-truthy))
      (cl-weave:assertion-failure (condition)
        (with-assertion-detail (detail condition)
          (expect (cl-weave::assertion-detail-matcher detail) :to-be :to-be-between)
          (expect (cl-weave::assertion-detail-actual detail)
                  :to-equal '(:value 11 :range (1 10)))
          (expect (cl-weave::assertion-detail-expected detail)
                  :to-equal '(:range (1 10)))))))

  (it "exposes stable matcher metadata for AI tooling"
    (let* ((metadata (cl-weave:list-matchers))
           (names (mapcar (lambda (entry) (getf entry :name)) metadata))
           (sorted-names (sort (copy-list names) #'string< :key #'symbol-name))
           (even (cl-weave:matcher-metadata :to-be-even))
           (odd (cl-weave:matcher-metadata :to-be-odd))
           (between (cl-weave:matcher-metadata :to-be-between))
           (slot (cl-weave:matcher-metadata :to-have-slot))
           (method (cl-weave:matcher-metadata :to-have-method-specialized-on)))
      (expect names :to-equal sorted-names)
      (expect names :to-contain :to-be)
      (expect even :to-equal
              '(:name :to-be-even
                :description "Passes when ACTUAL is an even integer."))
      (expect odd :to-equal
              '(:name :to-be-odd
                :description "Passes when ACTUAL is an odd integer."))
      (expect between :to-equal
              '(:name :to-be-between
                :description "Passes when ACTUAL is within the inclusive numeric range."))
      (expect slot :to-equal
              '(:name :to-have-slot
                :description "Passes when ACTUAL names a class that defines the EXPECTED slot."))
      (expect method :to-equal
              '(:name :to-have-method-specialized-on
                :description "Passes when ACTUAL names a generic function with a method specialized on the EXPECTED specializers."))))

  (it "signals smart assertion failures with operand values"
    (handler-case
        (progn
          (expect (= (+ 1 1) 3))
          (expect nil :to-be-truthy))
      (cl-weave:assertion-failure (condition)
        (with-assertion-detail (detail condition actual)
          (expect (cl-weave::assertion-detail-matcher detail) :to-be '=)
          (expect actual :to-contain '(:form (+ 1 1) :value 2))
          (expect actual :to-contain '(:form 3 :value 3))
          (expect (cl-weave::assertion-detail-expected detail)
                  :to-equal '(= (+ 1 1) 3))))))

  (it "reports performance measurements in assertion failures"
    (handler-case
        (progn
          (expect (lambda () (sleep 0.001)) :to-run-under-ms 0)
          (expect nil :to-be-truthy))
      (cl-weave:assertion-failure (condition)
        (with-assertion-detail (detail condition actual)
          (expect (cl-weave::assertion-detail-matcher detail) :to-be :to-run-under-ms)
          (expect actual :to-contain :elapsed-ms)
          (expect actual :to-contain :elapsed-seconds)
          (expect actual :to-contain :bytes-consed)
          (expect actual :to-contain :values)
          (expect (cl-weave::assertion-detail-expected detail)
                  :to-equal '(:max-ms 0))))))

  (it "reports allocation measurements in assertion failures"
    (handler-case
        (progn
          (expect (lambda () (list :allocated)) :to-allocate-under 0)
          (expect nil :to-be-truthy))
      (cl-weave:assertion-failure (condition)
(with-assertion-detail (detail condition actual)
          (expect (cl-weave::assertion-detail-matcher detail) :to-be :to-allocate-under)
          (expect actual :to-contain :elapsed-ms)
          (expect actual :to-contain :elapsed-seconds)
          (expect actual :to-contain :bytes-consed)
          (expect actual :to-contain :values)
          (expect (cl-weave::assertion-detail-expected detail)
                  :to-equal '(:max-bytes 0)))))))
