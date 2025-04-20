;;; gsl-ffi.el --- FFI example with GSL  -*- lexical-binding: t; -*-

;; Copyright (C) 2025      Suhail
;; Copyright (C) 2024      John Kitchin

;;; Commentary:

;; This is a brief example of using the FFI with libgsl.  Evaluating this file
;; yields some informative output.

;;; Code:

(require 'ffi)

(define-ffi-library gsl "libgsl")

(define-ffi-function gsl-sf-bessel-J0-v1 "gsl_sf_bessel_J0"
  :double
  [:double]
  gsl)

(let ((x 5.0))
  (message "J0(%s)=%s" x (gsl-sf-bessel-J0-v1 x)))


;; More verbose signature

(define-ffi-function gsl-sf-bessel-J0-v2 "gsl_sf_bessel_J0"
  (:double "J0(x)")
  ((:double x "X is the value to evaluate"))
  gsl
  "Return the J0(X)")


(let ((x 5.0))
  (message "J0(%s)=%s" x (gsl-sf-bessel-J0-v2 x)))

(message "\nDefault signature:\n%s"
         (let ((inhibit-message t)) (describe-function 'gsl-sf-bessel-J0-v1)))
(message "Descriptive signature:\n%s"
         (let ((inhibit-message t)) (describe-function 'gsl-sf-bessel-J0-v2)))

(provide 'gsl-ffi)

;;; gsl-ffi.el ends here
