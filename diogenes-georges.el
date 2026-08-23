;;; diogenes-georges.el --- Georges' Lateinisch-Deutsches Handwörterbuch -*- lexical-binding: t -*-

;;; Commentary:

;; Karl Ernst Georges' _Ausführliches lateinisch-deutsches Handwörterbuch_
;; (8th ed., 1913-1918) as a searchable dictionary, from the TEI XML of the
;; Dictan/Fora digitisation.  From a Latin entry press `G' -- capital, since
;; `g' is Gaffiot -- or click the "[Georges]" link.
;;
;; Built the way Bailly is, and for the same reason: the TEI is one 40 MB
;; document holding 54 740 <entryFree>s in the order the digitiser happened
;; to emit them, which no binary search can use.  So it is converted once,
;; each entry to a line, keyed and sorted:
;;
;;   (setq diogenes-georges-source-file "/path/to/georges-tei.xml")
;;   M-x diogenes-georges-build-dictionary
;;
;; and thereafter searched like the LSJ or Lewis & Short, by
;; `diogenes--search-dict' over the file the conversion wrote.
;;
;; ---------------------------------------------------------------------
;; COLLATION
;; ---------------------------------------------------------------------
;;
;; Georges prints the quantity of every vowel he can -- 15 247 headwords
;; carry a macron on an a alone -- numbers his homographs with superscripts
;; ("ā,²"), and has 220 headwords of more than one word ("Acca Lārentia").
;; None of that can appear in a key: `diogenes--ascii-sort-function', the
;; comparator the search uses, throws away everything but ASCII letters
;; before it compares, so a key that kept a space or a numeral would sit in
;; the file at a place the search would never look.
;;
;; One fold earns its place.  Georges has not one j-initial headword in 54
;; 740: he writes consonantal i as i, where Lewis & Short keys `jacio'.  So
;; j is written i in a key, and a lemma arriving from a Lewis & Short entry
;; finds its Georges article.  U and v are left alone -- Georges keeps them
;; apart, as Lewis & Short does.
;;
;; ---------------------------------------------------------------------
;; THE PRINTED VOLUMES
;; ---------------------------------------------------------------------
;;
;; The scans that were this module's whole subject now live in
;; `diogenes-georges-pdf.el', reached by pressing `G' a second time from
;; inside a Georges entry, exactly as Bailly's PDF is reached from a Bailly
;; entry.  Their page index is unchanged.

;;; Code:
(require 'cl-lib)
(require 'seq)
(require 'subr-x)
(require 'ucs-normalize)
(require 'diogenes-lisp-utils)          ; diogenes--path-usable-p

(declare-function diogenes-lookup-register-dictionary "diogenes-perseus"
                  (id &rest keys))
(declare-function diogenes--search-dict "diogenes-perseus"
                  (word lang sort-fn key-fn &optional file))
(declare-function diogenes--ascii-sort-function "diogenes-lisp-utils" (a b))
(declare-function diogenes--xml-key-fn "diogenes-perseus" (buf))
(declare-function diogenes--lookup-assert-lang "diogenes-perseus"
                  (expected dict-name))
(declare-function diogenes--lookup-current-headword "diogenes-perseus" ())
(declare-function diogenes-dict-flatten-hi "diogenes-dict-faces" (body))
(declare-function diogenes-dict-install-faces "diogenes-dict-faces" ())
(declare-function diogenes-georges-pdf-available-p "diogenes-georges-pdf" ())
(declare-function diogenes-lookup-open-georges-pdf "diogenes-georges-pdf"
                  (&optional word))

(defvar diogenes--lookup-file)
(defvar diogenes--lookup-same-window)
(defvar diogenes--dict-xml-handlers-extra)

;;;; --------------------------------------------------------------------
;;;; CUSTOMIZATION
;;;; --------------------------------------------------------------------

(defcustom diogenes-georges-file nil
  "The CONVERTED Georges dictionary: one entry per line, keyed and sorted.
Written by \\[diogenes-georges-build-dictionary] from
`diogenes-georges-source-file', and the file the lookup searches.  It must
not be the TEI file itself; see that variable.

Unset, the converted file is looked for as \"georges.xml\" beside the source."
  :type '(choice (const :tag "Beside the source file" nil) file)
  :group 'diogenes)

(defcustom diogenes-georges-source-file nil
  "The Georges TEI XML, as distributed: the SOURCE of the conversion.
A file, a directory of per-letter files, or a list of files.  Converted
once by \\[diogenes-georges-build-dictionary] into
`diogenes-georges-file', which is what searches read: the TEI is a single
40 MB document whose entries are in no order a binary search can use."
  :type '(choice (const :tag "Not set" nil) file directory
                 (repeat file))
  :group 'diogenes)

(defcustom diogenes-georges-display-in-same-window t
  "Whether a Georges entry replaces the entry it was called from.
Non-nil reuses the window, as a dictionary consulted about the entry in
front of you should; nil opens it as `display-buffer' sees fit."
  :type 'boolean
  :group 'diogenes)

;;;; --------------------------------------------------------------------
;;;; FORMATTING OF GEORGES' OWN ELEMENTS
;;;; --------------------------------------------------------------------

(defconst diogenes-georges--xml-handlers
  '()
  "Faces peculiar to Georges, over and above `diogenes-dict-tei-faces'.
Empty, as Bailly's is: this TEI uses <orth>, <sense>, <def>, <hi> and
<foreign>, all of which the shared table in `diogenes-dict-faces.el'
colours already -- <def> and <lb> being unwrapped at conversion time
rather than coloured.  Kept so a Georges-only element has somewhere to
go.")

(defun diogenes-georges--install-xml-handlers ()
  "Teach the dictionary formatter about Georges' elements.  Idempotent."
  (dolist (handler diogenes-georges--xml-handlers)
    (unless (assq (car handler) diogenes--dict-xml-handlers-extra)
      (push handler diogenes--dict-xml-handlers-extra)))
  (diogenes-dict-install-faces))

;;;; --------------------------------------------------------------------
;;;; THE KEY A HEADWORD SORTS UNDER
;;;; --------------------------------------------------------------------

(defun diogenes-georges--key (headword)
  "Return the collation key HEADWORD is filed under.
ASCII letters only, case-folded, with j written i.

Three things are removed.  The vowel quantities Georges prints on every
headword -- macron above all, but also diaeresis and breve: 15 247
headwords carry an a-macron alone -- are dropped by decomposing to NFD and
discarding the combining marks.  The superscript numeral that
distinguishes homographs goes with them (\"ā,²\" keys as a).  And the word
space of a multi-word headword goes too: there are 220 of them, \"Acca
Lārentia\" among the rest, and `diogenes--ascii-sort-function' -- the
comparator the search uses -- discards everything but letters before
comparing, so a key that kept its space would sort in this file at a
place the search would never look for it.

The fold of j onto i is what lets a lemma arrive from Lewis & Short at
all.  Georges has not one j-initial headword in 54 740; he writes
consonantal i as i, where Lewis & Short keys `jacio'.  Both then key as
iacio.  U and v are NOT folded: Georges keeps them apart, as Lewis & Short
does, and folding them would merge two letters the dictionary separates."
  (save-match-data
    (let* ((word (or headword ""))
           ;; Only the first of several forms is the one it is filed under.
           (word (or (car (split-string word "[,;]" t "[[:space:]]+")) ""))
           (word (ucs-normalize-NFD-string word))
           (letters nil))
      (dolist (c (string-to-list word))
        (unless (<= #x0300 c #x036f)          ; combining marks
          (let ((c (downcase c)))
            (cond ((eq c ?j) (push ?i letters))
                  ((<= ?a c ?z) (push c letters))))))
      (apply #'string (nreverse letters)))))

(defun diogenes-georges--key< (a b)
  "Non-nil if key A sorts before key B, as the binary search expects.
Delegates to `diogenes--ascii-sort-function', which answers `a' when A is
the greater, `b' when B is, and nil when they are equal, so A precedes B
exactly when the answer is `b'.

Written this way rather than as `string<' so that the file this module
writes and the search that reads it cannot drift apart.  They must not:
the search discards everything but ASCII letters before it compares, and a
file sorted on anything else -- spaces, numerals, macrons -- would send a
binary search down the wrong half and look for all the world like missing
entries."
  (eq 'b (diogenes--ascii-sort-function a b)))

;;;; --------------------------------------------------------------------
;;;; BUILDING THE DICTIONARY FILE
;;;; --------------------------------------------------------------------

(defun diogenes-georges--dictionary-file ()
  "Return the path of the converted dictionary, whether or not it exists."
  (or diogenes-georges-file
      (let ((source (if (consp diogenes-georges-source-file)
                        (car diogenes-georges-source-file)
                      diogenes-georges-source-file)))
        (when source
          (expand-file-name
           "georges.xml"
           (if (file-directory-p source)
               source
             (file-name-directory (expand-file-name source))))))))

(defun diogenes-georges--assert-writable (target)
  "Signal unless TARGET can be written, saying what to change if it cannot."
  (unless target
    (user-error "Set `diogenes-georges-file' or `diogenes-georges-source-file' \
first: there is nowhere to write the converted dictionary"))
  (let ((dir (file-name-directory (expand-file-name target))))
    (unless (file-writable-p (if (file-exists-p dir) dir target))
      (user-error "Cannot write %s: choose a `diogenes-georges-file' \
somewhere writable, %s for instance"
                  (abbreviate-file-name target)
                  (abbreviate-file-name
                   (expand-file-name "diogenes/georges.xml"
                                     user-emacs-directory))))))

(defun diogenes-georges--source-files (&optional source)
  "Return the list of TEI files to convert.
SOURCE defaults to `diogenes-georges-source-file' and may be a file, a
directory, or a list of files.  Signals if it names nothing readable,
since the alternative is a silently empty dictionary."
  (let ((source (or source diogenes-georges-source-file)))
    (cond
     ((null source) nil)
     ((consp source)
      (or (seq-filter #'file-readable-p source)
          (user-error "None of the files in `diogenes-georges-source-file' \
can be read")))
     ((file-directory-p source)
      (or (directory-files source t "\\.xml\\'" nil)
          (user-error "No .xml files in %s" (abbreviate-file-name source))))
     ((file-readable-p source) (list source))
     (t (user-error "Cannot read the Georges source at %s"
                    (abbreviate-file-name source))))))

(defun diogenes-georges--rewrite-entry (body)
  "Return BODY, the inside of one TEI <entryFree>, as the formatter wants it.
Four rewritings.  `xml:lang=\"grc\"' becomes the `lang=\"greek\"' that
`diogenes--dict-handle-elt' actually reads -- there are 20 537 <foreign>
elements in this dictionary, Georges glossing his Latin with the Greek it
translates -- and the German gets `lang=\"german\"' for the same reason.
<def> is unwrapped: it is TEI's container for the body of a sense, carries
nothing the formatter renders, and nests inside <sense> in a way that
would otherwise indent every definition twice.  <lb/> becomes a space.

<orth> is NOT renamed here: `diogenes-georges--convert-buffer' does that,
having found it already while reading the headword out."
  (let ((body body))
    (setq body (replace-regexp-in-string
                "xml:lang=\"grc\"" "lang=\"greek\"" body t t))
    (setq body (replace-regexp-in-string
                "xml:lang=\"de\"" "lang=\"german\"" body t t))
    (setq body (replace-regexp-in-string "</?def>" "" body t t))
    (setq body (replace-regexp-in-string "<lb[^>]*/?>" " " body t))
    ;; <hi rend="..."> becomes i / b / sc / sup, so that italic, bold and
    ;; small capitals can be told apart by the face table, which sees
    ;; element names only.  Georges leans on it hard: 585 957 <hi>s, the
    ;; German of his glosses being italic throughout.
    (diogenes-dict-flatten-hi body)))

(defun diogenes-georges--convert-buffer ()
  "Convert the TEI in the current buffer to a list of (KEY . LINE).
Returns (ENTRIES . SKIPPED), the entries in the order the file gives them.

Each <entryFree> becomes one line: its <orth> is renamed <head>, keeping
its attributes so that `C-c C-c' on the headword searches Latin, the rest
is rewritten by `diogenes-georges--rewrite-entry', newlines are folded to
spaces so the line-oriented binary search stays line-oriented, and a fresh
`key' is put on the opening tag.  The key goes on a tag of our own writing
because `diogenes--xml-key-fn' takes the FIRST `key=' in the line."
  (let ((rows nil)
        (skipped 0))
    (goto-char (point-min))
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
              ;; Read the whole match out FIRST: anything matched in between
              ;; would move these offsets and the <head> would be spliced
              ;; into the middle of the <orth> tag.
              (let* ((orth-start (match-beginning 0))
                     (orth-end (match-end 0))
                     (attrs (match-string 1 body))
                     (orth (match-string 2 body))
                     (plain (replace-regexp-in-string "<[^>]*>" "" orth))
                     (key (diogenes-georges--key plain))
                     (line (concat (substring body 0 orth-start)
                                   "<head" attrs " lang=\"latin\">"
                                   orth "</head>"
                                   (substring body orth-end))))
                (if (string-empty-p key)
                    (cl-incf skipped)
                  (setq line (diogenes-georges--rewrite-entry line))
                  (setq line (replace-regexp-in-string
                              "[[:space:]]*\n[[:space:]]*" " " line))
                  (push (cons key (format "<entry key=\"%s\">%s</entry>"
                                          key (string-trim line)))
                        rows))))))))
    (cons (nreverse rows) skipped)))

;;;###autoload
(defun diogenes-georges-build-dictionary (&optional source target)
  "Convert the Georges TEI XML into a dictionary Diogenes can search.
SOURCE defaults to `diogenes-georges-source-file' and TARGET to
`diogenes-georges-file'.  Each <entryFree> becomes one line, keyed by
`diogenes-georges--key' and sorted by `diogenes-georges--key<'; entries
keep their printed order within a key, so numbered homographs stay in the
sequence Georges prints them in.

Run once, after setting `diogenes-georges-source-file'.  The dictionary is
some 54 700 entries over 40 MB of TEI and takes a minute or so."
  (interactive)
  (let* ((sources (or (diogenes-georges--source-files source)
                      (list (read-file-name "Georges TEI XML (or directory): "
                                            nil nil t))))
         (sources (diogenes-georges--source-files sources))
         (target (or target (diogenes-georges--dictionary-file)))
         (rows nil)
         (skipped 0))
    (dolist (file sources)
      (when (and target (file-exists-p target)
                 (string= (file-truename file) (file-truename target)))
        (user-error "Refusing to convert %s onto itself: \
`diogenes-georges-file' must differ from `diogenes-georges-source-file'"
                    (abbreviate-file-name file))))
    (diogenes-georges--assert-writable target)
    ;; A 40 MB conversion allocates hard enough that the default threshold
    ;; has Emacs collecting more than it converts.
    (let ((gc-cons-threshold (max gc-cons-threshold (* 256 1024 1024))))
      (dolist (file sources)
        (message "Converting %s ..." (file-name-nondirectory file))
        (with-temp-buffer
          (insert-file-contents file)
          (let ((result (diogenes-georges--convert-buffer)))
            (setq rows (nconc rows (car result)))
            (cl-incf skipped (cdr result))))))
    (unless rows
      (user-error "Found no <entryFree> in %s: is this the Georges TEI?"
                  (mapconcat #'file-name-nondirectory sources ", ")))
    ;; `sort' on a list is stable, so entries sharing a key keep the order
    ;; the dictionary prints them in.
    (message "Sorting %d entries ..." (length rows))
    ;; `string<' rather than `diogenes-georges--key<': the keys were built
    ;; by `diogenes-georges--key' and hold nothing but lowercase ASCII
    ;; letters already, so the normalising the comparator would do on every
    ;; one of the ~900,000 comparisons a sort of this size needs is wasted
    ;; -- four fresh strings each time, for the same answer.  The two agree
    ;; exactly on keys of this shape, which is what makes the substitution
    ;; safe; `diogenes-georges--key<' remains the definition of record.
    (setq rows (sort rows (lambda (a b) (string< (car a) (car b)))))
    (make-directory (file-name-directory target) t)
    (let ((coding-system-for-write 'utf-8))
      (with-temp-file target
        (dolist (row rows)
          (insert (cdr row) "\n"))))
    (message "Georges: wrote %d entries (%s-%s) from %d file(s) to %s%s"
             (length rows) (car (car rows)) (car (car (last rows)))
             (length sources)
             (abbreviate-file-name target)
             (if (zerop skipped) "" (format "; skipped %d" skipped)))
    target))

;;;; --------------------------------------------------------------------
;;;; THE LOOKUP
;;;; --------------------------------------------------------------------

(defun diogenes-georges--assert-converted (file)
  "Signal a user-error unless FILE is a converted Georges dictionary.
The lookup wants one entry per line, each with a `key' attribute; handed
the TEI instead it would fail deep inside `diogenes--xml-key-fn' with an
unhelpful message."
  (with-temp-buffer
    (insert-file-contents file nil 0 400)
    (goto-char (point-min))
    (unless (looking-at "<entry[^>]*[[:space:]]key=\"")
      (user-error "%s is not a converted Georges dictionary (no key= on its \
first entry).  If this is the TEI file, set it as \
`diogenes-georges-source-file' instead and run \
M-x diogenes-georges-build-dictionary"
                  (abbreviate-file-name file)))))

;;;###autoload
(defun diogenes-georges-xml-available-p ()
  "Non-nil if the Georges XML is here, or could be built without asking twice.
True when the converted dictionary exists, and also when it does not but
`diogenes-georges-source-file' names TEI that is there -- because then
pressing `G' offers to build it.  `diogenes-georges--dictionary-file'
returns nil when neither option is set, which is unavailable too.  Never
signals: this is asked while an entry is being drawn."
  (let ((file (ignore-errors (diogenes-georges--dictionary-file))))
    (or (and file (file-readable-p file))
        (diogenes--source-usable-p diogenes-georges-source-file))))

;;;###autoload
(defun diogenes-georges-available-p ()
  "Non-nil if Georges can be reached at all, as XML or as printed volumes.
Either half is enough, `diogenes-lookup-georges' dispatching on which is
actually there: with the XML converted the link opens the entry, with only
`diogenes-georges-directory' set it opens the page instead, as the OLD and
the TLL do.  With neither the link is not offered."
  (or (diogenes-georges-xml-available-p)
      (and (require 'diogenes-georges-pdf nil t)
           (diogenes-georges-pdf-available-p))))

(defun diogenes-georges--file ()
  "Return the converted dictionary file, building it if the user agrees.
Falls back on nothing: unlike Gaffiot, whose TEI covers part of the
alphabet only, this XML is the whole of the Handwörterbuch.  The printed
volumes remain reachable from a Georges entry -- see
`diogenes-georges-pdf.el' -- but they are not an alternative to having
converted it."
  (let ((file (diogenes-georges--dictionary-file)))
    (cond
     ((and file (file-readable-p file))
      (diogenes-georges--assert-converted file)
      file)
     ((and diogenes-georges-source-file
           (y-or-n-p (format "Georges is not converted yet; build %s now? "
                             (abbreviate-file-name file))))
      (diogenes-georges-build-dictionary diogenes-georges-source-file file))
     (t
      (user-error "Georges is not set up yet: set \
`diogenes-georges-source-file' to the TEI XML and run \
M-x diogenes-georges-build-dictionary.  Either in your init file before \
Diogenes loads, or through M-x customize-variable")))))

(defun diogenes-georges-lookup-buffer-p ()
  "Non-nil if the current lookup buffer is showing Georges.
Read from the buffer-local `diogenes--lookup-file', which records the
dictionary the entries were read from.  Used by the banner, so that the
link always leads somewhere you are not, and by
`diogenes-lookup-georges', so that `G' pressed inside a Georges entry
opens the printed page instead of looking the word up again."
  (and (boundp 'diogenes--lookup-file)
       diogenes--lookup-file
       (let ((georges (diogenes-georges--dictionary-file)))
         (and georges
              (file-exists-p georges)
              (file-exists-p diogenes--lookup-file)
              (string= (file-truename diogenes--lookup-file)
                       (file-truename georges))))))

;;;###autoload
(defun diogenes-lookup-georges (&optional word)
  "Show Georges' entry for WORD in a Diogenes lookup buffer.
Interactively, WORD defaults to the headword of the Latin entry at point;
with a prefix argument, prompt for it.  The entry behaves like any other
lookup: `C-c C-n' and `C-c C-p' walk the dictionary, `C-c C-c' on a word
returns to Lewis & Short, and the print-dictionary banner opens the OLD,
the TLL and Gaffiot.

A word Georges does not have produces the nearest entry, with a message
saying so, exactly as Lewis & Short does.

With only `diogenes-georges-directory' set and no XML converted, Georges is
simply a print dictionary like the OLD, and this command opens the page
rather than explaining what is not installed.

Pressed a second time, from INSIDE the entry it has just shown, it opens
that word's page in the printed Handwörterbuch instead -- see
`diogenes-lookup-open-georges-pdf'.  `C-u G' looks another word up in the
XML from there.

Requires either a converted dictionary file (see
\\[diogenes-georges-build-dictionary]) or the printed volumes."
  (interactive
   (progn
     (diogenes--lookup-assert-lang "latin" "Georges")
     (list (if current-prefix-arg
               (read-string "Look up in Georges: ")
             (diogenes--lookup-current-headword)))))
  ;; Already reading Georges: this key's other job is the printed page.
  ;; Checked here rather than in the `interactive' form so that the banner
  ;; link, which calls us with a word, dispatches the same way.
  (if (and (null current-prefix-arg) (diogenes-georges-lookup-buffer-p))
      (if (and (require 'diogenes-georges-pdf nil t)
               (diogenes-georges-pdf-available-p))
          (diogenes-lookup-open-georges-pdf word)
        (user-error "This entry is Georges already; set \
`diogenes-georges-directory' to reach the printed page from here, `l' \
returns to Lewis & Short, `C-u G' looks up another word here"))
    (let ((word (string-trim (or word (diogenes--lookup-current-headword)))))
      (cond
       ;; No XML, and none to build: whatever Georges the user has is the
       ;; printed one, so send the word there instead of asking for a TEI
       ;; file that is not wanted.
       ((not (diogenes-georges-xml-available-p))
        (if (and (require 'diogenes-georges-pdf nil t)
                 (diogenes-georges-pdf-available-p))
            (diogenes-lookup-open-georges-pdf word)
          ;; Neither half configured: let `diogenes-georges--file' say so,
          ;; rather than repeating its message here.
          (diogenes-georges--file)))
       (t
        (let ((file (diogenes-georges--file))
              (key (diogenes-georges--key word)))
          (when (string-empty-p key)
            (user-error "Nothing to look up in \"%s\"" word))
          (let ((diogenes--lookup-same-window
                 diogenes-georges-display-in-same-window))
            (diogenes--search-dict key "latin"
                                   #'diogenes--ascii-sort-function
                                   #'diogenes--xml-key-fn
                                   file))))))))

;;;; --------------------------------------------------------------------
;;;; REGISTRATION
;;;; --------------------------------------------------------------------

(defun diogenes-georges--register ()
  "Announce Georges to the lookup banner.  Idempotent.
`:show unless-current' keeps the link out of a Georges entry, where its
place is taken by \"[PDF (G)]\" -- registered by `diogenes-georges-pdf.el',
which is also what makes the printed volumes unreachable from anywhere
else.  `:bind t' puts `G' on `diogenes-lookup-georges': the key is
Latin-only, so it needs no language dispatcher of the kind `P' and `l'
have."
  (diogenes-lookup-register-dictionary
   'georges :lang "latin" :name "Georges" :key "G" :order 75
   :command #'diogenes-lookup-georges
   :show 'unless-current
   :buffer-p #'diogenes-georges-lookup-buffer-p
   :available-p #'diogenes-georges-available-p
   :bind t
   :help "Show Georges' entry for \"%s\""))

(with-eval-after-load 'diogenes-perseus
  (diogenes-georges--install-xml-handlers)
  (diogenes-georges--register))

(provide 'diogenes-georges)
;;; diogenes-georges.el ends here
