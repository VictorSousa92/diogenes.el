;;; diogenes-montanari.el --- Open the Montanari/Brill Greek dictionary PDF -*- lexical-binding: t -*-

;; Copyright (C) 2024 Michael Neidhart
;;
;; Author: Michael Neidhart <mayhoth@gmail.com>
;; Keywords: classics, tools, philology, humanities

;;; Commentary:

;; This module lets you jump from a Diogenes *Greek* dictionary entry
;; (the buffer produced by `diogenes-lookup-mode' after a Greek lookup
;; or parse) to the page of Montanari's _Brill Dictionary of Ancient
;; Greek_ that contains that entry, displayed inside Emacs with
;; `pdf-tools' (or `doc-view').  It is the Greek counterpart of
;; `diogenes-old.el' / `diogenes-tll.el' and reuses that module's PDF
;; display code.
;;
;; It works with a Montanari PDF whose outline bookmarks give, for each
;; page, the interval of headwords it covers, e.g.
;;
;;   2: ’Α – Άβιαθάρ
;;   3: άβιαστικός – άβολιτίων
;;
;; i.e. "<column-number>: <first-headword> – <last-headword>" (the two
;; words separated by an en-dash).  A headword is matched to the page
;; whose interval contains it.  No pre-built data and no Perl are
;; needed: the index is read straight from the PDF outline.
;;
;; Because the bookmark text is OCR'd, its accents, breathings and iota
;; subscripts are unreliable, so all matching is done on an
;; accent-insensitive, case-insensitive key of the bare Greek letters
;; (see `diogenes-montanari--greek-key').
;;
;; Setup:
;;
;;   (setq diogenes-montanari-pdf-file "/path/to/Montanari.pdf")
;;
;; Then, in a Greek lookup buffer, press `m' or click the "[Montanari]"
;; link shown at the top of the entry.

;;; Code:
(require 'cl-lib)
(require 'seq)
(require 'ucs-normalize)
(require 'diogenes-old)                 ; reuse PDF display + cache pattern

(declare-function pdf-info-outline "pdf-info" (&optional file-or-buffer))
(declare-function diogenes--perseus-beta-to-utf8 "diogenes-utils" (str))

;;;; --------------------------------------------------------------------
;;;; CUSTOMIZATION
;;;; --------------------------------------------------------------------

(defcustom diogenes-montanari-pdf-file nil
  "Path to a PDF of Montanari's Brill Dictionary of Ancient Greek.
For the page lookup to work, this PDF must contain an outline whose
entries give each page's headword interval in the form
\"<n>: <first> – <last>\", as in

  2: ’Α – Άβιαθάρ

The two headwords are separated by an en-dash (or hyphen)."
  :type '(choice (const :tag "Not set" nil) file)
  :group 'diogenes)

(defcustom diogenes-montanari-page-offset 0
  "Integer added to every page number derived from the Montanari outline.
Normally leave this at 0: outline destinations are physical page
indices and are already correct.  See `diogenes-old-page-offset'."
  :type 'integer
  :group 'diogenes)

(defcustom diogenes-montanari-interval-regexp
  "\\`[[:space:]]*[0-9]+[[:space:]]*:[[:space:]]*\\(.+?\\)[[:space:]]*[–—‒―−-][[:space:]]*\\(.+?\\)[[:space:]]*\\'"
  "Regexp extracting a page's headword interval from a bookmark title.
Group 1 is the first headword on the page, group 2 the last.  The
default matches titles such as \"288: άραιρη- – Άραυάκαι\"."
  :type 'regexp
  :group 'diogenes)

(defcustom diogenes-montanari-single-regexp
  "\\`[[:space:]]*[0-9]+[[:space:]]*:[[:space:]]*\\(.+?\\)[[:space:]]*\\'"
  "Regexp for a bookmark title carrying only one headword.
Some Montanari pages are bookmarked with a single word rather than
an interval; group 1 captures it, and it is treated as both the
low and high bound of that page."
  :type 'regexp
  :group 'diogenes)

;;;; --------------------------------------------------------------------
;;;; GREEK COLLATION KEY
;;;; --------------------------------------------------------------------

(defun diogenes-montanari--greek-key (word)
  "Return an accent- and case-insensitive collation key for Greek WORD.
The key keeps only base Greek letters: combining marks (accents,
breathings, iota subscript, diaeresis) are stripped via NFD
decomposition, letters are lower-cased, final sigma is folded to
medial sigma, and every non-Greek character (stray punctuation,
OCR artefacts such as a leading guillemet, Latin letters) is
dropped.  This lets a properly accented lemma match the unreliable
accentuation of the OCR'd bookmark text."
  (if (or (null word) (string-empty-p word))
      ""
    ;; The LSJ headword captured from the dictionary XML is often in
    ;; Perseus beta code (e.g. "le/gw"), not Unicode Greek.  Montanari's
    ;; bookmarks are Unicode, so convert beta -> Unicode first.  We
    ;; detect beta by the presence of Roman letters; a string already in
    ;; Greek is left untouched.
    (let* ((word (if (and (fboundp 'diogenes--perseus-beta-to-utf8)
                          (string-match-p "[A-Za-z]" word))
                     (or (diogenes--perseus-beta-to-utf8 word) word)
                   word))
           (decomposed (ucs-normalize-NFD-string word))
           (chars (cl-loop for c across decomposed
                           for cp = c
                           ;; Drop combining marks (U+0300..U+036F and
                           ;; the Greek combining range within NFD).
                           unless (<= #x0300 cp #x036f)
                           collect (downcase c)))
           (folded (mapcar (lambda (c) (if (eq c ?\N{GREEK SMALL LETTER FINAL SIGMA})
                                           ?\N{GREEK SMALL LETTER SIGMA}
                                         c))
                           chars)))
      (apply #'string
             (cl-remove-if-not
              (lambda (c)
                (let ((o (if (characterp c) c 0)))
                  (or (<= #x0391 o #x03a9)    ; Greek capital letters
                      (<= #x03b1 o #x03c9)))) ; Greek small letters
              folded)))))

(defun diogenes-montanari--key< (a b)
  "Non-nil if Greek collation key A sorts before B."
  (string< a b))

;;;; --------------------------------------------------------------------
;;;; READING THE PDF OUTLINE
;;;; --------------------------------------------------------------------

(defvar diogenes-montanari--index-cache (make-hash-table :test 'equal)
  "Cache mapping a PDF cache-key to its parsed page-interval index.")

(defun diogenes-montanari--parse-title (title)
  "Parse a bookmark TITLE into (LOW-KEY . HIGH-KEY), or nil.
Recognises both the \"<n>: A – B\" interval form and the single
\"<n>: A\" form (returning A as both bounds)."
  (cond
   ((string-match diogenes-montanari-interval-regexp title)
    (let ((lo (diogenes-montanari--greek-key (match-string 1 title)))
          (hi (diogenes-montanari--greek-key (match-string 2 title))))
      ;; Only the LOW bound (the first headword on the page) is
      ;; reliable; the HIGH bound is frequently OCR-mangled (dropped
      ;; leading letters, stray glyphs).  We therefore key on LOW and do
      ;; NOT reorder the pair -- an earlier version swapped bounds when
      ;; hi<lo, which turned garbled titles into enormous spurious
      ;; intervals that captured unrelated words.  HI is retained only
      ;; for reference and is not used for routing.
      (when (> (length lo) 0)
        (cons lo (if (> (length hi) 0) hi lo)))))
   ((string-match diogenes-montanari-single-regexp title)
    (let ((w (diogenes-montanari--greek-key (match-string 1 title))))
      (when (> (length w) 0) (cons w w))))))

(defun diogenes-montanari--build-index (file)
  "Read FILE's outline and return a sorted page-interval index.
Each element is (LOW-KEY HIGH-KEY . PAGE), sorted ascending by
LOW-KEY then PAGE.  Depth-0 letter headers and unparseable titles
are skipped.  Signals a user-error if nothing usable is found."
  (unless (require 'pdf-info nil t)
    (user-error "pdf-tools is not installed; cannot read the Montanari outline.  \
Install pdf-tools (M-x package-install RET pdf-tools) and run M-x pdf-tools-install"))
  (let* ((large-file-warning-threshold nil)
         (outline (condition-case err
                      (pdf-info-outline file)
                    (error
                     (user-error "Could not read the outline of %s: %s"
                                 file (error-message-string err)))))
         (index
          (cl-loop for entry in outline
                   for page = (alist-get 'page entry)
                   for title = (or (alist-get 'title entry) "")
                   ;; Letter headers ("Α, α") and other non-page titles
                   ;; fail both interval regexps, so the parser itself
                   ;; filters them -- no need to depend on outline depth,
                   ;; whose numbering can vary.
                   for parsed = (and (integerp page) (> page 0)
                                     (diogenes-montanari--parse-title title))
                   when parsed
                   collect (list (car parsed) (cdr parsed) page))))
    (when (null index)
      (user-error "The PDF %s has no usable Montanari page intervals in its outline"
                  file))
    (sort index (lambda (a b)
                  (or (string< (car a) (car b))
                      (and (string= (car a) (car b))
                           (< (caddr a) (caddr b))))))))

(defun diogenes-montanari--cache-key (file)
  "Return a cache key for FILE combining its truename and mtime."
  (let ((true (file-truename file)))
    (cons true
          (file-attribute-modification-time (file-attributes true)))))

(defun diogenes-montanari--index (&optional file)
  "Return the cached page-interval index for FILE.
FILE defaults to `diogenes-montanari-pdf-file'."
  (let ((file (or file diogenes-montanari-pdf-file)))
    (unless file
      (user-error "Set `diogenes-montanari-pdf-file' to your Montanari PDF first"))
    (unless (file-readable-p file)
      (user-error "Cannot read Montanari PDF at %s" file))
    (let ((key (diogenes-montanari--cache-key file)))
      (or (gethash key diogenes-montanari--index-cache)
          (setf (gethash key diogenes-montanari--index-cache)
                (diogenes-montanari--build-index file))))))

;;;; --------------------------------------------------------------------
;;;; HEADWORD -> PAGE
;;;; --------------------------------------------------------------------

(defun diogenes-montanari--page-for-word (word &optional file)
  "Return the Montanari page number for WORD's entry.
The index is keyed on each page's FIRST headword (its low bound),
which is the reliable part of the OCR'd bookmark text.  WORD is
placed on the last page whose first-headword key sorts at or
before WORD's key -- exactly how one uses the running heads of a
printed dictionary.  The unreliable high bound is ignored.
Returns an integer page (with `diogenes-montanari-page-offset'
applied) or nil.

Because the bookmark text is OCR'd, an occasional page whose first
word is itself garbled can be off by a page or two; adjust
`diogenes-montanari-page-offset' only for a constant shift."
  (let* ((index (diogenes-montanari--index file))
         (key (diogenes-montanari--greek-key word))
         (best nil))
    (when (> (length key) 0)
      ;; INDEX is sorted ascending by low-key (then page).  Walk while
      ;; the page's first-word key is <= WORD, keeping the last page.
      (cl-loop for (lo _hi page) in index
               while (or (string< lo key) (string= lo key))
               do (setq best page)))
    ;; If WORD precedes every first-word key, fall back to the first page.
    (let ((page (or best (caddr (car index)))))
      (when page
        (+ page diogenes-montanari-page-offset)))))

;;;; --------------------------------------------------------------------
;;;; INTERACTIVE ENTRY POINTS
;;;; --------------------------------------------------------------------

(defvar diogenes--lookup-headword)      ; from diogenes-perseus.el
(defvar diogenes--lookup-lang)          ; from diogenes-perseus.el

(defun diogenes-montanari--current-headword ()
  "Return the headword to look up for the Greek entry at point."
  (or (and (boundp 'diogenes--lookup-headword) diogenes--lookup-headword)
      (get-text-property (point) 'orth)
      (thing-at-point 'word t)
      (user-error "No headword found at point")))

;;;###autoload
(defun diogenes-lookup-open-montanari (&optional word)
  "Open Montanari's Brill Dictionary PDF at the entry for WORD.
Interactively, WORD defaults to the headword of the Greek entry at
point in a `diogenes-lookup-mode' buffer.  With a prefix argument,
prompt for the word.

Requires `diogenes-montanari-pdf-file' to point at a Montanari PDF
with an interval outline, and `pdf-tools' (recommended) or
`doc-view' for display."
  (interactive
   (list (if current-prefix-arg
             (read-string "Open Montanari at word: ")
           (diogenes-montanari--current-headword))))
  (let* ((word (or word (diogenes-montanari--current-headword)))
         (page (diogenes-montanari--page-for-word word)))
    (unless page
      (user-error "Could not locate \"%s\" in the Montanari outline" word))
    ;; Reuse the OLD module's viewer driver (handles pdf-tools/doc-view,
    ;; async startup, page clamping and the large-file prompt).
    (diogenes-old--show-page page diogenes-montanari-pdf-file)
    (message "Montanari: \"%s\" -> page %d" word page)))

;;;###autoload
(defun diogenes-montanari-clear-cache ()
  "Forget the cached Montanari page index.
Call this if you replace or re-bookmark the Montanari PDF while
Emacs is running."
  (interactive)
  (clrhash diogenes-montanari--index-cache)
  (message "Diogenes Montanari index cache cleared"))

(provide 'diogenes-montanari)
;;; diogenes-montanari.el ends here
