;;; diogenes-gaffiot-pdf.el --- Open Gaffiot's printed dictionary at a word -*- lexical-binding: t -*-

;;; Commentary:

;; Jump to the page of Gaffiot's _Dictionnaire illustré latin-français_ -- the
;; 2016 typeset edition (Gérard Gréco's "Le Gaffiot 2016") -- that holds a
;; given Latin word, shown with `pdf-tools' (or `doc-view').
;;
;; ---------------------------------------------------------------------
;; WHY BOTH THIS AND `diogenes-gaffiot.el'
;; ---------------------------------------------------------------------
;;
;; The Gaffiot TEI XML that `diogenes-gaffiot.el' searches has been proofread
;; only as far as F.  This PDF is the whole dictionary, so the two together
;; cover it: `g' shows the XML entry when the word is in A-F -- a real lookup
;; buffer, with entry navigation and `C-c C-c' -- and falls through to this
;; module beyond it, which opens the page.  Nothing here duplicates the XML
;; side; it is the supplement, and the seam is `diogenes-gaffiot-pdf-fallback'.
;;
;; ---------------------------------------------------------------------
;; THE PAGE INDEX
;; ---------------------------------------------------------------------
;;
;; This edition is bookmarked with the FIRST HEADWORD OF EVERY PAGE -- 1 379
;; of them, one per page of the dictionary body (pp. 57-1439) -- which is the
;; ideal case: page N holds every word from its own bookmark up to the next
;; page's, so a word is placed by a binary search over them with no
;; interpolation and no guesswork.  No pre-built data is needed: the outline is
;; read from the PDF with `pdf-info-outline' and cached for the session.
;;
;; Two kinds of bookmark are NOT page guides and are kept out of that search:
;;
;;   * the front matter's "Lettre A - Auteurs - ouvrages" sections, which name
;;     letters but list cited authors (the body's own sections are "lettre A");
;;   * the 944 illustration bookmarks, tagged "(illustr.)".  These sit on the
;;     page where the plate is printed, not in alphabetical order relative to
;;     the page's first word, so including them would break the ordering the
;;     search depends on.  They are indexed separately instead, and when the
;;     word looked up has a plate, the message says which page it is on.
;;
;; Bookmark headwords carry macrons and breves, æ and œ, homograph numerals
;; ("abacus 1"), and -- in this edition -- a Cyrillic ў for y-breve, so they
;; are reduced to ASCII by `diogenes-gaffiot--key' before being compared, the
;; same key the XML dictionary is sorted on.
;;
;; Setup:
;;
;;   (setq diogenes-gaffiot-pdf-file "/path/to/gaffiot-2016.pdf")
;;
;; Then `g' on a Latin entry reaches it for any word past F, and `L' inside
;; the PDF looks up another word without leaving it.

;;; Code:
(require 'cl-lib)
(require 'seq)
(require 'subr-x)
(require 'diogenes-old)                 ; reuse the PDF display driver
(require 'diogenes-gaffiot)             ; reuse the collation key

(declare-function pdf-info-outline "pdf-info" (&optional file-or-buffer))

;;;; --------------------------------------------------------------------
;;;; CUSTOMIZATION
;;;; --------------------------------------------------------------------

(defcustom diogenes-gaffiot-pdf-file nil
  "Path to a PDF of Gaffiot's Dictionnaire illustré latin-français.
Written for the 2016 typeset edition, whose outline bookmarks give the
first headword of every page.  Any edition bookmarked that way will do;
one bookmarked by letter only will land you at the head of a letter."
  :type '(choice (const :tag "Not set" nil) file)
  :group 'diogenes)

(defcustom diogenes-gaffiot-pdf-page-offset 0
  "Integer added to every page number derived from the Gaffiot outline.
Leave at 0: outline destinations are physical page indices already.  See
`diogenes-old-page-offset'."
  :type 'integer
  :group 'diogenes)

(defcustom diogenes-gaffiot-pdf-fallback t
  "When non-nil, `\\[diogenes-lookup-gaffiot]' falls through to the PDF.
The Gaffiot TEI is proofread only to F, so a word past it has no entry to
show.  With this set, and `diogenes-gaffiot-pdf-file' pointing at the
printed dictionary, such a word opens the page instead of being reported
as out of range -- the two sources then cover the whole alphabet between
them.  Also used when no converted XML dictionary is present at all."
  :type 'boolean
  :group 'diogenes)

;;;; --------------------------------------------------------------------
;;;; READING THE OUTLINE
;;;; --------------------------------------------------------------------

(defconst diogenes-gaffiot-pdf--section-regexp "\\`[[:space:]]*lettres?[[:space:]]"
  "Regexp matching a bookmark that heads a letter rather than an entry.
Matched case-insensitively, so it also catches the front matter's
\"Lettre A - Auteurs - ouvrages\"; those are told apart by the body's own
sections being the first such bookmarks in the file (see
`diogenes-gaffiot-pdf--build-index').")

(defconst diogenes-gaffiot-pdf--illustration-regexp "([[:space:]]*illustr\\.[[:space:]]*)"
  "Regexp matching the tag this edition appends to an illustration bookmark.")

(defvar diogenes-gaffiot-pdf--index-cache (make-hash-table :test 'equal)
  "Cache mapping a PDF cache-key to its parsed page index.")

(defun diogenes-gaffiot-pdf--cache-key (file)
  "Return a cache key for FILE combining its truename and mtime."
  (let ((true (file-truename file)))
    (cons true (file-attribute-modification-time (file-attributes true)))))

(defun diogenes-gaffiot-pdf--section-p (title)
  "Non-nil if TITLE heads a letter of the dictionary or of the author list."
  (let ((case-fold-search t))
    (string-match-p diogenes-gaffiot-pdf--section-regexp (or title ""))))

(defun diogenes-gaffiot-pdf--illustration-p (title)
  "Non-nil if TITLE is an illustration bookmark."
  (string-match-p diogenes-gaffiot-pdf--illustration-regexp (or title "")))

(defun diogenes-gaffiot-pdf--build-index (file)
  "Read FILE\'s outline and return the Gaffiot page index.
The value is a plist:
  :keys    a vector of ASCII headword keys, ascending;
  :pages   the matching vector of page numbers;
  :heads   the matching vector of headwords as printed, for messages;
  :illustr a hash mapping a key to the page its plate is on;
  :body    the first page of the dictionary body.

The body begins at the first \"lettre …\" bookmark that does not belong to
the front matter\'s list of cited authors -- those are titled \"Lettre A -
Auteurs - ouvrages\" -- and every bookmark from there on is either a page
guide or an illustration.  Signals a user-error when nothing usable is
found."
  (unless (require 'pdf-info nil t)
    (user-error "pdf-tools is not installed; cannot read the Gaffiot outline.  \
Install pdf-tools (M-x package-install RET pdf-tools) and run M-x pdf-tools-install"))
  (let* ((large-file-warning-threshold nil)
         (outline (condition-case err
                      (pdf-info-outline file)
                    (error
                     (user-error "Could not read the outline of %s: %s"
                                 file (error-message-string err)))))
         (rows (cl-loop for entry in outline
                        for page = (alist-get 'page entry)
                        for title = (or (alist-get 'title entry) "")
                        when (and (integerp page) (> page 0))
                        collect (cons title page)))
         (body (cl-loop for (title . page) in rows
                        when (and (diogenes-gaffiot-pdf--section-p title)
                                  (not (string-match-p "Auteurs" title)))
                        return page))
         (guides nil)
         (pages (make-hash-table :test 'eql))
         (illustr (make-hash-table :test 'equal)))
    (unless body
      (user-error "%s has no \"lettre …\" bookmark for the dictionary itself: \
is it the Gaffiot PDF?" file))
    (pcase-dolist (`(,title . ,page) rows)
      (let ((key (and (>= page body)
                      (not (diogenes-gaffiot-pdf--section-p title))
                      (diogenes-gaffiot--key title))))
        (when (and key (not (string-empty-p key)))
          (if (diogenes-gaffiot-pdf--illustration-p title)
              ;; Keep the FIRST page a plate appears on, and keep plates out
              ;; of the page guides: they sit where the picture is printed,
              ;; not in alphabetical order, and would break the search.
              (unless (gethash key illustr)
                (puthash key page illustr))
            (let ((prior (gethash page pages)))
              ;; One guide per page: the page's FIRST headword.  A page
              ;; bookmarked twice -- p. 57 carries the title "Dictionnaire
              ;; illustré" as well as the entry a -- would otherwise put an
              ;; out-of-order key into the search.
              (when (or (null prior) (string< key (car prior)))
                (puthash page (cons key title) pages)))))))
    (maphash (lambda (page cell) (push (list (car cell) page (cdr cell)) guides))
             pages)
    (setq guides (sort guides (lambda (a b) (< (cadr a) (cadr b)))))
    (unless guides
      (user-error "Found no page headwords in the outline of %s" file))
    (list :keys (vconcat (mapcar #'car guides))
          :pages (vconcat (mapcar #'cadr guides))
          :heads (vconcat (mapcar #'caddr guides))
          :illustr illustr
          :body body)))

(defun diogenes-gaffiot-pdf--file ()
  "Return the configured Gaffiot PDF, or signal a user-error."
  (let ((file diogenes-gaffiot-pdf-file))
    (unless file
      (user-error "Set `diogenes-gaffiot-pdf-file' to your Gaffiot PDF first"))
    (unless (file-readable-p file)
      (user-error "Cannot read the Gaffiot PDF at %s" file))
    file))

(defun diogenes-gaffiot-pdf--index (&optional file)
  "Return the cached page index for FILE, building it if need be."
  (let* ((file (or file (diogenes-gaffiot-pdf--file)))
         (cache-key (diogenes-gaffiot-pdf--cache-key file)))
    (or (gethash cache-key diogenes-gaffiot-pdf--index-cache)
        (setf (gethash cache-key diogenes-gaffiot-pdf--index-cache)
              (diogenes-gaffiot-pdf--build-index file)))))

;;;; --------------------------------------------------------------------
;;;; HEADWORD -> PAGE
;;;; --------------------------------------------------------------------

(defun diogenes-gaffiot-pdf--locate (word &optional file)
  "Return (PAGE HEADWORD ILLUSTRATION-PAGE) for WORD in the Gaffiot PDF.
PAGE is the page whose printed range covers WORD -- the last page whose
own first headword sorts at or before it, which is exact here because
every page is bookmarked.  HEADWORD is that page's first headword as
printed, for the echo area.  ILLUSTRATION-PAGE is where this edition
prints a plate for the word, or nil.  Returns nil when WORD yields no
collatable key."
  (let* ((index (diogenes-gaffiot-pdf--index file))
         (keys (plist-get index :keys))
         (pages (plist-get index :pages))
         (heads (plist-get index :heads))
         (key (diogenes-gaffiot--key word))
         (n (length keys)))
    (when (and (> (length key) 0) (> n 0))
      ;; rightmost i with keys[i] <= key
      (let ((lo 0) (hi n) (found -1))
        (while (< lo hi)
          (let* ((mid (/ (+ lo hi) 2))
                 (k (aref keys mid)))
            (if (string< key k)
                (setq hi mid)
              (setq found mid
                    lo (1+ mid)))))
        (let ((i (max found 0)))
          (list (+ (aref pages i) diogenes-gaffiot-pdf-page-offset)
                (aref heads i)
                (gethash key (plist-get index :illustr))))))))

(defun diogenes-gaffiot-pdf--page-for-word (word &optional file)
  "Return the Gaffiot PDF page for WORD, or nil.
The entry point `diogenes-pdf-search' uses; see
`diogenes-gaffiot-pdf--locate' for the rest of what is known."
  (car (diogenes-gaffiot-pdf--locate word file)))

;;;; --------------------------------------------------------------------
;;;; INTERACTIVE ENTRY POINTS
;;;; --------------------------------------------------------------------

(declare-function diogenes--lookup-assert-lang "diogenes-perseus" (expected dict-name))

;;;###autoload
(defun diogenes-lookup-open-gaffiot-pdf (&optional word)
  "Open Gaffiot's printed dictionary at the page for WORD.
Interactively, WORD defaults to the headword of the Latin entry at point;
with a prefix argument, prompt for it.  Reached automatically by
`\\[diogenes-lookup-gaffiot]' for a word the proofread XML does not cover
\(see `diogenes-gaffiot-pdf-fallback'), and callable on its own for any
word.

Requires `diogenes-gaffiot-pdf-file', and `pdf-tools' (recommended) or
`doc-view' for display."
  (interactive
   (progn
     (diogenes--lookup-assert-lang "latin" "Gaffiot")
     (list (if current-prefix-arg
               (read-string "Open the Gaffiot PDF at word: ")
             (diogenes-gaffiot--current-headword)))))
  (let* ((word (string-trim (or word (diogenes-gaffiot--current-headword))))
         (file (diogenes-gaffiot-pdf--file))
         (hit (diogenes-gaffiot-pdf--locate word file)))
    (unless hit
      (user-error "Could not locate \"%s\" in the Gaffiot PDF" word))
    (seq-let (page head illustration) hit
      (diogenes-old--show-page page file)
      (if illustration
          (message "Gaffiot: \"%s\" -> page %d (%s...); illustrated on page %d"
                   word page head illustration)
        (message "Gaffiot: \"%s\" -> page %d (%s...)" word page head)))))

;;;###autoload
(defun diogenes-gaffiot-pdf-clear-cache ()
  "Forget the cached Gaffiot PDF page index.
Call this if you replace or re-bookmark the PDF while Emacs is running."
  (interactive)
  (clrhash diogenes-gaffiot-pdf--index-cache)
  (message "Diogenes Gaffiot PDF index cache cleared"))

(provide 'diogenes-gaffiot-pdf)
;;; diogenes-gaffiot-pdf.el ends here
