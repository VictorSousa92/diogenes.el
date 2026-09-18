EMACS   ?= emacs
PYTHON  ?= python3
ELS      = $(wildcard *.el)
BASELINE = per-file-baseline.txt

.PHONY: all check compile declare baseline balance duplicates forms clean help

all: check

help:
	@echo "make check      compile, declare, balance -- the whole gate"
	@echo "make compile    per-file warnings, against $(BASELINE)"
	@echo "make declare    every declare-function, against the definition"
	@echo "make balance    parens, per file"
	@echo "make baseline   rewrite $(BASELINE) -- read the diff before"
	@echo "                committing it, since it is the ratchet"
## ANYTHING DEFINED IN MORE THAN ONE FILE, which nothing else here sees.  The
## forms checker reads one file at a time, the compiler takes whichever
## loaded last, and check-declare reads declarations, not definitions.
##
## classicist--lookup-headword was defvar-local in one file and a plain
## defvar in another, both docstrings claiming buffer-local and only one
## making it so -- which won depended on the load order.  Nine other files
## declared it by hand believing there was one definition.
##
## A duplicate is visible while both copies sit in one file, where the forms
## checker calls it "defined twice", and invisible the moment a cut separates
## them.  So this runs after every cut, not once.
duplicates:
	@$(PYTHON) tools/check-elisp-duplicates.py
check: compile declare duplicates

## THE RATCHET, AND NOT A ZERO.  tei-browser fails on a single warning
## because that file is at zero and can stay there.  This package is at 154
## across forty files, most of it inherited, and a gate demanding zero would
## be switched off within a day.  So the gate is per file and against the
## recorded count: a file may get better and may not get worse.
##
## PER FILE AND NOT FOR THE TREE, because a tree total is not trustworthy.
## batch-byte-compile works alphabetically in one Emacs, and a `require' loads
## the required file AS SOURCE -- so one file silences another's warnings.  It
## happened three times during the extractions, once hiding the very bug two
## upstream patches then fixed.
## AN ERROR IS NOT ZERO WARNINGS, and this counted it as such.  The recipe
## used to pipe the compile straight into `grep -c Warning': a file that
## fails to compile prints an error and no warnings, so the count came out
## zero, which is less than whatever the baseline said -- and the ratchet
## announced
##
##     better diogenes-perseus.el: 40 -> 0   (make baseline)
##
## for a file that would not compile.  Three at once, and it read as the best
## result of the evening.  Worse than blind: inverted, and inviting `make
## baseline' to write the zero down as the standard.
##
## So the output is taken ONCE, checked for `error' before anything is
## counted, and only then compared.  Taking it once also halves the work: the
## old recipe compiled every worse file a second time to print its warnings.
compile:
	@rm -f *.elc
	@fail=0; \
	for f in $(ELS); do \
	  out=$$($(EMACS) -Q --batch -L . -f batch-byte-compile $$f 2>&1); \
	  if echo "$$out" | grep -q ": Error: "; then \
	    echo "ERROR  $$f -- does not compile"; \
	    echo "$$out" | sed 's/^/         /'; \
	    fail=1; \
	    continue; \
	  fi; \
	  n=$$(echo "$$out" | grep -c Warning); \
	  was=$$(awk -v f="$$f" '$$2 == f { print $$1 }' $(BASELINE)); \
	  if [ -z "$$was" ]; then was=0; fi; \
	  if [ "$$n" -gt "$$was" ]; then \
	    echo "WORSE  $$f: $$was -> $$n"; \
	    echo "$$out" | grep Warning | sed 's/^/         /'; \
	    fail=1; \
	  elif [ "$$n" -lt "$$was" ]; then \
	    echo "better $$f: $$was -> $$n   (make baseline)"; \
	  fi; \
	done; \
	rm -f *.elc; \
	if [ $$fail = 1 ]; then \
	  echo "COMPILATION IS WORSE THAN $(BASELINE)"; exit 1; \
	else echo "no file is worse than $(BASELINE)"; fi

## EVERY `declare-function', AGAINST THE DEFINITION IT NAMES.  Forty were
## wrong when this was first run: six named the wrong file, fifteen gave an
## arglist a cl-defun with keywords cannot have, one was malformed with `nil'
## in the file slot, and one named an obsolete alias.
##
## And one was a BROKEN COMMAND.  `diogenes-georges--locate' was declared and
## called and defined nowhere -- the function is
## `diogenes-georges-pdf--locate' -- so the Georges PDF lookup had never
## worked.  The evidence was in every compile log as `not known to be
## defined', and was read as noise for a day.
##
## `file not found' IS FILTERED: pdf-tools, evil, org-roam and reader are
## optional and are not on this load-path.  Those declarations are correct and
## `check-declare' cannot see them.
declare:
	@$(EMACS) -Q --batch -L . \
	  --eval "(progn (require 'check-declare) \
	                 (check-declare-directory default-directory))" 2>&1 \
	  | grep "check-declare" | grep -v "file not found" > /tmp/declare.log \
	  || true
	@if [ -s /tmp/declare.log ]; then \
	  cat /tmp/declare.log; \
	  echo "DECLARATIONS DISAGREE WITH THE DEFINITIONS"; \
	  echo "  tools/fix-declarations.py says what each should say"; \
	  exit 1; \
	else echo "every declare-function names what it says it names"; fi

balance:
	@if [ -f tools/check-elisp-balance.py ]; then \
	  for f in $(ELS); do $(PYTHON) tools/check-elisp-balance.py $$f; done; \
	else echo "tools/check-elisp-balance.py is in the tei-browser tree"; fi

baseline:
	@rm -f *.elc
	@for f in $(ELS); do \
	  printf '%s %s\n' \
	    "$$($(EMACS) -Q --batch -L . -f batch-byte-compile $$f 2>&1 \
	        | grep -c Warning)" "$$f"; \
	done | sort -rn > $(BASELINE)
	@rm -f *.elc
	@awk '{s+=$$1} END {print s" total, in "NR" files"}' $(BASELINE)
	@echo "read the diff before committing: this file IS the ratchet"

clean:
	@rm -f *.elc
