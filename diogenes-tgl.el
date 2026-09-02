;;; diogenes-tgl.el --- Open Estienne's Thesaurus Graecae Linguae page images -*- lexical-binding: t -*-

;;; Commentary:

;; Jump from a Diogenes *Greek* dictionary entry (the buffer produced by
;; `diogenes-lookup-mode') to the page of Henri Estienne's (Stephanus's)
;; _Thesaurus Graecae Linguae_ (TGL / TLG, the 1572 folio in the
;; Bayerische Staatsbibliothek scans) that contains that entry, shown in
;; the volume's PDF with `pdf-tools' (or `doc-view').  It is the Greek
;; counterpart of `diogenes-passow.el' and reuses that module's Greek
;; collation key and PDF-display driver.
;;
;; ---------------------------------------------------------------------
;; WHY THE TGL NEEDS ITS OWN MODULE
;; ---------------------------------------------------------------------
;;
;; The TGL is organised ETYMOLOGICALLY, not strictly alphabetically: a
;; root word is a main entry (printed in FULL CAPITALS at the left
;; margin), and its morphological/derivational relatives are nested
;; UNDER it as sub-entries (printed with a single leading capital).  So
;; e.g. διαλέγω is found under λέγω, and κάμψις under κάμπτω.  A plain
;; "find the running head" search -- which works for an alphabetical
;; dictionary like Passow or the OLD -- therefore does NOT reliably lead
;; to a derived word, because that word never heads a page.
;;
;; Fortunately the last (fifth) volume ends with a COMPREHENSIVE INDEX
;; that lists (very nearly) every word -- roots AND derivatives -- each
;; with a pointer of the form
;;
;;     <word>, t.<volume>, c.<column>, <section-letter>
;;
;; e.g. "Αβαξ, τ.1, c.1, b" or (OCR-mangled) "Αβασανισος, 1.1.0.723.8".
;; Those pointers are to the PRINTED book (tomus + column), NOT to PDF
;; pages, so we must translate them.
;;
;; This module therefore looks a word up in TWO stages:
;;
;;   1. ENTRY OPENING (caps).  The root entries are printed in FULL
;;      CAPITALS at the left margin, so the first page on which a word's
;;      all-caps headword appears is the true opening of its article.
;;      We build, per volume, a map from each caps headword to that
;;      first page and consult it FIRST -- it beats the index for long
;;      roots, whose index column often points into the middle of the
;;      article (the index sends ἔχω to a column about eleven pages past
;;      where ΕΧΩ actually begins).
;;
;;   2. INDEX (exact).  Otherwise parse the index in volume V, find the
;;      word by an exact headword match, read its (volume, column), and
;;      translate the column to a PDF page of that volume.
;;
;;   3. CROSS-REFERENCE HOP.  Many nested words carry no column of their
;;      own but an index line "vide in <root>" (e.g. "Αδενοειδής … vide
;;      in Αδήν").  We resolve the named root (by its caps opening, else
;;      the index) and use its location.
;;
;;   4. MORPHOLOGICAL FALLBACK.  A bare compound the index neither
;;      columns nor cross-references (e.g. διαλέγω under λέγω,
;;      καταλαμβάνω under λαμβάνω) is decomposed by stripping ONE leading
;;      prefix per Smyth, Greek Grammar Sections 870, 884-885 -- undoing
;;      the vowel contraction/lengthening at the seam (Sections 884 b,
;;      887) so δια+λεγω's surface αλεγω is reduced to the true root
;;      λεγω -- and the root is resolved by its caps opening or an EXACT
;;      index hit.  A small explicit table also maps specific
;;      REDUPLICATED presents to their root (e.g. πιφαύσκω -> φάω), since
;;      those are filed under a root in another volume that no
;;      letter-based route or general prefix rule could reach safely.
;;      Conservative and gated so it adds coverage without manufacturing
;;      cross-volume errors.
;;
;;   5. INDEX (fuzzy).  Only now, as a lower-priority attempt, a 1-edit
;;      fuzzy index match (for a word whose own headword the OCR
;;      garbled), accepted only when its volume agrees with the letter
;;      the word begins with -- so a garbled near-miss of another volume
;;      cannot hijack the lookup, and cannot outrank a real entry
;;      opening found above.
;;
;;   6. BODY FALLBACK.  Finally, scan the volumes' OCR for the word as a
;;      left-margin entry -- the Passow technique -- routing to the
;;      right volume by the letter each volume covers.  This reaches
;;      sub-lemmata (printed with a single leading capital) too.
;;
;; KNOWN LIMITATION.  A truly nested compound that has NO caps entry of
;; its own, NO index column, NO "vide" line, and NO strippable prefix
;; whose root resolves cannot be placed under its root with certainty --
;; nothing in the OCR records where Estienne filed it.  For such a word
;; the body scan lands in its own alphabetical neighbourhood, and the
;; running head lets the reader adjust.  This is inherent to a
;; page-image navigation aid over an etymologically-nested lexicon and
;; noisy OCR, and does not affect the many words handled by stages 1-5.
;;
;; ---------------------------------------------------------------------
;; COLUMN  ->  PDF PAGE
;; ---------------------------------------------------------------------
;;
;; The TGL folio is paginated by COLUMN, two columns to a physical page,
;; and each OCR page carries its two column numbers at the top, right
;; after the "----- N / TOTAL -----" delimiter, e.g.
;;
;;     ----- 57 / 1034 -----
;;     1
;;     2
;;     ...
;;
;; so PDF page 57 of volume I holds columns 1-2, page 58 holds 3-4, and
;; so on.  The left column L on a page satisfies  L = 2*PDF + b  for an
;; intercept b that is constant within a run and jumps only at an
;; inserted (unnumbered) plate -- a "seam" that shifts every following
;; page.  We exploit that fixed slope of 2 to derive the pagination from
;; its own structure rather than trusting scattered anchors:
;;
;;   * ORIGIN.  Each volume opens with front matter (often numbered in
;;     Roman numerals) before the arabic column count begins at cols 1-2
;;     (or 5-6).  We find the PDF page of arabic column 1 by EXTRAPOLATION
;;     -- since L = 2*PDF + b, each early anchor implies the origin page,
;;     and we take the modal implied origin -- so a leading "1" the OCR
;;     glued onto the Greek header does not matter.
;;   * SEAMS.  Walking the anchors in column order, we open a new segment
;;     only where several consecutive anchors agree on a new intercept b,
;;     so a single garbled column cannot invent a false seam and a genuine
;;     plate is carried forward for all later columns.
;;
;; The result is a PIECEWISE slope-2 model -- a list of (START-COLUMN . b)
;; segments -- and a column maps to  floor((COLUMN - b) / 2)  under its
;; segment.  This is robust to a garbled anchor (an outlier b that never
;; forms a segment) and to a page whose own anchor is missing (its
;; segment's line still places it).  No pre-built data and no Perl are
;; needed: everything is parsed from the OCR text shipped with each
;; volume.
;;
;; ---------------------------------------------------------------------
;; ACCURACY AND ONE KNOWN LIMITATION
;; ---------------------------------------------------------------------
;;
;; On genuine (cleanly-OCR'd) headwords this lands on the correct
;; volume about nine times in ten, and on the exact column-page for the
;; large majority; the misses are dominated by OCR noise -- a garbled
;; headword the fuzzy step cannot repair, or a very short key that
;; collides with a homograph in another volume.  It is a navigation aid,
;; not an oracle: you arrive on the right page (or its immediate
;; neighbour), read the running head, and nudge if need be.
;;
;; The genuinely unsolvable case is a NESTED COMPOUND that the index
;; records with NEITHER a column of its own NOR a "vide in <root>"
;; pointer -- a bare derivative like διαλέγω, printed only under λέγω.
;; Nothing in the OCR marks that "διαλέγω lives under λέγω": the
;; relationship exists solely in the editors' heads and the physical
;; nesting.  For such a word the best any method can do is route by its
;; own initial letter, so this module lands you in the δια- neighbourhood
;; rather than under λέγω.  Words that DO get an index column or a "vide"
;; cross-reference -- the great majority of derivatives -- are found.
;;
;; ---------------------------------------------------------------------
;; DIRECTORY LAYOUT
;; ---------------------------------------------------------------------
;;
;; A single parent folder (say TGL/) holds one sub-directory per volume,
;; named with the volume's Roman numeral exactly as the tomus is
;; numbered:
;;
;;     TGL/
;;       I/     <- tomus 1 : PDF + OCR .txt   (Α … Δ)
;;       II/    <- tomus 2 : PDF + OCR .txt   (Ε … Ο)
;;       III/   <- tomus 3 : PDF + OCR .txt   (Π … Υ)
;;       IIII/  <- tomus 4 : PDF + OCR .txt   (Φ … Ω)
;;       V/     <- tomus 5 : PDF + OCR .txt   (dialects appendix + INDEX)
;;
;; Each sub-directory contains that volume's PDF and an OCR text file
;; whose pages are delimited by "----- N / TOTAL -----" lines.  The
;; folder name is the sole source of the tomus number, so the index's
;; "t.<n>" pointers map straight onto folder <Roman-numeral-of-n>.
;;
;; Setup:
;;
;;   (setq diogenes-tgl-directory "/path/to/TGL/")   ; the parent folder
;;
;; Then, in a Greek lookup buffer, press `T' or click the "[TGL]" link.

;;; Code:
(require 'cl-lib)
(require 'seq)
(require 'diogenes-old)                 ; reuse the PDF display driver
(require 'diogenes-montanari)           ; reuse the Greek collation key

(declare-function evil-make-overriding-map "evil-core" (keymap &optional state copy))
(declare-function evil-normalize-keymaps "evil-core" (&optional state))
(declare-function diogenes--lookup-assert-lang "diogenes-perseus"
                  (expected dict-name))
(declare-function pdf-info-outline "pdf-info" (&optional file-or-buffer))

;;;; --------------------------------------------------------------------
;;;; CUSTOMIZATION
;;;; --------------------------------------------------------------------

(defcustom diogenes-tgl-directory nil
  "Directory holding the TGL volumes, one sub-directory per volume.
The sub-directories must be named with each volume's Roman numeral
\(I, II, III, IIII, V), and each must contain that volume's PDF and
an OCR text file whose pages are delimited by
\"----- N / TOTAL -----\" lines.  Volume V additionally supplies
the comprehensive index used as the primary lookup path.  The
folder name is taken as the tomus number, so the index's \"t.<n>\"
pointers map directly onto folder <n-in-Roman>."
  :type '(choice (const :tag "Not set" nil) directory)
  :group 'diogenes)

(defcustom diogenes-tgl-text-regexp "\\.txt\\'"
  "Regexp matching the OCR text file within a volume sub-directory.
The first file matching this in a volume folder is used."
  :type 'regexp
  :group 'diogenes)

(defcustom diogenes-tgl-pdf-regexp "\\.pdf\\'"
  "Regexp matching the PDF within a volume sub-directory.
The first file matching this in a volume folder is used."
  :type 'regexp
  :group 'diogenes)

(defcustom diogenes-tgl-page-offset 0
  "Integer added to every PDF page derived from a column number.
The column->page backbone is built from the column numbers printed
in the OCR itself, so its result is already a physical PDF page and
this normally stays 0.  Adjust only if your scans carry a constant
extra shift (e.g. a differing number of unnumbered cover pages that
the OCR page numbering does not count)."
  :type 'integer
  :group 'diogenes)

(defcustom diogenes-tgl-v5-part2-page nil
  "PDF page where volume V's index part 2 restarts its column numbering.
Volume V prints its back-of-book index in two parts; part 2 begins its
column count again at 1 on a later page, so a column number alone is
ambiguous between the two parts.  Left nil, the restart page is
detected automatically (`diogenes-tgl--detect-column-restart').  Set an
integer to pin it if a particular scan defeats detection."
  :type '(choice (const :tag "Auto-detect" nil) integer)
  :group 'diogenes)

(defcustom diogenes-tgl-page-marker-regexp
  "^-----[[:space:]]*\\([0-9]+\\)[[:space:]]*/[[:space:]]*[0-9]+[[:space:]]*-----[[:space:]]*$"
  "Regexp matching an OCR page-delimiter line; group 1 is the OCR/PDF page."
  :type 'regexp
  :group 'diogenes)

(defcustom diogenes-tgl-display-in-other-window nil
  "If non-nil, show the TGL PDF in another window, keeping the entry visible.
Bound to `diogenes-old-display-in-other-window' for the duration of the
display, and defaults to nil for the same reason: the page appears in the
window the lookup was made from, replacing the entry.

Left as it is, and not folded into `diogenes-window-behaviour\=': this says
whether THIS dictionary's page goes somewhere other than the window it was
asked for from, which is a question about one printed dictionary rather than
about where Diogenes buffers go.  Where it sends the page elsewhere,
`diogenes-dictionary-display-action\=' and `diogenes-window-behaviour\=' decide
where elsewhere is."
  :type 'boolean
  :group 'diogenes)

(defcustom diogenes-tgl-fuzzy-lookup t
  "If non-nil, allow a 1-edit fuzzy match when an index lookup misses.
The TGL OCR frequently drops or garbles a single letter of an index
headword (so a correctly-spelled lemma will not match it exactly).
When enabled, a missed exact lookup retries against index keys that
share the word's first two letters and differ from it by at most one
inserted, deleted or substituted letter."
  :type 'boolean
  :group 'diogenes)

;;;; --------------------------------------------------------------------
;;;; TOMUS  <->  FOLDER NAME
;;;; --------------------------------------------------------------------

(defconst diogenes-tgl--roman
  '((1 . "I") (2 . "II") (3 . "III") (4 . "IIII") (5 . "V"))
  "Map a TGL tomus number to its volume sub-directory name.
Note volume 4 uses the additive \"IIII\" (as on the folio's own
title pages), not the subtractive \"IV\".")

(defun diogenes-tgl--folder-tomus (name)
  "Return the tomus number encoded by sub-directory NAME, or nil.
Accepts the additive \"IIII\" and the subtractive \"IV\" for tomus 4."
  (let ((n (upcase (string-trim name))))
    (cond ((string= n "I") 1)
          ((string= n "II") 2)
          ((string= n "III") 3)
          ((or (string= n "IIII") (string= n "IV")) 4)
          ((string= n "V") 5))))

;;;; --------------------------------------------------------------------
;;;; COLUMN NUMBERS  ->  PDF PAGE  (per volume, from the OCR)
;;;; --------------------------------------------------------------------

;; For each page we read the numeric lines printed just under the page
;; marker.  A page's two column numbers appear there as a consecutive
;; pair (L, L+1); L is the page's left column.  Collected over the
;; volume these give a slope-2 backbone  L = 2*PDF + b  whose offset b is
;; locally constant.  A garbled column number shows up as an anchor
;; whose b disagrees with its neighbours; we drop those, then invert the
;; backbone to map an arbitrary column to its page.

(defun diogenes-tgl--page-anchors (file)
  "Scan OCR FILE and return an alist (PDF-PAGE . LEFT-COLUMN), by page.
For each OCR page the first consecutive numeric pair (L, L+1) found
among the lines just under the page marker is taken as that page's
\(left) column L.  Pages without such a pair contribute nothing."
  (let ((anchors nil))
    (with-temp-buffer
      (insert-file-contents file)
      (goto-char (point-min))
      (let ((marker diogenes-tgl-page-marker-regexp))
        (while (re-search-forward marker nil t)
          (let ((pdfp (string-to-number (match-string 1)))
                (nums nil)
                (limit (save-excursion
                         (if (re-search-forward marker nil t)
                             (match-beginning 0)
                           (point-max)))))
            ;; Gather up to the first several all-digit lines of the body.
            (save-excursion
              (let ((count 0))
                (while (and (< (point) limit) (< count 8)
                            (zerop (forward-line 1)))
                  (setq count (1+ count))
                  (let ((s (string-trim
                            (buffer-substring-no-properties
                             (line-beginning-position) (line-end-position)))))
                    (when (string-match-p "\\`[0-9]\\{1,5\\}\\'" s)
                      (push (string-to-number s) nums))))))
            (setq nums (nreverse nums))
            (cl-loop for (a b) on nums
                     while b
                     when (and (= b (1+ a)) (> a 0) (< a 6000))
                     do (push (cons pdfp a) anchors) and return nil)))))
    (nreverse anchors)))

(defun diogenes-tgl--detect-origin (anchors)
  "Return the PDF page carrying arabic column 1, inferred from ANCHORS.
ANCHORS is an alist (PDF-PAGE . LEFT-COLUMN).  Each volume opens with
some front matter (often numbered in Roman numerals) before the arabic
column count begins at columns 1-2 (or 5-6); that first arabic page is
the origin from which the two-columns-per-page law places every other
column.  Rather than trust a clean \"1 2\" to be legible on the origin
page itself -- the OCR frequently glues that leading \"1\" onto the
Greek header (\"1 ΚΑΓX\") -- we EXTRAPOLATE it: by the slope-2 law each
early anchor (PAGE, COL) implies origin = PAGE - (COL-1)/2, so we take
the modal implied origin over the earliest anchors, which outvotes a
garbled one.  Returns nil if ANCHORS is empty."
  (let ((by-page (sort (copy-sequence anchors)
                       (lambda (a b) (< (car a) (car b)))))
        (votes (make-hash-table :test 'eql))
        (seen 0))
    (cl-loop for (pg . col) in by-page
             while (< seen 25)
             do (setq seen (1+ seen))
                ;; left column COL sits on PG; column 1 is (COL-1)/2 pages earlier.
                (let ((origin (- pg (/ (1- col) 2))))
                  (puthash origin (1+ (gethash origin votes 0)) votes)))
    (let ((best nil) (bestn 0))
      (maphash (lambda (o n) (when (> n bestn) (setq best o bestn n))) votes)
      best)))

;; Per-volume column model.  The folio prints two columns per physical
;; page, the column number advancing by two each page, so within one run
;; the left column L satisfies  L = 2*PDF + b  for a constant intercept b.
;; b changes only at an inserted (unnumbered) plate -- a "seam" -- which
;; shifts every subsequent page by a whole number of pages.  The model is
;; therefore PIECEWISE slope-2: a list of (START-COLUMN . b) segments in
;; ascending column order, the first seeded from the auto-detected arabic
;; origin.  This derives the pagination from its own structure, so it is
;; robust to a garbled anchor (an outlier b that never forms a segment)
;; and to a page whose own anchor is missing (the segment's line still
;; places it), and it carries the offset correctly across each seam.
(defvar diogenes-tgl--colmodel-cache (make-hash-table :test 'equal)
  "Cache mapping a volume OCR cache-key to its piecewise slope-2 model.
The value is a list of (START-COLUMN . INTERCEPT) segments, ascending
by START-COLUMN, where a column C in that segment maps to PDF page
\(C - INTERCEPT) / 2.")

(defun diogenes-tgl--file-cache-key (file)
  "Return a cache key for FILE combining its truename and mtime."
  (let ((true (file-truename file)))
    (cons true (file-attribute-modification-time (file-attributes true)))))

(defconst diogenes-tgl--seam-run 3
  "Consecutive agreeing anchors required to confirm a new pagination segment.
A single OCR-garbled column yields one outlier intercept; requiring a
run of this many anchors that all share a new intercept before opening
a segment keeps such a garble from creating a false seam.")

(defun diogenes-tgl--build-model-from-anchors (anchors)
  "Build a piecewise slope-2 model from ANCHORS, an alist (PDF-PAGE . COL).
Returns a list of (START-COLUMN . INTERCEPT) segments, or nil.  Seeds
the first segment from the auto-detected arabic origin
\(`diogenes-tgl--detect-origin'), then walks the anchors in column
order, opening a new segment whenever `diogenes-tgl--seam-run'
consecutive anchors agree on a new intercept b = COLUMN - 2*PDF."
  (let ((origin (diogenes-tgl--detect-origin anchors)))
    (when origin
      (let* ((by-col (sort (copy-sequence anchors)
                           (lambda (a b) (< (cdr a) (cdr b)))))
             (vec (vconcat by-col))
             (n (length vec))
             (segments (list (cons 1 (- 1 (* 2 origin)))))
             (cur-b (- 1 (* 2 origin)))
             (i 0))
        (while (< i n)
          (let* ((e (aref vec i))
                 (b (- (cdr e) (* 2 (car e)))))
            (if (= b cur-b)
                (setq i (1+ i))
              (let ((j i) (cnt 0))
                (while (and (< j n) (< cnt diogenes-tgl--seam-run)
                            (= (- (cdr (aref vec j)) (* 2 (car (aref vec j)))) b))
                  (setq cnt (1+ cnt) j (1+ j)))
                (if (>= cnt diogenes-tgl--seam-run)
                    (progn
                      (setq segments (cons (cons (cdr e) b) segments))
                      (setq cur-b b)
                      (setq i j))
                  (setq i (1+ i)))))))
        (nreverse segments)))))

(defun diogenes-tgl--build-column-model (file)
  "Build the piecewise slope-2 column model for volume OCR FILE.
Returns a list of (START-COLUMN . INTERCEPT) segments (see
`diogenes-tgl--colmodel-cache')."
  (diogenes-tgl--build-model-from-anchors
   (diogenes-tgl--page-anchors file)))

(defun diogenes-tgl--detect-column-restart (anchors)
  "Return the PDF page where the column count RESTARTS, or nil.
Volume V's back-of-book index is printed in TWO parts, the second
restarting its column numbering at 1 (on a later PDF page).  Walking
ANCHORS in page order, a restart shows as the left column dropping far
below the running maximum and then continuing upward from the low
value.  Returns the first such page (the part-2 origin), or nil when
the column count never restarts (the normal single-part case)."
  (let ((by-page (sort (copy-sequence anchors)
                       (lambda (a b) (< (car a) (car b)))))
        (running-max -1) (found nil))
    (while (and by-page (not found))
      (let* ((e (car by-page)) (pg (car e)) (col (cdr e)))
        (when (< col (- running-max 100))
          ;; confirm the next few anchors continue upward from about here
          (let* ((tail (seq-take by-page 4))
                 (cols (mapcar #'cdr tail)))
            (when (and (>= (length cols) 2)
                       (< (car (last cols)) running-max)
                       (cl-loop for (a b) on cols while b
                                always (<= a (+ b 2))))
              (setq found pg))))
        (setq running-max (max running-max col))
        (setq by-page (cdr by-page))))
    found))

(defun diogenes-tgl--index-marker-page (file)
  "Return the OCR/PDF page where the `INDEX IN' marker appears in FILE, or nil.
This is the first page of the index proper (volume V); columns printed
before it belong to the front matter."
  (with-temp-buffer
    (insert-file-contents file)
    (goto-char (point-min))
    (when (search-forward diogenes-tgl--index-marker nil t)
      (let ((mk diogenes-tgl-page-marker-regexp) (page nil))
        (save-excursion
          (when (re-search-backward mk nil t)
            (setq page (string-to-number (match-string 1)))))
        page))))

(defun diogenes-tgl--build-v5-column-model (file)
  "Build volume V's TWO-PART piecewise column model from OCR FILE.
Volume V's index restarts its column numbering partway through (part 2,
detected by `diogenes-tgl--detect-column-restart', or pinned by
`diogenes-tgl-v5-part2-page').  The same printed column number then
denotes two different pages -- one in each part -- so a single model
cannot resolve it.  We therefore split the anchors at the restart page
and fit each part independently, returning

    (:v5 PART1-SEGMENTS PART2-SEGMENTS RESTART-PAGE PART1-FIRST-COLUMN)

where each PART is an ordinary (START-COLUMN . INTERCEPT) segment list,
and PART1-FIRST-COLUMN is the smallest column number actually printed
in part 1 (the first column of the main index proper -- part 1's model
extrapolates back to column 1, but the numbered index does not begin
until this column; the earlier columns are the volume's front matter,
including the anomalous roots).  When no restart is found the value
degrades to a plain one-part model list, so callers that ignore the
split still work."
  (let* ((anchors (diogenes-tgl--page-anchors file))
         (restart (or diogenes-tgl-v5-part2-page
                      (diogenes-tgl--detect-column-restart anchors))))
    (if (not restart)
        (diogenes-tgl--build-model-from-anchors anchors)
      (let* ((p1 (cl-remove-if (lambda (e) (>= (car e) restart)) anchors))
             (p2 (cl-remove-if (lambda (e) (<  (car e) restart)) anchors))
             ;; The index PROPER begins at the "INDEX IN" marker page; the
             ;; columns printed on earlier part-1 pages belong to the front
             ;; matter (dialects, anomalous roots, Herodian) and must not be
             ;; counted.  So part 1's first index column is the smallest
             ;; column among anchors at or after that marker page.
             (index-page (diogenes-tgl--index-marker-page file))
             (index-anchors (if index-page
                                (cl-remove-if (lambda (e) (< (car e) index-page)) p1)
                              p1))
             (p1-first (when index-anchors
                         (apply #'min (mapcar #'cdr index-anchors)))))
        (list :v5
              (diogenes-tgl--build-model-from-anchors p1)
              (diogenes-tgl--build-model-from-anchors p2)
              restart
              p1-first)))))

(defun diogenes-tgl--v5-part1-first-column (model)
  "Return part 1's first printed index column from a `:v5' MODEL, or nil.
This is the smallest column number that actually appears in the main
index (part 1); columns below it belong to volume V's front matter, not
to the index proper.  Returns nil for a non-`:v5' MODEL."
  (when (and (consp model) (eq (car model) :v5))
    (nth 4 model)))

;;;; --------------------------------------------------------------------
;;;; VOLUME V "ANOMALOUS ROOTS"  (VERBORVM QVORVNDAM THEMATA, pp. 53-114)
;;;; --------------------------------------------------------------------

;; Volume V opens (after the dialects appendix) with a section of
;; ANOMALOUS/POETIC VERB FORMS -- "Verborum quorundam themata, quae magna
;; ex parte vel sunt anomala, vel poetica" -- capital-initial Greek lemmas
;; (Αγωνιουμαι, Ακαχιας, ...) explained in Latin.  Words there are often
;; absent from the four dictionary volumes and from the main index, so we
;; harvest them as an EXACT-match fall-back for `diogenes-tgl--locate', and
;; expose an approximate jump for the in-PDF `C-u L' menu.
;;
;; The section's running header is a SINGLE letter (A, E, K, ... Ω), so it
;; can route a query only to the right letter's pages (COARSE); to place a
;; multi-letter fragment we then scan the actual entry headwords on those
;; pages (FINE).  The section continues part 1's column numbering, so its
;; pages are reached with the ordinary part-1 column model.

(defconst diogenes-tgl--anomalous-start-regexp "VERBOR"
  "Substring marking the first page of volume V's anomalous-roots section
\(the Latin heading \"VERBORVM QVORVNDAM THEMATA\").")

(defconst diogenes-tgl--anomalous-end-regexp "\u0397\u03a1\u03a9\u0394\u0399\u0391\u039d\\|\u03a1\u03a9\u0394\u0399\u0391\u039d"
  "Regexp marking the first page AFTER the section: the Herodian treatise
\(ΗΡΩΔΙΑΝΟΥ ΠΕΡΙ ... ΑΡΙΘΜΟΥ); the second alternative tolerates a
mis-OCR'd initial eta.")

(defvar diogenes-tgl--anomalous-cache (make-hash-table :test 'equal)
  "Cache mapping volume V's OCR cache-key to its anomalous-roots structure.
The value is a plist (:region (START . END) :letter-pages HASH
:entries HASH :pages VEC), where :letter-pages maps a Greek letter to
the sorted list of its PDF pages, :entries maps an entry collation key
to its PDF page, and :pages is a vector of (PDF-PAGE . KEYVEC) in page
order for the fine positional scan.")

(defun diogenes-tgl--anomalous-single-letter-header (body-lines)
  "Return the single Greek CAPITAL letter heading BODY-LINES, or nil.
Scans the first few lines for one that is exactly one Greek capital."
  (let ((case-fold-search nil) (found nil) (n 0))
    (while (and body-lines (< n 6) (not found))
      (let ((s (string-trim (car body-lines))))
        (when (and (= (length s) 1)
                   (string-match-p
                    (concat "[" diogenes-tgl--greek-capital-class "]") s))
          (setq found (aref (diogenes-montanari--greek-key s) 0))))
      (setq body-lines (cdr body-lines) n (1+ n)))
    found))

(defun diogenes-tgl--build-anomalous (file)
  "Build volume V's anomalous-roots structure from OCR FILE (see the cache).
Detects the section (VERBOR ... Herodian), then for each page in it
records its single-letter header, the entry headwords on it, and adds
each entry to the key->page map."
  (let ((case-fold-search nil)
        (start nil) (end nil)
        (letter-pages (make-hash-table :test 'eql))
        (entries (make-hash-table :test 'equal))
        (pages nil))
    (with-temp-buffer
      (insert-file-contents file)
      (goto-char (point-min))
      (let ((marker diogenes-tgl-page-marker-regexp)
            (cur-pg nil) (cur-lines nil))
        (cl-flet ((flush ()
                    (when (and cur-pg start (null end)
                               (>= cur-pg start))
                      ;; within the section (end not yet reached): record page
                      (let* ((hdr (diogenes-tgl--anomalous-single-letter-header
                                   cur-lines))
                             (keys (diogenes-tgl--page-candidates
                                    (mapconcat #'identity cur-lines "\n"))))
                        (when hdr
                          (push cur-pg (gethash hdr letter-pages)))
                        (dolist (k keys)
                          (when (>= (length k) 2)
                            (unless (gethash k entries)
                              (puthash k cur-pg entries))))
                        (push (cons cur-pg (vconcat keys)) pages)))))
          (while (not (eobp))
            (let ((line (buffer-substring-no-properties
                         (line-beginning-position) (line-end-position))))
              (cond
               ((string-match marker line)
                (flush)
                (setq cur-pg (string-to-number (match-string 1 line))
                      cur-lines nil))
               (t
                ;; detect section start / end from this line
                (when (and (null start)
                           (string-match-p diogenes-tgl--anomalous-start-regexp
                                           line))
                  (setq start cur-pg))
                (when (and start (null end) cur-pg (> cur-pg start)
                           (let ((case-fold-search nil))
                             (string-match-p diogenes-tgl--anomalous-end-regexp
                                             line)))
                  (setq end (1- cur-pg)))
                (push line cur-lines))))
            (forward-line 1))
          ;; trailing page (only if still inside the section)
          (setq cur-lines (nreverse cur-lines))
          (flush))))
    (when start
      (let* ((pagevec (vconcat (nreverse pages)))
             ;; Per-page representative key: among the page's entries, the
             ;; median key sharing the page's MODAL first letter.  This
             ;; denoises stray cross-letter OCR fragments and yields an
             ;; alphabetically monotone (PAGE . REPR-KEY) sequence for
             ;; positioning a fragment (the single-letter running header is
             ;; too sparse to bound a letter's pages directly).
             (repr
              (delq nil
                    (mapcar
                     (lambda (cell)
                       (let* ((pg (car cell)) (keys (cdr cell)))
                         (when (> (length keys) 0)
                           (let ((counts (make-hash-table :test 'eql))
                                 (modal nil) (best 0))
                             (cl-loop for k across keys
                                      do (let ((c (aref k 0)))
                                           (puthash c (1+ (gethash c counts 0))
                                                    counts)))
                             (maphash (lambda (c n)
                                        (when (> n best) (setq modal c best n)))
                                      counts)
                             (let ((same (sort (cl-loop for k across keys
                                                        when (eql (aref k 0) modal)
                                                        collect k)
                                               #'string<)))
                               (when same
                                 (cons pg (nth (/ (length same) 2) same))))))))
                     pagevec))))
        (list :region (cons start (or end (+ start 61)))
              :letter-pages
              (let ((h (make-hash-table :test 'eql)))
                (maphash (lambda (k v) (puthash k (sort v #'<) h)) letter-pages)
                h)
              :entries entries
              :pages pagevec
              :repr repr)))))

(defun diogenes-tgl--anomalous ()
  "Return the (cached) anomalous-roots structure for volume V, or nil."
  (let ((file (ignore-errors (diogenes-tgl--volume-text 5))))
    (when file
      (let ((key (diogenes-tgl--file-cache-key file)))
        (or (gethash key diogenes-tgl--anomalous-cache)
            (setf (gethash key diogenes-tgl--anomalous-cache)
                  (diogenes-tgl--build-anomalous file)))))))

(defun diogenes-tgl--anomalous-locate-exact (key)
  "Return (5 . PDF-PAGE) if KEY is EXACTLY an anomalous-roots entry, else nil.
Exact-only by design: this is a last-ditch fall-back for words absent
everywhere else, and must never hijack a word that belongs elsewhere."
  (when (>= (length key) 2)
    (let ((a (diogenes-tgl--anomalous)))
      (when a
        (let ((pg (gethash key (plist-get a :entries))))
          (when pg
            (cons 5 (+ pg diogenes-tgl-page-offset))))))))

(defun diogenes-tgl--anomalous-approx (word)
  "Return (5 . PDF-PAGE) for WORD's APPROXIMATE position in the anomalous
roots, or nil.  Positions WORD in the section's alphabetically monotone
per-page representative-key sequence (`:repr'): the page holding the
greatest representative <= WORD's key.  A bare one-letter query lands
on the first page of that letter's run.  The single-letter running
header is too sparse to bound a letter directly, so we use the
representative sequence (modal-letter median key per page), which is
robust to stray cross-letter OCR fragments."
  (let ((a (diogenes-tgl--anomalous))
        (key (diogenes-montanari--greek-key word)))
    (when (and a (> (length key) 0))
      (let ((repr (plist-get a :repr))
            (L (aref key 0))
            (best nil) (first-of-letter nil))
        (when repr
          (cl-loop for cell in repr do
                   (let ((pg (car cell)) (rk (cdr cell)))
                     (when (and (> (length rk) 0) (eql (aref rk 0) L)
                                (null first-of-letter))
                       (setq first-of-letter pg))
                     (cond
                      ((not (string< key rk)) ; rk <= key
                       (setq best pg))
                      ;; stop once we are past the query's letter entirely
                      ((> (aref rk 0) L)
                       (cl-return)))))
          (let ((pg (cond
                     ((= (length key) 1) (or first-of-letter best
                                             (car (car repr))))
                     (best best)
                     (first-of-letter first-of-letter)
                     (t (car (car repr))))))
            (when pg (cons 5 (+ pg diogenes-tgl-page-offset)))))))))

(defun diogenes-tgl--column-model (file)
  "Return the (cached) piecewise slope-2 column model for volume OCR FILE.
For volume V (whose index restarts its column numbering in part 2) the
value is a two-part model tagged `:v5' (see
`diogenes-tgl--build-v5-column-model'); for every other volume it is a
plain (START-COLUMN . INTERCEPT) segment list.  See
`diogenes-tgl--build-column-model' and `diogenes-tgl--colmodel-cache'."
  (let ((key (diogenes-tgl--file-cache-key file)))
    (or (gethash key diogenes-tgl--colmodel-cache)
        (setf (gethash key diogenes-tgl--colmodel-cache)
              (let ((v5 (ignore-errors (diogenes-tgl--volume-text 5))))
                (if (and v5 (equal (file-truename file) (file-truename v5)))
                    (diogenes-tgl--build-v5-column-model file)
                  (diogenes-tgl--build-column-model file)))))))

(defun diogenes-tgl--column-to-page (column model &optional part)
  "Map printed COLUMN to a PDF page using piecewise slope-2 MODEL.
MODEL is either a plain list of (START-COLUMN . INTERCEPT) segments, or
a volume-V two-part model `(:v5 PART1 PART2 RESTART-PAGE)'.  For the
two-part model PART selects which index part the COLUMN belongs to
\(1 or 2, default 1), since the same column number occurs in both.

Within the chosen segment list, the applicable segment is the last
whose START-COLUMN is <= COLUMN, and the two columns of a physical page
share it, so

    PDF page = floor((COLUMN - INTERCEPT) / 2).

Returns an integer PDF page, or nil if MODEL is empty."
  (let ((segs (if (and (consp model) (eq (car model) :v5))
                  (if (eql part 2) (nth 2 model) (nth 1 model))
                model)))
    (when segs
      (let ((b (cdr (car segs))))
        (dolist (seg segs)
          (when (<= (car seg) column) (setq b (cdr seg))))
        (let ((d (- column b)))
          ;; floor toward -infinity (Emacs `/' truncates toward zero)
          (if (>= d 0) (/ d 2) (- (/ (+ (- d) 1) 2))))))))

;;;; --------------------------------------------------------------------
;;;; THE INDEX  (volume V)  ->  word :  (VOLUME COLUMN LETTER)
;;;; --------------------------------------------------------------------

;; The index begins at a line containing "INDEX IN" and runs to the end
;; of volume V.  Each index line begins (at the left margin) with a
;; Greek headword; a line may carry several "word, reference" segments,
;; and a reference is  <volume-digit> <column-marker> <column> [<letter>]
;; in a variety of OCR spellings.  We attribute each reference to the
;; nearest Greek word preceding it on the line.

(defconst diogenes-tgl--index-marker "INDEX IN"
  "Substring marking the start of the index in volume V's OCR.")

(defconst diogenes-tgl--gword-regexp
  "['\u2019\u1ffe\u1fbf\u02bc\u0384`\u1fef]?\\([\u0386-\u03ce\u1f00-\u1fff]\\{2,\\}\\)"
  "Regexp matching a Greek word token (2+ Greek letters, optional breathing).")

(defconst diogenes-tgl--line-start-gword-regexp
  (concat "\\`[[:space:]]*" diogenes-tgl--gword-regexp)
  "Regexp matching a line that begins with a Greek word (an index line).")

(defconst diogenes-tgl--ref-regexp
  (concat
   "\\(?:t\\|\u03c4\\|1\\|i\\|l\\)?[[:space:]]*[.,]?[[:space:]]*"  ; 't'/'τ'/stray digit
   "\\([1-5]\\)[[:space:]]*[.,][[:space:]]*"                        ; volume digit  (grp 1)
   "\\(?:c\\|C\\|\u0441\\|\u03b5\\|e\\|o\\|0\\|G\\|6\\)"            ; column marker 'c'/misreads
   "[[:space:]]*[.,]?[[:space:]]*"
   "\\([0-9]\\{1,4\\}\\)"                                           ; column number (grp 2)
   "[[:space:]]*[.,]?[[:space:]]*\\([a-hA-H]\\)?")                  ; section letter (grp 3, opt)
  "Regexp extracting a (volume, column, letter) reference from index text.
Group 1 is the tomus digit, group 2 the printed column, group 3 the
optional section letter.  Deliberately liberal about the OCR
spelling of the \"t.\" and \"c.\" markers and their separators.")

(defconst diogenes-tgl--xref-regexp "vide\\|habes\\|Anomal"
  "Regexp (case-insensitive) marking an index line as a cross-reference.
Note: \"ibidem\" is NOT here -- it is resolved to the previous entry's
column by `diogenes-tgl--ibidem-regexp', not treated as an unresolved
cross-reference.")

(defconst diogenes-tgl--ibidem-regexp
  "\\b\\(?:ibidem\\|ibid\\|ib\\)\\b\\.?"
  "Regexp (case-insensitive) matching an \"ibidem\" reference.
\"Ibidem\" (and its abbreviations ibid./ib.) means the word sits in the
SAME volume and column as the PREVIOUS explicitly-numbered entry; any
single letter after it (\",a\" ... \",f\") is the line within that
column, which we ignore since navigation is column-granular.  A whole
run of consecutive ibidem entries therefore all inherit the one last
explicit column.")

(defconst diogenes-tgl--vide-root-regexp
  (concat "vide\\(?:[[:space:]]*&\\)?[[:space:]]+\\(?:in[[:space:]]+\\)?"
          "['\u2019\u1ffe\u1fbf\u02bc\u0384`]?"
          "\\([\u0386-\u03ce\u1f00-\u1fff]\\{3,\\}\\)")
  "Regexp extracting the ROOT word a \"vide in <root>\" cross-reference points to.
Group 1 is the referenced root.  The TGL nests derived words under
their root (e.g. \\\"Αδενοειδής … vide in Αδήν\\\"), and such index lines
carry no column of their own; resolving the root then locates the
derivative.  Matched case-insensitively.")

(defconst diogenes-tgl--article-class
  (concat "\u1f41\u1f21\u03bf\u03c4\u1f40\u03cc"   ; ὁ ἡ ο τ ὀ ό
          "\u03ae\u1f74\u03b7\u1f26\u1f27")        ; ή ὴ η ἦ ἧ  (precomposed/accented)
  "Character class body (no brackets) of Greek article letters that close
a noun's apparatus (\", <gen>, <article>\").  Includes the precomposed
accented feminine ή (U+03AE) and eta variants, whose omission silently
dropped every \", εως, ή\" entry (e.g. Προαίρεσις) from the harvest.")

(defconst diogenes-tgl--index-entry-apparatus-regexp
  (let* ((noun (concat ",[[:space:]]*[\u03b1-\u03c9\u0386-\u03ce]\\{1,4\\}"
                       "[[:space:]]*,[[:space:]]*"
                       "[" diogenes-tgl--article-class "]"))
         (verb ",?[[:space:]]*[A-Z][a-z]\\{2,\\}o\\b"))
    (concat "\\`['\u2019\u1ffe\u1fbf\u02bc\u0384`]?"
            "[\u0386-\u03ce\u1f00-\u1fff]\\{3,\\}"
            "[[:space:]]*\\(?:" noun "\\|" verb "\\)"))
  "Regexp marking an index line that is itself a supplementary ENTRY.
Volume V's index is not only a finding-aid: many lines are their own
lemma entries, glossed from Hesychius and others (e.g. \"Ἄβλεμα,
ατος, τό, Erratum, Peccatum\"), for words that appear NOWHERE in the
four dictionary volumes.  Such a line carries entry apparatus right
after the headword -- a noun's genitive + article, or a verb's Latin
gloss ending in -o (first person) -- and, crucially, NO \"t.N c.M\"
back-reference.  This regexp matches that apparatus so those entries
can be harvested to their own volume-V page and used as a LAST-resort
lookup for words the main volumes do not contain.")

(defconst diogenes-tgl--index-sive-variant-regexp
  (let* ((cap (concat "\u0391-\u03a9\u1f08-\u1f0f\u1f18-\u1f1f\u1f28-\u1f2f"
                      "\u1f38-\u1f3f\u1f48-\u1f4f\u1f68-\u1f6f\u1fb8-\u1fbf"
                      "\u1fc8-\u1fcf\u1fd8-\u1fdf\u1fe8-\u1fef\u1ff8-\u1fff"))
         (tail "\u0386-\u03ce\u1f00-\u1fff\u0384\u0301\u0300\u0342\u0308\u0313\u0314"))
    (concat "\\b\\(?:s[iı]ue\\|\u017fiue\\|fiue\\|fiiue\\|feu\\|seu\\)\\b"
            "[[:space:],]*"
            "['\u2019\u1ffe\u1fbf\u02bc\u0384`]?"
            "\\([" cap "][" tail "]\\{3,\\}\\)"))
  "Regexp for an alternative spelling introduced by \"sive\"/\"seu\" (Latin \"or\").
An index entry often gives a second spelling of its headword after
\"sive\" (e.g. \"Ψίμμυθος, ſiue Ψίμυθος, Cerussa\"); group 1 is that
variant.  Estienne's long s makes \"ſiue\" OCR as \"fiue\"/\"feu\", so
those forms are accepted too.  The variant must be CAPITAL-initial:
\"sive\" also introduces lowercase running-gloss forms (\"idem ac ψιας
fiue ψακάς\") that are NOT lemmata and must not be harvested.")

(defconst diogenes-tgl--index-amp-variant-regexp
  (let* ((cap (concat "\u0391-\u03a9\u1f08-\u1f0f\u1f18-\u1f1f\u1f28-\u1f2f"
                      "\u1f38-\u1f3f\u1f48-\u1f4f\u1f68-\u1f6f\u1fb8-\u1fbf"
                      "\u1fc8-\u1fcf\u1fd8-\u1fdf\u1fe8-\u1fef\u1ff8-\u1fff"))
         (tail "\u0386-\u03ce\u1f00-\u1fff\u0384\u0301\u0300\u0342\u0308\u0313\u0314"))
    (concat "&[[:space:]]*"
            "['\u2019\u1ffe\u1fbf\u02bc\u0384`]?"
            "\\([" cap "][" tail "]\\{3,\\}\\)"))
  "Regexp for a word introduced by \"&\" on an index entry line; group 1 is it.
An index entry sometimes lists an alternative spelling of its headword
after \"&\" (e.g. \"Ἀγρουτήρ & Ἀγρουτής\", \"Αἰγάγριος & Αἴγαγρος\").
But \"&\" is also plain \"and\" joining two DIFFERENT glossed words
\(\"Ἄγρωσις … herba: & Ἄρτος … panis\").  The caller therefore keeps the
\"&\"-word only when it shares a real leading stem with the headword --
the mark of a spelling variant rather than a separate lemma.")

(defvar diogenes-tgl--index-cache (make-hash-table :test 'equal)
  "Cache mapping volume V's OCR cache-key to its parsed index.
The cached value is a plist (:refs H :xrefs H :buckets H :vide H
:entries H):
  :refs    key -> list of (VOLUME COLUMN LETTER);
  :xrefs   key -> raw cross-reference line;
  :buckets 2-letter-prefix -> list of keys with a column ref
           \(the search space for the fuzzy fallback);
  :vide    key -> ROOT key, for \"vide in <root>\" lines that carry no
           column of their own (a derived word nested under its root);
  :entries key -> volume-V PDF page, for supplementary index entries
           (glossed lemmata, absent from vols I-IV) -- a last-resort
           lookup landing on their page within volume V's index.")

(defun diogenes-tgl--word-positions (line)
  "Return a list of (POS . KEY) for Greek words in LINE, in order.
KEY is the accent-insensitive collation key of the word."
  (let ((out nil) (start 0))
    (while (string-match diogenes-tgl--gword-regexp line start)
      ;; Capture ALL match data up front: `diogenes-montanari--greek-key'
      ;; runs its own regexp matching and would otherwise clobber it
      ;; before we read `match-end', corrupting START.
      (let* ((pos (match-beginning 0))
             (raw (match-string 1 line))
             (end (match-end 0))
             (key (diogenes-montanari--greek-key raw)))
        (when (>= (length key) 2)
          (push (cons pos key) out))
        (setq start (max end (1+ start)))))
    (nreverse out)))

(defun diogenes-tgl--ref-positions (line)
  "Return a list of (POS VOLUME COLUMN LETTER) for references in LINE."
  (let ((out nil) (start 0))
    (while (string-match diogenes-tgl--ref-regexp line start)
      (let ((pos (match-beginning 0))
            (vol (string-to-number (match-string 1 line)))
            (col (string-to-number (match-string 2 line)))
            (letter (downcase (or (match-string 3 line) ""))))
        (when (and (>= col 1) (<= col 2000))
          (push (list pos vol col letter) out))
        (setq start (match-end 0)))) ; NB: --greek-key was not called, match-data intact
    (nreverse out)))

(defun diogenes-tgl--ibidem-positions (line)
  "Return a list of buffer POSITIONS of \"ibidem\" markers in LINE, in order.
Used to attribute the previous explicit column to the word each ibidem
follows (an ibidem may be the line's only reference, or a second
segment after an explicit one, e.g. \"Αβίασος, c.734. Αβιάσως, ibidem\")."
  (let ((out nil) (start 0) (case-fold-search t))
    (while (string-match diogenes-tgl--ibidem-regexp line start)
      (push (match-beginning 0) out)
      (setq start (match-end 0)))
    (nreverse out)))

(defun diogenes-tgl--ref-target-keys (line pos preceding)
  "Return the keys a reference at POS on LINE should be attributed to.
PRECEDING is the list of (WORD-POS . KEY) whose position is before POS,
in order.  Normally the target is just the nearest preceding word (the
last of PRECEDING).  But when the headword and one or more spelling
variants are joined by \"&\" and SHARE the one reference -- e.g.
\"Αβροκομάω, & Αβροκόμης, ibidem\" or \"Αβελτηρία & Αβελτερία, c.NNN\" --
every word in that trailing \"X & Y (& Z)\" group inherits it.  We walk
back from the nearest word while each earlier neighbour is joined to
the group by a \"&\" (with only Greek/space/punctuation between them)
and shares a leading stem of >=3 with it, mirroring the conservative
variant test used when harvesting \"&\" spellings."
  (if (null preceding)
      nil
    (let* ((rev (reverse preceding))          ; nearest word first
           (group (list (car rev)))
           (rest (cdr rev)))
      (cl-block walk
        (dolist (w rest)
          (let* ((cur (car group))            ; current earliest in group
                 (gap (substring line
                                 (min (length line) (car w))
                                 (min (length line) (car cur)))))
            ;; The gap between this earlier word and the group's current
            ;; earliest must contain a "&" and nothing but Greek letters,
            ;; spaces and punctuation (no other lemma text), and the two
            ;; must share a real leading stem.
            (if (and (string-match-p "&" gap)
                     (>= (diogenes-tgl--shared-stem (cdr w) (cdr cur)) 3))
                (push w group)
              (cl-return-from walk)))))
      (mapcar #'cdr group))))

(defun diogenes-tgl--parse-index (file)
  "Parse volume V OCR FILE and return the index plist (see cache doc)."
  (let ((refs (make-hash-table :test 'equal))
        (xrefs (make-hash-table :test 'equal))
        (buckets (make-hash-table :test 'equal))
        (vide (make-hash-table :test 'equal))
        (entries (make-hash-table :test 'equal))
        (last-ref nil)                  ; last explicit (VOLUME . COLUMN), for ibidem
        (pdfp nil))
    (with-temp-buffer
      (insert-file-contents file)
      (goto-char (point-min))
      ;; Jump to the index proper.
      (when (search-forward diogenes-tgl--index-marker nil t)
        (forward-line 1))
      (while (not (eobp))
        (let ((line (buffer-substring-no-properties
                     (line-beginning-position) (line-end-position))))
          (if (string-match diogenes-tgl-page-marker-regexp line)
              (setq pdfp (string-to-number (match-string 1 line)))
           (progn
            ;; Harvest alternative spellings of this line's headword FIRST --
            ;; capturing the variant strings before `--greek-key' (below)
            ;; clobbers the match data -- and file each as an entry on the
            ;; current page.  Two connectives introduce them: "sive" (Latin
            ;; "or", incl. its long-s OCR "fiue"), whose Capital-Greek word is
            ;; always a spelling variant (e.g. Ψίμυθος beside Ψίμμυθος); and
            ;; "&", whose Capital-Greek word is a variant ONLY when it shares a
            ;; leading stem with the headword (e.g. Ἀγρουτήρ & Ἀγρουτής) --
            ;; otherwise "&" is plain "and" joining a DIFFERENT lemma, which we
            ;; must not misfile.
            (when pdfp
              (let ((start 0) (variants nil) (head nil))
                ;; the line's own headword (for the "&" stem test)
                (when (string-match diogenes-tgl--line-start-gword-regexp line)
                  (setq head (diogenes-montanari--greek-key
                              (match-string 1 line))))
                ;; sive variants: always kept
                (setq start 0)
                (while (string-match diogenes-tgl--index-sive-variant-regexp
                                     line start)
                  (push (match-string 1 line) variants)
                  (setq start (match-end 1)))
                ;; "&" variants: kept only if stem-sharing with the headword
                (setq start 0)
                (while (string-match diogenes-tgl--index-amp-variant-regexp
                                     line start)
                  (let* ((w (match-string 1 line))
                         (end (match-end 1))
                         (wk (diogenes-montanari--greek-key w)))
                    (when (and head
                               (>= (diogenes-tgl--shared-stem head wk) 3))
                      (push w variants))
                    (setq start end)))
                (dolist (v variants)
                  (let ((vk (diogenes-montanari--greek-key v)))
                    (when (and (>= (length vk) 4) (not (gethash vk entries)))
                      (puthash vk pdfp entries))))))
            (when (string-match diogenes-tgl--line-start-gword-regexp line)
            ;; NB: collect ref positions BEFORE word positions, because
            ;; `diogenes-montanari--greek-key' (used for words) runs its
            ;; own regexp matching; doing refs first keeps things clean.
            (let* ((rpos (diogenes-tgl--ref-positions line))
                   (ibpos (diogenes-tgl--ibidem-positions line))
                   (wpos (diogenes-tgl--word-positions line))
                   ;; Merge explicit refs and ibidem markers into one
                   ;; position-ordered event list.  An explicit ref is
                   ;; (POS :ref VOL COL LETTER); an ibidem is (POS :ib).
                   ;; Walking left-to-right, an explicit ref sets `last-ref'
                   ;; and an ibidem reuses it -- so a second segment on the
                   ;; same line, and a run of ibidem lines, both inherit the
                   ;; most recent explicit column.
                   (events
                    (sort (append
                           (mapcar (lambda (r)
                                     (list (nth 0 r) :ref
                                           (nth 1 r) (nth 2 r) (nth 3 r)))
                                   rpos)
                           (mapcar (lambda (p) (list p :ib)) ibpos))
                          (lambda (a b) (< (car a) (car b))))))
              (cond
               ((and events wpos)
                (dolist (ev events)
                  (let* ((pos (nth 0 ev)) (kind (nth 1 ev))
                         (preceding (cl-remove-if-not
                                     (lambda (w) (< (car w) pos)) wpos)))
                    (pcase kind
                      (:ref
                       (let ((vol (nth 2 ev)) (col (nth 3 ev)) (letter (nth 4 ev)))
                         (setq last-ref (cons vol col))
                         (dolist (key (diogenes-tgl--ref-target-keys
                                       line pos preceding))
                           (let ((rec (list vol col letter))
                                 (cur (gethash key refs)))
                             (unless (member rec cur)
                               (puthash key (cons rec cur) refs))))))
                      (:ib
                       ;; "ibidem": inherit the last explicit (vol . col);
                       ;; the trailing line-letter is ignored.  Attributed to
                       ;; the whole "X & Y" variant group, so both a headword
                       ;; and its &-variant inherit the column.
                       (when last-ref
                         (dolist (key (diogenes-tgl--ref-target-keys
                                       line pos preceding))
                           (let ((rec (list (car last-ref) (cdr last-ref) ""))
                                 (cur (gethash key refs)))
                             (unless (member rec cur)
                               (puthash key (cons rec cur) refs))))))))))
               (wpos
                ;; No column on this line: record a cross-reference for
                ;; word 1, and -- if it is a "vide in <root>" -- the root
                ;; to resolve the (nested) headword through.  If instead it
                ;; is a supplementary ENTRY (apparatus, no reference), record
                ;; its volume-V page.
                (let ((key (cdr (car wpos))))
                  (when (>= (length key) 2)
                    (let ((case-fold-search t))
                      (cond
                       ((string-match-p diogenes-tgl--xref-regexp line)
                        (unless (gethash key xrefs)
                          (puthash key (string-trim line) xrefs))
                        (when (and (not (gethash key vide))
                                   (string-match diogenes-tgl--vide-root-regexp line))
                          (let* ((raw (match-string 1 line))
                                 (root (diogenes-montanari--greek-key raw)))
                            (when (and (>= (length root) 2)
                                       (not (string= root key)))
                              (puthash key root vide)))))
                       ((and pdfp
                             (>= (length key) 3)
                             (not (gethash key entries))
                             (let ((case-fold-search nil))
                               (string-match-p
                                diogenes-tgl--index-entry-apparatus-regexp
                                (string-trim line))))
                        (puthash key pdfp entries))))))))))))
            )
        (forward-line 1)))
    ;; Reverse each ref list (we pushed) and build fuzzy buckets over
    ;; ONLY the keys that carry a column ref (the resolvable targets).
    (maphash (lambda (k v)
               (puthash k (nreverse v) refs)
               (let ((p (substring k 0 (min 2 (length k)))))
                 (puthash p (cons k (gethash p buckets)) buckets)))
             refs)
    (list :refs refs :xrefs xrefs :buckets buckets :vide vide
          :entries entries)))

(defun diogenes-tgl--index (&optional file)
  "Return the (cached) parsed index of volume V.
FILE is volume V's OCR text; when omitted it is discovered from
`diogenes-tgl-directory'."
  (let ((file (or file (diogenes-tgl--volume-text 5))))
    (unless file
      (user-error "TGL volume V (the index) was not found under %s"
                  (and diogenes-tgl-directory
                       (abbreviate-file-name diogenes-tgl-directory))))
    (let ((key (diogenes-tgl--file-cache-key file)))
      (or (gethash key diogenes-tgl--index-cache)
          (setf (gethash key diogenes-tgl--index-cache)
                (diogenes-tgl--parse-index file))))))

;;;; --------------------------------------------------------------------
;;;; FUZZY KEY MATCHING  (recover single-letter OCR damage)
;;;; --------------------------------------------------------------------

(defun diogenes-tgl--edit1-p (a b)
  "Non-nil if strings A and B are equal or one edit (ins/del/sub) apart."
  (let ((la (length a)) (lb (length b)))
    (cond
     ((string= a b) t)
     ((> (abs (- la lb)) 1) nil)
     ((= la lb)                          ; single substitution
      (let ((diff 0) (i 0))
        (while (and (< i la) (<= diff 1))
          (unless (eq (aref a i) (aref b i)) (setq diff (1+ diff)))
          (setq i (1+ i)))
        (= diff 1)))
     (t                                  ; single insertion/deletion
      (when (> la lb) (cl-rotatef a b) (cl-rotatef la lb))
      (let ((i 0) (j 0) (diff 0))
        (while (and (< i la) (< j lb))
          (if (eq (aref a i) (aref b j))
              (progn (setq i (1+ i)) (setq j (1+ j)))
            (setq diff (1+ diff)) (setq j (1+ j))
            (when (> diff 1) (setq i la j lb))))
        (<= diff 1))))))

(defun diogenes-tgl--shared-stem (a b)
  "Length of the common leading run of strings A and B."
  (let ((n 0) (m (min (length a) (length b))))
    (while (and (< n m) (eq (aref a n) (aref b n))) (setq n (1+ n)))
    n))

(defun diogenes-tgl--neighbour-correct (key prev next)
  "Return an OCR-corrected form of KEY suggested by neighbours PREV and NEXT, or nil.
When a harvested headword key sits between two entries that share a
leading stem KEY does not, and a single-edit fix to KEY's opening
restores that stem, KEY was almost certainly OCR-garbled at that
letter (e.g. Αζαθοποιέω between αγαθο- entries -> ἀγαθοποιέω, ζ misread
for γ).  The correction is returned only when it is within one edit of
KEY, so it is conservative; the caller stores the corrected key IN
ADDITION to the original, and only when it is not already a known
entry, so a legitimate different word is never overwritten.  Returns
nil when KEY already fits its neighbours or no safe correction exists."
  (when (and (>= (length key) 4) (>= (length prev) 4) (>= (length next) 4))
    (let ((base (diogenes-tgl--shared-stem prev next)))
      ;; Neighbours must agree on a real stem that KEY conspicuously lacks.
      (when (and (>= base 4)
                 (< (max (diogenes-tgl--shared-stem key prev)
                         (diogenes-tgl--shared-stem key next))
                    (1- base)))
        (let* ((stem (substring prev 0 base))
               (cand (when (> (length key) base)
                       (concat stem (substring key base)))))
          (when (and cand
                     (not (string= cand key))
                     (diogenes-tgl--edit1-p key cand))
            cand))))))

(defun diogenes-tgl--fuzzy-key (key index)
  "Return an index key within one edit of KEY, or nil.
Searches only the bucket of keys sharing KEY's first two letters, so
the scan is cheap."
  (when (and diogenes-tgl-fuzzy-lookup (>= (length key) 2))
    (let* ((buckets (plist-get index :buckets))
           (cands (gethash (substring key 0 2) buckets)))
      (cl-find-if (lambda (c) (diogenes-tgl--edit1-p key c)) cands))))

;;;; --------------------------------------------------------------------
;;;; VOLUME DISCOVERY  (parent folder -> {tomus: dir, pdf, txt})
;;;; --------------------------------------------------------------------

(defvar diogenes-tgl--volumes-cache (make-hash-table :test 'equal)
  "Cache mapping the parent-directory signature to its volume table.
The value is an alist (TOMUS . PLIST) where PLIST has :dir :pdf :txt.")

(defun diogenes-tgl--dir-signature (parent)
  "Return a cache signature for PARENT (its sub-dirs + their mtimes)."
  (let ((subs (seq-filter #'file-directory-p
                          (directory-files parent t "\\`[^.]" t)))
        (sig nil))
    (dolist (d (sort subs #'string<))
      (push (cons d (file-attribute-modification-time (file-attributes d))) sig))
    (cons (file-truename parent) sig)))

(defun diogenes-tgl--first-file (dir regexp)
  "Return the first file in DIR matching REGEXP, or nil."
  (car (sort (seq-filter (lambda (f) (string-match-p regexp f))
                         (directory-files dir t nil t))
             #'string<)))

(defun diogenes-tgl--scan-volumes (parent)
  "Scan PARENT for volume sub-directories, returning an alist (TOMUS . PLIST).
Each PLIST has :dir, :pdf (may be nil) and :txt (may be nil).  A
sub-directory whose name is not a recognised Roman numeral is
ignored.  Signals a user-error if no volume folder is found."
  (let ((subs (seq-filter #'file-directory-p
                          (directory-files parent t "\\`[^.]" t)))
        (out nil))
    (dolist (d subs)
      (let ((tomus (diogenes-tgl--folder-tomus (file-name-nondirectory
                                                (directory-file-name d)))))
        (when tomus
          (push (cons tomus
                      (list :dir d
                            :pdf (diogenes-tgl--first-file d diogenes-tgl-pdf-regexp)
                            :txt (diogenes-tgl--first-file d diogenes-tgl-text-regexp)))
                out))))
    (unless out
      (user-error "No TGL volume folders (I, II, III, IIII, V) found under %s"
                  (abbreviate-file-name parent)))
    (sort out (lambda (a b) (< (car a) (car b))))))

(defun diogenes-tgl--volumes ()
  "Return the (cached) volume table for `diogenes-tgl-directory'."
  (let ((parent diogenes-tgl-directory))
    (unless parent
      (diogenes--require-path parent 'diogenes-tgl-directory
                              "The Thesaurus Graecae Linguae" 'directory))
    (setq parent (file-name-as-directory (expand-file-name parent)))
    (let ((key (diogenes-tgl--dir-signature parent)))
      (or (gethash key diogenes-tgl--volumes-cache)
          (setf (gethash key diogenes-tgl--volumes-cache)
                (diogenes-tgl--scan-volumes parent))))))

(defun diogenes-tgl--volume (tomus)
  "Return the PLIST (:dir :pdf :txt) for TOMUS, or nil if not installed."
  (cdr (assq tomus (diogenes-tgl--volumes))))

(defun diogenes-tgl--volume-pdf (tomus)
  "Return the PDF path for TOMUS, or nil."
  (plist-get (diogenes-tgl--volume tomus) :pdf))

(defun diogenes-tgl--volume-text (tomus)
  "Return the OCR text path for TOMUS, or nil."
  (plist-get (diogenes-tgl--volume tomus) :txt))

;;;; --------------------------------------------------------------------
;;;; BODY FALLBACK  (scan a volume's OCR for a left-margin entry)
;;;; --------------------------------------------------------------------

;; When the index has no column for a word, we locate it the Passow way:
;; find the volume covering its initial letter, then the page whose
;; left-margin entries bracket it.  A page's entry headwords are the
;; longest non-decreasing run of left-margin Greek words on it (OCR
;; fragments and quoted Greek break the alphabetical order and drop
;; out).  This reaches sub-lemmata too, because they ARE printed at the
;; left margin (only with a single leading capital rather than in full
;; caps).

(defconst diogenes-tgl--entry-regexp
  (concat "\\`['\u2019\u1ffe\u1fbf\u02bc\u0384`]?"
          "\\([\u0386-\u03ce\u1f00-\u1fff]\\{2,\\}\\)"
          "[[:space:]]*[,(\u00b7.]")
  "Regexp matching a left-margin TGL entry headword; group 1 is the word.
Matches both the full-caps root entries and the capital-initial
sub-entries, since both begin a line and are followed by a comma,
parenthesis, middle dot or period.")

(defconst diogenes-tgl--entry-or-compound-regexp
  (concat "\\`\\(?:C\\.[[:space:]]*\\)?"
          "['\u2019\u1ffe\u1fbf\u02bc\u0384`]?"
          "\\([\u0386-\u03ce\u1f00-\u1fff]\\{2,\\}\\)"
          "[[:space:]]*[,(\u00b7.]")
  "Like `diogenes-tgl--entry-regexp' but also accepts a leading \"C.\".
Group 1 is the headword whether or not the compound marker is present,
so a neighbour-aware scan can treat compound and ordinary entries in a
single sweep.")

(defun diogenes-tgl--page-candidates (body)
  "Return (HEADWORD-KEY ...) for entry-like left-margin lines in BODY, in order."
  (let ((case-fold-search nil) out)
    (dolist (line (split-string body "\n"))
      (when (string-match diogenes-tgl--entry-regexp line)
        (let ((k (diogenes-montanari--greek-key (match-string 1 line))))
          (when (>= (length k) 2) (push k out)))))
    (nreverse out)))

;; The MAIN (root) entries are printed in FULL CAPITALS at the left
;; margin; a caps headword is, by definition, the FIRST line of its
;; article, so its page is the authoritative opening of the entry --
;; strictly better than an index column, which for a long root often
;; points into the middle of the article (e.g. the index sends ἔχω to a
;; column ~11 pages past ΕΧΩ's opening).  We therefore record, per
;; volume, the first PDF page on which each all-caps headword appears,
;; and consult it before the index.
(defconst diogenes-tgl--greek-capital-class
  (concat "\u0391-\u03a9"          ; base capitals Α–Ω
          "\u1f08-\u1f0f"          ; Ἀ.. (alpha with breathings)
          "\u1f18-\u1f1d"          ; Ἐ..
          "\u1f28-\u1f2f"          ; Ἠ..
          "\u1f38-\u1f3f"          ; Ἰ..
          "\u1f48-\u1f4d"          ; Ὀ..
          "\u1f59\u1f5b\u1f5d\u1f5f" ; Ὑ.. (only odd points are capital)
          "\u1f68-\u1f6f"          ; Ὠ..
          "\u1fb8-\u1fbc"          ; Ᾰ Ᾱ Ὰ Ά ᾼ
          "\u1fc8-\u1fcc"          ; Ὲ Έ Ὴ Ή ῌ
          "\u1fd8-\u1fdb"          ; Ῐ Ῑ Ὶ Ί
          "\u1fe8-\u1fec"          ; Ῠ Ῡ Ὺ Ύ Ῥ
          "\u1ff8-\u1ffc")         ; Ὸ Ό Ὼ Ώ ῼ
  "Character-class body (for use inside \"[...]\") of Greek CAPITAL letters.
Covers the base block Α–Ω plus ONLY the capital code points of the
Greek Extended block.  The naive range \\u1f08-\\u1fdb must NOT be used:
Greek Extended interleaves case, so that range wrongly admits ~100
LOWERCASE letters (ἐ ἠ ἰ ἵ …); capturing those made
`diogenes-tgl--all-caps-p' reject every headword and left the caps map
empty.  This class contains capitals only, so a captured headword is
genuinely all-caps.")

(defconst diogenes-tgl--caps-entry-regexp
  (concat "\\`['\u2019\u1ffe\u1fbf\u02bc\u0384`]?"
          "\\([" diogenes-tgl--greek-capital-class "]\\{3,\\}\\)"
          "[[:space:]]*[,(\u00b7.]")
  "Regexp matching a left-margin ALL-CAPS (root) entry; group 1 is the word.
Restricted to Greek CAPITAL letters (base Α–Ω plus the capital-only
Greek-Extended points, via `diogenes-tgl--greek-capital-class') so it
matches root headwords like ΛΑΜΒΑΝΩ but never captures the lowercase
continuation of a capital-initial sub-entry.")

(defconst diogenes-tgl--caps-head-lemma-regexp
  (concat "\\`['\u2019\u1ffe\u1fbf\u02bc\u0384`]?"
          "\\([" diogenes-tgl--greek-capital-class "]\\{3,\\}\\)"
          "[[:space:]]+"
          "['\u2019\u1ffe\u1fbf\u02bc\u0384`]?"
          "\\([\u03b1-\u03c9\u1f00-\u1f7d\u1f80-\u1fb4\u1fb6\u1fb7\u1fc2-\u1fc4\u1fc6\u1fc7\u1fd0-\u1fd3\u1fd6\u1fd7\u1fe0-\u1fe7\u1ff2-\u1ff4\u1ff6\u1ff7]\\{2,\\}\\)")
  "Regexp matching a ROOT head printed in caps then repeated lower-case.
An Estienne root article often opens with its headword ALL-CAPS,
immediately followed by the same word in lower case with the
definition, e.g. `ΑΥΤΟΣ αὐτό, αὐτό (pronomen) Ipse...'.  The plain
`diogenes-tgl--caps-entry-regexp' misses this because a space and a
lower-case letter, not punctuation, follow the caps word.  Group 1 is
the caps head; group 2 the lower-case lemma that follows it.  Used by
the caps harvester as a second way to detect a root opening.")

(defconst diogenes-tgl--lc-headword-regexp
  (concat "^['\u2019\u1ffe\u1fbf\u02bc\u0384`]?"
          "\\(\\(?:[" diogenes-tgl--greek-capital-class "]\\)?"
          "[\u03b1-\u03c9\u1f00-\u1f7d\u1f80-\u1fb4\u1fb6\u1fb7\u1fc2-\u1fc4\u1fc6\u1fc7\u1fd0-\u1fd3\u1fd6\u1fd7\u1fe0-\u1fe7\u1ff2-\u1ff4\u1ff6\u1ff7]"
          "\\{3,\\}\\)")
  "Regexp matching a left-margin head whose body is lower-case Greek.
Allows an optional single leading capital (the ordinary way a headword
prints: capital initial, then lower case), so it captures the volume's
real headwords.  Group 1 is the word.  Used only to gather a volume's
own headword vocabulary, which validates leading-capital repairs in the
caps harvester (see `diogenes-tgl--parse-body').")

(defun diogenes-tgl--all-caps-p (s)
  "Non-nil if string S contains no lowercase Greek letter.
Binds `case-fold-search' to nil: with the user's default case-folding
on (as in a normal session), a lowercase class like [α-ω] would match
CAPITAL letters too, so every all-caps headword would be misjudged as
containing lowercase.  Tests the base lowercase block α–ω and the whole
lowercase span of the Greek Extended block so no accented lowercase
form slips past."
  (let ((case-fold-search nil))
    (not (string-match-p
          (concat "[\u03b1-\u03c9"
                  "\u1f00-\u1f07\u1f10-\u1f15\u1f20-\u1f27\u1f30-\u1f37"
                  "\u1f40-\u1f45\u1f50-\u1f57\u1f60-\u1f67\u1f70-\u1f7d"
                  "\u1f80-\u1f87\u1f90-\u1f97\u1fa0-\u1fa7\u1fb0-\u1fb4"
                  "\u1fb6-\u1fb7\u1fc2-\u1fc7\u1fd0-\u1fd3\u1fd6-\u1fd7"
                  "\u1fe0-\u1fe7\u1ff2-\u1ff7]")
          s))))

(defconst diogenes-tgl--derivation-marker-regexp
  "\\(?:\\(?:^\\|[ \t]\\)\\(?:ΕΤ\\|Ετ\\|ET\\|Et\\|VNDE\\|Vnde\\|UNDE\\|Unde\\)\\(?:[ \t]\\|$\\)\\|comp\\.\\)"
  "Regexp marking Estienne's derivation/cross-reference apparatus.
\"ΕΤ\"/\"Et\" (et), \"VNDE\"/\"Vnde\" (unde), and \"comp.\" introduce
forms DERIVED from or related to an article's headword.  A run of
these near an all-caps word (e.g. ΙΣΤΩΡ among Επιΐστωρ, Πολυΐστωρ,
Υποΐστωρ) signals that word is a derivative discussed inside another
article, not a root opening -- used together with a header-letter
mismatch to reject such false anchors (see `diogenes-tgl--parse-body').")

(defconst diogenes-tgl--running-header-regexp
  "^[ \t]*\\([\u0391-\u03a9]\\{2,5\\}\\)[ \t]*$"
  "Regexp matching a page's running-header token (a short ALL-CAPS line).
Estienne prints a 2-5 letter capital abbreviation of the current
article's headword (e.g. ΕΙΔ, ΙΣΤ, ΙΧΘ) on its own line near the top
of each page.  Group 1 is that token; its initial letter is the
authoritative letter the page belongs to -- far more reliable than the
OCR-garbled entry lines, which scatter across letters.")

(defun diogenes-tgl--header-letter (body)
  "Return the Greek initial letter of BODY's running header, or nil.
Scans the first few lines of a page BODY for a
`diogenes-tgl--running-header-regexp' token and returns the collation
initial of the first one found.  Used to reject all-caps sub-entries
whose letter is alien to the page they sit on (a derived form quoted
inside an unrelated article), which would otherwise be mistaken for a
root opening."
  (let ((case-fold-search nil) (lines (split-string body "\n")) (n 0) (letter nil))
    (while (and lines (< n 6) (not letter))
      (let ((l (car lines)))
        (when (string-match diogenes-tgl--running-header-regexp l)
          (let ((k (diogenes-montanari--greek-key (match-string 1 l))))
            (when (> (length k) 0) (setq letter (aref k 0)))))
        (setq lines (cdr lines) n (1+ n))))
    letter))

(defun diogenes-tgl--header-letter-loose (body)
  "Like `diogenes-tgl--header-letter' but tolerant of a broken header.
The OCR sometimes splits the running-header token into space-separated
pieces (e.g. `ΑΥ Γ ΑΥΤ' for the ΑΥΓ/ΑΥΤ header), which the strict
regexp -- anchored to one unbroken caps run -- misses, so
`diogenes-tgl--header-letter' returns nil there.  This variant also
accepts a line made up solely of capital-Greek runs and blanks and
returns the initial of its first letter.  It is used ONLY to validate a
leading-capital repair of a caps head (see `diogenes-tgl--parse-body');
the stricter `diogenes-tgl--header-letter' still governs the
alien-anchor rejection, so that rejection's behaviour is unchanged."
  (or (diogenes-tgl--header-letter body)
      (let ((case-fold-search nil) (lines (split-string body "\n"))
            (n 0) (letter nil))
        (while (and lines (< n 6) (not letter))
          (let ((l (car lines)))
            (when (string-match
                   "\\`[ \t]*[\u0391-\u03a9]\\(?:[ \t]*[\u0391-\u03a9]\\)+[ \t]*\\'"
                   l)
              (let ((k (diogenes-montanari--greek-key l)))
                (when (> (length k) 0) (setq letter (aref k 0)))))
            (setq lines (cdr lines) n (1+ n))))
        letter)))

(defun diogenes-tgl--monotone-backbone (keys)
  "Return the longest non-decreasing subsequence of KEYS (a list of strings).
Ties (equal keys) are kept.  This is the reconstructed column of real
entry headwords, OCR fragments being the order-violating outliers."
  (let ((n (length keys)))
    (if (zerop n)
        nil
      (let* ((vec (vconcat keys))
             (tails (make-vector n 0))
             (tails-len 0)
             (prev (make-vector n -1)))
        (dotimes (i n)
          (let ((k (aref vec i)) (lo 0) (hi tails-len))
            (while (< lo hi)
              (let ((mid (/ (+ lo hi) 2)))
                (if (string< k (aref vec (aref tails mid)))
                    (setq hi mid)
                  (setq lo (1+ mid)))))
            (aset prev i (if (> lo 0) (aref tails (1- lo)) -1))
            (aset tails lo i)
            (when (= lo tails-len) (setq tails-len (1+ tails-len)))))
        (let ((seq nil) (i (aref tails (1- tails-len))))
          (while (>= i 0)
            (push (aref vec i) seq)
            (setq i (aref prev i)))
          seq)))))

(defun diogenes-tgl--majority-first-letter (keys)
  "Return the Greek first letter heading most of KEYS (a list), or nil."
  (when keys
    (let ((counts (make-hash-table :test 'eql)) (best nil) (bestn 0))
      (dolist (k keys)
        (let ((c (aref k 0)))
          (puthash c (1+ (gethash c counts 0)) counts)))
      (maphash (lambda (c n) (when (> n bestn) (setq best c bestn n))) counts)
      best)))

;; Per-volume body index: pages, each (:page PDF :lo KEY :hi KEY :maj CH
;; :keys [k0 k1 ...]); plus a per-letter page-count histogram for routing.
(defvar diogenes-tgl--body-cache (make-hash-table :test 'equal)
  "Cache mapping a volume OCR cache-key to its parsed body page index.")

;; COMPOUND ("C.") ENTRIES.  Estienne prefixes a compound's headword line
;; with "C." (Compositum), e.g. "C. Ἀνακαθαίρω, Expurgo…".  These are
;; left-margin entries, so the line's page is the compound's own entry --
;; a genuine locator, not a mere mention.  Crucially the TGL files a
;; compound under its ROOT, which often lives in another volume than the
;; compound's initial letter routes to (περιαγγέλλω, π-initial, is filed
;; in tomus I under ἀγγέλλω) -- exactly the words the letter-routed body
;; scan misplaces.  Harvesting these gives a compound->page map covering
;; ~12000 entries, most of which the index cannot resolve (their index
;; headword is OCR-garbled).  Consulted after the exact index but before
;; the fuzzy/body fallbacks, so it never overrides a trusted index hit.
(defconst diogenes-tgl--compound-entry-regexp
  (concat "\\`C\\.[[:space:]]*"
          "['\u2019\u1ffe\u1fbf\u02bc\u0384`]?"
          "\\([\u0386-\u03ce\u1f00-\u1fff]\\{3,\\}\\)")
  "Regexp matching a compound entry line marked \"C.\"; group 1 is the word.
The leading \"C.\" is Estienne's abbreviation for /compositum/.")

(defvar diogenes-tgl--compound-cache (make-hash-table :test 'equal)
  "Cache mapping a volume OCR cache-key to its compound headword->page map.")

(defconst diogenes-tgl--caps-lookalike-map
  '((?A . ?α) (?B . ?β) (?E . ?ε) (?H . ?η) (?I . ?ι) (?K . ?κ)
    (?M . ?μ) (?N . ?ν) (?O . ?ο) (?P . ?ρ) (?T . ?τ) (?Y . ?υ)
    (?X . ?χ) (?Z . ?ζ))
  "Latin capital letters to the lower-case Greek they visually stand for.
Estienne prints a compound's prefix in capitals (e.g. ΔΙΑ, ΚΑΤΑ), which
the OCR often renders with Latin look-alikes (K for kappa, P for rho,
and so on).  Used by `diogenes-tgl--fold-caps-prefix' to read such a
prefix.")

(defun diogenes-tgl--fold-caps-prefix (token)
  "Fold a caps prefix TOKEN (Greek and/or Latin look-alike capitals) to a Greek key.
Greek capitals are collated normally; Latin capitals are mapped via
`diogenes-tgl--caps-lookalike-map'; accents/breathings and other
characters are dropped.  Returns the lower-case Greek key, or a string
containing a `?' placeholder for an unmappable letter (so it will not
accidentally match a real prefix)."
  (let ((out nil))
    (dolist (ch (append (ucs-normalize-NFD-string (or token "")) nil))
      (cond
       ((and (>= ch #x300) (<= ch #x36f)) nil)                 ; combining mark
       ((or (and (>= ch #x3b1) (<= ch #x3c9))
            (and (>= ch #x391) (<= ch #x3a9)))                 ; Greek letter
        (let ((c (downcase ch))) (push (if (= c ?ς) ?σ c) out)))
       ((assq ch diogenes-tgl--caps-lookalike-map)             ; Latin look-alike
        (push (cdr (assq ch diogenes-tgl--caps-lookalike-map)) out))
       ((or (and (>= ch ?A) (<= ch ?Z)) (and (>= ch ?a) (<= ch ?z)))
        (push ?? out))))                                       ; unmappable Latin
    (apply #'string (nreverse out))))

(defconst diogenes-tgl--compound-variant-connectors
  '("vel" "uel" "et" "and")
  "Latin connectors that introduce a variant spelling in a compound headword.
On a \"C.\" line the lemma may be followed by alternative spellings
\(voices/forms), each introduced by one of these or by `&'; the Latin
gloss then follows.  A bare comma, by contrast, usually introduces
grammatical apparatus (a genitive ending, articles), which is NOT a
variant.  Used by `diogenes-tgl--compound-headword-keys'.")

(defun diogenes-tgl--latin-word-p (token)
  "Non-nil if TOKEN is a Latin-script word (no Greek letters)."
  (and (string-match-p "[A-Za-z]" token)
       (not (string-match-p "[\u0386-\u03ce\u1f00-\u1fff]" token))))

(defun diogenes-tgl--greek-word-p (token)
  "Non-nil if TOKEN contains a Greek letter."
  (and (stringp token)
       (string-match-p "[\u0386-\u03ce\u1f00-\u1fff]" token)))

(defun diogenes-tgl--compound-headword-keys (line)
  "Return the collation keys of a \"C.\" compound LINE's headword region, or nil.
Parses the Greek headword region of a compound entry and returns a list
whose first element is the LEMMA and the rest its variant spellings.

The headword region is read per Estienne's layout: the lemma, then any
alternative spellings each introduced by a connector
\(`diogenes-tgl--compound-variant-connectors' or `&'), up to where the
Latin gloss begins (the first Latin-script word -- a verb in -o, or a
noun, etc.).  Two OCR-specific points are handled:

  * a SPLIT lemma whose capital prefix is separated from its root by a
    space (e.g. `C.ΔΙΑ πράσω') is rejoined -- across whitespace only,
    never across a comma; the prefix may be OCR'd in Latin look-alikes
    \(`KATA'), which are folded via `diogenes-tgl--fold-caps-prefix'
    when they spell a prepositional prefix; and
  * grammatical apparatus after a bare COMMA (a genitive ending like
    `ονος', the articles `ὁ ἡ τό') is skipped, NOT treated as a variant,
    so a noun entry yields only its lemma.

Returns nil when LINE is not a \"C.\" entry or no Greek lemma is found."
  (when (and (stringp line) (string-match "\\`C\\." line))
    (let* ((body (replace-regexp-in-string "\\`C\\.[[:space:]]*" "" line))
           (raw (split-string body "[[:space:]]+" t))
           (seq nil) (sep 'start))
      ;; tokenise, tracking the separator BEFORE each token: whitespace,
      ;; comma, `&', or a connector word (folded into the separator).
      (dolist (w raw)
        ;; peel leading punctuation
        (while (and (> (length w) 0) (memq (aref w 0) '(?, ?&)))
          (setq sep (if (eq (aref w 0) ?&) 'amp 'comma))
          (setq w (substring w 1)))
        ;; detach trailing commas/ampersands (they mark the NEXT separator)
        (let ((trail nil))
          (when (string-match "\\([,&]+\\)\\'" w)
            (setq trail (match-string 1 w))
            (setq w (substring w 0 (match-beginning 1))))
          (let ((low (downcase (string-trim-right w "\\."))))
            (cond
             ((member low diogenes-tgl--compound-variant-connectors)
              (setq sep 'conn))
             ((> (length w) 0)
              (push (cons sep w) seq)
              (setq sep 'ws))))
          (when trail
            (setq sep (if (string-match-p "&" trail) 'amp 'comma)))))
      (setq seq (nreverse seq))
      ;; walk the region
      (let ((lemma nil) (variants nil) (i 0) (n (length seq)))
        (while (< i n)
          (let* ((cell (nth i seq)) (s (car cell)) (tok (cdr cell))
                 (gtok (diogenes-tgl--greek-word-p tok)))
            (cond
             ((null lemma)
              (cond
               (gtok
                (setq lemma (diogenes-montanari--greek-key tok))
                ;; join a following whitespace-separated Greek token (split lemma)
                (let ((nx (nth (1+ i) seq)))
                  (when (and nx (eq (car nx) 'ws)
                             (diogenes-tgl--greek-word-p (cdr nx)))
                    (setq lemma (concat lemma (diogenes-montanari--greek-key (cdr nx))))
                    (setq i (1+ i)))))
               ((let ((fold (diogenes-tgl--fold-caps-prefix tok)))
                  (and (member fold diogenes-tgl--prepositional-prefixes)
                       ;; a Latin-caps prefix: join the following ws Greek root
                       (let ((nx (nth (1+ i) seq)))
                         (when (and nx (eq (car nx) 'ws)
                                    (diogenes-tgl--greek-word-p (cdr nx)))
                           (setq lemma (concat fold (diogenes-montanari--greek-key
                                                     (cdr nx))))
                           (setq i (1+ i))
                           t)))))
               (t (setq i n))))          ; Latin gloss -> stop (no lemma)
             (t
              (if (not gtok)
                  (setq i n)             ; Latin gloss -> region ends
                ;; a Greek form after the lemma is a VARIANT only if a
                ;; connector/`&' introduced it; comma-apparatus is skipped.
                (when (memq s '(conn amp))
                  (let ((k (diogenes-montanari--greek-key tok)))
                    (when (>= (length k) 4) (push k variants))))))))
          (setq i (1+ i)))
        (when lemma
          (cons lemma (nreverse variants)))))))

(defun diogenes-tgl--parse-compounds (file)
  "Scan volume OCR FILE and return a hash: compound key -> first PDF page.
Records the first page on which each \"C.\"-marked compound headword
appears.  When a compound's harvested headword is OCR-garbled in a way
its neighbours expose (see `diogenes-tgl--neighbour-correct'), the
corrected key is stored too -- but only if not already mapped -- so
the compound is findable under its true spelling as well as the
garbled one.  The index proper (volume V) is skipped."
  (let ((case-fold-search nil)
        (map (make-hash-table :test 'equal))
        ;; sliding window over ALL detected entries: (KEY PAGE COMPOUND-P)
        (prev nil) (cur nil) (pending nil))
    (cl-flet ((emit (entry)
                ;; ENTRY is the middle of the window; PREV and NEXT known.
                (when entry
                  (cl-destructuring-bind (k page isc &optional nextk) entry
                    (when (and isc (>= (length k) 4))
                      (unless (gethash k map) (puthash k page map))
                      ;; neighbour-correct using previous and next entry keys
                      (let* ((pk (and prev (car prev)))
                             (corr (and pk nextk
                                        (diogenes-tgl--neighbour-correct k pk nextk))))
                        (when (and corr (not (gethash corr map)))
                          (puthash corr page map))))))))
      (with-temp-buffer
        (insert-file-contents file)
        (goto-char (point-min))
        (let ((index-start
               (save-excursion
                 (if (search-forward diogenes-tgl--index-marker nil t)
                     (line-beginning-position)
                   (point-max))))
              (marker diogenes-tgl-page-marker-regexp)
              (pdfp nil))
          (goto-char (point-min))
          (while (and (not (eobp)) (< (point) index-start))
            (let ((line (buffer-substring-no-properties
                         (line-beginning-position) (line-end-position))))
              ;; A compound line whose headword the OCR split after its capital
              ;; prefix (e.g. "C.ΔΙΑ πράσω") is REJECTED by the entry gate below
              ;; (its terminator is a space + Greek root, not punctuation), so
              ;; harvest such lines here, independently: record the lemma and
              ;; every variant spelling (see `diogenes-tgl--compound-headword-keys').
              (when (and pdfp (string-match "\\`C\\." line))
                (let ((keys (diogenes-tgl--compound-headword-keys line)))
                  (dolist (sk keys)
                    (when (and (>= (length sk) 4) (not (gethash sk map)))
                      (puthash sk pdfp map)))))
              (cond
               ((string-match marker line)
                (setq pdfp (string-to-number (match-string 1 line))))
               ((and pdfp (string-match diogenes-tgl--entry-or-compound-regexp line))
                (let* ((k (diogenes-montanari--greek-key (match-string 1 line)))
                       (isc (string-match diogenes-tgl--compound-entry-regexp line)))
                  (when (>= (length k) 3)
                    ;; shift window: the previous CUR now has its NEXT (=k), emit it
                    (when cur
                      (emit (list (nth 0 cur) (nth 1 cur) (nth 2 cur) k))
                      (setq prev cur))
                    (setq cur (list k pdfp (and isc t))))))))
            (forward-line 1))
          ;; flush the final buffered entry (no next neighbour)
          (when cur (emit (list (nth 0 cur) (nth 1 cur) (nth 2 cur) nil))))))
    map))

(defun diogenes-tgl--compounds (tomus)
  "Return the (cached) compound headword->page map for TOMUS, or nil."
  (let ((file (diogenes-tgl--volume-text tomus)))
    (when file
      (let ((key (diogenes-tgl--file-cache-key file)))
        (or (gethash key diogenes-tgl--compound-cache)
            (setf (gethash key diogenes-tgl--compound-cache)
                  (diogenes-tgl--parse-compounds file)))))))

(defun diogenes-tgl--fuzzy-in-map (key map &optional accept)
  "Return a key of hash MAP within one edit of KEY (same first 2 letters), or nil.
When ACCEPT is non-nil it is called with each otherwise-matching candidate
key; only a candidate for which it returns non-nil is accepted (scanning
continues past rejected ones)."
  (when (>= (length key) 4)
    (let ((pre (substring key 0 2)) (hit nil))
      (catch 'found
        (maphash (lambda (k _v)
                   (when (and (>= (length k) 4)
                              (string= (substring k 0 2) pre)
                              (diogenes-tgl--edit1-p key k)
                              (or (null accept) (funcall accept k)))
                     (setq hit k) (throw 'found k)))
                 map))
      hit)))

(defun diogenes-tgl--compound-locate (key)
  "Return (TOMUS . PAGE) for KEY as a \"C.\"-marked compound, or nil.
Searches every volume (a compound is filed under its root, whose
volume need not match the compound's initial letter), exact match
first, then a 1-edit fuzzy match within each volume's compound map to
absorb single-letter OCR damage in the compound's own headword.  Takes
the first exact hit in volume order; only if no volume has an exact
hit does it accept the first fuzzy hit.

The fuzzy pass is constrained when KEY is a PREPOSITIONAL compound (see
`diogenes-tgl--prepositional-root-initials'): its root's initial letter
is then certain, so a fuzzy candidate whose own prepositional root
begins with a different letter is rejected -- this stops a one-letter
OCR wobble from matching a genuinely different compound a letter apart
\(e.g. διαπράσσω must not match διαφράσσω: root π vs φ).  When KEY has no
prepositional prefix the fuzzy pass is unconstrained, as before."
  (when (>= (length key) 4)
    (let* ((fuzzy nil)
           (allowed (diogenes-tgl--prepositional-root-initials key))
           (accept (when allowed
                     (lambda (cand)
                       (let ((ci (diogenes-tgl--prepositional-root-initials cand)))
                         ;; accept if the candidate is not a prepositional
                         ;; compound at all, or shares an allowed root initial
                         (or (null ci)
                             (cl-intersection ci allowed)))))))
      (or (cl-loop for tomus in '(1 2 3 4)
                   for map = (diogenes-tgl--compounds tomus)
                   for page = (and map (gethash key map))
                   when page return (cons tomus (+ page diogenes-tgl-page-offset))
                   ;; remember a fuzzy candidate for the fallback pass
                   do (when (and map (not fuzzy))
                        (let ((fk (diogenes-tgl--fuzzy-in-map key map accept)))
                          (when fk
                            (setq fuzzy (cons tomus (+ (gethash fk map)
                                                       diogenes-tgl-page-offset)))))))
          fuzzy))))

;; "VNDE"/"INDE" DERIVATIONS.  A residual class of words appears in the
;; TGL only as an explicit derivation inside a root's article, introduced
;; by "Vnde" (whence) or "Inde" -- e.g. under χαράσσω: "VNDE Ἐγχάραγμα,
;; ατος, τό, …  Ἐγχάραξις, εως, ή, …".  These are neither "C."-marked
;; compounds nor headwords the index carries, so nothing else can place
;; them; the "Vnde X" line is the only evidence X sits on that page.  We
;; harvest them, but STRICTLY, to avoid mistaking a quoted inflected form
;; for a lemma: the word must (a) start with a CAPITAL (Estienne
;; capitalises lemma initials) and (b) be followed by real entry
;; apparatus -- for a noun/adjective a genitive ending + article
;; (", ατος, τό" / ", εως, ή" / ", ου, ὁ"), or for a verb a Latin gloss,
;; whose citation form ends in -o (first person singular, e.g. "Scribo").
;; A bare "Vnde" + Greek with neither is a passing mention and is ignored.
(defconst diogenes-tgl--vnde-apparatus-word
  (let* ((cap (concat "\u0391-\u03a9\u1f08-\u1f0f\u1f18-\u1f1f\u1f28-\u1f2f"
                      "\u1f38-\u1f3f\u1f48-\u1f4f\u1f68-\u1f6f\u1fb8-\u1fbf"
                      "\u1fc8-\u1fcf\u1fd8-\u1fdf\u1fe8-\u1fef\u1ff8-\u1fff"))
         ;; word tail must include precomposed accented lowercase (U+0386-03ce)
         ;; as well as the polytonic block, or accented vowels truncate the word.
         (tail "\u0386-\u03ce\u1f00-\u1fff\u0384\u0301\u0300\u0342\u0308\u0313\u0314")
         (gkword (concat "['\u2019\u1ffe\u1fbf\u02bc\u0384`]?"
                         "\\([" cap "][" tail "]\\{2,\\}\\)"))
         ;; noun apparatus: , <gen 1-4 letters>, <article incl. accented ή>
         (noun (concat ",[[:space:]]*[\u03b1-\u03c9\u0386-\u03ce]\\{1,4\\}"
                       "[[:space:]]*,[[:space:]]*"
                       "[" diogenes-tgl--article-class "]"))
         ;; verb/other: a capitalised Latin gloss word ending in -o
         (verb ",?[[:space:]]*[A-Z][a-z]\\{2,\\}o\\b"))
    (concat gkword "[[:space:]]*\\(?:" noun "\\|" verb "\\)"))
  "Regexp for a capital-initial Greek lemma followed by real entry apparatus.
Group 1 is the word.  Apparatus is either a noun's genitive+article or
a verb's Latin -o gloss -- the part-of-speech-specific shape that
distinguishes a genuine derived lemma from a quoted inflected form.")

(defconst diogenes-tgl--vnde-regexp
  (concat "\\b[VUI]nde\\b[[:space:],]*" diogenes-tgl--vnde-apparatus-word)
  "Regexp matching a \"Vnde/Inde X\" derived-entry line; group 1 is the word.
Requires capital-initial X plus noun apparatus or a verb's Latin -o
gloss, so only genuine derived lemmata are captured.  Matched
case-insensitively (Estienne also prints the marker as \"VNDE\").")

(defconst diogenes-tgl--vnde-amp-regexp
  (concat "&[[:space:]]*" diogenes-tgl--vnde-apparatus-word)
  "Regexp matching a chained \"& Y\" continuation of a Vnde/Inde line.
A \"Vnde X … & Y\" line lists a second derived lemma Y after the
ampersand (e.g. \"VNDE Τηλαύγημα … & Τηλαύγησις, εως, ή\").  Group 1 is
Y.  The SAME apparatus discipline is required, so quoted phrases after
\"&\" (\"& τὰ ἀκραῖα\") or bare inflected forms (\"& Εξαπλῇ\") are ignored.")

(defvar diogenes-tgl--vnde-cache (make-hash-table :test 'equal)
  "Cache mapping a volume OCR cache-key to its Vnde/Inde derived-entry map.")

(defun diogenes-tgl--parse-vnde (file)
  "Scan volume OCR FILE and return a hash: Vnde/Inde-derived key -> first PDF page.
On each line, harvests the word after \"Vnde/Inde\" and ALSO every
chained \"& Y\" continuation on that line (same apparatus discipline),
so a line like \"VNDE Τηλαύγημα … & Τηλαύγησις, εως, ή\" contributes
both lemmata.  When a harvested key looks OCR-garbled relative to the
other lemmata on the same line (its co-derivatives, which share a
stem), the neighbour-corrected key is stored too, but only if not
already mapped.  The index proper (volume V) is skipped."
  (let ((map (make-hash-table :test 'equal))
        (case-fold-search t))
    (cl-flet ((store (k page)
                (when (and (>= (length k) 4) (not (gethash k map)))
                  (puthash k page map))))
      (with-temp-buffer
        (insert-file-contents file)
        (goto-char (point-min))
        (let ((index-start
               (save-excursion
                 (if (search-forward diogenes-tgl--index-marker nil t)
                     (line-beginning-position)
                   (point-max))))
              (marker diogenes-tgl-page-marker-regexp)
              (pdfp nil))
          (goto-char (point-min))
          (while (and (not (eobp)) (< (point) index-start))
            (let ((line (buffer-substring-no-properties
                         (line-beginning-position) (line-end-position))))
              (if (string-match marker line)
                  (setq pdfp (string-to-number (match-string 1 line)))
                (when (and pdfp (string-match diogenes-tgl--vnde-regexp line))
                  ;; Collect the head word, then every "& Y" continuation,
                  ;; in line order, so co-derivatives can correct each other.
                  (let ((words nil))
                    (push (diogenes-montanari--greek-key (match-string 1 line))
                          words)
                    (let ((start (match-end 0)))
                      (while (string-match diogenes-tgl--vnde-amp-regexp line start)
                        (push (diogenes-montanari--greek-key (match-string 1 line))
                              words)
                        (setq start (match-end 1))))
                    (setq words (nreverse words))
                    ;; store each, plus a neighbour-correction against the
                    ;; adjacent co-derivative(s) on the same line
                    (let ((n (length words)))
                      (dotimes (i n)
                        (let* ((k (nth i words))
                               (prev (and (> i 0) (nth (1- i) words)))
                               (next (and (< (1+ i) n) (nth (1+ i) words)))
                               (corr (and prev next
                                          (diogenes-tgl--neighbour-correct k prev next))))
                          (store k pdfp)
                          (when corr (store corr pdfp)))))))))
            (forward-line 1)))))
    map))

(defun diogenes-tgl--vnde (tomus)
  "Return the (cached) Vnde/Inde derived-entry map for TOMUS, or nil."
  (let ((file (diogenes-tgl--volume-text tomus)))
    (when file
      (let ((key (diogenes-tgl--file-cache-key file)))
        (or (gethash key diogenes-tgl--vnde-cache)
            (setf (gethash key diogenes-tgl--vnde-cache)
                  (diogenes-tgl--parse-vnde file)))))))

(defun diogenes-tgl--vnde-locate (key)
  "Return (TOMUS . PAGE) for KEY as a \"Vnde/Inde\"-derived entry, or nil.
Searches every volume (the derivation is filed under its root, whose
volume need not match KEY's initial letter), exact match first, then a
1-edit fuzzy match within a volume's map for single-letter OCR damage."
  (when (>= (length key) 4)
    (let ((fuzzy nil))
      (or (cl-loop for tomus in '(1 2 3 4)
                   for map = (diogenes-tgl--vnde tomus)
                   for page = (and map (gethash key map))
                   when page return (cons tomus (+ page diogenes-tgl-page-offset))
                   do (when (and map (not fuzzy))
                        (let ((fk (diogenes-tgl--fuzzy-in-map key map)))
                          (when fk
                            (setq fuzzy (cons tomus (+ (gethash fk map)
                                                       diogenes-tgl-page-offset)))))))
          fuzzy))))

;; COMPREHENSIVE ENTRY MAP.  The caps map records only ALL-CAPS root
;; headwords; the compound map only "C."-marked compounds; the index
;; only a subset of words.  But the dictionary is full of ordinary
;; Capital-initial derivative entries with grammatical apparatus
;; (e.g. "Προαίρεσις, εως, ή, Propositum…") that none of those catch,
;; and whose index pointer may be OCR-garbled or cross-volume-rejected.
;; This map harvests EVERY such entry -- capital-initial headword +
;; apparatus (noun genitive+article, or verb Latin -o gloss) -- to its
;; own first page.  Because its key is the entry's OWN headword, a
;; lookup can only ever be sent to that word's own entry, never to a
;; different word; so it is safe to consult it ABOVE morphology (a
;; word's own entry beats its root), though still BELOW the index (a
;; clean index column is more precise than a harvested first-occurrence
;; page).  Neighbour-correction repairs a headword OCR-garbled at a
;; non-initial letter, storing the corrected key too.
(defconst diogenes-tgl--apparatus-entry-regexp
  (let* ((cap (concat "\u0391-\u03a9\u1f08-\u1f0f\u1f18-\u1f1f\u1f28-\u1f2f"
                      "\u1f38-\u1f3f\u1f48-\u1f4f\u1f68-\u1f6f\u1fb8-\u1fbf"
                      "\u1fc8-\u1fcf\u1fd8-\u1fdf\u1fe8-\u1fef\u1ff8-\u1fff"))
         (tail "\u0386-\u03ce\u1f00-\u1fff\u0384\u0301\u0300\u0342\u0308\u0313\u0314")
         (noun (concat ",[[:space:]]*[\u03b1-\u03c9\u0386-\u03ce]\\{1,4\\}"
                       "[[:space:]]*,[[:space:]]*"
                       "[" diogenes-tgl--article-class "]"))
         (verb (concat ",[[:space:]]*\\(?:[\u03b1-\u03c9\u0386-\u03ce\u1f60-\u1f6f]"
                       "\\{1,3\\}[[:space:]]*[,.][[:space:]]*\\)?"
                       "[A-Z][a-zA-Z\u017f\u00e6\u0153]\\{2,\\}o\\b")))
    (concat "\\`\\(?:C\\.[[:space:]]*\\)?"
            "['\u2019\u1ffe\u1fbf\u02bc\u0384`]?"
            "\\([" cap "][" tail "]\\{2,\\}\\)"
            "\\(?:" noun "\\|" verb "\\)"))
  "Regexp matching any Capital-initial dictionary entry with apparatus.
Group 1 is the headword.  Apparatus is a noun's genitive + article or
a verb's Latin gloss ending in -o.  Used to harvest the comprehensive
entry map (`diogenes-tgl--parse-entries').")

(defvar diogenes-tgl--entry-cache (make-hash-table :test 'equal)
  "Cache mapping a volume OCR cache-key to its apparatus-entry->page map.")

(defun diogenes-tgl--parse-entries (file)
  "Scan volume OCR FILE; return a hash: Capital-initial apparatus entry -> first page.
Applies neighbour-correction against the adjacent entries on the page
so a headword OCR-garbled at a non-initial letter is also stored under
its corrected key.  The index proper (volume V) is skipped."
  (let ((case-fold-search nil)
        (map (make-hash-table :test 'equal))
        (prev nil) (cur nil))
    (cl-flet ((emit (entry nextk)
                (when entry
                  (let ((k (car entry)) (page (cdr entry)))
                    (when (>= (length k) 4)
                      (unless (gethash k map) (puthash k page map))
                      (let ((corr (and prev nextk
                                       (diogenes-tgl--neighbour-correct
                                        k prev nextk))))
                        (when (and corr (not (gethash corr map)))
                          (puthash corr page map))))))))
      (with-temp-buffer
        (insert-file-contents file)
        (goto-char (point-min))
        (let ((index-start
               (save-excursion
                 (if (search-forward diogenes-tgl--index-marker nil t)
                     (line-beginning-position)
                   (point-max))))
              (marker diogenes-tgl-page-marker-regexp)
              (pdfp nil))
          (goto-char (point-min))
          (while (and (not (eobp)) (< (point) index-start))
            (let ((line (buffer-substring-no-properties
                         (line-beginning-position) (line-end-position))))
              (cond
               ((string-match marker line)
                (setq pdfp (string-to-number (match-string 1 line))))
               ((and pdfp (string-match diogenes-tgl--apparatus-entry-regexp line))
                (let ((k (diogenes-montanari--greek-key (match-string 1 line))))
                  (when (>= (length k) 4)
                    (when cur
                      (emit cur k)
                      (setq prev (car cur)))
                    (setq cur (cons k pdfp)))))))
            (forward-line 1))
          (when cur (emit cur nil)))))
    map))

(defun diogenes-tgl--entries (tomus)
  "Return the (cached) apparatus-entry->page map for TOMUS, or nil."
  (let ((file (diogenes-tgl--volume-text tomus)))
    (when file
      (let ((key (diogenes-tgl--file-cache-key file)))
        (or (gethash key diogenes-tgl--entry-cache)
            (setf (gethash key diogenes-tgl--entry-cache)
                  (diogenes-tgl--parse-entries file)))))))

(defun diogenes-tgl--entry-locate (key)
  "Return (TOMUS . PAGE) for KEY as a Capital-initial apparatus entry, or nil.
Searches every volume (a derivative is filed under its root, whose
volume need not match KEY's initial letter), exact first, then a
1-edit fuzzy match within a volume's map."
  (when (>= (length key) 4)
    (let ((fuzzy nil))
      (or (cl-loop for tomus in '(1 2 3 4)
                   for map = (diogenes-tgl--entries tomus)
                   for page = (and map (gethash key map))
                   when page return (cons tomus (+ page diogenes-tgl-page-offset))
                   do (when (and map (not fuzzy))
                        (let ((fk (diogenes-tgl--fuzzy-in-map key map)))
                          (when fk
                            (setq fuzzy (cons tomus (+ (gethash fk map)
                                                       diogenes-tgl-page-offset)))))))
          fuzzy))))

(defun diogenes-tgl--parse-body (file)
  "Parse volume OCR FILE into a body index plist.
Value: (:pages VEC :letter-hist HASH :caps HASH), where each page
plist is (:page PDF :lo KEY :hi KEY :maj CH :keys KEYVEC), and :caps
maps each all-caps (root) headword key to the FIRST PDF page it heads
\(the authoritative entry opening).  Only pages with at least two
backbone entries are kept for :pages.  The index proper (volume V) is
skipped so its alphabetical index lines are not mistaken for entries.

Binds `case-fold-search' to nil for the whole parse: the caps, entry
and header regexps distinguish Greek CAPITALS from lowercase, but a
normal session has case-folding on -- under which [Α-Ω] also matches
lowercase and [α-ω] also matches capitals.  That made every all-caps
headword fail `diogenes-tgl--all-caps-p', leaving the caps map empty
and sending root lookups (e.g. ἵστημι) to the fallback body scan."
  (let ((case-fold-search nil)
        (pages nil)
        (caps (make-hash-table :test 'equal)))
    (with-temp-buffer
      (insert-file-contents file)
      (goto-char (point-min))
      ;; If this file contains the index (volume V), stop body parsing
      ;; at the index marker: those lines are index entries, not body.
      (let ((index-start
             (save-excursion
               (if (search-forward diogenes-tgl--index-marker nil t)
                   (line-beginning-position)
                 (point-max)))))
        (goto-char (point-min))
        (let ((marker diogenes-tgl-page-marker-regexp)
              (seg-start nil) (pdfp nil)
              ;; Own-volume vocabulary of lower-case headwords (line-start
              ;; lower-case Greek words), gathered in one pre-pass.  Used to
              ;; validate a leading-capital repair in `harvest-caps': a repair
              ;; is trusted only if the stripped form is a headword this volume
              ;; actually prints.
              (lc-vocab (let ((h (make-hash-table :test 'equal)))
                          (save-excursion
                            (goto-char (point-min))
                            (while (re-search-forward
                                    diogenes-tgl--lc-headword-regexp
                                    index-start t)
                              (let ((k (diogenes-montanari--greek-key
                                        (match-string 1))))
                                (when (>= (length k) 3) (puthash k t h)))))
                          h)))
          (cl-flet ((harvest-caps (body page hletter loose-hletter)
                      ;; Record the first-occurrence page of each all-caps
                      ;; headword in BODY.  A capitalised line is normally a
                      ;; root opening -- but Estienne also sets DERIVED forms
                      ;; in caps inside another article (e.g. "ΙΣΤΩΡ" for
                      ;; ἵστωρ, with its compounds Επιΐστωρ/Πολυΐστωρ/…,
                      ;; discussed under the epsilon εἰδ- article).  Such a
                      ;; line is a FALSE anchor: taken as a root opening it
                      ;; would file ἵστωρ (and, via the body scan, ἵστημι) on
                      ;; an epsilon page.  We reject a caps line only when it
                      ;; is BOTH (a) alien to the page -- its initial letter
                      ;; differs from HLETTER, the page's running-header
                      ;; letter -- AND (b) sitting in a derivation cluster
                      ;; (ΕΤ/VNDE/comp. markers on or beside it).  A mismatch
                      ;; alone is kept (transition pages, OCR header lag); a
                      ;; word that is not a derivation is kept even if alien
                      ;; (so a genuine entry like ἵστημι is never suppressed).
                      ;; When the page has no detectable header we cannot
                      ;; judge alienness, so we keep the anchor.  LOOSE-HLETTER
                      ;; is a header letter obtained by a more forgiving scan
                      ;; (`diogenes-tgl--header-letter-loose'); it is used ONLY
                      ;; to validate a leading-capital repair, never for the
                      ;; rejection above, so the rejection is unchanged.
                      (let* ((lines (vconcat (split-string body "\n")))
                             (n (length lines)))
                        (dotimes (i n)
                          (let ((line (aref lines i)))
                            (when (or (string-match
                                       diogenes-tgl--caps-entry-regexp line)
                                      (string-match
                                       diogenes-tgl--caps-head-lemma-regexp line))
                              (let* ((mend (match-end 0))
                                     (raw (match-string 1 line))
                                     ;; lower-case lemma right after a caps head
                                     ;; (only the caps-head-lemma form has one)
                                     (lemma
                                      (and (string-match
                                            diogenes-tgl--caps-head-lemma-regexp line)
                                           (diogenes-montanari--greek-key
                                            (match-string 2 line)))))
                                (ignore mend)
                                (when (diogenes-tgl--all-caps-p raw)
                                  (let ((k (diogenes-montanari--greek-key raw)))
                                    ;; An all-caps head IS a root entry, so its
                                    ;; key must sit in the page's alphabetical
                                    ;; region.  When it does not, a single
                                    ;; leading capital may be OCR noise (e.g.
                                    ;; `ΒΑΥΤΟΣ' for ΑΥΤΟΣ on the αυτ- page).  We
                                    ;; only repair the caps-THEN-lowercase-lemma
                                    ;; form, because there the article's own
                                    ;; lower-case lemma printed right after the
                                    ;; head proves what the letters should be --
                                    ;; a self-check no mis-OCR'd running header
                                    ;; can fool.  Strip the leading capital only
                                    ;; when ALL hold: its first letter differs
                                    ;; from the (loosely read) running-header
                                    ;; letter LOOSE-HLETTER but the SECOND letter
                                    ;; equals it; the stripped form is a head this
                                    ;; volume prints (LC-VOCAB) while the
                                    ;; unstripped form is not; and the printed
                                    ;; lemma begins with the stripped key's first
                                    ;; letter.  (The bare caps-entry form, with no
                                    ;; lemma, is left alone: ΔΕΙΔΩ and ΕΙΔΩ are
                                    ;; both real, and only the lemma could tell
                                    ;; them apart.)  We use the LOOSE header here
                                    ;; because a root's own page may carry a
                                    ;; space-broken header the strict scan misses.
                                    (when (and loose-hletter (> (length k) 1)
                                               (not (eql (aref k 0) loose-hletter))
                                               (eql (aref k 1) loose-hletter)
                                               lemma (>= (length lemma) 3)
                                               (eql (aref lemma 0) (aref k 1))
                                               (gethash (substring k 1) lc-vocab)
                                               (not (gethash k lc-vocab)))
                                      (setq k (substring k 1)))
                                    (when (and (>= (length k) 3)
                                               (not (gethash k caps)))
                                      (let* ((mismatch
                                              (and hletter
                                                   (not (eql (aref k 0) hletter))))
                                             (derivation
                                              (and mismatch
                                                   (cl-loop
                                                    for j from (max 0 (1- i))
                                                    to (min (1- n) (+ i 2))
                                                    thereis
                                                    (string-match-p
                                                     diogenes-tgl--derivation-marker-regexp
                                                     (aref lines j))))))
                                        (unless (and mismatch derivation)
                                          (puthash k page caps)))))))))))))
            (while (and (re-search-forward marker nil t)
                        (< (match-beginning 0) index-start))
              (let ((this (string-to-number (match-string 1)))
                    (body-start (match-end 0)))
                (when (and seg-start pdfp)
                  (let* ((body (buffer-substring-no-properties
                                seg-start (match-beginning 0)))
                         (core (diogenes-tgl--monotone-backbone
                                (diogenes-tgl--page-candidates body))))
                    (harvest-caps body pdfp (diogenes-tgl--header-letter body)
                                  (diogenes-tgl--header-letter-loose body))
                    (when (>= (length core) 2)
                      (push (list :page pdfp
                                  :lo (car core)
                                  :hi (car (last core))
                                  :maj (diogenes-tgl--majority-first-letter core)
                                  :keys (vconcat core))
                            pages))))
                (setq seg-start body-start pdfp this)))
            ;; Final segment (only if it precedes the index).
            (when (and seg-start pdfp (< seg-start index-start))
              (let* ((end (min index-start (point-max)))
                     (body (buffer-substring-no-properties seg-start end))
                     (core (diogenes-tgl--monotone-backbone
                            (diogenes-tgl--page-candidates body))))
                (harvest-caps body pdfp (diogenes-tgl--header-letter body)
                              (diogenes-tgl--header-letter-loose body))
                (when (>= (length core) 2)
                  (push (list :page pdfp
                              :lo (car core)
                              :hi (car (last core))
                              :maj (diogenes-tgl--majority-first-letter core)
                              :keys (vconcat core))
                        pages))))))))
    (setq pages (nreverse pages))
    (let ((hist (make-hash-table :test 'eql)))
      (dolist (pg pages)
        (let ((maj (plist-get pg :maj)))
          (when maj (puthash maj (1+ (gethash maj hist 0)) hist))))
      (list :pages (vconcat pages) :letter-hist hist :caps caps))))

(defun diogenes-tgl--body (tomus)
  "Return the (cached) body page index for TOMUS, or nil if no OCR."
  (let ((file (diogenes-tgl--volume-text tomus)))
    (when file
      (let ((key (diogenes-tgl--file-cache-key file)))
        (or (gethash key diogenes-tgl--body-cache)
            (setf (gethash key diogenes-tgl--body-cache)
                  (diogenes-tgl--parse-body file)))))))

(defun diogenes-tgl--caps-opening (tomus key)
  "Return the first PDF page in TOMUS where all-caps KEY heads an entry, or nil."
  (let ((body (diogenes-tgl--body tomus)))
    (when body
      (gethash key (plist-get body :caps)))))

(defconst diogenes-tgl--bare-caps-line-regexp
  (concat "\\`['\u2019\u1ffe\u1fbf\u02bc\u0384`]?"
          "\\([" diogenes-tgl--greek-capital-class "]\\{4,\\}\\)"
          "[ \t]*\\'")
  "Regexp matching a line that is a BARE all-caps word (4+ letters), nothing else.
Some article openings are OCR'd with no trailing punctuation -- the
all-caps headword alone on a line (e.g. ΙΗΜΙ for the root ἵημι) -- so
the punctuation-terminated `diogenes-tgl--caps-entry-regexp' misses
them.  This matches such a line; group 1 is the word.  A 4-letter
minimum, plus the consecutive-page test in
`diogenes-tgl--bare-caps-opening', keeps short running-header tokens
\(e.g. ΑΓΑ, ΑΓΓ) and one-off header truncations out.")

(defun diogenes-tgl--bare-caps-opening (tomus key)
  "Return the first PDF page in TOMUS where KEY opens as a BARE all-caps line, or nil.
A genuine root article prints its all-caps headword as the running
header across the CONSECUTIVE pages the article spans; a truncated
running-header artifact appears only sporadically.  So this scans
TOMUS's OCR for bare all-caps lines (see
`diogenes-tgl--bare-caps-line-regexp') whose key is KEY, and returns
the first page of the earliest run of at least two consecutive pages.
On-demand fallback for `diogenes-tgl--caps-locate' when the punctuated
caps map has no opening for KEY; deliberately narrow, so it does not
pollute the global caps map."
  (let ((file (diogenes-tgl--volume-text tomus)))
    (when (and file (>= (length key) 4))
      (let ((case-fold-search nil))
        (with-temp-buffer
          (insert-file-contents file)
          (goto-char (point-min))
          (let ((marker diogenes-tgl-page-marker-regexp)
                (pdfp nil) (hits nil))    ; hits: list of pages carrying KEY, in order
            (while (not (eobp))
              (let ((line (buffer-substring-no-properties
                           (line-beginning-position) (line-end-position))))
                (if (string-match marker line)
                    (setq pdfp (string-to-number (match-string 1 line)))
                  (when (and pdfp
                             (string-match diogenes-tgl--bare-caps-line-regexp line)
                             (string= (diogenes-montanari--greek-key
                                       (match-string 1 line))
                                      key))
                    (unless (eql (car hits) pdfp) (push pdfp hits)))))
              (forward-line 1))
            ;; earliest run of >=2 consecutive pages
            (let ((asc (nreverse hits)) (run-start nil) (result nil))
              (while (and asc (not result))
                (let ((p (car asc)) (nx (cadr asc)))
                  (cond
                   ((and nx (= nx (1+ p)))
                    (unless run-start (setq run-start p))
                    (setq result run-start))
                   (t (setq run-start nil)))
                  (setq asc (cdr asc))))
              result)))))))

(defun diogenes-tgl--caps-locate (key)
  "Return (TOMUS . PAGE) for KEY's caps-entry opening in its own volume, or nil.
Consults only the volume that KEY's initial letter routes to (see
`diogenes-tgl--tomus-for-key'), so it cannot cross volumes.  First the
punctuation-terminated caps map; then, on a miss, the bare-caps
consecutive-page fallback (`diogenes-tgl--bare-caps-opening'), which
recovers root openings the OCR left without trailing punctuation."
  (when (> (length key) 0)
    (let ((tomus (diogenes-tgl--tomus-for-key key)))
      (when tomus
        (let ((page (or (diogenes-tgl--caps-opening tomus key)
                        (diogenes-tgl--bare-caps-opening tomus key))))
          (when page
            (cons tomus (+ page diogenes-tgl-page-offset))))))))

(defun diogenes-tgl--caps-locate-any (key)
  "Return (TOMUS . PAGE) for KEY's caps-entry opening in ANY volume, or nil.
Used for morphological roots, whose volume may differ from the
compound's initial letter; scans volumes in order and takes the first
caps opening found."
  (when (> (length key) 0)
    (cl-loop for tomus in '(1 2 3 4)
             for page = (diogenes-tgl--caps-opening tomus key)
             when page
             return (cons tomus (+ page diogenes-tgl-page-offset)))))

(defun diogenes-tgl--entry-page-in (tomus key)
  "Return the first PDF page in TOMUS on which KEY heads an entry line, or nil.
Scans the volume OCR for a left-margin entry (per
`diogenes-tgl--entry-regexp') whose collation key is KEY.  Unlike the
`:keys' backbone -- which drops entries that violate the page's
alphabetical order, exactly the badly-OCR'd pages where an anchor is
needed -- this considers every detected entry line, so a clean
neighbour such as ἀμφιλογέω or παραχαράκται is found even when it was
filtered out of the backbone.  Used to resolve an `:after' anchor in
`diogenes-tgl--entry-overrides'."
  (let ((file (diogenes-tgl--volume-text tomus))
        (case-fold-search nil))
    (when file
      (with-temp-buffer
        (insert-file-contents file)
        (goto-char (point-min))
        (let ((marker diogenes-tgl-page-marker-regexp)
              (pdfp nil) (found nil))
          (while (and (not found) (not (eobp)))
            (let ((line (buffer-substring-no-properties
                         (line-beginning-position) (line-end-position))))
              (cond
               ((string-match marker line)
                (setq pdfp (string-to-number (match-string 1 line))))
               ((and pdfp (string-match diogenes-tgl--entry-regexp line)
                     (string= (diogenes-montanari--greek-key
                               (match-string 1 line))
                              key))
                (setq found (+ pdfp diogenes-tgl-page-offset)))))
            (forward-line 1))
          found)))))

;;;; --------------------------------------------------------------------
;;;; ROUTING BY INITIAL LETTER
;;;; --------------------------------------------------------------------

;; A word's own entry lives in the volume covering its initial letter, so
;; correct letter->volume routing is fundamental (it decides which
;; volume's index references and body pages count as the word's own).
;; The TGL's four content volumes divide the alphabet in fixed, well
;; known blocks; we nonetheless DERIVE the split from the scans so it
;; adapts to a differently-cut set -- but from the ROBUST signal (how
;; many all-caps root entries each volume devotes to each initial
;; letter), not the fragile page-backbone histogram used before, which
;; could be swayed by quoted Greek and mis-route a letter (that bug sent
;; λέγω, a λ/tomus-2 word, into tomus 3).  The canonical block partition
;; is used as the tiebreak/fallback so routing stays correct even for a
;; volume whose OCR is too degraded to vote.

(defconst diogenes-tgl--canonical-letter-tomus
  '((?\N{GREEK SMALL LETTER ALPHA}   . 1) (?\N{GREEK SMALL LETTER BETA}    . 1)
    (?\N{GREEK SMALL LETTER GAMMA}   . 1) (?\N{GREEK SMALL LETTER DELTA}   . 1)
    (?\N{GREEK SMALL LETTER EPSILON} . 1) (?\N{GREEK SMALL LETTER ZETA}    . 1)
    (?\N{GREEK SMALL LETTER ETA}     . 1) (?\N{GREEK SMALL LETTER THETA}   . 1)
    (?\N{GREEK SMALL LETTER IOTA}    . 1)
    (?\N{GREEK SMALL LETTER KAPPA}   . 2) (?\N{GREEK SMALL LETTER LAMDA}   . 2)
    (?\N{GREEK SMALL LETTER MU}      . 2) (?\N{GREEK SMALL LETTER NU}      . 2)
    (?\N{GREEK SMALL LETTER XI}      . 2) (?\N{GREEK SMALL LETTER OMICRON} . 2)
    (?\N{GREEK SMALL LETTER PI}      . 3) (?\N{GREEK SMALL LETTER RHO}     . 3)
    (?\N{GREEK SMALL LETTER SIGMA}   . 3) (?\N{GREEK SMALL LETTER TAU}     . 3)
    (?\N{GREEK SMALL LETTER UPSILON} . 3)
    (?\N{GREEK SMALL LETTER PHI}     . 4) (?\N{GREEK SMALL LETTER CHI}     . 4)
    (?\N{GREEK SMALL LETTER PSI}     . 4) (?\N{GREEK SMALL LETTER OMEGA}   . 4))
  "Canonical map from a Greek initial letter to its TGL volume.
The 1572 folio divides the alphabet α–ι, κ–ο, π–υ, φ–ω across the
four content volumes.  Used as the fallback/tiebreak for
`diogenes-tgl--letter-map'.")

(defvar diogenes-tgl--letter-map-cache (make-hash-table :test 'equal)
  "Cache mapping the parent-directory signature to a Greek-letter->tomus map.")

(defun diogenes-tgl--letter-map ()
  "Return a hash mapping each Greek initial letter to its owning TOMUS.
Assigns each letter to the volume that devotes the most all-caps root
entries to it (a robust signal, from each volume's :caps map).  Any
letter with no clear caps winner falls back to
`diogenes-tgl--canonical-letter-tomus', which also seeds every letter
first so routing is never left undefined."
  (let ((key (diogenes-tgl--dir-signature
              (file-name-as-directory (expand-file-name diogenes-tgl-directory)))))
    (or (gethash key diogenes-tgl--letter-map-cache)
        (setf (gethash key diogenes-tgl--letter-map-cache)
              (let ((map (make-hash-table :test 'eql))
                    (best (make-hash-table :test 'eql)))
                ;; Seed with the canonical partition (fallback for letters
                ;; no volume votes strongly for).
                (dolist (pair diogenes-tgl--canonical-letter-tomus)
                  (puthash (car pair) (cdr pair) map))
                ;; Override from caps-entry counts: for each volume, tally
                ;; the initial letter of every all-caps root entry, and let
                ;; the volume with the most win each letter.
                (dolist (entry (diogenes-tgl--volumes))
                  (let* ((tomus (car entry))
                         (body (and (<= tomus 4) (diogenes-tgl--body tomus)))
                         (caps (and body (plist-get body :caps))))
                    (when caps
                      (let ((per (make-hash-table :test 'eql)))
                        (maphash (lambda (k _page)
                                   (when (> (length k) 0)
                                     (let ((c (aref k 0)))
                                       (puthash c (1+ (gethash c per 0)) per))))
                                 caps)
                        (maphash (lambda (c n)
                                   (when (> n (gethash c best 0))
                                     (puthash c n best)
                                     (puthash c tomus map)))
                                 per)))))
                map)))))

(defun diogenes-tgl--tomus-for-key (key)
  "Return the TOMUS whose body covers KEY's initial Greek letter, or nil."
  (when (> (length key) 0)
    (gethash (aref key 0) (diogenes-tgl--letter-map))))

;;;; --------------------------------------------------------------------
;;;; BODY PAGE SELECTION  (which page in the routed volume)
;;;; --------------------------------------------------------------------

(defun diogenes-tgl--page-gap (key pg)
  "Classify how KEY sits among page PG's entry keys.
0 = KEY equals an entry on the page; 1 = KEY lies strictly between two
entries; 2 = KEY is at or beyond an end of the page."
  (let* ((keys (plist-get pg :keys)) (n (length keys)))
    (if (zerop n)
        2
      (let ((lo 0) (hi n) (found nil))
        (while (< lo hi)
          (let* ((mid (/ (+ lo hi) 2)) (k (aref keys mid)))
            (cond ((string= k key) (setq found t lo hi))
                  ((string< k key) (setq lo (1+ mid)))
                  (t (setq hi mid)))))
        (cond (found 0)
              ((and (> lo 0) (< lo n)) 1)
              (t 2))))))

(defun diogenes-tgl--stage1 (key pages)
  "Return the PAGES whose majority first letter matches KEY's initial."
  (let ((L (and (> (length key) 0) (aref key 0))) hits)
    (when L
      (cl-loop for pg across pages
               when (eql (plist-get pg :maj) L)
               do (push pg hits)))
    (nreverse hits)))

(defun diogenes-tgl--stage2 (key candidates)
  "Pick the best page plist from CANDIDATES for KEY.
Prefers the smallest gap class; gap-0 (exact headword) resolves to the
earliest such page (where a multi-page entry begins), gap-1 to the
tightest bracketing page."
  (car (sort (copy-sequence candidates)
             (lambda (a b)
               (let ((ga (diogenes-tgl--page-gap key a))
                     (gb (diogenes-tgl--page-gap key b)))
                 (cond
                  ((/= ga gb) (< ga gb))
                  ((= ga 0) (< (plist-get a :page) (plist-get b :page)))
                  (t
                   (let* ((ka (aref (plist-get a :keys) 0))
                          (kb (aref (plist-get b :keys) 0))
                          (a-le (not (string< key ka)))
                          (b-le (not (string< key kb))))
                     (cond
                      ((and a-le (not b-le)) t)
                      ((and b-le (not a-le)) nil)
                      ((and a-le b-le)
                       (if (string= ka kb)
                           (< (plist-get a :page) (plist-get b :page))
                         (string> ka kb)))
                      (t (if (string= ka kb)
                             (< (plist-get a :page) (plist-get b :page))
                           (string< ka kb))))))))))))

(defun diogenes-tgl--body-headword-page (key pages)
  "Return the PDF page in PAGES whose backbone has KEY as a headword, or nil.
Scans every page's `:keys' backbone for KEY, preferring an EXACT
headword match (the entry opening); failing that, a 1-edit match that
shares KEY's first two letters, which recovers a headword the OCR
garbled by a single character (e.g. ΙΣΤΗΜΙ scanned as \"ισημι\", the
tau dropped).  Crucially this does NOT pre-filter pages by their
majority letter: a real entry page can have a noisy majority (its OCR
fragments scattered across letters), so the earlier majority-letter
stage would wrongly exclude it -- which is how ἵστημι, whose page's
majority letter is eta, was skipped and the lookup fell onto a nearby
ιστ- page.  An exact/near headword match is the strongest body signal,
so when one exists it is chosen over any alphabetical bracketing.
Returns the earliest matching page (where a multi-page entry begins)."
  (when (> (length key) 0)
    (let ((exact nil) (fuzzy nil)
          (pre (and (>= (length key) 2) (substring key 0 2))))
      (cl-loop for pg across pages do
               (let ((keys (plist-get pg :keys)) (page (plist-get pg :page)))
                 (cl-loop for k across keys do
                          (cond
                           ((string= k key)
                            (when (or (null exact) (< page exact))
                              (setq exact page)))
                           ((and (null exact) pre (>= (length k) 4)
                                 (string= (substring k 0 2) pre)
                                 (diogenes-tgl--edit1-p key k))
                            (when (or (null fuzzy) (< page fuzzy))
                              (setq fuzzy page)))))))
      (or exact fuzzy))))

(defun diogenes-tgl--body-locate (word)
  "Return (TOMUS . PDF-PAGE) for WORD by scanning volume bodies, or nil.
Routes to the volume owning WORD's initial letter.  Chooses, in order:
an EXACT or 1-edit headword match anywhere in that volume
\(`diogenes-tgl--body-headword-page' -- the strongest signal, and not
gated by a page's noisy majority letter); else the best page among
those whose majority letter matches (`diogenes-tgl--stage1' /
`-stage2', alphabetical bracketing); else the nearest lower page."
  (let ((key (diogenes-montanari--greek-key word)))
    (when (> (length key) 0)
      (let ((tomus (diogenes-tgl--tomus-for-key key)))
        (when tomus
          (let* ((body (diogenes-tgl--body tomus))
                 (pages (and body (plist-get body :pages))))
            (when (and pages (> (length pages) 0))
              (let ((hw (diogenes-tgl--body-headword-page key pages)))
                (cond
                 ;; 1. Exact/near headword match: the entry actually sits here.
                 (hw (cons tomus (+ hw diogenes-tgl-page-offset)))
                 ;; 2. Alphabetical bracketing among same-majority-letter pages.
                 (t
                  (let ((cands (diogenes-tgl--stage1 key pages)))
                    (if cands
                        (cons tomus (plist-get (diogenes-tgl--stage2 key cands) :page))
                      ;; 3. Letter owned but no same-letter page: nearest lower.
                      (let ((best (aref pages 0)))
                        (cl-loop for pg across pages
                                 when (not (string< key (aref (plist-get pg :keys) 0)))
                                 do (setq best pg))
                        (cons tomus (plist-get best :page)))))))))))))))

;;;; --------------------------------------------------------------------
;;;; APPROXIMATE (PREFIX) POSITION  --  running-header signal
;;;; --------------------------------------------------------------------

;; The body backbone (`:keys') is noisy: cross-letter OCR fragments and
;; quoted Greek leak into a page's detected entries, so its per-page key
;; range is unreliable for placing a bare prefix -- e.g. searching "λεγ"
;; landed on a λει- page because the alphabetical bracketing was thrown
;; off by stray keys.  Estienne's RUNNING HEADER, by contrast, is a short
;; all-caps token (ΛΕΓ, ΛΕΙ, ΛΟΓ...) printed once per page naming the
;; article that page belongs to; being short and all-caps it OCRs cleanly,
;; and it advances monotonically through the volume.  For the APPROXIMATE
;; jump we therefore position a query by the header sequence, not the body
;; keys: we find the article whose header is the greatest one <= the query
;; (sharing the query's initial letter) and land on the FIRST page carrying
;; that header -- the article's opening.  A prefix with no exact article
;; header lands at the nearest preceding article, whose running head lets
;; the reader page a little; that is the intended "neighbourhood" behaviour.

(defvar diogenes-tgl--header-map-cache (make-hash-table :test 'equal)
  "Cache mapping a volume OCR cache-key to its page-ordered header list.
The value is a list of (PDF-PAGE . HEADER-KEY), one entry per page that
carries a running header, in ascending page order.")

(defun diogenes-tgl--parse-headers (file)
  "Scan volume OCR FILE; return a page-ordered list of (PDF-PAGE . HEADER-KEY).
HEADER-KEY is the collation key of the page's most frequent running
header token (`diogenes-tgl--running-header-regexp'), which names the
article the page belongs to.  Taking the modal token per page is robust
to the occasional mis-OCR'd header line.  The index proper (volume V) is
skipped."
  (let ((case-fold-search nil) (out nil))
    (with-temp-buffer
      (insert-file-contents file)
      (goto-char (point-min))
      (let ((index-start
             (save-excursion
               (if (search-forward diogenes-tgl--index-marker nil t)
                   (line-beginning-position)
                 (point-max))))
            (marker diogenes-tgl-page-marker-regexp)
            (pdfp nil)
            (counts nil))                 ; alist HEADER-KEY -> count for current page
        (cl-flet ((flush ()
                    (when (and pdfp counts)
                      (let ((best nil) (bestn 0))
                        (dolist (kc counts)
                          (when (> (cdr kc) bestn)
                            (setq best (car kc) bestn (cdr kc))))
                        (when best (push (cons pdfp best) out))))
                    (setq counts nil)))
          (goto-char (point-min))
          (while (and (not (eobp)) (< (point) index-start))
            (let ((line (buffer-substring-no-properties
                         (line-beginning-position) (line-end-position))))
              (cond
               ((string-match marker line)
                (flush)
                (setq pdfp (string-to-number (match-string 1 line))))
               ((and pdfp (string-match diogenes-tgl--running-header-regexp line))
                (let ((k (diogenes-montanari--greek-key (match-string 1 line))))
                  (when (>= (length k) 2)
                    (let ((cell (assoc k counts)))
                      (if cell (setcdr cell (1+ (cdr cell)))
                        (push (cons k 1) counts))))))))
            (forward-line 1))
          (flush))))
    (nreverse out)))

(defun diogenes-tgl--header-map (tomus)
  "Return the (cached) page-ordered header list for TOMUS, or nil."
  (let ((file (diogenes-tgl--volume-text tomus)))
    (when file
      (let ((key (diogenes-tgl--file-cache-key file)))
        (or (gethash key diogenes-tgl--header-map-cache)
            (setf (gethash key diogenes-tgl--header-map-cache)
                  (diogenes-tgl--parse-headers file)))))))

(defun diogenes-tgl--approx-locate (word)
  "Return (TOMUS . PDF-PAGE) for WORD's APPROXIMATE (prefix) position, or nil.
Routes WORD to the volume owning its initial letter, then positions it
by that volume's running-header sequence (see the section comment):
finds the article whose header is the greatest one <= WORD's key that
shares WORD's initial letter, and returns the FIRST page carrying that
header.  Falls back to the body scan when the volume has no header data."
  (diogenes-tgl--maybe-load-prebuilt-index)
  (let ((key (diogenes-montanari--greek-key word)))
    (when (> (length key) 0)
      (let ((tomus (diogenes-tgl--tomus-for-key key)))
        (when tomus
          (let* ((L (aref key 0))
                 (headers (diogenes-tgl--header-map tomus))
                 ;; keep only headers under the query's own initial letter
                 (same (cl-remove-if-not
                        (lambda (ph) (let ((h (cdr ph)))
                                       (and (> (length h) 0) (eql (aref h 0) L))))
                        headers)))
            (if (null same)
                ;; No header data for this letter: fall back to the body scan.
                (diogenes-tgl--body-locate word)
              (let* ((le (cl-remove-if (lambda (ph) (string< key (cdr ph))) same))
                     (target (if le
                                 ;; greatest header <= key
                                 (car (sort (mapcar #'cdr le) #'string>))
                               ;; key precedes every same-letter header: earliest article
                               (car (sort (mapcar #'cdr same) #'string<))))
                     ;; first page carrying TARGET header
                     (page (car (sort (cl-loop for (pg . h) in same
                                               when (string= h target) collect pg)
                                      #'<))))
                (when page
                  (cons tomus (+ page diogenes-tgl-page-offset)))))))))))

;;;; --------------------------------------------------------------------
;;;; TOP-LEVEL LOCATE  (index first, then body fallback)
;;;; --------------------------------------------------------------------

;;;; --------------------------------------------------------------------
;;;; MORPHOLOGICAL DECOMPOSITION  (index-miss fallback for bare compounds)
;;;; --------------------------------------------------------------------

;; A word may be a compound whose root heads an entry elsewhere (often in
;; another volume) but which the index neither lists with a column nor
;; cross-references with a "vide" line -- a bare compound such as διαλέγω
;; (under λέγω).  Following Smyth, Greek Grammar Sections 870, 884-885, we strip a
;; single leading preposition/adverb or inseparable prefix and look the
;; remainder up in the index.  Two grammatical facts shape this:
;;
;;   * When a VOWEL-FINAL prefix meets a vowel-initial second element the
;;     vowels contract at the seam (Section 884 b) and the element's short
;;     initial vowel lengthens (Section 887: alpha/epsilon -> eta, omicron -> omega).
;;     So after stripping such a prefix we also peel the leftover leading
;;     vowel of the remainder and try de-lengthened forms (omega->omicron,
;;     eta->epsilon/alpha) -- this is what turns δια+λεγω's surface αλεγω
;;     into the real root λεγω.  Consonant-final prefixes leave a clean
;;     remainder and get no extra peel.
;;
;; This is deliberately CONSERVATIVE and safe:
;;   - at most ONE prefix is stripped (no chasing δι-έξ-οδο-ς, Section 869);
;;   - a candidate is accepted ONLY on an EXACT index hit -- never fuzzy,
;;     so an OCR-garbled near-miss cannot masquerade as a root;
;;   - both the stripped word's residual AND the root candidate must be at
;;     least `diogenes-tgl-morph-min-root' letters, which removes the
;;     short-word collisions (e.g. stripping alpha off ἀθήρ to reach θηρ, or
;;     ευ off εὐδία to reach δια);
;;   - the whole stage runs only AFTER index (exact + fuzzy) and the vide
;;     hop have failed, so it never overrides a more reliable result.
;; A wrong-but-surviving decomposition is almost always in the same volume
;; the word's own initial letter routes to, so it cannot cause a
;; cross-volume error; it merely picks a (usually nearby) page there.

(defcustom diogenes-tgl-morph-fallback t
  "If non-nil, try stripping a Greek prefix when a word misses the index.
Some derived compounds are printed under their root and are neither
listed with a column nor \"vide\"-referenced in the index; stripping a
single prefix (per Smyth Sections 870, 884-885) and resolving the root can
still place them.  Only an exact index hit on the root is trusted, and
only after the index and cross-reference paths have failed, so this
never degrades a more reliable match.  See
`diogenes-tgl-morph-min-root'."
  :type 'boolean
  :group 'diogenes)

(defcustom diogenes-tgl-morph-min-root 4
  "Minimum length of both the residual and the root in prefix stripping.
Guards against stripping a prefix off a short word and trusting the
tiny tail (which is frequently an unrelated real lemma), the main
source of false decompositions.  Applies only to
`diogenes-tgl-morph-fallback'."
  :type 'integer
  :group 'diogenes)

(defconst diogenes-tgl--prefixes
  ;; Collation keys (lowercase, unaccented), longest first so the maximal
  ;; prefix strips first.  Prepositions/adverbs (Section 884) and inseparable
  ;; prefixes (Section 885); the privative alpha/alpha-nu come last as the most
  ;; error-prone.  These are Greek letters, not Latin look-alikes.
  '("\u03b1\u03bc\u03c6\u03b9"          ; αμφι
    "\u03b1\u03bd\u03c4\u03b9"          ; αντι
    "\u03ba\u03b1\u03c4\u03b1"          ; κατα
    "\u03bc\u03b5\u03c4\u03b1"          ; μετα
    "\u03c0\u03b1\u03c1\u03b1"          ; παρα
    "\u03c0\u03b5\u03c1\u03b9"          ; περι
    "\u03c0\u03c1\u03bf\u03c3"          ; προς
    "\u03c5\u03c0\u03b5\u03c1"          ; υπερ
    "\u03b5\u03bd\u03b4\u03bf"          ; ενδο
    "\u03b1\u03bd\u03b1"                ; ανα
    "\u03b1\u03c0\u03bf"                ; απο
    "\u03b4\u03b9\u03b1"                ; δια
    "\u03b5\u03b9\u03c3"                ; εισ
    "\u03b5\u03c0\u03b9"                ; επι
    "\u03c0\u03c1\u03bf"                ; προ
    "\u03c3\u03c5\u03bd"                ; συν
    "\u03c3\u03c5\u03bc"                ; συμ
    "\u03c3\u03c5\u03bb"                ; συλ
    "\u03c5\u03c0\u03bf"                ; υπο
    "\u03b5\u03be\u03c9"                ; εξω
    "\u03b7\u03bc\u03b9"                ; ημι
    "\u03b1\u03c1\u03b9"                ; αρι
    "\u03b5\u03c1\u03b9"                ; ερι
    "\u03b1\u03b3\u03b1"                ; αγα
    "\u03b5\u03ba"                      ; εκ
    "\u03b5\u03be"                      ; εξ
    "\u03b5\u03bd"                      ; εν
    "\u03b5\u03c5"                      ; ευ
    "\u03b4\u03c5\u03c3"                ; δυσ
    "\u03bd\u03b7"                      ; νη
    "\u03b6\u03b1"                      ; ζα
    "\u03b4\u03b1"                      ; δα
    "\u03b1\u03bd"                      ; αν
    "\u03b1")                           ; α  (privative; last resort)
  "Greek prefixes stripped by the morphological fallback, longest first.
From Smyth, Greek Grammar Sections 884 (prepositions/adverbs) and 885 (inseparable
prefixes).  Used only by `diogenes-tgl--root-candidates'.")

(defconst diogenes-tgl--greek-vowels "\u03b1\u03b5\u03b7\u03b9\u03bf\u03c5\u03c9"
  "Lowercase Greek vowels (alpha epsilon eta iota omicron upsilon omega), for seam detection.")

(defconst diogenes-tgl--prepositional-prefixes
  '("\u03b1\u03bc\u03c6\u03b9"          ; αμφι
    "\u03b1\u03bd\u03c4\u03b9"          ; αντι
    "\u03ba\u03b1\u03c4\u03b1"          ; κατα
    "\u03bc\u03b5\u03c4\u03b1"          ; μετα
    "\u03c0\u03b1\u03c1\u03b1"          ; παρα
    "\u03c0\u03b5\u03c1\u03b9"          ; περι
    "\u03c0\u03c1\u03bf\u03c3"          ; προς
    "\u03c5\u03c0\u03b5\u03c1"          ; υπερ
    "\u03b5\u03bd\u03b4\u03bf"          ; ενδο
    "\u03b1\u03bd\u03b1"                ; ανα
    "\u03b1\u03c0\u03bf"                ; απο
    "\u03b4\u03b9\u03b1"                ; δια
    "\u03b5\u03b9\u03c3"                ; εισ
    "\u03b5\u03c0\u03b9"                ; επι
    "\u03c0\u03c1\u03bf"                ; προ
    "\u03c3\u03c5\u03bd"                ; συν
    "\u03c3\u03c5\u03bc"                ; συμ
    "\u03c3\u03c5\u03bb"                ; συλ
    "\u03c5\u03c0\u03bf"                ; υπο
    "\u03b5\u03be\u03c9"                ; εξω
    "\u03b5\u03ba"                      ; εκ
    "\u03b5\u03be"                      ; εξ
    "\u03b5\u03bd")                     ; εν
  "The PREPOSITIONAL prefixes (Smyth Section 884), longest first.
A subset of `diogenes-tgl--prefixes': the true prepositions/adverbs
used as preverbs, where a compound splits unambiguously into prefix +
root, so the root's initial letter is certain.  The inseparable and
intensive prefixes (Section 885: alpha-privative, alpha-copulative, νη,
δυσ, ευ, ημι, αρι, ερι, αγα, ζα, δα, αν) are deliberately EXCLUDED --
their residual root letter is not reliable enough to constrain a match
by (an alpha-word need not be an alpha-privative compound).  Used by
`diogenes-tgl--prepositional-root-initials'.")

(defun diogenes-tgl--prepositional-root-initials (key)
  "Return the set of possible root INITIAL letters if KEY is a prepositional compound.
Strips each applicable prefix in `diogenes-tgl--prepositional-prefixes'
from KEY (respecting `diogenes-tgl-morph-min-root' and the same
vowel-seam / de-lengthening allowances as `diogenes-tgl--root-candidates'),
and returns the list of distinct first characters of the resulting
roots.  Returns nil when KEY has no prepositional prefix -- meaning
\"no constraint\": callers must not filter in that case."
  (let ((min diogenes-tgl-morph-min-root) (inits nil))
    (dolist (p diogenes-tgl--prepositional-prefixes)
      (let ((lp (length p)))
        (when (and (> (length key) lp)
                   (string-prefix-p p key)
                   (>= (- (length key) lp) min))
          (let* ((rem (substring key lp))
                 (roots (list rem)))
            ;; same seam/de-lengthen allowances as root extraction
            (when (and (diogenes-tgl--vowel-p (substring p (1- lp) lp))
                       (> (length rem) 0)
                       (diogenes-tgl--vowel-p (substring rem 0 1)))
              (push (substring rem 1) roots)
              (setq roots (append roots
                                  (diogenes-tgl--delengthen-initial rem)
                                  (diogenes-tgl--delengthen-initial
                                   (substring rem 1)))))
            (dolist (r roots)
              (when (and (stringp r) (> (length r) 0))
                (cl-pushnew (aref r 0) inits)))))))
    (nreverse inits)))

(defun diogenes-tgl--vowel-p (s)
  "Non-nil if one-character string S is a lowercase Greek vowel."
  (and (stringp s) (> (length s) 0)
       (integerp (string-match-p (regexp-quote s) diogenes-tgl--greek-vowels))))

(defun diogenes-tgl--delengthen-initial (stem)
  "Return de-lengthened variants of STEM's initial long vowel (Smyth Section 887).
Leading omega -> omicron; leading eta -> epsilon or alpha.  Returns a
possibly-empty list not including STEM itself."
  (when (> (length stem) 0)
    (let ((c (substring stem 0 1)) (rest (substring stem 1)))
      (cond
       ((string= c "\u03c9") (list (concat "\u03bf" rest)))        ; ω -> ο
       ((string= c "\u03b7") (list (concat "\u03b5" rest)          ; η -> ε
                                   (concat "\u03b1" rest)))        ;   -> α
       (t nil)))))

(defun diogenes-tgl--root-candidates (key)
  "Return ordered root candidates for KEY by conservative prefix stripping.
Strips at most one prefix from `diogenes-tgl--prefixes'; for a
vowel-final prefix meeting a vowel-initial remainder, also peels the
leftover seam vowel and offers de-lengthened forms (see the section
comment above).  Both the residual and every candidate must be at
least `diogenes-tgl-morph-min-root' long.

As a LOWEST-priority fallback, a SECOND prefix is then stripped from
each first-round candidate, for doubly-compounded words whose singly
stripped form is itself still nested and unfindable (e.g. ἀποκάταγμα
-> κάταγμα -> ἄγμα, the ἄγνυμι root).  These twice-stripped candidates
are appended after all single-strip ones, so a single prefix is always
tried first; because every candidate is accepted only when it resolves
to a real caps opening or exact index entry, an over-strip to a
spurious short stem simply fails to resolve and does no harm."
  (let ((min diogenes-tgl-morph-min-root)
        (cands nil))
    (cl-labels ((strip1 (k acc)
                  ;; push single-prefix-strip candidates of K into ACC (a list
                  ;; symbol via closure); returns the new list.
                  (let ((out acc))
                    (cl-labels ((add (x)
                                  (when (and x (>= (length x) min)
                                             (not (member x out)))
                                    (push x out))))
                      (dolist (p diogenes-tgl--prefixes)
                        (let ((lp (length p)))
                          (when (and (> (length k) lp)
                                     (string-prefix-p p k)
                                     (>= (- (length k) lp) min))
                            (let ((rem (substring k lp)))
                              (add rem)
                              (when (and (diogenes-tgl--vowel-p
                                          (substring p (1- lp) lp))
                                         (> (length rem) 0)
                                         (diogenes-tgl--vowel-p
                                          (substring rem 0 1)))
                                (add (substring rem 1))
                                (mapc #'add (diogenes-tgl--delengthen-initial rem))
                                (mapc #'add (diogenes-tgl--delengthen-initial
                                             (substring rem 1)))))))))
                    out)))
      ;; first round: one prefix off KEY
      (setq cands (strip1 key nil))
      (let ((first (reverse cands)))       ; preserve discovery order
        ;; second round: one more prefix off each first-round candidate,
        ;; appended AFTER the single-strip candidates (lower priority).
        (let ((second nil))
          (dolist (c first)
            (setq second (strip1 c second)))
          (dolist (s (reverse second))
            (unless (member s cands) (push s cands))))
        (nreverse cands)))))

(defconst diogenes-tgl--entry-overrides
  ;; Each entry: (WORD-KEY . TARGET), where TARGET is either
  ;;   (:page TOMUS PAGE)         -- an exact PDF page, or
  ;;   (:after TOMUS NEIGHBOUR)   -- the page of a cleanly-detected
  ;;                                 neighbouring entry NEIGHBOUR (a
  ;;                                 collation key), used when the word's
  ;;                                 own headword is OCR-garbled but it
  ;;                                 sits right after a clean entry.
  ;; This is a hand-curated table for the handful of entries no automatic
  ;; signal (caps opening, index column, fuzzy match, prefix analysis)
  ;; can place correctly, yet whose location is known by eye.  Two kinds
  ;; occur: (a) an entry whose headword the OCR corrupts so badly it heads
  ;; no detectable line and has no usable index column (e.g. ἀντιλέγω);
  ;; and (b) a word whose index pointer leads only to a passing MENTION in
  ;; a dictionary volume while its real entry lives elsewhere -- typically
  ;; a supplementary entry in the volume V index (e.g. ψύλλος, whose
  ;; "τ.4 c.746" points into another article but whose Pulex entry is at
  ;; t.V p996).  It is consulted FIRST, so it wins over the general
  ;; resolution; because it only matches keys listed here, it can never
  ;; misroute a word it does not mention.
  ;;
  ;; ἀντιλέγω (contradico) is a sub-entry inside the λέγω article, the
  ;; last entry opening on t.II p319, but its headword is OCR-mangled to
  ;; "C.ANT Ιλέα" (the letters ντ are misread as νπ/υπ throughout the
  ;; passage), so it heads no detectable line and has no index column.
  ;; We anchor each to a cleanly-detected entry on its own page -- so the
  ;; target is expressed as a real neighbour, not a bare page number, and
  ;; tracks the book if it is re-scanned or re-paginated.  The list was
  ;; built by an out-of-order-entry scan (capital-initial lines with
  ;; grammatical apparatus whose key sorts wrong and is absent from the
  ;; index), then each candidate was confirmed by eye.
  '(("\u03b1\u03bd\u03c4\u03b9\u03bb\u03b5\u03b3\u03c9"                 ; αντιλεγω  (contradico)
     . (:after 2 "\u03b1\u03bc\u03c6\u03b9\u03bb\u03bf\u03b3\u03b5\u03c9"))       ; ~ αμφιλογεω   t.II p319
    ("\u03c0\u03c1\u03bf\u03bd\u03bf\u03b7\u03c4\u03b9\u03ba\u03bf\u03c3"          ; προνοητικος (OCR "Γρονοητικος")
     . (:after 2 "\u03c0\u03c1\u03bf\u03bd\u03bf\u03b7\u03c4\u03b9\u03ba\u03c9\u03c3"))  ; ~ προνοητικως t.II p554
    ("\u03b3\u03b5\u03b3\u03c1\u03b1\u03bc\u03bc\u03b5\u03bd\u03b7"                ; γεγραμμενη (OCR "Γραμμενη", lost redupl.)
     . (:after 1 "\u03c0\u03b1\u03c1\u03b1\u03b3\u03c1\u03b1\u03c6\u03b7"))         ; ~ παραγραφη   t.I p494
    ("\u03b1\u03c0\u03bf\u03b2\u03c1\u03c5\u03c4\u03bf\u03c3"                    ; αποβρυτος
     . (:after 3 "\u03b1\u03c0\u03bf\u03c1\u03c1\u03bf\u03b9\u03b1"))             ; ~ απορροια    t.III p346
    ("\u03b5\u03b3\u03c7\u03b1\u03c1\u03b1\u03be\u03b9\u03c3"                    ; εγχαραξις
     . (:after 4 "\u03c0\u03b1\u03c1\u03b1\u03c7\u03b1\u03c1\u03b1\u03ba\u03c4\u03b1\u03b9"))  ; ~ παραχαρακται t.IIII p200
    ("\u03c8\u03c5\u03bb\u03bb\u03bf\u03c3"                                ; ψυλλος (Pulex, the flea)
     . (:page 5 996))                                        ; supplementary entry, t.V p996
    ("\u03c8\u03c9\u03b1"                                    ; ψωα (Ψώα, Fœtor -- a stench)
     . (:page 5 996)))                                       ; entry OCR'd "Iwa"; t.V p996
  "Hand-curated overrides for entries the OCR corrupts beyond automatic reach.
See the source comment for the entry format and rationale.  Extend one
line at a time; each entry affects only the exact word-key it lists.")

(defun diogenes-tgl--override-locate (key)
  "Return (TOMUS . PAGE) for KEY from `diogenes-tgl--entry-overrides', or nil.
Resolves an `:after' anchor to the neighbour entry's actual detected
page, so the target tracks the real book rather than a fixed number."
  (let ((target (cdr (assoc key diogenes-tgl--entry-overrides))))
    (when target
      (pcase target
        (`(:page ,tomus ,page)
         (cons tomus (+ page diogenes-tgl-page-offset)))
        (`(:after ,tomus ,neighbour)
         (let ((page (diogenes-tgl--entry-page-in tomus neighbour)))
           (when page (cons tomus page))))))))

(defconst diogenes-tgl--denominative-suffixes
  ;; Each entry: (VERB-ENDING . LIST-OF-NOMINAL-ENDINGS).  A denominative
  ;; verb (Smyth, Greek Grammar Section 866) is built from a noun/adjective stem; to find
  ;; where the TGL files it we reverse the derivation, replacing the verbal
  ;; ending with the likely nominal ending(s) of its parent word and looking
  ;; that parent up.  Endings are collation keys (unaccented Greek).
  '(("\u03bf\u03c9"   . ("\u03bf\u03c3" "\u03b7" "\u03bf\u03bd"))                 ; -οω  <- -ος/-η/-ον  (factitive: δηλόω<δῆλος)
    ("\u03b1\u03c9"   . ("\u03b7" "\u03b1" "\u03bf\u03c3"))                       ; -αω  <- -η/-α/-ος    (τιμάω<τιμή)
    ("\u03b5\u03c9"   . ("\u03bf\u03c3" "\u03b7\u03c3" "\u03bf\u03bd"))           ; -εω  <- -ος/-ης      (οἰκέω<οἶκος, φιλέω<φίλος)
    ("\u03b5\u03c5\u03c9" . ("\u03b5\u03c5\u03c3" "\u03b7"))                      ; -ευω <- -ευς/-η      (βασιλεύω<βασιλεύς)
    ("\u03b9\u03b6\u03c9" . ("\u03bf\u03c3" "\u03b7" "\u03b9\u03c3" "\u03bc\u03b1")) ; -ιζω <- -ος/-ις/-μα (νομίζω<νόμος)
    ("\u03b1\u03b9\u03bd\u03c9" . ("\u03bf\u03c3" "\u03c9\u03bd" "\u03bc\u03b1")) ; -αινω <- -ος/-μα     (σημαίνω<σῆμα)
    ("\u03c5\u03bd\u03c9"   . ("\u03c5\u03c3" "\u03bf\u03c3")))                   ; -υνω <- -υς/-ος      (βαθύνω<βαθύς)
  "Reverse-derivation map for denominative verbs (Smyth Section 866).
Used by `diogenes-tgl--denominative-stems' as a LAST-resort way to
route a verb that has no entry of its own to the noun or adjective it
was formed from (e.g. μεστόω -> μεστός), when that parent has an
entry.  Each candidate is still required to resolve to a real
caps/index entry before being trusted, so a wrong reversal simply
yields nothing.  Longest verb-endings are tried first.")

(defun diogenes-tgl--denominative-stems (key)
  "Return candidate parent noun/adjective keys for a denominative verb KEY.
Reverses the Smyth Section 866 derivation: matches the longest applicable
verbal ending from `diogenes-tgl--denominative-suffixes' and swaps in
each plausible nominal ending.  Only the single longest-matching
verbal ending is used (so -ευω is tried as -ευω, not also as -ω).
Every candidate is at least `diogenes-tgl-morph-min-root' long."
  (let ((min diogenes-tgl-morph-min-root)
        (out nil))
    (cl-dolist (entry (sort (copy-sequence diogenes-tgl--denominative-suffixes)
                            (lambda (a b) (> (length (car a)) (length (car b))))))
      (let ((vend (car entry)))
        (when (and (string-suffix-p vend key)
                   (> (length key) (length vend)))
          (let ((base (substring key 0 (- (length key) (length vend)))))
            (dolist (nend (cdr entry))
              (let ((cand (concat base nend)))
                (when (and (>= (length cand) min) (not (member cand out)))
                  (push cand out)))))
          ;; Only the longest matching verbal ending; stop after it.
          (cl-return))))
    (nreverse out)))

(defconst diogenes-tgl--reduplicated-stems
  '(("\u03c0\u03b9\u03c6\u03b1\u03c5" . "\u03c6\u03b1\u03c3\u03ba\u03c9")   ; πιφαυ (πιφαύσκω) -> ΦΑΣΚΩ
    ("\u03c0\u03b9\u03c6\u03b1"     . "\u03c6\u03b1\u03c3\u03ba\u03c9"))   ; πιφα  (OCR-dropped υ) -> ΦΑΣΚΩ
  "Explicit map from a reduplicated present's stem-onset to a root key.
Greek reduplicated presents (Attic πι-/γι-/δι-/τι-, etc.) are filed in
the TGL under their root, but the surface form gives no letter-based
route there (πιφαύσκω belongs in the φ volume yet is π-initial) and its
reduplication cannot be stripped by a general rule without also
mangling the many ordinary words that merely begin with the same
letters (πίστις, πικρός, πίθος …).  This table is therefore
DELIBERATELY SPECIFIC: each key is a reduplicated stem-onset long
enough to be unique to its verb family, mapped to the collation key of
a root that (a) is in the right volume and (b) resolves cleanly (has a
caps opening or an exact index reference).  For the πιφαύσκω/πιφάσκω
group the mapped root is φάσκω: Estienne prints \"ΦΑΣΚΩ, … & per
reduplicationem Πιφαύσκω\" as the headword of the very entry that then
discusses πιφαύσκω at length (t.IIII), and ΦΑΣΚΩ is captured as a caps
opening, so the lookup lands on that exact page.  Entries are matched
longest-first; extend one line at a time, and because each key is an
onset unique to its verb, adding one cannot misroute unrelated words.")

(defun diogenes-tgl--reduplicated-root (key)
  "Return the root key for a reduplicated-present KEY, or nil.
Consults `diogenes-tgl--reduplicated-stems', matching the longest
stem-onset that is a prefix of KEY."
  (cl-loop for (stem . root) in
           (sort (copy-sequence diogenes-tgl--reduplicated-stems)
                 (lambda (a b) (> (length (car a)) (length (car b)))))
           when (string-prefix-p stem key)
           return root))

(defun diogenes-tgl--morph-locate-key (key index)
  "Resolve KEY through reduplication analysis or prefix stripping, or nil.
FIRST honours an explicit reduplicated-present mapping
\(`diogenes-tgl--reduplicated-stems': e.g. πιφαύσκω -> φάσκω), resolving
that root by its caps opening or index entry -- this places
reduplicated verbs, which are filed under their root in another volume
and which general prefix stripping cannot and must not touch.

Otherwise, for each prefix-strip root candidate (see
`diogenes-tgl--root-candidates') tries, in order, the root's all-caps
entry opening in any volume, then an EXACT, volume-consistent index
reference for the root (via `diogenes-tgl--index-locate-key', so the
same letter-routed-volume filter applies -- a root candidate is
accepted only when it is filed under its own initial letter).  A root
candidate is resolved preferentially by its caps opening, then an
EXACT own-volume index hit; only if NO candidate yields either does a
second pass allow a volume-consistent FUZZY index hit on a candidate
\(for a root whose own headword the OCR garbled and which is nested
without a caps line, e.g. πίμπλημι, printed \"Πίμπλημι\" under πλήθω --
so καταπίμπλημι resolves through it into the correct volume).  Returns
\(TOMUS PAGE COLUMN LETTER ROOT); COLUMN/LETTER are nil for a
caps-opening hit.  Honours `diogenes-tgl-morph-fallback'."
  (when (and diogenes-tgl-morph-fallback (> (length key) 0))
    (let ((cands (diogenes-tgl--root-candidates key))
          (result nil))
      ;; Step 0: explicit reduplicated-present mapping (most specific).
      ;; Resolve the mapped root by its caps opening, then an EXACT index
      ;; hit only -- never fuzzy, so a garbled near-neighbour (e.g. φαθω
      ;; at col 7) cannot hijack it; the table's root is chosen precisely
      ;; because it resolves cleanly.
      (let ((rroot (diogenes-tgl--reduplicated-root key)))
        (when rroot
          (let ((c (diogenes-tgl--caps-locate-any rroot)))
            (if c
                (setq result (list (car c) (cdr c) nil nil rroot))
              (let ((hit (diogenes-tgl--index-locate-key rroot index 'exact-only)))
                (when hit
                  (cl-destructuring-bind (vol page col letter kind) hit
                    (ignore kind)
                    (setq result (list vol page col letter rroot)))))))))
      ;; Pass 1: definitive resolutions (caps opening, then exact index),
      ;; preferred for every candidate before any fuzzy guess is considered.
      (unless result
        (cl-dolist (cand cands)
          (let ((c (diogenes-tgl--caps-locate-any cand)))
            (when c
              (setq result (list (car c) (cdr c) nil nil cand))
              (cl-return)))
          (let ((hit (diogenes-tgl--index-locate-key cand index 'exact-only)))
            (when hit
              (cl-destructuring-bind (vol page col letter kind) hit
                (ignore kind)
                ;; CHECKED against the page.  The index gives the relative
                ;; pronoun a column on a page of `ὄρος' -- the rho lost to the
                ;; OCR leaves a key that still looks like a word -- and an
                ;; unchecked hit is definitive, so it won.  A page whose own
                ;; range is nowhere near the key cannot hold it.
                (when (diogenes-tgl--page-holds-key-p vol page cand)
                  (setq result (list vol page col letter cand))
                  (cl-return)))))))
      ;; Pass 1.5: denominative reduction (Smyth Section 866).  If no prefix
      ;; candidate resolved, try the noun/adjective a denominative verb was
      ;; built from (μεστόω -> μεστός, δηλόω -> δῆλος), resolving each parent
      ;; DEFINITIVELY (caps opening or exact own-volume index).  Gated the
      ;; same way, so a reversal onto a non-existent stem yields nothing.
      (unless result
        (cl-dolist (cand (diogenes-tgl--denominative-stems key))
          (let ((c (diogenes-tgl--caps-locate-any cand)))
            (when c
              (setq result (list (car c) (cdr c) nil nil cand))
              (cl-return)))
          (let ((hit (diogenes-tgl--index-locate-key cand index 'exact-only)))
            (when hit
              (cl-destructuring-bind (vol page col letter kind) hit
                (ignore kind)
                ;; CHECKED against the page.  The index gives the relative
                ;; pronoun a column on a page of `ὄρος' -- the rho lost to the
                ;; OCR leaves a key that still looks like a word -- and an
                ;; unchecked hit is definitive, so it won.  A page whose own
                ;; range is nowhere near the key cannot hold it.
                (when (diogenes-tgl--page-holds-key-p vol page cand)
                  (setq result (list vol page col letter cand))
                  (cl-return)))))))
      ;; Pass 2: only if nothing definitive, allow a volume-consistent fuzzy
      ;; index hit on a candidate (`index-locate-key' without EXACT-ONLY
      ;; still applies the own-letter-volume filter, so a fuzzy hit is
      ;; accepted only when it lies in the candidate's own volume).
      (unless result
        (cl-dolist (cand cands)
          (let ((hit (diogenes-tgl--index-locate-key cand index nil)))
            (when hit
              (cl-destructuring-bind (vol page col letter kind) hit
                (ignore kind)
                (setq result (list vol page col letter cand))
                (cl-return))))))
      result)))

(defun diogenes-tgl--page-holds-key-p (tomus page key)
  "Whether PAGE of TOMUS plausibly holds KEY, by the page\='s own key range.
The body index records what each page begins and ends with, `:lo\=' and `:hi\=',
and a page whose range is nowhere near KEY cannot hold it however confidently an
index says so.

Compared on the first TWO letters, not the whole key: a page\='s range is read
from its running heads, which are abbreviated -- `ΟΡΟ\=' for a page of `ὄρος\=' --
so a stricter comparison would reject good pages, and a looser one (the first
letter alone) would accept the whole of a letter\='s hundreds of pages.

Nil where there is no body index for the volume, in which case nothing can be
checked and the caller should trust what it has."
  (let* ((body (diogenes-tgl--body tomus))
         (pages (and body (plist-get body :pages))))
    (if (or (null pages) (zerop (length pages)))
        t                               ; nothing to check against
      (let* ((want (substring key 0 (min 2 (length key))))
             (pg (cl-loop for p across pages
                          when (equal (plist-get p :page) page)
                          return p)))
        (if (null pg)
            t                           ; the page is not in the index either
          (let* ((lo (or (plist-get pg :lo) ""))
                 (hi (or (plist-get pg :hi) ""))
                 (lo2 (substring lo 0 (min 2 (length lo))))
                 (hi2 (substring hi 0 (min 2 (length hi)))))
            ;; Within the page\='s own two-letter span, inclusive, and in either
            ;; order: a page\='s `:lo\=' and `:hi\=' come from the OCR and are not
            ;; always the right way round.
            (or (and (not (string< want lo2)) (not (string< hi2 want)))
                (and (not (string< want hi2)) (not (string< lo2 want))))))))))

(defun diogenes-tgl--index-locate-key (key index &optional exact-only)
  "Resolve collation KEY through parsed INDEX, or nil.
Returns (TOMUS PAGE COLUMN LETTER MATCH-KIND), MATCH-KIND being
`exact' or `fuzzy'.

A root's own entry, when the index lists it at all, is filed under
the root's OWN initial letter, so its reference volume equals the
volume that letter routes to (`diogenes-tgl--tomus-for-key').  Any
reference to the word from a DIFFERENT volume comes from a derived
word that lives there (e.g. the alpha-privative ἀλογία mentions
λόγος while pointing into the alpha volume) and is at best an
approximate hint, never the root's location.  We therefore keep only
the references whose volume matches KEY's letter-routed volume; if
none remain, the index does not actually contain this word's own
entry and we return nil (the caller then tries caps/body, or the
cross-volume hint as a last resort).  Among the kept references we
take the SMALLEST column, which is the entry's opening (a larger
column for the same word is a later subsection).

An exact headword match and a 1-edit fuzzy match are handled the
same way -- both are subject to the volume filter -- so a garbled
fuzzy hit belonging to another volume is naturally discarded.  With
EXACT-ONLY non-nil no fuzzy match is attempted.  Cross-reference
lines carry no column and never resolve here."
  (when (> (length key) 0)
    (let* ((refs (plist-get index :refs))
           (owner (diogenes-tgl--tomus-for-key key))
           (kind 'exact)
           (rec (or (gethash key refs)
                    (unless exact-only
                      (let ((fk (diogenes-tgl--fuzzy-key key index)))
                        (when fk (setq kind 'fuzzy) (gethash fk refs)))))))
      (when (and rec owner)
        ;; Keep only references in the word's own (letter-routed) volume.
        (let* ((same (cl-remove-if-not (lambda (r) (= (nth 0 r) owner)) rec))
               (model (and same (diogenes-tgl--column-model
                                  (diogenes-tgl--volume-text owner))))
               ;; Page (with offset) each kept ref resolves to.
               (cands (and model
                           (delq nil
                                 (mapcar
                                  (lambda (r)
                                    (let ((p (diogenes-tgl--column-to-page
                                              (nth 1 r) model)))
                                      (when p
                                        (list :vol (nth 0 r) :col (nth 1 r)
                                              :letter (nth 2 r)
                                              :page (+ p diogenes-tgl-page-offset)))))
                                  same))))
               (best
                (cond
                 ((null cands) nil)
                 ((= (length cands) 1) (car cands))
                 (t
                  ;; Several references for one key.  The naive "smallest
                  ;; column is the entry opening" breaks when a GARBLED index
                  ;; headword in a foreign alphabetical region injects a
                  ;; spurious column onto this word (e.g. `Αὐτὸς,ibid.' misread
                  ;; among the αἰπ- entries files αυτος at c.176 -> p144,
                  ;; masking the real c.604 -> p358; and the outlier is not
                  ;; always the smallest -- ἆθλος has a spurious LARGE column,
                  ;; and ἀγανός a spurious c.7 at the very start of alpha).
                  ;; Pick the reference the volume itself corroborates, in
                  ;; order of decreasing reliability:
                  ;;   1. a reference whose page carries KEY as an ALL-CAPS
                  ;;      article header (`diogenes-tgl--caps-opening', the
                  ;;      authoritative entry opening) -- exact and decisive;
                  ;;   2. else the reference nearest KEY's running-header
                  ;;      position (`diogenes-tgl--approx-locate'), which places
                  ;;      the word alphabetically even without an all-caps head
                  ;;      (e.g. αὐτός, printed mixed-case);
                  ;;   3. else the smallest column (the usual opening).
                  (let* ((caps-page
                          (let ((cp (ignore-errors
                                     (diogenes-tgl--caps-opening owner key))))
                            (and cp (+ cp diogenes-tgl-page-offset))))
                         (corrob (and caps-page
                                      (cl-remove-if-not
                                       (lambda (c) (<= (abs (- (plist-get c :page)
                                                               caps-page)) 1))
                                       cands)))
                         (anchor (unless corrob
                                   (let ((b (ignore-errors
                                             (diogenes-tgl--approx-locate key))))
                                     (and b (= (car b) owner) (cdr b))))))
                    (cond
                     (corrob
                      (car (sort corrob
                                 (lambda (a b) (< (plist-get a :col)
                                                  (plist-get b :col))))))
                     (anchor
                      (car (sort (copy-sequence cands)
                                 (lambda (a b)
                                   (let ((da (abs (- (plist-get a :page) anchor)))
                                         (db (abs (- (plist-get b :page) anchor))))
                                     (if (= da db)
                                         (< (plist-get a :col) (plist-get b :col))
                                       (< da db)))))))
                     (t
                      (car (sort (copy-sequence cands)
                                 (lambda (a b)
                                   (< (plist-get a :col)
                                      (plist-get b :col))))))))))))
          (when best
            (list (plist-get best :vol)
                  (plist-get best :page)
                  (plist-get best :col)
                  (plist-get best :letter)
                  kind)))))))

(defvar diogenes-tgl--index-pagekeys-cache (make-hash-table :test 'equal)
  "Cache mapping volume V's OCR cache-key to its (REPKEY . PAGE) sequence.")

(defun diogenes-tgl--robust-representative (keys)
  "Return a noise-robust representative key for a page's KEYS, or nil.
Take the modal initial letter across KEYS, then the median key among
those that share it -- so a handful of OCR-scrambled lines whose keys
begin with an alien letter cannot drag the representative to the wrong
part of the alphabet."
  (when keys
    (let ((counts (make-hash-table :test 'eql)) (modal nil) (best 0))
      (dolist (k keys)
        (when (> (length k) 0)
          (let ((c (aref k 0)))
            (puthash c (1+ (gethash c counts 0)) counts))))
      (maphash (lambda (c n) (when (> n best) (setq modal c best n))) counts)
      (when modal
        (let ((same (sort (cl-remove-if-not
                           (lambda (k) (and (> (length k) 0) (eql (aref k 0) modal)))
                           keys)
                          #'string<)))
          (when same (nth (/ (length same) 2) same)))))))

(defun diogenes-tgl--index-pagekeys (file)
  "Return the volume-V index page-key data for FILE.
The value is a plist:
  (:seq ((REPRESENTATIVE-KEY . PDF-PAGE) ...)   ; page-ordered
   :perpage HASH)                               ; PDF-PAGE -> sorted key list

The representative key of each page is noise-robust (see
`diogenes-tgl--robust-representative'): the modal initial letter's
median key, so a few OCR-scrambled lines cannot skew a page into the
wrong part of the alphabet.  :seq drives the COARSE page estimate;
:perpage drives the FINE within-window refinement (see
`diogenes-tgl--where-in-index').  Both index parts are included -- the
index is printed in two parts that together run the whole alphabet
\(alpha--pi, then rho--omega) -- because positioning is done per-letter
rather than by one global scan."
  (let ((ck (diogenes-tgl--file-cache-key file)))
    (or (gethash ck diogenes-tgl--index-pagekeys-cache)
        (setf (gethash ck diogenes-tgl--index-pagekeys-cache)
              (with-temp-buffer
                (insert-file-contents file)
                (goto-char (point-min))
                (when (search-forward diogenes-tgl--index-marker nil t)
                  (forward-line 1))
                (let ((marker diogenes-tgl-page-marker-regexp)
                      (pdfp nil) (perpage (make-hash-table :test 'eql)))
                  (while (not (eobp))
                    (let ((line (buffer-substring-no-properties
                                 (line-beginning-position) (line-end-position))))
                      (if (string-match marker line)
                          (setq pdfp (string-to-number (match-string 1 line)))
                        (when (and pdfp
                                   (string-match
                                    diogenes-tgl--line-start-gword-regexp line))
                          (let ((k (diogenes-montanari--greek-key
                                    (match-string 1 line))))
                            (when (>= (length k) 3)
                              (push k (gethash pdfp perpage)))))))
                    (forward-line 1))
                  (let (seq)
                    (maphash
                     (lambda (page keys)
                       (let ((sorted (sort keys #'string<)))
                         (puthash page sorted perpage) ; store sorted for fine step
                         (let ((rep (diogenes-tgl--robust-representative sorted)))
                           (when rep (push (cons rep page) seq)))))
                     perpage)
                    (list :seq (sort seq (lambda (a b) (< (cdr a) (cdr b))))
                          :perpage perpage))))))))

(defun diogenes-tgl--where-in-index (word)
  "Return (5 . PAGE) for where WORD's entry falls in volume V, or nil.
Estimates WORD's alphabetical position among the volume-V index
headwords (a robust coarse page, then a fine within-window refinement).
A supplementary index entry or a t.5 index reference is used in
preference ONLY when it agrees with that estimate's neighbourhood --
otherwise it is ignored: the index apparatus mentions a word (e.g. a
gloss or a `vide') on pages far from where the word itself falls
alphabetically, and following such an incidental mention would jump to
the wrong letter.  Intended for the manual-check `i' key, not the main
resolver."
  (let* ((index (diogenes-tgl--index))
         (key (diogenes-montanari--greek-key word)))
    (when (> (length key) 0)
      (let ((estimate
             ;; two-step alphabetical estimate: COARSE vicinity, then FINE.
             (let ((file (diogenes-tgl--volume-text 5)))
               (when file
                 (let* ((data (diogenes-tgl--index-pagekeys file))
                        (coarse (diogenes-tgl--index-coarse-page
                                 key (plist-get data :seq))))
                   (when coarse
                     (+ (or (diogenes-tgl--index-fine-page
                             key coarse (plist-get data :perpage))
                            coarse)
                        diogenes-tgl-page-offset))))))
            (candidate-exact
             ;; A candidate strong enough to OVERRIDE the alphabetical
             ;; estimate: an EXACT supplementary-entry match, or a t.5
             ;; reference.  A *fuzzy* entry match is deliberately excluded
             ;; here -- a 1-edit neighbour (e.g. `αυτον' for `αυτοσ') is
             ;; often a different real word glossed in another part of the
             ;; same letter, and must not displace a clean estimate.
             (or (let ((entries (plist-get index :entries)))
                   (and entries
                        (let ((p (gethash key entries)))
                          (and p (+ p diogenes-tgl-page-offset)))))
                 (let* ((rec (gethash key (plist-get index :refs)))
                        (five (cl-find 5 rec :key #'car)))
                   (when five
                     (let ((model (diogenes-tgl--column-model
                                   (diogenes-tgl--volume-text 5))))
                       (when model
                         (+ (diogenes-tgl--column-to-page (nth 1 five) model)
                            diogenes-tgl-page-offset)))))))
            (candidate-any
             ;; A harvested supplementary entry, exact or a 1-edit neighbour,
             ;; used ONLY when there is no alphabetical estimate at all.
             ;;
             ;; A t.5 REFERENCE is deliberately not a fallback here.  The
             ;; clause below admits one only when the estimate agrees with
             ;; it, for the reason this function's docstring gives: the index
             ;; apparatus mentions a word in a gloss or a `vide' on pages far
             ;; from where the word itself falls, so an uncorroborated
             ;; reference lands in the wrong letter.  With no estimate there
             ;; is nothing to corroborate it, and no page is a better answer
             ;; than a page in the wrong letter -- the caller says "could not
             ;; place" and the reader looks for themselves.
             ;;
             ;; And an exact entry needs no mention here: it is what
             ;; `--index-entry-locate' returns first.
             (let ((e (diogenes-tgl--index-entry-locate key index)))
               (and e (cdr e)))))
        (cond
         ;; Trust the harvested page only when it is an EXACT entry/ref AND
         ;; sits in the estimate's neighbourhood (same letter region);
         ;; otherwise it is an incidental mention and the alphabetical
         ;; estimate is the right place.
         ((and candidate-exact estimate
               (<= (abs (- candidate-exact estimate))
                   diogenes-tgl-index-entry-agree-window))
          (cons 5 candidate-exact))
         (estimate (cons 5 estimate))
         ;; No estimate (letter absent from the index): fall back to any
         ;; harvested page if we have one -- better than nothing.
         (candidate-any (cons 5 candidate-any))
         (t nil))))))

(defcustom diogenes-tgl-index-entry-agree-window 40
  "How near, in pages, a harvested index entry/reference must be to the estimate.
The `i' key estimates a word's alphabetical place in the volume-V
index; a supplementary entry or a t.5 reference for the word is only
preferred over that estimate when within this many pages of it.
Farther away it is treated as an incidental mention (a gloss or a
`vide' printed under another lemma) and ignored."
  :type 'integer
  :group 'diogenes-tgl)

(defun diogenes-tgl--index-coarse-page (key seq)
  "Coarse step: return the vicinity PAGE for KEY from SEQ, or nil.
SEQ is the page-ordered ((REPRESENTATIVE-KEY . PAGE) ...) list.
Positioning is confined to the pages whose representative begins with
KEY's initial letter, and among those to the LARGEST contiguous run
\(the letter's real index block, so a lone mis-OCR'd page elsewhere
cannot capture the lookup).  Within that block, return the last page
whose representative is <= KEY, else the block's first page."
  (when (> (length key) 0)
    (let* ((l (aref key 0))
           (pages (cl-remove-if-not
                   (lambda (rk) (and (> (length (car rk)) 0)
                                     (eql (aref (car rk) 0) l)))
                   seq)))
      (when pages
        (let ((runs nil) (cur (list (car pages))))
          (dolist (rk (cdr pages))
            (if (<= (- (cdr rk) (cdr (car cur))) 4)
                (push rk cur)
              (push (nreverse cur) runs)
              (setq cur (list rk))))
          (push (nreverse cur) runs)
          (let* ((block (car (sort runs (lambda (a b) (> (length a) (length b))))))
                 (best (cdr (car block))))
            (dolist (rk block)
              (when (not (string< key (car rk)))  ; (car rk) <= key
                (setq best (cdr rk))))
            best))))))

(defcustom diogenes-tgl-index-fine-window 3
  "Half-width, in pages, of the fine-refinement window for the `i' key.
After the coarse step lands on a vicinity page, the fine step examines
this many pages either side to pick the page where the word actually
falls."
  :type 'integer
  :group 'diogenes-tgl)

(defun diogenes-tgl--index-fine-page (key center perpage)
  "Fine step: refine to the page that actually prints KEY, near CENTER, or nil.
PERPAGE maps a PDF page to its sorted headword-key list.  Considers the
pages within `diogenes-tgl-index-fine-window' of CENTER.

A TGL index page has two OCR-interleaved columns, so its span of keys
covers almost the whole letter and cannot bracket a word by min/max.
But the words sharing KEY's own leading letters cluster on the single
page where that article is printed.  So we pick the page carrying the
most headwords that share KEY's initial prefix, trying a 4-, then 3-,
then 2-letter prefix (a shorter prefix still catches the article when a
word's exact neighbours are OCR-mangled).  If no page in the window
shares even a 2-letter prefix (a rare or badly scanned word), fall back
to the crossover page: the last page where at least half of its
initial-letter keys are <= KEY.  Returns CENTER if nothing is usable."
  (when (and (integerp center) perpage (> (length key) 0))
    (let ((w (max 0 diogenes-tgl-index-fine-window)))
      (or
       ;; prefix-cluster page, longest prefix first
       (cl-loop for plen in '(4 3 2)
                when (>= (length key) plen)
                thereis
                (let ((pfx (substring key 0 plen)) (best nil) (bestc 0))
                  (cl-loop for pg from (- center w) to (+ center w) do
                           (let ((c 0))
                             (dolist (k (gethash pg perpage))
                               (when (and (>= (length k) plen)
                                          (string= (substring k 0 plen) pfx))
                                 (setq c (1+ c))))
                             (when (> c bestc) (setq bestc c best pg))))
                  (and best (> bestc 0) best)))
       ;; fallback: crossover on the initial letter
       (let ((l (aref key 0)) (best center) (found nil))
         (cl-loop for pg from (- center w) to (+ center w) do
                  (let ((same (cl-remove-if-not
                               (lambda (k) (and (> (length k) 0) (eql (aref k 0) l)))
                               (gethash pg perpage))))
                    (when same
                      (let ((below (cl-count-if
                                    (lambda (k) (not (string< key k))) same)))
                        (when (>= (* 2 below) (length same))
                          (setq best pg found t))))))
         (and found best))
       center))))

(defun diogenes-tgl--index-entry-locate (key index)
  "Return (5 . PAGE) for KEY as a supplementary volume-V index entry, or nil.
Volume V's index carries its own glossed lemma entries for words
absent from the four dictionary volumes (see
`diogenes-tgl--index-entry-apparatus-regexp').  These were harvested
to their volume-V page in `:entries'.  Exact match first, then a
1-edit fuzzy match over the entry keys, to absorb single-letter OCR
damage in the harvested headword."
  (when (>= (length key) 3)
    (let ((entries (plist-get index :entries)))
      (when entries
        (let ((page (gethash key entries)))
          (if page
              (cons 5 (+ page diogenes-tgl-page-offset))
            (let ((fk (diogenes-tgl--fuzzy-in-map key entries)))
              (when fk
                (cons 5 (+ (gethash fk entries) diogenes-tgl-page-offset))))))))))

(defun diogenes-tgl--index-hint-key (key index)
  "Return an APPROXIMATE (TOMUS PAGE COLUMN) from cross-volume index hints, or nil.
Used only as a last resort for a word the index does not list under
its own letter: its references then all come from derived words in
other volumes.  We take the reference whose volume matches the LEAST
unreasonable guess -- the smallest column in the most-referenced
other volume -- purely to land the reader in the right neighbourhood.
Never used when a same-volume reference, caps opening, or body match
exists."
  (when (> (length key) 0)
    (let ((rec (gethash key (plist-get index :refs))))
      (when rec
        ;; Most-referenced volume among the hints.
        (let ((counts (make-hash-table :test 'eql)))
          (dolist (r rec) (puthash (nth 0 r) (1+ (gethash (nth 0 r) counts 0)) counts))
          (let ((bestvol nil) (bestn 0))
            (maphash (lambda (v n) (when (> n bestn) (setq bestvol v bestn n))) counts)
            (when bestvol
              (let* ((invol (cl-remove-if-not (lambda (r) (= (nth 0 r) bestvol)) rec))
                     (col (apply #'min (mapcar (lambda (r) (nth 1 r)) invol)))
                     (txt (diogenes-tgl--volume-text bestvol))
                     (page (and txt
                                (diogenes-tgl--column-to-page
                                 col (diogenes-tgl--column-model txt)))))
                (when page
                  (list bestvol (+ page diogenes-tgl-page-offset) col))))))))))

(defun diogenes-tgl--locate (word)
  "Locate WORD in the TGL.  Return a plist or nil.

Resolution order (most authoritative first):
  1. CAPS OPENING: the first page whose left-margin ALL-CAPS entry is
     WORD, in the volume WORD's initial letter routes to -> :via
     `caps'.  A caps headword is the first line of its article, so
     this is the true entry opening -- preferred over an index column,
     which for long roots often points mid-article.
  2. INDEX, EXACT reference in WORD's own (letter-routed) volume, at
     its smallest column (the entry opening)                -> :via `index';
  3. INDEX, FUZZY reference in WORD's own volume             -> :via `index';
  4. INDEX \"vide in <root>\" cross-reference (one hop)     -> :via `xref';
  5. MORPHOLOGY: strip one prefix, resolve the root by its
     caps opening or an exact own-volume index hit          -> :via `morph';
  6. BODY scan by initial letter                            -> :via `body';
  7. CROSS-VOLUME index HINT (references from derived words in
     other volumes) -- approximate only                     -> :via `hint'.

The word's OWN index entry -- whether matched exactly (2) or through
a 1-edit OCR wobble in its headword (3) -- ranks ABOVE the vide (4)
and morphological (5) paths, because those only INFER where a related
root sits, whereas an own-volume index reference is the word's own
entry.  Steps 2, 3 and 5 keep only references whose volume matches
WORD's own initial letter, since a root's entry is filed under its
own letter; a reference from another volume belongs to a derived word
and is demoted to the approximate step 7.

The plist always has :tomus and :page.  Index/xref/morph hits add
:column, :letter and :match (`exact'/`fuzzy') when applicable; xref
and morph hits also add :root (the collation key jumped through);
the step-7 hint adds :column.  Returns nil only when WORD is found by
none of these and its volume/letter is uninstalled."
  (diogenes-tgl--maybe-load-prebuilt-index)
  (let* ((index (diogenes-tgl--index))
         (key (diogenes-montanari--greek-key word)))
    (when (> (length key) 0)
      (or
       ;; 0. Hand-curated override for entries the OCR corrupts beyond
       ;;    automatic reach (see `diogenes-tgl--entry-overrides').  First,
       ;;    so it wins; matches only explicitly-listed keys.
       (let ((o (diogenes-tgl--override-locate key)))
         (when o
           (list :via 'override :tomus (car o) :page (cdr o))))
       ;; 1. Caps-entry opening in the word's own volume (authoritative
       ;;    start of a root article; beats a mid-article index column).
       (let ((c (diogenes-tgl--caps-locate key)))
         (when c
           (list :via 'caps :tomus (car c) :page (cdr c))))
       ;; 2. Direct EXACT index hit in the word's own volume -- CHECKED
       ;;    against the page it names.  The index gives the relative pronoun
       ;;    column 1470, page 749, whose running heads read `ΟΡΟ': `ὄρος' on
       ;;    those pages, its rho lost to the OCR, leaves the key `οσ'.  Short
       ;;    keys suffer this most, so it is a class and not a one-off.
       (let ((hit (diogenes-tgl--index-locate-key key index 'exact-only)))
         (when (and hit
                    (diogenes-tgl--page-holds-key-p (nth 0 hit) (nth 1 hit) key))
           (cl-destructuring-bind (tomus page col letter kind) hit
             (list :via 'index :tomus tomus :page page
                   :column col :letter letter :match kind))))
       ;; 2b. Compound ("C.") entry.  A word marked "C." heads its own line,
       ;;     so this is its entry page -- a locator, and it correctly follows
       ;;     the compound into whatever volume its root lives in (unlike the
       ;;     letter-routed body scan).  Ranks above fuzzy index / vide /
       ;;     morph because those only infer a related root's position; ranks
       ;;     below the exact index so a clean own-entry still wins.
       (let ((c (diogenes-tgl--compound-locate key)))
         (when c
           (list :via 'compound :tomus (car c) :page (cdr c))))
       ;; 3. FUZZY index hit in the word's own volume.  This is still the
       ;;    word's OWN entry (its headword merely OCR-garbled by a letter),
       ;;    so per the index principle it outranks any cross-reference or
       ;;    prefix-analysis, which only infer where a *related* root sits.
       (let ((hit (diogenes-tgl--index-locate-key key index nil)))
         (when (and hit
                    (diogenes-tgl--page-holds-key-p (nth 0 hit) (nth 1 hit) key))
           (cl-destructuring-bind (tomus page col letter kind) hit
             (list :via 'index :tomus tomus :page page
                   :column col :letter letter :match kind))))
       ;; 4. "vide in <root>": resolve the root through the index (one hop).
       ;;    An approximation, so resolve the root only DEFINITIVELY (caps
       ;;    opening or an EXACT own-volume hit) -- never fuzz-on-fuzz.
       (let ((root (gethash key (plist-get index :vide))))
         (when (and root (not (string= root key)))
           (or (let ((c (diogenes-tgl--caps-locate root)))
                 (when c
                   (list :via 'xref :tomus (car c) :page (cdr c) :root root)))
               (let ((hit (diogenes-tgl--index-locate-key root index 'exact-only)))
                 (when hit
                   (cl-destructuring-bind (tomus page col letter kind) hit
                     (list :via 'xref :tomus tomus :page page
                           :column col :letter letter :match kind
                           :root root)))))))
       ;; 4b. Comprehensive entry map: the word's OWN Capital-initial entry
       ;;     with apparatus, anywhere in vols I-IV (e.g. Προαίρεσις, whose
       ;;     index pointer is OCR-garbled).  Ranks above morphology because
       ;;     a word's own entry beats being sent to its root; ranks below
       ;;     the index because a clean column is more precise.  Safe here as
       ;;     its key is the entry's own headword -- it can only resolve a
       ;;     word to its own entry, never to a different word.
       (let ((e (diogenes-tgl--entry-locate key)))
         (when e
           (list :via 'entry :tomus (car e) :page (cdr e))))
       ;; 4c. Supplementary volume-V index entry, EXACT match only: the
       ;;     word's OWN glossed lemma inside volume V's index (drawn from
       ;;     Hesychius etc.).  An exact own-listing must rank ABOVE the
       ;;     morphological fallback below -- which only INFERS that the
       ;;     word sits wherever its prefix-stripped root sits (it would
       ;;     otherwise send ἀμορία to μορία in another volume).  Only the
       ;;     EXACT match is promoted here; a 1-edit fuzzy V-index guess
       ;;     stays below morph (step 5c) so a solid root resolution is not
       ;;     overridden by an approximate index hit.  Ranks below the real
       ;;     vols-I-IV routes (caps, index column, compound, entry map),
       ;;     so a genuine dictionary article still wins.
       (let* ((entries (plist-get index :entries))
              (page (and entries (>= (length key) 3) (gethash key entries))))
         (when page
           (list :via 'index-entry :tomus 5
                 :page (+ page diogenes-tgl-page-offset))))
       ;; 5. Morphological fallback: strip one prefix, resolve the root by
       ;;    its caps opening or an EXACT own-volume index hit (never fuzzy).
       ;;    Catches bare compounds the index neither columns nor
       ;;    cross-references (e.g. διαλέγω -> λέγω, καταλαμβάνω -> λαμβάνω).
       (let ((hit (diogenes-tgl--morph-locate-key key index)))
         (when hit
           (cl-destructuring-bind (tomus page col letter root) hit
             (list :via 'morph :tomus tomus :page page
                   :column col :letter letter
                   :match (if col 'exact nil) :root root))))
       ;; 5b. "Vnde/Inde" derived entry.  A word that exists only as an
       ;;     explicit derivation inside its root's article (capital-initial,
       ;;     with real apparatus) is genuinely located on that page -- so it
       ;;     beats the alphabetical body guess below, though it ranks under
       ;;     the index/compound/morph routes, which are stronger when they
       ;;     apply.  Catches e.g. ἐγχάραγμα, filed under χαράσσω.
       (let ((v (diogenes-tgl--vnde-locate key)))
         (when v
           (list :via 'vnde :tomus (car v) :page (cdr v))))
       ;; 5c. Supplementary volume-V index entry, FUZZY fallback.  The
       ;;     exact case was already tried above morph (4c); this catches a
       ;;     1-edit OCR-garbled V-index headword, ranked here (below the
       ;;     morph/vnde inferences) so an approximate index hit does not
       ;;     override a solid root resolution.  Still beats the body guess.
       (let ((e (diogenes-tgl--index-entry-locate key index)))
         (when e
           (list :via 'index-entry :tomus (car e) :page (cdr e))))
       ;; 5d. Anomalous-roots EXACT match (volume V's "Verborum quorundam
       ;;     themata"): many anomalous/poetic verb forms are absent from
       ;;     the four dictionary volumes and the main index but listed
       ;;     here.  Exact-only, and below every real route above, so it
       ;;     only ever catches a word nothing else could place -- never
       ;;     hijacking a word that belongs elsewhere.  Beats the body guess.
       (let ((e (diogenes-tgl--anomalous-locate-exact key)))
         (when e
           (list :via 'anomalous :tomus (car e) :page (cdr e))))
       ;; 6. Body scan by initial letter.
       (let ((b (diogenes-tgl--body-locate word)))
         (when b
           (list :via 'body :tomus (car b) :page (cdr b))))
       ;; 7. Last resort: cross-volume index hints (references to this
       ;;    word from DERIVED words in other volumes).  Only an
       ;;    approximate neighbourhood, never definitive -- flagged as
       ;;    such in the message so the reader knows to look around.
       (let ((h (diogenes-tgl--index-hint-key key index)))
         (when h
           (cl-destructuring-bind (tomus page col) h
             (list :via 'hint :tomus tomus :page page :column col))))))))

;;;; --------------------------------------------------------------------
;;;; DISPLAY
;;;; --------------------------------------------------------------------

(defvar-local diogenes-tgl--pdf-word nil
  "The word this TGL PDF buffer was opened for, for the manual-check `i' key.")

(defcustom diogenes-tgl-index-key "i"
  "Key that opens volume V's index around the current word, or nil for none.
Bound in a TGL volume only, `diogenes-tgl-pdf-mode\=' being enabled there and
nowhere else -- so `i\=' is free to mean this without being taken from any
other document.  Under evil the map overrides normal state, where `i\=' is
`evil-insert-state\='.

Nil binds nothing; `M-x diogenes-tgl-open-index-here\=' still works.  Use
`diogenes-tgl-install-index-key\=' after changing this in a running Emacs."
  :type '(choice key-sequence (const :tag "Unbound" nil))
  :group 'diogenes)

(defvar diogenes-tgl-pdf-mode-map
  (let ((map (make-sparse-keymap)))
    (when diogenes-tgl-index-key
      (keymap-set map diogenes-tgl-index-key #'diogenes-tgl-open-index-here))
    map)
  "Keymap active in TGL volume PDF buffers (see `diogenes-tgl-pdf-mode').")

;;;###autoload
(defun diogenes-tgl-install-index-key ()
  "Apply `diogenes-tgl-index-key\=' to `diogenes-tgl-pdf-mode-map\='.
Whatever the key was before is unbound first, so it does not accumulate."
  (interactive)
  (dolist (key (where-is-internal #'diogenes-tgl-open-index-here
                                  diogenes-tgl-pdf-mode-map))
    (ignore-errors
      (keymap-unset diogenes-tgl-pdf-mode-map (key-description key) t)))
  (when diogenes-tgl-index-key
    (keymap-set diogenes-tgl-pdf-mode-map diogenes-tgl-index-key
                #'diogenes-tgl-open-index-here))
  (when (called-interactively-p 'interactive)
    (message "TGL index key: %s" (or diogenes-tgl-index-key "unbound"))))

(define-minor-mode diogenes-tgl-pdf-mode
  "Minor mode for PDF buffers opened by the TGL module.
Adds \\<diogenes-tgl-pdf-mode-map>\\[diogenes-tgl-open-index-here], which
opens volume V's index around where the current word falls -- a manual
cross-check for when the main lookup lands on the wrong page.  Enabled
only on TGL volume PDFs, so it never affects other dictionaries."
  :lighter " TGL"
  :keymap diogenes-tgl-pdf-mode-map)

;; `i' is `evil-insert-state' in normal state, and evil searches its state
;; maps before any minor mode's -- so without this the key would put the
;; reader into insert state instead of opening the index.  The map is marked
;; as overriding rather than the key bound globally, because that applies only
;; while this mode is on, which is to say only in a TGL volume.
(with-eval-after-load 'evil
  (when (fboundp 'evil-make-overriding-map)
    (evil-make-overriding-map diogenes-tgl-pdf-mode-map)
    (when (fboundp 'evil-normalize-keymaps)
      (evil-normalize-keymaps))))

(defun diogenes-tgl--show (tomus page &optional word)
  "Show volume TOMUS's PDF at PAGE.
Reuses `diogenes-old--show-page', so paging and zooming behave as for
the other print dictionaries.  Honours
`diogenes-tgl-display-in-other-window'.  WORD, when given, is the
looked-up word; it is remembered in the PDF buffer so the manual-check
`i' key (`diogenes-tgl-open-index-here') knows what to look up."
  (let ((pdf (diogenes-tgl--volume-pdf tomus))
        (diogenes-old-display-in-other-window
         diogenes-tgl-display-in-other-window))
    (unless pdf
      (user-error "No PDF found in the TGL volume %s folder"
                  (or (cdr (assq tomus diogenes-tgl--roman)) tomus)))
    (diogenes-old--show-page page pdf)
    ;; The displayed buffer is the one visiting PDF; tag it for the `i' key.
    (let ((buf (find-buffer-visiting pdf)))
      (when buf
        (with-current-buffer buf
          (diogenes-tgl-pdf-mode 1)
          (when word (setq diogenes-tgl--pdf-word word)))))
    page))

(defun diogenes-tgl-open-index-here ()
  "Open volume V's index around where the current PDF buffer's word falls.
A manual cross-check: when a TGL lookup opens the wrong page, press
\\[diogenes-tgl-open-index-here] to jump to that word's place in the
fifth-volume index and read its entry or reference by eye.  Uses the
word remembered when this PDF was opened; with a prefix argument, or
when no word is remembered, prompts for one."
  (interactive)
  (let* ((word (if (or current-prefix-arg (not diogenes-tgl--pdf-word))
                   (read-string "Show V index around word: "
                                diogenes-tgl--pdf-word)
                 diogenes-tgl--pdf-word))
         (loc (diogenes-tgl--where-in-index word)))
    (unless loc
      (user-error "Could not place \"%s\" in the volume V index" word))
    (diogenes-tgl--show 5 (cdr loc) word)
    (message "TGL: volume V index around \"%s\" -> PDF p.%d (manual check)"
             word (cdr loc))))

;;;; --------------------------------------------------------------------
;;;; INTERACTIVE ENTRY POINTS
;;;; --------------------------------------------------------------------

(defvar diogenes--lookup-headword)      ; from diogenes-perseus.el

(declare-function diogenes--lookup-headword-at-point "diogenes-perseus" (&optional pos))

(defun diogenes-tgl--current-headword ()
  "Return the headword to look up for the Greek entry point is in.
Resolved from point on every call via
`diogenes--lookup-headword-at-point', so the opener always acts on
the entry the cursor is currently in -- including entries loaded
later by `diogenes-lookup-next' / `diogenes-lookup-previous'."
  (or (and (fboundp 'diogenes--lookup-headword-at-point)
           (diogenes--lookup-headword-at-point))
      (get-text-property (point) 'orth)
      (and (boundp 'diogenes--lookup-headword) diogenes--lookup-headword)
      (thing-at-point 'word t)
      (user-error "No headword found at point")))

;;;###autoload
(defun diogenes-lookup-open-tgl (&optional word)
  "Open Estienne's Thesaurus Graecae Linguae PDF at the entry for WORD.
Interactively, WORD defaults to the headword of the Greek entry at
point in a `diogenes-lookup-mode' buffer.  With a prefix argument,
prompt for the word.

The word is located via the fifth volume's comprehensive index (a
1-edit fuzzy match covers single-letter OCR damage).  If the index
lists it only as a \"vide in <root>\" cross-reference -- as it does for
many nested derivatives -- the root is resolved instead.  Failing
both, the volumes' OCR is scanned for the word as a left-margin entry,
routed by its initial letter.  The resulting tomus + column is
translated to a PDF page and opened.

Requires `diogenes-tgl-directory' to point at the parent folder of the
volume sub-directories I, II, III, IIII and V, each holding that
volume's PDF and OCR text.  Uses `pdf-tools' (recommended) or
`doc-view' for display."
  (interactive
   (progn
     (diogenes--lookup-assert-lang "greek" "Estienne's Thesaurus Graecae Linguae")
     (list (if current-prefix-arg
               (read-string "Open TGL at word: ")
             (diogenes-tgl--current-headword)))))
  (let* ((word (or word (diogenes-tgl--current-headword)))
         (hit (diogenes-tgl--locate word)))
    (unless hit
      (user-error "Could not locate \"%s\" in the TGL (is its volume installed?)" word))
    (let* ((tomus (plist-get hit :tomus))
           (page (plist-get hit :page))
           (roman (or (cdr (assq tomus diogenes-tgl--roman)) tomus)))
      (diogenes-tgl--show tomus page word)
      (let* ((col (plist-get hit :column))
             (letter (plist-get hit :letter))
             (fuzzy (and (eq (plist-get hit :match) 'fuzzy) " (fuzzy)"))
             (colstr (if col
                         (format " c.%d%s" col
                                 (if (and letter (> (length letter) 0))
                                     (concat "," letter) ""))
                       "")))
        (pcase (plist-get hit :via)
          ('override
           (message "TGL: \"%s\" -> t.%s PDF p.%d (entry; OCR-garbled headword, located by neighbour)"
                    word roman page))
          ('compound
           (message "TGL: \"%s\" -> t.%s PDF p.%d (compound entry, filed under its root)"
                    word roman page))
          ('vnde
           (message "TGL: \"%s\" -> t.%s PDF p.%d (derived form, given under its root)"
                    word roman page))
          ('entry
           (message "TGL: \"%s\" -> t.%s PDF p.%d (its own entry)"
                    word roman page))
          ('index-entry
           (message "TGL: \"%s\" -> t.%s PDF p.%d (supplementary entry in the volume V index; not in the main volumes)"
                    word roman page))
          ('caps
           (message "TGL: \"%s\" -> t.%s PDF p.%d (entry opening)"
                    word roman page))
          ('index
           (message "TGL: \"%s\" -> t.%s%s -> PDF p.%d%s"
                    word roman colstr page (or fuzzy "")))
          ('xref
           (message "TGL: \"%s\" -> vide %s -> t.%s%s -> PDF p.%d%s"
                    word (plist-get hit :root) roman colstr page (or fuzzy "")))
          ('morph
           (message "TGL: \"%s\" -> root %s -> t.%s%s -> PDF p.%d (via prefix analysis)"
                    word (plist-get hit :root) roman colstr page))
          ('body
           (message "TGL: \"%s\" -> t.%s PDF p.%d (found in body; not indexed separately)"
                    word roman page))
          ('hint
           (message "TGL: \"%s\" -> t.%s PDF p.%d (approximate: only cross-references from derived words; look nearby)"
                    word roman page)))))))

;;;###autoload
(defun diogenes-tgl-explain (word)
  "Print how WORD is resolved in the TGL, for debugging.
Shows the collation key, the letter-routed volume, whether the word
has a caps opening / exact index / fuzzy index / vide / reduplication
mapping, and the final `diogenes-tgl--locate' result.  Read the echo
area or the *Messages* buffer.  Interactively, prompts for a word (or
uses the Greek headword at point)."
  (interactive
   (list (if current-prefix-arg
             (read-string "Explain TGL lookup for word: ")
           (or (and (boundp 'diogenes--lookup-headword) diogenes--lookup-headword)
               (thing-at-point 'word t)
               (read-string "Explain TGL lookup for word: ")))))
  (let* ((key (diogenes-montanari--greek-key word))
         (index (diogenes-tgl--index))
         (owner (diogenes-tgl--tomus-for-key key))
         (override (diogenes-tgl--override-locate key))
         (compound (diogenes-tgl--compound-locate key))
         (entry (diogenes-tgl--entry-locate key))
         (vnde (diogenes-tgl--vnde-locate key))
         (ientry (diogenes-tgl--index-entry-locate key index))
         (rroot (diogenes-tgl--reduplicated-root key))
         (caps (diogenes-tgl--caps-locate key))
         (exact (diogenes-tgl--index-locate-key key index 'exact-only))
         (fuzzy (diogenes-tgl--index-locate-key key index nil))
         (vide (gethash key (plist-get index :vide)))
         (final (diogenes-tgl--locate word)))
    (message
     (concat
      "TGL explain %S:\n"
      "  collation key : %S\n"
      "  letter volume : %s\n"
      "  override      : %s\n"
      "  compound (C.) : %s\n"
      "  own entry     : %s\n"
      "  vnde/inde     : %s\n"
      "  vol-V entry   : %s\n"
      "  caps opening  : %s\n"
      "  exact index   : %s\n"
      "  fuzzy index   : %s\n"
      "  vide root     : %s\n"
      "  reduplication : %s\n"
      "  FINAL         : %s")
     word key
     (or owner "?")
     (if override (format "t%s p%s" (car override) (cdr override)) "-")
     (if compound (format "t%s p%s" (car compound) (cdr compound)) "-")
     (if entry (format "t%s p%s" (car entry) (cdr entry)) "-")
     (if vnde (format "t%s p%s" (car vnde) (cdr vnde)) "-")
     (if ientry (format "t%s p%s" (car ientry) (cdr ientry)) "-")
     (if caps (format "t%s p%s" (car caps) (cdr caps)) "-")
     (if exact (format "t%s p%s c%s" (nth 0 exact) (nth 1 exact) (nth 2 exact)) "-")
     (if fuzzy (format "t%s p%s c%s (%s)" (nth 0 fuzzy) (nth 1 fuzzy) (nth 2 fuzzy) (nth 4 fuzzy)) "-")
     (or vide "-")
     (or rroot "-")
     (if final (format "%s -> t%s p%s"
                       (plist-get final :via)
                       (plist-get final :tomus)
                       (plist-get final :page))
       "nil"))))

;;;###autoload
;;;; --------------------------------------------------------------------
;;;; PORTABLE PREBUILT INDEX  (ship-and-load, no run-time OCR parse)
;;;; --------------------------------------------------------------------

;; Building every TGL cache from the OCR (column models, index, per-volume
;; compound/vnde/entry/body/header maps, letter map) takes several seconds
;; the first time in a session.  `diogenes-tgl-build-index' does it once and
;; writes a PORTABLE snapshot -- `tgl-index.eld' in the parent folder -- that
;; any machine with the same OCR can load instantly, so the OCR is never
;; parsed at look-up time.
;;
;; Portability trick: the live caches are keyed by each file's truename+mtime
;; (machine-specific), so we do NOT store those keys.  We store each cached
;; value under a PORTABLE role key -- the tomus number for per-volume caches,
;; `:all' for the whole-set letter map -- and on load we re-key each value to
;; THIS machine's current truename+mtime for that volume.  The live caches
;; and their accessors are therefore untouched; the snapshot simply adopts
;; local keys when loaded.  Hash-table values are written with Emacs's
;; readable `#s(hash-table ...)' syntax (print-length/level nil), so no
;; per-field conversion is needed.

(defcustom diogenes-tgl-prebuilt-index-name "tgl-index.eld"
  "Filename of the portable prebuilt TGL index, kept in the parent folder.
Written by \\[diogenes-tgl-build-index]; when present it makes every
look-up instant, on any machine, without parsing the OCR at run time."
  :type 'string
  :group 'diogenes)

(defconst diogenes-tgl--index-format-version 3
  "Bumped when the prebuilt-index structure changes, to invalidate old files.
Version 2: the compound map now also harvests split-headword compounds
\(e.g. `C.ΔΙΑ πράσω'), so a version-1 index (built before that) is
rejected and rebuilt on demand.
Version 3: the caps map now also harvests the caps-head-then-lowercase-
lemma root form (e.g. `ΑΥΤΟΣ αὐτό, ...') and repairs a spurious leading
capital on such a head when the article's own lemma confirms it (OCR
`ΒΑΥΤΟΣ' -> ΑΥΤΟΣ, landing αὐτός on its true root page).  A version-2
index (built before that) is rejected and rebuilt on demand.")

(defun diogenes-tgl--prebuilt-index-file ()
  "Return the portable prebuilt-index path, or nil if the directory is unset."
  (when diogenes-tgl-directory
    (expand-file-name diogenes-tgl-prebuilt-index-name
                      (file-name-as-directory
                       (expand-file-name diogenes-tgl-directory)))))

(defun diogenes-tgl--installed-tomus-list ()
  "Return the list of installed tomus numbers (those with an OCR text file)."
  (let (out)
    (dolist (tomus '(1 2 3 4 5))
      (when (diogenes-tgl--volume-text tomus) (push tomus out)))
    (nreverse out)))

(defun diogenes-tgl--collect-index-payload ()
  "Force every cache to build and return a portable payload alist.
Each entry is (CACHE-TYPE . ((ROLE . VALUE) ...)), ROLE being a tomus
number (per-volume caches) or `:all' (letter map).  Calls the ordinary
accessors, so the values are exactly what look-up uses."
  (let ((per (lambda (getter)
               (delq nil
                     (mapcar (lambda (tm)
                               (let ((v (funcall getter tm)))
                                 (and v (cons tm v))))
                             (diogenes-tgl--installed-tomus-list))))))
    (list
     (cons 'colmodel
           (delq nil
                 (mapcar (lambda (tm)
                           (let ((txt (diogenes-tgl--volume-text tm)))
                             (and txt
                                  (cons tm (diogenes-tgl--column-model txt)))))
                         (diogenes-tgl--installed-tomus-list))))
     (cons 'body        (funcall per #'diogenes-tgl--body))
     (cons 'compound    (funcall per #'diogenes-tgl--compounds))
     (cons 'vnde        (funcall per #'diogenes-tgl--vnde))
     (cons 'entry       (funcall per #'diogenes-tgl--entries))
     (cons 'header-map  (funcall per #'diogenes-tgl--header-map))
     (cons 'index
           (let ((v (ignore-errors (diogenes-tgl--index))))
             (and v (list (cons 5 v)))))
     (cons 'index-pagekeys
           (let ((txt (diogenes-tgl--volume-text 5)))
             (and txt (list (cons 5 (diogenes-tgl--index-pagekeys txt))))))
     (cons 'anomalous
           (let ((a (ignore-errors (diogenes-tgl--anomalous))))
             (and a (list (cons 5 a)))))
     (cons 'letter-map  (list (cons :all (diogenes-tgl--letter-map)))))))

(defun diogenes-tgl--repopulate-from-payload (payload)
  "Load PAYLOAD (from `diogenes-tgl--collect-index-payload') into the caches.
Each stored value is re-keyed to THIS machine's current cache key for
the relevant volume, so a snapshot built elsewhere is adopted locally.
Silently skips a role whose volume is not installed here."
  (dolist (entry payload)
    (let ((type (car entry)) (items (cdr entry)))
      (dolist (kv items)
        (let* ((role (car kv)) (val (cdr kv)))
          (pcase type
            ('letter-map
             (setf (gethash
                    (diogenes-tgl--dir-signature
                     (file-name-as-directory
                      (expand-file-name diogenes-tgl-directory)))
                    diogenes-tgl--letter-map-cache)
                   val))
            ((or 'colmodel 'body 'compound 'vnde 'entry 'header-map
                 'index 'index-pagekeys 'anomalous)
             (let ((txt (diogenes-tgl--volume-text role)))
               (when txt
                 (let ((key (diogenes-tgl--file-cache-key txt))
                       (cache (pcase type
                                ('colmodel diogenes-tgl--colmodel-cache)
                                ('body diogenes-tgl--body-cache)
                                ('compound diogenes-tgl--compound-cache)
                                ('vnde diogenes-tgl--vnde-cache)
                                ('entry diogenes-tgl--entry-cache)
                                ('header-map diogenes-tgl--header-map-cache)
                                ('index diogenes-tgl--index-cache)
                                ('index-pagekeys diogenes-tgl--index-pagekeys-cache)
                                ('anomalous diogenes-tgl--anomalous-cache))))
                   (setf (gethash key cache) val)))))))))))

(defvar diogenes-tgl--prebuilt-loaded nil
  "Non-nil once the portable prebuilt index has been loaded this session.")

(defun diogenes-tgl--maybe-load-prebuilt-index ()
  "Load the portable prebuilt index into the caches once, if present.
A missing, corrupt or wrong-version file is a silent no-op, so look-up
falls through to the ordinary (parsing) accessors.  When the stored
directory signature differs from the current one, warns that the index
may be stale but still loads it."
  (unless diogenes-tgl--prebuilt-loaded
    (setq diogenes-tgl--prebuilt-loaded t)   ; attempt at most once per session
    (let ((file (diogenes-tgl--prebuilt-index-file)))
      (when (and file (file-readable-p file))
        (condition-case err
            (let ((data (with-temp-buffer
                          (insert-file-contents file)
                          (goto-char (point-min))
                          (read (current-buffer)))))
              ;; (:diogenes-tgl-index VERSION SIGNATURE PAYLOAD)
              (when (and (consp data)
                         (eq (car data) :diogenes-tgl-index)
                         (eq (nth 1 data) diogenes-tgl--index-format-version))
                (let ((stored-sig (nth 2 data))
                      (payload (nth 3 data))
                      (cur-sig (diogenes-tgl--dir-signature
                                (file-name-as-directory
                                 (expand-file-name diogenes-tgl-directory)))))
                  (unless (equal stored-sig cur-sig)
                    (message "TGL: prebuilt index %s may be stale (OCR changed); \
rebuild with M-x diogenes-tgl-build-index"
                             (abbreviate-file-name file)))
                  (diogenes-tgl--repopulate-from-payload payload))))
          (error (ignore err) nil))))))

;;;###autoload
(defun diogenes-tgl-build-index ()
  "Parse the TGL OCR now and write a portable prebuilt index file.
Builds every cache (column models, the volume-V index, and the
per-volume compound/vnde/entry/body/header maps -- the slow step) and
writes them to `tgl-index.eld' in `diogenes-tgl-directory'.  Thereafter
every look-up -- including the first in a session, and on any machine
the folder is copied to -- loads that file instantly instead of
parsing the OCR.  Run once after installing or re-OCRing the volumes."
  (interactive)
  (unless diogenes-tgl-directory
    (user-error "Set `diogenes-tgl-directory' first"))
  (let ((file (diogenes-tgl--prebuilt-index-file)))
    (message "TGL: building index from OCR (this may take several seconds)...")
    ;; Start clean so the snapshot reflects the current OCR exactly.
    (diogenes-tgl-clear-cache)
    (setq diogenes-tgl--prebuilt-loaded t)   ; we are building fresh; don't reload
    (let* ((sig (diogenes-tgl--dir-signature
                 (file-name-as-directory
                  (expand-file-name diogenes-tgl-directory))))
           (payload (diogenes-tgl--collect-index-payload)))
      (let ((coding-system-for-write 'utf-8)
            (print-length nil) (print-level nil) (print-circle nil))
        (with-temp-file file
          (prin1 (list :diogenes-tgl-index
                       diogenes-tgl--index-format-version
                       sig payload)
                 (current-buffer))))
      (message "TGL: wrote prebuilt index to %s"
               (abbreviate-file-name file)))))

(defun diogenes-tgl-clear-cache (&optional keep-prebuilt)
  "Forget all cached TGL data (volumes, index, column models, body scans).
Call this if you add, replace or re-OCR a volume while Emacs is
running.

This also DELETES the portable prebuilt index file, if present, because
otherwise the next look-up would immediately reload it and undo the
clear -- so stale prebuilt data cannot mask freshly-parsed results.
With a prefix argument (KEEP-PREBUILT non-nil) the file is kept and only
the in-memory caches are cleared; the stale file will then reload on the
next look-up, so use this only when you know the file is current."
  (interactive "P")
  (clrhash diogenes-tgl--volumes-cache)
  (clrhash diogenes-tgl--index-cache)
  (clrhash diogenes-tgl--index-pagekeys-cache)
  (clrhash diogenes-tgl--colmodel-cache)
  (clrhash diogenes-tgl--body-cache)
  (clrhash diogenes-tgl--header-map-cache)
  (clrhash diogenes-tgl--compound-cache)
  (clrhash diogenes-tgl--entry-cache)
  (clrhash diogenes-tgl--vnde-cache)
  (clrhash diogenes-tgl--letter-map-cache)
  (clrhash diogenes-tgl--anomalous-cache)
  (setq diogenes-tgl--prebuilt-loaded nil)
  (let ((deleted nil))
    (if keep-prebuilt
        ;; keep the file and allow it to reload on the next look-up
        (setq diogenes-tgl--prebuilt-loaded nil)
      (let ((file (ignore-errors (diogenes-tgl--prebuilt-index-file))))
        (when (and file (file-exists-p file))
          (condition-case err
              (progn (delete-file file) (setq deleted t))
            (error (message "Diogenes TGL: could not delete prebuilt index %s (%s)"
                            (abbreviate-file-name file)
                            (error-message-string err))))))
      ;; do not reload a (possibly stale) prebuilt index this session
      (setq diogenes-tgl--prebuilt-loaded t))
    (message "Diogenes TGL caches cleared%s"
             (if deleted "; prebuilt index deleted (rebuild with M-x diogenes-tgl-build-index)"
               ""))))

;;;; --------------------------------------------------------------------
;;;; REGISTRATION
;;;; --------------------------------------------------------------------

(declare-function diogenes-lookup-register-dictionary "diogenes-perseus"
                  (id &rest keys))

;;;###autoload
(defun diogenes-tgl-available-p ()
  "Non-nil if Estienne's Thesaurus Graecae Linguae can be opened.
True when `diogenes-tgl-directory' is set.  Whether it exists, and whether
every volume is in it, is not asked here."
  (diogenes--path-set-p diogenes-tgl-directory))

(defconst diogenes-tgl--declared-at-load (diogenes--declared-at-load-p)
  "Whether the TGL was asked for, rather than bundled with the rest.
Computed when this file is read: a `require' in an init file means the
user wants this dictionary, and it is then offered whatever its paths
say.  See `diogenes--loading-bundle'.")

(defun diogenes-tgl--register ()
  "Announce the TGL to the lookup banner.  Idempotent."
  (diogenes-lookup-register-dictionary
   'tgl :lang "greek" :name "TGL" :key "t" :order 50
   :command #'diogenes-lookup-open-tgl
   :available-p #'diogenes-tgl-available-p
   :declared diogenes-tgl--declared-at-load
   :paths '(diogenes-tgl-directory)
   :help "Open Estienne's Thesaurus Graecae Linguae at \"%s\""))

(with-eval-after-load 'diogenes-perseus
  (diogenes-tgl--register))

(provide 'diogenes-tgl)
;;; diogenes-tgl.el ends here
