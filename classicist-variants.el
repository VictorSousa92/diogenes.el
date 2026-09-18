;;; classicist-variants.el --- the spellings a word might be keyed under -*- lexical-binding: t; -*-

;; Copyright (C) 2024 Michael Neidhart
;; Copyright (C) 2026 Victor Gonçalves de Sousa
;;
;; Author: Victor Gonçalves de Sousa <victor.goncalves.sousa@alumni.usp.br>
;; Keywords: classics, philology

;; This program is free software; you can redistribute it and/or modify
;; it under the terms of the GNU General Public License as published by
;; the Free Software Foundation, either version 3 of the License, or
;; (at your option) any later version.

;; This program is distributed in the hope that it will be useful,
;; but WITHOUT ANY WARRANTY; without even the implied warranty of
;; MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
;; GNU General Public License for more details.

;; You should have received a copy of the GNU General Public License
;; along with this program.  If not, see <https://www.gnu.org/licenses/>.

;;; Commentary:

;; WHAT A DICTIONARY MIGHT HAVE CALLED IT.  A lexicon is keyed under one
;; spelling and a text may use another: `immitto' is `in-mitto' assimilated,
;; `coeo' is `con-eo' contracted, and a Greek form may be accented where the
;; lemma is not.  Nothing here decides anything -- every plausible spelling is
;; offered, likeliest first, and whoever holds the dictionary keeps the one it
;; actually has.
;;
;; THE BOTTOM OF THE STACK, and it reaches nothing.  Twenty-eight forms, of
;; which eleven are called from outside and seventeen are this module talking
;; to itself.  It compiles alone; `diogenes-perseus.el' requires it.
;;
;; The check that says so was wrong the first time.  A closure that strips
;; comments and not strings reported `--latin-assimilations' calling
;; `--assimilated-offset\=', which is a sentence in its docstring.

;;; Code:

(require 'cl-lib)
(require 'seq)
(require 'ucs-normalize)               ; ucs-normalize-NFD-string
(require 'diogenes-utils)              ; --strip-diacritics
(require 'diogenes-lisp-utils)         ; --ascii-alpha-only
(require 'classicist-groups)

(defgroup classicist-variants nil
  "What a dictionary might have called a word.
Latin assimilation and contraction, Greek accentuation, and the beta-code
stripping both need."
  :group 'classicist)


(defcustom classicist-latin-fold-letters '((?j . ?i))
  "Initial letters folded together when searching the Latin dictionary.
An alist of (FROM . TO) characters, applied to the FIRST letter of both the
search word and the dictionary key before they are compared.

The Lewis & Short that comes with Diogenes is ordered two ways at once,
depending on where the j falls.  An initial J is interleaved with I --

  I, J, Jabolenus, Iacchus, jacea, jaceo, Jacetani, ja^ci^o

which is alphabetical only if j counts as i -- while an internal j sorts
after i, as it does in print:

  abitus, abjecte, ... circumitus, circumjaceo, ... deitas, dejecte

so folding everywhere trades one set of inversions for another (measured on
the shipped file: 126 with no folding, 129 folding throughout, and fewest
folding the initial letter alone).  Hence the fold applies only to the
first letter.

The u/v distinction is NOT folded: this dictionary keeps separate U and V
sections.  Set this to nil to compare keys literally, as Diogenes\\=' own
`$do_lookup\\=' does -- at the cost of `iacio\\=' landing between the letter
articles and `jacio\\=' overshooting its whole block."
  :type '(alist :key-type character :value-type character)
  :group 'classicist-variants)


(defun classicist--latin-fold-key (str)
  "Reduce STR to the letters the Latin dictionary is ordered by.
ASCII letters only, downcased, with `classicist-latin-fold-letters' applied
to the initial letter."
  (let ((key (downcase (diogenes--ascii-alpha-only str))))
    (if (or (null classicist-latin-fold-letters)
	    (zerop (length key)))
	key
      (let ((folded (cdr (assq (aref key 0) classicist-latin-fold-letters))))
	(if folded
	    (concat (string folded) (substring key 1))
	  key)))))

(defun classicist--beta-drop-extra-accents (word)
  "WORD with every accent after the first removed.
A Greek word bears one accent of its own.  A second appears when an ENCLITIC
follows: a proparoxytone takes an extra acute on its ultima, so the text prints
`*bria/rew/n\=' where the analyses file has `*bria/rewn\=' -- and the search then
looks for a key that cannot exist, lands on whatever sorts next to it, and shows
that entry as though it had found something.  `Βριάρεών\=' answered with
`Βρίακχος\='.

The added accent is always the last, the rule putting it on the ultima, so the
first is the word\='s own and the rest come off."
  (let ((seen nil))
    (apply #'string
           (cl-loop for c across word
                    if (memq c '(?/ ?\\ ?=))
                    unless seen collect c and do (setq seen t)
                    end
                    else collect c))))


(defcustom classicist-latin-assimilate-prefixes t
  "Whether a hyphenated Latin lemma is retried with its prefix assimilated.
Morpheus writes a compound unassimilated, marking the morpheme boundary --
`in-mitto\=', `in-lido\=', `con-pello\=' -- where Lewis & Short keys the
assimilated form: `immitto\=', `illido\=', `compello\='.
`make_latin_analyses.pl\=' strips the lemma to its bare letters as a last
resort, which yields `inmitto\=', matches no key, and leaves the confidence
at 0 with the offset at wherever that spelling would sort -- `innabilis\=',
as it happens.

The hyphen says where the boundary falls, so the assimilated spellings can
be worked out and offered to the dictionary, and only the one it has a key
for is used.  Nothing is guessed: a spelling the dictionary does not
confirm is discarded."
  :type 'boolean
  :group 'classicist-variants)


(defconst classicist--latin-labials '(?p ?b ?m)
  "The letters before which a nasal is written m.")


(defcustom classicist-latin-prefix-variants
  '(("de" . "di") ("di" . "de"))
  "Prefixes the dictionary may key under a spelling other than Morpheus\\='s.
An alist of (LEMMA . DICTIONARY): the prefix as the analyses file writes it,
and the prefix to try instead when nothing else has matched a key.

This is not assimilation, which is a sound change the hyphen lets one work
out.  It is one prefix written two ways, the choice falling out differently
in the two sources: Morpheus has `de-rego\\=' and `de-rigo\\=' where Lewis &
Short keys `dirigo\\=', with derigo named inside the entry as the spelling
Roby and Ribbeck preferred and the manuscripts mostly print.  A reader
parsing any form of it -- `derigamus\\=' -- got no headword at all.

Each is tried last, after every spelling `classicist--latin-assimilations\\='
works out, so a compound the dictionary has under its own prefix is never
sent elsewhere: `de-duco\\=' finds `deduco\\=' and is not offered `diduco\\=',
which is another verb.  Only a spelling the dictionary confirms is used."
  :type '(alist :key-type (string :tag "Lemma prefix")
                :value-type (string :tag "Dictionary prefix"))
  :group 'classicist-variants)


(defun classicist--latin-assimilations (lemma)
  "The spellings a hyphenated LEMMA might be keyed under, likeliest first.
`in-mitto\=' gives `immitto\=' and `inmitto\='; `con-pello\=' gives `compello\=',
`conpello\=' and `coppello\='; `con-eo\=' gives `coeo\='.  Nothing is decided
here -- every candidate is offered, and `classicist--assimilated-offset\=' keeps
whichever the dictionary actually has."
  (let* ((clean (replace-regexp-in-string
		 "[_^+]" ""
		 (replace-regexp-in-string "#?[0-9]+\\'" "" lemma)))
	 ;; The analyses file writes some lemmata as FORM,LEMMA -- the accented
	 ;; form and then the lemma proper, `obsessi_s,ob-sedeo'.  Only the part
	 ;; after the comma is the compound to be assimilated: with the form
	 ;; still attached every candidate came out as `obsessi_s,obsideo', which
	 ;; is nobody's key, and the reader was shown `ob-septus' -- the entry
	 ;; that follows where `obsideo' would have been.
	 (clean (if (string-match ",\\([^,]*\\)\\'" clean)
		    (match-string 1 clean)
		  clean))
	 (parts (split-string clean "-" t)))
    (when (= 2 (length parts))
      (let* ((prefix (downcase (car parts)))
	     (stem (downcase (cadr parts)))
	     (final (and (> (length prefix) 0)
			 (aref prefix (1- (length prefix)))))
	     (initial (and (> (length stem) 0) (aref stem 0)))
	     (stub (substring prefix 0 (max 0 (1- (length prefix)))))
	     candidates)
	(when (and final initial)
	  ;; The compound simply run together comes FIRST, and deliberately.
	  ;; It is what make_latin_lemmata.pl assumes, and it costs nothing: a
	  ;; confidence of 0 means make_latin_analyses.pl already tried the
	  ;; letters-only spelling -- this very one -- and found no key, so it
	  ;; cannot match here either.  At a confidence of 2 it DOES match, and
	  ;; matching it returns the offset the build already chose, which
	  ;; leaves `re-tento\=' to the homograph sweep where it belongs.  Trying
	  ;; an assimilated spelling first would instead send `ad-sum\=' to
	  ;; `assum\=', roast meat, in preference to `adsum\='.
	  (push (concat prefix stem) candidates)
	  (when (memq final '(?n ?m ?d ?b ?s ?x))
	    (cond
	     ;; A nasal is written m before a labial: con+pello, in+mitto.
	     ((and (memq final '(?n ?m))
		   (memq initial classicist--latin-labials))
	      (push (concat stub "m" stem) candidates))
	     ;; Before a vowel the consonant drops: con+eo.
	     ((memq initial '(?a ?e ?i ?o ?u ?y))
	      (push (concat stub stem) candidates)))
	    ;; Total assimilation, which is what doubles the letter: in+lido,
	    ;; ad+sum, ob+fero, ex+fero.
	    (push (concat stub (string initial) stem) candidates)))
	;; `ex' loses its consonant before s: ex+surio is esurio, and likewise
	;; educo, evado, emitto.  Not the vowel rule above -- the stem begins
	;; with a consonant -- and without this `ex-surio' reaches no key and
	;; the reader is shown `exsurrectio', which is the next entry along.
	(when (and final (eq final ?x) initial)
	  (push (concat stub stem) candidates))
	;; And the stem's own first vowel weakens in composition: sedeo becomes
	;; -sideo, teneo -tineo, facio -ficio, capio -cipio, cado -cido.  So
	;; `ob-sedeo' is keyed `obsideo', and until this was offered the reader
	;; got `ob-septus'.  Offered LAST, being the least common of these, and
	;; harmless where it is wrong: a spelling the dictionary has not got
	;; costs one binary search.
	(when (and prefix stem (> (length stem) 0))
	  (let ((weakened (classicist--latin-weaken-stem stem)))
	    (when weakened
	      (push (concat prefix weakened) candidates)
	      ;; ...and with the prefix assimilated as well: ad+teneo is
	      ;; `attineo', both changes at once.
	      (when (and final initial (memq final '(?n ?m ?d ?b ?s ?x)))
		(push (concat stub (string (aref weakened 0)) weakened)
		      candidates)))))
	;; And the PREFIX itself may be spelt otherwise in the dictionary.
	;; Not an assimilation: de- and di- are one prefix written two ways,
	;; and the two spellings are distributed between Morpheus and Lewis
	;; & Short.  Morpheus writes `de-rego' and `de-rigo'; the dictionary
	;; keys the verb `dirigo' and mentions derigo only inside the entry.
	;; So no candidate above reached a key, the confidence stayed at 0,
	;; and every form of the commonest verb of its family -- `derigamus'
	;; -- printed the gap between `derelictio' and `deripio'.
	;;
	;; Offered after everything else, and so tried only where the
	;; dictionary has not got the compound under its own spelling:
	;; `de-duco' matches `deduco' first and never asks about `diduco',
	;; which is a different verb.
	(let ((alt (cdr (assoc prefix classicist-latin-prefix-variants))))
	  (when (and alt (> (length stem) 0))
	    (push (concat alt stem) candidates)
	    (let ((weakened (classicist--latin-weaken-stem stem)))
	      (when weakened
		(push (concat alt weakened) candidates)))))
	(nreverse (delete-dups candidates))))))


(defun classicist--latin-weaken-stem (stem)
  "STEM with its first vowel weakened to `i\=', or nil if nothing changes.
The vowel of a simple verb weakens when it becomes the second element of a
compound: sedeo/-sideo, teneo/-tineo, facio/-ficio, capio/-cipio,
cado/-cido, salio/-silio, statuo/-stituo.  So a lemma Morpheus writes
`ob-sedeo\=' is keyed in the dictionary as `obsideo\='.

Only a first-syllable `a\=' or `e\=' is touched, and only where a consonant
follows it, which is where the change occurs.  Returns nil when there is
nothing to do, so the caller can tell a real candidate from a repetition."
  (when (and stem (> (length stem) 1))
    (let ((i 0) (len (length stem)))
      ;; Past any initial consonants to the first vowel.
      (while (and (< i len)
		  (not (memq (aref stem i) '(?a ?e ?i ?o ?u ?y))))
	(setq i (1+ i)))
      (when (and (< i len)
		 (memq (aref stem i) '(?a ?e))
		 ;; A consonant must follow: this is a closed syllable's vowel,
		 ;; not a hiatus.
		 (< (1+ i) len)
		 (not (memq (aref stem (1+ i)) '(?a ?e ?i ?o ?u ?y))))
	(concat (substring stem 0 i) "i" (substring stem (1+ i)))))))


(defcustom classicist-latin-try-spelling-variants t
  "Whether a Latin form that will not parse is retried under other spellings.
The wordlists Morpheus was run over do not agree with every text a reader
copies from, in three ways.

They spell consonantal i as i -- there are 108 j-initial forms in the whole
of `latin-analyses.txt\=' -- so a form written `jacio\=' is not a key in it at
all.  They spell consonantal u as v, so `ualdissime\=' is likewise absent.
And the cruncher assimilated a nasal before a consonant only sometimes: it
produced `quendam\=' and `quandam\=', but `quorumdam\=' where every text
prints `quorundam\='.

Either way the parse fails and falls through to a headword search, which
cannot help: an inflected form is nobody\='s dictionary headword, so
`quorundam\=' landed on `quorsum\='.  Trying the other spelling finds the
record, and with it the offset of the right entry.

The form as typed is always tried first, so a form that parses costs
nothing.  Set to nil to try only what the user typed, as Diogenes\=' own
`$do_parse\=' does."
  :type 'boolean
  :group 'classicist-variants)


(defconst classicist--latin-vowels '(?a ?e ?i ?o ?u ?y)
  "The letters that count as vowels when reading a spelling.")


(defun classicist--latin-swap-letters (word from to)
  "Replace every FROM in WORD with TO, in upper case as well as lower.
For the swaps that need no judgement: every j in a Latin word stands for
the consonant, and so does every v, so they can be rewritten wholesale as
i and u."
  (concat (mapcar (lambda (c)
		    (cond ((eq c from) to)
			  ((eq c (upcase from)) (upcase to))
			  (t c)))
		  word)))


(defun classicist--latin-swap-at (word positions mask from to)
  "WORD with the POSITIONS picked out by MASK rewritten from FROM to TO."
  (let ((variant (copy-sequence word)))
    (cl-loop for bit from 0
	     for i in positions
	     unless (zerop (logand mask (ash 1 bit)))
	     do (aset variant i (if (eq (aref variant i) (upcase from))
				    (upcase to)
				  to)))
    variant))


(defun classicist--latin-positional-swaps (word from to predicate &optional cap)
  "Spellings of WORD with some of its FROMs, where PREDICATE holds, written TO.
PREDICATE is called with the character following the candidate.  Rewriting
every occurrence gives nonsense -- `iacio\=' would become `jacjo\=', `seruus\='
`servvs\=' -- so each combination of the qualifying positions is returned
instead, at most CAP of them considered (four by default)."
  (let* ((positions (cl-loop for i from 0 below (max 0 (1- (length word)))
			     when (and (eq (downcase (aref word i)) from)
				       (funcall predicate
						(downcase (aref word (1+ i)))))
			     collect i))
	 (positions (seq-take positions (or cap 4))))
    (cl-loop for mask from 1 to (1- (ash 1 (length positions)))
	     collect (classicist--latin-swap-at word positions mask from to))))


(defun classicist--latin-vowel-p (char)
  "Whether CHAR is a vowel."
  (memq char classicist--latin-vowels))


(defun classicist--latin-consonant-p (char)
  "Whether CHAR is a letter and not a vowel."
  (and (>= char ?a) (<= char ?z) (not (memq char classicist--latin-vowels))))


(defun classicist--latin-exs-variants (word)
  "Spellings of WORD with an s inserted or dropped after an initial ex.
Editions differ over the prefix: `exstruo\=' and `extruo\=', `exspecto\=' and
`expecto\=', `exstinguo\=' and `extinguo\=', `exsisto\=' and `existo\='.  The
wordlists carry one of the pair and not the other -- `exstruxit\=' is there,
`extruxit\=' is not, so a text printing the shorter form parsed as nothing
and fell through to a headword search that landed on `extrudo\='.

The s is only meaningful before a consonant: `exeo\=' and `exsul\=' are not
alternatives of one another."
  (let ((case-fold-search nil))
    (cond
     ((string-match "\\`\\([Ee]\\)xs\\([bcdfglmnpqrstv]\\)" word)
      (list (concat (match-string 1 word) "x"
		    (substring word (match-beginning 2)))))
     ;; No s in this class: the s of `exsul\=' is the word's own, and adding
     ;; another would only ask the dictionary about `exssul\='.
     ((string-match "\\`\\([Ee]\\)x\\([bcdfglmnpqrtv]\\)" word)
      (list (concat (match-string 1 word) "xs"
		    (substring word (match-beginning 2))))))))


(defun classicist--latin-genitive-plural-variants (word)
  "Spellings of WORD with the other third-declension genitive plural ending.
`aedium\=' and `aedum\=' are both the genitive plural of `aedes\=', and the
wordlists have the second: `aedum\=' is recorded at confidence 9 against
`aedes\=', `aedium\=' not at all, so the commoner of the two forms parsed as
nothing and fell through to `aedon\=', the nightingale.

Nothing here decides whether a word IS a genitive plural -- a noun in -um
gets an -ium candidate whether it could bear one or not.  That costs one
binary search on a form that would have failed anyway, and only an exact
match counts, so a candidate like `bellium\=' is looked for and not found."
  (cond
   ((string-suffix-p "ium" word)
    (list (concat (substring word 0 -3) "um")))
   ((string-suffix-p "um" word)
    (list (concat (substring word 0 -2) "ium")))))


(defcustom classicist-latin-spelling-rules
  '(classicist--latin-exs-variants
    classicist--latin-genitive-plural-variants)
  "Functions producing further spellings of a Latin form that will not parse.
Each is called with a form and returns a list of alternatives, or nil.
Unlike the letter swaps `classicist--latin-form-variants\=' applies, these are
insertions and endings rather than substitutions, so each needs a rule of
its own.

Add to this to cover a variation of your own texts: a function here is
tried against every spelling the letter swaps produce, and its answers are
looked for in the analyses file like any other."
  :type '(repeat function)
  :group 'classicist-variants)


(defun classicist--latin-form-variants (word)
  "Spelling variants of WORD to try in the analyses file, WORD first.
Three conventions the wordlists and the texts disagree over are applied in
turn -- i/j, u/v, and a nasal before a consonant -- so a form ambiguous on
more than one count is covered.  See `classicist-latin-try-spelling-variants\='."
  (if (not classicist-latin-try-spelling-variants)
      (list word)
    (let ((variants (list word)))
      (dolist (axis
	       ;; Each axis: the wholesale swap, then the positional one.
	       '((?j ?i ?i ?j classicist--latin-vowel-p)
		 (?v ?u ?u ?v classicist--latin-vowel-p)
		 ;; A nasal before a consonant, either way about: the cruncher
		 ;; wrote `quorumdam\=' but `quendam\='.
		 (nil nil ?n ?m classicist--latin-consonant-p)
		 (nil nil ?m ?n classicist--latin-consonant-p)))
	(seq-let (from to pos-from pos-to predicate) axis
	  (setq variants
		(cl-loop
		 for v in variants
		 append (append (list v)
				 (when from
				   (list (classicist--latin-swap-letters v from to)))
				 (classicist--latin-positional-swaps
				  v pos-from pos-to predicate))))))
      ;; The rules go last, and over everything the swaps produced, so that a
      ;; form needing both -- `exstruxit\=' typed with a u for its v, say --
      ;; is still reached.
      (dolist (rule classicist-latin-spelling-rules)
	(setq variants
	      (append variants
		      (cl-loop for v in variants
			       append (ignore-errors (funcall rule v))))))
      (delete-dups variants))))


(defcustom classicist-latin-expand-contractions t
  "Whether a circumflex in a Latin form is read as a contraction.
The editions the corpora print do not mark quantity, so a circumflex in
them is not decoration: it marks a contracted syllable, the vowel standing
for the two it was made from.  `desîmus' is `desiimus', `dî' is `dii'.
Non-nil reads it that way.

The distinction decides which word you are shown, because both spellings
can be keys.  `desîmus' is the syncopated perfect of `desino', while
`desimus' without the mark is a key too -- the present subjunctive of
`dēsum' -- and a text that meant that verb would not have printed the
circumflex.  Strip the mark as though it said nothing and the answer is
confidently the wrong verb.

Nil treats a circumflex like any other mark, to be removed."
  :type 'boolean
  :group 'classicist-variants)


(defun classicist--latin-expand-contractions (word)
  "WORD with each circumflexed vowel written as the pair it stands for.
Returns nil when WORD carries no circumflex, so a caller can tell the
expansion from the form itself.  Works on the decomposition, so a
precomposed `î' and an `i' followed by a combining circumflex are treated
alike, and any other marks are left for `diogenes--strip-diacritics'."
  (let ((out nil)
        (found nil))
    (dolist (c (string-to-list (ucs-normalize-NFD-string (or word ""))))
      (if (= c ?\N{COMBINING CIRCUMFLEX ACCENT})
          ;; The mark says the letter just read stands for two of itself.
          (when out
            (push (car out) out)
            (setq found t))
        (push c out)))
    (and found (apply #'string (nreverse out)))))


(defun classicist--latin-parse-candidates (word)
  "The spellings of Latin WORD to look for in the analyses file, in order.
The file is keyed by bare ASCII forms, while the corpora print what their
editors chose, so a form as printed may be no key at all.  Three spellings,
each tried only if it differs from those before it:

  WORD itself, which is the whole of the matter for an unmarked form;

  WORD with its circumflexes read as contractions -- `desîmus' as
  `desiimus', which is in the file, under `desino'.  This is the reading
  that matters, the texts marking no quantities: a circumflex in them says
  the syllable is contracted.  It comes BEFORE the stripped spelling
  because `desimus' is a key as well, for the present subjunctive of
  `dēsum', and a text meaning that verb would not have printed the mark.
  See `classicist-latin-expand-contractions';

  WORD with every mark removed.  Last, and for two things the corpora do
  not produce: a contraction whose expansion is not a form -- `nîl' gives
  `niil', which is nothing, where the bare `nil' is a key -- and a word
  from somewhere else, typed into the minibuffer with macrons or copied
  from a dictionary headword.

Normalisation, not guesswork, so this is not one of
`classicist-latin-spelling-rules' and not subject to
`classicist-latin-try-spelling-variants': i-for-j is a convention two sources
disagree about, where these are the same word written as an editor prints
it and as a wordlist keys it."
  (let* ((expanded (and classicist-latin-expand-contractions
                        (classicist--latin-expand-contractions word)))
         (candidates (list word
                           (and expanded (diogenes--strip-diacritics expanded))
                           (diogenes--strip-diacritics word))))
    (delete-dups (delq nil candidates))))


(defun classicist--beta-drop-capital-marker (word)
  "WORD without the leading asterisk beta code marks a capital with.
`Εὐφήμει\=' is `*eu)fh/mei\=', and the analyses file keeps proper names under the
asterisk and everything else without it -- so a word capitalised only because
it opens a sentence is looked for among the names and not found.

The asterisk sits before the letter and before its breathing, so removing it is
removing the first character; nothing else moves."
  (if (and (> (length word) 1) (eq (aref word 0) ?*))
      (substring word 1)
    word))


(defun classicist--greek-parse-candidates (word)
  "The Greek forms to try for WORD, in order.

WORD as it stands first: nothing that parses today may stop parsing, and a
genuine proper name -- `Εὐφράτης\=', which the file really does keep under the
asterisk -- must find itself before anything else is tried.

Then, on a miss:

  * without the CAPITAL MARKER, for a word capitalised because it opens a
    sentence.  Latin has had this since Diogenes\=' own \"Fixed parsing of
    capitalized Latin words\"; Greek had not, and `Εὐφήμει\=' answered with
    `εὐφαής\=' -- the nearest name in `*eu)-\=' -- where `εὐφήμει\=' finds
    `εὐφημέω\='.  See `classicist--beta-drop-capital-marker\='.

  * without the accent an ENCLITIC added, where the form carries more than
    one.  See `classicist--beta-drop-extra-accents\='.

  * and without either, since a capitalised word may also carry an enclitic\='s
    accent.

`delete-dups\=' in the caller removes the repetitions this leaves when a form
needs only one of the two."
  (let* ((plain (classicist--beta-drop-capital-marker word))
         (dropped (classicist--beta-drop-extra-accents word))
         (both (classicist--beta-drop-extra-accents plain)))
    (delete-dups (list word plain dropped both))))


(defun classicist--greek-accent-variants (word)
  "WORD in beta code with its accent moved, every way it might sit.

The accent is stripped and then put back on each vowel in turn -- acute,
grave and circumflex -- because a Greek word carries one accent and an
editor\='s may not be the wordlist\='s: Ross prints `mu=on\=' where the file has
`mu/on\='.

The BREATHINGS and the iota subscript are left as they stand.  They are part
of the spelling, not of the accentuation: `a)nh/r\=' and `a(nh/r\=' are
different words, where `a)nh/r\=' and `a)nh=r\=' are one word differently
accented.

The form as given is not among them, its own spelling having been tried
already."
  (let* ((bare (replace-regexp-in-string "[/\\\\=]" "" (or word "")))
         (out nil))
    (dotimes (i (length bare))
      (when (memq (aref bare i) '(?a ?e ?i ?o ?u ?h ?w))
        ;; AFTER THE BREATHING, which beta code writes between the vowel and
        ;; the accent: `a)/nhr\=' and not `a/)nhr\='.  Putting the accent
        ;; straight after the vowel made a spelling no wordlist can hold, and
        ;; so six lookups that could not match.
        (let ((at (1+ i)))
          (while (and (< at (length bare))
                      (memq (aref bare at) '(?\) ?\()))
            (setq at (1+ at)))
          (dolist (accent '("/" "\\\\" "="))
            (push (concat (substring bare 0 at)
                          accent
                          (substring bare at))
                  out)))))
    (delete word (nreverse out))))


(defcustom classicist-latin-extra-lemmata nil
  "Forms Morpheus does not analyse, and the headword to look up instead.
An alist of (FORM . HEADWORD), consulted only when a form will not parse at
all, and before falling back on a search for the form itself.

Diogenes\=' analyses are a batch run of Morpheus over wordlists harvested
from the corpora it indexes, so a form those wordlists missed is missing
altogether -- not misspelt, which
`classicist-latin-try-spelling-variants\=' would cover, but absent.  The gaps
are not random: `illidant\=', the present subjunctive of `illido\=', whose
fourteen other forms are all there; `aedium\=', where the wordlists have only
the rarer `aedum\='; `transilire\='.  Each parsed as nothing and fell through
to a search for itself, which found the nearest headword instead --
`illico\=', `aedon\=' the nightingale, `transilis\='.

HEADWORD is a headword, not an offset, so an entry here survives a rebuild
of the Perseus data.  Matching ignores case and the spelling conventions,
so one entry answers for `ualdissime\=' as well as `valdissime\='.

Consulted AFTER the parse, never instead of it: a form Morpheus does know
keeps its own analysis, and an entry here for such a form is simply never
reached.  A serious accumulation of these is an argument for running
Morpheus itself over the form -- it generates paradigms rather than
harvesting a corpus -- rather than for a longer alist."
  :type '(alist :key-type (string :tag "Form")
		:value-type (string :tag "Headword"))
  :group 'classicist-variants)


(defcustom classicist-latin-mark-corrections t
  "Whether a corrected analysis is marked as corrected.
Non-nil appends \" [corr.]\" to any morphology that
`classicist-latin-analysis-corrections' has altered or added, so that what
you are reading is never silently other than what the shipped data says.
Nil prints the correction as though it came from the file."
  :type 'boolean
  :group 'classicist-variants)


(defcustom classicist-latin-analysis-corrections nil
  "Corrections to the morphology the analyses file records for a Latin form.
An alist of (FORM . PLIST).  FORM is the form as `latin-analyses.txt' keys
it -- bare ASCII, which is what a contraction or an accented spelling has
been resolved to by the time this is consulted.  PLIST takes:

  :info STRING     -- the morphology to print instead, for every analysis
                      of FORM.
  :info ALIST      -- ((OLD . NEW) ...), replacing only the analyses whose
                      morphology is OLD.  For a form with several analyses
                      of which one is wrong.
  :lemma STRING    -- the headword to print instead, for every analysis of
                      FORM.  Where Morpheus has the morphology of one word
                      and the lemma of another: `superstite' is the ablative
                      of `superstes', analysed from `super-sto'.  The entry
                      the dictionary keys open follows the corrected lemma,
                      the file's byte offset being dropped with it.
  :add ENTRIES     -- ((LEMMA . INFO) ...), further analyses to show after
                      those the file gives.  LEMMA nil means the lemma the
                      file already names, so a missing reading of the same
                      word is added without repeating its headword; a
                      string is a headword, whose entry is fetched and
                      shown alongside.

For example, where the batch run of Morpheus over the wordlists labels the
deponent's imperative an active infinitive:

    (setq classicist-latin-analysis-corrections
          \\='((\"experire\" :info \"pres imperat pass 2nd sg\")))

or, where both the lemma and the morphology are wrong:

    (setq classicist-latin-analysis-corrections
          \\='((\"superstite\" :lemma \"superstes\" :info \"abl sg\")))

or, to keep the file's reading and add the missing one:

    (setq classicist-latin-analysis-corrections
          \\='((\"experire\" :add ((nil . \"pres imperat pass 2nd sg\")))))

This is for a form the file analyses WRONGLY.  A form it does not analyse
at all is `classicist-latin-extra-lemmata'; a form whose spelling the file
does not use is normalised before it gets here -- see
`classicist--latin-parse-candidates' -- and neither is a correction.

A long list here is an argument for reporting the analyses upstream rather
than for maintaining it: the data is a batch run of Morpheus, so a
systematic error in it is one error, not a hundred."
  :type '(alist :key-type (string :tag "Form")
                :value-type (sexp :tag "Plist"))
  :group 'classicist-variants)

(provide 'classicist-variants)

;;; classicist-variants.el ends here
