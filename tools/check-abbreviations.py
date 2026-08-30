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


# Prepositions, which belong to a Latin title and not to the abbreviation:
# `de Sen.\' and `Sen.\' are De Senectute twice, `post Red. in Sen.\' and
# `Red. in Sen.\' one oration.  `c\' is deliberately absent though it can mean
# `cum\': dropping it mangles `C. S.\', the Carmen Saeculare.
PREPOSITIONS = {"de", "ad", "in", "post", "contra", "adv", "ex", "pro", "cum",
                "apud", "ap"}


def title_parts(abbrev):
    """ABBREV as its meaningful components, folded and stripped of prepositions."""
    bits = re.split(r"[\s.]+", abbrev.lower())
    return [bit for bit in bits if bit and bit not in PREPOSITIONS]


def one_title(first, second):
    """Whether FIRST and SECOND are one title abbreviated two ways.

    These dictionaries shorten COMPONENT BY COMPONENT and to no fixed length:
    `Bell. Pun.\' and `B. Pun.\', `Pet. Cons.\' and `Petit. Cons.\', `C. S.\' and
    `Carm. Sec.\', `Excerpt. Contr.\' and `Exc. Contr.\'.  And a component may be
    dropped altogether -- `Part.\' for `Part. Or.\', `Epit.\' for `Epit. lib.\'.

    So: each component of the shorter a prefix of the corresponding component of
    the longer, or the reverse.  Which merges those eight and leaves the real
    collections alone -- `APo.\' beside `APr.\', `Cleom.\' beside `Agis\', `Od.\'
    beside `Fr.\'.  Thirty-six pairs from a live run, every one as wanted.

    Whitespace alone was not enough, and comparing whole strings was not
    enough.  The dictionaries are irregular in three ways at once."""
    left, right = title_parts(first), title_parts(second)
    if not left or not right:
        return False
    short, long = (left, right) if len(left) <= len(right) else (right, left)
    for part, whole in zip(short, long):
        if not (part.startswith(whole) or whole.startswith(part)):
            return False
    return True


def compare_form(abbrev):
    """ABBREV reduced to what distinguishes it from another abbreviation.

    A rough key for grouping; `one_title\' is the real test.  Kept because
    identical-but-for-space is the commonest case by far and worth a cheap
    answer."""
    return re.sub(r"\s+", "", abbrev).lower()


def clean(raw):
    return re.sub(r"\s+", " ", raw.decode("utf-8", "replace").strip())


def read_catalogue(path):
    """Every (corpus, author, work) the Perseus catalogue knows, from a tarball.

    An authority independent of the dictionaries: the catalogue says which texts
    exist and under what numbers, where the dictionaries only say what they
    happened to cite.  So it catches what a count cannot -- a work number that
    is not a work at all.

    Read from the FILENAMES, which carry the identifiers, rather than from the
    MODS records inside: 38,505 records is a great deal to parse for a fact the
    paths already state."""
    import tarfile
    pairs = set()
    name = re.compile(r"(tlg|phi)(\d{4})\.(?:abo|tlg|phi)(\d+)")
    try:
        with tarfile.open(path, "r:*") as archive:
            for member in archive:
                found = name.search(os.path.basename(member.name))
                if found:
                    corpus, author, work = found.groups()
                    pairs.add((corpus, author, work))
    except (OSError, tarfile.TarError) as error:
        sys.stderr.write("Cannot read the catalogue: %s\n" % error)
        return None
    return pairs


def read_diogenes_works(path):
    """Every (corpus, author, work) Diogenes holds, from list-diogenes-works.pl.

    THE authority, and the only one that answers the question a reader has: what
    can I browse?  The Perseus catalogue covers 1627 authors where the TLG alone
    has 1823, so a number absent from it proves nothing -- Epictetus, Philo and
    Hermogenes are all absent from the catalogue and all real."""
    pairs = set()
    try:
        with open(path, encoding="utf-8") as handle:
            for line in handle:
                bits = line.split()
                if len(bits) == 3:
                    pairs.add(tuple(bits))
    except OSError as error:
        sys.stderr.write("Cannot read %s: %s\n" % (path, error))
        return None
    return pairs


def report_absent(table, catalogue, what, conclusive):
    """Table entries naming a work the authority does not have.

    CONCLUSIVE says whether absence is a verdict.  For Diogenes it is: what it
    does not hold cannot be browsed, so an abbreviation for it can never be
    used.  For the Perseus catalogue it is not, the catalogue being partial."""
    if not catalogue:
        return
    authors = {(corpus, author) for (corpus, author, _) in catalogue}
    missing_works = []
    missing_authors = []
    for key in sorted(table):
        if len(key) == 3:
            if key not in catalogue:
                missing_works.append(key)
        elif key not in authors:
            missing_authors.append(key)
    print()
    print("=== AGAINST %s ===" % what)
    print("%d works and %d authors known there" % (len(catalogue), len(authors)))
    if not conclusive:
        print("Absence here is NOT a verdict: this authority is partial, and "
              "Epictetus,")
        print("Philo and Hermogenes are among the real authors it omits.")
    if missing_authors:
        print("\n%d AUTHORS the catalogue does not have:" % len(missing_authors))
        for key in missing_authors[:40]:
            print("  %-12s -> %s" % ("/".join(key), table[key]))
    if missing_works:
        print("\n%d WORKS the catalogue does not have:" % len(missing_works))
        for key in missing_works[:60]:
            print("  %-18s -> %s" % ("/".join(key), table[key]))
    if not missing_authors and not missing_works:
        print("\nEvery entry names a text the catalogue knows.")


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
    """Every abbreviation for KEY, commonest first, whitespace variants merged.

    Merging matters more than it looks.  Before it, the survey called
    ninety-nine works collections and most were a title beside itself with a
    space moved -- `Comp. Phil.Flam.\' at three citations and
    `Comp.Phil.Flam.\' at one, which any ratio rule flags and which is one
    abbreviation."""
    found = [(abbrev, n) for ((k, abbrev), n) in counter.items() if k == key]
    groups = []
    for abbrev, count in sorted(found, key=lambda pair: -pair[1]):
        for group in groups:
            if one_title(group[0], abbrev):
                group[1] += count
                break
        else:
            groups.append([abbrev, count])
    return sorted((tuple(g) for g in groups), key=lambda pair: -pair[1])


def report(counter, table, keys, how_many, what):
    """Print HOW-MANY of KEYS with their support, and return what is amiss.

    Returns (DISPUTED, UNSUPPORTED).  Sampled by how often a thing is cited, so
    a partial run covers what a reader is likeliest to meet rather than the
    lowest numbers."""
    support = {}
    for key in keys:
        found = alternatives(counter, key)
        support[key] = found[0][1] if found else 0
    keys = sorted(keys, key=lambda k: -support[k])[:how_many]

    disputed = []
    unsupported = []
    print()
    print("=== %s ===" % what)
    print("%-18s %-22s %7s   %s"
          % ("KEY", "TABLE SAYS", "CITED", "ALTERNATIVES"))
    print("-" * 86)
    for key in keys:
        found = alternatives(counter, key)
        given = table[key]
        best = found[0] if found else ("", 0)
        floor = max(2, min(3, best[1] // 20))
        others = [pair for pair in found[1:] if pair[1] >= floor]
        if not found:
            unsupported.append(key)
        elif best[0] != given:
            disputed.append((key, given, found))
            # A DISPUTE always shows its rival, whatever the floor: the whole
            # point of the row is that the table chose one and the dictionaries
            # prefer another, and hiding the other for being uncommon leaves a
            # reader with a complaint and no evidence.
            others = found[1:4]
        print("%-18s %-22s %7d   %s"
              % ("/".join(key), given, best[1],
                 ", ".join("%s (%d)" % pair for pair in others) or "-"))
    return disputed, unsupported


def summarise(what, sampled, total, disputed, unsupported, table):
    print()
    print("%d %s sampled, of %d in the table" % (sampled, what, total))
    if disputed:
        print("\nDISPUTED %s -- the table does not give the commonest:" % what)
        for key, given, found in disputed:
            print("  %-18s table %-20s dictionaries %s"
                  % ("/".join(key), given,
                     ", ".join("%s (%d)" % pair for pair in found[:4])))
    else:
        print("\nNo disputes among the %s: each is the commonest the "
              "dictionaries give." % what)
    if unsupported:
        print("\nUNSUPPORTED %s -- in the table, cited nowhere:" % what)
        for key in unsupported:
            print("  %s -> %s" % ("/".join(key), table[key]))


def survey(works, table, work_keys):
    """What remains questionable, by kind rather than one row at a time.

    The faults found so far have each been a KIND of fault -- a count threshold
    discarding rare citations, a regexp missing an attribute, a number naming a
    collection -- and each was found by accident.  This groups what is left so
    that a kind is visible without meeting an instance of it."""
    collections = []
    close = []
    thin = []
    for key in work_keys:
        found = alternatives(works, key)
        if len(found) < 2:
            if found and found[0][1] < 3:
                thin.append((key, found[0]))
            continue
        best, second = found[0], found[1]
        share = second[1] / best[1] if best[1] else 0
        if share > 0.25:
            collections.append((key, found))
        elif share > 0.05:
            close.append((key, found))

    print()
    print("=== WHAT REMAINS QUESTIONABLE ===")
    print()
    print("%d works whose second title has more than a QUARTER of the "
          "commonest's" % len(collections))
    print("   -- these name a collection and should carry no work "
          "abbreviation:")
    for key, found in collections[:25]:
        print("   %-18s %s" % ("/".join(key),
                               ", ".join("%s (%d)" % p for p in found[:4])))
    print()
    print("%d works whose second title has between a twentieth and a quarter"
          % len(close))
    print("   -- a spelling variant, or a collection the threshold missed:")
    for key, found in close[:25]:
        print("   %-18s %s" % ("/".join(key),
                               ", ".join("%s (%d)" % p for p in found[:4])))
    print()
    print("%d works resting on fewer than three citations" % len(thin))
    print("   -- right about what the dictionary says, and thin evidence "
          "that it meant this work:")
    for key, found in thin[:20]:
        print("   %-18s %s (%d)" % ("/".join(key), found[0], found[1]))


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

    author_keys = [k for k in table if len(k) == 2]
    work_keys = [k for k in table if len(k) == 3]

    # WORKS as well as authors, and they are where the subtler error hides: an
    # author's abbreviation is wrong loudly -- `Symm.' for Aurelius Victor -- and
    # a work's is wrong quietly, a title attached to its neighbour's number.
    disputed, unsupported = report(authors, table, author_keys, how_many,
                                   "AUTHORS")
    summarise("authors", min(how_many, len(author_keys)), len(author_keys),
              disputed, unsupported, table)

    disputed, unsupported = report(works, table, work_keys, how_many, "WORKS")
    summarise("works", min(how_many, len(work_keys)), len(work_keys),
              disputed, unsupported, table)

    # And against the catalogue, where one is to hand.  This is the check that
    # states a FACT rather than a majority: a work number the catalogue does not
    # list is not a work, whatever the dictionaries did with it.
    survey(works, table, work_keys)

    # DIOGENES first, being the authority that decides.  Made by
    # `tools/list-diogenes-works.pl'; absence here means a reader can never
    # browse the text, so an abbreviation for it can never be used.
    works_path = os.path.expanduser(
        os.environ.get("DIOGENES_WORKS", "/tmp/diogenes-works.txt"))
    if os.path.exists(works_path):
        report_absent(table, read_diogenes_works(works_path),
                      "WHAT DIOGENES HOLDS", True)
    else:
        print()
        print("No list of Diogenes' works at %s." % works_path)
        print("Make one -- it is the authority that settles this -- with:")
        print("  cd /usr/local/diogenes/server")
        print("  perl -I/usr/local/diogenes/dependencies/CPAN -I. \\")
        print("       .../tools/list-diogenes-works.pl > /tmp/diogenes-works.txt")

    # And the Perseus catalogue, which corroborates and does not decide.
    catalogue_path = os.environ.get("PERSEUS_CATALOGUE")
    if catalogue_path:
        catalogue_path = os.path.expanduser(catalogue_path)
    if catalogue_path and os.path.exists(catalogue_path):
        report_absent(table, read_catalogue(catalogue_path),
                      "THE PERSEUS CATALOGUE", False)
    elif catalogue_path:
        print()
        print("No catalogue at %s." % catalogue_path)


if __name__ == "__main__":
    main()
