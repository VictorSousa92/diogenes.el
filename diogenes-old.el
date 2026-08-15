;;; diogenes-old.el --- Open the Oxford Latin Dictionary PDF from lookup -*- lexical-binding: t -*-

;;; Commentary:

;; This module lets you jump from a Diogenes dictionary entry (the
;; buffer produced by `diogenes-lookup-mode', i.e. after you look up or
;; parse a Latin word) straight to the page of the *Oxford Latin
;; Dictionary* (OLD) that contains that entry, displayed inside Emacs
;; with `pdf-tools' (or, as a fallback, `doc-view').
;;
;; It works with any OLD PDF that carries an outline / table of contents
;; whose bookmarks are the printed running heads (guide words) of each
;; page -- which is exactly what the OLD's first edition has, and what
;; the upstream Diogenes build tools rely on.  No pre-built data file and
;; no Perl round-trip are needed: the page index is read directly from
;; the PDF's own outline via `pdf-info-outline'.
;;
;; Setup:
;;
;;   (setq diogenes-old-pdf-file "/path/to/OLD.pdf")
;;
;; Then, in a lookup buffer, press `o' or click the "[OLD]" link shown at
;; the top of each entry.
;;
;; If your PDF's page labels are offset from the physical page numbers
;; (common with scans that include unnumbered front matter), set
;; `diogenes-old-page-offset' to the difference, or -- more robustly --
;; just rely on the outline, whose destinations are always physical
;; pages and therefore already correct.

;;; Code:
(require 'cl-lib)
(require 'seq)
(require 'ucs-normalize)

(declare-function diogenes--lookup-assert-lang "diogenes-perseus" (expected dict-name))
(declare-function pdf-info-outline "pdf-info" (&optional file-or-buffer))
(declare-function pdf-info-number-of-pages "pdf-info" (&optional file-or-buffer))
(declare-function pdf-view-goto-page "pdf-view" (page &optional window))
(declare-function pdf-view-mode "pdf-view" ())
(declare-function doc-view-goto-page "doc-view" (page))

;;;; --------------------------------------------------------------------
;;;; CUSTOMIZATION
;;;; --------------------------------------------------------------------

(defcustom diogenes-old-pdf-file nil
  "Path to a PDF of the Oxford Latin Dictionary.
For the page-lookup to work, this PDF must contain an outline
\(a.k.a. bookmarks or table of contents) in which every entry
corresponds to a page and is labelled with that page's running
head (guide word).  The first edition of the OLD, as used by the
upstream Diogenes build tools, is such a PDF."
  :type '(choice (const :tag "Not set" nil) file)
  :group 'diogenes)

(defcustom diogenes-old-page-offset 0
  "Integer added to every page number derived from the OLD outline.
Normally you should leave this at 0: the destinations stored in a
PDF outline are physical page indices, so they already point at
the right page regardless of how the printed pages are numbered.
Adjust this only if you find that jumps land a fixed number of
pages away from the entry you wanted."
  :type 'integer
  :group 'diogenes)

(defcustom diogenes-old-display-in-other-window t
  "If non-nil, show the OLD PDF in another window, keeping the entry visible.
This mirrors the behaviour of the original Diogenes desktop
application, which shows the dictionary text and the PDF page side
by side."
  :type 'boolean
  :group 'diogenes)

;;;; --------------------------------------------------------------------
;;;; HEADWORD NORMALIZATION
;;;; --------------------------------------------------------------------

(defconst diogenes-old--sort-key-table
  ;; Map the letters that the OLD alphabetises together.  Classical OLD
  ;; treats i/j and u/v as the same letter; running heads are printed
  ;; with the classical spelling, so we fold accordingly before
  ;; comparing.
  '((?j . ?i) (?J . ?i) (?I . ?i)
    (?v . ?u) (?V . ?u) (?U . ?u))
  "Alist folding OLD-equivalent letters to a single sort character.")

(defun diogenes-old--strip-diacritics (str)
  "Remove combining marks and macron/breve notation from STR.
Handles both the ASCII notation used in the Perseus data
\(\"_\" for a macron, \"^\" for a breve) and real Unicode
combining characters, so it works whether the headword was taken
from `orth_orig' or from displayed text."
  (let* ((s (replace-regexp-in-string "[_^]" "" str))
         ;; Decompose, then drop the combining-diacritic range.
         (decomposed (ucs-normalize-NFD-string s)))
    (replace-regexp-in-string "[\u0300-\u036f]" "" decomposed)))

(defun diogenes-old--sort-key (word)
  "Return a comparison key for WORD as the OLD would alphabetise it.
Diacritics are stripped, homograph-distinguishing digits and
surrounding punctuation are removed, i/j and u/v are folded, and
the result is downcased."
  (let* ((w (diogenes-old--strip-diacritics word))
         ;; Drop anything that is not a letter (trailing homograph
         ;; numbers like "malus^2", stray punctuation, spaces).
         (w (replace-regexp-in-string "[^[:alpha:]]" "" w))
         (w (downcase w)))
    (apply #'string
           (mapcar (lambda (c) (or (cdr (assq c diogenes-old--sort-key-table)) c))
                   (append w nil)))))

;;;; --------------------------------------------------------------------
;;;; READING THE PDF OUTLINE
;;;; --------------------------------------------------------------------

;; Building the index requires querying the epdfinfo server, which is
;; not instantaneous, so we cache the parsed result per PDF file (keyed
;; on truename + modification time, so editing/replacing the PDF
;; invalidates the cache automatically).
(defvar diogenes-old--index-cache (make-hash-table :test 'equal)
  "Cache mapping a PDF cache-key to its parsed running-head index.")

(defun diogenes-old--cache-key (file)
  "Return a cache key for FILE combining its truename and mtime."
  (let ((true (file-truename file)))
    (cons true
          (file-attribute-modification-time (file-attributes true)))))

(defcustom diogenes-old-bookmark-exclude
  '("title" "tittle" "preface" "editors" "abbr" "aut" "contents"
    "bibliography" "addenda" "corrigenda")
  "Single-word OLD bookmark guide words to exclude from the index.
These label front matter (title page, preface, author and
abbreviation lists) rather than dictionary entries.  Multi-word
guide words are excluded automatically; this list covers the
single-word ones.  Compared case-insensitively."
  :type '(repeat string)
  :group 'diogenes)

(defcustom diogenes-old-bookmark-title-regexp
  "\\`[0-9]*[[:space:]]*\\(.*?\\)\\.tif\\'"
  "Regexp extracting the guide word from an OLD outline TITLE.
The OLD PDF's bookmarks are scan file names of the form
\"1922 tam.tif\" -- a sequence number, the page's guide word, and a
\".tif\" extension.  Group 1 must capture the guide word (here
\"tam\").  If a title does not match, it is used as-is after
stripping a leading number."
  :type 'regexp
  :group 'diogenes)

(defun diogenes-old--clean-bookmark-title (title)
  "Extract the guide word from an outline TITLE string.
The OLD bookmarks are scan file names like \"1922 tam.tif\"; we
pull out the guide word (\"tam\") via
`diogenes-old-bookmark-title-regexp', discarding the leading
sequence number and the \".tif\" extension.  Without this, the
extension would fuse into the sort key (\"tam.tif\" -> \"tamtif\")
and corrupt both matching and ordering.  Final normalization
happens in `diogenes-old--sort-key'."
  (let ((s (string-trim (or title ""))))
    (if (string-match diogenes-old-bookmark-title-regexp s)
        (string-trim (match-string 1 s))
      ;; Fallback: no ".tif"; just drop a leading sequence number.
      (replace-regexp-in-string "\\`[0-9]+[[:space:]]+" "" s))))

(defun diogenes-old--build-index (file)
  "Read FILE's outline and return a sorted running-head index.
The result is a list of (SORT-KEY . PAGE) conses, sorted
ascending by SORT-KEY, with entries lacking a usable guide word or
page dropped.  Signals a user-error if the PDF has no usable
outline."
  (unless (require 'pdf-info nil t)
    (user-error "pdf-tools is not installed; cannot read the OLD outline.  \
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
                   for guide = (diogenes-old--clean-bookmark-title
                                (alist-get 'title entry))
                   for key = (diogenes-old--sort-key guide)
                   when (and (integerp page) (> page 0)
                             (> (length key) 0)
                             ;; Skip front-matter scans (title page,
                             ;; preface, author/abbreviation lists): their
                             ;; guide words contain whitespace ("aut cic",
                             ;; "abbr ger") or are known non-lemmata.
                             (not (string-match-p "[[:space:]]" guide))
                             (not (member (downcase guide)
                                          diogenes-old-bookmark-exclude)))
                   collect (cons key page))))
    (when (null index)
      (user-error "The PDF %s has no usable outline / running-head bookmarks.  \
This feature needs an OLD PDF whose bookmarks are the page guide words"
                  file))
    ;; Sort ascending by key; break ties by earlier page.  Each key is
    ;; the last headword on its page; if the same guide word heads two
    ;; consecutive pages (a long entry spanning the page break), the
    ;; earlier page -- where the entry begins -- must come first, so the
    ;; matcher's "first key >= word" lands there.
    (sort index (lambda (a b)
                  (or (string< (car a) (car b))
                      (and (string= (car a) (car b))
                           (< (cdr a) (cdr b))))))))

(defun diogenes-old--index (&optional file)
  "Return the running-head index for FILE (default `diogenes-old-pdf-file').
Uses and populates `diogenes-old--index-cache'."
  (let ((file (or file diogenes-old-pdf-file)))
    (unless file
      (user-error "Set `diogenes-old-pdf-file' to the path of your OLD PDF first"))
    (unless (file-readable-p file)
      (user-error "Cannot read OLD PDF at %s" file))
    (let ((key (diogenes-old--cache-key file)))
      (or (gethash key diogenes-old--index-cache)
          (setf (gethash key diogenes-old--index-cache)
                (diogenes-old--build-index file))))))

;;;; --------------------------------------------------------------------
;;;; HEADWORD -> PAGE
;;;; --------------------------------------------------------------------

(defun diogenes-old--page-for-word (word &optional file)
  "Return the OLD page number containing the entry for WORD.
Each bookmark in the index is the *last* headword on its page, so
WORD's entry is on the first page whose guide word sorts at or
after WORD -- the earliest page whose running head has reached
WORD.  When WORD is itself the last entry of a page and continues
onto the next (so the same guide word heads two consecutive
pages), this returns the earlier page, where the entry begins.
Returns an integer page (with `diogenes-old-page-offset' applied),
or the final page if WORD sorts after every guide word."
  (let* ((index (diogenes-old--index file))
         (key (diogenes-old--sort-key word))
         (hit nil))
    ;; INDEX is sorted ascending by key, ties broken to the EARLIER page.
    ;; The first entry whose last-word key is >= WORD's key is the page
    ;; WORD falls on; because ties favour the earlier page, a word that
    ;; heads two consecutive pages resolves to where it begins.
    (cl-loop for (gkey . page) in index
             when (or (string< key gkey) (string= key gkey))
             do (setq hit page) and return nil)
    ;; If WORD sorts after every guide word, use the last page.
    (let ((page (or hit (cdr (car (last index))))))
      (when page
        (+ page diogenes-old-page-offset)))))

;;;; --------------------------------------------------------------------
;;;; OPENING THE PDF
;;;; --------------------------------------------------------------------

(defun diogenes-old--goto-page-in-window (buffer page)
  "Go to PAGE in the window that displays BUFFER, disturbing no other window.
`pdf-view-goto-page' with no window argument acts on the SELECTED
window, so a jump that runs asynchronously (see
`diogenes-old--goto-page-when-ready') could repage whatever PDF the
user has since switched to.  Passing BUFFER's own window confines the
jump; if BUFFER is not currently displayed, the jump is skipped rather
than applied to the wrong window."
  (when (buffer-live-p buffer)
    (let ((win (get-buffer-window buffer t)))
      (with-current-buffer buffer
        (cond
         ((derived-mode-p 'pdf-view-mode)
          (when win
            (let ((page (if (fboundp 'pdf-info-number-of-pages)
                            (max 1 (min page (pdf-info-number-of-pages)))
                          (max 1 page))))
              (pdf-view-goto-page page win))))
         ((derived-mode-p 'doc-view-mode)
          (when win
            (with-selected-window win
              (doc-view-goto-page (max 1 page))))))))))

(defun diogenes-old--goto-page-when-ready (buffer page)
  "Jump to PAGE in BUFFER once its PDF viewer is ready.
Handles the asynchronous start-up of `pdf-view-mode': if the
buffer is not yet displaying pages, the jump is deferred to
`pdf-view-mode-hook'.  The jump is always confined to BUFFER's own
window (see `diogenes-old--goto-page-in-window'), so it never changes
the page of another PDF the user may have selected in the meantime."
  (with-current-buffer buffer
    (cond
     ((derived-mode-p 'pdf-view-mode)
      (diogenes-old--goto-page-in-window buffer page))
     ((derived-mode-p 'doc-view-mode)
      (diogenes-old--goto-page-in-window buffer page))
     ((and (fboundp 'pdf-view-mode)
           buffer-file-name
           (string-match-p "\\.pdf\\'" buffer-file-name))
      ;; pdf-view-mode is available but the buffer hasn't finished
      ;; entering it yet.  Defer until it has.
      (let ((buf buffer) (pg page) fn)
        (setq fn (lambda ()
                   (when (eq (current-buffer) buf)
                     (remove-hook 'pdf-view-mode-hook fn t)
                     (run-with-timer
                      0 nil
                      (lambda ()
                        (diogenes-old--goto-page-in-window buf pg))))))
        (add-hook 'pdf-view-mode-hook fn nil t)))
     (t
      (message "OLD entry is on page %d (couldn't drive the PDF viewer)" page)))))

(defun diogenes-old--show-page (page &optional file)
  "Display the OLD PDF FILE at PAGE inside Emacs.
Prefers `pdf-tools'; falls back to `doc-view' if pdf-tools is not
available.  Honours `diogenes-old-display-in-other-window'."
  (let* ((file (or file diogenes-old-pdf-file))
         (already (find-buffer-visiting file))
         ;; TLL fascicles and OLD scans are hundreds of MB; opening one
         ;; is deliberate here, so don't prompt about its size.
         (large-file-warning-threshold nil)
         (buffer (or already (find-file-noselect file)))
         (display (if diogenes-old-display-in-other-window
                      #'display-buffer
                    #'pop-to-buffer-same-window)))
    (funcall display buffer)
    (diogenes-old--goto-page-when-ready buffer page)
    page))

;;;; --------------------------------------------------------------------
;;;; INTERACTIVE ENTRY POINTS
;;;; --------------------------------------------------------------------

(defvar diogenes--lookup-headword)     ; defined/made-local in diogenes-perseus.el

(declare-function diogenes--lookup-headword-at-point "diogenes-perseus" (&optional pos))

(defun diogenes-old--current-headword ()
  "Return the headword to look up for the entry point is in.
Resolved from point on every call via
`diogenes--lookup-headword-at-point', so the opener always acts on
the entry the cursor is currently in -- including entries loaded
later by `diogenes-lookup-next' / `diogenes-lookup-previous' --
rather than the entry the buffer was first opened on.  Falls back to
the buffer-local `diogenes--lookup-headword', then the `orth' at
point, then the word at point."
  (or (and (fboundp 'diogenes--lookup-headword-at-point)
           (diogenes--lookup-headword-at-point))
      (get-text-property (point) 'orth)
      (and (boundp 'diogenes--lookup-headword) diogenes--lookup-headword)
      (thing-at-point 'word t)
      (user-error "No headword found at point")))

;;;###autoload
(defun diogenes-lookup-open-old (&optional word)
  "Open the Oxford Latin Dictionary PDF at the entry for WORD.
Interactively, WORD defaults to the headword of the entry at point
in a `diogenes-lookup-mode' buffer.  With a prefix argument, prompt
for the word to look up.

Requires `diogenes-old-pdf-file' to point at an OLD PDF that has a
running-head outline, and `pdf-tools' (recommended) or `doc-view'
for display."
  (interactive
   (progn
     (diogenes--lookup-assert-lang "latin" "The Oxford Latin Dictionary")
     (list (if current-prefix-arg
               (read-string "Open OLD at word: ")
             (diogenes-old--current-headword)))))
  (let* ((word (or word (diogenes-old--current-headword)))
         (page (diogenes-old--page-for-word word)))
    (unless page
      (user-error "Could not locate \"%s\" in the OLD outline" word))
    (diogenes-old--show-page page)
    (message "OLD: \"%s\" -> page %d" word page)))

;;;###autoload
(defun diogenes-old-clear-cache ()
  "Forget any cached OLD page index.
Call this if you replace or re-bookmark the OLD PDF while Emacs is
running."
  (interactive)
  (clrhash diogenes-old--index-cache)
  (message "Diogenes OLD index cache cleared"))

(provide 'diogenes-old)
;;; diogenes-old.el ends here
