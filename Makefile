## Makefile --- run the tests and the compiler over diogenes.el
##
## The two things a change should pass before it is pushed, and neither needs
## Diogenes' data, its Perl, or a display -- so both give the same answer on
## any machine.
##
##     make test       the ERT suite
##     make compile    byte-compile, and fail on an error
##     make check      both
##     make clean      remove the byte-code
##
## Neither is sufficient on its own.  Every hard fault in this package's
## history was found by running it inside a live configuration -- Doom's
## `find-file-hook', evil's state maps, persp-mode's workspace filter -- and
## none of those exists under `emacs -Q'.  So after `make check' passes,
## `M-x diogenes-tests-run' in each configuration you support, and
## `M-x diogenes-tests-environment' when something differs between them.

EMACS ?= emacs
BATCH  = $(EMACS) -Q -batch -L . -L test

SRC = $(wildcard diogenes*.el)

.PHONY: all check test compile clean

all: check

check: compile test

test:
	@$(BATCH) -l test/diogenes-tests.el \
		-f ert-run-tests-batch-and-exit

## Warnings are many and mostly inherited; an ERROR is a broken file, and
## that is what this fails on.  `grep -i ": error"' rather than the exit
## status, because `batch-byte-compile' exits zero for a file it could not
## compile.
compile:
	@$(BATCH) -f batch-byte-compile $(SRC) 2>&1 \
		| tee /tmp/diogenes-compile.log \
		| grep -i ": error" \
		&& { echo "COMPILATION ERRORS -- see /tmp/diogenes-compile.log"; \
		     exit 1; } \
		|| echo "compiled with no errors"

clean:
	@rm -f *.elc test/*.elc
