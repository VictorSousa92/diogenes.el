;;; diogenes-pdf-search.el --- Look up an entry inside an open dictionary PDF -*- lexical-binding: t -*-

;; Copyright (C) 2024 Michael Neidhart
;;
;; Author: Michael Neidhart <mayhoth@gmail.com>
;; Keywords: classics, tools, philology, humanities

;;; Commentary:

;; This module adds ONE command, `diogenes-pdf-lookup-entry', that you
;; run *from inside an open dictionary PDF* (a `pdf-view-mode' or
;; `doc-view-mode' buffer).  It reads a headword from the minibuffer --
;; exactly the way `diogenes-lookup-greek' reads a word to search the
;; LSJ, or `diogenes-lookup-latin' for Lewis & Short -- and jumps the
;; *current* PDF to the page containing that entry.
;;
;; It is a companion to the per-dictionary "open the PDF at this
;; entry" commands (`diogenes-lookup-open-old', `-open-bdag',
;; `-open-montanari', ...).  Those start FROM a Diogenes lookup buffer
;; and open the print dictionary.  This one is the reverse workflow:
;; you are ALREADY reading the print dictionary as a PDF, you want to
;; look up a different word, and you would rather type it in the
;; minibuffer than page around by hand or run the outline search.
;;
;; It works for every print dictionary the package knows how to open:
;;
;;   OLD        Oxford Latin Dictionary       (diogenes-old)
;;   TLL        Thesaurus Linguae Latinae     (diogenes-tll, per-fascicle)
;;   Montanari  Brill Dictionary of Gk        (diogenes-montanari)
;;   CGL        Cambridge Greek Lexicon       (diogenes-cambridge)
;;   BDAG       Bauer (Danker) Gk NT lexicon  (diogenes-bdag)
;;   Bailly     Dictionnaire grec-français    (diogenes-bailly-pdf)
;;   Gaffiot    Dictionnaire latin-français   (diogenes-gaffiot-pdf)
;;   Georges    Lat.-deutsches Handwörterbuch (diogenes-georges, 2 vols.)
;;   Passow     Passow's Handwörterbuch       (diogenes-passow, multi-volume)
;;   TGL        Estienne, Thesaurus Gk Ling.  (diogenes-tgl, multi-volume)
;;
;; The command figures out WHICH dictionary the buffer is showing by
;; matching the visited file against each module's configured path
;; variable (`diogenes-old-pdf-file', `diogenes-tll-pdf-directory',
;; the TGL volume folder, etc.), then reuses that module's existing,
;; already-tuned page-lookup logic -- so the page it lands on is the
;; same one the corresponding "[OLD]"/"[BDAG]"/... link would open.
;;
;; Setup: just require it and bind the command in the PDF viewers.  A
;; ready-made installer is provided:
;;
;;   (require 'diogenes-pdf-search)
;;   (diogenes-pdf-search-setup-keys)     ; binds "L" in pdf/doc-view
;;
;; or bind it yourself:
;;
;;   (with-eval-after-load 'pdf-view
;;     (keymap-set pdf-view-mode-map "L" #'diogenes-pdf-lookup-entry))
;;
;; With point already on a word in the PDF (pdf-tools lets you select
;; text), that word is offered as the default, just as `thing-at-point'
;; prefills the LSJ/Lewis prompts.

;;; Code:
(require 'cl-lib)
(require 'diogenes-lisp-utils)          ; diogenes--display-buffer
(require 'seq)
(declare-function evil-make-overriding-map "evil-core" (keymap &optional state copy))
(declare-function evil-normalize-keymaps "evil-core" (&optional state))

;; Each print-dictionary module is optional at load time: we only need
;; the one matching the PDF actually open.  Declare what we call so the
;; byte-compiler is quiet, and `require' lazily at dispatch time.
(declare-function diogenes-old--page-for-word        "diogenes-old"       (word &optional file))
(declare-function diogenes-old--show-page            "diogenes-old"       (page &optional file))
(declare-function diogenes-montanari--page-for-word  "diogenes-montanari" (word &optional file))
(declare-function diogenes-cambridge--page-for-word  "diogenes-cambridge" (word &optional file))
(declare-function diogenes-bdag--page-for-word       "diogenes-bdag"      (word &optional file))
(declare-function diogenes-bailly-pdf--page-for-word     "diogenes-bailly-pdf"    (word &optional file))
(declare-function diogenes-gaffiot-pdf--page-for-word "diogenes-gaffiot-pdf" (word &optional file))
(declare-function diogenes-georges--locate            "diogenes-georges"   (word))
(declare-function diogenes-tll--file-for-word        "diogenes-tll"       (word))
(declare-function diogenes-tll--page-for-word        "diogenes-tll"       (word file))
(declare-function diogenes-passow--locate            "diogenes-passow"    (word))
(declare-function diogenes-passow--pdf-page          "diogenes-passow"    (pg))
(declare-function diogenes-tgl--locate               "diogenes-tgl"       (word))
(declare-function diogenes-tgl--volume-pdf           "diogenes-tgl"       (tomus))
(declare-function diogenes-tgl--show                 "diogenes-tgl"       (tomus page &optional word))
(declare-function diogenes-tgl--approx-locate        "diogenes-tgl"       (word))
(declare-function diogenes-tgl--anomalous-approx     "diogenes-tgl"       (word))
(declare-function diogenes-tgl--volume-text          "diogenes-tgl"       (tomus))
(declare-function diogenes-tgl--column-model         "diogenes-tgl"       (file))
(declare-function diogenes-tgl--column-to-page       "diogenes-tgl"       (column model &optional part))
(declare-function diogenes-tgl--v5-part1-first-column "diogenes-tgl"      (model))

(declare-function pdf-view-goto-page          "pdf-view" (page &optional window))
(declare-function pdf-info-number-of-pages    "pdf-info" (&optional file-or-buffer))
(declare-function pdf-view-active-region-text "pdf-view" ())
(declare-function pdf-view-active-region-p    "pdf-view" ())
(declare-function doc-view-goto-page          "doc-view" (page))

(defvar diogenes-old-pdf-file)
(defvar diogenes-tll-pdf-directory)
(defvar diogenes-montanari-pdf-file)
(defvar diogenes-cambridge-pdf-file)
(defvar diogenes-bdag-pdf-file)
(defvar diogenes-bailly-pdf-file)
(defvar diogenes-gaffiot-pdf-file)
(defvar diogenes-georges-directory)
(defvar diogenes-passow-directory)
(defvar diogenes-tgl-directory)
(defvar diogenes-old-display-in-other-window)

;;;; --------------------------------------------------------------------
;;;; IDENTIFYING WHICH DICTIONARY THE BUFFER SHOWS
;;;; --------------------------------------------------------------------

(defun diogenes-pdf-search--same-file-p (a b)
  "Return non-nil if paths A and B name the same file.
Compares truenames, so symlinks and \"..\"/\".\" differences do not
matter.  Nil if either argument is nil."
  (and a b
       (string= (file-truename a) (file-truename b))))

(defun diogenes-pdf-search--under-dir-p (file dir)
  "Return non-nil if FILE lies inside directory DIR (recursively).
Both are compared as truenames.  Nil if either argument is nil."
  (and file dir
       (let ((f (file-truename file))
             (d (file-name-as-directory (file-truename dir))))
         (string-prefix-p d f))))

(defun diogenes-pdf-search--tgl-tomus (file)
  "If FILE is a PDF inside a TGL volume folder, return that volume number.
`diogenes-tgl-directory' holds one sub-folder per volume; a volume's
PDF sits inside it.  Returns the tomus (an integer 1..N) whose folder
contains FILE, or nil.  Requires the `diogenes-tgl' module and its
`diogenes-tgl--volume-pdf' resolver."
  (when (and (boundp 'diogenes-tgl-directory)
             diogenes-tgl-directory
             (diogenes-pdf-search--under-dir-p file diogenes-tgl-directory)
             (require 'diogenes-tgl nil t)
             (fboundp 'diogenes-tgl--volume-pdf))
    (cl-loop for tomus from 1 to 9
             for pdf = (ignore-errors (diogenes-tgl--volume-pdf tomus))
             when (diogenes-pdf-search--same-file-p file pdf)
             return tomus)))

(defun diogenes-pdf-search--identify (file)
  "Identify which print dictionary the PDF FILE belongs to.
Returns a symbol: `old', `tll', `montanari', `cambridge', `bdag',
`bailly', `gaffiot', `georges', `passow' or `tgl', or nil when FILE matches no configured
dictionary path.  Each match `require's its module lazily so an
unused dictionary need not be loaded.

Single-file dictionaries match by truename against their
`...-pdf-file' variable; the TLL matches any PDF under
`diogenes-tll-pdf-directory'; the TGL matches any PDF inside a
`diogenes-tgl-directory' volume folder."
  (cond
   ;; Single-file dictionaries (compare against the configured file).
   ((and (boundp 'diogenes-old-pdf-file)
         (diogenes-pdf-search--same-file-p file diogenes-old-pdf-file))
    (and (require 'diogenes-old nil t) 'old))
   ((and (boundp 'diogenes-montanari-pdf-file)
         (diogenes-pdf-search--same-file-p file diogenes-montanari-pdf-file))
    (and (require 'diogenes-montanari nil t) 'montanari))
   ((and (boundp 'diogenes-cambridge-pdf-file)
         (diogenes-pdf-search--same-file-p file diogenes-cambridge-pdf-file))
    (and (require 'diogenes-cambridge nil t) 'cambridge))
   ((and (boundp 'diogenes-bdag-pdf-file)
         (diogenes-pdf-search--same-file-p file diogenes-bdag-pdf-file))
    (and (require 'diogenes-bdag nil t) 'bdag))
   ((and (boundp 'diogenes-bailly-pdf-file)
         (diogenes-pdf-search--same-file-p file diogenes-bailly-pdf-file))
    (and (require 'diogenes-bailly-pdf nil t) 'bailly))
   ((and (boundp 'diogenes-gaffiot-pdf-file)
         (diogenes-pdf-search--same-file-p file diogenes-gaffiot-pdf-file))
    (and (require 'diogenes-gaffiot-pdf nil t) 'gaffiot))
   ;; Georges: a folder holding the two volumes' PDFs.
   ((and (boundp 'diogenes-georges-directory)
         (diogenes-pdf-search--under-dir-p file diogenes-georges-directory))
    (and (require 'diogenes-georges nil t) 'georges))
   ;; Passow: a parent folder of per-volume sub-directories, each with a PDF.
   ((and (boundp 'diogenes-passow-directory)
         (diogenes-pdf-search--under-dir-p file diogenes-passow-directory))
    (and (require 'diogenes-passow nil t) 'passow))
   ;; TLL: a whole folder of fascicle PDFs.
   ((and (boundp 'diogenes-tll-pdf-directory)
         (diogenes-pdf-search--under-dir-p file diogenes-tll-pdf-directory))
    (and (require 'diogenes-tll nil t) 'tll))
   ;; TGL: a folder per volume, each holding a PDF.
   ((diogenes-pdf-search--tgl-tomus file)
    'tgl)))

;; Human-readable names for messages/prompts, keyed by the symbol above.
(defconst diogenes-pdf-search--names
  '((old       . "OLD")
    (tll       . "TLL")
    (montanari . "Montanari")
    (cambridge . "Cambridge Greek Lexicon")
    (bdag      . "BDAG")
    (bailly    . "Bailly")
    (gaffiot   . "Gaffiot")
    (georges   . "Georges")
    (passow    . "Passow")
    (tgl       . "TGL"))
  "Alist mapping a dictionary symbol to its display name.")

(defun diogenes-pdf-search--name (dict)
  "Return a display name for dictionary symbol DICT."
  (or (cdr (assq dict diogenes-pdf-search--names))
      (symbol-name dict)))

;;;; --------------------------------------------------------------------
;;;; JUMPING WITHIN THE CURRENT PDF BUFFER
;;;; --------------------------------------------------------------------

(defun diogenes-pdf-search--goto-page (page)
  "Jump the CURRENT PDF buffer to PAGE.
Works in `pdf-view-mode' (clamping to the document length),
`doc-view-mode', and the Emacs Reader's `reader-mode'.  Signals a
user-error in any other mode."
  (cond
   ((derived-mode-p 'pdf-view-mode)
    (let ((page (if (fboundp 'pdf-info-number-of-pages)
                    (max 1 (min page (pdf-info-number-of-pages)))
                  (max 1 page))))
      (pdf-view-goto-page page)))
   ((derived-mode-p 'doc-view-mode)
    (doc-view-goto-page (max 1 page)))
   ((and (derived-mode-p 'reader-mode) (fboundp 'reader-goto-page))
    ;; The Emacs Reader renders asynchronously; reuse the robust poll
    ;; from diogenes-old if available, else jump directly.
    (if (progn (require 'diogenes-old nil t)
               (fboundp 'diogenes-old--reader-goto-when-ready))
        (diogenes-old--reader-goto-when-ready (current-buffer) page)
      (let ((page (if (boundp 'reader-current-doc-pagecount)
                      (max 1 (min page reader-current-doc-pagecount))
                    (max 1 page))))
        (reader-goto-page page))))
   (t
    (user-error "Not in a PDF buffer (pdf-view-mode, doc-view-mode, or reader-mode)"))))

;;;; --------------------------------------------------------------------
;;;; PER-DICTIONARY: WORD -> (PAGE [. FILE]) FOR THE OPEN BUFFER
;;;; --------------------------------------------------------------------

;; Each helper returns either an integer page (jump within the current
;; buffer's file) or a cons (PAGE . FILE) when the entry lives in a
;; DIFFERENT physical file than the one on screen -- which happens with
;; the multi-file TLL and TGL.  In that case we open the sibling file.

(defun diogenes-pdf-search--resolve (dict word file)
  "Return where WORD's entry is, for dictionary DICT whose open PDF is FILE.
Returns an integer PAGE (in FILE), a cons (PAGE . OTHER-FILE) when
the entry is in a different physical volume/fascicle, or nil if the
word cannot be located.  Reuses each module's own page-lookup
logic, so results agree with that dictionary's link/opener command."
  (pcase dict
    ('old       (diogenes-old--page-for-word word file))
    ('montanari (diogenes-montanari--page-for-word word file))
    ('cambridge (diogenes-cambridge--page-for-word word file))
    ('bdag      (diogenes-bdag--page-for-word word file))
    ('bailly    (diogenes-bailly-pdf--page-for-word word file))
    ('gaffiot   (diogenes-gaffiot-pdf--page-for-word word file))
    ('georges
     ;; Two volumes, and the word chooses which; open the sibling when it is
     ;; not the one on screen.
     (let ((hit (diogenes-georges--locate word)))
       (unless hit
         (user-error "Could not locate \"%s\" in Georges" word))
       (let ((other (nth 0 hit))
             (page (nth 1 hit)))
         (if (diogenes-pdf-search--same-file-p other file)
             page
           (cons page other)))))
    ('passow
     ;; Passow is multi-volume; --locate returns (VOLUME . PAGE-PLIST),
     ;; where VOLUME is a plist carrying :pdf and PAGE-PLIST feeds
     ;; --pdf-page.  The entry may sit in a different volume PDF than
     ;; the one open, so return a sibling when it does.
     (let ((hit (diogenes-passow--locate word)))
       (unless hit
         (user-error "Could not locate \"%s\" in Passow (is its volume installed?)"
                     word))
       (let* ((vol  (car hit))
              (pg   (cdr hit))
              (pdf  (plist-get vol :pdf))
              (page (diogenes-passow--pdf-page pg)))
         (cond
          ((null page) nil)
          ((diogenes-pdf-search--same-file-p pdf file) page)
          (t (cons page pdf))))))
    ('tll
     ;; The TLL is split into fascicle PDFs; the word may live in a
     ;; DIFFERENT fascicle than the one open.  Find its fascicle, then
     ;; its page there.
     (let ((wfile (diogenes-tll--file-for-word word)))
       (unless wfile
         (user-error "No TLL fascicle covering \"%s\" is present" word))
       (let ((page (diogenes-tll--page-for-word word wfile)))
         (and page
              (if (diogenes-pdf-search--same-file-p wfile file)
                  page
                (cons page wfile))))))
    ('tgl
     ;; The TGL is multi-volume; --locate returns a plist with :tomus
     ;; and :page.  Resolve to that volume's PDF; open a sibling if the
     ;; entry is in another volume.
     (let ((loc (diogenes-tgl--locate word)))
       (unless loc
         (user-error "Could not locate \"%s\" in the TGL" word))
       (let* ((tomus (plist-get loc :tomus))
              (page  (plist-get loc :page))
              (pdf   (diogenes-tgl--volume-pdf tomus)))
         (cond
          ((null page) nil)
          ((diogenes-pdf-search--same-file-p pdf file) page)
          (t (cons page pdf))))))
    (_ (user-error "Unknown dictionary: %s" dict))))

;;;; --------------------------------------------------------------------
;;;; READING THE WORD FROM THE MINIBUFFER
;;;; --------------------------------------------------------------------

(defun diogenes-pdf-search--default-word ()
  "Return a sensible default word for the prompt, or nil.
The PDF's own text selection, where there is one: pdf-tools lets one select
text with the mouse, and that is a word the reader has pointed at.

And NOTHING otherwise, in a document buffer.  `thing-at-point\=' there reads the
buffer's text, which is the bytes of the file -- so the prompt offered `%PDF\=',
the first four of them, and a reader pressing RET looked that up.  A default is
a guess at what is meant, and there is nothing in a page image to guess from.

In a plain buffer -- the command is not confined to scans -- the word at point
is the sensible guess and is used."
  (cond
   ((and (derived-mode-p 'pdf-view-mode)
         (fboundp 'pdf-view-active-region-p)
         (pdf-view-active-region-p)
         (fboundp 'pdf-view-active-region-text))
    (let ((txt (car (pdf-view-active-region-text))))
      (and txt (string-trim txt))))
   ((or (derived-mode-p 'pdf-view-mode 'doc-view-mode)
        (and (fboundp 'reader-mode) (derived-mode-p 'reader-mode)))
    nil)
   (t (thing-at-point 'word t))))

;;;; --------------------------------------------------------------------
;;;; THE COMMAND
;;;; --------------------------------------------------------------------

(defun diogenes-pdf-search--tgl-v5-index-then-column (part-known)
  "Prompt for a volume-V index column; return the (WORD COLUMN-REF nil) list.
When PART-KNOWN is nil, first ask which of the two index parts (their
column numbering each restart at 1)."
  (let* ((part (if part-known part-known
                 (if (eq (car (read-multiple-choice
                               "Index part: "
                               '((?1 "part-1" "Main index (columns from 229)")
                                 (?2 "part-2" "Second index (column numbering restarts at 1)"))))
                         ?2)
                     2 1)))
         (column (read-number "Index column (C) number: ")))
    (list nil (list :v5-index :part part :column column) nil)))

(defun diogenes-pdf-search--tgl-v5-prompt ()
  "Prompt for a volume-V jump; return a (WORD COLUMN-REF APPROXIMATE) list.
Offers, from within volume V:
  * its own two-part INDEX (part 1 or 2, then a column);
  * the ANOMALOUS-ROOTS section (by column, or approximate search); and
  * a jump to ANOTHER TOME by index reference (t.N c.NNN) -- useful when
    reading a `t.3 c.746'-style pointer in the index and wanting to
    follow it into tomes I-IV (or back into volume V's own index).
Shared by both entry points: pressing \\[diogenes-pdf-lookup-entry]
inside volume V, and answering \"5\" to the tomus prompt from another
volume."
  (let ((top (car (read-multiple-choice
                   "TGL vol V: "
                   '((?i "index" "This volume's alphabetical INDEX (parts 1-2)")
                     (?a "anomalous" "The anomalous/poetic verb-forms section")
                     (?t "other-tome" "Jump by reference t.N c.NNN into another tome"))))))
    (pcase top
      (?i (diogenes-pdf-search--tgl-v5-index-then-column nil))
      (?t
       ;; Cross-tome index reference.  Tomus 5 loops back into this
       ;; volume's own two-part index; tomes 1-4 take a plain column.
       (let ((tm (read-number "TGL tomus (1-5): ")))
         (if (eql tm 5)
             (diogenes-pdf-search--tgl-v5-index-then-column nil)
           (let ((column (read-number "TGL column (C) number: ")))
             (list nil (cons tm column) nil)))))
      (_
       (let ((how (car (read-multiple-choice
                        "Anomalous roots: "
                        '((?c "column" "Jump to a column number in this section")
                          (?a "approximate" "Search a word by approximation"))))))
         (if (eq how ?c)
             (let ((column (read-number "Anomalous-roots column (C) number: ")))
               (list nil (list :v5-anomalous-column :column column) nil))
           (list (read-from-minibuffer
                  "Approximate (prefix) in anomalous roots: "
                  (diogenes-pdf-search--default-word))
                 (list :v5-anomalous-approx) t)))))))

(defun diogenes-pdf-search--tgl-column-page (tomus column &optional part)
  "Return the PDF page in TGL volume TOMUS for printed COLUMN, or signal.
Maps COLUMN to a page via TOMUS's column model (the same column->page
backbone the index lookup uses) and applies `diogenes-tgl-page-offset'.
For volume V, PART (1 or 2) selects the index part, since its column
numbering restarts in part 2.  Signals a `user-error' if TOMUS is not
installed, its OCR/model is missing, or COLUMN cannot be placed."
  (let ((txt (diogenes-tgl--volume-text tomus)))
    (unless txt
      (user-error "TGL volume %s is not installed" tomus))
    (let ((model (diogenes-tgl--column-model txt)))
      (unless model
        (user-error "No column model for TGL volume %s (missing/unreadable OCR)"
                    tomus))
      (let ((page (diogenes-tgl--column-to-page column model part)))
        (unless page
          (user-error "Could not place column %d in TGL volume %s" column tomus))
        (+ page diogenes-tgl-page-offset)))))

;;;###autoload
(defun diogenes-pdf-lookup-entry (word &optional column-ref approximate)
  "Look up WORD's entry inside the dictionary PDF in the current buffer.
Run this from a `pdf-view-mode' (or `doc-view-mode') buffer that is
showing one of the print dictionaries Diogenes knows how to open --
the OLD, TLL, Montanari, Cambridge Greek Lexicon, BDAG, Passow, or
TGL.  Type a headword in the minibuffer and the CURRENT PDF jumps to
the page containing that entry.

This is the in-PDF analogue of `diogenes-lookup-greek' (\"Search LSJ
for: \") and `diogenes-lookup-latin' (\"Search Lewis & Short for: \"):
same minibuffer workflow, but it drives the print dictionary you are
already reading instead of the electronic LSJ/Lewis.  The word at
point -- or the PDF's active text selection -- is offered as the
default.

With a prefix argument (\\[universal-argument] then the key) the
command does an APPROXIMATE search instead of an exact lookup: type a
partial headword (a beginning of a word, e.g. \"ab\" or \"isth\") and
the PDF jumps to where that fragment falls alphabetically -- the first
entry that begins with, or sorts at, what you typed.  This is how you
reach a neighbourhood when you do not know or cannot type the whole
headword.

In a TGL volume the prefix argument first asks which of two jumps you
want -- \"Approximate search (a) or Index reference jump (i)\":
  a  approximate search, exactly as in the other dictionaries;
  i  index-reference jump -- prompts for a TOMUS and a column (C)
     number and jumps that volume's PDF to the page containing that
     column (the TGL index prints its references as \"t.N c.NNN\").

COLUMN-REF, when non-nil, is a (TOMUS . COLUMN) index-reference request
\(set only by the TGL prefix path, and it overrides WORD).  APPROXIMATE,
when non-nil, requests the positional/prefix search described above.

The buffer's dictionary is detected from the visited file, and an
exact lookup computes the page with that dictionary's own logic, so it
lands where the matching \"[OLD]\"/\"[BDAG]\"/... link would.  For the
multi-file TLL and TGL, an entry in another fascicle or volume opens
that sibling PDF."
  (interactive
   (let* ((file (or buffer-file-name
                    (user-error "This buffer is not visiting a PDF file")))
          (dict (or (diogenes-pdf-search--identify file)
                    (user-error
                     "This PDF is not a configured Diogenes dictionary.  \
Set the matching path variable (e.g. `diogenes-old-pdf-file') to this file"))))
     (cond
      ;; No prefix: ordinary exact lookup.
      ((not current-prefix-arg)
       (let ((prompt (format "Look up in %s: " (diogenes-pdf-search--name dict))))
         (list (read-from-minibuffer prompt (diogenes-pdf-search--default-word))
               nil nil)))
      ;; Prefix in the TGL.
      ((eq dict 'tgl)
       (let ((tomus (diogenes-pdf-search--tgl-tomus file)))
         (if (eql tomus 5)
             ;; Volume V: Index (two parts) or the anomalous-roots section.
             (diogenes-pdf-search--tgl-v5-prompt)
           ;; Volumes I-IV (or unknown): approximate search or index-ref jump.
           (let ((choice (car (read-multiple-choice
                               "TGL prefix jump: "
                               '((?a "approximate" "Approximate/prefix search, as in other dictionaries")
                                 (?i "index-ref"   "Jump by an index reference t.N c.NNN"))))))
             (if (eq choice ?i)
                 (let ((tm (read-number "TGL tomus (1-5): ")))
                   ;; A t.5 reference needs volume V's two-part / anomalous
                   ;; sub-menu, exactly as if we were inside volume V.
                   (if (eql tm 5)
                       (diogenes-pdf-search--tgl-v5-prompt)
                     (let ((column (read-number "TGL column (C) number: ")))
                       (list nil (cons tm column) nil))))
               (list (read-from-minibuffer "Approximate (prefix) in the TGL: "
                                           (diogenes-pdf-search--default-word))
                     nil t))))))
      ;; Prefix in any other dictionary: approximate search.
      (t
       (let ((prompt (format "Approximate (prefix) in %s: "
                             (diogenes-pdf-search--name dict))))
         (list (read-from-minibuffer prompt (diogenes-pdf-search--default-word))
               nil t))))))
  (let* ((file (or buffer-file-name
                   (user-error "This buffer is not visiting a PDF file")))
         (dict (or (diogenes-pdf-search--identify file)
                   (user-error "This PDF is not a configured Diogenes dictionary"))))
    (cond
     ;; --- TGL column / index-reference jumps ---------------------------
     ;; (The :v5-anomalous-approx marker also travels in column-ref but is an
     ;; approximate search, handled further below, so exclude it here.)
     ((and column-ref (not (eq (car-safe column-ref) :v5-anomalous-approx)))
      (unless (eq dict 'tgl)
        (user-error "Column jumps are only available in the TGL"))
      (pcase column-ref
        ;; Volume V, INDEX: (:v5-index :part P :column C)
        (`(:v5-index . ,plist)
         (let ((part (plist-get plist :part))
               (column (plist-get plist :column)))
           (unless (and (integerp column) (> column 0))
             (user-error "Index column must be a positive number"))
           ;; Part 1's numbered index does not begin at column 1: the earlier
           ;; columns are volume V's front matter (dialects, anomalous roots,
           ;; Herodian).  If the requested part-1 column is before the index
           ;; proper, say so rather than jump to a nonsensical page.
           (when (eql (or part 1) 1)
             (let* ((txt (ignore-errors (diogenes-tgl--volume-text 5)))
                    (model (and txt (diogenes-tgl--column-model txt)))
                    (first (and model
                                (diogenes-tgl--v5-part1-first-column model))))
               (when (and first (< column first))
                 (user-error
                  "The main index (part 1) begins at column %d; column %d falls in the front matter before it (dialects, anomalous roots, Herodian) -- use the Anomalous-roots option for those"
                  first column))))
           (let ((page (diogenes-pdf-search--tgl-column-page 5 column part)))
             (diogenes-tgl--show 5 page)
             (message "TGL vol V index part %d: c.%d -> page %d"
                      (or part 1) column page))))
        ;; Volume V, ANOMALOUS ROOTS by column: (:v5-anomalous-column :column C)
        ;; (the section continues part 1's numbering, so use part 1.)
        (`(:v5-anomalous-column . ,plist)
         (let ((column (plist-get plist :column)))
           (unless (and (integerp column) (> column 0))
             (user-error "Column must be a positive number"))
           (let ((page (diogenes-pdf-search--tgl-column-page 5 column 1)))
             (diogenes-tgl--show 5 page)
             (message "TGL vol V anomalous roots: c.%d -> page %d" column page))))
        ;; Volumes I-IV index reference: (TOMUS . COLUMN)
        (`(,tomus . ,column)
         (unless (and (integerp tomus) (<= 1 tomus 5))
           (user-error "TGL tomus must be between 1 and 5"))
         (unless (and (integerp column) (> column 0))
           (user-error "TGL column must be a positive number"))
         (let ((page (diogenes-pdf-search--tgl-column-page tomus column)))
           (diogenes-tgl--show tomus page)
           (message "TGL: t.%d c.%d -> page %d" tomus column page)))
        (_ (user-error "Malformed TGL column request"))))
     ;; --- Approximate (prefix) search in the TGL -----------------------
     ;; Land at the fragment's alphabetical position among the TGL's own
     ;; headwords via the body scan (which routes the key to its volume and
     ;; finds where it falls), opened under `diogenes-tgl-pdf-mode'.  When
     ;; the request is the volume-V anomalous-roots marker, position within
     ;; that section instead (`diogenes-tgl--anomalous-approx').
     ((and approximate (eq dict 'tgl))
      (let ((frag (string-trim (or word ""))))
        (when (string-empty-p frag)
          (user-error "No search fragment given"))
        (let ((loc (if (eq (car-safe column-ref) :v5-anomalous-approx)
                       (diogenes-tgl--anomalous-approx frag)
                     (diogenes-tgl--approx-locate frag))))
          (unless loc
            (user-error "Could not place \"%s\" in the TGL" frag))
          (let ((tomus (car loc)) (page (cdr loc)))
            (diogenes-tgl--show tomus page frag)
            (message "TGL: ~\"%s\" -> t.%s p.%d (approximate)" frag tomus page)))))
     ;; --- Approximate (prefix) search in every other dictionary --------
     ;; The dictionaries' own resolver is already positional (it lands on
     ;; the page whose guide word sorts at/after the input), so feeding it
     ;; a fragment jumps to that fragment's neighbourhood.
     (approximate
      (let ((frag (string-trim (or word ""))))
        (when (string-empty-p frag)
          (user-error "No search fragment given"))
        (let ((where (diogenes-pdf-search--resolve dict frag file)))
          (unless where
            (user-error "Could not place \"%s\" in %s"
                        frag (diogenes-pdf-search--name dict)))
          (cond
           ((integerp where)
            (diogenes-pdf-search--goto-page where)
            (message "%s: ~\"%s\" -> page %d (approximate)"
                     (diogenes-pdf-search--name dict) frag where))
           ((consp where)
            (let ((page (car where)) (other (cdr where)))
              (require 'diogenes-old nil t)
              (if (fboundp 'diogenes-old--show-page)
                  (diogenes-old--show-page page other)
                (let ((large-file-warning-threshold nil))
                  (pop-to-buffer (find-file-noselect other))
                  (diogenes-pdf-search--goto-page page)))
              (message "%s: ~\"%s\" -> %s p.%d (approximate)"
                       (diogenes-pdf-search--name dict)
                       frag (file-name-nondirectory other) page)))))))
     ;; --- TGL headword lookup ------------------------------------------
     ;; Resolve with the TGL's own locator and open through
     ;; `diogenes-tgl--show', so the (possibly sibling) volume opens under
     ;; `diogenes-tgl-pdf-mode' and remembers WORD for the `i' key.
     ((eq dict 'tgl)
      (let ((word (string-trim (or word ""))))
        (when (string-empty-p word)
          (user-error "No word given"))
        (let ((loc (diogenes-tgl--locate word)))
          (unless loc
            (user-error "Could not locate \"%s\" in the TGL" word))
          (let ((tomus (plist-get loc :tomus))
                (page  (plist-get loc :page)))
            (unless page
              (user-error "Could not locate \"%s\" in the TGL" word))
            (diogenes-tgl--show tomus page word)
            (message "TGL: \"%s\" -> t.%s p.%d" word tomus page)))))
     ;; --- Every other dictionary ---------------------------------------
     (t
      (let ((word (string-trim (or word ""))))
        (when (string-empty-p word)
          (user-error "No word given"))
        (let ((where (diogenes-pdf-search--resolve dict word file)))
          (unless where
            (user-error "Could not locate \"%s\" in %s"
                        word (diogenes-pdf-search--name dict)))
          (cond
           ;; Same file: jump within this very buffer.
           ((integerp where)
            (diogenes-pdf-search--goto-page where)
            (message "%s: \"%s\" -> page %d"
                     (diogenes-pdf-search--name dict) word where))
           ;; A sibling volume/fascicle: open it (reusing the shared viewer
           ;; driver so async pdf-tools startup and page clamping are handled).
           ((consp where)
            (let ((page (car where))
                  (other (cdr where)))
              (require 'diogenes-old nil t)  ; provides the viewer driver
              (if (fboundp 'diogenes-old--show-page)
                  (diogenes-old--show-page page other)
                ;; Fallback: open the file ourselves and jump.
                (let ((large-file-warning-threshold nil))
                  (pop-to-buffer (find-file-noselect other))
                  (diogenes-pdf-search--goto-page page)))
              (message "%s: \"%s\" -> %s p.%d"
                       (diogenes-pdf-search--name dict)
                       word (file-name-nondirectory other) page))))))))))

;;;; --------------------------------------------------------------------
;;;; KEY INSTALLATION
;;;; --------------------------------------------------------------------

(defcustom diogenes-pdf-search-key "L"
  "Key to bind `diogenes-pdf-lookup-entry' in the PDF viewers.
Used by `diogenes-pdf-search-setup-keys'.  The default is \"L\"
\(capital, mnemonic \"Lookup\"), which is unbound in `pdf-view-mode'
by default.

Note: lowercase \"l\" is NOT used, because `pdf-view-mode' inherits
it from `image-mode' as `image-forward-hscroll' (scroll the page
image right) -- binding it here would shadow that.  Set this to nil
to bind nothing and do it yourself."
  :type '(choice (const :tag "Do not bind" nil) key-sequence)
  :group 'diogenes)

(defvar diogenes-pdf-search-mode-map
  (make-sparse-keymap)
  "Keymap active in a PDF buffer visiting one of the print dictionaries.
Populated from `diogenes-pdf-search-key\=' when the mode is set up.")

;;;###autoload
(define-minor-mode diogenes-pdf-search-mode
  "Minor mode for a PDF buffer that is one of Diogenes\=' print dictionaries.
Carries `diogenes-pdf-search-key\=' (default \"L\"), which looks a headword up
in the dictionary you are reading.

Enabled per buffer, and only where the file is a configured dictionary --
`diogenes-pdf-search--identify\=' decides, from the path variables you have
set.  So the key exists in the OLD and the TLL and Montanari, and not in
every PDF you happen to open."
  :lighter " Dict"
  :keymap diogenes-pdf-search-mode-map)

(defun diogenes-pdf-search--maybe-enable ()
  "Turn on `diogenes-pdf-search-mode\=' if this buffer is a dictionary."
  (when (and diogenes-pdf-search-key
             buffer-file-name
             (ignore-errors (diogenes-pdf-search--identify buffer-file-name)))
    (diogenes-pdf-search-mode 1)))

;;;###autoload
(defun diogenes-pdf-search-setup-keys ()
  "Arrange for `diogenes-pdf-search-key\=' to work in the dictionary PDFs.
Binds the key in `diogenes-pdf-search-mode-map\=' and turns that mode on, from
the viewers\=' mode hooks, in a buffer whose file is a configured dictionary.
Safe to call at startup: the hooks attach whether or not the viewers are
loaded yet, and in either order.  Does nothing if `diogenes-pdf-search-key\='
is nil.

A MINOR mode rather than the viewers\=' own maps, and enabled per buffer
rather than per mode, because the key should exist where a dictionary is open
and nowhere else: `L\=' in an unrelated PDF is evil\='s `evil-window-bottom\=',
and there is no reason to take it away.

`evil-make-overriding-map\=' is what makes the key reachable under evil.  A
document buffer is one evil leaves in normal state -- rightly, `j\=' and `k\='
being how one moves down a page -- and evil searches its state maps before
any minor mode\='s, so a key bound here would otherwise not be seen.  Marking
the map as overriding applies only while the mode is on, which is to say only
in a dictionary."
  (when diogenes-pdf-search-key
    (keymap-set diogenes-pdf-search-mode-map diogenes-pdf-search-key
                #'diogenes-pdf-lookup-entry)
    (dolist (hook '(pdf-view-mode-hook doc-view-mode-hook reader-mode-hook))
      (add-hook hook #'diogenes-pdf-search--maybe-enable))
    (with-eval-after-load 'evil
      (when (fboundp 'evil-make-overriding-map)
        (evil-make-overriding-map diogenes-pdf-search-mode-map)
        (when (fboundp 'evil-normalize-keymaps)
          (evil-normalize-keymaps))))))

(provide 'diogenes-pdf-search)
;;; diogenes-pdf-search.el ends here
