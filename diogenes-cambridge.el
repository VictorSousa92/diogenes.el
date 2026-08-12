;;; diogenes-cambridge.el --- Open the Cambridge Greek Lexicon PDF -*- lexical-binding: t -*-

;;; Commentary:

;; This module lets you jump from a Diogenes *Greek* dictionary entry
;; (the buffer produced by `diogenes-lookup-mode') to the page of the
;; _Cambridge Greek Lexicon_ (CGL) that contains that entry, displayed
;; with `pdf-tools' (or `doc-view').  It is a Greek counterpart of
;; `diogenes-old.el' and reuses that module's PDF display code, and it
;; shares the accent-insensitive Greek collation key with the Montanari
;; module (`diogenes-montanari--greek-key').
;;
;; The CGL PDF is bookmarked with ONE running-head word per page, in the
;; form "<n>: <word>", numbered sequentially, e.g.
;;
;;   1: ά
;;   2: αββα
;;   3: άγακτίμενος
;;   4: αγάλακτος
;;
;; The parity of the running number encodes which word it is:
;;   * EVEN bookmarks give the FIRST headword on the page;
;;   * ODD  bookmarks give the LAST  headword on the page;
;;   * except the first odd bookmark of each letter, which opens the
;;     letter and gives that letter's first entry.
;;
;; Because there is only one guide word per page, matching a word to a
;; page is done by an accent-insensitive binary search over the guide
;; words, then refined using the parity: if the nearest preceding guide
;; word is an ODD (last-word) bookmark and the query sorts strictly
;; after it, the query is on the following page.
;;
;; Setup:
;;
;;   (setq diogenes-cambridge-pdf-file "/path/to/CambridgeGreekLexicon.pdf")
;;
;; Then, in a Greek lookup buffer, press `c' or click the "[CGL]" link.

;;; Code:
(require 'cl-lib)
(require 'seq)
(require 'diogenes-old)                 ; reuse PDF display + cache pattern
(require 'diogenes-montanari)           ; reuse the Greek collation key

(declare-function pdf-info-outline "pdf-info" (&optional file-or-buffer))

;;;; --------------------------------------------------------------------
;;;; CUSTOMIZATION
;;;; --------------------------------------------------------------------

(defcustom diogenes-cambridge-pdf-file nil
  "Path to a PDF of the Cambridge Greek Lexicon.
For the page lookup to work, this PDF must contain an outline with
one running-head word per page in the form \"<n>: <word>\", as in

  2: αββα

numbered sequentially.  Even numbers denote a page's first
headword, odd numbers its last (see this file's Commentary)."
  :type '(choice (const :tag "Not set" nil) file)
  :group 'diogenes)

(defcustom diogenes-cambridge-page-offset 0
  "Integer added to every page number derived from the CGL outline.
Normally leave this at 0: outline destinations are physical page
indices and are already correct.  See `diogenes-old-page-offset'."
  :type 'integer
  :group 'diogenes)

(defcustom diogenes-cambridge-entry-regexp
  "\\`[[:space:]]*\\([0-9]+\\)[[:space:]]*:[[:space:]]*\\(.+?\\)[[:space:]]*\\'"
  "Regexp extracting the running number and guide word from a CGL title.
Group 1 must capture the sequential number (its parity encodes
first- vs last-word), group 2 the guide word.  The default matches
titles such as \"3: άγακτίμενος\"."
  :type 'regexp
  :group 'diogenes)

;;;; --------------------------------------------------------------------
;;;; READING THE PDF OUTLINE
;;;; --------------------------------------------------------------------

(defvar diogenes-cambridge--index-cache (make-hash-table :test 'equal)
  "Cache mapping a PDF cache-key to its parsed guide-word index.")

(defun diogenes-cambridge--parse-title (title)
  "Parse a CGL bookmark TITLE into its Greek collation KEY, or nil.
Letter-header titles like \"Α, α\" do not match the running-number
pattern and yield nil.  The running number's parity is no longer
used: the CGL outline's OCR is not clean enough (truncated or
mis-ordered guide words) for parity-based refinement, so matching
relies on a monotonic backbone of the guide words instead."
  (when (string-match diogenes-cambridge-entry-regexp title)
    (let ((key (diogenes-montanari--greek-key (match-string 2 title))))
      (when (> (length key) 0) key))))

(defun diogenes-cambridge--monotone-backbone (rows)
  "Return the longest non-decreasing subsequence of ROWS by key.
ROWS is a list of (PAGE . KEY) in reading (page) order.  The CGL
guide words ascend down the book; OCR errors (truncated or garbled
words) show up as order-violating outliers, which this drops,
leaving a clean monotonic guide-word list for binary search."
  (let ((n (length rows)))
    (if (zerop n)
        nil
      (let* ((vec (vconcat rows))
             (keys (make-vector n nil))
             (tails (make-vector n 0))
             (tails-len 0)
             (prev (make-vector n -1)))
        (dotimes (i n) (aset keys i (cdr (aref vec i))))
        (dotimes (i n)
          (let ((k (aref keys i)) (lo 0) (hi tails-len))
            (while (< lo hi)
              (let ((mid (/ (+ lo hi) 2)))
                (if (string< k (aref keys (aref tails mid)))
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

(defun diogenes-cambridge--build-index (file)
  "Read FILE's outline and return the CGL guide-word index.
The return value is a plist:
  :keys   a vector of guide-word keys, ascending;
  :pages  the matching vector of page numbers.
Only the monotonic backbone of the guide words is kept, so OCR
outliers do not derail the binary search.  Signals a user-error if
nothing usable is found."
  (unless (require 'pdf-info nil t)
    (user-error "pdf-tools is not installed; cannot read the CGL outline.  \
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
                   for key = (and (integerp page) (> page 0)
                                  (diogenes-cambridge--parse-title title))
                   when key
                   collect (cons page key))))
    (when (null rows)
      (user-error "The PDF %s has no usable CGL guide words in its outline" file))
    ;; Reading order = page order; then keep the monotonic backbone.
    (setq rows (sort rows (lambda (a b) (< (car a) (car b)))))
    (let* ((backbone (diogenes-cambridge--monotone-backbone rows))
           (keys (vconcat (mapcar #'cdr backbone)))
           (pages (vconcat (mapcar #'car backbone))))
      (list :keys keys :pages pages))))

(defun diogenes-cambridge--cache-key (file)
  "Return a cache key for FILE combining its truename and mtime."
  (let ((true (file-truename file)))
    (cons true
          (file-attribute-modification-time (file-attributes true)))))

(defun diogenes-cambridge--index (&optional file)
  "Return the cached CGL guide-word index for FILE.
FILE defaults to `diogenes-cambridge-pdf-file'."
  (let ((file (or file diogenes-cambridge-pdf-file)))
    (unless file
      (user-error "Set `diogenes-cambridge-pdf-file' to your Cambridge Greek Lexicon PDF first"))
    (unless (file-readable-p file)
      (user-error "Cannot read Cambridge Greek Lexicon PDF at %s" file))
    (let ((key (diogenes-cambridge--cache-key file)))
      (or (gethash key diogenes-cambridge--index-cache)
          (setf (gethash key diogenes-cambridge--index-cache)
                (diogenes-cambridge--build-index file))))))

;;;; --------------------------------------------------------------------
;;;; HEADWORD -> PAGE
;;;; --------------------------------------------------------------------

(defun diogenes-cambridge--page-for-word (word &optional file)
  "Return the CGL page number for WORD's entry.
Locates WORD by an accent-insensitive binary search over the
monotonic backbone of the outline's guide words: the page is the
last one whose guide word sorts at or before WORD.  Returns an
integer page (with `diogenes-cambridge-page-offset' applied) or
nil.

The CGL bookmark text is OCR'd and occasionally garbled or
incomplete (some pages carry no bookmark), so a word may land on
the nearest preceding guide-word page rather than exactly its own;
the running head shown there lets you step a page with `pdf-tools'
if needed."
  (let* ((index (diogenes-cambridge--index file))
         (keys (plist-get index :keys))
         (pages (plist-get index :pages))
         (key (diogenes-montanari--greek-key word))
         (n (length keys)))
    (when (and (> (length key) 0) (> n 0))
      ;; Binary search: rightmost i with keys[i] <= key.
      (let ((lo 0) (hi n) (found -1))
        (while (< lo hi)
          (let* ((mid (/ (+ lo hi) 2))
                 (k (aref keys mid)))
            (if (or (string< k key) (string= k key))
                (progn (setq found mid) (setq lo (1+ mid)))
              (setq hi mid))))
        (let ((page (aref pages (if (>= found 0) found 0))))
          (+ page diogenes-cambridge-page-offset))))))

;;;; --------------------------------------------------------------------
;;;; INTERACTIVE ENTRY POINTS
;;;; --------------------------------------------------------------------

(defvar diogenes--lookup-headword)      ; from diogenes-perseus.el

(declare-function diogenes--lookup-headword-at-point "diogenes-perseus" (&optional pos))

(defun diogenes-cambridge--current-headword ()
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
(defun diogenes-lookup-open-cambridge (&optional word)
  "Open the Cambridge Greek Lexicon PDF at the entry for WORD.
Interactively, WORD defaults to the headword of the Greek entry at
point in a `diogenes-lookup-mode' buffer.  With a prefix argument,
prompt for the word.

Requires `diogenes-cambridge-pdf-file' to point at a CGL PDF with a
one-word-per-page outline, and `pdf-tools' (recommended) or
`doc-view' for display."
  (interactive
   (progn
     (diogenes--lookup-assert-lang "greek" "The Cambridge Greek Lexicon")
     (list (if current-prefix-arg
               (read-string "Open Cambridge Greek Lexicon at word: ")
             (diogenes-cambridge--current-headword)))))
  (let* ((word (or word (diogenes-cambridge--current-headword)))
         (page (diogenes-cambridge--page-for-word word)))
    (unless page
      (user-error "Could not locate \"%s\" in the Cambridge Greek Lexicon outline" word))
    ;; Reuse the OLD module's viewer driver (pdf-tools/doc-view, async
    ;; startup, page clamping, large-file prompt).
    (diogenes-old--show-page page diogenes-cambridge-pdf-file)
    (message "Cambridge Greek Lexicon: \"%s\" -> page %d" word page)))

;;;###autoload
(defun diogenes-cambridge-clear-cache ()
  "Forget the cached Cambridge Greek Lexicon page index.
Call this if you replace or re-bookmark the CGL PDF while Emacs is
running."
  (interactive)
  (clrhash diogenes-cambridge--index-cache)
  (message "Diogenes Cambridge Greek Lexicon index cache cleared"))

(provide 'diogenes-cambridge)
;;; diogenes-cambridge.el ends here
