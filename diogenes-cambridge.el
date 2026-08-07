;;; diogenes-cambridge.el --- Open the Cambridge Greek Lexicon PDF -*- lexical-binding: t -*-

;; Copyright (C) 2024 Michael Neidhart
;;
;; Author: Michael Neidhart <mayhoth@gmail.com>
;; Keywords: classics, tools, philology, humanities

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
  "Parse a CGL bookmark TITLE into (KEY PARITY), or nil.
KEY is the Greek collation key of the guide word; PARITY is the
symbol `odd' (guide word is the page's LAST headword) or `even'
\(guide word is the page's FIRST headword), taken from the running
number.  Letter-header titles like \"Α, α\" do not match the
running-number pattern and yield nil."
  (when (string-match diogenes-cambridge-entry-regexp title)
    (let* ((n (string-to-number (match-string 1 title)))
           (word (match-string 2 title))
           (key (diogenes-montanari--greek-key word)))
      (when (> (length key) 0)
        (list key (if (cl-oddp n) 'odd 'even))))))

(defun diogenes-cambridge--build-index (file)
  "Read FILE's outline and return the CGL guide-word index.
The return value is a plist:
  :by-page  a vector of (PAGE KEY PARITY), in reading (page) order;
  :order    a vector of indices into :by-page, sorted by KEY.
Letter headers and unparseable titles are skipped.  Signals a
user-error if nothing usable is found."
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
                   for parsed = (and (integerp page) (> page 0)
                                     (diogenes-cambridge--parse-title title))
                   when parsed
                   collect (list page (car parsed) (cadr parsed)))))
    (when (null rows)
      (user-error "The PDF %s has no usable CGL guide words in its outline" file))
    ;; Reading order = page order.
    (let* ((by-page (vconcat (sort rows (lambda (a b) (< (car a) (car b))))))
           (n (length by-page))
           ;; Order indices by KEY (then page), for binary search.
           (order (vconcat
                   (sort (number-sequence 0 (1- n))
                         (lambda (i j)
                           (let ((ki (nth 1 (aref by-page i)))
                                 (kj (nth 1 (aref by-page j))))
                             (or (string< ki kj)
                                 (and (string= ki kj)
                                      (< (car (aref by-page i))
                                         (car (aref by-page j)))))))))))
      (list :by-page by-page :order order))))

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

(defun diogenes-cambridge--bisect-last-<= (by-page order key)
  "Return the reading-order index of the last guide word sorting <= KEY.
BY-PAGE and ORDER are as in `diogenes-cambridge--build-index'.
Returns nil if KEY precedes every guide word."
  (let ((lo 0) (hi (length order)) (found nil))
    ;; Binary search over ORDER (sorted by key) for the rightmost entry
    ;; whose key <= KEY; return the corresponding BY-PAGE index.
    (while (< lo hi)
      (let* ((mid (/ (+ lo hi) 2))
             (idx (aref order mid))
             (k (nth 1 (aref by-page idx))))
        (if (or (string< k key) (string= k key))
            (progn (setq found idx) (setq lo (1+ mid)))
          (setq hi mid))))
    found))

(defun diogenes-cambridge--page-for-word (word &optional file)
  "Return the CGL page number for WORD's entry.
Finds the nearest preceding guide word by an accent-insensitive
binary search, then refines with the running-number parity: if
that guide word is a page's LAST headword (odd) and WORD sorts
strictly after it, WORD is on the following page.  Returns an
integer page (with `diogenes-cambridge-page-offset' applied) or
nil."
  (let* ((index (diogenes-cambridge--index file))
         (by-page (plist-get index :by-page))
         (order (plist-get index :order))
         (key (diogenes-montanari--greek-key word)))
    (when (and (> (length key) 0) (> (length by-page) 0))
      (let* ((i (diogenes-cambridge--bisect-last-<= by-page order key))
             (page
              (cond
               ;; WORD precedes every guide word: use the first page.
               ((null i) (car (aref by-page 0)))
               (t (let* ((row (aref by-page i))
                         (rkey (nth 1 row))
                         (par (nth 2 row))
                         (rpage (car row)))
                    (cond
                     ;; Exact guide word: it is on this page regardless of role.
                     ((string= rkey key) rpage)
                     ;; Guide word is the page's LAST headword and WORD sorts
                     ;; after it => WORD is on the next page in reading order.
                     ((and (eq par 'odd) (< (1+ i) (length by-page)))
                      (car (aref by-page (1+ i))))
                     ;; Guide word is the page's FIRST headword (or no next
                     ;; page): WORD is on this page.
                     (t rpage)))))))
        (when page
          (+ page diogenes-cambridge-page-offset))))))

;;;; --------------------------------------------------------------------
;;;; INTERACTIVE ENTRY POINTS
;;;; --------------------------------------------------------------------

(defvar diogenes--lookup-headword)      ; from diogenes-perseus.el

(defun diogenes-cambridge--current-headword ()
  "Return the headword to look up for the Greek entry at point."
  (or (and (boundp 'diogenes--lookup-headword) diogenes--lookup-headword)
      (get-text-property (point) 'orth)
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
   (list (if current-prefix-arg
             (read-string "Open Cambridge Greek Lexicon at word: ")
           (diogenes-cambridge--current-headword))))
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
