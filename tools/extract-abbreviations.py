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

BIBL = re.compile(
    rb'<bibl n="Perseus:abo:(tlg|phi),(\d{4}),([0-9-]{3,4})[^"]*">(.{0,300}?)</bibl>',
    re.S)
AUTHOR = re.compile(rb'<author>([^<]{1,40})</author>')
TITLE = re.compile(rb'<title>([^<]{1,60})</title>')

# Anaphors, not names: `id.' means the author last cited.  They are dropped
# rather than resolved, the author being inside the <bibl> where it is wanted.
ANAPHORS = {"id.", "ib.", "ibid.", "idem", "ead.", "eadem"}


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


def most_frequent(counter, key_length):
    """The commonest abbreviation for each key, with how often it occurred."""
    best = {}
    for key, count in counter.items():
        short = key[:key_length]
        if short not in best or count > best[short][1]:
            best[short] = (key[key_length], count)
    return best


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
        best_authors = most_frequent(authors, 1)
        best_works = most_frequent(works, 2)
        tables[corpus] = (best_authors, best_works)
        provenance.append(";; %s (%s): %d authors, %d works"
                          % (name, filename, len(best_authors), len(best_works)))

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
