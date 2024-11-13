;;; ffi.el --- FFI for Emacs  -*- lexical-binding: t; -*-

;; Copyright (C) 2015-2017 Tom Tromey

;; Author: Tom Tromey <tom@tromey.com>
;; Package-Requires: ((emacs "25.1"))

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

(eval-and-compile (module-load (locate-library "ffi-module")))

(gv-define-simple-setter ffi--mem-ref ffi--mem-set t)

(defmacro define-ffi-library (symbol name)
  `(progn
     (defvar ,symbol nil)
     (defun ,symbol ()
       (or ,symbol
           (setq ,symbol (ffi--dlopen (locate-library ,name)))))))

(defmacro define-ffi-function (name c-name return-type arg-types library)
  (declare (indent defun))
  ;; Turn variable references into actual types; while keeping keywords
  ;; the same.
  (let* ((n 0)
         (args (mapcar (lambda (_) (intern (format "arg%d" (cl-incf n)))) arg-types))
         (sym (intern (concat "ffi-fun-" c-name))))
    `(progn
       (defvar ,sym nil)
       (defun ,name (,@args)
         (unless ,sym
           (setq ,sym (ffi--dlsym ,c-name (,library))))
         ;; FIXME do we even need a separate prep?
         (ffi--call (ffi--prep-cif ,return-type
                                   (vconcat
                                    (mapcar #'symbol-value ',arg-types)))
                    ,sym ,@args)))))

(defun ffi-lambda (function-pointer return-type arg-types)
  (let ((cif (ffi--prep-cif return-type (vconcat arg-types))))
    (lambda (&rest args)             ; lame
      (apply #'ffi--call cif function-pointer args))))

(defsubst ffi--align (offset align)
  (+ offset (mod (- align (mod offset align)) align)))

(defun ffi--lay-out-struct (types)
  (let ((offset 0))
    (mapcar (lambda (type)
              (prog1
                  (setq offset (ffi--align offset (ffi--type-alignment type)))
                (cl-incf offset (ffi--type-size type))))
            types)))

(defun ffi--struct-union-helper (name slots definer-function layout-function)
  (cl-assert (symbolp name))
  (let* ((docstring (and (stringp (car slots))
                         (pop slots)))
         (field-types (mapcar (lambda (slot)
                                (cl-assert (eq (cadr slot) :type))
                                (symbol-value (cl-caddr slot)))
                              slots))
         (field-offsets (funcall layout-function field-types)))
    `(progn
       (defvar ,name
         (apply #',definer-function ',field-types)
         ,docstring)
       ,@(cl-mapcar
          (lambda (slot type offset)
            (let ((getter-name (intern (format "%s-%s" name (car slot))))
                  (offsetter (if (> offset 0)
                                 `(ffi-pointer+ object ,offset)
                               'object)))
              ;; One benefit of using cl-defsubst here is that we don't
              ;; have to provide a GV setter.
              `(cl-defsubst ,getter-name (object)
                 (ffi--mem-ref ,offsetter ,type))))
          slots field-types field-offsets))))

(defmacro define-ffi-struct (name &rest slots)
  "Like a limited form of `cl-defstruct', but works with foreign objects.

NAME must be a symbol.
Each SLOT must be of the form `(SLOT-NAME :type TYPE)', where
SLOT-NAME is a symbol and TYPE is an FFI type descriptor."
  (declare (indent defun))
  (ffi--struct-union-helper name slots #'ffi--define-struct
                            #'ffi--lay-out-struct))

(defmacro define-ffi-union (name &rest slots)
  "Like a limited form of `cl-defstruct', but works with foreign objects.

NAME must be a symbol.
Each SLOT must be of the form `(SLOT-NAME :type TYPE)', where
SLOT-NAME is a symbol and TYPE is an FFI type descriptor."
  (declare (indent defun))
  (ffi--struct-union-helper name slots #'ffi--define-union
                            (lambda (types)
                              (make-list (length types) 0))))

(defmacro define-ffi-array (name type length &optional docstring)
  ;; This is a hack until libffi gives us direct support.
  (declare (indent defun))
  `(defvar ,name
     (apply #'ffi--define-struct (make-list ,length ,type))
     ,docstring))

(defsubst ffi-aref (array type index)
  (ffi--mem-ref (ffi-pointer+ array (* index (ffi--type-size type))) type))

(defmacro with-ffi-temporary (binding &rest body)
  (declare (indent defun))
  `(let ((,(car binding) (ffi-allocate ,@(cdr binding))))
     (unwind-protect
         (progn ,@body)
       (ffi-free ,(car binding)))))

(defmacro with-ffi-temporaries (bindings &rest body)
  (declare (indent defun))
  (let ((first-binding (car bindings))
        (rest-bindings (cdr bindings)))
    (if rest-bindings
        `(with-ffi-temporary ,first-binding
           (with-ffi-temporaries ,rest-bindings
             ,@body))
      `(with-ffi-temporary ,first-binding ,@body))))

(defmacro with-ffi-string (binding &rest body)
  (declare (indent defun))
  `(let ((,(car binding) (ffi-make-c-string ,@(cdr binding))))
     (unwind-protect
         (progn ,@body)
       (ffi-free ,(car binding)))))

(defmacro with-ffi-strings (bindings &rest body)
  (declare (indent defun))
  (let ((first-binding (car bindings))
        (rest-bindings (cdr bindings)))
    (if rest-bindings
        `(with-ffi-string ,first-binding
           (with-ffi-strings ,rest-bindings
             ,@body))
      `(with-ffi-string ,first-binding ,@body))))

(provide 'ffi)

;;; ffi.el ends here
