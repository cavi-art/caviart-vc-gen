;;; CAVIART-VCGEN - A verification condition generator for the CAVI-ART project
;;; developed originally at GPD UCM.
;;; Copyright (C) 2016 Santiago Saavedra López, Grupo de Programación Declarativa -
;;; Universidad Complutense de Madrid
;;;
;;; This file is part of CAVIART-VCGEN.
;;;
;;; CAVIART-VCGEN is free software: you can redistribute it and/or modify
;;; it under the terms of the GNU Affero General Public License as
;;; published by the Free Software Foundation, either version 3 of the
;;; License, or (at your option) any later version.
;;;
;;; CAVIART-VCGEN is distributed in the hope that it will be useful,
;;; but WITHOUT ANY WARRANTY; without even the implied warranty of
;;; MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
;;; GNU Affero General Public License for more details.
;;;
;;; You should have received a copy of the GNU Affero General Public License
;;; along with CAVIART-VCGEN.  If not, see <http://www.gnu.org/licenses/>.


(in-package :cl-user)

(declaim (optimize debug))

(eval-when (:compile-toplevel :load-toplevel :execute)
  (labels
      ((delete-package-recursive (package-identifier)
	 (let ((pkg (find-package package-identifier)))
	   (when pkg
	     (mapcar #'delete-package-recursive (package-used-by-list pkg))
	     (when (find-package package-identifier)
	       (delete-package pkg))))))
    (delete-package-recursive :caviart.vc-gen)))

(defpackage :ir.vc
  (:use)
  (:documentation "Verification conditions package. Defines no symbols
  a priori, but will later export those of core."))

;; (delete-package :ir.vc.core)
;; (delete-package :ir.vc.core.impl)

(defpackage :ir.vc.core
  (:use)

  ;; Runtime directives
  (:import-from :cl :declare :optimize :speed :debug :safety)
  (:export :declare :optimize :speed :debug :safety)

  ;; Logical connections
  (:import-from :cl :and :or)
  (:export :and :or)

  ;; We can use the same `the' and `type' as CL.
  (:export :the :type)

  ;; Our basic macro for defining everything else.
  (:export :verification-unit)

  ;; Basic types
  (:export :int)
  (:export :bool :true :false)

  (:export :*assume-verified* :*verify-only* :*external-functions*)

  ;; Our own DSL keywords
  (:export :assertion :precd :postcd)
  (:export :define :lettype :letvar :letconst :let :let* :letfun :case :default "@" "@@")

  ;; Assertion comparators (will later be in another package)
  (:shadowing-import-from :cl :=)
  (:export :=))

(defpackage :ir.vc.core.impl
  (:documentation "Functionality for generating Verification Conditions for later use in Why3")
  (:use :cl :ir.utils)
  (:import-from :ir.vc.core :assertion :precd :postcd :default :*external-functions*)
  (:export :verifier-identifier :verifier-output :verifier-output-comment *entry-points*
	   :remove-decls))

(in-package :ir.vc.core.impl)

(defun get-toplevel-functions (clir)
  (loop
     for a in clir
     when (eq (car a) 'ir.vc.core:define) collect (cadr a)))

(defun get-toplevel-definitions (clir)
  (loop
     for a in clir
     when (eq (car a) 'ir.vc.core:define) collect (cdr a)))


(defun verifier-identifier (symb)
  "Sanitizes a symbol name so that it is a valid identififer in the
  underlying verifier grammar."
  (symbol-name symb))


(defun verifier-output (&rest elements)
  (write-to-string elements))


(defun verifier-output-comment (&rest forms)
  (format t " (* ~s *)~%"
	  (with-output-to-string (s)
	    (apply #'format s forms))))


(defun get-precondition (function-definition)
  (let* ((body (function-body function-definition))
	 (declarations (cdr (assoc 'declare body)))
	 (assertions (cdr (assoc 'assertion declarations)))
	 (precd (assoc 'precd assertions)))
    (when precd
      (cadr precd))))

(defun get-postcondition (function-definition)
  (let* ((body (function-body function-definition))
	 (declarations (cdr (assoc 'declare body)))
	 (assertions (cdr (assoc 'assertion declarations)))
	 (postcd (assoc 'postcd assertions)))
    (when postcd
      (cadr postcd))))


(defparameter *entry-points* nil)
(defvar *external-functions* nil)


;;;; Grammar follows 
(defmacro ir.vc.core:verification-unit (package-id &key sources uses documentation verify-only assume-verified)
  (declare (ignorable sources))
  (let ((pkg (get-package-symbol package-id)))
      `(progn (when (find-package ,pkg)
		(unuse-package ',@uses ,pkg)
		(delete-package ,pkg))
	      (defpackage ,pkg
		 (:use ,@uses)
		 (:documentation ,documentation))
	    (in-package ,pkg)
	    (cl:mapcar (cl:lambda (f) (cl:push f ir.vc.core:*assume-verified*)) ,assume-verified)
	    (cl:mapcar (cl:lambda (f) (cl:push f ir.vc.core:*verify-only*)) ,verify-only)
	    ;; (verifier-output-comment "Parsing units in package ~a~%" ,package-id)
	    )))


(defmacro ir.vc.core:lettype (type-symbol param-list type-boolean-expression optional-data)
  (declare (ignorable type-boolean-expression))
  `(prog1
       (verifier-output 'type ,type-symbol ,param-list)
     (verifier-output-comment-to-string ,optional-data)))


(defvar *premise-list* nil)
(defvar *goal-set* nil)
(defvar *variable-list* nil)
(defvar *function-list* nil)
(defvar *current-function* nil)

(defun remove-decls (body &optional declarations)
  "Gets the `declare'-d and docstring forms (if there are any) of a
defun-ish body and the resulting body as values."
  (declare (type list body declarations))
  (let ((form (car body)))
    (typecase form
      ((or symbol nil) (values body (reverse declarations)))
      (cons (if (eq (car form) 'declare)
		(remove-decls (cdr body) (cons form declarations))
		(values body (reverse declarations)))))))

;; TODO at some point, replace function "list" with a proper struct
(defun function-body (function-definition)
  (cdddr function-definition))

(defun typed-lambda-list (function-definition)
  "Gets the lambda list of a function definition. E.g., simple
   accessor"
  (second function-definition))

(defun typed-result-list (function-definition)
  "Gets the result list of a function definition. E.g., simple
   accessor"
  (third function-definition))

(defun get-current-typed-result-list ()
  (typed-result-list (assoc *current-function* *function-list*)))


(defmacro with-empty-premise-list (&body body)
  `(let ((*premise-list* nil))
     ,@body))

(defmacro with-premise (content &body body)
  (if (macroexpand-1 content)
      `(let ((*premise-list* (cons ,content *premise-list*)))
	 ,@body)
      `(progn ,@body)))

(defmacro terminal-expression (expression &key type)
  "We have to do postcd/{result=expression}"
  (declare (ignore type))
  `(output-goal (rename-symbols (@postcd *current-function*)
				(drop-types (get-current-typed-result-list))
				',expression)))

(defmacro with-variables (typed-variable-list &body body)
  "Introduces variables in the `premise-list' and `symbol-macrolet's
  those variables so that when they are `macroexpand-1'-ed they will
  be known as variables and the postcondition will be well formed."
  (if typed-variable-list
      (labels ((symbol-macroletize (typed-var)
		 (destructuring-bind (var-name var-type) typed-var
		   `(,var-name (terminal-expression (,var-name) :type ,var-type)))))
	`(with-premise (list :forall ',typed-variable-list)
	   (symbol-macrolet ,(mapcar #'symbol-macroletize typed-variable-list))
	   ,@body))
      `(progn ,@body)))

(defmacro with-function-definition (new-definition &body body)
  `(let ((*function-list* (cons ,new-definition *function-list*)))
     ,@body))

(defmacro with-current-function (function-name &body body)
  `(let ((*current-function* ,function-name))
     ,@body))


(defun @precd (function-name function-args)
  (let* ((f (assoc function-name (append *function-list* *external-functions*)))
	 (precd (get-precondition f))
	 (parameter-list (drop-types (typed-lambda-list f))))
    (if precd
	;; Rename parameters
	(rename-symbols precd parameter-list function-args)
	;; Else
	'true
	;; (list 'THE_PRECD_PLACEHOLDER_FOR
	;;       function-name
	;;       (list parameter-list function-args))
	)))

(defun @postcd (function-name &optional function-args result-args)
  (let* ((f (assoc function-name (append *function-list* *external-functions*)))
	 (postcd (get-postcondition f))
	 (parameter-list (drop-types (typed-lambda-list f)))
	 (result-list (drop-types (typed-result-list f))))
    (if postcd
	;; Rename lambda parameters and result parameters
	(rename-symbols
	 (rename-symbols postcd parameter-list function-args)
	 result-list result-args)
	;; Else
	(list 'THE_POSTCD_PLACEHOLDER_FOR function-name
	      (list parameter-list function-args)
	      (list result-list result-args))
	)))


(defun rename-symbols (formula original-symbols new-symbols &optional rec)
  (unless (or (not new-symbols) rec)
    (format t "Renaming ~S from ~s in terms of ~s~%" formula original-symbols new-symbols))
  (if (eq nil new-symbols)
      formula
      ;; Simple s-exp tree walker
      (typecase formula
	(nil nil)
	(symbol (let ((p (position formula original-symbols)))
		  (if p
		      (nth p new-symbols)
		      formula)))
	(cons (cons (rename-symbols (car formula) original-symbols new-symbols t)
		    (rename-symbols (cdr formula) original-symbols new-symbols t)))
	(t formula))))


(defmacro with-goal-set (&body body)
  `(let ((*goal-set* nil))
     (let ((result (progn ,@body)))
       (values *goal-set* result))))

(defun @-p (form)
  "Returns whether the form is a funcall."
  (and (consp form)
       (eq 'ir.vc.core:@
	   (car form))))

(defmacro expr-postcondition (form &optional results)
  "Gets the postcondition of an expression, if that expression is a
  funcall. If it is not, it returns NIL (which is a suitable return
  value for `with-premise')."
  (when (@-p form)
    `(@postcd ',(cadr form) ',(cddr form) ',results)))

(defmacro assume-binding (lhs form &body body)
  (if lhs
      `(with-premise (list 'ir.vc.core:@ '= ',lhs ',form)
	 (with-premise (expr-postcondition ',form ,lhs)
	   ,@body))))


(defmacro ir.vc.core:define (&whole definition
			       function-name typed-lambda-list result-arg
			     &body full-body)
  "`DEFINE' introduces a set of goals. There should be pre/post
  conditions in this body, and from the expression (likely a letfun)
  we should increase our goal-set until we finally prove the latest
  expression implies the postcondition. For the moment, a define is
  self-contained, meaning definitions inside cannot call another
  define."
  (declare (ignorable result-arg full-body))
  (let ((body (remove-decls (function-body (cdr definition)))))
    `(defun ,function-name ()
       (with-goal-set
	 (with-empty-premise-list
	   (with-variables ,typed-lambda-list
	     (with-function-definition ',(cdr definition)
	       (with-current-function ',function-name
		 ,@body))))))))

(defun drop-types (typed-var-list)
  (mapcar #'car typed-var-list))

(defun drop-types-from-case-pattern (pattern)
  (typecase pattern
    (symbol pattern)
    (cons (case (car pattern)
	    (ir.vc.core:the (third pattern)
			    )
	    (ir.vc.core:@ pattern)
	    ;; Unmatched case TUPLE
	    ))))

(defun case-alternative (case-condition)
  (lambda (alt)
    (destructuring-bind (pattern form) alt
      `(assume-binding ,(drop-types-from-case-pattern pattern) ',case-condition
	 ,form))))

(defun case-default-p (alt)
  (eq (car alt)
      'default))

(defun case-alternative-default (condition default-alternative alternative-list)
  (if alternative-list
      (let ((pattern (caar alternative-list)))
	`(with-premise (list 'ir.vc.core:@ '<> ,(drop-types-from-case-pattern pattern) ',condition)
	   ,(case-alternative-default condition default-alternative (cdr alternative-list))))
      (let ((default-body (second default-alternative)))
	default-body)))

(defmacro ir.vc.core:case (condition &body alternative-list)
  "A `ir.vc.core:CASE' with n alternatives will generate n goals, one
  per alternative, sequentially."
  (let ((non-default-alternative-list (remove-if #'case-default-p alternative-list))
	(default-alternative-list (remove-if-not #'case-default-p alternative-list)))
    (let ((default-alternative (car default-alternative-list)))
      (assert (eq nil (cdr default-alternative-list)))
      `(let ((case-condition ',condition))
	 (declare (ignore case-condition))
	 ,@(mapcar (case-alternative condition) non-default-alternative-list)
	 ,(when default-alternative
		(case-alternative-default condition default-alternative non-default-alternative-list))))))

(defmacro ir.vc.core:the (expr-type value)
  `(terminal-expression (,value) :type ,expr-type))

(defmacro maybe-output-precd-goal (val)
  (when (@-p val)
    `(output-goal (@precd ',(cadr val) ',(cddr val)))))

(defmacro ir.vc.core:let (typed-var-list val &body body)
  "Lexically binds a var, syntax is: (let var val body-form). It can
   destructure tuples as (let (a b) (list a b) a)"
  (assert (not (cdr body))) ;; Only one expression
  (if (and (= 1 (length typed-var-list))
	   (= 2 (length (car typed-var-list))))
      `(with-variables ,typed-var-list
	 (maybe-output-precd-goal ,val)
	 (with-premise (@precd ',(cadr val) ',(cddr val))
	   (assume-binding ,(car (drop-types typed-var-list)) ,val
	     ;; TODO Warning it only works for let with one element in lhs see `car' above
	     ,@body)))
      (or nil
	  (error "This let binding is not supported: ~S = ~S" typed-var-list val))))

(defmacro ir.vc.core:@ (function-name &rest rest)
  "We will use this macro to call all further functions. Depending
  on whether they already have pre/post conditions on them, we will
  terminate the goal or pursue further by interpreting the next
  function."
  (let ((precd (gensym))
	(postcd (gensym)))
    `(let ((,precd (@precd ',function-name ',rest))
	   (,postcd (@postcd ',function-name ',rest (drop-types (get-current-typed-result-list)))))
       (output-goal ,precd)

       (with-premise ,precd
	 (macrolet ((ir.vc.core:the (type value) (declare (ignore type)) value))
	   (if ,postcd
	       (with-premise ,postcd
		 (terminal-expression ((ir.vc.core:@ ,function-name ,@(mapcar #'macroexpand-1 rest)))))
	       (terminal-expression ((ir.vc.core:@ ,function-name ,@(mapcar #'macroexpand-1 rest))))))))))

(defun output-goal (target)
  (when (not (eq target 'true))
    (push (list (reverse *premise-list*) target) *goal-set*)))

;;;; End of grammar. 




(defun clir-formula-to-string (formula)
  (labels ((is-infix (op)
	     (and (symbolp op)
		  (member op
			  '(+ - * / < <= >= = > % <>)
			  :test (lambda (a b) (string-equal (symbol-name a) (symbol-name b))))))
	   (clir-term-to-string (term)
	     (typecase term
	       (number term)
	       (symbol term)
	       (string term)
	       (cons (case (car term)
		       (quote (second term))
		       (ir.vc.core:the (third term))
		       (ir.vc.core:@ (apply-predicate (rest term)))
		       (t (error "Term ~S not understood." term))))
	       (t (error "Term ~S not understood." term))))
	   (apply-predicate (p)
	     (if (is-infix (first p))
		 (format nil "~A ~A ~A" (clir-term-to-string (second p)) (first p) (clir-term-to-string (third p)))
		 (format nil "~A(~{~A~^,~})" (first p) (mapcar #'clir-term-to-string (rest p))))))
    (typecase formula
      (symbol formula)
      (string formula)
      (number formula)
      (cons (case (car formula)
	      (:forall (format nil "forall ~:{(~A:~A)~:^,~}. " (second formula)))
	      (the_postcd_placeholder_for (format nil "POSTCD[~A]" (rest formula)))
	      (the_precd_placeholder_for "true")
	      (ir.vc.core:@ (apply-predicate (rest formula)))
	      (t (error "Formula ~S not understood. (car=~S)" formula (car formula)))))
      (t (error "Formula ~S not understood." formula)))))

(defun clir-premises-to-string (premises)
  (flet ((not-quantifier (premise)
	   (or (not (consp premise))
	       (not (member (car premise) (list :forall :exists))))))
    (when premises
      (concatenate 'string (format nil "~(~A~)~@[ -> ~]"
				   (clir-formula-to-string (first premises))
				   (and (not-quantifier (first premises))
					(rest premises)))
		   (clir-premises-to-string (rest premises))))))

(defun clir-goal-to-string (goal)
  (clir-premises-to-string (append (first goal) (rest goal))))



(defmacro quantified-lambda-params (lambda-params)
  "Adds forall quantifiers for the received typed parameters. This is
  useful for generating goals involving preconditions."
  `'(:forall . ,lambda-params))


(defun load-file (pathname)
  "Loads a file eval'uating package changes, so that identifiers will
get read and `INTERN'-ed on their proper packages."
  (with-throwaway-package (:ir.vc.core :ir.vc.builtins :ir.vc) (:ir)
    ;; We need to use the IR package so that we import the
    ;; verification-unit construct in order to `EVAL' it on the `LOOP'
    ;; to make the new package definition.
    (with-open-file (clir-stream pathname)
      (loop
	 for a = (read clir-stream nil)
	 while a
	 if (and (consp a)
		 (symbolp (car a))
		 (string-equal (symbol-name (car a))
			       "verification-unit"))
	 collect (progn (eval a) a)
	 else
	 collect a))))

(defun eval-clir-file (pathname)
  (with-throwaway-package (:ir.vc.core :ir.vc.builtins :ir.vc) (:ir)
    (with-open-file (clir-stream pathname)
      (loop for a = (read clir-stream nil)
	 while a
	 collect (eval a)))))



(setf *entry-points* nil)

(defparameter *test-file* "../test/factorial.clir")


(caddr (load-file *test-file*))

;; (IR.VC.CORE:DEFINE FACTORIAL::FACT
;;     ((FACTORIAL::N IR.VC.CORE:INT))
;;     ((FACTORIAL::RESULT IR.VC.CORE:INT))
;;   (DECLARE
;;    (ASSERTION (PRECD (IR.VC.CORE:@ IR.VC.BUILTINS:>= FACTORIAL::N 0))
;;     (POSTCD
;;      (IR.VC.CORE:@ = FACTORIAL::RESULT
;;                    (IR.VC.CORE:@ FACTORIAL::FACTORIAL FACTORIAL::N)))))
;;   (IR.VC.CORE:CASE FACTORIAL::N
;;     ((IR.VC.CORE:THE IR.VC.CORE:INT 0) (IR.VC.CORE:THE IR.VC.CORE:INT 1))
;;     (DEFAULT
;;      (IR.VC.CORE:LET ((FACTORIAL::N1 IR.VC.CORE:INT))
;;          (IR.VC.CORE:@ IR.VC.BUILTINS:- FACTORIAL::N
;;                        (IR.VC.CORE:THE IR.VC.CORE:INT 1))
;;        (IR.VC.CORE:LET ((FACTORIAL::F1 IR.VC.CORE:INT))
;;            (IR.VC.CORE:@ FACTORIAL::FACT FACTORIAL::N1)
;;          (IR.VC.CORE:@ IR.VC.BUILTINS:* FACTORIAL::N FACTORIAL::F1))))))

;; (multiple-value-bind (a b) (factorial::fact)
;;   (values
;;    (mapcar #'clir-goal-to-string a)
;;    (length a)))



(setf *goal-set* nil)

;; (eval-clir-file *test-file*)

;; (simple::test-define)

;; (setf *entry-points* (get-toplevel-definitions (load-file *test-file*)))



