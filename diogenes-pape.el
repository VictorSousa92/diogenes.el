;;; diogenes-pape.el --- Look up a Greek word in Pape -*- lexical-binding: t -*-

;;; Commentary:

;; Show the entry of Wilhelm Pape's _Handwörterbuch der griechischen
;; Sprache_ (Braunschweig: Vieweg, 1863-1880) for the Greek word you are
;; reading -- in a Diogenes lookup buffer, not a PDF.  From a Greek entry
;; (LSJ), press `P' or click the "[Pape]" link.
;;
;; ---------------------------------------------------------------------
;; WHAT THIS IS, AND WHAT IT IS NOT
;; ---------------------------------------------------------------------
;;
;; This is the Greek counterpart of `diogenes-gaffiot.el', and it works the
;; same way: Pape comes as TEI XML, entry by entry, exactly the kind of
;; thing `diogenes-lookup-mode' already displays for the LSJ and Lewis &
;; Short, so this module adds no display machinery of its own.  It hands
;; Pape to `diogenes--search-dict' as one more dictionary file, and
;; everything the lookup buffer can do comes with it --
;;
;;   * `C-c C-n' / `C-c C-p' walk to the next and previous entry;
;;   * `C-c C-c' on a word looks it up: Greek goes to the LSJ, so you can
;;     step from Pape back into the electronic Greek dictionary, and the
;;     Latin Pape quotes goes to Lewis & Short;
;;   * the print dictionaries are one keystroke away, since the entry
;;     carries the usual "[Montanari] [CGL] [BDAG] [Bailly] [Passow] [TGL]"
;;     banner;
;;   * every entry opens in a fresh buffer, so the LSJ entry you came from
;;     stays live and reachable.
;;
;; It is NOT one of the print-dictionary modules.  `diogenes-passow.el' and
;; its siblings jump a scanned PDF to a page; there is no PDF here, and no
;; provision for one.  Pape's TEI is complete, so a scan would add nothing
;; but a second thing to configure.  This is the one substantive difference
;; from Gaffiot, whose proofread TEI stops at F and which therefore needs
;; `diogenes-gaffiot-pdf.el' to reach the rest of the alphabet, needs to ask
;; whether a word falls inside its range before showing an entry, and needs
;; to explain itself when it does not.  None of that applies here: a word
;; Pape does not have is simply a word Pape does not have, and Diogenes
;; does what it does for the LSJ -- shows the nearest entry and says so,
;; which for a complete dictionary is information rather than a failure.
;;
;; ---------------------------------------------------------------------
;; THE DICTIONARY FILE
;; ---------------------------------------------------------------------
;;
;; Diogenes looks a word up by binary search over a file of ONE ENTRY PER
;; LINE, sorted by a `key' attribute (see `diogenes--binary-search').  For
;; Greek that key is beta code, sorted in the order of the Greek alphabet
;; rather than of ASCII -- see `diogenes--beta-sort-function' -- and the
;; Pape TEI has Unicode headwords full of accents, breathings and macrons
;; spread over a document per letter.  So it has to be converted once:
;;
;;   (setq diogenes-pape-source-file "/path/to/tei-pape")   ; or one file
;;   M-x diogenes-pape-build-dictionary
;;
;; which writes `pape.xml' beside the other Diogenes dictionaries.  Each
;; entry becomes one line, its <orth> becomes the <head> the formatter
;; recognises as a headword, and its key is that headword transliterated
;; into beta code and reduced to bare letters -- diacritics dropped, ᾱ and
;; ᾰ with them, final sigma folded to `s' -- so that the keys the LSJ sends
;; us match.  Offered automatically the first time you press `P' with no
;; dictionary file present.
;;
;; `diogenes-pape-source-file' may name a single XML file, a DIRECTORY of
;; them, or a list: the TEI is usually distributed as one document per
;; letter (grc.pape-deu1.xml ... grc.pape-deu24.xml), and all of them
;; belong in one converted dictionary.
;;
;; ---------------------------------------------------------------------
;; WHAT THE TEI IS ASSUMED TO HAVE FIXED ALREADY
;; ---------------------------------------------------------------------
;;
;; The Dictan database Pape is digitised from spells some Greek letters with
;; the mathematical symbols they resemble -- U+2206 INCREMENT for delta,
;; U+2126 OHM SIGN for omega, about 1,450 times between them, in headwords
;; and article text alike.  Left alone they would defeat this module\'s key:
;; neither is a Greek letter, and only the OHM SIGN has a canonical
;; decomposition, so stripping diacritics quietly repairs one and drops the
;; other, filing \"Ἁ∆εῖν\" under \"aein\".
;;
;; The conversion to TEI normalises them and records having done so in the
;; <projectDesc> of each file, so nothing is needed here.  If you build the
;; dictionary from some other conversion of the same database and a handful
;; of delta entries turn out unreachable, that is where to look.

;;; Code:
(require 'cl-lib)
(require 'seq)
(require 'subr-x)
(require 'diogenes-utils)

(declare-function diogenes--search-dict "diogenes-perseus"
                  (word lang sort-fn key-fn &optional file))
(declare-function diogenes--beta-sort-function "diogenes-perseus" (a b))
(declare-function diogenes--xml-key-fn "diogenes-perseus" (buf))
(declare-function diogenes--lookup-current-headword "diogenes-perseus" ())
(declare-function diogenes--lookup-assert-lang "diogenes-perseus"
                  (expected dict-name))
(declare-function diogenes--lookup-own-dictionary-p "diogenes-perseus" ())
(declare-function diogenes--lookup-dict "diogenes-perseus" (word lang))
(declare-function diogenes-lookup-lewis "diogenes-perseus" (&optional word))
(declare-function diogenes-lookup-open-gaffiot-pdf "diogenes-gaffiot-pdf"
                  (&optional word))
(declare-function diogenes--perseus-path "diogenes" ())
(declare-function diogenes--strip-diacritics "diogenes-utils" (str))
(declare-function diogenes-lookup-register-dictionary "diogenes-perseus"
                  (id &rest keys))
(declare-function diogenes--utf8-to-beta "diogenes-utils" (str))

(defvar diogenes-lookup-mode-map)
(defvar diogenes--lookup-file)
(defvar diogenes--lookup-lang)
(defvar diogenes--lookup-same-window)
(defvar diogenes--dict-xml-handlers-extra)

;;;; --------------------------------------------------------------------
;;;; CUSTOMIZATION
;;;; --------------------------------------------------------------------

(defcustom diogenes-pape-file nil
  "Path to the converted Pape dictionary, one entry per line.
Nil means `pape.xml' among the other Diogenes dictionaries, which is where
\\[diogenes-pape-build-dictionary] writes it -- and where, on many
installations, it cannot: that directory lives inside the Diogenes tree and
is commonly owned by root.  Name a path you can write instead, as for
Gaffiot:

    (setq diogenes-pape-file \"/mnt/archive/Diogenes Data/Lexica/Pape/pape.xml\")

Missing directories are created.  This is NOT the TEI you downloaded -- see
`diogenes-pape-source-file'."
  :type '(choice (const :tag "pape.xml beside the other dictionaries" nil)
                 file)
  :group 'diogenes)

(defcustom diogenes-pape-source-file nil
  "Where the Pape TEI XML lives, as distributed.
Read by \\[diogenes-pape-build-dictionary] to produce `diogenes-pape-file';
not used for lookups afterwards, so it may live anywhere and be deleted
once converted.

The TEI is normally one document per letter of the Greek alphabet, so this
may be any of three things: a single XML file, a DIRECTORY (every *.xml in
it is read, in `string<' order of file name), or an explicit list of files.
All of them go into the one converted dictionary."
  :type '(choice (const :tag "Not set" nil)
                 (file :tag "Single XML file")
                 (directory :tag "Directory of XML files")
                 (repeat :tag "List of XML files" file))
  :group 'diogenes)

(defcustom diogenes-pape-display-in-same-window t
  "If non-nil, show a Pape entry in the window it was invoked from.
The LSJ entry you came from is not destroyed either way -- each lookup gets
a fresh buffer -- so with the default you stay in one window and can return
through the buffer history.  Nil lets `display-buffer' place it as it sees
fit."
  :type 'boolean
  :group 'diogenes)

;;;; --------------------------------------------------------------------
;;;; FORMATTING OF PAPE'S OWN ELEMENTS
;;;; --------------------------------------------------------------------

(defconst diogenes-pape--xml-handlers
  '((hi   . (font-lock-face italic))            ; <hi rend="italic">
    (gram . (font-lock-face font-lock-keyword-face)))
  "Faces for the elements Pape uses and the Perseus dictionaries do not.
Added to `diogenes--dict-xml-handlers-extra' on load, without disturbing an
entry already there, so the LSJ and Lewis & Short keep their appearance.
Pape's <head>, <sense>, <bibl>, <foreign> and <title> need nothing: the
shared handlers in `diogenes--dict-handle-elt' already cover them.  <hi> is
what a TEI conversion writes where the print has italics, and the LSJ uses
it too, so the face improves that as well.")

(defun diogenes-pape--install-xml-handlers ()
  "Teach the dictionary formatter about Pape's elements.  Idempotent."
  (dolist (handler diogenes-pape--xml-handlers)
    (unless (assq (car handler) diogenes--dict-xml-handlers-extra)
      (push handler diogenes--dict-xml-handlers-extra))))

;;;; --------------------------------------------------------------------
;;;; THE KEY A HEADWORD SORTS UNDER
;;;; --------------------------------------------------------------------

(defconst diogenes-pape--beta-letters "abgdevzhqiklmncoprstufxyw"
  "The letters a beta-code key may consist of, and nothing else.
`diogenes--beta-sort-function' looks every character up in
`diogenes--beta-code-alphabet' and SIGNALS on one it does not find, so a
stray Latin letter in a key -- a `j', a `d' from some editorial note --
would not merely sort oddly but break every search that walked past it.
Hence a key is filtered down to these, in this order (alpha beta gamma
delta epsilon digamma zeta eta theta ...), which is the order Greek sorts
in and not the order ASCII does.")

(defun diogenes-pape--key (headword)
  "Return the beta-code key HEADWORD is filed under.
`diogenes--beta-sort-function' compares keys after discarding everything
but ASCII letters, so a key must survive that: the headword is
transliterated into beta code and stripped to bare letters.

Two things happen first.  A headword may offer several forms (\"ἃ ἅ\",
\"α, α. Ἄλφα\") and the first is the one to file it under.  Then diacritics
go: accents, breathings, the iota subscript, and -- the reason the ASCII
rules of the Latin dictionaries will not do here -- the macrons and breves
Pape prints on almost every other headword (ἀγκῡροειδής), which live in
precomposed characters like ᾱ that no transliteration table lists.
Decomposing and dropping the combining marks reduces them to plain υ,
which does transliterate.  Final sigma folds to `s' with the rest.

Wrapped in `save-match-data': this does its own matching, and a caller
that has just located something with `string-match' would otherwise find
its `match-beginning' quietly redirected here."
  (save-match-data
    (let* ((word (or headword ""))
           ;; The first form only.  Pape separates alternatives by comma or
           ;; by space; either ends the word we file under.
           (word (or (car (split-string word "[,;·.]" t "[[:space:]]+")) ""))
           (word (or (car (split-string word "[[:space:]]+" t)) ""))
           ;; `concat' because `diogenes--strip-diacritics' is built on
           ;; `cl-remove-if', whose return type follows its argument: a
           ;; string here, but a list would be just as valid a reading of
           ;; the contract, and `diogenes--utf8-to-beta' inserts into a
           ;; buffer and would not take one.
           (bare (concat (diogenes--strip-diacritics (downcase word))))
           (beta (downcase (diogenes--utf8-to-beta bare))))
      (apply #'string
             (seq-filter (lambda (c)
                           (cl-find c diogenes-pape--beta-letters))
                         (string-to-list beta))))))

(defun diogenes-pape--key< (a b)
  "Non-nil if key A sorts before key B, as the binary search expects.
Delegates to `diogenes--beta-sort-function', which returns `a' when A is
the greater, `b' when B is, and nil when they are equal; A precedes B
exactly when the answer is `b'.

Written this way rather than reimplemented so that the file this module
writes and the search that reads it can never disagree.  They must not:
the Greek alphabet and ASCII part company at ξ -- beta code `c', which
sorts after ν and before ο, but between b and d in ASCII -- so a
dictionary sorted by `string<' would send every binary search for a word
from ο onwards down the wrong half of the file, and the failure would look
like missing entries rather than a sorting bug."
  (eq 'b (diogenes--beta-sort-function a b)))

;;;; --------------------------------------------------------------------
;;;; BUILDING THE DICTIONARY FILE
;;;; --------------------------------------------------------------------

(defun diogenes-pape--dictionary-file ()
  "Return the path of the converted dictionary, whether or not it exists."
  (or diogenes-pape-file
      (file-name-concat (diogenes--perseus-path) "pape.xml")))

(defun diogenes-pape--nearest-existing-directory (dir)
  "Return the innermost existing directory at or above DIR.
The target directory is created on demand, so it is its nearest existing
ancestor whose writability decides whether the build can finish."
  (let ((dir (directory-file-name (expand-file-name dir))))
    (while (and (not (file-directory-p dir))
                (not (string= dir (directory-file-name
                                   (file-name-directory dir)))))
      (setq dir (directory-file-name (file-name-directory dir))))
    dir))

(defun diogenes-pape--assert-writable (target)
  "Signal a user-error unless TARGET can be written.
Asked BEFORE anything is converted.  The default location is inside the
Diogenes installation, which is usually owned by root, and the conversion
takes a minute or two over 80 MB of TEI: finding out at the end, with the
sorted result thrown away and only `Permission denied\' to explain it, is a
poor trade for one call to `file-writable-p\'."
  (unless (if (file-exists-p target)
              (file-writable-p target)
            (file-writable-p (diogenes-pape--nearest-existing-directory
                              (file-name-directory target))))
    (user-error "Cannot write %s -- no permission.  Set \
`diogenes-pape-file\' to a path you own, e.g. (setq diogenes-pape-file \
\"~/.emacs.d/diogenes/pape.xml\")"
                (abbreviate-file-name target))))

(defun diogenes-pape--source-files (&optional source)
  "Return the list of TEI files to convert.
SOURCE defaults to `diogenes-pape-source-file' and may be a file, a
directory, or a list of files; see that variable.  Signals if it names
nothing readable, since the alternative is a silently empty dictionary."
  (let ((source (or source diogenes-pape-source-file)))
    (cond
     ((null source) nil)
     ((consp source)
      (or (seq-filter #'file-readable-p source)
          (user-error "None of the files in `diogenes-pape-source-file' \
can be read")))
     ((file-directory-p source)
      (or (directory-files source t "\\.xml\\'" nil)
          (user-error "No .xml files in %s" (abbreviate-file-name source))))
     ((file-readable-p source) (list source))
     (t (user-error "Cannot read the Pape source at %s"
                    (abbreviate-file-name source))))))

(defconst diogenes-pape--language-codes
  '(("grc" . "greek") ("la" . "latin") ("lat" . "latin")
    ("de" . "german") ("deu" . "german") ("en" . "english"))
  "How a TEI language tag maps onto the languages Diogenes knows.
`diogenes--dict-handle-elt' reads the attribute `lang' and nothing in
Diogenes reads `xml:lang', which is the only one TEI has: a conformant
edition writes `xml:lang=\"grc\"' where this formatter wants
`lang=\"greek\"'.  Only `greek' and `latin' do anything, being the two
languages a lookup can be made in; the rest are here to say positively
that a run of prose is NOT Greek, so that `C-c C-c' on a German word
does not go looking for it in the LSJ.")

(defun diogenes-pape--rewrite-entry (body)
  "Return BODY with TEI's `xml:lang' turned into the `lang' Diogenes reads.
A no-op on a file that already uses `lang', so both the conformant TEI and
the older Diogenes-flavoured conversions build alike.  This is what
`diogenes-bailly.el' and `diogenes-dge.el' do; Pape did not need it while
the only TEI in circulation was already flavoured, and needs it now that
fdb2tei emits an edition a validator accepts."
  (let ((body body))
    (dolist (code diogenes-pape--language-codes)
      (setq body (replace-regexp-in-string
                  (concat "xml:lang=\"" (car code) "\"")
                  (concat "lang=\"" (cdr code) "\"")
                  body t t)))
    body))

(defun diogenes-pape--convert-buffer ()
  "Convert the TEI in the current buffer to a list of (KEY . LINE).
Point is left at the end.  Returns the entries in the order the file gives
them, together with the number skipped as the second value of a cons cell:
\(ENTRIES . SKIPPED)."
  (let ((rows nil)
        (skipped 0))
    (goto-char (point-min))
    ;; The TEI writes attributes on <entryFree> -- xml:id, key, key2, key3 --
    ;; where Gaffiot's has none, so match the tag and not the string.
    (while (re-search-forward "<entryFree\\(?:[[:space:]][^>]*\\)?>" nil t)
      (let ((start (point))
            (end (save-excursion
                   (when (search-forward "</entryFree>" nil t)
                     (match-beginning 0)))))
        (if (null end)
            (cl-incf skipped)
          (let ((body (buffer-substring-no-properties start end)))
            (goto-char end)
            (if (not (string-match
                      "<orth\\([^>]*\\)>\\(\\(?:.\\|\n\\)*?\\)</orth>" body))
                (cl-incf skipped)
              ;; Read the whole match out FIRST: anything that matches in
              ;; between would move these offsets and the <head> would be
              ;; spliced into the middle of the <orth> tag.
              (let* ((orth-start (match-beginning 0))
                     (orth-end (match-end 0))
                     (attrs (match-string 1 body))
                     (orth (match-string 2 body))
                     (plain (replace-regexp-in-string "<[^>]*>" "" orth))
                     (key (diogenes-pape--key plain))
                     ;; Keep the <orth> attributes on the <head>: lang="greek"
                     ;; is what makes `C-c C-c' on the headword search Greek
                     ;; rather than treat it as English prose.
                     (line (concat (substring body 0 orth-start)
                                   "<head" attrs ">" orth "</head>"
                                   (substring body orth-end))))
                (if (string-empty-p key)
                    (cl-incf skipped)
                  (setq line (diogenes-pape--rewrite-entry line))
                  (setq line (replace-regexp-in-string
                              "[[:space:]]*\n[[:space:]]*" " " line))
                  ;; A fresh open tag, so that OUR key is the one
                  ;; `diogenes--xml-key-fn' finds: the TEI carries a Unicode
                  ;; key= of its own, and it matches that regexp first.
                  (push (cons key (format "<entryFree key=\"%s\">%s</entryFree>"
                                          key (string-trim line)))
                        rows))))))))
    (cons (nreverse rows) skipped)))

;;;###autoload
(defun diogenes-pape-build-dictionary (&optional source target)
  "Convert the Pape TEI XML into a dictionary Diogenes can search.
SOURCE defaults to `diogenes-pape-source-file' -- a file, a directory of
per-letter files, or a list -- and TARGET to `diogenes-pape-file'.  Each
<entryFree> becomes one line: its <orth> is renamed <head> (the element
the formatter treats as a headword), the whole entry is flattened, and it
is given the beta-code `key' attribute that `diogenes--binary-search'
sorts on -- see `diogenes-pape--key'.  Entries keep their printed order
within a key, so homographs stay in the sequence Pape prints them in.

Run once, after setting `diogenes-pape-source-file'.  The full dictionary
is some 96,000 entries over 80 MB of TEI and takes a minute or two."
  (interactive)
  (let* ((sources (or (diogenes-pape--source-files source)
                      (list (read-file-name "Pape TEI XML (or directory): "
                                            nil nil t))))
         (sources (diogenes-pape--source-files sources))
         (target (or target (diogenes-pape--dictionary-file)))
         (rows nil)
         (skipped 0))
    (dolist (file sources)
      (when (and (file-exists-p target)
                 (string= (file-truename file) (file-truename target)))
        (user-error "Refusing to convert %s onto itself: \
`diogenes-pape-file' must differ from `diogenes-pape-source-file'"
                    (abbreviate-file-name file))))
    (diogenes-pape--assert-writable target)
    (dolist (file sources)
      (message "Converting %s ..." (file-name-nondirectory file))
      (with-temp-buffer
        (insert-file-contents file)
        (let ((result (diogenes-pape--convert-buffer)))
          (setq rows (nconc rows (car result)))
          (cl-incf skipped (cdr result)))))
    (unless rows
      (user-error "Found no entries in %s: is this the Pape TEI?"
                  (mapconcat #'file-name-nondirectory sources ", ")))
    ;; `sort' on a list is stable, so entries sharing a key keep the order
    ;; the dictionary prints them in -- and, across per-letter files, the
    ;; order the letters were read in.
    (message "Sorting %d entries ..." (length rows))
    (setq rows (sort rows (lambda (a b) (diogenes-pape--key< (car a) (car b)))))
    (make-directory (file-name-directory target) t)
    (let ((coding-system-for-write 'utf-8))
      (with-temp-file target
        (dolist (row rows)
          (insert (cdr row) "\n"))))
    (message "Pape: wrote %d entries (%s-%s) from %d file(s) to %s%s"
             (length rows) (car (car rows)) (car (car (last rows)))
             (length sources)
             (abbreviate-file-name target)
             (if (zerop skipped) "" (format "; skipped %d" skipped)))
    target))

;;;; --------------------------------------------------------------------
;;;; THE LOOKUP
;;;; --------------------------------------------------------------------

(defun diogenes-pape--assert-converted (file)
  "Signal a user-error unless FILE is a converted Pape dictionary.
The lookup wants one entry per line, each with a `key' attribute; handed
the TEI file instead it would fail deep inside `diogenes--xml-key-fn' with
an unhelpful message.  `diogenes-pape-file' is the CONVERTED file; the TEI
belongs in `diogenes-pape-source-file'."
  (with-temp-buffer
    (insert-file-contents file nil 0 400)
    (goto-char (point-min))
    (unless (looking-at "<entryFree[^>]*[[:space:]]key=\"")
      (user-error "%s is not a converted Pape dictionary (it does not begin \
with an entry).  If this is the TEI file, set it as \
`diogenes-pape-source-file' instead and run \
M-x diogenes-pape-build-dictionary"
                  (abbreviate-file-name file)))))

(defun diogenes-pape--file ()
  "Return the converted dictionary file, building it if the user agrees.
Signals rather than returning nil when there is nothing to search: unlike
Gaffiot, Pape has no PDF to fall back on, so a missing dictionary is the
end of the road and the error may as well say how to fix it."
  (let ((file (diogenes-pape--dictionary-file)))
    (cond
     ((file-readable-p file)
      (diogenes-pape--assert-converted file)
      file)
     ((and diogenes-pape-source-file
           (y-or-n-p (format "Pape is not converted yet; build %s now? "
                             (abbreviate-file-name file))))
      (diogenes-pape-build-dictionary diogenes-pape-source-file file))
     (t
      (user-error "Pape is not set up yet: set `diogenes-pape-source-file' \
to the TEI XML (a file, or the directory holding the per-letter files) and \
run M-x diogenes-pape-build-dictionary.  Either in your init file before \
Diogenes loads, or through M-x customize-variable")))))

(defun diogenes-pape-lookup-buffer-p ()
  "Non-nil if the current lookup buffer is showing Pape.
Read from the buffer-local `diogenes--lookup-file', which records the
dictionary the entries were read from.  Used by
`diogenes--lookup-insert-dict-links' to offer \"[Pape]\" in an LSJ entry
and \"[LSJ]\" here, so the link always leads to the other Greek
dictionary rather than the one you are reading."
  (and (boundp 'diogenes--lookup-file)
       diogenes--lookup-file
       (let ((pape (diogenes-pape--dictionary-file)))
         (and (file-exists-p pape)
              (file-exists-p diogenes--lookup-file)
              (string= (file-truename diogenes--lookup-file)
                       (file-truename pape))))))

;;;###autoload
(defun diogenes-lookup-pape (&optional word)
  "Show Pape's entry for WORD in a Diogenes lookup buffer.
Interactively, WORD defaults to the headword of the Greek entry at point;
with a prefix argument, prompt for it.  The entry behaves like any other
lookup: `C-c C-n' and `C-c C-p' walk the dictionary, `C-c C-c' on a Greek
word returns to the LSJ, and the print-dictionary banner opens Montanari,
the CGL, BDAG, Bailly, Passow and the TGL.

Pape is complete, so there is no coverage to check and no printed
supplement to fall back on: a word that is not in it produces the nearest
entry, with a message saying so, exactly as the LSJ does.

Requires a converted dictionary file; see
\\[diogenes-pape-build-dictionary]."
  (interactive
   (progn
     (diogenes--lookup-assert-lang "greek" "Pape")
     ;; Already here: `l' leads back to the LSJ.
     (when (and (not current-prefix-arg) (diogenes-pape-lookup-buffer-p))
       (user-error "This entry is Pape already; `l' returns to the LSJ, \
`C-u P' looks up another word here"))
     (list (if current-prefix-arg
               (read-string "Look up in Pape: ")
             (diogenes--lookup-current-headword)))))
  (let* ((word (string-trim (or word (diogenes--lookup-current-headword))))
         (file (diogenes-pape--file))
         (key (diogenes-pape--key word)))
    (when (string-empty-p key)
      (user-error "Nothing to look up in \"%s\"" word))
    (let ((diogenes--lookup-same-window diogenes-pape-display-in-same-window))
      (diogenes--search-dict key "greek"
                             #'diogenes--beta-sort-function
                             #'diogenes--xml-key-fn
                             file))))

;;;###autoload
(defun diogenes-lookup-lsj (&optional word)
  "Show the LSJ entry for WORD in a lookup buffer.
Interactively, WORD defaults to the headword of the Greek entry at point;
with a prefix argument, prompt for it.  This is the way back from another
Greek dictionary -- Pape, say -- to the one Diogenes searches by default,
and it is what the \"[LSJ]\" link in a Pape entry runs.  The exact Greek
counterpart of `diogenes-lookup-lewis', and it lives here only because
Pape is the first Greek dictionary to need a way back."
  (interactive
   (progn
     (diogenes--lookup-assert-lang "greek" "LSJ")
     (unless (or current-prefix-arg
                 (not (diogenes--lookup-own-dictionary-p)))
       (user-error "This entry is the LSJ already; `P' opens Pape, \
`C-u l' looks up another word here"))
     (list (if current-prefix-arg
               (read-string "Look up in the LSJ: ")
             (diogenes--lookup-current-headword)))))
  (let ((word (string-trim (or word (diogenes--lookup-current-headword))))
        (diogenes--lookup-same-window (derived-mode-p 'diogenes-lookup-mode)))
    (when (string-empty-p word)
      (user-error "No word given"))
    (diogenes--lookup-dict word "greek")))

;;;; --------------------------------------------------------------------
;;;; KEYS THAT SERVE BOTH LANGUAGES
;;;; --------------------------------------------------------------------

;; `p' is Passow's, so Pape takes `P'.  In `diogenes-lookup-mode-map' that
;; was the printed Gaffiot, and `l' was Lewis & Short; both are Latin-only
;; and would refuse a Greek entry.  Rather than move anyone's keys, these
;; two dispatch on the language of the entry, as
;; `diogenes-lookup-open-tll-or-tgl' already does for `t'.

;;;###autoload
(defun diogenes-lookup-pape-or-gaffiot-pdf ()
  "Open Pape on a Greek entry, the printed Gaffiot on a Latin one.
Retained for anyone who has bound this command themselves; \\`P' no longer
points here.  The printed Gaffiot is reached by pressing \\`g' a second time
from inside a Gaffiot article -- as \\`B' is Bailly\='s and \\`G' Georges\=' --
so a Latin branch on \\`P' is a second route to somewhere that now has its
own, and one that made \\`P' mean two unrelated dictionaries depending on
the buffer.  \\`P' is Pape, and Greek."
  (interactive)
  (let ((lang (and (boundp 'diogenes--lookup-lang) diogenes--lookup-lang)))
    (pcase lang
      ("greek" (call-interactively #'diogenes-lookup-pape))
      (_       (call-interactively #'diogenes-lookup-open-gaffiot-pdf)))))

;;;###autoload
(defun diogenes-lookup-lewis-or-lsj ()
  "Return to the language's own dictionary: the LSJ in Greek, Lewis in Latin.
Bound to \\`l' in `diogenes-lookup-mode'.  Before Pape, `l' was Lewis &
Short and Greek entries had no other electronic dictionary to come back
from; now it dispatches on the buffer-local `diogenes--lookup-lang'.  A
prefix argument is passed through.  If the language is unknown it falls
back to Lewis & Short, the historical binding of this key."
  (interactive)
  (let ((lang (and (boundp 'diogenes--lookup-lang) diogenes--lookup-lang)))
    (pcase lang
      ("greek" (call-interactively #'diogenes-lookup-lsj))
      (_       (call-interactively #'diogenes-lookup-lewis)))))

(defun diogenes-pape--install-keys ()
  "Point \\`l' at its language-dispatching command, and \\`P' at Pape.  Idempotent.
\\`l' has two dictionaries to choose between and must dispatch: the LSJ in
Greek, Lewis & Short in Latin.  \\`P' no longer does.  It once opened the
printed Gaffiot on a Latin entry, that PDF having no key of its own, but
`g\=' pressed a second time from inside a Gaffiot article reaches it now --
as `B\=' does in Bailly and `G\=' in Georges -- so the Latin branch only made
one key stand for two unrelated dictionaries.  Pressed on a Latin entry
`P\=' now says that Pape is Greek, which is the truth about the key."
  (when (boundp 'diogenes-lookup-mode-map)
    (keymap-set diogenes-lookup-mode-map "P" #'diogenes-lookup-pape)
    (keymap-set diogenes-lookup-mode-map "l"
                #'diogenes-lookup-lewis-or-lsj)))

;;;; --------------------------------------------------------------------
;;;; REGISTRATION
;;;; --------------------------------------------------------------------

(defun diogenes-pape--register ()
  "Announce Pape, and the LSJ as the way back, to the lookup banner.
Idempotent.  Both are `:show unless-current': Pape is not offered inside
Pape, and the LSJ is not offered inside the LSJ -- which
`diogenes--lookup-own-dictionary-p' recognises -- so from Pape or from
Bailly the LSJ link appears, and in the LSJ it does not.

Neither binds its key here.  `P' and `l' have to serve both languages, so
`diogenes-pape--install-keys' binds them: `l\=' to a dispatcher, since it has
the LSJ and Lewis & Short to choose between, and `P\=' straight to Pape."
  (diogenes-lookup-register-dictionary
   'pape :lang "greek" :name "Pape" :key "P" :order 60
   :command #'diogenes-lookup-pape
   :show 'unless-current
   :buffer-p #'diogenes-pape-lookup-buffer-p
   :help "Show Pape's entry for \"%s\"")
  (diogenes-lookup-register-dictionary
   'lsj :lang "greek" :name "LSJ" :key "l" :order 80
   :command #'diogenes-lookup-lsj
   :show 'unless-current
   :buffer-p #'diogenes--lookup-own-dictionary-p
   :help "Show the LSJ entry for \"%s\""))

(with-eval-after-load 'diogenes-perseus
  (diogenes-pape--install-xml-handlers)
  (diogenes-pape--install-keys)
  (diogenes-pape--register))

(provide 'diogenes-pape)
;;; diogenes-pape.el ends here
