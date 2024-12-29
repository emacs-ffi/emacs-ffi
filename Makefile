# Makefile for FFI module.

# This is is free software: you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation, either version 3 of the License, or
# (at your option) any later version.

# This is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.

# You should have received a copy of the GNU General Public License
# along with this.  If not, see <https://www.gnu.org/licenses/>.

# Where your dynamic-module-enabled Emacs build lies.
EMACS  = $(shell realpath `which emacs`)
EMACS_BIN = $(shell dirname $(EMACS))
EMACS_BUILDDIR ?= $(shell dirname $(EMACS_BIN))

LDFLAGS += -shared
LIBS = -lffi -lltdl
CFLAGS += -g3 -Og -shared -fPIC -I$(EMACS_BUILDDIR)/include/ -I$(EMACS_BUILDDIR)/lib/
CFLAGS += $(shell pkg-config -cflags libffi)

# Set this to debug make check.
#GDB = gdb --args

all: ffi-module.so

ffi-module.so: ffi-module.o	
	$(CC) $(LDFLAGS) -o ffi-module.so ffi-module.o $(LIBS)

ffi-module.o: ffi-module.c

check: ffi-module.so test.so
	$(GDB) $(EMACS) -batch -L `pwd` -l ert -l test.el \
	  -f ert-run-tests-batch-and-exit

test.so: test.o
	$(CC) $(LDFLAGS) -o test.so test.o

test.o: test.c

clean:
	-rm -f ffi-module.o ffi-module.so test.o test.so

gsl:
	emacs --batch -L . -l gsl-ffi.el

gsl-org:
	emacs --batch -L . --eval="(progn (find-file \"gsl-ffi.org\") (setq org-confirm-babel-evaluate nil) (org-babel-execute-buffer))"
