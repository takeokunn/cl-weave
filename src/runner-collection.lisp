(in-package #:cl-weave)

(defun suite-hook-path (suite phase)
  (append (mapcar #'suite-name (rest (suite-lineage suite)))
          (list (string-downcase (symbol-name phase)))))

(defun make-suite-hook-event (suite phase causes)
  (make-test-event
   :status :error
   :path (suite-hook-path suite phase)
   :condition (make-condition 'hook-failure :phase phase :causes causes)
   :elapsed-internal-time 0))

(defun collect-suite-events/k
    (suite control continue filter &optional ancestor-focused suppressed-status suppressed-reason inherited-execution-mode)
  (if (or (execution-control-stopped control)
          (not (selected-suite-p suite filter ancestor-focused)))
      (funcall continue '())
      (let ((active-execution-mode
              (effective-suite-execution-mode suite inherited-execution-mode)))
        (multiple-value-bind (active-status active-reason)
            (suite-suppression suite suppressed-status suppressed-reason)
          (if active-status
              (collect-children/k
               suite
               (ordered-children suite (suite-children suite))
               control
               continue
               filter
               ancestor-focused
               active-status
               active-reason
               active-execution-mode)
              (let ((before-errors
                      (call-hooks/collect-errors (suite-hook suite before-all))))
                (labels ((finish (events)
                           (let* ((after-errors
                                   (call-hooks/collect-errors
                                    (reverse (suite-hook suite after-all))))
                                  (all-events
                                    (append
                                     (when before-errors
                                       (list (record-event/control
                                              control
                                              (make-suite-hook-event
                                               suite :before-all before-errors))))
                                     events
                                     (when after-errors
                                       (list (record-event/control
                                              control
                                              (make-suite-hook-event
                                               suite :after-all after-errors)))))))
                             (funcall continue all-events))))
                  (if before-errors
                      (finish '())
                      (collect-children/k
                       suite
                       (ordered-children suite (suite-children suite))
                       control
                       #'finish
                       filter
                       ancestor-focused
                       nil
                       nil
                       active-execution-mode)))))))))

(defun collect-children/k
    (suite children control continue filter &optional ancestor-focused suppressed-status suppressed-reason execution-mode)
  (macrolet ((recur (remaining next-continue)
               `(collect-children/k
                 suite
                 ,remaining
                 control
                 ,next-continue
                 filter
                 ancestor-focused
                 suppressed-status
                 suppressed-reason
                 execution-mode)))
    (labels ((continue-with-tail (head-events remaining)
               (recur remaining
                      (lambda (tail)
                       (funcall continue (append head-events tail)))))
             (continue-with-event (event)
               (if (execution-control-stopped control)
                   (funcall continue (list event))
                   (recur (rest children)
                          (lambda (tail)
                            (funcall continue (cons event tail)))))))
      (if (or (null children) (execution-control-stopped control))
          (funcall continue '())
          (let ((child (first children)))
            (multiple-value-bind (step payload rest-children)
                (describe-event-collection-step
                 suite
                 child
                 children
                 control
                 filter
                 ancestor-focused
                 suppressed-status
                 suppressed-reason
                 execution-mode)
              (ecase step
                (:skip
                 (recur (rest children) continue))
                (:collect-suite
                 (collect-suite-events/k
                  child
                  control
                  (lambda (events)
                    (if (execution-control-stopped control)
                        (funcall continue events)
                        (continue-with-tail events (rest children))))
                  filter
                  payload
                  suppressed-status
                  suppressed-reason
                  execution-mode))
                (:collect-concurrent
                 (continue-with-tail
                  (mapcar (lambda (event)
                            (record-event/control control event))
                          (run-concurrent-test-cases suite payload))
                  rest-children))
                (:collect-test
                 (continue-with-event payload)))))))))

(defun call-with-collection-context
    (suite name-filter location-filter test-path-filter include-tags exclude-tags shard order seed
     retry timeout-ms max-workers continue)
  (let* ((filter (make-selection-filter
                  :focus-enabled (focused-suite-p suite)
                  :name-filter (normalized-test-filter name-filter)
                  :location-filter (normalize-location-filter location-filter)
                  :test-path-filter test-path-filter
                  :include-tags (normalize-tags include-tags "include-tags")
                  :exclude-tags (normalize-tags exclude-tags "exclude-tags")))
         (normalized-shard (normalize-shard shard))
         (normalized-order (normalize-sequence-order order))
         (normalized-seed (normalize-sequence-seed seed))
         (normalized-retry (normalize-retry-count retry))
         (normalized-timeout-ms (normalize-timeout-ms timeout-ms))
         (normalized-max-workers (normalize-max-workers max-workers)))
    (setf (selection-filter-shard-paths filter)
          (collect-shard-paths suite filter normalized-shard))
    (let ((*test-sequence-order* normalized-order)
          (*test-sequence-seed* normalized-seed)
          (*default-retry* normalized-retry)
          (*default-timeout-ms* normalized-timeout-ms)
          (*max-workers* normalized-max-workers))
      (funcall continue filter))))

(defun collect-events
    (suite &key name-filter location-filter test-path-filter include-tags exclude-tags bail shard
                  order seed retry timeout-ms max-workers)
  (with-runner-condition-propagation (nil)
    (call-with-collection-context
     suite
     name-filter
     location-filter
     test-path-filter
     include-tags
     exclude-tags
     shard
     order
     seed
     retry
     timeout-ms
     max-workers
     (lambda (filter)
       (collect-suite-events/k
        suite
        (make-execution-control :bail-limit (normalize-bail bail))
        #'identity
        filter)))))

(declaim (ftype (function (suite list function selection-filter &optional t t t t) *) collect-children-plan/k))

(defun collect-suite-plan/k
    (suite continue filter &optional ancestor-focused suppressed-status suppressed-reason inherited-execution-mode)
  (if (not (selected-suite-p suite filter ancestor-focused))
      (funcall continue '())
      (let ((active-execution-mode
              (effective-suite-execution-mode suite inherited-execution-mode)))
        (multiple-value-bind (active-status active-reason)
            (suite-suppression suite suppressed-status suppressed-reason)
          (collect-children-plan/k
           suite
           (ordered-children suite (suite-children suite))
           continue
           filter
           ancestor-focused
           active-status
           active-reason
           active-execution-mode)))))

(defun collect-children-plan/k
    (suite children continue filter &optional ancestor-focused suppressed-status suppressed-reason execution-mode)
  (macrolet ((recur (remaining next-continue)
               `(collect-children-plan/k
                 suite
                 ,remaining
                 ,next-continue
                 filter
                 ancestor-focused
                 suppressed-status
                 suppressed-reason
                 execution-mode)))
    (labels ((continue-with-tail (entries)
               (recur (rest children)
                      (lambda (tail)
                        (funcall continue (append entries tail)))))
             (continue-with-entry (entry)
               (recur (rest children)
                      (lambda (tail)
                       (funcall continue (cons entry tail))))))
      (if (null children)
          (funcall continue '())
          (let ((child (first children)))
            (multiple-value-bind (step payload)
                (describe-plan-collection-step
                 suite
                 child
                 filter
                 ancestor-focused
                 suppressed-status
                 suppressed-reason
                 execution-mode)
              (ecase step
                (:skip
                 (recur (rest children) continue))
                (:collect-suite
                 (collect-suite-plan/k
                  child
                  #'continue-with-tail
                  filter
                  payload
                  suppressed-status
                  suppressed-reason
                  execution-mode))
                (:collect-test
                 (continue-with-entry payload)))))))))

(defun collect-test-plan
    (suite &key name-filter location-filter test-path-filter include-tags exclude-tags
                  shard order seed retry timeout-ms)
  (call-with-collection-context
   suite
   name-filter
   location-filter
   test-path-filter
   include-tags
   exclude-tags
   shard
   order
   seed
   retry
   timeout-ms
   nil
   (lambda (filter)
     (collect-suite-plan/k suite #'identity filter))))
