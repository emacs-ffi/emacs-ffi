# SPDX-License-Identifier: GPL-3.0-or-later

-include config.mk

# Set this to debug make test.
# GDB = gdb --args

# FIXME Emacs (what release?) now installs the necessary headers
# so this shouldn't be required anymore.
# EMACS_BUILDDIR ?= /home/tromey/Emacs/emacs
EMACS_BUILDDIR ?= /home/jonas/src/emacs/emacs/master

PKG = ffi

ELS   = ffi.el
ELS  += test.el
ELCS  = $(ELS:.el=.elc)

EMACS      ?= emacs
EMACS_ARGS ?=
LOAD_PATH   = -L .

LDFLAGS  = -shared
LIBS     = -lffi -lltdl
CFLAGS  += -g3 -Og -finline-small-functions -shared -fPIC \
  -I$(EMACS_BUILDDIR)/src/ -I$(EMACS_BUILDDIR)/lib/

all: module test-module lisp

help:
	$(info make all          - build module and lisp)
	$(info make redo         - re-build module and lisp)
	$(info make module       - build module)
	$(info make test-module  - build test module)
	$(info make lisp         - build lisp and autoloads)
	$(info make test         - run tests)
	$(info make clean        - remove generated files)
	@printf "\n"

redo: clean all

module: ffi-module.so

test-module: test.so

lisp: $(ELCS) loaddefs

test: ffi-module.so test.so $(ELCS)
	LD_LIBRARY_PATH=`pwd`:$$LD_LIBRARY_PATH; \
	  export LD_LIBRARY_PATH; \
	$(GDB) $(EMACS_BUILDDIR)/src/emacs -batch -L `pwd` -l ert -l test.el \
	  -f ert-run-tests-batch-and-exit

clean:
	@printf " Cleaning *...\n"
	@rm -rf $(ELCS) $(PKG)-autoloads.el *.o *.so


ffi-module.so: ffi-module.o
	$(CC) $(LDFLAGS) -o ffi-module.so ffi-module.o $(LIBS)

ffi-module.o: ffi-module.c

test.so: test.o
	$(CC) $(LDFLAGS) -o test.so test.o

test.o: test.c ffi-module.c

loaddefs: $(PKG)-autoloads.el

%.elc: %.el
	@printf "Compiling $<\n"
	@$(EMACS) -Q --batch $(EMACS_ARGS) $(LOAD_PATH) -f batch-byte-compile $<

$(PKG)-autoloads.el: $(ELS)
	@printf " Creating $@\n"
	@$(EMACS) -Q --batch -l autoload -l cl-lib --eval "\
(let ((file (expand-file-name \"$@\"))\
      (autoload-timestamps nil) \
      (backup-inhibited t)\
      (version-control 'never)\
      (coding-system-for-write 'utf-8-emacs-unix))\
  (write-region (autoload-rubric file \"package\" nil) nil file nil 'silent)\
  (cl-letf (((symbol-function 'progress-reporter-do-update) (lambda (&rest _)))\
            ((symbol-function 'progress-reporter-done) (lambda (_))))\
    (let ((generated-autoload-file file))\
      (update-directory-autoloads default-directory))))" \
	2>&1 | sed "/^Package autoload is deprecated$$/d"
