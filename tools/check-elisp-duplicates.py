#!/usr/bin/env python3
r"""Anything defined in more than one file.

    python3 check-elisp-duplicates.py            # every .el here
    python3 check-elisp-duplicates.py --dir DIR

WHAT NOTHING ELSE SEES.  `classicist--lookup-headword' was defined twice and
differently:

    defvar-local   classicist-lexicon.el
    defvar         diogenes-perseus.el

with both docstrings saying "Buffer-local in `diogenes-lookup-mode' buffers"
and only one of them making it so.  Which won depended on load order:
`classicist-lexicon.el' sorts first, so its `defvar-local' ran and then
perseus' `defvar' re-set the value globally.  The symbol kept its
buffer-local property from one and its value from the other, and the thing
worked by alphabetical accident.

NINE OTHER FILES declared it by hand -- `(defvar classicist--lookup-headword)'
with comments saying "from diogenes-perseus.el" -- so its author believed
there was one definition, in perseus, and buffer-local.  There were two, in
two files, and the one in perseus was not.

AND NOTHING IN THE TOOLCHAIN LOOKS:

  the per-file forms checker  sees one definition per file and is satisfied
  the byte-compiler           sees whichever file loaded last
  `check-declare'             reads declarations, not definitions
  a reference walker          asks who CALLS a name, not who defines it

A duplicate is invisible while both copies sit in one file -- there they are
"defined twice" and the forms checker says so.  Split the file and the copies
land in different files, where nothing is looking.  Which is the argument for
running this after every cut rather than once.

A BARE `(defvar x)' IS A DECLARATION AND NOT A DEFINITION, and is skipped:
the character after the name says which, `)' for the one and anything else
for the other.  Ten files carry bare declarations of the headword and none of
them is at fault.

A name that is both a variable and a function IN ONE FILE is left alone too:
`classicist-browser-header-line' is a `defcustom' and a `defun', which is
legitimate in a lisp with separate namespaces.
"""
import argparse
import os
import re
import sys
from collections import defaultdict

DEFINER = re.compile(
    r"^\((?:cl-)?(defun|defmacro|defsubst|defcustom|defvar|defvar-local"
    r"|defvar-keymap|defconst|defface|define-derived-mode|define-minor-mode"
    r"|cl-defstruct|transient-define-prefix|transient-define-argument"
    r"|transient-define-suffix)\s+([^\s()]+)(.)", re.M | re.S)

VARIABLES = {"defcustom", "defvar", "defvar-local", "defvar-keymap",
             "defconst", "defface"}


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--dir", default=".")
    ap.add_argument("--quiet", action="store_true",
                    help="say nothing when there is nothing")
    args = ap.parse_args()

    files = sorted(f for f in os.listdir(args.dir) if f.endswith(".el"))
    if not files:
        sys.exit(f"no .el files in {args.dir}")

    where = defaultdict(list)
    for f in files:
        s = open(os.path.join(args.dir, f), encoding="utf-8",
                 errors="replace").read()
        for m in DEFINER.finditer(s):
            kind, name, nxt = m.group(1), m.group(2), m.group(3)
            # a bare `(defvar x)' says the variable lives elsewhere
            if kind == "defvar" and nxt == ")":
                continue
            where[name].append((f, kind, s[:m.start()].count("\n") + 1))

    bad = []
    for name, v in sorted(where.items()):
        if len({f for f, _, _ in v}) > 1:
            bad.append((name, v))

    if not bad:
        if not args.quiet:
            print(f"   nothing is defined in more than one file "
                  f"({len(files)} files, {len(where)} names)")
        return 0

    for name, v in bad:
        kinds = {k for _, k, _ in v}
        note = ""
        if kinds & {"defvar"} and kinds & {"defvar-local"}:
            note = ("  -- one buffer-local and one not, so which wins is the\n"
                    "      load order")
        elif len(kinds) > 1:
            note = f"  -- and not even the same kind of definition"
        print(f"   TROUBLE  {name} is defined in "
              f"{len({f for f, _, _ in v})} files{note}")
        for f, k, ln in v:
            print(f"                {k:14} {f}:{ln}")
    print(f"\n   {len(bad)} defined in more than one file.  Nothing else here"
          f" looks:\n"
          f"   the forms checker reads one file, the compiler takes whichever\n"
          f"   loaded last, and check-declare reads declarations.")
    return 1


if __name__ == "__main__":
    sys.exit(main())
