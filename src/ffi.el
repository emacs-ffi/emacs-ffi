;;; ffi.el --- FFI for Emacs  -*- lexical-binding: t; -*-

;; Copyright (C) 2015-2024 Tom Tromey
;; Copyright (C) 2020-2024 Jonas Bernoulli
;; Copyright (C) 2024-2025 John Kitchin
;; Copyright (C) 2024-2025 Suhail

;; Author: Tom Tromey <tom@tromey.com>
;; Maintainer: Suhail <suhail@bayesians.ca>
;; Description: An FFI for Emacs based on dynamic module support
;; Keywords: extensions, internal, lisp, tools, unix
;; License: GNU General Public License >= 3
;; Package-Requires: ((emacs "25.1"))
;; Package-Version: 0.1.0.50-git
;; URL: https://github.com/emacs-ffi/emacs-ffi

;; This file is not part of GNU Emacs.

;; This is is free software: you can redistribute it and/or modify
;; it under the terms of the GNU General Public License as published by
;; the Free Software Foundation, either version 3 of the License, or
;; (at your option) any later version.

;; This is distributed in the hope that it will be useful,
;; but WITHOUT ANY WARRANTY; without even the implied warranty of
;; MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
;; GNU General Public License for more details.

;; You should have received a copy of the GNU General Public License
;; along with this.  If not, see <https://www.gnu.org/licenses/>.

;;; Commentary:

;; This is an FFI for Emacs.  It is based on libffi and relies on the
;; dynamic module support in order to be loaded into Emacs.  It is
;; relatively full-featured, but for the time being low-level.

;;; Code:

(require 'cl-macs)

;; this module is located in the directory where ffi.el is located.
(module-load (expand-file-name
              (concat "ffi-module" module-file-suffix)
              (file-name-directory (or load-file-name
                                       (buffer-file-name)))))


(gv-define-simple-setter ffi--mem-ref ffi--mem-set t)

(defmacro define-ffi-library (symbol name)
  "Create a pointer in SYMBOL that points to the c library of NAME.
NAME is a string that can be an absolute path or library name."
  (declare (debug (sexp form))
           (indent defun))
  (let* ((prefix (concat (symbol-name symbol) "--ffi-"))
         (library (cl-gensym prefix))
         (filename (cl-gensym prefix)))
    `(let nil
       (declare-function ,symbol nil)
       (defvar ,library nil)
       (defvar ,filename ,name)
       (defun ,symbol ()
         (or ,library
             (setq ,library (ffi--dlopen ,filename))))
       (put #',symbol 'function-documentation
            (format "Returns a pointer to the %s library." ,filename))
       ',symbol)))

(declare-function ffi--prep-cif "ffi-module.c")
(defmacro define-ffi-function (name c-name return args library &optional docstring)
  "Create an Emacs function from a c-function.
NAME is a symbol for  the Emacs function to create.
C-NAME is a string of the c-function to use.
RETURN is a type-keyword or (type-keyword docstring)
ARGS is a list of type-keyword or (type-keyword name &optional arg-docstring)
LIBRARY is a symbol usually defined by `define-ffi-library'
DOCSTRING is a string for the function to be created.

An overall docstring is created for the function from the arg and return
docstrings."
  (declare (debug (sexp form form form sexp &optional form))
           (indent defun))
  (let* ((return-type (if (listp return)
                          (car return)
                        ;; anything else we use as is
			return))
         (arg-names (mapcar (lambda (arg)
	        	      (if (listp arg)
                                  ;; assume list (type-keyword name &optional doc)
	        		  (cl-second arg)
	        		(cl-gensym)))
	        	    args))
         (return-docstring (format "Returns: %s (%s)"
				   (if (listp return)
				       (cl-second return)
				     (format "%s%s" c-name arg-names))
				   return-type))
         (prefix (concat (symbol-name name) "--ffi-"))
         (fn (cl-gensym prefix))
         (cif (cl-gensym prefix)))
    `(let* ((arg-types
             (vconcat (mapcar (lambda (arg)
	        	        (if (listp arg)
                                    ;; assume list (type-keyword name &optional doc)
                                    (symbol-value (car arg))
	        	          (symbol-value arg)))
	        	      ',args)))
            (arg-docstring
             (mapconcat
              'identity
	      (cl-mapcar (lambda (name type arg-doc)
	        	   (format "%s (%s) %s"
	        		   (upcase (symbol-name name))
	        		   type
	        		   arg-doc))
	        	 ',arg-names arg-types
                         (mapcar (lambda (arg)
	        		   (cond
	        		    ((keywordp arg)
	        		     "")
	        		    ((and (listp arg) (= 3 (length arg)))
	        		     (cl-third arg))
	        		    (t "")))
	        		 ',args))
	      "\n")))
       (declare-function ,name nil)
       (defvar ,fn nil)
       (defvar ,cif (ffi--prep-cif ,return-type arg-types))
       (defun ,name (,@arg-names)
         ,docstring
         (unless ,fn
	   (setq ,fn (ffi--dlsym ,c-name (,library))))
         ;; FIXME do we even need a separate prep?
         (ffi--call ,cif ,fn ,@arg-names))
       (put #',name 'function-documentation
            (concat ,docstring
                    (when ,docstring "\n\n")
                    arg-docstring
                    "\n\n"
                    ,return-docstring))
       ',name)))

(declare-function ffi--call "ffi-module.c")
(defun ffi-lambda (function-pointer return-type arg-types)
  "Create a callable Lisp function for a foreign function.
FUNCTION-POINTER is the address of the C function (can be obtained via
`ffi--dlsym').  RETURN-TYPE is the FFI type specifier for the return
value.  ARG-TYPES is a list of FFI type specifiers for arguments.

The returned lambda can be called with arguments matching ARG-TYPES, however,
this isn't enforced."
  (let ((cif (ffi--prep-cif return-type (vconcat arg-types))))
    (lambda (&rest args)             ; lame
      (apply #'ffi--call cif function-pointer args))))

(defsubst ffi--align (offset align)
  "Return OFFSET aligned to ALIGNMENT boundary.
Returns smallest value >= OFFSET that is a multiple of ALIGN.
This is an inline helper for memory layout calculations."
  (+ offset (mod (- align (mod offset align)) align)))

(declare-function ffi--type-alignment "ffi-module.c")
(declare-function ffi--type-size "ffi-module.c")
(defun ffi--lay-out-struct (types)
  "Calculate field offsets for a struct with given TYPES.
TYPES is a list of FFI type specifiers.
Returns a list of byte offsets for each field, considering alignment.

This handles struct padding according to each type's alignment requirements.
Uses `ffi--align' to compute each field's starting position."
  (let ((offset 0))
    (mapcar (lambda (this-type)
              (setf offset (ffi--align offset
                                       (ffi--type-alignment this-type)))
              (let ((here offset))
                (cl-incf offset (ffi--type-size this-type))
                here))
            types)))

(defun ffi--struct-union-helper (name slots definer-function layout-function)
  "Internal helper for defining struct/union types.
NAME is the symbol for the new type.
SLOTS is a list of (FIELD-NAME :type TYPE-SYMBOL [DOC]) entries.
DEFINER-FUNCTION is either `ffi-defstruct' or `ffi-defunion'.
LAYOUT-FUNCTION calculates field offsets (e.g. `ffi--lay-out-struct').

Generates code as data that includes:
1. A type definition variable NAME
2. Inline accessor functions for each field
3. Offset calculations using LAYOUT-FUNCTION

The first element of SLOTS may be a docstring for the type.
Accessors are named NAME-FIELD-NAME using `cl-defsubst' for inline expansion."
  (cl-assert (symbolp name))
  (let* ((docstring (if (stringp (car slots))
                        (pop slots)))
         (conc-name (concat (symbol-name name) "-"))
         (result-forms ())
         (field-types (mapcar (lambda (slot)
                                (cl-assert (eq (cadr slot) :type))
                                (symbol-value (cl-caddr slot)))
                              slots))
         (field-offsets (funcall layout-function field-types)))
    (push `(defvar ,name nil ,docstring)
          result-forms)
    (push `(setq ,name (apply #',definer-function ',field-types))
          result-forms)
    (cl-mapc
     (lambda (slot type offset)
       (let ((getter-name (intern (concat conc-name
                                          (symbol-name (car slot)))))
             (offsetter (if (> offset 0)
                            `(ffi-pointer+ object ,offset)
                          'object)))
         ;; One benefit of using defsubst here is that we don't have
         ;; to provide a GV setter.
         (push `(cl-defsubst ,getter-name (object)
                  (ffi--mem-ref ,offsetter ,type))
               result-forms)))
     slots field-types field-offsets)
    (cons 'progn (nreverse result-forms))))

(declare-function ffi--define-struct "ffi-module.c")
(defmacro define-ffi-struct (name &rest slots)
  "Like a limited form of `cl-defstruct', but works with foreign objects.
NAME must be a symbol.  SLOTS is a list with each SLOT of the
form `(SLOT-NAME :type TYPE)', where SLOT-NAME is a symbol and TYPE is
an FFI type descriptor.  The first element of SLOTS may be a docstring
for the struct."
  (declare (debug (sexp &rest form))
           (indent defun))
  (ffi--struct-union-helper name slots #'ffi--define-struct
                            #'ffi--lay-out-struct))

(declare-function ffi--define-union "ffi-module.c")
(defmacro define-ffi-union (name &rest slots)
  "Like a limited form of `cl-defstruct', but works with foreign objects.
NAME must be a symbol.  SLOTS is a list with each SLOT of the
form `(SLOT-NAME :type TYPE)', where SLOT-NAME is a symbol and TYPE is
an FFI type descriptor.  The first element of SLOTS may be a docstring
for the union."
  (declare (debug (sexp &rest form))
           (indent defun))
  (ffi--struct-union-helper name slots #'ffi--define-union
                            (lambda (types)
                              (make-list (length types) 0))))

(defmacro define-ffi-array (name type length &optional docstring)
  "Like a limited form of `cl-defstruct', but works with foreign objects.
NAME must be a symbol.
TYPE is an FFI type descriptor.
LENGTH is an integer denoting length of the array.
DOCSTRING is a string to document the variable being created.

This is a hack until libffi gives us direct support."
  (declare (debug (sexp form form &optional form))
           (indent defun))
  `(progn
     (defvar ,name)
     (funcall
      (lambda (field-types)
        (defvar ,name (apply #'ffi--define-struct field-types)
          ,docstring))
      (make-list ,length ,type))))

(declare-function ffi--mem-ref "ffi-module.c")
(declare-function ffi-pointer+ "ffi-module.c")
(defsubst ffi-aref (array type index)
  "Return the element at INDEX in FFI ARRAY of TYPE.
ARRAY is a pointer to a C array.  TYPE is an FFI type specifier.
INDEX is the zero-based position of the element to access."
  (ffi--mem-ref (ffi-pointer+ array (* index (ffi--type-size type))) type))

(defmacro with-ffi-temporary (binding &rest body)
  "Allocate a temporary FFI object, execute BODY, then free it.
BINDING is (VAR TYPE-OR-INT) where VAR is the symbol to bind.

The memory is automatically freed with `unwind-protect'.
Use this for scoped FFI resource management."
  (declare (debug t)
           (indent defun))
  `(let ((,(car binding) (ffi-allocate ,@(cdr binding))))
     (unwind-protect
         (progn ,@body)
       (ffi-free ,(car binding)))))

(defmacro with-ffi-temporaries (bindings &rest body)
  "Allocate multiple temporary FFI objects in sequence.
BINDINGS is a list of (VAR TYPE-OR-INT) bindings.
Objects are allocated left-to-right and freed right-to-left.
Execute BODY with all variables bound."
  (declare (debug t)
           (indent defun))
  (let ((first-binding (car bindings))
        (rest-bindings (cdr bindings)))
    (if rest-bindings
        `(with-ffi-temporary ,first-binding
                             (with-ffi-temporaries ,rest-bindings
                                                   ,@body))
      `(with-ffi-temporary ,first-binding ,@body))))

(defmacro with-ffi-string (binding &rest body)
  "Create a temporary C string from a Lisp string.
BINDING is (VAR LISP-STRING) where:
  VAR is the symbol to bind to the C string
  LISP-STRING is the string to convert

The string is automatically freed after BODY executes."
  (declare (debug t)
           (indent defun))
  `(let ((,(car binding) (ffi-make-c-string ,@(cdr binding))))
     (unwind-protect
         (progn ,@body)
       (ffi-free ,(car binding)))))

(defmacro with-ffi-strings (bindings &rest body)
  "Create multiple temporary C strings from Lisp strings.
BINDINGS is a list of (VAR LISP-STRING) bindings.
Strings are created left-to-right and freed right-to-left.
Execute BODY with all variables bound."
  (declare (debug t)
           (indent defun))
  (let ((first-binding (car bindings))
        (rest-bindings (cdr bindings)))
    (if rest-bindings
        `(with-ffi-string ,first-binding
                          (with-ffi-strings ,rest-bindings
                                            ,@body))
      `(with-ffi-string ,first-binding ,@body))))

(provide 'ffi)

;;; ffi.el ends here
