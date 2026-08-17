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
(require 'diogenes-lisp-utils)          ; diogenes--require-path

(declare-function diogenes--lookup-assert-lang "diogenes-perseus" (expected dict-name))
(declare-function pdf-info-outline "pdf-info" (&optional file-or-buffer))
(declare-function reader-fit-to-width "reader" ())
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

(defcustom diogenes-old-display-in-other-window nil
  "If non-nil, show the dictionary PDF in another window.
The default is nil: the page appears in the window the lookup was made
from, replacing the entry.  Closing the document buffer brings the entry
back, so a lookup and the print dictionary it opens share one window
instead of splitting the frame for a page you will read and close.

A non-nil `pop-up-frames' overrides this: asking for a frame of its own
is asking for another window, so the page is displayed rather than put in
the entry\'s place, and lands in a new frame (the next dictionary then
joins it -- see `diogenes-old-reader-reuse-document-frame').  Unset
`pop-up-frames' and the page replaces the entry again.

Set it to t for the side-by-side arrangement of the original Diogenes
desktop application, which shows the dictionary text and the PDF page at
once.  Which window, or frame, the page then goes to is decided by
`diogenes-old-reader-display-action' and
`diogenes-old-reader-reuse-document-frame' under the Emacs Reader, and by
`display-buffer' (with window-purpose, if you use it) otherwise.

Passow and the TGL bind this to their own equivalents; see
`diogenes-passow-display-in-other-window' and
`diogenes-tgl-display-in-other-window'."
  :type 'boolean
  :group 'diogenes)

(defcustom diogenes-old-reader-display-action
  '((display-buffer-reuse-window
     display-buffer-reuse-mode-window
     display-buffer-use-some-window)
    (mode . (reader-mode pdf-view-mode doc-view-mode))
    (reusable-frames . visible)
    (inhibit-same-window . t))
  "`display-buffer' ACTION for showing a dictionary in the Emacs Reader.
The Reader needs `display-buffer-overriding-action' bound to nil (see
`diogenes-old--show-page'), which also takes window-purpose out of the
picture -- and with it the behaviour that keeps one dictionary after
another in a single window.  Reusing a window that already shows a
document buffer restores it, so opening one dictionary after another
replaces the page on screen instead of splitting the frame again.

`reusable-frames' is `visible' because the reuse functions otherwise
look at the selected frame alone: with `pop-up-frames' non-nil, or any
setup where the dictionary ends up in a frame of its own, the window
holding it would not be found and a further frame would be created for
every dictionary.  Set it to nil to keep the search to one frame.

Used for the Reader only: with pdf-tools and doc-view, purpose's own
overriding action is left in place and already does this.  Consulted
only when `diogenes-old-display-in-other-window' is non-nil."
  :type 'sexp
  :group 'diogenes)

(defcustom diogenes-old-reader-reuse-document-frame t
  "When non-nil, a dictionary joins the window a document is already in.
Concerns the Emacs Reader only, and leaves `pop-up-frames' alone until
there is something to reuse: the FIRST dictionary opens wherever your
`pop-up-frames' and `display-buffer-alist' would put it -- a frame of its
own, if that is your setting -- and each dictionary after it replaces the
page in that same window, for as long as some visible frame still shows a
document buffer.  Close it and the next dictionary opens a fresh frame
again.

Two things have to give way for that.  The Reader's entry point
`reader-open-doc' DISPLAYS the document as part of loading it, before
Diogenes has any say in where it goes, and `save-window-excursion' cannot
take a new frame back -- it restores the window configuration of a frame,
not the set of frames.  So when a document window exists, `pop-up-frames'
is bound to nil for the duration of the open (the Reader\'s own display
then lands on the selected frame, where `save-window-excursion' does undo
it) and of the display that follows, which goes through
`diogenes-old-reader-display-action'.

Set this to nil to let `pop-up-frames' apply to every dictionary, giving
each one its own frame.  Consulted only when
`diogenes-old-display-in-other-window' is non-nil; with the default nil
the page replaces the entry in the lookup's own window and no second
window is involved."
  :type 'boolean
  :group 'diogenes)

(defcustom diogenes-old-reader-fit-to-width 'once
  "Whether to fit a dictionary page to the window width in the Emacs Reader.
`once' (the default) fits each document the first time Diogenes shows a
page in it, and then leaves it alone, so a zoom level you set by hand
survives the next lookup.  t re-fits on every jump.  nil never fits, and
you press \\<reader-mode-map>\\[reader-fit-to-width] yourself.

The fit is done from `diogenes-old--reader-goto-when-ready', at the one
moment it can work: the Reader renders asynchronously, and
`reader-fit-to-width' scales the page in the selected window, so it needs
both a rendered document and a live window.  A `reader-mode-hook' runs too
early for the first (nothing to scale yet) and not at all for a document
whose buffer is merely redisplayed, which is why this is not a hook.

Ignored under pdf-tools and doc-view, which have their own fit commands."
  :type '(choice (const :tag "First page shown in each document" once)
                 (const :tag "Every jump" t)
                 (const :tag "Never" nil))
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
      (diogenes--require-path file 'diogenes-old-pdf-file
                              "The Oxford Latin Dictionary" 'file))
    (unless (file-readable-p file)
      (diogenes--require-path file 'diogenes-old-pdf-file
                              "The Oxford Latin Dictionary" 'file))
    (let ((key (diogenes-old--cache-key file)))
      (or (gethash key diogenes-old--index-cache)
          (setf (gethash key diogenes-old--index-cache)
                (diogenes-old--build-index file))))))

;;;; --------------------------------------------------------------------
;;;; HEADWORD -> PAGE
;;;; --------------------------------------------------------------------

(defconst diogenes-old--truncated-guide-min-length 5
  "Minimum guide-word length for the truncated-guide-word fallback.
A page's guide word is its last headword, but the OLD's OCR/bookmark
text sometimes drops a headword's final letters (e.g. `uadimoni' for
UADIMONIUM).  Such a clipped guide word sorts just before the full
word, so the plain search steps past its page to the next one.  When
the immediately preceding page's guide word is a prefix of the looked-up
word and is at least this many characters long, we treat it as that
headword truncated and return the preceding page.  The length floor
keeps genuinely short, distinct guide words (`ua', `uir', `pes') from
swallowing later words that merely share their opening letters.")

(defun diogenes-old--page-for-word (word &optional file)
  "Return the OLD page number containing the entry for WORD.
Each bookmark in the index is the *last* headword on its page, so
WORD's entry is on the first page whose guide word sorts at or
after WORD -- the earliest page whose running head has reached
WORD.  When WORD is itself the last entry of a page and continues
onto the next (so the same guide word heads two consecutive
pages), this returns the earlier page, where the entry begins.

If the preceding page's guide word is a truncation of WORD (a
prefix of it, and long enough to be a clipped headword rather than
a distinct short word -- see
`diogenes-old--truncated-guide-min-length'), WORD is that page's
spilled-over last entry, so the preceding page is returned.  This
handles running heads whose final letters the OCR dropped (e.g.
`uadimoni' for UADIMONIUM, the last entry of its page).

Returns an integer page (with `diogenes-old-page-offset' applied),
or the final page if WORD sorts after every guide word."
  (let* ((index (diogenes-old--index file))
         (key (diogenes-old--sort-key word))
         (hit nil)
         (prev-key nil) (prev-page nil))
    ;; INDEX is sorted ascending by key, ties broken to the EARLIER page.
    ;; The first entry whose last-word key is >= WORD's key is the page
    ;; WORD falls on; because ties favour the earlier page, a word that
    ;; heads two consecutive pages resolves to where it begins.  We also
    ;; remember the entry just before the hit: if its guide word is a
    ;; (substantial) prefix of KEY, that guide word is a truncated form of
    ;; WORD and WORD is the spilled-over last entry of that earlier page.
    (cl-loop for (gkey . page) in index
             when (or (string< key gkey) (string= key gkey))
             do (setq hit page) and return nil
             do (setq prev-key gkey prev-page page))
    (let* ((truncated
            (and hit prev-key prev-page
                 (not (string= prev-key key))
                 (>= (length prev-key)
                     diogenes-old--truncated-guide-min-length)
                 (string-prefix-p prev-key key)))
           (page (cond (truncated prev-page)
                       (hit hit)
                       ;; WORD sorts after every guide word: last page.
                       (t (cdr (car (last index)))))))
      (when page
        (+ page diogenes-old-page-offset)))))

;;;; --------------------------------------------------------------------
;;;; OPENING THE PDF
;;;; --------------------------------------------------------------------

(defcustom diogenes-old-pdf-viewer 'auto
  "Which in-Emacs viewer opens a print dictionary at an entry's page.
All the forward openers -- the dictionary keys (`o', `m', `b', ...) and
the `diogenes-lookup-open-*' commands -- display their PDF through
`diogenes-old--show-page', which honours this setting:

  `auto'         Use `pdf-tools' if it is available, otherwise fall back
                 to the built-in `doc-view'.  This is the default.
  `pdf-tools'    Force `pdf-view-mode'.
  `doc-view'     Force the built-in `doc-view-mode'.
  `emacs-reader' Use the Emacs Reader (`reader-mode', the MuPDF-backed
                 reader from https://codeberg.org/MonadicSheep/emacs-reader).

All four are in-Emacs viewers, so window management (including
`window-purpose') applies to their buffers normally.

Note: the reverse in-PDF lookup, `diogenes-pdf-lookup-entry' (the `L'
key), works only with `pdf-tools' (and, partially, `doc-view').  It
reads the word under point from the PDF's text layer, which
`emacs-reader' does not expose (it renders pages as images), so `L' is
unavailable when the dictionary is open in the Emacs Reader.  The
forward openers work with every viewer."
  :type '(choice (const :tag "Auto (pdf-tools, else doc-view)" auto)
                 (const :tag "pdf-tools" pdf-tools)
                 (const :tag "doc-view" doc-view)
                 (const :tag "Emacs Reader (reader-mode)" emacs-reader))
  :group 'diogenes)

(defun diogenes-old--resolved-viewer ()
  "Return the concrete viewer to use: `pdf-tools', `doc-view', or `emacs-reader'.
Resolves `diogenes-old-pdf-viewer', turning `auto' into `pdf-tools'
when pdf-tools is available and `doc-view' otherwise."
  (pcase diogenes-old-pdf-viewer
    ('pdf-tools 'pdf-tools)
    ('doc-view 'doc-view)
    ('emacs-reader 'emacs-reader)
    (_ (if (or (featurep 'pdf-tools) (fboundp 'pdf-view-mode))
           'pdf-tools
         'doc-view))))

(defun diogenes-old--goto-page-in-window (buffer page)
  "Go to PAGE in the window that displays BUFFER, disturbing no other window.
`pdf-view-goto-page' with no window argument acts on the SELECTED
window, so a jump that runs asynchronously (see
`diogenes-old--goto-page-when-ready') could repage whatever PDF the
user has since switched to.  Passing BUFFER's own window confines the
jump; if BUFFER is not currently displayed, the jump is skipped rather
than applied to the wrong window.

Handles `pdf-view-mode', `doc-view-mode', and the Emacs Reader's
`reader-mode' (via `reader-goto-page', clamped with
`reader-current-doc-pagecount')."
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
              (doc-view-goto-page (max 1 page)))))
         ((and (derived-mode-p 'reader-mode) (fboundp 'reader-goto-page))
          (when win
            (with-selected-window win
              (let ((page (if (boundp 'reader-current-doc-pagecount)
                              (max 1 (min page reader-current-doc-pagecount))
                            (max 1 page))))
                (reader-goto-page page))))))))))

(defcustom diogenes-old-reader-jump-retries 40
  "How many times to retry the Emacs Reader page jump while the doc loads.
`reader-open-doc' returns before the document has finished rendering
\(so `reader-current-pagenumber' is momentarily nil), and the Emacs
Reader provides no \"document ready\" hook.  We therefore poll: attempt
the jump, and if the reader is not ready yet, retry after
`diogenes-old-reader-jump-retry-interval' seconds, up to this many
times, then give up.  The cap guarantees the retries cannot loop
forever."
  :type 'integer
  :group 'diogenes)

(defcustom diogenes-old-reader-jump-retry-interval 0.1
  "Seconds between retries of the Emacs Reader page jump.
See `diogenes-old-reader-jump-retries'."
  :type 'number
  :group 'diogenes)

(defvar-local diogenes-old--reader-fitted nil
  "Non-nil once Diogenes has fitted this Reader document to the window width.
Keeps `diogenes-old-reader-fit-to-width' set to `once' from undoing a zoom
level the user chose after the document was first shown.")

(defun diogenes-old--reader-maybe-fit-to-width (buffer window)
  "Fit BUFFER's page to WINDOW's width, if `diogenes-old-reader-fit-to-width'.
Called only once the page has been rendered and jumped to, since
`reader-fit-to-width' needs a live document in the selected window.  Any
error is ignored: a page that will not scale is not worth abandoning the
lookup for."
  (when (and diogenes-old-reader-fit-to-width
             (fboundp 'reader-fit-to-width)
             (buffer-live-p buffer)
             (window-live-p window))
    (with-current-buffer buffer
      (when (or (eq diogenes-old-reader-fit-to-width t)
                (not diogenes-old--reader-fitted))
        (condition-case nil
            (with-selected-window window
              (reader-fit-to-width)
              (setq diogenes-old--reader-fitted t))
          (error nil))))))

(defun diogenes-old--reader-goto-when-ready (buffer page &optional attempt)
  "Jump BUFFER's Emacs Reader to PAGE once the document can accept it.
This affects the Emacs Reader (`reader-mode') ONLY; the pdf-tools and
doc-view jumps go through `diogenes-old--goto-page-in-window' and are
untouched.

The first `reader-open-doc' of a session sets up its render state (an
overlay) asynchronously, and a `reader-goto-page' issued before that is
ready signals `(wrong-type-argument overlayp nil)' from the dynamic
module and leaves the document on its cover page.  `reader-current-doc-pagecount'
is already set by then, so it is NOT a sufficient readiness test.  The
reliable signal is whether the jump itself completes without error:
we attempt `reader-goto-page' inside `condition-case', and on ANY error
treat the reader as not-ready-yet and retry after
`diogenes-old-reader-jump-retry-interval', up to
`diogenes-old-reader-jump-retries' times.  Subsequent documents reuse
the initialised state and succeed on the first attempt.  The jump is
confined to BUFFER's own window and skipped if BUFFER is not displayed.

A successful jump is also where the page is fitted to the window width,
when `diogenes-old-reader-fit-to-width' asks for it."
  (let ((attempt (or attempt 0)))
    (when (buffer-live-p buffer)
      (let ((win (get-buffer-window buffer t)))
        (when win
          (let ((ok
                 (and (fboundp 'reader-goto-page)
                      (with-selected-window win
                        (with-current-buffer buffer
                          (let ((pg (if (and (boundp 'reader-current-doc-pagecount)
                                             (numberp reader-current-doc-pagecount)
                                             (> reader-current-doc-pagecount 0))
                                        (max 1 (min page reader-current-doc-pagecount))
                                      (max 1 page))))
                            ;; Success is "the jump did not error".  A cold
                            ;; first document errors here until its overlay
                            ;; exists; that error is our retry signal.
                            (condition-case nil
                                (progn (reader-goto-page pg) t)
                              (error nil))))))))
            (if ok
                ;; The jump succeeded, so the document is rendered and WIN is
                ;; live: the one moment a fit-to-width can work.
                (diogenes-old--reader-maybe-fit-to-width buffer win)
              (when (< attempt diogenes-old-reader-jump-retries)
                (run-with-timer
                 diogenes-old-reader-jump-retry-interval nil
                 #'diogenes-old--reader-goto-when-ready
                 buffer page (1+ attempt))))))))))

(defun diogenes-old--goto-page-when-ready (buffer page)
  "Jump to PAGE in BUFFER once its viewer is ready.
Handles the asynchronous start-up of `pdf-view-mode': if the
buffer is not yet displaying pages, the jump is deferred to
`pdf-view-mode-hook'.  `doc-view-mode' and the Emacs Reader's
`reader-mode' are driven directly once present, with a `reader-mode-hook'
deferral for a buffer still entering reader-mode.  The jump is always
confined to BUFFER's own window (see
`diogenes-old--goto-page-in-window'), so it never changes the page of
another document the user may have selected in the meantime."
  (with-current-buffer buffer
    (cond
     ((derived-mode-p 'pdf-view-mode)
      (diogenes-old--goto-page-in-window buffer page))
     ((derived-mode-p 'doc-view-mode)
      (diogenes-old--goto-page-in-window buffer page))
     ((derived-mode-p 'reader-mode)
      ;; The Reader renders asynchronously and has no ready-hook, so poll.
      (diogenes-old--reader-goto-when-ready buffer page))
     ((and (fboundp 'pdf-view-mode)
           buffer-file-name
           (string-match-p "\\.pdf\\'" buffer-file-name)
           (not (fboundp 'reader-goto-page)))
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
     ((fboundp 'reader-goto-page)
      ;; The Emacs Reader is loaded; the buffer may still be entering
      ;; `reader-mode' / rendering.  The poll waits for readiness.
      (diogenes-old--reader-goto-when-ready buffer page))
     (t
      (message "OLD entry is on page %d (couldn't drive the viewer)" page)))))

(defun diogenes-old--reader-installed-p ()
  "Non-nil if the Emacs Reader is present and claims `.pdf' files.
When true, a plain `find-file-noselect' on a PDF would open it in
`reader-mode', so the pdf-tools and doc-view branches must keep the
Reader's `auto-mode-alist' entry from claiming the file."
  (and (fboundp 'reader-open-doc)
       (cl-some (lambda (x) (and (consp x) (eq (cdr x) 'reader-mode)))
                auto-mode-alist)))

(defun diogenes-old--document-window ()
  "Return a window on a visible frame showing a document buffer, or nil.
A document buffer is one in `reader-mode', `pdf-view-mode' or
`doc-view-mode' -- in practice, a dictionary already on screen.  Used to
decide whether a dictionary should join it (see
`diogenes-old-reader-reuse-document-frame') or open a window, or frame,
of its own."
  (cl-find-if (lambda (window)
                (with-current-buffer (window-buffer window)
                  (derived-mode-p 'reader-mode 'pdf-view-mode 'doc-view-mode)))
              (window-list-1 nil nil 'visible)))

(defun diogenes-old--reader-reuse-window ()
  "Return the document window a dictionary should join, or nil.
Nil when `diogenes-old-reader-reuse-document-frame' is nil, or when no
document is on screen yet -- in which case the dictionary is displayed
the ordinary way, `pop-up-frames' and all."
  (and diogenes-old-reader-reuse-document-frame
       (diogenes-old--document-window)))

(defun diogenes-old--open-buffer-in-viewer (file viewer)
  "Return a buffer visiting FILE, opened in VIEWER's major mode.
VIEWER is `pdf-tools', `doc-view', or `emacs-reader'.  If a buffer
already visits FILE it is returned as-is (whatever viewer it is in),
so we never open a second copy of a huge scan.

For `pdf-tools' and `doc-view', the file is opened exactly the way it
always was -- a plain `find-file-noselect', letting the normal
major-mode machinery choose the viewer -- UNLESS the Emacs Reader is
installed (see `diogenes-old--reader-installed-p'), in which case the
Reader's `.pdf' -> `reader-mode' entry is temporarily removed for the
open so it does not hijack the file; the mode is not otherwise forced.

For `emacs-reader', the Reader's own entry point `reader-open-doc' is
used (a manual `pdf-view-mode'/`reader-mode' switch on an
already-loaded buffer is not equivalent)."
  (or (find-buffer-visiting file)
      (let ((large-file-warning-threshold nil))  ; huge scans: open without prompt
        (pcase viewer
          ('emacs-reader
           ;; `reader-open-doc' is the Emacs Reader's own entry point: it sets
           ;; up the MuPDF document state and puts the buffer in `reader-mode'.
           ;; It DISPLAYS the document as a side effect, so shield the window
           ;; configuration and then locate the buffer it created for FILE.
           ;; That display is also why `pop-up-frames' is bound here: when a
           ;; dictionary is already on screen we want this one to join it, and
           ;; a new frame made during the open could not be undone --
           ;; `save-window-excursion' restores a window configuration, not the
           ;; set of frames.  With nothing to join, `pop-up-frames' is left
           ;; alone and the first dictionary opens as usual.  See
           ;; `diogenes-old-reader-reuse-document-frame'.
           (let ((pop-up-frames (if (diogenes-old--reader-reuse-window)
                                    nil
                                  pop-up-frames))
                 (display-buffer-overriding-action nil))
             (save-window-excursion
               (reader-open-doc (expand-file-name file))))
           (find-buffer-visiting file))
          ((or 'pdf-tools 'doc-view)
           (if (diogenes-old--reader-installed-p)
               ;; Reader would claim the .pdf; drop its auto-mode entry just
               ;; for this open so pdf-tools/doc-view get the file instead.
               (let ((auto-mode-alist
                      (cl-remove-if
                       (lambda (x) (and (consp x) (eq (cdr x) 'reader-mode)))
                       auto-mode-alist)))
                 (find-file-noselect file))
             ;; No Reader installed: open exactly as before, no interference.
             (find-file-noselect file)))
          (_ (find-file-noselect file))))))

(defun diogenes-old--display-in-this-window (buffer)
  "Put BUFFER in the selected window, and only there; return BUFFER.
`pop-to-buffer-same-window' is deliberately not used.  It declines a
window that something has dedicated -- window-purpose dedicates the
lookup and browser windows to their purposes -- and silently displays the
buffer in ANOTHER window instead, so the page appeared in the browser's
window as well as the entry's.  With the Emacs Reader that is doubly
confusing, since it keeps the current page per WINDOW: the copy Diogenes
had jumped showed the entry, while the stray one sat on page 1.

So the selected window is undedicated if need be and set directly, and
any other window on this frame that shows BUFFER is handed back its
previous buffer."
  (let ((window (selected-window)))
    (when (window-live-p window)
      (when (window-dedicated-p window)
        (set-window-dedicated-p window nil))
      (set-window-buffer window buffer)
      (select-window window)
      (dolist (other (get-buffer-window-list buffer nil (window-frame window)))
        (unless (eq other window)
          (switch-to-prev-buffer other)))))
  buffer)

(defun diogenes-old--display-other-window-p ()
  "Non-nil if a dictionary page belongs in a window other than the entry\'s.
True when `diogenes-old-display-in-other-window' asks for it, and also
when `pop-up-frames' is set -- wanting a frame of its own is wanting
another window.  Must be consulted BEFORE `diogenes-old--show-page' binds
`pop-up-frames' for the Reader, since that binding is about where the
frame may go, not about what the user asked for."
  (or diogenes-old-display-in-other-window pop-up-frames))

(defun diogenes-old--display-page-buffer (buffer action other-window)
  "Display BUFFER and return it.
With OTHER-WINDOW non-nil, hand it to `display-buffer\' with ACTION (nil
for the ordinary rules); otherwise put the page in the selected window, in
place of the entry the lookup was made from."
  (if other-window
      (display-buffer buffer action)
    (diogenes-old--display-in-this-window buffer))
  buffer)

(defun diogenes-old--show-page (page &optional file)
  "Display the dictionary PDF FILE at PAGE inside Emacs.
Opens FILE in the viewer chosen by `diogenes-old-pdf-viewer' (see
`diogenes-old--resolved-viewer': `pdf-tools', `doc-view', or the Emacs
Reader `reader-mode'), reusing an already-open buffer for FILE if one
exists.  Honours `diogenes-old-display-in-other-window'.  Returns PAGE.

For the Emacs Reader specifically, `display-buffer-overriding-action'
is bound to nil around the open and display.  window-purpose installs
such an overriding action, and when it intercepts the Reader's display
the Reader's render pipeline does not run, so its page overlay is never
created and every `reader-goto-page' fails with `(wrong-type-argument
overlayp nil)'.  Letting the Reader display through the normal path
fixes that.  This binding is scoped to the Reader case only, so
pdf-tools, doc-view, and window-purpose's handling of every other
buffer (lookups, browser) are unaffected.

Taking purpose out of the loop costs one thing, though: it is purpose
that otherwise keeps one dictionary after another in a single window,
so without it each dictionary opened a new one.  The Reader case
therefore displays through `diogenes-old-reader-display-action', which
reuses a window already showing a document buffer.  While a dictionary
is on screen, `pop-up-frames' is bound to nil so that neither the
Reader\'s own display nor this one moves the next dictionary to a frame
of its own; with no document displayed yet, `pop-up-frames' is left
alone and the first dictionary opens wherever your configuration puts
it.  See `diogenes-old-reader-reuse-document-frame'."
  (let* ((file (or file diogenes-old-pdf-file))
         (viewer (diogenes-old--resolved-viewer)))
    (if (eq viewer 'emacs-reader)
        ;; Bypass purpose's display override so the Reader renders normally
        ;; (creating its overlay).  Covers both the open and the display.
        (let* ((reuse (diogenes-old--reader-reuse-window))
               (other-window (diogenes-old--display-other-window-p))
               (display-buffer-overriding-action nil)
               (pop-up-frames (if reuse nil pop-up-frames)))
          (let ((buffer (diogenes-old--open-buffer-in-viewer file viewer)))
            (diogenes-old--display-page-buffer
             buffer diogenes-old-reader-display-action other-window)
            (diogenes-old--goto-page-when-ready buffer page)))
      (let ((buffer (diogenes-old--open-buffer-in-viewer file viewer)))
        (diogenes-old--display-page-buffer
         buffer nil (diogenes-old--display-other-window-p))
        (diogenes-old--goto-page-when-ready buffer page)))
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
