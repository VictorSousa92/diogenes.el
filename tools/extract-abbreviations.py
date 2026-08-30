#!/usr/bin/env python3
"""Extract the LSJ and Lewis & Short abbreviations from the Perseus dictionaries.

Diogenes ships both dictionaries as TEI, and every citation in them carries the
TLG or PHI numbers of the text it cites together with the abbreviation the
dictionary uses for it:

    <bibl n="Perseus:abo:phi,0134,006:254"><author>Ter.</author>
      <title>Ad.</title> 254</bibl>

So the crosswalk between numbers and abbreviations is IN THE DATA, and needs no
table typed out from the printed lists -- which could not be joined to numbers
anyway, `Arist. Metaph.' saying nothing about `0086/025'.

The author and the title are INSIDE the <bibl>, which is the whole trick.  An
earlier attempt paired each <bibl> with the nearest <author> BEFORE it and
attributed Plautus to Terence throughout, the previous citation's author being
the one it found.  The counts gave it away: `Ter.' now has 5798 occurrences
where the guess had `Plaut.' with 2388.

Keyed by WORK, with the author as a supplement.  Homer is cited `Il.' and `Od.'
and hardly ever with his name, so a table of authors alone would miss him
entirely -- his author tag appears twice in the whole of the LSJ.

Run:  python3 tools/extract-abbreviations.py > diogenes-abbreviations.el
"""

import collections
import os
import re
import sys

DICTIONARIES = [
    ("tlg", "grc.lsj.xml", "LSJ"),
    ("phi", "lat.ls.perseus-eng1.xml", "Lewis & Short"),
]

# `[^>]*>' and not `[^"]*">', which cost forty per cent of the LSJ.  The tag
# often carries another attribute after the identifier:
#
#     <bibl n="Perseus:abo:tlg,0008,001:5:207c" default="NO"><author>Ath.</author>
#
# and a pattern demanding `>' straight after the closing quote finds a space
# instead and skips the whole citation.  266,035 citations matched where
# 439,887 exist -- Athenaeus absent from the table with 2849 of them, every one
# tagged `default="NO"'.
#
# Found by asking why one author was missing and testing the pattern piece by
# piece; nothing about the count of rows suggested a third of them were absent.
BIBL = re.compile(
    rb'<bibl n="Perseus:abo:(tlg|phi),(\d{4}),([0-9-]{3,4})[^>]*>(.{0,300}?)</bibl>',
    re.S)
AUTHOR = re.compile(rb'<author>([^<]{1,40})</author>')
TITLE = re.compile(rb'<title>([^<]{1,60})</title>')

# Anaphors, not names: `id.' means the author last cited.  They are dropped
# rather than resolved, the author being inside the <bibl> where it is wanted.
ANAPHORS = {"id.", "ib.", "ibid.", "idem", "ead.", "eadem"}


def compare_form(abbrev):
    """ABBREV reduced to what distinguishes it from another abbreviation.

    Spaces removed and case folded, so `Comp. Phil.Flam.\' and
    `Comp.Phil.Flam.\' count as one -- which they are.  The dictionaries are
    inconsistent about the space after a stop, and comparing the printed form
    made two spellings of one title look like two titles: a first attempt at
    finding collections flagged ninety-nine works, most of them a title beside
    itself with a space moved."""
    return re.sub(r"\s+", "", abbrev).lower()


def clean(raw):
    text = raw.decode("utf-8", "replace").strip()
    text = re.sub(r"\s+", " ", text)
    return text


def extract(path, corpus):
    """(authors, works), each a Counter keyed by number and abbreviation."""
    authors = collections.Counter()
    works = collections.Counter()
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
                authors[(author_num, name)] += 1
        found = TITLE.search(inner)
        if found:
            title = clean(found.group(1))
            if title:
                works[(author_num, work_num, title)] += 1
    return authors, works


# A count is the wrong filter, and printing what a threshold DROPPED is what
# showed it.  At three occurrences it discarded 319 rows of 1051, and they were
# not accidents: Euripides' plays -- `Hipp.', `Hec.', `Supp.', `Hel.', `Ba.' --
# Plutarch's Lives and Comparationes, `Sapph.', `h.Hom.', Cicero's `Fam.' and
# `Off.'.  Texts a LEXICON quotes once or twice because they are short or seldom
# bear on a word, which says nothing against the abbreviation.
#
# The accidents are recognisable by their SHAPE instead:
#
#   0474/0055 -> "Off,"      a comma where a stop belongs
#   0474/0056 -> "Fam."      a four-digit work number, and there are none
#   0474/065  -> "Horte"     the Hortensius, truncated
#   phi 0012  -> "Hom."      Homer's TLG number in the Latin corpus
#
# So: keep whatever is wellformed, whatever its count.  A work number is three
# characters, digits or a leading minus for the fragments; an abbreviation
# carries no comma.  That admits `Hipp.' and `Fam.' and excludes the malformed,
# which a frequency cannot distinguish in either direction.
WORK_NUMBER = re.compile(r"\A[0-9-]{3}\Z")


def wellformed(key, abbrev):
    """Whether this row looks like a citation rather than a slip.

    KEY is (AUTHOR) or (AUTHOR WORK).  Malformed rows are few -- four in a
    thousand -- and each is malformed in a way a count would not catch."""
    if "," in abbrev or not abbrev.strip():
        return False
    if len(key) > 1 and not WORK_NUMBER.match(key[1]):
        return False
    return True


# A work number whose citations carry SEVERAL distinct titles, each with real
# support, names a collection and not a work.  Suetonius is the case that showed
# it: `phi,1348,001' is `De Vita Caesarum', which Diogenes has as one work and
# the dictionary cites as one work -- and Lewis & Short puts the title of
# whichever LIFE is meant inside the citation.  So the number attracts twelve
# titles, `Aug.' 1681 times, `Caes.' 1143, `Tib.' 1015, and eleven twelfths of
# any single choice is wrong.
#
# Sallust the same, `Cat.' beside `Hist.'; Varro, `L. L.' beside `R. R.';
# Caelius Aurelianus, `Acut.' beside `Tard.'; Pindar's fragments beside his
# Paeans.  For those the author's abbreviation alone is right -- `Suet. 6.4' --
# and a work abbreviation is worse than none.
#
# A THIRD, because the gap is wide and unambiguous.  `Caes.' has 68 per cent of
# `Aug.'; `de Off.' has 0.2 per cent of `Off.', being the same work spelt
# longer.  Nothing observed falls between 5 and 60.
COLLECTION_SHARE = 0.25

# And a count cannot catch them all, which Varro settles.  `L. L.' has 1767
# citations and `Sat. Men.' 13 -- two different works, one at three quarters of
# a per cent of the other.  Cicero's `Off.' has 3037 and `de Off.' 7, which is
# ONE work spelt two ways at two tenths of a per cent.  Nothing numerical
# separates those, because the difference is what the titles MEAN.
#
# So the rest are named.  From Lewis & Short's own list of authors and works:
# Sallust `C./Cat.' Catilina beside `H./Hist.' Historia and `J./Jug.' Jugurtha;
# Varro `L. L.' De Lingua Latina beside `R. R.' De Re Rustica; Pindar's `Fr.'
# fragments beside his `Pae.' Paeans and `Parth.' Partheneia.  Each is a number
# Diogenes holds as one work and the dictionaries cite for several.
COLLECTIONS = {
    ("phi", "0631", "001"),             # Sallust: Catilina, Historiae, Jugurtha
    ("phi", "0684", "001"),             # Varro: De Lingua Latina, Sat. Menippeae
    ("tlg", "0033", "005"),             # Pindar: fragments, Paeans, Partheneia
}


def names_a_collection(key, found):
    """Whether these titles are several works under one number.

    FOUND is [(title, count)], commonest first.  Either a rival with real
    support, or a number known to be a collection where the counts cannot say."""
    if key in COLLECTIONS:
        return True
    if len(found) < 2:
        return False
    return found[1][1] > found[0][1] * COLLECTION_SHARE


def most_frequent(counter, key_length, dropped=None):
    """The commonest abbreviation for each key, with how often it occurred.

    Keys whose best abbreviation falls below MINIMUM are left out, and noted in
    Rows that do not look wellformed are left out, and noted in DROPPED where a
    list is given, so that what the filter cost is visible rather than
    silent."""
    best = {}
    for key, count in counter.items():
        short = key[:key_length]
        if short not in best or count > best[short][1]:
            best[short] = (key[key_length], count)
    # Every title each key attracts, so a collection can be told from a work --
    # MERGED by comparison form first, or a title beside itself with a space
    # moved looks like two titles.
    titles = {}
    for key, count in counter.items():
        short = key[:key_length]
        merged = titles.setdefault(short, {})
        form = compare_form(key[key_length])
        if form not in merged or count > merged[form][1]:
            merged[form] = (key[key_length], count)
        else:
            merged[form] = (merged[form][0], merged[form][1] + count)
    for short, merged in list(titles.items()):
        titles[short] = sorted(merged.values(), key=lambda pair: -pair[1])

    kept = {}
    for short, (abbrev, count) in best.items():
        if not wellformed(short, abbrev):
            if dropped is not None:
                dropped.append((short, abbrev, count, "malformed"))
        elif key_length == 2 and names_a_collection(short, titles.get(short, [])):
            # Works only: an AUTHOR cited under two names is Aurelius Victor
            # and Symmachus sharing a number, which is a different fault and
            # not one a majority makes worse.
            if dropped is not None:
                rivals = ", ".join("%s (%d)" % pair
                                   for pair in titles[short][:4])
                dropped.append((short, abbrev, count, "a collection: " + rivals))
        else:
            kept[short] = (abbrev, count)
    return kept


def main():
    root = None
    for candidate in (os.environ.get("DIOGENES_DATA"),
                      "/usr/local/diogenes/dependencies/data"):
        if candidate and os.path.isdir(candidate):
            root = candidate
            break
    if not root:
        sys.exit("Cannot find the Diogenes data directory; set DIOGENES_DATA.")

    tables = {}
    provenance = []
    for corpus, filename, name in DICTIONARIES:
        path = os.path.join(root, filename)
        if not os.path.exists(path):
            provenance.append(";; %s: %s NOT FOUND" % (name, filename))
            continue
        authors, works = extract(path, corpus)
        dropped = []
        best_authors = most_frequent(authors, 1, dropped)
        best_works = most_frequent(works, 2, dropped)
        tables[corpus] = (best_authors, best_works)
        provenance.append(";; %s (%s): %d authors, %d works"
                          % (name, filename, len(best_authors), len(best_works)))
        if dropped:
            malformed = len([d for d in dropped if d[3] == "malformed"])
            collections = len(dropped) - malformed
            provenance.append(";;   %d malformed and %d naming a collection, "
                              "left out" % (malformed, collections))
            for short, abbrev, count, why in sorted(dropped)[:40]:
                sys.stderr.write("  dropped %-18s %-14s %6d  %s\n"
                                 % ("/".join(short), abbrev, count, why))

    out = sys.stdout
    out.write(""";;; diogenes-abbreviations.el --- how the dictionaries cite -*- lexical-binding: t; -*-

;; GENERATED.  Do not edit by hand: run tools/extract-abbreviations.py again.
;;
;; The abbreviations LSJ and Lewis & Short use for the texts they cite, taken
;; from the dictionaries themselves.  Every citation in them carries the TLG or
;; PHI numbers beside the abbreviation, so this is Perseus's own crosswalk and
;; not a list typed out from the printed front matter -- which could not have
;; been joined to numbers in any case.
;;
%s
;;
;; Keyed by work, `CORPUS AUTHOR WORK' -> `(AUTHOR-ABBREV . WORK-ABBREV)', with
;; the author alone under `CORPUS AUTHOR'.  Homer is why the work is the key: he
;; is cited `Il.' and `Od.' and his name appears in a <bibl> twice in the whole
;; of the LSJ.

;;; Code:

(defconst diogenes-abbreviations
  (let ((table (make-hash-table :test #'equal)))
""" % "\n".join(provenance))

    rows = 0
    for corpus in ("tlg", "phi"):
        if corpus not in tables:
            continue
        best_authors, best_works = tables[corpus]
        out.write("    ;; %s\n" % corpus.upper())
        for (author_num,), (abbrev, count) in sorted(best_authors.items()):
            out.write('    (puthash (list "%s" "%s") %s table)\n'
                      % (corpus, author_num, elisp_string(abbrev)))
            rows += 1
        for (author_num, work_num), (abbrev, count) in sorted(best_works.items()):
            out.write('    (puthash (list "%s" "%s" "%s") %s table)\n'
                      % (corpus, author_num, work_num, elisp_string(abbrev)))
            rows += 1
    out.write("""    table)
  "How LSJ and Lewis & Short cite the texts of the TLG and the PHI.
A hash keyed by `(CORPUS AUTHOR)\\=' for an author and `(CORPUS AUTHOR WORK)\\=' for
a work, each giving the abbreviation as a string.")

(provide 'diogenes-abbreviations)
;;; diogenes-abbreviations.el ends here
""")
    sys.stderr.write("%d rows written\n" % rows)


def elisp_string(text):
    return '"%s"' % text.replace("\\\\", "\\\\\\\\").replace('"', '\\\\"')


if __name__ == "__main__":
    main()
