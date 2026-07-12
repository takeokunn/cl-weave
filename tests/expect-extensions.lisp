(in-package #:cl-weave/tests)

(defun slow-measured-operation ()
  (sleep 0.001))

(defun allocating-measured-operation ()
  (list :allocated))

(defparameter *measurement-fields*
  '(:elapsed-ms :elapsed-seconds :bytes-consed :values))

(defun expect-measurement-fields (actual)
  (dolist (field *measurement-fields*)
    (expect actual :to-contain field)))

(defun expect-measurement-failure (condition matcher expected)
  (with-assertion-detail (detail condition actual)
    (expect (cl-weave::assertion-detail-matcher detail) :to-be matcher)
    (expect-measurement-fields actual)
    (expect (cl-weave::assertion-detail-expected detail) :to-equal expected)))

(defun expect-performance-measurement-failure ()
  (handler-case
      (progn
        (expect #'slow-measured-operation :to-run-under-ms 0)
        (expect nil :to-be-truthy))
    (cl-weave:assertion-failure (condition)
      (expect-measurement-failure condition :to-run-under-ms '(:max-ms 0)))))

(defun expect-allocation-measurement-failure ()
  (handler-case
      (progn
        (expect #'allocating-measured-operation :to-allocate-under 0)
        (expect nil :to-be-truthy))
    (cl-weave:assertion-failure (condition)
      (expect-measurement-failure condition
                                  :to-allocate-under
                                  '(:max-bytes 0)))))

(defun expect-public-custom-matcher-failure ()
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

(defun expect-extended-custom-matcher-failure ()
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

(defun expect-data-driven-custom-matcher-failure ()
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

(defun expect-stable-matcher-metadata ()
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

(defun expect-smart-assertion-failure ()
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

(describe "expect extensions and measurements"
  (it "supports public custom matchers with structured failure data"
    (expect-public-custom-matcher-failure)))

(describe "expect-extend custom matchers"
  (it "supports Vitest-style expect-extend custom matchers"
    (expect-extended-custom-matcher-failure)))

(describe "data-driven custom matchers"
  (it "supports data-driven extend-expect custom matchers"
    (expect-data-driven-custom-matcher-failure)))

(describe "matcher metadata and smart assertions"
  (it "exposes stable matcher metadata for AI tooling"
    (expect-stable-matcher-metadata)))

(describe "smart assertions"
  (it "signals smart assertion failures with operand values"
    (expect-smart-assertion-failure)))

(describe "expect performance and allocation measurements"
  (it "reports performance measurements in assertion failures"
    (expect-performance-measurement-failure))

  (it "reports allocation measurements in assertion failures"
    (expect-allocation-measurement-failure)))

(describe "matcher argument validation"
  (it "rejects malformed matcher arguments with stable errors"
    (dolist (bad-expectation
             (list (lambda () (expect 1 :to-be-close-to))
                   (lambda () (expect 1 :to-be-close-to 2 :digits))
                   (lambda () (expect 1 :to-be-close-to 2 -3))
                   (lambda () (expect 1 :to-be-one-of))
                   (lambda () (expect 1 :to-be-instance-of :no-such-class))
                   (lambda () (expect (lambda () t) :to-throw 42))
                   (lambda () (expect 42 :to-run-under-ms 5))
                   (lambda () (expect (lambda () t) :to-run-under-ms "fast"))
                   (lambda () (expect (lambda () t) :to-run-under-ms -1))
                   (lambda () (expect (lambda () t) :to-allocate-under "few"))
                   (lambda () (expect 42 :to-have-method-specialized-on 'name))
                   (lambda () (expect 42 :to-have-slot))))
      (expect bad-expectation :to-throw))))
