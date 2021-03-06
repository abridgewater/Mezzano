;;;; Copyright (c) 2011-2015 Henry Harrington <henry.harrington@gmail.com>
;;;; This code is licensed under the MIT license.

;;; ERROR and the debugger.

(in-package :sys.int)

(declaim (special *error-output* *debug-io*))
(defparameter *infinite-error-protect* 0)
(defparameter *debugger-hook* nil)

(define-condition error (serious-condition)
  ())

(define-condition simple-error (simple-condition error)
  ())

(define-condition arithmetic-error (error)
  ((operation :initarg :operation
	      :reader arithmetic-error-operation)
   (operands :initarg :operands
	     :initarg nil
	     :reader arithmetic-error-operands)))

(define-condition array-dimension-error (error)
  ((array :initarg :array
	  :reader array-dimension-error-array)
   (axis :initarg :axis
	 :reader array-dimension-error-axis)))

(define-condition cell-error (error)
  ((name :initarg :name
	 :reader cell-error-name)))

(define-condition control-error (error)
  ())

(define-condition bad-catch-tag-error (control-error)
  ((tag :initarg :tag
        :reader bad-catch-tag-error-tag))
  (:report (lambda (condition stream)
             (format stream "Throw to unknown catch-tag ~S." (bad-catch-tag-error-tag condition)))))

(define-condition division-by-zero (arithmetic-error)
  ())

(define-condition invalid-index-error (error)
  ((array :initarg :array
	  :reader invalid-index-error-array)
   (axis :initarg :axis
	 :initform nil
	 :reader invalid-index-error-axis)
   (datum :initarg :datum
	  :reader invalid-index-error-datum))
  (:report (lambda (condition stream)
	     (if (invalid-index-error-axis condition)
		 (format stream "Invalid index ~S for array ~S. Must be non-negative and less than ~S."
			 (invalid-index-error-datum condition)
			 (invalid-index-error-array condition)
			 (array-dimension (invalid-index-error-array condition)
					  (invalid-index-error-axis condition)))
		 (format stream "Invalid index ~S for array ~S."
			 (invalid-index-error-datum condition)
			 (invalid-index-error-array condition))))))

(define-condition package-error (error)
  ((package :initarg :package
	    :reader package-error-package)))

(define-condition parse-error (error)
  ())

(define-condition print-not-readable (error)
  ((object :initarg :object
	   :reader print-not-readable-object)))

(define-condition program-error (error)
  ())

(define-condition invalid-arguments (program-error)
  ())

(define-condition simple-program-error (program-error simple-error)
  ())

(define-condition stream-error (error)
  ((stream :initarg :stream
	   :reader stream-error-stream)))

(define-condition end-of-file (stream-error)
  ())

(define-condition reader-error (parse-error stream-error)
  ())

(define-condition simple-reader-error (simple-condition reader-error)
  ())

(define-condition type-error (error)
  ((datum :initarg :datum
	  :reader type-error-datum)
   (expected-type :initarg :expected-type
		  :reader type-error-expected-type))
  (:report (lambda (condition stream)
	     (format stream "Type error. ~S is not of type ~S."
		     (type-error-datum condition)
		     (type-error-expected-type condition)))))

(define-condition simple-type-error (simple-condition type-error)
  ())

(define-condition unbound-variable (cell-error)
  ()
  (:report (lambda (condition stream)
	     (format stream "The variable ~S is unbound." (cell-error-name condition)))))

(define-condition undefined-function (cell-error)
  ()
  (:report (lambda (condition stream)
	     (format stream "Undefined function ~S." (cell-error-name condition)))))

(define-condition warning ()
  ())

(define-condition simple-warning (simple-condition warning)
  ())

(define-condition style-warning (warning)
  ())

(define-condition simple-style-warning (simple-condition style-warning)
  ())

(define-condition storage-condition (serious-condition) ())
(define-condition simple-storage-condition (simple-condition storage-condition) ())

(defun error (datum &rest arguments)
  (let ((condition datum))
    (let ((*infinite-error-protect* (1+ *infinite-error-protect*)))
      (cond ((<= *infinite-error-protect* 10)
             (setf condition (coerce-to-condition 'simple-error datum arguments))
             (signal condition))
            (t ;; gone into infinite-error-protect.
             (setf *print-safe* t)
             (dolist (x arguments)
               (write-char #\Space *debug-io*)
               (typecase x
                 (string (write-string x *debug-io*))
                 (symbol (cond ((and (symbol-package x) (packagep (symbol-package x)))
                                (write-string (package-name (symbol-package x)) *debug-io*)
                                (write-string "::" *debug-io*))
                               (t (write-string "#:" *debug-io*)))
                         (write-string (symbol-name x) *debug-io*))
                 (fixnum (write x :stream *debug-io*))
                 (t (write-string "#<unknown>" *debug-io*)))))))
    (invoke-debugger condition)))

(defun cerror (continue-format-control datum &rest arguments)
  (let ((condition (if (typep datum 'condition)
		       datum
		       (coerce-to-condition 'simple-error datum arguments))))
    (restart-case (progn (signal condition)
			 (invoke-debugger condition))
      (continue ()
	:report (lambda (stream)
		  (apply #'format stream continue-format-control arguments))))))

(defun assert-error (test-form datum &rest arguments)
  (let ((condition (if datum
		       (coerce-to-condition 'simple-error datum arguments)
		       (make-condition 'simple-error
				       :format-control "Assertion failed: ~S."
				       :format-arguments (list test-form)))))
    (cerror "Retry assertion." condition)))

(defun assert-prompt (place value)
  (format *debug-io* "~&Current value of ~S is ~S~%" place value)
  (format *debug-io* "~&Enter a new value for ~S.~%> " place)
  (eval (read *debug-io*)))

(defmacro assert (test-form &optional places datum-form &rest argument-forms)
  `(do () (,test-form)
     (assert-error ',test-form ,datum-form ,@argument-forms)
     ,@(mapcar (lambda (place)
		 `(setf ,place (assert-prompt ',place ,place)))
	       places)))

(defun break (&optional (format-control "Break") &rest format-arguments)
  (with-simple-restart (continue "Return from BREAK.")
    (let ((*debugger-hook* nil))
      (invoke-debugger
       (make-condition 'simple-condition
		       :format-control format-control
		       :format-arguments format-arguments))))
  nil)

(defun warn (datum &rest arguments)
  (let ((condition (coerce-to-condition 'simple-warning datum arguments)))
    (restart-case (signal condition)
      (muffle-warning ()
	:report "Ignore this warning."
	:test (lambda (c) (eq c condition))
	(return-from warn nil)))
    (if (typep condition 'style-warning)
	(format *error-output* "~&Style-Warning: ~A~%" condition)
	(format *error-output* "~&Warning: ~A~%" condition))
    nil))

(defun invoke-debugger (condition)
  (when *debugger-hook*
    (let ((old-hook *debugger-hook*)
	  (*debugger-hook* nil))
      (funcall old-hook condition old-hook)))
  (enter-debugger condition))
