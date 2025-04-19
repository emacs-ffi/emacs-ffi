(use-modules (gnu packages)
             (guix packages))

(concatenate-manifests
 (list (package->development-manifest (specification->package "emacs"))
       (specifications->manifest (list
                                  ;; env necessities
                                  "coreutils-minimal"
                                  "bash"
                                  "openssl"
                                  "git-minimal" ;; for emacs' vc hooks
                                  ;; package essentials
                                  "emacs"
                                  "libltdl"
                                  "libffi"
                                  "gcc-toolchain"
                                  "gcc-toolchain:static"
                                  ;; package examples
                                  "gsl"
                                  ;; package debugging
                                  "emacs-macrostep"
                                  "gdb"))))
