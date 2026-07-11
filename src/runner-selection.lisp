(in-package #:cl-weave)

(defun focused-child-p (child)
  (cond
    ((suite-p child)
     (or (suite-focus child)
         (some #'focused-child-p (suite-children child))))
    ((test-case-p child)
     (test-case-focus child))))

(defun focused-suite-p (suite)
  (some #'focused-child-p (suite-children suite)))

(defun normalized-test-filter (filter)
  (when (and filter (not (string= filter "")))
    (string-downcase filter)))

(defun test-path-matches-filter-p (path filter)
  (or (null filter)
      (search filter
              (string-downcase (filter-path-string path))
              :test #'char=)))

(defun normalize-shard (shard)
  (when shard
    (unless (and (consp shard)
                 (integerp (first shard))
                 (integerp (second shard))
                 (null (cddr shard))
                 (<= 1 (first shard) (second shard)))
      (error "Shard must be NIL or (INDEX COUNT) with 1 <= INDEX <= COUNT: ~S" shard))
    shard))

(defun shard-includes-ordinal-p (ordinal shard)
  (or (null shard)
      (= (first shard)
         (1+ (mod (1- ordinal) (second shard))))))

(defun location-pathname-designator (designator)
  (etypecase designator
    (pathname (uiop:ensure-absolute-pathname designator))
    (string (uiop:ensure-absolute-pathname designator))))

(defun normalize-location-filter (location-filter)
  (when location-filter
    (mapcar #'location-pathname-designator location-filter)))

(defun test-location-pathname (test)
  (let ((file (getf (test-case-location test) :file)))
    (when file
      (location-pathname-designator file))))

(defun test-location-matches-filter-p (test location-filter)
  (or (null location-filter)
      (let ((pathname (test-location-pathname test)))
        (and pathname
             (member pathname location-filter :test #'equal)))))

(defun base-selected-test-case-p (suite test focus-enabled ancestor-focused name-filter location-filter)
  (and (or (not focus-enabled)
           ancestor-focused
           (test-case-focus test))
       (test-path-matches-filter-p (test-path suite test) name-filter)
       (test-location-matches-filter-p test location-filter)))

(defun collect-shard-paths (suite focus-enabled name-filter location-filter shard)
  (when shard
    (let ((paths (make-hash-table :test #'equal))
          (ordinal 0))
      (labels ((visit (current-suite ancestor-focused)
                 (dolist (child (suite-children current-suite))
                   (cond
                     ((suite-p child)
                      (visit child (or ancestor-focused (suite-focus child))))
                     ((test-case-p child)
                      (when (base-selected-test-case-p
                             current-suite
                             child
                             focus-enabled
                             ancestor-focused
                             name-filter
                             location-filter)
                        (incf ordinal)
                        (when (shard-includes-ordinal-p ordinal shard)
                          (setf (gethash (test-path current-suite child) paths)
                                t))))))))
        (visit suite nil))
      paths)))

(defun normalize-sequence-order (order)
  (cond
    ((null order) :defined)
    ((eq order :random) :random)
    (t (error "Sequence order must be NIL or :RANDOM: ~S" order))))

(defun normalize-sequence-seed (seed)
  (cond
    ((null seed) 0)
    ((integerp seed) seed)
    (t (error "Sequence seed must be an integer: ~S" seed))))

(defun stable-string-hash (string seed)
  (let ((hash (mod (+ +stable-hash-offset+ seed) +stable-hash-modulus+)))
    (loop for char across string
          do (setf hash
                   (mod (* (logxor hash (char-code char))
                           +stable-hash-prime+)
                        +stable-hash-modulus+))
          finally (return hash))))

(defun sequence-suite-prefix (suite)
  (format nil "~{~A~^ > ~}" (mapcar #'suite-name (rest (suite-lineage suite)))))

(defun sequence-child-label (suite child)
  (format nil "~A :: ~A:~A"
          (sequence-suite-prefix suite)
          (cond
            ((suite-p child) "suite")
            ((test-case-p child) "test")
            (t "unknown"))
          (cond
            ((suite-p child) (suite-name child))
            ((test-case-p child) (test-case-name child))
            (t child))))

(defun ordered-children (suite children)
  (if (eq *test-sequence-order* :random)
      (stable-sort
       (copy-list children)
       #'<
       :key (lambda (child)
              (stable-string-hash
               (sequence-child-label suite child)
               *test-sequence-seed*)))
      children))

(defun selected-path-p (path shard-paths)
  (or (null shard-paths)
      (gethash path shard-paths)))

(defun selected-test-case-p (suite test focus-enabled ancestor-focused name-filter location-filter shard-paths)
  (let ((path (test-path suite test)))
    (and (base-selected-test-case-p suite test focus-enabled ancestor-focused name-filter location-filter)
         (selected-path-p path shard-paths))))

(defun selected-suite-p (suite focus-enabled ancestor-focused name-filter location-filter shard-paths)
  (some (lambda (child)
          (cond
            ((suite-p child)
             (let ((child-focused (or ancestor-focused (suite-focus child))))
               (and (or (not focus-enabled)
                        child-focused
                        (focused-child-p child))
                    (selected-suite-p
                     child
                     focus-enabled
                     child-focused
                     name-filter
                     location-filter
                     shard-paths))))
            ((test-case-p child)
             (selected-test-case-p
              suite
              child
              focus-enabled
              ancestor-focused
              name-filter
              location-filter
              shard-paths))
            (t nil)))
        (suite-children suite)))

(defun selected-child-suite-p
    (child focus-enabled child-focused name-filter location-filter shard-paths)
  (and (or (not focus-enabled)
           child-focused
           (focused-child-p child))
       (selected-suite-p child
                         focus-enabled
                         child-focused
                         name-filter
                         location-filter
                         shard-paths)))

(defun selected-child-test-p
    (suite child focus-enabled ancestor-focused name-filter location-filter shard-paths)
  (selected-test-case-p suite
                        child
                        focus-enabled
                        ancestor-focused
                        name-filter
                        location-filter
                        shard-paths))

