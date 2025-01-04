all:  gsl-linalg.so

clean:
	rm *.o *.so

# Where your dynamic-module-enabled Emacs build lies.
EMACS  = $(shell realpath `which emacs`)
EMACS_BIN = $(shell dirname $(EMACS))
EMACS_BUILDDIR ?= $(shell dirname $(EMACS_BIN))/..

##############
# GSL linalg #
##############

LIBS = $(shell pkg-config --libs gsl)
LDFLAGS += -shared
CFLAGS += -g3 -Og -shared -fPIC -I$(EMACS_BUILDDIR)/include/ -I$(EMACS_BUILDDIR)/lib/ $(shell pkg-config --cflags gsl)

gsl-linalg.so: gsl-linalg.o 
	$(CC) $(LDFLAGS) -o gsl-linalg.so gsl-linalg.o $(LIBS)

gsl-linalg.o: gsl-linalg.c

test: gsl-linalg.so tests.el
	emacs -batch -q -l tests.el -f test-linalg
	emacs -batch -q -l tests.el -f test-dgemm

