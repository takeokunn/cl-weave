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
        (let ((resolved '()))
          (dolist (part value (nreverse resolved))
            (push (resolve-logic-value part bindings) resolved)))
        value)))

(defun normalize-logic-bindings (bindings)
  (let ((normalized '()))
    (dolist (binding bindings normalized)
      (push (cons (car binding)
                  (resolve-logic-value (cdr binding) bindings))
            normalized))))

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

(defun logic-query (program clauses &key limit)
  (unless (or (null limit) (and (integerp limit) (plusp limit)))
    (error "cl-weave: logic-query limit must be NIL or a positive integer, got ~S."
           limit))
  (let ((normalized-program (normalize-logic-program program))
        (query-variables
          (remove-duplicate-logic-variables (collect-logic-variables clauses)))
        (frames (list (make-logic-search-frame clauses nil)))
        (results nil)
        (next-rule-id 0))
    (loop while (and frames (logic-below-limit-p results limit))
          do (let* ((frame (pop frames))
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
    (nreverse results)))

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
     (loop for tag in (test-plan-entry-tags entry)
           collect (list :tag path tag))
     (loop for dependency in (test-plan-entry-depends-on entry)
           collect (list :depends-on path dependency))
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
