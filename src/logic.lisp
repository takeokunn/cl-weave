(in-package #:cl-weave)

(defun make-logic-rule (&key head (body nil))
  (vector 'logic-rule head body))

(defun logic-rule-p (value)
  (and (simple-vector-p value)
       (= (length value) 3)
       (eq (svref value 0) 'logic-rule)))

(defun logic-rule-head (rule)
  (svref rule 1))

(defun logic-rule-body (rule)
  (svref rule 2))

(defun logic-variable-p (value)
  (and (symbolp value)
       (< 0 (length (symbol-name value)))
       (char= #\? (char (symbol-name value) 0))))

(defun logic-binding-value (variable bindings)
  (let ((binding (assoc variable bindings)))
    (if binding
        (values (cdr binding) t)
        (values nil nil))))

(defun logic-walk (value bindings &optional seen)
  (if (logic-variable-p value)
      (if (member value seen :test #'eq)
          value
          (multiple-value-bind (bound found-p) (logic-binding-value value bindings)
            (if found-p
                (logic-walk bound bindings (cons value seen))
                value)))
      value))

(defun extend-logic-binding (variable value bindings)
  (acons variable value bindings))

(defun logic-occurs-in-p (variable value bindings)
  (let ((value (logic-walk value bindings)))
    (cond
      ((eql variable value) t)
      ((consp value)
       (or (logic-occurs-in-p variable (car value) bindings)
           (logic-occurs-in-p variable (cdr value) bindings)))
      (t nil))))

(defun unify-logic-values (left right bindings)
  (let ((left (logic-walk left bindings))
        (right (logic-walk right bindings)))
    (cond
      ((and (consp left) (consp right))
       (multiple-value-bind (head-bindings head-ok-p)
           (unify-logic-values (first left) (first right) bindings)
         (if head-ok-p
             (unify-logic-values (rest left) (rest right) head-bindings)
             (values nil nil))))
      ((logic-variable-p left)
       (if (logic-occurs-in-p left right bindings)
           (values nil nil)
           (values (extend-logic-binding left right bindings) t)))
      ((logic-variable-p right)
       (if (logic-occurs-in-p right left bindings)
           (values nil nil)
           (values (extend-logic-binding right left bindings) t)))
      ((equal left right) (values bindings t))
      (t (values nil nil)))))

(defun resolve-logic-value (value bindings)
  (let ((value (logic-walk value bindings)))
    (if (consp value)
        (let ((resolved '()))
          (dolist (part value (nreverse resolved))
            (push (resolve-logic-value part bindings) resolved)))
        value)))

(defun normalize-logic-bindings (bindings)
  (nreverse
   (mapcar (lambda (binding)
             (cons (car binding)
                   (resolve-logic-value (cdr binding) bindings)))
           bindings)))

(defun collect-logic-variables (value)
  (cond
    ((logic-variable-p value) (list value))
    ((consp value)
     (append (collect-logic-variables (car value))
             (collect-logic-variables (cdr value))))
    (t '())))

(defun project-logic-bindings (bindings variables)
  (let ((normalized (normalize-logic-bindings bindings)))
    (loop for variable in variables
          for binding = (assoc variable normalized)
          when binding
            collect binding)))

(defun logic-rule-indicator-p (value)
  (eq value :-))

(defun logic-rule-form-p (form)
  (and (consp form)
       (logic-rule-indicator-p (first form))))

(defun normalize-logic-rule-form (form)
  (unless (and (consp form) (consp (rest form)))
    (error "cl-weave: logic rule requires a head and optional body, got ~S." form))
  (make-logic-rule :head (second form)
                   :body (cddr form)))

(defun normalize-logic-program (program)
  (let ((normalized '()))
    (dolist (entry program (nreverse normalized))
      (push (if (logic-rule-form-p entry)
                (normalize-logic-rule-form entry)
                entry)
            normalized))))

(defun fresh-logic-variable (variable rule-id)
  (make-symbol (format nil "~A/~D" (symbol-name variable) rule-id)))

(defun instantiate-logic-term (term mapping rule-id)
  (cond
    ((logic-variable-p term)
     (multiple-value-bind (renamed present-p) (gethash term mapping)
       (if present-p
           renamed
           (let ((fresh (fresh-logic-variable term rule-id)))
             (setf (gethash term mapping) fresh)
             fresh))))
    ((consp term)
     (cons (instantiate-logic-term (car term) mapping rule-id)
           (instantiate-logic-term (cdr term) mapping rule-id)))
    (t term)))

(defun instantiate-logic-rule (rule rule-id)
  (let ((mapping (make-hash-table :test #'eq)))
    (make-logic-rule
     :head (instantiate-logic-term (logic-rule-head rule) mapping rule-id)
     :body (let ((instantiated '()))
             (dolist (goal (logic-rule-body rule) (nreverse instantiated))
               (push (instantiate-logic-term goal mapping rule-id)
                     instantiated))))))

(defun logic-entry-head (entry)
  (if (logic-rule-p entry)
      (logic-rule-head entry)
      entry))

(defun logic-entry-body (entry)
  (if (logic-rule-p entry)
      (logic-rule-body entry)
      '()))

(defun logic-below-limit-p (results limit)
  (or (null limit) (< (length results) limit)))

(defun remove-duplicate-logic-variables (variables)
  (let ((unique '()))
    (dolist (variable variables (nreverse unique))
      (unless (member variable unique :test #'eq)
        (push variable unique)))))

(defun make-logic-search-frame (pending bindings)
  (list pending bindings))

(defun logic-search-frame-pending (frame)
  (first frame))

(defun logic-search-frame-bindings (frame)
  (second frame))

(define-condition logic-search-exhausted (error)
  ((steps :initarg :steps :reader logic-search-exhausted-steps)
   (limit :initarg :limit :reader logic-search-exhausted-limit)
   (pending :initarg :pending :reader logic-search-exhausted-pending)
   (partial-results :initarg :partial-results
                    :reader logic-search-exhausted-partial-results))
  (:report (lambda (condition stream)
             (format stream
                     "cl-weave: logic query exhausted its ~D step limit with ~D frames pending."
                     (logic-search-exhausted-limit condition)
                     (logic-search-exhausted-pending condition)))))

(defun logic-query (program clauses &key limit max-steps)
  (unless (or (null limit) (and (integerp limit) (plusp limit)))
    (error "cl-weave: logic-query limit must be NIL or a positive integer, got ~S."
           limit))
  (unless (or (null max-steps)
              (and (integerp max-steps) (plusp max-steps)))
    (error "cl-weave: logic-query max-steps must be NIL or a positive integer, got ~S."
           max-steps))
  (let ((normalized-program (normalize-logic-program program))
        (query-variables
          (remove-duplicate-logic-variables (collect-logic-variables clauses)))
        (frames (list (make-logic-search-frame clauses nil)))
        (results nil)
        (steps 0)
        (next-rule-id 0))
    (block search
      (loop while (and frames (logic-below-limit-p results limit))
          do (when (and max-steps (>= steps max-steps))
               (restart-case
                   (error 'logic-search-exhausted
                          :steps steps
                          :limit max-steps
                          :pending (length frames)
                          :partial-results (reverse results))
                 (return-partial-results ()
                   :report "Return the results found before the step budget was exhausted."
                   (return-from search (nreverse results)))
                 (increase-limit (new-limit)
                   :report "Continue the logic query with a larger step limit."
                   (unless (and (integerp new-limit) (> new-limit steps))
                     (error "cl-weave: increased logic step limit must exceed ~D, got ~S."
                            steps new-limit))
                   (setf max-steps new-limit))))
             (incf steps)
             (let* ((frame (pop frames))
                    (pending (logic-search-frame-pending frame))
                    (bindings (logic-search-frame-bindings frame)))
               (if (null pending)
                   (push (project-logic-bindings bindings query-variables) results)
                   (let ((goal (first pending))
                         (rest-goals (rest pending))
                         (new-frames nil))
                     (dolist (candidate normalized-program)
                       (let* ((rule-p (logic-rule-p candidate))
                              (rule-id next-rule-id)
                              (instantiated (if rule-p
                                                (instantiate-logic-rule candidate rule-id)
                                                candidate))
                              (head (logic-entry-head instantiated))
                              (body (logic-entry-body instantiated)))
                         (when rule-p
                           (incf next-rule-id))
                         (multiple-value-bind (next-bindings matched-p)
                             (unify-logic-values goal head bindings)
                           (when matched-p
                             (push (make-logic-search-frame (append body rest-goals)
                                                            next-bindings)
                                   new-frames)))))
                     (dolist (new-frame new-frames)
                       (push new-frame frames))))))
      (nreverse results))))

(defun split-logic-where-forms (forms)
  (let ((limit nil)
        (limit-present-p nil)
        (max-steps nil)
        (max-steps-present-p nil)
        (clauses forms))
    (loop while (and clauses
                     (consp (first clauses))
                     (member (first (first clauses)) '(:limit :max-steps)))
          for option = (pop clauses)
          do (unless (= 2 (length option))
               (error "cl-weave: ~S expects exactly one value, got ~S."
                      (first option) option))
             (ecase (first option)
               (:limit
                (when limit-present-p
                  (error "cl-weave: duplicate :limit logic option."))
                (setf limit (second option)
                      limit-present-p t))
               (:max-steps
                (when max-steps-present-p
                  (error "cl-weave: duplicate :max-steps logic option."))
                (setf max-steps (second option)
                      max-steps-present-p t))))
    (unless clauses
      (error "cl-weave: logic where macros require at least one relation clause."))
    (dolist (clause clauses)
      (unless (and (consp clause) (keywordp (first clause)))
        (error "cl-weave: logic clauses must be non-empty keyword relation lists, got ~S."
               clause)))
    (values clauses limit limit-present-p max-steps max-steps-present-p)))

(defmacro logic-where (facts &body forms)
  (multiple-value-bind (clauses limit limit-present-p max-steps max-steps-present-p)
      (split-logic-where-forms forms)
    `(logic-query ,facts ',clauses
                  ,@(when limit-present-p `(:limit ,limit))
                  ,@(when max-steps-present-p `(:max-steps ,max-steps)))))

(defmacro logic-program (&body entries)
  `(list ,@(mapcar (lambda (entry) `',entry) entries)))

(defmacro logic-run (program &body forms)
  (multiple-value-bind (clauses limit limit-present-p max-steps max-steps-present-p)
      (split-logic-where-forms forms)
    `(logic-query ,program ',clauses
                  ,@(when limit-present-p `(:limit ,limit))
                  ,@(when max-steps-present-p `(:max-steps ,max-steps)))))

(defmacro test-plan-where (plan &body forms)
  (multiple-value-bind (clauses limit limit-present-p max-steps max-steps-present-p)
      (split-logic-where-forms forms)
    `(query-test-plan ,plan ',clauses
                      ,@(when limit-present-p `(:limit ,limit))
                      ,@(when max-steps-present-p `(:max-steps ,max-steps)))))

(defun test-plan-entry-facts (entry)
  (let ((path (test-plan-entry-path entry)))
    (append
     (list (list :test path)
           (list :status path (test-plan-entry-status entry))
           (list :retry path (test-plan-entry-retry entry)))
     (when (test-plan-entry-reason entry)
       (list (list :reason path (test-plan-entry-reason entry))))
     (when (test-plan-entry-focused entry)
       (list (list :focused path)))
     (when (test-plan-entry-timeout-ms entry)
       (list (list :timeout-ms path (test-plan-entry-timeout-ms entry))))
     (when (test-plan-entry-concurrent entry)
       (list (list :concurrent path)))
     (when (test-plan-entry-location entry)
       (list (list :location path (test-plan-entry-location entry)))))))

(defun test-plan-facts (plan)
  (mapcan #'test-plan-entry-facts plan))

(defun normalize-test-plan-query-input (value)
  (if (and (listp value)
           (every #'test-plan-entry-p value))
      (test-plan-facts value)
      value))

(defun query-test-plan (plan-or-program clauses &key limit max-steps)
  (logic-query (normalize-test-plan-query-input plan-or-program)
               clauses
               :limit limit
               :max-steps max-steps))
