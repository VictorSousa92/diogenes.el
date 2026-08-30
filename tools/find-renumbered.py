#!/usr/bin/env python3
"""Find abbreviations whose number Diogenes has not got but whose text it has.

Epictetus is the pattern.  The dictionaries cite him as `tlg,0575', which is no
file on the disc; Diogenes has the Discourses under `0557', where Arrian
transmits them.  So the abbreviation is right, the number belongs to another
scheme, and the row is unusable -- until somebody says which number Diogenes
uses, whereupon it is an override.

This looks for the rest of them.  For every author the dictionaries cite that
Diogenes has not got, it reports the abbreviation and then every author
Diogenes DOES hold whose own abbreviation is the same.  A match is a candidate
renumbering: the same text under two numbers.

    tlg/0575 -> Epict.    Diogenes has that abbreviation at: tlg/0557 (Arr.)

It cannot decide.  `Call.' belongs to Callimachus and to Callias and to
Callistratus, so a shared abbreviation is a lead and not a conclusion -- which is
why the output names both and stops.

Run:  python3 tools/find-renumbered.py
Wants DIOGENES_WORKS, from tools/list-diogenes-works.pl.
"""

import collections
import os
import re
import sys

PUTHASH = re.compile(
    r'\(puthash \(list "(tlg|phi)" "(\d{4})"(?: "([0-9-]{3,4})")?\) "([^"]*)" table\)')


BIBL = re.compile(
    rb'<bibl n="Perseus:abo:(tlg|phi),(\d{4}),([0-9-]{3,4})[^>]*>(.{0,300}?)</bibl>',
    re.S)
AUTHOR = re.compile(rb'<author>([^<]{1,40})</author>')
ANAPHORS = {"id.", "ib.", "ibid.", "idem", "ead.", "eadem"}
DICTIONARIES = [("tlg", "grc.lsj.xml"), ("phi", "lat.ls.perseus-eng1.xml")]


def compare_key(abbrev):
    """ABBREV folded, so `Epict.' and `epict' answer to one another."""
    return re.sub(r"[\s.]+", "", abbrev).lower()


def count_dictionaries():
    """{((corpus, author), abbreviation): count} over both dictionaries."""
    root = None
    for candidate in (os.environ.get("DIOGENES_DATA"),
                      "/usr/local/diogenes/dependencies/data"):
        if candidate and os.path.isdir(candidate):
            root = candidate
            break
    if not root:
        sys.exit("Cannot find the Diogenes data directory; set DIOGENES_DATA.")
    counted = collections.Counter()
    for corpus, filename in DICTIONARIES:
        path = os.path.join(root, filename)
        if not os.path.exists(path):
            continue
        with open(path, "rb") as handle:
            data = handle.read()
        for match in BIBL.finditer(data):
            if match.group(1).decode() != corpus:
                continue
            found = AUTHOR.search(match.group(4))
            if not found:
                continue
            name = re.sub(r"\s+", " ",
                          found.group(1).decode("utf-8", "replace").strip())
            if name and name.lower() not in ANAPHORS:
                counted[((corpus, match.group(2).decode()), name)] += 1
    return counted


def read_table(path):
    authors = {}
    works = collections.defaultdict(dict)
    with open(path, encoding="utf-8") as handle:
        for match in PUTHASH.finditer(handle.read()):
            corpus, author, work, abbrev = match.groups()
            if work:
                works[(corpus, author)][work] = abbrev
            else:
                authors[(corpus, author)] = abbrev
    return authors, works


def read_held(path):
    pairs = set()
    with open(path, encoding="utf-8") as handle:
        for line in handle:
            bits = line.split()
            if len(bits) == 3:
                pairs.add(tuple(bits))
    return pairs


def main():
    table_path = "diogenes-abbreviations.el"
    works_path = os.path.expanduser(
        os.environ.get("DIOGENES_WORKS", "/tmp/diogenes-works.txt"))
    for path in (table_path, works_path):
        if not os.path.exists(path):
            sys.exit("No %s." % path)

    authors, works = read_table(table_path)
    held = read_held(works_path)
    authors_held = {(corpus, author) for (corpus, author, _) in held}

    # EVERY abbreviation each held author attracts, not merely the one the
    # table chose.  Epictetus is why: `tlg/0557' is `Arr.' in the table, being
    # what LSJ says 849 times, and attracts `Epict.' 107 times besides.  Looking
    # only at chosen forms missed the case this script was written for.
    counted = count_dictionaries()
    by_abbreviation = collections.defaultdict(set)
    for ((corpus, author), abbrev), n in counted.items():
        if (corpus, author) in authors_held:
            by_abbreviation[compare_key(abbrev)].add(((corpus, author), abbrev, n))

    missing = sorted(key for key in authors if key not in authors_held)
    print("%d authors in the table that Diogenes has not got.\n" % len(missing))

    candidates = []
    orphans = []
    for key in missing:
        abbrev = authors[key]
        elsewhere = sorted(
            (found for found in by_abbreviation.get(compare_key(abbrev), ())
             if found[0] != key),
            key=lambda found: -found[2])
        if elsewhere:
            candidates.append((key, abbrev, elsewhere))
        else:
            orphans.append((key, abbrev))

    print("=== SAME ABBREVIATION ON A NUMBER DIOGENES HAS ===")
    print("Candidates for an override, and each wants deciding by eye:")
    print("a shared abbreviation may be two authors, not one renumbered.\n")
    for key, abbrev, elsewhere in candidates:
        print("  %-12s %-16s also at %s"
              % ("/".join(key), abbrev,
                 ", ".join("%s (%s, %d citations)"
                           % ("/".join(other), form, n)
                           for other, form, n in elsewhere[:3])))

    print()
    print("=== NO COUNTERPART ===")
    print("%d abbreviations for authors Diogenes has not got, and no author it "
          "has\nshares the abbreviation.  Nothing to override: the text is "
          "simply absent.\n" % len(orphans))
    for key, abbrev in orphans[:40]:
        print("  %-12s %s" % ("/".join(key), abbrev))
    if len(orphans) > 40:
        print("  ... and %d more" % (len(orphans) - 40))


if __name__ == "__main__":
    main()
