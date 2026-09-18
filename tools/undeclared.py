#!/usr/bin/env python3
r"""What each file uses and has not said it uses.

    python3 undeclared.py                      # every file
    python3 undeclared.py diogenes-search.el   # one

WRITTEN AFTER NINE FALSE POSITIVES IN ONE DAY, from five causes, each of
which this now accounts for:

  1. DOCSTRINGS READ AS CODE.  `diogenes--focus-role' appeared to reach every
     dictionary module through a name in the docstring of the command that
     calls it.  Four more the same.  So: strip strings, not only comments.

  2. QUOTED DATA READ AS REFERENCES.  `(diogenes-browser-mode . browser)' in
     a role table is a symbol in an alist, matched against `major-mode' at run
     time; the mode need not be defined for the file to compile.  Following it
     left the module and never came back -- a closure of 747 forms in a
     39-file package.  Not fully solvable by regexp; the report says which
     hits are inside a quote so a reader can judge.

  3. A DEFINER REGEXP TOO NARROW.  `transient-define-prefix' and
     `-argument' missing cost fourteen forms and made two README names look
     undefined; `defvar-keymap' missing cost eight more, and those held the
     real straddle.  So: check the list against the file's own top-level
     forms, and say so when something matches `^\(' and no definer.

  4. `declare-function' UNCOUNTED.  `diogenes-corpora.el' declares all five
     of its bridge symbols with accurate arglists.  A walker that counts only
     `require' reports every honestly-declared file as broken.

  5. TRANSITIVE REQUIRES UNCOUNTED.  `diogenes-forms.el' reaches four foreign
     functions through `diogenes-perseus', which requires both files they are
     in.  Nothing warns, because `batch-byte-compile' loads a required file as
     source.  So the report separates DIRECT from TRANSITIVE: the first is a
     fault, the second is a file not saying what it depends on.

AND A SIXTH, which is not about references at all: a value expression can
constrain the load order independently of the graph.
`diogenes--corpora-abbrevs' is `(mapcar #\='car diogenes--corpora)', so it
cannot be moved without the table, whatever the references say.  No tool here
will catch that; it is why the report is for reading rather than for acting on.
"""
import argparse
import os
import re
import sys

DEFINER = re.compile(
    r"^\s*\((?:cl-)?(?:defun|defmacro|defsubst|defcustom|defvar|defvar-local"
    r"|defvar-keymap|defconst|defface|define-derived-mode|define-minor-mode"
    r"|cl-defstruct|defgroup|transient-define-prefix|transient-define-argument"
    r"|transient-define-suffix|defalias|define-obsolete-function-alias"
    r"|define-obsolete-variable-alias)\s+'?([^\s()]+)", re.M)

TOPLEVEL = re.compile(r"^\((?!;)", re.M)
REQUIRE = re.compile(r"^\(require '([a-z0-9-]+)", re.M)
DECLARE = re.compile(r"^\(declare-function\s+(\S+)", re.M)
DEFVAR_BARE = re.compile(r"^\(defvar\s+(\S+)\)", re.M)

BEFORE = r"(?<![-A-Za-z0-9_+*/=<>!?])"
AFTER = r"(?![-A-Za-z0-9_+*/=<>!?])"


def strip_noise(text):
    """Comments and strings out, so prose cannot read as code.

    LESSON ONE.  A docstring naming a function is not a call, and five of the
    day's false leads were exactly that.  Character literals first, so `?\"'
    does not open a string that swallows the file.
    """
    out = []
    i = 0
    while i < len(text):
        c = text[i]
        if c == "?" and i + 1 < len(text) and text[i + 1] in "();\"\\":
            out.append("  ")
            i += 2
        elif c == "\\" and i + 1 < len(text):
            out.append("  ")
            i += 2
        elif c == '"':
            i += 1
            while i < len(text):
                if text[i] == "\\":
                    i += 2
                    continue
                if text[i] == '"':
                    i += 1
                    break
                i += 1
            out.append(' "" ')
        elif c == ";":
            nl = text.find("\n", i)
            i = nl if nl > 0 else len(text)
            out.append("\n")
        else:
            out.append(c)
            i += 1
    return "".join(out)


def quoted_spans(code):
    """Rough spans of `'(...)' and '`(...)', where a symbol is data."""
    spans = []
    for m in re.finditer(r"[\'`]\(", code):
        depth, i = 0, m.end() - 1
        while i < len(code):
            if code[i] == "(":
                depth += 1
            elif code[i] == ")":
                depth -= 1
                if depth == 0:
                    spans.append((m.start(), i))
                    break
            i += 1
    return spans


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("files", nargs="*")
    ap.add_argument("--dir", default=".")
    args = ap.parse_args()

    names = sorted(f for f in os.listdir(args.dir) if f.endswith(".el"))
    raw = {f: open(os.path.join(args.dir, f), encoding="utf-8",
                   errors="replace").read() for f in names}

    owner, defined = {}, {}
    for f, s in raw.items():
        got = {m.group(1) for m in DEFINER.finditer(s)}
        defined[f] = got
        for n in got:
            owner.setdefault(n, f)

    # LESSON THREE: is the definer list complete for these files?
    short = {}
    for f, s in raw.items():
        odd = []
        for m in TOPLEVEL.finditer(s):
            head = s[m.start():m.start() + 140]
            if not DEFINER.match(head) and not re.match(
                    r"^\((?:require|provide|declare-function|add-to-list|setq"
                    r"|with-eval-after-load|eval-when-compile|if|when|unless"
                    r"|let|dolist|autoload|put|global-set-key|custom-)", head):
                odd.append((s[:m.start()].count("\n") + 1,
                            head.split("\n")[0][:58]))
        if odd:
            short[f] = odd

    reqs = {f: {m.group(1) + ".el" for m in REQUIRE.finditer(s)}
            for f, s in raw.items()}

    def closure(f, seen=None):
        seen = seen or set()
        for r in reqs.get(f, ()):
            if r in seen or r not in raw:
                continue
            seen.add(r)
            closure(r, seen)
        return seen

    targets = args.files or names
    for f in targets:
        if f not in raw:
            print(f"?? {f}")
            continue
        s = raw[f]
        code = strip_noise(s)
        qs = quoted_spans(code)
        said = ({m.group(1) for m in DECLARE.finditer(s)}
                | {m.group(1) for m in DEFVAR_BARE.finditer(s)})
        direct = reqs[f] | {f}
        indirect = closure(f) - direct

        rows = []
        for n, home in owner.items():
            if home in direct or n in defined[f] or n in said:
                continue
            m = re.search(BEFORE + re.escape(n) + AFTER, code)
            if not m:
                continue
            quoted = any(a <= m.start() <= b for a, b in qs)
            rows.append((home in indirect, quoted, home, n))
        if not rows and f not in short:
            continue

        print(f"\n### {f}")
        for tag, label in ((False, "UNDECLARED -- not required, not "
                                   "declared, not reachable"),
                           (True, "transitive -- reached through a require, "
                                  "and not said")):
            these = [r for r in rows if r[0] == tag]
            if not these:
                continue
            print(f"  {label}")
            for _, quoted, home, n in sorted(these, key=lambda r: (r[2], r[3])):
                q = "  [quoted -- may be data, lesson two]" if quoted else ""
                print(f"     {home:30} {n}{q}")
        if f in short:
            print("  top-level forms this definer list does not know "
                  "(lesson three)")
            for ln, head in short[f][:6]:
                print(f"     {ln:5}  {head}")


if __name__ == "__main__":
    main()
