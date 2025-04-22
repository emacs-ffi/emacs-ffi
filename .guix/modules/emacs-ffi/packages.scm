;;; emacs-ffi --- FFI for Emacs

;; Copyright © 2025 Suhail <suhail@bayesians.ca>

;;; Code:

(define-module (emacs-ffi packages)
  #:use-module (ice-9 popen)
  #:use-module (ice-9 rdelim)
  #:use-module (guix packages)
  #:use-module (guix build emacs-utils)
  #:use-module (guix build utils)
  #:use-module (guix build-system emacs)
  #:use-module (guix build-system trivial)
  #:use-module (guix gexp)
  #:use-module (guix profiles)
  #:use-module (guix utils)
  #:use-module (guix git-download)
  #:use-module ((guix licenses) #:prefix license:)
  #:use-module (gnu packages version-control)
  #:use-module (gnu packages texinfo)
  #:use-module (gnu packages emacs)
  #:use-module (gnu packages emacs-xyz)
  #:use-module (gnu packages base)
  ;; package-specific
  #:use-module (gnu packages libffi)
  #:use-module (gnu packages autotools) ;; libltdl
  #:use-module (gnu packages maths) ;; gsl
  )

;;;; Utils:

(define* (git-output source-dir #:rest args)
  "Execute 'git ARGS ...' command and return its output without trailing
newspace."
  (with-directory-excursion source-dir
    (let* ((port   (apply open-pipe* OPEN_READ "git" args))
           (output (read-string port)))
      (close-port port)
      (string-trim-right output #\newline))))

(define (current-commit source-dir)
  "The commit corresponding to HEAD.
SOURCE-DIR is some path within an existing git repository."
  (git-output source-dir "rev-parse" "HEAD"))

(define (current-revision source-dir)
  "Returns (version,revision) tuple.
SOURCE-DIR is some path within an existing git repository."
  (list-head (string-split (git-output source-dir "describe" "--tags") #\-) 2))

;;;; emacs-ffi-dev

(define-public emacs-ffi-dev
  "Package for the development version of `emacs-ffi'.
For being able to run the examples, it propagates libgsl and Emacs and ensures
that LD_LIBRARY_PATH is set within the Emacs instance."
  (let* ((source-dir (emacs-batch-script
                      '(princ
                        (directory-file-name
                         (expand-file-name
                          (locate-dominating-file default-directory ".git"))))))
         (commit (current-commit source-dir))
         (ver-rev (current-revision source-dir))
         (version (car ver-rev))
         (revision (cadr ver-rev)))
    (package
      (name "emacs-ffi-dev")
      (version (git-version version revision commit))
      (source (local-file source-dir
                          #:recursive? #t
                          #:select? (git-predicate source-dir)))
      (build-system emacs-build-system)
      (arguments
       (list
        #:tests? (not (%current-target-system))
        #:phases
        #~(modify-phases %standard-phases
            (add-after 'unpack 'patch-module-load
              (lambda _
                (make-file-writable "src/ffi.el")
                (emacs-substitute-sexps "src/ffi.el"
                  ("(require 'ffi-module nil t)"
                   `(module-load
                     ,(string-append #$output "/lib/ffi-module.so"))))))
            (add-before 'check 'build-emacs-module
              (lambda _
                ;; Compile the shared object file.
                (invoke "make" #$(string-append "CC=" (cc-for-target)))
                ;; Copy build directory to root and let the install phase do its
                ;; thing
                (copy-recursively "build/lib" ".")
                ;; Install the shared object file into /lib.
                (install-file "build/lib/ffi-module.so"
                              (string-append #$output "/lib"))))
            (add-before 'install 'installinfo
              (lambda _
                (install-file "build/doc/emacs-ffi.info"
                              (string-append #$output "/share/info")))))))
      (inputs (list emacs-compat libltdl libffi))
      (native-inputs (list texinfo))
      (propagated-inputs (list coreutils-minimal
                               ;; for dev convenience, to run examples
                               emacs-ffi-dev-emacs-wrapper gsl))
      (home-page "https://github.com/emacs-ffi/emacs-ffi")
      (synopsis "FFI for Emacs based in libffi")
      (description "This package provides an FFI for Emacs.  It is based on
libffi and relies on the dynamic module support in order to be loaded into
Emacs.  It is relatively full-featured, but for the time being low-level.")
      (license license:gpl3+))))

(define-public emacs-ffi-dev-emacs-wrapper
  "Emacs wrapper that ensures the libraries in Guix environment are accessible
via LD_LIBRARY_PATH."
  (package
    (inherit emacs)
    (name "emacs-ffi-dev-emacs-wrapper")
    (source #f)
    (build-system trivial-build-system)
    (arguments
     (list #:modules '((guix build union)
                       (guix build utils))
           #:builder
           #~(begin
               (use-modules (guix build union)
                            (guix build utils))
               (union-build #$output (list #$emacs)))))
    (native-search-paths
     (append (package-native-search-paths emacs)
             (list (search-path-specification
                    (variable "LD_LIBRARY_PATH")
                    (files (list "lib"))))))
    (inputs (list emacs))
    (synopsis "Emacs variant with LD_LIBRARY_PATH set based on profile")))

emacs-ffi-dev
