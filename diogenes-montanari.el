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

(declare-function diogenes--lookup-assert-lang "diogenes-perseus"
                  (expected dict-name))
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
accentuation of the OCR'd bookmark text.

This function does its own regexp matching and Unicode
normalisation, so it wraps the work in `save-match-data' to avoid
clobbering the match data of callers (e.g. a `parse-title' that
reads several `match-string' groups around a call to this)."
  (save-match-data
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
              folded))))))

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
    ;; Capture BOTH groups first; `diogenes-montanari--greek-key' runs its
    ;; own regexp matching, which would clobber this match data before we
    ;; read group 2 (this made the HIGH bound come out empty, breaking
    ;; straddle detection for multi-page entries).
    (let* ((raw-lo (match-string 1 title))
           (raw-hi (match-string 2 title))
           (lo (diogenes-montanari--greek-key raw-lo))
           (hi (diogenes-montanari--greek-key raw-hi)))
      ;; Only the LOW bound (the first headword on the page) is
      ;; reliable; the HIGH bound is frequently OCR-mangled (dropped
      ;; leading letters, stray glyphs).  We therefore key on LOW and do
      ;; NOT reorder the pair -- an earlier version swapped bounds when
      ;; hi<lo, which turned garbled titles into enormous spurious
      ;; intervals that captured unrelated words.  HI is used only for
      ;; detecting a straddle (HIGH = next page's LOW).
      (when (> (length lo) 0)
        (cons lo (if (> (length hi) 0) hi lo)))))
   ((string-match diogenes-montanari-single-regexp title)
    (let* ((raw (match-string 1 title))
           (w (diogenes-montanari--greek-key raw))
           ;; A LETTER HEADING.  The first page of each letter is bookmarked
           ;; with the letter in both cases -- `Ε, ε' -- and the key keeps only
           ;; Greek letters, so it comes out `εε': which sorts after `εα' and
           ;; puts the letter's own page among its words rather than at their
           ;; head.  A reader asking for the letter was sent to the letter's
           ;; second page, or before this was noticed to the previous letter's
           ;; last.
           ;;
           ;; One letter repeated is that letter.  No Greek headword is a letter
           ;; written twice, so nothing else is caught -- and the page then
           ;; sorts where it belongs, the ordinary rule finding it with no
           ;; special case anywhere else.
           (w (if (and (> (length w) 1)
                       (cl-every (lambda (c) (eq c (aref w 0))) w))
                  (substring w 0 1)
                w)))
      (when (> (length w) 0) (cons w w))))))

(defun diogenes-montanari--build-index (file)
  "Read FILE's outline and return the Montanari page index.
The return value is a plist:
  :low    a list of (LOW-KEY . PAGE), sorted ascending by LOW-KEY
          then PAGE -- the reliable low-bound guide for each page;
  :straddle  a hash mapping a KEY to the EARLIER page P of a
          consecutive pair whose last word equals the next page's
          first word (HIGH(P) = LOW(P+1) = KEY): the signature of an
          entry that ends page P and continues on P+1.  Such an
          entry BEGINS on P, so a low-bound match landing on P+1 is
          stepped back to P.
Depth-0 letter headers and unparseable titles are skipped.
Signals a user-error if nothing usable is found."
  (unless (require 'pdf-info nil t)
    (user-error "pdf-tools is not installed; cannot read the Montanari outline.  \
Install pdf-tools (M-x package-install RET pdf-tools) and run M-x pdf-tools-install"))
  (let* ((large-file-warning-threshold nil)
         (outline (condition-case err
                      (pdf-info-outline file)
                    (error
                     (user-error "Could not read the outline of %s: %s"
                                 file (error-message-string err)))))
         (rows
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
    (when (null rows)
      (user-error "The PDF %s has no usable Montanari page intervals in its outline"
                  file))
    ;; Page (reading) order, to detect straddles between consecutive pages.
    (let* ((by-page (sort (copy-sequence rows)
                          (lambda (a b) (< (caddr a) (caddr b)))))
           (straddle (make-hash-table :test 'equal)))
      (cl-loop for (a b) on by-page
               while b
               for hi-a = (cadr a)
               for lo-b = (car b)
               for pa = (caddr a)
               when (and hi-a lo-b (> (length hi-a) 0) (string= hi-a lo-b))
               ;; The straddling headword begins on the earlier page PA.
               ;; Keep the earliest such page if a key straddles twice.
               do (let ((prev (gethash hi-a straddle)))
                    (when (or (null prev) (< pa prev))
                      (puthash hi-a pa straddle))))
      ;; Low-bound guide, sorted by low-key then page for the search.
      (let ((low (sort (mapcar (lambda (r) (cons (car r) (caddr r))) rows)
                       (lambda (a b)
                         (or (string< (car a) (car b))
                             (and (string= (car a) (car b))
                                  (< (cdr a) (cdr b))))))))
        (list :low low :straddle straddle)))))

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
      (diogenes--require-path file 'diogenes-montanari-pdf-file
                              "Montanari" 'file))
    (unless (file-readable-p file)
      (diogenes--require-path file 'diogenes-montanari-pdf-file
                              "Montanari" 'file))
    (let ((key (diogenes-montanari--cache-key file)))
      (or (gethash key diogenes-montanari--index-cache)
          (setf (gethash key diogenes-montanari--index-cache)
                (diogenes-montanari--build-index file))))))

;;;; --------------------------------------------------------------------
;;;; HEADWORD -> PAGE
;;;; --------------------------------------------------------------------

(defun diogenes-montanari--page-after (page low)
  "The (KEY . PAGE) in LOW for the first page after PAGE, or nil.
LOW is in order, so this is the entry following the one whose page is PAGE --
and where PAGE is nil, the first entry of all, a word sorting before every
headword in the book."
  (if (null page)
      (car low)
    (cl-loop for rest on low
             when (equal (cdr (car rest)) page)
             return (cadr rest))))

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
         (low (plist-get index :low))
         (straddle (plist-get index :straddle))
         (key (diogenes-montanari--greek-key word))
         (best nil))
    (when (> (length key) 0)
      ;; Low-bound guide: last page whose first-word key sorts <= KEY.
      ;; This is the page whose running head has reached WORD -- how one
      ;; uses the guide words of a printed dictionary.  The high bound is
      ;; ignored because Montanari's OCR corrupts it.
      (cl-loop for (lo . page) in low
               while (or (string< lo key) (string= lo key))
               do (setq best page))
      ;; If WORD is exactly a page's first word AND that headword also ends
      ;; the previous page (a straddling multi-page entry), the entry began
      ;; on that earlier page -- jump there.  Restricting the step-back to
      ;; the straddle signature keeps ordinary entries (and homographs like
      ;; Δία vs διά, where no straddle holds) on their low-bound page.
      (let ((start (gethash key straddle)))
        (when (and start (or (null best) (< start best)))
          (setq best start)))
      ;; A PREFIX, not a word.  `C-u L\=' invites the beginning of a word, and a
      ;; bare letter sorts before every headword that begins with it -- `e\=' is
      ;; less than `ea\=' -- so the rule above sends a reader asking for epsilon
      ;; to the last page of delta.
      ;;
      ;; Where the page AFTER the chosen one opens with a headword having KEY as
      ;; a prefix, that page is where the letter begins.  A whole word is
      ;; untouched: `dwrea\=' is the prefix of nothing on the next page.
      ;; And only where the chosen page has not ALREADY reached the key:
      ;; asking for `ea\=' exactly must stay on the page `ea\=' opens, though
      ;; `eautou\=' on the next page begins with it too.
      (let* ((here (cl-loop for (lo . page) in low
                            when (equal page best) return lo))
             (next (diogenes-montanari--page-after best low)))
        (when (and next
                   (not (and here (string-prefix-p key here)))
                   (string-prefix-p key (car next)))
          (setq best (cdr next)))))
    (let ((page (or best (cdr (car low)))))
      (when page
        (+ page diogenes-montanari-page-offset)))))

;;;; --------------------------------------------------------------------
;;;; INTERACTIVE ENTRY POINTS
;;;; --------------------------------------------------------------------

(defvar diogenes--lookup-headword)      ; from diogenes-perseus.el
(defvar diogenes--lookup-lang)          ; from diogenes-perseus.el

(declare-function diogenes--lookup-headword-at-point "diogenes-perseus" (&optional pos))

(defun diogenes-montanari--current-headword ()
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
(defun diogenes-lookup-open-montanari (&optional word)
  "Open Montanari's Brill Dictionary PDF at the entry for WORD.
Interactively, WORD defaults to the headword of the Greek entry at
point in a `diogenes-lookup-mode' buffer.  With a prefix argument,
prompt for the word.

Requires `diogenes-montanari-pdf-file' to point at a Montanari PDF
with an interval outline, and `pdf-tools' (recommended) or
`doc-view' for display."
  (interactive
   (progn
     (diogenes--lookup-assert-lang "greek" "Montanari's Brill Dictionary")
     (list (if current-prefix-arg
               (read-string "Open Montanari at word: ")
             (diogenes-montanari--current-headword)))))
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


;;;; --------------------------------------------------------------------
;;;; REGISTRATION
;;;; --------------------------------------------------------------------

(declare-function diogenes-lookup-register-dictionary "diogenes-perseus"
                  (id &rest keys))

;;;###autoload
(defun diogenes-montanari-available-p ()
  "Non-nil if Montanari's Brill Dictionary can be opened.
True when `diogenes-montanari-pdf-file' is set, whether or not the file is
there."
  (diogenes--path-set-p diogenes-montanari-pdf-file))

(defconst diogenes-montanari--declared-at-load (diogenes--declared-at-load-p)
  "Whether Montanari was asked for, rather than bundled with the rest.
Computed when this file is read: a `require' in an init file means the
user wants this dictionary, and it is then offered whatever its paths
say.  See `diogenes--loading-bundle'.")

(defun diogenes-montanari--register ()
  "Announce Montanari to the lookup banner.  Idempotent."
  (diogenes-lookup-register-dictionary
   'montanari :lang "greek" :name "Montanari" :key "m" :order 10
   :command #'diogenes-lookup-open-montanari
   :available-p #'diogenes-montanari-available-p
   :declared diogenes-montanari--declared-at-load
   :paths '(diogenes-montanari-pdf-file)
   :bind t
   :help "Open Montanari at \"%s\""))

(with-eval-after-load 'diogenes-perseus
  (diogenes-montanari--register))

(provide 'diogenes-montanari)
;;; diogenes-montanari.el ends here
