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
DOC_DIR = $(BUILD_DIR)/doc
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
# Elisp targets
TEST_EL_SRC = $(filter $(TEST_DIR)/%, $(EL_SRC_FILES))
SRC_EL_SRC = $(filter-out $(TEST_DIR)/%, $(EL_SRC_FILES))
TEST_EL_TARGETS = $(foreach t, $(TEST_EL_SRC), \
	$(BUILD_DIR)/$(TEST_DIR)/$(basename $(notdir $(t)))-lexical.el \
	$(BUILD_DIR)/$(TEST_DIR)/$(basename $(notdir $(t)))-dynamic.el )
SRC_EL_TARGETS = $(patsubst $(SRC_DIR)/%,$(LIB_DIR)/%.el, \
	$(basename $(SRC_EL_SRC)))
EL_TARGETS = $(TEST_EL_TARGETS) $(SRC_EL_TARGETS)
ELC_TARGETS = $(patsubst %.el,%.elc, $(EL_TARGETS))
# Documentation targets
DOC_TARGETS = $(DOC_DIR)/ffi.texi $(DOC_DIR)/ffi.info

$(DOC_DIR)/ffi.info: $(DOC_DIR)/ffi.texi
$(DOC_DIR)/ffi.texi: README.org
	@mkdir -p $(@D)
	cp README.org $(DOC_DIR)/ffi.org
	$(EMACS) -Q --batch -l org $(DOC_DIR)/ffi.org -f org-texinfo-export-to-texinfo
.PHONY: docs-html
docs-html: | $(DOC_DIR)/html
$(DOC_DIR)/html: $(DOC_DIR)/ffi.texi
	rm -rf $(DOC_DIR)/html
	makeinfo --html -o $(DOC_DIR)/html $<

.PHONY: all check clean
all: $(OBJ_FILES) $(SO_FILES) $(EL_TARGETS) $(ELC_TARGETS) $(DOC_TARGETS)

check: $(SO_FILES) $(EL_TARGETS) $(ELC_TARGETS)
	$(call run-test,Lexical + Interpreted,LEXICAL,el)
	$(call run-test,Dynamic + Interpreted,DYNAMIC,el)
	$(call run-test,Lexical + Byte-compiled,LEXICAL,elc)
	$(call run-test,Dynamic + Byte-compiled,DYNAMIC,elc)
define run-test
	@echo "Testing: $(1)"
	$(GDB) $(EMACS) -Q --batch \
	  -L $(CURDIR)/$(LIB_DIR) -L $(CURDIR)/$(BUILD_DIR)/$(TEST_DIR) \
	  $(foreach name,$(patsubst %.elc,%.$(3),$(TEST_ELC_$(2))),-l $(name)) \
	  -f ert-run-tests-batch-and-exit
endef
TEST_ELC_TARGETS = $(filter $(BUILD_DIR)/$(TEST_DIR)/%, $(ELC_TARGETS))
TEST_ELC_DYNAMIC = $(filter %-dynamic.elc, $(TEST_ELC_TARGETS))
TEST_ELC_LEXICAL = $(filter %-lexical.elc, $(TEST_ELC_TARGETS))

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
$(LIB_DIR)/%.elc: $(LIB_DIR)/%.el
	$(EMACS) -Q --batch -f batch-byte-compile $<

# Linking rule for obj/tests/*.o -> tests/*.so
$(BUILD_DIR)/$(TEST_DIR)/%.so: $(OBJ_DIR)/$(TEST_DIR)/%.o
	@mkdir -p $(@D)
	$(CC) $(LDFLAGS) -o $@ $<
# Generate test-lexical.el and test-dynamic.el for each test.el
$(BUILD_DIR)/$(TEST_DIR)/%-lexical.el: $(TEST_DIR)/%.el
	@mkdir -p $(@D)
	sed '1s/lexical-binding:[[:space:]]*[^ ;]*/lexical-binding: t/' $< > $@
$(BUILD_DIR)/$(TEST_DIR)/%-dynamic.el: $(TEST_DIR)/%.el
	@mkdir -p $(@D)
	sed '1s/lexical-binding:[[:space:]]*[^ ;]*/lexical-binding: nil/' $< > $@
$(BUILD_DIR)/$(TEST_DIR)/%.elc: $(BUILD_DIR)/$(TEST_DIR)/%.el
	$(EMACS) -Q --batch -L $(LIB_DIR) -f batch-byte-compile $<

# Compilation rule for .c -> .o
$(OBJ_DIR)/%.o: %.c
	@mkdir -p $(@D)
	$(CC) -c $(CFLAGS) -o $@ $<

# Lint
.PHONY: lint
lint:
	eldev doctor
	eldev lint

# examples using gsl
# NOTE: below we assume that either LIBRARY_PATH or LD_LIBRARY_PATH includes
# libgsl.  Guix shell ensures that it's added to LIBRARY_PATH.
.PHONY: gsl gsl-org
gsl: $(SO_FILES) $(EL_TARGETS)
	LD_LIBRARY_PATH=${LIBRARY_PATH}:${LD_LIBRARY_PATH} \
	$(GDB) $(EMACS) -Q --batch -L $(CURDIR)/$(LIB_DIR) \
	  -l examples/gsl-ffi.el

gsl-org: $(SO_FILES) $(EL_TARGETS)
	LD_LIBRARY_PATH=${LIBRARY_PATH}:${LD_LIBRARY_PATH} \
	$(GDB) $(EMACS) -Q --batch -L $(CURDIR)/$(LIB_DIR) \
	  --eval="(progn (find-file \"examples/gsl-ffi.org\") (setq org-confirm-babel-evaluate nil) (org-babel-execute-buffer))"

# diagnostics
.PHONY: emacs-info
emacs-info:
	@$(EMACS) --version
	@$(EMACS) -Q --batch --eval='(message "%s" (with-temp-buffer (emacs-build-description) (buffer-string)))'
