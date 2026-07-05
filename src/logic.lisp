(in-package #:cl-weave)

(defstruct logic-rule
  head
  (body '()))

(defun logic-variable-p (value)
  (and (symbolp value)
       (< 0 (length (symbol-name value)))
       (char= #\? (char (symbol-name value) 0))))

(defun logic-binding-value (variable bindings)
  (let ((binding (assoc variable bindings)))
    (if binding
        (values (cdr binding) t)
        (values nil nil))))

(defun logic-walk (value bindings)
  (if (logic-variable-p value)
      (multiple-value-bind (bound found-p) (logic-binding-value value bindings)
        (if found-p
            (logic-walk bound bindings)
            value))
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
        (mapcar (lambda (part) (resolve-logic-value part bindings)) value)
        value)))

(defun normalize-logic-bindings (bindings)
  (mapcar (lambda (binding)
            (cons (car binding) (resolve-logic-value (cdr binding) bindings)))
          (reverse bindings)))

(defun collect-logic-variables (value)
  (cond
    ((logic-variable-p value) (list value))
    ((consp value)
     (append (collect-logic-variables (car value))
             (collect-logic-variables (cdr value))))
    (t '())))

(defun project-logic-bindings (bindings variables)
  (let ((normalized (normalize-logic-bindings bindings)))
    (remove nil
            (mapcar (lambda (variable)
                      (assoc variable normalized))
                    variables))))

(defun logic-rule-indicator-p (value)
  (and (symbolp value)
       (or (string= (symbol-name value) ":-")
           (and (keywordp value)
                (string= (symbol-name value) "-")))))

(defun logic-rule-form-p (form)
  (and (consp form)
       (logic-rule-indicator-p (first form))))

(defun normalize-logic-rule-form (form)
  (unless (and (consp form) (consp (rest form)))
    (error "cl-weave: logic rule requires a head and optional body, got ~S." form))
  (make-logic-rule :head (second form)
                   :body (cddr form)))

(defun normalize-logic-program-entry (entry)
  (if (logic-rule-form-p entry)
      (normalize-logic-rule-form entry)
      entry))

(defun normalize-logic-program (program)
  (mapcar #'normalize-logic-program-entry program))

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
     :body (mapcar (lambda (goal)
                     (instantiate-logic-term goal mapping rule-id))
                   (logic-rule-body rule)))))

(defun logic-entry-head (entry)
  (if (logic-rule-p entry)
      (logic-rule-head entry)
      entry))

(defun logic-entry-body (entry)
  (if (logic-rule-p entry)
      (logic-rule-body entry)
      '()))

(defun logic-query (program clauses &key limit)
  (unless (or (null limit) (and (integerp limit) (plusp limit)))
    (error "cl-weave: logic-query limit must be NIL or a positive integer, got ~S."
           limit))
  (let ((normalized-program (normalize-logic-program program))
        (query-variables (remove-duplicates (collect-logic-variables clauses)
                                            :test #'eq)))
    (labels ((below-limit-p (results)
               (or (null limit) (< (length results) limit)))
             (solve-goals/k (pending bindings results next-rule-id continue)
               (cond
                 ((not (below-limit-p results))
                  (funcall continue results next-rule-id))
                 ((null pending)
                  (funcall continue
                           (cons (project-logic-bindings bindings query-variables)
                                 results)
                           next-rule-id))
                 (t
                  (solve-program-entry/k
                   normalized-program
                   (first pending)
                   (rest pending)
                   bindings
                   results
                   next-rule-id
                   continue))))
             (solve-program-entry/k (entries goal rest-goals bindings results
                                     next-rule-id continue)
               (if (or (null entries) (not (below-limit-p results)))
                   (funcall continue results next-rule-id)
                   (let* ((candidate (first entries))
                          (instantiated (if (logic-rule-p candidate)
                                            (instantiate-logic-rule candidate next-rule-id)
                                            candidate))
                          (head (logic-entry-head instantiated))
                          (body (logic-entry-body instantiated))
                          (advanced-rule-id (if (logic-rule-p candidate)
                                                (1+ next-rule-id)
                                                next-rule-id)))
                     (multiple-value-bind (next-bindings matched-p)
                         (unify-logic-values goal head bindings)
                       (if matched-p
                           (solve-goals/k
                            (append body rest-goals)
                            next-bindings
                            results
                            advanced-rule-id
                            (lambda (next-results final-rule-id)
                              (solve-program-entry/k (rest entries)
                                                     goal
                                                     rest-goals
                                                     bindings
                                                     next-results
                                                     final-rule-id
                                                     continue)))
                           (solve-program-entry/k (rest entries)
                                                  goal
                                                  rest-goals
                                                  bindings
                                                  results
                                                  advanced-rule-id
                                                  continue)))))))
      (nreverse
       (nth-value 0
         (solve-goals/k clauses nil nil 0
                        (lambda (results final-rule-id)
                          (declare (ignore final-rule-id))
                          (values results 0))))))))

(defun split-logic-where-forms (forms)
  (let ((limit nil)
        (limit-present-p nil)
        (clauses forms))
    (when (and clauses
               (consp (first clauses))
               (eq (first (first clauses)) :limit))
      (unless (= 2 (length (first clauses)))
        (error "cl-weave: :limit expects exactly one value, got ~S."
               (first clauses)))
      (setf limit (second (first clauses))
            limit-present-p t
            clauses (rest clauses)))
    (unless clauses
      (error "cl-weave: logic where macros require at least one relation clause."))
    (dolist (clause clauses)
      (unless (and (consp clause) (keywordp (first clause)))
        (error "cl-weave: logic clauses must be non-empty keyword relation lists, got ~S."
               clause)))
    (values clauses limit limit-present-p)))

(defmacro logic-where (facts &body forms)
  (multiple-value-bind (clauses limit limit-present-p)
      (split-logic-where-forms forms)
    `(logic-query ,facts ',clauses ,@(when limit-present-p `(:limit ,limit)))))

(defmacro logic-program (&body entries)
  `(list ,@(mapcar (lambda (entry) `',entry) entries)))

(defmacro logic-run (program &body forms)
  (multiple-value-bind (clauses limit limit-present-p)
      (split-logic-where-forms forms)
    `(logic-query ,program ',clauses ,@(when limit-present-p `(:limit ,limit)))))

(defmacro test-plan-where (plan &body forms)
  (multiple-value-bind (clauses limit limit-present-p)
      (split-logic-where-forms forms)
    `(query-test-plan ,plan ',clauses ,@(when limit-present-p `(:limit ,limit)))))

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

(defun query-test-plan (plan-or-program clauses &key limit)
  (logic-query (normalize-test-plan-query-input plan-or-program)
               clauses
               :limit limit))
