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
EMACS  = $(shell realpath `command -v emacs`)
EMACS_BIN = $(shell dirname $(EMACS))
EMACS_BUILDDIR ?= $(shell dirname $(EMACS_BIN))
EMACS_LIBRARY_PATH = $(CURDIR)/$(BUILD_DIR)/$(TEST_DIR):$(CURDIR)/$(LIB_DIR)
EMACS_LIBRARY_PATH = $(CURDIR)/$(LIB_DIR)
EMACS_LIBRARY_PATH = $(CURDIR)/$(BUILD_DIR)/$(TEST_DIR)
EMACS_PREFIX ?= env LD_LIBRARY_PATH=$(EMACS_LIBRARY_PATH):$$LD_LIBRARY_PATH

ifeq ($(origin CC),default)
CC  := gcc
endif
CFLAGS += -g3 -Og -shared -fPIC -I$(EMACS_BUILDDIR)/include/ -I$(EMACS_BUILDDIR)/lib/
CFLAGS += $(shell pkg-config --cflags libffi)

LDFLAGS += -shared
LIBS = -lffi -lltdl

# Set this to debug make check.
#GDB = gdb --args

# Directories
SRC_DIR := src
TEST_DIR = tests
BUILD_DIR := build
OBJ_DIR := $(BUILD_DIR)/obj
LIB_DIR = $(BUILD_DIR)/lib
# Sources
SRC_FILES := $(wildcard $(SRC_DIR)/*.c $(TEST_DIR)/*.c)
EL_SRC_FILES := $(wildcard $(SRC_DIR)/*.el $(TEST_DIR)/*.el)
# Targets
OBJ_FILES := $(patsubst %,$(OBJ_DIR)/%.o,$(basename $(SRC_FILES)))
# FIXME: support `module-file-suffix'
SO_FILES := $(patsubst $(SRC_DIR)/%,$(LIB_DIR)/%.so,\
              $(patsubst $(TEST_DIR)/%,$(BUILD_DIR)/$(TEST_DIR)/%.so,\
              $(basename $(SRC_FILES))))
EL_TARGETS := $(patsubst $(SRC_DIR)/%,$(LIB_DIR)/%.el,\
              $(patsubst $(TEST_DIR)/%,$(BUILD_DIR)/$(TEST_DIR)/%.el,\
              $(basename $(EL_SRC_FILES))))



.PHONY: all check clean
all: $(OBJ_FILES) $(SO_FILES) $(EL_TARGETS)

check: $(SO_FILES) $(EL_TARGETS)
	$(EMACS_PREFIX) $(GDB) $(EMACS) -batch \
	  -L $(CURDIR)/$(LIB_DIR) -L $(CURDIR)/$(BUILD_DIR)/$(TEST_DIR) \
	  -l $(BUILD_DIR)/$(TEST_DIR)/test.el \
	  -f ert-run-tests-batch-and-exit

clean:
	-rm -rf $(BUILD_DIR)


# Linking rule for obj/src/*.o -> lib/*.so
$(LIB_DIR)/%.so: $(OBJ_DIR)/$(SRC_DIR)/%.o
	@mkdir -p $(@D)
	$(CC) $(LDFLAGS) -o $@ $< $(LIBS)
# Copy rule for src/ .el files
$(LIB_DIR)/%.el: $(SRC_DIR)/%.el
	@mkdir -p $(@D)
	cp $< $@

# Linking rule for obj/tests/*.o -> tests/*.so
$(BUILD_DIR)/$(TEST_DIR)/%.so: $(OBJ_DIR)/$(TEST_DIR)/%.o
	@mkdir -p $(@D)
	$(CC) $(LDFLAGS) -o $@ $<
# Copy rule for tests/ .el files
$(BUILD_DIR)/$(TEST_DIR)/%.el: $(TEST_DIR)/%.el
	@mkdir -p $(@D)
	cp $< $@

# Compilation rule for .c -> .o
$(OBJ_DIR)/%.o: %.c
	@mkdir -p $(@D)
	$(CC) -c $(CFLAGS) -o $@ $<


# examples using gsl
.PHONY: gsl gsl-org
gsl: $(SO_FILES) $(EL_TARGETS)
	$(EMACS_PREFIX) $(EMACS) --batch \
	  -L $(CURDIR)/$(LIB_DIR) \
	  -l examples/gsl-ffi.el

gsl-org: $(SO_FILES) $(EL_TARGETS)
	$(EMACS_PREFIX) $(EMACS) --batch \
	  -L $(CURDIR)/$(LIB_DIR) \
	  --eval="(progn (find-file \"examples/gsl-ffi.org\") (setq org-confirm-babel-evaluate nil) (org-babel-execute-buffer))"
