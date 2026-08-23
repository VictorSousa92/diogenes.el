;;; diogenes-dge.el --- Look up a Greek word in the DGE -*- lexical-binding: t -*-

;;; Commentary:

;; Show the entry of the _Diccionario Griego-Español_ (Madrid: CSIC,
;; 1980- ), the Greek-Spanish dictionary of the Instituto de Lenguas y
;; Culturas del Mediterráneo y Oriente Próximo, for the Greek word you are
;; reading -- in a Diogenes lookup buffer, not a PDF.  From a Greek entry
;; (LSJ), press `d' or click the "[DGE]" link.
;;
;; ---------------------------------------------------------------------
;; WHAT THIS IS, AND WHAT IT IS NOT
;; ---------------------------------------------------------------------
;;
;; This is a sibling of `diogenes-pape.el' and `diogenes-bailly.el', and it
;; works the same way: the DGE comes as TEI XML, entry by entry, exactly the
;; kind of thing `diogenes-lookup-mode' already displays for the LSJ and
;; Lewis & Short, so this module adds no display machinery of its own.  It
;; hands the DGE to `diogenes--search-dict' as one more dictionary file, and
;; everything the lookup buffer can do comes with it --
;;
;;   * `C-c C-n' / `C-c C-p' walk to the next and previous entry;
;;   * `C-c C-c' on a word looks it up: Greek goes to the LSJ, so you can
;;     step from the DGE back into the electronic Greek dictionary, and the
;;     Latin the DGE quotes goes to Lewis & Short.  The Spanish of the
;;     definitions is tagged as Spanish and is left alone, as Pape's German
;;     is;
;;   * the print dictionaries are one keystroke away, since the entry
;;     carries the usual "[Montanari] [CGL] [BDAG] [Passow] [TGL]" banner;
;;   * every entry opens in a fresh buffer, so the LSJ entry you came from
;;     stays live and reachable.
;;
;; It is NOT one of the print-dictionary modules.  `diogenes-passow.el' and
;; its siblings jump a scanned PDF to a page; there is no PDF here, and no
;; provision for one.  Unlike Bailly and Gaffiot, the DGE has no freely
;; available scan to fall back on -- what the CSIC publishes for nothing is
;; exactly this XML -- so a word the XML does not have is the end of the
;; road, and the module's business is to say which kind of "does not have"
;; it is.  There are two, and they are not alike:
;;
;;   * A GAP.  The word falls inside the range the volumes cover and the
;;     DGE simply has no article for it.  Diogenes then does what it does
;;     for the LSJ -- shows the nearest entry and says so -- which for a
;;     dictionary this dense is information rather than a failure.
;;
;;   * BEYOND THE PUBLISHED VOLUMES.  The DGE is unfinished.  Eight volumes
;;     have appeared and they reach ἐπισκήπτω; ζέω, νόμος and ὕβρις are not
;;     missing but unwritten, and there is nothing to show.  Left to the
;;     binary search, asking for one of them would produce the last entry
;;     of vol. VIII with "showing nearest entry" -- indistinguishable from a
;;     near miss on a word that really is absent.  So the range is checked
;;     first and refused with a message that names the boundary; see
;;     `diogenes-dge-check-coverage'.
;;
;; The boundary is READ FROM THE DICTIONARY, never hard-coded: it is the key
;; of the last entry in the converted file.  Add vol. IX and rebuild, and
;; the coverage grows by itself.  (The advertised range of vol. VIII ends at
;; ἐπισκήνωσις, but the file carries one entry past it, ἐπισκήπτω.  Another
;; reason not to hard-code it.)
;;
;; ---------------------------------------------------------------------
;; THE DICTIONARY FILE
;; ---------------------------------------------------------------------
;;
;; Diogenes looks a word up by binary search over a file of ONE ENTRY PER
;; LINE, sorted by a `key' attribute (see `diogenes--binary-search').  For
;; Greek that key is beta code, sorted in the order of the Greek alphabet
;; rather than of ASCII -- see `diogenes--beta-sort-function' -- and the DGE
;; TEI has Unicode headwords full of accents, quantities and editorial
;; sigla, spread over one document per volume.  So it has to be converted
;; once:
;;
;;   (setq diogenes-dge-source-file "/path/to/xdge_xml")   ; or one file
;;   M-x diogenes-dge-build-dictionary
;;
;; which writes `dge.xml' beside the other Diogenes dictionaries.  Offered
;; automatically the first time you press `d' with no dictionary file
;; present.
;;
;; The TEI is at https://github.com/dge-csic/xdge_xml, one file per volume
;; (xdge1.xml ... xdge8.xml), and all of them belong in one converted
;; dictionary, so `diogenes-dge-source-file' may name a single XML file, a
;; DIRECTORY of them, or a list.  Point it at the clone and it will read
;; them in file-name order.  The dictionary is CC BY-NC-SA 3.0 ES: free to
;; convert and to read, not to sell.
;;
;; ---------------------------------------------------------------------
;; WHAT THE CONVERSION REWRITES, AND WHY
;; ---------------------------------------------------------------------
;;
;; The converted file is a display artefact, rebuilt from the TEI whenever
;; you like; the TEI stays the edition.  Seven rewritings, none of them
;; cosmetic:
;;
;;   * `xml:lang="grc"' becomes `lang="greek"', `"spa"' becomes
;;     `lang="spanish"', `"lat"' becomes `lang="latin"'.
;;     `diogenes--dict-handle-elt' reads the attribute `lang' and defaults
;;     to "english"; nothing in Diogenes looks at `xml:lang'.  Left alone,
;;     every Greek word in a DGE entry -- and the headword itself -- would
;;     count as English, and `C-c C-c' on one would go to Lewis & Short
;;     instead of the LSJ.
;;
;;   * <orth type="lemma"> becomes <head>, as in Pape and Bailly.  That is
;;     the element the formatter draws as a headword and hangs the `orth'
;;     text property on, which is what makes the print-dictionary keys act
;;     on the entry the cursor is in.  It gains `lang="greek"', which the
;;     DGE does not put on it.
;;
;;   * <bibl> becomes <cit>.  The shared <bibl> handler builds a clickable
;;     citation out of an `n' attribute holding a Perseus reference, and the
;;     DGE's 405,561 citations have no such attribute: every one of them
;;     would be drawn as a link with nothing behind it, and clicking one
;;     would fail inside `diogenes--lookup-parse-bibl-string'.  Their
;;     <author>, <title> and <biblScope> keep their own faces, so a citation
;;     still looks like one.
;;
;;   * A NUMBERED <sense> gives up its <num> child to an `n' attribute:
;;     <sense rend="num"><num>I</num> becomes <sense n="I">.  The formatter
;;     opens a <sense> with a blank line and prints its `n' as a coloured
;;     label, which is how the DGE sets a numbered sense; the number would
;;     otherwise run on into the text as ordinary characters.
;;
;;   * An UNNUMBERED <sense> becomes <seg>.  This is the other half of the
;;     same point, and it matters more.  The DGE uses <sense> for two
;;     different things: 74,944 numbered divisions (A, I, 1, a\)) and 77,769
;;     unnumbered continuations, which the print runs on inside the sense
;;     they belong to after a semicolon -- they even carry the semicolon,
;;     as <pc>.  The shared handler gives every <sense> a blank line, so
;;     left alone they would break each article into twice as many
;;     paragraphs as it has senses, most of them a clause long.  <seg> has
;;     no handler and no face: the text runs on, which is what the print
;;     does with it.
;;
;;   * <etym> is WRAPPED in a labelled <sense>, and kept inside it so that
;;     it keeps its own face.  The DGE sets an etymology off by position
;;     alone, last in the article; in a reflowed paragraph it runs straight
;;     on from the final citation and reads as part of it.  The label is
;;     ours, not the CSIC's -- see `diogenes-dge-etymology-label'.
;;
;;   * <hi> becomes `i' / `sup' by way of `diogenes-dict-flatten-hi', so
;;     that the face table -- which sees element names and not attributes --
;;     can tell emphasis from a superscript.  The DGE writes 29,301 <hi>
;;     with no `rend' at all, which its own stylesheet renders italic, so
;;     those are given `rend="italic"' first; 110 `rend="sub"' lose their
;;     marking and keep their text, Emacs having nowhere to put a subscript.
;;
;; XML comments are dropped -- there are 26, and two of them contain markup
;; and a stray ampersand that would not survive the trip.  The `xml:id' of
;; the entry is kept, since it is the name of the article in the DGE's own
;; system and worth having; the rest of the <entry> attributes go, the
;; formatter having nothing to do with them.
;;
;; ---------------------------------------------------------------------
;; COLLATION
;; ---------------------------------------------------------------------
;;
;; The key comes off the lemma: leading sigla and homograph number dropped
;; (†, *, "1 "), the first word only where a lemma names a phrase,
;; diacritics and quantities gone with the combining marks NFD exposes,
;; everything that is not a Greek letter discarded, and what is left
;; transliterated into beta code and filtered down to the letters
;; `diogenes--beta-sort-function' can sort.
;;
;; Discarding the non-Greek is the step that does the work here, because the
;; DGE writes letters INTO a Greek word from outside the Greek alphabet:
;; digamma, the epigraphic heta (hαγρατέρα), and the transcriptional u̯, y
;; and w of reconstructed forms (Ἀhεριγu̯ος, ἐντροκwατᾱς).  Dropping them is
;; not a shortcut but the DGE's own practice, and it can be read off its
;; pages: Ϝαγανόω is set among ἀγαν-, Ϝέος among ἑο-, hαγρατέρα between
;; Ἀγραστυών and ἀγραυλέω, ἐντροκwατᾱς between ἔντριψις and ἐντρομή.  Every
;; one of them is filed as though the letter were not there.  Sorting all
;; 64,373 keys this way and comparing with the order the volumes print them
;; in leaves 228 disagreements, all of them phrases and homographs.
;;
;; It also settles what to do about a headword arriving from elsewhere.  The
;; LSJ hands over beta code ("a)ba/c"), which has to be read as Greek and
;; not thrown away -- so a word with no Greek in it is converted first, and
;; a word with Greek in it is not.  Testing for LATIN letters instead, as a
;; Latin dictionary may, would send hαγρατέρα through the beta table and
;; file it under eta.
;;
;; Two smaller things the source needs help with:
;;
;;   * PRIVATE-USE CHARACTERS.  The DGE sets epigraphic letterforms in the
;;     private-use area of New Athena Unicode, and 38 lemmas contain one.
;;     They are in no beta-code table, so they would drop out of the key and
;;     file the word a letter short.  What each one stands for can be had
;;     from the DGE itself: the `xml:id' of an entry is the project's own
;;     normalisation of its lemma, and it spells them out -- διαιτατ<E1B4>ρ
;;     is `xml:id="διαιτατερ"'.  Hence
;;     `diogenes-dge-epichoric-substitutions'.  (The editors were no
;;     happier about them than we are; vol. VII carries the comment
;;     "<!-- &#xE1B0; ? -->" beside one.)
;;
;;   * ONE LEMMA IS MISTYPED.  Vol. IV has an entry whose lemma reads
;;     "gelidoτρομερός": the stem was typed with the Latin keymap and the
;;     ending with the Greek one, g-e-l-i-d-o standing on the keys of
;;     γ-ε-λ-ι-δ-ο.  The DGE files it between Γελίας and γελίκη, which is
;;     where γελιδο- belongs and nowhere near where τρομερός would go, so
;;     the reading is not in doubt.  Uncorrected it is the one entry in the
;;     dictionary that sorts outside α-ἐπ, and it would take the coverage
;;     check with it: the last key in the file would be `tromeros', and
;;     every unwritten word from ζ to τ would look as though the DGE
;;     covered it.  Hence `diogenes-dge-key-corrections'.
;;
;; Both are lists you can edit, and both act on the KEY alone.  The entry
;; you read keeps the letters the CSIC published, private-use characters and
;; all -- install New Athena Unicode if you want to see them -- because a
;; converted dictionary may re-file an article but should not silently
;; re-spell it.
;;
;; ---------------------------------------------------------------------
;; ONE WORD OF WARNING ABOUT ἐπί
;; ---------------------------------------------------------------------
;;
;; DGE articles can be enormous -- ἐπί is 431 KB on its own line -- and
;; `diogenes--dict-parse-xml' runs `xml-parse-region', which is Lisp, over
;; the whole of an entry before anything is displayed.  The prepositions and
;; the commonest verbs therefore take a few seconds to open where an
;; ordinary entry is instantaneous.  Nothing is wrong; it is the same parse
;; the LSJ gets, over fifty times the text.

;;; Code:
(require 'cl-lib)
(require 'seq)
(require 'subr-x)
(require 'ucs-normalize)
(require 'diogenes-utils)
(require 'diogenes-dict-faces)

(declare-function diogenes--search-dict "diogenes-perseus"
                  (word lang sort-fn key-fn &optional file))
(declare-function diogenes--beta-sort-function "diogenes-perseus" (a b))
(declare-function diogenes--xml-key-fn "diogenes-perseus" (buf))
(declare-function diogenes--lookup-current-headword "diogenes-perseus" ())
(declare-function diogenes--lookup-assert-lang "diogenes-perseus"
                  (expected dict-name))
(declare-function diogenes-lookup-register-dictionary "diogenes-perseus"
                  (id &rest keys))
(declare-function diogenes--perseus-path "diogenes" ())
(declare-function diogenes--utf8-to-beta "diogenes-utils" (str))
(declare-function diogenes--beta-to-utf8 "diogenes-utils" (str))
(declare-function diogenes--perseus-beta-to-utf8 "diogenes-utils" (str))
(declare-function diogenes-dict-install-faces "diogenes-dict-faces" ())
(declare-function diogenes-dict-flatten-hi "diogenes-dict-faces" (line))

(defvar diogenes--lookup-file)
(defvar diogenes--lookup-same-window)
(defvar diogenes--dict-xml-handlers-extra)

(defvar diogenes-dge--coverage-cache nil
  "Cached last entry of the dictionary: (STAMP KEY . HEADWORD).
STAMP identifies the file the answer was read from -- name, modification
time and size -- so a rebuilt dictionary is noticed without asking.  Read
by `diogenes-dge--coverage-limit', which is where this is explained, and
declared up here only because the builder clears it.")

;;;; --------------------------------------------------------------------
;;;; CUSTOMIZATION
;;;; --------------------------------------------------------------------

(defcustom diogenes-dge-file nil
  "Path to the converted DGE dictionary, one entry per line.
Nil means `dge.xml' among the other Diogenes dictionaries, which is where
\\[diogenes-dge-build-dictionary] writes it -- and where, on many
installations, it cannot: that directory lives inside the Diogenes tree and
is commonly owned by root.  Name a path you can write instead:

    (setq diogenes-dge-file \"/mnt/archive/Diogenes Data/Lexica/DGE/dge.xml\")

Missing directories are created.  The converted file is about 80 MB.  This
is NOT the TEI you downloaded -- see `diogenes-dge-source-file'."
  :type '(choice (const :tag "dge.xml beside the other dictionaries" nil)
                 file)
  :group 'diogenes)

(defcustom diogenes-dge-source-file nil
  "Where the DGE TEI XML lives, as distributed.
Read by \\[diogenes-dge-build-dictionary] to produce `diogenes-dge-file';
not used for lookups afterwards, so it may live anywhere and be deleted
once converted.

The TEI is one document per volume -- https://github.com/dge-csic/xdge_xml,
files xdge1.xml to xdge8.xml -- so this may be any of three things: a
single XML file, a DIRECTORY (every *.xml in it is read, in `string<' order
of file name), or an explicit list of files.  All of them go into the one
converted dictionary.

A directory that also holds the repository's other XML (monstre_css.xml,
monstre_xsl.xml) is no trouble: those carry no <entry> and contribute
nothing."
  :type '(choice (const :tag "Not set" nil)
                 (file :tag "Single XML file")
                 (directory :tag "Directory of XML files")
                 (repeat :tag "List of XML files" file))
  :group 'diogenes)

(defcustom diogenes-dge-display-in-same-window t
  "If non-nil, show a DGE entry in the window it was invoked from.
The LSJ entry you came from is not destroyed either way -- each lookup gets
a fresh buffer -- so with the default you stay in one window and can return
through the buffer history.  Nil lets `display-buffer' place it as it sees
fit."
  :type 'boolean
  :group 'diogenes)

(defcustom diogenes-dge-check-coverage t
  "If non-nil, refuse a word beyond the volumes the DGE has published.
The DGE is unfinished, and the last entry of the converted file is the
edge of what exists.  Beyond it `diogenes--search-dict' would show that
last entry as the nearest to, say, ὕβρις -- true, and useless.  With this
set, such a word gets a message naming the boundary instead.

Nil restores the plain behaviour of the other dictionaries: nearest entry,
with a message.  Turn it off if the check ever gets in your way; it costs
one short read of the tail of the dictionary, cached until the file
changes."
  :type 'boolean
  :group 'diogenes)

(defcustom diogenes-dge-etymology-label "Etim."
  "The label put on an entry's etymology when the dictionary is built.
The DGE sets its etymologies off by position alone -- last in the article,
after the final full stop -- which a printed column makes plain and a
reflowed paragraph does not: run on, the etymology of δελφίς reads as
though it were part of the last citation.  So <etym> is given a <sense> to
live in, and a <sense> is drawn with a blank line and a label.

The label is therefore OURS, not the CSIC's, and it is in Spanish because
the dictionary is.  Set it to \"Etym.\" if you would rather, or to
something wordless like \"◆\".  Takes effect at the next
\\[diogenes-dge-build-dictionary]."
  :type 'string
  :group 'diogenes)

(defcustom diogenes-dge-epichoric-substitutions
  '((?\uE1B0 . "ε") (?\uE1B3 . "ε") (?\uE1B4 . "ε")
    (?\uE1C0 . "ο") (?\uE1C3 . "ο") (?\uE1C4 . "ο")
    (?\uEB00 . "α"))
  "What a private-use character in a lemma is worth when keying it.
The DGE sets epigraphic letterforms in the private-use area of New Athena
Unicode; 38 lemmas contain one, and no beta-code table knows them, so
without this they drop out of the key and the word is filed a letter short.

Each of the seven here is vouched for by the DGE itself.  An entry's
`xml:id' is the project's normalisation of its own lemma, and it spells the
character out: the lemma διαιτατ<U+E1B4>ρ has `xml:id=\"διαιτατερ\"',
αἱλ<U+E1C3>τικός has `xml:id=\"αἱλοτικός\"'.  They are epichoric shapes of
E, O and A.

The fifteen other private-use characters in the dictionary occur only in
quoted text, never in a lemma, so nothing here depends on them and they are
left out rather than guessed at.  Add one if you identify it.

Applies to the KEY only.  The entry keeps its characters as published; to
see them, install New Athena Unicode."
  :type '(alist :key-type character :value-type string)
  :group 'diogenes)

(defcustom diogenes-dge-key-corrections
  '(("gelidoτρομερός" . "γελιδοτρομερός"))
  "Lemmas that are mistyped in the source, and what to key them under.
An alist of (LEMMA . READING), matched against the lemma with its markup
stripped and its edges trimmed.  Applies to the KEY only: the entry is
displayed as the CSIC published it.

The one shipped entry is an article of vol. IV whose stem was typed with
the Latin keymap and its ending with the Greek one -- g, e, l, i, d, o
stand on the keys of γ, ε, λ, ι, δ, ο.  The DGE prints it between Γελίας
and γελίκη, exactly where γελιδο- belongs, so the reading is certain even
though the word is otherwise unattested.  It also matters out of proportion
to its size: uncorrected, τρομερός is the only key in the dictionary
outside α-ἐπ, and `diogenes-dge--coverage-limit' would take it for the edge
of the published alphabet and pass every unwritten word from ζ to τ as
covered."
  :type '(alist :key-type string :value-type string)
  :group 'diogenes)

;;;; --------------------------------------------------------------------
;;;; FORMATTING OF THE DGE'S OWN ELEMENTS
;;;; --------------------------------------------------------------------

(defface diogenes-dge-def
  '((t :inherit bold))
  "A definition: the Spanish that translates the headword.
The DGE's <def>, and the thing a reader is looking for, so it is the one
element given weight rather than colour."
  :group 'diogenes-dict-faces)

(defface diogenes-dge-usg
  '((t :inherit font-lock-builtin-face))
  "A label placed on a sense: register, dialect, subject, construction.
The DGE's <usg> -- \"medic.\", \"fig.\", \"c. gen.\" -- which qualifies a
definition without being one."
  :group 'diogenes-dict-faces)

(defface diogenes-dge-num
  '((t :inherit success))
  "The number or letter of a sense, where it is printed in the text.
Sense numbers lifted into a <sense n=\"...\"> are drawn by the shared
formatter; this is for the <num> that stay where they are, inside a locus."
  :group 'diogenes-dict-faces)

(defconst diogenes-dge--xml-handlers
  '((def       . (font-lock-face diogenes-dge-def))
    (usg       . (font-lock-face diogenes-dge-usg))
    (num       . (font-lock-face diogenes-dge-num))
    (gramGrp   . (font-lock-face diogenes-dict-gram))
    (lbl       . (font-lock-face diogenes-dict-scope))
    (foreign   . (font-lock-face diogenes-dict-mentioned))
    (placeName . (font-lock-face diogenes-dict-scope))
    (date      . (font-lock-face diogenes-dict-scope))
    (del       . (font-lock-face diogenes-dict-note))
    (gloss     . (font-lock-face diogenes-dict-quote)))
  "Faces for the elements the DGE uses and the other dictionaries do not.
Added to `diogenes--dict-xml-handlers-extra' on load, without disturbing an
entry already there, so the LSJ and Lewis & Short keep their appearance.

The rest of what a DGE entry contains needs nothing: <quote>, <author>,
<title>, <biblScope>, <note>, <ref> and <etym> are coloured for every
converted dictionary in `diogenes-dict-tei-faces', <orth> among them --
which is right, since by the time the formatter sees the entry the only
<orth> left is a variant spelling, the lemma having become <head>.  <cit>,
<form>, <dictScrap> and <pc> are containers and punctuation, and <milestone>
is empty.")

(defun diogenes-dge--install-xml-handlers ()
  "Teach the dictionary formatter about the DGE's elements.  Idempotent."
  (dolist (handler diogenes-dge--xml-handlers)
    (unless (assq (car handler) diogenes--dict-xml-handlers-extra)
      (push handler diogenes--dict-xml-handlers-extra)))
  (diogenes-dict-install-faces))

;;;; --------------------------------------------------------------------
;;;; THE KEY A HEADWORD SORTS UNDER
;;;; --------------------------------------------------------------------

(defconst diogenes-dge--beta-letters "abgdevzhqiklmncoprstufxyw"
  "The letters a beta-code key may consist of, and nothing else.
`diogenes--beta-sort-function' looks every character up in
`diogenes--beta-code-alphabet' and SIGNALS on one it does not find, so one
character that is not a beta-code letter -- the `_' or `^' of a quantity,
the `(' of a breathing, whatever a transliteration table hands back for a
letter it does not know -- would not merely sort oddly but break every
search that walked past it.  Hence a key is filtered down to these, in this
order
\(alpha beta gamma delta epsilon digamma zeta eta theta ...), which is the
order Greek sorts in and not the order ASCII does.")

(defconst diogenes-dge--letter-folds
  '((?ς . ?σ) (?ϐ . ?β) (?ϑ . ?θ) (?ϕ . ?φ) (?ϰ . ?κ) (?ϱ . ?ρ) (?ϖ . ?π)
    (?ϴ . ?θ))
  "Alist folding variant letter shapes onto the plain letter.
Applied before transliteration, since `diogenes--utf8-to-beta' knows only
the plain letters and leaves anything else for the filter to discard.
Final sigma is the one that matters in the DGE; the others are here so that
a lemma copied from a font-conscious edition cannot go missing.")

(defun diogenes-dge--prepare (word)
  "Normalise WORD before it is keyed, and return it NFD-decomposed.
WORD is a lemma with its markup already stripped, or a headword arriving
from another dictionary.

A word with NO GREEK IN IT is taken for beta code and converted: LSJ
headwords arrive as e.g. \"a)ba/c\", and so does anything typed at the
prompt by a reader who has no Greek keymap to hand.  A word that has Greek
in it is left as it is -- which is not the same as testing for Latin
letters, because the DGE writes Latin letters INTO Greek words, the h of an
epigraphic heta and the u̯, y and w of a reconstruction, and \"hαγρατέρα\"
run through a beta-code table would come out under eta.  Those letters are
dropped later, by `diogenes-dge--key'.

Then: the corrections in `diogenes-dge-key-corrections'; the substitutions
in `diogenes-dge-epichoric-substitutions'; the sigla and the homograph
number the DGE prints before a lemma (†, *, \"1 \"), which have to go
before the next step or they would be taken for the word itself; and the
first word only, since a lemma may name a phrase (Ἀβώνου τεῖχος) and the
DGE files it under its first word.

Wrapped in `save-match-data': this does its own matching, and a caller that
has just located something with `string-match' would otherwise find its
`match-beginning' quietly redirected here."
  (save-match-data
    (let* ((word (string-trim (or word "")))
           (word (or (cdr (assoc word diogenes-dge-key-corrections)) word))
           (word (if (or (string-match-p "\\cg" word)
                         (not (fboundp 'diogenes--perseus-beta-to-utf8)))
                     word
                   (or (diogenes--perseus-beta-to-utf8 word) word)))
           (word (mapconcat (lambda (c)
                              (or (cdr (assq c
                                             diogenes-dge-epichoric-substitutions))
                                  (string c)))
                            word ""))
           ;; The sigla of a conjectural or suspect lemma, and the numeral
           ;; that distinguishes homographs, both stand before the word.
           (word (replace-regexp-in-string
                  "\\`[[:space:][:digit:]†*]+" "" word))
           (word (or (car (split-string word "[[:space:]]+" t)) "")))
      (ucs-normalize-NFD-string word))))

(defun diogenes-dge--key (headword)
  "Return the beta-code key HEADWORD is filed under.
`diogenes--beta-sort-function' compares keys after discarding everything
but ASCII letters, so a key must survive that: HEADWORD is normalised by
`diogenes-dge--prepare', its combining marks dropped -- accents,
breathings, the iota subscript, and the quantities the DGE prints on nearly
every other lemma (ἀγκῡροειδής), which live in precomposed characters that
no transliteration table lists -- everything that is not a Greek letter
discarded, its variant shapes folded, and what remains transliterated into
beta code and filtered down to `diogenes-dge--beta-letters'.

Discarding the non-Greek is what disposes of the brackets and hyphens of a
restored or bound form, the entities of an editorial supplement
\(δι&lt;αρ&gt;ρσιος), and above all the letters that are not in the Greek
alphabet at all: digamma, the epigraphic heta, the u̯, y and w of a
reconstruction.  That is how the DGE files them too, and the pages say so
-- Ϝέος among ἑο-, hαγρατέρα between Ἀγραστυών and ἀγραυλέω.  Note that it
must happen AFTER `diogenes-dge--prepare' has had its chance to read a
wholly Latin word as beta code, and BEFORE transliteration, which would
make Greek letters of them all.

Returns the empty string for a word with no Greek in it, which the caller
is expected to refuse rather than search for."
  (let ((out nil))
    (dolist (c (string-to-list (diogenes-dge--prepare headword)))
      (when (and (not (<= #x0300 c #x036f))      ; combining marks
                 (string-match-p "\\cg" (string c)))
        (let* ((c (downcase c))
               (folded (or (cdr (assq c diogenes-dge--letter-folds)) c)))
          (dolist (b (string-to-list
                      (downcase (diogenes--utf8-to-beta (string folded)))))
            (when (cl-find b diogenes-dge--beta-letters)
              (push b out))))))
    (apply #'string (nreverse out))))

(defun diogenes-dge--key< (a b)
  "Non-nil if key A sorts before key B, as the binary search expects.
Delegates to `diogenes--beta-sort-function', which returns `a' when A is
the greater, `b' when B is, and nil when they are equal; A precedes B
exactly when the answer is `b'.

Written this way rather than reimplemented so that the file this module
writes and the search that reads it can never disagree.  They must not:
the Greek alphabet and ASCII part company at ξ -- beta code `c', which
sorts after ν and before ο, but between b and d in ASCII -- so a dictionary
sorted by `string<' would send every binary search for a word from ο
onwards down the wrong half of the file, and the failure would look like
missing entries rather than a sorting bug."
  (eq 'b (diogenes--beta-sort-function a b)))

;;;; --------------------------------------------------------------------
;;;; REWRITING AN ENTRY
;;;; --------------------------------------------------------------------

(defconst diogenes-dge--language-codes
  '(("grc"  . "greek")
    ("spa"  . "spanish")
    ("lat"  . "latin")
    ;; Mistyped in the source, four times between them, and all four are
    ;; Latin beyond doubt: `laat' on "Africanus Minor"; `lang' on "a
    ;; breuis", beside a sibling <def xml:lang="lat">, on an "apophasis"
    ;; labelled `en lat.', and on the "astulosa" of an entry that calls
    ;; itself a transcription from Latin.
    ("laat" . "latin")
    ("lang" . "latin"))
  "How the DGE's `xml:lang' codes map onto the languages Diogenes knows.
A code that is not here keeps its `xml:lang' and is treated as English --
which is what happens to every code if this rewriting is skipped, since
`diogenes--dict-handle-elt' reads `lang' and nothing in Diogenes reads
`xml:lang'.  Only `greek' and `latin' actually do anything, being the two
languages a lookup can be made in; `spanish' is here to say positively that
the definitions are NOT Greek, so that `C-c C-c' on a Spanish word does not
go looking for it in the LSJ.")

(defun diogenes-dge--rewrite-senses (line)
  "Give the <sense> elements of LINE the shape the formatter wants.
A sense that opens with a <num> keeps its element and takes the number as
an `n' attribute, which the shared handler prints as a coloured label after
a blank line; the <num> itself is removed, so the number is not shown
twice.  A sense that does not becomes <seg>, which has no handler: the
DGE's unnumbered senses are continuations printed inside the sense they
belong to, and a blank line before each of them -- there are 77,769 --
would break every article into fragments.

Either way the sense's own attributes go: its `xml:id' names the sense in
the DGE's system (\"δελφίς_II1\") but nothing here displays it, and at
152,714 senses it is several megabytes of file.  The article keeps its own;
see `diogenes-dge--convert-buffer'.

Nesting is preserved by counting, closing tags being renamed only if their
opening tag was: senses nest three and four deep, and 31 unnumbered ones
contain a numbered one.  A number that is not plain text is left alone
rather than escaped into an attribute; there is none in the eight volumes,
but a future one is cheaper to leave than to repair.

The end of each tag is read out of the match BEFORE anything else is
matched, since the `string-match' that looks for a following <num>
overwrites the match data -- the same trap `diogenes-dict-flatten-hi'
documents at length -- and the pieces are collected in a list rather than
appended to a string, because ἐπί is 431 KB and would otherwise be copied
once per sense."
  (let ((pos 0) (stack nil) (parts nil))
    (while (string-match "<\\(/?\\)sense\\(?:[^>]*\\)>" line pos)
      (let ((tag-start (match-beginning 0))
            (tag-end (match-end 0))
            (closing (string= (match-string 1 line) "/")))
        (push (substring line pos tag-start) parts)
        (setq pos tag-end)
        (if closing
            (push (if (pop stack) "</sense>" "</seg>") parts)
          ;; A <num> immediately inside makes this a numbered sense.  It
          ;; has to begin exactly where the tag ended: a <num> found later
          ;; in the entry belongs to another element.
          (let* ((found (string-match "[[:space:]]*<num[^>]*>\\([^<&\"]*\\)</num>"
                                      line tag-end))
                 (num (and found
                           (= (match-beginning 0) tag-end)
                           (string-trim (match-string 1 line)))))
            (cond ((and num (not (string-empty-p num)))
                   (push (format "<sense n=\"%s\">" num) parts)
                   (push t stack)
                   (setq pos (match-end 0)))
                  (t
                   (push "<seg>" parts)
                   (push nil stack)))))))
    (push (substring line pos) parts)
    (apply #'concat (nreverse parts))))

(defun diogenes-dge--rewrite-entry (body)
  "Return BODY, the inside of one TEI <entry>, as the formatter wants it.
The rewritings the Commentary describes, less the <orth> that
`diogenes-dge--convert-buffer' has renamed already: the languages the
formatter actually reads, citations that are not drawn as links Diogenes
cannot follow, senses numbered and unnumbered told apart, and <hi> flattened
into elements a face table can key on."
  (let ((body body))
    (dolist (code diogenes-dge--language-codes)
      (setq body (replace-regexp-in-string
                  (concat "xml:lang=\"" (car code) "\"")
                  (concat "lang=\"" (cdr code) "\"")
                  body t t)))
    ;; Citations: a face, not a dead link.
    (setq body (replace-regexp-in-string "<bibl\\([ >]\\)" "<cit\\1" body))
    (setq body (replace-regexp-in-string "</bibl>" "</cit>" body t t))
    (setq body (diogenes-dge--rewrite-senses body))
    ;; The etymology, in a block of its own.  AFTER the senses have been
    ;; sorted out, or this <sense> -- which has no <num> to give up -- would
    ;; be turned into a <seg> and lose the blank line it was made for.  The
    ;; <etym> is kept INSIDE it rather than renamed, so the etymology also
    ;; keeps the face `diogenes-dict-tei-faces' gives it.
    (setq body (replace-regexp-in-string
                "<etym>" (concat "<sense n=\"" diogenes-dge-etymology-label
                                 "\"><etym>")
                body t t))
    (setq body (replace-regexp-in-string
                "</etym>" "</etym></sense>" body t t))
    ;; The DGE's own stylesheet renders a bare <hi> italic; say so, or
    ;; `diogenes-dict-flatten-hi' will drop the element as unrecognised.
    (setq body (replace-regexp-in-string "<hi>" "<hi rend=\"italic\">" body t t))
    (diogenes-dict-flatten-hi body)))

;;;; --------------------------------------------------------------------
;;;; BUILDING THE DICTIONARY FILE
;;;; --------------------------------------------------------------------

(defun diogenes-dge--dictionary-file ()
  "Return the path of the converted dictionary, whether or not it exists."
  (or diogenes-dge-file
      (file-name-concat (diogenes--perseus-path) "dge.xml")))

(defun diogenes-dge--nearest-existing-directory (dir)
  "Return the innermost existing directory at or above DIR.
The target directory is created on demand, so it is its nearest existing
ancestor whose writability decides whether the build can finish."
  (let ((dir (directory-file-name (expand-file-name dir))))
    (while (and (not (file-directory-p dir))
                (not (string= dir (directory-file-name
                                   (file-name-directory dir)))))
      (setq dir (directory-file-name (file-name-directory dir))))
    dir))

(defun diogenes-dge--assert-writable (target)
  "Signal a user-error unless TARGET can be written.
Asked BEFORE anything is converted.  The default location is inside the
Diogenes installation, which is usually owned by root, and the conversion
takes a minute or two over 112 MB of TEI: finding out at the end, with the
sorted result thrown away and only `Permission denied' to explain it, is a
poor trade for one call to `file-writable-p'."
  (unless (if (file-exists-p target)
              (file-writable-p target)
            (file-writable-p (diogenes-dge--nearest-existing-directory
                              (file-name-directory target))))
    (user-error "Cannot write %s -- no permission.  Set \
`diogenes-dge-file' to a path you own, e.g. (setq diogenes-dge-file \
\"~/.emacs.d/diogenes/dge.xml\")"
                (abbreviate-file-name target))))

(defun diogenes-dge--source-files (&optional source)
  "Return the list of TEI files to convert.
SOURCE defaults to `diogenes-dge-source-file' and may be a file, a
directory, or a list of files; see that variable.  Signals if it names
nothing readable, since the alternative is a silently empty dictionary."
  (let ((source (or source diogenes-dge-source-file)))
    (cond
     ((null source) nil)
     ((consp source)
      (or (seq-filter #'file-readable-p source)
          (user-error "None of the files in `diogenes-dge-source-file' \
can be read")))
     ((file-directory-p source)
      (or (directory-files source t "\\.xml\\'" nil)
          (user-error "No .xml files in %s" (abbreviate-file-name source))))
     ((file-readable-p source) (list source))
     (t (user-error "Cannot read the DGE source at %s"
                    (abbreviate-file-name source))))))

(defun diogenes-dge--convert-buffer ()
  "Convert the TEI in the current buffer to a list of (KEY . LINE).
Point is left at the end.  Returns (ENTRIES . SKIPPED), the entries in the
order the file gives them.

Each <entry> becomes one line: its <orth type=\"lemma\"> is renamed <head>
and told it is Greek, the rest is rewritten by
`diogenes-dge--rewrite-entry', newlines are folded to spaces so the
line-oriented binary search stays line-oriented, and a fresh opening tag is
written carrying the beta-code key.  The tag is fresh because
`diogenes--xml-key-fn' takes the FIRST `key=' it finds in the line; the
entry's `xml:id' is copied onto it, being the name of the article in the
DGE's own system, and the other attributes are dropped."
  (let ((rows nil)
        (skipped 0))
    (goto-char (point-min))
    (while (re-search-forward "<entry\\(?:[[:space:]][^>]*\\)?>" nil t)
      (let* ((attrs (match-string 0))
             (start (point))
             (end (save-excursion
                    (when (search-forward "</entry>" nil t)
                      (match-beginning 0)))))
        (if (null end)
            (cl-incf skipped)
          (let ((body (buffer-substring-no-properties start end))
                (id (and (string-match "xml:id=\"\\([^\"]*\\)\"" attrs)
                         (match-string 1 attrs))))
            (goto-char end)
            ;; Comments first: two of the twenty-six hold markup and a
            ;; stray ampersand, and one sits between <form> and the lemma.
            (setq body (replace-regexp-in-string "<!--\\(?:.\\|\n\\)*?-->"
                                                 "" body))
            (if (not (string-match
                      "<orth[^>]*type=\"lemma\"[^>]*>\\(\\(?:.\\|\n\\)*?\\)</orth>"
                      body))
                (cl-incf skipped)
              ;; Read the whole match out FIRST: anything that matches in
              ;; between would move these offsets and the <head> would be
              ;; spliced into the middle of the <orth> tag.
              (let* ((orth-start (match-beginning 0))
                     (orth-end (match-end 0))
                     (orth (match-string 1 body))
                     (plain (string-trim
                             (replace-regexp-in-string "<[^>]*>" "" orth)))
                     (key (diogenes-dge--key plain))
                     (line (concat (substring body 0 orth-start)
                                   "<head lang=\"greek\" type=\"lemma\">"
                                   orth "</head>"
                                   (substring body orth-end))))
                (if (string-empty-p key)
                    (cl-incf skipped)
                  (setq line (diogenes-dge--rewrite-entry line))
                  (setq line (replace-regexp-in-string
                              "[[:space:]]*\n[[:space:]]*" " " line))
                  (push (cons key
                              (format "<entry key=\"%s\"%s>%s</entry>"
                                      key
                                      (if id (format " xml:id=\"%s\"" id) "")
                                      (string-trim line)))
                        rows))))))))
    (cons (nreverse rows) skipped)))

;;;###autoload
(defun diogenes-dge-build-dictionary (&optional source target)
  "Convert the DGE TEI XML into a dictionary Diogenes can search.
SOURCE defaults to `diogenes-dge-source-file' -- a file, the directory of
per-volume files, or a list -- and TARGET to `diogenes-dge-file'.  Each
<entry> becomes one line, keyed in beta code by `diogenes-dge--key' and
sorted in Greek alphabetical order; see `diogenes-dge--convert-buffer' for
what else the conversion does.  Entries keep their printed order within a
key, so homographs stay in the sequence the DGE prints them in -- and
volumes read in file-name order stay in alphabetical order, which for this
dictionary is the same thing.

Run once, after setting `diogenes-dge-source-file'.  The eight volumes are
64,373 entries over 112 MB of TEI and take a minute or two; the result is
about 80 MB."
  (interactive)
  (let* ((sources (or (diogenes-dge--source-files source)
                      (list (read-file-name "DGE TEI XML (or directory): "
                                            nil nil t))))
         (sources (diogenes-dge--source-files sources))
         (target (or target (diogenes-dge--dictionary-file)))
         (rows nil)
         (skipped 0))
    (dolist (file sources)
      (when (and (file-exists-p target)
                 (string= (file-truename file) (file-truename target)))
        (user-error "Refusing to convert %s onto itself: \
`diogenes-dge-file' must differ from `diogenes-dge-source-file'"
                    (abbreviate-file-name file))))
    (diogenes-dge--assert-writable target)
    (dolist (file sources)
      (message "Converting %s ..." (file-name-nondirectory file))
      (with-temp-buffer
        (insert-file-contents file)
        (let ((result (diogenes-dge--convert-buffer)))
          (setq rows (nconc rows (car result)))
          (cl-incf skipped (cdr result)))))
    (unless rows
      (user-error "Found no entries in %s: is this the DGE TEI?"
                  (mapconcat #'file-name-nondirectory sources ", ")))
    ;; `sort' on a list is stable, so entries sharing a key keep the order
    ;; the dictionary prints them in.
    (message "Sorting %d entries ..." (length rows))
    (setq rows (sort rows (lambda (a b) (diogenes-dge--key< (car a) (car b)))))
    (make-directory (file-name-directory target) t)
    (let ((coding-system-for-write 'utf-8))
      (with-temp-file target
        (dolist (row rows)
          (insert (cdr row) "\n"))))
    (setq diogenes-dge--coverage-cache nil)
    (message "DGE: wrote %d entries (%s-%s) from %d file(s) to %s%s"
             (length rows) (car (car rows)) (car (car (last rows)))
             (length sources)
             (abbreviate-file-name target)
             (if (zerop skipped) "" (format "; skipped %d" skipped)))
    target))

;;;; --------------------------------------------------------------------
;;;; HOW FAR THE DICTIONARY GOES
;;;; --------------------------------------------------------------------

(defun diogenes-dge--last-entry-in-window (file from to)
  "Return (KEY . HEADWORD) from the last whole line of FILE between FROM and TO.
Nil if no line begins inside the window, which is the answer for a window
too small to hold the final entry -- DGE articles run to 431 KB -- and the
signal for the caller to widen it.  FROM and TO are byte offsets."
  (with-temp-buffer
    (let ((coding-system-for-read 'utf-8))
      (insert-file-contents file nil from to))
    (goto-char (point-max))
    (skip-chars-backward "\n")
    (beginning-of-line)
    ;; Unless the window starts at the head of the file, its own first line
    ;; is a fragment: a line only counts if a newline was seen before it.
    (when (or (zerop from) (> (point) (point-min)))
      (when (looking-at "<entry[[:space:]][^>]*key=\"\\([^\"]*\\)\"")
        (let* ((key (match-string 1))
               (head (save-excursion
                       (when (re-search-forward
                              "<head[^>]*>\\(.*?\\)</head>"
                              (line-end-position) t)
                         (string-trim
                          (replace-regexp-in-string
                           "<[^>]*>" "" (match-string 1)))))))
          (cons key (if (and head (not (string-empty-p head)))
                        head
                      (diogenes--beta-to-utf8 key))))))))

(defun diogenes-dge--coverage-limit (file)
  "Return (KEY . HEADWORD) of the last entry of FILE, or nil.
The edge of what the DGE has published, read from the dictionary rather
than written down here, so that a new volume needs nothing but a rebuild.
Cached until the file changes.

Read from the tail, in windows that double until a line begins inside one:
the entries are wildly uneven -- ἐπί alone is 431 KB -- so no single window
is both small enough to be cheap and large enough to be sure."
  (let* ((attrs (file-attributes file))
         (size (file-attribute-size attrs))
         (stamp (list (file-truename file)
                      (file-attribute-modification-time attrs)
                      size)))
    (if (equal (car-safe diogenes-dge--coverage-cache) stamp)
        (cdr diogenes-dge--coverage-cache)
      (let ((found nil))
        (cl-loop for window in '(65536 524288 2097152 8388608)
                 for from = (max 0 (- size window))
                 do (setq found (diogenes-dge--last-entry-in-window
                                 file from size))
                 until (or found (zerop from)))
        (setq diogenes-dge--coverage-cache (cons stamp found))
        found))))

(defun diogenes-dge--assert-covered (word key file)
  "Signal a user-error if KEY sorts beyond the last entry of FILE.
WORD is what the reader asked for, and appears in the message.  A no-op
unless `diogenes-dge-check-coverage' is set, or if the limit cannot be read
-- an unreadable tail is a reason to fall back on the ordinary nearest-entry
behaviour, not to refuse the lookup."
  (when diogenes-dge-check-coverage
    (let ((limit (diogenes-dge--coverage-limit file)))
      (when (and limit (diogenes-dge--key< (car limit) key))
        (user-error "The DGE reaches %s so far; \"%s\" is not written yet"
                    (cdr limit) word)))))

;;;; --------------------------------------------------------------------
;;;; THE LOOKUP
;;;; --------------------------------------------------------------------

(defun diogenes-dge--assert-converted (file)
  "Signal a user-error unless FILE is a converted DGE dictionary.
The lookup wants one entry per line, each with a `key' attribute; handed
the TEI file instead it would fail deep inside `diogenes--xml-key-fn' with
an unhelpful message.  `diogenes-dge-file' is the CONVERTED file; the TEI
belongs in `diogenes-dge-source-file'."
  (with-temp-buffer
    (insert-file-contents file nil 0 400)
    (goto-char (point-min))
    (unless (looking-at "<entry[^>]*[[:space:]]key=\"")
      (user-error "%s is not a converted DGE dictionary (it does not begin \
with an entry).  If this is the TEI file, set it as \
`diogenes-dge-source-file' instead and run \
M-x diogenes-dge-build-dictionary"
                  (abbreviate-file-name file)))))

;;;###autoload
(defun diogenes-dge-available-p ()
  "Non-nil if the DGE is here, or could be built without asking twice.
True when the converted dictionary exists, and also when it does not but
`diogenes-dge-source-file' names TEI that is there -- because then pressing
`d' offers to build it, which is a real destination for the link.  What the
CSIC publishes for nothing is exactly this XML, so there is no printed
companion and this is the whole of the DGE's availability.  Never signals:
`diogenes-path' may itself be unset, and this is asked while an entry is
being drawn."
  (let ((file (ignore-errors (diogenes-dge--dictionary-file))))
    (or (and file (file-readable-p file))
        (diogenes--source-usable-p diogenes-dge-source-file))))

(defun diogenes-dge--file ()
  "Return the converted dictionary file, building it if the user agrees.
Signals rather than returning nil when there is nothing to search: the DGE
has no PDF to fall back on, so a missing dictionary is the end of the road
and the error may as well say how to fix it."
  (let ((file (diogenes-dge--dictionary-file)))
    (cond
     ((file-readable-p file)
      (diogenes-dge--assert-converted file)
      file)
     ((and diogenes-dge-source-file
           (y-or-n-p (format "The DGE is not converted yet; build %s now? "
                             (abbreviate-file-name file))))
      (diogenes-dge-build-dictionary diogenes-dge-source-file file))
     (t
      (user-error "The DGE is not set up yet: set `diogenes-dge-source-file' \
to the TEI XML (a file, or the directory holding the per-volume files) and \
run M-x diogenes-dge-build-dictionary.  Either in your init file before \
Diogenes loads, or through M-x customize-variable")))))

(defun diogenes-dge-lookup-buffer-p ()
  "Non-nil if the current lookup buffer is showing the DGE.
Read from the buffer-local `diogenes--lookup-file', which records the
dictionary the entries were read from.  Used by
`diogenes--lookup-insert-dict-links' to offer \"[DGE]\" in an LSJ entry and
\"[LSJ]\" here, so the link always leads to another dictionary rather than
the one you are reading."
  (and (boundp 'diogenes--lookup-file)
       diogenes--lookup-file
       (let ((dge (diogenes-dge--dictionary-file)))
         (and (file-exists-p dge)
              (file-exists-p diogenes--lookup-file)
              (string= (file-truename diogenes--lookup-file)
                       (file-truename dge))))))

;;;###autoload
(defun diogenes-lookup-dge (&optional word)
  "Show the DGE's entry for WORD in a Diogenes lookup buffer.
Interactively, WORD defaults to the headword of the Greek entry at point;
with a prefix argument, prompt for it.  The entry behaves like any other
lookup: `C-c C-n' and `C-c C-p' walk the dictionary, `C-c C-c' on a Greek
word returns to the LSJ, and the print-dictionary banner opens Montanari,
the CGL, BDAG, Passow and the TGL.

The DGE is unfinished.  A word inside the published range that it has no
article for produces the nearest entry, with a message saying so, exactly
as the LSJ does; a word beyond the last volume is refused with a message
naming how far the dictionary reaches, since the nearest entry to ὕβρις
would be the last page of vol. VIII and no use to anybody.  See
`diogenes-dge-check-coverage'.

Requires a converted dictionary file; see
\\[diogenes-dge-build-dictionary]."
  (interactive
   (progn
     (diogenes--lookup-assert-lang "greek" "DGE")
     ;; Already here: `l' leads back to the LSJ.
     (when (and (not current-prefix-arg) (diogenes-dge-lookup-buffer-p))
       (user-error "This entry is the DGE already; `l' returns to the LSJ, \
`C-u d' looks up another word here"))
     (list (if current-prefix-arg
               (read-string "Look up in the DGE: ")
             (diogenes--lookup-current-headword)))))
  (let* ((word (string-trim (or word (diogenes--lookup-current-headword))))
         (file (diogenes-dge--file))
         (key (diogenes-dge--key word)))
    (when (string-empty-p key)
      (user-error "Nothing to look up in \"%s\"" word))
    (diogenes-dge--assert-covered word key file)
    (let ((diogenes--lookup-same-window diogenes-dge-display-in-same-window))
      (diogenes--search-dict key "greek"
                             #'diogenes--beta-sort-function
                             #'diogenes--xml-key-fn
                             file))))

;;;; --------------------------------------------------------------------
;;;; REGISTRATION
;;;; --------------------------------------------------------------------

(defun diogenes-dge--register ()
  "Announce the DGE to the lookup banner, on \\`d'.  Idempotent.
`:show unless-current', so the DGE is not offered inside the DGE; the way
back is the \"[LSJ]\" link `diogenes-pape.el' registers, which appears here
because `diogenes--lookup-own-dictionary-p' is false in a DGE buffer.

`d' is bound here and not shared with a Latin command, unlike `P' and `l':
Latin has nothing to put on it.  Pressed in a Latin entry, the command
declines through `diogenes--lookup-assert-lang'."
  (diogenes-lookup-register-dictionary
   'dge :lang "greek" :name "DGE" :key "d" :order 65
   :command #'diogenes-lookup-dge
   :show 'unless-current
   :buffer-p #'diogenes-dge-lookup-buffer-p
   :available-p #'diogenes-dge-available-p
   :bind t
   :help "Show the DGE's entry for \"%s\""))

(with-eval-after-load 'diogenes-perseus
  (diogenes-dge--install-xml-handlers)
  (diogenes-dge--register))

(provide 'diogenes-dge)
;;; diogenes-dge.el ends here
