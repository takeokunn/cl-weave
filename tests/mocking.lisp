(in-package #:cl-weave/tests)

(describe "mocking"
  (it "restores symbol functions"
    (expect (sample-size '(a b c)) :to-be 3)
    (with-mocked-functions (((symbol-function 'sample-size)
                             (lambda (value)
                               (declare (ignore value))
                               99)))
      (expect (sample-size '(a b c)) :to-be 99))
    (expect (sample-size '(a b c)) :to-be 3))

  (it "records mock function calls"
    (let ((mock (make-mock-function (lambda (left right)
                                      (+ left right)))))
      (expect (funcall mock 1 2) :to-be 3)
      (expect (funcall mock 5 8) :to-be 13)
      (expect mock :to-have-been-called)
      (expect mock :to-have-been-called-times 2)
      (expect mock :to-have-been-called-with 1 2)
      (expect mock :to-have-been-nth-called-with 1 1 2)
      (expect mock :to-have-been-nth-called-with 2 5 8)
      (expect mock :to-have-been-last-called-with 5 8)
      (expect (mock-calls mock) :to-equal '((1 2) (5 8)))
      (clear-mock mock)
      (expect mock :not :to-have-been-called)
      (expect (mock-calls mock) :to-equal nil)
      (expect (mock-results mock) :to-equal nil)))

  (it "clears one mock with the Vitest-shaped vi.mockclear alias"
    (let ((mock (vi.fn (lambda (value) value))))
      (expect (funcall mock :before) :to-be :before)
      (expect mock :to-have-been-called-times 1)
      (expect (vi.mockclear mock) :to-be mock)
      (expect mock :not :to-have-been-called)
      (expect (mock-results mock) :to-equal nil)
      (expect (funcall mock :after) :to-be :after)
      (expect mock :to-have-been-called-with :after)))

  (it "creates mock functions with the Vitest-shaped vi.fn alias"
    (let ((mock (vi.fn (lambda (value)
                         (values value (1+ value))))))
      (multiple-value-bind (value incremented) (funcall mock 41)
        (expect value :to-be 41)
        (expect incremented :to-be 42))
      (expect mock :to-have-been-called-times 1)
      (expect mock :to-have-been-called-with 41)
      (expect mock :to-have-returned-with 41 42)
      (expect (mock-calls mock) :to-equal '((41)))))

  (it "detects mock functions with Lisp and Vitest-shaped predicates"
    (let ((mock (vi.fn)))
      (expect (mock-function-p mock) :to-be t)
      (expect (vi.ismockfunction mock) :to-be t)
      (expect (vi.mocked mock) :to-be t)
      (expect (mock-function-p (lambda () :not-a-mock)) :to-be nil)
      (expect (vi.ismockfunction :not-a-function) :to-be nil)
      (expect (vi.mocked :not-a-function) :to-be nil)))

  (it "updates mock implementations with Lisp and Vitest-shaped aliases"
    (let ((mock (vi.fn)))
      (expect (funcall mock 1) :to-be nil)
      (expect (mock-implementation mock (lambda (value) (* value 2))) :to-be mock)
      (expect (funcall mock 21) :to-be 42)
      (expect mock :to-have-been-called-with 21)
      (expect (vi.mockimplementation mock (lambda (value) (+ value 1))) :to-be mock)
      (expect (funcall mock 41) :to-be 42)
      (expect mock :to-have-returned-with 42)))

  (it "sets mock return values including Common Lisp multiple values"
    (let ((mock (vi.fn (lambda () :old))))
      (expect (vi.mockreturnvalue mock :next) :to-be mock)
      (expect (funcall mock :ignored) :to-be :next)
      (expect mock :to-have-returned-with :next)
      (expect (mock-return-values mock :ok 42) :to-be mock)
      (multiple-value-bind (status count) (funcall mock)
        (expect status :to-be :ok)
        (expect count :to-be 42))
      (expect mock :to-have-returned-with :ok 42)
      (expect (vi.mockreturnvalues mock :done 7) :to-be mock)
      (multiple-value-bind (status count) (funcall mock :ignored)
        (expect status :to-be :done)
        (expect count :to-be 7))
      (expect (mock-return-value mock :final) :to-be mock)
      (expect (funcall mock) :to-be :final)))

  (it "rejects non-function mock implementations early"
    (expect (lambda () (make-mock-function :not-a-function)) :to-throw)
    (let ((mock (vi.fn)))
      (expect (lambda () (mock-implementation mock :not-a-function)) :to-throw)))

  (it "spies on global function cells and restores originals"
    (expect (sample-size '(a b c)) :to-be 3)
    (let ((spy (spy-on 'sample-size)))
      (expect (mock-function-p spy) :to-be t)
      (expect (sample-size '(a b c d)) :to-be 4)
      (expect spy :to-have-been-called-with '(a b c d))
      (expect spy :to-have-returned-with 4)
      (expect (mock-return-value spy 99) :to-be spy)
      (expect (sample-size '(a b)) :to-be 99)
      (expect (mock-restore spy) :to-be spy)
      (expect (sample-size '(a b)) :to-be 2)
      (expect (mock-restore spy) :to-be spy)))

  (it "restores all spies with Vitest-shaped aliases"
    (let ((spy (vi.spyon 'sample-size)))
      (expect (vi.mockreturnvalue spy 10) :to-be spy)
      (expect (sample-size '(a b c)) :to-be 10)
      (expect (vi.restoreallmocks) :to-be t)
      (expect (sample-size '(a b c)) :to-be 3)
      (expect spy :not :to-have-been-called)))

  (it "rejects spy targets without function cells"
    (expect (lambda () (spy-on "sample-size")) :to-throw)
    (let ((missing (gensym "MISSING-FUNCTION-")))
      (expect (lambda () (vi.spyon missing)) :to-throw)))

  (it "clears all registered mock histories with vi.clearallmocks"
    (let ((left (vi.fn (lambda () :left)))
          (right (make-mock-function (lambda (value) value))))
      (expect (funcall left) :to-be :left)
      (expect (funcall right :right) :to-be :right)
      (expect left :to-have-been-called-times 1)
      (expect right :to-have-been-called-with :right)
      (expect (vi.clearallmocks) :to-be t)
      (expect left :not :to-have-been-called)
      (expect right :not :to-have-been-called)
      (expect (funcall left) :to-be :left)
      (expect left :to-have-been-called-times 1)))

  (it "resets one mock history and implementation"
    (let ((mock (vi.fn (lambda () :custom))))
      (expect (funcall mock) :to-be :custom)
      (expect mock :to-have-been-called-times 1)
      (expect (reset-mock mock) :to-be mock)
      (expect mock :not :to-have-been-called)
      (expect (funcall mock) :to-be nil)
      (expect mock :to-have-returned-with nil)))

  (it "resets one mock with the Vitest-shaped vi.mockreset alias"
    (let ((mock (vi.fn (lambda () :custom))))
      (expect (funcall mock) :to-be :custom)
      (expect mock :to-have-been-called-times 1)
      (expect (vi.mockreset mock) :to-be mock)
      (expect mock :not :to-have-been-called)
      (expect (funcall mock) :to-be nil)
      (expect mock :to-have-returned-with nil)))

  (it "resets all registered mock histories and implementations with vi.resetallmocks"
    (let ((left (vi.fn (lambda () :left)))
          (right (make-mock-function (lambda () :right))))
      (expect (funcall left) :to-be :left)
      (expect (funcall right) :to-be :right)
      (expect left :to-have-been-called-times 1)
      (expect right :to-have-been-called-times 1)
      (expect (vi.resetallmocks) :to-be t)
      (expect left :not :to-have-been-called)
      (expect right :not :to-have-been-called)
      (expect (funcall left) :to-be nil)
      (expect (funcall right) :to-be nil)))

  (it "matches ordered zero-argument mock calls"
    (let ((mock (make-mock-function (lambda () :pong))))
      (expect (funcall mock) :to-be :pong)
      (expect mock :to-have-been-nth-called-with 1)
      (expect mock :to-have-been-last-called-with)))

  (it "records mock return values including multiple values"
    (let ((mock (make-mock-function (lambda (value)
                                      (values value (* value 2))))))
      (multiple-value-bind (value doubled) (funcall mock 4)
        (expect value :to-be 4)
        (expect doubled :to-be 8))
      (multiple-value-bind (value doubled) (funcall mock 7)
        (expect value :to-be 7)
        (expect doubled :to-be 14))
      (expect mock :to-have-returned)
      (expect mock :to-have-returned-times 2)
      (expect mock :to-have-returned-with 4 8)
      (expect mock :to-have-nth-returned-with 1 4 8)
      (expect mock :to-have-nth-returned-with 2 7 14)
      (expect mock :to-have-last-returned-with 7 14)
      (expect (mock-results mock)
              :to-equal
              '((:type :return :value 4 :values (4 8))
                (:type :return :value 7 :values (7 14))))))

  (it "matches returned order without counting thrown results"
    (let ((mock (let ((state 0))
                  (make-mock-function
                   (lambda ()
                     (incf state)
                     (when (= state 2)
                       (error "mock exploded"))
                     (values state :ok))))))
      (multiple-value-bind (value status) (funcall mock)
        (expect value :to-be 1)
        (expect status :to-be :ok))
      (expect (lambda () (funcall mock)) :to-throw "mock exploded")
      (multiple-value-bind (value status) (funcall mock)
        (expect value :to-be 3)
        (expect status :to-be :ok))
      (expect mock :to-have-returned-times 2)
      (expect mock :to-have-nth-returned-with 1 1 :ok)
      (expect mock :to-have-nth-returned-with 2 3 :ok)
      (expect mock :to-have-last-returned-with 3 :ok)
      (expect mock :to-have-thrown)))

  (it "records thrown conditions from mock functions"
    (let ((mock (make-mock-function (lambda ()
                                      (error "mock exploded")))))
      (expect (lambda () (funcall mock)) :to-throw "mock exploded")
      (expect mock :to-have-thrown)
      (expect mock :not :to-have-returned)
      (expect (getf (first (mock-results mock)) :type) :to-be :throw)
      (expect (getf (first (mock-results mock)) :message)
              :to-contain
              "mock exploded")))

  (it "reports structured mock assertion failures"
    (handler-case
        (let ((mock (make-mock-function (lambda () :ok))))
          (funcall mock)
          (expect mock :to-have-returned-times 2)
          (error "unreachable"))
      (assertion-failure (condition)
        (let ((assertion (cl-weave::failure-detail condition)))
          (expect (cl-weave::assertion-detail-matcher assertion)
                  :to-be
                  :to-have-returned-times)
          (expect (getf (cl-weave::assertion-detail-actual assertion)
                        :return-count)
                  :to-be
                  1)
          (expect (cl-weave::assertion-detail-expected assertion)
                  :to-equal
                  '(:return-count 2))))))

  (it "reports structured ordered mock assertion failures"
    (handler-case
        (let ((mock (make-mock-function (lambda (value) value))))
          (funcall mock :actual)
          (expect mock :to-have-been-nth-called-with 2 :missing)
          (error "unreachable"))
      (assertion-failure (condition)
        (let ((assertion (cl-weave::failure-detail condition)))
          (expect (cl-weave::assertion-detail-matcher assertion)
                  :to-be
                  :to-have-been-nth-called-with)
          (expect (getf (cl-weave::assertion-detail-actual assertion)
                        :call-count)
                  :to-be
                  1)
          (expect (cl-weave::assertion-detail-expected assertion)
                  :to-equal
                  '(:index 2 :arguments (:missing))))))))

