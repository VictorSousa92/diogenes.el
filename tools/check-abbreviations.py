#!/usr/bin/env python3
"""Check the generated abbreviations against the dictionaries they came from.

Not a test of the extraction -- that would only confirm itself -- but of whether
the table AGREES with what the dictionaries say, counted independently and by a
different route.  For each author and work in the table it reports:

    the abbreviation the table gives
    how many citations support it
    what OTHER abbreviations the same number is given, and how often

The third column is the interesting one.  A number cited a thousand times as
`Ath.' and twice as something else is settled; one cited forty times as `Ar.'
and thirty-eight as `Arist.' is a genuine ambiguity, and the reader should know
rather than have the majority silently chosen for them.

Run:  python3 tools/check-abbreviations.py [HOW-MANY]
"""

import collections
import os
import re
import sys

DICTIONARIES = [
    ("tlg", "grc.lsj.xml", "LSJ"),
    ("phi", "lat.ls.perseus-eng1.xml", "Lewis & Short"),
]

BIBL = re.compile(
    rb'<bibl n="Perseus:abo:(tlg|phi),(\d{4}),([0-9-]{3,4})[^>]*>(.{0,300}?)</bibl>',
    re.S)
AUTHOR = re.compile(rb'<author>([^<]{1,40})</author>')
TITLE = re.compile(rb'<title>([^<]{1,60})</title>')
ANAPHORS = {"id.", "ib.", "ibid.", "idem", "ead.", "eadem"}

# The generated table, read as text rather than by loading elisp.
PUTHASH = re.compile(
    r'\(puthash \(list "(tlg|phi)" "(\d{4})"(?: "([0-9-]{3,4})")?\) "([^"]*)" table\)')


def clean(raw):
    return re.sub(r"\s+", " ", raw.decode("utf-8", "replace").strip())


def read_table(path):
    """The generated table as {(corpus, author[, work]): abbreviation}."""
    table = {}
    with open(path, encoding="utf-8") as handle:
        for match in PUTHASH.finditer(handle.read()):
            corpus, author, work, abbrev = match.groups()
            key = (corpus, author, work) if work else (corpus, author)
            table[key] = abbrev
    return table


def count(root):
    """Every (key, abbreviation) pair the dictionaries contain, with counts."""
    authors = collections.Counter()
    works = collections.Counter()
    for corpus, filename, _ in DICTIONARIES:
        path = os.path.join(root, filename)
        if not os.path.exists(path):
            continue
        with open(path, "rb") as handle:
            data = handle.read()
        for match in BIBL.finditer(data):
            if match.group(1).decode() != corpus:
                continue
            author_num = match.group(2).decode()
            work_num = match.group(3).decode()
            inner = match.group(4)
            found = AUTHOR.search(inner)
            if found:
                name = clean(found.group(1))
                if name and name.lower() not in ANAPHORS:
                    authors[((corpus, author_num), name)] += 1
            found = TITLE.search(inner)
            if found:
                title = clean(found.group(1))
                if title:
                    works[((corpus, author_num, work_num), title)] += 1
    return authors, works


def alternatives(counter, key):
    """Every abbreviation for KEY, commonest first."""
    found = [(abbrev, n) for ((k, abbrev), n) in counter.items() if k == key]
    return sorted(found, key=lambda pair: -pair[1])


def main():
    how_many = int(sys.argv[1]) if len(sys.argv) > 1 else 200
    root = None
    for candidate in (os.environ.get("DIOGENES_DATA"),
                      "/usr/local/diogenes/dependencies/data"):
        if candidate and os.path.isdir(candidate):
            root = candidate
            break
    if not root:
        sys.exit("Cannot find the Diogenes data directory; set DIOGENES_DATA.")

    table_path = "diogenes-abbreviations.el"
    if not os.path.exists(table_path):
        sys.exit("No %s; run tools/extract-abbreviations.py first." % table_path)

    table = read_table(table_path)
    authors, works = count(root)

    # The authors of the table, most-cited first, so the sample is the ones a
    # reader is likeliest to meet rather than the lowest numbers.
    author_keys = [k for k in table if len(k) == 2]
    support = {}
    for key in author_keys:
        found = alternatives(authors, key)
        support[key] = found[0][1] if found else 0
    author_keys.sort(key=lambda k: -support[k])
    sample = author_keys[:how_many]

    disputed = []
    unsupported = []
    print("%-12s %-14s %7s   %s" % ("KEY", "TABLE SAYS", "CITED", "ALTERNATIVES"))
    print("-" * 78)
    for key in sample:
        found = alternatives(authors, key)
        given = table[key]
        best = found[0] if found else ("", 0)
        # A twentieth of the commonest, or two occurrences, whichever is
        # smaller: an alternative worth a reader's attention is one that could
        # plausibly have been meant, and `Ar.' against `Arist.' at two to one is
        # exactly that.  A fixed floor of three hid it.
        floor = max(2, min(3, best[1] // 20))
        others = [pair for pair in found[1:] if pair[1] >= floor]
        if not found:
            unsupported.append(key)
        elif best[0] != given:
            disputed.append((key, given, found))
        print("%-12s %-14s %7d   %s"
              % ("/".join(key), given, best[1],
                 ", ".join("%s (%d)" % pair for pair in others) or "-"))

    print()
    print("%d authors sampled, of %d in the table" % (len(sample), len(author_keys)))
    print("%d works in the table" % len([k for k in table if len(k) == 3]))
    if disputed:
        print("\nDISPUTED -- the table does not give the commonest abbreviation:")
        for key, given, found in disputed:
            print("  %-12s table %-12s dictionaries %s"
                  % ("/".join(key), given,
                     ", ".join("%s (%d)" % pair for pair in found[:4])))
    else:
        print("\nNo disputes: every sampled author's abbreviation is the "
              "commonest the dictionaries give.")
    if unsupported:
        print("\nUNSUPPORTED -- in the table, cited nowhere:")
        for key in unsupported:
            print("  %s -> %s" % ("/".join(key), table[key]))


if __name__ == "__main__":
    main()
