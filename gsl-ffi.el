(require 'ffi)

(define-ffi-library gsl "libgsl")

(define-ffi-function gsl-sf-bessel-J0 "gsl_sf_bessel_J0"
  :double
  [:double] 
  gsl)

(let ((x 5.0))
  (message "J0(%s)=%s" x (gsl-sf-bessel-J0 x)))


;; More verbose signature

(define-ffi-function gsl-sf-bessel-J0-v2 "gsl_sf_bessel_J0"
  (:double "J0(x)")
  ((:double x "X is the value to evaluate")) 
  gsl
  "Return the J0(X)")


(let ((x 5.0))
  (message "J0(%s)=%s" x (gsl-sf-bessel-J0-v2 x)))

(describe-function 'gsl-sf-bessel-J0-v2)
