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


;; CLIR Core.

(cl:in-package :cl-user)
(defpackage :ir.rt
  (:use)
  (:documentation "Runtime package. Defines no symbols a priori."))

(defpackage :ir.rt.core.impl
  (:use :cl)
  (:export :assertion :get-package-symbol :assertion-decl-to-code :signature-to-typedecl
	   :lambda-list-type-decls :maybe-macroexpand))

(defpackage :ir.rt.core
  (:use)
  (:import-from :cl &allow-other-keys &body &key &rest)
  (:import-from :cl :declare :optimize :speed :debug :safety)
  (:import-from :cl :the :type :nil :t :car :cdr :length :and :or :list)

  (:export :verification-unit)
  (:export :list)
  (:export :int)
  (:export :bool :true :false)
  (:export :load :assertion :declare :var :the :type :optimize :speed :debug :safety)
  (:export :*assume-verified* :*verify-only*)
  (:export :define :lettype :letvar :letconst :let :let* :letfun :case "@" "@@"))


(in-package :ir.rt.core.impl)
;;;; Package ir.rt.core.impl follows.

;; Declare that "assertion" is a valid "declare" form.
(eval-when (:compile-toplevel :load-toplevel :execute)
  (declaim (declaration assertion)))

(defparameter *auto-macroexpand* t)

(defun get-package-symbol (input-package-symbol &optional (pkg "KEYWORD"))
  ;; (return-from get-package-symbol input-package-symbol)
  (if (stringp input-package-symbol)
      input-package-symbol
      (intern (symbol-name input-package-symbol) pkg)))

(defun assertion-decl-to-code (body-forms)
  (if (assoc 'declare body-forms)
      (let ((declarations (cdr (assoc 'declare body-forms))))
	(declare (cl:ignore declarations))
	body-forms)
      body-forms))

(defun maybe-macroexpand (forms)
  (if *auto-macroexpand*
      (mapcar #'macroexpand-1 forms)
      forms))

(defun lambda-list-type-decls (typed-lambda-list)
  (mapcar (lambda (e) (list 'type (cadr e) (car e)))
	  typed-lambda-list))

;;;; Package ir.rt.core must define vars before overriding package in cl-user.

(deftype ir.rt.core:int () `(cl:integer ,cl:most-negative-fixnum ,cl:most-positive-fixnum))
(deftype ir.rt.core:bool () '(cl:member ir.rt.core:true ir.rt.core:false))

;; We declaim assertion so that compiled files with assertions get no warnings
(declaim (declaration ir.rt.core:assertion))

(defparameter ir.rt.core:*assume-verified* nil)
(defparameter ir.rt.core:*verify-only* nil)

;; Override CL-USER environment to define package (CLIR entry point)

(defmacro ir.rt.core:verification-unit (package-id &key sources uses documentation verify-only assume-verified)
  (declare (ignorable sources))
  (let ((pkg (ir.rt.core.impl:get-package-symbol package-id)))
      `(progn (when (find-package ,pkg)
		(unuse-package ,@uses ,pkg)
		(delete-package ,pkg))
	      (defpackage ,pkg
		 (:use ,@uses)
		 (:documentation ,documentation))
	    (in-package ,pkg)
	    (cl:mapcar (cl:lambda (f) (cl:push f ir.rt.core:*assume-verified*)) ,assume-verified)
	    (cl:mapcar (cl:lambda (f) (cl:push f ir.rt.core:*verify-only*)) ,verify-only))))

(defun from-clir (clir-expr)
  "Returns a Common Lisp expression from a CLIR expression. I.e., this
  parses <form> entries in the grammar."
  (if (symbolp clir-expr)
      clir-expr ; It's a variable
      (case (car clir-expr)
	((ir.rt.core:var) (cadr clir-expr))
	((ir.rt.core:the) (third clir-expr))
	((ir.rt.core:@ ir.rt.core:@@ ir.rt.core:let ir.rt.core:letfun ir.rt.core:case) (macroexpand-1 clir-expr))
	(t (multiple-value-bind (expr expanded) (macroexpand-1 clir-expr)
	     (assert expanded)
	     expr)))))


(defun enclose-in-typed-return-type (return-lambda-list expr)
  "TODO Test with different values. Now we are cheating because CL
works with the 'any' (t) type."
  (declare (ignore return-lambda-list))
  (let ((result-type t))
    `(the ,result-type ,expr)))

(defmacro ir.rt.core:define (function-name typed-lambda-list result-lambda-list declaration &body full-body)
  (let ((function-lambda-list (mapcar #'car typed-lambda-list)))
    `(defun ,function-name ,function-lambda-list
       (declare ,@ (lambda-list-type-decls typed-lambda-list))
       ,declaration
       ,(enclose-in-typed-return-type result-lambda-list (from-clir (car full-body))))))


(defmacro ir.rt.core:lettype (type-symbol param-list type-boolean-expresssion optional-data)
  ;; TODO This is not working
  (declare (ignore optional-data))
  "Defines a type globally in the environment."
  `(cl:deftype ,type-symbol ,param-list ,type-boolean-expresssion)
  ;; TODO: Use `optional-data'
  )

(eval-when (:compile-toplevel :execute :load-toplevel)
  ;; We need these accessible on compiling so that
  ;; `defun-with-assertion' can be computed in compile-time
  (defun get-decls (body)
    "Gets the `declare'-d and docstring forms (if there are any) of a
defun-ish body"
    (let ((form (car body)))
      (if (or (and (listp form)
		   (eq (car form)
		       'declare))
	      (stringp form))
	  (cons form (get-decls (cdr body)))
	  nil)))

  (defun remove-decls (body)
    "Returns the `declare'-stripped forms of a `defun'-ish body so
that only executable things get there."
    (let ((form (car body)))
      (if (or (and (listp form)
		   (eq (car form)
		       'declare))
	      (stringp form))
	  (remove-decls (cdr body))
	  body))))



(defmacro ir.rt.core:letfun (function-decls &body body)
  "Defines a lexically bound set of possibly mutually-recursive
functions."
  (assert (not (cdr body))) ;; Only one expression
  `(labels
       ,(mapcar (lambda (f)
		  (let ((function-name (car f))
			(typed-lambda-list (cadr f))
			(function-lambda-list (mapcar #'car (cadr f)))
			;; (return-type (caddr f))
			(function-full-body (cdddr f)))
		    (let ((function-body (remove-decls function-full-body))
			  (function-decls (get-decls function-full-body)))
		      (assert (not (cdr function-body))) ;; Only one expression
		      `(,function-name
			,function-lambda-list
			(declare ,@ (lambda-list-type-decls typed-lambda-list))
			,@function-decls
			,(from-clir (car function-body))))))
		function-decls)
     ,(from-clir (car body))))

(defmacro ir.rt.core:let (typed-var-list val &body body)
  "Lexically binds a var, syntax is: (let var val body-form). It can
destructure tuples as (let (a b) (list a b) a)"
  (assert (not (cdr body))) ;; Only one expression
  (if (and (= 1 (length typed-var-list))
	   (= 2 (length (car typed-var-list))))
      `(let ((,(caar typed-var-list) (the ,(cadar typed-var-list) ,(from-clir val)))) ,(from-clir (car body)))

      ;; TODO Rewrite case for more than one variable
      (if (and (= 2 (length typed-var-list))
	       (symbolp (first typed-var-list)))

	  (destructuring-bind
		(var-name var-type) typed-var-list
	    `(let ((,var-name ,val))
	       (declare (type ,var-type ,var-name))
	       ,(from-clir (car body))))
		
	  ;; TODO Correctly treat constructor application
	  (labels
	      ((strip-var-types (typed-var-list)
		 "Strips variable types from a let-pattern (more
or less, a simple destructuring lambda list)"
		 (if (consp (car typed-var-list))
		     (cons (strip-var-types (car typed-var-list))
			   (strip-var-types (cdr typed-var-list)))
		     (car typed-var-list)))
	       (get-type-for-decl (typed-var-list)
		 (reduce #'get-type-for-decl-acc typed-var-list))

	       (get-type-for-decl-acc (typed-var-list acc)
		 (if (consp (car typed-var-list))
		     (nconc (get-type-for-decl typed-var-list) acc)
		     (cons 'type typed-var-list))))
	    `(destructuring-bind ,(strip-var-types typed-var-list) ,val
	       (declare ,@(get-type-for-decl typed-var-list))
	       ,(from-clir (car body)))))))

(defun from-clir-case-alt (pattern)
  (typecase pattern
    (symbol pattern)
    (cons (case (car pattern)
	    ((ir.rt.core:the) (third pattern))
	    ((ir.rt.core:@@) (error "case-constructor-destructuring is not yet implemented"))
	    (t (error "Unknown case alternative pattern: ~S" pattern))))))

(defmacro ir.rt.core:case (condition &body cases)
  "Defines a case conditional."
  ;; TODO The cases may be destructuring
  `(cl:case
       ,(from-clir condition)
     ,@ (cl:mapcar
	 (cl:lambda (c)
	   (cl:destructuring-bind
		 (pattern form) c
	     (list (from-clir-case-alt pattern) (from-clir form)))) cases)))


(defmacro ir.rt.core:@@ (cname &rest args)
  "Substitutes the @ function application form for the appropriate
executable funcall."
  `(funcall #',cname ,@ (mapcar #'from-clir args)))

(defmacro ir.rt.core:@ (fname &rest args)
  "Substitutes the @ function application form for the appropriate
executable funcall."
  (if (eq fname :external)
      `(funcall #'call-external ,@ (mapcar #'from-clir args))
      `(,fname ,@ (mapcar #'from-clir args))))


(defmacro package-protect (&body body)
  (let ((prev-package (gensym)))
    `(let ((,prev-package (package-name *package*)))
       (unwind-protect
	    (progn ,@body)
	 (eval (list 'in-package ,prev-package))))))


(defmacro with-changed-package (pkg &body body)
  `(package-protect
     (eval (list 'in-package ,pkg))
     ,@body))

(defmacro with-throwaway-package (uses nicknames &body body)
  "Evaluates content in a throwaway `GENSYM' package, which gets later
deleted."
  `(let ((pkg-name (symbol-name (gensym "THROWPKG"))))
     (make-package pkg-name :use ',uses :nicknames ,nicknames)
     (unwind-protect
	  (with-changed-package pkg-name
	    ,@body)
       (delete-package pkg-name)
       )))

(defun load-file (pathname)
  "Loads a file eval'uating package changes, so that identifiers will
get read and `INTERN'-ed on their proper packages."
  (with-throwaway-package (:IR) nil
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
	 collect (eval a)
	 else
	 collect a))))


(defun execute-clir-file (pathname)
  (macrolet
      ((with-changed-package (pkg &body body)
	 (let ((prev-package (package-name *package*)))
	   `(unwind-protect
		 (progn
		   (in-package ,pkg)
		   ,@body)
	      (in-package ,prev-package)))))
    (with-changed-package :ir
      (with-open-file (clir-stream pathname)
	(loop
	   for a = (read clir-stream nil)
	   while a
	   collect (eval a))))))


;; (ir.rt.core.impl::execute-clir-file #P"../test/inssort.clir")
;; (cons 'progn (mapcar #'macroexpand-1 (ir.rt.core.impl::load-file #P"../test/inssort.clir")))
