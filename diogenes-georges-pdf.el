;;; diogenes-georges-pdf.el --- the printed Georges, from a Georges entry -*- lexical-binding: t -*-

;;; Commentary:

;; The scans of Georges' _Handwörterbuch_ (8th ed., 1913-1918), opened at the
;; page holding a word, with `pdf-tools' or `doc-view'.
;;
;; This was once the whole of `diogenes-georges.el'.  Now that the
;; Handwörterbuch is searchable as XML, the printed page is where Bailly's
;; is: reached by pressing `G' a second time from inside a Georges entry, and
;; from nowhere else.  `diogenes-lookup-georges' does that dispatching; this
;; module registers the "[PDF (G)]" link that says so, and binds no key of
;; its own.
;;
;; ---------------------------------------------------------------------
;; BOOKMARKS THAT LIST A PAGE'S WHOLE CONTENTS
;; ---------------------------------------------------------------------
;;
;; These scans are bookmarked once per page, and the bookmark names not the
;; page's first entry but EVERY entry on it:
;;
;;   Bd1_Sp0005-0006_a-3_abacinus_abactio_abactor_abactus-1_abactus-2_...
;;
;; -- volume, the printed column range (Spalten 5-6), then the headwords,
;; underscore-separated, with a numeral suffix on homographs (abactus-1) and
;; a hyphen where a headword is more than one word (Acca-Larentia,
;; Iccius-portus).  A page with more entries than the title can hold ends in
;; "ua13": und andere, thirteen further entries not named.
;;
;; That gives some 43 000 (headword, page) pairs, which is far more than a
;; running head would: a word that IS named is placed on its exact page.  A
;; word that is not -- one of the "ua" remainder, a spelling Georges files
;; differently, or a word he does not have at all -- is placed on the page of
;; the last named entry before it alphabetically, which is the page it would
;; be on if it were there, and in practice the page it IS on when the title
;; was truncated.  The echo area says which of the two happened.
;;
;; The OCR of these titles is good but not perfect -- occupatio appears as
;; "oceupaetio", quirrito as "guirrito" -- and a garbled headword sits in the
;; wrong alphabetical place, which would misdirect a binary search.  So only
;; the longest non-decreasing run of the headwords is kept, by the same
;; `diogenes-cambridge--monotone-backbone' the Cambridge Greek Lexicon module
;; uses on its OCR'd guide words.  It discards 43 headwords of 43 425 and
;; leaves an index that ascends without exception.
;;
;; Note that this module keys a headword its own way, on the bookmark titles
;; as the OCR left them: ASCII letters and word SPACES, a hyphen counting as
;; a space so that "Acca Larentia" precedes "accado" as the print requires.
;; The XML module cannot do that -- the search it uses discards spaces -- and
;; the two indexes are searched separately, so they need not agree.
;;
;; Setup:
;;
;;   (setq diogenes-georges-directory "/path/to/georges/")
;;
;; a folder holding both volumes' PDFs; they are taken in filename order, so
;; the usual Georges-1913_Bd1.pdf and _Bd2.pdf need no further arrangement.

;;; Code:
(require 'cl-lib)
(require 'seq)
(require 'subr-x)
(require 'diogenes-old)                 ; PDF display driver
(require 'diogenes-cambridge)           ; monotone backbone over OCR'd headwords

(declare-function pdf-info-outline "pdf-info" (&optional file-or-buffer))
(declare-function diogenes-lookup-register-dictionary "diogenes-perseus"
                  (id &rest keys))
(declare-function diogenes--lookup-assert-lang "diogenes-perseus"
                  (expected dict-name))
(declare-function diogenes--lookup-headword-at-point "diogenes-perseus"
                  (&optional pos))
(declare-function diogenes--require-path "diogenes-lisp-utils"
                  (value name dictionary &optional kind))
(declare-function diogenes-georges-lookup-buffer-p "diogenes-georges" ())

(defvar diogenes--lookup-headword)

;;;; --------------------------------------------------------------------
;;;; CUSTOMIZATION
;;;; --------------------------------------------------------------------

(defcustom diogenes-georges-directory nil
  "Directory holding the PDFs of Georges' Handwörterbuch.
Both volumes live here as separate files; they are read in filename order,
which puts Bd. 1 (A-H) before Bd. 2 (I-Z).  Which letters each volume
covers is then read from its own bookmarks, so nothing else needs saying."
  :type '(choice (const :tag "Not set" nil) directory)
  :group 'diogenes)

(defcustom diogenes-georges-pdf-regexp "\\.pdf\\'"
  "Regexp matching the volume PDFs inside `diogenes-georges-directory'."
  :type 'regexp
  :group 'diogenes)

(defcustom diogenes-georges-page-offset 0
  "Integer added to every page number derived from a Georges outline.
Leave at 0: outline destinations are physical page indices already."
  :type 'integer
  :group 'diogenes)

(defcustom diogenes-georges-title-regexp
  "\\`[^_]*_Sp[0-9]+\\(?:-[0-9]+\\)?_"
  "Regexp matching the part of a bookmark title before the headwords.
The titles of these scans read \"Bd1_Sp0005-0006_a-3_abacinus_…\": a volume
name, the printed column range, then the page's entries.  Everything this
matches is stripped, and what remains is split on underscores."
  :type 'regexp
  :group 'diogenes)

(defcustom diogenes-georges-others-regexp "\\`ua[0-9]+\\'"
  "Regexp matching the token that stands for entries a title had no room for.
\"ua13\" -- und andere -- ends a bookmark whose page holds thirteen more
entries than it names.  Such a token is no headword and is skipped; the
words it stands for are reached by falling back to the preceding entry."
  :type 'regexp
  :group 'diogenes)

;;;; --------------------------------------------------------------------
;;;; THE KEY A HEADWORD SORTS UNDER
;;;; --------------------------------------------------------------------

(defun diogenes-georges-pdf--key (headword)
  "Return the collation key HEADWORD is filed under.
ASCII letters and word spaces only, case-folded.  A hyphen in a bookmark
headword marks a word boundary (Acca-Larentia, Iccius-portus) and becomes
a space, which sorts before every letter as the printed order wants; a
trailing numeral marks a homograph (abactus-2) and is dropped."
  (save-match-data
    (let* ((word (replace-regexp-in-string "-[0-9]+\\'" "" (or headword "")))
           (word (replace-regexp-in-string "-" " " word))
           (letters nil))
      (dolist (c (string-to-list word))
        (cond ((or (<= ?a c ?z) (<= ?A c ?Z)) (push (downcase c) letters))
              ((memq c '(?\s ?\t)) (push ?\s letters))))
      (string-trim
       (replace-regexp-in-string "  +" " " (apply #'string (nreverse letters)))))))

;;;; --------------------------------------------------------------------
;;;; READING A VOLUME
;;;; --------------------------------------------------------------------

(defvar diogenes-georges-pdf--cache (make-hash-table :test 'equal)
  "Cache mapping a directory signature to the parsed volume list.")

(defun diogenes-georges-pdf--volume-files ()
  "Return the volume PDFs, in filename order.
Signals a user-error when `diogenes-georges-directory' is unset, absent,
or holds no PDF."
  (let ((dir diogenes-georges-directory))
    (diogenes--require-path dir 'diogenes-georges-directory "Georges" 'directory)
    (setq dir (file-name-as-directory (expand-file-name dir)))
    (let ((files (sort (directory-files dir t diogenes-georges-pdf-regexp)
                       #'string<)))
      (unless files
        (user-error "No PDF matching %s in %s"
                    diogenes-georges-pdf-regexp dir))
      files)))

(defun diogenes-georges-pdf--parse-title (title)
  "Return the headwords a bookmark TITLE names, in order.
Strips `diogenes-georges-title-regexp' and drops the
`diogenes-georges-others-regexp' token; see those for the shape of a
title."
  (save-match-data
    (let ((rest (if (string-match diogenes-georges-title-regexp title)
                    (substring title (match-end 0))
                  title)))
      (seq-remove (lambda (token)
                    (or (string-empty-p token)
                        (string-match-p diogenes-georges-others-regexp token)))
                  (split-string rest "_")))))

(defun diogenes-georges-pdf--build-volume (file)
  "Read FILE's outline and return a plist describing that volume.
  :file   the PDF;
  :keys   a vector of headword keys, ascending;
  :pages  the matching vector of page numbers;
  :heads  the matching vector of headwords as the bookmark spells them.
Only the monotone backbone of the headwords is kept, so an OCR slip in one
title cannot misdirect the search.  Nil when the PDF has no usable
bookmarks."
  (unless (require 'pdf-info nil t)
    (user-error "pdf-tools is not installed; cannot read the Georges outline.  \
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
                   when (and (integerp page) (> page 0))
                   append (cl-loop for head in (diogenes-georges-pdf--parse-title title)
                                   for key = (diogenes-georges-pdf--key head)
                                   unless (string-empty-p key)
                                   ;; car: what we want back; cdr: the key the
                                   ;; backbone sorts on (see that function).
                                   collect (cons (cons page head) key)))))
    (when rows
      (let ((backbone (diogenes-cambridge--monotone-backbone rows)))
        (list :file file
              :keys (vconcat (mapcar #'cdr backbone))
              :pages (vconcat (mapcar (lambda (r) (car (car r))) backbone))
              :heads (vconcat (mapcar (lambda (r) (cdr (car r))) backbone)))))))

(defun diogenes-georges-pdf--dir-signature (dir files)
  "Return a cache signature for DIR built from FILES and their mtimes."
  (cons (file-truename dir)
        (mapcar (lambda (f)
                  (cons f (file-attribute-modification-time (file-attributes f))))
                files)))

(defun diogenes-georges-pdf--volumes ()
  "Return the parsed volume list, cached for the session."
  (let* ((files (diogenes-georges-pdf--volume-files))
         (key (diogenes-georges-pdf--dir-signature diogenes-georges-directory files)))
    (or (gethash key diogenes-georges-pdf--cache)
        (setf (gethash key diogenes-georges-pdf--cache)
              (let ((volumes (delq nil (mapcar #'diogenes-georges-pdf--build-volume
                                               files))))
                (unless volumes
                  (user-error "No usable bookmarks in the Georges PDFs under %s"
                              diogenes-georges-directory))
                volumes)))))

;;;; --------------------------------------------------------------------
;;;; HEADWORD -> VOLUME AND PAGE
;;;; --------------------------------------------------------------------

(defun diogenes-georges-pdf--volume-for-key (key volumes)
  "Return the volume of VOLUMES that should hold KEY.
The last volume whose first headword sorts at or before KEY -- so a word
past the end of Bd. 1 goes to Bd. 2 -- and the first volume for a word
before every volume's start."
  (or (cl-loop for volume in (reverse volumes)
               for first = (aref (plist-get volume :keys) 0)
               when (not (string< key first)) return volume)
      (car volumes)))

(defun diogenes-georges-pdf--locate (word)
  "Return (FILE PAGE HEADWORD EXACT) for WORD in Georges, or nil.
PAGE is the page naming WORD when Georges' bookmarks name it, and
otherwise the page of the last headword before it -- where the word would
stand if it were an entry, which is also where the entries a truncated
bookmark did not name are to be found.  EXACT distinguishes the two."
  (let ((key (diogenes-georges-pdf--key word)))
    (unless (string-empty-p key)
      (let* ((volume (diogenes-georges-pdf--volume-for-key key (diogenes-georges-pdf--volumes)))
             (keys (plist-get volume :keys))
             (n (length keys)))
        (when (> n 0)
          ;; rightmost i with keys[i] <= key
          (let ((lo 0) (hi n) (found -1))
            (while (< lo hi)
              (let ((mid (/ (+ lo hi) 2)))
                (if (string< key (aref keys mid))
                    (setq hi mid)
                  (setq found mid
                        lo (1+ mid)))))
            (let ((i (max found 0)))
              (list (plist-get volume :file)
                    (+ (aref (plist-get volume :pages) i)
                       diogenes-georges-page-offset)
                    (aref (plist-get volume :heads) i)
                    (string= (aref keys i) key)))))))))

(defun diogenes-georges-pdf--page-for-word (word &optional _file)
  "Return the page of WORD in Georges, for `diogenes-pdf-search'.
The volume is chosen by the word, so a word in the other volume returns
that volume's page; the caller opens the file `diogenes-georges-pdf--locate'
names."
  (nth 1 (diogenes-georges-pdf--locate word)))

;;;; --------------------------------------------------------------------
;;;; INTERACTIVE ENTRY POINTS
;;;; --------------------------------------------------------------------

(defun diogenes-georges-pdf--current-headword ()
  "Return the headword of the Latin entry point is in."
  (or (and (fboundp 'diogenes--lookup-headword-at-point)
           (diogenes--lookup-headword-at-point))
      (get-text-property (point) 'orth)
      (and (boundp 'diogenes--lookup-headword) diogenes--lookup-headword)
      (thing-at-point 'word t)
      (user-error "No headword found at point")))

;;;###autoload
(defun diogenes-lookup-open-georges-pdf (&optional word)
  "Open Georges' Handwörterbuch at the page for WORD.
Interactively, WORD defaults to the headword of the Latin entry at point;
with a prefix argument, prompt for it.  The volume is chosen by the word.

When Georges' page bookmarks name WORD, that is the page.  When they do
not -- the word is one a crowded bookmark could not list, a spelling filed
differently, or absent from the dictionary -- the page is where the word
would stand alphabetically, and the echo area says so along with the last
headword before it.

Requires `diogenes-georges-directory', and `pdf-tools' (recommended) or
`doc-view' for display."
  (interactive
   (progn
     (diogenes--lookup-assert-lang "latin" "Georges")
     (list (if current-prefix-arg
               (read-string "Open Georges at word: ")
             (diogenes-georges-pdf--current-headword)))))
  (let* ((word (string-trim (or word (diogenes-georges-pdf--current-headword))))
         (hit (diogenes-georges-pdf--locate word)))
    (unless hit
      (user-error "Could not locate \"%s\" in Georges" word))
    (seq-let (file page head exact) hit
      (diogenes-old--show-page page file)
      (if exact
          (message "Georges: \"%s\" -> %s page %d"
                   word (file-name-nondirectory file) page)
        (message "Georges: \"%s\" is not among the entries listed; showing \
%s page %d, after \"%s\""
                 word (file-name-nondirectory file) page head)))))

;;;###autoload
(defun diogenes-georges-pdf-clear-cache ()
  "Forget the parsed Georges page index.
Call this if you replace or re-bookmark a volume while Emacs is running."
  (interactive)
  (clrhash diogenes-georges-pdf--cache)
  (message "Diogenes Georges index cache cleared"))


;;;; --------------------------------------------------------------------
;;;; REGISTRATION
;;;; --------------------------------------------------------------------

(defun diogenes-georges-pdf-available-p ()
  "Non-nil when the printed Georges can be opened.
`diogenes-georges-directory' set to a directory that exists: enough for the
banner to decide whether to offer the link, without reading an outline."
  (diogenes--path-set-p diogenes-georges-directory))

(defconst diogenes-georges-pdf--declared-at-load (diogenes--declared-at-load-p)
  "Whether the printed Georges was asked for, rather than bundled with the rest.
Computed when this file is read: a `require' in an init file means the
user wants this dictionary, and it is then offered whatever its paths
say.  See `diogenes--loading-bundle'.")

(defun diogenes-georges-pdf--register ()
  "Announce the printed Georges to the lookup banner.  Idempotent.
`:show when-current :of georges' offers it ONLY inside a Georges entry,
which is where pressing `G' means the printed page rather than another
lookup.  The key is shared with `diogenes-lookup-georges', which does that
dispatching, so nothing is bound here."
  (diogenes-lookup-register-dictionary
   'georges-pdf :lang "latin" :name "PDF" :key "G" :order 90
   :command #'diogenes-lookup-open-georges-pdf
   :show 'when-current :of 'georges
   :available-p #'diogenes-georges-pdf-available-p
   :declared diogenes-georges-pdf--declared-at-load
   :paths '(diogenes-georges-directory)
   :help "Open the printed Georges at \"%s\""))

(with-eval-after-load 'diogenes-perseus
  (diogenes-georges-pdf--register))

(provide 'diogenes-georges-pdf)
;;; diogenes-georges-pdf.el ends here
