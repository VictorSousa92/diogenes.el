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
Prefers the PDF's active text selection (pdf-tools lets you select
text with the mouse), then the word at point in a plain buffer."
  (or (and (derived-mode-p 'pdf-view-mode)
           (fboundp 'pdf-view-active-region-p)
           (pdf-view-active-region-p)
           (fboundp 'pdf-view-active-region-text)
           (let ((txt (car (pdf-view-active-region-text))))
             (and txt (string-trim txt))))
      (thing-at-point 'word t)))

;;;; --------------------------------------------------------------------
;;;; THE COMMAND
;;;; --------------------------------------------------------------------

;;;###autoload
(defun diogenes-pdf-lookup-entry (word)
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

The buffer's dictionary is detected from the visited file, and the
page is computed with that dictionary's own lookup logic, so it lands
where the matching \"[OLD]\"/\"[BDAG]\"/... link would.  For the
multi-file TLL and TGL, an entry in another fascicle or volume opens
that sibling PDF."
  (interactive
   (let* ((file (or buffer-file-name
                    (user-error "This buffer is not visiting a PDF file")))
          (dict (or (diogenes-pdf-search--identify file)
                    (user-error
                     "This PDF is not a configured Diogenes dictionary.  \
Set the matching path variable (e.g. `diogenes-old-pdf-file') to this file")))
          (prompt (format "Look up in %s: " (diogenes-pdf-search--name dict))))
     (list (read-from-minibuffer prompt (diogenes-pdf-search--default-word)))))
  (let* ((file (or buffer-file-name
                   (user-error "This buffer is not visiting a PDF file")))
         (dict (or (diogenes-pdf-search--identify file)
                   (user-error "This PDF is not a configured Diogenes dictionary")))
         (word (string-trim (or word ""))))
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
              (diogenes--display-buffer (find-file-noselect other)
                                        :kind 'dictionary)
              (diogenes-pdf-search--goto-page page)))
          (message "%s: \"%s\" -> %s p.%d"
                   (diogenes-pdf-search--name dict)
                   word (file-name-nondirectory other) page)))))))

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

;;;###autoload
(defun diogenes-pdf-search-setup-keys ()
  "Bind `diogenes-pdf-lookup-entry' in the supported PDF viewers.
Binds `diogenes-pdf-search-key' (default \"L\") in `pdf-view-mode',
`doc-view-mode', and the Emacs Reader's `reader-mode'.  Safe to call at
startup: the bindings are installed via `with-eval-after-load', so they
attach whenever the viewers load, in either order.  Does nothing if
`diogenes-pdf-search-key' is nil.

In the Emacs Reader the command still works -- you type the headword at
the prompt and the reader jumps to its page -- but, unlike pdf-tools,
the Reader exposes no text layer, so the word under point cannot be
offered as the prompt's default; the prompt simply starts empty."
  (when diogenes-pdf-search-key
    (with-eval-after-load 'pdf-view
      (when (boundp 'pdf-view-mode-map)
        (keymap-set pdf-view-mode-map diogenes-pdf-search-key
                    #'diogenes-pdf-lookup-entry)))
    (with-eval-after-load 'doc-view
      (when (boundp 'doc-view-mode-map)
        (keymap-set doc-view-mode-map diogenes-pdf-search-key
                    #'diogenes-pdf-lookup-entry)))
    (with-eval-after-load 'reader
      (when (boundp 'reader-mode-map)
        (keymap-set reader-mode-map diogenes-pdf-search-key
                    #'diogenes-pdf-lookup-entry)))))

(provide 'diogenes-pdf-search)
;;; diogenes-pdf-search.el ends here
