;;; diogenes-bailly.el --- Open Bailly's Dictionnaire grec-français PDF -*- lexical-binding: t -*-

;;; Commentary:

;; Jump from a Diogenes *Greek* dictionary entry (the buffer produced by
;; `diogenes-lookup-mode') to the page of Anatole Bailly's
;; _Dictionnaire grec-français_ -- in the freely available re-typeset
;; edition "Le Bailly 2020 - Hugo Chávez" (Gérard Gréco et al.) -- shown
;; inside Emacs with `pdf-tools' (or `doc-view').  It is a Greek
;; counterpart of `diogenes-montanari.el' / `diogenes-cambridge.el' and
;; reuses `diogenes-old.el''s PDF display driver.
;;
;; ---------------------------------------------------------------------
;; THE RUNNING HEADS, NOT THE BOOKMARKS
;; ---------------------------------------------------------------------
;;
;; The Bailly 2020 PDF *is* bookmarked -- some 2 170 lemmas, roughly one
;; per page -- but a bookmark names a word that occurs SOMEWHERE on its
;; page, not the page's first or last entry, so the bookmarks alone give
;; no page boundaries (the CGL and Montanari modules can key on their
;; bookmarks precisely because those do give bounds).
;;
;; What this edition has instead is a machine-clean text layer -- it is
;; typeset, not scanned -- and a running head on every entry page in the
;; familiar three-part form
;;
;;     ἀγελαδόν                     90                     ἀγέροχος
;;     first lemma on the page   page no.   last lemma on the page
;;
;; Each entry page thus announces its own interval, and the intervals of
;; consecutive pages tile the whole word list with no gaps and no
;; overlaps.  That is a sorted array, and finding a word in it is a
;; binary search.
;;
;; ---------------------------------------------------------------------
;; TWO WAYS TO GET THE HEADS: LAZY PROBING, OR A PREBUILT .eld INDEX
;; ---------------------------------------------------------------------
;;
;; Out of the box nothing is built.  A lookup reads ONE head per probe --
;; only the top strip of the page, via `pdf-info-gettext' or `pdftotext'
;; -- and caches it: a cold lookup costs 11-13 page probes, and since
;; every probe warms the cache, later lookups in the same session
;; usually cost one or two, often none.
;;
;; \\[diogenes-bailly-build-index] reads every head in one pass (a few
;; seconds with poppler's `pdftotext') and writes a portable prebuilt
;; index -- `<pdf-name>-index.eld' beside the PDF, in the same spirit as
;; Passow's `passow-index.eld' -- after which even the first lookup of a
;; session, on any machine the file is copied to, needs no probing at
;; all.  Building it is an optimisation, never a requirement: both paths
;; fill the same table and give the same pages.
;;
;; Because the page is *found* by probing, nothing depends on the printed
;; page number matching the PDF page number (in this edition they do
;; match, on all 2 470 numbered heads); the number in a head serves only
;; as the anchor that separates its two lemmas.
;;
;; A head counts as read only when both sides of its page number hold
;; Greek lemmas in alphabetical order.  That is what keeps the front
;; matter -- prefaces, the list of authors, where a page number sits amid
;; prose -- out of the index, and what discards a page whose text came
;; back with body matter attached instead of just the head.
;;
;; The 24 pages that open a letter print a large "Α, α" instead of a
;; running head.  They need no special data: a page with no parsable head
;; is simply not a probe point, and a word sorting before the following
;; page's first lemma is placed on it.
;;
;; ---------------------------------------------------------------------
;; COLLATION
;; ---------------------------------------------------------------------
;;
;; `diogenes-bailly--key' reproduces Bailly's own macro-alphabetical
;; order: accents, breathings, diaereses, iota subscript, quantity marks,
;; case, the compound interpunct "·", the "*" conjecture mark, homograph
;; numerals ("1 ἄν", "2 ἄν") and the contracted half of a verb lemma
;; ("τελέω-ῶ") are all ignored.  This module does NOT borrow
;; `diogenes-montanari--greek-key', because Bailly prints medial beta as
;; "ϐ" (U+03D0), which that key -- keeping only U+03B1..U+03C9 -- would
;; silently DROP, turning ἀ·ϐαρής into αρης.  Here ϐ folds to β (and ς to
;; σ, ϑ to θ, ϕ to φ, ϰ to κ, ϱ to ρ, ϖ to π).
;;
;; Two finer points, both required by the printed order:
;;
;;   * an apostrophe of crasis or elision closes the gap around it, so
;;     "τῷ ’χλῳ" keys as τωχλω and follows τῶν, where Bailly puts it;
;;   * a real word space does not close up, and sorts before any letter,
;;     so "Διὸς ἱερόν" precedes "διόσ·δοτος".
;;
;; A second, accent-KEEPING key (`diogenes-bailly--tight-key') breaks
;; ties: where consecutive pages share one accent-insensitive key (the
;; ποιός/ποῖος and τίς/τις/τὶς clusters), the page whose own first lemma
;; is spelt like the word wins.
;;
;; ---------------------------------------------------------------------
;; ACCURACY
;; ---------------------------------------------------------------------
;;
;; Checked against the PDF's own 2 170 lemma bookmarks -- an independent
;; witness, since a bookmark sits mid-page while the search knows only
;; page edges: 2 169 land on exactly the bookmarked page.  The one miss is
;; a numbered homograph ("2 ἄρῃ") whose twin "1 ἄρῃ" ends the preceding
;; page: identical spelling, so no collation key could separate them, and
;; the reader arrives one page early with both in view.  Unlike the
;; scanned dictionaries, there is no OCR noise here to allow for.
;;
;; Poppler's `pdftotext' is preferred for reading a page, because its
;; `-layout' output puts the running head on the first line; pdf-tools'
;; `pdf-info-gettext' is the fallback, and on some versions returns more
;; of the page than the strip asked for, in which case heads are refused
;; rather than guessed at.  Set `diogenes-bailly-text-method' to override.
;;
;; Setup:
;;
;;   (setq diogenes-bailly-pdf-file "/path/to/bailly-2020-hugo-chavez.pdf")
;;
;; Then, in a Greek lookup buffer, press `B' or click the "[Bailly]" link;
;; optionally run \\[diogenes-bailly-build-index] once.

;;; Code:
(require 'cl-lib)
(require 'seq)
(require 'subr-x)
(require 'ucs-normalize)
(require 'diogenes-old)                 ; reuse the PDF display driver

(declare-function pdf-info-gettext "pdf-info"
                  (page edges &optional selection-style file-or-buffer))
(declare-function pdf-info-outline "pdf-info" (&optional file-or-buffer))
(declare-function pdf-info-number-of-pages "pdf-info" (&optional file-or-buffer))
(declare-function diogenes--perseus-beta-to-utf8 "diogenes-utils" (str))

;;;; --------------------------------------------------------------------
;;;; CUSTOMIZATION
;;;; --------------------------------------------------------------------

(defcustom diogenes-bailly-pdf-file nil
  "Path to a PDF of Bailly's Dictionnaire grec-français.
Written for the re-typeset \"Bailly 2020 - Hugo Chávez\" edition, whose
entry pages carry a running head of the form

  ἀγελαδόν            90            ἀγέροχος

\(first lemma, page number, last lemma).  Any edition with such heads
and a real text layer will do; a scan without a text layer will not,
since the heads are read from the page text."
  :type '(choice (const :tag "Not set" nil) file)
  :group 'diogenes)

(defcustom diogenes-bailly-page-offset 0
  "Integer added to every page number this module returns.
Leave at 0: the page is located by reading the PDF's own pages, so it
is already a physical PDF page index.  See `diogenes-old-page-offset'."
  :type 'integer
  :group 'diogenes)

(defcustom diogenes-bailly-text-method 'auto
  "How to read the text of a single PDF page.
`auto' prefers poppler's `pdftotext' and falls back to
`pdf-info-gettext' (pdf-tools, no external process).  Force either with
`pdftotext' or `pdf-tools'.

`pdftotext' comes first deliberately.  Its `-layout' output puts a
page's running head on the first line, exactly as printed, which is what
the head parser wants; `pdf-info-gettext' asks for the top strip of the
page but, depending on the pdf-tools version, may return a good deal
more, in which case the head cannot be told from the body text following
it and the page is skipped.  \\[diogenes-bailly-build-index] is also far
faster with `pdftotext', which reads the whole dictionary in one run."
  :type '(choice (const :tag "Prefer pdftotext, else pdf-tools" auto)
                 (const :tag "The pdftotext program" pdftotext)
                 (const :tag "pdf-tools (pdf-info-gettext)" pdf-tools))
  :group 'diogenes)

(defcustom diogenes-bailly-pdftotext-program "pdftotext"
  "Name of (or path to) poppler's `pdftotext' program."
  :type 'string
  :group 'diogenes)

(defcustom diogenes-bailly-head-strip 0.06
  "Fraction of the page height, from the top, that holds the running head.
Only this strip is read when `pdf-info-gettext' is used.  Enlarge it if
heads are missed; too large a value merely pulls in the first line of
the body, which the head parser ignores."
  :type 'number
  :group 'diogenes)

(defcustom diogenes-bailly-number-tolerance 30
  "How far the number in a running head may differ from its PDF page.
The head's central number is the anchor separating its two lemmas, so a
candidate number is accepted only within this many pages of the page it
was read from.  That rejects the numeral of a homograph lemma (a head
can read \"1 ἄν  212  2 ἄν\") and any number in ordinary body text.  Raise
it for a copy with much unnumbered front matter, where printed and
physical numbering drift apart."
  :type 'integer
  :group 'diogenes)

(defcustom diogenes-bailly-body-range nil
  "First and last PDF page of the dictionary proper, as a cons (FIRST . LAST).
Nil means detect it: FIRST from the outline's \"lettre …\" bookmarks (or,
without them, by scanning for the first page with a running head), LAST
by probing for the last page that has one.  Set it explicitly to skip
the detection, e.g. (81 . 2574) for the Bailly 2020 PDF."
  :type '(choice (const :tag "Detect automatically" nil)
                 (cons integer integer))
  :group 'diogenes)

(defcustom diogenes-bailly-index-file nil
  "Where \\[diogenes-bailly-build-index] writes the portable index.
Nil means `<pdf-name>-index.eld' in the PDF's own directory -- the
counterpart of Passow's `passow-index.eld', and the natural place, since
the index belongs to that one PDF.  Set a path of your own if the PDF
lives somewhere unwritable."
  :type '(choice (const :tag "Beside the PDF" nil) file)
  :group 'diogenes)

(defcustom diogenes-bailly-cache-directory
  (expand-file-name "diogenes-bailly" user-emacs-directory)
  "Directory for the fallback on-disk cache of the running heads.
Used by \\[diogenes-bailly-build-index] when the portable index cannot
be written beside the PDF (a read-only folder, say).  Keyed by the PDF's
modification time, so replacing the PDF invalidates it.  Set to nil to
disable on-disk caching entirely; the in-memory cache still applies
within a session."
  :type '(choice (const :tag "Disable disk cache" nil) directory)
  :group 'diogenes)

;;;; --------------------------------------------------------------------
;;;; COLLATION KEYS
;;;; --------------------------------------------------------------------

(defconst diogenes-bailly--letter-folds
  '((?ϐ . ?β)                          ; U+03D0 medial beta -- Bailly's default
    (?ς . ?σ) (?ϑ . ?θ) (?ϕ . ?φ) (?ϰ . ?κ) (?ϱ . ?ρ) (?ϖ . ?π)
    (?ϴ . ?θ) (?ϒ . ?υ))
  "Alist folding Greek variant letter shapes onto their plain letter.")

(defsubst diogenes-bailly--greek-letter-p (c)
  "Non-nil if character C is a plain Greek letter, upper or lower case."
  (or (<= #x0391 c #x03a9) (<= #x03b1 c #x03c9)))

(defun diogenes-bailly--prepare (word)
  "Normalise WORD for keying and return its NFD decomposition.
Converts Perseus beta code (LSJ headwords arrive as e.g. \"le/gw\") to
Unicode, closes up an apostrophe of crasis or elision together with any
space before it, and drops the contracted tail of a lemma such as
\"τελέω-ῶ\"."
  (save-match-data
    (let* ((word (or word ""))
           (word (if (and (fboundp 'diogenes--perseus-beta-to-utf8)
                          (string-match-p "[A-Za-z]" word))
                     (or (diogenes--perseus-beta-to-utf8 word) word)
                   word))
           ;; "τῷ ’χλῳ" -> "τῷχλῳ": the apostrophe and the space before it go.
           (word (replace-regexp-in-string "[[:space:]]*['’ʼ´`]" "" word))
           ;; "τελέω-ῶ" -> "τελέω"; a lemma that is only a hyphenated
           ;; prefix ("ἀ-") keeps its letters.
           (word (let ((cut (car (split-string word "-"))))
                   (if (string-empty-p cut)
                       (replace-regexp-in-string "-" "" word)
                     cut))))
      (ucs-normalize-NFD-string word))))

(defun diogenes-bailly--key (word)
  "Return Bailly's macro-alphabetical collation key for WORD.
Keeps the bare Greek letters and word spaces only: accents, breathings,
diaereses, iota subscript, quantity marks, case, \"·\", \"*\",
parentheses, commas and homograph numerals all drop out, and variant
letter shapes fold (notably ϐ to β; see
`diogenes-bailly--letter-folds').  A word space survives and sorts
before every letter, so a two-word lemma is ordered as Bailly orders it.
Plain lowercase Greek letters are in alphabetical order in Unicode, so
keys compare with `string<'."
  (let ((chars nil))
    (dolist (c (string-to-list (diogenes-bailly--prepare word)))
      (unless (<= #x0300 c #x036f)     ; combining marks
        (let* ((c (downcase c))
               (c (or (cdr (assq c diogenes-bailly--letter-folds)) c)))
          (cond ((diogenes-bailly--greek-letter-p c) (push c chars))
                ((memq c '(?\s ?\t)) (push ?\s chars))))))
    (string-trim
     (replace-regexp-in-string "  +" " " (apply #'string (nreverse chars))))))

(defun diogenes-bailly--tight-key (word)
  "Return an accent-KEEPING key for WORD, used only to break ties.
Like `diogenes-bailly--key' but retaining the combining marks, so ποιός,
ποῖος and ποιὸς stay distinct while case, \"·\" and the rest are still
ignored.  Compared with `string=' only, never ordered."
  (let ((chars nil))
    (dolist (c (string-to-list (diogenes-bailly--prepare word)))
      (if (<= #x0300 c #x036f)
          (push c chars)
        (let* ((c (downcase c))
               (c (or (cdr (assq c diogenes-bailly--letter-folds)) c)))
          (when (diogenes-bailly--greek-letter-p c) (push c chars)))))
    (ucs-normalize-NFD-string (apply #'string (nreverse chars)))))

;;;; --------------------------------------------------------------------
;;;; READING ONE PAGE'S RUNNING HEAD
;;;; --------------------------------------------------------------------

(defun diogenes-bailly--pdftotext-p ()
  "Non-nil if poppler's `pdftotext' is available."
  (and (executable-find diogenes-bailly-pdftotext-program) t))

(defun diogenes-bailly--pdf-tools-p ()
  "Non-nil if `pdf-info-gettext' can be used."
  (and (or (fboundp 'pdf-info-gettext) (require 'pdf-info nil t))
       (fboundp 'pdf-info-gettext)))

(defun diogenes-bailly--page-text (file page &optional whole-page)
  "Return the text of PAGE of FILE, or nil.
By default only the top strip is read (`diogenes-bailly-head-strip'),
which is where the running head is; with WHOLE-PAGE non-nil the whole
page is read.  Uses `pdf-info-gettext' or `pdftotext' according to
`diogenes-bailly-text-method'.  Returns nil for a page that does not
exist or cannot be read."
  (let ((method diogenes-bailly-text-method))
    (cond
     ((and (memq method '(auto pdftotext)) (diogenes-bailly--pdftotext-p))
      (with-temp-buffer
        (when (zerop (call-process diogenes-bailly-pdftotext-program nil t nil
                                   "-layout"
                                   "-f" (number-to-string page)
                                   "-l" (number-to-string page)
                                   file "-"))
          (buffer-string))))
     ((and (memq method '(auto pdf-tools)) (diogenes-bailly--pdf-tools-p))
      (ignore-errors
        (pdf-info-gettext page
                          (list 0 0 1 (if whole-page 1 diogenes-bailly-head-strip))
                          'line file)))
     ((eq method 'pdf-tools)
      (user-error "pdf-tools is not installed, but `diogenes-bailly-text-method' \
is set to `pdf-tools'"))
     ((eq method 'pdftotext)
      (user-error "Cannot find %s; install poppler-utils or set \
`diogenes-bailly-text-method'" diogenes-bailly-pdftotext-program))
     (t
      (user-error "Bailly needs either pdf-tools or poppler's %s to read the \
running heads" diogenes-bailly-pdftotext-program)))))

(defun diogenes-bailly--lemma-token-p (token)
  "Non-nil if TOKEN can be part of a lemma, i.e. it holds Greek letters.
Tested through `diogenes-bailly--key', so a precomposed polytonic form
\(ὁ, ᾧ) and the variant shapes (ϐ) count, and a French or Latin word
does not."
  (not (string-empty-p (diogenes-bailly--key token))))

(defsubst diogenes-bailly--homograph-numeral-p (token)
  "Non-nil if TOKEN is the small numeral that distinguishes homographs."
  (string-match-p "\\`[1-9]\\'" token))

(defun diogenes-bailly--lemma-before (tokens)
  "Return the lemma that TOKENS end with, or an empty string.
Walks back from the end while the tokens are lemma-like, so a
two-word lemma (\"Διὸς ἱερόν\") and a numbered homograph (\"1 ἄν\") come
back whole, while anything before them is left alone."
  (let ((out nil))
    (cl-loop for token in (reverse tokens)
             while (or (diogenes-bailly--lemma-token-p token)
                       (and out (diogenes-bailly--homograph-numeral-p token)))
             do (push token out))
    (if (cl-some #'diogenes-bailly--lemma-token-p out)
        (mapconcat #'identity out " ")
      "")))

(defun diogenes-bailly--lemma-after (tokens)
  "Return the lemma that TOKENS begin with, or an empty string.
The mirror image of `diogenes-bailly--lemma-before'."
  (let ((out nil))
    (cl-loop for token in tokens
             while (or (diogenes-bailly--lemma-token-p token)
                       (and (null out)
                            (diogenes-bailly--homograph-numeral-p token)))
             do (setq out (append out (list token))))
    (if (cl-some #'diogenes-bailly--lemma-token-p out)
        (mapconcat #'identity out " ")
      "")))

(defun diogenes-bailly--split-at-number (line page)
  "Split LINE at its page-number token; return (FIRST . LAST) or nil.
An entry page's head is \"<first lemma> <number> <last lemma>\", so the
number is the anchor.  Integer tokens within
`diogenes-bailly-number-tolerance' of PAGE are tried nearest first, and
a split is accepted only when all three of these hold:

  * the tokens immediately LEFT of the number end in a lemma, and
  * the tokens immediately RIGHT of it begin with one -- both judged by
    the presence of Greek letters, so French definition text abutting
    the number is refused; and
  * the two lemmas are in alphabetical order.

Those conditions are what keep a page out of the index unless its head
really was read.  They matter because the page text is not always just
the head: `pdf-info-gettext' may hand back more of the page than the
strip asked for, in which case the \"last lemma\" would otherwise be
swallowed body text (\"κίρνημι 1329 lequel on mélange…\"), and a bogus
interval like that misdirects the binary search across the whole
dictionary.  They also stop the front matter -- prefaces and the list
of authors, where a page number sits amid ordinary prose -- from
looking like dictionary pages."
  (let* ((tokens (split-string line nil t))
         (candidates
          (sort (cl-loop for token in tokens
                         for i from 0
                         for n = (and (string-match-p "\\`[0-9]+\\'" token)
                                      (string-to-number token))
                         when (and n (<= (abs (- n page))
                                         diogenes-bailly-number-tolerance))
                         collect (cons (abs (- n page)) i))
                (lambda (a b) (< (car a) (car b))))))
    (cl-loop for candidate in candidates
             for i = (cdr candidate)
             for first = (diogenes-bailly--lemma-before (seq-take tokens i))
             for last = (diogenes-bailly--lemma-after (seq-drop tokens (1+ i)))
             for key-first = (diogenes-bailly--key first)
             for key-last = (diogenes-bailly--key last)
             when (and (not (string-empty-p key-first))
                       (not (string-empty-p key-last))
                       (not (string< key-last key-first)))
             return (cons first last))))

(defun diogenes-bailly--parse-head (text page)
  "Parse the running head out of TEXT, the top of PAGE.
Returns (FIRST-LEMMA . LAST-LEMMA) as strings, or nil when PAGE has no
running head -- the case for the pages that open a letter (they print a
large \"Α, α\" instead), for front and back matter, and for blank pages.

Copes with both shapes the extractors produce: all three fields on one
line (`pdftotext -layout'), and each on a line of its own."
  (when (and text (not (string-empty-p text)))
    (let ((lines (seq-remove (lambda (l) (string-match-p "\\`[[:space:]]*\\'" l))
                             (split-string text "\n"))))
      (when lines
        (or (diogenes-bailly--split-at-number (car lines) page)
            (diogenes-bailly--split-at-number
             (mapconcat #'identity (seq-take lines 3) " ") page))))))

;;;; --------------------------------------------------------------------
;;;; THE HEAD TABLE: MEMORY, PREBUILT INDEX, DISK CACHE, LAZY PROBES
;;;; --------------------------------------------------------------------

;; One data structure serves both routes.  A state plist
;;
;;     (:heads HASH :min PAGE :max PAGE)
;;
;; maps a page to (FIRST . LAST) or to the symbol `none' (no head there).
;; Lazy probing fills it entry by entry; the prebuilt index fills it in
;; one go.  The search does not care which happened.

(defconst diogenes-bailly--cache-format-version 1
  "Bumped when the cached data structure changes, to invalidate old files.")

(defvar diogenes-bailly--cache (make-hash-table :test 'equal)
  "Cache mapping a PDF cache-key to that file's state plist.")

(defun diogenes-bailly--cache-key (file)
  "Return a session cache key for FILE: its truename and mtime.
Machine-local by design -- it also names the fallback cache file."
  (let ((true (file-truename file)))
    (cons true (file-attribute-modification-time (file-attributes true)))))

(defun diogenes-bailly--signature (file)
  "Return a portable signature for the PDF FILE: its size in bytes.
Deliberately not the path or the mtime, both of which change when the
file is copied while its contents -- and therefore its running heads --
do not.  This is what a stored index records, so an index built here and
shipped alongside the PDF is accepted elsewhere without complaint, while
a genuinely different PDF is still caught."
  (file-attribute-size (file-attributes file)))

(defun diogenes-bailly--file ()
  "Return the configured Bailly PDF, or signal a user-error."
  (let ((file diogenes-bailly-pdf-file))
    (unless file
      (user-error "Set `diogenes-bailly-pdf-file' to your Bailly PDF first"))
    (unless (file-readable-p file)
      (user-error "Cannot read the Bailly PDF at %s" file))
    file))

(defun diogenes-bailly--new-state ()
  "Return an empty state plist."
  (list :heads (make-hash-table :test 'eql) :min nil :max nil))

;;; Serialisation ------------------------------------------------------

(defun diogenes-bailly--state-to-serializable (state)
  "Return STATE as plain data: its head table becomes an alist."
  (let (alist)
    (maphash (lambda (page head) (push (cons page head) alist))
             (plist-get state :heads))
    (list :heads (sort alist (lambda (a b) (< (car a) (car b))))
          :min (plist-get state :min)
          :max (plist-get state :max))))

(defun diogenes-bailly--state-from-serializable (data)
  "Inverse of `diogenes-bailly--state-to-serializable'."
  (let ((table (make-hash-table :test 'eql)))
    (dolist (kv (plist-get data :heads))
      (puthash (car kv) (cdr kv) table))
    (list :heads table :min (plist-get data :min) :max (plist-get data :max))))

(defun diogenes-bailly--index-file (file)
  "Return the path \\[diogenes-bailly-build-index] writes for the PDF FILE.
`<pdf-name>-index.eld' in the PDF's own folder, unless
`diogenes-bailly-index-file' says otherwise."
  (or diogenes-bailly-index-file
      (expand-file-name (concat (file-name-base file) "-index.eld")
                        (file-name-directory (expand-file-name file)))))

(defun diogenes-bailly--index-candidates (file)
  "Return the index files worth trying for the PDF FILE, best first.
The one \\[diogenes-bailly-build-index] would write, then any other
`*-index.eld' sitting in the same folder.  So an index built elsewhere
and dropped in beside the PDF is picked up whatever it is called, and
the PDF may be renamed without losing it -- safely, because an index
whose signature does not match the PDF is refused (see
`diogenes-bailly--read-index')."
  (let* ((primary (diogenes-bailly--index-file file))
         (dir (file-name-directory (expand-file-name file)))
         (others (and (file-directory-p dir)
                      (directory-files dir t "-index\\.eld\\'"))))
    (cons primary
          (seq-remove (lambda (f) (string= (expand-file-name f)
                                           (expand-file-name primary)))
                      others))))

(defun diogenes-bailly--disk-cache-file (key)
  "Return the fallback on-disk cache path for cache KEY, or nil if disabled."
  (when diogenes-bailly-cache-directory
    (expand-file-name (format "bailly-%d-%s.eld"
                              diogenes-bailly--cache-format-version
                              (secure-hash 'sha1 (format "%S" key)))
                      diogenes-bailly-cache-directory)))

(defun diogenes-bailly--read-index (path signature describe)
  "Read a stored state from PATH, or return nil.
SIGNATURE is the PDF's current signature.  A stored index whose signature
differs was built from a different PDF, and its page numbers would be
quietly wrong for this one, so it is REFUSED (with a message naming
DESCRIBE) rather than used: probing the PDF is cheap, a silently
misdirected lookup is not.  A missing, corrupt or wrong-version file is a
silent miss."
  (when (and path (file-readable-p path))
    (condition-case err
        (with-temp-buffer
          (insert-file-contents path)
          (goto-char (point-min))
          (let ((data (read (current-buffer))))
            ;; Stored form: (:diogenes-bailly-index VERSION SIGNATURE . STATE)
            (when (and (consp data)
                       (eq (car data) :diogenes-bailly-index)
                       (eq (nth 1 data) diogenes-bailly--cache-format-version))
              (if (equal (nth 2 data) signature)
                  (diogenes-bailly--state-from-serializable (nthcdr 3 data))
                (message "Bailly: ignoring %s -- it was built from a \
different PDF; rebuild it with M-x diogenes-bailly-build-index" describe)
                nil))))
      ;; A corrupt index must never break a lookup.
      (error (ignore err) nil))))

(defun diogenes-bailly--write-index (path signature state)
  "Write STATE for SIGNATURE to PATH; return the path on success.
Failures are swallowed and reported by the caller: a stored index is an
optimisation, never needed for correctness."
  (condition-case err
      (progn
        (make-directory (file-name-directory path) t)
        (let ((coding-system-for-write 'utf-8)
              (print-length nil)        ; never abbreviate long structures
              (print-level nil)
              (print-circle nil))
          (with-temp-file path
            (prin1 (append (list :diogenes-bailly-index
                                 diogenes-bailly--cache-format-version
                                 signature)
                           (diogenes-bailly--state-to-serializable state))
                   (current-buffer))))
        path)
    (error (ignore err) nil)))

;;; The state for a file ------------------------------------------------

(defun diogenes-bailly--state (file)
  "Return the state plist for FILE, loading or creating it as needed.
Resolution order, cheapest first:

  1. the in-memory cache (instant within a session);
  2. the portable prebuilt index beside the PDF, written by
     \\[diogenes-bailly-build-index] -- so even a fresh session, or a
     fresh machine the file was copied to, does no probing;
  3. the mtime-keyed fallback cache under
     `diogenes-bailly-cache-directory';
  4. an empty table, which the lookup then fills by probing the dozen
     pages it actually needs."
  (let ((key (diogenes-bailly--cache-key file))
        (signature (diogenes-bailly--signature file)))
    (or (gethash key diogenes-bailly--cache)
        (let ((loaded
               (or (cl-loop for path in (diogenes-bailly--index-candidates file)
                            thereis (diogenes-bailly--read-index
                                     path signature
                                     (abbreviate-file-name path)))
                   (diogenes-bailly--read-index
                    (diogenes-bailly--disk-cache-file key) signature
                    "the cached head table"))))
          (puthash key (or loaded (diogenes-bailly--new-state))
                   diogenes-bailly--cache)))))

(defun diogenes-bailly--head (file page)
  "Return PAGE's running head as (FIRST . LAST), or nil; cached.
A page whose head cannot be parsed is remembered as such, so it is read
only once per session."
  (let* ((heads (plist-get (diogenes-bailly--state file) :heads))
         (hit (gethash page heads)))
    (cond
     ((consp hit) hit)
     ((eq hit 'none) nil)
     (t (let* ((text (diogenes-bailly--page-text file page))
               (head (diogenes-bailly--parse-head text page)))
          ;; With pdf-tools only the top strip was read.  If it came back
          ;; empty the strip is too small (or the page renders oddly), which
          ;; is not the same thing as a page having no head, so read the
          ;; whole page before concluding there is none.  A page that does
          ;; yield text but no head -- a letter opening, front matter -- is
          ;; not re-read: parsing its body could invent a head.
          (when (and (null head)
                     (or (null text)
                         (string-match-p "\\`[[:space:]]*\\'" text)))
            (setq head (diogenes-bailly--parse-head
                        (diogenes-bailly--page-text file page t) page)))
          (puthash page (or head 'none) heads)
          head)))))

(defun diogenes-bailly--head-near-p (file page)
  "Non-nil if PAGE or one of its neighbours has a running head.
Used to decide whether PAGE is still inside the dictionary body: a
letter-opening page has no head of its own but sits between pages that
do."
  (and (> page 0)
       (or (diogenes-bailly--head file page)
           (diogenes-bailly--head file (1+ page))
           (and (> page 1) (diogenes-bailly--head file (1- page))))))

;;;; --------------------------------------------------------------------
;;;; WHERE THE DICTIONARY BODY BEGINS AND ENDS
;;;; --------------------------------------------------------------------

(defun diogenes-bailly--letter-bookmark-p (title)
  "Non-nil if TITLE is a bookmark opening a letter of the dictionary.
The Bailly 2020 outline titles those \"lettre Α, α\" -- but it also titles
the sections of the front-matter list of authors \"Lettre A - Auteurs -
ouvrages\", which is the same word followed by a LATIN letter.  Requiring
a Greek letter after \"lettre\" separates them; taking the author list for
the start of the dictionary would otherwise put the body\'s first page
some sixty pages too early."
  (save-match-data
    (and (string-match "\\`[[:space:]]*lettre[[:space:]]+\\(.\\)"
                       (downcase title))
         (diogenes-bailly--lemma-token-p (match-string 1 (downcase title))))))

(defun diogenes-bailly--letter-pages (file)
  "Return the pages of FILE's \"lettre <Greek letter>\" bookmarks, ascending.
Nil when pdf-tools is unavailable or the PDF has no such bookmarks.  See
`diogenes-bailly--letter-bookmark-p' for what counts as one."
  (when (or (fboundp 'pdf-info-outline) (require 'pdf-info nil t))
    (ignore-errors
      (sort (cl-loop for entry in (pdf-info-outline file)
                     for page = (alist-get 'page entry)
                     for title = (or (alist-get 'title entry) "")
                     when (and (integerp page) (> page 0)
                               (diogenes-bailly--letter-bookmark-p title))
                     collect page)
            #'<))))

(defun diogenes-bailly--find-body-start (file)
  "Return the first page of the dictionary body in FILE.
Prefers the first \"lettre …\" bookmark.  Failing that, scans forward for
the first page that has a running head whose successor also has one, in
order -- a stray page of front matter cannot fake that -- and steps back
one page, since a letter-opening page carries no head."
  (or (car (diogenes-bailly--letter-pages file))
      (cl-loop for page from 1 to 400
               for this = (diogenes-bailly--head file page)
               for next = (and this (diogenes-bailly--head file (1+ page)))
               when (and this next
                         (not (string< (diogenes-bailly--key (car next))
                                       (diogenes-bailly--key (car this)))))
               return (max 1 (1- page)))
      (user-error "Found no running heads in %s: is it a text-layer PDF of Bailly?"
                  file)))

(defun diogenes-bailly--find-body-end (file start)
  "Return the last page of the dictionary body in FILE, above START.
Walks back from `pdf-info-number-of-pages' when pdf-tools is available;
otherwise doubles a step until it is past the body, then bisects.  Either
way a handful of probes, once per session."
  (let ((known (and (or (fboundp 'pdf-info-number-of-pages)
                        (require 'pdf-info nil t))
                    (ignore-errors (pdf-info-number-of-pages file)))))
    (if known
        (cl-loop for page downfrom known to start
                 when (diogenes-bailly--head file page) return page
                 finally return start)
      (let ((inside start) (step 1) (outside nil))
        (while (and (null outside) (< step 8192))
          (let ((probe (+ inside step)))
            (if (diogenes-bailly--head-near-p file probe)
                (setq inside probe
                      step (* 2 step))
              (setq outside probe))))
        (unless outside (setq outside (+ inside step)))
        (while (> (- outside inside) 1)
          (let ((mid (/ (+ inside outside) 2)))
            (if (diogenes-bailly--head-near-p file mid)
                (setq inside mid)
              (setq outside mid))))
        (cl-loop for page downfrom inside to start
                 when (diogenes-bailly--head file page) return page
                 finally return start)))))

(defun diogenes-bailly--body-range (file)
  "Return (FIRST . LAST), the PDF pages of the dictionary body of FILE.
Honours `diogenes-bailly-body-range' when set; otherwise detects the
range once and keeps it with the file's heads."
  (or diogenes-bailly-body-range
      (let ((state (diogenes-bailly--state file)))
        (unless (and (plist-get state :min) (plist-get state :max))
          (let* ((start (diogenes-bailly--find-body-start file))
                 (end (diogenes-bailly--find-body-end file start)))
            (when (< end start)
              (user-error "Could not delimit the dictionary body in %s" file))
            (plist-put state :min start)
            (plist-put state :max end)))
        (cons (plist-get state :min) (plist-get state :max)))))

;;;; --------------------------------------------------------------------
;;;; HEADWORD -> PAGE
;;;; --------------------------------------------------------------------

(defun diogenes-bailly--probe (file page lo hi)
  "Return the page nearest PAGE within LO..HI that has a running head.
Nil if none has.  Letter-opening pages are the only gaps inside the
body, so this normally returns PAGE itself or a neighbour."
  (cl-loop for d from 0 to 5
           thereis (cl-loop for cand in (list (+ page d) (- page d))
                            when (and (<= lo cand) (<= cand hi)
                                      (diogenes-bailly--head file cand))
                            return cand)))

(defun diogenes-bailly--search (file key)
  "Return the first page of FILE whose head interval reaches KEY, or nil.
That is the lowest page whose LAST lemma sorts at or after KEY, so an
entry running over a page break resolves to the page it begins on.
Pages without a head are skipped as probe points."
  (let* ((range (diogenes-bailly--body-range file))
         (lo (car range))
         (hi (cdr range))
         (found nil))
    (while (<= lo hi)
      (let ((probe (diogenes-bailly--probe file (/ (+ lo hi) 2) lo hi)))
        (if (null probe)
            (setq lo (1+ hi))          ; nothing left to probe: stop
          (let ((head (diogenes-bailly--head file probe)))
            (if (not (string< (diogenes-bailly--key (cdr head)) key))
                (setq found probe
                      hi (1- probe))
              (setq lo (1+ probe)))))))
    found))

(defun diogenes-bailly--refine (file page key tight)
  "Adjust PAGE, as returned by `diogenes-bailly--search', and return it.
KEY and TIGHT are the word's accent-insensitive and accent-keeping keys.
Three corrections, all for things the running heads cannot settle alone:

  * the word sorts BEFORE this page's first lemma, so it belongs to the
    page before -- the one that opens a letter and prints no head;
  * several consecutive pages share the word's key (the ποιός/ποῖος,
    τίς/τις/τὶς clusters): if a later page of that run has the word
    itself as its first lemma, that is the page;
  * the word's key equals this page's first lemma but is spelt
    differently, and the page before opens a letter: the entry is on
    that head-less page."
  (let* ((range (diogenes-bailly--body-range file))
         (min-page (car range))
         (max-page (cdr range))
         (head (diogenes-bailly--head file page))
         (first-key (diogenes-bailly--key (car head))))
    (cond
     ((and (string< key first-key) (> page min-page))
      (1- page))
     ((or (string= (diogenes-bailly--tight-key (car head)) tight)
          (string= (diogenes-bailly--tight-key (cdr head)) tight))
      page)
     (t
      (or
       ;; Walk the run of pages still sharing KEY, looking for the word.
       (cl-loop for p from (1+ page) to max-page
                for h = (diogenes-bailly--head file p)
                while (and h (not (string< key (diogenes-bailly--key (car h)))))
                when (string= (diogenes-bailly--tight-key (car h)) tight)
                return p)
       (and (string= key first-key)
            (> page min-page)
            (not (diogenes-bailly--head file (1- page)))
            (1- page))
       page)))))

(defun diogenes-bailly--page-for-word (word &optional file)
  "Return the Bailly page number for WORD's entry, or nil.
FILE defaults to `diogenes-bailly-pdf-file'.  The page is found by a
binary search over the running heads of the dictionary's pages -- read
from the PDF on demand, or from a prebuilt index if one was built -- and
`diogenes-bailly-page-offset' is added to the result.

A word that is no lemma of Bailly's still yields the page where it would
stand alphabetically, which is what one wants for an inflected form or a
variant spelling."
  (let* ((file (or file (diogenes-bailly--file)))
         (key (diogenes-bailly--key word)))
    (unless (string-empty-p key)
      (let ((page (diogenes-bailly--search file key)))
        (when page
          (+ (diogenes-bailly--refine file page key
                                      (diogenes-bailly--tight-key word))
             diogenes-bailly-page-offset))))))

(defun diogenes-bailly--head-string (file page)
  "Return \"FIRST – LAST\" for PAGE of FILE, or nil; used in messages."
  (let ((head (diogenes-bailly--head file (- page diogenes-bailly-page-offset))))
    (when head (format "%s – %s" (car head) (cdr head)))))

;;;; --------------------------------------------------------------------
;;;; BUILDING THE PORTABLE INDEX
;;;; --------------------------------------------------------------------

(defun diogenes-bailly--read-all-heads-pdftotext (file first last state)
  "Fill STATE's head table for pages FIRST..LAST of FILE in one pass.
Runs `pdftotext' once over the whole dictionary; pages come back
separated by form feeds.  Returns the number of pages that carry a head."
  (let ((heads (plist-get state :heads))
        (found 0))
    (with-temp-buffer
      (unless (zerop (call-process diogenes-bailly-pdftotext-program nil t nil
                                   "-layout"
                                   "-f" (number-to-string first)
                                   "-l" (number-to-string last)
                                   file "-"))
        (user-error "%s failed on %s" diogenes-bailly-pdftotext-program file))
      (let ((page first))
        (dolist (text (split-string (buffer-string) "\f"))
          (when (<= page last)
            (let ((head (diogenes-bailly--parse-head text page)))
              (when head (setq found (1+ found)))
              (puthash page (or head 'none) heads))
            (setq page (1+ page))))))
    found))

(defun diogenes-bailly--read-all-heads-page-by-page (file first last)
  "Fill the head table for pages FIRST..LAST of FILE one page at a time.
The fallback when `pdftotext' is absent: slower, but needs nothing but
pdf-tools.  Returns the number of pages that carry a head."
  (let ((reporter (make-progress-reporter "Bailly: reading running heads..."
                                          first last))
        (found 0))
    (cl-loop for page from first to last
             do (when (diogenes-bailly--head file page)
                  (setq found (1+ found)))
                (progress-reporter-update reporter page))
    (progress-reporter-done reporter)
    found))

;;;###autoload
(defun diogenes-bailly-build-index ()
  "Read every running head of the Bailly PDF and write a portable index.
Lookups work without this -- each reads the dozen pages it needs -- but
building the index once makes every later lookup, in this and any future
session, instant.  The file is `<pdf-name>-index.eld' beside the PDF (or
`diogenes-bailly-index-file'), the counterpart of Passow's
`passow-index.eld': plain data, portable, worth committing next to the
PDF.  If that folder cannot be written, the table is saved instead under
`diogenes-bailly-cache-directory', which serves the same purpose for
this machine only.

With poppler's `pdftotext' this is one pass and takes a few seconds;
with pdf-tools alone it reads page by page and takes longer."
  (interactive)
  (let* ((file (diogenes-bailly--file))
         (key (diogenes-bailly--cache-key file))
         (signature (diogenes-bailly--signature file))
         (range (diogenes-bailly--body-range file))
         (first (car range))
         (last (cdr range))
         (state (diogenes-bailly--new-state))
         found)
    (plist-put state :min first)
    (plist-put state :max last)
    (setq found
          (if (and (diogenes-bailly--pdftotext-p)
                   (not (eq diogenes-bailly-text-method 'pdf-tools)))
              (progn
                (message "Bailly: reading the running heads of %s ..."
                         (file-name-nondirectory file))
                (diogenes-bailly--read-all-heads-pdftotext file first last state))
            ;; No pdftotext: fill the session cache page by page, then copy
            ;; that table into the state we are about to write.
            (let ((n (diogenes-bailly--read-all-heads-page-by-page
                      file first last)))
              (setq state (copy-sequence (diogenes-bailly--state file)))
              n)))
    ;; Make the current session use the freshly built table.
    (puthash key state diogenes-bailly--cache)
    (let ((written (or (diogenes-bailly--write-index
                        (diogenes-bailly--index-file file) signature state)
                       (let ((fallback (diogenes-bailly--disk-cache-file key)))
                         (and fallback
                              (diogenes-bailly--write-index
                               fallback signature state))))))
      (message "Bailly: %d of %d pages carry a running head (pp. %d-%d)%s"
               found (1+ (- last first)) first last
               (if written
                   (format "; index written to %s" (abbreviate-file-name written))
                 "; could not write an index file, so this session only")))))

;;;###autoload
(defun diogenes-bailly-clear-cache ()
  "Forget the cached Bailly running heads and body range.
Clears the in-memory table and deletes the mtime-keyed files under
`diogenes-bailly-cache-directory', so the next lookup reads the PDF
again.  The portable index written by \\[diogenes-bailly-build-index] is
a deliberate artifact and is left alone -- delete or rebuild it yourself
after replacing the PDF; it records the PDF's signature and warns when
it looks stale."
  (interactive)
  (clrhash diogenes-bailly--cache)
  (when (and diogenes-bailly-cache-directory
             (file-directory-p diogenes-bailly-cache-directory))
    (dolist (f (directory-files diogenes-bailly-cache-directory t
                                "\\`bailly-[0-9]+-.*\\.eld\\'"))
      (ignore-errors (delete-file f))))
  (message "Diogenes Bailly page cache cleared"))

;;;; --------------------------------------------------------------------
;;;; INTERACTIVE ENTRY POINTS
;;;; --------------------------------------------------------------------

(defvar diogenes--lookup-headword)      ; from diogenes-perseus.el

(declare-function diogenes--lookup-headword-at-point "diogenes-perseus"
                  (&optional pos))
(declare-function diogenes--lookup-assert-lang "diogenes-perseus"
                  (expected dict-name))

(defun diogenes-bailly--current-headword ()
  "Return the headword to look up for the Greek entry point is in.
Resolved from point on every call via
`diogenes--lookup-headword-at-point', so the opener always acts on the
entry the cursor is currently in -- including entries loaded later by
`diogenes-lookup-next' / `diogenes-lookup-previous'."
  (or (and (fboundp 'diogenes--lookup-headword-at-point)
           (diogenes--lookup-headword-at-point))
      (get-text-property (point) 'orth)
      (and (boundp 'diogenes--lookup-headword) diogenes--lookup-headword)
      (thing-at-point 'word t)
      (user-error "No headword found at point")))

;;;###autoload
(defun diogenes-lookup-open-bailly (&optional word)
  "Open Bailly's Dictionnaire grec-français at the entry for WORD.
Interactively, WORD defaults to the headword of the Greek entry at point
in a `diogenes-lookup-mode' buffer.  With a prefix argument, prompt for
the word.

Requires `diogenes-bailly-pdf-file' to point at a Bailly PDF with a text
layer, and `pdf-tools' (recommended) or `doc-view' for display."
  (interactive
   (progn
     (diogenes--lookup-assert-lang "greek" "Bailly's Dictionnaire grec-français")
     (list (if current-prefix-arg
               (read-string "Open Bailly at word: ")
             (diogenes-bailly--current-headword)))))
  (let* ((word (or word (diogenes-bailly--current-headword)))
         (file (diogenes-bailly--file))
         (page (diogenes-bailly--page-for-word word file)))
    (unless page
      (user-error "Could not locate \"%s\" in Bailly" word))
    ;; Reuse the OLD module's viewer driver (pdf-tools/doc-view/Reader,
    ;; async startup, page clamping, large-file prompt).
    (diogenes-old--show-page page file)
    (let ((head (diogenes-bailly--head-string file page)))
      (if head
          (message "Bailly: \"%s\" -> page %d (%s)" word page head)
        (message "Bailly: \"%s\" -> page %d" word page)))))

(provide 'diogenes-bailly)
;;; diogenes-bailly.el ends here
