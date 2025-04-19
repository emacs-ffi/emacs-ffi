(use-modules (gnu packages)
             (guix packages))

(concatenate-manifests
 (list (package->development-manifest (specification->package "emacs"))
       (specifications->manifest (list
                                  ;; essentials
                                  "emacs"
                                  "gdb"
                                  "libltdl"
                                  "libffi"
                                  "gcc-toolchain"
                                  "gcc-toolchain:static"
                                  "gsl"
                                  "openssl"
                                  ;; env nevessities
                                  "coreutils-minimal"
                                  "bash"
                                  "git-minimal" ;; for emacs' vc hooks
                                  ;; niceties
                                  "emacs-macrostep"))))
