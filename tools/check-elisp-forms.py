#!/usr/bin/env python3
"""Read an elisp file far enough to check the shape of its defcustom forms.

The failure being looked for is a docstring closed early by an unescaped
quote, which turns the rest of the form into rubbish while leaving the parens
balanced -- so a paren check passes and the form is still wrong.
"""
import os
import re
import sys


class Reader:
    def __init__(self, text):
        self.t, self.i, self.n = text, 0, len(text)

    def skip(self):
        while self.i < self.n:
            c = self.t[self.i]
            if c in " \t\n\r\f":
                self.i += 1
            elif c == ";":
                while self.i < self.n and self.t[self.i] != "\n":
                    self.i += 1
            else:
                return

    def read(self):
        self.skip()
        if self.i >= self.n:
            return None
        c = self.t[self.i]
        if c == '"':
            return self.string()
        if c in "([":
            return self.seq(")" if c == "(" else "]")
        if c in ")]":
            self.i += 1
            return ("unexpected-close",)
        if c == "?":
            start = self.i
            self.i += 1
            if self.i < self.n and self.t[self.i] == "\\":
                self.i += 2
                while self.i < self.n and self.t[self.i] not in " \t\n()[];\"":
                    self.i += 1
            else:
                self.i += 1
            return ("char", self.t[start:self.i])
        if c in "'`,#":
            self.i += 1
            if c == "," and self.i < self.n and self.t[self.i] == "@":
                self.i += 1
            inner = self.read()
            return ("quote", inner)
        return self.atom()

    def string(self):
        self.i += 1
        out = []
        while self.i < self.n:
            c = self.t[self.i]
            if c == "\\":
                out.append(self.t[self.i:self.i + 2])
                self.i += 2
                continue
            if c == '"':
                self.i += 1
                return ("string", "".join(out))
            out.append(c)
            self.i += 1
        return ("string-unterminated", "".join(out))

    def seq(self, close):
        self.i += 1
        items = []
        while True:
            self.skip()
            if self.i >= self.n:
                return ("list-unterminated", items)
            if self.t[self.i] in ")]":
                self.i += 1
                return ("list", items)
            before = self.i
            items.append(self.read())
            if self.i == before:
                self.i += 1

    def atom(self):
        start = self.i
        while self.i < self.n:
            c = self.t[self.i]
            if c == "\\":
                self.i += 2
                continue
            if c in " \t\n\r\f()[];\"'`,":
                break
            self.i += 1
        return ("atom", self.t[start:self.i])


def name_of(node):
    return node[1] if node and node[0] == "atom" else None


def check(path):
    text = open(path, encoding="utf-8", errors="replace").read()
    reader = Reader(text)
    problems, seen = [], 0
    while True:
        node = reader.read()
        if node is None:
            break
        if node[0] != "list":
            continue
        items = node[1]
        if not items:
            continue
        head = name_of(items[0])
        if head not in ("defcustom", "defvar", "defun", "defface"):
            continue
        if head != "defcustom":
            continue
        seen += 1
        symbol = name_of(items[1]) if len(items) > 1 else "?"
        # (defcustom SYMBOL STANDARD DOC &rest KEYWORD VALUE ...)
        if len(items) < 4:
            problems.append("%s: too few parts" % symbol)
            continue
        doc = items[3]
        if doc[0] != "string":
            problems.append("%s: the docstring is %s, not a string"
                            % (symbol, doc[0]))
            continue
        rest = items[4:]
        if len(rest) % 2:
            problems.append("%s: %d parts after the docstring, an odd number "
                            "-- a keyword is missing its value"
                            % (symbol, len(rest)))
        for j in range(0, len(rest) - 1, 2):
            key = name_of(rest[j])
            if key is None or not key.startswith(":"):
                problems.append("%s: expected a keyword, found %r"
                                % (symbol, rest[j][1] if len(rest[j]) > 1
                                   else rest[j][0]))
        keys = [name_of(rest[j]) for j in range(0, len(rest) - 1, 2)]
        if ":type" not in keys:
            problems.append("%s: no :type" % symbol)
        if ":group" not in keys:
            problems.append("%s: no :group" % symbol)
    return seen, problems


DEFINERS = ("defun", "defmacro", "define-derived-mode", "define-minor-mode",
            "cl-defun", "defsubst", "transient-define-prefix",
            "transient-define-argument", "transient-define-infix",
            "transient-define-suffix")


def duplicates(path):
    """Names a file defines more than once.

    THE FAULT THIS EXISTS FOR is the worst of the three this file checks,
    because the later definition WINS: rewriting a section and leaving the old
    functions below it does not shadow them, it replaces the new ones.  It
    happened to `tei-diorisis-lemmata\', whose old body read a key the new
    cache no longer held, so the vocabulary came back empty and the prompt was
    silently useless -- the compiler said `defined multiple times\' and
    nothing else did."""
    with open(path, encoding="utf-8") as handle:
        text = handle.read()
    prefix = os.path.basename(path)[:-3]
    # FUNCTIONS AND VARIABLES ARE TWO NAMESPACES in elisp, so a name may be
    # both without either shadowing the other -- which the first version of
    # this check did not know, and reported three names that were fine.  They
    # were confusing all the same and were renamed; the check now counts the
    # two separately, which is the truth about the language.
    groups = {"function": DEFINERS,
              "variable": ("defcustom", "defvar", "defvar-local",
                           "defvar-keymap", "defconst", "defface")}
    twice = []
    for kind, definers in groups.items():
        seen = {}
        for definer in definers:
            for match in re.finditer(r"\(%s\s+(%s[^\s()]*)"
                                     % (re.escape(definer),
                                        re.escape(prefix)), text):
                name = match.group(1)
                line = text[:match.start()].count("\n") + 1
                if name in seen:
                    twice.append(("%s %s" % (kind, name), seen[name], line))
                else:
                    seen[name] = line
    return twice


def calls(path):
    """Functions a file calls with its own prefix but never defines.

    WHY THIS IS WORTH CHECKING.  An edit that replaces a span of a file can
    take a function out along with the one it meant to replace, and nothing
    notices: the parens still balance, the defcustoms are still well formed,
    and the fault appears months later as `Symbol's function definition is
    void' the first time anybody presses the key that needs it.  It happened
    while `tei-diorisis-read-lemma' was being rewritten, and two functions
    four other places call went with it.

    ONLY `#\'name' AND `(name ' COUNT as calls.  A quoted symbol may be a text
    property or a face or a mode name being passed as data -- `tei-diorisis-hit'
    is a property on every character of a hit -- and those are not calls and
    are not missing anything."""
    with open(path, encoding="utf-8") as handle:
        text = handle.read()
    # The prefix is the file's own name, which is this project's convention.
    prefix = os.path.basename(path)[:-3]
    defined = set()
    for definer in DEFINERS:
        defined |= set(re.findall(r"\(%s\s+([^\s()]+)" % re.escape(definer),
                                  text))
    # A `defalias' or a `defvar' holding a lambda is neither, and neither is
    # anything the file only declares: those are other files' business.
    declared = set(re.findall(r"\(declare-function\s+([^\s()]+)", text))
    # VARIABLES COUNT AS KNOWN, because a `cond' clause reads exactly like a
    # call: `(tei-diorisis-show-beta-code beta)' is a test and its value, not
    # a function of one argument.  The cost is that a call to a function that
    # happens to share a variable's name would pass, which is a thing nobody
    # does; the gain is a check with no noise in it, which is a check that
    # gets read.
    declared |= set(re.findall(
        r"\((?:defcustom|defvar|defvar-local|defvar-keymap|defconst|defface)"
        r"\s+([^\s()]+)", text))
    called = set(re.findall(r"#'(%s[a-zA-Z0-9<>=/+*-]*)" % re.escape(prefix),
                            text))
    # A QUOTED LIST IS DATA AND NOT A CALL.  `\'(tei-diorisis-greek ...)' is a
    # completion style being registered and `\'(tei-diorisis-lemma (styles
    # ...))' a category override: both read exactly like a function at the
    # head of a form, and neither is one.  So a head preceded by a quote,
    # a backquote or a hash is passed over.
    called |= set(re.findall(r"(?<![\'`#])\((%s[a-zA-Z0-9<>=/+*-]*)[\s)]"
                             % re.escape(prefix), text))
    return sorted(name for name in called
                  if name not in defined and name not in declared)


def assignments(path):
    """Variables a file assigns above the line that declares them.

    THE FAULT THIS EXISTS FOR has now happened four times in one file:
    `tei-diorisis-forget-vocabulary' clears half a dozen caches and stands
    above the code that fills them, so each new cache was assigned before its
    own `defvar' -- which the byte-compiler calls an assignment to a free
    variable, and which is a real fault in a file loaded in another order.

    Only the file's own prefix, and only `setq': a `let' binding of an
    undeclared name is a different question and a lexical one."""
    with open(path, encoding="utf-8") as handle:
        text = handle.read()
    prefix = os.path.basename(path)[:-3]
    declared = {}
    for match in re.finditer(
            r"\((?:defvar|defvar-local|defcustom|defconst)\s+"
            r"(%s[^\s()]*)" % re.escape(prefix), text):
        declared.setdefault(match.group(1), match.start())
    early = []
    for match in re.finditer(r"\(setq\s+(%s[^\s()]*)" % re.escape(prefix),
                             text):
        name = match.group(1)
        where = declared.get(name)
        if where is None or where > match.start():
            early.append((name, text[:match.start()].count("\n") + 1,
                          "assigned"))
    # AND READ BEFORE IT IS DECLARED, which is the same fault and the commoner
    # one: a function written later and inserted above the `defvar' that
    # declares what it reads.  Three of those appeared in one afternoon, in
    # code that had been moved rather than written.
    #
    # A QUOTED NAME IS NOT A READ -- `\'tei-diorisis-form-face' is a face being
    # named, `#\'tei-diorisis-foo' a function -- so a name preceded by a quote
    # or a hash is passed over, as are the declarations themselves.
    for name, where in declared.items():
        for match in re.finditer(r"(?<![\'`#])\b%s\b" % re.escape(name),
                                 text[:where]):
            # A longer name that merely begins with this one is not this one.
            after = text[match.end():match.end() + 1]
            if after and (after.isalnum() or after in "-_"):
                continue
            early.append((name, text[:match.start()].count("\n") + 1,
                          "read"))
            break
    return sorted(early, key=lambda one: one[1])


for path in sys.argv[1:]:
    seen, problems = check(path)
    print("%s: %d defcustom forms" % (path, seen))
    for p in problems:
        print("   TROUBLE  %s" % p)
    if not problems:
        print("   all well formed")
    twice = duplicates(path)
    for name, first, again in twice:
        print("   TROUBLE  %s is defined at line %d and again at line %d"
              % (name, first, again))
        problems.append("defined twice")
    if not twice:
        print("   nothing defined twice")
    early = assignments(path)
    for name, line, how in early:
        print("   TROUBLE  line %d: %s is %s above its declaration"
              % (line, name, how))
        problems.append("early use")
    if not early:
        print("   nothing used before it is declared")
    missing = calls(path)
    if missing:
        print("   TROUBLE  called but defined nowhere in this file: %s"
              % ", ".join(missing))
        problems.append("missing definitions")
    else:
        print("   every function it calls, it defines")
    if problems:
        sys.exit(1)
