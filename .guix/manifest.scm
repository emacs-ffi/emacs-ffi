(add-to-load-path (string-append (dirname (current-filename)) "/modules"))

(use-modules (gnu packages)
             (guix packages)
             (emacs-ffi packages))

(concatenate-manifests
 (list (specifications->manifest (list "git-minimal" "nss-certs" "openssl"
                                       "gsl" ;; examples
                                       ;; debugging
                                       "gdb" "emacs-macrostep"
                                       ;; linting
                                       "emacs-eldev"
                                       "emacs-package-lint" "emacs-relint"))
       (package->development-manifest emacs-ffi-dev)))
