(add-to-load-path (string-append (dirname (current-filename)) "/modules"))

(use-modules (gnu packages)
             (guix packages)
             (guix transformations)
             (emacs-ffi packages))

(define revert-emacs-wrapping
  (options->transformation
   '((with-input . "emacs-ffi-dev-emacs-wrapper=emacs"))))

(concatenate-manifests
 (list (specifications->manifest (list "git-minimal" "nss-certs" "openssl"
                                       "gsl" ;; examples
                                       ;; debugging
                                       "gdb" "emacs-macrostep"
                                       ;; linting
                                       "emacs-eldev"
                                       "emacs-package-lint" "emacs-relint"))
       (package->development-manifest (revert-emacs-wrapping emacs-ffi-dev))))
