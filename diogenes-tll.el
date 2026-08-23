;;; diogenes-tll.el --- Open the Thesaurus Linguae Latinae PDFs from lookup -*- lexical-binding: t -*-

;;; Commentary:

;; This module lets you jump from a Diogenes dictionary entry (the
;; buffer produced by `diogenes-lookup-mode') straight to the page of
;; the *Thesaurus Linguae Latinae* (TLL) that contains that entry,
;; displayed inside Emacs with `pdf-tools' (or, as a fallback,
;; `doc-view').  It is the TLL counterpart of `diogenes-old.el' and
;; reuses that module's headword normalization and PDF-display code.
;;
;; Unlike the OLD, the TLL is distributed as *many* PDFs, one per
;; fascicle, as downloaded from the Bayerische Akademie der
;; Wissenschaften.  Two facts about those files make everything work
;; with no pre-built data and no Perl:
;;
;;   1. Each file NAME states the interval of words the fascicle
;;      covers, e.g.
;;        "ThLL vol. 06.1 col. 0001-0808 (f-firmitas).pdf"
;;      The parenthetical "(f-firmitas)" tells us this fascicle runs
;;      from the headword "f" to "firmitas".  We route a headword to the
;;      correct fascicle by finding the file whose interval contains it.
;;
;;   2. Inside each fascicle every headword is a bookmark in the PDF
;;      outline (several per page).  Once the fascicle is chosen we look
;;      the headword up in that outline for its exact page.
;;
;; Setup:
;;
;;   (setq diogenes-tll-pdf-directory "/path/to/TLL/")
;;
;; Then, in a lookup buffer, press `t' or click the "[TLL]" link shown
;; at the top of each Latin entry.

;;; Code:
(require 'cl-lib)
(require 'seq)
(require 'diogenes-old)                 ; sort-key, diacritics, PDF display

(declare-function pdf-info-outline "pdf-info" (&optional file-or-buffer))
(declare-function pdf-info-number-of-pages "pdf-info" (&optional file-or-buffer))

;;;; --------------------------------------------------------------------
;;;; CUSTOMIZATION
;;;; --------------------------------------------------------------------

(defcustom diogenes-tll-pdf-directory nil
  "Directory containing the Thesaurus Linguae Latinae fascicle PDFs.
These are the PDFs as distributed by the Bayerische Akademie der
Wissenschaften.  Their file names must state the word interval each
fascicle covers in parentheses, as in

  ThLL vol. 06.1 col. 0001-0808 (f-firmitas).pdf

Every such file is scanned for its interval, and each fascicle's
PDF outline is consulted for the exact page of a headword."
  :type '(choice (const :tag "Not set" nil) directory)
  :group 'diogenes)

(defcustom diogenes-tll-file-regexp "\\.pdf\\'"
  "Regexp matching the TLL fascicle PDFs in `diogenes-tll-pdf-directory'.
Only files whose name matches are considered.  The default accepts
any PDF; tighten it (e.g. \"\\`ThLL \") if the directory also holds
unrelated PDFs."
  :type 'regexp
  :group 'diogenes)

(defcustom diogenes-tll-interval-regexp
  "(\\([^()-]+\\)-\\(.+\\))\\s-*\\.pdf\\'"
  "Regexp extracting the word interval from a TLL file name.
Group 1 must capture the first (low) headword of the fascicle and
group 2 the last (high) headword.  The default matches the
parenthetical interval at the end of names such as

  ThLL vol. 07.2.2 col. 1347-1952 (librarium-lyxipyretos).pdf

yielding \"librarium\" and \"lyxipyretos\"."
  :type 'regexp
  :group 'diogenes)

(defcustom diogenes-tll-page-offset 0
  "Integer added to every page number derived from a TLL outline.
Normally leave this at 0: outline destinations are physical page
indices and are already correct.  See `diogenes-old-page-offset'."
  :type 'integer
  :group 'diogenes)

;;;; --------------------------------------------------------------------
;;;; CHOOSING THE FASCICLE (word interval per file)
;;;; --------------------------------------------------------------------

;; Cache the directory scan, keyed on the directory's truename and
;; modification time, so adding/removing fascicles invalidates it.
(defvar diogenes-tll--fascicle-cache (make-hash-table :test 'equal)
  "Cache mapping a directory cache-key to its parsed fascicle list.")

(defcustom diogenes-tll-onomasticon-regexp "\\bonom\\."
  "Regexp identifying an Onomasticon fascicle by its file name.
The TLL Onomasticon is a separate alphabetical series covering
proper names; its fascicles restart at A, so their word intervals
overlap those of the main series.  A file whose name matches this
regexp is treated as Onomasticon rather than main-series, and a
headword is routed to whichever series matches its capitalization
\(capitalized -> Onomasticon, lower-case -> main).  The default
matches the \"onom.\" that appears in names such as
\"ThLL vol. onom.3 col. 0001-0280 (d-dzoni).pdf\"."
  :type 'regexp
  :group 'diogenes)

(defun diogenes-tll--word-is-proper-p (word)
  "Non-nil if WORD looks like a proper name (starts with a capital).
Used to decide whether to prefer the Onomasticon series.  Any
leading non-letter characters are skipped before the test."
  (let ((w (replace-regexp-in-string "\\`[^[:alpha:]]+" "" (or word ""))))
    (and (> (length w) 0)
         ;; First letter differs from its own downcase => it is capital.
         (not (eq (aref w 0) (aref (downcase w) 0))))))

(defun diogenes-tll--dir-cache-key (dir)
  "Return a cache key for DIR combining its truename and mtime."
  (let ((true (file-truename dir)))
    (cons true
          (file-attribute-modification-time (file-attributes true)))))

(defun diogenes-tll--parse-file-interval (file)
  "Return (LOW-KEY HIGH-KEY ONOM-P . FILE) for a TLL FILE, or nil.
LOW-KEY and HIGH-KEY are normalized sort keys (see
`diogenes-old--sort-key') for the fascicle's first and last
headwords, taken from the interval in FILE's name via
`diogenes-tll-interval-regexp'.  ONOM-P is non-nil when the file
name marks it as an Onomasticon fascicle
\(`diogenes-tll-onomasticon-regexp')."
  (let ((name (file-name-nondirectory file)))
    (when (let ((case-fold-search t))
            (string-match diogenes-tll-interval-regexp name))
      (let ((low (diogenes-old--sort-key (match-string 1 name)))
            (high (diogenes-old--sort-key (match-string 2 name)))
            (onom (let ((case-fold-search t))
                    (and (string-match diogenes-tll-onomasticon-regexp name) t))))
        (when (and (> (length low) 0) (> (length high) 0))
          (cons low (cons high (cons onom file))))))))

(defun diogenes-tll--scan-fascicles (dir)
  "Scan DIR and return its fascicles sorted by low key.
Each element is (LOW-KEY HIGH-KEY ONOM-P . FILE).  Signals a
user-error if no file names yield a usable interval."
  (let* ((files (let ((case-fold-search t))
                  (directory-files dir t diogenes-tll-file-regexp)))
         (fascicles (delq nil (mapcar #'diogenes-tll--parse-file-interval
                                      files))))
    (when (null fascicles)
      (user-error "No TLL fascicle intervals found in %s.  \
Do the file names contain a \"(word-word)\" interval?  \
See `diogenes-tll-interval-regexp'"
                  dir))
    (sort fascicles (lambda (a b) (string< (car a) (car b))))))

(defun diogenes-tll--fascicles ()
  "Return the parsed, cached fascicle list for `diogenes-tll-pdf-directory'."
  (let ((dir diogenes-tll-pdf-directory))
    (unless dir
      (diogenes--require-path dir 'diogenes-tll-pdf-directory
                              "The Thesaurus Linguae Latinae" 'directory))
    (setq dir (expand-file-name dir))
    (unless (file-directory-p dir)
      (diogenes--require-path dir 'diogenes-tll-pdf-directory
                              "The Thesaurus Linguae Latinae" 'directory))
    (let ((key (diogenes-tll--dir-cache-key dir)))
      (or (gethash key diogenes-tll--fascicle-cache)
          (setf (gethash key diogenes-tll--fascicle-cache)
                (diogenes-tll--scan-fascicles dir))))))

(defun diogenes-tll--brackets-p (fascicle key)
  "Non-nil if FASCICLE's [LOW, HIGH] interval contains sort-KEY."
  (let ((low (car fascicle))
        (high (cadr fascicle)))
    (and (or (string< low key) (string= low key))
         (or (string< key high) (string= key high)))))

(defun diogenes-tll--file-for-word (word)
  "Return the TLL fascicle PDF whose interval contains WORD, or nil.
Routing rules, in order:

1. Determine the desired series from WORD's capitalization: a
   capitalized WORD (a proper name) prefers the Onomasticon, a
   lower-case WORD prefers the main series.
2. Among fascicles whose word interval brackets WORD, prefer those
   of the desired series; fall back to the other series only if the
   preferred series has none.
3. If several fascicles of the chosen series bracket WORD, pick the
   one with the greatest LOW key (the tightest, latest-starting
   interval).
4. If nothing brackets WORD (a gap in coverage), fall back to the
   nearest lower fascicle so a near-miss still opens a sensible
   volume."
  (let* ((fascicles (diogenes-tll--fascicles))
         (key (diogenes-old--sort-key word))
         (want-onom (diogenes-tll--word-is-proper-p word))
         (matching (cl-remove-if-not
                    (lambda (f) (diogenes-tll--brackets-p f key))
                    fascicles))
         (preferred (cl-remove-if-not
                     (lambda (f) (eq (and (caddr f) t) want-onom))
                     matching))
         (chosen-set (or preferred matching)))
    (cond
     ;; Best case: something brackets the word.  Pick the tightest,
     ;; i.e. the greatest LOW key (fascicles are sorted ascending, so
     ;; that is the last one).
     (chosen-set
      (cdddr (car (last chosen-set))))
     ;; Interior gap: the word sorts between two fascicles we own (there
     ;; is coverage both below AND above it).  Fall back to the nearest
     ;; lower fascicle, respecting the desired series when possible.
     ;; If instead the word is past the LAST fascicle we own (no
     ;; fascicle sorts above it), we do NOT have its volume -- return
     ;; nil so the caller can say so rather than open a wrong-letter
     ;; fascicle.
     ((let ((some-above (cl-some (lambda (f) (string< key (car f)))
                                 fascicles)))
        (and some-above
             (let* ((lower (cl-remove-if-not
                            (lambda (f) (or (string< (car f) key)
                                            (string= (car f) key)))
                            fascicles))
                    (lower-pref (cl-remove-if-not
                                 (lambda (f) (eq (and (caddr f) t) want-onom))
                                 lower))
                    (set (or lower-pref lower)))
               (and set (cdddr (car (last set)))))))))))

;;;; --------------------------------------------------------------------
;;;; HEADWORD -> PAGE (within a chosen fascicle)
;;;; --------------------------------------------------------------------

(defun diogenes-tll--page-for-word (word file)
  "Return the page of FILE containing WORD's TLL entry.
FILE's outline has one bookmark per headword.  We reuse the OLD
module's outline index (built once per file and cached) and match
WORD to the last bookmark that sorts at or before it -- i.e. the
headword at or immediately preceding WORD -- which is the page
WORD's entry begins on.  Returns an integer page (with
`diogenes-tll-page-offset' applied) or nil."
  (let* ((index (diogenes-old--index file))   ; ((sort-key . page) ...), sorted
         (key (diogenes-old--sort-key word))
         (best nil))
    (cl-loop for (gkey . page) in index
             while (or (string< gkey key) (string= gkey key))
             do (setq best page))
    ;; Before the first bookmark: fall back to the fascicle's first page.
    (let ((page (or best (cdr (car index)))))
      (when page
        (+ page diogenes-tll-page-offset)))))

;;;; --------------------------------------------------------------------
;;;; INTERACTIVE ENTRY POINTS
;;;; --------------------------------------------------------------------

(defvar diogenes--lookup-headword)      ; from diogenes-perseus.el

;;;###autoload
(defun diogenes-lookup-open-tll (&optional word)
  "Open the Thesaurus Linguae Latinae PDF at the entry for WORD.
Interactively, WORD defaults to the headword of the entry at point
in a `diogenes-lookup-mode' buffer.  With a prefix argument, prompt
for the word.

Requires `diogenes-tll-pdf-directory' to point at a folder of TLL
fascicle PDFs whose names carry \"(word-word)\" intervals, and
`pdf-tools' (recommended) or `doc-view' for display."
  (interactive
   (progn
     (diogenes--lookup-assert-lang "latin" "The Thesaurus Linguae Latinae")
     (list (if current-prefix-arg
               (read-string "Open TLL at word: ")
             (diogenes-old--current-headword)))))
  (let* ((word (or word (diogenes-old--current-headword)))
         (file (diogenes-tll--file-for-word word)))
    (unless file
      (user-error "No TLL fascicle covering \"%s\" is present in %s (missing volume?)"
                  word
                  (abbreviate-file-name
                   (directory-file-name diogenes-tll-pdf-directory))))
    (let ((page (diogenes-tll--page-for-word word file)))
      (unless page
        (user-error "Could not locate \"%s\" in %s"
                    word (file-name-nondirectory file)))
      (diogenes-old--show-page page file)
      (message "TLL: \"%s\" -> %s p.%d"
               word (file-name-nondirectory file) page))))

;;;###autoload
(defun diogenes-tll-clear-cache ()
  "Forget the cached TLL fascicle list.
Call this if you add or remove fascicle PDFs while Emacs is
running.  (Per-file page indices are cached by `diogenes-old' and
cleared with `diogenes-old-clear-cache'.)"
  (interactive)
  (clrhash diogenes-tll--fascicle-cache)
  (message "Diogenes TLL fascicle cache cleared"))


;;;; --------------------------------------------------------------------
;;;; REGISTRATION
;;;; --------------------------------------------------------------------

(declare-function diogenes-lookup-register-dictionary "diogenes-perseus"
                  (id &rest keys))

;;;###autoload
(defun diogenes-tll-available-p ()
  "Non-nil if the TLL can be opened.
True when `diogenes-tll-pdf-directory' is set.  Whether it exists, and
which fascicles are in it, is not asked here: a path that is set is a
dictionary the user means to have, so the link is offered and the key
explains what is wrong with the path."
  (diogenes--path-set-p diogenes-tll-pdf-directory))

(defconst diogenes-tll--declared-at-load (diogenes--declared-at-load-p)
  "Whether the TLL was asked for, rather than bundled with the rest.
Computed when this file is read: a `require' in an init file means the
user wants this dictionary, and it is then offered whatever its paths
say.  See `diogenes--loading-bundle'.")

(defun diogenes-tll--register ()
  "Announce the TLL to the lookup banner.  Idempotent."
  (diogenes-lookup-register-dictionary
   'tll :lang "latin" :name "TLL" :key "t" :order 20
   :command #'diogenes-lookup-open-tll
   :available-p #'diogenes-tll-available-p
   :declared diogenes-tll--declared-at-load
   :paths '(diogenes-tll-pdf-directory)
   :help "Open the TLL at \"%s\""))

(with-eval-after-load 'diogenes-perseus
  (diogenes-tll--register))

(provide 'diogenes-tll)
;;; diogenes-tll.el ends here
