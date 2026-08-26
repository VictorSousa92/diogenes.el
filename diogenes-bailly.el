;;; diogenes-bailly.el --- Look up a Greek word in Bailly -*- lexical-binding: t -*-

;;; Commentary:

;; Show the entry of Anatole Bailly's _Dictionnaire grec-français_ -- in the
;; re-typeset and corrected edition "Bailly 2020 - Hugo Chávez" (Gérard
;; Gréco, André Charbonnet, Mark De Wilde, Bernard Maréchal) -- for the
;; Greek word you are reading, in a Diogenes lookup buffer.  From a Greek
;; entry (the LSJ, or Pape), press `B' or click the "[Bailly (B)]" link.
;;
;; ---------------------------------------------------------------------
;; WHAT THIS IS, AND WHAT IT IS NOT
;; ---------------------------------------------------------------------
;;
;; This is the Greek counterpart of `diogenes-gaffiot.el', and it works the
;; same way: Bailly comes as TEI XML, entry by entry, exactly the kind of
;; thing `diogenes-lookup-mode' already displays for the LSJ and Lewis &
;; Short, so this module adds no display machinery of its own.  It hands
;; Bailly to `diogenes--search-dict' as one more dictionary file, and
;; everything the lookup buffer can do comes with it --
;;
;;   * `C-c C-n' / `C-c C-p' walk to the next and previous entry;
;;   * `C-c C-c' on a word looks it up: Greek goes to the LSJ, so you can
;;     step from Bailly back into the electronic Greek dictionary;
;;   * the print dictionaries are one keystroke away, since the entry
;;     carries the usual "[Montanari] [CGL] [BDAG] [Passow] [TGL]" banner;
;;   * every entry opens in a fresh buffer, so the LSJ entry you came from
;;     stays live and reachable.
;;
;; It is NOT one of the print-dictionary modules, and this is where it
;; parts company with Gaffiot.  Gaffiot's proofread TEI stops at F, so
;; `diogenes-gaffiot.el' asks whether a word falls inside its range and
;; sends the rest to `diogenes-gaffiot-pdf.el'.  Nothing of the sort
;; applies here: the Bailly 2020 XML is the whole dictionary, all 110,000
;; articles of it, and it is the same text the PDF prints.  So the PDF is
;; never a fallback and `B' never opens it from the LSJ or from Pape.  A
;; word Bailly does not have is simply a word Bailly does not have, and
;; Diogenes does what it does for the LSJ -- shows the nearest entry and
;; says so, which for a complete dictionary is information rather than a
;; failure.
;;
;; The printed page is still worth reaching, for the typography and the
;; page as an object; `diogenes-bailly-pdf.el' opens it, from INSIDE a
;; Bailly entry only, on the same `B' that brought you here (or the
;; "[PDF (B)]" link in the entry's banner).  Pressing `B' twice therefore
;; walks LSJ -> Bailly entry -> Bailly page, which is the one path where
;; the PDF is what you asked for rather than what was left when the XML
;; came up short.
;;
;; ---------------------------------------------------------------------
;; THE DICTIONARY FILE
;; ---------------------------------------------------------------------
;;
;; Diogenes looks a word up by binary search over a file of ONE ENTRY PER
;; LINE, sorted by a `key' attribute (see `diogenes--binary-search').  For
;; Greek that key is beta code, sorted in the order of the Greek alphabet
;; rather than of ASCII -- see `diogenes--beta-sort-function' -- and the
;; TEI has Unicode headwords full of accents and breathings.  So it has to
;; be converted once:
;;
;;   (setq diogenes-bailly-source-file "/path/to/bailly-tei.xml")
;;   M-x diogenes-bailly-build-dictionary
;;
;; which writes `bailly.xml' beside the other Diogenes dictionaries.  Each
;; <entry> becomes one line, its <orth> becomes the <head> the formatter
;; recognises as a headword, and its key is that headword transliterated
;; into beta code and reduced to bare letters, so that the keys the LSJ
;; sends us match.  Offered automatically the first time you press `B' with
;; no dictionary file present.
;;
;; `diogenes-bailly-source-file' may name a single XML file, a DIRECTORY of
;; them, or a list, as Pape's does: the conversion is the same whether the
;; TEI arrives whole or split per letter.
;;
;; ---------------------------------------------------------------------
;; WHAT THE CONVERSION DOES TO THE TEI
;; ---------------------------------------------------------------------
;;
;; Four rewritings, all of them for the formatter's benefit and none of
;; them touching the text.  The converted file is a display artefact,
;; rebuilt from the TEI whenever you like; the TEI stays the edition.
;;
;;   * `xml:lang="grc"' becomes `lang="greek"'.  This one is not
;;     cosmetic.  `diogenes--dict-handle-elt' reads the attribute `lang'
;;     and defaults to "english"; nothing in Diogenes looks at `xml:lang'.
;;     Left alone, every Greek word in a Bailly entry -- and the headword
;;     itself -- would count as English, and `C-c C-c' on one would go to
;;     Lewis & Short instead of the LSJ.
;;
;;   * <orth> becomes <head>, keeping its attributes, as in Pape.  That is
;;     the element the formatter draws as a headword and hangs the `orth'
;;     text property on, which is what makes the print-dictionary keys act
;;     on the entry the cursor is in.
;;
;;   * <etym> becomes <sense n="Étym.">, and <re type="variant"> becomes
;;     <sense n="➳">.  The formatter gives <sense> a blank line and prints
;;     its `n' as a label, which is exactly how Bailly sets an etymology
;;     and a list of dialect forms off from the article; as bare elements
;;     they would have run on into the last sense unlabelled.  The label
;;     the TEI drops -- the printed "Étym." -- comes back here.
;;
;;   * <bibl> becomes <cit>.  The shared <bibl> handler builds a clickable
;;     citation from an `n' attribute holding a Perseus reference, and
;;     Bailly's sigla are not that: "PLUT. T. Gracch. 5" is resolved by a
;;     bibliography (biblio.2020) distributed apart from the dictionary, so
;;     an <bibl> here would be a link with nothing behind it, and clicking
;;     it would fail inside `diogenes--lookup-parse-bibl-string'.  Its
;;     <author> and <biblScope> keep their own faces, so a citation still
;;     looks like one.  Should the sigla ever be resolved, the place to
;;     undo this is `diogenes-bailly--rewrite-entry'.
;;
;; ---------------------------------------------------------------------
;; COLLATION
;; ---------------------------------------------------------------------
;;
;; `diogenes-bailly--key' has one job the other Greek dictionaries do not:
;; Bailly prints medial beta as "ϐ" (U+03D0), in 6,209 of its headwords.
;; That character is in no beta-code table, so `diogenes--utf8-to-beta'
;; passes it through untranslated and the filter to beta letters then drops
;; it -- ἀϐαρής would be filed under "aarhs", where nothing will ever look
;; for it.  So it folds to β first, together with the other variant shapes
;; (ς, ϑ, ϕ, ϰ, ϱ, ϖ), exactly as `diogenes-bailly-pdf--key' folds them for
;; the printed page.
;;
;; The rest of what a Bailly headword can carry, measured over all 110,646
;; of them: 1,548 superscript homograph numerals (ἤ ¹, ἤ ²) and the space
;; before them; 60 apostrophes of elision; 38 en dashes on prefix and
;; suffix entries (βου–, -δις); 26 parentheses; 7 asterisks of conjecture;
;; 35 no-break spaces.  All of them drop out.  Three headwords are simply
;; mis-spelt in the source, each once, and each would otherwise be
;; unreachable: a Coptic kapa for κ in θαλίηⲕτρον, a Latin o for ο in
;; συστράτηγoς, and a byte-order mark left on the end of λευκερῴδιος.
;; They are folded here rather than corrected in the TEI, which is under a
;; no-derivatives licence and is not ours to emend.
;;
;; Digamma (ϝέ, ϝέθεν, ϝοῖ) is beta code `v', which sorts between ε and ζ
;; in `diogenes--beta-code-alphabet'; since no table transliterates it,
;; this module spells it out itself.
;;
;; The result: no headword keys to nothing, and 7,332 of them share a key
;; with another -- the numbered homographs, ἤ ¹ against ἤ ², which no
;; accent-blind key could separate and which Bailly means as one word
;; anyway.  They stay in printed order, because `sort' on a list is stable,
;; and `C-c C-n' walks from one to the next.

;;; Code:
(require 'cl-lib)
(require 'seq)
(require 'subr-x)
(require 'ucs-normalize)
(require 'diogenes-dict-faces)
(require 'diogenes-lisp-utils)          ; diogenes--path-usable-p

(declare-function diogenes--search-dict "diogenes-perseus"
                  (word lang sort-fn key-fn &optional file))
(declare-function diogenes--beta-sort-function "diogenes-perseus" (a b))
(declare-function diogenes--xml-key-fn "diogenes-perseus" (buf))
(declare-function diogenes--binary-search "diogenes-perseus"
                  (dict-file comp-fn key-fn word &optional start stop))
(declare-function diogenes--lookup-current-headword "diogenes-perseus" ())
(declare-function diogenes--lookup-assert-lang "diogenes-perseus"
                  (expected dict-name))
(declare-function diogenes--perseus-path "diogenes" ())
(declare-function diogenes--utf8-to-beta "diogenes-utils" (str))
(declare-function diogenes--perseus-beta-to-utf8 "diogenes-utils" (str))
(declare-function diogenes-lookup-register-dictionary "diogenes-perseus"
                  (id &rest keys))
(declare-function diogenes-lookup-open-bailly-pdf "diogenes-bailly-pdf"
                  (&optional word))
(declare-function diogenes-bailly-pdf-available-p "diogenes-bailly-pdf" ())

(defvar diogenes--lookup-file)
(defvar diogenes--lookup-same-window)
(defvar diogenes--dict-xml-handlers-extra)

;;;; --------------------------------------------------------------------
;;;; CUSTOMIZATION
;;;; --------------------------------------------------------------------

(defcustom diogenes-bailly-file nil
  "Path to the converted Bailly dictionary, one entry per line.
Nil means `bailly.xml' among the other Diogenes dictionaries, which is
where \\[diogenes-bailly-build-dictionary] writes it -- and where, on many
installations, it cannot: that directory lives inside the Diogenes tree and
is commonly owned by root.  Name a path you can write instead, as for
Pape:

    (setq diogenes-bailly-file \"~/.emacs.d/diogenes/bailly.xml\")

Missing directories are created.  This is NOT the TEI you converted from --
see `diogenes-bailly-source-file'."
  :type '(choice (const :tag "bailly.xml beside the other dictionaries" nil)
                 file)
  :group 'diogenes)

(defcustom diogenes-bailly-source-file nil
  "Where the Bailly TEI XML lives.
Read by \\[diogenes-bailly-build-dictionary] to produce
`diogenes-bailly-file'; not used for lookups afterwards, so it may live
anywhere and be deleted once converted.

May be any of three things: a single XML file, a DIRECTORY (every *.xml in
it is read, in `string<' order of file name), or an explicit list of files.
All of them go into the one converted dictionary."
  :type '(choice (const :tag "Not set" nil)
                 (file :tag "Single XML file")
                 (directory :tag "Directory of XML files")
                 (repeat :tag "List of XML files" file))
  :group 'diogenes)

(defcustom diogenes-bailly-display-in-same-window t
  "Whether a Bailly entry replaces the entry it was called from.
Non-nil reuses the window, as a dictionary consulted about the entry in
front of you should; nil opens it as `display-buffer' sees fit.

Either way this applies only when there IS an entry in front of you --
when the lookup was made from a lookup buffer.  Asked for from a browser,
or from anywhere else, the entry never takes the window it was called
from: the text being read would be the thing replaced.  Where it goes
then is `display-buffer''s to decide, which is what `pop-up-frames' and
`diogenes-purpose' are for.

Left as it is, and not folded into `diogenes-window-behaviour\=': this says
whether THIS dictionary replaces the entry it was consulted from, which is a
different question from where a lookup goes in general.  It applies only from
a lookup buffer -- asked for from a browser, an entry never takes the window
the text is in -- and where it says nil, `diogenes-lookup-display-action\=' and
`diogenes-window-behaviour\=' decide as they do for anything else."
  :type 'boolean
  :group 'diogenes)

;;;; --------------------------------------------------------------------
;;;; FORMATTING OF BAILLY'S OWN ELEMENTS
;;;; --------------------------------------------------------------------

(defconst diogenes-bailly--xml-handlers
  '()
  "Faces peculiar to Bailly, over and above `diogenes-dict-tei-faces'.
Empty: every element Bailly uses -- <gram>, <pron>, <author>, <biblScope>,
<mentioned> -- is shared with Gaffiot and Georges and coloured for all of
them in `diogenes-dict-faces.el'.  Kept so a Bailly-only element has
somewhere to go.")

(defun diogenes-bailly--install-xml-handlers ()
  "Teach the dictionary formatter about Bailly's elements.  Idempotent."
  (dolist (handler diogenes-bailly--xml-handlers)
    (unless (assq (car handler) diogenes--dict-xml-handlers-extra)
      (push handler diogenes--dict-xml-handlers-extra)))
  (diogenes-dict-install-faces))

;;;; --------------------------------------------------------------------
;;;; THE KEY A HEADWORD SORTS UNDER
;;;; --------------------------------------------------------------------

(defconst diogenes-bailly--beta-letters "abgdevzhqiklmncoprstufxyw"
  "The letters a beta-code key may consist of, and nothing else.
`diogenes--beta-sort-function' looks every character up in
`diogenes--beta-code-alphabet' and SIGNALS on one it does not find, so a
stray Latin letter in a key would not merely sort oddly but break every
search that walked past it.  Hence a key is filtered down to these, in
this order (alpha beta gamma delta epsilon digamma zeta eta theta ...),
which is the order Greek sorts in and not the order ASCII does.")

(defconst diogenes-bailly--letter-folds
  '((?ϐ . ?β)                     ; U+03D0 medial beta -- 6,209 headwords
    (?ς . ?σ) (?ϑ . ?θ) (?ϕ . ?φ) (?ϰ . ?κ) (?ϱ . ?ρ) (?ϖ . ?π)
    (?ϴ . ?θ) (?ϒ . ?υ)
    ;; Three one-off misspellings in the source; see the Commentary.
    (?ⲕ . ?κ)                     ; U+2C95 COPTIC SMALL LETTER KAPA
    (?o . ?ο))                    ; LATIN SMALL LETTER O
  "Alist folding variant and mistaken letter shapes onto a plain Greek letter.
Applied BEFORE transliteration, since `diogenes--utf8-to-beta' knows only
the plain letters and silently leaves anything else for the filter in
`diogenes-bailly--key' to discard.")

(defconst diogenes-bailly--spelt-out
  '((?ϝ . "v") (?Ϝ . "v"))
  "Letters transliterated here because no beta-code table lists them.
Digamma is beta code `v', which `diogenes--beta-code-alphabet' sorts
between epsilon and zeta; three Bailly headwords begin with it.")

(defun diogenes-bailly--prepare (word)
  "Normalise WORD before it is keyed, and return it decomposed.
Converts Perseus beta code to Unicode -- LSJ headwords arrive as e.g.
\"le/gw\", and the translation leaves Greek letters alone, so a headword
with one Latin letter in it survives the trip -- then removes what Bailly
prints around a lemma but does not file it under: the superscript numeral
that distinguishes homographs, the apostrophe of elision, the en dash of a
prefix or suffix entry, parentheses, the asterisk of conjecture, commas
and every kind of space.

Wrapped in `save-match-data': this does its own matching, and a caller
that has just located something with `string-match' would otherwise find
its `match-beginning' quietly redirected here."
  (save-match-data
    (let* ((word (or word ""))
           (word (if (and (fboundp 'diogenes--perseus-beta-to-utf8)
                          (string-match-p "[A-Za-z]" word))
                     (or (diogenes--perseus-beta-to-utf8 word) word)
                   word))
           ;; A headword may offer several forms; the first is the one it
           ;; is filed under.
           (word (or (car (split-string word "[,;]" t "[[:space:]]+")) ""))
           (word (replace-regexp-in-string
                  "[¹²³⁴⁵⁶⁷⁸⁹'’ʼ´`()*\ufeff\u00a0[:space:]–—-]" "" word)))
      (ucs-normalize-NFD-string word))))

(defun diogenes-bailly--key (headword)
  "Return the beta-code key HEADWORD is filed under.
`diogenes--beta-sort-function' compares keys after discarding everything
but ASCII letters, so a key must survive that: the headword is normalised
by `diogenes-bailly--prepare', its variant letter shapes folded (ϐ to β
above all -- see the Commentary), its diacritics dropped with the
combining marks NFD decomposition exposes, and what is left transliterated
into beta code and filtered down to `diogenes-bailly--beta-letters'.

Returns the empty string for a word with no Greek in it, which the caller
is expected to refuse rather than search for."
  (let ((out nil))
    (dolist (c (string-to-list (diogenes-bailly--prepare headword)))
      (unless (<= #x0300 c #x036f)                 ; combining marks
        (let* ((c (downcase c))
               (spelt (cdr (assq c diogenes-bailly--spelt-out))))
          (if spelt
              (dolist (l (string-to-list spelt)) (push l out))
            (let ((folded (or (cdr (assq c diogenes-bailly--letter-folds)) c)))
              (dolist (b (string-to-list
                          (downcase (diogenes--utf8-to-beta (string folded)))))
                (when (cl-find b diogenes-bailly--beta-letters)
                  (push b out))))))))
    (apply #'string (nreverse out))))

(defun diogenes-bailly--key< (a b)
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

(defun diogenes-bailly--dictionary-file ()
  "Return the path of the converted dictionary, whether or not it exists."
  (or diogenes-bailly-file
      (file-name-concat (diogenes--perseus-path) "bailly.xml")))

(defun diogenes-bailly--nearest-existing-directory (dir)
  "Return the innermost existing directory at or above DIR.
The target directory is created on demand, so it is its nearest existing
ancestor whose writability decides whether the build can finish."
  (let ((dir (directory-file-name (expand-file-name dir))))
    (while (and (not (file-directory-p dir))
                (not (string= dir (directory-file-name
                                   (file-name-directory dir)))))
      (setq dir (directory-file-name (file-name-directory dir))))
    dir))

(defun diogenes-bailly--assert-writable (target)
  "Signal a user-error unless TARGET can be written.
Asked BEFORE anything is converted.  The default location is inside the
Diogenes installation, which is usually owned by root, and the conversion
takes a minute or two over 86 MB of TEI: finding out at the end, with the
sorted result thrown away and only `Permission denied' to explain it, is a
poor trade for one call to `file-writable-p'."
  (unless (if (file-exists-p target)
              (file-writable-p target)
            (file-writable-p (diogenes-bailly--nearest-existing-directory
                              (file-name-directory target))))
    (user-error "Cannot write %s -- no permission.  Set \
`diogenes-bailly-file' to a path you own, e.g. (setq diogenes-bailly-file \
\"~/.emacs.d/diogenes/bailly.xml\")"
                (abbreviate-file-name target))))

(defun diogenes-bailly--source-files (&optional source)
  "Return the list of TEI files to convert.
SOURCE defaults to `diogenes-bailly-source-file' and may be a file, a
directory, or a list of files; see that variable.  Signals if it names
nothing readable, since the alternative is a silently empty dictionary."
  (let ((source (or source diogenes-bailly-source-file)))
    (cond
     ((null source) nil)
     ((consp source)
      (or (seq-filter #'file-readable-p source)
          (user-error "None of the files in `diogenes-bailly-source-file' \
can be read")))
     ((file-directory-p source)
      (or (directory-files source t "\\.xml\\'" nil)
          (user-error "No .xml files in %s" (abbreviate-file-name source))))
     ((file-readable-p source) (list source))
     (t (user-error "Cannot read the Bailly source at %s"
                    (abbreviate-file-name source))))))

(defconst diogenes-bailly--quantity-marks
  "\u0304\u0306\u00af\u02d8\u1fb0\u1fb1\u1fd0\u1fd1\u1fe0\u1fe1"
  "The marks of vowel quantity that may trail a Bailly headword.
Bailly gives the quantity of a doubtful vowel after the word rather than on
it -- \u1f31\u03c3\u03c4\u03b7\u03bc\u03b9 then a breve, the breve belonging to the iota of the headword
and not to what comes after.  Combining macron and breve, their spacing
equivalents, and the precomposed Greek vowels that carry one.")

(defun diogenes-bailly--head-and-rest (rest)
  "Split REST, what follows a headword, into (ATTACH SPACE REMAINDER).
ATTACH is the run of quantity marks that belongs to the headword and goes
inside its <head>; SPACE says whether a space is then wanted; REMAINDER is
the rest of the entry.

The <head> replaces <orth> where it stood, and Bailly follows a headword
directly with its grammar, so without this the two are rendered run
together: `\u1f31\u03c3\u03c4\u03b7\u03bc\u03b9\u1fb0(au sens tr.\='.  Two separate things are wrong there.
The breve wants to stay with the headword whose vowel it measures, and the
parenthesis wants a space before it.

A space is wanted before anything except clause punctuation -- a comma,
semicolon, colon or full stop, or a closing bracket -- and except where
there is a space already.  Tags are looked through to decide, the
separation that matters being the one the reader sees rather than the one in
the markup."
  (let* ((marks (concat "[" diogenes-bailly--quantity-marks "]+"))
	 (attach (if (string-match (concat "\\`" marks) (or rest ""))
		     (match-string 0 rest)
		   ""))
	 (remainder (substring (or rest "") (length attach)))
	 (plain (replace-regexp-in-string "<[^>]*>" "" remainder))
	 (first (and (> (length plain) 0) (aref plain 0))))
    (list attach
	  ;; A regexp rather than a list of character literals: `?\;' and
	  ;; `?\)' are correct Lisp and a nuisance to read.
	  (and first
	       (not (string-match-p "\\`[,;.:!?)]}[:space:]]" plain)))
	  remainder)))

(defun diogenes-bailly--rewrite-entry (body)
  "Return BODY, the inside of one TEI <entry>, as the formatter wants it.
The rewritings the Commentary describes: `xml:lang=\"grc\"' becomes the
`lang=\"greek\"' that `diogenes--dict-handle-elt' actually reads, <etym>
and <re type=\"variant\"> become labelled <sense>s so they are set off from
the article as the print sets them off, and <bibl> becomes <cit> so that a
citation Diogenes cannot resolve is not drawn as a link that fails when
clicked.

And <pron notation=\"prosody\"> is bracketed.  Bailly gives the quantity of
a doubtful vowel in an element of its own, after the headword and after any
form whose measure is in question -- 37 845 of them in this dictionary --
and with the element drawn as bare text it ran into whatever followed:
\u1f31\u03c3\u03c4\u03b7\u03bc\u03b9 then a breve then `(au sens tr.\=', with nothing to say that the breve
measured the iota of the headword rather than beginning the grammar.  In
brackets it reads as the dictionary means it, and as the dictionary itself
sets the same note further down the article: `\u03c3\u03c4\u03b1\u03b8\u03ae\u03c3\u03bf\u03bc\u03b1\u03b9 [\u1fb0]\='.

<orth> is NOT renamed here: `diogenes-bailly--convert-buffer' does that,
having found it already while reading the headword out."
  (let ((body body))
    (setq body (replace-regexp-in-string
                "xml:lang=\"grc\"" "lang=\"greek\"" body t t))
    (setq body (replace-regexp-in-string
                "xml:lang=\"fr\"" "lang=\"french\"" body t t))
    ;; The etymology and the dialect forms, labelled as Bailly labels them.
    (setq body (replace-regexp-in-string
                "<etym>" "<sense n=\"Étym.\">" body t t))
    (setq body (replace-regexp-in-string "</etym>" "</sense>" body t t))
    (setq body (replace-regexp-in-string
                "<re type=\"variant\">" "<sense n=\"➳\">" body t t))
    (setq body (replace-regexp-in-string "</re>" "</sense>" body t t))
    ;; Prosody: bracketed, and set off by a space from whatever precedes
    ;; it, which is a headword or a form.  The brackets are the
    ;; dictionary's own for this note; a <pron> left as text abuts what
    ;; follows and reads as part of it.
    (setq body (replace-regexp-in-string
                "<pron\\(?:[[:space:]][^>]*\\)?>[[:space:]]*"
                " [" body t))
    (setq body (replace-regexp-in-string "[[:space:]]*</pron>" "]" body t))
    ;; The form group and the grammar that follows it are adjacent in the
    ;; source and both render inline, so `</form><gramGrp>' comes out as
    ;; \u1f31\u03c3\u03c4\u03b7\u03bc\u03b9 run into `(au sens tr.\=' -- with or without a prosody note
    ;; between them.  One space at that boundary, which is where the
    ;; headword ends and the article begins.
    (setq body (replace-regexp-in-string
                "</form>[[:space:]]*<gramGrp" "</form> <gramGrp" body t))
    ;; Citations: a face, not a dead link.
    (setq body (replace-regexp-in-string "<bibl>" "<cit>" body t t))
    (setq body (replace-regexp-in-string "</bibl>" "</cit>" body t t))
    ;; <hi rend="..."> becomes i / b / sc / sup, so that italic, bold and
    ;; small capitals can be told apart by the face table, which sees
    ;; element names only.
    (diogenes-dict-flatten-hi body)))

(defun diogenes-bailly--convert-buffer ()
  "Convert the TEI in the current buffer to a list of (KEY . LINE).
Point is left at the end.  Returns (ENTRIES . SKIPPED), the entries in the
order the file gives them.

Each <entry> becomes one line: its <orth> is renamed <head> -- keeping its
attributes, so the headword carries a language and `C-c C-c' on it
searches Greek -- the rest is rewritten by
`diogenes-bailly--rewrite-entry', newlines are folded to spaces so the
line-oriented binary search stays line-oriented, and a fresh `key' is put
on the opening tag.  The key goes on a tag of our own writing because
`diogenes--xml-key-fn' takes the FIRST `key=' it finds in the line, and
an <entry> may already carry attributes of its own."
  (let ((rows nil)
        (skipped 0))
    (goto-char (point-min))
    (while (re-search-forward "<entry\\(?:[[:space:]][^>]*\\)?>" nil t)
      (let ((start (point))
            (end (save-excursion
                   (when (search-forward "</entry>" nil t)
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
                     (key (diogenes-bailly--key plain))
                     (split (diogenes-bailly--head-and-rest
                             (substring body orth-end)))
                     (line (concat (substring body 0 orth-start)
                                   "<head" attrs ">" orth (nth 0 split)
                                   "</head>"
                                   (if (nth 1 split) " " "")
                                   (nth 2 split))))
                (if (string-empty-p key)
                    (cl-incf skipped)
                  (setq line (diogenes-bailly--rewrite-entry line))
                  (setq line (replace-regexp-in-string
                              "[[:space:]]*\n[[:space:]]*" " " line))
                  (push (cons key (format "<entry key=\"%s\">%s</entry>"
                                          key (string-trim line)))
                        rows))))))))
    (cons (nreverse rows) skipped)))

;;;###autoload
(defun diogenes-bailly-build-dictionary (&optional source target)
  "Convert the Bailly TEI XML into a dictionary Diogenes can search.
SOURCE defaults to `diogenes-bailly-source-file' -- a file, a directory of
per-letter files, or a list -- and TARGET to `diogenes-bailly-file'.  Each
<entry> becomes one line, keyed in beta code by `diogenes-bailly--key' and
sorted in Greek alphabetical order; see `diogenes-bailly--convert-buffer'
for what else the conversion does.  Entries keep their printed order
within a key, so numbered homographs stay in the sequence Bailly prints
them in.

Run once, after setting `diogenes-bailly-source-file'.  The full
dictionary is some 110,000 entries over 86 MB of TEI and takes a minute or
two."
  (interactive)
  (let* ((sources (or (diogenes-bailly--source-files source)
                      (list (read-file-name "Bailly TEI XML (or directory): "
                                            nil nil t))))
         (sources (diogenes-bailly--source-files sources))
         (target (or target (diogenes-bailly--dictionary-file)))
         (rows nil)
         (skipped 0))
    (dolist (file sources)
      (when (and (file-exists-p target)
                 (string= (file-truename file) (file-truename target)))
        (user-error "Refusing to convert %s onto itself: \
`diogenes-bailly-file' must differ from `diogenes-bailly-source-file'"
                    (abbreviate-file-name file))))
    (diogenes-bailly--assert-writable target)
    (dolist (file sources)
      (message "Converting %s ..." (file-name-nondirectory file))
      (with-temp-buffer
        (insert-file-contents file)
        (let ((result (diogenes-bailly--convert-buffer)))
          (setq rows (nconc rows (car result)))
          (cl-incf skipped (cdr result)))))
    (unless rows
      (user-error "Found no entries in %s: is this the Bailly TEI?"
                  (mapconcat #'file-name-nondirectory sources ", ")))
    ;; `sort' on a list is stable, so entries sharing a key keep the order
    ;; the dictionary prints them in -- and, across per-letter files, the
    ;; order the letters were read in.
    (message "Sorting %d entries ..." (length rows))
    (setq rows (sort rows (lambda (a b) (diogenes-bailly--key< (car a) (car b)))))
    (make-directory (file-name-directory target) t)
    (let ((coding-system-for-write 'utf-8))
      (with-temp-file target
        (dolist (row rows)
          (insert (cdr row) "\n"))))
    (message "Bailly: wrote %d entries (%s-%s) from %d file(s) to %s%s"
             (length rows) (car (car rows)) (car (car (last rows)))
             (length sources)
             (abbreviate-file-name target)
             (if (zerop skipped) "" (format "; skipped %d" skipped)))
    target))

;;;; --------------------------------------------------------------------
;;;; THE LOOKUP
;;;; --------------------------------------------------------------------

(defun diogenes-bailly--assert-converted (file)
  "Signal a user-error unless FILE is a converted Bailly dictionary.
The lookup wants one entry per line, each with a `key' attribute; handed
the TEI file instead it would fail deep inside `diogenes--xml-key-fn' with
an unhelpful message.  `diogenes-bailly-file' is the CONVERTED file; the
TEI belongs in `diogenes-bailly-source-file'."
  (with-temp-buffer
    (insert-file-contents file nil 0 400)
    (goto-char (point-min))
    (unless (looking-at "<entry[^>]*[[:space:]]key=\"")
      (user-error "%s is not a converted Bailly dictionary (no key= on its \
first entry).  If this is the TEI file, set it as \
`diogenes-bailly-source-file' instead and run \
M-x diogenes-bailly-build-dictionary"
                  (abbreviate-file-name file)))))

;;;###autoload
(defun diogenes-bailly-xml-available-p ()
  "Non-nil if Bailly's XML is here, or could be built without asking twice.
True when the converted dictionary exists, and also when it does not but
`diogenes-bailly-source-file' names TEI that is there -- because then
pressing `B' offers to build it.  Never signals: `diogenes-path' may itself
be unset, and this is asked while an entry is being drawn."
  (let ((file (ignore-errors (diogenes-bailly--dictionary-file))))
    (or (and file (file-readable-p file))
        (diogenes--source-set-p diogenes-bailly-source-file))))

;;;###autoload
(defun diogenes-bailly-available-p ()
  "Non-nil if Bailly can be reached at all, as XML or as a printed page.
Either half is enough, `diogenes-lookup-bailly' dispatching on which is
actually there: with the XML converted the link opens the entry, with only
`diogenes-bailly-pdf-file' set it opens the page instead, as the OLD and
Montanari do.  With neither the link is not offered."
  (or (diogenes-bailly-xml-available-p)
      (and (require 'diogenes-bailly-pdf nil t)
           (diogenes-bailly-pdf-available-p))))

(defun diogenes-bailly--file ()
  "Return the converted dictionary file, building it if the user agrees.
Signals rather than returning nil when there is nothing to search: unlike
Gaffiot, whose TEI covers only part of the alphabet and whose PDF is
therefore a genuine alternative, Bailly's XML is the whole dictionary.  A
missing dictionary is the end of the road, and the error may as well say
how to fix it."
  (let ((file (diogenes-bailly--dictionary-file)))
    (cond
     ((file-readable-p file)
      (diogenes-bailly--assert-converted file)
      file)
     ((and diogenes-bailly-source-file
           (y-or-n-p (format "Bailly is not converted yet; build %s now? "
                             (abbreviate-file-name file))))
      (diogenes-bailly-build-dictionary diogenes-bailly-source-file file))
     (t
      (user-error "Bailly is not set up yet: set `diogenes-bailly-source-file' \
to the TEI XML (a file, or the directory holding the per-letter files) and \
run M-x diogenes-bailly-build-dictionary.  Either in your init file before \
Diogenes loads, or through M-x customize-variable")))))

(defun diogenes-bailly-lookup-buffer-p ()
  "Non-nil if the current lookup buffer is showing Bailly.
Read from the buffer-local `diogenes--lookup-file', which records the
dictionary the entries were read from.  Used by
`diogenes--lookup-insert-dict-links' to offer \"[Bailly (B)]\" in an LSJ or
Pape entry and \"[PDF (B)]\" here, so the link always leads somewhere you
are not; and by `diogenes-lookup-bailly', so that `B' pressed inside a
Bailly entry opens the printed page instead of looking the word up again."
  (and (boundp 'diogenes--lookup-file)
       diogenes--lookup-file
       (let ((bailly (diogenes-bailly--dictionary-file)))
         (and (file-exists-p bailly)
              (file-exists-p diogenes--lookup-file)
              (string= (file-truename diogenes--lookup-file)
                       (file-truename bailly))))))

;;;###autoload
(defun diogenes-lookup-bailly (&optional word)
  "Show Bailly's entry for WORD in a Diogenes lookup buffer.
Interactively, WORD defaults to the headword of the Greek entry at point;
with a prefix argument, prompt for it.  The entry behaves like any other
lookup: `C-c C-n' and `C-c C-p' walk the dictionary, `C-c C-c' on a Greek
word returns to the LSJ, and the print-dictionary banner opens Montanari,
the CGL, BDAG, Passow and the TGL.

Bailly's XML is complete -- it is the whole of the Bailly 2020 edition, the
same text its PDF prints -- so there is no coverage to check: a word that
is not in it produces the nearest entry, with a message saying so, exactly
as the LSJ does.

With only `diogenes-bailly-pdf-file' set and no XML converted, Bailly is
simply a print dictionary like the OLD, and this command opens the page
rather than explaining what is not installed.  Where the XML IS there, this
command never opens the PDF except in the case below.

Pressed a second time, from INSIDE the entry it has just shown, it opens
that word's page in the printed Bailly instead -- see
`diogenes-lookup-open-bailly-pdf' and `diogenes-bailly-pdf-file'.  That is
the only way to the PDF, and `C-u B' looks another word up in the XML from
there.

Requires either a converted dictionary file (see
\\[diogenes-bailly-build-dictionary]) or a PDF of the printed edition."
  (interactive
   (progn
     (diogenes--lookup-assert-lang "greek" "Bailly")
     (list (if current-prefix-arg
               (read-string "Look up in Bailly: ")
             (diogenes--lookup-current-headword)))))
  ;; Already reading Bailly: this key's other job is the printed page.
  ;; Checked here rather than in the `interactive' form so that the link in
  ;; the banner, which calls us with a word, dispatches the same way.
  (if (and (null current-prefix-arg) (diogenes-bailly-lookup-buffer-p))
      (if (and (require 'diogenes-bailly-pdf nil t)
               (diogenes-bailly-pdf-available-p))
          (diogenes-lookup-open-bailly-pdf word)
        (user-error "This entry is Bailly already; set \
`diogenes-bailly-pdf-file' to reach the printed page from here, `l' returns \
to the LSJ, `C-u B' looks up another word here"))
    (let ((word (string-trim (or word (diogenes--lookup-current-headword)))))
      (cond
       ;; No XML, and none to build: whatever Bailly the user has is the
       ;; printed one, so send the word there instead of asking for a TEI
       ;; file that is not wanted.
       ((not (diogenes-bailly-xml-available-p))
        (if (and (require 'diogenes-bailly-pdf nil t)
                 (diogenes-bailly-pdf-available-p))
            (diogenes-lookup-open-bailly-pdf word)
          ;; Neither half configured: let `diogenes-bailly--file' say so,
          ;; rather than repeating its message here.
          (diogenes-bailly--file)))
       (t
        (let ((file (diogenes-bailly--file))
              (key (diogenes-bailly--key word)))
          (when (string-empty-p key)
            (user-error "Nothing to look up in \"%s\"" word))
          (let ((diogenes--lookup-same-window
                 (and diogenes-bailly-display-in-same-window
                      (derived-mode-p 'diogenes-lookup-mode))))
            (diogenes--search-dict key "greek"
                                   #'diogenes--beta-sort-function
                                   #'diogenes--xml-key-fn
                                   file))))))))

;;;; --------------------------------------------------------------------
;;;; REGISTRATION
;;;; --------------------------------------------------------------------

(defconst diogenes-bailly--declared-at-load (diogenes--declared-at-load-p)
  "Whether Bailly was asked for, rather than bundled with the rest.
Computed when this file is read: a `require' in an init file means the
user wants this dictionary, and it is then offered whatever its paths
say.  See `diogenes--loading-bundle'.")

(defun diogenes-bailly--register ()
  "Announce Bailly to the lookup banner.  Idempotent.
`:show unless-current' keeps the link out of a Bailly entry, where its
place is taken by \"[PDF (B)]\" -- registered by `diogenes-bailly-pdf.el',
which is also what makes the printed page unreachable from anywhere else.
`:bind t' puts `B' on `diogenes-lookup-bailly': the key is Greek-only, so
it needs no language dispatcher of the kind `P' and `l' have."
  (diogenes-lookup-register-dictionary
   'bailly :lang "greek" :name "Bailly" :key "B" :order 70
   :command #'diogenes-lookup-bailly
   :show 'unless-current
   :buffer-p #'diogenes-bailly-lookup-buffer-p
   :available-p #'diogenes-bailly-available-p
   :declared diogenes-bailly--declared-at-load
   :paths '(diogenes-bailly-file diogenes-bailly-source-file diogenes-bailly-pdf-file)
   :bind t
   :help "Show Bailly's entry for \"%s\""))

(with-eval-after-load 'diogenes-perseus
  (diogenes-bailly--install-xml-handlers)
  (diogenes-bailly--register))

(provide 'diogenes-bailly)
;;; diogenes-bailly.el ends here
