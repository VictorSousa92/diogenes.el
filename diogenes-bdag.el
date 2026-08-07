;;; diogenes-bdag.el --- Open the BDAG (Bauer) Greek NT lexicon PDF -*- lexical-binding: t -*-

;; Copyright (C) 2024 Michael Neidhart
;;
;; Author: Michael Neidhart <mayhoth@gmail.com>
;; Keywords: classics, tools, philology, humanities

;;; Commentary:

;; This module lets you jump from a Diogenes *Greek* dictionary entry
;; (the buffer produced by `diogenes-lookup-mode') to the page of BDAG
;; -- Bauer's _Greek-English Lexicon of the New Testament_ (Bauer,
;; Danker, Arndt, Gingrich) -- that contains that entry, displayed with
;; `pdf-tools' (or `doc-view').  It is a Greek counterpart of
;; `diogenes-old.el' and reuses that module's PDF display code, and it
;; shares the accent-insensitive Greek collation key with the Montanari
;; module (`diogenes-montanari--greek-key').
;;
;; The BDAG PDF is bookmarked with one HEADWORD INTERVAL per page, in
;; the form "<n>: <first> - <last>", e.g.
;;
;;   2: ἀβροχία - ἀγαθός
;;   3: ἀγαθότης - ἀγαλλίασις
;;
;; Pages that begin a letter, or that are wholly taken up by one long
;; entry, carry a single word instead of an interval (e.g. "5: ἀγάπη",
;; "290: ἐν"); such a word is treated as both bounds of the page.
;;
;; Unlike the Montanari scan, BDAG's bookmark text is clean, accented
;; Unicode Greek, so a word is matched to the page whose interval
;; CONTAINS it (first <= word <= last); words falling in a gap use the
;; nearest preceding page.  Matching is accent- and case-insensitive.
;;
;; Setup:
;;
;;   (setq diogenes-bdag-pdf-file "/path/to/BDAG.pdf")
;;
;; Then, in a Greek lookup buffer, press `d' or click the "[BDAG]" link.

;;; Code:
(require 'cl-lib)
(require 'seq)
(require 'diogenes-old)                 ; reuse PDF display + cache pattern
(require 'diogenes-montanari)           ; reuse the Greek collation key

(declare-function pdf-info-outline "pdf-info" (&optional file-or-buffer))

;;;; --------------------------------------------------------------------
;;;; CUSTOMIZATION
;;;; --------------------------------------------------------------------

(defcustom diogenes-bdag-pdf-file nil
  "Path to a PDF of BDAG (Bauer's Greek-English NT lexicon).
For the page lookup to work, this PDF must contain an outline
whose entries give each page's headword interval in the form
\"<n>: <first> - <last>\", as in

  2: ἀβροχία - ἀγαθός

The two headwords are separated by a hyphen."
  :type '(choice (const :tag "Not set" nil) file)
  :group 'diogenes)

(defcustom diogenes-bdag-page-offset 0
  "Integer added to every page number derived from the BDAG outline.
Normally leave this at 0: outline destinations are physical page
indices and are already correct.  See `diogenes-old-page-offset'."
  :type 'integer
  :group 'diogenes)

(defcustom diogenes-bdag-interval-regexp
  "\\`[[:space:]]*[0-9]+[[:space:]]*:[[:space:]]*\\(.+?\\)[[:space:]]*[–—‒―−-][[:space:]]*\\(.+?\\)[[:space:]]*\\'"
  "Regexp extracting a page's headword interval from a BDAG title.
Group 1 is the first headword on the page, group 2 the last.  The
default matches titles such as \"2: ἀβροχία - ἀγαθός\"."
  :type 'regexp
  :group 'diogenes)

(defcustom diogenes-bdag-single-regexp
  "\\`[[:space:]]*[0-9]+[[:space:]]*:[[:space:]]*\\(.+?\\)[[:space:]]*\\'"
  "Regexp for a BDAG bookmark title carrying only one headword.
Letter-opening pages and pages filled by one long entry are
bookmarked with a single word; group 1 captures it, and it is
treated as both the low and high bound of that page."
  :type 'regexp
  :group 'diogenes)

;;;; --------------------------------------------------------------------
;;;; READING THE PDF OUTLINE
;;;; --------------------------------------------------------------------

(defvar diogenes-bdag--index-cache (make-hash-table :test 'equal)
  "Cache mapping a PDF cache-key to its parsed page-interval index.")

(defun diogenes-bdag--parse-title (title)
  "Parse a BDAG bookmark TITLE into (LOW-KEY . HIGH-KEY), or nil.
Recognises both the \"<n>: A - B\" interval form and the single
\"<n>: A\" form (returning A as both bounds).  Letter headers such
as \"Α, α\" carry no running number and yield nil."
  (cond
   ((string-match diogenes-bdag-interval-regexp title)
    (let ((lo (diogenes-montanari--greek-key (match-string 1 title)))
          (hi (diogenes-montanari--greek-key (match-string 2 title))))
      (when (and (> (length lo) 0) (> (length hi) 0))
        ;; BDAG's text is clean, so bounds are reliable; keep as-is.
        (cons lo hi))))
   ((string-match diogenes-bdag-single-regexp title)
    (let ((w (diogenes-montanari--greek-key (match-string 1 title))))
      (when (> (length w) 0) (cons w w))))))

(defun diogenes-bdag--build-index (file)
  "Read FILE's outline and return a sorted page-interval index.
Each element is (LOW-KEY HIGH-KEY PAGE), sorted ascending by
LOW-KEY then PAGE.  Letter headers and unparseable titles are
skipped.  Signals a user-error if nothing usable is found."
  (unless (require 'pdf-info nil t)
    (user-error "pdf-tools is not installed; cannot read the BDAG outline.  \
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
                   ;; Letter headers ("Α, α") lack a running number and
                   ;; fail both regexps, so the parser filters them.
                   for parsed = (and (integerp page) (> page 0)
                                     (diogenes-bdag--parse-title title))
                   when parsed
                   collect (list (car parsed) (cdr parsed) page))))
    (when (null index)
      (user-error "The PDF %s has no usable BDAG page intervals in its outline" file))
    (sort index (lambda (a b)
                  (or (string< (car a) (car b))
                      (and (string= (car a) (car b))
                           (< (caddr a) (caddr b))))))))

(defun diogenes-bdag--cache-key (file)
  "Return a cache key for FILE combining its truename and mtime."
  (let ((true (file-truename file)))
    (cons true
          (file-attribute-modification-time (file-attributes true)))))

(defun diogenes-bdag--index (&optional file)
  "Return the cached page-interval index for FILE.
FILE defaults to `diogenes-bdag-pdf-file'."
  (let ((file (or file diogenes-bdag-pdf-file)))
    (unless file
      (user-error "Set `diogenes-bdag-pdf-file' to your BDAG PDF first"))
    (unless (file-readable-p file)
      (user-error "Cannot read BDAG PDF at %s" file))
    (let ((key (diogenes-bdag--cache-key file)))
      (or (gethash key diogenes-bdag--index-cache)
          (setf (gethash key diogenes-bdag--index-cache)
                (diogenes-bdag--build-index file))))))

;;;; --------------------------------------------------------------------
;;;; HEADWORD -> PAGE
;;;; --------------------------------------------------------------------

(defun diogenes-bdag--page-for-word (word &optional file)
  "Return the BDAG page number containing WORD's entry.
Each index element covers the interval [LOW, HIGH] of headwords on
a page.  We return the page whose interval contains WORD's Greek
key; if WORD falls in a gap between pages, the nearest preceding
page is used.  Returns an integer page (with
`diogenes-bdag-page-offset' applied) or nil."
  (let* ((index (diogenes-bdag--index file))
         (key (diogenes-montanari--greek-key word))
         (nearest nil)
         (contained nil))
    (when (> (length key) 0)
      (cl-loop for (lo hi page) in index
               while (or (string< lo key) (string= lo key))
               do (setq nearest page)
               when (or (string< key hi) (string= key hi))
               do (setq contained page)))
    (let ((page (or contained nearest (caddr (car index)))))
      (when page
        (+ page diogenes-bdag-page-offset)))))

;;;; --------------------------------------------------------------------
;;;; INTERACTIVE ENTRY POINTS
;;;; --------------------------------------------------------------------

(defvar diogenes--lookup-headword)      ; from diogenes-perseus.el

(defun diogenes-bdag--current-headword ()
  "Return the headword to look up for the Greek entry at point."
  (or (and (boundp 'diogenes--lookup-headword) diogenes--lookup-headword)
      (get-text-property (point) 'orth)
      (thing-at-point 'word t)
      (user-error "No headword found at point")))

;;;###autoload
(defun diogenes-lookup-open-bdag (&optional word)
  "Open the BDAG (Bauer) NT lexicon PDF at the entry for WORD.
Interactively, WORD defaults to the headword of the Greek entry at
point in a `diogenes-lookup-mode' buffer.  With a prefix argument,
prompt for the word.

Requires `diogenes-bdag-pdf-file' to point at a BDAG PDF with an
interval outline, and `pdf-tools' (recommended) or `doc-view' for
display."
  (interactive
   (list (if current-prefix-arg
             (read-string "Open BDAG at word: ")
           (diogenes-bdag--current-headword))))
  (let* ((word (or word (diogenes-bdag--current-headword)))
         (page (diogenes-bdag--page-for-word word)))
    (unless page
      (user-error "Could not locate \"%s\" in the BDAG outline" word))
    ;; Reuse the OLD module's viewer driver (pdf-tools/doc-view, async
    ;; startup, page clamping, large-file prompt).
    (diogenes-old--show-page page diogenes-bdag-pdf-file)
    (message "BDAG: \"%s\" -> page %d" word page)))

;;;###autoload
(defun diogenes-bdag-clear-cache ()
  "Forget the cached BDAG page index.
Call this if you replace or re-bookmark the BDAG PDF while Emacs
is running."
  (interactive)
  (clrhash diogenes-bdag--index-cache)
  (message "Diogenes BDAG index cache cleared"))

(provide 'diogenes-bdag)
;;; diogenes-bdag.el ends here
