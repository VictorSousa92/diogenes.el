#!/usr/bin/env python3
r"""Every `declare-function', against the definition it names.

    python3 fix-declarations.py                 # report
    python3 fix-declarations.py --write

`M-x check-declare-directory' says a declaration is wrong.  It does not say
what is right, and there were twenty-five of them.  This finds the real
definition and reports the file and arglist it should have named.

WHAT IT FOUND THE FIRST TIME IT RAN, and none of it by any other tool here:

  - `diogenes-georges--locate' declared and CALLED, and defined nowhere.  The
    function is `diogenes-georges-pdf--locate'.  So the Georges PDF lookup
    had never worked -- void-function at a keypress -- and the evidence was in
    every compile log as `not known to be defined', read as noise.
  - six declarations naming `diogenes-browser' and `diogenes-utils' for
    functions that are in `classicist-citation' now, one of them wrong before
    any of today's renames.
  - `(declare-function diogenes-perseus-action nil)', where `nil' is being
    read as the FILE NAME: the signature is (FN FILE &optional ARGLIST).

A `cl-defun' WITH KEYWORDS CANNOT BE DECLARED HONESTLY by copying its
arglist.  `diogenes-lookup-register-dictionary' takes fourteen keywords and is
declared `(id &rest keys)' in fifteen files -- a summary that reads well and
is formally wrong, so `check-declare' flags all fifteen.  The form for that is
`t' in place of the arglist, which means "defined there, arglist
unspecified".  This proposes `t' for any `cl-defun' whose arglist holds `&key'.

NOT A RENAMER.  It changes the FILE and the ARGLIST of a declaration, never
the symbol: a declaration naming a symbol that does not exist is a finding for
a person, because the answer might be a typo, a rename, or a function nobody
ever wrote.  All three turned up.
"""
import argparse
import os
import re
import sys

DECL = re.compile(
    r"\(declare-function\s+([^\s()]+)\s+((?:\"[^\"]*\")|nil|t)"
    r"(\s+(?:\([^)]*\)|t|nil))?\s*\)", re.S)

DEFN = re.compile(
    r"^\s*\((cl-defun|defun|defmacro|defsubst|define-derived-mode"
    r"|define-minor-mode|defalias|define-obsolete-function-alias)\s+'?"
    r"([^\s()]+)", re.M)


def arglist_at(text, pos):
    """The arglist of the definition whose head is at POS, as written."""
    i = text.index("(", pos)          # the defun's own paren
    i = text.index(" ", i)
    # past the name
    while text[i] == " ":
        i += 1
    while i < len(text) and text[i] not in " \n(":
        i += 1
    while i < len(text) and text[i] in " \n":
        i += 1
    if i >= len(text) or text[i] != "(":
        return None                   # a mode, an alias: no arglist here
    depth, j = 0, i
    while j < len(text):
        if text[j] == "(":
            depth += 1
        elif text[j] == ")":
            depth -= 1
            if depth == 0:
                return " ".join(text[i:j + 1].split())
        j += 1
    return None


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--dir", default=".")
    ap.add_argument("--write", action="store_true")
    args = ap.parse_args()

    files = sorted(f for f in os.listdir(args.dir) if f.endswith(".el"))
    raw = {f: open(os.path.join(args.dir, f), encoding="utf-8",
                   errors="replace").read() for f in files}

    # where everything really is, and with what arglist
    home, args_of, kind_of = {}, {}, {}
    for f, s in raw.items():
        for m in DEFN.finditer(s):
            name = m.group(2)
            if name in home:
                continue
            home[name] = f[:-3]
            kind_of[name] = m.group(1)
            args_of[name] = arglist_at(s, m.start())

    fixes, findings = {}, []
    for f, s in raw.items():
        out, moved = s, 0
        for m in DECL.finditer(s):
            name, said_file, said_args = m.group(1), m.group(2), m.group(3)
            said_file = said_file.strip('"') if said_file.startswith('"') \
                else said_file
            said_args = (said_args or "").strip()

            ours = name.startswith(("diogenes", "classicist", "tei-",
                                    "diorisis", "treebank"))
            if name not in home:
                # NOT OURS AND NOT FOUND is the ordinary case for an optional
                # package: `pdf-info', `evil-core', `org-roam' are declared
                # correctly and are simply not on this load-path.
                # `check-declare' says "file not found" for those, and it is
                # noise.  Ours being missing is a finding.
                if ours:
                    findings.append((f, name, said_file, "DEFINED NOWHERE"))
                continue
            if not ours:
                continue
            real_file = home[name]
            if real_file not in {x[:-3] for x in files}:
                continue
            real_args = args_of[name]
            keyed = real_args and "&key" in real_args
            want_args = "t" if keyed else (real_args or "t")

            bad_file = said_file != real_file
            bad_args = (said_args != want_args) and not (
                said_args == "t" and keyed)
            if not (bad_file or bad_args):
                continue
            if said_file in ("nil", "t"):
                findings.append((f, name, said_file,
                                 "MALFORMED -- the file slot holds "
                                 + said_file))
            new = (f"(declare-function {name} \"{real_file}\" {want_args})")
            out = out.replace(m.group(0), new, 1)
            moved += 1
            why = []
            if bad_file:
                why.append(f"file {said_file} -> {real_file}")
            if bad_args:
                why.append(f"arglist {said_args or '(none)'} -> {want_args}"
                           + ("  [cl-defun with &key]" if keyed else ""))
            findings.append((f, name, said_file, "; ".join(why)))
        if moved:
            fixes[f] = out

    by_reason = {}
    for f, name, said, why in findings:
        by_reason.setdefault(why.split(";")[0].split(" ->")[0], []).append(
            (f, name, why))
    print(f"{len(findings)} declarations to change, in {len(fixes)} files\n")
    for f, name, said, why in sorted(findings):
        print(f"  {f:28} {name:44} {why}")

    nowhere = [x for x in findings if "DEFINED NOWHERE" in x[3]]
    if nowhere:
        print("\nDEFINED NOWHERE -- for a person, not for this tool.  The\n"
              "answer may be a typo, a rename, or a function never written;\n"
              "all three have turned up:")
        for f, name, said, _ in nowhere:
            print(f"  {f}: {name}  (said {said})")

    if not args.write:
        print("\nDRY RUN.  Add --write to apply.")
        return
    for f, s in fixes.items():
        open(os.path.join(args.dir, f), "w", encoding="utf-8").write(s)
    print(f"\nWritten: {len(fixes)} files.")
    print("CHECK:  emacs -Q --batch -L . --eval \"(progn (require "
          "'check-declare) (check-declare-directory default-directory))\"")


if __name__ == "__main__":
    main()
