;;; classicist-citation.el --- how a passage is named -*- lexical-binding: t; -*-

;; Copyright (C) 2024 Michael Neidhart
;; Copyright (C) 2026 Victor Gonçalves de Sousa
;;
;; Author: Victor Gonçalves de Sousa <victor.goncalves.sousa@alumni.usp.br>
;; Keywords: classics, philology

;; This program is free software; you can redistribute it and/or modify
;; it under the terms of the GNU General Public License as published by
;; the Free Software Foundation, either version 3 of the License, or
;; (at your option) any later version.

;; This program is distributed in the hope that it will be useful,
;; but WITHOUT ANY WARRANTY; without even the implied warranty of
;; MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
;; GNU General Public License for more details.

;; You should have received a copy of the GNU General Public License
;; along with this program.  If not, see <https://www.gnu.org/licenses/>.

;;; Commentary:

;; A CITATION IS NOT A BROWSER.  How a passage is named, keyed, abbreviated
;; and turned back into levels is one thing; fetching its text from Perl and
;; drawing it in a window is another.  They lived in one file, and eleven of
;; that file\='s twelve consumers wanted only the first.
;;
;; `tei-diorisis.el\=' took ten citation symbols and five browser ones,
;; `diogenes-org.el\=' seven and three, `tei-browser.el\=' six and two --
;; so two packages in another repository depended on a Perl process and a
;; stream filter in order to render `Ael. NA 1.19.5\='.  They depend on this
;; instead.
;;
;; A CITATION is a list of level strings, outermost first: ("1" "19" "5").  A
;; KEY is that flattened for a hash table or a filename.  A REFERENCE is the
;; whole of it -- corpus, author, work, citation -- and what a reader sees.
;;
;; WHAT IS NOT HERE.  `diogenes-open-passage\=', which opens a passage in the
;; browser and so belongs to the browser.  Anything wanting it should ask
;; `fboundp\=' first: citations without a browser is a coherent state, and the
;; guard `tei-diorisis.el\=' already has stops being defensive.
;;
;; NOT QUITE PERL-FREE, and the exception is worth knowing.
;; `diogenes--browser-labels\=' falls back to asking Perl for a work\='s levels
;; when the buffer-local is unset.  `tei-browser.el\=' and `tei-diorisis.el\='
;; set that local themselves and never take the fallback.

;;; Code:
(require 'cl-lib)
(require 'seq)
(require 'subr-x)
(require 'text-property-search)   ; prop-match-value, and the searches

;; CALLED AT RUN TIME, from files that require this one or are required by it.
;; Declared rather than required: `diogenes-browser.el\=' requires this file,
;; and `diogenes.el\=' requires that, so requiring either from here closes a
;; circle.  `diogenes-abbreviations\=' is a table and could be required
;; honestly; it is declared with the rest for the sake of one rule.
(declare-function diogenes--get-work-labels "diogenes-perl-interface"
                  (options work))
(declare-function diogenes--select-passage "diogenes-user-interface"
                  (options author work))
(declare-function diogenes-browse-tlg "diogenes" ())
(defvar diogenes-abbreviations)

;; STAYED IN THE BROWSER, because it opens a passage there, and opening one is
;; browser work.  This file is required BY the browser, so it cannot require it
;; back; anything outside should ask `fboundp' first, citations without a
;; browser being a state one can now be in.
(declare-function diogenes-open-passage "diogenes-browser"
                  (corpus author work &optional passage))

(defun classicist--browser-format-citation (citation)
  (propertize (format "%-14s"
		      (mapconcat (lambda (x) (format "%s" x))
				 citation
				 "."))
	      'diogenes-citation t
	      'face 'font-lock-comment-face
	      'font-lock-face 'font-lock-comment-face
	      'rear-nonsticky t))

(defvar-local classicist--browser-corpus nil
  "The corpus this browser buffer is reading -- `tlg\=', `phi\=', and the rest.
Recorded so that the buffer can say what it is showing.  It could not: a
browser buffer knew its LANGUAGE and nothing else, so nothing outside it could
name the passage on the screen -- not a link to it, not a citation, not a
message.  Set where the buffer is made, that being the one place every route in
passes through.")

(defvar-local classicist--browser-author nil
  "The author number this browser buffer is reading; see
`classicist--browser-corpus\='.")

(defvar-local classicist--browser-work nil
  "The work number this browser buffer is reading; see
`classicist--browser-corpus\='.")

(defvar-local classicist--browser-labels nil
  "What the levels of this work's citations are called, outermost first.
`(\"book\" \"verse\")\=', `(\"Bekker page\" \"line\")\=', `(\"Stephanus page\"
\"section\" \"line\")\=' -- Diogenes's own data says, per work, and a citation
is a
list in exactly that order.

Recorded once when the buffer is made rather than asked for each time it is
wanted: `diogenes--get-work-labels\=' is a call into Perl, which is cheap once
and
not cheap per reference.

This is what makes a citation renderable.  `(1053a 15)\=' is conventionally
written `1053a15\=' and `(4 208)\=' is written `4.208\=', and the difference is
not
the author but the LEVEL: a page and a line run together, numbered levels take a
stop between them.  Without the labels there is no way to tell which is which,
and rendering would have to know a convention per author -- an open set, where
the levels are a handful.")

(defvar-local classicist--browser-passage nil
  "The passage this browser buffer was opened at, if one was given.
Where the reader answered `no\=' to `Specify passage?\=' this is nil and the
buffer began at the start of the work.  It is where it BEGAN, not where it now
is: paging moves the buffer and does not update this, the position being the
Perl process's to know.")

(defcustom classicist-citation-run-on-labels
  '("page" "pg" "column" "folio")
  "Levels that run into the level after them, with no stop between.
Aristotle is cited `1053a15\=' and Plato `246a4\=', the page and what follows
written as one; a book and a verse are cited `4.208\=', with a stop.  The
difference is the LEVEL and not the author, which is why this is a list of
labels: Diogenes names the levels of every work -- `(\"book\" \"verse\")\=',
`(\"Stephanus page\" \"section\" \"line\")\=' -- so one rule per label covers
every
author who uses it.

`pg\=' is there because the corpora abbreviate: the scan finds `pg\=' 341 times
beside `page\=' 1785, and `ln\=', `vol\=', `sect\=' and `chap\=' likewise
beside their
full forms.  Only the paginated ones need listing, the rest taking stops anyway.

Matched as SUBSTRINGS of a label, so `page\=' covers `Stephanus page\=',
`Bekker page\=', `Jebb page\=' and the twenty-odd other editors' pages the two
corpora use -- including any this list has never heard of, which a list of whole
labels could not do.

This affects DISPLAY only.  What a link records is
`classicist-citation-to-key\=', which puts a stop between every level whatever
their labels, because that is reversible and a run-on citation is not:
`1053a15\='
cannot be split back into a page and a line without already knowing which is
which.  So a pattern missing from this list costs a reader `1053a.15\=' where
they
would write `1053a15\=', and costs nothing that has to work."
  :type '(repeat string)
  :group 'diogenes)

(defun classicist--citation-runs-on-p (label)
  "Whether LABEL runs into the level after it, with no stop between.
Matched as SUBSTRINGS, case-insensitively, and both parts of that were learnt
from the data rather than guessed.

Substrings, because every editor's page is its own level.  A pass over all 2194
authors of the TLG and the PHI turns up `page\=' itself 1785 times and then
`Stephanus page\=', `Bekker page\=', `Jebb page\=', `Harduin page\=', `Morel
page\=',
`Olearius page\=', `Aubert page\=', `Thevenot page\=', `Wescher page\=',
`Spengel
page\=', `Dietz page\=', `Usener page\=', `Dindorf page\=', `Kallierges page\=',
`Hermann page\=', `Klein page\=', `Walz page\=', `MPG page\=', `codex page\=',
`Dindorf-Stephanus page\=', `page+column\=', `Bekker page+line\=' -- and there
will
be editors neither of us has met.  A LIST of labels would have to name each; the
pattern `page\=' catches them all.

Case-insensitively, because the corpora do not agree: the TLG capitalises --
`Book\=', `Line\=', `Fragment\=', `Ode\=' -- and the PHI does not.  And trimmed,
because at least one work carries a label with a leading space."
  (when label
    (let ((clean (string-trim (downcase label))))
      (and (cl-some (lambda (pattern)
                      (string-match-p (regexp-quote (downcase pattern)) clean))
                    classicist-citation-run-on-labels)
           t))))

(defun classicist-citation-to-string (citation &optional labels)
  "CITATION written as a reader would write it.
LABELS names its levels, outermost first, as `classicist--browser-labels\='
holds
them; without them every level takes a stop, which is right for most and wrong
for the pages.

    (4 208)      with (\"book\" \"verse\")                  -> 4.208
    (1053a 15)   with (\"Bekker page\" \"line\")             -> 1053a15
    (246a 4 2)   with (\"Stephanus page\" \"section\" \"line\") -> 246a4.2
    (25)         with (\"verse\")                          -> 25

The elements may be numbers or symbols -- `1053a\=' is a symbol -- so each is
printed rather than formatted as a number."
  (let ((parts nil))
    (cl-loop for element in citation
             for index from 0
             for label = (nth index labels)
             do (push (format "%s" element) parts)
             ;; A stop BEFORE the next element, unless this level runs on.
             when (and (nth (1+ index) citation)
                       (not (classicist--citation-runs-on-p label)))
             do (push "." parts))
    (apply #'concat (nreverse parts))))

(defun classicist-citation-to-key (citation)
  "CITATION as a string that can be turned back into CITATION.
A stop between every level, whatever the levels are called:

    (1053a 15)     -> \"1053a.15\"
    (10 20 2 1)    -> \"10.20.2.1\"
    (25)           -> \"25\"

REVERSIBLE, which is the whole point and the reason it ignores the conventions
that `classicist-citation-to-string\=' honours.  `1053a15\=' is how a reader
writes
Aristotle and cannot be read back: nothing in the string says where the page
ends and the line begins, and knowing would mean knowing the work\='s levels
before parsing the citation that identifies the work.  `1053a.15\=' says.

So: this for anything that must be read again -- a link, a stored reference, an
argument to a command -- and the other for anything a person reads."
  (mapconcat (lambda (element) (format "%s" element)) citation "."))

(defun classicist-citation-from-key (key)
  "KEY, as `classicist-citation-to-key\=' wrote it, back to a citation.
The elements come back as strings.  Diogenes gives some as numbers and some as
symbols -- `1053a\=' is a symbol -- and it takes strings where it takes a
passage
at all, `diogenes--select-passage\=' collecting them with `read-string\='; so
strings are what a caller wants and no attempt is made to guess which were
numbers."
  (and key (split-string key "\\." t)))

(defun classicist-citation-interval-from-key (key)
  "KEY back to (FROM . TO), TO nil where KEY names a single citation.
The inverse of what `classicist-browser-reference\=' puts in `:key\='.

Split on the HYPHEN first and each half on stops after: splitting the whole of
`2.2-2.5\=' on stops gave `(\"2\" \"2-2\" \"5\")\=', the hyphen swallowed into
an
element and the passage unopenable.  `classicist-citation-from-key\=' reads one
citation and was handed two, which is the sort of fault that shows only when
something tries to read back what was written -- and a link that cannot be read
back is a dead link."
  (when key
    (let* ((halves (split-string key "-" t))
           (from (classicist-citation-from-key (car halves)))
           (to (and (cdr halves)
                    (classicist-citation-from-key (cadr halves)))))
      (cons from to))))

(defun classicist-open-reference (reference)
  "Open the passage REFERENCE names.
REFERENCE is what `classicist-browser-reference\=' returns, or the same plist
read
back from wherever it was stored -- a link, a note.  `:key\=' is used in
preference to `:from\=', being the form that survives writing down."
  (let* ((key (plist-get reference :key))
         (interval (and key (classicist-citation-interval-from-key key)))
         (from (or (car interval)
                   (mapcar (lambda (element) (format "%s" element))
                           (plist-get reference :from)))))
    (diogenes-open-passage (plist-get reference :corpus)
                           (plist-get reference :author)
                           (plist-get reference :work)
                           from)))

(defun classicist-browser-citation-at (&optional position)
  "The citation of the line at POSITION, or at point.
Nil where there is none -- a header line, a blank, the space between passages.
Searches BACKWARD from there if the line itself has none, a citation belonging
to the lines that follow it rather than sitting on every one."
  (save-excursion
    (when position (goto-char position))
    (or (get-text-property (point) 'cit)
        (let ((match (text-property-search-backward 'cit)))
          (and match (prop-match-value match))))))

(defun classicist-browser-citation-interval ()
  "The citations bounding the region, or the one at point.
Returns (START . END), with END nil where there is no region: a reader
referring to a single line wants that line, and one who has marked a passage
wants its extent.

This is what the buffer can say about WHERE IT IS.  It keeps no record of that
-- paging is the Perl process\='s business and the buffer is told only what to
display -- but every line carries its citation as a text property, so the
position is readable from the text even though it is not remembered."
  (if (use-region-p)
      (let ((start (classicist-browser-citation-at (region-beginning)))
            (end (classicist-browser-citation-at (max (region-beginning)
                                                    (1- (region-end))))))
        ;; NOT A RANGE WHERE BOTH ENDS ARE THE SAME LINE.  A region marked
        ;; within one line, or across a wrapped one, gave END equal to START
        ;; and everything downstream then wrote it out twice:
        ;; `Arist. Metaph. 1048a27-1048a27', which says no more than
        ;; `1048a27' and says it worse.
        (cons start (unless (equal start end) end)))
    (cons (classicist-browser-citation-at) nil)))

(defcustom classicist-abbreviation-overrides nil
  "Abbreviations to use instead of the generated table\='s.
An alist keyed as the table is -- `((\"tlg\" \"0086\") . \"Aristot.\")\=' for an
author, `((\"tlg\" \"0086\" \"025\") . \"Met.\")\=' for a work -- and consulted
first,
so an entry here wins.

Two uses.  A reader who prefers another convention to LSJ\='s: `Aristot.\=' for
`Arist.\=', or an English title where the dictionaries give a Latin one.

And the handful of rows the extraction gets wrong, which are wrong in ways no
rule catches.  `phi 0012\=' is Homer, whose number that is in the TLG and not
the
PHI, from a mistagged citation in Lewis & Short -- harmless, there being no such
author to browse.  `phi 0474/065\=' reads `Horte\=', the Hortensius truncated in
the source.  Four such rows in a thousand when this was written, and each is
one line to correct here rather than a reason to distrust the rest."
  :type '(alist :key-type (repeat string) :value-type string)
  :group 'diogenes)

(defun classicist-citation-abbreviation (corpus author &optional work)
  "How the dictionaries cite this author, or this work of theirs.
Returns (AUTHOR-ABBREV . WORK-ABBREV), either of which may be nil.

`Arist.\=' and `Metaph.\=', `Hom.\=' and `Il.\=', `Verg.\=' and `A.\=' -- the
forms LSJ
and Lewis & Short use, taken from the dictionaries themselves rather than from
their printed front matter, which names no numbers.  See
`tools/extract-abbreviations.py\='.

Nil for a text neither dictionary cites, which is most of the two corpora: the
table covers some five hundred works of the TLG and two hundred and seventy of
the PHI, being the texts the lexicographers had occasion to quote."
  (let ((look (lambda (key)
                (or (cdr (assoc key classicist-abbreviation-overrides))
                    (and (boundp 'diogenes-abbreviations)
                         (gethash key diogenes-abbreviations))))))
    (cons (funcall look (list corpus author))
          (and work (funcall look (list corpus author work))))))

(defun classicist-reference-to-string (reference)
  "REFERENCE written as a scholar would write it.
`Arist. Metaph. 1053a15\=', `Hom. Il. 9.1\=', `Verg. A. 4.208\='.

Falls back by degrees, each step giving up something and none failing outright:
the work\='s abbreviation where the dictionaries have one, the author\='s alone
where they name him but not it, and the numbers where they name neither.  A
reader who cites a text no lexicographer quoted gets `tlg 2632/001 3.4\=', which
is at least unambiguous."
  (let* ((corpus (plist-get reference :corpus))
         (author (plist-get reference :author))
         (work (plist-get reference :work))
         (text (plist-get reference :text))
         (pair (classicist-citation-abbreviation corpus author work))
         (author-abbrev (car pair))
         (work-abbrev (cdr pair)))
    (string-join
     (delq nil
           (list (cond ((and author-abbrev work-abbrev)
                        (concat author-abbrev " " work-abbrev))
                       (author-abbrev)
                       (t (format "%s %s/%s" corpus author work)))
                 text))
     " ")))

(defun classicist-browser-reference ()
  "Everything needed to name, and to reopen, the passage in this buffer.
A plist: `:corpus\=', `:author\=', `:work\=', `:from\=' and `:to\=' -- the last
two
being citations, and `:to\=' nil unless a region is marked.

The corpus, author and work are what `diogenes-browse-tlg\=' and its siblings
take, so a reference is enough to open the work again; `:from\=' says where in
it.
Nil in a buffer that is not a browser, there being nothing to refer to."
  (when (derived-mode-p 'diogenes-browser-mode)
    (let* ((interval (classicist-browser-citation-interval))
           (from (car interval))
           (to (cdr interval))
           (labels classicist--browser-labels))
      (list :corpus classicist--browser-corpus
            :author classicist--browser-author
            :work classicist--browser-work
            :labels labels
            :from from
            :to to
            ;; TWO renderings, for two jobs.  `:text' is for a reader and
            ;; follows the conventions: `1053a15'.  `:key' is for anything that
            ;; must read it back and puts a stop between every level:
            ;; `1053a.15'.  Neither can do the other's work -- the conventional
            ;; form is not reversible, and the reversible form is not what
            ;; anyone writes in a note.
            :text (when from
                    (concat (classicist-citation-to-string from labels)
                            (when to
                              (concat "-" (classicist-citation-to-string
                                           to labels)))))
            :key (when from
                   (concat (classicist-citation-to-key from)
                           (when to
                             (concat "-" (classicist-citation-to-key to)))))))))

(provide 'classicist-citation)

;;; classicist-citation.el ends here
