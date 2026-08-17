;;; diogenes-gaffiot.el --- Look up a Latin word in Gaffiot -*- lexical-binding: t -*-

;;; Commentary:

;; Show the entry of Félix Gaffiot's _Dictionnaire illustré latin-français_
;; for the Latin word you are reading -- in a Diogenes lookup buffer, not a
;; PDF.  From a Latin entry (Lewis & Short), press `g' or click the
;; "[Gaffiot]" link.
;;
;; ---------------------------------------------------------------------
;; WHY THIS IS NOT LIKE THE PRINT-DICTIONARY MODULES
;; ---------------------------------------------------------------------
;;
;; `diogenes-old.el' and its siblings jump a scanned PDF to a page.  Gaffiot
;; comes as TEI XML instead, entry by entry, exactly the kind of thing
;; `diogenes-lookup-mode' already displays for the LSJ and Lewis & Short.  So
;; this module adds no display machinery of its own: it hands Gaffiot to
;; `diogenes--search-dict' as one more dictionary file, and everything the
;; lookup buffer can do comes with it --
;;
;;   * `C-c C-n' / `C-c C-p' walk to the next and previous entry;
;;   * `C-c C-c' on a word looks it up: a Latin word goes to Lewis & Short,
;;     so you can step from Gaffiot back into the electronic Latin
;;     dictionary, and Greek inside an entry (Gaffiot quotes plenty) goes to
;;     the LSJ;
;;   * the print dictionaries are one keystroke away, since the entry carries
;;     the usual "[OLD] [TLL]" banner;
;;   * every entry opens in a fresh buffer, so the Lewis & Short entry you
;;     came from stays live and reachable.
;;
;; ---------------------------------------------------------------------
;; THE DICTIONARY FILE
;; ---------------------------------------------------------------------
;;
;; Diogenes looks a word up by binary search over a file of ONE ENTRY PER
;; LINE, sorted by an ASCII `key' attribute (see `diogenes--binary-search'
;; and `diogenes--ascii-sort-function').  The Gaffiot TEI is a single
;; document with entries spread over many lines and headwords full of
;; macrons, so it has to be converted once:
;;
;;   (setq diogenes-gaffiot-source-file "/path/to/gaffiot-unicode.xml")
;;   M-x diogenes-gaffiot-build-dictionary
;;
;; which writes `gaffiot.xml' beside the other Diogenes dictionaries.  Each
;; entry becomes one line, its first <orth> becomes the <head> the formatter
;; recognises as a headword, and its key is that headword reduced to ASCII
;; letters -- macrons and breves stripped, æ and œ expanded, the homograph
;; numeral of \"1 ăbactus\" dropped -- so that the keys Lewis & Short sends
;; us match.  Offered automatically the first time you press `g' with no
;; dictionary file present.
;;
;; ---------------------------------------------------------------------
;; COVERAGE
;; ---------------------------------------------------------------------
;;
;; Mind which Gaffiot you have.  The proofread Unicode TEI in circulation
;; covers the letters A to F only (some 28 000 entries); a word past that is
;; not missing from Gaffiot, merely from the file.  Rather than show you the
;; last entry of F and call it a near miss, this module reads the range its
;; file actually spans and says so.

;;; Code:
(require 'cl-lib)
(require 'seq)
(require 'subr-x)
(require 'ucs-normalize)

(declare-function diogenes--search-dict "diogenes-perseus"
                  (word lang sort-fn key-fn &optional file))
(declare-function diogenes--ascii-sort-function "diogenes-perseus" (a b))
(declare-function diogenes--xml-key-fn "diogenes-perseus" (buf))
(declare-function diogenes--get-dict-line "diogenes-perseus"
                  (file pos &optional file-length))
(declare-function diogenes--lookup-headword-at-point "diogenes-perseus"
                  (&optional pos))
(declare-function diogenes--lookup-assert-lang "diogenes-perseus"
                  (expected dict-name))
(declare-function diogenes--perseus-path "diogenes" ())

(defvar diogenes--lookup-headword)
(defvar diogenes--lookup-file)
(defvar diogenes--lookup-same-window)
(defvar diogenes--dict-xml-handlers-extra)

;;;; --------------------------------------------------------------------
;;;; CUSTOMIZATION
;;;; --------------------------------------------------------------------

(defcustom diogenes-gaffiot-file nil
  "Path to the converted Gaffiot dictionary, one entry per line.
Nil means `gaffiot.xml' among the other Diogenes dictionaries, which is
where \\[diogenes-gaffiot-build-dictionary] writes it.  This is NOT the
TEI file you downloaded -- see `diogenes-gaffiot-source-file'."
  :type '(choice (const :tag "gaffiot.xml beside the other dictionaries" nil)
                 file)
  :group 'diogenes)

(defcustom diogenes-gaffiot-source-file nil
  "Path to the Gaffiot TEI XML, as distributed (e.g. `gaffiot-unicode.xml').
Read by \\[diogenes-gaffiot-build-dictionary] to produce
`diogenes-gaffiot-file'; not used for lookups afterwards, so it may live
anywhere and be deleted once converted."
  :type '(choice (const :tag "Not set" nil) file)
  :group 'diogenes)

(defcustom diogenes-gaffiot-display-in-same-window t
  "If non-nil, show a Gaffiot entry in the window it was invoked from.
The Lewis & Short entry you came from is not destroyed either way -- each
lookup gets a fresh buffer -- so with the default you stay in one window
and can return through the buffer history.  Nil lets `display-buffer'
place it as it sees fit."
  :type 'boolean
  :group 'diogenes)

;;;; --------------------------------------------------------------------
;;;; FORMATTING OF GAFFIOT'S OWN ELEMENTS
;;;; --------------------------------------------------------------------

(defconst diogenes-gaffiot--xml-handlers
  '((latin . (font-lock-face italic))          ; the Latin being illustrated
    (auth  . (font-lock-face font-lock-keyword-face))
    (refno . (font-lock-face shadow)))
  "Faces for the elements Gaffiot uses and the Perseus dictionaries do not.
Added to `diogenes--dict-xml-handlers-extra' on load, without disturbing an
entry already there, so the LSJ and Lewis & Short keep their appearance.
Gaffiot's <head>, <sense>, <foreign> and <title> need nothing: the shared
handlers in `diogenes--dict-handle-elt' already cover them.")

(defun diogenes-gaffiot--install-xml-handlers ()
  "Teach the dictionary formatter about Gaffiot's elements.  Idempotent."
  (dolist (handler diogenes-gaffiot--xml-handlers)
    (unless (assq (car handler) diogenes--dict-xml-handlers-extra)
      (push handler diogenes--dict-xml-handlers-extra))))

;;;; --------------------------------------------------------------------
;;;; THE KEY A HEADWORD SORTS UNDER
;;;; --------------------------------------------------------------------

(defconst diogenes-gaffiot--ligatures
  '((?æ . "ae") (?Æ . "Ae") (?œ . "oe") (?Œ . "Oe"))
  "Ligatures spelt out, since a key holds plain ASCII letters only.")

(defun diogenes-gaffiot--key (headword)
  "Return the ASCII key HEADWORD is filed under.
`diogenes--ascii-sort-function' compares keys after discarding everything
but ASCII letters, so a key must survive that: macrons and breves are
stripped by NFD decomposition, ligatures spelt out, and case folded.  A
leading homograph numeral (\"1 ăbactus\") is not part of the word, and
where an entry gives several spellings (\"ā, ăb, abs\") the first is the
one to file it under.

Wrapped in `save-match-data\': this does its own matching, and a caller
that has just located something with `string-match\' would otherwise find
its `match-beginning\' quietly redirected here."
  (save-match-data
   (let* ((word (replace-regexp-in-string "\\`[[:space:]]*[0-9]+[[:space:]]*" ""
                                         (or headword "")))
         (word (car (split-string word "," t "[[:space:]]+")))
         ;; Decompose FIRST: a ligature may itself carry an accent (ǽ), and
         ;; only after NFD is the bare æ there to be spelt out.
         (decomposed (ucs-normalize-NFD-string (or word "")))
         (letters nil))
    (dolist (c (string-to-list decomposed))
      (let ((spelt (cdr (assq c diogenes-gaffiot--ligatures))))
        (cond (spelt (dolist (l (string-to-list spelt)) (push (downcase l) letters)))
              ((or (<= ?a c ?z) (<= ?A c ?Z)) (push (downcase c) letters)))))
     (apply #'string (nreverse letters)))))

;;;; --------------------------------------------------------------------
;;;; BUILDING THE DICTIONARY FILE
;;;; --------------------------------------------------------------------

(defun diogenes-gaffiot--dictionary-file ()
  "Return the path of the converted dictionary, whether or not it exists."
  (or diogenes-gaffiot-file
      (file-name-concat (diogenes--perseus-path) "gaffiot.xml")))

;;;###autoload
(defun diogenes-gaffiot-build-dictionary (&optional source target)
  "Convert the Gaffiot TEI XML into a dictionary Diogenes can search.
SOURCE defaults to `diogenes-gaffiot-source-file', TARGET to
`diogenes-gaffiot-file'.  Each <entryFree> becomes one line: its first
<orth> is renamed <head> (the element the formatter treats as a headword),
the whole entry is flattened, and it is given the ASCII `key' attribute
that `diogenes--binary-search' sorts on -- see `diogenes-gaffiot--key'.
Entries keep their printed order within a key, so \"1 a\", \"2 ā\" and
\"3 ā, ăb, abs\" stay in sequence.

Run once, after setting `diogenes-gaffiot-source-file'.  Takes a few
seconds for the 11 MB file."
  (interactive)
  (let ((source (or source diogenes-gaffiot-source-file
                    (read-file-name "Gaffiot TEI XML: " nil nil t)))
        (target (or target (diogenes-gaffiot--dictionary-file)))
        (rows nil)
        (skipped 0))
    (unless (file-readable-p source)
      (user-error "Cannot read the Gaffiot source at %s" source))
    (when (and (file-exists-p target)
               (string= (file-truename source) (file-truename target)))
      (user-error "Refusing to convert %s onto itself: \
`diogenes-gaffiot-file' must differ from `diogenes-gaffiot-source-file'"
                  (abbreviate-file-name source)))
    (message "Converting %s ..." (file-name-nondirectory source))
    (with-temp-buffer
      (insert-file-contents source)
      (goto-char (point-min))
      (while (re-search-forward "<entryFree>" nil t)
        (let ((start (point))
              (end (save-excursion
                     (when (search-forward "</entryFree>" nil t)
                       (match-beginning 0)))))
          (if (null end)
              (cl-incf skipped)
            (let ((body (buffer-substring-no-properties start end)))
              (goto-char end)
              (if (not (string-match "<orth>\\(\\(?:.\\|\n\\)*?\\)</orth>" body))
                  (cl-incf skipped)
                ;; Read the whole match out FIRST.  Anything that matches in
                ;; between -- `diogenes-gaffiot--key\' used to -- would move
                ;; these offsets, and the <head> would be spliced into the
                ;; middle of the <orth> tag.
                (let* ((orth-start (match-beginning 0))
                       (orth-end (match-end 0))
                       (orth (match-string 1 body))
                       (plain (replace-regexp-in-string "<[^>]*>" "" orth))
                       (key (diogenes-gaffiot--key plain))
                       (line (concat (substring body 0 orth-start)
                                     "<head>" orth "</head>"
                                     (substring body orth-end))))
                  (if (string-empty-p key)
                      (cl-incf skipped)
                    (setq line (replace-regexp-in-string
                                "[[:space:]]*\n[[:space:]]*" " " line))
                    (push (cons key (format "<entryFree key=\"%s\">%s</entryFree>"
                                            key (string-trim line)))
                          rows)))))))))
    (setq rows (nreverse rows))
    ;; `sort' on a list is stable, so entries sharing a key keep the order
    ;; the dictionary prints them in.
    (setq rows (sort rows (lambda (a b) (string< (car a) (car b)))))
    (unless rows
      (user-error "Found no entries in %s: is it the Gaffiot TEI file?" source))
    (make-directory (file-name-directory target) t)
    (let ((coding-system-for-write 'utf-8))
      (with-temp-file target
        (dolist (row rows)
          (insert (cdr row) "\n"))))
    (message "Gaffiot: wrote %d entries (%s-%s) to %s%s"
             (length rows) (car (car rows)) (car (car (last rows)))
             (abbreviate-file-name target)
             (if (zerop skipped) "" (format "; skipped %d" skipped)))
    target))

;;;; --------------------------------------------------------------------
;;;; WHAT THE FILE COVERS
;;;; --------------------------------------------------------------------

(defvar diogenes-gaffiot--coverage-cache (make-hash-table :test 'equal)
  "Cache mapping a dictionary file to the (FIRST-KEY . LAST-KEY) it spans.")

(defun diogenes-gaffiot--coverage (file)
  "Return (FIRST-KEY . LAST-KEY) for the dictionary FILE, or nil.
Read from the first and last line, so it costs two seeks, once per
session.  The Gaffiot TEI in circulation stops at F, and a lookup beyond
it would otherwise land on the last entry of F as if it were a near
miss."
  (let ((cache-key (cons (file-truename file)
                         (file-attribute-modification-time
                          (file-attributes file)))))
    (or (gethash cache-key diogenes-gaffiot--coverage-cache)
        (let* ((size (file-attribute-size (file-attributes file)))
               (first (car (diogenes--get-dict-line file 0 size)))
               (last (car (diogenes--get-dict-line file (max 0 (1- size)) size)))
               (range
                (and first last
                     (cons (car (ignore-errors (diogenes--xml-key-fn first)))
                           (car (ignore-errors (diogenes--xml-key-fn last)))))))
          (when (and (car range) (cdr range))
            (puthash cache-key range diogenes-gaffiot--coverage-cache))))))

;;;; --------------------------------------------------------------------
;;;; THE LOOKUP
;;;; --------------------------------------------------------------------

(defun diogenes-gaffiot--file ()
  "Return the dictionary file, building it if the user agrees.
Signals a user-error when there is nothing to search and nothing to build
it from."
  (let ((file (diogenes-gaffiot--dictionary-file)))
    (cond
     ((file-readable-p file)
      (diogenes-gaffiot--assert-converted file)
      file)
     ((and diogenes-gaffiot-source-file
           (file-readable-p diogenes-gaffiot-source-file)
           (y-or-n-p (format "Gaffiot is not converted yet; build %s now? "
                             (abbreviate-file-name file))))
      (diogenes-gaffiot-build-dictionary diogenes-gaffiot-source-file file))
     (t
      (user-error "No Gaffiot dictionary at %s.  Set \
`diogenes-gaffiot-source-file' to the TEI XML and run \
M-x diogenes-gaffiot-build-dictionary"
                  (abbreviate-file-name file))))))

(defun diogenes-gaffiot--assert-converted (file)
  "Signal a user-error unless FILE is a converted Gaffiot dictionary.
The lookup wants one entry per line, each with a `key\' attribute; handed
the TEI file instead it would fail deep inside
`diogenes--xml-key-fn\' with an unhelpful message.  `diogenes-gaffiot-file\'
is the CONVERTED file; the TEI belongs in
`diogenes-gaffiot-source-file\'."
  (with-temp-buffer
    (insert-file-contents file nil 0 400)
    (goto-char (point-min))
    (unless (looking-at "<entry[^>]*[[:space:]]key=\"")
      (user-error "%s is not a converted Gaffiot dictionary (no key= on its \
first entry).  If this is the TEI file, set it as \
`diogenes-gaffiot-source-file\' instead and run \
M-x diogenes-gaffiot-build-dictionary"
                  (abbreviate-file-name file)))))

(defun diogenes-gaffiot-lookup-buffer-p ()
  "Non-nil if the current lookup buffer is showing Gaffiot.
Read from the buffer-local `diogenes--lookup-file\', which records the
dictionary the entries were read from.  Used by
`diogenes--lookup-insert-dict-links\' to offer \"[Lewis & Short]\" here and
\"[Gaffiot]\" in a Lewis & Short entry, so the link always leads to the
other Latin dictionary rather than the one you are reading."
  (and (boundp 'diogenes--lookup-file)
       diogenes--lookup-file
       (let ((gaffiot (diogenes-gaffiot--dictionary-file)))
         (and (file-exists-p gaffiot)
              (file-exists-p diogenes--lookup-file)
              (string= (file-truename diogenes--lookup-file)
                       (file-truename gaffiot))))))

(defun diogenes-gaffiot--current-headword ()
  "Return the headword to look up: the one of the entry point is in.
Resolved on every call, so the command acts on the entry the cursor is
currently in, including entries appended by `diogenes-lookup-next'."
  (or (and (fboundp 'diogenes--lookup-headword-at-point)
           (diogenes--lookup-headword-at-point))
      (get-text-property (point) 'orth)
      (and (boundp 'diogenes--lookup-headword) diogenes--lookup-headword)
      (thing-at-point 'word t)
      (user-error "No headword found at point")))

;;;###autoload
(defun diogenes-lookup-gaffiot (&optional word)
  "Show Gaffiot's entry for WORD in a Diogenes lookup buffer.
Interactively, WORD defaults to the headword of the Latin entry at point;
with a prefix argument, prompt for it.  The entry behaves like any other
lookup: `C-c C-n' and `C-c C-p' walk the dictionary, `C-c C-c' on a Latin
word returns to Lewis & Short and on a Greek one goes to the LSJ, and the
\"[OLD] [TLL]\" banner opens the print dictionaries.

Requires a converted dictionary file; see
\\[diogenes-gaffiot-build-dictionary]."
  (interactive
   (progn
     (diogenes--lookup-assert-lang "latin" "Gaffiot")
     (list (if current-prefix-arg
               (read-string "Look up in Gaffiot: ")
             (diogenes-gaffiot--current-headword)))))
  (let* ((word (string-trim (or word (diogenes-gaffiot--current-headword))))
         (file (diogenes-gaffiot--file))
         (key (diogenes-gaffiot--key word))
         (coverage (diogenes-gaffiot--coverage file)))
    (when (string-empty-p key)
      (user-error "Nothing to look up in \"%s\"" word))
    ;; A word outside the file's range is not a near miss, so say so rather
    ;; than showing the first or last entry as if it were one.
    (when (and coverage
               (or (string< key (car coverage))
                   (string< (cdr coverage) key)))
      (user-error "Gaffiot: \"%s\" is outside this file, which runs %s-%s \
(the circulating TEI covers A-F)"
                  word (car coverage) (cdr coverage)))
    (let ((diogenes--lookup-same-window diogenes-gaffiot-display-in-same-window))
      (diogenes--search-dict key "latin"
                             #'diogenes--ascii-sort-function
                             #'diogenes--xml-key-fn
                             file))))

;;;###autoload
(defun diogenes-gaffiot-clear-cache ()
  "Forget what Gaffiot dictionary file was found to cover.
Call this after rebuilding the dictionary while Emacs is running."
  (interactive)
  (clrhash diogenes-gaffiot--coverage-cache)
  (message "Diogenes Gaffiot cache cleared"))

(with-eval-after-load 'diogenes-perseus
  (diogenes-gaffiot--install-xml-handlers))

(provide 'diogenes-gaffiot)
;;; diogenes-gaffiot.el ends here
